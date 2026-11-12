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

-- The pin is only touched out of combat; Nav:Update comes by again a few
-- times a second, so a change that was held back is made right after.
local function clearPin()
    if pinned and not InCombatLockdown() then
        -- Leave a pin alone that the player has since placed elsewhere.
        if samePin(pinned) then
            C_Map.ClearUserWaypoint()
        end
        pinned = nil
    end
end

local function setPin(p)
    if not (ns.db.pin and p) then
        return clearPin()
    end
    if p == pinned or InCombatLockdown() then
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
    pinned = p
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

function Nav:Update()
    if not ns.db then
        return
    end
    local inst, px, py = Maps.Player()

    for _, arrival in ipairs(Engine.arrivals) do
        local distance = Maps.Distance(arrival.point, inst, px, py)
        if distance and distance <= (arrival.point.radius or 15) then
            Engine:LatchKey(arrival.key)
        end
    end

    local target = choose(inst, px, py)
    if target ~= Nav.target then
        Nav.target = target
        -- The pin goes on a real destination, not on a point along a route.
        local pin = target
        if pin and pin.noPin then
            pin = nil
            for _, p in ipairs(points) do
                if not p.noPin and not p.noArrow then
                    pin = p
                    break
                end
            end
        end
        setPin(pin)
        ns.Fire("Target", target)
    end
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
            Nav.target = nil
            Nav:Update()
        else
            clearPin()
        end
    end
end)
