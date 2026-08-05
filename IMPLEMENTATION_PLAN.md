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
4. **Board model — outward-bevel 3D turtle.** The board is 3D: a tile is `{ x, y, layer }` on a
   shared grid (x, y may be fractional — the head/tail/cap sit on the half grid). The classic
   **Turtle layout** (144 tiles, the canonical GNOME Mahjongg map) is:
   - L0: body rows (12+8+10+12+12+10+8+12 = 84) + head (x=0, y=3.5) + tail (x=13..14, y=3.5) = 87
   - L1: block x=4..9, y=1..6 (6x6 = 36)
   - L2: block x=5..8, y=2..5 (4x4 = 16)
   - L3: block x=6..7, y=3..4 (2x2 = 4)
   - L4: single tile x=6.5, y=3.5 (1)
   Grid extents: x=0..14, y=0..7.
    Rendering draws every tile at its real `(x, y, layer)` position, but **each layer is shifted
    up-left by exactly the bevel thickness** (`tilePos` subtracts `layer*bw`/`layer*bh`), so a
    raised tile's face is inset from the tile directly beneath it and its outward bevels land
    exactly on that underlying tile's face edges — the bevel is the visible step and never
    overlaps the tiles to its east/south. Each tile face is 100x140 (portrait, aspect 1.4)
    and the outward depth bevels (right side `#78909c`, bottom base `#546e7a`) hang OFF the
    east/south edges into extension bands of a shared 110x154 viewBox, so a tile with visible
    bevels is slightly larger than a bare face. The bevels are on the
    bottom/right, so the camera is at the bottom-right and the stack rises toward the top-left.
    (A first redesign shipped no layer offset and let the artwork overhang the neighbours — the
    user rejected it because the bevels overlapped the tiles to their east/south; the
    per-layer shift of exactly one bevel makes the steps land cleanly. Earlier manual
    `LAYER_OFF_*` shifts — 0.25/0.25, 0.2/0.14 up-and-right, 0.10/0.10 up-and-left — all
    produced skewed stacks or white face strips.) The stepped pyramid silhouette, the head/tail
    protrusions, and the exposed depth
    bevel edges of lower tiles are visible (US-06, reworked from the earlier flat-projection
    experiment — see `AGENTS.md` history). Lower layers paint first; the topmost tile at any
    screen point is the one you tap.
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
8. **Rendering:** the board is an `InputContainer` that paints `IconWidget`s (the tile SVGs)
   absolutely positioned via an `OverlapGroup`'s `overlap_offset` — each tile at its real
    `(x, y, layer)` position on the shared grid. It hit-tests taps itself (topmost tile at the
    tapped point wins) and forwards `(x, y, layer)`. The stock `ButtonTable` grid from the
    original plan was replaced; `buttontable.lua`/`button.lua` shims were removed. Tiles install
    into `DataStorage:getDataDir()/icons/mahjong/`.
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
├── tests/                        # official test suite (tests/run.sh)
│   ├── run.sh                    # luac -p + luacheck + logic self-tests + harnesses
│   ├── mock.lua                  # shared KOReader stubs (fresh mock.newContext() per test)
│   ├── us01_shell.lua            # meta, menu, dispatcher, startGame/new-game/exit shell
│   ├── us03_icons.lua            # installIconsIfNeeded copies every SVG
│   ├── us06_board.lua            # 3D turtle: geometry, z-order, hit-test, taps, wiring
│   ├── us06_paint.lua            # getSize/paint-contract regression
│   ├── us07_gameplay.lua         # select/match/remove/win flow
│   ├── us08_features.lua         # undo/hint/shuffle
│   ├── us09_score.lua            # scoring, chain bonus, feedback band
│   ├── us10_persistence.lua      # save/restore + settings dialog
│   ├── us11_timer.lua            # timer refresh modes + interval settings
│   ├── hud_bar.lua               # two-row HUD shape + setStats (preloaded by mock)
│   ├── board_updates.lua         # incremental tile add/remove contract
│   ├── us12_stats.lua            # win summary + lifetime stats (planned)
│   ├── us13_stats_screen.lua     # stats button + floating stats card (planned)
│   ├── us14_layouts.lua          # layout registry + picker (planned)
│   ├── us15_spider.lua           # Spider layout (planned)
│   ├── us16_bridge.lua           # Bridge layout (planned)
│   ├── us17_pause.lua            # pause overlay (planned)
│   ├── us18_penalties.lua        # hint/shuffle score penalties (planned)
│   └── us19_autosolve.lua        # long-press Hint auto-solver (US-19)
└── mahjong.koplugin/             # the deliverable
    ├── _meta.lua
    ├── main.lua                  # plugin class: menu, dispatch, full-screen shell
    ├── mahjonglogic.lua          # pure logic: deck, layout, free-tiles, match, win, shuffle
    ├── mahjongboard.lua          # offset-layer 3D board widget (IconWidget/OverlapGroup + hit-test)
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
- Create simple flat-fill SVG icons (42 distinct faces, each in 4 bevel variants: base, `_nb`
  no bottom, `_nr` no right, `_n` neither) sized 100x140 (portrait, matching the
  board's 1.4 aspect) installed via `installIconsIfNeeded()` (copy from plugin `icons/` to
  `DataStorage:getDataDir()/icons/mahjong/`), plus `select.svg`/`hint.svg` transparent overlays
  (also portrait 100x140 so the highlight frames the face without intruding on neighbours).
   The depth bevel is an **outward extension**: the white face fills (nearly) the full 100x140
   canvas and medium/dark bevels (right `#78909c`, bottom `#546e7a`) hang OFF its east/south
   edges into the extension bands of a shared **110x154 viewBox** (bevels 10px wide / 14px tall),
   so a tile with visible bevels is slightly larger than a bare face. The 3D step is produced by
   the **board's per-layer up-left shift** (exactly one bevel thickness per layer), so a raised
   tile's bevels land exactly on the edges of the tile directly beneath it. The face
   also has a **thin gray outline** drawn inside the face box (~1 viewBox unit ≈ 1 device px,
   tone `#78909c`), so
   two adjacent same-layer tiles — which have no bevels between them — show a crisp ~1px grid
   line at
   their seam instead of an invisible white-on-white border. Bevels are only drawn
   on **exposed edges**: a same-layer neighbour to the right/below hides that bevel (no fake seam
   inside a solid layer); on the half grid an edge is also hidden when covered by TWO
   half-overlapping same-layer neighbours. Where BOTH bevels are exposed (base variant) the two
   side faces meet along a **diagonal line** from the face's bottom-right corner (100,140) to the
   widget corner (110,154) — the block's front-right edge from the bottom-right camera — so the
   corner reads as one receding point (the implied rectangular box) instead of a flat L; the
   upper-left triangle of the corner is the right face (medium), the lower-right is the base face
   (dark). Single-bevel variants keep plain rectangles. Icons are generated by `tools/gen_icons.py` (never
   hand-edited) and QA'd by `tools/check_icons.py`.
  IconWidget renders SVGs directly (alpha is inherent to the SVG), so no ButtonTable patch is
  needed.

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

- `mahjongboard.lua`: `Board` extends `InputContainer` (full-screen sized), paints one
  `IconWidget` per visible tile inside an `OverlapGroup` (children offset via `overlap_offset`).
- Geometry (`computeGeometry`): portrait tiles (`th = TILE_ASPECT * tw`, `TILE_ASPECT = 1.4`)
  sized to fit both axes (`tw = floor(min(usable_w/units_w, (usable_h/units_h)/ASPECT))`),
  centered with `origin_x/origin_y`. **Each layer is shifted up-left by exactly the bevel
  thickness** (`tilePos` subtracts `layer*bw`/`layer*bh`), so a raised tile's face is inset from
  the tile directly beneath it and its outward bevels land exactly on that underlying tile's
  face edges — the bevel is the visible step and never overlaps the tiles to its east/south.
  Each widget is sized `tile_w = tw + bw`,
  `tile_h = th + bh` with `BEVEL_FRAC = 0.10` (`bw = floor(tw*0.10+0.5)`, `bh = floor(th*0.10+0.5)`),
  the face is anchored at the widget's top-left, and the tile's outward depth bevels (right
  `#78909c`, bottom `#546e7a`) hang off its east/south edges. Earlier
  manual `LAYER_OFF_*` shifts (0.25/0.25, 0.2/0.14 up-and-right, 0.10/0.10 up-and-left) all
  produced skewed stacks or white face strips, and the first outward-bevel attempt (no layer
  offset, bevels overhanging the neighbours) overlapped the tiles to their east/south. `units_w/units_h` come from `LAYOUT_BOUNDS`,
  computed with `+1 + BEVEL_FRAC` on the east/south extents (bevel overhang) and
  `- layer*BEVEL_FRAC` on the west/north (the up-left shift).
  Tile SVGs are portrait 100x140 (matching the 1.4 aspect) in a shared 110x154 viewBox with the
  outward bevels, so tiles fill their box exactly (no white row gaps) and the stack reads as
  raised. Each tile's icon is resolved per-position via
  `MahjongLogic.iconForTile(board, x, y, layer)`, which hides the bottom/right bevel when a
  same-layer neighbour covers that edge (4 generated variants per face), including on the half
  grid where an edge covered by TWO half-overlapping same-layer neighbours is also hidden.
- Children are appended in `buildLayout()` order (bottom layer first) so lower tiles paint under
  upper ones; `OverlapGroup` gets a board-sized `dimen`.
- `updateBoard()` frees + rebuilds the tiles and calls `UIManager:setDirty`.
- Taps: `TapSelect` gesture on `self.dimen` → `hitTest` walks layers top-down and returns the
  topmost tile whose rect contains the point; forwarded as `(x, y, layer)` via `onTileTap`.
- `getSize()` returns `self.dimen` — the board is NOT a `FrameContainer` subclass, so the
  `_padding_*` override crash (`AGENTS.md` pitfall) cannot occur.
- Per-story harnesses live in `tests/` (see `tests/run.sh`): `us06_board.lua` (geometry,
  z-order, hit-test, taps, main wiring) and `us06_paint.lua` (paint-contract regression for
  the crash). New stories extend this suite.

**Acceptance:** Full board renders as 144 tiles in the Turtle silhouette (outward bevels readable
as a 3D stack); board fits the screen on the target resolution; no blank cells; icons legible;
tap on a tile reports the exact (x, y, layer).

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
- HUD top bar (`hudbar.lua`, replacing the original `TitleBarWidget` subtitle): the top of the
  screen is a full-width band with the title plus three stylized stat "chips" — Pairs remaining,
  Free pairs, Score — each a rounded pill with an icon, a bold value and a tiny label, pushed via
  `setStats()` after every move.
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

### US-12 — Win summary + best-score/best-time tracking

As a player, I want the win screen to tell me how I did and to see my personal bests, so there is a
reason to replay.

- Add a pure `mahjongstats.lua` module (no UI deps, `--`-style self-tests like
  `mahjonglogic.lua`). A lifetime stats record is a plain table:
  `games_played`, `games_won`, `best_score`, `best_time` (seconds of the fastest win; `nil` until
  the first win), `current_streak`, `longest_streak`.
  - `defaults()`, `startGame(stats, previous_won)` (bumps `games_played`; resets `current_streak`
    to 0 when the previous game was abandoned, i.e. not won), `recordWin(stats, score, elapsed,
    pairs)` (bumps `games_won`/`current_streak`, tracks `longest_streak`, best-score/best-time
    maxima/minima).
- `main.lua` holds `self.stats` and persists it under the `"stats"` `LuaSettings` key — separate
  from the `"game"` key, so a win or a restore never touches it. Flush on every update.
- Call sites: `startGame()` fresh deal → `startGame(stats, previous_won)`; on win →
  `recordWin`; New Game/reset → `startGame(stats, self.game_won)`; set a `self.game_won` flag in
  `showWinDialog()`.
- Replace the one-line win dialog text with a summary: score, elapsed time, pairs matched (72),
  best score, best time, current streak. Mark best-score/best-time lines with "New best!" the first
  time each record is set. Keep "Play again" / "Close" (Play again still calls `resetGame()` until
  US-14 reroutes it through the layout picker).
- Bests are computed from the real game (score + `getElapsed()`), so they are genuine records.
- **Auto-solve games never count toward stats (US-19 note):** a board cleared by the long-press
  Hint auto-solver is considered "cheated". The auto-solve win must NOT call `recordWin` or
  `startGame`'s previous-won logic — it records no win, no bests, no streak change, and does not
  bump `games_played`. Only the normal `showWinDialog()` path (a human play-through) records a
  win. Implementation touchpoints: the auto-solver reaches `showWinDialog()` too, so gate the
  stats recording on a `self.game_was_autosolved` flag that US-19's `startAutoSolve` sets and the
  normal win path never does (or route auto-solve wins through a dedicated win dialog path).

**Acceptance:**
- Self-tests: `startGame` bumps games_played and breaks a stale streak only when the previous game
  wasn't won; `recordWin` updates every field; best_time starts nil and only ever decreases;
  streak increments across consecutive wins and resets on an abandoned game.
- `tests/us12_stats.lua` (registered in `tests/run.sh`): stats survive a fresh plugin instance;
  the win dialog text contains score/time/pairs/bests and the "New best!" marker on a first
  record; Play again starts a new game; a mid-game New Game resets the streak.
- Manual: win → summary matches the game; a later win with a higher score updates best_score;
  abandoning resets the streak.

### US-13 — Stats screen (dedicated "Stats" button + floating card)

As a player, I want a dedicated stats screen so I can review my lifetime progress at a glance.

- Extend `hudbar.lua` to support **multiple left buttons**
  (`left_icons = { { icon=.., size_ratio=.., callback=.. }, ... }`) while keeping the existing
  `left_icon`/`right_icon` fields (the existing tests read
  `status_bar.left_icon_tap_callback`/`right_icon_tap_callback`). Add a "Stats" button next to the
  settings gear; the title stays centered in the remaining width.
- New widget `mahjongstats.lua` — a floating card in the exact `mahjongsettings.lua` pattern
  (transparent full-screen `InputContainer` → `CenterContainer` → white rounded `FrameContainer`;
  full-screen `TapClose` dismissing on a tap outside `_panel_geom`; the `onShow` panel-region
  refresh trick so the card appears immediately; rows with right-aligned labels and a
  uniform-width value column).
- Rows: Games played, Games won, Win rate, Best score, Best time, Average time per win, Current
  streak, Longest streak. A bottom "Reset" button (ConfirmBox first) clears the record back to
  `defaults()`.
- Timer: opening the dialog calls `stopTimer()`; closing resumes via `startTimer()`, exactly like
  `openSettings`.
- `main.lua`: `createStatusBar()` wires the Stats button; `openStats()` shows the dialog.

**Acceptance:**
- `tests/us13_stats.lua` (registered in `tests/run.sh`): the HUD exposes a stats button whose
  callback opens the dialog; the card lists the persisted lifetime stats; Reset zeroes them only
  after a confirm; tap-outside closes; the timer stops while open and resumes on close. Existing
  `hud_bar.lua` assertions still pass (compat fields preserved).
- Manual: open Stats mid-game → values match real play; Reset works; closing the card resumes the
  clock.

### US-14 — Layout registry + layout selection screen (architecture)

As a player, I want to choose which board shape to play on.

This story ships the **architecture only**: Turtle stays the only registered layout, but every
layout-dependent path is generalized and a picker exists, so a new layout becomes a one-file
addition (US-15/16).

- `mahjonglogic.lua` — layout registry:
  - `MahjongLogic.layouts` maps `id -> { id, name, spec }` (the Turtle spec moves in verbatim)
    with `registerLayout(spec)`, `layoutIds()`, `layoutName(id)`.
  - Generalize the layout-dependent functions to take a layout id (defaulting to `"turtle"` so
    existing behavior and self-tests are unchanged): `buildLayout(id)`, `gridBounds(id)`,
    `maxLayer(id)` (replaces the fixed `MAX_LAYER`), `isLayoutPosition(x, y, layer, id)`,
    `newGame(id, rng)`, `freeTiles(board, id)`. Each `_layout_cache` becomes per-id.
- `mahjongboard.lua` — per-layout geometry:
  - `Board` gains a `layout_id`; the module-level `LAYOUT_BOUNDS` block becomes `layoutBounds(id)`;
    `tilePos`/`computeGeometry`/`rebuildTiles`/`syncOverlapGroup`/`hitTest` use the board's layout
    and `maxLayer`. (Turtle renders identically.)
- Persistence:
  - `serializeGameState` adds a `layout` field; `deserializeGameState` bumps to v2 and validates
    the stored layout id (unknown id → corrupt → fresh game) and every board/history position
    against THAT layout's position set. Old v1 saves (no `layout` field) restore as Turtle.
- `main.lua` — selection flow:
  - `startGame()`: a **saved** game restores directly (as today); otherwise (first launch, New
    Game, or win "Play again") show the **layout selection screen**; the chosen layout deals the
    board.
  - `resetGame(layout_id)`/`newGame` take the layout; `self.layout` tracks the current one and is
    saved with the game state. The `"layout"` settings key stays as the last-chosen default.
  - The picker makes the New Game `ConfirmBox` redundant (choosing a layout IS the confirmation):
    stop consulting `confirm_new_game` (keep the key; drop it in a later cleanup).
- New `mahjonglayoutselect.lua` widget — a full-screen selection screen with a **2x3 grid** of
  cards (6 slots, enough for the current set; wrap in a scroll container if more are added later).
  Each card: a small **thumbnail** (a miniature schematic of the layout's positions — small rounded
  rects per tile, per-layer offset so the 3D shape reads) plus the layout **name** underneath.
  Tapping a card deals a game on that layout.
- Add a `layoutThumbnail(id, w, h)` helper (in the picker module) that builds the schematic from
  the layout positions so US-15/16 get their thumbnail for free.

**Acceptance:**
- Self-tests: passing a layout id returns byte-identical Turtle results; the registry enumerates
  exactly `{"turtle"}`.
- `tests/us14_layouts.lua` (registered in `tests/run.sh`): registering a throwaway layout at
  test-time works end-to-end (deal → free tiles → render via a board built with that layout →
  serialize/restore round-trip → an unknown saved layout id deals fresh); the picker appears on
  first launch / New Game / Play again; choosing Turtle deals a game; the thumbnail renders for
  every registered layout.
- Manual: fresh launch → picker shows the Turtle card (thumbnail + name); picking it deals; New
  Game returns to the picker.

### US-15 — Spider layout

As a player, I want a second board shape ("Spider") to vary the game.

- Add the classic Spider layout (144 positions) to the registry via `registerLayout`. The
  neighbour-based bevel-variant icon logic is layout-agnostic and needs no changes.
- It appears automatically as a second card (thumbnail + name) in the US-14 picker.
- Verify on the target resolutions: geometry fits the screen (Spider's grid extents may exceed the
  Turtle's 14x7 — exercise `layoutBounds`/`computeGeometry`), free-tile detection and gameplay
  work, persistence round-trips with `layout="spider"`.
- `tests/us15_spider.lua` (registered in `tests/run.sh`): 144 unique positions, per-layer counts
  match the spec, deal/free-tiles/hasMoves work, save/restore with the layout id, the picker lists
  two entries.

**Acceptance:** Manual — pick Spider, play a full game, save/restore mid-game on the Spider board.

### US-16 — Bridge layout

Same template as US-15 for the classic Bridge layout (144 positions). Register it, thumbnail
automatic, geometry/free-tile/persistence verified, `tests/us16_bridge.lua` (registered in
`tests/run.sh`).

**Acceptance:** Manual — pick Bridge, play, restore mid-game.

### US-17 — Pause

As a player, I want to pause the game so the clock stops and stray taps can't move tiles.

- Add a Pause button (extend the HUD's `left_icons` list).
- Tap → `stopTimer()` (freezes `elapsed_base`), then show a modal overlay: a full-screen
  transparent `InputContainer` with a centered "Paused" card (the settings/stats floating-card
  pattern) and a **Resume** button. The overlay consumes all taps, so no tile can be selected
  while paused.
- Resume → close the overlay + `startTimer()`.
- Closing the plugin while paused still saves the game (`onCloseWidget` calls `saveGameState`;
  ensure `stopTimer` runs once — reuse the existing timer helpers).
- `tests/us17_pause.lua` (registered in `tests/run.sh`): pause freezes elapsed (two `getElapsed()`
  reads are stable), the overlay sits on the window stack and blocks board taps, resume restarts
  the clock, pause-then-close saves.

**Acceptance:** Manual — pause mid-game, elapsed freezes, taps do nothing, resume continues.

### US-18 — Hint/shuffle score penalties

As a player, I want hints and shuffles to cost points, so using them is a real trade-off.

- `mahjonglogic.lua`: add `HINT_PENALTY` (5) and `SHUFFLE_PENALTY` (10) constants and a pure
  `applyPenalty(score, amount)` that floors at 0 (score can't go negative).
- `main.lua`:
  - `showHint()` deducts `HINT_PENALTY` when a hint is actually shown (the dead-board shuffle offer
    is not a hint and does not penalize).
  - `shuffleBoard()` deducts `SHUFFLE_PENALTY` once per **user-initiated** shuffle; the bounded
    auto-repeat re-shuffles that guarantee a playable board do NOT re-charge.
  - Penalties apply at use time and persist via the existing score save; they are NOT part of the
    pair history, so `undo()` restores only the pair's points (never a penalty).
- Track per-game counters `hints_used` / `shuffles_used` (persisted in the game state) that feed
  the US-12/13 stats.
- `tests/us18_penalties.lua` (registered in `tests/run.sh`): constants + floor at 0; a hint
  deducts once per real hint; a shuffle deducts once (not per auto-repeat); undo doesn't restore
  penalties; the counters increment and survive a save/restore.

**Acceptance:** Manual — use a hint and shuffle, watch the Score chip drop; the win summary
reflects the net score.

### US-19 — Long-press Hint to auto-solve the board

As a player, I want to watch the machine clear the board when I'm stuck, by holding the Hint
button for ~10 seconds, so the game finishes itself.

- KOReader's `Button` already supports long-press via `hold_callback` (the `hold` gesture fires
  ~`ges_hold_interval_ms`, ~0.5 s, after contact), but the ~10 s requirement cannot be expressed
  in the gesture system (that interval is device-global). Instead:
  - `main.lua` adds a `LongPressButton = ButtonWidget:extend{}` that surfaces the normally-hidden
    `hold_release` event (`onHoldReleaseSelectButton` override → `hold_release_callback`).
  - The Hint button's `hold_callback` (`armAutoSolve`) shows a persistent "Keep holding to
    auto-solve…" band message and arms a `UIManager:scheduleIn(AUTO_SOLVE_HOLD_SECONDS=10, ...)`;
    `hold_release_callback` (`disarmAutoSolve`) cancels the arm if the finger lifts first.
  - `startAutoSolve` runs a solver (`autoSolveStep`) that reuses the exact tap-path code — a new
    `applyMatch(a, b)` helper extracted from `handleTileTap` (scoring, chain bonus, history,
    HUD + mm:ss refresh, save) — removing one matching free pair per `AUTO_SOLVE_STEP_SECONDS`
    (0.55 s) step until the board is empty, then shows the normal win dialog. A dead board
    mid-solve shuffles (bounded retries) and continues. History is cleared at solve start and
    before a mid-solve shuffle so undo can't restore tiles to positions that moved under a
    shuffle.
  - Any board tap, a short Hint tap, Undo, New Game, or close stops the solver (token-bumped
    pending steps become no-ops). The `hints` setting gates the arm like it gates `showHint`.
  - Flash refactor: `setFlash` (persistent, used by the solver) split out of `flashMessage`
    (auto-clearing); `clearFlash` bumps the sequence token instead of niling it, fixing a latent
    `nil + 1` crash on a second flash after a cleared band.
- `tests/us19_autosolve.lua` (registered in `tests/run.sh`): arm/10 s-cancel, full board clear +
  win dialog + history/score, board-tap/short-tap/undo stop the solve (pending step no-ops),
  hints-off arms nothing, second-flash-after-clear regression.

**Acceptance:** Manual — hold Hint for ~10 s; the band says "Auto-solving…" and the board clears
one pair at a time; tapping the board interrupts; a held-then-quickly-released press does
nothing.

## Deferred optimizations (P3 — marked for later)

Reviewed during the P1/P2 optimization pass (US-01..06 shipped). These were
**not** worth doing before gameplay landed (US-07..09), but are recorded here so
they are not lost. Revisited after US-10/11 — see status below.

1. **`freeTiles()` string-key round trip.** ~~`freeTiles` iterates `pairs(board)`
   and re-parses every key with `key:match("^(%d+),(%d+),(%d+)$")` + 3×
   `tonumber`~~ — **DONE (post-US-11 cleanup):** `freeTiles` now iterates the
   (memoized) `buildLayout()` instead of `pairs(board)`, doing a posKey lookup
   per position, which replaces the per-key regex parse (roughly 5-6× faster)
   and also makes the returned order deterministic (layout order, bottom layer
   first). The board's storage is unchanged (flat `posKey → kind` table — that
   is what makes US-10 persistence a plain table).
2. **Dead code** — **DONE (US-11 cleanup pass):**
   - `MahjongLogic.topTileAt` (`mahjonglogic.lua`) plus its self-tests — a
     leftover from the flat-projection renderer; the 3D turtle board hit-tests
     via `Board:hitTest` and never calls it. Removed.
   - `MahjongLogic.isSpecial`/`isFlower`/`isSeason` — unused; removed.
   - `MahjongLogic.MULTIPLICITY` export — only used internally by `createDeck`;
     the export was dropped (the local table stays).
3. **Explicitly not worth it:** coroutines/timers (no AI engine), `hasMoves`
   O(n²) (free-tile count ≤ 144), micro-optimizing `posKey` string
   concatenation, or replacing the string-keyed board with nested tables.

---

## Later / optional enhancements (not in the current scope)

- Half-tile-offset rendering for a true "stacked" look.
- Additional layouts beyond Spider/Bridge (the registry + picker make this a data-only addition).
- Keyboard/d-pad navigation for non-touch Kindles.
- Dark/night-mode theme (KOReader night mode inverts the framebuffer; a proper dark theme needs
  dark tile SVGs + a theme setting).
- Keep the device awake during play (inhibit KOReader auto-suspend while the game is open).
- Localization catalogs.
- Cleanup: drop the now-redundant `confirm_new_game` setting once US-14's picker is in.
