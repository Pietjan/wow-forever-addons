-- Options.lua: the game's options window (Options > AddOns), with the
-- settings of /fchat as check boxes, sliders and dropdowns. Every change goes
-- through ns.Set (Core.lua), as the slash command's do. Optional: without
-- the game's settings API the slash command still does everything.
--
-- /fchat save, load and layout rewrite a character's whole chat setup; they
-- stay commands.
local _, ns = ...

function ns.RegisterSettings()
	local db, DEFAULTS = ns.db, ns.defaults
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("ForeverChat")

	local function Proxy(key, kind, name, default, get, set)
		if default == nil then
			default = DEFAULTS[key]
		end
		return Settings.RegisterProxySetting(category, "ForeverChat_" .. key, kind, name, default,
			get or function() return db[key] end, set or function(value) ns.Set(key, value) end)
	end
	local function Checkbox(key, name, tooltip, default, get, set)
		Settings.CreateCheckbox(category, Proxy(key, Settings.VarType.Boolean, name, default, get, set), tooltip)
	end
	-- A slider hands over what its arithmetic gives (0.30000000000000004):
	-- store the step it stands on.
	local function Slider(key, name, tooltip, min, max, step, format, default, get, set)
		set = set or function(value) ns.Set(key, value) end
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

	Checkbox("sync", "This character follows the shared chat setup",
		"The shared setup is put on this character at login and its changes are taken back at logout. /fchat save and /fchat load do it by hand.",
		true, ns.Sync.IsEnabled, ns.Sync.SetEnabled)
	Dropdown("short", "Channel names", "For new messages; lines already in the window stay as they are.", {
		{ "number", "[1]", "[1] [G] [P] [RL]" },
		{ "name", "[General]", "The channel's name without its number and zone." },
		{ "off", "The game's own", "[1. General - Orgrimmar] [Guild] [Party] [Raid Leader]" },
	})
	Checkbox("links", "Web addresses are links", "A click on a web address in chat opens a box to copy it from.")
	Checkbox("skin", "Forever art on the chat frame", "Takes effect after a /reload.")
	Checkbox("combatLogLast", "Combat Log tab after the other tabs", "Instead of in second place. Takes effect after a /reload.", false,
		function() return db.combatLogLast and true or false end) -- unset until first chosen
	Dropdown("input", "Input box", nil, {
		{ "active", "Only while typing" },
		{ "always", "Always shown" },
	})
	Checkbox("arrows", "Arrow keys move the cursor", "In the input box, without holding Alt.")
	Checkbox("follow", "Bring the channel's tab to the front", "Typing /2, /p or /g brings the tab that shows that channel to the front.")
	Checkbox("history", "Keep chat lines across a reload")
	Slider("scrollDown", "Return to the newest line", "Seconds before a chat window left scrolled up goes back to the newest line; all the way left for never.",
		0, 600, 5, function(value) return value < 5 and "never" or ("%d s"):format(value + 0.5) end)

	Settings.RegisterAddOnCategory(category)
end
