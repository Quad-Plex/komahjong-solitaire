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
local win_text = ctx.summaryText(ctx.last_confirm)
expect(win_text:find("Congratulations! New overall best score and best time!", 1, true) ~= nil,
    "a first win headlines a new overall best score and best time")
expect(win_text:find("Score: 35", 1, true) ~= nil, "the summary shows the final score")
expect(win_text:find("Time: 00:45", 1, true) ~= nil, "the summary shows the elapsed time")
expect(win_text:find("Pairs matched: 2", 1, true) ~= nil, "the summary shows the pairs matched")
expect(win_text:find("Hints used: 0", 1, true) ~= nil,
    "the summary shows zero hints used on a clean win")
expect(win_text:find("Shuffles: 0", 1, true) ~= nil,
    "the summary shows zero shuffles on a clean win")
expect(win_text:find("Overall best score: 35 (New best!)", 1, true) ~= nil,
    "the summary shows the overall best score")
expect(win_text:find("Overall best time: 00:45 (New best!)", 1, true) ~= nil,
    "the summary shows the overall best time")
expect(win_text:find("Turtle best score: 35 (New best!)", 1, true) ~= nil,
    "the summary shows the layout best score")
expect(win_text:find("Turtle best time: 00:45 (New best!)", 1, true) ~= nil,
    "the summary shows the layout best time")
expect(win_text:find("Current streak: 1", 1, true) ~= nil, "the summary shows the current streak")
expect(win_text:find("New best!", 1, true) ~= nil,
    "a first record marks the best lines with New best!")

-- The win summary is a centered floating card (mahjongwinsummary.lua). Its
-- headline is centered (wrapped in a CenterContainer over the content width),
-- and the value column is aligned: every row is a HorizontalGroup shaped
-- { leading right-align span, label, gap, value }, and the right-align span
-- sizes every row so all value TextWidgets start at the same x.
local win_summary = ctx.last_confirm
expect(win_summary ~= nil and win_summary.name == "mahjongwinsummary",
    "the win is a centered floating summary card")
local row_group = win_summary._row_group
expect(row_group ~= nil and row_group[1] ~= nil,
    "the summary card builds the aligned rows as a widget")
local row_count = #(win_summary.win_rows or {})
expect(row_count == 10, "the summary has 10 aligned rows (got " .. row_count .. ")")
local text_is_headline = win_summary.text:find("Congratulations! New overall best score and best time!", 1, true) ~= nil
expect(text_is_headline, "the dialog's text is the headline (centered title)")
-- The headline is the first child of the card's content VerticalGroup, wrapped
-- in a CenterContainer (a table with a `dimen` and the headline TextWidget at
-- [1]) so it centers horizontally across the content width.
local vgroup = win_summary[1] and win_summary[1][1] and win_summary[1][1][1]
local headline_wrap = vgroup and vgroup[1]
expect(headline_wrap ~= nil and headline_wrap.dimen ~= nil
        and headline_wrap[1] ~= nil and headline_wrap[1].text == win_summary.text,
    "the headline is horizontally centered by a CenterContainer")
if row_group then
    local aligned = true
    local lead_x
    for i = 1, row_count do
        local row = row_group[(i - 1) * 2 + 1]
        local lead = row and row[1]
        local label = row and row[2]
        -- In the harness every text measures 0 wide, so the value x is the
        -- leading span + label + gap; it must be identical across rows.
        local x = (lead and lead.width or 0) + (label and label.width or 0)
        if lead_x == nil then lead_x = x end
        if x ~= lead_x or row == nil or row[4] == nil then aligned = false end
    end
    expect(aligned, "every row's value TextWidget starts at the same x (left-aligned column)")
end
expect(mj1.stats.games_won == 1 and mj1.stats.best_score == 35
        and mj1.stats.best_time == 45 and mj1.stats.current_streak == 1
        and mj1.stats.longest_streak == 1,
    "a human win recorded games_won / bests / streak")
expect(mj1.game_won == true, "showWinDialog sets the game_won flag")
expect(store.stats ~= nil and store.stats.games_won == 1 and store.stats.best_score == 35,
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
win_text = ctx.summaryText(ctx.last_confirm)
expect(win_text:find("Hints used: 2", 1, true) ~= nil,
    "the summary shows the number of hints used")
expect(win_text:find("Shuffles: 1", 1, true) ~= nil,
    "the summary shows the number of shuffles used")
expect(win_text:find("New best!", 1, true) == nil,
    "a win that beats no record shows no New best! marker")
expect(win_text:find("You cleared the board!", 1, true) ~= nil,
    "a win that breaks no record falls back to the plain headline")
expect(mj1.stats.games_won == 2 and mj1.stats.current_streak == 2,
    "a worse win still counts and extends the streak")
expect(mj1.stats.best_score == 35 and mj1.stats.best_time == 45,
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
expect(mj1.score == 65, "the six-tile chain/combo win scores 65 (10+25+30)")
expect(mj1.pairs_matched == 3, "the pair counter tracked the three matched pairs")
win_text = ctx.summaryText(ctx.last_confirm)
expect(win_text:find("Overall best score: 65 (New best!)", 1, true) ~= nil,
    "a new overall best score is marked New best!")
expect(win_text:find("Overall best time: 00:30 (New best!)", 1, true) ~= nil,
    "a new overall best time is marked New best!")
expect(win_text:find("Turtle best score: 65 (New best!)", 1, true) ~= nil,
    "a new layout best score is marked New best!")
expect(win_text:find("Turtle best time: 00:30 (New best!)", 1, true) ~= nil,
    "a new layout best time is marked New best!")
expect(mj1.stats.best_score == 65 and mj1.stats.best_time == 30,
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
expect(mj2.stats.games_won == 3 and mj2.stats.best_score == 65
        and mj2.stats.best_time == 30 and mj2.stats.current_streak == 0
        and mj2.stats.games_played == 3,
    "an auto-solve win leaves the loaded lifetime stats untouched")
expect(mj2.game_won == false, "an auto-solve win does not set the game_won flag")
win_text = ctx.summaryText(ctx.last_confirm)
expect(win_text:find("New best!", 1, true) == nil,
    "an auto-solve win never marks a New best!")
expect(win_text:find("Pairs matched: 2", 1, true) ~= nil,
    "the auto-solve win dialog still shows the pair count")
expect(win_text:find("Hints used: 1", 1, true) ~= nil,
    "the auto-solve win dialog shows hints used")
expect(win_text:find("Shuffles: 2", 1, true) ~= nil,
    "the auto-solve win dialog shows shuffles used")

-- Play again after an auto-solve win: a genuinely new game DOES bump
-- game_played (the auto-solve itself recorded nothing).
ctx.last_confirm.ok_callback()
pickTurtle() -- US-14: Play again shows the picker
expect(mj2.stats.games_played == 4, "Play again after an auto-solve starts a fresh game")
expect(mj2.game_won == false and mj2.game_was_autosolved == false,
    "a new game clears the game_won and auto-solved flags")

-- ---- Win that only breaks THIS layout's records headlines the layout variant ----

-- Seed global bests (100 / 00:10) that this win can't touch, but give Turtle a
-- weaker layout record (30 / 00:40). A 2-pair win scores 35 in 25s, so it beats
-- only Turtle's records — the headline must call out the layout, not the overall.
store.game = nil
store.stats = Stats.load{
    best_score = 100, best_time = 10,
    layout_highscores = { turtle = 30 },
    layout_best_times = { turtle = 40 },
}
local mjX = Mahjong:new()
setBoard(mjX, { {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"b1"}, {8,2,0,"b1"} })
mjX.elapsed_base = 25
playAndWin(mjX, 2)
win_text = ctx.summaryText(ctx.last_confirm)
expect(win_text:find("Congratulations! New best score and time on this layout!", 1, true) ~= nil,
    "a win that breaks only THIS layout's records headlines that layout")
expect(win_text:find("Congratulations! New overall", 1, true) == nil,
    "a layout-only record win does not headline the overall records")
expect(win_text:find("Turtle best score: 35 (New best!)", 1, true) ~= nil,
    "the layout score line marks the new layout best")
expect(win_text:find("Turtle best time: 00:25 (New best!)", 1, true) ~= nil,
    "the layout time line marks the new layout best")
expect(win_text:find("Overall best score: 100", 1, true) ~= nil,
    "the overall best score line is unchanged at 100")

if failures == 0 then
    print("\nALL US-12 STATS/SUMMARY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
