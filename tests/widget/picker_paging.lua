-- US-48 -- fixed 3x4 paged layout picker.

local mock = require("mock")
local ctx = mock.newContext()
local Logic = ctx.loadPlugin("mahjonglogic")
local Picker = ctx.loadPlugin("mahjonglayoutselect")

local failures = 0
local function expect(ok, message)
    if not ok then failures = failures + 1; print("FAIL: " .. message)
    else print("PASS: " .. message) end
end

local spec = {
    { layer = 0, kind = "row", x_min = 0, x_max = 1, y = 0 },
    { layer = 0, kind = "row", x_min = 0, x_max = 1, y = 1 },
}
local extra = {}
for i = 1, 12 do
    local id = string.format("zz-us48-%02d", i)
    extra[#extra + 1] = id
    Logic.registerLayout{ id = id, name = id, spec = spec }
end

local picked
local picker = Picker:new{ onPick = function(id) picked = id end }
local ids = Logic.layoutIds()
expect(picker.page_count == 3, "30 layouts create exactly three pages")
expect(#picker._card_rects == 12, "page one has twelve cards")
expect(picker.page == 1, "picker starts on page one")
expect(picker._page_left.enabled == false, "left arrow is disabled on page one")
expect(picker._page_right.enabled ~= false, "right arrow is enabled on page one")
for i, rect in ipairs(picker._card_rects) do
    expect(rect.id == ids[i], "page one slot " .. i .. " follows registry ordering")
end

local old_card = picker._card_rects[1]
picker._page_right.callback()
expect(picker.page == 2, "right arrow changes to page two")
expect(#picker._card_rects == 12, "page two has twelve cards")
expect(picker._card_rects[1].id == ids[13], "page two starts at registry slot thirteen")
expect(picker._card_rects[12].id == ids[24], "page two ends at registry slot twenty-four")
expect(picker._page_right.enabled ~= false, "right arrow is enabled before the last page")
expect(picker._page_left.enabled ~= false, "left arrow is enabled on page two")

picker._page_right.callback()
expect(picker.page == 3, "right arrow changes to page three")
expect(#picker._card_rects == 12, "page three contains the remaining twelve cards")
expect(picker._card_rects[1].id == ids[25] and picker._card_rects[12].id == ids[36],
    "page three contains registry slots twenty-five through thirty-six")
expect(picker._page_right.enabled == false, "right arrow is disabled on the last page")
picker._page_left.callback()

local card = picker._card_rects[1]
picker:onTapSelect(nil, { pos = { x = card.x + card.w / 2, y = card.y + card.h / 2 } })
expect(picked == nil, "page-two card waits for deferred tap feedback")
ctx.runScheduled()
expect(picked == card.id, "visible page-two card is selected after deferred feedback")

local old_picker = Picker:new{ onPick = function(id) picked = id end }
old_picker:onTapSelect(nil, { pos = { x = old_card.x + old_card.w / 2,
    y = old_card.y + old_card.h / 2 } })
old_picker._page_right.callback()
ctx.runScheduled()
expect(picked == card.id, "a card from a previous page cannot deal after paging")

for _, id in ipairs(extra) do Logic.deregisterLayout(id) end

if failures == 0 then
    print("\nALL US-48 PAGED PICKER CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
