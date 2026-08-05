# komahjong-solitaire

A Mahjong Solitaire plugin for KOReader, optimized to run on an old Kindle Touch.

## Layout

- `mahjong.koplugin/` — the plugin deliverable (`_meta.lua` + `main.lua` + `icons/`)
- `example_app/casualkochess.koplugin/` — reference plugin used as a pattern
- `install_plugin.sh` — syncs the plugin to a Kindle mounted at `D:\`
- `tools/` — icon generator + icon QA tools (see Development)
- `tests/` — official headless test suite (`tests/run.sh`)
- `IMPLEMENTATION_PLAN.md` — locked design overview + story index
- `implementation-plan/` — one file per user story (`_completed` = shipped)
- `AGENTS.md` — KOReader plugin development notes

## Status

The plugin launches "Mahjong Solitaire" from the **Tools** menu and renders the
full 144-tile Turtle board as an outward-bevel 3D stack. Core gameplay is in:
tap two matching free tiles to remove them, win when the board is clear, and a
dead board offers to reshuffle (US-01..US-09 done).

Recent improvements:
- **Scoring (US-09):** 10 points per matched pair, plus a +5 chain bonus when
  the consecutive match is of the same tile group (same suited/wind/dragon
  kind, or any flower after a flower / any season after a season). A blocked
  tile tap now shows a brief non-blocking "Tile is blocked" message in the band
  between the board and the toolbar — it never blocks a follow-up tap. A timer
  bonus is not implemented (no elapsed-time tracking yet — see scoring rules
  below).
- **Undo / Hint / Shuffle:** the toolbar now has undo (restores the removed
  pair, its score, and the chain state), a hint (highlights a matching free
  pair for 2s), and a confirm-gated reshuffle; dead boards prompt to shuffle
  instead of shuffling silently, with bounded auto-repeat.
- **Visual Feedback:** Fixed selection overlay transparency (tile symbols remain visible).
- **Bevel Logic:** Dynamic bevel restoration when neighbors are removed (no "floating" tiles).
- **Rule Accuracy:** Improved free-tile detection to handle partial and half-grid overlaps correctly.

Persistence and polish (US-10..US-11) are not implemented yet.

## Scoring rules

- **Base:** 10 points for every matched pair.
- **Chain bonus:** +5 when the new pair belongs to the same tile group as the
  immediately previous match — same suited/wind/dragon kind, or any flower
  after a flower, any season after a season. The chain spans shuffles and
  survives undo/redo correctly (undo restores the chain state).
- **Timer bonus:** not implemented (elapsed-time tracking is deferred).

## Install on a Kindle

```
./install_plugin.sh           # mount D: if needed, rsync, verify
./install_plugin.sh --unmount # install, then unmount D:
```

Then fully restart KOReader and open **Tools → Mahjong Solitaire**.

## Development

Game-logic modules are pure Lua so they can be tested headlessly. Run the
official suite with `tests/run.sh` (syntax check, `luacheck`, logic
self-tests, headless harnesses).

### Icon tooling (`tools/`)

The tile SVGs are **generated**, not hand-edited, so the set stays consistent.
Edit `tools/gen_icons.py` to redesign tiles, then regenerate and verify:

```
python3 tools/gen_icons.py            # rewrite mahjong.koplugin/icons/*.svg
python3 tools/gen_icons.py --check    # exit 1 if committed icons are stale
python3 tools/check_icons.py          # QA: XML valid, icons match generator,
                                      #   tiles touch with no gaps, symbols not clipped
python3 tools/preview.py              # render a board+strip PNG to eyeball changes
```

`check_icons.py` and `preview.py` need `lua` and `rsvg-convert` on PATH; the
rest is dependency-free.
