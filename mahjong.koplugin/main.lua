local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local Geometry = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local ButtonWidget = require("ui/widget/button")
local IconWidget = require("ui/widget/iconwidget")
local TextWidget = require("ui/widget/textwidget")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local MahjongLogic = require("mahjonglogic")
local MahjongBoard = require("mahjongboard")
local HudBar = require("hudbar")
local SettingsWidget = require("mahjongsettings")

local BACKGROUND_COLOR = Blitbuffer.COLOR_WHITE

local function getPluginPath()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", "")
    return src:match("^(.*[/\\])main%.lua$") or "."
end

local function normalizePath(path)
    path = (path or ""):gsub("\\", "/")
    return path:gsub("/+", "/")
end

local function joinPath(...)
    local parts = {...}
    local path = tostring(parts[1] or "")
    for i = 2, #parts do
        local part = tostring(parts[i] or "")
        path = path:gsub("/+$", "") .. "/" .. part:gsub("^/+", "")
    end
    return normalizePath(path)
end

local PLUGIN_PATH = normalizePath(getPluginPath()):gsub("/+$", "")
local ICON_DIR = "mahjong"

-- US-09 scoring: base + chain bonus live in mahjonglogic.lua
-- (MahjongLogic.pairPoints / SCORE_PER_PAIR / CHAIN_BONUS); main.lua only
-- tracks the kind of the previous match for the chain. A timer bonus is not
-- implemented, but elapsed time IS tracked and displayed (US-10).
-- FLASH_TIMEOUT: how long a non-blocking feedback message (e.g. "Tile is
-- blocked") stays visible in the band between the board and the toolbar.
local FLASH_TIMEOUT = 2

-- US-19: holding the Hint button for AUTO_SOLVE_HOLD_SECONDS starts an
-- automated solver that plays matching pairs until the board is cleared;
-- AUTO_SOLVE_STEP_SECONDS paces how fast the pairs are removed so each move
-- is visible on the e-ink refresh.
local AUTO_SOLVE_HOLD_SECONDS = 10
local AUTO_SOLVE_STEP_SECONDS = 0.4

-- Settings keys (persisted via LuaSettings in the KOReader settings dir).
-- score_method: "chain" (default, +5 for consecutive same-group matches) or
-- "basic" (flat 10 per pair). layout is "turtle" (the only one today).
-- timer_update: "interval" (repaint the mm:ss on a periodic polling loop,
-- default) or "move" (only repaint on board interaction, so an idle board
-- never forces an e-ink refresh). timer_interval: seconds between periodic
-- repaints (cosmetic; a 1 Hz e-ink repaint is overkill, 5 s is the default).
local SETTINGS_DEFAULTS = {
    hints = true,               -- show hints on the toolbar / allow the Hint button
    confirm_new_game = true,    -- ask before starting a New Game
    score_method = "chain",     -- "chain" or "basic"
    layout = "turtle",
    timer_update = "interval",  -- "interval" or "move"
    timer_interval = 5,         -- seconds between periodic timer repaints
}

-- Smallest interval the timer loop will honor (dialog offers 1..60).
local MIN_TIMER_INTERVAL = 1

-- A ButtonWidget that surfaces the "long-press released" event. KOReader's
-- Button registers a "hold" gesture (fires ~ges_hold_interval_ms after
-- contact) that calls `hold_callback`, and it consumes the matching
-- "hold_release" internally with no callback exposed. The auto-solver needs
-- to cancel its 10 s arm if the finger lifts early, so this subclass forwards
-- the release. In real KOReader it is a subclass of the stock Button; the test
-- harness stubs `ui/widget/button` with an equivalent class.
local LongPressButton = ButtonWidget:extend{
    hold_release_callback = nil,
}

function LongPressButton:onHoldReleaseSelectButton()
    if self.hold_release_callback then
        self.hold_release_callback()
    end
    return ButtonWidget.onHoldReleaseSelectButton(self)
end

-- Toolbar action button: a rounded rectangle `w` x `h` — the WHOLE widget is
-- the tap area — with a square icon centered inside it, plus a small hint
-- label beneath. Padding keeps the icon off the button edges, bordersize draws
-- a slim rounded border, and radius rounds the corners. The icon button and
-- its label are stacked in a VerticalGroup so each toolbar cell carries a
-- caption (Undo / Hint / Shuffle / New Game). The cells are separated by
-- HorizontalSpan spacers in buildUILayout() (the stock HorizontalGroup ignores
-- any `spacing` field).
--
-- Optional `hold_cb` / `hold_release_cb` turn the button into a LongPressButton
-- (long-press arm + release hook, used by the Hint button's auto-solver).
-- Returns the cell (the VerticalGroup) and the ButtonWidget itself (so tests
-- can reach the hold callbacks).
local function createToolbarButton(icon, label, w, h, cb, hold_cb, hold_release_cb)
    local pad = Screen:scaleBySize(6)
    local border = Screen:scaleBySize(1)
    local radius = Screen:scaleBySize(4)
    local icon_h = h - 2 * pad - 2 * border
    local button_opts = {
        icon = icon,
        width = w,
        icon_width = icon_h,
        icon_height = icon_h,
        padding = pad,
        margin = 0,
        bordersize = border,
        radius = radius,
        callback = cb,
    }
    if hold_cb or hold_release_cb then
        button_opts.hold_callback = hold_cb
        button_opts.hold_release_callback = hold_release_cb
        button_opts = LongPressButton:new(button_opts)
    else
        button_opts = ButtonWidget:new(button_opts)
    end
    local label_widget = TextWidget:new{
        text = label,
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(11)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local cell = VerticalGroup:new{
        align = "center",
        button_opts,
        label_widget,
    }
    return cell, button_opts
end

-- Binary copy in pure Lua (no shell subprocess).
local function copyFile(src, dst)
    local in_f, err = io.open(src, "rb")
    if not in_f then return false, err end
    local data = in_f:read("*a")
    in_f:close()
    local out_f, oerr = io.open(dst, "wb")
    if not out_f then return false, oerr end
    out_f:write(data)
    out_f:close()
    return true
end

-- Copies the bundled SVG tiles into the KOReader icons dir so IconWidget can
-- resolve "mahjong/<name>" from anywhere (plugin dirs are not icon search
-- paths). Always overwrites so bundled icon updates (e.g. a redesign) reach
-- the device on the next plugin load. The copy is a Lua io loop rather than
-- per-file os.execute('cp ...') to avoid spawning ~45 shell processes on every
-- plugin load on the slow Kindle.
local function installIconsIfNeeded()
    local src_dir = joinPath(PLUGIN_PATH, "icons")
    if lfs.attributes(src_dir, "mode") ~= "directory" then return end
    local dest_dir = DataStorage:getDataDir() .. "/icons/" .. ICON_DIR
    util.makePath(dest_dir)
    for entry in lfs.dir(src_dir) do
        if entry:match("%.svg$") then
            copyFile(joinPath(src_dir, entry), joinPath(dest_dir, entry))
        end
    end
end

local Mahjong = FrameContainer:extend{
    name = "mahjong",
    is_doc_only = false,
    background = BACKGROUND_COLOR,
    bordersize = 0,
    padding = 0,
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    board = nil,
    board_view = nil,
    status_bar = nil,
    selected = nil, -- { x, y, layer, kind } of the currently selected tile
    score = 0,
    last_match_kind = nil, -- kind of the last matched pair (chain scoring, US-09)
    history = nil, -- stack of { a, b, ka, kb, score, prev_last }
    settings = nil, -- LuaSettings handle (US-10)
    score_method = "chain", -- "chain" or "basic" (settings, defaulted for tests)
    elapsed_base = 0, -- elapsed seconds at last stop (US-10)
    _timer_running = false,
    _timer_started_at = nil,
    _timer_run_id = 0,
    timer_text = nil, -- the mm:ss TextWidget in the feedback band
    _flash_seq = 0, -- monotonic token for the pending feedback-clear timer
    flash_band = nil,  -- fixed-height band between the board and the toolbar
    flash_text = nil,  -- the band's TextWidget (feedback messages appear here)
    _auto_solve_token = 0, -- monotonic token invalidating pending auto-solve arms/steps
    _auto_solve_active = false, -- true while the long-press solver is running (US-19)
    _last_hint = nil, -- the last hinted pair { a, b }, so repeated Hint presses cycle (US-08)
    hint_button = nil, -- the toolbar Hint ButtonWidget (exposes hold callbacks, US-19)
}

function Mahjong:init()
    self.history = {}
    self.dimensions = Geometry:new{
        w = self.full_width,
        h = self.full_height,
    }
    self.covers_fullscreen = true
    Dispatcher:registerAction("mahjong", {
        category = "none",
        event = "MahjongStart",
        title = _("Mahjong Solitaire"),
        general = true,
    })
    self.ui.menu:registerToMainMenu(self)
    installIconsIfNeeded()
    -- US-10: one LuaSettings file for both the game state and the settings.
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/mahjong.lua")
end

-- Settings helpers (mirror the kochess example). setSetting persists
-- immediately so a setting change survives an abrupt exit.
function Mahjong:getSetting(key, default)
    if not self.settings then return default end
    return self.settings:readSetting(key, default)
end

function Mahjong:setSetting(key, value)
    if not self.settings then return end
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

function Mahjong:refreshScoreMethod()
    self.score_method = self:getSetting("score_method", SETTINGS_DEFAULTS.score_method)
end

function Mahjong:addToMainMenu(menu_items)
    menu_items.mahjong = {
        text = _("Mahjong Solitaire"),
        sorting_hint = "tools",
        callback = function() self:startGame() end,
        keep_menu_open = false,
    }
end

function Mahjong:onMahjongStart()
    self:startGame()
    return true
end

function Mahjong:handleEvent(event)
    -- Dispatcher can launch the game while this widget is not on the stack.
    if event.handler == "onMahjongStart" then
        return self:onMahjongStart()
    end
    -- FileManager can still propagate child events after UIManager:close().
    local on_stack = false
    for i = #UIManager._window_stack, 1, -1 do
        if UIManager._window_stack[i].widget == self then
            on_stack = true
            break
        end
    end
    if not on_stack then return false end
    return FrameContainer.handleEvent(self, event)
end

function Mahjong:startGame()
    if UIManager.isWidgetShown and UIManager:isWidgetShown(self) then
        UIManager:close(self)
    end
    self:refreshScoreMethod()
    local restored = self:restoreGameState()
    if restored then
        self.board = restored.board
        self.history = restored.history
        self.score = restored.score
        self.last_match_kind = restored.last_match_kind
        self.elapsed_base = restored.elapsed
    else
        self.board = MahjongLogic.newGame()
        self.history = {}
        self.score = 0
        self.last_match_kind = nil
        self.elapsed_base = 0
    end
    self.selected = nil
    self._last_hint = nil -- the hint cycle starts fresh for this session
    self._timer_running = false
    self:buildUILayout()
    self:updateStatus()
    self:updateTimerDisplay()
    self:startTimer()
    UIManager:show(self)
end

-- US-10: persistence -------------------------------------------------------
--
-- The whole game is saved under the "game" LuaSettings key after every move
-- (and on close). State is compact: the board is a flat posKey -> kind table
-- and the undo history is flattened by serializeGameState. A mid-game save is
-- a few KB at most, so writing it after each move is cheap (moves are
-- user-paced, seconds apart on e-ink).
--
-- A won game (empty board) is NOT saved: closing after a win clears the key,
-- so the next launch deals a fresh board instead of showing a stale empty one.

function Mahjong:saveGameState()
    if not self.settings or not self.board then return end
    if MahjongLogic.isWin(self.board) then
        self.settings:saveSetting("game", nil)
    else
        local data = MahjongLogic.serializeGameState(
            self.board, self.history, self.score,
            self.last_match_kind, self:getElapsed())
        self.settings:saveSetting("game", data)
    end
    self.settings:flush()
end

-- Restores a previously saved mid-game state, or nil (fresh game). A corrupt
-- or impossible saved state silently starts a new game (per US-10).
function Mahjong:restoreGameState()
    if not self.settings then return nil end
    local data = self.settings:readSetting("game", nil)
    if not data then return nil end
    local restored = MahjongLogic.deserializeGameState(data)
    if not restored or MahjongLogic.isWin(restored.board) then
        self.settings:saveSetting("game", nil)
        self.settings:flush()
        return nil
    end
    return restored
end

-- Elapsed-time timer --------------------------------------------------------
--
-- Cosmetic only (no score bonus): the mm:ss display in the feedback band.
-- Elapsed seconds ALWAYS accrue (getElapsed diffs against os.time) and are
-- saved with the game state so the clock survives a close/reopen. The
-- SETTING only controls when the DISPLAY repaints:
--   * "interval" (default): a polling loop (the kochess pollingLoop pattern)
--     repaints every timer_interval seconds (default 5 — 1 Hz is overkill for
--     e-ink). The loop is the ONLY thing that refreshes an idle board.
--   * "move": no polling loop; the display is refreshed from the interaction
--     handlers (select/deselect/match/undo/shuffle/new game) so an idle board
--     never forces an e-ink refresh.
-- Each start bumps a run-id token; stopTimer() invalidates the pending tick,
-- so a stale timer can never fire after close/new-game.

function Mahjong:timerMode()
    return self:getSetting("timer_update", SETTINGS_DEFAULTS.timer_update)
end

function Mahjong:timerInterval()
    local v = tonumber(self:getSetting("timer_interval", SETTINGS_DEFAULTS.timer_interval))
    if not v or v < MIN_TIMER_INTERVAL then
        return SETTINGS_DEFAULTS.timer_interval
    end
    return v
end

function Mahjong:getElapsed()
    if self._timer_running and self._timer_started_at then
        return self.elapsed_base + os.difftime(os.time(), self._timer_started_at)
    end
    return self.elapsed_base
end

function Mahjong:startTimer()
    self._timer_run_id = self._timer_run_id + 1
    local run_id = self._timer_run_id
    self._timer_started_at = os.time()
    self._timer_running = true
    if self:timerMode() ~= "interval" then
        -- "move" mode: no polling loop; interactions refresh the display.
        return
    end
    local interval = self:timerInterval()
    local tick
    tick = function()
        if self._timer_running and self._timer_run_id == run_id then
            self:updateTimerDisplay()
            UIManager:scheduleIn(interval, tick)
        end
    end
    UIManager:nextTick(tick)
end

function Mahjong:stopTimer()
    if self._timer_running then
        self.elapsed_base = self:getElapsed()
    end
    self._timer_running = false
    self._timer_run_id = self._timer_run_id + 1
end

function Mahjong:resetTimer()
    self:stopTimer()
    self.elapsed_base = 0
    self:startTimer()
end

function Mahjong:updateTimerDisplay()
    if not self.timer_text then return end
    self.timer_text:setText(MahjongLogic.formatElapsed(self:getElapsed()))
    if self.timer_text.resetLayout then self.timer_text:resetLayout() end
    UIManager:setDirty(self, "ui")
end

-- Settings dialog (US-10) ---------------------------------------------------

function Mahjong:openSettings()
    -- Freeze the clock and stop the polling loop while the dialog is up: the
    -- settings dialog floats over the game now, and a periodic full-screen
    -- refresh (US-11 "interval" mode) would flash every tick behind the panel.
    -- Save restarts via onApply, Cancel / tap-outside via onCancel.
    self:stopTimer()
    local dlg = SettingsWidget:new{
        parent = self,
        settings_defaults = SETTINGS_DEFAULTS,
        onApply = function()
            self:refreshScoreMethod()
            self:updateStatus()
            -- The timer mode/interval may have changed (US-11): restart the
            -- polling loop. stopTimer freezes elapsed_base, startTimer resumes.
            self:stopTimer()
            self:startTimer()
            self:updateTimerDisplay()
        end,
        onCancel = function()
            self:startTimer()
            self:updateTimerDisplay()
        end,
    }
    dlg:show()
end

function Mahjong:buildUILayout()
    self.status_bar = self:createStatusBar()
    local status_h = self.status_bar:getSize().h

    -- Toolbar is 48px tall (rounded bordered buttons) with a small hint label
    -- under each icon, small gaps between the buttons, edge gaps so the outer
    -- buttons don't scrape the screen sides, and a bottom spacer that lifts
    -- the row off the screen edge; the board fills what remains.
    local toolbar_btn_h = Screen:scaleBySize(48)
    local toolbar_gap = Screen:scaleBySize(6)
    -- 5 gaps: one at each edge + 3 between the 4 buttons.
    local toolbar_btn_w = math.floor((self.full_width - 5 * toolbar_gap) / 4)
    -- Probe the hint-label height so the toolbar row reserves room for it.
    local label_probe = TextWidget:new{
        text = "Ag",
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(11)),
    }
    local label_h = label_probe:getSize().h
    label_probe:free()
    local toolbar_h = toolbar_btn_h + label_h
    local bottom_gap = Screen:scaleBySize(12)
    -- Feedback band (US-09): a fixed-height strip between the board and the
    -- toolbar where brief non-blocking messages appear. The slot is always
    -- reserved so the board geometry stays stable when a message shows/clears.
    -- Font is kept small (~0.8× HUD labels) so it reads as a subtle notice;
    -- height is probed from the font so it fits any DPI.
    local flash_font_size = Screen:scaleBySize(30)
    local flash_probe = TextWidget:new{
        text = "Ag",
        padding = 0,
        face = Font:getFace("smallinfofont", flash_font_size),
    }
    local flash_text_h = flash_probe:getSize().h
    flash_probe:free()
    local flash_pad_top = Screen:scaleBySize(4)
    local flash_pad_bottom = Screen:scaleBySize(14)
    local flash_h = flash_text_h + flash_pad_top + flash_pad_bottom
    local board_h = self.full_height - status_h - flash_h - toolbar_h - bottom_gap

    self.board_view = MahjongBoard:new{
        board = self.board,
        width = self.full_width,
        height = board_h,
        onTileTap = function(x, y, layer) self:handleTileTap(x, y, layer) end,
    }

    local board_area = FrameContainer:new{
        background = BACKGROUND_COLOR,
        bordersize = 0,
        padding = 0,
        width = self.full_width,
        height = board_h,
        self.board_view,
    }

    -- Non-blocking feedback: a plain (non-input) text band with a chip-style
    -- border that extends screen-to-screen. Because it is not a dialog, taps
    -- on the board keep working while a message is showing.  The warning
    -- triangle icon sits on the far left; the text is centered across the
    -- full band width.  Both appear/disappear together.
    local band_edge_pad = Screen:scaleBySize(8)
    local band_border = Screen:scaleBySize(1)
    -- Icon sized to the band's text (a bit smaller than the cap height) and
    -- vertically aligned with the text's vertical center, so the icon reads
    -- as vertically centered in the band.
    local icon_size = math.floor(flash_text_h * 0.72)
    local icon_x = band_edge_pad + Screen:scaleBySize(4)
    local icon_y = math.floor((flash_text_h - icon_size) / 2)
    self.flash_band_icon = IconWidget:new{
        icon = ICON_DIR .. "/warning",
        width = icon_size,
        height = icon_size,
        hide = true,
        -- OverlapGroup paints a child at overlap_offset[1]/[2] — this field
        -- must live ON the child widget (see the board's tile widgets), and
        -- it must be an ARRAY, not a {x=.., y=..} map.
        overlap_offset = { icon_x, icon_y },
    }
    self.flash_text = TextWidget:new{
        text = "",
        padding = 0,
        face = Font:getFace("smallinfofont", flash_font_size),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        -- OverlapGroup supports per-child overlap_align; "center" centers the
        -- text across the FULL band width, independent of the icon position.
        overlap_align = "center",
    }
    -- Elapsed-time display (US-10): a permanently visible mm:ss in the RIGHT
    -- part of the band (the flash message stays centered, the timer on the
    -- right never moves). Reserve a fixed-width slot so the number doesn't
    -- drift as the text width changes between "0:07" and "59:59".
    local timer_probe = TextWidget:new{
        text = "00:00",
        padding = 0,
        face = Font:getFace("smallinfofont", flash_font_size),
    }
    local timer_slot_w = timer_probe:getSize().w
    timer_probe:free()
    self.timer_text = TextWidget:new{
        text = MahjongLogic.formatElapsed(0),
        padding = 0,
        face = Font:getFace("smallinfofont", flash_font_size),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        -- Array-form offset on the widget itself (OverlapGroup contract, see
        -- the board's tile widgets). Right-aligned to the band edge with the
        -- same margin the warning icon uses on the left.
        overlap_offset = {
            self.full_width - timer_slot_w - band_edge_pad - Screen:scaleBySize(4),
            0,
        },
    }
    -- OverlapGroup iterates its children and calls getSize() on each one
    -- (overlapgroup.lua getSize/init). Every child MUST be a real widget — a
    -- plain wrapper table like { overlap_offset = ..., widget } has no
    -- getSize() and crashes with "attempt to call method 'getSize' (a nil
    -- value)". The icon, text and timer go in directly, exactly like the board.
    local band_overlay = OverlapGroup:new{
        dimen = Geometry:new{ w = self.full_width, h = flash_h },
        self.flash_text,
        self.flash_band_icon,
        self.timer_text,
    }
    self.flash_band = FrameContainer:new{
        band_overlay,
        bordersize = band_border,
        color = Blitbuffer.COLOR_DARK_GRAY,
        background = BACKGROUND_COLOR,
        radius = Screen:scaleBySize(8),
        padding = band_edge_pad,
    }
    -- getSize() is overridden below, so the real FrameContainer:getSize() —
    -- which is the ONLY thing that populates the _padding_* fields — never
    -- runs. paintTo would crash on nil _padding_left (framecontainer.lua:143);
    -- mirror the padding assignments like HudBar does (AGENTS.md pitfall).
    self.flash_band._padding_left = band_edge_pad
    self.flash_band._padding_right = band_edge_pad
    self.flash_band._padding_top = band_edge_pad
    self.flash_band._padding_bottom = band_edge_pad
    self.flash_band.getSize = function()
        return Geometry:new{ w = self.full_width, h = flash_h }
    end

    -- US-19: the Hint button is a LongPressButton — a short tap hints, holding
    -- it for AUTO_SOLVE_HOLD_SECONDS arms the auto-solver. Keep a reference so
    -- the test harness can drive the hold callbacks.
    local hint_cell, hint_button = createToolbarButton(
        "mahjong/lightbulb", _("Hint"), toolbar_btn_w, toolbar_btn_h,
        function() self:showHint() end,
        function() self:armAutoSolve() end,
        function() self:disarmAutoSolve() end)
    self.hint_button = hint_button

    local toolbar = HorizontalGroup:new{
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("chevron.left", _("Undo"), toolbar_btn_w, toolbar_btn_h,
            function() self:undo() end),
        HorizontalSpan:new{ width = toolbar_gap },
        hint_cell,
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("mahjong/shuffle", _("Shuffle"), toolbar_btn_w, toolbar_btn_h,
            function() self:shuffleBoard() end),
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("plus", _("New Game"), toolbar_btn_w, toolbar_btn_h, function()
            if self:getSetting("confirm_new_game", SETTINGS_DEFAULTS.confirm_new_game) then
                UIManager:show(ConfirmBox:new{
                    text        = _("Start a new game?"),
                    ok_text     = _("New Game"),
                    ok_callback = function() self:resetGame() end,
                })
            else
                self:resetGame()
            end
        end),
        HorizontalSpan:new{ width = toolbar_gap },
    }

    local main_vgroup = VerticalGroup:new{
        align = "center",
        width = self.full_width,
        height = self.full_height,
        self.status_bar,
        board_area,
        self.flash_band,
        toolbar,
        VerticalSpan:new{ width = bottom_gap },
    }
    self[1] = main_vgroup
end

function Mahjong:createStatusBar()
    -- HUD top bar (hudbar.lua): settings gear (left) + title + three stat
    -- chips (Pairs / Free / Score) + the quit X (right), replacing the old
    -- TitleBarWidget text subtitle. updateStatus() pushes the values via
    -- setStats().
    return HudBar:new{
        title                  = _("Mahjong Solitaire"),
        left_icon              = "appbar.settings",
        left_icon_size_ratio   = 0.9,
        left_icon_tap_callback = function() self:openSettings() end,
        right_icon             = "mahjong/close",
        right_icon_size_ratio  = 0.9,
        right_icon_tap_callback = function()
            UIManager:show(ConfirmBox:new{
                text        = _("Exit Mahjong Solitaire?"),
                ok_text     = _("Exit"),
                ok_callback = function()
                    UIManager:close(self, "full")
                end,
            })
        end,
    }
end

function Mahjong:resetGame()
    -- US-19: a New Game cancels a pending long-press arm or an active solve.
    self:stopAutoSolve()
    self._last_hint = nil -- a fresh board resets the hint cycle
    self.board = MahjongLogic.newGame()
    self.selected = nil
    self.score = 0
    self.last_match_kind = nil
    self.history = {}
    self:refreshScoreMethod()
    self.elapsed_base = 0
    self._timer_running = false
    self:buildUILayout()
    self:updateStatus()
    self:updateTimerDisplay()
    self:startTimer()
    -- Save-after-every-move model: a New Game immediately replaces the old
    -- saved state (which was cleared), so a close/reopen resumes the fresh
    -- board rather than resurrecting the previous game.
    self:saveGameState()
    UIManager:setDirty(self, "ui")
end

-- Core gameplay (US-07) ------------------------------------------------------
--
-- Tap behavior:
--   * free tile tapped -> select (highlight with the `select` overlay);
--   * non-free tile tapped -> ignored;
--   * tapping the selected tile again -> deselect;
--   * tapping a different matching free tile -> remove the pair, then check for
--     a win / a dead board;
--   * tapping a different, non-matching free tile -> switch the selection.

function Mahjong:handleTileTap(x, y, layer)
    -- US-19: a board tap while the auto-solver is running interrupts it. The
    -- tap itself is consumed so it cannot fight the solver for a tile.
    if self._auto_solve_active then
        self:stopAutoSolve()
        return
    end
    local kind = MahjongLogic.tileAt(self.board, x, y, layer)
    if not kind then return end
    if not MahjongLogic.isFree(self.board, x, y, layer) then
        self:flashMessage(_("Tile is blocked"))
        return
    end

    local sel = self.selected
    if sel then
        -- Tapping the selected tile again deselects it.
        if sel.x == x and sel.y == y and sel.layer == layer then
            self:clearSelection()
            return
        end
        -- A matching free tile removes both.
        local a = { x = sel.x, y = sel.y, layer = sel.layer }
        local b = { x = x, y = y, layer = layer }
        if self:applyMatch(a, b) then
            self:checkGameState()
            return
        end
    end

    -- First tap, or switching from a different tile.
    self:setSelection(x, y, layer, kind)
end

-- Applies a matched pair to the game: removes it from the logic board and the
-- rendered board, scores it (chain bonus for consecutive same-group matches),
-- records it in the undo history, refreshes the HUD and the mm:ss display, and
-- persists. Returns true when the pair was applied. `a`/`b` are { x, y, layer }
-- tables. Shared by the tap path (handleTileTap) and the auto-solver (US-19)
-- so an auto-solved game scores and saves exactly like a hand-played one.
function Mahjong:applyMatch(a, b)
    local ok, ka, kb = MahjongLogic.removePair(self.board, a, b)
    if not ok then return false end
    self.selected = nil
    self.board_view:removePair(a, b)
    local prev_last = self.last_match_kind
    local points
    if self.score_method == "chain" then
        points = MahjongLogic.pairPoints(prev_last, ka)
    else
        points = MahjongLogic.SCORE_PER_PAIR
    end
    self.last_match_kind = ka
    self.score = self.score + points
    table.insert(self.history, { a = a, b = b, ka = ka, kb = kb, score = points, prev_last = prev_last })
    self:updateStatus()
    self:updateTimerDisplay()
    self:saveGameState()
    return true
end

function Mahjong:setSelection(x, y, layer, kind)
    self:clearSelection()
    self.selected = { x = x, y = y, layer = layer, kind = kind }
    self.board_view:setOverlay(x, y, layer, "select")
    self:updateTimerDisplay()
end

function Mahjong:clearSelection()
    if self.selected then
        self.board_view:clearOverlay(self.selected.x, self.selected.y, self.selected.layer)
        self.selected = nil
        self:updateTimerDisplay()
    end
end

-- After every removal: win dialog when the board is empty, otherwise an
-- offer to reshuffle when no move remains (US-08).
function Mahjong:checkGameState()
    if MahjongLogic.isWin(self.board) then
        self:showWinDialog()
    elseif not MahjongLogic.hasMoves(self.board) then
        UIManager:show(ConfirmBox:new{
            text = _("No moves left! Shuffle the board?"),
            ok_text = _("Shuffle"),
            ok_callback = function() self:shuffleBoard(true) end,
            cancel_text = _("Close"),
            cancel_callback = function()
                UIManager:close(self, "full")
            end,
        })
    end
end

function Mahjong:showWinDialog()
    UIManager:show(ConfirmBox:new{
        text = string.format(_("You cleared the board! Score: %d"), self.score),
        ok_text = _("Play again"),
        ok_callback = function() self:resetGame() end,
        cancel_text = _("Close"),
        cancel_callback = function()
            UIManager:close(self, "full")
        end,
    })
end

-- US-08: Undo, hint, and shuffle ---------------------------------------------

function Mahjong:undo()
    -- US-19: undoing mid-solve stops the solver first so the next scheduled
    -- step cannot immediately replay a tile.
    if self._auto_solve_active then
        self:stopAutoSolve()
    end
    local move = table.remove(self.history)
    if not move then return end

    self:clearSelection()
    MahjongLogic.undoPair(self.board, move.a, move.b, move.ka, move.kb)
    self.board_view:addPair({ x = move.a.x, y = move.a.y, layer = move.a.layer, kind = move.ka },
                            { x = move.b.x, y = move.b.y, layer = move.b.layer, kind = move.kb })
    self.score = self.score - move.score
    self.last_match_kind = move.prev_last
    self:updateStatus()
    self:updateTimerDisplay()
    self:saveGameState()
end

-- Repeated Hint presses cycle through the available matching pairs instead of
-- always highlighting the same first one (the hint stays on each pair for the
-- usual 2 s, then the next press moves to the pair AFTER it, wrapping around).
function Mahjong:showHint()
    -- US-19: a short tap while the auto-solver runs stops it (the solver also
    -- highlights pairs as it plays, so a hint would be redundant).
    if self._auto_solve_active then
        self:stopAutoSolve()
    end
    if not self:getSetting("hints", SETTINGS_DEFAULTS.hints) then return end
    local board_view = self.board_view
    -- Drop the previous hint's overlays first so cycling presses never leave a
    -- stale highlight behind (clearOverlay is a no-op if the tile is gone).
    if self._last_hint then
        board_view:clearOverlay(self._last_hint.a.x, self._last_hint.a.y, self._last_hint.a.layer)
        board_view:clearOverlay(self._last_hint.b.x, self._last_hint.b.y, self._last_hint.b.layer)
    end
    local pairs = MahjongLogic.matchingFreePairs(self.board)
    if #pairs == 0 then
        self._last_hint = nil
        -- In theory checkGameState already caught this, but user can tap Hint
        -- on a dead board before the shuffle prompt is accepted.
        UIManager:show(ConfirmBox:new{
            text = _("No moves left! Shuffle the board?"),
            ok_text = _("Shuffle"),
            ok_callback = function() self:shuffleBoard(true) end,
        })
        return
    end
    -- Cycle: highlight the pair AFTER the one just shown (wrapping around). If
    -- the board changed under the previous hint (a match/shuffle moved or
    -- removed it), the scan finds nothing and we start over at the first pair.
    local idx = 0
    if self._last_hint then
        for i, p in ipairs(pairs) do
            if p.a.x == self._last_hint.a.x and p.a.y == self._last_hint.a.y
                and p.a.layer == self._last_hint.a.layer
                and p.b.x == self._last_hint.b.x and p.b.y == self._last_hint.b.y
                and p.b.layer == self._last_hint.b.layer then
                idx = i
                break
            end
        end
    end
    local pair = pairs[idx % #pairs + 1]
    self._last_hint = pair
    board_view:setOverlay(pair.a.x, pair.a.y, pair.a.layer, "hint")
    board_view:setOverlay(pair.b.x, pair.b.y, pair.b.layer, "hint")
    -- Clear hints after 2 seconds.
    UIManager:scheduleIn(2, function()
        if board_view == self.board_view then
            board_view:clearOverlay(pair.a.x, pair.a.y, pair.a.layer)
            board_view:clearOverlay(pair.b.x, pair.b.y, pair.b.layer)
        end
    end)
end

-- Reshuffles the tiles remaining on the board in place.
function Mahjong:shuffleBoard(force, attempts)
    attempts = attempts or 10
    local do_shuffle = function()
        MahjongLogic.shuffleBoard(self.board)
        self:clearSelection()
        self.board_view:updateBoard()
        self:updateStatus()
        self:updateTimerDisplay()
        self:saveGameState()
        -- If still no moves (rare but possible), auto-repeat a bounded number
        -- of times (a board whose remaining kinds can never pair must not loop).
        if attempts > 0 and not MahjongLogic.hasMoves(self.board)
            and MahjongLogic.tileCount(self.board) > 0 then
            self:shuffleBoard(true, attempts - 1)
        end
    end

    if force then
        do_shuffle()
    else
        UIManager:show(ConfirmBox:new{
            text        = _("Reshuffle remaining tiles?"),
            ok_text     = _("Shuffle"),
            ok_callback = do_shuffle,
        })
    end
end

-- US-19: long-press auto-solve -------------------------------------------------
--
-- Holding the Hint button for AUTO_SOLVE_HOLD_SECONDS starts a solver that
-- plays out matching free pairs one at a time until the board is cleared.
-- KOReader's `hold` gesture fires ~0.5 s after contact (the device-global
-- ges_hold_interval_ms), so it cannot be configured to fire at 10 s itself:
-- the hold callback ARMS a 10 s timer and the release hook DISARMS it if the
-- finger lifts early. The solver reuses the exact tap-path scoring/history/
-- save code (applyMatch), so an auto-solved game is indistinguishable from a
-- hand-played one. A board tap, a short Hint tap, Undo, or New Game stops it.

function Mahjong:armAutoSolve()
    if not self:getSetting("hints", SETTINGS_DEFAULTS.hints) then return end
    if MahjongLogic.isWin(self.board) then return end
    local token = self._auto_solve_token + 1
    self._auto_solve_token = token
    self:setFlash(_("Keep holding to auto-solve…"))
    UIManager:scheduleIn(AUTO_SOLVE_HOLD_SECONDS, function()
        if self._auto_solve_token == token then
            self:startAutoSolve()
        end
    end)
end

-- The finger lifted: cancel the pending 10 s arm. This also fires on the very
-- release that ends the successful hold — by then the solve is already running
-- (startAutoSolve bumped the token), so only a pending arm is cancelled.
function Mahjong:disarmAutoSolve()
    self._auto_solve_token = self._auto_solve_token + 1
    if not self._auto_solve_active then
        self:clearFlash()
    end
end

function Mahjong:startAutoSolve()
    if self._auto_solve_active then return end
    self._auto_solve_token = self._auto_solve_token + 1
    self._auto_solve_active = true
    -- The solver replays pairs far faster than a human, so start a clean undo
    -- history: a mid-solve shuffle moves tiles to different positions, which
    -- would scramble a long shared history under a later undo.
    self.history = {}
    self:clearSelection()
    self:setFlash(_("Auto-solving…"))
    self:autoSolveStep()
end

-- Stops the solver (and any pending arm). Called from board/hint taps, undo,
-- New Game, and close. Safe to call when nothing is running.
function Mahjong:stopAutoSolve()
    if not self._auto_solve_active then
        self._auto_solve_token = self._auto_solve_token + 1
        return
    end
    self._auto_solve_active = false
    self._auto_solve_token = self._auto_solve_token + 1
    self:clearFlash()
end

function Mahjong:autoSolveStep()
    if not self._auto_solve_active then return end
    if MahjongLogic.isWin(self.board) then
        self._auto_solve_active = false
        self:clearFlash()
        self:showWinDialog()
        return
    end
    local pair = MahjongLogic.matchingFreePair(self.board)
    if not pair then
        -- Dead board mid-solve: shuffle and carry on (mirrors the manual
        -- no-moves prompt). History is cleared first so the shuffle can't
        -- scramble it under a later undo; a bounded retry loop covers the
        -- (rare) shuffled board that is still dead.
        self.history = {}
        self:clearSelection()
        local attempts = 10
        repeat
            MahjongLogic.shuffleBoard(self.board)
            pair = MahjongLogic.matchingFreePair(self.board)
            attempts = attempts - 1
        until pair or attempts == 0
        self.board_view:updateBoard()
        if not pair then
            self:stopAutoSolve()
            return
        end
    end
    self:applyMatch(pair.a, pair.b)
    if MahjongLogic.isWin(self.board) then
        -- Cleared: handle the win immediately instead of scheduling a
        -- redundant no-op step (this is also the branch a stale step lands
        -- in, though none is scheduled once _auto_solve_active is cleared).
        self._auto_solve_active = false
        self:clearFlash()
        self:showWinDialog()
        return
    end
    UIManager:scheduleIn(AUTO_SOLVE_STEP_SECONDS, function()
        self:autoSolveStep()
    end)
end

-- Brief NON-BLOCKING feedback (US-09): `text` appears in the fixed band
-- between the board and the toolbar and auto-clears after FLASH_TIMEOUT.
-- The band is a plain text widget (not a modal dialog), so the board keeps
-- accepting taps while a message is showing — an accidental blocked-tile tap
-- can be corrected immediately. Each call bumps a sequence token; a stale
-- clear timer (e.g. from before a close/new game) is a no-op.
function Mahjong:flashMessage(text)
    self:setFlash(text)
    local seq = self._flash_seq
    UIManager:scheduleIn(FLASH_TIMEOUT, function()
        if self._flash_seq == seq then
            self:clearFlash()
        end
    end)
end

-- Sets a PERSISTENT message in the feedback band (no auto-clear): used while
-- the auto-solve arm/solve is active, where the text must stay until the
-- finger lifts or the solve stops (US-19). Bumps the sequence token so any
-- pending auto-clear for a previous message becomes a no-op.
function Mahjong:setFlash(text)
    local seq = (self._flash_seq or 0) + 1
    self._flash_seq = seq
    if self.flash_text then
        self.flash_text:setText(text)
        if self.flash_band_icon then
            -- ImageWidget:paintTo skips painting when `hide` is true (the
            -- `visible` field is ignored by KOReader widgets).
            self.flash_band_icon.hide = false
        end
        UIManager:setDirty(self, "ui")
    end
end

-- Clears the feedback band (called by the flash timer, the auto-solve paths,
-- and on close). Bumps the sequence token instead of niling it so the next
-- setFlash never has to add to a nil (the old `self._flash_seq + 1` crashed on
-- a second flash after a cleared one).
function Mahjong:clearFlash()
    self._flash_seq = (self._flash_seq or 0) + 1
    if self.flash_text and self.flash_text.text and self.flash_text.text ~= "" then
        self.flash_text:setText("")
        if self.flash_band_icon then
            self.flash_band_icon.hide = true
        end
        UIManager:setDirty(self, "ui")
    end
end

-- The HUD bar reflects the pairs left, the number of currently-matching free
-- pairs (legal moves available to tap), and the score — each in its own chip.
function Mahjong:updateStatus()
    if not self.status_bar then return end
    local pairs = math.floor(MahjongLogic.tileCount(self.board) / 2)
    local free = MahjongLogic.countFreePairs(self.board)
    self.status_bar:setStats(pairs, free, self.score)
    -- status_bar is a subwidget, so setDirty on it alone would not repaint;
    -- flag the window-level widget as well (same pattern as the chess example).
    UIManager:setDirty(self.status_bar, "ui")
    UIManager:setDirty(self, "ui")
end

function Mahjong:onCloseWidget()
    -- US-19: cancel a pending long-press arm / running solve (bumps the token
    -- so no stale step can fire into a closed widget).
    self:stopAutoSolve()
    self:saveGameState()
    self:stopTimer()
    self:clearFlash()
    self.selected = nil
    self.board_view = nil
    self.board = nil
end

return Mahjong
