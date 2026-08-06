# US-32 — Failure recognition (deadlock detection)

As a player, I want the game to recognize when the board is permanently dead — when
no sequence of legal moves (plus shuffles) can ever clear it — and tell me it's
time to undo or start over, instead of leaving me stuck shuffling forever.

## Motivation

The canonical trigger: "two identical tiles stacked on top of each other" (the
last two copies of a kind sitting in the same column, one directly covering the
other). Shuffle preserves the position set AND the kind multiset, so both tiles
stay in the same column — the upper tile has no matching partner (its only twin
is trapped beneath) and the lower tile is permanently covered. The board can
never be cleared, but the current shuffle loop just exhausts silently (or charges
the player for every subsequent manual press).

## Detection — structural check first, retries-exhausted fallback

`MahjongLogic.isPermanentlyDead(board)` in `mahjonglogic.lua` is a pure-Lua,
sound (never false-positive) check composed of two cheap heuristics:

1. **Match-group parity (A).** Every legal match removes exactly two tiles from
   the same group (kind / "flower" / "season"). Any group with an odd remaining
   count can never fully clear → immediately dead. (Example: a lone leftover
   flower after its partner was matched away.)

2. **Stacked-kind deadlock (B).** For a kind K with ≥2 remaining tiles, if at
   most ONE K-tile is free *and* every non-free K-tile is covered (from above,
   within ±0.5 in both axes) by a K-tile, the K's form a self-blocking chain —
   no pair can ever escape. This catches the 2-stack, the 4-in-one-column stack,
   and the whole stacked-identical family.

A third candidate (geometric position-trapping closure) was considered and
rejected: on these grids "out of grid = open side" guarantees every position is
eventually freeable, so the closure is vacuously false. The selected checks are
sound and cover all common permanent deadlocks. Exotic deadlocks that slip past
both are caught by the **retries-exhausted fallback**: when the shuffle (or
auto-solve) retry loop exhausts with no moves the same loss dialog fires,
closing the loop.

## Flow

At no-moves time (`checkGameState`, `showHint`'s dead branch, and the
`startGame` restore branch):

1. Run `isPermanentlyDead`.
2. **Provably dead** → `showDeadBoardDialog()` — a three-button dialog:
   - **New Game** (→ layout picker)
   - **Close** (→ exit the game)
   - **Undo** (pops one move, restarts the timer; hidden when history is empty)
3. **Not provably dead** → existing shuffle `ConfirmBox` (unchanged).

> **Tap-outside fix (after shipping):** KOReader fires a ConfirmBox's
> `cancel_callback` for a tap OUTSIDE the dialog too, so a stray tap next to
> the loss dialog (or the shuffle prompt, or the win dialog) used to run the
> "Close = exit" callback and close the whole app — reported as a crash. All
> three dialogs now wrap their options in `dismissDialogOnTapOutside`
> (`main.lua`), an `onTapClose` override so a tap outside only dismisses the
> dialog; the Close button still runs `cancel_callback` and exits.

The same loss dialog fires when `shuffleBoard`'s auto-repeat loop exhausts and
when `autoSolveStep`'s mid-solve shuffle loop exhausts. In the auto-solve case
history is cleared, so Undo is naturally absent.

The timer is paused while the loss dialog is up (matching the win-dialog
pattern).

## Call sites (main.lua)

| Site | Change |
|---|---|
| `checkGameState` | `not hasMoves` → `handleNoMoves()` |
| `showHint` `#pairs==0` branch | replaces inline shuffle prompt with `handleNoMoves()` |
| `shuffleBoard` `do_shuffle` retry | `attempts==0` + no moves → `showDeadBoardDialog()` |
| `autoSolveStep` shuffle exhaust | `stopAutoSolve()` + `showDeadBoardDialog()` |
| `startGame` restore branch | after `show(self)`, if no moves → `handleNoMoves()` |

## Acceptance

- Logic self-tests: odd-count board, stacked-identical board, 4-stack, single
  flower → all true; free-pair board, full newGame → false.
- Harness (`tests/us32_deadlock.lua`): provably-dead → loss dialog; Undo
  restores and resumes; New Game → picker; Close → exit; shuffle retries
  exhaust → dialog; auto-solve exhaust → dialog (no Undo); monkeypatched
  not-dead → shuffle prompt.
- Existing tests (`us07_gameplay`, `us08_features`, `us18_penalties`) updated
  for the changed flow on boards that are now provably dead.
