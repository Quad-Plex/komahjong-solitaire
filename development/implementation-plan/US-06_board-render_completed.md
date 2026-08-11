# US-06 — Render the board on screen (first playable visuals)

As a player, I want to see the full Turtle board of tiles laid out on the e-ink screen.

- `mahjongboard.lua`: `Board` extends `InputContainer` (full-screen sized), paints one
  `IconWidget` per visible tile inside an `OverlapGroup` (children offset via `overlap_offset`).
- Geometry (`computeGeometry`): portrait tiles (`th = TILE_ASPECT * tw`, `TILE_ASPECT = 1.4`)
  sized to fit both axes (`tw = floor(min(usable_w/units_w, (usable_h/units_h)/ASPECT))`),
  centered with `origin_x/origin_y`. **Each layer is shifted up-left by exactly the bevel
  thickness** (`tilePos` subtracts `layer*bw`/`layer*bh`), so a raised tile's face is inset from
  the tile directly beneath it and its outward bevels land exactly on that underlying tile's
  face edges — the bevel is the visible step and never overlaps the tiles to its east/south.
  Each widget is sized `tile_w = tw + bw`,
  `tile_h = th + bh` with `BEVEL_FRAC = 0.10` (`bw = floor(tw*0.10+0.5)`, `bh = floor(th*0.10+0.5)`),
  the face is anchored at the widget's top-left, and the tile's outward depth bevels (right
  `#78909c`, bottom `#546e7a`) hang off its east/south edges. Earlier
  manual `LAYER_OFF_*` shifts (0.25/0.25, 0.2/0.14 up-and-right, 0.10/0.10 up-and-left) all
  produced skewed stacks or white face strips, and the first outward-bevel attempt (no layer
  offset, bevels overhanging the neighbours) overlapped the tiles to their east/south. `units_w/units_h` come from `LAYOUT_BOUNDS`,
  computed with `+1 + BEVEL_FRAC` on the east/south extents (bevel overhang) and
  `- layer*BEVEL_FRAC` on the west/north (the up-left shift).
  Tile SVGs are portrait 100x140 (matching the 1.4 aspect) in a shared 110x154 viewBox with the
  outward bevels, so tiles fill their box exactly (no white row gaps) and the stack reads as
  raised. Each tile's icon is resolved per-position via
  `MahjongLogic.iconForTile(board, x, y, layer)`, which hides the bottom/right bevel when a
  same-layer neighbour covers that edge (4 generated variants per face), including on the half
  grid where an edge covered by TWO half-overlapping same-layer neighbours is also hidden.
- Children are appended in `buildLayout()` order (bottom layer first) so lower tiles paint under
  upper ones; `OverlapGroup` gets a board-sized `dimen`.
- `updateBoard()` frees + rebuilds the tiles and calls `UIManager:setDirty`.
- Taps: `TapSelect` gesture on `self.dimen` → `hitTest` walks layers top-down and returns the
  topmost tile whose rect contains the point; forwarded as `(x, y, layer)` via `onTileTap`.
- `getSize()` returns `self.dimen` — the board is NOT a `FrameContainer` subclass, so the
  `_padding_*` override crash (`AGENTS.md` pitfall) cannot occur.
- Per-story harnesses live in `tests/` (see `tests/run.sh`): `us06_board.lua` (geometry,
  z-order, hit-test, taps, main wiring) and `us06_paint.lua` (paint-contract regression for
  the crash). New stories extend this suite.

**Acceptance:** Full board renders as 144 tiles in the Turtle silhouette (outward bevels readable
as a 3D stack); board fits the screen on the target resolution; no blank cells; icons legible;
tap on a tile reports the exact (x, y, layer).
