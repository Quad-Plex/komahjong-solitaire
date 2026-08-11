-- US-52: automatic standby is inhibited only while a playable game is active.
local mock = require("mock")
local ctx = mock.newContext()
local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local failures = 0
local function expect(condition, message)
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    else
        print("PASS: " .. message)
    end
end

local function lastCall()
    return ctx.auto_standby_calls[#ctx.auto_standby_calls]
end

local function callCount()
    return #ctx.auto_standby_calls
end

local game = Mahjong:new()
game:startGame()
local picker = ctx.window_stack[#ctx.window_stack].widget
local card
for _, candidate in ipairs(picker._card_rects) do
    if candidate.id == "turtle" then card = candidate break end
end
picker:onTapSelect(nil, { pos = { x = card.x + card.w / 2, y = card.y + card.h / 2 } })
ctx.runScheduled()
expect(#ctx.auto_standby_calls == 1 and lastCall() == false,
    "fresh playable game disables automatic standby")

game:startTimer()
game:startTimer()
expect(#ctx.auto_standby_calls == 1, "acquiring the wake policy is idempotent")

game:showLayoutPicker()
expect(lastCall() == true, "opening the picker releases standby inhibition")
game:showLayoutPicker()
expect(#ctx.auto_standby_calls == 2, "releasing the wake policy is idempotent")

local picker = game._picker_dlg
picker:closeDialog()
expect(lastCall() == false, "returning from the picker reacquires standby inhibition")

game:openSettings()
expect(lastCall() == true, "settings releases standby inhibition while play is covered")
local settings = ctx.window_stack[#ctx.window_stack].widget
settings:cancel()
expect(lastCall() == false, "closing settings reacquires standby inhibition")

game:openStats()
expect(lastCall() == true, "stats releases standby inhibition while play is covered")
local stats = ctx.window_stack[#ctx.window_stack].widget
stats:closeDialog()
expect(lastCall() == false, "closing stats reacquires standby inhibition")

local dead = Mahjong:new()
dead:startGameWithLayout("turtle")
dead.board = {
    [Logic.posKey(4, 2, 0)] = "b1",
    [Logic.posKey(4, 2, 1)] = "b1",
}
dead.layout = "turtle"
dead.history = {}
dead:buildUILayout()
dead:handleNoMoves()
expect(lastCall() == true, "dead-board terminal state releases standby inhibition")

local solver = Mahjong:new()
solver:startGameWithLayout("turtle")
solver:startAutoSolve()
expect(lastCall() == true, "auto-solve releases standby inhibition")

game:onCloseWidget()
expect(lastCall() == true, "closing without a game does not disable standby")

local restored = Mahjong:new()
restored.board = Logic.newGame("turtle", 52)
restored:buildUILayout()
restored:startTimer()
restored:onCloseWidget()
expect(lastCall() == true, "framework close restores normal standby")

if failures > 0 then error(failures .. " awake-policy test(s) failed") end
print("US-52 awake-policy tests passed")
