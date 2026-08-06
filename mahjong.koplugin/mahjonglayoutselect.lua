-- Layout selection screen (US-14) — full-screen picker.
--
-- A full-screen opaque widget (not a floating card): choosing a layout is a
-- fresh start, so the previous board does not need to show through. A 3-column
-- grid of cards (one per registered layout, dynamically many rows — minimum 3)
-- wrapped in a scroll container so 4+ rows scroll on small screens instead of
-- clipping (US-21). Each card carries a small thumbnail (a miniature schematic
-- of the layout's positions — small rounded rects per tile, per-layer up-left
-- offset so the 3D shape reads) plus the layout name underneath. Tapping a card
-- deals a game on that layout.
--
-- Interaction model (mirrors the board's hit-test): one full-screen tap
-- gesture; the handler hit-tests the tap against each card's rect and fires
-- `onPick(layout_id)` for the hit, or `onClose()` for a tap outside any card
-- (and the close X in the top-right corner). The owner (main.lua) pauses the
-- timer while the picker is up and resumes it on close (exactly like the
-- settings/stats dialogs).
--
-- `layoutThumbnail(id, w, h)` is exported as a module function so US-15/16
-- get their thumbnail for free (it builds the schematic from the layout
-- positions).

local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local SVContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local ButtonWidget = require("ui/widget/button")
local _ = require("gettext")
local MahjongLogic = require("mahjonglogic")

-- Tile face aspect (portrait) and bevel fraction — must match the board
-- (mahjongboard.lua) so the thumbnail's 3D offset reads the same as the real
-- board.
local TILE_ASPECT = 1.4
local BEVEL_FRAC = 0.10

local LayoutSelect = InputContainer:extend{
    name = "mahjonglayoutselect",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,      -- the Mahjong instance
    onPick = nil,      -- function(layout_id) — deals a fresh game on the layout
    onClose = nil,     -- function() — close X / tap outside (owner resumes timer)
    _card_rects = nil, -- { { id=, x=, y=, w=, h= } } in widget-local coords
}

-- Builds a miniature schematic of a layout's positions, scaled to fit a w x h
-- box. Each position is a small rounded rect (light gray, dark border) offset
-- per-layer up-left by the bevel fraction so the 3D pyramid reads (the same
-- projection the real board uses). The thumbnail is an OverlapGroup of these
-- tiles with a fixed dimen, so the owner can place it inside a card.
local function layoutThumbnail(id, w, h)
    local grid = MahjongLogic.gridBounds(id)
    local min_px, max_px = math.huge, -math.huge
    local min_py, max_py = math.huge, -math.huge
    for _, p in ipairs(MahjongLogic.buildLayout(id)) do
        local ux = (p.x - grid.x_min) - p.layer * BEVEL_FRAC
        local uy = (p.y - grid.y_min) - p.layer * BEVEL_FRAC
        min_px = math.min(min_px, ux)
        max_px = math.max(max_px, (p.x - grid.x_min) + 1 + BEVEL_FRAC)
        min_py = math.min(min_py, uy)
        max_py = math.max(max_py, (p.y - grid.y_min) + 1 + BEVEL_FRAC)
    end
    local w_units = max_px - min_px
    local h_units = max_py - min_py
    -- Portrait faces (th = TILE_ASPECT * tw) sized to fit both axes.
    local scale = math.min(w / w_units, (h / h_units) / TILE_ASPECT)
    local tw = math.max(2, math.floor(scale))
    local th = math.max(2, math.floor(tw * TILE_ASPECT))
    local bw = tw * BEVEL_FRAC
    local bh = th * BEVEL_FRAC
    local origin_x = math.floor((w - w_units * tw) / 2) - min_px * tw
    local origin_y = math.floor((h - h_units * th) / 2) - min_py * th

    local opts = {
        dimen = Geometry:new{ w = w, h = h },
    }
    for _, p in ipairs(MahjongLogic.buildLayout(id)) do
        local px = math.floor(origin_x + (p.x - grid.x_min) * tw - p.layer * bw)
        local py = math.floor(origin_y + (p.y - grid.y_min) * th - p.layer * bh)
        local tile = FrameContainer:new{
            width = tw,
            height = th,
            bordersize = 1,
            radius = math.max(1, math.floor(tw * 0.15)),
            padding = 0,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            color = Blitbuffer.COLOR_DARK_GRAY,
            _padding_left = 0,
            _padding_right = 0,
            _padding_top = 0,
            _padding_bottom = 0,
        }
        -- OverlapGroup children must be real widgets with a getSize (the real
        -- OverlapGroup:getSize iterates them). Override getSize (and keep the
        -- _padding_* fields set — see AGENTS.md FrameContainer pitfall).
        tile.getSize = function() return Geometry:new{ w = tw, h = th } end
        -- overlap_offset must live ON the child widget and be an ARRAY.
        tile.overlap_offset = { px, py }
        opts[#opts + 1] = tile
    end
    return OverlapGroup:new(opts)
end
LayoutSelect.layoutThumbnail = layoutThumbnail

function LayoutSelect:init()
    self.dimen = Geometry:new{ x = 0, y = 0, w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true
    self._card_rects = {}

    local edge_pad = Screen:scaleBySize(16)
    local gap = Screen:scaleBySize(12)

    -- Title row: "Choose a layout" centered, with a close X pinned top-right
    -- (the same grey-square style as the other dialogs). Tapping the X
    -- cancels (closes the picker without dealing).
    local title_widget = TextWidget:new{
        text = _("Choose a layout"),
        padding = 0,
        face = Font:getFace("tfont", Screen:scaleBySize(22)),
    }
    local title_h = title_widget:getSize().h
    local close_size = title_h + Screen:scaleBySize(8)
    self._close_btn = ButtonWidget:new{
        icon = "mahjong/close",
        width = close_size,
        height = close_size,
        icon_width = math.floor(close_size * 0.6),
        icon_height = math.floor(close_size * 0.6),
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        callback = function() self:closeDialog() end,
    }
    local title_w = title_widget:getSize().w
    local title_row_w = self.full_width - 2 * edge_pad
    local title_space = math.max(0, math.floor((title_row_w - title_w - close_size) / 2))
    local title_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = edge_pad },
        HorizontalSpan:new{ width = title_space },
        title_widget,
        HorizontalSpan:new{ width = math.max(0, title_row_w - title_w - close_size - title_space) },
        self._close_btn,
        HorizontalSpan:new{ width = edge_pad },
    }
    title_row.width = title_row_w

    -- Grid: 3 columns with a dynamically computed row count. Every registered
    -- layout gets a card (one per id, sorted); rows = ceil(#ids / 3) floored at
    -- 3 so the grid never shrinks below the original 3-row footprint. An SVContainer
    -- wraps the grid so a tall grid (4+ rows on small e-ink screens) scrolls instead
    -- of clipping (US-21 — prerequisite for the full GNOME board set).
    local cols = 3
    local ids = MahjongLogic.layoutIds()
    local rows = math.max(3, math.ceil(#ids / cols))
    local title_row_h = math.max(title_h, close_size)
    local grid_top = title_row_h + Screen:scaleBySize(16)
    local grid_w = self.full_width - 2 * edge_pad - (cols - 1) * gap
    local card_w = math.floor(grid_w / cols)
    local grid_h = self.full_height - grid_top - edge_pad - (rows - 1) * gap
    local card_h = math.floor(grid_h / rows)

    -- Card layout: thumbnail on top, name underneath.
    local name_h = Screen:scaleBySize(28)
    local thumb_pad = Screen:scaleBySize(6)
    local thumb_w = card_w - 2 * thumb_pad
    local thumb_h = card_h - name_h - 2 * thumb_pad

    local grid_rows = {}
    local slot = 0
    for r = 0, rows - 1 do
        local row_children = { HorizontalSpan:new{ width = edge_pad } }
        for c = 0, cols - 1 do
            slot = slot + 1
            local id = ids[slot]
            if id then
                local thumb = layoutThumbnail(id, thumb_w, thumb_h)
                local name = TextWidget:new{
                    text = MahjongLogic.layoutName(id),
                    padding = 0,
                    face = Font:getFace("smallinfofont", Screen:scaleBySize(16)),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                }
                local card_content = VerticalGroup:new{
                    align = "center",
                    VerticalSpan:new{ width = thumb_pad },
                    thumb,
                    VerticalSpan:new{ width = thumb_pad },
                    name,
                }
                local card = FrameContainer:new{
                    card_content,
                    background = Blitbuffer.COLOR_WHITE,
                    color = Blitbuffer.COLOR_DARK_GRAY,
                    bordersize = Screen:scaleBySize(1),
                    radius = Screen:scaleBySize(8),
                    padding = 0,
                    width = card_w,
                    height = card_h,
                    _padding_left = 0,
                    _padding_right = 0,
                    _padding_top = 0,
                    _padding_bottom = 0,
                }
                card.getSize = function() return Geometry:new{ w = card_w, h = card_h } end
                -- Record the card's widget-local rect for the tap hit-test.
                -- The card sits at grid_top + r*(card_h+gap) vertically and
                -- edge_pad + c*(card_w+gap) horizontally.
                table.insert(self._card_rects, {
                    id = id,
                    x = edge_pad + c * (card_w + gap),
                    y = grid_top + r * (card_h + gap),
                    w = card_w,
                    h = card_h,
                })
                row_children[#row_children + 1] = card
            else
                -- Empty slot: a transparent spacer so the grid stays aligned.
                row_children[#row_children + 1] = HorizontalSpan:new{ width = card_w }
            end
            if c < cols - 1 then
                row_children[#row_children + 1] = HorizontalSpan:new{ width = gap }
            end
        end
        row_children[#row_children + 1] = HorizontalSpan:new{ width = edge_pad }
        grid_rows[#grid_rows + 1] = HorizontalGroup:new(row_children)
        if r < rows - 1 then
            grid_rows[#grid_rows + 1] = VerticalSpan:new{ width = gap }
        end
    end

    -- Wrap the grid rows in an SVContainer (scroll view) so the grid scrolls
    -- vertically on small screens when 4+ rows don't fit. The card-rect math
    -- above records positions in widget-local coords: the SVContainer sits at
    -- x=0 within the content VerticalGroup, and the grid rows' left edge_pad
    -- span places the first card at x=edge_pad — matching _card_rects. The
    -- SVContainer's width is the full grid-row width (edge_pad + cards + gaps
    -- + edge_pad) so no card is clipped by the viewport; height is capped to
    -- the available screen space, letting the full grid scroll when it
    -- overflows (US-21).
    local grid_total_h = rows * card_h + (rows - 1) * gap
    local grid_avail_h = self.full_height - grid_top - edge_pad
    local grid_content_w = 2 * edge_pad + cols * card_w + (cols - 1) * gap
    local grid_scroller = SVContainer:new{
        VerticalGroup:new{
            unpack(grid_rows),
        },
        dimen = Geometry:new{ w = grid_content_w, h = math.min(grid_avail_h, grid_total_h) },
    }
    local content = VerticalGroup:new{
        title_row,
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
        grid_scroller,
    }
    self._grid_scroller = grid_scroller

    -- Wrap in an opaque full-screen FrameContainer so the picker paints a
    -- solid background (hides the previous board behind it).
    self[1] = FrameContainer:new{
        content,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        _padding_left = 0,
        _padding_right = 0,
        _padding_top = 0,
        _padding_bottom = 0,
    }
    self[1].getSize = function()
        return Geometry:new{ w = self.full_width, h = self.full_height }
    end

    self.ges_events = {
        TapSelect = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function LayoutSelect:show()
    -- Scrolling content lives in a ScrollableContainer; KOReader requires the
    -- top-level widget to expose it as cropping_widget so the UIManager can
    -- confine repaints/flashes to the clipped region.
    self.cropping_widget = self._grid_scroller
    UIManager:show(self)
end

-- The picker is an opaque full-screen widget, so it must enqueue its own
-- full-screen refresh on show (the same onShow trick the dialogs use, but
-- covering the whole screen rather than a panel rect).
function LayoutSelect:onShow()
    UIManager:setDirty(self, "full")
    return true
end

-- Closes the picker and notifies the owner (close X or a tap outside any
-- card). The owner resumes the paused timer (or does nothing on the
-- first-launch path where no game was running).
function LayoutSelect:closeDialog()
    if self.onClose then self.onClose() end
    UIManager:close(self)
end

-- A tap inside the picker: hit-test the card rects, fire onPick for the hit
-- or closeDialog for a tap outside any card. `ges` is the second argument
-- (the first is the gesture spec's `args`, nil here) — see the Input-handling
-- pitfall in AGENTS.md.
function LayoutSelect:onTapSelect(_, ges)
    if not ges or not ges.pos then return true end
    local lx, ly = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    for _, r in ipairs(self._card_rects or {}) do
        if lx >= r.x and lx < r.x + r.w and ly >= r.y and ly < r.y + r.h then
            if self.onPick then self.onPick(r.id) end
            return true
        end
    end
    self:closeDialog()
    return true
end

return LayoutSelect
