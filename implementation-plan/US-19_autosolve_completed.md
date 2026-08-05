# US-19 — Long-press Hint to auto-solve the board

As a player, I want to watch the machine clear the board when I'm stuck, by holding the Hint
button for ~10 seconds, so the game finishes itself.

- KOReader's `Button` already supports long-press via `hold_callback` (the `hold` gesture fires
  ~`ges_hold_interval_ms`, ~0.5 s, after contact), but the ~10 s requirement cannot be expressed
  in the gesture system (that interval is device-global). Instead:
  - `main.lua` adds a `LongPressButton = ButtonWidget:extend{}` that surfaces the normally-hidden
    `hold_release` event (`onHoldReleaseSelectButton` override → `hold_release_callback`).
  - The Hint button's `hold_callback` (`armAutoSolve`) shows a persistent "Keep holding to
    auto-solve…" band message and arms a `UIManager:scheduleIn(AUTO_SOLVE_HOLD_SECONDS=10, ...)`;
    `hold_release_callback` (`disarmAutoSolve`) cancels the arm if the finger lifts first.
  - `startAutoSolve` runs a solver (`autoSolveStep`) that reuses the exact tap-path code — a new
    `applyMatch(a, b)` helper extracted from `handleTileTap` (scoring, chain bonus, history,
    HUD + mm:ss refresh, save) — removing one matching free pair per `AUTO_SOLVE_STEP_SECONDS`
    (0.55 s) step until the board is empty, then shows the normal win dialog. A dead board
    mid-solve shuffles (bounded retries) and continues. History is cleared at solve start and
    before a mid-solve shuffle so undo can't restore tiles to positions that moved under a
    shuffle.
  - Any board tap, a short Hint tap, Undo, New Game, or close stops the solver (token-bumped
    pending steps become no-ops). The `hints` setting gates the arm like it gates `showHint`.
  - Flash refactor: `setFlash` (persistent, used by the solver) split out of `flashMessage`
    (auto-clearing); `clearFlash` bumps the sequence token instead of niling it, fixing a latent
    `nil + 1` crash on a second flash after a cleared band.
- `tests/us19_autosolve.lua` (registered in `tests/run.sh`): arm/10 s-cancel, full board clear +
  win dialog + history/score, board-tap/short-tap/undo stop the solve (pending step no-ops),
  hints-off arms nothing, second-flash-after-clear regression.

**Acceptance:** Manual — hold Hint for ~10 s; the band says "Auto-solving…" and the board clears
one pair at a time; tapping the board interrupts; a held-then-quickly-released press does
nothing.
