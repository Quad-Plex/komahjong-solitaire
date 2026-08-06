-- US-07 gameplay suite: select, match, remove, win, dead-board shuffle.
--
-- Loads the REAL mahjonglogic + mahjongboard + main and drives the full tap
-- flow. Checks:
--   * logic hooks (removePair / isWin / matchingFreePair / shuffleBoard) — the
--     deep rule coverage also lives in mahjonglogic.lua's embedded self-tests;
--   * selecting a free tile highlights it with the `select` overlay;
--   * tapping a matching free tile removes both (logic board + rendered board),
--     clears the selection, bumps the score stub, and updates the status bar;
--   * tapping the selected tile again deselects;
--   * tapping a non-free tile is ignored;
--   * tapping a different non-matching tile switches the selection;
--   * removing the last pair shows the Win dialog; "Play again" resets to a
--     fresh 144-tile board; "Close" exits;
--   * after a removal that leaves no moves, the remaining tiles are shuffled
--     immediately (US-07 simple variant; US-08 adds the prompt UX);
--   * board taps reach Mahjong:handleTileTap via the real dispatch path.

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

local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local function pk(x, y, l) return Logic.posKey(x, y, l) end
local function boardWith(tiles)
    local b = {}
    for _, t in ipairs(tiles) do b[pk(t[1], t[2], t[3])] = t[4] end
    return b
end
local function sortedKinds(board)
    local kinds = {}
    for _, k in pairs(board) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    return kinds
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

-- ---- Logic hooks (US-07) --------------------------------------------------

local l1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"} }
expect(Logic.removePair(l1, { x = 2, y = 2, layer = 0 }, { x = 4, y = 2, layer = 0 }) == true,
    "logic removePair accepts a valid matching free pair")
expect(Logic.tileCount(l1) == 1 and Logic.tileAt(l1, 6, 2, 0) == "c1",
    "logic removePair leaves exactly the other tile")
expect(not Logic.removePair(l1, { x = 2, y = 2, layer = 0 }, { x = 4, y = 2, layer = 0 }),
    "logic removePair rejects a pair whose tile is already gone")
expect(Logic.isWin(boardWith{}), "logic isWin true on an empty board")
expect(not Logic.isWin(boardWith{ {2,2,0,"b1"} }), "logic isWin false with a tile left")
local lp = Logic.matchingFreePair(boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"} })
expect(lp ~= nil and Logic.matches(lp.a.kind, lp.b.kind), "logic matchingFreePair finds a move")
expect(Logic.matchingFreePair(boardWith{ {2,2,0,"c1"}, {4,2,0,"c2"} }) == nil,
    "logic matchingFreePair nil when no move exists")

-- ---- Full-turtle flow: select, match, remove --------------------------------

local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
pickTurtle()
expect(#ctx.window_stack >= 1 and mj.board and Logic.tileCount(mj.board) == 144,
    "startGame shows a full 144-tile game")

local free = Logic.freeTiles(mj.board)
local i, j
for a = 1, #free - 1 do
    for b = a + 1, #free do
        if Logic.matches(free[a].kind, free[b].kind) then
            i, j = a, b
            break
        end
    end
    if i then break end
end
expect(i ~= nil, "a full turtle has a playable free pair")

local tileA, tileB = free[i], free[j]
mj:handleTileTap(tileA.x, tileA.y, tileA.layer)
expect(mj.selected ~= nil and mj.selected.kind == tileA.kind
    and mj.selected.x == tileA.x and mj.selected.y == tileA.y and mj.selected.layer == tileA.layer,
    "tapping a free tile selects it")
expect(mapCount(mj.board_view.overlays) == 1,
    "selection draws the select overlay")

mj:handleTileTap(tileB.x, tileB.y, tileB.layer)
expect(mj.selected == nil, "matching tap clears the selection")
expect(Logic.tileCount(mj.board) == 142,
    "matching tap removes the pair from the logic board")
expect(mapCount(mj.board_view.tile_widgets) == 142 and mapCount(mj.board_view.overlays) == 0,
    "pair removal drops exactly the two widgets and any overlays")
expect(mj.score == 10, "score stub adds 10 per pair (got " .. tostring(mj.score) .. ")")
expect(mj.status_bar.stats.pairs == 71
        and mj.status_bar.stats.free == Logic.countFreePairs(mj.board)
        and mj.status_bar.stats.score == 10,
    "HUD chips show the remaining pairs, free pairs, and score (got "
        .. tostring(mj.status_bar.stats.pairs) .. "/" .. tostring(mj.status_bar.stats.free)
        .. "/" .. tostring(mj.status_bar.stats.score) .. ")")
local window_dirtied = false
for _, c in ipairs(ctx.dirty_calls) do
    if c.widget == mj then window_dirtied = true end
end
expect(window_dirtied,
    "status update dirties the window-level widget (repaint actually happens)")

-- ---- Deselect ----------------------------------------------------------------

local free2 = Logic.freeTiles(mj.board)
mj:handleTileTap(free2[1].x, free2[1].y, free2[1].layer)
expect(mj.selected ~= nil, "selecting again after a removal works")
mj:handleTileTap(free2[1].x, free2[1].y, free2[1].layer)
expect(mj.selected == nil and mapCount(mj.board_view.overlays) == 0,
    "tapping the selected tile again deselects it")

-- ---- Non-free taps are ignored ------------------------------------------------

local mj_edge = Mahjong:new()
mj_edge.board = boardWith{
    {5,3,0,"b1"}, {5,3,1,"b2"},     -- L0 covered from above
    {3,2,0,"c1"}, {4,2,0,"c2"}, {5,2,0,"c3"}, -- middle blocked on both sides
}
mj_edge:buildUILayout()
mj_edge:handleTileTap(5, 3, 0)
expect(mj_edge.selected == nil, "a covered tile is ignored")
mj_edge:handleTileTap(4, 2, 0)
expect(mj_edge.selected == nil, "a tile blocked on both sides is ignored")

-- ---- Switching selection ------------------------------------------------------

mj_edge:handleTileTap(3, 2, 0)
expect(mj_edge.selected ~= nil and mj_edge.selected.kind == "c1",
    "selecting an isolated free tile works")
mj_edge:handleTileTap(5, 2, 0)
expect(mj_edge.selected ~= nil and mj_edge.selected.kind == "c3"
    and mapCount(mj_edge.board_view.overlays) == 1,
    "tapping a different non-matching tile switches the selection")

-- ---- Win dialog: Play again ----------------------------------------------------

local mj_win = Mahjong:new()
mj_win.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"} }
mj_win:buildUILayout()
mj_win:handleTileTap(2, 2, 0)
mj_win:handleTileTap(4, 2, 0)
expect(Logic.isWin(mj_win.board), "removing the last pair empties the board")
expect(ctx.last_confirm ~= nil and ctx.last_confirm.ok_text == "Play again"
    and tostring(ctx.last_confirm.text):find("Score: 10", 1, true) ~= nil,
    "win dialog is shown with the final score")
ctx.last_confirm.ok_callback()
-- US-14: "Play again" shows the picker; pick Turtle to deal the fresh board.
pickTurtle()
expect(Logic.tileCount(mj_win.board) == 144 and mj_win.score == 0 and mj_win.selected == nil,
    "'Play again' resets to a fresh shuffled board")
expect(mj_win.status_bar.stats.pairs == 72
        and mj_win.status_bar.stats.free == Logic.countFreePairs(mj_win.board)
        and mj_win.status_bar.stats.score == 0,
    "HUD chips reset after play-again (got "
        .. tostring(mj_win.status_bar.stats.pairs) .. "/" .. tostring(mj_win.status_bar.stats.free)
        .. "/" .. tostring(mj_win.status_bar.stats.score) .. ")")

-- ---- Win dialog: Close ----------------------------------------------------------

local mj_win2 = Mahjong:new()
mj_win2.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"} }
mj_win2:buildUILayout()
mj_win2:handleTileTap(2, 2, 0)
mj_win2:handleTileTap(4, 2, 0)
expect(ctx.last_confirm ~= nil and ctx.last_confirm.cancel_text == "Close",
    "win dialog offers Close")
ctx.last_confirm.cancel_callback()
local still_on_stack = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj_win2 then still_on_stack = true end
end
expect(not still_on_stack and mj_win2.board == nil,
    "'Close' exits the game and clears the board")

-- ---- Dead board: shuffle prompt (US-08) → US-32 loss dialog ------------------

local mj_dead = Mahjong:new()
mj_dead.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"},   -- playable pair
    {6,2,0,"c1"}, {8,2,0,"c2"},   -- leftovers: no move possible, odd parity → dead
}
mj_dead:buildUILayout()
ctx.last_confirm = nil
mj_dead:handleTileTap(2, 2, 0)
mj_dead:handleTileTap(4, 2, 0)
expect(Logic.tileCount(mj_dead.board) == 2, "pair removed from the dead-board game")
expect(ctx.last_confirm ~= nil
        and tostring(ctx.last_confirm.text):find("can't help", 1, true) ~= nil,
    "dead board with odd parity shows the loss dialog (not the shuffle prompt)")
expect(mj_dead.score == 10 and #mj_dead.history == 1,
    "the removal that dead-locked the board still counts")

-- Undo restores the last pair so the player can try a different approach.
expect(ctx.last_confirm.other_buttons ~= nil
        and ctx.last_confirm.other_buttons[1][1].text:find("Undo", 1, true),
    "loss dialog has an Undo button")
ctx.last_confirm.other_buttons[1][1].callback()
expect(Logic.tileCount(mj_dead.board) == 4, "undo from the loss dialog restores the pair")
expect(mapCount(mj_dead.board_view.tile_widgets) == 4,
    "board view has all 4 tiles after undo")

-- ---- Board tap forwarding ---------------------------------------------------------

local mj_tap = Mahjong:new()
mj_tap.board = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {9,6,0,"east"} }
mj_tap:buildUILayout()
local bv = mj_tap.board_view
bv.dimen.x, bv.dimen.y = 0, 0
local px, py = bv:tilePos(9, 6, 0)
bv:onTapSelect(nil, { pos = { x = px + 2, y = py + 2 } })
expect(mj_tap.selected ~= nil and mj_tap.selected.kind == "east",
    "a board tap reaches handleTileTap and selects the tile")

if failures == 0 then
    print("\nALL US-07 GAMEPLAY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
