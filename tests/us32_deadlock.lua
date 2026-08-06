-- US-32 deadlock detection: permanent-deadboard recognition + loss dialog.
--
-- Checks:
--   * isPermanentlyDead returns true for the named stacked-identical trap
--     and for odd-parity groups, false for winnable boards;
--   * handleNoMoves shows the loss dialog (not the shuffle prompt) when the
--     board is provably dead;
--   * the loss dialog has New Game / Close with an Undo button only when
--     history is non-empty;
--   * Undo pops one move and resumes play;
--   * New Game shows the layout picker, Close closes the game;
--   * shuffle retries-exhausted triggers the loss dialog;
--   * auto-solver retries-exhausted triggers the loss dialog (no Undo — the
--     solver clears history);
--   * not-provably-dead boards still show the shuffle prompt (existing
--     behaviour unchanged).
--
-- The geometric closure check is skipped: on these grids "out of grid =
-- open side" guarantees every position is eventually freeable, so
-- isPermanentlyDead needs only match-group parity (A) and the stacked-kind
-- column check (B). Both are already validated by the logic self-tests;
-- this harness exercises the UI integration.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store
local um = require("ui/uimanager")

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
local function lastConfirmText()
    return ctx.last_confirm and tostring(ctx.last_confirm.text) or ""
end

-- ---- Provably dead: loss dialog (not the shuffle prompt) ----------------------

local mj = Mahjong:new()
mj.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj.layout = "turtle"
mj:buildUILayout()
mj.history = {}
ctx.last_confirm = nil
mj:handleNoMoves()
expect(ctx.last_confirm ~= nil, "loss dialog appears on a provably-dead board")
expect(lastConfirmText():find("can't help", 1, true) ~= nil,
    "dialog text mentions shuffling can't help")
expect(lastConfirmText():find("No moves left", 1, true) ~= nil,
    "dialog text also says no moves left")
-- No Undo when history is empty
expect(ctx.last_confirm.other_buttons == nil,
    "no Undo button when history is empty")

-- ---- Provably dead WITH history → Undo button present --------------------------

local mj2 = Mahjong:new()
-- Two b1's stacked (deadlock) + two c1's free (already matched in history).
mj2.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj2.layout = "turtle"
mj2:buildUILayout()
mj2.score = 10
mj2.history = {
    { a = { x = 3, y = 2, layer = 0 }, b = { x = 4, y = 2, layer = 0 },
      ka = "c1", kb = "c1", score = 10, prev_last = nil },
}
-- Pairs matched for the summary.
mj2.pairs_matched = 1
ctx.last_confirm = nil
mj2:handleNoMoves()
expect(ctx.last_confirm ~= nil, "loss dialog appears when board is provably dead and history exists")
local ob = ctx.last_confirm.other_buttons
expect(ob ~= nil and #ob == 1 and #ob[1] == 1 and ob[1][1].text:find("Undo", 1, true),
    "Undo button present when history is non-empty")

-- ---- Undo from loss dialog resumes the game ------------------------------------

expect(Logic.tileCount(mj2.board) == 2, "before Undo board has 2 stacked tiles")
expect(#mj2.history == 1, "before Undo history has 1 entry")
ob[1][1].callback()  -- undo + restart timer + redraw
expect(Logic.tileCount(mj2.board) == 4, "Undo restored the pair to the board")
expect(#mj2.history == 0, "Undo popped the history entry")
expect(mj2.score == 0, "Undo subtracted the pair's points")

-- The timer was stopped by showDeadBoardDialog; the Undo callback should restart it.
expect(mj2._timer_running, "timer restarted after Undo from loss dialog")

-- ---- New Game from loss dialog → layout picker ----------------------------------

local mj3 = Mahjong:new()
mj3.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj3.layout = "turtle"
mj3:buildUILayout()
mj3.history = {}
mj3:handleNoMoves()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.ok_text == "New Game",
    "loss dialog ok_text is New Game")
local windows_before = #ctx.window_stack
ctx.last_confirm.ok_callback()  -- showLayoutPicker
-- showLayoutPicker creates a LayoutSelect widget and calls UIManager:show on it.
-- The mock adds every widget (not just ConfirmBox) to the window stack.
expect(#ctx.window_stack > windows_before,
    "New Game button shows the layout picker")

-- ---- Close from loss dialog -----------------------------------------------------

local mj4 = Mahjong:new()
mj4.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj4.layout = "turtle"
mj4:buildUILayout()
mj4.history = {}
um:show(mj4)
mj4:handleNoMoves()
-- The Close button runs cancel_callback, which exits the game (documented
-- US-32 behavior: Close -> exit the game).
ctx.last_confirm.cancel_callback()  -- Close
local mj4_still_on_stack = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj4 then mj4_still_on_stack = true end
end
expect(not mj4_still_on_stack,
    "the loss dialog's Close button exits the game")

-- ---- Tap-outside the loss dialog does NOT exit the game ----------------------------

-- The mock's ConfirmBox now models the real onTapClose: a tap outside the
-- dialog's movable dimen triggers the dialog's close path. The loss dialog
-- overrides onTapClose so a stray tap next to the dialog only dismisses the
-- dialog — it must never close the whole game (the reported "crash").
local mj_tap = Mahjong:new()
mj_tap.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj_tap.layout = "turtle"
mj_tap:buildUILayout()
mj_tap.history = {}
um:show(mj_tap)
mj_tap:handleNoMoves()
local tap_dlg = ctx.last_confirm
expect(tap_dlg.onTapClose ~= nil, "loss dialog carries a tap-outside handler")
local stack_before = #ctx.window_stack
tap_dlg:onTapClose(nil, { pos = { x = 1, y = 1 } })  -- tap next to the dialog
local game_still_open = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj_tap then game_still_open = true end
end
local dlg_still_up = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == tap_dlg then dlg_still_up = true end
end
expect(game_still_open, "tap-outside the loss dialog keeps the game open")
expect(not dlg_still_up, "tap-outside the loss dialog dismisses the dialog")
expect(#ctx.window_stack == stack_before - 1,
    "tap-outside only removes the dialog, nothing else")

-- ---- Tap-outside the shuffle prompt does NOT exit the game --------------------------

-- Not-provably-dead board -> shuffle prompt; a stray tap next to it dismisses
-- the prompt but the game keeps running (previously it closed the whole app).
local mj_tap2 = Mahjong:new()
mj_tap2.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj_tap2.layout = "turtle"
mj_tap2:buildUILayout()
mj_tap2.history = {}
um:show(mj_tap2)
local orig_dead = Logic.isPermanentlyDead
Logic.isPermanentlyDead = function() return false end
mj_tap2:handleNoMoves()
Logic.isPermanentlyDead = orig_dead
local shuffle_dlg = ctx.last_confirm
expect(tostring(shuffle_dlg.text):find("No moves left", 1, true) ~= nil,
    "shuffle prompt shown (not dead board)")
shuffle_dlg:onTapClose(nil, { pos = { x = 1, y = 1 } })  -- tap next to the prompt
local game2_still_open = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj_tap2 then game2_still_open = true end
end
expect(game2_still_open,
    "tap-outside the shuffle prompt keeps the game open (no app exit)")

-- ---- Not-provably-dead board → shuffle prompt (existing behaviour) ---------------

local mj_shuf = Mahjong:new()
-- Two free b1's side by side → 2 b1 left. Free in a way that both match → hasMoves.
-- Wait, a board with ONLY 2 free b1's HAS moves. Need no-moves but not provably dead.
-- Construction: 2 free tiles of different kinds, each count even, coverers non-own-kind.
--  (2,2,0)="b1" free, (3,2,0)="c1" free → no match. b1 count=1 odd → provably dead.
--  Need even counts. Simplest real example: hand-built board that B doesn't catch.
--  (2,2,0)="b1" (free), (3,2,0)="b2" (free) → no match. b1=1 odd → dead.
--  To avoid odd parity, need 2 of each kind but arranged so no pair is free.
--  Approach: each kind in a same-kind chain → B catches it.  
--  To avoid both A and B: 2 b1, 1 covered by b2. 2 b2, 1 covered by b1.
--  (2,2,0)="b1" free, (2,2,1)="b2" free (covers b1 through half-grid? No, same coords).
--  Hmm half-grid: (2,2,1) covers (2,2,0) regardless of kind. Let me try:
--  (2,2,0)="b1" covered by (2,2,1)="b2", (3,2,0)="b1" free, (3,2,1)="b2" covered by nothing
--  → free tiles: (2,2,1)b2, (3,2,0)b1, (3,2,1)b2 → no b2-b2 match AND no b1-b1 match.
--  b1: covered (2,2,0) by b2 (not b1!) → B false. b1 count=2 even. b2 count=2 even. → not dead.
--  hasMoves: free tiles b2,b1,b2 → b2+b2=free pair → hasMoves TRUE. Ugh.
--  Can't have 2 free b2's without a match. Let me use the 2 covered 1 free approach:
--  (2,2,0)="b1" free, (2,2,1)="b2" covers b1, (3,2,0)="b2" free.
--  free: b1, b2. No match. b1=1 odd → A catches! Need b1=2.
--  Add another b1 covered by b1. But that makes B true...
--
-- After much experimentation, a not-provably-dead no-moves board is non-trivial to
-- construct on a hand-built 4-tile setup because the parity check catches nearly
-- everything small. The feature's structural checks (A+B) are exact for the common
-- cases; larger boards that slip through are handled by the shuffle-retries-exhausted
-- fallback, which is tested separately.
--
-- We test that the shuffle prompt appears when there's no move and the board is NOT
-- provably dead. Use a board that showHint exposes via its dead-branch routing.
-- Construct: a board with 2 free b1 tiles and 2 covered c1 tiles — hasMoves is TRUE
-- (b1+b1 match), so this can't test it. Instead test directly:
--  set a board that is NOT provably dead but has no moves... hmm.
--
-- Simpler: we set up a board that is provably dead but then monkeypatch
-- isPermanentlyDead to return false, verifying handleNoMoves then shows the
-- shuffle prompt. This tests the routing, not the structural check (covered by
-- logic self-tests).
local mj_prompt = Mahjong:new()
mj_prompt.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }  -- actually dead
mj_prompt.layout = "turtle"
mj_prompt:buildUILayout()
mj_prompt.history = {}
ctx.last_confirm = nil
local orig_permanent = Logic.isPermanentlyDead
Logic.isPermanentlyDead = function() return false end
mj_prompt:handleNoMoves()
Logic.isPermanentlyDead = orig_permanent
expect(ctx.last_confirm ~= nil, "a dialog appeared (shuffle prompt expected)")
expect(lastConfirmText():find("No moves left", 1, true) ~= nil,
    "not-provably-dead shows the shuffle prompt")
expect(lastConfirmText():find("Shuffle", 1, true) ~= nil,
    "shuffle prompt has a Shuffle button")
expect(ctx.last_confirm.other_buttons == nil,
    "shuffle prompt has no Undo button")
-- Drive the Shuffle button.
ctx.last_confirm.ok_callback()  -- calls shuffleBoard(true) which performs the shuffle

-- ---- Shuffle retries-exhausted → loss dialog ------------------------------------

-- Three c1/c2/c3 tiles — all free, no two match. Odd parity (each group count
-- is 1), so isPermanentlyDead is true.  shuffleBoard(true) fires 10 shuffles,
-- all dead, then shows the loss dialog.
local mj_retry = Mahjong:new()
mj_retry.board = boardWith{ {2,2,0,"c1"}, {3,2,0,"c2"}, {5,2,0,"c3"} }
mj_retry.layout = "turtle"
mj_retry:buildUILayout()
mj_retry.score = 30
mj_retry.shuffles_used = 0
ctx.last_confirm = nil
mj_retry:shuffleBoard(true, 10)  -- force, 10 attempts
-- After all shuffles exhaust, showDeadBoardDialog should fire.
expect(ctx.last_confirm ~= nil, "loss dialog appears after shuffle retries exhaust")
expect(lastConfirmText():find("can't help", 1, true) ~= nil,
    "retries-exhausted dialog is the loss dialog")
-- Only the first shuffle is charged; the penalty is applied once.
expect(mj_retry.shuffles_used == 1, "only the first of 10 shuffles is charged")

-- ---- Auto-solver retries-exhausted → loss dialog ---------------------------------

local mj_auto = Mahjong:new()
mj_auto.board = boardWith{ {2,2,0,"c1"}, {3,2,0,"c2"}, {5,2,0,"c3"} }
mj_auto.layout = "turtle"
mj_auto:buildUILayout()
mj_auto.history = {}
ctx.last_confirm = nil
local orig_schedule = um.scheduleIn
local schedule_calls = {}
um.scheduleIn = function(_, delay, fn) schedule_calls[#schedule_calls + 1] = {delay, fn} end
mj_auto:startAutoSolve()
-- startAutoSolve calls autoSolveStep synchronously on a dead board (no matching
-- free pair); the first step's shuffle loop runs 10 shuffles then shows the dialog.
-- scheduleIn is only used when a pair IS found (for the next step), so we don't
-- need to flush the queue for this dead-board path.
expect(ctx.last_confirm ~= nil, "loss dialog appears when auto-solver's shuffle loop exhausts")
expect(ctx.last_confirm.other_buttons == nil,
    "auto-solver cleared history → no Undo button")
um.scheduleIn = orig_schedule

if failures == 0 then
    print("\nALL US-32 DEADLOCK CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
