-- XPBar.lua: a segment on the experience bar for the XP the completed
-- quests in the log will give when handed in. It starts where the bar's
-- fill ends and reaches as far as that XP goes, stopping at the bar's
-- right edge when it runs into the next level.
--
-- Each experience bar (the main and the secondary status bar container
-- both have one) gets a frame of our own as a child, so it shows, hides
-- and fades with that bar. Nothing of the game's bars is written or
-- called; their size is only followed through our frame's anchors.

local _, ns = ...

local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local COLOR = { 1.00, 0.73, 0.35, 0.75 } -- peach, apart from the XP and rested fills

local IsSecret = issecretvalue or function() return false end
local overlays = {} -- exp bar -> our frame

local function Plain(value)
	if type(value) ~= "number" or IsSecret(value) then
		return nil
	end
	return value
end

-- XP of every completed quest in the log, or nil when a number is hidden.
function ns.CompletedQuestXP()
	local total, count = 0, 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
			local xp = Plain((GetQuestLogRewardXP(info.questID)))
			if not xp then
				return nil
			end
			total, count = total + xp, count + 1
		end
	end
	return total, count
end

local function ExpBars()
	local bars = {}
	local manager = StatusTrackingBarManager
	for _, container in ipairs(manager and manager.barContainers or {}) do
		for _, bar in pairs(container.bars or {}) do
			if bar.isExpBar and bar.StatusBar then
				bars[#bars + 1] = bar
			end
		end
	end
	return bars
end

local function Layout(frame, have, max, gain)
	local width = frame:GetWidth()
	if not (have and max and gain) or max <= 0 or gain <= 0 or not width or width <= 0 then
		frame.fill:Hide()
		return
	end
	local from = math.min(have / max, 1) * width
	local to = math.min((have + gain) / max, 1) * width
	if to - from < 1 then
		frame.fill:Hide()
		return
	end
	frame.fill:ClearAllPoints()
	frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", from, 0)
	frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", from, 0)
	frame.fill:SetWidth(to - from)
	frame.fill:Show()
end

local last = {} -- have, max, gain as last worked out

local function Update()
	local gain = ns.CompletedQuestXP()
	if gain == nil then
		return -- keep what shows until the numbers can be read again
	end
	last.have, last.max, last.gain = Plain(UnitXP("player")), Plain(UnitXPMax("player")), gain
	for _, frame in pairs(overlays) do
		Layout(frame, last.have, last.max, last.gain)
	end
end

local function Attach()
	for _, bar in ipairs(ExpBars()) do
		if not overlays[bar] then
			local frame = CreateFrame("Frame", nil, bar)
			frame:SetAllPoints(bar.StatusBar)
			frame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 1)
			local fill = frame:CreateTexture(nil, "ARTWORK")
			fill:SetTexture(TEXTURE)
			fill:SetVertexColor(unpack(COLOR))
			fill:Hide()
			frame.fill = fill
			frame:SetScript("OnSizeChanged", function(self)
				Layout(self, last.have, last.max, last.gain)
			end)
			overlays[bar] = frame
		end
	end
end

local pending = false
local function Schedule()
	if not pending then
		pending = true
		C_Timer.After(0.2, function()
			pending = false
			Attach()
			Update()
		end)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_REGEN_ENABLED") -- numbers hidden in combat can be read again
events:SetScript("OnEvent", Schedule)
