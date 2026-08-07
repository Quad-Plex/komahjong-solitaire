-- Gameplay help shown above the layout picker.

local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geometry = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local IconWidget = require("ui/widget/iconwidget")
local ButtonWidget = require("ui/widget/button")
local _ = require("gettext")
local MahjongLogic = require("mahjonglogic")

local HelpWidget = InputContainer:extend{
    name = "mahjonghelp",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    _panel_geom = nil,
    onClose = nil,
    page = 1,
}

local function label(value, size, color)
    return TextWidget:new{
        text = _(value), padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(size or 15)),
        fgcolor = color or Blitbuffer.COLOR_BLACK,
    }
end

local function bullet(value)
    return label("• " .. value, 15)
end

local function icon(name, size)
    size = Screen:scaleBySize(size or 30)
    return IconWidget:new{ icon = "mahjong/" .. name, width = size, height = size }
end

local function icon_group(names, description)
    local icons = {}
    for _, name in ipairs(names) do
        icons[#icons + 1] = icon(name, 34)
        icons[#icons + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(4) }
    end
    local group = { align = "left", HorizontalGroup:new(icons) }
    for line in description:gmatch("[^\n]+") do
        group[#group + 1] = label(line, 13)
    end
    return VerticalGroup:new(group)
end

local function board_tile(board, x, y, layer, marker, px, py, tw, th)
    local marker_widget = TextWidget:new{
        text = marker, padding = 0, bold = true,
        face = Font:getFace("tfont", Screen:scaleBySize(26)),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local marker_layer = CenterContainer:new{
        marker_widget, dimen = Geometry:new{ w = tw, h = th },
    }
    marker_layer.getSize = function()
        return Geometry:new{ w = tw, h = th }
    end
    local icon_name = MahjongLogic.iconForTile(board, x, y, layer)
    local bevel = icon_name:match("(_n[rb]?)$") or ""
    local tile = OverlapGroup:new{
        IconWidget:new{
            icon = "mahjong/empty" .. bevel,
            width = tw, height = th, alpha = true,
        },
        marker_layer,
        dimen = Geometry:new{ w = tw, h = th },
    }
    tile.overlap_offset = { px, py }
    return tile
end

local function example_board()
    local tw = Screen:scaleBySize(42)
    local th = Screen:scaleBySize(59)
    local bw = Screen:scaleBySize(4)
    local bh = Screen:scaleBySize(6)
    local origin_x = Screen:scaleBySize(9)
    local board = {}
    local positions = {
        { x = 0, y = 1, layer = 0 }, { x = 1, y = 1, layer = 0 },
        { x = 2, y = 1, layer = 0 }, { x = 3, y = 1, layer = 0 },
        { x = 4, y = 0.5, layer = 0 },
        { x = 1.5, y = 0.5, layer = 1 },
    }
    for _, p in ipairs(positions) do
        board[MahjongLogic.posKey(p.x, p.y, p.layer)] = "c1"
    end
    local children = {}
    for _, p in ipairs(positions) do
        local px = math.floor(origin_x + p.x * tw - p.layer * bw)
        local py = math.floor(p.y * th - p.layer * bh)
        local marker = MahjongLogic.isFree(board, p.x, p.y, p.layer) and "✓" or "X"
        children[#children + 1] = board_tile(board, p.x, p.y, p.layer,
            marker, px, py, tw + bw, th + bh)
    end
    children.dimen = Geometry:new{
        w = Screen:scaleBySize(235), h = Screen:scaleBySize(100),
    }
    return OverlapGroup:new(children)
end

local function lifted_example_board(width)
    local board = example_board()
    board.overlap_offset = { Screen:scaleBySize(150), -Screen:scaleBySize(30) }
    return OverlapGroup:new{
        board,
        dimen = Geometry:new{ w = width, h = Screen:scaleBySize(96) },
    }
end

function HelpWidget:init()
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true
    self:buildPage()
    self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function HelpWidget:buildPage()
    local gap = Screen:scaleBySize(8)
    local title = TextWidget:new{
        text = _("How to play"), padding = 0, bold = true, underline = true,
        face = Font:getFace("tfont", Screen:scaleBySize(21)),
    }
    local close = ButtonWidget:new{
        icon = "mahjong/close", width = Screen:scaleBySize(34), height = Screen:scaleBySize(34),
        icon_width = Screen:scaleBySize(20), icon_height = Screen:scaleBySize(20),
        bordersize = 0, padding = 0, callback = function() self:closeDialog() end,
    }
    local panel_w = math.floor(self.full_width * 0.86)
    local inner_w = panel_w - 2 * Screen:scaleBySize(22)
    local function section_heading(value)
        return CenterContainer:new{
            TextWidget:new{
                text = _(value), padding = 0, bold = true,
                face = Font:getFace("tfont", Screen:scaleBySize(18)),
            },
            dimen = Geometry:new{ w = inner_w, h = Screen:scaleBySize(26) },
        }
    end
    local title_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = close.width },
        CenterContainer:new{
            title,
            dimen = Geometry:new{ w = inner_w - 2 * close.width, h = Screen:scaleBySize(36) },
        },
        close,
    }
    local left = ButtonWidget:new{
        text = "←", width = Screen:scaleBySize(34), height = Screen:scaleBySize(34),
        bordersize = Screen:scaleBySize(1), padding = 0,
        callback = function() self.page = 1; self:buildPage() end,
    }
    local right = ButtonWidget:new{
        text = "→", width = Screen:scaleBySize(34), height = Screen:scaleBySize(34),
        bordersize = Screen:scaleBySize(1), padding = 0,
        callback = function() self.page = 2; self:buildPage() end,
    }
    if self.page == 1 then
        if left.disable then left:disable() else left.enabled = false end
    else
        if right.disable then right:disable() else right.enabled = false end
    end
    local page_indicator = label(string.format("%d/2", self.page), 15)
    local footer = CenterContainer:new{
        HorizontalGroup:new{
            left, HorizontalSpan:new{ width = Screen:scaleBySize(14) },
            page_indicator, HorizontalSpan:new{ width = Screen:scaleBySize(14) }, right,
        },
        dimen = Geometry:new{ w = inner_w, h = Screen:scaleBySize(34) },
    }
    local content
    if self.page == 1 then
        content = VerticalGroup:new{
            align = "left",
            label("Remove all tiles to win. Select two matching tiles", 15),
            label("that are free.", 15),
            label("Free tiles have no tile covering them.", 15),
            label("They also have a fully open right or left side,", 15),
            label("with no tile covering any part of it.", 15),
            VerticalSpan:new{ width = gap },
            CenterContainer:new{
                lifted_example_board(inner_w),
                dimen = Geometry:new{ w = inner_w, h = Screen:scaleBySize(96) },
            },
            label("Checkmarks are selectable. The raised tile covers the two middle tiles,", 12),
            label("and the far-right tile blocks its neighbor's side, so its neighbor is X.", 12),
            VerticalSpan:new{ width = gap },
            section_heading("Tile Groups"),
            icon_group({"c1", "d1", "b1"}, "Characters, dots and bamboo: match the same number\nand suit."),
            icon_group({"east", "south", "west", "north"}, "Winds: match identical winds."),
            icon_group({"red", "green", "white"}, "Dragons: match identical dragons."),
            icon_group({"flower1", "flower2", "flower3", "flower4"}, "Flowers: any flower matches\nany flower."),
            icon_group({"season1", "season2", "season3", "season4"}, "Seasons: match any season."),
        }
    else
        content = VerticalGroup:new{
            align = "left",
            section_heading("Scoring"),
            bullet("Each pair scores 10 points."),
            bullet("A same-group chain bonus adds 5 points when"),
            label("the score method is Chain.", 15),
            bullet("Clear another pair within 5 seconds for a COMBO:"),
            label("+10 points.", 15),
            bullet("Continue clearing pairs within 5 seconds for a chain"),
            label("combo: +5 more points each time.", 15),
            bullet("Hint shows a possible pair and costs -5 points"),
            label("once per hint session.", 15),
            bullet("Shuffle rearranges the remaining tiles and costs -10 points."),
            VerticalSpan:new{ width = gap },
            section_heading("Features"),
            bullet("Undo reverses your last pair, but does not refund"),
            label("hint or shuffle penalties.", 15),
            bullet("Pause stops the clock. Choose a layout when"),
            label("starting a new game.", 15),
        }
    end
    local panel_h = math.floor(self.full_height * 0.82) + Screen:scaleBySize(35)
    local panel_padding = Screen:scaleBySize(22)
    local inner_h = panel_h - 2 * panel_padding
    local title_h = Screen:scaleBySize(36)
    local footer_h = Screen:scaleBySize(34)
    local credits
    local credits_h = Screen:scaleBySize(30)
    if self.page == 2 then
        credits = CenterContainer:new{
            VerticalGroup:new{
                align = "center",
                label("Created by @Quad-Plex", 12),
                label("https://github.com/Quad-Plex/komahjong-solitaire", 12),
            },
            dimen = Geometry:new{ w = inner_w, h = credits_h },
        }
        credits.overlap_offset = { 0, inner_h - footer_h - credits_h - Screen:scaleBySize(6) }
    end
    -- Keep the header and footer out of the page content's intrinsic flow.
    -- This prevents a taller first page from pushing the footer outside the
    -- card, and prevents old page controls from being exposed on page two.
    title_row.overlap_offset = { 0, 0 }
    content.overlap_offset = { 0, title_h + gap }
    footer.overlap_offset = { 0, inner_h - footer_h }
    -- The headless widget stubs do not provide intrinsic sizing for groups;
    -- real KOReader groups already have getSize and keep their normal layout.
    local function ensure_size(widget, w, h)
        if not widget.getSize then
            widget.getSize = function()
                return Geometry:new{ w = w, h = h }
            end
        end
    end
    ensure_size(title_row, inner_w, title_h)
    ensure_size(content, inner_w, inner_h - title_h - gap - footer_h - gap)
    ensure_size(footer, inner_w, footer_h)
    if credits then ensure_size(credits, inner_w, credits_h) end
    local body = OverlapGroup:new{
        title_row,
        content,
        footer,
        credits,
        dimen = Geometry:new{ w = inner_w, h = inner_h },
    }
    local panel = FrameContainer:new{
        body,
        width = panel_w, height = panel_h,
        background = Blitbuffer.COLOR_WHITE, color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1), radius = Screen:scaleBySize(10),
        padding = panel_padding,
        _padding_left = panel_padding,
        _padding_right = panel_padding,
        _padding_top = panel_padding,
        _padding_bottom = panel_padding,
    }
    -- Keep the card bounds independent of the current page's intrinsic
    -- content size. This makes changing pages a content replacement, not a
    -- new floating window with a different center or border.
    panel.getSize = function()
        return Geometry:new{ w = panel_w, h = panel_h }
    end
    local size = panel:getSize()
    self._panel_geom = Geometry:new{
        x = math.floor((self.full_width - size.w) / 2), y = math.floor((self.full_height - size.h) / 2),
        w = size.w, h = size.h,
    }
    self[1] = CenterContainer:new{ dimen = self.dimen, panel }
    if UIManager:isWidgetShown(self) then
        UIManager:setDirty(self, "full")
    end
end

function HelpWidget:show() UIManager:show(self) end
function HelpWidget:onShow()
    UIManager:setDirty(self, "full")
    return true
end
function HelpWidget:closeDialog()
    if self.onClose then self.onClose() end
    UIManager:close(self, "full")
end
function HelpWidget:onCloseWidget() if self.onClose then self.onClose() end end
function HelpWidget:onTapClose(_, ges)
    if ges and ges.pos and ges.pos.notIntersectWith and self._panel_geom
            and ges.pos:notIntersectWith(self._panel_geom) then self:closeDialog() end
    return true
end

return HelpWidget
