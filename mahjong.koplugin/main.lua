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
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local MahjongLogic = require("mahjonglogic")
local MahjongBoard = require("mahjongboard")
local HudBar = require("hudbar")

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
-- implemented (no elapsed-time tracking).
-- FLASH_TIMEOUT: how long a non-blocking feedback message (e.g. "Tile is
-- blocked") stays visible in the band between the board and the toolbar.
local FLASH_TIMEOUT = 2

-- Toolbar action button: a rounded rectangle `w` x `h` — the WHOLE widget is
-- the tap area — with a square icon centered inside it, plus a small hint
-- label beneath. Padding keeps the icon off the button edges, bordersize draws
-- a slim rounded border, and radius rounds the corners. The icon button and
-- its label are stacked in a VerticalGroup so each toolbar cell carries a
-- caption (Undo / Hint / Shuffle / New Game). The cells are separated by
-- HorizontalSpan spacers in buildUILayout() (the stock HorizontalGroup ignores
-- any `spacing` field).
local function createToolbarButton(icon, label, w, h, cb)
    local pad = Screen:scaleBySize(6)
    local border = Screen:scaleBySize(1)
    local radius = Screen:scaleBySize(4)
    local icon_h = h - 2 * pad - 2 * border
    local button = ButtonWidget:new{
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
    local label_widget = TextWidget:new{
        text = label,
        padding = 0,
        face = Font:getFace("smallinfofont", Screen:scaleBySize(11)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    return VerticalGroup:new{
        align = "center",
        button,
        label_widget,
    }
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
    _flash_seq = 0, -- monotonic token for the pending feedback-clear timer
    flash_band = nil,  -- fixed-height band between the board and the toolbar
    flash_text = nil,  -- the band's TextWidget (feedback messages appear here)
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
    self.board = MahjongLogic.newGame()
    self.selected = nil
    self.score = 0
    self.last_match_kind = nil
    self.history = {}
    self:buildUILayout()
    self:updateStatus()
    UIManager:show(self)
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
    -- OverlapGroup iterates its children and calls getSize() on each one
    -- (overlapgroup.lua getSize/init). Every child MUST be a real widget — a
    -- plain wrapper table like { overlap_offset = ..., widget } has no
    -- getSize() and crashes with "attempt to call method 'getSize' (a nil
    -- value)". The icon and text go in directly, exactly like the board.
    local band_overlay = OverlapGroup:new{
        dimen = Geometry:new{ w = self.full_width, h = flash_h },
        self.flash_text,
        self.flash_band_icon,
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

    local toolbar = HorizontalGroup:new{
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("chevron.left", _("Undo"), toolbar_btn_w, toolbar_btn_h,
            function() self:undo() end),
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("mahjong/lightbulb", _("Hint"), toolbar_btn_w, toolbar_btn_h,
            function() self:showHint() end),
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("mahjong/shuffle", _("Shuffle"), toolbar_btn_w, toolbar_btn_h,
            function() self:shuffleBoard() end),
        HorizontalSpan:new{ width = toolbar_gap },
        createToolbarButton("plus", _("New Game"), toolbar_btn_w, toolbar_btn_h, function()
            UIManager:show(ConfirmBox:new{
                text        = _("Start a new game?"),
                ok_text     = _("New Game"),
                ok_callback = function() self:resetGame() end,
            })
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
    -- HUD top bar (hudbar.lua): title + three stat chips (Pairs / Free /
    -- Score) + the quit X, replacing the old TitleBarWidget text subtitle.
    -- updateStatus() pushes the values via setStats().
    return HudBar:new{
        title                  = _("Mahjong Solitaire"),
        right_icon             = "mahjong/close",
        right_icon_size_ratio  = 0.9,
        right_icon_tap_callback = function()
            UIManager:show(ConfirmBox:new{
                text        = _("Exit Mahjong Solitaire?"),
                ok_text     = _("Exit"),
                ok_callback = function()
                    self:saveGameState()
                    UIManager:close(self, "full")
                end,
            })
        end,
    }
end

function Mahjong:resetGame()
    self.board = MahjongLogic.newGame()
    self.selected = nil
    self.score = 0
    self.last_match_kind = nil
    self.history = {}
    self:buildUILayout()
    self:updateStatus()
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
        local ok, ka, kb = MahjongLogic.removePair(self.board, a, b)
        if ok then
            self.selected = nil
            self.board_view:removePair(a, b)
            local prev_last = self.last_match_kind
            local points = MahjongLogic.pairPoints(prev_last, ka)
            self.last_match_kind = ka
            self.score = self.score + points
            table.insert(self.history, { a = a, b = b, ka = ka, kb = kb, score = points, prev_last = prev_last })
            self:updateStatus()
            self:checkGameState()
            return
        end
    end

    -- First tap, or switching from a different tile.
    self:setSelection(x, y, layer, kind)
end

function Mahjong:setSelection(x, y, layer, kind)
    self:clearSelection()
    self.selected = { x = x, y = y, layer = layer, kind = kind }
    self.board_view:setOverlay(x, y, layer, "select")
end

function Mahjong:clearSelection()
    if self.selected then
        self.board_view:clearOverlay(self.selected.x, self.selected.y, self.selected.layer)
        self.selected = nil
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
                self:saveGameState()
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
            self:saveGameState()
            UIManager:close(self, "full")
        end,
    })
end

-- US-08: Undo, hint, and shuffle ---------------------------------------------

function Mahjong:undo()
    local move = table.remove(self.history)
    if not move then return end

    self:clearSelection()
    MahjongLogic.undoPair(self.board, move.a, move.b, move.ka, move.kb)
    self.board_view:addPair({ x = move.a.x, y = move.a.y, layer = move.a.layer, kind = move.ka },
                            { x = move.b.x, y = move.b.y, layer = move.b.layer, kind = move.kb })
    self.score = self.score - move.score
    self.last_match_kind = move.prev_last
    self:updateStatus()
end

function Mahjong:showHint()
    local pair = MahjongLogic.matchingFreePair(self.board)
    if not pair then
        -- In theory checkGameState already caught this, but user can tap Hint
        -- on a dead board before the shuffle prompt is accepted.
        UIManager:show(ConfirmBox:new{
            text = _("No moves left! Shuffle the board?"),
            ok_text = _("Shuffle"),
            ok_callback = function() self:shuffleBoard(true) end,
        })
        return
    end
    self.board_view:setOverlay(pair.a.x, pair.a.y, pair.a.layer, "hint")
    self.board_view:setOverlay(pair.b.x, pair.b.y, pair.b.layer, "hint")
    -- Clear hints after 2 seconds.
    local board_view = self.board_view
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

-- Brief NON-BLOCKING feedback (US-09): `text` appears in the fixed band
-- between the board and the toolbar and auto-clears after FLASH_TIMEOUT.
-- The band is a plain text widget (not a modal dialog), so the board keeps
-- accepting taps while a message is showing — an accidental blocked-tile tap
-- can be corrected immediately. Each call bumps a sequence token; a stale
-- clear timer (e.g. from before a close/new game) is a no-op.
function Mahjong:flashMessage(text)
    local seq = self._flash_seq + 1
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
    UIManager:scheduleIn(FLASH_TIMEOUT, function()
        if self._flash_seq == seq then
            self:clearFlash()
        end
    end)
end

-- Clears the feedback band (called by the flash timer and on close).
function Mahjong:clearFlash()
    self._flash_seq = nil
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

-- luacheck: no unused args
function Mahjong:saveGameState()
end

function Mahjong:onCloseWidget()
    self:clearFlash()
    self.selected = nil
    self.board_view = nil
    self.board = nil
end

return Mahjong
