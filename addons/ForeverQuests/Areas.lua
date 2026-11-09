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

-- Blizzard's quest icons on the world map: the "..." in-progress icons go,
-- the dots take their place; a "?" turn-in icon shows only for a tracked,
-- open or hovered quest. The icons are
-- Blizzard's QuestPinTemplate pins, re-acquired on every refresh of the
-- quest data provider, so a post-hook on that refresh hides them again.

local hiddenIcons = {}
local hookedProviders = {}

-- Our own show/hide of an icon fades like the dots. Quest pins do not
-- manage their alpha themselves, so it is ours while fading.
local FADE = 0.2 -- seconds
local fadingIcons = {} -- pin -> true fading in, false fading out
local fader = CreateFrame("Frame")

local function FadeIcons(_, elapsed)
	local step = elapsed / FADE
	for pin, fadeIn in pairs(fadingIcons) do
		local alpha = pin:GetAlpha() + (fadeIn and step or -step)
		if fadeIn and alpha >= 1 then
			pin:SetAlpha(1)
			fadingIcons[pin] = nil
		elseif not fadeIn and alpha <= 0 then
			pin:Hide()
			pin:SetAlpha(1)
			fadingIcons[pin] = nil
		else
			pin:SetAlpha(alpha)
		end
	end
	if not next(fadingIcons) then
		fader:SetScript("OnUpdate", nil)
	end
end

local function FadeIcon(pin, fadeIn)
	if fadeIn then
		if not pin:IsShown() then
			pin:SetAlpha(0)
			pin:Show()
		end
	end
	fadingIcons[pin] = fadeIn
	fader:SetScript("OnUpdate", FadeIcons)
end

-- After a refresh every pin is new: put alphas back, stop all fades.
local function StopIconFades()
	for pin in pairs(fadingIcons) do
		pin:SetAlpha(1)
	end
	wipe(fadingIcons)
	fader:SetScript("OnUpdate", nil)
end

local function UpdateQuestIcons(instant)
	if not WorldMapFrame or not WorldMapFrame.EnumeratePinsByTemplate then
		return
	end
	for pin in WorldMapFrame:EnumeratePinsByTemplate("QuestPinTemplate") do
		local questID = pin.GetQuestID and pin:GetQuestID()
		local style = pin.GetStyle and pin:GetStyle()
		local hide = false
		if questID and ns.ready then
			if style == POIButtonUtil.Style.QuestInProgress then
				hide = true
			elseif style == POIButtonUtil.Style.QuestComplete then
				hide = not ns.ShowsTurnIn(questID)
			end
		end
		if hide then
			if pin:IsShown() and not hiddenIcons[pin] then
				hiddenIcons[pin] = true
				if instant then
					pin:Hide()
				else
					FadeIcon(pin, false)
				end
			end
		elseif hiddenIcons[pin] then
			hiddenIcons[pin] = nil
			FadeIcon(pin, true)
		end
	end
end

-- Selecting a quest pings its icon's spot; with the icon hidden, hide the
-- ping too.
local function HidePing(provider)
	local ping = provider.pingPin
	if not ping or not ping.GetID then
		return
	end
	local idKey, id = ping:GetID()
	if idKey ~= "questID" then
		return
	end
	for pin in pairs(hiddenIcons) do
		if pin:GetQuestID() == id then
			ping:Hide()
			return
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
			hooksecurefunc(provider, "RefreshAllData", function(self)
				wipe(hiddenIcons) -- every pin was released and acquired again
				StopIconFades()
				UpdateQuestIcons(true)
				HidePing(self)
			end)
			if provider.PingQuestID then
				hooksecurefunc(provider, "PingQuestID", HidePing)
			end
		end
	end
	UpdateQuestIcons(false)
end
