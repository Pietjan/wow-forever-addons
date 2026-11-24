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
	local reaction = f[6] or ""
	return {
		id = id, name = f[1], title = text(f[2]), minLevel = number(f[3]), maxLevel = number(f[4]),
		rank = number(f[5]), alliance = REACTION[string.sub(reaction, 1, 1)], horde = REACTION[string.sub(reaction, 2, 2)],
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

-- {id, name, title, minLevel, maxLevel, rank, alliance, horde}: rank 0
-- normal, 1 elite, 2 rare elite, 3 boss, 4 rare; alliance and horde how
-- it takes that side's players, "hostile", "neutral" (you can attack it, it
-- does not attack you) or "friendly", from its faction; nil when unknown.
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

-- Fuzzy search, as a command palette ranks: each word typed must match
-- the name somehow, and the name scores by how well each did:
--   100  the name starts with it          "turtle" Turtle Scale
--    85  a word of the name starts with it "scale"  Turtle Scale
--    60  it is inside the name            "urtl"
--    45  a word of the name is one typo away (4 letters or more) "tutrle"
--  30-40 its letters are in the name in order (3 letters or more) "trtl",
--        the closer together the better
-- Within a score, shorter names first. The search is staged: first only
-- the plain tiers (100, 85, 60); typos and letters in order only when that
-- finds fewer than asked for. Typos are found against the distinct words
-- of all names, not every name.

-- wordsBy collects the distinct words of all names searched, by first
-- letter, on first use.
local wordsByFirst
local function wordsBy(letter)
	if not wordsByFirst then
		local seen = {}
		wordsByFirst = {}
		for _, kind in ipairs(SEARCHED) do
			for _, entry in ipairs(names(kind)) do
				for word in string.gmatch(entry[2], "[%w']+") do
					if not seen[word] and #word >= 3 then
						seen[word] = true
						local first = string.sub(word, 1, 1)
						wordsByFirst[first] = wordsByFirst[first] or {}
						table.insert(wordsByFirst[first], word)
					end
				end
			end
		end
	end
	return wordsByFirst[letter] or EMPTY
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

local function scoreTerm(name, t, allowFuzzy)
	local at = string.find(name, t.text, 1, true)
	if at == 1 then
		return 100
	end
	if at then
		local before = string.sub(name, at - 1, at - 1)
		if string.find(before, "[^%w']") then
			return 85
		end
		return 60
	end
	if not allowFuzzy then
		return nil
	end
	if t.typos then
		for _, word in ipairs(t.typos) do
			local w = string.find(name, word, 1, true)
			if w then
				local before, after = string.sub(name, w - 1, w - 1), string.sub(name, w + #word, w + #word)
				if not string.find(before, "[%w']") and not string.find(after, "[%w']") then
					return 45
				end
			end
		end
	end
	if t.pattern then
		local first, last = string.find(name, t.pattern)
		if first then
			return 30 + math.max(0, 10 - (last - first + 1 - #t.text))
		end
	end
	return nil
end

-- Things whose name matches the text, best first: rows {kind, id, name}.
-- kinds limits the search ({"item", "npc"}); limit caps the rows (default
-- 50). A whole search takes up to a few tens of milliseconds; to keep the
-- game smooth, call it in a coroutine with options {yieldEvery = n}: it
-- yields after every n names, and the caller resumes it a frame later.
function FD.Search(text, limit, kinds, options)
	local yieldEvery = options and options.yieldEvery
	local seen = 0
	if type(text) ~= "string" then
		return EMPTY
	end
	local terms = {}
	for token in string.gmatch(string.lower(text), "%S+") do
		terms[#terms + 1] = term(token)
	end
	if #terms == 0 then
		return EMPTY
	end
	local found, matched = {}, {}
	local want = limit or 50
	-- pass scores every name the plain tiers (or, when fuzzy, all tiers) match.
	local function pass(allowFuzzy)
		for _, kind in ipairs(kinds or SEARCHED) do
			if SOURCE[kind] then
				for _, entry in ipairs(names(kind)) do
					if yieldEvery then
						seen = seen + 1
						if seen % yieldEvery == 0 then
							coroutine.yield()
						end
					end
					if not matched[entry] then
						local total = 0
						for _, t in ipairs(terms) do
							local s = scoreTerm(entry[2], t, allowFuzzy)
							if not s then
								total = nil
								break
							end
							total = total + s
						end
						if total then
							matched[entry] = true
							found[#found + 1] = { kind = kind, id = entry[1], name = entry[3], score = total }
						end
					end
				end
			end
		end
	end
	pass(false)
	if #found < want then
		for _, t in ipairs(terms) do
			fuzzy(t)
		end
		pass(true)
	end
	table.sort(found, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
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
	for i = 1, math.min(#found, want) do
		local f = found[i]
		out[i] = { kind = f.kind, id = f.id, name = f.name }
	end
	return out
end
