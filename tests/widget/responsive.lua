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
local WinSummary = ctx.loadPlugin("mahjongwinsummary")
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
ctx.mocks["device"].isAndroid = nil
ctx.screen.scaleBySize = function(_, px) return px * 2 end
local pw_hud = HudBar:new{
    title = "Mahjong Solitaire",
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() end,
}
pw_hud:setStats(0, 0, 1870)
expect(pw_hud._value_widgets.score.text == "1870"
        and pw_hud._value_widgets.score.truncate_with_ellipsis == false,
    "PW12 HUD keeps the complete four-digit score without ellipsis")
expect(pw_hud._value_widgets.score.face.size <= 24
        and pw_hud._label_widgets.score.face.size <= 18,
    "PW12 HUD fits score and label typography below the high-DPI default")
for _, key in ipairs({ "pairs", "free", "score" }) do
    expect(pw_hud._value_widgets[key].max_width == pw_hud._value_specs[key].max_width,
        "PW12 HUD " .. key .. " value keeps an explicit chip slot")
end

-- Kindle regression: a Kindle also has a scaleBySize factor above one, but it
-- must retain the established picker typography and chip metrics.
ctx.mocks["device"].isAndroid = nil
ctx.screen.scaleBySize = function(_, px) return px * 2 end
local pw_summary = WinSummary:new{
    text = "Congratulations! New overall best score and best time!",
    win_rows = {
        { label = "Layout", value = "Bridge" },
        { label = "Score", value = "1870", marker = "(Global Record!)",
          marker_widget = { getSize = function() return { w = 900, h = 40 } end } },
        { label = "Time", value = "10:06", marker = "(Global Record!)",
          marker_widget = { getSize = function() return { w = 900, h = 40 } end } },
        { label = "Best combo", value = "15 (+80)", marker = "(Global Record!)",
          marker_widget = { getSize = function() return { w = 900, h = 40 } end } },
        { label = "Hints used", value = "0" },
        { label = "Shuffles", value = "1" },
        { label = "Current streak", value = "1" },
    },
    ok_text = "Play again",
    cancel_text = "Select Layout",
}
expect(pw_summary._content_w + 2 * pw_summary._panel_padding + 2 * pw_summary._border
        <= pw_summary._max_panel_w,
    "PW12 win summary card reserves a hard in-canvas width")
expect(pw_summary._headline_widget.max_width <= pw_summary._content_w
        and pw_summary._headline_widget.face.size <= 28,
    "PW12 win summary headline is bounded and not DPI-enlarged")
expect(pw_summary._content_w < pw_summary._max_panel_w,
    "PW12 win summary headline does not force a full-width result card")
expect(pw_summary._row_slots.value < pw_summary._max_panel_w / 2,
    "PW12 win summary value column has an explicit slot")
local pw_summary_row = pw_summary._row_group[3]
expect(pw_summary_row[6].max_width <= pw_summary._row_slots.value,
    "PW12 win summary record markers cannot widen a result row")

local pw_game = Main:new()
pw_game.board = Logic.newGame("turtle", 12)
pw_game:buildUILayout()
expect(pw_game.hint_counter_badge.face.size <= 18
        and pw_game.shuffle_counter_badge.face.size <= 18
        and pw_game.hint_counter_badge.height <= 24
        and pw_game.shuffle_counter_badge.height <= 24,
    "PW12 toolbar counters stay compact beside the action icons")
pw_game.hints_used = 12
pw_game.shuffles_used = 1234
pw_game:updateStatus()
ctx.runScheduled(2) -- drain the chrome settle before the shared picker flow
ctx.runScheduled(2)
expect(pw_game.hint_counter_badge.text == "12"
        and pw_game.shuffle_counter_badge.text == "1234"
        and pw_game.hint_counter_badge.face.size <= 18
        and pw_game.shuffle_counter_badge.face.size <= 18,
    "PW12 toolbar counters refit live multi-digit values")

-- Kindle Touch-sized canvas: retain the larger native counter face while the
-- fixed badge slot prevents a two-digit value from widening past the button.
ctx.screen.getWidth = function() return 600 end
ctx.screen.getHeight = function() return 800 end
ctx.screen.scaleBySize = function(_, px) return px * 2 end
ctx.mocks["device"].isAndroid = nil
local touch_game = Main:new()
touch_game.board = Logic.newGame("turtle", 12)
touch_game:buildUILayout()
local touch_badge_width = touch_game.hint_counter_badge.width
expect(touch_game.hint_counter_badge.face.size == 24
        and touch_game.shuffle_counter_badge.face.size == 24,
    "Kindle Touch keeps its readable native counter face")
touch_game.hint_counter_badge:setCounterText("12")
touch_game.shuffle_counter_badge:setCounterText("12")
expect(touch_game.hint_counter_badge.width == touch_badge_width
        and touch_game.shuffle_counter_badge.width == touch_badge_width
        and touch_game.hint_counter_badge.max_width == touch_badge_width
        and touch_game.shuffle_counter_badge.max_width == touch_badge_width,
    "Kindle Touch counter badges keep a fixed two-digit slot")

ctx.screen.getWidth = function() return 1072 end
ctx.screen.getHeight = function() return 1448 end

local kindle_picker = Picker:new{
    wins_by_layout = { bridge = 0 },
}
local kindle_card
for _, rect in ipairs(kindle_picker._card_rects) do
    if rect.id == "bridge" then kindle_card = rect break end
end
if kindle_card then
    local kindle_content = kindle_card.card[1][1]
    local kindle_thumb = kindle_content[2]
    local kindle_badge = kindle_thumb[2]
    local kindle_badge_row = kindle_badge[1]
    local kindle_name = kindle_content[4]
    expect(kindle_name.face.size == 32 and kindle_name.forced_height >= 32,
        "Kindle picker retains the established layout caption size")
    expect(kindle_badge_row[1].width == 32 and kindle_badge_row[3].face.size == 28,
        "Kindle picker retains the established played badge metrics")
    expect(kindle_picker._help_btn.text_font_size
            == math.floor(kindle_picker._close_btn.width * 0.45),
        "Kindle picker retains the established help glyph proportion")
end

-- Fold-like high-DPI canvas: scaleBySize is intentionally much larger than
-- the canvas growth, so card-internal text and chips must use the card as an
-- additional bound instead of inheriting the raw DPI-scaled size.
ctx.screen.getWidth = function() return 1600 end
ctx.screen.getHeight = function() return 2000 end
ctx.screen.scaleBySize = function(_, px) return px * 3 end
ctx.mocks["device"].isAndroid = function() return true end
local fold_hud = HudBar:new{
    title = "Mahjong Solitaire",
    full_width = 1600,
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() end,
}
expect(fold_hud._chip_layouts[1][3].face.size <= 36
        and fold_hud._chip_layouts[1][5].face.size <= 24,
    "Fold HUD keeps stat text compact and centered beside its icons")
local fold_picker = Picker:new{
    wins_by_layout = { bridge = 0 },
    highscores_by_layout = { bridge = 120 },
    best_times_by_layout = { bridge = 125 },
}
local fold_card
for _, rect in ipairs(fold_picker._card_rects) do
    if rect.id == "bridge" then fold_card = rect break end
end
if fold_card then
    local fold_content = fold_card.card[1][1]
    local fold_thumb = fold_content[2]
    local fold_badge = fold_thumb[2]
    local fold_badge_row = fold_badge[1]
    local fold_name = fold_content[4]
    expect(fold_picker._help_btn.text_font_size <= 40,
        "Fold-sized picker keeps the help question mark compact")
    expect(fold_name.face.size <= 32
            and fold_name.forced_height > math.floor(fold_card.h * 0.14)
            and fold_name.forced_height <= math.floor(fold_card.h * 0.20),
        "Fold-sized picker keeps layout captions compact despite high DPI")
    expect(fold_badge_row[1].width <= 24,
        "Fold-sized picker keeps the played badge icon compact")
    expect(fold_badge_row[3].face.size <= 24,
        "Fold-sized picker keeps the played badge count compact")
    local fold_thumb_dimen = fold_thumb[1].dimen
    expect(fold_badge:getSize().w < fold_thumb_dimen.w * 0.25
            and fold_badge:getSize().h < fold_thumb_dimen.h * 0.25,
        "Fold-sized picker keeps the played badge inside a small thumbnail corner")
    expect(fold_thumb[3]:getSize().w < fold_thumb_dimen.w * 0.25
            and fold_thumb[4]:getSize().w < fold_thumb_dimen.w * 0.25,
        "Fold-sized picker keeps score and time chips compact")
end

-- Restore the phone canvas and neutral mock DPI for the game assertions below.
ctx.mocks["device"].isAndroid = nil
ctx.screen.getWidth = function() return 360 end
ctx.screen.getHeight = function() return 640 end
ctx.screen.scaleBySize = function(_, px) return px end

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
