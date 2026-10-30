#!/usr/bin/env python3
"""Structural sync gate: game_state.gd must still match model assumptions."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def _repo_root() -> Path:
    here = Path(__file__).resolve().parent
    for cand in [here, *here.parents]:
        if (cand / "scripts" / "game_state.gd").is_file() and (cand / "project.godot").is_file():
            return cand
    raise SystemExit(f"FAIL sync_gate: cannot find repo root above {here}")


ROOT = _repo_root()
GS = ROOT / "scripts" / "game_state.gd"


def func_body(src: str, name: str) -> str:
    m = re.search(rf"func {re.escape(name)}\s*\(", src)
    if not m:
        return ""
    rest = src[m.start() :]
    # next top-level func or EOF
    n = re.search(r"\nfunc ", rest[1:])
    return rest if n is None else rest[: n.start() + 1]


def main() -> int:
    if not GS.is_file():
        print(f"FAIL sync_gate: missing {GS}", file=sys.stderr)
        return 1
    text = GS.read_text(encoding="utf-8")
    tick = func_body(text, "_tick")
    offline = func_body(text, "settle_offline")
    buy = func_body(text, "try_buy_upgrade")
    sell = func_body(text, "_sell_amount")

    checks: list[tuple[str, str, bool]] = [
        (
            "tick_ingredient_cap",
            "_tick must cap 茶叶 with minf(ingredient_cap, ...)",
            re.search(r"ingredient\s*=\s*minf\(\s*ingredient_cap\s*,", tick) is not None,
        ),
        (
            "tick_product_cap",
            "_tick brew must respect product_cap - product",
            re.search(r"minf\(\s*can_make\s*,\s*product_cap\s*-\s*product\s*\)", tick) is not None,
        ),
        (
            "tick_order_brew_before_sell",
            "_tick must brew (ingredient -=) before auto-sell (_sell_amount)",
            (re.search(r"ingredient\s*-=\s*can_make", tick) is not None
             and re.search(r"_sell_amount\(\s*product\s*\)", tick) is not None
             and tick.find("ingredient -= can_make") < tick.find("_sell_amount(product)")),
        ),
        (
            "offline_ingredient_cap",
            "settle_offline must cap 茶叶 with minf(ingredient_cap, ...)",
            re.search(r"ingredient\s*=\s*minf\(\s*ingredient_cap\s*,", offline) is not None,
        ),
        (
            "offline_product_cap",
            "settle_offline brew must respect product_cap - product",
            re.search(r"minf\(\s*d_prod\s*,\s*product_cap\s*-\s*product\s*\)", offline) is not None,
        ),
        (
            "buy_gold_check",
            "try_buy_upgrade must refuse when gold < cost before deducting",
            (re.search(r"if\s+gold\s*<\s*cost", buy) is not None
             and buy.find("if gold < cost") < buy.find("gold -= cost")),
        ),
        (
            "buy_level_plus_one",
            "try_buy_upgrade level chain requires to_level == cur + 1",
            re.search(r"to_lv\s*!=\s*cur\s*\+\s*1", buy) is not None,
        ),
        (
            "sell_amount_uses_product",
            "_sell_amount must decrease product and increase gold",
            (re.search(r"product\s*-=\s*amount", sell) is not None
             and re.search(r"gold\s*\+=\s*amount\s*\*\s*gold_per_cup", sell) is not None),
        ),
        (
            "constants",
            "OFFLINE_FACTOR 0.7 and ING_PER_CUP 10.0 still defined",
            (re.search(r"const OFFLINE_FACTOR\s*:=\s*0\.7", text) is not None
             and re.search(r"const ING_PER_CUP\s*:=\s*10\.0", text) is not None),
        ),
    ]

    failed = [(i, h) for i, h, ok in checks if not ok]
    if failed:
        print("FAIL sync_gate: game_state.gd no longer matches formal model assumptions:")
        for rid, human in failed:
            print(f"  - [{rid}] {human}")
        print("Update models/GameStateEconomy.tla to match intentional changes, then re-run.")
        return 1
    print(f"OK sync_gate: {len(checks)} patterns match {GS.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
