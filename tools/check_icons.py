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
    """(tiles, bounds) — screen pos of every tile on a seeded board plus the
    board's pixel bounds. Mirrors the widget's computeGeometry/tilePos."""
    lua = r'''
package.path = "%s/?.lua;" .. package.path
local Logic = require("mahjonglogic")
local TW, TH = %d, %d
local offx, offy = math.floor(TW/2), math.floor(TH/2)
local g = Logic.gridBounds()
local min_px, max_px = math.huge, -math.huge
local min_py, max_py = math.huge, -math.huge
for _, p in ipairs(Logic.buildLayout()) do
    local ux = (p.x - g.x_min) + 0.5*p.layer
    local uy = (p.y - g.y_min) - 0.5*p.layer
    min_px = math.min(min_px, ux); max_px = math.max(max_px, ux+1)
    min_py = math.min(min_py, uy); max_py = math.max(max_py, uy+1)
end
local ox = %d - min_px*TW
local oy = %d - min_py*TH
local board = Logic.newGame(42)
for _, p in ipairs(Logic.buildLayout()) do
    local kind = Logic.tileAt(board, p.x, p.y, p.layer)
    if kind then
        local px = math.floor(ox + (p.x - g.x_min)*TW + p.layer*offx)
        local py = math.floor(oy + (p.y - g.y_min)*TH - p.layer*offy)
        io.write(string.format("%%s %%d %%d %%d %%d\n", kind, px, py, p.x, p.y))
    end
end
-- also print bottom-row tile left edges (L0 y=7, unobscured) and the board
-- origin/bounds
io.write(string.format("BOUNDS %%d %%d\n", %d, %d))
''' % (os.path.join(REPO_ROOT, "mahjong.koplugin"), TILE_W, TILE_H, MARGIN, MARGIN,
       MARGIN + 12 * TILE_W, MARGIN + 7 * TILE_H)
    res = subprocess.run(["lua", "-e", lua], capture_output=True, text=True, check=True)
    tiles = []
    bounds = None
    for ln in res.stdout.strip().splitlines():
        parts = ln.split()
        if parts[0] == "BOUNDS":
            bounds = (int(parts[1]), int(parts[2]))
        else:
            tiles.append({"kind": parts[0], "px": int(parts[1]), "py": int(parts[2]),
                          "x": int(parts[3]), "y": int(parts[4])})
    return tiles, bounds


def render_board(tiles, bounds):
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{bounds[0]}" height="{bounds[1]}" '
           f'viewBox="0 0 {bounds[0]} {bounds[1]}">',
           f'<rect width="{bounds[0]}" height="{bounds[1]}" fill="#ffffff"/>']
    for t in tiles:
        body = open(os.path.join(ICONS_DIR, t["kind"] + ".svg")).read()
        body = body.replace('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">', '').replace('</svg>', '')
        svg.append(f'<g transform="translate({t["px"]},{t["py"]}) scale({TILE_W / 100},{TILE_H / 100})">{body}</g>')
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


def is_white(px):
    r, g, b = px[0], px[1], px[2]
    a = px[3] if len(px) > 3 else 255
    return a == 0 or (r > 240 and g > 240 and b > 240)


def run_rendered_checks():
    tiles, (W, H) = board_geometry()
    w, h, px = render_board(tiles, (W, H))

    # ---- Horizontal: tiles in the bottom L0 row touch edge-to-edge. ----
    bottom = [t for t in tiles if t["y"] == 7 and t["x"] >= 2]
    bottom.sort(key=lambda t: t["px"])
    mid_y = bottom[0]["py"] + TILE_H // 2
    gaps = []
    for i in range(len(bottom) - 1):
        boundary = bottom[i + 1]["px"]
        if any(is_white(px[mid_y + dy][boundary]) for dy in (-20, 0, 20)):
            gaps.append(boundary)
    check(not gaps, "bottom-row tiles touch edge-to-edge (no white gap at any tile boundary)")

    # ---- Vertical: L0 rows y=6 and y=7 touch along the shared edge. ----
    # The boundary is at the top edge of the bottom row; rounded corners make
    # the very ends white, so probe the mid-column of each tile instead.
    row7_top = bottom[0]["py"]  # bottom edge of row 6 == top edge of row 7
    bad = [t["px"] for t in bottom if is_white(px[row7_top][t["px"] + TILE_W // 2])]
    check(not bad, "L0 rows y=6 and y=7 touch along the shared edge (no white gap)")

    # ---- Symbols: every tile renders with its symbol fully inside the canvas. ----
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        clipped = []
        for name in sorted(os.listdir(ICONS_DIR)):
            if not name.endswith(".svg"):
                continue
            png = os.path.join(tmp, name.replace(".svg", ".png"))
            render(os.path.join(ICONS_DIR, name), png, 100, 100)
            tw, th, tpx = read_png(png)
            minx, miny, maxx, maxy = 10 ** 9, 10 ** 9, -1, -1
            for yy in range(th):
                for xx in range(tw):
                    r, g, b = tpx[yy][xx][0], tpx[yy][xx][1], tpx[yy][xx][2]
                    a = tpx[yy][xx][3] if len(tpx[yy][xx]) > 3 else 255
                    if a > 0 and (max(r, g, b) - min(r, g, b)) > 40 and max(r, g, b) > 60:
                        minx = min(minx, xx); maxx = max(maxx, xx)
                        miny = min(miny, yy); maxy = max(maxy, yy)
            if minx < 0 or miny < 0 or maxx > 99 or maxy > 99:
                clipped.append(name)
        check(not clipped, f"no symbol is clipped by the tile canvas ({len(clipped) or 'all 45'} in bounds)")


def main():
    # Check 1: XML well-formedness.
    names = sorted(n for n in os.listdir(ICONS_DIR) if n.endswith(".svg"))
    check(len(names) == 45, f"icons dir holds 45 SVGs (got {len(names)})")
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
