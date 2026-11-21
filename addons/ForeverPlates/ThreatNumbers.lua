-- Threat numbers (/fplates numbers): your threat on an enemy as a
-- percentage, right of its nameplate's health bar, or right of the level
-- box while that shows (OnShow/OnHide hooked on it, as Enemy targets does
-- with the cast bar).
--
-- The number is the one Blizzard puts on the target frame (Options >
-- Combat, numeric threat), worked out the same way in
-- UnitFrame_UpdateThreatIndicator: while it is not on you, your threat as
-- a percentage of the threat of whoever it is on (melee pull it from them
-- at 110, ranged at 130); while it is on you, UnitThreatPercentageOfLead
-- (undocumented; by its name your threat against whoever is second, not
-- checked in game). No number when it is 0 or nil (you are not on its
-- list), and none on "minus" mobs, as Blizzard does.
--
-- Threat values are secret to addon code on bosses (and wherever else the
-- game says ShouldUnitThreatValuesBeSecret). The number cannot be looked at
-- then, but SetFormattedText takes a secret number and the game writes it.
-- Whether it is on you may be secret too: then the plate has both numbers
-- and SetAlphaFromBoolean lets the game show the right one. A secret 0
-- cannot be told from any other number, so on bosses a 0% can show.
--
-- Like Enemy targets, the text is a FontString on a frame of this file's
-- own, parented to the nameplate; nothing on the plate is written or
-- measured. Updates come from the threat events of nameplate units and a
-- 0.5 s sweep.

local _, ns = ...
local IsSecret = ns.IsSecret

local SWEEP = 0.5
local SIZE = 0.85 -- of the nameplate name's height, as Enemy targets
local FORMAT = "%.0f%%"

local feature
local labels = {} -- nameplate -> our frame
local lastError -- the last error caught, for /fplates numbers
local ticker

local function Note(err)
	lastError = tostring(err)
end

local function ApplyFont(frame)
	local object, height = ns.NamePlateFont()
	local key = object .. ":" .. tostring(height)
	if frame.fontKey == key then
		return
	end
	frame.fontKey = key
	for _, text in ipairs({ frame.behind, frame.ahead }) do
		text:SetFontObject(object)
		if type(height) == "number" and height > 0 then
			text:SetTextHeight(height * SIZE)
		end
	end
end

local function LabelFor(plate)
	local frame = labels[plate]
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", nil, plate)
	frame:SetSize(1, 1)
	local okLevel, level = pcall(plate.GetFrameLevel, plate)
	if okLevel and type(level) == "number" and not IsSecret(level) then
		frame:SetFrameLevel(level + 110)
	end
	-- behind: your share of the threat of whoever it is on; ahead: your lead
	-- while it is on you. Only one shows.
	local behind = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
	local ahead = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
	local unitFrame = plate.UnitFrame
	local health = unitFrame and unitFrame.HealthBarsContainer
	local level = unitFrame and unitFrame.PlayerLevelDiffFrame

	-- Right of the level box while it shows, else right of the health bar.
	local function Anchor(levelShown)
		for _, text in ipairs({ behind, ahead }) do
			text:ClearAllPoints()
			if levelShown and level then
				text:SetPoint("LEFT", level, "RIGHT", 3, 0)
			elseif health then
				-- More room than beside the level box: the bar's border art
				-- reaches past its container.
				text:SetPoint("LEFT", health, "RIGHT", 6, 0)
			else
				text:SetPoint("LEFT", plate, "RIGHT", 0, 0)
			end
		end
	end
	for _, text in ipairs({ behind, ahead }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	Anchor(false)
	if level then
		-- HookScript runs after Blizzard's own handler and only moves our
		-- text. Guarded: should Forever refuse it, the text stays beside
		-- the health bar.
		local okHook, err = pcall(function()
			level:HookScript("OnShow", function() Anchor(true) end)
			level:HookScript("OnHide", function() Anchor(false) end)
		end)
		if not okHook then
			Note(err)
		end
		local okShown, shown = pcall(level.IsShown, level)
		if okShown and not IsSecret(shown) and shown == true then
			Anchor(true)
		end
	end
	frame.behind, frame.ahead = behind, ahead
	frame:Hide()
	labels[plate] = frame
	return frame
end

-- Fill one plate's numbers; false when there is nothing to show.
local function Fill(frame, unit)
	ApplyFont(frame)
	if not UnitExists(unit) or not UnitCanAttack("player", unit) or UnitIsDead(unit) then
		return false
	end
	local class = UnitClassification(unit)
	if not IsSecret(class) and class == "minus" then
		return false
	end
	local isTanking, _, _, raw = UnitDetailedThreatSituation("player", unit)
	if isTanking == nil then
		return false -- not on its threat list
	end
	local behind, ahead = frame.behind, frame.ahead
	if IsSecret(isTanking) then
		-- The game picks which of the two is visible.
		behind:SetFormattedText(FORMAT, raw)
		ahead:SetFormattedText(FORMAT, UnitThreatPercentageOfLead("player", unit))
		ahead:SetAlphaFromBoolean(isTanking)
		behind:SetAlphaFromBoolean(isTanking, 0, 255)
		return true
	end
	local display = isTanking and UnitThreatPercentageOfLead("player", unit) or raw
	if not IsSecret(display) and (not display or display == 0) then
		return false
	end
	behind:SetFormattedText(FORMAT, display)
	behind:SetAlpha(1)
	ahead:SetAlpha(0)
	return true
end

local function Update(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	local okFrame, frame = pcall(LabelFor, plate)
	if not okFrame then
		Note(frame)
		return
	end
	local ok, shown = pcall(Fill, frame, unit)
	if not ok then
		Note(shown)
	end
	frame:SetShown(ok and shown == true)
end

local function UpdateAll()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.UnitFrame and plate.UnitFrame.unit
		if type(unit) == "string" and not IsSecret(unit) then
			Update(unit)
		elseif labels[plate] then
			labels[plate]:Hide()
		end
	end
end

-- /fplates numbers: what the feature sees on your target.
local function Report()
	local Say = ns.Print
	Say("Threat numbers " .. (feature.db.enabled and "on" or "off; /fplates numbers on"))
	if UnitExists("target") and UnitCanAttack("player", "target") then
		local ok, isTanking, status, scaled, raw = pcall(UnitDetailedThreatSituation, "player", "target")
		local okLead, lead = pcall(UnitThreatPercentageOfLead, "player", "target")
		local function show(v)
			return IsSecret(v) and "secret" or tostring(v)
		end
		Say(("target: on you %s, status %s, scaled %s%%, raw %s%%, lead %s%%"):format(
			ok and show(isTanking) or "error", ok and show(status) or "?", ok and show(scaled) or "?",
			ok and show(raw) or "?", okLead and show(lead) or "error"))
	end
	Say("last error: " .. (lastError or "none"))
end

feature = ns.Feature({
	key = "numbers",
	title = "Threat numbers",
	tooltip = "Your threat on each enemy as a percentage, right of its health bar and level box: the number Blizzard shows on the target frame.",
	defaults = { enabled = true },
	events = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" },
	Command = Report,
})

function feature.Start()
	ticker = C_Timer.NewTicker(SWEEP, UpdateAll)
	UpdateAll()
end

function feature.Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	for _, frame in pairs(labels) do
		frame:Hide()
	end
end

function feature.OnEvent(event, unit)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and labels[plate] then
			labels[plate]:Hide()
		end
	elseif type(unit) == "string" and not IsSecret(unit) and unit:find("^nameplate") then
		Update(unit)
	else
		-- UNIT_THREAT_SITUATION_UPDATE for you or your pet: any plate may change.
		UpdateAll()
	end
end
