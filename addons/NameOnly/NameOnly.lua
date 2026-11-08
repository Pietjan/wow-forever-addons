-- NameOnly: friendly player nameplates show just the name, in the font,
-- size and position of your choosing.
--
-- Forever has a "show only name" mode for friendly player nameplates
-- (Options > Gameplay > Nameplates): it drops the health bar, cast bar,
-- auras and level, and leaves the name standing where the bar would be.
-- On first login this addon turns that mode on, together with friendly
-- player nameplates and class-coloured names, and from then on restyles
-- the name on every such plate: font, size, outline, shadow and an offset
-- from where Blizzard puts it. The raid marker stays, as it does in
-- Blizzard's mode, unless you turn it off here.
--
-- Nameplate unit frames are pooled and reused. Blizzard sets the name's
-- font up in ApplyFrameOptions each time a frame is handed a unit, and
-- lays the name out in UpdateAnchors, which also runs at the end of
-- ApplyFrameOptions and whenever the mode changes. UpdateAnchors is hooked
-- on each unit frame the first time it is seen, so the style is put back
-- whenever Blizzard redoes its own, and left alone on plates that are not
-- in name-only mode (enemies, NPCs, your own).

local ADDON_NAME = ...

local DEFAULTS = {
	font = "friz",
	size = 14,
	outline = "thin", -- "none", "thin" or "thick"
	shadow = true,
	x = 0, -- offset from where Blizzard puts the name
	y = 0,
	raidIcon = true, -- keep the raid marker above the name
}

local FONTS = {
	friz = { STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", "Friz Quadrata, the game's own" },
	arial = { "Fonts\\ARIALN.TTF", "Arial Narrow" },
	skurri = { "Fonts\\skurri.ttf", "Skurri" },
	morpheus = { "Fonts\\MORPHEUS.ttf", "Morpheus" },
}
local FONT_ORDER = { "friz", "arial", "skurri", "morpheus" }
local OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }

-- What Blizzard's name-only mode needs switched on. Applied once, on the
-- first login with the addon, and again on /nameonly setup.
local CVARS = {
	{ "nameplateShowFriendlyPlayers", "1", "friendly player nameplates" },
	{ "nameplateShowOnlyNameForFriendlyPlayerUnits", "1", "only the name on them" },
	{ "nameplateUseClassColorForFriendlyPlayerUnitNames", "1", "class-coloured names" },
}

local db

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffNameOnly|r " .. text)
end

-- Style the name of one nameplate unit frame, or hand it back to Blizzard
-- when the plate is not in name-only mode.
local function Style(unitFrame)
	local name = unitFrame.name
	if not name then
		return
	end
	if not (unitFrame.IsShowOnlyName and unitFrame:IsShowOnlyName()) then
		if unitFrame.nameOnlyStyled then
			-- Blizzard has already re-anchored the name; put its font back
			-- too, shadow included, by reapplying the font object it set.
			unitFrame.nameOnlyStyled = nil
			local object = name:GetFontObject()
			if object then
				name:SetFontObject(object)
			end
		end
		return
	end
	unitFrame.nameOnlyStyled = true

	local font = FONTS[db.font] or FONTS.friz
	name:SetFont(font[1], db.size, OUTLINES[db.outline] or OUTLINES.thin)
	if db.shadow then
		name:SetShadowColor(0, 0, 0, 1)
		name:SetShadowOffset(1, -1)
	else
		name:SetShadowOffset(0, 0)
	end
	name:SetJustifyH("CENTER")

	-- Blizzard anchors the name either across the (hidden) health bar or
	-- along its top edge, depending on the nameplate style. Keep that
	-- reference and add the offset, on a single point so the text takes
	-- its natural width.
	local container = unitFrame.HealthBarsContainer
	local point = name:GetPoint(1)
	name:ClearAllPoints()
	if point == "LEFT" or point == "RIGHT" or point == "CENTER" then
		name:SetPoint("CENTER", container, "CENTER", db.x, db.y)
	else
		name:SetPoint("BOTTOM", container, "TOP", db.x, 2 + db.y)
	end
end

local function StyleRaidIcon(raidTargetFrame)
	if db.raidIcon then
		return
	end
	if raidTargetFrame.IsShowOnlyName and raidTargetFrame:IsShowOnlyName() then
		raidTargetFrame:Hide()
	end
end

local function Hook(unitFrame)
	if unitFrame.nameOnlyHooked then
		return
	end
	unitFrame.nameOnlyHooked = true
	if type(unitFrame.UpdateAnchors) == "function" then
		hooksecurefunc(unitFrame, "UpdateAnchors", Style)
	end
	local raid = unitFrame.RaidTargetFrame
	if raid and type(raid.UpdateShownState) == "function" then
		hooksecurefunc(raid, "UpdateShownState", StyleRaidIcon)
	end
end

local function StyleAll()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unitFrame = plate.UnitFrame
		if unitFrame then
			Hook(unitFrame)
			Style(unitFrame)
			local raid = unitFrame.RaidTargetFrame
			if raid and raid.UpdateShownState then
				pcall(raid.UpdateShownState, raid)
			end
		end
	end
end

local function Setup()
	if InCombatLockdown() then
		Print("Nameplate options cannot be changed in combat; try /nameonly setup afterwards.")
		return
	end
	local changed = {}
	for _, cvar in ipairs(CVARS) do
		if GetCVar(cvar[1]) ~= cvar[2] then
			SetCVar(cvar[1], cvar[2])
			changed[#changed + 1] = cvar[3]
		end
	end
	if #changed > 0 then
		Print("Turned on " .. table.concat(changed, ", ") .. ".")
	else
		Print("Friendly player nameplates, name-only mode and class colours are already on.")
	end
end

-- Slash command ------------------------------------------------------------

local function Status()
	local font = FONTS[db.font] or FONTS.friz
	Print(("font %s (%s), size %d, outline %s, shadow %s, offset %d %d, raid marker %s"):format(
		db.font, font[2], db.size, db.outline, db.shadow and "on" or "off", db.x, db.y, db.raidIcon and "shown" or "hidden"))
end

local function Usage()
	Status()
	Print("/nameonly size 8-32 | font friz, arial, skurri or morpheus | outline none, thin or thick")
	Print("/nameonly shadow on|off | x -50..50 | y -50..50 | raidicon on|off | setup | reset")
	Print("Turn friendly player nameplates themselves on or off under Options > Gameplay > Nameplates.")
end

local function OnOff(value)
	if value == "on" or value == "1" or value == "yes" then
		return true
	elseif value == "off" or value == "0" or value == "no" then
		return false
	end
end

local function Number(value, min, max)
	local n = tonumber(value)
	if n and n >= min and n <= max then
		return math.floor(n + 0.5)
	end
end

local function Command(msg)
	local cmd, arg = msg:match("^%s*(%S+)%s*(.-)%s*$")
	cmd = cmd and cmd:lower()
	arg = arg and arg:lower() or ""
	if cmd == "size" then
		local n = Number(arg, 8, 32)
		if not n then
			return Print("Size is a number from 8 to 32.")
		end
		db.size = n
	elseif cmd == "font" then
		if not FONTS[arg] then
			return Print("Fonts: " .. table.concat(FONT_ORDER, ", ") .. ".")
		end
		db.font = arg
	elseif cmd == "outline" then
		if not OUTLINES[arg] then
			return Print("Outline is none, thin or thick.")
		end
		db.outline = arg
	elseif cmd == "shadow" or cmd == "raidicon" then
		local value = OnOff(arg)
		if value == nil then
			return Print(cmd .. " is on or off.")
		end
		if cmd == "shadow" then
			db.shadow = value
		else
			db.raidIcon = value
		end
	elseif cmd == "x" or cmd == "y" then
		local n = Number(arg, -50, 50)
		if not n then
			return Print(cmd .. " is a number from -50 to 50; positive moves right or up.")
		end
		db[cmd] = n
	elseif cmd == "setup" then
		return Setup()
	elseif cmd == "reset" then
		for key, value in pairs(DEFAULTS) do
			db[key] = value
		end
	else
		return Usage()
	end
	StyleAll()
	Status()
end

-- Events -------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("NAME_PLATE_UNIT_ADDED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		NameOnlyDB = NameOnlyDB or {}
		db = NameOnlyDB
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				db[key] = value
			end
		end
		SLASH_NAMEONLY1 = "/nameonly"
		SLASH_NAMEONLY2 = "/nonly"
		SlashCmdList.NAMEONLY = Command
	elseif event == "PLAYER_LOGIN" then
		if not db.setupDone then
			db.setupDone = true
			Setup()
			Print("Friendly player names are now nameplates with just the name. /nameonly to style them.")
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- Blizzard's driver registered first, so the plate already has its
		-- unit frame set up by the time this fires.
		local plate = C_NamePlate.GetNamePlateForUnit(arg1)
		local unitFrame = plate and plate.UnitFrame
		if unitFrame then
			Hook(unitFrame)
			Style(unitFrame)
		end
	end
end)
