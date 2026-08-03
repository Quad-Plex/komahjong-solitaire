# AGENTS.md — Writing Native KOReader Plugins

This document captures what I learned from studying `example_app/casualkochess.koplugin`
(a working chess/checkers/reversi/fox-and-hounds suite for jailbroken e-ink readers running
KOReader) plus the official KOReader documentation, so that future agents can write native
KOReader plugins (and specifically the Mahjong Solitaire plugin in this repo) correctly.

## What KOReader is

KOReader is an open-source document reader (Lua) that runs on jailbroken Kindles, Kobos,
PocketBooks, etc. It has a plugin system: drop a directory ending in `.koplugin` into the
KOReader `plugins/` directory and it is loaded at startup. Everything is Lua (5.1-compatible
plus some 5.2/5.3 bits), rendered on an e-ink screen.

## Plugin structure (minimum required)

A plugin is a directory `<name>.koplugin/` containing at least:

```
name.koplugin/
├── _meta.lua     # metadata for KOReader's plugin manager
└── main.lua      # entry point; returns the plugin's widget class
```

Optional extra `.lua` files are `require`d by `main.lua`. KOReader adds the plugin directory
to `package.path` before loading, so `require("chessgame")` inside a plugin resolves to
`<plugin-dir>/chessgame.lua`.

### `_meta.lua`

```lua
local _ = require("gettext")
return {
    name        = "pluginname",           -- lowercase, no spaces; matches dir name
    fullname    = _("Display Name"),
    description = _([[One-line description.]]),
}
```

`fullname`/`description` should be wrapped in `_()` for translation.

### `main.lua`

The file returns a widget class. For a plain menu plugin you extend `WidgetContainer`; for a
full-screen game you extend a full-screen container (`FrameContainer`) like the chess example.

```lua
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local MyPlugin = WidgetContainer:extend{
    name = "pluginname",
    is_doc_only = false,   -- false = available from FileManager & reader
}

function MyPlugin:init()
    self.ui.menu:registerToMainMenu(self)
end

function MyPlugin:addToMainMenu(menu_items)
    menu_items.pluginname = {
        text = _("My Plugin"),
        sorting_hint = "tools",          -- or "more_tools", "main", ...
        callback = function() self:run() end,
    }
end

return MyPlugin
```

Key facts:
- `init()` is called when the plugin is instantiated. Use it to register menu entries
  (`self.ui.menu:registerToMainMenu(self)` → calls `addToMainMenu`) and dispatcher actions.
- `sorting_hint` controls which (sub)menu the entry appears in: `tools`, `more_tools`,
  `main`, `setting`, `filemanager`, `search`, etc.
- Dispatcher actions (optional): `Dispatcher:registerAction("id", {category="none",
  event="EventName", title=_("..."), general=true})` then implement `onEventName()`. This lets
  users bind gestures/profiles to launch the plugin.

## Core KOReader modules used by game plugins

| Module | Purpose |
|---|---|
| `device` | `Device.screen`, `Screen:getWidth()/getHeight()`, `Screen:scaleBySize(px)` (e-ink DPI scaling) |
| `ui/uimanager` | `UIManager:show(w)`, `UIManager:close(w)`, `UIManager:setDirty(w, "ui"/"full")`, `UIManager:scheduleIn(s, fn)`, `UIManager:nextTick(fn)` |
| `ui/geometry` | `Geometry:new{w=..,h=..}` dimen objects |
| `ui/font`, `ui/size` | `Font:getFace("smallinfofont", size)`, `Size.padding.*`, `Size.radius.*` |
| `ffi/blitbuffer` | `Blitbuffer.COLOR_WHITE`, `COLOR_LIGHT_GRAY`, `COLOR_DARK_GRAY`, etc. |
| `luasettings` | Persistent settings: `LuaSettings:open(path)`, `readSetting/writeSetting/flush` |
| `datastorage` | `DataStorage:getDataDir()`, `DataStorage:getSettingsDir()` |
| `gettext` | `_("string")` for translatable UI text |
| `dispatcher` | Gesture/profile actions |
| `json` | JSON encode/decode |
| `libs/libkoreader-lfs` | `lfs.attributes`, `lfs.dir`, `lfs.mkdir` (file IO helpers) |
| `util` | `util.makePath(...)` etc. |

## Building a full-screen game widget (the pattern in the example)

The chess example is the best template. The plugin class extends `FrameContainer` with
full-screen dimensions and replaces itself with a layout of widgets:

```lua
local Kochess = FrameContainer:extend{
    name = "casualkochess",
    background = Blitbuffer.COLOR_WHITE,
    full_width = Screen:getWidth(),
    full_height = Screen:getHeight(),
    ...
}

function Kochess:init()
    self.dimensions = Geometry:new{ w = self.full_width, h = self.full_height }
    self.covers_fullscreen = true
    Dispatcher:registerAction("casualkochess", {...})
    self.ui.menu:registerToMainMenu(self)
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/casualkochess.lua")
end
```

Flow for starting the game:
1. `startGame()` checks `UIManager:isWidgetShown(self)` and closes if open.
2. Initializes game logic + timer + engine, builds the layout into `self[1]`
   (the widget's content — a `VerticalGroup`), restores saved state, calls `board:updateBoard()`.
3. `UIManager:show(self)`.
4. If a computer side is to move, kick it off (`UIManager:nextTick(function() self:launchCurrentComputerMove() end)`).

Important quirks learned from the example:
- `onCloseWidget()` must clean up timers/engine/processes.
- `handleEvent()` must guard: the Dispatcher can fire `onCasualChessStart` while the widget is
  NOT on the window stack, and the FileManager can still propagate events after close. The
  example checks whether `self` is present in `UIManager._window_stack` before forwarding.
- The layout is built once and stored in `self[1]`; `UIManager:setDirty(self, "ui")` triggers
  repaints after state changes.

## Rendering a board with `ButtonTable`

The board is a grid of equal-sized square buttons:

```lua
local ButtonTable = require("ui/widget/buttontable")

self.table = ButtonTable:new{
    width = cell * GRID_SIZE,
    buttons = grid,              -- rows of button-spec tables
    shrink_unneeded_width = false,
    zero_sep = true, sep_width = 0,
    addVerticalSpan = function() end,
}
```

Each cell in `grid` is a table: `{ id=.., icon="icon/name", alpha=true, width=cell,
icon_width=cell, icon_height=cell-h, bordersize=.., callback=function() self:handleClick(...) end }`.
After creating the table you can look cells up with `self.table:getButtonById(id)` and change
icons with `button:setIcon(icon_name, size)`.

Cell sizing: `Screen:scaleBySize()` for padding; compute `cell = floor(min(usable_w, usable_h)/n)`
so squares fit the screen. Note ButtonTable adds vertical padding inside each button, so the
icon height is `cell - 2*padding`.

The example ships a custom `buttontable.lua` that monkey-patches stock `Button`/`ButtonTable`
to pass `alpha = true` through to `IconWidget` so transparent SVGs aren't flattened to white.
If you use transparent tile SVGs you need the same patch (copy the file into the plugin and
`require("buttontable")` instead of the stock one).

Overlays for selection/hints are done by wrapping a cell's icon in an `OverlapGroup` and
appending `IconWidget`s (see `overlayIcon`/`clearOverlay` in `reversiboard.lua`). This is how
"selected tile" and "hint" highlights are drawn on top of a tile without rebuilding the table.

## Icons / SVG assets

- Icons are SVG files. `IconWidget` resolves icon names against KOReader's icon search paths.
- The example copies its SVGs from the plugin dir into `DataStorage:getDataDir() .. "/icons/casualchess/"`
  on init (see `installIconsIfNeeded`) and then references them as `"casualchess/wP"` etc.
  This keeps the plugin self-contained and installable without touching KOReader's own icons.
- Keep SVGs simple (flat fills, minimal strokes) — they're rendered to grayscale blitbuffers on
  e-ink. Colors are still fine; they'll render as shades of gray.
- Overlay icons (`select.svg`, `hint.svg`) should have transparency so they can layer.

## Input handling

- Taps on board cells fire the `callback` in each button spec.
- For `InputContainer` `ges_events` (e.g. `TapSelect = { GestureRange:new{...} }`), KOReader's
  `onGesture` builds `Event:new(name, gsseq.args, ev)` and `EventListener:handleEvent` calls the
  handler as `self[event.handler](self, unpack(event.args))` → the handler receives
  **`(gsseq.args, gesture_event)`**. Unless you set `args` in the gesture spec, the FIRST arg is
  `nil` and the actual gesture is the **SECOND** arg. Correct signature:
  `function Board:onTapSelect(_, ges)` (use `ges.pos`, `ges.pos.x` etc.). Writing
  `onTapSelect(ges)` crashes with `attempt to index local 'ges' (a nil value)` the moment the
  gesture fires (this bug shipped once in US-06).
- A tap on the title bar's left icon / close icon fires `left_icon_tap_callback` /
  `close_callback` (see `TitleBarWidget`).
- General widget events are methods `onXxx()`; e.g. `onCloseWidget()` for cleanup.
- For e-ink, avoid hover/long-press complexity; single taps are the primary input.

## Settings persistence

```lua
self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/pluginname.lua")
-- read
local v = self.settings:readSetting("key", default)
-- write + persist
self.settings:saveSetting("key", value); self.settings:flush()
```

Game state (position, turn, history, timers) is serialized and restored:
- Chess uses PGN text; checkers/reversi use `export_state()` / `load_state()` tables stored via
  settings keys (see `saveReversiGameState`/`restoreReversiGameState`).
- Save on close (`onCloseWidget` or title-bar close callback), restore on `startGame()`.

## Cooperative AI / non-blocking work

E-ink devices are slow; never block the UI loop. The example runs AI inside a coroutine and
resumes it on a timer:

```lua
co = coroutine.create(function() return AI.bestMove(game, depth, chance, yield_fn) end)
-- step(): coroutine.resume(co); if not dead, UIManager:scheduleIn(resume_delay, step)
```

`yield_fn` is called periodically inside the AI search; after N checkpoints it yields so the UI
can process input/repaint. `runCooperativeAI(busy_key, guard, compute, apply)` in
`casualkochess.koplugin/main.lua` is the reference implementation. It also shows a "Computer
thinking..." indicator after ~3s of wall time.

Simple timers (e.g. a game clock) are driven by `UIManager:scheduleIn` polling loops
(see `utils.lua:Utils.pollingLoop` and `timer.lua`).

## Full-screen layout building blocks

Compose the screen with containers:
- `VerticalGroup` / `HorizontalGroup` (stack children), `VerticalSpan`/`HorizontalSpan` (spacers)
- `FrameContainer` (borders/padding/background), `CenterContainer` (centers a child),
  `LeftContainer`/`RightContainer`, `MovableContainer` (drag anywhere)
- `OverlapGroup` (layer widgets on top of each other)
- `TitleBarWidget` (status/title bar with optional icons + callbacks)
- `TextBoxWidget` / `TextWidget` (multi-line / single-line text)
- Dialogs: `InfoMessage`, `ConfirmBox`, `InputDialog`, `PathChooser`, `RadioButtonTable`,
  `DoubleSpinWidget`, `ButtonProgressWidget`

The chess example's `buildUILayout()` computes cell/row sizes from `full_width`/`full_height`
and stacks: `board` → log section → `status_bar` in a full-screen `VerticalGroup`.

## Events / dirtying

- After mutating visible state you must call `UIManager:setDirty(widget, "ui")` (or `"full"`
  for full-screen refresh on e-ink) or the change won't paint.
- For dialogs you've built, dirty the dialog; for the board, dirty the board or `"all"`.

## Testing and iteration workflow

- There is no unit-test harness in the example. The practical loop is: edit Lua → copy/rsync the
  `.koplugin` dir onto the device (or into KOReader's `plugins/` on the emulator) → restart
  KOReader → exercise the menu entry.
- KOReader on desktop (Linux) is the fastest way to iterate; the plugin code is portable. Run
  the KOReader emulator and drop the plugin into `plugins/`.
- Write the game-logic modules (rules, free-tile detection, shuffle) as pure Lua with no
  UI dependencies so they can be tested with plain `lua`/`luajit` scripts (`--`-style self-tests
  or a small test runner) before wiring the UI.
- Use `luacheck` for linting if available; keep `require`s at the top, wrap user strings in `_()`.

## Common pitfalls (from the example + docs)

- Forgetting `UIManager:setDirty` → UI doesn't update.
- Blocking the main loop with long synchronous computation (AI, big board init) → use the
  coroutine + `scheduleIn` pattern.
- Loading a plugin while a widget is mid-lifecycle: guard `handleEvent` against the widget not
  being on the window stack.
- Not cleaning up on `onCloseWidget` (timers keep firing, subprocesses leak).
- SVG icons that don't exist or have wrong paths → blank cells; verify icon install + name.
- Alpha transparency not passing through → flat/white boxes (use the patched `buttontable.lua`).
- Mixing `Geometry` dimen objects with `Screen` objects; always build `Geometry:new{...}` for
  containers/dialogs.
- Hardcoding pixel sizes; use `Screen:scaleBySize()` so it works across Kindle models.
- Overriding `getSize()` on a `FrameContainer` subclass WITHOUT setting the
  `_padding_left/_padding_right/_padding_top/_padding_bottom` fields → every paint of that widget
  crashes with `framecontainer.lua:143: attempt to perform arithmetic on field '_padding_left' (a nil
  value)`, silently killing KOReader (no error UI). `FrameContainer:paintTo` calls `getSize()` then
  reads those fields. This hit the original `mahjongboard.lua` `Board:getSize()` (pattern copied from
  the chess boards, which have the same latent bug). If you override `getSize()`, mirror
  `FrameContainer:getSize()`'s padding assignments first. The chess boards
  (`casualkochess.koplugin/*board.lua`) are NOT safe to copy verbatim here. (The current 3D board
  avoids the trap entirely: it extends `InputContainer`, not `FrameContainer`, and `getSize()` just
  returns `self.dimen`.)

## Mahjong plugin — implementation state (US-01..US-06 done)

This repo builds `mahjong.koplugin` (Mahjong Solitaire). Read `IMPLEMENTATION_PLAN.md` for
the locked design and story list. Current state:

- **Repo layout:** `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `mahjong.koplugin/` (the deliverable),
  `tests/` (official suite: `run.sh`, `mock.lua`, `us01_shell.lua`, `us03_icons.lua`,
  `us06_board.lua`, `us06_paint.lua`), `install_plugin.sh` (device sync script),
  `example_app/casualkochess.koplugin/` (reference).
- **US-01 (done):** `_meta.lua` + `main.lua` skeleton; menu entry under `sorting_hint="tools"`
  ("Mahjong Solitaire"); `Dispatcher` action `mahjong` → event `MahjongStart` with `general=true`.
  The original separate placeholder widget was replaced by US-02's real shell — do not resurrect it.
- **US-02 (done):** `main.lua` now extends `FrameContainer` (not `WidgetContainer`) with
  `full_width`/`full_height`, `covers_fullscreen = true`, `is_doc_only = false`. Key methods:
  - `startGame()`: closes self if already shown, calls `buildUILayout()`, then `UIManager:show(self)`.
  - `buildUILayout()`: builds into `self[1]` a `VerticalGroup` = [board widget,
    New Game toolbar (`CenterContainer` with a `plus` icon `ButtonWidget`), `self.status_bar`].
    `board_h = full_height - status_h - toolbar_btn_h` (mirrors the chess example's math).
  - `createStatusBar()`: `TitleBarWidget` with `fullscreen = true`, title "Mahjong Solitaire",
    `close_callback` → `ConfirmBox` ("Exit Mahjong Solitaire?") → `saveGameState()` stub +
    `UIManager:close(self, "full")`.
  - New Game button → `ConfirmBox` ("Start a new game?") → `resetGame()` = rebuild layout +
    `UIManager:setDirty(self, "ui")`.
  - `handleEvent()`: dispatcher guard (`onMahjongStart`) then the `_window_stack` check, then
    forward to `FrameContainer.handleEvent`.
  - `onCloseWidget()`: cleanup stub (clears `self.board`). `saveGameState()` is an intentional
    empty stub (persistence is US-10); it carries `-- luacheck: no unused args` above it.
  - `createToolbarButton` is a module-local function (not a method) — it never used `self`.
- **US-03 (done):** 42 tile kinds + 144-tile deck + flower/season match rule in `mahjonglogic.lua`
  (`createDeck`, `matches`); 45 SVGs in `icons/` (42 faces + `empty`/`select`/`hint`). The SVGs
  are **generated by `tools/gen_icons.py`** — never hand-edit an SVG; edit the generator and
  re-run it (`--check` verifies the committed icons match). Tile faces fill the whole viewBox so
  adjacent tiles touch edge-to-edge (no white margin between tiles/rows), with a thin gray stroke
  per tile; symbols are large with little inner padding.
- **US-04 (done):** Turtle `buildLayout()` (144 positions), seeded `newRng`/`shuffle`, `newGame(rng)`.
- **US-05 (done):** free-tile rules: `tileAt`, `isFree`, `freeTiles`, `hasMoves`.
- **US-06 (done, reworked):** real board rendering as an **offset-layer 3D turtle**. The first
  US-06 attempt was a flat `ButtonTable` projection (see git history) — the user rejected it
  because it renders as a flat rectangle. `mahjongboard.lua` now extends `InputContainer` (NOT
  `FrameContainer` — see the getSize crash pitfall above) and paints one `IconWidget` per
  visible tile inside an `OverlapGroup`, each positioned with `overlap_offset = tilePos(x,y,layer)`.
  - Geometry (`computeGeometry`): portrait tiles `th = 1.4*tw` sized to fit both axes,
    `tw = floor(min(usable_w/units_w, (usable_h/units_h)/1.4))`; centered via `origin_x/origin_y`;
    per-layer offsets `offx = floor(tw/2)`, `offy = floor(th/2)`. `units_w/units_h` come from the
    layout's screen-space bounding box (0.5 tile per layer step).
  - Children are appended in `buildLayout()` order (bottom layer first) so lower tiles paint
    under upper ones; the `OverlapGroup` gets a board-sized `dimen` so the whole area is painted.
  - `updateBoard()` calls `free()` on the old paint container, rebuilds, and `setDirty`.
  - Taps: `TapSelect` gesture ranged over `self.dimen`; `hitTest` walks layers MAX→0 and returns
    the topmost tile whose rect contains the point; `onTileTap(x, y, layer)` is invoked with the
    tapped tile's grid position. The handler signature is `onTapSelect(_, ges)` (the gesture is
    the second arg — see the Input-handling pitfall above).
  - `getSize()` returns `self.dimen` (no `FrameContainer` `_padding_*` contract involved).
  - `main.lua` wires `onTileTap = function(x, y, layer) self:handleTileTap(x, y, layer) end`;
    `handleTileTap(x, y, layer)` is an intentional empty stub (`-- luacheck: no unused args`)
    until US-07.
  - `buttontable.lua`/`button.lua` shims were **deleted** from the plugin (ButtonTable unused).
    Note the shims still exist in `example_app/casualkochess.koplugin` and are documented above
    for chess-style grids.

### Verification workflow used so far

- Tooling now installed on this machine: `lua` (5.1) and `luacheck` (via luarocks).
  The official suite is `tests/`; run everything with `tests/run.sh` (syntax check
  `luac -p`, `luacheck mahjong.koplugin/`, the embedded `mahjonglogic.lua` self-tests, and the
  headless harnesses). **All future stories must extend this suite** (add a new `tests/usNN_*.lua`
  and register it in `tests/run.sh`), not create throwaway scripts.
- Icon QA lives in `tools/` (not the test suite, which must stay dependency-free):
  `tools/gen_icons.py` regenerates the tile SVGs, `tools/check_icons.py` asserts the icons
  parse, match the generator, touch edge-to-edge with no gaps, and aren't clipped,
  `tools/preview.py` renders a board+strip PNG for eyeballing. `check_icons`/`preview` need
  `lua` + `rsvg-convert`; run all three after any icon change.
- The headless harnesses reuse `tests/mock.lua`, which stubs every KOReader module with
  `package.preload` (device, ui/uimanager, widgets, gettext, lfs, util, etc.) and provides a
  fresh `mock.newContext()` per test. They drive `main.lua`/`mahjongboard.lua` end-to-end:
  instantiate the class, fire the menu callback, tap toolbar buttons, run `ConfirmBox`
  ok_callbacks, and assert the mock window stack/`self[1]` change correctly.
- Mock gotcha: the stubbed `WidgetContainer:extend` must be `function(self, o)` (colon receiver)
  or `:extend{...}` silently drops the class table → "loop in gettable" at runtime.
- KOReader UI code can't be exercised headlessly; the harness proves load-order, return values,
  and control flow. Visual checks still need the real device/emulator.

### Installing/updating on the connected Kindle

The dev PC is WSL; a Kindle shows up in Windows as drive **D:** and is mounted here under
`/mnt/d` (`sudo mount -t drvfs 'D:' /mnt/d`). KOReader lives at `/mnt/d/koreader/`, plugins at
`/mnt/d/koreader/plugins/`. Automate with:

```
./install_plugin.sh            # mount if needed, rsync --delete, diff-verify
./install_plugin.sh --unmount  # same, then unmount D:
```

The script pre-flights that Windows actually sees `D:\` (via `powershell.exe Test-Path`), so a
disconnected/charging-only Kindle fails with a clear message. Gotchas handled by the script:
- `/mnt/d` can linger as an empty leftover dir after unmount; the script checks `/proc/mounts`
  (not `ls`) to decide whether to mount.
- The Kindle's filesystem is FAT32 with no Unix perms/groups, so the script uses `rsync -r
  --delete` — NOT `rsync -a`, which fails with "Operation not permitted".
After install, the user must fully restart KOReader (plugins load at startup), then open
**Tools → Mahjong Solitaire**. If Windows stops seeing the drive after use, `sudo umount /mnt/d`.

## Reference

- Example studied: `example_app/casualkochess.koplugin` (chess/checkers/reversi/fox-and-hounds).
- Official "hello" plugin: `plugins/hello.koplugin` in the KOReader repo.
- KOReader source (widgets/containers/docs): https://github.com/koreader/koreader
- Plugin dev discussions: https://github.com/koreader/koreader/issues/9201
