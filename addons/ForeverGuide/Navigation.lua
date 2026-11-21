-- Navigation.lua: which point of the current step to head for, the map
-- pin on it, and noticing that the player has arrived somewhere.
local _, ns = ...

local Engine = ns.Engine
local Maps = ns.Maps

local Nav = {}
ns.Nav = Nav

local points, loop
local reached = {}

---------------------------------------------------------------------------
-- Map pin: the game's own user waypoint, super tracked so the world map,
-- the minimap and the in-world marker all show it.
---------------------------------------------------------------------------
local pinned

local function samePin(p)
    local current = C_Map.GetUserWaypoint()
    if not (current and p and current.uiMapID == p.map and current.position) then
        return false
    end
    return math.abs(current.position.x * 100 - p.x) < 0.05 and math.abs(current.position.y * 100 - p.y) < 0.05
end

-- The pin is only touched when it is quiet (see the gate in Core.lua).
-- So what the pin should be on is kept apart from what it is on: setPin
-- only notes the wish, and syncPin, which Nav:Update runs a few times a
-- second, carries it out once it is quiet. A step that changes during a
-- fight or right after it (the kill that finishes a quest) gets its pin
-- then, not never.
local wanted        -- the point the pin should be on, or nil for none
local handled = true -- whether `wanted` has been carried out

local function clearPin()
    if pinned then
        -- Leave a pin alone that the player has since placed elsewhere.
        if samePin(pinned) then
            C_Map.ClearUserWaypoint()
        end
        pinned = nil
    end
end

-- Forever's engine reports every navigation target as Invalid (state 0),
-- which Blizzard's SuperTrackedFrame draws at alpha 0, so the in-world
-- marker never shows. Its own hook SetTargetAlphaForState makes Invalid
-- fully visible; the frame still hides itself when the point has no
-- screen position. Called once, from syncPin, so only when it is quiet.
local markerShown

local function showMarker()
    if markerShown then
        return
    end
    markerShown = true
    if SuperTrackedFrame and SuperTrackedFrame.SetTargetAlphaForState and Enum.NavigationState then
        SuperTrackedFrame:SetTargetAlphaForState(Enum.NavigationState.Invalid, 1)
    end
end

local function syncPin()
    if handled or not ns.Quiet() then
        return
    end
    handled = true
    local p = ns.db.pin and wanted or nil
    if not p then
        return clearPin()
    end
    if p == pinned then
        return
    end
    if not (Maps.Resolve(p) and p.x and p.x >= 0 and p.x <= 100 and p.y >= 0 and p.y <= 100) then
        return clearPin()
    end
    if not C_Map.CanSetUserWaypointOnMap(p.map) then
        return clearPin()
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.map, p.x / 100, p.y / 100))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    showMarker()
    pinned = p
end

local function setPin(p)
    wanted = p
    handled = false
    syncPin()
end

---------------------------------------------------------------------------
-- Target choice
---------------------------------------------------------------------------
local function choose(inst, px, py)
    if not points then
        return nil
    end
    -- Route points are walked in order.
    local hasRoute, lastRoute = false, nil
    for _, p in ipairs(points) do
        if p.route then
            hasRoute, lastRoute = true, p
            if not reached[p] then
                local distance = Maps.Distance(p, inst, px, py)
                if distance and distance <= p.radius then
                    reached[p] = true
                else
                    return p
                end
            end
        end
    end
    if hasRoute and loop then
        for _, p in ipairs(points) do
            reached[p] = nil
        end
        return choose(inst, px, py)
    end
    -- Otherwise the nearest of the places the step names.
    local best, bestDistance, low
    for _, p in ipairs(points) do
        if not p.route and not p.noArrow then
            if p.low then
                low = low or p
            else
                local distance = Maps.Distance(p, inst, px, py)
                if not best or (distance and (not bestDistance or distance < bestDistance)) then
                    if not best or distance then
                        best, bestDistance = p, distance or bestDistance
                    end
                end
            end
        end
    end
    return best or low or lastRoute
end

---------------------------------------------------------------------------
-- The player's own waypoints (/way, and other addons through the TomTom
-- stand-in in TomTom.lua): while any is set the arrow and the pin go to
-- the nearest of them instead of to the guide's goal. Each is dropped on
-- arrival. Nav.waypoint is the one currently chosen.
---------------------------------------------------------------------------
local ARRIVED = 10 -- yards

local waypoints = {}

local function clearWaypoints()
    for i = #waypoints, 1, -1 do
        waypoints[i] = nil
    end
end

-- x, y are zone coordinates (0..100) on `map` (a uiMapID), or on the map
-- the player is on when none is given. Returns the point, or nil when the
-- map is unknown or the place cannot be resolved.
local function newWaypoint(x, y, map, title)
    map = map or C_Map.GetBestMapForUnit("player")
    if not map then
        return nil
    end
    local p = { map = map, x = x, y = y, radius = ARRIVED, title = title }
    if not Maps.Resolve(p) then
        return nil
    end
    return p
end

-- Nearest of the waypoints; one on another continent only when none is
-- on this one.
local function nearestWaypoint(inst, px, py)
    local best, bestDistance
    for _, p in ipairs(waypoints) do
        local distance = Maps.Distance(p, inst, px, py)
        if distance and (not bestDistance or distance < bestDistance) then
            best, bestDistance = p, distance
        end
    end
    return best or waypoints[1]
end

-- Replaces every waypoint with this one.
function Nav:SetWaypoint(x, y, map, title)
    local p = newWaypoint(x, y, map, title)
    if not p then
        return nil
    end
    clearWaypoints()
    waypoints[1] = p
    Nav:Update()
    return p
end

-- Adds one to those already set.
function Nav:AddWaypoint(x, y, map, title)
    local p = newWaypoint(x, y, map, title)
    if not p then
        return nil
    end
    waypoints[#waypoints + 1] = p
    Nav:Update()
    return p
end

function Nav:RemoveWaypoint(p)
    for i, q in ipairs(waypoints) do
        if q == p then
            table.remove(waypoints, i)
            Nav:Update()
            return true
        end
    end
    return false
end

function Nav:ClearWaypoint()
    if #waypoints == 0 then
        return false
    end
    clearWaypoints()
    Nav:Update()
    return true
end

function Nav:WaypointCount()
    return #waypoints
end

---------------------------------------------------------------------------
-- The corpse: while the player is a ghost the arrow goes there, before the
-- waypoint and the guide. The map pin stays where it was.
---------------------------------------------------------------------------
local corpse

local function corpsePoint()
    if not UnitIsGhost("player") then
        corpse = nil
        return nil
    end
    if corpse then
        return corpse
    end
    -- The corpse may lie in another zone than the graveyard: ask for it on
    -- the player's map, then on the maps above it.
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if not map or map == 0 then
            break
        end
        local pos = C_DeathInfo.GetCorpseMapPosition(map)
        if pos then
            local x, y = pos:GetXY()
            local p = { map = map, x = x * 100, y = y * 100, radius = 8, corpse = true }
            if Maps.Resolve(p) then
                corpse = p
                return p
            end
        end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    return nil
end

---------------------------------------------------------------------------
-- The focused quest (Focus in the quest log, the game's super tracking):
-- the arrow goes there when neither the waypoint nor the guide has a goal.
-- The place is where the game itself marks the quest: its icon on the
-- player's map, else its next waypoint, else its icon on the quest's own
-- map. The map pin is not involved; the game shows its own marker.
--
-- For some finished quests the game marks no place at all (one handed in
-- at an object on another continent). Then the place is the nearest spot
-- QuestieDB, when installed, knows for whoever takes the quest.
---------------------------------------------------------------------------
local focus

-- QuestieDB keys spawns by AreaTable ID with 0-100 coordinates on that
-- zone's map; the table from area to uiMapID is a Lua source string.
local areaMaps

local function areaMap(area)
    if not areaMaps then
        areaMaps = {}
        local ok, zones = pcall(LibQuestieDB.Support.Get, "ZoneDB")
        local private = ok and zones and zones.private or {}
        -- The override is Questie's own choice and wins; 0 means "no map".
        for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
            local source = private[key]
            if type(source) == "string" then
                local chunk = loadstring(source)
                local good, result = pcall(chunk or error)
                source = good and result
            end
            for id, map in pairs(type(source) == "table" and source or {}) do
                areaMaps[id] = map
            end
        end
    end
    local map = areaMaps[area]
    return map and map ~= 0 and map or nil
end

local handIns = {} -- quest -> the points where it can be handed in

local function addSpawns(list, quest, spawns)
    for area, spots in pairs(type(spawns) == "table" and spawns or {}) do
        local map = areaMap(area)
        for _, spot in ipairs(map and type(spots) == "table" and spots or {}) do
            local x, y = spot[1], spot[2]
            -- -1, -1 marks "somewhere inside an instance".
            if x and y and x >= 0 and y >= 0 then
                local p = { map = map, x = x, y = y, radius = 8, quest = quest }
                if Maps.Resolve(p) then
                    list[#list + 1] = p
                end
            end
        end
    end
end

local function readHandIns(quest)
    local list = {}
    local finishers = QuestDB.finishedBy(quest) or {}
    for _, npc in ipairs(finishers[1] or {}) do
        addSpawns(list, quest, NpcDB.spawns(npc))
    end
    for _, object in ipairs(finishers[2] or {}) do
        addSpawns(list, quest, ObjectDB.spawns(object))
    end
    return list
end

-- The nearest hand-in spot; one on another continent when none is on this.
local function handIn(quest, inst, px, py)
    if not (LibQuestieDB and QuestDB and NpcDB and ObjectDB) then
        return nil
    end
    local list = handIns[quest]
    if not list then
        local ok, result = pcall(readHandIns, quest)
        list = ok and result or {}
        handIns[quest] = list
    end
    local best, bestDistance
    for _, p in ipairs(list) do
        local distance = Maps.Distance(p, inst, px, py)
        if not best or (distance and (not bestDistance or distance < bestDistance)) then
            best, bestDistance = p, distance
        end
    end
    return best
end

local function questOnMap(quest, map)
    if not (map and map ~= 0 and C_QuestLog.GetQuestsOnMap) then
        return nil
    end
    local ok, onMap = pcall(C_QuestLog.GetQuestsOnMap, map)
    for _, info in ipairs(ok and type(onMap) == "table" and onMap or {}) do
        if info.questID == quest and info.x and info.y then
            return map, info.x, info.y
        end
    end
    return nil
end

local function questPlace(quest, playerMap)
    local map, x, y = questOnMap(quest, playerMap)
    if map then
        return map, x, y
    end
    if C_QuestLog.GetNextWaypoint then
        local ok
        ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, quest)
        if ok and map and x and y then
            return map, x, y
        end
    end
    return questOnMap(quest, GetQuestUiMapID and GetQuestUiMapID(quest))
end

local function focusPoint(playerMap, inst, px, py)
    local quest = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if not quest or quest == 0 then
        focus = nil
        return nil
    end
    local map, x, y = questPlace(quest, playerMap)
    if not map then
        focus = C_QuestLog.IsComplete(quest) and handIn(quest, inst, px, py) or nil
        return focus
    end
    x, y = x * 100, y * 100
    -- The same table as long as the place is the same, so the arrow's
    -- target only changes when the place does.
    if focus and focus.quest == quest and focus.map == map
        and math.abs(focus.x - x) < 0.01 and math.abs(focus.y - y) < 0.01 then
        return focus
    end
    local p = { map = map, x = x, y = y, radius = 8, quest = quest }
    focus = Maps.Resolve(p) and p or nil
    return focus
end

-- The point the map pin is on, or nil (Route.lua leaves a gap there).
function Nav:Pinned()
    return pinned
end

-- Whether the player has passed this route point (Route.lua dims it).
function Nav:IsReached(p)
    return reached[p] == true
end

local goal -- what the pin follows: the waypoint or the guide's point

function Nav:Update()
    if not ns.db then
        return
    end
    local inst, px, py, playerMap = Maps.Player()

    for i = #waypoints, 1, -1 do
        local p = waypoints[i]
        local distance = Maps.Distance(p, inst, px, py)
        if distance and distance <= ARRIVED then
            table.remove(waypoints, i)
            ns.Print((p.title or "waypoint") .. " reached.")
        end
    end
    Nav.waypoint = nearestWaypoint(inst, px, py)

    for _, arrival in ipairs(Engine.arrivals) do
        local distance = Maps.Distance(arrival.point, inst, px, py)
        if distance and distance <= (arrival.point.radius or 15) then
            Engine:LatchKey(arrival.key)
        end
    end

    local now = Nav.waypoint or choose(inst, px, py)
    local target = corpsePoint() or now or focusPoint(playerMap, inst, px, py)
    if target ~= Nav.target then
        Nav.target = target
        ns.Fire("Target", target)
    end

    -- The pin, and with it the in-world marker, goes where the arrow
    -- points, route points included, so the two do not disagree. Not on
    -- the super-tracked quest: the game marks that itself, and a pin of
    -- ours would take its super-tracking away. Not on the corpse either:
    -- as a ghost the pin keeps the guide's goal (corpse.lua).
    local pin = now
    if pin ~= goal then
        goal = pin
        setPin(pin)
    end
    syncPin()
    return inst, px, py
end

ns.Listen("Updated", function()
    local nav = Engine.nav
    local list = nav and nav.points or nil
    if list ~= points then
        points = list
        for p in pairs(reached) do
            reached[p] = nil
        end
    end
    loop = nav and nav.loop
    Nav.title = nav and nav.title
    Nav:Update()
end)

ns.Listen("Setting", function(key)
    if key == "pin" then
        if ns.db.pin then
            pinned = nil
            goal = nil
            Nav:Update()
        else
            setPin(nil)
        end
    end
end)
