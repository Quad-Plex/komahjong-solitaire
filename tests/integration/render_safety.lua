-- US-47 render-safety suite: terminal board transitions must let a structural
-- tile repaint settle before opening a full-screen win card, while headless
-- construction retains the immediate behavior used throughout the older tests.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")
local UIManager = require("ui/uimanager")
UIManager._repaint = function() end

local failures = 0
local function expect(cond, msg)
    if cond then
        print("PASS: " .. msg)
    else
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

local function boardWith(entries)
    local board = {}
    for _, e in ipairs(entries) do
        board[Logic.posKey(e[1], e[2], e[3])] = e[4]
    end
    return board
end

-- A live game is on the window stack. The final pair queues a two-tick modal
-- transition, leaving the pair's regional tile refresh to drain first.
local live = Mahjong:new()
live.board = boardWith{ { 2, 2, 0, "b1" }, { 4, 2, 0, "b1" } }
live:buildUILayout()
UIManager:show(live)
live:handleTileTap(2, 2, 0)
live:handleTileTap(4, 2, 0)
expect(Logic.isWin(live.board), "final pair clears the live board")
expect(ctx.last_confirm == nil and live._win_dialog_pending == true,
    "live win card waits for the structural board repaint")
ctx.runScheduled()
expect(ctx.last_confirm == nil,
    "first deferred tick only creates the second-tick callback")
ctx.runScheduled()
expect(ctx.last_confirm == nil and live._win_dialog_pending == true,
    "second deferred tick lets the board structural retry repaint first")
ctx.runScheduled()
expect(ctx.last_confirm and ctx.last_confirm.name == "mahjongwinsummary"
        and live._win_dialog_pending == false,
    "third deferred tick opens the win summary after the repaint opportunity")

-- Closing/replacing the game while that callback is pending must make it inert.
local stale = Mahjong:new()
stale.board = boardWith{ { 2, 2, 0, "b1" }, { 4, 2, 0, "b1" } }
stale:buildUILayout()
UIManager:show(stale)
stale:handleTileTap(2, 2, 0)
stale:handleTileTap(4, 2, 0)
UIManager:close(stale)
ctx.last_confirm = nil
ctx.runScheduled()
ctx.runScheduled()
ctx.runScheduled()
expect(ctx.last_confirm == nil,
    "a pending win transition cannot open a card over a closed game")

-- Opening the layout picker supersedes a pending win card even though the won
-- game remains on the stack beneath the opaque picker.
local superseded = Mahjong:new()
superseded.board = boardWith{ { 2, 2, 0, "b1" }, { 4, 2, 0, "b1" } }
superseded:buildUILayout()
UIManager:show(superseded)
superseded:handleTileTap(2, 2, 0)
superseded:handleTileTap(4, 2, 0)
superseded:showLayoutPicker()
ctx.last_confirm = nil
ctx.runScheduled()
ctx.runScheduled()
ctx.runScheduled()
expect(ctx.last_confirm == nil,
    "a pending win transition cannot open a card over the layout picker")

if failures == 0 then
    print("\nALL US-47 RENDER SAFETY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
