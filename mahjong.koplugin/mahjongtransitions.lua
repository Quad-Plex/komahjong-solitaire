-- Deferred transition boundary. It deliberately delegates to private owner
-- implementations so all identity and token guards remain in one lifecycle owner.
local Transitions = {}

function Transitions.scheduleFullScreenRefresh(self, ...) return self:_scheduleFullScreenRefresh(...) end
function Transitions.isBoardRefreshActive(self, ...) return self:_isBoardRefreshActive(...) end
function Transitions.handleNoMoves(self, ...) return self:_handleNoMoves(...) end
function Transitions.showDeadBoardDialog(self, ...) return self:_showDeadBoardDialog(...) end
function Transitions.checkGameState(self, ...) return self:_checkGameState(...) end
function Transitions.scheduleWinDialog(self, ...) return self:_scheduleWinDialog(...) end
function Transitions.scheduleDeadBoardDialog(self, ...) return self:_scheduleDeadBoardDialog(...) end

return Transitions
