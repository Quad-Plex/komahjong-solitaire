# Mahjong Solitaire for KOReader

A native Mahjong Solitaire (Shanghai) plugin for KOReader, optimized for e-ink devices.

## Features

- **3D Turtle Layout:** Renders the classic 144-tile pyramid using an outward-bevel 3D stack.
- **E-ink Optimized:** High-contrast tile symbols and crisp grid lines designed for grayscale screens.
- **Adaptive Sizing:** Automatically fits the board to your device's screen resolution.
- **Core Gameplay:** Tap matching free tiles to remove them. Flowers match any flower, and seasons match any season.
- **Automatic Shuffle:** Reshuffles remaining tiles if no moves are left.

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

## License

GNU GPLv3 (or later).
