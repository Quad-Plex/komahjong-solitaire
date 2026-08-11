# komahjong-solitaire

A Mahjong Solitaire plugin for KOReader, optimized to run on an old Kindle Touch.

## Layout

- `mahjong.koplugin/` — the plugin deliverable (see the module map in `AGENTS.md`)
- `example_app/casualkochess.koplugin/` — reference plugin used as a pattern
- `install_plugin.sh` — syncs the plugin to a Kindle mounted at `D:\`
- `tools/` — icon generator + icon QA tools (see Development)
- `tests/` — official headless test suite (`tests/run.sh`)
- `IMPLEMENTATION_PLAN.md` — locked design overview + story index
- `implementation-plan/` — one file per user story (`_completed` = shipped)
- `AGENTS.md` — KOReader plugin development notes

## Status

All user stories through **US-50**, plus **US-52** and **US-53**, are shipped
(`US-01..US-31`, `US-22a`, `US-32`, `US-33`, `US-37`, `US-48..US-50`,
`US-52..US-53`); `IMPLEMENTATION_PLAN.md` and the story files under
`implementation-plan/` are the source of truth for design decisions and the
per-story history.

The plugin launches "Mahjong Solitaire" from the **Tools** menu. Core gameplay:
tap two matching free tiles to remove them, win when the board is clear. The
board renders as an outward-bevel 3D stack of 144 tiles.

Features:

- **24 layouts:** Turtle, Spider, Bridge, Ziggurat, Cloud, Tic-Tac-Toe, Red
  Dragon, Overpass, Pyramid's Walls, Confounding Cross, Taipei, Crab, Hare, Horse,
  Tiger, Ram, Monkey, Rooster, Dog, Snake, Boar, Ox, Wedges, and Hourglass. The
  first twelve are transcriptions of the GNOME Mahjongg maps; the twelve compact
  multi-layer layouts come from PySolFC. Choosing a layout from the full-screen
  **layout picker** is how you start a New Game; picker
  cards show a thumbnail schematic, a per-layout win-count trophy badge, and a
  per-layout best-score chip (when a human win has recorded one). US-48 replaces
  picker scrolling with fixed 3x4 pages; the twelve compact 144-tile PySolFC
  layouts from US-49 and US-50 fill the second page.
- **3D board:** portrait tiles on a shared grid, each upper layer shifted
  up-left by exactly one bevel so raised tiles' bevels step cleanly onto the
  tiles beneath; dynamic bevel restoration when neighbours are removed. Local
  updates are clipped to the board canvas and terminal dialogs wait for a final
  structural repaint to settle, avoiding stale or garbled e-ink frames.
- **Scoring:** 10 points per pair plus a +50 chain bonus for consecutive matches
  of the same group (suited/wind/dragon kind, or flower→flower / season→season),
  with escalating fast-clear combo bonuses. **Penalties (US-18):** a hint costs 5
  and a manual shuffle costs 10, charged once per hint *session* (US-20) and
  never refunded by undo. Per-game `hints_used` / `shuffles_used` are shown in
  the win summary.
- **Undo / Hint / Shuffle:** undo restores the pair, score, and chain state; a
  hint highlights a matching free pair (long-press the Hint button to
  **auto-solve** the whole board, US-19/33); shuffle is confirm-gated and
  dead boards evaluate 15 background shuffles and keep the arrangement with
  the most available matching free pairs, with bounded auto-repeat if needed.
- **Failure recognition (US-32):** a provably-dead board (e.g. the last two
  copies of a kind stacked in one column) triggers a loss dialog with
  New Game / Close / Undo instead of an endless shuffle loop; a retries-exhausted
  fallback catches exotic deadlocks. The no-moves shuffle prompt pauses the
  clock until a playable shuffle is found.
- **Pause (US-17):** a bottom-toolbar button freezes the clock behind a
  tap-consuming overlay; the clock restarts exactly once on resume.
- **Timer:** elapsed seconds always accrue; the mode controls only when the
  mm:ss repaints (`interval` poll vs. on-interaction).
- **Persistence:** game state and settings live in one `LuaSettings` file;
  a won board is not saved, corrupt/tainted saves start fresh (a save tainted
  by a mid-solve close auto-resumes the solver). Settings include the
  `deselect_on_empty` toggle: when enabled, tapping empty board space clears
  the selected tile; when disabled, the selection remains until it is matched
  or replaced by another viable tile.
- **Win summary + stats (US-12/13):** a win dialog plus a lifetime-stats screen
  (games won, average time per win, and the rest of the `MahjongStats` record)
  with a confirm-gated reset.
- **Localization:** English and German are supported. On first launch, the
  plugin detects KOReader's locale and selects German for German locales;
  English is used for English and all other locales. The language can then be
  changed from Mahjong's Settings.

## Scoring rules

- **Base:** 10 points for every matched pair.
- **Chain bonus:** +50 when the new pair belongs to the same tile group as the
  immediately previous match — same suited/wind/dragon kind, or any flower
  after a flower, any season after a season. The chain spans shuffles and
  survives undo correctly. This chain scoring is always enabled.
- **Penalties:** a hint shown costs 5 (`HINT_PENALTY`) and a user-initiated
  shuffle costs 10 (`SHUFFLE_PENALTY`), may reduce the score below zero, and is
  never refunded by undo. The hint penalty is charged once per hint session (until the next pair
  is cleared), so re-hints are free. Auto-solve and auto-repeat shuffles never
  re-charge.
- **Timer bonus:** not implemented (no time-based scoring).

## Install on a Kindle

```
./install_plugin.sh           # mount D: if needed, rsync, verify
./install_plugin.sh --unmount # install, then unmount D:
```

Then fully restart KOReader and open **Tools → Mahjong Solitaire**.

## Development

Game-logic modules are pure Lua so they can be tested headlessly. Run the
official feature-driven suite with `tests/run.sh` (syntax check, `luacheck`,
logic self-tests, and the deterministic suites listed in
`tests/manifest.lua`). Shared files under `tests/support/` are fixtures, not
executable suites.

`main.lua` is the only KOReader plugin/lifecycle owner and compatibility facade.
Controller details are split into `mahjongtimer.lua`, `mahjonggameplay.lua`,
`mahjongtransitions.lua`, and `mahjongchrome.lua`; see `AGENTS.md` for their
strict ownership and callback/refresh contracts before changing game flow.

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
