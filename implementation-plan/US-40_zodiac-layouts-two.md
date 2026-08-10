# US-40 - Zodiac layouts II (Dog, Snake, Boar, Ox, Wedges and Hourglass)

As a player, I want the second picker page to be filled with another six
compact, layered layouts, so the 24-layout collection has two complete pages
instead of a partially empty second page.

## Source and selection

These are additional 144-tile, multi-layer definitions from **PySolFC** at
screened GPL-3.0-or-later revision `afc03254518984f2950c2a5ff26079124dd89da6`:

- `Dog`, `Snake`, `Boar`, `Ox` and `Wedges` are in
  `pysollib/games/mahjongg/mahjongg3.py`.
- `Hourglass` is in `pysollib/games/mahjongg/mahjonggL.py`.
- Repository: `https://github.com/shlomif/PySolFC`

| id | display name | per-layer counts | grid bounds |
|---|---|---:|---|
| `dog` | Dog | 62 / 47 / 29 / 6 | x=0..14, y=0..7 |
| `snake` | Snake | 60 / 58 / 21 / 5 | x=0..14, y=0..7 |
| `boar` | Boar | 65 / 43 / 28 / 8 | x=0..14, y=0..7 |
| `ox` | Ox | 73 / 44 / 21 / 6 | x=0..13, y=0..7 |
| `wedges` | Wedges | 60 / 39 / 26 / 13 / 5 / 1 | x=0..12, y=0..7 |
| `hourglass` | Hourglass | 74 / 40 / 12 / 10 / 8 | x=0..12, y=0..7 |

The first four complete the usable compact subset of PySolFC's zodiac boards.
Wedges and Hourglass are included because they are visually distinct deep
stacks that remain inside the current board canvas. All twelve planned PySolFC
maps are non-flat and 144 tiles; no deck-size adaptation is needed.

## Prerequisite

US-38 and US-39 are complete. This story takes 18 built-ins to exactly 24, so
the selector's two 3x4 pages are both full.

## Implementation

In `mahjong.koplugin/mahjonglayouts.lua`, transcribe the six exact PySolFC
definitions to native specs, register them and add `checkShape` assertions
using the table above. Use the same coordinate conversion and no-runtime-
decoder rule as US-39. Preserve half-grid coordinates where they occur.

Add English/German `layout.<id>` strings; update the registry documentation;
and add `tests/us40_zodiac_two.lua` to `tests/run.sh`. The harness covers the
same pure-logic, persistence, board-widget and picker-page checks as US-39.

The final expected sorted registry order is:

```
boar, bridge, cloud, confounding, crab, dog, hare, horse, hourglass, monkey,
overpass, ox, pyramid, ram, red-dragon, rooster, snake, spider, taipei,
tictactoe, tiger, turtle, wedges, ziggurat
```

Assert page one contains the first twelve ids and page two contains the final
twelve ids in that order. Both pages must expose 12 card rects and no empty
slot; the final page indicator is `2/2` with its right arrow disabled.

## Verification

- `lua mahjong.koplugin/mahjonglayouts.lua`
- `tests/run.sh`
- Device/emulator: confirm all 24 cards render across two non-scrolling pages;
  inspect and play each of the six new maps, including a save/restore smoke
  test and a board-edge clipping check.

## Out of scope

- No third picker page, deck-size variants, new tile assets or rules changes.
- No changes to scores, stats, save format or board projection; the existing
  layout-id plumbing supplies those behaviors.
