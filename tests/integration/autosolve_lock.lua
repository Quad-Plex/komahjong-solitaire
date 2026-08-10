-- US-33 auto-solve lock suite: the solver is UNINTERRUPTIBLE, its games are
-- tainted in the save, and a reload RESUMES the solve — there is no way to
-- close mid-solve and finish by hand to keep a score.
--
-- Checks:
--   * a save made mid-solve carries the `autosolved` taint flag;
--   * closing mid-solve (onCloseWidget) saves the tainted partial board, and a
--     fresh instance restores it tainted and RESUMES the solver;
--   * the resumed solve runs to completion -> win dialog with NO stats
--     recorded (game_won stays false);
--   * a pre-US-33 v2 save (no flag) restores clean and does NOT resume;
--   * while the solver runs, Pause / Settings / Stats / Layout picker / quit X
--     are all silent no-ops (no dialog or overlay is pushed).

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store
local um = require("ui/uimanager")
local scheduled = {}
um.scheduleIn = function(_, delay, fn) scheduled[#scheduled + 1] = { delay = delay, fn = fn } end
um.nextTick = function(_, fn) scheduled[#scheduled + 1] = { delay = 0, fn = fn } end

-- "move" timer mode: no polling loop, so flushing scheduled tasks is
-- deterministic (a 5 s polling tick would otherwise keep re-queueing itself).
store.timer_update = "move"

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

local function startSolve(mj)
    scheduled = {}
    mj.hint_button.hold_callback()
    local arm = scheduled[1].fn
    scheduled = {}
    arm()
    expect(mj._auto_solve_active == true, "the auto-solver is running")
end

local function drainScheduled(guard)
    guard = guard or 500
    local n = 0
    while scheduled[1] and n < guard do
        local e = table.remove(scheduled, 1)
        e.fn()
        n = n + 1
    end
    return n
end

-- ---- A save made mid-solve carries the taint flag -------------------------------

local mj = Mahjong:new()
mj.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj:buildUILayout()
mj.score = 0
scheduled = {}
mj.hint_button.hold_callback()
local arm = scheduled[1].fn
scheduled = {}
arm()
expect(mj.game_was_autosolved == true, "startAutoSolve taints the game")
mj:saveGameState()
expect(store.game ~= nil and store.game.autosolved == true,
    "a save made mid-solve carries the taint flag")

-- ---- Closing mid-solve saves a tainted board; reload RESUMES the solve ----------

-- A full 144-tile board so the saved state passes deserializeGameState's
-- hard validation (tileCount + 2*#history == 144).
local mj2 = Mahjong:new()
mj2.board = Logic.newGame(3)
mj2:buildUILayout()
mj2.score = 0
startSolve(mj2)
expect(Logic.tileCount(mj2.board) == 142, "the first solve step removed one pair")

mj2:onCloseWidget() -- the close path (quit X / framework) while solving
expect(store.game ~= nil and store.game.autosolved == true,
    "closing mid-solve saves the tainted partial board")
expect(mj2.board == nil and mj2.board_view == nil, "the closed instance is cleaned up")

local mj3 = Mahjong:new()
scheduled = {}
mj3:startGame()
expect(mj3.game_was_autosolved == true, "a tainted save restores tainted")
expect(scheduled[1] ~= nil and scheduled[1].delay == 0,
    "the reload schedules the resume on the next tick")
scheduled[1].fn() -- run the deferred resume
expect(mj3._auto_solve_active == true, "the solve RESUMES on reload (US-33)")
expect(Logic.tileCount(mj3.board) == 140, "the resumed solve immediately removed a pair")

local steps = drainScheduled()
expect(Logic.isWin(mj3.board), "the resumed solve clears the board")
expect(ctx.last_confirm ~= nil
        and ctx.last_confirm.text:find("You cleared the board", 1, true),
    "the resumed solve shows the win dialog")
expect(mj3.game_was_autosolved == true and mj3.game_won == false,
    "an auto-solved win records no win/streak")

-- ---- A pre-US-33 v2 save (no flag) restores clean, no resume --------------------

store.game = Logic.serializeGameState(Logic.newGame(5), {}, 0, nil, 0, 0, 0, "turtle")
local mj4 = Mahjong:new()
scheduled = {}
mj4:startGame()
expect(mj4.game_was_autosolved == false, "a pre-US-33 save restores clean")
expect(mj4._auto_solve_active == false, "no solve resumes on a clean reload")
expect(#scheduled == 0, "no resume/arm task was scheduled")

-- ---- All inputs are silent no-ops while the solver runs -------------------------

local mj5 = Mahjong:new()
mj5.board = Logic.newGame(7)
mj5:buildUILayout()
mj5.score = 0
startSolve(mj5)

local stack_before = #ctx.window_stack
mj5:pauseGame()
expect(mj5._auto_solve_active == true and mj5._pause_dlg == nil,
    "Pause is a no-op while the solver runs")
expect(#ctx.window_stack == stack_before, "Pause pushes no overlay")

mj5:openSettings()
expect(mj5._auto_solve_active == true, "Settings is a no-op while the solver runs")
expect(#ctx.window_stack == stack_before, "Settings pushes no dialog")

mj5:openStats()
expect(mj5._auto_solve_active == true, "Stats is a no-op while the solver runs")
expect(#ctx.window_stack == stack_before, "Stats pushes no dialog")

mj5:showLayoutPicker()
expect(mj5._auto_solve_active == true and mj5._picker_dlg == nil,
    "New Game is a no-op while the solver runs")
expect(#ctx.window_stack == stack_before, "the picker is not pushed")

mj5.status_bar.right_icon_tap_callback()
expect(mj5._auto_solve_active == true, "quit X is a no-op while the solver runs")
expect(#ctx.window_stack == stack_before, "quit X shows no exit ConfirmBox")

-- An arm attempt during a solve is also ignored (the flash keeps the solving msg).
scheduled = {} -- drop the pending step so the arm check is isolated
mj5.hint_button.hold_callback()
expect(#scheduled == 0, "a second hold during a solve arms nothing")
expect(mj5.flash_text.text == "Auto-solving…", "the solving message is preserved")

mj5:stopAutoSolve() -- clean up before the next checks
mj5:clearFlash()

if failures == 0 then
    print("\nALL US-33 AUTO-SOLVE LOCK CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
