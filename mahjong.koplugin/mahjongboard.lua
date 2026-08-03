-- Mahjong Solitaire — board widget.
--
-- Renders the 3D Turtle board as a ButtonTable over the flat projection grid
-- (design decision 4/5): a 12x6 grid of square cells, each showing the
-- topmost tile at that (x, y) position. Cell size is derived from the widget
-- size and the grid dimensions so the whole board always fits the screen.
-- Tap handling (US-07) hooks in through the optional `onTileTap` callback.

local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("buttontable")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local MahjongLogic = require("mahjonglogic")

local Board = FrameContainer:extend{
    board = nil,
    width = 0,
    height = 0,
    onTileTap = nil,
    bordersize = 0,
    padding = 0,
    background = Blitbuffer.COLOR_WHITE,
    grid = nil,
    button_size = 0,
    icon_height = 0,
}

function Board:getSize()
    -- FrameContainer:paintTo() reads these after calling getSize(); without
    -- them it crashes with "attempt to perform arithmetic on nil value".
    self._padding_left = self.padding_left or self.padding
    self._padding_right = self.padding_right or self.padding
    self._padding_top = self.padding_top or self.padding
    self._padding_bottom = self.padding_bottom or self.padding
    return Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

function Board:init()
    self.grid = MahjongLogic.gridBounds()
    local cols = self.grid.x_max - self.grid.x_min + 1
    local rows = self.grid.y_max - self.grid.y_min + 1

    local pad = Screen:scaleBySize(8)
    local bt_pad_v = Screen:scaleBySize(4) -- ButtonTable's vertical padding
    local usable_w = self.width - 2 * pad
    local usable_h = self.height - 2 * pad
    local cell = math.floor(math.min(usable_w / cols, usable_h / rows))
    self.button_size = cell
    self.icon_height = cell - 2 * bt_pad_v

    local grid = {}
    for y = self.grid.y_min, self.grid.y_max do
        local row = {}
        for x = self.grid.x_min, self.grid.x_max do
            row[#row + 1] = self:createCellButton(x, y)
        end
        grid[#grid + 1] = row
    end

    self.table = ButtonTable:new{
        width = cell * cols,
        buttons = grid,
        shrink_unneeded_width = false,
        zero_sep = true,
        sep_width = 0,
        addVerticalSpan = function() end,
    }

    self[1] = FrameContainer:new{
        bordersize = 0,
        background = self.background,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            self.table,
        },
    }
end

function Board:createCellButton(x, y)
    local kind = self.board and MahjongLogic.topTileAt(self.board, x, y) or nil
    local icon = kind and ("mahjong/" .. MahjongLogic.iconForKind(kind)) or "mahjong/empty"
    return {
        id = self:idFor(x, y),
        icon = icon,
        alpha = true,
        width = self.button_size,
        icon_width = self.button_size,
        icon_height = self.icon_height,
        callback = function() self:handleClick(x, y) end,
    }
end

function Board:idFor(x, y)
    local rows = self.grid.y_max - self.grid.y_min + 1
    return (x - self.grid.x_min) * rows + (y - self.grid.y_min) + 1
end

-- Refreshes every cell icon from the current board state. Used on first paint
-- and after tile removals / reshuffles (US-07+).
function Board:updateBoard()
    for y = self.grid.y_min, self.grid.y_max do
        for x = self.grid.x_min, self.grid.x_max do
            local kind = self.board and MahjongLogic.topTileAt(self.board, x, y) or nil
            local icon = kind and ("mahjong/" .. MahjongLogic.iconForKind(kind)) or "mahjong/empty"
            local button = self.table:getButtonById(self:idFor(x, y))
            if button then button:setIcon(icon, self.button_size) end
        end
    end
    UIManager:setDirty(self, "ui")
end

function Board:handleClick(x, y)
    if self.onTileTap then self.onTileTap(x, y) end
end

return Board
