-- Stats screen (US-13) — floating window.
--
-- A modal centered panel in the exact mahjongsettings.lua pattern: a
-- transparent full-screen InputContainer whose single child is a
-- CenterContainer holding a white rounded FrameContainer, so the game stays
-- visible around the card. A tap outside the panel closes it; the close X in
-- the title row does too. Every close runs the owner's onClose hook (which
-- resumes the polling loop that openStats paused, exactly like openSettings).
--
-- Rows are right-aligned labels with the values in a uniform column (the same
-- layout trick the settings dialog uses), listing the lifetime stats from the
-- owner's `stats` record (mahjongstats.lua). A bottom Reset button zeroes the
-- record — but only after a ConfirmBox. All strings are wrapped in _().
--
-- Note: US-12 already took the file name `mahjongstats.lua` for the pure
-- stats module, so this dialog lives in `mahjongstatswidget.lua`.

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
local ConfirmBox = require("ui/widget/confirmbox")
local _ = require("gettext")
local MahjongLogic = require("mahjonglogic")
local MahjongStats = require("mahjongstats")

local StatsWidget = InputContainer:extend{
    name = "mahjongstatswidget",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,      -- the Mahjong instance (reads `stats`, saves after reset)
    onClose = nil,     -- hook so the owner can resume the paused timer loop
    _values = nil,     -- { played=, won=, win_rate=, best_score=, best_time=,
                       --   avg_time=, current_streak=, longest_streak= } value widgets
    _panel_geom = nil, -- absolute screen rect of the floating panel (tap-outside test)
}

-- The stats record to display: the owner's live record (so a Reset that swaps
-- in a fresh defaults() table is seen on the next render).
function StatsWidget:statsRecord()
    local p = self.parent
    if p and p.stats then return p.stats end
    return MahjongStats.defaults()
end

-- Formats the display strings for every row from a stats record.
local function valueStrings(stats)
    local played = stats.games_played or 0
    local won = stats.games_won or 0
    local win_rate = played > 0
            and string.format("%d%%", math.floor(won * 100 / played)) or "—"
    local best_time = stats.best_time and MahjongLogic.formatElapsed(stats.best_time) or "—"
    local avg_time = won > 0
            and MahjongLogic.formatElapsed(math.floor((stats.total_time or 0) / won)) or "—"
    return {
        played = tostring(played),
        won = tostring(won),
        win_rate = win_rate,
        best_score = tostring(stats.best_score or 0),
        best_time = best_time,
        avg_time = avg_time,
        current_streak = tostring(stats.current_streak or 0),
        longest_streak = tostring(stats.longest_streak or 0),
    }
end

-- Re-renders every value widget from the current record (used after Reset).
function StatsWidget:updateValues()
    local vs = valueStrings(self:statsRecord())
    for key, widget in pairs(self._values or {}) do
        widget:setText(vs[key] or "")
        if widget.resetLayout then widget:resetLayout() end
    end
end

function StatsWidget:init()
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local stats = self:statsRecord()
    local vs = valueStrings(stats)

    local label_gap = Screen:scaleBySize(12) -- label -> value gap
    local label_face = Font:getFace("smallinfofont", Screen:scaleBySize(16))
    local label_color = Blitbuffer.COLOR_DARK_GRAY
    local value_face = Font:getFace("cfont", Screen:scaleBySize(18))

    local function measureText(text, face, bold)
        local probe = TextWidget:new{ text = text, padding = 0, face = face, bold = bold }
        local w = probe:getSize().w
        probe:free()
        return w
    end

    local row_specs = {
        { key = "played",         label = _("Games played") },
        { key = "won",            label = _("Games won") },
        { key = "win_rate",       label = _("Win rate") },
        { key = "best_score",     label = _("Best score") },
        { key = "best_time",      label = _("Best time") },
        { key = "avg_time",       label = _("Average time per win") },
        { key = "current_streak", label = _("Current streak") },
        { key = "longest_streak", label = _("Longest streak") },
    }

    -- Right-align the labels to the widest one so the value column starts at
    -- the same x on every row (the settings dialog's layout trick).
    local max_label_w = 0
    for _, r in ipairs(row_specs) do
        local w = measureText(r.label, label_face, false)
        if w > max_label_w then max_label_w = w end
    end
    -- The value column width (so the panel is wide enough for the widest value).
    local max_value_w = 0
    for _, r in ipairs(row_specs) do
        local w = measureText(vs[r.key], value_face, true)
        if w > max_value_w then max_value_w = w end
    end

    self._values = {}
    local rows = {}
    for _, r in ipairs(row_specs) do
        local value_widget = TextWidget:new{
            text = vs[r.key],
            padding = 0,
            bold = true,
            face = value_face,
        }
        self._values[r.key] = value_widget
        rows[#rows + 1] = HorizontalGroup:new{
            HorizontalSpan:new{ width = max_label_w - measureText(r.label, label_face, false) },
            TextWidget:new{ text = r.label, padding = 0, face = label_face, fgcolor = label_color },
            HorizontalSpan:new{ width = label_gap },
            value_widget,
        }
    end

    -- Reset button (bottom): clears the record back to defaults, after a
    -- ConfirmBox so an accidental tap cannot wipe the lifetime stats.
    local reset_w = Screen:scaleBySize(160)
    local reset_btn = ButtonWidget:new{
        text = _("Reset"),
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = true,
        width = reset_w,
        height = Screen:scaleBySize(32),
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = Screen:scaleBySize(6),
        callback = function() self:resetStats() end,
    }
    self._reset_btn = reset_btn

    local gap = Screen:scaleBySize(14)
    local content_w = max_label_w + label_gap + max_value_w
    local panel_content_w = math.max(content_w, reset_w)
    local pad_side = math.max(0, math.floor((panel_content_w - reset_w) / 2))
    local reset_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = pad_side },
        reset_btn,
        HorizontalSpan:new{ width = math.max(0, panel_content_w - reset_w - pad_side) },
    }

    -- Title row: "Stats" centered, with a close X pinned at the panel's
    -- top-right corner (same grey-square style as the HUD's quit X). Tapping
    -- it closes the card (and runs onClose).
    local title_widget = TextWidget:new{
        text = _("Stats"),
        padding = 0,
        face = Font:getFace("tfont", Screen:scaleBySize(20)),
    }
    local title_w = title_widget:getSize().w
    local close_size = title_widget:getSize().h + Screen:scaleBySize(8)
    self._close_btn = ButtonWidget:new{
        icon = "mahjong/close",
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
    local title_space = math.max(0, math.floor((panel_content_w - title_w - close_size) / 2))
    local title_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = title_space },
        title_widget,
        HorizontalSpan:new{ width = math.max(0, panel_content_w - title_w - close_size - title_space) },
        self._close_btn,
    }

    -- Floating panel: a white rounded card centered over the game. The outer
    -- widget stays transparent, so the board shows through around the card.
    local top_pad = Screen:scaleBySize(40)
    local vchildren = {
        title_row,
        VerticalSpan:new{ width = gap },
    }
    for i, row in ipairs(rows) do
        vchildren[#vchildren + 1] = row
        if i < #rows then
            vchildren[#vchildren + 1] = VerticalSpan:new{ width = gap }
        end
    end
    vchildren[#vchildren + 1] = VerticalSpan:new{ width = gap * 2 }
    vchildren[#vchildren + 1] = reset_row
    vchildren[#vchildren + 1] = VerticalSpan:new{ width = top_pad }
    local panel = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(10),
        padding = Screen:scaleBySize(24),
        VerticalGroup:new(vchildren),
    }

    -- Where the panel sits on screen (CenterContainer centers it in the
    -- full-screen dimen), so a tap outside it can dismiss the dialog.
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

    -- Full-screen tap gesture: a tap that misses the panel closes the card.
    -- (The buttons inside the panel match their own more-specific gesture and
    -- consume the tap before this ever fires — the same pattern ConfirmBox and
    -- the settings dialog use.)
    self.ges_events = {
        TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function StatsWidget:show()
    UIManager:show(self)
end

-- The panel must be refreshed to the screen when the dialog is shown (the same
-- onShow trick the settings dialog and ConfirmBox use): show() flags us for
-- repaint but enqueues no refresh, so without re-dirtying the panel region the
-- card can stay invisible until some interaction forces a refresh.
function StatsWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self._panel_geom
    end)
    return true
end

-- Closes the card (close X or a tap outside the panel), notifying the owner so
-- it can resume the timer loop that openStats paused.
function StatsWidget:closeDialog()
    if self.onClose then self.onClose() end
    UIManager:close(self)
end

-- A tap outside the floating panel dismisses the dialog. `ges` is the second
-- argument (the first is the gesture spec's `args`, nil here) — see the
-- Input-handling pitfall in AGENTS.md.
function StatsWidget:onTapClose(_, ges)
    if ges and ges.pos and ges.pos.notIntersectWith and self._panel_geom then
        if ges.pos:notIntersectWith(self._panel_geom) then
            self:closeDialog()
        end
    end
    return true
end

-- Zeroes the lifetime record back to defaults — after a ConfirmBox.
function StatsWidget:resetStats()
    UIManager:show(ConfirmBox:new{
        text = _("Reset all statistics? This cannot be undone."),
        ok_text = _("Reset"),
        ok_callback = function()
            local p = self.parent
            if p then
                p.stats = MahjongStats.defaults()
                if p.saveStats then p:saveStats() end
            end
            self:updateValues()
            UIManager:setDirty(self, "ui")
        end,
    })
end

return StatsWidget
