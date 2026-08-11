# US-20 — Hint penalty per session + Pause moves to the bottom toolbar

As a player, I want cycling through hints to cost me once per hint session (not once per press),
and I want the Pause control out of the crowded HUD and among the bottom action buttons.

- `main.lua` `showHint()`: the `HINT_PENALTY` is charged only when a press STARTS a hint session —
  a session runs from the first hint after a pair was cleared until the next pair is cleared.
  Presses that continue an active session (cycling, or re-hinting the same board) are free and do
  not re-increment `hints_used`. `applyMatch()` resets `self._last_hint` so any cleared pair (hand
  or auto-solver) ends the session and the next hint pays once again. The dead-board shuffle offer
  still charges nothing.
- `main.lua` `createStatusBar()`: the Pause button is removed from the HUD's `left_icons` (now
  gear + stats, two buttons), decluttering the top bar.
- `main.lua` `buildUILayout()`: Pause joins the bottom toolbar as the fifth action button
  (`mahjong/pause`, kept as `self.pause_button`), wired to the existing `pauseGame()`. Toolbar
  spacing/width updated from 4→5 buttons (6 edge/between gaps).
- `tests/us01_shell.lua` (5 buttons / 6 gaps + Pause wiring), `tests/us06_board.lua` (New Game
  found by icon, no longer the last button), `tests/us13_stats.lua` (HUD has two left buttons),
  `tests/us17_pause.lua` (Pause tapped via the toolbar button), `tests/us18_penalties.lua`
  (cycling re-charges nothing; a cleared pair re-opens a paying session).

**Acceptance:** Manual — press Hint repeatedly: only the first press drops the Score chip; match a
pair, then Hint again: it drops once more; Pause now sits at the right end of the bottom row.
