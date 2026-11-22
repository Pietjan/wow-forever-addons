-- GroupFrames in the game's options window (Options > AddOns > GroupFrames).
-- Optional: without the game's settings API /groupframes still does
-- everything.
--
-- Party: your solo frame, party pets. Raid of 10, of 25, of 40: each
-- layout's pets and size. Frames: the aggro highlight, the range fade and how
-- faded. Buttons do what the slash commands do: unlock or lock, reset the
-- places, test a party or a raid of 10, 25 or 40, end a test.
--
-- What changes the secure headers (solo frame, pets, raid size) cannot
-- change in combat: the setting is saved at once and shows when combat ends.

local _, ns = ...

local function Say(text)
	print("|cffffd100GroupFrames|r: " .. text)
end

local function Slash(text)
	SlashCmdList.GROUPFRAMES(text)
end

local registered = false

function ns.RegisterSettings(db)
	if registered then
		return
	end
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown and Settings.RegisterInitializer
		and CreateSettingsButtonInitializer) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("GroupFrames")

	local function Header(text)
		if CreateSettingsListSectionHeaderInitializer then
			Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(text))
		end
	end

	-- apply runs after a change; false from it means "after combat".
	local function Applied(ok)
		if ok == false then
			Say("saved; it shows when combat ends.")
		end
	end

	local function Proxy(key, kind, name, default, get, set)
		return Settings.RegisterProxySetting(category, "GroupFrames_" .. key, kind, name, default,
			get or function() return db[key] end, set)
	end

	local function Checkbox(key, name, tooltip, default, apply)
		local setting = Proxy(key, Settings.VarType.Boolean, name, default, nil, function(value)
			db[key] = value and true or false
			Applied(apply())
		end)
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	-- A slider hands over what its arithmetic gives (0.30000000000000004):
	-- store the step it stands on. Shown as a percentage.
	local function Slider(key, name, tooltip, min, max, step, default, get, set)
		local setting = Proxy(key, Settings.VarType.Number, name, default, get, function(value)
			set(tonumber(("%.4f"):format(min + math.floor((value - min) / step + 0.5) * step)))
		end)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return ("%d%%"):format(math.floor(value * 100 + 0.5))
		end)
		Settings.CreateSlider(category, setting, options, tooltip)
	end

	-- choices: a list of { key = , label = }.
	local function Dropdown(key, name, tooltip, choices, default, get, set)
		local setting = Proxy(key, Settings.VarType.String, name, default, get, set)
		Settings.CreateDropdown(category, setting, function()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(choices) do
				container:Add(choice.key, choice.label)
			end
			return container:GetData()
		end, tooltip)
	end

	local function Button(name, text, onClick, tooltip)
		Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
	end

	local defaults = ns.PARTY_DEFAULTS

	Header("Party")
	Checkbox("soloFrame", "Your frame when solo", "Shows your own frame (and your pet's) when you are not in a group.",
		defaults.soloFrame, ns.PartyApplySettings)
	Checkbox("partyPets", "Party pets", "A row of your party's pets under the party, at 75%.",
		defaults.partyPets, ns.PartyApplySettings)
	Dropdown("partyLayout", "Layout", "A row or a column, and which way it grows from where you placed it. Pets follow the shape.",
		ns.PARTY_LAYOUTS, defaults.partyLayout,
		function() return db.partyLayout end,
		function(value)
			db.partyLayout = value
			Applied(ns.PartyApplySettings())
		end)

	-- A section per raid layout: its pets and its size. The headcount picks
	-- the layout: up to 10, up to 25, more.
	db.raidScales = db.raidScales or {}
	db.raidLayouts = db.raidLayouts or {}
	for _, size in ipairs({ 10, 25, 40 }) do
		Header(("Raid of %d"):format(size))
		local reach = size == 40 and "in a raid of more than 25" or ("in a raid of up to %d"):format(size)
		local setting = Proxy("raidPets" .. size, Settings.VarType.Boolean, "Pets", false,
			function() return ns.RaidPetsShown(size) end,
			function(value) Applied(ns.RaidPets(value, size)) end)
		Settings.CreateCheckbox(category, setting, ("The raid's pets in a grid of 5 with the raid, at 75%%, %s."):format(reach))
		Dropdown("raidLayout" .. size, "Layout",
			("How the groups are laid out %s: each group a row or a column, and which way they go from where you placed it."):format(reach),
			ns.RAID_LAYOUTS, ns.RAID_LAYOUTS[1].key,
			function() return db.raidLayouts[size] or ns.RAID_LAYOUTS[1].key end,
			function(value)
				db.raidLayouts[size] = value
				Applied(ns.RaidApplySettings())
			end)
		local default = ns.RaidDefaultScale(size)
		Slider("raidScale" .. size, "Size", ("How big the raid frames are %s."):format(reach),
			0.5, 1.2, 0.01, default,
			function() return db.raidScales[size] or default end,
			function(value)
				db.raidScales[size] = value
				Applied(ns.RaidApplySettings())
			end)
	end

	Header("Frames")
	Checkbox("aggro", "Aggro highlight", "A glow round a frame whose unit has threat: orange gaining, red high.",
		defaults.aggro, ns.PartyApplySettings)
	Checkbox("rangeFade", "Fade out of range", "Fades the frames of group members out of range.",
		defaults.rangeFade, ns.PartyApplySettings)
	Slider("fadedAlpha", "Faded to", "How visible an out-of-range member's frame stays.", 0.1, 0.9, 0.05, defaults.fadedAlpha,
		function() return db.fadedAlpha end,
		function(value)
			db.fadedAlpha = value
			ns.PartyApplySettings()
		end)

	Header("Moving and testing")
	Button("Move the frames", "Unlock / lock", function() Slash("") end,
		"Unlocks the frames: drag the green box (party) or the blue box (raid). Again to lock. Ends a test.")
	Button("Places", "Reset", function() Slash("reset") end, "Party and raid frames back at their starting places.")
	Button("Test a party", "Party of 5", function() Slash("test 5") end, "Five made-up members, unlocked to drag.")
	Button("Test a raid of 10", "Raid of 10", function() Slash("test raid 10") end, "A made-up raid of 10, unlocked to drag the 10 layout's place.")
	Button("Test a raid of 25", "Raid of 25", function() Slash("test raid 25") end, "A made-up raid of 25, unlocked to drag the 25 layout's place.")
	Button("Test a raid of 40", "Raid of 40", function() Slash("test raid 40") end, "A made-up raid of 40, unlocked to drag the 40 layout's place.")
	Button("End a test", "End test", function()
		if ns.PartyTesting() or ns.RaidTesting() then
			Slash("")
		end
	end, "Ends a running test and locks the frames.")

	Settings.RegisterAddOnCategory(category)
	registered = true
end
