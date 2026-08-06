# US-22 — Ziggurat layout

As a player, I want the "Ziggurat" board shape to vary the game.

- Add the Ziggurat layout (144 positions) to the registry via `registerLayout` in
  `mahjonglogic.lua`, transcribed from GNOME Mahjongg's `ziggurat` map. The
  neighbour-based bevel-variant icon logic (US-14) is layout-agnostic and needs no
  changes — it already handles the fractional coordinates Ziggurat uses on layers 3/4.
  Per-layer counts: 64/20/18/18/14/10 across 6 layers; grid extents x=0..14, y=0..7.
- It appears automatically as a card (thumbnail + name) in the US-21 picker after the
  grid is expanded.
- Verify geometry fits the screen (`layoutBounds`/`computeGeometry`), free-tile detection
  and gameplay work, persistence round-trips with `layout="ziggurat"`.

**Test:** `tests/us22_ziggurat.lua` (registered in `tests/run.sh`): 144 unique positions,
per-layer counts match the spec, deal/free-tiles/hasMoves work, save/restore with the
layout id, the picker lists the Ziggurat card.

**Acceptance:** Manual — pick Ziggurat, play a full game, save/restore mid-game. (Completed.)

**Follow-up (US-22a):** the Ziggurat spec (and the Turtle/Spider/Bridge specs, the
registry, the per-id caches, and the geometry helpers) were later extracted out of
`mahjonglogic.lua` into the dedicated pure module `mahjong.koplugin/mahjonglayouts.lua`.
`mahjonglogic.lua` now requires that module and re-exports its API unchanged; future board
stories (US-23..US-29) add their spec + `registerLayout` call in `mahjonglayouts.lua` only.
