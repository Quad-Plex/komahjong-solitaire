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

Design goals (locked in by the 2.5D redesign + the v2 traditional-art pass):
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
  3. E-INK-FRIENDLY 3-TONE PALETTE. A real mahjong set uses green bamboo, red
     中, blue coins, etc.; on a grayscale e-ink screen those colors drop to
     indistinguishable mid-grays. The redesign keeps silhouettes in FULL
     BLACK (#000000) and adds beauty via a restricted second-language of
     grays used ONLY as detail inside black silhouettes (so they never
     compete with the face-stroke / bevel tones, which stay ~#78909c):
       #1a1a1a  near-black — strong interior detail (bird body, coin inner
                 band) that reads clearly but is plainly darker than the
                 bevel grays.
       #3a3a3a  mid-dark  — hatch / fill tonality for the "green" bamboo
                 tubes; stays under check_icons.py's "<60 = symbol" clip
                 threshold, so the QA still pegs it as a real ink pixel.
       white    negative space inside silhouettes (coin holes, bird eye,
                 hollow rings), never as a face background (that stays #fff).
     Hues are communicated by SHAPE complexity + density, not by color, so
     suits stay distinct in monochrome.
  4. Bevels appear ONLY on exposed edges. Each kind ships in four variants
     (base / "_nb" / "_nr" / "_n", see VARIANTS): a same-layer neighbour to
     the right or below blocks that bevel (it would read as a fake seam inside
     an otherwise solid layer). The board picks the variant per tile via
     MahjongLogic.iconForTile, which also handles the Turtle's half-grid
     head/tail (an edge covered by two half-overlapping neighbours has no
     bevel either).
  5. TRADITIONAL RECOGNIZABILITY (v2). The first draft drew abstract count
     sticks / line numerals; the v2 set uses real mahjong iconography so a
     player instantly reads it as mahjong and not as dots-and-sticks:
       - Characters 萬子 1..9 show the Chinese numeral 一..九 above the 萬
         character (the suit name), both rendered from Droid Sans Fallback
         outlines (Apache-2.0), baked into this generator via GLYPHS / the
         tools/extract_glyphs.py helper. No runtime font dependency.
       - Winds 東南西北 show the actual wind characters centered.
       - Dragons 中/發/白 show the dragon characters inside an ornamental
         double frame (the traditional "badge" form, and a quick way to tell
         them apart from the winds at a glance).
       - Dots 筒子 are real Chinese COINS (outer ring + inner ring + square
         center hole), 1-tong a large medallion with extra concentric rings.
       - Bamboo 索子 are real bamboo tubes (rounded body + dark node joints
         + a faint interior highlight line per internode), with the 1-suo
         being the sparrow (麻雀 — the namesake of the game) perched on a
         stem.
       - Flowers 梅蘭竹菊 and seasons 春夏秋冬: numeral 1..4 above the
         flower/season-name character, mirroring the 萬 layout.
  6. Symbols fill much of the face: larger glyphs, less inner padding.
     Low-count tiles use larger symbols (authentic mahjong style).
"""
import argparse
import math
import os
import xml.etree.ElementTree as ET

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
# outward bevel bands. The symbols use the 3-TONE ink palette (above) for
# maximum contrast on e-ink; the bevels keep their gray tones for the 3D
# depth.
FACE_BEVEL_RIGHT = '<rect x="100" y="0" width="10" height="154" fill="#78909c"/>'
FACE_BEVEL_BOTTOM = '<path d="M0 140 L100 140 L100 154 L10 154 Z" fill="#546e7a"/>'

# Corner-diagonal bevels: when BOTH bevels are exposed (base variant) the two
# side faces meet along a DIAGONAL line from the face's bottom-right corner
# (100,140) to the widget's bottom-right corner (110,154). That diagonal is the
# block's front-right vertical edge as seen from the bottom-right camera, so the
# corner reads as one receding point (the implied rectangular box) instead of a
# square L where the right face flatly covers the corner. The upper-left
# triangle of the corner square belongs to the right face (medium #78909c), the
# lower-right to the base/front face (dark #546e7a).
#
# The bottom bevel also carries a mirrored diagonal on its LEFT edge (0,140) to
# (10,154): the board shifts each upper layer up-left by the bevel thickness, so
# a raised tile's bottom bevel is the visible WEST step of the tower, and a
# square corner there breaks the continuous diagonal that the tower's west face
# would otherwise trace down the stack (right side diagonal, then left-side
# diagonal of the tile below, and so on). Mirrored diagonals keep the stacking
# edge crisp on the deeper multi-layer boards. Single-bevel variants (only one
# exposed edge) keep the bevel band straight on the covered side: the "_nr"
# bottom bevel's right edge is a seam against a same-layer neighbour's face,
# while its left edge stays a receding corner like the base variant's.
FACE_BEVEL_RIGHT_CORNER = '<path d="M100 0 L110 0 L110 154 L100 140 Z" fill="#78909c"/>'
FACE_BEVEL_BOTTOM_CORNER = '<path d="M0 140 L100 140 L110 154 L10 154 Z" fill="#546e7a"/>'

# Face outline: thin medium-gray ring inside the white face box, ~1 viewBox
# unit (~1 device px on the target screen). Same tone as the side bevel. See
# the tile-body comment above.
FACE_STROKE = 1
FACE_STROKE_COLOR = "#78909c"
FACE_COLOR = "#ffffff"

# v2 ink palette (see design goal 3 near the top). Stay under
# check_icons.py's "symbol pixel = max(r,g b)<60" threshold so the clip check
# still recognizes these as real ink, not face-stroke / bevel grays.
INK_BLACK = "#000000"     # dominant silhouettes, characters, node joints
INK_DARK  = "#1a1a1a"     # strong interior detail (bird body, coin inner band)
INK_MID   = "#3a3a3a"     # mid-dark fill (the "green" bamboo tubes)


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
                 f'fill="{FACE_COLOR}" stroke="{FACE_STROKE_COLOR}" stroke-width="{s}"/>')
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


def ellipse(cx, cy, rx, ry, fill):
    return f'<ellipse cx="{fnum(cx)}" cy="{fnum(cy)}" rx="{fnum(rx)}" ry="{fnum(ry)}" fill="{fill}"/>'


def fill_path(d, fill):
    return f'<path d="{d}" fill="{fill}"/>'


def svg(body, bottom=True, right=True):
    # Symbols are authored in 100x120 space (the face minus a 20px top inset),
    # then translated DOWN by 20 viewBox units so their box aligns with the
    # face's lower band (the top inset balances the bottom bevel band's 14px
    # + a hair of breathing room, keeping art optically centered).
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{VB_W}" height="{VB_H}" '
            f'viewBox="0 0 {VB_W} {VB_H}">{face(bottom, right)}'
            f'<g transform="translate(0,20)">{body}</g></svg>')


# ---------------------------------------------------------------------------
# Baked Han glyph outlines (Droid Sans Fallback, Apache-2.0). Regenerate the
# data block below with `python3 tools/extract_glyphs.py`; keep this block the
# sole source of glyph geometry so the generator stays runtime-font-free. Each
# value: (path_d, xmin, ymin, xmax, ymax) in font-UPM units using a y-UP
# origin. glyph_in_box() flips y to SVG y-down when emitting.
GLYPHS = {}
GLYPHS[("num","1")] = ('M21 112H234V93H21Z', 21,93,234,112)
GLYPHS[("num","2")] = ('M36 178H219V159H36ZM14 19H241V0H14Z', 14,0,241,178)
GLYPHS[("num","3")] = ('M32 188H224V169H32ZM43 102H213V83H43ZM20 14H236V-5H20Z', 20,-5,236,188)
GLYPHS[("num","4")] = ('M233 199V-23H213V-9H43V-23H23V199ZM43 10H213V180H43ZM88 189H107Q107 112 95.5 81.5Q84 51 57 33L47 51Q69 67 78.5 93.5Q88 120 88 189ZM200 69V51L181 49Q156 49 151 53Q143 58 143 71V189H162V75Q162 67 181 67Z', 23,-23,233,199)
GLYPHS[("num","5")] = ('M26 193H230V174H126L112 114H208V7H240V-12H16V7H69L88 95H35V114H92L106 174H26ZM89 7H188V95H108Z', 16,-12,240,193)
GLYPHS[("num","6")] = ('M127 203Q140 183 148 157L128 151Q121 177 107 197ZM19 141H238V122H19ZM90 100 108 90Q69 22 29 -17L13 -3Q61 45 90 100ZM169 100Q212 53 242 2L226 -15Q195 41 153 88Z', 13,-17,242,203)
GLYPHS[("num","7")] = ('M241 142 243 123 110 108V15Q110 9 115.0 7.0Q120 5 160 5Q201 5 209 10Q215 14 218 45L239 39Q235 1 226.0 -7.0Q217 -15 160 -15L103 -13Q89 -8 89 11V106L16 98L13 117L89 125V201H110V128Z', 13,-15,243,201)
GLYPHS[("num","8")] = ('M169 196Q184 58 245 0L232 -24Q202 4 179.0 61.0Q156 118 149 191ZM84 191 104 189Q95 46 27 -24L12 -4Q77 60 84 191Z', 12,-24,245,196)
GLYPHS[("num","9")] = ('M27 157H87L89 207H109L107 157H189V11Q189 2 202.0 2.0Q215 2 219.0 8.0Q223 14 224 44L245 37Q243 6 235.5 -6.0Q228 -18 200 -18Q179 -18 174.0 -13.0Q169 -8 169 6V138H106Q101 69 81.0 35.5Q61 2 24 -23L13 -5Q79 38 86 138H27Z', 13,-23,245,207)
GLYPHS[("wan","_")] = ('M241 207V-23H153L139 -7H71V-23H51V189L53 207H71V189H138L152 207ZM71 6H139V172H71ZM169 6H222V172L169 173V189Q206 188 222 168Z', 13,-23,241,207)
GLYPHS[("wind","east")] = ('M13 189H117V207H136V189H243V171H136V152H218V56H154Q189 23 244 6L232 -17Q173 6 136 50V-23H117V47Q82 6 27 -17L12 2Q67 23 101 56H35V152H117V171H13ZM55 113H117V134H55ZM136 134V113H198V134ZM55 74H117V95H55ZM136 95V74H198V95Z', 12,-23,243,207)
GLYPHS[("wind","south")] = ('M13 183H118V207H138V183H243V164H138V140H228V3Q228 -22 200 -22L171 -20L166 0L199 -2Q209 -2 209 8V122H45V-23H26V140H118V164H13ZM96 117Q109 103 117 88H141L155 118L175 113L162 88H193V70H137V48H199V30H137V-12H118V30H55V48H118V70H62V88H96L80 107Z', 13,-23,243,207)
GLYPHS[("wind","west")] = ('M227 138V-23H207V-4H49V-23H29V138H91V180H15V199H241V180H166V138ZM146 180H111V138H146ZM49 15H207V54L191 53Q161 53 154 57Q146 63 146 77V119H111Q111 74 66 48L54 67Q91 87 91 119H49ZM166 119V82Q166 76 170.0 74.5Q174 73 191 73L207 74V119Z', 15,-23,241,199)
GLYPHS[("wind","north")] = ('M84 205H104V-20H84V35Q56 15 22 0L14 22Q52 39 84 59V127H17V147H84ZM143 205H163V130Q197 147 227 169L240 151Q205 126 163 108V11Q163 3 191 3Q210 3 214.0 5.5Q218 8 220.0 15.0Q222 22 223 50L244 44Q243 5 235.0 -5.5Q227 -16 191 -16Q160 -16 151.5 -11.5Q143 -7 143 4Z', 14,-20,244,205)
GLYPHS[("dragon","red")] = ('M229 169V46H209V62H137V-25H117V62H48V44H28V169H117V208H137V169ZM48 81H117V150H48ZM137 150V81H209V150Z', 28,-25,229,208)
GLYPHS[("dragon","green")] = ('M149 207 160 186Q181 194 198 206L212 190L172 171L186 159Q207 167 224 180L238 165L205 146L246 130L231 112Q151 139 131 202ZM25 200H123V182Q92 130 20 113L13 131L52 144L28 159L42 174L70 154Q88 167 98 182H25ZM42 130H106V74H56L50 54H109Q103 3 94.5 -10.0Q86 -23 68 -23L43 -21L40 -2L67 -4Q81 -4 87 37H26L39 91H86V113H42ZM197 133V102Q197 95 203 95H231V78H200Q178 78 178 96V115H154Q152 82 126 71L113 85Q126 92 130.5 100.5Q135 109 136 133ZM132 40 173 23Q186 34 193 47H125V64H216V50Q206 28 192 14L232 -8L218 -25L176 0Q152 -16 121 -23L111 -4Q137 1 155 11L119 27Z', 13,-25,246,207)
GLYPHS[("dragon","white")] = ('M109 208 132 203 120 174H222V-24H202V-3H54V-23H34V174H97Q106 190 109 208ZM54 97H202V155H54ZM54 16H202V78H54Z', 34,-24,222,208)
GLYPHS[("flower","1")] = ('M18 161H45V207H64V161H90V142H64V129L92 85L79 66L64 100V-23H45V82Q37 55 24 31L10 45Q35 88 43 142H18ZM128 208 149 203 142 185H235V167H133Q121 147 108 135L94 150Q116 174 128 208ZM122 146H229L228 88H245V70H227L224 29H242V12H222Q222 -23 193 -23L170 -21L167 -4L193 -6Q201 -6 203 12H106L116 70H96V88H117ZM138 88H208L209 129H141ZM166 124Q179 117 189 107L177 92L154 112ZM204 29 207 70H136L130 29ZM162 66 185 48 173 33 150 53Z', 10,-23,245,208)
GLYPHS[("flower","2")] = ('M16 195H75V207H96V195H161V207H181V195H241V178H181V167H161V178H96V166H75V178H16ZM235 165V3Q235 -22 214 -22L191 -21L186 -3L211 -4Q217 -4 217 8V107H140V165ZM158 143H217V150H158ZM217 121V129H158V121ZM115 165V107H39V-23H21V165ZM39 143H97V150H39ZM39 121H97V129H39ZM57 98H119V108H137V98H200V85H137V77H193V26H137V23L187 6L175 -11Q159 0 137 8V-20H119V17Q97 -2 62 -14L49 2Q88 12 109 26H64V77H119V85H57ZM82 39H119V64H82ZM99 61Q107 56 112 49L99 41Q95 48 87 54ZM137 64V39H175V64ZM152 61 167 58 157 41 143 46Z', 16,-23,241,195)
GLYPHS[("flower","3")] = ('M153 209 173 205 164 167H242V148H210V1Q209 -23 179 -23L152 -20L148 0L176 -3Q190 -3 190 8V148H158Q142 108 128 88L112 103Q140 146 153 209ZM50 208 70 204 61 167H127V148H88V-23H68V148H55Q39 108 26 90L10 105Q37 146 50 208Z', 10,-23,242,209)
GLYPHS[("flower","4")] = ('M15 189H75V207H96V189H161V207H181V189H241V171H181V155H161V171H96V155H75V171H15ZM54 157 74 153 70 141H230Q230 39 225.0 7.5Q220 -24 197 -24L176 -21L172 -1L195 -4Q203 -4 206.0 11.0Q209 26 211 123H61Q47 97 28 80L14 95Q41 121 54 157ZM165 113 181 103Q167 84 153 73L140 85Q155 98 165 113ZM32 69H107V113H126V69H192V51H126V-20H107V44Q78 7 37 -12L24 5Q62 20 89 51H32ZM72 110Q84 97 92 81L75 72Q68 88 56 102ZM148 42 184 15 172 1Q156 17 137 28Z', 15,-24,241,207)
GLYPHS[("season","1")] = ('M26 190H108L112 209L131 206L128 190H233V173H124L118 155H225V139H111L101 121H241V104H191Q210 83 243 64L227 45L198 70V-23H178V-10H75V-23H55V67L27 47L14 64Q42 83 63 104H14V121H77L89 139H31V155H97L104 173H26ZM90 104 75 86H182L169 104ZM75 47H178V69H75ZM75 8H178V30H75Z', 14,-23,243,209)
GLYPHS[("season","2")] = ('M20 200H235V182H133L127 170H213V67H109L98 56H202V39Q184 20 157 7Q200 -2 241 -3L236 -22Q170 -21 127 -3Q83 -16 24 -23L15 -3L101 9Q81 20 67 33Q45 19 29 14L16 30Q55 44 81 67H41V170H103L109 182H20ZM59 140H194V154H59ZM59 112H194V125H59ZM59 83H194V97H59ZM129 16Q159 25 175 39H88Q106 25 129 16Z', 15,-23,241,200)
GLYPHS[("season","3")] = ('M13 140H52V173L21 166L14 184Q59 192 96 208L105 191L71 179V140H107V122H71V117L106 75L93 57L71 91V-23H52V77Q40 47 21 22L7 39Q35 75 49 122H13ZM166 207H186L184 150L183 125L185 114Q207 136 219 160L236 146Q218 116 191 92Q207 30 247 -7L230 -23Q193 15 176 78Q166 22 113 -23L99 -7Q136 20 151.0 62.0Q166 104 166 207ZM126 152 145 147Q142 110 128 79L111 87Q123 120 126 152Z', 7,-23,247,208)
GLYPHS[("season","4")] = ('M94 210 113 204 100 182H205V165Q184 133 155 112Q194 94 244 83L234 63Q183 76 133 100Q87 76 24 66L12 85Q72 94 111 112L68 144L36 118L19 131Q71 167 94 210ZM80 158Q103 140 133 124Q161 141 178 164H86ZM100 78Q150 67 185 51L172 32Q139 48 91 60ZM57 30Q143 16 202 -4L189 -23Q132 -3 48 12Z', 12,-23,244,210)


def glyph_in_box(key, tx, ty, tw, th, fill=INK_BLACK, weight=0.0):
    """Place a baked GLYPH into a target box (contain + center) in the
    symbol-space (the inner 100x120 box that svg() offsets by +20y).

    Font paths use a y-UP origin; we flip y to SVG y-down by emitting the
    glyph inside a `<g transform="translate(tx,sy) scale(s,-s)">`. The
    translate compensates for both the flip and the glyph's bounding box:
      screen_x = s * font_x + tx_screen     where tx_screen = px - s*xmin
      screen_y = -s * font_y + ty_screen    where ty_screen = py + s*ymin
    Font y is UP; we flip y to SVG y-down via `scale(s,-s)`. With that flip:
      screen_x = s*font_x + ox
      screen_y = -s*font_y + oy
    We want the glyph's box top (font y = ymax, on the screen that's the
    SMALLER screen-y) to land at the target box top `py`, and the glyph's
    box bottom (font y = ymin, larger screen-y post-flip) at `py+ph`. Solve:
      -s*ymax + oy = py      ->      oy = py + s*ymax
      check:  -s*ymin + oy  = -s*ymin + py + s*ymax = py + s*gh = py+ph. ok.
    So `ty_screen = py + s*ymax` (NOT ymin — using ymin pushes everything up
    by th, which is the bug that dumped characters out the top of the tile).

    `weight` adds an emboldening stroke (same color as `fill`) of the given
    font-units thickness to counter the thin strokes the font ships with at
    small render sizes — used only for the 萬子 numeral characters, whose
    Droid-Sans-Fallback outlines read too fine on e-ink at tile scale. The
    stroke is in the glyph's own coordinate system, so 2.0 font-units ≈ 1
    pixel at the rendered tile size.
    """
    d, xmin, ymin, xmax, ymax = GLYPHS[key]
    gw, gh = xmax - xmin, ymax - ymin
    if gw <= 0 or gh <= 0:
        return ""
    s = min(tw / gw, th / gh)         # contain
    pw, ph = s * gw, s * gh
    px = tx + (tw - pw) / 2            # center inside target box
    py = ty + (th - ph) / 2
    tx_screen = px - s * xmin
    ty_screen = py + s * ymax
    if weight > 0.0:
        path_el = (f'<path d="{d}" fill="{fill}" stroke="{fill}" '
                   f'stroke-width="{fnum(weight)}" stroke-linejoin="round"/>')
    else:
        path_el = f'<path d="{d}" fill="{fill}"/>'
    return (f'<g transform="translate({fnum(tx_screen)},{fnum(ty_screen)}) '
            f'scale({fnum(s)},{fnum(-s)})">{path_el}</g>')


# ---------------------------------------------------------------------------
# BAMBOO (索子) — real bamboo tubes with node joints (b2..b9); the 1-suo is
# the sparrow 麻雀 (the bird the game is named for) perched on a stem. The
# "green" tone of the bamboo is encoded as INK_MID fill inside a black tube
# outline, with thin black node bands at the internode joints and a faint
# INK_DARK highlight stripe per tube — readable as ink on e-ink (all <#60)
# but visually richer than a flat black stick.

def bamboo_tube(cx, cy, w, h):
    """One bamboo internode tube: black rounded outline + INK_MID body
    + 2 black node-ring bands at the 1/3 and 2/3 heights + a faint INK_DARK
    vertical highlight stripe off-center."""
    x = cx - w / 2
    y = cy - h / 2
    parts = [rect(x, y, w, h, w * 0.30, INK_BLACK),                # outline
             rect(x + 1.4, y + 1.4, w - 2.8, h - 2.8, w * 0.25, INK_MID)]  # body
    band_y1 = y + h * 0.30
    band_y2 = y + h * 0.70
    parts.append(rect(x - 0.6, band_y1 - 1.6, w + 1.2, 3.2, 1.4, INK_BLACK))
    parts.append(rect(x - 0.6, band_y2 - 1.6, w + 1.2, 3.2, 1.4, INK_BLACK))
    # Slim highlight stripe so the tube doesn't read as a flat blob.
    parts.append(rect(x + w * 0.18, y + h * 0.18, w * 0.18, h * 0.64,
                      w * 0.09, INK_DARK))
    return "".join(parts)


# Bamboo-tube arrangements for b1..b9. Each entry is a list of (cx, cy, w, h)
# tubes laid out in the inner 100x120 box. The count patterns follow the
# classic mahjong tile arrangements (1/2/3-in-a-row, 2x2 + center, 2x3, etc.).
# 1-suo is a single big bamboo stick (the simplest 1-tile form); the sparrow
# variant was tried and dropped — a plain stick reads cleaner on e-ink.
# 8-suo uses a 4-4 top/bottom row (instead of 2x4 columns) so it reads
# plainly distinct from 6-suo's 2x3.
# All arrangements center at symbol-space y=50 (viewBox y=70 = face center).
# Row gaps exceed tube heights so adjacent sticks never touch.
B = {
    1: [(50, 50, 28, 102)],
    2: [(32, 50, 22, 78), (68, 50, 22, 78)],
    3: [(24, 50, 18, 80), (50, 50, 18, 80), (76, 50, 18, 80)],
    4: [(32, 22, 20, 44), (68, 22, 20, 44),
        (32, 78, 20, 44), (68, 78, 20, 44)],
    5: [(30, 18, 18, 34), (70, 18, 18, 34),
        (50, 50, 18, 34),
        (30, 82, 18, 34), (70, 82, 18, 34)],
    6: [(31, 16, 17, 28), (69, 16, 17, 28),
        (31, 50, 17, 28), (69, 50, 17, 28),
        (31, 84, 17, 28), (69, 84, 17, 28)],
    7: [(31, 16, 17, 28), (69, 16, 17, 28),
        (31, 50, 17, 28), (50, 50, 17, 28), (69, 50, 17, 28),
        (31, 84, 17, 28), (69, 84, 17, 28)],
    8: [(20, 22, 15, 40), (40, 22, 15, 40), (60, 22, 15, 40), (80, 22, 15, 40),
        (20, 78, 15, 40), (40, 78, 15, 40), (60, 78, 15, 40), (80, 78, 15, 40)],
    9: [(24, 16, 16, 28), (50, 16, 16, 28), (76, 16, 16, 28),
        (24, 50, 16, 28), (50, 50, 16, 28), (76, 50, 16, 28),
        (24, 84, 16, 28), (50, 84, 16, 28), (76, 84, 16, 28)],
}


def bamboo_body(n):
    return "".join(bamboo_tube(cx, cy, w, h) for cx, cy, w, h in B[n])


# ---------------------------------------------------------------------------
# DOTS (筒子) — real Chinese COINS: outer black ring + white band + black
# inner ring + square center hole. 1-tong is a large medallion with extra
# concentric rings and four small "pearl" pips at the cardinal points (the
# ornate "yang" medallion pattern). 2..9 stay readable as small coins in the
# same count layouts as the bamboo.

def coin(cx, cy, r):
    """One Chinese coin: outer black ring, white gap, black inner ring,
    white square hole in the middle. r is the OUTER radius."""
    parts = [circle(cx, cy, r, INK_BLACK),                   # outer
             circle(cx, cy, r * 0.72, FACE_COLOR),           # white band
             circle(cx, cy, r * 0.54, INK_BLACK),            # inner ring
             circle(cx, cy, r * 0.30, FACE_COLOR)]           # white hole-ring
    s = r * 0.42                                              # square hole
    parts.append(rect(cx - s / 2, cy - s / 2, s, s, 0, INK_BLACK))
    return "".join(parts)


def coin_medallion(cx, cy, r):
    """The 1-tong: a large ornate medallion — three concentric rings + the
    square hole + four pearl pips at N/S/E/W between the outer rings."""
    parts = [circle(cx, cy, r, INK_BLACK),                   # outer rim
             circle(cx, cy, r * 0.86, FACE_COLOR),           # white moat
             circle(cx, cy, r * 0.72, INK_BLACK),            # ring 2
             circle(cx, cy, r * 0.52, FACE_COLOR),           # white moat
             circle(cx, cy, r * 0.38, INK_BLACK),            # ring 3 / hub
             circle(cx, cy, r * 0.24, FACE_COLOR)]           # hub inset
    s = r * 0.30
    parts.append(rect(cx - s / 2, cy - s / 2, s, s, 0, INK_BLACK))   # hole
    # four pearl pips on the outer moat (N/E/S/W).
    for dx, dy in [(0, -r * 0.79), (r * 0.79, 0), (0, r * 0.79), (-r * 0.79, 0)]:
        parts.append(circle(cx + dx, cy + dy, r * 0.09, FACE_COLOR))
    return "".join(parts)


D = {
    1: None,
    2: [(28, 50, 21), (72, 50, 21)],
    3: [(18, 50, 18), (50, 50, 18), (82, 50, 18)],
    4: [(28, 22, 18), (72, 22, 18), (28, 78, 18), (72, 78, 18)],
    5: [(26, 18, 16), (74, 18, 16), (50, 50, 16), (26, 82, 16), (74, 82, 16)],
    6: [(27, 18, 16), (73, 18, 16), (27, 50, 16), (73, 50, 16), (27, 82, 16), (73, 82, 16)],
    7: [(27, 18, 15), (73, 18, 15),
        (27, 50, 15), (50, 50, 15), (73, 50, 15),
        (27, 82, 15), (73, 82, 15)],
    8: [(30, 12, 12), (70, 12, 12), (30, 38, 12), (70, 38, 12),
        (30, 64, 12), (70, 64, 12), (30, 90, 12), (70, 90, 12)],
    9: [(20, 18, 14), (50, 18, 14), (80, 18, 14),
        (20, 50, 14), (50, 50, 14), (80, 50, 14),
        (20, 82, 14), (50, 82, 14), (80, 82, 14)],
}


def dot_body(n):
    if n == 1:
        return coin_medallion(50, 50, 28)
    return "".join(coin(cx, cy, r) for cx, cy, r in D[n])


# ---------------------------------------------------------------------------
# CHARACTERS (萬子) 1..9. A single large Chinese numeral 一..九 centered on
# the face. Traditional mahjong tiles also stamp the suit-name 萬 below the
# numeral, but at e-ink tile size the second character reads as clutter
# rather than recognition, so the v2 set uses just the numeral — large,
# centered, and unmistakably distinct from the dot/bamboo suits. The glyphs
# are baked Han outlines (see GLYPHS) dropped into the inner 100x120 box.

def char_body(n):
    # weight 2.0 thickens every stroke ~1 rendered px so the 萬子 numerals
    # read bold on e-ink (the font's natural outlines are too fine at tile
    # scale). The target box is inset a hair to give the stroke room.
    return glyph_in_box(("num", str(n)), 10, 4, 80, 112, weight=2.0)


# ---------------------------------------------------------------------------
# WINDS East/South/West/North — a compass rose whose four cardinal arms are
# the only ones drawn; the arm pointing in that wind's direction is bold +
# filled black while the other three are thin gray, so the card's "point"
# reads instantly as the wind direction without any Chinese character.
# Center is marked with a small filled hub + a two-tone N tick (the classic
# compass "north arrow" look) so the tile is recognizable AS a compass at a
# glance and the four tiles read as a coherent set.
def compass_arm(cx, cy, length, half_w, direction, active):
    """One diamond arm pointing `direction` (a unit vector (dx, dy)). Active =
    a bold filled-black diamond (slightly longer); inactive = a thin dark-gray
    OUTLINE only, so the active arm dominates by both mass and length (not by a
    tonal difference — on e-ink #1a1a1a vs #000000 reads the same)."""
    nx, ny = direction
    L = length if active else length * 0.78
    tip_x = cx + nx * L
    tip_y = cy + ny * L
    px, py = -ny, nx
    hw = half_w if active else half_w * 0.62
    base_x = cx + px * hw
    base_y = cy + py * hw
    base_x2 = cx - px * hw
    base_y2 = cy - py * hw
    d = (f"M{fnum(cx)} {fnum(cy)} "
         f"L{fnum(base_x)} {fnum(base_y)} "
         f"L{fnum(tip_x)} {fnum(tip_y)} "
         f"L{fnum(base_x2)} {fnum(base_y2)} Z")
    if active:
        return fill_path(d, INK_BLACK)
    # Inactive: white-filled + thin dark outline so it reads as a faint guide,
    # not a second bold arm.
    return f'<path d="{d}" fill="{FACE_COLOR}" stroke="{INK_DARK}" stroke-width="1.6"/>'


def wind_body(name):
    # svg() translates symbol artwork down by 20px; y=50 therefore lands on
    # the face center at viewBox y=70. Keep the enlarged compass inside the
    # 100x120 symbol area (2..98 in both axes).
    cx, cy = 50, 50
    length, half_w = 48, 12
    dirs = {"east": (1, 0), "south": (0, 1), "west": (-1, 0), "north": (0, -1)}
    active = dirs[name]
    parts = []
    for d_name, d in dirs.items():
        parts.append(compass_arm(cx, cy, length, half_w, d, d == active))
    # Hub.
    parts.append(circle(cx, cy, 6, INK_BLACK))
    parts.append(circle(cx, cy, 2.4, FACE_COLOR))
    return "".join(parts)


# ---------------------------------------------------------------------------
# DRAGONS — to keep the three tiles plainly distinct from each other on
# e-ink (where tonal differences don't survive) AND from every other suit, the
# v2 set uses a COUNT convention inside a SHARED round medallion: each dragon
# is the "one-dot / two-dot / three-dot" dragon. The medallion (outer black
# ring + a "dragon-scale" ring of inward-pointing triangles + white interior +
# a faint inner dark ring) marks them as a coherent group of "honors" and
# plainly distinguishes them from the plain-count dot suit; the dot COUNT
# (1/2/3) inside is the disambiguator between the three. The triangular scales
# around the outer ring evoke a mythical dragon's hide — the one thematic cue
# that ties the suit to its name without breaking the count-distinguishes rule.
# Mapping: red = 1 dot, green = 2 dots, white = 3 dots.
def dragon_scales(cx, cy, r_inner, n=24, depth=5):
    """A ring of inward-pointing small black triangles whose bases sit on the
    inner edge of the outer black ring (at radius r_inner) and whose apices
    point toward the center, poking into the white interior. Drawn AFTER the
    white interior so they're visible against white, not swallowed by the
    black ring."""
    parts = []
    for i in range(n):
        a = math.radians(i * (360 / n))
        half = math.radians((360 / n) / 2)
        # Base sits on the ring's inner edge.
        bx1 = cx + math.cos(a - half) * r_inner
        by1 = cy + math.sin(a - half) * r_inner
        bx2 = cx + math.cos(a + half) * r_inner
        by2 = cy + math.sin(a + half) * r_inner
        # Apex points inward.
        apex_x = cx + math.cos(a) * (r_inner - depth)
        apex_y = cy + math.sin(a) * (r_inner - depth)
        parts.append(fill_path(
            f"M{fnum(bx1)} {fnum(by1)} "
            f"L{fnum(bx2)} {fnum(by2)} "
            f"L{fnum(apex_x)} {fnum(apex_y)} Z", INK_BLACK))
    return "".join(parts)


def dragon_medallion():
    """A round honor badge: bold outer black ring + white interior (drawn
    first), then dragon-scale triangles pointing inward from the ring's inner
    edge into the white area so they're visible, then a faint inner dark-gray
    ring. Centered at symbol-space (50, 50) = viewBox y=70 = face center;
    radius 42 fills the face width while staying inside the stroke."""
    cx, cy = 50, 50
    return (circle(cx, cy, 42, INK_BLACK)                  # outer black ring
            + circle(cx, cy, 38, FACE_COLOR)               # white interior
            + dragon_scales(cx, cy, 38, n=24, depth=6)     # scales on white
            + f'<circle cx="{cx}" cy="{cy}" r="31" fill="none" '
              f'stroke="{INK_DARK}" stroke-width="1.5"/>')  # faint inner ring


# Dot counts and layouts inside the medallion, indexed by dragon name. Each
# dot is a plain filled black circle so the COUNT is the only differentiator
# (no tonal tricks that would collapse on e-ink). Centers at cy=50 to match
# the medallion.
_DRAGON_DOTS = {
    "red":   [(50, 50, 15)],
    "green": [(37, 50, 10), (63, 50, 10)],
    "white": [(28, 50, 8), (50, 50, 8), (72, 50, 8)],
}


def dragon_body(name):
    dots = "".join(circle(cx, cy, r, INK_BLACK) for cx, cy, r in _DRAGON_DOTS[name])
    return dragon_medallion() + dots


# ---------------------------------------------------------------------------
# FLOWERS (1..4) — four iconographically distinct plant tiles: Plum /
# Orchid / Tulip / Peony. Each is a clear silhouette arrangement drawn in the
# inner 100x120 box; no Chinese character required to read it. A small index
# pip (1..4 dots) at the bottom tracks the four-tile set so the rule "match
# the two flowers of the same index" still reads from the art alone.
def plum_blossom():
    """1 = Plum: a branch with a 5-petal blossom + two buds."""
    p = []
    # Branch.
    p.append(path("M14 108 Q40 88 70 78 Q84 74 88 60", INK_BLACK, 4))
    # Five-petal blossom near the branch tip.
    bx, by, r = 56, 54, 16
    for ang in range(0, 360, 72):
        a = math.radians(ang)
        px = bx + math.cos(a) * r
        py = by + math.sin(a) * r
        p.append(circle(px, py, 11, INK_BLACK))
    p.append(circle(bx, by, 7, INK_DARK))     # darker center for the blossom
    p.append(circle(bx, by, 3, FACE_COLOR))   # white pip in the middle
    # Two small buds on the branch.
    p.append(circle(34, 92, 6, INK_BLACK))
    p.append(circle(78, 68, 5, INK_BLACK))
    return "".join(p)


def orchid():
    """2 = Orchid: a spray of long, arching, grass-like leaves from a basal
    rosette, with one simple 5-petal bloom on a slim stem."""
    p = []
    # Five long curving leaves from the base.
    leaves = ["M50 108 Q24 78 16 40",
              "M50 108 Q34 78 30 32",
              "M50 108 L50 28",
              "M50 108 Q66 78 70 32",
              "M50 108 Q76 78 84 40"]
    p.extend(path(d, INK_BLACK, 4.5) for d in leaves)
    # Slim flower stem with a small bloom near the top.
    p.append(path("M50 60 Q60 40 62 18", INK_BLACK, 2.5))
    # 5 simple petals as small filled circles around the bloom center.
    fx, fy = 62, 16
    for ang in range(0, 360, 72):
        a = math.radians(ang)
        p.append(circle(fx + math.cos(a) * 7, fy + math.sin(a) * 7, 6, INK_DARK))
    p.append(circle(fx, fy, 3, INK_BLACK))
    return "".join(p)


def lotus():
    """3 = TULIP: a classic cup-shaped bloom on a stem with two leaves. The
    single most universally recognizable flower silhouette, and plainly
    distinct from the plum (5 loose petals on a branch), the orchid (grassy
    arching leaves), and the peony (round scalloped disc)."""
    p = []
    # Cup: outline of three petals — a center pointed petal between two
    # rounded side petals. A single closed shape read as a tulip head.
    p.append(fill_path(
        "M50 16 "                       # top point of the center petal
        "Q60 18 62 32 "                 # right shoulder of the center petal
        "Q68 30 76 38 "                 # outer-right slope -> side petal tip
        "Q70 52 60 56 "                 # bottom of the right side petal
        "Q62 64 50 64 "                 # cup floor, right to center
        "Q38 64 40 56 "                 # cup floor, center to left
        "Q30 52 24 38 "                 # bottom of the left side petal
        "Q32 30 38 32 "                 # outer-left slope up
        "Q40 18 50 16 Z", INK_BLACK))   # left shoulder back to top
    # Inner petal lines (the two seams that separate the 3 petals) in
    # INK_DARK so the cup reads as 3 petals, not one blob.
    p.append(path("M50 18 Q48 36 42 56", INK_DARK, 1.6))
    p.append(path("M50 18 Q52 36 58 56", INK_DARK, 1.6))
    # Stem.
    p.append(path("M50 64 L50 100", INK_BLACK, 4))
    # Two long leaves on the stem — the tulip's signature.
    p.append(fill_path("M50 80 Q24 76 18 92 Q36 84 50 86 Z", INK_BLACK))
    p.append(fill_path("M50 86 Q76 80 82 96 Q64 88 50 92 Z", INK_BLACK))
    return "".join(p)


def peony():
    """4 = PEONY: the "king of flowers," a large round bloom built from
    CONCENTRIC TIERS of ROUNDED petals (not radial spokes), so it can't be
    confused with the radial-spoke sun / snowflake / chrysanthemum designs.
    The silhouette is a solid disc with scalloped edges and a small dark
    hub — plain and round, but the scallops (not spikes) read as petals."""
    p = []
    cx, cy = 50, 54
    # Outer ring of 10 small rounded petals — drawn as a ring of filled
    # circles first to establish the scalloped disc silhouette.
    r_pet = 32
    for i in range(10):
        a = math.radians(i * 36 + 18)
        p.append(circle(cx + math.cos(a) * r_pet, cy + math.sin(a) * r_pet,
                        14, INK_BLACK))
    # Cover the hole in the middle with a disc so the outer ring reads as
    # one bloom, not 9 separate blobs.
    p.append(circle(cx, cy, r_pet + 4, INK_BLACK))
    # Mid-tier: 9 petals offset, slightly smaller, scalloping inward.
    r_mid = 21
    for i in range(9):
        a = math.radians(i * 40)
        p.append(circle(cx + math.cos(a) * r_mid, cy + math.sin(a) * r_mid,
                        11, INK_BLACK))
    # Fill the mid-tier hole too so it doesn't read as a nest of blobs.
    p.append(circle(cx, cy, r_mid + 5, INK_BLACK))
    # Inner tier: 8 small petals in INK_DARK (closer to a petal-junction ring).
    r_in = 11
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        p.append(circle(cx + math.cos(a) * r_in, cy + math.sin(a) * r_in,
                        6, INK_DARK))
    # Center: a small filled dark hub with a white pip.
    p.append(circle(cx, cy, 6, INK_DARK))
    p.append(circle(cx, cy, 2.4, FACE_COLOR))
    return "".join(p)


_FLOWER_ART = {
    1: plum_blossom,
    2: orchid,
    3: lotus,
    4: peony,
}


def index_pips(n):
    """1..4 small dots centered at the bottom of the tile for the flower /
    season sets, so the matching rule (same index) reads from the art."""
    spacing = 12
    x0 = 50 - (n - 1) * spacing / 2
    return "".join(circle(x0 + i * spacing, 110, 2.6, INK_BLACK) for i in range(n))


def flower_body(n):
    return _FLOWER_ART[n]() + index_pips(n)


# ---------------------------------------------------------------------------
# SEASONS (1..4) — Avatar's four elemental sigils, extracted from the source
# SVG in the project root. The source is a four-panel sheet: top-left Fire,
# top-right Water, bottom-left Earth, bottom-right Air. Keeping extraction here
# makes the generated icons use the actual source paths rather than a redraw.
AVATAR_SOURCE = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "1670152831Avatar the last airbender all the four elements.svg"))
AVATAR_PANEL = 3733.0
AVATAR_MARGIN = 10.0
AVATAR_STROKE = 90.0
# The source panels are not optically centered: their sigils sit down and to
# the right, especially the broad Air and Earth marks. These small corrections
# center the rendered ink within the 100x140 face after normalization.
AVATAR_OFFSETS = {
    "fire": (-7.0, -10.5),
    "water": (-6.25, -10.25),
    "earth": (-7.0, -10.0),
    "air": (-7.0, -9.25),
}
AVATAR_PANELS = {
    "fire": (4900.0, 9583.0),
    "water": (11700.0, 9583.0),
    "earth": (4900.0, 16383.0),
    "air": (11700.0, 16383.0),
}
_AVATAR_SIGILS = None


def avatar_sigils():
    """Extract the black sigil paths and normalize them to tile coordinates."""
    global _AVATAR_SIGILS
    if _AVATAR_SIGILS is not None:
        return _AVATAR_SIGILS
    if not os.path.exists(AVATAR_SOURCE):
        raise RuntimeError("Avatar source SVG is missing: " + AVATAR_SOURCE)
    root = ET.parse(AVATAR_SOURCE).getroot()
    ns = "{http://www.w3.org/2000/svg}"
    paths = [e.attrib["d"] for e in root.iter(ns + "path")
             if e.attrib.get("class") == "fil3" and e.attrib.get("d")]
    # The source has two Fire paths, three Water paths, two Earth paths, and
    # one Air path, in panel order.
    groups = {
        "fire": paths[0:2], "water": paths[2:5],
        "earth": paths[5:7], "air": paths[7:8],
    }
    # Leave a clear face-border margin. The source artwork was composed on
    # colored panels and some sigils reach the panel edge; mapping the whole
    # panel to the whole face lets those paths spill into the bevel band.
    scale = (100.0 - 2 * AVATAR_MARGIN) / AVATAR_PANEL
    result = {}
    for name, source_paths in groups.items():
        ox, oy = AVATAR_PANELS[name]
        dx, dy = AVATAR_OFFSETS[name]
        transform = "translate({:.5f},{:.5f}) scale({:.5f})".format(
            AVATAR_MARGIN - ox * scale + dx,
            AVATAR_MARGIN - oy * scale + dy,
            scale)
        result[name] = "".join(
            '<path d="{}" fill="{}" stroke="{}" stroke-width="{}" '
            'stroke-linejoin="round" stroke-linecap="round"/>'.format(
                d, INK_BLACK, INK_BLACK, AVATAR_STROKE)
            for d in source_paths
        )
        result[name] = '<g transform="{}">{}</g>'.format(
            transform, result[name])
    _AVATAR_SIGILS = result
    return result


def season_body(n):
    # Spring = Water, Summer = Earth, Autumn = Fire, Winter = Air.
    # The source sheet's water/air panel labels are reversed relative to the
    # visible sigils, so use the keys that produce the requested visual order.
    elements = ("air", "earth", "fire", "water")
    return avatar_sigils()[elements[n - 1]] + index_pips(n)


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
        body_b = bamboo_body(n)
        body_d = dot_body(n)
        body_c = char_body(n)
        for suffix, bottom, right in VARIANTS:
            written[f"b{n}{suffix}.svg"] = svg(body_b, bottom, right)
            written[f"d{n}{suffix}.svg"] = svg(body_d, bottom, right)
            written[f"c{n}{suffix}.svg"] = svg(body_c, bottom, right)
    for name in ("east", "south", "west", "north"):
        body = wind_body(name)
        for suffix, bottom, right in VARIANTS:
            written[f"{name}{suffix}.svg"] = svg(body, bottom, right)
    for name in ("red", "green", "white"):
        body = dragon_body(name)
        for suffix, bottom, right in VARIANTS:
            written[f"{name}{suffix}.svg"] = svg(body, bottom, right)
    for n in range(1, 5):
        body_f = flower_body(n)
        body_s = season_body(n)
        for suffix, bottom, right in VARIANTS:
            written[f"flower{n}{suffix}.svg"] = svg(body_f, bottom, right)
            written[f"season{n}{suffix}.svg"] = svg(body_s, bottom, right)
    # Blank 2.5D faces are used by the help screen's instructional board. They
    # retain the generated bevel geometry without competing with its markers.
    for suffix, bottom, right in VARIANTS:
        written[f"empty{suffix}.svg"] = svg("", bottom, right)
    # Overlays + empty face (no face rect). Portrait, matching the tile box so
    # the highlight covers the whole face. Dark strokes so the selection / hint
    # highlights read on the (white) tile faces.
    written["select.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" '
                             f'viewBox="0 0 100 140"><rect x="1" y="1" width="98" height="138" rx="4" '
                             f'fill="none" stroke="#263238" stroke-width="5"/></svg>')
    # The hint's bolder variant (US-34): the same corner brackets with a
    # thicker stroke. main.lua's brief hint pulse alternates the overlay between
    # "hint" and "hint_bold", then settles on "hint_bold" for the (now
    # non-timing-out) hint highlight. stroke-width 9 stays inside the 100x140
    # viewBox (the outer corner strokes span at most x 1.5..98.5 / y 1.5..138.5).
    hint_brackets = ('<path d="M6 18 L6 6 L18 6" fill="none" stroke="#263238" stroke-width="{sw}" '
                     'stroke-linecap="round" stroke-linejoin="round"/>'
                     '<path d="M82 6 L94 6 L94 18" fill="none" stroke="#263238" stroke-width="{sw}" '
                     'stroke-linecap="round" stroke-linejoin="round"/>'
                     '<path d="M94 122 L94 134 L82 134" fill="none" stroke="#263238" stroke-width="{sw}" '
                     'stroke-linecap="round" stroke-linejoin="round"/>'
                     '<path d="M18 134 L6 134 L6 122" fill="none" stroke="#263238" stroke-width="{sw}" '
                     'stroke-linecap="round" stroke-linejoin="round"/>')
    written["hint.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" '
                           f'viewBox="0 0 100 140">{hint_brackets.format(sw=6)}</svg>')
    written["hint_bold.svg"] = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="140" '
                                f'viewBox="0 0 100 140">{hint_brackets.format(sw=9)}</svg>')
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
    # Played-count icon: Material Design "sync" glyph — two arrows circling
    # each other, shown beside the per-layout human-win count.
    written["sync.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                            'viewBox="0 0 24 24" width="24">'
                            '<path d="M0 0h24v24H0z" fill="none"/>'
                            '<path d="M12 4V1L8 5l4 4V6c3.31 0 6 2.69 6 6 0 1.01-.25 1.97-.7 2.8l1.46 '
                            '1.46A7.93 7.93 0 0 0 20 12c0-4.42-3.58-8-8-8zm-6 8c0-1.01.25-1.97.7-2.8L5.24 '
                            '7.74A7.93 7.93 0 0 0 4 12c0 4.42 3.58 8 8 8v3l4-4-4-4v3c-3.31 0-6-2.69-6-6z"/>'
                            '</svg>')
    # Quit X (title bar): KOReader's stock "close" icon is a thin 1.5px-stroke
    # X; this is a heavier 4px rounded X, full-bleed in the 24x24 canvas. It is
    # the title bar's right icon ("mahjong/close"), see createStatusBar().
    written["close.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
                            'viewBox="0 0 24 24">'
                            '<path d="M5 5 L19 19" fill="none" stroke="#000000" stroke-width="4" '
                            'stroke-linecap="round"/>'
                            '<path d="M19 5 L5 19" fill="none" stroke="#000000" stroke-width="4" '
                            'stroke-linecap="round"/></svg>')
    # Pause button (US-17): Material Design "pause" glyph — two rounded bars,
    # the HUD's middle left button that opens the pause overlay.
    written["pause.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                            'viewBox="0 0 24 24" width="24">'
                            '<path d="M0 0h24v24H0z" fill="none"/>'
                            '<path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>')
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
    # Trophy (layout picker highscore chip): Material Design "emoji_events"
    # glyph, shown beside the best winning score for a layout.
    written["trophy.svg"] = ('<svg xmlns="http://www.w3.org/2000/svg" height="24" '
                             'viewBox="0 0 24 24" width="24">'
                             '<path d="M0 0h24v24H0z" fill="none"/>'
                             '<path d="M19 5h-2V3H7v2H5c-1.1 0-2 .9-2 2v1c0 2.55 1.92 4.63 4.39 4.94'
                             '.63 1.5 1.98 2.63 3.61 2.96V19H7v2h10v-2h-4v-3.1c1.63-.33 2.98-1.46 '
                             '3.61-2.96C19.08 12.63 21 10.55 21 8V7c0-1.1-.9-2-2-2zM5 8V7h2v3.82'
                             'C5.84 10.4 5 9.3 5 8zm14 0c0 1.3-.84 2.4-2 2.82V7h2v1z"/></svg>')
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
