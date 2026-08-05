# US-18 — Hint/shuffle score penalties

As a player, I want hints and shuffles to cost points, so using them is a real trade-off.

- `mahjonglogic.lua`: add `HINT_PENALTY` (5) and `SHUFFLE_PENALTY` (10) constants and a pure
  `applyPenalty(score, amount)` that floors at 0 (score can't go negative).
- `main.lua`:
  - `showHint()` deducts `HINT_PENALTY` when a hint is actually shown (the dead-board shuffle offer
    is not a hint and does not penalize).
  - `shuffleBoard()` deducts `SHUFFLE_PENALTY` once per **user-initiated** shuffle; the bounded
    auto-repeat re-shuffles that guarantee a playable board do NOT re-charge.
  - Penalties apply at use time and persist via the existing score save; they are NOT part of the
    pair history, so `undo()` restores only the pair's points (never a penalty).
- Track per-game counters `hints_used` / `shuffles_used` (persisted in the game state) that feed
  the US-12/13 stats.
- `tests/us18_penalties.lua` (registered in `tests/run.sh`): constants + floor at 0; a hint
  deducts once per real hint; a shuffle deducts once (not per auto-repeat); undo doesn't restore
  penalties; the counters increment and survive a save/restore.

**Acceptance:** Manual — use a hint and shuffle, watch the Score chip drop; the win summary
reflects the net score.
