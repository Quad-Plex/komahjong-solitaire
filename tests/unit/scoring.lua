-- US-09 score & status suite: base + chain/combo scoring, HUD feedback, and the
-- invalid-selection flash.
--
-- Checks:
--   * Logic: pairPoints (base 10 / +5 chain) and matchGroup;
--   * A consecutive same-kind match chains (+5) and a fast match gets +10;
--   * A different-kind match does NOT chain;
--   * Flower pairs chain with any flower;
--   * Undo restores the score AND the chain state (last_match_kind);
--   * The HUD score chip reflects the running total after every move;
--   * Tapping a blocked tile flashes a brief feedback message and selects nothing;
--   * The win dialog reports the chain-inclusive final score;
--   * Shuffle keeps the chain state (a chain is about consecutive matches,
--     not board positions).

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

local function pk(x, y, l) return Logic.posKey(x, y, l) end
local function boardWith(tiles)
    local b = {}
    for _, t in ipairs(tiles) do b[pk(t[1], t[2], t[3])] = t[4] end
    return b
end

-- ---- Logic scoring (US-09) -------------------------------------------------

expect(Logic.SCORE_PER_PAIR == 10, "logic base score constant is 10")
expect(Logic.CHAIN_BONUS == 5, "logic chain bonus constant is 5")
expect(Logic.COMBO_BONUS == 10, "logic combo bonus constant is 10")
expect(Logic.COMBO_INCREMENT == 5, "combo-chain increment is 5")
expect(Logic.pairPoints(nil, "b1") == 10, "first match scores the base 10")
expect(Logic.pairPoints("b1", "b1") == 15, "same-kind chain scores 15")
expect(Logic.pairPoints("b2", "b1") == 10, "different kind scores 10")
expect(Logic.pairPoints("flower1", "flower3") == 15, "flower-to-flower chains")
expect(Logic.pairPoints("season2", "season1") == 15, "season-to-season chains")
expect(Logic.pairPoints("flower1", "season1") == 10, "flower never chains with a season")
expect(Logic.matchGroup("b1") == "b1" and Logic.matchGroup("flower1") == "flower",
    "matchGroup maps kinds to their chain group")

-- ---- Chain scoring through the real tap flow -------------------------------

local mj = Mahjong:new()
mj.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj:buildUILayout()
mj:handleTileTap(2, 2, 0)
mj:handleTileTap(4, 2, 0)
expect(mj.score == 10, "first b1 pair scores 10 (got " .. tostring(mj.score) .. ")")
expect(mj.last_match_kind == "b1", "last match kind is tracked")
expect(mj.status_bar.stats.score == 10, "HUD score chip shows 10")

mj:handleTileTap(6, 2, 0)
mj:handleTileTap(8, 2, 0)
expect(mj.score == 35, "fast consecutive same-kind pair gets chain + combo, total 35 (got " .. tostring(mj.score) .. ")")
expect(mj.status_bar.stats.score == 35, "HUD score chip reflects the chain and combo bonuses")
expect(mj.flash_text.text == "COMBO +10", "fast pair shows COMBO +10 in the feedback band")
expect(Logic.isWin(mj.board), "board emptied after the chain pair")

-- ---- Undo restores score AND chain state -----------------------------------

mj:undo()
expect(mj.score == 10, "undo restores score to 10")
expect(mj.last_match_kind == "b1", "undo restores the chain state")
mj:handleTileTap(6, 2, 0)
mj:handleTileTap(8, 2, 0)
expect(mj.score == 25, "undo breaks the combo window but preserves chain scoring (back to 25)")
expect(mj.flash_text.text ~= "COMBO +10", "redoing an undone pair shows no combo message")

-- ---- No chain across different kinds ---------------------------------------

local mj2 = Mahjong:new()
mj2.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj2:buildUILayout()
mj2:handleTileTap(2, 2, 0)
mj2:handleTileTap(4, 2, 0)
mj2:handleTileTap(6, 2, 0)
mj2:handleTileTap(8, 2, 0)
expect(mj2.score == 30, "different-kind match gets combo but not chain (10 + 20 = 30)")
expect(mj2.last_match_kind == "c1", "last kind updates to c1")
expect(Logic.isWin(mj2.board), "board emptied")

-- ---- Flower wildcard chains -------------------------------------------------

local mj3 = Mahjong:new()
mj3.board = boardWith{
    {2,2,0,"flower1"}, {4,2,0,"flower2"},
    {6,2,0,"flower3"}, {8,2,0,"flower4"},
}
mj3:buildUILayout()
mj3:handleTileTap(2, 2, 0)
mj3:handleTileTap(4, 2, 0)
mj3:handleTileTap(6, 2, 0)
mj3:handleTileTap(8, 2, 0)
expect(mj3.score == 35, "flower pairs chain and combo (10 + 25 = 35)")

-- ---- Escalating combo chain ---------------------------------------------------

local mj_chain = Mahjong:new()
mj_chain.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
    {10,2,0,"b1"}, {12,2,0,"b1"},
}
mj_chain:buildUILayout()
mj_chain:handleTileTap(2, 2, 0)
mj_chain:handleTileTap(4, 2, 0)
mj_chain:handleTileTap(6, 2, 0)
mj_chain:handleTileTap(8, 2, 0)
expect(mj_chain.score == 35 and mj_chain.flash_text.text == "COMBO +10",
    "the first fast clear gets a +10 combo")
mj_chain:handleTileTap(10, 2, 0)
mj_chain:handleTileTap(12, 2, 0)
expect(mj_chain.score == 65 and mj_chain.flash_text.text == "COMBO-CHAIN +15"
        and mj_chain.flash_text.bold == true,
    "the next fast clear escalates to COMBO-CHAIN +15")

-- ---- Invalid selection shows non-blocking feedback ---------------------------

local mj4 = Mahjong:new()
mj4.board = boardWith{
    {5,3,0,"b1"}, {5,3,1,"b2"}, -- L0 covered from above
}
mj4:buildUILayout()
expect(mj4.flash_band_icon ~= nil and mj4.flash_band_icon.hide == true,
    "warning icon exists and is hidden by default")
expect(mj4.flash_band_icon.overlap_offset ~= nil
        and type(mj4.flash_band_icon.overlap_offset[1]) == "number"
        and type(mj4.flash_band_icon.overlap_offset[2]) == "number",
    "warning icon offset is an array {x, y} on the widget itself (OverlapGroup getSize contract)")
mj4:handleTileTap(5, 3, 0)
expect(mj4.selected == nil, "blocked tile is not selected")
expect(mj4.flash_text ~= nil and tostring(mj4.flash_text.text):find("blocked", 1, true) ~= nil,
    "tapping a blocked tile shows feedback in the band between board and toolbar")
expect(mj4.flash_band_icon.hide == false,
    "the warning icon shows while a message is displayed")
expect(mj4[1] and mj4[1][2] and mj4[1][3] == mj4.flash_band and mj4[1][4],
    "feedback band sits between the board (index 2) and the toolbar (index 4)")
expect(mj4.flash_band._padding_left == 8 and mj4.flash_band._padding_right == 8
        and mj4.flash_band._padding_top == 8 and mj4.flash_band._padding_bottom == 8,
    "feedback band sets _padding_* fields (getSize override must not crash paintTo)")
mj4:clearFlash()
expect(mj4.flash_text.text == "", "feedback clears after its timeout")
expect(mj4.flash_band_icon.hide == true,
    "the warning icon hides again once the message clears")

-- The band is non-blocking: an immediate next tap still selects a free tile.
local mj4b = Mahjong:new()
mj4b.board = boardWith{
    {5,3,0,"b1"}, {5,3,1,"b2"},
    {9,6,0,"east"},
}
mj4b:buildUILayout()
mj4b:handleTileTap(5, 3, 0) -- blocked -> flash
mj4b:handleTileTap(9, 6, 0) -- free -> should select despite the flash
expect(mj4b.selected ~= nil and mj4b.selected.kind == "east",
    "feedback is non-blocking: the next tap still selects a free tile")
expect(tostring(mj4b.flash_text.text):find("blocked", 1, true) ~= nil,
    "the feedback is still visible while the next tile gets selected")

-- ---- Win dialog reports the chain-inclusive score ----------------------------

local mj5 = Mahjong:new()
mj5.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj5:buildUILayout()
mj5:handleTileTap(2, 2, 0)
mj5:handleTileTap(4, 2, 0)
ctx.last_confirm = nil
mj5:handleTileTap(6, 2, 0)
mj5:handleTileTap(8, 2, 0)
expect(ctx.last_confirm ~= nil
        and ctx.summaryText(ctx.last_confirm):find("Score: 35", 1, true) ~= nil,
    "win dialog shows the chain/combo-inclusive score (35)")
expect(mj5.score == 35, "score is 35 at the win")

-- ---- Shuffle keeps the chain state -------------------------------------------

local mj6 = Mahjong:new()
mj6.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj6:buildUILayout()
mj6:handleTileTap(2, 2, 0)
mj6:handleTileTap(4, 2, 0)
mj6:shuffleBoard(true)
expect(mj6.last_match_kind == "b1", "shuffle keeps the chain state")
local free = Logic.freeTiles(mj6.board)
local ta, tb
for i = 1, #free - 1 do
    for j = i + 1, #free do
        if Logic.matches(free[i].kind, free[j].kind) then
            ta, tb = free[i], free[j]
            break
        end
    end
    if ta then break end
end
expect(ta ~= nil, "shuffled board still has a playable pair")
mj6:handleTileTap(ta.x, ta.y, ta.layer)
mj6:handleTileTap(tb.x, tb.y, tb.layer)
-- The second same-kind pair chains (+15) and is fast (+10), but the
-- user-initiated shuffle in between costs SHUFFLE_PENALTY (10), so the net is
-- 10 + 25 - 10 = 25 (US-18).
expect(mj6.score == 25, "chain/combo applies across a shuffle (10 + 25 - 10 = 25)")

-- ---- Combo window ------------------------------------------------------------

local mj7 = Mahjong:new()
mj7.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
    {10,2,0,"c1"}, {12,2,0,"c1"},
}
mj7:buildUILayout()
mj7:handleTileTap(2, 2, 0)
mj7:handleTileTap(4, 2, 0)
mj7.last_match_elapsed = mj7:getElapsed() - 6
mj7:handleTileTap(6, 2, 0)
mj7:handleTileTap(8, 2, 0)
expect(mj7.score == 25, "a match after five seconds gets chain points but no combo")
expect(mj7.flash_text.text ~= "COMBO +10", "expired combo window shows no combo message")

-- ---- Basic score method disables BOTH chain and combo -------------------------

local mj8 = Mahjong:new()
mj8.score_method = "basic"
mj8.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj8:buildUILayout()
-- Set score_method via assignment above; buildUILayout must not overwrite it.
mj8:handleTileTap(2, 2, 0)
mj8:handleTileTap(4, 2, 0)
expect(mj8.score == 10, "basic: first pair scores base 10 (got " .. tostring(mj8.score) .. ")")
mj8:handleTileTap(6, 2, 0)
mj8:handleTileTap(8, 2, 0)
expect(mj8.score == 20, "basic: fast same-kind pair gets NO chain and NO combo, total 20 (got " .. tostring(mj8.score) .. ")")
expect(mj8.flash_text.text ~= "COMBO +10", "basic: fast pair shows no combo message")
expect(Logic.isWin(mj8.board), "board emptied after the basic-method pair")

if failures == 0 then
    print("\nALL US-09 SCORE/STATUS CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
