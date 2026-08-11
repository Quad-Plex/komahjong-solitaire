# US-08 — Undo, hint, and shuffle

As a player, I want undo, a hint when stuck, and shuffle to rescue a dead board.

- **Undo:** keep a stack of removed pairs; undo restores the two tiles (validate they were both
  free/removed last). Toolbar or menu button "undo" (`chevron.left` icon). Undo clears score for
  that pair.
- **Hint:** find a matching free pair (`matchingFreePair`) and flash the `hint` overlay on both
  for a short time (then clear).
- **Shuffle:** reshuffle remaining (unmatched) tiles in place; prompt with `ConfirmBox` first.
  If still no moves after shuffle, allow repeat; also auto-offer when `hasMoves` is false.
- Persist the undo stack for state restore (US-10).

**Acceptance:**
- Self-tests: undo restores exact previous state; shuffle preserves the multiset of remaining
  tiles and number of remaining tiles.
- Manual: undo works repeatedly; hint highlights a real matching pair; shuffle changes the board
  and enables play when stuck.
