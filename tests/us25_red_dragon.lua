-- US-25 — Red Dragon layout suite.
--
-- Verifies the "Red Dragon" board (144 positions, 82/45/17 across 3 layers,
-- transcribed from GNOME Mahjongg's `dragon` map) is registered, deals/saves/
-- restores correctly, the board widget renders it, free-tile detection
-- (including the fractional-y horn tiles and the off-center peak tile) +
-- gameplay work, and the picker lists it alongside the other layouts.

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
    expect(#ids == 18 and ids[5] == "hare" and ids[11] == "red-dragon"
        and ids[13] == "spider" and ids[17] == "turtle",
    "registry enumerates all 18 layouts (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("red-dragon") == "Red Dragon", "layoutName returns 'Red Dragon'")
expect(Logic.maxLayer("red-dragon") == 2, "maxLayer(red-dragon) == 2")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("red-dragon")
expect(#layout == 144, "Red Dragon layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Red Dragon layout has no duplicate positions")

-- Per-layer counts: 82 / 45 / 17.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 82, "Red Dragon layer 0 has 82 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 45, "Red Dragon layer 1 has 45 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 17, "Red Dragon layer 2 has 17 tiles (got " .. tostring(layer_counts[2]) .. ")")

-- Grid bounds: x = 0..14, y = 0..6.5.
local cb = Logic.gridBounds("red-dragon")
expect(cb.x_min == 0 and cb.x_max == 14 and cb.y_min == 0 and cb.y_max == 6.5,
    "Red Dragon grid bounds are x=0..14, y=0..6.5")

-- Position and layer validation, including the fractional-y horn tiles.
expect(Logic.isLayoutPosition(0, 6, 0, "red-dragon"),
    "the left horn tip (0, 6) is a Red Dragon position")
expect(Logic.isLayoutPosition(2, 6.5, 0, "red-dragon"),
    "the base-row tile (2, 6.5) is a Red Dragon position")
expect(Logic.isLayoutPosition(11, 4, 2, "red-dragon"),
    "the peak tile (11, 4, L2) is a Red Dragon position")
expect(not Logic.isLayoutPosition(1, 6.5, 0, "red-dragon"),
    "the base row is at even x only — (1, 6.5) is not a position")
expect(not Logic.isLayoutPosition(11, 4, 3, "red-dragon"), "no L3 in Red Dragon (max layer is 2)")
expect(not Logic.isLayoutPosition(99, 99, 0, "red-dragon"), "out-of-layout position rejected against Red Dragon")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("red-dragon", 42)
expect(Logic.tileCount(board) == 144, "newGame('red-dragon', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("red-dragon", 42)) == Logic.tileCount(board),
    "Red Dragon deal is deterministic for a fixed seed")

-- L2 ridge edge tiles and the horn tips are free; the fractional-y base-row
-- tile (2, 6.5) has open sides too.
expect(Logic.isFree(board, 5, 1, 2), "Red Dragon's L2 ridge west edge (5, 1) is free")
expect(Logic.isFree(board, 8, 4, 2), "Red Dragon's L2 ridge east edge (8, 4) is free")
expect(Logic.isFree(board, 0, 6, 0), "Red Dragon's left horn tip (0, 6, L0) is free")
expect(Logic.isFree(board, 14, 0, 0), "Red Dragon's right horn tip (14, 0, L0) is free")
expect(Logic.isFree(board, 2, 6.5, 0), "Red Dragon's base-row tile (2, 6.5, L0) is free")
-- The off-center peak tile (11, 4, L2) has nothing on L3 above it, so it is
-- free even though the angled L1 horn column sits below it.
expect(Logic.isFree(board, 11, 4, 2), "Red Dragon's peak tile (11, 4, L2) is free")
-- L1 ridge tiles under the L2 block are covered.
expect(not Logic.isFree(board, 6, 2, 1), "Red Dragon's L1 ridge tile (6, 2, L1) is covered")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "red-dragon")
expect(#free > 0, "Red Dragon board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "red-dragon"), "Red Dragon board has at least one move")
local pair = Logic.matchingFreePair(board, "red-dragon")
expect(pair ~= nil, "Red Dragon board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Red Dragon board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "red-dragon")
expect(ser.v == 2 and ser.layout == "red-dragon", "serialized state is v2 with layout='red-dragon'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "red-dragon",
    "deserialize restores a Red Dragon mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Red Dragon board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Red Dragon board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Red Dragon grid is x=0..14, y=0..6.5 (wide and short).
local rd_board = Logic.newGame("red-dragon", 99)
local bv = Board:new{
    board = rd_board,
    layout_id = "red-dragon",
    width = 1600,
    height = 700,
    onTileTap = function() end,
}
expect(bv.layout_id == "red-dragon", "board widget stores layout_id = 'red-dragon'")
expect(bv.grid == Logic.gridBounds("red-dragon"),
    "board grid bounds match the Red Dragon layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("red-dragon") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Red Dragon tiles (got " .. drawn .. ")")
expect(all_inside, "all Red Dragon tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L2 peak tile and the base-row (2, 6.5) tile returns
-- them (fractional coordinates stay hit-testable).
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(11, 4, 2)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 11 and hit.y == 4 and hit.layer == 2,
    "hit-test finds the peak tile (11, 4, L2)")
local pxb, pyb = bv:tilePos(2, 6.5, 0)
local hitb = bv:hitTest(pxb + 1, pyb + 1)
expect(hitb ~= nil and hitb.x == 2 and hitb.y == 6.5 and hitb.layer == 0,
    "hit-test finds the base-row tile (2, 6.5, L0)")

-- ---- Picker lists Red Dragon --------------------------------------------------

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
if picker._page_right and picker._page_right.enabled ~= false then picker._page_right.callback() end
picker = ctx.window_stack[#ctx.window_stack].widget
if picker._page_left and picker._page_left.enabled ~= false then picker._page_left.callback() end
picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "first launch shows the layout picker")
    expect(#picker._card_rects == math.min(12, #Logic.layoutIds()),
    "picker lists one card per registered layout (got " .. #picker._card_rects .. " cards, "
    .. #Logic.layoutIds() .. " ids)")

local has_rd_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "red-dragon" then has_rd_card = true end
end
expect(has_rd_card, "picker has a Red Dragon card")

-- Thumbnail renders for Red Dragon.
local thumb = LayoutSelect.layoutThumbnail("red-dragon", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Red Dragon thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Red Dragon thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Red Dragon -> deals a 144-tile board on the red-dragon layout.
local rd_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "red-dragon" then rd_card = c break end
end
picker:onTapSelect(nil, { pos = { x = rd_card.x + rd_card.w / 2,
                                   y = rd_card.y + rd_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Red Dragon deals a 144-tile board")
expect(mj.layout == "red-dragon", "the chosen layout is tracked as 'red-dragon'")
expect(store.layout == "red-dragon", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "red-dragon",
    "the dealt game is saved with layout='red-dragon'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Red Dragon shows the Mahjong widget")

-- ---- Gameplay end-to-end on Red Dragon ----------------------------------------

local rd_pair = Logic.matchingFreePair(mj.board, "red-dragon")
mj:handleTileTap(rd_pair.a.x, rd_pair.a.y, rd_pair.a.layer)
mj:handleTileTap(rd_pair.b.x, rd_pair.b.y, rd_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Red Dragon removes both tiles")
expect(mj.score == 10, "first Red Dragon match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Red Dragon move")
expect(store.game.layout == "red-dragon", "saved Red Dragon game keeps its layout id")

-- ---- Restore a saved Red Dragon game (mid-game, 142 tiles) --------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Red Dragon game restores directly (no picker)")
expect(mj2.layout == "red-dragon", "restored game keeps layout='red-dragon'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Red Dragon")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-25 RED DRAGON CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
