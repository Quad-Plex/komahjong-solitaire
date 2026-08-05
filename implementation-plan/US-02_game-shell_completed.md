# US-02 — Full-screen game shell with title bar and New Game/Exit

As a player, I want a proper full-screen game window with a status/title bar so I can start a
game and exit cleanly back to KOReader.

- Plugin widget extends `FrameContainer` with `full_width`/`full_height` and
  `covers_fullscreen = true`.
- `startGame()` builds a minimal layout (empty board area + `TitleBarWidget`) into `self[1]` and
  calls `UIManager:show(self)`.
- Title bar: close icon → confirm → save state (stub) + `UIManager:close(self, "full")`.
- Add `onCloseWidget()` cleanup stub; guard `handleEvent()` using the `_window_stack` pattern.
- Add a "New Game" button (e.g. `plus` icon button like the example toolbar) that triggers a
  confirm box, then resets the board (stub).

**Acceptance:** Window opens full-screen, title bar shows, close exits back to KOReader with no
errors/leaked timers, New Game confirm box appears and works.
