-- Watches.lua: the guide decides which quests the tracker shows.
--
-- While a guide runs, the watched quests are exactly the quests the
-- current steps work on. Everything else in the log is unwatched, so the
-- tracker's quest section reads as the detail of the guide step above it.
local _, ns = ...

local Engine = ns.Engine
local QL = C_QuestLog

local syncing = false
local managed = {} -- the quests the current steps had us track

local function sync()
    if syncing or not (ns.db and ns.db.watches) or not Engine:Current() then
        return
    end
    if Engine.view.paused then
        -- Paused: let go of the guide's quests and leave the list to the
        -- player from here.
        syncing = true
        for quest in pairs(managed) do
            QL.RemoveQuestWatch(quest)
        end
        managed = {}
        syncing = false
        return
    end
    if Engine.view.finished then
        return
    end
    syncing = true
    local wanted = Engine.quests
    managed = wanted

    -- Drop what the steps do not need.
    local watched = {}
    for i = QL.GetNumQuestWatches(), 1, -1 do
        local quest = QL.GetQuestIDForQuestWatchIndex(i)
        if quest then
            if wanted[quest] then
                watched[quest] = true
            else
                QL.RemoveQuestWatch(quest)
            end
        end
    end
    -- Add what they do.
    local limit = Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES or 25
    for quest in pairs(wanted) do
        if not watched[quest] and QL.IsOnQuest(quest) and QL.GetNumQuestWatches() < limit then
            QL.AddQuestWatch(quest)
        end
    end
    syncing = false
end

local function request()
    ns.AfterCombat("watches", sync)
end

ns.Listen("Updated", request)

local scheduled = false
local function later()
    if scheduled or syncing then
        return
    end
    scheduled = true
    C_Timer.After(0.3, function()
        scheduled = false
        request()
    end)
end

-- The game watches a quest by itself when it is accepted, and the player
-- can change the list; put it back.
ns.On("QUEST_WATCH_LIST_CHANGED", later)
ns.On("QUEST_LOG_UPDATE", later)

ns.Listen("Setting", function(key, value)
    if key == "watches" and value then
        request()
    end
end)
