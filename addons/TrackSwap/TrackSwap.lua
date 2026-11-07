-- TrackSwap: the minimap can track herbs or minerals, not both. This swaps
-- between Find Herbs and Find Minerals every few seconds, so nodes of both
-- kinds keep appearing on the minimap while you move through a zone.
--
-- It only swaps while one of the two (or nothing) is being tracked: pick
-- any other tracking, such as Find Fish, and it stays out of the way until
-- you come back to herbs or minerals. It also waits out combat and death.

local ADDON_NAME = ...

local FIND_HERBS, FIND_MINERALS = 2383, 2580 -- the tracking spells

local DEFAULTS = {
	enabled = true,
	interval = 2, -- seconds between swaps
}

local db
local ticker

local function Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff9999ffTrackSwap|r " .. msg)
end

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID)
	elseif GetSpellInfo then
		return (GetSpellInfo(spellID))
	end
end

-- The tracking entries, read through whichever form of the API this client
-- has: newer ones return a table, older ones a list of values.
local function TrackingInfo(index)
	local info = C_Minimap.GetTrackingInfo(index)
	if type(info) == "table" then
		return info.name, info.active, info.spellID
	end
	local name, _, active, _, _, spellID = C_Minimap.GetTrackingInfo(index)
	return name, active, spellID
end

-- The tracking index of a tracking spell, and whether it is active.
local function Find(spellID)
	local spellName = SpellName(spellID)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local name, active, id = TrackingInfo(i)
		if id == spellID or (id == nil and spellName and name == spellName) then
			return i, active
		end
	end
	return nil
end

local function AnyOtherTrackingActive(herbs, minerals)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		if i ~= herbs and i ~= minerals then
			local _, active = TrackingInfo(i)
			if active then
				return true
			end
		end
	end
	return false
end

local function Swap()
	if not db.enabled or InCombatLockdown() or UnitIsDeadOrGhost("player") then
		return
	end
	local herbs, herbsActive = Find(FIND_HERBS)
	local minerals, mineralsActive = Find(FIND_MINERALS)
	if not (herbs and minerals) then
		return -- one of the two is not known yet
	end
	local next
	if herbsActive then
		next = minerals
	elseif mineralsActive then
		next = herbs
	elseif not AnyOtherTrackingActive(herbs, minerals) then
		next = herbs
	else
		return -- the player is tracking something else
	end
	-- Changing tracking plays a click. Sound effects started while they are
	-- switched off never play, so turn them off around the swap and put them
	-- back a moment later.
	local sfx = GetCVar("Sound_EnableSFX")
	if sfx == "1" then
		SetCVar("Sound_EnableSFX", "0")
	end
	local ok, err = pcall(C_Minimap.SetTracking, next, true)
	if sfx == "1" then
		C_Timer.After(0.2, function()
			SetCVar("Sound_EnableSFX", "1")
		end)
	end
	if not ok then
		Print("could not switch tracking: %s", tostring(err))
		db.enabled = false
	end
end

local function Start()
	if ticker then
		ticker:Cancel()
	end
	ticker = C_Timer.NewTicker(db.interval, Swap)
end

local function Status()
	local herbs = Find(FIND_HERBS)
	local minerals = Find(FIND_MINERALS)
	Print("%s, every %g s%s", db.enabled and "on" or "off", db.interval,
		(herbs and minerals) and "" or " (needs both Find Herbs and Find Minerals)")
end

SLASH_TRACKSWAP1 = "/ts"
SLASH_TRACKSWAP2 = "/trackswap"
SlashCmdList.TRACKSWAP = function(msg)
	local word = msg:lower():match("^%s*(%S*)")
	local seconds = tonumber(word)
	if word == "" then
		db.enabled = not db.enabled
	elseif word == "on" then
		db.enabled = true
	elseif word == "off" then
		db.enabled = false
	elseif seconds then
		db.interval = math.max(0.5, math.min(30, seconds))
		Start()
	elseif word ~= "status" then
		Print("/ts  toggles the swapping; /ts on, /ts off; /ts <seconds> sets the pace")
		return
	end
	Status()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON_NAME then
			return
		end
		TrackSwapDB = TrackSwapDB or {}
		db = TrackSwapDB
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				db[key] = value
			end
		end
	elseif event == "PLAYER_LOGIN" then
		Start()
	end
end)
