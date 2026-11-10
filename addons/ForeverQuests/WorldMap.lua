-- Dots on the world map, for zone-sized maps and smaller.
--
-- The dots are our own frames on the map canvas; we hook Blizzard's map
-- methods for when to redraw instead of registering a data provider, so
-- nothing of ours runs inside the map's own (secure) provider loops.

local _, ns = ...

local DOT_SIZE = 10
local CELL = 15 -- dots of one quest closer than this (screen units) merge

local pool
local canvas
local hooked = false
local shownMap

local function Place(dot)
	local scale = 1 / WorldMapFrame:GetCanvasScale()
	local width, height = canvas:GetSize()
	dot:SetScale(scale)
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", canvas, "TOPLEFT", dot.point.x * width / scale, -dot.point.y * height / scale)
end

local function Layout()
	if not pool then
		return
	end
	for _, dot in pairs(pool.active) do
		Place(dot)
	end
end

local function FrameLevel()
	local ok, level = pcall(function()
		return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
	end)
	return ok and level or canvas:GetFrameLevel() + 1
end

function ns.RefreshWorldMap()
	if not pool or not WorldMapFrame:IsShown() then
		return
	end
	local mapID = WorldMapFrame:GetMapID()
	if mapID ~= shownMap then
		shownMap = mapID
		pool:Clear()
	end
	pool:Begin()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if ns.ready and info and info.mapType >= Enum.UIMapType.Zone then
		local level = FrameLevel()
		local width, height = canvas:GetSize()
		local scale = WorldMapFrame:GetCanvasScale()
		local points = ns.PointsOn(mapID)
		if width * scale > 0 and height * scale > 0 then
			points = ns.Cluster(points, CELL / (width * scale), CELL / (height * scale))
		end
		for _, point in ipairs(points) do
			local dot = pool:Acquire(point)
			dot:SetFrameLevel(level)
		end
	end
	pool:Finish()
	Layout()
end

function ns.SetUpWorldMap()
	if hooked or not WorldMapFrame then
		return
	end
	hooked = true
	canvas = WorldMapFrame:GetCanvas()
	pool = ns.DotPool(canvas, DOT_SIZE)
	hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.RefreshWorldMap)
	-- Zooming changes which dots overlap, so merge again.
	hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", ns.RefreshWorldMap)
	hooksecurefunc(WorldMapFrame, "OnCanvasSizeChanged", ns.RefreshWorldMap)
	WorldMapFrame:HookScript("OnShow", ns.RefreshWorldMap)
	-- Opening a quest's details in the map's quest log focuses it.
	hooksecurefunc(WorldMapFrame, "SetFocusedQuestID", ns.Rebuild)
	hooksecurefunc(WorldMapFrame, "ClearFocusedQuestID", ns.Rebuild)
	-- Hovering a quest in that log highlights it.
	hooksecurefunc(WorldMapFrame, "SetHighlightedQuestID", function(_, questID)
		ns.hovered = questID
		ns.Rebuild()
	end)
	hooksecurefunc(WorldMapFrame, "ClearHighlightedQuestID", function()
		ns.hovered = nil
		ns.Rebuild()
	end)
	ns.HideMapAreas()
	ns.HideMapIcons()
	ns.RefreshWorldMap()
end
