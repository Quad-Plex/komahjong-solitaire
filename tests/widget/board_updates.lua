-- P1 refactor suite: incremental board updates + overlays.
--
-- * removeTile / removePair drop only the affected widgets from the
--   OverlapGroup (no full 144-widget rebuild) and keep the hit-test table
--   (tiles_by_layer) consistent.
-- * setOverlay / clearOverlay / clearAllOverlays add select/hint highlights
--   on top of all tiles; overlays never appear in hit-testing.
-- * buildLayout() / gridBounds() are memoized (stable table references).

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

local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local function tilesOf(w)
    return mapCount(w.tile_widgets)
end

-- ---- Memoized layout / bounds ---------------------------------------------

expect(Logic.buildLayout() == Logic.buildLayout(), "buildLayout() is memoized (same table)")
expect(Logic.gridBounds() == Logic.gridBounds(), "gridBounds() is memoized (same table)")
expect(#Logic.buildLayout() == 144, "memoized layout still has 144 positions")

-- ---- Incremental removal ---------------------------------------------------

local function pk(x, y, l) return Logic.posKey(x, y, l) end
local proj = {}
proj[pk(5, 3, 0)] = "b1"
proj[pk(5, 3, 1)] = "c2"
proj[pk(5, 3, 2)] = "d3"
proj[pk(9, 6, 0)] = "east"

local p = Board:new{ board = proj, width = 600, height = 400 }
expect(mapCount(p.tile_widgets) == 4, "tile_widgets map has one entry per tile")
expect(#p.overlap > 4 and mapCount(p.bevel_widgets) > 0,
    "OverlapGroup includes separate bevel widgets")

local removed = p:removeTile(5, 3, 2)
expect(removed == true, "removeTile returns true for a present tile")
expect(tilesOf(p) == 3 and #p.overlap == tilesOf(p) + mapCount(p.bevel_widgets),
    "removeTile drops the face and bevel widgets from paint stack and maps")
local lpx, lpy = p:tilePos(5, 3, 2)
expect(p:hitTest(lpx + 2, lpy + 2) == nil,
    "removed top tile's spot is empty (the L1 tile below is offset up-left by the bevel)")

expect(p:removeTile(5, 3, 2) == false, "removeTile returns false for a missing tile")

local lp1x, lp1y = p:tilePos(5, 3, 1)
local h = p:hitTest(lp1x + 2, lp1y + 2)
expect(h ~= nil and h.layer == 1 and h.kind == "c2",
    "lower tile is hit after the tile above it was removed")

-- removePair removes exactly the two tiles
local proj2 = {}
proj2[pk(5, 3, 0)] = "b1"
proj2[pk(9, 6, 0)] = "east"
proj2[pk(2, 2, 0)] = "west"
local p2 = Board:new{ board = proj2, width = 600, height = 400 }
local ok = p2:removePair({ x = 5, y = 3, layer = 0 }, { x = 9, y = 6, layer = 0 })
expect(ok == true and tilesOf(p2) == 1
        and #p2.overlap == tilesOf(p2) + mapCount(p2.bevel_widgets),
    "removePair removes both faces and their bevels, leaving the third")
local rpx, rpy = p2:tilePos(2, 2, 0)
expect(p2:hitTest(rpx + 1, rpy + 1).kind == "west", "remaining tile still hit-tests")

-- A clear must repaint the tiles that disappeared, plus only a same-layer
-- neighbour whose bevel artwork actually changed. Speculative west/north
-- candidates used to make isolated clears drive an unnecessary ~2-tile region.
local isolated = {}
isolated[pk(2, 2, 0)] = "b1"
isolated[pk(10, 6, 0)] = "b1"
local isolated_board = Board:new{ board = isolated, width = 600, height = 400 }
ctx.dirty_calls = {}
isolated_board:removePair({ x = 2, y = 2, layer = 0 }, { x = 10, y = 6, layer = 0 })
expect(#ctx.dirty_calls == 2,
    "isolated pair clear refreshes only the two removed tile regions")

local bevel = {}
bevel[pk(4, 3, 0)] = "b1"
bevel[pk(5, 3, 0)] = "b1"
bevel[pk(10, 6, 0)] = "c1"
local bevel_board = Board:new{ board = bevel, width = 600, height = 400 }
local retained_west_face = bevel_board.tile_widgets[pk(4, 3, 0)]
ctx.dirty_calls = {}
-- The board view is deliberately updated after the logic board, as main.lua
-- does before invoking Board:removePair.
bevel[pk(5, 3, 0)] = nil
bevel[pk(10, 6, 0)] = nil
bevel_board:removePair({ x = 5, y = 3, layer = 0 }, { x = 10, y = 6, layer = 0 })
local west_x, west_y = bevel_board:tilePos(4, 3, 0)
local refreshed_west_neighbour = false
local refreshed_west_face = false
for _, call in ipairs(ctx.dirty_calls) do
    local region = call.region
    if region and west_x + bevel_board.tw >= region.x
            and west_x + bevel_board.tw < region.x + region.w
            and west_y >= region.y and west_y < region.y + region.h then
        refreshed_west_neighbour = true
    end
    if region and region.x <= west_x and region.x + region.w > west_x
            and region.y <= west_y and region.y + region.h > west_y then
        refreshed_west_face = true
    end
end
expect(refreshed_west_neighbour,
    "pair clear includes a neighbour only when its exposed bevel changes")
expect(not refreshed_west_face,
    "exposed bevel refresh does not dirty the neighboring tile face")
expect(bevel_board.tile_widgets[pk(4, 3, 0)] == retained_west_face,
    "exposing a bevel preserves the neighboring face widget")

-- ---- Overlays ---------------------------------------------------------------

local p3 = Board:new{ board = proj2, width = 600, height = 400 }
local ox, oy = p3:tilePos(5, 3, 0)

expect(p3:setOverlay(5, 3, 0, "select") == true, "setOverlay succeeds on a present tile")
expect(mapCount(p3.overlays) == 1
        and #p3.overlap == tilesOf(p3) + mapCount(p3.bevel_widgets) + 1,
    "overlay registered on top of the tiles")
expect(p3:hitTest(ox + 2, oy + 2).kind == "b1", "overlay does not shadow hit-testing")

expect(p3:setOverlay(1, 1, 0, "select") == false, "setOverlay fails on a missing tile")

p3:setOverlay(5, 3, 0, "hint")
expect(mapCount(p3.overlays) == 1
        and #p3.overlap == tilesOf(p3) + mapCount(p3.bevel_widgets) + 1,
    "setOverlay replaces an existing overlay")

expect(p3:clearOverlay(5, 3, 0) == true, "clearOverlay returns true when an overlay existed")
expect(mapCount(p3.overlays) == 0
        and #p3.overlap == tilesOf(p3) + mapCount(p3.bevel_widgets),
    "clearOverlay removes the overlay widget")
expect(p3:clearOverlay(5, 3, 0) == false, "clearOverlay returns false when none existed")

p3:setOverlay(5, 3, 0, "select")
p3:setOverlay(9, 6, 0, "select")
p3:clearAllOverlays()
expect(mapCount(p3.overlays) == 0
        and #p3.overlap == tilesOf(p3) + mapCount(p3.bevel_widgets),
    "clearAllOverlays removes every overlay")

-- removing a tile drops an overlay that was sitting on it
p3:setOverlay(5, 3, 0, "select")
p3:removeTile(5, 3, 0)
expect(mapCount(p3.overlays) == 0
        and #p3.overlap == tilesOf(p3) + mapCount(p3.bevel_widgets),
    "removeTile drops the tile's overlay too")

-- ---- updateBoard (full rebuild) resets maps and overlays ---------------------

local proj3 = {}
for k, v in pairs(proj2) do proj3[k] = v end
proj3[pk(3, 2, 0)] = "red"
p3.board = proj3
p3:updateBoard()
expect(tilesOf(p3) == 4
        and #p3.overlap == tilesOf(p3) + mapCount(p3.bevel_widgets)
        and mapCount(p3.overlays) == 0,
    "updateBoard rebuilds tiles and clears stale overlays")

-- ---- Window-level repaint regression --------------------------------------
-- The board is NOT a window-level widget, so setDirty(self) would never flag
-- anything for repaint on a real device (only window-level widgets get
-- repainted). Every board mutation must request a repaint via the "all"
-- sentinel (as the chess reference boards do).

local p4 = Board:new{ board = proj3, width = 600, height = 400 }
local function dirtyTargetsAll()
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == "all" and c.refreshtype == "ui" then return true end
    end
    return false
end

ctx.dirty_calls = {}
p4:setOverlay(5, 3, 0, "select")
expect(dirtyTargetsAll(), "setOverlay dirties the window-level widget (setDirty 'all')")
ctx.dirty_calls = {}
p4:clearOverlay(5, 3, 0)
expect(dirtyTargetsAll(), "clearOverlay dirties the window-level widget (setDirty 'all')")
ctx.dirty_calls = {}
p4:removeTile(5, 3, 0)
expect(dirtyTargetsAll(), "removeTile dirties the window-level widget (setDirty 'all')")
ctx.dirty_calls = {}
p4:updateBoard()
expect(dirtyTargetsAll(), "updateBoard dirties the window-level widget (setDirty 'all')")
ctx.dirty_calls = {}
p4:clearAllOverlays()
expect(dirtyTargetsAll(), "clearAllOverlays dirties the window-level widget (setDirty 'all')")

-- Disjoint tile changes must remain disjoint refresh regions. In particular,
-- the two tiles of a pair can be far apart; a single bounding box would flash
-- much of the board for a local mutation.
ctx.dirty_calls = {}
p4:requestRefresh({
    { x = 0, y = 0, layer = 0 },
    { x = 10, y = 7, layer = 0 },
})
expect(#ctx.dirty_calls == 2, "disjoint board changes enqueue separate refresh regions")
expect(ctx.dirty_calls[1].region.w == p4.tw + 2
        and ctx.dirty_calls[2].region.w == p4.tw + 2,
    "separate face refreshes include only a small edge margin")

ctx.dirty_calls = {}
p4:requestRefresh({
    { x = 5, y = 3, layer = 0 },
    { x = 4, y = 3, layer = 0 },
})
expect(#ctx.dirty_calls == 1,
    "touching local board changes share one refresh region")

-- The one-pixel raster margin must not escape the board at an outer edge.
-- Escaping into the feedback/status bands would make KOReader merge this local
-- repaint with adjacent chrome (it merges regions that share an edge).
local edge_parent = {}
local edge_board = Board:new{
    board = proj3, width = 600, height = 400, show_parent = edge_parent,
    refresh_origin_x = 10, refresh_origin_y = 20,
}
edge_parent.board_view = edge_board
ctx.dirty_calls = {}
local edge_x, edge_y, edge_layer = 5, 3, 0
local edge_key = next(edge_board.tile_widgets)
if edge_key then
    local x, y, layer = edge_key:match("^([^,]+),([^,]+),([^,]+)$")
    edge_x, edge_y, edge_layer = tonumber(x), tonumber(y), tonumber(layer)
end
edge_board.tilePos = function() return 0, 0 end
edge_board:requestRefresh({ { x = edge_x, y = edge_y, layer = edge_layer } })
local edge_region = ctx.dirty_calls[1] and ctx.dirty_calls[1].region
expect(edge_region and edge_region.x >= 10 and edge_region.y >= 20
        and edge_region.x + edge_region.w <= 610
        and edge_region.y + edge_region.h <= 420,
    "board refresh margins stay within the board canvas")

-- A live game retries structural pair regions after an intervening repaint;
-- standalone boards deliberately do not schedule that owner-level fallback.
local retry_parent = {}
local p5 = Board:new{
    board = proj3, width = 600, height = 400, show_parent = retry_parent,
}
retry_parent.board_view = p5
ctx.scheduled = {}
p5:removePair({ x = 5, y = 3, layer = 0 }, { x = 10, y = 7, layer = 0 })
expect(#ctx.scheduled == 1,
    "structural pair updates schedule one coalesced retry")
ctx.runScheduled()
ctx.runScheduled()
expect(#ctx.dirty_calls > 2,
    "the structural retry re-requests the affected regions")

if failures == 0 then
    print("\nALL BOARD UPDATE/OVERLAY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
