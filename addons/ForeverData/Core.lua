-- ForeverData: WoW Forever's game data for other addons, read through the
-- global ForeverData table. The data files (Data/*.lua) are written by
-- `forever addon` in wow-forever-data, which documents their format; each
-- thing is a packed string, decoded the first time it is asked for.
--
-- A consumer lists ForeverData in its .toc (Dependencies or OptionalDeps)
-- and checks the contract before reading:
--
--   if ForeverData and ForeverData.RequireContract(1) then ... end
--
-- Tables handed out are shared and cached: read them, do not change them.
-- Chances are percentages (0.68 is 0.68%); nil where unknown.
local ADDON, ns = ...

local CONTRACT = 1

local KIND_CODE = { npc = "n", object = "o", item = "i", zone = "a" }
local KIND_NAME = { n = "npc", o = "object", i = "item", a = "zone" }
local METHOD = { d = "drop", k = "skinning", p = "pickpocketing", c = "contained", f = "fishing", e = "disenchanting" }
-- How a chance is known: counted in Forever, counted in Classic Era, a
-- percentage wowhead shows, CMaNGOS's Classic table, or only seen dropping.
local BASIS = { f = "forever", e = "classicEra", s = "shown", c = "classic", v = "seen" }
local REACTION = { h = "hostile", n = "neutral", f = "friendly" }
local INSTANCE = { d = "dungeon", r = "raid", b = "battleground" }

local EMPTY = {}

-- split cuts s at each sep (plain), keeping empty fields.
local function split(s, sep)
	local out, start = {}, 1
	while true do
		local at = string.find(s, sep, start, true)
		if not at then
			out[#out + 1] = string.sub(s, start)
			return out
		end
		out[#out + 1] = string.sub(s, start, at - 1)
		start = at + #sep
	end
end

local function number(s)
	if s == nil or s == "" then
		return nil
	end
	return tonumber(s)
end

local function text(s)
	if s == nil or s == "" then
		return nil
	end
	return s
end

-- cached makes a lookup that decodes once per key; weak, so what nobody
-- holds on to can be collected.
local function cached(decode)
	local cache = setmetatable({}, { __mode = "v" })
	return function(key)
		if key == nil then
			return nil
		end
		local v = cache[key]
		if v == nil then
			v = decode(key)
			if v ~= nil then
				cache[key] = v
			end
		end
		return v
	end
end

local item = cached(function(id)
	local s = ns.items and ns.items[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	return {
		id = id, name = f[1], quality = number(f[2]), class = number(f[3]), subclass = number(f[4]),
		itemLevel = number(f[5]), requiredLevel = number(f[6]), available = f[7] == "1",
		widespread = string.sub(f[8] or "", 1, 1) == "*",
	}
end)

local npc = cached(function(id)
	local s = ns.npcs and ns.npcs[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	local reaction = f[6] or ""
	return {
		id = id, name = f[1], title = text(f[2]), minLevel = number(f[3]), maxLevel = number(f[4]),
		rank = number(f[5]), alliance = REACTION[string.sub(reaction, 1, 1)], horde = REACTION[string.sub(reaction, 2, 2)],
		boss = f[7] == "1", display = number(f[8]), kind = text(f[9]),
	}
end)

local object = cached(function(id)
	local s = ns.objects and ns.objects[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	return { id = id, name = f[1], type = number(f[2]) }
end)

-- refs decodes "n2505,o1731,i8167" into {kind, id} rows; an "f" ref (a
-- reputation objective, "f72:3000") becomes {kind = "faction", id, standing}.
local function refs(s)
	local out = {}
	if s == nil or s == "" then
		return out
	end
	for _, r in ipairs(split(s, ",")) do
		local code = string.sub(r, 1, 1)
		if code == "f" then
			local faction, standing = string.match(r, "^f(%d+):(-?%d*)$")
			out[#out + 1] = { kind = "faction", id = tonumber(faction), standing = number(standing) }
		else
			out[#out + 1] = { kind = KIND_NAME[code], id = tonumber(string.sub(r, 2)) }
		end
	end
	return out
end

local function ids(s)
	local out = {}
	if s == nil or s == "" then
		return out
	end
	for _, v in ipairs(split(s, ",")) do
		out[#out + 1] = tonumber(v)
	end
	return out
end

local SIDE = { a = "alliance", h = "horde" }

-- repPair reads "faction:value": {faction, value}, nil for "".
local function repPair(s)
	local faction, value = string.match(s or "", "^(%d+):(-?%d+)$")
	return faction and { faction = tonumber(faction), value = tonumber(value) } or nil
end

-- itemCounts reads "item" or "item:n", comma-separated: {{item, n}, ...}.
local function itemCounts(s)
	local out = {}
	for part in string.gmatch(s or "", "[^,]+") do
		local item, n = string.match(part, "^(%d+):?(%d*)$")
		if item then
			out[#out + 1] = { item = tonumber(item), n = tonumber(n) or 1 }
		end
	end
	return out
end

-- rankList reads "skill line:value,...": {{line, value}, ...}.
local function rankList(s)
	local out = {}
	for line, value in string.gmatch(s or "", "(%d+):(-?%d+)") do
		out[#out + 1] = { line = tonumber(line), value = tonumber(value) }
	end
	return out
end

local quest = cached(function(id)
	local s = ns.quests and ns.quests[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	local reputation = {}
	for _, r in ipairs(f[15] and f[15] ~= "" and split(f[15], ",") or EMPTY) do
		local faction, value = string.match(r, "^(%d+):(-?%d+)$")
		reputation[#reputation + 1] = { faction = tonumber(faction), value = tonumber(value) }
	end
	return {
		id = id, name = text(f[1]), level = number(f[2]), requiredLevel = number(f[3]), new = f[4] == "1",
		side = SIDE[f[5]], classes = number(f[6]), zone = number(f[7]), skillLine = number(f[8]), skill = number(f[9]),
		repeatable = f[10] == "1", starts = refs(f[11]), ends = refs(f[12]), objectives = refs(f[13]),
		rewards = ids(f[14]), reputation = reputation, requiresAll = ids(f[16]), requiresOne = ids(f[17]),
		next = number(f[18]), text = text(f[19]), races = ids(f[20]),
		-- What else it asks before it is offered.
		maxLevel = number(f[21]), minRep = repPair(f[22]), maxRep = repPair(f[23]), needsItems = ids(f[24]),
		spell = number(f[25]), specialization = number(f[26]), untilQuest = number(f[27]), fromQuest = number(f[28]),
		disabledBy = number(f[29]), ranks = rankList(f[30]),
		-- The rewards as the quest log shows them: items to choose one of,
		-- items given, {item, n} each; experience at its own level, money.
		choices = itemCounts(f[31]), given = itemCounts(f[32]), xp = number(f[33]), money = number(f[34]),
	}
end)

-- questsOf decodes the quests a thing is part of: "s123,e456,o789,r12,z34".
local QUEST_ROLE = { s = "start", e = "end", o = "objective", r = "reward", z = "zone" }
local questsOf = cached(function(ref)
	local code, id = string.sub(ref, 1, 1), tonumber(string.sub(ref, 2))
	local s = ns.questsOf and ns.questsOf[code] and ns.questsOf[code][id]
	if not s then
		return nil
	end
	local rows = {}
	for _, r in ipairs(split(s, ",")) do
		rows[#rows + 1] = { quest = tonumber(string.sub(r, 2)), role = QUEST_ROLE[string.sub(r, 1, 1)] }
	end
	return rows
end)

local zone = cached(function(id)
	local s = ns.zones and ns.zones[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	return { id = id, name = f[1], parent = number(f[2]), instance = INSTANCE[f[3] or ""], map = number(f[4]) }
end)

-- amounts decodes how many come at once: "1-2" 1, 2; "3" 3, 3; nothing
-- when it is one or not known.
local function amounts(s)
	local low, high = string.match(s or "", "^(%d+)%-(%d+)$")
	if low then
		return tonumber(low), tonumber(high)
	end
	return number(s), number(s)
end

-- lootOf decodes what one thing gives: "item,method,chance,sample,basis;...",
-- each with ",amount" after it where more than one comes at once.
local lootOf = cached(function(ref)
	local code, id = string.sub(ref, 1, 1), tonumber(string.sub(ref, 2))
	local s = ns.loot and ns.loot[code] and ns.loot[code][id]
	if not s then
		return nil
	end
	local rows = {}
	for _, row in ipairs(split(s, ";")) do
		local f = split(row, ",")
		local low, high = amounts(f[6])
		rows[#rows + 1] = {
			item = tonumber(f[1]), method = METHOD[f[2]], chance = number(f[3]), sample = number(f[4]), basis = BASIS[f[5]],
			low = low, high = high,
		}
	end
	return rows
end)

local function decodePoint(s, at)
	return tonumber(string.sub(s, at, at + 1), 36) / 10
end

local spawnsOf = cached(function(ref)
	local code, id = string.sub(ref, 1, 1), tonumber(string.sub(ref, 2))
	local s = ns.spawns and ns.spawns[code] and ns.spawns[code][id]
	if not s then
		return nil
	end
	local out = {}
	for _, part in ipairs(split(s, ";")) do
		local colon = string.find(part, ":", 1, true)
		local zoneID, points = tonumber(string.sub(part, 1, colon - 1)), string.sub(part, colon + 1)
		if points == "" then
			out[#out + 1] = { zone = zoneID }
		end
		for at = 1, #points - 3, 4 do
			out[#out + 1] = { zone = zoneID, x = decodePoint(points, at), y = decodePoint(points, at + 2) }
		end
	end
	return out
end)

local vendors = cached(function(id)
	local s = ns.vendors and ns.vendors[id]
	if not s then
		return nil
	end
	local rows = {}
	for _, row in ipairs(split(s, ";")) do
		local f = split(row, ",")
		rows[#rows + 1] = { npc = number(f[1]), price = number(f[2]), currency = number(f[3]), stock = number(f[4]), standing = number(f[5]) }
	end
	return rows
end)

local trainers = cached(function(id)
	local s = ns.trainers and ns.trainers[id]
	if not s then
		return nil
	end
	local rows = {}
	for _, row in ipairs(split(s, ";")) do
		local f = split(row, ",")
		rows[#rows + 1] = { npc = number(f[1]), skillLine = number(f[2]), skill = number(f[3]), level = number(f[4]), cost = number(f[5]) }
	end
	return rows
end)

ForeverData = {}
local FD = ForeverData

-- The data's version: contract, when it was made, and each source's
-- version ({client = "1.60.1.71037", questie = "1.1.5", ...}).
FD.meta = ns.meta or { sources = {} }

-- True when the data is of the layout a consumer was written for.
function FD.RequireContract(n)
	return n == CONTRACT and FD.meta.contract == CONTRACT
end

-- {id, name, quality, class, subclass, itemLevel, requiredLevel,
-- available, widespread}: available is false for test, unused and not yet
-- released items (not available to players by wowhead); widespread is true
-- for an item creatures or objects give in five zones or more (a world
-- drop, or turtle meat): a zone filter counts it only where it is given
-- at 1% or better.
function FD.Item(id) return item(id) end

-- {id, name, title, minLevel, maxLevel, rank, alliance, horde, boss, display, kind}: rank
-- 0 normal, 1 elite, 2 rare elite, 3 boss (a world boss), 4 rare; alliance
-- and horde how it takes that side's players, "hostile", "neutral" (you can
-- attack it, it does not attack you) or "friendly", from its faction; nil
-- when unknown. boss is true for a dungeon or raid boss: named as one of
-- the client's boss encounters, in that encounter's instance. display is
-- the creature display ID wowhead shows its model with, for
-- SetPortraitTextureFromCreatureDisplayID; nil when unknown.
-- kind is its family ("Cat", "Turtle") or else its type ("Humanoid",
-- "Undead"); nil when unknown.
function FD.Npc(id) return npc(id) end

-- {id, name, type}: type 3 chest (veins and herbs too), 25 fishing hole.
function FD.Object(id) return object(id) end

-- {id, name, level, requiredLevel, new, side, classes, zone, skillLine,
-- skill, repeatable, starts, ends, objectives, rewards, reputation,
-- requiresAll, requiresOne, next, text}: name nil for the few quests known
-- only by who starts and ends them; new true for quests new in Forever;
-- side "alliance" or "horde", nil for both; classes a class mask (bit n-1
-- for class n), nil for all; zone an area; skillLine and skill a
-- profession and level it asks. starts, ends and objectives are rows
-- {kind, id}: kind "npc", "object" or "item", or for a reputation
-- objective "faction" with standing. rewards are item IDs, reputation rows
-- {faction, value}; requiresAll the quests all needed first, requiresOne
-- those of which one is; next the quest it leads to; text what to do, as
-- QuestieDB writes it ($N your name, $B a new line).
function FD.Quest(id) return quest(id) end

-- The quests a thing is part of: kind "npc", "object", "item" or "zone".
-- Rows {quest, role}: role "start", "end", "objective", "reward", or for a
-- zone "zone" (the quests filed under it).
function FD.QuestsOf(kind, id)
	local code = KIND_CODE[kind]
	if not code or not id then
		return EMPTY
	end
	return questsOf(code .. id) or EMPTY
end

-- A race of Forever's, by ID: {id, name, side "alliance" or "horde"}; a
-- quest's races (quest.races) are these, listed only for a quest some
-- races of Forever may not take.
local RACE_SIDE = { a = "alliance", h = "horde" }
function FD.Race(id)
	local s = ns.races and ns.races[id]
	if not s then
		return nil
	end
	local name, side = string.match(s, "^([^|]*)|(%a*)$")
	return { id = id, name = name, side = RACE_SIDE[side] }
end

-- Forever's races, by ID.
function FD.Races()
	local out = {}
	for id in pairs(ns.races or EMPTY) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

-- A faction's name, for a quest's reputation.
function FD.Faction(id)
	return ns.factions and ns.factions[id]
end

-- A class's name (1 Warrior .. 11 Druid), for a quest's classes.
function FD.ClassName(id)
	return ns.classes and ns.classes[id]
end

-- A profession's name by skill line (164 Blacksmithing), for a quest's skillLine.
function FD.SkillName(line)
	local s = ns.skills and ns.skills[line]
	return s and (string.match(s, "^([^|]*)")) or nil
end

-- A profession's icon (a file ID), nil when the data has none.
function FD.SkillIcon(line)
	local s = ns.skills and ns.skills[line]
	return s and tonumber(string.match(s, "|(%d+)$") or "") or nil
end

-- A spell's name, for a quest that asks it known (or not) or a
-- specialisation.
function FD.SpellName(id)
	return ns.spells and ns.spells[id]
end

-- The skill line of a profession by name, any case ("fishing" 356); nil
-- when no quest needs one of that name.
function FD.SkillLine(name)
	local lower = type(name) == "string" and string.lower(name)
	for line, n in pairs(ns.skills or EMPTY) do
		if string.lower((string.match(n, "^([^|]*)"))) == lower then
			return line
		end
	end
	return nil
end

-- An area and every area inside it, at any depth: {12, 9, 24, ...} for
-- Elwynn Forest, Northshire Valley, Northshire Abbey and the rest.
local children
function FD.Subzones(id)
	if not children then
		children = {}
		for child, s in pairs(ns.zones or EMPTY) do
			local parent = tonumber(string.match(s, "^[^|]*|(%d+)") or "")
			if parent then
				children[parent] = children[parent] or {}
				table.insert(children[parent], child)
			end
		end
	end
	local out, at = { id }, 1
	while out[at] and at <= 1000 do
		for _, child in ipairs(children[out[at]] or EMPTY) do
			out[#out + 1] = child
		end
		at = at + 1
	end
	return out
end

-- The wings of an instance: the areas in it that are instances themselves
-- (Scarlet Monastery's four), in order; none for any other.
function FD.Wings(id)
	local out = {}
	for _, area in ipairs(FD.Subzones(id)) do
		local z = area ~= id and FD.Zone(area)
		if z and z.instance then
			out[#out + 1] = area
		end
	end
	table.sort(out)
	return out
end

-- The level of what one fights in a zone, as the generator worked it out
-- (Data/Levels.lua): low, high; nil when too few creatures say, or for data
-- made before it did (ok then false: the caller works it out itself).
function FD.ZoneLevels(id)
	if not ns.levels then
		return nil, nil, false
	end
	local s = ns.levels[id]
	if not s then
		return nil, nil, true
	end
	local low, high = string.match(s, "^(%d*),(%d*)")
	return tonumber(low), tonumber(high), true
end

-- The level the game's dungeon finder gives a dungeon, raid or wing: one
-- level, a level or two below what one fights there (Wailing Caverns 17,
-- its creatures 19-21), for ordering them; nil for none, or for data made
-- before it was shipped.
function FD.FinderLevel(id)
	local s = ns.levels and ns.levels[id]
	return s and tonumber(string.match(s, "^%d*,%d*,(%d+)$")) or nil
end

-- {id, name, parent, instance, map}: an area; parent nil for a zone or an
-- instance; instance "dungeon", "raid" or "battleground" for an instance's
-- own area, else nil; map the game map (UiMap) the x and y of spawns in it
-- are of, nil when unknown.
function FD.Zone(id) return zone(id) end

-- What a thing gives: kind "npc", "object", "item" (a container) or
-- "zone" (fishing). Rows {item, method, chance, sample, basis, low, high},
-- likeliest first; sample is the kills or opens a counted chance is over;
-- low and high how many come at once (1-2 Silk Cloth), nil for one or
-- unknown.
function FD.Loot(kind, id)
	local code = KIND_CODE[kind]
	if not code or not id then
		return EMPTY
	end
	return lootOf(code .. id) or EMPTY
end

-- Whether a thing gives anything, without decoding what.
function FD.HasLoot(kind, id)
	local code = KIND_CODE[kind]
	return code ~= nil and ns.loot ~= nil and ns.loot[code] ~= nil and ns.loot[code][id] ~= nil
end

-- Where an item comes from. Rows {kind, id, method, chance, sample, basis,
-- low, high} (see FD.Loot).
-- pause, if given, is called every 25 sources (see FD.Search's options.pause).
-- Only the item's own rows of each source's loot are read: a source's whole
-- table is not decoded (Linen Cloth has 773 sources, each with dozens of
-- items; decoding them all took 300 ms).
function FD.Drops(itemID, pause)
	local refs = ns.drops and ns.drops[itemID]
	if not refs then
		return EMPTY
	end
	local out = {}
	local key = itemID .. ","
	for n, ref in ipairs(split(refs, ",")) do
		if pause and n % 25 == 0 then
			pause()
		end
		local code, id = string.sub(ref, 1, 1), tonumber(string.sub(ref, 2))
		local s = ns.loot and ns.loot[code] and ns.loot[code][id]
		-- Each "item,method,chance,sample,basis" row of the item: one at the
		-- start, or after a ";".
		local start = s and string.sub(s, 1, #key) == key and 1 or nil
		local from = 1
		while s do
			if not start then
				local hit = string.find(s, ";" .. key, from, true)
				if not hit then
					break
				end
				start = hit + 1
			end
			local stop = string.find(s, ";", start, true)
			local f = split(string.sub(s, start, stop and stop - 1 or -1), ",")
			local low, high = amounts(f[6])
			out[#out + 1] = {
				kind = KIND_NAME[code], id = id,
				method = METHOD[f[2]], chance = number(f[3]), sample = number(f[4]), basis = BASIS[f[5]],
				low = low, high = high,
			}
			if not stop then
				break
			end
			from, start = stop, nil
		end
	end
	return out
end

-- Where a creature or object stands: rows {zone, x, y}, x and y 0-100 on
-- the zone's map; nil x and y in a place without a map (a dungeon).
function FD.Spawns(kind, id)
	local code = KIND_CODE[kind]
	if (code ~= "n" and code ~= "o") or not id then
		return EMPTY
	end
	return spawnsOf(code .. id) or EMPTY
end

-- What killing a creature of the open world is worth on average, in copper:
-- {items, coin, basis}: items what a vendor pays for its drops, coin the
-- money it drops (Classic's); basis what most of items is from, "forever"
-- or "classic_era" (counted there) or "classic_table", nil without items.
-- nil when not known, or for a creature only in instances.
local WORTH_BASIS = { f = "forever", e = "classic_era", c = "classic_table" }
function FD.Worth(npcID)
	local s = ns.worth and ns.worth[npcID]
	local items, coin, basis = string.match(s or "", "^(%d+),(%d+),(%a*)$")
	if not items then
		return nil
	end
	return { items = tonumber(items), coin = tonumber(coin), basis = WORTH_BASIS[basis] }
end

-- What a reagent is used in: rows {spell, name, skillLine, item, skill,
-- count}: the recipe's spell and name, its profession, the item it makes
-- (nil for an enchantment), the skill it asks (nil unknown) and how many of
-- the reagent it takes. Lowest skill first.
local usedIn = cached(function(itemID)
	local spells = ns.uses and ns.uses[itemID]
	if not spells then
		return nil
	end
	local rows = {}
	for _, spell in ipairs(split(spells, ",")) do
		spell = tonumber(spell)
		local s = ns.recipes and ns.recipes[spell]
		if s then
			local f = split(s, "|")
			local made = number(f[3])
			local name, count = f[1], nil
			if name == "" then
				local it = made and item(made)
				name = it and it.name or ""
			end
			for _, reagent in ipairs(split(f[5] or "", ",")) do
				local id, n = string.match(reagent, "^(%d+):(%d+)$")
				if tonumber(id) == itemID then
					count = tonumber(n)
				end
			end
			rows[#rows + 1] = { spell = spell, name = name, skillLine = number(f[2]), item = made, skill = number(f[4]), count = count }
		end
	end
	table.sort(rows, function(a, b)
		if (a.skill or 0) ~= (b.skill or 0) then
			return (a.skill or 0) < (b.skill or 0)
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.spell < b.spell
	end)
	return rows
end)
function FD.UsedIn(itemID) return usedIn(itemID) or EMPTY end

-- How an item is made: rows {spell, name, skillLine, skill, reagents,
-- patterns}: the recipe's spell and name, its profession, the skill it asks
-- (nil unknown), reagents as {item, count} in the recipe's order, and the
-- items that teach it (empty when only trainers do: FD.Trainers(spell)).
-- Lowest skill first.
local createdBy = cached(function(itemID)
	local spells = ns.made and ns.made[itemID]
	if not spells then
		return nil
	end
	local rows = {}
	for _, spell in ipairs(split(spells, ",")) do
		spell = tonumber(spell)
		local s = ns.recipes and ns.recipes[spell]
		if s then
			local f = split(s, "|")
			local name = f[1]
			if name == "" then
				local it = item(itemID)
				name = it and it.name or ""
			end
			local reagents, patterns = {}, {}
			for _, reagent in ipairs(split(f[5] or "", ",")) do
				local id, n = string.match(reagent, "^(%d+):(%d+)$")
				if id then
					reagents[#reagents + 1] = { item = tonumber(id), count = tonumber(n) }
				end
			end
			for _, id in ipairs(split(f[6] or "", ",")) do
				patterns[#patterns + 1] = tonumber(id)
			end
			rows[#rows + 1] = { spell = spell, name = name, skillLine = number(f[2]), skill = number(f[4]), reagents = reagents, patterns = patterns }
		end
	end
	table.sort(rows, function(a, b)
		if (a.skill or 0) ~= (b.skill or 0) then
			return (a.skill or 0) < (b.skill or 0)
		end
		return a.spell < b.spell
	end)
	return rows
end)
function FD.CreatedBy(itemID) return createdBy(itemID) or EMPTY end

-- Who sells an item: rows {npc, price, currency, stock, standing}. price
-- in copper, or in currency when currency is set (3402 Merchant's Favor);
-- stock nil for unlimited; standing the reputation asked (4 neutral .. 8
-- exalted), nil for none.
function FD.Vendors(itemID) return vendors(itemID) or EMPTY end

-- What a vendor sells: item IDs; FD.Vendors(item) has its price there.
function FD.Sells(npcID)
	local s = ns.sells and ns.sells[npcID]
	if not s then
		return EMPTY
	end
	return ids(s)
end

-- Who teaches a recipe (its spell): rows {npc, skillLine, skill, level, cost}.
function FD.Trainers(spellID) return trainers(spellID) or EMPTY end

-- Search ----------------------------------------------------------------------

local SEARCHED = { "item", "npc", "object", "quest", "zone" }
local SOURCE = { item = "items", npc = "npcs", object = "objects", quest = "quests", zone = "zones" }
local index = {}

-- buildNames makes a kind's search list: {id, lower-case name, name, words
-- in the name, lower-case title (creatures with one)}. With pause, it
-- calls pause() every few hundred names, so a coroutine can spread the
-- work over frames.
local function buildNames(kind, pause)
	local list = {}
	local n = 0
	for id, s in pairs(ns[SOURCE[kind]] or EMPTY) do
		n = n + 1
		if pause and n % 500 == 0 then
			pause()
		end
		local bar = string.find(s, "|", 1, true)
		local name = bar and string.sub(s, 1, bar - 1) or s
		-- Names the client keeps for its own use ("[PH] Hakkar'i Urn",
		-- "Hidden Belt (DNT)") are not in the data: the generator leaves
		-- them out, and refuses data that holds one.
		if name ~= "" then
			local _, words = string.gsub(name, "%S+", "")
			local title
			if kind == "npc" and bar then
				title = string.match(s, "^([^|]*)", bar + 1)
				title = title ~= "" and string.lower(title) or nil
			end
			list[#list + 1] = { id, string.lower(name), name, words, title }
		end
	end
	return list
end

-- names is a kind's search list, built on first use if not built yet.
local function names(kind)
	local list = index[kind]
	if not list then
		list = buildNames(kind)
		index[kind] = list
	end
	return list
end

-- Fuzzy search, as a command palette ranks: each word typed must match
-- the name somehow, and the name scores by how well each did:
--   100  the name starts with it          "turtle" Turtle Scale
--    85  a word of the name starts with it "scale"  Turtle Scale
--   +15  and it is that whole word         "silk"   Silk Cloth over Silky Gown
--    60  it is inside the name            "urtl"
--   -15  only a creature's title has it   "banker" (title <Banker>)
--    45  a word of the name is one typo away (4 letters or more) "tutrle"
--    42  a word of the name starts one typo away (6 letters or more) "rocknu"
--  30-40 its letters are in the name in order (3 letters or more) "trtl",
--        the closer together the better
-- Within a score, shorter names first. The search is staged: first only
-- the plain tiers (100, 85, 60); typos only when that finds nothing, starts
-- of words only when typos find nothing, and letters in order only when
-- neither does, so a near miss never
-- pads a list of better matches. Typos are found against the distinct words
-- of all names, not every name.

-- wordsBy collects the distinct words of all names searched, by first
-- letter, on first use.
-- It also keeps, for each word, the names it is a whole word of (kind,
-- entry, kind, entry, ...): a typo word leads straight to its names, not
-- through all of them (48,054).
local wordsByFirst, namesByWord
local function buildWords(pause)
	local byWord, out, n = {}, {}, 0
	local function add(word, kind, entry)
		if #word < 3 then
			return
		end
		local list = byWord[word]
		if not list then
			list = {}
			byWord[word] = list
			local first = string.sub(word, 1, 1)
			out[first] = out[first] or {}
			table.insert(out[first], word)
		end
		if list[#list] ~= entry then -- "Linen Linen" once
			list[#list + 1] = kind
			list[#list + 1] = entry
		end
	end
	for _, kind in ipairs(SEARCHED) do
		for _, entry in ipairs(names(kind)) do
			n = n + 1
			if pause and n % 500 == 0 then
				pause()
			end
			for word in string.gmatch(entry[2], "[%w']+") do
				add(word, kind, entry)
				-- "rocknot's" is Rocknot's too: "rocknut" is a typo of it.
				local stem = string.match(word, "^(.+)'s$")
				if stem then
					add(stem, kind, entry)
				end
			end
		end
	end
	return out, byWord
end
local function wordsBy(letter)
	if not wordsByFirst then
		wordsByFirst, namesByWord = buildWords()
	end
	return wordsByFirst[letter] or EMPTY
end

-- FD.PrepareSearch builds the search lists ahead of the first search, a
-- slice at a time: each call works for at most seconds (by clock, a
-- function returning seconds; GetTime would not move within a frame) and
-- returns true once all is built. A search before then builds what it
-- needs itself, as without this.
local preparing
function FD.PrepareSearch(seconds, clock)
	if index.prepared then
		return true
	end
	preparing = preparing or coroutine.create(function()
		for _, kind in ipairs(SEARCHED) do
			if not index[kind] then
				local list = buildNames(kind, coroutine.yield)
				index[kind] = index[kind] or list
			end
		end
		if not wordsByFirst then
			local words, byWord = buildWords(coroutine.yield)
			if not wordsByFirst then
				wordsByFirst, namesByWord = words, byWord
			end
		end
		index.prepared = true
	end)
	local start = clock()
	repeat
		local ok, err = coroutine.resume(preparing)
		if not ok then
			preparing = nil
			error(err)
		end
	until coroutine.status(preparing) == "dead" or clock() - start >= seconds
	return index.prepared == true
end

-- oneEdit tells whether a and b differ by at most one insertion, deletion,
-- change, or swap of two neighbouring letters.
local function oneEdit(a, b)
	local la, lb = #a, #b
	if math.abs(la - lb) > 1 then
		return false
	end
	if la == lb then
		local first
		for i = 1, la do
			if string.byte(a, i) ~= string.byte(b, i) then
				first = i
				break
			end
		end
		if not first then
			return true
		end
		-- one change, or a swap of first and first + 1
		if string.sub(a, first + 1) == string.sub(b, first + 1) then
			return true
		end
		return string.sub(a, first, first) == string.sub(b, first + 1, first + 1)
			and string.sub(a, first + 1, first + 1) == string.sub(b, first, first)
			and string.sub(a, first + 2) == string.sub(b, first + 2)
	end
	if la < lb then
		a, b, la, lb = b, a, lb, la
	end
	-- a is one longer: drop one of its letters
	for i = 1, la do
		if string.byte(a, i) ~= string.byte(b, i) then
			return string.sub(a, i + 1) == string.sub(b, i)
		end
	end
	return true
end

-- term prepares a typed word for the plain tiers; fuzzy adds what the
-- fuzzy tiers need (its letters-in-order pattern, its typo words), when
-- they are needed.
local function term(token)
	return { text = token }
end

local typoCache = setmetatable({}, { __mode = "k" })

local function fuzzy(t)
	if t.fuzzy then
		return
	end
	t.fuzzy = true
	local token = t.text
	if #token >= 3 then
		local parts = {}
		for i = 1, #token do
			parts[i] = (string.gsub(string.sub(token, i, i), "(%W)", "%%%1"))
		end
		t.pattern = table.concat(parts, ".-")
	end
	if #token >= 4 then
		t.typos = typoCache[token]
		if not t.typos then
			-- A typo in both of the first two letters is rare: the words to
			-- try start with the first or the second letter (a swap).
			t.typos = {}
			local first, second = string.sub(token, 1, 1), string.sub(token, 2, 2)
			for _, letter in ipairs(first == second and { first } or { first, second }) do
				for _, word in ipairs(wordsBy(letter)) do
					if word ~= token and oneEdit(word, token) then
						t.typos[#t.typos + 1] = word
					end
				end
			end
			typoCache[token] = t.typos
		end
	end
end

-- starts adds the words a half-typed word with a typo may be the start of:
-- one whose first letters, as many as were typed or one more or less, are
-- one edit off ("rocknu", on the way to rocknot). For 6 letters or more:
-- shorter, it took too much from letters in order ("mudsh", Mudsnout Shaman).
local startCache = {}
local function starts(t)
	if t.starts then
		return
	end
	local token = t.text
	t.starts = startCache[token]
	if t.starts then
		return
	end
	t.starts = {}
	if #token >= 6 then
		local first, second = string.sub(token, 1, 1), string.sub(token, 2, 2)
		for _, letter in ipairs(first == second and { first } or { first, second }) do
			for _, word in ipairs(wordsBy(letter)) do
				for n = #token - 1, math.min(#token + 1, #word - 1) do
					if oneEdit(string.sub(word, 1, n), token) then
						t.starts[#t.starts + 1] = word
						break
					end
				end
			end
		end
	end
	startCache[token] = t.starts
end

-- common is how many things give an item: creatures and objects that drop
-- it, vendors that sell it. Linen Cloth (some 400) is what "linen" means
-- more than Linen Boots (none). Search weighs it only for materials (see
-- MATERIAL) and only when words are typed.
local function common(id)
	local refs = ns.drops and ns.drops[id]
	local n = 0
	if refs and refs ~= "" then
		local _, commas = string.gsub(refs, ",", "")
		n = commas + 1
	end
	local sold = ns.vendors and ns.vendors[id]
	if sold and sold ~= "" then
		local _, more = string.gsub(sold, ";", "")
		n = n + more + 1
	end
	return n
end

-- Item classes a bare word names as a material: 5 reagent, 7 trade goods
-- ("linen" Linen Cloth, "copper" Copper Ore). They come before the gear of
-- that name, the commonest first.
local MATERIAL = { [5] = true, [7] = true }

local WHOLE = 15 -- bonus for a typed word that is a whole word of the name

-- wholeWord tells whether a word is a whole word of a name, its 's aside:
-- "rocknot" of "rocknot's ale".
local function wholeWord(name, word)
	local w = string.find(name, word, 1, true)
	while w do
		local rest = string.sub(name, w + #word, w + #word + 2)
		if string.sub(rest, 1, 2) == "'s" then
			rest = string.sub(rest, 3)
		end
		if not string.find(string.sub(name, w - 1, w - 1), "[%w']") and not string.find(rest, "^[%w']") then
			return true
		end
		w = string.find(name, word, w + 1, true)
	end
	return false
end

local function scoreTerm(name, t, allowFuzzy)
	local at = string.find(name, t.text, 1, true)
	if at then
		local after = string.sub(name, at + #t.text, at + #t.text)
		local whole = not string.find(after, "[%w']") and WHOLE or 0
		-- "The Deadmines" starts with "deadmines" as much as with "the".
		if at == 1 or (at == 5 and string.sub(name, 1, 4) == "the ") then
			return 100 + whole
		end
		local before = string.sub(name, at - 1, at - 1)
		if string.find(before, "[^%w']") then
			return 85 + whole
		end
		-- Inside a word only for 3 letters or more: "dm" is not Deadmire.
		return #t.text >= 3 and 60 or nil
	end
	if not allowFuzzy then
		return nil
	end
	if t.typos then
		for _, word in ipairs(t.typos) do
			if wholeWord(name, word) then
				return 45
			end
		end
	end
	if t.starts and allowFuzzy ~= "typo" then
		for _, word in ipairs(t.starts) do
			if wholeWord(name, word) then
				return 42
			end
		end
	end
	if t.pattern and allowFuzzy == true then
		local first, last = string.find(name, t.pattern)
		if first then
			return 30 + math.max(0, 10 - (last - first + 1 - #t.text))
		end
	end
	return nil
end

-- Filters ---------------------------------------------------------------------

-- Which kinds each ready-made filter applies to; set, it limits the search
-- to them.
local FILTER_KINDS = {
	quality = { item = true },
	level = { item = true, npc = true, quest = true },
	zone = { npc = true, object = true, item = true, quest = true },
}

-- withWings is the zones and their wings: what stands in a wing of an
-- instance is in the instance, though its spots are filed under the wing.
local function withWings(zones)
	local out = {}
	for _, id in ipairs(zones) do
		out[#out + 1] = id
		for _, wing in ipairs(FD.Wings(id)) do
			out[#out + 1] = wing
		end
	end
	return out
end

-- instanceQuests is the quests of the instances and wings among the zones,
-- wherever filed: those that take one to a wing are filed under the whole,
-- some of a dungeon's under the area outside its entrance.
local function instanceQuests(zones)
	local out = {}
	for _, id in ipairs(zones) do
		local z = zone(id)
		if z and z.instance then
			for _, row in ipairs(questsOf("a" .. id) or EMPTY) do
				out[row.quest] = true
			end
		end
	end
	return out
end

-- questIn tells whether a quest is filed under one of the zones, or under
-- a subzone of one (Northshire Valley lies in Elwynn Forest).
local function questIn(id, zones)
	local q = quest(id)
	local at, guard = q and q.zone, 0
	while at and guard < 8 do
		for _, z in ipairs(zones) do
			if z == at then
				return true
			end
		end
		local area = zone(at)
		at, guard = area and area.parent, guard + 1
	end
	return false
end

-- standsIn tells whether a creature (code n) or object (o) stands in one
-- of the zones. The packed spots name their zones ("47:...;12:..."): look
-- there rather than decode every point.
local function standsIn(code, id, zones)
	local packed = ns.spawns and ns.spawns[code] and ns.spawns[code][id]
	if not packed then
		return false
	end
	packed = ";" .. packed
	for _, zoneID in ipairs(zones) do
		if string.find(packed, ";" .. zoneID .. ":", 1, true) then
			return true
		end
	end
	return false
end

-- givenIn tells whether something in one of the zones gives the item: a
-- creature or object standing there, or fishing there; for a world drop,
-- only a zone where it is given at 1% or better. Reads the drop
-- index ("n9028,o1731,a47"), decoding no loot.
local function givenIn(itemID, zones)
	local refs = ns.drops and ns.drops[itemID]
	if not refs then
		return false
	end
	-- A world drop is a zone's only where it is given at 1% or better: the
	-- zones after its "*" ("Fiery War Axe|...|*" is no zone's).
	local packed = ns.items and ns.items[itemID]
	local world = packed and string.match(packed, "|%*([%d,]*)$")
	if world then
		world = "," .. world .. ","
		for _, zoneID in ipairs(zones) do
			if string.find(world, "," .. zoneID .. ",", 1, true) then
				return true
			end
		end
	end
	for ref in string.gmatch(refs, "[^,]+") do
		local code, id = string.sub(ref, 1, 1), tonumber(string.sub(ref, 2))
		if code == "a" then
			for _, zoneID in ipairs(zones) do
				if id == zoneID then
					return true
				end
			end
		elseif (code == "n" or code == "o") and not world and standsIn(code, id, zones) then
			return true
		end
	end
	return false
end

-- accepter builds the test a match must pass from the options: filter
-- (function(kind, id) returning true to keep), quality (items of at least
-- this quality), level ({min, max}: items by required level, creatures by
-- their level range, quests by level), zone (an area ID or a list:
-- creatures and objects that stand there, items something there gives,
-- quests filed under it or a subzone of it). Returns nil without filters, and the kinds
-- the filters allow.
local function accepter(options)
	if not options then
		return nil, nil
	end
	local allowed
	for key, kindsOf in pairs(FILTER_KINDS) do
		if options[key] ~= nil then
			local next = {}
			for kind in pairs(kindsOf) do
				if not allowed or allowed[kind] then
					next[kind] = true
				end
			end
			allowed = next
		end
	end
	if not allowed and not options.filter then
		return nil, nil
	end
	local quality, level, custom = options.quality, options.level, options.filter
	local zones = options.zone
	if type(zones) == "number" then
		zones = { zones }
	end
	local inside
	if zones then
		zones = withWings(zones)
		inside = instanceQuests(zones)
	end
	local lo, hi = level and level[1] or 0, level and (level[2] or level[1]) or math.huge
	return function(kind, id)
		if quality then
			local it = item(id)
			if not it or (it.quality or -1) < quality then
				return false
			end
		end
		if level then
			if kind == "item" then
				local it = item(id)
				local need = it and it.requiredLevel or 0
				if need < lo or need > hi then
					return false
				end
			elseif kind == "npc" then
				local n = npc(id)
				if not n or not n.minLevel or (n.maxLevel or n.minLevel) < lo or n.minLevel > hi then
					return false
				end
			elseif kind == "quest" then
				local q = quest(id)
				if not q or not q.level or q.level < lo or q.level > hi then
					return false
				end
			end
		end
		if zones then
			if kind == "item" then
				if not givenIn(id, zones) then
					return false
				end
			elseif kind == "quest" then
				if not inside[id] and not questIn(id, zones) then
					return false
				end
			elseif not standsIn(kind == "npc" and "n" or "o", id, zones) then
				return false
			end
		end
		return not custom or custom(kind, id) and true or false
	end, allowed
end

-- Among equal matches, places and bosses are what a name usually means
-- ("scarlet" Scarlet Monastery, "whitemane" the boss), then items.
local KIND_ORDER = { zone = 1, boss = 2, item = 3, npc = 4, object = 5, quest = 6 }
local COMPLETE = 30 -- bonus for a name with no words beyond those typed

-- Things whose name matches the text, best first: rows {kind, id, name}.
-- Best: how well the name matches (with a bonus for a name with no words
-- beyond those typed), then places, bosses, items, the rest, better quality first,
-- then by type, then the shorter name.
-- kinds limits the search ({"item", "npc"}); limit caps the rows (default
-- 50). options narrow what is found, before the limit:
--   filter   function(kind, id): true to keep
--   quality  items of at least this quality (3 rare)
--   level    {min, max}: items by required level, creatures by level, quests by level
--   zone     an area ID, or a list of them: creatures and objects that stand
--            there, items something there gives (or that are fished there;
--            a world drop only where something gives it at 1% or better),
--            quests filed under it or a subzone of it
--   distinct one row a kind and name, with all its IDs in ids ({1731, 2055, ...}
--            for the Copper Veins), before the limit
-- quality, level and zone limit the search to the kinds they apply to.
-- With a filter the text may be empty: everything that passes, shortest
-- names first. A whole search takes up to a few tens of milliseconds; to
-- keep the game smooth, call it in a coroutine with options {yieldEvery =
-- n}: it yields after every n names, and the caller resumes it a frame later.
local PAUSE_EVERY = 200
function FD.Search(text, limit, kinds, options)
	local yieldEvery = options and options.yieldEvery
	-- options.pause: called every PAUSE_EVERY names, so a caller can give
	-- the frame back when its time is up (it yields its own coroutine).
	local pause = options and options.pause
	local seen = 0
	if type(text) ~= "string" then
		return EMPTY
	end
	local terms = {}
	for token in string.gmatch(string.lower(text), "%S+") do
		terms[#terms + 1] = term(token)
	end
	local accept, allowed = accepter(options)
	if #terms == 0 and not accept then
		return EMPTY
	end
	local found, matched = {}, {}
	local want = limit or 50
	-- pass scores every name the plain tiers (or, when fuzzy, all tiers) match.
	local searched = {}
	for _, kind in ipairs(kinds or SEARCHED) do
		searched[kind] = SOURCE[kind] ~= nil and (not allowed or allowed[kind]) or nil
	end
	local score
	-- pass scores every name the plain tiers (or, when fuzzy, the fuzzy
	-- ones too) match; with only = {kind, entry, ...}, only those names.
	local function pass(allowFuzzy, only)
		if only then
			for i = 1, #only, 2 do
				if searched[only[i]] then
					score(only[i], only[i + 1], allowFuzzy)
				end
			end
			return
		end
		for _, kind in ipairs(kinds or SEARCHED) do
			if searched[kind] then
				for _, entry in ipairs(names(kind)) do
					if yieldEvery or pause then
						seen = seen + 1
						if yieldEvery and seen % yieldEvery == 0 then
							coroutine.yield()
						end
						if pause and seen % PAUSE_EVERY == 0 then
							pause()
						end
					end
					score(kind, entry, allowFuzzy)
				end
			end
		end
	end
	function score(kind, entry, allowFuzzy)
		if matched[entry] then
			return
		end
		local total, byName = 0, true
		for _, t in ipairs(terms) do
			local s = scoreTerm(entry[2], t, allowFuzzy)
			if not s and entry[5] then
				s = scoreTerm(entry[5], t, false)
				s = s and s - 15
				byName = false
			end
			if not s then
				return
			end
			total = total + s
		end
		-- A name with no words beyond those typed is the one meant: "turtle
		-- scale" is Turtle Scale, not Turtle Scale Helm.
		if byName and entry[4] == #terms then
			total = total + COMPLETE
		end
		if not accept or accept(kind, entry[1]) then
			matched[entry] = true
			found[#found + 1] = { kind = kind, id = entry[1], name = entry[3], score = total }
		end
	end
	pass(false)
	if #found == 0 and #terms > 0 then
		-- Nothing plain: first the names with a word one typo off what was
		-- typed, reached through the word index; then those with a word that
		-- starts one typo off it; only when there are none, letters in
		-- order, over every name, the last resort.
		local function namesOf(which)
			local only = {}
			for _, t in ipairs(terms) do
				for _, word in ipairs(t[which] or EMPTY) do
					for _, x in ipairs(namesByWord and namesByWord[word] or EMPTY) do
						only[#only + 1] = x
					end
				end
			end
			return only
		end
		for _, t in ipairs(terms) do
			fuzzy(t)
		end
		pass("typo", namesOf("typos"))
		-- Then the same for a word not typed out yet.
		if #found == 0 then
			for _, t in ipairs(terms) do
				starts(t)
			end
			pass("start", namesOf("starts"))
		end
		if #found == 0 then
			pass(true)
		end
	end
	-- Among equal matches: places (whole zones first), bosses, items
	-- (materials first, the commonest first; see MATERIAL), the best
	-- quality first, then by type
	-- (class, subclass), then the shortest name.
	for n, f in ipairs(found) do
		if pause and n % PAUSE_EVERY == 0 then
			pause()
		end
		if yieldEvery and n % yieldEvery == 0 then
			coroutine.yield()
		end
		f.order = KIND_ORDER[f.kind] or 9
		if f.kind == "npc" then
			local n = npc(f.id)
			if n and n.boss then
				f.order = KIND_ORDER.boss
			end
		end
		if f.kind == "item" then
			local it = item(f.id)
			f.quality, f.class, f.subclass = it and it.quality or -1, it and it.class or 99, it and it.subclass or 99
			f.common = #terms > 0 and MATERIAL[f.class] and 1 + common(f.id) or 0
		else
			f.quality, f.class, f.subclass, f.common = -1, 99, 99, 0
			-- A whole zone before a spot in one: Scarlet Monastery before
			-- Scarlet Base Camp.
			if f.kind == "zone" then
				local z = zone(f.id)
				f.common = z and not z.parent and 1 or 0
			end
		end
	end
	table.sort(found, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		if a.common ~= b.common then
			return a.common > b.common
		end
		if a.quality ~= b.quality then
			return a.quality > b.quality
		end
		if a.class ~= b.class then
			return a.class < b.class
		end
		if a.subclass ~= b.subclass then
			return a.subclass < b.subclass
		end
		if #a.name ~= #b.name then
			return #a.name < #b.name
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	local out = {}
	if options and options.distinct then
		local byName = {}
		for _, f in ipairs(found) do
			local key = f.kind .. "\0" .. f.name
			local row = byName[key]
			if row then
				row.ids[#row.ids + 1] = f.id
			elseif #out < want then
				row = { kind = f.kind, id = f.id, name = f.name, ids = { f.id } }
				byName[key] = row
				out[#out + 1] = row
			end
		end
		return out
	end
	for i = 1, math.min(#found, want) do
		local f = found[i]
		out[i] = { kind = f.kind, id = f.id, name = f.name }
	end
	return out
end
