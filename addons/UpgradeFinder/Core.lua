-- UpgradeFinder: every piece of gear that would be an upgrade, slot by
-- slot, with where it comes from. /upgrades opens the list.
--
-- This file is the workings; Window.lua draws them.
--
-- - What exists and where it comes from is QuestieDB's: its item list, and
--   per item the quests that reward it, the mobs, chests and containers
--   that drop it and the vendors that sell it. What professions make is in
--   Data.lua, from the client's recipe tables.
-- - What an item is (slot, stats, who can wear it) is asked of the game,
--   item by item: half of the gear is not in the client's files and only
--   the running game knows it. That takes a while the first time in a
--   session.
-- - Whether it is an upgrade, and by how much, is UpgradeArrow's answer:
--   the same weights and the same comparison with what you wear.
--
-- Listed is what you could get now: an item you can equip at your level,
-- from a quest you can still do (your race and class, its level reached,
-- not handed in yet), a vendor of your side, a drop, a chest or a recipe.
-- An item with no known source is left out unless asked for.
--
-- Not known here: drop chances, the skill a recipe needs, and the random
-- "of the ..." stats a world drop can roll (it is scored without them).

local ADDON, ns = ...

local TICK = 0.05
local BUDGET = 8 -- milliseconds of work per tick
local ASK_PER_TICK = 40 -- items asked of the game per tick
local WAITING_MAX = 200 -- asked and not answered yet, at most
local GIVE_UP = 8 -- seconds to wait for an item the game does not answer for
local CONTRACT = 4 -- QuestieDB's: race masks and class keys

ns.GROUPS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
	"Finger", "Trinket", "Weapon", "Off hand", "Ranged" }
local GROUP_OF = {
	INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands",
	INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger",
	INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "Weapon", INVTYPE_2HWEAPON = "Weapon",
	INVTYPE_WEAPONMAINHAND = "Weapon", INVTYPE_WEAPONOFFHAND = "Off hand", INVTYPE_SHIELD = "Off hand",
	INVTYPE_HOLDABLE = "Off hand", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
	INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged",
}
local WEAPON, ARMOR = 2, 4 -- item classes

local db
local ready = false -- both addons this one leans on are there
local me = {} -- level, side ("A" or "H"), raceBit, classBit

ns.results = {} -- group -> { entry, ... }, unsorted
ns.phase = "idle" -- "scan", "load", "done"
ns.progress = { at = 0, of = 0, silent = 0 }

function ns.Changed() end -- the window's, once it is made

local function Now()
	return debugprofilestop()
end

-- Not bit.band: the race masks go past 32 bits.
local function HasBit(mask, bit)
	return math.floor(mask / bit) % 2 == 1
end

-- Where from --------------------------------------------------------------

local function QuestDone(quest)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted(quest)
	end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(quest) or false
end

-- A quest you could still do now.
local function QuestOpen(quest)
	if not QuestDB.Exists(quest) or QuestDone(quest) then
		return false
	end
	if (QuestDB.requiredLevel(quest) or 0) > me.level then
		return false
	end
	local oldest = QuestDB.requiredMaxLevel(quest) or 0
	if oldest ~= 0 and oldest < me.level then
		return false
	end
	local races = QuestDB.requiredRaces(quest) or 0
	if races ~= 0 and me.raceBit and not HasBit(races, me.raceBit) then
		return false
	end
	local classes = QuestDB.requiredClasses(quest) or 0
	if classes ~= 0 and me.classBit and not HasBit(classes, me.classBit) then
		return false
	end
	return true
end

-- The ways to get an item that are open to you, as { kind, id } with the
-- handiest first, and whether any way at all is known.
local function Ways(id)
	local ways, known = {}, false
	for _, npc in ipairs(ItemDB.vendors(id) or {}) do
		known = true
		local side = NpcDB.friendlyToFaction(npc)
		if not side or side:find(me.side, 1, true) then
			ways[#ways + 1] = { "vendor", npc }
		end
	end
	for _, quest in ipairs(ItemDB.questRewards(id) or {}) do
		known = true
		if QuestOpen(quest) then
			ways[#ways + 1] = { "quest", quest }
		end
	end
	if ns.crafted[id] then
		known = true
		ways[#ways + 1] = { "craft", ns.crafted[id] }
	end
	for _, npc in ipairs(ItemDB.npcDrops(id) or {}) do
		known = true
		ways[#ways + 1] = { "drop", npc }
	end
	for _, object in ipairs(ItemDB.objectDrops(id) or {}) do
		known = true
		ways[#ways + 1] = { "object", object }
	end
	for _, item in ipairs(ItemDB.itemDrops(id) or {}) do
		known = true
		ways[#ways + 1] = { "inside", item }
	end
	return ways, known
end

local RANK = { "elite", "rare elite", "boss", "rare" }

local function Place(area)
	local name = area and area > 0 and C_Map.GetAreaInfo(area) or nil
	return name and (", " .. name) or ""
end

local function Mob(npc)
	local low, high = NpcDB.minLevel(npc) or 0, NpcDB.maxLevel(npc) or 0
	local note = low > 0 and (high > low and (low .. "-" .. high) or tostring(low)) or nil
	local rank = RANK[NpcDB.rank(npc) or 0]
	if rank then
		note = note and (note .. " " .. rank) or rank
	end
	return (NpcDB.name(npc) or ("NPC " .. npc)) .. (note and (" (" .. note .. ")") or "") .. Place(NpcDB.zoneID(npc))
end

-- One way, in words.
function ns.Describe(way)
	local kind, id = way[1], way[2]
	if kind == "vendor" then
		return "Vendor: " .. (NpcDB.name(id) or ("NPC " .. id)) .. Place(NpcDB.zoneID(id))
	elseif kind == "quest" then
		local level = QuestDB.questLevel(id) or 0
		return "Quest: " .. (QuestDB.name(id) or ("quest " .. id)) .. (level > 0 and (" [" .. level .. "]") or "")
			.. Place(QuestDB.zoneOrSort(id))
	elseif kind == "craft" then
		return "Crafted: " .. (ns.professions[id] or "a profession")
	elseif kind == "drop" then
		return "Drop: " .. Mob(id)
	elseif kind == "object" then
		return "Found in: " .. (ObjectDB.name(id) or ("object " .. id)) .. Place(ObjectDB.zoneID(id))
	end
	return "Found in: " .. (ItemDB.name(id) or ("item " .. id))
end

-- The handiest way, and how many others there are.
function ns.Headline(entry)
	local ways = entry.ways
	if #ways == 0 then
		return "Source unknown"
	end
	return ns.Describe(ways[1]) .. (#ways > 1 and (" +" .. (#ways - 1)) or "")
end

-- The search ---------------------------------------------------------------

local ticker
local ids, index -- QuestieDB's item list and where the scan is in it
local candidates = {} -- item ID -> its ways
local order = {} -- the candidates, in the order they are asked for
local at, waiting, waitingCount -- the load: next in order, asked -> when
local needScan, needScore = true, true
local levelSeen = 0 -- from PLAYER_LEVEL_UP, which can come before UnitLevel follows

local function Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Gear, wearable at your level, with a way to get it.
local function Consider(id)
	-- QuestieDB lists items the game does not have; those never load.
	if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id) then
		return
	end
	local _, _, _, equipLoc, _, class = C_Item.GetItemInfoInstant(id)
	if class == nil then
		class, equipLoc = ItemDB.class(id), nil -- the slot comes with the item
	end
	if class ~= WEAPON and class ~= ARMOR then
		return
	end
	if equipLoc and not GROUP_OF[equipLoc] then
		return
	end
	if (ItemDB.requiredLevel(id) or 0) > me.level then
		return
	end
	local ways, known = Ways(id)
	if #ways == 0 and (known or not db.unknown) then
		return
	end
	candidates[id] = ways
	order[#order + 1] = id
end

-- The item has loaded: keep it when it is an upgrade.
local function Finish(id)
	local name, link, quality, _, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(id)
	local group = GROUP_OF[equipLoc or ""]
	if not (link and group) then
		return
	end
	local result = UpgradeArrow.Evaluate(link)
	if not (result and result.upgrade) then
		return
	end
	local score = result.score or 0
	local list = ns.results[group]
	if not list then
		list = {}
		ns.results[group] = list
	end
	list[#list + 1] = {
		id = id, name = name or ("item " .. id), link = link, quality = quality, icon = icon,
		empty = result.empty, gain = result.empty and score or score - (result.against or 0),
		ways = candidates[id],
	}
end

local function Loaded(id)
	return C_Item.GetItemInfo(id) ~= nil
end

local function Tick()
	local stop = Now() + BUDGET
	if ns.phase == "scan" then
		while Now() < stop do
			local id = ids[index]
			if not id then
				ns.phase, at, waiting, waitingCount = "load", 1, {}, 0
				ns.results = {}
				ns.progress = { at = 0, of = #order, silent = 0 }
				break
			end
			index = index + 1
			Consider(id)
		end
		if ns.phase == "scan" then
			ns.progress.at = index - 1
		end
	elseif ns.phase == "load" then
		local time = GetTime()
		for id, since in pairs(waiting) do
			local loaded = Loaded(id)
			if loaded or time - since > GIVE_UP then
				waiting[id] = nil
				waitingCount = waitingCount - 1
				if loaded then
					Finish(id)
				else
					ns.progress.silent = ns.progress.silent + 1
				end
			end
		end
		local asked = 0
		while at <= #order and asked < ASK_PER_TICK and waitingCount < WAITING_MAX and Now() < stop do
			local id = order[at]
			at = at + 1
			if Loaded(id) then
				Finish(id)
			else
				asked = asked + 1
				if C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(id)
				end
				waiting[id] = time
				waitingCount = waitingCount + 1
			end
		end
		ns.progress.at = at - 1 - waitingCount
		if at > #order and waitingCount == 0 then
			ns.phase = "done"
			Stop()
		end
	end
	ns.Changed()
end

-- Brings the list up to date, when something changed since it was made.
function ns.Run()
	if not ready or not (needScan or needScore) then
		return
	end
	Stop()
	if needScan then
		local _, class = UnitClass("player")
		local _, _, race = UnitRace("player")
		me.level = math.max(UnitLevel("player"), levelSeen)
		me.side = UnitFactionGroup("player") == "Alliance" and "A" or "H"
		me.raceBit = LibQuestieDB.Enum.raceMaskById[race]
		me.classBit = LibQuestieDB.Enum.classKeys[class]
		candidates, order = {}, {}
		ids, index = ItemDB.GetAllIds(), 1
		ns.phase = "scan"
		ns.progress = { at = 0, of = #ids, silent = 0 }
	else
		ns.phase, at, waiting, waitingCount = "load", 1, {}, 0
		ns.results = {}
		ns.progress = { at = 0, of = #order, silent = 0 }
	end
	needScan, needScore = false, false
	ticker = C_Timer.NewTicker(TICK, Tick)
	ns.Changed()
end

-- Something changed: the answers (score), or also what is in reach (scan).
-- The work waits until the window is looked at.
function ns.Stale(scan)
	needScan = needScan or scan or false
	needScore = true
	if ns.Shown and ns.Shown() then
		ns.Run()
	end
end

function ns.ShowUnknown(show)
	db.unknown = show and true or false
	ns.Stale(true)
end

function ns.Ready()
	return ready
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		UpgradeFinderDB = UpgradeFinderDB or {}
		db = UpgradeFinderDB
		ns.db = db
		if not (UpgradeArrow and UpgradeArrow.Evaluate and UpgradeArrow.OnChange) then
			print("|cff40c040UpgradeFinder|r: needs a newer UpgradeArrow.")
			return
		end
		if not (LibQuestieDB and ItemDB and QuestDB and NpcDB and ObjectDB) then
			print("|cff40c040UpgradeFinder|r: QuestieDB is not loaded.")
			return
		end
		local ok, message = LibQuestieDB.RequireContract(CONTRACT)
		if not ok then
			print("|cff40c040UpgradeFinder|r: " .. tostring(message))
			return
		end
		ready = true
		UpgradeArrow.OnChange(function()
			ns.Stale(false)
		end)
		self:RegisterEvent("PLAYER_LEVEL_UP")
		self:RegisterEvent("QUEST_TURNED_IN")
	else
		-- A level opens items and quests; a quest handed in closes its rewards.
		if event == "PLAYER_LEVEL_UP" then
			levelSeen = tonumber(name) or 0
		end
		ns.Stale(true)
	end
end)
