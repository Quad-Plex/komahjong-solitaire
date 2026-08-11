-- US-53 controller-boundary suite. Public Mahjong methods must remain stable
-- while delegating to the focused controller modules with the live owner.
local mock = require("mock")
local ctx = mock.newContext()

local Mahjong = ctx.loadPlugin("main")
local Timer = ctx.loadPlugin("mahjongtimer")
local Gameplay = ctx.loadPlugin("mahjonggameplay")
local Transitions = ctx.loadPlugin("mahjongtransitions")
local Chrome = ctx.loadPlugin("mahjongchrome")

local failures = 0
local function expect(condition, message)
    if condition then
        print("PASS: " .. message)
    else
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

local mj = Mahjong:new()
local original = {
    timer_mode = Timer.mode,
    gameplay_tap = Gameplay.handleTileTap,
    transition_check = Transitions.checkGameState,
    chrome_status = Chrome.updateStatus,
}

Timer.mode = function(owner)
    return owner == mj and "timer-boundary" or "wrong-owner"
end
expect(mj:timerMode() == "timer-boundary", "timer facade passes the live Mahjong owner")
Timer.mode = original.timer_mode

Gameplay.handleTileTap = function(owner, x, y, layer)
    return owner == mj and x + y + layer or nil
end
expect(mj:handleTileTap(1, 2, 3) == 6,
    "gameplay facade preserves handleTileTap arguments and return value")
Gameplay.handleTileTap = original.gameplay_tap

Transitions.checkGameState = function(owner, value)
    return owner == mj and value
end
expect(mj:checkGameState("transition-boundary") == "transition-boundary",
    "transition facade passes the live owner without copied state")
Transitions.checkGameState = original.transition_check

Chrome.updateStatus = function(owner)
    return owner == mj and "chrome-boundary"
end
expect(mj:updateStatus() == "chrome-boundary",
    "chrome facade keeps updateStatus's public calling shape")
Chrome.updateStatus = original.chrome_status

expect(type(Timer.start) == "function" and type(Timer.stop) == "function"
        and type(Timer.updateDisplay) == "function",
    "timer controller exposes lifecycle and display operations")
expect(type(Gameplay.applyMatch) == "function" and type(Gameplay.showHint) == "function"
        and type(Gameplay.shuffleBoard) == "function",
    "gameplay controller exposes gameplay operations")
expect(type(Transitions.scheduleWinDialog) == "function"
        and type(Transitions.scheduleDeadBoardDialog) == "function",
    "transition controller exposes deferred terminal operations")
expect(type(Chrome.defer) == "function" and type(Chrome.settle) == "function"
        and type(Chrome.bake) == "function",
    "chrome controller exposes batching and settling operations")

if failures == 0 then
    print("\nALL US-53 CONTROLLER BOUNDARY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
