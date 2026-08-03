# Implementation Plan — Mahjong Solitaire for Kindle (KOReader Plugin)

## Goal

Build a native KOReader plugin that plays **Mahjong Solitaire** (tile-matching, aka "Shanghai")
on jailbroken e-ink Kindles. The player clears a 144-tile board by tapping matching tiles that
are "free" (not blocked from above and with at least one open side).

Everything is driven by an AI agent working through the **User Stories** below, one per prompt.
Each story produces a working, verifiable increment before the next begins. Read `AGENTS.md`
first — it contains the KOReader plugin knowledge (structure, widgets, rendering, pitfalls)
captured from `example_app/casualkochess.koplugin`.

## Key design decisions (locked in)

1. **Game variant:** Mahjong Solitaire. No AI opponents, single player, ideal for e-ink.
2. **Plugin name:** `mahjong` (dir `mahjong.koplugin`, menu item "Mahjong Solitaire").
3. **Game logic is pure Lua, free of UI dependencies** (`mahjonglogic.lua` + friends). It must be
   runnable/testable with a plain `lua` interpreter (add `--`-style self-tests to the file).
   The UI (`main.lua`, `mahjongboard.lua`) only reads/writes via a small API.
4. **Board model — flat projection.** The board is 3D: a tile is `{ x, y, layer }` on an integer
   grid shared by all layers. The classic **Turtle layout** (144 tiles) is:
   - L0: x=2..11, y=2..7 (60 tiles)
   - L1: x=1..12, y=2..5 (48)
   - L2: x=3..8,  y=2..5 (24)
   - L3: x=4..7,  y=3..4 (8)
   - L4: x=4..7,  y=4    (4)
   Rendering projects to a flat grid: the cell at (x,y) shows the **topmost** tile at that
   position (or empty). This is simpler than half-tile-offset rendering and looks correct from
   above; offset "peek" rendering is a later enhancement, not a requirement.
5. **Free-tile rule** (flat projection): tile at (x,y,L) is free iff:
   - no tile exists at (x,y,L+1) above it, **and**
   - at least one horizontal side is open: no tile at (x-1,y,L) OR no tile at (x+1,y,L).
6. **Tile set (144):** 3 suits (Bamboo, Characters, Dots) ranks 1-9 ×4 = 108; 4 Winds (East,
   South, West, North) ×4 = 16; 3 Dragons (Red, Green, White) ×4 = 12; 4 Flowers + 4 Seasons
   = 8. Flowers/Seasons may match any flower with any flower and any season with any season
   (classic rule) — keep this rule, it makes Flower/Season pairs always matchable.
7. **Input:** single taps only (e-ink). Tap a free tile to select it; tap a second free tile of
   the same kind to remove the pair. Tap a selected tile again to deselect. Invalid selection
   just re-selects.
8. **Rendering:** `ButtonTable` grid (patched `buttontable.lua` for `alpha=true` transparency),
   tiles as simple SVG icons installed into `DataStorage:getDataDir()/icons/mahjong/`.
9. **Persistence:** `LuaSettings` in the KOReader settings dir; game state (tile deck, removed
   pairs, score) serialized to a table, saved on close, restored on start. Also persist a small
   settings table (hints on/off, new-game confirmation, etc.).
10. **No heavy background work needed** (no engine/AI) — the only timers are cosmetic (elapsed
    time). Coroutines are unnecessary; keep the UI loop simple.

## Repo layout (target)

```
kindle_majong/
├── AGENTS.md                     # this repo's plugin-writing guide (already written)
├── IMPLEMENTATION_PLAN.md        # this file
└── mahjong.koplugin/             # the deliverable
    ├── _meta.lua
    ├── main.lua                  # plugin class: menu, dispatch, full-screen shell
    ├── mahjonglogic.lua          # pure logic: deck, layout, free-tiles, match, win, shuffle
    ├── mahjongboard.lua          # ButtonTable board widget (rendering + tap handling)
    ├── buttontable.lua           # alpha patch (copy from example_app)
    ├── icons/*.svg               # tile + overlay icons
    └── README.md                 # install/usage (write at the end)
```

## Agent workflow for each story

1. Read `AGENTS.md` and any prior story output before starting.
2. Implement pure logic files first, then UI, keeping logic free of `require("ui/...")`.
3. Verify with a plain `lua` interpreter where a self-test is specified (the machine running
   this repo should have `lua`/`luajit`). Confirm the self-test passes before moving on.
4. For UI: keep the widget code aligned with the example plugin's patterns; run `luacheck` if
   available; make sure nothing errors at load time.
5. Deployment check (can be a dry-run on the repo): confirm the plugin dir structure, that
   `_meta.lua`/`main.lua` return the expected values, and that icons referenced exist.
6. When a story is complete, summarize what was done and any follow-ups.

---

## User stories

### US-01 — Plugin skeleton loads and shows a placeholder screen

As a player, I want to launch "Mahjong Solitaire" from the KOReader main menu so I can confirm
the plugin is installed and reachable.

- Create `mahjong.koplugin/` with `_meta.lua` and `main.lua`.
- `main.lua` extends `WidgetContainer`, `name = "mahjong"`, `is_doc_only = false`.
- Register to main menu (`sorting_hint = "tools"`, text "Mahjong Solitaire"); on callback show a
  temporary full-screen widget (or `InfoMessage`) so the entry is visibly wired up.
- Optionally register a Dispatcher action (`MahjongStart`) as in the example.

**Acceptance:**
- Structure matches AGENTS.md; `_meta.lua` returns correct table; `main.lua` returns a class.
- Menu item appears and, when tapped, displays the placeholder.
- No `require` errors at load; `luacheck` clean (if available).

### US-02 — Full-screen game shell with title bar and New Game/Exit

As a player, I want a proper full-screen game window with a status/title bar so I can start a
game and exit cleanly back to KOReader.

- Plugin widget extends `FrameContainer` with `full_width`/`full_height` and
  `covers_fullscreen = true`.
- `startGame()` builds a minimal layout (empty board area + `TitleBarWidget`) into `self[1]` and
  calls `UIManager:show(self)`.
- Title bar: close icon → confirm → save state (stub) + `UIManager:close(self, "full")`.
- Add `onCloseWidget()` cleanup stub; guard `handleEvent()` using the `_window_stack` pattern.
- Add a "New Game" button (e.g. `plus` icon button like the example toolbar) that triggers a
  confirm box, then resets the board (stub).

**Acceptance:** Window opens full-screen, title bar shows, close exits back to KOReader with no
errors/leaked timers, New Game confirm box appears and works.

### US-03 — Tile deck: 144-tile definition + SVG assets

As a player, I want each tile to have a distinct, recognizable face so I can tell tile kinds apart.

- Pure logic `mahjonglogic.lua`: define tile kind constants (bamboo `b1..b9`, characters
  `c1..c9`, dots `d1..d9`, winds `east/south/west/north`, dragons `red/green/white`,
  flowers `flower1..4`, seasons `season1..4`).
- `createDeck()` returns exactly 144 tile IDs (108 suited + 16 winds + 12 dragons + 8
  flowers/seasons). Self-test: counts per category match.
- `matches(a, b)` returns true iff same kind, EXCEPT flowers match any flower and seasons match
  any season.
- Create simple flat-fill SVG icons (36 distinct faces) sized ~100x100 viewBox, installed via
  `installIconsIfNeeded()` (copy from plugin `icons/` to
  `DataStorage:getDataDir()/icons/mahjong/`), plus `select.svg`/`hint.svg` transparent overlays.
  Use the patched `buttontable.lua` for `alpha=true`.

**Acceptance:**
- Self-test passes: deck size 144, per-category counts, flower/season matching rule.
- `installIconsIfNeeded()` copies SVGs; icon names referenced in code exist on disk.
- (Optional) render a test strip of tiles on screen to eyeball icon quality.

### US-04 — Turtle layout + shuffled tile placement

As a player, I want the board to be a standard shuffled Turtle so every game is different.

- In `mahjonglogic.lua`: `buildLayout()` returns the 144 tile positions from the Turtle table
  above (keyed by `{x,y,layer}`).
- `newGame(rng)`: shuffle the 144 deck tiles and assign them to the 144 positions.
- Self-tests: layout has exactly 144 positions matching the table; after shuffle every deck tile
  appears exactly once; layout is deterministic given a seeded RNG.

**Acceptance:** Self-tests pass. (No UI needed yet — this is pure logic.)

### US-05 — Free-tile detection (core rules)

As a player, I want only genuinely "free" tiles to be selectable so the game is fair.

- Pure logic functions on a board state:
  - `tileAt(board, x, y, layer)`.
  - `isFree(board, x, y, layer)` implementing the rule in design decision 5.
  - `freeTiles(board)` returns all free tiles.
  - `hasMoves(board)`: true if at least one pair of matching free tiles exists.
- Self-tests: build a small hand-crafted board; assert known free/blocked results, including:
  a tile covered from above is not free; a tile with both sides occupied is not free; a tile
  with one open side IS free; empty cell is not a tile; after removing a pair the newly exposed
  tile becomes free.

**Acceptance:** Self-tests pass for all listed cases.

### US-06 — Render the board on screen (first playable visuals)

As a player, I want to see the full Turtle board of tiles laid out on the e-ink screen.

- `mahjongboard.lua`: `ButtonTable` over the flat projection grid (max x = 12, max y = 7).
  Compute `cell = floor(min(usable_w/cols, usable_h/rows))` using `Screen:scaleBySize()`.
- Each cell is a button with `icon = topmost tile icon or "mahjong/empty"`, `alpha=true`,
  callback → `handleClick(x, y)`.
- `updateBoard()` refreshes every cell icon + `UIManager:setDirty`.
- Tiles above/overlap fully cover lower ones in the projection (topmost wins).

**Acceptance:** Full board renders as 144 tiles in the Turtle silhouette; board fits the screen
on the target resolution; no blank cells; icons are legible.

### US-07 — Core gameplay: select, match, remove, win

As a player, I want to play a full game: tap two matching free tiles to remove them and win when
the board is clear.

- Tap behavior:
  - Free tile tapped → select (highlight with `select` overlay). Non-free tile tapped → ignored
    (or brief feedback).
  - Second tap on a matching free tile → remove both, update score stub, expose new tiles.
  - Tapping the selected tile again → deselect.
  - Tapping a different tile → switch selection.
- After each removal, call `freeTiles`/`hasMoves`; if the board is empty show a Win dialog
  (`ConfirmBox`: "Play again" → new game, "Close" → exit). If no moves remain, offer Shuffle
  (can be a simple immediate reshuffle of remaining tiles this story; dedicated shuffle UX in
  US-08).
- Keep game logic in `mahjonglogic.lua`: `removePair(board, a, b)`, `isWin(board)`,
  `matchingFreePair(board)`.

**Acceptance:**
- Self-test (logic): removing a valid pair updates state; invalid pairs rejected; `isWin` true
  only when empty; `matchingFreePair` returns a valid pair when one exists.
- Manual (on device/emulator): full game flow works — select, match, remove, win dialog,
  play-again resets a new shuffled board.

### US-08 — Undo, hint, and shuffle

As a player, I want undo, a hint when stuck, and shuffle to rescue a dead board.

- **Undo:** keep a stack of removed pairs; undo restores the two tiles (validate they were both
  free/removed last). Toolbar or menu button "undo" (`chevron.left` icon). Undo clears score for
  that pair.
- **Hint:** find a matching free pair (`matchingFreePair`) and flash the `hint` overlay on both
  for a short time (then clear).
- **Shuffle:** reshuffle remaining (unmatched) tiles in place; prompt with `ConfirmBox` first.
  If still no moves after shuffle, allow repeat; also auto-offer when `hasMoves` is false.
- Persist the undo stack for state restore (US-10).

**Acceptance:**
- Self-tests: undo restores exact previous state; shuffle preserves the multiset of remaining
  tiles and number of remaining tiles.
- Manual: undo works repeatedly; hint highlights a real matching pair; shuffle changes the board
  and enables play when stuck.

### US-09 — Score, pair counter, and status feedback

As a player, I want feedback on my progress and a running score.

- Score model (keep simple, document it in README):
  - Base 10 points per matched pair.
  - Consecutive bonus: +5 if the previous match was the same tile kind (chain).
  - Timer bonus: on a win, add remaining-time bonus (or skip if timing not implemented).
- Status bar (TitleBarWidget): title = elapsed time (optional, `mm:ss`), subtitle = "Pairs
  remaining: N · Score: S".
- Show brief feedback on invalid selections (e.g. a small `InfoMessage` or status subtitle
  flash) and on win ("You cleared the board! Score: S").

**Acceptance:** Score/pairs update correctly as pairs are removed; chain bonus applies only on
consecutive same-kind matches; status bar reflects state; logic for score is unit-testable and
tested.

### US-10 — Persistence: save/restore game + settings

As a player, I want my game to survive closing the plugin so I can continue later.

- `LuaSettings` file `mahjong.lua` in the KOReader settings dir.
- Settings: hints enabled, new-game confirm enabled, score method, layout variant (Turtle only
  for now).
- Game state export/restore: remaining tile deck (position + kind), removed-pair history
  (for undo), score, elapsed time. Restore on `startGame()`; save on close (title-bar close and
  `onCloseWidget`).
- Invalid/corrupt saved state → silently start a new game.

**Acceptance:** Close mid-game, reopen → board/score/undo stack identical. New Game clears the
saved state. A tampered/corrupt settings value falls back to a fresh game without crashing.

### US-11 — Polish and cross-device refinement

As a player, I want a polished, stable game on my specific Kindle.

- Validate layout/sizing on the common Kindle resolutions (6", 6.8", 7") via `scaleBySize`;
  confirm the board never clips and cells stay tappable (min cell size).
- Tune e-ink refresh: use `"ui"` dirtying during play, `"full"` on screen open/close and on
  shuffle; avoid flicker-heavy updates.
- Verify icon legibility in grayscale; refine any muddy SVGs; ensure `select`/`hint` overlays
  are visible on both light and dark tiles.
- Add `README.md` to the plugin (install: copy `mahjong.koplugin` into
  `/mnt/us/extensions`? No — into the KOReader `plugins/` dir; usage; scoring rules).
- Run `luacheck`; clean up comments/dead code; ensure all user-facing strings use `_()`.

**Acceptance:** Game runs smoothly end-to-end on the target device; no clipped tiles; overlays
readable; README present; luacheck clean.

---

## Later / optional enhancements (not in the current scope)

- Half-tile-offset rendering for a true "stacked" look.
- Additional layouts (e.g. "Spider", "Bridge") selectable from settings.
- Keyboard/d-pad navigation for non-touch Kindles.
- Achievement/stat tracking and best-time leaderboard.
- Localization catalogs.
