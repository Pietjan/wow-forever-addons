-- ThreatColor: the health bar of an enemy nameplate shows your threat on
-- it, green / yellow / orange / red, from the start of the fight.
--
-- Blizzard's own threat colour (Options > Nameplates, threat display) only
-- takes over once you are close to pulling, and only in a group; the rest
-- of the time the bar keeps its hostility colour, so most fights go from
-- red to a shade of red. Here, every enemy that is in combat gets a threat
-- colour, and the scale turns around with your role:
--
--   not a tank  green: no threat, yellow/orange: about to pull, red: it is on you
--   tank        green: you hold it, yellow/orange: someone is catching up,
--               red: you lost it (or never had it)
--
-- These are the game's own threat states (UnitThreatSituation for others,
-- UnitThreatLeadSituation for tanks, as Blizzard uses them). Enemies out of
-- combat, players, tapped and dead units keep Blizzard's colour.
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

local DEFAULTS = {
	role = "auto", -- "auto", "tank" or "dps"
}

local COLORS = {
	[0] = CreateColor(0.20, 0.80, 0.20), -- green
	[1] = CreateColor(1.00, 0.85, 0.00), -- yellow
	[2] = CreateColor(1.00, 0.50, 0.00), -- orange
	[3] = CreateColor(1.00, 0.10, 0.10), -- red
}

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
-- it secret.
local function State(unit, tank)
	local state
	if tank then
		state = UnitThreatLeadSituation("player", unit)
	else
		state = UnitThreatSituation("player", unit)
	end
	if IsSecret(state) then
		return nil
	end
	if state == nil then
		-- Not on its threat list: no threat at all, which a tank should fix.
		return tank and 3 or 0
	end
	return state
end

-- The colour when the threat state is secret: whether you are tanking it,
-- turned into a colour by the game.
local function SecretColor(unit, tank)
	local isTanking = UnitDetailedThreatSituation("player", unit)
	if tank then
		return C_CurveUtil.EvaluateColorFromBoolean(isTanking, COLORS[0], COLORS[3])
	end
	return C_CurveUtil.EvaluateColorFromBoolean(isTanking, COLORS[3], COLORS[0])
end

local function Paint(frame)
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
		return
	end
	local tank = IsTank()
	local okState, state = pcall(State, unit, tank)
	if okState and state then
		local color = COLORS[state] or COLORS[3]
		healthBar:SetStatusBarColor(color:GetRGB())
		return
	end
	pcall(function()
		local color = SecretColor(unit, tank)
		healthBar:SetStatusBarColor(color:GetRGB())
	end)
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
		local ok, state = pcall(State, unit, IsTank())
		Print(("target: in combat %s, threat state %s"):format(tostring(UnitAffectingCombat(unit)),
			not ok and "error" or state == nil and "secret" or tostring(state)))
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ROLES_ASSIGNED")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
loader:RegisterEvent("PLAYER_TALENT_UPDATE")
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
		end
	elseif event == "PLAYER_LOGIN" then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", Paint)
		PaintAll()
	else
		PaintAll() -- the role may have changed
	end
end)
