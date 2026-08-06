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

**Acceptance:** Manual — pick Taipei, play, restore mid-game. (Completed.)

**Implementation notes:** the Taipei spec lives in `mahjonglayouts.lua` only (per the
US-22a contract): `TAIPEI_SPEC` + one `registerLayout{ id="taipei", name="Taipei", ... }`
call plus a `checkShape("taipei", { [0]=63, [1]=46, [2]=19, [3]=10, [4]=3, [5]=2, [6]=1 }, ...)`
self-test. The L0 base is two corner towers (x=0/x=10 at y=3 plus four 2x2 corner blocks and two
2-wide 2x2 edge blocks) around the 5-wide center block (x=3..7, y=2..4) and its top/bottom/mid
rows; the tiered walls shrink one layer at a time to the L6 peak tile (5,3). Grid extents
x=0..10, y=0..6. The half-grid L0/L1 positions feed the existing bevel/free-tile logic unchanged.
