# US-13 — Stats screen (dedicated "Stats" button + floating card)

As a player, I want a dedicated stats screen so I can review my lifetime progress at a glance.

- Extend `hudbar.lua` to support **multiple left buttons**
  (`left_icons = { { icon=.., size_ratio=.., callback=.. }, ... }`) while keeping the existing
  `left_icon`/`right_icon` fields (the existing tests read
  `status_bar.left_icon_tap_callback`/`right_icon_tap_callback`). Add a "Stats" button next to the
  settings gear; the title stays centered in the remaining width.
- New widget `mahjongstats.lua` — a floating card in the exact `mahjongsettings.lua` pattern
  (transparent full-screen `InputContainer` → `CenterContainer` → white rounded `FrameContainer`;
  full-screen `TapClose` dismissing on a tap outside `_panel_geom`; the `onShow` panel-region
  refresh trick so the card appears immediately; rows with right-aligned labels and a
  uniform-width value column).
- Rows: Games played, Games won, Win rate, Best score, Best time, Average time per win, Current
  streak, Longest streak. A bottom "Reset" button (ConfirmBox first) clears the record back to
  `defaults()`.
- Timer: opening the dialog calls `stopTimer()`; closing resumes via `startTimer()`, exactly like
  `openSettings`.
- `main.lua`: `createStatusBar()` wires the Stats button; `openStats()` shows the dialog.

**Acceptance:**
- `tests/us13_stats.lua` (registered in `tests/run.sh`): the HUD exposes a stats button whose
  callback opens the dialog; the card lists the persisted lifetime stats; Reset zeroes them only
  after a confirm; tap-outside closes; the timer stops while open and resumes on close. Existing
  `hud_bar.lua` assertions still pass (compat fields preserved).
- Manual: open Stats mid-game → values match real play; Reset works; closing the card resumes the
  clock.
