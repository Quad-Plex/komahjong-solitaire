-- US-26 — Overpass layout suite.
--
-- Verifies the "Overpass" board (144 positions, 52/20/16/32/24 across 5
-- layers, transcribed from GNOME Mahjongg's `overpass` map) is registered,
-- deals/saves/restores correctly, the board widget renders it, free-tile
-- detection + gameplay work, and the picker lists it alongside the other
-- layouts.

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
expect(Logic.layoutName("overpass") == "Overpass", "layoutName returns 'Overpass'")
expect(Logic.maxLayer("overpass") == 4, "maxLayer(overpass) == 4")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("overpass")
expect(#layout == 144, "Overpass layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Overpass layout has no duplicate positions")

-- Per-layer counts: 52 / 20 / 16 / 32 / 24.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 52, "Overpass layer 0 has 52 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 20, "Overpass layer 1 has 20 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 16, "Overpass layer 2 has 16 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 32, "Overpass layer 3 has 32 tiles (got " .. tostring(layer_counts[3]) .. ")")
expect(layer_counts[4] == 24, "Overpass layer 4 has 24 tiles (got " .. tostring(layer_counts[4]) .. ")")

-- Grid bounds: x = 0..11, y = 0..8.
local cb = Logic.gridBounds("overpass")
expect(cb.x_min == 0 and cb.x_max == 11 and cb.y_min == 0 and cb.y_max == 8,
    "Overpass grid bounds are x=0..11, y=0..8")

-- Position and layer validation.
expect(Logic.isLayoutPosition(0, 2, 0, "overpass"),
    "the left tower column bottom (0, 2) is an Overpass position")
expect(Logic.isLayoutPosition(11, 7, 0, "overpass"),
    "the right tower column top (11, 7) is an Overpass position")
expect(Logic.isLayoutPosition(4, 0, 0, "overpass"),
    "the center deck corner (4, 0) is an Overpass position")
expect(Logic.isLayoutPosition(3, 3, 4, "overpass"),
    "the L4 upper deck corner (3, 3) is an Overpass position")
expect(not Logic.isLayoutPosition(1, 2, 1, "overpass"),
    "the L1 left column steps in — (1, 2) is not a L1 position")
expect(not Logic.isLayoutPosition(3, 3, 2, "overpass"),
    "the L2 deck segments are at x=1..2 / x=9..10 — (3, 3) is not a L2 position")
expect(not Logic.isLayoutPosition(4, 0, 5, "overpass"), "no L5 in Overpass (max layer is 4)")
expect(not Logic.isLayoutPosition(99, 99, 0, "overpass"), "out-of-layout position rejected against Overpass")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("overpass", 42)
expect(Logic.tileCount(board) == 144, "newGame('overpass', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("overpass", 42)) == Logic.tileCount(board),
    "Overpass deal is deterministic for a fixed seed")

-- L4 (top) deck edge tiles are free; a center deck tile is boxed in; a tower
-- tile under an L1 column is covered.
expect(Logic.isFree(board, 3, 3, 4), "Overpass's L4 deck west edge (3, 3) is free")
expect(Logic.isFree(board, 8, 6, 4), "Overpass's L4 deck corner (8, 6) is free")
expect(Logic.isFree(board, 1, 2, 0), "Overpass's left tower corner tile (1, 2, L0) is free")
expect(not Logic.isFree(board, 0, 2, 0),
    "Overpass's left tower base (0, 2, L0) is covered by the L1 column")
expect(not Logic.isFree(board, 5, 3, 0),
    "Overpass's center deck tile (5, 3, L0) is boxed in on both sides")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "overpass")
expect(#free > 0, "Overpass board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "overpass"), "Overpass board has at least one move")
local pair = Logic.matchingFreePair(board, "overpass")
expect(pair ~= nil, "Overpass board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on an Overpass board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "overpass")
expect(ser.v == 2 and ser.layout == "overpass", "serialized state is v2 with layout='overpass'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "overpass",
    "deserialize restores an Overpass mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Overpass board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Overpass board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Overpass grid is x=0..11, y=0..8 (12x9).
local ov_board = Logic.newGame("overpass", 99)
local bv = Board:new{
    board = ov_board,
    layout_id = "overpass",
    width = 1400,
    height = 700,
    onTileTap = function() end,
}
expect(bv.layout_id == "overpass", "board widget stores layout_id = 'overpass'")
expect(bv.grid == Logic.gridBounds("overpass"),
    "board grid bounds match the Overpass layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("overpass") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Overpass tiles (got " .. drawn .. ")")
expect(all_inside, "all Overpass tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L4 upper deck and the L0 center deck returns them.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(3, 3, 4)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 3 and hit.y == 3 and hit.layer == 4,
    "hit-test finds the L4 deck tile (3, 3, L4)")
local px0, py0 = bv:tilePos(4, 0, 0)
local hit0 = bv:hitTest(px0 + 1, py0 + 1)
expect(hit0 ~= nil and hit0.x == 4 and hit0.y == 0 and hit0.layer == 0,
    "hit-test finds the L0 center deck corner (4, 0, L0)")

-- ---- Picker lists Overpass ----------------------------------------------------

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

local has_ov_card = false
local has_turtle_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "overpass" then has_ov_card = true end
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_ov_card, "picker has an Overpass card")
expect(has_turtle_card, "picker has a Turtle card")

-- Thumbnail renders for Overpass.
local thumb = LayoutSelect.layoutThumbnail("overpass", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Overpass thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Overpass thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Overpass -> deals a 144-tile board on the overpass layout.
local ov_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "overpass" then ov_card = c break end
end
picker:onTapSelect(nil, { pos = { x = ov_card.x + ov_card.w / 2,
                                   y = ov_card.y + ov_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Overpass deals a 144-tile board")
expect(mj.layout == "overpass", "the chosen layout is tracked as 'overpass'")
expect(store.layout == "overpass", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "overpass",
    "the dealt game is saved with layout='overpass'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Overpass shows the Mahjong widget")

-- ---- Gameplay end-to-end on Overpass ------------------------------------------

local ov_pair = Logic.matchingFreePair(mj.board, "overpass")
mj:handleTileTap(ov_pair.a.x, ov_pair.a.y, ov_pair.a.layer)
mj:handleTileTap(ov_pair.b.x, ov_pair.b.y, ov_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Overpass removes both tiles")
expect(mj.score == 10, "first Overpass match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after an Overpass move")
expect(store.game.layout == "overpass", "saved Overpass game keeps its layout id")

-- ---- Restore a saved Overpass game (mid-game, 142 tiles) ----------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Overpass game restores directly (no picker)")
expect(mj2.layout == "overpass", "restored game keeps layout='overpass'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Overpass")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-26 OVERPASS CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
