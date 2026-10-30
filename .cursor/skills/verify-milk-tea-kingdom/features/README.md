# milk-tea-kingdom verification map

Maintained source for verifying player-facing Web behavior. Read this index, then the matching feature file.

## Baseline preconditions

- Prefer local launch via `scripts/launch-local-web.sh` → `READY_URL`.
- Run `scripts/doctor.sh "$READY_URL"` before driving.
- Never drive a browser tab you did not open for this run when mutating upgrades (IndexedDB save).
- Public Pages (`sumo91.github.io/milk-tea-kingdom`) is for Lando Safari sign-off; agents use local `build/web` when possible.
- Pass = enter main HUD after hard refresh, not “URL opens” or “`?v=` changed”.

## Driving conventions

- Godot draws to canvas: assert by screenshot text/layout, not ARIA.
- Start from a fresh load for boot features.
- Keep proof under `artifacts/verify/<feature-id>/`.

## Proof and skip reporting

- Capture boot overlay when possible AND the HUD result.
- Record open→HUD seconds.
- If a stage is skipped due to fast network, say so; still require HUD.

## Features

- [Boot to HUD](./boot-to-hud.md) — Chinese load states → main HUD.
- [Stations HUD](./stations-hud.md) — title + three stations + upgrade list.
- [Buy one upgrade](./buy-upgrade.md) — click one upgrade, observe change.
- [Portrait fill width](./portrait-fill-width.md) — ~390 wide, no large gutters.
