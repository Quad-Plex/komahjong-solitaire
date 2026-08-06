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

**Acceptance:** Manual — pick Confounding Cross, play, restore mid-game. (Completed.)

**Implementation notes:** the Confounding Cross spec lives in `mahjonglayouts.lua` only (per the
US-22a contract): `CONFOUNDING_SPEC` + one
`registerLayout{ id="confounding", name="Confounding Cross", ... }` call plus a
`checkShape("confounding", { [0]=47, [1]=42, [2]=27, [3]=18, [4]=9, [5]=1 }, ...)` self-test.
The L0 cross is three-wide arms (rows/columns) with the four arm tips at (5,0)/(0,4)/(10,4)/(5,8)
and a full center column; the upper layers hollow the corners and shrink toward the center
column x=5 until a single L5 peak tile (5,4) remains. Grid extents x=0..10, y=0..8. The half-grid
L1/L3 positions feed the existing bevel/free-tile logic unchanged.
