-- US-23 — Cloud layout suite.
--
-- Verifies the "Cloud" board (144 positions, 79/36/29 across 3 layers,
-- transcribed from GNOME Mahjongg's `cloud` map) is registered, deals/saves/
-- restores correctly, the board widget renders it, free-tile detection
-- (including the fractional y=5.5 spine tile) + gameplay work, and the picker
-- lists it alongside the other layouts.

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
expect(#ids == 8 and ids[1] == "bridge" and ids[2] == "cloud" and ids[3] == "overpass"
        and ids[4] == "red-dragon" and ids[5] == "spider" and ids[6] == "tictactoe"
        and ids[7] == "turtle" and ids[8] == "ziggurat",
    "registry enumerates {bridge, cloud, overpass, red-dragon, spider, tictactoe, turtle, ziggurat} (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("cloud") == "Cloud", "layoutName returns 'Cloud'")
expect(Logic.maxLayer("cloud") == 2, "maxLayer(cloud) == 2")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("cloud")
expect(#layout == 144, "Cloud layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Cloud layout has no duplicate positions")

-- Per-layer counts: 79 / 36 / 29.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 79, "Cloud layer 0 has 79 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 36, "Cloud layer 1 has 36 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 29, "Cloud layer 2 has 29 tiles (got " .. tostring(layer_counts[2]) .. ")")

-- Grid bounds: x = 0..13, y = 0..5.5.
local cb = Logic.gridBounds("cloud")
expect(cb.x_min == 0 and cb.x_max == 13 and cb.y_min == 0 and cb.y_max == 5.5,
    "Cloud grid bounds are x=0..13, y=0..5.5")

-- Spine tile and layer validation.
expect(Logic.isLayoutPosition(6, 5.5, 2, "cloud"),
    "the L2 spine tile (6, 5.5) is a Cloud position")
expect(Logic.isLayoutPosition(13, 0, 0, "cloud"),
    "body corner (13, 0, L0) is a Cloud position")
expect(not Logic.isLayoutPosition(6, 5.5, 3, "cloud"), "no L3 in Cloud (max layer is 2)")
expect(not Logic.isLayoutPosition(1, 5.5, 2, "cloud"),
    "the L2 row only holds the (6, 5.5) spine tile")
expect(not Logic.isLayoutPosition(99, 99, 0, "cloud"), "out-of-layout position rejected against Cloud")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("cloud", 42)
expect(Logic.tileCount(board) == 144, "newGame('cloud', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("cloud", 42)) == Logic.tileCount(board),
    "Cloud deal is deterministic for a fixed seed")

-- The L2 spine tile is free (nothing above it); the L1 tile directly beneath
-- it is covered (the spine overlaps it from above) — the fractional-y overlap.
expect(Logic.isFree(board, 6, 5.5, 2), "Cloud's L2 spine tile (6, 5.5) is free")
expect(not Logic.isFree(board, 6, 5.5, 1), "the L1 tile under the spine is covered and not free")
expect(Logic.isFree(board, 3, 5.5, 1), "the west end of the L1 spine row is free")

-- Body edge tiles are free; an interior body tile is not.
expect(Logic.isFree(board, 13, 0, 0), "Cloud's east body edge (13, 0, L0) is free")
expect(Logic.isFree(board, 0, 4, 0), "Cloud's body corner (0, 4, L0) is free")
expect(not Logic.isFree(board, 1, 0, 0),
    "an interior body edge tile (1, 0, L0) is blocked on both sides")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "cloud")
expect(#free > 0, "Cloud board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "cloud"), "Cloud board has at least one move")
local pair = Logic.matchingFreePair(board, "cloud")
expect(pair ~= nil, "Cloud board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Cloud board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "cloud")
expect(ser.v == 2 and ser.layout == "cloud", "serialized state is v2 with layout='cloud'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "cloud",
    "deserialize restores a Cloud mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Cloud board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Cloud board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Cloud grid is x=0..13, y=0..5.5 (wide and short); give the widget room.
local cv_board = Logic.newGame("cloud", 99)
local bv = Board:new{
    board = cv_board,
    layout_id = "cloud",
    width = 1400,
    height = 650,
    onTileTap = function() end,
}
expect(bv.layout_id == "cloud", "board widget stores layout_id = 'cloud'")
expect(bv.grid == Logic.gridBounds("cloud"),
    "board grid bounds match the Cloud layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("cloud") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Cloud tiles (got " .. drawn .. ")")
expect(all_inside, "all Cloud tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L2 spine tile returns it.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(6, 5.5, 2)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 6 and hit.y == 5.5 and hit.layer == 2,
    "hit-test finds the Cloud spine tile (6, 5.5, L2)")

-- ---- Picker lists Cloud -----------------------------------------------------

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

local has_cloud_card = false
local has_turtle_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "cloud" then has_cloud_card = true end
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_cloud_card, "picker has a Cloud card")
expect(has_turtle_card, "picker has a Turtle card")

-- Thumbnail renders for Cloud.
local thumb = LayoutSelect.layoutThumbnail("cloud", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Cloud thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Cloud thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Cloud -> deals a 144-tile board on the cloud layout.
local cloud_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "cloud" then cloud_card = c break end
end
picker:onTapSelect(nil, { pos = { x = cloud_card.x + cloud_card.w / 2,
                                   y = cloud_card.y + cloud_card.h / 2 } })
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Cloud deals a 144-tile board")
expect(mj.layout == "cloud", "the chosen layout is tracked as 'cloud'")
expect(store.layout == "cloud", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "cloud",
    "the dealt game is saved with layout='cloud'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Cloud shows the Mahjong widget")

-- ---- Gameplay end-to-end on Cloud -------------------------------------------

local cl_pair = Logic.matchingFreePair(mj.board, "cloud")
mj:handleTileTap(cl_pair.a.x, cl_pair.a.y, cl_pair.a.layer)
mj:handleTileTap(cl_pair.b.x, cl_pair.b.y, cl_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Cloud removes both tiles")
expect(mj.score == 10, "first Cloud match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Cloud move")
expect(store.game.layout == "cloud", "saved Cloud game keeps its layout id")

-- ---- Restore a saved Cloud game (mid-game, 142 tiles) ------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Cloud game restores directly (no picker)")
expect(mj2.layout == "cloud", "restored game keeps layout='cloud'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Cloud")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-23 CLOUD CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
