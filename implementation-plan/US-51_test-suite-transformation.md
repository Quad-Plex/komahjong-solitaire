# US-51 - Feature-driven test-suite transformation

As a developer, I want a feature-driven, contract-oriented test suite so that
each behavior has one clear owner, changes do not preserve obsolete story-era
assumptions, and new functionality can be covered without duplicating setup
and assertions.

## Why this exists

The existing harnesses were created beside individual user stories. That
history is useful, but it has left overlapping tests for gameplay, timers,
picker behavior, auto-solve, layouts, and e-ink refreshes. A change to one
feature can therefore fail several suites that each encode a different
historical version of the same contract. The suite must retain its extensive
regression coverage while making responsibility explicit.

## Scope

- Make `tests/manifest.lua` the authoritative, deterministic list of executable
  suites. `tests/run.sh` must not execute arbitrary Lua files by globbing.
- Organize ownership by feature domains: plugin/assets, pure game rules,
  scoring/penalties, persistence, lifetime stats, board widget, picker widget,
  layout contracts, gameplay, lifecycle, timer/pause, auto-solve, chrome and
  dialogs, localization, and e-ink refresh.
- Add shared test support for deterministic fixtures and picker interaction.
  Helpers are infrastructure, not executable suites.
- Consolidate duplicate checks into their owning feature suite. A behavior must
  have one primary owner; cross-feature suites may verify integration, but must
  not copy the owner suite's unit assertions.
- Move layout checks under one `contract/` ownership area while retaining every
  layout's counts, bounds, depth, fractional-coordinate landmarks, rendering,
  persistence, and picker checks. The current migration preserves each layout's
  detailed assertions; future layout work should consolidate common assertions
  into shared case data before adding more layout-specific checks.
- Preserve the real filesystem icon test, fresh `mock.newContext()` isolation,
  temporary-layout registration/deregistration, and explicit scheduled-task
  flushing. Do not bypass UI interaction paths in fixtures.
- Remove obsolete scroll-picker assertions. The current picker contract is a
  fixed three-column by four-row paged picker.

## Migration rules

The migration is complete only when the manifest points exclusively to
feature-owned paths below `tests/contract/`, `tests/unit/`,
`tests/widget/`, and `tests/integration/`. Root-level `usNN_*.lua` and other
story-era executable names must not remain. Story traceability belongs in this
plan and suite comments, not executable filenames.

The current ownership map is:

| Responsibility | Suite paths |
|---|---|
| Plugin/assets | `contract/assets.lua` |
| Rules/deadlock | `unit/solvable_deals.lua`, `integration/deadlock.lua` |
| Scoring/selection | `unit/scoring.lua`, `unit/penalties.lua`, `unit/combo_and_selection.lua` |
| Persistence/stats | `integration/persistence.lua`, `integration/win_and_stats.lua` |
| Board | `widget/board_geometry.lua`, `widget/board_paint.lua`, `widget/board_updates.lua` |
| Picker | `widget/picker_grid.lua`, `widget/picker_cards.lua`, `widget/picker_paging.lua`, `widget/picker_stats.lua`, `widget/help.lua` |
| Layout contracts | `contract/layout_*.lua` |
| Gameplay/lifecycle | `integration/gameplay.lua`, `integration/interaction_features.lua`, `integration/game_lifecycle.lua` |
| Timer/pause/auto-solve | `integration/timer.lua`, `integration/pause.lua`, `integration/autosolve*.lua` |
| Chrome/localization | `widget/chrome.lua`, `widget/stats_card.lua`, `widget/responsive.lua`, `integration/localization.lua`, `integration/locale_defaults.lua` |
| E-ink refresh | `integration/timer_refresh.lua`, `widget/lower_chrome.lua`, `integration/full_refresh.lua`, `integration/refresh_batching.lua`, `integration/render_safety.lua` |

The moved suites retain their assertion bodies during the first migration so
coverage is preserved byte-for-byte. Consolidation of repeated assertions is
performed only where the resulting feature contract retains the old edge cases.
New layouts extend shared layout data and the layout-contract owner rather than
cloning a story-specific test file.

The shared mock remains a behavioral contract. Its positional-child semantics,
`OverlapGroup:getSize()`, window-stack lifecycle, ConfirmBox behavior, and
snapshot scheduling must continue to model the device closely enough to catch
load and rendering failures.

## Acceptance criteria

1. `tests/run.sh` executes only manifest-listed suites and detects duplicate or
   missing entries.
2. The current suite remains green with no reduction in existing assertions.
3. Every current layout is represented by a contract suite below
   `tests/contract/`, with unique layout-specific edge cases retained.
4. Shared fixtures eliminate repeated picker-selection and board-fixture
   boilerplate without weakening integration paths.
5. E-ink refresh tests retain region scope, dirty-owner, ordering, identity
   guard, and deferred-retry assertions.
6. Documentation names the feature owner for each suite and no longer directs
   developers to create or manually register story-numbered test files.

## Verification

- `lua mahjong.koplugin/mahjonglogic.lua`
- `lua mahjong.koplugin/mahjonglayouts.lua`
- `lua mahjong.koplugin/mahjongstats.lua`
- `tests/run.sh`

No production plugin behavior is in scope for this story.
