-- ForeverGuide: leveling guides shown as a section of the quest tracker.
--
-- Core.lua: the addon table, saved variables, event and signal plumbing.
local ADDON, ns = ...
ForeverGuide = ns

ns.name = ADDON

-- Settings (account wide) and their defaults.
ns.defaults = {
    arrow = true,       -- show the direction arrow
    arrowLocked = false,
    pin = true,         -- set the map pin (user waypoint) on the current goal
    watches = true,     -- track exactly the quests of the current steps
    group = true,       -- include steps for group quests
    autoNext = true,    -- load the next guide when one is finished
    skipLow = true,     -- leave out quests that are grey for the character
    pauseInDungeon = true, -- set the guide aside inside dungeons, raids and battlegrounds
    autoQuest = true,   -- accept and turn in the quests of the current steps
    cleanup = true,     -- offer to abandon leftover quests when a guide is finished
    progress = true,    -- progress bar at the top of the guide in the tracker
}

-- Who is playing; guide files are filtered on this while they load.
ns.player = {}
do
    local p = ns.player
    p.faction = UnitFactionGroup("player") or "Neutral"
    p.race = select(2, UnitRace("player")) or ""
    p.class = select(2, UnitClass("player")) or ""
    p.locale = GetLocale()
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

-- ns.On("EVENT", fn): fn(event, ...) on every firing. Events this client
-- does not know are ignored.
function ns.On(event, fn)
    local list = handlers[event]
    if not list then
        if not pcall(frame.RegisterEvent, frame, event) then
            return false
        end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        for i = 1, #list do
            list[i](event, ...)
        end
    end
end)

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------
-- In combat the game hides ("secret") values such as auras from code that
-- runs on an addon's behalf, and that includes the game's own handlers
-- when one of our calls sets them off: tracking a quest, setting the map
-- pin or asking the tracker to lay out all run Blizzard code on the spot.
-- So anything that reaches into the game's UI goes through here: at once
-- when out of combat, otherwise once when combat ends. A later call with
-- the same key replaces the earlier one.
local waiting, order = {}, {}

function ns.AfterCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    if not waiting[key] then
        order[#order + 1] = key
    end
    waiting[key] = fn
    return false
end

ns.On("PLAYER_REGEN_ENABLED", function()
    local keys, fns = order, waiting
    order, waiting = {}, {}
    for _, key in ipairs(keys) do
        fns[key]()
    end
end)

---------------------------------------------------------------------------
-- Signals between our own modules
---------------------------------------------------------------------------
local listeners = {}

function ns.Listen(signal, fn)
    local list = listeners[signal]
    if not list then
        list = {}
        listeners[signal] = list
    end
    list[#list + 1] = fn
end

function ns.Fire(signal, ...)
    local list = listeners[signal]
    if list then
        for i = 1, #list do
            list[i](...)
        end
    end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then
        return
    end
    ForeverGuideDB = ForeverGuideDB or {}
    for key, value in pairs(ns.defaults) do
        if ForeverGuideDB[key] == nil then
            ForeverGuideDB[key] = value
        end
    end
    ForeverGuideCharDB = ForeverGuideCharDB or {}
    ForeverGuideCharDB.progress = ForeverGuideCharDB.progress or {}
    ns.db = ForeverGuideDB
    ns.char = ForeverGuideCharDB
    ns.Fire("Loaded")
end)

function ns.Set(key, value)
    ns.db[key] = value
    ns.Fire("Setting", key, value)
end

function ns.Print(...)
    print("|cffffd100ForeverGuide|r:", ...)
end
