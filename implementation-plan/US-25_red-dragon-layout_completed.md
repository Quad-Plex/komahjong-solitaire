# US-25 — Red Dragon layout

As a player, I want the "Red Dragon" board shape to vary the game.

- Add the Red Dragon layout (144 positions) to the registry via `registerLayout`,
  transcribed from GNOME Mahjongg's `dragon` map. Two curved "horn" towers connected by a
  central spine, with fractional x coordinates on the half-grid. Per-layer counts:
  82/45/17 across 3 layers; grid extents x=0..14, y=0..6.5.
- Appears automatically as a card in the US-21 picker.

**Test:** `tests/us25_red_dragon.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the layout
id, picker lists the card.

**Acceptance:** Manual — pick Red Dragon, play, restore mid-game. (Completed.)

**Implementation notes:** the Red Dragon spec lives in `mahjonglayouts.lua` only (per the
US-22a contract): `RED_DRAGON_SPEC` + one `registerLayout{ id="red-dragon", name="Red Dragon", ... }`
call plus a `checkShape("red-dragon", { [0]=82, [1]=45, [2]=17 }, ...)` self-test. The body is a
11x6 block (x=2..12, y=0..5) with five-tile horn towers at x=0/x=14 and a six-tile base row at
y=6.5; the L1 ridge (8x5 block at x=3.5..10.5, y=0.5..4.5) plus a right horn column and two left
horn tiles; L2 is a 4x4 ridge plus the off-center peak tile (11, 4). The fractional-y horn/base
tiles exercise the half-grid bevel/free-tile logic unchanged. The peak tile (11, 4, L2) has no L3
above it, so it is free on a full board. The layout id is `red-dragon`.
