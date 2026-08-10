# US-49 - Zodiac layouts I (Hare through Rooster)

As a player, I want six additional compact animal-shaped layouts, so the
second page of the layout picker has a varied, recognizable first half.

## Source and selection

The GNOME Mahjongg map set is already fully represented and is explicitly out
of scope. These layouts come from **PySolFC**, which ships its Mahjongg layout
definitions under GPL-3.0-or-later:

- Repository: `https://github.com/shlomif/PySolFC`
- Source file: `pysollib/games/mahjongg/mahjongg3.py`
- Definitions: `Hare`, `Horse`, `Tiger`, `Ram`, `Monkey`, `Rooster`
- Screened source revision: `afc03254518984f2950c2a5ff26079124dd89da6`

PySolFC's compact encoded definitions decode to integer half-tile coordinates;
divide x/y by 2 to obtain this plugin's tile units. All six have exactly 144
positions, fit the established board envelope and have multiple layers:

| id | display name | per-layer counts | grid bounds |
|---|---|---:|---|
| `hare` | Hare | 59 / 44 / 26 / 11 / 4 | x=0..14, y=0..7 |
| `horse` | Horse | 62 / 49 / 27 / 6 | x=0..14, y=0..7 |
| `tiger` | Tiger | 62 / 58 / 18 / 6 | x=0..14, y=0..7 |
| `ram` | Ram | 69 / 52 / 20 / 3 | x=0..14, y=0..7 |
| `monkey` | Monkey | 60 / 44 / 23 / 15 / 2 | x=0..14, y=0..7 |
| `rooster` | Rooster | 66 / 44 / 26 / 7 / 1 | x=0..14, y=0..7 |

They are deliberately selected over PySolFC's many flat 144-tile layouts:
their silhouettes read in the current 2.5D thumbnail, exercise the existing
layer-aware free-tile rules, and do not duplicate a current layout name or
shape.

## Prerequisite

US-48 is complete. Adding these six maps raises the built-in total from 12 to
18, which starts page two without changing the fixed page-one grid.

## Implementation

All board data changes are in `mahjong.koplugin/mahjonglayouts.lua`:

1. Transcribe each named PySolFC definition into one native `*_SPEC` using the
   existing `block`, `row`, `column`, `tile` and/or `set` vocabulary. Do not add
   a runtime Python/PySolFC decoder or ship copied upstream files. Preserve
   every decoded coordinate exactly, including half-grid positions.
2. Register the six entries with ids and display names from the table.
3. Add one `checkShape` assertion per id with the exact counts and bounds from
   the table. The self-test must prove 144 unique positions for every layout.
4. Add `layout.<id>` English and German strings in `mahjongi18n.lua` (animal
   names may remain the conventional English names in German if no clear local
   product translation is chosen, but both tables must contain the keys).
5. Add `tests/us39_zodiac_one.lua`, registered in `tests/run.sh`. Mirror the
   existing individual-layout harnesses: registry/name/max layer/bounds,
   144 unique positions, a solvable nil-rng deal, save/restore, board widget
   construction and pair removal. Assert that all six cards are on picker page
   two after US-48, not page one.

Update registry-order assertions and README/AGENTS documentation mechanically.
With the other planned maps absent, sorted ids are:

```
bridge, cloud, confounding, crab, hare, horse, monkey, overpass, pyramid,
ram, red-dragon, rooster, spider, taipei, tictactoe, tiger, turtle, ziggurat
```

## Verification

- `lua mahjong.koplugin/mahjonglayouts.lua`
- `tests/run.sh`
- Device/emulator: inspect all six thumbnails, start and save/restore each at
  least once, and confirm the boards fit with no clipped tiles.
