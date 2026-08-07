-- Compact gameplay help shown above the layout picker.

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
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local IconWidget = require("ui/widget/iconwidget")
local ButtonWidget = require("ui/widget/button")
local _ = require("gettext")

local HelpWidget = InputContainer:extend{
    name = "mahjonghelp",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    _panel_geom = nil,
    onClose = nil,
}

local function text(value, size, color)
    return TextWidget:new{
        text = _(value),
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(size or 15)),
        fgcolor = color or Blitbuffer.COLOR_BLACK,
    }
end

local function tile(icon, label)
    local size = Screen:scaleBySize(34)
    return HorizontalGroup:new{
        IconWidget:new{ icon = "mahjong/" .. icon, width = size, height = size },
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        text(label, 13),
    }
end

function HelpWidget:init()
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local title = text("How to play", 21)
    local close = ButtonWidget:new{
        icon = "mahjong/close",
        width = Screen:scaleBySize(34),
        height = Screen:scaleBySize(34),
        icon_width = Screen:scaleBySize(20),
        icon_height = Screen:scaleBySize(20),
        bordersize = 0,
        padding = 0,
        callback = function() self:closeDialog() end,
    }

    local gap = Screen:scaleBySize(8)
    local content = VerticalGroup:new{
        align = "left",
        text("Remove all tiles to win. Select two matching tiles that are free.", 15),
        text("A tile is free when no tile covers it and either its left or", 15),
        text("right side is open.", 15),
        VerticalSpan:new{ width = gap },
        text("Tile types", 16),
        tile("c1", "Characters, dots and bamboo: match the same number and suit."),
        tile("east", "Winds and dragons: match identical symbols."),
        tile("flower1", "Flowers: any flower matches any other flower."),
        tile("season1", "Seasons: any season matches any other season."),
        VerticalSpan:new{ width = gap },
        text("Features", 16),
        text("Hint shows a possible pair (and costs points). Shuffle costs", 15),
        text("points too. Undo reverses your last pair.", 15),
        text("Pause stops the clock. Choose a different layout when starting", 15),
        text("a new game.", 15),
        VerticalSpan:new{ width = gap },
        text("Scoring", 16),
        text("Pairs score points; consecutive matches from the same group", 15),
        text("earn a bonus. The timer is for reference.", 15),
    }

    local panel = FrameContainer:new{
        VerticalGroup:new{
            HorizontalGroup:new{
                title,
                HorizontalSpan:new{ width = Screen:scaleBySize(80) },
                close,
            },
            VerticalSpan:new{ width = gap },
            content,
        },
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(10),
        padding = Screen:scaleBySize(18),
    }
    local panel_size = panel:getSize()
    self._panel_geom = Geometry:new{
        x = math.floor((self.full_width - panel_size.w) / 2),
        y = math.floor((self.full_height - panel_size.h) / 2),
        w = panel_size.w,
        h = panel_size.h,
    }
    self[1] = CenterContainer:new{
        dimen = Geometry:new{ w = self.full_width, h = self.full_height },
        panel,
    }
    self.ges_events = {
        TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function HelpWidget:show()
    UIManager:show(self)
end

function HelpWidget:onShow()
    UIManager:setDirty(self, function() return "ui", self._panel_geom end)
    return true
end

function HelpWidget:closeDialog()
    if self.onClose then self.onClose() end
    UIManager:close(self, "full")
end

function HelpWidget:onCloseWidget()
    if self.onClose then self.onClose() end
end

function HelpWidget:onTapClose(_, ges)
    if ges and ges.pos and ges.pos.notIntersectWith and self._panel_geom
            and ges.pos:notIntersectWith(self._panel_geom) then
        self:closeDialog()
    end
    return true
end

return HelpWidget
