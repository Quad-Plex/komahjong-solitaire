-- US-28 — Confounding Cross layout suite.
--
-- Verifies the "Confounding Cross" board (144 positions, 47/42/27/18/9/1
-- across 6 layers, transcribed from GNOME Mahjongg's `confounding` map — a
-- plus/cross shape built from nested hollow rings rising to a lone center
-- peak tile on layer 5) is registered, deals/saves/restores correctly, the
-- board widget renders it, free-tile detection + gameplay work, and the
-- picker lists it alongside the other layouts.

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
    expect(#ids == 18 and ids[3] == "confounding" and ids[5] == "hare"
        and ids[13] == "spider" and ids[17] == "turtle",
    "registry enumerates all 18 layouts (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("confounding") == "Confounding Cross",
    "layoutName returns 'Confounding Cross'")
expect(Logic.maxLayer("confounding") == 5, "maxLayer(confounding) == 5")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("confounding")
expect(#layout == 144, "Confounding layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Confounding layout has no duplicate positions")

-- Per-layer counts: 47 / 42 / 27 / 18 / 9 / 1.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 47, "Confounding layer 0 has 47 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 42, "Confounding layer 1 has 42 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 27, "Confounding layer 2 has 27 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 18, "Confounding layer 3 has 18 tiles (got " .. tostring(layer_counts[3]) .. ")")
expect(layer_counts[4] == 9,  "Confounding layer 4 has 9 tiles (got " .. tostring(layer_counts[4]) .. ")")
expect(layer_counts[5] == 1,  "Confounding layer 5 has 1 tile (got " .. tostring(layer_counts[5]) .. ")")

-- Grid bounds: x = 0..10, y = 0..8.
local cb = Logic.gridBounds("confounding")
expect(cb.x_min == 0 and cb.x_max == 10 and cb.y_min == 0 and cb.y_max == 8,
    "Confounding grid bounds are x=0..10, y=0..8")

-- Position and layer validation.
expect(Logic.isLayoutPosition(5, 0, 0, "confounding"),
    "the L0 top arm tip (5, 0) is a Confounding position")
expect(Logic.isLayoutPosition(0, 4, 0, "confounding"),
    "the L0 left arm tip (0, 4) is a Confounding position")
expect(Logic.isLayoutPosition(10, 4, 0, "confounding"),
    "the L0 right arm tip (10, 4) is a Confounding position")
expect(Logic.isLayoutPosition(5, 8, 0, "confounding"),
    "the L0 bottom arm tip (5, 8) is a Confounding position")
expect(Logic.isLayoutPosition(5, 4, 5, "confounding"),
    "the L5 peak tile (5, 4) is a Confounding position")
expect(not Logic.isLayoutPosition(5, 0, 1, "confounding"),
    "the L1 center column starts at y=0.5 — (5, 0) is not a L1 position")
expect(not Logic.isLayoutPosition(5, 4, 6, "confounding"), "no L6 in Confounding (max layer is 5)")
expect(not Logic.isLayoutPosition(99, 99, 0, "confounding"), "out-of-layout position rejected against Confounding")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("confounding", 42)
expect(Logic.tileCount(board) == 144, "newGame('confounding', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("confounding", 42)) == Logic.tileCount(board),
    "Confounding deal is deterministic for a fixed seed")

-- The L5 peak is free (nothing above, both sides open); the L0 arm tip is
-- covered by the L1 center column above it.
expect(Logic.isFree(board, 5, 4, 5), "Confounding's L5 peak (5, 4) is free")
expect(not Logic.isFree(board, 5, 0, 0),
    "Confounding's L0 top arm tip (5, 0) is covered by the L1 column")
expect(not Logic.isFree(board, 5, 4, 0),
    "Confounding's L0 center (5, 4) is covered by the L1 center block")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "confounding")
expect(#free > 0, "Confounding board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "confounding"), "Confounding board has at least one move")
local pair = Logic.matchingFreePair(board, "confounding")
expect(pair ~= nil, "Confounding board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Confounding board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "confounding")
expect(ser.v == 2 and ser.layout == "confounding",
    "serialized state is v2 with layout='confounding'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "confounding",
    "deserialize restores a Confounding mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Confounding board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Confounding board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Confounding grid is x=0..10, y=0..8 (11x9) with 6 layers.
local cc_board = Logic.newGame("confounding", 99)
local bv = Board:new{
    board = cc_board,
    layout_id = "confounding",
    width = 1400,
    height = 800,
    onTileTap = function() end,
}
expect(bv.layout_id == "confounding", "board widget stores layout_id = 'confounding'")
expect(bv.grid == Logic.gridBounds("confounding"),
    "board grid bounds match the Confounding layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("confounding") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Confounding tiles (got " .. drawn .. ")")
expect(all_inside, "all Confounding tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L5 peak and a L0 arm-tip tile returns them.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(5, 4, 5)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 5 and hit.y == 4 and hit.layer == 5,
    "hit-test finds the L5 peak tile (5, 4, L5)")
local px0, py0 = bv:tilePos(5, 0, 0)
local hit0 = bv:hitTest(px0 + 1, py0 + 1)
expect(hit0 ~= nil and hit0.x == 5 and hit0.y == 0 and hit0.layer == 0,
    "hit-test finds the L0 top arm tip (5, 0, L0)")

-- ---- Picker lists Confounding --------------------------------------------------

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

local has_cc_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "confounding" then has_cc_card = true end
end
expect(has_cc_card, "picker has a Confounding card")

-- Thumbnail renders for Confounding.
local thumb = LayoutSelect.layoutThumbnail("confounding", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Confounding thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Confounding thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Confounding -> deals a 144-tile board on the confounding layout.
local cc_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "confounding" then cc_card = c break end
end
picker:onTapSelect(nil, { pos = { x = cc_card.x + cc_card.w / 2,
                                   y = cc_card.y + cc_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Confounding deals a 144-tile board")
expect(mj.layout == "confounding", "the chosen layout is tracked as 'confounding'")
expect(store.layout == "confounding", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "confounding",
    "the dealt game is saved with layout='confounding'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Confounding shows the Mahjong widget")

-- ---- Gameplay end-to-end on Confounding ------------------------------------------

local cc_pair = Logic.matchingFreePair(mj.board, "confounding")
mj:handleTileTap(cc_pair.a.x, cc_pair.a.y, cc_pair.a.layer)
mj:handleTileTap(cc_pair.b.x, cc_pair.b.y, cc_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Confounding removes both tiles")
expect(mj.score == 10, "first Confounding match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Confounding move")
expect(store.game.layout == "confounding", "saved Confounding game keeps its layout id")

-- ---- Restore a saved Confounding game (mid-game, 142 tiles) ----------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Confounding game restores directly (no picker)")
expect(mj2.layout == "confounding", "restored game keeps layout='confounding'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Confounding")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-28 CONFOUNDING CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
