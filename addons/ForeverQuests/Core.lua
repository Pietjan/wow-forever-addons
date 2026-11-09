-- Tracked quests -> dots; while a quest's details are open in the map's
-- quest log, only that quest. Rebuilds after quest log and watch list changes,
-- and tells the world map and minimap to redraw.

local addonName, ns = ...

-- Distinct, bright colours, handed out to tracked quests in turn and kept
-- for the session so a quest does not change colour when another is tracked.
local PALETTE = {
	{ 1.00, 0.82, 0.00 },
	{ 0.30, 0.80, 1.00 },
	{ 1.00, 0.35, 0.35 },
	{ 0.45, 1.00, 0.35 },
	{ 1.00, 0.45, 1.00 },
	{ 1.00, 0.60, 0.15 },
	{ 0.60, 0.55, 1.00 },
	{ 0.35, 1.00, 0.80 },
}

ns.active = {}
local colorOf = {}

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

local function PickColor(questID, taken)
	local color = colorOf[questID]
	if color and not taken[color] then
		return color
	end
	for _, candidate in ipairs(PALETTE) do
		if not taken[candidate] then
			colorOf[questID] = candidate
			return candidate
		end
	end
	return PALETTE[questID % #PALETTE + 1]
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

function ns.Rebuild()
	if not ns.ready then
		return
	end
	wipe(ns.active)
	local taken = {}
	local focused = FocusedQuest()
	for _, questID in ipairs(focused and { focused } or TrackedQuests()) do
		local quest = ns.Quest(questID)
		if quest.count > 0 and not C_QuestLog.IsComplete(questID) then
			ns.UpdateProgress(quest)
			quest.color = PickColor(questID, taken)
			taken[quest.color] = true
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
	ns.ready = true
	ns.HideMinimapAreas()
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
	else
		ScheduleRebuild()
	end
end)

-- /fq: what we know about each tracked quest.
SLASH_FOREVERQUESTS1 = "/fq"
SLASH_FOREVERQUESTS2 = "/foreverquests"
SlashCmdList.FOREVERQUESTS = function()
	if not ns.ready then
		ns.Print("not running: QuestieDB is missing or does not fit.")
		return
	end
	local mode = LibQuestieDB.readMode or "?"
	ns.Print(("QuestieDB %s mode. Tracked quests:"):format(mode))
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
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	print(("  %d dots on your current map."):format(#ns.PointsOn(mapID)))
end

_G[addonName] = ns -- for /dump while testing
