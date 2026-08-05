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

## Mahjong plugin — current state and key contracts (US-01..11, US-19 shipped; US-12..18 planned)

This repo builds `mahjong.koplugin` (Mahjong Solitaire). `IMPLEMENTATION_PLAN.md` is the source
of truth for the locked design; the per-story detail lives in `implementation-plan/` (one file
per user story; `_completed` in the filename marks shipped stories — US-01..11, US-19 shipped,
US-12..18 planned: win summary/bests, stats screen, layout registry + picker, Spider, Bridge,
pause, hint/shuffle score penalties). The full history of *why* things are the way they are
(rejected designs, shipped bugs) lives in `IMPLEMENTATION_PLAN.md`, the story files, and the
code comments — this section is only the load-bearing facts an agent needs before touching the
code.

### Repo layout

```
mahjong.koplugin/            # the deliverable
├── _meta.lua                # plugin metadata (name/fullname/description)
├── main.lua                 # plugin class: menu/dispatcher, buildUILayout, gameplay,
│                            #   timer, settings/stats entry, save/restore, flash band
├── mahjonglogic.lua         # PURE logic (no ui/ requires): deck, Turtle layout, free tiles,
│                            #   match/win/shuffle, scoring, persistence, self-tests
├── mahjongboard.lua         # 3D board widget (InputContainer): IconWidgets in an
│                            #   OverlapGroup, per-layer up-left shift, hit-test, overlays
├── hudbar.lua               # 2-row top bar: title + gear (left) + 3 stat chips + quit X
├── mahjongsettings.lua      # floating settings dialog (CenterContainer card over the game)
└── icons/*.svg              # generated tile faces + overlays
tests/                       # official suite (tests/run.sh): mock.lua + usNN_*.lua harnesses
tools/                       # gen_icons.py, check_icons.py, preview.py (icon QA, not in suite)
install_plugin.sh            # rsync to the Kindle over /mnt/d
example_app/casualkochess.koplugin/   # the chess/checkers reference plugin
```

### Architecture map (what talks to what)

- `main.lua` owns the game: `self.board` (logic state), `self.history` (undo stack),
  `self.score`, `self.selected`, `self.board_view` (the rendered board), `self.status_bar`
  (HudBar). `handleTileTap(x, y, layer)` is the gameplay entry; it mutates the **logic board
  first**, then tells the **board widget** to update its paint.
- `MahjongLogic` (in `mahjonglogic.lua`) is pure: deck/layout/free-tiles/match/win/shuffle,
  scoring (`pairPoints`, `matchGroup`), and `serializeGameState`/`deserializeGameState`. UI
  code must never reach into it except through its functions; keep new logic here so it stays
  testable with plain `lua` (self-tests via `--selftest`).
- The board (`mahjongboard.lua`) paints one `IconWidget` per tile, absolutely positioned via an
  `OverlapGroup`'s `overlap_offset`. The stock `ButtonTable` is NOT used (flat projection was
  rejected — see plan). Tiles are keyed by `posKey(x,y,layer)` strings (`x,y,layer`).
- Hit-testing lives in the board (`hitTest`, walks `tiles_by_layer` top-down), not in the logic.

### Key contracts (do not regress)

1. **Board = 3D outward-bevel turtle.** Tiles are portrait 100x140 faces (aspect 1.4) on a
   shared **110x154 viewBox**; the outward bevels (right `#78909c`, bottom `#546e7a`) hang OFF
   the face's east/south edges. **Each layer is shifted up-left by exactly one bevel thickness**
   (`tilePos` subtracts `layer*bw`/`layer*bh`), so a raised tile's bevels land exactly on the
   edges of the tile directly beneath it — the bevel is the visible step and never overlaps the
   tiles to its east/south. Camera is bottom-right. (A `FrameContainer` subclass's `getSize()`
   MUST set `_padding_*` first, or every paint crashes — see Common pitfalls; that is why the
   board extends `InputContainer` and `getSize()` just returns `self.dimen`.)
2. **Bevel variants:** each kind ships `_n`/`_nr`/`_nb`/base (neither/right/bottom/both bevels),
   chosen by `MahjongLogic.iconForTile` — a same-layer neighbour hides that bevel; on the half
   grid an edge fully covered by TWO half-overlapping same-layer neighbours also hides it
   (`(x+1,y±0.5)` east, `(x±0.5,y+1)` south). SVGs are **generated by `tools/gen_icons.py`** —
   never hand-edit an SVG; re-run the generator and `tools/check_icons.py`.
3. **Layout** is the canonical GNOME Mahjongg Turtle: per-layer 87/36/16/4/1, grid x=0..14,
   y=0..7, fractional x/y on the head/tail/cap half-grid. `buildLayout()`/`gridBounds()` are
   memoized at module level — callers must not mutate the returned tables. (US-14 will
   generalize this into a per-layout registry; until then there is exactly one layout.)
4. **Free-tile rule:** a tile is free iff nothing overlaps it from layer+1 (within ±0.5 in both
   axes) AND at least one horizontal side is open (`x-1` or `x+1` on the same layer, also
   half-grid aware).
5. **Incremental board updates:** pair removal must NOT rebuild all 144 widgets. Use
   `board_view:removePair(a, b)` / `removeTile` / `addTile` / `addPair`, which keep
   `tiles_by_layer` + `tile_widgets` (posKey → IconWidget) in sync and end in
   `syncOverlapGroup()` (rebuilds the OverlapGroup child array in layer order + overlays).
   `removePair` drops BOTH widgets before refreshing neighbours (a stale widget with a nil kind
   crashes on `"mahjong/" .. nil` — the US-10 bug).
6. **Overlays** (`select`/`hint`) are extra IconWidgets appended AFTER all tiles in the same
   OverlapGroup, never added to `tiles_by_layer`, so they paint on top and taps pass through.
7. **Persistence:** one `LuaSettings` file at `DataStorage:getSettingsDir()/mahjong.lua`. Game
   state = `"game"` key (versioned table `v=1`: flat posKey→kind board + flattened 10-field undo
   history `{ax,ay,al,bx,by,bl,ka,kb,score,prev_last}`), validated hard on load (count sum must
   be 144, kinds valid, positions in layout, history disjoint). Settings = their own keys
   (`hints`, `confirm_new_game`, `score_method`, `layout`, `timer_update`, `timer_interval`).
   A **won (empty) board is NOT saved** — the key is cleared. Corrupt state silently starts
   fresh.
8. **Timer:** elapsed seconds always accrue (`getElapsed()` diffs `os.time()`); the mode only
   controls when the mm:ss **repaints** — `timer_update="interval"` (default, poll every
   `timer_interval`s, default 5) vs `"move"` (repaint on interaction only). `startTimer` bumps a
   run-id token; `stopTimer` freezes `elapsed_base`. No timer score bonus.
9. **Scoring:** base 10 per pair (`SCORE_PER_PAIR`), +5 chain bonus (`CHAIN_BONUS`) when the new
   pair is in the same `matchGroup` as the previous match; flowers chain with flowers, seasons
   with seasons. `score_method="basic"` disables the chain. US-18 will subtract hint/shuffle
   penalties.
10. **Dirtying:** a nested subwidget's `setDirty` alone never repaints (US-07's "zero effect"
    bug) — the window-level widget must be dirtied (`UIManager:setDirty(self, "ui")`), or use
    the `"all"` sentinel from inside the board.
 11. **Settings dialog (`mahjongsettings.lua`)** is the canonical floating-card pattern (reuse it
     for the US-13 stats screen and any other dialog): transparent full-screen `InputContainer` →
     `CenterContainer` → white rounded `FrameContainer`; `TapClose` dismisses on a tap outside
     `_panel_geom`; `onShow` re-dirties a refresh function over `_panel_geom` (else the panel may
     stay invisible); row buttons `setDirty(self, "ui")`; toggle labels are rebuilt via
     `setButtonText` (Button:setText truncates long values — the score-toggle bug); value buttons
     are sized to the widest value; timer-interval button greys out in "On interaction" mode.
 12. **Long-press auto-solve (US-19):** KOReader `Button` fires `hold_callback` ~0.5 s after
     contact (the device-global `ges_hold_interval_ms`), NOT per-widget, so a ~10 s hold is
     implemented as arm/cancel: the Hint button is a `LongPressButton` (a `ButtonWidget` subclass
     that surfaces the normally-hidden `hold_release` via `onHoldReleaseSelectButton` →
     `hold_release_callback`), `armAutoSolve` schedules a `UIManager:scheduleIn(10, ...)` and
     `disarmAutoSolve` cancels it on early release. The solver drives the shared
     `applyMatch(a, b)` helper (extracted from `handleTileTap`) once per `AUTO_SOLVE_STEP_SECONDS`;
     `matchingFreePair` + `applyMatch` are reused for scoring/history/save so an auto-solved game
     is indistinguishable from a played one. Any board tap / short Hint tap / Undo / New Game /
     close stops it (token-bumped pending steps no-op). Flash has a persistent `setFlash` vs the
     auto-clearing `flashMessage`, and `clearFlash` bumps the token (never nils it — the old
     `nil + 1` crashed on a second flash after a cleared band).

### Test harness notes (and verification workflow)

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
- `tests/mock.lua` stubs every KOReader module via `package.preload` (device, ui/uimanager,
  widgets, gettext, lfs, util, etc.) with a fresh `mock.newContext()` per test. Harnesses drive
  `main.lua`/`mahjongboard.lua` end-to-end: instantiate the class, fire the menu callback, tap
  toolbar buttons, run `ConfirmBox` ok_callbacks, and assert the mock window stack/`self[1]`.
- The harness cannot run `UIManager:scheduleIn`; tests call cleanup/clear paths directly.
- Mock gotchas (keep the stubs faithful, or the suite won't catch real layout bugs):
  - `WidgetContainer:extend` must be `function(self, o)` (colon receiver) or `:extend{...}`
    silently drops the class table → "loop in gettable" at runtime.
  - `frame_container.new` must mimic `Widget:new`: (a) `self:extend(o)` so the subclass
    metatable chain is preserved, (b) copy a positional child to `o[1]` (and map `o.layout` to
    `o[1]`), (c) call `o:init()` if present. Skipping any makes the harness crash with a nil
    `self[1]` or silently skip `init()`.
  - The mock mirrors real `OverlapGroup:getSize()` (iterates children) — a lazy no-op stub let a
    wrapper-table layout bug slip through to the device once.
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
