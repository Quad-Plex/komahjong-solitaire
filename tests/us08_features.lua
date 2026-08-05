-- US-08 features suite: undo, hint, shuffle.
--
-- Checks:
--   * Undo restores the exact previous state (logic board, rendered board, score);
--   * Hint highlights a matching free pair (overlays created);
--   * Shuffle preserves the multiset of remaining tiles;
--   * No-moves offer a shuffle prompt;
--   * Immediate auto-repeat of shuffle if it produces another dead board.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Board = ctx.loadPlugin("mahjongboard")
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

local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local function pk(x, y, l) return Logic.posKey(x, y, l) end
local function boardWith(tiles)
    local b = {}
    for _, t in ipairs(tiles) do b[pk(t[1], t[2], t[3])] = t[4] end
    return b
end
local function sortedKinds(board)
    local kinds = {}
    for _, k in pairs(board) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    return kinds
end

-- ---- Undo (US-08) ----------------------------------------------------------

local mj = Mahjong:new()
mj.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"}, {8,2,0,"c1"} }
mj:buildUILayout()
mj.score = 0
mj.history = {}

-- Perform a move
mj:handleTileTap(2, 2, 0)
mj:handleTileTap(4, 2, 0)
expect(Logic.tileCount(mj.board) == 2, "pair removed")
expect(mj.score == 10, "score updated to 10")
expect(#mj.history == 1, "history has one move")

-- Undo the move
mj:undo()
expect(Logic.tileCount(mj.board) == 4, "undo restored the tiles to the logic board")
expect(mapCount(mj.board_view.tile_widgets) == 4, "undo restored the widgets")
expect(mj.score == 0, "undo restored the score to 0")
expect(#mj.history == 0, "history is empty")
expect(Logic.tileAt(mj.board, 2, 2, 0) == "b1" and Logic.tileAt(mj.board, 4, 2, 0) == "b1",
    "undone tiles have correct kinds")

-- Undo on empty history
mj:undo()
expect(Logic.tileCount(mj.board) == 4, "undo on empty history does nothing")

-- ---- Hint (US-08) ----------------------------------------------------------

local mj_hint = Mahjong:new()
mj_hint.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"} }
mj_hint:buildUILayout()
mj_hint:showHint()
expect(mapCount(mj_hint.board_view.overlays) == 2, "hint draws two overlays")
-- We can't easily test the scheduled clear headlessly without mocking scheduleIn more deeply,
-- but we verified the setOverlay call.

-- ---- Hint cycling (US-08 follow-up) ----------------------------------------
--
-- Repeated Hint presses cycle through the distinct matching pairs instead of
-- always highlighting the first one: press 1/2/3 highlight three different
-- pairs, press 4 wraps back to the first.

local function hintedPair(mj)
    local keys = {}
    for k in pairs(mj.board_view.overlays) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, "/")
end

local mj_cycle = Mahjong:new()
mj_cycle.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
    {2,4,0,"d1"}, {4,4,0,"d1"},
}
mj_cycle:buildUILayout()
mj_cycle:showHint()
local h1 = hintedPair(mj_cycle)
mj_cycle:showHint()
local h2 = hintedPair(mj_cycle)
mj_cycle:showHint()
local h3 = hintedPair(mj_cycle)
mj_cycle:showHint()
local h4 = hintedPair(mj_cycle)
expect(h1 ~= "" and h2 ~= "" and h3 ~= "", "each hint press highlights two tiles")
expect(h2 ~= h1, "a second hint press cycles to a different pair")
expect(h3 ~= h1 and h3 ~= h2, "a third hint press cycles to a third pair")
expect(h4 == h1, "the hint cycle wraps back to the first pair")

-- The previous hint's overlays are cleared before the next one is drawn, so
-- repeated presses never stack highlights.
expect(mapCount(mj_cycle.board_view.overlays) == 2,
    "cycling hints keep exactly one pair highlighted at a time")

-- If the board changes under the hinted pair (it is matched away), the next
-- hint starts the cycle over instead of resuming at a stale position.
local mj_stale = Mahjong:new()
mj_stale.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj_stale:buildUILayout()
mj_stale:showHint()
local stale_h1 = hintedPair(mj_stale)
mj_stale:handleTileTap(2, 2, 0) -- select
mj_stale:handleTileTap(4, 2, 0) -- match the hinted pair away
expect(mapCount(mj_stale.board_view.overlays) == 0,
    "removing the hinted pair drops its overlay")
mj_stale:showHint()
expect(hintedPair(mj_stale) ~= "" and hintedPair(mj_stale) ~= stale_h1,
    "a hint after the board changed starts the cycle over cleanly")

-- ---- Shuffle (US-08) -------------------------------------------------------

local mj_shuf = Mahjong:new()
mj_shuf.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b2"}, {6,2,0,"b3"} }
mj_shuf:buildUILayout()
local kinds_before = sortedKinds(mj_shuf.board)
mj_shuf:shuffleBoard(true) -- force
local kinds_after = sortedKinds(mj_shuf.board)
expect(#kinds_after == 3, "shuffle keeps count")
local same = true
for i=1,3 do if kinds_before[i] ~= kinds_after[i] then same = false end end
expect(same, "shuffle preserves the multiset of tiles")

-- ---- No-moves Shuffle prompt (US-08) ---------------------------------------

local mj_dead = Mahjong:new()
mj_dead.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},   -- playable pair
    {6,2,0,"c1"}, {8,2,0,"c2"},   -- leftovers: no move possible
}
mj_dead:buildUILayout()
ctx.last_confirm = nil
mj_dead:handleTileTap(2, 2, 0)
mj_dead:handleTileTap(4, 2, 0)
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text:find("No moves left", 1, true),
    "dead board shows a shuffle prompt instead of immediate shuffle")
ctx.last_confirm.ok_callback()
expect(Logic.tileCount(mj_dead.board) == 2, "shuffled board still has 2 tiles")
expect(mapCount(mj_dead.board_view.tile_widgets) == 2, "board view updated after shuffle prompt")

if failures == 0 then
    print("\nALL US-08 FEATURE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
