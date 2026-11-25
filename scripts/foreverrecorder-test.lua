-- Offline checks for ForeverRecorder: the game's API stood in for, the
-- addon's files loaded as the game does, its events fired, and what it
-- writes into ForeverRecorderDB checked. Secret values are stood in for by
-- a table issecretvalue knows.
--   lua5.1 scripts/foreverrecorder-test.lua
local dir = "addons/ForeverRecorder/"
local failures = 0

local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		io.write("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
	end
end

-- The game -------------------------------------------------------------------

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == SECRET end

local now = 1000
function GetTime() return now end
function date() return "2026-11-25" end
function GetBuildInfo() return "1.60.1", "71037" end
function print() end
SlashCmdList = {}

local frames = {}
function CreateFrame()
	local f = { events = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(_, fn) self.onEvent = fn end
	frames[#frames + 1] = f
	return f
end
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.onEvent then
			f.onEvent(f, event, ...)
		end
	end
end

-- Where the player stands: Westfall, 52.3%, 47.8%; or in an instance.
local inInstance = false
C_Map = {
	GetBestMapForUnit = function()
		if inInstance then return nil end
		return 1436
	end,
	GetPlayerMapPosition = function()
		return { GetXY = function() return 0.523, 0.478 end }
	end,
}
function GetInstanceInfo()
	if inInstance then
		return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36
	end
	return "Westfall", "none", 0, "", 0, 0, false, 0
end

local fighting = false
function InCombatLockdown() return fighting end
function UnitAffectingCombat() return fighting end

local spells = { [8613] = "Skinning", [2366] = "Herb Gathering", [7620] = "Fishing", [133] = "Fireball" }
C_Spell = { GetSpellName = function(id) return spells[id] end }

-- The loot window: slots of { type, link or money text, quantity, sources }.
local loot = {}
local fishingLoot = false
function GetNumLootItems() return #loot end
function GetLootSlotType(i) return loot[i].type end
function GetLootSlotLink(i) return loot[i].link end
function GetLootSlotInfo(i) return "icon", loot[i].text or "item", loot[i].quantity or 1 end
function GetLootSourceInfo(i) return unpack(loot[i].sources or {}) end
function IsFishingLoot() return fishingLoot end

local function creature(id, spawn) return "Creature-0-1-0-1436-" .. id .. "-" .. (spawn or "0000AB") end
local function object(id, spawn) return "GameObject-0-1-0-1436-" .. id .. "-" .. (spawn or "0000CD") end
local function item(id) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[Item]|h|r" end

-- Units: token -> { guid, level, ... }.
local units = {}
function UnitGUID(u) return units[u] and units[u].guid end
function UnitExists(u) return units[u] ~= nil end
function UnitPlayerControlled(u) return units[u] and units[u].player or false end
function UnitLevel(u) return units[u] and units[u].level end
function UnitName(u) return units[u] and units[u].name end
function UnitClassification(u) return units[u] and units[u].class end
function UnitCreatureType(u) return units[u] and units[u].type end
function UnitCreatureFamily(u) return units[u] and units[u].family end
function UnitReaction(u) return units[u] and units[u].reaction end
function UnitFactionGroup() return "Horde" end

-- A vendor's window: { id, price, stack, available, costs = { {value, link} } }.
local merchant = {}
function GetMerchantNumItems() return #merchant end
function GetMerchantItemID(i) return merchant[i].id end
function GetMerchantItemInfo(i)
	local m = merchant[i]
	return "name", "icon", m.price, m.stack, m.available, true, true, m.costs ~= nil
end
function GetMerchantItemCostInfo(i) return merchant[i].costs and #merchant[i].costs or 0 end
function GetMerchantItemCostItem(i, j)
	local c = merchant[i].costs[j]
	return "icon", c[1], c[2], c[3]
end

-- Talents: the Professions Legacy tree (trait system 45) is config 7;
-- Bartering is node 110286. barteringRank nil: the game gives no node.
local barteringRank = 1
C_Traits = {
	GetConfigIDBySystemID = function(system) return system == 45 and 7 or nil end,
	GetNodeInfo = function(config, node)
		if config == 7 and node == 110286 and barteringRank then
			return { currentRank = barteringRank, activeRank = barteringRank }
		end
		return {}
	end,
}

-- A quest dialog.
local quest = {}
function GetQuestID() return quest.id end
function GetNumQuestRewards() return #(quest.rewards or {}) end
function GetNumQuestChoices() return #(quest.choices or {}) end
function GetQuestItemLink(kind, i) return item((kind == "reward" and quest.rewards or quest.choices)[i][1]) end
function GetQuestItemInfo(kind, i) return "name", "icon", (kind == "reward" and quest.rewards or quest.choices)[i][2] end
function GetRewardMoney() return quest.money or 0 end

-- The addon --------------------------------------------------------------------

local ns = {}
for _, file in ipairs({ "Core.lua", "Loot.lua", "Vendors.lua", "Quests.lua", "Creatures.lua" }) do
	assert(loadfile(dir .. file))("ForeverRecorder", ns)
end
fire("ADDON_LOADED", "ForeverRecorder")
local db = ForeverRecorderDB
check("loaded: format and build", db.version == 1 and db.build == "1.60.1.71037", db.build)

-- Loot: a Saltwater Snapjaw corpse, read on LOOT_READY and LOOT_OPENED.
loot = {
	{ type = 1, link = item(4556), sources = { creature(2505), 1 } },
	{ type = 1, link = item(3712), sources = { creature(2505), 2 } },
	{ type = 2, text = "1 Silver\n20 Copper", sources = { creature(2505), 0 } },
}
fire("LOOT_READY")
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
local drop = db.loot.n2505 and db.loot.n2505.drop
check("a corpse counts once, read twice", drop and drop.looted == 1, drop and drop.looted)
check("its items, with amounts", drop and drop.items[4556].n == 1 and drop.items[3712].q == 2)
check("its money", drop and drop.money and drop.money.n == 1 and drop.money.total == 120)
check("placed where it was looted", db.spots.n2505 and db.spots.n2505["1436:523:478"] == 1)

-- Opened again: not counted again.
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
check("a corpse opened again does not count again", drop.looted == 1 and drop.items[4556].n == 1)

-- Two corpses shown at once, one item split over two slots.
loot = {
	{ type = 1, link = item(4556), sources = { creature(2505, "1"), 1, creature(2505, "2"), 1 } },
	{ type = 1, link = item(3712), sources = { creature(2505, "1"), 1 } },
	{ type = 1, link = item(3712), sources = { creature(2505, "1"), 1 } },
}
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
check("two corpses at once count as two", drop.looted == 3, drop.looted)
check("an item split over two slots is one drop of both amounts", drop.items[3712].n == 2 and drop.items[3712].q == 4,
	drop.items[3712].n .. "/" .. drop.items[3712].q)

-- Skinning the first corpse: the same GUID, another method.
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8613)
loot = { { type = 1, link = item(8167), sources = { creature(2505), 1 } } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
local skin = db.loot.n2505.skinning
check("skinning a looted corpse counts as skinning", skin and skin.looted == 1 and skin.items[8167].n == 1)
-- Long after, a plain corpse is a drop again.
now = now + 60
loot = { { type = 1, link = item(4556), sources = { creature(2505, "9"), 1 } } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
check("a spell long past names nothing", drop.looted == 4, drop.looted)

-- Gathering: a herb node.
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 2366)
loot = { { type = 1, link = item(2447), sources = { object(1617), 2 } } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
check("a node gathered", db.loot.o1617 and db.loot.o1617.gathering and db.loot.o1617.gathering.items[2447].q == 2)
-- A chest, no spell: contained.
now = now + 60
loot = { { type = 1, link = item(3371), sources = { object(2843), 1 } } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
check("a chest", db.loot.o2843 and db.loot.o2843.contained and db.loot.o2843.contained.looted == 1)

-- Fishing: two catches, each its own window, filed under the map.
fishingLoot = true
for _ = 1, 2 do
	loot = { { type = 1, link = item(6303), quantity = 1 } }
	fire("LOOT_READY")
	fire("LOOT_OPENED")
	fire("LOOT_CLOSED")
end
fishingLoot = false
local fish = db.loot.a1436 and db.loot.a1436.fishing
check("each catch counts once", fish and fish.looted == 2 and fish.items[6303].n == 2, fish and fish.looted)

-- A secret source is left out and counted.
loot = { { type = 1, link = item(4556), sources = { SECRET, 1 } } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
check("a secret source is not recorded", drop.looted == 4)
check("and counted as refused", db.secret["loot source"] == 1, db.secret["loot source"])

-- No GUID is saved anywhere.
local function hasGuid(t)
	for k, v in pairs(t) do
		if (type(k) == "string" and k:find("Creature%-")) or (type(v) == "string" and v:find("Creature%-")) then
			return true
		end
		if type(v) == "table" and hasGuid(v) then
			return true
		end
	end
	return false
end

-- Vendors.
units.npc = { guid = creature(3000), reaction = 6 }
merchant = {
	{ id = 159, price = 25, stack = 5, available = -1 },
	{ id = 18949, price = 0, stack = 1, available = 1, costs = { { 3, item(6948) }, { 10, "|Hcurrency:3402|h[Favor]|h" } } },
}
fire("MERCHANT_SHOW")
local v = db.vendors[3000]
check("a vendor's stock", v and v.seen == "2026-11-25" and v.items[159].price == 25 and v.items[159].stack == 5 and v.items[159].available == -1)
check("the discounts: standing and Bartering rank", v and v.standing == 6 and v.bartering == 1, v and (tostring(v.standing) .. " " .. tostring(v.bartering)))
check("limited stock and costs besides gold", v and v.items[18949].available == 1 and v.items[18949].costs == "i6948:3,c3402:10",
	v and v.items[18949].costs)
merchant = { { id = 117, price = 25, stack = 1, available = -1 } }
fire("MERCHANT_SHOW")
check("a visit replaces the stock", db.vendors[3000].items[117] and not db.vendors[3000].items[159])
barteringRank = nil
merchant = { { id = 117, price = 25, stack = 1, available = -1 } }
fire("MERCHANT_SHOW")
check("a rank the game does not give is left out and counted", db.vendors[3000].bartering == nil and (db.secret["bartering rank unread"] or 0) >= 1)
barteringRank = 1
fighting = true
merchant = { { id = 2287, price = 100, stack = 1, available = -1 } }
fire("MERCHANT_SHOW")
fighting = false
check("nothing read in combat", not db.vendors[3000].items[2287])

-- Quests: offered by one, taken by another; rewards and choices.
units.npc = { guid = creature(718) }
quest = { id = 192, rewards = { { 4108, 1 } }, choices = { { 4109, 1 }, { 4110, 1 } }, money = 2500 }
fire("QUEST_DETAIL")
units.npc = { guid = object(1557) }
fire("QUEST_COMPLETE")
local q = db.quests[192]
check("who offers and who takes it", q and q.starts.n718 and q.ends.o1557)
check("rewards, choices, money", q and q.rewards[4108] == 1 and q.choices[4110] == 1 and q.money == 2500)

-- Creatures.
units.target = { guid = creature(2505), name = "Saltwater Snapjaw", level = 49, class = "normal", type = "Beast", family = "Turtle", reaction = 4 }
fire("PLAYER_TARGET_CHANGED")
units.target.level = 50
fire("PLAYER_TARGET_CHANGED")
local c = db.creatures[2505]
check("a creature's name, levels, kind and reaction", c and c.name == "Saltwater Snapjaw" and c.min == 49 and c.max == 50 and c.type == "Beast" and c.family == "Turtle" and c.h == "neutral")
units.target = { guid = "Player-1-0ABC", player = true }
fire("PLAYER_TARGET_CHANGED")
check("players are not recorded", not hasGuid(db) and db.creatures["Player-1-0ABC"] == nil)
units.target = { guid = creature(6000), level = SECRET }
fire("PLAYER_TARGET_CHANGED")
check("a secret level is left out", db.creatures[6000] and db.creatures[6000].min == nil and db.secret.level == 1)
units.target = { guid = creature(6001), player = SECRET }
fire("PLAYER_TARGET_CHANGED")
check("a unit the game will not say is a creature is skipped", db.creatures[6001] == nil)

-- In an instance with no map position: filed under the instance.
inInstance = true
loot = { { type = 1, link = item(5195), sources = { creature(639), 1 } } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
inInstance = false
check("in an instance, its map", db.spots.n639 and db.spots.n639.i36 == 1)

check("no GUID saved", not hasGuid(db))
check("/recorder reads", ns.Summary()[1]:find("1.60.1.71037", 1, true) ~= nil, ns.Summary()[1])

if failures > 0 then
	io.write(failures .. " failed\n")
	os.exit(1)
end
io.write("ok\n")
