-- TomTom.lua: a stand-in for TomTom's waypoint call, so addons that set
-- their waypoints through TomTom (Books Forever, Leatrix Plus) point the
-- guide's arrow instead. Only made when the real TomTom is not loaded; it
-- is an optional dependency, so it loads first when installed.
--
-- Only AddWaypoint and RemoveWaypoint exist. An addon that calls more of
-- TomTom gets an error of its own, as it would with an older TomTom.
local _, ns = ...

if TomTom ~= nil then
    return
end

local ErrNoWaypoint = "ForeverGuide: cannot set a waypoint there"

TomTom = { ForeverGuide = true }

-- TomTom:AddWaypoint(uiMapID, x, y, opts): x, y from 0 to 1, opts.title
-- names it. Returns a handle for RemoveWaypoint. Raises an error when the
-- place cannot be used, so a caller that tries TomTom under pcall falls
-- back to its own way.
function TomTom:AddWaypoint(map, x, y, opts)
    if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number"
        or x < 0 or x > 1 or y < 0 or y > 1 then
        error(ErrNoWaypoint, 2)
    end
    local title = type(opts) == "table" and type(opts.title) == "string" and opts.title or nil
    local p = ns.Nav:AddWaypoint(x * 100, y * 100, map, title)
    if not p then
        error(ErrNoWaypoint, 2)
    end
    return p
end

function TomTom:RemoveWaypoint(handle)
    return ns.Nav:RemoveWaypoint(handle)
end
