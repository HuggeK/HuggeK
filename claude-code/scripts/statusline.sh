#!/usr/bin/env bash
set -euo pipefail

# statusline.sh — claude-carbon status line, de-OAuth'd fork.
# Reads Claude Code status JSON from stdin, outputs CO2 + usage status line.
#
# CHANGES vs upstream claude-carbon:
#   * Removed the Anthropic OAuth fallback (no token read, no api.anthropic.com call).
#     5h / weekly usage now come ONLY from rate_limits.* in the statusline stdin —
#     if this Claude Code version doesn't inject them, those segments are omitted.
#   * Added a weekly (seven_day) usage segment in the same style as the 5h one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORS_FILE="${SCRIPT_DIR}/../data/factors.json"

# Read stdin
INPUT="$(cat)"

# Extract fields with defaults to avoid failures on null
MODEL_ID="$(echo "$INPUT" | jq -r '.model.id // ""')"
DISPLAY_NAME="$(echo "$INPUT" | jq -r '.model.display_name // "Unknown model"' | sed -E 's/ *\((1M|200K) context\)//')"
INPUT_TOKENS="$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0')"
OUTPUT_TOKENS="$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')"
COST_USD="$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')"
USED_PCT="$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')"
CURRENT_DIR="$(echo "$INPUT" | jq -r '.workspace.current_dir // ""')"
TRANSCRIPT="$(echo "$INPUT" | jq -r '.transcript_path // ""')"

# Project name = last path segment
PROJECT="$(basename "$CURRENT_DIR")"

# Resolve model family
MODEL_FAMILY="sonnet"
if echo "$MODEL_ID" | grep -qiE "fable|mythos"; then
  MODEL_FAMILY="fable"
elif echo "$MODEL_ID" | grep -qi "opus"; then
  MODEL_FAMILY="opus"
elif echo "$MODEL_ID" | grep -qi "haiku"; then
  MODEL_FAMILY="haiku"
fi

# Load emission factors (zero for non-Anthropic models, e.g. local models
# behind ANTHROPIC_BASE_URL — a datacenter factor doesn't apply to them)
if echo "$MODEL_ID" | grep -qi "claude"; then
  FACTOR_IN="$(jq -r ".models.${MODEL_FAMILY}.input // 39" "$FACTORS_FILE")"
  FACTOR_OUT="$(jq -r ".models.${MODEL_FAMILY}.output // 826" "$FACTORS_FILE")"
else
  FACTOR_IN="0"
  FACTOR_OUT="0"
fi

# Calculate CO2 in grams: (input * factor_in + output * factor_out) / 1_000_000
CO2_G="$(echo "$INPUT_TOKENS $FACTOR_IN $OUTPUT_TOKENS $FACTOR_OUT" | LC_ALL=C awk '{printf "%.0f", ($1 * $2 + $3 * $4) / 1000000}')"

# Format CO2 with adaptive unit
if [ "$CO2_G" -ge 1000 ] 2>/dev/null; then
  CO2_DISPLAY="$(echo "$CO2_G" | LC_ALL=C awk '{printf "%.1fkg", $1/1000}') CO₂"
else
  CO2_DISPLAY="${CO2_G}g CO₂"
fi

# Round cost to 2 decimals
COST_DISPLAY="$(echo "$COST_USD" | LC_ALL=C awk '{printf "%.2f", $1}')"

# Build progress bar (10 blocks)
FILLED=$(( USED_PCT * 10 / 100 ))
EMPTY=$(( 10 - FILLED ))
PROGRESS_BAR=""
for ((i=0; i<FILLED; i++)); do PROGRESS_BAR="${PROGRESS_BAR}▓"; done
for ((i=0; i<EMPTY; i++)); do PROGRESS_BAR="${PROGRESS_BAR}░"; done

# Color dot and percentage display
if [ "$USED_PCT" -ge 80 ]; then
  DOT="🔴"
  PCT_DISPLAY="COMPACT!"
elif [ "$USED_PCT" -ge 60 ]; then
  DOT="🟡"
  PCT_DISPLAY="${USED_PCT}%"
else
  DOT="🟢"
  PCT_DISPLAY="${USED_PCT}%"
fi

# --- Usage segments (5h + weekly), stdin-only, network-free. ---
# Parse a reset timestamp (epoch number OR ISO-8601) into a "+%s" epoch.
to_epoch() {
  local v="$1"
  [ -z "$v" ] && return 0
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$v"
  else
    local t="${v%%.*}"; t="${t%%Z}"; t="${t%%+*}"
    date -j -u -f "%Y-%m-%dT%H:%M:%S" "$t" "+%s" 2>/dev/null \
      || date -d "$v" "+%s" 2>/dev/null || echo ""
  fi
}
# Format an epoch into local time with the given strftime format.
fmt_local() {
  local e="$1" f="$2"
  [ -z "$e" ] && return 0
  date -r "$e" "+$f" 2>/dev/null || date -d "@$e" "+$f" 2>/dev/null || echo ""
}
# Build " | <label> <pct>% ↻<reset>" from a raw pct + reset stamp.
build_seg() {
  local label="$1" pct_raw="$2" reset="$3" rfmt="$4"
  [ -z "$pct_raw" ] && return 0
  local pct; pct="$(echo "$pct_raw" | LC_ALL=C awk '{printf "%.0f", $1}')"
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  local ep rl=""
  ep="$(to_epoch "$reset")"
  [ -n "$ep" ] && rl="$(fmt_local "$ep" "$rfmt")"
  if [ -n "$rl" ]; then
    printf ' | %s %s%% ↻ %s' "$label" "$pct" "$rl"
  else
    printf ' | %s %s%%' "$label" "$pct"
  fi
}

USAGE_SEGMENT=""
WEEK_SEGMENT=""
if command -v jq &>/dev/null; then
  FIVE_PCT="$(echo "$INPUT"   | jq -r '.rate_limits.five_hour.used_percentage // empty')"
  FIVE_RESET="$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty')"
  # Weekly key is unconfirmed for this CLI version — try the likely candidates.
  WEEK_PCT="$(echo "$INPUT"   | jq -r '.rate_limits.seven_day.used_percentage // .rate_limits.weekly.used_percentage // .rate_limits.seven_day.utilization // empty')"
  WEEK_RESET="$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // .rate_limits.weekly.resets_at // empty')"

  USAGE_SEGMENT="$(build_seg "Use" "$FIVE_PCT" "$FIVE_RESET" "%H:%M")"
  WEEK_SEGMENT="$(build_seg "Wk"  "$WEEK_PCT"  "$WEEK_RESET" "%a %H:%M")"
fi

# --- Effort level indicator: 5 dots (low→medium→high→xhigh→max). ---
# Current level = larger ringed dot (◉); the rest small dots (•), dash-joined.
# No text label — the ring marks the level. NB: .effort.level never reports
# "ultracode" (it resolves to "xhigh"), so there is no 6th dot to light.
EFFORT_SEGMENT=""
EFFORT_RAW="$(echo "$INPUT" | jq -r '(.effort | objects | .level) // (.effort | strings) // empty' | tr '[:upper:]' '[:lower:]')"
if [ -n "$EFFORT_RAW" ]; then
  case "$EFFORT_RAW" in
    low|1)                                             EFF_IDX=1 ;;
    medium|med|2)                                      EFF_IDX=2 ;;
    high|3)                                            EFF_IDX=3 ;;
    xhigh|extrahigh|extra_high|extra-high|ultracode|4) EFF_IDX=4 ;;
    max|maximum|5)                                     EFF_IDX=5 ;;
    *)                                                 EFF_IDX=0 ;;
  esac
  EFF_DOTS=""
  for s in 1 2 3 4 5; do
    if [ "$s" -eq "$EFF_IDX" ]; then dot="◉"; else dot="•"; fi
    if [ -z "$EFF_DOTS" ]; then EFF_DOTS="$dot"; else EFF_DOTS="${EFF_DOTS}–${dot}"; fi
  done
  EFFORT_BODY="Eff ${EFF_DOTS}"
  # max → purple (ANSI 256-colour 141)
  [ "$EFF_IDX" -eq 5 ] && EFFORT_BODY=$'\033[38;5;141m'"Eff ${EFF_DOTS}"$'\033[0m'
  EFFORT_SEGMENT=" | ${EFFORT_BODY}"
fi

# --- Running workflow / subagent activity (on-disk, mtime-based). ---
# The statusline stdin carries NO task/workflow field, but subagents journal to
# <session>/subagents/... and workflows to <session>/subagents/workflows/<run>/.
# Session dir = transcript_path with the .jsonl suffix stripped. A journal whose
# mtime is within FRESH_S seconds means that work is still running.
WF_SEGMENT=""
if [ -n "$TRANSCRIPT" ]; then
  SDIR="${TRANSCRIPT%.jsonl}"
  if [ -d "$SDIR/subagents" ]; then
    FRESH_S=8
    now="$(date +%s)"
    fresh_wf=0; fresh_ag=0
    # Workflow agents (under .../subagents/workflows/<run>/agent-*.jsonl)
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      m="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
      [ "$(( now - m ))" -le "$FRESH_S" ] && fresh_wf=$(( fresh_wf + 1 ))
    done < <(find "$SDIR/subagents/workflows" -name 'agent-*.jsonl' 2>/dev/null)
    # Plain /agent subagents (directly under subagents/, not the workflows subtree)
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      m="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
      [ "$(( now - m ))" -le "$FRESH_S" ] && fresh_ag=$(( fresh_ag + 1 ))
    done < <(find "$SDIR/subagents" -maxdepth 1 -name 'agent-*.jsonl' 2>/dev/null)
    if [ "$fresh_wf" -gt 0 ]; then
      WF_SEGMENT=$' | \033[38;5;141m⚙ wf×'"${fresh_wf}"$'\033[0m'   # purple, like max
    elif [ "$fresh_ag" -gt 0 ]; then
      WF_SEGMENT=" | ⚙ ag×${fresh_ag}"
    fi
  fi
fi

# Git branch (if in a git repo)
BRANCH_SUFFIX=""
if [ -n "$CURRENT_DIR" ] && command -v git &>/dev/null; then
  BRANCH="$(git -C "$CURRENT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ] && BRANCH_SUFFIX=" ⌥ ${BRANCH}"
fi

echo "${PROJECT}${BRANCH_SUFFIX} | ${DOT} ${DISPLAY_NAME} ${PROGRESS_BAR} ${PCT_DISPLAY}${EFFORT_SEGMENT} | \$${COST_DISPLAY} · ${CO2_DISPLAY}${USAGE_SEGMENT}${WEEK_SEGMENT}${WF_SEGMENT}"
