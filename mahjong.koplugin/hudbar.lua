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

local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
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

local BAR_BG = Blitbuffer.COLOR_WHITE
local QUIT_BG = Blitbuffer.COLOR_LIGHT_GRAY
local CHIP_BG = Blitbuffer.COLOR_WHITE
local CHIP_BORDER = Blitbuffer.COLOR_DARK_GRAY

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
-- invalidation) and the value TextWidget (for setStats).
local function buildChip(icon, label, chip_w, chip_h)
    local pad = Screen:scaleBySize(6)
    local icon_size = Screen:scaleBySize(20)
    local value = TextWidget:new{
        text = "0",
        bold = true,
        padding = 0,
        face = Font:getFace("smallinfofontbold", Screen:scaleBySize(16)),
    }
    local label_widget = TextWidget:new{
        text = label,
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(10)),
        fgcolor = Blitbuffer.COLOR_BLACK, -- high contrast
    }

    -- Chip content: icon | spacer | value | spacer | label
    local content = HorizontalGroup:new{
        IconWidget:new{ icon = icon, width = icon_size, height = icon_size },
        HorizontalSpan:new{ width = Screen:scaleBySize(4) },
        value,
        HorizontalSpan:new{ width = Screen:scaleBySize(4) },
        label_widget,
    }

    local chip = FrameContainer:new{
        content,
        bordersize = Screen:scaleBySize(1),
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
    return chip, content, value
end

function HudBar:init()
    self._padding_left = 0
    self._padding_right = 0
    self._padding_top = 0
    self._padding_bottom = 0
    self.bordersize = 0

    local chip_gap = Screen:scaleBySize(8)
    local edge_pad = Screen:scaleBySize(8)
    local right_pad = Screen:scaleBySize(8)

    -- Title text (row 1, center)
    local title_widget = TextWidget:new{
        text = self.title or "",
        padding = 0,
        face = Font:getFace("tfont", Screen:scaleBySize(18)),
    }
    local h1 = title_widget:getSize().h

    -- Dummy chip to measure natural chip height (initial estimate)
    local dummy_chip = select(1, buildChip("mahjong/hud_pairs", t("hud.pairs"), 100, 40))
    local h2 = dummy_chip:getSize().h
    self.HUD_H = h1 + h2 + Screen:scaleBySize(12)

    -- Square quit button width = height = HUD_H
    local quit_w = self.right_icon and self.right_icon_tap_callback and self.HUD_H or 0

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
    local left_btn_w = math.floor(self.HUD_H * 0.6)
    local left_w = #left_specs * left_btn_w
    local content_w = self.full_width - quit_w - left_w

    local available_for_chips = content_w - edge_pad - right_pad - (2 * chip_gap)
    local chip_w = math.floor(available_for_chips / 3)

    -- Build chips with precise chip_w and h2
    local chip_pairs, lay_pairs, val_pairs = buildChip("mahjong/hud_pairs", t("hud.pairs"), chip_w, h2)
    local chip_free, lay_free, val_free = buildChip("mahjong/lightbulb", t("hud.free"), chip_w, h2)
    local chip_score, lay_score, val_score = buildChip("mahjong/hud_score", t("hud.score"), chip_w, h2)
    self._value_widgets = { pairs = val_pairs, free = val_free, score = val_score }
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
    local title_w = title_widget:getSize().w
    local title_left = math.floor((self.full_width - title_w) / 2)
    local title_space = math.max(0, title_left - left_w)
    local title_right_space = math.max(0, content_w - title_w - title_space)
    local row1 = HorizontalGroup:new{
        HorizontalSpan:new{ width = title_space },
        title_widget,
        HorizontalSpan:new{ width = title_right_space },
    }
    row1.width = content_w

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
    row2.width = content_w

    -- Left vertical group holding row1 and row2
    local left_vertical_group = VerticalGroup:new{
        VerticalSpan:new{ height = Screen:scaleBySize(4) },
        row1,
        VerticalSpan:new{ height = Screen:scaleBySize(4) },
        row2,
        VerticalSpan:new{ height = Screen:scaleBySize(4) },
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
    self._value_widgets.pairs:setText(tostring(pairs))
    self._value_widgets.free:setText(tostring(free))
    self._value_widgets.score:setText(tostring(score))
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
