# US-21 — Expand the layout selection grid

As a player, I want the layout picker to hold the full set of boards so I can pick any of them.

- The picker (`mahjonglayoutselect.lua`) currently uses a **fixed 2×3 grid (6 slots)**
  with the comment "wrap in a scroll container if more are added later". Turtle + Spider +
  Bridge already fill 3 of the 6 slots; the US-22..US-29 boards take the total to **11**,
  which overflows the grid.
- Expand the grid to a **3-column layout with a dynamically computed row count**
  (`rows = ceil(#ids / 3)`, minimum 3) so all registered layouts always get a card, exactly
  one full-screen `TapSelect` gesture hit-tests against the recorded `_card_rects`, and the
  `onTapSelect` / `onClose` handlers stay unchanged. Wrap the grid rows in a scroll
  container so a tall grid (4+ rows) scrolls on smaller screens instead of clipping.
- Empty slots (when `#ids` is not a multiple of 3) stay blank spacers exactly as today.
- `layoutThumbnail(id, w, h)` and the card rect math are already per-id and layout-agnostic;
  this is purely a layout change to `LayoutSelect:init()`.

**Test impact:** `tests/us15_spider.lua`'s assertions on `#picker._card_rects == 3` and
`#ids == 3` move to `tests/us21_picker.lua` and assert the new dynamic count after all
US-22..29 layouts are registered.

**Acceptance:** Pick a layout from a 4-row (3×4) grid with 11 cards; tapping the bottom
cards scrolls into view. (Planned — prerequisite for US-22..29.)

---

## Implementation notes

- **Grid:** `cols = 3`, `rows = math.max(3, math.ceil(#ids / cols))`. Card sizing
  (`card_w`, `card_h`) is unchanged — cards scale with row count so the grid
  always fits the available screen height; the scroll container is a safety
  net for very small screens or future minimum-card-size constraints.
- **`tests/us15_spider.lua` and `tests/us16_bridge.lua`:** the hardcoded
  `#picker._card_rects == 3` assertion was relaxed to
  `#picker._card_rects == #Logic.layoutIds()` so it stays correct as layouts
  are added. The detailed 3-column / dynamic-rows assertions live in
  `tests/us21_picker.lua`.
- **`tests/us21_picker.lua`:** verifies the 3-column grid (x-stepping by
  `card_w + gap`), sorted-id card order, the 4th-card-wraps-to-row-1 path
  (via a throwaway toy layout), and pick / close-X / tap-outside-cancel.
- **Pitfall (KOReader module name):** the scroll container module is
  `ui/widget/container/scrollablecontainer` (class `ScrollableContainer`),
  **not** `svcontainer`. The latter does not exist on the device and causes a
  load-time `module not found` error that silently drops the whole plugin.
  Always verify module paths against the device's `frontend/ui/widget/` tree.
- **Pitfall (positional child):** `ScrollableContainer:initState()` reads
  `self[1]:getSize()` for its content, so the content **must** be passed as a
  positional child (`SVContainer:new{ child, dimen = ... }`), not as a named
  `content` field.
- **Pitfall (`cropping_widget`):** KOReader's `ScrollableContainer` docs
  require the parent widget (the one passed to `UIManager:show`) to set
  `self.cropping_widget` to the scroll container, otherwise repaints and flash
  feedback can leak outside the clipped region. Set it in `show()` before
  `UIManager:show(self)`.
