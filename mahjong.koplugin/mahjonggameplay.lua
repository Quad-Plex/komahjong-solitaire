-- Gameplay boundary. The owner retains every mutable field and all UI objects.
-- Implementations remain private owner methods while this module is the single
-- dependency surface used by main.lua's public compatibility facade.
local Gameplay = {}

function Gameplay.handleTileTap(self, ...) return self:_handleTileTap(...) end
function Gameplay.applyMatch(self, ...) return self:_applyMatch(...) end
function Gameplay.setSelection(self, ...) return self:_setSelection(...) end
function Gameplay.clearSelection(self, ...) return self:_clearSelection(...) end
function Gameplay.undo(self, ...) return self:_undo(...) end
function Gameplay.clearHint(self, ...) return self:_clearHint(...) end
function Gameplay.clearHintBatched(self, ...) return self:_clearHintBatched(...) end
function Gameplay.startHintPulse(self, ...) return self:_startHintPulse(...) end
function Gameplay.showHint(self, ...) return self:_showHint(...) end
function Gameplay.shuffleBestDeadBoard(self, ...) return self:_shuffleBestDeadBoard(...) end
function Gameplay.shuffleBoard(self, ...) return self:_shuffleBoard(...) end

return Gameplay
