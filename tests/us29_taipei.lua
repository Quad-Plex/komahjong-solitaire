-- US-29 — Taipei layout suite.
--
-- Verifies the "Taipei" board (144 positions, 63/46/19/10/3/2/1 across 7
-- layers, transcribed from GNOME Mahjongg's `difficult` map — the iconic
-- fortified Great Wall board with tiered walls rising to a single peak tile
-- on layer 6) is registered, deals/saves/restores correctly, the board widget
-- renders it, free-tile detection + gameplay work, and the picker lists it
-- alongside the other layouts.

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
expect(#ids == 12 and ids[1] == "bridge" and ids[2] == "cloud" and ids[3] == "confounding"
        and ids[4] == "crab" and ids[5] == "overpass" and ids[6] == "pyramid"
        and ids[7] == "red-dragon" and ids[8] == "spider" and ids[9] == "taipei"
        and ids[10] == "tictactoe" and ids[11] == "turtle" and ids[12] == "ziggurat",
    "registry enumerates {bridge, cloud, confounding, crab, overpass, pyramid, red-dragon,\n"
    .. "spider, taipei, tictactoe, turtle, ziggurat} (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("taipei") == "Taipei", "layoutName returns 'Taipei'")
expect(Logic.maxLayer("taipei") == 6, "maxLayer(taipei) == 6")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("taipei")
expect(#layout == 144, "Taipei layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Taipei layout has no duplicate positions")

-- Per-layer counts: 63 / 46 / 19 / 10 / 3 / 2 / 1.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 63, "Taipei layer 0 has 63 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 46, "Taipei layer 1 has 46 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 19, "Taipei layer 2 has 19 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 10, "Taipei layer 3 has 10 tiles (got " .. tostring(layer_counts[3]) .. ")")
expect(layer_counts[4] == 3,  "Taipei layer 4 has 3 tiles (got " .. tostring(layer_counts[4]) .. ")")
expect(layer_counts[5] == 2,  "Taipei layer 5 has 2 tiles (got " .. tostring(layer_counts[5]) .. ")")
expect(layer_counts[6] == 1,  "Taipei layer 6 has 1 tile (got " .. tostring(layer_counts[6]) .. ")")

-- Grid bounds: x = 0..10, y = 0..6.
local cb = Logic.gridBounds("taipei")
expect(cb.x_min == 0 and cb.x_max == 10 and cb.y_min == 0 and cb.y_max == 6,
    "Taipei grid bounds are x=0..10, y=0..6")

-- Position and layer validation.
expect(Logic.isLayoutPosition(0, 3, 0, "taipei"),
    "the L0 left tower tile (0, 3) is a Taipei position")
expect(Logic.isLayoutPosition(10, 3, 0, "taipei"),
    "the L0 right tower tile (10, 3) is a Taipei position")
expect(Logic.isLayoutPosition(3, 0, 0, "taipei"),
    "the L0 top row west end (3, 0) is a Taipei position")
expect(Logic.isLayoutPosition(5, 3, 6, "taipei"),
    "the L6 peak tile (5, 3) is a Taipei position")
expect(not Logic.isLayoutPosition(3, 0, 1, "taipei"),
    "the L1 tower peaks are at x=3.5/x=6.5 — (3, 0) is not a L1 position")
expect(not Logic.isLayoutPosition(5, 3, 7, "taipei"), "no L7 in Taipei (max layer is 6)")
expect(not Logic.isLayoutPosition(99, 99, 0, "taipei"), "out-of-layout position rejected against Taipei")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("taipei", 42)
expect(Logic.tileCount(board) == 144, "newGame('taipei', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("taipei", 42)) == Logic.tileCount(board),
    "Taipei deal is deterministic for a fixed seed")

-- The L6 peak is free; a left tower tile is free (nothing above it, west side
-- open); a center base tile is covered by the L1 center block.
expect(Logic.isFree(board, 5, 3, 6), "Taipei's L6 peak (5, 3) is free")
expect(Logic.isFree(board, 0, 3, 0), "Taipei's L0 left tower tile (0, 3) is free")
expect(not Logic.isFree(board, 3, 2, 0),
    "Taipei's L0 center base (3, 2) is covered by the L1 center block")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "taipei")
expect(#free > 0, "Taipei board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "taipei"), "Taipei board has at least one move")
local pair = Logic.matchingFreePair(board, "taipei")
expect(pair ~= nil, "Taipei board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Taipei board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "taipei")
expect(ser.v == 2 and ser.layout == "taipei", "serialized state is v2 with layout='taipei'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "taipei",
    "deserialize restores a Taipei mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Taipei board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Taipei board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Taipei grid is x=0..10, y=0..6 (11x7) with 7 layers.
local tp_board = Logic.newGame("taipei", 99)
local bv = Board:new{
    board = tp_board,
    layout_id = "taipei",
    width = 1400,
    height = 800,
    onTileTap = function() end,
}
expect(bv.layout_id == "taipei", "board widget stores layout_id = 'taipei'")
expect(bv.grid == Logic.gridBounds("taipei"),
    "board grid bounds match the Taipei layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("taipei") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Taipei tiles (got " .. drawn .. ")")
expect(all_inside, "all Taipei tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

local function tileIndex(x, y, layer)
    for i, tile in ipairs(bv.tiles_by_layer[layer] or {}) do
        if tile.x == x and tile.y == y then return i end
    end
    return nil
end
expect(tileIndex(1.5, 1.5, 0) < tileIndex(2.5, 1, 0),
    "Taipei's upper-left diagonal overlap paints after the lower-left tile")
expect(tileIndex(7.5, 1, 0) < tileIndex(8.5, 0.5, 0),
    "Taipei's upper-right diagonal overlap paints after the lower-left tile")
expect(tileIndex(1.5, 5.5, 0) < tileIndex(2.5, 5, 0),
    "Taipei's lower-left diagonal overlap paints after the lower-left tile")
expect(tileIndex(7.5, 5, 0) < tileIndex(8.5, 4.5, 0),
    "Taipei's lower-right diagonal overlap paints after the lower-left tile")

-- Hit-test: tapping the L6 peak and a L0 tower tile returns them.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(5, 3, 6)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 5 and hit.y == 3 and hit.layer == 6,
    "hit-test finds the L6 peak tile (5, 3, L6)")
local px0, py0 = bv:tilePos(0, 3, 0)
local hit0 = bv:hitTest(px0 + 1, py0 + 1)
expect(hit0 ~= nil and hit0.x == 0 and hit0.y == 3 and hit0.layer == 0,
    "hit-test finds the L0 left tower tile (0, 3, L0)")

-- ---- Picker lists Taipei ------------------------------------------------------

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

local has_tp_card = false
local has_turtle_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "taipei" then has_tp_card = true end
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_tp_card, "picker has a Taipei card")
expect(has_turtle_card, "picker has a Turtle card")

-- Thumbnail renders for Taipei.
local thumb = LayoutSelect.layoutThumbnail("taipei", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Taipei thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Taipei thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Taipei -> deals a 144-tile board on the taipei layout.
local tp_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "taipei" then tp_card = c break end
end
picker:onTapSelect(nil, { pos = { x = tp_card.x + tp_card.w / 2,
                                   y = tp_card.y + tp_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Taipei deals a 144-tile board")
expect(mj.layout == "taipei", "the chosen layout is tracked as 'taipei'")
expect(store.layout == "taipei", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "taipei",
    "the dealt game is saved with layout='taipei'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Taipei shows the Mahjong widget")

-- ---- Gameplay end-to-end on Taipei ----------------------------------------------

local tp_pair = Logic.matchingFreePair(mj.board, "taipei")
mj:handleTileTap(tp_pair.a.x, tp_pair.a.y, tp_pair.a.layer)
mj:handleTileTap(tp_pair.b.x, tp_pair.b.y, tp_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Taipei removes both tiles")
expect(mj.score == 10, "first Taipei match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Taipei move")
expect(store.game.layout == "taipei", "saved Taipei game keeps its layout id")

-- ---- Restore a saved Taipei game (mid-game, 142 tiles) --------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Taipei game restores directly (no picker)")
expect(mj2.layout == "taipei", "restored game keeps layout='taipei'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Taipei")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-29 TAIPEI CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
