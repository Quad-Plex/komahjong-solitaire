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

local saw_icon = {}
local saw_auto_solve = false
local function inspect(node)
    if type(node) ~= "table" then return end
    if node.icon then saw_icon[node.icon] = true end
    if type(node.text) == "string" and node.text:lower():match("auto.?solve") then
        saw_auto_solve = true
    end
    for _, child in ipairs(node) do inspect(child) end
end
inspect(help)
expect(saw_icon["mahjong/c1"] and saw_icon["mahjong/east"]
        and saw_icon["mahjong/flower1"] and saw_icon["mahjong/season1"],
    "help renders suit, wind, flower, and season tile examples")
expect(not saw_auto_solve, "help does not mention the hidden auto-solve feature")

help:closeDialog()
expect(ctx.window_stack[#ctx.window_stack].widget == picker,
    "closing help returns to the layout picker")
expect(mj._help_dlg == nil, "closing help clears the owner reference")

if failures > 0 then
    os.exit(1)
end
print("US-36 help suite passed")
