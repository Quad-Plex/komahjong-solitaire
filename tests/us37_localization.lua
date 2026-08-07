-- US-37 - English/German localization and picker settings entry point.

local mock = require("mock")
local ctx = mock.newContext()
local I18n = ctx.loadPlugin("mahjongi18n")
local Mahjong = ctx.loadPlugin("main")

local failures = 0
local function expect(cond, msg)
    if not cond then failures = failures + 1; print("FAIL: " .. msg)
    else print("PASS: " .. msg) end
end

expect(I18n.t("toolbar.hint") == "Hint", "English is the default language")
I18n.setLanguage("de")
expect(I18n.t("toolbar.hint") == "Tipp", "German catalog translates toolbar text")
expect(I18n.t("game.combo", 10) == "KOMBO +10", "German catalog formats placeholders")
I18n.setLanguage("invalid")
expect(I18n.getLanguage() == "en", "invalid language falls back to English")

local mj = Mahjong:new()
local menu = {}
mj:addToMainMenu(menu)
menu.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker.name == "mahjonglayoutselect", "picker opens on first launch")
expect(picker._settings_btn ~= nil and picker._help_btn ~= nil,
    "picker has settings and help controls")

picker._settings_btn.callback()
local settings = ctx.window_stack[#ctx.window_stack].widget
expect(settings.name == "mahjongsettings", "picker settings button opens settings")
expect(settings._rows.language.text == "English", "language row defaults to English")

settings._rows.language.callback()
expect(settings.changes.language == "de", "language row cycles to German")
settings:save()

local german_picker = ctx.window_stack[#ctx.window_stack].widget
expect(mj:getSetting("language", "en") == "de", "German language preference is persisted")
expect(I18n.getLanguage() == "de", "saving language changes the active locale")
expect(german_picker.name == "mahjonglayoutselect", "picker is rebuilt after language change")
local saw_german_title = false
local function inspect_picker(node)
    if type(node) ~= "table" then return end
    if node.text == I18n.t("picker.title") then saw_german_title = true end
    for _, child in ipairs(node) do inspect_picker(child) end
end
inspect_picker(german_picker)
expect(saw_german_title, "rebuilt picker has German title")

if german_picker._help_btn then german_picker._help_btn.callback() end
local help = ctx.window_stack[#ctx.window_stack].widget
expect(help.name == "mahjonghelp", "help still opens above the localized picker")
local saw_german = false
local function inspect(node)
    if type(node) ~= "table" then return end
    if node.text == "Spielanleitung" then saw_german = true end
    for _, child in ipairs(node) do inspect(child) end
end
inspect(help)
expect(saw_german, "help content is localized")

if failures > 0 then os.exit(1) end
print("US-37 localization suite passed")
