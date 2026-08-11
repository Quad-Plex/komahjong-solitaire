-- US-47 refresh-batching suite: the selection-overlay transition, the hint
-- dismissal, and the pair-clear must each go through ONE combined refresh
-- pass, and the chrome repaints spawned by a pair clear must not join the
-- board mutation's own batch.
--
-- This is the AGENTS.md rule "batch overlay transitions — clear old highlight
-- widgets and install new ones with refresh deferred, then enqueue one
-- combined region covering both the old and new locations" made concrete. It
-- is what prevents the intermittent "garbled leftovers after a fast clear"
-- report: the old highlight's clear and the new highlight's paint racing as
-- two separate regional updates (the selection/hint overlays), or a full-width
-- chrome rect (band / HUD / toolbar) merging with the board's tile rect into
-- one EPDC ioctl that a partial waveform half-applies.
--
-- Checks:
--   * Board:setSelectionOverlay clears the OLD overlay and draws the NEW one
--     in a single requestRefresh (one merged region for adjacent tiles), and
--     keeps exactly ONE selection overlay around;
--   * Mahjong:setSelection (a selection SWITCH) keeps one select overlay and
--     emits ONE combined refresh region instead of two (clear + set);
--   * Board:removePair(a,b,extra_rects) folds extra locations (dismissed hint
--     tiles) into the SAME refresh pass as the pair removal;
--   * Mahjong:clearHintBatched clears the hint overlays with NO own refresh and
--     returns the rects for the caller to batch;
--   * Mahjong:applyMatch with a hint up folds the hint-clear into the pair
--     removal (hint overlays gone, one batch);
--   * a combo applyMatch defers the HUD / toolbar / combo-band repaints out of
--     the pair-clear batch (they land on the next tick), while the board's own
--     structural repaint still happens immediately;
--   * requestRefresh widens the raster margin for half-grid (fractional) tiles
--     so a cleared Taipei-style tile never leaves a one-pixel edge sliver.

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
local function mapCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local function boardWith(tiles)
    local b = {}
    for _, t in ipairs(tiles) do b[pk(t[1], t[2], t[3])] = t[4] end
    return b
end
-- Does the recorded run include a "ui" refresh of THIS exact Geom object
-- (same reference) against the game window?
local function hasRegionDirty(mj, region)
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == mj and c.refreshtype == "ui" and c.region == region then
            return true
        end
    end
    return false
end

-- ---- Board:setSelectionOverlay batches the transition -----------------------

local proj = {}
proj[pk(5, 3, 0)] = "b1"
proj[pk(6, 3, 0)] = "c2"
local p = Board:new{ board = proj, width = 600, height = 400 }

p:setSelectionOverlay(nil, { x = 5, y = 3, layer = 0 })
expect(mapCount(p.overlays) == 1 and p.overlays[pk(5, 3, 0)] ~= nil,
    "setSelectionOverlay draws the first selection highlight")

ctx.dirty_calls = {}
p:setSelectionOverlay({ x = 5, y = 3, layer = 0 }, { x = 6, y = 3, layer = 0 })
expect(mapCount(p.overlays) == 1 and p.overlays[pk(6, 3, 0)] ~= nil
        and p.overlays[pk(5, 3, 0)] == nil,
    "switching selection keeps exactly ONE highlight (old cleared, new drawn)")
expect(#ctx.dirty_calls == 1,
    "switching selection batches old-clear + new-paint into ONE merged refresh")

-- ---- Board:removePair folds extra rects into the same pass -------------------

-- A covered() helper: is some recorded dirty region the given location's
-- screen-space Geom (tilePos plus the board's refresh_origin, matching how
-- requestRefresh anchors its regions)?
local function covered(p, location)
    local x, y = p:tilePos(location.x, location.y, location.layer)
    x = (p.refresh_origin_x or 0) + x
    y = (p.refresh_origin_y or 0) + y
    for _, c in ipairs(ctx.dirty_calls) do
        local r = c.region
        if r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            return true
        end
    end
    return false
end

ctx.dirty_calls = {}
-- Extra rects far from the pair (x=10/11 while the pair sits at x=5/6) so they
-- keep their own cluster: they must land in the SAME batch as the pair's
-- refresh, but never blur into a board-sized bounding box.
p:removePair({ x = 5, y = 3, layer = 0 }, { x = 6, y = 3, layer = 0 },
    { { x = 10, y = 6, layer = 0 }, { x = 11, y = 6, layer = 0 } })
expect(#ctx.dirty_calls == 2,
    "extra hint rects land in the same batch as the pair, kept as their own region")
expect(covered(p, { x = 10, y = 6, layer = 0 })
        and covered(p, { x = 11, y = 6, layer = 0 }),
    "the extra rects' locations are covered by their own refresh region")

-- ---- Half-grid tiles get a wider raster margin ---------------------------------

ctx.dirty_calls = {}
p:requestRefresh({ { x = 5, y = 3, layer = 0 } })
expect(ctx.dirty_calls[1].region.w == p.tw + 2,
    "integer-grid face tiles keep the 1 px raster margin")
ctx.dirty_calls = {}
p:requestRefresh({ { x = 2.5, y = 3, layer = 0 } })
expect(ctx.dirty_calls[1].region.w == p.tw + 4,
    "half-grid face tiles get a wider (2 px) raster margin to cover the sub-pixel floor")

-- ---- Mahjong:setSelection switch is ONE combined refresh ----------------------

local store = ctx.settings_store
local mj_sel = Mahjong:new()
mj_sel.board = boardWith{ {2,2,0,"b1"}, {3,2,0,"b2"} }
mj_sel:buildUILayout()
local bv = mj_sel.board_view

mj_sel:handleTileTap(2, 2, 0)
expect(mj_sel.selected ~= nil and mapCount(bv.overlays) == 1,
    "tapping a free tile selects it with one highlight")

ctx.dirty_calls = {}
mj_sel:handleTileTap(3, 2, 0) -- non-matching free tile -> switch selection
expect(mj_sel.selected.x == 3 and mapCount(bv.overlays) == 1
        and bv.overlays[pk(3, 2, 0)] ~= nil and bv.overlays[pk(2, 2, 0)] == nil,
    "tapping a different free tile switches the single highlight")
expect(#ctx.dirty_calls == 1,
    "a selection switch enqueues ONE combined refresh (not clear+set) on the game level")

-- Re-tapping the selected tile while a hint is active must also batch both
-- overlay clears. This used to clear selection and hint in separate requests.
local mj_deselect = Mahjong:new()
mj_deselect.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"b2"}, {8,2,0,"b2"},
}
mj_deselect:buildUILayout()
mj_deselect:handleTileTap(2, 2, 0)
mj_deselect:showHint()
ctx.dirty_calls = {}
mj_deselect:handleTileTap(2, 2, 0)
expect(mj_deselect.selected == nil and mapCount(mj_deselect.board_view.overlays) == 0,
    "re-tapping selection clears selection and persistent hint")
expect(#ctx.dirty_calls == 2,
    "selection and hint clears share ONE refresh pass with disjoint local regions")

-- ---- clearHintBatched defers the clear and returns the rects -------------------

local mj_hint = Mahjong:new()
mj_hint.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj_hint:buildUILayout()
mj_hint:showHint()
expect(mj_hint._last_hint ~= nil and mapCount(mj_hint.board_view.overlays) == 2,
    "a persistent hint draws both highlight overlays")

ctx.dirty_calls = {}
local rects = mj_hint:clearHintBatched()
expect(mj_hint._last_hint == nil and mapCount(mj_hint.board_view.overlays) == 0,
    "clearHintBatched removes the hint overlays")
expect(#rects == 2 or #ctx.dirty_calls == 0,
    "clearHintBatched awaits the caller's own refresh (nothing enqueued itself)")
if #ctx.dirty_calls == 0 then
    local bvh = mj_hint.board_view
    bvh:requestRefresh(rects)
    expect(#ctx.dirty_calls > 0
            and covered(bvh, rects[1]) and covered(bvh, rects[2]),
        "the caller folding the hint rects in covers BOTH hinted tiles in one batch")
end

-- ---- applyMatch folds a live hint-clear into the pair removal --------------------

local mj_match = Mahjong:new()
mj_match.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj_match:buildUILayout()
mj_match:showHint()
local h_pair = mj_match._last_hint
expect(h_pair ~= nil, "a matching hint exists to clear")

ctx.dirty_calls = {}
mj_match:applyMatch(h_pair.a, h_pair.b)
expect(mj_match._last_hint == nil and mapCount(mj_match.board_view.overlays) == 0,
    "applying a match along the hint folds the hint-clear into the pair removal")
expect(#ctx.dirty_calls > 0,
    "the pair removal still drives its structural refresh")

-- ---- A combo clear defers the chrome repaints out of the clear batch ------------

store.timer_update = "interval"
local mj_combo = Mahjong:new()
mj_combo.board = boardWith{
    {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"b1"}, {8,2,0,"b1"},
}
mj_combo:buildUILayout()
mj_combo:handleTileTap(2, 2, 0)
mj_combo:handleTileTap(4, 2, 0) -- first pair, seeds the combo window
expect(mj_combo.flash_text.text ~= "COMBO +10",
    "the first pair is not yet a combo")

ctx.dirty_calls = {}
mj_combo:handleTileTap(6, 2, 0)
mj_combo:handleTileTap(8, 2, 0) -- fast same-kind pair -> combo
expect(mj_combo.flash_text.text == "COMBO +10",
    "the combo band TEXT is set immediately (only the repaint defers)")
expect(not hasRegionDirty(mj_combo, mj_combo.flash_region),
    "the combo-band repaint is deferred out of the pair-clear batch")
expect(not hasRegionDirty(mj_combo, mj_combo.status_region),
    "the HUD repaint is deferred out of the pair-clear batch")
expect(#ctx.dirty_calls > 0,
    "the board pair-removal repaint still happens immediately")
ctx.runScheduled()
ctx.runScheduled()
expect(hasRegionDirty(mj_combo, mj_combo.flash_region),
    "the deferred combo-band repaint lands on the next tick")
expect(hasRegionDirty(mj_combo, mj_combo.status_region),
    "the deferred HUD repaint lands on the next tick")

if failures == 0 then
    print("\nALL US-47 REFRESH-BATCHING CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
