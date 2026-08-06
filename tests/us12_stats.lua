-- US-12 win-summary suite: lifetime stats, the win dialog's summary, stats
-- persistence, the streak rules around Play again / a mid-game New Game, and
-- the US-19 rule that auto-solve wins never count.
--
-- Checks:
--   * MahjongStats defaults/startGame/recordWin/load (logic-level, mirroring
--     the module's own self-tests);
--   * Stats persist under their own "stats" LuaSettings key and survive a
--     fresh plugin instance (the "game" key is untouched);
--   * The win dialog is a multi-line summary containing score / time / pairs /
--     best score / best time / current streak;
--   * The first records are marked "New best!", later equal or worse wins are
--     not, and a later better win is;
--   * A human win records games_won / bests / streaks and sets game_won;
--   * Play again starts a fresh game and keeps the winning streak;
--   * A mid-game New Game abandons the game and resets the streak;
--   * An auto-solve win records no win / bests / streak / games_played and
--     leaves game_won false (the dialog still shows the summary).

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Stats = ctx.loadPlugin("mahjongstats")
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

-- A tiny full play-through helper: `pairs_n` b1 tiles in a row (all free),
-- tapped as matched pairs. Clears the board and leaves the win dialog up.
local function playAndWin(mj, pairs_n)
    ctx.last_confirm = nil
    for i = 0, pairs_n - 1 do
        mj:handleTileTap(2 + 4 * i, 2, 0)
        mj:handleTileTap(4 + 4 * i, 2, 0)
    end
end

-- US-14: the win dialog's "Play again" and the New Game button both show the
-- layout picker; pick Turtle to deal a fresh board.
local function pickTurtle()
    local picker = ctx.window_stack[#ctx.window_stack].widget
    if not picker or picker.name ~= "mahjonglayoutselect" then return end
    local r
    for _, c in ipairs(picker._card_rects) do
        if c.id == "turtle" then r = c break end
    end
    picker:onTapSelect(nil, { pos = { x = r.x + r.w / 2, y = r.y + r.h / 2 } })
    -- US-30: the picker deals on a deferred tick. This test overrides
    -- um.scheduleIn into its own `scheduled` list; the deal is the task just
    -- added (last), so run it.
    if scheduled[#scheduled] then
        local e = table.remove(scheduled, #scheduled)
        e[2]()
    end
end
local function setBoard(mj, tiles)
    mj.board = boardWith(tiles)
    mj.score = 0
    mj.last_match_kind = nil
    mj.pairs_matched = 0
    mj.history = {}
    mj.selected = nil
    mj:buildUILayout()
end

-- ---- Pure stats module (logic-level, mirrors the self-tests) ------------------

local s = Stats.defaults()
expect(s.games_played == 0 and s.games_won == 0 and s.best_score == 0
        and s.best_time == nil and s.current_streak == 0 and s.longest_streak == 0,
    "defaults() is zeroed with best_time nil")

Stats.startGame(s, true)
Stats.startGame(s, true)
expect(s.games_played == 2, "startGame bumps games_played each time")
expect(s.current_streak == 0, "startGame keeps the streak when the previous game was won")

local nb, nbt = Stats.recordWin(s, 100, 90, 72)
expect(s.games_won == 1 and s.current_streak == 1 and s.longest_streak == 1,
    "recordWin bumps games_won / current_streak / longest_streak")
expect(s.best_score == 100 and s.best_time == 90 and nb and nbt,
    "a first win sets both records and reports the new bests")

Stats.recordWin(s, 50, 120, 72)
expect(s.best_score == 100 and s.best_time == 90,
    "a worse win does not replace the bests")
Stats.recordWin(s, 150, 60, 72)
expect(s.best_score == 150 and s.best_time == 60,
    "a better win replaces both bests")

Stats.startGame(s, false)
expect(s.games_played == 3 and s.current_streak == 0,
    "an abandoned previous game resets the streak")
expect(s.longest_streak == 3, "the longest streak keeps its peak")

-- ---- Stats persist under their own "stats" key across instances ---------------

local mj0 = Mahjong:new()
expect(mj0.stats ~= nil and mj0.stats.games_played == 0,
    "a fresh plugin instance loads default stats")
mj0.stats.games_played = 5
mj0.stats.best_score = 120
mj0.stats.best_time = 42
mj0:saveStats()
expect(store.stats ~= nil and store.stats.games_played == 5 and store.stats.best_score == 120,
    "saveStats persists the record under the 'stats' key")
expect(store.game == nil, "the stats key is separate from the game key")

local mj0b = Mahjong:new()
expect(mj0b.stats.games_played == 5 and mj0b.stats.best_score == 120
        and mj0b.stats.best_time == 42,
    "a fresh plugin instance reads the persisted stats back")

-- Start the gameplay section from a clean stats record.
store.stats = nil

-- ---- The win dialog is a summary with bests + New best! markers ---------------

local mj1 = Mahjong:new()
setBoard(mj1, {
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
})
mj1.elapsed_base = 45
playAndWin(mj1, 2)
expect(Logic.isWin(mj1.board), "test board emptied for the win")
expect(ctx.last_confirm ~= nil, "a win shows the win dialog")
local win_text = tostring(ctx.last_confirm.text)
expect(win_text:find("You cleared the board!", 1, true) ~= nil,
    "the summary keeps the cleared-the-board headline")
expect(win_text:find("Score: 25", 1, true) ~= nil, "the summary shows the final score")
expect(win_text:find("Time: 00:45", 1, true) ~= nil, "the summary shows the elapsed time")
expect(win_text:find("Pairs matched: 2", 1, true) ~= nil, "the summary shows the pairs matched")
expect(win_text:find("Hints used: 0", 1, true) ~= nil,
    "the summary shows zero hints used on a clean win")
expect(win_text:find("Shuffles: 0", 1, true) ~= nil,
    "the summary shows zero shuffles on a clean win")
expect(win_text:find("Best score: 25", 1, true) ~= nil, "the summary shows the best score")
expect(win_text:find("Best time: 00:45", 1, true) ~= nil, "the summary shows the best time")
expect(win_text:find("Current streak: 1", 1, true) ~= nil, "the summary shows the current streak")
expect(win_text:find("New best!", 1, true) ~= nil,
    "a first record marks the best lines with New best!")
expect(mj1.stats.games_won == 1 and mj1.stats.best_score == 25
        and mj1.stats.best_time == 45 and mj1.stats.current_streak == 1
        and mj1.stats.longest_streak == 1,
    "a human win recorded games_won / bests / streak")
expect(mj1.game_won == true, "showWinDialog sets the game_won flag")
expect(store.stats ~= nil and store.stats.games_won == 1 and store.stats.best_score == 25,
    "the win was persisted to the stats key")
expect(store.game == nil, "a won board is still not saved under the game key")

-- ---- Play again starts a new game and keeps the streak ------------------------

ctx.last_confirm.ok_callback()
pickTurtle() -- US-14: Play again shows the picker
expect(Logic.tileCount(mj1.board) == 144, "Play again dealt a fresh 144-tile board")
expect(mj1.stats.games_played == 1, "Play again bumped games_played")
expect(mj1.stats.current_streak == 1, "Play again keeps the streak after a win")
expect(mj1.game_won == false, "the new game clears the game_won flag")

-- ---- A worse second win extends the streak but updates no record --------------

setBoard(mj1, {
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
})
mj1.hints_used = 2
mj1.shuffles_used = 1
mj1.elapsed_base = 60
playAndWin(mj1, 2)
win_text = tostring(ctx.last_confirm.text)
expect(win_text:find("Hints used: 2", 1, true) ~= nil,
    "the summary shows the number of hints used")
expect(win_text:find("Shuffles: 1", 1, true) ~= nil,
    "the summary shows the number of shuffles used")
expect(win_text:find("New best!", 1, true) == nil,
    "a win that beats no record shows no New best! marker")
expect(mj1.stats.games_won == 2 and mj1.stats.current_streak == 2,
    "a worse win still counts and extends the streak")
expect(mj1.stats.best_score == 25 and mj1.stats.best_time == 45,
    "a worse win keeps the existing records")

-- ---- A better third win marks the records again -------------------------------

setBoard(mj1, {
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
    {10,2,0,"b1"}, {12,2,0,"b1"},
})
mj1.elapsed_base = 30
playAndWin(mj1, 3)
expect(Logic.isWin(mj1.board), "six-tile board emptied for the win")
expect(mj1.score == 40, "the six-tile chain win scores 40 (10+15+15)")
expect(mj1.pairs_matched == 3, "the pair counter tracked the three matched pairs")
win_text = tostring(ctx.last_confirm.text)
expect(win_text:find("Best score: 40 (New best!)", 1, true) ~= nil,
    "a new best score is marked New best!")
expect(win_text:find("Best time: 00:30 (New best!)", 1, true) ~= nil,
    "a new best time is marked New best!")
expect(mj1.stats.best_score == 40 and mj1.stats.best_time == 30,
    "the records updated to the better win")

-- ---- A mid-game New Game abandons the game and resets the streak --------------

ctx.last_confirm.ok_callback()
pickTurtle() -- US-14: Play again shows the picker
expect(mj1.stats.games_played == 2 and mj1.stats.current_streak == 3,
    "Play again after a win keeps the 3-win streak")
expect(Logic.tileCount(mj1.board) == 144, "Play again dealt a fresh board")

-- Drive the toolbar's New Game button (real flow): US-14 shows the picker
-- instead of a ConfirmBox.
local toolbar = mj1[1][4]
local btns = {}
for i = 1, #toolbar do
    local b = toolbar[i]
    if type(b) == "table" and b.bordersize then
        btns[#btns + 1] = b
    elseif type(b) == "table" and b[1] and b[1].bordersize then
        btns[#btns + 1] = b[1]
    end
end
local played_before = mj1.stats.games_played
ctx.last_confirm = nil
btns[4].callback()
expect(ctx.last_confirm == nil, "New Game shows no ConfirmBox (picker instead)")
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "New Game opens the layout picker")
pickTurtle()
expect(mj1.stats.games_played == played_before + 1,
    "a mid-game New Game bumps games_played")
expect(mj1.stats.current_streak == 0,
    "a mid-game New Game resets the streak (previous game abandoned)")
expect(mj1.stats.longest_streak == 3,
    "the abandoned game keeps the all-time longest streak")

-- ---- Auto-solve wins never count toward the lifetime stats (US-19) ------------

local mj2 = Mahjong:new()
mj2.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"c1"}, {8,2,0,"c1"},
}
mj2:buildUILayout()
mj2.score = 0
mj2.hints_used = 1
mj2.shuffles_used = 2
scheduled = {}
mj2.hint_button.hold_callback()
local arm = scheduled[1][2]
scheduled = {}
arm()
expect(mj2.game_was_autosolved == true, "startAutoSolve flags the game as auto-solved")
local guard = 0
while scheduled[1] and guard < 200 do
    local e = table.remove(scheduled, 1)
    e[2]()
    guard = guard + 1
end
expect(Logic.isWin(mj2.board), "auto-solve cleared the board")
expect(mj2.stats.games_won == 3 and mj2.stats.best_score == 40
        and mj2.stats.best_time == 30 and mj2.stats.current_streak == 0
        and mj2.stats.games_played == 3,
    "an auto-solve win leaves the loaded lifetime stats untouched")
expect(mj2.game_won == false, "an auto-solve win does not set the game_won flag")
win_text = tostring(ctx.last_confirm.text)
expect(win_text:find("New best!", 1, true) == nil,
    "an auto-solve win never marks a New best!")
expect(win_text:find("Pairs matched: 2", 1, true) ~= nil,
    "the auto-solve win dialog still shows the pair count")
expect(win_text:find("Hints used: 1", 1, true) ~= nil,
    "the auto-solve win dialog shows hints used")
expect(win_text:find("Shuffles: 2", 1, true) ~= nil,
    "the auto-solve win dialog shows shuffles used")

-- Play again after an auto-solve win: a genuinely new game DOES bump
-- games_played (the auto-solve itself recorded nothing).
ctx.last_confirm.ok_callback()
pickTurtle() -- US-14: Play again shows the picker
expect(mj2.stats.games_played == 4, "Play again after an auto-solve starts a fresh game")
expect(mj2.game_won == false and mj2.game_was_autosolved == false,
    "a new game clears the game_won and auto-solved flags")

if failures == 0 then
    print("\nALL US-12 STATS/SUMMARY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
