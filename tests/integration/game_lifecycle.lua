-- US-01/02 shell: _meta.lua, main.lua class, menu entry, dispatcher action,
-- and the full-screen shell flows (startGame, New Game, exit). The board widget
-- itself is exercised in us06_board.lua; here we verify the plugin shell
-- structure and control flow against the current implementation.

local mock = require("mock")
local fixtures = require("support.fixtures")
local ctx = mock.newContext()

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

-- US-14: startGame with no saved game shows the layout picker; pick Turtle to
-- deal a board. Drives the real tap path (hit-test the Turtle card).
-- ---- _meta.lua ----------------------------------------------------------

local meta = ctx.loadPlugin("_meta")
expect(type(meta) == "table", "_meta.lua returns a table")
expect(meta.name == "mahjong", "_meta.lua name == 'mahjong' (got " .. tostring(meta.name) .. ")")
expect(type(meta.fullname) == "string" and #meta.fullname > 0, "_meta.lua fullname is a non-empty string")
expect(type(meta.description) == "string" and #meta.description > 0, "_meta.lua description is a non-empty string")

-- ---- main.lua class ------------------------------------------------------

local Logic = ctx.loadPlugin("mahjonglogic")
ctx.loadPlugin("mahjongboard")
local Mahjong = ctx.loadPlugin("main")
expect(type(Mahjong) == "table" and Mahjong.name == "mahjong", "main.lua returns the plugin class")
expect(Mahjong.is_doc_only == false, "is_doc_only == false (available from FileManager & reader)")

local mj = Mahjong:new()
expect(ctx.menu_registered, "init() registered to main menu")
local action = ctx.dispatcher_actions["mahjong"]
expect(action ~= nil, "init() registered the 'mahjong' dispatcher action")
expect(action.event == "MahjongStart", "dispatcher action event == 'MahjongStart'")
expect(action.general == true, "dispatcher action is general (usable from any view)")
expect(type(action.title) == "string" and #action.title > 0, "dispatcher action has a title")

-- ---- addToMainMenu -------------------------------------------------------

local menu_items = {}
mj:addToMainMenu(menu_items)
expect(menu_items.mahjong ~= nil, "menu entry 'mahjong' present")
expect(menu_items.mahjong.text == "Mahjong Solitaire", "menu text == 'Mahjong Solitaire'")
expect(menu_items.mahjong.sorting_hint == "tools", "sorting_hint == 'tools'")
expect(type(menu_items.mahjong.callback) == "function", "menu callback is a function")

-- ---- startGame -----------------------------------------------------------

menu_items.mahjong.callback()
-- US-14: first launch shows the layout picker, not a board.
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "startGame with no saved game shows the layout picker")
fixtures.pickTurtle(ctx)
expect(#ctx.window_stack == 1 and ctx.window_stack[1].widget == mj,
    "startGame shows the plugin widget")
expect(type(mj.board) == "table" and Logic.tileCount(mj.board) == 144,
    "startGame built a 144-tile board")
expect(mj.status_bar ~= nil and mj.status_bar.title == "Mahjong Solitaire",
    "status bar created with the right title")
expect(mj[1] ~= nil, "full-screen layout built into self[1]")
expect(mj.status_bar.right_icon == "mahjong/close"
        and (mj.status_bar.right_icon_size_ratio or 0.6) > 0.6,
    "quit X uses the bolder mahjong/close icon at a larger size")

-- Dispatcher can re-launch while the widget is on the stack: it must close and
-- rebuild without duplicating the widget on the stack.
local handled = mj:handleEvent({ handler = "onMahjongStart" })
expect(handled == true, "handleEvent handles onMahjongStart")
expect(Logic.tileCount(mj.board) == 144, "board rebuilt after dispatcher re-launch")
local on_stack = 0
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj then on_stack = on_stack + 1 end
end
expect(on_stack == 1, "widget still on the stack exactly once after re-launch")

-- ---- New Game ------------------------------------------------------------

-- The toolbar holds 5 action-button cells (icon button + hint label)
-- separated by 4 HorizontalSpan gaps plus one edge spacer on each side
-- (the stock HorizontalGroup ignores a `spacing` field, so real spacers).
-- Layout: [1] status bar, [2] board, [3] feedback band, [4] toolbar, [5] spacer.
local toolbar = mj[1][4]
local btns, gaps = {}, {}
for i = 1, #toolbar do
    local b = toolbar[i]
    if type(b) == "table" and b.bordersize then
        btns[#btns + 1] = b
    elseif type(b) == "table" and b[1] and b[1].bordersize then
        btns[#btns + 1] = b[1] -- a toolbar cell: VerticalGroup{ button, label }
    elseif type(b) == "table" and (b.width or 0) > 0 then
        gaps[#gaps + 1] = b
    end
end
expect(#btns == 5, "toolbar holds exactly 5 action buttons")
expect(#gaps == 6 and gaps[1].width > 0 and gaps[6].width > 0
        and toolbar[1] == gaps[1] and toolbar[#toolbar] == gaps[6],
    "six spacers: four between the buttons plus edge gaps at both screen sides")
local all_bordered = true
for _, b in ipairs(btns) do
    if not b.padding or not b.radius then all_bordered = false end
end
expect(all_bordered, "toolbar buttons are rounded bordered rectangles (bigger tap areas)")
local labels_ok = true
for i, cell in ipairs({ toolbar[2], toolbar[4], toolbar[6], toolbar[8], toolbar[10] }) do
    if type(cell[2]) ~= "table" or type(cell[2].text) ~= "string" or #cell[2].text == 0 then
        labels_ok = false
    end
end
expect(labels_ok, "each toolbar cell carries a hint label under the icon")
expect(type(mj[1][5]) == "table" and (mj[1][5].width or 0) > 0,
    "a bottom spacer lifts the toolbar off the screen edge")
local pause_btn = btns[5]
expect(pause_btn.icon == "mahjong/pause" and type(pause_btn.callback) == "function",
    "the fifth toolbar button is Pause and is wired")
local new_game_btn = btns[4]
expect(type(new_game_btn.callback) == "function", "New Game button wired")
ctx.last_confirm = nil
new_game_btn.callback()
-- US-14: New Game shows the picker (choosing a layout IS the confirmation),
-- so no ConfirmBox appears.
expect(ctx.last_confirm == nil, "New Game no longer opens a ConfirmBox (picker instead)")
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "New Game opens the layout picker")
local old_board = mj.board
fixtures.pickTurtle(ctx)
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text ==
        "Start a new game? Your current game will be stopped.",
    "picking a layout over the running game opens a replacement confirmation")
expect(mj.board == old_board, "the running game remains until replacement is confirmed")
ctx.last_confirm.ok_callback()
expect(mj.board ~= old_board and Logic.tileCount(mj.board) == 144,
    "confirming the layout choice builds a fresh board")

-- ---- Close / exit --------------------------------------------------------

local mj_close_cb = mj.status_bar.right_icon_tap_callback
ctx.last_confirm = nil
mj_close_cb()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text == "Exit Mahjong Solitaire?",
    "quit X opens its ConfirmBox")
ctx.last_confirm.ok_callback()
local still_on_stack = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj then still_on_stack = true end
end
expect(not still_on_stack, "exit removed the plugin widget from the window stack")
expect(mj.board == nil, "onCloseWidget cleared self.board")

if failures == 0 then
    print("\nALL US-01/02 SHELL CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
