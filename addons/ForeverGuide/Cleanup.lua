-- Cleanup.lua: offer to abandon the quests the guides are done with.
--
-- A quest is a leftover when it is in the log, some guide of this set has
-- to do with it (so it is not a quest the player took on their own), and
-- neither a coming step of the current guide nor any later guide mentions
-- it. A quest that is ready to hand in is never offered.
local _, ns = ...

local Engine = ns.Engine
local Registry = ns.Registry
local QL = C_QuestLog

local Cleanup = {}
ns.Cleanup = Cleanup

local function add(set, text)
    for id in text:gmatch("%d+") do
        set[tonumber(id)] = true
    end
end

local QUEST_COMMANDS = {
    accept = true, turnin = true, complete = true, daily = true, dailyturnin = true,
    isonquest = true, isquestcomplete = true, isquestturnedin = true, isquestavailable = true,
}

-- Every quest id a guide file mentions, whoever the step is for. Too many
-- is the safe side: a quest named here is kept.
local function mentioned(guide)
    if guide.questIDs then
        return guide.questIDs
    end
    local set = {}
    if guide.format == "rxp" then
        for command, ids in guide.text:gmatch("%.(%a+)[ \t]+([%d,]+)") do
            command = command:lower()
            if QUEST_COMMANDS[command] then
                -- ".complete quest,objective": only the first number is a quest
                add(set, command == "complete" and ids:match("^%d+") or ids)
            end
        end
        for id in guide.text:gmatch("%.collect[ \t]+%d+,%d+,(%d+)") do
            set[tonumber(id)] = true
        end
    elseif type(guide.source) == "function" then
        local ok, text = pcall(guide.source)
        if ok and type(text) == "string" then
            for ids in text:gmatch("|QID|([^|]+)|") do
                -- "123^456", "123&456", "123.2" (the part after the dot is a step)
                for id in ids:gmatch("(%d+)%.?%d*") do
                    set[tonumber(id)] = true
                end
            end
        end
    end
    guide.questIDs = set
    return set
end

local function union(into, set)
    for id in pairs(set) do
        into[id] = true
    end
end

-- The quests in the log the guides have no more use for, as
-- { id = , title = } in log order.
function Cleanup.Leftovers()
    local out = {}
    local guide = Engine:Current()
    if not guide or not (QL.GetNumQuestLogEntries and QL.GetInfo) then
        return out
    end
    local known, needed = {}, Engine:RemainingQuests()
    union(needed, Engine.quests)
    for _, other in ipairs(Registry.list) do
        if other.group == guide.group then
            local ids = mentioned(other)
            union(known, ids)
            if other ~= guide and (other.min or 0) >= (guide.min or 0) then
                union(needed, ids)
            end
        end
    end
    local following, guard = Registry.Next(guide), 0
    while following and guard < 100 do
        union(needed, mentioned(following))
        following, guard = Registry.Next(following), guard + 1
    end

    for i = 1, QL.GetNumQuestLogEntries() do
        local info = QL.GetInfo(i)
        local id = info and not info.isHeader and not info.isHidden and info.questID
        if id and known[id] and not needed[id] and not QL.IsComplete(id)
            and (not QL.CanAbandonQuest or QL.CanAbandonQuest(id)) then
            out[#out + 1] = { id = id, title = info.title or QL.GetTitleForQuestID(id) or ("quest " .. id) }
        end
    end
    return out
end

local function abandon(list)
    if not (QL.SetSelectedQuest and QL.SetAbandonQuest and QL.AbandonQuest) then
        ns.Print("this client does not let an addon abandon quests.")
        return
    end
    -- Abandoning goes through the quest log's selection; put back what the
    -- player had selected there.
    local selected = QL.GetSelectedQuest and QL.GetSelectedQuest()
    local names = {}
    for _, quest in ipairs(list) do
        -- Only what is still a leftover now: the popup may have been open a while.
        if QL.IsOnQuest(quest.id) then
            QL.SetSelectedQuest(quest.id)
            QL.SetAbandonQuest()
            QL.AbandonQuest()
            names[#names + 1] = quest.title
        end
    end
    if selected and selected ~= 0 and QL.IsOnQuest(selected) then
        QL.SetSelectedQuest(selected)
    end
    if #names > 0 then
        ns.Print("abandoned: " .. table.concat(names, ", "))
    end
end

-- Add our entry only. Assigning the StaticPopupDialogs global itself, even
-- to its own value, marks it as addon-owned, and then every popup of the
-- game that leads to a protected action (setting your home at an
-- innkeeper) is blocked.
StaticPopupDialogs.FOREVERGUIDE_CLEANUP = {
    text = "%s",
    button1 = "Abandon",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, list)
        ns.AfterCombat("abandon", function()
            abandon(list)
        end)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Ask. Returns false when there is nothing to clean up.
function Cleanup.Offer()
    local list = Cleanup.Leftovers()
    if #list == 0 then
        return false
    end
    if InCombatLockdown() then
        ns.Print("the quest log clean-up waits until you are out of combat.")
        ns.AfterCombat("cleanup", Cleanup.Offer)
        return true
    end
    local lines = {}
    for i, quest in ipairs(list) do
        if i > 12 then
            lines[#lines + 1] = ("and %d more"):format(#list - 12)
            break
        end
        lines[#lines + 1] = "|cffffffff" .. quest.title .. "|r"
    end
    local text = ("The guide no longer needs %s:\n\n%s\n\nAbandon %s?"):format(
        #list == 1 and "this quest" or "these quests", table.concat(lines, "\n"), #list == 1 and "it" or "them")
    if StaticPopup_Show then
        StaticPopup_Show("FOREVERGUIDE_CLEANUP", text, nil, list)
    end
    return true
end

-- When a guide is finished, once the next one (if any) has started.
local offeredFor
ns.Listen("Finished", function(finished)
    -- A finished guide reports itself on every refresh; ask once.
    if not (ns.db and ns.db.cleanup) or not finished or offeredFor == finished.key then
        return
    end
    offeredFor = finished.key
    C_Timer.After(1.5, function()
        if ns.db.cleanup and Engine:Current() and not Engine:Paused() and not InCombatLockdown() then
            Cleanup.Offer()
        end
    end)
end)
