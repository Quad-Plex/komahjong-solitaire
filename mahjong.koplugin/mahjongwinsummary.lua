-- Win summary (US-12) — floating centered card.
--
-- The cleared-board dialog as a floating card in the exact
-- mahjongsettings.lua / mahjongstatswidget.lua / mahjongpause.lua pattern: a
-- transparent full-screen InputContainer whose single child is a
-- CenterContainer holding a white rounded FrameContainer, so the game stays
-- visible around the card. The card sizes itself to its content and is centered,
-- so the whole summary is horizontally centered in the window (the stock
-- ConfirmBox centers a wide headline text area, which left the narrow label/
-- value rows hugging the left edge).
--
-- Layout inside the card:
--   * the headline ("You cleared the board!" / "Congratulations! …best score…")
--     centered across the card's content width;
--   * the summary rows as right-aligned labels (widest label drives the column)
--     with the VALUES in a uniform, LEFT-aligned column — every value starts at
--     the same x;
--   * a two-button row (Play again / Select Layout) centered at the bottom.
--
-- A tap anywhere OUTSIDE the buttons is silently consumed (never closes the
-- card), matching the dialog contract that only the buttons dismiss it
-- (US-20/32: a stray tap must not exit the whole app).
--
-- It exposes `text` (the headline), `win_rows` ({ label, value } pairs),
-- `ok_text`/`cancel_text`, and `ok_callback`/`cancel_callback` — the same
-- surface as a ConfirmButton — so the headless harness drives it and re-reads
-- its summary exactly as before.

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
local ButtonWidget = require("ui/widget/button")
local MahjongUI = require("mahjongui")

local WinSummary = InputContainer:extend{
    name = "mahjongwinsummary",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,        -- the Mahjong instance (unused; kept for symmetry)
    text = "",           -- headline string (the harness reads it)
    win_rows = nil,      -- { {label=, value=}, ... } (rows + harness surface)
    ok_text = nil,       -- "Play again"
    cancel_text = nil,   -- "Select Layout"
    ok_callback = nil,   -- fired by "Play again" (the harness calls it directly)
    cancel_callback = nil, -- fired by "Select Layout"
    _done = false,       -- guards the buttons so a double tap fires once
    _row_group = nil,    -- the aligned-rows VerticalGroup (harness structural check)
    _panel_geom = nil,   -- absolute screen rect of the floating card
}

function WinSummary:init()
    MahjongUI.refreshDimensions(self)
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local label_face = Font:getFace("smallinfofont", Screen:scaleBySize(18))
    local value_face = Font:getFace("cfont", Screen:scaleBySize(20))
    local label_color = Blitbuffer.COLOR_DARK_GRAY

    local function measureText(text, face)
        local probe = TextWidget:new{ text = text, padding = 0, face = face }
        local w = probe:getSize().w
        probe:free()
        return w
    end

    -- Rows: right-align every label to the widest one so the value column
    -- starts at the same x and each value is LEFT-aligned within it (the stats
    -- screen's column trick). Measure each label so the leading span pads it.
    local win_rows = self.win_rows or {}
    local max_label_w = 0
    for _, r in ipairs(win_rows) do
        max_label_w = math.max(max_label_w, measureText(r.label, label_face))
    end
    local label_gap = Screen:scaleBySize(12)
    local row_gap = Screen:scaleBySize(4)
    local max_value_w = 0
    for _, r in ipairs(win_rows) do
        max_value_w = math.max(max_value_w, measureText(r.value, value_face))
    end
    local row_widgets = {}
    for i, r in ipairs(win_rows) do
        row_widgets[#row_widgets + 1] = HorizontalGroup:new{
            HorizontalSpan:new{ width = max_label_w - measureText(r.label, label_face) },
            TextWidget:new{ text = r.label, padding = 0, face = label_face, fgcolor = label_color },
            HorizontalSpan:new{ width = label_gap },
            TextWidget:new{ text = r.value, padding = 0, face = value_face, bold = true },
        }
        if i < #win_rows then
            row_widgets[#row_widgets + 1] = VerticalSpan:new{ width = row_gap }
        end
    end
    self._row_group = VerticalGroup:new(row_widgets)

    -- Headline, centered across the card's content width.
    local headline_widget = TextWidget:new{
        text = self.text,
        padding = 0,
        face = Font:getFace("tfont", Screen:scaleBySize(20)),
    }
    local headline_size = headline_widget:getSize()
    local gap = Screen:scaleBySize(14)

    -- Buttons: Play again (primary) + Select Layout, centered at the bottom.
    local panel_padding = math.min(Screen:scaleBySize(24),
        math.max(Screen:scaleBySize(10), math.floor(self.full_width * 0.05)))
    local max_content_w = math.max(1, self.full_width - 2 * panel_padding - 2 * Screen:scaleBySize(8))
    local btn_w = math.min(Screen:scaleBySize(150),
        math.max(1, math.floor((max_content_w - Screen:scaleBySize(10)) / 2)))
    local btn_h = Screen:scaleBySize(32)
    local primary = ButtonWidget:new{
        text = self.ok_text,
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = true,
        width = btn_w,
        height = btn_h,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = Screen:scaleBySize(6),
        callback = function() self:_finish(true) end,
    }
    local secondary = ButtonWidget:new{
        text = self.cancel_text,
        text_font_face = "cfont",
        text_font_size = 20,
        width = btn_w,
        height = btn_h,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = Screen:scaleBySize(6),
        callback = function() self:_finish(false) end,
    }
    local buttons = HorizontalGroup:new{
        primary,
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        secondary,
    }
    -- Content width: at least the widest row, but wide enough for the headline
    -- and the button row so those center over the value column. Widths come
    -- from measured text (the mock's group containers expose no getSize, so this
    -- never depends on a container's getSize — mirroring the stats screen).
    local rows_w = max_label_w + label_gap + max_value_w
    local buttons_w = 2 * btn_w + Screen:scaleBySize(10)
    local content_w = math.min(max_content_w, math.max(rows_w, headline_size.w, buttons_w))
    local headline_h = headline_size.h

    -- Horizontal children are centered at `content_w`; the rows keep their
    -- left-aligned value column below.
    local vchildren = {
        CenterContainer:new{
            dimen = Geometry:new{ w = content_w, h = headline_h },
            headline_widget,
        },
        VerticalSpan:new{ width = gap },
        self._row_group,
        VerticalSpan:new{ width = gap * 2 },
        CenterContainer:new{
            dimen = Geometry:new{ w = content_w, h = btn_h },
            buttons,
        },
    }

    local panel = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(10),
        padding = panel_padding,
        VerticalGroup:new(vchildren),
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

    -- Consume every tap outside the buttons (a stray tap must not dismiss, and
    -- must never reach the board/toolbar/HUD).
    self.ges_events = {
        TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function WinSummary:show()
    UIManager:show(self)
end

function WinSummary:onShow()
    UIManager:setDirty(self, function()
        return "ui", self._panel_geom
    end)
    return true
end

function WinSummary:onTapClose() -- luacheck: no unused args
    return true
end

-- Fires the action (Play again true / Select Layout false), then drops the card.
-- Guarded so a double tap cannot fire the callback twice.
function WinSummary:_finish(ok)
    if self._done then return end
    self._done = true
    local cb = ok and self.ok_callback or self.cancel_callback
    if cb then cb() end
    UIManager:close(self, "ui", self._panel_geom)
end

return WinSummary
