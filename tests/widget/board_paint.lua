-- Regression for the startup crash:
-- FrameContainer:paintTo() calls getSize() and then computes
--     x + margin + bordersize + _padding_left + shift_x
-- The old board overrode FrameContainer:getSize() without setting the
-- _padding_* fields -> "attempt to perform arithmetic on field '_padding_left'
-- (a nil value)" (the crash seen in crash.log).
-- The 3D board sidesteps this: it extends InputContainer (not FrameContainer)
-- and its getSize() returns self.dimen, so no _padding_* contract applies.
-- Verifies the inheritance, the inner paint container's fields, and that the
-- paint arithmetic is safe.

local mock = require("mock")
local ctx = mock.newContext()

local Logic = ctx.loadPlugin("mahjonglogic")
local Board = ctx.loadPlugin("mahjongboard")

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

-- Board extends InputContainer, NOT FrameContainer (no getSize-override hazard).
expect(getmetatable(Board).__index == mock.input_container,
    "Board extends InputContainer (not FrameContainer)")

local b = Board:new{
    board = Logic.newGame(),
    width = 600,
    height = 700,
    onTileTap = function() end,
}

local sz = b:getSize()
expect(sz.w == 600 and sz.h == 700, "getSize returns the board dimen (600x700)")

-- The painted content is a stock FrameContainer with padding/bordersize 0,
-- so its own paintTo arithmetic resolves _padding_left from the padding field.
local inner = b[1]
expect(type(inner) == "table", "board built its paint container")
expect(inner.padding == 0 and inner.bordersize == 0, "inner container uses zero padding/bordersize")

-- Simulate stock FrameContainer:getSize padding fallback used at paint time.
local pad_l = inner.padding_left or inner.padding
local pad_r = inner.padding_right or inner.padding
local pad_t = inner.padding_top or inner.padding
local pad_b = inner.padding_bottom or inner.padding
expect(type(pad_l) == "number" and type(pad_r) == "number"
       and type(pad_t) == "number" and type(pad_b) == "number",
    "all four _padding_* fields resolve at paint time")

-- Simulate the exact paintTo arithmetic that used to crash (on the inner frame).
local shift_x = 0
local x = 10
local xx = x + (inner.margin or 0) + (inner.bordersize or 0) + pad_l + shift_x
expect(type(xx) == "number", "paintTo x arithmetic no longer errors")

-- Rebuilding (free + rebuild path) must be repeatable.
b:updateBoard()
local rendered_faces = 0
for _ in pairs(b.tile_widgets or {}) do rendered_faces = rendered_faces + 1 end
expect(type(b[1]) == "table" and rendered_faces == 144
        and #b[1][1] > rendered_faces,
    "updateBoard rebuilds the full 144 faces and separate bevel widgets")
local sz2 = b:getSize()
expect(sz2.w == 600 and sz2.h == 700, "getSize still returns the board dimen after rebuild")

if failures == 0 then
    print("\nALL US-06 PAINT-CONTRACT CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
