# komahjong-solitaire

A Mahjong Solitaire plugin for KOReader, optimized to run on an old Kindle Touch.

## Layout

- `mahjong.koplugin/` — the plugin deliverable (`_meta.lua` + `main.lua` + `icons/`)
- `example_app/casualkochess.koplugin/` — reference plugin used as a pattern
- `install_plugin.sh` — syncs the plugin to a Kindle mounted at `D:\`
- `tools/` — icon generator + icon QA tools (see Development)
- `tests/` — official headless test suite (`tests/run.sh`)
- `IMPLEMENTATION_PLAN.md` — locked design and user stories
- `AGENTS.md` — KOReader plugin development notes

## Status

The plugin launches "Mahjong Solitaire" from the **Tools** menu and renders the
full 144-tile Turtle board as an offset-layer 3D stack (US-01..US-06 done).
Tile-matching gameplay (select, match, remove, undo, scoring, persistence) is
not implemented yet.

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
