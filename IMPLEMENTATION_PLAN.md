# Implementation Plan — Mahjong Solitaire for Kindle (KOReader Plugin)

## Goal

Build a native KOReader plugin that plays **Mahjong Solitaire** (tile-matching, aka "Shanghai")
on jailbroken e-ink Kindles. The player clears a 144-tile board by tapping matching tiles that
are "free" (not blocked from above and with at least one open side).

Everything is driven by an AI agent working through the **User Stories**, one per prompt.
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
    into `DataStorage:getDataDir()/icons/mahjong/`. Incremental board updates use clipped,
    screen-space `ui` refresh regions per connected local cluster: the anti-aliasing margin
    must remain within the board canvas so it cannot merge with adjacent chrome. A structural
    final-pair update settles its local retry before the full-screen win summary is shown;
    delayed modal callbacks are board-identity guarded and invalidated on replacement or close.
9. **Persistence:** `LuaSettings` in the KOReader settings dir; game state (tile deck, removed
   pairs, score) serialized to a table, saved on close, restored on start. Also persist a small
   settings table (hints on/off, new-game confirmation, etc.).
10. **No heavy background work needed** (no engine/AI) — the only timers are cosmetic (elapsed
    time). Coroutines are unnecessary; keep the UI loop simple.

## Repo layout (target)

```
kindle_majong/
├── AGENTS.md                     # this repo's plugin-writing guide (already written)
├── IMPLEMENTATION_PLAN.md        # this file — the overview (design + story index)
├── implementation-plan/          # one file per user story (US-01..40, US-22a)
│   ├── US-01_plugin-skeleton_completed.md
│   ├── US-02_game-shell_completed.md
│   ├── US-03_tile-deck_completed.md
│   ├── US-04_turtle-layout_completed.md
│   ├── US-05_free-tiles_completed.md
│   ├── US-06_board-render_completed.md
│   ├── US-07_gameplay_completed.md
│   ├── US-08_undo-hint-shuffle_completed.md
│   ├── US-09_score_completed.md
│   ├── US-10_persistence_completed.md
│   ├── US-11_polish_completed.md
│   ├── US-12_win-summary_completed.md
│   ├── US-13_stats-screen_completed.md
│   ├── US-14_layout-registry_completed.md
│   ├── US-15_spider-layout_completed.md
│   ├── US-16_bridge-layout_completed.md
│   ├── US-17_pause_completed.md
│   ├── US-18_penalties_completed.md
│   ├── US-19_autosolve_completed.md
│   ├── US-20_hint-session-and-pause-button_completed.md
│   ├── US-21_layout-picker-expansion_completed.md
│   ├── US-22_ziggurat-layout_completed.md
│   ├── US-22a_layouts-module_completed.md
│   ├── US-23_cloud-layout_completed.md
│   ├── US-24_tictactoe-layout_completed.md
│   ├── US-25_red-dragon-layout_completed.md
│   ├── US-26_overpass-layout_completed.md
│   ├── US-27_pyramid-walls-layout_completed.md
│   ├── US-28_confounding-cross-layout_completed.md
│   ├── US-29_taipei-layout_completed.md
│   ├── US-30_picker-polish_completed.md
│   ├── US-31_layout-highscore_completed.md
│   ├── US-32_failure-recognition_completed.md
│   ├── US-33_autosolve-lock_completed.md
│   ├── US-38_paged-layout-picker.md
│   ├── US-39_zodiac-layouts-one.md
│   └── US-40_zodiac-layouts-two.md
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
│   ├── us12_stats.lua            # win summary + lifetime stats
│   ├── us13_stats.lua            # stats button + floating stats card
│   ├── us14_layouts.lua          # layout registry + picker (US-14)
│   ├── us15_spider.lua           # Spider layout (US-15)
│   ├── us16_bridge.lua           # Bridge layout (shipped)
│   ├── us17_pause.lua            # pause overlay
│   ├── us18_penalties.lua        # hint/shuffle score penalties
│   ├── us19_autosolve.lua        # long-press Hint auto-solver (US-19)
│   ├── us21_picker.lua           # dynamic 3-col picker grid + scroll (US-21)
│   ├── us22_ziggurat.lua         # Ziggurat layout (US-22)
│   ├── us23_cloud.lua            # Cloud layout (US-23)
│   ├── us24_tictactoe.lua        # Tic-Tac-Toe layout (US-24)
│   ├── us25_red_dragon.lua       # Red Dragon layout (US-25)
│   ├── us26_overpass.lua         # Overpass layout (US-26)
│   ├── us27_pyramid.lua          # Pyramid's Walls layout (US-27)
│   ├── us28_confounding.lua      # Confounding Cross layout (US-28)
│   ├── us29_taipei.lua           # Taipei layout (US-29)
│   ├── us30_picker_wins.lua      # picker polish: badges, tap feedback (US-30)
│   ├── us31_layout_score.lua     # per-layout highscore chip (US-31)
│   ├── us32_deadlock.lua         # failure recognition / loss dialog (US-32)
│   └── us33_autosolve_lock.lua   # uninterruptible auto-solve (US-33)
└── mahjong.koplugin/             # the deliverable
    ├── _meta.lua
    ├── main.lua                  # plugin class: menu, dispatch, full-screen shell
    ├── mahjonglogic.lua          # pure logic: deck, free-tiles, match, win, shuffle, scoring,
    │                             #   persistence; re-exports the layout API (US-22a)
    ├── mahjonglayouts.lua        # pure layout module (US-22a): board specs + registry +
    │                             #   geometry; a new board is one change here
    ├── mahjongstats.lua          # pure lifetime stats (US-12)
    ├── mahjongboard.lua          # offset-layer 3D board widget (IconWidget/OverlapGroup + hit-test)
    ├── hudbar.lua                # 2-row top bar: buttons, title, stat chips, quit X
    ├── mahjongsettings.lua       # floating settings dialog
    ├── mahjongstatswidget.lua    # floating stats screen (US-13)
    ├── mahjongpause.lua          # pause overlay (US-17)
    ├── mahjonglayoutselect.lua   # full-screen layout picker (US-14)
    ├── icons/*.svg               # tile + overlay icons
    └── README.md                 # install/usage
```

## User stories

Each story has its own file under `implementation-plan/`. A `_completed` suffix in the
filename marks a shipped story; files without it are planned. Completed: **US-01..US-33, US-22a, US-37**.

| Story | File | Status |
|---|---|---|
| US-01 — Plugin skeleton loads and shows a placeholder screen | [US-01_plugin-skeleton_completed.md](implementation-plan/US-01_plugin-skeleton_completed.md) | ✅ completed |
| US-02 — Full-screen game shell with title bar and New Game/Exit | [US-02_game-shell_completed.md](implementation-plan/US-02_game-shell_completed.md) | ✅ completed |
| US-03 — Tile deck: 144-tile definition + SVG assets | [US-03_tile-deck_completed.md](implementation-plan/US-03_tile-deck_completed.md) | ✅ completed |
| US-04 — Turtle layout + shuffled tile placement | [US-04_turtle-layout_completed.md](implementation-plan/US-04_turtle-layout_completed.md) | ✅ completed |
| US-05 — Free-tile detection (core rules) | [US-05_free-tiles_completed.md](implementation-plan/US-05_free-tiles_completed.md) | ✅ completed |
| US-06 — Render the board on screen (first playable visuals) | [US-06_board-render_completed.md](implementation-plan/US-06_board-render_completed.md) | ✅ completed |
| US-07 — Core gameplay: select, match, remove, win | [US-07_gameplay_completed.md](implementation-plan/US-07_gameplay_completed.md) | ✅ completed |
| US-08 — Undo, hint, and shuffle | [US-08_undo-hint-shuffle_completed.md](implementation-plan/US-08_undo-hint-shuffle_completed.md) | ✅ completed |
| US-09 — Score, pair counter, and status feedback | [US-09_score_completed.md](implementation-plan/US-09_score_completed.md) | ✅ completed |
| US-10 — Persistence: save/restore game + settings | [US-10_persistence_completed.md](implementation-plan/US-10_persistence_completed.md) | ✅ completed |
| US-11 — Polish and cross-device refinement | [US-11_polish_completed.md](implementation-plan/US-11_polish_completed.md) | ✅ completed |
| US-12 — Win summary + best-score/best-time tracking | [US-12_win-summary_completed.md](implementation-plan/US-12_win-summary_completed.md) | ✅ completed |
| US-13 — Stats screen (dedicated "Stats" button + floating card) | [US-13_stats-screen_completed.md](implementation-plan/US-13_stats-screen_completed.md) | ✅ completed |
| US-14 — Layout registry + layout selection screen (architecture) | [US-14_layout-registry_completed.md](implementation-plan/US-14_layout-registry_completed.md) | ✅ completed |
| US-15 — Spider layout | [US-15_spider-layout_completed.md](implementation-plan/US-15_spider-layout_completed.md) | ✅ completed |
| US-16 — Bridge layout | [US-16_bridge-layout_completed.md](implementation-plan/US-16_bridge-layout_completed.md) | ✅ completed |
| US-17 — Pause | [US-17_pause_completed.md](implementation-plan/US-17_pause_completed.md) | ✅ completed |
| US-18 — Hint/shuffle score penalties | [US-18_penalties_completed.md](implementation-plan/US-18_penalties_completed.md) | ✅ completed |
| US-19 — Long-press Hint to auto-solve the board | [US-19_autosolve_completed.md](implementation-plan/US-19_autosolve_completed.md) | ✅ completed |
| US-20 — Hint penalty per session + Pause in the bottom toolbar | [US-20_hint-session-and-pause-button_completed.md](implementation-plan/US-20_hint-session-and-pause-button_completed.md) | ✅ completed |
| US-21 — Expand the layout picker grid to hold the full board set | [US-21_layout-picker-expansion_completed.md](implementation-plan/US-21_layout-picker-expansion_completed.md) | ✅ completed |
| US-22 — Ziggurat layout | [US-22_ziggurat-layout_completed.md](implementation-plan/US-22_ziggurat-layout_completed.md) | ✅ completed |
| US-22a — Extract board definitions into `mahjonglayouts.lua` | [US-22a_layouts-module_completed.md](implementation-plan/US-22a_layouts-module_completed.md) | ✅ completed |
| US-23 — Cloud layout | [US-23_cloud-layout_completed.md](implementation-plan/US-23_cloud-layout_completed.md) | ✅ completed |
| US-24 — Tic-Tac-Toe layout | [US-24_tictactoe-layout_completed.md](implementation-plan/US-24_tictactoe-layout_completed.md) | ✅ completed |
| US-25 — Red Dragon layout | [US-25_red-dragon-layout_completed.md](implementation-plan/US-25_red-dragon-layout_completed.md) | ✅ completed |
| US-26 — Overpass layout | [US-26_overpass-layout_completed.md](implementation-plan/US-26_overpass-layout_completed.md) | ✅ completed |
| US-27 — Pyramid's Walls layout | [US-27_pyramid-walls-layout_completed.md](implementation-plan/US-27_pyramid-walls-layout_completed.md) | ✅ completed |
| US-28 — Confounding Cross layout | [US-28_confounding-cross-layout_completed.md](implementation-plan/US-28_confounding-cross-layout_completed.md) | ✅ completed |
| US-29 — Taipei layout | [US-29_taipei-layout_completed.md](implementation-plan/US-29_taipei-layout_completed.md) | ✅ completed |
| US-30 — Layout picker polish + bevel corner fix | [US-30_picker-polish_completed.md](implementation-plan/US-30_picker-polish_completed.md) | ✅ completed |
| US-31 — Per-layout highscore chip on the layout picker | [US-31_layout-highscore_completed.md](implementation-plan/US-31_layout-highscore_completed.md) | ✅ completed |
| US-32 — Failure recognition (deadlock detection) | [US-32_failure-recognition_completed.md](implementation-plan/US-32_failure-recognition_completed.md) | ✅ completed |
| US-33 — Uninterruptible auto-solve (input lock + tainted save + resume-on-reload) | [US-33_autosolve-lock_completed.md](implementation-plan/US-33_autosolve-lock_completed.md) | ✅ completed |
| US-37 — English/German localization with runtime language selection | [US-37_localization_completed.md](implementation-plan/US-37_localization_completed.md) | ✅ completed |
| US-38 — Paged layout picker (two fixed 3×4 pages) | [US-38_paged-layout-picker.md](implementation-plan/US-38_paged-layout-picker.md) | planned |
| US-39 — Zodiac layouts I (Hare through Rooster) | [US-39_zodiac-layouts-one.md](implementation-plan/US-39_zodiac-layouts-one.md) | planned |
| US-40 — Zodiac layouts II (Dog, Snake, Boar, Ox, Wedges and Hourglass) | [US-40_zodiac-layouts-two.md](implementation-plan/US-40_zodiac-layouts-two.md) | planned |

The US-21..US-29 stories added the full GNOME Mahjongg layout set once the registry + picker
(US-14) and two extra layouts (Spider, Bridge) had shipped. A full git checkout of the GNOME
Mahjongg sources lives at `/tmp/gnome-mahjongg` (`data/maps/mahjongg.map`); every board is
transcribed from that map and verified to have exactly 144 positions (the deck size).
US-21 (picker grid expansion) was the prerequisite for US-22..US-29 — the picker's fixed 2×3
(6-slot) grid held only 6 cards and had to grow before all 11 layouts fit. **US-22a** (extract
the board definitions out of `mahjonglogic.lua` into a dedicated `mahjonglayouts.lua` module)
was the **prerequisite for US-23..US-29**: it shipped before any further board story so that
each later board was a single-file addition to `mahjonglayouts.lua`. When a planned story
ships, rename its file to add the `_completed` suffix (and re-run the story index/status
table above). The stories must be read in order — later stories assume the earlier ones'
contracts.

US-38 replaces US-21's scrollable picker with a fixed, Help-style paged picker before further
maps are added. US-39 and US-40 use compact, multi-layer, 144-tile layouts from PySolFC rather
than revisiting the already-exhausted GNOME source. Together they expand the built-in collection
from 12 to 24: the existing maps remain page one, while the twelve PySolFC maps fill page two.

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
- Keyboard/d-pad navigation for non-touch Kindles.
- Dark/night-mode theme (KOReader night mode inverts the framebuffer; a proper dark theme needs
  dark tile SVGs + a theme setting).
- Keep the device awake during play (inhibit KOReader auto-suspend while the game is open).
- Additional languages beyond English and German.

## Retrospectives (post-completion notes)

### US-14 retrospective — `confirm_new_game` retired
The layout picker (US-14) made the New Game `ConfirmBox` redundant — choosing a layout
is the confirmation. The original plan kept the `confirm_new_game` setting key around
and just stopped consulting it on the New-Game path, deferring a small cleanup. After
shipping, that cleanup landed too: the setting default, its settings-dialog toggle row,
and all test references to it were removed (the `tests/us10_persistence.lua` dialog
section was rewritten to exercise toggle/Cancel/Reset via `hints` and `score_method`
instead). `confirm_new_game` no longer exists anywhere in code, config, or tests.

---

## Reference / external sources

The built-in layout specs (all 11: Turtle, Spider, Bridge, Ziggurat, Cloud, Tic-Tac-Toe,
Red Dragon, Overpass, Pyramid's Walls, Confounding Cross, Taipei) are transcribed from the
upstream GNOME Mahjongg layout maps so the boards are byte-identical to the canonical game.
A full git checkout of the GNOME Mahjongg sources is available on the dev machine at
`/tmp/gnome-mahjongg` (map data lives at `/tmp/gnome-mahjongg/data/maps/mahjongg.map`).
Use it to verify tile counts, grid extents, and per-layer breakdowns when adding or
fixing a layout spec.
