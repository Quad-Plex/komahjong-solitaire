-- First-launch language default follows KOReader for German only.

local mock = require("mock")
local ctx = mock.newContext()
ctx.setKoreaderLanguage("de_DE")

local I18n = ctx.loadPlugin("mahjongi18n")
local Mahjong = ctx.loadPlugin("main")
local mj = Mahjong:new()

local failures = 0
local function expect(cond, msg)
    if not cond then failures = failures + 1; print("FAIL: " .. msg)
    else print("PASS: " .. msg) end
end

expect(I18n.getLanguage() == "de", "first launch follows KOReader's German locale")
expect(ctx.settings_store.language == "de", "detected German language is persisted")
expect(mj:getSetting("language", "en") == "de", "persisted language is readable")

if failures > 0 then os.exit(1) end
print("US-40 locale default suite passed")
