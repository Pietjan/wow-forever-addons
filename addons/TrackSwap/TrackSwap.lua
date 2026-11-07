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
	-- Changing tracking plays the interface's click, sound file 567407 in the
	-- game's data. "file" mutes just that file around each swap, "all" turns
	-- every sound effect off for a moment instead, "off" mutes nothing.
	mute = "file",
	muteFile = 567407,
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
		return info.name, info.active, info.spellID, info.type
	end
	local name, _, active, category, _, spellID = C_Minimap.GetTrackingInfo(index)
	return name, active, spellID, category
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

-- Whether another tracking *spell* is on (Find Fish, a hunter's tracking).
-- The list also holds the minimap's filters for vendors, trainers and so
-- on, which are ticked by default and are not tracking in this sense.
local function AnyOtherTrackingActive(herbs, minerals)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		if i ~= herbs and i ~= minerals then
			local _, active, _, kind = TrackingInfo(i)
			if active and kind == "spell" then
				return true
			end
		end
	end
	return false
end

-- Put sound effects back if a swap turned them off.
local function RestoreSound()
	if db.soundOff then
		db.soundOff = nil
		SetCVar("Sound_EnableSFX", "1")
	end
	if db.mutedFile then
		local file = db.mutedFile
		db.mutedFile = nil
		pcall(UnmuteSoundFile, file)
	end
end

-- Keep the click quiet while the tracking changes. Sound effects started
-- while they are muted never play. A saved flag survives a reload or logout
-- that lands inside that moment, so the next login can put the sound back.
local Quiet
function Quiet()
	if db.mute == "all" then
		if GetCVar("Sound_EnableSFX") == "1" then
			db.soundOff = true
			SetCVar("Sound_EnableSFX", "0")
		end
	elseif db.mute == "file" and db.muteFile then
		db.mutedFile = db.muteFile
		local ok, err = pcall(MuteSoundFile, db.muteFile)
		if not ok then
			-- No such function on this client, or it is not allowed: fall
			-- back to switching all effects off for the moment.
			db.mutedFile = nil
			db.mute = "all"
			Print("cannot mute a single sound file (%s); muting all effects during swaps instead", tostring(err))
			return Quiet()
		end
	end
	-- The game confirms the change with MINIMAP_UPDATE_TRACKING, and the
	-- click plays then; the sound comes back right after that, or after a
	-- moment if the event never comes.
	C_Timer.After(0.5, RestoreSound)
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
	Quiet()
	local ok, err = pcall(C_Minimap.SetTracking, next, true)
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
	local mute = db.mute == "all" and "all sound effects" or db.mute == "file" and ("sound file " .. db.muteFile) or "nothing"
	Print("%s, every %g s, muting %s during the swap%s", db.enabled and "on" or "off", db.interval, mute,
		(herbs and minerals) and "" or " (needs both Find Herbs and Find Minerals)")
end

SLASH_TRACKSWAP1 = "/ts"
SLASH_TRACKSWAP2 = "/trackswap"
SlashCmdList.TRACKSWAP = function(msg)
	local word, rest = msg:lower():match("^%s*(%S*)%s*(%S*)")
	local seconds = tonumber(word)
	if word == "mute" then
		if rest == "all" or rest == "off" then
			db.mute = rest
		elseif rest == "file" or tonumber(rest) then
			db.mute = "file"
			db.muteFile = tonumber(rest) or db.muteFile
		else
			Print("/ts mute file | all | off | <sound file id>")
			return
		end
	elseif word == "" then
		db.enabled = not db.enabled
	elseif word == "on" then
		db.enabled = true
	elseif word == "off" then
		db.enabled = false
	elseif seconds then
		db.interval = math.max(0.5, math.min(30, seconds))
		Start()
	elseif word ~= "status" then
		Print("/ts  toggles the swapping; /ts on, /ts off; /ts <seconds> sets the pace; /ts mute file|all|off")
		return
	end
	Status()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LEAVING_WORLD")
loader:RegisterEvent("MINIMAP_UPDATE_TRACKING")
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
		RestoreSound()
	elseif event == "PLAYER_LOGIN" then
		Start()
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- A reload or logout: do not leave the sound off.
		RestoreSound()
	elseif event == "MINIMAP_UPDATE_TRACKING" then
		if db and (db.soundOff or db.mutedFile) then
			C_Timer.After(0, RestoreSound)
		end
	end
end)
