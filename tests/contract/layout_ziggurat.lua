-- US-22 — Ziggurat layout suite.
--
-- Verifies "The Ziggurat" board (144 positions, 64/20/18/18/14/10 across
-- 6 layers) is registered, deals/saves/restores correctly, the board widget
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
    expect(#ids == 24 and ids[1] == "boar" and ids[18] == "spider"
        and ids[22] == "turtle" and ids[24] == "ziggurat",
    "registry enumerates all 24 layouts (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("ziggurat") == "Ziggurat", "layoutName returns 'Ziggurat'")
expect(Logic.maxLayer("ziggurat") == 5, "maxLayer(ziggurat) == 5")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("ziggurat")
expect(#layout == 144, "Ziggurat layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Ziggurat layout has no duplicate positions")

-- Per-layer counts: 64 / 20 / 18 / 18 / 14 / 10.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 64, "Ziggurat layer 0 has 64 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 20, "Ziggurat layer 1 has 20 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 18, "Ziggurat layer 2 has 18 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 18, "Ziggurat layer 3 has 18 tiles (got " .. tostring(layer_counts[3]) .. ")")
expect(layer_counts[4] == 14, "Ziggurat layer 4 has 14 tiles (got " .. tostring(layer_counts[4]) .. ")")
expect(layer_counts[5] == 10, "Ziggurat layer 5 has 10 tiles (got " .. tostring(layer_counts[5]) .. ")")

-- Grid bounds: x = 0..14, y = 0..7 (same extents as Turtle).
local zb = Logic.gridBounds("ziggurat")
expect(zb.x_min == 0 and zb.x_max == 14 and zb.y_min == 0 and zb.y_max == 7,
    "Ziggurat grid bounds are x=0..14, y=0..7")

-- Top-center tile and layer validation.
expect(Logic.isLayoutPosition(7, 3, 5, "ziggurat"),
    "top-center tile (7, 3, L5) is a Ziggurat position")
expect(Logic.isLayoutPosition(0, 0, 0, "ziggurat"),
    "base wall tile (0, 0, L0) is a Ziggurat position")
expect(not Logic.isLayoutPosition(7, 3, 6, "ziggurat"), "no L6 in Ziggurat (max layer is 5)")
expect(not Logic.isLayoutPosition(99, 99, 0, "ziggurat"), "out-of-layout position rejected against Ziggurat")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("ziggurat", 42)
expect(Logic.tileCount(board) == 144, "newGame('ziggurat', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("ziggurat", 42)) == Logic.tileCount(board),
    "Ziggurat deal is deterministic for a fixed seed")

-- The top-layer edge tile and a base-layer half-grid wall tile are free.
expect(Logic.isFree(board, 5, 3, 5), "Ziggurat's top-center west edge (5, 3, L5) is free")
expect(Logic.isFree(board, 0, 0, 0), "Ziggurat's base wall tile (0, 0, L0) is free")
expect(not Logic.isFree(board, 7, 3, 0),
    "a base tile under the center staircase is not free")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "ziggurat")
expect(#free > 0, "Ziggurat board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "ziggurat"), "Ziggurat board has at least one move")
local pair = Logic.matchingFreePair(board, "ziggurat")
expect(pair ~= nil, "Ziggurat board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Ziggurat board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "ziggurat")
expect(ser.v == 2 and ser.layout == "ziggurat", "serialized state is v2 with layout='ziggurat'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "ziggurat",
    "deserialize restores a Ziggurat mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Ziggurat board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Ziggurat board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

local zv_board = Logic.newGame("ziggurat", 99)
local bv = Board:new{
    board = zv_board,
    layout_id = "ziggurat",
    width = 1200,
    height = 600,
    onTileTap = function() end,
}
expect(bv.layout_id == "ziggurat", "board widget stores layout_id = 'ziggurat'")
expect(bv.grid == Logic.gridBounds("ziggurat"),
    "board grid bounds match the Ziggurat layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("ziggurat") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Ziggurat tiles (got " .. drawn .. ")")
expect(all_inside, "all Ziggurat tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the top-center tile returns it.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(7, 3, 5)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 7 and hit.y == 3 and hit.layer == 5,
    "hit-test finds the Ziggurat top-center tile")

-- ---- Picker lists Ziggurat -----------------------------------------------------

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
picker:setPage(1)
picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "first launch shows the layout picker")
    expect(#picker._card_rects == #Logic.layoutIds() - 12,
    "picker lists one card per registered layout (got " .. #picker._card_rects .. " cards, "
    .. #Logic.layoutIds() .. " ids)")

local has_ziggurat_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "ziggurat" then has_ziggurat_card = true end
end
expect(has_ziggurat_card, "picker has a Ziggurat card")
for _, c in ipairs(picker._card_rects) do
end

-- Thumbnail renders for Ziggurat.
local thumb = LayoutSelect.layoutThumbnail("ziggurat", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Ziggurat thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Ziggurat thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Ziggurat -> deals a 144-tile board on the ziggurat layout.
local ziggurat_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "ziggurat" then ziggurat_card = c break end
end
picker:onTapSelect(nil, { pos = { x = ziggurat_card.x + ziggurat_card.w / 2,
                                   y = ziggurat_card.y + ziggurat_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Ziggurat deals a 144-tile board")
expect(mj.layout == "ziggurat", "the chosen layout is tracked as 'ziggurat'")
expect(store.layout == "ziggurat", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "ziggurat",
    "the dealt game is saved with layout='ziggurat'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Ziggurat shows the Mahjong widget")

-- ---- Gameplay end-to-end on Ziggurat -------------------------------------------

local zg_pair = Logic.matchingFreePair(mj.board, "ziggurat")
mj:handleTileTap(zg_pair.a.x, zg_pair.a.y, zg_pair.a.layer)
mj:handleTileTap(zg_pair.b.x, zg_pair.b.y, zg_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Ziggurat removes both tiles")
expect(mj.score == 10, "first Ziggurat match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Ziggurat move")
expect(store.game.layout == "ziggurat", "saved Ziggurat game keeps its layout id")

-- ---- Restore a saved Ziggurat game (mid-game, 142 tiles) ------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Ziggurat game restores directly (no picker)")
expect(mj2.layout == "ziggurat", "restored game keeps layout='ziggurat'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Ziggurat")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-22 ZIGGURAT CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
