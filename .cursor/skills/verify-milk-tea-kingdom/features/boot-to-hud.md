# Boot to HUD

Player opens the Web build, sees Chinese download/load copy with progress, then lands on the main idle HUD.

## Sub-features

- `boot-progress` shows `下载资源…` with percent and MB while wasm/pck download.
- `boot-compile` shows `加载游戏…` / `马上好…` after download.
- `boot-hud` reaches main HUD (title + stations).

## How to get to it (user POV)

- Open local `index.html` from a fresh verification server.
- Or open Pages URL with tip `?v=` after hard refresh / new tab.

## Driving it with desktop browser

Preconditions:

- `doctor.sh` passed on `$READY_URL`.
- Browser tab opened for this run only.

- **Open.** Navigate to `$READY_URL`. Prefer hard reload.
- **Watch overlay.** Screenshot when `下载资源` / MB visible if timing allows.
- **Wait HUD.** Poll until canvas shows **奶茶王国** (timeout suggest 120s on slow links; local often ~15–60s).
- **Proof.** Save `artifacts/verify/boot-to-hud/hud.png` and note seconds. Fail if stuck on English Godot splash with no Chinese progress for >15s with no MB movement.

## Gotchas

- Fast desktop may skip middle states; HUD still required.
- Stale cache shows old shell — hard refresh or new `?v=`.
- COI true breaks some Safari paths; project must keep COI false.
