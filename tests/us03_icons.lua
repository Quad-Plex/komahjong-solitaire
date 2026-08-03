-- US-03 icons: verifies installIconsIfNeeded() copies every bundled SVG from
-- the plugin's icons/ dir into the (stubbed) data dir, referenced as
-- "mahjong/<name>" by IconWidget. Exercises the real main.lua init path with
-- a real plugin icons directory and captured `cp` invocations.

local mock = require("mock")
local ctx = mock.newContext()

local src_icons = mock.ROOT .. "/mahjong.koplugin/icons"

local function list_dir(dir)
    local f = io.popen('ls -1 "' .. dir .. '"')
    local names = {}
    if f then
        for line in f:lines() do names[#names + 1] = line end
        f:close()
    end
    return names
end

-- Simulate a real icons dir that needs installing (dest does not exist yet).
ctx.setMock("libs/libkoreader-lfs", {
    attributes = function(path, mode)
        if path == src_icons then return "directory" end
        return nil
    end,
    dir = function(path)
        local names = list_dir(path)
        local i = 0
        return function()
            i = i + 1
            return names[i]
        end
    end,
})

-- Capture every `cp` installIconsIfNeeded issues instead of writing anywhere.
local copied = {}
local real_execute = os.execute
os.execute = function(cmd)
    local src, dst = cmd:match('cp "([^"]+)" "([^"]+)"')
    if src then
        assert(io.open(src, "rb"), "cp source missing: " .. src)
        copied[#copied + 1] = { src = src, dst = dst }
        return true
    end
    return real_execute(cmd)
end

-- Load the real plugin; new() runs init() -> installIconsIfNeeded().
ctx.loadPlugin("mahjonglogic")
ctx.loadPlugin("mahjongboard")
local Mahjong = ctx.loadPlugin("main")
local m = Mahjong:new{ ui = { menu = { registerToMainMenu = function() end } } }
assert(m.name == "mahjong", "plugin failed to init")

-- The expected set is exactly the SVGs bundled in the repo.
local expected = {}
for _, name in ipairs(list_dir(src_icons)) do
    if name:match("%.svg$") then expected[#expected + 1] = name end
end
assert(#expected > 0, "no SVG icons found in " .. src_icons)

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

expect(#copied == #expected, "every SVG installed (" .. #copied .. "/" .. #expected .. ")")

local copied_names = {}
local all_copied = true
for _, c in ipairs(copied) do
    local name = c.dst:match("([^/]+)$")
    if not name:match("%.svg$") then all_copied = false end
    copied_names[name] = true
end
expect(all_copied, "all copied targets are .svg files")

local missing = {}
for _, name in ipairs(expected) do
    if not copied_names[name] then missing[#missing + 1] = name end
end
expect(#missing == 0, "every bundled SVG reached the data dir" .. (#missing > 0 and (" (missing " .. table.concat(missing, ", ") .. ")") or ""))

local dest_prefix = (ctx.data_dir or (mock.ROOT .. "/tests/.tmp")) .. "/icons/mahjong/"
local dest_ok = true
for _, c in ipairs(copied) do
    if c.dst:sub(1, #dest_prefix) ~= dest_prefix then dest_ok = false end
end
expect(dest_ok, "copied into the mahjong icon dir")

if failures == 0 then
    print("\nALL US-03 ICON CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
