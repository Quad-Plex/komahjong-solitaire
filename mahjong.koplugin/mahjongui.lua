-- Small UI helpers shared by the plugin's screen-sized widgets.

local Screen = require("device").screen

local UI = {}

function UI.screenSize()
    return Screen:getWidth(), Screen:getHeight()
end

function UI.refreshDimensions(widget)
    widget.full_width, widget.full_height = UI.screenSize()
end

function UI.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- This is deliberately based on the canvas width, rather than DPI. The
-- controls themselves already use scaleBySize; using a scaled threshold here
-- would make a high-DPI phone choose the compact layout despite having ample
-- pixel width.
function UI.isNarrow(width)
    return width < 480
end

return UI
