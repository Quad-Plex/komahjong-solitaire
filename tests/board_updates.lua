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
expect(#p.overlap == 4, "OverlapGroup holds the 4 tile widgets")

local removed = p:removeTile(5, 3, 2)
expect(removed == true, "removeTile returns true for a present tile")
expect(tilesOf(p) == 3 and #p.overlap == 3, "removeTile drops the widget from paint stack and map")
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
expect(ok == true and tilesOf(p2) == 1 and #p2.overlap == 1,
    "removePair removes both tiles and leaves the third")
local rpx, rpy = p2:tilePos(2, 2, 0)
expect(p2:hitTest(rpx + 1, rpy + 1).kind == "west", "remaining tile still hit-tests")

-- ---- Overlays ---------------------------------------------------------------

local p3 = Board:new{ board = proj2, width = 600, height = 400 }
local ox, oy = p3:tilePos(5, 3, 0)

expect(p3:setOverlay(5, 3, 0, "select") == true, "setOverlay succeeds on a present tile")
expect(mapCount(p3.overlays) == 1 and #p3.overlap == 4, "overlay registered on top of the tiles")
expect(p3:hitTest(ox + 2, oy + 2).kind == "b1", "overlay does not shadow hit-testing")

expect(p3:setOverlay(1, 1, 0, "select") == false, "setOverlay fails on a missing tile")

p3:setOverlay(5, 3, 0, "hint")
expect(mapCount(p3.overlays) == 1 and #p3.overlap == 4, "setOverlay replaces an existing overlay")

expect(p3:clearOverlay(5, 3, 0) == true, "clearOverlay returns true when an overlay existed")
expect(mapCount(p3.overlays) == 0 and #p3.overlap == 3, "clearOverlay removes the overlay widget")
expect(p3:clearOverlay(5, 3, 0) == false, "clearOverlay returns false when none existed")

p3:setOverlay(5, 3, 0, "select")
p3:setOverlay(9, 6, 0, "select")
p3:clearAllOverlays()
expect(mapCount(p3.overlays) == 0 and #p3.overlap == 3, "clearAllOverlays removes every overlay")

-- removing a tile drops an overlay that was sitting on it
p3:setOverlay(5, 3, 0, "select")
p3:removeTile(5, 3, 0)
expect(mapCount(p3.overlays) == 0 and #p3.overlap == 2, "removeTile drops the tile's overlay too")

-- ---- updateBoard (full rebuild) resets maps and overlays ---------------------

local proj3 = {}
for k, v in pairs(proj2) do proj3[k] = v end
proj3[pk(3, 2, 0)] = "red"
p3.board = proj3
p3:updateBoard()
expect(tilesOf(p3) == 4 and #p3.overlap == 4 and mapCount(p3.overlays) == 0,
    "updateBoard rebuilds tiles and clears stale overlays")

if failures == 0 then
    print("\nALL BOARD UPDATE/OVERLAY CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
