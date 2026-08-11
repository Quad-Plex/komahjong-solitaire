# US-53 - Incremental game-controller module extraction

As a maintainer, I want `main.lua` split along stable controller boundaries
without changing Mahjong Solitaire behavior, so that future features can be
implemented and reviewed without risking timer, e-ink, persistence, or modal
lifecycle regressions.

## Status

Completed. This was the deliberately deferred refactor portion of US-52. The
implementation keeps `main.lua` as the lifecycle/public-method facade and adds
`mahjongtimer.lua`, `mahjonggameplay.lua`, `mahjongtransitions.lua`, and
`mahjongchrome.lua`. Timer and chrome logic moved into their controllers;
gameplay and transition public boundaries delegate through their controllers to
private owner implementations, preserving callback shapes and token/identity
guards without introducing a second stateful controller.

## Goal and non-goal

`mahjong.koplugin/main.lua` remains the KOReader plugin class and the one
top-level lifecycle owner. It must still own widget construction, settings,
stats, board state, window-stack interactions, and public methods used by the
existing harnesses. This story extracts implementation detail, not behavior.

Do not attempt a broad rewrite or a framework. Do not change gameplay rules,
save format, translations, generated icons, layouts, widget hierarchy, refresh
regions, or user-visible strings. Do not add a second controller object that
duplicates `Mahjong` state.

## Preconditions

1. Read `AGENTS.md`, especially the e-ink dirtying, modal sequencing, and
   stale-callback rules.
2. Read US-52 and this story fully.
3. Start from a green `tests/run.sh` worktree. Run the full suite after every
   extraction, not just once at the end.
4. Preserve Lua 5.1 compatibility. Do not introduce `goto`, bit operators,
   `table.unpack`, or new runtime dependencies.

## Existing ownership contracts

- `MahjongLogic`, `MahjongLayouts`, and `MahjongStats` stay pure. They must not
  require KOReader UI modules, `Device`, or `UIManager`.
- `Mahjong` owns live state: `board`, `history`, `score`, selection/hint/combo
  fields, `board_view`, chrome widgets, dialog references, settings, stats,
  layout, and lifecycle tokens.
- Extracted controller modules receive `self` explicitly and mutate only this
  existing owner. They return ordinary Lua tables of functions; they do not
  construct a new class or retain global mutable state.
- `main.lua` remains the compatibility façade. Existing public methods, tests,
  dispatcher handlers, toolbar callbacks, and dialog callbacks must retain
  their names and calling shapes. A façade method may delegate internally.
- Require dependencies at a module top level. Avoid dependency cycles: helpers
  may require KOReader modules and pure logic modules, but must never require
  `main.lua`.

## Extraction order

Extract one concern at a time. Commit only after its focused tests and the
complete suite pass. Do not combine steps merely because nearby code happens
to be related.

### 1. Timer controller

Create `mahjongtimer.lua`. Move only these responsibilities:

- timer mode and interval lookup;
- elapsed-time calculation;
- start/stop/reset lifecycle;
- run-id invalidation;
- periodic polling scheduling;
- timer text update and timer-region repaint scheduling.

The module must expose functions that are called as, for example,
`Timer.start(self)` and `Timer.stop(self)`. Keep `Mahjong:startTimer()`,
`stopTimer()`, `resetTimer()`, `getElapsed()`, `timerMode()`,
`timerInterval()`, `updateTimerText()`, `refreshTimerDisplay()`, and
`updateTimerDisplay()` as thin delegates initially.

Required invariants:

- `stopTimer()` freezes `elapsed_base` once and invalidates every pending poll.
- `startTimer()` increments the run token before scheduling work. A stale tick
  must never repaint a replaced, closed, paused, or picker-covered game.
- "On interaction" updates text but does not create a polling loop.
- "Periodic" has one timer repaint source. It must defer while
  `board_view:has_pending_refresh_retry()` is true.
- Hint pulses retain their current coupling to timer lifecycle: stopping the
  timer invalidates a pulse; starting it resumes a live hint pulse.
- Repaint targets remain the window-level game widget and retain explicit,
  stable screen-space regions. Do not turn regional updates into regionless
  refreshes.

Add a focused timer-module boundary suite or extend `integration/timer.lua`
to prove direct delegate behavior and stale scheduled callbacks. Keep the
existing real-composition tests unchanged.

### 2. Gameplay controller

Create `mahjonggameplay.lua`. Move selection, matching, undo, hint, and
shuffle coordination in small slices, preserving public `Mahjong` methods.
Recommended sequence:

1. selection/hint clear and overlay batching;
2. `applyMatch` and score/combo/history persistence;
3. undo;
4. hint cycling and penalties;
5. manual/dead-board shuffle candidate search.

The module may call pure `MahjongLogic` and owner methods supplied by the
facade, but must not own dialogs, widget construction, or terminal transition
scheduling. Keep terminal decisions in the transition controller below.

Required invariants:

- Mutate the logic board before mutating the board widget.
- Pair removal uses `board_view:removePair`; never rebuild all tile widgets.
- Preserve history fields and serialization exactly, including `prev_last`,
  combo fields, negative scores, hint/shuffle counters, and autosolve taint.
- Hint penalties charge once per hint session. Hints reset fast-clear combo
  timing but not the same-group chain reward.
- Undo never refunds penalties.
- Keep `clearHintBatched()` and selection transitions in a single local refresh
  batch. Do not introduce an intermediate repaint that can leave stale overlays.
- User shuffle confirmation remains modal-safe: its callback must defer the
  board rebuild until the modal clear repaint has an intervening UI tick.
- The auto-solve input lock remains absolute. Gameplay entry points must remain
  silent no-ops while `_auto_solve_active` is true.

Add focused tests for each extracted boundary while retaining current gameplay,
scoring, penalty, auto-solve, and refresh-batching integration suites.

### 3. Transition controller

Create `mahjongtransitions.lua`. Move only identity/token-guarded deferred
transition work:

- structural-refresh retries and full-screen restart refresh scheduling;
- no-moves and win deferred dialog sequencing;
- dead-board terminal scheduling;
- picker replacement and modal-safe new-game replacement helpers;
- close-time invalidation helpers where it is safe to centralize them.

Keep actual UI composition and dialog content in `main.lua` at first. The
module should schedule/guard callbacks, not become a generic dialog framework.

Required invariants:

- Every deferred callback captures enough identity (`board`, `board_view`, and
  relevant monotonically increasing token) to become inert after close, new
  game, picker replacement, or a board rebuild.
- A nested widget cannot be dirtied as the only paint target. Deferred work
  dirties the window-level owner or the established board helper.
- Final-pair flow must allow the local structural repaint and its deferred retry
  to drain before a covers-fullscreen win card is shown.
- Dead-board and shuffle dialogs are deferred after structural mutation; do not
  cover an unpainted changed board.
- ConfirmBox `ok_callback` runs before its own close. Any operation rebuilding
  the board must use `tickAfterNext`, not an inline rebuild or a plain
  `nextTick` where the modal repaint still races.
- Picker close/replacement retains its full-refresh behavior and never returns
  to a won empty board.
- Terminal transitions remain input locks until resolved or deliberately
  superseded. A stale callback must never open a dialog over a new board.

Extend `integration/render_safety.lua`, `integration/full_refresh.lua`,
`integration/deadlock.lua`, and picker tests rather than adding a parallel
test harness that bypasses real `main.lua` composition.

### 4. Chrome-refresh helper

Create `mahjongchrome.lua`. Move only lower-chrome region computation helpers,
chrome baking, deferred batching, and settle retry mechanics. Layout assembly
stays in `main.lua`; it owns the widgets and assigns stable regions.

Required invariants:

- Keep the board, HUD, feedback band, and toolbar refresh regions in screen
  coordinates.
- A pair clear keeps its first refresh board-local. HUD/timer/flash changes
  defer through one coalesced chrome pass rather than merging with the board
  mutation batch.
- `bakeLowerChrome()` paints the current flash and toolbar trees into the
  framebuffer before the EPDC samples the explicit lower-chrome region.
- Counter-pill structural changes retain the one guarded settling retry.
- Do not use a regionless `setDirty(..., "ui")` in a hot gameplay path.

Extend `widget/lower_chrome.lua`, `integration/timer_refresh.lua`, and
`integration/refresh_batching.lua` to exercise the module through the facade.

## Awake-policy coordination

`mahjongawake.lua` is intentionally a separate idempotent ownership helper.
Do not fold platform behavior into any controller module. All extracted code
must preserve this condition:

```
awake lock held <=> a non-won, non-terminal board is visible for play
```

Important exceptions already established by product behavior:

- Pause retains the lock because the paused board remains an active session.
- Picker, settings, stats, help, exit/shuffle confirmation, win/dead-board
  terminal cards, and auto-solve release the lock while gameplay is covered or
  unavailable.
- Returning to an eligible visible board reacquires it exactly once.
- Explicit power-button and sleep-cover behavior remains KOReader/device-owned.

Keep `integration/awake_policy.lua` passing and add cases whenever an
extraction moves a path that can cover, replace, resume, or close a game.

## Testing and review checklist

After each extraction step run:

```sh
lua mahjong.koplugin/mahjonglogic.lua
lua mahjong.koplugin/mahjonglayouts.lua
lua mahjong.koplugin/mahjongstats.lua
tests/run.sh
```

At story completion also run:

```sh
python3 tools/gen_icons.py --check
python3 tools/check_icons.py
```

Review the diff specifically for:

- added or removed `UIManager:scheduleIn`, `nextTick`, and `tickAfterNext` calls;
- lost token/identity guards;
- changed `setDirty` owner, refresh type, or region;
- public `Mahjong` method signature changes;
- new cyclic `require`s;
- state copied into a helper instead of remaining on `self`;
- broadened refreshes and modal callbacks that rebuild synchronously.

Perform a device/emulator smoke pass after each module boundary lands: start,
restore, select/match/undo/hint/shuffle, pause/resume, picker return and
replacement, settings/stats/help close, dead board, win, auto-solve, and close
during every modal state.

## Acceptance criteria

1. `main.lua` remains the lifecycle façade but delegates timer, gameplay,
   transitions, and chrome batching to four focused modules.
2. Every existing public controller method and persisted save behavior is
   preserved.
3. Pure game-rule modules remain free of KOReader UI dependencies.
4. Stale callbacks, modal ordering, local e-ink refresh behavior, and awake
   policy are unchanged or gain targeted regression coverage.
5. Each module has focused boundary coverage and the complete manifest suite
   remains green.
6. No user-visible behavior changes are introduced solely by this refactor.

## Out of scope

- New gameplay features, layouts, themes, translations, or scoring changes.
- Save-format migrations unrelated to compatibility fixes found during work.
- Replacing the feature-driven harness or modifying its manifest authority.
- UI redesign or a large widget-tree rewrite.
