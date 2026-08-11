-- US-52: fresh deals are generated from a legal clear sequence.
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

local function canClear(board, layout_id, witness)
    if witness then
        local remaining = {}
        for key, kind in pairs(board) do remaining[key] = kind end
        for _, pair in ipairs(witness) do
            local a = Logic.posKey(pair.a.x, pair.a.y, pair.a.layer)
            local b = Logic.posKey(pair.b.x, pair.b.y, pair.b.layer)
            if not remaining[a] or not remaining[b]
                    or not Logic.isFree(remaining, pair.a.x, pair.a.y, pair.a.layer)
                    or not Logic.isFree(remaining, pair.b.x, pair.b.y, pair.b.layer)
                    or not Logic.matches(remaining[a], remaining[b]) then return false end
            remaining[a], remaining[b] = nil, nil
        end
        return Logic.tileCount(remaining) == 0
    end
    local remaining = {}
    for key, kind in pairs(board) do remaining[key] = kind end
    local seen = {}
    local function search()
        if Logic.tileCount(remaining) == 0 then return true end
        local keys = {}
        for key, kind in pairs(remaining) do keys[#keys + 1] = key .. "=" .. kind end
        table.sort(keys)
        local signature = table.concat(keys, ";")
        if seen[signature] then return false end
        seen[signature] = true
        for _, pair in ipairs(Logic.matchingFreePairs(remaining, layout_id)) do
            local a = Logic.posKey(pair.a.x, pair.a.y, pair.a.layer)
            local b = Logic.posKey(pair.b.x, pair.b.y, pair.b.layer)
            remaining[a], remaining[b] = nil, nil
            if search() then return true end
            remaining[a], remaining[b] = pair.a.kind, pair.b.kind
        end
        return false
    end
    return search()
end

for _, id in ipairs(Logic.layoutIds()) do
    for _ = 1, 2 do
        local board, witness = Logic.dealWithWitness(id)
        expect(board ~= nil and witness ~= nil,
            id .. " fresh deal produced a legal-clear witness")
        if not board then break end
        expect(Logic.tileCount(board) == 144,
            id .. " fresh deal has all 144 tiles")
        expect(Logic.countFreePairs(board, id) > 0,
            id .. " fresh deal has a matching opening pair")
        expect(not Logic.isPermanentlyDead(board),
            id .. " fresh deal is not structurally dead")
        expect(canClear(board, id, witness), id .. " fresh deal is legally clearable without shuffling")
    end
end

if failures > 0 then
    error(failures .. " solvable-deal test(s) failed")
end
print("US-38 solvable-deal tests passed")
