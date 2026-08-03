-- US-01/02 shell: _meta.lua, main.lua class, menu entry, dispatcher action,
-- and the full-screen shell flows (startGame, New Game, exit). The board widget
-- itself is exercised in us06_board.lua; here we verify the plugin shell
-- structure and control flow against the current implementation.

local mock = require("mock")
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
expect(#ctx.window_stack == 1 and ctx.window_stack[1].widget == mj,
    "startGame shows the plugin widget")
expect(type(mj.board) == "table" and Logic.tileCount(mj.board) == 144,
    "startGame built a 144-tile board")
expect(mj.status_bar ~= nil and mj.status_bar.title == "Mahjong Solitaire",
    "status bar created with the right title")
expect(mj[1] ~= nil, "full-screen layout built into self[1]")

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

local new_game_btn = mj[1][2][1]
expect(type(new_game_btn.callback) == "function", "New Game button wired")
ctx.last_confirm = nil
new_game_btn.callback()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text == "Start a new game?",
    "New Game opens its ConfirmBox")
local old_board = mj.board
ctx.last_confirm.ok_callback()
expect(mj.board ~= old_board and Logic.tileCount(mj.board) == 144,
    "New Game ok builds a fresh board")

-- ---- Close / exit --------------------------------------------------------

local mj_close_cb = mj.status_bar.close_callback
ctx.last_confirm = nil
mj_close_cb()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text == "Exit Mahjong Solitaire?",
    "close_callback opens its ConfirmBox")
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
