-- Responsive UI regression checks for a narrow phone canvas and rotation.

local mock = require("mock")
local ctx = mock.newContext()
ctx.screen.getWidth = function() return 360 end
ctx.screen.getHeight = function() return 640 end

local Logic = ctx.loadPlugin("mahjonglogic")
local Board = ctx.loadPlugin("mahjongboard")
local HudBar = ctx.loadPlugin("hudbar")
local Help = ctx.loadPlugin("mahjonghelp")
local Main = ctx.loadPlugin("main")

local failures = 0
local function expect(condition, message)
    if condition then
        print("PASS: " .. message)
    else
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

local hud = HudBar:new{
    title = "Mahjong Solitaire",
    full_width = 360,
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() end,
}
expect(hud.full_width == 360, "HUD uses the narrow runtime width")
expect(hud._chip_layouts[1][1] ~= nil and #hud._chip_layouts[1] == 3,
    "narrow HUD chips keep an icon/value readout without overflowing labels")
expect(hud:getSize().w == 360 and hud:getSize().h > 0,
    "narrow HUD reports a positive size")

ctx.screen.getWidth = function() return 600 end
ctx.screen.getHeight = function() return 800 end
local kindle_hud = HudBar:new{
    title = "Mahjong Solitaire",
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() end,
}
expect(#kindle_hud._chip_layouts[1] == 5,
    "Kindle-sized HUD keeps the original labels and pill composition")
ctx.screen.getWidth = function() return 360 end
ctx.screen.getHeight = function() return 640 end

local board = Board:new{
    board = Logic.newGame("turtle", 42),
    layout_id = "turtle",
    width = 120,
    height = 80,
}
expect(board.tw > 0 and board.th > 0, "board geometry remains positive in a very small area")

local help = Help:new{}
expect(help._panel_geom ~= nil and help._panel_geom.w > 0,
    "help panel remains constructible on a phone canvas")

local mj = Main:new()
local menu = {}
mj:addToMainMenu(menu)
menu.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker.name == "mahjonglayoutselect" and picker.full_width == 360
        and picker.full_height == 640, "picker uses the phone canvas dimensions")
expect(#picker._card_rects == math.min(12, #Logic.layoutIds()), "narrow picker exposes the active page")
local first_row = 0
for _, rect in ipairs(picker._card_rects) do
    if rect.y == picker._card_rects[1].y then first_row = first_row + 1 end
    expect(rect.x >= 0 and rect.x + rect.w <= 360 and rect.h > 0,
        "picker card stays inside the narrow canvas")
end
expect(first_row == 3, "narrow picker keeps three columns")

local turtle
if picker._page_right and picker._page_right.enabled ~= false then picker._page_right.callback() end
picker = ctx.window_stack[#ctx.window_stack].widget
for _, rect in ipairs(picker._card_rects) do
    if rect.id == "turtle" then turtle = rect break end
end
picker:onTapSelect(nil, { pos = { x = turtle.x + turtle.w / 2, y = turtle.y + turtle.h / 2 } })
ctx.runScheduled(1)
expect(mj.board_view.width == 360 and mj.board_view.height >= 80,
    "game board receives a usable narrow area")
expect(mj.status_bar.full_width == 360, "game HUD and board share the same width")

ctx.screen.getWidth = function() return 640 end
ctx.screen.getHeight = function() return 360 end
mj:buildUILayout()
expect(mj.full_width == 640 and mj.full_height == 360,
    "rotating the device refreshes the game dimensions")
expect(mj.board_view.width == 640 and mj.status_bar.full_width == 640,
    "rotated board and HUD use the refreshed width")

if failures == 0 then
    print("\nALL RESPONSIVE LAYOUT CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
