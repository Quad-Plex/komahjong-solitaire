# US-38 - Paged layout picker (two fixed 3x4 pages)

As a player, I want the layout picker to retain its readable 3-column by
4-row card grid while offering a small page selector below it, so I can choose
from more than twelve layouts without scrolling or making cards hard to read.

## Context

The picker currently makes one dynamically tall grid and wraps it in a
`ScrollableContainer` (US-21). It was appropriate while the collection could
grow without a known bound, but it is inferior for the e-ink target: scrolling
is less discoverable than paging, card height changes as layouts are added,
and the card grid can run below the screen.

US-39 and US-40 add twelve layouts to the current twelve built-ins. This story
is their prerequisite: the picker has exactly **two pages**, each with twelve
cards in a fixed **3 columns x 4 rows** grid. Page one remains the current
sorted first twelve maps; page two holds the sorted next twelve maps. The
registry remains the single source of ordering (`MahjongLogic.layoutIds()`).

## Implementation

### 1. Replace scrolling with page state

In `mahjong.koplugin/mahjonglayoutselect.lua`:

- Remove `ScrollableContainer` / `SVContainer` and its `require`.
- Remove `_grid_scroller`, `cropping_widget`, and all scroll-specific geometry
  and comments. The picker is an opaque, non-scrolling full-screen
  `InputContainer`; card positions are therefore stable widget-local screen
  positions.
- Add `page = 1` and derive `page_count = math.max(1, math.ceil(#ids / 12))`.
  `page` is clamped to `1..page_count` in `init()` so an instance rebuilt after
  a registry change cannot address a missing page.
- Slice the sorted id list for the active page: slots `1..12` map to global
  positions `(page - 1) * 12 + 1 .. page * 12`. The grid always has four rows,
  including transparent placeholders in a partially populated final page.
- Preserve the current 3-column layout on the supported e-ink canvases.
  Remove the two-column narrow-phone branch rather than changing the page
  capacity: a page is always 12 cards and US-39/40 must result in exactly two
  pages. Use existing screen-relative padding, font and thumbnail scaling so
  the 3 columns still fit a narrow display.

### 2. Make vertical space for the footer

Reserve a fixed footer band below the cards, using the same controls and
visual sizes as `mahjonghelp.lua`'s `buildPage()`:

```lua
local left = ButtonWidget:new{ text = "<-", ... }
local indicator = label(string.format("%d/%d", self.page, page_count), 15)
local right = ButtonWidget:new{ text = "->", ... }
```

Use the actual arrow glyphs already used by Help (`"←"` and `"→"`), not the
ASCII illustration above. The footer is horizontally centered beneath the
grid, with the same 34dp buttons, 14dp gaps, centered `N/N` indicator, and
disabled boundary button behavior as Help:

- Page 1 disables the left arrow.
- The last page disables the right arrow.
- A page-arrow callback updates `self.page`, rebuilds the page content and
  dirties the picker with one full UI repaint. It must not start, stop or resume
  the background game's timer.

The footer consumes about 34dp plus a small gap. Keep the 3x4 geometry by
reducing each card's vertical allocation slightly (approximately 10-15dp on a
Kindle-sized screen), rather than shrinking widths, names, badges or chips.
This deliberately makes the individual schematic tiles in `layoutThumbnail`
slightly shorter through its existing fit calculation; do not introduce a
separate distortion or alter the portrait tile aspect ratio. The thumbnail
receives the remaining card height and continues to use `layoutThumbnail`; its
mass-centering and score/time/win overlays are unchanged. Do not introduce a
minimum `card_h` that forces the fourth row or the footer off screen.

Keep the title row and close/settings/stats/help callbacks unchanged. Close,
help, settings and stats must be usable from either page. Reopening the picker
creates a new instance and begins at page 1; no page preference is persisted.

### 3. Hit testing and tap feedback

`_card_rects` contains only the active page's cards. It is recreated whenever
the page changes, so a card tap can only select a visible card. Existing
pressed-card feedback and its deferred `_finishPick` guard remain unchanged.
Changing pages clears `_pending_pick`; a previously scheduled deal must become
a no-op if the page has changed or the picker has closed.

Empty-card slots, grid gaps, the footer background and the title area still
consume/ignore the full-screen tap gesture. Footer `ButtonWidget` callbacks
must take precedence in normal KOReader dispatch; the screen gesture must not
also choose a card. The close X remains the only way to cancel the picker.

### 4. Tests

Extend `tests/us21_picker.lua` or add `tests/us38_paged_picker.lua`, and
register any new harness in `tests/run.sh`. Cover:

- With the current 12 built-ins, `page_count == 1`, `_card_rects` has all 12
  sorted ids, four rows of three cards, and both the scroll-container require
  and `cropping_widget` are absent.
- Register twelve temporary compact layouts through `registerLayout`, using
  ids that sort after the built-ins. The picker exposes page `1/2` with the
  first 12 ids and page `2/2` with exactly the remaining 12; all `_card_rects`
  on either page are within the full-screen bounds and each page has four
  rows.
- Page arrows change only the rendered page / `_card_rects`, are disabled at
  their respective boundaries, and never call `onPick`.
- A visible page-two card gets normal pressed feedback and calls `onPick` only
  after the deferred tick. A card from page one cannot be selected while page
  two is visible.
- Close, return-to-background-game, help, settings and stats paths remain
  functional from page two; page changes do not schedule timer work.
- Deregister every temporary layout in teardown so caches and later harnesses
  observe the original registry.

## Verification

- `tests/run.sh`
- On device/emulator: inspect page 1 at 12 layouts, then with the US-39/40
  layouts installed inspect `1/2` and `2/2`. Confirm every page is a readable
  3x4 grid, no scrolling is possible or necessary, the footer matches Help's
  arrows and indicator, and page-two map selection, close and return work.

## Out of scope

- No changes to the layout registry, board geometry, tile rules, persistence
  schema, scores or statistics.
- No arbitrary-size paging or persisted last-page preference. This story is
  intentionally a two-page, 24-layout product decision.
