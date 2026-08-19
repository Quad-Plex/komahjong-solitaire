# US-11 — Polish and cross-device refinement

As a player, I want a polished, stable game on my specific Kindle.

- Validate layout/sizing on the common Kindle resolutions (6", 6.8", 7") via `scaleBySize`;
  confirm the board never clips and cells stay tappable (min cell size).
- Tune e-ink refresh: use `"ui"` dirtying during play, `"full"` on screen open/close and on
  shuffle; avoid flicker-heavy updates.
- Verify icon legibility in grayscale; refine any muddy SVGs; ensure `select`/`hint` overlays
  are visible on both light and dark tiles.
- Add `README.md` to the plugin (install: copy `mahjong.koplugin` into
  `/mnt/us/extensions`? No — into the KOReader `plugins/` dir; usage; scoring rules).
- Run `luacheck`; clean up comments/dead code; ensure all user-facing strings use `_()`.

**Acceptance:** Game runs smoothly end-to-end on the target device; no clipped tiles; overlays
readable; README present; luacheck clean.

## Responsive follow-up

The later responsive hardening pass extends this story's cross-device requirement beyond the board:

- `mahjongui.lua` provides shared runtime dimension refresh and a text-face fitting helper.
- The picker, HUD chips, title rows, feedback/timer band, toolbar captions, Settings, Help,
  Statistics, and win-summary widgets bind text to their available geometry and use smaller faces
  when needed.
- Floating panels clamp their width and height to the runtime canvas. Statistics keeps two columns
  when they fit and stacks them when the available width is too small. The win summary uses fixed
  label/value slots and bounds record markers and buttons so intrinsic text cannot widen the card.
- `tests/widget/responsive.lua` covers 360x640, 600x800, 640x360, and a 1072x1448 PW12-sized
  portrait canvas, including panel-bound assertions for Settings, Help, Statistics, and a long-text
  win summary with oversized record markers.
