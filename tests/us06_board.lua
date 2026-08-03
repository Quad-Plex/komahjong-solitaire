-- US-06 (3D turtle) board suite: loads the REAL mahjonglogic.lua +
-- mahjongboard.lua against the shared stubs and verifies the offset-layer
-- board rendering. Checks: geometry fitting, per-layer tile counts, z-order,
-- layer offsets, hit-testing (topmost wins), tap forwarding (x,y,layer) via
-- both the direct and the real KOReader dispatch path, updateBoard after
-- removal, and main.lua wiring.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Board = ctx.loadPlugin("mahjongboard")

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

-- ---- Board widget in isolation ------------------------------------------------

local board = Logic.newGame(42)
local taps = {}
local b = Board:new{
    board = board,
    width = 1200,
    height = 600,
    onTileTap = function(x, y, layer) taps[#taps + 1] = { x, y, layer } end,
}

expect(b.grid.x_min == 1 and b.grid.x_max == 12 and b.grid.y_min == 2 and b.grid.y_max == 7,
    "grid bounds are 1..12 x 2..7")
expect(b.tw > 0 and b.th > 0, "tile size computed (" .. b.tw .. "x" .. b.th .. ")")
expect(b.th > b.tw, "tiles are portrait (th > tw)")

local function tileCount()
    local n = 0
    for l = 0, Logic.MAX_LAYER do n = n + #(b.tiles_by_layer[l] or {}) end
    return n
end
expect(tileCount() == 144, "all 144 tiles are drawn (got " .. tileCount() .. ")")
expect(#b[1][1] == 144, "OverlapGroup holds 144 icon widgets")

local layer_sizes = {}
for l = 0, Logic.MAX_LAYER do layer_sizes[l] = #b.tiles_by_layer[l] end
expect(layer_sizes[0] == 60 and layer_sizes[1] == 48 and layer_sizes[2] == 24
    and layer_sizes[3] == 8 and layer_sizes[4] == 4,
    "per-layer tile counts match the Turtle layout")

-- Every drawn tile stays inside the widget area.
local all_inside = true
for l = 0, Logic.MAX_LAYER do
    for _, t in ipairs(b.tiles_by_layer[l]) do
        if t.px < 0 or t.py < 0 or t.px + t.w > b.width or t.py + t.h > b.height then
            all_inside = false
        end
    end
end
expect(all_inside, "all tiles fit inside the widget area")

-- Z-order: children are appended in buildLayout order (bottom layer first), so
-- lower layers paint first and upper layers land on top.
local children = b[1][1]
local zi = 1
local z_order_ok = true
for _, p in ipairs(Logic.buildLayout()) do
    if Logic.tileAt(board, p.x, p.y, p.layer) then
        local px, py = b:tilePos(p.x, p.y, p.layer)
        local c = children[zi]
        if not c or c.overlap_offset[1] ~= px or c.overlap_offset[2] ~= py then
            z_order_ok = false
        end
        zi = zi + 1
    end
end
expect(zi - 1 == 144 and z_order_ok, "children appended in buildLayout order (bottom layer first)")

-- Layer offset: same (x,y) in a higher layer sits up-and-right of the lower.
local px0, py0 = b:tilePos(2, 2, 0)
local px1, py1 = b:tilePos(2, 2, 1)
local px2, py2 = b:tilePos(2, 2, 2)
expect(px1 > px0 and py1 < py0, "L1 is offset right-and-up from L0")
expect(px2 > px1 and py2 < py1, "L2 is offset right-and-up from L1")
expect(px1 - px0 == b.offx and py0 - py1 == b.offy, "offsets equal one layer step")

-- ---- Hit-testing: topmost tile at a point wins ---------------------------------

local function pk(x, y, l) return Logic.posKey(x, y, l) end
local proj = {}
proj[pk(5, 3, 0)] = "b1"
proj[pk(5, 3, 1)] = "c2"
proj[pk(5, 3, 2)] = "d3"
proj[pk(9, 6, 0)] = "east"

local p = Board:new{ board = proj, width = 600, height = 400 }

local lp0x, lp0y = p:tilePos(5, 3, 0)
local lp1x, lp1y = p:tilePos(5, 3, 1)
local lp2x, lp2y = p:tilePos(5, 3, 2)
local epx, epy = p:tilePos(9, 6, 0)

local h = p:hitTest(lp2x + 2, lp2y + 2)
expect(h ~= nil and h.layer == 2 and h.kind == "d3", "tap on top tile hits L2")
h = p:hitTest(lp1x + 2, lp1y + 2)
expect(h ~= nil and h.layer == 1 and h.kind == "c2", "tap on exposed L1 top-left hits L1 (not L2)")
h = p:hitTest(lp0x + p.tw - 2, lp0y + p.th - 2)
expect(h ~= nil and h.layer == 0 and h.kind == "b1", "tap on exposed L0 bottom-right hits L0")
h = p:hitTest(epx + 2, epy + 2)
expect(h ~= nil and h.layer == 0 and h.kind == "east", "tap on lone tile hits it")
h = p:hitTest(0, 0)
expect(h == nil, "tap on empty area hits nothing")

-- ---- Tap forwarding (x, y, layer) ---------------------------------------------

local taps2 = {}
local p3 = Board:new{ board = proj, width = 300, height = 200, onTileTap = function(x, y, layer) taps2[#taps2 + 1] = { x, y, layer } end }
p3.dimen.x, p3.dimen.y = 0, 0
local p3x, p3y = p3:tilePos(5, 3, 0)
local g = { pos = { x = p3x + p3.tw - 2, y = p3y + p3.th - 2 } }
p3:onTapSelect(nil, g)
expect(#taps2 == 1 and taps2[1][1] == 5 and taps2[1][2] == 3 and taps2[1][3] == 0,
    "onTapSelect forwards (5, 3, 0) for a tap on the exposed L0 tile")

-- Simulate KOReader's REAL dispatch (regression for a device crash):
-- onGesture does Event:new(name, gsseq.args, ev) which table.pack()s the
-- args; EventListener:handleEvent then calls self[handler](self, unpack(...)).
-- With no `args` in the gesture spec, the handler receives (nil, ges_event),
-- so the handler MUST read the gesture from its SECOND parameter.
local dispatched = nil
local p4 = Board:new{ board = proj, width = 300, height = 200, onTileTap = function(x, y, layer) dispatched = { x, y, layer } end }
p4.dimen.x, p4.dimen.y = 0, 0
local p4x, p4y = p4:tilePos(9, 6, 0)
local ev = { pos = { x = p4x + 2, y = p4y + 2 } }
local packed = { nil, ev, n = 2 }
p4["onTapSelect"](p4, unpack(packed, 1, packed.n))
expect(dispatched ~= nil and dispatched[1] == 9 and dispatched[2] == 6 and dispatched[3] == 0,
    "real dispatch path (unpacked args) forwards (9, 6, 0)")

-- ---- updateBoard after a removal ----------------------------------------------

local function tileCountFor(w)
    local n = 0
    for l = 0, Logic.MAX_LAYER do n = n + #(w.tiles_by_layer[l] or {}) end
    return n
end

proj[pk(5, 3, 2)] = nil
p:updateBoard()
expect(#p.tiles_by_layer[2] == 0 and tileCountFor(p) == 3, "removed tile is no longer drawn")
h = p:hitTest(lp2x + 2, lp2y + 2)
expect(h == nil, "removed tile's old spot is no longer tappable")

-- ---- main.lua integration ------------------------------------------------------

local Mahjong = ctx.loadPlugin("main")
expect(type(Mahjong) == "table" and Mahjong.name == "mahjong", "main.lua returns the plugin class")

local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()

expect(#ctx.window_stack == 1 and ctx.window_stack[1].widget == mj, "startGame shows the plugin widget")
expect(type(mj.board) == "table" and Logic.tileCount(mj.board) == 144, "startGame created a 144-tile board")

local board_area = mj[1][1]
local board_widget = board_area[1]
expect(type(board_widget) == "table" and type(board_widget.tiles_by_layer) == "table",
    "layout contains the 3D board widget")
expect(board_widget.board == mj.board, "board widget renders the same board state")
expect(tileCountFor(board_widget) == 144, "game board draws all 144 tiles")

local tapped = nil
mj.handleTileTap = function(_, x, y, layer) tapped = { x, y, layer } end
board_widget.dimen.x, board_widget.dimen.y = 0, 0
local bpx, bpy = board_widget:tilePos(4, 4, 4)
board_widget:onTapSelect(nil, { pos = { x = bpx + 1, y = bpy + 1 } })
expect(tapped ~= nil and tapped[1] == 4 and tapped[2] == 4 and tapped[3] == 4,
    "board tap reaches Mahjong:handleTileTap with (4, 4, 4)")

local new_game_btn = mj[1][2][1]
expect(type(new_game_btn.callback) == "function", "New Game button wired")
ctx.last_confirm = nil
new_game_btn.callback()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text == "Start a new game?", "New Game opens its ConfirmBox")
local old_board = mj.board
ctx.last_confirm.ok_callback()
expect(mj.board ~= old_board and Logic.tileCount(mj.board) == 144, "New Game ok builds a fresh board")

-- Close flow still works and clears the board
local mj_close_cb = mj.status_bar.close_callback
ctx.last_confirm = nil
mj_close_cb()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text == "Exit Mahjong Solitaire?", "close_callback opens its ConfirmBox")
ctx.last_confirm.ok_callback()
local mj_still_on_stack = false
for _, e in ipairs(ctx.window_stack) do
    if e.widget == mj then mj_still_on_stack = true end
end
expect(not mj_still_on_stack, "exit removed the plugin widget from the window stack")
expect(mj.board == nil, "onCloseWidget cleared self.board")

if failures == 0 then
    print("\nALL US-06 (3D turtle) BOARD CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
