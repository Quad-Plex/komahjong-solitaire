#!/usr/bin/env python3
"""Render a visual preview of the mahjong board from the committed icons.

Composes the real board layout (same geometry the widget uses) plus a strip
of all 42 tiles into one SVG and rasterizes it, so icon/tile changes can be
eyeballed without booting KOReader.

Requirements: lua (for mahjonglogic geometry), rsvg-convert (for rasterizing).
The preview PNG is a throwaway artifact — it is NOT committed.

Usage:
    python3 tools/preview.py                  # writes preview.png in the cwd
    python3 tools/preview.py --out /path/x.png
    python3 tools/preview.py --icons DIR      # custom icons dir (default repo)
    python3 tools/preview.py --tile 65        # tile width in px (default 65)
"""
import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imgutil import render

REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ICONS_DIR = os.path.join(REPO_ROOT, "mahjong.koplugin", "icons")


def svg_content(icon_dir, name):
    return open(os.path.join(icon_dir, name)).read()


def board_tiles(tile_w):
    """Screen positions of every tile on a seeded board, via mahjonglogic."""
    lua = r'''
package.path = "%s/?.lua;" .. package.path
local Logic = require("mahjonglogic")
local TW = %d
local TH = math.floor(TW * 1.4)
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
local ox = 10 - min_px*TW
local oy = 10 - min_py*TH
local board = Logic.newGame(42)
for _, p in ipairs(Logic.buildLayout()) do
    local kind = Logic.tileAt(board, p.x, p.y, p.layer)
    if kind then
        local px = math.floor(ox + (p.x - g.x_min)*TW + p.layer*offx)
        local py = math.floor(oy + (p.y - g.y_min)*TH - p.layer*offy)
        io.write(string.format("%%s %%d %%d\n", kind, px, py))
    end
end
''' % (os.path.join(REPO_ROOT, "mahjong.koplugin"), tile_w)
    res = subprocess.run(["lua", "-e", lua], capture_output=True, text=True, check=True)
    return [ln.split() for ln in res.stdout.strip().splitlines()]


def main():
    parser = argparse.ArgumentParser(description="Render a mahjong board preview PNG.")
    parser.add_argument("--icons", default=ICONS_DIR, help="icons dir (default: %(default)s)")
    parser.add_argument("--out", default="preview.png", help="output PNG (default: %(default)s)")
    parser.add_argument("--tile", type=int, default=65, help="tile width in px (default: %(default)s)")
    args = parser.parse_args()

    tw = args.tile
    th = int(tw * 1.4)
    tiles = board_tiles(tw)
    W = 10 + 12 * tw + 10
    H = 10 + 7 * th + 10
    strip_cols = 15
    strip_rows = 3
    kinds = []
    for s in "bcd":
        for i in range(1, 10):
            kinds.append(f"{s}{i}")
    kinds += ["east", "south", "west", "north", "red", "green", "white",
              "flower1", "flower2", "flower3", "flower4",
              "season1", "season2", "season3", "season4"]
    tot_h = H + 20 + strip_rows * (th + 2) + 10

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{tot_h}" '
             f'viewBox="0 0 {W} {tot_h}">',
             f'<rect width="{W}" height="{tot_h}" fill="#ffffff"/>']
    for kind, px, py in tiles:
        body = svg_content(args.icons, kind + ".svg")
        body = body.replace('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">', '').replace('</svg>', '')
        parts.append(f'<g transform="translate({px},{py}) scale({tw / 100},{th / 100})">{body}</g>')
    parts.append(f'<g transform="translate(0,{H + 20})">')
    for i, kind in enumerate(kinds):
        col = i % strip_cols
        row = i // strip_cols
        body = svg_content(args.icons, kind + ".svg")
        body = body.replace('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">', '').replace('</svg>', '')
        parts.append(f'<g transform="translate({col * (tw + 2)},{row * (th + 2)}) scale({tw / 100},{th / 100})">{body}</g>')
    parts.append('</g></svg>')

    svg_path = os.path.join(os.path.dirname(os.path.abspath(args.out)) or ".", ".preview.svg")
    with open(svg_path, "w") as f:
        f.write("".join(parts))
    render(svg_path, args.out, W, tot_h)
    os.unlink(svg_path)
    print(f"wrote {args.out} ({W}x{tot_h})")


if __name__ == "__main__":
    main()
