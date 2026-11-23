-- Route.lua: the current step's route drawn as a marching ant trail on the
-- world map and the minimap, and the shown steps' marked places.
--
-- A route is the step's route points (RXP .waypoint and optional .goto
-- with a radius, WoW-Pro path points) in the order the arrow walks them,
-- closed into a loop for patrol steps. It is drawn as small gold dots
-- that move along it in the walking direction; dots on segments already
-- walked are muted.
--
-- Marked places are RXP ".goto ...,0" points ("He has 4 spawnpoints
-- (marked on the map)"): places to look out for that the arrow never
-- points at. Each is a larger gold disc with a dark rim.
--
-- Everything drawn is our own frames and textures. Blizzard's map is only
-- read (canvas size and scale, map id) and its methods are followed with
-- hooksecurefunc, the way ForeverQuests draws its dots.
local _, ns = ...

local Engine = ns.Engine
local Maps = ns.Maps
local Nav = ns.Nav

local AHEAD = { 1, 0.82, 0, 1 }         -- dots still to walk
local WALKED = { 0.55, 0.47, 0.25, 1 }  -- dots already walked
local UNDER = { 0.08, 0.06, 0.02, 0.7 } -- thin dark edge under each dot
local MARK = { 1, 0.62, 0.1, 1 }        -- a marked place
local MARK_RIM = { 0.08, 0.06, 0.02, 0.85 }
-- Sizes in screen pixels; the dot texture fades over its outer fifth.
local CORE, EDGE_SIZE = 2.5, 4.5 -- dot size, and of its dark edge
local MARK_SIZE, MARK_RIM_SIZE = 9, 13 -- marked place, and its dark rim
local SPACING = 6                -- from dot to dot along the route
local SPEED = 8                  -- pixels per second along the route
local DOT = "Interface\\AddOns\\ForeverGuide\\Textures\\RouteDot"
local RIM = 0.92        -- keep minimap dots off the round frame's rim
local PIN_GAP = 9       -- no minimap dots this close to the pin (pixels)
local INTERVAL = 0.03   -- seconds between redraws

---------------------------------------------------------------------------
-- The route
---------------------------------------------------------------------------
-- route[i] = point; segments go i -> i + 1, and last -> first on a loop.
local route = {}
local closed = false
local marks = {} -- the shown steps' marked places

local function rebuild()
    for i = #route, 1, -1 do
        route[i] = nil
    end
    local nav = Engine.nav
    for _, p in ipairs(nav and nav.points or {}) do
        if p.route and Maps.Resolve(p) then
            route[#route + 1] = p
        end
    end
    closed = nav and nav.loop and #route > 2 or false
    if #route < 2 then
        for i = #route, 1, -1 do
            route[i] = nil
        end
    end
    for i = #marks, 1, -1 do
        marks[i] = nil
    end
    for _, p in ipairs(Engine.marks or {}) do
        if Maps.Resolve(p) then
            marks[#marks + 1] = p
        end
    end
end

local function segments()
    return closed and #route or #route - 1
end

-- Segment i ends at this point; it is walked once that point is reached.
local function segmentEnd(i)
    return route[i % #route + 1]
end

---------------------------------------------------------------------------
-- Painter: pools of dot textures on one frame (dark edges below, walked
-- dots, dots ahead on top), reused on every redraw.
---------------------------------------------------------------------------
local function newPool(parent, layer, sublevel)
    return { parent = parent, layer = layer, sublevel = sublevel, items = {}, used = 0 }
end

local function acquire(pool)
    pool.used = pool.used + 1
    local dot = pool.items[pool.used]
    if not dot then
        dot = pool.parent:CreateTexture(nil, pool.layer, nil, pool.sublevel)
        -- Soft-edged disc: a flat square would look jagged when small.
        dot:SetTexture(DOT)
        pool.items[pool.used] = dot
    end
    dot:Show()
    return dot
end

local function newPainter(parent)
    return {
        under = newPool(parent, "ARTWORK", 0),
        walked = newPool(parent, "OVERLAY", 0),
        ahead = newPool(parent, "OVERLAY", 2),
        markRim = newPool(parent, "OVERLAY", 4),
        mark = newPool(parent, "OVERLAY", 6),
    }
end

local function finishPainter(painter)
    for _, pool in pairs(painter) do
        for i = pool.used + 1, #pool.items do
            pool.items[i]:Hide()
        end
        pool.used = 0
    end
end

local function dot(pool, color, size, anchor, point, x, y)
    local d = acquire(pool)
    d:SetVertexColor(color[1], color[2], color[3], color[4])
    d:SetSize(size, size)
    d:ClearAllPoints()
    d:SetPoint("CENTER", anchor, point, x, y)
end

-- Draws the trail along `path`: a list of { ax, ay, bx, by, walked } in
-- route order, offsets from `point` of `anchor`, in units where one screen
-- pixel is `unit`. Dots are spaced along the whole path so they flow
-- across bends; `keep(x, y)` says whether a dot may be drawn there.
local function trail(painter, anchor, point, path, unit, keep)
    local spacing = SPACING * unit
    local phase = (GetTime() * SPEED * unit) % spacing
    local start = 0 -- distance along the path where this segment begins
    for _, s in ipairs(path) do
        local ax, ay, bx, by = s[1], s[2], s[3], s[4]
        local dx, dy = bx - ax, by - ay
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0 then
            local ux, uy = dx / length, dy / length
            -- The first dot on this segment: phase + k * spacing >= start.
            local d = start + (phase - start) % spacing
            while d < start + length do
                local x, y = ax + ux * (d - start), ay + uy * (d - start)
                if keep(x, y) then
                    dot(painter.under, UNDER, EDGE_SIZE * unit, anchor, point, x, y)
                    dot(s[5] and painter.walked or painter.ahead, s[5] and WALKED or AHEAD,
                        CORE * unit, anchor, point, x, y)
                end
                d = d + spacing
            end
        end
        start = start + length
    end
end

-- Draws the marked places in `spots` (x, y offsets from `point` of
-- `anchor`), sized like the trail by `unit`.
local function markers(painter, anchor, point, spots, unit)
    for _, s in ipairs(spots) do
        dot(painter.markRim, MARK_RIM, MARK_RIM_SIZE * unit, anchor, point, s[1], s[2])
        dot(painter.mark, MARK, MARK_SIZE * unit, anchor, point, s[1], s[2])
    end
end

-- Repeats `draw` every INTERVAL while `frame` is shown, for the marching.
local function animate(frame, draw)
    local since = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= INTERVAL then
            since = 0
            draw()
        end
    end)
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local canvas, mapLayer, mapPainter
local scratch = CreateVector2D and CreateVector2D(0, 0)
local mapPath = {}
local mapSpots = {}

-- Where a point falls on a map, 0..1, or nil when it is not on it.
local function onMap(p, mapID)
    if p.map == mapID then
        return p.x / 100, p.y / 100
    end
    scratch:SetXY(p.wx, p.wy)
    local _, pos = C_Map.GetMapPosFromWorldPos(p.inst, scratch, mapID)
    if pos then
        return pos.x, pos.y
    end
end

local mapWidth, mapHeight = 0, 0
local function onCanvas(x, y)
    return x >= 0 and x <= mapWidth and y <= 0 and y >= -mapHeight
end

local function drawWorldMap()
    if not mapPainter then
        return
    end
    for i = #mapPath, 1, -1 do
        mapPath[i] = nil
    end
    for i = #mapSpots, 1, -1 do
        mapSpots[i] = nil
    end
    local mapID = WorldMapFrame:IsShown() and (#route > 1 or #marks > 0) and WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if info and info.mapType >= Enum.UIMapType.Continent then
        mapWidth, mapHeight = canvas:GetSize()
        for _, p in ipairs(marks) do
            local x, y = onMap(p, mapID)
            if x and onCanvas(x * mapWidth, -y * mapHeight) then
                mapSpots[#mapSpots + 1] = { x * mapWidth, -y * mapHeight }
            end
        end
        for i = 1, segments() do
            local b = segmentEnd(i)
            local ax, ay = onMap(route[i], mapID)
            local bx, by = onMap(b, mapID)
            if ax and bx then
                mapPath[#mapPath + 1] = { ax * mapWidth, -ay * mapHeight, bx * mapWidth, -by * mapHeight, Nav:IsReached(b) }
            end
        end
    end
    if #mapPath > 0 or #mapSpots > 0 then
        -- Above the explored-area art and fog, where ForeverQuests puts its
        -- dots; the game hands out pin levels as pins appear, so ask each
        -- time.
        local ok, level = pcall(function()
            return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
        end)
        mapLayer:SetFrameLevel(ok and level or canvas:GetFrameLevel() + 1)
        -- The canvas is scaled with the zoom; keep sizes on screen.
        local scale = WorldMapFrame:GetCanvasScale()
        local unit = 1 / (scale > 0 and scale or 1)
        trail(mapPainter, canvas, "TOPLEFT", mapPath, unit, onCanvas)
        markers(mapPainter, canvas, "TOPLEFT", mapSpots, unit)
    end
    finishPainter(mapPainter)
end

local function setUpWorldMap()
    if mapPainter or not WorldMapFrame or not WorldMapFrame.GetCanvas then
        return
    end
    canvas = WorldMapFrame:GetCanvas()
    mapLayer = CreateFrame("Frame", nil, canvas)
    mapLayer:SetAllPoints()
    mapLayer:SetFrameLevel(canvas:GetFrameLevel() + 1)
    mapPainter = newPainter(mapLayer)
    -- mapLayer is a child of the map, so it only updates while it shows.
    animate(mapLayer, drawWorldMap)
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local miniLayer, miniPainter
local miniPath = {}
local miniSpots = {}
local limit = 0 -- squared radius a dot must stay within
local pinX, pinY -- the pin on the minimap, or nil

-- The game draws the pin as part of the minimap itself, under every
-- frame an addon can add, so the trail leaves a gap around it instead.
local function onMinimap(x, y)
    if pinX and (x - pinX) ^ 2 + (y - pinY) ^ 2 < PIN_GAP * PIN_GAP then
        return false
    end
    return x * x + y * y <= limit
end

local function drawMinimap()
    for i = #miniPath, 1, -1 do
        miniPath[i] = nil
    end
    for i = #miniSpots, 1, -1 do
        miniSpots[i] = nil
    end
    local inst, px, py = Maps.Player()
    local radius = C_Minimap.GetViewRadius()
    local rotates = GetCVarBool("rotateMinimap") and not C_Minimap.IsRotateMinimapIgnored()
    local facing = rotates and GetPlayerFacing() or nil
    if (#route > 1 or #marks > 0) and inst and radius and radius > 0 and (facing or not rotates) then
        local half = Minimap:GetWidth() / 2
        local perYard = half / radius
        limit = (half * RIM) ^ 2
        local cos, sin = 1, 0
        if facing then
            cos, sin = math.cos(facing), math.sin(facing)
        end
        -- A point's place on the minimap in pixels from the centre, x
        -- right and y up. World X is north and world Y is west.
        local function place(p)
            local north, east = p.wx - px, py - p.wy
            local x, y = east, north
            if facing then
                -- The rotating minimap keeps the facing direction up;
                -- facing is counter-clockwise from north.
                x, y = east * cos + north * sin, north * cos - east * sin
            end
            return x * perYard, y * perYard
        end
        local pin = Nav:Pinned()
        pinX, pinY = nil, nil
        if pin and pin.inst == inst then
            pinX, pinY = place(pin)
        end
        for i = 1, segments() do
            local a, b = route[i], segmentEnd(i)
            if a.inst == inst and b.inst == inst then
                local ax, ay = place(a)
                local bx, by = place(b)
                miniPath[#miniPath + 1] = { ax, ay, bx, by, Nav:IsReached(b) }
            end
        end
        trail(miniPainter, miniLayer, "CENTER", miniPath, 1, onMinimap)
        -- Only marks inside the round frame; the arrow does the far ones.
        local inside = (half * RIM - MARK_RIM_SIZE / 2) ^ 2
        for _, p in ipairs(marks) do
            if p.inst == inst then
                local x, y = place(p)
                if x * x + y * y <= inside then
                    miniSpots[#miniSpots + 1] = { x, y }
                end
            end
        end
        markers(miniPainter, miniLayer, "CENTER", miniSpots, 1)
    end
    finishPainter(miniPainter)
end

local function setUpMinimap()
    if miniPainter or not Minimap or not C_Minimap then
        return
    end
    miniLayer = CreateFrame("Frame", nil, Minimap)
    miniLayer:SetAllPoints()
    miniLayer:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    miniPainter = newPainter(miniLayer)
    animate(miniLayer, drawMinimap)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
-- The world map may load on demand, after login.
ns.On("PLAYER_LOGIN", function()
    if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
        setUpWorldMap()
    end
    setUpMinimap()
    rebuild()
end)

ns.On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" and IsLoggedIn() then
        setUpWorldMap()
    end
end)

ns.Listen("Updated", rebuild)
