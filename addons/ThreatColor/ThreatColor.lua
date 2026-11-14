-- ThreatColor: the health bar of an enemy nameplate shows your threat on
-- it, green / yellow / orange / red, from the start of the fight.
--
-- Blizzard's own threat colour (Options > Nameplates, threat display) only
-- takes over once you are close to pulling, and only in a group; the rest
-- of the time the bar keeps its hostility colour, so most fights go from
-- red to a shade of red. Here, every enemy that is in combat gets a threat
-- colour, and the scale turns around with your role:
--
--   not a tank  green: no threat, yellow/orange: about to pull, red: it is on you,
--               amber: loose on another healer or damage dealer (only in a
--               group with an assigned tank)
--   tank        green: you hold it, yellow/orange: someone is catching up,
--               red: you lost it (or never had it), grey: another tank in
--               your group holds it (an off-tank or tank swap, not a loss)
--
-- These are the game's own threat states (UnitThreatSituation for others,
-- UnitThreatLeadSituation for tanks, as Blizzard uses them). Enemies out of
-- combat, players, tapped and dead units keep Blizzard's colour.
--
-- Only your own fights are coloured. An enemy that has you on no threat
-- list is coloured when it is coming for you (its target is you: a body
-- pull before the first hit) or when your pet or someone in your group is
-- on its list. An enemy that strangers are fighting keeps Blizzard's colour.
--
-- Blizzard only recolours a bar when its own colour changes, and not always
-- when an enemy drops out of combat, so a bar this addon painted is put
-- back by hand once the enemy is no longer wanted: on the unit's flag and
-- threat events, when you leave combat, and on a slow sweep for what has
-- no event.
--
-- How: CompactUnitFrame_UpdateHealthColor is post-hooked, so the colour
-- goes on right after Blizzard sets its own, whenever it does (health,
-- threat, faction updates). Only SetStatusBarColor is called: no Blizzard
-- field is written and no Blizzard function is called, since on Forever
-- either one taints the nameplate (see NameOnly).
--
-- Threat state can be secret to addon code. Then the number cannot be
-- looked at, but whether you are tanking it can be turned into a colour by
-- the game (C_CurveUtil.EvaluateColorFromBoolean), so the bar drops to two
-- colours: green and red. If even that is refused, Blizzard's colour stays.
--
-- Grey and amber are asked from the group's side: the members with an
-- assigned role, and whether the threat API says each is tanking this
-- enemy. (The enemy's own target is identity-restricted on nameplates, so
-- its role cannot be read.) Secret answers are chained through
-- C_CurveUtil.EvaluateColorFromBoolean, so the game picks the colour.

local DEFAULTS = {
	role = "auto", -- "auto", "tank" or "dps"
}

local COLORS = {
	[0] = CreateColor(0.20, 0.80, 0.20, 1), -- green
	[1] = CreateColor(1.00, 0.85, 0.00, 1), -- yellow
	[2] = CreateColor(1.00, 0.50, 0.00, 1), -- orange
	[3] = CreateColor(1.00, 0.10, 0.10, 1), -- red
}
local GREY = CreateColor(0.55, 0.55, 0.55, 1) -- tank: another tank has it
local LOOSE = CreateColor(1.00, 0.70, 0.15, 1) -- healer/damage: it is on another healer or damage dealer

local IsSecret = issecretvalue or function() return false end

local db

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff8040ThreatColor|r " .. text)
end

local function AutoTank()
	local ok, tank = pcall(function()
		return PlayerUtil and PlayerUtil.IsPlayerEffectivelyTank and PlayerUtil.IsPlayerEffectivelyTank()
	end)
	return ok and tank == true
end

local function IsTank()
	if db.role == "tank" then
		return true
	elseif db.role == "dps" then
		return false
	end
	return AutoTank()
end

-- Whether a nameplate's unit is one this addon colours.
local function Wanted(unit)
	return UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit)
		and not UnitIsDead(unit) and not UnitIsTapDenied(unit) and UnitAffectingCombat(unit)
end

-- Threat state 0-3 on the green-to-red scale, or nil when the game keeps
-- it secret. The second value says whether you are on the enemy's threat
-- list at all; off the list the state is "no threat", which a tank should
-- fix.
local function State(unit, tank)
	local state
	if tank then
		state = UnitThreatLeadSituation("player", unit)
	else
		state = UnitThreatSituation("player", unit)
	end
	if IsSecret(state) then
		return nil, true
	end
	if state == nil then
		return tank and 3 or 0, false
	end
	return state, true
end

-- Whether the enemy's target is you: true, false, or a secret boolean that
-- only the game can turn into a colour (see Pick).
local function OnMe(unit)
	local target = unit .. "target"
	local exists = UnitExists(target)
	if not IsSecret(exists) and not exists then
		return false
	end
	return UnitIsUnit(target, "player")
end

-- Whether your pet or someone in your group is on the enemy's threat list.
local function GroupOnList(unit)
	local function listed(member)
		if not UnitExists(member) then
			return false
		end
		local state = UnitThreatSituation(member, unit)
		return IsSecret(state) or state ~= nil
	end
	if listed("pet") then
		return true
	end
	local raid = IsInRaid()
	local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		if listed((raid and "raid" or "party") .. i) or listed((raid and "raidpet" or "partypet") .. i) then
			return true
		end
	end
	return false
end

-- Blizzard's colour for an enemy nameplate, as CompactUnitFrame_UpdateHealthColor
-- works it out for a unit this addon colours (alive, attackable, not a player).
local function BaseColor(frame, unit)
	if UnitIsTapDenied(unit) then
		return CreateColor(0.9, 0.9, 0.9, 1)
	end
	local options = frame.optionTable
	local r, g, b = UnitSelectionColor(unit, type(options) == "table" and options.colorHealthWithExtendedColors or false)
	return CreateColor(r, g, b, 1)
end

-- ifTrue or ifFalse by a flag that may be secret.
local function Pick(flag, ifTrue, ifFalse)
	if IsSecret(flag) then
		return C_CurveUtil.EvaluateColorFromBoolean(flag, ifTrue, ifFalse)
	end
	return flag and ifTrue or ifFalse
end

-- The other members of your group with an assigned role: the tanks, or
-- the healers and damage dealers. Also says whether the group has any
-- assigned tank besides you (without one, nobody can be "loose").
local function Members(wantTanks)
	local found, anyTank = {}, false
	local raid = IsInRaid()
	local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		local member = (raid and "raid" or "party") .. i
		local isMe = UnitIsUnit(member, "player")
		if IsSecret(isMe) then
			isMe = false -- harmless: only asked about enemies that are not on you
		end
		if UnitExists(member) and not isMe then
			local role = UnitGroupRolesAssigned(member)
			if not IsSecret(role) then
				anyTank = anyTank or role == "TANK"
				if (wantTanks and role == "TANK") or (not wantTanks and (role == "HEALER" or role == "DAMAGER")) then
					found[#found + 1] = member
				end
			end
		end
	end
	return found, anyTank
end

-- ifHeld when one of these members is tanking the enemy, otherwise the
-- given colour. Secret answers are chained through the game, so this
-- works for any number of members in lockdown too.
local function HeldColor(members, unit, ifHeld, otherwise)
	local color = otherwise
	for _, member in ipairs(members) do
		local isTanking = UnitDetailedThreatSituation(member, unit)
		if IsSecret(isTanking) then
			color = C_CurveUtil.EvaluateColorFromBoolean(isTanking, ifHeld, color)
		elseif isTanking then
			return ifHeld
		end
	end
	return color
end

-- Tank: red ("not on you") becomes grey when another tank has it.
local function LostColor(unit)
	local ok, color = pcall(HeldColor, (Members(true)), unit, GREY, COLORS[3])
	return ok and color or COLORS[3]
end

-- Healer or damage: green ("not on you") becomes amber when it is loose on
-- another healer or damage dealer, in a group that has a tank.
local function SafeColor(unit)
	local ok, color = pcall(function()
		local others, anyTank = Members(false)
		if not anyTank then
			return COLORS[0]
		end
		return HeldColor(others, unit, LOOSE, COLORS[0])
	end)
	return ok and color or COLORS[0]
end

-- The colour when the threat state is secret: whether you are tanking it,
-- turned into a colour by the game.
local function SecretColor(unit, tank)
	local isTanking = UnitDetailedThreatSituation("player", unit)
	if tank then
		return C_CurveUtil.EvaluateColorFromBoolean(isTanking, COLORS[0], LostColor(unit))
	end
	return C_CurveUtil.EvaluateColorFromBoolean(isTanking, COLORS[3], SafeColor(unit))
end

local painted = setmetatable({}, { __mode = "k" }) -- unit frames whose bar carries our colour

-- Put Blizzard's colour back on a bar we painted. From the hook Blizzard
-- has just done that itself.
local function Release(frame, unit, fromHook)
	if not painted[frame] then
		return
	end
	painted[frame] = nil
	if fromHook or not frame.healthBar then
		return
	end
	pcall(function()
		if UnitExists(unit) then
			frame.healthBar:SetStatusBarColor(BaseColor(frame, unit):GetRGB())
		end
	end)
end

-- The colour for an enemy in combat, or nil when the fight is not yours.
local function ColorFor(frame, unit, tank)
	local state, listed = State(unit, tank)
	if state == nil then
		return SecretColor(unit, tank)
	end
	local onMe = OnMe(unit)
	local mine = tank and COLORS[0] or COLORS[3] -- the colour of "it is on you"
	if not listed then
		local group = GroupOnList(unit)
		if not group and not IsSecret(onMe) and not onMe then
			return nil
		end
		local other = group and (tank and LostColor(unit) or SafeColor(unit)) or BaseColor(frame, unit)
		return Pick(onMe, mine, other)
	end
	if tank then
		return state == 3 and LostColor(unit) or COLORS[state] or COLORS[3]
	elseif state == 0 then
		-- No threat to speak of, but it may be heading for you all the same.
		return Pick(onMe, mine, SafeColor(unit))
	end
	return COLORS[state] or COLORS[3]
end

local function Paint(frame, fromHook)
	local unit = frame.unit
	if type(unit) ~= "string" or IsSecret(unit) or not unit:find("^nameplate") then
		return
	end
	local healthBar = frame.healthBar
	if not healthBar then
		return
	end
	local ok, wanted = pcall(Wanted, unit)
	if not ok or not wanted then
		Release(frame, unit, fromHook)
		return
	end
	local okColor, color = pcall(ColorFor, frame, unit, IsTank())
	if not okColor or not color then
		Release(frame, unit, fromHook)
		return
	end
	if pcall(function() healthBar:SetStatusBarColor(color:GetRGB()) end) then
		painted[frame] = true
	end
end

local function PaintHook(frame)
	Paint(frame, true)
end

local function PaintAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		if plate.UnitFrame then
			Paint(plate.UnitFrame)
		end
	end
end

local ROLES = { auto = true, tank = true, dps = true }

local function Command(msg)
	local word = (msg or ""):lower():match("^%s*(%S*)")
	if ROLES[word] then
		db.role = word
		PaintAll()
	elseif word ~= "" and word ~= "status" then
		Print("/threatcolor auto | tank | dps   -- which way the colours run")
	end
	Print(("role: %s (%s); green means %s"):format(db.role, IsTank() and "tank" or "not a tank",
		IsTank() and "you hold threat" or "no threat on you"))
	local unit = UnitExists("target") and "target"
	if unit and UnitCanAttack("player", unit) then
		local ok, state, listed = pcall(State, unit, IsTank())
		local okMe, onMe = pcall(OnMe, unit)
		local okGroup, group = pcall(GroupOnList, unit)
		Print(("target: in combat %s, threat state %s, you are on its list %s, it targets you %s, pet or group on its list %s"):format(
			tostring(UnitAffectingCombat(unit)),
			not ok and "error" or state == nil and "secret" or tostring(state),
			not ok and "?" or tostring(listed),
			not okMe and "error" or IsSecret(onMe) and "secret" or tostring(onMe),
			not okGroup and "error" or tostring(group)))
	end
end

------------------------------------------------------------------------------
-- The game's options window (Options > AddOns): the setting of the slash
-- command as a dropdown. Optional: without the game's settings API the
-- slash command still does everything.
------------------------------------------------------------------------------

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting and Settings.CreateDropdown) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("ThreatColor")

	local function Proxy(key, kind, name, default, get, set)
		if default == nil then
			default = DEFAULTS[key]
		end
		return Settings.RegisterProxySetting(category, "ThreatColor_" .. key, kind, name, default,
			get or function() return db[key] end, set or function(value) db[key] = value end)
	end
	-- choices: { value, label, tooltip } each.
	local function Dropdown(key, name, tooltip, choices, default, get, set)
		local function Choices()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(choices) do
				container:Add(choice[1], choice[2], choice[3])
			end
			return container:GetData()
		end
		Settings.CreateDropdown(category, Proxy(key, Settings.VarType.String, name, default, get, set), Choices, tooltip)
	end

	Dropdown("role", "Role", "Which way the nameplate colours run.", {
		{ "auto", "Automatic", "Tank when the game counts you as one." },
		{ "tank", "Tank", "Green means you hold threat." },
		{ "dps", "Healer or damage", "Green means no threat on you." },
	}, nil, nil, function(value)
		db.role = value
		PaintAll()
	end)

	Settings.RegisterAddOnCategory(category)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ROLES_ASSIGNED")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
loader:RegisterEvent("PLAYER_TALENT_UPDATE")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("UNIT_FLAGS")
loader:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
loader:RegisterEvent("UNIT_TARGET")
loader:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" then
		if arg == "ThreatColor" then
			ThreatColorDB = ThreatColorDB or {}
			db = ThreatColorDB
			for key, value in pairs(DEFAULTS) do
				if db[key] == nil then
					db[key] = value
				end
			end
			SLASH_THREATCOLOR1 = "/threatcolor"
			SLASH_THREATCOLOR2 = "/tcolor"
			SlashCmdList.THREATCOLOR = Command
			local ok, err = pcall(RegisterSettings)
			if not ok then
				Print(("options panel unavailable (%s); use /threatcolor instead"):format(tostring(err)))
			end
		end
	elseif event == "PLAYER_LOGIN" then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", PaintHook)
		PaintAll()
		-- An enemy changing target or leaving combat does not always come
		-- with an event for its nameplate.
		C_Timer.NewTicker(0.5, PaintAll)
	elseif event == "UNIT_FLAGS" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_TARGET" then
		if db and type(arg) == "string" and not IsSecret(arg) and arg:find("^nameplate") then
			local plate = C_NamePlate.GetNamePlateForUnit(arg)
			if plate and plate.UnitFrame then
				Paint(plate.UnitFrame)
			end
		end
	else
		PaintAll() -- the role may have changed
	end
end)
