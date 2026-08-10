-- US-16 — Bridge layout suite.
--
-- Verifies the classic "Four Bridges" board (144 positions, 88/36/16/4 across
-- 4 layers, transcribed from GNOME Mahjongg's `bridges` map) is registered,
-- deals/saves/restores correctly, the board widget renders it, free-tile
-- detection + gameplay work, and the picker lists it alongside Spider and
-- Turtle.

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

-- US-16 picker driver: tap the Bridge card center to deal a Bridge game.
local function pickBridge()
    local picker = ctx.window_stack[#ctx.window_stack].widget
    if not picker or picker.name ~= "mahjonglayoutselect" then return end
    local r
    for _, c in ipairs(picker._card_rects) do
        if c.id == "bridge" then r = c break end
    end
    picker:onTapSelect(nil, { pos = { x = r.x + r.w / 2,
                                       y = r.y + r.h / 2 } })
    ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
end

-- ---- Registry ---------------------------------------------------------------

local ids = Logic.layoutIds()
expect(#ids == 24 and ids[1] == "boar" and ids[5] == "crab"
        and ids[18] == "spider" and ids[22] == "turtle",
    "registry enumerates all 24 layouts (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("bridge") == "Bridge", "layoutName returns 'Bridge'")
expect(Logic.maxLayer("bridge") == 3, "maxLayer(bridge) == 3")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("bridge")
expect(#layout == 144, "Bridge layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Bridge layout has no duplicate positions")

-- Per-layer counts: 88 / 36 / 16 / 4.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 88, "Bridge layer 0 has 88 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 36, "Bridge layer 1 has 36 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 16, "Bridge layer 2 has 16 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 4,  "Bridge layer 3 has 4 tiles (got " .. tostring(layer_counts[3]) .. ")")

-- Grid bounds: x = 0..12, y = 0..8.
local bb = Logic.gridBounds("bridge")
expect(bb.x_min == 0 and bb.x_max == 12 and bb.y_min == 0 and bb.y_max == 8,
    "Bridge grid bounds are x=0..12, y=0..8")

-- Peak tiles and layer validation.
expect(Logic.isLayoutPosition(3.5, 1.5, 3, "bridge"), "peak tile (3.5, 1.5, L3) is a Bridge position")
expect(Logic.isLayoutPosition(8.5, 6.5, 3, "bridge"), "peak tile (8.5, 6.5, L3) is a Bridge position")
expect(not Logic.isLayoutPosition(3.5, 1.5, 4, "bridge"), "no L4 in Bridge (max layer is 3)")
expect(not Logic.isLayoutPosition(99, 99, 0, "bridge"), "out-of-layout position rejected against Bridge")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("bridge", 42)
expect(Logic.tileCount(board) == 144, "newGame('bridge', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("bridge", 42)) == Logic.tileCount(board),
    "Bridge deal is deterministic for a fixed seed")

-- The peak tiles are free (nothing above them).
expect(Logic.isFree(board, 3.5, 1.5, 3), "Bridge peak tile (3.5, 1.5, L3) is free")
expect(Logic.isFree(board, 8.5, 1.5, 3), "Bridge peak tile (8.5, 1.5, L3) is free")
expect(Logic.isFree(board, 3.5, 6.5, 3), "Bridge peak tile (3.5, 6.5, L3) is free")
expect(Logic.isFree(board, 8.5, 6.5, 3), "Bridge peak tile (8.5, 6.5, L3) is free")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "bridge")
expect(#free > 0, "Bridge board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "bridge"), "Bridge board has at least one move")
local pair = Logic.matchingFreePair(board, "bridge")
expect(pair ~= nil, "Bridge board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Bridge board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "bridge")
expect(ser.v == 2 and ser.layout == "bridge", "serialized state is v2 with layout='bridge'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "bridge",
    "deserialize restores a Bridge mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Bridge board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Bridge board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Bridge grid is x=0..12, y=0..8 (9 units tall); give the widget room.
local sv_board = Logic.newGame("bridge", 99)
local bv = Board:new{
    board = sv_board,
    layout_id = "bridge",
    width = 800,
    height = 1000,
    onTileTap = function() end,
}
expect(bv.layout_id == "bridge", "board widget stores layout_id = 'bridge'")
expect(bv.grid == Logic.gridBounds("bridge"),
    "board grid bounds match the Bridge layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("bridge") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Bridge tiles (got " .. drawn .. ")")
expect(all_inside, "all Bridge tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping a peak tile returns it.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(3.5, 1.5, 3)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 3.5 and hit.y == 1.5 and hit.layer == 3,
    "hit-test finds the Bridge peak tile (3.5, 1.5, L3)")

-- ---- Picker lists Bridge -----------------------------------------------------

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "first launch shows the layout picker")
expect(#picker._card_rects == math.min(12, #Logic.layoutIds()),
    "picker lists one card per registered layout (got " .. #picker._card_rects .. " cards, "
    .. #Logic.layoutIds() .. " ids)")

local has_bridge_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "bridge" then has_bridge_card = true end
end
expect(has_bridge_card, "picker has a Bridge card")
local has_spider_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "spider" then has_spider_card = true end
end
expect(has_spider_card, "picker has a Spider card")

-- Thumbnail renders for Bridge.
local thumb = LayoutSelect.layoutThumbnail("bridge", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Bridge thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Bridge thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Bridge -> deals a 144-tile board on the bridge layout.
pickBridge()
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Bridge deals a 144-tile board")
expect(mj.layout == "bridge", "the chosen layout is tracked as 'bridge'")
expect(store.layout == "bridge", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "bridge",
    "the dealt game is saved with layout='bridge'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Bridge shows the Mahjong widget")

-- ---- Gameplay end-to-end on Bridge -------------------------------------------

local bp_pair = Logic.matchingFreePair(mj.board, "bridge")
mj:handleTileTap(bp_pair.a.x, bp_pair.a.y, bp_pair.a.layer)
mj:handleTileTap(bp_pair.b.x, bp_pair.b.y, bp_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Bridge removes both tiles")
expect(mj.score == 10, "first Bridge match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Bridge move")
expect(store.game.layout == "bridge", "saved Bridge game keeps its layout id")

-- ---- Restore a saved Bridge game (mid-game, 142 tiles) ------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Bridge game restores directly (no picker)")
expect(mj2.layout == "bridge", "restored game keeps layout='bridge'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Bridge")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-16 BRIDGE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
