-- ForeverPlates: nameplate tweaks, one feature per file, each of which can
-- be switched on or off on its own (Options > AddOns > ForeverPlates, or
-- /fplates <feature> on|off).
--
--   names   NameOnly.lua     friendly player plates show just the name
--   threat  ThreatColor.lua  enemy bars coloured by your threat
--   numbers ThreatNumbers.lua  your threat on each enemy as a percentage
--   target  PlateTarget.lua  who each enemy is targeting, under its bar
--   quest   QuestTarget.lua  a quest mark on enemies you still need
--   level   LevelBox.lua     hides the level box beside the bar (off by default)
--
-- A feature file calls ns.Feature{...} with:
--   key       its slash word and the name of its saved table
--   title     its name in the options window and in chat
--   defaults  its saved settings; every feature has `enabled`
--   events    events it listens to while on; unitEvents { event, unit } too
--   OnEvent(event, ...)  while on
--   OnLoad()  once the saved settings are there, on or off
--   OnLogin() once at login, on or off (hooks go here: they cannot be
--             taken out again, so a hook checks feature.db.enabled itself)
--   Start()   when it goes on: at login, or from the toggle
--   Stop()    when it goes off from the toggle: undo what it shows
--   Command(rest)  for /fplates <key> <rest>
--   Options(page, ui)  its own page in the options window
--
-- Every feature keeps to Forever's nameplate rules: no Blizzard layout
-- function is called and no Blizzard field is written on a plate (either
-- one taints Blizzard's own code), and nothing on a plate is measured.

local ADDON_NAME, ns = ...

ns.features = {} -- in load order, which is the order they are shown in
local byKey = {}
local loggedIn = false

ns.IsSecret = issecretvalue or function() return false end

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffForeverPlates|r " .. text)
end

-- "on", "1", "yes" -> true; "off", "0", "no" -> false; anything else nil.
function ns.OnOff(value)
	if value == "on" or value == "1" or value == "yes" then
		return true
	elseif value == "off" or value == "0" or value == "no" then
		return false
	end
end

-- Tank or not, for the colours of ThreatColor and PlateTarget: the role
-- chosen under Threat colours, or else the game's own answer (spec role, or
-- the assigned group role). Asked whether ThreatColor is on or not.
function ns.IsTank()
	local threat = byKey.threat
	local role = threat and threat.db and threat.db.role
	if role == "tank" then
		return true
	elseif role == "dps" then
		return false
	end
	local ok, tank = pcall(function()
		return PlayerUtil and PlayerUtil.IsPlayerEffectivelyTank and PlayerUtil.IsPlayerEffectivelyTank()
	end)
	return ok and tank == true
end

-- Whether there is anyone else to share threat with: a party or raid, or
-- your pet. Alone, every mob is on you, so Threat numbers and the YOU of
-- Enemy targets say nothing.
function ns.Shared()
	return IsInGroup() or UnitExists("pet")
end

-- The nameplate name's own font: Blizzard's rule from
-- Blizzard_NamePlateUnitFrame.lua (GetNamePlateFontObject, a local there),
-- read from its plain NamePlateSetupOptions table, never from the plate.
function ns.NamePlateFont()
	local options = NamePlateSetupOptions or {}
	local styles = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES or {}
	local style = options.unitNameAnchorStyle
	local outlined = style ~= nil and (style == styles.InsideHealthBar or style == styles.CenteredAboveHealthBar
		or (style == styles.AboveHealthBar and options.useOutlinedFontWhenAboveHealthBar))
	return outlined and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate", options.healthBarFontHeight
end

function ns.Feature(feature)
	feature.frame = CreateFrame("Frame")
	feature.frame:SetScript("OnEvent", function(_, ...)
		feature.OnEvent(...)
	end)
	ns.features[#ns.features + 1] = feature
	byKey[feature.key] = feature
	return feature
end

local function Listen(feature, on)
	local frame = feature.frame
	for _, event in ipairs(feature.events or {}) do
		if on then
			frame:RegisterEvent(event)
		else
			frame:UnregisterEvent(event)
		end
	end
	for _, pair in ipairs(feature.unitEvents or {}) do
		if on then
			frame:RegisterUnitEvent(pair[1], pair[2])
		else
			frame:UnregisterEvent(pair[1])
		end
	end
end

local function Report(feature, err)
	ns.Print(("%s: %s"):format(feature.title, tostring(err)))
end

-- Switch a feature on or off. Before login only the saved flag changes;
-- login starts what is on.
function ns.SetEnabled(feature, on)
	if feature.db.enabled == on then
		return
	end
	feature.db.enabled = on
	if not loggedIn then
		return
	end
	Listen(feature, on)
	local step = on and feature.Start or feature.Stop
	if step then
		local ok, err = pcall(step)
		if not ok then
			Report(feature, err)
		end
	end
end

-- Slash command --------------------------------------------------------------

local function Status()
	for _, feature in ipairs(ns.features) do
		ns.Print(("%s (%s): %s"):format(feature.title, feature.key, feature.db.enabled and "on" or "|cffff8080off|r"))
	end
end

local function Command(msg)
	local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	word = word:lower()
	local feature = byKey[word]
	if not feature then
		Status()
		local keys = {}
		for _, f in ipairs(ns.features) do
			keys[#keys + 1] = f.key
		end
		ns.Print("/fplates " .. table.concat(keys, " | ") .. "  -- then on, off, or that feature's own settings")
		return
	end
	local on = ns.OnOff(rest:lower())
	if on ~= nil then
		ns.SetEnabled(feature, on)
		ns.Print(("%s %s."):format(feature.title, on and "on" or "off"))
	elseif feature.Command then
		feature.Command(rest)
	else
		ns.Print(("%s is %s; /fplates %s on|off"):format(feature.title, feature.db.enabled and "on" or "off", feature.key))
	end
end

-- Events -------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" then
		if arg ~= ADDON_NAME then
			return
		end
		ForeverPlatesDB = ForeverPlatesDB or {}
		for _, feature in ipairs(ns.features) do
			local db = ForeverPlatesDB[feature.key] or {}
			ForeverPlatesDB[feature.key] = db
			for key, value in pairs(feature.defaults) do
				if db[key] == nil then
					db[key] = value
				end
			end
			feature.db = db
			if feature.OnLoad then
				local ok, err = pcall(feature.OnLoad)
				if not ok then
					Report(feature, err)
				end
			end
		end
		SLASH_FOREVERPLATES1 = "/fplates"
		SLASH_FOREVERPLATES2 = "/foreverplates"
		SlashCmdList.FOREVERPLATES = Command
		local ok, err = pcall(ns.RegisterSettings)
		if not ok then
			ns.Print(("options panel unavailable (%s); use /fplates instead"):format(tostring(err)))
		end
	elseif event == "PLAYER_LOGIN" then
		loggedIn = true
		for _, feature in ipairs(ns.features) do
			if feature.OnLogin then
				local ok, err = pcall(feature.OnLogin)
				if not ok then
					Report(feature, err)
				end
			end
			if feature.db.enabled then
				Listen(feature, true)
				if feature.Start then
					local ok, err = pcall(feature.Start)
					if not ok then
						Report(feature, err)
					end
				end
			end
		end
	end
end)
