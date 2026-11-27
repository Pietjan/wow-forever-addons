-- Loot: what each creature, node and chest gave, read from the loot window.
--
-- A loot window lists its slots, and GetLootSourceInfo(slot) names the
-- GUIDs each slot came from (several when loot from more corpses is shown
-- at once). Each source counts once per way of looting it ("looted"), and
-- each item it gave once ("n") with its amount ("q"): n / looted is the
-- chance per corpse opened. A corpse with nothing on it cannot be opened,
-- so this is the chance per corpse looted, not per kill: the combat log,
-- which would count kills, is closed to addons in Forever.
--
-- How it was looted comes from the last spell you cast, by name (enUS):
-- Skinning, Pick Pocket, Herb Gathering, Mining, Fishing. Fishing loot has
-- no source to name: it is filed under the map you fish on ("a<uiMap>").

local _, ns = ...

local METHOD_BY_SPELL = {
	["Skinning"] = "skinning",
	["Pick Pocket"] = "pickpocketing",
	["Herb Gathering"] = "gathering",
	["Mining"] = "gathering",
	["Fishing"] = "fishing",
}
local SPELL_WINDOW = 10 -- seconds a looting spell names the loot after it

local lastMethod, lastAt
-- This session's sources already counted, by GUID and method. Kept in
-- memory only: a GUID is never saved.
local counted = {}
-- The loot window being shown: one per opening, so a catch (which has no
-- GUID) counts once however often its window is read.
local window = 1
ns.On("LOOT_CLOSED", function()
	window = window + 1
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spell)
	if unit ~= "player" then
		return
	end
	local name = ns.Read("spell", C_Spell.GetSpellName, ns.Plain(spell))
	local method = name and METHOD_BY_SPELL[name]
	if method then
		lastMethod, lastAt = method, GetTime()
	end
end)

-- Method is how the window being read was looted, for a source of kind.
local function Method(kind)
	if IsFishingLoot and IsFishingLoot() then
		return "fishing"
	end
	local recent = lastMethod and GetTime() - lastAt <= SPELL_WINDOW and lastMethod or nil
	if kind == "object" then
		return recent == "gathering" and "gathering" or "contained"
	end
	if recent == "skinning" or recent == "pickpocketing" then
		return recent
	end
	return "drop"
end

-- Copper in a money slot's text ("1 Silver\n20 Copper").
local function Copper(text)
	text = ns.Plain(text)
	if type(text) ~= "string" then
		return nil
	end
	local g = tonumber(string.match(text, "(%d+) Gold")) or 0
	local s = tonumber(string.match(text, "(%d+) Silver")) or 0
	local c = tonumber(string.match(text, "(%d+) Copper")) or 0
	local total = g * 10000 + s * 100 + c
	return total > 0 and total or nil
end

local function Entry(key, method)
	local loot = ns.db.loot
	loot[key] = loot[key] or {}
	local e = loot[key][method]
	if not e then
		e = { looted = 0, items = {} }
		loot[key][method] = e
	end
	return e
end

-- Sources of one slot: { {guid, quantity}, ... }.
local function Sources(slot)
	local ok, list = pcall(function()
		return { GetLootSourceInfo(slot) }
	end)
	local out = {}
	if not ok then
		return out
	end
	for i = 1, #list, 2 do
		local guid, quantity = ns.Plain(list[i]), ns.Plain(list[i + 1])
		if list[i] ~= nil and guid == nil then
			ns.Secret("loot source")
		elseif guid then
			out[#out + 1] = { guid, tonumber(quantity) or 1 }
		end
	end
	return out
end

-- CorpseLevel files the level of the one creature a loot window is of
-- (id, guid), read from the dead unit you target or point at. Inside an
-- instance the game keeps which creature a unit is secret from addons,
-- name and GUID alike, but the loot window still names it, and a unit's
-- level and death are never secret. A unit whose GUID can be read must be
-- that corpse; one whose GUID is secret is taken as it, the window being
-- of that one corpse only.
-- The corpses whose level was taken this session, by GUID, so a window
-- read twice (LOOT_READY, LOOT_OPENED) counts once. In memory only.
local levelled = {}
local function CorpseLevel(id, guid)
	for _, unit in ipairs({ "target", "mouseover" }) do
		if ns.Read("dead", UnitIsDead, unit) == true then
			local ok, unitGuid = pcall(UnitGUID, unit)
			unitGuid = ok and ns.Plain(unitGuid) or nil
			if unitGuid == nil or unitGuid == guid then
				local level = ns.Read("level", UnitLevel, unit)
				if level and level > 0 then
					local c = ns.db.creatures[id] or {}
					ns.db.creatures[id] = c
					c.min = math.min(c.min or level, level)
					c.max = math.max(c.max or level, level)
					c.class = ns.Read("classification", UnitClassification, unit) or c.class
					if not levelled[guid] then
						levelled[guid] = true
						c.corpses = (c.corpses or 0) + 1
					end
				end
				return
			end
		end
	end
end

-- Read records the loot window once per source and method.
function ns.ReadLoot()
	local slots = ns.Read("loot slots", GetNumLootItems) or 0
	local fishing = IsFishingLoot and IsFishingLoot()
	local fishKey = fishing and ns.Read("map", C_Map.GetBestMapForUnit, "player")
	fishKey = fishKey and ("a" .. fishKey)
	local opened = {} -- this window's sources: mark -> entry
	local corpses, corpseCount = {}, 0 -- this window's creatures: GUID -> ID
	local given = {} -- this window's items per source: mark .. item -> true
	local function Open(key, kind, guid)
		local method = fishing and "fishing" or Method(kind)
		local mark = (fishing and ("catch#" .. window) or guid) .. "|" .. method
		if counted[mark] then
			return nil
		end
		if not opened[mark] then
			local e = Entry(key, method)
			e.looted = e.looted + 1
			opened[mark] = e
			if not fishing then
				ns.Place(key)
			end
		end
		return opened[mark], mark
	end
	for slot = 1, slots do
		local slotType = ns.Read("loot slot type", GetLootSlotType, slot)
		local item = slotType == 1 and ns.ItemID(ns.Read("loot link", GetLootSlotLink, slot)) or nil
		local money = slotType == 2 and Copper(ns.Read("loot money", function(s) return (select(2, GetLootSlotInfo(s))) end, slot)) or nil
		local amount = fishing and ns.Read("loot amount", function(s) return (select(3, GetLootSlotInfo(s))) end, slot)
		local sources = fishing and { { "fishing", tonumber(amount) or 1 } } or Sources(slot)
		for _, src in ipairs(sources) do
			local key, kind
			if fishing then
				key, kind = fishKey, "area"
			else
				local id
				key, kind, id = ns.Key(src[1])
				if kind == "npc" and not corpses[src[1]] then
					corpses[src[1]] = id
					corpseCount = corpseCount + 1
				end
			end
			local e, mark
			if key then
				e, mark = Open(key, kind, src[1])
			end
			if e and item then
				-- An item split over two slots is one drop of the two amounts.
				local it = e.items[item] or { n = 0, q = 0 }
				if not given[mark .. ":" .. item] then
					given[mark .. ":" .. item] = true
					it.n = it.n + 1
				end
				it.q = it.q + src[2]
				e.items[item] = it
			elseif e and money then
				e.money = e.money or { n = 0, total = 0 }
				e.money.n, e.money.total = e.money.n + 1, e.money.total + money
			end
		end
	end
	for mark in pairs(opened) do
		counted[mark] = true
	end
	if corpseCount == 1 then
		local guid, id = next(corpses)
		CorpseLevel(id, guid)
	end
end

-- LOOT_READY comes before auto loot empties the window; LOOT_OPENED after.
-- Either reads it; a source counts once.
ns.On("LOOT_READY", ns.ReadLoot)
ns.On("LOOT_OPENED", ns.ReadLoot)
