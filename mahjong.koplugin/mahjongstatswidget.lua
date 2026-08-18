-- Stats screen (US-13) — floating window, two columns.
--
-- A modal centered panel in the exact mahjongsettings.lua pattern: a
-- transparent full-screen InputContainer whose single child is a
-- CenterContainer holding a white rounded FrameContainer, so the game stays
-- visible around the card. A tap outside the panel closes it; the close X in
-- the title row does too. Every close runs the owner's onClose hook (which
-- resumes the polling loop that openStats paused, exactly like openSettings).
--
-- The card shows TWO side-by-side columns of the lifetime stats from the
-- owner's `stats` record (mahjongstats.lua):
--   * a "Global" column with the all-layouts record (games played, wins, win
    --     rate, best score/time/combo, average time, streaks), and
--   * a "<layout>" column (named after the currently played layout) mirroring
--     the same rows from the per-layout maps — games started on that layout,
    --     wins, win rate, best score/time/combo, average time and streaks.
-- Rows are right-aligned labels with the values in a uniform column (the same
-- layout trick the settings dialog uses). A bottom Reset button zeroes the
-- whole record (both columns) — but only after a ConfirmBox. All strings are
-- wrapped in _().
--
-- Note: US-12 already took the file name `mahjongstats.lua` for the pure
-- stats module, so this dialog lives in `mahjongstatswidget.lua`.

local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
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
local I18n = require("mahjongi18n")
local t = I18n.t
local MahjongLogic = require("mahjonglogic")
local MahjongStats = require("mahjongstats")
local MahjongUI = require("mahjongui")

local StatsWidget = InputContainer:extend{
    name = "mahjongstatswidget",
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    parent = nil,      -- the Mahjong instance (reads `stats`, saves after reset)
    onClose = nil,     -- hook so the owner can resume the paused timer loop
    show_map = true,   -- false = no layout selected (no game behind): the card
                       --   shows only the Global column (opened from the layout
                       --   picker on first launch / the Play-again path)
    _values = nil,     -- value widgets: global rows under their bare keys
    --   (played/won/win_rate/best_score/best_time/best_combo/avg_time/
                       --   current_streak/longest_streak), the <layout> column
                       --   under the same keys prefixed "map_" (map_played, ...)
    _panel_geom = nil, -- absolute screen rect of the floating panel (tap-outside test)
}

-- The stats record to display: the owner's live record (so a Reset that swaps
-- in a fresh defaults() table is seen on the next render).
function StatsWidget:statsRecord()
    local p = self.parent
    if p and p.stats then return p.stats end
    return MahjongStats.defaults()
end

-- The layout the <layout> column describes: the currently played layout
-- (falls back to turtle, so the card renders even if the owner has no board).
function StatsWidget:layoutId()
    local p = self.parent
    if p and type(p.layout) == "string" and p.layout ~= "" then
        return p.layout
    end
    return "turtle"
end

-- Formats the display strings for every row of the global column.
local function valueStrings(stats)
    local played = stats.games_played or 0
    local won = stats.games_won or 0
    local win_rate = played > 0
            and string.format("%d%%", math.floor(won * 100 / played)) or "—"
    local best_time = stats.best_time and MahjongLogic.formatElapsed(stats.best_time) or "—"
    local best_combo = stats.best_combo and stats.best_combo > 0
            and string.format("%d (+%d)", stats.best_combo, stats.best_combo_points or 0) or "—"
    local avg_time = won > 0
            and MahjongLogic.formatElapsed(math.floor((stats.total_time or 0) / won)) or "—"
    local function withLayout(value, layout_id)
        if type(layout_id) == "string" and layout_id ~= "" then
            return value .. " (" .. t("layout." .. layout_id) .. ")"
        end
        return value
    end
    return {
        played = tostring(played),
        won = tostring(won),
        win_rate = win_rate,
        best_score = withLayout(tostring(stats.best_score or 0), stats.best_score_layout),
        best_time = withLayout(best_time, stats.best_time_layout),
        best_combo = withLayout(best_combo, stats.best_combo_layout),
        avg_time = avg_time,
        current_streak = tostring(stats.current_streak or 0),
        longest_streak = tostring(stats.longest_streak or 0),
    }
end

-- Formats the display strings for the <layout> column from the per-layout
-- maps. Missing values render exactly like the global column ("—" for times
-- and the win rate, 0 for counts).
local function layoutValueStrings(stats, layout_id)
    local played = (stats.layout_played and stats.layout_played[layout_id]) or 0
    local won = (stats.layout_wins and stats.layout_wins[layout_id]) or 0
    local win_rate = played > 0
            and string.format("%d%%", math.floor(won * 100 / played)) or "—"
    local best_time = stats.layout_best_times and stats.layout_best_times[layout_id]
            and MahjongLogic.formatElapsed(stats.layout_best_times[layout_id]) or "—"
    local combo = stats.layout_best_combos and stats.layout_best_combos[layout_id]
    local best_combo = combo and string.format("%d (+%d)", combo.chain, combo.points) or "—"
    local avg_time = won > 0
            and MahjongLogic.formatElapsed(math.floor(
                (stats.layout_total_times and stats.layout_total_times[layout_id] or 0) / won)) or "—"
    return {
        played = tostring(played),
        won = tostring(won),
        win_rate = win_rate,
        best_score = tostring(stats.layout_highscores and stats.layout_highscores[layout_id] or 0),
        best_time = best_time,
        best_combo = best_combo,
        avg_time = avg_time,
        current_streak = tostring(stats.layout_current_streaks and stats.layout_current_streaks[layout_id] or 0),
        longest_streak = tostring(stats.layout_longest_streaks and stats.layout_longest_streaks[layout_id] or 0),
    }
end

-- Re-renders every value widget from the current record (used after Reset).
function StatsWidget:updateValues()
    local stats = self:statsRecord()
    local vs = valueStrings(stats)
    local map_vs = layoutValueStrings(stats, self:layoutId())
    for key, widget in pairs(self._values or {}) do
        local text = vs[key]
        if text == nil and key:sub(1, 4) == "map_" then
            text = map_vs[key:sub(5)]
        end
        widget:setText(text or "")
        if widget.resetLayout then widget:resetLayout() end
    end
end

function StatsWidget:init()
    MahjongUI.refreshDimensions(self)
    self.dimen = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true

    local stats = self:statsRecord()
    local layout_id = self:layoutId()
    local show_map = self.show_map ~= false
    local vs = valueStrings(stats)
    local map_vs = layoutValueStrings(stats, layout_id)
    local compact = MahjongUI.isNarrow(self.full_width) or self.full_height < 700

    local label_gap = math.min(Screen:scaleBySize(12),
        math.max(Screen:scaleBySize(4), math.floor(self.full_width * 0.02)))
    -- Keep the dual-column gutter tight. The columns already have their own
    -- midpoint spacing, so a larger responsive gap only wastes card width.
    local col_gap = math.max(1, math.min(Screen:scaleBySize(10), math.floor(self.full_width * 0.02)))
    local label_face = MahjongUI.fitTextFace(
        t("stats.longest_streak"), "smallinfofont", Screen:scaleBySize(compact and 12 or 16),
        Screen:scaleBySize(8), math.max(1, math.floor(self.full_width * 0.28)),
        Screen:scaleBySize(22))
    local label_color = Blitbuffer.COLOR_DARK_GRAY
    local value_face = MahjongUI.fitTextFace(
        "0000 (Confounding Cross)", "cfont", Screen:scaleBySize(compact and 14 or 18),
        Screen:scaleBySize(9), math.max(1, math.floor(self.full_width * 0.42)),
        Screen:scaleBySize(24))

    local function measureText(text, face, bold)
        local probe = TextWidget:new{ text = text, padding = 0, face = face, bold = bold }
        local w = probe:getSize().w
        probe:free()
        return w
    end

    local row_specs = {
        { key = "played",         label = t("stats.games_played") },
        { key = "won",            label = t("stats.games_won") },
        { key = "win_rate",       label = t("stats.win_rate") },
        { key = "best_score",     label = t("stats.best_score") },
        { key = "best_time",      label = t("stats.best_time") },
        { key = "best_combo",     label = t("stats.best_combo") },
        { key = "avg_time",       label = t("stats.average_time") },
        { key = "current_streak", label = t("stats.current_streak") },
        { key = "longest_streak", label = t("stats.longest_streak") },
    }

    -- Each column uses the same divider logic as the win summary: labels end
    -- at one shared x-coordinate and values begin after the gap. Measure the
    -- value side independently, though. Global records often include a layout
    -- suffix and are wider than the local records; equal column widths would
    -- force the divider to the screen midpoint and leave an empty half beside
    -- the local column.
    local max_label_w = 0
    local max_global_value_w = 0
    local max_map_value_w = 0
    for _, r in ipairs(row_specs) do
        local label_w = measureText(r.label, label_face, false)
        if label_w > max_label_w then max_label_w = label_w end
        local w = measureText(vs[r.key], value_face, true)
        if w > max_global_value_w then max_global_value_w = w end
        local mw = measureText(map_vs[r.key], value_face, true)
        if mw > max_map_value_w then max_map_value_w = mw end
    end
    local header_face = MahjongUI.fitTextFace(
        t("stats.global"), "tfont", Screen:scaleBySize(compact and 15 or 18),
        Screen:scaleBySize(10), math.max(1, math.floor(self.full_width * 0.35)),
        Screen:scaleBySize(28))
    local global_header_text = t("stats.global")
    local map_header_text = t("layout." .. layout_id)
    local global_column_w = math.max(max_label_w + label_gap + max_global_value_w,
        measureText(global_header_text, header_face, true))
    local map_column_w = math.max(max_label_w + label_gap + max_map_value_w,
        measureText(map_header_text, header_face, true))
    -- With no layout selected (show_map=false) the card is a single Global
    -- column, so the two-column math collapses to that column's width.
    local content_w = show_map and (global_column_w + col_gap + map_column_w) or global_column_w
    -- This card is content-sized; large responsive padding leaves conspicuous
    -- empty margins beside the columns and pushes the close button outward.
    local panel_padding = math.max(2, math.min(Screen:scaleBySize(10),
        math.floor(math.min(self.full_width, self.full_height) * 0.02)))
    local max_panel_w = math.max(1, self.full_width - 2 * Screen:scaleBySize(8))
    local max_inner_w = math.max(1, max_panel_w - 2 * panel_padding)
    global_column_w = math.min(global_column_w, max_inner_w)
    map_column_w = math.min(map_column_w, max_inner_w)
    local stacked_columns = show_map
        and global_column_w + col_gap + map_column_w > max_inner_w
    local global_value_w = math.max(1, math.min(max_global_value_w,
        global_column_w - label_gap - 1))
    local map_value_w = math.max(1, math.min(max_map_value_w,
        map_column_w - label_gap - 1))

    self._values = {}

    -- Builds one column: a centered header ("Global" or the layout name) over
    -- its measured width, then the labelled value rows. Each row is split around
    -- that column's own divider, so the combined columns can remain centered
    -- without making the divider itself the screen midpoint.
    -- Value widgets are stored in _values under `prefix .. key` so
    -- updateValues() can re-render them.
    local function buildColumn(header_text, source_vs, prefix, column_w, column_value_w)
        local label_slot_w = math.max(1, math.min(max_label_w,
            column_w - label_gap - column_value_w))
        local column_header_face = MahjongUI.fitTextFace(
            header_text, "tfont", header_face.size or Screen:scaleBySize(18),
            Screen:scaleBySize(9), column_w, Screen:scaleBySize(28))
        local header = TextWidget:new{
            text = header_text,
            padding = 0,
            bold = true,
            face = column_header_face,
            max_width = column_w,
            truncate_with_ellipsis = true,
        }
        local header_w = header:getSize().w
        local header_space = math.max(0, math.floor((column_w - header_w) / 2))
        local vchildren = {
            HorizontalGroup:new{
                HorizontalSpan:new{ width = header_space },
                header,
                HorizontalSpan:new{ width = math.max(0, column_w - header_w - header_space) },
            },
        }
        for _, r in ipairs(row_specs) do
            vchildren[#vchildren + 1] = VerticalSpan:new{ width = Screen:scaleBySize(14) }
            local row_value_face = MahjongUI.fitTextFace(
                source_vs[r.key], "cfont", value_face.size or Screen:scaleBySize(18),
                Screen:scaleBySize(8), column_value_w, Screen:scaleBySize(24))
            local value_widget = TextWidget:new{
                text = source_vs[r.key],
                padding = 0,
                bold = true,
                face = row_value_face,
                max_width = column_value_w,
                truncate_with_ellipsis = true,
            }
            self._values[prefix .. r.key] = value_widget
            local label_w = measureText(r.label, label_face, false)
            local value_w = measureText(source_vs[r.key], value_face, true)
            vchildren[#vchildren + 1] = HorizontalGroup:new{
                HorizontalSpan:new{ width = math.max(0, label_slot_w - label_w) },
                TextWidget:new{ text = r.label, padding = 0, face = label_face,
                    max_width = label_slot_w, truncate_with_ellipsis = true,
                    fgcolor = label_color },
                HorizontalSpan:new{ width = label_gap },
                value_widget,
                HorizontalSpan:new{ width = math.max(0, column_value_w - value_w) },
            }
        end
        return VerticalGroup:new(vchildren)
    end

    local global_col = buildColumn(global_header_text, vs, "", global_column_w, global_value_w)
    local map_col
    if show_map then
        map_col = buildColumn(map_header_text, map_vs, "map_", map_column_w, map_value_w)
    end

    -- Reset button (bottom): clears the whole record (global + per-layout
    -- maps) back to defaults, after a ConfirmBox so an accidental tap cannot
    -- wipe the lifetime stats.
    local reset_w = math.min(Screen:scaleBySize(160),
        math.max(1, max_panel_w - 2 * panel_padding))
    local reset_h = math.max(1, math.min(Screen:scaleBySize(32),
        math.floor(self.full_height * 0.06)))
    local reset_btn = ButtonWidget:new{
        text = t("settings.reset"),
        text_font_face = "cfont",
        text_font_size = math.max(8, math.min(20, math.floor(reset_h * 0.6))),
        text_font_bold = true,
        width = reset_w,
        height = reset_h,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(4),
        padding = math.max(1, math.min(Screen:scaleBySize(6), math.floor(reset_h * 0.16))),
        callback = function() self:resetStats() end,
    }
    self._reset_btn = reset_btn

    local gap = math.min(Screen:scaleBySize(14),
        math.max(Screen:scaleBySize(4), math.floor(self.full_height * 0.018)))
    local layout_content_w = stacked_columns and math.max(global_column_w, map_column_w) or content_w
    local panel_content_w = math.max(layout_content_w, reset_w)
    local pad_side = math.max(0, math.floor((panel_content_w - reset_w) / 2))
    local reset_row = HorizontalGroup:new{
        HorizontalSpan:new{ width = pad_side },
        reset_btn,
        HorizontalSpan:new{ width = math.max(0, panel_content_w - reset_w - pad_side) },
    }

    -- Title row: "Stats" centered, with a close X pinned at the panel's
    -- top-right corner (same grey-square style as the HUD's quit X). Tapping
    -- it closes the card (and runs onClose).
    local close_size = math.max(1, math.min(Screen:scaleBySize(36),
        math.floor(self.full_height * 0.08)))
    local title_max_w = math.max(1, panel_content_w - close_size - gap)
    local title_face = MahjongUI.fitTextFace(
        t("toolbar.stats"), "tfont", Screen:scaleBySize(compact and 16 or 20),
        Screen:scaleBySize(10), title_max_w, close_size)
    local title_widget = TextWidget:new{
        text = t("toolbar.stats"), padding = 0, face = title_face,
        max_width = title_max_w, truncate_with_ellipsis = true,
    }
    local title_w = math.min(title_widget:getSize().w, title_max_w)
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
    local top_pad = math.max(Screen:scaleBySize(6), math.min(
        Screen:scaleBySize(18), math.floor(self.full_height * 0.025)))
    -- The two columns ALWAYS render side by side: a vertical stacked layout
    -- (Global above <layout>) made the card a very tall panel that overflowed
    -- the screen. The columns share the same width, so a side-by-side row is
    -- no taller than the settings dialog's rows and fits any canvas whose
    -- width holds two columns (the responsive gap/padding clamps below keep
    -- the columns from crowding on narrow screens).
    local columns_layout
    if show_map then
        if stacked_columns then
            columns_layout = VerticalGroup:new{
                global_col,
                VerticalSpan:new{ height = col_gap },
                map_col,
            }
        else
            columns_layout = HorizontalGroup:new{
                global_col,
                HorizontalSpan:new{ width = col_gap },
                map_col,
            }
        end
    else
        columns_layout = global_col
    end
    local panel = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(10),
        padding = panel_padding,
        VerticalGroup:new{
            title_row,
            VerticalSpan:new{ width = gap },
            columns_layout,
            VerticalSpan:new{ width = gap * 2 },
            reset_row,
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
    UIManager:close(self, "ui", self._panel_geom)
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

-- Zeroes the whole lifetime record (global + per-layout maps) back to
-- defaults — after a ConfirmBox.
function StatsWidget:resetStats()
    UIManager:show(ConfirmBox:new{
        text = t("stats.reset_confirm"),
        ok_text = t("settings.reset"),
        ok_callback = function()
            local p = self.parent
            if p then
                p.stats = MahjongStats.defaults()
                if p.saveStats then p:saveStats() end
            end
            self:updateValues()
            UIManager:setDirty(self, "ui", self._panel_geom)
        end,
    })
end

return StatsWidget
