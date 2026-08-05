# US-05 — Free-tile detection (core rules)

As a player, I want only genuinely "free" tiles to be selectable so the game is fair.

- Pure logic functions on a board state:
  - `tileAt(board, x, y, layer)`.
  - `isFree(board, x, y, layer)` implementing the rule in design decision 5.
  - `freeTiles(board)` returns all free tiles.
  - `hasMoves(board)`: true if at least one pair of matching free tiles exists.
- Self-tests: build a small hand-crafted board; assert known free/blocked results, including:
  a tile covered from above is not free; a tile with both sides occupied is not free; a tile
  with one open side IS free; empty cell is not a tile; after removing a pair the newly exposed
  tile becomes free.

**Acceptance:** Self-tests pass for all listed cases.
