-- TotemBarTimes: the time left on each active totem, written on its slot of
-- Blizzard's totem bar (MultiCastActionBarFrame).
--
-- Totem times can be secret (GetTotemInfo is SecretWhenTotemSlotSecret), so
-- Lua never reads them: a duration text binding hands the totem's duration
-- object to the game, which writes the countdown into the font string.

local SLOT_BUTTONS = 4

-- The same formatter Blizzard's aura containers use: "5 m", "90 s".
local formatter = C_StringUtil.CreateSecondsFormatter()
do
	local curve = C_CurveUtil.CreateCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	curve:AddPoint(0, Enum.SecondsFormatterInterval.Seconds)
	curve:AddPoint(1 + 1.5 * SECONDS_PER_MIN, Enum.SecondsFormatterInterval.Minutes)
	curve:AddPoint(1 + 1.5 * SECONDS_PER_HOUR, Enum.SecondsFormatterInterval.Hours)
	formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
	formatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
	formatter:SetCanRoundUpLastUnit(true)
	formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
	formatter:SetMaxIntervalCurve(curve)
	formatter:SetDesiredUnitCount(1)
	formatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale) -- "4m", not "4 m"
end

-- Text colour by time left, picked by the game (works on secret times):
-- white, yellow under 10 s, red under 5 s.
local colorCurve = C_CurveUtil.CreateColorCurve()
colorCurve:SetType(Enum.LuaCurveType.Step)
colorCurve:AddPoint(0, CreateColor(1, 0.15, 0.15, 1))
colorCurve:AddPoint(5, CreateColor(1, 0.82, 0, 1))
colorCurve:AddPoint(10, CreateColor(1, 1, 1, 1))

local overlays = {}

-- One text per slot button, on a child frame raised above the action button
-- that Blizzard lays over the slot.
local function Overlay(button)
	local overlay = overlays[button]
	if overlay then return overlay end
	overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button:GetFrameLevel() + 10)
	overlay.text = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	overlay.text:SetPoint("BOTTOM", 0, 1)
	-- Same face and size, heavier outline than the font object's.
	local font, size = overlay.text:GetFont()
	overlay.text:SetFont(font, size, "THICKOUTLINE")
	local binding = C_DurationUtil.CreateDurationTextBinding()
	binding:SetToDefaults()
	binding:SetFormatter(formatter)
	binding:SetZeroDurationText("")
	binding:SetExpiredText("")
	binding:SetFontString(overlay.text)
	binding:SetTextColorCurve(colorCurve, Enum.DurationTextBindingProperty.RemainingDuration)
	overlay.binding = binding
	overlays[button] = overlay
	return overlay
end

local warned = false

-- A slot button's ID is the totem slot it shows (0 when hidden); Blizzard
-- reassigns it in MultiCastSlotButton_Update.
local function Refresh(button)
	local slot = button:GetID()
	local overlay = Overlay(button)
	if slot == 0 then
		overlay.binding:SetEnabled(false)
		overlay.text:SetText("")
		return
	end
	-- Seen in game at login: SetDuration refused what GetTotemDuration gave
	-- (documented never nil), so an empty answer means no countdown.
	local duration = GetTotemDuration(slot)
	if duration == nil then
		overlay.binding:SetEnabled(false)
		overlay.text:SetText("")
		return
	end
	local ok, err = pcall(function()
		overlay.binding:SetDuration(duration)
		overlay.binding:SetEnabled(true)
	end)
	if not ok and not warned then
		warned = true
		print(("|cffff8000TotemBarTimes:|r slot %d, %s: %s"):format(slot, type(duration), tostring(err)))
	end
end

local function RefreshAll()
	for i = 1, SLOT_BUTTONS do
		local button = _G["MultiCastSlotButton" .. i]
		if button then Refresh(button) end
	end
end

if MultiCastSlotButton_Update then
	hooksecurefunc("MultiCastSlotButton_Update", Refresh)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TOTEM_UPDATE")
events:SetScript("OnEvent", RefreshAll)
