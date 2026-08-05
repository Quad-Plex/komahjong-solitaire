# US-01 — Plugin skeleton loads and shows a placeholder screen

As a player, I want to launch "Mahjong Solitaire" from the KOReader main menu so I can confirm
the plugin is installed and reachable.

- Create `mahjong.koplugin/` with `_meta.lua` and `main.lua`.
- `main.lua` extends `WidgetContainer`, `name = "mahjong"`, `is_doc_only = false`.
- Register to main menu (`sorting_hint = "tools"`, text "Mahjong Solitaire"); on callback show a
  temporary full-screen widget (or `InfoMessage`) so the entry is visibly wired up.
- Optionally register a Dispatcher action (`MahjongStart`) as in the example.

**Acceptance:**
- Structure matches AGENTS.md; `_meta.lua` returns correct table; `main.lua` returns a class.
- Menu item appears and, when tapped, displays the placeholder.
- No `require` errors at load; `luacheck` clean (if available).
