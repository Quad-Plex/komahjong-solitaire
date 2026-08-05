# US-10 — Persistence: save/restore game + settings

As a player, I want my game to survive closing the plugin so I can continue later.

- `LuaSettings` file `mahjong.lua` in the KOReader settings dir.
- Settings: hints enabled, new-game confirm enabled, score method, layout variant (Turtle only
  for now).
- Game state export/restore: remaining tile deck (position + kind), removed-pair history
  (for undo), score, elapsed time. Restore on `startGame()`; save on close (title-bar close and
  `onCloseWidget`).
- Invalid/corrupt saved state → silently start a new game.

**Acceptance:** Close mid-game, reopen → board/score/undo stack identical. New Game clears the
saved state. A tampered/corrupt settings value falls back to a fresh game without crashing.
