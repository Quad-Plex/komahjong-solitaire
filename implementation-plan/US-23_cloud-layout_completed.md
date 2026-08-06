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

**Acceptance:** Manual — pick Cloud, play, restore mid-game. (Completed.)

**Implementation notes:** the Cloud spec lives in `mahjonglayouts.lua` only (per the US-22a
contract): `CLOUD_SPEC` + one `registerLayout{ id="cloud", name="Cloud", ... }` call plus a
`checkShape("cloud", { [0]=79, [1]=36, [2]=29 }, ...)` self-test. The body is a 14x5 block
(x=0..13, y=0..4) with a three-row spine at y=5.5 (L0 row x=2.5..10.5, L1 row x=3..10, and a
single L2 tile at (6, 5.5)) capped by seven even-x columns (y=0..3) on L1/L2. The fractional-y
free-tile/bevel logic handles the spine unchanged. Registering Cloud bumps the built-in
registry to five ids, so the count/sorted-order assertions in `mahjonglogic.lua` +
`mahjonglayouts.lua` self-tests and in `tests/us14/us15/us16/us21/us22` were updated
({bridge, cloud, spider, turtle, ziggurat}); `tests/us21_picker.lua`'s dynamic-rows section now
demos a 6-layout grid (toy fills row 1).
