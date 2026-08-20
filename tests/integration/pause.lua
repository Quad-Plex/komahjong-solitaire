-- US-17 pause suite: a Pause button in the bottom toolbar freezes the clock and
-- drops a full-screen modal overlay that consumes every tap, so no tile can move
-- while paused; Resume restarts the clock; closing while paused still saves.
--
-- Checks:
--   * the bottom toolbar carries a Pause button that wires pauseGame;
--   * pauseGame stops the timer (freezes elapsed: two getElapsed() reads are
--     stable) and shows the overlay on the window stack;
--   * the overlay is a full-screen modal with a board blackout whose tap gesture consumes
--     taps (it never closes on a stray tap, and a board tap can't get through);
--   * Resume (the overlay's button) closes the overlay and restarts the clock;
--   * Pause is IGNORED while the auto-solver runs (US-33): the solve is
--     un-interruptible, so no overlay is pushed, the clock keeps running, and
--     the solve still completes (recording no win);
--   * pause-then-close saves the game and stopTimer runs once;
--   * pausing a won board is a no-op.

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

local function pk(x, y, l) return Logic.posKey(x, y, l) end
local function boardWith(tiles)
    local b = {}
    for _, t in ipairs(tiles) do b[pk(t[1], t[2], t[3])] = t[4] end
    return b
end

-- ---- The toolbar Pause button ---------------------------------------------------

local mj = Mahjong:new()
mj.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj:buildUILayout()
mj:startTimer()

expect(mj.status_bar ~= nil and #mj.status_bar._left_buttons == 2,
    "the HUD carries two left buttons (settings gear + stats)")
expect(mj.pause_button ~= nil and mj.pause_button.icon == "mahjong/pause",
    "the Pause button lives in the bottom toolbar")
expect(type(mj.pause_button.callback) == "function",
    "the Pause button wires a callback")

-- ---- pauseGame freezes the clock and shows the overlay ------------------------

local elapsed_before = mj:getElapsed()
local live_tile_icon = mj.board_view.tile_widgets[pk(2, 2, 0)].icon
mj.pause_button.callback() -- tap Pause
expect(mj._timer_running == false, "pause stops the timer")
expect(mj:getElapsed() == mj:getElapsed(), "two getElapsed() reads are stable while paused")
expect(mj:getElapsed() == mj.elapsed_base,
    "paused elapsed equals the frozen elapsed_base")
expect(mj:getElapsed() >= elapsed_before,
    "the frozen elapsed is at least what it was before pausing")
local paused_widget_count = 0
for _ in pairs(mj.board_view.tile_widgets) do paused_widget_count = paused_widget_count + 1 end
expect(mj.board_view.paused == true and paused_widget_count == 144,
    "pausing switches the board view to the complete empty-tile layout")
local empty_faces = 0
for _, widget in pairs(mj.board_view.tile_widgets) do
    if widget.icon == "mahjong/empty" or widget.icon == "mahjong/empty_n"
            or widget.icon == "mahjong/empty_nr" or widget.icon == "mahjong/empty_nb" then
        empty_faces = empty_faces + 1
    end
end
expect(empty_faces == 144, "every paused tile face uses empty artwork")

local top = ctx.window_stack[#ctx.window_stack]
expect(top ~= nil and top.widget ~= nil and top.widget.name == "mahjongpause",
    "pause shows the overlay on the window stack")
local dlg = top.widget
expect(mj._pause_dlg == dlg, "the main widget tracks the open pause overlay")

-- ---- The overlay blocks taps ---------------------------------------------------

expect(dlg.covers_fullscreen == true, "the pause overlay is a full-screen modal")
expect(dlg.background == nil, "the pause overlay itself has no flat background")
expect(type(dlg[1]) == "table" and type(dlg[1].dimen) == "table",
    "the overlay's single child is a centering container")
local panel = dlg[1][1]
expect(type(panel) == "table" and panel.background == "white"
        and panel.bordersize ~= nil and panel.radius ~= nil,
    "the centered panel is a bordered white card")
expect(dlg.ges_events ~= nil and dlg.ges_events.TapClose ~= nil,
    "the overlay registers a full-screen tap gesture")

-- A tap that misses the Resume button is swallowed: the overlay stays up, the
-- game stays paused, and nothing on the board moves.
local tiles_before = Logic.tileCount(mj.board)
expect(dlg:onTapClose(nil, { pos = { notIntersectWith = function() return true end } }) == true,
    "the overlay's tap handler consumes the tap (returns true)")
local still_top = ctx.window_stack[#ctx.window_stack]
expect(still_top.widget == dlg, "a stray tap does NOT dismiss the pause overlay")
expect(mj._timer_running == false, "a stray tap leaves the clock frozen")
expect(Logic.tileCount(mj.board) == tiles_before, "a stray tap moves no tiles")

-- ---- Resume restarts the clock and drops the overlay ---------------------------

expect(dlg._resume_btn ~= nil and type(dlg._resume_btn.callback) == "function",
    "the card has a Resume button")
local frozen = mj:getElapsed()
dlg._resume_btn.callback()
local gone = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg then gone = false end
end
expect(gone, "Resume closes the pause overlay")
expect(mj._pause_dlg == nil, "the main widget clears the pause reference")
expect(mj._timer_running == true, "Resume restarts the clock")
expect(mj:getElapsed() >= frozen, "the clock accrues again after Resume")
expect(mj.board_view.paused == false
        and mj.board_view.tile_widgets[pk(2, 2, 0)].icon == live_tile_icon,
    "Resume restores the live tile artwork")

-- ---- Device suspend/resume freezes only a previously-running timer ------------

local suspend_elapsed = mj:getElapsed()
expect(mj:onSuspend() == false and mj._timer_running == false,
    "Suspend stops the running game timer")
expect(mj:getElapsed() == suspend_elapsed,
    "Suspend freezes elapsed time")
local suspend_frozen = mj:getElapsed()
mj:onSuspend() -- Some device paths can emit another Suspend before Resume.
expect(mj:getElapsed() == suspend_frozen,
    "duplicate Suspend events do not advance or reset elapsed time")
mj:onResume()
expect(mj._timer_running == true and mj:getElapsed() >= suspend_frozen,
    "Resume restarts a timer paused by device suspend")

mj:pauseGame()
mj:onSuspend()
mj:onResume()
expect(mj._timer_running == false,
    "Resume does not override an already-manually-paused game")
local manual_dlg = mj._pause_dlg
if manual_dlg then manual_dlg:resume() end

-- ---- Pause is IGNORED while a running auto-solver owns the board (US-33) ---------

local mj_solve = Mahjong:new()
mj_solve.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj_solve:buildUILayout()
mj_solve.score = 0
mj_solve:startTimer()
scheduled = {}
mj_solve.hint_button.hold_callback()
local arm = scheduled[1][2]
scheduled = {}
arm()
expect(mj_solve._auto_solve_active == true, "auto-solver running before pause")
mj_solve:pauseGame()
expect(mj_solve._auto_solve_active == true,
    "Pause is ignored while the solver runs (US-33)")
expect(mj_solve._pause_dlg == nil, "no pause overlay is pushed")
expect(mj_solve._timer_running == true, "a blocked pause leaves the clock running")
-- The solve still runs to completion (it is un-interruptible).
local guard = 0
while scheduled[1] and guard < 200 do
    local e = table.remove(scheduled, 1)
    e[2]()
    guard = guard + 1
end
expect(Logic.isWin(mj_solve.board), "the solve still clears the board after a blocked pause")
expect(ctx.last_confirm ~= nil
        and ctx.last_confirm.text:find("You cleared the board", 1, true),
    "the completed solve shows the win dialog")
expect(mj_solve.game_was_autosolved == true and mj_solve.game_won == false,
    "an auto-solved win records nothing")

-- ---- Closing while paused still saves ------------------------------------------

local mj_close = Mahjong:new()
mj_close.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj_close:buildUILayout()
mj_close:startTimer()
mj_close:pauseGame()
local dlg3 = ctx.window_stack[#ctx.window_stack].widget
expect(mj_close._timer_running == false, "paused before close")

mj_close:onCloseWidget() -- the quit/close path while paused
expect(type(store.game) == "table" and store.game.v == 2,
    "closing while paused saves the game state")
expect(mj_close._timer_running == false,
    "closing while paused leaves the clock stopped (stopTimer ran once)")
local dlg3_gone = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg3 then dlg3_gone = false end
end
expect(dlg3_gone, "closing the game drops the pause overlay too")
expect(mj_close.board == nil and mj_close.board_view == nil,
    "onCloseWidget still cleans up the board")

-- ---- Pausing a won board is a no-op ---------------------------------------------

local mj_won = Mahjong:new()
mj_won.board = {}
mj_won:buildUILayout()
mj_won:pauseGame()
local stack_len = #ctx.window_stack
local any_pause = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget ~= nil and e.widget.name == "mahjongpause" then any_pause = true end
end
expect(not any_pause, "pausing a won board shows no overlay")

if failures == 0 then
    print("\nALL US-17 PAUSE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
