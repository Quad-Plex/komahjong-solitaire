-- Mahjong Solitaire — pure game logic (no KOReader dependencies).
--
-- US-03: tile kind definitions, 144-tile deck, and the match rule.
-- US-04: Turtle layout, seeded shuffling, and newGame().
-- US-05: free-tile detection (tileAt, isFree, freeTiles, hasMoves).
-- US-07+ will build on this: removal, scoring.
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

-- Helpers ---------------------------------------------------------------

-- True if `kind` is one of the 42 valid tile kinds. Used to validate
-- deserialized state (US-10): a tampered/corrupt value must be rejected.
function MahjongLogic.isKind(kind)
    return CATEGORY[kind] ~= nil
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

-- Layout registry (US-14) --------------------------------------------------
--
-- The Turtle layout is the canonical GNOME Mahjongg map, with the stepped
-- pyramid and the head/tail protrusions. Coordinates are tile top-left
-- corners; `y` may be fractional (x=0/y=3.5 head, x=13..14/y=3.5 tail,
-- x=6.5/y=3.5 cap) so the silhouette's half-tile overhang is kept:
--   L0: body rows (12+8+10+12+12+10+8+12 = 84) + head (x=0, y=3.5) + tail
--       (x=13..14, y=3.5) = 87
--   L1: block x=4..9,  y=1..6   (6x6  = 36)
--   L2: block x=5..8,  y=2..5   (4x4  = 16)
--   L3: block x=6..7,  y=3..4   (2x2  =  4)
--   L4: single tile x=6.5, y=3.5 (       1)
-- 87 + 36 + 16 + 4 + 1 = 144. Grid extents: x=0..14, y=0..7.
--
-- US-14 generalizes the layout-dependent paths through a registry: every
-- layout is registered as { id=, name=, spec= } and the layout functions take
-- a layout id (defaulting to "turtle" so existing callers and self-tests stay
-- byte-identical). Adding a layout (US-15/16) is a one-line registerLayout call.

local TURTLE_SPEC = {
    -- Layer 0 body rows, bottom row first.
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 0 },
    { layer = 0, kind = "row",   x_min = 3,  x_max = 10, y = 1 },
    { layer = 0, kind = "row",   x_min = 2,  x_max = 11, y = 2 },
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 3 },
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 4 },
    { layer = 0, kind = "row",   x_min = 2,  x_max = 11, y = 5 },
    { layer = 0, kind = "row",   x_min = 3,  x_max = 10, y = 6 },
    { layer = 0, kind = "row",   x_min = 1,  x_max = 12, y = 7 },
    -- Head and tail protrusions (half a tile below the y=3 body row).
    { layer = 0, kind = "tile",  x = 0,  y = 3.5 },
    { layer = 0, kind = "row",   x_min = 13, x_max = 14, y = 3.5 },
    -- Upper pyramid blocks.
    { layer = 1, kind = "block", x_min = 4, x_max = 9,  y_min = 1, y_max = 6 },
    { layer = 2, kind = "block", x_min = 5, x_max = 8,  y_min = 2, y_max = 5 },
    { layer = 3, kind = "block", x_min = 6, x_max = 7,  y_min = 3, y_max = 4 },
    { layer = 4, kind = "tile",  x = 6.5, y = 3.5 },
}

-- The registry itself: id -> { id=, name=, spec= }. Callers must NOT mutate
-- the entries (the cached layout tables reference the spec).
MahjongLogic.layouts = {}

-- Per-id caches (forward-declared so registerLayout can invalidate them).
local _layout_cache = {}      -- id -> positions array
local _bounds_cache = {}      -- id -> { x_min, x_max, y_min, y_max }
local _layout_key_cache = {}  -- id -> { [posKey] = true }
local _max_layer_cache = {}   -- id -> number

-- Builds the flat positions array from a layout spec. Caller-cached per id via
-- buildLayout(id); this helper never memoizes (it is only run once per id).
local function buildLayoutFromSpec(spec)
    local layout = {}
    local function add(x, y, layer)
        layout[#layout + 1] = { x = x, y = y, layer = layer }
    end
    for _, s in ipairs(spec) do
        if s.kind == "row" then
            for x = s.x_min, s.x_max do
                add(x, s.y, s.layer)
            end
        elseif s.kind == "block" then
            for y = s.y_min, s.y_max do
                for x = s.x_min, s.x_max do
                    add(x, y, s.layer)
                end
            end
        elseif s.kind == "set" then
            -- Explicit point list: { {x=, y=}, ... } at a fixed layer. Used by
            -- layouts (e.g. Spider) whose per-layer shape is too irregular for
            -- rows/blocks to express compactly. (US-15)
            for _, pt in ipairs(s.points) do
                add(pt.x, pt.y, s.layer)
            end
        else -- single tile
            add(s.x, s.y, s.layer)
        end
    end
    return layout
end

-- Registers a layout. `entry` is { id=string, name=string, spec=table } (name
-- defaults to the id). Re-registering an id replaces it and drops its caches
-- so a hot-reload picks up a new spec. US-15/16 call this for Spider/Bridge.
function MahjongLogic.registerLayout(entry)
    if type(entry) ~= "table" or type(entry.id) ~= "string" or type(entry.spec) ~= "table" then
        error("registerLayout: needs { id=string, name=string, spec=table }")
    end
    local copy = {
        id = entry.id,
        name = entry.name or entry.id,
        spec = entry.spec,
    }
    MahjongLogic.layouts[copy.id] = copy
    _layout_cache[copy.id] = nil
    _bounds_cache[copy.id] = nil
    _layout_key_cache[copy.id] = nil
    _max_layer_cache[copy.id] = nil
end

-- Sorted list of registered layout ids (the picker iterates this).
function MahjongLogic.layoutIds()
    local ids = {}
    for id in pairs(MahjongLogic.layouts) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

-- Display name of a layout id (falls back to the id for an unknown layout).
function MahjongLogic.layoutName(id)
    local l = MahjongLogic.layouts[id]
    return (l and l.name) or id
end

-- Spider layout (US-15): the classic Spider board, transcribed from GNOME
-- Mahjongg's `spider` map (4 levels, 144 tiles: 65/53/25/1). The shape is a
-- wide diamond with nested hollow rings stepping up to a single peak tile.
-- Coordinates are on the same half-grid as Turtle (x = 0.5..14.5, y = 0..7);
-- the per-layer point sets use `kind = "set"` because the silhouette is too
-- irregular for rows/blocks to express compactly.
local SPIDER_SPEC = {
    { layer = 0, kind = "set", points = {
        {x = 3, y = 0}, {x = 4, y = 0}, {x = 6.5, y = 0}, {x = 8.5, y = 0}, {x = 11, y = 0}, {x = 12, y = 0},
        {x = 4, y = 1}, {x = 7, y = 1}, {x = 8, y = 1}, {x = 11, y = 1},
        {x = 1, y = 1.5}, {x = 5, y = 1.5}, {x = 10, y = 1.5}, {x = 14, y = 1.5},
        {x = 2, y = 2}, {x = 6, y = 2}, {x = 7, y = 2}, {x = 8, y = 2}, {x = 9, y = 2}, {x = 13, y = 2},
        {x = 3, y = 2.5}, {x = 4, y = 2.5}, {x = 11, y = 2.5}, {x = 12, y = 2.5},
        {x = 5, y = 3}, {x = 6, y = 3}, {x = 7, y = 3}, {x = 8, y = 3}, {x = 9, y = 3}, {x = 10, y = 3},
        {x = 4.5, y = 4}, {x = 5.5, y = 4}, {x = 6.5, y = 4}, {x = 7.5, y = 4},
        {x = 8.5, y = 4}, {x = 9.5, y = 4}, {x = 10.5, y = 4},
        {x = 0.5, y = 4.5}, {x = 1.5, y = 4.5}, {x = 2.5, y = 4.5}, {x = 3.5, y = 4.5},
        {x = 11.5, y = 4.5}, {x = 12.5, y = 4.5}, {x = 13.5, y = 4.5}, {x = 14.5, y = 4.5},
        {x = 5, y = 5}, {x = 6, y = 5}, {x = 7, y = 5}, {x = 8, y = 5}, {x = 9, y = 5}, {x = 10, y = 5},
        {x = 4, y = 6}, {x = 6, y = 6}, {x = 7, y = 6}, {x = 8, y = 6}, {x = 9, y = 6}, {x = 11, y = 6},
        {x = 3, y = 6.5}, {x = 12, y = 6.5},
        {x = 1, y = 7}, {x = 2, y = 7}, {x = 7, y = 7}, {x = 8, y = 7}, {x = 13, y = 7}, {x = 14, y = 7},
    } },
    { layer = 1, kind = "set", points = {
        {x = 3, y = 0}, {x = 4, y = 0}, {x = 6.5, y = 0}, {x = 8.5, y = 0}, {x = 11, y = 0}, {x = 12, y = 0},
        {x = 4, y = 1}, {x = 11, y = 1},
        {x = 1, y = 1.5}, {x = 5, y = 1.5}, {x = 10, y = 1.5}, {x = 14, y = 1.5},
        {x = 2, y = 2}, {x = 7, y = 2}, {x = 8, y = 2}, {x = 13, y = 2},
        {x = 3, y = 2.5}, {x = 4, y = 2.5}, {x = 11, y = 2.5}, {x = 12, y = 2.5},
        {x = 6, y = 3}, {x = 7, y = 3}, {x = 8, y = 3}, {x = 9, y = 3},
        {x = 5.5, y = 4}, {x = 6.5, y = 4}, {x = 7.5, y = 4}, {x = 8.5, y = 4}, {x = 9.5, y = 4},
        {x = 0.5, y = 4.5}, {x = 1.5, y = 4.5}, {x = 2.5, y = 4.5}, {x = 3.5, y = 4.5},
        {x = 11.5, y = 4.5}, {x = 12.5, y = 4.5}, {x = 13.5, y = 4.5}, {x = 14.5, y = 4.5},
        {x = 6, y = 5}, {x = 7, y = 5}, {x = 8, y = 5}, {x = 9, y = 5},
        {x = 4, y = 6}, {x = 7, y = 6}, {x = 8, y = 6}, {x = 11, y = 6},
        {x = 3, y = 6.5}, {x = 12, y = 6.5},
        {x = 1, y = 7}, {x = 2, y = 7}, {x = 7, y = 7}, {x = 8, y = 7}, {x = 13, y = 7}, {x = 14, y = 7},
    } },
    { layer = 2, kind = "set", points = {
        {x = 4, y = 0}, {x = 11, y = 0},
        {x = 1, y = 1.5}, {x = 5, y = 1.5}, {x = 10, y = 1.5}, {x = 14, y = 1.5},
        {x = 3, y = 2.5}, {x = 12, y = 2.5},
        {x = 7, y = 3}, {x = 8, y = 3},
        {x = 6.5, y = 4}, {x = 7.5, y = 4}, {x = 8.5, y = 4},
        {x = 0.5, y = 4.5}, {x = 2.5, y = 4.5}, {x = 12.5, y = 4.5}, {x = 14.5, y = 4.5},
        {x = 7, y = 5}, {x = 8, y = 5},
        {x = 7, y = 6}, {x = 8, y = 6},
        {x = 3, y = 6.5}, {x = 12, y = 6.5},
        {x = 1, y = 7}, {x = 14, y = 7},
    } },
    { layer = 3, kind = "set", points = {
        {x = 7.5, y = 4.5},
    } },
}

-- Turtle is registered in US-14; US-15 adds Spider; US-16 adds Bridge.
MahjongLogic.registerLayout{ id = "turtle", name = "Turtle", spec = TURTLE_SPEC }
MahjongLogic.registerLayout{ id = "spider", name = "Spider", spec = SPIDER_SPEC }

-- Bridge layout (US-16): the classic "Four Bridges" board from GNOME
-- Mahjongg's `bridges` map — two towers linked by a deck, 144 tiles across
-- 4 layers (88/36/16/4). The shape is regular enough for rows/blocks (unlike
-- Spider's irregular silhouette, which needs `set`).
--   L0: bridge deck (88) — two wide towers with a connecting deck
--   L1: four 3x3 towers (36)
--   L2: four 2x2 towers (16)
--   L3: four peak tiles (4) at (3.5,1.5), (8.5,1.5), (3.5,6.5), (8.5,6.5)
-- Grid extents: x=0..12, y=0..8.
local BRIDGE_SPEC = {
    -- Layer 0: the bridge deck and outer towers.
    { layer = 0, kind = "row",   x_min = 1,   x_max = 11, y = 0 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 5,  y = 1 },
    { layer = 0, kind = "row",   x_min = 7,   x_max = 10,  y = 1 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 10, y = 2 },
    { layer = 0, kind = "row",   x_min = 0,   x_max = 12, y = 3 },
    { layer = 0, kind = "row",   x_min = 1.5, x_max = 3.5, y = 4 },
    { layer = 0, kind = "row",   x_min = 8.5, x_max = 10.5, y = 4 },
    { layer = 0, kind = "row",   x_min = 0,   x_max = 12, y = 5 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 10, y = 6 },
    { layer = 0, kind = "row",   x_min = 2,   x_max = 5,  y = 7 },
    { layer = 0, kind = "row",   x_min = 7,   x_max = 10,  y = 7 },
    { layer = 0, kind = "row",   x_min = 1,   x_max = 11, y = 8 },
    -- Layer 1: four 3x3 towers.
    { layer = 1, kind = "block", x_min = 2.5, x_max = 4.5, y_min = 0.5, y_max = 2.5 },
    { layer = 1, kind = "block", x_min = 7.5, x_max = 9.5, y_min = 0.5, y_max = 2.5 },
    { layer = 1, kind = "block", x_min = 2.5, x_max = 4.5, y_min = 5.5, y_max = 7.5 },
    { layer = 1, kind = "block", x_min = 7.5, x_max = 9.5, y_min = 5.5, y_max = 7.5 },
    -- Layer 2: four 2x2 towers.
    { layer = 2, kind = "block", x_min = 3, x_max = 4, y_min = 1, y_max = 2 },
    { layer = 2, kind = "block", x_min = 8, x_max = 9, y_min = 1, y_max = 2 },
    { layer = 2, kind = "block", x_min = 3, x_max = 4, y_min = 6, y_max = 7 },
    { layer = 2, kind = "block", x_min = 8, x_max = 9, y_min = 6, y_max = 7 },
    -- Layer 3: four peak tiles.
    { layer = 3, kind = "tile",  x = 3.5, y = 1.5 },
    { layer = 3, kind = "tile",  x = 8.5, y = 1.5 },
    { layer = 3, kind = "tile",  x = 3.5, y = 6.5 },
    { layer = 3, kind = "tile",  x = 8.5, y = 6.5 },
}
MahjongLogic.registerLayout{ id = "bridge", name = "Bridge", spec = BRIDGE_SPEC }

-- Returns the 144 tile positions of a layout as an array of
-- { x = .., y = .., layer = .. } tables, bottom layer first (so the UI can
-- paint lower layers first). The layout is static, so it is built once and
-- cached per id: rebuilds (new game, board repaints) iterate the same table
-- instead of allocating fresh position tables every call. Callers must NOT
-- mutate the returned array.
function MahjongLogic.buildLayout(id)
    if id == nil then id = "turtle" end
    if not _layout_cache[id] then
        local entry = MahjongLogic.layouts[id]
        if not entry then
            error("buildLayout: unknown layout id " .. tostring(id))
        end
        _layout_cache[id] = buildLayoutFromSpec(entry.spec)
    end
    return _layout_cache[id]
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
-- 144 layout positions. Returns a board keyed by posKey(x,y,layer) -> kind.
-- `id` is the layout id (defaults to "turtle"). `rng` is nil (random from the
-- clock), an integer seed, or a function returning [0,1).
--
-- Backward-compat: the pre-US-14 signature was newGame(rng) — a number/nil
-- first argument is still treated as the rng for a Turtle deal, so every
-- existing caller (and the self-tests) stays byte-identical. The explicit form
-- is newGame("turtle", 42).
function MahjongLogic.newGame(id, rng)
    if type(id) ~= "string" then
        -- old call shape: newGame(rng) or newGame()
        rng = id
        id = "turtle"
    end
    local layout = MahjongLogic.buildLayout(id)
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

-- Returns true if the two tiles can be removed together.
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

-- True if a same-layer neighbour fully covers the tile's east edge — either
-- a tile directly at (x+1, y), or two half-overlapping neighbours at
-- (x+1, y-0.5) and (x+1, y+0.5). The Turtle's head/tail/cap sit on the half
-- grid, so a tile can be adjacent to half of two other tiles on one side
-- (the head at (0, 3.5) has body tiles at (1, 3) and (1, 4) to its east);
-- only a FULLY covered edge hides the bevel. x/y are 0.5-grid exact in the
-- layout, so ±0.5 arithmetic produces the canonical keys.
local function hasEastNeighbour(board, x, y, layer)
    if MahjongLogic.tileAt(board, x + 1, y, layer) then return true end
    return MahjongLogic.tileAt(board, x + 1, y - 0.5, layer) ~= nil
        and MahjongLogic.tileAt(board, x + 1, y + 0.5, layer) ~= nil
end

local function hasSouthNeighbour(board, x, y, layer)
    if MahjongLogic.tileAt(board, x, y + 1, layer) then return true end
    return MahjongLogic.tileAt(board, x - 0.5, y + 1, layer) ~= nil
        and MahjongLogic.tileAt(board, x + 0.5, y + 1, layer) ~= nil
end

-- Icon name for the tile at (x, y, layer), including the 2.5D bevel-variant
-- suffix: "" (both bevels), "_nb" (no bottom bevel), "_nr" (no right bevel),
-- "_n" (neither). A tile's right/bottom bevel is only drawn when that edge is
-- exposed: a same-layer neighbour to the right/below blocks it (otherwise it
-- reads as a fake seam inside an otherwise solid layer). The variants are
-- generated by tools/gen_icons.py and installed with the rest of the set.
-- Returns nil if the cell is empty.
function MahjongLogic.iconForTile(board, x, y, layer)
    local kind = MahjongLogic.tileAt(board, x, y, layer)
    if not kind then return nil end
    local has_right = hasEastNeighbour(board, x, y, layer)
    local has_bottom = hasSouthNeighbour(board, x, y, layer)
    if has_right and has_bottom then
        return kind .. "_n"
    elseif has_right then
        return kind .. "_nr"
    elseif has_bottom then
        return kind .. "_nb"
    end
    return kind
end

-- Free-tile rules ----------------------------------------------------------
--
-- Flat projection (design decision 5): a tile at (x,y,L) is free if
--   * no tile exists directly above it at (x,y,L+1), and
--   * at least one horizontal side is open: no tile at (x-1,y,L) OR
--     no tile at (x+1,y,L).

-- Kind at (x, y, layer), or nil if the cell is empty.
function MahjongLogic.tileAt(board, x, y, layer)
    return board[MahjongLogic.posKey(x, y, layer)]
end

-- True if a tile at (x, y, layer) is free. An empty cell is never free.
function MahjongLogic.isFree(board, x, y, layer)
    if MahjongLogic.tileAt(board, x, y, layer) == nil then
        return false
    end
    -- Covered from above: any tile at layer + 1 whose 1x1 rect overlaps ours.
    -- On the half-grid, offsets of -0.5, 0, 0.5 can overlap.
    for dx = -0.5, 0.5, 0.5 do
        for dy = -0.5, 0.5, 0.5 do
            if MahjongLogic.tileAt(board, x + dx, y + dy, layer + 1) then
                return false
            end
        end
    end

    -- Blocked on the left: any tile at layer whose right edge touches our left
    -- edge (nx = x-1) and whose y-range overlaps ours.
    local blocked_left = false
    for dy = -0.5, 0.5, 0.5 do
        if MahjongLogic.tileAt(board, x - 1, y + dy, layer) then
            blocked_left = true
            break
        end
    end

    -- Blocked on the right: same logic, nx = x+1.
    local blocked_right = false
    for dy = -0.5, 0.5, 0.5 do
        if MahjongLogic.tileAt(board, x + 1, y + dy, layer) then
            blocked_right = true
            break
        end
    end

    return not (blocked_left and blocked_right)
end

-- All free tiles on a board, as an array of { x, y, layer, kind } tables.
-- Real boards only ever hold a single layout's positions, so the hot path
-- iterates the (memoized) buildLayout(id) and does a posKey lookup per
-- position — no per-key regex parse (IMPLEMENTATION_PLAN P3 #1, roughly 5-6x
-- faster, and a deterministic bottom-layer-first order). Hand-crafted boards
-- in the self-tests may place tiles at non-layout positions; those straggler
-- keys (typically none in a real game) fall back to the old parse path.
-- `id` is the layout the board was dealt on (default "turtle" for
-- backward-compat with every pre-US-14 caller).
function MahjongLogic.freeTiles(board, id)
    if id == nil then id = "turtle" end
    local free = {}
    local seen = {}
    for _, p in ipairs(MahjongLogic.buildLayout(id)) do
        local key = MahjongLogic.posKey(p.x, p.y, p.layer)
        local kind = board[key]
        if kind then
            seen[key] = true
            if MahjongLogic.isFree(board, p.x, p.y, p.layer) then
                free[#free + 1] = { x = p.x, y = p.y, layer = p.layer, kind = kind }
            end
        end
    end
    for key, kind in pairs(board) do
        if not seen[key] then
            -- x/y may be fractional (head/tail/cap tiles sit on the half grid).
            local x, y, layer = key:match("^([%d%.]+),([%d%.]+),(%d+)$")
            if not x then
                error("freeTiles: malformed board key " .. tostring(key))
            end
            x, y, layer = tonumber(x), tonumber(y), tonumber(layer)
            if MahjongLogic.isFree(board, x, y, layer) then
                free[#free + 1] = { x = x, y = y, layer = layer, kind = kind }
            end
        end
    end
    return free
end

-- True if at least one pair of matching free tiles can be removed.
-- The free-tile count is bounded by the tile count (<= 144), so an O(n^2)
-- scan of the free tiles is fine for a board game.
function MahjongLogic.hasMoves(board, id)
    local free = MahjongLogic.freeTiles(board, id)
    for i = 1, #free - 1 do
        for j = i + 1, #free do
            if MahjongLogic.matches(free[i].kind, free[j].kind) then
                return true
            end
        end
    end
    return false
end

-- Scoring ---------------------------------------------------------------
--
-- US-09: base 10 points per matched pair, plus a +5 consecutive bonus when
-- the pair belongs to the same tile group as the previous match (a chain).
-- A timer bonus is not implemented (elapsed-time tracking is out of scope).
local SCORE_PER_PAIR = 10
local CHAIN_BONUS = 5
MahjongLogic.SCORE_PER_PAIR = SCORE_PER_PAIR
MahjongLogic.CHAIN_BONUS = CHAIN_BONUS

-- US-18: using a hint or reshuffling costs points, so those helps are a real
-- trade-off. The penalty is applied at USE time and is NOT part of the pair
-- history, so undo() restores only the pair's points (never a penalty).
local HINT_PENALTY = 5
local SHUFFLE_PENALTY = 10
MahjongLogic.HINT_PENALTY = HINT_PENALTY
MahjongLogic.SHUFFLE_PENALTY = SHUFFLE_PENALTY

-- Returns `score` minus `amount`, never going below 0 (a score can't go
-- negative, no matter how many helps are used).
function MahjongLogic.applyPenalty(score, amount)
    return math.max(0, (score or 0) - (amount or 0))
end

-- The chain group of a kind: suited/wind/dragon kinds chain with themselves
-- (group == the kind), flowers chain with any flower, seasons with any season.
-- This is the same grouping the match rule uses (MATCH_GROUP).
function MahjongLogic.matchGroup(kind)
    return MATCH_GROUP[kind]
end

-- Points awarded for matching a pair of `kind`, given the kind of the
-- previously matched pair (`prev_kind`, or nil for the first move). Base
-- score, plus the chain bonus when both matches are in the same tile group.
function MahjongLogic.pairPoints(prev_kind, kind)
    local points = SCORE_PER_PAIR
    if prev_kind then
        local prev_group = MATCH_GROUP[prev_kind]
        if prev_group and prev_group == MATCH_GROUP[kind] then
            points = points + CHAIN_BONUS
        end
    end
    return points
end

-- Formats elapsed seconds as "mm:ss" (zero-padded), e.g. 65 -> "01:05".
-- The HUD feedback band shows this permanently (US-10).
function MahjongLogic.formatElapsed(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Removal / win / hint ---------------------------------------------------
--
-- US-07: pair removal, win detection, and a free matching-pair finder. These
-- are the logic hooks the UI calls after every tap; the board widget's own
-- removePair() only drops the rendered widgets, the caller updates the logic
-- board FIRST (via removePair below) then the view.

-- Removes a matched pair of free tiles from the board. `a` and `b` are
-- { x, y, layer } tables. The board is mutated (both cells cleared) only when
-- the pair is valid: both cells hold tiles, they are distinct positions, both
-- tiles are free, and they match. Returns true, kind_a, kind_b on success,
-- false otherwise (with the board left unchanged).
function MahjongLogic.removePair(board, a, b)
    if not a or not b then return false end
    if a.x == b.x and a.y == b.y and a.layer == b.layer then return false end
    local ka = MahjongLogic.tileAt(board, a.x, a.y, a.layer)
    local kb = MahjongLogic.tileAt(board, b.x, b.y, b.layer)
    if not ka or not kb then return false end
    if not MahjongLogic.isFree(board, a.x, a.y, a.layer) then return false end
    if not MahjongLogic.isFree(board, b.x, b.y, b.layer) then return false end
    if not MahjongLogic.matches(ka, kb) then return false end
    board[MahjongLogic.posKey(a.x, a.y, a.layer)] = nil
    board[MahjongLogic.posKey(b.x, b.y, b.layer)] = nil
    return true, ka, kb
end

-- Restores a previously removed pair to the board. `a` and `b` are
-- { x, y, layer } tables, `ka` and `kb` are their tile kinds.
function MahjongLogic.undoPair(board, a, b, ka, kb)
    board[MahjongLogic.posKey(a.x, a.y, a.layer)] = ka
    board[MahjongLogic.posKey(b.x, b.y, b.layer)] = kb
end

-- True when the board is empty (every tile matched and removed).
function MahjongLogic.isWin(board)
    return MahjongLogic.tileCount(board) == 0
end

-- All distinct matching free pairs, as an array of { a = { x, y, layer, kind },
-- b = { x, y, layer, kind } } tables in free-tile scan order. Each unordered
-- pair of free tiles that matches counts once (so three free flowers = three
-- entries). Used by the US-08 hint to cycle through the available options on
-- repeated presses; the scan order is deterministic (freeTiles walks the
-- memoized layout, bottom layer first), so consecutive hints move forward.
function MahjongLogic.matchingFreePairs(board, id)
    local free = MahjongLogic.freeTiles(board, id)
    local pairs = {}
    for i = 1, #free - 1 do
        for j = i + 1, #free do
            if MahjongLogic.matches(free[i].kind, free[j].kind) then
                pairs[#pairs + 1] = { a = free[i], b = free[j] }
            end
        end
    end
    return pairs
end

-- The first matching free pair on the board, as { a = { x, y, layer, kind },
-- b = { x, y, layer, kind } }, or nil if no move exists. Used for the no-moves
-- check, the auto-solver (US-19) and the logic self-tests; the hint uses
-- matchingFreePairs to cycle through options.
function MahjongLogic.matchingFreePair(board, id)
    return MahjongLogic.matchingFreePairs(board, id)[1]
end

-- The number of distinct matching free pairs currently available — i.e. how
-- many legal moves could be made right now. Each unordered pair of free tiles
-- that matches counts once (so three free flowers = 3 available pairs).
function MahjongLogic.countFreePairs(board, id)
    local free = MahjongLogic.freeTiles(board, id)
    local count = 0
    for i = 1, #free - 1 do
        for j = i + 1, #free do
            if MahjongLogic.matches(free[i].kind, free[j].kind) then
                count = count + 1
            end
        end
    end
    return count
end

-- Shuffle ----------------------------------------------------------------

-- Reshuffles the tiles remaining on a board IN PLACE: the remaining kinds are
-- reassigned to the remaining positions, so the board keeps the same keys, the
-- same tile count, and the same multiset of kinds — only their placement
-- changes. `rng` is nil (math.random), an integer seed, or a [0,1) function.
function MahjongLogic.shuffleBoard(board, rng)
    rng = rng or math.random
    local positions = {}
    local kinds = {}
    for key, kind in pairs(board) do
        positions[#positions + 1] = key
        kinds[#kinds + 1] = kind
    end
    MahjongLogic.shuffle(kinds, rng)
    for i, key in ipairs(positions) do
        board[key] = kinds[i]
    end
    return board
end

-- Persistence ------------------------------------------------------------
--
-- US-10: the whole game state is serialized to a plain Lua table that
-- LuaSettings can write to disk. The board is stored as-is (a flat
-- posKey -> kind table, which is what makes this story a plain table), and
-- the undo history is flattened to compact 10-field arrays
-- { ax, ay, al, bx, by, bl, ka, kb, score, prev_last } instead of nested
-- tables, so a mid-game save stays small.
--
-- A valid mid-game state satisfies `tileCount(board) + 2 * #history == 144`
-- (every move removes exactly 2 tiles and pushes exactly one history entry);
-- deserializeGameState enforces that plus per-field checks, and returns nil
-- for anything a real game could not have produced.

-- Serializes the current game for persistence. `history` is the UI's undo
-- stack ({ a, b, ka, kb, score, prev_last } records), `last_match_kind` the
-- chain-scoring kind, `elapsed` the elapsed seconds, `hints_used` /
-- `shuffles_used` the per-game help counters (US-18), and `layout` the layout
-- id the board was dealt on (US-14, defaults to "turtle"). Returns a fresh
-- table (no references into live state, so later mutations can't corrupt the
-- save).
function MahjongLogic.serializeGameState(board, history, score, last_match_kind,
                                          elapsed, hints_used, shuffles_used, layout)
    local out_board = {}
    for key, kind in pairs(board) do
        out_board[key] = kind
    end
    local out_history = {}
    for _, m in ipairs(history or {}) do
        out_history[#out_history + 1] = {
            m.a.x, m.a.y, m.a.layer,
            m.b.x, m.b.y, m.b.layer,
            m.ka, m.kb, m.score, m.prev_last,
        }
    end
    return {
        v = 2,
        layout = layout or "turtle",
        board = out_board,
        history = out_history,
        score = score or 0,
        last = last_match_kind,
        elapsed = elapsed or 0,
        hints = hints_used or 0,
        shuffles = shuffles_used or 0,
    }
end

-- Validates and restores a serialized game state. Returns
-- { board, history, score, last_match_kind, elapsed, hints_used, shuffles_used,
-- layout } with the history un-flattened back to the UI's record shape, or nil
-- if the state is corrupt/invalid (the caller then silently starts a new
-- game).
--
-- Versioning (US-14): v1 saves have no `layout` field and restore as Turtle;
-- v2 saves carry `layout` and every board/history position is validated
-- against THAT layout's position set. An unknown saved layout id is corrupt
-- (the caller deals fresh).
function MahjongLogic.deserializeGameState(data)
    if type(data) ~= "table" then return nil end
    if data.v ~= 1 and data.v ~= 2 then return nil end

    -- Layout id: v1 -> "turtle" (no field); v2 -> the stored id (validated).
    local layout_id
    if data.v == 1 then
        layout_id = "turtle"
    else
        layout_id = data.layout or "turtle"
        if type(layout_id) ~= "string" or not MahjongLogic.layouts[layout_id] then
            return nil
        end
    end

    local board = data.board
    if type(board) ~= "table" then return nil end
    local history = data.history
    if type(history) ~= "table" then return nil end

    -- Board: every key must be a canonical position of the saved layout,
    -- every kind valid, count even.
    local n = 0
    local board_keys = {}
    for key, kind in pairs(board) do
        if not MahjongLogic.isKind(kind) then return nil end
        local x, y, layer = key:match("^([%d%.]+),([%d%.]+),(%d+)$")
        if not x then return nil end
        x, y, layer = tonumber(x), tonumber(y), tonumber(layer)
        if not MahjongLogic.isLayoutPosition(x, y, layer, layout_id) then return nil end
        board_keys[key] = true
        n = n + 1
    end
    if n % 2 ~= 0 then return nil end

    -- History: flat records, positions valid + distinct, kinds valid and
    -- matching (a removed pair must have matched), positions not on the board.
    local out_history = {}
    for _, m in ipairs(history) do
        if type(m) ~= "table" then return nil end
        local ax, ay, al, bx, by, bl = m[1], m[2], m[3], m[4], m[5], m[6]
        local ka, kb, ms, ml = m[7], m[8], m[9], m[10]
        if type(ax) ~= "number" or type(ay) ~= "number" or type(al) ~= "number"
            or type(bx) ~= "number" or type(by) ~= "number" or type(bl) ~= "number" then
            return nil
        end
        if not MahjongLogic.isLayoutPosition(ax, ay, al, layout_id)
            or not MahjongLogic.isLayoutPosition(bx, by, bl, layout_id) then
            return nil
        end
        if ax == bx and ay == by and al == bl then return nil end
        if not MahjongLogic.isKind(ka) or not MahjongLogic.isKind(kb) then return nil end
        if not MahjongLogic.matches(ka, kb) then return nil end
        if board_keys[MahjongLogic.posKey(ax, ay, al)]
            or board_keys[MahjongLogic.posKey(bx, by, bl)] then
            return nil
        end
        if type(ms) ~= "number" or ms < 0 then return nil end
        if ml ~= nil and not MahjongLogic.isKind(ml) then return nil end
        out_history[#out_history + 1] = {
            a = { x = ax, y = ay, layer = al },
            b = { x = bx, y = by, layer = bl },
            ka = ka, kb = kb, score = ms, prev_last = ml,
        }
    end
    if n + 2 * #out_history ~= 144 then return nil end

    local score = data.score
    if type(score) ~= "number" or score < 0 then return nil end
    local last = data.last
    if last ~= nil and not MahjongLogic.isKind(last) then return nil end
    local elapsed = data.elapsed
    if elapsed == nil then
        elapsed = 0
    elseif type(elapsed) ~= "number" or elapsed < 0 then
        return nil
    end

    -- US-18: per-game help counters. Absent on a pre-US-18 save -> 0 (a valid
    -- older state restores fine); present but non-count invalidates.
    local hints_used = data.hints
    if hints_used == nil then
        hints_used = 0
    elseif type(hints_used) ~= "number" or hints_used < 0 or math.floor(hints_used) ~= hints_used then
        return nil
    end
    local shuffles_used = data.shuffles
    if shuffles_used == nil then
        shuffles_used = 0
    elseif type(shuffles_used) ~= "number" or shuffles_used < 0 or math.floor(shuffles_used) ~= shuffles_used then
        return nil
    end

    -- Copy the board so the restored game never aliases the stored table.
    local out_board = {}
    for key, kind in pairs(board) do out_board[key] = kind end

    return {
        board = out_board,
        history = out_history,
        score = score,
        last_match_kind = last,
        elapsed = elapsed,
        hints_used = hints_used,
        shuffles_used = shuffles_used,
        layout = layout_id,
    }
end

-- Flat projection grid -----------------------------------------------------
--
-- The UI renders the 3D board as a flat grid: each (x, y) cell shows the
-- topmost tile at that position. These helpers give the grid extents and the
-- topmost tile lookup the renderer needs.

-- Highest layer used by the Turtle layout. Kept as a constant for backward
-- compat with pre-US-14 callers (board widget, tests); per-layout code uses
-- maxLayer(id) instead.
MahjongLogic.MAX_LAYER = 4

-- Highest layer used by a layout (US-14). Cached per id.
function MahjongLogic.maxLayer(id)
    if id == nil then id = "turtle" end
    if not _max_layer_cache[id] then
        local m = 0
        for _, p in ipairs(MahjongLogic.buildLayout(id)) do
            if p.layer > m then m = p.layer end
        end
        _max_layer_cache[id] = m
    end
    return _max_layer_cache[id]
end

-- Bounds of a layout's projection grid as { x_min, x_max, y_min, y_max }.
-- Static per id, so cached like buildLayout(id) (callers must not mutate).
function MahjongLogic.gridBounds(id)
    if id == nil then id = "turtle" end
    if not _bounds_cache[id] then
        local bounds = {
            x_min = math.huge,
            x_max = -math.huge,
            y_min = math.huge,
            y_max = -math.huge,
        }
        for _, p in ipairs(MahjongLogic.buildLayout(id)) do
            bounds.x_min = math.min(bounds.x_min, p.x)
            bounds.x_max = math.max(bounds.x_max, p.x)
            bounds.y_min = math.min(bounds.y_min, p.y)
            bounds.y_max = math.max(bounds.y_max, p.y)
        end
        _bounds_cache[id] = bounds
    end
    return _bounds_cache[id]
end

-- True if (x, y, layer) is one of the saved layout's positions. Used to
-- validate deserialized state (US-10): a position that is not part of the
-- layout was not produced by a real game. `id` defaults to "turtle".
function MahjongLogic.isLayoutPosition(x, y, layer, id)
    if id == nil then id = "turtle" end
    if not _layout_key_cache[id] then
        _layout_key_cache[id] = {}
        for _, p in ipairs(MahjongLogic.buildLayout(id)) do
            _layout_key_cache[id][MahjongLogic.posKey(p.x, p.y, p.layer)] = true
        end
    end
    return _layout_key_cache[id][MahjongLogic.posKey(x, y, layer)] == true
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

    -- Turtle layout: exactly 144 unique positions, per-layer counts matching
    -- the classic Turtle (87/36/16/4/1), grid within x<=14, y<=7.
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
    check(layer_counts[0] == 87, "layer 0 has 87 tiles (got " .. tostring(layer_counts[0]) .. ")")
    check(layer_counts[1] == 36, "layer 1 has 36 tiles (got " .. tostring(layer_counts[1]) .. ")")
    check(layer_counts[2] == 16, "layer 2 has 16 tiles (got " .. tostring(layer_counts[2]) .. ")")
    check(layer_counts[3] == 4, "layer 3 has 4 tiles (got " .. tostring(layer_counts[3]) .. ")")
    check(layer_counts[4] == 1, "layer 4 has 1 tile (got " .. tostring(layer_counts[4]) .. ")")
    check(max_x == 14 and max_y == 7, "grid bounds are x<=14, y<=7 (got " .. max_x .. "x" .. max_y .. ")")
    for _, s in ipairs(TURTLE_SPEC) do
        if s.kind == "row" then
            for x = s.x_min, s.x_max do
                check(seen[MahjongLogic.posKey(x, s.y, s.layer)] ~= nil,
                    "row tile " .. x .. "," .. s.y .. ",L" .. s.layer .. " is present")
            end
        elseif s.kind == "block" then
            for y = s.y_min, s.y_max do
                for x = s.x_min, s.x_max do
                    check(seen[MahjongLogic.posKey(x, y, s.layer)] ~= nil,
                        "block tile " .. x .. "," .. y .. ",L" .. s.layer .. " is present")
                end
            end
        else
            check(seen[MahjongLogic.posKey(s.x, s.y, s.layer)] ~= nil,
                "tile " .. s.x .. "," .. s.y .. ",L" .. s.layer .. " is present")
        end
    end

    -- Layout registry (US-14/US-15/US-16) ---------------------------------------
    -- The registry now enumerates {"bridge", "spider", "turtle"} (US-15 adds
    -- Spider, US-16 adds Bridge); the layout-dependent functions accept an id
    -- and default to "turtle" so the byte-identical Turtle results fall out of
    -- the parameterized paths.
    local ids = MahjongLogic.layoutIds()
    check(#ids == 3 and ids[1] == "bridge" and ids[2] == "spider" and ids[3] == "turtle",
        "layoutIds returns exactly {bridge, spider, turtle} (got " .. table.concat(ids, ",") .. ")")
    check(MahjongLogic.layoutName("turtle") == "Turtle", "layoutName returns the registered name")
    check(MahjongLogic.layoutName("spider") == "Spider", "layoutName returns Spider's registered name")
    check(MahjongLogic.layoutName("bridge") == "Bridge", "layoutName returns Bridge's registered name")
    check(MahjongLogic.layoutName("nope") == "nope",
        "layoutName falls back to the id for an unknown layout")
    check(MahjongLogic.buildLayout("turtle") == MahjongLogic.buildLayout(),
        "buildLayout(id) and buildLayout() share one memoized Turtle table")
    check(MahjongLogic.buildLayout("turtle") == MahjongLogic.buildLayout("turtle"),
        "buildLayout(id) is memoized per id")
    check(MahjongLogic.gridBounds("turtle") == MahjongLogic.gridBounds(),
        "gridBounds(id) and gridBounds() share one memoized Turtle bounds")
    check(MahjongLogic.maxLayer("turtle") == 4, "maxLayer(turtle) == 4")
    check(MahjongLogic.isLayoutPosition(6.5, 3.5, 4, "turtle"),
        "isLayoutPosition accepts a Turtle position with an explicit id")
    check(not MahjongLogic.isLayoutPosition(99, 99, 0, "turtle"),
        "isLayoutPosition rejects an out-of-layout position with an explicit id")

    -- A throwaway layout can be registered at test time and drives the
    -- parameterized paths end-to-end (deal → free tiles → bounds →
    -- position check), mirroring what tests/us14_layouts.lua does with the
    -- board widget. Use a small 4-position pyramid so the test is cheap.
    local toy_spec = {
        { layer = 0, kind = "row",   x_min = 0, x_max = 1, y = 0 },
        { layer = 0, kind = "row",   x_min = 0, x_max = 1, y = 1 },
        { layer = 1, kind = "block", x_min = 0, x_max = 1, y_min = 0, y_max = 1 },
    }
    MahjongLogic.registerLayout{ id = "toy", name = "Toy", spec = toy_spec }
    local toy_ids = MahjongLogic.layoutIds()
    check(#toy_ids == 4 and toy_ids[1] == "bridge" and toy_ids[2] == "spider"
        and toy_ids[3] == "toy" and toy_ids[4] == "turtle",
        "registerLayout adds the id; layoutIds returns them sorted")
    check(#MahjongLogic.buildLayout("toy") == 8, "the toy layout has 8 positions")
    check(MahjongLogic.maxLayer("toy") == 1, "the toy layout's max layer is 1")
    check(MahjongLogic.isLayoutPosition(0, 0, 1, "toy"),
        "isLayoutPosition validates against the toy layout")
    check(not MahjongLogic.isLayoutPosition(2, 0, 0, "toy"),
        "isLayoutPosition rejects a Turtle-only position against the toy layout")
    local toy_bounds = MahjongLogic.gridBounds("toy")
    check(toy_bounds.x_min == 0 and toy_bounds.x_max == 1
            and toy_bounds.y_min == 0 and toy_bounds.y_max == 1,
        "gridBounds(toy) extents are 0..1 x 0..1")
    -- newGame on the toy layout: 8 tiles dealt, deterministic for a fixed seed.
    -- The deck is 144 (Turtle-sized) but only the first 8 land on toy
    -- positions, so the toy board is an 8-tile subset of the shuffled deck —
    -- fine for exercising the parameterized deal + free-tile paths.
    local tg1 = MahjongLogic.newGame("toy", 42)
    check(MahjongLogic.tileCount(tg1) == 8, "newGame(toy,42) deals 8 tiles")
    local tg2 = MahjongLogic.newGame("toy", 42)
    local toy_same = true
    for k, v in pairs(tg1) do
        if tg2[k] ~= v then toy_same = false break end
    end
    check(toy_same, "newGame(toy,42) is deterministic for a fixed seed")
    check(#MahjongLogic.freeTiles(tg1, "toy") == 4,
        "freeTiles(toy) finds the 4 top-layer tiles (all free)")

    -- Backward-compat: newGame(42) and newGame() (no id) still deal Turtle.
    check(MahjongLogic.tileCount(MahjongLogic.newGame(42)) == 144,
        "newGame(42) still deals a 144-tile Turtle board (old call shape)")
    -- Deregister the toy layout so the rest of the self-tests see only Turtle
    -- (the registry is module-global, and later assertions count exactly one
    -- id implicitly via the Turtle-specific layout checks above).
    MahjongLogic.layouts["toy"] = nil
    _layout_cache["toy"] = nil
    _bounds_cache["toy"] = nil
    _layout_key_cache["toy"] = nil
    _max_layer_cache["toy"] = nil
    check(#MahjongLogic.layoutIds() == 3, "deregistering toy restores the {bridge, spider, turtle} registry")

    -- Spider layout (US-15) -----------------------------------------------
    -- The classic Spider board: 144 positions, 65/53/25/1 across 4 layers.
    local spider = MahjongLogic.buildLayout("spider")
    check(#spider == 144, "Spider layout has 144 positions (got " .. #spider .. ")")
    local spider_layers = {}
    local spider_seen = {}
    for _, p in ipairs(spider) do
        spider_layers[p.layer] = (spider_layers[p.layer] or 0) + 1
        local key = MahjongLogic.posKey(p.x, p.y, p.layer)
        check(not spider_seen[key], "no duplicate Spider position " .. key)
        spider_seen[key] = true
    end
    check(spider_layers[0] == 65, "Spider layer 0 has 65 tiles (got " .. tostring(spider_layers[0]) .. ")")
    check(spider_layers[1] == 53, "Spider layer 1 has 53 tiles (got " .. tostring(spider_layers[1]) .. ")")
    check(spider_layers[2] == 25, "Spider layer 2 has 25 tiles (got " .. tostring(spider_layers[2]) .. ")")
    check(spider_layers[3] == 1, "Spider layer 3 has 1 tile (got " .. tostring(spider_layers[3]) .. ")")
    check(MahjongLogic.maxLayer("spider") == 3, "maxLayer(spider) == 3")
    local spider_bounds = MahjongLogic.gridBounds("spider")
    check(spider_bounds.x_min == 0.5 and spider_bounds.x_max == 14.5
        and spider_bounds.y_min == 0 and spider_bounds.y_max == 7,
        "Spider grid bounds are x=0.5..14.5, y=0..7")
    -- Spider deal + free tiles + hasMoves.
    local sg = MahjongLogic.newGame("spider", 42)
    check(MahjongLogic.tileCount(sg) == 144, "newGame('spider', 42) deals 144 tiles")
    local sg_free = MahjongLogic.freeTiles(sg, "spider")
    check(#sg_free > 0, "Spider board has free tiles")
    check(MahjongLogic.hasMoves(sg, "spider"), "Spider board has at least one move")
    check(MahjongLogic.isFree(sg, 7.5, 4.5, 3), "Spider's peak tile (7.5, 4.5, L3) is free")
    -- Spider persistence round-trip.
    local sp_pair = MahjongLogic.matchingFreePair(sg, "spider")
    check(sp_pair ~= nil, "Spider board has a matching free pair to remove")
    local sp_ok, sp_ka, sp_kb = MahjongLogic.removePair(sg, sp_pair.a, sp_pair.b)
    check(sp_ok, "removePair works on a Spider board")
    local sp_hist = {
        { a = sp_pair.a, b = sp_pair.b, ka = sp_ka, kb = sp_kb, score = 10, prev_last = nil },
    }
    local sp_ser = MahjongLogic.serializeGameState(sg, sp_hist, 10, sp_ka, 99, 0, 0, "spider")
    check(sp_ser.layout == "spider", "serialized Spider state carries layout=spider")
    local sp_restored = MahjongLogic.deserializeGameState(sp_ser)
    check(sp_restored ~= nil and sp_restored.layout == "spider",
        "deserialize restores a Spider state")
    check(MahjongLogic.tileCount(sp_restored.board) == 142,
        "restored Spider board has 142 tiles after one removal")

    -- Bridge layout (US-16) -----------------------------------------------
    -- The classic Four Bridges board: 144 positions, 88/36/16/4 across 4 layers.
    local bridge = MahjongLogic.buildLayout("bridge")
    check(#bridge == 144, "Bridge layout has 144 positions (got " .. #bridge .. ")")
    local bridge_layers = {}
    local bridge_seen = {}
    for _, p in ipairs(bridge) do
        bridge_layers[p.layer] = (bridge_layers[p.layer] or 0) + 1
        local key = MahjongLogic.posKey(p.x, p.y, p.layer)
        check(not bridge_seen[key], "no duplicate Bridge position " .. key)
        bridge_seen[key] = true
    end
    check(bridge_layers[0] == 88, "Bridge layer 0 has 88 tiles (got " .. tostring(bridge_layers[0]) .. ")")
    check(bridge_layers[1] == 36, "Bridge layer 1 has 36 tiles (got " .. tostring(bridge_layers[1]) .. ")")
    check(bridge_layers[2] == 16, "Bridge layer 2 has 16 tiles (got " .. tostring(bridge_layers[2]) .. ")")
    check(bridge_layers[3] == 4, "Bridge layer 3 has 4 tiles (got " .. tostring(bridge_layers[3]) .. ")")
    check(MahjongLogic.maxLayer("bridge") == 3, "maxLayer(bridge) == 3")
    local bridge_bounds = MahjongLogic.gridBounds("bridge")
    check(bridge_bounds.x_min == 0 and bridge_bounds.x_max == 12
        and bridge_bounds.y_min == 0 and bridge_bounds.y_max == 8,
        "Bridge grid bounds are x=0..12, y=0..8")
    -- Bridge deal + free tiles + hasMoves.
    local bg = MahjongLogic.newGame("bridge", 42)
    check(MahjongLogic.tileCount(bg) == 144, "newGame('bridge', 42) deals 144 tiles")
    local bg_free = MahjongLogic.freeTiles(bg, "bridge")
    check(#bg_free > 0, "Bridge board has free tiles")
    check(MahjongLogic.hasMoves(bg, "bridge"), "Bridge board has at least one move")
    check(MahjongLogic.isFree(bg, 3.5, 1.5, 3), "Bridge peak tile (3.5, 1.5, L3) is free")
    check(MahjongLogic.isFree(bg, 8.5, 6.5, 3), "Bridge peak tile (8.5, 6.5, L3) is free")
    -- Bridge persistence round-trip.
    local bp_pair = MahjongLogic.matchingFreePair(bg, "bridge")
    check(bp_pair ~= nil, "Bridge board has a matching free pair to remove")
    local bp_ok, bp_ka, bp_kb = MahjongLogic.removePair(bg, bp_pair.a, bp_pair.b)
    check(bp_ok, "removePair works on a Bridge board")
    local bp_ser = MahjongLogic.serializeGameState(bg, {
        { a = bp_pair.a, b = bp_pair.b, ka = bp_ka, kb = bp_kb, score = 10, prev_last = nil },
    }, 10, bp_ka, 99, 0, 0, "bridge")
    check(bp_ser.layout == "bridge", "serialized Bridge state carries layout=bridge")
    local bp_restored = MahjongLogic.deserializeGameState(bp_ser)
    check(bp_restored ~= nil and bp_restored.layout == "bridge",
        "deserialize restores a Bridge state")
    check(MahjongLogic.tileCount(bp_restored.board) == 142,
        "restored Bridge board has 142 tiles after one removal")

    -- newGame: same seed is deterministic; different seed differs.
    local g1 = MahjongLogic.newGame(42)
    local g2 = MahjongLogic.newGame(42)
    check(MahjongLogic.tileCount(g1) == 144, "newGame(42) places 144 tiles")
    local same = true
    for k, v in pairs(g1) do
        if g2[k] ~= v then same = false break end
    end
    check(same, "newGame(42) is deterministic for a fixed seed")
    -- Explicit id form: newGame("turtle", 42) deals the same board as newGame(42).
    local g2b = MahjongLogic.newGame("turtle", 42)
    local same_explicit = true
    for k, v in pairs(g1) do
        if g2b[k] ~= v then same_explicit = false break end
    end
    check(same_explicit, "newGame('turtle', 42) matches newGame(42)")
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

    -- Free-tile detection ------------------------------------------------
    local boardWith = function(tiles)
        local board = {}
        for _, t in ipairs(tiles) do
            board[MahjongLogic.posKey(t[1], t[2], t[3])] = t[4]
        end
        return board
    end

    local b = boardWith{ {2,2,0,"b1"}, {3,2,0,"b2"}, {2,2,1,"c1"} }
    check(MahjongLogic.tileAt(b, 2, 2, 0) == "b1", "tileAt returns the kind at (2,2,L0)")
    check(MahjongLogic.tileAt(b, 2, 2, 1) == "c1", "tileAt returns the kind at (2,2,L1)")
    check(MahjongLogic.tileAt(b, 9, 9, 0) == nil, "tileAt returns nil for an empty cell")
    check(not MahjongLogic.isFree(b, 9, 9, 0), "empty cell is not a free tile")
    check(not MahjongLogic.isFree(b, 2, 2, 0), "tile covered from above is not free")
    check(MahjongLogic.isFree(b, 2, 2, 1), "top tile with open sides is free")
    check(MahjongLogic.isFree(b, 3, 2, 0), "tile with one open side is free")

    local b2 = boardWith{ {4,2,0,"d1"}, {5,2,0,"d2"}, {6,2,0,"d3"} }
    check(not MahjongLogic.isFree(b2, 5, 2, 0), "tile with both sides occupied is not free")
    check(MahjongLogic.isFree(b2, 4, 2, 0), "edge tile with one side open is free")
    check(MahjongLogic.isFree(b2, 6, 2, 0), "edge tile with one side open is free")

    local b_half = boardWith{ {2,2,0,"b1"}, {1,1.5,0,"b2"}, {1,2.5,0,"b3"}, {3,2,0,"b4"} }
    check(not MahjongLogic.isFree(b_half, 2, 2, 0), "tile blocked by half-grid neighbours on both sides is not free")
    check(MahjongLogic.isFree(boardWith{ {2,2,0,"b1"}, {1,1.5,0,"b2"}, {1,2.5,0,"b3"} }, 2, 2, 0),
        "tile with one side (left) blocked by two half-neighbours but other side open is free")

    local b_cap = boardWith{ {6,3,0,"b1"}, {6.5,3.5,1,"b2"} }
    check(not MahjongLogic.isFree(b_cap, 6, 3, 0), "tile partially covered from above is not free")

    local free = MahjongLogic.freeTiles(b)
    check(#free == 2, "freeTiles finds exactly the free tiles (got " .. #free .. ")")
    local free_ok = true
    for _, t in ipairs(free) do
        if not MahjongLogic.isFree(b, t.x, t.y, t.layer) then free_ok = false end
    end
    check(free_ok, "every freeTiles entry passes isFree")

    -- Removing a tile exposes the one directly below it.
    local b3 = boardWith{ {10,2,0,"east"}, {10,2,1,"west"} }
    check(not MahjongLogic.isFree(b3, 10, 2, 0), "covered tile is not free before removal")
    check(MahjongLogic.isFree(b3, 10, 2, 1), "covering tile is free")
    b3[MahjongLogic.posKey(10, 2, 1)] = nil
    check(MahjongLogic.tileAt(b3, 10, 2, 1) == nil, "removed tile is gone from the board")
    check(MahjongLogic.isFree(b3, 10, 2, 0), "tile becomes free after the tile above is removed")

    -- hasMoves
    local m1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"} }
    check(MahjongLogic.hasMoves(m1), "two matching free tiles -> hasMoves true")
    check(#MahjongLogic.freeTiles(m1) == 2, "isolated layer-0 tiles are both free")
    local m2 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b2"} }
    check(not MahjongLogic.hasMoves(m2), "two free but unmatched tiles -> hasMoves false")
    local m3 = boardWith{ {2,2,0,"flower1"}, {4,2,0,"flower2"} }
    check(MahjongLogic.hasMoves(m3), "any two free flowers count as a move")
    local m4 = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"}, {4,2,0,"b2"} }
    check(not MahjongLogic.hasMoves(m4), "covered matching tiles are not counted by hasMoves")
    check(not MahjongLogic.hasMoves({}), "empty board has no moves")
    check(#MahjongLogic.freeTiles({}) == 0, "empty board has no free tiles")

    -- Removal / win / hint (US-07) --------------------------------------
    local r1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"} }
    check(MahjongLogic.removePair(r1, { x = 2, y = 2, layer = 0 }, { x = 4, y = 2, layer = 0 }) == true,
        "removePair removes a valid matching free pair")
    check(MahjongLogic.tileCount(r1) == 1 and MahjongLogic.tileAt(r1, 2, 2, 0) == nil
        and MahjongLogic.tileAt(r1, 4, 2, 0) == nil,
        "removePair cleared exactly the two cells")
    check(MahjongLogic.tileAt(r1, 6, 2, 0) == "c1", "removePair leaves other tiles untouched")

    local r2 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b2"} }
    check(MahjongLogic.removePair(r2, { x = 2, y = 2, layer = 0 }, { x = 4, y = 2, layer = 0 }) == false,
        "removePair rejects a non-matching pair")
    check(MahjongLogic.tileCount(r2) == 2, "rejected pair leaves the board unchanged")

    local r3 = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"}, {4,2,0,"b1"} }
    check(MahjongLogic.removePair(r3, { x = 2, y = 2, layer = 0 }, { x = 4, y = 2, layer = 0 }) == false,
        "removePair rejects a pair with a non-free (covered) tile")
    check(MahjongLogic.tileCount(r3) == 3, "covered-tile rejection leaves the board unchanged")
    check(MahjongLogic.removePair(r3, { x = 2, y = 2, layer = 1 }, { x = 4, y = 2, layer = 0 }) == true,
        "removePair accepts a free pair from different layers")
    check(MahjongLogic.tileCount(r3) == 1, "valid removal drops the count by 2")

    check(MahjongLogic.removePair(r2, { x = 2, y = 2, layer = 0 }, { x = 2, y = 2, layer = 0 }) == false,
        "removePair rejects tapping the same tile twice")
    check(MahjongLogic.removePair(r2, { x = 9, y = 9, layer = 0 }, { x = 4, y = 2, layer = 0 }) == false,
        "removePair rejects a missing tile")
    check(MahjongLogic.removePair(r2, nil, { x = 4, y = 2, layer = 0 }) == false,
        "removePair rejects a nil position")

    local r4 = boardWith{ {2,2,0,"flower1"}, {4,2,0,"flower3"} }
    check(MahjongLogic.removePair(r4, { x = 2, y = 2, layer = 0 }, { x = 4, y = 2, layer = 0 }) == true,
        "removePair accepts the flower rule (any flower matches any flower)")
    check(MahjongLogic.isWin(r4), "board is empty after removing its last pair")

    local w1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"} }
    check(not MahjongLogic.isWin(w1), "isWin is false while tiles remain")
    check(MahjongLogic.isWin({}), "isWin is true only when the board is empty")

    local mp1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"}, {8,2,0,"c2"} }
    local pair = MahjongLogic.matchingFreePair(mp1)
    check(pair ~= nil and pair.a.kind == pair.b.kind
        and MahjongLogic.matches(pair.a.kind, pair.b.kind),
        "matchingFreePair returns a matching free pair when one exists")
    check(MahjongLogic.isFree(mp1, pair.a.x, pair.a.y, pair.a.layer)
        and MahjongLogic.isFree(mp1, pair.b.x, pair.b.y, pair.b.layer),
        "matchingFreePair's pair is genuinely free")
    local mp2 = boardWith{ {2,2,0,"flower1"}, {4,2,0,"flower2"}, {6,2,0,"season1"} }
    pair = MahjongLogic.matchingFreePair(mp2)
    check(pair ~= nil and pair.a.kind ~= pair.b.kind and MahjongLogic.matches(pair.a.kind, pair.b.kind),
        "matchingFreePair honors the flower/season wildcard match")
    local mp3 = boardWith{ {2,2,0,"c1"}, {4,2,0,"c2"}, {6,2,0,"c3"} }
    check(MahjongLogic.matchingFreePair(mp3) == nil, "matchingFreePair returns nil when no move exists")
    check(MahjongLogic.matchingFreePair({}) == nil, "matchingFreePair returns nil on an empty board")

    -- All matching free pairs (US-08 hint cycling): each unordered matching
    -- pair counts once, in deterministic free-tile scan order.
    local mfp1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"}, {8,2,0,"c1"} }
    local all_pairs = MahjongLogic.matchingFreePairs(mfp1)
    check(#all_pairs == 2, "matchingFreePairs lists both distinct matching pairs")
    local mfp1_keys = {}
    for _, p in ipairs(all_pairs) do
        mfp1_keys[#mfp1_keys + 1] = MahjongLogic.posKey(p.a.x, p.a.y, p.a.layer)
            .. "/" .. MahjongLogic.posKey(p.b.x, p.b.y, p.b.layer)
    end
    check(mfp1_keys[1] ~= mfp1_keys[2], "matchingFreePairs does not repeat a pair")
    check(#MahjongLogic.matchingFreePairs(boardWith{ {2,2,0,"flower1"}, {4,2,0,"flower2"},
            {6,2,0,"flower3"} }) == 3,
        "matchingFreePairs honors the flower wildcard (3 flowers -> 3 pairs)")
    check(#MahjongLogic.matchingFreePairs(mp3) == 0, "matchingFreePairs is empty when no move exists")

    -- Free-pair counter (US-08 status line).
    check(MahjongLogic.countFreePairs(mp3) == 0, "countFreePairs is 0 when no free pair matches")
    check(MahjongLogic.countFreePairs({}) == 0, "countFreePairs is 0 on an empty board")
    local cf1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"}, {8,2,0,"c2"} }
    check(MahjongLogic.countFreePairs(cf1) == 1,
        "countFreePairs counts the single matching free pair")
    local cf2 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"b1"}, {8,2,0,"b2"} }
    check(MahjongLogic.countFreePairs(cf2) == 3,
        "three free b1 tiles give 3 distinct matching pairs")
    local cf3 = boardWith{ {2,2,0,"flower1"}, {4,2,0,"flower2"}, {6,2,0,"flower3"} }
    check(MahjongLogic.countFreePairs(cf3) == 3,
        "countFreePairs honors the flower wildcard (3 flowers -> 3 pairs)")
    local cf4 = boardWith{ {2,2,0,"b1"}, {2,2,1,"b1"}, {4,2,0,"b1"} }
    check(MahjongLogic.countFreePairs(cf4) == 1,
        "countFreePairs ignores covered matching tiles")
    check(MahjongLogic.countFreePairs(mp1) == 1,
        "countFreePairs matches matchingFreePair's availability on mp1")

    -- Shuffle preserves the remaining multiset and the position set (US-07).
    local s1 = boardWith{ {2,2,0,"b1"}, {4,2,0,"b1"}, {6,2,0,"c1"}, {8,2,0,"c2"} }
    local s1_keys, s1_kinds = {}, {}
    for k, v in pairs(s1) do s1_keys[#s1_keys + 1] = k; s1_kinds[#s1_kinds + 1] = v end
    table.sort(s1_keys)
    MahjongLogic.shuffleBoard(s1, MahjongLogic.newRng(11))
    check(MahjongLogic.tileCount(s1) == 4, "shuffleBoard keeps the tile count")
    local s2_keys, s2_kinds = {}, {}
    for k, v in pairs(s1) do s2_keys[#s2_keys + 1] = k; s2_kinds[#s2_kinds + 1] = v end
    table.sort(s2_keys)
    local key_same = #s1_keys == #s2_keys
    if key_same then
        for i = 1, #s1_keys do
            if s1_keys[i] ~= s2_keys[i] then key_same = false break end
        end
    end
    check(key_same, "shuffleBoard keeps the same positions (same keys)")
    table.sort(s1_kinds)
    table.sort(s2_kinds)
    local multiset_same = #s1_kinds == #s2_kinds
    if multiset_same then
        for i = 1, #s1_kinds do
            if s1_kinds[i] ~= s2_kinds[i] then multiset_same = false break end
        end
    end
    check(multiset_same, "shuffleBoard preserves the multiset of remaining tiles")

    -- Flat projection helpers -------------------------------------------
    local bounds = MahjongLogic.gridBounds()
    check(bounds.x_min == 0 and bounds.x_max == 14, "grid x extents are 0..14")
    check(bounds.y_min == 0 and bounds.y_max == 7, "grid y extents are 0..7")

    -- Bevel-variant icons (2.5D bevels only on exposed edges): a same-layer
    -- neighbour below hides the bottom bevel, one to the right hides the right
    -- bevel.
    local bv = boardWith{
        {2,2,0,"b1"}, {3,2,0,"b2"}, {2,3,0,"b3"}, {3,3,0,"b4"},
    }
    check(MahjongLogic.iconForTile(bv, 2, 2, 0) == "b1_n",
        "tile with right + bottom neighbours draws no bevels (b1_n)")
    check(MahjongLogic.iconForTile(bv, 3, 2, 0) == "b2_nb",
        "tile with only a bottom neighbour keeps the right bevel (b2_nb)")
    check(MahjongLogic.iconForTile(bv, 2, 3, 0) == "b3_nr",
        "tile with only a right neighbour keeps the bottom bevel (b3_nr)")
    check(MahjongLogic.iconForTile(bv, 3, 3, 0) == "b4",
        "corner tile with no neighbours keeps both bevels (b4)")
    check(MahjongLogic.iconForTile(boardWith{ {5,5,0,"east"} }, 5, 5, 0) == "east",
        "lone tile keeps both bevels")
    check(MahjongLogic.iconForTile(bv, 9, 9, 0) == nil, "no icon for an empty cell")

    -- Half-grid protrusions: a tile adjacent to half of two other tiles loses
    -- the bevel on that side (fully covered edge), while a partly-exposed
    -- edge keeps it. On a full Turtle the head (0,3.5) faces (1,3) and (1,4)
    -- on its east, so it has no right bevel; the cap and the east tail tip
    -- are fully exposed and keep both bevels.
    local tur_bevel = MahjongLogic.newGame(42)
    local head_kind = MahjongLogic.tileAt(tur_bevel, 0, 3.5, 0)
    check(MahjongLogic.iconForTile(tur_bevel, 0, 3.5, 0) == head_kind .. "_nr",
        "head (0,3.5) has no right bevel (its east edge is covered by (1,3)+(1,4))")
    local cap_kind = MahjongLogic.tileAt(tur_bevel, 6.5, 3.5, 4)
    check(MahjongLogic.iconForTile(tur_bevel, 6.5, 3.5, 4) == cap_kind,
        "cap (6.5,3.5,L4) keeps both bevels")
    local tail_kind = MahjongLogic.tileAt(tur_bevel, 14, 3.5, 0)
    check(MahjongLogic.iconForTile(tur_bevel, 14, 3.5, 0) == tail_kind,
        "east tail tip (14,3.5) keeps both bevels")
    local tail_l_kind = MahjongLogic.tileAt(tur_bevel, 13, 3.5, 0)
    check(MahjongLogic.iconForTile(tur_bevel, 13, 3.5, 0) == tail_l_kind .. "_nr",
        "left tail tile (13,3.5) has no right bevel (neighbour (14,3.5) covers it)")
    -- (12,3) is only PARTIALLY covered on its east by the tail (which starts
    -- at y=3.5), so it keeps the right bevel.
    local b12_3 = MahjongLogic.tileAt(tur_bevel, 12, 3, 0)
    check(MahjongLogic.iconForTile(tur_bevel, 12, 3, 0) == b12_3 .. "_nb",
        "(12,3) keeps the right bevel (tail covers only half its east edge)")

    -- Half-grid protrusions: head/tail/cap are free on a full board, and
    -- freeTiles parses their fractional position keys.
    local tur = MahjongLogic.newGame(42)
    check(MahjongLogic.isFree(tur, 0, 3.5, 0), "head tile is free")
    check(not MahjongLogic.isFree(tur, 13, 3.5, 0), "left tail tile is blocked on both sides")
    check(MahjongLogic.isFree(tur, 14, 3.5, 0), "right tail tile is free")
    check(MahjongLogic.isFree(tur, 6.5, 3.5, 4), "cap tile is free")
    local ft = MahjongLogic.freeTiles(tur)
    local has_head = false
    for _, t in ipairs(ft) do
        if t.x == 0 and t.y == 3.5 and t.layer == 0 then has_head = true end
    end
    check(has_head, "freeTiles parses half-grid keys and lists the head tile")

    -- Scoring (US-09) -------------------------------------------------
    check(MahjongLogic.SCORE_PER_PAIR == 10, "base score is 10 per pair")
    check(MahjongLogic.CHAIN_BONUS == 5, "chain bonus is 5")
    check(MahjongLogic.pairPoints(nil, "b1") == 10, "first match scores the base 10")
    check(MahjongLogic.pairPoints("b1", "b1") == 15, "consecutive same-kind match chains (+5)")
    check(MahjongLogic.pairPoints("b2", "b1") == 10, "a different kind breaks the chain")
    check(MahjongLogic.pairPoints("flower1", "flower3") == 15, "flower pairs chain with any flower")
    check(MahjongLogic.pairPoints("season1", "season2") == 15, "season pairs chain with any season")
    check(MahjongLogic.pairPoints("flower1", "season1") == 10, "a flower never chains with a season")
    check(MahjongLogic.pairPoints("b1", "flower1") == 10, "a suited tile never chains with a flower")
    check(MahjongLogic.pairPoints("east", "east") == 15, "consecutive winds chain")
    check(MahjongLogic.matchGroup("b1") == "b1", "matchGroup of a suited kind is the kind")
    check(MahjongLogic.matchGroup("east") == "east", "matchGroup of a wind is the kind")
    check(MahjongLogic.matchGroup("red") == "red", "matchGroup of a dragon is the kind")
    check(MahjongLogic.matchGroup("flower1") == "flower", "matchGroup of a flower is flower")
    check(MahjongLogic.matchGroup("season1") == "season", "matchGroup of a season is season")

    -- US-18 penalties -------------------------------------------------
    check(MahjongLogic.HINT_PENALTY == 5, "hint penalty is 5")
    check(MahjongLogic.SHUFFLE_PENALTY == 10, "shuffle penalty is 10")
    check(MahjongLogic.applyPenalty(100, MahjongLogic.HINT_PENALTY) == 95,
        "applyPenalty subtracts the hint penalty")
    check(MahjongLogic.applyPenalty(100, MahjongLogic.SHUFFLE_PENALTY) == 90,
        "applyPenalty subtracts the shuffle penalty")
    check(MahjongLogic.applyPenalty(3, 5) == 0, "applyPenalty floors at 0")
    check(MahjongLogic.applyPenalty(0, 10) == 0, "applyPenalty(0, n) stays 0")
    check(MahjongLogic.applyPenalty(5, 10) == 0, "applyPenalty never goes negative")
    check(MahjongLogic.applyPenalty(nil, 5) == 0, "applyPenalty handles a nil score")

    -- Elapsed formatting (US-10).
    check(MahjongLogic.formatElapsed(0) == "00:00", "formatElapsed(0) is 00:00")
    check(MahjongLogic.formatElapsed(65) == "01:05", "formatElapsed(65) is 01:05")
    check(MahjongLogic.formatElapsed(599) == "09:59", "formatElapsed(599) is 09:59")
    check(MahjongLogic.formatElapsed(-3) == "00:00", "formatElapsed clamps negatives")
    check(MahjongLogic.formatElapsed(3600) == "60:00", "formatElapsed rolls past 59:59")

    -- Persistence round-trip (US-10) ------------------------------------
    check(MahjongLogic.isKind("b1") and MahjongLogic.isKind("east") and MahjongLogic.isKind("flower2"),
        "isKind accepts real kinds")
    check(not MahjongLogic.isKind("xyz") and not MahjongLogic.isKind(nil) and not MahjongLogic.isKind(42),
        "isKind rejects garbage")
    check(MahjongLogic.isLayoutPosition(6.5, 3.5, 4) and MahjongLogic.isLayoutPosition(0, 3.5, 0),
        "isLayoutPosition accepts real Turtle positions (cap, head)")
    check(not MahjongLogic.isLayoutPosition(99, 99, 0) and not MahjongLogic.isLayoutPosition(2, 2, 9),
        "isLayoutPosition rejects positions outside the Turtle")

    -- Play a small real game (remove one matching free pair) and round-trip it.
    local p_board = MahjongLogic.newGame(42)
    local p_pair = MahjongLogic.matchingFreePair(p_board)
    local p_ok, p_ka, p_kb = MahjongLogic.removePair(p_board, p_pair.a, p_pair.b)
    check(p_ok, "persistence test: removePair works on a real board")
    local p_hist = {
        { a = p_pair.a, b = p_pair.b, ka = p_ka, kb = p_kb, score = 10, prev_last = nil },
    }
    local p_serialized = MahjongLogic.serializeGameState(p_board, p_hist, 10, p_ka, 123)
    check(type(p_serialized) == "table" and p_serialized.v == 2, "serializeGameState returns a versioned table")
    check(p_serialized.layout == "turtle", "serialized state carries the layout id (turtle by default)")
    check(p_serialized.board[MahjongLogic.posKey(p_pair.a.x, p_pair.a.y, p_pair.a.layer)] == nil,
        "serialized board does not include the removed tile")
    check(#p_serialized.history == 1 and p_serialized.history[1][7] == p_ka,
        "serialized history is a flat 10-field record")
    local p_restored = MahjongLogic.deserializeGameState(p_serialized)
    check(p_restored ~= nil, "deserializeGameState accepts a valid mid-game state")
    check(MahjongLogic.tileCount(p_restored.board) == MahjongLogic.tileCount(p_board),
        "restored board has the same tile count")
    local p_same = true
    for k, v in pairs(p_board) do
        if p_restored.board[k] ~= v then p_same = false break end
    end
    check(p_same, "restored board matches the saved board")
    check(p_restored.score == 10 and p_restored.last_match_kind == p_ka and p_restored.elapsed == 123,
        "restored score/last/elapsed match")
    check(#p_restored.history == 1 and p_restored.history[1].ka == p_ka
        and p_restored.history[1].score == 10,
        "restored history is back in the UI record shape")
    -- The restored board is a COPY (mutations must not corrupt the source).
    p_restored.board["0,3.5,0"] = nil
    check(MahjongLogic.tileAt(p_board, 0, 3.5, 0) ~= nil,
        "restored board is a copy, not a reference to the saved table")

    -- US-18: the per-game help counters ride along in the game state.
    check(p_restored.hints_used == 0 and p_restored.shuffles_used == 0,
        "a save without counters restores them as 0 (pre-US-18 compat)")
    local p_serialized2 = MahjongLogic.serializeGameState(p_board, p_hist, 10, p_ka, 123, 3, 2)
    check(p_serialized2.hints == 3 and p_serialized2.shuffles == 2,
        "serialized state carries the hint/shuffle counters")
    local p_restored2 = MahjongLogic.deserializeGameState(p_serialized2)
    check(p_restored2 ~= nil and p_restored2.hints_used == 3 and p_restored2.shuffles_used == 2,
        "restored state round-trips the hint/shuffle counters")

    -- Rejection paths ------------------------------------------------------
    check(MahjongLogic.deserializeGameState(nil) == nil, "deserialize rejects nil")
    check(MahjongLogic.deserializeGameState({}) == nil, "deserialize rejects an empty table (no version)")
    local bad_v = p_serialized
    bad_v.v = 99
    check(MahjongLogic.deserializeGameState(bad_v) == nil, "deserialize rejects an unknown version")
    bad_v.v = 2

    local bad_layout = p_serialized
    bad_layout.layout = "nope"
    check(MahjongLogic.deserializeGameState(bad_layout) == nil,
        "deserialize rejects an unknown saved layout id (v2)")
    bad_layout.layout = "turtle"

    -- A v1 save (no layout field) still restores as Turtle. Build one from
    -- the real mid-game state: same board/history, just v=1 and no `layout`.
    local v1_save = {
        v = 1,
        board = p_serialized.board,
        history = p_serialized.history,
        score = p_serialized.score,
        last = p_serialized.last,
        elapsed = p_serialized.elapsed,
        hints = p_serialized.hints,
        shuffles = p_serialized.shuffles,
    }
    local v1_restored = MahjongLogic.deserializeGameState(v1_save)
    check(v1_restored ~= nil and v1_restored.layout == "turtle",
        "a v1 save (no layout field) restores as Turtle")

    local bad_key = p_serialized
    bad_key.board = { ["999,999,0"] = "b1" }
    check(MahjongLogic.deserializeGameState(bad_key) == nil, "deserialize rejects a non-layout position")
    bad_key.board = p_serialized.board

    local bad_kind = p_serialized
    bad_kind.board = { [MahjongLogic.posKey(2, 2, 0)] = "nope" }
    check(MahjongLogic.deserializeGameState(bad_kind) == nil, "deserialize rejects an invalid kind")
    bad_kind.board = p_serialized.board

    local bad_key_fmt = p_serialized
    bad_key_fmt.board = { ["a,b,c"] = "b1" }
    check(MahjongLogic.deserializeGameState(bad_key_fmt) == nil, "deserialize rejects a malformed key")
    bad_key_fmt.board = p_serialized.board

    local bad_odd = p_serialized
    bad_odd.board = {}
    check(MahjongLogic.deserializeGameState(bad_odd) == nil, "deserialize rejects an odd/empty-with-history count")
    bad_odd.board = p_serialized.board

    local bad_hist = p_serialized
    local h0 = p_serialized.history[1]
    bad_hist.history = { { h0[1], h0[2], h0[3], h0[1], h0[2], h0[3], h0[7], h0[8], 10, nil } }
    check(MahjongLogic.deserializeGameState(bad_hist) == nil,
        "deserialize rejects a history pair with the same tile twice")
    bad_hist.history = { { 1, 1, 0, 2, 2, 0, "b1", "b2", 10, nil } }
    check(MahjongLogic.deserializeGameState(bad_hist) == nil,
        "deserialize rejects history positions outside the layout")
    bad_hist.history = { { h0[1], h0[2], h0[3], h0[4], h0[5], h0[6], "b1", "c1", 10, nil } }
    check(MahjongLogic.deserializeGameState(bad_hist) == nil,
        "deserialize rejects a history pair whose kinds never matched")
    bad_hist.history = p_serialized.history

    local bad_overlap = p_serialized
    -- Take two positions that are actually on the saved board and mark them as
    -- a "removed" pair in history: a removed tile can never also be on the board.
    local in_board_key = next(p_board)
    local other_key = next(p_board, in_board_key)
    local ox, oy, ol = in_board_key:match("^([%d%.]+),([%d%.]+),(%d+)$")
    local bx2, by2, bl2 = other_key:match("^([%d%.]+),([%d%.]+),(%d+)$")
    bad_overlap.history = {
        { tonumber(ox), tonumber(oy), tonumber(ol),
          tonumber(bx2), tonumber(by2), tonumber(bl2), "b1", "b1", 10, nil },
    }
    check(MahjongLogic.deserializeGameState(bad_overlap) == nil,
        "deserialize rejects history overlapping the board")
    bad_overlap.history = p_serialized.history

    local bad_count = p_serialized
    bad_count.history = {}
    check(MahjongLogic.deserializeGameState(bad_count) == nil, "deserialize rejects count + 2*history != 144")
    bad_count.history = p_serialized.history

    local bad_score = p_serialized
    bad_score.score = -1
    check(MahjongLogic.deserializeGameState(bad_score) == nil, "deserialize rejects a negative score")
    bad_score.score = p_serialized.score

    local bad_last = p_serialized
    bad_last.last = "not-a-kind"
    check(MahjongLogic.deserializeGameState(bad_last) == nil, "deserialize rejects an invalid chain kind")
    bad_last.last = p_serialized.last

    local bad_elapsed = p_serialized
    bad_elapsed.elapsed = -5
    check(MahjongLogic.deserializeGameState(bad_elapsed) == nil, "deserialize rejects negative elapsed")
    bad_elapsed.elapsed = p_serialized.elapsed

    local bad_hints = p_serialized
    bad_hints.hints = -1
    check(MahjongLogic.deserializeGameState(bad_hints) == nil,
        "deserialize rejects a negative hint count")
    bad_hints.hints = p_serialized.hints
    local bad_hints_fmt = p_serialized
    bad_hints_fmt.hints = 1.5
    check(MahjongLogic.deserializeGameState(bad_hints_fmt) == nil,
        "deserialize rejects a fractional hint count")
    bad_hints_fmt.hints = p_serialized.hints
    local bad_shuffles = p_serialized
    bad_shuffles.shuffles = "x"
    check(MahjongLogic.deserializeGameState(bad_shuffles) == nil,
        "deserialize rejects a non-numeric shuffle count")
    bad_shuffles.shuffles = p_serialized.shuffles

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
