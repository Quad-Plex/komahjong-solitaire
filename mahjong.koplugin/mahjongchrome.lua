-- Lower-chrome repaint controller. Widget ownership and regions stay on Mahjong.
local UIManager = require("ui/uimanager")
local MahjongLogic = require("mahjonglogic")

local Chrome = {}

function Chrome.region(self)
    return self.lower_band_region or self.toolbar_region or self.flash_region
end

function Chrome.bake(self)
    if not UIManager.widgetRepaint or not self.toolbar_region or not self.flash_region then return end
    if self.flash_band then UIManager:widgetRepaint(self.flash_band, 0, self.flash_region.y) end
    if self.toolbar_widget then UIManager:widgetRepaint(self.toolbar_widget, 0, self.toolbar_region.y) end
end

function Chrome.settle(self)
    if not UIManager.tickAfterNext or self._chrome_settle then return end
    self._chrome_settle = true
    local board = self.board
    UIManager:tickAfterNext(function()
        self._chrome_settle = false
        if self.board ~= board or not self.toolbar_widget or not self.board_view then return end
        UIManager:setDirty(nil, "ui", Chrome.region(self))
    end)
end

function Chrome.defer(self, fn)
    if not UIManager.tickAfterNext then
        if fn then fn() end
        return
    end
    local board = self.board
    local fns = self._deferred_chrome_fns or {}
    self._deferred_chrome_fns = fns
    fns[#fns + 1] = fn
    if #fns ~= 1 then return end
    UIManager:tickAfterNext(function()
        local pending = self._deferred_chrome_fns
        self._deferred_chrome_fns = nil
        if self.board ~= board then return end
        for i = 1, #pending do if pending[i] then pending[i]() end end
        Chrome.bake(self)
    end)
end

function Chrome.updateStatus(self)
    if not self.status_bar then return end
    self.status_bar:setStats(math.floor(MahjongLogic.tileCount(self.board) / 2),
        MahjongLogic.countFreePairs(self.board, self.layout), self.score)
    local structural = false
    if self.hint_counter_badge then
        local text = tostring(self.hints_used or 0)
        structural = structural or self.hint_counter_badge.text ~= text
        self.hint_counter_badge:setText(text)
    end
    if self.shuffle_counter_badge then
        local text = tostring(self.shuffles_used or 0)
        structural = structural or self.shuffle_counter_badge.text ~= text
        self.shuffle_counter_badge:setText(text)
    end
    local refresh = function()
        UIManager:setDirty(self, "ui", self.status_region or self.status_bar.dimen)
        if self.toolbar_region then
            UIManager:setDirty(self, "ui", self.toolbar_region)
            Chrome.bake(self)
        end
    end
    if self._defer_chrome_refresh then Chrome.defer(self, refresh) else refresh() end
    if structural then Chrome.settle(self) end
end

return Chrome
