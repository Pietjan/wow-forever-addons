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
	}
end)

local npc = cached(function(id)
	local s = ns.npcs and ns.npcs[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	return {
		id = id, name = f[1], title = text(f[2]), minLevel = number(f[3]), maxLevel = number(f[4]),
		rank = number(f[5]), reacts = text(f[6]),
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

local quest = cached(function(id)
	local s = ns.quests and ns.quests[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	return { id = id, name = text(f[1]), level = number(f[2]), requiredLevel = number(f[3]), new = f[4] == "1" }
end)

local zone = cached(function(id)
	local s = ns.zones and ns.zones[id]
	if not s then
		return nil
	end
	local f = split(s, "|")
	return { id = id, name = f[1], parent = number(f[2]) }
end)

-- lootOf decodes what one thing gives: "item,method,chance,sample,basis;...".
local lootOf = cached(function(ref)
	local code, id = string.sub(ref, 1, 1), tonumber(string.sub(ref, 2))
	local s = ns.loot and ns.loot[code] and ns.loot[code][id]
	if not s then
		return nil
	end
	local rows = {}
	for _, row in ipairs(split(s, ";")) do
		local f = split(row, ",")
		rows[#rows + 1] = {
			item = tonumber(f[1]), method = METHOD[f[2]], chance = number(f[3]), sample = number(f[4]), basis = BASIS[f[5]],
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

local EMPTY = {}

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
-- available}: available is false for test, unused and not yet released
-- items (not available to players by wowhead).
function FD.Item(id) return item(id) end

-- {id, name, title, minLevel, maxLevel, rank, reacts}: rank 0 normal,
-- 1 elite, 2 rare elite, 3 boss, 4 rare; reacts "A", "H" or "AH" when
-- friendly, nil when hostile to both.
function FD.Npc(id) return npc(id) end

-- {id, name, type}: type 3 chest (veins and herbs too), 25 fishing hole.
function FD.Object(id) return object(id) end

-- {id, name, level, requiredLevel, new}: name nil for the few quests
-- known only by who starts and ends them; new true for quests new in Forever.
function FD.Quest(id) return quest(id) end

-- {id, name, parent}: an area; parent nil for a zone or an instance.
function FD.Zone(id) return zone(id) end

-- What a thing gives: kind "npc", "object", "item" (a container) or
-- "zone" (fishing). Rows {item, method, chance, sample, basis}, likeliest
-- first; sample is the kills or opens a counted chance is over.
function FD.Loot(kind, id)
	local code = KIND_CODE[kind]
	if not code or not id then
		return EMPTY
	end
	return lootOf(code .. id) or EMPTY
end

-- Where an item comes from. Rows {kind, id, method, chance, sample, basis}.
function FD.Drops(itemID)
	local refs = ns.drops and ns.drops[itemID]
	if not refs then
		return EMPTY
	end
	local out = {}
	for _, ref in ipairs(split(refs, ",")) do
		for _, row in ipairs(lootOf(ref) or EMPTY) do
			if row.item == itemID then
				out[#out + 1] = {
					kind = KIND_NAME[string.sub(ref, 1, 1)], id = tonumber(string.sub(ref, 2)),
					method = row.method, chance = row.chance, sample = row.sample, basis = row.basis,
				}
			end
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

-- Who sells an item: rows {npc, price, currency, stock, standing}. price
-- in copper, or in currency when currency is set (3402 Merchant's Favor);
-- stock nil for unlimited; standing the reputation asked (4 neutral .. 8
-- exalted), nil for none.
function FD.Vendors(itemID) return vendors(itemID) or EMPTY end

-- Who teaches a recipe (its spell): rows {npc, skillLine, skill, level, cost}.
function FD.Trainers(spellID) return trainers(spellID) or EMPTY end

-- Search ----------------------------------------------------------------------

local SEARCHED = { "item", "npc", "object", "quest", "zone" }
local SOURCE = { item = "items", npc = "npcs", object = "objects", quest = "quests", zone = "zones" }
local index = {}

-- names builds a kind's search list on first use: {id, lower-case name, name}.
local function names(kind)
	local list = index[kind]
	if list then
		return list
	end
	list = {}
	for id, s in pairs(ns[SOURCE[kind]] or EMPTY) do
		local bar = string.find(s, "|", 1, true)
		local name = bar and string.sub(s, 1, bar - 1) or s
		if name ~= "" then
			list[#list + 1] = { id, string.lower(name), name }
		end
	end
	index[kind] = list
	return list
end

-- Things whose name holds the text, any case: rows {kind, id, name}, names
-- that start with the text first, then shorter names. kinds limits the
-- search ({"item", "npc"}); limit caps the rows (default 50).
function FD.Search(text, limit, kinds)
	if type(text) ~= "string" or text == "" then
		return EMPTY
	end
	local needle = string.lower(text)
	local found = {}
	for _, kind in ipairs(kinds or SEARCHED) do
		if SOURCE[kind] then
			for _, entry in ipairs(names(kind)) do
				local at = string.find(entry[2], needle, 1, true)
				if at then
					found[#found + 1] = { kind = kind, id = entry[1], name = entry[3], prefix = at == 1 }
				end
			end
		end
	end
	table.sort(found, function(a, b)
		if a.prefix ~= b.prefix then
			return a.prefix
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
	for i = 1, math.min(#found, limit or 50) do
		local f = found[i]
		out[i] = { kind = f.kind, id = f.id, name = f.name }
	end
	return out
end
