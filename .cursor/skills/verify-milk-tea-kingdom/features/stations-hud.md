# Stations HUD

Main screen shows the game title, three production stations, and an upgrade list a player can read.

## Sub-features

- `hud-title` shows **奶茶王国**.
- `hud-stations` shows **茶园**, **调制台**, **摊位**.
- `hud-upgrades` shows an upgrade list region.

## How to get to it (user POV)

- Complete boot to HUD on Web.

## Driving it with desktop browser

Preconditions:

- Boot-to-HUD already reached (or same session after boot).

- **Inspect.** Screenshot full game view.
- **Proof.** `artifacts/verify/stations-hud/hud.png` must show title and all three station names plus upgrade rows. Missing any station = fail.

## Gotchas

- CJK tofu on station labels is a content/font fail even if layout exists.
- Do not pass on placeholder letterboxing alone.
