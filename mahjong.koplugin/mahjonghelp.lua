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
local I18n = require("mahjongi18n")
local t = I18n.t
local MahjongLogic = require("mahjonglogic")
local MahjongUI = require("mahjongui")

local HelpWidget = InputContainer:extend{
    name = "mahjonghelp",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    _panel_geom = nil,
    cover_region = nil,
    _page_navigation_cover = nil,
    onClose = nil,
    page = 1,
}

local function label(value, size, color)
    return TextWidget:new{
        text = t(value), padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(size or 15)),
        fgcolor = color or Blitbuffer.COLOR_BLACK,
    }
end

local function bullet(value)
    return label("• " .. t(value), 15)
end

local function icon(name, size)
    size = Screen:scaleBySize(size or 30)
    return IconWidget:new{ icon = "mahjong/" .. name, width = size, height = size }
end

local function icon_group(names, description, group_size, max_width)
    group_size = group_size or #names
    local icon_size = Screen:scaleBySize(34)
    local row_gap = Screen:scaleBySize(1)
    local boundary_gap = Screen:scaleBySize(12)
    if max_width then
        icon_size = math.min(icon_size,
            math.max(Screen:scaleBySize(12),
                math.floor((max_width - (group_size - 1) * row_gap) / group_size)))
    end
    local icons = {}
    for i, name in ipairs(names) do
        icons[#icons + 1] = icon(name, icon_size / Screen:scaleBySize(1))
        if i < #names then
            icons[#icons + 1] = HorizontalSpan:new{
                width = i % group_size == 0 and boundary_gap or row_gap,
            }
        end
    end
    local group = { align = "left" }
    local boundary_count = math.floor((#names - 1) / group_size)
    local total_width = #names * icon_size + (#names - 1 - boundary_count) * row_gap
        + boundary_count * boundary_gap
    if max_width and #names > group_size and total_width > max_width then
        group = { align = "left" }
        for first = 1, #names, group_size do
            local row = {}
            for i = first, math.min(first + group_size - 1, #names) do
                row[#row + 1] = icon(names[i], icon_size / Screen:scaleBySize(1))
                if i < math.min(first + group_size - 1, #names) then
                    row[#row + 1] = HorizontalSpan:new{ width = row_gap }
                end
            end
            group[#group + 1] = HorizontalGroup:new(row)
            if first + group_size <= #names then
                group[#group + 1] = VerticalSpan:new{ height = row_gap }
            end
        end
    else
        group[#group + 1] = HorizontalGroup:new(icons)
    end
    for line in t(description):gmatch("[^\n]+") do
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

local function example_board(max_width)
    -- Keep the illustration at its original small reference size. It is an
    -- explanatory example between paragraphs, not a second board; only shrink
    -- it when a very narrow phone panel cannot hold the reference width.
    local reference_w = Screen:scaleBySize(235)
    local board_width = math.min(reference_w, max_width)
    local ratio = board_width / reference_w
    local tw = math.max(Screen:scaleBySize(12), math.floor(Screen:scaleBySize(42) * ratio))
    local th = math.max(Screen:scaleBySize(16), math.floor(Screen:scaleBySize(59) * ratio))
    local bw = math.max(1, math.floor(Screen:scaleBySize(4) * ratio))
    local bh = math.max(1, math.floor(Screen:scaleBySize(6) * ratio))
    local origin_x = math.max(0, math.floor(Screen:scaleBySize(9) * ratio))
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
        w = board_width, h = math.max(Screen:scaleBySize(70), th + Screen:scaleBySize(8)),
    }
    return OverlapGroup:new(children)
end

local function lifted_example_board(width)
    local board = example_board(width)
    board.overlap_offset = {
        math.max(0, math.floor((width - board.dimen.w) / 2)),
        -Screen:scaleBySize(38),
    }
    return OverlapGroup:new{
        board,
        dimen = Geometry:new{ w = width, h = Screen:scaleBySize(96) },
    }
end

function HelpWidget:init()
    MahjongUI.refreshDimensions(self)
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true
    self:buildPage()
    self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function HelpWidget:buildPage()
    local gap = Screen:scaleBySize(8)
    local title = TextWidget:new{
        text = t("help.title"), padding = 0, bold = true, underline = true,
        face = Font:getFace("tfont", Screen:scaleBySize(21)),
    }
    local close = ButtonWidget:new{
        icon = "mahjong/close", width = Screen:scaleBySize(34), height = Screen:scaleBySize(34),
        icon_width = Screen:scaleBySize(20), icon_height = Screen:scaleBySize(20),
        bordersize = 0, padding = 0, callback = function() self:closeDialog() end,
    }
    local panel_w = math.max(1, math.floor(self.full_width * 0.86))
    panel_w = math.min(panel_w, math.max(1, self.full_width - 2 * Screen:scaleBySize(8)))
    local panel_padding = math.min(Screen:scaleBySize(22), math.max(2, math.floor(panel_w * 0.08)))
    local inner_w = math.max(1, panel_w - 2 * panel_padding)
    local function section_heading(value)
        return CenterContainer:new{
            TextWidget:new{
                text = t(value), padding = 0, bold = true,
                face = Font:getFace("tfont", Screen:scaleBySize(18)),
            },
            dimen = Geometry:new{ w = inner_w, h = Screen:scaleBySize(26) },
        }
    end
    local title_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = close.width },
        CenterContainer:new{
            title,
            dimen = Geometry:new{ w = math.max(1, inner_w - 2 * close.width), h = Screen:scaleBySize(36) },
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
            label("help.page_one_1", 15), label("help.page_one_2", 15),
            label("help.page_one_3", 15), label("help.page_one_4", 15),
            label("help.page_one_5", 15),
            VerticalSpan:new{ width = gap },
            CenterContainer:new{
                lifted_example_board(inner_w),
                dimen = Geometry:new{ w = inner_w, h = Screen:scaleBySize(96) },
            },
            label("help.page_one_6", 12), label("help.page_one_7", 12),
            VerticalSpan:new{ width = gap },
            section_heading("help.tile_groups"),
            icon_group({"c1", "c2", "c3", "d1", "d2", "d3", "b1", "b2", "b3"}, "help.characters", 3, inner_w),
            icon_group({"east", "south", "west", "north"}, "help.winds", nil, inner_w),
            icon_group({"red", "green", "white"}, "help.dragons", nil, inner_w),
            icon_group({"flower1", "flower2", "flower3", "flower4"}, "help.flowers", nil, inner_w),
            icon_group({"season1", "season2", "season3", "season4"}, "help.seasons", nil, inner_w),
        }
    else
        content = VerticalGroup:new{
            align = "left",
            section_heading("help.scoring"),
            bullet("help.each_pair"), bullet("help.chain_bonus"), label("help.chain_method", 15),
            label("help.chain_method_2", 15),
            bullet("help.combo_1"), label("help.combo_2", 15), bullet("help.combo_3"),
            label("help.combo_4", 15), bullet("help.hint_penalty"), label("help.hint_session", 15),
            bullet("help.shuffle_penalty"),
            VerticalSpan:new{ width = gap },
            section_heading("help.features"),
            bullet("help.undo_1"), label("help.undo_2", 15),
            bullet("help.pause_1"), label("help.pause_2", 15),
        }
    end
    local panel_h = math.floor(self.full_height * 0.82) + Screen:scaleBySize(35)
    panel_h = math.min(panel_h, math.max(1, self.full_height - 2 * Screen:scaleBySize(8)))
    local inner_h = math.max(1, panel_h - 2 * panel_padding)
    local title_h = Screen:scaleBySize(36)
    local footer_h = Screen:scaleBySize(34)
    local credits
    local credits_h = Screen:scaleBySize(30)
    if self.page == 2 then
        credits = CenterContainer:new{
            VerticalGroup:new{
                align = "center",
                label("help.created_by", 12),
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
    local centered = CenterContainer:new{ dimen = self.dimen, panel }
    if self.cover_region then
        local region = self.cover_region
        local cover = FrameContainer:new{
            width = region.w,
            height = region.h,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            _padding_left = 0,
            _padding_right = 0,
            _padding_top = 0,
            _padding_bottom = 0,
        }
        cover.getSize = function()
            return Geometry:new{ w = region.w, h = region.h }
        end
        cover.overlap_offset = { region.x, region.y }
        self._page_navigation_cover = cover
        self[1] = OverlapGroup:new{
            cover,
            centered,
            dimen = self.dimen,
        }
    else
        self[1] = centered
    end
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
