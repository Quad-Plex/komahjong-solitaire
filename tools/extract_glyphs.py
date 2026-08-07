#!/usr/bin/env python3
"""Extract SVG path data for the Chinese characters used on the mahjong tiles.

The mahjong tile art needs real Han glyphs (numerals 1-9 + 萬, winds 東南西北,
dragons 中發白, flowers 梅蘭竹菊, seasons 春夏秋冬). Hand-authoring 25 brush
characters by hand is impractical, so this helper reads them from Droid Sans
Fallback (a clean CJK font shipped on most Linuxen, license Apache 2.0) and
prints compact SVG path strings + each glyph's advance width / bbox.

The output is meant to be pasted into tools/gen_icons.py as a baked-in dict so
the generator stays self-contained: no runtime font dependency, no fontTools
import, no TT file path. Re-run this only when you want to change font / glyph
selection.

Usage:
    python3 tools/extract_glyphs.py            # print all glyphs
    python3 tools/extract_glyphs.py --font PATH # use a specific TTF/OTF
"""
import argparse
import os
from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont

# The character sets we ship. Keep these symbols stable; gen_icons.py indexes
# by the labels below (e.g. GLYPHS["num"]["1"]).
NUMERALS = {"1": "一", "2": "二", "3": "三", "4": "四", "5": "五",
            "6": "六", "7": "七", "8": "八", "9": "九"}
WAN = "萬"
WINDS = {"east": "東", "south": "南", "west": "西", "north": "北"}
DRAGONS = {"red": "中", "green": "發", "white": "白"}
FLOWERS = {"1": "梅", "2": "蘭", "3": "竹", "4": "菊"}
SEASONS = {"1": "春", "2": "夏", "3": "秋", "4": "冬"}

DEFAULT_FONT = "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf"


def glyph_path(font, char):
    """Return (path_d, bbox) for a single character from `font`.

    The path is expressed in the glyph's own EM-square coordinates (the font's
    UPM, typically 1000). gen_icons.py scales and translates it onto the tile
    face. `bbox` is (xMin, yMin, xMax, yMax) in glyph units; note fonts use a
    y-up coordinate system (origin at the baseline), so the consumer must flip
    y when embedding into an SVG (y-down) context.
    """
    cmap = font.getBestCmap()
    glyf = font["glyf"]
    name = cmap[ord(char)]
    glyph = glyf[name]

    # Composite glyphs (e.g. 四) reference component glyphs by name, and the
    # pen must resolve them via a glyphSet so the references expand. SVGPathPen
    # takes that glyphSet as its first arg.
    from fontTools.pens.svgPathPen import SVGPathPen
    glyphset = font.getGlyphSet()
    spen = SVGPathPen(glyphset)
    glyph.draw(spen, glyf)
    d = spen.getCommands()
    bbox = glyph.xMin, glyph.yMin, glyph.xMax, glyph.yMax
    return d, bbox


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--font", default=DEFAULT_FONT)
    args = ap.parse_args()

    font = TTFont(args.font)
    groups = [("num", NUMERALS), ("wan", {"_": WAN}),
              ("wind", WINDS), ("dragon", DRAGONS),
              ("flower", FLOWERS), ("season", SEASONS)]
    for label, table in groups:
        for key, ch in table.items():
            d, (xmin, ymin, xmax, ymax) = glyph_path(font, ch)
            print(f"# {label}[{key!r}] U+{ord(ch):04X} {ch}  "
                  f"bbox=({xmin},{ymin})-({xmax},{ymax})  "
                  f"w={xmax-xmin} h={ymax-ymin}")
            print(f"{label}|{key}|{d}")
            print()


if __name__ == "__main__":
    main()