-- No level box (/fplates level): hides the box with the unit's level that
-- Forever puts right of a nameplate's health bar. Off by default.
--
-- Blizzard shows or hides that box (the unit frame's PlayerLevelDiffFrame)
-- in CompactUnitFrame_UpdatePlayerLevelDiff, whenever a plate gets a unit
-- or the unit's level changes. That function is post-hooked: once Blizzard
-- has shown the box, this hides it again. Only Hide and Show are called on
-- it; no Blizzard function is called and no Blizzard field is written (see
-- Core.lua). Blizzard's layout still keeps the box's room free beside the
-- bar, as it decides that from its own rule, not from the box being shown.
--
-- Switched off, the box comes back on every plate this hid, where
-- Blizzard's own rule (the box's ShouldDisplay) says it belongs.

local _, ns = ...
local IsSecret = ns.IsSecret

local feature
local hidden = setmetatable({}, { __mode = "k" }) -- unit frames whose box this hid

local function IsNamePlate(frame)
	local unit = frame.unit
	return type(unit) == "string" and not IsSecret(unit) and unit:find("^nameplate") ~= nil
end

local function HideBox(frame)
	local box = frame.PlayerLevelDiffFrame
	if not box then
		return
	end
	box:Hide()
	hidden[frame] = true
end

-- After each CompactUnitFrame_UpdatePlayerLevelDiff. Party and raid frames
-- go through there too, and so do nameplates addons may not touch
-- (forbidden): only nameplates that are not forbidden are this feature's.
local function OnUpdateLevel(frame)
	if not (feature.db and feature.db.enabled) or frame:IsForbidden() or not IsNamePlate(frame) then
		return
	end
	HideBox(frame)
end

feature = ns.Feature({
	key = "level",
	title = "No level box",
	tooltip = "Hides the box with the unit's level beside the health bar of every nameplate.",
	defaults = { enabled = false },
})

function feature.OnLogin()
	if type(CompactUnitFrame_UpdatePlayerLevelDiff) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdatePlayerLevelDiff", OnUpdateLevel)
	end
end

function feature.Start()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local frame = plate.UnitFrame
		if frame and not frame:IsForbidden() and IsNamePlate(frame) then
			HideBox(frame)
		end
	end
end

function feature.Stop()
	for frame in pairs(hidden) do
		hidden[frame] = nil
		local box = frame.PlayerLevelDiffFrame
		local ok, display = pcall(box.ShouldDisplay, box, frame.unit)
		if ok and display == true then
			box:Show()
		end
	end
end

function feature.OnEvent()
end
