-- Tracked quests -> dots, plus the quest hovered in the map's quest log;
-- while a quest's details are open there, only that quest. Rebuilds after quest log and watch list changes,
-- and tells the world map and minimap to redraw.

local addonName, ns = ...

-- Soft (pastel) colours, picked to stay as far as pastels can from every
-- class colour (party members are class-coloured dots on the map) and from
-- the yellow the minimap uses for tracked herbs and ore. A quest gets one
-- the first time it shows dots and keeps it while it is in the quest log,
-- saved per character; a new quest takes the colour fewest other quests in
-- the log have.
local PALETTE = {
	{ 0.64, 0.90, 0.21 }, -- lime
	{ 0.43, 0.91, 0.72 }, -- emerald
	{ 0.85, 0.71, 1.00 }, -- lavender
	{ 0.98, 0.44, 0.52 }, -- rose
	{ 0.91, 0.47, 0.98 }, -- orchid
	{ 0.38, 0.65, 0.98 }, -- cornflower
	{ 1.00, 0.73, 0.35 }, -- peach
	{ 0.35, 0.35, 1.00 }, -- periwinkle
	{ 0.95, 0.49, 0.33 }, -- coral
	{ 0.35, 1.00, 0.35 }, -- mint
}

ns.active = {} -- quests whose objective dots show
ns.turnInQuests = {} -- completed quests whose turn-in "?" we draw (the game draws none)
local colorOf -- questID -> PALETTE index, the saved ForeverQuestsColors

function ns.Print(text)
	print("|cffffd100ForeverQuests|r: " .. text)
end

function ns.IsActive(questID)
	for _, quest in ipairs(ns.active) do
		if quest.questID == questID then
			return true
		end
	end
	return false
end

local function ColorOf(questID)
	local index = colorOf[questID]
	if not PALETTE[index] then
		local uses = {}
		for other, otherIndex in pairs(colorOf) do
			if C_QuestLog.GetLogIndexForQuestID(other) then
				uses[otherIndex] = (uses[otherIndex] or 0) + 1
			else
				colorOf[other] = nil -- abandoned or turned in
			end
		end
		index = 1
		for candidate = 2, #PALETTE do
			if (uses[candidate] or 0) < (uses[index] or 0) then
				index = candidate
			end
		end
		colorOf[questID] = index
	end
	return PALETTE[index]
end

local function TrackedQuests()
	local list = {}
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if questID then
			list[#list + 1] = questID
		end
	end
	return list
end

local function FocusedQuest()
	local questID = QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID()
	if questID and questID > 0 then
		return questID
	end
end

-- Whether the game's "?" turn-in icon of a quest should show.
function ns.ShowsTurnIn(questID)
	return questID == ns.focused or questID == ns.hovered or C_QuestLog.GetQuestWatchType(questID) ~= nil
end

-- Whether the game draws a "?" for this quest on one of the maps its
-- turn-in is on. It does not for every quest: one handed in at an object
-- on another continent gets none.
local function GameShowsTurnIn(quest)
	if not (C_QuestLog.GetQuestsOnMap and GetCVarBool("questPOI")) then
		return false
	end
	for uiMap in pairs(quest.turnIns) do
		local ok, onMap = pcall(C_QuestLog.GetQuestsOnMap, uiMap)
		for _, info in ipairs(ok and type(onMap) == "table" and onMap or {}) do
			if info.questID == quest.questID then
				return true
			end
		end
	end
	return false
end

function ns.Rebuild()
	if not ns.ready then
		return
	end
	wipe(ns.active)
	wipe(ns.turnInQuests)
	-- Where the game draws no "?" turn-in icon (its quest POIs switched off,
	-- or none for this quest) we draw one.
	local focused = FocusedQuest()
	ns.focused = focused
	local shown = focused and { focused } or TrackedQuests()
	if ns.hovered and not tContains(shown, ns.hovered) then
		shown[#shown + 1] = ns.hovered
	end
	for _, questID in ipairs(shown) do
		local quest = ns.Quest(questID)
		if C_QuestLog.IsComplete(questID) then
			if next(quest.turnIns) and not GameShowsTurnIn(quest) then
				quest.color = ColorOf(questID)
				ns.turnInQuests[#ns.turnInQuests + 1] = quest
			end
		elseif quest.count > 0 then
			ns.UpdateProgress(quest)
			quest.color = ColorOf(questID)
			ns.active[#ns.active + 1] = quest
		end
	end
	ns.ForgetPoints()
	ns.ResetMinimap()
	ns.RefreshWorldMap()
	ns.HideMapAreas() -- areas of quests without dots may need to come back
	ns.HideMapIcons()
end

local pending = false
local function ScheduleRebuild()
	if ns.ready and not pending then
		pending = true
		C_Timer.After(0.2, function()
			pending = false
			ns.Rebuild()
		end)
	end
end

local function Start()
	if not LibQuestieDB or not QuestDB then
		ns.Print("QuestieDB is not loaded, so no dots; the game's quest areas stay.")
		return
	end
	local ok, message = LibQuestieDB.RequireContract(1)
	if not ok then
		ns.Print("QuestieDB does not fit: " .. tostring(message))
		return
	end
	ForeverQuestsColors = type(ForeverQuestsColors) == "table" and ForeverQuestsColors or {}
	colorOf = ForeverQuestsColors
	ns.ready = true
	ns.HideMinimapAreas()
	ns.HideMinimapAreaTooltips()
	ns.SetUpMinimap()
	ns.Rebuild()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "PLAYER_LOGIN" then
		Start()
		if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
			ns.SetUpWorldMap()
		end
	elseif event == "ADDON_LOADED" then
		if arg == "Blizzard_WorldMap" and IsLoggedIn() then
			ns.SetUpWorldMap()
		end
	elseif event == "CVAR_UPDATE" then
		if arg == "questPOI" then
			ScheduleRebuild()
		end
	else
		ScheduleRebuild()
	end
end)

-- /fq: what we know about each tracked quest.
SLASH_FOREVERQUESTS1 = "/fq"
SLASH_FOREVERQUESTS2 = "/foreverquests"
SlashCmdList.FOREVERQUESTS = function(input)
	if input and input:match("^%s*tip") then
		ns.Print("last minimap tooltip, as the game wrote it:")
		for i, text in ipairs(ns.lastMinimapTip or {}) do
			print(("  %d: %s"):format(i, (text:gsub("|", "||"):gsub("\n", " \\n "))))
		end
		return
	end
	if not ns.ready then
		ns.Print("not running: QuestieDB is missing or does not fit.")
		return
	end
	local mode = LibQuestieDB.readMode or "?"
	ns.Print(("QuestieDB %s mode. Game quest POIs %s. Tracked quests:"):format(mode,
		GetCVarBool("questPOI") and "on (we hide theirs)" or "off (we draw turn-in icons)"))
	for _, questID in ipairs(TrackedQuests()) do
		local quest = ns.Quest(questID)
		local title = C_QuestLog.GetTitleForQuestID(questID) or "?"
		if not QuestDB.Exists(questID) then
			print(("  %d %s: not in QuestieDB, quest area kept"):format(questID, title))
		elseif quest.count == 0 then
			print(("  %d %s: in QuestieDB but no spawn points, quest area kept"):format(questID, title))
		else
			ns.UpdateProgress(quest)
			local open, maps = 0, {}
			for _, target in ipairs(quest.targets) do
				if target.open then
					open = open + 1
				end
			end
			for uiMap, spots in pairs(quest.byMap) do
				local info = C_Map.GetMapInfo(uiMap)
				maps[#maps + 1] = ("%s %d"):format(info and info.name or uiMap, #spots)
			end
			print(("  %d %s: %d spawns (%s), %d of %d sources still needed%s"):format(
				questID, title, quest.count, table.concat(maps, ", "), open, #quest.targets,
				C_QuestLog.IsComplete(questID) and ", complete" or ""))
		end
		if QuestDB.Exists(questID) then
			local turnIns = {}
			for uiMap, spots in pairs(quest.turnIns) do
				local info = C_Map.GetMapInfo(uiMap)
				turnIns[#turnIns + 1] = ("%s %d"):format(info and info.name or uiMap, #spots)
			end
			local gameMap = GetQuestUiMapID and GetQuestUiMapID(questID) or 0
			local gameInfo = gameMap ~= 0 and C_Map.GetMapInfo(gameMap)
			print(("      turn-in: %s; the game's map for it: %s"):format(
				#turnIns > 0 and table.concat(turnIns, ", ") or "none known",
				gameInfo and gameInfo.name or tostring(gameMap)))
		end
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	print(("  %d dots on your current map."):format(#ns.PointsOn(mapID)))
end

_G[addonName] = ns -- for /dump while testing
