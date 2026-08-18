-- Responsive UI regression checks for a narrow phone canvas and rotation.

local mock = require("mock")
local ctx = mock.newContext()
ctx.screen.getWidth = function() return 360 end
ctx.screen.getHeight = function() return 640 end

local Logic = ctx.loadPlugin("mahjonglogic")
local Board = ctx.loadPlugin("mahjongboard")
local HudBar = ctx.loadPlugin("hudbar")
local Help = ctx.loadPlugin("mahjonghelp")
local Settings = ctx.loadPlugin("mahjongsettings")
local StatsWidget = ctx.loadPlugin("mahjongstatswidget")
local Picker = ctx.loadPlugin("mahjonglayoutselect")
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
expect(hud.HUD_H < 360 * 0.30, "narrow HUD stays within a compact screen-height budget")
for _, layout in ipairs(hud._chip_layouts) do
    expect(layout[3].max_width and layout[3].max_width > 0,
        "narrow HUD values have bounded text slots")
end

ctx.screen.getWidth = function() return 600 end
ctx.screen.getHeight = function() return 800 end
local kindle_hud = HudBar:new{
    title = "Mahjong Solitaire",
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() end,
}
expect(#kindle_hud._chip_layouts[1] == 5,
    "Kindle-sized HUD keeps the original labels and pill composition")
expect(kindle_hud.HUD_H < 800 * 0.25, "Kindle-sized HUD remains compact")
for _, layout in ipairs(kindle_hud._chip_layouts) do
    expect(layout[5].max_width and layout[5].max_width > 0,
        "Kindle-sized HUD labels have bounded text slots")
end
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
expect(help._panel_geom.x >= 0 and help._panel_geom.y >= 0
        and help._panel_geom.x + help._panel_geom.w <= 360
        and help._panel_geom.y + help._panel_geom.h <= 640,
    "help panel remains inside the phone canvas")

local settings = Settings:new{}
expect(settings._panel_geom.x >= 0 and settings._panel_geom.y >= 0
        and settings._panel_geom.x + settings._panel_geom.w <= 360
        and settings._panel_geom.y + settings._panel_geom.h <= 640,
    "settings panel remains inside the phone canvas")
local phone_stats = StatsWidget:new{ show_map = false }
expect(phone_stats._panel_geom.x >= 0 and phone_stats._panel_geom.y >= 0
        and phone_stats._panel_geom.x + phone_stats._panel_geom.w <= 360
        and phone_stats._panel_geom.y + phone_stats._panel_geom.h <= 640,
    "stats panel remains inside the phone canvas")

local mj = Main:new()
local menu = {}
mj:addToMainMenu(menu)
menu.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker.name == "mahjonglayoutselect" and picker.full_width == 360
        and picker.full_height == 640, "picker uses the phone canvas dimensions")
expect(#picker._card_rects == math.min(12, #Logic.layoutIds()), "narrow picker exposes the active page")
local title_row = picker[1][1][2]
local title_widget = title_row[8]
expect(title_widget.max_width and title_widget.max_width > 0
        and title_widget.max_width <= picker.full_width,
    "narrow picker constrains the title to the canvas")
expect(title_row[2].width <= picker.full_width and title_row[10].width <= picker.full_width,
    "narrow picker keeps header controls bounded")
local first_row = 0
for _, rect in ipairs(picker._card_rects) do
    if rect.y == picker._card_rects[1].y then first_row = first_row + 1 end
    expect(rect.x >= 0 and rect.x + rect.w <= 360 and rect.h > 0,
        "picker card stays inside the narrow canvas")
    expect(rect.card[1][1][4].max_width and rect.card[1][1][4].max_width <= rect.w,
        "picker layout name stays inside its card")
end
expect(first_row == 3, "narrow picker keeps three columns")

-- Kindle PW12-sized portrait canvas: the header must not become the widest
-- child and pull the grid off-screen, even when device font metrics are large.
ctx.screen.getWidth = function() return 1072 end
ctx.screen.getHeight = function() return 1448 end
local pw_picker = Picker:new{}
expect(pw_picker.full_width == 1072 and pw_picker.full_height == 1448,
    "picker refreshes Kindle-sized runtime dimensions")
local pw_title_row = pw_picker[1][1][2]
expect(pw_title_row[8].max_width <= pw_picker.full_width,
    "Kindle-sized picker constrains the title width")
for _, rect in ipairs(pw_picker._card_rects) do
    expect(rect.x >= 0 and rect.x + rect.w <= pw_picker.full_width
            and rect.y >= 0 and rect.y + rect.h <= pw_picker.full_height,
        "Kindle-sized picker keeps every card inside the canvas")
    expect(rect.card[1][1][4].max_width <= rect.w,
        "Kindle-sized picker keeps every layout name inside its card")
end

local pw_help = Help:new{}
expect(pw_help._panel_geom.x >= 0 and pw_help._panel_geom.y >= 0
        and pw_help._panel_geom.x + pw_help._panel_geom.w <= 1072
        and pw_help._panel_geom.y + pw_help._panel_geom.h <= 1448,
    "help panel remains inside the PW12 canvas")
local pw_settings = Settings:new{}
expect(pw_settings._panel_geom.x >= 0 and pw_settings._panel_geom.y >= 0
        and pw_settings._panel_geom.x + pw_settings._panel_geom.w <= 1072
        and pw_settings._panel_geom.y + pw_settings._panel_geom.h <= 1448,
    "settings panel remains inside the PW12 canvas")
local pw_stats = StatsWidget:new{ show_map = true }
expect(pw_stats._panel_geom.x >= 0 and pw_stats._panel_geom.y >= 0
        and pw_stats._panel_geom.x + pw_stats._panel_geom.w <= 1072
        and pw_stats._panel_geom.y + pw_stats._panel_geom.h <= 1448,
    "stats panel remains inside the PW12 canvas")

ctx.screen.getWidth = function() return 360 end
ctx.screen.getHeight = function() return 640 end

local turtle
for _, rect in ipairs(picker._card_rects) do
    if rect.id == "turtle" then turtle = rect break end
end
picker:onTapSelect(nil, { pos = { x = turtle.x + turtle.w / 2, y = turtle.y + turtle.h / 2 } })
ctx.runScheduled(1)
expect(mj.board_view.width == 360 and mj.board_view.height >= 80,
    "game board receives a usable narrow area")
expect(mj.status_bar.full_width == 360, "game HUD and board share the same width")

ctx.screen.getWidth = function() return 1072 end
ctx.screen.getHeight = function() return 1448 end
mj:buildUILayout()
expect(mj.status_bar.HUD_H < 1448 * 0.15,
    "PW12-sized HUD does not consume excessive vertical space")
expect(mj.flash_region.h < 1448 * 0.08,
    "PW12-sized feedback band remains compact")
expect(mj.flash_text.max_width > 0 and mj.timer_text.max_width > 0,
    "PW12-sized status text reserves bounded slots")

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
