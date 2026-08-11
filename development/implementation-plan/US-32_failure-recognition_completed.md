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

2. **Single-free-tile stack (B).** If at most one tile on the whole board is
   free, the board is a single-column stack and is permanently stuck: no move
   can ever be made, because a shuffle only re-assigns *kinds* to the fixed
   set of positions — which positions are *free* depends purely on the
   occupancy pattern (nothing covers the tile, an open horizontal side), never
   on kinds. This catches the named 2-stack, the 4-in-one-column stack, and
   any single-column stack.

   > **Corrected after shipping (this was the "reloading a 0-moves game never
   > prompts to shuffle" bug):** the first version of B ("a kind K with ≥2
   > tiles, ≤1 free K, every covered K covered by a K") was UNSOUND. When the
   > board has other positions, a shuffle separates the stacked kinds into a
   > matching free pair, so those boards must still be offered a shuffle. The
   > sound rule is B above; any board with ≥2 free tiles is NOT provably dead
   > (a shuffle can place two copies of a kind with count ≥2 on two free
   > positions — if every kind had count 1, parity A already fired) and keeps
   > the shuffle offer, with the retries-exhausted fallback closing the loop.

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
3. **Not provably dead** → existing shuffle `ConfirmBox`; accepting it starts a
   background search of 15 shuffled candidates, and commits the candidate with
   the greatest number of matching free pairs. If every candidate is still
   stuck, the bounded retry path repeats the search without charging another
   shuffle penalty. The timer is paused while this prompt and its background
   shuffle search are active, and resumes only after a playable arrangement is
   found.

> **Tap-outside fix (after shipping):** KOReader fires a ConfirmBox's
> `cancel_callback` for a tap OUTSIDE the dialog too, so a stray tap next to
> the loss dialog (or the shuffle prompt, or the win dialog) used to run the
> "Close = exit" callback and close the whole app — reported as a crash. All
> three dialogs now wrap their options in `dismissDialogOnTapOutside`
> (`main.lua`), an `onTapClose` override that CONSUMES the stray tap — the
> dialog stays open and only its own buttons dismiss it; the Close button
> still runs `cancel_callback` and exits.

The same loss dialog fires when `shuffleBoard`'s auto-repeat loop exhausts and
when `autoSolveStep`'s mid-solve shuffle loop exhausts. In the auto-solve case
history is cleared, so Undo is naturally absent.

The timer is paused while the loss dialog is up (matching the win-dialog
pattern) and while the no-moves shuffle prompt/search is active. Closing the
shuffle prompt exits the game; accepting it resumes the timer only after the
shuffle produces a playable board.

## No-moves shuffle optimization (post-US-32)

The no-moves recovery path does not mutate the live board during candidate
evaluation. Each candidate is shuffled on a copy and scored with
`MahjongLogic.countFreePairs`; one candidate is evaluated per scheduled UI tick
to keep the KOReader UI responsive. After 15 candidates, the best candidate is
committed, the board is rebuilt, and the user-initiated shuffle penalty is
applied exactly once. A token invalidates pending callbacks when the game
closes.

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
  flower, mixed single-column stack → all true; free-pair board, full newGame,
  stacked pair WITH other free tiles (shuffle-fixable regression) → all false.
- Harness (`tests/us32_deadlock.lua`): provably-dead → loss dialog; Undo
  restores and resumes; New Game → picker; Close → exit; shuffle retries
  exhaust → dialog; auto-solve exhaust → dialog (no Undo); monkeypatched
  not-dead → shuffle prompt; reload of a saved 0-moves fixable board → shuffle
  prompt (not the loss dialog); no-moves recovery evaluates 15 candidates in
  the background and commits the candidate with the most moves.
- Existing tests (`us07_gameplay`, `us08_features`, `us18_penalties`) updated
  for the changed flow on boards that are now provably dead.
