-- Shared KOReader stub infrastructure for the headless test suite.
--
-- Each tests/us*.lua creates a fresh context with mock.newContext(), loads the
-- REAL plugin modules through it (mock:loadPlugin), and asserts behavior.
-- KOReader's UI cannot be exercised headlessly; the stubs prove load-order,
-- return values, and control flow. Visual checks still need the device/emulator.
--
-- Adding a future story's test: reuse this file. Add any new stubs here (or
-- override one via ctx:setMock(...) before loading the plugin modules) and
-- write the checks against the real plugin code.

local src = debug.getinfo(1, "S").source or ""
src = src:gsub("^@", "")
local M = {}

-- Repo root. run.sh exports TESTS_DIR (absolute path to this dir); fall back to
-- deriving it from this file's source path when run directly.
local function normalize(path)
    path = (path or ""):gsub("\\", "/")
    return path:gsub("/+$", "")
end
local tests_dir = os.getenv("TESTS_DIR")
if tests_dir then
    M.ROOT = normalize(tests_dir) .. "/.."
else
    M.ROOT = normalize(src:match("^(.*[/\\])tests[/\\]mock%.lua$")) or "."
end

local function make_class()
    local cls = {}
    function cls:new(opts)
        local inst = setmetatable(opts or {}, { __index = self })
        if inst._init then inst:_init() end
        if inst.init then inst:init() end
        return inst
    end
    -- NOTE: must be a colon receiver (function(self, o)) or :extend{...} drops
    -- the class table -> "loop in gettable" at runtime.
    function cls:extend(o)
        o = o or {}
        o.__index = o
        setmetatable(o, { __index = self })
        return o
    end
    function cls:free() end
    return cls
end

local widget_base = make_class()
local input_container = widget_base:extend{}
function input_container:new(opts)
    local inst = widget_base.new(self, opts)
    inst.ges_events = inst.ges_events or {}
    return inst
end
input_container.ges_events = {}

M.input_container = input_container

local function geom_new(_, t) return t end

function M.newContext()
    local ctx = {}
    ctx.window_stack = {}
    ctx.last_confirm = nil
    ctx.confirms = {}
    ctx.menu_registered = false
    ctx.dispatcher_actions = {}

    ctx.screen = {
        getWidth = function() return 1200 end,
        getHeight = function() return 800 end,
        scaleBySize = function(_, px) return px end,
    }

    local uimanager = {
        _window_stack = ctx.window_stack,
        isWidgetShown = function(_, w)
            for _, e in ipairs(ctx.window_stack) do
                if e.widget == w then return true end
            end
            return false
        end,
        show = function(_, w)
            if w and w.ok_callback then
                ctx.last_confirm = w
                ctx.confirms[#ctx.confirms + 1] = w
            end
            table.insert(ctx.window_stack, { widget = w })
        end,
        close = function(_, w)
            for i = #ctx.window_stack, 1, -1 do
                if ctx.window_stack[i].widget == w then table.remove(ctx.window_stack, i) end
            end
            if w and w.onCloseWidget then w:onCloseWidget() end
        end,
        setDirty = function() end,
        scheduleIn = function() end,
        nextTick = function() end,
    }

    local frame_container = widget_base:extend{}
    -- main.lua init() does self.ui.menu:registerToMainMenu(self)
    frame_container.ui = {
        menu = {
            registerToMainMenu = function() ctx.menu_registered = true end,
        },
    }

    ctx.mocks = {
        ["device"] = { screen = ctx.screen },
        ["ffi/blitbuffer"] = {
            COLOR_WHITE = "white",
            COLOR_BLACK = "black",
            COLOR_LIGHT_GRAY = "light_gray",
            COLOR_DARK_GRAY = "dark_gray",
        },
        ["datastorage"] = {
            getDataDir = function() return ctx.data_dir or (M.ROOT .. "/tests/.tmp") end,
            getSettingsDir = function() return ctx.data_dir or (M.ROOT .. "/tests/.tmp") end,
        },
        ["dispatcher"] = {
            registerAction = function(_, id, spec)
                ctx.dispatcher_actions[id] = spec
            end,
        },
        ["ui/uimanager"] = uimanager,
        ["ui/geometry"] = { new = geom_new },
        ["ui/gesturerange"] = { new = function(_, o) return o end },
        ["ui/widget/container/framecontainer"] = frame_container,
        ["ui/widget/container/inputcontainer"] = input_container,
        ["ui/widget/overlapgroup"] = {
            new = function(cls, o)
                o = o or {}
                setmetatable(o, { __index = cls })
                if o.init then o:init() end
                return o
            end,
        },
        ["ui/widget/iconwidget"] = {
            new = function(_, o)
                o = o or {}
                setmetatable(o, { __index = widget_base })
                return o
            end,
        },
        ["ui/widget/container/centercontainer"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/verticalgroup"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/button"] = {
            new = function(_, o) o = o or {}; return o end,
        },
        ["ui/widget/titlebar"] = {
            new = function(_, o) o.getSize = function() return { h = 40 } end; return o end,
        },
        ["ui/widget/confirmbox"] = {
            new = function(_, o) o = o or {}; return o end,
        },
        ["libs/libkoreader-lfs"] = {
            attributes = function() return "file" end,
            dir = function() return function() return nil end end,
        },
        ["util"] = {
            makePath = function() end,
        },
        ["gettext"] = function(s) return s end,
    }

    for name, mod in pairs(ctx.mocks) do
        package.preload[name] = function() return mod end
    end

    -- Override/insert a stub (call BEFORE loading the plugin modules).
    ctx.setMock = function(name, mod)
        ctx.mocks[name] = mod
        package.preload[name] = function() return mod end
    end

    -- Load a REAL plugin module as a preload chunk and require() it.
    -- Load in dependency order: mahjonglogic, mahjongboard, main.
    ctx.loadPlugin = function(name)
        local path = M.ROOT .. "/mahjong.koplugin/" .. name .. ".lua"
        local chunk, err = loadfile(path)
        assert(chunk, "cannot load plugin module " .. name .. ": " .. tostring(err))
        package.preload[name] = chunk
        return require(name)
    end

    return ctx
end

return M
