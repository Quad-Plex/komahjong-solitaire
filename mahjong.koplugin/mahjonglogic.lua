-- Mahjong Solitaire — pure game logic (no KOReader dependencies).
--
-- US-03: tile kind definitions, 144-tile deck, and the match rule.
-- US-04+ will build on this: layout, shuffle, free-tile rules, scoring.
--
-- Self-test: `lua mahjonglogic.lua` (or `lua mahjonglogic.lua --selftest`).

local MahjongLogic = {}

-- Tile kinds --------------------------------------------------------------

local BAMBOO = {}
local CHARACTERS = {}
local DOTS = {}
for i = 1, 9 do
    BAMBOO[i]      = "b" .. i
    CHARACTERS[i]  = "c" .. i
    DOTS[i]        = "d" .. i
end

local WINDS   = { "east", "south", "west", "north" }
local DRAGONS = { "red", "green", "white" }
local FLOWERS = {}
local SEASONS = {}
for i = 1, 4 do
    FLOWERS[i] = "flower" .. i
    SEASONS[i] = "season" .. i
end

local SUITED = {}
for i = 1, 9 do SUITED[#SUITED + 1] = BAMBOO[i] end
for i = 1, 9 do SUITED[#SUITED + 1] = CHARACTERS[i] end
for i = 1, 9 do SUITED[#SUITED + 1] = DOTS[i] end

-- All 42 distinct kinds, in a stable order (used by the deck and icon names).
local TILE_KINDS = {}
for _, kind in ipairs(SUITED)    do TILE_KINDS[#TILE_KINDS + 1] = kind end
for _, kind in ipairs(WINDS)     do TILE_KINDS[#TILE_KINDS + 1] = kind end
for _, kind in ipairs(DRAGONS)   do TILE_KINDS[#TILE_KINDS + 1] = kind end
for _, kind in ipairs(FLOWERS)   do TILE_KINDS[#TILE_KINDS + 1] = kind end
for _, kind in ipairs(SEASONS)   do TILE_KINDS[#TILE_KINDS + 1] = kind end

-- Each suited/wind/dragon kind appears 4 times; each flower/season once.
local MULTIPLICITY = {}
local set_multiplicity = function(kinds, n)
    for _, kind in ipairs(kinds) do MULTIPLICITY[kind] = n end
end
set_multiplicity(SUITED, 4)
set_multiplicity(WINDS, 4)
set_multiplicity(DRAGONS, 4)
set_multiplicity(FLOWERS, 1)
set_multiplicity(SEASONS, 1)

-- Match groups: flowers match any flower, seasons match any season,
-- everything else matches only an identical kind.
local MATCH_GROUP = {}
local CATEGORY = {}
local set_category = function(kinds, group, category)
    for _, kind in ipairs(kinds) do
        MATCH_GROUP[kind] = group
        CATEGORY[kind] = category
    end
end
set_category(SUITED, nil, "suited")   -- group nil => matches only identical kind
set_category(WINDS, nil, "winds")
set_category(DRAGONS, nil, "dragons")
set_category(FLOWERS, "flower", "flowers")
set_category(SEASONS, "season", "seasons")

-- Match group for kinds that match only themselves.
for _, kind in ipairs(SUITED)  do MATCH_GROUP[kind] = kind end
for _, kind in ipairs(WINDS)   do MATCH_GROUP[kind] = kind end
for _, kind in ipairs(DRAGONS) do MATCH_GROUP[kind] = kind end

-- Exported read-only views -------------------------------------------------

MahjongLogic.bamboo      = BAMBOO
MahjongLogic.characters  = CHARACTERS
MahjongLogic.dots        = DOTS
MahjongLogic.suited      = SUITED
MahjongLogic.winds       = WINDS
MahjongLogic.dragons     = DRAGONS
MahjongLogic.flowers     = FLOWERS
MahjongLogic.seasons     = SEASONS
MahjongLogic.tileKinds   = TILE_KINDS
MahjongLogic.MULTIPLICITY = MULTIPLICITY

-- Helpers ---------------------------------------------------------------

-- True if `kind` is a flower or a season.
function MahjongLogic.isSpecial(kind)
    return MATCH_GROUP[kind] == "flower" or MATCH_GROUP[kind] == "season"
end

function MahjongLogic.isFlower(kind)
    return MATCH_GROUP[kind] == "flower"
end

function MahjongLogic.isSeason(kind)
    return MATCH_GROUP[kind] == "season"
end

-- Deck ------------------------------------------------------------------

-- Returns a fresh 144-tile deck: a plain array of kind IDs ("b1", "east", ...).
--  108 suited + 16 winds + 12 dragons + 4 flowers + 4 seasons = 144.
function MahjongLogic.createDeck()
    local deck = {}
    for _, kind in ipairs(TILE_KINDS) do
        for _ = 1, MULTIPLICITY[kind] do
            deck[#deck + 1] = kind
        end
    end
    return deck
end

-- Counts of each category in a deck, for verification.
function MahjongLogic.deckCounts(deck)
    local counts = { suited = 0, winds = 0, dragons = 0, flowers = 0, seasons = 0 }
    for _, kind in ipairs(deck) do
        local category = CATEGORY[kind]
        if not category then
            error("deckCounts: unknown kind " .. tostring(kind))
        end
        counts[category] = counts[category] + 1
    end
    return counts
end

-- Matching rule ----------------------------------------------------------

-- Returns true iff the two tiles can be removed together.
--   Identical kinds match; any flower matches any flower; any season matches
--   any season; a flower never matches a season (or a suited tile).
function MahjongLogic.matches(a, b)
    if a == b then return true end
    local ga = MATCH_GROUP[a]
    local gb = MATCH_GROUP[b]
    return ga ~= nil and ga == gb
end

-- Icon base name for a kind ("b1", "east", "flower3", ...). The UI prefixes
-- this with the installed icon path ("mahjong/" .. base).
function MahjongLogic.iconForKind(kind)
    return kind
end

-- Self-tests --------------------------------------------------------------

function MahjongLogic.runSelfTests()
    local function check(cond, msg)
        if not cond then
            io.write("FAIL: ", msg, "\n")
            os.exit(1)
        end
        io.write("ok:   ", msg, "\n")
    end

    -- Deck size and per-category counts.
    local deck = MahjongLogic.createDeck()
    check(#deck == 144, "deck has 144 tiles (got " .. #deck .. ")")
    local counts = MahjongLogic.deckCounts(deck)
    check(counts.suited == 108, "108 suited tiles (got " .. counts.suited .. ")")
    check(counts.winds == 16, "16 winds (got " .. counts.winds .. ")")
    check(counts.dragons == 12, "12 dragons (got " .. counts.dragons .. ")")
    check(counts.flowers == 4, "4 flowers (got " .. counts.flowers .. ")")
    check(counts.seasons == 4, "4 seasons (got " .. counts.seasons .. ")")

    -- 42 distinct kinds.
    check(#MahjongLogic.tileKinds == 42, "42 distinct kinds (got " .. #MahjongLogic.tileKinds .. ")")

    -- Matching rule.
    check(MahjongLogic.matches("b1", "b1"), "b1 matches b1")
    check(not MahjongLogic.matches("b1", "b2"), "b1 does not match b2")
    check(not MahjongLogic.matches("b1", "c1"), "b1 does not match c1")
    check(MahjongLogic.matches("flower1", "flower3"), "flower1 matches flower3")
    check(MahjongLogic.matches("season1", "season4"), "season1 matches season4")
    check(not MahjongLogic.matches("flower1", "season1"), "flower never matches a season")
    check(not MahjongLogic.matches("flower1", "b1"), "flower never matches a suited tile")
    check(not MahjongLogic.matches("east", "south"), "east does not match south")

    io.write("All self-tests passed.\n")
    return true
end

-- Run self-tests when executed directly (`lua mahjonglogic.lua`) or with
-- `lua mahjonglogic.lua --selftest`.
-- luacheck: no unused args
if select("#", ...) == 0 then
    MahjongLogic.runSelfTests()
end

return MahjongLogic
