---
name: verify-milk-tea-kingdom
description: Drive the milk-tea-kingdom Godot HTML5 Web build (or live Pages) like a player: boot through Chinese loading states into the main HUD, check stations/upgrades, capture screenshots. Use when proving Web load, HUD, layout, or upgrade clicks for this Idle game.
---

# verify-milk-tea-kingdom

Godot 4 Web idle game. The playable surface is a **canvas** (no reliable ARIA). Agents drive it with a desktop browser: wait for visible Chinese copy, screenshot, click by layout. Never treat HTTP 200 or a changed `?v=` alone as pass.

## Launch

Prefer a **local** `build/web` so IndexedDB and cache do not collide with the public Pages session.

```bash
cd /path/to/milk-tea-kingdom
export VERIFY_RUN_ID=$$
export VERIFY_PORT=8765
.cursor/skills/verify-milk-tea-kingdom/scripts/launch-local-web.sh
# expect: READY_URL=http://127.0.0.1:8765/index.html
```

Ready means `index.html` returns 200 **and** the browser can fetch `index.wasm` + `index.pck`. The game is usable only after the boot overlay reaches the main HUD (title **奶茶王国**).

**Live Pages (phone / Lando Safari only for final gate):**  
`https://sumo91.github.io/milk-tea-kingdom/?v=<shortsha>` from `tools/web_deploy_tip.sh`. Do not use Pages for parallel agent drives; share state.

**Desktop editor (optional):** Godot 4.7+ F5 on `scenes/main.tscn` — not the Web proof path.

Teardown: `.cursor/skills/verify-milk-tea-kingdom/scripts/cleanup.sh "$PIDFILE"` (kills only the server you started). **Keep** files under `artifacts/verify/`.

## Doctor

```bash
.cursor/skills/verify-milk-tea-kingdom/scripts/doctor.sh "$READY_URL"
```

Requires: HTML/JS/wasm/pck HTTP 200; HTML must **not** force `ensureCrossOriginIsolationHeaders=true` (project keeps COI false).

If doctor fails, do not drive.

## Drive

Harness: **box/desktop browser** (computerUse) or equivalent. Canvas → no ARIA; use visual proof.

1. Open `$READY_URL` (hard refresh / empty cache when checking a new export).
2. Boot overlay (system font, from `web/shell.html`): expect sequence when network is slow enough to see:
   - `下载资源… NN%` and `x.x / y.y MB` climbing
   - `加载游戏…`
   - `马上好…`
3. Main HUD pass criteria (from `tools/web_smoke_checklist.txt`): visible **奶茶王国**, three stations **茶园 / 调制台 / 摊位**, upgrade list. Stuck Godot splash without Chinese progress = fail.
4. Optional: portrait width ~390 — content fills width (no large side gutters).
5. Optional: click one upgrade row once; gold/levels should change on a second screenshot.

Store evidence under `artifacts/verify/<feature-id>/` (repo root).

## Evidence

- Screenshots: boot (if caught), HUD, after-action.
- Note wall-clock seconds from open → HUD.
- Console: no hard errors preferred; log if present.
- Proof standards: real boot path only; do not stub Engine; do not assert only tip sha.

## Cleanup

```bash
.cursor/skills/verify-milk-tea-kingdom/scripts/cleanup.sh /tmp/milk-tea-verify-$VERIFY_RUN_ID.pid
```

Never `pkill -f http.server` by name. Do not delete `artifacts/verify/`.

## Helpers

| Script | Role |
| --- | --- |
| `scripts/launch-local-web.sh` | Serve `build/web` on `VERIFY_PORT` |
| `scripts/doctor.sh` | Read-only asset + COI check |
| `scripts/cleanup.sh` | Kill launched server by pidfile |

Also read `tools/web_smoke_checklist.txt` and `tools/web_deploy_tip.sh` for deploy tip shape.

## Feature map

See `features/README.md`.
