-- US-24 — Tic-Tac-Toe layout suite.
--
-- Verifies the "Tic-Tac-Toe" board (144 positions, 40/36/28/20/20 across 5
-- layers, transcribed from GNOME Mahjongg's `tictactoe` map) is registered,
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
    expect(#ids == 18 and ids[5] == "hare" and ids[13] == "spider"
        and ids[15] == "tictactoe" and ids[17] == "turtle",
    "registry enumerates all 18 layouts (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("tictactoe") == "Tic-Tac-Toe", "layoutName returns 'Tic-Tac-Toe'")
expect(Logic.maxLayer("tictactoe") == 4, "maxLayer(tictactoe) == 4")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("tictactoe")
expect(#layout == 144, "Tic-Tac-Toe layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Tic-Tac-Toe layout has no duplicate positions")

-- Per-layer counts: 40 / 36 / 28 / 20 / 20.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 40, "Tic-Tac-Toe layer 0 has 40 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 36, "Tic-Tac-Toe layer 1 has 36 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 28, "Tic-Tac-Toe layer 2 has 28 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 20, "Tic-Tac-Toe layer 3 has 20 tiles (got " .. tostring(layer_counts[3]) .. ")")
expect(layer_counts[4] == 20, "Tic-Tac-Toe layer 4 has 20 tiles (got " .. tostring(layer_counts[4]) .. ")")

-- Grid bounds: x = 0..12, y = 0..8.
local cb = Logic.gridBounds("tictactoe")
expect(cb.x_min == 0 and cb.x_max == 12 and cb.y_min == 0 and cb.y_max == 8,
    "Tic-Tac-Toe grid bounds are x=0..12, y=0..8")

-- Position and layer validation.
expect(Logic.isLayoutPosition(3, 8, 0, "tictactoe"),
    "the L0 column bottom (3, 8) is a Tic-Tac-Toe position")
expect(Logic.isLayoutPosition(12, 6, 0, "tictactoe"),
    "the L0 frame corner (12, 6) is a Tic-Tac-Toe position")
expect(Logic.isLayoutPosition(9, 2, 4, "tictactoe"),
    "the L4 column cap (9, 2) is a Tic-Tac-Toe position")
expect(not Logic.isLayoutPosition(0, 2, 1, "tictactoe"),
    "the L1 edge row steps in — (0, 2) is not a L1 position")
expect(not Logic.isLayoutPosition(9, 2, 5, "tictactoe"), "no L5 in Tic-Tac-Toe (max layer is 4)")
expect(not Logic.isLayoutPosition(99, 99, 0, "tictactoe"), "out-of-layout position rejected against Tic-Tac-Toe")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("tictactoe", 42)
expect(Logic.tileCount(board) == 144, "newGame('tictactoe', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("tictactoe", 42)) == Logic.tileCount(board),
    "Tic-Tac-Toe deal is deterministic for a fixed seed")

-- L4 (top) tiles are never covered; the free column tiles have both sides
-- open, while the center row tiles are boxed in.
expect(Logic.isFree(board, 3, 3, 4), "Tic-Tac-Toe's L4 column interior (3, 3) is free")
expect(Logic.isFree(board, 9, 2, 4), "Tic-Tac-Toe's L4 column cap (9, 2) is free")
expect(not Logic.isFree(board, 6, 2, 4),
    "Tic-Tac-Toe's L4 center row interior (6, 2) is boxed in on both sides")
-- A base-frame tile with an open east side is free; a base center-row tile is
-- covered from above by L1.
expect(Logic.isFree(board, 12, 6, 0), "Tic-Tac-Toe's base frame corner (12, 6, L0) is free")
expect(not Logic.isFree(board, 6, 2, 0),
    "Tic-Tac-Toe's base center-row tile (6, 2, L0) is covered from above")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "tictactoe")
expect(#free > 0, "Tic-Tac-Toe board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "tictactoe"), "Tic-Tac-Toe board has at least one move")
local pair = Logic.matchingFreePair(board, "tictactoe")
expect(pair ~= nil, "Tic-Tac-Toe board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Tic-Tac-Toe board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "tictactoe")
expect(ser.v == 2 and ser.layout == "tictactoe", "serialized state is v2 with layout='tictactoe'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "tictactoe",
    "deserialize restores a Tic-Tac-Toe mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Tic-Tac-Toe board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Tic-Tac-Toe board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Tic-Tac-Toe grid is x=0..12, y=0..8 (13x9).
local tt_board = Logic.newGame("tictactoe", 99)
local bv = Board:new{
    board = tt_board,
    layout_id = "tictactoe",
    width = 1500,
    height = 700,
    onTileTap = function() end,
}
expect(bv.layout_id == "tictactoe", "board widget stores layout_id = 'tictactoe'")
expect(bv.grid == Logic.gridBounds("tictactoe"),
    "board grid bounds match the Tic-Tac-Toe layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("tictactoe") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Tic-Tac-Toe tiles (got " .. drawn .. ")")
expect(all_inside, "all Tic-Tac-Toe tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L4 column cap and a base frame corner returns them.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(9, 2, 4)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 9 and hit.y == 2 and hit.layer == 4,
    "hit-test finds the L4 column cap (9, 2, L4)")
local px0, py0 = bv:tilePos(12, 6, 0)
local hit0 = bv:hitTest(px0 + 1, py0 + 1)
expect(hit0 ~= nil and hit0.x == 12 and hit0.y == 6 and hit0.layer == 0,
    "hit-test finds the base frame corner (12, 6, L0)")

-- ---- Picker lists Tic-Tac-Toe ------------------------------------------------

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
if picker._page_right and picker._page_right.enabled ~= false then picker._page_right.callback() end
picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "first launch shows the layout picker")
    expect(#picker._card_rects == #Logic.layoutIds() - 12,
    "picker lists one card per registered layout (got " .. #picker._card_rects .. " cards, "
    .. #Logic.layoutIds() .. " ids)")

local has_tt_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "tictactoe" then has_tt_card = true end
end
expect(has_tt_card, "picker has a Tic-Tac-Toe card")

-- Thumbnail renders for Tic-Tac-Toe.
local thumb = LayoutSelect.layoutThumbnail("tictactoe", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Tic-Tac-Toe thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Tic-Tac-Toe thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Tic-Tac-Toe -> deals a 144-tile board on the tictactoe layout.
local tt_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "tictactoe" then tt_card = c break end
end
picker:onTapSelect(nil, { pos = { x = tt_card.x + tt_card.w / 2,
                                   y = tt_card.y + tt_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Tic-Tac-Toe deals a 144-tile board")
expect(mj.layout == "tictactoe", "the chosen layout is tracked as 'tictactoe'")
expect(store.layout == "tictactoe", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "tictactoe",
    "the dealt game is saved with layout='tictactoe'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Tic-Tac-Toe shows the Mahjong widget")

-- ---- Gameplay end-to-end on Tic-Tac-Toe --------------------------------------

local tt_pair = Logic.matchingFreePair(mj.board, "tictactoe")
mj:handleTileTap(tt_pair.a.x, tt_pair.a.y, tt_pair.a.layer)
mj:handleTileTap(tt_pair.b.x, tt_pair.b.y, tt_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Tic-Tac-Toe removes both tiles")
expect(mj.score == 10, "first Tic-Tac-Toe match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Tic-Tac-Toe move")
expect(store.game.layout == "tictactoe", "saved Tic-Tac-Toe game keeps its layout id")

-- ---- Restore a saved Tic-Tac-Toe game (mid-game, 142 tiles) ------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Tic-Tac-Toe game restores directly (no picker)")
expect(mj2.layout == "tictactoe", "restored game keeps layout='tictactoe'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Tic-Tac-Toe")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-24 TIC-TAC-TOE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
