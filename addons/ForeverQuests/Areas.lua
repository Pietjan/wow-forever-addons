-- Switch off the quest areas the game paints over the map and minimap.
--
-- World map: Blizzard's single QuestBlobPin redraws on every selection
-- change. A post-hook on its Refresh wipes the drawing again and only puts
-- back areas of quests we have no dots for, so those keep some guidance.
--
-- Minimap: the engine draws the areas itself; all we can do is make them
-- fully transparent.

local _, ns = ...

local hooked = {}

local function RedrawBlobs(pin)
	pin:DrawNone()
	if not pin.mapAllowsBlobs or not GetCVarBool("questPOI") then
		return
	end
	local candidates = {
		not pin.focusedQuestID and pin.questID or nil,
		pin.highlightedQuestID,
		pin.focusedQuestID,
		POIButtonHighlightManager and POIButtonHighlightManager:GetQuestID() or nil,
	}
	for i = 1, 4 do
		local questID = candidates[i]
		if questID and questID > 0 and not ns.HasMarkers(questID) then
			pin:TryDrawQuest(questID)
		end
	end
end

function ns.HideMapAreas()
	if not WorldMapFrame or not WorldMapFrame.EnumeratePinsByTemplate then
		return
	end
	for pin in WorldMapFrame:EnumeratePinsByTemplate("QuestBlobPinTemplate") do
		if not hooked[pin] then
			hooked[pin] = true
			hooksecurefunc(pin, "Refresh", RedrawBlobs)
		end
		RedrawBlobs(pin)
	end
end

function ns.HideMinimapAreas()
	for _, method in ipairs({ "SetQuestBlobInsideAlpha", "SetQuestBlobOutsideAlpha", "SetQuestBlobRingAlpha" }) do
		if Minimap[method] then
			pcall(Minimap[method], Minimap, 0)
		end
	end
end

-- The "..." in-progress icons on the world map, for quests that have dots;
-- turn-in "?" icons and quests without dots keep theirs. The icons are
-- Blizzard's QuestPinTemplate pins, re-acquired on every refresh of the
-- quest data provider, so a post-hook on that refresh hides them again.

local hiddenIcons = {}
local hookedProviders = {}

local function UpdateQuestIcons()
	if not WorldMapFrame or not WorldMapFrame.EnumeratePinsByTemplate then
		return
	end
	for pin in WorldMapFrame:EnumeratePinsByTemplate("QuestPinTemplate") do
		local questID = pin.GetQuestID and pin:GetQuestID()
		local inProgress = pin.GetStyle and pin:GetStyle() == POIButtonUtil.Style.QuestInProgress
		if questID and inProgress and ns.IsActive(questID) then
			if pin:IsShown() then
				pin:Hide()
				hiddenIcons[pin] = true
			end
		elseif hiddenIcons[pin] then
			hiddenIcons[pin] = nil
			pin:Show()
		end
	end
end

function ns.HideMapIcons()
	if not WorldMapFrame or type(WorldMapFrame.dataProviders) ~= "table" then
		return
	end
	for provider in pairs(WorldMapFrame.dataProviders) do
		if not hookedProviders[provider] and provider.AddQuest and provider.GetPinTemplate
			and provider:GetPinTemplate() == "QuestPinTemplate" then
			hookedProviders[provider] = true
			hooksecurefunc(provider, "RefreshAllData", function()
				wipe(hiddenIcons) -- every pin was released and acquired again
				UpdateQuestIcons()
			end)
		end
	end
	UpdateQuestIcons()
end
