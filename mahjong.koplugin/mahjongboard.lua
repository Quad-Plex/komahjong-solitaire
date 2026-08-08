-- Mahjong Solitaire — board widget (outward-bevel 3D turtle).
--
-- Renders the 3D Turtle as a stack of flat tile faces with OUTWARD depth
-- bevels. Each layer is shifted up-left by exactly the bevel thickness (the
-- board's tilePos subtracts layer*bw/layer*bh), so a raised (higher-layer)
-- tile's face is inset from the tile directly beneath it and its outward
-- bevels land EXACTLY on that underlying tile's face edges — the bevel is the
-- visible step between layers and never overlaps the tiles to its east/south
-- (unlike the earlier model where bevels overhung the neighbours). The camera
-- sits at the bottom-right and the pyramid rises toward the top-left. Lower
-- layers are painted first so the raised tiles land on top of them.
--
-- The bevel bands live in the tile artwork (right #78909c, bottom #546e7a,
-- 10% of each axis, see tools/gen_icons.py); each icon widget is sized
-- (tw + bw) x (th + bh) so the rendered face is exactly the grid pitch.
--
-- Instead of a ButtonTable, the board paints IconWidgets absolutely
-- positioned via an OverlapGroup's `overlap_offset`, and hit-tests taps
-- itself (topmost tile at the tapped point wins). Tap results are forwarded
-- as (x, y, layer) so the game logic can identify the exact tile (US-07).

local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local IconWidget = require("ui/widget/iconwidget")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local MahjongLogic = require("mahjonglogic")

-- Tile height/width ratio: tiles are portrait (taller than wide).
local TILE_ASPECT = 1.4
-- Outward bevel thickness as a fraction of the tile size: the icons' bevel
-- bands are 10 viewBox units wide (right) / 14 tall (bottom) on a 110x154
-- canvas — i.e. 0.10 of a face width in both axes. Each icon widget is sized
-- (tw + bw) x (th + bh) with bw/bh = this fraction, so the rendered face is
-- exactly the grid pitch. The bevel is ALSO the per-layer offset: tilePos
-- shifts layer L up-left by L*bw / L*bh, so a raised tile's bevels land
-- exactly on the edges of the tile directly beneath it (the step between
-- layers is the bevel width).
local BEVEL_FRAC = 0.10
-- Empty board padding inside the widget.
local MARGIN = 6

-- Unit-space extents of a layout, including the 0.10-unit outward bevel
-- overhang on the east/south edges AND the up-left layer shift on the
-- west/north (layer L is shifted by L*BEVEL_FRAC, so the top layer reaches
-- maxLayer(id)*BEVEL_FRAC up and left of its grid position). These depend
-- only on the layout and the fixed bevel fraction (not on widget size or
-- board state), so they are computed once per layout id and reused by every
-- geometry pass. US-14 generalizes the old module-level LAYOUT_BOUNDS (which
-- was Turtle-only) to a per-id cache; the board picks its entry by layout_id.
local _layout_bounds_cache = {}
local function layoutBounds(id)
    if not _layout_bounds_cache[id] then
        local grid = MahjongLogic.gridBounds(id)
        local min_px, max_px = math.huge, -math.huge
        local min_py, max_py = math.huge, -math.huge
        for _, p in ipairs(MahjongLogic.buildLayout(id)) do
            local ux = (p.x - grid.x_min) - p.layer * BEVEL_FRAC
            local uy = (p.y - grid.y_min) - p.layer * BEVEL_FRAC
            min_px = math.min(min_px, ux)
            max_px = math.max(max_px, (p.x - grid.x_min) + 1 + BEVEL_FRAC) -- right edge + bevel
            min_py = math.min(min_py, uy)
            max_py = math.max(max_py, (p.y - grid.y_min) + 1 + BEVEL_FRAC) -- bottom edge + bevel
        end
        _layout_bounds_cache[id] = {
            min_px = min_px,
            min_py = min_py,
            width_units = max_px - min_px,
            height_units = max_py - min_py,
        }
    end
    return _layout_bounds_cache[id]
end

local Board = InputContainer:extend{
    name = "mahjongboard",
    board = nil,
    width = 0,
    height = 0,
    layout_id = "turtle",  -- US-14: which registered layout this board renders
    onTileTap = nil,   -- fired with (x, y, layer) when a tap hits a tile
    onEmptyTap = nil,  -- fired (no args) when a tap lands on empty board space
    grid = nil,
    tw = 0,          -- face width in px (also the grid pitch)
    th = 0,          -- face height in px
    bw = 0,          -- outward right-bevel thickness in px
    bh = 0,          -- outward bottom-bevel thickness in px
    tile_w = 0,      -- icon widget width = tw + bw (face + right bevel)
    tile_h = 0,      -- icon widget height = th + bh
    origin_x = 0,    -- widget-local position of grid cell (x_min, y_min)
    origin_y = 0,
    tiles_by_layer = nil, -- [layer] -> array of {x, y, layer, kind, px, py, w, h}
    tile_widgets = nil,   -- posKey -> IconWidget (for O(1) incremental removal)
    overlap = nil,        -- the painted OverlapGroup (self[1][1])
    overlays = nil,       -- posKey -> IconWidget overlay (select/hint), painted on top
    paused = false,        -- render empty faces while the pause modal is open
    empty_board = nil,     -- full-layout placeholder used for empty bevel variants
}

function Board:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.grid = MahjongLogic.gridBounds(self.layout_id)
    self.empty_board = {}
    for _, p in ipairs(MahjongLogic.buildLayout(self.layout_id)) do
        self.empty_board[MahjongLogic.posKey(p.x, p.y, p.layer)] = "empty"
    end
    self.ges_events.TapSelect = {
        GestureRange:new{
            ges = "tap",
            -- InputContainer:paintTo() keeps self.dimen in screen coords.
            range = function() return self.dimen end,
        },
    }
    self:computeGeometry()
    self:rebuildTiles()
end

-- Derives the face size and bevel thickness from the widget size so the whole
-- layout fits, then centers it. Uses the per-layout layoutBounds(self.layout_id)
-- (computed once per id), so no layout re-scan happens per geometry pass.
function Board:computeGeometry()
    local bounds = layoutBounds(self.layout_id)
    local width_units = bounds.width_units
    local height_units = bounds.height_units

    -- Very small/short canvases still get a positive fit area. This matters on
    -- phone split-screen and after rotation, where the surrounding chrome can
    -- temporarily leave less room than the normal Kindle layout.
    local margin = math.min(Screen:scaleBySize(MARGIN),
        math.max(0, math.floor(math.min(self.width, self.height) / 20)))
    local usable_w = math.max(1, self.width - 2 * margin)
    local usable_h = math.max(1, self.height - 2 * margin)

    -- Portrait faces (th = TILE_ASPECT * tw) sized to fit both axes.
    local tw_w = usable_w / width_units
    local tw_h = (usable_h / height_units) / TILE_ASPECT
    local tw = math.max(1, math.floor(math.min(tw_w, tw_h)))
    local th = math.max(1, math.floor(tw * TILE_ASPECT))

    self.tw = tw
    self.th = th
    -- Outward bevels, rounded so the icon widget dimen stays integral (the
    -- face then lands within half a pixel of the grid pitch — invisible).
    self.bw = math.floor(tw * BEVEL_FRAC + 0.5)
    self.bh = math.floor(th * BEVEL_FRAC + 0.5)
    self.tile_w = tw + self.bw
    self.tile_h = th + self.bh

    local bounds_w = width_units * tw
    local bounds_h = height_units * th
    self.origin_x = margin + math.floor((usable_w - bounds_w) / 2) - bounds.min_px * tw
    self.origin_y = margin + math.floor((usable_h - bounds_h) / 2) - bounds.min_py * th
end

-- Widget-local position of a tile's FACE top-left corner. Layer L is shifted
-- up-left by L*bw / L*bh (the bevel thickness), so a raised tile's face is
-- inset from the tile directly beneath it and its outward bevels land exactly
-- on that underlying tile's face edges — the visible step between layers.
function Board:tilePos(x, y, layer)
    local px = self.origin_x + (x - self.grid.x_min) * self.tw - layer * self.bw
    local py = self.origin_y + (y - self.grid.y_min) * self.th - layer * self.bh
    return math.floor(px), math.floor(py)
end

-- (Re)builds the visible tile widgets from the current board state. Called on
-- init and whenever the board changes structurally (new game, shuffle). After
-- a pair removal, prefer removeTile/removePair so only the removed tiles are
-- dropped instead of recreating all 144 IconWidgets.
function Board:rebuildTiles()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    self.overlap = nil
    self.tile_widgets = {}
    self.overlays = {}

    local by_layer = {}
    local max_layer = MahjongLogic.maxLayer(self.layout_id)
    for layer = 0, max_layer do
        by_layer[layer] = {}
    end
    local children = {}

    for _, p in ipairs(MahjongLogic.buildLayout(self.layout_id)) do
        local kind = self.paused and "empty"
            or MahjongLogic.tileAt(self.board, p.x, p.y, p.layer)
        if kind then
            local px, py = self:tilePos(p.x, p.y, p.layer)
            local icon_kind
            if self.paused then
                icon_kind = MahjongLogic.iconForTile(self.empty_board, p.x, p.y, p.layer)
            else
                icon_kind = MahjongLogic.iconForTile(self.board, p.x, p.y, p.layer)
            end
            local w = IconWidget:new{
                icon = "mahjong/" .. icon_kind,
                width = self.tile_w,
                height = self.tile_h,
                overlap_offset = { px, py },
                alpha = true,
            }
            self.tile_widgets[MahjongLogic.posKey(p.x, p.y, p.layer)] = w
            by_layer[p.layer][#by_layer[p.layer] + 1] = {
                x = p.x, y = p.y, layer = p.layer, kind = kind,
                px = px, py = py, w = self.tw, h = self.th,
            }
        end
    end

    -- Layout specs are grouped by shape, not paint order. On half-grid layouts
    -- a diagonal neighbor can overlap the other tile's face/bevel, so paint
    -- every layer along the board's diagonal depth (x+y). This makes an
    -- upper-right half-overlap paint after the lower-left tile it covers.
    for layer = 0, max_layer do
        table.sort(by_layer[layer], function(a, b)
            local da, db = a.x + a.y, b.x + b.y
            if da ~= db then return da < db end
            if a.y ~= b.y then return a.y < b.y end
            return a.x < b.x
        end)
    end
    for layer = 0, max_layer do
        for _, t in ipairs(by_layer[layer]) do
            children[#children + 1] = self.tile_widgets[MahjongLogic.posKey(t.x, t.y, t.layer)]
        end
    end

    self.tiles_by_layer = by_layer
    local overlap_opts = {
        -- Board-sized OverlapGroup: tiles are offset relative to its top-left.
        dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height },
    }
    for i, child in ipairs(children) do
        overlap_opts[i] = child
    end
    local overlap = OverlapGroup:new(overlap_opts)
    self.overlap = overlap

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        overlap,
    }
end

-- Refreshes the board from the current game state (US-07+ hooks here).
function Board:updateBoard()
    self:rebuildTiles()
    self:requestRefresh()
end

-- Swap the rendered faces without touching the logic board. The pause modal
-- blocks input, while this keeps the exact live geometry and z-order visible
-- as an empty board silhouette.
function Board:setPaused(paused)
    paused = paused == true
    if self.paused == paused then return end
    self.paused = paused
    self:rebuildTiles()
    self:requestRefresh()
end

-- Incremental removal -------------------------------------------------------
--
-- After a matched pair is removed the logic board changes by exactly two
-- tiles, so rebuilding all 144 IconWidgets (updateBoard) would be wasteful.
-- US-07 removes from the logic board first, then calls removePair here so only
-- the two affected widgets are freed and the hit-test table is updated.

-- Drops a single rendered tile (widget, hit-test entry, and any overlay
-- sitting on it) WITHOUT refreshing neighbours or syncing the overlap group —
-- removeTile / removePair batch those so a pair's widgets are dropped before
-- any neighbour icon is recomputed. The logic board must already be updated
-- by the caller. Returns true if the tile was present.
function Board:dropTileWidget(x, y, layer)
    local key = MahjongLogic.posKey(x, y, layer)
    local w = self.tile_widgets[key]
    if not w then return false end

    -- drop the tile widget from the paint stack
    self.tile_widgets[key] = nil
    for i = #(self.overlap or {}), 1, -1 do
        if self.overlap[i] == w then
            table.remove(self.overlap, i)
            break
        end
    end
    w:free()

    -- drop the tile from the hit-test table
    local by = self.tiles_by_layer[layer]
    if by then
        for i = #by, 1, -1 do
            if by[i].x == x and by[i].y == y then
                table.remove(by, i)
                break
            end
        end
    end

    -- drop any overlay that was sitting on this tile
    local ov = self.overlays[key]
    if ov then
        self.overlays[key] = nil
        for i = #(self.overlap or {}), 1, -1 do
            if self.overlap[i] == ov then
                table.remove(self.overlap, i)
                break
            end
        end
        ov:free()
    end
    return true
end

-- Recomputes the icons of a tile's same-layer west/north neighbours: the only
-- tiles whose bevels can change when this tile is removed (its removal exposes
-- their right/bottom bevels) or added (it hides them). The tile itself may
-- already be gone — refreshTileIcon skips tiles without a widget.
function Board:refreshWestNorthNeighbours(x, y, layer)
    for dy = -0.5, 0.5, 0.5 do
        self:refreshTileIcon(x - 1, y + dy, layer)
    end
    for dx = -0.5, 0.5, 0.5 do
        self:refreshTileIcon(x + dx, y - 1, layer)
    end
end

local function refreshRectsForTile(x, y, layer)
    local rects = { { x = x, y = y, layer = layer } }
    for dy = -0.5, 0.5, 0.5 do
        rects[#rects + 1] = { x = x - 1, y = y + dy, layer = layer }
    end
    for dx = -0.5, 0.5, 0.5 do
        rects[#rects + 1] = { x = x + dx, y = y - 1, layer = layer }
    end
    return rects
end

-- Removes a single rendered tile. Returns true if it was present. Any overlay
-- sitting on the tile is dropped too. Repaints the board.
function Board:removeTile(x, y, layer)
    if not self:dropTileWidget(x, y, layer) then return false end
    self:refreshWestNorthNeighbours(x, y, layer)
    self:syncOverlapGroup(refreshRectsForTile(x, y, layer))
    return true
end

-- Re-resolves the icon for the tile at (x, y, layer) and replaces its widget
-- if the icon (i.e. its bevel variants) has changed. Used after a neighbor
-- is removed or added. A widget whose tile is no longer on the board (e.g. a
-- half-removed pair) is skipped: removeTile/removePair batch the drops, so
-- the widget has already been freed.
function Board:refreshTileIcon(x, y, layer)
    local key = MahjongLogic.posKey(x, y, layer)
    local w = self.tile_widgets[key]
    if not w then return end

    local icon_board = self.paused and self.empty_board or self.board
    local icon = MahjongLogic.iconForTile(icon_board, x, y, layer)
    if not icon then return end
    local new_icon = "mahjong/" .. icon
    if w.icon == new_icon then return end

    local px, py = self:tilePos(x, y, layer)
    local new_w = IconWidget:new{
        icon = new_icon,
        width = self.tile_w,
        height = self.tile_h,
        overlap_offset = { px, py },
        alpha = true,
    }

    -- Swap in the map
    self.tile_widgets[key] = new_w
    w:free()
end

-- Synchronizes the OverlapGroup children with tiles_by_layer and overlays,
-- maintaining correct z-order (layers 0-4 then overlays). Repaints.
-- Board is nested inside the full-screen game window. Target that window when
-- available so unrelated windows are not repainted; retain the "all" fallback
-- for standalone boards and the headless tests. The region keeps the e-ink
-- refresh limited to the tiles affected by this mutation.
function Board:requestRefresh(rects)
    local target = self.show_parent or "all"
    if rects and #rects > 0 then
        -- Keep each connected local change together, but do not collapse a
        -- distant matched pair into one board-sized bounding box. Explicitly
        -- merging here is more reliable than relying on the refresh queue to
        -- combine many overlapping tile requests in the same e-ink frame.
        -- Include a pixel of surrounding space for SVG bevel/raster edges.
        local margin = 1
        local regions = {}
        for _, r in ipairs(rects) do
            local x, y = self:tilePos(r.x, r.y, r.layer)
            local region = {
                x = (self.refresh_origin_x or 0) + x - margin,
                y = (self.refresh_origin_y or 0) + y - margin,
                w = self.tile_w + 2 * margin,
                h = self.tile_h + 2 * margin,
            }
            local merged = true
            while merged do
                merged = false
                for i = #regions, 1, -1 do
                    local other = regions[i]
                    if region.x <= other.x + other.w
                            and other.x <= region.x + region.w
                            and region.y <= other.y + other.h
                            and other.y <= region.y + region.h then
                        local right = math.max(region.x + region.w, other.x + other.w)
                        local bottom = math.max(region.y + region.h, other.y + other.h)
                        region.x = math.min(region.x, other.x)
                        region.y = math.min(region.y, other.y)
                        region.w = right - region.x
                        region.h = bottom - region.y
                        table.remove(regions, i)
                        merged = true
                    end
                end
            end
            regions[#regions + 1] = region
        end
        for _, region in ipairs(regions) do
            UIManager:setDirty(target, "ui", Geom:new(region))
        end
        return
    end

    UIManager:setDirty(target, "ui", Geom:new{
        x = self.refresh_origin_x or 0,
        y = self.refresh_origin_y or 0,
        w = self.width,
        h = self.height,
    })
end

function Board:syncOverlapGroup(refresh_rects)
    if not self.overlap then return end
    -- Clear current children array (do NOT free them, they are in maps)
    for i = #self.overlap, 1, -1 do
        self.overlap[i] = nil
    end
    -- Add tiles in layer order and diagonal depth order.
    local max_layer = MahjongLogic.maxLayer(self.layout_id)
    for layer = 0, max_layer do
        local tiles = {}
        for _, t in ipairs(self.tiles_by_layer[layer]) do
            tiles[#tiles + 1] = t
        end
        table.sort(tiles, function(a, b)
            local da, db = a.x + a.y, b.x + b.y
            if da ~= db then return da < db end
            if a.y ~= b.y then return a.y < b.y end
            return a.x < b.x
        end)
        for _, t in ipairs(tiles) do
            local w = self.tile_widgets[MahjongLogic.posKey(t.x, t.y, t.layer)]
            if w then
                self.overlap[#self.overlap + 1] = w
            end
        end
    end
    -- Add overlays
    for _, ov in pairs(self.overlays) do
        self.overlap[#self.overlap + 1] = ov
    end
    self:requestRefresh(refresh_rects)
end

-- Incremental addition ------------------------------------------------------

-- Restores a single tile to the rendered board. Returns true if it was
-- missing. Repaints the board.
function Board:addTile(x, y, layer, kind, defer_sync)
    local key = MahjongLogic.posKey(x, y, layer)
    if self.tile_widgets[key] then return false end

    local px, py = self:tilePos(x, y, layer)
    local icon_name = MahjongLogic.iconForTile(self.board, x, y, layer)
    local w = IconWidget:new{
        icon = "mahjong/" .. icon_name,
        width = self.tile_w,
        height = self.tile_h,
        overlap_offset = { px, py },
        alpha = true,
    }

    self.tile_widgets[key] = w
    table.insert(self.tiles_by_layer[layer], {
        x = x, y = y, layer = layer, kind = kind,
        px = px, py = py, w = self.tw, h = self.th,
    })

    -- Update same-layer neighbors whose bevels might now be occluded.
    self:refreshWestNorthNeighbours(x, y, layer)

    if not defer_sync then
        self:syncOverlapGroup(refreshRectsForTile(x, y, layer))
    end
    return true
end

-- Restores a pair of tiles (a and b are { x, y, layer, kind } tables).
-- Returns true if both tiles were added.
function Board:addPair(a, b)
    local ra = self:addTile(a.x, a.y, a.layer, a.kind, true)
    local rb = self:addTile(b.x, b.y, b.layer, b.kind, true)
    if ra then self:refreshWestNorthNeighbours(a.x, a.y, a.layer) end
    if rb then self:refreshWestNorthNeighbours(b.x, b.y, b.layer) end
    local rects = refreshRectsForTile(a.x, a.y, a.layer)
    for _, r in ipairs(refreshRectsForTile(b.x, b.y, b.layer)) do
        rects[#rects + 1] = r
    end
    self:syncOverlapGroup(rects)
    return ra and rb
end

-- Removes a matched pair (a and b are { x, y, layer } tables) with a single
-- call, keeping z-order. Returns true if both tiles were present. The logic
-- board is expected to have been updated by the caller before this.
--
-- Both widgets are dropped BEFORE any neighbour icon is refreshed: by the time
-- this runs the logic board no longer has the pair, so if the two tiles are
-- adjacent (one west/north of the other) the first removal's neighbour refresh
-- would find the second tile's still-present widget with a nil kind and crash
-- on "mahjong/" .. nil. Batching the drops keeps every refreshTileIcon call on
-- a tile that is genuinely on the board.
function Board:removePair(a, b)
    local ra = self:dropTileWidget(a.x, a.y, a.layer)
    local rb = self:dropTileWidget(b.x, b.y, b.layer)
    if ra then self:refreshWestNorthNeighbours(a.x, a.y, a.layer) end
    if rb then self:refreshWestNorthNeighbours(b.x, b.y, b.layer) end
    local rects = refreshRectsForTile(a.x, a.y, a.layer)
    for _, r in ipairs(refreshRectsForTile(b.x, b.y, b.layer)) do
        rects[#rects + 1] = r
    end
    self:syncOverlapGroup(rects)
    return ra and rb
end

-- Overlays ----------------------------------------------------------------
--
-- Selection/hint highlights (US-07/US-08) are IconWidgets appended AFTER all
-- tile widgets in the same OverlapGroup, so they always paint on top of every
-- tile. They are never added to tiles_by_layer, so the board's own hit-testing
-- (which walks tiles_by_layer) ignores them and taps pass through to tiles.

-- Draws `icon` ("select" or "hint" from the mahjong/ icon set) over the tile
-- at (x, y, layer), replacing any existing overlay on that tile. Returns true
-- if the tile exists. Repaints the board.
function Board:setOverlay(x, y, layer, icon, defer_refresh)
    local key = MahjongLogic.posKey(x, y, layer)
    if not self.tile_widgets[key] then return false end
    self:clearOverlay(x, y, layer, true)
    local px, py = self:tilePos(x, y, layer)
    local ov = IconWidget:new{
        icon = "mahjong/" .. icon,
        width = self.tw,
        height = self.th,
        overlap_offset = { px, py },
        alpha = true,
    }
    self.overlays[key] = ov
    self.overlap[#self.overlap + 1] = ov
    if not defer_refresh then
        self:requestRefresh({ { x = x, y = y, layer = layer } })
    end
    return true
end

-- Removes the overlay on the tile at (x, y, layer), if any. Returns true if
-- one existed. Repaints the board.
function Board:clearOverlay(x, y, layer, defer_refresh)
    local key = MahjongLogic.posKey(x, y, layer)
    local ov = self.overlays[key]
    if not ov then return false end
    self.overlays[key] = nil
    for i = #(self.overlap or {}), 1, -1 do
        if self.overlap[i] == ov then
            table.remove(self.overlap, i)
            break
        end
    end
    ov:free()
    if not defer_refresh then
        self:requestRefresh({ { x = x, y = y, layer = layer } })
    end
    return true
end

-- Removes every overlay (new game, shuffle, full rebuild). Repaints.
function Board:clearAllOverlays()
    local rects = {}
    for key, ov in pairs(self.overlays or {}) do
        local x, y, layer = key:match("^([^,]+),([^,]+),([^,]+)$")
        rects[#rects + 1] = { x = tonumber(x), y = tonumber(y), layer = tonumber(layer) }
        for i = #(self.overlap or {}), 1, -1 do
            if self.overlap[i] == ov then
                table.remove(self.overlap, i)
                break
            end
        end
        ov:free()
        self.overlays[key] = nil
    end
    self:requestRefresh(#rects > 0 and rects or nil)
end

-- Topmost tile whose rect contains the widget-local point, or nil.
function Board:hitTest(lx, ly)
    local max_layer = MahjongLogic.maxLayer(self.layout_id)
    for layer = max_layer, 0, -1 do
        local tiles = {}
        for _, t in ipairs(self.tiles_by_layer[layer] or {}) do
            tiles[#tiles + 1] = t
        end
        table.sort(tiles, function(a, b)
            local da, db = a.x + a.y, b.x + b.y
            if da ~= db then return da < db end
            if a.y ~= b.y then return a.y < b.y end
            return a.x < b.x
        end)
        for i = #tiles, 1, -1 do
            local t = tiles[i]
            if lx >= t.px and lx < t.px + t.w
                and ly >= t.py and ly < t.py + t.h then
                return t
            end
        end
    end
    return nil
end

-- KOReader dispatches gesture handlers as onTapSelect(gsseq.args, ges_event);
-- the gesture is the SECOND argument.
function Board:onTapSelect(_, ges)
    if not self.dimen then return false end
    local hit = self:hitTest(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y)
    if hit then
        if self.onTileTap then self.onTileTap(hit.x, hit.y, hit.layer) end
        return true
    end
    -- A tap on empty board space (beside the stack) is the player's "deselect"
    -- gesture: forward it so the game can clear any selection. Return nil only
    -- when there is no handler, so an unhandled board still yields to the
    -- event dispatch above (legacy behavior).
    if self.onEmptyTap then
        self.onEmptyTap()
        return true
    end
    return false
end

function Board:getSize()
    return self.dimen or Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

return Board
