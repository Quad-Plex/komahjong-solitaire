-- US-32 deadlock detection: permanent-deadboard recognition + loss dialog.
--
-- Checks:
--   * isPermanentlyDead returns true for the named stacked-identical trap
--     and for odd-parity groups, false for winnable boards;
--   * handleNoMoves shows the loss dialog (not the shuffle prompt) when the
--     board is provably dead;
--   * the loss dialog has Play again / Select Layout with an Undo button only when
--     history is non-empty;
--   * Undo pops one move and resumes play;
--   * Select Layout shows the layout picker;
--   * shuffle retries-exhausted triggers the loss dialog;
--   * auto-solver retries-exhausted triggers the loss dialog (no Undo — the
--     solver clears history);
--   * not-provably-dead boards still show the shuffle prompt (existing
--     behaviour unchanged);
--   * a reload of a saved 0-moves game that is NOT provably dead (a stacked
--     pair with other free positions) offers the shuffle again, and the
--     in-game no-moves path does the same (regression: the old stacked-kind
--     check wrongly sent these to the loss dialog).
--   * the no-moves shuffle evaluates 15 candidates asynchronously and commits
--     the candidate with the most available matching free pairs.
--   * an ordinary confirmed shuffle defers its board rebuild until after the
--     ConfirmBox has closed, avoiding a covered-window repaint race.
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

-- ---- Play again from loss dialog keeps the current layout ------------------------

local mj3 = Mahjong:new()
mj3.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj3.layout = "turtle"
mj3:buildUILayout()
mj3.history = {}
mj3:handleNoMoves()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.ok_text == "Play again",
    "loss dialog ok_text is Play again")
ctx.last_confirm.ok_callback()  -- startGameWithLayout
local picker_open = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget ~= nil and e.widget.name == "mahjonglayoutselect" then
        picker_open = true
    end
end
expect(not picker_open,
    "Play again does not open the layout picker")
expect(Logic.tileCount(mj3.board) == 144 and mj3.layout == "turtle",
    "Play again starts a fresh game on the current layout")

-- ---- Select Layout from loss dialog → layout picker ------------------------------

local mj4 = Mahjong:new()
mj4.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj4.layout = "turtle"
mj4:buildUILayout()
mj4.history = {}
um:show(mj4)
mj4:handleNoMoves()
expect(ctx.last_confirm.cancel_text == "Select Layout",
    "loss dialog cancel_text is Select Layout")
ctx.last_confirm.cancel_callback()  -- Select Layout
local picker4 = ctx.window_stack[#ctx.window_stack].widget
expect(picker4 ~= nil and picker4.name == "mahjonglayoutselect",
    "Select Layout opens the layout picker")
picker4:closeDialog()

-- ---- Tap-outside the loss dialog does NOT exit the game ----------------------------

-- The mock's ConfirmBox now models the real onTapClose: a tap outside the
-- dialog's movable dimen triggers the dialog's close path. The loss dialog
-- overrides onTapClose so a stray tap next to the dialog does NOTHING — the
-- dialog stays open, and only its buttons act — it must
-- never close the whole game (the reported "crash").
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
expect(dlg_still_up, "tap-outside the loss dialog keeps the dialog open")
expect(#ctx.window_stack == stack_before,
    "tap-outside leaves the dialog + game untouched")

-- ---- Tap-outside the shuffle prompt does NOT exit the game --------------------------

-- Not-provably-dead board -> shuffle prompt; a stray tap next to it keeps the
-- prompt up (the game remains open and the clock stays paused).
local mj_tap2 = Mahjong:new()
mj_tap2.board = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"} }
mj_tap2.layout = "turtle"
mj_tap2:buildUILayout()
mj_tap2.history = {}
mj_tap2:startTimer()
um:show(mj_tap2)
local orig_dead = Logic.isPermanentlyDead
Logic.isPermanentlyDead = function() return false end
mj_tap2:handleNoMoves()
Logic.isPermanentlyDead = orig_dead
local shuffle_dlg = ctx.last_confirm
expect(not mj_tap2._timer_running,
    "shuffle prompt pauses the timer")
expect(tostring(shuffle_dlg.text):find("No moves left", 1, true) ~= nil,
    "shuffle prompt shown (not dead board)")
expect(tostring(shuffle_dlg.text):find("-10 Score", 1, true) ~= nil,
    "shuffle prompt shows its score penalty")
shuffle_dlg:onTapClose(nil, { pos = { x = 1, y = 1 } })  -- tap next to the prompt
local game2_still_open = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj_tap2 then game2_still_open = true end
end
expect(game2_still_open,
    "tap-outside the shuffle prompt keeps the game open (no app exit)")
local shuffle_still_up = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == shuffle_dlg then shuffle_still_up = true end
end
expect(shuffle_still_up,
    "tap-outside the shuffle prompt keeps the prompt open")
shuffle_dlg.cancel_callback()
expect(not mj_tap2._timer_running,
    "closing the shuffle prompt leaves the timer stopped")

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

-- ---- Reload of a saved 0-moves game must offer the shuffle -------------------
--
-- Regression: a board that is dead (no move) but NOT permanently dead must
-- show the shuffle prompt again on reload. The old stacked-kind check wrongly
-- flagged a stacked identical pair with other free positions as permanently
-- dead, so reloading such a saved game showed the loss dialog ("shuffling
-- can't help") instead of the shuffle prompt.
--
-- Board (all real turtle positions): two identical tiles stacked in one
-- column plus another kind stacked beside it — exactly one free tile of each
-- kind, so no match exists, even parity, and a shuffle can separate the pair.
local reload_board = {}
for _, t in ipairs{
    {4,2,0,"b1"}, {4,2,1,"b1"},
    {5,2,0,"c1"}, {5,2,1,"c1"},
} do
    reload_board[pk(t[1], t[2], t[3])] = t[4]
end
expect(not Logic.hasMoves(reload_board), "the saved board has no moves")
expect(Logic.tileCount(reload_board) == 4, "saved board holds 4 tiles")
expect(not Logic.isPermanentlyDead(reload_board),
    "stacked pair + other free tiles is NOT provably dead (a shuffle can fix it)")

-- Pad history to a valid save (n + 2 * #history == 144). US-52 validates the
-- whole deck multiset, so use every tile not already on the four-tile board.
local reload_history = {}
local used_keys = {}
for key in pairs(reload_board) do used_keys[key] = true end
local positions = {}
for _, p in ipairs(Logic.buildLayout("turtle")) do
    if not used_keys[pk(p.x, p.y, p.layer)] then positions[#positions + 1] = p end
end
local remaining, skipped = {}, { b1 = 0, c1 = 0 }
for _, kind in ipairs(Logic.createDeck()) do
    if skipped[kind] and skipped[kind] < 2 then
        skipped[kind] = skipped[kind] + 1
    else
        remaining[#remaining + 1] = kind
    end
end
for i = 1, #remaining, 2 do
    local match_at
    for j = i + 1, #remaining do
        if Logic.matches(remaining[i], remaining[j]) then match_at = j break end
    end
    remaining[i + 1], remaining[match_at] = remaining[match_at], remaining[i + 1]
    local a, b = positions[i], positions[i + 1]
    reload_history[#reload_history + 1] = {
        a = { x = a.x, y = a.y, layer = a.layer },
        b = { x = b.x, y = b.y, layer = b.layer },
        ka = remaining[i], kb = remaining[i + 1], score = 10, prev_last = nil,
    }
end
expect(4 + 2 * #reload_history == 144, "the reload save is a valid 144-tile state")

local mj_save = Mahjong:new()
mj_save.board = reload_board
mj_save.layout = "turtle"
mj_save.history = reload_history
mj_save.score = 0
mj_save.hints_used = 0
mj_save.shuffles_used = 0
mj_save:saveGameState()

-- Reload in a fresh instance: startGame must restore the game and offer a
-- shuffle, NOT show the loss dialog.
local mj_reload = Mahjong:new()
ctx.last_confirm = nil
mj_reload:startGame()
expect(ctx.last_confirm ~= nil, "reload of a 0-moves game shows a dialog")
expect(lastConfirmText():find("Shuffle the board", 1, true) ~= nil,
    "reload prompts to shuffle (not the loss dialog)")
expect(lastConfirmText():find("can't help", 1, true) == nil,
    "reload does NOT claim shuffling can't help")
local reload_game_shown = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget and e.widget.name == "mahjong" then reload_game_shown = true end
end
expect(reload_game_shown, "reload restored the game itself (not the layout picker)")

-- The same board reached in-game (checkGameState) also offers the shuffle.
local mj_ingame = Mahjong:new()
mj_ingame.board = {}
for key, kind in pairs(reload_board) do mj_ingame.board[key] = kind end
mj_ingame.layout = "turtle"
mj_ingame:buildUILayout()
mj_ingame.history = {}
ctx.last_confirm = nil
mj_ingame:handleNoMoves()
expect(ctx.last_confirm ~= nil
        and lastConfirmText():find("Shuffle the board", 1, true) ~= nil,
    "in-game no-moves on a fixable board also offers the shuffle")

-- ---- Dead-board shuffle picks the best of 15 background candidates ------------

local mj_best = Mahjong:new()
mj_best.board = boardWith{
    {4,2,0,"b1"}, {4,2,1,"b1"},
    {5,2,0,"c1"}, {5,2,1,"c1"},
}
mj_best.layout = "turtle"
mj_best:buildUILayout()
mj_best.shuffles_used = 0
local before_best = {}
for key, kind in pairs(mj_best.board) do before_best[key] = kind end

local scheduled_best = {}
local original_schedule = um.scheduleIn
um.scheduleIn = function(_, seconds, fn)
    scheduled_best[#scheduled_best + 1] = { seconds = seconds, fn = fn }
end
local original_shuffle = Logic.shuffleBoard
local candidate_count = 0
Logic.shuffleBoard = function(board)
    candidate_count = candidate_count + 1
    -- Candidate 2 puts the matching pair on the two free top tiles; all other
    -- candidates remain dead, making the expected winner unambiguous.
    if candidate_count == 2 then
        board[pk(4,2,1)] = "b1"
        board[pk(5,2,1)] = "b1"
        board[pk(4,2,0)] = "c1"
        board[pk(5,2,0)] = "c1"
    end
    return board
end

mj_best:shuffleBoard(true, 0, true, true)
expect(candidate_count == 0 and before_best[pk(4,2,1)] == mj_best.board[pk(4,2,1)],
    "dead-board candidate search starts in the background")
for _ = 1, 15 do
    local task = table.remove(scheduled_best, 1)
    if task then task.fn() end
end
expect(candidate_count == 15, "dead-board shuffle evaluates exactly 15 candidates")
expect(Logic.hasMoves(mj_best.board), "dead-board shuffle commits the candidate with most moves")
expect(mj_best.shuffles_used == 1, "best-of-15 shuffle charges one penalty")
Logic.shuffleBoard = original_shuffle
um.scheduleIn = original_schedule

-- ---- Confirmed ordinary shuffle rebuilds after the dialog closes -------------

local mj_confirm = Mahjong:new()
mj_confirm.board = Logic.newGame("turtle", 42)
mj_confirm.layout = "turtle"
mj_confirm:buildUILayout()
mj_confirm:shuffleBoard()
local ordinary_dlg = ctx.last_confirm
local scheduled_before = #ctx.scheduled
ordinary_dlg.ok_callback()
expect(#ctx.scheduled > scheduled_before,
    "confirmed ordinary shuffle defers its board rebuild")
ctx.runScheduled()
ctx.runScheduled()
local rendered_faces = 0
for _ in pairs(mj_confirm.board_view and mj_confirm.board_view.tile_widgets or {}) do
    rendered_faces = rendered_faces + 1
end
expect(mj_confirm.board_view and rendered_faces == 144
        and #mj_confirm.board_view.overlap > rendered_faces,
    "deferred ordinary shuffle leaves a complete rendered board")

if failures == 0 then
    print("\nALL US-32 DEADLOCK CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
