# US-31 — Per-layout highscore on the layout picker

As a player, I want the layout picker to show each map's best score, so I can
compare layouts and chase a record without remembering my scores.

- Each picker card shows a **score chip** (the layout's best winning score, as
  a plain number) in the thumbnail's **bottom-left corner**, opposite the
  trophy badge's top-right.
- A layout with no human win shows **no chip** (nothing to display).
- Auto-solve wins never record a highscore, matching the existing `layout_wins`
  gating.

**Test:** `tests/us31_layout_score.lua` (registered in `tests/run.sh`): fresh
stats show no chips; a persisted highscore shows on the right card with the
right value and corner position; a human win records + persists the score and
the chip appears after "Play again"; auto-solve wins record no chip.

**Acceptance:** Manual — win games on two layouts and confirm the picker shows
each layout's best score in its card's bottom-left corner; confirm a never-won
layout has no chip.

**Implementation notes:**

- `mahjongstats.lua` gained a `layout_highscores` map (id → best winning score)
  in `defaults()`/`load()` (sanitized like `layout_wins`; old records default to
  `{}`). `MahjongStats.recordLayoutWin(stats, id, score)` now takes an optional
  third `score` argument and keeps `layout_highscores[id]` at the max; the
  two-argument form still just bumps the win counter, so existing callers and
  saved data stay valid.
- `main.lua`'s `showWinDialog` passes `self.score` to `recordLayoutWin` inside
  the existing human-win gate (auto-solve never sets a highscore), and
  `showLayoutPicker` passes `highscores_by_layout = self.stats.layout_highscores`
  to the picker.
- `mahjonglayoutselect.lua`: a new `layoutScoreChip(score)` widget mirrors
  `layoutBadge` (white rounded `FrameContainer`, dark border, `getSize`
  override); the card appends it as the **third child** of the thumbnail's
  `OverlapGroup` (badge stays child 2 — the US-30 badge assertions are
  unaffected) only when `highscores_by_layout[id] > 0`, positioned bottom-left
  via `overlap_offset` at the same `badge_margin` as the badge.
