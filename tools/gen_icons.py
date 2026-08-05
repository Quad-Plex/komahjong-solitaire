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

Design goals (locked in by the 2.5D redesign):
  1. The bevel is an OUTWARD extension of the tile, not an inset. The tile
     face fills (nearly) the full 100x140 portrait canvas (matching the
     board's 1.4 aspect) and the depth bevels hang off its right and bottom
     sides, so a tile with visible bevels is slightly LARGER than a bare
     face. This is the outside of the tile that is visible. The 3D step is
     produced by the BOARD: it shifts each layer up-left by exactly the bevel
     thickness (mahjongboard.lua tilePos subtracts layer*bevel), so a raised
     tile's bevels land exactly on the edges of the tile directly beneath it
     and the bevel never overlaps the tiles to its east/south. The artwork
     only supplies the outward bevel bands; the shift is a board concern.
  2. Every variant shares one 110x154 viewBox: the face at [0,0]-[100,140]
     and the bevels in the extension bands [100,110]x[0,154] (right side) and
     [0,100]x[140,154] (base). A variant simply leaves the absent bevel band
     transparent, so the board can give every tile widget the same dimen and
     the face is always anchored at the widget's top-left. The board sets the
     widget dimen to (tw + bw, th + bh) with bw/bh = 10% of the tile size, so
     the rendered face is exactly the grid pitch.
  3. The face carries a thin gray outline (FACE_STROKE, ~1 viewBox unit)
     drawn inside the face box, so adjacent same-layer tiles — which have no
     bevels between them — show a crisp ~1px grid line at every seam instead
     of an invisible white-on-white border.
  4. Bevels appear ONLY on exposed edges. Each kind ships in four variants
     (base / "_nb" / "_nr" / "_n", see VARIANTS): a same-layer neighbour to
     the right or below blocks that bevel (it would read as a fake seam inside
     an otherwise solid layer). The board picks the variant per tile via
     MahjongLogic.iconForTile, which also handles the Turtle's half-grid
     head/tail (an edge covered by two half-overlapping neighbours has no
     bevel either).
  5. Symbols fill much of the face: larger glyphs, less inner padding.
     Low-count tiles use larger symbols (authentic mahjong style: the single
     bamboo is a large stick, the 1-dot is a big dot).
"""
import argparse
import os

# mahjong.koplugin/icons, resolved relative to this script (tools/).
ICONS_DIR = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "mahjong.koplugin", "icons"))

# Canvas: face + outward bevels. The FACE is [0,0]-[100,140] (portrait,
# matching the board's TILE_ASPECT); the bevel bands hang OFF the face, so a
# tile with visible bevels is larger than a bare face. Every variant uses the
# SAME 110x154 viewBox — absent bevels are just left transparent — which lets
# the board give every tile widget one uniform dimen.
VB_W, VB_H = 110, 154
FACE_W, FACE_H = 100, 140

# The tile body: the white face fills the whole 100x140 area and the two
# depth-bevel bands extend OUTSIDE it — a 10-wide right side and a 14-tall
# base (10% of each axis). They are drawn first so the face sits on top.
#
# The face is outlined by a medium-gray ring (FACE_STROKE, ~1 viewBox unit —
# about 1 device px on the target screen) drawn INSIDE the face box, so it
# never bleeds into the bevel bands or beyond the widget. Two adjacent
# same-layer tiles (which have no bevels between them) each draw half of this
# ring, giving a crisp ~1px "grid" line at every seam instead of a pure-white
# hairline — without it, internal seams of a solid layer are invisible on
# e-ink. The tone matches the right-side bevel so an exposed edge still reads
# as one continuous tile side (face -> border -> bevel).
#
# Bevel variants: a tile's right/bottom bevel is only drawn when that edge is
# exposed — a same-layer neighbour to the right/below blocks it (the bevel
# would read as a fake seam inside an otherwise solid layer). Each kind is
# generated in four variants (see VARIANTS): base (both bevels), "_nb" (no
# bottom bevel), "_nr" (no right bevel), "_n" (neither). The bevel band is
# transparent on the hidden side, so hidden edges mesh seamlessly with the
# neighbouring tile.
#
# The step between layers comes from the board, not the artwork: mahjongboard
# shifts each layer up-left by exactly the bevel thickness, so a raised tile's
# bevels land exactly on the edges of the tile directly beneath it (the bevel
# never overlaps the tiles to its east/south). This artwork only supplies the
# outward bevel bands. Darker fills than the original pale grays give the
# tiles contrast on e-ink (white face -> light right side -> dark base).
FACE_BEVEL_RIGHT = '<rect x="100" y="0" width="10" height="154" fill="#78909c"/>'
FACE_BEVEL_BOTTOM = '<rect x="0" y="140" width="100" height="14" fill="#546e7a"/>'

# Corner-diagonal bevels: when BOTH bevels are exposed (base variant) the two
# side faces meet along a DIAGONAL line from the face's bottom-right corner
# (100,140) to the widget's bottom-right corner (110,154). That diagonal is the
# block's front-right vertical edge as seen from the bottom-right camera, so the
# corner reads as one receding point (the implied rectangular box) instead of a
# square L where the right face flatly covers the corner. The upper-left
# triangle of the corner square belongs to the right face (medium #78909c), the
# lower-right to the base/front face (dark #546e7a). Single-bevel variants
# (only one exposed edge) keep plain rectangles — a lone strip has no other face
# to meet, so its outer edge stays straight.
FACE_BEVEL_RIGHT_CORNER = '<path d="M100 0 L110 0 L110 154 L100 140 Z" fill="#78909c"/>'
FACE_BEVEL_BOTTOM_CORNER = '<path d="M0 140 L100 140 L110 154 L0 154 Z" fill="#546e7a"/>'

# Face outline: thin medium-gray ring inside the face box, ~1 viewBox unit
# (~1 device px on the target screen). Same tone as the side bevel. See the
# tile-body comment above.
FACE_STROKE = 1
FACE_STROKE_COLOR = "#78909c"


def face(bottom=True, right=True):
    parts = []
    if right and bottom:
        parts.append(FACE_BEVEL_RIGHT_CORNER)
        parts.append(FACE_BEVEL_BOTTOM_CORNER)
    else:
        if right:
            parts.append(FACE_BEVEL_RIGHT)
        if bottom:
            parts.append(FACE_BEVEL_BOTTOM)
    s = FACE_STROKE
    parts.append(f'<rect x="{s / 2:.1f}" y="{s / 2:.1f}" '
                 f'width="{FACE_W - s}" height="{FACE_H - s}" rx="3" '
                 f'fill="#ffffff" stroke="{FACE_STROKE_COLOR}" stroke-width="{s}"/>')
    return "".join(parts)


def fnum(x):
    s = ("%.2f" % x).rstrip("0").rstrip(".")
    return s


def rect(x, y, w, h, rx, fill):
    return f'<rect x="{fnum(x)}" y="{fnum(y)}" width="{fnum(w)}" height="{fnum(h)}" rx="{fnum(rx)}" fill="{fill}"/>'


def circle(cx, cy, r, fill):
    return f'<circle cx="{fnum(cx)}" cy="{fnum(cy)}" r="{fnum(r)}" fill="{fill}"/>'


def path(d, stroke, w=8, fill="none", lc="round", lj="round"):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{fnum(w)}" stroke-linecap="{lc}" stroke-linejoin="{lj}"/>'


def svg(body, bottom=True, right=True):
    # Symbols are authored in 100x100 space; shift them so their center lands
    # on the face center (50, 70) in viewBox units.
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{VB_W}" height="{VB_H}" '
            f'viewBox="0 0 {VB_W} {VB_H}">{face(bottom, right)}'
            f'<g transform="translate(0,20)">{body}</g></svg>')


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


# Bevel variants per kind, in the order the board expects (see
# MahjongLogic.iconForTile): "" both bevels, "_nb" no bottom, "_nr" no right,
# "_n" neither. base name <-> (bottom, right).
VARIANTS = [
    ("",     True,  True),
    ("_nb",  False, True),
    ("_nr",  True,  False),
    ("_n",   False, False),
]


def generate():
    """Return {filename: svg_contents} for every icon the plugin ships."""
    written = {}
    for n in range(1, 10):
        for suffix, bottom, right in VARIANTS:
            written[f"b{n}{suffix}.svg"] = svg("".join(bamboo(cx, cy, w, h) for cx, cy, w, h in B[n]), bottom, right)
        for suffix, bottom, right in VARIANTS:
            written[f"d{n}{suffix}.svg"] = svg("".join(dot(cx, cy, r) for cx, cy, r in D[n]), bottom, right)
        for suffix, bottom, right in VARIANTS:
            written[f"c{n}{suffix}.svg"] = svg("".join(path(d, "#c62828") for d in C[n]), bottom, right)
    for name, strokes in WINDS.items():
        for suffix, bottom, right in VARIANTS:
            written[f"{name}{suffix}.svg"] = svg("".join(path(d, "#1565c0") for d in strokes), bottom, right)
    for name, body in DRAGONS.items():
        if isinstance(body, list):
            body = "".join(body)
        for suffix, bottom, right in VARIANTS:
            written[f"{name}{suffix}.svg"] = svg(body, bottom, right)
    for n in range(1, 5):
        for suffix, bottom, right in VARIANTS:
            written[f"flower{n}{suffix}.svg"] = svg("".join(FLOWERS[n]), bottom, right)
        for suffix, bottom, right in VARIANTS:
            written[f"season{n}{suffix}.svg"] = svg("".join(SEASONS[n]), bottom, right)
    # Overlays + empty face (no face rect). Portrait, matching the tile box so
    # the highlight covers the whole face.
    written["select.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" '
                             f'viewBox="0 0 100 140"><rect x="1" y="1" width="98" height="138" rx="4" '
                             f'fill="none" stroke="#263238" stroke-width="5"/></svg>')
    written["hint.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" '
                           f'viewBox="0 0 100 140">'
                           f'<path d="M6 18 L6 6 L18 6" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/>'
                           f'<path d="M82 6 L94 6 L94 18" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/>'
                           f'<path d="M94 122 L94 134 L82 134" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/>'
                           f'<path d="M18 134 L6 134 L6 122" fill="none" stroke="#263238" stroke-width="6" '
                           f'stroke-linecap="round" stroke-linejoin="round"/></svg>')
    written["empty.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" '
                            'viewBox="0 0 100 140"/>')
    # Toolbar icons (hint = lightbulb, shuffle = crossing arrows), imported from
    # Google's Material Design icon set (24px, flat fills). The toolbar buttons
    # in main.lua reference them as "mahjong/lightbulb" / "mahjong/shuffle";
    # installIconsIfNeeded() ships them to the KOReader icons dir like the tiles.
    written["lightbulb.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                                'viewBox="0 0 24 24" width="24">'
                                '<path d="M0 0h24v24H0z" fill="none"/>'
                                '<path d="M9 21c0 .5.4 1 1 1h4c.6 0 1-.5 1-1v-1H9v1zm3-19C8.1 2 5 5.1 5 9'
                                'c0 2.4 1.2 4.5 3 5.7V17c0 .5.4 1 1 1h6c.6 0 1-.5 1-1v-2.3c1.8-1.3 3-3.4 '
                                '3-5.7 0-3.9-3.1-7-7-7z"/></svg>')
    written["shuffle.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                              'viewBox="0 0 24 24" width="24">'
                              '<path d="M0 0h24v24H0z" fill="none"/>'
                              '<path d="M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 '
                              '2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 '
                              '3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z"/></svg>')
    # Quit X (title bar): KOReader's stock "close" icon is a thin 1.5px-stroke
    # X; this is a heavier 4px rounded X, full-bleed in the 24x24 canvas. It is
    # the title bar's right icon ("mahjong/close"), see createStatusBar().
    written["close.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
                            'viewBox="0 0 24 24">'
                            '<path d="M5 5 L19 19" fill="none" stroke="#000000" stroke-width="4" '
                            'stroke-linecap="round"/>'
                            '<path d="M19 5 L5 19" fill="none" stroke="#000000" stroke-width="4" '
                            'stroke-linecap="round"/></svg>')
    # HUD chip icons (hudbar.lua): Material Design glyphs — "layers" for the
    # Pairs-remaining chip and a star for the Score chip. The Free-pairs chip
    # reuses the lightbulb shipped above. Like the toolbar icons these are
    # imported 24x24 flat-fill paths.
    written["hud_pairs.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                                'viewBox="0 0 24 24" width="24">'
                                '<path d="M0 0h24v24H0z" fill="none"/>'
                                '<path d="M11.99 18.54l-7.37-5.73L3 14.07l9 7 9-7-1.63-1.27-7.38 '
                                '5.74zM12 16l7.36-5.73L21 9l-9-7-9 7 1.63 1.27L12 16z"/></svg>')
    written["hud_score.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                                'viewBox="0 0 24 24" width="24">'
                                '<path d="M0 0h24v24H0z" fill="none"/>'
                                '<path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 '
                                '9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>')
    # Warning triangle (US-09 feedback band): Material Design "warning" glyph,
    # shown on the far left of the flash band while a feedback message is up.
    written["warning.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                              'viewBox="0 0 24 24" width="24">'
                              '<path d="M0 0h24v24H0z" fill="none"/>'
                              '<path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>')
    # Stats button (US-13): Material Design "assessment" bar chart, the HUD's
    # left button (next to the settings gear) that opens the stats screen.
    written["stats.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                            'viewBox="0 0 24 24" width="24">'
                            '<path d="M0 0h24v24H0z" fill="none"/>'
                            '<path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 '
                            '2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z"/></svg>')
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
