-- Mahjong Solitaire — pure layout definitions + registry (no KOReader deps).
--
-- US-22a: the layout spec tables, the registry, the per-id caches, and the
-- layout-dependent geometry helpers were extracted out of mahjonglogic.lua so
-- each future board (US-23..US-29) is a single-file change: add the spec
-- table + registerLayout call here (and a shape self-test below).
-- mahjonglogic.lua requires this module and re-exports its API, so every
-- existing caller (main.lua, mahjongboard.lua, mahjonglayoutselect.lua, the
-- harnesses) is unchanged.
--
-- Self-test: `lua mahjonglayouts.lua` (or `lua mahjonglayouts.lua --selftest`).

local Layouts = {}

-- Layout registry (US-14) --------------------------------------------------
--
-- The Turtle layout is the canonical GNOME Mahjongg map, with the stepped
-- pyramid and the head/tail protrusions. Coordinates are tile top-left
-- corners; `y` may be fractional (x=0/y=3.5 head, x=13..14/y=3.5 tail,
-- x=6.5/y=3.5 cap) so the silhouette's half-tile overhang is kept:
--   L0: body rows (12+8+10+12+12+10+8+12 = 84) + head (x=0, y=3.5) + tail
--       (x=13..14, y=3.5) = 87
--   L1: block x=4..9,  y=1..6   (6x6  = 36)
--   L2: block x=5..8,  y=2..5   (4x4  = 16)
--   L3: block x=6..7,  y=3..4   (2x2  =  4)
--   L4: single tile x=6.5, y=3.5 (       1)
-- 87 + 36 + 16 + 4 + 1 = 144. Grid extents: x=0..14, y=0..7.
--
-- US-14 generalizes the layout-dependent paths through a registry: every
-- layout is registered as { id=, name=, spec= } and the layout functions take
-- a layout id (defaulting to "turtle" so existing callers and self-tests stay
-- byte-identical). Adding a layout (US-15/16/22, and US-23..29) is a
-- registerLayout call in this module.

local TURTLE_SPEC = {
    -- Layer 0 body rows, bottom row first.
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 0 },
    { layer = 0, kind = "row",   x_min = 3,  x_max = 10, y = 1 },
    { layer = 0, kind = "row",   x_min = 2,  x_max = 11, y = 2 },
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 3 },
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 4 },
    { layer = 0, kind = "row",   x_min = 2,  x_max = 11, y = 5 },
    { layer = 0, kind = "row",   x_min = 3,  x_max = 10, y = 6 },
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 7 },
    -- Head and tail protrusions (half a tile below the y=3 body row).
    { layer = 0, kind = "tile",  x = 0,  y = 3.5 },
    { layer = 0, kind = "row",   x_min = 13, x_max = 14, y = 3.5 },
    -- Upper pyramid blocks.
    { layer = 1, kind = "block", x_min = 4, x_max = 9,  y_min = 1, y_max = 6 },
    { layer = 2, kind = "block", x_min = 5, x_max = 8,  y_min = 2, y_max = 5 },
    { layer = 3, kind = "block", x_min = 6, x_max = 7,  y_min = 3, y_max = 4 },
    { layer = 4, kind = "tile",  x = 6.5, y = 3.5 },
}

-- Spider layout (US-15): the classic Spider board, transcribed from GNOME
-- Mahjongg's `spider` map (4 levels, 144 tiles: 65/53/25/1). The shape is a
-- wide diamond with nested hollow rings stepping up to a single peak tile.
-- Coordinates are on the same half-grid as Turtle (x = 0.5..14.5, y = 0..7);
-- the per-layer point sets use `kind = "set"` because the silhouette is too
-- irregular for rows/blocks to express compactly.
local SPIDER_SPEC = {
    { layer = 0, kind = "set", points = {
        {x = 3, y = 0}, {x = 4, y = 0}, {x = 6.5, y = 0}, {x = 8.5, y = 0}, {x = 11, y = 0}, {x = 12, y = 0},
        {x = 4, y = 1}, {x = 7, y = 1}, {x = 8, y = 1}, {x = 11, y = 1},
        {x = 1, y = 1.5}, {x = 5, y = 1.5}, {x = 10, y = 1.5}, {x = 14, y = 1.5},
        {x = 2, y = 2}, {x = 6, y = 2}, {x = 7, y = 2}, {x = 8, y = 2}, {x = 9, y = 2}, {x = 13, y = 2},
        {x = 3, y = 2.5}, {x = 4, y = 2.5}, {x = 11, y = 2.5}, {x = 12, y = 2.5},
        {x = 5, y = 3}, {x = 6, y = 3}, {x = 7, y = 3}, {x = 8, y = 3}, {x = 9, y = 3}, {x = 10, y = 3},
        {x = 4.5, y = 4}, {x = 5.5, y = 4}, {x = 6.5, y = 4}, {x = 7.5, y = 4},
        {x = 8.5, y = 4}, {x = 9.5, y = 4}, {x = 10.5, y = 4},
        {x = 0.5, y = 4.5}, {x = 1.5, y = 4.5}, {x = 2.5, y = 4.5}, {x = 3.5, y = 4.5},
        {x = 11.5, y = 4.5}, {x = 12.5, y = 4.5}, {x = 13.5, y = 4.5}, {x = 14.5, y = 4.5},
        {x = 5, y = 5}, {x = 6, y = 5}, {x = 7, y = 5}, {x = 8, y = 5}, {x = 9, y = 5}, {x = 10, y = 5},
        {x = 4, y = 6}, {x = 6, y = 6}, {x = 7, y = 6}, {x = 8, y = 6}, {x = 9, y = 6}, {x = 11, y = 6},
        {x = 3, y = 6.5}, {x = 12, y = 6.5},
        {x = 1, y = 7}, {x = 2, y = 7}, {x = 7, y = 7}, {x = 8, y = 7}, {x = 13, y = 7}, {x = 14, y = 7},
    } },
    { layer = 1, kind = "set", points = {
        {x = 3, y = 0}, {x = 4, y = 0}, {x = 6.5, y = 0}, {x = 8.5, y = 0}, {x = 11, y = 0}, {x = 12, y = 0},
        {x = 4, y = 1}, {x = 11, y = 1},
        {x = 1, y = 1.5}, {x = 5, y = 1.5}, {x = 10, y = 1.5}, {x = 14, y = 1.5},
        {x = 2, y = 2}, {x = 7, y = 2}, {x = 8, y = 2}, {x = 13, y = 2},
        {x = 3, y = 2.5}, {x = 4, y = 2.5}, {x = 11, y = 2.5}, {x = 12, y = 2.5},
        {x = 6, y = 3}, {x = 7, y = 3}, {x = 8, y = 3}, {x = 9, y = 3},
        {x = 5.5, y = 4}, {x = 6.5, y = 4}, {x = 7.5, y = 4}, {x = 8.5, y = 4}, {x = 9.5, y = 4},
        {x = 0.5, y = 4.5}, {x = 1.5, y = 4.5}, {x = 2.5, y = 4.5}, {x = 3.5, y = 4.5},
        {x = 11.5, y = 4.5}, {x = 12.5, y = 4.5}, {x = 13.5, y = 4.5}, {x = 14.5, y = 4.5},
        {x = 6, y = 5}, {x = 7, y = 5}, {x = 8, y = 5}, {x = 9, y = 5},
        {x = 4, y = 6}, {x = 7, y = 6}, {x = 8, y = 6}, {x = 11, y = 6},
        {x = 3, y = 6.5}, {x = 12, y = 6.5},
        {x = 1, y = 7}, {x = 2, y = 7}, {x = 7, y = 7}, {x = 8, y = 7}, {x = 13, y = 7}, {x = 14, y = 7},
    } },
    { layer = 2, kind = "set", points = {
        {x = 4, y = 0}, {x = 11, y = 0},
        {x = 1, y = 1.5}, {x = 5, y = 1.5}, {x = 10, y = 1.5}, {x = 14, y = 1.5},
        {x = 3, y = 2.5}, {x = 12, y = 2.5},
        {x = 7, y = 3}, {x = 8, y = 3},
        {x = 6.5, y = 4}, {x = 7.5, y = 4}, {x = 8.5, y = 4},
        {x = 0.5, y = 4.5}, {x = 2.5, y = 4.5}, {x = 12.5, y = 4.5}, {x = 14.5, y = 4.5},
        {x = 7, y = 5}, {x = 8, y = 5},
        {x = 7, y = 6}, {x = 8, y = 6},
        {x = 3, y = 6.5}, {x = 12, y = 6.5},
        {x = 1, y = 7}, {x = 14, y = 7},
    } },
    { layer = 3, kind = "set", points = {
        {x = 7.5, y = 4.5},
    } },
}

-- Bridge layout (US-16): the classic "Four Bridges" board from GNOME
-- Mahjongg's `bridges` map — two towers linked by a deck, 144 tiles across
-- 4 layers (88/36/16/4). The shape is regular enough for rows/blocks (unlike
-- Spider's irregular silhouette, which needs `set`).
--   L0: bridge deck (88) — two wide towers with a connecting deck
--   L1: four 3x3 towers (36)
--   L2: four 2x2 towers (16)
--   L3: four peak tiles (4) at (3.5,1.5), (8.5,1.5), (3.5,6.5), (8.5,6.5)
-- Grid extents: x=0..12, y=0..8.
local BRIDGE_SPEC = {
    -- Layer 0: the bridge deck and outer towers.
    { layer = 0, kind = "row",   x_min = 1,   x_max = 11, y = 0 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 5,  y = 1 },
    { layer = 0, kind = "row",   x_min = 7,   x_max = 10,  y = 1 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 10, y = 2 },
    { layer = 0, kind = "row",   x_min = 0,   x_max = 12, y = 3 },
    { layer = 0, kind = "row",   x_min = 1.5, x_max = 3.5, y = 4 },
    { layer = 0, kind = "row",   x_min = 8.5, x_max = 10.5, y = 4 },
    { layer = 0, kind = "row",   x_min = 0,   x_max = 12, y = 5 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 10, y = 6 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 5,  y = 7 },
    { layer = 0, kind = "row",   x_min = 7,   x_max = 10,  y = 7 },
    { layer = 0, kind = "row",   x_min = 1,   x_max = 11, y = 8 },
    -- Layer 1: four 3x3 towers.
    { layer = 1, kind = "block", x_min = 2.5, x_max = 4.5, y_min = 0.5, y_max = 2.5 },
    { layer = 1, kind = "block", x_min = 7.5, x_max = 9.5, y_min = 0.5, y_max = 2.5 },
    { layer = 1, kind = "block", x_min = 2.5, x_max = 4.5, y_min = 5.5, y_max = 7.5 },
    { layer = 1, kind = "block", x_min = 7.5, x_max = 9.5, y_min = 5.5, y_max = 7.5 },
    -- Layer 2: four 2x2 towers.
    { layer = 2, kind = "block", x_min = 3, x_max = 4, y_min = 1, y_max = 2 },
    { layer = 2, kind = "block", x_min = 8, x_max = 9, y_min = 1, y_max = 2 },
    { layer = 2, kind = "block", x_min = 3, x_max = 4, y_min = 6, y_max = 7 },
    { layer = 2, kind = "block", x_min = 8, x_max = 9, y_min = 6, y_max = 7 },
    -- Layer 3: four peak tiles.
    { layer = 3, kind = "tile",  x = 3.5, y = 1.5 },
    { layer = 3, kind = "tile",  x = 8.5, y = 1.5 },
    { layer = 3, kind = "tile",  x = 3.5, y = 6.5 },
    { layer = 3, kind = "tile",  x = 8.5, y = 6.5 },
}

-- Ziggurat layout (US-22): "The Ziggurat" from GNOME Mahjongg's `ziggurat`
-- map — a stepped pyramid with two tall outer walls and a center staircase,
-- 144 tiles across 6 layers (64/20/18/18/14/10). The map's `<column>` runs
-- are transcribed as blocks with x_min == x_max. The half-grid positions on
-- layers 0/1/2 (x=2.5/3.5/6.5/7.5/11.5/14, y=0.5/1/6/6.5) feed the existing
-- layout-agnostic bevel logic unchanged.
--   L0: base (64) — walls at x=0/x=14 (y=0..7), caps at x=2.5/x=11.5,
--       corner blocks x=1..3 / x=11..13 at y=3..4, center mid-columns
--       x=6.5..7.5 (y=1..2 and y=5..6), and the y=0/y=7 center rows.
--   L1: 20 — end tiles, 3x2 wall blocks, center columns at y=1/y=6.
--   L2: 18 — inner 3x2 blocks x=2..4 / x=10..12 plus peak-ish tiles.
--   L3: 18 — block x=3..11, y=3..4
--   L4: 14 — block x=4..10, y=3..4
--   L5: 10 — block x=5..9,  y=3..4
-- Grid extents: x=0..14, y=0..7.
local ZIGGURAT_SPEC = {
    -- Layer 0: the base — outer walls, side columns, and center rows.
    { layer = 0, kind = "block", x_min = 0,   x_max = 0,   y_min = 0, y_max = 7 },
    { layer = 0, kind = "block", x_min = 1,   x_max = 3,   y_min = 3, y_max = 4 },
    { layer = 0, kind = "block", x_min = 2.5, x_max = 2.5, y_min = 0, y_max = 2 },
    { layer = 0, kind = "block", x_min = 2.5, x_max = 2.5, y_min = 5, y_max = 7 },
    { layer = 0, kind = "row",   x_min = 3.5, x_max = 10.5, y = 0 },
    { layer = 0, kind = "row",   x_min = 3.5, x_max = 10.5, y = 7 },
    { layer = 0, kind = "block", x_min = 6.5, x_max = 7.5, y_min = 1, y_max = 2 },
    { layer = 0, kind = "block", x_min = 6.5, x_max = 7.5, y_min = 5, y_max = 6 },
    { layer = 0, kind = "block", x_min = 11.5, x_max = 11.5, y_min = 0, y_max = 2 },
    { layer = 0, kind = "block", x_min = 11.5, x_max = 11.5, y_min = 5, y_max = 7 },
    { layer = 0, kind = "block", x_min = 11,  x_max = 13,  y_min = 3, y_max = 4 },
    { layer = 0, kind = "block", x_min = 14,  x_max = 14,  y_min = 0, y_max = 7 },
    -- Layer 1.
    { layer = 1, kind = "tile",  x = 3,    y = 0.5 },
    { layer = 1, kind = "tile",  x = 11,   y = 0.5 },
    { layer = 1, kind = "row",   x_min = 6.5, x_max = 7.5, y = 1 },
    { layer = 1, kind = "block", x_min = 1, x_max = 3, y_min = 3, y_max = 4 },
    { layer = 1, kind = "block", x_min = 11, x_max = 13, y_min = 3, y_max = 4 },
    { layer = 1, kind = "row",   x_min = 6.5, x_max = 7.5, y = 6 },
    { layer = 1, kind = "tile",  x = 3,    y = 6.5 },
    { layer = 1, kind = "tile",  x = 11,   y = 6.5 },
    -- Layer 2.
    { layer = 2, kind = "tile",  x = 3,    y = 0.5 },
    { layer = 2, kind = "tile",  x = 11,   y = 0.5 },
    { layer = 2, kind = "tile",  x = 7,    y = 1 },
    { layer = 2, kind = "block", x_min = 2, x_max = 4, y_min = 3, y_max = 4 },
    { layer = 2, kind = "block", x_min = 10, x_max = 12, y_min = 3, y_max = 4 },
    { layer = 2, kind = "tile",  x = 7,    y = 6 },
    { layer = 2, kind = "tile",  x = 3,    y = 6.5 },
    { layer = 2, kind = "tile",  x = 11,   y = 6.5 },
    -- Layers 3-5: the stacked center staircase.
    { layer = 3, kind = "block", x_min = 3, x_max = 11, y_min = 3, y_max = 4 },
    { layer = 4, kind = "block", x_min = 4, x_max = 10, y_min = 3, y_max = 4 },
    { layer = 5, kind = "block", x_min = 5, x_max = 9,  y_min = 3, y_max = 4 },
}

-- Cloud layout (US-23): GNOME Mahjongg's `cloud` map — a rounded body with
-- seven pillared columns on top, 144 tiles across 3 layers (79/36/29). The
-- body is a wide 14x5 block; the lower spine row (L0) and the two spine rows
-- above it sit on the half-grid at y=5.5, with a single L2 spine tile at
-- (6, 5.5) capping the stack. The layout-agnostic bevel/free-tile logic
-- (US-14) handles those fractional y coordinates unchanged.
--   L0: body block x=0..13, y=0..4 (70) + spine row x=2.5..10.5, y=5.5 (9) = 79
--   L1: spine row x=3..10, y=5.5 (8) + seven columns at even x, y=0..3 (28) = 36
--   L2: seven columns at even x, y=0..3 (28) + spine tile (6, 5.5) = 29
-- Grid extents: x=0..13, y=0..5.5.
local CLOUD_SPEC = {
    -- Layer 0: the cloud body plus the lower spine row.
    { layer = 0, kind = "block", x_min = 0,   x_max = 13, y_min = 0, y_max = 4 },
    { layer = 0, kind = "row",   x_min = 2.5, x_max = 10.5, y = 5.5 },
    -- Layer 1: the middle spine row plus seven columns.
    { layer = 1, kind = "row",   x_min = 3, x_max = 10, y = 5.5 },
    { layer = 1, kind = "block", x_min = 0,  x_max = 0,  y_min = 0, y_max = 3 },
    { layer = 1, kind = "block", x_min = 2,  x_max = 2,  y_min = 0, y_max = 3 },
    { layer = 1, kind = "block", x_min = 4,  x_max = 4,  y_min = 0, y_max = 3 },
    { layer = 1, kind = "block", x_min = 6,  x_max = 6,  y_min = 0, y_max = 3 },
    { layer = 1, kind = "block", x_min = 8,  x_max = 8,  y_min = 0, y_max = 3 },
    { layer = 1, kind = "block", x_min = 10, x_max = 10, y_min = 0, y_max = 3 },
    { layer = 1, kind = "block", x_min = 12, x_max = 12, y_min = 0, y_max = 3 },
    -- Layer 2: the same seven columns on top, plus the spine tile.
    { layer = 2, kind = "block", x_min = 0,  x_max = 0,  y_min = 0, y_max = 3 },
    { layer = 2, kind = "block", x_min = 2,  x_max = 2,  y_min = 0, y_max = 3 },
    { layer = 2, kind = "block", x_min = 4,  x_max = 4,  y_min = 0, y_max = 3 },
    { layer = 2, kind = "block", x_min = 6,  x_max = 6,  y_min = 0, y_max = 3 },
    { layer = 2, kind = "block", x_min = 8,  x_max = 8,  y_min = 0, y_max = 3 },
    { layer = 2, kind = "block", x_min = 10, x_max = 10, y_min = 0, y_max = 3 },
    { layer = 2, kind = "block", x_min = 12, x_max = 12, y_min = 0, y_max = 3 },
    { layer = 2, kind = "tile",  x = 6,      y = 5.5 },
}

-- Tic-Tac-Toe layout (US-24): GNOME Mahjongg's `tictactoe` map — a 3x3 grid
-- of nested blocks (the center block and two tall side columns), 144 tiles
-- across 5 layers (40/36/28/20/20). The center 5-wide rows and the two 9-tall
-- columns repeat on every layer, shrinking one row per layer; the x=0/2 and
-- x=10/12 edge blocks step down layer by layer. All coordinates are on the
-- full grid, so the regular row/block spec terms express it directly.
--   L0: columns x=3/x=9 (y=0..8, 9 each) + 3-wide edge rows at y=2/y=6 and
--       the 5-wide center rows (3+5+3 per row) = 40
--   L1: columns x=3/x=9 (y=0..8) + edge rows narrowed to 2 (x=1..2, x=10..11)
--       and the same 5-wide center rows = 36
--   L2: columns x=3/x=9 (y=1..7, 7 each) + single edge tiles x=2/x=10 at
--       y=2/y=6 and the 5-wide center rows = 28
--   L3/L4: columns x=3/x=9 (y=2..6) + 5-wide center rows = 20 each
-- Grid extents: x=0..12, y=0..8.
local TICTACTOE_SPEC = {
    -- Layer 0: the two tall side columns plus the full 3x3 frame rows.
    { layer = 0, kind = "block", x_min = 3, x_max = 3, y_min = 0, y_max = 8 },
    { layer = 0, kind = "block", x_min = 9, x_max = 9, y_min = 0, y_max = 8 },
    { layer = 0, kind = "row",   x_min = 0, x_max = 2,  y = 2 },
    { layer = 0, kind = "row",   x_min = 0, x_max = 2,  y = 6 },
    { layer = 0, kind = "row",   x_min = 4, x_max = 8,  y = 2 },
    { layer = 0, kind = "row",   x_min = 4, x_max = 8,  y = 6 },
    { layer = 0, kind = "row",   x_min = 10, x_max = 12, y = 2 },
    { layer = 0, kind = "row",   x_min = 10, x_max = 12, y = 6 },
    -- Layer 1: columns unchanged; the edge rows step in by one tile.
    { layer = 1, kind = "block", x_min = 3, x_max = 3, y_min = 0, y_max = 8 },
    { layer = 1, kind = "block", x_min = 9, x_max = 9, y_min = 0, y_max = 8 },
    { layer = 1, kind = "row",   x_min = 1, x_max = 2,  y = 2 },
    { layer = 1, kind = "row",   x_min = 1, x_max = 2,  y = 6 },
    { layer = 1, kind = "row",   x_min = 4, x_max = 8,  y = 2 },
    { layer = 1, kind = "row",   x_min = 4, x_max = 8,  y = 6 },
    { layer = 1, kind = "row",   x_min = 10, x_max = 11, y = 2 },
    { layer = 1, kind = "row",   x_min = 10, x_max = 11, y = 6 },
    -- Layer 2: columns shrink vertically; the edge rows collapse to single
    -- tiles.
    { layer = 2, kind = "block", x_min = 3, x_max = 3, y_min = 1, y_max = 7 },
    { layer = 2, kind = "block", x_min = 9, x_max = 9, y_min = 1, y_max = 7 },
    { layer = 2, kind = "tile",  x = 2, y = 2 },
    { layer = 2, kind = "tile",  x = 2, y = 6 },
    { layer = 2, kind = "row",   x_min = 4, x_max = 8, y = 2 },
    { layer = 2, kind = "row",   x_min = 4, x_max = 8, y = 6 },
    { layer = 2, kind = "tile",  x = 10, y = 2 },
    { layer = 2, kind = "tile",  x = 10, y = 6 },
    -- Layers 3-4: only the columns and the 5-wide center rows remain.
    { layer = 3, kind = "block", x_min = 3, x_max = 3, y_min = 2, y_max = 6 },
    { layer = 3, kind = "block", x_min = 9, x_max = 9, y_min = 2, y_max = 6 },
    { layer = 3, kind = "row",   x_min = 4, x_max = 8, y = 2 },
    { layer = 3, kind = "row",   x_min = 4, x_max = 8, y = 6 },
    { layer = 4, kind = "block", x_min = 3, x_max = 3, y_min = 2, y_max = 6 },
    { layer = 4, kind = "block", x_min = 9, x_max = 9, y_min = 2, y_max = 6 },
    { layer = 4, kind = "row",   x_min = 4, x_max = 8, y = 2 },
    { layer = 4, kind = "row",   x_min = 4, x_max = 8, y = 6 },
}

-- Red Dragon layout (US-25): GNOME Mahjongg's `dragon` map — two curved "horn"
-- towers on the left/right edges joined by a wide body block, with a raised
-- ridge and a single off-center peak tile, 144 tiles across 3 layers
-- (82/45/17). The horns use the half-grid (y=1.5/3/4.5/6 and the x=6.5 base
-- row), which the layout-agnostic bevel/free-tile logic handles unchanged.
--   L0: body block x=2..12, y=0..5 (66) + five-tile horns at x=0/x=14
--       (y=0..6) + the six-tile base row at y=6.5 (x=2..12, even) = 82
--   L1: ridge block x=3.5..10.5, y=0.5..4.5 (40) + right horn column
--       x=11.5 (y=1.5..3.5) + two left horn tiles x=2.5 (y=1.5, 4.5) = 45
--   L2: top ridge block x=5..8, y=1..4 (16) + the peak tile (11, 4) = 17
-- Grid extents: x=0..14, y=0..6.5.
local RED_DRAGON_SPEC = {
    -- Layer 0: the body block, the two horn towers, and the base row.
    { layer = 0, kind = "block", x_min = 2, x_max = 12, y_min = 0, y_max = 5 },
    { layer = 0, kind = "tile",  x = 0,  y = 0 },
    { layer = 0, kind = "tile",  x = 0,  y = 1.5 },
    { layer = 0, kind = "tile",  x = 0,  y = 3 },
    { layer = 0, kind = "tile",  x = 0,  y = 4.5 },
    { layer = 0, kind = "tile",  x = 0,  y = 6 },
    { layer = 0, kind = "tile",  x = 14, y = 0 },
    { layer = 0, kind = "tile",  x = 14, y = 1.5 },
    { layer = 0, kind = "tile",  x = 14, y = 3 },
    { layer = 0, kind = "tile",  x = 14, y = 4.5 },
    { layer = 0, kind = "tile",  x = 14, y = 6 },
    { layer = 0, kind = "tile",  x = 2,  y = 6.5 },
    { layer = 0, kind = "tile",  x = 4,  y = 6.5 },
    { layer = 0, kind = "tile",  x = 6,  y = 6.5 },
    { layer = 0, kind = "tile",  x = 8,  y = 6.5 },
    { layer = 0, kind = "tile",  x = 10, y = 6.5 },
    { layer = 0, kind = "tile",  x = 12, y = 6.5 },
    -- Layer 1: the raised ridge plus the horns' upper tiles.
    { layer = 1, kind = "block", x_min = 3.5,  x_max = 10.5, y_min = 0.5, y_max = 4.5 },
    { layer = 1, kind = "block", x_min = 11.5, x_max = 11.5, y_min = 1.5, y_max = 3.5 },
    { layer = 1, kind = "tile",  x = 2.5, y = 1.5 },
    { layer = 1, kind = "tile",  x = 2.5, y = 4.5 },
    -- Layer 2: the top ridge and the off-center peak tile.
    { layer = 2, kind = "block", x_min = 5, x_max = 8, y_min = 1, y_max = 4 },
    { layer = 2, kind = "tile",  x = 11, y = 4 },
}

-- Overpass layout (US-26): GNOME Mahjongg's `overpass` map — twin towers on
-- the far left/right linked by two deck layers that cross over/under each
-- other, 144 tiles across 5 layers (52/20/16/32/24). The center deck is a
-- 4-wide full-height block on L0; the two towers step in by one tile per layer
-- while the deck spans L2 (two 2-wide segments), L3 (8-wide) and L4 (6-wide).
-- All coordinates are on the full grid.
--   L0: left tower column x=0 (y=2..7) + corner tiles x=1 at y=2/y=7 + center
--       deck block x=4..7 (y=0..8) + mirror corner tiles x=10 + right tower
--       column x=11 (y=2..7) = 6+1+1+36+1+1+6 = 52
--   L1: the four tower columns x=0 (y=2..7), x=1 (y=3..6), x=10 (y=3..6),
--       x=11 (y=2..7) = 6+4+4+6 = 20
--   L2: two 2-wide deck segments x=1..2 and x=9..10 (y=3..6) = 8+8 = 16
--   L3: the 8-wide lower deck x=2..9 (y=3..6) = 32
--   L4: the 6-wide upper deck x=3..8 (y=3..6) = 24
-- Grid extents: x=0..11, y=0..8.
local OVERPASS_SPEC = {
    -- Layer 0: the towers and the center deck.
    { layer = 0, kind = "block", x_min = 0, x_max = 0, y_min = 2, y_max = 7 },
    { layer = 0, kind = "tile",  x = 1, y = 2 },
    { layer = 0, kind = "tile",  x = 1, y = 7 },
    { layer = 0, kind = "block", x_min = 4, x_max = 7, y_min = 0, y_max = 8 },
    { layer = 0, kind = "tile",  x = 10, y = 2 },
    { layer = 0, kind = "tile",  x = 10, y = 7 },
    { layer = 0, kind = "block", x_min = 11, x_max = 11, y_min = 2, y_max = 7 },
    -- Layer 1: the four tower columns.
    { layer = 1, kind = "block", x_min = 0,  x_max = 0,  y_min = 2, y_max = 7 },
    { layer = 1, kind = "block", x_min = 1,  x_max = 1,  y_min = 3, y_max = 6 },
    { layer = 1, kind = "block", x_min = 10, x_max = 10, y_min = 3, y_max = 6 },
    { layer = 1, kind = "block", x_min = 11, x_max = 11, y_min = 2, y_max = 7 },
    -- Layer 2: two short deck segments.
    { layer = 2, kind = "block", x_min = 1, x_max = 2,  y_min = 3, y_max = 6 },
    { layer = 2, kind = "block", x_min = 9, x_max = 10, y_min = 3, y_max = 6 },
    -- Layer 3: the 8-wide lower deck.
    { layer = 3, kind = "block", x_min = 2, x_max = 9, y_min = 3, y_max = 6 },
    -- Layer 4: the 6-wide upper deck.
    { layer = 4, kind = "block", x_min = 3, x_max = 8, y_min = 3, y_max = 6 },
}

-- Pyramid's Walls layout (US-27): GNOME Mahjongg's `pyramid` map — concentric
-- square rings stepping up to a single peak tile, the deepest board at 7
-- layers (41/34/27/20/13/6/3). Each layer keeps the same shape: a full border
-- ring of tiles (rows at y=1/y=7, columns at x=0/x=11) plus a horizontal
-- middle bar at y=4, all shrinking inward by one tile per layer until only the
-- three L6 peak tiles remain. The y=1..7 rows (no tile at y=0 or y=8) and the
-- fractional x=2.5..8.5 middle bars sit on the same half-grid the bevel logic
-- already handles. (The story's "y=0..6" extent summary is a mis-transcription;
-- the map's rows span y=1..7.)
--   L0: border rows y=1/y=7 (12 each) + columns x=0/x=11 (5 each) + middle bar
--       x=2.5..8.5 at y=4 (7) = 41
--   L1..L4: same shape, ring shrunk by one per layer (34/27/20/13)
--   L5: the inner ring narrows to two-wide rows at x=5..6, y=1/y=4/y=7 (6)
--   L6: three peak tiles x=5.5 at y=1/y=4/y=7 (3)
-- Grid extents: x=0..11, y=1..7.
local PYRAMID_SPEC = {
    -- Layer 0: the outer border ring plus the wide middle bar.
    { layer = 0, kind = "row",   x_min = 0,   x_max = 11,  y = 1 },
    { layer = 0, kind = "row",   x_min = 0,   x_max = 11,  y = 7 },
    { layer = 0, kind = "block", x_min = 0,   x_max = 0,   y_min = 2, y_max = 6 },
    { layer = 0, kind = "block", x_min = 11,  x_max = 11,  y_min = 2, y_max = 6 },
    { layer = 0, kind = "row",   x_min = 2.5, x_max = 8.5, y = 4 },
    -- Layer 1.
    { layer = 1, kind = "row",   x_min = 1,   x_max = 10,  y = 1 },
    { layer = 1, kind = "row",   x_min = 1,   x_max = 10,  y = 7 },
    { layer = 1, kind = "block", x_min = 0,   x_max = 0,   y_min = 2.5, y_max = 5.5 },
    { layer = 1, kind = "block", x_min = 11,  x_max = 11,  y_min = 2.5, y_max = 5.5 },
    { layer = 1, kind = "row",   x_min = 3,   x_max = 8,   y = 4 },
    -- Layer 2.
    { layer = 2, kind = "row",   x_min = 2,   x_max = 9,   y = 1 },
    { layer = 2, kind = "row",   x_min = 2,   x_max = 9,   y = 7 },
    { layer = 2, kind = "block", x_min = 0,   x_max = 0,   y_min = 3, y_max = 5 },
    { layer = 2, kind = "block", x_min = 11,  x_max = 11,  y_min = 3, y_max = 5 },
    { layer = 2, kind = "row",   x_min = 3.5, x_max = 7.5, y = 4 },
    -- Layer 3.
    { layer = 3, kind = "row",   x_min = 3,   x_max = 8,   y = 1 },
    { layer = 3, kind = "row",   x_min = 3,   x_max = 8,   y = 7 },
    { layer = 3, kind = "block", x_min = 0,   x_max = 0,   y_min = 3.5, y_max = 4.5 },
    { layer = 3, kind = "block", x_min = 11,  x_max = 11,  y_min = 3.5, y_max = 4.5 },
    { layer = 3, kind = "row",   x_min = 4,   x_max = 7,   y = 4 },
    -- Layer 4: the side columns have shrunk to a single tile each.
    { layer = 4, kind = "row",   x_min = 4,   x_max = 7,   y = 1 },
    { layer = 4, kind = "row",   x_min = 4,   x_max = 7,   y = 7 },
    { layer = 4, kind = "tile",  x = 0,  y = 4 },
    { layer = 4, kind = "tile",  x = 11, y = 4 },
    { layer = 4, kind = "row",   x_min = 4.5, x_max = 6.5, y = 4 },
    -- Layer 5.
    { layer = 5, kind = "row",   x_min = 5, x_max = 6, y = 1 },
    { layer = 5, kind = "row",   x_min = 5, x_max = 6, y = 7 },
    { layer = 5, kind = "row",   x_min = 5, x_max = 6, y = 4 },
    -- Layer 6: the three peak tiles.
    { layer = 6, kind = "tile",  x = 5.5, y = 1 },
    { layer = 6, kind = "tile",  x = 5.5, y = 7 },
    { layer = 6, kind = "tile",  x = 5.5, y = 4 },
}

-- Confounding Cross layout (US-28): GNOME Mahjongg's `confounding` map — a
-- plus/cross shape built from nested hollow rings rising to a lone center
-- peak tile, 144 tiles across 6 layers (47/42/27/18/9/1). The cross arms are
-- three-wide rows/columns; the inner rings keep the arms but hollow out the
-- corners until a single peak tile (5, 4, L5) remains. L0 has the corner
-- tiles of the 5x5 cross-center hollowed; the upper layers shrink toward the
-- center column x=5. Grid extents: x=0..10, y=0..8.
local CONFOUNDING_SPEC = {
    -- Layer 0: the outer cross — arms, corner fills, and the center column.
    { layer = 0, kind = "row",   x_min = 1, x_max = 9,  y = 1 },
    { layer = 0, kind = "row",   x_min = 1, x_max = 9,  y = 7 },
    { layer = 0, kind = "block", x_min = 1, x_max = 1,  y_min = 2, y_max = 6 },
    { layer = 0, kind = "block", x_min = 9, x_max = 9,  y_min = 2, y_max = 6 },
    { layer = 0, kind = "tile",  x = 5,  y = 0 },
    { layer = 0, kind = "tile",  x = 5,  y = 8 },
    { layer = 0, kind = "tile",  x = 0,  y = 4 },
    { layer = 0, kind = "tile",  x = 10, y = 4 },
    { layer = 0, kind = "tile",  x = 2,  y = 2 },
    { layer = 0, kind = "tile",  x = 2,  y = 6 },
    { layer = 0, kind = "tile",  x = 8,  y = 2 },
    { layer = 0, kind = "tile",  x = 8,  y = 6 },
    { layer = 0, kind = "row",   x_min = 2, x_max = 8,  y = 4 },
    { layer = 0, kind = "tile",  x = 5,  y = 2 },
    { layer = 0, kind = "tile",  x = 5,  y = 3 },
    { layer = 0, kind = "tile",  x = 5,  y = 5 },
    { layer = 0, kind = "tile",  x = 5,  y = 6 },
    -- Layer 1: the ring steps inward — hollow 2x2 corner blocks and stub arms.
    { layer = 1, kind = "row",   x_min = 0.5, x_max = 3.5,  y = 4 },
    { layer = 1, kind = "row",   x_min = 6.5, x_max = 9.5,  y = 4 },
    { layer = 1, kind = "block", x_min = 4.5, x_max = 5.5,  y_min = 3.5, y_max = 4.5 },
    { layer = 1, kind = "block", x_min = 1, x_max = 2,  y_min = 1, y_max = 2 },
    { layer = 1, kind = "block", x_min = 8, x_max = 9,  y_min = 1, y_max = 2 },
    { layer = 1, kind = "block", x_min = 1, x_max = 2,  y_min = 6, y_max = 7 },
    { layer = 1, kind = "block", x_min = 8, x_max = 9,  y_min = 6, y_max = 7 },
    { layer = 1, kind = "block", x_min = 5, x_max = 5,  y_min = 0.5, y_max = 2.5 },
    { layer = 1, kind = "block", x_min = 5, x_max = 5,  y_min = 5.5, y_max = 7.5 },
    { layer = 1, kind = "tile",  x = 1, y = 3 },
    { layer = 1, kind = "tile",  x = 1, y = 5 },
    { layer = 1, kind = "tile",  x = 9, y = 3 },
    { layer = 1, kind = "tile",  x = 9, y = 5 },
    { layer = 1, kind = "tile",  x = 3, y = 1 },
    { layer = 1, kind = "tile",  x = 3, y = 7 },
    { layer = 1, kind = "tile",  x = 7, y = 1 },
    { layer = 1, kind = "tile",  x = 7, y = 7 },
    -- Layer 2: the cross body plus the four 2-tile corner stubs.
    { layer = 2, kind = "row",   x_min = 1, x_max = 9,  y = 4 },
    { layer = 2, kind = "block", x_min = 5, x_max = 5,  y_min = 1, y_max = 3 },
    { layer = 2, kind = "block", x_min = 5, x_max = 5,  y_min = 5, y_max = 7 },
    { layer = 2, kind = "tile",  x = 1, y = 1 },
    { layer = 2, kind = "tile",  x = 1, y = 2 },
    { layer = 2, kind = "tile",  x = 2, y = 1 },
    { layer = 2, kind = "tile",  x = 9, y = 7 },
    { layer = 2, kind = "tile",  x = 9, y = 6 },
    { layer = 2, kind = "tile",  x = 8, y = 7 },
    { layer = 2, kind = "tile",  x = 9, y = 1 },
    { layer = 2, kind = "tile",  x = 9, y = 2 },
    { layer = 2, kind = "tile",  x = 8, y = 1 },
    { layer = 2, kind = "tile",  x = 1, y = 7 },
    { layer = 2, kind = "tile",  x = 1, y = 6 },
    { layer = 2, kind = "tile",  x = 2, y = 7 },
    -- Layer 3: the arms shrink to stub rows plus the 2-tile center spine.
    { layer = 3, kind = "block", x_min = 4.5, x_max = 5.5, y_min = 3.5, y_max = 4.5 },
    { layer = 3, kind = "row",   x_min = 1.5, x_max = 3.5, y = 4 },
    { layer = 3, kind = "row",   x_min = 6.5, x_max = 8.5, y = 4 },
    { layer = 3, kind = "block", x_min = 5, x_max = 5,  y_min = 1.5, y_max = 2.5 },
    { layer = 3, kind = "block", x_min = 5, x_max = 5,  y_min = 5.5, y_max = 6.5 },
    { layer = 3, kind = "tile",  x = 1, y = 1 },
    { layer = 3, kind = "tile",  x = 9, y = 7 },
    { layer = 3, kind = "tile",  x = 1, y = 7 },
    { layer = 3, kind = "tile",  x = 9, y = 1 },
    -- Layer 4: a horizontal bar plus the two 2-tile center stubs.
    { layer = 4, kind = "row",   x_min = 3, x_max = 7, y = 4 },
    { layer = 4, kind = "block", x_min = 5, x_max = 5, y_min = 2, y_max = 3 },
    { layer = 4, kind = "block", x_min = 5, x_max = 5, y_min = 5, y_max = 6 },
    -- Layer 5: the lone center peak tile.
    { layer = 5, kind = "tile",  x = 5, y = 4 },
}

-- Taipei layout (US-29): GNOME Mahjongg's `difficult` map (Taipei, the
-- "difficult" default) — the iconic fortified Great Wall board, 144 tiles
-- across 7 layers (63/46/19/10/3/2/1). Two tall corner towers and a stepped
-- center mound: the tiered wall bands shrink one layer at a time toward a
-- single peak tile (5, 3, L6). The four corner 2x2 blocks and the half-grid
-- center rows feed the existing bevel logic unchanged.
--   L0: towers x=0/x=10 at y=3, 2x2 corner blocks, 2-wide 2x2 edge blocks at
--       x=1..2 / x=8..9, the 5-wide center block x=3..7 (y=2..4), top/bottom
--       rows y=0/y=6 and mid rows y=1/y=5 = 63
--   L1: tower peaks, the left/right 3-wide tower bodies, and the half-grid
--       center bands (46)
--   L2: three full rows y=2/y=3/y=4 stepping in (19)
--   L3: two edge tiles + a 4-wide block (10)
--   L4/L5/L6: the three-row taper to the peak (3/2/1)
-- Grid extents: x=0..10, y=0..6.
local TAIPEI_SPEC = {
    -- Layer 0: the base walls and corner towers.
    { layer = 0, kind = "tile",  x = 0,  y = 3 },
    { layer = 0, kind = "tile",  x = 10, y = 3 },
    { layer = 0, kind = "block", x_min = 0.5, x_max = 1.5, y_min = 0.5, y_max = 1.5 },
    { layer = 0, kind = "block", x_min = 8.5, x_max = 9.5, y_min = 0.5, y_max = 1.5 },
    { layer = 0, kind = "block", x_min = 0.5, x_max = 1.5, y_min = 4.5, y_max = 5.5 },
    { layer = 0, kind = "block", x_min = 8.5, x_max = 9.5, y_min = 4.5, y_max = 5.5 },
    { layer = 0, kind = "block", x_min = 1, x_max = 2, y_min = 2.5, y_max = 3.5 },
    { layer = 0, kind = "block", x_min = 8, x_max = 9, y_min = 2.5, y_max = 3.5 },
    { layer = 0, kind = "block", x_min = 3, x_max = 7, y_min = 2, y_max = 4 },
    { layer = 0, kind = "row",   x_min = 3, x_max = 7, y = 0 },
    { layer = 0, kind = "row",   x_min = 3, x_max = 7, y = 6 },
    { layer = 0, kind = "row",   x_min = 2.5, x_max = 7.5, y = 1 },
    { layer = 0, kind = "row",   x_min = 2.5, x_max = 7.5, y = 5 },
    -- Layer 1: the tier above — tower bodies and the half-grid center bands.
    { layer = 1, kind = "tile",  x = 3.5, y = 0 },
    { layer = 1, kind = "tile",  x = 6.5, y = 0 },
    { layer = 1, kind = "tile",  x = 3.5, y = 6 },
    { layer = 1, kind = "tile",  x = 6.5, y = 6 },
    { layer = 1, kind = "row",   x_min = 1, x_max = 3,  y = 1 },
    { layer = 1, kind = "block", x_min = 1.5, x_max = 2.5, y_min = 2, y_max = 4 },
    { layer = 1, kind = "row",   x_min = 1, x_max = 3,  y = 5 },
    { layer = 1, kind = "row",   x_min = 7, x_max = 9,  y = 1 },
    { layer = 1, kind = "block", x_min = 7.5, x_max = 8.5, y_min = 2, y_max = 4 },
    { layer = 1, kind = "row",   x_min = 7, x_max = 9,  y = 5 },
    { layer = 1, kind = "row",   x_min = 4.5, x_max = 5.5, y = 0.5 },
    { layer = 1, kind = "row",   x_min = 4, x_max = 6, y = 1.5 },
    { layer = 1, kind = "block", x_min = 3.5, x_max = 6.5, y_min = 2.5, y_max = 3.5 },
    { layer = 1, kind = "row",   x_min = 4, x_max = 6, y = 4.5 },
    { layer = 1, kind = "row",   x_min = 4.5, x_max = 5.5, y = 5.5 },
    -- Layer 2: three full stepped rows.
    { layer = 2, kind = "row", x_min = 2.5, x_max = 7.5, y = 2 },
    { layer = 2, kind = "row", x_min = 2,   x_max = 8,   y = 3 },
    { layer = 2, kind = "row", x_min = 2.5, x_max = 7.5, y = 4 },
    -- Layer 3: two edge tiles flanking the 4-wide center block.
    { layer = 3, kind = "tile",  x = 2.5, y = 3 },
    { layer = 3, kind = "tile",  x = 7.5, y = 3 },
    { layer = 3, kind = "block", x_min = 3.5, x_max = 6.5, y_min = 2.5, y_max = 3.5 },
    -- Layers 4-6: the taper to the peak tile.
    { layer = 4, kind = "row",   x_min = 4, x_max = 6,  y = 3 },
    { layer = 5, kind = "row",   x_min = 4.5, x_max = 5.5, y = 3 },
    { layer = 6, kind = "tile",  x = 5, y = 3 },
}

-- The registry itself: id -> { id=, name=, spec= }. Callers must NOT mutate
-- the entries (the cached layout tables reference the spec).
Layouts.layouts = {}

-- Per-id caches (forward-declared so registerLayout/deregisterLayout can
-- invalidate them).
local _layout_cache = {}      -- id -> positions array
local _bounds_cache = {}      -- id -> { x_min, x_max, y_min, y_max }
local _layout_key_cache = {}  -- id -> { [posKey] = true }
local _max_layer_cache = {}   -- id -> number

-- Builds the flat positions array from a layout spec. Caller-cached per id via
-- buildLayout(id); this helper never memoizes (it is only run once per id).
local function buildLayoutFromSpec(spec)
    local layout = {}
    local function add(x, y, layer)
        layout[#layout + 1] = { x = x, y = y, layer = layer }
    end
    for _, s in ipairs(spec) do
        if s.kind == "row" then
            for x = s.x_min, s.x_max do
                add(x, s.y, s.layer)
            end
        elseif s.kind == "block" then
            for y = s.y_min, s.y_max do
                for x = s.x_min, s.x_max do
                    add(x, y, s.layer)
                end
            end
        elseif s.kind == "set" then
            -- Explicit point list: { {x=, y=}, ... } at a fixed layer. Used by
            -- layouts (e.g. Spider) whose per-layer shape is too irregular for
            -- rows/blocks to express compactly. (US-15)
            for _, pt in ipairs(s.points) do
                add(pt.x, pt.y, s.layer)
            end
        else -- single tile
            add(s.x, s.y, s.layer)
        end
    end
    return layout
end

-- Registers a layout. `entry` is { id=string, name=string, spec=table } (name
-- defaults to the id). Re-registering an id replaces it and drops its caches
-- so a hot-reload picks up a new spec. US-15/16/22 (and each US-23..29 board)
-- call this at module load.
function Layouts.registerLayout(entry)
    if type(entry) ~= "table" or type(entry.id) ~= "string" or type(entry.spec) ~= "table" then
        error("registerLayout: needs { id=string, name=string, spec=table }")
    end
    local copy = {
        id = entry.id,
        name = entry.name or entry.id,
        spec = entry.spec,
    }
    Layouts.layouts[copy.id] = copy
    _layout_cache[copy.id] = nil
    _bounds_cache[copy.id] = nil
    _layout_key_cache[copy.id] = nil
    _max_layer_cache[copy.id] = nil
end

-- Removes a layout and drops its caches. Idempotent for an unknown id.
-- (US-22a — replaces the manual `layouts[id] = nil` + cache-nilling in tests.)
function Layouts.deregisterLayout(id)
    if type(id) ~= "string" then
        error("deregisterLayout: needs a string id")
    end
    Layouts.layouts[id] = nil
    _layout_cache[id] = nil
    _bounds_cache[id] = nil
    _layout_key_cache[id] = nil
    _max_layer_cache[id] = nil
end

-- Sorted list of registered layout ids (the picker iterates this).
function Layouts.layoutIds()
    local ids = {}
    for id in pairs(Layouts.layouts) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

-- Display name of a layout id (falls back to the id for an unknown layout).
function Layouts.layoutName(id)
    local l = Layouts.layouts[id]
    return (l and l.name) or id
end

-- Turtle is registered in US-14; US-15 adds Spider; US-16 adds Bridge; US-22
-- adds Ziggurat; US-23 adds Cloud; US-24/25/26 add Tic-Tac-Toe, Red Dragon and
-- Overpass; US-27/28/29 add Pyramid's Walls, Confounding Cross and Taipei.
Layouts.registerLayout{ id = "turtle", name = "Turtle", spec = TURTLE_SPEC }
Layouts.registerLayout{ id = "spider", name = "Spider", spec = SPIDER_SPEC }
Layouts.registerLayout{ id = "bridge", name = "Bridge", spec = BRIDGE_SPEC }
Layouts.registerLayout{ id = "ziggurat", name = "Ziggurat", spec = ZIGGURAT_SPEC }
Layouts.registerLayout{ id = "cloud", name = "Cloud", spec = CLOUD_SPEC }
Layouts.registerLayout{ id = "tictactoe", name = "Tic-Tac-Toe", spec = TICTACTOE_SPEC }
Layouts.registerLayout{ id = "red-dragon", name = "Red Dragon", spec = RED_DRAGON_SPEC }
Layouts.registerLayout{ id = "overpass", name = "Overpass", spec = OVERPASS_SPEC }
Layouts.registerLayout{ id = "pyramid", name = "Pyramid's Walls", spec = PYRAMID_SPEC }
Layouts.registerLayout{ id = "confounding", name = "Confounding Cross", spec = CONFOUNDING_SPEC }
Layouts.registerLayout{ id = "taipei", name = "Taipei", spec = TAIPEI_SPEC }

-- Returns the 144 tile positions of a layout as an array of
-- { x = .., y = .., layer = .. } tables, bottom layer first (so the UI can
-- paint lower layers first). The layout is static, so it is built once and
-- cached per id: rebuilds (new game, board repaints) iterate the same table
-- instead of allocating fresh position tables every call. Callers must NOT
-- mutate the returned array.
function Layouts.buildLayout(id)
    if id == nil then id = "turtle" end
    if not _layout_cache[id] then
        local entry = Layouts.layouts[id]
        if not entry then
            error("buildLayout: unknown layout id " .. tostring(id))
        end
        _layout_cache[id] = buildLayoutFromSpec(entry.spec)
    end
    return _layout_cache[id]
end

-- Canonical map key for a board position. A board is keyed by this string
-- (x,y,layer -> kind) so lookups/removals are O(1) and persistence (US-10)
-- is a plain table.
function Layouts.posKey(x, y, layer)
    return x .. "," .. y .. "," .. layer
end

-- Highest layer used by a layout (US-14). Cached per id.
function Layouts.maxLayer(id)
    if id == nil then id = "turtle" end
    if not _max_layer_cache[id] then
        local m = 0
        for _, p in ipairs(Layouts.buildLayout(id)) do
            if p.layer > m then m = p.layer end
        end
        _max_layer_cache[id] = m
    end
    return _max_layer_cache[id]
end

-- Bounds of a layout's projection grid as { x_min, x_max, y_min, y_max }.
-- Static per id, so cached like buildLayout(id) (callers must not mutate).
function Layouts.gridBounds(id)
    if id == nil then id = "turtle" end
    if not _bounds_cache[id] then
        local bounds = {
            x_min = math.huge,
            x_max = -math.huge,
            y_min = math.huge,
            y_max = -math.huge,
        }
        for _, p in ipairs(Layouts.buildLayout(id)) do
            bounds.x_min = math.min(bounds.x_min, p.x)
            bounds.x_max = math.max(bounds.x_max, p.x)
            bounds.y_min = math.min(bounds.y_min, p.y)
            bounds.y_max = math.max(bounds.y_max, p.y)
        end
        _bounds_cache[id] = bounds
    end
    return _bounds_cache[id]
end

-- True if (x, y, layer) is one of the saved layout's positions. Used to
-- validate deserialized state (US-10): a position that is not part of the
-- layout was not produced by a real game. `id` defaults to "turtle".
function Layouts.isLayoutPosition(x, y, layer, id)
    if id == nil then id = "turtle" end
    if not _layout_key_cache[id] then
        _layout_key_cache[id] = {}
        for _, p in ipairs(Layouts.buildLayout(id)) do
            _layout_key_cache[id][Layouts.posKey(p.x, p.y, p.layer)] = true
        end
    end
    return _layout_key_cache[id][Layouts.posKey(x, y, layer)] == true
end

-- Self-tests --------------------------------------------------------------
--
-- US-22a: the per-layout shape checks (144 positions, per-layer counts, dedup,
-- grid bounds, maxLayer) and the registry-behavior checks (sorted layoutIds,
-- layoutName fallback, memoization, register/re-register/deregister) moved here
-- from mahjonglogic.lua. The per-layout GAMEPLAY checks (deal / free tiles /
-- hasMoves / persistence round-trip) stay in mahjonglogic.lua because they need
-- the deck/removal logic.

function Layouts.runSelfTests()
    local function check(cond, msg)
        if not cond then
            io.write("FAIL: ", msg, "\n")
            os.exit(1)
        end
        io.write("ok:   ", msg, "\n")
    end

    -- Verifies one layout's shape: exactly 144 unique positions, per-layer
    -- counts, max layer, grid bounds, and that every spec entry's positions are
    -- present in the built layout (spec -> layout coverage).
    local function checkShape(id, layer_counts, expected_bounds)
        local layout = Layouts.buildLayout(id)
        check(#layout == 144, id .. " layout has 144 positions (got " .. #layout .. ")")
        local seen = {}
        local counts = {}
        for _, p in ipairs(layout) do
            counts[p.layer] = (counts[p.layer] or 0) + 1
            local key = Layouts.posKey(p.x, p.y, p.layer)
            check(not seen[key], id .. ": no duplicate position " .. key)
            seen[key] = true
        end
        for layer, count in pairs(layer_counts) do
            check(counts[layer] == count, id .. " layer " .. layer .. " has " .. count
                .. " tiles (got " .. tostring(counts[layer]) .. ")")
        end
        local max_layer = 0
        for layer in pairs(layer_counts) do
            if layer > max_layer then max_layer = layer end
        end
        check(Layouts.maxLayer(id) == max_layer,
            id .. " maxLayer(" .. id .. ") == " .. max_layer)
        local bounds = Layouts.gridBounds(id)
        check(bounds.x_min == expected_bounds.x_min and bounds.x_max == expected_bounds.x_max
            and bounds.y_min == expected_bounds.y_min and bounds.y_max == expected_bounds.y_max,
            id .. " grid bounds are x=" .. expected_bounds.x_min .. ".." .. expected_bounds.x_max
            .. ", y=" .. expected_bounds.y_min .. ".." .. expected_bounds.y_max)
        -- Every spec entry's positions must be present.
        for _, s in ipairs(Layouts.layouts[id].spec) do
            if s.kind == "row" then
                for x = s.x_min, s.x_max do
                    check(seen[Layouts.posKey(x, s.y, s.layer)] ~= nil,
                        id .. " row tile " .. x .. "," .. s.y .. ",L" .. s.layer .. " is present")
                end
            elseif s.kind == "block" then
                for y = s.y_min, s.y_max do
                    for x = s.x_min, s.x_max do
                        check(seen[Layouts.posKey(x, y, s.layer)] ~= nil,
                            id .. " block tile " .. x .. "," .. y .. ",L" .. s.layer .. " is present")
                    end
                end
            elseif s.kind == "set" then
                for _, pt in ipairs(s.points) do
                    check(seen[Layouts.posKey(pt.x, pt.y, s.layer)] ~= nil,
                        id .. " set tile " .. pt.x .. "," .. pt.y .. ",L" .. s.layer .. " is present")
                end
            else
                check(seen[Layouts.posKey(s.x, s.y, s.layer)] ~= nil,
                    id .. " tile " .. s.x .. "," .. s.y .. ",L" .. s.layer .. " is present")
            end
        end
    end

    -- Per-layout shape (US-04/15/16/22/23/24/25/26/27/28/29): Turtle
    -- 87/36/16/4/1, Spider 65/53/25/1, Bridge 88/36/16/4, Ziggurat
    -- 64/20/18/18/14/10, Cloud 79/36/29, Tic-Tac-Toe 40/36/28/20/20, Red Dragon
    -- 82/45/17, Overpass 52/20/16/32/24, Pyramid's Walls 41/34/27/20/13/6/3,
    -- Confounding Cross 47/42/27/18/9/1, Taipei 63/46/19/10/3/2/1.
    checkShape("turtle", { [0] = 87, [1] = 36, [2] = 16, [3] = 4, [4] = 1 },
        { x_min = 0, x_max = 14, y_min = 0, y_max = 7 })
    checkShape("spider", { [0] = 65, [1] = 53, [2] = 25, [3] = 1 },
        { x_min = 0.5, x_max = 14.5, y_min = 0, y_max = 7 })
    checkShape("bridge", { [0] = 88, [1] = 36, [2] = 16, [3] = 4 },
        { x_min = 0, x_max = 12, y_min = 0, y_max = 8 })
    checkShape("ziggurat", { [0] = 64, [1] = 20, [2] = 18, [3] = 18, [4] = 14, [5] = 10 },
        { x_min = 0, x_max = 14, y_min = 0, y_max = 7 })
    checkShape("cloud", { [0] = 79, [1] = 36, [2] = 29 },
        { x_min = 0, x_max = 13, y_min = 0, y_max = 5.5 })
    checkShape("tictactoe", { [0] = 40, [1] = 36, [2] = 28, [3] = 20, [4] = 20 },
        { x_min = 0, x_max = 12, y_min = 0, y_max = 8 })
    checkShape("red-dragon", { [0] = 82, [1] = 45, [2] = 17 },
        { x_min = 0, x_max = 14, y_min = 0, y_max = 6.5 })
    checkShape("overpass", { [0] = 52, [1] = 20, [2] = 16, [3] = 32, [4] = 24 },
        { x_min = 0, x_max = 11, y_min = 0, y_max = 8 })
    checkShape("pyramid", { [0] = 41, [1] = 34, [2] = 27, [3] = 20, [4] = 13, [5] = 6, [6] = 3 },
        { x_min = 0, x_max = 11, y_min = 1, y_max = 7 })
    checkShape("confounding", { [0] = 47, [1] = 42, [2] = 27, [3] = 18, [4] = 9, [5] = 1 },
        { x_min = 0, x_max = 10, y_min = 0, y_max = 8 })
    checkShape("taipei", { [0] = 63, [1] = 46, [2] = 19, [3] = 10, [4] = 3, [5] = 2, [6] = 1 },
        { x_min = 0, x_max = 10, y_min = 0, y_max = 6 })

    -- maxLayer per layout.
    check(Layouts.maxLayer("turtle") == 4, "maxLayer(turtle) == 4")
    check(Layouts.maxLayer("spider") == 3, "maxLayer(spider) == 3")
    check(Layouts.maxLayer("bridge") == 3, "maxLayer(bridge) == 3")
    check(Layouts.maxLayer("ziggurat") == 5, "maxLayer(ziggurat) == 5")
    check(Layouts.maxLayer("cloud") == 2, "maxLayer(cloud) == 2")
    check(Layouts.maxLayer("tictactoe") == 4, "maxLayer(tictactoe) == 4")
    check(Layouts.maxLayer("red-dragon") == 2, "maxLayer(red-dragon) == 2")
    check(Layouts.maxLayer("overpass") == 4, "maxLayer(overpass) == 4")
    check(Layouts.maxLayer("pyramid") == 6, "maxLayer(pyramid) == 6")
    check(Layouts.maxLayer("confounding") == 5, "maxLayer(confounding) == 5")
    check(Layouts.maxLayer("taipei") == 6, "maxLayer(taipei) == 6")

    -- Registry behavior (US-14..US-29): the eleven built-ins are enumerated
    -- sorted; memoization is per-id; an unknown id falls back to the id itself.
    local ids = Layouts.layoutIds()
    check(#ids == 11 and ids[1] == "bridge" and ids[2] == "cloud"
        and ids[3] == "confounding" and ids[4] == "overpass"
        and ids[5] == "pyramid" and ids[6] == "red-dragon"
        and ids[7] == "spider" and ids[8] == "taipei"
        and ids[9] == "tictactoe" and ids[10] == "turtle"
        and ids[11] == "ziggurat",
        "layoutIds returns exactly {bridge, cloud, confounding, overpass, pyramid,\n"
        .. "red-dragon, spider, taipei, tictactoe, turtle, ziggurat} (got "
        .. table.concat(ids, ",") .. ")")
    check(Layouts.layoutName("turtle") == "Turtle", "layoutName returns the registered Turtle name")
    check(Layouts.layoutName("spider") == "Spider", "layoutName returns Spider's registered name")
    check(Layouts.layoutName("bridge") == "Bridge", "layoutName returns Bridge's registered name")
    check(Layouts.layoutName("ziggurat") == "Ziggurat", "layoutName returns Ziggurat's registered name")
    check(Layouts.layoutName("cloud") == "Cloud", "layoutName returns Cloud's registered name")
    check(Layouts.layoutName("tictactoe") == "Tic-Tac-Toe", "layoutName returns Tic-Tac-Toe's registered name")
    check(Layouts.layoutName("red-dragon") == "Red Dragon", "layoutName returns Red Dragon's registered name")
    check(Layouts.layoutName("overpass") == "Overpass", "layoutName returns Overpass's registered name")
    check(Layouts.layoutName("pyramid") == "Pyramid's Walls",
        "layoutName returns Pyramid's Walls' registered name")
    check(Layouts.layoutName("confounding") == "Confounding Cross",
        "layoutName returns Confounding Cross's registered name")
    check(Layouts.layoutName("taipei") == "Taipei", "layoutName returns Taipei's registered name")
    check(Layouts.layoutName("nope") == "nope",
        "layoutName falls back to the id for an unknown layout")
    check(Layouts.buildLayout("turtle") == Layouts.buildLayout(),
        "buildLayout(id) and buildLayout() share one memoized Turtle table")
    check(Layouts.buildLayout("turtle") == Layouts.buildLayout("turtle"),
        "buildLayout(id) is memoized per id")
    check(Layouts.gridBounds("turtle") == Layouts.gridBounds(),
        "gridBounds(id) and gridBounds() share one memoized Turtle bounds")
    check(Layouts.gridBounds("turtle") == Layouts.gridBounds("turtle"),
        "gridBounds(id) is memoized per id")
    check(Layouts.isLayoutPosition(6.5, 3.5, 4, "turtle"),
        "isLayoutPosition accepts a Turtle position with an explicit id")
    check(not Layouts.isLayoutPosition(99, 99, 0, "turtle"),
        "isLayoutPosition rejects an out-of-layout position with an explicit id")

    -- register / re-register / deregister (US-22a): a throwaway layout can be
    -- registered, re-registering the same id with a new spec drops its caches,
    -- and deregisterLayout removes the entry + caches (idempotent).
    local toy_spec = {
        { layer = 0, kind = "row",   x_min = 0, x_max = 1, y = 0 },
        { layer = 0, kind = "row",   x_min = 0, x_max = 1, y = 1 },
        { layer = 1, kind = "tile",  x = 0,    y = 0 },
    }
    Layouts.registerLayout{ id = "toy", name = "Toy", spec = toy_spec }
    local toy_ids = Layouts.layoutIds()
    check(#toy_ids == 12 and toy_ids[1] == "bridge" and toy_ids[2] == "cloud"
        and toy_ids[3] == "confounding" and toy_ids[4] == "overpass"
        and toy_ids[5] == "pyramid" and toy_ids[6] == "red-dragon"
        and toy_ids[7] == "spider" and toy_ids[8] == "taipei"
        and toy_ids[9] == "tictactoe" and toy_ids[10] == "toy"
        and toy_ids[11] == "turtle" and toy_ids[12] == "ziggurat",
        "registerLayout adds the id; layoutIds returns them sorted (got " .. table.concat(toy_ids, ",") .. ")")
    check(#Layouts.buildLayout("toy") == 5, "the toy layout has 5 positions")
    check(Layouts.maxLayer("toy") == 1, "the toy layout's max layer is 1")
    check(Layouts.isLayoutPosition(0, 0, 1, "toy"),
        "isLayoutPosition validates against the toy layout")
    check(not Layouts.isLayoutPosition(2, 0, 0, "toy"),
        "isLayoutPosition rejects a Turtle-only position against the toy layout")
    local toy_bounds = Layouts.gridBounds("toy")
    check(toy_bounds.x_min == 0 and toy_bounds.x_max == 1
            and toy_bounds.y_min == 0 and toy_bounds.y_max == 1,
        "gridBounds(toy) extents are 0..1 x 0..1")

    local toy_spec2 = {
        { layer = 0, kind = "row", x_min = 0, x_max = 2, y = 0 },
    }
    Layouts.registerLayout{ id = "toy", name = "Toy2", spec = toy_spec2 }
    check(#Layouts.buildLayout("toy") == 3,
        "re-registering an id drops its cache and picks up the new spec")
    check(Layouts.layoutName("toy") == "Toy2", "re-registering an id replaces its name")

    Layouts.deregisterLayout("toy")
    check(Layouts.layouts["toy"] == nil and #Layouts.layoutIds() == 11,
        "deregisterLayout removes the entry and restores the built-in registry")
    Layouts.deregisterLayout("toy")
    check(#Layouts.layoutIds() == 11,
        "deregisterLayout is a no-op for an already-deregistered id")

    local function checkError(fn, msg)
        local ok, err = pcall(fn)
        check(not ok and type(err) == "string" and err ~= "", msg)
    end
    checkError(function() Layouts.registerLayout{ id = 42, spec = {} } end,
        "registerLayout rejects a non-string id")
    checkError(function() Layouts.deregisterLayout(42) end,
        "deregisterLayout rejects a non-string id")

    io.write("All layout self-tests passed.\n")
    return true
end

-- Run self-tests when executed directly (`lua mahjonglayouts.lua`) or with
-- `lua mahjonglayouts.lua --selftest`.
if select("#", ...) == 0 then
    Layouts.runSelfTests()
end

return Layouts
