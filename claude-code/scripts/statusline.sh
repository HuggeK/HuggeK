#!/usr/bin/env bash
set -euo pipefail

# statusline.sh — claude-carbon status line, de-OAuth'd fork.
# Reads Claude Code status JSON from stdin, outputs CO2 + usage status line.
# Usage: ... | statusline.sh             (full status line)
#        ... | statusline.sh --segment   (cost + CO2 only, for embedding in
#        another status line, e.g. a ccstatusline custom command widget)
#
# CHANGES vs upstream claude-carbon:
#   * Removed the Anthropic OAuth fallback (no token read, no api.anthropic.com call).
#     5h / weekly usage now come ONLY from rate_limits.* in the statusline stdin —
#     if this Claude Code version doesn't inject them, those segments are omitted.
#   * Added a weekly (seven_day) usage segment in the same style as the 5h one.
#   * Added effort-dots, workflow/subagent activity, and init-dir segments.
#   * State paths derive from SCRIPT_DIR (the fork is not a plugin install), with
#     CLAUDE_CARBON_DB / CLAUDE_CONFIG_DIR as overrides.
#   * Upstream's monthly /carbon-card nudge is NOT pulled in: the skill isn't
#     installed here, and it writes state from the statusline (this fork keeps
#     the statusline read-only).
#
# PULLED IN from upstream (v1.5.x line, 2026-08):
#   * Cumulative CO2 from carbon.db (session row written by a Stop hook), with the
#     context-window estimate as fallback. DORMANT until persist-session.sh is
#     wired as a Stop hook — the fallback is a snapshot of the current context and
#     understates long agentic sessions.
#   * --segment mode.
#   * 🔥 over-pace warning on the 5h segment (on pace to hit 100% before reset).
#   * "Update available" notice read from update-check.json (network-free here).
#   * Install-drift check vs the newest marketplace plugin cache (self-skips
#     when no marketplace install exists).

SEGMENT_MODE=0
[ "${1:-}" = "--segment" ] && SEGMENT_MODE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARBON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FACTORS_FILE="${CARBON_DIR}/data/factors.json"
DB_PATH="${CLAUDE_CARBON_DB:-${CARBON_DIR}/carbon.db}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$(cd "${CARBON_DIR}/.." && pwd)}"

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
# Directory the session was initialized in (project root). Unlike current_dir,
# this stays put when the cwd moves (e.g. into a worktree). Fall back to cwd.
INIT_DIR="$(echo "$INPUT" | jq -r '.workspace.project_dir // .cwd // ""')"
TRANSCRIPT="$(echo "$INPUT" | jq -r '.transcript_path // ""')"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // ""')"

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

# CO2 in grams. Preferred source: this session's row in carbon.db, written by the
# Stop hook (persist-session.sh) at the end of every turn. That figure is
# CUMULATIVE and carries the full token breakdown (cache reads, subagents), so it
# sits on the same time base as the cost next to it. It lags by at most one turn.
#
# Fallback: the context-window estimate, used until a row exists (first turn, no
# Stop hook wired, or DB absent). That figure is a SNAPSHOT of the current
# context, not a session total — it drops back on every compaction and
# understates a long agentic session by orders of magnitude.
CO2_G=""
if [ -n "$SESSION_ID" ] && [ -f "$DB_PATH" ] && command -v sqlite3 >/dev/null 2>&1; then
  SESSION_ID_SQL="${SESSION_ID//\'/\'\'}"
  CO2_G="$(sqlite3 -cmd ".timeout 300" "$DB_PATH" "SELECT printf('%.0f', co2_grams) FROM sessions WHERE session_id='${SESSION_ID_SQL}' AND COALESCE(excluded, 0) = 0 AND co2_grams > 0;" 2>/dev/null || true)"
  case "$CO2_G" in ''|*[!0-9]*) CO2_G="" ;; esac
fi
if [ -z "$CO2_G" ]; then
  CO2_G="$(echo "$INPUT_TOKENS $FACTOR_IN $OUTPUT_TOKENS $FACTOR_OUT" | LC_ALL=C awk '{printf "%.0f", ($1 * $2 + $3 * $4) / 1000000}')"
fi

# Format CO2 with adaptive unit
if [ "$CO2_G" -ge 1000 ] 2>/dev/null; then
  CO2_DISPLAY="$(echo "$CO2_G" | LC_ALL=C awk '{printf "%.1fkg", $1/1000}') CO₂"
else
  CO2_DISPLAY="${CO2_G}g CO₂"
fi

# Round cost to 2 decimals
COST_DISPLAY="$(echo "$COST_USD" | LC_ALL=C awk '{printf "%.2f", $1}')"

# Segment mode stops here: no progress bar, no git call. The host status line
# owns the rest.
if [ "$SEGMENT_MODE" = "1" ]; then
  echo "\$${COST_DISPLAY} · ${CO2_DISPLAY}"
  exit 0
fi

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

  # 🔥 pace warning: past 15% of the 5h block AND on pace to hit 100% before the
  # reset. The block start is reconstructed as reset - 5h; the first 15 minutes
  # are ignored (a fresh block always projects hot).
  WARN=""
  if [ -n "$FIVE_PCT" ]; then
    FIVE_INT="$(echo "$FIVE_PCT" | LC_ALL=C awk '{printf "%.0f", $1}')"
    END_EPOCH="$(to_epoch "$FIVE_RESET")"
    if [ -n "$END_EPOCH" ] && [ "$FIVE_INT" -ge 15 ] 2>/dev/null; then
      NOW_EPOCH="$(date +%s)"
      ELAPSED_SEC=$(( NOW_EPOCH - (END_EPOCH - 18000) ))
      if [ "$ELAPSED_SEC" -gt 900 ]; then
        HOT="$(echo "$FIVE_PCT $ELAPSED_SEC" | LC_ALL=C awk '{print (($1 * 18000 / $2) >= 100) ? "1" : "0"}')"
        [ "$HOT" = "1" ] && WARN="🔥 "
      fi
    fi
  fi

  USAGE_SEGMENT="$(build_seg "${WARN}Use" "$FIVE_PCT" "$FIVE_RESET" "%H:%M")"
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

# Name of the directory the session was initialized in (leaf folder only).
# Just the basename keeps the line readable when the cwd moves into a deep
# worktree path. Handles both / and \ path separators.
INIT_SEGMENT=""
if [ -n "$INIT_DIR" ]; then
  INIT_NAME="${INIT_DIR//\\//}"   # normalize Windows backslashes to forward slashes
  INIT_NAME="${INIT_NAME%/}"       # drop any trailing slash
  INIT_NAME="${INIT_NAME##*/}"     # keep the last path component
  [ -n "$INIT_NAME" ] && INIT_SEGMENT=" | 📁 ${INIT_NAME}"
fi

# Git branch (if in a git repo)
BRANCH_SUFFIX=""
if [ -n "$CURRENT_DIR" ] && command -v git &>/dev/null; then
  BRANCH="$(git -C "$CURRENT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ] && BRANCH_SUFFIX=" ⌥ ${BRANCH}"
fi

# "Update available" notice — read-only, network-free. The remote check runs in
# the background (check-update.sh, launched by a SessionStart hook when wired)
# and writes a cached flag; here we only read it. A 7-day staleness gate means an
# abandoned flag (background check stopped) self-clears. Dormant on this install
# until the fork is a git clone with a version to compare.
UPDATE_SEGMENT=""
UPD_FILE="${CARBON_DIR}/update-check.json"
if [ -z "${CLAUDE_CARBON_NO_UPDATE_NOTIFIER:-}" ] && [ -f "$UPD_FILE" ] && command -v jq &>/dev/null; then
  # One jq call for the three fields: this runs on every turn, so each spawn is felt.
  UPD_BEHIND=""; UPD_AT=0; UPD_REMOTE=""
  IFS="$(printf '\t')" read -r UPD_BEHIND UPD_AT UPD_REMOTE <<EOF
$(jq -r '[(.behind // false), (.checked_at // 0), (.remote // "")] | @tsv' "$UPD_FILE" 2>/dev/null)
EOF
  if [ "$UPD_BEHIND" = "true" ] && [ "${UPD_AT:-0}" -gt 0 ] 2>/dev/null && [ "$(( $(date +%s) - UPD_AT ))" -lt 604800 ] 2>/dev/null; then
    # Naming the target version turns "something changed" into a judgeable call.
    # This fork updates via scripts/update.sh, not the /carbon-update skill.
    UPDATE_SEGMENT=" | ⬆ ${UPD_REMOTE:+${UPD_REMOTE} }update.sh"
  fi
fi

# Install-sync check — local-only, two cmp calls, no state file. Only matters on
# machines that ALSO carry a marketplace install of claude-carbon whose hooks
# write carbon.db: a stale plugin cache would silently persist with outdated
# factors while this copy runs green. Compares this install's factors/prices
# against the newest cached plugin copy. Fast path: one cmp per file, no spawn
# when the bytes match. Only when they differ does a jq pass strip the
# "_"-prefixed documentation keys, so a docs-only edit never flags while any
# value difference still does. Self-skips when no marketplace cache exists.
DRIFT_SEGMENT=""
# drift_values_differ <a> <b>: 0 when the two JSON files disagree once every
# "_"-prefixed key (at any depth) is removed; 1 when they agree. Without jq, any
# byte difference counts.
drift_values_differ() {
  command -v jq &>/dev/null || return 0
  local A B
  A="$(jq -S 'walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)' "$1" 2>/dev/null)" || return 0
  B="$(jq -S 'walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)' "$2" 2>/dev/null)" || return 0
  [ "$A" != "$B" ]
}
if [ -z "${CLAUDE_CARBON_NO_DRIFT_CHECK:-}" ] && printf '1.0\n1.0.1\n' | sort -V >/dev/null 2>&1; then
  CACHE_LATEST=""
  for D in "${CONFIG_DIR}/plugins/cache"/*/claude-carbon/*/; do
    [ -d "$D" ] || continue
    if [ -z "$CACHE_LATEST" ] || [ "$(printf '%s\n%s\n' "$CACHE_LATEST" "$D" | sort -V | tail -1)" = "$D" ]; then
      CACHE_LATEST="$D"
    fi
  done
  if [ -n "$CACHE_LATEST" ]; then
    OWN_ROOT="$CARBON_DIR"
    CACHE_ROOT="$(cd "$CACHE_LATEST" 2>/dev/null && pwd || echo "")"
    if [ -n "$OWN_ROOT" ] && [ -n "$CACHE_ROOT" ] && [ "$OWN_ROOT" != "$CACHE_ROOT" ]; then
      for F in data/factors.json data/prices.json; do
        if [ -f "${CACHE_ROOT}/${F}" ] && [ -f "${OWN_ROOT}/${F}" ] \
           && ! cmp -s "${CACHE_ROOT}/${F}" "${OWN_ROOT}/${F}" \
           && drift_values_differ "${CACHE_ROOT}/${F}" "${OWN_ROOT}/${F}"; then
          DRIFT_SEGMENT=" | ≠ install drift"
          break
        fi
      done
    fi
  fi
fi

echo "${PROJECT}${BRANCH_SUFFIX}${INIT_SEGMENT} | ${DOT} ${DISPLAY_NAME} ${PROGRESS_BAR} ${PCT_DISPLAY}${EFFORT_SEGMENT} | \$${COST_DISPLAY} · ${CO2_DISPLAY}${USAGE_SEGMENT}${WEEK_SEGMENT}${WF_SEGMENT}${UPDATE_SEGMENT}${DRIFT_SEGMENT}"
