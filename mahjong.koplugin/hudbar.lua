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
local _ = require("gettext")

local BAR_BG = Blitbuffer.COLOR_WHITE
local QUIT_BG = Blitbuffer.COLOR_LIGHT_GRAY
local CHIP_BG = Blitbuffer.COLOR_WHITE
local CHIP_BORDER = Blitbuffer.COLOR_DARK_GRAY

local HudBar = FrameContainer:extend{
    name = "hudbar",
    full_width = Screen:getWidth(),
    title = nil,
    left_icon = nil,
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
    _bar_layout = nil,    -- the outer HorizontalGroup holding left_button + left_vertical_group + quit_button
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
    local dummy_chip = select(1, buildChip("mahjong/hud_pairs", "Pairs", 100, 40))
    local h2 = dummy_chip:getSize().h
    self.HUD_H = h1 + h2 + Screen:scaleBySize(12)

    -- Square quit button width = height = HUD_H
    local quit_w = self.right_icon and self.right_icon_tap_callback and self.HUD_H or 0
    local settings_w = self.left_icon and self.left_icon_tap_callback and self.HUD_H or 0
    local content_w = self.full_width - quit_w - settings_w

    local available_for_chips = content_w - edge_pad - right_pad - (2 * chip_gap)
    local chip_w = math.floor(available_for_chips / 3)

    -- Build chips with precise chip_w and h2
    local chip_pairs, lay_pairs, val_pairs = buildChip("mahjong/hud_pairs", _("Pairs"), chip_w, h2)
    local chip_free, lay_free, val_free = buildChip("mahjong/lightbulb", _("Free"), chip_w, h2)
    local chip_score, lay_score, val_score = buildChip("mahjong/hud_score", _("Score"), chip_w, h2)
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

    -- Settings button: square (HUD_H x HUD_H), pinned to the far left, with a
    -- slim rounded border so it reads as a control distinct from the quit X.
    local settings_button = nil
    if self.left_icon and self.left_icon_tap_callback then
        local gear_icon = math.floor(self.HUD_H * 0.45)
        settings_button = ButtonWidget:new{
            icon = self.left_icon,
            width = self.HUD_H,
            height = self.HUD_H,
            icon_width = gear_icon,
            icon_height = gear_icon,
            bordersize = Screen:scaleBySize(1),
            radius = Screen:scaleBySize(4),
            padding = 0,
            margin = 0,
            background = CHIP_BG,
            color = CHIP_BORDER,
            callback = self.left_icon_tap_callback,
        }
    end

    -- Row 1: Centered title in content_w
    local title_w = title_widget:getSize().w
    local title_space = math.max(0, math.floor((content_w - title_w) / 2))
    local row1 = HorizontalGroup:new{
        HorizontalSpan:new{ width = title_space },
        title_widget,
        HorizontalSpan:new{ width = math.max(0, content_w - title_w - title_space) },
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

    -- Full bar: HorizontalGroup holding settings_button + left_vertical_group +
    -- quit_button (settings pinned left, quit pinned right).
    local bar_children = {}
    if settings_button then
        bar_children[#bar_children + 1] = settings_button
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
