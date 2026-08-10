-- Hint/combo + empty-board-tap suite.
--
-- Checks:
--   * using a hint breaks the fast-clear combo chain — the pair cleared after
--     the hint earns no combo bonus and any running chain restarts at 0 (the
--     chain bonus is untouched: that is about consecutive same-group matches);
--   * the broken combo is what prevents hint-and-immediately-tap autopilot
--     farming of escalating COMBO points;
--   * a tap on EMPTY board space (beside the stack) deselects the currently
--     selected tile and drops its overlay;
--   * an empty-area tap with nothing selected is a harmless no-op.
--   * disabling the setting preserves a selected tile on an empty-area tap.

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

local function pk(x, y, l) return Logic.posKey(x, y, l) end
local function boardWith(tiles)
    local b = {}
    for _, t in ipairs(tiles) do b[pk(t[1], t[2], t[3])] = t[4] end
    return b
end
local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
-- First empty board-local point (any tile misses it). Used to simulate a tap
-- beside the stack; a full-turtle canvas centered on a small deal has plenty.
local function findEmptyPoint(bv)
    for y = 0, bv.height, 10 do
        for x = 0, bv.width, 10 do
            if not bv:hitTest(x, y) then return x, y end
        end
    end
    return 0, 0
end

-- ---- Hint breaks the combo chain -----------------------------------------------

-- Three b1 pairs on the classic full row (positions proven in us09).
local mj = Mahjong:new()
mj.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
    {10,2,0,"b1"}, {12,2,0,"b1"},
}
mj:buildUILayout()

-- Pair 1 (no previous match): +10.
mj:handleTileTap(2, 2, 0)
mj:handleTileTap(4, 2, 0)
expect(mj.score == 10, "first pair scores 10 (got " .. tostring(mj.score) .. ")")

-- Pair 2 fast (same group): chain +5, combo +10 -> +25 (total 35).
mj:handleTileTap(6, 2, 0)
mj:handleTileTap(8, 2, 0)
expect(mj.score == 35 and mj.combo_chain == 1,
    "a fast same-group pair gets the chain and a combo (35, chain 1)")

-- Use a hint: it must break the combo chain.
mj:showHint()
expect(mj.last_match_elapsed == nil and mj.combo_chain == 0,
    "showing a hint resets the combo window and chain counter")

-- Pair 3 (still fast, same kind). Without the break it would also get a
-- combo (chain would climb to 2 and add COMBO_BONUS + COMBO_INCREMENT). With
-- the break it gets ONLY the chain bonus (+5) -> 35 - 5 (hint penalty) + 15.
mj:handleTileTap(10, 2, 0)
mj:handleTileTap(12, 2, 0)
expect(mj.score == 45,
    "a pair right after a hint gets chain but NO combo (35 - 5 + 15 = 45, got "
        .. tostring(mj.score) .. ")")
expect(mj.combo_chain == 0, "post-hint pair restarts the combo chain at 0")

-- ---- Empty-board tap deselects -------------------------------------------------

local mj2 = Mahjong:new()
mj2.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"} }
mj2:buildUILayout()
local bv = mj2.board_view
bv.dimen.x, bv.dimen.y = 0, 0

-- Select the b1 tile.
mj2:handleTileTap(2, 2, 0)
expect(mj2.selected ~= nil and mapCount(bv.overlays) == 1,
    "tile selected before the empty-area tap")

-- Tap an empty spot in the playing area: the selection is dropped.
local ex, ey = findEmptyPoint(bv)
local handled = bv:onTapSelect(nil, { pos = { x = ex, y = ey } })
expect(handled == true
        and mj2.selected == nil
        and mapCount(bv.overlays) == 0,
    "tapping empty board space deselects the selected tile")

-- A second empty-area tap with nothing selected is a no-op.
local handled2 = bv:onTapSelect(nil, { pos = { x = ex, y = ey } })
expect(handled2 == true and mj2.selected == nil,
    "an empty-area tap with no selection is a harmless no-op")

-- Same via the real dispatch path (packed args -> (nil, ges)).
local packed = { nil, { pos = { x = ex, y = ey } }, n = 2 }
expect(bv["onTapSelect"](bv, unpack(packed, 1, packed.n)) == true
        and mj2.selected == nil,
    "empty-area tap via the real dispatch path still deselects")

-- The setting-off behavior preserves the old selection until another viable
-- tile is tapped or the selected tile is matched.
local mj3 = Mahjong:new()
mj3:setSetting("deselect_on_empty", false)
mj3.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"} }
mj3:buildUILayout()
local bv3 = mj3.board_view
bv3.dimen.x, bv3.dimen.y = 0, 0
mj3:handleTileTap(2, 2, 0)
local ex3, ey3 = findEmptyPoint(bv3)
bv3:onTapSelect(nil, { pos = { x = ex3, y = ey3 } })
expect(mj3.selected ~= nil and mj3.selected.x == 2 and mapCount(bv3.overlays) == 1,
    "with deselect-on-empty off, empty board space preserves the selection")

if failures == 0 then
    print("\nALL COMBO/HINT + EMPTY-TAP CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
