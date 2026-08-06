# US-12 — Win summary + best-score/best-time tracking

As a player, I want the win screen to tell me how I did and to see my personal bests, so there is a
reason to replay.

- Add a pure `mahjongstats.lua` module (no UI deps, `--`-style self-tests like
  `mahjonglogic.lua`). A lifetime stats record is a plain table:
  `games_played`, `games_won`, `best_score`, `best_time` (seconds of the fastest win; `nil` until
  the first win), `current_streak`, `longest_streak`.
  - `defaults()`, `startGame(stats, previous_won)` (bumps `games_played`; resets `current_streak`
    to 0 when the previous game was abandoned, i.e. not won), `recordWin(stats, score, elapsed,
    pairs)` (bumps `games_won`/`current_streak`, tracks `longest_streak`, best-score/best-time
    maxima/minima).
- `main.lua` holds `self.stats` and persists it under the `"stats"` `LuaSettings` key — separate
  from the `"game"` key, so a win or a restore never touches it. Flush on every update.
- Call sites: `startGame()` fresh deal → `startGame(stats, previous_won)`; on win →
  `recordWin`; New Game/reset → `startGame(stats, self.game_won)`; set a `self.game_won` flag in
  `showWinDialog()`.
- Replace the one-line win dialog text with a summary: score, elapsed time, pairs matched (72),
  hints used, shuffles used, best score, best time, and current streak. The hint/shuffle lines are
  always shown, including `0`, and appear after pairs matched. Mark best-score/best-time lines with
  "New best!" the first time each record is set. Keep "Play again" / "Close" (Play again still
  calls `resetGame()` until US-14 reroutes it through the layout picker).
- Bests are computed from the real game (score + `getElapsed()`), so they are genuine records.
- **Auto-solve games never count toward stats (US-19 note):** a board cleared by the long-press
  Hint auto-solver is considered "cheated". The auto-solve win must NOT call `recordWin` or
  `startGame`'s previous-won logic — it records no win, no bests, no streak change, and does not
  bump `games_played`. Only the normal `showWinDialog()` path (a human play-through) records a
  win. Implementation touchpoints: the auto-solver reaches `showWinDialog()` too, so gate the
  stats recording on a `self.game_was_autosolved` flag that US-19's `startAutoSolve` sets and the
  normal win path never does (or route auto-solve wins through a dedicated win dialog path).

**Acceptance:**
- Self-tests: `startGame` bumps games_played and breaks a stale streak only when the previous game
  wasn't won; `recordWin` updates every field; best_time starts nil and only ever decreases;
  streak increments across consecutive wins and resets on an abandoned game.
- `tests/us12_stats.lua` (registered in `tests/run.sh`): stats survive a fresh plugin instance;
  the win dialog text contains score/time/pairs/help counters/bests and the "New best!" marker on
  a first record; zero and nonzero help counts are covered for human wins, and help counts are
  shown for auto-solve wins; Play again starts a new game; a mid-game New Game resets the streak.
- Manual: win → summary matches the game; a later win with a higher score updates best_score;
  abandoning resets the streak.
