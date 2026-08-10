-- US-31 — layout picker score chips.
--
-- Verifies the per-layout highscore feature:
--   * MahjongStats tracks layout_highscores (id -> best winning score) next to
--     layout_wins, persisted under the "stats" key and sanitized by load()
--     (the pure module self-tests cover the record semantics in depth);
--   * The picker shows a score chip as the THIRD child of the thumbnail
--     OverlapGroup (the played badge stays child 2) in the thumbnail's
--     bottom-right corner, opposite the badge;
--   * A layout with no highscore shows NO chip at all;
--   * The chip reads the best score as a plain number, using the same corner
--     margin as the badge;
--   * A human win records the layout highscore and the chip appears after the
--     win dialog's "Select Layout" reopens the picker;
--   * Auto-solve wins never record a layout highscore, so no chip appears.

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

-- Opens the picker by invoking the menu entry on a fresh instance (no saved
-- game), returns the picker.
local function openPicker()
    store.game = nil
    local mj = Mahjong:new()
    local menu_items = {}
    mj:addToMainMenu(menu_items)
    menu_items.mahjong.callback()
    return ctx.window_stack[#ctx.window_stack].widget
end

local function cardById(picker, id)
    for _, c in ipairs(picker._card_rects) do
        if c.id == id then return c end
    end
end

-- Card content tree (mocks are pass-through arrays):
--   card[1]        = CenterContainer
--   card[1][1]     = VerticalGroup { span, OverlapGroup(thumb+badge[+chip]), span, name }
--   card[1][1][2]     = the thumbnail OverlapGroup
--   card[1][1][2][2]  = the trophy badge FrameContainer
--   card[1][1][2][3]  = the score chip FrameContainer (only when a highscore exists)
--   card[1][1][2][3][1] = HorizontalGroup { trophy, span, score }
--   card[1][1][2][3][1][3] = the score TextWidget
local function cardScoreChip(c)
    return c.card[1][1][2][3]
end

local function cardBadge(c)
    return c.card[1][1][2][2]
end

local function cardScoreIcon(c)
    return cardScoreChip(c)[1][1]
end

-- ---- Fresh stats: no chips anywhere -------------------------------------------

local picker = openPicker()
for _, c in ipairs(picker._card_rects) do
    expect(cardScoreChip(c) == nil,
        "no score chip on '" .. c.id .. "' when no layout has a highscore")
end

-- ---- Persisted highscore shows on the right card only -------------------------

store.game = nil
store.stats = Stats.load{ layout_highscores = { turtle = 123, spider = 456 } }
local picker2 = openPicker()
picker2._page_right.callback()
picker2 = ctx.window_stack[#ctx.window_stack].widget
local tcard = cardById(picker2, "turtle")
local scard = cardById(picker2, "spider")
local ocard = cardById(picker2, "bridge")
if tcard then
    local chip = cardScoreChip(tcard)
    expect(chip ~= nil and chip[1] ~= nil and chip[1][3] ~= nil
        and chip[1][3].text == "123",
        "Turtle's chip shows its best score (123) as a plain number")
    if chip then
        expect(cardScoreIcon(tcard).icon == "mahjong/trophy",
            "Turtle's highscore chip uses a trophy icon")
        local badge = cardBadge(tcard)
        -- Bottom-right corner, opposite the top-right badge.
        expect(chip.overlap_offset[1] == tcard.w - 2 * 6
            - chip:getSize().w - badge.overlap_offset[2],
            "the score chip uses the thumbnail's bottom-right margin")
        local thumb_h = tcard.h - 28 - 2 * 6
        expect(chip.overlap_offset[2] == thumb_h - chip:getSize().h - badge.overlap_offset[2],
            "the score chip sits in the thumbnail's bottom-right corner")
    end
end
expect(scard ~= nil and cardScoreChip(scard) ~= nil
    and cardScoreChip(scard)[1][3].text == "456",
    "Spider's chip shows its own best score (456)")
expect(ocard == nil or cardScoreChip(ocard) == nil,
    "a layout without a highscore shows no chip")

-- ---- A human win records the score; the chip appears after Select Layout ------

store.game = nil
store.stats = Stats.load(nil)
local mj3 = Mahjong:new()
mj3.board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1" }
mj3.layout = "turtle"
mj3.score = 0
mj3.last_match_kind = nil
mj3.pairs_matched = 0
mj3.history = {}
mj3:buildUILayout()
mj3:handleTileTap(2, 2, 0)
mj3:handleTileTap(4, 2, 0)
expect(Logic.isWin(mj3.board), "the tiny board is won")
expect(mj3.stats.layout_highscores and mj3.stats.layout_highscores.turtle == mj3.score,
    "a human win records the layout highscore")
expect(store.stats and store.stats.layout_highscores
    and store.stats.layout_highscores.turtle == mj3.score,
    "the layout highscore is persisted under the stats key")
local winning_score = mj3.score
ctx.last_confirm.cancel_callback()
local picker3 = ctx.window_stack[#ctx.window_stack].widget
local tcard3 = cardById(picker3, "turtle")
if tcard3 then
    local chip = cardScoreChip(tcard3)
        expect(chip ~= nil and chip[1] ~= nil and chip[1][3] ~= nil
            and chip[1][3].text == tostring(winning_score),
            "Turtle's chip shows the just-won score after Select Layout")
end

-- ---- Auto-solve wins never record a layout highscore --------------------------

store.game = nil
store.stats = Stats.load(nil)
local mj4 = Mahjong:new()
mj4.board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1",
              [pk(6, 2, 0)] = "c1", [pk(8, 2, 0)] = "c1" }
mj4.layout = "turtle"
mj4:buildUILayout()
mj4.score = 0
scheduled = {}
mj4.hint_button.hold_callback()
local arm = scheduled[1][2]
scheduled = {}
arm()
local guard = 0
while scheduled[1] and guard < 200 do
    local e = table.remove(scheduled, 1)
    e[2]()
    guard = guard + 1
end
expect(Logic.isWin(mj4.board), "auto-solve cleared the board")
expect((mj4.stats.layout_highscores and mj4.stats.layout_highscores.turtle or 0) == 0,
    "an auto-solve win does not record a layout highscore")
expect(store.stats and store.stats.layout_highscores
    and store.stats.layout_highscores.turtle == nil,
    "an auto-solve win persists no layout highscore")
ctx.last_confirm.cancel_callback()
local picker4 = ctx.window_stack[#ctx.window_stack].widget
local tcard4 = cardById(picker4, "turtle")
expect(tcard4 == nil or cardScoreChip(tcard4) == nil,
    "an auto-solve win leaves no score chip on the picker card")

-- ---- A best time shows as an mm:ss chip in the bottom-left corner --------------

-- The time chip is the LAST child of the thumbnail OverlapGroup (children are
-- thumb, badge, [score chip when a highscore exists], time chip), sitting in
-- the bottom-LEFT corner, read from layout_best_times. It is the only child
-- whose content is a bare TextWidget holding an mm:ss string — the badge and
-- score chip wrap their content in a HorizontalGroup, so a scan can find it
-- regardless of whether the score chip is present.
local function isTimeChip(x)
    return x ~= nil and x[1] ~= nil and type(x[1].text) == "string"
        and x[1].text:match("^%d%d:%d%d$") ~= nil
end
local function cardTimeChip(c)
    local ovl = c.card[1][1][2]
    if isTimeChip(ovl[#ovl]) then return ovl[#ovl] end
    return nil
end

-- Fresh stats: no layout has a best time, so no time chips anywhere.
local pickerT0 = openPicker()
for _, c in ipairs(pickerT0._card_rects) do
    expect(cardTimeChip(c) == nil,
        "no time chip on '" .. c.id .. "' when no layout has a best time")
end

-- A persisted best time shows on the right card only, formatted mm:ss.
store.game = nil
store.stats = Stats.load{ layout_best_times = { turtle = 125, spider = 90 } }
local pickerT = openPicker()
pickerT._page_right.callback()
pickerT = ctx.window_stack[#ctx.window_stack].widget
local tcardT = cardById(pickerT, "turtle")
local scardT = cardById(pickerT, "spider")
local ocardT = cardById(pickerT, "bridge")
if tcardT then
    local tchip = cardTimeChip(tcardT)
    expect(tchip ~= nil and tchip[1] ~= nil and tchip[1].text == "02:05",
        "Turtle's chip shows its best time (125s) as mm:ss (02:05)")
    if tchip then
        local thumb_h = tcardT.h - 28 - 2 * 6
        expect(tchip.overlap_offset[1] == 4,
            "the time chip sits in the thumbnail's bottom-left corner (left margin)")
        expect(tchip.overlap_offset[2] == thumb_h - tchip:getSize().h - 4,
            "the time chip sits at the thumbnail's bottom edge")
    end
end
expect(scardT ~= nil and cardTimeChip(scardT) ~= nil
    and cardTimeChip(scardT)[1].text == "01:30",
    "Spider's chip shows its own best time (90s) as mm:ss (01:30)")
expect(ocardT == nil or cardTimeChip(ocardT) == nil,
    "a layout without a best time shows no time chip")

-- A human win records the layout best time and the chip appears after Select Layout.
store.game = nil
store.stats = Stats.load(nil)
local mjT = Mahjong:new()
mjT.elapsed_base = 75
store.stats.best_time = nil
mjT.board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1" }
mjT.layout = "turtle"
mjT.score = 0
mjT.last_match_kind = nil
mjT.pairs_matched = 0
mjT.history = {}
mjT:buildUILayout()
-- Advance the clock past elapsed_base so the win records a non-zero elapsed time.
mjT:handleTileTap(2, 2, 0)
mjT:handleTileTap(4, 2, 0)
expect(Logic.isWin(mjT.board), "the timed tiny board is won")
expect(mjT.stats.layout_best_times and mjT.stats.layout_best_times.turtle ~= nil,
    "a human win records the layout best time")
expect(store.stats and store.stats.layout_best_times
    and store.stats.layout_best_times.turtle == mjT.stats.layout_best_times.turtle,
    "the layout best time is persisted under the stats key")
ctx.last_confirm.cancel_callback()
local pickerT2 = ctx.window_stack[#ctx.window_stack].widget
local tcardT2 = cardById(pickerT2, "turtle")
    if tcardT2 then
        local tchip = cardTimeChip(tcardT2)
        expect(tchip ~= nil and tchip[1] ~= nil and tchip[1].text == "01:15",
            "Turtle's time chip shows the just-won time (01:15) after Select Layout")
    end

-- An auto-solve win never records a best time, so no time chip appears.
store.game = nil
store.stats = Stats.load(nil)
local mj6 = Mahjong:new()
mj6.board = { [pk(2, 2, 0)] = "b1", [pk(4, 2, 0)] = "b1",
              [pk(6, 2, 0)] = "c1", [pk(8, 2, 0)] = "c1" }
mj6.layout = "turtle"
mj6:buildUILayout()
mj6.score = 0
scheduled = {}
mj6.hint_button.hold_callback()
local arm2 = scheduled[1][2]
scheduled = {}
arm2()
local g2 = 0
while scheduled[1] and g2 < 200 do
    local e = table.remove(scheduled, 1)
    e[2]()
    g2 = g2 + 1
end
expect(Logic.isWin(mj6.board), "auto-solve cleared the timed board")
expect((mj6.stats.layout_best_times and mj6.stats.layout_best_times.turtle or nil) == nil,
    "an auto-solve win does not record a layout best time")
expect(store.stats and store.stats.layout_best_times
    and store.stats.layout_best_times.turtle == nil,
    "an auto-solve win persists no layout best time")

if failures == 0 then
    print("\nALL US-31 LAYOUT-SCORE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
