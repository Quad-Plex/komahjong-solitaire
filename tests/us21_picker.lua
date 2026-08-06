-- US-21 — Layout picker grid expansion suite.
--
-- Verifies the picker's grid grew from a fixed 2x3 (6-slot) layout to a
-- 3-column grid with dynamically computed rows (max(3, ceil(#ids/3))),
-- wrapped in a scroll container so 4+ rows scroll on small screens. One card
-- per registered layout, sorted by id, in the correct 3-column positions.
-- Pick / close-X / tap-outside still work. This is the prerequisite for the
-- US-22..29 boards that take the total past the old 6-slot ceiling.
--
-- At US-21 time the registry holds {bridge, spider, turtle} (3 layouts →
-- 3 rows min, 9 slots, 3 cards in row 0). A throwaway "toy" layout is
-- registered mid-test to exercise the 4th-card-falls-in-row-1 path. (US-22
-- adds Ziggurat and US-23 adds Cloud, US-24/25/26 add Tic-Tac-Toe, Red Dragon
-- and Overpass, and US-27/28/29 add Pyramid's Walls, Confounding Cross and
-- Taipei, so the base registry now has 11 layouts and the toy makes 12.)

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
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

local COLS = 3
local EDGE_PAD = 16   -- Screen:scaleBySize(16) — mock is identity
local GAP = 12        -- Screen:scaleBySize(12) — mock is identity

local function cardSpacing()
    local grid_w = 1200 - 2 * EDGE_PAD - (COLS - 1) * GAP
    return math.floor(grid_w / COLS)
end
local CARD_W = cardSpacing()

-- ---- Grid is 3-column, one card per layout ----------------------------------------

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "first launch shows the layout picker")

local ids = Logic.layoutIds()
local expected_rows = math.max(3, math.ceil(#ids / COLS))
expect(#picker._card_rects == #ids,
    "picker lists one card per registered layout (" .. #ids .. " layouts, "
    .. #picker._card_rects .. " cards)")

-- The grid uses 3 columns: the first COLS cards share a row (same y) and
-- their x values step by (card_w + gap).
local row0_y = picker._card_rects[1].y
local row0_count = 0
for i = 1, #picker._card_rects do
    if picker._card_rects[i].y == row0_y then row0_count = row0_count + 1 end
end
expect(row0_count == COLS,
    "first grid row has 3 cards (got " .. row0_count .. ")")
expect(row0_count == math.min(COLS, #picker._card_rects),
    "first grid row has min(3, #ids) cards")

-- X positions step by (card_w + gap) across the first row.
for i = 1, row0_count do
    local expected_x = EDGE_PAD + (i - 1) * (CARD_W + GAP)
    expect(math.abs(picker._card_rects[i].x - expected_x) <= 1,
        "card " .. i .. " x=" .. picker._card_rects[i].x
        .. " matches 3-column layout (expected ~" .. expected_x .. ")")
end

-- Cards are appended in sorted-id order.
local sorted = true
for i = 2, #picker._card_rects do
    if picker._card_rects[i].id < picker._card_rects[i-1].id then
        sorted = false
    end
end
expect(sorted, "cards appear in sorted-id order")

-- Card ids match the registered layout ids exactly.
local card_ids = {}
for _, c in ipairs(picker._card_rects) do card_ids[#card_ids + 1] = c.id end
local ids_match = true
for i = 1, #ids do
    if card_ids[i] ~= ids[i] then ids_match = false end
end
expect(ids_match, "card ids match sorted registered layout ids")

-- Every card has a non-nil thumbnail-backed content (the card was built).
for _, c in ipairs(picker._card_rects) do
    expect(c.id == "bridge" or c.id == "cloud" or c.id == "confounding"
            or c.id == "overpass" or c.id == "pyramid" or c.id == "red-dragon"
            or c.id == "spider" or c.id == "taipei" or c.id == "tictactoe"
            or c.id == "turtle" or c.id == "ziggurat",
        "card id is a known layout (" .. tostring(c.id) .. ")")
end

-- ---- Dynamic rows: 12 layouts fill 4 rows -------------------------------------

-- Register a throwaway toy layout: 12 layouts → ceil(12/3)=4 → max(3,4)=4 rows.
-- The 4th card (overpass) wraps to row 1, column 0; the toy (10th) is the
-- first card of row 3.
local toy_spec = {
    { layer = 0, kind = "row",   x_min = 0, x_max = 1, y = 0 },
    { layer = 0, kind = "row",   x_min = 0, x_max = 1, y = 1 },
    { layer = 1, kind = "tile",  x = 0.5, y = 0.5 },
}
Logic.registerLayout{ id = "toy", name = "Toy", spec = toy_spec }

store.game = nil
local mj2 = Mahjong:new()
mj2:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker2 = ctx.window_stack[#ctx.window_stack].widget
expect(#picker2._card_rects == 12,
    "12 layouts → 12 cards (got " .. #picker2._card_rects .. ")")

-- Sorted ids: {bridge, cloud, confounding, overpass, pyramid, red-dragon,
-- spider, taipei, tictactoe, toy, turtle, ziggurat}
expect(picker2._card_rects[1].id == "bridge", "12-layout grid: slot 1 = bridge")
expect(picker2._card_rects[2].id == "cloud",  "12-layout grid: slot 2 = cloud")
expect(picker2._card_rects[3].id == "confounding", "12-layout grid: slot 3 = confounding")
expect(picker2._card_rects[4].id == "overpass", "12-layout grid: slot 4 = overpass")
expect(picker2._card_rects[5].id == "pyramid", "12-layout grid: slot 5 = pyramid")
expect(picker2._card_rects[6].id == "red-dragon", "12-layout grid: slot 6 = red-dragon")
expect(picker2._card_rects[7].id == "spider", "12-layout grid: slot 7 = spider")
expect(picker2._card_rects[8].id == "taipei", "12-layout grid: slot 8 = taipei")
expect(picker2._card_rects[9].id == "tictactoe", "12-layout grid: slot 9 = tictactoe")
expect(picker2._card_rects[10].id == "toy",    "12-layout grid: slot 10 = toy")
expect(picker2._card_rects[11].id == "turtle", "12-layout grid: slot 11 = turtle")
expect(picker2._card_rects[12].id == "ziggurat", "12-layout grid: slot 12 = ziggurat")

-- First 3 cards share row 0; the 4th is in row 1 (lower y).
expect(picker2._card_rects[1].y == picker2._card_rects[2].y
    and picker2._card_rects[2].y == picker2._card_rects[3].y,
    "first 3 cards share row 0")
expect(picker2._card_rects[4].y > picker2._card_rects[1].y,
    "4th card is in a lower row (grid has >= 2 rows)")

-- The 4th card wraps to column 0 (x = EDGE_PAD); the 5th and 6th sit beside
-- it in row 1.
expect(picker2._card_rects[4].x == EDGE_PAD,
    "4th card wraps to column 0 (x=" .. picker2._card_rects[4].x .. ")")
expect(picker2._card_rects[5].y == picker2._card_rects[4].y,
    "5th card shares the 4th card's row")
expect(picker2._card_rects[5].x > picker2._card_rects[4].x,
    "5th card sits in row 1, column 1 (x=" .. picker2._card_rects[5].x .. ")")
expect(picker2._card_rects[6].y == picker2._card_rects[4].y,
    "6th card shares the 4th card's row")
expect(picker2._card_rects[6].x > picker2._card_rects[5].x,
    "6th card sits in row 1, column 2 (x=" .. picker2._card_rects[6].x .. ")")

-- The 7th card wraps to row 2, column 0; 8th and 9th sit beside it.
expect(picker2._card_rects[7].y > picker2._card_rects[4].y,
    "7th card is in row 2 (lower than row 1)")
expect(picker2._card_rects[7].x == EDGE_PAD,
    "7th card wraps to column 0 (x=" .. picker2._card_rects[7].x .. ")")
expect(picker2._card_rects[8].y == picker2._card_rects[7].y
    and picker2._card_rects[9].y == picker2._card_rects[7].y,
    "8th and 9th cards share the 7th card's row")
expect(picker2._card_rects[8].x > picker2._card_rects[7].x
    and picker2._card_rects[9].x > picker2._card_rects[8].x,
    "8th and 9th cards sit in row 2, columns 1 and 2")

-- The 10th card (toy) wraps to row 3, column 0; 11th and 12th sit beside it.
expect(picker2._card_rects[10].y > picker2._card_rects[7].y,
    "10th card is in row 3 (lower than row 2)")
expect(picker2._card_rects[10].x == EDGE_PAD,
    "10th card wraps to column 0 (x=" .. picker2._card_rects[10].x .. ")")
expect(picker2._card_rects[11].y == picker2._card_rects[10].y
    and picker2._card_rects[12].y == picker2._card_rects[10].y,
    "11th and 12th cards share the 10th card's row")
expect(picker2._card_rects[11].x > picker2._card_rects[10].x
    and picker2._card_rects[12].x > picker2._card_rects[11].x,
    "11th and 12th cards sit in row 3, columns 1 and 2")

-- Deregister the toy layout (restore the eleven built-ins).
Logic.deregisterLayout("toy")

-- ---- Pick a layout from the grid -----------------------------------------------

-- Pick Turtle: tap its card center.
store.game = nil
local mj3 = Mahjong:new()
local mi3 = {}
mj3:addToMainMenu(mi3)
mi3.mahjong.callback()
local picker3 = ctx.window_stack[#ctx.window_stack].widget
local turtle_card
for _, c in ipairs(picker3._card_rects) do
    if c.id == "turtle" then turtle_card = c break end
end
expect(turtle_card ~= nil, "Turtle card exists in the picker")
if turtle_card then
    picker3:onTapSelect(nil, { pos = { x = turtle_card.x + turtle_card.w / 2,
                                       y = turtle_card.y + turtle_card.h / 2 } })
    ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
    expect(mj3.board ~= nil and Logic.tileCount(mj3.board) == 144,
        "picking Turtle deals a 144-tile board")
    expect(mj3.layout == "turtle", "the chosen layout is tracked as 'turtle'")
    expect(ctx.window_stack[#ctx.window_stack].widget == mj3,
        "picking Turtle shows the Mahjong widget")
end

-- ---- Close X cancels -----------------------------------------------------------

store.game = nil
local mj4 = Mahjong:new()
local mi4 = {}
mj4:addToMainMenu(mi4)
mi4.mahjong.callback()
local picker4 = ctx.window_stack[#ctx.window_stack].widget
picker4._close_btn.callback()
local gone4 = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == picker4 then gone4 = false end
end
expect(gone4, "close X dismisses the picker")
expect(mj4.board == nil, "canceling the picker deals no board")

-- ---- Tap outside cancels -------------------------------------------------------

store.game = nil
local mj5 = Mahjong:new()
local mi5 = {}
mj5:addToMainMenu(mi5)
mi5.mahjong.callback()
local picker5 = ctx.window_stack[#ctx.window_stack].widget
-- Tap top-left corner (the title row, above the grid — outside any card).
picker5:onTapSelect(nil, { pos = { x = 1, y = 1 } })
local gone5 = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == picker5 then gone5 = false end
end
expect(gone5, "tap outside any card cancels the picker")

if failures == 0 then
    print("\nALL US-21 PICKER CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
