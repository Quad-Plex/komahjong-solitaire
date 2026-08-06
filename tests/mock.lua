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
    -- Generic getSize/setText so real plugin widgets that call them (e.g.
    -- HudBar, via its chip TextWidgets and children) don't crash headlessly.
    -- Real dimensions aren't available without KOReader, so these are stubs;
    -- HudBar overrides getSize itself.
    function cls:getSize()
        return { w = self.width or 0, h = self.height or 0 }
    end
    function cls:setText(text) self.text = text end
    function cls:resetLayout() end
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
    ctx.dirty_calls = {}
    -- Scheduled-task capture (US-30): the picker defers its deal by a short
    -- UIManager:scheduleIn so the pressed state paints on e-ink before the
    -- board build replaces the picker. Harnesses run the deal with
    -- ctx.runScheduled() (snapshot semantics — tasks added while one runs,
    -- like the timer polling loop's reschedule, stay queued and are not
    -- re-executed, so there is no spin).
    ctx.scheduled = {}

    ctx.screen = {
        getWidth = function() return 1200 end,
        getHeight = function() return 800 end,
        scaleBySize = function(_, px) return px end,
    }

    -- LuaSettings (US-10): in-memory store shared across every open() in a
    -- test context, so a plugin instance can save a game and a later instance
    -- (or a SettingsWidget) can read it back. flush() just counts.
    ctx.settings_store = {}
    ctx.flushes = 0

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
        setDirty = function(_, widget, refreshtype)
            ctx.dirty_calls[#ctx.dirty_calls + 1] = { widget = widget, refreshtype = refreshtype }
        end,
        scheduleIn = function(_, seconds, fn)
            ctx.scheduled[#ctx.scheduled + 1] = { seconds = seconds, fn = fn }
        end,
        nextTick = function(_, fn)
            ctx.scheduled[#ctx.scheduled + 1] = { seconds = 0, fn = fn }
        end,
    }

    local frame_container = widget_base:extend{}
    -- main.lua init() does self.ui.menu:registerToMainMenu(self)
    frame_container.ui = {
        menu = {
            registerToMainMenu = function() ctx.menu_registered = true end,
        },
    }
    -- Real FrameContainer:new copies "layout" to self[1]; mock must do the same
    -- or getSize() crashes with "attempt to index a nil value".
    function frame_container:new(o)
        o = self:extend(o or {})
        if o.layout then o[1] = o.layout end
        -- Mirror Widget:new: call init() if present
        if o.init then o:init() end
        return o
    end

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
        ["luasettings"] = {
            open = function(_, _path)
                local store = ctx.settings_store
                local s = {
                    readSetting = function(_, key, default)
                        local v = store[key]
                        if v == nil then return default end
                        return v
                    end,
                    saveSetting = function(_, key, value)
                        store[key] = value
                    end,
                    delSetting = function(_, key)
                        store[key] = nil
                    end,
                    flush = function()
                        ctx.flushes = ctx.flushes + 1
                    end,
                }
                return s
            end,
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
                -- Faithful to real OverlapGroup:init()/getSize(): it iterates
                -- its children and calls getSize() on EACH one.  A plain
                -- wrapper table (e.g. { overlap_offset = ..., widget }) is NOT
                -- a widget and has no getSize -> mirror the real crash
                -- "attempt to call method 'getSize' (a nil value)" so the
                -- suite catches the bug instead of only the device doing so.
                local size = { w = 0, h = 0 }
                for _, w in ipairs(o) do
                    local ws = w:getSize()
                    if ws.h > size.h then size.h = ws.h end
                    if ws.w > size.w then size.w = ws.w end
                end
                if o.dimen then
                    if o.dimen.w then size.w = o.dimen.w end
                    if o.dimen.h then size.h = o.dimen.h end
                end
                o._size = size
                -- The real OverlapGroup exposes getSize() (returns its dimen),
                -- so a nested OverlapGroup (e.g. the layout-picker thumbnail
                -- wrapped with its trophy badge) is queryable by an outer one.
                o.getSize = function(self)
                    return self.dimen or self._size
                end
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
        -- ScrollableContainer — a pass-through stub. The real widget clips +
        -- scrolls its `content` child; the stub just keeps the options table so
        -- picker layout code that wraps the grid in a ScrollableContainer loads
        -- and the card-rect math is unaffected.
        ["ui/widget/container/scrollablecontainer"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/verticalgroup"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/verticalspan"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/horizontalspan"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/horizontalgroup"] = {
            new = function(_, o) return o end,
        },
        ["ui/widget/textwidget"] = {
            new = function(_, o)
                o = o or {}
                setmetatable(o, { __index = widget_base })
                return o
            end,
        },
        ["ui/font"] = {
            getFace = function(_, name, size)
                return {
                    name = name,
                    size = size,
                    ftsize = { getHeightAndAscender = function() return 20, 15 end },
                }
            end,
        },
        ["ui/widget/button"] = (function()
            -- A proper class (not a bare table) so main.lua can subclass it
            -- (LongPressButton for the US-19 auto-solve hold hook). The real
            -- Button handles the "hold"/"hold_release" gestures; the stubs
            -- mirror the callbacks so a subclass override can call through.
            local btn = input_container:extend{}
            btn.new = function(self, o)
                o = o or {}
                o.getSize = function() return { w = o.width or 32, h = o.height or 32 } end
                return setmetatable(o, { __index = self })
            end
            btn.onHoldSelectButton = function(self)
                if self.hold_callback then self.hold_callback() end
            end
            btn.onHoldReleaseSelectButton = function(self)
                if self.hold_release_callback then self.hold_release_callback() end
                return true
            end
            return btn
        end)(),
        ["ui/widget/titlebar"] = {
            new = function(_, o)
                o = o or {}
                o.getSize = function() return { h = 40 } end
                o.setSubTitle = function(_, s) ctx.status_subtitle = s end
                o.setTitle = function() end
                return o
            end,
        },
        ["ui/widget/confirmbox"] = {
            new = function(_, o)
                o = o or {}
                -- Faithful to the real ConfirmBox: onClose runs cancel_callback
                -- (used by the Close button AND the tap-outside gesture), and
                -- onTapClose calls onClose when the tap is outside the dialog's
                -- movable dimen. The mock has no real dimen, so tests set
                -- o.movable.dimen to delimit the dialog; without it every tap
                -- is "outside".
                o.onClose = function(self)
                    if self.cancel_callback then self.cancel_callback() end
                    require("ui/uimanager"):close(self)
                    return true
                end
                o.onTapClose = function(self, arg, ges)
                    local d = self.movable and self.movable.dimen
                    local inside = d and ges and ges.pos
                        and ges.pos.x >= d.x and ges.pos.x < d.x + d.w
                        and ges.pos.y >= d.y and ges.pos.y < d.y + d.h
                    if not inside then self:onClose() end
                    return true
                end
                return o
            end,
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

    -- Preload the REAL plugin modules too, so a require() from one plugin
    -- module to another (e.g. main.lua requires hudbar) resolves regardless
    -- of the order tests call ctx.loadPlugin(). The module bodies only run
    -- when require()'d; ctx.loadPlugin() (below) loads the same file.
    for _, name in ipairs({ "mahjonglayouts", "mahjonglogic", "mahjongstats", "mahjongboard", "hudbar", "mahjongsettings", "mahjongstatswidget", "mahjongpause", "mahjonglayoutselect", "main" }) do
        local path = M.ROOT .. "/mahjong.koplugin/" .. name .. ".lua"
        local chunk, err = loadfile(path)
        assert(chunk, "cannot preload plugin module " .. name .. ": " .. tostring(err))
        package.preload[name] = chunk
    end

    -- Override/insert a stub (call BEFORE loading the plugin modules).
    ctx.setMock = function(name, mod)
        ctx.mocks[name] = mod
        package.preload[name] = function() return mod end
    end

    -- Run the first `n` currently-pending scheduled tasks (default: all of
    -- them), snapshot semantics: tasks scheduled while one of these runs stay
    -- queued for a later call, so a self-rescheduling loop (the timer's
    -- polling tick) cannot spin here. Returns how many tasks ran.
    ctx.runScheduled = function(n)
        local total = n and math.min(n, #ctx.scheduled) or #ctx.scheduled
        for _ = 1, total do
            local e = table.remove(ctx.scheduled, 1)
            e.fn()
        end
        return total
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
