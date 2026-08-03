#!/usr/bin/env python3
"""Regenerate the mahjong tile SVGs (the icons shipped in mahjong.koplugin/).

The SVGs are generated, not hand-edited, so the tile set stays consistent
(one face template, one symbol palette). Edit THIS file to redesign tiles,
then run it. The repo icons are the source of truth on disk; use --check to
verify they still match this generator (e.g. before committing).

Usage:
    python3 tools/gen_icons.py            # rewrite mahjong.koplugin/icons/*.svg
    python3 tools/gen_icons.py --check    # exit 1 if any committed icon is stale
    python3 tools/gen_icons.py --out DIR  # write into a custom directory

Design goals (locked in by the rendering upgrade):
  1. Tile faces fill the whole 100x100 viewBox so adjacent tiles touch
     edge-to-edge (no white margin between tiles or between rows). A thin
     gray stroke on each face delineates individual tiles.
  2. Symbols fill much more of the tile: larger glyphs, less inner padding.
     Low-count tiles use larger symbols (authentic mahjong style: the single
     bamboo is a large stick, the 1-dot is a big dot).
"""
import argparse
import os

# mahjong.koplugin/icons, resolved relative to this script (tools/).
ICONS_DIR = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "mahjong.koplugin", "icons"))

FACE = '<rect x="1" y="1" width="98" height="98" rx="4" fill="#ffffff" stroke="#9e9e9e" stroke-width="2"/>'


def fnum(x):
    s = ("%.2f" % x).rstrip("0").rstrip(".")
    return s


def rect(x, y, w, h, rx, fill):
    return f'<rect x="{fnum(x)}" y="{fnum(y)}" width="{fnum(w)}" height="{fnum(h)}" rx="{fnum(rx)}" fill="{fill}"/>'


def circle(cx, cy, r, fill):
    return f'<circle cx="{fnum(cx)}" cy="{fnum(cy)}" r="{fnum(r)}" fill="{fill}"/>'


def path(d, stroke, w=8, fill="none", lc="round", lj="round"):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{fnum(w)}" stroke-linecap="{lc}" stroke-linejoin="{lj}"/>'


def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
            f'viewBox="0 0 100 100">{FACE}{body}</svg>')


def dot(cx, cy, r=8.5):
    return circle(cx, cy, r, "#1565c0")


def numdots(cx_list, cy=80, r=3):
    return "".join(circle(cx, cy, r, "#424242") for cx in cx_list)


def bamboo(cx, cy, w, h):
    x = cx - w / 2
    y = cy - h / 2
    return (rect(x, y, w, h, w / 2, "#2e7d32")
            + rect(x, cy - 2, w, 4, 2, "#1b5e20"))


# ---------------------------------------------------------------------------
# Bamboo (green sticks with a node band), 1..9. Fewer sticks = bigger sticks.
B = {
    1: [(50, 50, 16, 26)],
    2: [(37, 50, 14, 24), (63, 50, 14, 24)],
    3: [(27, 50, 14, 24), (50, 50, 14, 24), (73, 50, 14, 24)],
    4: [(36, 36, 13, 20), (64, 36, 13, 20), (36, 64, 13, 20), (64, 64, 13, 20)],
    5: [(36, 36, 13, 20), (64, 36, 13, 20), (50, 50, 13, 20), (36, 64, 13, 20), (64, 64, 13, 20)],
    6: [(36, 28, 13, 20), (64, 28, 13, 20), (36, 50, 13, 20), (64, 50, 13, 20), (36, 72, 13, 20), (64, 72, 13, 20)],
    7: [(36, 28, 13, 20), (64, 28, 13, 20), (36, 50, 13, 20), (64, 50, 13, 20), (50, 50, 13, 20), (36, 72, 13, 20), (64, 72, 13, 20)],
    8: [(35, 23, 11, 15), (65, 23, 11, 15), (35, 42, 11, 15), (65, 42, 11, 15), (35, 61, 11, 15), (65, 61, 11, 15), (35, 80, 11, 15), (65, 80, 11, 15)],
    9: [(26, 28, 13, 20), (50, 28, 13, 20), (74, 28, 13, 20), (26, 50, 13, 20), (50, 50, 13, 20), (74, 50, 13, 20), (26, 72, 13, 20), (50, 72, 13, 20), (74, 72, 13, 20)],
}

# ---------------------------------------------------------------------------
# Dots (blue circles), 1..9. Fewer dots = bigger dots.
D = {
    1: [(50, 50, 13)],
    2: [(37, 50, 11), (63, 50, 11)],
    3: [(27, 50, 11), (50, 50, 11), (73, 50, 11)],
    4: [(36, 36, 10), (64, 36, 10), (36, 64, 10), (64, 64, 10)],
    5: [(36, 36, 10), (64, 36, 10), (50, 50, 10), (36, 64, 10), (64, 64, 10)],
    6: [(36, 28, 10), (64, 28, 10), (36, 50, 10), (64, 50, 10), (36, 72, 10), (64, 72, 10)],
    7: [(36, 28, 10), (64, 28, 10), (36, 50, 10), (64, 50, 10), (36, 72, 10), (64, 72, 10), (50, 72, 10)],
    8: [(35, 23, 8.5), (65, 23, 8.5), (35, 42, 8.5), (65, 42, 8.5), (35, 61, 8.5), (65, 61, 8.5), (35, 80, 8.5), (65, 80, 8.5)],
    9: [(26, 28, 8.5), (50, 28, 8.5), (74, 28, 8.5), (26, 50, 8.5), (50, 50, 8.5), (74, 50, 8.5), (26, 72, 8.5), (50, 72, 8.5), (74, 72, 8.5)],
}

# ---------------------------------------------------------------------------
# Characters (red line-art numerals), 1..9
C = {
    1: ["M24 50 L76 50"],
    2: ["M26 38 L74 38", "M26 62 L74 62"],
    3: ["M26 29 L74 29", "M26 50 L74 50", "M26 71 L74 71"],
    4: ["M26 28 L74 28", "M26 72 L74 72", "M26 28 L26 72", "M74 28 L74 72", "M50 28 L50 72"],
    5: ["M28 27 L72 27", "M28 27 L28 60", "M28 46 L72 46", "M28 63 L72 63"],
    6: ["M30 28 L70 28", "M42 28 L26 72", "M58 28 L74 72"],
    7: ["M28 30 L72 30", "M62 30 L62 46 L72 66"],
    8: ["M40 28 L28 72", "M60 28 L72 72"],
    9: ["M28 28 L62 28", "M48 28 L48 62", "M48 62 L64 58"],
}

# ---------------------------------------------------------------------------
# Winds (blue), East/South/West/North
WINDS = {
    "east": ["M50 26 L50 74", "M50 26 L72 26", "M50 50 L70 50", "M50 74 L72 74"],
    "south": ["M30 28 L70 28", "M30 28 L30 52", "M30 52 L70 52", "M70 52 L70 72", "M30 72 L70 72"],
    "west": ["M28 30 L48 50", "M48 50 L28 70", "M72 30 L52 50", "M52 50 L72 70"],
    "north": ["M30 28 L30 72", "M30 30 L70 70", "M70 28 L70 72"],
}

# ---------------------------------------------------------------------------
# Dragons
DRAGONS = {
    "red": rect(26, 26, 48, 48, 4, "#c62828") + rect(46, 26, 8, 48, 0, "#ffffff"),
    "green": [path(d, "#2e7d32") for d in [
        "M50 24 L50 76", "M36 38 L64 38", "M32 50 L68 50", "M36 62 L64 62"]],
    "white": '<rect x="24" y="24" width="52" height="52" rx="4" fill="none" stroke="#1565c0" stroke-width="8"/>',
}

# ---------------------------------------------------------------------------
# Flowers: pink petals around center (50,42), number dots at y=80
FLOWER_CENTER = ('<circle cx="50" cy="42" r="6" fill="#ffffff"/>'
                 '<circle cx="50" cy="42" r="6" fill="none" stroke="#ad1457" stroke-width="2.5"/>')

FLOWERS = {
    1: ([circle(cx, cy, 12, "#ad1457") for cx, cy in
         [(50, 22), (69, 42), (50, 62), (31, 42)]] + [FLOWER_CENTER] + [numdots([50])]),
    2: ([circle(cx, cy, 12, "#ad1457") for cx, cy in
         [(50, 23), (68, 36), (32, 36), (32, 48), (68, 48)]] + [FLOWER_CENTER] + [numdots([45.5, 54.5])]),
    3: ([circle(cx, cy, 12, "#ad1457") for cx, cy in
         [(67, 32), (50, 22), (33, 32), (33, 52), (50, 62), (67, 52)]] + [FLOWER_CENTER] + [numdots([41, 50, 59])]),
    4: ([circle(cx, cy, 12, "#ad1457") for cx, cy in
         [(70, 42), (64, 28), (50, 22), (36, 28), (30, 42), (36, 56), (50, 62), (64, 56)]]
        + [FLOWER_CENTER] + [numdots([36.5, 45.5, 54.5, 63.5])]),
}

# ---------------------------------------------------------------------------
# Seasons: teal spokes/star around center (50,44), number dots at y=80
SEASONS = {
    1: ([path(d, "#00695c", 7) for d in
         ["M50 44 L72 44", "M50 44 L50 66", "M50 44 L28 44", "M50 44 L50 22"]]
        + [numdots([50])]),
    2: ([path(d, "#00695c", 7) for d in
         ["M50 44 L70 44", "M50 44 L60 61", "M50 44 L40 61", "M50 44 L30 44",
          "M50 44 L40 27", "M50 44 L60 27"]]
        + [numdots([45.5, 54.5])]),
    3: ([path(d, "#00695c", 7) for d in
         ["M50 44 L70 44", "M50 44 L64 30", "M50 44 L50 24", "M50 44 L36 30",
          "M50 44 L30 44", "M50 44 L36 58", "M50 44 L50 64", "M50 44 L64 58"]]
        + [numdots([41, 50, 59])]),
    4: ([path("M50 20 L56.5 37.1 L74.7 38 L60.5 49.4 L65.3 67 L50 57 L34.7 67 "
              "L39.5 49.4 L25.3 38 L43.5 37.1 Z", "#00695c", 7)]
        + [numdots([36.5, 45.5, 54.5, 63.5])]),
}


def generate():
    """Return {filename: svg_contents} for every icon the plugin ships."""
    written = {}
    for n in range(1, 10):
        written[f"b{n}.svg"] = svg("".join(bamboo(cx, cy, w, h) for cx, cy, w, h in B[n]))
        written[f"d{n}.svg"] = svg("".join(dot(cx, cy, r) for cx, cy, r in D[n]))
        written[f"c{n}.svg"] = svg("".join(path(d, "#c62828") for d in C[n]))
    for name, strokes in WINDS.items():
        written[f"{name}.svg"] = svg("".join(path(d, "#1565c0") for d in strokes))
    for name, body in DRAGONS.items():
        if isinstance(body, list):
            body = "".join(body)
        written[f"{name}.svg"] = svg(body)
    for n in range(1, 5):
        written[f"flower{n}.svg"] = svg("".join(FLOWERS[n]))
        written[f"season{n}.svg"] = svg("".join(SEASONS[n]))
    # Overlays + empty face (no face rect).
    written["select.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
                             f'viewBox="0 0 100 100"><rect x="1" y="1" width="98" height="98" rx="4" '
                             f'fill="none" stroke="#263238" stroke-width="5"/></svg>')
    written["hint.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
                           f'viewBox="0 0 100 100">'
                           f'<path d="M6 18 L6 6 L18 6" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/>'
                           f'<path d="M82 6 L94 6 L94 18" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/>'
                           f'<path d="M94 82 L94 94 L82 94" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/>'
                           f'<path d="M18 94 L6 94 L6 82" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/></svg>')
    written["empty.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
                            'viewBox="0 0 100 100"/>')
    return written


def build(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, content in sorted(generate().items()):
        with open(os.path.join(out_dir, name), "w") as f:
            f.write(content)
        print(f"wrote {os.path.join(out_dir, name)}")


def check(out_dir):
    failures = 0
    generated = generate()
    for name, content in sorted(generated.items()):
        path = os.path.join(out_dir, name)
        if not os.path.isfile(path):
            print(f"MISSING: {path} (not in the icons dir — run gen_icons.py)")
            failures += 1
        elif open(path).read() != content:
            print(f"STALE:   {path} differs from the generator — run gen_icons.py")
            failures += 1
    return failures


def main():
    parser = argparse.ArgumentParser(description="Regenerate the mahjong tile SVGs.")
    parser.add_argument("--out", default=ICONS_DIR,
                        help="icons directory to write into (default: %(default)s)")
    parser.add_argument("--check", action="store_true",
                        help="verify committed icons match this generator; exit 1 if not")
    args = parser.parse_args()
    if args.check:
        raise SystemExit(1 if check(args.out) else 0)
    build(args.out)


if __name__ == "__main__":
    main()
