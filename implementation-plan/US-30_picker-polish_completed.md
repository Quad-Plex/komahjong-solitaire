# US-30 — Layout picker polish + bevel corner fix

As a player, I want the layout picker to be readable and responsive, and the
tile artwork to stay crisp on deep towers.

- Card names in the picker render **dark black** (was gray), for readability on e-ink.
- The thumbnail (miniature tower schematic) is centered by the tower's **face center of
  mass** inside a box inset by a breathing-room margin, and the card centers the whole
  thumbnail via a `CenterContainer`, so the 2.5D up-left layer shift and the width-filling
  towers (Spider/Bridge/Taipei on near-square portrait cards) no longer make the picture
  lean or sit flush against the card's left edge.
- Tapping a layout card shows a **pressed state** (background + border darken) and defers
  the deal by a short `UIManager:scheduleIn` tick, so the feedback paints on e-ink before
  the (synchronous) board build replaces the picker. Closing the picker cancels a pending
  pick.
- Every card carries a **trophy badge** (trophy glyph + number) in the thumbnail's top-right
  corner counting human wins on that layout, starting at `trophy 0` when never won.
- The bottom bevel's **left edge gets the same diagonal as the right edge**, so the tower's
  west face traces one continuous diagonal down a stack (visible on the deep multi-layer
  boards added in US-27..29).
- **Fresh deals always have a move:** `MahjongLogic.newGame(id)` re-deals a random board
  until it has at least one matching free pair (a small fraction of deals — ~5% on Bridge —
  started dead, which also made the picker-deal tests flaky).

**Test:** `tests/us30_picker_wins.lua` (registered in `tests/run.sh`): names are black,
badges start at 0, per-layout wins track/persist via `MahjongStats.layout_wins`, auto-solve
wins never count, tap feedback (pressed card + deferred deal + cancel-on-close), and the
thumbnail still renders after the centering change.

**Acceptance:** Manual — open the picker; tap a card and confirm the press shows before the
game loads; win games on a couple of layouts and confirm the badges count them.

**Implementation notes:**

- `mahjongstats.lua` gained a `layout_wins` map (id → wins) in `defaults()`/`load()`
  (sanitized) plus `MahjongStats.recordLayoutWin(stats, id)`. `main.lua`'s `showWinDialog`
  records the layout inside the same human-win gate as `recordWin` (auto-solve never
  counts), and `showLayoutPicker` passes `wins_by_layout = self.stats.layout_wins` to the
  picker.
- `mahjonglayoutselect.lua`: `layoutThumbnail` scales the tower to fit a margin-inset box,
  positions it by the tower's face center of mass, and shrinks it one notch if the fit-box
  rounding leaves no room to center a lopsided tower (Turtle's head/tail); each card wraps
  its content (`VerticalGroup` = thumbnail + name) in a `CenterContainer`
  (`dimen = card_w x card_h`) so the thumbnail is centered in the card rather than flush
  left; a `layoutBadge()` trophy widget rides the thumbnail's top-right corner in an
  `OverlapGroup`; `onTapSelect` calls `_pressCard` + `scheduleIn(TAP_FEEDBACK_SECONDS, ...)`
  → `_finishPick` (guarded by `_pending_pick` so a closed/superseded picker never deals).
- `mahjonglogic.lua`: `newGame(id, rng)` re-deals when `rng` is nil until the board has at
  least one matching free pair (seeded deals are unchanged — only the random path re-deals).
- `tools/gen_icons.py`: `FACE_BEVEL_BOTTOM` and `FACE_BEVEL_BOTTOM_CORNER` gained the left
  corner diagonal (`M0 140 L100 140 L100 154 L10 154 Z` / `M0 140 L100 140 L110 154 L10 154 Z`);
  added the Material `emoji_events`-based `trophy.svg`. `tools/check_icons.py` count bumped
  179 → 180. All icons regenerated (the bevel change touches every tile variant).
- The harness mock now captures `scheduleIn`/`nextTick` into `ctx.scheduled` and exposes
  `ctx.runScheduled()` (snapshot semantics) so the deferred picker deal can be flushed;
  `OverlapGroup` stub gained `getSize()` (real overlapgroups are queryable), which the new
  nested thumbnail OverlapGroup needs.
