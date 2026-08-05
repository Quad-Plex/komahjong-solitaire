-- US-19 auto-solve suite: the Hint button's long-press solver.
--
-- KOReader's Button fires `hold_callback` ~0.5 s after contact (the global
-- ges_hold_interval_ms), so the ~10 s hold is implemented as: the hold callback
-- ARMS a 10 s timer and the release hook DISARMS it if the finger lifts early.
-- Checks:
--   * the Hint button is a LongPressButton wiring armAutoSolve/disarmAutoSolve;
--   * a hold alone arms a 10 s timer and shows "Keep holding…" but does NOT
--     start the solve;
--   * releasing before the 10 s cancels the arm (the timer is a no-op);
--   * firing the arm starts the solve and the solver removes one pair per step
--     until the board is cleared, then shows the win dialog;
--   * the solver scores and records history like a hand-played game;
--   * a board tap / a short Hint tap / Undo stop the solve (a pending step is
--     a no-op afterwards);
--   * holding with the hints setting off arms nothing;
--   * the flash refactor keeps flashMessage working across a cleared band.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store
local um = require("ui/uimanager")
local scheduled = {}
um.scheduleIn = function(_, delay, fn) scheduled[#scheduled + 1] = { delay, fn } end

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

-- ---- Hold arms, release before 10 s cancels -------------------------------------

local mj = Mahjong:new()
mj.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj:buildUILayout()
mj.score = 0
scheduled = {}

expect(mj.hint_button ~= nil and mj.hint_button.hold_callback ~= nil
        and mj.hint_button.hold_release_callback ~= nil,
    "the Hint button wires the long-press arm/release hooks")
mj.hint_button.hold_callback()
expect(mj._auto_solve_active == false, "a hold alone does NOT start the solve")
expect(mj.flash_text.text == "Keep holding to auto-solve…",
    "the arm shows a keep-holding message in the band")
expect(#scheduled == 1 and scheduled[1][1] == 10,
    "the arm schedules a single 10 s timer")
local arm_fn = scheduled[1][2]
scheduled = {}

mj.hint_button.hold_release_callback()
arm_fn()
expect(mj._auto_solve_active == false, "releasing early cancels the arm (timer is a no-op)")
expect(Logic.tileCount(mj.board) == 4, "no pair was removed by a cancelled arm")
expect(mj.flash_text.text == "", "releasing early clears the keep-holding message")

-- ---- Firing the arm starts the solve; it clears the whole board -------------------

local mj2 = Mahjong:new()
mj2.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
    {2,4,0,"d1"}, {4,4,0,"d1"},
}
mj2:buildUILayout()
mj2.score = 0
scheduled = {}
mj2.hint_button.hold_callback()
local arm2 = scheduled[1][2]
scheduled = {}

arm2()
expect(mj2._auto_solve_active == true, "firing the arm starts the auto-solver")
expect(mj2.flash_text.text == "Auto-solving…", "the solve shows an auto-solving message")
expect(Logic.tileCount(mj2.board) == 4, "the first step removed one pair immediately")

local guard = 0
while scheduled[1] and guard < 200 do
    local e = table.remove(scheduled, 1)
    e[2]()
    guard = guard + 1
end
expect(Logic.isWin(mj2.board), "auto-solve clears the entire board")
expect(guard == 2, "the remaining two pairs were removed one per step")
expect(mj2.score == 30, "auto-solve scores 10 per pair (chain bonus off on a fresh board)")
expect(#mj2.history == 3, "auto-solve records history for undo")
expect(ctx.last_confirm ~= nil
        and ctx.last_confirm.text:find("You cleared the board", 1, true),
    "a cleared board shows the win dialog")
expect(mj2.flash_text.text == "", "the solve clears the band before the win dialog")

-- ---- A board tap cancels a running solve -----------------------------------------

local mj3 = Mahjong:new()
mj3.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj3:buildUILayout()
mj3.score = 0
scheduled = {}
mj3.hint_button.hold_callback()
local arm3 = scheduled[1][2]
scheduled = {}
arm3()
expect(mj3._auto_solve_active == true, "solve running after the first step")
expect(Logic.tileCount(mj3.board) == 2, "first step removed one pair")
local frees = Logic.freeTiles(mj3.board)
mj3:handleTileTap(frees[1].x, frees[1].y, frees[1].layer)
expect(mj3._auto_solve_active == false, "a board tap interrupts the solve")
expect(mj3.flash_text.text == "", "interrupting clears the auto-solving message")
if scheduled[1] then
    scheduled[1][2]() -- the pending step must be a no-op now
end
expect(Logic.tileCount(mj3.board) == 2, "a pending step after cancel removes nothing")

-- ---- A short Hint tap also stops the solve ---------------------------------------

local mj4 = Mahjong:new()
mj4.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj4:buildUILayout()
mj4.score = 0
scheduled = {}
mj4.hint_button.hold_callback()
local arm4 = scheduled[1][2]
scheduled = {}
arm4()
expect(mj4._auto_solve_active == true, "solve running")
mj4:showHint()
expect(mj4._auto_solve_active == false, "a short Hint tap stops the solve")

-- ---- Undo during a solve stops it and restores the last pair ----------------------

local mj5 = Mahjong:new()
mj5.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj5:buildUILayout()
mj5.score = 0
scheduled = {}
mj5.hint_button.hold_callback()
local arm5 = scheduled[1][2]
scheduled = {}
arm5()
expect(mj5._auto_solve_active == true, "solve running")
expect(Logic.tileCount(mj5.board) == 2, "one pair solved")
mj5:undo()
expect(mj5._auto_solve_active == false, "Undo stops the solve")
expect(Logic.tileCount(mj5.board) == 4, "Undo restored the solved pair")
expect(#mj5.history == 0, "Undo consumed the auto-solve history entry")

-- ---- hints off: holding arms nothing ----------------------------------------------

store.hints = false
local mj6 = Mahjong:new()
mj6.board = Logic.newGame(3)
mj6:buildUILayout()
scheduled = {}
mj6.hint_button.hold_callback()
expect(#scheduled == 0, "holding with hints disabled arms nothing")
store.hints = nil

-- ---- flashMessage still works across a cleared band (US-09 refactor) --------------

local mj7 = Mahjong:new()
mj7.board = Logic.newGame(3)
mj7:buildUILayout()
scheduled = {}
mj7:flashMessage("Tile is blocked")
mj7:clearFlash()          -- the auto-clear path
mj7:flashMessage("Tile is blocked") -- must NOT crash on the nil token bug
expect(mj7.flash_text.text == "Tile is blocked", "a second flash after a cleared band works")

if failures == 0 then
    print("\nALL US-19 AUTO-SOLVE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
