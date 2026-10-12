# OpenFlight session handoff

Context from a Claude Code cloud session (2026-10-12) about the **open-flight/openflight** repo
(https://github.com/open-flight/openflight). Read this first, then pick up the open items at the end.
Everything below was checked against `main` at commit `8d681d0`, the merge base of both PRs.

---

## 1. Dependabot PR review

### open-flight/openflight#291: npm minor/patch group (13 updates)
- Only touches `ui/package.json` and `ui/package-lock.json`.
- The main bumps are vite 8.2.2→8.3.4, eslint 10.8.1→10.12.0, electron 44.1.0→44.7.0,
  typescript-eslint 8.67→8.71.1, @playwright/test 1.62.1→1.64.0, socket.io/socket.io-client →4.8.4,
  @types/node, prettier, tsx, globals, @vitejs/plugin-react and eslint-plugin-react-refresh.
- I ran `npm ci`, `npm run build`, `npm run lint`, `npm run format:check` and `vitest` (246 tests).
  All passed.
- `npm audit` drops from 16 to 14 vulnerabilities (high: 8→6) compared with `main`.
- The lockfile resolves to `electron@44.7.0`. The `dependency-version: 44.5.1` in the commit-message
  metadata is stale from an earlier revision and only cosmetic.
- **Verdict:** safe to merge. The one gap is that CI never launches Electron (see section 2).

### open-flight/openflight#253: React group (4 updates)
- react, react-dom, @types/react and @types/react-dom go from 19.2.x to 19.3.0.
  There is a single copy of React (zustand dedupes onto it).
- Build, lint, format and vitest all pass.
- **Production JS bundle grows about 29 KB:** 361 KB → 390 KB, or 106 → 115 KB gzipped.
  The growth is in React itself, not app code.
- **Verdict:** OK if the bundle growth is acceptable. Click through the UI quickly, since it's a React minor bump.

### Interaction between the two
- They **conflict in `ui/package.json`** because they edit neighbouring lines. Merge #291 first,
  then comment `@dependabot rebase` on #253 rather than resolving by hand.
- Neither PR fixes the existing high/critical audit findings (e.g. `ws` pulled in via `engine.io-client`).
  `npm audit fix` would be a separate PR.
- An older issue unrelated to the PRs: `@eslint/js` is still `^9.39.1` while `eslint` is `^10`.
  Lint passes, but `@eslint/js` should be bumped to v10 at some point.
- Not checked: the e2e Playwright tests (they need the Python backend) and GitHub CI status
  (the session had no API access to that repo).

---

## 2. Electron 44.1.0 → 44.7.0: what changed and why it matters

### How OpenFlight uses Electron
`ui/electron/main.js` (41 lines) creates one `BrowserWindow` with `kiosk: true`, `fullscreen`,
`contextIsolation: true` and `sandbox: true`. It sets no menu, denies popups through
`setWindowOpenHandler`, and calls `loadURL()` on the target URL. That URL is `OPENFLIGHT_URL`, then
argv[2], then the default `http://localhost:8080`. The splash page loads first and then the app.
`scripts/start-kiosk.sh` launches it. `docs/electron-kiosk-shell.md` explains the design but still
says `electron@44.1.0`, so it needs updating after #291.

### Release summary
| Version | Highlights |
|---|---|
| 44.1.1 | Fixes an intermittent **Linux startup crash** (Pango/fontconfig race) and several `contextBridge` crashes |
| 44.2.0 | Chromium 152.0.7977.76, Node 24.20. Fixes a crash after very many IPC messages |
| 44.3.0 | Chromium 152.0.7977.78 and some security tightening (below) |
| 44.4.0–44.4.5 | Chromium 152.0.7977.130, Node 24.21. **Fixes a crash when `loadURL()` is called again right after a failed load.** Several UAF/lifetime fixes |
| 44.5.0/44.5.1 | About 35 fixes, many for Linux: GPU startup crash, Wayland/X11 window fixes, idle clipboard lag, frameless borders |
| 44.6.0 | macOS launch crash, tzdata 2026d, experimental `protocol.registerSource()` |
| 44.7.0 | `net.fetch` crash fix, more Chromium/V8 security backports |

- No release is labelled a security advisory, but nearly every one carries Chromium/V8/ANGLE security backports.
- 44.3.0 changed behaviour for `<webview>` IPC, popups, `getUserMedia` desktop capture,
  `nodeIntegrationInWorker` and permissions from subframes. **OpenFlight uses none of these.**
- Fixes that may help OpenFlight: the `loadURL()`-after-failure crash, because the splash page hands off
  to the app, plus the Linux startup and GPU crash fixes.

### Recommended manual smoke test on the Pi
Run `scripts/start-kiosk.sh` and confirm three things: the window opens fullscreen with no menu, the
splash page hands off to the app, and `target="_blank"` links are still blocked.

Sources:
- https://github.com/electron/electron/releases?q=v44&expanded=true
- https://github.com/electron/electron/releases?q=v44&expanded=true&page=2

---

## 3. Memory use and headroom for a "4GB+ Pi" recommendation

The repo documents no measurements. `docs/get-started/parts.md:14` only says
"Raspberry Pi 5 … 4GB+ recommended".

### What I measured (x86 container, not a Pi)
Mock backend plus the built UI loaded in Playwright's Chromium (same engine as Electron) at 1280×720.
I used **PSS** because summing RSS double-counts Chromium's shared memory: RSS gave about 710 MB for
Chromium against 290 MB PSS.

| Component | PSS, steady over 60 s |
|---|---|
| Python server (`openflight-server --mock`) | ~130 MB |
| UI in Chromium | ~290 MB |
| **Total** | **~420 MB** |

### Estimated from the code, not measured
- **Camera capture:** the rolling buffer is 150 ms before and 50 ms after the trigger
  (`src/openflight/camera/capture_runtime.py:60-61`). At 576 fps and 640×400 grayscale that's about
  115 frames, or about 30 MB. Loading a clip (`server.py` `_load_camera_capture_archive`) and replay
  encoding add copies, so peaks may reach about 100 MB plus FFmpeg. `camera/replay.py` already limits
  encodes to one at a time with a semaphore.
- **Radar processing:** bounded queues (`server.py:177-190`), probably tens of MB.
- **Pi OS with desktop:** a few hundred MB. Not measured.

### Conclusion
OpenFlight probably uses **about 0.5–0.8 GB**, or **about 1–1.2 GB with the OS**. A 4 GB Pi 5 leaves
roughly 3 GB free, so 4 GB is comfortable. 2 GB is likely workable but tight during camera replays.

Caveats: these figures come from x86, headless, no GPU and no real radar. The Pi 5's 16 KB page size
inflates memory somewhat. I measured for only 60 s, so a slow leak would not show up.

### How to get real numbers on a Pi
After about an hour of shots with the camera enabled, run this, then repeat it hours later to check for growth:
```bash
for p in $(pgrep -f 'openflight-server|electron'); do grep -H '^Pss:' /proc/$p/smaps_rollup; done; free -m
```

### Measurement script I used (to reproduce on a desktop)
The backend was started with `uv sync --python 3.12 && uv run openflight-server --mock`. It listens
on :8080 and ignored `--port`. The UI was built with `cd ui && npm ci && npm run build`, and the
server serves `ui/dist`.
```js
// mem.mjs — run with: node mem.mjs   (adjust the import path and executablePath)
import { chromium } from './ui/node_modules/@playwright/test/index.mjs';
import { execSync } from 'child_process';
const pss = (re) => {
  const out = execSync(`for p in $(pgrep -f '${re}'); do grep -m1 '^Pss:' /proc/$p/smaps_rollup 2>/dev/null; done`).toString();
  return ((out.match(/\d+/g) || []).reduce((a, b) => a + +b, 0) / 1024) | 0;
};
const report = () => `chromium PSS ${pss('chromium')} MB, server PSS ${pss('venv/bin/openflight-server')} MB`;
const b = await chromium.launch(/* { executablePath: '/path/to/chromium' } */);
const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
await p.goto('http://localhost:8080');
await p.waitForTimeout(5000);  console.log('t=5s', report());
await p.waitForTimeout(55000); console.log('t=60s', report());
await b.close();
```

---

## 4. Running the UI locally without a Pi

Frontend only, which needs Node ≥ 22.12 and no Python or hardware:
```bash
git clone https://github.com/open-flight/openflight
cd openflight/ui
npm install
npm run dev:mock      # Vite + Node Socket.IO mock on :8080
```
Open http://localhost:5173 and press **Simulate** to generate shots.

With the real Python backend in mock mode, which needs `uv`:
```bash
scripts/start-kiosk.sh --mock        # from repo root
cd ui && npm install && npm run dev
```
See `ui/README.md` for details.

---

## 5. Open items
- [ ] Merge #291, have Dependabot rebase #253, then merge #253 if the +29 KB bundle growth is OK.
- [ ] Smoke-test the Electron kiosk on a Pi after #291 (section 2).
- [ ] Update `docs/electron-kiosk-shell.md`, which still says `electron@44.1.0`.
- [ ] Bump `@eslint/js` to v10 to match `eslint`.
- [ ] Consider a separate `npm audit fix` PR (`ws` via `engine.io-client`, among others).
- [ ] Measure memory on a real Pi 5 (section 3). Optionally document the result next to the
      "4GB+ recommended" line in `docs/get-started/parts.md`.
