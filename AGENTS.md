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

## Mahjong plugin — implementation state (US-01..US-09 done)

This repo builds `mahjong.koplugin` (Mahjong Solitaire). Read `IMPLEMENTATION_PLAN.md` for
the locked design and story list. Current state:

- **Repo layout:** `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `mahjong.koplugin/` (the deliverable),
  `tests/` (official suite: `run.sh`, `mock.lua`, `us01_shell.lua`, `us03_icons.lua`,
  `us06_board.lua`, `us06_paint.lua`, `board_updates.lua`, `us07_gameplay.lua`,
  `us08_features.lua`, `us09_score.lua`, `us10_persistence.lua`, `us11_timer.lua`,
  `hud_bar.lua`), `install_plugin.sh`
  (device sync script), `example_app/casualkochess.koplugin/` (reference).
- **US-01 (done):** `_meta.lua` + `main.lua` skeleton; menu entry under `sorting_hint="tools"`
  ("Mahjong Solitaire"); `Dispatcher` action `mahjong` → event `MahjongStart` with `general=true`.
  The original separate placeholder widget was replaced by US-02's real shell — do not resurrect it.
- **US-02 (done):** `main.lua` now extends `FrameContainer` (not `WidgetContainer`) with
  `full_width`/`full_height`, `covers_fullscreen = true`, `is_doc_only = false`. Key methods:
  - `startGame()`: closes self if already shown, calls `buildUILayout()`, then `UIManager:show(self)`.
  - `buildUILayout()`: builds into `self[1]` a `VerticalGroup` = [`self.status_bar`,
    board widget, New Game toolbar (`CenterContainer` with a `plus` icon `ButtonWidget`),
    bottom `VerticalSpan`] — title bar on top, board in the middle, toolbar at the
    bottom raised off the screen edge.
    `board_h = full_height - status_h - toolbar_btn_h - bottom_gap`.
  - `createStatusBar()`: returns a `HudBar` from `hudbar.lua` (the file
    `require("hudbar")` in `main.lua`). `HudBar` extends `FrameContainer` and renders a
    full-width light-gray band: title "Mahjong Solitaire" (left), three stat **chips**
    (rounded white pills, dark-gray border, `radius`/`bordersize`/`background` on a
    `FrameContainer`) for Pairs remaining / Free pairs / Score, and the quit X (right).
    Each chip is a `VerticalGroup` of icon (`mahjong/hud_pairs`, `mahjong/lightbulb`,
    `mahjong/hud_score`) over a bold value (`smallinfofontbold`) over a tiny label
    (`smallinfofont`); the bar is a `HorizontalGroup` whose default `align = "center"`
    vertically centers the title, chips and X (no `CenterContainer` gymnastics needed).
    The quit X is a `ButtonWidget` (icon-only, `bordersize = 0`, background = the bar
    color so only the bold X shows) with `callback = right_icon_tap_callback` → `ConfirmBox`
    ("Exit Mahjong Solitaire?") → `saveGameState()` + `UIManager:close(self, "full")`.
    The bar keeps `title`/`right_icon`/`right_icon_size_ratio`/`right_icon_tap_callback`
    fields, so `tests/us01_shell.lua`/`us06_board.lua` still read `status_bar.right_icon_tap_callback`.
    Since US-10 the bar also carries `left_icon`/`left_icon_size_ratio`/
    `left_icon_tap_callback`: a square rounded-bordered gear (`appbar.settings`) pinned at
    the far left that opens the settings dialog.
    `HudBar` overrides `getSize()` (returns `Geom:new{w=full_width, h=HUD_H}`) — it MUST set
    the `_padding_left/right/top/bottom` fields in `init()` or every paint crashes with the
    framecontainer `_padding_*` nil error (see the pitfall above). Both `VerticalGroup` and
    `HorizontalGroup` memoize their size (`_size`/`_offsets`), so `setStats()` calls
    `resetLayout()` on the chip layouts and the bar layout after a value changes width.
  - New Game button → `ConfirmBox` ("Start a new game?") → `resetGame()` = rebuild layout +
    `UIManager:setDirty(self, "ui")`.
  - `handleEvent()`: dispatcher guard (`onMahjongStart`) then the `_window_stack` check, then
    forward to `FrameContainer.handleEvent`.
  - `onCloseWidget()`: cleanup stub (clears `self.board`). Since US-10 it saves the game
    state first, then stops the timer (see US-10 below).
  - `createToolbarButton` is a module-local function (not a method) — it never used `self`.
- **US-03 (done):** 42 tile kinds + 144-tile deck + flower/season match rule in `mahjonglogic.lua`
  (`createDeck`, `matches`); **171 SVGs** in `icons/` — 42 faces × 4 bevel variants
  (`b1`, `b1_nb`, `b1_nr`, `b1_n`) + `empty`/`select`/`hint`. The SVGs are **generated by
  `tools/gen_icons.py`** — never hand-edit an SVG; edit the generator and re-run it (`--check`
  verifies the committed icons match). Since the 2.5D redesign the bevel is an **OUTWARD
  extension**, not an inset: the white face fills (nearly) the full **100x140** portrait canvas
  (matching the board's 1.4 aspect) and the depth bevels hang OFF its right and bottom sides — a
  medium-gray side (`#78909c`) on the right and a darker base (`#546e7a`) on the bottom, so a
  tile with visible bevels is slightly LARGER than a bare face. The **3D step is produced by
  the BOARD, not the artwork**: each layer is shifted up-left by exactly the bevel thickness
  (`mahjongboard.lua:tilePos` subtracts `layer*bw`/`layer*bh`), so a raised tile's bevels land
  **exactly on the edges of the tile directly beneath it** — the bevel is the visible step and
  never overlaps the tiles to its east/south. The face also carries
  a **thin gray outline** (`FACE_STROKE`, ~1 viewBox unit ≈ 1 device px, tone `#78909c`) drawn
  INSIDE the face box: two adjacent same-layer tiles — which have no bevels between them — each
  draw half of this ring, so every seam shows a crisp ~1px grid line instead of an invisible
  white-on-white border (on e-ink that seam was illegible). **Every variant
  shares one 110x154 viewBox** — face at [0,0]-[100,140], bevels in the extension bands
  [100,110]x[0,154] (right) and [0,100]x[140,154] (base) — and absent bevels are just left
  transparent, so the board gives every tile widget the same dimen and the face is always
  anchored top-left. **Bevels only appear on exposed edges:** each kind ships in four variants
  — base (both bevels), `_nb` (no bottom), `_nr` (no right), `_n` (neither) — because a
  same-layer neighbour below/right would otherwise leave a fake dark seam inside an otherwise
   solid layer. Where BOTH bevels are exposed (base variant) the two side faces meet along a
   **diagonal line** from the face's bottom-right corner (100,140) to the widget corner (110,154) —
   the block's front-right edge as seen from the bottom-right camera, so the corner reads as one
   receding point (the implied rectangular box) instead of a flat L; the upper-left triangle of
   the corner is the right face (medium), the lower-right is the base face (dark). Single-bevel
   variants keep plain rectangles. The board picks the variant per tile via `MahjongLogic.iconForTile(board,x,y,layer)`,
   which also handles the half-grid head/tail: an edge fully covered by TWO half-overlapping
  same-layer neighbours (`(x+1,y-0.5)` + `(x+1,y+0.5)`) hides the bevel too, while a
  partly-exposed edge keeps it. Symbols are authored in 100x100 space and wrapped in
  `<g transform="translate(0,20)">` to center them in the taller face. Overlays
  `select`/`hint`/`empty` stay 100x140 (face box only) so the highlight frames the face without
  intruding on neighbours.
  `installIconsIfNeeded()` copies the SVGs with a pure-Lua `io.open` byte copy (P2 refactor — no
  per-file `os.execute('cp')` shell forks, which used to spawn ~45 processes at every plugin load).
- **US-04 (done):** Turtle `buildLayout()` (144 positions), seeded `newRng`/`shuffle`, `newGame(rng)`.
  The layout is the **canonical GNOME Mahjongg Turtle** (per-layer 87/36/16/4/1): L0 body rows
  (12+8+10+12+12+10+8+12=84) plus head (x=0, y=3.5) and tail (x=13..14, y=3.5); L1 block
  x=4..9,y=1..6; L2 block x=5..8,y=2..5; L3 block x=6..7,y=3..4; L4 single tile (x=6.5, y=3.5).
  Grid extents x=0..14, y=0..7; x/y may be fractional (the head/tail/cap sit on the half grid).
  `posKey`/`freeTiles` handle the fractional keys (`freeTiles` iterates the memoized
  `buildLayout()` and looks up each position's posKey — no per-key regex parse since the
  post-US-11 cleanup).
- **US-05 (done):** free-tile rules: `tileAt`, `isFree`, `freeTiles`, `hasMoves`.
- **US-06 (done, reworked):** real board rendering as an **outward-bevel 3D turtle**. The first
  US-06 attempt was a flat `ButtonTable` projection (see git history) — the user rejected it
  because it renders as a flat rectangle. `mahjongboard.lua` now extends `InputContainer` (NOT
  `FrameContainer` — see the getSize crash pitfall above) and paints one `IconWidget` per
  visible tile inside an `OverlapGroup`, each positioned with `overlap_offset = tilePos(x,y,layer)`.
  - Geometry (`computeGeometry`): portrait tiles `th = 1.4*tw` sized to fit both axes,
    `tw = floor(min(usable_w/units_w, (usable_h/units_h)/1.4))`; centered via `origin_x/origin_y`.
    **Each layer is shifted up-left by exactly the bevel thickness** (`tilePos` subtracts
    `layer*bw`/`layer*bh`), so a raised tile's face is inset from the tile directly beneath it
    and its outward bevels land **exactly on that underlying tile's face edges** — the bevel is
    the visible step and never overlaps the tiles to its east/south. Each widget is sized
    `tile_w = tw + bw`, `tile_h = th + bh` with `BEVEL_FRAC = 0.10`
    (`bw = floor(tw*0.10+0.5)`, `bh = floor(th*0.10+0.5)`), the face is
    anchored at the widget's top-left, and the outward depth bevels (right side `#78909c`,
    bottom base `#546e7a`) hang off the east/south edges. The
    bevels are on the bottom/right of the artwork, so the camera is at bottom-right and the
    stack rises toward top-left. (The original redesign tried the opposite: no layer offset
    with the bevels doing all the layering by overhanging the neighbours — the user rejected
    that because the bevels overlapped the tiles to their east/south; the per-layer shift of
    exactly one bevel makes the steps land cleanly. Earlier manual `LAYER_OFF_*` shifts —
    0.25/0.25, 0.2/0.14 up-and-right, 0.10/0.10 up-and-left — all produced skewed stacks or
    white face strips.) `units_w/units_h` come from `LAYOUT_BOUNDS`, which the board computes
    with `+1 + BEVEL_FRAC` on the east/south extents (bevel overhang) and
    `- layer*BEVEL_FRAC` on the west/north (the up-left shift).
  - **Bevel variants (US-06 follow-up):** the board resolves each tile's icon via
    `MahjongLogic.iconForTile(board,x,y,layer)` — a same-layer neighbour to the right/below
    hides that bevel (`_nr`/`_nb`/`_n`), so internal seams of a solid layer show no fake 3D
    bevel; only exposed edges keep theirs. On the half grid (head/tail/cap) the coverage rule
    also treats an edge as covered when it is adjacent to TWO half-overlapping same-layer
    neighbours (`(x+1,y-0.5)` + `(x+1,y+0.5)`, or `(x-0.5,y+1)` + `(x+0.5,y+1)`), so e.g. the
    head `(0,3.5)` and tail-left `(13,3.5)` drop the right bevel while the east tail tip
    `(14,3.5)` and the cap `(6.5,3.5,L4)` keep both.
  - Children are appended in `buildLayout()` order (bottom layer first) so lower tiles paint
    under upper ones; the `OverlapGroup` gets a board-sized `dimen` so the whole area is painted.
  - `updateBoard()` calls `free()` on the old paint container, rebuilds, and `setDirty`. This is
    the *structural* refresh (new game, shuffle). For pair removals, US-07 must use the
    **incremental API** instead of a full rebuild (P1 refactor): `removeTile(x,y,layer)` and
    `removePair(a, b)` drop only the affected `IconWidget`s from the `OverlapGroup` (via a
    `posKey → widget` map, `self.tile_widgets`) and keep `tiles_by_layer` (the hit-test table) in
    sync, then `setDirty`. Rebuilding all 144 widgets per removal would waste SVG-blitbuffer
    lookups and force a full e-ink repaint.
  - **Overlays (select/hint, for US-07/08):** `setOverlay(x,y,layer,icon)` / `clearOverlay(...)`
    / `clearAllOverlays()` append `IconWidget`s (e.g. `"mahjong/select"`, `"mahjong/hint"`)
    AFTER all tile widgets in the same `OverlapGroup` (`self.overlap`), so they always paint on
    top. They are never added to `tiles_by_layer`, so `hitTest` ignores them and taps pass through.
  - **Memoized layout (P1 refactor):** `MahjongLogic.buildLayout()` and `gridBounds()` are cached
    at module level (do not mutate the returned tables); the board precomputes `LAYOUT_BOUNDS`
    (unit-space extents) once at load instead of rescanning the layout per geometry pass.
  - Taps: `TapSelect` gesture ranged over `self.dimen`; `hitTest` walks layers MAX→0 and returns
    the topmost tile whose rect contains the point; `onTileTap(x, y, layer)` is invoked with the
    tapped tile's grid position. The handler signature is `onTapSelect(_, ges)` (the gesture is
    the second arg — see the Input-handling pitfall above).
  - `getSize()` returns `self.dimen` (no `FrameContainer` `_padding_*` contract involved).
  - `main.lua` wires `onTileTap = function(x, y, layer) self:handleTileTap(x, y, layer) end`;
    `handleTileTap(x, y, layer)` was an intentional empty stub until US-07 (now the gameplay
    entry point, below).
  - `buttontable.lua`/`button.lua` shims were **deleted** from the plugin (ButtonTable unused).
    Note the shims still exist in `example_app/casualkochess.koplugin` and are documented above
    for chess-style grids.
- **US-07 (done):** core gameplay in `main.lua` + logic hooks in `mahjonglogic.lua`.
  - `mahjonglogic.lua` additions: `removePair(board, a, b)` (validates both cells present,
    distinct, free, and matching; mutates only on success), `isWin(board)`, and
    `matchingFreePair(board)` (returns `{ a = {x,y,layer,kind}, b = {...} }` or nil). Also
    `shuffleBoard(board, rng)` which reassigns the remaining kinds to the remaining positions
    IN PLACE (same keys, same multiset, same count — verified by self-tests).
  - `main.lua` gameplay: `self.selected` (`{ x, y, layer, kind }`) + `self.board_view` (the
    board widget, stored at buildUILayout so taps can drive it). `handleTileTap`:
    free tile → `setSelection` (draws the `select` overlay); tap on the selected tile →
    `clearSelection`; tap on a matching free tile → `Logic.removePair` on the logic board
    FIRST, then `self.board_view:removePair(a, b)` (incremental widget removal, per the P1
    refactor), `self.score += SCORE_PER_PAIR` (10; US-09 replaces this stub), status update,
    then `checkGameState`; tap on a non-matching free tile → switch selection; non-free tiles
    are ignored. `checkGameState`: empty board → Win `ConfirmBox` ("Play again" → `resetGame`,
    "Close" → save + `UIManager:close`); no moves → immediate `shuffleBoard()` (US-07's simple
    variant; US-08 adds the prompt/repeat UX). `updateStatus()` pushes the three numbers into
    the HUD chips via `self.status_bar:setStats(pairs, free, score)` — pairs remaining, the
    count of currently-matching free pairs (legal moves available to tap, from the new
    `MahjongLogic.countFreePairs(board)`), and the score — + `UIManager:setDirty(self.status_bar, "ui")`
    and the window-level widget.
  - **Repaint fix:** after initial deployment showed "zero effect" taps, the board internal
    dirty calls were changed from `setDirty(self)` to `setDirty("all", "ui")`. Because the board
    is a nested subwidget, only the "all" sentinel (or dirtying the window-level widget `self`
    directly) flags the widget tree for repaint in `UIManager:_repaint`. `updateStatus` was
    similarly fixed to dirty the window-level widget.
  - `tests/us07_gameplay.lua` (registered in `tests/run.sh`) drives the whole flow headlessly:
    select/overlay, match removal (logic + rendered board + score + status), deselect,
    non-free ignored, selection switch, Win dialog play-again/close, and dead-board shuffle.
    The mock's titlebar stub gained `setSubTitle`/`setTitle` and now tracks all `setDirty`
    calls for regression testing.
- **HUD bar (done, 2-row):** the top of the screen is now a stylized `HudBar`
  (`mahjong.koplugin/hudbar.lua`, `require("hudbar")` in `main.lua`) instead of a
  `TitleBarWidget`. It is a full-width `VerticalGroup` of two rows:
  - **Row 1:** the title text (left), the settings gear (far left, US-10) and the quit X
    (far right) — `ButtonWidget`s with `bordersize = 0`, `background = BAR_BG` so only the
    icon shows. The gear (`appbar.settings`) is a square rounded-bordered button whose
    `left_icon_tap_callback` opens the settings dialog (`openSettings`).
  - **Row 2:** the three stat chips side by side: **Pairs** (`mahjong/hud_pairs`, a
    Material "layers" glyph), **Free** (`mahjong/lightbulb`), **Score**
    (`mahjong/hud_score`, a Material "star" glyph). Each chip is a rounded white pill
    (`bordersize`, `radius`, `background = WHITE`, `color = DARK_GRAY`) whose content is
    a `HorizontalGroup`: **icon | value | label**, so the icon is on the left, the bold
    value in the middle, and the tiny label at the right corner of the pill.
  - `setStats(pairs, free, score)` pushes the three values into the chip value
    TextWidgets and calls `resetLayout()` on the chip layouts + the bar layout so the
    memoized groups re-measure.
  `tests/hud_bar.lua` (registered in `tests/run.sh`, preloaded by `mock.lua` alongside
  the other plugin modules so `main.lua`'s `require("hudbar")` resolves) checks the two-row
  bar shape (title + 3 chips + quit X in row 1/row 2), that each chip is an
  icon/value/label row, and that `setStats()` both stores and pushes the values;
  `us01_shell.lua`/`us06_board.lua` still read `status_bar.right_icon_tap_callback` for
  the close flow.
  - **Row-height note:** the bar does NOT call `getSize()` on its own groups to compute
    `HUD_H`; it measures the individual child widgets (`title`, `quit_button`, the chips)
    first, then sums them. This avoids calling `getSize()` on `HorizontalSpan` (no such
    method) and sidesteps the group-size cache. When sizing a bar by its children, always
    measure the direct children, never the group.
- **US-08 (done):** undo, hint, and shuffle UX in `main.lua` + board/logic hooks.
  - Toolbar is now a 4-button `HorizontalGroup` under the board: `mahjong/chevron.left`
    (undo), `mahjong/lightbulb` (hint), `mahjong/shuffle` (shuffle), `plus` (new game).
    The hint/shuffle icons are Material Design SVGs shipped in `icons/` (see the US-03 note
    on `lightbulb.svg`/`shuffle.svg`) — the stock KOReader icon set has **no**
    `lightbulb`/`refresh`/`shuffle`, so verify any icon name against `resources/icons/mdlight`
    before use. Each button is a **cell** — a `VerticalGroup` of `{ icon ButtonWidget,
    hint TextWidget }` (small dark-gray caption beneath the icon, `smallinfofont` @ 11) —
    with the icon button as the tap area. The cells are **separated by 3 `HorizontalSpan`
    spacers plus one edge spacer on each side** (5 total — the outer buttons must not
    scrape the screen edges) — `tests/us01_shell.lua`/`us06_board.lua` scan the toolbar
    and unwrap the `VerticalGroup` cells (`cell[1]` = the bordered button) instead of
    hardcoding indices (cells sit at children 2/4/6/8 of `mj[1][3]`, gaps at 1/3/5/7/9).
  - **Button styling (UI pass):** each toolbar icon button is a slim rounded rectangle —
    `bordersize = 1px`, `radius = 4px`, `padding = 6px` around a square centered icon —
    so the whole `w × 48px` button is the tap area (the caption below is not part of it).
    **Do NOT use a `spacing` field on `HorizontalGroup`** — the stock KOReader group widget
    ignores it (verified against the source; the user hit exactly this: buttons stayed flush).
    Use `HorizontalSpan:new{ width = gap }`
    widgets between buttons. `toolbar_btn_w = floor((full_width - 5*gap)/4)` accounts for the
    five gaps (3 between + 2 edges). `createToolbarButton` computes the icon size as `h - 2*pad - 2*border`
    (ButtonWidget's total height = icon_height + 2*padding + 2*bordersize). The toolbar row
    reserves the caption height too: `toolbar_h = toolbar_btn_h + label_h`, probed from a
    throwaway `TextWidget` in `buildUILayout()`.
  - **Undo:** `self.history` is a stack of `{ a, b, ka, kb, score }` records pushed on every
    successful pair removal. `MahjongLogic.undoPair(board, a, b, ka, kb)` re-inserts the two
    kinds; `Mahjong:undo()` pops the last move, clears the selection, restores the logic board,
    calls `board_view:addPair(...)` (new incremental add), subtracts the move's score, and
    updates status. The board's `addTile`/`addPair` insert a tile into `tiles_by_layer`,
    refresh west/north neighbours' bevel variants, then `syncOverlapGroup()` (which now rebuilds
    the `OverlapGroup` child array from `tiles_by_layer` in layer order 0..4 plus overlays —
    this replaces the old "swap in place" logic that broke when a removed tile's `refreshTileIcon`
    rebuilt widgets). `removeTile` also calls `syncOverlapGroup()` so incremental removal and
    addition share one z-order-safe path.
  - **Hint:** `Mahjong:showHint()` finds `matchingFreePair`, draws the `hint` overlay on both
    tiles, and clears it after 2s via `UIManager:scheduleIn` (guarding that the board widget
    hasn't been replaced). If no move exists it offers the shuffle prompt.
  - **Shuffle:** `shuffleBoard()` (toolbar) prompts with a `ConfirmBox`; the no-moves path in
    `checkGameState()` shows a prompt too (replacing US-07's silent immediate shuffle). After
    shuffling it auto-repeats **at most 10 times** while the board still has no moves (a board
    whose remaining kinds can never pair must not recurse forever). `shuffleBoard(force)` skips
    the prompt.
  - **US-08 acceptance covered by** `tests/us08_features.lua` (registered in `tests/run.sh`):
    undo restores the exact previous state (logic board, widgets, score, history), undo on empty
    history is a no-op, hint draws two overlays, shuffle preserves the multiset, and a dead board
    prompts rather than shuffling silently.
- **US-09 (done):** real scoring + status feedback in `main.lua` + `mahjonglogic.lua`.
  - Scoring lives in `mahjonglogic.lua` (pure, unit-tested): `SCORE_PER_PAIR` (10),
    `CHAIN_BONUS` (5), `matchGroup(kind)` (the chain group: a suited/wind/dragon kind chains
    with itself, flowers chain with any flower, seasons with any season — exactly the
    match-rule grouping), and `pairPoints(prev_kind, kind)` (base 10, +5 when the new pair is
    in the same group as the previous match). No timer bonus (elapsed time is tracked
    and displayed — see US-10 — but never affects the score). Self-tests cover
    base/chain/cross-group/wildcard cases.
  - `main.lua`: `self.last_match_kind` tracks the previous match's kind; each successful
    `handleTileTap` match computes `pairPoints(prev_last, ka)`, stores `prev_last` in the
    history record (`{ ..., score, prev_last }`), and `undo()` restores both the score and
    `last_match_kind` so the chain survives undo. A shuffle does NOT reset the chain (a chain
    is about consecutive matches, not positions). `startGame`/`resetGame` clear the chain.
  - **Invalid-selection feedback (non-blocking):** tapping a non-free (blocked)
    tile no longer vanishes silently — `flashMessage(text)` writes the message
    into a **fixed-height feedback band** (`self.flash_band`/`self.flash_text`)
    that sits **between the board and the toolbar** in `buildUILayout()`
    (children: [1] status bar, [2] board, [3] band, [4] toolbar, [5] bottom
    spacer). The band is a chip-style `FrameContainer` (rounded border,
    screen-to-screen) whose `getSize` is overridden to the fixed strip height,
    so the slot is always reserved and the board geometry never shifts when a
    message shows/clears. **The band content is an `OverlapGroup`**, NOT a
    `CenterContainer` — the text carries `overlap_align = "center"` (centered
    across the FULL band width, independently of the icon) and the warning
    triangle `IconWidget` is a second direct child with
    `overlap_offset = { icon_x, icon_y }` (icon on the far left, vertically
    aligned to the text's center; sized `0.72 × flash_text_h`). Two failed
    attempts: a `CenterContainer` child crashed on missing `dimen`, and a
    **wrapper table** `{ overlap_offset = ..., icon }` crashed `OverlapGroup`
    `getSize` (children must be real widgets — see the Common-pitfalls entry).
    The icon is hidden with `hide = true` (KOReader ignores `visible`).
    It auto-clears after `FLASH_TIMEOUT` (2s) via
    `UIManager:scheduleIn`; each call bumps a `self._flash_seq` token so a stale
    clear timer (from a close/new game) is a no-op. Because it is NOT a modal
    dialog, board taps keep working while a message is showing — an accidental
    blocked-tile tap can be corrected immediately. The win dialog already
    reports the total score ("You cleared the board! Score: %d").
  - **US-09 acceptance covered by** `tests/us09_score.lua` (registered in `tests/run.sh`):
    logic scoring rules, chain scoring through the real tap flow, HUD score chip tracking,
    no-chain across different kinds, flower wildcard chains, undo restoring score + chain
    state, blocked-tile band placement (index 3 of the layout, between board and toolbar),
    the band clearing on timeout, non-blocking feedback (a tap right after a blocked tap
    still selects a free tile), chain-inclusive win dialog score, and chain persisting
    across a shuffle. Band-icon checks: the warning icon is hidden by default,
    uses an array-form `overlap_offset` on the widget itself, shows with the
    message, and hides again on clear.
  - **Feedback-band test note:** `tests/us09_score.lua` asserts on
    `mj.flash_text.text` (the band TextWidget) for the message and on
    `mj[1][3] == mj.flash_band` for its layout position — the harness cannot
    run `UIManager:scheduleIn`, so it calls `clearFlash()` directly to prove
    the timeout path. Any layout change that moves the band must update
    `us01_shell.lua`/`us06_board.lua`'s toolbar index (`mj[1][4]`, spacer
    `mj[1][5]`).
- **US-10 (done):** persistence (save/restore game + settings), a settings dialog, and an
  elapsed-time display, in `main.lua` + `mahjonglogic.lua` + `mahjongsettings.lua`.
  - **State save/restore:** everything lives in one `LuaSettings` file
    (`DataStorage:getSettingsDir() .. "/mahjong.lua"`); the whole game state is the
    `"game"` key, the settings are their own keys (`hints`, `confirm_new_game`,
    `score_method`, `layout`). `setSetting()` flushes immediately.
  - `MahjongLogic.serializeGameState(board, history, score, last_match_kind, elapsed)`
    returns a compact versioned table (`v=1`): the board stays a flat `posKey -> kind`
    table and the undo history is flattened to 10-field arrays
    `{ ax, ay, al, bx, by, bl, ka, kb, score, prev_last }`. `deserializeGameState(data)`
    validates EVERYTHING (version, valid kinds via `isKind`, canonical Turtle positions via
    `isLayoutPosition`, even tile count, matching history kinds, history not overlapping the
    board, `tileCount + 2*#history == 144`, non-negative score/elapsed, valid chain kind) and
    returns the state in the UI's record shape — or nil. Both are pure Lua with self-tests
    (round-trip, copy-not-alias, and a rejection path per validation rule).
  - `main.lua`: `saveGameState()` is called after every match (US-10), on undo, after a
    shuffle, and on `onCloseWidget()`. A **won (empty) board is NOT saved** — `saveGameState`
    clears the `"game"` key instead, so reopening after a win deals a fresh board.
    `restoreGameState()` reads the key, deserializes, and silently clears + starts fresh on
    corrupt data (garbage value, invalid layout position, impossible count, etc.).
    `startGame()` restores the saved board/history/score/chain/elapsed or deals a fresh game;
    `resetGame()` immediately re-saves the fresh board so the old game can't resurrect.
    Persistence does NOT save anything else (no per-tile history of moves beyond undo; the
    chain survives a close/reopen because `last_match_kind` is serialized).
  - **Settings dialog (`mahjongsettings.lua`):** a **floating window** (the ConfirmBox
    pattern), not a full-screen page: a transparent full-screen `InputContainer` whose single
    child is a `CenterContainer` holding a white rounded `FrameContainer` card, so the game
    stays visible around the panel. A `TapClose` full-screen gesture dismisses the dialog
    (like Cancel) when the tap misses the card (`onTapClose` tests `ges.pos:notIntersectWith(self._panel_geom)`
    — the card's on-screen rect computed from its centered size). **`onShow` re-dirties the
    dialog with a refresh function covering `_panel_geom`** (the ConfirmBox trick): `UIManager:show`
    dirties the widget but enqueues NO refresh, and if the settings gear's own tap left a small
    "fast" refresh in the queue, `_repaint` paints the panel into the framebuffer yet skips the
    full-screen refresh — the dialog stayed invisible until an interaction forced a refresh.
    One row per setting — an
    On/Off toggle button for **Hints** and **Confirm new game**, a Chain → Basic cycling
    button for **Score**, a **Timer update** mode button (Periodic → On interaction),
    and a **Timer interval** button — plus a bottom
    Reset / Save / Cancel row. The **informational Layout (Turtle) row was removed**
    (layout is still round-tripped via `changes`/save, but its UI will be handled
    differently later). A **close X** (grey square, `mahjong/close`, the HUD quit-X
    style) is pinned at the panel's top-right corner in the "Settings" title row
    (`self._close_btn`), and tapping it discards changes and closes — exactly like
    Cancel (it calls `self:cancel()`, so the owner's `onCancel` restarts the paused
    timer loop). The **title row spans the FULL inner width of the panel**
    (`title_row_w = max(value-column width, 3×Reset/Save/Cancel + 2×gap)`), NOT just
    the value column — the panel is as wide as its widest child (the bottom button
    row), so a title row sized to the value column alone would get centered with
    empty space to the right of the X. Sizing it to the widest child pins the X flush
    against the panel's inner right edge. Changes are collected in a `changes` table and ONLY written to
    `LuaSettings` on Save (Cancel discards, Reset restores the defaults); `onApply` refreshes
    `score_method` + the HUD after Save, `onCancel` lets the owner resume what `openSettings`
    paused. **Each row button's callback updates `changes`, re-renders the label via
    `setButtonText()` (see below), and MUST call
    `UIManager:setDirty(self, "ui")` on the dialog** — setDirty on a subwidget never flags a
    window, so without it the button highlights on tap but the value stays stale on screen
    until a Save+reopen (this was the "no visual change" bug). Opened from the HUD's left
    settings gear (`main.lua:openSettings`), which also calls `stopTimer()` first and relies
    on `onApply`/`onCancel` to `startTimer()` again — otherwise the US-11 polling loop flashes
    a full-screen refresh behind the floating panel every tick. `hints=false` disables the
    Hint button; `confirm_new_game=false` makes the New Game button skip its `ConfirmBox`;
    `score_method="basic"` makes every pair worth a flat `SCORE_PER_PAIR` (no chain bonus).
    - **Settings polish (label re-alignment + no cut-off values):** every toggle button is
      sized at init to fit the **widest value on a single line** — `init()` measures every
      possible value ("On"/"Off"/"Basic"/"Chain (+5 bonus)"/"Periodic"/"On interaction"/"N s")
      with a throwaway `TextWidget` in the exact font the `Button` renders them with (`cfont`
      **20 bold**, passed explicitly to `makeButton` as `text_font_face`/`text_font_size`/
      `text_font_bold`), adds the button padding/borders plus ~12px breathing room, and gives
      every value button that shared `toggle_w` — so nothing wraps, truncates, or gets cut off
      when a value changes, and the button column is uniform. The row **labels are right-aligned**
      to the widest label (each row is `[alignment HorizontalSpan, label, label_gap span,
      control]`, where the leading span is `max_label_w - label_w`), so the button column starts
      at the same x on every row instead of staggering with the label lengths.
    - **`setButtonText()` rebuilds the label** (free the old `label_widget`, then re-run
      `Button:init`) instead of using `Button:setText` — KOReader's `Button:setText` has a
      **fast path** that pushes the new text into the button's EXISTING `label_widget`; when
      that label is a single-line `TextWidget` (e.g. after showing the short "Basic") and the
      new value is long ("Chain (+5 bonus)"), the fast path renders the long text as **one
      truncated line cut off at the end of the button** (the score-toggle bug). Rebuilding
      always reruns the full truncation/wrap logic, so the value renders exactly like it did
      the first time the button was built. Mock fallback: store `.text` (the suite asserts on
      it).
    - **Timer interval is greyed out + non-interactive in "On interaction" mode:** an interval
      is meaningless in `move` mode, so the mode button's callback calls `setIntervalEnabled()`
      which `Button:disable()`s / `Button:enable()`s the interval button (grey label, taps
      ignored — `onTapSelectButton` only fires the callback when `enabled`); the callback body
      also guards `if not enabled then return` (the mock drives callbacks directly). The dialog
      starts in the disabled state if a saved `move` mode is active; Reset re-enables it. The
      enable/disable helper is stored as `self._set_interval_enabled` so `resetToDefaults` can
      reuse it.
  - **Elapsed-time display:** a `UIManager:scheduleIn` polling loop (the kochess
    `pollingLoop` pattern; originally `TIMER_TICK = 1`, now a US-11 setting — see the
    "updated by US-11" note below) drives a permanently visible mm:ss in the RIGHT
    part of the feedback band (`main.lua:updateTimerDisplay` / `MahjongLogic.formatElapsed`).
    It is a third child of the band's `OverlapGroup` with an array-form `overlap_offset`
    right-aligned to the band edge and a fixed-width slot (probed from a `"00:00"`
    `TextWidget`) so the number doesn't drift. `startTimer` bumps a run-id token;
    `stopTimer` (on close) freezes `elapsed_base = getElapsed()`. Elapsed seconds are saved in
    the state (`elapsed`), so the clock survives close/reopen. No score bonus.
  - **US-10 board bug fixed en route:** `Board:removePair` used to call `removeTile(a)` then
    `removeTile(b)`. The caller updates the shared logic board BEFORE the view, so the second
    tile is already gone from `board` while its widget is still present; when the pair tiles
    are adjacent (one west/north of the other) the first removal's neighbour-icon refresh hit
    that stale widget and crashed on `"mahjong/" .. nil`. `removePair` now drops BOTH widgets
    (new `dropTileWidget`) before refreshing neighbours (new `refreshWestNorthNeighbours`,
    shared by `removeTile`/`addTile`), and `refreshTileIcon` guards against a nil icon.
  - **US-10 acceptance covered by** `tests/us10_persistence.lua` (registered in `tests/run.sh`):
    settings defaults + set/get + cross-instance round-trip, save-after-every-match contents,
    restore in a fresh instance (identical board/score/chain/history, positions preserved),
    undo-after-restore, New Game replacing the saved state, corrupt-state handling (garbage and
    invalid-table both deal fresh AND clear the key), won-board-not-saved, settings dialog
    (toggle collect / Save persists / Cancel discards / Reset restores / score cycle + onApply),
    score cycling Basic back to the full "Chain (+5 bonus)" label, uniform toggle-button width
    + right-aligned row labels (`[pad, label, gap, button]` shape), the Layout row being gone,
    the in-panel close X acting like Cancel (discards + notifies the owner), `confirm_new_game=false`
    skipping the prompt, and the mm:ss band display.
    The mock's `luasettings` stub is an in-memory store shared across `open()` calls in a ctx
    (`ctx.settings_store`, `ctx.flushes`), so a later plugin instance reads back what an earlier
    one saved.
  - **Elapsed-time display (updated by US-11):** the permanently visible mm:ss in the RIGHT
    part of the feedback band repaints either periodically (`timer_update = "interval"`, the
    default) or only on board interaction (`timer_update = "move"`), chosen in the settings
    dialog. The elapsed seconds ALWAYS accrue (`getElapsed()` diffs against `os.time()`) and
    are saved with the game state; the mode only controls when the DISPLAY repaints. In
    "interval" mode a kochess-style `UIManager:scheduleIn` polling loop repaints every
    `timer_interval` seconds (default **5**, was 1 in US-10 — a 1 Hz e-ink repaint was
    overkill); the dialog offers `{1,2,5,10,15,30,60}`. In "move" mode no loop is armed and
    `updateTimerDisplay()` is instead called from the interaction handlers (select/deselect/
    match/undo/shuffle/new-game) so an idle board never forces an e-ink refresh.
    `timerInterval()` clamps invalid stored values (non-numeric or < 1) back to the default 5.
    `openSettings`'s `onApply` restarts the loop (`stopTimer` → `startTimer`) so a changed
    mode/interval takes effect immediately.
- **US-11 (done):** timer refresh mode + interval settings (see the updated elapsed-time
  display note above). New settings keys `timer_update` ("interval"/"move") and
  `timer_interval` (seconds), with two new settings-dialog rows ("Timer update" cycles
  Periodic → On interaction; "Timer interval" cycles the offered values) that are collected,
  saved with the rest, and restored by Reset like every other row. `tests/us11_timer.lua`
  (registered in `tests/run.sh`) captures `scheduleIn`/`nextTick` on the mock uimanager to
  assert the loop's reschedule delay, and drives the dialog rows; coverage: defaults not
  written, interval loop uses 5 / a stored 2 / a saved-then-onApply 30, move mode arms no loop
  yet runs the clock, move mode refreshes the mm:ss on select/match/undo, dialog cycle/Save/
  Cancel/Reset, the interval row being greyed out + tap-ignored in "On interaction" mode (and
  re-enabled in Periodic mode / on Reset, including when the dialog opens with a saved `move`
  mode), onApply re-arming, and interval clamping.

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
- Mock gotcha (container `new`): the mock's `frame_container.new` must mimic KOReader's
  `Widget:new` — it must (a) call `self:extend(o)` so a subclass table's metatable chain is
  preserved, (b) copy a positional child to `o[1]` (and map `o.layout` to `o[1]` for code that
  still uses the old named form), and (c) call `o:init()` if present. Forgetting any of these
  makes the harness either crash with a nil `self[1]` or silently skip `init()` (no dispatcher
  action registered). The plugin code itself must pass children as positional array args (see
  the Common-pitfalls entry on `self[1]`).
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
