# US-52 - Reliability, maintainability, and device-awake policy

As a maintainer and player, I want the Mahjong plugin's persistence and deal
guarantees to be stronger, its game controller easier to change safely, and
automatic standby inhibited only while a playable game is active, so that the
plugin remains reliable on e-ink devices as features continue to grow.

## Status

Planned. This story is intentionally implementation-only: complete it in a
fresh session after reading `AGENTS.md`, this story, and the current code.

## Decisions locked before implementation

- Scores are allowed to become negative. Hint and shuffle penalties must always
  deduct their full amount; do not clamp scores to zero.
- CI, rendered-icon enforcement, shell linting, release/versioning work, and a
  formal device/emulator QA checklist are out of scope.
- Only one optional product enhancement is in scope: preventing **automatic**
  standby while an active game is visible. Explicit power-button and sleep-cover
  behavior must remain under KOReader/device control.
- Preserve existing gameplay, e-ink refresh, save-format compatibility, and
  user-facing behavior unless a change below explicitly requires otherwise.

## Scope and implementation order

### 1. Persistence and documentation correctness

The negative-score behavior is current and intentional. Keep
`MahjongLogic.applyPenalty(score, amount)` as a subtracting operation and
preserve negative values through save/restore, undo, stats, and win summaries.

Harden `MahjongLogic.deserializeGameState()` so malformed data cannot restore
an impossible board. In addition to the existing layout/count/kind checks:

- Validate the complete tile multiset across the live board and flattened undo
  history against the canonical 144-tile deck multiplicities.
- Reject duplicate removed positions within history, including positions reused
  by separate history entries.
- Keep rejecting history positions that are present on the live board.
- Validate the history records as a coherent sequence where practical without
  breaking valid older v1/v2 saves. In particular, preserve compatibility for
  fields absent from older saves when the current loader already defaults them.
- Continue treating corrupt data as a fresh game: clear the saved key and show
  the layout picker rather than exposing an error to the player.

Update the feature-owned persistence tests with deliberately malformed fixtures
for duplicate history positions, impossible duplicate kinds, missing kinds, and
invalid live-board/history combinations. Keep a valid negative-score round trip
test.

Update docs/comments only where they still disagree with the current behavior.
Historical completed-story text may state its original requirement if it has an
explicit retrospective explaining the superseding rule.

### 2. Prove fresh deals are fully solvable

`MahjongLogic.newGame(id)` currently constructs random deals from a reverse
legal clear sequence, but the feature suite only proves that each board has an
opening move. Add a pure-Lua proof that a generated random deal can be cleared
legally without a shuffle.

Choose the smallest design that keeps runtime production behavior unchanged:

- Prefer a deterministic pure test solver/replayer that repeatedly chooses
  legal matching free pairs and backtracks only when necessary.
- Alternatively, have the deal builder expose a test-only solution witness
  without retaining it in persisted game state or adding UI dependencies.
- Do not change seeded-deal compatibility: `newGame("layout", seed)` and the
  legacy `newGame(seed)` call shape must remain byte-identical.

For every registered built-in layout, test multiple nil-RNG fresh deals and
prove all 72 pairs can be removed legally. Retain the existing opening-move and
non-permanent-dead assertions as inexpensive smoke checks.

Add invariant tests, in their existing feature-owned suites, covering:

- deck multiplicity after deal;
- board integrity after match, undo, and shuffle;
- persistence round trips after legal state transitions;
- deterministic ordering/freeness behavior where it is already contractually
  required.

### 3. Refactor `main.lua` incrementally

`mahjong.koplugin/main.lua` owns too many unrelated concerns. Preserve it as
the top-level game/widget lifecycle coordinator, but extract behavior into
focused modules in this order:

1. **Timer module:** elapsed-time state, start/stop lifecycle, mode selection,
   and timer repaint scheduling.
2. **Gameplay module:** selection, match application, score/combo state, undo,
   hints, and shuffle coordination.
3. **Transition module:** identity/token-guarded deferred work for structural
   repaint retries, win/dead-board dialogs, picker replacement, and modal-safe
   rebuilds.
4. **Chrome-refresh helper:** deferred lower-chrome repaint batching and any
   tightly related board/chrome handoff helpers.

Requirements:

- Keep KOReader UI requires out of pure game-rule modules.
- Do not perform a broad rewrite. Extract one concern at a time, run the suite
  after each extraction, and preserve current public methods until callers and
  tests are migrated.
- Preserve all stale-callback guards, board identity checks, timer run tokens,
  e-ink local-refresh contracts, and modal ordering behavior described in
  `AGENTS.md`.
- Add focused tests for each extracted module's boundary. Existing integration
  tests must continue to exercise the real composition through `main.lua`.

### 4. Improve test-runner signal

Keep `tests/manifest.lua` authoritative and retain all assertions, but reduce
repetitive success output from high-volume layout checks. Favor one concise
success summary per logical layout/assertion group while retaining the position,
layout id, and expected/actual values in failure messages.

Do not remove coverage merely to shorten output. `tests/run.sh` must still run
syntax checks, lint when installed, pure-module self-tests, and only the
manifest-listed suites.

### 5. Keep the device awake during active play

Use KOReader's device abstraction:

```lua
Device:setAutoStandby(false) -- inhibit automatic standby
Device:setAutoStandby(true)  -- restore normal automatic standby
```

Implement a small, idempotent ownership helper in the game lifecycle. It must
not call platform shell commands or Kindle-specific APIs directly.

Inhibit automatic standby only when a non-won board is active and visible for
play. Restore normal standby on every path where that condition ends, including:

- plugin close and exit confirmation;
- first-launch picker with no game underneath;
- opening the picker over a running game, then returning, replacing, or closing;
- win summary and dead-board terminal states;
- new-game replacement;
- auto-solve completion or terminal failure;
- any framework-driven `onCloseWidget()` path.

Pause behavior is a product detail to preserve deliberately: a paused game is
still an active game session, so retain the wake lock while the pause overlay is
shown unless device testing demonstrates that this is inappropriate. Never
interfere with explicit power-button or sleep-cover suspension.

Extend `tests/mock.lua` with `Device:setAutoStandby()` call capture and add
feature-owned lifecycle tests that verify balanced, idempotent transitions. The
tests must prove a closed/replaced game cannot leave automatic standby disabled.

## Out of scope

- New layouts, scoring changes, new gameplay controls, themes, keyboard/d-pad
  support, onboarding, or new languages.
- GitHub Actions or any other CI configuration.
- Mandatory rendered SVG checks, shell linting, release tooling, changelog
  policy, or a manual QA checklist.
- Changes to normal explicit device suspend behavior.

## Acceptance criteria

1. Scores may be negative everywhere, and documentation/tests no longer claim
   that penalties clamp them to zero.
2. Corrupt saved states with invalid tile multiplicities or duplicate history
   positions are rejected and replaced with a fresh-game flow.
3. Multiple random fresh deals for every built-in layout are proven legally
   clearable without shuffling; seeded deals retain their existing results.
4. `main.lua` delegates timer, gameplay, transition, and chrome-refresh
   responsibilities to focused modules without behavioral regressions.
5. The full test suite remains green, retains current coverage, and produces
   substantially less repetitive successful output.
6. Automatic standby is inhibited only during an active playable game and is
   restored reliably across all close, picker, terminal, and replacement paths.
7. Explicit power-button and sleep-cover handling remain unchanged.

## Verification

Run after each incremental step and once at completion:

```sh
lua mahjong.koplugin/mahjonglogic.lua
lua mahjong.koplugin/mahjonglayouts.lua
lua mahjong.koplugin/mahjongstats.lua
tests/run.sh
python3 tools/gen_icons.py --check
python3 tools/check_icons.py
```

The rendered portion of `check_icons.py` may remain skipped when
`rsvg-convert` is unavailable; installing or enforcing that dependency is out
of scope for this story.
