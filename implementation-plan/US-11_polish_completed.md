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
