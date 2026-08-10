-- US-46 — layout-picker chrome: a Stats button joins settings + help in the
-- title row, and the title stays centered; the close button renders as a
-- return arrow when an active game sits below the picker. The stats card
-- opened from the picker shows the Map column only when a game is running in
-- the background (first launch / Play-again path: Global column only), and
-- closing that card must NOT resume the timer — the opaque picker paused it
-- and stays up on top (the openSettings picker_was_open pattern).

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Mahjong = ctx.loadPlugin("main")

local store = ctx.settings_store

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

local function closePickerStats(card)
    if card._close_btn then
        card._close_btn.callback()
    else
        card:onTapClose(nil, { pos = { notIntersectWith = function() return true end } })
    end
end

-- ---- 1. First launch: picker with stats button, close X, single Global column ----

store.game = nil
local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
local picker = ctx.window_stack[#ctx.window_stack].widget
expect(picker ~= nil and picker.name == "mahjonglayoutselect",
    "picker opens on a fresh game")

expect(picker._settings_btn ~= nil and picker._stats_btn ~= nil
        and picker._help_btn ~= nil,
    "picker carries settings, stats and help buttons")
expect(picker._stats_btn.icon == "mahjong/stats",
    "the stats button uses the stats icon")
expect(picker._stats_btn.callback ~= nil, "the stats button has a callback")

-- Order in the title row: settings - stats - help (left), close X (right).
local title_row = picker[1] and picker[1][1] and picker[1][1][2]
expect(title_row ~= nil, "picker title row exists in the content group")
if title_row then
    expect(title_row[2] == picker._settings_btn and title_row[4] == picker._stats_btn
            and title_row[6] == picker._help_btn,
        "title row order is settings, stats, help")
    expect(title_row[10] == picker._close_btn, "the close button ends the row")
end

-- Centering: the title sits exactly at the screen center (the flex spans are
-- asymmetric because the left side now carries three buttons).
if title_row then
    local function child_w(c)
        if type(c) ~= "table" then return 0 end
        if c.width then return c.width end
        if c.getSize then
            local s = c:getSize()
            return s.w or 0
        end
        return 0
    end
    local left_of_title = 0
    for i = 1, 7 do -- edge pad + settings + gap + stats + gap + help + left span
        left_of_title = left_of_title + child_w(title_row[i])
    end
    local title_center = left_of_title + child_w(title_row[8]) / 2
    expect(math.abs(title_center - mj.full_width / 2) <= 1,
        "title is centered in the full row (center=" .. title_center .. ")")
    local left_gap_w = child_w(title_row[7])
    local right_gap_w = child_w(title_row[9])
    expect(math.abs(left_gap_w - right_gap_w) >= 1,
        "free spans are asymmetric for three left buttons ("
        .. left_gap_w .. " vs " .. right_gap_w .. ")")
end

expect(picker.game_in_background == false, "no game behind the picker on first launch")
expect(picker._close_btn.icon == "mahjong/close",
    "no game behind: the close button is an X")

-- Open the stats card from the picker: no Map column (no layout selected).
picker._stats_btn.callback()
local card = ctx.window_stack[#ctx.window_stack].widget
expect(card ~= nil and card.name == "mahjongstatswidget",
    "the picker stats button opens the stats card")
expect(card._values.played ~= nil, "the card shows the Global column")
expect(card._values.map_played == nil,
    "no Map column when no game is running in the background")
expect(mj._timer_running == false, "opening the stats card keeps the timer paused")

-- Closing the card does NOT resume the timer: the opaque picker is still up
-- and owns the pause (the openSettings pattern).
closePickerStats(card)
expect(mj._timer_running == false,
    "closing stats over the picker does NOT resume the paused timer")
expect(ctx.window_stack[#ctx.window_stack].widget == picker,
    "the picker is still on top after closing stats")
-- Clean up (no game behind this picker): the close X dismisses it.
picker._close_btn.callback()
expect(mj._timer_running == false, "closing the first-launch picker stays paused")
expect(mj.board == nil, "closing the first-launch picker deals no board")

-- ---- 2. Active game in the background: return arrow + Map column ----------------

-- Deal a game on the regular path (pick Turtle), then reopen the picker as the
-- New Game button would.
store.game = nil
local mj2 = Mahjong:new()
local menu2 = {}
mj2:addToMainMenu(menu2)
menu2.mahjong.callback()
local picker2 = ctx.window_stack[#ctx.window_stack].widget
picker2._page_right.callback()
picker2 = ctx.window_stack[#ctx.window_stack].widget
local turtle_r
for _, c in ipairs(picker2._card_rects) do
    if c.id == "turtle" then turtle_r = c break end
end
picker2:onTapSelect(nil, { pos = { x = turtle_r.x + turtle_r.w / 2,
                                   y = turtle_r.y + turtle_r.h / 2 } })
ctx.runScheduled() -- US-30: the deal is deferred by TAP_FEEDBACK_SECONDS
expect(mj2.board ~= nil and Logic.tileCount(mj2.board) == 144,
    "picking Turtle deals a fresh board")
expect(mj2._timer_running == true, "the game timer is running")

mj2:showLayoutPicker()
local picker3 = ctx.window_stack[#ctx.window_stack].widget
expect(picker3 ~= nil and picker3.name == "mahjonglayoutselect",
    "New Game reopens the picker above the running game")
expect(picker3.game_in_background == true,
    "an active (un-won) game is flagged in the background")
expect(picker3._close_btn.icon == "chevron.left",
    "an active game behind the picker: the close button is a return arrow")

-- Choosing a layout while an unfinished game is underneath must confirm before
-- replacing that game. Cancel keeps both the picker and the old board intact.
local old_board = mj2.board
local replacement
picker3._page_right.callback()
picker3 = ctx.window_stack[#ctx.window_stack].widget
for _, c in ipairs(picker3._card_rects) do
    if c.id == "spider" then replacement = c break end
end
picker3:onTapSelect(nil, { pos = { x = replacement.x + replacement.w / 2,
                                   y = replacement.y + replacement.h / 2 } })
ctx.runScheduled()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text ==
        "Start a new game? Your current game will be stopped.",
    "choosing a layout over an active game opens a replacement confirmation")
expect(mj2.board == old_board, "the active game is unchanged before confirmation")
ctx.last_confirm:onClose()
expect(mj2.board == old_board, "cancelling replacement keeps the active game")
expect(ctx.window_stack[#ctx.window_stack].widget == picker3,
    "cancelling replacement leaves the layout picker open")

-- Confirming the same selection closes the picker and replaces the board.
picker3 = ctx.window_stack[#ctx.window_stack].widget
for _, c in ipairs(picker3._card_rects) do
    if c.id == "spider" then replacement = c break end
end
picker3:onTapSelect(nil, { pos = { x = replacement.x + replacement.w / 2,
                                   y = replacement.y + replacement.h / 2 } })
ctx.runScheduled()
ctx.last_confirm.ok_callback()
expect(mj2.board ~= old_board and mj2.layout == "spider",
    "confirming replacement starts the selected layout")

-- The stats card opened from this picker keeps the Map column for the board.
-- Reopen the picker for the stats assertions below.
mj2:showLayoutPicker()
picker3 = ctx.window_stack[#ctx.window_stack].widget
picker3._stats_btn.callback()
card = ctx.window_stack[#ctx.window_stack].widget
expect(card ~= nil and card.name == "mahjongstatswidget",
    "the picker stats button opens the stats card over a running game")
expect(card._values.map_played ~= nil,
    "the Map column follows the running game's layout")
expect(card._values.played ~= nil, "the Global column is still present")
expect(mj2._timer_running == false, "opening stats keeps the timer paused")
closePickerStats(card)
expect(mj2._timer_running == false,
    "closing stats over the picker keeps the timer paused (picker owns it)")

-- Closing the picker (return arrow) resumes the running game.
picker3._close_btn.callback()
expect(mj2._timer_running == true, "the return arrow resumes the running game")

-- ---- 3. Restored game resumes directly (no picker) ------------------------------

store.game = nil
local mj3 = Mahjong:new()
mj3.board = Logic.newGame(7)
mj3.layout = "turtle"
mj3:buildUILayout()
local a = Logic.matchingFreePair(mj3.board)
mj3:handleTileTap(a.a.x, a.a.y, a.a.layer)
mj3:handleTileTap(a.b.x, a.b.y, a.b.layer)
local mj4 = Mahjong:new()
mj4:startGame()
expect(mj4.board ~= nil and Logic.tileCount(mj4.board) == 142,
    "a saved game restores directly")
local saw_picker = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget and e.widget.name == "mahjonglayoutselect" then
        saw_picker = true
    end
end
expect(not saw_picker, "a restored game does NOT show the picker")

-- ---- 4. In-game HUD stats still show both columns (regression) ------------------

mj4.status_bar._left_buttons[2].callback()
card = ctx.window_stack[#ctx.window_stack].widget
expect(card ~= nil and card.name == "mahjongstatswidget",
    "the HUD stats button opens the stats card")
expect(card._values.map_played ~= nil, "the in-game stats card keeps the Map column")
closePickerStats(card)
expect(mj4._timer_running == true, "closing the in-game stats card resumes the timer")

if failures > 0 then
    os.exit(1)
end
print("US-46 picker stats + return-arrow suite passed")
