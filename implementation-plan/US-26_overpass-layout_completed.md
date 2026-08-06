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

**Acceptance:** Manual — pick Overpass, play, restore mid-game. (Completed.)

**Implementation notes:** the Overpass spec lives in `mahjonglayouts.lua` only (per the
US-22a contract): `OVERPASS_SPEC` + one `registerLayout{ id="overpass", name="Overpass", ... }`
call plus a `checkShape("overpass", { [0]=52, [1]=20, [2]=16, [3]=32, [4]=24 }, ...)` self-test.
The L0 towers are columns at x=0/x=11 (y=2..7) with single corner tiles at x=1/x=10, plus the
4-wide full-height center deck (x=4..7, y=0..8); L1 is the four tower columns; L2 two 2-wide deck
segments; L3 the 8-wide lower deck; L4 the 6-wide upper deck. All coordinates are on the full grid.
