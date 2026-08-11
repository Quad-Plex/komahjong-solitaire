-- Ownership of KOReader's automatic-standby policy for one visible game.
-- This intentionally does not handle explicit power-button or cover events.
local Device = require("device")

local Awake = {}

function Awake.acquire(owner)
    if owner._awake_owned then return end
    Device:setAutoStandby(false)
    owner._awake_owned = true
end

function Awake.release(owner)
    if not owner._awake_owned then return end
    Device:setAutoStandby(true)
    owner._awake_owned = false
end

return Awake
