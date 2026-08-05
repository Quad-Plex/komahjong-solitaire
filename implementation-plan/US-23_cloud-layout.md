# US-23 — Cloud layout

As a player, I want the "Cloud" board shape to vary the game.

- Add the Cloud layout (144 positions) to the registry via `registerLayout`, transcribed
  from GNOME Mahjongg's `cloud` map. The bevel-variant logic (US-14) is layout-agnostic
  and handles Cloud's fractional `y=5.5` spine tile unchanged.
  Per-layer counts: 79/36/29 across 3 layers; grid extents x=0..13, y=0..5.5.
- Appears automatically as a card in the US-21 picker.
- Verify geometry/free-tiles/persistence round-trip with `layout="cloud"`.

**Test:** `tests/us23_cloud.lua` (registered in `tests/run.sh`): 144 unique positions, per-layer
counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout id, picker
lists the Cloud card.

**Acceptance:** Manual — pick Cloud, play, restore mid-game. (Planned.)
