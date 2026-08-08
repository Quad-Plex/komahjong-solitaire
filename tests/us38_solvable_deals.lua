-- US-38: fresh deals are generated from a legal clear sequence.
--
-- The generator must not merely provide an opening move: every built-in layout
-- should get a full board with a usable opening and no structural deadlock.

local mock = require("mock")
local ctx = mock.newContext()
local Logic = ctx.loadPlugin("mahjonglogic")

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

for _, id in ipairs(Logic.layoutIds()) do
    for _ = 1, 2 do
        local board = Logic.newGame(id)
        expect(Logic.tileCount(board) == 144,
            id .. " fresh deal has all 144 tiles")
        expect(Logic.countFreePairs(board, id) > 0,
            id .. " fresh deal has a matching opening pair")
        expect(not Logic.isPermanentlyDead(board),
            id .. " fresh deal is not structurally dead")
    end
end

if failures > 0 then
    error(failures .. " solvable-deal test(s) failed")
end
print("US-38 solvable-deal tests passed")
