# US-25 — Red Dragon layout

As a player, I want the "Red Dragon" board shape to vary the game.

- Add the Red Dragon layout (144 positions) to the registry via `registerLayout`,
  transcribed from GNOME Mahjongg's `dragon` map. Two curved "horn" towers connected by a
  central spine, with fractional x coordinates on the half-grid. Per-layer counts:
  82/45/17 across 3 layers; grid extents x=0..14, y=0..6.5.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us25_red_dragon.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Red Dragon, play, restore mid-game. (Planned.)
