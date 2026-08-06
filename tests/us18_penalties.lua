-- US-18 hint/shuffle-penalty suite: hints and reshuffles cost points.
--
-- Checks:
--   * HINT_PENALTY / SHUFFLE_PENALTY constants and applyPenalty flooring at 0;
--   * a hint deducts HINT_PENALTY once per hint session (cycling presses within
--     the same session are free until a pair is cleared), and increments
--     hints_used;
--   * the dead-board shuffle offer (no matching free pair) is not a hint and
--     charges nothing;
--   * a user-initiated shuffle deducts SHUFFLE_PENALTY once and increments
--     shuffles_used;
--   * the bounded auto-repeat re-shuffles that guarantee a playable board do
--     NOT re-charge (a board that can never pair still charges once);
--   * undo restores only the pair's points — a penalty is never refunded, and
--     the score is floored at 0;
--   * the hints_used / shuffles_used counters survive a save/restore.

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

-- ---- Pure logic: constants + applyPenalty floors at 0 ------------------------

expect(Logic.HINT_PENALTY == 5, "hint penalty is 5")
expect(Logic.SHUFFLE_PENALTY == 10, "shuffle penalty is 10")
expect(Logic.applyPenalty(100, Logic.HINT_PENALTY) == 95,
    "applyPenalty subtracts the hint penalty")
expect(Logic.applyPenalty(3, 5) == 0, "applyPenalty floors at 0")
expect(Logic.applyPenalty(0, 10) == 0, "applyPenalty(0, n) stays 0")
expect(Logic.applyPenalty(5, 10) == 0, "applyPenalty never goes negative")

-- ---- A real hint deducts once and increments hints_used -----------------------

local mj = Mahjong:new()
mj.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj:buildUILayout()
mj.score = 30
mj.hints_used = 0
mj.shuffles_used = 0
mj:showHint()
expect(mj.score == 25 and mj.hints_used == 1,
    "a hint shown costs HINT_PENALTY and increments hints_used")
expect(store.game ~= nil and store.game.hints == 1,
    "a hint penalty is persisted via the existing score save")

-- US-20: cycling through the hints re-charges nothing until a pair is cleared —
-- the penalty is paid once per hint session, not once per press.
mj:showHint() -- cycle to the next matching pair
mj:showHint() -- and again
expect(mj.score == 25 and mj.hints_used == 1,
    "cycling hints within the same session re-charges nothing")

-- Clearing a pair ends the session: the next hint press starts a fresh one and
-- pays HINT_PENALTY once (then its cycling presses are free again).
mj:handleTileTap(2, 2, 0)
mj:handleTileTap(4, 2, 0) -- match the b1/b1 pair (+10 -> 35)
mj:showHint()             -- fresh session: -5 -> 30
expect(mj.score == 30 and mj.hints_used == 2,
    "after a pair is cleared the next hint charges HINT_PENALTY once")
mj:showHint()             -- cycle in the fresh session: free
expect(mj.score == 30 and mj.hints_used == 2,
    "cycling in a fresh session re-charges nothing either")

-- ---- The dead-board shuffle offer is NOT a hint -------------------------------

local mj_dead = Mahjong:new()
mj_dead.board = boardWith{
    {2,2,0,"c1"}, {4,2,0,"c2"}, {6,2,0,"c3"},
}
mj_dead:buildUILayout()
mj_dead.score = 40
mj_dead.hints_used = 0
mj_dead:showHint()
expect(ctx.last_confirm ~= nil
        and tostring(ctx.last_confirm.text):find("No moves left", 1, true) ~= nil,
    "a hint on a dead board offers a shuffle instead of highlighting a pair")
expect(mj_dead.score == 40 and mj_dead.hints_used == 0,
    "the dead-board shuffle offer is not a hint and charges nothing")

-- ---- A user-initiated shuffle deducts once ------------------------------------

local mj_shuf = Mahjong:new()
mj_shuf.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj_shuf:buildUILayout()
mj_shuf.score = 50
mj_shuf.shuffles_used = 0
mj_shuf:shuffleBoard(true) -- force (no confirm box)
expect(mj_shuf.score == 40 and mj_shuf.shuffles_used == 1,
    "a user-initiated shuffle costs SHUFFLE_PENALTY once")
expect(store.game ~= nil and store.game.shuffles == 1,
    "the shuffle penalty is persisted with the game state")

-- The provably-dead board shows the loss dialog (US-32) — no shuffle
-- prompt is offered, so no shuffle penalty is charged. Instead the dialog
-- has an Undo button.
local mj_prompt = Mahjong:new()
mj_prompt.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c2"}, -- after the pair, c1/c2 odd parity → provably dead
}
mj_prompt:buildUILayout()
mj_prompt.score = 20
mj_prompt.shuffles_used = 0
mj_prompt:handleTileTap(2, 2, 0)
mj_prompt:handleTileTap(4, 2, 0) -- dead board -> checkGameState shows the loss dialog
expect(ctx.last_confirm ~= nil
        and tostring(ctx.last_confirm.text):find("can't help", 1, true) ~= nil,
    "a provably-dead board shows the loss dialog (not the shuffle prompt)")
expect(mj_prompt.score == 30, "the pair scored 10 points; no shuffle penalty was charged")
expect(mj_prompt.shuffles_used == 0,
    "a provably-dead board skips the shuffle offer → no shuffle charge")

-- ---- Auto-repeat re-shuffles do NOT re-charge ----------------------------------

-- A c1/c2/c3 board can never produce a move, so every shuffle is dead and the
-- bounded auto-repeat kicks in — but only the FIRST (user-initiated) shuffle
-- is charged.
local mj_rep = Mahjong:new()
mj_rep.board = boardWith{
    {2,2,0,"c1"}, {4,2,0,"c2"}, {6,2,0,"c3"},
}
mj_rep:buildUILayout()
mj_rep.score = 40
mj_rep.shuffles_used = 0
local hasmoves_before = Logic.hasMoves(mj_rep.board)
mj_rep:shuffleBoard(true)
expect(not hasmoves_before, "the c1/c2/c3 board starts with no moves")
expect(mj_rep.score == 30 and mj_rep.shuffles_used == 1,
    "auto-repeat re-shuffles do not re-charge (charged exactly once)")

-- ---- Undo restores only the pair's points, never a penalty --------------------

-- pair (10) then hint (5): undoing the pair leaves the penalty applied.
local mj_u = Mahjong:new()
mj_u.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj_u:buildUILayout()
mj_u.score = 0
mj_u.hints_used = 0
mj_u:handleTileTap(2, 2, 0)
mj_u:handleTileTap(4, 2, 0) -- +10 -> 10
mj_u:showHint()             -- -5  -> 5
mj_u:undo()
expect(Logic.tileCount(mj_u.board) == 4, "undo restored the pair's tiles")
expect(mj_u.score == 0 and mj_u.hints_used == 1,
    "undo subtracts the pair's points but never refunds the hint penalty")

-- A penalty applied right after a pair cannot push the restored score negative.
local mj_neg = Mahjong:new()
mj_neg.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj_neg:buildUILayout()
mj_neg.score = 0
mj_neg.hints_used = 0
mj_neg:handleTileTap(2, 2, 0)
mj_neg:handleTileTap(4, 2, 0) -- +10 -> 10
mj_neg:showHint()             -- -5  -> 5
mj_neg:handleTileTap(6, 2, 0) -- select
mj_neg:handleTileTap(8, 2, 0) -- +10 -> 15
mj_neg:undo()                 -- -10 -> 5
mj_neg:undo()                 -- -10 -> 0 (floored, not -5)
expect(mj_neg.score == 0 and Logic.tileCount(mj_neg.board) == 4,
    "undoing a pair after a penalty floors the score at 0 (never negative)")

-- ---- The counters survive a save/restore --------------------------------------

-- deserializeGameState validates a REAL game (board + 2*history == 144), so
-- build a genuine mid-game state on a full board: play one pair, use a hint,
-- save, and restore it in a fresh instance.
local mj_full = Mahjong:new()
mj_full.board = Logic.newGame(7)
mj_full:buildUILayout()
local free = Logic.freeTiles(mj_full.board)
local a, b
for i = 1, #free - 1 do
    for j = i + 1, #free do
        if Logic.matches(free[i].kind, free[j].kind) then
            a, b = free[i], free[j]
            break
        end
    end
    if a then break end
end
expect(a ~= nil, "the seeded board has a playable first pair")
mj_full:handleTileTap(a.x, a.y, a.layer)
mj_full:handleTileTap(b.x, b.y, b.layer)
mj_full:showHint() -- hints_used = 1, score now pair + 10 then -5
expect(mj_full.hints_used == 1, "a hint used on the real board increments hints_used")
expect(store.game ~= nil and store.game.hints == 1,
    "the saved real game carries hints_used")

local mj_r = Mahjong:new()
mj_r:startGame()
expect(mj_r.hints_used == 1, "a restored game brings hints_used back")
expect(mj_r.shuffles_used == 0, "a restored game brings shuffles_used back")

-- A fresh (no saved) game starts the counters at 0.
store.game = nil
local mj_fresh = Mahjong:new()
mj_fresh:startGame()
expect(mj_fresh.hints_used == 0 and mj_fresh.shuffles_used == 0,
    "a fresh deal starts both help counters at 0")

-- Reset (New Game) zeroes the counters too.
mj_r:shuffleBoard(true)
mj_r:showHint()
expect(mj_r.hints_used == 2 and mj_r.shuffles_used == 1,
    "help counters accumulate across interactions")
mj_r:resetGame()
expect(mj_r.hints_used == 0 and mj_r.shuffles_used == 0,
    "a New Game resets the help counters")

if failures == 0 then
    print("\nALL US-18 PENALTY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
