-- Options.lua: the game's options window (Options > AddOns), with the
-- settings of the guide menu's Options list as check boxes. Each one goes
-- through ns.Set, as the menu's do, so the rest of the addon hears about it
-- the same way. Optional: without the game's settings API the menu still
-- has them all.
local _, ns = ...

-- In the menu's order: key, the menu's text, a longer word on it.
local OPTIONS = {
    { "arrow", "Direction arrow", "An arrow that points to the current goal." },
    { "arrowLocked", "Lock the arrow in place", "The arrow can no longer be dragged." },
    { "progress", "Progress bar", "A progress bar at the top of the guide in the tracker." },
    { "pin", "Map pin on the current goal", "Sets the map pin (your waypoint) on the current goal." },
    { "watches", "Track only the quests of the current step", "Keeps the quest tracker to the quests the current steps are about." },
    { "group", "Include group quests", "Includes the steps for group quests." },
    { "skipLow", "Skip quests too low for my level", "Leaves out quests that are grey for you and not in your log, with their follow-ups." },
    { "autoQuest", "Accept and turn in guide quests for me", "Only the quests of the current steps." },
    { "pauseInDungeon", "Pause inside dungeons", "Sets the guide aside inside dungeons, raids and battlegrounds." },
    { "cleanup", "Offer to clean up the quest log after a guide", "Offers to abandon the quests a finished guide left behind." },
    { "autoNext", "Continue with the next guide", "Loads the next guide when one is finished." },
}

local function register()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
        and Settings.CreateCheckbox) then
        return
    end
    local category = Settings.RegisterVerticalLayoutCategory("ForeverGuide")
    for _, option in ipairs(OPTIONS) do
        local key, name, tooltip = option[1], option[2], option[3]
        local setting = Settings.RegisterProxySetting(category, "ForeverGuide_" .. key, Settings.VarType.Boolean, name,
            ns.defaults[key],
            function()
                return ns.db[key] and true or false
            end,
            function(value)
                ns.Set(key, value)
            end)
        Settings.CreateCheckbox(category, setting, tooltip)
    end
    Settings.RegisterAddOnCategory(category)
end

ns.Listen("Loaded", function()
    local ok, err = pcall(register)
    if not ok then
        ns.Print("options panel unavailable (" .. tostring(err) .. "); the guide menu has the options.")
    end
end)
