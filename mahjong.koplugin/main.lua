local Device = require("device")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local Geometry = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local TextWidget = require("ui/widget/textwidget")
local ButtonWidget = require("ui/widget/button")
local TitleBarWidget = require("ui/widget/titlebar")
local ConfirmBox = require("ui/widget/confirmbox")
local _ = require("gettext")

local BACKGROUND_COLOR = Blitbuffer.COLOR_WHITE

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

local Mahjong = FrameContainer:extend{
    name = "mahjong",
    is_doc_only = false,
    background = BACKGROUND_COLOR,
    bordersize = 0,
    padding = 0,
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    board = nil,
    status_bar = nil,
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
    self:buildUILayout()
    UIManager:show(self)
end

function Mahjong:buildUILayout()
    self.status_bar = self:createStatusBar()
    local status_h = self.status_bar:getSize().h

    local pad = Screen:scaleBySize(8)
    local toolbar_btn_h = Screen:scaleBySize(32)
    local toolbar_btn_w = math.floor(self.full_width / 3)
    local inner_w = self.full_width - 2 * pad
    local board_h = self.full_height - status_h - toolbar_btn_h

    local board_area = FrameContainer:new{
        background = BACKGROUND_COLOR,
        bordersize = 0,
        padding = 0,
        width = self.full_width,
        height = board_h,
        CenterContainer:new{
            dimen = Geometry:new{ w = inner_w, h = board_h },
            TextWidget:new{
                text = _("Board area"),
                face = Font:getFace("ffont", 20),
            },
        },
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
    self:buildUILayout()
    UIManager:setDirty(self, "ui")
end

-- luacheck: no unused args
function Mahjong:saveGameState()
end

function Mahjong:onCloseWidget()
    self.board = nil
end

return Mahjong
