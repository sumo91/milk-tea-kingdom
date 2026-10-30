#!/usr/bin/env python3
"""Cross-check station, upgrade, and unlock ids. Optionally simulate payback.

    python3 tools/balance_content_gate.py
    python3 tools/balance_content_gate.py --simulate
    python3 tools/balance_content_gate.py --self-test

Reads data/content.json against data/buildings.json, data/upgrades.json,
data/resources.json, and data/v0_balance_draft.json. The game loads the first
four. The draft is the economy table those files are copied from. It does not
load v0_balance_draft.json at runtime.

Missing or extra ids exit 1. Placeholder ids the economy documents and
scripts/game_state.gd does not apply also exit 1.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import re
import sys
from pathlib import Path


# Flat ids the V0 comment in game_state.gd calls placeholders.
# tea_up / output_up add tea_bonus_per_min. waste_down and speed_up do not:
# the flat fallback charges gold and returns without changing a rate.
PLACEHOLDER_IDS = ("tea_up", "output_up", "waste_down", "speed_up")

PAYBACK_TOL = 0.051

ASSUMPTIONS = """
Assumptions for --simulate (greedy minutes-to-loop / payback)
--------------------------------------------------------------
Starting save: gold / ingredient / product / prestige from data/resources.json
(start). Levels start at 0. Station bases come from data/buildings.json.
Per-level outputs are the numbers scripts/game_state.gd applies, not the
JSON field names:

  tea_garden    +5 ingredient/min per level, on top of base_rate_per_min
  brew_station  +0.25 cycles/min per level, on top of base_cycles_per_min
  stall         +1 gold per cup per level; gold per cup starts at ratio_out

10 ingredient makes 1 cup (ING_PER_CUP). Stall starts unlocked and auto-sells.
cups/min = min(brew cycles, ingredient per min / 10).
gold/min = cups/min * gold per cup.

Payback of a buy is cost / increase in gold/min. Tea and brew start in exact
balance, so one side alone does not raise cups/min. A zero-delta buy is scored
with one lookahead step: (this cost + the next level of one other station) /
the gold/min increase after both. Lowest score wins. Ties break to the cheaper
upgrade, then the id. If that upgrade costs more gold than you have, the sim
waits at the current gold/min. It waits for the best score even when a worse
upgrade would become affordable sooner.

minutes-to-loop is the clock from t=0 until every station is at least level 1
and gold is back to the starting amount. Each step prints its own payback.
"bundle payback" is gold spent on that opening lap divided by the extra
gold/min at the end. Those two numbers are not the same: minutes-to-loop
includes the opening gold you already had.

Not modeled: ingredient cap, product cap, the 0.7 offline factor, prestige
locks, clicks, tea_up / waste_down / speed_up. Auto-sell means the product
cap does not fill. Gold/min uses the steady bottleneck rate, so caps are
ignored on purpose.

The payback-hint check (always on, not only --simulate) uses a different
assumption, the one baked into v0_balance_draft.json: base cup price, and the
new output fully converts (no tea/brew bottleneck). Stall hints are at 1
cup/min. Hints may disagree with the bottleneck sim. They must agree with
that unconstrained formula within 0.05 min.

Flat placeholders (tea_up, output_up, waste_down, speed_up) are not chain
upgrades. A new one needs the same id in content.json upgrade_copy,
upgrades.json, and v0_balance_draft.json flat_upgrades. tea_up and output_up
already add tea_bonus_per_min in game_state.gd. waste_down and speed_up hit
the flat fallback, which charges gold and does not change a rate, so the
gate fails until that changes.
""".strip()


def strip_gd_comments(src: str) -> str:
    out = []
    for line in src.splitlines():
        buf: list[str] = []
        in_str = False
        quote = ""
        i = 0
        while i < len(line):
            c = line[i]
            if in_str:
                buf.append(c)
                if c == "\\" and i + 1 < len(line):
                    buf.append(line[i + 1])
                    i += 2
                    continue
                if c == quote:
                    in_str = False
                i += 1
                continue
            if c in ('"', "'"):
                in_str = True
                quote = c
                buf.append(c)
                i += 1
                continue
            if c == "#":
                break
            buf.append(c)
            i += 1
        out.append("".join(buf))
    return "\n".join(out)


def branch_applies_rate(code: str, ident: str) -> tuple[bool, bool]:
    """Return (id appears outside comments, a rate is written in that branch)."""
    found = False
    applied = False
    needle = f'"{ident}"'
    start = 0
    while True:
        i = code.find(needle, start)
        if i < 0:
            break
        found = True
        window = code[i : i + 500]
        cut = window.find("return")
        if cut >= 0:
            window = window[:cut]
        if "tea_bonus_per_min" in window or re.search(r"gold_per_cup\s*=", window) or "building_levels[" in window:
            applied = True
        start = i + len(needle)
    return found, applied


def parse_rules(game_src: str) -> tuple[dict, list[str]]:
    code = strip_gd_comments(game_src)
    errors = []
    ing = re.search(r"const\s+ING_PER_CUP\s*:=\s*([0-9.]+)", code)
    tea = re.search(
        r"return\s+base\s*\+\s*float\(lv\)\s*\*\s*([0-9.]+)\s*\+\s*tea_bonus_per_min",
        code,
    )
    brew = re.search(r"return\s+base\s*\+\s*float\(lv\)\s*\*\s*([0-9.]+)\s*$", code, re.M)
    stall = re.search(
        r"gold_per_cup\s*=\s*([0-9.]+)\s*\+\s*float\(to_lv\)\s*(?:\*\s*([0-9.]+))?",
        code,
    )
    if not ing:
        errors.append("FAIL could not read ING_PER_CUP from scripts/game_state.gd")
    if not tea:
        errors.append("FAIL could not read tea per-level output from scripts/game_state.gd")
    if not brew:
        errors.append("FAIL could not read brew per-level output from scripts/game_state.gd")
    if not stall:
        errors.append("FAIL could not read stall gold_per_cup formula from scripts/game_state.gd")
    if errors:
        return {}, errors
    wiring = {}
    for ident in PLACEHOLDER_IDS:
        found, applied = branch_applies_rate(code, ident)
        wiring[ident] = "applied" if found and applied else "unwired"
    rules = {
        "ing_per_cup": float(ing.group(1)),
        "tea_delta": float(tea.group(1)),
        "brew_delta": float(brew.group(1)),
        "stall_base": float(stall.group(1)),
        "stall_delta": float(stall.group(2)) if stall.group(2) else 1.0,
        "wiring": wiring,
    }
    return rules, []


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"FAIL missing {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"FAIL {path} is not valid JSON: {exc}")


def load(root: Path) -> dict:
    data = root / "data"
    game = root / "scripts" / "game_state.gd"
    if not game.is_file():
        raise SystemExit(f"FAIL missing {game}")
    return {
        "content": load_json(data / "content.json"),
        "buildings": load_json(data / "buildings.json"),
        "upgrades": load_json(data / "upgrades.json"),
        "resources": load_json(data / "resources.json"),
        "balance": load_json(data / "v0_balance_draft.json"),
        "game_src": game.read_text(encoding="utf-8"),
    }


def _ids(items, key="id") -> list[str]:
    out = []
    for item in items:
        if isinstance(item, dict) and key in item:
            out.append(str(item[key]))
    return out


def _dupes(ids: list[str]) -> list[str]:
    seen = set()
    dup = []
    for i in ids:
        if i in seen and i not in dup:
            dup.append(i)
        seen.add(i)
    return dup


def _set_errors(kind: str, groups: dict[str, set[str]]) -> list[str]:
    errors = []
    labels = list(groups)
    union: set[str] = set()
    for s in groups.values():
        union |= s
    for ident in sorted(union):
        have = [label for label in labels if ident in groups[label]]
        if len(have) != len(labels):
            missing = [label for label in labels if ident not in groups[label]]
            errors.append(
                f"FAIL {kind} id {ident}: in {', '.join(have)}; missing from {', '.join(missing)}"
            )
    return errors


def _close(a: float, b: float) -> bool:
    return abs(a - b) <= PAYBACK_TOL


def check(loaded: dict) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    notes: list[str] = []
    rules, rule_errors = parse_rules(loaded["game_src"])
    errors.extend(rule_errors)
    if rule_errors:
        return errors, notes

    content = loaded["content"]
    buildings_doc = loaded["buildings"]
    upgrades_doc = loaded["upgrades"]
    resources_doc = loaded["resources"]
    balance = loaded["balance"]

    content_buildings = list(content.get("buildings") or [])
    runtime_buildings = list(buildings_doc.get("buildings") or [])
    balance_buildings = list(balance.get("buildings") or [])
    content_ups = list(content.get("upgrade_copy") or [])
    runtime_ups = list(upgrades_doc.get("upgrades") or [])
    balance_up_map = balance.get("upgrades") or {}
    flat_rows = list(balance.get("flat_upgrades") or [])

    for label, ids in (
        ("content.json buildings", _ids(content_buildings)),
        ("buildings.json", _ids(runtime_buildings)),
        ("v0_balance_draft.json buildings", _ids(balance_buildings)),
        ("content.json upgrade_copy", _ids(content_ups)),
        ("upgrades.json", _ids(runtime_ups)),
    ):
        for ident in _dupes(ids):
            errors.append(f"FAIL duplicate {label} id {ident}")

    c_stations = set(_ids(content_buildings))
    r_stations = set(_ids(runtime_buildings))
    b_stations = set(_ids(balance_buildings))
    errors.extend(
        _set_errors(
            "station",
            {
                "content.json": c_stations,
                "buildings.json": r_stations,
                "v0_balance_draft.json": b_stations,
            },
        )
    )

    chain_ids = []
    balance_rows = []  # (building_id, row)
    if not isinstance(balance_up_map, dict):
        errors.append("FAIL v0_balance_draft.json upgrades is not an object")
        balance_up_map = {}
    for bid, rows in balance_up_map.items():
        if not isinstance(rows, list):
            errors.append(f"FAIL v0_balance_draft.json upgrades.{bid} is not a list")
            continue
        for row in rows:
            if not isinstance(row, dict) or "to_level" not in row:
                errors.append(f"FAIL v0_balance_draft.json upgrades.{bid} row missing to_level")
                continue
            chain_ids.append(f"{bid}_{int(row['to_level'])}")
            balance_rows.append((str(bid), row))
    for ident in _dupes(chain_ids):
        errors.append(f"FAIL duplicate balance upgrade id {ident}")
    flat_ids = []
    for row in flat_rows:
        if isinstance(row, dict) and row.get("id"):
            flat_ids.append(str(row["id"]))
    for ident in _dupes(flat_ids):
        errors.append(f"FAIL duplicate flat_upgrades id {ident}")

    balance_ids = set(chain_ids) | set(flat_ids)
    errors.extend(
        _set_errors(
            "upgrade",
            {
                "content.json upgrade_copy": set(_ids(content_ups)),
                "upgrades.json": set(_ids(runtime_ups)),
                "v0_balance_draft.json": balance_ids,
            },
        )
    )

    by_id = {str(u.get("id")): u for u in runtime_ups if isinstance(u, dict)}
    content_by_id = {str(u.get("id")): u for u in content_ups if isinstance(u, dict)}
    balance_by_id = {f"{bid}_{int(row['to_level'])}": (bid, row) for bid, row in balance_rows}

    for ident, up in by_id.items():
        if "building_id" not in up:
            continue
        bid = str(up.get("building_id"))
        if bid not in r_stations:
            errors.append(f"FAIL upgrade {ident} building_id {bid} is not a station")
        pair = balance_by_id.get(ident)
        if pair is None:
            continue
        b_bid, brow = pair
        if b_bid != bid:
            errors.append(f"FAIL upgrade {ident} building_id {bid} != balance {b_bid}")
        if "cost_gold" in up and "cost_gold" in brow and float(up["cost_gold"]) != float(brow["cost_gold"]):
            errors.append(
                f"FAIL upgrade {ident} cost_gold {up['cost_gold']} != balance {brow['cost_gold']}"
            )
        if int(up.get("to_level", -1)) != int(brow["to_level"]):
            errors.append(f"FAIL upgrade {ident} to_level does not match the balance row")

    for bid in sorted(r_stations):
        levels = sorted(
            int(u.get("to_level", 0))
            for u in runtime_ups
            if isinstance(u, dict) and str(u.get("building_id")) == bid
        )
        if not levels:
            errors.append(f"FAIL station {bid} has no upgrades")
            continue
        expect = list(range(1, levels[-1] + 1))
        if levels != expect:
            errors.append(f"FAIL station {bid} upgrade levels {levels} are not 1..{levels[-1]} with no gaps")

    # Unlock ids are the station ids. prestige_gates must name that set and
    # no other id. A future unlock has to land in content and both building
    # tables before it is an unlock id.
    def prestige_of(rows: list) -> dict[str, float]:
        out = {}
        for row in rows:
            if not isinstance(row, dict) or "id" not in row:
                continue
            if "unlock_prestige" not in row:
                errors.append(f"FAIL station {row.get('id')} is missing unlock_prestige")
                continue
            out[str(row["id"])] = float(row["unlock_prestige"])
        return out

    c_un = prestige_of(content_buildings)
    r_un = prestige_of(runtime_buildings)
    b_un = prestige_of(balance_buildings)
    for ident in sorted(set(c_un) | set(r_un) | set(b_un)):
        vals = {
            "content.json": c_un.get(ident),
            "buildings.json": r_un.get(ident),
            "v0_balance_draft.json": b_un.get(ident),
        }
        present = {k: v for k, v in vals.items() if v is not None}
        if len(present) < 3:
            continue
        if len({v for v in present.values()}) != 1:
            shown = ", ".join(f"{k}={v:g}" for k, v in present.items())
            errors.append(f"FAIL unlock {ident} prestige mismatch: {shown}")

    gates = balance.get("prestige_gates") or []
    gate_map: dict[str, float] = {}
    for gate in gates:
        if not isinstance(gate, dict) or "unlocks" not in gate:
            errors.append("FAIL prestige_gates entry missing unlocks")
            continue
        uid = str(gate["unlocks"])
        if uid in gate_map:
            errors.append(f"FAIL unlock id {uid} appears more than once in prestige_gates")
            continue
        gate_map[uid] = float(gate.get("prestige", -1))
    errors.extend(
        _set_errors(
            "unlock",
            {
                "stations": set(r_un),
                "v0_balance_draft.json prestige_gates": set(gate_map),
            },
        )
    )
    for ident, prestige in gate_map.items():
        if ident in r_un and prestige != r_un[ident]:
            errors.append(
                f"FAIL unlock {ident}: prestige_gates says {prestige:g} but unlock_prestige is {r_un[ident]:g}"
            )

    res_content = set(_ids(content.get("resources") or [], "key"))
    res_balance = set(_ids(balance.get("resources") or [], "key"))
    res_runtime = set(resources_doc.keys()) if isinstance(resources_doc, dict) else set()
    errors.extend(
        _set_errors(
            "resource",
            {
                "content.json": res_content,
                "resources.json": res_runtime,
                "v0_balance_draft.json": res_balance,
            },
        )
    )

    # Placeholder fields the economy documents.
    documented: dict[str, list[str]] = {ident: [] for ident in PLACEHOLDER_IDS}
    for label, blob in (
        ("upgrades.json", upgrades_doc),
        ("v0_balance_draft.json", balance),
        ("content.json", content),
        ("buildings.json", buildings_doc),
    ):
        for path, text in _walk_strings(blob):
            if text in documented:
                documented[text].append(f"{label} {path}")
    for ident, places in documented.items():
        status = rules["wiring"][ident]
        if places and status != "applied":
            where = "; ".join(places[:6])
            errors.append(
                f"FAIL placeholder {ident}: economy documents it ({where}) "
                f"but scripts/game_state.gd does not apply it "
                f"(flat fallback charges gold and leaves rates unchanged)"
            )
        elif places and status == "applied":
            notes.append(f"audit {ident}: economy documents it and game_state.gd applies it")
        elif status == "applied":
            notes.append(
                f"audit {ident}: game_state.gd applies it (tea_bonus_per_min); not in data/*.json"
            )
        else:
            notes.append(
                f"audit {ident}: unwired in game_state.gd (gold charge, no rate change); not in data/*.json"
            )

    for ident, up in by_id.items():
        if "building_id" in up:
            continue
        if ident not in PLACEHOLDER_IDS or rules["wiring"].get(ident) != "applied":
            if not any(ident in e for e in errors):
                errors.append(
                    f"FAIL placeholder {ident}: upgrades.json has a flat upgrade the game does not apply"
                )

    # Deltas are documented on the draft and hardcoded in game_state.gd.
    delta_field = {
        "tea_garden": ("delta_ingredient_per_min", rules["tea_delta"]),
        "brew_station": ("delta_cycles_per_min", rules["brew_delta"]),
        "stall": ("delta_gold_per_cup", rules["stall_delta"]),
    }
    runtime_by_station = {str(b.get("id")): b for b in runtime_buildings if isinstance(b, dict)}
    balance_by_station = {str(b.get("id")): b for b in balance_buildings if isinstance(b, dict)}
    brew_ratio = None
    if "brew_station" in runtime_by_station:
        brew_ratio = float(runtime_by_station["brew_station"].get("ratio_in", rules["ing_per_cup"]))
        if brew_ratio != rules["ing_per_cup"]:
            errors.append(
                f"FAIL brew_station ratio_in {brew_ratio:g} != game ING_PER_CUP {rules['ing_per_cup']:g} "
                f"(economy documents a convert the game does not apply)"
            )
    if "stall" in runtime_by_station:
        ratio_out = float(runtime_by_station["stall"].get("ratio_out", -1))
        if ratio_out != rules["stall_base"]:
            errors.append(
                f"FAIL stall ratio_out {ratio_out:g} != game gold_per_cup base {rules['stall_base']:g}"
            )
    for bid, (field, applied) in delta_field.items():
        rows = [row for b, row in balance_rows if b == bid]
        if not rows:
            continue
        for row in rows:
            if field not in row:
                errors.append(f"FAIL balance {bid} level {row.get('to_level')} missing {field}")
                continue
            documented_delta = float(row[field])
            if documented_delta != applied:
                errors.append(
                    f"FAIL {field} on {bid} level {row.get('to_level')} is {documented_delta:g} "
                    f"but game_state.gd applies {applied:g} and does not read this field"
                )
        b_row = balance_by_station.get(bid, {})
        r_row = runtime_by_station.get(bid, {})
        for key in ("base_rate_per_min", "base_cycles_per_min", "base_cap", "ratio_in", "ratio_out"):
            if key in b_row and key in r_row and float(b_row[key]) != float(r_row[key]):
                errors.append(
                    f"FAIL {bid} {key} balance {b_row[key]} != buildings.json {r_row[key]}"
                )

    base_price = rules["stall_base"]
    ratio_in = brew_ratio if brew_ratio else rules["ing_per_cup"]
    hint_notes = []
    for bid, (field, applied) in delta_field.items():
        for row in [row for b, row in balance_rows if b == bid]:
            level = int(row["to_level"])
            ident = f"{bid}_{level}"
            cost = float(row.get("cost_gold", 0))
            if bid == "tea_garden":
                gold_delta = (applied / ratio_in) * base_price
                hint_key = "payback_min"
            elif bid == "brew_station":
                gold_delta = applied * base_price
                hint_key = "payback_min"
            else:
                gold_delta = applied * 1.0  # one cup per minute
                hint_key = "payback_min_at_1_cup_per_min"
            if gold_delta <= 0:
                errors.append(f"FAIL {ident} output does not raise gold under the hint formula")
                continue
            expect = cost / gold_delta
            if hint_key in row and not _close(float(row[hint_key]), expect):
                errors.append(
                    f"FAIL {ident} {hint_key} {row[hint_key]} != unconstrained payback {expect:.2f} "
                    f"(cost {cost:g} / gold-per-min {gold_delta:g}, base price {base_price:g}, no bottleneck)"
                )
            if bid == "stall" and "payback_min_at_2_cup_per_min" in row:
                two = float(row["payback_min_at_2_cup_per_min"])
                if not _close(two, expect / 2.0):
                    errors.append(
                        f"FAIL {ident} payback_min_at_2_cup_per_min {two} != {expect / 2.0:.2f}"
                    )
            up = by_id.get(ident, {})
            if "payback_min_hint" in up and hint_key in row:
                if not _close(float(up["payback_min_hint"]), float(row[hint_key])):
                    errors.append(
                        f"FAIL {ident} payback_min_hint {up['payback_min_hint']} != balance {row[hint_key]}"
                    )
            copy = content_by_id.get(ident, {})
            short = str(copy.get("payback_short", ""))
            m = re.fullmatch(r"回本~([0-9]+(?:\.[0-9]+)?)分", short)
            if not m:
                errors.append(f"FAIL {ident} content payback_short {short!r} is not 回本~N分")
            elif "payback_min_hint" in up and not _close(float(m.group(1)), float(up["payback_min_hint"])):
                errors.append(
                    f"FAIL {ident} content payback_short {short} != payback_min_hint {up['payback_min_hint']}"
                )
            hint_notes.append(ident)
    if hint_notes and not any(e.startswith("FAIL") and "payback" in e for e in errors):
        notes.append(
            f"NOTE payback hints match unconstrained cost/output for {len(hint_notes)} upgrades "
            f"(base price {base_price:g}, full convert, stall at 1 cup/min)"
        )
    notes.append(
        "NOTE delta_ingredient_per_min / delta_cycles_per_min / delta_gold_per_cup "
        f"are not read from JSON. game_state.gd hardcodes +{rules['tea_delta']:g} / "
        f"+{rules['brew_delta']:g} / +{rules['stall_delta']:g}. "
        + (
            "Every balance row matches those numbers."
            if not any("delta_" in e for e in errors)
            else "At least one balance row does not match."
        )
    )
    return errors, notes


def _walk_strings(obj, path="$"):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield f"{path}.{k}", str(k)
            yield from _walk_strings(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _walk_strings(v, f"{path}[{i}]")
    elif isinstance(obj, str):
        yield path, obj


def _bases(loaded: dict, rules: dict) -> dict[str, float]:
    out = {"tea": 10.0, "brew": 1.0, "price": rules["stall_base"]}
    for row in loaded["buildings"].get("buildings") or []:
        bid = str(row.get("id"))
        if bid == "tea_garden":
            out["tea"] = float(row.get("base_rate_per_min", out["tea"]))
        elif bid == "brew_station":
            out["brew"] = float(row.get("base_cycles_per_min", out["brew"]))
        elif bid == "stall":
            out["price"] = float(row.get("ratio_out", out["price"]))
    return out


def _gold_per_min(levels: dict[str, int], rules: dict, bases: dict[str, float]) -> float:
    tea = bases["tea"] + rules["tea_delta"] * levels.get("tea_garden", 0)
    brew = bases["brew"] + rules["brew_delta"] * levels.get("brew_station", 0)
    price = bases["price"] + rules["stall_delta"] * levels.get("stall", 0)
    cups = min(brew, tea / rules["ing_per_cup"]) if rules["ing_per_cup"] else 0.0
    return cups * price


def simulate(loaded: dict) -> list[str]:
    rules, rule_errors = parse_rules(loaded["game_src"])
    if rule_errors:
        return rule_errors
    bases = _bases(loaded, rules)
    ups = []
    for row in loaded["upgrades"].get("upgrades") or []:
        if not isinstance(row, dict) or "building_id" not in row:
            continue
        ups.append(
            {
                "id": str(row["id"]),
                "building": str(row["building_id"]),
                "to_level": int(row["to_level"]),
                "cost": float(row["cost_gold"]),
            }
        )
    stations = [str(b.get("id")) for b in loaded["buildings"].get("buildings") or [] if isinstance(b, dict)]
    levels = {bid: 0 for bid in stations}
    start_gold = float((loaded["resources"].get("gold") or {}).get("start", 0))
    gold = start_gold
    clock = 0.0
    lines = [
        "greedy payback (see --help for assumptions)",
        f"start gold={start_gold:g} gold/min={_gold_per_min(levels, rules, bases):.2f} "
        f"tea={bases['tea']:g}/min brew={bases['brew']:g}/min price={bases['price']:g}",
    ]
    spent = 0.0
    reached = False
    for _step in range(40):
        options = []
        for bid in stations:
            nxt = levels[bid] + 1
            match = [u for u in ups if u["building"] == bid and u["to_level"] == nxt]
            if match:
                options.append(match[0])
        if not options:
            break
        g0 = _gold_per_min(levels, rules, bases)
        ranked = []
        for up in options:
            trial = dict(levels)
            trial[up["building"]] = up["to_level"]
            g1 = _gold_per_min(trial, rules, bases)
            delta = g1 - g0
            if delta > 1e-9:
                ranked.append((up["cost"] / delta, up["cost"], up["id"], up, delta, "marginal", ""))
                continue
            best = None
            for other in options:
                if other["building"] == up["building"]:
                    continue
                both = dict(trial)
                both[other["building"]] = other["to_level"]
                g2 = _gold_per_min(both, rules, bases)
                both_delta = g2 - g0
                if both_delta <= 1e-9:
                    continue
                score = (up["cost"] + other["cost"]) / both_delta
                cand = (score, other["id"], both_delta)
                if best is None or cand < best:
                    best = cand
            if best is None:
                ranked.append((math.inf, up["cost"], up["id"], up, 0.0, "none", ""))
            else:
                ranked.append((best[0], up["cost"], up["id"], up, 0.0, "lookahead", best[1]))
        ranked.sort(key=lambda item: (item[0], item[1], item[2]))
        score, _cost, _id, best, delta, kind, partner = ranked[0]
        if math.isinf(score):
            lines.append("stop: no upgrade raises gold/min, even with one lookahead step")
            break
        if gold + 1e-6 < best["cost"]:
            if g0 <= 1e-9:
                lines.append("stop: gold/min is 0, cannot afford the next upgrade")
                break
            wait = (best["cost"] - gold) / g0
            clock += wait
            gold += wait * g0
            lines.append(f"  t={clock:.2f}  wait {wait:.2f} min for {best['id']} (gold {gold:.2f})")
        g_before = _gold_per_min(levels, rules, bases)
        gold -= best["cost"]
        spent += best["cost"]
        levels[best["building"]] = best["to_level"]
        g_after = _gold_per_min(levels, rules, bases)
        if kind == "marginal":
            pay = f"payback {score:.2f} min"
        elif kind == "lookahead":
            pay = (
                f"immediate payback n/a (gold/min unchanged); "
                f"lookahead {score:.2f} min if {partner} is also bought"
            )
        else:
            pay = "payback n/a"
        lines.append(
            f"  t={clock:.2f}  buy {best['id']} cost={best['cost']:g} "
            f"gold/min {g_before:.2f} -> {g_after:.2f}  {pay}"
        )
        if all(levels.get(bid, 0) >= 1 for bid in stations):
            reached = True
            break
    g_end = _gold_per_min(levels, rules, bases)
    if not reached:
        lines.append("minutes-to-loop: not reached (opening lap did not buy every station to level 1)")
        return lines
    if gold + 1e-6 < start_gold:
        if g_end <= 1e-9:
            lines.append("minutes-to-loop: not reached (gold/min is 0 after the opening lap)")
            return lines
        wait = (start_gold - gold) / g_end
        clock += wait
        lines.append(f"  t={clock:.2f}  earn back to starting gold {start_gold:g} ({wait:.2f} min)")
        gold = start_gold
    extra = g_end - _gold_per_min({bid: 0 for bid in stations}, rules, bases)
    lines.append(
        f"opening lap levels: " + ", ".join(f"{bid}={levels[bid]}" for bid in stations)
    )
    if extra > 1e-9:
        lines.append(
            f"bundle payback: {spent / extra:.2f} min "
            f"(spent {spent:.2f} gold / extra {extra:.2f} gold per min)"
        )
    else:
        lines.append("bundle payback: n/a (gold/min did not rise)")
    lines.append(
        f"minutes-to-loop: {clock:.2f} min "
        f"(every station level >= 1, gold back to {start_gold:g})"
    )
    return lines


def self_test(root: Path) -> None:
    loaded = load(root)
    errors, _notes = check(loaded)
    if errors:
        raise SystemExit("self-test expected the repo to pass:\n" + "\n".join(errors))

    missing = copy.deepcopy(loaded)
    missing["content"]["upgrade_copy"] = [
        u for u in missing["content"]["upgrade_copy"] if u.get("id") != "stall_1"
    ]
    bad, _ = check(missing)
    if not any("stall_1" in e for e in bad):
        raise SystemExit("self-test did not fail when stall_1 was removed from content")

    extra = copy.deepcopy(loaded)
    extra["balance"]["prestige_gates"] = list(extra["balance"]["prestige_gates"]) + [
        {"prestige": 200, "unlocks": "cap_boost_tier1"}
    ]
    bad, _ = check(extra)
    if not any("cap_boost_tier1" in e for e in bad):
        raise SystemExit("self-test did not fail on extra unlock id cap_boost_tier1")

    unwired = copy.deepcopy(loaded)
    row = {"id": "waste_down", "cost_gold": 10, "name": "waste"}
    unwired["upgrades"]["upgrades"] = list(unwired["upgrades"]["upgrades"]) + [row]
    unwired["content"]["upgrade_copy"] = list(unwired["content"]["upgrade_copy"]) + [
        {"id": "waste_down", "name": "损耗", "effect_short": "x", "payback_short": "回本~1分"}
    ]
    unwired["balance"].setdefault("flat_upgrades", [])
    unwired["balance"]["flat_upgrades"] = list(unwired["balance"]["flat_upgrades"]) + [row]
    bad, _ = check(unwired)
    if not any(e.startswith("FAIL") and "waste_down" in e and "does not apply" in e for e in bad):
        raise SystemExit("self-test did not flag unwired waste_down:\n" + "\n".join(bad))

    wired = copy.deepcopy(loaded)
    tea = {"id": "tea_up", "cost_gold": 10, "name": "tea"}
    wired["upgrades"]["upgrades"] = list(wired["upgrades"]["upgrades"]) + [tea]
    wired["content"]["upgrade_copy"] = list(wired["content"]["upgrade_copy"]) + [
        {"id": "tea_up", "name": "茶叶", "effect_short": "x", "payback_short": "回本~1分"}
    ]
    wired["balance"].setdefault("flat_upgrades", [])
    wired["balance"]["flat_upgrades"] = list(wired["balance"]["flat_upgrades"]) + [tea]
    bad, _ = check(wired)
    if bad:
        raise SystemExit("self-test tea_up is wired and should pass:\n" + "\n".join(bad))

    drifted = copy.deepcopy(loaded)
    drifted["balance"]["upgrades"]["tea_garden"][0]["delta_ingredient_per_min"] = 9
    bad, _ = check(drifted)
    if not any("delta_ingredient_per_min" in e for e in bad):
        raise SystemExit("self-test did not fail when a documented tea delta diverged from the game")

    sim = simulate(loaded)
    text = "\n".join(sim)
    if "minutes-to-loop:" not in text or "not reached" in text:
        raise SystemExit("self-test simulate did not reach minutes-to-loop:\n" + text)
    print("self-test: pass")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Fail if content ids and economy tables disagree, or a documented placeholder is unwired.",
        epilog=ASSUMPTIONS,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--root", type=Path, default=None, help="repo root (default: parent of tools/)")
    parser.add_argument("--simulate", action="store_true", help="print greedy minutes-to-loop and payback")
    parser.add_argument("--self-test", action="store_true", help="check fail paths, then the real tables")
    args = parser.parse_args(argv)
    root = args.root or Path(__file__).resolve().parent.parent
    loaded = load(root)
    errors, notes = check(loaded)
    for line in notes:
        print(line)
    if errors:
        for line in errors:
            print(line)
        print("balance content gate: fail")
        return 1
    print("balance content gate: pass")
    if args.simulate or args.self_test:
        if args.simulate:
            for line in simulate(loaded):
                print(line)
        if args.self_test:
            self_test(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
