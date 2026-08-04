-- Mahjong Solitaire — board widget (offset-layer 3D turtle).
--
-- Renders the 3D Turtle as a stack of flat tile faces: every tile in the
-- layout is drawn at its real (x, y, layer) position, with each higher layer
-- offset up-and-right by half a tile from the one below (classic mahjong
-- interlock). Lower layers are painted first so the stepped pyramid
-- silhouette and the exposed edges of lower tiles are visible.
--
-- Instead of a ButtonTable, the board paints IconWidgets absolutely
-- positioned via an OverlapGroup's `overlap_offset`, and hit-tests taps
-- itself (topmost tile at the tapped point wins). Tap results are forwarded
-- as (x, y, layer) so the game logic can identify the exact tile (US-07).
--
-- Replaces the US-06 flat-projection grid.

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
-- Per-layer screen offset, as a fraction of the tile size. Half a tile gives
-- the classic interlock (each upper tile covers the corner of 4 below it).
local LAYER_OFF_X = 0.5
local LAYER_OFF_Y = 0.5
-- Empty board padding inside the widget.
local MARGIN = 6

-- Unit-space extents of the Turtle layout. These depend only on the static
-- layout and the fixed layer offsets (not on widget size or board state), so
-- they are computed once at load and reused by every geometry pass.
local GRID = MahjongLogic.gridBounds()
local LAYOUT_BOUNDS
do
    local min_px, max_px = math.huge, -math.huge
    local min_py, max_py = math.huge, -math.huge
    for _, p in ipairs(MahjongLogic.buildLayout()) do
        local ux = (p.x - GRID.x_min) + LAYER_OFF_X * p.layer
        local uy = (p.y - GRID.y_min) - LAYER_OFF_Y * p.layer
        min_px = math.min(min_px, ux)
        max_px = math.max(max_px, ux + 1) -- right edge (in tile-width units)
        min_py = math.min(min_py, uy)
        max_py = math.max(max_py, uy + 1) -- bottom edge (in tile-height units)
    end
    LAYOUT_BOUNDS = {
        min_px = min_px,
        min_py = min_py,
        width_units = max_px - min_px,
        height_units = max_py - min_py,
    }
end

local Board = InputContainer:extend{
    name = "mahjongboard",
    board = nil,
    width = 0,
    height = 0,
    onTileTap = nil,
    grid = nil,
    tw = 0,          -- tile width in px
    th = 0,          -- tile height in px
    origin_x = 0,    -- widget-local position of grid cell (x_min, y_min)
    origin_y = 0,
    offx = 0,        -- layer offset in px
    offy = 0,
    tiles_by_layer = nil, -- [layer] -> array of {x, y, layer, kind, px, py, w, h}
    tile_widgets = nil,   -- posKey -> IconWidget (for O(1) incremental removal)
    overlap = nil,        -- the painted OverlapGroup (self[1][1])
    overlays = nil,       -- posKey -> IconWidget overlay (select/hint), painted on top
}

function Board:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.grid = GRID
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

-- Derives tile size and layer offsets from the widget size so the whole
-- turtle fits, then centers it. Uses the module-level LAYOUT_BOUNDS (the
-- layout is static), so no layout re-scan happens per geometry pass.
function Board:computeGeometry()
    local width_units = LAYOUT_BOUNDS.width_units
    local height_units = LAYOUT_BOUNDS.height_units

    local margin = Screen:scaleBySize(MARGIN)
    local usable_w = self.width - 2 * margin
    local usable_h = self.height - 2 * margin

    -- Portrait tiles (th = TILE_ASPECT * tw) sized to fit both axes.
    local tw_w = usable_w / width_units
    local tw_h = (usable_h / height_units) / TILE_ASPECT
    local tw = math.max(1, math.floor(math.min(tw_w, tw_h)))
    local th = math.max(1, math.floor(tw * TILE_ASPECT))

    self.tw = tw
    self.th = th
    self.offx = math.floor(tw * LAYER_OFF_X)
    self.offy = math.floor(th * LAYER_OFF_Y)

    local bounds_w = width_units * tw
    local bounds_h = height_units * th
    self.origin_x = margin + math.floor((usable_w - bounds_w) / 2) - LAYOUT_BOUNDS.min_px * tw
    self.origin_y = margin + math.floor((usable_h - bounds_h) / 2) - LAYOUT_BOUNDS.min_py * th
end

-- Widget-local position of a tile's top-left corner.
function Board:tilePos(x, y, layer)
    local px = self.origin_x + (x - self.grid.x_min) * self.tw + layer * self.offx
    local py = self.origin_y + (y - self.grid.y_min) * self.th - layer * self.offy
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
    for layer = 0, MahjongLogic.MAX_LAYER do
        by_layer[layer] = {}
    end
    local children = {}

    for _, p in ipairs(MahjongLogic.buildLayout()) do
        local kind = MahjongLogic.tileAt(self.board, p.x, p.y, p.layer)
        if kind then
            local px, py = self:tilePos(p.x, p.y, p.layer)
            local w = IconWidget:new{
                icon = "mahjong/" .. MahjongLogic.iconForKind(kind),
                width = self.tw,
                height = self.th,
                overlap_offset = { px, py },
            }
            children[#children + 1] = w
            self.tile_widgets[MahjongLogic.posKey(p.x, p.y, p.layer)] = w
            by_layer[p.layer][#by_layer[p.layer] + 1] = {
                x = p.x, y = p.y, layer = p.layer, kind = kind,
                px = px, py = py, w = self.tw, h = self.th,
            }
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
    UIManager:setDirty(self, "ui")
end

-- Incremental removal -------------------------------------------------------
--
-- After a matched pair is removed the logic board changes by exactly two
-- tiles, so rebuilding all 144 IconWidgets (updateBoard) would be wasteful.
-- US-07 removes from the logic board first, then calls removePair here so only
-- the two affected widgets are freed and the hit-test table is updated.

-- Removes a single rendered tile. Returns true if it was present. Any overlay
-- sitting on the tile is dropped too. Repaints the board.
function Board:removeTile(x, y, layer)
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

    -- drop any overlay that was sitting on this tile (no repaint here;
    -- the one from removeTile below covers it)
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

    UIManager:setDirty(self, "ui")
    return true
end

-- Removes a matched pair (a and b are { x, y, layer } tables) with a single
-- call, keeping z-order. Returns true if both tiles were present. The logic
-- board is expected to have been updated by the caller before this.
function Board:removePair(a, b)
    local ra = self:removeTile(a.x, a.y, a.layer)
    local rb = self:removeTile(b.x, b.y, b.layer)
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
function Board:setOverlay(x, y, layer, icon)
    local key = MahjongLogic.posKey(x, y, layer)
    if not self.tile_widgets[key] then return false end
    self:clearOverlay(x, y, layer)
    local px, py = self:tilePos(x, y, layer)
    local ov = IconWidget:new{
        icon = "mahjong/" .. icon,
        width = self.tw,
        height = self.th,
        overlap_offset = { px, py },
    }
    self.overlays[key] = ov
    self.overlap[#self.overlap + 1] = ov
    UIManager:setDirty(self, "ui")
    return true
end

-- Removes the overlay on the tile at (x, y, layer), if any. Returns true if
-- one existed. Repaints the board.
function Board:clearOverlay(x, y, layer)
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
    UIManager:setDirty(self, "ui")
    return true
end

-- Removes every overlay (new game, shuffle, full rebuild). Repaints.
function Board:clearAllOverlays()
    for key, ov in pairs(self.overlays or {}) do
        for i = #(self.overlap or {}), 1, -1 do
            if self.overlap[i] == ov then
                table.remove(self.overlap, i)
                break
            end
        end
        ov:free()
        self.overlays[key] = nil
    end
    UIManager:setDirty(self, "ui")
end

-- Topmost tile whose rect contains the widget-local point, or nil.
function Board:hitTest(lx, ly)
    for layer = MahjongLogic.MAX_LAYER, 0, -1 do
        for _, t in ipairs(self.tiles_by_layer[layer] or {}) do
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
    return false
end

function Board:getSize()
    return self.dimen or Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

return Board
