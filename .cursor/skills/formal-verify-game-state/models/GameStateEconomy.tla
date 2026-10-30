-------------------------- MODULE GameStateEconomy --------------------------
\* Formal model of scripts/game_state.gd economy loop (V0).
\*
\* Code mapping:
\*   Produce4Minutes ~ the add-tea + brew portion of _tick (batched 4 minutes)
\*   AutoSell         ~ _sell_amount(product) at end of _tick when 摊位 unlocked
\*   OfflineSettle    ~ settle_offline (atomic; OFFLINE_FACTOR already in mins)
\*   BuyTea/Brew/Stall ~ try_buy_upgrade level-chain branches
\*   SellAll          ~ sell_all_product (manual; same math as AutoSell)
\*
\* Why Produce and AutoSell are separate actions:
\*   In GDScript both run inside one _tick without yielding. Splitting them in
\*   the model exposes the mid-tick state so InvCaps can fail if brew omits
\*   product_cap. The code's call order must stay Produce-then-AutoSell.
\*
\* Brew rate: code brew_cycles_per_min = 1 + lv*0.25.
\*   Produce4Minutes uses cycles = 4 + brew_lv (= 4*(1+0.25*lv)).
\* Sub-minute deltas, floats, save/load, tea_up/waste_down/speed_up: out of scope.
\* V0 buildings.json unlock_prestige = 0 for all three → 摊位 always auto-sells.

EXTENDS Integers, TLC

CONSTANTS
  IngredientCap,     \* 120 — resources.json hard_cap / tea_garden base_cap
  ProductCap,        \* 60  — brew_station base_cap
  IngPerCup,         \* 10  — ING_PER_CUP
  GoldPerCupBase,    \* 8   — stall ratio_out
  MaxLevel,          \* model bound
  GoldBound,          \* CONSTRAINT (gold has no hard_cap)
  OfflineMinuteSet   \* post-OFFLINE_FACTOR minutes

VARIABLES
  ingredient,        \* 茶叶
  product,           \* 杯装奶茶
  gold,              \* 金币
  prestige,          \* 声望
  tea_lv,            \* building_levels["tea_garden"]
  brew_lv,           \* building_levels["brew_station"]
  stall_lv,          \* building_levels["stall"]
  gold_per_cup,      \* 8 + stall_lv after stall upgrade
  pc                 \* "idle" | "need_sell" — model-only mid-tick marker

vars == <<ingredient, product, gold, prestige, tea_lv, brew_lv, stall_lv, gold_per_cup, pc>>

TeaCost(to) == CASE to = 1 -> 20 [] to = 2 -> 28 [] OTHER -> 999999
BrewCost(to) == CASE to = 1 -> 8 [] to = 2 -> 11 [] OTHER -> 999999
StallCost(to) == CASE to = 1 -> 25 [] to = 2 -> 34 [] OTHER -> 999999

IngredientRate == 10 + 5 * tea_lv
BrewCyclesPer4Min == 4 + brew_lv

Min2(a, b) == IF a < b THEN a ELSE b
Min3(a, b, c) == Min2(Min2(a, b), c)
Max2(a, b) == IF a > b THEN a ELSE b

----------------------------------------------------------------------------
Init ==
  /\ ingredient = 20
  /\ product = 0
  /\ gold = 50
  /\ prestige = 0
  /\ tea_lv = 0
  /\ brew_lv = 0
  /\ stall_lv = 0
  /\ gold_per_cup = GoldPerCupBase
  /\ pc = "idle"

----------------------------------------------------------------------------
\* Brew helper: returns <<new_ingredient, new_product>> after add+brew for mins.
BrewAfter(ing, prod, mins) ==
  LET d_ing == IngredientRate * mins
      ing1  == Min2(IngredientCap, ing + d_ing)
      cycles == (BrewCyclesPer4Min * mins) \div 4
      can0  == Min3(cycles, ing1 \div IngPerCup, ProductCap - prod)
      can   == Max2(0, can0)
  IN <<ing1 - can * IngPerCup, prod + can>>

Produce4Minutes ==
  /\ pc = "idle"
  /\ LET r == BrewAfter(ingredient, product, 4)
     IN /\ ingredient' = r[1]
        /\ product'    = r[2]
        /\ pc'         = "need_sell"
        /\ UNCHANGED <<gold, prestige, tea_lv, brew_lv, stall_lv, gold_per_cup>>

AutoSell ==
  /\ pc = "need_sell"
  /\ product' = 0
  /\ gold' = gold + product * gold_per_cup
  /\ prestige' = prestige + product
  /\ pc' = "idle"
  /\ UNCHANGED <<ingredient, tea_lv, brew_lv, stall_lv, gold_per_cup>>

\* settle_offline: one function — produce then sell, return to idle.
OfflineSettle ==
  /\ pc = "idle"
  /\ \E m \in OfflineMinuteSet:
       LET r == BrewAfter(ingredient, product, m)
           prod1 == r[2]
       IN /\ ingredient' = r[1]
          /\ product'    = 0
          /\ gold'       = gold + prod1 * gold_per_cup
          /\ prestige'   = prestige + prod1
          /\ UNCHANGED <<tea_lv, brew_lv, stall_lv, gold_per_cup, pc>>

BuyTea ==
  /\ pc = "idle"
  /\ tea_lv < MaxLevel
  /\ LET to == tea_lv + 1
         cost == TeaCost(to)
     IN /\ gold >= cost
        /\ gold' = gold - cost
        /\ tea_lv' = to
        /\ UNCHANGED <<ingredient, product, prestige, brew_lv, stall_lv, gold_per_cup, pc>>

BuyBrew ==
  /\ pc = "idle"
  /\ brew_lv < MaxLevel
  /\ LET to == brew_lv + 1
         cost == BrewCost(to)
     IN /\ gold >= cost
        /\ gold' = gold - cost
        /\ brew_lv' = to
        /\ UNCHANGED <<ingredient, product, prestige, tea_lv, stall_lv, gold_per_cup, pc>>

BuyStall ==
  /\ pc = "idle"
  /\ stall_lv < MaxLevel
  /\ LET to == stall_lv + 1
         cost == StallCost(to)
     IN /\ gold >= cost
        /\ gold' = gold - cost
        /\ stall_lv' = to
        /\ gold_per_cup' = GoldPerCupBase + to
        /\ UNCHANGED <<ingredient, product, prestige, tea_lv, brew_lv, pc>>

BuyUpgrade == BuyTea \/ BuyBrew \/ BuyStall

SellAll ==
  /\ pc = "idle"
  /\ product > 0
  /\ product' = 0
  /\ gold' = gold + product * gold_per_cup
  /\ prestige' = prestige + product
  /\ UNCHANGED <<ingredient, tea_lv, brew_lv, stall_lv, gold_per_cup, pc>>

Done ==
  /\ pc = "idle"
  /\ gold > GoldBound
  /\ UNCHANGED vars

Next ==
  Produce4Minutes \/ AutoSell \/ OfflineSettle \/ BuyUpgrade \/ SellAll \/ Done

Spec == Init /\ [][Next]_vars

----------------------------------------------------------------------------
TypeOK ==
  /\ ingredient \in Int
  /\ product \in Int
  /\ gold \in Nat
  /\ prestige \in Nat
  /\ tea_lv \in 0..MaxLevel
  /\ brew_lv \in 0..MaxLevel
  /\ stall_lv \in 0..MaxLevel
  /\ gold_per_cup = GoldPerCupBase + stall_lv
  /\ pc \in {"idle", "need_sell"}

\* Promise: 茶叶 / 杯装 stay inside hard caps and never go negative.
InvCaps ==
  /\ ingredient >= 0 /\ ingredient <= IngredientCap
  /\ product >= 0 /\ product <= ProductCap

InvGoldNonNeg == gold >= 0

InvStallPrice == gold_per_cup = GoldPerCupBase + stall_lv

InvLevelsBounded ==
  /\ tea_lv \in 0..MaxLevel
  /\ brew_lv \in 0..MaxLevel
  /\ stall_lv \in 0..MaxLevel

\* After Produce, AutoSell must be the next economy step (model of _tick tail).
InvNeedSellImpliesProduct ==
  pc = "need_sell" => product >= 0

GoldConstraint == gold <= GoldBound

=============================================================================
