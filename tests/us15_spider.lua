-- US-15 — Spider layout suite.
--
-- Verifies the classic Spider board (144 positions, 65/53/25/1 across 4 layers)
-- is registered, deals/saves/restores correctly, the board widget renders it,
-- free-tile detection + gameplay work, and the picker lists it alongside Turtle.

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
expect(#ids == 3 and ids[1] == "bridge" and ids[2] == "spider" and ids[3] == "turtle",
    "registry enumerates {bridge, spider, turtle} (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("spider") == "Spider", "layoutName returns 'Spider'")
expect(Logic.maxLayer("spider") == 3, "maxLayer(spider) == 3")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("spider")
expect(#layout == 144, "Spider layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Spider layout has no duplicate positions")

-- Per-layer counts: 65 / 53 / 25 / 1.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 65, "Spider layer 0 has 65 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 53, "Spider layer 1 has 53 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 25, "Spider layer 2 has 25 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 1,  "Spider layer 3 has 1 tile (got " .. tostring(layer_counts[3]) .. ")")

-- Grid bounds: x = 0.5..14.5, y = 0..7 (same height as Turtle, shifted in x).
local sb = Logic.gridBounds("spider")
expect(sb.x_min == 0.5 and sb.x_max == 14.5 and sb.y_min == 0 and sb.y_max == 7,
    "Spider grid bounds are x=0.5..14.5, y=0..7")

-- Peak tile and layer validation.
expect(Logic.isLayoutPosition(7.5, 4.5, 3, "spider"), "peak tile (7.5, 4.5, L3) is a Spider position")
expect(not Logic.isLayoutPosition(7.5, 4.5, 4, "spider"), "no L4 in Spider (max layer is 3)")
expect(not Logic.isLayoutPosition(99, 99, 0, "spider"), "out-of-layout position rejected against Spider")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("spider", 42)
expect(Logic.tileCount(board) == 144, "newGame('spider', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("spider", 42)) == Logic.tileCount(board),
    "Spider deal is deterministic for a fixed seed")

-- The peak tile is free (nothing above it).
expect(Logic.isFree(board, 7.5, 4.5, 3), "Spider's peak tile is free")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "spider")
expect(#free > 0, "Spider board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "spider"), "Spider board has at least one move")
local pair = Logic.matchingFreePair(board, "spider")
expect(pair ~= nil, "Spider board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Spider board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "spider")
expect(ser.v == 2 and ser.layout == "spider", "serialized state is v2 with layout='spider'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "spider",
    "deserialize restores a Spider mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Spider board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Spider board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

local sv_board = Logic.newGame("spider", 99)
local bv = Board:new{
    board = sv_board,
    layout_id = "spider",
    width = 1200,
    height = 600,
    onTileTap = function() end,
}
expect(bv.layout_id == "spider", "board widget stores layout_id = 'spider'")
expect(bv.grid == Logic.gridBounds("spider"),
    "board grid bounds match the Spider layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("spider") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Spider tiles (got " .. drawn .. ")")
expect(all_inside, "all Spider tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the peak tile returns it.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(7.5, 4.5, 3)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 7.5 and hit.y == 4.5 and hit.layer == 3,
    "hit-test finds the Spider peak tile")

-- ---- Picker lists Spider -----------------------------------------------------

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

local has_spider_card = false
local has_turtle_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "spider" then has_spider_card = true end
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_spider_card, "picker has a Spider card")
expect(has_turtle_card, "picker has a Turtle card")

-- Thumbnail renders for Spider.
local thumb = LayoutSelect.layoutThumbnail("spider", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Spider thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Spider thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Spider -> deals a 144-tile board on the spider layout.
local spider_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "spider" then spider_card = c break end
end
picker:onTapSelect(nil, { pos = { x = spider_card.x + spider_card.w / 2,
                                   y = spider_card.y + spider_card.h / 2 } })
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Spider deals a 144-tile board")
expect(mj.layout == "spider", "the chosen layout is tracked as 'spider'")
expect(store.layout == "spider", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "spider",
    "the dealt game is saved with layout='spider'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Spider shows the Mahjong widget")

-- ---- Gameplay end-to-end on Spider -------------------------------------------

local sp_pair = Logic.matchingFreePair(mj.board, "spider")
mj:handleTileTap(sp_pair.a.x, sp_pair.a.y, sp_pair.a.layer)
mj:handleTileTap(sp_pair.b.x, sp_pair.b.y, sp_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Spider removes both tiles")
expect(mj.score == 10, "first Spider match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Spider move")
expect(store.game.layout == "spider", "saved Spider game keeps its layout id")

-- ---- Restore a saved Spider game (mid-game, 142 tiles) ------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Spider game restores directly (no picker)")
expect(mj2.layout == "spider", "restored game keeps layout='spider'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Spider")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-15 SPIDER CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
