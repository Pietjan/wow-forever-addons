-- ForeverPlates in the game's options window (Options > AddOns): a check
-- box per feature on the first page, and under it a page for each feature
-- that has settings of its own. Optional: without the game's settings API
-- /fplates still does everything.

local _, ns = ...

function ns.RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory
		and Settings.RegisterProxySetting and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("ForeverPlates")

	for _, feature in ipairs(ns.features) do
		local setting = Settings.RegisterProxySetting(category, "ForeverPlates_" .. feature.key .. "_enabled",
			Settings.VarType.Boolean, feature.title, true,
			function() return feature.db.enabled end,
			function(value) ns.SetEnabled(feature, value) end)
		Settings.CreateCheckbox(category, setting, feature.tooltip)
	end

	-- The helpers a feature's Options(page, ui) builds its page with. key is
	-- the setting in the feature's saved table; get and set replace the
	-- plain read and write of it.
	for _, feature in ipairs(ns.features) do
		if feature.Options then
			local page = Settings.RegisterVerticalLayoutSubcategory(category, feature.title)
			local db, defaults = feature.db, feature.defaults
			local ui = {}

			local function Proxy(key, kind, name, default, get, set)
				if default == nil then
					default = defaults[key]
				end
				return Settings.RegisterProxySetting(page, "ForeverPlates_" .. feature.key .. "_" .. key, kind, name, default,
					get or function() return db[key] end, set or function(value) db[key] = value end)
			end
			function ui.Checkbox(key, name, tooltip, default, get, set)
				Settings.CreateCheckbox(page, Proxy(key, Settings.VarType.Boolean, name, default, get, set), tooltip)
			end
			-- A slider hands over what its arithmetic gives (0.30000000000000004):
			-- store the step it stands on.
			function ui.Slider(key, name, tooltip, min, max, step, format, default, get, set)
				set = set or function(value) db[key] = value end
				local setting = Proxy(key, Settings.VarType.Number, name, default, get, function(value)
					set(tonumber(("%.4f"):format(min + math.floor((value - min) / step + 0.5) * step)))
				end)
				local options = Settings.CreateSliderOptions(min, max, step)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
				Settings.CreateSlider(page, setting, options, tooltip)
			end
			-- choices: { value, label, tooltip } each.
			function ui.Dropdown(key, name, tooltip, choices, default, get, set)
				local function Choices()
					local container = Settings.CreateControlTextContainer()
					for _, choice in ipairs(choices) do
						container:Add(choice[1], choice[2], choice[3])
					end
					return container:GetData()
				end
				Settings.CreateDropdown(page, Proxy(key, Settings.VarType.String, name, default, get, set), Choices, tooltip)
			end

			local ok, err = pcall(feature.Options, page, ui)
			if not ok then
				ns.Print(("%s: options page incomplete (%s)"):format(feature.title, tostring(err)))
			end
		end
	end

	Settings.RegisterAddOnCategory(category)
end
