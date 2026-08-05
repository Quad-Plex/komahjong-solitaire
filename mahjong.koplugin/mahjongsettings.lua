-- Settings dialog (US-10) — floating window.
--
-- A modal centered panel (the ConfirmBox pattern) instead of a full-screen
-- page: a transparent full-screen InputContainer whose single child is a
-- CenterContainer holding a white rounded FrameContainer. The game stays
-- visible around the panel. A tap outside the panel (or the title-row close X)
-- closes it and discards the collected changes; Save / Reset act on `changes`.
-- There is no Cancel button — leaving without Save already cancels.
--
-- Row buttons: tapping a toggle/cycle button updates `changes`, re-renders
-- the button label (rebuilding the label widget so the full truncation/wrap
-- logic of KOReader's Button runs again — see setButtonText below), and dirties
-- THIS window-level widget so UIManager actually repaints it. setDirty on a
-- subwidget would never flag a window (AGENTS.md pitfall), which is why the
-- old full-screen dialog only showed the new value after Save + reopen.
--
-- Layout (settings polish):
--   * Every toggle button is sized to fit the WIDEST value it can show on a
--     single line (measured at init with the same font the Button uses), so no
--     value ever gets truncated / wrapped / cut off, and all the buttons line
--     up in one column.
--   * The row labels are right-aligned to the widest label, so the button
--     column starts at the same x on every row instead of wandering with the
--     label lengths.
--   * The Timer interval button is greyed out and non-interactive while Timer
--     update is "On interaction" (an interval only matters in Periodic mode).
--
-- The widget only uses the plugin's existing primitives plus the standard
-- dialog containers (CenterContainer, GestureRange), so the headless suite can
-- drive it with the existing stubs.

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
local _ = require("gettext")

local DEFAULTS = {
    hints = true,
    confirm_new_game = true,
    score_method = "chain",
    layout = "turtle",
    timer_update = "interval",
    timer_interval = 5,
}
local SCORE_OPTIONS = { "chain", "basic" }
local TIMER_MODES = { "interval", "move" }
local TIMER_INTERVALS = { 1, 2, 5, 10, 15, 30, 60 }

local SettingsWidget = InputContainer:extend{
    name = "mahjongsettings",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,
    onApply = nil,
    onCancel = nil,   -- optional hook so the owner can react to a discard
    changes = nil,    -- current (unsaved) values
    _rows = nil,      -- { hints=btn, confirm_new_game=btn, score_method=btn,
                      --   timer_update=btn, timer_interval=btn }
    _panel_geom = nil, -- absolute screen rect of the floating panel (tap-outside test)
}

-- A control button: rounded rect, `w` wide, `h` tall. `refresh` re-renders the
-- label when the value changes. The text font is set explicitly (matching the
-- measurement in init) so the value always renders in the same face/size.
local function makeButton(text, w, h, refresh)
    local btn = ButtonWidget:new{
        text = text,
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = true,
        width = w,
        height = h,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = Screen:scaleBySize(6),
        callback = nil,
    }
    btn.refresh = refresh
    return btn
end

-- Re-render a row button's label.
--
-- The label is REBUILT from scratch (free the old TextWidget, then re-run
-- Button:init) instead of going through Button:setText. KOReader's
-- Button:setText has a "fast path" that shoves the new text into the button's
-- EXISTING label widget; when that label is a single-line TextWidget (e.g.
-- after showing the short "Basic") and the new value is long ("Chain (+5
-- bonus)"), the fast path renders the long text as one truncated line, cut off
-- at the end of the button — the score-toggle bug. Rebuilding always runs the
-- full truncation/wrap logic, so the value renders exactly like it did the
-- first time the button was built. The headless mock has neither setText nor
-- init, so the fallback just stores the text field (the suite asserts on
-- `.text`).
local function setButtonText(btn, text)
    if not btn then return end
    btn.text = text
    if btn.init then
        if btn.label_widget then
            if btn.label_widget.free then btn.label_widget:free() end
            btn.label_widget = nil
        end
        btn:init()
    end
end

function SettingsWidget:init()
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local defaults = self.settings_defaults or DEFAULTS
    local getv = function(key, default)
        if self.parent and self.parent.getSetting then
            return self.parent:getSetting(key, default)
        end
        return default
    end
    self.changes = {
        hints = getv("hints", defaults.hints),
        confirm_new_game = getv("confirm_new_game", defaults.confirm_new_game),
        score_method = getv("score_method", defaults.score_method),
        layout = getv("layout", defaults.layout),
        timer_update = getv("timer_update", defaults.timer_update),
        timer_interval = getv("timer_interval", defaults.timer_interval),
    }
    self._rows = {}

    local label_gap = Screen:scaleBySize(12) -- label -> control gap
    local label_face = Font:getFace("smallinfofont", Screen:scaleBySize(16))
    local label_color = Blitbuffer.COLOR_DARK_GRAY

    -- Value texts ----------------------------------------------------------
    local function scoreText(method)
        return method == "basic" and _("Basic") or _("Chain (+5 bonus)")
    end
    local function timerModeText(mode)
        return mode == "move" and _("On interaction") or _("Periodic")
    end
    local function intervalText(sec)
        return string.format(_("%d s"), sec)
    end

    -- Measure a string in the face it will be rendered with. The probes are
    -- throwaway TextWidgets (the same pattern main.lua uses to probe the
    -- flash band / timer slot sizes).
    local function measureText(text, face, bold)
        local probe = TextWidget:new{ text = text, padding = 0, face = face, bold = bold }
        local w = probe:getSize().w
        probe:free()
        return w
    end

    -- Toggle-button width: every value button is sized to fit the widest
    -- value on a SINGLE line, so nothing wraps, truncates, or gets cut off
    -- when a value is changed later. Values are measured in the exact font the
    -- Button renders them with (cfont 20 bold, see makeButton).
    local btn_face = Font:getFace("cfont", 20)
    local widest_value = 0
    local function considerValue(v)
        local w = measureText(v, btn_face, true)
        if w > widest_value then widest_value = w end
    end
    considerValue(_("On"))
    considerValue(_("Off"))
    considerValue(_("Basic"))
    considerValue(scoreText("chain"))
    considerValue(timerModeText("move"))
    considerValue(timerModeText("interval"))
    for _, sec in ipairs(TIMER_INTERVALS) do
        considerValue(intervalText(sec))
    end
    -- The button's inner content width is width - 2*padding - 2*bordersize;
    -- add that plus a little breathing room so nothing sits flush.
    local toggle_w = widest_value + 2 * Screen:scaleBySize(6) + 2 * Screen:scaleBySize(1)
                    + Screen:scaleBySize(12)

    -- Right-align the row labels to the widest label so every button column
    -- starts at the same x (the label lengths differ, which previously left
    -- the buttons staggered). (The Layout row was dropped from the dialog;
    -- the layout setting itself is still round-tripped via `changes`.)
    local row_labels = { _("Hints"), _("Confirm new game"), _("Score"),
                         _("Timer update"), _("Timer interval") }
    local max_label_w = 0
    for _, l in ipairs(row_labels) do
        local w = measureText(l, label_face, false)
        if w > max_label_w then max_label_w = w end
    end
    local function row(label, control)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = max_label_w - measureText(label, label_face, false) },
            TextWidget:new{ text = label, padding = 0, face = label_face, fgcolor = label_color },
            HorizontalSpan:new{ width = label_gap },
            control,
        }
    end

    -- Hint button --------------------------------------------------------
    local hints_btn
    hints_btn = makeButton(
        self.changes.hints and _("On") or _("Off"), toggle_w, Screen:scaleBySize(32),
        function() return self.changes.hints and _("On") or _("Off") end)
    hints_btn.callback = function()
        self.changes.hints = not (self.changes.hints or false)
        setButtonText(hints_btn, hints_btn.refresh())
        UIManager:setDirty(self, "ui")
    end
    self._rows.hints = hints_btn

    -- New-game confirmation button ---------------------------------------
    local confirm_btn
    confirm_btn = makeButton(
        self.changes.confirm_new_game and _("On") or _("Off"), toggle_w, Screen:scaleBySize(32),
        function() return self.changes.confirm_new_game and _("On") or _("Off") end)
    confirm_btn.callback = function()
        self.changes.confirm_new_game = not (self.changes.confirm_new_game or false)
        setButtonText(confirm_btn, confirm_btn.refresh())
        UIManager:setDirty(self, "ui")
    end
    self._rows.confirm_new_game = confirm_btn

    -- Score-method button (cycles Chain -> Basic) -------------------------
    local score_btn
    score_btn = makeButton(
        scoreText(self.changes.score_method), toggle_w, Screen:scaleBySize(32),
        function() return scoreText(self.changes.score_method) end)
    score_btn.callback = function()
        local idx = 1
        for i, m in ipairs(SCORE_OPTIONS) do
            if m == self.changes.score_method then idx = i break end
        end
        idx = idx % #SCORE_OPTIONS + 1
        self.changes.score_method = SCORE_OPTIONS[idx]
        setButtonText(score_btn, score_btn.refresh())
        UIManager:setDirty(self, "ui")
    end
    self._rows.score_method = score_btn

    -- Timer-update mode (cycles Periodic -> On interaction) ----------------
    -- The interval button is created just below, but its enabled state is
    -- toggled from this callback, so forward-declare the locals first.
    local timer_interval_btn
    local setIntervalEnabled
    local timer_mode_btn
    timer_mode_btn = makeButton(
        timerModeText(self.changes.timer_update), toggle_w, Screen:scaleBySize(32),
        function() return timerModeText(self.changes.timer_update) end)
    timer_mode_btn.callback = function()
        local idx = 1
        for i, m in ipairs(TIMER_MODES) do
            if m == self.changes.timer_update then idx = i break end
        end
        idx = idx % #TIMER_MODES + 1
        self.changes.timer_update = TIMER_MODES[idx]
        setButtonText(timer_mode_btn, timer_mode_btn.refresh())
        setIntervalEnabled()
        UIManager:setDirty(self, "ui")
    end
    self._rows.timer_update = timer_mode_btn

    -- Timer interval (cycles through the offered values) -------------------
    -- While Timer update is "On interaction" ("move" mode) an interval is
    -- meaningless (the mm:ss only repaints on board interaction), so the
    -- button is greyed out and its taps are ignored.
    timer_interval_btn = makeButton(
        intervalText(self.changes.timer_interval), toggle_w, Screen:scaleBySize(32),
        function() return intervalText(self.changes.timer_interval) end)
    setIntervalEnabled = function()
        local on = self.changes.timer_update ~= "move"
        if on then
            if timer_interval_btn.enable then timer_interval_btn:enable() else timer_interval_btn.enabled = true end
        else
            if timer_interval_btn.disable then timer_interval_btn:disable() else timer_interval_btn.enabled = false end
        end
    end
    timer_interval_btn.callback = function()
        if not timer_interval_btn.enabled then return end
        local idx = 1
        for i, v in ipairs(TIMER_INTERVALS) do
            if v == self.changes.timer_interval then idx = i break end
        end
        idx = idx % #TIMER_INTERVALS + 1
        self.changes.timer_interval = TIMER_INTERVALS[idx]
        setButtonText(timer_interval_btn, timer_interval_btn.refresh())
        UIManager:setDirty(self, "ui")
    end
    self._rows.timer_interval = timer_interval_btn
    self._set_interval_enabled = setIntervalEnabled -- reused by resetToDefaults
    setIntervalEnabled() -- start greyed if a saved "move" mode is active

    -- Bottom buttons: Reset / Save ------------------------------------------
    -- (No Cancel button: a tap outside the panel or the title-row close X
    -- already discards the collected changes, so Cancel would be redundant.)
    local bottom_w = Screen:scaleBySize(150)
    local reset_btn = makeButton(_("Reset"), bottom_w, Screen:scaleBySize(32))
    reset_btn.callback = function() self:resetToDefaults() end
    local save_btn = makeButton(_("Save"), bottom_w, Screen:scaleBySize(32))
    save_btn.callback = function() self:save() end

    -- Title row: "Settings" centered, with a close X pinned at the panel's
    -- top-right corner (same grey-square style as the HUD's quit X). Tapping
    -- it discards the changes and closes.
    --
    -- The row spans the FULL inner width of the panel, not just the value
    -- column: the panel is as wide as its widest child (the Reset/Save row),
    -- so a title row sized to the value column would be centered with
    -- empty space to the right of the X. Sizing it to the widest child pins
    -- the X flush against the panel's inner right edge.
    local gap = Screen:scaleBySize(14)
    local content_w = max_label_w + label_gap + toggle_w
    local title_row_w = math.max(content_w, 2 * bottom_w + gap)
    local title_widget = TextWidget:new{
        text = _("Settings"),
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
        callback = function() self:cancel() end,
    }
    local title_space = math.max(0, math.floor((title_row_w - title_w - close_size) / 2))
    local title_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = title_space },
        title_widget,
        HorizontalSpan:new{ width = math.max(0, title_row_w - title_w - close_size - title_space) },
        self._close_btn,
    }

    -- Floating panel: a white rounded card centered over the game. The outer
    -- widget stays transparent, so the board shows through around the card.
    local top_pad = Screen:scaleBySize(40)
    local panel = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(10),
        padding = Screen:scaleBySize(24),
        VerticalGroup:new{
            align = "center",
            title_row,
            VerticalSpan:new{ width = gap },
            row(_("Hints"), hints_btn),
            VerticalSpan:new{ width = gap },
            row(_("Confirm new game"), confirm_btn),
            VerticalSpan:new{ width = gap },
            row(_("Score"), score_btn),
            VerticalSpan:new{ width = gap },
            row(_("Timer update"), timer_mode_btn),
            VerticalSpan:new{ width = gap },
            row(_("Timer interval"), timer_interval_btn),
            VerticalSpan:new{ width = gap * 2 },
            HorizontalGroup:new{
                reset_btn,
                HorizontalSpan:new{ width = gap },
                save_btn,
            },
            VerticalSpan:new{ width = top_pad },
        },
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

    -- Full-screen tap gesture: a tap that misses the panel discards the
    -- collected changes and closes. (The buttons inside the panel match their
    -- own more-specific gesture and consume the tap before this ever fires —
    -- the same pattern ConfirmBox uses.)
    self.ges_events = {
        TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function SettingsWidget:show()
    UIManager:show(self)
end

-- The panel must be refreshed to the screen when the dialog is shown. show()
-- calls setDirty(self, nil), which flags us for repaint but enqueues NO
-- refresh; if the settings gear's own tap left a small "fast" refresh in the
-- queue (flash_ui), the next _repaint paints the panel into the framebuffer
-- but skips adding a full-screen refresh, so the center of the screen never
-- updates and the dialog looks invisible until some interaction forces a
-- refresh. Re-dirty with a refresh function for the panel region (the same
-- onShow trick ConfirmBox uses).
function SettingsWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self._panel_geom
    end)
    return true
end

-- Writes the changes to the parent's LuaSettings, applies, and closes.
function SettingsWidget:save()
    local p = self.parent
    if p and p.setSetting then
        p:setSetting("hints", self.changes.hints)
        p:setSetting("confirm_new_game", self.changes.confirm_new_game)
        p:setSetting("score_method", self.changes.score_method)
        p:setSetting("layout", self.changes.layout)
        p:setSetting("timer_update", self.changes.timer_update)
        p:setSetting("timer_interval", self.changes.timer_interval)
    end
    if self.onApply then self.onApply(self.changes) end
    UIManager:close(self)
end

-- Discards the changes and closes (a tap outside the panel or the close X).
function SettingsWidget:cancel()
    if self.onCancel then self.onCancel() end
    UIManager:close(self)
end

-- A tap outside the floating panel dismisses the dialog (discarding changes).
-- `ges` is the second argument (the first is the gesture spec's `args`, nil
-- here) — see the Input-handling pitfall in AGENTS.md.
function SettingsWidget:onTapClose(_, ges)
    if ges and ges.pos and ges.pos.notIntersectWith and self._panel_geom then
        if ges.pos:notIntersectWith(self._panel_geom) then
            self:cancel()
        end
    end
    return true
end

-- Resets the (unsaved) changes to the defaults and refreshes the rows.
function SettingsWidget:resetToDefaults()
    local defaults = self.settings_defaults or DEFAULTS
    self.changes.hints = defaults.hints
    self.changes.confirm_new_game = defaults.confirm_new_game
    self.changes.score_method = defaults.score_method
    self.changes.layout = defaults.layout
    self.changes.timer_update = defaults.timer_update
    self.changes.timer_interval = defaults.timer_interval
    setButtonText(self._rows.hints, self._rows.hints.refresh())
    setButtonText(self._rows.confirm_new_game, self._rows.confirm_new_game.refresh())
    setButtonText(self._rows.score_method, self._rows.score_method.refresh())
    setButtonText(self._rows.timer_update, self._rows.timer_update.refresh())
    setButtonText(self._rows.timer_interval, self._rows.timer_interval.refresh())
    if self._set_interval_enabled then self._set_interval_enabled() end
    UIManager:setDirty(self, "ui")
end

return SettingsWidget
