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

-- Dots just above where the quest areas were; turn-in markers where the
-- game keeps its own quest pins, above other addons' map icons.
local function FrameLevel(levelType, fallback)
	local ok, level = pcall(function()
		return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel(levelType)
	end)
	return ok and level or canvas:GetFrameLevel() + fallback
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
		local level = FrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT", 1)
		local turnInLevel = FrameLevel("PIN_FRAME_LEVEL_ACTIVE_QUEST", 2)
		local width, height = canvas:GetSize()
		local scale = WorldMapFrame:GetCanvasScale()
		local points = ns.PointsOn(mapID)
		if width * scale > 0 and height * scale > 0 then
			points = ns.Cluster(points, CELL / (width * scale), CELL / (height * scale))
		end
		for _, point in ipairs(points) do
			local dot = pool:Acquire(point)
			dot:SetFrameLevel(point.target.turnIn and turnInLevel or level)
		end
	end
	pool:Finish()
	Layout()
end

-- The game pings a quest when you open its details or click its tracker
-- button; ripple its turn-in markers like the game's own pins did.
local function PingQuest(_, questID)
	C_Timer.After(0, function()
		for _, dot in pairs(pool and pool.active or {}) do
			local target = dot.point and dot.point.target
			if dot.wanted and target and target.turnIn and target.quest.questID == questID then
				ns.PlayRipple(dot)
			end
		end
	end)
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
	EventRegistry:RegisterCallback("MapCanvas.PingQuestID", PingQuest, ns)
	ns.HideMapAreas()
	ns.HideMapIcons()
	ns.RefreshWorldMap()
end
