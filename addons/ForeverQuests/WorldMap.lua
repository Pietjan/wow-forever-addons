-- Dots on the world map, for zone-sized maps and smaller.
--
-- The dots are our own frames on the map canvas; we hook Blizzard's map
-- methods for when to redraw instead of registering a data provider, so
-- nothing of ours runs inside the map's own (secure) provider loops.

local _, ns = ...

local DOT_SIZE = 8
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
-- The quest log re-opens the open quest on every quest log update, which
-- pings again; ripple once per opening.
local pingedOpen, pingedObjectives

local function PingQuest(_, questID, objectives)
	local open = QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID()
	if open and open == questID then
		if pingedOpen == questID and (pingedObjectives or not objectives) then
			return
		end
		pingedOpen = questID
		pingedObjectives = pingedObjectives or objectives
	end
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

-- Opening a quest's details moves the map to the map the game gives the
-- quest (GetQuestUiMapID). For some quests that map has nothing on it:
-- "... and that note you found" opens on the Barrens, where it was picked
-- up, while it is handed in at an object in Westfall; others get no map at
-- all (0). When the game's map has neither a game marker for the quest nor
-- any of our points, the map is where QuestieDB puts it instead.
local function ShownHere(questID, uiMap)
	local quest = ns.Quest(questID)
	local byMap = C_QuestLog.IsComplete(questID) and quest.turnIns or quest.byMap
	if byMap and byMap[uiMap] and #byMap[uiMap] > 0 then
		return true
	end
	local ok, onMap = pcall(C_QuestLog.GetQuestsOnMap, uiMap)
	for _, info in ipairs(ok and type(onMap) == "table" and onMap or {}) do
		if info.questID == questID then
			return true
		end
	end
	return false
end

local function BetterMap(questID, gameMap)
	if not ns.ready or not questID then
		return nil
	end
	if gameMap and gameMap ~= 0 and ShownHere(questID, gameMap) then
		return nil
	end
	return BestMap(questID)
end

-- The quest log asks GetQuestUiMapID by name each time it opens a quest's
-- details, and again on every quest log update, then sets the map and
-- remembers it as the quest's map (closing the details if the map ever
-- differs). Switching the map afterwards would close the details, so the
-- answer itself is ours for such quests: Blizzard then opens the details
-- on that map, keeps them open, and Back returns to the map shown before.
-- Replacing the global taints the quest log paths that call it; the quest
-- log has no protected actions.
local overridden = {} -- questID -> true while we chose its map
local function InstallQuestMapOverride()
	local original = GetQuestUiMapID
	if type(original) ~= "function" then
		return
	end
	GetQuestUiMapID = function(questID, ...)
		local gameMap = original(questID, ...)
		local ok, better = pcall(BetterMap, questID, gameMap)
		if ok and better then
			overridden[questID] = true
			return better
		end
		overridden[questID] = nil
		return gameMap
	end
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
	hooksecurefunc(WorldMapFrame, "ClearFocusedQuestID", function()
		pingedOpen, pingedObjectives = nil, nil
		ns.Rebuild()
	end)
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
	InstallQuestMapOverride()
	if QuestMapFrame_ShowQuestDetails then
		-- On a map we chose, ripple the quest's markers (objective dots too):
		-- the game's own ping only finds its own pins.
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
			if overridden[questID] then
				PingQuest(nil, questID, true)
			end
		end)
	end
	ns.HideMapAreas()
	ns.HideMapIcons()
	ns.RefreshWorldMap()
end
