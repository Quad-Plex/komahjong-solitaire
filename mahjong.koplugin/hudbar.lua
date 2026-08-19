-- HUD top bar (replaces the TitleBarWidget + plain-text subtitle).
--
-- Two-row layout:
--   Row 1:  ─── "Mahjong Solitaire" ───         [  X  ]
--   Row 2:  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
--           │ 🀡 45            │  │ 💡 12            │  │ ⭐ 340           │
--           │  Pairs           │  │   Free           │  │  Score           │
--           └──────────────────>  └──────────────────>  └──────────────────┘
--
-- Row 1: title centered, square grey quit X at far-right edge.
-- Row 2: three chips with edge gaps and ~8px spacers between them.
-- Each chip: icon | value | label (horizontal pill). main.lua calls
-- setStats(pairs, free, score) after every state change.

local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local Geometry = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local IconWidget = require("ui/widget/iconwidget")
local TextWidget = require("ui/widget/textwidget")
local ButtonWidget = require("ui/widget/button")
local I18n = require("mahjongi18n")
local t = I18n.t
local MahjongUI = require("mahjongui")

local BAR_BG = Blitbuffer.COLOR_WHITE
local QUIT_BG = Blitbuffer.COLOR_LIGHT_GRAY
local CHIP_BG = Blitbuffer.COLOR_WHITE
local CHIP_BORDER = Blitbuffer.COLOR_DARK_GRAY

local function isAndroidDevice()
    return type(Device.isAndroid) == "function" and Device:isAndroid()
end

local HudBar = FrameContainer:extend{
    name = "hudbar",
    full_width = Screen:getWidth(),
    title = nil,
    left_icons = nil, -- list of { icon=, size_ratio=, callback= } left buttons (US-13)
    left_icon = nil,  -- legacy single left button (kept for compat)
    left_icon_size_ratio = 0.9,
    left_icon_tap_callback = nil,
    right_icon = nil,
    right_icon_size_ratio = 0.9,
    right_icon_tap_callback = nil,
    HUD_H = 0,
    bordersize = 0,
    stats = { pairs = 0, free = 0, score = 0 },
    _value_widgets = nil, -- { pairs=, free=, score= } value TextWidgets
    _chip_layouts = nil,  -- the three chips' layouts (size caches)
    _left_buttons = nil,  -- the left ButtonWidgets (settings gear, stats, ...)
    _bar_layout = nil,    -- the outer HorizontalGroup holding left buttons + left_vertical_group + quit_button
}

-- One stat chip: rounded pill, icon (left), bold value (center),
-- label text (right). Returns the chip widget, its layout (for size
-- invalidation), the value TextWidget, the value sizing spec, and the label
-- TextWidget. Values are re-fitted when live stats change; a three-digit probe
-- is not enough for a score that grows to four digits.
local function buildChip(icon, label, chip_w, chip_h, compact)
    local border = math.max(1, Screen:scaleBySize(1))
    local pad = math.max(1, math.min(Screen:scaleBySize(compact and 4 or 6),
        math.floor(chip_h * 0.16)))
    local inner_h = math.max(1, chip_h - 2 * pad - 2 * border)
    local icon_size = math.max(1, math.min(Screen:scaleBySize(compact and 16 or 20), inner_h))
    local gap = math.max(1, math.min(Screen:scaleBySize(4), math.floor(chip_w * 0.04)))
    local inner_w = math.max(1, chip_w - 2 * pad - 2 * border)
    local label_max_w = compact and 0 or math.max(1, math.floor(inner_w * 0.40))
    local value_max_w = math.max(1, inner_w - icon_size - gap
        - (compact and 0 or gap) - label_max_w)
    local android = isAndroidDevice()
    -- Keep high-DPI devices from turning short chip values into oversized
    -- glyphs. The live-value fitting below then reduces this further when a
    -- score or counter needs more horizontal room.
    local value_preferred = math.min(Screen:scaleBySize(compact and 14 or 16), 24)
    -- The fallback is deliberately small: values have ellipsis disabled, so
    -- an unusually large score must shrink rather than leave digits outside
    -- the chip.
    local value_minimum = 1
    local label_preferred = math.min(Screen:scaleBySize(10), 18)
    local label_minimum = 1
    if android then
        -- Android can report a large DPI multiplier without giving the HUD
        -- proportionally more room. Keep the text readable inside the chip;
        -- the HorizontalGroup will then center it beside the icon.
        value_preferred = math.min(value_preferred, math.floor(inner_h * 0.48))
        value_minimum = math.min(value_minimum, math.floor(inner_h * 0.35))
        label_preferred = math.min(label_preferred, math.floor(inner_h * 0.32))
        label_minimum = math.min(label_minimum, math.floor(inner_h * 0.24))
    end
    local value_face = MahjongUI.fitTextFace(
        "0000", "smallinfofontbold", value_preferred,
        value_minimum, value_max_w, inner_h)
    local value = TextWidget:new{
        text = "0",
        bold = true,
        padding = 0,
        face = value_face,
        max_width = value_max_w,
        truncate_with_ellipsis = false,
    }
    local label_widget = nil
    local content_children = {
        IconWidget:new{ icon = icon, width = icon_size, height = icon_size },
        HorizontalSpan:new{ width = gap },
        value,
    }
    if not compact then
        local label_face = MahjongUI.fitTextFace(
            label, "smallinfofont", label_preferred, label_minimum,
            label_max_w, inner_h)
        content_children[#content_children + 1] = HorizontalSpan:new{ width = gap }
        label_widget = TextWidget:new{
            text = label,
            padding = 0,
            face = label_face,
            max_width = label_max_w,
            truncate_with_ellipsis = false,
            fgcolor = Blitbuffer.COLOR_BLACK, -- high contrast
        }
        content_children[#content_children + 1] = label_widget
    end
    local content = HorizontalGroup:new(content_children)

    local chip = FrameContainer:new{
        content,
        bordersize = border,
        color = CHIP_BORDER,
        background = CHIP_BG,
        radius = Screen:scaleBySize(8),
        padding = pad,
        _padding_left = pad,
        _padding_right = pad,
        _padding_top = pad,
        _padding_bottom = pad,
    }
    chip.getSize = function()
        return Geometry:new{ w = chip_w, h = chip_h }
    end
    return chip, content, value, {
        face_name = "smallinfofontbold",
        preferred_size = value_preferred,
        minimum_size = value_minimum,
        max_width = value_max_w,
        max_height = inner_h,
    }, label_widget
end

function HudBar:init()
    MahjongUI.refreshDimensions(self)
    self._padding_left = 0
    self._padding_right = 0
    self._padding_top = 0
    self._padding_bottom = 0
    self.bordersize = 0

    local compact = MahjongUI.isNarrow(self.full_width)
    -- Left buttons: the new `left_icons` list (one button per entry) or the
    -- legacy single `left_icon` fields (US-13). Each is a slim rounded-border
    -- button pinned to the far left, so a row of them reads as controls
    -- distinct from the quit X. The buttons are a touch narrower than tall
    -- (0.6 x HUD_H) so a pair of them (settings + stats) sits close together
    -- without squeezing the stat chips in the middle.
    local left_specs = {}
    if self.left_icons and #self.left_icons > 0 then
        left_specs = self.left_icons
    elseif self.left_icon and self.left_icon_tap_callback then
        left_specs = {
            { icon = self.left_icon, size_ratio = 0.45, callback = self.left_icon_tap_callback },
        }
    end
    -- Reserve a compact two-row status bar. The previous implementation let
    -- device font metrics determine both rows, which made the HUD consume a
    -- large fraction of tall Kindle screens.
    local title_row_h = math.max(1, math.min(
        Screen:scaleBySize(compact and 28 or 34),
        math.floor(self.full_height * 0.05)))
    local chip_h = math.max(1, math.min(
        Screen:scaleBySize(compact and 30 or 38),
        math.floor(self.full_height * 0.055)))
    local row_gap = math.max(1, math.min(
        Screen:scaleBySize(compact and 4 or 6),
        math.floor(self.full_height * 0.012)))
    local bar_edge_pad = math.max(1, math.min(
        Screen:scaleBySize(compact and 3 or 5),
        math.floor(self.full_height * 0.01)))
    self.HUD_H = title_row_h + chip_h + row_gap + 2 * bar_edge_pad

    -- Square quit button width = height = HUD_H
    local quit_w = self.right_icon and self.right_icon_tap_callback and self.HUD_H or 0
    local left_btn_w = math.max(1, math.floor(self.HUD_H * 0.6))
    local left_w = #left_specs * left_btn_w
    local content_w = self.full_width - quit_w - left_w

    -- Title text (row 1, center). Keep it centered in the full screen while
    -- preventing it from expanding the intrinsic width of the bar.
    local title_max_w = math.max(1, math.min(
        self.full_width - 2 * left_w,
        content_w - Screen:scaleBySize(8)))
    local title_face = MahjongUI.fitTextFace(
        self.title or "", "tfont", Screen:scaleBySize(compact and 16 or 18),
        Screen:scaleBySize(10), title_max_w, title_row_h)
    local title_widget = TextWidget:new{
        text = self.title or "",
        padding = 0,
        face = title_face,
        max_width = title_max_w,
        truncate_with_ellipsis = true,
    }

    local chip_gap = math.max(1, math.min(Screen:scaleBySize(8), math.floor(self.full_width * 0.02)))
    local edge_pad = math.max(1, math.min(Screen:scaleBySize(8), math.floor(self.full_width * 0.02)))
    local right_pad = edge_pad
    local available_for_chips = content_w - edge_pad - right_pad - (2 * chip_gap)
    local chip_w = math.max(1, math.floor(available_for_chips / 3))

    -- Build chips with precise dimensions and text that fits those dimensions.
    local chip_pairs, lay_pairs, val_pairs, spec_pairs, label_pairs = buildChip(
        "mahjong/hud_pairs", t("hud.pairs"), chip_w, chip_h, compact)
    local chip_free, lay_free, val_free, spec_free, label_free = buildChip(
        "mahjong/lightbulb", t("hud.free"), chip_w, chip_h, compact)
    local chip_score, lay_score, val_score, spec_score, label_score = buildChip(
        "mahjong/hud_score", t("hud.score"), chip_w, chip_h, compact)
    self._value_widgets = { pairs = val_pairs, free = val_free, score = val_score }
    self._value_specs = { pairs = spec_pairs, free = spec_free, score = spec_score }
    self._label_widgets = { pairs = label_pairs, free = label_free, score = label_score }
    self._chip_layouts = { lay_pairs, lay_free, lay_score }

    -- Quit button: square (HUD_H x HUD_H), grey background, well-proportioned X icon
    local quit_button = nil
    if self.right_icon and self.right_icon_tap_callback then
        local x_icon = math.floor(self.HUD_H * 0.45)
        quit_button = ButtonWidget:new{
            icon = self.right_icon,
            width = self.HUD_H,
            height = self.HUD_H,
            icon_width = x_icon,
            icon_height = x_icon,
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = QUIT_BG,
            callback = self.right_icon_tap_callback,
        }
    end

    -- Left buttons (gear / stats / ...): one left_btn_w x HUD_H button per
    -- entry, icon sized 45% of the bar height (matches the pre-US-13 gear).
    local left_buttons = {}
    for _, spec in ipairs(left_specs) do
        local btn_icon = math.floor(self.HUD_H * (spec.size_ratio or 0.45))
        left_buttons[#left_buttons + 1] = ButtonWidget:new{
            icon = spec.icon,
            width = left_btn_w,
            height = self.HUD_H,
            icon_width = btn_icon,
            icon_height = btn_icon,
            bordersize = Screen:scaleBySize(1),
            radius = Screen:scaleBySize(4),
            padding = 0,
            margin = 0,
            background = CHIP_BG,
            color = CHIP_BORDER,
            callback = spec.callback,
        }
    end
    self._left_buttons = left_buttons

    -- Row 1: Center the title in the full bar, not merely in the space
    -- between the left controls and the quit button. With settings + stats on
    -- the left, centering within content_w visibly shifts the title right.
    local title_w = math.min(title_widget:getSize().w, title_max_w)
    local title_left = math.floor((self.full_width - title_w) / 2)
    local title_space = math.max(0, title_left - left_w)
    local title_right_space = math.max(0, content_w - title_w - title_space)
    local row1 = HorizontalGroup:new{
        HorizontalSpan:new{ width = title_space },
        title_widget,
        HorizontalSpan:new{ width = title_right_space },
    }

    -- Row 2: Chips with edge gaps and ~8px spacers between them
    local row2 = HorizontalGroup:new{
        HorizontalSpan:new{ width = edge_pad },
        chip_pairs,
        HorizontalSpan:new{ width = chip_gap },
        chip_free,
        HorizontalSpan:new{ width = chip_gap },
        chip_score,
        HorizontalSpan:new{ width = right_pad },
    }

    -- Left vertical group holding row1 and row2
    local left_vertical_group = VerticalGroup:new{
        VerticalSpan:new{ height = bar_edge_pad },
        row1,
        VerticalSpan:new{ height = row_gap },
        row2,
        VerticalSpan:new{ height = bar_edge_pad },
    }

    -- Full bar: HorizontalGroup holding left buttons + left_vertical_group +
    -- quit_button (left controls pinned left, quit pinned right).
    local bar_children = {}
    for _, b in ipairs(left_buttons) do
        bar_children[#bar_children + 1] = b
    end
    bar_children[#bar_children + 1] = left_vertical_group
    if quit_button then
        bar_children[#bar_children + 1] = quit_button
    end
    self._bar_layout = HorizontalGroup:new(bar_children)
    self[1] = self._bar_layout
    self.width = self.full_width
    self.height = self.HUD_H
    self.background = BAR_BG
end

function HudBar:setStats(pairs, free, score)
    self.stats = { pairs = pairs, free = free, score = score }
    if not self._value_widgets then return end
    local function updateValue(key, value)
        local widget = self._value_widgets[key]
        local spec = self._value_specs[key]
        local text = tostring(value)
        widget.face = MahjongUI.fitTextFace(text, spec.face_name,
            spec.preferred_size, spec.minimum_size, spec.max_width, spec.max_height)
        widget:setText(text)
        -- Changing the face is not covered by setText when the value is
        -- unchanged; explicitly invalidate the cached TextWidget metrics.
        if widget.free then widget:free() end
    end
    updateValue("pairs", pairs)
    updateValue("free", free)
    updateValue("score", score)
    for _, layout in ipairs(self._chip_layouts or {}) do
        if layout.resetLayout then layout:resetLayout() end
    end
    if self._bar_layout and self._bar_layout.resetLayout then
        self._bar_layout:resetLayout()
    end
end

function HudBar:getSize()
    return Geometry:new{ w = self.full_width, h = self.HUD_H }
end

return HudBar
