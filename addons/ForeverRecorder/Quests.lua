-- Quests: who offers a quest (QUEST_DETAIL) and who takes it in
-- (QUEST_COMPLETE), creature or object ("npc" is whatever you talk to),
-- and what it rewards: the items given, the items to choose from, money.
-- A quest started from an item has no one offering it: only its rewards.

local _, ns = ...

local function Rewards(kind, count)
	local out = {}
	for i = 1, count or 0 do
		local item = ns.ItemID(ns.Read("quest reward", GetQuestItemLink, kind, i))
		if item then
			local ok, _, _, n = pcall(GetQuestItemInfo, kind, i)
			out[item] = ok and tonumber(ns.Plain(n)) or 1
		end
	end
	return out
end

function ns.ReadQuest(role)
	local id = ns.Read("quest id", GetQuestID)
	if not id or id == 0 then
		return
	end
	local q = ns.db.quests[id] or {}
	q.starts, q.ends = q.starts or {}, q.ends or {}
	ns.db.quests[id] = q
	local key = ns.Key(ns.Read("quest giver", UnitGUID, "npc"))
	if key then
		q[role][key] = true
		ns.Place(key)
	end
	local rewards = Rewards("reward", ns.Read("quest rewards", GetNumQuestRewards))
	local choices = Rewards("choice", ns.Read("quest choices", GetNumQuestChoices))
	if next(rewards) then
		q.rewards = rewards
	end
	if next(choices) then
		q.choices = choices
	end
	local money = ns.Read("quest money", GetRewardMoney)
	if money and money > 0 then
		q.money = money
	end
end

ns.On("QUEST_DETAIL", function()
	ns.ReadQuest("starts")
end)
ns.On("QUEST_COMPLETE", function()
	ns.ReadQuest("ends")
end)
