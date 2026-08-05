# US-28 — Confounding Cross layout

As a player, I want the "Confounding Cross" board shape to vary the game.

- Add the Confounding Cross layout (144 positions) to the registry via `registerLayout`,
  transcribed from GNOME Mahjongg's `confounding` map. A plus/cross shape built from
  nested hollow rings rising to a lone center peak tile. Per-layer counts:
  47/42/27/18/9/1 across 6 layers; grid extents x=0..10, y=0..8.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us28_confounding.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Confounding Cross, play, restore mid-game. (Planned.)
