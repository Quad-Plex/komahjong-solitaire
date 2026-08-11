# US-17 — Pause

As a player, I want to pause the game so the clock stops and stray taps can't move tiles.

- Add a Pause button (extend the HUD's `left_icons` list).
- Tap → `stopTimer()` (freezes `elapsed_base`), then show a modal overlay: a full-screen
  transparent `InputContainer` with a centered "Paused" card (the settings/stats floating-card
  pattern) and a **Resume** button. The overlay consumes all taps, so no tile can be selected
  while paused.
- Resume → close the overlay + `startTimer()`.
- Closing the plugin while paused still saves the game (`onCloseWidget` calls `saveGameState`;
  ensure `stopTimer` runs once — reuse the existing timer helpers).
- `tests/us17_pause.lua` (registered in `tests/run.sh`): pause freezes elapsed (two `getElapsed()`
  reads are stable), the overlay sits on the window stack and blocks board taps, resume restarts
  the clock, pause-then-close saves.

**Acceptance:** Manual — pause mid-game, elapsed freezes, taps do nothing, resume continues.
