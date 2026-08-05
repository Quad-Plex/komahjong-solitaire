# US-29 — Taipei layout

As a player, I want the "Taipei" board shape (GNOME's "difficult" default) to vary the game.

- Add the Taipei layout (144 positions) to the registry via `registerLayout`, transcribed
  from GNOME Mahjongg's `difficult` (Taipei) map. The iconic fortified "Great Wall" board:
  tiered walls rising to a single peak tile at the top. Per-layer counts:
  63/46/19/10/3/2/1 across 7 layers; grid extents x=0..10, y=0..6.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us29_taipei.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Taipei, play, restore mid-game. (Planned.)
