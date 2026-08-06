-- US-14 layout-registry suite: the registry, the per-id-parameterized logic
-- functions, the per-layout board geometry, the v2 persistence layout field,
-- and the layout selection screen.
--
-- Checks (mirroring the story's acceptance):
--   * Self-tests: passing a layout id returns byte-identical Turtle results;
--     the registry enumerates exactly {"turtle"} (covered in the logic
--     self-tests; re-asserted lightly here for the harness context).
--   * registerLayout works end-to-end: deal → free tiles → render via a board
--     built with that layout → serialize/restore round-trip → an unknown
--     saved layout id deals fresh.
--   * The picker appears on first launch / New Game / Play again; choosing
--     Turtle deals a game; the thumbnail renders for every registered layout.

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

local function pk(x, y, l) return Logic.posKey(x, y, l) end
local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- US-14 picker driver: tap the Turtle card center to deal a Turtle game.
local function pickTurtle()
    local picker = ctx.window_stack[#ctx.window_stack].widget
    if not picker or picker.name ~= "mahjonglayoutselect" then return end
    local r
    for _, c in ipairs(picker._card_rects) do
        if c.id == "turtle" then r = c break end
    end
    picker:onTapSelect(nil, { pos = { x = r.x + r.w / 2, y = r.y + r.h / 2 } })
end

-- ---- Registry ---------------------------------------------------------------
--
-- US-14 registered Turtle; US-15 adds Spider; US-16 Bridge; US-22 Ziggurat.
-- The registry now enumerates exactly {"bridge", "spider", "turtle", "ziggurat"}
-- (sorted).
local ids = Logic.layoutIds()
expect(#ids == 4 and ids[1] == "bridge" and ids[2] == "spider" and ids[3] == "turtle"
        and ids[4] == "ziggurat",
    "registry enumerates exactly {bridge, spider, turtle, ziggurat} (got " .. table.concat(ids, ",") .. ")")
expect(Logic.layoutName("turtle") == "Turtle", "layoutName returns the registered Turtle name")
expect(Logic.layoutName("spider") == "Spider", "layoutName returns the registered Spider name")
expect(Logic.layoutName("bridge") == "Bridge", "layoutName returns the registered Bridge name")
expect(Logic.layouts.turtle ~= nil and Logic.layouts.turtle.spec ~= nil,
    "the turtle registry entry exposes its spec")
expect(Logic.layouts.spider ~= nil and Logic.layouts.spider.spec ~= nil,
    "the spider registry entry exposes its spec")

-- Passing "turtle" (or nil) returns byte-identical results: the parameterized
-- paths are the old Turtle paths with the id threaded through.
expect(Logic.buildLayout("turtle") == Logic.buildLayout(),
    "buildLayout('turtle') and buildLayout() share the memoized table")
expect(Logic.gridBounds("turtle") == Logic.gridBounds(),
    "gridBounds('turtle') and gridBounds() share the memoized bounds")
expect(Logic.maxLayer("turtle") == Logic.MAX_LAYER,
    "maxLayer('turtle') matches the legacy MAX_LAYER constant")
expect(Logic.isLayoutPosition(6.5, 3.5, 4, "turtle")
        and Logic.isLayoutPosition(6.5, 3.5, 4),
    "isLayoutPosition matches for explicit-id and default-id forms")

-- newGame with explicit id matches the legacy call shape.
local g1 = Logic.newGame(42)
local g2 = Logic.newGame("turtle", 42)
local same = true
for k, v in pairs(g1) do
    if g2[k] ~= v then same = false break end
end
expect(same, "newGame('turtle', 42) matches newGame(42) byte-for-byte")
expect(Logic.tileCount(g1) == 144, "newGame('turtle', 42) deals 144 tiles")

-- freeTiles / hasMoves / matchingFreePair accept the id and agree with the
-- default-id form on a Turtle board.
expect(#Logic.freeTiles(g1, "turtle") == #Logic.freeTiles(g1),
    "freeTiles with explicit id matches the default-id form")
expect(Logic.hasMoves(g1, "turtle") == Logic.hasMoves(g1),
    "hasMoves with explicit id matches the default-id form")
expect(Logic.countFreePairs(g1, "turtle") == Logic.countFreePairs(g1),
    "countFreePairs with explicit id matches the default-id form")

-- ---- registerLayout end-to-end (a throwaway test-time layout) ----------------

-- A small 4-tile pyramid so the round-trip is cheap. Two layers, 2x2 base +
-- 1 top tile = 5 positions (odd is fine: we only deal a subset for the
-- render check, and the persistence round-trip uses a full Turtle board
-- under layout="toy" only for the unknown-id rejection path — see below).
local toy_spec = {
    { layer = 0, kind = "row", x_min = 0, x_max = 1, y = 0 },
    { layer = 0, kind = "row", x_min = 0, x_max = 1, y = 1 },
    { layer = 1, kind = "tile", x = 0.5, y = 0.5 },
}
Logic.registerLayout{ id = "toy", name = "Toy", spec = toy_spec }
local toy_ids = Logic.layoutIds()
expect(#toy_ids == 5 and toy_ids[1] == "bridge" and toy_ids[2] == "spider"
        and toy_ids[3] == "toy" and toy_ids[4] == "turtle" and toy_ids[5] == "ziggurat",
    "registerLayout adds the id; layoutIds returns them sorted (got " .. table.concat(toy_ids, ",") .. ")")
expect(#Logic.buildLayout("toy") == 5, "the toy layout has 5 positions")
expect(Logic.maxLayer("toy") == 1, "the toy layout's max layer is 1")
expect(Logic.isLayoutPosition(0.5, 0.5, 1, "toy"),
    "isLayoutPosition validates a toy position against the toy layout")
expect(not Logic.isLayoutPosition(2, 0, 0, "toy"),
    "isLayoutPosition rejects a Turtle-only position against the toy layout")

-- Deal on the toy layout: 5 tiles land on the 5 toy positions (the deck is
-- 144-sized, so 5 of them land; the rest are unused — fine for the render
-- check). Deterministic for a fixed seed.
local toy_board = Logic.newGame("toy", 42)
expect(Logic.tileCount(toy_board) == 5, "newGame('toy', 42) deals 5 tiles")
local toy_free = Logic.freeTiles(toy_board, "toy")
expect(#toy_free == 1, "freeTiles on the toy board finds the single top tile")
expect(Logic.isFree(toy_board, 0.5, 0.5, 1), "the toy top tile is free")
expect(not Logic.isFree(toy_board, 0, 0, 0),
    "a toy base tile covered from above is not free")

-- Render the toy board via a Board built with layout_id = "toy": the board
-- widget picks up the toy geometry and tiles_by_layer shape.
local toy_bv = Board:new{
    board = toy_board,
    layout_id = "toy",
    width = 800,
    height = 400,
    onTileTap = function() end,
}
expect(toy_bv.layout_id == "toy", "the board widget stores its layout id")
expect(toy_bv.grid == Logic.gridBounds("toy"),
    "the board's grid bounds match the toy layout")
local toy_layer_count = 0
for l = 0, Logic.maxLayer("toy") do
    toy_layer_count = toy_layer_count + #(toy_bv.tiles_by_layer[l] or {})
end
expect(toy_layer_count == 5, "the toy board renders all 5 tiles across layers")
expect(mapCount(toy_bv.tile_widgets) == 5,
    "the toy board built 5 tile widgets")
-- Hit-test the top tile: a tap on its face returns the top tile.
toy_bv.dimen.x, toy_bv.dimen.y = 0, 0
local tpx, tpy = toy_bv:tilePos(0.5, 0.5, 1)
local hit = toy_bv:hitTest(tpx + 1, tpy + 1)
expect(hit ~= nil and hit.x == 0.5 and hit.y == 0.5 and hit.layer == 1,
    "the toy board hit-tests the top tile")

-- ---- Persistence v2 round-trip with layout ---------------------------------

-- A real mid-game Turtle state round-trips with layout="turtle" in v2.
local p_board = Logic.newGame(7)
local p_pair = Logic.matchingFreePair(p_board)
local p_ok, p_ka, p_kb = Logic.removePair(p_board, p_pair.a, p_pair.b)
expect(p_ok, "persistence round-trip: removePair works on a real board")
local p_hist = {
    { a = p_pair.a, b = p_pair.b, ka = p_ka, kb = p_kb, score = 10, prev_last = nil },
}
local p_ser = Logic.serializeGameState(p_board, p_hist, 10, p_ka, 123, 0, 0, "turtle")
expect(p_ser.v == 2 and p_ser.layout == "turtle",
    "serialized state is v2 and carries the turtle layout id")
local p_restored = Logic.deserializeGameState(p_ser)
expect(p_restored ~= nil and p_restored.layout == "turtle",
    "deserialize restores the turtle layout id")

-- An unknown saved layout id is corrupt -> nil (the caller deals fresh).
local bad = {
    v = 2, layout = "nope",
    board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1" },
    history = {}, score = 0, last = nil, elapsed = 0,
}
expect(Logic.deserializeGameState(bad) == nil,
    "deserialize rejects an unknown saved layout id (deals fresh)")

-- A v1 save (no layout field) restores as Turtle. Build a genuine mid-game
-- v1 state from a real board (count must satisfy tile + 2*history == 144).
local v1_base = Logic.newGame(7)
local v1_pair = Logic.matchingFreePair(v1_base)
local v1_ok, v1_ka, v1_kb = Logic.removePair(v1_base, v1_pair.a, v1_pair.b)
expect(v1_ok, "v1 round-trip: removePair works on a real board")
local v1 = {
    v = 1,
    board = (function()
        local b = {}
        for k, vv in pairs(v1_base) do b[k] = vv end
        return b
    end)(),
    history = { { v1_pair.a.x, v1_pair.a.y, v1_pair.a.layer,
                  v1_pair.b.x, v1_pair.b.y, v1_pair.b.layer,
                  v1_ka, v1_kb, 10, nil } },
    score = 10, last = v1_ka, elapsed = 0,
}
local v1_r = Logic.deserializeGameState(v1)
expect(v1_r ~= nil and v1_r.layout == "turtle",
    "a v1 save (no layout field) restores as turtle")

-- ---- The picker appears on first launch / New Game / Play again --------------

-- First launch: no saved game -> menu callback shows the picker.
store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local top = ctx.window_stack[#ctx.window_stack].widget
expect(top ~= nil and top.name == "mahjonglayoutselect",
    "first launch (no saved game) shows the layout picker")
-- The picker lists a card for every registered layout (turtle + toy at this
-- point in the test). One of them MUST be Turtle.
local has_turtle_card = false
for _, c in ipairs(top._card_rects) do
    if c.id == "turtle" then has_turtle_card = true end
end
expect(has_turtle_card, "the picker lists a Turtle card")
expect(#top._card_rects == #Logic.layoutIds(),
    "the picker lists one card per registered layout")

-- The thumbnail renders for every registered layout (turtle + toy).
for _, c in ipairs(top._card_rects) do
    local thumb = LayoutSelect.layoutThumbnail(c.id, 100, 100)
    expect(thumb ~= nil and type(thumb) == "table" and thumb.dimen ~= nil
            and thumb.dimen.w == 100 and thumb.dimen.h == 100,
        "the thumbnail renders for layout '" .. c.id .. "' with the requested dimen")
    -- The thumbnail has one tile widget per layout position.
    expect(#thumb == #Logic.buildLayout(c.id),
        "the thumbnail for '" .. c.id .. "' has one tile per layout position")
end

-- Picking Turtle deals a game and shows the Mahjong widget.
pickTurtle()
expect(mj.board ~= nil and Logic.tileCount(mj.board) == 144,
    "picking Turtle from the picker deals a 144-tile board")
expect(mj.layout == "turtle", "the chosen layout is tracked on the Mahjong instance")
expect(store.layout == "turtle", "the chosen layout is persisted as the last-chosen default")
expect(ctx.window_stack[#ctx.window_stack].widget == mj,
    "picking Turtle shows the Mahjong widget")
expect(store.game ~= nil and store.game.layout == "turtle",
    "the dealt game is saved with the turtle layout id")

-- New Game button: shows the picker (no ConfirmBox). Choosing Turtle deals
-- a fresh board.
ctx.last_confirm = nil
local toolbar = mj[1][4]
local btns = {}
for i = 1, #toolbar do
    local b = toolbar[i]
    if type(b) == "table" and b.bordersize then
        btns[#btns + 1] = b
    elseif type(b) == "table" and b[1] and b[1].bordersize then
        btns[#btns + 1] = b[1]
    end
end
local old_board = mj.board
btns[4].callback() -- New Game
expect(ctx.last_confirm == nil, "New Game shows no ConfirmBox (picker instead)")
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "New Game opens the layout picker")
pickTurtle()
expect(mj.board ~= old_board and Logic.tileCount(mj.board) == 144,
    "New Game -> pick Turtle deals a fresh board")

-- Play again (win dialog): the ok_callback shows the picker.
local mj2 = Mahjong:new()
mj2.board = (function()
    local b = {}
    b[pk(2, 2, 0)] = "b1"; b[pk(4, 2, 0)] = "b1"
    return b
end)()
mj2:buildUILayout()
mj2:handleTileTap(2, 2, 0)
mj2:handleTileTap(4, 2, 0)
expect(Logic.isWin(mj2.board), "the two-tile board is won")
expect(ctx.last_confirm ~= nil and ctx.last_confirm.ok_text == "Play again",
    "the win dialog offers Play again")
ctx.last_confirm.ok_callback()
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "Play again shows the layout picker")
pickTurtle()
expect(Logic.tileCount(mj2.board) == 144 and mj2.layout == "turtle",
    "Play again -> pick Turtle deals a fresh turtle board")

-- ---- Picker close X / tap outside cancels ----------------------------------

-- A tap outside any card calls onClose (the picker closes without dealing).
store.game = nil
local mj3 = Mahjong:new()
mj3:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker3 = ctx.window_stack[#ctx.window_stack].widget
-- Tap the very top-left corner (the title row, above the grid) — outside cards.
picker3:onTapSelect(nil, { pos = { x = 1, y = 1 } })
local picker3_gone = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == picker3 then picker3_gone = false end
end
expect(picker3_gone, "a tap outside any card closes the picker (cancel)")
expect(mj3.board == nil, "canceling the picker on first launch deals no board")

-- The close X button also cancels.
store.game = nil
local mj4 = Mahjong:new()
mj4:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker4 = ctx.window_stack[#ctx.window_stack].widget
picker4._close_btn.callback()
local picker4_gone = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == picker4 then picker4_gone = false end
end
expect(picker4_gone, "the close X closes the picker")

-- ---- A restored game keeps its layout (no picker) ---------------------------

-- Save a mid-game turtle state; a fresh instance restores it directly (the
-- picker does NOT appear — a saved game resumes, per the plan).
store.game = nil
local mj5 = Mahjong:new()
mj5.board = Logic.newGame(7)
mj5.layout = "turtle"
mj5:buildUILayout()
local a5 = Logic.matchingFreePair(mj5.board)
mj5:handleTileTap(a5.a.x, a5.a.y, a5.a.layer)
mj5:handleTileTap(a5.b.x, a5.b.y, a5.b.layer)
expect(store.game ~= nil and store.game.layout == "turtle",
    "a mid-game turtle state is saved with layout=turtle")

local mj6 = Mahjong:new()
mj6:startGame()
expect(mj6.board ~= nil and Logic.tileCount(mj6.board) == 142,
    "a saved game restores directly (no picker on a restored game)")
expect(mj6.layout == "turtle", "the restored game keeps its layout id")
local restored_via_picker = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget ~= nil and e.widget.name == "mahjonglayoutselect" then
        restored_via_picker = true
    end
end
expect(not restored_via_picker,
    "a restored game does NOT show the picker (resumes directly)")

-- ---- Deregister the toy layout (restore the {bridge, spider, turtle, ziggurat} registry) ----------

Logic.layouts["toy"] = nil
expect(#Logic.layoutIds() == 4 and Logic.layoutIds()[1] == "bridge" and Logic.layoutIds()[2] == "spider"
        and Logic.layoutIds()[3] == "turtle" and Logic.layoutIds()[4] == "ziggurat",
    "deregistering the toy layout restores the {bridge, spider, turtle, ziggurat} registry")

if failures == 0 then
    print("\nALL US-14 LAYOUT-REGISTRY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
