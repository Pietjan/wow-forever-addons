-- Dots on the minimap: the tracked quests' spawns within the minimap's view
-- radius, placed from the player's position on the current zone map and
-- turned with the minimap when it rotates.

local _, ns = ...

local DOT_SIZE = 8
local INTERVAL = 0.03 -- seconds between position updates
local EDGE = 0.92 -- keep dots off the round frame's rim

local layer, pool
local mapID, points, mapWidth, mapHeight
local elapsedSince = 0

function ns.ResetMinimap()
	mapID = nil
end

local function Update()
	pool:Begin()
	local current = ns.ready and C_Map.GetBestMapForUnit("player")
	if current ~= mapID then
		mapID = current
		points = ns.PointsOn(mapID)
		mapWidth, mapHeight = 0, 0
		if mapID then
			mapWidth, mapHeight = C_Map.GetMapWorldSize(mapID)
			mapWidth, mapHeight = mapWidth or 0, mapHeight or 0
		end
	end
	local position = mapID and #points > 0 and mapWidth > 0 and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		local px, py = position:GetXY()
		local radius = C_Minimap.GetViewRadius()
		local half = Minimap:GetWidth() / 2
		local limit = (radius * EDGE) ^ 2
		local rotates = GetCVarBool("rotateMinimap") and not C_Minimap.IsRotateMinimapIgnored()
		local facing = rotates and GetPlayerFacing() or nil
		local cos, sin = 1, 0
		if facing then
			cos, sin = math.cos(facing), math.sin(facing)
		end
		if radius > 0 and (facing or not rotates) then
			for _, point in ipairs(points) do
				local east = (point.x - px) * mapWidth -- yards
				local north = (py - point.y) * mapHeight
				local x, y = east, north
				if facing then
					-- Facing is counter-clockwise from north; the rotating
					-- minimap keeps the facing direction pointing up.
					x, y = east * cos + north * sin, north * cos - east * sin
				end
				if x * x + y * y < limit then
					local dot = pool:Acquire(point)
					dot:ClearAllPoints()
					dot:SetPoint("CENTER", layer, "CENTER", x / radius * half, y / radius * half)
				end
			end
		end
	end
	pool:Finish()
end

local function OnUpdate(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince >= INTERVAL then
		elapsedSince = 0
		Update()
	end
end

function ns.SetUpMinimap()
	if layer or not Minimap then
		return
	end
	layer = CreateFrame("Frame", nil, Minimap)
	layer:SetAllPoints()
	layer:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	pool = ns.DotPool(layer, DOT_SIZE)
	layer:SetScript("OnUpdate", OnUpdate)
end
