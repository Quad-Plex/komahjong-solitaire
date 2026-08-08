-- US-43 lower-chrome suite: the banner + action-bar strip must never be
-- refreshed in a way that leaves the toolbar's action buttons out of the
-- EPDC drive ("the whole lower part refreshed at once, but the action buttons
-- came up blank" — KOReader's open-range merge folded the edge-adjacent
-- banner/toolbar/board rects into one ioctl that a half-applying EPDC could
-- ink with the toolbar row omitted).
--
-- Checks:
--   * buildUILayout computes a single lower_band_region covering the banner
--     AND the toolbar row edge-to-edge (from the banner's top to the screen
--     bottom), so no chrome refresh can ever stop short of the buttons;
--   * updateStatus keeps the toolbar refresh tight (toolbar_region only) and
--     the HUD regional — it never asks for a regionless full-screen refresh;
--   * a hint counter-pill change (a genuine toolbar structural change) is the
--     only thing that schedules the deferred pure-refresh settle, and exactly
--     one at a time;
--   * the settle re-drives the WHOLE lower-chrome region with a
--     window-agnostic setDirty(nil, ...) — a refresh with no repaint, because
--     bakeLowerChrome already painted the current content into the framebuffer;
--   * repeated structural changes while a settle is pending do not stack
--     settle tasks.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
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

-- Does the recorded run include a "ui" refresh of THIS exact Geom object
-- (same reference) against the game window that window?
local function hasRegionDirty(mj, region)
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == mj and c.refreshtype == "ui" and c.region == region then
            return true
        end
    end
    return false
end

local function hasRegionlessDirty(mj)
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == mj and c.region == nil then return true end
    end
    return false
end

local function hasNilWidgetRefresh()
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == nil and c.refreshtype == "ui" then return true end
    end
    return false
end

local mj = Mahjong:new()
mj.board = Logic.newGame(12)
mj:buildUILayout()

-- ---- The single lower-band region covers banner AND toolbar ------------------

expect(mj.lower_band_region ~= nil, "buildUILayout computes lower_band_region")
expect(mj.lower_band_region.x == 0 and mj.lower_band_region.w == mj.full_width,
    "lower_band_region spans the full width, edge to edge")
expect(mj.lower_band_region.y == mj.flash_region.y,
    "lower_band_region starts at the banner's top edge")
expect(mj.lower_band_region.y + mj.lower_band_region.h
        >= mj.toolbar_region.y + mj.toolbar_region.h,
    "lower_band_region reaches at least the toolbar's bottom edge")
expect(mj:lowerChromeRegion() == mj.lower_band_region,
    "lowerChromeRegion() returns the merged lower region")
expect(mj:lowerChromeRegion().y + mj:lowerChromeRegion().h
        >= mj.toolbar_region.y + mj.toolbar_region.h,
    "lowerChromeRegion encloses the toolbar row (buttons can't be missed)")

-- ---- updateStatus keeps the toolbar + HUD refreshes tight and regional ------

ctx.dirty_calls = {}
mj:updateStatus()
expect(hasRegionDirty(mj, mj.toolbar_region),
    "updateStatus refreshes the toolbar's own tight region")
expect(hasRegionDirty(mj, mj.status_region),
    "updateStatus refreshes the HUD status region")
expect(not hasRegionlessDirty(mj),
    "updateStatus never issues a regionless (full-screen) refresh")

-- ---- bakeLowerChrome paints the banner + toolbar at their screen positions ----

local raw_bakes = {}
local um = require("ui/uimanager")
um.widgetRepaint = function(_, w, x, y)
    raw_bakes[#raw_bakes + 1] = { widget = w, x = x, y = y }
end
mj:bakeLowerChrome()
um.widgetRepaint = nil

local baked_band, baked_toolbar = false, false
for _, b in ipairs(raw_bakes) do
    if b.widget == mj.flash_band then
        expect(b.x == 0 and b.y == mj.flash_region.y,
            "bakeLowerChrome paints the banner at its screen position")
        baked_band = true
    elseif b.widget == mj.toolbar_widget then
        expect(b.x == 0 and b.y == mj.toolbar_region.y,
            "bakeLowerChrome paints the toolbar at its screen position")
        baked_toolbar = true
    end
end
expect(baked_band and baked_toolbar,
    "bakeLowerChrome paints both the banner and the toolbar sub-trees")

-- Restore the mock's no-widgetRepaint world: the bake is a safe no-op.
mj:bakeLowerChrome() -- must not throw

-- ---- ONLY a real pill change schedules a settle; a plain update never stacks ---

ctx.scheduled = {}
ctx.dirty_calls = {}
mj:updateStatus() -- same counters as before ("0" == "0")
expect(#ctx.scheduled == 0,
    "a plain HUD update schedules no settle")
expect(not hasNilWidgetRefresh(),
    "a plain HUD update never issues a window-agnostic pseudo-refresh")

-- Jog the count so an impending Hint press would show "1": structural.
mj.hints_used = 1
ctx.scheduled = {}
mj:updateStatus()
expect(#ctx.scheduled == 1,
    "a counter-pill change schedules exactly ONE settle")
mj.shuffles_used = 2 -- keep the pill changing while the settle is still pending
mj:updateStatus()
expect(#ctx.scheduled == 1,
    "settle coalesces: a pending settle absorbs further pill changes")

-- Run the settle to completion (mock's tickAfterNext is a two-tick wrapper).
local settled = false
-- The settle refresh is a window-agnostic pure refresh (widget==nil) over the
-- whole lower chrome, so the action-button row is always in the drive.
local settle_region
local function expectSettleApplied()
    for _, c in ipairs(ctx.dirty_calls) do
        if c.widget == nil and c.refreshtype == "ui" then
            settled = true
            settle_region = c.region
        end
    end
end
ctx.runScheduled()
ctx.dirty_calls = {}
ctx.runScheduled()
expectSettleApplied()
expect(settled,
    "the settle re-drives a pure refresh of the lower chrome")
expect(settle_region == mj.lower_band_region,
    "the settle targets the FULL lower-chrome region, toolbar included")
expect(mj._chrome_settle == false,
    "the settle clears its pending flag after applying")

if failures == 0 then
    print("\nALL US-43 LOWER-CHROME CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end