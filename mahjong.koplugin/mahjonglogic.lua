-- Mahjong Solitaire — pure game logic (no KOReader dependencies).
--
-- US-03: tile kind definitions, 144-tile deck, and the match rule.
-- US-04: Turtle layout, seeded shuffling, and newGame().
-- US-05+ will build on this: free-tile rules, scoring.
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

-- Turtle layout ---------------------------------------------------------
--
-- The classic 144-tile Turtle, one flat rectangle per height level (L0
-- bottom, L4 top), all on the shared integer grid:
--   L0: x=2..11, y=2..7   (10x6 = 60)
--   L1: x=1..12, y=2..5   (12x4 = 48)
--   L2: x=3..8,  y=2..5   ( 6x4 = 24)
--   L3: x=4..7,  y=3..4   ( 4x2 =  8)
--   L4: x=4..7,  y=4       ( 4x1 =  4)
-- 60 + 48 + 24 + 8 + 4 = 144. Max x is 12, max y is 7.
local LAYOUT_SPEC = {
    { layer = 0, x_min = 2,  x_max = 11, y_min = 2, y_max = 7 },
    { layer = 1, x_min = 1,  x_max = 12, y_min = 2, y_max = 5 },
    { layer = 2, x_min = 3,  x_max = 8,  y_min = 2, y_max = 5 },
    { layer = 3, x_min = 4,  x_max = 7,  y_min = 3, y_max = 4 },
    { layer = 4, x_min = 4,  x_max = 7,  y_min = 4, y_max = 4 },
}

-- Returns the 144 tile positions of the Turtle layout as an array of
-- { x = .., y = .., layer = .. } tables, bottom layer first.
function MahjongLogic.buildLayout()
    local layout = {}
    for _, spec in ipairs(LAYOUT_SPEC) do
        for y = spec.y_min, spec.y_max do
            for x = spec.x_min, spec.x_max do
                layout[#layout + 1] = { x = x, y = y, layer = spec.layer }
            end
        end
    end
    return layout
end

-- Canonical map key for a board position. A board is keyed by this string
-- (x,y,layer -> kind) so lookups/removals are O(1) and persistence (US-10)
-- is a plain table.
function MahjongLogic.posKey(x, y, layer)
    return x .. "," .. y .. "," .. layer
end

-- Deterministic RNG ------------------------------------------------------
--
-- A tiny Park-Miller (Lehmer) PRNG: seeded games are reproducible on any
-- interpreter and we never disturb math.random's global state.

function MahjongLogic.newRng(seed)
    seed = seed or math.floor(os.time())
    local state = seed % 2147483647
    if state <= 0 then state = 2147483646 end
    return function()
        state = (state * 16807) % 2147483647
        return state / 2147483647 -- in [0, 1)
    end
end

-- Fisher-Yates shuffle. `rng` is a function returning [0,1); defaults to
-- math.random. Shuffles `t` in place and returns it.
function MahjongLogic.shuffle(t, rng)
    rng = rng or math.random
    for i = #t, 2, -1 do
        local j = 1 + math.floor(rng() * i)
        if j > i then j = i end
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- New game ---------------------------------------------------------------

-- Builds a fresh shuffled board: the 144-tile deck dealt at random onto the
-- 144 Turtle positions. Returns a board keyed by posKey(x,y,layer) -> kind.
-- `rng` is nil (random from the clock), an integer seed, or a function
-- returning [0,1).
function MahjongLogic.newGame(rng)
    local layout = MahjongLogic.buildLayout()
    local deck = MahjongLogic.createDeck()
    if type(rng) == "number" then
        rng = MahjongLogic.newRng(rng)
    elseif rng == nil then
        local seed = os.time() * 1000 + math.random(1000)
        rng = MahjongLogic.newRng(seed)
    end
    MahjongLogic.shuffle(deck, rng)
    local board = {}
    for i = 1, #layout do
        local p = layout[i]
        board[MahjongLogic.posKey(p.x, p.y, p.layer)] = deck[i]
    end
    return board
end

-- Number of tiles currently on a board.
function MahjongLogic.tileCount(board)
    local n = 0
    for _ in pairs(board) do n = n + 1 end
    return n
end

-- Category counts for a board (same shape as deckCounts). Verifies a
-- shuffled board still holds exactly one of each deck tile.
function MahjongLogic.boardCounts(board)
    local kinds = {}
    for _, kind in pairs(board) do kinds[#kinds + 1] = kind end
    return MahjongLogic.deckCounts(kinds)
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

    -- Turtle layout: exactly 144 unique positions, per-layer rectangles
    -- matching the table, grid within x<=12, y<=7.
    local layout = MahjongLogic.buildLayout()
    check(#layout == 144, "layout has 144 positions (got " .. #layout .. ")")
    local layer_counts = {}
    local seen = {}
    local max_x, max_y = 0, 0
    for _, p in ipairs(layout) do
        layer_counts[p.layer] = (layer_counts[p.layer] or 0) + 1
        local key = MahjongLogic.posKey(p.x, p.y, p.layer)
        check(not seen[key], "no duplicate position " .. key)
        seen[key] = true
        max_x = math.max(max_x, p.x)
        max_y = math.max(max_y, p.y)
    end
    check(layer_counts[0] == 60, "layer 0 has 60 tiles (got " .. tostring(layer_counts[0]) .. ")")
    check(layer_counts[1] == 48, "layer 1 has 48 tiles (got " .. tostring(layer_counts[1]) .. ")")
    check(layer_counts[2] == 24, "layer 2 has 24 tiles (got " .. tostring(layer_counts[2]) .. ")")
    check(layer_counts[3] == 8, "layer 3 has 8 tiles (got " .. tostring(layer_counts[3]) .. ")")
    check(layer_counts[4] == 4, "layer 4 has 4 tiles (got " .. tostring(layer_counts[4]) .. ")")
    check(max_x == 12 and max_y == 7, "grid bounds are x<=12, y<=7 (got " .. max_x .. "x" .. max_y .. ")")
    for _, s in ipairs(LAYOUT_SPEC) do
        local count = 0
        for y = s.y_min, s.y_max do
            for x = s.x_min, s.x_max do
                count = count + 1
                check(seen[MahjongLogic.posKey(x, y, s.layer)] ~= nil,
                    "position " .. x .. "," .. y .. ",L" .. s.layer .. " is present")
            end
        end
        check(count == layer_counts[s.layer],
            "layer " .. s.layer .. " has " .. count .. " spec cells (got " .. tostring(layer_counts[s.layer]) .. ")")
    end

    -- newGame: same seed is deterministic; different seed differs.
    local g1 = MahjongLogic.newGame(42)
    local g2 = MahjongLogic.newGame(42)
    check(MahjongLogic.tileCount(g1) == 144, "newGame(42) places 144 tiles")
    local same = true
    for k, v in pairs(g1) do
        if g2[k] ~= v then same = false break end
    end
    check(same, "newGame(42) is deterministic for a fixed seed")
    local g3 = MahjongLogic.newGame(43)
    local different = false
    for k, v in pairs(g1) do
        if g3[k] ~= v then different = true break end
    end
    check(different, "newGame(43) differs from newGame(42)")

    -- A shuffled board still holds exactly one of each deck tile.
    local board_counts = MahjongLogic.boardCounts(g1)
    check(board_counts.suited == 108, "board has 108 suited (got " .. board_counts.suited .. ")")
    check(board_counts.winds == 16, "board has 16 winds (got " .. board_counts.winds .. ")")
    check(board_counts.dragons == 12, "board has 12 dragons (got " .. board_counts.dragons .. ")")
    check(board_counts.flowers == 4, "board has 4 flowers (got " .. board_counts.flowers .. ")")
    check(board_counts.seasons == 4, "board has 4 seasons (got " .. board_counts.seasons .. ")")

    -- shuffle() is a permutation: length and multiset unchanged.
    local shuf = MahjongLogic.createDeck()
    MahjongLogic.shuffle(shuf, MahjongLogic.newRng(7))
    check(#shuf == 144, "shuffle keeps 144 tiles")
    local plain = MahjongLogic.createDeck()
    local sorted = function(t)
        local s = {}
        for _, v in ipairs(t) do s[#s + 1] = v end
        table.sort(s)
        return s
    end
    local sa, sb = sorted(shuf), sorted(plain)
    local perm = true
    for i = 1, 144 do
        if sa[i] ~= sb[i] then perm = false break end
    end
    check(perm, "shuffle is a permutation of the deck")

    -- Unseeded newGame still produces a full board.
    local g4 = MahjongLogic.newGame()
    check(MahjongLogic.tileCount(g4) == 144, "newGame() (random) places 144 tiles")

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
