-- Quest enemies (/fplates quest): puts a quest icon next to the nameplate of every enemy that
-- still counts towards one of your quest objectives.
--
-- The icon goes left of whatever sits furthest left of the health bar.
-- Blizzard puts the raid mark (the unit frame's RaidTargetFrame) against the
-- bar's left edge and the buff list (AurasFrame.BuffListFrame, up to two
-- icons growing leftwards) left of that. The icon follows the buff list
-- while it holds icons, else the raid mark while one is set, else the bar.
-- Nothing is measured: the mark is followed by OnShow/OnHide, the buff list
-- by its child count after each Layout (released icons get SetParent(nil)).
-- All hooks are HookScript/hooksecurefunc and only move this file's icon.

local _, ns = ...
local IsSecret = ns.IsSecret

local ICON_SIZE = 22
local ICON_ATLAS = "QuestNormal" -- the yellow exclamation mark

local LineType = Enum.TooltipDataLineType

local plateOfUnit = {} -- nameplate unit token -> nameplate frame, while shown
local indicators = {} -- nameplate frame -> icon frame, created on first use
local hooked = setmetatable({}, { __mode = "k" }) -- Blizzard frames already hooked

-- What the unit's tooltip says about my quests:
--   true   it lists an objective I have not finished
--   false  it only lists objectives I have finished
--   nil    it lists no objectives of mine
local function ObjectiveState(unit)
	local data = C_TooltipInfo.GetUnit(unit)
	if not data or not data.lines then
		return nil
	end
	local me = UnitName("player")
	local mine, state = true, nil
	for _, line in ipairs(data.lines) do
		if line.type == LineType.QuestTitle then
			mine = true
		elseif line.type == LineType.QuestPlayer then
			-- In a group every member's progress is listed under their name.
			mine = line.leftText == me
		elseif line.type == LineType.QuestObjective and mine then
			if not line.completed then
				return true
			end
			state = false
		end
	end
	return state
end

local function Check(unit)
	if not UnitCanAttack("player", unit) then
		return false
	end
	local state = ObjectiveState(unit)
	if state == nil then
		-- No progress to go by: ask the game whether the unit matters at all.
		state = C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	end
	return state == true
end

-- Unit information can be restricted for addons; treat that as "no".
local function IsQuestTarget(unit)
	local ok, result = pcall(Check, unit)
	return ok and result
end

-- Shown and holding aura icons; false when that cannot be read.
local function HasIcons(list)
	local okShown, shown = pcall(list.IsShown, list)
	local okCount, count = pcall(list.GetNumChildren, list)
	return okShown and okCount and not IsSecret(shown) and not IsSecret(count)
		and shown == true and type(count) == "number" and count > 0
end

local function IsShownSafe(frame)
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and not IsSecret(shown) and shown == true
end

-- Hook a Blizzard frame once: scripts = { OnShow = fn, ... }, methods =
-- { Layout = fn, ... }; each fn runs after Blizzard's own.
-- Guarded: should Forever refuse a hook, the icon just stays where it was.
local function Hook(frame, scripts, methods)
	if hooked[frame] ~= nil then
		return
	end
	hooked[frame] = pcall(function()
		for script, fn in pairs(scripts) do
			frame:HookScript(script, fn)
		end
		for method, fn in pairs(methods) do
			hooksecurefunc(frame, method, fn)
		end
	end)
end

local function GetIndicator(plate)
	local indicator = indicators[plate]
	if not indicator then
		indicator = CreateFrame("Frame", nil, plate)
		indicator:SetSize(ICON_SIZE, ICON_SIZE)
		indicator:SetFrameLevel(plate:GetFrameLevel() + 10)
		local icon = indicator:CreateTexture(nil, "OVERLAY")
		icon:SetAllPoints()
		icon:SetAtlas(ICON_ATLAS)
		indicators[plate] = indicator
	end
	-- The default health bar is recreated whenever the plate is reused, and
	-- is absent when another addon draws the plate, so anchor every time.
	local unitFrame = plate.UnitFrame
	local bar = unitFrame and unitFrame.HealthBarsContainer
	local mark = unitFrame and unitFrame.RaidTargetFrame
	local auras = unitFrame and unitFrame.AurasFrame
	local buffs = auras and auras.BuffListFrame
	-- The "!" is narrow in a square texture: the offsets pull its clear
	-- edge in over the buffs, the mark or the bar's border.
	local function Anchor()
		indicator:ClearAllPoints()
		if buffs and HasIcons(buffs) then
			indicator:SetPoint("RIGHT", buffs, "LEFT", 4, 0)
		elseif mark and indicator.marked then
			indicator:SetPoint("RIGHT", mark, "LEFT", 6, 0)
		elseif bar then
			indicator:SetPoint("RIGHT", bar, "LEFT", 4, 0)
		else
			indicator:SetPoint("RIGHT", plate, "LEFT", 0, 0)
		end
	end
	local function Reanchor(marked)
		local i = indicators[plate]
		if i and i.Anchor then
			if marked ~= nil then
				i.marked = marked
			end
			i.Anchor()
		end
	end
	if mark then
		-- The mark's state comes from the script that fired, not IsShown.
		Hook(mark, {
			OnShow = function() Reanchor(true) end,
			OnHide = function() Reanchor(false) end,
		}, {})
	end
	if buffs then
		-- Layout runs after every refresh of the list's icons.
		local function follow() Reanchor() end
		Hook(buffs, { OnShow = follow, OnHide = follow }, { Layout = follow })
	end
	indicator.marked = mark ~= nil and IsShownSafe(mark)
	indicator.Anchor = Anchor
	Anchor()
	return indicator
end

local function Update(unit)
	local plate = plateOfUnit[unit]
	if not plate then
		return
	end
	if IsQuestTarget(unit) then
		GetIndicator(plate):Show()
	elseif indicators[plate] then
		indicators[plate]:Hide()
	end
end

-- Quest events arrive in bursts; redo all visible plates once they settle.
local refreshPending = false
local function RequestRefresh()
	if refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(0.2, function()
		refreshPending = false
		for unit in pairs(plateOfUnit) do
			Update(unit)
		end
	end)
end

local function HideAll()
	for _, indicator in pairs(indicators) do
		indicator:Hide()
	end
end

local feature = ns.Feature({
	key = "quest",
	title = "Quest enemies",
	tooltip = "Marks the nameplates of enemies you still need for a quest.",
	defaults = { enabled = true },
	events = {
		"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
		"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
	},
	unitEvents = { { "UNIT_QUEST_LOG_CHANGED", "player" } },
})

-- Plates already in view when it is switched on.
function feature.Start()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.UnitFrame and plate.UnitFrame.unit
		if type(unit) == "string" and not IsSecret(unit) and unit:find("^nameplate") then
			plateOfUnit[unit] = plate
		end
	end
	RequestRefresh()
end

function feature.Stop()
	wipe(plateOfUnit)
	HideAll()
end

function feature.OnEvent(event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		plateOfUnit[unit] = C_NamePlate.GetNamePlateForUnit(unit)
		Update(unit)
		-- Quest lines can be missing the moment a unit comes into view.
		RequestRefresh()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = plateOfUnit[unit]
		plateOfUnit[unit] = nil
		if plate and indicators[plate] then
			indicators[plate]:Hide()
		end
	else
		RequestRefresh()
	end
end
