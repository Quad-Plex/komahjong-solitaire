# US-07 — Core gameplay: select, match, remove, win

As a player, I want to play a full game: tap two matching free tiles to remove them and win when
the board is clear.

- Tap behavior:
  - Free tile tapped → select (highlight with `select` overlay). Non-free tile tapped → ignored
    (or brief feedback).
  - Second tap on a matching free tile → remove both, update score stub, expose new tiles.
  - Tapping the selected tile again → deselect.
  - Tapping a different tile → switch selection.
- After each removal, call `freeTiles`/`hasMoves`; if the board is empty show a Win dialog
  (`ConfirmBox`: "Play again" → new game, "Close" → exit). If no moves remain, offer Shuffle
  (can be a simple immediate reshuffle of remaining tiles this story; dedicated shuffle UX in
  US-08).
- Keep game logic in `mahjonglogic.lua`: `removePair(board, a, b)`, `isWin(board)`,
  `matchingFreePair(board)`.

**Acceptance:**
- Self-test (logic): removing a valid pair updates state; invalid pairs rejected; `isWin` true
  only when empty; `matchingFreePair` returns a valid pair when one exists.
- Manual (on device/emulator): full game flow works — select, match, remove, win dialog,
  play-again resets a new shuffled board.
