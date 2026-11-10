-- Tracked quests -> dots, plus the quest hovered in the map's quest log;
-- while a quest's details are open there, only that quest. Rebuilds after quest log and watch list changes,
-- and tells the world map and minimap to redraw.

local addonName, ns = ...

-- Distinct, bright colours. A quest gets one the first time it shows dots
-- and keeps it while it is in the quest log, saved per character; a new
-- quest takes the colour fewest other quests in the log have.
local PALETTE = {
	{ 0.95, 0.95, 0.95 }, -- not yellow: the minimap uses that for tracked herbs and ore
	{ 0.30, 0.80, 1.00 },
	{ 1.00, 0.35, 0.35 },
	{ 0.45, 1.00, 0.35 },
	{ 1.00, 0.45, 1.00 },
	{ 1.00, 0.60, 0.15 },
	{ 0.60, 0.55, 1.00 },
	{ 0.35, 1.00, 0.80 },
}

ns.active = {}
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

function ns.Rebuild()
	if not ns.ready then
		return
	end
	wipe(ns.active)
	local focused = FocusedQuest()
	ns.focused = focused
	local shown = focused and { focused } or TrackedQuests()
	if ns.hovered and not tContains(shown, ns.hovered) then
		shown[#shown + 1] = ns.hovered
	end
	for _, questID in ipairs(shown) do
		local quest = ns.Quest(questID)
		if quest.count > 0 and not C_QuestLog.IsComplete(questID) then
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
