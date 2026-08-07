-- US-13 stats-screen suite: the dedicated Stats button on the HUD opens a
-- floating card showing the lifetime stats in two columns — a "Global" column
-- (the all-layouts record) and a "<layout>" column (the currently played
-- layout's per-layout record). Reset zeroes both columns (only after a
-- confirm); tap-outside / the close X close the card and resume the paused
-- timer.
--
-- Checks:
--   * The HudBar exposes the new `left_icons` API (one button per entry) while
--     the legacy single `left_icon` fields still build a working button;
--   * startGame's HUD carries two left buttons (settings gear + stats), and
--     the Stats button opens the stats card;
--   * openStats pauses the timer loop (like openSettings) and any close
--     resumes it;
--   * The card shows two columns: a Global column (games/wins/rate/bests/
--     average time/streaks) and a <layout> column mirroring the same rows from
--     the per-layout maps;
--   * Reset clears the whole record (global + per-layout maps) only after a
--     ConfirmBox, persists it, and re-renders both columns;
--   * The card is a floating transparent-window pattern with an onShow
--     panel-region refresh (like the settings dialog).

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Stats = ctx.loadPlugin("mahjongstats")
local HudBar = ctx.loadPlugin("hudbar")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store

-- US-14: startGame with no saved game shows the layout picker; pick Turtle.
local function pickTurtle()
    local picker = ctx.window_stack[#ctx.window_stack].widget
    if not picker or picker.name ~= "mahjonglayoutselect" then return end
    local r
    for _, c in ipairs(picker._card_rects) do
        if c.id == "turtle" then r = c break end
    end
    picker:onTapSelect(nil, { pos = { x = r.x + r.w / 2, y = r.y + r.h / 2 } })
    ctx.runScheduled() -- US-30: the picker deals on a deferred tick (flush it)
end

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

-- ---- HudBar left-button API ----------------------------------------------------

-- Legacy single left_icon still builds one left button.
local legacy = HudBar:new{
    title = "T",
    left_icon = "appbar.settings",
    left_icon_tap_callback = function() return "settings" end,
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() return "close" end,
}
expect(type(legacy._left_buttons) == "table" and #legacy._left_buttons == 1,
    "legacy left_icon builds one left button")
expect(legacy._left_buttons[1].icon == "appbar.settings"
        and legacy._left_buttons[1].callback() == "settings",
    "the legacy left button keeps its icon and callback")

-- The new left_icons list builds one square button per entry.
local multi = HudBar:new{
    title = "T",
    left_icons = {
        { icon = "appbar.settings", size_ratio = 0.45, callback = function() return "settings" end },
        { icon = "mahjong/stats",   size_ratio = 0.45, callback = function() return "stats" end },
    },
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() return "close" end,
}
expect(#multi._left_buttons == 2, "left_icons builds one button per entry")
expect(multi._left_buttons[2].icon == "mahjong/stats"
        and multi._left_buttons[2].callback() == "stats",
    "the second left button is the Stats button with its callback")
expect(multi._left_buttons[1].height == multi.HUD_H
        and multi._left_buttons[2].height == multi.HUD_H,
    "left buttons take the full HUD height")
expect(multi._left_buttons[1].width == math.floor(multi.HUD_H * 0.6)
        and multi._left_buttons[2].width == math.floor(multi.HUD_H * 0.6),
    "left buttons are narrower than tall so a pair sits close together")

-- ---- main.lua wiring: the HUD's Stats button opens the card --------------------

local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
pickTurtle()
expect(mj.status_bar ~= nil and mj.status_bar.name == "hudbar",
    "startGame builds the HUD bar")
expect(#mj.status_bar._left_buttons == 2,
    "the HUD carries two left buttons (settings gear + stats)")
expect(mj.status_bar._left_buttons[1].icon == "appbar.settings"
        and mj.status_bar._left_buttons[2].icon == "mahjong/stats",
    "the left buttons are the settings gear and the stats button")

-- A bar with no left controls still has no left buttons (hud_bar compat).
local bare = HudBar:new{
    title = "T",
    right_icon = "mahjong/close",
    right_icon_tap_callback = function() return "close" end,
}
expect(#bare._left_buttons == 0, "a bar without left controls has no left buttons")

-- Open the stats card: it pauses the timer and becomes the top widget.
ctx.last_confirm = nil
mj.status_bar._left_buttons[2].callback()
expect(mj._timer_running == false, "openStats pauses the timer loop")
local top = ctx.window_stack[#ctx.window_stack]
expect(top ~= nil and top.widget ~= nil and top.widget.name == "mahjongstatswidget",
    "the Stats button opens the stats card")
local dlg = top.widget

-- ---- The card lists the persisted lifetime stats -------------------------------

mj.stats.games_played = 10
mj.stats.games_won = 4
mj.stats.best_score = 340
mj.stats.best_time = 95
mj.stats.total_time = 480
mj.stats.current_streak = 2
mj.stats.longest_streak = 3
-- Per-layout data for the <layout> (Turtle) column. Deliberately distinct from
-- the global numbers so the two columns read independently.
mj.stats.layout_played = { turtle = 6 }
mj.stats.layout_wins = { turtle = 3 }
mj.stats.layout_highscores = { turtle = 300 }
mj.stats.layout_best_times = { turtle = 200 }
mj.stats.layout_total_times = { turtle = 240 }
mj.stats.layout_current_streaks = { turtle = 2 }
mj.stats.layout_longest_streaks = { turtle = 3 }
mj:saveStats()

-- Close the card and reopen it so it snapshots the new record.
dlg:onTapClose(nil, { pos = { notIntersectWith = function() return true end } })
expect(mj._timer_running == true, "tap-outside close resumes the timer loop")
mj.status_bar._left_buttons[2].callback()
dlg = ctx.window_stack[#ctx.window_stack].widget

-- ---- Two columns: Global (left) and <layout name> (right) ----------------------

-- dlg[1] = center container, [1] = panel (Frame), [1] of that = the content
-- VerticalGroup; its child at [3] is the HorizontalGroup holding the two
-- columns ({global_col, span, map_col}).
local global_col = dlg[1][1][1][3][1]
local map_col = dlg[1][1][1][3][3]
expect(global_col ~= nil and map_col ~= nil and dlg[1][1][1][3][2] ~= nil,
    "the panel holds a two-column HorizontalGroup (col, gap, col)")
expect(global_col[1][2].text == "Global", "the left column is headed 'Global'")
expect(map_col[1][2].text == "Turtle", "the right column is headed by the layout name")

expect(dlg._values.played.text == "10", "card shows Games played")
expect(dlg._values.won.text == "4", "card shows Games won")
expect(dlg._values.win_rate.text == "40%", "card shows the win rate (4/10)")
expect(dlg._values.best_score.text == "340", "card shows Best score")
expect(dlg._values.best_time.text == "01:35", "card shows Best time (95 s)")
expect(dlg._values.avg_time.text == "02:00", "card shows Average time per win (480/4)")
expect(dlg._values.current_streak.text == "2", "card shows Current streak")
expect(dlg._values.longest_streak.text == "3", "card shows Longest streak")

-- The Turtle column mirrors the same rows from the per-layout maps.
expect(dlg._values.map_played.text == "6", "map column shows Games played on the layout")
expect(dlg._values.map_won.text == "3", "map column shows Games won on the layout")
expect(dlg._values.map_win_rate.text == "50%", "map column shows the win rate (3/6)")
expect(dlg._values.map_best_score.text == "300", "map column shows Best score on the layout")
expect(dlg._values.map_best_time.text == "03:20", "map column shows Best time (200 s)")
expect(dlg._values.map_avg_time.text == "01:20", "map column shows Average time per win (240/3)")
expect(dlg._values.map_current_streak.text == "2", "map column shows Current streak on the layout")
expect(dlg._values.map_longest_streak.text == "3", "map column shows Longest streak on the layout")

-- ---- Floating-card structure + onShow refresh ----------------------------------

expect(dlg.background == nil, "the stats card's outer widget is transparent (floating)")
expect(dlg.covers_fullscreen == true, "the stats card is a full-screen modal wrapper")
expect(type(dlg[1]) == "table" and type(dlg[1].dimen) == "table",
    "the card's single child is a centering container")
local panel = dlg[1][1]
expect(type(panel) == "table" and panel.background == "white"
        and panel.bordersize ~= nil and panel.radius ~= nil,
    "the centered panel is a bordered white card")
expect(type(dlg._panel_geom) == "table" and type(dlg._panel_geom.w) == "number"
        and type(dlg._panel_geom.h) == "number",
    "the panel's screen rect is exposed for the tap-outside test")
expect(dlg._close_btn ~= nil and type(dlg._close_btn.icon) == "string"
        and type(dlg._close_btn.callback) == "function",
    "the panel has a close X button")
expect(type(dlg._reset_btn) == "table" and type(dlg._reset_btn.callback) == "function",
    "the panel has a Reset button")

local show_dirty = #ctx.dirty_calls
dlg:onShow()
local refresh_fn_queued = false
for i = show_dirty + 1, #ctx.dirty_calls do
    if ctx.dirty_calls[i].widget == dlg and type(ctx.dirty_calls[i].refreshtype) == "function" then
        refresh_fn_queued = true
    end
end
expect(refresh_fn_queued, "onShow enqueues a refresh function for the panel")

-- ---- Reset zeroes the record only after a confirm ------------------------------

ctx.last_confirm = nil
dlg._reset_btn.callback()
expect(ctx.last_confirm ~= nil
        and tostring(ctx.last_confirm.text):find("Reset", 1, true) ~= nil,
    "Reset asks for confirmation first")
expect(mj.stats.games_played == 10 and mj.stats.best_time == 95,
    "stats are unchanged before the confirm")
ctx.last_confirm.ok_callback()
expect(mj.stats.games_played == 0 and mj.stats.games_won == 0
        and mj.stats.best_score == 0 and mj.stats.best_time == nil
        and mj.stats.total_time == 0 and mj.stats.current_streak == 0
        and mj.stats.longest_streak == 0,
    "confirming Reset zeroes the record back to defaults")
expect(next(mj.stats.layout_played) == nil and next(mj.stats.layout_wins) == nil
        and next(mj.stats.layout_highscores) == nil and next(mj.stats.layout_best_times) == nil
        and next(mj.stats.layout_total_times) == nil
        and next(mj.stats.layout_current_streaks) == nil
        and next(mj.stats.layout_longest_streaks) == nil,
    "confirming Reset wipes the per-layout maps too")
expect(store.stats ~= nil and store.stats.games_played == 0
        and store.stats.games_won == 0,
    "Reset persists the zeroed record")
expect(dlg._values.played.text == "0" and dlg._values.won.text == "0"
        and dlg._values.best_score.text == "0",
    "the card re-renders the zeroed values")
expect(dlg._values.best_time.text == "—" and dlg._values.avg_time.text == "—"
        and dlg._values.win_rate.text == "—",
    "no best/average/rate yet: the card shows dashes")
expect(dlg._values.map_played.text == "0" and dlg._values.map_won.text == "0"
        and dlg._values.map_best_score.text == "0",
    "the map column re-renders its zeroed counts")
expect(dlg._values.map_best_time.text == "—" and dlg._values.map_avg_time.text == "—"
        and dlg._values.map_win_rate.text == "—",
    "the map column shows dashes where nothing is recorded")

-- ---- Tap-outside and the close X both close the card ---------------------------

expect(mj._timer_running == false, "the card holds the timer paused after reset")
dlg:onTapClose(nil, { pos = { notIntersectWith = function() return true end } })
local closed = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg then closed = false end
end
expect(closed, "a tap outside the card closes it")
expect(mj._timer_running == true, "closing the card resumes the timer loop")

-- Reopen and close via the panel's X.
mj.status_bar._left_buttons[2].callback()
dlg = ctx.window_stack[#ctx.window_stack].widget
expect(mj._timer_running == false, "reopening the card pauses the timer again")
dlg._close_btn.callback()
local x_closed = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg then x_closed = false end
end
expect(x_closed, "the panel's close X closes the card")
expect(mj._timer_running == true, "the close X resumes the timer too")

-- ---- Win-rate / average-time edge cases (no games yet) -------------------------

local mj2 = Mahjong:new()
mj2.board = Logic.newGame(5)
mj2:buildUILayout()
expect(mj2.stats.games_played == 0 and mj2.stats.games_won == 0,
    "a fresh (not-yet-started) instance has zero games")
mj2:openStats()
local dlg2 = ctx.window_stack[#ctx.window_stack].widget
expect(dlg2._values.win_rate.text == "—" and dlg2._values.avg_time.text == "—"
        and dlg2._values.best_time.text == "—",
    "with no games, rate / average time / best time show dashes")
dlg2:onTapClose(nil, { pos = { notIntersectWith = function() return true end } })

if failures == 0 then
    print("\nALL US-13 STATS-SCREEN CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
