-- Layout selection screen (US-14) — full-screen picker.
--
-- A full-screen opaque widget (not a floating card): choosing a layout is a
-- fresh start, so the previous board does not need to show through. The picker
-- uses fixed 3-column by 4-row pages with a small footer pager (US-48). Each
-- card carries a small thumbnail (a miniature schematic
-- of the layout's positions — small rounded rects per tile, per-layer up-left
-- offset so the 3D shape reads) centered by the tower's face center of mass
-- (US-30), a circular-arrows badge with the layout's human-win count (US-30), a
-- trophy score chip with the layout's best winning score (US-31, only shown once a win
-- exists), a time chip with the layout's best winning time (mm:ss, only
-- shown once a best time exists), and the layout name underneath (dark black, US-30). Tapping a card
-- shows a pressed state and, after a short deferred tick, deals a game on that
-- layout (US-30).
--
-- Interaction model (mirrors the board's hit-test): one full-screen tap
-- gesture; the handler hit-tests the tap against each card's rect and fires
-- `onPick(layout_id)` for the hit. A tap that misses every card (empty space)
-- is ignored — only the close X in the top-right corner cancels (closing the
-- picker on an empty-space tap dumped the user back to the file manager on
-- first launch, which read as an app crash). The owner (main.lua) pauses the
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
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local IconWidget = require("ui/widget/iconwidget")
local ButtonWidget = require("ui/widget/button")
local I18n = require("mahjongi18n")
local t = I18n.t
local MahjongLogic = require("mahjonglogic")
local MahjongUI = require("mahjongui")

-- Tile face aspect (portrait) and bevel fraction — must match the board
-- (mahjongboard.lua) so the thumbnail's 3D offset reads the same as the real
-- board.
local TILE_ASPECT = 1.4
local BEVEL_FRAC = 0.10

-- US-30: tapping a card shows a pressed state for this long before the deal
-- runs. The deal (board build + show) is synchronous, so without the deferral
-- the pressed state would never paint on e-ink; a short delay lets one screen
-- refresh show the feedback while the board loads in the background.
local TAP_FEEDBACK_SECONDS = 0.2

-- Keep the original layouts together on the first screen. New layouts belong
-- on the second screen rather than being interleaved by registry id. Unknown
-- layouts (for example, an installed custom layout) follow in sorted order.
local PICKER_LAYOUT_ORDER = {
    "bridge", "cloud", "confounding", "crab", "overpass", "pyramid",
    "red-dragon", "spider", "taipei", "tictactoe", "turtle", "ziggurat",
    "hare", "horse", "tiger", "ram", "monkey", "rooster",
    "dog", "snake", "boar", "ox", "wedges", "hourglass",
}

local function pickerLayoutIds()
    local registered = MahjongLogic.layouts
    local ids, seen = {}, {}
    for _, id in ipairs(PICKER_LAYOUT_ORDER) do
        if registered[id] then
            ids[#ids + 1] = id
            seen[id] = true
        end
    end
    local extra = {}
    for _, id in ipairs(MahjongLogic.layoutIds()) do
        if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do ids[#ids + 1] = id end
    return ids
end

local LayoutSelect = InputContainer:extend{
    name = "mahjonglayoutselect",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,      -- the Mahjong instance
    onPick = nil,      -- function(layout_id) — deals a fresh game on the layout
    onClose = nil,     -- function() — close X / tap outside (owner resumes timer)
    onHomeCallback = nil, -- function() — Kindle Home button
    onHelp = nil,      -- function() — show gameplay help above this picker
    onSettings = nil,  -- function() — show settings above this picker
    onStats = nil,     -- function() — show the stats card above this picker
    game_in_background = false, -- true = an active (un-won) game sits below the picker
    wins_by_layout = nil, -- map layout_id -> human wins (sync badge, US-30)
    highscores_by_layout = nil, -- map layout_id -> best winning score (score chip)
    best_times_by_layout = nil, -- map layout_id -> fastest win seconds (time chip)
    _card_rects = nil, -- { { id=, x=, y=, w=, h=, card= } } in widget-local coords
    _pending_pick = nil, -- layout id of a tapped-but-not-yet-dealt card (US-30)
    _page_buttons_visible = true,
    page = 1,
    page_count = 1,
}

-- Builds a miniature schematic of a layout's positions, scaled to fit a w x h
-- box. Each position is a small rounded rect (light gray, dark border) offset
-- per-layer up-left by the bevel fraction so the 3D pyramid reads (the same
-- projection the real board uses). The thumbnail is an OverlapGroup of these
-- tiles with a fixed dimen, so the owner can place it inside a card.
--
-- Centering: the tiles are scaled to fit the layout's bounding box (incl. the
-- outward bevels and the up-left layer shift), but the box is positioned by
-- the tower's FACE center of mass, not the box center. The 2.5D projection
-- shifts the upper layers up-left, so the box center sits to the east/south of
-- where the tower actually reads; centering the box would leave the picture
-- leaning up-left inside the card.
local function layoutThumbnail(id, w, h)
    local grid = MahjongLogic.gridBounds(id)
    local positions = MahjongLogic.buildLayout(id)
    local min_px, max_px = math.huge, -math.huge
    local min_py, max_py = math.huge, -math.huge
    local mass_cx, mass_cy, n = 0, 0, 0
    for _, p in ipairs(positions) do
        local ux = (p.x - grid.x_min) - p.layer * BEVEL_FRAC
        local uy = (p.y - grid.y_min) - p.layer * BEVEL_FRAC
        min_px = math.min(min_px, ux)
        max_px = math.max(max_px, (p.x - grid.x_min) + 1 + BEVEL_FRAC)
        min_py = math.min(min_py, uy)
        max_py = math.max(max_py, (p.y - grid.y_min) + 1 + BEVEL_FRAC)
        mass_cx = mass_cx + ux + 0.5
        mass_cy = mass_cy + uy + 0.5
        n = n + 1
    end
    local w_units = max_px - min_px
    local h_units = max_py - min_py
    -- Breathing room: scale the tower to fit a box inset by `margin` on every
    -- side, so a width-filling layout (e.g. the wide Spider/Bridge/Taipei
    -- shapes on a near-square portrait card) never touches the thumbnail's
    -- edge — a flush tower reads as "not centered" even when its mass is.
    local margin = math.min(math.max(Screen:scaleBySize(6), math.floor(math.min(w, h) * 0.05)),
        math.floor(math.min(w, h) / 3))
    local fit_w = math.max(2, w - 2 * margin)
    local fit_h = math.max(2, h - 2 * margin)
    -- Portrait faces (th = TILE_ASPECT * tw) sized to fit both axes.
    local scale = math.min(fit_w / w_units, (fit_h / h_units) / TILE_ASPECT)
    local tw = math.max(2, math.floor(scale))
    local function geometry(size)
        local th = math.max(2, math.floor(size * TILE_ASPECT))
        local bw = size * BEVEL_FRAC
        local bh = th * BEVEL_FRAC
        -- Position the tower's face center of mass at the canvas center
        -- (instead of centering the bounding box, which leans up-left; see
        -- the function comment above).
        local origin_x = math.floor(w / 2 - (mass_cx / n) * size)
        local origin_y = math.floor(h / 2 - (mass_cy / n) * th)
        return th, bw, bh, origin_x, origin_y
    end
    local th, bw, bh, origin_x, origin_y = geometry(tw)
    -- The fit-box scale can leave so little room that a lopsided tower's mass
    -- cannot reach the center (Turtle's head/tail asymmetry wants ~10px while
    -- the rounding slack is a few px). Shrink the tower a notch so the mass
    -- centering fits inside the margins — mass-centered with breathing room
    -- beats edge-to-edge with a residual lean.
    while tw > 2 and (origin_x + min_px * tw < margin
                      or origin_x + max_px * tw > w - margin
                      or origin_y + min_py * th < margin
                      or origin_y + max_py * th > h - margin) do
        tw = tw - 1
        th, bw, bh, origin_x, origin_y = geometry(tw)
    end

    local opts = {
        dimen = Geometry:new{ w = w, h = h },
    }
    for _, p in ipairs(positions) do
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

-- Builds the small played-count badge shown in the top-right corner of every
-- card: a circular-arrows glyph plus the human win count for that layout (0
-- when never won).
-- The badge is a real FrameContainer with a fixed dimen + getSize override, so
-- it can sit as a child of an OverlapGroup (see the OverlapGroup child rules in
-- AGENTS.md). The caller sets `overlap_offset` to position it on the thumb.
local function chipSize(scaled_size, extent, fraction)
    return math.max(1, math.min(Screen:scaleBySize(scaled_size),
        math.floor(extent * fraction)))
end

local function chipRadius(extent)
    return math.max(1, math.min(Screen:scaleBySize(4), math.floor(extent * 0.02)))
end

local function layoutBadge(wins, thumb_w, thumb_h)
    local extent = math.max(1, math.min(thumb_w, thumb_h))
    -- Card-internal controls must follow the thumbnail, not just device DPI.
    -- Android devices can report a large scaleBySize value while the picker
    -- cards grow by a much smaller factor than the Kindle canvas.
    local pad = chipSize(3, extent, 0.02)
    local icon_fraction = Screen:scaleBySize(1) > 1 and 0.07 or 0.09
    local icon_size = chipSize(16, extent, icon_fraction)
    local gap = chipSize(4, extent, 0.02)
    local text = tostring(wins or 0)
    local preferred = chipSize(14, extent, 0.08)
    local minimum = math.max(1, math.min(preferred, math.floor(extent * 0.04)))
    local text_max_w = math.max(1, math.floor(thumb_w * 0.18))
    local count_face = MahjongUI.fitTextFace(text, "smallinfofont", preferred,
        minimum, text_max_w, icon_size)
    local sync = IconWidget:new{
        icon = "mahjong/sync",
        width = icon_size,
        height = icon_size,
    }
    local count = TextWidget:new{
        text = text,
        padding = 0,
        face = count_face,
        max_width = text_max_w,
        truncate_with_ellipsis = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local count_size = count:getSize()
    local badge_w = icon_size + gap + count_size.w + 2 * pad
    local badge_h = math.max(icon_size, count_size.h) + 2 * pad
    local badge = FrameContainer:new{
        HorizontalGroup:new{
            sync,
            HorizontalSpan:new{ width = gap },
            count,
        },
        padding = pad,
        bordersize = 1,
        radius = chipRadius(extent),
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        width = badge_w,
        height = badge_h,
        _padding_left = pad,
        _padding_right = pad,
        _padding_top = pad,
        _padding_bottom = pad,
    }
    badge.getSize = function() return Geometry:new{ w = badge_w, h = badge_h } end
    return badge
end

-- Builds the small score chip shown in the thumbnail's bottom-right corner:
-- a trophy glyph plus the layout's best winning score (formatting keeps the
-- chip compact, and per-layout scores top out well below 1000 today). The chip
-- is a real FrameContainer with a fixed dimen + getSize override, so it can sit
-- as a child of an OverlapGroup (see the OverlapGroup child rules in
-- AGENTS.md). The caller sets `overlap_offset` to position it on the thumb and
-- only adds the chip to a card when the layout has a highscore (US-31).
local function layoutScoreChip(score, thumb_w, thumb_h)
    local extent = math.max(1, math.min(thumb_w, thumb_h))
    local pad = chipSize(3, extent, 0.02)
    local icon_fraction = Screen:scaleBySize(1) > 1 and 0.07 or 0.09
    local icon_size = chipSize(16, extent, icon_fraction)
    local gap = chipSize(4, extent, 0.02)
    local text_value = tostring(score)
    local preferred = chipSize(14, extent, 0.08)
    local minimum = math.max(1, math.min(preferred, math.floor(extent * 0.04)))
    local text_max_w = math.max(1, math.floor(thumb_w * 0.24))
    local text_face = MahjongUI.fitTextFace(text_value, "smallinfofont", preferred,
        minimum, text_max_w, icon_size)
    local trophy = IconWidget:new{
        icon = "mahjong/trophy",
        width = icon_size,
        height = icon_size,
    }
    local text = TextWidget:new{
        text = text_value,
        padding = 0,
        face = text_face,
        max_width = text_max_w,
        truncate_with_ellipsis = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local text_size = text:getSize()
    local chip_w = icon_size + gap + text_size.w + 2 * pad
    local chip_h = math.max(icon_size, text_size.h) + 2 * pad
    local chip = FrameContainer:new{
        HorizontalGroup:new{
            trophy,
            HorizontalSpan:new{ width = gap },
            text,
        },
        padding = pad,
        bordersize = 1,
        radius = chipRadius(extent),
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        width = chip_w,
        height = chip_h,
        _padding_left = pad,
        _padding_right = pad,
        _padding_top = pad,
        _padding_bottom = pad,
    }
    chip.getSize = function() return Geometry:new{ w = chip_w, h = chip_h } end
    return chip
end

-- Builds the small time chip shown in the thumbnail's bottom-left corner: the
-- layout's best winning time as an mm:ss string (no icon -- the value reads
-- clearly on its own, and this chip sits in the corner OPPOSITE the trophy
-- score chip so the two numbers aren't confused). The chip is a real
-- FrameContainer with a fixed dimen + getSize override, so it can sit as a
-- child of an OverlapGroup (see the OverlapGroup child rules in AGENTS.md).
-- The caller sets `overlap_offset` to position it on the thumb and only adds
-- the chip to a card when the layout has a best time.
local function layoutTimeChip(time_str, thumb_w, thumb_h)
    local extent = math.max(1, math.min(thumb_w, thumb_h))
    local pad = chipSize(3, extent, 0.02)
    local preferred = chipSize(14, extent, 0.08)
    local minimum = math.max(1, math.min(preferred, math.floor(extent * 0.04)))
    local text_max_w = math.max(1, math.floor(thumb_w * 0.28))
    local text_face = MahjongUI.fitTextFace(time_str, "smallinfofont", preferred,
        minimum, text_max_w, math.max(1, math.floor(extent * 0.12)))
    local text = TextWidget:new{
        text = time_str,
        padding = 0,
        face = text_face,
        max_width = text_max_w,
        truncate_with_ellipsis = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local text_size = text:getSize()
    local chip_w = text_size.w + 2 * pad
    local chip_h = text_size.h + 2 * pad
    local chip = FrameContainer:new{
        text,
        padding = pad,
        bordersize = 1,
        radius = chipRadius(extent),
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        width = chip_w,
        height = chip_h,
        _padding_left = pad,
        _padding_right = pad,
        _padding_top = pad,
        _padding_bottom = pad,
    }
    chip.getSize = function() return Geometry:new{ w = chip_w, h = chip_h } end
    return chip
end

function LayoutSelect:init()
    MahjongUI.refreshDimensions(self)
    self.dimen = Geometry:new{ x = 0, y = 0, w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true
    self._card_rects = {}
    local all_ids = pickerLayoutIds()
    self.page_count = math.max(1, math.ceil(#all_ids / 12))
    self.page = math.max(1, math.min(self.page or 1, self.page_count))

    local edge_pad = math.min(Screen:scaleBySize(16),
        math.max(Screen:scaleBySize(4), math.floor(self.full_width * 0.04)))
    local gap = math.min(Screen:scaleBySize(12),
        math.max(Screen:scaleBySize(2), math.floor(self.full_width * 0.03)))

    -- Title row: settings + stats + help at left, title centered, close X /
    -- return arrow at right. (the same grey-square style as the other dialogs).
    -- Tapping the close X cancels (closes the picker without dealing); when an
    -- active game sits below the picker the X renders as a return arrow (the
    -- owner's onClose resumes that game).
    local compact = MahjongUI.isNarrow(self.full_width)
    -- Header controls are sized from the canvas, not from the title's font
    -- metrics. A device font can be substantially larger than its nominal
    -- point size and must not make the whole header wider than the screen.
    local control_size = math.max(1, math.min(
        Screen:scaleBySize(compact and 38 or 42),
        math.floor(self.full_width / 7),
        math.floor(self.full_height / 10)))
    local btn_gap = math.max(1, math.min(Screen:scaleBySize(4), math.floor(control_size * 0.12)))
    local left_btns = 3 * control_size + 2 * btn_gap
    local right_btn = control_size
    local title_gap = btn_gap
    -- The stronger centered-title bound accounts for the asymmetric three-left
    -- button header. Without it, the title can fit between the controls while
    -- still being unable to sit at the actual screen center.
    local title_max_w = math.max(1, math.min(
        self.full_width - 2 * edge_pad - left_btns - right_btn - 2 * title_gap,
        self.full_width - 2 * edge_pad - 2 * left_btns))
    local title_max_h = math.max(1, control_size - 2 * title_gap)
    local title_face = MahjongUI.fitTextFace(
        t("picker.title"), "tfont", Screen:scaleBySize(compact and 18 or 22),
        Screen:scaleBySize(10), title_max_w, title_max_h)
    local title_widget = TextWidget:new{
        text = t("picker.title"),
        padding = 0,
        face = title_face,
        max_width = title_max_w,
        truncate_with_ellipsis = true,
    }
    local title_h = title_widget:getSize().h
    local close_size = control_size
    self._close_btn = ButtonWidget:new{
        icon = self.game_in_background and "chevron.left" or "mahjong/close",
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
    self._help_btn = ButtonWidget:new{
        text = "?",
        text_font_face = "tfont",
        -- Keep the Kindle glyph proportion, but stop a high-DPI font from
        -- filling the entire help button on Android devices.
        text_font_size = math.max(8, math.floor(close_size
            * (Screen:scaleBySize(1) > 1 and 0.30 or 0.45))),
        width = close_size,
        height = close_size,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = 0,
        callback = function() if self.onHelp then self.onHelp() end end,
    }
    self._settings_btn = ButtonWidget:new{
        icon = "appbar.settings",
        width = close_size,
        height = close_size,
        icon_width = math.floor(close_size * 0.6),
        icon_height = math.floor(close_size * 0.6),
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = 0,
        callback = function() if self.onSettings then self.onSettings() end end,
    }
    self._stats_btn = ButtonWidget:new{
        icon = "mahjong/stats",
        width = close_size,
        height = close_size,
        icon_width = math.floor(close_size * 0.6),
        icon_height = math.floor(close_size * 0.6),
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = 0,
        callback = function() if self.onStats then self.onStats() end end,
    }
    local title_w = math.min(title_widget:getSize().w, title_max_w)
    local title_row_w = self.full_width
    -- Keep the title centered in the full row, rather than centered in the
    -- space between the buttons. The left side carries three buttons (settings
    -- + stats + help) while the right carries only the close X / return arrow,
    -- so the two flexible spans must be asymmetric: left_space bumps the flex
    -- by a button (close_size + the 4px gap) so the title sits exactly at the
    -- row center regardless of how many buttons the left side holds.
    local flex = math.max(0, title_row_w - 2 * edge_pad
        - left_btns - right_btn - title_w)
    local left_space = math.max(0, math.floor((flex - (left_btns - right_btn)) / 2))
    local right_space = math.max(0, flex - left_space)
    local title_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = edge_pad },
        self._settings_btn,
        HorizontalSpan:new{ width = btn_gap },
        self._stats_btn,
        HorizontalSpan:new{ width = btn_gap },
        self._help_btn,
        HorizontalSpan:new{ width = left_space },
        title_widget,
        HorizontalSpan:new{ width = right_space },
        self._close_btn,
        HorizontalSpan:new{ width = edge_pad },
    }

    -- US-48: every page has exactly three columns and four rows. Empty slots
    -- remain transparent so a partial final page keeps the same geometry.
    local cols, rows = 3, 4
    local ids = all_ids
    local title_row_h = math.max(title_h, close_size)
    local top_pad = Screen:scaleBySize(5)
    local grid_top = top_pad + title_row_h + Screen:scaleBySize(16)
    local grid_w = self.full_width - 2 * edge_pad - (cols - 1) * gap
    local card_w = math.max(1, math.floor(grid_w / cols))
    local footer_h = math.max(1, math.min(Screen:scaleBySize(34), math.floor(self.full_height * 0.08)))
    local footer_gap = Screen:scaleBySize(8)
    local grid_h = math.max(1, self.full_height - grid_top - edge_pad - footer_gap - footer_h
        - (rows - 1) * gap)
    local card_h = math.max(1, math.floor(grid_h / rows))

    -- Card layout: thumbnail on top, name underneath.
    -- Keep the Kindle baseline, but do not let a high-DPI Android face turn
    -- the label area into a quarter of every card. The label is a compact
    -- caption below the schematic, so its slot scales with the card itself.
    -- Kindle-sized screens use the established geometry unchanged; the
    -- relative cap is for canvases where DPI scaling is the source of the
    -- oversized caption.
    local dpi_scale = Screen:scaleBySize(1)
    local name_h
    if dpi_scale > 1 then
        name_h = math.max(1, math.min(Screen:scaleBySize(28), math.floor(card_h * 0.14)))
    else
        name_h = math.min(Screen:scaleBySize(28),
            math.max(Screen:scaleBySize(16), math.floor(card_h * 0.25)))
    end
    local thumb_pad = math.min(Screen:scaleBySize(6), math.max(1, math.floor(card_w * 0.05)))
    local badge_margin = math.min(Screen:scaleBySize(4), math.max(1, math.floor(card_w * 0.03)))
    local thumb_w = math.max(1, card_w - 2 * thumb_pad)
    local thumb_h = math.max(1, card_h - name_h - 2 * thumb_pad)

    local grid_rows = {}
    local slot = 0
    for r = 0, rows - 1 do
        local row_children = { HorizontalSpan:new{ width = edge_pad } }
        for c = 0, cols - 1 do
            slot = slot + 1
            local id = ids[(self.page - 1) * 12 + slot]
            if id then
                local thumb = layoutThumbnail(id, thumb_w, thumb_h)
                -- US-30: played-count badge in the top-right corner of the
                -- thumbnail, counting human wins on this layout.
                local wins = (self.wins_by_layout and self.wins_by_layout[id]) or 0
                local badge = layoutBadge(wins, thumb_w, thumb_h)
                badge.overlap_offset = {
                    thumb_w - badge:getSize().w - badge_margin,
                    badge_margin,
                }
                -- US-31: score chip in the thumbnail's bottom-right corner
                -- (opposite the played badge's top-right). Only added when the
                -- layout has a highscore — a never-won layout shows no chip.
                local thumb_children = { thumb, badge }
                local highscore = (self.highscores_by_layout and self.highscores_by_layout[id]) or 0
                if highscore > 0 then
                    local chip = layoutScoreChip(highscore, thumb_w, thumb_h)
                    chip.overlap_offset = {
                        thumb_w - chip:getSize().w - badge_margin,
                        thumb_h - chip:getSize().h - badge_margin,
                    }
                    thumb_children[#thumb_children + 1] = chip
                end
                -- Best winning time chip in the thumbnail's bottom-left corner
                -- (opposite the score chip's bottom-right -- the corner the
                -- US-31 score chip left free). Only added when the layout has a
                -- best time, rendered as mm:ss; a never-won layout shows no chip.
                local best_time = (self.best_times_by_layout and self.best_times_by_layout[id]) or nil
                if best_time then
                    local tchip = layoutTimeChip(MahjongLogic.formatElapsed(best_time), thumb_w, thumb_h)
                    tchip.overlap_offset = {
                        badge_margin,
                        thumb_h - tchip:getSize().h - badge_margin,
                    }
                    thumb_children[#thumb_children + 1] = tchip
                end
                local name_text = t("layout." .. id)
                local name_max_w = math.max(1, card_w - 2 * thumb_pad)
                local name_preferred = math.max(1, math.min(Screen:scaleBySize(16),
                    math.floor(card_w * 0.06)))
                local name_minimum = math.max(1, math.min(name_preferred,
                    Screen:scaleBySize(10), math.floor(card_w * 0.035)))
                local name_face = MahjongUI.fitTextFace(
                    name_text, "smallinfofont", name_preferred,
                    name_minimum, name_max_w, name_h)
                local name = TextWidget:new{
                    text = name_text,
                    padding = 0,
                    face = name_face,
                    max_width = name_max_w,
                    forced_height = name_h,
                    truncate_with_ellipsis = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }
                local card_content = VerticalGroup:new{
                    align = "center",
                    VerticalSpan:new{ width = thumb_pad },
                    OverlapGroup:new(thumb_children),
                    VerticalSpan:new{ width = thumb_pad },
                    name,
                }
                local card = FrameContainer:new{
                    -- Center the card's content horizontally: the content
                    -- VerticalGroup is only as wide as its widest child (the
                    -- thumbnail), so without a full-card-width centering
                    -- wrapper it would sit flush against the card's LEFT edge
                    -- and the tower would look off-center whenever it fills
                    -- the thumbnail (US-30). CenterContainer centers it inside
                    -- the card's own box.
                    CenterContainer:new{
                        card_content,
                        dimen = Geometry:new{ w = card_w, h = card_h },
                    },
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
                    card = card, -- the FrameContainer, for the tap pressed state
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

    local left = ButtonWidget:new{
        text = "←", width = footer_h, height = footer_h,
        bordersize = Screen:scaleBySize(1), padding = 0,
        callback = function() self:setPage(self.page - 1) end,
    }
    local right = ButtonWidget:new{
        text = "→", width = footer_h, height = footer_h,
        bordersize = Screen:scaleBySize(1), padding = 0,
        callback = function() self:setPage(self.page + 1) end,
    }
    if self.page == 1 then
        if left.disable then left:disable() else left.enabled = false end
    end
    if self.page == self.page_count then
        if right.disable then right:disable() else right.enabled = false end
    end
    self._page_left = left
    self._page_right = right
    local indicator = TextWidget:new{
        text = string.format("%d/%d", self.page, self.page_count), padding = 0,
        face = MahjongUI.fitTextFace(string.format("%d/%d", self.page, self.page_count),
            "smallinfofont", Screen:scaleBySize(15), Screen:scaleBySize(9),
            math.max(1, footer_h * 2), footer_h),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local page_button_gap = Screen:scaleBySize(14)
    self._page_indicator = indicator
    self._page_footer_group = HorizontalGroup:new{
        self._page_buttons_visible and left or HorizontalSpan:new{ width = left:getSize().w },
        HorizontalSpan:new{ width = page_button_gap },
        self._page_buttons_visible and indicator or HorizontalSpan:new{ width = indicator:getSize().w },
        HorizontalSpan:new{ width = page_button_gap },
        self._page_buttons_visible and right or HorizontalSpan:new{ width = right:getSize().w },
    }
    local footer = CenterContainer:new{
        self._page_footer_group,
        dimen = Geometry:new{ w = self.full_width, h = footer_h },
    }
    self._page_footer_region = Geometry:new{
        x = 0,
        y = grid_top + grid_h + footer_gap,
        w = self.full_width,
        h = footer_h,
    }
    local grid = VerticalGroup:new{ unpack(grid_rows) }
    local content = VerticalGroup:new{
        VerticalSpan:new{ width = top_pad },
        title_row,
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
        grid,
        VerticalSpan:new{ width = footer_gap },
        footer,
    }

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
        Swipe = {
            GestureRange:new{ ges = "swipe", range = self.dimen },
        },
    }
    self.key_events = {
        Home = {
            { "Home" },
        },
    }
end

function LayoutSelect:setPage(page)
    page = math.max(1, math.min(page, self.page_count or 1))
    if page == self.page then return end
    self._pending_pick = nil
    self.page = page
    self:init()
    UIManager:setDirty(self, "ui")
end

function LayoutSelect:show()
    UIManager:show(self)
end

function LayoutSelect:setPageButtonsVisible(visible)
    self._page_buttons_visible = visible ~= false
    if self._page_footer_group then
        self._page_footer_group[1] = self._page_buttons_visible and self._page_left
            or HorizontalSpan:new{ width = self._page_left:getSize().w }
        self._page_footer_group[3] = self._page_buttons_visible and self._page_indicator
            or HorizontalSpan:new{ width = self._page_indicator:getSize().w }
        self._page_footer_group[5] = self._page_buttons_visible and self._page_right
            or HorizontalSpan:new{ width = self._page_right:getSize().w }
    end
    UIManager:setDirty(self, "ui")
end

-- Horizontal swipes follow the pager direction: a swipe left advances and a
-- swipe right goes back. KOReader reports these as west/east directions.
function LayoutSelect:onSwipe(_, ges)
    if not ges then return true end
    local direction = ges.direction or ges.dir
    if direction == "west" or direction == "left" then
        self:setPage(self.page + 1)
    elseif direction == "east" or direction == "right" then
        self:setPage(self.page - 1)
    end
    return true
end

function LayoutSelect:onHome()
    if self.onHomeCallback then self.onHomeCallback() end
    return true
end

-- The picker is an opaque full-screen widget, so it must enqueue its own
-- full-screen refresh on show (the same onShow trick the dialogs use, but
-- covering the whole screen rather than a panel rect).
function LayoutSelect:onShow()
    UIManager:setDirty(self, "full")
    return true
end

-- Closes the picker and notifies the owner (the close X — empty-space taps
-- are ignored, see onTapSelect). The owner resumes the paused timer (or does
-- nothing on the first-launch path where no game was running). An owner may
-- return false to keep the picker open while showing a confirmation dialog.
-- Clears a pending pick so a deferred deal can never fire after the picker is gone.
--
-- The close MUST request a full-screen refresh ("full"). A bare
-- UIManager:close(self) flags the uncovered widgets for repaint but enqueues
-- no refresh, and _repaint's fallback region-less "partial" refresh does not
-- actually update the e-ink panel — so when the picker is closed with no
-- active game underneath (first launch, or a won board's Play-again), the
-- picker's last frame stays on screen. Passing "full" is the same convention
-- as the HUD quit X and the win/Close dialogs (UIManager:close(self, "full"))
-- and the picker's own onShow (UIManager:setDirty(self, "full")).
function LayoutSelect:closeDialog()
    self._pending_pick = nil
    local close_picker = true
    if self.onClose and self.onClose() == false then
        close_picker = false
    end
    if close_picker then UIManager:close(self, "full") end
end

-- US-30: tap feedback. Darkens the tapped card's background + border so the
-- press is visible on e-ink while the board loads, and dirties the picker so
-- the next repaint shows it.
function LayoutSelect:_pressCard(r)
    if not r or not r.card then return end
    r.card.background = Blitbuffer.COLOR_LIGHT_GRAY
    r.card.color = Blitbuffer.COLOR_BLACK
    UIManager:setDirty(self, "ui", Geometry:new{
        x = r.x, y = r.y, w = r.w, h = r.h,
    })
end

-- US-30: runs the actual deal for a tapped card. The deal is deferred by
-- TAP_FEEDBACK_SECONDS (see onTapSelect) so the pressed state paints first;
-- this guard makes the deferred callback a no-op if the picker was closed or
-- another card was tapped in the meantime.
function LayoutSelect:_finishPick(id)
    if self._pending_pick ~= id then return end
    self._pending_pick = nil
    if self.onPick then self.onPick(id) end
end

-- A tap inside the picker: hit-test the card rects, fire onPick for the hit.
-- A tap that misses every card is a NO-OP — closing the picker on empty space
-- (gaps, the title row, the padding below the last row) dumped the user back
-- to the file manager on first launch, which reads as "the app crashed". Only
-- the close X cancels. `ges` is the second argument (the first is the gesture
-- spec's `args`, nil here) — see the Input-handling pitfall in AGENTS.md.
function LayoutSelect:onTapSelect(_, ges)
    if not ges or not ges.pos then return true end
    local lx, ly = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    for _, r in ipairs(self._card_rects or {}) do
        if lx >= r.x and lx < r.x + r.w and ly >= r.y and ly < r.y + r.h then
            -- Show the pressed state, then defer the deal one short tick so
            -- it actually paints before the (synchronous) board build replaces
            -- the picker — without this the feedback is swallowed by the build.
            self._pending_pick = r.id
            self:_pressCard(r)
            UIManager:scheduleIn(TAP_FEEDBACK_SECONDS, function()
                self:_finishPick(r.id)
            end)
            return true
        end
    end
    -- Empty space: ignore the tap (do not closeDialog).
    return true
end

return LayoutSelect
