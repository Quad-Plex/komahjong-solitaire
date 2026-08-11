-- US-03 icons: verifies installIconsIfNeeded() copies every bundled SVG from
-- the plugin's icons/ dir into the data dir's icons/mahjong/ directory,
-- referenced as "mahjong/<name>" by IconWidget. The copy is a Lua io loop (no
-- per-file shell forks), so this test writes to a real temp dir and compares
-- the copied bytes against the bundled originals.

local mock = require("mock")
local ctx = mock.newContext()

local src_icons = mock.ROOT .. "/mahjong.koplugin/icons"
local tmp_dir = mock.ROOT .. "/tests/.tmp/us03"
os.execute('rm -rf "' .. tmp_dir .. '"')
os.execute('mkdir -p "' .. tmp_dir .. '"')
ctx.data_dir = tmp_dir

local function list_dir(dir)
    local f = io.popen('ls -1 "' .. dir .. '"')
    local names = {}
    if f then
        for line in f:lines() do names[#names + 1] = line end
        f:close()
    end
    return names
end

-- Simulate a real icons dir: lfs.dir lists the bundled SVGs, and
-- util.makePath creates the destination directories the io copy needs.
ctx.setMock("libs/libkoreader-lfs", {
    attributes = function(path, mode)
        if path == src_icons or path:match("/translations/?$") then return "directory" end
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
ctx.setMock("util", {
    makePath = function(path)
        os.execute('mkdir -p "' .. path .. '"')
    end,
})

local expected = {}
for _, name in ipairs(list_dir(src_icons)) do
    if name:match("%.svg$") then expected[#expected + 1] = name end
end
assert(#expected > 0, "no SVG icons found in " .. src_icons)

-- Load the real plugin; new() runs init() -> installIconsIfNeeded().
ctx.loadPlugin("mahjonglogic")
ctx.loadPlugin("mahjongboard")
local Mahjong = ctx.loadPlugin("main")
local m = Mahjong:new{ ui = { menu = { registerToMainMenu = function() end } } }
assert(m.name == "mahjong", "plugin failed to init")

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    else
        print("PASS: " .. msg)
    end
end

local dest_dir = tmp_dir .. "/icons/mahjong"
local copied = list_dir(dest_dir)

expect(#copied == #expected, "every SVG installed (" .. #copied .. "/" .. #expected .. ")")

local copied_names = {}
local all_svg = true
for _, name in ipairs(copied) do
    if not name:match("%.svg$") then all_svg = false end
    copied_names[name] = true
end
expect(all_svg, "all copied targets are .svg files")

local missing = {}
for _, name in ipairs(expected) do
    if not copied_names[name] then missing[#missing + 1] = name end
end
expect(#missing == 0, "every bundled SVG reached the data dir" .. (#missing > 0 and (" (missing " .. table.concat(missing, ", ") .. ")") or ""))

-- Byte-for-byte: the io copy must not corrupt any icon.
local identical = true
for _, name in ipairs(expected) do
    local src = assert(io.open(src_icons .. "/" .. name, "rb"))
    local dst = assert(io.open(dest_dir .. "/" .. name, "rb"))
    local same = src:read("*a") == dst:read("*a")
    src:close()
    dst:close()
    if not same then identical = false end
end
expect(identical, "copied icons match the bundled originals byte-for-byte")

os.execute('rm -rf "' .. tmp_dir .. '"')

if failures == 0 then
    print("\nALL US-03 ICON CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
