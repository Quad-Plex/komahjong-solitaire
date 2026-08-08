# US-37 - English/German localization with runtime language selection

## Goal

Replace the current mixture of English literals, KOReader `gettext` calls, and
display names stored directly in the layout registry with one plugin-owned
localization system. The first supported languages are English (`en`) and
German (`de`). Every user-facing string in the Mahjong plugin must come from
that system, and the language must be selectable from the existing settings
dialog even when the user is still on the layout picker.

## Current-state constraints

- Most UI modules already call `require("gettext")`, but KOReader's gettext
  locale is not an app-level setting and cannot be changed reliably while the
  plugin is running.
- `mahjonghelp.lua` builds some sentences by concatenating lines before
  translating them, which prevents clean catalog extraction and makes German
  line wrapping difficult.
- Layout names are currently held as English display strings by
  `mahjonglayouts.lua` and are used by the picker, stats, and win summary.
- The layout picker currently has a help button and close button in its title
  row. It needs a settings button immediately beside the help button.
- Existing saved games, stats, and settings must remain readable. Language is
  a preference, not part of a game position or a stats record.

## Design

### 1. Plugin-owned localization module

Add `mahjong.koplugin/mahjongi18n.lua`, a pure Lua module with:

- Supported locale metadata: `en`, `de`, display labels `English` and
  `Deutsch`, and a deterministic fallback to `en` for missing/invalid values.
- A stable-key catalog, with English and German entries in the same module (or
  adjacent data files if the catalog becomes too large).
- `getLanguage()`, `setLanguage(language)`, `supportedLanguages()`, and
  `translate(key, ...)`/equivalent placeholder formatting.
- No UI or `LuaSettings` dependency. The active language is set by `main.lua`
  after reading the persisted preference, which keeps the module testable with
  plain Lua.
- No translation of arbitrary concatenated strings. Dynamic text must use
  keyed templates with named or positional placeholders.

Use semantic keys such as `settings.title`, `toolbar.hint`,
`win.overall_best_score`, `help.free_tile_rule`, and `layout.turtle`, rather
than English sentences as keys. Keep numbers, tile IDs, layout IDs, and
persisted enum values language-neutral.

### 2. Language lifecycle and persistence

- Add a `language` setting to `SETTINGS_DEFAULTS`, defaulting to `en`.
- On first launch, when the setting is absent, inspect KOReader's active
  gettext locale (`current_lang`): German locales (`de`, `de_DE`, `de-DE`,
  and equivalent variants) select `de`; English and all other locales select
  `en`. Persist that initial choice so it is not re-detected on later starts.
- Read and validate an existing setting during plugin initialization; invalid
  values fall back to `en` without touching unrelated saved data.
- Add `Mahjong:setLanguage(language)` as the owner-level operation. It validates
  the locale, updates `mahjongi18n`, persists the setting, and rebuilds the
  currently visible UI surface.
- Language changes must not reset the board, timer, undo history, score,
  autosolve state, or lifetime stats.
- If a modal is open, close/recreate it with the new language rather than
  mutating only a subset of child labels. If the picker is underneath settings,
  rebuild the picker after applying the language and preserve its current
  mode, layout cards, scroll position when practical, and close behavior.
- Ensure timers and scheduled callbacks do not create duplicate widgets or
  resume a paused timer twice during a language refresh.

### 3. Settings UI

- Add a `Language` row to `mahjongsettings.lua`.
- Cycle through the supported languages, showing native labels (`English`,
  `Deutsch`) and sizing the value button from the widest translated value.
- Include the language row in reset-to-defaults, unsaved-change handling, save,
  and cancel behavior. Saving applies the change; tapping outside or close
  discards it.
- Translate the settings title, row labels, value labels, buttons, and all
  timer/score option text through the catalog.
- Rebuild/remeasure the card for German strings instead of assuming English
  widths. The timer interval control must retain its disabled behavior in
  interaction-only mode.

### 4. Layout picker entry point

- Add a settings gear button next to the existing `?` help button in
  `mahjonglayoutselect.lua`.
- Expose an `onSettings` callback alongside `onHelp`; `main.lua` opens the same
  `SettingsWidget` used from the game HUD.
- Keep the picker opaque and modal while settings is shown. A language change
  must return to a correctly localized picker; cancel must return to the
  unchanged picker.
- Recalculate title centering and button spacing for the additional control,
  including small screens and the existing scroll/crop behavior.
- Translate the picker title, close/settings/help affordance labels where
  applicable, all layout card names, and score/time badge text if any text is
  added to those badges.

### 5. Full string audit and migration

Replace direct user-facing literals and existing `gettext` calls in:

- `_meta.lua` plugin metadata, with the documented limitation that metadata is
  loaded by KOReader before the app preference exists; use KOReader-compatible
  translation wrapping/catalog entries for that surface.
- `main.lua`: menu entry, toolbar, HUD title, exit/dead-board/shuffle/win
  dialogs, flash messages, combo messages, autosolve status, win summary, and
  button labels.
- `hudbar.lua`: stat chip labels and any accessible text.
- `mahjongsettings.lua`: all settings text and language labels.
- `mahjongstatswidget.lua`: headings, stat labels, reset confirmation, and
  layout column names.
- `mahjongpause.lua` and `mahjongwinsummary.lua`: titles, explanatory text,
  and actions.
- `mahjonglayoutselect.lua`: picker title, layout names, and any user-facing
  card/badge text.
- `mahjonghelp.lua`: convert help pages to structured keyed paragraphs and
  headings. Translate each complete sentence/paragraph, preserve intentional
  line breaks only where needed, and keep tile icon IDs separate from prose.

Do not translate internal identifiers, SVG filenames, log/self-test messages,
or pure logic values. Add a code-review/search check for user-facing widget
fields (`text`, `label`, `title`, dialog messages, and formatted flash text)
that bypass `mahjongi18n`.

### 6. Layout display names

Keep canonical layout IDs unchanged for saves and stats. Replace direct display
names in `mahjonglayouts.lua` with stable localization keys or add a
`layoutNameKey(id)` API. UI callers resolve the key through `mahjongi18n`, so
the same layout is shown as German everywhere without changing persistence.
All twelve built-in layouts, including Crab, must have English and German
names. Unknown/custom registered layouts use their supplied name as an English
fallback and never break the picker.

## Acceptance criteria

- A fresh install on a German KOReader opens in German; English and all other
  KOReader locales open in English. An explicit saved language preference
  always takes precedence over KOReader's locale.
- Selecting `Deutsch` in Settings and saving translates every visible game,
  picker, help, stats, pause, and win-summary string to German.
- Selecting `English` restores English, and the choice survives plugin/KOReader
  restart.
- Changing language from the picker works through the new gear button placed
  beside help; canceling settings leaves the picker unchanged.
- Changing language during an active game preserves board state, timer elapsed
  time, selection/overlays where safe, score, history, and stats.
- German strings are not truncated in settings, picker titles, HUD chips, or
  dialogs on the supported screen sizes.
- Layout IDs and saved game/stat schemas are unchanged; corrupt/unknown
  language values safely fall back to English.
- No user-facing plugin string remains untranslated or is accidentally passed
  through KOReader's global locale instead of the plugin locale.

## Tests and verification

Add `tests/us37_localization.lua` and register it in `tests/run.sh`.

The headless test should verify:

- catalog key coverage for both locales and fallback behavior;
- language setting default, validation, persistence, reset, save, and cancel;
- translated settings values and widest-value sizing inputs;
- picker title-row order: settings button, help button, centered title, close;
- opening settings from the picker and returning to the picker after cancel/save;
- language changes rebuild the visible surface without changing game state;
- every built-in layout has localized display names while IDs remain stable;
- representative translations from HUD, help, stats, pause, dialogs, flash
  messages, and win summary;
- no duplicate timer polling or stale modal callback after a language refresh.

Run the existing verification workflow in addition to the new test:

```text
tests/run.sh
luacheck mahjong.koplugin/
```

Perform a device/emulator pass in both languages, concentrating on German
wrapping, the picker title row, every modal opened from the picker, and e-ink
full-refresh behavior after saving a language change.

## Implementation order

1. Add the pure catalog module and its self-tests.
2. Add language loading, validation, persistence, and owner-level refresh
   plumbing in `main.lua`.
3. Add the Settings language row and translate/rebuild the settings dialog.
4. Add the picker settings button and picker/modal lifecycle handling.
5. Migrate layout names and all UI/help strings module by module.
6. Add the US-37 harness, run the full suite, then perform device/emulator QA.

## Non-goals

- Changing KOReader's global language or translating unrelated KOReader UI.
- Translating tile artwork or icon filenames.
- Adding languages beyond English and German in this story.
- Changing saved layout IDs, game-state versions, stats schema, or scoring rules.
