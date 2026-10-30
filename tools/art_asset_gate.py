#!/usr/bin/env python3
"""Station-icon pixel gate, panel inset measurement, and pck art report.

    python3 tools/art_asset_gate.py
    python3 tools/art_asset_gate.py --tip --pck build/web/index.pck
    python3 tools/art_asset_gate.py --self-test

The HUD draws each station icon in a 64×64 slot (scripts/main.gd). This fails
when a wired station PNG is not about 64px, or its opaque bounding box is
skinny or mostly transparent.

Panel / skin insets are printed and do not fail the gate. Layout insets live
in main.gd (L/R 24, bottom 56), not in the bitmap.

Art on a phone is the imported ctex inside index.pck, not the git PNG.
Source sha256 lines identify the file you meant to ship. They are live only
after a Web export whose pck sha (tools/web_deploy_tip.sh) contains that
import. A changed PNG with an unchanged pck is still the old art.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
import tempfile
import zlib
from pathlib import Path


SLOT = 64
SLOT_TOL = 4  # ~64px → 60..68
MIN_BBOX_SIDE = 48
MIN_OPAQUE_RATIO = 0.40
ALPHA_OPAQUE = 16
# Real station ctex files are several KB. An empty import (seal) was ~246 bytes.
MIN_CTEX_BYTES = 512
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png_rgba(path: Path) -> tuple[int, int, list[bytearray]]:
    """Return width, height, and reconstructed rows of 8-bit RGBA."""
    data = path.read_bytes()
    if not data.startswith(PNG_SIG):
        raise ValueError(f"{path} is not a PNG")
    pos = 8
    width = height = bit = color = inter = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        tag = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, bit, color, _comp, _filt, inter = struct.unpack(">IIBBBBB", chunk)
        elif tag == b"IDAT":
            idat.extend(chunk)
        elif tag == b"IEND":
            break
    if width is None:
        raise ValueError(f"{path} has no IHDR")
    if bit != 8 or inter != 0 or color not in (2, 6):
        raise ValueError(
            f"{path} is {width}x{height} bit={bit} color={color} interlace={inter}; "
            "need 8-bit non-interlaced RGB or RGBA"
        )
    bpp = 4 if color == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = width * bpp
    rows: list[bytearray] = []
    prev = bytearray(stride)
    i = 0
    for _y in range(height):
        if i >= len(raw):
            raise ValueError(f"{path} IDAT ended early")
        filt = raw[i]
        i += 1
        row = bytearray(raw[i : i + stride])
        i += stride
        if len(row) != stride:
            raise ValueError(f"{path} IDAT row is short")
        if filt == 0:
            pass
        elif filt == 1:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + left) & 255
        elif filt == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif filt == 4:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                up = prev[x]
                ul = prev[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + _paeth(left, up, ul)) & 255
        else:
            raise ValueError(f"{path} uses PNG filter {filt}")
        prev = row
        if color == 2:
            rgba = bytearray(width * 4)
            for x in range(width):
                rgba[x * 4 : x * 4 + 3] = row[x * 3 : x * 3 + 3]
                rgba[x * 4 + 3] = 255
            row = rgba
        rows.append(row)
    return width, height, rows


def measure(path: Path) -> dict:
    width, height, rows = read_png_rgba(path)
    minx, miny = width, height
    maxx, maxy = -1, -1
    opaque = 0
    for y, row in enumerate(rows):
        for x in range(width):
            if row[x * 4 + 3] >= ALPHA_OPAQUE:
                opaque += 1
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    if maxx < 0:
        bbox_w = bbox_h = 0
        left = top = right = bottom = 0
    else:
        bbox_w = maxx - minx + 1
        bbox_h = maxy - miny + 1
        left, top = minx, miny
        right, bottom = width - 1 - maxx, height - 1 - maxy
    return {
        "w": width,
        "h": height,
        "opaque": opaque,
        "opaque_ratio": opaque / float(width * height) if width and height else 0.0,
        "bbox_w": bbox_w,
        "bbox_h": bbox_h,
        "left": left,
        "top": top,
        "right": right,
        "bottom": bottom,
    }


def station_errors(name: str, info: dict) -> list[str]:
    errors = []
    lo, hi = SLOT - SLOT_TOL, SLOT + SLOT_TOL
    if not (lo <= info["w"] <= hi and lo <= info["h"] <= hi):
        errors.append(
            f"FAIL {name}: expected slot ~{SLOT}px ({lo}–{hi}), got {info['w']}x{info['h']}"
        )
    if info["bbox_w"] < MIN_BBOX_SIDE or info["bbox_h"] < MIN_BBOX_SIDE:
        errors.append(
            f"FAIL {name}: opaque bounding box is {info['bbox_w']}x{info['bbox_h']} "
            f"on a {info['w']}x{info['h']} image (need both sides >= {MIN_BBOX_SIDE}). Too skinny."
        )
    pct = info["opaque_ratio"] * 100.0
    if info["opaque_ratio"] < MIN_OPAQUE_RATIO:
        errors.append(
            f"FAIL {name}: only {pct:.1f}% of pixels are opaque (alpha>={ALPHA_OPAQUE}). "
            f"Too transparent for a station icon (need >= {MIN_OPAQUE_RATIO:.0%})."
        )
    return errors


def read_pck(path: Path) -> list[tuple[str, int]]:
    """Godot PCK v2/v3/v4 directory as (path, size). Paths have no res:// prefix."""
    data = path.read_bytes()
    if data[:4] != b"GDPC":
        raise ValueError(f"{path} is not a Godot pck (magic {data[:4]!r})")
    version = struct.unpack_from("<I", data, 4)[0]
    if version not in (2, 3, 4):
        raise ValueError(f"{path} pack version {version} is not 2, 3, or 4")
    if version >= 3:
        flags = struct.unpack_from("<I", data, 20)[0]
        if flags & 1:
            raise ValueError(f"{path} directory is encrypted; cannot list art")
        dir_offset = struct.unpack_from("<Q", data, 32)[0]
        off = dir_offset
    else:
        off = 20 + 16 * 4
    if off + 4 > len(data):
        raise ValueError(f"{path} directory offset {off} is past end of file")
    file_count = struct.unpack_from("<I", data, off)[0]
    off += 4
    if file_count > 100000:
        raise ValueError(f"{path} file count {file_count} looks wrong")
    entries = []
    for _ in range(file_count):
        if off + 4 > len(data):
            raise ValueError(f"{path} directory truncated")
        sl = struct.unpack_from("<I", data, off)[0]
        off += 4
        raw = data[off : off + sl]
        off += sl
        name = raw.rstrip(b"\x00").decode("utf-8", "replace")
        _ofs, size = struct.unpack_from("<QQ", data, off)
        off += 16
        off += 16  # md5
        off += 4  # flags
        entries.append((name, size))
    return entries


def ctex_bytes(entries: list[tuple[str, int]], filename: str) -> int | None:
    best = None
    for name, size in entries:
        if filename in name and name.endswith(".ctex"):
            if best is None or size > best:
                best = size
    return best


def layout_insets(main_src: str) -> tuple[float, float] | None:
    left = re.search(r"const\s+INSET_L\s*:=\s*([0-9.]+)", main_src)
    bottom = re.search(r"const\s+INSET_B\s*:=\s*([0-9.]+)", main_src)
    if not left or not bottom:
        return None
    return float(left.group(1)), float(bottom.group(1))


def resolve_station_icons(root: Path, main_src: str) -> tuple[list[tuple[str, Path]], list[str]]:
    import json

    content = json.loads((root / "data" / "content.json").read_text(encoding="utf-8"))
    errors = []
    found = []
    icons = root / "assets" / "ui" / "idle" / "icons"
    for building in content.get("buildings") or []:
        bid = str(building.get("id", "?"))
        asset = str(building.get("icon_asset", ""))
        if not asset:
            errors.append(f"FAIL station {bid} has no icon_asset in content.json")
            continue
        candidates = [icons / f"{asset}.png", icons / f"{asset}_temp.png"]
        existing = [p for p in candidates if p.is_file()]
        if not existing:
            errors.append(
                f"FAIL station {bid} icon {asset}: no {asset}.png or {asset}_temp.png under assets/ui/idle/icons/"
            )
            continue
        referenced = [p for p in existing if p.name in main_src]
        if not referenced:
            errors.append(
                f"FAIL station {bid} icon {existing[0].name} is not referenced in scripts/main.gd, so the game will not draw it"
            )
            continue
        non_temp = [p for p in referenced if "_temp" not in p.name]
        found.append((bid, non_temp[0] if non_temp else referenced[0]))
    return found, errors


def portrait_panel(root: Path, main_src: str) -> tuple[Path | None, list[str]]:
    m = re.search(r"UI_PANEL_MAIN_portrait(?:_temp)?\.png", main_src)
    if not m:
        return None, ["FAIL scripts/main.gd does not reference UI_PANEL_MAIN_portrait png"]
    path = root / "assets" / "ui" / "idle" / "main" / m.group(0)
    if not path.is_file():
        return None, [f"FAIL portrait skin missing: {path}"]
    return path, []


def inset_lines(path: Path, insets: tuple[float, float] | None) -> list[str]:
    try:
        info = measure(path)
    except ValueError as exc:
        return [f"NOTE inset {path.name}: {exc}"]
    lines = [
        f"inset {path.name} {info['w']}x{info['h']} "
        f"alpha margins L{info['left']} T{info['top']} R{info['right']} B{info['bottom']} "
        f"(opaque bbox {info['bbox_w']}x{info['bbox_h']})"
    ]
    if insets is None:
        lines.append("  layout insets: could not read INSET_L / INSET_B from scripts/main.gd")
    elif info["opaque"] == info["w"] * info["h"]:
        lines.append(
            f"  bitmap is fully opaque. HUD insets are layout offsets in scripts/main.gd "
            f"(L/R {insets[0]:g}, bottom {insets[1]:g}), not alpha padding. Measurement only."
        )
    else:
        lines.append(
            f"  layout insets in scripts/main.gd are L/R {insets[0]:g}, bottom {insets[1]:g}. "
            "Alpha margins above are a measurement, not a failure."
        )
    return lines


def pck_report(pck: Path, files: list[Path]) -> tuple[list[str], list[str]]:
    """Return (lines, errors). Art is unverified until these names are in the pck."""
    lines = [
        "Art is only verifiable after it is inside this pck.",
        "Source sha256 is the git PNG. The phone shows the imported .ctex in index.pck,",
        "which is the pck sha on the deploy tip line. A new source hash does not ship",
        "until the next Web export replaces that pck.",
    ]
    errors = []
    if not files:
        return lines + ["art_in_pck=no"], ["FAIL no key art files to look up in the pck"]
    try:
        entries = read_pck(pck)
    except ValueError as exc:
        return lines, [f"FAIL {exc}"]
    for path in files:
        digest = sha256_file(path)
        size = ctex_bytes(entries, path.name)
        if size is None:
            lines.append(f"  {path.name} sha256={digest} in_pck=no")
            errors.append(
                f"FAIL {path.name} is not in {pck}. Source sha256={digest}. "
                "Re-export Web so the imported ctex is packed, then rerun sh tools/web_deploy_tip.sh. "
                "The player never sees a PNG that is only in git."
            )
        elif size < MIN_CTEX_BYTES:
            lines.append(f"  {path.name} sha256={digest} ctex_bytes={size} in_pck=no")
            errors.append(
                f"FAIL {path.name} ctex is in {pck} but only {size} bytes "
                f"(need >= {MIN_CTEX_BYTES}). The import looks empty, so the pixels are not in the pack."
            )
        else:
            lines.append(f"  {path.name} sha256={digest} ctex_bytes={size} in_pck=yes")
    if errors:
        lines.append("art_in_pck=no")
    else:
        lines.append("art_in_pck=yes")
    return lines, errors


def gather(root: Path) -> tuple[list[str], list[str], list[Path]]:
    main_path = root / "scripts" / "main.gd"
    if not main_path.is_file():
        return [f"FAIL missing {main_path}"], [], []
    main_src = main_path.read_text(encoding="utf-8")
    errors: list[str] = []
    notes: list[str] = []
    stations, icon_errors = resolve_station_icons(root, main_src)
    errors.extend(icon_errors)
    key_files: list[Path] = []
    for bid, path in stations:
        key_files.append(path)
        try:
            info = measure(path)
        except ValueError as exc:
            errors.append(f"FAIL {path.name}: {exc}")
            continue
        got = station_errors(path.name, info)
        errors.extend(got)
        if not got:
            notes.append(
                f"OK {bid} {path.name} {info['w']}x{info['h']} "
                f"opaque bbox {info['bbox_w']}x{info['bbox_h']} "
                f"opaque {info['opaque_ratio']:.1%}"
            )
    panel, panel_errors = portrait_panel(root, main_src)
    errors.extend(panel_errors)
    if panel is not None:
        key_files.append(panel)
    insets = layout_insets(main_src)
    panels = []
    if panel is not None:
        panels.append(panel)
    landscape = root / "assets" / "ui" / "idle" / "main" / "UI_PANEL_MAIN_temp.png"
    if landscape.is_file():
        panels.append(landscape)
    skins = root / "assets" / "ui" / "idle" / "skins"
    if skins.is_dir():
        panels.extend(sorted(skins.rglob("*.png")))
    for path in panels:
        notes.extend(inset_lines(path, insets))
    return errors, notes, key_files


def write_png(path: Path, width: int, height: int, pixel) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixel(x, y))
    comp = zlib.compress(bytes(raw))

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(PNG_SIG + chunk(b"IHDR", ihdr) + chunk(b"IDAT", comp) + chunk(b"IEND", b""))


def self_test(root: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        skinny = base / "skinny.png"
        faint = base / "faint.png"
        solid = base / "solid.png"

        def skinny_px(x, y):
            if 30 <= x <= 33:
                return bytes((180, 100, 40, 255))
            return bytes((0, 0, 0, 0))

        def faint_px(x, y):
            if x < 4 and y < 4:
                return bytes((180, 100, 40, 255))
            return bytes((0, 0, 0, 0))

        def solid_px(x, y):
            if 2 <= x < 62 and 2 <= y < 62:
                return bytes((200, 120, 60, 255))
            return bytes((0, 0, 0, 0))

        write_png(skinny, 64, 64, skinny_px)
        write_png(faint, 64, 64, faint_px)
        write_png(solid, 64, 64, solid_px)
        if not station_errors("skinny.png", measure(skinny)):
            raise SystemExit("self-test skinny icon did not fail")
        if not any("transparent" in e for e in station_errors("faint.png", measure(faint))):
            raise SystemExit("self-test transparent icon did not fail")
        if station_errors("solid.png", measure(solid)):
            raise SystemExit("self-test solid icon should pass: " + str(station_errors("solid.png", measure(solid))))
    # Real station icons must decode and pass. A broken PNG reader fails here.
    errors, notes, files = gather(root)
    if errors:
        raise SystemExit("self-test repo art gate failed:\n" + "\n".join(errors))
    if len(files) < 4:
        raise SystemExit(f"self-test expected 3 station icons + portrait skin, got {files}")
    print("self-test: pass")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Fail skinny/transparent station icons. Report whether key art is inside the pck.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--root", type=Path, default=None, help="repo root (default: parent of tools/)")
    parser.add_argument("--pck", type=Path, default=None, help="index.pck to check (default: build/web/index.pck if it exists)")
    parser.add_argument("--no-pck", action="store_true", help="do not look for a pck; source PNG checks only")
    parser.add_argument("--tip", action="store_true", help="print source sha256 and in_pck lines for the deploy tip")
    parser.add_argument("--self-test", action="store_true", help="fail a skinny PNG and a transparent PNG; pass the repo icons")
    args = parser.parse_args(argv)
    root = args.root or Path(__file__).resolve().parent.parent
    errors, notes, key_files = gather(root)
    for line in notes:
        print(line)
    pck = args.pck
    if pck is None and not args.no_pck:
        default = root / "build" / "web" / "index.pck"
        if default.is_file():
            pck = default
    if args.tip and pck is None:
        errors.append("FAIL --tip needs a pck (pass --pck or export build/web/index.pck)")
    if pck is not None:
        lines, pck_errors = pck_report(pck, key_files)
        for line in lines:
            print(line)
        errors.extend(pck_errors)
    elif not args.tip:
        print(
            "NOTE no index.pck. Station checks above are the git PNGs only. "
            "Art is not verifiable until a Web export packs the imported ctex into index.pck. "
            "Then run: sh tools/web_deploy_tip.sh"
        )
    if errors:
        for line in errors:
            print(line)
        print("art asset gate: fail")
        return 1
    print("art asset gate: pass")
    if args.self_test:
        self_test(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
