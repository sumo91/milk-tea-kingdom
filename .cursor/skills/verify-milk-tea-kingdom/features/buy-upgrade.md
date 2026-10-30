# Buy one upgrade

Player taps one upgrade entry and sees currency or level feedback change.

## Sub-features

- `upgrade-click` activates one listed upgrade.
- `upgrade-feedback` shows gold/level (or disabled state) change on a second view.

## How to get to it (user POV)

- From main HUD, tap an affordable upgrade row in the list.

## Driving it with desktop browser

Preconditions:

- Stations HUD visible; enough gold for at least one upgrade (fresh save usually starts with auto-sell income — wait a few seconds if needed).

- **Baseline.** Screenshot `artifacts/verify/buy-upgrade/before.png`.
- **Click.** Click the first enabled upgrade control in the list (canvas click by visual position).
- **After.** Wait ~1s; screenshot `artifacts/verify/buy-upgrade/after.png`. Observable difference required (level, cost, or gold).

## Gotchas

- Fresh IndexedDB may differ from another profile’s save — use local port isolation.
- Clicking locked prestige upgrades may no-op; pick an early unlocked row.
