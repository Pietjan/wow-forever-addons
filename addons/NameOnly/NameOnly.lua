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
-- Blizzard only grants name-only mode to players. With /nameonly npcs on,
-- friendly NPC nameplates are switched on as well and the addon puts them
-- in the same mode itself, by setting the flag Blizzard's components read
-- and hiding the level, each time Blizzard re-evaluates the plate.
--
-- Nameplate unit frames are pooled and reused. Blizzard sets the name's
-- font up in ApplyFrameOptions each time a frame is handed a unit, and
-- lays the name out in UpdateAnchors, which also runs at the end of
-- ApplyFrameOptions and whenever the mode changes. UpdateAnchors is hooked
-- on each unit frame the first time it is seen, so the style is put back
-- whenever Blizzard redoes its own, and left alone on plates that are not
-- in name-only mode (enemies, NPCs, your own).

local ADDON_NAME = ...

-- "default" and size 0 mean Blizzard's own nameplate font, size and
-- outline, so out of the box only the position is the addon's.
local DEFAULTS = {
	font = "default",
	size = 0,
	outline = "default", -- "none", "thin" or "thick"
	shadow = false,
	x = 0, -- offset from where Blizzard puts the name
	y = 0,
	raidIcon = true, -- keep the raid marker above the name
	npcs = false, -- friendly NPC nameplates too, name only
}

local FONTS = {
	friz = { STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", "Friz Quadrata, the game's own" },
	arial = { "Fonts\\ARIALN.TTF", "Arial Narrow" },
	skurri = { "Fonts\\skurri.ttf", "Skurri" },
	morpheus = { "Fonts\\MORPHEUS.ttf", "Morpheus" },
}
local FONT_ORDER = { "default", "friz", "arial", "skurri", "morpheus" }
local OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local VERSION = 2 -- bumped when saved settings need migrating

-- What Blizzard's name-only mode needs switched on. Applied once, on the
-- first login with the addon, and again on /nameonly setup.
local CVARS = {
	{ "nameplateShowFriendlyPlayers", "1", "friendly player nameplates" },
	{ "nameplateShowOnlyNameForFriendlyPlayerUnits", "1", "only the name on them" },
	{ "nameplateUseClassColorForFriendlyPlayerUnitNames", "1", "class-coloured names" },
}
local NPC_CVAR = "nameplateShowFriendlyNpcs"

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
			local ok, object = pcall(name.GetFontObject, name)
			if ok and object then
				name:SetFontObject(object)
			end
		end
		return
	end
	unitFrame.nameOnlyStyled = true

	-- Blizzard's font is already on the name when this runs; only replace
	-- it when a face, size or outline has been chosen. Whatever is not
	-- chosen is filled in the way Blizzard would: Friz Quadrata, the
	-- health bar text height, and an outline only for styles that put the
	-- name inside the bar.
	local options = NamePlateSetupOptions or {}
	local styles = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES or {}
	if db.font ~= "default" or db.size > 0 or db.outline ~= "default" then
		local face = FONTS[db.font] and FONTS[db.font][1] or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
		local size = db.size > 0 and db.size or options.healthBarFontHeight or 14
		local flags = OUTLINES[db.outline]
		if not flags then
			local style = options.unitNameAnchorStyle
			local outlined = style == styles.InsideHealthBar or style == styles.CenteredAboveHealthBar
				or (style == styles.AboveHealthBar and options.useOutlinedFontWhenAboveHealthBar)
			flags = outlined and "OUTLINE" or ""
		end
		name:SetFont(face, size, flags)
	end
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
	-- its natural width. Nameplate regions cannot be measured by addons on
	-- Forever (GetPoint and friends are refused), so the style is read from
	-- Blizzard's setup table rather than from the name's current anchors.
	local container = unitFrame.HealthBarsContainer
	local inside = options.unitNameAnchorStyle == styles.InsideHealthBar
	name:ClearAllPoints()
	if inside then
		name:SetPoint("CENTER", container, "CENTER", db.x, db.y)
	else
		name:SetPoint("BOTTOM", container, "TOP", db.x, 2 + db.y)
	end
end

-- Blizzard's UpdateShowOnlyName grants the mode to friendly players only.
-- Runs after it: for a friendly NPC, when asked, do what it would have
-- done for a player. Blizzard's own next evaluation turns the mode off
-- again and this turns it straight back on, within the same call.
local function ForceNameOnly(unitFrame)
	local force = db.npcs and unitFrame.unit ~= nil and not unitFrame.widgetsOnlyMode
		and unitFrame.IsFriend and unitFrame:IsFriend() and not unitFrame:IsPlayer()
	if not force then
		unitFrame.nameOnlyForced = nil
		return
	end
	unitFrame.nameOnlyForced = true
	if unitFrame.showOnlyName then
		return
	end
	unitFrame.showOnlyName = true
	for _, component in ipairs({
		unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar,
		unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar,
		unitFrame.AurasFrame, unitFrame.ClassificationFrame, unitFrame.RaidTargetFrame,
	}) do
		if component and component.SetShowOnlyName then
			component:SetShowOnlyName(true)
		end
	end
	for _, level in ipairs({ unitFrame.PlayerLevelDiffFrame, unitFrame.LevelFrame }) do
		if level then
			level:Hide()
		end
	end
	if unitFrame.UpdateAnchors then
		unitFrame:UpdateAnchors() -- lays the name out for name-only; Style runs after it
	end
	if unitFrame.UpdateHitTestArea and NamePlateSetupOptions then
		unitFrame:UpdateHitTestArea(NamePlateSetupOptions)
	end
end

-- The level is re-shown by Blizzard code that does not know about the
-- forced mode; keep it hidden on those plates.
local function HideForcedLevel(levelFrame)
	local unitFrame = levelFrame:GetParent()
	if unitFrame and unitFrame.nameOnlyForced then
		levelFrame:Hide()
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
	if type(unitFrame.UpdateShowOnlyName) == "function" then
		hooksecurefunc(unitFrame, "UpdateShowOnlyName", ForceNameOnly)
	end
	for _, level in ipairs({ unitFrame.PlayerLevelDiffFrame, unitFrame.LevelFrame }) do
		if level then
			hooksecurefunc(level, "Show", HideForcedLevel)
		end
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
			if unitFrame.UpdateShowOnlyName then
				unitFrame:UpdateShowOnlyName() -- re-evaluates, and ForceNameOnly after it
			end
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
	if db.npcs and GetCVar(NPC_CVAR) ~= "1" then
		SetCVar(NPC_CVAR, "1")
		changed[#changed + 1] = "friendly NPC nameplates"
	end
	if #changed > 0 then
		Print("Turned on " .. table.concat(changed, ", ") .. ".")
	else
		Print("Friendly player nameplates, name-only mode and class colours are already on.")
	end
end

local function SetNpcs(on)
	if InCombatLockdown() then
		Print("Nameplate options cannot be changed in combat; try again afterwards.")
		return false
	end
	db.npcs = on
	SetCVar(NPC_CVAR, on and "1" or "0")
	return true
end

-- Slash command ------------------------------------------------------------

local function Status()
	local font = FONTS[db.font] and (db.font .. " (" .. FONTS[db.font][2] .. ")") or "default"
	Print(("font %s, size %s, outline %s, shadow %s, offset %d %d, raid marker %s"):format(
		font, db.size > 0 and tostring(db.size) or "default", db.outline, db.shadow and "on" or "off",
		db.x, db.y, db.raidIcon and "shown" or "hidden"))
	Print("friendly NPC nameplates " .. (db.npcs and "on, name only" or "off"))
end

local function Usage()
	Status()
	Print("/nameonly size 8-32 | font friz, arial, skurri or morpheus | outline none, thin or thick")
	Print("Each of those also takes 'default' for Blizzard's own.")
	Print("/nameonly shadow on|off | x -50..50 | y -50..50 | raidicon on|off | npcs on|off | setup | reset")
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
		local n = arg == "default" and 0 or Number(arg, 8, 32)
		if not n then
			return Print("Size is a number from 8 to 32, or default.")
		end
		db.size = n
	elseif cmd == "font" then
		if arg ~= "default" and not FONTS[arg] then
			return Print("Fonts: " .. table.concat(FONT_ORDER, ", ") .. ".")
		end
		db.font = arg
	elseif cmd == "outline" then
		if arg ~= "default" and not OUTLINES[arg] then
			return Print("Outline is none, thin, thick or default.")
		end
		db.outline = arg
	elseif cmd == "shadow" or cmd == "raidicon" or cmd == "npcs" then
		local value = OnOff(arg)
		if value == nil then
			return Print(cmd .. " is on or off.")
		end
		if cmd == "shadow" then
			db.shadow = value
		elseif cmd == "raidicon" then
			db.raidIcon = value
		elseif not SetNpcs(value) then
			return
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
			if key ~= "npcs" then
				db[key] = value
			end
		end
		if db.npcs then
			SetNpcs(false)
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
		if (db.version or 1) < 2 then
			-- Version 1 shipped with Friz 14, a thin outline and a shadow
			-- as its defaults; Blizzard's font is the default now.
			db.font, db.size, db.outline, db.shadow = DEFAULTS.font, DEFAULTS.size, DEFAULTS.outline, DEFAULTS.shadow
		end
		db.version = VERSION
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
