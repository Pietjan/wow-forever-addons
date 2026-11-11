-- Dots on the world map, for zone-sized maps and smaller.
--
-- The dots are our own frames on the map canvas; we hook Blizzard's map
-- methods for when to redraw instead of registering a data provider, so
-- nothing of ours runs inside the map's own (secure) provider loops.

local _, ns = ...

local DOT_SIZE = 10
local TURN_IN_SIZE = 32 -- the game's quest pins draw at 32
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
-- button; ripple its turn-in markers like the game's own pins did. With
-- objectives = true (a quest the game has no map for) its objective dots
-- ripple instead while it is not complete.
local function PingQuest(_, questID, objectives)
	C_Timer.After(0, function()
		local complete = C_QuestLog.IsComplete(questID)
		for _, dot in pairs(pool and pool.active or {}) do
			local target = dot.point and dot.point.target
			if dot.wanted and target and target.quest.questID == questID
				and (target.turnIn or (objectives and not complete)) then
				ns.PlayRipple(dot)
			end
		end
	end)
end

-- The map with the most of a quest's points: its turn-in once complete,
-- else its objectives.
local function BestMap(questID)
	local quest = ns.Quest(questID)
	local byMap = C_QuestLog.IsComplete(questID) and quest.turnIns or quest.byMap
	local best, most = nil, 0
	for uiMap, points in pairs(byMap or {}) do
		if #points > most then
			best, most = uiMap, #points
		end
	end
	return best
end

-- Opening a quest's details moves the map to the quest's map, but only
-- when the game knows one (GetQuestUiMapID is not 0). For a quest it does
-- not know, such as one handed in at an object on another continent, the
-- map stayed where it was; go to where QuestieDB puts it instead.
local switching = false
local function OnShowQuestDetails(questID)
	if switching or not questID or GetQuestUiMapID(questID) ~= 0 then
		return
	end
	local uiMap = BestMap(questID)
	if not uiMap then
		return
	end
	if WorldMapFrame:GetMapID() ~= uiMap then
		switching = true
		WorldMapFrame:SetMapID(uiMap)
		switching = false
	end
	PingQuest(nil, questID, true)
end

function ns.SetUpWorldMap()
	if hooked or not WorldMapFrame then
		return
	end
	hooked = true
	canvas = WorldMapFrame:GetCanvas()
	pool = ns.DotPool(canvas, DOT_SIZE, TURN_IN_SIZE)
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
	if QuestMapFrame_ShowQuestDetails then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
			local ok, message = pcall(OnShowQuestDetails, questID)
			if not ok then
				switching = false
				ns.Print("could not open the quest's map: " .. tostring(message))
			end
		end)
	end
	ns.HideMapAreas()
	ns.HideMapIcons()
	ns.RefreshWorldMap()
end
