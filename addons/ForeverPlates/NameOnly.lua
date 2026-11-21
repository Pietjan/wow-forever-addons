-- Friendly names (/fplates names): friendly player nameplates show just the
-- name, in the font, size and position of your choosing.
--
-- Forever has a "show only name" mode for friendly player nameplates
-- (Options > Gameplay > Nameplates): it drops the health bar, cast bar,
-- auras and level, and leaves the name standing where the bar would be.
-- While this is on, every login sets the game options that go with it:
-- that mode, friendly player nameplates, class-coloured names, names on
-- every plate, the nameplate range at Forever's ceiling of 41 yards, and
-- the floating names of friendly players and their pets off, since the
-- plates replace them within range and nothing is legible beyond it.
-- Switching it off leaves those options as they are. It then restyles the
-- name on every such plate: font, size, outline, shadow and an offset from
-- where Blizzard puts it. The raid marker stays, as it does in Blizzard's
-- mode, unless you turn it off here. Forever characters have a first name
-- and a surname; the surname can be left off these plates.
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
-- in name-only mode (enemies, NPCs, your own). Switched off, the font and
-- full name go back on every plate at once; the position goes back when
-- Blizzard next lays the plate out (a new unit on it).

local _, ns = ...
local Print, IsSecret = ns.Print, ns.IsSecret

-- "default" and size 0 mean Blizzard's own nameplate font, size and
-- outline, so out of the box only the position is the addon's.
local DEFAULTS = {
	enabled = true,
	font = "default",
	size = 0,
	outline = "default", -- "none", "thin" or "thick"
	shadow = false,
	x = 0, -- offset from where Blizzard puts the name
	y = 0,
	raidIcon = true, -- keep the raid marker above the name
	firstName = false, -- leave the surname off the name
}

local FONTS = {
	friz = { STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", "Friz Quadrata, the game's own" },
	arial = { "Fonts\\ARIALN.TTF", "Arial Narrow" },
	skurri = { "Fonts\\skurri.ttf", "Skurri" },
	morpheus = { "Fonts\\MORPHEUS.ttf", "Morpheus" },
}
local FONT_ORDER = { "default", "friz", "arial", "skurri", "morpheus" }
local OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }

-- The game options the feature owns, applied at every login and on
-- /fplates names setup, so a settings reset or another character does not
-- undo them. Nameplate range is capped at 41 on Forever; higher is clamped.
local CVARS = {
	{ "nameplateShowFriendlyPlayers", "1", "friendly player nameplates" },
	{ "nameplateShowOnlyNameForFriendlyPlayerUnits", "1", "only the name on them" },
	{ "nameplateUseClassColorForFriendlyPlayerUnitNames", "1", "class-coloured names" },
	{ "nameplateForceShowUnitName", "1", "a name on every nameplate" },
	{ "nameplateMaxDistance", "41", "nameplates out to 41 yards" },
	{ "UnitNameFriendlyPlayerName", "0", "floating names of friendly players off" },
	{ "UnitNameFriendlyMinionName", "0", "floating names of their pets off" },
}

local feature
local db

local function On()
	return db and db.enabled
end

-- Forever characters have a first name and a surname. UnitName returns
-- the two apart, and Blizzard's CompactUnitFrame_UpdateName writes both
-- on the plate, joined; this writes the first one back over them. Text
-- set on the font string touches none of Blizzard's own fields. A secret
-- name (by the API's notes a player's is not) can only be handed on, not
-- tested.
local function ShortenName(unitFrame)
	local unit = unitFrame.unit
	if not unit then
		return
	end
	local first = UnitName(unit)
	if IsSecret(first) or first then
		unitFrame.name:SetText(first)
		unitFrame.nameOnlyShortened = true
	end
end

-- Put the full name back on a plate whose name was shortened, as Blizzard
-- would write it. Blizzard only rewrites the name on its own occasions
-- (a new unit, the mouse over the plate), not when the surname is turned
-- back on here or the plate leaves name-only mode.
local function RestoreName(unitFrame)
	if not unitFrame.nameOnlyShortened then
		return
	end
	unitFrame.nameOnlyShortened = nil
	local unit = unitFrame.unit
	if unit then
		local ok, full = pcall(GetUnitName, unit, true)
		if ok and (IsSecret(full) or full) then
			unitFrame.name:SetText(full)
		end
	end
end

-- After each CompactUnitFrame_UpdateName. Raid and party frames come
-- through there too, and so do nameplates addons may not touch
-- (forbidden, on which any other call is an error): only the plates this
-- feature has hooked are its own.
local function OnUpdateName(frame)
	if not On() or frame:IsForbidden() or not frame.nameOnlyHooked then
		return
	end
	frame.nameOnlyShortened = nil -- Blizzard has just written the full name
	if db.firstName and frame.IsShowOnlyName and frame:IsShowOnlyName() then
		ShortenName(frame)
	end
end

-- Give a plate its full name and Blizzard's font back.
local function Unstyle(unitFrame)
	RestoreName(unitFrame)
	if unitFrame.nameOnlyStyled then
		-- Blizzard has already re-anchored the name, or will when it next
		-- lays the plate out; put its font back too, shadow included, by
		-- reapplying the font object it set.
		unitFrame.nameOnlyStyled = nil
		local name = unitFrame.name
		local ok, object = pcall(name.GetFontObject, name)
		if ok and object then
			name:SetFontObject(object)
		end
	end
end

-- Style the name of one nameplate unit frame, or hand it back to Blizzard
-- when the plate is not in name-only mode.
local function Style(unitFrame)
	if not On() then
		return
	end
	local name = unitFrame.name
	if not name then
		return
	end
	if not (unitFrame.IsShowOnlyName and unitFrame:IsShowOnlyName()) then
		Unstyle(unitFrame)
		return
	end
	unitFrame.nameOnlyStyled = true

	-- The plate may have entered name-only mode after Blizzard last wrote
	-- its name, and the setting may just have changed.
	if db.firstName then
		ShortenName(unitFrame)
	else
		RestoreName(unitFrame)
	end

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
	if not On() or db.raidIcon then
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
		Print("Game options cannot be changed in combat; try /fplates names setup afterwards.")
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
		Print("All game options already as Friendly names wants them.")
	end
	return true
end

-- The live values of every option the feature owns, for checking that
-- they took and stayed.
local function PrintCVars()
	for _, cvar in ipairs(CVARS) do
		local current = GetCVar(cvar[1])
		local same = tonumber(current) and tonumber(cvar[2]) and tonumber(current) == tonumber(cvar[2]) or current == cvar[2]
		Print(("%s%s = %s (wanted %s)"):format(same and "" or "|cffff8080", cvar[1], tostring(current), cvar[2]))
	end
end

-- Slash command ------------------------------------------------------------

local function Status()
	local font = FONTS[db.font] and (db.font .. " (" .. FONTS[db.font][2] .. ")") or "default"
	Print(("Friendly names %s: font %s, size %s, outline %s, shadow %s, offset %d %d, raid marker %s, surname %s"):format(
		db.enabled and "on" or "off", font, db.size > 0 and tostring(db.size) or "default", db.outline,
		db.shadow and "on" or "off", db.x, db.y, db.raidIcon and "shown" or "hidden", db.firstName and "hidden" or "shown"))
end

local function Usage()
	Status()
	Print("/fplates names on|off | size 8-32 | font friz, arial, skurri or morpheus | outline none, thin or thick")
	Print("Size, font and outline also take 'default' for Blizzard's own.")
	Print("/fplates names shadow on|off | x -50..50 | y -50..50 | raidicon on|off | firstname on|off | setup | cvars | reset")
	Print("While on, the nameplate and floating-name options it needs are set at every login; setup reapplies them now.")
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
	elseif cmd == "shadow" or cmd == "raidicon" or cmd == "firstname" then
		local value = ns.OnOff(arg)
		if value == nil then
			return Print(cmd .. " is on or off.")
		end
		if cmd == "shadow" then
			db.shadow = value
		elseif cmd == "raidicon" then
			db.raidIcon = value
		else
			db.firstName = value
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
			if key ~= "enabled" then
				db[key] = value
			end
		end
	else
		return Usage()
	end
	StyleAll()
	Status()
end

------------------------------------------------------------------------------
-- Its page in the options window: the settings of the slash command as
-- check boxes, sliders and dropdowns.
------------------------------------------------------------------------------

local function Options(page, ui)
	local function Styled(key)
		return function(value)
			db[key] = value
			StyleAll()
		end
	end
	local OWN = "the game's own"
	local fonts = { { "default", "The game's own" } }
	for _, key in ipairs(FONT_ORDER) do
		if FONTS[key] then
			fonts[#fonts + 1] = { key, FONTS[key][2] }
		end
	end
	ui.Dropdown("font", "Font", "The font of friendly players' names on their nameplates.", fonts, nil, nil, Styled("font"))
	-- Size 0 is the game's own size: the slider's left end.
	ui.Slider("size", "Size", "All the way left for the game's own size.", 7, 32, 1,
		function(value) return value < 8 and OWN or ("%d"):format(value) end, 7,
		function() return db.size > 0 and db.size or 7 end,
		function(value)
			db.size = value >= 8 and value or 0
			StyleAll()
		end)
	ui.Dropdown("outline", "Outline", nil, {
		{ "default", "The game's own" }, { "none", "None" }, { "thin", "Thin" }, { "thick", "Thick" },
	}, nil, nil, Styled("outline"))
	ui.Checkbox("shadow", "Shadow", nil, nil, nil, Styled("shadow"))
	local function Offset(value)
		return ("%d"):format(value)
	end
	ui.Slider("x", "Sideways", "Moves the name from where the game puts it; positive is to the right.", -50, 50, 1, Offset, nil, nil, Styled("x"))
	ui.Slider("y", "Up or down", "Moves the name from where the game puts it; positive is up.", -50, 50, 1, Offset, nil, nil, Styled("y"))
	ui.Checkbox("raidIcon", "Raid marker above the name", nil, nil, nil, Styled("raidIcon"))
	ui.Checkbox("firstName", "First name only", "Leaves the surname off friendly players' names on their nameplates.", nil, nil, Styled("firstName"))
end

feature = ns.Feature({
	key = "names",
	title = "Friendly names",
	tooltip = "Friendly player nameplates show just the name: your font, size and position. While on, sets the game's nameplate options for it at every login.",
	defaults = DEFAULTS,
	events = { "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED" },
	Command = Command,
	Options = Options,
})

function feature.OnLoad()
	db = feature.db
end

function feature.OnLogin()
	if type(CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", OnUpdateName)
	end
end

function feature.Start()
	if not InCombatLockdown() then
		Setup(true) -- quiet unless something had to change
	end
	StyleAll()
end

function feature.Stop()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unitFrame = plate.UnitFrame
		if unitFrame and unitFrame.nameOnlyHooked then
			Unstyle(unitFrame)
			-- A raid marker this hid: Blizzard's own rule decides again.
			local raid = unitFrame.RaidTargetFrame
			if raid and raid.UpdateShownState then
				pcall(raid.UpdateShownState, raid)
			end
		end
	end
end

function feature.OnEvent(event, unit)
	if event == "PLAYER_ENTERING_WORLD" then
		-- Per-character options can load after PLAYER_LOGIN and undo what
		-- was set there; apply again once the world is up (harmless when
		-- nothing differs).
		if not InCombatLockdown() then
			Setup(true)
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- Blizzard's driver registered first, so the plate already has its
		-- unit frame set up by the time this fires.
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		local unitFrame = plate and plate.UnitFrame
		if unitFrame then
			Hook(unitFrame) -- too late for this plate's own UpdateAnchors, hence the call below
			Style(unitFrame)
		end
	end
end
