-- NameOnly: friendly player nameplates show just the name, in the font,
-- size and position of your choosing.
--
-- Forever has a "show only name" mode for friendly player nameplates
-- (Options > Gameplay > Nameplates): it drops the health bar, cast bar,
-- auras and level, and leaves the name standing where the bar would be.
-- At every login this addon sets the game options that go with it: that
-- mode, friendly player nameplates, class-coloured names, names on every
-- plate, the nameplate range at Forever's ceiling of 41 yards, and the
-- floating names of friendly players and their pets off, since the plates
-- replace them within range and nothing is legible beyond it. It then
-- restyles the name on every such plate: font, size, outline, shadow and
-- an offset from where Blizzard puts it. The raid marker stays, as it
-- does in Blizzard's mode, unless you turn it off here.
--
-- NPC nameplates and NPC floating names are left to the game's own
-- options. (An NPC name-only mode was tried and dropped: Forever shows
-- some neutral guards' floating names whatever the options say, and the
-- forced mode needed care, as a value an addon writes into Blizzard's
-- frames taints Blizzard's code that reads it, and on Forever addon code
-- may not measure nameplate regions, which Blizzard's layout does.)
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
}

local FONTS = {
	friz = { STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", "Friz Quadrata, the game's own" },
	arial = { "Fonts\\ARIALN.TTF", "Arial Narrow" },
	skurri = { "Fonts\\skurri.ttf", "Skurri" },
	morpheus = { "Fonts\\MORPHEUS.ttf", "Morpheus" },
}
local FONT_ORDER = { "default", "friz", "arial", "skurri", "morpheus" }
local OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local VERSION = 3 -- bumped when saved settings need migrating

-- The game options the addon owns, applied at every login and on
-- /nameonly setup, so a settings reset or another character does not undo
-- them. Nameplate range is capped at 41 on Forever; higher is clamped.
local CVARS = {
	{ "nameplateShowFriendlyPlayers", "1", "friendly player nameplates" },
	{ "nameplateShowOnlyNameForFriendlyPlayerUnits", "1", "only the name on them" },
	{ "nameplateUseClassColorForFriendlyPlayerUnitNames", "1", "class-coloured names" },
	{ "nameplateForceShowUnitName", "1", "a name on every nameplate" },
	{ "nameplateMaxDistance", "41", "nameplates out to 41 yards" },
	{ "UnitNameFriendlyPlayerName", "0", "floating names of friendly players off" },
	{ "UnitNameFriendlyMinionName", "0", "floating names of their pets off" },
}
-- Options an earlier version owned and this one leaves to the game; put
-- back to their defaults once when upgrading.
local RELEASED_CVARS = {
	"nameplateShowFriendlyNpcs", "UnitNameNPC", "UnitNameFriendlySpecialNPCName",
	"UnitNameHostleNPC", "UnitNameInteractiveNPC",
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

-- Set one game option when it differs; true when it did.
local function Apply(cvar)
	local current, wanted = GetCVar(cvar[1]), cvar[2]
	if tonumber(current) and tonumber(wanted) and tonumber(current) == tonumber(wanted) then
		return false
	elseif current == wanted then
		return false
	end
	SetCVar(cvar[1], wanted)
	return true
end

local function Setup(quiet)
	if InCombatLockdown() then
		Print("Game options cannot be changed in combat; try /nameonly setup afterwards.")
		return false
	end
	local changed = {}
	for _, cvar in ipairs(CVARS) do
		if Apply(cvar) then
			changed[#changed + 1] = cvar[3]
		end
	end
	if #changed > 0 then
		Print("Set " .. table.concat(changed, ", ") .. ".")
	elseif not quiet then
		Print("All game options already as the addon wants them.")
	end
	return true
end

-- The live values of every option the addon owns, for checking that they
-- took and stayed.
local function PrintCVars()
	for _, cvar in ipairs(CVARS) do
		local current = GetCVar(cvar[1])
		local same = tonumber(current) and tonumber(cvar[2]) and tonumber(current) == tonumber(cvar[2]) or current == cvar[2]
		Print(("%s%s = %s (addon wants %s)"):format(same and "" or "|cffff8080", cvar[1], tostring(current), cvar[2]))
	end
end

-- Hand options an earlier version owned back to the game, at their defaults.
local function ReleaseCVars()
	for _, name in ipairs(RELEASED_CVARS) do
		local default = GetCVarDefault(name)
		if default then
			SetCVar(name, default)
		end
	end
	Print("NPC nameplate and NPC name options are back to the game's defaults.")
end

-- Slash command ------------------------------------------------------------

local function Status()
	local font = FONTS[db.font] and (db.font .. " (" .. FONTS[db.font][2] .. ")") or "default"
	Print(("font %s, size %s, outline %s, shadow %s, offset %d %d, raid marker %s"):format(
		font, db.size > 0 and tostring(db.size) or "default", db.outline, db.shadow and "on" or "off",
		db.x, db.y, db.raidIcon and "shown" or "hidden"))
end

local function Usage()
	Status()
	Print("/nameonly size 8-32 | font friz, arial, skurri or morpheus | outline none, thin or thick")
	Print("Each of those also takes 'default' for Blizzard's own.")
	Print("/nameonly shadow on|off | x -50..50 | y -50..50 | raidicon on|off | setup | cvars | reset")
	Print("The addon sets the nameplate and floating-name options it needs at every login; setup reapplies them now.")
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
		Setup()
		return
	elseif cmd == "cvars" then
		return PrintCVars()
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
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
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
		db.release = (db.version or 1) < 3 -- version 2 owned the NPC options
		db.npcs = nil
		db.version = VERSION
		SLASH_NAMEONLY1 = "/nameonly"
		SLASH_NAMEONLY2 = "/nonly"
		SlashCmdList.NAMEONLY = Command
	elseif event == "PLAYER_LOGIN" then
		-- Quiet unless something had to change; the first login says it all.
		local first = not db.setupDone
		db.setupDone = true
		if db.release and not InCombatLockdown() then
			db.release = nil
			ReleaseCVars()
		end
		Setup(true)
		if first then
			Print("Friendly player names are now nameplates with just the name. /nameonly to style them.")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Per-character options can load after PLAYER_LOGIN and undo what
		-- was set there; apply again once the world is up (harmless when
		-- nothing differs).
		if not InCombatLockdown() then
			Setup(true)
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- Blizzard's driver registered first, so the plate already has its
		-- unit frame set up by the time this fires.
		local plate = C_NamePlate.GetNamePlateForUnit(arg1)
		local unitFrame = plate and plate.UnitFrame
		if unitFrame then
			Hook(unitFrame) -- too late for this plate's own UpdateAnchors, hence the call below
			Style(unitFrame)
		end
	end
end)
