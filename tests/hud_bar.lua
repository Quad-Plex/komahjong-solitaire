-- HUD top bar suite: the title bar is a stylized HUD (hudbar.lua) holding the
-- game title, three stat chips (Pairs / Free / Score) and the quit X, instead
-- of a TitleBarWidget with a plain-text subtitle.
--
-- * the HudBar class builds one chip per stat, each with an icon, a bold
--   value and a tiny label;
-- * setStats() updates the three values and the stored stats;
-- * the chips live on the same bar as the title and the quit button;
-- * main.lua wires the bar and pushes the real numbers after every move.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
ctx.loadPlugin("mahjongboard")
local HudBar = ctx.loadPlugin("hudbar")
local Mahjong = ctx.loadPlugin("main")

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

-- US-14: startGame with no saved game shows the layout picker; pick Turtle.
local function pickTurtle()
    local picker = ctx.window_stack[#ctx.window_stack].widget
    if not picker or picker.name ~= "mahjonglayoutselect" then return end
    if picker._page_right and picker._page_right.enabled ~= false then
        picker._page_right.callback()
    end
    local r
    for _, c in ipairs(picker._card_rects) do
        if c.id == "turtle" then r = c break end
    end
    picker:onTapSelect(nil, { pos = { x = r.x + r.w / 2, y = r.y + r.h / 2 } })
    ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
end

-- ---- HudBar widget ---------------------------------------------------------

local close_cb = function() return "closed" end
local bar = HudBar:new{
    title = "Mahjong Solitaire",
    right_icon = "mahjong/close",
    right_icon_size_ratio = 0.9,
    right_icon_tap_callback = close_cb,
}

expect(bar.title == "Mahjong Solitaire", "HUD bar keeps the game title")
expect(bar.right_icon == "mahjong/close"
        and (bar.right_icon_size_ratio or 0.6) > 0.6,
    "quit X uses the bolder mahjong/close icon at a larger size")
expect(bar.right_icon_tap_callback == close_cb, "quit X callback is wired")
expect(bar.stats.pairs == 0 and bar.stats.free == 0 and bar.stats.score == 0,
    "chips start at zero")
expect(type(bar:getSize()) == "table" and bar:getSize().h >= 0,
    "HUD bar reports a size (getSize contract)")

-- The bar's layout holds row1/row2 on the left and quit button on the right.
-- Recursively scan descendants for bordered rounded boxes (chips) and icon buttons (quit X).
local function findDescendants(node, chips, quits)
    if type(node) ~= "table" then return end
    if (node.bordersize or 0) > 0 and node.name ~= "hudbar" then
        chips[#chips + 1] = node
    end
    if node.icon and node.callback and node.name ~= "hudbar" then
        quits[#quits + 1] = node
    end
    for _, child in ipairs(node) do
        findDescendants(child, chips, quits)
    end
end

local chips, quits = {}, {}
findDescendants(bar._bar_layout, chips, quits)
local quit = quits[1]

expect(#chips == 3, "exactly three stat chips on the bar")
expect(quit ~= nil and quit.icon == "mahjong/close" and quit.callback == close_cb,
    "quit X sits on the bar as an icon button")
expect(quit.height == bar.HUD_H,
    "close button on the right takes the space of both row of title text and row of score chips")

-- Each chip is a HorizontalGroup with icon | value | label (5 children).
-- Also verify label text has high contrast (fgcolor == black).
local icons = { "mahjong/hud_pairs", "mahjong/lightbulb", "mahjong/hud_score" }
local labels = { "Pairs", "Free", "Score" }
local all_chips_ok = true
local high_contrast_ok = true
for i, chip in ipairs(chips) do
    local layout = chip[1]  -- KOReader stores first positional arg as self[1]
    if type(layout) ~= "table" or #layout ~= 5
            or layout[1].icon ~= icons[i] or layout[3].text ~= "0"
            or layout[5].text ~= labels[i] then
        all_chips_ok = false
    end
    local label_widget = layout[5]
    if label_widget.fgcolor ~= "black" then
        high_contrast_ok = false
    end
end
expect(all_chips_ok, "chips are icon / value / label rows (Pairs, Free, Score)")
expect(high_contrast_ok, "contrast on the hint/label text in the chips is increased (black)")

-- ---- setStats ----------------------------------------------------------------

bar:setStats(70, 5, 120)
expect(bar.stats.pairs == 70 and bar.stats.free == 5 and bar.stats.score == 120,
    "setStats stores the three stats")
expect(bar._value_widgets.pairs.text == "70"
        and bar._value_widgets.free.text == "5"
        and bar._value_widgets.score.text == "120",
    "setStats pushes the values into the chip widgets")

-- ---- main.lua wiring ----------------------------------------------------------

local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
pickTurtle()

expect(mj.status_bar ~= nil and mj.status_bar.name == "hudbar",
    "startGame builds the HUD bar (not a stock title bar)")
expect(mj.status_bar.stats.pairs == 72 and mj.status_bar.stats.score == 0,
    "new game starts at 72 pairs / 0 score in the HUD")
expect(mj.status_bar.stats.free == Logic.countFreePairs(mj.board),
    "free chip matches the logic's free-pair count")

-- After a removal the HUD chips track the game.
local free = Logic.freeTiles(mj.board)
local a, b
for i = 1, #free - 1 do
    for j = i + 1, #free do
        if Logic.matches(free[i].kind, free[j].kind) then
            a, b = free[i], free[j]
            break
        end
    end
    if a then break end
end
expect(a ~= nil, "a full turtle has a playable free pair")
mj:handleTileTap(a.x, a.y, a.layer)
mj:handleTileTap(b.x, b.y, b.layer)
expect(mj.status_bar.stats.pairs == 71 and mj.status_bar.stats.score == 10,
    "HUD chips update after a pair is removed")
expect(mj.status_bar.stats.free == Logic.countFreePairs(mj.board),
    "free chip still matches the logic after the move")

if failures == 0 then
    print("\nALL HUD BAR CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
