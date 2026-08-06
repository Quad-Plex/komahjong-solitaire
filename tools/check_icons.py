#!/usr/bin/env python3
"""QA checks for the generated mahjong tile SVGs.

Checks:
  1. Every committed icon is well-formed XML.
  2. Committed icons match tools/gen_icons.py (the generator is the source
     of truth for the tile art).
  3. Rendered tiles touch edge-to-edge: no white gap between faces,
     horizontally AND between rows (the rendering-upgrade requirement).
  4. Symbols render inside the tile (nothing clipped by the viewBox).

Checks 1-2 are dependency-free. Checks 3-4 need `lua` (for the board
geometry) and `rsvg-convert` (for rasterizing); they are skipped with a
notice if those are unavailable. Exits non-zero on any failed check.

Usage:
    python3 tools/check_icons.py
"""
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_icons
from imgutil import read_png, render

REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ICONS_DIR = gen_icons.ICONS_DIR
TILE_W = 65
TILE_H = int(TILE_W * 1.4)
MARGIN = 10  # board preview margin in px (must match preview.py's board framing)

failures = 0
warnings = 0


def check(cond, msg):
    global failures
    if cond:
        print(f"PASS: {msg}")
    else:
        failures += 1
        print(f"FAIL: {msg}")


def note(msg):
    global warnings
    warnings += 1
    print(f"SKIP: {msg}")


def has_tool(name):
    return shutil.which(name) is not None


def board_geometry():
    """(tiles, (W, H)) — screen pos of every tile on a seeded board plus the
    board's pixel size. Mirrors the widget's computeGeometry/tilePos with the
    outward-bevel model: layer L is shifted up-left by L*BW/L*BH (the bevel
    thickness), so a raised tile's bevels land exactly on the edges of the
    tile directly beneath it. The bounds add the bevel overhang on the
    east/south and the layer shift on the west/north. Emits the bevel-variant
    icon name per tile (see MahjongLogic.iconForTile)."""
    lua = r'''
package.path = "%s/?.lua;" .. package.path
local Logic = require("mahjonglogic")
local TW, TH = %d, %d
local BW = math.floor(TW * 0.10 + 0.5)
local BH = math.floor(TH * 0.10 + 0.5)
local MARGIN = %d
local g = Logic.gridBounds()
local min_px, max_px = math.huge, -math.huge
local min_py, max_py = math.huge, -math.huge
for _, p in ipairs(Logic.buildLayout()) do
    local ux = (p.x - g.x_min) - p.layer * 0.10
    local uy = (p.y - g.y_min) - p.layer * 0.10
    min_px = math.min(min_px, ux); max_px = math.max(max_px, (p.x - g.x_min) + 1 + 0.10)
    min_py = math.min(min_py, uy); max_py = math.max(max_py, (p.y - g.y_min) + 1 + 0.10)
end
local ox = MARGIN - min_px * TW
local oy = MARGIN - min_py * TH
local board = Logic.newGame(42)
    for _, p in ipairs(Logic.buildLayout()) do
        local kind = Logic.tileAt(board, p.x, p.y, p.layer)
        if kind then
            local icon = Logic.iconForTile(board, p.x, p.y, p.layer)
            local px = math.floor(ox + (p.x - g.x_min) * TW - p.layer * BW)
            local py = math.floor(oy + (p.y - g.y_min) * TH - p.layer * BH)
            io.write(string.format("%%s %%d %%d %%s %%s %%d\n", icon, px, py, tostring(p.x), tostring(p.y), p.layer))
        end
    end
io.write(string.format("BOUNDS %%d %%d\n",
    math.ceil(max_px - min_px) * TW + 2 * MARGIN, math.ceil(max_py - min_py) * TH + 2 * MARGIN))
''' % (os.path.join(REPO_ROOT, "mahjong.koplugin"), TILE_W, TILE_H, MARGIN)
    res = subprocess.run(["lua", "-e", lua], capture_output=True, text=True, check=True)
    tiles = []
    bounds = None
    for ln in res.stdout.strip().splitlines():
        parts = ln.split()
        if parts[0] == "BOUNDS":
            bounds = (int(parts[1]), int(parts[2]))
        else:
            tiles.append({"icon": parts[0], "px": int(parts[1]), "py": int(parts[2]),
                          "x": float(parts[3]), "y": float(parts[4]), "layer": int(parts[5])})
    return tiles, bounds


def render_board(tiles, bounds):
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{bounds[0]}" height="{bounds[1]}" '
           f'viewBox="0 0 {bounds[0]} {bounds[1]}">',
           f'<rect width="{bounds[0]}" height="{bounds[1]}" fill="#ffffff"/>']
    for t in tiles:
        body = open(os.path.join(ICONS_DIR, t["icon"] + ".svg")).read()
        body = body.replace('<svg xmlns="http://www.w3.org/2000/svg" width="110" height="154" viewBox="0 0 110 154">', '').replace('</svg>', '')
        svg.append(f'<g transform="translate({t["px"]},{t["py"]}) scale({TILE_W / 100},{TILE_H / 140})">{body}</g>')
    svg.append('</svg>')
    svg_path = os.path.join(REPO_ROOT, ".board_check.svg")
    png_path = os.path.join(REPO_ROOT, ".board_check.png")
    with open(svg_path, "w") as f:
        f.write("".join(svg))
    render(svg_path, png_path, bounds[0], bounds[1])
    result = read_png(png_path)
    os.unlink(svg_path)
    os.unlink(png_path)
    return result


def is_transparent(px):
    return (px[3] if len(px) > 3 else 255) == 0


def max_run(seq):
    best = cur = 0
    for v in seq:
        cur = cur + 1 if v else 0
        best = max(best, cur)
    return best


def run_rendered_checks():
    tiles, (W, H) = board_geometry()
    w, h, px = render_board(tiles, (W, H))

    by_pos = {}
    for t in tiles:
        by_pos[(t["x"], t["y"], t["layer"])] = t

    # ---- Horizontal: bottom-row tiles touch edge-to-edge. The face's
    # anti-aliased edge can leave a single 1px transparent hairline at a seam,
    # but there must be no real gap: within a few columns of each boundary, no
    # run of 2+ fully transparent columns.
    bottom = sorted([t for t in tiles if t["y"] == 7 and t["layer"] == 0], key=lambda t: t["px"])
    mid_y = bottom[0]["py"] + TILE_H // 2
    gaps = []
    for i in range(len(bottom) - 1):
        boundary = bottom[i + 1]["px"]
        for dy in (-20, 0, 20):
            row = px[mid_y + dy]
            if max_run([is_transparent(row[c]) for c in range(boundary - 4, boundary + 4)]) >= 2:
                gaps.append((boundary, dy))
                break
    check(not gaps, "bottom-row tiles touch edge-to-edge (no gap >1px at any tile boundary)")

    # ---- Vertical: L0 rows y=6 and y=7 touch along the shared edge. ----
    row7_top = bottom[0]["py"]  # bottom edge of row 6 == top edge of row 7
    bad = []
    for t in bottom:
        col = t["px"] + TILE_W // 2
        if max_run([is_transparent(px[r][col]) for r in range(row7_top - 4, row7_top + 4)]) >= 2:
            bad.append(t["px"])
    check(not bad, "L0 rows y=6 and y=7 touch along the shared edge (no gap >1px)")

    # ---- 2.5D bevels only on exposed edges (bevel-variant follow-up): a tile
    # with a same-layer neighbour below hides its dark bottom bevel, while an
    # exposed bottom edge keeps it. The bevels are OUTWARD extensions now, so
    # the dark band sits just below the face (py+TILE_H .. py+TILE_H+BH).
    BH = int(TILE_H * 0.10 + 0.5)

    def sample_bottom_band(t):
        return px[t["py"] + TILE_H + BH // 2][t["px"] + TILE_W // 2]

    def is_dark_bevel(rgb):
        r, g, b = rgb[0], rgb[1], rgb[2]
        return abs(r - 84) <= 30 and abs(g - 110) <= 30 and abs(b - 122) <= 30

    exposed = by_pos[(1, 7, 0)]   # bottom row, right neighbour -> keeps bottom bevel
    hidden = by_pos[(2, 3, 0)]    # neighbours below AND right -> no bevels
    check(is_dark_bevel(sample_bottom_band(exposed)),
        "exposed bottom edge keeps the dark 2.5D bevel (tile at (1,7,0))")
    check(not is_dark_bevel(sample_bottom_band(hidden)),
        "bottom bevel is hidden where a same-layer tile sits below ((2,3,0))")

    # ---- Grid border: adjacent same-layer tiles have no bevels between them,
    # so the FACE outline (FACE_STROKE, tone of the side bevel #78909c) is what
    # separates them. The stroke is ~1px now, so scan a small window around the
    # seam and assert a visibly darker-than-white line is present (otherwise
    # internal seams of a solid layer would be invisible on e-ink).
    def is_dark_line(rgb):
        return rgb[0] < 205  # clearly darker than the white face

    mid_y = exposed["py"] + TILE_H // 2
    horiz = by_pos[(2, 7, 0)]
    seam_col = horiz["px"]  # the (1,7,0)-(2,7,0) boundary column
    window = [px[mid_y][c][:3] for c in range(seam_col - 2, seam_col + 3)]
    check(any(is_dark_line(rgb) for rgb in window),
        "vertical seam shows the face border (not white) between (1,7,0) and (2,7,0)")

    row7_top = by_pos[(3, 7, 0)]["py"]  # bottom edge of row 6 == top edge of row 7
    vert = by_pos[(3, 7, 0)]
    seam_row = row7_top  # the (3,6,0)-(3,7,0) boundary row
    window = [px[r][vert["px"] + TILE_W // 2][:3] for r in range(seam_row - 2, seam_row + 3)]
    check(any(is_dark_line(rgb) for rgb in window),
        "horizontal seam shows the face border (not white) between (3,6,0) and (3,7,0)")

    # ---- Symbols: every tile renders with its symbol fully inside the canvas. ----
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        clipped = []
        for name in sorted(os.listdir(ICONS_DIR)):
            if not name.endswith(".svg"):
                continue
            png = os.path.join(tmp, name.replace(".svg", ".png"))
            render(os.path.join(ICONS_DIR, name), png, 110, 154)
            tw, th, tpx = read_png(png)
            minx, miny, maxx, maxy = 10 ** 9, 10 ** 9, -1, -1
            for yy in range(th):
                for xx in range(tw):
                    r, g, b = tpx[yy][xx][0], tpx[yy][xx][1], tpx[yy][xx][2]
                    a = tpx[yy][xx][3] if len(tpx[yy][xx]) > 3 else 255
                    if a > 0 and (max(r, g, b) - min(r, g, b)) > 40 and max(r, g, b) > 60:
                        minx = min(minx, xx); maxx = max(maxx, xx)
                        miny = min(miny, yy); maxy = max(maxy, yy)
            if minx < 0 or miny < 0 or maxx > 153 or maxy > 153:
                clipped.append(name)
        n_icons = len([n for n in os.listdir(ICONS_DIR) if n.endswith(".svg")])
        check(not clipped, f"no symbol is clipped by the tile canvas ({len(clipped) or n_icons} in bounds)")


def main():
    # Check 1: XML well-formedness.
    names = sorted(n for n in os.listdir(ICONS_DIR) if n.endswith(".svg"))
    check(len(names) == 180, f"icons dir holds 180 SVGs (got {len(names)})")
    malformed = []
    for name in names:
        try:
            ET.parse(os.path.join(ICONS_DIR, name))
        except ET.ParseError:
            malformed.append(name)
    check(not malformed, "every icon parses as well-formed XML")

    # Check 2: icons are up to date with the generator.
    stale = gen_icons.check(ICONS_DIR)
    check(stale == 0, "committed icons match tools/gen_icons.py (run gen_icons.py if stale)")

    # Checks 3-4 need lua + a rasterizer.
    if has_tool("lua") and has_tool("rsvg-convert"):
        run_rendered_checks()
    else:
        note("rendered checks (tile touching / symbol bounds) need `lua` and `rsvg-convert` on PATH")

    if failures:
        print(f"\n{len(names)} icons, {failures} FAILURES")
        sys.exit(1)
    print("\nALL ICON CHECKS PASSED")
    if warnings:
        print(f"({warnings} skipped)")


if __name__ == "__main__":
    main()
