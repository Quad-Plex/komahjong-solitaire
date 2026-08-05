# US-24 — Tic-Tac-Toe layout

As a player, I want the "Tic-Tac-Toe" board shape to vary the game.

- Add the Tic-Tac-Toe layout (144 positions) to the registry via `registerLayout`,
  transcribed from GNOME Mahjongg's `tictactoe` map. A 3×3 grid of nested blocks —
  regular geometry well suited to `block`/`column`/`row` spec terms. Per-layer counts:
  40/36/28/20/20 across 5 layers; grid extents x=0..12, y=0..8.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us24_tictactoe.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Tic-Tac-Toe, play, restore mid-game. (Planned.)
