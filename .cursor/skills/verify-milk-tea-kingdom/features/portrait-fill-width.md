# Portrait fill width

On a phone-width viewport, the cream game surface fills the width without large empty side gutters.

## Sub-features

- `fill-390` at ~390 CSS px wide, content reaches edges (small safe inset OK).
- `no-letterbox` no large black/cream empty columns that make the playfield look postage-stamp.

## How to get to it (user POV)

- Open Web HUD in portrait phone width (device mode 390×844 or real phone).

## Driving it with desktop browser

Preconditions:

- Boot-to-HUD reached.

- **Resize.** Set viewport ~390 wide.
- **Proof.** `artifacts/verify/portrait-fill-width/w390.png`. Fail if playfield is a narrow column with large side gutters.

## Gotchas

- Desktop narrow window is not a substitute for the smoke checklist’s 390 gate when claiming mobile layout, but it is enough for agent local proof.
- Live Safari sign-off remains Lando’s gate.
