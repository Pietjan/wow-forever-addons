-- TrackSwap: the minimap can track herbs or minerals, not both. This swaps
-- between Find Herbs and Find Minerals every few seconds, so nodes of both
-- kinds keep appearing on the minimap while you move through a zone.
--
-- It only swaps while one of the two (or nothing) is being tracked: pick
-- any other tracking, such as Find Fish, and it stays out of the way until
-- you come back to herbs or minerals. It also waits out combat, death and
-- any cast or channel, since the swap itself would interrupt those.

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
	-- Seconds to keep still after the player casts or channels anything,
	-- and after a Fishing cast in particular: the line is out for a while
	-- after the cast itself ends, and a swap would reel it in.
	hold = 3,
	fishingHold = 30,
}

local FISHING = 7620 -- for the spell's name

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

-- Switching tracking is a spell cast of its own, and it interrupts whatever
-- the player is casting or channelling, such as a fishing line. The values
-- these calls return may be secret while something is going on, so an error
-- reading them also counts as busy; a skipped swap costs nothing.
local holdUntil = 0

local function Hold(seconds)
	holdUntil = math.max(holdUntil, GetTime() + seconds)
end

local function Busy()
	local ok, busy = pcall(function()
		return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
	end)
	if not ok or busy then
		Hold(db.hold) -- and a moment longer once the cast ends
		return true
	end
	return GetTime() < holdUntil
end

-- A spell the player cast: the tracking spells themselves do not count,
-- Fishing holds longer, anything else holds for a moment.
local function SpellCast(spellID)
	local ok, kind = pcall(function()
		if spellID == FIND_HERBS or spellID == FIND_MINERALS then
			return "tracking"
		end
		local name = SpellName(spellID)
		if name == SpellName(FIND_HERBS) or name == SpellName(FIND_MINERALS) then
			return "tracking"
		elseif name == SpellName(FISHING) then
			return "fishing"
		end
		return "other"
	end)
	if not ok or kind == "other" then
		Hold(db.hold)
	elseif kind == "fishing" then
		Hold(db.fishingHold)
	end
end

local function Swap()
	if not db.enabled or InCombatLockdown() or UnitIsDeadOrGhost("player") or Busy() then
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

------------------------------------------------------------------------------
-- The minimap's tracking button: right-click toggles the swapping, and
-- the game's marching-ants alert runs around it while swapping is on.
------------------------------------------------------------------------------

local glow

local function TrackingButton()
	return MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
		or MiniMapTrackingButton or MiniMapTracking
end

local function UpdateGlow()
	local button = TrackingButton()
	if not button then
		return
	end
	if glow == nil then
		-- The alert template from Blizzard_VisualAlerts, kept shown for as
		-- long as we like instead of handing itself back after two seconds.
		local ok, frame = pcall(CreateFrame, "Frame", nil, button, "VisualAlertMarchingAntsBaseTemplate")
		if ok and frame then
			if frame.SetManualRelease then
				frame:SetManualRelease(true)
			end
			frame:SetScript("OnUpdate", nil)
			frame:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 6)
			frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 7, -7)
			frame:SetFrameLevel(button:GetFrameLevel() + 2)
			glow = frame
		else
			glow = false
		end
	end
	if glow then
		glow:SetShown(db.enabled and true or false)
	end
end

local function Status()
	local herbs = Find(FIND_HERBS)
	local minerals = Find(FIND_MINERALS)
	local mute = db.mute == "all" and "all sound effects" or db.mute == "file" and ("sound file " .. db.muteFile) or "nothing"
	Print("%s, every %g s, muting %s during the swap, holding %g s after a cast and %g s after fishing%s",
		db.enabled and "on" or "off", db.interval, mute, db.hold, db.fishingHold,
		(herbs and minerals) and "" or " (needs both Find Herbs and Find Minerals)")
	UpdateGlow()
end

------------------------------------------------------------------------------
-- The game's options window (Options > AddOns): the settings of the slash
-- command as check boxes, sliders and dropdowns. Optional: without the
-- game's settings API the slash command still does everything.
------------------------------------------------------------------------------

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("TrackSwap")

	local function Proxy(key, kind, name, default, get, set)
		if default == nil then
			default = DEFAULTS[key]
		end
		return Settings.RegisterProxySetting(category, "TrackSwap_" .. key, kind, name, default,
			get or function() return db[key] end, set or function(value) db[key] = value end)
	end
	local function Checkbox(key, name, tooltip, default, get, set)
		Settings.CreateCheckbox(category, Proxy(key, Settings.VarType.Boolean, name, default, get, set), tooltip)
	end
	-- A slider hands over what its arithmetic gives (0.30000000000000004):
	-- store the step it stands on.
	local function Slider(key, name, tooltip, min, max, step, format, default, get, set)
		set = set or function(value) db[key] = value end
		local setting = Proxy(key, Settings.VarType.Number, name, default, get, function(value)
			set(tonumber(("%.4f"):format(min + math.floor((value - min) / step + 0.5) * step)))
		end)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		Settings.CreateSlider(category, setting, options, tooltip)
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

	local function Seconds(value)
		return ("%g s"):format(value)
	end
	Checkbox("enabled", "Swap between herbs and minerals", "Switches the minimap tracking between Find Herbs and Find Minerals. Also on a key binding and on a right-click of the tracking button.",
		nil, nil, function(value)
			db.enabled = value
			UpdateGlow()
		end)
	Slider("interval", "Pace", "Seconds between swaps.", 0.5, 30, 0.5, Seconds, nil, nil, function(value)
		db.interval = value
		Start()
	end)
	Dropdown("mute", "Mute during the swap", "Changing tracking plays a click.", {
		{ "file", "Just the click", "Mutes the one sound file of the click (/ts mute <sound file id> picks another)." },
		{ "all", "All sound effects", "Turns every sound effect off for a moment." },
		{ "off", "Nothing" },
	})
	Slider("hold", "Pause after a cast", "Seconds to leave the tracking alone after you cast or channel anything.", 0, 120, 1, Seconds)
	Slider("fishingHold", "Pause after fishing", "Seconds to leave the tracking alone after a Fishing cast: a swap would reel the line in.", 0, 120, 1, Seconds)

	Settings.RegisterAddOnCategory(category)
end

BINDING_HEADER_TRACKSWAP = "TrackSwap"
BINDING_NAME_TRACKSWAP_TOGGLE = "Toggle herb/mineral swapping"

SLASH_TRACKSWAP1 = "/ts"
SLASH_TRACKSWAP2 = "/trackswap"
SlashCmdList.TRACKSWAP = function(msg)
	local word, rest = msg:lower():match("^%s*(%S*)%s*(%S*)")
	local seconds = tonumber(word)
	if word == "hold" or word == "fishing" then
		local value = tonumber(rest)
		if not value then
			Print("/ts hold <seconds>  pause after any cast; /ts fishing <seconds>  pause after a Fishing cast")
			return
		end
		db[word == "hold" and "hold" or "fishingHold"] = math.max(0, math.min(120, value))
	elseif word == "mute" then
		if rest == "all" or rest == "off" then
			db.mute = rest
		elseif rest == "file" or tonumber(rest) then
			db.mute = "file"
			db.muteFile = tonumber(rest) or db.muteFile
		else
			Print("/ts mute file | all | off | <sound file id>")
			return
		end
	elseif word == "" or word == "toggle" then
		db.enabled = not db.enabled
	elseif word == "on" then
		db.enabled = true
	elseif word == "off" then
		db.enabled = false
	elseif seconds then
		db.interval = math.max(0.5, math.min(30, seconds))
		Start()
	elseif word ~= "status" then
		Print("/ts or /ts toggle  toggles the swapping (also bindable under Key Bindings > AddOns); /ts on, /ts off; /ts <seconds> sets the pace; /ts mute file|all|off; /ts hold <seconds>; /ts fishing <seconds>")
		return
	end
	Status()
end

-- For the key binding (Bindings.xml).
function TrackSwap_Toggle()
	if db then
		db.enabled = not db.enabled
		Status()
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LEAVING_WORLD")
loader:RegisterEvent("MINIMAP_UPDATE_TRACKING")
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
	loader:RegisterUnitEvent(event, "player")
end
loader:SetScript("OnEvent", function(self, event, name, _, spellID)
	if event:sub(1, 15) == "UNIT_SPELLCAST_" then
		if db then
			SpellCast(spellID)
		end
	elseif event == "ADDON_LOADED" then
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
		local ok, err = pcall(RegisterSettings)
		if not ok then
			Print("options panel unavailable (%s); use /ts instead", tostring(err))
		end
	elseif event == "PLAYER_LOGIN" then
		Start()
		UpdateGlow()
		local button = TrackingButton()
		if button then
			-- The button only listens for the left mouse button, so a
			-- right-click on it reaches nobody; catch it from the global
			-- mouse event when the cursor is over the button.
			self:RegisterEvent("GLOBAL_MOUSE_UP")
			button:HookScript("OnEnter", function(self)
				if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
					GameTooltip:AddLine("Right-click: toggle TrackSwap", 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end
			end)
		end
	elseif event == "GLOBAL_MOUSE_UP" then
		if name == "RightButton" and db then
			local button = TrackingButton()
			local over = false
			if button and GetMouseFoci then
				for _, frame in ipairs(GetMouseFoci()) do
					if frame == button or frame == button:GetParent() then
						over = true
					end
				end
			elseif button and GetMouseFocus then
				local focus = GetMouseFocus()
				over = focus == button or focus == button:GetParent()
			end
			if over then
				db.enabled = not db.enabled
				Status()
			end
		end
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- A reload or logout: do not leave the sound off.
		RestoreSound()
	elseif event == "MINIMAP_UPDATE_TRACKING" then
		if db and (db.soundOff or db.mutedFile) then
			C_Timer.After(0, RestoreSound)
		end
	end
end)
