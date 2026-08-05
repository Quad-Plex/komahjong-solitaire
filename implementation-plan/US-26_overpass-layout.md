# US-26 — Overpass layout

As a player, I want the "Overpass" board shape to vary the game.

- Add the Overpass layout (144 positions) to the registry via `registerLayout`,
  transcribed from GNOME Mahjongg's `overpass` map. Twin towers linked by deck layers that
  cross over/under each other. Per-layer counts: 52/20/16/32/24 across 5 layers; grid
  extents x=0..11, y=0..8.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us26_overpass.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Overpass, play, restore mid-game. (Planned.)
