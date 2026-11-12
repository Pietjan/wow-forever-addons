-- Maps.lua: zone names to map ids, and map positions to world positions.
--
-- A point is a table. Guides give it in one of two forms:
--   { map = uiMapID, x = 0..100, y = 0..100 }             zone coordinates
--   { map = uiMapID, inst = continent, wx = X, wy = Y }   world coordinates
-- Resolve() fills in the other form, so every resolved point has
-- inst/wx/wy (yards, the game's own axes: X north, Y west) for the arrow
-- and map/x/y for the pin.
local _, ns = ...

local Maps = {}
ns.Maps = Maps

local byName

local function buildNames()
    byName = {}
    local rank = {}
    -- Lower is better when two maps share a name.
    local order = { [3] = 1, [6] = 2, [4] = 3, [5] = 4, [2] = 5, [1] = 6, [0] = 7 }
    for id = 1, 3000 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            local key = info.name:lower()
            local r = order[info.mapType] or 9
            if not rank[key] or r < rank[key] then
                rank[key] = r
                byName[key] = id
            end
        end
    end
end

-- "Mulgore", "1412", "1412; Mulgore" or a number -> uiMapID
function Maps.Find(zone)
    if type(zone) == "number" then
        return zone
    end
    if not zone then
        return nil
    end
    local id = tonumber(zone) or tonumber(zone:match("^%s*(%d+)%s*;"))
    if id then
        return id
    end
    if not byName then
        buildNames()
    end
    local name = zone:match(";%s*(.-)%s*$") or zone
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    return byName[name]
end

function Maps.Name(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name
end

local scratch = CreateVector2D(0, 0)

function Maps.Resolve(p)
    if p.resolved ~= nil then
        return p.resolved
    end
    p.resolved = false
    if not p.map then
        return false
    end
    if p.wx then
        scratch:SetXY(p.wx, p.wy)
        local _, pos = C_Map.GetMapPosFromWorldPos(p.inst, scratch, p.map)
        if pos then
            p.x, p.y = pos.x * 100, pos.y * 100
        end
        p.resolved = true
    elseif p.x then
        scratch:SetXY(p.x / 100, p.y / 100)
        local inst, pos = C_Map.GetWorldPosFromMapPos(p.map, scratch)
        if inst and pos then
            p.inst, p.wx, p.wy = inst, pos.x, pos.y
            p.resolved = true
        end
    end
    return p.resolved
end

-- The player's world position: continent, X, Y. Nil inside instances.
function Maps.Player()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then
        return nil
    end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then
        return nil
    end
    local inst, world = C_Map.GetWorldPosFromMapPos(map, pos)
    if not (inst and world) then
        return nil
    end
    return inst, world.x, world.y, map
end

-- Distance in yards from the player to a point, and the bearing in radians
-- counter-clockwise from north. Nil when they are on different continents
-- or the player's position is unknown.
function Maps.Distance(p, inst, px, py)
    if not Maps.Resolve(p) then
        return nil
    end
    if not inst then
        inst, px, py = Maps.Player()
    end
    if not inst or inst ~= p.inst then
        return nil
    end
    local dx, dy = p.wx - px, p.wy - py
    return math.sqrt(dx * dx + dy * dy), math.atan2(dy, dx)
end
