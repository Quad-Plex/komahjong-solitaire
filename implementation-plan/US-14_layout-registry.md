# US-14 — Layout registry + layout selection screen (architecture)

As a player, I want to choose which board shape to play on.

This story ships the **architecture only**: Turtle stays the only registered layout, but every
layout-dependent path is generalized and a picker exists, so a new layout becomes a one-file
addition (US-15/16).

- `mahjonglogic.lua` — layout registry:
  - `MahjongLogic.layouts` maps `id -> { id, name, spec }` (the Turtle spec moves in verbatim)
    with `registerLayout(spec)`, `layoutIds()`, `layoutName(id)`.
  - Generalize the layout-dependent functions to take a layout id (defaulting to `"turtle"` so
    existing behavior and self-tests are unchanged): `buildLayout(id)`, `gridBounds(id)`,
    `maxLayer(id)` (replaces the fixed `MAX_LAYER`), `isLayoutPosition(x, y, layer, id)`,
    `newGame(id, rng)`, `freeTiles(board, id)`. Each `_layout_cache` becomes per-id.
- `mahjongboard.lua` — per-layout geometry:
  - `Board` gains a `layout_id`; the module-level `LAYOUT_BOUNDS` block becomes `layoutBounds(id)`;
    `tilePos`/`computeGeometry`/`rebuildTiles`/`syncOverlapGroup`/`hitTest` use the board's layout
    and `maxLayer`. (Turtle renders identically.)
- Persistence:
  - `serializeGameState` adds a `layout` field; `deserializeGameState` bumps to v2 and validates
    the stored layout id (unknown id → corrupt → fresh game) and every board/history position
    against THAT layout's position set. Old v1 saves (no `layout` field) restore as Turtle.
- `main.lua` — selection flow:
  - `startGame()`: a **saved** game restores directly (as today); otherwise (first launch, New
    Game, or win "Play again") show the **layout selection screen**; the chosen layout deals the
    board.
  - `resetGame(layout_id)`/`newGame` take the layout; `self.layout` tracks the current one and is
    saved with the game state. The `"layout"` settings key stays as the last-chosen default.
  - The picker makes the New Game `ConfirmBox` redundant (choosing a layout IS the confirmation):
    stop consulting `confirm_new_game` (keep the key; drop it in a later cleanup).
- New `mahjonglayoutselect.lua` widget — a full-screen selection screen with a **2x3 grid** of
  cards (6 slots, enough for the current set; wrap in a scroll container if more are added later).
  Each card: a small **thumbnail** (a miniature schematic of the layout's positions — small rounded
  rects per tile, per-layer offset so the 3D shape reads) plus the layout **name** underneath.
  Tapping a card deals a game on that layout.
- Add a `layoutThumbnail(id, w, h)` helper (in the picker module) that builds the schematic from
  the layout positions so US-15/16 get their thumbnail for free.

**Acceptance:**
- Self-tests: passing a layout id returns byte-identical Turtle results; the registry enumerates
  exactly `{"turtle"}`.
- `tests/us14_layouts.lua` (registered in `tests/run.sh`): registering a throwaway layout at
  test-time works end-to-end (deal → free tiles → render via a board built with that layout →
  serialize/restore round-trip → an unknown saved layout id deals fresh); the picker appears on
  first launch / New Game / Play again; choosing Turtle deals a game; the thumbnail renders for
  every registered layout.
- Manual: fresh launch → picker shows the Turtle card (thumbnail + name); picking it deals; New
  Game returns to the picker.
