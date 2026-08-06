-- US-27 — Pyramid's Walls layout suite.
--
-- Verifies the "Pyramid's Walls" board (144 positions, 41/34/27/20/13/6/3
-- across 7 layers — the deepest board — transcribed from GNOME Mahjongg's
-- `pyramid` map, concentric square rings rising to three peak tiles on layer
-- 6) is registered, deals/saves/restores correctly, the board widget renders
-- it, free-tile detection + gameplay work, and the picker lists it alongside
-- the other layouts.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Board = ctx.loadPlugin("mahjongboard")
local LayoutSelect = ctx.loadPlugin("mahjonglayoutselect")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- ---- Registry ---------------------------------------------------------------

local ids = Logic.layoutIds()
expect(#ids == 11 and ids[1] == "bridge" and ids[2] == "cloud" and ids[3] == "confounding"
        and ids[4] == "overpass" and ids[5] == "pyramid" and ids[6] == "red-dragon"
        and ids[7] == "spider" and ids[8] == "taipei" and ids[9] == "tictactoe"
        and ids[10] == "turtle" and ids[11] == "ziggurat",
    "registry enumerates {bridge, cloud, confounding, overpass, pyramid, red-dragon,\n"
    .. "spider, taipei, tictactoe, turtle, ziggurat} (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("pyramid") == "Pyramid's Walls",
    "layoutName returns 'Pyramid's Walls'")
expect(Logic.maxLayer("pyramid") == 6, "maxLayer(pyramid) == 6")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("pyramid")
expect(#layout == 144, "Pyramid layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Pyramid layout has no duplicate positions")

-- Per-layer counts: 41 / 34 / 27 / 20 / 13 / 6 / 3.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 41, "Pyramid layer 0 has 41 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 34, "Pyramid layer 1 has 34 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 27, "Pyramid layer 2 has 27 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 20, "Pyramid layer 3 has 20 tiles (got " .. tostring(layer_counts[3]) .. ")")
expect(layer_counts[4] == 13, "Pyramid layer 4 has 13 tiles (got " .. tostring(layer_counts[4]) .. ")")
expect(layer_counts[5] == 6,  "Pyramid layer 5 has 6 tiles (got " .. tostring(layer_counts[5]) .. ")")
expect(layer_counts[6] == 3,  "Pyramid layer 6 has 3 tiles (got " .. tostring(layer_counts[6]) .. ")")

-- Grid bounds: x = 0..11, y = 1..7 (the map's rings span rows 1..7).
local cb = Logic.gridBounds("pyramid")
expect(cb.x_min == 0 and cb.x_max == 11 and cb.y_min == 1 and cb.y_max == 7,
    "Pyramid grid bounds are x=0..11, y=1..7")

-- Position and layer validation.
expect(Logic.isLayoutPosition(0, 1, 0, "pyramid"),
    "the L0 border row west end (0, 1) is a Pyramid position")
expect(Logic.isLayoutPosition(11, 7, 0, "pyramid"),
    "the L0 border row east end (11, 7) is a Pyramid position")
expect(Logic.isLayoutPosition(0, 4, 0, "pyramid"),
    "the L0 left column middle (0, 4) is a Pyramid position")
expect(Logic.isLayoutPosition(5.5, 4, 6, "pyramid"),
    "the L6 peak tile (5.5, 4) is a Pyramid position")
expect(Logic.isLayoutPosition(5.5, 1, 6, "pyramid"),
    "the L6 top peak tile (5.5, 1) is a Pyramid position")
expect(not Logic.isLayoutPosition(5, 1, 6, "pyramid"),
    "the L6 peaks are only at x=5.5 — (5, 1) is not a L6 position")
expect(not Logic.isLayoutPosition(0, 0, 0, "pyramid"),
    "Pyramid's rows span y=1..7 — there is no tile at y=0")
expect(not Logic.isLayoutPosition(5.5, 4, 7, "pyramid"), "no L7 in Pyramid (max layer is 6)")
expect(not Logic.isLayoutPosition(99, 99, 0, "pyramid"), "out-of-layout position rejected against Pyramid")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("pyramid", 42)
expect(Logic.tileCount(board) == 144, "newGame('pyramid', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("pyramid", 42)) == Logic.tileCount(board),
    "Pyramid deal is deterministic for a fixed seed")

-- The L6 peak tiles are free (nothing above, both sides open); the border
-- column tiles are covered by the layer above them.
expect(Logic.isFree(board, 5.5, 4, 6), "Pyramid's L6 peak (5.5, 4) is free")
expect(Logic.isFree(board, 5.5, 1, 6), "Pyramid's L6 top peak (5.5, 1) is free")
expect(not Logic.isFree(board, 0, 4, 0),
    "Pyramid's L0 left column (0, 4) is covered by the L1 column")
expect(not Logic.isFree(board, 5, 4, 0),
    "Pyramid's L0 middle bar (5, 4) is covered by the L1 bar")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "pyramid")
expect(#free > 0, "Pyramid board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "pyramid"), "Pyramid board has at least one move")
local pair = Logic.matchingFreePair(board, "pyramid")
expect(pair ~= nil, "Pyramid board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Pyramid board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "pyramid")
expect(ser.v == 2 and ser.layout == "pyramid", "serialized state is v2 with layout='pyramid'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "pyramid",
    "deserialize restores a Pyramid mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Pyramid board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Pyramid board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Pyramid grid is x=0..11, y=1..7 (12x7 span) with 7 layers.
local py_board = Logic.newGame("pyramid", 99)
local bv = Board:new{
    board = py_board,
    layout_id = "pyramid",
    width = 1400,
    height = 800,
    onTileTap = function() end,
}
expect(bv.layout_id == "pyramid", "board widget stores layout_id = 'pyramid'")
expect(bv.grid == Logic.gridBounds("pyramid"),
    "board grid bounds match the Pyramid layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("pyramid") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Pyramid tiles (got " .. drawn .. ")")
expect(all_inside, "all Pyramid tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L6 peak and a L0 border tile returns them.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(5.5, 4, 6)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 5.5 and hit.y == 4 and hit.layer == 6,
    "hit-test finds the L6 peak tile (5.5, 4, L6)")
local px0, py0 = bv:tilePos(0, 1, 0)
local hit0 = bv:hitTest(px0 + 1, py0 + 1)
expect(hit0 ~= nil and hit0.x == 0 and hit0.y == 1 and hit0.layer == 0,
    "hit-test finds the L0 border tile (0, 1, L0)")

-- ---- Picker lists Pyramid ------------------------------------------------------

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "first launch shows the layout picker")
expect(#picker._card_rects == #Logic.layoutIds(),
    "picker lists one card per registered layout (got " .. #picker._card_rects .. " cards, "
    .. #Logic.layoutIds() .. " ids)")

local has_py_card = false
local has_turtle_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "pyramid" then has_py_card = true end
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_py_card, "picker has a Pyramid card")
expect(has_turtle_card, "picker has a Turtle card")

-- Thumbnail renders for Pyramid.
local thumb = LayoutSelect.layoutThumbnail("pyramid", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Pyramid thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Pyramid thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Pyramid -> deals a 144-tile board on the pyramid layout.
local py_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "pyramid" then py_card = c break end
end
picker:onTapSelect(nil, { pos = { x = py_card.x + py_card.w / 2,
                                   y = py_card.y + py_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Pyramid deals a 144-tile board")
expect(mj.layout == "pyramid", "the chosen layout is tracked as 'pyramid'")
expect(store.layout == "pyramid", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "pyramid",
    "the dealt game is saved with layout='pyramid'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Pyramid shows the Mahjong widget")

-- ---- Gameplay end-to-end on Pyramid --------------------------------------------

local py_pair = Logic.matchingFreePair(mj.board, "pyramid")
mj:handleTileTap(py_pair.a.x, py_pair.a.y, py_pair.a.layer)
mj:handleTileTap(py_pair.b.x, py_pair.b.y, py_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Pyramid removes both tiles")
expect(mj.score == 10, "first Pyramid match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Pyramid move")
expect(store.game.layout == "pyramid", "saved Pyramid game keeps its layout id")

-- ---- Restore a saved Pyramid game (mid-game, 142 tiles) ------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Pyramid game restores directly (no picker)")
expect(mj2.layout == "pyramid", "restored game keeps layout='pyramid'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Pyramid")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-27 PYRAMID CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
