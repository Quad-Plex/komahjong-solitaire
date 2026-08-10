-- US-49 -- Hare, Horse, Tiger, Ram, Monkey and Rooster.

local mock = require("mock")
local ctx = mock.newContext()
local Logic = ctx.loadPlugin("mahjonglogic")
local Picker = ctx.loadPlugin("mahjonglayoutselect")

local failures = 0
local function expect(ok, message)
    if not ok then failures = failures + 1; print("FAIL: " .. message)
    else print("PASS: " .. message) end
end

local expected = {
    hare = { 59, 44, 26, 11, 4 }, horse = { 62, 49, 27, 6 },
    tiger = { 62, 58, 18, 6 }, ram = { 69, 52, 20, 3 },
    monkey = { 60, 44, 23, 15, 2 }, rooster = { 66, 44, 26, 7, 1 },
    dog = { 62, 47, 29, 6 }, snake = { 60, 58, 21, 5 },
    boar = { 65, 43, 28, 8 }, ox = { 73, 44, 21, 6 },
    wedges = { 60, 39, 26, 13, 5, 1 }, hourglass = { 74, 40, 12, 10, 8 },
}
for id, counts in pairs(expected) do
    local layout = Logic.buildLayout(id)
    local seen, layers = {}, {}
    for _, p in ipairs(layout) do
        local key = Logic.posKey(p.x, p.y, p.layer)
        expect(not seen[key], id .. " has unique positions")
        seen[key] = true
        layers[p.layer] = (layers[p.layer] or 0) + 1
    end
    expect(#layout == 144, id .. " has 144 tiles")
    for layer, count in ipairs(counts) do
        expect(layers[layer - 1] == count, id .. " layer " .. (layer - 1) .. " count")
    end
    local bounds = Logic.gridBounds(id)
    local expected_x_max = (id == "ox" and 13) or ((id == "wedges" or id == "hourglass") and 12) or 14
    expect(bounds.x_min == 0 and bounds.x_max == expected_x_max and bounds.y_min == 0 and bounds.y_max == 7,
        id .. " fits the board envelope")
    expect(Logic.maxLayer(id) == #counts - 1, id .. " has the expected layer depth")
    expect(Logic.matchingFreePair(Logic.newGame(id), id) ~= nil, id .. " nil-rng deal has a move")
end

local picker = Picker:new{}
picker._page_right.callback()
local animal_ids = {
    hare = true, horse = true, tiger = true, ram = true, monkey = true, rooster = true,
    dog = true, snake = true, boar = true, ox = true, wedges = true, hourglass = true,
}
local all_animals = #picker._card_rects == 12
for _, card in ipairs(picker._card_rects) do
    if not animal_ids[card.id] then all_animals = false end
end
expect(all_animals, "new animal and shape cards are grouped on page two")

if failures == 0 then
    print("\nALL US-49 ZODIAC CHECKS PASSED")
else
    print("\n" .. failures .. " FAILURES")
    os.exit(1)
end
