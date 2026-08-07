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
--   layout_wins      layout per_id -> human-played wins on that layout (the
--                    layout picker's trophy badge reads it; auto-solve wins
--                    never count, matching games_won)
--   layout_highscores map layout_id -> best winning score on that layout (the
--                    layout picker's score chip reads it; auto-solve wins
--                    never count, matching layout_wins)
--   layout_best_times map layout_id -> fastest (fewest-seconds) winning time on
--                    that layout (the layout picker's time chip reads it,
--                    formatted mm:ss; auto-solve wins never count, matching
--                    layout_wins). For a layout with no win yet it stays nil,
--                    so a never-won layout shows no time chip.
--   layout_played    map layout_id -> games started on that layout (the US-13
--                    stats screen's <layout> column reads it; bumped by
--                    startGame() alongside games_played)
--   layout_current_streaks / layout_longest_streaks
--                    map layout_id -> consecutive wins on that layout / that
--                    layout's all-time peak (the <layout> column's streak
--                    rows). A per-layout streak only changes when a game on
--                    THAT layout starts (resets on abandon) or wins
--                    (increments); games on other layouts leave it untouched.
--   layout_total_times map layout_id -> cumulative winning seconds on that
--                    layout (feeds the <layout> column's average-time row,
--                    mirroring the global total_time)
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
        layout_highscores = {},
        layout_best_times = {},
        layout_played = {},
        layout_current_streaks = {},
        layout_longest_streaks = {},
        layout_total_times = {},
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
    -- layout_highscores is a per-id best-score map, sanitized like layout_wins
    -- (non-negative numbers; garbage keys become absent). Old records saved
    -- before this map existed default to {}.
    stats.layout_highscores = {}
    if type(saved.layout_highscores) == "table" then
        for id, n in pairs(saved.layout_highscores) do
            if type(id) == "string" and type(n) == "number" and n >= 0 then
                stats.layout_highscores[id] = n
            end
        end
    end
    -- layout_best_times is a per-id fastest-win-seconds map, sanitized like
    -- layout_highscores (non-negative numbers; garbage keys become absent). Old
    -- records saved before this map existed default to {}.
    stats.layout_best_times = {}
    if type(saved.layout_best_times) == "table" then
        for id, n in pairs(saved.layout_best_times) do
            if type(id) == "string" and type(n) == "number" and n >= 0 then
                stats.layout_best_times[id] = n
            end
        end
    end
    -- layout_played / layout_current_streaks / layout_longest_streaks /
    -- layout_total_times are per-layout counters, sanitized like the maps
    -- above (non-negative integers; garbage keys become absent). Old records
    -- saved before these maps existed default to {}.
    stats.layout_played = {}
    if type(saved.layout_played) == "table" then
        for id, n in pairs(saved.layout_played) do
            if type(id) == "string" and type(n) == "number" and n >= 0 and n % 1 == 0 then
                stats.layout_played[id] = n
            end
        end
    end
    stats.layout_current_streaks = {}
    if type(saved.layout_current_streaks) == "table" then
        for id, n in pairs(saved.layout_current_streaks) do
            if type(id) == "string" and type(n) == "number" and n >= 0 and n % 1 == 0 then
                stats.layout_current_streaks[id] = n
            end
        end
    end
    stats.layout_longest_streaks = {}
    if type(saved.layout_longest_streaks) == "table" then
        for id, n in pairs(saved.layout_longest_streaks) do
            if type(id) == "string" and type(n) == "number" and n >= 0 and n % 1 == 0 then
                stats.layout_longest_streaks[id] = n
            end
        end
    end
    stats.layout_total_times = {}
    if type(saved.layout_total_times) == "table" then
        for id, n in pairs(saved.layout_total_times) do
            if type(id) == "string" and type(n) == "number" and n >= 0 then
                stats.layout_total_times[id] = n
            end
        end
    end
    return stats
end

-- Called when a NEW game begins (a fresh deal or a New Game). Bumps
-- games_played and, when the PREVIOUS game was abandoned (i.e. not won),
-- resets the current winning streak to 0. `previous_won` is the caller's
-- game_won flag for the game that just ended (nil on the very first game,
-- which is treated as not won). The optional `layout_id` also bumps that
-- layout's games-started counter and resets that layout's current streak on
-- an abandoned game — the stats screen's <layout> column mirror of the global
-- counters. A nil/empty layout_id keeps the old global-only behavior, so
-- legacy two-argument callers stay byte-identical.
function MahjongStats.startGame(stats, previous_won, layout_id)
    stats.games_played = stats.games_played + 1
    if not previous_won then
        stats.current_streak = 0
    end
    if type(layout_id) == "string" and layout_id ~= "" then
        if type(stats.layout_played) ~= "table" then
            stats.layout_played = {}
        end
        stats.layout_played[layout_id] = (stats.layout_played[layout_id] or 0) + 1
        if not previous_won then
            if type(stats.layout_current_streaks) ~= "table" then
                stats.layout_current_streaks = {}
            end
            stats.layout_current_streaks[layout_id] = 0
        end
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
-- auto-solve wins. Missing layout_wins maps degrade to zero wins. Also bumps
-- the layout's current/longest streak and accumulates the layout's total win
-- time (the stats screen's <layout> column rows). The optional `score` also
-- records the layout's best winning score (the picker's score chip) and the
-- optional `elapsed` (seconds) remembers the layout's fastest winning time
-- (the picker's mm:ss time chip) — auto-solve wins never set either, matching
-- the win counter. Passing nil/omitting any keeps the win counter behavior so
-- existing two-argument callers stay valid. Returns (new_layout_score,
-- new_layout_time) — whether THIS win set a new per-layout best for each, so
-- the win summary can mark the just-set records.
function MahjongStats.recordLayoutWin(stats, layout_id, score, elapsed)
    if type(layout_id) ~= "string" or layout_id == "" then return false, false end
    if type(stats.layout_wins) ~= "table" then
        stats.layout_wins = {}
    end
    stats.layout_wins[layout_id] = (stats.layout_wins[layout_id] or 0) + 1
    -- Per-layout streaks mirror the global ones: a win here bumps this
    -- layout's current streak and its all-time peak (games on OTHER layouts
    -- never touch it). The layout_current_streaks map is only reset by
    -- startGame() on an abandoned game of THIS layout.
    if type(stats.layout_current_streaks) ~= "table" then
        stats.layout_current_streaks = {}
    end
    local cur = (stats.layout_current_streaks[layout_id] or 0) + 1
    stats.layout_current_streaks[layout_id] = cur
    if type(stats.layout_longest_streaks) ~= "table" then
        stats.layout_longest_streaks = {}
    end
    if cur > (stats.layout_longest_streaks[layout_id] or 0) then
        stats.layout_longest_streaks[layout_id] = cur
    end
    -- Cumulative winning seconds on this layout feed the <layout> column's
    -- average-time-per-win row (mirroring the global total_time).
    if type(elapsed) == "number" and elapsed >= 0 then
        if type(stats.layout_total_times) ~= "table" then
            stats.layout_total_times = {}
        end
        stats.layout_total_times[layout_id] =
            (stats.layout_total_times[layout_id] or 0) + elapsed
    end
    local new_layout_score, new_layout_time = false, false
    if type(score) == "number" and score >= 0 then
        if type(stats.layout_highscores) ~= "table" then
            stats.layout_highscores = {}
        end
        if score > (stats.layout_highscores[layout_id] or 0) then
            stats.layout_highscores[layout_id] = score
            new_layout_score = true
        end
    end
    if type(elapsed) == "number" and elapsed >= 0 then
        if type(stats.layout_best_times) ~= "table" then
            stats.layout_best_times = {}
        end
        local prev = stats.layout_best_times[layout_id]
        if prev == nil or elapsed < prev then
            stats.layout_best_times[layout_id] = elapsed
            new_layout_time = true
        end
    end
    return new_layout_score, new_layout_time
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
    check(next(s.layout_highscores) == nil,
        "defaults() has an empty layout_highscores map")
    check(next(s.layout_best_times) == nil,
        "defaults() has an empty layout_best_times map")
    check(next(s.layout_played) == nil
        and next(s.layout_current_streaks) == nil
        and next(s.layout_longest_streaks) == nil
        and next(s.layout_total_times) == nil,
        "defaults() has empty per-layout counter maps")

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

    -- layout_highscores: recordLayoutWin(id, score) records the best winning
    -- score per layout; a lower score never replaces the record, and a
    -- two-argument call (score omitted) still bumps the win counter without
    -- touching the highscore. It returns which per-layout record THIS win set.
    local hs = MahjongStats.defaults()
    local hs_s1, hs_t1 = MahjongStats.recordLayoutWin(hs, "turtle", 100)
    check(hs.layout_highscores.turtle == 100 and hs.layout_wins.turtle == 1,
        "recordLayoutWin(id, score) sets the layout highscore")
    check(hs_s1 and not hs_t1,
        "a scored win with no elapsed reports a new layout score, not time")
    local hs_s2, hs_t2 = MahjongStats.recordLayoutWin(hs, "turtle", 50)
    local hs_s3, hs_t3 = MahjongStats.recordLayoutWin(hs, "turtle", 150)
    check(hs.layout_highscores.turtle == 150,
        "a lower win never replaces the layout highscore")
    check(not hs_s2 and not hs_t2 and hs.layout_wins.turtle == 3,
        "a lower layout score is not a new layout best and sets no time")
    check(hs_s3 and not hs_t3, "a higher layout score reports a new layout best")
    MahjongStats.recordLayoutWin(hs, "spider")
    check(hs.layout_highscores.spider == nil and hs.layout_wins.spider == 1,
        "a two-argument recordLayoutWin bumps wins but not the highscore")
    MahjongStats.recordLayoutWin(hs, nil, 50)
    MahjongStats.recordLayoutWin(hs, "", 50)
    check(hs.layout_highscores.turtle == 150 and hs.layout_wins.turtle == 3,
        "recordLayoutWin ignores nil/empty layout ids for both maps")
    local hs2 = MahjongStats.defaults()
    hs2.layout_highscores = nil
    MahjongStats.recordLayoutWin(hs2, "turtle", 42)
    check(hs2.layout_highscores ~= nil and hs2.layout_highscores.turtle == 42,
        "recordLayoutWin recreates a missing layout_highscores map")
    local hs3 = MahjongStats.load{ layout_highscores = { turtle = 300, spider = "x", ziggurat = -1, [5] = 2 } }
    check(hs3.layout_highscores.turtle == 300 and hs3.layout_highscores.spider == nil
        and hs3.layout_highscores.ziggurat == nil and hs3.layout_highscores[5] == nil,
        "load() keeps valid layout_highscores entries and drops garbage")
    check(next(MahjongStats.load(nil).layout_highscores) == nil
        and next(MahjongStats.load("garbage").layout_highscores) == nil,
        "load() defaults layout_highscores for non-table records")
    local old_record = MahjongStats.load{ games_played = 5, layout_wins = { turtle = 1 } }
    check(old_record.layout_highscores ~= nil and next(old_record.layout_highscores) == nil,
        "load() defaults layout_highscores for pre-feature records")
    MahjongStats.recordLayoutWin(old_record, "turtle", 77)
    check(old_record.layout_highscores.turtle == 77,
        "a pre-feature record gains a highscore after its first scored win")

    -- layout_best_times: recordLayoutWin(id, score, elapsed) keeps the fastest
    -- winning time per layout (only ever decreasing); a missing/Slower/equal
    -- time never replaces the record, and a call without elapsed touches
    -- nothing. It returns whether THIS win set a new layout time record.
    local bt = MahjongStats.defaults()
    local bt_s1, bt_t1 = MahjongStats.recordLayoutWin(bt, "turtle", 100, 300)
    check(bt.layout_best_times.turtle == 300,
        "recordLayoutWin(id, score, elapsed) sets the layout best time")
    check(bt_s1 and bt_t1, "a scored+timed win reports new layout score and time")
    local bt_s2, bt_t2 = MahjongStats.recordLayoutWin(bt, "turtle", 100, 120)
    local bt_s3, bt_t3 = MahjongStats.recordLayoutWin(bt, "turtle", 100, 200)
    check(bt.layout_best_times.turtle == 120,
        "a faster win replaces the layout best time; a slower one does not")
    check(not bt_s2 and bt_t2 and not bt_s3 and not bt_t3,
        "only the faster win reports a new layout time; an equal/lower score sets no record")
    MahjongStats.recordLayoutWin(bt, "spider", 50)
    check(bt.layout_best_times.spider == nil,
        "a two-argument recordLayoutWin does not set a layout best time")
    MahjongStats.recordLayoutWin(bt, "", 50, 60)
    MahjongStats.recordLayoutWin(bt, nil, 50, 60)
    check(bt.layout_best_times.turtle == 120,
        "recordLayoutWin ignores nil/empty layout ids for best times")
    local bt2 = MahjongStats.defaults()
    bt2.layout_best_times = nil
    MahjongStats.recordLayoutWin(bt2, "turtle", 100, 42)
    check(bt2.layout_best_times ~= nil and bt2.layout_best_times.turtle == 42,
        "recordLayoutWin recreates a missing layout_best_times map")
    local bt3 = MahjongStats.load{ layout_best_times = { turtle = 300, spider = "x", ziggurat = -1, [5] = 2 } }
    check(bt3.layout_best_times.turtle == 300 and bt3.layout_best_times.spider == nil
        and bt3.layout_best_times.ziggurat == nil and bt3.layout_best_times[5] == nil,
        "load() keeps valid layout_best_times entries and drops garbage")
    check(next(MahjongStats.load(nil).layout_best_times) == nil
        and next(MahjongStats.load("garbage").layout_best_times) == nil,
        "load() defaults layout_best_times for non-table records")
    local old_bt = MahjongStats.load{ games_played = 5, layout_wins = { turtle = 1 } }
    check(old_bt.layout_best_times ~= nil and next(old_bt.layout_best_times) == nil,
        "load() defaults layout_best_times for pre-feature records")
    MahjongStats.recordLayoutWin(old_bt, "turtle", 100, 77)
    check(old_bt.layout_best_times.turtle == 77,
        "a pre-feature record gains a best time after its first timed win")

    -- Per-layout played/streaks/total_times (US-13 <layout> column):
    -- startGame() bumps a valid layout's started counter and resets its streak
    -- on an abandoned game; other layouts are untouched; a nil/empty layout
    -- id keeps the global-only behavior.
    local pl = MahjongStats.defaults()
    MahjongStats.startGame(pl, false, "turtle")
    MahjongStats.startGame(pl, true, "turtle")
    MahjongStats.startGame(pl, true, "spider")
    check(pl.layout_played.turtle == 2 and pl.layout_played.spider == 1,
        "startGame(id) bumps the per-layout started counters")
    check(pl.layout_current_streaks.turtle == 0,
        "an abandoned first turtle game resets the turtle streak")
    MahjongStats.startGame(pl, nil, "")
    MahjongStats.startGame(pl, nil, nil)
    check(pl.layout_played.turtle == 2 and pl.layout_played.spider == 1,
        "startGame ignores nil/empty layout ids")
    MahjongStats.startGame(pl, false)
    check(pl.layout_played.turtle == 2 and pl.layout_played.spider == 1,
        "a two-argument startGame keeps the global-only behavior")

    -- recordLayoutWin bumps the per-layout current/longest streak and
    -- accumulates the per-layout total time (feeding avg-time-per-win).
    local pst = MahjongStats.defaults()
    MahjongStats.startGame(pst, false, "turtle")
    MahjongStats.recordLayoutWin(pst, "turtle", 100, 300)
    MahjongStats.recordLayoutWin(pst, "turtle", 50, 120)
    MahjongStats.recordLayoutWin(pst, "spider")
    check(pst.layout_current_streaks.turtle == 2
        and pst.layout_longest_streaks.turtle == 2,
        "two turtle wins push the layout current/longest streak to 2")
    check(pst.layout_current_streaks.spider == 1
        and pst.layout_longest_streaks.spider == 1,
        "an unscored spider win still bumps its streak")
    check(pst.layout_total_times.turtle == 420,
        "recordLayoutWin accumulates the turtle win time (420)")
    check(pst.layout_total_times.spider == nil,
        "an unscored win records no total time")
    MahjongStats.recordLayoutWin(pst, "", 10, 60)
    MahjongStats.recordLayoutWin(pst, nil, 10, 60)
    check(pst.layout_total_times.turtle == 420 and pst.layout_current_streaks.turtle == 2,
        "recordLayoutWin ignores nil/empty layout ids for streak/time")
    local pst2 = MahjongStats.defaults()
    pst2.layout_current_streaks = nil
    pst2.layout_longest_streaks = nil
    pst2.layout_total_times = nil
    MahjongStats.recordLayoutWin(pst2, "turtle", 50, 42)
    check(pst2.layout_current_streaks ~= nil and pst2.layout_current_streaks.turtle == 1
        and pst2.layout_longest_streaks ~= nil and pst2.layout_longest_streaks.turtle == 1
        and pst2.layout_total_times ~= nil and pst2.layout_total_times.turtle == 42,
        "recordLayoutWin recreates missing per-layout streak/time maps")

    -- load() sanitizes the four new per-layout maps like the existing ones;
    -- pre-feature records default to empty maps and never mutate `saved`.
    local pl_san = MahjongStats.load{
        layout_played = { turtle = 3, spider = "x", [5] = 2 },
        layout_current_streaks = { turtle = 2, spider = -1 },
        layout_longest_streaks = { turtle = 4, spider = "y" },
        layout_total_times = { turtle = 600, spider = -1, [5] = 99 },
    }
    check(pl_san.layout_played.turtle == 3 and pl_san.layout_played.spider == nil
        and pl_san.layout_played[5] == nil,
        "load() keeps valid layout_played entries and drops garbage")
    check(pl_san.layout_current_streaks.turtle == 2 and pl_san.layout_current_streaks.spider == nil,
        "load() drops negative layout streaks")
    check(pl_san.layout_longest_streaks.turtle == 4 and pl_san.layout_longest_streaks.spider == nil,
        "load() drops non-number layout streaks")
    check(pl_san.layout_total_times.turtle == 600 and pl_san.layout_total_times.spider == nil
        and pl_san.layout_total_times[5] == nil,
        "load() keeps valid layout_total_times entries and drops garbage")
    local old_pl = MahjongStats.load{ games_played = 5, layout_wins = { turtle = 1 } }
    check(next(old_pl.layout_played) == nil and next(old_pl.layout_current_streaks) == nil
        and next(old_pl.layout_longest_streaks) == nil and next(old_pl.layout_total_times) == nil,
        "load() defaults the four new maps for pre-feature records")
    MahjongStats.startGame(old_pl, false, "turtle")
    MahjongStats.recordLayoutWin(old_pl, "turtle", 77, 55)
    check(old_pl.layout_played.turtle == 1 and old_pl.layout_total_times.turtle == 55,
        "a pre-feature record gains per-layout counters after its first game/win")

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
