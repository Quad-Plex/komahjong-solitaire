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
| `ui/uimanager` | `UIManager:show(w)`, `UIManager:close(w)`, `UIManager:setDirty(w, "ui"/"full")`, `UIManager:scheduleIn(s, fn)`, `UIManager:nextTick(fn)`, `UIManager:tickAfterNext(fn)` |
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

### E-ink reactive refresh rules

KOReader separates repainting a widget from refreshing the framebuffer. `setDirty` queues
both; the actual `paintTo` and e-ink update happen later in `UIManager:_repaint`. Treat every
input callback as a transaction that may be coalesced with the next callback.

- Dirty the window-level owner (`self` in a top-level game), never only the nested board,
  HUD, or icon widget. A nested target can enqueue a refresh region without causing its
  parent to paint.
- Prefer `"ui"` with an explicit `Geom` in **screen coordinates**. A regionless `"ui"`
  request refreshes the whole screen and is the usual source of accidental large updates.
  Use `"full"` only when a full-screen high-fidelity waveform is genuinely required.
- Keep stable regions for widgets whose `dimen` is not populated until their first paint.
  Derive them from the known layout geometry instead of passing a nil child `dimen`.
- For a mutation affecting several tiles, build one region per connected local cluster,
  with a small raster edge margin, but do not take the bounding box of distant changes.
  Two tiles at opposite ends of a board must not produce a board-sized refresh. KOReader
  merges touching regions, but explicit grouping is more reliable for e-ink drivers. Clamp
  the margin to the board canvas: a region that reaches an edge-adjacent HUD/feedback band
  will be merged with that band by KOReader's open-range refresh queue and ceases to be local.
 - Do not enqueue speculative neighbour regions. A pair clear includes the removed face and old
   bevel-segment rects, while a west/north same-layer neighbour belongs in the refresh only when
   its visible bevel segment set actually changed. KOReader merges edge-touching rectangles
   (`openIntersectWith`), so refresh the exact segment ink bounds and never dirty an unaffected
   neighboring face.
- Batch overlay transitions. Clear old highlight widgets and install new ones with refresh
  deferred, then enqueue one combined region covering both the old and new locations. This
  prevents a stale highlight clear and a new highlight paint from racing in separate
  regional updates.
- Structural tile changes can need one coalesced retry after the first repaint. If rapid
  pair removals can arrive before the previous e-ink update settles, accumulate their local
  regions and re-request them once via `UIManager:tickAfterNext`. Guard the retry so a closed
  or replaced board cannot dirty a new window.
- Board gestures do not receive the `Button` widget's built-in EPDC handoff. After a structural
  pair clear, first drain its local repaint with `UIManager:forceRePaint()`, then call
  `UIManager:yieldToEPDC()` before more gameplay can write overlapping framebuffer pixels. This
  is a short controller-read handoff, not `waitForVSync()`; never use a full waveform wait in the
  normal pair-clear path. Keep the deferred retry too: it heals a locally half-applied drive, while
  the handoff reduces the framebuffer-read race that can cause it.
- A pending terminal transition (win or no-moves card) is a transient input lock. Do not let a
  settings/stats/pause card invalidate it and strand the user on an empty or dead board. A picker
  or new-game transition may deliberately supersede it, but must invalidate the transition token.
- Never rebuild a large widget tree while a modal is still on the window stack. KOReader's
  `ConfirmBox` runs `ok_callback` before closing itself; defer a board rebuild with
  `UIManager:tickAfterNext` so the dialog-clear repaint gets an intervening UI tick first.
  Likewise, defer shuffle/dead-board dialogs after a pair clear until the cleared board has
  painted. A plain `nextTick` may still run before that repaint drains.
- A terminal modal after a structural tile mutation needs the same care. In particular, do
  not show a `covers_fullscreen` win summary in the batch that clears the final pair: it can
  prevent the board's deferred structural retry from being painted. Queue the card after the
  retry's repaint opportunity, guard it with the board identity, and invalidate the pending
  transition on a new game or close.
- Do not assume two refresh requests in one callback will paint two intermediate states.
  The final framebuffer is what gets painted, so update model state and widget structure
  consistently before the queued repaint. Use tokens or identity checks on delayed callbacks
  so stale work cannot repaint over a new game.

Recommended shape for a local update:

```lua
-- region is a screen-space Geom covering the changed connected area
UIManager:setDirty(self.show_parent or "all", "ui", region)
```

Recommended shape for a modal-dependent update:

```lua
UIManager:tickAfterNext(function()
    if self.board ~= board_snapshot then return end
    rebuildBoard()
end)
```

The practical goal is not zero refreshes. It is one correct `"ui"` refresh for each changed
local area, with a delayed retry only for structural changes that can overlap rapid input.
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
- **Children go in ARRAY position (`self[1]`, not a named field):** KOReader containers
  (`FrameContainer`, `WidgetContainer`) store their child at array index 1 — 
  `FrameContainer:new{ child, bordersize = 1, ... }`. Passing the child as a **named**
  field instead — `FrameContainer:new{ layout = child, ... }` — leaves `self[1]` nil, so
  `FrameContainer:getSize()` (and `WidgetContainer:getSize()`, paintTo) die with
  `framecontainer.lua:55: attempt to index a nil value` the moment the widget measures or
  paints itself, silently killing KOReader at launch. Mix named options with a positional
  child freely (`{ child, border=... }` puts `child` at `[1]` and the rest as fields).
  `HorizontalGroup`/`VerticalGroup` do the same: they iterate `ipairs(self)`, so pass each
  child as an array element, not `layout = ...`. (Root cause of a HUD-bar launch crash.)
- **`setDirty` on subwidgets:** KOReader's `_repaint` only repaints window-level widgets
  flagged in `_dirty`. Calling `setDirty(subwidget, "ui")` enqueues a refresh region but
  NEVER flags a window widget for repaint, leaving the screen stale. Subwidgets must either
  call `setDirty("all", "ui")` (matches the chess reference) or hold a reference to the
  window-level widget and dirty that. (This was the root cause of US-07's "zero effect" taps).
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
- **`OverlapGroup` children MUST be real widgets — no wrapper tables.** `OverlapGroup:init()`
  calls `self:getSize()`, which iterates its children and calls `getSize()` on each one
  (`overlapgroup.lua:27`). A plain table like `{ overlap_offset = { x = .. }, icon_widget }` is NOT
  a widget, has no `getSize()`, and crashes on launch with
  `overlapgroup.lua:27: attempt to call method 'getSize' (a nil value)`. The `overlap_offset` field
  must live **directly on the child widget** (set it inside the child's `:new{}`) and must be an
  **ARRAY** `{ px, py }` (accessed as `[1]`/`[2]`), NOT a `{x=.., y=..}` map. This bit the
  US-09 feedback band twice; the board's tile widgets (`mahjongboard.lua`) show the correct form.
- **`OverlapGroup` positions/centers via fields on each child:** `overlap_offset[1]/[2]` offsets a
  child from the group's top-left; `overlap_align = "center"` (or `"right"`) centers a child
  horizontally across the group's `size.w` (useful to center text across a full-width band
  independently of a side icon). Only the first matching rule wins: `overlap_align` is checked
  BEFORE `overlap_offset`, so you can't combine "center horizontally" with a vertical offset on one
  widget — use `overlap_align = "center"` for the text and a separate `overlap_offset` child for the
  icon (see `main.lua`'s flash band).
- **`visible = false` is ignored by KOReader widgets — use `hide = true`.** `ImageWidget:paintTo`
  skips painting when `self.hide` is truthy; a `visible` field does nothing and the widget still
  paints. The US-09 flash band toggles `self.flash_band_icon.hide` to show/hide the warning icon.
- **Mock fidelity pays off:** the headless suite's `OverlapGroup` stub was a lazy no-op that never
  called `getSize()` on children, so the wrapper-table bug above passed tests and only crashed on
  device. `tests/mock.lua` now mirrors the real `OverlapGroup:getSize()` (iterates children,
  calls `getSize()`, applies `dimen` override). When you stub a container for tests, mimic its real
   `getSize`/`init` behavior or the suite can't catch layout crashes.
- **Current picker contract (US-48).** The layout picker uses fixed three-column
  by four-row pages. Do not reintroduce `ScrollableContainer` or scroll-era
  cropping behavior; page changes and card selection are tested through the
  picker widget's active-page hit regions.

## Mahjong plugin — current state and key contracts (US-01..US-50 shipped)

This repo builds `mahjong.koplugin` (Mahjong Solitaire). `IMPLEMENTATION_PLAN.md` is the source
of truth for the locked design; the per-story detail lives in `implementation-plan/` (one file
per user story; `_completed` in the filename marks shipped stories — US-01..US-50
shipped). The full history of *why* things are the way they are
(rejected designs, shipped bugs) lives in `IMPLEMENTATION_PLAN.md`, the story files, and the
code comments — this section is only the load-bearing facts an agent needs before touching the
code.

### Repo layout

```
mahjong.koplugin/            # the deliverable
├── _meta.lua                # plugin metadata (name/fullname/description)
├── main.lua                 # plugin class: menu/dispatcher, buildUILayout, gameplay,
│                            #   timer, settings/stats entry, save/restore, flash band,
│                            #   layout picker entry (US-14)
├── mahjonglogic.lua         # PURE logic (no ui/ requires): deck, free tiles, match/win/
│                            #   shuffle, scoring, persistence (v2 with layout field),
│                            #   re-exports mahjonglayouts.lua's registry API, self-tests
├── mahjonglayouts.lua       # PURE layout module (US-22a): the spec tables (Turtle/Spider/
│                            #   Bridge/Ziggurat/Cloud/Tic-Tac-Toe/Red Dragon/Overpass) +
│                            #   registerLayout calls, the registry and
│                            #   per-id caches, buildLayout/posKey/maxLayer/gridBounds/
│                            #   isLayoutPosition/deregisterLayout, shape+registry self-tests.
│                            #   US-27..US-29 add a board HERE (spec + self-test) only
├── mahjongstats.lua         # PURE lifetime stats (US-12): defaults/load/startGame/recordWin,
│                            #   total_time, self-tests (no ui/ requires)
├── mahjongboard.lua         # 3D board widget (InputContainer): IconWidgets in an
│                            #   OverlapGroup, per-layer up-left shift, hit-test, overlays;
│                            #   per-layout geometry via layout_id (US-14)
├── hudbar.lua               # 2-row top bar: left buttons (gear + stats, left_icons API) +
│                            #   title + 3 stat chips + quit X (Pause lives in the bottom toolbar)
├── mahjongsettings.lua      # floating settings dialog (CenterContainer card over the game)
├── mahjongstatswidget.lua   # floating stats screen (US-13): the same card pattern, lists
│                            #   lifetime stats + Reset-after-confirm
├── mahjongpause.lua         # pause overlay (US-17): floating card with a Resume button; the
│                            #   full-screen tap gesture consumes taps (no tap-outside dismiss)
├── mahjonglayoutselect.lua  # full-screen layout picker (US-14): fixed 3x4 paged grid, each a
│                            #   thumbnail (miniature schematic of the layout's positions) +
│                            #   name; tapping a card deals a game on that layout
└── icons/*.svg              # generated tile faces + UI glyphs (gen_icons.py owns them all)
tests/                       # official feature-driven suite (manifest.lua + support + suites)
tools/                       # gen_icons.py, check_icons.py, preview.py (icon QA, not in suite)
install_plugin.sh            # rsync to the Kindle over /mnt/d
example_app/casualkochess.koplugin/   # the chess/checkers reference plugin
```

### Architecture map (what talks to what)

- `main.lua` owns the game: `self.board` (logic state), `self.history` (undo stack),
  `self.score`, `self.selected`, `self.board_view` (the rendered board), `self.status_bar`
  (HudBar), and `self.layout` (the current layout id, US-14). `handleTileTap(x, y, layer)` is
  the gameplay entry; it mutates the **logic board first**, then tells the **board widget** to
  update its paint.
- `MahjongLogic` (in `mahjonglogic.lua`) is pure: deck/free-tiles/match/win/shuffle,
  scoring (`pairPoints`, `matchGroup`), and `serializeGameState`/
  `deserializeGameState`. The layout registry and geometry live in
  `mahjonglayouts.lua` (US-22a); `mahjonglogic.lua` requires it and re-exports
  the API, so all callers see one surface. UI code must never reach into the
  logic modules except through their functions; keep new logic here so it stays
  testable with plain `lua` (self-tests via `--selftest`).
- The board (`mahjongboard.lua`) paints one `IconWidget` per tile, absolutely positioned via an
  `OverlapGroup`'s `overlap_offset`. The stock `ButtonTable` is NOT used (flat projection was
  rejected — see plan). Tiles are keyed by `posKey(x,y,layer)` strings (`x,y,layer`). A board
  is built with `layout_id` (US-14) and all its geometry paths (`tilePos`/`computeGeometry`/
  `rebuildTiles`/`syncOverlapGroup`/`hitTest`) key off `maxLayer(self.layout_id)` and
  `layoutBounds(self.layout_id)`.
- Hit-testing lives in the board (`hitTest`, walks `tiles_by_layer` top-down), not in the logic.

### Key contracts (do not regress)

1. **Board = 3D outward-bevel turtle.** Tiles are portrait 100x140 faces (aspect 1.4), with
   independently rendered bevel segments on a shared **110x154 viewBox**; the outward bevels
   (right `#78909c`, bottom `#546e7a`) hang OFF
   the face's east/south edges. **Each layer is shifted up-left by exactly one bevel thickness**
   (`tilePos` subtracts `layer*bw`/`layer*bh`), so a raised tile's bevels land exactly on the
   edges of the tile directly beneath it — the bevel is the visible step and never overlaps the
   tiles to its east/south. Camera is bottom-right. (A `FrameContainer` subclass's `getSize()`
   MUST set `_padding_*` first, or every paint crashes — see Common pitfalls; that is why the
   board extends `InputContainer` and `getSize()` just returns `self.dimen`.)
2. **Bevel segments:** faces use kind-specific 100x140 SVGs; shared `bevel_right`,
   `bevel_bottom`, and half-edge assets are selected by pure
   `MahjongLogic.visibleBevelSegments`. A same-layer neighbour hides only its overlapping edge
   interval; direct or two half-overlapping neighbours hide the complete edge
   (`(x+1,y±0.5)` east, `(x±0.5,y+1)` south). SVGs are **generated by `tools/gen_icons.py`** —
   never hand-edit an SVG; re-run the generator and `tools/check_icons.py`.
3. **Layout registry (US-14, module US-22a).** `MahjongLogic.layouts` maps
   `id -> { id, name, spec }`; `registerLayout(entry)`, `layoutIds()`,
   `layoutName(id)` manage it. The specs, the registry, and the per-id caches
   live in `mahjonglayouts.lua` (pure Lua); `mahjonglogic.lua` requires that
   module and re-exports `layouts/posKey/registerLayout/deregisterLayout/
   layoutIds/layoutName/buildLayout/maxLayer/gridBounds/isLayoutPosition` so
   callers keep one surface, and a new board (US-23..29) is a
   **single-file change to `mahjonglayouts.lua`** (spec + `registerLayout` call
   + shape self-test) plus a harness. Turtle is registered at
   module load (the canonical GNOME Mahjongg map: per-layer 87/36/16/4/1, grid x=0..14, y=0..7,
   fractional x/y on the head/tail/cap half-grid); US-15/16 add Spider/Bridge via one
   `registerLayout` call each, US-22 adds Ziggurat (per-layer 64/20/18/18/14/10, grid
   x=0..14, y=0..7, half-grid on layers 0/1/2), US-23 adds Cloud (per-layer 79/36/29,
   grid x=0..13, y=0..5.5, half-grid y=5.5 spine rows), and US-24/25/26 add Tic-Tac-Toe
   (`tictactoe`, per-layer 40/36/28/20/20, grid x=0..12, y=0..8), Red Dragon (`red-dragon`,
   per-layer 82/45/17, grid x=0..14, y=0..6.5, fractional-y horn/base tiles) and Overpass
   (per-layer 52/20/16/32/24, grid x=0..11, y=0..8). US-27/28/29 add Pyramid's Walls
   (`pyramid`, per-layer 41/34/27/20/13/6/3, grid x=0..11, y=1..7, the deepest board at 7
   layers), Confounding Cross (`confounding`, per-layer 47/42/27/18/9/1, grid x=0..10, y=0..8)
   and Taipei (`taipei`, per-layer 63/46/19/10/3/2/1, grid x=0..10, y=0..6). US-35 adds Crab
    (`crab`, per-layer 77/50/15/2, grid x=1..14, y=0..7, the classic Microsoft Mahjong Titans
     crab transcribed from KMahjongg's `crab.layout`). US-49 adds the PySolFC animal layouts Hare
    (59/44/26/11/4), Horse (62/49/27/6), Tiger (62/58/18/6), Ram (69/52/20/3), Monkey
    (60/44/23/15/2), and Rooster (66/44/26/7/1), all on x=0..14, y=0..7. The sorted built-in
     registry is {bridge, cloud, confounding, crab, hare, horse, monkey, overpass, pyramid, ram,
     red-dragon, rooster, spider, taipei, tictactoe, tiger, turtle, ziggurat}. US-50 adds Dog
     (62/47/29/6), Snake (60/58/21/5), Boar (65/43/28/8), Ox (73/44/21/6), Wedges
     (60/39/26/13/5/1), and Hourglass (74/40/12/10/8), taking the sorted built-in registry to
     {boar, bridge, cloud, confounding, crab, dog, hare, horse, hourglass, monkey, overpass, ox,
     pyramid, ram, red-dragon, rooster, snake, spider, taipei, tictactoe, tiger, turtle, wedges,
     ziggurat}. Every
    layout-dependent function takes a layout id (defaulting to
   `"turtle"` so legacy callers and the self-tests stay byte-identical): `buildLayout(id)`,
   `gridBounds(id)`, `maxLayer(id)`, `isLayoutPosition(x,y,layer,id)`, `newGame(id, rng)`,
   `freeTiles(board, id)`, `hasMoves`/`matchingFreePair*`/`countFreePairs` (all take a trailing
   `id`). Each cache (`_layout_cache`/`_bounds_cache`/`_layout_key_cache`/`_max_layer_cache`)
   is per-id; `registerLayout` and `deregisterLayout` invalidate the caches for the affected
   id. The old
   `MAX_LAYER` constant stays for legacy callers (== `maxLayer("turtle")`). The `newGame(rng)`
   old call shape is preserved (a non-string first arg is the rng, defaulting id to "turtle").
4. **Free-tile rule:** a tile is free iff nothing overlaps it from layer+1 (within ±0.5 in both
   axes) AND at least one horizontal side is open (`x-1` or `x+1` on the same layer, also
   half-grid aware).
5. **Incremental board updates:** pair removal must NOT rebuild all 144 face widgets. Use
    `board_view:removePair(a, b)` / `removeTile` / `addTile` / `addPair`, which keep
     `tiles_by_layer`, `tile_widgets`, and `bevel_widgets` (position/segment → IconWidget) in sync
     and end in `syncOverlapGroup()` (rebuilds the ordered face/bevel child array + overlays).
     `removePair` drops both faces and their bevels before refreshing neighbours. Its regional
     refresh contains removed face/bevel ink and only newly changed west/north bevel segments;
     it never replaces an unaffected neighboring face or adds speculative full-tile regions.
6. **Overlays** (`select`/`hint`) are extra IconWidgets appended AFTER all tiles in the same
   OverlapGroup, never added to `tiles_by_layer`, so they paint on top and taps pass through.
 7. **Persistence:** one `LuaSettings` file at `DataStorage:getSettingsDir()/mahjong.lua`. Game
    state = `"game"` key (versioned table: **`v=2`** with a `layout` field (US-14) and an optional
    `autosolved` taint flag (US-33, absent/non-boolean → false so older saves restore clean); flat
    posKey→kind board + flattened 10-field undo history
    `{ax,ay,al,bx,by,bl,ka,kb,score,prev_last}`), validated hard on load (count sum must be 144,
    kinds valid, positions in the saved layout, history disjoint, layout id registered). A **v1**
    save (no `layout` field) restores as Turtle. An unknown saved `layout` id is corrupt →
    fresh. Settings = their own keys (`hints`, `deselect_on_empty`,
    `layout`, `timer_update`, `timer_interval`). `deselect_on_empty` defaults to
    true; when false, an empty-board tap leaves the selected tile highlighted
    until it is matched or replaced by another viable tile. A **won (empty) board is NOT saved** —
    the key is cleared. Corrupt state silently starts fresh.
8. **Timer:** elapsed seconds always accrue (`getElapsed()` diffs `os.time()`); the mode only
   controls when the mm:ss **repaints** — `timer_update="interval"` (default, poll every
   `timer_interval`s, default 5) vs `"move"` (repaint on interaction only). `startTimer` bumps a
   run-id token; `stopTimer` freezes `elapsed_base`. No timer score bonus.
9. **Scoring:** base 10 per pair (`SCORE_PER_PAIR`), +50 chain bonus (`CHAIN_BONUS`) when the new
   pair is in the same `matchGroup` as the previous match; flowers chain with flowers, seasons
   with seasons. Chain/combo scoring is always enabled for human play. **A hint breaks the fast-clear
   combo:** `showHint` resets `last_match_elapsed` and `combo_chain` when a hint is shown, so
   the pair cleared after a hint earns NO combo and any running combo chain restarts at 0 — this
   blocks "hint then immediately tap the shown pair" from farming escalating COMBO points. The
   same-group `CHAIN_BONUS` is intentionally unaffected (that reward is about consecutive
   groups, which a hint helps track rather than skip). **US-18 penalties:** a hint shown
   costs `HINT_PENALTY` (5) and a user-initiated shuffle costs `SHUFFLE_PENALTY` (10), applied at
   use time via `MahjongLogic.applyPenalty(score, amount)` (may reduce the score below 0); the bounded auto-repeat
   re-shuffles and the auto-solver's mid-solve shuffles never re-charge. **US-20:** the hint
   penalty is charged once per *hint session* — a session runs from the first hint after a pair
   was cleared until the next pair is cleared (`applyMatch` resets `_last_hint`), so cycling
   presses and re-hints on the same board are free; only the press that starts a session pays.
   Penalties are NOT in the pair history, so `undo()` subtracts only the pair's points
   and never refunds a penalty. Per-game `hints_used` / `shuffles_used` counters are persisted in
   the game state (`serializeGameState`/`deserializeGameState` fields `hints`/`shuffles`,
   absent = 0) and shown in the win summary when non-zero. A no-moves shuffle
   evaluates 15 copied-board candidates asynchronously, selects the one with
   the most matching free pairs, then charges the user penalty once; bounded
   retries repeat the search without re-charging.
10. **Dirtying:** a nested subwidget's `setDirty` alone never repaints (US-07's "zero effect"
    bug) — the window-level widget must be dirtied (`UIManager:setDirty(self, "ui")`), or use
    the `"all"` sentinel from inside the board.
 11. **Floating dialogs (`mahjongsettings.lua`, and `mahjongstatswidget.lua` for US-13's stats
     screen)** follow the canonical floating-card pattern: transparent full-screen `InputContainer` →
     `CenterContainer` → white rounded `FrameContainer`; `TapClose` dismisses on a tap outside
     `_panel_geom`; `onShow` re-dirties a refresh function over `_panel_geom` (else the panel may
     stay invisible); row buttons `setDirty(self, "ui")`; toggle labels are rebuilt via
     `setButtonText` (Button:setText can truncate changed values); value buttons
     are sized to the widest value; timer-interval button greys out in "On interaction" mode. The
     stats screen is the read-only counterpart: right-aligned labels + a uniform value column, a
     Reset button gated behind a `ConfirmBox`, and an `onClose` hook (main.lua's `openStats`
     pauses the timer while the card is up, exactly like `openSettings`). The record it lists is
     `MahjongStats` (`total_time` feeds the average-time-per-win row).
 12. **Long-press auto-solve (US-19):** KOReader `Button` fires `hold_callback` ~0.5 s after
     contact (the device-global `ges_hold_interval_ms`), NOT per-widget, so a ~10 s hold is
     implemented as arm/cancel: the Hint button is a `LongPressButton` (a `ButtonWidget` subclass
     that surfaces the normally-hidden `hold_release` via `onHoldReleaseSelectButton` →
     `hold_release_callback`), `armAutoSolve` schedules a `UIManager:scheduleIn(10, ...)` and
     `disarmAutoSolve` cancels it on early release. The solver drives the shared
     `applyMatch(a, b)` helper (extracted from `handleTileTap`) once per `AUTO_SOLVE_STEP_SECONDS`
     (0.3 s, US-33);
     `matchingFreePair` + `applyMatch` are reused for scoring/history/save so an auto-solved game
     is indistinguishable from a played one. **US-33: once running, the solver is UNINTERRUPTIBLE
     and there is no way to keep a partial score.** Every user input is a silent no-op while
     `_auto_solve_active` (board taps, Hint, Undo, Shuffle, New Game, Pause, gear/stats, quit X,
     and a second hold); the game is flagged `autosolved` in the saved state (`game_was_autosolved`
     → `serializeGameState`'s `autosolved` field), so a crash/close mid-solve saves a tainted
     board; and a reload of a tainted save RESUMES the solver on `UIManager:nextTick` (the
     `startGame` restore branch skips the `handleNoMoves` check for it — the solver shuffles dead
     boards itself). It only ever ends via the win dialog (no win recorded, `game_won` stays false)
     or a provably-dead board (`stopAutoSolve` + dead-board dialog). Flash has a persistent
     `setFlash` vs the
     auto-clearing `flashMessage`, and `clearFlash` bumps the token (never nils it — the old
     `nil + 1` crashed on a second flash after a cleared band).
 13. **Pause (US-17):** the bottom toolbar's fifth button (`mahjong/pause` icon, kept as
     `self.pause_button`) calls `pauseGame()` — `stopTimer()` (freezes
     `elapsed_base`) then drops `mahjongpause.lua`, a floating card in the settings/stats pattern
     but with NO tap-outside dismiss: its full-screen `TapClose` handler returns true and does
     nothing, so every stray tap is consumed and the board/toolbar/HUD are unreachable. Only the
     Resume button (or the framework closing the overlay) runs `onResume` → `startTimer()`;
     `PauseWidget:resume()` is `_resumed`-guarded and `onCloseWidget()` falls back to it, so the
     clock restarts exactly once no matter the close path. **US-33: Pause is a no-op while the
     auto-solver runs** (the solve must run to completion), so it never has to stop a solver
     behind the overlay. `Mahjong:onCloseWidget()` closes a
     still-open overlay before the final idempotent `stopTimer()`/`saveGameState()` (closing
     while paused saves).
 14. **Layout picker (US-14):** `startGame()` restores a saved game directly (no picker);
    otherwise (first launch, New Game, win "Play again") it shows the full-screen
    `mahjonglayoutselect.lua` picker — choosing a layout IS the New Game confirmation, so the
    old New Game `ConfirmBox` and the `confirm_new_game` setting are retired. The picker is an opaque
    `InputContainer` (full-screen, not a floating card) with a fixed 3x4 paged grid of cards (one per registered layout, sorted id order); each card is a
    `FrameContainer` holding a `layoutThumbnail(id, w, h)` schematic (an `OverlapGroup` of small
    rounded `FrameContainer` tiles, one per layout position, per-layer up-left offset so the 3D
    shape reads) plus the layout name. A single full-screen `TapSelect` gesture hit-tests the
    card rects (the board's pattern, not per-card gestures): a hit fires `onPick(id)` →
    `startGameWithLayout(id)` (deals, persists `layout` as the last-chosen default, shows the
    game); a miss (empty space) is **ignored** — only the close X fires `onClose` (resumes the
    timer if a game was running, does nothing on first launch). (Closing the picker on an
    empty-space tap used to dump the user back to the file manager on first launch — reported
    as an app crash.) `showLayoutPicker()` stops the auto-solver + timer first (so the
    polling loop doesn't flash behind the opaque picker); `onClose`/`onPick` resume. The board
    widget is rebuilt with `layout_id` so its geometry follows the chosen layout. **Closing the
    picker MUST request a full refresh:** `closeDialog` (and `startGameWithLayout`'s drop of the
    picker) call `UIManager:close(w, "full")` — a bare `UIManager:close` flags the uncovered
    widgets for repaint but enqueues no refresh, and `_repaint`'s fallback region-less
    `"partial"` doesn't take on e-ink, so with no active game underneath (first launch, or a
    won board) the picker's last frame stays on screen. The picker's `onClose` also exits the
    game when the board underneath is WON (the Play-again flow): an empty board must never be
    returned to, so `onClose` does `UIManager:close(self, "full")` there (merges with the
    picker's own close refresh instead of double-flashing); mid-game `onClose` resumes the
    timer, first-launch `onClose` does nothing. The picker's title row carries
    **three left buttons** — settings (`appbar.settings`), stats (`mahjong/stats`)
    and help (`?`) — keeping the title centered over the full row width (the
    asymmetric flex spans place it at exactly the row center for any button
    count). When an active (un-won) game sits below the picker, `showLayoutPicker`
    hands it `game_in_background = true` and the close button renders as
    `chevron.left` (a return arrow — closing it resumes that game via `onClose`);
    with no game behind it stays the `mahjong/close` X. The picker's stats button
    calls `openStats`, which passes `show_map = self.board ~= nil and
    not MahjongLogic.isWin(self.board)` so `mahjongstatswidget` hides its Map
    (per-layout) column when no game is running; `openStats`'s `onClose` uses the
    `picker_was_open` guard (like `openSettings`) and NEVER resumes the timer
    while the opaque picker is still up.
 15. **US-30 picker polish:** (a) card names are `COLOR_BLACK` (were gray);
    (b) the thumbnail is centered by the tower's **face center of mass** —
    `layoutThumbnail` averages every tile's face center (the per-layer up-left
    shift means the bounding box center sits east/south of where the tower
    reads, so bbox-centering left the picture leaning up-left; e.g. Turtle was
    ~5px left in the real card). The tower scales to fit a box inset by
    `margin` (≈5% of the smaller thumb axis, so a width-filling layout never
    touches the thumbnail's edge — a flush tower reads as off-center), and if
    the fit-box rounding leaves too little room to center a lopsided tower's
    mass (Turtle's head/tail asymmetry), it shrinks one tile-width notch at a
    time until the mass fits. The card ALSO centers the thumbnail in the card:
    without a full-card-width wrapper, the content `VerticalGroup` is only as
    wide as its widest child (the thumbnail) and sits flush against the card's
    LEFT edge, so a width-filling tower looked left-flush even when internally
    centered — the card wraps its content in a `CenterContainer`
    (`dimen = card_w x card_h`). (c) every card shows a **trophy badge**
    (`mahjong/trophy` + win count, Material `emoji_events` glyph, white rounded
    `FrameContainer`) in the thumbnail's top-right corner via an `OverlapGroup`
    wrapping the thumb; the count is `self.wins_by_layout[id] or 0`, fed from
    `MahjongStats.layout_wins` (a `layout_id -> wins` map added to the stats
    record, `defaults()`/`load()`-sanitized, bumped by
    `MahjongStats.recordLayoutWin` inside the same human-win gate as `recordWin`
    in `showWinDialog` — auto-solve wins never count); (d) tapping a card calls
    `_pressCard` (darkens background + border) and defers the deal by
    `UIManager:scheduleIn(TAP_FEEDBACK_SECONDS=0.2, ...)` → `_finishPick`, so
    the press paints on e-ink before the synchronous board build replaces the
    picker; `_pending_pick` guards the deferred callback (cleared by
    `closeDialog`, so a closed/superseded picker never deals). Note the
    picker-deal flow is now asynchronous on the device — harnesses must flush it
    (see the picker test notes below).
 16. **US-30 bevel corner:** the bottom bevel's LEFT edge carries the same diagonal as its right
    (`FACE_BEVEL_BOTTOM_CORNER` = `M0 140 L100 140 L110 154 L10 154 Z`, `FACE_BEVEL_BOTTOM` =
    `M0 140 L100 140 L100 154 L10 154 Z` in `tools/gen_icons.py`). The board shifts each upper
    layer up-left by the bevel thickness, so a raised tile's bottom bevel is the visible WEST
    step of the tower; a square corner there broke the continuous diagonal the west face traces
    down a stack. Mirrored diagonals keep the stacking edge crisp on the deep multi-layer boards
     (US-27..29). `tools/check_icons.py` validates the current 62 generated SVG assets.
 17. **Fresh deals always have a move (US-30):** `MahjongLogic.newGame(id)` with a random
    (nil) rng re-deals until the board has at least one matching free pair. Without this a
    small fraction of deals (measured ~5% on Bridge) start dead, forcing the player to
    shuffle a board they never played — and the layout picker tests that play a pair after
    picking a layout crashed intermittently on those deals (`matchingFreePair` returns nil).
    Seeded deals (self-tests, deterministic checks) are byte-identical — only the nil-rng
    path re-deals.
 18. **Per-layout highscore chip (US-31):** each picker card shows the layout's best
    winning score as a plain-number chip in the thumbnail's **bottom-right corner**
    (opposite the trophy badge's top-right), only when a human win has recorded one.
    The value comes from `MahjongStats.layout_highscores` (a `layout_id -> best score`
    map added to the stats record, `defaults()`/`load()`-sanitized — old pre-US-31
    records default to `{}`). `MahjongStats.recordLayoutWin(stats, id, score)` takes an
    optional third `score` arg and keeps the highscore at its max (the two-argument
    form still just bumps `layout_wins`, so existing callers/saves stay valid). `main.lua`
    passes `self.score` at win time inside the same human-win gate as `recordWin`
    (auto-solve never sets a highscore) and hands the picker `highscores_by_layout`; the
    chip is the thumbnail OverlapGroup's **third child** (badge stays child 2, so the
    US-30 badge assertions hold) and is simply absent when there is no record. A **time
    chip** extends this: the layout's fastest winning time (`MahjongStats.layout_best_times`,
    a `layout_id -> seconds` map tracked by the same `recordLayoutWin(stats, id, score,
    elapsed)`, sanitized `defaults()`/`load()` like the highscore map) renders as an
    mm:ss chip in the thumbnail's **bottom-left corner** (opposite the score chip's
    bottom-right), only when a human win has set one; `main.lua` hands the
    picker `best_times_by_layout`. `recordLayoutWin` returns `(new_layout_score,
    new_layout_time)` so the win summary can distinguish a **layout** best from an
    **overall** best.
 19. **Win-summary headline variants (US-12+):** the confirm text's first line varies
    with what the win achieved — a new **overall** best score and/or time headlines
    "Congratulations! New (overall) best score/best time!", a record that only breaks
    THIS layout's best headlines "…New best score/time **on this layout**!", and a win
    that breaks nothing falls back to "You cleared the board!". The summary also lists
    both the overall (all-layouts) bests and the current layout's bests (`<Layout> best
    score/time`), each marked "(New best!)" only when that specific record fell.
    Auto-solve wins (US-19/33) set none of these flags, so they always show the plain
    fallback headline. **The dialog is a floating centered card
    (`mahjongwinsummary.lua`), not a ConfirmBox**: a stock ConfirmBox centers a
    wide headline text area, which leaves a narrow aligned label/value block
    hugging the window's left edge. The card sizes itself to its content and is
    centered (the pause/stats floating-card pattern), the headline is centered
    via a CenterContainer over the content width, and each row is a
    HorizontalGroup `{ leading right-align span, label, gap, value }` — labels
    right-aligned to the widest one so every value TextWidget starts at the same
    x, LEFT-aligned in its column. A full-screen tap is consumed (only the
    buttons dismiss), matching the tap-outside contract. The widget exposes
    `text` (headline), `win_rows` (`{label, value}` pairs), `ok_text`/
    `cancel_text`, and `ok_callback`/`cancel_callback` so the headless harness
    re-reads the summary with `ctx.summaryText` exactly as before; `_row_group`
    holds the aligned-rows VerticalGroup for the structural check.
 20. **Tap-outside a dialog never closes the game.** The shuffle / dead-board / win
    ConfirmBoxes use `cancel_callback` to exit the game (the "Close" button's documented
    action), but KOReader fires `cancel_callback` for a tap OUTSIDE the dialog too — so a
    stray tap next to the dialog used to close the whole app (reported as a crash). These
    three dialogs are wrapped in `dismissDialogOnTapOutside` (`main.lua`), which overrides
    the per-instance `onTapClose` to CONSUME the stray tap — the dialog stays open and only
    its own buttons dismiss it (the Close button keeps its exit behavior). Likewise the
    layout picker ignores taps on empty space (only the close X cancels — see contract 14).

### Test harness notes (and verification workflow)

- Tooling now installed on this machine: `lua` (5.1) and `luacheck` (via luarocks).
  The official suite is `tests/`; run everything with `tests/run.sh` (syntax check
  `luac -p`, `luacheck mahjong.koplugin/`, embedded pure-module self-tests, and
  the suites listed in `tests/manifest.lua`). New tests are feature-owned and
  extend the responsible suite; add a manifest entry rather than creating a
  story-numbered harness. Modify `run.sh` only for runner, discovery, or
  environment behavior. Do not create throwaway scripts.
- Icon QA lives in `tools/` (not the test suite, which must stay dependency-free):
  `tools/gen_icons.py` regenerates the tile SVGs, `tools/check_icons.py` asserts the icons
  parse, match the generator, touch edge-to-edge with no gaps, and aren't clipped,
  `tools/preview.py` renders a board+strip PNG for eyeballing. `check_icons`/`preview` need
  `lua` + `rsvg-convert`; run all three after any icon change.
- `tests/mock.lua` stubs every KOReader module via `package.preload` (device, ui/uimanager,
  widgets, gettext, lfs, util, etc.) with a fresh `mock.newContext()` per test. Harnesses drive
  `main.lua`/`mahjongboard.lua` end-to-end: instantiate the class, fire the menu callback, tap
  toolbar buttons, run `ConfirmBox` ok_callbacks, and assert the mock window stack/`self[1]`.
- A throwaway "toy" layout is registered for registry/picker tests and torn down with
  `Logic.deregisterLayout("toy")` (US-22a) — never mutate `Logic.layouts["toy"] = nil` directly,
  which leaves the module's caches stale.
- The mock captures `UIManager:scheduleIn`/`nextTick` into `ctx.scheduled` (US-30). Harnesses
  flush pending tasks with `ctx.runScheduled()` (snapshot semantics: tasks scheduled while one
  runs — like the timer polling loop's reschedule — stay queued, so nothing spins). Tests that
  override `um.scheduleIn` themselves (us11/12/17/18/19) keep their own capture and must run
   the deferred picker deal out of it.
- Rendering-transition harnesses must put the game widget on the mock window stack when they
  test device-only sequencing. Direct `board` + `buildUILayout()` construction intentionally
  takes the immediate path because it has no framebuffer/EPDC work to settle. The win-summary
    transition is covered by `tests/integration/render_safety.lua`; flush each deferred snapshot in
  order to verify both the structural retry and the later modal opening.
- **US-14/30 picker in harness:** `startGame()` with no saved game now shows the layout picker
  instead of dealing a board. Harnesses that drive `menu_items.mahjong.callback()` or the
  toolbar's New Game button must pick a layout to proceed — the shared idiom is a small
  `pickTurtle()` helper that finds the Turtle card's rect in the picker's `_card_rects` and
  fires `picker:onTapSelect(nil, { pos = { x = r.x + r.w/2, y = r.y + r.h/2 } })`, then
  `ctx.runScheduled()` (or runs the just-scheduled deal) because the deal is deferred by
  TAP_FEEDBACK_SECONDS. Tests that set `mj.board = ...; mj:buildUILayout()` directly bypass the
  picker. A restored game (save present) still resumes directly, no picker. Cancel taps (outside
  a card / close X) schedule no deal and need no flush.
- Mock gotchas (keep the stubs faithful, or the suite won't catch real layout bugs):
  - `WidgetContainer:extend` must be `function(self, o)` (colon receiver) or `:extend{...}`
    silently drops the class table → "loop in gettable" at runtime.
  - `frame_container.new` must mimic `Widget:new`: (a) `self:extend(o)` so the subclass
    metatable chain is preserved, (b) copy a positional child to `o[1]` (and map `o.layout` to
    `o[1]`), (c) call `o:init()` if present. Skipping any makes the harness crash with a nil
    `self[1]` or silently skip `init()`.
  - The mock mirrors real `OverlapGroup:getSize()` (iterates children) — a lazy no-op stub let a
    wrapper-table layout bug slip through to the device once. Instances also expose `getSize()`
    (the real overlapgroup is queryable), which the nested thumbnail-overlapgroup (US-30) needs.
- KOReader UI code can't be exercised headlessly; the harness proves load-order, return values,
  and control flow. Visual checks still need the real device/emulator.

### Installing/updating on the connected Kindle

The Kindle now runs a SSH server, so the preferred (and only) transport in daily use is **SSH**
`root@192.168.2.213` with an **empty root password**. This is faster than USB/KMS and works
over wi-fi. `install_plugin.sh` tries SSH first and only falls back to USB mass-storage
(mounting D: under WSL) when SSH is unreachable.

```
./install_plugin.sh            # SSH → rsync over ssh → verify; falls back to /mnt/d
./install_plugin.sh --unmount  # USB path only: then unmount D:
```

After the SSH path the running KOReader instance is **stopped automatically** (SIGTERM to
`reader.lua`/`koreader.sh` so state saves cleanly, with a SIGKILL fallback) **and relaunched
automatically** afterwards (`(./koreader.sh >/var/tmp/koreader.log 2>&1 &)` from
`/mnt/us/koreader`, in a detached subshell — BusyBox has no `nohup` — so it survives the SSH
session ending), so the freshly-installed plugin is already loaded when the install finishes.
The USB path leaves KOReader running; restart it manually.

**SSH transport facts (verified):**
- Login is `root` with an **empty password**, which requires `sshpass` (`sudo apt-get install
  sshpass`). The script uses `sshpass -e` (password from the `SSHPASS` env var) with
  `export SSHPASS=""` — this avoids the empty password being word-split as an argument.
- The Kindle is ROOTED and its shell is BusyBox v1.17.1: no `grep -E` (`grep` with basic
  `\|` instead), no `readlink -m`, no `find -printf`. Scripts must test paths with `test -d`
  rather than rely on those tools. KOReader lives at `/mnt/us/koreader/` (plugins at
  `/mnt/us/koreader/plugins/`) as seen over SSH.
- `rsync -e "sshpass -e ssh <opts>"` is used for the transfer. Verification avoids any extra
  device tooling: a `rsync -rcn --delete` checksum dry-run prints nothing only when the trees
  are identical.

**USB/KMS fallback (legacy, only when SSH is down):** the Kindle shows up in Windows as drive
**D:** mounted here under `/mnt/d` (`sudo mount -t drvfs 'D:' /mnt/d`). The script pre-flights
that Windows actually sees `D:\` (via `powershell.exe Test-Path`), so a
disconnected/charging-only Kindle fails with a clear message. Gotchas handled by the script:
- `/mnt/d` can linger as an empty leftover dir after unmount; the script checks `/proc/mounts`
  (not `ls`) to decide whether to mount.
- The Kindle's filesystem is FAT32 with no Unix perms/groups, so the USB path uses `rsync -r
  --delete` — NOT `rsync -a`, which fails with "Operation not permitted".
After install, fully restart KOReader (plugins load at startup), then open over
**Tools → Mahjong Solitaire**. If Windows stops seeing the drive after use, `sudo umount /mnt/d`.

## Reference

- Example studied: `example_app/casualkochess.koplugin` (chess/checkers/reversi/fox-and-hounds).
- Official "hello" plugin: `plugins/hello.koplugin` in the KOReader repo.
- KOReader source (widgets/containers/docs): https://github.com/koreader/koreader
- Plugin dev discussions: https://github.com/koreader/koreader/issues/9201
