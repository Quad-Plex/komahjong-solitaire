# US-22a — Extract board definitions into a dedicated module

As a developer, I want the layout definitions and registry extracted out of
`mahjonglogic.lua` into their own module so adding future boards (US-23..US-29)
is a single-file change.

## Why this exists

US-22 (Ziggurat) would otherwise have to carry this structural refactor too.
It is deliberately split out — and must ship BEFORE any US-23..US-29 board —
so those stories only add a spec entry in `mahjonglayouts.lua`, never touching
`mahjonglogic.lua`.

## Scope

- Create `mahjong.koplugin/mahjonglayouts.lua` (pure Lua, no `require("ui/...")`,
  same self-test convention as `mahjonglogic.lua`):
  - The four spec tables (`TURTLE_SPEC`, `SPIDER_SPEC`, `BRIDGE_SPEC`,
    `ZIGGURAT_SPEC`) and their `registerLayout` calls (moved verbatim from
    `mahjonglogic.lua`).
  - The registry (`layouts`) and the four per-id caches
    (`_layout_cache`/`_bounds_cache`/`_layout_key_cache`/`_max_layer_cache`).
  - `registerLayout`, new `deregisterLayout` (replaces the manual
    `layouts[id] = nil` + cache-nilling in tests), `layoutIds`, `layoutName`.
  - `posKey`, `buildLayout`, `maxLayer`, `gridBounds`, `isLayoutPosition`.
  - Embedded self-tests: per-layout shape checks (144 positions, per-layer
    counts, dedup, grid bounds, maxLayer) and registry behavior
    (sorted `layoutIds`, `layoutName` fallback, memoization, register/
    re-register/deregister).
- `mahjonglogic.lua` requires it and re-exports the API
  (`MahjongLogic.layouts/posKey/registerLayout/deregisterLayout/layoutIds/
  layoutName/buildLayout/maxLayer/gridBounds/isLayoutPosition`) so every
  existing caller (`main.lua`, `mahjongboard.lua`, `mahjonglayoutselect.lua`,
  the harnesses) is unchanged. `MahjongLogic.MAX_LAYER = 4` stays.
- Move the layout shape/registry self-tests out of `mahjonglogic.lua`'s
  `runSelfTests()` into the new module; keep the per-layout gameplay checks
  (deal / free tiles / hasMoves / persistence round-trip) in `mahjonglogic.lua`
  since they need the deck/removal logic. The toy-layout block there switches
  to `MahjongLogic.deregisterLayout("toy")`.
- Update `tests/mock.lua` preload list, add `mahjonglayouts` to `tests/run.sh`
  stage 3, and switch the harness toy-deregistration to `deregisterLayout`.
- Update `AGENTS.md` (repo layout + registry contract) and note the module in
  the US-22 story file.

**Test:** the existing suite stays green (logic self-tests, all harnesses) plus
the new `mahjonglayouts.lua` self-test stage in `tests/run.sh`.

**Acceptance:** a future layout story touches only `mahjonglayouts.lua` (spec +
shape self-test) and a `tests/usNN_*.lua` harness — `mahjonglogic.lua` is never
edited to add a board.
