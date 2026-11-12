-- Auto.lua: take and hand in the quests of the current steps.
--
-- Only quests the shown guide steps ask for are touched; every other quest
-- an NPC offers is left to the player. A reward with a choice is left to
-- the player too. Hold Shift while talking to do it all by hand.
local _, ns = ...

local Engine = ns.Engine

local function ready()
    if not (ns.db and ns.db.autoQuest) or not Engine:Current() or IsShiftKeyDown() or InCombatLockdown() then
        return false
    end
    -- The step may have moved on with the quest that was just handed in.
    Engine:Refresh()
    return not Engine:Paused()
end

-- The NPC's own list of quests (the gossip window).
ns.On("GOSSIP_SHOW", function()
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) or not ready() then
        return
    end
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if quest.isComplete and Engine:Wants("turnin", quest.questID) then
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if Engine:Wants("accept", quest.questID) then
            C_GossipInfo.SelectAvailableQuest(quest.questID)
            return
        end
    end
end)

-- The same list for NPCs that have nothing else to say.
ns.On("QUEST_GREETING", function()
    if not (GetActiveQuestID and GetAvailableQuestInfo) or not ready() then
        return
    end
    for i = 1, GetNumActiveQuests() do
        local _, complete = GetActiveTitle(i)
        if complete and Engine:Wants("turnin", GetActiveQuestID(i)) then
            SelectActiveQuest(i)
            return
        end
    end
    for i = 1, GetNumAvailableQuests() do
        local _, _, _, _, quest = GetAvailableQuestInfo(i)
        if Engine:Wants("accept", quest) then
            SelectAvailableQuest(i)
            return
        end
    end
end)

ns.On("QUEST_DETAIL", function()
    if not ready() or not Engine:Wants("accept", GetQuestID()) then
        return
    end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        -- Already in the log; the window only needs closing.
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end)

ns.On("QUEST_PROGRESS", function()
    if ready() and Engine:Wants("turnin", GetQuestID()) and IsQuestCompletable() then
        CompleteQuest()
    end
end)

ns.On("QUEST_COMPLETE", function()
    if not ready() or not Engine:Wants("turnin", GetQuestID()) then
        return
    end
    -- A quest that costs money asks for a confirmation; leave that one.
    local choices = GetNumQuestChoices()
    local cost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if choices <= 1 and cost == 0 then
        GetQuestReward(choices)
    end
end)
