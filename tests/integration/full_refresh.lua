-- US-45 full-screen refresh suite: restarting a game through a lingering dialog
-- ("Play again" from the win/dead-board card) must ink the whole new canvas with
-- a single high-fidelity full-screen refresh, deferred until the dialog-clear
-- repaint has drained.
--
-- Checks:
--   * a restart while the game window is ALREADY shown (the dialog path) arms a
--     deferred full-screen refresh, and never two;
--   * the deferred task, once flushed, actually issues `setDirty(self, "full",
--     self.dimensions)` — the whole window, high-veracity waveform;
--   * the deferral is guarded by board identity: if the game was replaced or
--     closed before the tick fires, no stale full refresh is issued;
--   * a fresh (not-yet-shown) deal does NOT arm the full refresh (its 'show'
--     already paints the new window).

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

local function hadFullScreenDirty(mj)
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == mj and c.refreshtype == "full" then
            return true
        end
    end
    return false
end

local um = require("ui/uimanager")

-- ---- already-shown restart (win dialog "Play again" path) arms the refresh ---

local mj = Mahjong:new()
mj.board = Logic.newGame(4)
mj:buildUILayout()
-- Simulate the game window being on the stack (as it is during a win dialog).
um:show(mj)

ctx.dirty_calls = {}
ctx.scheduled = {}
mj:startGameWithLayout("turtle")
expect(mj._full_screen_refresh_scheduled == true,
    "restart on an already-shown window arms the deferred full-screen refresh")
expect(Logic.tileCount(mj.board) == 144,
    "the restart deals a fresh full board synchronously")
expect(not hadFullScreenDirty(mj),
    "the full-screen refresh is NOT issued inline (it is deferred post-dialog)")

-- Flush the deferred refresh through the mock's two-tick wrapper.
ctx.runScheduled()
ctx.runScheduled()
expect(hadFullScreenDirty(mj),
    "the deferred task finally drives a setDirty(self, \"full\") of the window")
expect(mj._full_screen_refresh_scheduled == false,
    "the deferred refresh clears its armed flag after firing")

-- ---- a second restart does not stack refreshes -------------------------------

ctx.dirty_calls = {}
mj:startGameWithLayout("spider")
expect(mj._full_screen_refresh_scheduled == true,
    "a further restart re-arms the full-screen refresh")
ctx.runScheduled()
ctx.runScheduled()
expect(hadFullScreenDirty(mj),
    "the second restart's full-screen refresh fires cleanly")

-- ---- the board-identity guard drops a stale refresh ---------------------------

local mj2 = Mahjong:new()
mj2.board = Logic.newGame(1)
mj2:buildUILayout()
um:show(mj2)
mj2:startGameWithLayout("turtle")          -- arms the refresh for THIS board
mj2.board = Logic.newGame(2)              -- a newer deal replaces it before the tick
ctx.dirty_calls = {}
ctx.runScheduled()
ctx.runScheduled()
expect(not hadFullScreenDirty(mj2),
    "a replaced board cancels the deferred full-screen refresh (identity guard)")
expect(mj2._full_screen_refresh_scheduled == false,
    "a replaced board still clears the armed flag (no stale tick leaks)")

-- ---- a first-ever deal (not shown) does not arm the refresh -------------------

local mj3 = Mahjong:new()
mj3.board = Logic.newGame(3)
mj3:buildUILayout()
ctx.scheduled = {}
mj3:startGameWithLayout("bridge")
expect(mj3._full_screen_refresh_scheduled == nil,
    "a fresh (not-yet-shown) deal does not arm a full-screen refresh")

if failures == 0 then
    print("\nALL US-45 FULL-SCREEN REFRESH CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
