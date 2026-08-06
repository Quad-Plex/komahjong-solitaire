-- Mahjong Solitaire — lifetime statistics (pure Lua, no KOReader dependencies).
--
-- US-12: win summary + best-score/best-time tracking. A lifetime stats record
-- is a plain table with seven fields:
--   games_played     total games started (fresh deals only — the long-press
--                    auto-solver (US-19) never bumps this)
--   games_won        human-played wins (auto-solve wins do not count)
--   best_score       highest winning score (0 until the first win)
--   best_time        seconds of the fastest win; nil until the first win
--   total_time       cumulative seconds of all wins (for the average-time
--                    row on the US-13 stats screen)
--   current_streak   consecutive wins; reset to 0 by startGame() when the
--                    previous game was abandoned (not won)
--   longest_streak   all-time longest current_streak
--   layout_wins      map layout_id -> human-played wins on that layout (the
--                    layout picker's trophy badge reads it; auto-solve wins
--                    never count, matching games_won)
--
-- UI code only reaches in through defaults() / load() / startGame() /
-- recordWin() / recordLayoutWin(), so the record stays a plain serializable
-- table (LuaSettings writes it under its own "stats" key, separate from the
-- "game" key).
--
-- Self-test: `lua mahjongstats.lua` (or `lua mahjongstats.lua --selftest`).

local MahjongStats = {}

-- A fresh, zeroed record.
function MahjongStats.defaults()
    return {
        games_played = 0,
        games_won = 0,
        best_score = 0,
        best_time = nil, -- nil = no win yet (fastest-win seconds once set)
        total_time = 0, -- cumulative win seconds (average time per win)
        current_streak = 0,
        longest_streak = 0,
        layout_wins = {},
    }
end

-- Returns a valid record loaded from a saved LuaSettings value: anything that
-- is not a proper record (nil, a string, a table with missing/garbage fields)
-- silently falls back to defaults, so corrupt state never crashes or poisons
-- the lifetime numbers. Does not mutate `saved`.
function MahjongStats.load(saved)
    local stats = MahjongStats.defaults()
    if type(saved) ~= "table" then return stats end
    local num = function(v)
        if type(v) == "number" and v >= 0 then return v end
        return nil
    end
    stats.games_played = num(saved.games_played) or 0
    stats.games_won = num(saved.games_won) or 0
    stats.best_score = num(saved.best_score) or 0
    stats.best_time = num(saved.best_time)
    stats.total_time = num(saved.total_time) or 0
    stats.current_streak = num(saved.current_streak) or 0
    stats.longest_streak = num(saved.longest_streak) or 0
    -- layout_wins is a per-id win map; garbage entries are sanitized to
    -- non-negative integers (nil/0/garbage keys become absent, so the map
    -- only ever holds real layout ids -> wins).
    stats.layout_wins = {}
    if type(saved.layout_wins) == "table" then
        for id, n in pairs(saved.layout_wins) do
            if type(id) == "string" and type(n) == "number" and n >= 0 and n % 1 == 0 then
                stats.layout_wins[id] = n
            end
        end
    end
    return stats
end

-- Called when a NEW game begins (a fresh deal or a New Game). Bumps
-- games_played and, when the PREVIOUS game was abandoned (i.e. not won),
-- resets the current winning streak to 0. `previous_won` is the caller's
-- game_won flag for the game that just ended (nil on the very first game,
-- which is treated as not won).
function MahjongStats.startGame(stats, previous_won)
    stats.games_played = stats.games_played + 1
    if not previous_won then
        stats.current_streak = 0
    end
    return stats
end

-- Records a human-played win (auto-solve wins must never reach here — the UI
-- gates on its game_was_autosolved flag). Bumps games_won and the current
-- streak, tracks the longest streak, and updates the best-score/best-time
-- records. Returns (new_best_score, new_best_time) so the win summary can
-- mark the just-set records with "New best!". best_time is the FASTEST win,
-- so once set it only ever decreases; it stays nil until the first win.
-- `pairs` (the number of matched pairs in the winning game) is accepted for
-- forward-compatibility (a future stats screen may record it); it is not part
-- of the lifetime record today.
function MahjongStats.recordWin(stats, score, elapsed, pairs) -- luacheck: ignore 212
    stats.games_won = stats.games_won + 1
    stats.current_streak = stats.current_streak + 1
    if stats.current_streak > stats.longest_streak then
        stats.longest_streak = stats.current_streak
    end
    local new_best_score = score > (stats.best_score or 0)
    if new_best_score then
        stats.best_score = score
    end
    local new_best_time = elapsed ~= nil and (stats.best_time == nil or elapsed < stats.best_time)
    if new_best_time then
        stats.best_time = elapsed
    end
    -- Cumulative win time feeds the "Average time per win" row on the US-13
    -- stats screen (recordWin is only ever called for real wins).
    stats.total_time = (stats.total_time or 0) + (elapsed or 0)
    return new_best_score, new_best_time
end

-- Records a human-played win on a specific layout (the layout picker's trophy
-- badge). Shares recordWin's gating: the caller must NOT reach here for
-- auto-solve wins. Missing layout_wins maps degrade to zero wins.
function MahjongStats.recordLayoutWin(stats, layout_id)
    if type(layout_id) ~= "string" or layout_id == "" then return end
    if type(stats.layout_wins) ~= "table" then
        stats.layout_wins = {}
    end
    stats.layout_wins[layout_id] = (stats.layout_wins[layout_id] or 0) + 1
end

-- Self-tests ---------------------------------------------------------------

function MahjongStats.runSelfTests()
    local function check(cond, msg)
        if not cond then
            io.write("FAIL: ", msg, "\n")
            os.exit(1)
        end
        io.write("ok:   ", msg, "\n")
    end

    local s = MahjongStats.defaults()
    check(s.games_played == 0 and s.games_won == 0 and s.best_score == 0
        and s.best_time == nil and s.total_time == 0
        and s.current_streak == 0 and s.longest_streak == 0,
        "defaults() is zeroed with best_time nil")
    check(next(s.layout_wins) == nil,
        "defaults() has an empty layout_wins map")

    -- startGame bumps games_played; it only breaks the streak when the
    -- previous game was abandoned (not won).
    MahjongStats.startGame(s, true)
    check(s.games_played == 1 and s.current_streak == 0,
        "startGame bumps games_played (1)")
    MahjongStats.startGame(s, true)
    check(s.games_played == 2 and s.current_streak == 0,
        "startGame after a won game keeps the (zero) streak")

    -- recordWin updates every field and returns the new-best flags.
    local nb, nbt = MahjongStats.recordWin(s, 100, 90, 72)
    check(s.games_won == 1 and s.current_streak == 1 and s.longest_streak == 1,
        "recordWin bumps games_won / current_streak / longest_streak")
    check(s.best_score == 100 and s.best_time == 90,
        "the first win sets the best-score and best-time records")
    check(nb and nbt, "the first win reports both new bests")
    check(s.total_time == 90, "recordWin accumulates the win time (total_time)")

    -- A worse win never replaces the records.
    local nb2, nbt2 = MahjongStats.recordWin(s, 50, 120, 72)
    check(s.best_score == 100 and s.best_time == 90,
        "a worse win keeps the records")
    check(not nb2 and not nbt2, "a worse win reports no new bests")
    check(s.games_won == 2 and s.current_streak == 2 and s.longest_streak == 2,
        "a worse win still counts and extends the streak")
    check(s.total_time == 210, "total_time sums every win's elapsed seconds")

    -- best_time only ever decreases; equal score/time do not replace.
    local nb3, nbt3 = MahjongStats.recordWin(s, 100, 60, 72)
    check(s.best_score == 100 and s.best_time == 60,
        "an equal score with a faster time updates only the best time")
    check(not nb3 and nbt3, "only the time reports a new best")
    local nb4, nbt4 = MahjongStats.recordWin(s, 100, 60, 72)
    check(s.best_score == 100 and s.best_time == 60,
        "an equal score and time replace nothing")
    check(not nb4 and not nbt4, "an equal record reports no new bests")

    -- A higher score with a slower time updates only the best score.
    local nb5, nbt5 = MahjongStats.recordWin(s, 150, 120, 72)
    check(s.best_score == 150 and s.best_time == 60,
        "a higher score with a slower time updates only the best score")
    check(nb5 and not nbt5, "only the score reports a new best")

    -- Streak: consecutive wins increment; an abandoned game resets the streak
    -- but keeps the longest-streak peak.
    MahjongStats.startGame(s, true)
    check(s.current_streak == 5 and s.longest_streak == 5,
        "a new game after a win keeps the streak")
    MahjongStats.recordWin(s, 10, 10, 72)
    check(s.current_streak == 6 and s.longest_streak == 6,
        "the streak keeps climbing across consecutive wins")
    MahjongStats.startGame(s, false)
    check(s.current_streak == 0 and s.longest_streak == 6,
        "an abandoned game resets the streak but not the longest streak")
    MahjongStats.startGame(s, nil)
    check(s.current_streak == 0,
        "a missing previous result is treated as abandoned")
    MahjongStats.recordWin(s, 10, 10, 72)
    check(s.current_streak == 1,
        "a win after a reset restarts the streak at 1")

    -- load(): garbage falls back to defaults, valid records come back intact,
    -- corrupt fields are sanitized, and the saved table is never mutated.
    check(MahjongStats.load(nil).games_played == 0
        and MahjongStats.load("garbage").games_played == 0
        and MahjongStats.load({}).games_played == 0,
        "load() falls back to defaults for nil/garbage/empty input")
    local good = MahjongStats.load{ games_played = 9, games_won = 4, best_score = 40,
        best_time = 30, total_time = 300, current_streak = 3, longest_streak = 3 }
    check(good.games_played == 9 and good.games_won == 4 and good.best_score == 40
        and good.best_time == 30 and good.total_time == 300
        and good.current_streak == 3 and good.longest_streak == 3,
        "load() keeps a valid record intact")
    local saved = { games_played = 9, games_won = 4, best_score = 40, best_time = 30,
        total_time = 300, current_streak = 3, longest_streak = 3 }
    MahjongStats.load(saved)
    check(saved.games_played == 9, "load() does not mutate the saved table")
    local bad = MahjongStats.load{ games_played = -1, games_won = "x", best_score = nil,
        best_time = -5, total_time = "y", current_streak = "nope", longest_streak = -3 }
    check(bad.games_played == 0 and bad.games_won == 0 and bad.best_score == 0
        and bad.best_time == nil and bad.total_time == 0
        and bad.current_streak == 0 and bad.longest_streak == 0,
        "load() sanitizes invalid fields to defaults")
    check(MahjongStats.load{ games_played = 5 }.best_time == nil,
        "load() keeps best_time nil when the saved record has no best time")
    check(MahjongStats.load{ games_played = 5 }.total_time == 0,
        "load() defaults total_time when a pre-US-13 record lacks it")

    -- layout_wins: recordLayoutWin bumps per-layout counters; it is
    -- sanitized by load() and degrades gracefully for records without it.
    local lw = MahjongStats.defaults()
    MahjongStats.recordLayoutWin(lw, "turtle")
    MahjongStats.recordLayoutWin(lw, "turtle")
    MahjongStats.recordLayoutWin(lw, "spider")
    check(lw.layout_wins.turtle == 2 and lw.layout_wins.spider == 1,
        "recordLayoutWin bumps the per-layout win counters")
    MahjongStats.recordLayoutWin(lw, nil)
    MahjongStats.recordLayoutWin(lw, "")
    check(lw.layout_wins.turtle == 2 and lw.layout_wins.spider == 1,
        "recordLayoutWin ignores nil/empty layout ids")
    local lw2 = MahjongStats.defaults()
    lw2.layout_wins = nil
    MahjongStats.recordLayoutWin(lw2, "turtle")
    check(lw2.layout_wins ~= nil and lw2.layout_wins.turtle == 1,
        "recordLayoutWin recreates a missing layout_wins map")
    local lw3 = MahjongStats.load{ layout_wins = { turtle = 3, spider = "x", ziggurat = -1, [5] = 2 } }
    check(lw3.layout_wins.turtle == 3 and lw3.layout_wins.spider == nil
        and lw3.layout_wins.ziggurat == nil and lw3.layout_wins[5] == nil,
        "load() keeps valid layout_wins entries and drops garbage")
    check(next(MahjongStats.load(nil).layout_wins) == nil
        and next(MahjongStats.load("garbage").layout_wins) == nil,
        "load() defaults layout_wins for non-table records")

    io.write("All self-tests passed.\n")
    return true
end

-- Run self-tests when executed directly (`lua mahjongstats.lua`) or with
-- `lua mahjongstats.lua --selftest`.
-- luacheck: no unused args
if select("#", ...) == 0 then
    MahjongStats.runSelfTests()
end

return MahjongStats
