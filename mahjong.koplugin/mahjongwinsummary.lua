-- Win summary (US-12): a bounded, centered floating results card.

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
    parent = nil,
    text = "",
    win_rows = nil,
    ok_text = nil,
    cancel_text = nil,
    ok_callback = nil,
    cancel_callback = nil,
    _done = false,
    _row_group = nil,
    _panel_geom = nil,
}

function WinSummary:init()
    MahjongUI.refreshDimensions(self)
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local compact = MahjongUI.isNarrow(self.full_width) or self.full_height < 700
    -- Kindle screens can report a large scaleBySize factor without providing
    -- proportionally more room. Keep this card readable instead of allowing
    -- DPI scaling to turn the headline into a screen-wide widget.
    local label_preferred = math.min(Screen:scaleBySize(compact and 14 or 18), 24)
    local value_preferred = math.min(Screen:scaleBySize(compact and 16 or 20), 26)
    local headline_preferred = math.min(Screen:scaleBySize(compact and 16 or 20), 28)
    local label_minimum = math.min(Screen:scaleBySize(8), label_preferred)
    local value_minimum = math.min(Screen:scaleBySize(9), value_preferred)
    local label_color = Blitbuffer.COLOR_DARK_GRAY

    local function measureText(text, face)
        local probe = TextWidget:new{ text = text, padding = 0, face = face }
        local w = probe:getSize().w
        if probe.free then probe:free() end
        return w
    end

    local win_rows = self.win_rows or {}
    local longest_label = ""
    local longest_value = ""
    local max_label_w = 0
    local max_value_w = 0
    local probe_label_face = Font:getFace("smallinfofont", label_preferred)
    local probe_value_face = Font:getFace("cfont", value_preferred)
    for _, r in ipairs(win_rows) do
        local label_w = measureText(r.label, probe_label_face)
        if label_w > max_label_w then
            max_label_w = label_w
            longest_label = r.label
        end
        local full = r.value .. (r.marker and (" " .. r.marker) or "")
        local value_w = measureText(full, probe_value_face)
        if value_w > max_value_w then
            max_value_w = value_w
            longest_value = full
        end
    end

    local border = math.max(1, math.min(Screen:scaleBySize(1),
        math.floor(self.full_width * 0.01)))
    local outer_margin = math.max(Screen:scaleBySize(8),
        math.floor(self.full_width * 0.02))
    local max_panel_w = math.max(1, self.full_width - 2 * outer_margin)
    local panel_padding = math.max(Screen:scaleBySize(compact and 8 or 12),
        math.floor(math.min(self.full_width, self.full_height) * 0.018))
    panel_padding = math.min(panel_padding, Screen:scaleBySize(24))
    local max_content_w = math.max(1,
        max_panel_w - 2 * panel_padding - 2 * border)

    local headline_widget = TextWidget:new{
        text = self.text,
        padding = 0,
        face = Font:getFace("tfont", headline_preferred),
    }
    local headline_size = headline_widget:getSize()

    local row_gap = math.min(Screen:scaleBySize(compact and 4 or 6),
        math.max(2, math.floor(self.full_height * 0.008)))
    local center_gap = math.min(Screen:scaleBySize(8),
        math.max(3, math.floor(max_content_w * 0.02)))
    local marker_gap = math.min(Screen:scaleBySize(4),
        math.max(2, math.floor(max_content_w * 0.01)))
    local gap = math.min(Screen:scaleBySize(compact and 8 or 12),
        math.max(2, math.floor(self.full_height * 0.018)))

    -- Buttons have a bounded width too, so they cannot become the child that
    -- silently widens the FrameContainer on a translated or small screen.
    local button_gap = math.min(Screen:scaleBySize(10),
        math.max(2, math.floor(max_content_w * 0.02)))
    local btn_w = math.min(Screen:scaleBySize(150),
        math.max(1, math.floor((max_content_w - button_gap) / 2)))
    local btn_h = math.max(1, math.min(Screen:scaleBySize(32),
        math.floor(self.full_height * 0.06)))
    local button_face_size = math.max(8, math.min(20, math.floor(btn_h * 0.6)))
    local primary = ButtonWidget:new{
        text = self.ok_text,
        text_font_face = "cfont",
        text_font_size = button_face_size,
        text_font_bold = true,
        width = btn_w,
        height = btn_h,
        bordersize = border,
        radius = Screen:scaleBySize(4),
        padding = math.max(1, math.min(Screen:scaleBySize(6), math.floor(btn_h * 0.16))),
        callback = function() self:_finish(true) end,
    }
    local secondary = ButtonWidget:new{
        text = self.cancel_text,
        text_font_face = "cfont",
        text_font_size = button_face_size,
        text_font_bold = true,
        width = btn_w,
        height = btn_h,
        bordersize = border,
        radius = Screen:scaleBySize(4),
        padding = math.max(1, math.min(Screen:scaleBySize(6), math.floor(btn_h * 0.16))),
        callback = function() self:_finish(false) end,
    }
    local buttons = HorizontalGroup:new{
        primary,
        HorizontalSpan:new{ width = button_gap },
        secondary,
    }

    -- Keep the card content-sized when it fits, but never let intrinsic text
    -- determine a width larger than the runtime canvas. Rows use two equal
    -- bounded slots around a stable divider.
    local rows_w = 2 * math.max(max_label_w, max_value_w) + 2 * center_gap
    local buttons_w = 2 * btn_w + button_gap
    local content_w = math.min(max_content_w,
        math.max(rows_w, headline_size.w, buttons_w))
    local half_w = math.max(1, math.floor((content_w - 2 * center_gap) / 2))
    local label_slot_w = half_w
    local value_slot_w = half_w
    local fitted_label_face = MahjongUI.fitTextFace(
        longest_label, "smallinfofont", label_preferred, label_minimum,
        label_slot_w, Screen:scaleBySize(24))
    local fitted_value_face = MahjongUI.fitTextFace(
        longest_value, "cfont", value_preferred, value_minimum,
        value_slot_w, Screen:scaleBySize(28))
    local fitted_headline_face = MahjongUI.fitTextFace(
        self.text, "tfont", headline_preferred, label_minimum,
        content_w, Screen:scaleBySize(32))
    headline_widget.face = fitted_headline_face
    headline_widget.max_width = content_w
    headline_widget.truncate_with_ellipsis = true
    local headline_h = math.min(headline_widget:getSize().h,
        math.max(1, math.floor(self.full_height * 0.06)))

    self._content_w = content_w
    self._max_panel_w = max_panel_w
    self._panel_padding = panel_padding
    self._border = border
    self._row_slots = { label = label_slot_w, value = value_slot_w }
    self._headline_widget = headline_widget

    local function boundedMarker(r, marker_slot_w)
        if not r.marker_widget then return nil end
        local marker_size = r.marker_widget.getSize
            and r.marker_widget:getSize() or { w = 0 }
        if marker_size.w <= marker_slot_w then return r.marker_widget end

        -- Record markers are secondary to the session value. If an icon/group
        -- marker cannot fit, use its harness-equivalent text with an ellipsis
        -- guard rather than allowing a HorizontalGroup to widen the card.
        local marker_text = r.marker or ""
        local marker_face = MahjongUI.fitTextFace(
            marker_text, "cfont", fitted_value_face.size or value_preferred,
            value_minimum, marker_slot_w, Screen:scaleBySize(28))
        return TextWidget:new{
            text = marker_text,
            padding = 0,
            face = marker_face,
            bold = true,
            max_width = marker_slot_w,
            truncate_with_ellipsis = true,
        }
    end

    local row_widgets = {}
    for i, r in ipairs(win_rows) do
        local label_w = math.min(label_slot_w, measureText(r.label, fitted_label_face))
        local value_w = math.min(value_slot_w, measureText(r.value, fitted_value_face))
        local row_children = {
            HorizontalSpan:new{ width = math.max(0, label_slot_w - label_w) },
            TextWidget:new{
                text = r.label,
                padding = 0,
                face = fitted_label_face,
                max_width = label_slot_w,
                truncate_with_ellipsis = true,
                fgcolor = label_color,
            },
            HorizontalSpan:new{ width = center_gap },
            TextWidget:new{
                text = r.value,
                padding = 0,
                face = fitted_value_face,
                bold = true,
                max_width = value_slot_w,
                truncate_with_ellipsis = true,
            },
        }
        local used_w = label_slot_w + center_gap + value_w
        local marker_slot_w = math.max(1, value_slot_w - value_w - marker_gap)
        local marker_widget = boundedMarker(r, marker_slot_w)
        if marker_widget then
            row_children[#row_children + 1] = HorizontalSpan:new{ width = marker_gap }
            row_children[#row_children + 1] = marker_widget
            local marker_w = marker_widget.getSize
                and (marker_widget:getSize().w or 0) or 0
            used_w = used_w + marker_gap + math.min(marker_slot_w, marker_w)
        end
        row_children[#row_children + 1] = HorizontalSpan:new{
            width = math.max(0, content_w - used_w),
        }
        row_widgets[#row_widgets + 1] = HorizontalGroup:new(row_children)
        if i < #win_rows then
            row_widgets[#row_widgets + 1] = VerticalSpan:new{ width = row_gap }
        end
    end
    self._row_group = VerticalGroup:new(row_widgets)

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
        bordersize = border,
        radius = Screen:scaleBySize(10),
        padding = panel_padding,
        VerticalGroup:new(vchildren),
    }

    local panel_size = panel:getSize()
    self._panel_geom = Geometry:new{
        x = math.max(0, math.floor((self.full_width - panel_size.w) / 2)),
        y = math.max(0, math.floor((self.full_height - panel_size.h) / 2)),
        w = panel_size.w,
        h = panel_size.h,
    }
    self[1] = CenterContainer:new{
        dimen = Geometry:new{ w = self.full_width, h = self.full_height },
        panel,
    }

    -- Consume every tap outside the buttons. Only the explicit buttons dismiss
    -- the card, so a stray tap cannot reach the board or exit the game.
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

function WinSummary:_finish(ok)
    if self._done then return end
    self._done = true
    local cb = ok and self.ok_callback or self.cancel_callback
    if cb then cb() end
    UIManager:close(self, "ui", self._panel_geom)
end

return WinSummary
