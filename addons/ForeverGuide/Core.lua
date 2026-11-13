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
-- The gate: the one way from this addon into the game's UI
---------------------------------------------------------------------------
-- In combat the game hides ("secret") values such as auras from code that
-- runs on an addon's behalf. That includes the game's own code when one of
-- our calls sets it off: tracking a quest, setting the map pin or asking
-- the tracker to redraw all make Blizzard code run for us, and part of it
-- only runs a frame or an event later.
--
-- The rules, with no exceptions:
--
--   1. Nothing here touches the game's UI unless it is quiet: out of
--      combat, and out of it for SETTLE seconds. The wait is for the work
--      the game does after our call; a fight that drops for a moment and
--      picks up again (one enemy resets, the next one arrives) must not
--      find that work still under way.
--   2. Work that cannot run now is kept, one piece per key (a later one
--      replaces the earlier), and runs when it is quiet. That is looked at
--      on a timer for as long as work is waiting, so it does not depend on
--      an event arriving.
--   3. Each piece runs on its own: an error in one is reported and does not
--      stop the others.
--   4. Every function that touches the game's UI also checks for itself
--      (ns.Guard). Through the gate that check always passes; when it does
--      not, a call got around the gate: it is refused and counted in
--      ForeverGuideDB.refused, which is where to look after a taint error.
local SETTLE = 1.5
local POLL = 0.5

-- When combat last ended; nil while in combat. Loading counts as long ago.
local quietSince = (not InCombatLockdown()) and -math.huge or nil

function ns.InCombat()
    return InCombatLockdown() or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")) or false
end

function ns.Quiet()
    if ns.InCombat() then
        quietSince = nil
        return false
    end
    if not quietSince then
        -- Combat ended and no event told us.
        quietSince = GetTime()
    end
    return GetTime() - quietSince >= SETTLE
end

ns.refused = {}

function ns.Guard(where)
    if ns.Quiet() then
        return true
    end
    ns.refused[where] = (ns.refused[where] or 0) + 1
    if ns.db then
        ns.db.refused = ns.db.refused or {}
        ns.db.refused[where] = (ns.db.refused[where] or 0) + 1
    end
    return false
end

local waiting, order = {}, {}
local reported = {}
local pumping = false

local function attempt(key, fn)
    local ok, err = pcall(fn)
    if not ok and not reported[err] then
        reported[err] = true
        ns.Print(("problem in %s: %s"):format(key, tostring(err)))
    end
end

local pump

local function flush()
    while order[1] do
        if not ns.Quiet() then
            return
        end
        local key = table.remove(order, 1)
        local fn = waiting[key]
        waiting[key] = nil
        attempt(key, fn)
    end
end

function pump()
    pumping = false
    flush()
    if order[1] and not pumping then
        pumping = true
        C_Timer.After(POLL, pump)
    end
end

-- Runs fn now when it is quiet and nothing is waiting, otherwise keeps it
-- under key until it is. Returns whether it ran now.
function ns.AfterCombat(key, fn)
    if not order[1] and ns.Quiet() then
        attempt(key, fn)
        return true
    end
    if not waiting[key] then
        order[#order + 1] = key
    end
    waiting[key] = fn
    if not pumping then
        pumping = true
        C_Timer.After(POLL, pump)
    end
    return false
end

ns.On("PLAYER_REGEN_DISABLED", function()
    quietSince = nil
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    quietSince = GetTime()
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
