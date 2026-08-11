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

**Acceptance:** Manual — pick Tic-Tac-Toe, play, restore mid-game. (Completed.)

**Implementation notes:** the Tic-Tac-Toe spec lives in `mahjonglayouts.lua` only (per the
US-22a contract): `TICTACTOE_SPEC` + one `registerLayout{ id="tictactoe", name="Tic-Tac-Toe", ... }`
call plus a `checkShape("tictactoe", { [0]=40, [1]=36, [2]=28, [3]=20, [4]=20 }, ...)` self-test.
The two 9-tall columns (x=3/x=9) and the 3-wide edge rows step in one row per layer while the
5-wide center rows repeat on every layer; all coordinates are on the full grid. The layout id is
`tictactoe`. Registering it bumps the built-in registry to eight ids, so the count/sorted-order
assertions in `mahjonglogic.lua` + `mahjonglayouts.lua` self-tests and in
`tests/us14/us15/us16/us21/us22/us23` were updated to
{bridge, cloud, overpass, red-dragon, spider, tictactoe, turtle, ziggurat}; `tests/us21_picker.lua`'s
dynamic-rows section now demos a 9-layout grid (toy fills row 2).
