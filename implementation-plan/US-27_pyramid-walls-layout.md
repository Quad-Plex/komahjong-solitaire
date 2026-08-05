# US-27 — Pyramid's Walls layout

As a player, I want the "Pyramid's Walls" board shape (the deepest layout) to vary the game.

- Add the Pyramid's Walls layout (144 positions) to the registry via `registerLayout`,
  transcribed from GNOME Mahjongg's `pyramid` map. Concentric square rings stepping up to a
  single peak tile — the deepest board at 7 layers. Per-layer counts:
  41/34/27/20/13/6/3 across 7 layers; grid extents x=0..11, y=0..6.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us27_pyramid.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Pyramid's Walls, play, restore mid-game. (Planned.)
