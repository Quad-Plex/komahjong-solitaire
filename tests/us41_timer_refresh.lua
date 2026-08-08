-- US-41 timer-refresh suite: the mm:ss has EXACTLY ONE regional repaint source
-- per timer_update mode, and the periodic tick defers while a structural board
-- refresh retry is pending.
--
-- Checks:
--   * "interval" mode: an interaction (select / match) updates the mm:ss TEXT
--     but does NOT enqueue a timer-region repaint — the periodic polling loop
--     is the only regional refresh source, so the timer refill can never be
--     enqueued into the same framebuffer batch as a board mutation (that race
--     used to leave the board half-rendered on e-ink).
--   * "interval" mode: the periodic tick DOES repaint the timer region, and
--     reschedules with the configured interval.
--   * "move" mode: the same interactions DO enqueue a timer-region repaint.
--   * "interval" mode: while a structural pair refresh retry is pending, the
--     periodic tick defers (reschedules without repainting) instead of racing
--     a second region into the same batch.

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

-- True if any recorded dirty call repainted the game's timer region (the
-- feedback-band slot the mm:ss occupies).
local function timerRegionDirty(mj)
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == mj and c.region == mj.timer_region then
            return true
        end
    end
    return false
end

-- ---- "interval" mode: interactions never repaint the timer region -------------

store.timer_update = nil
store.timer_interval = nil
local mj_i = Mahjong:new()
mj_i.board = Logic.newGame(3)
mj_i:buildUILayout()
mj_i.elapsed_base = 65
local ai, bi = firstFreePair(mj_i.board)

ctx.dirty_calls = {}
mj_i:handleTileTap(ai.x, ai.y, ai.layer)
expect(mj_i.timer_text.text == "01:05", "interval: select updates the mm:ss text")
expect(not timerRegionDirty(mj_i),
    "interval: select does NOT enqueue a timer-region repaint")

ctx.dirty_calls = {}
mj_i:handleTileTap(bi.x, bi.y, bi.layer)
expect(mj_i.timer_text.text == "01:05", "interval: match updates the mm:ss text")
expect(not timerRegionDirty(mj_i),
    "interval: match does NOT enqueue a timer-region repaint")
-- The match queued a structural refresh retry (the mock's tickAfterNext is a
-- two-tick wrapper); flush both so the board's pending-flag clears before the
-- periodic tick is exercised below.
ctx.runScheduled()
ctx.runScheduled()

-- ---- "interval" mode: the periodic tick IS the repaint source -----------------

local nt_before = #next_ticks
mj_i:startTimer()
expect(#next_ticks == nt_before + 1, "interval: startTimer arms the polling loop")
scheduled = {}
ctx.dirty_calls = {}
next_ticks[#next_ticks]()
expect(timerRegionDirty(mj_i),
    "interval: the periodic tick repaints the timer region")
expect(scheduled[1] and scheduled[1][1] == 5,
    "interval: the tick reschedules with the configured interval")

-- ---- "move" mode: interactions DO repaint the timer region --------------------

store.timer_update = "move"
local mj_m = Mahjong:new()
mj_m.board = Logic.newGame(7)
mj_m:buildUILayout()
mj_m.elapsed_base = 65
local am, bm = firstFreePair(mj_m.board)

ctx.dirty_calls = {}
mj_m:handleTileTap(am.x, am.y, am.layer)
expect(mj_m.timer_text.text == "01:05", "move: select updates the mm:ss text")
expect(timerRegionDirty(mj_m),
    "move: select enqueues a timer-region repaint")

ctx.dirty_calls = {}
mj_m:handleTileTap(bm.x, bm.y, bm.layer)
expect(timerRegionDirty(mj_m),
    "move: match enqueues a timer-region repaint")

-- ---- interval tick defers while a structural refresh retry is pending ---------

store.timer_update = "interval"
store.timer_interval = 5
local mj_d = Mahjong:new()
mj_d.board = Logic.newGame(11)
mj_d:buildUILayout()
mj_d:startTimer()
local tick_d = next_ticks[#next_ticks]
expect(type(tick_d) == "function", "interval: the periodic tick is captured")

-- Simulate a pair clear whose structural refresh retry is still queued
-- (queueStructuralRefreshRetry has set the board's flag but the deferred
-- re-request has not run yet).
mj_d.board_view._refresh_retry_scheduled = true
scheduled = {}
ctx.dirty_calls = {}
tick_d()
expect(not timerRegionDirty(mj_d),
    "interval: the tick defers the timer repaint while a structural retry is pending")
expect(#scheduled == 1,
    "interval: a deferred tick reschedules instead of repainting")

-- Once the structural refresh has run, the next tick repaints normally.
mj_d.board_view._refresh_retry_scheduled = false
scheduled = {}
ctx.dirty_calls = {}
tick_d()
expect(timerRegionDirty(mj_d),
    "interval: the tick repaints once the structural retry has cleared")

if failures == 0 then
    print("\nALL US-41 TIMER REFRESH CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
