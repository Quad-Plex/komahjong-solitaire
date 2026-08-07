-- Pause overlay (US-17) — floating window.
--
-- A modal centered card in the exact mahjongsettings.lua /
-- mahjongstatswidget.lua pattern: a transparent full-screen InputContainer
-- whose single child is a CenterContainer holding a white rounded
-- FrameContainer, so the game stays visible around the card. Unlike those
-- dialogs, a tap OUTSIDE the card does NOT dismiss it — it is silently
-- consumed, so no stray tap can reach the board, the toolbar, or the HUD while
-- the game is paused. The only way out is the Resume button (or the framework
-- closing the overlay, e.g. a back gesture), both of which run the owner's
-- onResume hook so the frozen clock restarts.
--
-- Closing the overlay by any path resumes the clock exactly once: resume() is
-- guarded by the _resumed flag, and onCloseWidget() falls back to resume() so
-- a framework-driven close never leaves the game paused with the clock frozen.

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
local VerticalSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
local ButtonWidget = require("ui/widget/button")
local I18n = require("mahjongi18n")
local t = I18n.t
local MahjongUI = require("mahjongui")

local PauseWidget = InputContainer:extend{
    name = "mahjongpause",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,      -- the Mahjong instance
    onResume = nil,    -- hook so the owner can restart the frozen clock
    _resumed = false,  -- true once onResume has fired (close paths run it once)
    _resume_btn = nil,
    _panel_geom = nil, -- absolute screen rect of the floating card
}

function PauseWidget:init()
    MahjongUI.refreshDimensions(self)
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local title = TextWidget:new{
        text = t("pause.title"),
        padding = 0,
        face = Font:getFace("tfont", Screen:scaleBySize(20)),
    }
    local hint = TextWidget:new{
        text = t("pause.body"),
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(16)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local resume_btn = ButtonWidget:new{
        text = t("pause.resume"),
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = true,
        width = Screen:scaleBySize(160),
        height = Screen:scaleBySize(32),
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = Screen:scaleBySize(6),
        callback = function() self:resume() end,
    }
    self._resume_btn = resume_btn

    local gap = Screen:scaleBySize(14)
    local panel = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(10),
        padding = Screen:scaleBySize(24),
        VerticalGroup:new{
            align = "center",
            title,
            VerticalSpan:new{ width = gap },
            hint,
            VerticalSpan:new{ width = gap },
            resume_btn,
        },
    }

    -- Where the card sits on screen (CenterContainer centers it in the
    -- full-screen dimen), kept for symmetry with the other floating dialogs.
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

    -- Full-screen tap gesture: it CONSUMES every tap (the handler returns true
    -- and does nothing), so no input reaches the board, toolbar, or HUD while
    -- paused. The Resume button inside the card matches its own more-specific
    -- gesture first (the same pattern the settings/stats dialogs rely on), so
    -- its callback still fires.
    self.ges_events = {
        TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function PauseWidget:show()
    UIManager:show(self)
end

-- The card must be refreshed to the screen when the overlay is shown (the same
-- onShow trick the settings dialog and ConfirmBox use).
function PauseWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self._panel_geom
    end)
    return true
end

-- Every tap that reaches the overlay (i.e. outside the Resume button) is
-- swallowed: the game stays paused. Unlike the settings/stats dialogs there is
-- deliberately no tap-outside-to-close.
function PauseWidget:onTapClose() -- luacheck: no unused args
    return true
end

-- Unpauses the game: fires the owner's onResume hook (restarts the clock) and
-- drops the overlay. Guarded so it runs exactly once no matter how many times
-- it is invoked (Resume button, onCloseWidget fallback).
function PauseWidget:resume()
    if self._resumed then return end
    self._resumed = true
    if self.onResume then self.onResume() end
    UIManager:close(self)
end

-- If the framework closes the overlay without resume() (e.g. a back gesture),
-- still restart the clock so the game never stays frozen behind the scenes.
function PauseWidget:onCloseWidget()
    self:resume()
end

return PauseWidget
