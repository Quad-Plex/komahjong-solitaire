# US-33 — Uninterruptible auto-solve (input lock + tainted save + resume-on-reload)

As a player, I want the auto-solver to be impossible to cheat: while it runs, no input may
interrupt it, and even closing the app mid-solve must not let me keep a partial score.

## Motivation

The long-press auto-solver (US-19) deliberately let ANY input stop the solve: a board tap, a
short Hint tap, Undo, New Game, Pause, or the quit X. That was the cheat: hold the Hint button,
let the solver clear most of the board, tap quit X, and the game saved a nearly-cleared board
with the solver's score. `game_was_autosolved` was an in-memory flag only, so the next launch
restored that board with the flag reset and finishing the last few pairs by hand recorded a
legitimate win (win, bests, streak, per-layout trophy + highscore).

## Design

Three layers, so the cheat is dead even across a crash or a force-quit (no UI block can stop
those):

1. **Input lock.** While `_auto_solve_active`, EVERY user entry point is a silent no-op:
   board taps, Hint, Undo, Shuffle, New Game (layout picker), Pause, the settings gear, the
   stats card, the quit X, and a second hold of the Hint button. The solve runs to completion
   and cannot be cancelled.

2. **Tainted save.** `game_was_autosolved` rides along in the game state as an optional v2
   `autosolved` field (`serializeGameState`/`deserializeGameState`). Because `saveGameState`
   already runs after every solver step (`applyMatch`), a save made at any point during a solve
   — including the framework-close path in `onCloseWidget` — is permanently tainted. No version
   bump: the field is optional and lenient (missing / non-boolean → false), so pre-US-33 v2
   saves restore clean.

3. **Resume on reload.** The `startGame` restore branch reads `restored.autosolved`; a tainted
   game restores tainted AND immediately re-arms the solver via `UIManager:nextTick`. There is
   no avoiding it once triggered. The resume skips the `handleNoMoves` check (the solver
   shuffles dead boards itself); `startAutoSolve` clears the restored undo history as it already
   does on a fresh trigger, so the dead-board dialog's Undo is absent on a resumed solve — same
   as mid-solve today. The solver ends only via the win dialog (no win recorded, `game_won`
   stays false) or a provably-dead board (`stopAutoSolve` + dead-board dialog).

## Call sites (main.lua)

| Site | Change |
|---|---|
| `handleTileTap` | early return instead of the old `stopAutoSolve()` interrupt |
| `showHint` | early return |
| `undo` | early return |
| `shuffleBoard` | new early return (previously shuffled *under* the solver) |
| `pauseGame` | early return; drop the now-dead `stopAutoSolve()` |
| `openSettings` / `openStats` | new early return |
| `showLayoutPicker` | new early return (blocks the New Game toolbar button; win/dead-board dialogs only reach it after the solve ends) |
| quit-X callback (`createStatusBar`) | early return (no Exit ConfirmBox during a solve) |
| `armAutoSolve` / `disarmAutoSolve` | early return (a second hold can't clobber the "Auto-solving…" flash) |
| `saveGameState` | passes `self.game_was_autosolved` (9th `serializeGameState` arg) |
| `startGame` restore branch | sets `game_was_autosolved` from `restored.autosolved`; tainted → `nextTick(startAutoSolve)`; else the existing `hasMoves` check |

## mahjonglogic.lua

- `serializeGameState(..., layout, autosolved)` gains a 9th arg → `autosolved = autosolved == true`.
- `deserializeGameState` reads `data.autosolved == true` leniently and returns it.
- Embedded self-tests: flag absent → false; round-trips true; non-boolean → false (lenient).

## Speed

`AUTO_SOLVE_STEP_SECONDS` 0.4 → 0.3 s, so a full solve (~72 steps) is quicker.

## Acceptance

- Logic self-tests: the taint flag round-trips; a non-boolean value validates as not-tainted.
- Harness (`tests/us33_autosolve_lock.lua`): a mid-solve save carries `autosolved=true`;
  closing mid-solve (`onCloseWidget`) saves the tainted partial board; a fresh instance
  restores it tainted and RESUMES the solve on the next tick; the resumed solve clears the
  board and records no win; a pre-US-33 save restores clean with no resume; Pause / Settings /
  Stats / New Game / quit X / a second hold are all no-ops while a solve runs.
- `tests/us19_autosolve.lua` and `tests/us17_pause.lua` updated: board tap / Hint / Undo /
  Shuffle / Pause no longer stop the solve — they are ignored and it keeps running.
