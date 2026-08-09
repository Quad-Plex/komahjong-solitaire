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
local GetText = require("gettext")
local I18n = require("mahjongi18n")
local t = I18n.t
local MahjongLogic = require("mahjonglogic")
local MahjongStats = require("mahjongstats")
local MahjongBoard = require("mahjongboard")
local HudBar = require("hudbar")
local SettingsWidget = require("mahjongsettings")
local StatsWidget = require("mahjongstatswidget")
local PauseWidget = require("mahjongpause")
local LayoutSelect = require("mahjonglayoutselect")
local HelpWidget = require("mahjonghelp")
local WinSummary = require("mahjongwinsummary")
local MahjongUI = require("mahjongui")

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
-- tracks the kind and active-game time of the previous match for chain/combo
-- scoring. Combos only apply in Chain mode (score_method="chain").
-- FLASH_TIMEOUT: how long a non-blocking feedback message (e.g. "Tile is
-- blocked") stays visible in the band between the board and the toolbar.
local FLASH_TIMEOUT = 2
local COMBO_WINDOW_SECONDS = 5
local COMBO_PULSE_STEP_SECONDS = 0.5

-- A dead board gets several cheap candidate shuffles instead of accepting the
-- first random result.  Candidates are evaluated one per UI tick so the
-- e-ink UI remains responsive while the best arrangement is selected.
local DEAD_BOARD_SHUFFLE_CANDIDATES = 15
local DEAD_BOARD_SHUFFLE_STEP_SECONDS = 0

-- US-19: holding the Hint button for AUTO_SOLVE_HOLD_SECONDS starts an
-- automated solver that plays matching pairs until the board is cleared;
-- AUTO_SOLVE_STEP_SECONDS paces how fast the pairs are removed so each move
-- is visible on the e-ink refresh. US-33: while the solver runs, ALL input is
-- locked (silent no-ops), the game is flagged as auto-solved in its save, and
-- a reload of that save RESUMES the solver — there is no way to keep a
-- partial score.
local AUTO_SOLVE_HOLD_SECONDS = 10
local AUTO_SOLVE_STEP_SECONDS = 0.3

-- US-34: the hint no longer times out (it used to vanish after 2 s). On show
-- it does a brief boldness pulse — HINT_PULSE_TICKS steps swap the thin "hint"
-- and bold "hint_bold" corner-bracket overlays every HINT_PULSE_STEP_SECONDS,
-- starting and ending on the bold variant — then the highlight stays at bold
-- until the player acts (taps a tile, matches a pair, shuffles, etc.).
local HINT_PULSE_STEP_SECONDS = 0.5
local HINT_PULSE_TICKS = 6

-- Settings keys (persisted via LuaSettings in the KOReader settings dir).
-- score_method: "chain" (default, +5 for consecutive same-group matches) or
-- "basic" (flat 10 per pair). layout: the last-chosen layout id (US-14);
-- "turtle" today, US-15/16 add "spider"/"bridge".
-- timer_update: "interval" (repaint the mm:ss on a periodic polling loop,
-- default) or "move" (only repaint on board interaction, so an idle board
-- never forces an e-ink refresh). timer_interval: seconds between periodic
-- repaints (cosmetic; a 1 Hz e-ink repaint is overkill, 5 s is the default).
local SETTINGS_DEFAULTS = {
    language = "en",
    hints = true,               -- show hints on the toolbar / allow the Hint button
    score_method = "chain",     -- "chain" or "basic"
    layout = "turtle",
    timer_update = "interval",  -- "interval" or "move"
    timer_interval = 5,         -- seconds between periodic timer repaints
}

-- Smallest interval the timer loop will honor (dialog offers 1..60).
local MIN_TIMER_INTERVAL = 1

-- Tap-outside on a ConfirmBox normally runs `cancel_callback` — the same
-- action as the Close button. The shuffle / loss / win dialogs use
-- cancel_callback to EXIT the game, so a stray tap next to the dialog would
-- close the whole app (reported by users as a crash). This per-dialog
-- onTapClose override makes a tap outside do NOTHING — the dialog stays up
-- and only its buttons (Close keeps cancel_callback's documented action)
-- dismiss it.
local function dismissDialogOnTapOutside(opts)
    opts.onTapClose = function(_self, _, _ges)
        -- consume the stray tap; the dialog stays open. Only the dialog's own
        -- buttons (Close runs cancel_callback) dismiss it.
        return true
    end
    return opts
end

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

-- A tiny count number shown inside the Hint / Shuffle toolbar buttons'
-- bottom-right corner (how many times they've been used this game). It's a
-- bare dark number with no pill behind it, so it reads as a subtle readout
-- that doesn't crowd the icon. Shown directly as a real TextWidget child of
-- the button's OverlapGroup (a bare table can't be painted). Headless the
-- badge is created but the button's frame is a plain stub, so it is only
-- ever sized/painted on the device.
local function createCountBadge(value)
    return TextWidget:new{
        text = tostring(value),
        -- Reserve a stable slot; changing TextWidget text frees its cached
        -- size, which otherwise makes this tiny overlay unreliable on device.
        width = Screen:scaleBySize(18),
        height = Screen:scaleBySize(16),
        align = "right",
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(12)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
end

-- Toolbar action button: a rounded rectangle `w` x `h` — the WHOLE widget is
-- the tap area — with a square icon centered inside it, plus a small hint
-- label beneath (labels are omitted in compact mode). Padding keeps the icon
-- off the button edges, bordersize draws
-- a slim rounded border, and radius rounds the corners. The icon button and
-- its label are stacked in a VerticalGroup so each toolbar cell carries a
-- caption (Undo / Hint / Shuffle / New Game). The cells are separated by
-- HorizontalSpan spacers in buildUILayout() (the stock HorizontalGroup ignores
-- any `spacing` field).
--
-- Optional `hold_cb` / `hold_release_cb` turn the button into a LongPressButton
-- (long-press arm + release hook, used by the Hint button's auto-solver).
-- Optional `counter` (a number) drops the small count pill in the button's
-- bottom-right corner and attaches it as `button.badge` for updates.
-- Returns the cell (the VerticalGroup), the ButtonWidget itself (so tests can
-- reach the hold callbacks), and the badge (or nil).
local function createToolbarButton(icon, label, w, h, cb, hold_cb, hold_release_cb, counter, hide_label)
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
    local badge = nil
    if counter ~= nil then
        badge = createCountBadge(counter)
        -- Keep the badge as a sibling of the Button frame. KOReader's button
        -- feedback inverts the entire frame rectangle; a badge inside that
        -- frame becomes white and appears to disappear after a press.
        local bsz = badge:getSize()
        local button_size = button_opts:getSize()
        local corner = Screen:scaleBySize(2)
        badge.overlap_offset = {
            button_size.w - bsz.w - corner,
            button_size.h - bsz.h - corner + Screen:scaleBySize(3),
        }
        button_opts.badge = badge
    end
    local button_layer = button_opts
    if badge then
        button_layer = OverlapGroup:new{
            dimen = Geometry:new{ w = button_opts:getSize().w, h = button_opts:getSize().h },
            button_opts,
            badge,
        }
        -- Preserve the button's structural metadata on the visual layer for
        -- callers that inspect toolbar cells rather than the live Button
        -- reference returned below.
        button_layer.bordersize = button_opts.bordersize
        button_layer.radius = button_opts.radius
        button_layer.padding = button_opts.padding
        button_layer.icon = button_opts.icon
        button_layer.callback = button_opts.callback
    end
    local cell
    if hide_label then
        cell = VerticalGroup:new{ align = "center", button_layer }
    else
        local label_widget = TextWidget:new{
            text = label,
            padding = 0,
            face = Font:getFace("smallinfofont", Screen:scaleBySize(11)),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        cell = VerticalGroup:new{
            align = "center",
            button_layer,
            label_widget,
        }
    end
    return cell, button_opts, badge
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
    last_match_elapsed = nil, -- active-game time of the last pair (combo scoring)
    combo_chain = 0, -- consecutive fast-clear count (the first combo is 1)
    history = nil, -- stack of { a, b, ka, kb, score, prev_last }
    settings = nil, -- LuaSettings handle (US-10)
    score_method = "chain", -- "chain" or "basic" (settings, defaulted for tests)
    stats = nil, -- lifetime stats record (US-12), loaded in init()
    game_won = false, -- true once the CURRENT game is won by the player (US-12)
    game_was_autosolved = false, -- set by startAutoSolve; gates stats recording (US-12/US-19)
    pairs_matched = 0, -- pairs removed this game (72 on a full win; the auto-solver
                       -- replays pairs into a cleared history, so this is tracked
                       -- apart from the undo stack) (US-12)
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
    _shuffle_active = false, -- true while a dead-board candidate search is running
    _shuffle_token = 0,
    _last_hint = nil, -- the last hinted pair { a, b }, so repeated Hint presses cycle (US-08);
                      -- also gates the once-per-session hint penalty (US-20); the highlight now
                      -- persists (no 2 s timeout) until the player acts (US-34)
    _hint_pulse_token = 0, -- monotonic token for the hint boldness pulse (US-34): a stale tick
                           -- (after clearHint/undo/close/new-game) is a no-op
    hint_button = nil, -- the toolbar Hint ButtonWidget (exposes hold callbacks, US-19)
    pause_button = nil, -- the toolbar Pause ButtonWidget (US-17/US-20)
    hints_used = 0, -- per-game hints actually shown (US-18; persisted in the game state)
    shuffles_used = 0, -- per-game user-initiated shuffles (US-18; persisted)
    _pause_dlg = nil, -- the pause overlay while it is up (US-17)
    layout = "turtle", -- current layout id (US-14); saved with the game state
    _picker_dlg = nil, -- the layout picker while it is up (US-14)
    _help_dlg = nil, -- gameplay help above the layout picker
}

function Mahjong:init()
    MahjongUI.refreshDimensions(self)
    self.history = {}
    self.dimensions = Geometry:new{
        w = self.full_width,
        h = self.full_height,
    }
    self.covers_fullscreen = true
    -- US-10: one LuaSettings file for both the game state and the settings.
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/mahjong.lua")
    local saved_language = self.settings:readSetting("language", nil)
    if saved_language == nil then
        -- Respect KOReader's locale only for the initial default. Once the
        -- user has chosen a language, that explicit preference wins.
        saved_language = I18n.languageForLocale(GetText.current_lang)
        self.settings:saveSetting("language", saved_language)
        self.settings:flush()
    end
    I18n.setLanguage(saved_language or SETTINGS_DEFAULTS.language)
    Dispatcher:registerAction("mahjong", {
        category = "none",
        event = "MahjongStart",
        title = t("app.name"),
        general = true,
    })
    self.ui.menu:registerToMainMenu(self)
    installIconsIfNeeded()
    -- US-12: lifetime stats live under their own "stats" key (saveStats), so a
    -- win or a restore never touches them. A corrupt/missing record silently
    -- falls back to a fresh one (MahjongStats.load sanitizes).
    self.stats = MahjongStats.load(self.settings:readSetting("stats", nil))
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

function Mahjong:setLanguage(language)
    language = I18n.setLanguage(language)
    self:setSetting("language", language)
    return language
end

function Mahjong:refreshScoreMethod()
    self.score_method = self:getSetting("score_method", SETTINGS_DEFAULTS.score_method)
end

-- US-12: lifetime stats are persisted under their own "stats" key, separate
-- from the "game" key (a win or a restore never touches the game save). Every
-- mutation flushes immediately so a win or a new game survives an abrupt exit.
function Mahjong:saveStats()
    if not self.settings or not self.stats then return end
    self.settings:saveSetting("stats", self.stats)
    self.settings:flush()
end

-- US-12: every fresh deal (plugin launch with no saved game, or a New Game)
-- is recorded in the lifetime stats: games_played bumps, and when the PREVIOUS
-- game was abandoned (not won) the winning streak resets. `self.game_won` still
-- holds the previous game's outcome at this point (set by showWinDialog); it is
-- cleared for the new game afterwards, along with the auto-solve flag.
function Mahjong:noteNewGame()
    if self.stats then
        MahjongStats.startGame(self.stats, self.game_won, self.layout)
        self:saveStats()
    end
    self.game_won = false
    self.game_was_autosolved = false
end

function Mahjong:addToMainMenu(menu_items)
    menu_items.mahjong = {
        text = t("app.name"),
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
        self.layout = restored.layout or "turtle"
        self.board = restored.board
        self.history = restored.history
        self.score = restored.score
        self.last_match_kind = restored.last_match_kind
        self.last_match_elapsed = restored.last_match_elapsed
        self.combo_chain = restored.combo_chain or 0
        self.elapsed_base = restored.elapsed
        -- US-18: the per-game help counters ride along in the saved state.
        self.hints_used = restored.hints_used or 0
        self.shuffles_used = restored.shuffles_used or 0
        -- A restored game has no fresh deal; the pair count for the win
        -- summary comes from the restored undo stack (US-12).
        self.pairs_matched = #restored.history
        self.selected = nil
        self._last_hint = nil -- the hint cycle starts fresh for this session
        -- US-33: a tainted save (the solver ran before a close/crash) must stay
        -- tainted across reloads — and, below, its solve is resumed.
        self.game_was_autosolved = restored.autosolved == true
        self._timer_running = false
        self:buildUILayout()
        self:updateStatus()
        self:updateTimerDisplay()
        self:startTimer()
        -- Queue the first paint as well as the framebuffer update. Without a
        -- refresh mode, a restored game can remain invisible until unrelated
        -- input happens to trigger another refresh.
        UIManager:show(self, "ui", self.dimensions)
        -- US-33: a tainted save resumes the solver — there is no avoiding it
        -- once triggered. The solver shuffles dead boards itself, so the
        -- hasMoves check below is skipped for it.
        if self.game_was_autosolved then
            UIManager:nextTick(function() self:startAutoSolve() end)
        elseif not MahjongLogic.hasMoves(self.board, self.layout) then
            -- US-32: a restored dead board must be recognized at launch (saved a
            -- dead game, closed, re-opened — the player should not face a silent
            -- dead board).
            self:handleNoMoves()
        end
    else
        -- US-14: no saved game (first launch, or the save was cleared). Show
        -- the layout picker instead of dealing a default board; the chosen
        -- layout deals the game via startGameWithLayout.
        self:showLayoutPicker()
    end
end

-- US-14: shows the full-screen layout picker. Pauses the timer (if running)
-- so the polling loop does not flash behind the opaque picker; the picker's
-- onClose resumes it (or exits, see below). Used by startGame (first launch),
-- the New Game button, and the win dialog's "Select Layout" — choosing a layout
-- IS the confirmation, so the old New Game ConfirmBox is gone.
function Mahjong:showLayoutPicker()
    -- US-33: the New Game button is dead while the auto-solver runs (dropping
    -- to the picker would abandon a tainted solve and farm its partial score).
    -- Win/dead-board dialogs only reach this after the solve is over.
    if self._auto_solve_active then return end
    self:stopAutoSolve()
    self:stopTimer()
    self._picker_dlg = LayoutSelect:new{
        full_width = self.full_width,
        full_height = self.full_height,
        parent = self,
        wins_by_layout = (self.stats and self.stats.layout_wins) or {},
        highscores_by_layout = (self.stats and self.stats.layout_highscores) or {},
        best_times_by_layout = (self.stats and self.stats.layout_best_times) or {},
        onPick = function(id) self:startGameWithLayout(id) end,
        onHelp = function() self:showHelp() end,
        onSettings = function() self:openSettings() end,
        onClose = function()
            self._picker_dlg = nil
            if self.board and not MahjongLogic.isWin(self.board) then
                -- Active board under the picker (New Game / dead-board path):
                -- closing the picker resumes the running game.
                self:startTimer()
                self:updateTimerDisplay()
            elseif self.board then
                -- Won (empty) board under the picker (the Play-again flow):
                -- closing the picker must EXIT the game — the board is already
                -- cleared, so returning to it would strand the player on an
                -- empty board. The picker's own close (also "full") merges
                -- with this refresh.
                UIManager:close(self, "full")
            end
        end,
    }
    self._picker_dlg:show()
end

function Mahjong:showHelp()
    if self._help_dlg then return end
    self._help_dlg = HelpWidget:new{
        full_width = self.full_width,
        full_height = self.full_height,
        onClose = function() self._help_dlg = nil end,
    }
    UIManager:show(self._help_dlg)
end

-- US-14: deals a fresh game on the chosen layout and shows the game (or
-- rebuilds it if already shown). Called by the picker's onPick.
function Mahjong:startGameWithLayout(id)
    -- Drop the picker first; its onClose hook would otherwise resume the
    -- timer for the OLD board, which we're about to replace. "full" so the
    -- close enqueues a real refresh (a bare close leaves the e-ink stale;
    -- see the LayoutSelect:closeDialog note) — it merges with the setDirty
    -- below instead of double-flashing.
    if self._picker_dlg then
        local dlg = self._picker_dlg
        self._picker_dlg = nil
        UIManager:close(dlg, "full")
    end
    if not MahjongLogic.layouts[id] then id = "turtle" end
    self.layout = id
    -- Persist the choice as the last-chosen default.
    self:setSetting("layout", id)
    self.board = MahjongLogic.newGame(id)
    self.selected = nil
    self.score = 0
    self.last_match_kind = nil
    self.last_match_elapsed = nil
    self.combo_chain = 0
    self.history = {}
    self.pairs_matched = 0
    self.hints_used = 0
    self.shuffles_used = 0
    self._last_hint = nil
    self:refreshScoreMethod()
    self.elapsed_base = 0
    self._timer_running = false
    self:noteNewGame()
    self:buildUILayout()
    self:updateStatus()
    self:updateTimerDisplay()
    self:startTimer()
    -- If the game widget is already on the stack (New Game / Play again path),
    -- a fresh UIManager:show would duplicate it; only show when absent.
    local already_shown = false
    if UIManager.isWidgetShown and UIManager:isWidgetShown(self) then
        already_shown = true
    end
    if not already_shown then
        -- A show without a refresh mode paints the new window but does not
        -- enqueue a framebuffer refresh. This matters when the picker was the
        -- only window on the stack. The game is mixed content, so a regional
        -- UI refresh is enough and avoids a high-fidelity full-screen flash.
        UIManager:show(self, "ui", self.dimensions)
    else
        -- The child tree was rebuilt completely. A restart is a whole-canvas
        -- change (a cleared, "empty" board becomes 144 tiles again), which a
        -- regional refresh does not ink cleanly: the EPDC's partial update can
        -- wash the frame out to an almost-empty board (the "Play again shows
        -- a blank board" report). Defer a single high-fidelity full-screen
        -- refresh to after the modal's clear repaint has drained, and re-drive
        -- the window with the new tree immediately too.
        UIManager:setDirty(self, "ui", self.dimensions)
        self:scheduleFullScreenRefresh()
    end
    -- Save-after-every-move model: a New Game immediately replaces the old
    -- saved state (which was cleared), so a close/reopen resumes the fresh
    -- board rather than resurrecting the previous game.
    self:saveGameState()
end

-- US-45: one high-fidelity full-screen refresh after a same-layout restart
-- (the win/dead-board dialog's "Play again" -> startGameWithLayout while the
-- game window is already shown).
--
-- The two asymmetrical halves of a restart make a regional refresh lie:
-- the board the EPDC last drew for this window is EMPTY (the dialog served as
-- a won board), and the new tree is a full 144-tile canvas. A regional "ui"
-- partial over that delta comes up as an almost-empty board. Deleting it with
-- a "full" (GC16) refresh of the whole window after the window is actually
-- painted back to a well-formed state.
--
-- It is deferred (not issued inline in startGameWithLayout) for an ordering
-- reason: the "Play again" callback runs while the win dialog is still on the
-- window stack (KOReader fires the dialog's ok_callback before closing it), so
-- an immediate refresh is driven from a window whose paint KOReader has not
-- yet completed for the closing dialog repaint. One tick later the dialog is
-- gone and the new canvas has repainted, at which point a single full flash
-- inks the fresh board crisply.
--
-- Guarded by a board identity so a closed/replaced game (or a second restart
-- arriving before the tick) can never fire a stale refresh into a new window.
function Mahjong:scheduleFullScreenRefresh()
    if not UIManager.tickAfterNext then return end
    if self._full_screen_refresh_scheduled then return end
    self._full_screen_refresh_scheduled = true
    local board = self.board
    UIManager:tickAfterNext(function()
        self._full_screen_refresh_scheduled = false
        if self.board ~= board or not self.board_view then return end
        -- Full-screen high-veracity waveform over the whole window: this is the
        -- expensive e-ink flash the picker/close paths already use on purpose.
        UIManager:setDirty(self, "full", self.dimensions)
    end)
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
            self.last_match_kind, self:getElapsed(),
            self.hints_used, self.shuffles_used, self.layout,
            self.game_was_autosolved, self.last_match_elapsed, self.combo_chain)
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
-- SETTING only controls when the DISPLAY repaints, and it is EXCLUSIVE —
-- one source of repaints per mode, never both:
--   * "interval" (default): a polling loop (the kochess pollingLoop pattern)
--     repaints every timer_interval seconds (default 5 — 1 Hz is overkill for
--     e-ink). The loop is the ONLY thing that repaints the mm:ss; an
--     interaction only updates the text string (so the next periodic tick
--     shows the true value) without enqueuing its own regional repaint into
--     the same framebuffer batch as a board mutation.
--   * "move": no polling loop; the display is repainted from the interaction
--     handlers (select/deselect/match/undo/shuffle) so an idle board never
--     forces an e-ink refresh.
-- The exclusivity also fixes a half-refreshed board: in the old code the
-- interaction callbacks repainted the timer region unconditionally, so a
-- periodic "interval" repaint and a pair clear could enqueue two regional
-- refreshes in the same batch — the timer refill raced the pair's structural
-- refresh retry and left the board partially rendered on e-ink. Separating
-- the text update from the regional repaint (and deferring the periodic tick
-- while a structural tile refresh is pending) gives each mode exactly one
-- regional refresh source.
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
    -- US-34: resume the hint's boldness pulse too (only when a hint is active).
    -- The pulse is an animation loop just like the polling loop below, so it
    -- must not run while the board is covered by an overlay: every stopTimer
    -- site (pause/settings/stats/picker/dialogs/close) stops it and every
    -- startTimer site (resume/new-game/restore) restarts it — mirroring the
    -- polling loop's lifecycle so a pulse can never repaint behind a panel.
    if self._last_hint and self.board_view then
        self:startHintPulse(self._last_hint)
    end
    if self:timerMode() ~= "interval" then
        -- "move" mode: no polling loop; interactions refresh the display.
        return
    end
    local interval = self:timerInterval()
    local tick
    tick = function()
        if self._timer_running and self._timer_run_id == run_id then
            -- US-41: when a pair was just cleared its structural tile refresh
            -- (and any coalesced retry) is still pending in the refresh queue.
            -- Defer this periodic repaint by one interval so the timer refill
            -- cannot be enqueued into the same framebuffer batch as the board
            -- mutation — that race left the board half-rendered on e-ink.
            if self.board_view and self.board_view.has_pending_refresh_retry
                    and self.board_view:has_pending_refresh_retry() then
                UIManager:scheduleIn(interval, tick)
                return
            end
            self:refreshTimerDisplay()
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
    -- US-34: stop the hint's boldness pulse (see startTimer). Bumping the token
    -- invalidates any pending pulse tick so it can't repaint behind a floating
    -- overlay or a closed widget.
    self._hint_pulse_token = self._hint_pulse_token + 1
end

function Mahjong:resetTimer()
    self:stopTimer()
    self.elapsed_base = 0
    self:startTimer()
end

-- Pure text update: sets the mm:ss string without enqueuing any repaint.
-- Used by interaction handlers in "interval" mode, so the widget's text is
-- always current for the next periodic repaint without the interaction
-- racing a regional refresh into the same batch as the board mutation.
function Mahjong:updateTimerText()
    if not self.timer_text then return end
    self.timer_text:setText(MahjongLogic.formatElapsed(self:getElapsed()))
    if self.timer_text.resetLayout then self.timer_text:resetLayout() end
end

-- Text update + a regional repaint of the timer slot. This is the ONLY
-- regional refresh source per timer mode: the periodic polling loop in
-- "interval" mode, or the interaction handlers in "move" mode (via
-- updateTimerDisplay). Keeping one source per mode is what prevents the
-- timer refill from racing a structural board refresh.
function Mahjong:refreshTimerDisplay()
    if not self.timer_text then return end
    self:updateTimerText()
    -- Use the known feedback-band region even before KOReader has painted the
    -- child and populated timer_text.dimen.
    UIManager:setDirty(self, "ui", self.timer_region or self.flash_region or self.timer_text.dimen)
    -- Bake the chrome before the refresh drains so the EPDC reads current
    -- pixels (never a stale/blank toolbar row — see bakeLowerChrome).
    self:bakeLowerChrome()
end

-- Interaction entry point: repaints the timer region ONLY in "move" mode.
-- In "interval" mode the periodic loop is the sole repaint source, so an
-- interaction updates the text (see updateTimerText) but enqueues no timer
-- refresh — it must not piggyback a regional refresh onto the same batch as
-- a pair clear / undo / shuffle mutation.
function Mahjong:updateTimerDisplay()
    self:updateTimerText()
    if self:timerMode() == "move" then
        UIManager:setDirty(self, "ui", self.timer_region or self.flash_region or self.timer_text.dimen)
        self:bakeLowerChrome()
    end
end

-- Settings dialog (US-10) ---------------------------------------------------

function Mahjong:openSettings()
    -- US-33: the settings gear is dead while the auto-solver runs (the solver
    -- would keep moving tiles behind the floating panel otherwise).
    if self._auto_solve_active then return end
    -- Freeze the clock and stop the polling loop while the dialog is up: the
    -- settings dialog floats over the game now, and a periodic full-screen
    -- refresh (US-11 "interval" mode) would flash every tick behind the panel.
    -- Save restarts via onApply, Cancel / tap-outside via onCancel.
    local picker_was_open = self._picker_dlg ~= nil
    self:stopTimer()
    local dlg = SettingsWidget:new{
        full_width = self.full_width,
        full_height = self.full_height,
        parent = self,
        settings_defaults = SETTINGS_DEFAULTS,
        onApply = function(changes)
            local language_changed = changes.language ~= I18n.getLanguage()
            if language_changed then
                self:setLanguage(changes.language)
            end
            if language_changed and picker_was_open then
                local old_picker = self._picker_dlg
                self._picker_dlg = nil
                if old_picker then UIManager:close(old_picker, "full") end
                self:showLayoutPicker()
            elseif language_changed and self.board then
                self:buildUILayout()
                self:updateStatus()
                UIManager:setDirty(self, "ui", self.dimensions)
            end
            self:refreshScoreMethod()
            self:updateStatus()
            -- The timer mode/interval may have changed (US-11): restart the
            -- polling loop. stopTimer freezes elapsed_base, startTimer resumes.
            self:stopTimer()
            -- A language change rebuilds an open picker. Keep polling stopped
            -- until the picker is picked or closed; it is opaque and has no
            -- active game surface to update.
            if not self._picker_dlg then self:startTimer() end
            self:updateTimerDisplay()
        end,
        onCancel = function()
            if not picker_was_open then
                self:startTimer()
                self:updateTimerDisplay()
            end
        end,
    }
    dlg:show()
end

-- Stats screen (US-13) -------------------------------------------------------

function Mahjong:openStats()
    -- US-33: the stats card is dead while the auto-solver runs (same reason as
    -- openSettings: the solver must not keep moving tiles behind the panel).
    if self._auto_solve_active then return end
    -- Freeze the clock and stop the polling loop while the card is up (the
    -- same reason openSettings does): a periodic full-screen refresh (US-11
    -- "interval" mode) would flash every tick behind the panel. Any close
    -- (tap-outside or the panel's X) resumes via onClose.
    self:stopTimer()
    local dlg = StatsWidget:new{
        full_width = self.full_width,
        full_height = self.full_height,
        parent = self,
        onClose = function()
            self:startTimer()
            self:updateTimerDisplay()
        end,
    }
    dlg:show()
end

-- Pause (US-17) --------------------------------------------------------------

function Mahjong:pauseGame()
    -- US-33: Pause is dead while the auto-solver runs — the solve must run to
    -- completion (interrupting it is how a partial score used to be saved).
    if self._auto_solve_active then return end
    -- A won game has no play left to pause (defensive: the win dialog already
    -- covers that screen, so the HUD pause button is unreachable anyway).
    if MahjongLogic.isWin(self.board) then return end
    -- Freeze the clock (freezes elapsed_base) and stop the polling loop; the
    -- overlay below consumes every tap, so no tile can be selected or moved
    -- while paused. Resume restarts via the overlay's onResume hook.
    self:stopTimer()
    if self.board_view and self.board_view.setPaused then
        self.board_view:setPaused(true)
    end
    -- Paint the replacement faces before putting the transparent modal on top;
    -- otherwise the modal can be shown from the old framebuffer even though
    -- the parent window is marked dirty.
    if UIManager.forceRePaint then
        UIManager:forceRePaint()
    end
    local dlg = PauseWidget:new{
        full_width = self.full_width,
        full_height = self.full_height,
        parent = self,
        onResume = function()
            self._pause_dlg = nil
            if self.board_view and self.board_view.setPaused then
                self.board_view:setPaused(false)
            end
            if UIManager.forceRePaint then
                UIManager:forceRePaint()
            end
            self:startTimer()
            self:updateTimerDisplay()
        end,
    }
    self._pause_dlg = dlg
    dlg:show()
end

function Mahjong:buildUILayout()
    -- Screen dimensions can change when KOReader rotates a phone. Re-read them
    -- before rebuilding so the board and all surrounding chrome use one canvas.
    MahjongUI.refreshDimensions(self)
    self.dimensions = Geometry:new{ w = self.full_width, h = self.full_height }
    self.status_bar = self:createStatusBar()
    local status_h = self.status_bar:getSize().h
    -- Keep stable screen-space regions for non-board updates. Child `dimen`
    -- values are not guaranteed to exist until the first paint; passing nil to
    -- UIManager:setDirty would otherwise request a regionless refresh.
    self.status_region = Geometry:new{
        x = 0, y = 0, w = self.full_width, h = status_h,
    }

    -- Toolbar is 48px tall (rounded bordered buttons) with a small hint label
    -- under each icon, small gaps between the buttons, edge gaps so the outer
    -- buttons don't scrape the screen sides, and a bottom spacer that lifts
    -- the row off the screen edge; the board fills what remains.
    local compact_toolbar = MahjongUI.isNarrow(self.full_width)
    local toolbar_btn_h = math.min(Screen:scaleBySize(compact_toolbar and 44 or 48),
        math.max(Screen:scaleBySize(30), math.floor(self.full_height * 0.10)))
    local toolbar_gap = Screen:scaleBySize(6)
    -- 6 gaps: one at each edge + 4 between the 5 buttons.
    local toolbar_btn_w = math.max(1, math.floor((self.full_width - 6 * toolbar_gap) / 5))
    -- Probe the hint-label height so the toolbar row reserves room for it.
    local label_probe = TextWidget:new{
        text = "Ag",
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(11)),
    }
    local label_h = compact_toolbar and 0 or label_probe:getSize().h
    label_probe:free()
    local toolbar_h = toolbar_btn_h + label_h
    local bottom_gap = Screen:scaleBySize(12)
    -- Feedback band (US-09): a fixed-height strip between the board and the
    -- toolbar where brief non-blocking messages appear. The slot is always
    -- reserved so the board geometry stays stable when a message shows/clears.
    -- Font is kept small (~0.8× HUD labels) so it reads as a subtle notice;
    -- height is probed from the font so it fits any DPI.
    local flash_font_size = Screen:scaleBySize(compact_toolbar and 22 or 30)
    local flash_probe = TextWidget:new{
        text = "Ag",
        padding = 0,
        face = Font:getFace("smallinfofont", flash_font_size),
    }
    local flash_text_h = flash_probe:getSize().h
    flash_probe:free()
    local flash_pad_top = Screen:scaleBySize(4)
    local flash_pad_bottom = Screen:scaleBySize(compact_toolbar and 8 or 14)
    local flash_h = flash_text_h + flash_pad_top + flash_pad_bottom
    local board_h = math.max(Screen:scaleBySize(80),
        self.full_height - status_h - flash_h - toolbar_h - bottom_gap)
    self.flash_region = Geometry:new{
        x = 0, y = status_h + board_h, w = self.full_width, h = flash_h,
    }
    self.toolbar_region = Geometry:new{
        x = 0, y = status_h + board_h + flash_h,
        w = self.full_width, h = toolbar_h + bottom_gap,
    }
    -- The banner (flash band + timer) sits directly above the toolbar and
    -- shares an edge with it, so KOReader's open-range refresh merge
    -- (uimanager.lua `_refresh`: rects sharing an edge are combined) would
    -- collapse any banner+toolbar pair, and often the board's tile rects too,
    -- into ONE ioctl per batch. When that merged rect is driven while the
    -- board's own structural update settles, the EPDC can half-apply it and
    -- leave the action-button row outside the rect — i.e. the "band repainted,
    -- buttons blank" artifact. Give the whole lower chrome (banner + toolbar)
    -- ONE explicit rect so a refresh can never stop short of the toolbar row.
    self.lower_band_region = Geometry:new{
        x = 0,
        y = self.flash_region.y,
        w = self.full_width,
        h = self.full_height - self.flash_region.y,
    }

    self.board_view = MahjongBoard:new{
        board = self.board,
        layout_id = self.layout,
        width = self.full_width,
        height = board_h,
        -- UIManager only repaints window-level widgets, so board mutations
        -- must target this owning game window.
        show_parent = self,
        refresh_origin_x = 0,
        refresh_origin_y = status_h,
        onTileTap = function(x, y, layer) self:handleTileTap(x, y, layer) end,
        onEmptyTap = function()
            -- US-33: an empty-area board tap is still an input — during a
            -- solve it must be a silent no-op just like a tile tap.
            if self._auto_solve_active then return end
            self:clearSelection()
        end,
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
    local timer_x = self.full_width - timer_slot_w - band_edge_pad - Screen:scaleBySize(4)
    self.timer_region = Geometry:new{
        x = timer_x, y = self.flash_region.y,
        w = timer_slot_w + band_edge_pad + Screen:scaleBySize(4), h = flash_h,
    }
    self.timer_text = TextWidget:new{
        text = MahjongLogic.formatElapsed(0),
        padding = 0,
        face = Font:getFace("smallinfofont", flash_font_size),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        -- Array-form offset on the widget itself (OverlapGroup contract, see
        -- the board's tile widgets). Right-aligned to the band edge with the
        -- same margin the warning icon uses on the left.
        overlap_offset = {
            timer_x,
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
    -- the test harness can drive the hold callbacks. The small counter pill
    -- shows how many hints this game has used.
    local hint_cell, hint_button, hint_badge = createToolbarButton(
        "mahjong/lightbulb", t("toolbar.hint"), toolbar_btn_w, toolbar_btn_h,
        function() self:showHint() end,
        function() self:armAutoSolve() end,
        function() self:disarmAutoSolve() end,
         self.hints_used or 0, compact_toolbar)
    self.hint_button = hint_button
    self.hint_counter_badge = hint_badge

    -- The Shuffle button carries the same count pill for shuffles_used.
    local shuffle_cell, shuffle_button, shuffle_badge = createToolbarButton(
        "mahjong/shuffle", t("toolbar.shuffle"), toolbar_btn_w, toolbar_btn_h,
         function() self:shuffleBoard() end, nil, nil, self.shuffles_used or 0, compact_toolbar)
    self.shuffle_button = shuffle_button
    self.shuffle_counter_badge = shuffle_badge

    -- US-17/US-20: Pause moved off the cluttered HUD top bar into the bottom
    -- action-button row (the fifth button). The pause overlay still freezes the
    -- clock and blocks every tap until Resume.
    local pause_cell, pause_button = createToolbarButton(
        "mahjong/pause", t("toolbar.pause"), toolbar_btn_w, toolbar_btn_h,
         function() self:pauseGame() end, nil, nil, nil, compact_toolbar)
    self.pause_button = pause_button

    local toolbar = HorizontalGroup:new{
        HorizontalSpan:new{ width = toolbar_gap },
         createToolbarButton("chevron.left", t("toolbar.undo"), toolbar_btn_w, toolbar_btn_h,
            function() self:undo() end, nil, nil, nil, compact_toolbar),
        HorizontalSpan:new{ width = toolbar_gap },
        hint_cell,
        HorizontalSpan:new{ width = toolbar_gap },
        shuffle_cell,
        HorizontalSpan:new{ width = toolbar_gap },
         createToolbarButton("plus", t("toolbar.new_game"), toolbar_btn_w, toolbar_btn_h, function()
             self:showLayoutPicker()
         end, nil, nil, nil, compact_toolbar),
        HorizontalSpan:new{ width = toolbar_gap },
        pause_cell,
        HorizontalSpan:new{ width = toolbar_gap },
    }
    -- Keep the raw toolbar so the lower-chrome bake can repaint it
    -- immediately (see bakeLowerChrome below) instead of waiting for the
    -- dirty queue.
    self.toolbar_widget = toolbar

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
    -- HUD top bar (hudbar.lua): two left buttons (settings gear + stats card
    -- (US-13)) + title + three stat chips (Pairs / Free / Score) + the quit X
    -- (right). Pause (US-17) lives in the bottom toolbar (US-20). updateStatus()
    -- pushes the values via setStats().
    return HudBar:new{
            full_width            = self.full_width,
            title                  = t("app.name"),
        left_icons = {
            { icon = "appbar.settings", size_ratio = 0.45,
              callback = function() self:openSettings() end },
            { icon = "mahjong/stats", size_ratio = 0.45,
              callback = function() self:openStats() end },
        },
        right_icon             = "mahjong/close",
        right_icon_size_ratio  = 0.9,
        right_icon_tap_callback = function()
            -- US-33: the quit X is dead while the auto-solver runs — closing
            -- mid-solve used to save a partial score that could be finished
            -- by hand on the next launch.
            if self._auto_solve_active then return end
            UIManager:show(ConfirmBox:new{
                text        = t("game.exit_confirm"),
                ok_text     = t("toolbar.exit"),
                ok_callback = function()
                    -- Returning to the file manager only needs the normal UI
                    -- waveform; avoid a high-fidelity full-screen flash for a
                    -- routine exit.
                    UIManager:close(self, "ui", self.dimensions)
                end,
            })
        end,
    }
end

-- US-14: resetGame is now a thin wrapper over startGameWithLayout for the
-- current layout (the production New Game / Play again path goes through the
-- picker -> startGameWithLayout). Kept so the headless tests that drive a
-- direct reset (e.g. us18's counter reset) still work.
function Mahjong:resetGame()
    self:startGameWithLayout(self.layout or "turtle")
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
    -- US-33: a board tap while the auto-solver is running is consumed and
    -- ignored — the solver owns the board until it finishes. (US-19's old
    -- "interrupt the solve" behavior is gone: an interrupt let a close/
    -- reopen farm the partial score.)
    if self._auto_solve_active then
        return
    end
    -- US-34: the hint is persistent, so any tile tap dismisses it (the player
    -- is now acting; a tap on empty/blocked space clears it too — re-hinting
    -- is one press away).
    self:clearHint()
    local kind = MahjongLogic.tileAt(self.board, x, y, layer)
    if not kind then return end
    if not MahjongLogic.isFree(self.board, x, y, layer) then
        self:flashMessage(t("game.blocked"))
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
    -- US-20: clearing a pair ends the current hint session — the next hint
    -- press starts a new one and pays HINT_PENALTY once again. (Auto-solve
    -- steps call applyMatch too, so a solved board also resets the session.)
    -- US-34: clearHint also drops the persistent hint highlight/pulse (a hint
    -- is guidance, and the player just acted).
    self:clearHint()
    self.board_view:removePair(a, b)
    local prev_last = self.last_match_kind
    local prev_match_elapsed = self.last_match_elapsed
    local now_elapsed = self:getElapsed()
    -- Auto-solve paces its own moves and keeps the persistent "Auto-solving…"
    -- message; combos are a reward for the player's fast clears. Combos only
    -- apply in Chain mode — the Basic score method disables both the group
    -- chain bonus and the combo bonus.
    local chain_enabled = self.score_method == "chain"
    local combo = chain_enabled
        and not self._auto_solve_active
        and prev_match_elapsed ~= nil
        and now_elapsed >= prev_match_elapsed
        and now_elapsed - prev_match_elapsed <= COMBO_WINDOW_SECONDS
    local combo_chain = combo and ((self.combo_chain or 0) + 1) or 0
    local points
    if chain_enabled then
        points = MahjongLogic.pairPoints(prev_last, ka)
    else
        points = MahjongLogic.SCORE_PER_PAIR
    end
    if combo then
        points = points + MahjongLogic.COMBO_BONUS
            + (combo_chain - 1) * MahjongLogic.COMBO_INCREMENT
    end
    self.last_match_kind = ka
    self.last_match_elapsed = now_elapsed
    self.combo_chain = combo_chain
    self.score = self.score + points
    self.pairs_matched = (self.pairs_matched or 0) + 1
    table.insert(self.history, {
        a = a, b = b, ka = ka, kb = kb, score = points, prev_last = prev_last,
    })
    self:updateStatus()
    self:updateTimerDisplay()
    if combo then
        local combo_points = MahjongLogic.COMBO_BONUS
            + (combo_chain - 1) * MahjongLogic.COMBO_INCREMENT
        local label = combo_chain == 1 and t("game.combo") or t("game.combo_chain")
        self:flashMessage(string.format(label, combo_points), true)
    end
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

-- US-32: centralized no-moves handler.  Called from checkGameState (after
-- every match), showHint's dead branch, and startGame's restore branch.
-- If the board is provably dead the loss dialog skips the shuffle offer
-- entirely; otherwise the existing shuffle prompt still runs.
function Mahjong:handleNoMoves()
    if MahjongLogic.isPermanentlyDead(self.board) then
        self:showDeadBoardDialog()
    else
        -- US-32's tap-outside fix (dismissDialogOnTapOutside): a stray tap next
        -- to this dialog must only keep it open — the old cancel_callback here
        -- exited the whole game.
        UIManager:show(dismissDialogOnTapOutside(ConfirmBox:new{
            text = t("game.no_moves_shuffle"),
            ok_text = t("toolbar.shuffle"),
            ok_callback = function() self:shuffleBoard(true, 10, nil, true) end,
            cancel_text = t("toolbar.close"),
            cancel_callback = function()
                    UIManager:close(self, "ui", self.dimensions)
            end,
        }))
    end
end

-- US-32: permanent-dead-board dialog (Play again / Select Layout + optional
-- Undo).
-- Shown when isPermanentlyDead is true, or when the shuffle/auto-solve
-- retry loops exhaust with no moves. The dialog pauses the clock (like the
-- win dialog) so the polling loop does not flash behind the modal.
function Mahjong:showDeadBoardDialog()
    self:stopTimer()
    local has_undo = self.history and #self.history > 0
    local opts = {
        text = t("game.no_moves_dead"),
         ok_text = t("toolbar.play_again"),
         ok_callback = function()
             self:startGameWithLayout(self.layout)
         end,
         cancel_text = t("toolbar.select_layout"),
         cancel_callback = function()
             self:showLayoutPicker()
        end,
    }
    if has_undo then
        opts.other_buttons = { {
            {
                text = t("toolbar.undo"),
                callback = function()
                    self:undo()
                    self:startTimer()
                    self:updateTimerDisplay()
                end,
            },
        } }
        opts.other_buttons_first = true
    end
    -- Tap-outside only dismisses; a stray tap next to the dialog must never
    -- close the app (see dismissDialogOnTapOutside).
    UIManager:show(dismissDialogOnTapOutside(ConfirmBox:new(opts)))
end

-- After every removal: win dialog when the board is empty, otherwise an
-- offer to reshuffle when no move remains (US-08).  US-32: provably-dead
-- boards skip the shuffle offer and show the loss dialog instead.
function Mahjong:checkGameState()
    if MahjongLogic.isWin(self.board) then
        self:showWinDialog()
        return
    end
    if MahjongLogic.hasMoves(self.board, self.layout) then return end

    -- applyMatch has changed the framebuffer contents and queued the affected
    -- tile regions. Do not put a shuffle/dead-board modal over those regions
    -- before the repaint has drained: its dimmer/card can otherwise combine
    -- with stale tile pixels and leave garbled content in the center. Two
    -- ticks gives KOReader one complete repaint of the cleared board first.
    local board = self.board
    UIManager:tickAfterNext(function()
        -- A New Game/close may have replaced or discarded this board while the
        -- repaint was pending. Never show a stale result over the new state.
        if self.board ~= board or not self.board_view then return end
        if not MahjongLogic.isWin(self.board)
                and not MahjongLogic.hasMoves(self.board, self.layout) then
            self:handleNoMoves()
        end
    end)
end

-- US-12: the win screen is a summary — score, elapsed time, pairs matched,
-- overall (all layouts) best score/best time, this layout's own best score/
-- best time, and the current winning streak. The headline varies with what the
-- win achieved: "New overall best score/time" for overall records, "New best
-- score/time on this layout" when only the current map's record fell, and the
-- plain "You cleared the board!" otherwise. Only a human play-through records
-- stats: the long-press auto-solver (US-19) reaches this dialog too, and its
-- wins record no win, no bests, no streak change, and no games_played bump.
function Mahjong:showWinDialog()
    -- Freeze the clock before reading it (the summary uses the final elapsed,
    -- and stopping the polling loop also stops periodic refreshes flashing
    -- behind the modal dialog -- same reason openSettings pauses the timer).
    self:stopTimer()
    local elapsed = self:getElapsed()
    local pairs = self.pairs_matched or 0
    local new_best_score, new_best_time = false, false
    local new_layout_score, new_layout_time = false, false
    if not self.game_was_autosolved then
        new_best_score, new_best_time = MahjongStats.recordWin(
            self.stats, self.score, elapsed, pairs)
        -- US-30: the layout picker's trophy badge counts human wins per layout
        -- (auto-solve wins never reach recordWin, so they never count either).
        -- US-31: the same call records the layout's best winning score for the
        -- picker's score chip, and the per-layout fastest win for its time chip.
        -- recordLayoutWin returns which per-layout record THIS win just set, so
        -- the summary can distinguish a layout best from an overall best.
        new_layout_score, new_layout_time = MahjongStats.recordLayoutWin(
            self.stats, self.layout, self.score, elapsed)
        self:saveStats()
        self.game_won = true
    end
    -- Headline: celebrate whichever records this win broke, distinguishing the
    -- overall (all layouts) records from this layout's own bests.
    local headline
    if new_best_score and new_best_time then
        headline = t("game.congrats_overall_score_time")
    elseif new_best_score then
        headline = t("game.congrats_overall_score")
    elseif new_best_time then
        headline = t("game.congrats_overall_time")
    elseif new_layout_score and new_layout_time then
        headline = t("game.congrats_layout_score_time")
    elseif new_layout_score then
        headline = t("game.congrats_layout_score")
    elseif new_layout_time then
        headline = t("game.congrats_layout_time")
    else
        headline = t("game.cleared")
    end
    -- The summary rows as (label, value) pairs: the label is the description
    -- (no trailing colon) and the value is the data, so the dialog can right-
    -- align every label and start every value at the same x (the stats screen's
    -- column trick). The pairs are also kept on the dialog (win_rows) so the
    -- headless harness can reconstruct the rendered text for assertions.
    --
    -- These are the stats for THIS play session only — score, time, pairs
    -- matched, and the per-game help counters — plus the current winning
    -- streak, placed last (below the shuffle and hint counters). The global
    -- best records (overall / per-layout best score and time, which the
    -- headline above still celebrates) are NOT listed here as their own rows,
    -- so the card stays focused on what was achieved in this session.
    --
    -- US-12: the score/time rows still reach for the best, though — a win that
    -- breaks the overall or this-layout record gets a "(New best!)" text marker
    -- next to its value; a win that does NOT break a record instead shows the
    -- current best on that layout as a trophy icon + the best figure, so the
    -- player can compare this run against the best on the layout just played.
    -- The marker is carried as a text string (`marker`, for the harness) and a
    -- parallel widget (`marker_widget`) that the dialog renders after the value;
    -- the harness appends `marker` to `value`. A first win is always a new best
    -- (recordWin/recordLayoutWin raise the best from 0/nil), so the trophy branch
    -- only fires when a prior best already exists.
    local layout = self.layout
    local layout_best_score = self.stats.layout_highscores[layout]
    local layout_best_time = self.stats.layout_best_times[layout]
    local score_is_new_best = new_best_score or new_layout_score
    local time_is_new_best = new_best_time or new_layout_time
    local value_face = Font:getFace("cfont", Screen:scaleBySize(20))

    -- Builds the trophy+old-best marker widget for a row that did not beat the
    -- record: "(", a trophy icon, the best figure, ")" — bold/parenthesized to
    -- visually set the marker off from this run's own value, so the player can
    -- compare at a glance. The icon matches the value text height so the bracket
    -- pair sits on one visual line with the figure.
    local function trophy_marker(best_str)
        local icon_size = Screen:scaleBySize(20)
        local gap = Screen:scaleBySize(4)
        return HorizontalGroup:new{
            TextWidget:new{ text = "(", padding = 0, face = value_face, bold = true },
            IconWidget:new{ icon = "mahjong/trophy", width = icon_size, height = icon_size },
            HorizontalSpan:new{ width = gap },
            TextWidget:new{ text = best_str, padding = 0, face = value_face, bold = true },
            TextWidget:new{ text = ")", padding = 0, face = value_face, bold = true },
        }
    end
    -- Returns (marker_text, marker_widget) for a value row: "(New best!)" + a
    -- TextWidget when the row broke the record, a trophy icon + best figure when
    -- it did not (best_str is the prior best as a string), or nil/nil when there
    -- is no best to show.
    local function marker_for(is_new_best, best_str)
        if is_new_best then
            return t("game.new_best"), TextWidget:new{
                text = t("game.new_best"), padding = 0, face = value_face, bold = true,
            }
        end
        if best_str then
            return "(🏆 " .. best_str .. ")", trophy_marker(best_str)
        end
        return nil, nil
    end

    local score_best_str
    if not score_is_new_best and layout_best_score then
        score_best_str = tostring(layout_best_score)
    end
    local time_best_str
    if not time_is_new_best and layout_best_time then
        time_best_str = MahjongLogic.formatElapsed(layout_best_time)
    end
    local score_marker, score_marker_widget = marker_for(score_is_new_best, score_best_str)
    local time_marker, time_marker_widget = marker_for(time_is_new_best, time_best_str)

    local win_rows = {
        { label = t("hud.score"),           value = tostring(self.score),
          marker = score_marker, marker_widget = score_marker_widget },
        { label = t("game.time"),           value = MahjongLogic.formatElapsed(elapsed),
          marker = time_marker, marker_widget = time_marker_widget },
        { label = t("game.pairs_matched"),  value = tostring(pairs) },
        -- US-18: always report the per-game help counters, including clean
        -- wins, so the summary explicitly tells the player whether either was
        -- used.
        { label = t("game.hints_used"), value = tostring(self.hints_used or 0) },
        { label = t("game.shuffles"),   value = tostring(self.shuffles_used or 0) },
        -- The winning streak (consecutive wins) is shown after the hint
        -- counters, as the last row of the session summary.
        { label = t("game.current_streak"), value = tostring(self.stats.current_streak) },
    }
    -- The summary is a floating centered card (mahjongwinsummary.lua): it
    -- right-aligns the labels to the widest one so every value starts at the
    -- same x (left-aligned column), centers the headline and buttons, and the
    -- card itself is centered in the window (a stock ConfirmBox centers a wide
    -- headline text area, leaving the narrow label/value rows hugging the left
    -- edge). A tap outside the buttons is consumed, so only Close exits.
    UIManager:show(WinSummary:new{
         full_width = self.full_width,
         full_height = self.full_height,
         parent = self,
        text = headline,
        win_rows = win_rows,
         ok_text = t("toolbar.play_again"),
         cancel_text = t("toolbar.select_layout"),
         -- Keep the winning map selected for the quick replay action.
         ok_callback = function() self:startGameWithLayout(self.layout) end,
         cancel_callback = function() self:showLayoutPicker() end,
    })
end

-- US-08: Undo, hint, and shuffle ---------------------------------------------

function Mahjong:undo()
    -- US-33: Undo is dead while the auto-solver runs (the solve must run to
    -- completion; an undo mid-solve could un-solve a tile and keep its score).
    if self._auto_solve_active then return end
    local move = table.remove(self.history)
    if not move then return end

    self:clearSelection()
    self:clearFlash()
    -- US-34: the board changed under the hint, so drop it (clearHint is a
    -- no-op when no hint is up).
    self:clearHint()
    MahjongLogic.undoPair(self.board, move.a, move.b, move.ka, move.kb)
    self.board_view:addPair({ x = move.a.x, y = move.a.y, layer = move.a.layer, kind = move.ka },
                            { x = move.b.x, y = move.b.y, layer = move.b.layer, kind = move.kb })
    -- US-18: undo restores only the pair's points (the move's incremental score
    -- is subtracted — a hint/shuffle penalty is never refunded). The balance may
    -- go negative here too: removing a pair's points from a low score is fine.
    self.score = MahjongLogic.applyPenalty(self.score, move.score)
    self.pairs_matched = math.max(0, (self.pairs_matched or 0) - 1)
    self.last_match_kind = move.prev_last
    -- Undo restores chain state, but it intentionally breaks the combo window:
    -- redoing an undone pair must not receive a speed bonus.
    self.last_match_elapsed = nil
    self.combo_chain = 0
    self:updateStatus()
    self:updateTimerDisplay()
    self:saveGameState()
end

-- US-34: clears the active hint highlight (and stops its pulse). Called when
-- the player acts (tile tap, pair cleared, undo), when the auto-solver takes
-- over, and on new-game/restore (the board rebuild drops the overlays anyway).
-- A no-op when no hint is up. The token bump makes any pending pulse tick a
-- no-op, so a stale animation can never repaint after a clear.
function Mahjong:clearHint()
    self._hint_pulse_token = self._hint_pulse_token + 1
    if self._last_hint and self.board_view then
        local h = self._last_hint
        local refresh_rects = {
            { x = h.a.x, y = h.a.y, layer = h.a.layer },
            { x = h.b.x, y = h.b.y, layer = h.b.layer },
        }
        self.board_view:clearOverlay(h.a.x, h.a.y, h.a.layer, true)
        self.board_view:clearOverlay(h.b.x, h.b.y, h.b.layer, true)
        self.board_view:requestRefresh(refresh_rects)
    end
    self._last_hint = nil
end

-- US-34: brief boldness pulse for a persistent hint. Draws the bold overlay
-- immediately (so the hint reads from the very first paint), then toggles it
-- between the thin "hint" and bold "hint_bold" icons every
-- HINT_PULSE_STEP_SECONDS for HINT_PULSE_TICKS steps, ending on bold. The hint
-- then stays highlighted at bold until the player acts (clearHint). Guarded by
-- a monotonic token plus _last_hint, so a restart (new hint press, resume) or
-- a clear can never leave a stale tick repainting.
function Mahjong:startHintPulse(pair, refresh_rects)
    self._hint_pulse_token = self._hint_pulse_token + 1
    local token = self._hint_pulse_token
    local board_view = self.board_view
    if not board_view then return end
    local initial_rects = refresh_rects or {}
    board_view:setOverlay(pair.a.x, pair.a.y, pair.a.layer, "hint_bold", true)
    board_view:setOverlay(pair.b.x, pair.b.y, pair.b.layer, "hint_bold", true)
    initial_rects[#initial_rects + 1] = { x = pair.a.x, y = pair.a.y, layer = pair.a.layer }
    initial_rects[#initial_rects + 1] = { x = pair.b.x, y = pair.b.y, layer = pair.b.layer }
    board_view:requestRefresh(initial_rects)
    local step = 0
    local tick
    tick = function()
        step = step + 1
        if self._hint_pulse_token ~= token then return end
        if not self._last_hint or not self.board_view then return end
        local icon = (step % 2 == 1) and "hint" or "hint_bold"
        self.board_view:setOverlay(pair.a.x, pair.a.y, pair.a.layer, icon, true)
        self.board_view:setOverlay(pair.b.x, pair.b.y, pair.b.layer, icon, true)
        self.board_view:requestRefresh({
            { x = pair.a.x, y = pair.a.y, layer = pair.a.layer },
            { x = pair.b.x, y = pair.b.y, layer = pair.b.layer },
        })
        if step < HINT_PULSE_TICKS then
            UIManager:scheduleIn(HINT_PULSE_STEP_SECONDS, tick)
        end
    end
    UIManager:scheduleIn(HINT_PULSE_STEP_SECONDS, tick)
end

-- Repeated Hint presses cycle through the available matching pairs instead of
-- always highlighting the same first one (the highlight stays on each pair —
-- it no longer times out (US-34) — so the next press moves to the pair AFTER
-- it, wrapping around).
function Mahjong:showHint()
    -- US-33: the Hint button is dead while the auto-solver runs (a hint would
    -- be redundant — the solver highlights pairs as it plays).
    if self._auto_solve_active then return end
    if not self:getSetting("hints", SETTINGS_DEFAULTS.hints) then return end
    local board_view = self.board_view
    -- US-20: a hint session runs from the first hint after a pair was cleared
    -- until the next pair is cleared (applyMatch resets _last_hint). Presses
    -- that continue an active session (cycling, or re-hinting the same board)
    -- are free; only the press that STARTS a session pays HINT_PENALTY.
    local was_session = self._last_hint ~= nil
    -- Drop the previous hint's overlays first so cycling presses never leave a
    -- stale highlight behind (clearOverlay is a no-op if the tile is gone).
    local transition_rects = {}
    if self._last_hint then
        transition_rects[#transition_rects + 1] = {
            x = self._last_hint.a.x, y = self._last_hint.a.y, layer = self._last_hint.a.layer,
        }
        transition_rects[#transition_rects + 1] = {
            x = self._last_hint.b.x, y = self._last_hint.b.y, layer = self._last_hint.b.layer,
        }
        board_view:clearOverlay(self._last_hint.a.x, self._last_hint.a.y, self._last_hint.a.layer, true)
        board_view:clearOverlay(self._last_hint.b.x, self._last_hint.b.y, self._last_hint.b.layer, true)
    end
    local pairs = MahjongLogic.matchingFreePairs(self.board)
    if #pairs == 0 then
        self._last_hint = nil
        if #transition_rects > 0 then
            board_view:requestRefresh(transition_rects)
        end
        -- In theory checkGameState already caught this, but user can tap Hint
        -- on a dead board before the shuffle prompt is accepted.
        self:handleNoMoves()
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
    -- A hint points at the next move, so it must never feed the fast-clear
    -- combo: reset the combo window and chain counter here, so the pair the
    -- player clears after the hint earns no combo and any running chain
    -- restarts. Without this, Hint + immediate tap would farm COMBO points on
    -- autopilot. (The chain bonus in pairPoints is unaffected — that is about
    -- consecutive same-group matches, which a hint genuinely helps the player
    -- keep track of rather than skip ahead of.)
    self.last_match_elapsed = nil
    self.combo_chain = 0
    -- US-18: a hint that is ACTUALLY shown costs HINT_PENALTY (the dead-board
    -- shuffle offer above is not a hint and charges nothing). The penalty is
    -- applied at use time, not part of the pair history, so undo restores only
    -- the pair's points. US-20: the penalty is charged ONCE per hint session —
    -- only when this press starts a fresh session (no hint shown since the last
    -- cleared pair). Cycling presses within the same session re-charge nothing.
    if not was_session then
        self.hints_used = (self.hints_used or 0) + 1
        self.score = MahjongLogic.applyPenalty(self.score, MahjongLogic.HINT_PENALTY)
    end
    self:updateStatus()
    self:saveGameState()
    -- US-34: the hint no longer times out. startHintPulse draws the bold
    -- overlay and runs the brief normal/bold flicker that draws the eye; the
    -- highlight then stays until the player acts (any tile tap, a cleared
    -- pair, undo, or the auto-solver starting all call clearHint).
    self:startHintPulse(pair, transition_rects)
end

-- Reshuffles the tiles remaining on the board in place. `charge` is nil/true on
-- a USER-INITIATED shuffle (Shuffle button, the no-moves prompt, the dead-board
-- hint offer): it costs SHUFFLE_PENALTY once (US-18). The bounded auto-repeat
-- re-shuffles that guarantee a playable board pass false, so they never
-- re-charge. (The auto-solver's mid-solve shuffles call MahjongLogic directly
-- and never charge — only the player pays.)
function Mahjong:shuffleBestDeadBoard(attempts, charge)
    if self._shuffle_active then return end
    self._shuffle_active = true
    self._shuffle_token = self._shuffle_token + 1
    local token = self._shuffle_token
    local best_board, best_moves = nil, -1
    local candidate = 0

    local copy_board = function(source)
        local copy = {}
        for key, kind in pairs(source) do copy[key] = kind end
        return copy
    end

    local finish
    finish = function()
        if self._shuffle_token ~= token or not self._shuffle_active then return end
        self._shuffle_active = false
        if best_board then
            for key, kind in pairs(best_board) do self.board[key] = kind end
        end
        self:clearSelection()
        self:clearHint()
        if charge then
            self.shuffles_used = (self.shuffles_used or 0) + 1
            self.score = MahjongLogic.applyPenalty(self.score, MahjongLogic.SHUFFLE_PENALTY)
        end
        self.board_view:updateBoard()
        self:updateStatus()
        self:updateTimerDisplay()
        self:saveGameState()
        if not MahjongLogic.hasMoves(self.board, self.layout) then
            if attempts > 0 then
                self:shuffleBestDeadBoard(attempts - 1, false)
            elseif MahjongLogic.tileCount(self.board) > 0 then
                self:showDeadBoardDialog()
            end
        end
    end

    local evaluate
    evaluate = function()
        if self._shuffle_token ~= token or not self._shuffle_active then return end
        candidate = candidate + 1
        local shuffled = copy_board(self.board)
        MahjongLogic.shuffleBoard(shuffled)
        local moves = MahjongLogic.countFreePairs(shuffled, self.layout)
        if moves > best_moves then
            best_moves = moves
            best_board = shuffled
        end
        if candidate >= DEAD_BOARD_SHUFFLE_CANDIDATES then
            finish()
        else
            UIManager:scheduleIn(DEAD_BOARD_SHUFFLE_STEP_SECONDS, evaluate)
        end
    end
    UIManager:scheduleIn(DEAD_BOARD_SHUFFLE_STEP_SECONDS, evaluate)
end

function Mahjong:shuffleBoard(force, attempts, charge, optimize_dead_board)
    -- US-33: the Shuffle button is dead while the auto-solver runs (the solver
    -- shuffles via MahjongLogic.shuffleBoard directly when it needs to).
    if self._auto_solve_active or self._shuffle_active then return end
    attempts = attempts or 10
    if charge == nil then charge = true end
    if force and optimize_dead_board then
        self:shuffleBestDeadBoard(attempts, charge)
        return
    end
    local do_shuffle = function()
        MahjongLogic.shuffleBoard(self.board)
        self:clearSelection()
        -- US-34: a shuffle reorders the board under the hint, so drop it
        -- (clearHint is a no-op when no hint is up; the board rebuild below
        -- would otherwise leave a stale _last_hint repainting at old coords).
        self:clearHint()
        if charge then
            self.shuffles_used = (self.shuffles_used or 0) + 1
            self.score = MahjongLogic.applyPenalty(self.score, MahjongLogic.SHUFFLE_PENALTY)
        end
        self.board_view:updateBoard()
        self:updateStatus()
        self:updateTimerDisplay()
        self:saveGameState()
        -- If still no moves (rare but possible), auto-repeat a bounded number
        -- of times. When the retries run out and the board is still stuck, the
        -- board is empirically dead — show the permanent deadlock dialog.
        if not MahjongLogic.hasMoves(self.board, self.layout) then
            if attempts > 0 then
                self:shuffleBoard(true, attempts - 1, false)
            elseif MahjongLogic.tileCount(self.board) > 0 then
                self:showDeadBoardDialog()
            end
        end
    end

    if force then
        do_shuffle()
    else
        UIManager:show(ConfirmBox:new{
            text        = t("game.reshuffle"),
            ok_text     = t("toolbar.shuffle"),
            -- ConfirmBox invokes ok_callback before it removes itself from
            -- the window stack. Rebuilding all tile widgets while the modal
            -- is still on top can make the repaint run against the covered
            -- stack, leaving a partially rendered board. Let the dialog close
            -- first, then rebuild and request the board refresh after an
            -- intervening repaint. tickAfterNext is important here: a plain
            -- nextTick can still run before the dialog-clear repaint drains.
            ok_callback = function() UIManager:tickAfterNext(do_shuffle) end,
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
-- hand-played one. US-33: once running, the solver is UNINTERRUPTIBLE — every
-- input path no-ops, the game is flagged auto-solved in its save, and a
-- reload of that save resumes the solve. It only ever ends via the win dialog
-- (no win recorded) or a provably-dead board.

function Mahjong:armAutoSolve()
    -- US-33: a second hold during a running solve is ignored (it would only
    -- clobber the "Auto-solving…" flash with a stale keep-holding message).
    if self._auto_solve_active then return end
    if not self:getSetting("hints", SETTINGS_DEFAULTS.hints) then return end
    if MahjongLogic.isWin(self.board) then return end
    local token = self._auto_solve_token + 1
    self._auto_solve_token = token
    self:setFlash(t("game.auto_solve_arming"))
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
    -- US-33: releases during a running solve are a no-op.
    if self._auto_solve_active then return end
    self._auto_solve_token = self._auto_solve_token + 1
    self:clearFlash()
end

function Mahjong:startAutoSolve()
    if self._auto_solve_active then return end
    self._auto_solve_token = self._auto_solve_token + 1
    self._auto_solve_active = true
    -- US-12: a board the solver clears is considered "cheated" — its win must
    -- never record a win/best/streak (showWinDialog gates on this flag).
    self.game_was_autosolved = true
    -- The solver replays pairs far faster than a human, so start a clean undo
    -- history: a mid-solve shuffle moves tiles to different positions, which
    -- would scramble a long shared history under a later undo.
    self.history = {}
    self:clearSelection()
    -- US-34: drop any lingering hint (overlays + pulse) before the solver
    -- takes over the board.
    self:clearHint()
    self:setFlash(t("game.auto_solving"))
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
    local pair = MahjongLogic.matchingFreePair(self.board, self.layout)
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
            pair = MahjongLogic.matchingFreePair(self.board, self.layout)
            attempts = attempts - 1
        until pair or attempts == 0
        self.board_view:updateBoard()
        if not pair then
            -- US-32: the board is empirically dead (all shuffles failed).
            self:stopAutoSolve()
            self:showDeadBoardDialog()
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
function Mahjong:flashMessage(text, pulse)
    self:setFlash(text)
    local seq = self._flash_seq
    if pulse and self.flash_text then
        self.flash_text.bold = true
        UIManager:setDirty(self, "ui", self.flash_region)
        self:bakeLowerChrome()
        local elapsed = 0
        local tick
        tick = function()
            if self._flash_seq ~= seq or not self.flash_text then return end
            elapsed = elapsed + COMBO_PULSE_STEP_SECONDS
            if elapsed >= FLASH_TIMEOUT then return end
            self.flash_text.bold = not self.flash_text.bold
            UIManager:setDirty(self, "ui", self.flash_region)
            UIManager:scheduleIn(COMBO_PULSE_STEP_SECONDS, tick)
        end
        UIManager:scheduleIn(COMBO_PULSE_STEP_SECONDS, tick)
    end
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
        self.flash_text.bold = false
        if self.flash_band_icon then
            -- ImageWidget:paintTo skips painting when `hide` is true (the
            -- `visible` field is ignored by KOReader widgets).
            self.flash_band_icon.hide = false
        end
        UIManager:setDirty(self, "ui", self.flash_region)
        -- Draw the new band content now so the refresh can't sample stale
        -- pixels (see bakeLowerChrome).
        self:bakeLowerChrome()
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
        self.flash_text.bold = false
        if self.flash_band_icon then
            self.flash_band_icon.hide = true
        end
        UIManager:setDirty(self, "ui", self.flash_region)
        self:bakeLowerChrome()
    end
end

-- Lower-chrome refresh plumbing (US-43) -----------------------------------------
--
-- The banner (flash text + timer) and the action-button toolbar share an edge,
-- so KOReader's `_refresh` merges (open-range) any pair of their regional
-- refreshes into ONE ioctl per batch, often merged yet again with the board's
-- tile rect just above the banner. When the EPDC starts driving that combined
-- rect while the board's structural update is still settling, it can ink the
-- upper part of the strip but skip the toolbar row — observed as "the whole
-- lower part refreshed, but the action buttons came out blank" until the next
-- full repaint.
--
-- Mitigations (mirroring the stock ReaderFooter, e.g. readerfooter.lua
-- `_updateFooterText` → `UIManager:widgetRepaint` then a lambda-setDirty, and
-- the board's own `queueStructuralRefreshRetry`):
--   * buildUILayout gives the whole lower chrome ONE explicit rect
--     (`lower_band_region`), so no refresh can end short of the toolbar row;
--   * `bakeLowerChrome` paints the banner + toolbar sub-trees into the
--     framebuffer right before a refresh, so the EPDC never reads pixels that
--     predate the change (stale chrome is exactly a blank-looking button);
--   * `settleLowerChrome` re-drives the strip once, a tick later, as a pure
--     refresh (no repaint — the fb is already painted) to heal a half-applied
--     dribble from same-batch racing.

function Mahjong:lowerChromeRegion()
    return self.lower_band_region or self.toolbar_region or self.flash_region
end

-- Paint the banner + toolbar sub-trees into the framebuffer right now, before
-- the queued refresh drains. Stock ReaderFooter does the same
-- (`widgetRepaint(self.view.footer, 0, 0)` before its regional setDirty); it
-- guarantees that whatever region the EPDC samples already holds the NEW
-- pixels. No-op on the headless harness (no widgetRepaint stub).
function Mahjong:bakeLowerChrome()
    if not UIManager.widgetRepaint then return end
    if not self.toolbar_region or not self.flash_region then return end
    if self.flash_band then
        UIManager:widgetRepaint(self.flash_band, 0, self.flash_region.y)
    end
    if self.toolbar_widget then
        UIManager:widgetRepaint(self.toolbar_widget, 0, self.toolbar_region.y)
    end
end

-- One deferred, pure-refresh re-request of the lower chrome (no repaint: the
-- framebuffer is already current). Used after toolbar structural changes
-- (counter pills) so a same-batch merge that the EPDC half-applied gets a
-- second stab at the strip on the next tick. Single-shot guarded so closed
-- or rebuilt games never schedule twice.
function Mahjong:settleLowerChrome()
    if not UIManager.tickAfterNext then return end
    local pending = self._chrome_settle
    self._chrome_settle = true
    if pending then return end
    UIManager:tickAfterNext(function()
        self._chrome_settle = false
        -- A closed/replaced game must never drive a refresh into a new window.
        if not self.toolbar_widget or not self.board_view then return end
        UIManager:setDirty(nil, "ui", self:lowerChromeRegion())
    end)
end

-- The HUD bar reflects the pairs left, the number of currently-matching free
-- pairs (legal moves available to tap), and the score — each in its own chip.
function Mahjong:updateStatus()
    if not self.status_bar then return end
    local pairs = math.floor(MahjongLogic.tileCount(self.board) / 2)
    local free = MahjongLogic.countFreePairs(self.board, self.layout)
    self.status_bar:setStats(pairs, free, self.score)
    -- Keep the toolbar Hint / Shuffle count pills in sync (they mirror the
    -- persisted hints_used / shuffles_used counters the win summary reports).
    local toolbar_structural = false
    if self.hint_counter_badge then
        local txt = tostring(self.hints_used or 0)
        toolbar_structural = toolbar_structural or self.hint_counter_badge.text ~= txt
        self.hint_counter_badge:setText(txt)
    end
    if self.shuffle_counter_badge then
        local txt = tostring(self.shuffles_used or 0)
        toolbar_structural = toolbar_structural or self.shuffle_counter_badge.text ~= txt
        self.shuffle_counter_badge:setText(txt)
    end
    -- status_bar is a subwidget, so flag the window-level widget, but keep the
    -- refresh regional. A regionless request here refreshes the entire game
    -- window after every pair removal.
    UIManager:setDirty(self, "ui", self.status_region or self.status_bar.dimen)
    -- Keep the toolbar's own refresh tight (regional, not the whole lower
    -- strip): when the banner (flash/timer) refreshes in the same batch,
    -- KOReader's open-range merge folds the two edge-adjacent rects — and the
    -- board's tile rect just above the banner — into one ioctl anyway. That
    -- big merged rect is where the "band repainted, buttons blank" report
    -- comes from: the EPDC half-applies it and the action-button row ends up
    -- out of the final drive. Bake the chrome into the framebuffer NOW (stock
    -- ReaderFooter idiom) so whichever rect the EPDC samples holds the
    -- just-built toolbar content, and re-drive the strip on a later tick when
    -- it genuinely changed.
    if self.toolbar_region then
        UIManager:setDirty(self, "ui", self.toolbar_region)
        self:bakeLowerChrome()
    end
    -- A count pill changed (a genuine toolbar structural change): re-drive the
    -- strip once on a later tick, pure-refresh, to heal a half-applied merge.
    if toolbar_structural then
        self:settleLowerChrome()
    end
end

function Mahjong:onCloseWidget()
    -- Invalidate any pending dead-board candidate callbacks before releasing
    -- the board; scheduled UI work must never mutate a closed game.
    self._shuffle_token = self._shuffle_token + 1
    self._shuffle_active = false
    -- US-19: cancel a pending long-press arm / running solve (bumps the token
    -- so no stale step can fire into a closed widget).
    self:stopAutoSolve()
    -- US-17: if the pause overlay is up, drop it first (its onCloseWidget
    -- restarts the clock, which the final stopTimer below re-freezes). This is
    -- the "closing while paused still saves" path: saveGameState below always
    -- runs, and stopTimer is idempotent so it never double-freezes.
    if self._pause_dlg then
        local dlg = self._pause_dlg
        self._pause_dlg = nil
        UIManager:close(dlg)
    end
    -- US-14: if the layout picker is up, drop it too.
    if self._picker_dlg then
        local dlg = self._picker_dlg
        self._picker_dlg = nil
        UIManager:close(dlg)
    end
    self:saveGameState()
    self:saveStats()
    self:stopTimer()
    self:clearFlash()
    self.selected = nil
    self.board_view = nil
    self.board = nil
end

return Mahjong
