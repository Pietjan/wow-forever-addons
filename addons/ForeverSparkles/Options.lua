-- ForeverSparkles in the game's options window (Options > AddOns): a page of
-- general settings, and under it one page per kind of sparkle with every
-- number that shapes it. The sparkle reads these as it draws, so a change
-- shows on the sparkle in front of you at once.

local _, ns = ...

function ns.RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory
		and Settings.RegisterProxySetting and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown) then
		return
	end
	local db = ns.GetDB()
	local category = Settings.RegisterVerticalLayoutCategory("ForeverSparkles")

	-- page: the settings page; id: unique name; store: the table the value
	-- lives in; after: run once the value is stored.
	local function Proxy(page, id, kind, name, store, key, default, after)
		return Settings.RegisterProxySetting(page, "ForeverSparkles_" .. id, kind, name, default,
			function() return store[key] end,
			function(value)
				store[key] = value
				if after then
					after()
				end
			end)
	end
	local function Checkbox(page, id, name, tooltip, store, key, default, after)
		Settings.CreateCheckbox(page, Proxy(page, id, Settings.VarType.Boolean, name, store, key, default, after), tooltip)
	end
	-- A slider hands over what its arithmetic gives (0.30000000000000004):
	-- store the step it stands on.
	local function Slider(page, id, name, tooltip, store, key, default, min, max, step, format, after)
		local setting = Settings.RegisterProxySetting(page, "ForeverSparkles_" .. id, Settings.VarType.Number, name, default,
			function() return store[key] end,
			function(value)
				store[key] = tonumber(("%.4f"):format(min + math.floor((value - min) / step + 0.5) * step))
				if after then
					after()
				end
			end)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		Settings.CreateSlider(page, setting, options, tooltip)
	end

	local function Whole(value) return ("%d"):format(value) end
	local function Pixels(value) return ("%d px"):format(value) end
	local function Percent(value) return ("%d%%"):format(value * 100 + 0.5) end
	local function Seconds(value) return ("%.1f s"):format(value) end

	-- General ---------------------------------------------------------------

	Checkbox(category, "enabled", "Sparkles", "Switches every sparkle of this addon on or off. Off also puts the game's interact key settings back as they were.",
		db, "enabled", ns.DEFAULTS.enabled, ns.Sync)
	Slider(category, "range", "Reach", "How far ahead the game is asked to look for something to sparkle. The game can stop sooner: objects only get a nameplate up to a distance of its own.",
		db, "range", ns.DEFAULTS.range, 5, 60, 1, function(value) return ("%d yd"):format(value) end, ns.Sync)
	Settings.CreateDropdown(category, Proxy(category, "arc", Settings.VarType.String, "Looks", db, "arc", ns.DEFAULTS.arc, ns.Sync), function()
		local container = Settings.CreateControlTextContainer()
		container:Add("2", "All around you")
		container:Add("1", "In front of you")
		container:Add("0", "Straight ahead only")
		return container:GetData()
	end, "Where the thing has to be for the game to pick it.")
	Checkbox(category, "lootEffect", "The game's own loot sparkle", "Keeps the game's sparkle on things you can loot, also after a graphics preset switches it off. The game only draws it while Outline Mode is off.",
		db, "lootEffect", ns.DEFAULTS.lootEffect, ns.Sync)
	Checkbox(category, "outlineOff", "Keep Outline Mode off", "The game's loot sparkle takes the place of its outlines, so it needs them off. Unticking puts your outline setting back.",
		db, "outlineOff", ns.DEFAULTS.outlineOff, ns.Sync)

	-- One page per kind ----------------------------------------------------

	for _, kind in ipairs(ns.ORDER) do
		local look, defaults = db.categories[kind], ns.CATEGORY_DEFAULTS[kind]
		local page = Settings.RegisterVerticalLayoutSubcategory(category, ns.TITLE[kind])
		local function id(key) return kind .. "_" .. key end

		Checkbox(page, id("enabled"), "Sparkle", nil, look, "enabled", defaults.enabled, ns.Sync)
		if Settings.CreateColorSwatch then
			Settings.CreateColorSwatch(page, Proxy(page, id("color"), Settings.VarType.String, "Colour", look, "color", defaults.color))
		end
		Slider(page, id("size"), "Glint size", "How wide one glint is at its brightest.",
			look, "size", defaults.size, 8, 160, 1, Pixels)
		Slider(page, id("spread"), "Spread", "How far from the middle the glints appear.",
			look, "spread", defaults.spread, 0, 200, 1, Pixels)
		Slider(page, id("count"), "Glints", "How many glints there are at once. They add up where they overlap, so more of them is brighter.",
			look, "count", defaults.count, 1, 40, 1, Whole)
		Slider(page, id("brightness"), "Brightness", "100% lets a glint just reach full strength at its peak. Above that it holds full strength for longer; below it never gets there.",
			look, "brightness", defaults.brightness, 0.1, 3, 0.05, Percent)
		Slider(page, id("speed"), "Pace", "How fast the glints twinkle.",
			look, "speed", defaults.speed, 0.25, 3, 0.05, Percent)
		Slider(page, id("life"), "Glint lifetime", "How long one glint lasts at 100% pace, on average.",
			look, "life", defaults.life, 0.3, 4, 0.1, Seconds)
		Slider(page, id("height"), "Height", "Moves the sparkle up (positive) or down from the object's nameplate.",
			look, "height", defaults.height, -200, 200, 1, Pixels)
		Slider(page, id("drift"), "Drift", "How fast a glint floats up while it lasts, in pixels a second.",
			look, "drift", defaults.drift, 0, 60, 1, Pixels)
		Slider(page, id("unusable"), "When greyed out", "Brightness left while the game shows its greyed-out cursor for the object, as it does when your skill is too low.",
			look, "unusable", defaults.unusable, 0, 1, 0.05, Percent)
	end

	Settings.RegisterAddOnCategory(category)
end
