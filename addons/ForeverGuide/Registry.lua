-- Registry.lua: collects the guides while the guide files load.
--
-- The guide files are the unmodified files of RestedXP Guides and WoW-Pro
-- Leveling. They register themselves through the globals of those addons
-- (RXPGuides.RegisterGuide, WoWPro:RegisterGuide ...). For the time our
-- copies load, those globals are ours; RegistryEnd.lua puts back whatever
-- was there, so the real addons keep working when they are installed too.
local _, ns = ...

local Text = ns.Text

local Registry = { list = {}, byKey = {}, byGID = {} }
ns.Registry = Registry

local saved = { RXPGuides = _G.RXPGuides, RXP = _G.RXP, WoWPro = _G.WoWPro }

local function insert(guide)
    local old = Registry.byKey[guide.key]
    if old then
        if (guide.version or 0) <= (old.version or 0) then
            return
        end
        for i, g in ipairs(Registry.list) do
            if g == old then
                table.remove(Registry.list, i)
                break
            end
        end
    end
    Registry.byKey[guide.key] = guide
    Registry.list[#Registry.list + 1] = guide
end

---------------------------------------------------------------------------
-- RestedXP
---------------------------------------------------------------------------
local function registerRXP(a, b)
    local text = type(b) == "string" and b or a
    if type(text) ~= "string" then
        return
    end
    local h = ns.ParserRXP.Header(text)
    if h.disabled then
        return
    end
    -- Leveling only: no dungeon runs, no profession or gold farming.
    if h.group:find("Dungeon") or h.group:sub(1, 1) == "+" then
        return
    end
    local low, high = h.name:match("^(%d+)%-(%d+)")
    insert({
        format = "rxp",
        key = "rxp:" .. h.group .. "/" .. h.name,
        id = h.name,
        name = Text.Plain(Text.RXP(h.displayname or h.name)),
        group = h.group,
        subgroup = h.subgroup,
        min = tonumber(low),
        max = tonumber(high),
        next = h.next,
        defaultFor = h.defaultfor,
        version = tonumber(h.version) or 0,
        text = text,
        signature = #text,
    })
end

RXPGuides = { RegisterGuide = registerRXP }
RXP = { RegisterGuide = registerRXP, enabledLocale = {} }

---------------------------------------------------------------------------
-- WoW-Pro
---------------------------------------------------------------------------
local pending = {}
local shim = {}
local function ignore() end

function shim:RegisterGuide(gid, kind, zone, author, faction)
    local guide = { format = "wowpro", gid = gid, kind = kind, zone = zone, author = author, faction = faction }
    pending[#pending + 1] = guide
    return guide
end

function shim:GuideName(guide, name)
    guide.name = name
end

function shim:GuideLevels(guide, low, high)
    guide.min, guide.max = tonumber(low), tonumber(high)
end

function shim:GuideNextGuide(guide, gid)
    guide.nextGID = gid
end

function shim:GuideSteps(guide, source)
    guide.source = source
end

-- Everything else a guide file may call (icons, sort order, ...) is of no
-- use to us.
setmetatable(shim, { __index = function() return ignore end })
WoWPro = shim

function Registry.Finish()
    local faction = ns.player.faction
    for _, guide in ipairs(pending) do
        if guide.kind == "Leveling" and type(guide.source) == "function"
            and (guide.faction == faction or guide.faction == "Neutral" or not guide.faction) then
            guide.key = "wowpro:" .. tostring(guide.gid)
            guide.group = "WoW-Pro Leveling"
            local zone = guide.name or guide.zone or tostring(guide.gid)
            zone = zone:gsub("%s*%(%d+%-%d+%)%s*$", "")
            if guide.min and guide.max then
                guide.name = ("%d-%d %s"):format(guide.min, guide.max, zone)
            else
                guide.name = zone
            end
            Registry.byGID[guide.gid] = guide
            insert(guide)
        end
    end
    pending = nil

    table.sort(Registry.list, function(x, y)
        if x.group ~= y.group then
            return x.group < y.group
        end
        if (x.subgroup or "") ~= (y.subgroup or "") then
            local a = tonumber((x.subgroup or ""):match("(%d+)%-")) or 0
            local b = tonumber((y.subgroup or ""):match("(%d+)%-")) or 0
            if a ~= b then
                return a < b
            end
            return (x.subgroup or "") < (y.subgroup or "")
        end
        if (x.min or 0) ~= (y.min or 0) then
            return (x.min or 0) < (y.min or 0)
        end
        if (x.max or 0) ~= (y.max or 0) then
            return (x.max or 0) < (y.max or 0)
        end
        return x.name < y.name
    end)

    RXPGuides, RXP, WoWPro = saved.RXPGuides, saved.RXP, saved.WoWPro
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
function Registry.Get(key)
    return key and Registry.byKey[key]
end

-- The guide that follows this one, if its author named one.
function Registry.Next(guide)
    if guide.format == "wowpro" then
        return guide.nextGID and Registry.byGID[guide.nextGID]
    end
    if not guide.next then
        return nil
    end
    for name in guide.next:gmatch("[^;]+") do
        name = Text.trim(name:gsub("^.-\\", ""))
        local found = Registry.byKey["rxp:" .. guide.group .. "/" .. name]
        if found then
            return found
        end
    end
    return nil
end

-- Guides that fit the character's level, the ones written for its race
-- first.
function Registry.Suggest()
    local level = UnitLevel("player") or 1
    local fits = {}
    for _, guide in ipairs(Registry.list) do
        if guide.min and guide.max and level >= guide.min and level <= guide.max then
            local own = guide.defaultFor ~= nil and ns.ParserRXP.Applies(guide.defaultFor)
            local foreign = guide.defaultFor ~= nil and not own
            if guide.format == "wowpro" then
                -- WoW-Pro does not say whose start zone a guide is; go by
                -- where the character stands.
                local zone = (guide.zone or ""):match("([^;]+)$") or ""
                own = Text.trim(zone):lower() == (GetZoneText() or ""):lower()
                foreign = not own
            end
            -- A starting-zone guide for another race is a poor suggestion.
            if not (foreign and guide.min <= 1) then
                fits[#fits + 1] = { guide = guide, rank = own and 0 or 1 }
            end
        end
    end
    table.sort(fits, function(x, y)
        if x.rank ~= y.rank then
            return x.rank < y.rank
        end
        return x.guide.max - x.guide.min < y.guide.max - y.guide.min
    end)
    local out = {}
    for i = 1, math.min(#fits, 5) do
        out[i] = fits[i].guide
    end
    return out
end
