# komahjong-solitaire

A Mahjong Solitaire plugin for KOReader, optimized to run on an old Kindle Touch.

## Layout

- `mahjong.koplugin/` — the plugin deliverable (`_meta.lua` + `main.lua`)
- `example_app/casualkochess.koplugin/` — reference plugin used as a pattern
- `install_plugin.sh` — syncs the plugin to a Kindle mounted at `D:\`
- `IMPLEMENTATION_PLAN.md` — locked design and user stories
- `AGENTS.md` — KOReader plugin development notes

## Status

Initial skeleton only: the plugin registers a "Mahjong Solitaire" entry under
**Tools** and opens a full-screen shell (board stub, New Game toolbar, title bar
with exit confirm). Game logic and tiles are not implemented yet.

## Install on a Kindle

```
./install_plugin.sh           # mount D: if needed, rsync, verify
./install_plugin.sh --unmount # install, then unmount D:
```

Then fully restart KOReader and open **Tools → Mahjong Solitaire**.

## Development

Game-logic modules are written as pure Lua so they can be tested headlessly.
Syntax check with `luac -p`, lint with `luacheck mahjong.koplugin/`.
