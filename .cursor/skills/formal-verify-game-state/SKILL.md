---
name: formal-verify-game-state
description: Formal-check milk-tea-kingdom GameState economy invariants (茶叶/杯装 caps, non-negative gold, stall price, level+1 buys) via sync_gate + TLA+/TLC. Use when changing scripts/game_state.gd tick, offline settle, buy, or sell; or when asked for formal verification of the idle loop.
---

# formal-verify-game-state

## Promise (one sentence)

After every `_tick` / `settle_offline` / `try_buy_upgrade` / `sell_all_product` step, **茶叶** stay in `[0, ingredient_cap]`, **杯装奶茶** stay in `[0, product_cap]`, **金币** never go negative, stall `gold_per_cup` matches stall level, and building levels only advance by +1 when gold is paid.

## Harm if broken

Players can stockpile past hard caps, go negative on a bad sell/buy order, skip upgrade tiers, or desync 摊位 price from level — soft-locks and unfair economy.

## When this skill applies

A change **touches verified code** if it edits any of:

| Path | Functions / constants |
| --- | --- |
| `scripts/game_state.gd` | `_tick`, `settle_offline`, `try_buy_upgrade`, `_sell_amount`, `sell_all_product`, `ingredient_rate`, `brew_cycles_per_min`, `ING_PER_CUP`, `OFFLINE_FACTOR`, caps |
| `data/buildings.json` | `base_rate_per_min`, `base_cycles_per_min`, `base_cap`, `ratio_out`, `unlock_prestige` for tea_garden / brew_station / stall |
| `data/resources.json` | `hard_cap` / `start` for ingredient, product, gold |
| `data/upgrades.json` | `cost_gold` / `to_level` for levels 1..2 (model bound) |

Also run after intentional economy rewrites before shipping. Behavioral Web proof stays in `verify-milk-tea-kingdom` — this skill does not drive the browser.

## One command

From the repo root (or anywhere):

```bash
export JAVA_BIN=${JAVA_BIN:-/home/box/tools/jdk-21.0.13+9-jre/bin/java}
export TLA_JAR=${TLA_JAR:-/home/box/tools/tla2tools.jar}
.cursor/skills/formal-verify-game-state/scripts/check.sh
```

Expect: `OK sync_gate` then `Model checking completed. No error has been found.` then `OK formal-verify-game-state` (about 1–2s, ~67k distinct states at current bounds).

Needs: JRE 21+, `tla2tools.jar` (TLC), Python 3. Set `JAVA_BIN` / `TLA_JAR` if not on the box defaults above.

## What the check does

1. **`scripts/sync_gate.py`** — regex/structure gate on `game_state.gd` so removing a cap, reordering brew-before-sell, or dropping the gold\<cost guard fails **without** editing TLA+.
2. **TLC** on `models/GameStateEconomy.tla` + `GameStateEconomy.cfg` — explores orders of Produce → AutoSell, OfflineSettle, BuyTea/Brew/Stall, SellAll under the bounds below.

## Reading results

- **sync_gate FAIL** → real code no longer matches the assumptions listed in the failure lines. Either fix the code or intentionally update `models/GameStateEconomy.tla` + this skill, then re-run.
- **TLC `Error: Invariant …`** → counterexample is an event order. Read every TLC result with pstack **`/statechart`** (load that skill; do not copy its CLI flags from memory). Replay the path against `game_state.gd` in code nouns (茶园 upgrade → 离线结算 → `_tick` produce…).
- **TLC pass + sync_gate OK** → properties hold **inside the model bounds**, not for the whole Godot runtime (floats, save/load, UI).

### Real bug vs modeling error

| Symptom | Likely cause |
| --- | --- |
| sync_gate fails on a line you did not mean to change | Real regression in `game_state.gd` |
| TLC fails after you edited only the `.tla` to match a code change | Model now exposes a bad order — treat as bug until replayed in GDScript |
| TLC fails but GDScript replay cannot reproduce | Modeling error (batching, missing unlock gate, wrong cost table) — fix the `.tla`, do not weaken invariants |
| Invariant only fails past GoldBound / MaxLevel | Raise bounds carefully or document new LIMIT; do not delete the invariant |

**Findings stay findings.** Do not soften `InvCaps` / `InvGoldNonNeg` to make TLC green.

## Bounds and assumptions

Recorded in `models/GameStateEconomy.cfg`:

- `IngredientCap=120`, `ProductCap=60`, `IngPerCup=10`, `GoldPerCupBase=8`
- `MaxLevel=2` (upgrade costs for lv1–2 from `data/upgrades.json`)
- `GoldBound=120` (CONSTRAINT; gold has no hard_cap in code)
- `OfflineMinuteSet={1,2,4}` — minutes **after** `OFFLINE_FACTOR` (0.7) already applied
- Online time batched as **4-minute** produce steps so `brew_cycles = 4 + brew_lv` matches `1 + 0.25*lv` exactly
- V0: all three stations `unlock_prestige=0` → 摊位 auto-sell always on; model always AutoSells after Produce
- Produce vs AutoSell are **separate** TLC actions (with `pc`) so mid-tick 杯装 can violate `InvCaps` if the brew cap is dropped; in GDScript both run inside one `_tick`

## Not covered

- Sub-minute `_process` deltas and float error
- `save_game` / `load_game` / IndexedDB flush
- Flat upgrades `tea_up` / `waste_down` / `speed_up` (placeholders; some still charge gold)
- Prestige unlock gates ≠ 0 (future content)
- UI / Web boot (see `verify-milk-tea-kingdom`)
- `tools/balance_content_gate.py` payback simulation (separate P1 tool)

## Coverage record

| Check | Covers |
| --- | --- |
| sync_gate + InvCaps | `_tick`, `settle_offline` cap + brew floor |
| InvGoldNonNeg + Buy* | `try_buy_upgrade` gold guard + deduct |
| InvStallPrice | stall branch sets `gold_per_cup = 8 + to_lv` |
| InvLevelsBounded + Buy* +1 | level chain `to_lv == cur + 1` |
| Produce→AutoSell order | `_tick` brew then `_sell_amount(product)` |

**Sync commit** (last confirmed model describes this code): `9215b6240c51556721bd77e52e1d5b7ce2e3c810` (`9215b62`).

Move the sync commit forward **only** after you re-run `check.sh` and confirm the `.tla` still matches `game_state.gd` at the new commit. Use `/maintain-formal-verification-skill` when covered code changed without a recheck.

## Layout

```
.cursor/skills/formal-verify-game-state/
  SKILL.md
  models/GameStateEconomy.tla
  models/GameStateEconomy.cfg
  scripts/check.sh
  scripts/sync_gate.py
  artifacts/          # TLC logs (gitignored)
```
