-- US-30 — layout picker polish suite.
--
-- Verifies the picker's recent improvements:
--   * Card names render dark black (fgcolor COLOR_BLACK) for readability;
--   * Every card carries a sync badge (circular-arrows icon + win count) in the
--     thumbnail's top-right corner, starting at 0 for a never-won layout;
--   * Human wins on a layout are tracked per-layout (MahjongStats.layout_wins,
--     persisted under the "stats" key) and the badge reflects them; auto-solve
--     wins never count;
--   * Tapping a card shows a pressed state (background + border darken) and
--     defers the deal by one scheduled tick so the feedback paints on e-ink;
--     closing the picker cancels a pending pick;
--   * The thumbnail centers the tower's face center of mass (not the bounding
--     box), so the 2.5D up-left lean no longer off-centers the picture.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Stats = ctx.loadPlugin("mahjongstats")
local LayoutSelect = ctx.loadPlugin("mahjonglayoutselect")
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

-- Show the picker on a fresh instance (no saved game).
local function openPicker()
    store.game = nil
    local mj = Mahjong:new()
    local menu_items = {}
    mj:addToMainMenu(menu_items)
    menu_items.mahjong.callback()
    local picker = ctx.window_stack[#ctx.window_stack].widget
    expect(picker ~= nil and picker.name == "mahjonglayoutselect",
        "first launch shows the layout picker")
    return mj, picker
end

local function turtleCard(picker)
    for _, c in ipairs(picker._card_rects) do
        if c.id == "turtle" then return c end
    end
end

-- The card's content tree (mocks are pass-through arrays):
--   card[1]        = CenterContainer
--   card[1][1]     = VerticalGroup { span, OverlapGroup(thumb+badge), span, name }
--   card[1][1][2]     = the thumbnail OverlapGroup
--   card[1][1][2][2]  = the trophy badge FrameContainer
--   card[1][1][2][2][1] = HorizontalGroup { sync, span, count }
--   card[1][1][2][2][1][3] = the win-count TextWidget
--   card[1][1][4]     = the layout-name TextWidget
local function cardNameWidget(c)
    return c.card[1][1][4]
end

local function cardBadgeCountWidget(c)
    return c.card[1][1][2][2][1][3]
end

local function cardBadgeIconWidget(c)
    return c.card[1][1][2][2][1][1]
end

-- ---- Card names are dark black -----------------------------------------------

local mj, picker = openPicker()
if picker._page_right and picker._page_right.enabled ~= false then
    picker._page_right.callback()
    picker = ctx.window_stack[#ctx.window_stack].widget
end
local tcard = turtleCard(picker)
expect(tcard ~= nil, "the picker lists a Turtle card")
if tcard then
    expect(cardNameWidget(tcard).fgcolor == "black",
        "card names render dark black (COLOR_BLACK)")
end

-- ---- Trophy badges start at 0 for never-won layouts ---------------------------

for _, c in ipairs(picker._card_rects) do
    local count = cardBadgeCountWidget(c)
    expect(count ~= nil and count.text == "0",
        "played badge for layout '" .. c.id .. "' starts at 0 wins (got "
        .. tostring(count and count.text) .. ")")
    expect(cardBadgeIconWidget(c) ~= nil and cardBadgeIconWidget(c).icon == "mahjong/sync",
        "played badge for layout '" .. c.id .. "' uses circular arrows")
end

-- ---- Per-layout win tracking (pure stats) ------------------------------------

local s = Stats.defaults()
Stats.recordLayoutWin(s, "turtle")
Stats.recordLayoutWin(s, "turtle")
Stats.recordLayoutWin(s, "spider")
expect(s.layout_wins.turtle == 2 and s.layout_wins.spider == 1,
    "recordLayoutWin bumps per-layout counters")

-- ---- A human win records the layout win and the badge shows it ----------------

-- Tiny 2-pair board on Turtle; win it for real (human, not auto-solve).
local mj1 = Mahjong:new()
mj1.board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1" }
mj1.layout = "turtle"
mj1.score = 0
mj1.last_match_kind = nil
mj1.pairs_matched = 0
mj1.history = {}
mj1:buildUILayout()
mj1:handleTileTap(2, 2, 0)
mj1:handleTileTap(4, 2, 0)
expect(Logic.isWin(mj1.board), "the tiny board is won")
expect(mj1.stats.layout_wins.turtle == 1,
    "a human win bumps the turtle layout win count")
expect(store.stats ~= nil and store.stats.layout_wins ~= nil
    and store.stats.layout_wins.turtle == 1,
    "layout wins are persisted under the stats key")

-- Win dialog "Select Layout" shows the picker; Turtle's badge now shows 1.
ctx.last_confirm.cancel_callback()
local picker2 = ctx.window_stack[#ctx.window_stack].widget
expect(picker2 ~= nil and picker2.name == "mahjonglayoutselect",
    "Select Layout re-opens the layout picker")
local tcard2 = turtleCard(picker2)
if tcard2 then
    expect(cardBadgeCountWidget(tcard2).text == "1",
        "Turtle's badge shows 1 after one win (got "
        .. tostring(cardBadgeCountWidget(tcard2).text) .. ")")
end

-- ---- Auto-solve wins never count toward layout wins ---------------------------

local mj2 = Mahjong:new()
mj2.board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1",
              [pk(6, 2, 0)] = "c1", [pk(8, 2, 0)] = "c1" }
mj2.layout = "turtle"
mj2:buildUILayout()
mj2.score = 0
scheduled = {}
mj2.hint_button.hold_callback()
local arm = scheduled[1][2]
scheduled = {}
arm()
local guard = 0
while scheduled[1] and guard < 200 do
    local e = table.remove(scheduled, 1)
    e[2]()
    guard = guard + 1
end
expect(Logic.isWin(mj2.board), "auto-solve cleared the board")
expect((mj2.stats.layout_wins and mj2.stats.layout_wins.turtle or 0) == 1,
    "an auto-solve win does not bump the layout win count")

-- ---- Tap feedback: pressed card + deferred deal -------------------------------

-- Tap Turtle's card: the card highlights immediately and the deal is deferred
-- by one scheduled tick (so the press paints on e-ink before the board build).
store.game = nil
local mj3 = Mahjong:new()
local mi3 = {}
mj3:addToMainMenu(mi3)
mi3.mahjong.callback()
local picker3 = ctx.window_stack[#ctx.window_stack].widget
picker3._page_right.callback()
picker3 = ctx.window_stack[#ctx.window_stack].widget
local tcard3 = turtleCard(picker3)
local before_background = tcard3.card.background
picker3:onTapSelect(nil, { pos = { x = tcard3.x + tcard3.w / 2,
                                   y = tcard3.y + tcard3.h / 2 } })
expect(picker3._pending_pick == "turtle",
    "tapping a card registers the pending pick")
expect(tcard3.card.background == "light_gray",
    "the tapped card shows the pressed state (background darkened)")
expect(picker3._pending_pick ~= nil and #scheduled > 0,
    "the deal is deferred (a scheduled task is pending)")
expect(mj3.board == nil, "the deal has not run yet (deferred)")

-- Closing the picker cancels a pending pick, so the deferred deal is a no-op.
picker3:closeDialog()
expect(picker3._pending_pick == nil, "closing the picker clears the pending pick")

-- The deferred deal runs on the scheduled tick and deals the board.
store.game = nil
local mj4 = Mahjong:new()
local mi4 = {}
mj4:addToMainMenu(mi4)
mi4.mahjong.callback()
local picker4 = ctx.window_stack[#ctx.window_stack].widget
picker4._page_right.callback()
picker4 = ctx.window_stack[#ctx.window_stack].widget
local tcard4 = turtleCard(picker4)
picker4:onTapSelect(nil, { pos = { x = tcard4.x + tcard4.w / 2,
                                   y = tcard4.y + tcard4.h / 2 } })
-- This test overrides um.scheduleIn into its own `scheduled`; the deal is the
-- task just added (last), so run it.
if scheduled[#scheduled] then
    table.remove(scheduled, #scheduled)[2]()
end
expect(mj4.board ~= nil and Logic.tileCount(mj4.board) == 144,
    "the deferred deal fires on the scheduled tick and deals a 144-tile board")
expect(mj4.layout == "turtle", "the deferred deal picks the tapped layout")

-- ---- Thumbnail still renders after the centering change -----------------------

for _, c in ipairs(picker4._card_rects) do
    local thumb = LayoutSelect.layoutThumbnail(c.id, 100, 100)
    expect(thumb ~= nil and thumb.dimen ~= nil and thumb.dimen.w == 100
            and thumb.dimen.h == 100,
        "the thumbnail renders for layout '" .. c.id .. "' with the requested dimen")
    expect(#thumb == #Logic.buildLayout(c.id),
        "the thumbnail for '" .. c.id .. "' has one tile per layout position")
end

-- ---- Win-case close X exits the game (never returns to an empty board) ---------

-- After a win, "Select Layout" shows the picker over the WON (empty) board. Tapping
-- the picker's X must EXIT the game entirely — a bare close would land the player
-- on the empty board (reported bug). The real ConfirmBox auto-closes itself after
-- ok_callback runs, so mimic that before driving the picker's close X.
store.game = nil
local mj5 = Mahjong:new()
mj5.board = { [pk(2, 2, 0)] = "d2", [pk(4, 2, 0)] = "d2" }
mj5.layout = "turtle"
mj5.score = 0
mj5.last_match_kind = nil
mj5.pairs_matched = 0
mj5.history = {}
mj5:buildUILayout()
mj5:handleTileTap(2, 2, 0)
mj5:handleTileTap(4, 2, 0)
expect(Logic.isWin(mj5.board), "the second tiny board is won")
local win_dlg = ctx.last_confirm
win_dlg.cancel_callback() -- "Select Layout" -> layout picker
um.close(win_dlg)     -- the real ConfirmBox closes itself on OK
local picker5 = ctx.window_stack[#ctx.window_stack].widget
expect(picker5 ~= nil and picker5.name == "mahjonglayoutselect",
    "win 'Select Layout' re-opens the layout picker")
picker5:closeDialog() -- the close X
-- The flow fix: closing the picker over a WON board must close the game itself,
-- never return the player to the empty board. (The harness drives games without
-- UIManager:show(self), so the stack never held the game; the close_calls record
-- proves the Mahjong widget was actually closed.)
local mj5_closed = false
for _, c in ipairs(ctx.close_calls) do
    if c.widget == mj5 then mj5_closed = true break end
end
expect(mj5_closed,
    "the win-case close X closes the Mahjong game (no empty board)")
expect(not um.isWidgetShown(picker5), "the win-case close X closes the picker")
expect(store.game == nil,
    "the exited won game is not saved (no empty board on next launch)")
local last_close5 = ctx.close_calls[#ctx.close_calls]
expect(last_close5 and last_close5.widget == picker5
        and last_close5.refreshtype == "full",
    "the win-case close X requests a full-screen refresh (got "
    .. tostring(last_close5 and last_close5.refreshtype) .. ")")

if failures == 0 then
    print("\nALL US-30 PICKER-POLISH CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
