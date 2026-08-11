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

**Acceptance:** Manual — pick Pyramid's Walls, play, restore mid-game. (Completed.)

**Implementation notes:** the Pyramid's Walls spec lives in `mahjonglayouts.lua` only (per the
US-22a contract): `PYRAMID_SPEC` + one `registerLayout{ id="pyramid", name="Pyramid's Walls", ... }`
call plus a `checkShape("pyramid", { [0]=41, [1]=34, [2]=27, [3]=20, [4]=13, [5]=6, [6]=3 }, ...)`
self-test. Each of the 7 layers is the same shape — a border ring (rows at y=1/y=7, columns at
x=0/x=11) plus a horizontal middle bar at y=4 — shrinking inward by one tile per layer until
only the three L6 peak tiles (x=5.5 at y=1/y=4/y=7) remain. The map's rings span rows y=1..7
(no tile at y=0), so the true grid bounds are x=0..11, y=1..7 — the story's "y=0..6" extent
summary was a mis-transcription. The half-grid y=4 bars and y=1/y=7 rows feed the existing
bevel/free-tile logic unchanged.
