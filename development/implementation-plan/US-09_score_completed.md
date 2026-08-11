# US-09 — Score, pair counter, and status feedback

As a player, I want feedback on my progress and a running score.

- Score model (keep simple, document it in README):
  - Base 10 points per matched pair.
  - Consecutive bonus: +50 if the previous match was the same tile kind (chain).
  - Timer bonus: on a win, add remaining-time bonus (or skip if timing not implemented).
- HUD top bar (`hudbar.lua`, replacing the original `TitleBarWidget` subtitle): the top of the
  screen is a full-width band with the title plus three stylized stat "chips" — Pairs remaining,
  Free pairs, Score — each a rounded pill with an icon, a bold value and a tiny label, pushed via
  `setStats()` after every move.
- Show brief feedback on invalid selections (e.g. a small `InfoMessage` or status subtitle
  flash) and on win ("You cleared the board! Score: S").

**Acceptance:** Score/pairs update correctly as pairs are removed; chain bonus applies only on
consecutive same-kind matches; status bar reflects state; logic for score is unit-testable and
tested.
