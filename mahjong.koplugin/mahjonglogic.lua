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
-- The classic 144-tile Turtle (the canonical GNOME Mahjongg map), with the
-- stepped pyramid and the head/tail protrusions. Coordinates are tile
-- top-left corners; `y` may be fractional (x=0/y=3.5 head, x=13..14/y=3.5
-- tail, x=6.5/y=3.5 cap) so the silhouette's half-tile overhang is kept:
--   L0: body rows (12+8+10+12+12+10+8+12 = 84) + head (x=0, y=3.5) + tail
--       (x=13..14, y=3.5) = 87
--   L1: block x=4..9,  y=1..6   (6x6  = 36)
--   L2: block x=5..8,  y=2..5   (4x4  = 16)
--   L3: block x=6..7,  y=3..4   (2x2  =  4)
--   L4: single tile x=6.5, y=3.5 (       1)
-- 87 + 36 + 16 + 4 + 1 = 144. Grid extents: x=0..14, y=0..7.
local LAYOUT_SPEC = {
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

-- Returns the 144 tile positions of the Turtle layout as an array of
-- { x = .., y = .., layer = .. } tables, bottom layer first (so the UI can
-- paint lower layers first).
-- The layout is static, so it is built once and cached: rebuilds (new game,
-- board repaints) iterate the same table instead of allocating 144 fresh
-- position tables every call. Callers must NOT mutate the returned array.
local _layout_cache = nil
function MahjongLogic.buildLayout()
    if not _layout_cache then
        local layout = {}
        local function add(x, y, layer)
            layout[#layout + 1] = { x = x, y = y, layer = layer }
        end
        for _, spec in ipairs(LAYOUT_SPEC) do
            if spec.kind == "row" then
                for x = spec.x_min, spec.x_max do
                    add(x, spec.y, spec.layer)
                end
            elseif spec.kind == "block" then
                for y = spec.y_min, spec.y_max do
                    for x = spec.x_min, spec.x_max do
                        add(x, y, spec.layer)
                    end
                end
            else -- single tile
                add(spec.x, spec.y, spec.layer)
            end
        end
        _layout_cache = layout
    end
    return _layout_cache
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
function MahjongLogic.freeTiles(board)
    local free = {}
    for key, kind in pairs(board) do
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
    return free
end

-- True if at least one pair of matching free tiles can be removed.
-- The free-tile count is bounded by the tile count (<= 144), so an O(n^2)
-- scan of the free tiles is fine for a board game.
function MahjongLogic.hasMoves(board)
    local free = MahjongLogic.freeTiles(board)
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

-- A matching free pair on the board, as { a = { x, y, layer, kind },
-- b = { x, y, layer, kind } }, or nil if no move exists. Used for the no-moves
-- check and the US-08 hint.
function MahjongLogic.matchingFreePair(board)
    local free = MahjongLogic.freeTiles(board)
    for i = 1, #free - 1 do
        for j = i + 1, #free do
            if MahjongLogic.matches(free[i].kind, free[j].kind) then
                return { a = free[i], b = free[j] }
            end
        end
    end
    return nil
end

-- The number of distinct matching free pairs currently available — i.e. how
-- many legal moves could be made right now. Each unordered pair of free tiles
-- that matches counts once (so three free flowers = 3 available pairs).
function MahjongLogic.countFreePairs(board)
    local free = MahjongLogic.freeTiles(board)
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

-- Flat projection grid -----------------------------------------------------
--
-- The UI renders the 3D board as a flat grid: each (x, y) cell shows the
-- topmost tile at that position. These helpers give the grid extents and the
-- topmost tile lookup the renderer needs.

-- Highest layer used by the Turtle layout.
MahjongLogic.MAX_LAYER = 4

-- Bounds of the projection grid as { x_min, x_max, y_min, y_max }.
-- Static, so cached like buildLayout() (callers must not mutate).
local _bounds_cache = nil
function MahjongLogic.gridBounds()
    if not _bounds_cache then
        local bounds = {
            x_min = math.huge,
            x_max = -math.huge,
            y_min = math.huge,
            y_max = -math.huge,
        }
        for _, p in ipairs(MahjongLogic.buildLayout()) do
            bounds.x_min = math.min(bounds.x_min, p.x)
            bounds.x_max = math.max(bounds.x_max, p.x)
            bounds.y_min = math.min(bounds.y_min, p.y)
            bounds.y_max = math.max(bounds.y_max, p.y)
        end
        _bounds_cache = bounds
    end
    return _bounds_cache
end

-- Kind of the topmost tile at projection cell (x, y), or nil if the cell is
-- empty. Topmost means the highest layer; lower tiles are fully covered.
function MahjongLogic.topTileAt(board, x, y)
    for layer = MahjongLogic.MAX_LAYER, 0, -1 do
        local kind = MahjongLogic.tileAt(board, x, y, layer)
        if kind then return kind end
    end
    return nil
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
    for _, s in ipairs(LAYOUT_SPEC) do
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

    local proj = boardWith{ {2,2,0,"b1"}, {2,2,1,"c2"}, {2,2,2,"d3"}, {3,2,0,"east"} }
    check(MahjongLogic.topTileAt(proj, 2, 2) == "d3", "topTileAt returns the highest layer's kind")
    check(MahjongLogic.topTileAt(proj, 3, 2) == "east", "topTileAt returns a lone tile's kind")
    check(MahjongLogic.topTileAt(proj, 9, 9) == nil, "topTileAt returns nil for an empty cell")
    check(MahjongLogic.topTileAt({}, 4, 4) == nil, "topTileAt on an empty board returns nil")

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
