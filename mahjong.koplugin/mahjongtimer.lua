-- Timer controller. State remains on the Mahjong owner; this module only
-- centralizes lifecycle and repaint scheduling.
local UIManager = require("ui/uimanager")
local MahjongLogic = require("mahjonglogic")

local Timer = {}

function Timer.mode(self)
    return self:getSetting("timer_update", self._timer_defaults.timer_update)
end

function Timer.interval(self)
    local value = tonumber(self:getSetting("timer_interval", self._timer_defaults.timer_interval))
    if not value or value < self._timer_min_interval then
        return self._timer_defaults.timer_interval
    end
    return value
end

function Timer.elapsed(self)
    if self._timer_running and self._timer_started_at then
        return self.elapsed_base + os.difftime(os.time(), self._timer_started_at)
    end
    return self.elapsed_base
end

function Timer.start(self)
    self._timer_run_id = self._timer_run_id + 1
    local run_id = self._timer_run_id
    self._timer_started_at = os.time()
    self._timer_running = true
    if self._last_hint and self.board_view then self:startHintPulse(self._last_hint) end
    if Timer.mode(self) ~= "interval" then return end

    local interval = Timer.interval(self)
    local tick
    tick = function()
        if not self._timer_running or self._timer_run_id ~= run_id then return end
        if self.board_view and self.board_view.has_pending_refresh_retry
                and self.board_view:has_pending_refresh_retry() then
            UIManager:scheduleIn(interval, tick)
            return
        end
        Timer.refreshDisplay(self)
        UIManager:scheduleIn(interval, tick)
    end
    UIManager:nextTick(tick)
end

function Timer.stop(self)
    if self._timer_running then self.elapsed_base = Timer.elapsed(self) end
    self._timer_running = false
    self._timer_run_id = self._timer_run_id + 1
    self._hint_pulse_token = self._hint_pulse_token + 1
end

function Timer.reset(self)
    Timer.stop(self)
    self.elapsed_base = 0
    Timer.start(self)
end

function Timer.updateText(self)
    if not self.timer_text then return end
    self.timer_text:setText(MahjongLogic.formatElapsed(Timer.elapsed(self)))
    if self.timer_text.resetLayout then self.timer_text:resetLayout() end
end

function Timer.refreshDisplay(self)
    if not self.timer_text then return end
    Timer.updateText(self)
    UIManager:setDirty(self, "ui", self.timer_region or self.flash_region or self.timer_text.dimen)
    self:bakeLowerChrome()
end

function Timer.updateDisplay(self)
    Timer.updateText(self)
    if Timer.mode(self) ~= "move" then return end
    local refresh = function()
        UIManager:setDirty(self, "ui", self.timer_region or self.flash_region or self.timer_text.dimen)
        self:bakeLowerChrome()
    end
    if self._defer_chrome_refresh then
        self:deferChromeRefresh(refresh)
    else
        refresh()
    end
end

return Timer
