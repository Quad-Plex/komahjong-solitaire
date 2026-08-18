-- Small UI helpers shared by the plugin's screen-sized widgets.

local Screen = require("device").screen
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")

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

-- Pick the largest face that fits both dimensions of a bounded text slot.
-- TextWidget is single-line, so callers should still provide max_width as a
-- final ellipsis guard for translations or live values that grow later.
function UI.fitTextFace(text, face_name, preferred_size, minimum_size, max_width, max_height)
    local size = math.max(1, math.floor(preferred_size))
    local minimum = math.max(1, math.floor(minimum_size))
    while size >= minimum do
        local face = Font:getFace(face_name, size)
        local probe = TextWidget:new{ text = text, padding = 0, face = face }
        local dimen = probe:getSize()
        if probe.free then probe:free() end
        if (not max_width or dimen.w <= max_width)
                and (not max_height or dimen.h <= max_height) then
            return face, size
        end
        size = size - 1
    end
    return Font:getFace(face_name, minimum), minimum
end

return UI
