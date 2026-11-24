-- ForeverSearch, the data side: what a search finds and what to say about
-- each find, from ForeverData, Auctionator and Syndicator. No frames here
-- (Window.lua draws), so this file runs outside the game too.
local ADDON, ns = ...

local FD -- ForeverData, once it has passed its contract check

ns.KIND_LABEL = { item = "Item", npc = "Creature", object = "Object", quest = "Quest", zone = "Zone" }
local RANK_LABEL = { [1] = "Elite", [2] = "Rare elite", [3] = "Boss", [4] = "Rare" }
local STANDING_LABEL = { [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }
local CURRENCY_LABEL = { [3402] = "Merchant's Favor" }
local GREY, GOLD, RED = "|cff9d9d9d", "|cffffd100", "|cffff6040"

-- Ready is true once ForeverData is there and of the layout this was written for.
function ns.Ready()
	if FD then
		return true
	end
	if ForeverData and ForeverData.RequireContract and ForeverData.RequireContract(1) then
		FD = ForeverData
		return true
	end
	return false
end

function ns.Money(copper)
	copper = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then
		return ("%dg %02ds %02dc"):format(g, s, c)
	elseif s > 0 then
		return ("%ds %02dc"):format(s, c)
	end
	return ("%dc"):format(c)
end

-- Percent with as many decimals as the number needs, up to three.
local function Percent(chance)
	local s = ("%.3f"):format(chance):gsub("0+$", ""):gsub("%.$", "")
	return s .. "%"
end

-- What a chance rests on, in words; counted in Forever is the plain case.
local function Basis(row)
	if row.basis == "forever" then
		return row.sample and (" of %d"):format(row.sample) or ""
	elseif row.basis == "classicEra" then
		return GREY .. (" (Classic Era, of %d)"):format(row.sample or 0) .. "|r"
	elseif row.basis == "shown" then
		return GREY .. " (wowhead's figure)|r"
	elseif row.basis == "classic" then
		return GREY .. " (Classic's table)|r"
	end
	return ""
end

local function Chance(row)
	if not row.chance then
		return GREY .. "seen, no figure|r"
	end
	return Percent(row.chance) .. Basis(row)
end

function ns.NameOf(kind, id)
	local thing = FD and (kind == "item" and FD.Item(id) or kind == "npc" and FD.Npc(id) or kind == "object" and FD.Object(id)
		or kind == "zone" and FD.Zone(id) or kind == "quest" and FD.Quest(id))
	return thing and thing.name or (kind .. " " .. tostring(id))
end

-- How a creature takes players, in a few words: "hostile", "neutral",
-- "friendly to both", or the two sides when they differ.
local function Reaction(n)
	local a, h = n.alliance, n.horde
	if not a and not h then
		return nil
	end
	if a == h then
		return a == "friendly" and "friendly to both" or a
	end
	return ("%s to Alliance, %s to Horde"):format(a or "unknown", h or "unknown")
end

-- Higher chances first; no figure last.
local function ByChance(a, b)
	if (a.chance ~= nil) ~= (b.chance ~= nil) then
		return a.chance ~= nil
	end
	if a.chance and a.chance ~= b.chance then
		return a.chance > b.chance
	end
	return (a.sample or 0) > (b.sample or 0)
end

-- Places a creature or object stands: "The Hinterlands (92), ...".
local function Places(kind, id)
	local counts, order = {}, {}
	for _, s in ipairs(FD.Spawns(kind, id)) do
		if not counts[s.zone] then
			counts[s.zone] = 0
			order[#order + 1] = s.zone
		end
		counts[s.zone] = counts[s.zone] + 1
	end
	table.sort(order, function(a, b) return counts[a] > counts[b] end)
	local parts = {}
	for _, zone in ipairs(order) do
		parts[#parts + 1] = ("%s (%d)"):format(ns.NameOf("zone", zone), counts[zone])
	end
	return table.concat(parts, ", ")
end

-- Auctionator's price, when it is there and has one.
function ns.AuctionPrice(itemID)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not api then
		return nil
	end
	local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
	return ok and type(price) == "number" and price > 0 and price or nil
end

-- How many of an item your characters own, from Syndicator: total and
-- {who = count}; nil without Syndicator.
function ns.Owned(itemID)
	local api = Syndicator and Syndicator.API
	if not api or not api.GetAllCharacters then
		return nil
	end
	local total, byWho = 0, {}
	local function Add(who, item)
		if type(item) == "table" and item.itemID == itemID then
			local n = item.itemCount or 1
			total, byWho[who] = total + n, (byWho[who] or 0) + n
		end
	end
	for _, name in ipairs(api.GetAllCharacters() or {}) do
		local c = api.GetByCharacterFullName(name)
		if c and not (c.details and c.details.hidden) then
			local who = name:match("^[^-]+") or name
			for _, place in ipairs({ c.bags or {}, c.bank or {} }) do
				for _, bag in ipairs(place) do
					for _, item in ipairs(bag) do Add(who, item) end
				end
			end
			for _, tab in ipairs(c.bankTabs or {}) do
				for _, item in ipairs(tab.slots or {}) do Add(who, item) end
			end
			for _, item in ipairs(c.mail or {}) do Add(who, item) end
		end
	end
	return total, byWho
end

-- How much is known of a thing, to pick among things of one name.
local function Weight(kind, id)
	if kind == "item" then
		local item = FD.Item(id)
		return (item and item.available and 100000 or 0) + #FD.Drops(id) + #FD.Vendors(id)
	end
	return #FD.Spawns(kind, id) + #FD.Loot(kind, id)
end

-- The search bar's words for narrowing a search, as command palettes have
-- them: a kind ("item:", "npc:"), "q:rare" (or q:3) for item quality,
-- "lvl:40-50" (or lvl:40, lvl:40+) for level, "in:hinterlands" for a zone.
-- A kind word may carry text: "npc:snapjaw".
local KIND_WORD = {
	item = "item", items = "item", npc = "npc", npcs = "npc", creature = "npc", creatures = "npc", mob = "npc", mobs = "npc",
	object = "object", objects = "object", obj = "object", quest = "quest", quests = "quest", zone = "zone", zones = "zone",
}
local QUALITY_WORD = {
	poor = 0, grey = 0, gray = 0, common = 1, white = 1, uncommon = 2, green = 2,
	rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5,
}

-- The zone an area lies in: a subzone's top zone, a zone itself.
local function TopZone(id)
	local zone = FD.Zone(id)
	local guard = 0
	while zone and zone.parent and guard < 8 do
		local parent = FD.Zone(zone.parent)
		if not parent then
			break
		end
		zone, guard = parent, guard + 1
	end
	return zone
end

-- Zones a word names: every zone with a word of its name starting with it
-- ("blackrock": Blackrock Depths, Blackrock Spire, ...); failing that, the
-- best fuzzy match ("hinterlnds"). Spots are filed under whole zones, so
-- when the word names only subzones ("goldshire"), their zones count
-- (Elwynn Forest); when it names a whole zone too, only whole zones do.
local function ZonesNamed(word)
	-- Dashes stand for spaces: in:blackrock-depths. A zone of exactly that
	-- name is the answer.
	word = string.gsub(word, "%-", " ")
	local exact = ns.ZoneByName(word)
	if exact then
		local zone, top = FD.Zone(exact), TopZone(exact)
		if top and top.id ~= exact then
			return { top.id }, { zone.name .. " (" .. top.name .. ")" }
		end
		return { exact }, { zone.name }
	end
	local found = FD.Search(word, 50, { "zone" })
	local lower = string.lower(word)
	local matched = {}
	for _, z in ipairs(found) do
		local name = string.lower(z.name)
		if string.sub(name, 1, #lower) == lower or string.find(name, "[^%w']" .. lower:gsub("%W", "%%%0")) then
			matched[#matched + 1] = z
		end
	end
	if #matched == 0 and found[1] then
		matched[1] = found[1]
	end
	local whole = {}
	for _, z in ipairs(matched) do
		local zone = FD.Zone(z.id)
		if zone and not zone.parent then
			whole[#whole + 1] = z
		end
	end
	local out, names, seen = {}, {}, {}
	if #whole > 0 then
		for _, z in ipairs(whole) do
			out[#out + 1], names[#names + 1] = z.id, z.name
		end
		return out, names
	end
	for _, z in ipairs(matched) do
		local top = TopZone(z.id)
		if top and not seen[top.id] then
			seen[top.id] = true
			out[#out + 1] = top.id
			names[#names + 1] = top.id == z.id and z.name or (z.name .. " (" .. top.name .. ")")
		end
	end
	return out, names
end

-- ZoneByName finds the zone of exactly that name ("Blackrock Depths", as
-- the game names the instance you are in), a whole zone before a subzone
-- of the same name; nil when none has it.
function ns.ZoneByName(name)
	if not ns.Ready() or type(name) ~= "string" or name == "" then
		return nil
	end
	local lower, best = string.lower(name), nil
	for _, z in ipairs(FD.Search(name, 50, { "zone" })) do
		if string.lower(z.name) == lower then
			local zone = FD.Zone(z.id)
			if zone and not zone.parent then
				return z.id
			end
			best = best or z.id
		end
	end
	return best
end

-- InWord writes a zone's name as one in: word: "in:blackrock-depths".
function ns.InWord(name)
	return "in:" .. string.gsub(string.lower(name), "%s+", "-")
end

local QUALITY_NAME = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }
local KIND_PLURAL = { item = "items", npc = "creatures", object = "objects", quest = "quests", zone = "zones" }

-- Describe says how the bar read the filter words: "Blackrock Depths ·
-- items · rare or better · level 40-50"; nil without filters.
function ns.Describe(typed)
	local _, kinds, options = ns.Parse(typed)
	local parts = {}
	if options.zone then
		parts[#parts + 1] = #(options.zoneNames or {}) > 0 and table.concat(options.zoneNames, ", ") or "no such zone"
	end
	if kinds then
		local names = {}
		for _, kind in ipairs(kinds) do
			names[#names + 1] = KIND_PLURAL[kind] or kind
		end
		parts[#parts + 1] = table.concat(names, ", ")
	end
	if options.quality then
		parts[#parts + 1] = (QUALITY_NAME[options.quality] or ("quality " .. options.quality)) .. (options.quality < 5 and " or better" or "")
	end
	if options.level then
		local lo, hi = options.level[1], options.level[2]
		parts[#parts + 1] = hi == math.huge and ("level " .. lo .. "+") or lo == hi and ("level " .. lo) or ("level %d-%d"):format(lo, hi)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " · ")
end

-- Parse splits what was typed into the text to match, the kinds, and the
-- options for ForeverData.Search. A word that is not a filter is text. A
-- filter word with nothing after its colon takes the next word ("in:
-- blackrock" is "in:blackrock").
function ns.Parse(typed)
	local list = {}
	for word in string.gmatch(typed or "", "%S+") do
		list[#list + 1] = word
	end
	local words, kinds, options = {}, nil, {}
	local i = 1
	while i <= #list do
		local word = list[i]
		local key, value = string.match(string.lower(word), "^(%a+):(.*)$")
		if (key == "in" or key == "q" or key == "lvl") and value == "" and list[i + 1] then
			i = i + 1
			value = string.lower(list[i])
		end
		local kind = key and KIND_WORD[key]
		if kind then
			kinds = kinds or {}
			kinds[#kinds + 1] = kind
			if value ~= "" then
				words[#words + 1] = value
			end
		elseif key == "q" and (QUALITY_WORD[value] or tonumber(value)) then
			options.quality = QUALITY_WORD[value] or tonumber(value)
		elseif key == "lvl" and string.match(value, "^%d") then
			local lo, hi = string.match(value, "^(%d+)%-(%d+)$")
			if lo then
				options.level = { tonumber(lo), tonumber(hi) }
			elseif string.match(value, "^%d+%+$") then
				options.level = { tonumber(string.match(value, "^(%d+)")), math.huge }
			else
				local n = tonumber(value)
				options.level = n and { n, n } or nil
			end
		elseif key == "in" and value ~= "" then
			local zones, names = {}, {}
			if ns.Ready() then
				zones, names = ZonesNamed(value)
			end
			options.zone = #zones > 0 and zones or { -1 } -- no such zone: nothing stands there
			options.zoneNames = names
		else
			words[#words + 1] = word
		end
		i = i + 1
	end
	return table.concat(words, " "), kinds, options
end

-- What a search finds: rows {kind, id, name, quality, available, ids}, one
-- a kind and name: five Copper Vein objects are one row, its id the one
-- most is known of, ids all of them.
-- typed may hold filter words (see Parse); options go to ForeverData.Search
-- along with them (yieldEvery).
function ns.Results(typed, limit, options)
	if not ns.Ready() then
		return {}
	end
	local text, kinds, filters = ns.Parse(typed)
	-- What was typed wins: an in: typed overrides the instance's zone.
	for k, v in pairs(options or {}) do
		if filters[k] == nil then
			filters[k] = v
		end
	end
	filters.distinct = true
	local out = {}
	for _, hit in ipairs(FD.Search(text, limit or 30, kinds, filters)) do
		local row = { kind = hit.kind, id = hit.id, name = hit.name, ids = hit.ids }
		-- Several of one name (five Copper Vein objects): the one most is
		-- known of. Weighing decodes an item's every source, so only then.
		if #hit.ids > 1 then
			local best = -1
			for _, id in ipairs(hit.ids) do
				local w = Weight(hit.kind, id)
				if w > best then
					row.id, best = id, w
				end
				if filters.yieldEvery then
					coroutine.yield()
				end
			end
		end
		out[#out + 1] = row
	end
	for _, row in ipairs(out) do
		if row.kind == "item" then
			local item = FD.Item(row.id)
			row.quality, row.available = item and item.quality, item and item.available
		end
	end
	return out
end

-- The zone a creature or object stands in most.
local function MainZone(kind, id)
	local counts, best = {}, nil
	for _, s in ipairs(FD.Spawns(kind, id)) do
		counts[s.zone] = (counts[s.zone] or 0) + 1
		if not best or counts[s.zone] > counts[best] then
			best = s.zone
		end
	end
	return best and ns.NameOf("zone", best)
end

-- One line under a find's name: "Creature · level 49-50 · The Hinterlands".
function ns.Subtitle(row)
	local parts = { ns.KIND_LABEL[row.kind] or row.kind }
	if row.kind == "item" then
		local item = FD.Item(row.id)
		if item and item.itemLevel and item.itemLevel > 0 then
			parts[#parts + 1] = "item level " .. item.itemLevel
		end
		local price = ns.AuctionPrice(row.id)
		if price then
			parts[#parts + 1] = ns.Money(price)
		end
		if item and not item.available then
			parts[#parts + 1] = "not available"
		end
	elseif row.kind == "npc" then
		local n = FD.Npc(row.id)
		if n and n.minLevel then
			parts[#parts + 1] = n.minLevel == n.maxLevel and ("level " .. n.minLevel) or ("level %d-%d"):format(n.minLevel, n.maxLevel or n.minLevel)
		end
		if n and n.title then
			parts[#parts + 1] = "<" .. n.title .. ">"
		end
		parts[#parts + 1] = MainZone("npc", row.id)
	elseif row.kind == "object" then
		parts[#parts + 1] = MainZone("object", row.id)
	elseif row.kind == "quest" then
		local q = FD.Quest(row.id)
		if q and q.level then
			parts[#parts + 1] = "level " .. q.level
		end
		if q and q.new then
			parts[#parts + 1] = "new in Forever"
		end
	elseif row.kind == "zone" then
		local z = FD.Zone(row.id)
		if z and z.parent then
			parts[#parts + 1] = "in " .. ns.NameOf("zone", z.parent)
		end
	end
	if #row.ids > 1 then
		parts[#parts + 1] = #row.ids .. " of this name"
	end
	return table.concat(parts, " · ")
end

-- The ways of getting something, in this order, with a heading each: on
-- an item's page where it comes from, on a creature's, object's or zone's
-- what it gives.
local METHODS = { "drop", "skinning", "pickpocketing", "contained", "fishing", "disenchanting" }
local FROM_HEADING = {
	drop = "Drops from", skinning = "Skinned from", pickpocketing = "Pickpocketed from",
	contained = "Found in", fishing = "Fished in", disenchanting = "Disenchanted from",
}
local GIVES_HEADING = {
	drop = "Drops", skinning = "Skinning", pickpocketing = "Pickpocketing",
	contained = "Contains", fishing = "Fishing", disenchanting = "Disenchanting",
}
local PER_METHOD = 8

-- Grouped writes rows by way of getting, likeliest first, at most
-- PER_METHOD each; label names a row's other side.
local function Grouped(lines, rows, headings, label)
	local byMethod = {}
	for _, row in ipairs(rows) do
		byMethod[row.method] = byMethod[row.method] or {}
		table.insert(byMethod[row.method], row)
	end
	for _, method in ipairs(METHODS) do
		local list = byMethod[method]
		if list then
			table.sort(list, ByChance)
			lines[#lines + 1] = ""
			lines[#lines + 1] = GOLD .. ("%s (%d):|r"):format(headings[method], #list)
			for i = 1, math.min(#list, PER_METHOD) do
				lines[#lines + 1] = ("  %s: %s"):format(label(list[i]), Chance(list[i]))
			end
			if #list > PER_METHOD then
				lines[#lines + 1] = GREY .. ("  and %d more|r"):format(#list - PER_METHOD)
			end
		end
	end
end

local function ItemLines(id, lines)
	local item = FD.Item(id)
	if item and not item.available then
		lines[#lines + 1] = RED .. "Not available to players (test, unused or not yet released).|r"
	end
	local facts = {}
	if item and item.itemLevel and item.itemLevel > 0 then
		facts[#facts + 1] = "item level " .. item.itemLevel
	end
	if item and item.requiredLevel and item.requiredLevel > 1 then
		facts[#facts + 1] = "requires level " .. item.requiredLevel
	end
	if #facts > 0 then
		lines[#lines + 1] = table.concat(facts, ", ")
	end
	local price = ns.AuctionPrice(id)
	if price then
		lines[#lines + 1] = GOLD .. "Auction:|r " .. ns.Money(price)
	end
	local total, byWho = ns.Owned(id)
	if total and total > 0 then
		local who = {}
		for name, n in pairs(byWho) do
			who[#who + 1] = ("%s %d"):format(name, n)
		end
		table.sort(who)
		lines[#lines + 1] = GOLD .. "You own:|r " .. total .. " (" .. table.concat(who, ", ") .. ")"
	end

	-- Where it comes from, a heading a way of getting it, so a rare drop
	-- is not hidden behind a likely skinning.
	Grouped(lines, FD.Drops(id), FROM_HEADING, function(d)
		if d.kind == "zone" then
			return ns.NameOf("zone", d.id)
		end
		return ns.NameOf(d.kind, d.id)
	end)

	local vendors = FD.Vendors(id)
	if #vendors > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. ("Sold by (%d):|r"):format(#vendors)
		for i = 1, math.min(#vendors, PER_METHOD) do
			local v = vendors[i]
			local price = v.price and (v.currency and ("%d %s"):format(v.price, CURRENCY_LABEL[v.currency] or ("currency " .. v.currency))
				or ns.Money(v.price)) or GREY .. "price unknown|r"
			local extra = {}
			if v.stock then
				extra[#extra + 1] = v.stock .. " in stock"
			end
			if v.standing then
				extra[#extra + 1] = STANDING_LABEL[v.standing] or ("standing " .. v.standing)
			end
			lines[#lines + 1] = ("  %s: %s%s"):format(ns.NameOf("npc", v.npc), price,
				#extra > 0 and (GREY .. " (" .. table.concat(extra, ", ") .. ")|r") or "")
		end
	end
end

local function LootLines(kind, id, lines)
	Grouped(lines, FD.Loot(kind, id), GIVES_HEADING, function(row)
		return ns.NameOf("item", row.item)
	end)
end

-- What to say about a find, as lines of text with colour codes.
function ns.Details(kind, id)
	if not ns.Ready() then
		return { RED .. "ForeverData is missing or of another version.|r" }
	end
	local lines = {}
	if kind == "item" then
		ItemLines(id, lines)
	elseif kind == "npc" then
		local n = FD.Npc(id)
		if n then
			local facts = {}
			if n.title then
				facts[#facts + 1] = "<" .. n.title .. ">"
			end
			if n.minLevel then
				facts[#facts + 1] = n.minLevel == n.maxLevel and ("level " .. n.minLevel) or ("level %d-%d"):format(n.minLevel, n.maxLevel or n.minLevel)
			end
			if RANK_LABEL[n.rank] then
				facts[#facts + 1] = RANK_LABEL[n.rank]
			end
			local reaction = Reaction(n)
			if reaction then
				facts[#facts + 1] = reaction
			end
			lines[#lines + 1] = table.concat(facts, ", ")
		end
		local where = Places("npc", id)
		if where ~= "" then
			lines[#lines + 1] = GOLD .. "Where:|r " .. where
		end
		LootLines("npc", id, lines)
	elseif kind == "object" then
		local where = Places("object", id)
		if where ~= "" then
			lines[#lines + 1] = GOLD .. "Where:|r " .. where
		end
		LootLines("object", id, lines)
	elseif kind == "quest" then
		local q = FD.Quest(id)
		if q then
			local facts = {}
			if q.level then
				facts[#facts + 1] = "level " .. q.level
			end
			if q.requiredLevel then
				facts[#facts + 1] = "from level " .. q.requiredLevel
			end
			if q.new then
				facts[#facts + 1] = "new in Forever"
			end
			lines[#lines + 1] = table.concat(facts, ", ")
		end
	elseif kind == "zone" then
		local z = FD.Zone(id)
		if z and z.parent then
			lines[#lines + 1] = "In " .. ns.NameOf("zone", z.parent)
		end
		LootLines("zone", id, lines)
	end
	if #lines == 0 then
		lines[1] = GREY .. "Nothing more known.|r"
	end
	return lines
end
