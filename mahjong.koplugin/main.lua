local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local Geometry = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ButtonWidget = require("ui/widget/button")
local TitleBarWidget = require("ui/widget/titlebar")
local ConfirmBox = require("ui/widget/confirmbox")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local MahjongLogic = require("mahjonglogic")
local MahjongBoard = require("mahjongboard")

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

-- US-07 score stub: flat 10 points per matched pair. US-09 replaces this with
-- the full scoring model (base + chain bonus + timer bonus).
local SCORE_PER_PAIR = 10

local function createToolbarButton(icon, w, h, cb)
    return ButtonWidget:new{
        icon = icon,
        width = w,
        icon_width = w,
        icon_height = h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        callback = cb,
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
}

function Mahjong:init()
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
    self:buildUILayout()
    self:updateStatus()
    UIManager:show(self)
end

function Mahjong:buildUILayout()
    self.status_bar = self:createStatusBar()
    local status_h = self.status_bar:getSize().h

    local toolbar_btn_h = Screen:scaleBySize(32)
    local toolbar_btn_w = math.floor(self.full_width / 3)
    local board_h = self.full_height - status_h - toolbar_btn_h

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

    local toolbar = CenterContainer:new{
        dimen = Geometry:new{ w = self.full_width, h = toolbar_btn_h },
        createToolbarButton("plus", toolbar_btn_w, toolbar_btn_h, function()
            UIManager:show(ConfirmBox:new{
                text        = _("Start a new game?"),
                ok_text     = _("New Game"),
                ok_callback = function() self:resetGame() end,
            })
        end),
    }

    local main_vgroup = VerticalGroup:new{
        align = "center",
        width = self.full_width,
        height = self.full_height,
        board_area,
        toolbar,
        self.status_bar,
    }
    self[1] = main_vgroup
end

function Mahjong:createStatusBar()
    return TitleBarWidget:new{
        fullscreen             = true,
        title                  = _("Mahjong Solitaire"),
        subtitle               = _("Tap New Game to begin"),
        title_top_padding      = Screen:scaleBySize(2),
        bottom_v_padding       = Screen:scaleBySize(8),
        close_callback = function()
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
    if not MahjongLogic.isFree(self.board, x, y, layer) then return end

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
        if MahjongLogic.matches(sel.kind, kind)
            and MahjongLogic.removePair(self.board, a, b) then
            self.selected = nil
            self.board_view:removePair(a, b)
            self.score = self.score + SCORE_PER_PAIR
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
-- immediate reshuffle when no move remains (dedicated shuffle UX in US-08).
function Mahjong:checkGameState()
    if MahjongLogic.isWin(self.board) then
        self:showWinDialog()
    elseif not MahjongLogic.hasMoves(self.board) then
        self:shuffleBoard()
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

-- Reshuffles the tiles remaining on the board in place (US-07: immediate,
-- no prompt; US-08 adds the ConfirmBox + repeat UX).
function Mahjong:shuffleBoard()
    MahjongLogic.shuffleBoard(self.board)
    self:clearSelection()
    self.board_view:updateBoard()
    self:updateStatus()
    UIManager:setDirty(self, "ui")
end

-- Status bar reflects the pairs left and the score stub.
function Mahjong:updateStatus()
    if not self.status_bar then return end
    local pairs = math.floor(MahjongLogic.tileCount(self.board) / 2)
    self.status_bar:setSubTitle(string.format(_("Pairs remaining: %d · Score: %d"), pairs, self.score))
    -- status_bar is a subwidget, so setDirty on it alone would not repaint;
    -- flag the window-level widget as well (same pattern as the chess example).
    UIManager:setDirty(self.status_bar, "ui")
    UIManager:setDirty(self, "ui")
end

-- luacheck: no unused args
function Mahjong:saveGameState()
end

function Mahjong:onCloseWidget()
    self.selected = nil
    self.board_view = nil
    self.board = nil
end

return Mahjong
