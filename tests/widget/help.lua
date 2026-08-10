-- US-36 — compact gameplay help opened from the layout picker.

local mock = require("mock")
local ctx = mock.newContext()

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

local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget

expect(picker and picker.name == "mahjonglayoutselect", "picker opens on a fresh game")
expect(picker and picker._help_btn and picker._help_btn.text == "?",
    "picker has a question-mark help button")

if picker and picker._help_btn then picker._help_btn.callback() end
local help = ctx.window_stack[#ctx.window_stack].widget
expect(help and help.name == "mahjonghelp", "question button opens the help page")
expect(#ctx.window_stack == 2, "help is modal above the picker")
expect(help._page_navigation_cover ~= nil,
    "help covers the layout picker's page-navigation footer")
expect(picker._page_footer_group[1] ~= picker._page_left
        and picker._page_footer_group[3] ~= picker._page_indicator
        and picker._page_footer_group[5] ~= picker._page_right,
    "picker page buttons are hidden while help is open")

local saw_icon = {}
local saw_auto_solve = false
local saw_text = {}
local function inspect(node)
    if type(node) ~= "table" then return end
    if node.icon then saw_icon[node.icon] = true end
    if type(node.text) == "string" and node.text:lower():match("auto.?solve") then
        saw_auto_solve = true
    end
    if type(node.text) == "string" then saw_text[node.text] = true end
    for _, child in ipairs(node) do inspect(child) end
end
inspect(help)
expect(saw_icon["mahjong/c1"] and saw_icon["mahjong/east"]
        and saw_icon["mahjong/d1"] and saw_icon["mahjong/b1"]
        and saw_icon["mahjong/south"] and saw_icon["mahjong/west"]
        and saw_icon["mahjong/north"] and saw_icon["mahjong/red"]
        and saw_icon["mahjong/green"] and saw_icon["mahjong/white"]
        and saw_icon["mahjong/flower1"] and saw_icon["mahjong/flower2"]
        and saw_icon["mahjong/flower3"] and saw_icon["mahjong/flower4"]
        and saw_icon["mahjong/season1"] and saw_icon["mahjong/season2"]
        and saw_icon["mahjong/season3"] and saw_icon["mahjong/season4"],
    "help renders every requested tile-group example")
expect(not saw_auto_solve, "help does not mention the hidden auto-solve feature")
expect(saw_text["X"], "help marks blocked tiles with X")

if help and help[1] then
    local function inspect_for_text(node, found)
        if type(node) ~= "table" then return end
        if type(node.text) == "string" then
            if node.text:match("costs 5 points") or node.text:match("costs 10 points")
                    or node.text:match("COMBO") or node.text:match("chain combo") then
                found.value = true
            end
        end
        for _, child in ipairs(node) do inspect_for_text(child, found) end
    end
    local next_button
    local page_indicator
    local function find_button(node)
        if type(node) ~= "table" then return end
        if node.text == "Next" then next_button = node end
        if node.text == "1/2" then page_indicator = node end
        for _, child in ipairs(node) do find_button(child) end
    end
    find_button(help)
    expect(next_button == nil and page_indicator ~= nil,
        "help uses a bottom page indicator instead of a top Next button")
    if page_indicator then
        local right_arrow
        local function find_right(node)
            if type(node) ~= "table" then return end
            if node.text == "→" then right_arrow = node end
            for _, child in ipairs(node) do find_right(child) end
        end
        find_right(help)
        if right_arrow then right_arrow.callback() end
    end
    local page_two = { value = false }
    inspect_for_text(help, page_two)
    expect(page_two.value, "help page two explains penalties and combo scoring")
end

help:closeDialog()
expect(ctx.window_stack[#ctx.window_stack].widget == picker,
    "closing help returns to the layout picker")
expect(picker._page_footer_group[1] == picker._page_left
        and picker._page_footer_group[3] == picker._page_indicator
        and picker._page_footer_group[5] == picker._page_right,
    "picker page buttons reappear after help closes")
expect(mj._help_dlg == nil, "closing help clears the owner reference")

if failures > 0 then
    os.exit(1)
end
print("US-36 help suite passed")
