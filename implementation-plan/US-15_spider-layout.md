# US-15 — Spider layout

As a player, I want a second board shape ("Spider") to vary the game.

- Add the classic Spider layout (144 positions) to the registry via `registerLayout`. The
  neighbour-based bevel-variant icon logic is layout-agnostic and needs no changes.
- It appears automatically as a second card (thumbnail + name) in the US-14 picker.
- Verify on the target resolutions: geometry fits the screen (Spider's grid extents may exceed the
  Turtle's 14x7 — exercise `layoutBounds`/`computeGeometry`), free-tile detection and gameplay
  work, persistence round-trips with `layout="spider"`.
- `tests/us15_spider.lua` (registered in `tests/run.sh`): 144 unique positions, per-layer counts
  match the spec, deal/free-tiles/hasMoves work, save/restore with the layout id, the picker lists
  two entries.

**Acceptance:** Manual — pick Spider, play a full game, save/restore mid-game on the Spider board.
