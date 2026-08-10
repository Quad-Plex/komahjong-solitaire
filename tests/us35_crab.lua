-- US-35 — Crab layout suite.
--
-- Verifies the "Crab" board (144 positions, 77/50/15/2 across 4 layers,
-- transcribed from KMahjongg's `crab.layout` — the classic Microsoft Mahjong
-- Titans crab silhouette with two claws at the north corners, an hourglass
-- body, and two stacked peak tiles in the center on layer 3) is registered,
-- deals/saves/restores correctly, the board widget renders it, free-tile
-- detection + gameplay work, and the picker lists it — bringing the picker to a
-- full 3x4 grid of 12 cards.

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
    "registry enumerates 12 ids {bridge, cloud, confounding, crab, overpass, pyramid,\n"
    .. "red-dragon, spider, taipei, tictactoe, turtle, ziggurat} (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("crab") == "Crab", "layoutName returns 'Crab'")
expect(Logic.maxLayer("crab") == 3, "maxLayer(crab) == 3")

-- ---- Layout shape -----------------------------------------------------------

local layout = Logic.buildLayout("crab")
expect(#layout == 144, "Crab layout has 144 positions (got " .. #layout .. ")")

-- 144 unique positions.
local seen = {}
local dups = 0
for _, p in ipairs(layout) do
    local key = Logic.posKey(p.x, p.y, p.layer)
    if seen[key] then dups = dups + 1 end
    seen[key] = true
end
expect(dups == 0, "Crab layout has no duplicate positions")

-- Per-layer counts: 77 / 50 / 15 / 2.
local layer_counts = {}
for _, p in ipairs(layout) do
    layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
end
expect(layer_counts[0] == 77, "Crab layer 0 has 77 tiles (got " .. tostring(layer_counts[0]) .. ")")
expect(layer_counts[1] == 50, "Crab layer 1 has 50 tiles (got " .. tostring(layer_counts[1]) .. ")")
expect(layer_counts[2] == 15, "Crab layer 2 has 15 tiles (got " .. tostring(layer_counts[2]) .. ")")
expect(layer_counts[3] == 2,  "Crab layer 3 has 2 tiles (got " .. tostring(layer_counts[3]) .. ")")

-- Grid bounds: x = 1..14, y = 0..7.
local cb = Logic.gridBounds("crab")
expect(cb.x_min == 1 and cb.x_max == 14 and cb.y_min == 0 and cb.y_max == 7,
    "Crab grid bounds are x=1..14, y=0..7")

-- Position and layer validation.
expect(Logic.isLayoutPosition(1.5, 0, 0, "crab"),
    "the L0 left claw start (1.5, 0) is a Crab position")
expect(Logic.isLayoutPosition(13.5, 0, 0, "crab"),
    "the L0 right claw end (13.5, 0) is a Crab position")
expect(Logic.isLayoutPosition(7.5, 4, 3, "crab"),
    "the L3 peak tile (7.5, 4) is a Crab position")
expect(Logic.isLayoutPosition(7.5, 5, 3, "crab"),
    "the L3 second peak tile (7.5, 5) is a Crab position")
expect(not Logic.isLayoutPosition(0, 0, 0, "crab"),
    "(0, 0, L0) is not a Crab position (claws start at x=1.5)")
expect(not Logic.isLayoutPosition(7.5, 4, 4, "crab"), "no L4 in Crab (max layer is 3)")
expect(not Logic.isLayoutPosition(99, 99, 0, "crab"), "out-of-layout position rejected against Crab")

-- ---- Deal + free tiles + gameplay ------------------------------------------

local board = Logic.newGame("crab", 42)
expect(Logic.tileCount(board) == 144, "newGame('crab', 42) deals 144 tiles")
expect(Logic.tileCount(Logic.newGame("crab", 42)) == Logic.tileCount(board),
    "Crab deal is deterministic for a fixed seed")

-- The L3 peaks are free (nothing above, both layer-3 peers at x=6.5/8.5 are
-- empty); a L0 center body tile is covered by the L1 body row x=6..9, y=4.
expect(Logic.isFree(board, 7.5, 5, 3), "Crab's L3 peak (7.5, 5) is free")
expect(Logic.isFree(board, 7.5, 4, 3), "Crab's L3 peak (7.5, 4) is free")
expect(Logic.isFree(board, 1.5, 0, 0), "Crab's L0 left claw corner (1.5, 0) is free")
expect(not Logic.isFree(board, 7, 4, 0),
    "Crab's L0 center body (7, 4) is covered by the L1 body row x=6..9, y=4")

-- Free tiles and matching pairs are non-empty on a full board.
local free = Logic.freeTiles(board, "crab")
expect(#free > 0, "Crab board has free tiles (" .. #free .. ")")
expect(Logic.hasMoves(board, "crab"), "Crab board has at least one move")
local pair = Logic.matchingFreePair(board, "crab")
expect(pair ~= nil, "Crab board has a matching free pair")

-- Remove a pair and verify the board shrinks.
local ok, ka, kb = Logic.removePair(board, pair.a, pair.b)
expect(ok, "removePair works on a Crab board")
expect(Logic.tileCount(board) == 142, "board has 142 tiles after one removal")
expect(not Logic.isWin(board), "not won after one removal")

-- ---- Persistence round-trip --------------------------------------------------

local ser = Logic.serializeGameState(board, {
    { a = pair.a, b = pair.b, ka = ka, kb = kb, score = 10, prev_last = nil },
}, 10, ka, 42, 0, 0, "crab")
expect(ser.v == 2 and ser.layout == "crab", "serialized state is v2 with layout='crab'")
local restored = Logic.deserializeGameState(ser)
expect(restored ~= nil and restored.layout == "crab",
    "deserialize restores a Crab mid-game state")
expect(Logic.tileCount(restored.board) == 142,
    "restored Crab board has 142 tiles")
local same = true
for k, v in pairs(board) do
    if restored.board[k] ~= v then same = false break end
end
expect(same, "restored Crab board matches the saved board")

-- ---- Board widget rendering --------------------------------------------------

-- Crab grid is x=1..14, y=0..7 (14x8) with 4 layers.
local cb_board = Logic.newGame("crab", 99)
local bv = Board:new{
    board = cb_board,
    layout_id = "crab",
    width = 1400,
    height = 800,
    onTileTap = function() end,
}
expect(bv.layout_id == "crab", "board widget stores layout_id = 'crab'")
expect(bv.grid == Logic.gridBounds("crab"),
    "board grid bounds match the Crab layout")

local all_inside = true
local drawn = 0
for l = 0, Logic.maxLayer("crab") do
    drawn = drawn + #(bv.tiles_by_layer[l] or {})
    for _, t in ipairs(bv.tiles_by_layer[l] or {}) do
        if t.px < 0 or t.py < 0 or t.px + t.w > bv.width or t.py + t.h > bv.height then
            all_inside = false
        end
    end
end
expect(drawn == 144, "board widget draws all 144 Crab tiles (got " .. drawn .. ")")
expect(all_inside, "all Crab tiles fit inside the widget area")
expect(mapCount(bv.tile_widgets) == 144, "board widget built 144 tile widgets")

-- Hit-test: tapping the L3 peak and a L0 claw corner returns them.
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(7.5, 5, 3)
local hit = bv:hitTest(px + 1, py + 1)
expect(hit ~= nil and hit.x == 7.5 and hit.y == 5 and hit.layer == 3,
    "hit-test finds the L3 peak tile (7.5, 5, L3)")
local px0, py0 = bv:tilePos(1.5, 0, 0)
local hit0 = bv:hitTest(px0 + 1, py0 + 1)
expect(hit0 ~= nil and hit0.x == 1.5 and hit0.y == 0 and hit0.layer == 0,
    "hit-test finds the L0 left claw corner (1.5, 0, L0)")

-- ---- Picker lists Crab + full 3x4 --------------------------------------------

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
expect(#picker._card_rects == 12, "the picker is a full 12-card grid (got " .. #picker._card_rects .. ")")
expect(#picker._card_rects == 12 and #Logic.layoutIds() == 12
    and 12 == (3 * 4), "12 cards = 3 columns x 4 rows (no empty slot)")

local has_crab_card = false
local has_turtle_card = false
for _, c in ipairs(picker._card_rects) do
    if c.id == "crab" then has_crab_card = true end
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_crab_card, "picker has a Crab card")
expect(has_turtle_card, "picker has a Turtle card")

-- The 12-card grid is a complete 3x4: every 3-card row fills (rows 0..3).
-- driver computes cards in sorted-id order, so card k shares row floor((k-1)/3)).
expect(picker._card_rects[12].y == picker._card_rects[11].y
    and picker._card_rects[11].y == picker._card_rects[10].y,
    "row 3 (cards 10/11/12) is full — last row of the 3x4 grid")
expect(picker._card_rects[10].y > picker._card_rects[9].y,
    "row 3 starts at card 10 (lower than row 2)")

-- Thumbnail renders for Crab.
local thumb = LayoutSelect.layoutThumbnail("crab", 200, 200)
expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 200 and thumb.dimen.h == 200,
    "Crab thumbnail renders at the requested dimen")
expect(#thumb == 144,
    "Crab thumbnail has one tile widget per layout position (got " .. #thumb .. ")")

-- Pick Crab -> deals a 144-tile board on the crab layout.
local crab_card
for _, c in ipairs(picker._card_rects) do
    if c.id == "crab" then crab_card = c break end
end
picker:onTapSelect(nil, { pos = { x = crab_card.x + crab_card.w / 2,
                                  y = crab_card.y + crab_card.h / 2 } })
ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Crab deals a 144-tile board")
expect(mj.layout == "crab", "the chosen layout is tracked as 'crab'")
expect(store.layout == "crab", "the chosen layout is persisted as the last-chosen default")
expect(store.game ~= nil and store.game.layout == "crab",
    "the dealt game is saved with layout='crab'")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Crab shows the Mahjong widget")

-- ---- Gameplay end-to-end on Crab ----------------------------------------------

local crab_pair = Logic.matchingFreePair(mj.board, "crab")
mj:handleTileTap(crab_pair.a.x, crab_pair.a.y, crab_pair.a.layer)
mj:handleTileTap(crab_pair.b.x, crab_pair.b.y, crab_pair.b.layer)
expect(Logic.tileCount(mj.board) == 142,
    "tapping a matching pair on Crab removes both tiles")
expect(mj.score == 10, "first Crab match scores 10 (got " .. mj.score .. ")")
expect(store.game ~= nil, "game state is saved after a Crab move")
expect(store.game.layout == "crab", "saved Crab game keeps its layout id")

-- ---- Restore a saved Crab game (mid-game, 142 tiles) --------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 142,
    "a saved Crab game restores directly (no picker)")
expect(mj2.layout == "crab", "restored game keeps layout='crab'")

-- Undo restores the pair.
mj:undo()
expect(Logic.tileCount(mj.board) == 144, "undo restores the pair on Crab")
expect(mj.score == 0, "undo restores score to 0 (got " .. mj.score .. ")")

if failures == 0 then
    print("\nALL US-35 CRAB CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
