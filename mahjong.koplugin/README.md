# Mahjong Solitaire for KOReader

A native Mahjong Solitaire (Shanghai) plugin for KOReader, optimized for e-ink devices.

## Features

- **24 layouts:** Turtle, Spider, Bridge, Ziggurat, Cloud, Tic-Tac-Toe, Red
  Dragon, Overpass, Pyramid's Walls, Confounding Cross, Taipei, Crab, Hare,
  Horse, Tiger, Ram, Monkey, Rooster, Dog, Snake, Boar, Ox, Wedges, and
  Hourglass. The first twelve are GNOME Mahjongg maps and the twelve compact
  multi-layer layouts are from PySolFC. A full-screen paged layout
  picker lets you choose one to start a game. Picker cards
  show a thumbnail schematic, a win-count trophy badge, and a best-score chip
  per layout.
- **3D Board:** Renders the 144-tile stack as an outward-bevel 3D structure
  with portrait tiles and per-layer up-left offsets; bevels step cleanly onto
  the tiles beneath.
- **E-ink Optimized:** High-contrast tile symbols and crisp bevels designed for grayscale screens. Incremental tile refreshes stay within the board canvas, and terminal dialogs wait for the final tile repaint to settle so they cannot leave stale board pixels behind.
- **Adaptive Sizing:** Automatically fits the board to your device's screen resolution.
- **Core Gameplay:** Tap matching free tiles to remove them. Flowers match any flower, and seasons match any season.
- **Scoring:** 10 points per pair, +5 chain bonus for consecutive same-group matches, and escalating fast-clear combos (+10, then +15, then +20 within 5 seconds); hint and shuffle cost score penalties.
- **Undo / Hint / Shuffle:** Undo restores a pair (and its score), a hint highlights a matching free pair, and dead boards offer a confirm-gated reshuffle. No-moves recovery evaluates 15 candidate shuffles in the background and keeps the one with the most available matching free pairs, with bounded auto-repeat if all candidates remain stuck.
- **Auto-solve:** Long-press the Hint button to let the solver clear the board automatically.
- **Failure recognition:** Provably-dead boards (e.g. two identical tiles stacked) trigger a loss dialog instead of an endless shuffle loop.
- **Pause:** Freeze the game clock behind a tap-consuming overlay.
- **Persistence:** Game state and settings are saved and restored on relaunch; lifetime stats (wins, times) survive across sessions.
- **Selection behavior:** The Settings dialog controls whether tapping empty
  board space clears the selected tile. `Deselect on empty` is enabled by
  default; disabling it preserves the selection until it is matched or
  replaced by another viable tile.
- **Win summary + stats:** A win dialog and a lifetime-stats screen, with a confirm-gated reset.
- **Localization:** English and German are available in Mahjong's Settings.
  On first launch, German KOReader locales select German automatically; English
  is the fallback for English and all other KOReader locales.

## Installation

1. Copy the `mahjong.koplugin` directory into your KOReader `plugins/` folder on your device.
2. Fully restart KOReader.
3. Launch the game from the menu: **Tools → Mahjong Solitaire**.

## Rules

- A tile is **free** if it has no tile on top of it AND has at least one of its left or right sides open.
- Match two identical tiles to remove them.
- **Special Tiles:**
    - Any **Flower** matches any other Flower.
    - Any **Season** matches any other Season.
- The goal is to clear the entire board.

## Scoring

- **Base Score:** 10 points per matched pair.
- **Chain Bonus:** +5 when consecutive matches are of the same tile group.
- **Penalties:** 5 per hint session, 10 per manual shuffle (floor at 0, not refunded by undo).

## License

GNU GPLv3 (or later).
