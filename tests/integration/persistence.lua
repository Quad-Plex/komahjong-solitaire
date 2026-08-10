-- US-10 persistence suite: settings round-trip, save/restore of the whole
-- game state, the settings dialog, and the elapsed-time display.
--
-- Checks:
--   * Settings defaults and set/get via LuaSettings (in-memory store per ctx);
--   * Settings persist across plugin instances (fresh Mahjong:new() in the
--     same ctx reads back what an earlier instance wrote);
--   * Every successful match saves the game to the "game" key;
--   * A fresh instance restores an identical board / score / history / chain;
--   * Undo after restore pops the restored history and re-saves;
--   * New Game replaces the saved state with a fresh board;
--   * Corrupt saved state silently starts a fresh game AND clears the key;
--   * A won (empty) board is never saved;
--   * The settings dialog: toggles are collected, Save persists, Cancel
--     discards, and Reset restores the defaults;
--   * New Game always shows the layout picker (US-14);
--   * The mm:ss timer text lives in the band and tracks elapsed time.

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
local function count(board)
    local n = 0
    for _ in pairs(board) do n = n + 1 end
    return n
end
local function firstFreePair(board)
    local free = Logic.freeTiles(board)
    for i = 1, #free - 1 do
        for j = i + 1, #free do
            if Logic.matches(free[i].kind, free[j].kind) then
                return free[i], free[j]
            end
        end
    end
    return nil, nil
end

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

local store = ctx.settings_store

-- ---- Settings defaults + set/get + cross-instance round-trip ----------------

local mj0 = Mahjong:new()
expect(mj0:getSetting("hints", true) == true, "unset hints defaults to true")
expect(store.hints == nil, "defaults are NOT written to the settings file")

mj0:setSetting("hints", false)
expect(store.hints == false, "setSetting persists 'hints' immediately")
expect(ctx.flushes >= 1, "setSetting flushed the settings file")
-- A brand-new instance in the same ctx reads the stored settings back.
local mj0b = Mahjong:new()
expect(mj0b:getSetting("hints", true) == false, "a later instance reads the persisted hints")

-- ---- Save after every match -------------------------------------------------

local mj1 = Mahjong:new()
mj1.board = Logic.newGame(7)
mj1:buildUILayout()
expect(store.game == nil, "no saved game before the first move")

local a1, b1 = firstFreePair(mj1.board)
expect(a1 ~= nil, "seeded board has a playable first pair")
local ka1 = a1.kind
mj1:handleTileTap(a1.x, a1.y, a1.layer)
mj1:handleTileTap(b1.x, b1.y, b1.layer)
expect(mj1.score == 10, "first match scored 10")
expect(type(store.game) == "table" and store.game.v == 2, "a match saved a versioned game state")
expect(store.game.layout == "turtle", "the saved state carries the turtle layout id")
expect(store.game.board[pk(a1.x, a1.y, a1.layer)] == nil
        and store.game.board[pk(b1.x, b1.y, b1.layer)] == nil,
    "saved board excludes the removed pair")
expect(count(store.game.board) == 142 and #store.game.history == 1,
    "saved state has 142 tiles and one history record")
expect(store.game.history[1][7] == ka1 and store.game.history[1][9] == 10,
    "flat history record stores the kind and the move's score")
expect(store.game.score == 10 and store.game.last == ka1,
    "saved score and chain kind match the live state")

-- ---- Restore round-trip in a fresh instance ----------------------------------

local mj2 = Mahjong:new()
mj2:startGame()
expect(Logic.tileCount(mj2.board) == 142, "fresh instance restored the 142-tile board")
local same = true
for k, v in pairs(mj1.board) do
    if mj2.board[k] ~= v then same = false break end
end
expect(same, "restored board matches the saved board exactly")
expect(mj2.score == 10, "restored score is 10")
expect(mj2.last_match_kind == ka1, "restored chain kind matches")
expect(#mj2.history == 1 and mj2.history[1].ka == ka1 and mj2.history[1].score == 10,
    "restored history is back in the UI record shape")
expect(mj2.history[1].a.x == a1.x and mj2.history[1].b.y == b1.y,
    "restored history keeps the removed positions")

-- ---- Undo after restore pops the restored history ----------------------------

mj2:undo()
expect(Logic.tileCount(mj2.board) == 144 and mj2.score == 0,
    "undo after restore puts both tiles back and resets the score")
expect(#mj2.history == 0, "undo emptied the restored history")
expect(store.game and count(store.game.board) == 144 and #store.game.history == 0,
    "undo re-saved the restored (now full) board")

-- Elapsed time is part of the save.
local elapsed_probe = Mahjong:new()
elapsed_probe.board = Logic.newGame(7)
elapsed_probe:buildUILayout()
elapsed_probe.elapsed_base = 65
elapsed_probe:saveGameState()
expect(store.game.elapsed == 65, "elapsed seconds are included in the saved state")

-- ---- New Game replaces the saved state ----------------------------------------

local mj3 = Mahjong:new()
mj3.board = Logic.newGame(11)
mj3:buildUILayout()
local a3, b3 = firstFreePair(mj3.board)
mj3:handleTileTap(a3.x, a3.y, a3.layer)
mj3:handleTileTap(b3.x, b3.y, b3.layer)
local saved_before = store.game.board

-- Drive the toolbar's New Game button through its ConfirmBox.
local toolbar = mj3[1][4]
local btns = {}
for i = 1, #toolbar do
    local b = toolbar[i]
    if type(b) == "table" and b.bordersize then
        btns[#btns + 1] = b
    elseif type(b) == "table" and b[1] and b[1].bordersize then
        btns[#btns + 1] = b[1]
    end
end
ctx.last_confirm = nil
btns[4].callback()
-- US-14: New Game shows the picker (choosing a layout IS the confirmation).
expect(ctx.last_confirm == nil, "New Game no longer prompts (picker instead)")
pickTurtle()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text ==
        "Start a new game? Your current game will be stopped.",
    "picking over the restored game opens a replacement confirmation")
ctx.last_confirm.ok_callback()
expect(count(mj3.board) == 144, "New Game built a fresh 144-tile board")
expect(store.game.board ~= saved_before and count(store.game.board) == 144
        and #store.game.history == 0,
    "New Game replaced the saved state with a fresh board")

-- ---- Corrupt saved state -> fresh game + key cleared --------------------------

store.game = "this is not a table"
local mj4 = Mahjong:new()
mj4:startGame()
-- The corrupt key is cleared before the picker deals a replacement board.
expect(store.game == nil, "a garbage saved state is cleared from settings")
pickTurtle()
expect(Logic.tileCount(mj4.board) == 144, "a garbage saved state deals a fresh board")

store.game = { v = 1, board = { [pk(999, 999, 0)] = "b1", [pk(2, 2, 0)] = "b1" },
               history = {}, score = 0, last = nil, elapsed = 0 }
local mj4b = Mahjong:new()
mj4b:startGame()
expect(store.game == nil, "the invalid table state is cleared too")
pickTurtle()
expect(Logic.tileCount(mj4b.board) == 144,
    "a table that fails validation also deals a fresh board")

-- ---- A won board is never saved ----------------------------------------------

local mj5 = Mahjong:new()
mj5.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},
    {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj5:buildUILayout()
mj5:handleTileTap(2, 2, 0)
mj5:handleTileTap(4, 2, 0)
mj5:handleTileTap(6, 2, 0)
mj5:handleTileTap(8, 2, 0)
expect(Logic.isWin(mj5.board), "test board emptied for the win")
expect(ctx.last_confirm ~= nil
        and ctx.summaryText(ctx.last_confirm):find("Score: 80", 1, true) ~= nil,
    "win dialog shows the final score")
expect(store.game == nil, "a won board is not left in the saved state")

-- ---- Settings dialog -----------------------------------------------------------

-- Baseline the settings file for a self-contained dialog walk: wipe the keys
-- written by the earlier defaults section so the dialog starts from defaults.
store.hints = nil
store.deselect_on_empty = nil

local mj6 = Mahjong:new()
mj6.board = Logic.newGame(13)
mj6:buildUILayout()
expect(mj6:getSetting("hints", true) == true, "pre-dialog hints is the default true")
expect(mj6:getSetting("deselect_on_empty", true) == true,
    "pre-dialog deselect-on-empty is enabled by default")

mj6:openSettings()
local dlg = ctx.window_stack[#ctx.window_stack].widget
expect(dlg ~= nil and dlg.name == "mahjongsettings", "openSettings shows the settings dialog")
expect(dlg._rows ~= nil and dlg._rows.hints and dlg._rows.deselect_on_empty
        and dlg._rows.timer_update,
    "dialog exposes the setting rows")
expect(dlg._rows.hints.text == "On", "hints row starts at the persisted value (On)")

dlg._rows.hints.callback()
expect(dlg.changes.hints == false and dlg._rows.hints.text == "Off",
    "toggling the hints row flips its (unsaved) value")
expect(store.hints == nil, "a toggle is collected, not yet persisted")
dlg:save()
expect(store.hints == false, "Save persists the toggled hints")
expect(mj6:getSetting("hints", true) == false, "the parent reads the saved hints back")
local dlg_still_open = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg then dlg_still_open = true end
end
expect(not dlg_still_open, "Save closes the settings dialog")

-- Empty-space deselection is independently persisted.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
dlg._rows.deselect_on_empty.callback()
expect(dlg.changes.deselect_on_empty == false and dlg._rows.deselect_on_empty.text == "Off",
    "toggling deselect-on-empty flips its unsaved value")
expect(store.deselect_on_empty == true,
    "deselect-on-empty remains at its saved value before Save")
dlg:save()
expect(store.deselect_on_empty == false
        and mj6:getSetting("deselect_on_empty", true) == false,
    "Save persists deselect-on-empty disabled")

-- Cancel discards the (unsaved) changes.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
expect(dlg.changes.hints == false, "reopened dialog reflects the saved Off value")
dlg._rows.hints.callback() -- Off -> On (unsaved)
expect(dlg.changes.hints == true, "hints toggle flips (Off -> On) before cancel")
dlg:cancel()
expect(store.hints == false,
    "Cancel discards the unsaved toggle (keeps the previously saved false)")
expect(mj6:getSetting("hints", true) == false,
    "Cancel leaves already-saved settings untouched")

-- Reset restores the defaults and Save writes them.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
dlg._rows.hints.callback() -- Off -> On
dlg._rows.hints.callback() -- On -> Off (differs from the default)
dlg:resetToDefaults()
expect(dlg.changes.hints == true,
    "Reset restores the default settings")
expect(dlg._rows.hints.text == "On", "Reset re-renders the row labels")
dlg:save()
expect(store.hints == true,
    "Save after Reset writes the defaults back")

-- The dialog is a floating window: a transparent full-screen container whose
-- only child centers a white card over the game (not an opaque full-screen
-- page), and the panel's on-screen rect is exposed for tap-outside handling.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
expect(dlg.background == nil, "the dialog's outer widget is transparent (floating window)")
expect(dlg.covers_fullscreen == true, "the dialog is a full-screen modal wrapper")
expect(dlg.dimen ~= nil and dlg.dimen.w == 1200 and dlg.dimen.h == 800,
    "the dialog spans the full screen")
expect(type(dlg[1]) == "table" and type(dlg[1].dimen) == "table",
    "the dialog's single child is a centering container")
local dlg_panel = dlg[1][1]
expect(type(dlg_panel) == "table" and dlg_panel.background == "white"
        and dlg_panel.bordersize ~= nil and dlg_panel.radius ~= nil,
    "the centered panel is a bordered white card")
expect(type(dlg._panel_geom) == "table" and type(dlg._panel_geom.w) == "number"
        and type(dlg._panel_geom.h) == "number",
    "the panel's screen rect is exposed for the tap-outside test")

-- Settings polish (US-10/11 follow-up): every toggle button is sized to the
-- same measured width (so the value column lines up and no value is cut off),
-- and every row is [alignment spacer, label, gap, control] so the button
-- column starts at the same x regardless of the label length.
local vgroup = dlg_panel[1]
expect(type(vgroup) == "table" and type(vgroup[3]) == "table",
    "the settings card holds a vertical row list")
local row_indices = {
    [3] = "hints", [5] = "deselect_on_empty", [7] = "timer_update",
    [9] = "timer_interval",
}
local btn_w = dlg._rows.hints.width
local all_same_w = true
for _, key in pairs(row_indices) do
    if dlg._rows[key].width ~= btn_w then all_same_w = false end
end
expect(all_same_w, "every toggle button shares one measured width")
for i, key in pairs(row_indices) do
    local r = vgroup[i]
    expect(type(r) == "table" and type(r[1]) == "table" and type(r[2]) == "table"
            and type(r[3]) == "table" and r[4] == dlg._rows[key],
        "settings row " .. key .. " is [pad, label, gap, button]")
end
expect(vgroup[3][2] ~= nil and vgroup[5][2] ~= nil and vgroup[7][2] ~= nil
        and vgroup[9][2] ~= nil and vgroup[11][2] ~= nil,
    "row labels are the second element of each row")
expect(vgroup[13] == nil or type(vgroup[13]) ~= "table" or vgroup[13][2] == nil
        or vgroup[13][2].text ~= "Layout",
    "the informational Layout row is gone from the dialog")
expect(dlg._close_btn ~= nil and type(dlg._close_btn.icon) == "string"
        and type(dlg._close_btn.callback) == "function",
    "the panel has a close X button")
expect(type(vgroup[1]) == "table" and vgroup[1][2] and vgroup[1][2].text == "Settings"
        and vgroup[1][4] == dlg._close_btn,
    "the close X sits in the title row, right of the title")

-- The dialog must refresh the panel region when shown: UIManager:show dirties
-- the widget but (with a nil refreshtype) enqueues no refresh, so without this
-- the panel would stay invisible after tapping the settings gear (the gear's
-- own highlight refresh is what gets flushed instead). onShow must enqueue a
-- refresh function for the panel rect.
local show_dirty = #ctx.dirty_calls
dlg:onShow()
local refresh_fn_queued = false
for i = show_dirty + 1, #ctx.dirty_calls do
    if ctx.dirty_calls[i].widget == dlg and type(ctx.dirty_calls[i].refreshtype) == "function" then
        refresh_fn_queued = true
    end
end
expect(refresh_fn_queued, "onShow enqueues a refresh function for the panel")

-- A toggle repaints the dialog itself (the US-10 "value doesn't change on
-- screen" bug): the callback must mark the WINDOW-level widget dirty, not a
-- subwidget, or UIManager never re-renders the new label.
local dirty_before = #ctx.dirty_calls
dlg._rows.hints.callback() -- On -> Off
local self_dirtied = false
for i = dirty_before + 1, #ctx.dirty_calls do
    if ctx.dirty_calls[i].widget == dlg and ctx.dirty_calls[i].refreshtype == "ui" then
        self_dirtied = true
    end
end
expect(self_dirtied, "a toggle dirties the dialog widget so the new label repaints")
expect(dlg._rows.hints.text == "Off", "the row label text updated in place")
dlg:save()

-- Cancel (and the equivalent tap-outside) notify the owner so it can restart
-- the timer loop that openSettings paused; the dialog closes either way.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
expect(mj6._timer_running == false, "openSettings pauses the timer loop")
dlg:cancel()
local dlg_closed = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg then dlg_closed = false end
end
expect(dlg_closed, "Cancel closes the dialog")
expect(mj6._timer_running == true, "Cancel restarts the paused timer loop")

-- The close X inside the panel behaves exactly like Cancel: it discards the
-- (unsaved) changes, notifies the owner (restarting the paused timer loop),
-- and closes the dialog.
mj6:openSettings()
dlg = ctx.window_stack[#ctx.window_stack].widget
local saved_hints = store.hints
local toggled = not (dlg.changes.hints or false)
dlg._rows.hints.callback()
expect(dlg.changes.hints == toggled, "unsaved change collected before the X tap")
expect(mj6._timer_running == false, "openSettings paused the timer loop")
dlg._close_btn.callback()
local x_closed = true
for _, e in ipairs(ctx.window_stack) do
    if e.widget == dlg then x_closed = false end
end
expect(x_closed, "the close X closes the settings dialog")
expect(store.hints == saved_hints, "the close X discards the unsaved change")
expect(mj6._timer_running == true, "the close X notifies the owner (timer restarted)")

-- ---- New Game always shows the picker ----------------------------------------
-- US-14: choosing a layout IS the confirmation, so confirm_new_game is gone
-- (the New Game button shows the picker unconditionally).

local mj7 = Mahjong:new()
mj7.board = Logic.newGame(17)
mj7:buildUILayout()
local toolbar7 = mj7[1][4]
local btns7 = {}
for i = 1, #toolbar7 do
    local b = toolbar7[i]
    if type(b) == "table" and b.bordersize then
        btns7[#btns7 + 1] = b
    elseif type(b) == "table" and b[1] and b[1].bordersize then
        btns7[#btns7 + 1] = b[1]
    end
end
local old_board7 = mj7.board
ctx.last_confirm = nil
btns7[4].callback()
expect(ctx.last_confirm == nil, "New Game shows no ConfirmBox (picker instead)")
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "New Game opens the layout picker")
pickTurtle()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text ==
        "Start a new game? Your current game will be stopped.",
    "picking over the active game opens a replacement confirmation")
ctx.last_confirm.ok_callback()
expect(mj7.board ~= old_board7 and count(mj7.board) == 144,
    "picking Turtle from the picker builds a fresh board")

-- ---- Elapsed-time display -------------------------------------------------------

local mj8 = Mahjong:new()
mj8.board = Logic.newGame(19)
mj8:buildUILayout()
expect(mj8.timer_text ~= nil, "the band has an elapsed-time TextWidget")
expect(mj8.flash_band[1] and mj8.flash_band[1][1] == mj8.flash_text
        and mj8.flash_band[1][3] == mj8.timer_text,
    "the timer sits in the feedback band's OverlapGroup")
expect(mj8.timer_text.overlap_offset ~= nil
        and type(mj8.timer_text.overlap_offset[1]) == "number"
        and type(mj8.timer_text.overlap_offset[2]) == "number",
    "timer offset is an array on the widget itself (OverlapGroup contract)")
expect(mj8.timer_text.text == "00:00", "timer starts at 00:00")

mj8.elapsed_base = 65
mj8:updateTimerDisplay()
expect(mj8.timer_text.text == "01:05", "the band shows the formatted elapsed time")
mj8:startTimer()
expect(mj8._timer_running == true and mj8._timer_started_at ~= nil,
    "startTimer arms the polling loop")
mj8:stopTimer()
expect(mj8._timer_running == false and type(mj8.elapsed_base) == "number",
    "stopTimer freezes the elapsed time")

if failures == 0 then
    print("\nALL US-10 PERSISTENCE CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
