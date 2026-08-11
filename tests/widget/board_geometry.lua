-- US-06 (3D turtle) board suite: loads the REAL mahjonglogic.lua +
-- mahjongboard.lua against the shared stubs and verifies the outward-bevel
-- board rendering. Checks: geometry fitting, per-layer tile counts, z-order,
-- per-layer up-left shift by the bevel width, bevel-extended icon dimen,
-- hit-testing (topmost wins), tap forwarding (x,y,layer) via both the direct
-- and the real KOReader dispatch path, updateBoard after removal, and
-- main.lua wiring.

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

-- ---- Board widget in isolation ------------------------------------------------

local board = Logic.newGame(42)
local taps = {}
local b = Board:new{
    board = board,
    width = 1200,
    height = 600,
    onTileTap = function(x, y, layer) taps[#taps + 1] = { x, y, layer } end,
}

expect(b.grid.x_min == 0 and b.grid.x_max == 14 and b.grid.y_min == 0 and b.grid.y_max == 7,
    "grid bounds are 0..14 x 0..7")
expect(b.tw > 0 and b.th > 0, "tile size computed (" .. b.tw .. "x" .. b.th .. ")")
expect(b.th > b.tw, "tiles are portrait (th > tw)")

local function tileCount()
    local n = 0
    for l = 0, Logic.MAX_LAYER do n = n + #(b.tiles_by_layer[l] or {}) end
    return n
end
expect(tileCount() == 144, "all 144 tiles are drawn (got " .. tileCount() .. ")")
expect(tileCount() == 144, "face widget map holds 144 tile faces")
expect(#b[1][1] > 144, "OverlapGroup includes independently rendered bevel widgets")

local layer_sizes = {}
for l = 0, Logic.MAX_LAYER do layer_sizes[l] = #b.tiles_by_layer[l] end
expect(layer_sizes[0] == 87 and layer_sizes[1] == 36 and layer_sizes[2] == 16
    and layer_sizes[3] == 4 and layer_sizes[4] == 1,
    "per-layer tile counts match the classic Turtle (87/36/16/4/1)")

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

-- Z-order: children are appended by layer and diagonal depth, so lower layers
-- paint first and diagonal half-overlaps land on top.
local children = b[1][1]
local function pk(x, y, l) return Logic.posKey(x, y, l) end
local zi = 1
local z_order_ok = true
local ordered = {}
for _, p in ipairs(Logic.buildLayout()) do
    ordered[#ordered + 1] = p
end
table.sort(ordered, function(a, b)
    if a.layer ~= b.layer then return a.layer < b.layer end
    local da, db = a.x + a.y, b.x + b.y
    if da ~= db then return da < db end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
end)
local child_index = 1
for _, p in ipairs(ordered) do
    if Logic.tileAt(board, p.x, p.y, p.layer) then
        local px, py = b:tilePos(p.x, p.y, p.layer)
        local face = b.tile_widgets[pk(p.x, p.y, p.layer)]
        local c = children[child_index]
        if c ~= face or c.overlap_offset[1] ~= px or c.overlap_offset[2] ~= py then
            z_order_ok = false
        end
        child_index = child_index + 1
        for _, segment in ipairs(b.tile_bevels[pk(p.x, p.y, p.layer)] or {}) do
            if children[child_index] ~= b.bevel_widgets[pk(p.x, p.y, p.layer) .. ":" .. segment] then
                z_order_ok = false
            end
            child_index = child_index + 1
        end
        zi = zi + 1
    end
end
expect(zi - 1 == 144 and child_index - 1 == #children and z_order_ok,
    "faces and bevels use diagonal depth order (bottom layer first)")

-- Layer offset: each layer L is shifted up-left by L*bw / L*bh (the outward
-- bevel thickness), so a raised tile's face is inset from the tile directly
-- beneath it and its bevels land exactly on that underlying tile's face
-- edges — the visible step between layers.
local px0, py0 = b:tilePos(2, 2, 0)
local px1, py1 = b:tilePos(2, 2, 1)
local px2, py2 = b:tilePos(2, 2, 2)
expect(px1 == px0 - b.bw and py1 == py0 - b.bh
    and px2 == px0 - 2 * b.bw and py2 == py0 - 2 * b.bh,
    "each layer is shifted up-left by the bevel width (L*BW / L*BH)")
expect(b.bw > 0 and b.bh > 0, "outward bevel thickness computed (" .. b.bw .. "x" .. b.bh .. ")")
expect(b.tile_w == b.tw + b.bw and b.tile_h == b.th + b.bh,
    "icon widget dimen is face + bevel (tile_w/tile_h)")
local icon_widget = b.tile_widgets[Logic.posKey(2, 2, 0)]
expect(icon_widget.width == b.tw and icon_widget.height == b.th,
    "face IconWidgets are sized to the grid pitch")
local bevel_widget = next(b.bevel_widgets)
expect(bevel_widget ~= nil and b.bevel_widgets[bevel_widget].width == b.tile_w
        and b.bevel_widgets[bevel_widget].height == b.tile_h,
    "bevel IconWidgets use the face-plus-bevel canvas")

-- ---- Hit-testing: topmost tile at a point wins ---------------------------------

local proj = {}
proj[pk(5, 3, 0)] = "b1"
proj[pk(5, 3, 1)] = "c2"
proj[pk(5, 3, 2)] = "d3"
proj[pk(9, 6, 0)] = "east"

local p = Board:new{ board = proj, width = 600, height = 400 }

local lpx, lpy = p:tilePos(5, 3, 0)
local epx, epy = p:tilePos(9, 6, 0)

local h = p:hitTest(lpx + 2, lpy + 2)
expect(h ~= nil and h.layer == 2 and h.kind == "d3",
    "tap on a 3-tile stack hits the topmost layer (L2)")
h = p:hitTest(lpx + p.tw - 1, lpy + p.th - 1)
expect(h ~= nil and h.layer == 0 and h.kind == "b1",
    "raised tiles are shifted up-left, so the stack's bottom-right corner exposes the bottom tile (L0)")
h = p:hitTest(epx + 2, epy + 2)
expect(h ~= nil and h.layer == 0 and h.kind == "east", "tap on lone tile hits it")
h = p:hitTest(0, 0)
expect(h == nil, "tap on empty area hits nothing")

-- Removing the top tile exposes the one below it at the same grid position.
proj[pk(5, 3, 2)] = nil
proj[pk(5, 3, 1)] = nil
p:updateBoard()
h = p:hitTest(lpx + 2, lpy + 2)
expect(h ~= nil and h.layer == 0 and h.kind == "b1",
    "lower tile is hit after the tiles above it were removed")

-- ---- Tap forwarding (x, y, layer) ---------------------------------------------

local taps2 = {}
local p3 = Board:new{ board = proj, width = 300, height = 200, onTileTap = function(x, y, layer) taps2[#taps2 + 1] = { x, y, layer } end }
p3.dimen.x, p3.dimen.y = 0, 0
local p3x, p3y = p3:tilePos(9, 6, 0)
local g = { pos = { x = p3x + p3.tw - 2, y = p3y + p3.th - 2 } }
p3:onTapSelect(nil, g)
expect(#taps2 == 1 and taps2[1][1] == 9 and taps2[1][2] == 6 and taps2[1][3] == 0,
    "onTapSelect forwards (9, 6, 0) for a tap on the lone tile")

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

local projB = {}
projB[pk(5, 3, 0)] = "b1"
projB[pk(5, 3, 1)] = "c2"
projB[pk(9, 6, 0)] = "east"
local pB = Board:new{ board = projB, width = 600, height = 400 }
projB[pk(5, 3, 1)] = nil
pB:updateBoard()
expect(#pB.tiles_by_layer[1] == 0 and tileCountFor(pB) == 2, "removed tile is no longer drawn")
local blpx, blpy = pB:tilePos(5, 3, 0)
h = pB:hitTest(blpx + 2, blpy + 2)
expect(h ~= nil and h.layer == 0 and h.kind == "b1",
    "after removal the tile below is drawn and tappable")

-- ---- main.lua integration ------------------------------------------------------

local Mahjong = ctx.loadPlugin("main")
expect(type(Mahjong) == "table" and Mahjong.name == "mahjong", "main.lua returns the plugin class")

local mj = Mahjong:new()
local menu_items = {}
mj:addToMainMenu(menu_items)
menu_items.mahjong.callback()
pickTurtle()

expect(#ctx.window_stack == 1 and ctx.window_stack[1].widget == mj, "startGame shows the plugin widget")
expect(type(mj.board) == "table" and Logic.tileCount(mj.board) == 144, "startGame created a 144-tile board")

local board_area = mj[1][2]
local board_widget = board_area[1]
expect(type(board_widget) == "table" and type(board_widget.tiles_by_layer) == "table",
    "layout contains the 3D board widget")
expect(board_widget.board == mj.board, "board widget renders the same board state")
expect(tileCountFor(board_widget) == 144, "game board draws all 144 tiles")

local tapped = nil
mj.handleTileTap = function(_, x, y, layer) tapped = { x, y, layer } end
board_widget.dimen.x, board_widget.dimen.y = 0, 0
local bpx, bpy = board_widget:tilePos(6.5, 3.5, 4)
board_widget:onTapSelect(nil, { pos = { x = bpx + 1, y = bpy + 1 } })
expect(tapped ~= nil and tapped[1] == 6.5 and tapped[2] == 3.5 and tapped[3] == 4,
    "board tap reaches Mahjong:handleTileTap with (6.5, 3.5, 4)")

local new_game_btn = nil
for i = 1, #mj[1][4] do
    local b = mj[1][4][i]
    if type(b) == "table" and b.bordersize and b.icon == "plus" then
        new_game_btn = b
    elseif type(b) == "table" and b[1] and b[1].bordersize and b[1].icon == "plus" then
        new_game_btn = b[1] -- a toolbar cell: VerticalGroup{ button, label }
    end
end
expect(type(new_game_btn.callback) == "function", "New Game button wired")
ctx.last_confirm = nil
new_game_btn.callback()
-- US-14: New Game shows the picker (choosing a layout IS the confirmation).
expect(ctx.last_confirm == nil, "New Game no longer opens a ConfirmBox (picker instead)")
expect(ctx.window_stack[#ctx.window_stack].widget ~= nil
        and ctx.window_stack[#ctx.window_stack].widget.name == "mahjonglayoutselect",
    "New Game opens the layout picker")
local old_board = mj.board
pickTurtle()
expect(ctx.last_confirm ~= nil and ctx.last_confirm.text ==
        "Start a new game? Your current game will be stopped.",
    "picking a layout over the running game opens a replacement confirmation")
expect(mj.board == old_board, "the running game remains until replacement is confirmed")
ctx.last_confirm.ok_callback()
expect(mj.board ~= old_board and Logic.tileCount(mj.board) == 144,
    "confirming the layout choice builds a fresh board")

-- Close flow still works and clears the board
local mj_close_cb = mj.status_bar.right_icon_tap_callback
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
