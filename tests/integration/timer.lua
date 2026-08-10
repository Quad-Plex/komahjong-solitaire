-- US-11 timer-settings suite: the mm:ss display's refresh mode and interval.
--
-- Checks:
--   * timer_update defaults to "interval", timer_interval defaults to 5; the
--     defaults are NOT written to the settings file until a setSetting/Save;
--   * "interval" mode arms a polling loop that reschedules with the configured
--     interval (5 by default, or the stored timer_interval);
--   * "move" mode arms NO polling loop but still runs the clock;
--   * "move" mode refreshes the mm:ss on board interaction (select, match,
--     undo);
--   * the settings dialog exposes the timer rows, cycles them, Save persists,
--     Cancel discards, Reset restores the defaults;
--   * the timer-interval row is greyed out and ignores taps while the mode is
--     "On interaction", and re-enables in Periodic mode (or on Reset);
--   * Save (onApply) restarts the loop with the new interval;
--   * an out-of-range / non-numeric interval falls back to the default.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store
local um = require("ui/uimanager")
local scheduled = {}
local next_ticks = {}
um.scheduleIn = function(_, delay, fn) scheduled[#scheduled + 1] = { delay, fn } end
um.nextTick = function(_, fn) next_ticks[#next_ticks + 1] = fn end

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

local function firstFreePair(board)
    local free = Logic.freeTiles(board)
    for i = 1, #free - 1 do
        for j = i + 1, #free do
            if Logic.matches(free[i].kind, free[j].kind) then
                return free[i], free[j]
            end
        end
    end
    return nil, nil
end

-- ---- Defaults ----------------------------------------------------------------

local mj0 = Mahjong:new()
expect(mj0:getSetting("timer_update", "interval") == "interval",
    "unset timer_update defaults to interval")
expect(mj0:getSetting("timer_interval", 5) == 5, "unset timer_interval defaults to 5")
expect(mj0:timerMode() == "interval", "timerMode() defaults to interval")
expect(mj0:timerInterval() == 5, "timerInterval() defaults to 5")
expect(store.timer_update == nil and store.timer_interval == nil,
    "timer defaults are NOT written to the settings file")

-- ---- "interval" mode arms a loop with the configured interval ------------------

local mj1 = Mahjong:new()
mj1.board = Logic.newGame(3)
mj1:buildUILayout()
local nt_before = #next_ticks
mj1:startTimer()
expect(mj1._timer_running == true, "interval mode runs the clock")
expect(#next_ticks == nt_before + 1, "interval mode arms the polling loop")
scheduled = {}
next_ticks[#next_ticks]()
expect(scheduled[1] and scheduled[1][1] == 5,
    "loop reschedules with the default 5 s interval")

store.timer_interval = 2
local mj2 = Mahjong:new()
mj2.board = Logic.newGame(3)
mj2:buildUILayout()
mj2:startTimer()
scheduled = {}
next_ticks[#next_ticks]()
expect(scheduled[1] and scheduled[1][1] == 2,
    "loop reschedules with the configured 2 s interval")
expect(mj2:timerInterval() == 2, "timerInterval() reads the stored interval")
store.timer_interval = nil

-- ---- "move" mode arms no polling loop ------------------------------------------

store.timer_update = "move"
local mj3 = Mahjong:new()
mj3.board = Logic.newGame(3)
mj3:buildUILayout()
local nt_before3 = #next_ticks
mj3:startTimer()
expect(mj3._timer_running == true, "move mode still runs the clock")
expect(#next_ticks == nt_before3, "move mode does NOT arm a polling loop")
expect(mj3:timerMode() == "move", "timerMode() reflects the stored mode")

-- ---- "move" mode refreshes the mm:ss on board interaction ------------------------

local mj5 = Mahjong:new()
mj5.board = Logic.newGame(3)
mj5:buildUILayout()
mj5.elapsed_base = 65
local a5, b5 = firstFreePair(mj5.board)
mj5:handleTileTap(a5.x, a5.y, a5.layer)
expect(mj5.timer_text.text == "01:05", "move mode refreshes the mm:ss on select")
mj5:handleTileTap(b5.x, b5.y, b5.layer)
expect(mj5.timer_text.text == "01:05", "move mode refreshes the mm:ss on a match")
mj5:undo()
expect(mj5.timer_text.text == "01:05", "move mode refreshes the mm:ss on undo")
expect(mj5.timer_text.text == "01:05"
        and type(mj5.timer_text.overlap_offset) == "table",
    "timer text still has its band position (untouched by interactions)")

-- ---- Settings dialog -------------------------------------------------------------

store.timer_update = nil
store.timer_interval = nil
local mj6 = Mahjong:new()
mj6.board = Logic.newGame(5)
mj6:buildUILayout()
mj6:openSettings()
local dlg = ctx.window_stack[#ctx.window_stack].widget
expect(dlg._rows.timer_update ~= nil and dlg._rows.timer_interval ~= nil,
    "dialog exposes the timer rows")
expect(dlg.changes.timer_update == "interval" and dlg._rows.timer_update.text == "Periodic",
    "timer-update row starts at Periodic")
expect(dlg.changes.timer_interval == 5 and dlg._rows.timer_interval.text == "5 s",
    "timer-interval row starts at 5 s")
dlg._rows.timer_update.callback()
expect(dlg.changes.timer_update == "move" and dlg._rows.timer_update.text == "On interaction",
    "timer-update row cycles Periodic -> On interaction")
expect(dlg._rows.timer_interval.enabled == false,
    "timer-interval row is greyed out while the mode is On interaction")
dlg._rows.timer_interval.callback()
expect(dlg.changes.timer_interval == 5,
    "timer-interval taps are ignored while the mode is On interaction")
dlg._rows.timer_update.callback() -- move -> interval
expect(dlg.changes.timer_update == "interval" and dlg._rows.timer_interval.enabled == true,
    "timer-interval row re-enables when the mode is back to Periodic")
dlg._rows.timer_interval.callback()
expect(dlg.changes.timer_interval == 10 and dlg._rows.timer_interval.text == "10 s",
    "timer-interval row cycles 5 s -> 10 s while enabled")
dlg._rows.timer_update.callback() -- interval -> move (the mode to persist)
expect(dlg._rows.timer_interval.enabled == false,
    "timer-interval row greyed again when back to On interaction")
expect(store.timer_update == nil and store.timer_interval == nil,
    "timer changes are collected, not yet persisted")
dlg:save()
expect(store.timer_update == "move" and store.timer_interval == 10,
    "Save persists the timer settings")

-- Cancel discards the (unsaved) timer changes.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
expect(dlg.changes.timer_update == "move", "reopened dialog reflects the saved move mode")
expect(dlg._rows.timer_interval.enabled == false,
    "a dialog opened in move mode starts with the interval greyed out")
dlg._rows.timer_update.callback() -- move -> interval
expect(dlg.changes.timer_update == "interval", "timer toggle collected")
dlg:cancel()
expect(store.timer_update == "move", "Cancel discards the timer-mode change")

-- Reset restores the defaults and Save writes them.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
dlg._rows.timer_update.callback()   -- move -> interval (re-enables the row)
dlg._rows.timer_interval.callback() -- 10 -> 15
dlg:resetToDefaults()
expect(dlg.changes.timer_update == "interval" and dlg.changes.timer_interval == 5,
    "Reset restores the timer defaults")
expect(dlg._rows.timer_update.text == "Periodic" and dlg._rows.timer_interval.text == "5 s",
    "Reset re-renders the timer rows")
expect(dlg._rows.timer_interval.enabled == true,
    "Reset re-enables the timer-interval row")
dlg:save()
expect(store.timer_update == "interval" and store.timer_interval == 5,
    "Save after Reset writes the timer defaults back")

-- ---- onApply restarts the loop with the new interval ------------------------------

store.timer_update = "interval"
store.timer_interval = 10
local mj7 = Mahjong:new()
mj7.board = Logic.newGame(7)
mj7:buildUILayout()
mj7:startTimer() -- arms a 10 s loop
mj7:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
dlg._rows.timer_interval.callback() -- 10 -> 15
dlg._rows.timer_interval.callback() -- 15 -> 30
scheduled = {}
dlg:save()
expect(store.timer_interval == 30, "Save persisted the new interval")
next_ticks[#next_ticks]()
expect(scheduled[1] and scheduled[1][1] == 30,
    "onApply re-armed the loop with the new 30 s interval")

-- ---- Interval validation -------------------------------------------------------------

store.timer_interval = 0
local mj8 = Mahjong:new()
expect(mj8:timerInterval() == 5, "a zero interval falls back to the default")
store.timer_interval = "abc"
expect(mj8:timerInterval() == 5, "a non-numeric interval falls back to the default")
store.timer_interval = 1
expect(mj8:timerInterval() == 1, "the minimum interval is honored")

-- ---- stopTimer freezes elapsed in move mode too ----------------------------------------

store.timer_update = "move"
local mj9 = Mahjong:new()
mj9.board = Logic.newGame(9)
mj9:buildUILayout()
mj9:startTimer()
expect(mj9._timer_running == true, "move mode arms the clock")
mj9:stopTimer()
expect(mj9._timer_running == false and type(mj9.elapsed_base) == "number",
    "stopTimer freezes elapsed in move mode too")

if failures == 0 then
    print("\nALL US-11 TIMER CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
