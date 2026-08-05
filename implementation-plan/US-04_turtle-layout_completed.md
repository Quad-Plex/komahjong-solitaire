# US-04 — Turtle layout + shuffled tile placement

As a player, I want the board to be a standard shuffled Turtle so every game is different.

- In `mahjonglogic.lua`: `buildLayout()` returns the 144 tile positions from the Turtle table
  above (keyed by `{x,y,layer}`).
- `newGame(rng)`: shuffle the 144 deck tiles and assign them to the 144 positions.
- Self-tests: layout has exactly 144 positions matching the table; after shuffle every deck tile
  appears exactly once; layout is deterministic given a seeded RNG.

**Acceptance:** Self-tests pass. (No UI needed yet — this is pure logic.)
