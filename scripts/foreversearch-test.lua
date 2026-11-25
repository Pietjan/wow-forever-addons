-- Offline checks for ForeverSearch's data side (Core.lua) on ForeverData's
-- real data, with Auctionator and Syndicator stood in for.
--   lua5.1 scripts/foreversearch-test.lua
local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

local data = {}
for _, f in ipairs({ "Meta", "Items", "Npcs", "Objects", "Quests", "Zones", "Loot", "Spawns", "Vendors", "Trainers" }) do
	assert(loadfile("addons/ForeverData/Data/" .. f .. ".lua"))("ForeverData", data)
end
assert(loadfile("addons/ForeverData/Core.lua"))("ForeverData", data)

-- Stand-ins: a price for Turtle Scale, and two characters owning some.
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return id == 8167 and 150 or nil end } } }
Syndicator = { API = {
	GetAllCharacters = function() return { "Gorack-PvE Horde", "Pietjan-PvE Horde" } end,
	GetByCharacterFullName = function(name)
		if name == "Gorack-PvE Horde" then
			return { bags = { { { itemID = 8167, itemCount = 10 } } }, mail = { { itemID = 8167, itemCount = 2 } } }
		end
		return { bank = { { { itemID = 8167, itemCount = 3 }, { itemID = 2589, itemCount = 20 } } } }
	end,
} }

-- The game's item type names (Classic's), for type:.
local CLASS_NAMES = { [2] = "Weapon", [4] = "Armor", [9] = "Recipe" }
local SUBCLASS_NAMES = {
	[2] = { [0] = "One-Handed Axes", [1] = "Two-Handed Axes", [2] = "Bows", [7] = "One-Handed Swords", [8] = "Two-Handed Swords" },
	[4] = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" },
	[9] = { [0] = "Book", [2] = "Tailoring" },
}
C_Item = {
	GetItemClassInfo = function(class) return CLASS_NAMES[class] end,
	GetItemSubClassInfo = function(class, sub) return SUBCLASS_NAMES[class] and SUBCLASS_NAMES[class][sub] end,
}
local ns = {}
assert(loadfile("addons/ForeverSearch/Core.lua"))("ForeverSearch", ns)
check("ready", ns.Ready())

-- A list entry is {left, right}; as text it reads "left | right".
local function lineText(line)
	return type(line) == "table" and (line[1] .. " | " .. line[2]) or line
end
local function joined(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = lineText(line)
	end
	return table.concat(out, "\n")
end

local function has(lines, needle)
	for _, line in ipairs(lines) do
		if ns.Unlink(lineText(line)):find(needle, 1, true) then
			return true
		end
	end
	return false
end

local found = ns.Results("turtle scale")
check("results", #found > 0 and found[1].kind == "item" and found[1].id == 8167 and found[1].quality == 1, found[1] and found[1].name)

local lines = ns.Details("item", 8167)
check("item: drops have their own heading", has(lines, "Drops from (") and has(lines, "Skinned from ("), joined(lines))
check("item: a drop, the chance on its own", has(lines, "Stolid Snapjaw · Maraudon | 15%"), joined(lines))
local entry
for _, line in ipairs(lines) do
	if type(line) == "table" and ns.Unlink(line[1]):find("Stolid Snapjaw", 1, true) then entry = line break end
end
local rare
for _, line in ipairs(ns.Details("npc", 13599)) do
	if type(line) == "table" and ns.Unlink(line[1]):find("Reinforced Steel Lockbox", 1, true) then rare = line end
end
check("a chance under half a percent reads <1%", rare and rare[2] == "<1%", rare and lineText(rare))
check("item: a list entry is {name, chance}", entry and entry[2] == "15%" and not ns.Unlink(entry[1]):find("%", 1, true), entry and lineText(entry))
check("item: auction price", has(lines, "Auction: 1s 50c"))
check("item: owned", has(lines, "You own: 15 (Gorack 12, Pietjan 3)"))
check("item: no drop left out", not has(lines, "Gammerita: 14.69"))
check("unavailable items are not shipped", ForeverData.Item(16801) == nil and ForeverData.Item(19370) == nil)
check("nor found", (function()
	for _, r in ipairs(ns.Results("mantle of the blackwing cabal")) do
		if r.id == 19370 then return false end
	end
	return true
end)())
check("triggers are not shipped", (function()
	for _, r in ipairs(ns.Results("blackwing orb trigger")) do
		if r.name == "Blackwing Orb Trigger" then return false end
	end
	return true
end)())

lines = ns.Details("npc", 2505)
check("npc: level and neutral", has(lines, "level 49-50") and has(lines, "neutral"), lines[1])
check("npc: where", has(lines, "Where: The Hinterlands ("), joined(lines))
check("npc: gives, by way of getting", has(lines, "Drops (") and has(lines, "Skinning (") and has(lines, "Turtle Scale | "))

lines = ns.Details("npc", 54)
check("a vendor: by side", has(lines, "<Weaponsmith>") and has(lines, "friendly to Alliance, hostile to Horde"), lines[1])

lines = ns.Details("object", 1731)
check("object: where and contains", has(lines, "Where:") and has(lines, "Contains (") and has(lines, "Copper Ore | "), joined(lines))

-- An item sold for Merchant's Favor.
lines = ns.Details("item", 264201)
check("sold for Merchant's Favor", has(lines, "45 Merchant's Favor"), joined(lines))

local veins = ns.Results("copper vein")
check("one row a kind and name", veins[1] and veins[1].name == "Copper Vein" and #veins[1].ids >= 2 and (veins[2] == nil or veins[2].name ~= "Copper Vein"),
	veins[1] and #veins[1].ids)
check("subtitle of a creature", ns.Subtitle(ns.Results("saltwater snapjaw")[1]) == "Turtle · level 49-50 · The Hinterlands", ns.Subtitle(ns.Results("saltwater snapjaw")[1]))
check("a creature of no known kind says Creature", ns.Subtitle({ kind = "npc", id = 2462, ids = { 2462 } }):find("^Creature · level 25") ~= nil,
	ns.Subtitle({ kind = "npc", id = 2462, ids = { 2462 } }))
check("a humanoid says so", ns.Subtitle({ kind = "npc", id = 1718, ids = { 1718 } }):find("^Humanoid · ") ~= nil, ns.Subtitle({ kind = "npc", id = 1718, ids = { 1718 } }))
check("subtitle of an item", ns.Subtitle(ns.Results("turtle scale")[1]):find("^Item · item level 35 · 1s 50c") ~= nil, ns.Subtitle(ns.Results("turtle scale")[1]))
check("subtitle of an object", ns.Subtitle(veins[1]):find("^Object · .+ · %d+ of this name$") ~= nil, ns.Subtitle(veins[1]))
local text, kinds, options = ns.Parse("item: q:rare lvl:40-50 in:hinterlands cloak")
check("parse: kinds, quality, level, zone, text", text == "cloak" and kinds[1] == "item" and options.quality == 3
	and options.level[1] == 40 and options.level[2] == 50 and options.zone[1] == 47, text)
text, kinds, options = ns.Parse("in: blackrock q: rare lvl: 50-60 black")
local zoneNames = table.concat(options.zoneNames, ", ")
check("parse: a space after the colon takes the next word", text == "black" and options.quality == 3 and options.level[1] == 50
	and zoneNames:find("Blackrock Depths", 1, true) and zoneNames:find("Blackrock Spire", 1, true), text .. " | " .. zoneNames)
local _, _, sub = ns.Parse("in:goldshire")
check("parse: a subzone stands for its zone", sub.zone[1] == 12 and #sub.zone == 1 and sub.zoneNames[1] == "Goldshire (Elwynn Forest)",
	table.concat(sub.zone, ",") .. " " .. table.concat(sub.zoneNames, ","))
local _, _, both = ns.Parse("in:blackrock")
check("parse: whole zones win over subzones", (function()
	for _, id in ipairs(both.zone) do
		if ForeverData.Zone(id).parent then return false end
	end
	return #both.zone >= 2
end)(), table.concat(both.zoneNames, ", "))
check("bar: in: items by where they drop", (function()
	for _, r in ipairs(ns.Results("in:blackrock hand of", 30)) do
		if r.name == "Hand of Justice" then return true end
	end
	return false
end)())
check("bar: a zone alone fills the rows with distinct names", #ns.Results("in:blackrock", 30) == 30)
check("bar: in:goldshire finds Elwynn's creatures", #ns.Results("npc: in:goldshire kobold", 30) > 0)
check("bar: in: blackrock finds the Blackrock dungeons' creatures", (function()
	local r = ns.Results("in: blackrock dark iron", 30)
	return #r > 0
end)())
text, kinds, options = ns.Parse("npc:snapjaw lvl:40+ Q:EPIC weird:word")
check("parse: kind with text, open level, any case, unknown words kept", text == "snapjaw weird:word" and kinds[1] == "npc"
	and options.level[1] == 40 and options.level[2] == math.huge and options.quality == 4, text)
local function allOf(rows, test)
	for _, r in ipairs(rows) do
		if not test(r) then return false end
	end
	return #rows > 0
end
check("bar: rare items only", allOf(ns.Results("q:rare cloak", 30), function(r) return r.kind == "item" and (r.quality or 0) >= 3 end))
check("bar: creatures in a zone", allOf(ns.Results("npc: in:hinterlands", 30), function(r)
	for _, spot in ipairs(ForeverData.Spawns("npc", r.id)) do
		if spot.zone == 47 then return true end
	end
	return false
end))
check("bar: a level range", allOf(ns.Results("npc: lvl:49-50 snap", 30), function(r)
	local n = ForeverData.Npc(r.id)
	return n.minLevel <= 50 and (n.maxLevel or n.minLevel) >= 49
end))
check("bar: no such zone finds nothing", #ns.Results("npc: in:zzzzqq turtle", 30) == 0)
check("instance: the zone of that name", ns.ZoneByName("Blackrock Depths") == 1584 and ns.ZoneByName("blackrock depths") == 1584
	and ns.ZoneByName("Nowhere Land") == nil, ns.ZoneByName("Blackrock Depths"))
check("in: a full name with dashes is that zone only", (function()
	local _, _, o = ns.Parse("in:blackrock-depths")
	return #o.zone == 1 and o.zone[1] == 1584
end)())
check("in: the word for an instance", ns.InWord("Blackrock Depths") == "in:blackrock-depths" and ns.InWord("The Temple of Atal'Hakkar") == "in:the-temple-of-atalhakkar")
check("in: without the apostrophe", ns.Describe("in:kroldok-stronghold") == ns.Describe("in:krol'dok-stronghold") and ns.Describe("in:kroldok-stronghold"):find("Krol'dok Stronghold", 1, true) ~= nil, ns.Describe("in:kroldok-stronghold"))
check("in: a word of the name without the apostrophe", ns.Describe("in:atalhakkar"):find("Atal'Hakkar", 1, true) ~= nil, ns.Describe("in:atalhakkar"))
check("from: without the apostrophe", ns.FromWord("Gri'lek") == "from:grilek" and ns.Describe("from:grilek"):find("Gri'lek", 1, true) ~= nil, ns.Describe("from:grilek"))
check("in: the word reads back", (function()
	local _, _, o = ns.Parse(ns.InWord("The Temple of Atal'Hakkar") .. " hakkar")
	return o.zone and #o.zone == 1 and ForeverData.Zone(o.zone[1]).name == "The Temple of Atal'Hakkar"
end)())
check("describe: how filters were read", ns.Describe("item: q:rare lvl:40-50 in:blackrock-depths cloak") == "Blackrock Depths · items · rare or better · level 40-50",
	ns.Describe("item: q:rare lvl:40-50 in:blackrock-depths cloak"))
check("describe: nothing without filters", ns.Describe("turtle scale") == nil)
check("describe: an unknown zone", ns.Describe("in:zzzzqq") == "no such zone")
check("rank: by filters alone, best quality first, then type", (function()
	local r = ns.Results("in:ragefire-chasm item:", 30)
	local lastQ, lastClass = 99, -1
	for _, row in ipairs(r) do
		local it = ForeverData.Item(row.id)
		local q, c = it.quality or -1, it.class or 99
		if q > lastQ or (q == lastQ and c < lastClass) then
			return false
		end
		if q < lastQ then lastClass = -1 end
		lastQ, lastClass = q, c
	end
	return #r > 0
end)())
check("rank: the text still comes first", ns.Results("copper ore", 5)[1].name == "Copper Ore")
check("rank: a name with no extra words first, even with a typo", ns.Results("tutrle scale", 5)[1].name == "Turtle Scale", ns.Results("tutrle scale", 5)[1].name)
check("rank: with text too, items by quality", (function()
	-- Among the names that start with it (one tier of match), and leaving
	-- out an item named just "Scarlet" (no extra words: first by design).
	local r, last, n = ns.Results("item: scarlet", 30), 99, 0
	for _, row in ipairs(r) do
		if row.name:find("^Scarlet ") then
			local q = ForeverData.Item(row.id).quality or -1
			if q > last then return false end
			last, n = q, n + 1
		end
	end
	return n > 5
end)())
check("rank: items before creatures among equal matches", (function()
	local r, seenNpc = ns.Results("scarlet", 30), false
	for _, row in ipairs(r) do
		if row.kind == "npc" then seenNpc = true elseif row.kind == "item" and seenNpc then return false end
	end
	return true
end)())
local function raw(lines, needle)
	for _, line in ipairs(lines) do
		if lineText(line):find(needle, 1, true) then return true end
	end
	return false
end
-- Pages: a quest's, a vendor's, quests on a creature's and an item's, a zone's.
lines = ns.Details("quest", 7)
check("quest page: facts", has(lines, "level 2, from level 1, Alliance only"), joined(lines))
check("quest page: the side's crest", raw(lines, "|A:UI-HUD-UnitFrame-SmallCircle-Alliance:18:18:0:-3|a Alliance only"), joined(lines))
check("quest page: starts at, with where", has(lines, "Marshal McBride · Elwynn Forest 48.9, 41.6"), joined(lines))
check("quest page: objective", has(lines, "Kobold Vermin · Elwynn Forest"), joined(lines))
check("quest page: reputation", has(lines, "+100 Stormwind"), joined(lines))
check("quest page: chain", has(lines, "Requires one of:") and has(lines, "Leads to:") and has(lines, "Investigate Echo Ridge"), joined(lines))
check("quest page: item starter with its source", has(ns.Details("quest", 2), "Sharptalon's Claw · Sharptalon"), joined(ns.Details("quest", 2)))
lines = ns.Details("npc", 197)
check("creature page: quests it starts, level right", has(lines, "Starts quests (") and has(lines, "Kobold Camp Cleanup | 2"), joined(lines))
check("quest list: the other side's quest has its crest", raw(lines, "Kobold Camp Cleanup|r|h |A:UI-HUD-UnitFrame-SmallCircle-Alliance:18:18:0:-3|a"), joined(lines))
-- Gladius at Corina Steele: the client's buy price, 5s 36c (wowhead's 5s 68c
-- is a scanned price, not shipped since 2026-11-25).
check("vendor page: sells, price right", has(ns.Details("npc", 54), "Sells (") and has(ns.Details("npc", 54), "Gladius | 5s 36c"), joined(ns.Details("npc", 54)))
check("item page: starts a quest", has(ns.Details("item", 16305), "Starts a quest (1):"), joined(ns.Details("item", 16305)))
lines = ns.Details("zone", 12)
check("zone page: level range", has(lines, "creatures mostly level 1-11"), joined(lines))
check("zone page: quests, subzones' too", has(lines, "Quests here (79):"), joined(lines))
local herbFirst
for i, line in ipairs(lines) do
	if type(line) == "string" and line:find("Objects here", 1, true) then herbFirst = ns.Unlink(lines[i + 1]) break end
end
check("zone page: objects that give loot first", herbFirst and herbFirst ~= "  Book", herbFirst)
lines = ns.Details("zone", 47)
local firstFought
for i, line in ipairs(lines) do
	if type(line) == "string" and line:find("Creatures here", 1, true) then firstFought = ns.Unlink(lines[i + 1][1]) break end
end
check("zone page: the creatures you fight, most common first", firstFought == "  Savage Owlbeast", firstFought)
-- Links that search: the words the bar gets from a link's data.
local function linkWords(line, label)
	for data, text in string.gmatch(lineText(line), "|Hfsearch:find:([^|]+)|h|c%x%x%x%x%x%x%x%x([^|]*)|r|h") do
		if not label or text == label then
			return (string.gsub(data, ",", " "))
		end
	end
end
local function searchLink(lines, label)
	for _, line in ipairs(lines) do
		local words = linkWords(line, label)
		if words then
			return words
		end
	end
end
check("zone page: a link searching the zone", searchLink(lines, "Search in The Hinterlands") == "in:the-hinterlands", joined(lines))
check("zone page: and N more searches for the rest", has(lines, "and 42 more: quest: in:the-hinterlands")
	and searchLink(lines, "and 42 more") == "quest: in:the-hinterlands", joined(lines))
check("zone search link: its words find things in the zone", #ns.Results("in:the-hinterlands", 30) > 0)
do
	-- Clicking a zone in the results searches it: in: and the find's name.
	local zone
	for _, f in ipairs(ns.Results("blackrock depths", 30)) do
		if f.kind == "zone" then zone = zone or f end
	end
	local found = zone and ns.Results(ns.InWord(zone.name), 30) or {}
	check("zone result: in:<its name> finds things there", zone and zone.name == "Blackrock Depths" and #found > 0, zone and ns.InWord(zone.name) .. " " .. #found)
end
check("zone page: people with a title or a quest", has(lines, "People here (") and not has(lines, "Adventurer's Tent"), joined(lines))

check("links: an item's sources link to them", raw(ns.Details("item", 8167), "|Hfsearch:npc:2505|h"))
check("links: a creature's loot links to the items", raw(ns.Details("npc", 2505), "|Hfsearch:item:8167|h"))
check("links: where it stands links to the zone", raw(ns.Details("npc", 2505), "|Hfsearch:zone:47|h"))
check("zone page: its creatures, linked", has(ns.Details("zone", 47), "Creatures here (") and raw(ns.Details("zone", 47), "|Hfsearch:npc:"),
	joined(ns.Details("zone", 47)))
check("unlink keeps the name", ns.Unlink("  " .. ns.Link("npc", 2505) .. ": 1%") == "  Saltwater Snapjaw: 1%", ns.Unlink(ns.Link("npc", 2505)))
local function sets(typed, which, value, want)
	local got = ns.SetFilter(typed, which, value)
	check("SetFilter " .. which .. " " .. tostring(value) .. " on '" .. typed .. "'", got == want, "'" .. got .. "'")
end
sets("scarlet", "kind", "item", "item: scarlet")
sets("npc: scarlet", "kind", "item", "item: scarlet")
sets("npc:snapjaw lvl:40", "kind", "object", "object: snapjaw lvl:40")
sets("item: scarlet", "kind", nil, "scarlet")
sets("item: scarlet q:rare", "q", "epic", "q:epic item: scarlet")
sets("q: rare scarlet", "q", nil, "scarlet")
sets("in: blackrock black", "in", "in:the-hinterlands", "in:the-hinterlands black")
sets("lvl:10-20 wolf", "lvl", "57-63", "lvl:57-63 wolf")
sets("", "kind", "item", "item: ")
-- The Dungeons button: is:dungeon replaces another is:, and goes again.
sets("is:rare wail", "is", "dungeon", "is:dungeon wail")
sets("is:dungeon wail", "is", nil, "wail")
check("is:dungeon finds dungeons only", allOf(ns.Results("is:dungeon", 30), function(r)
	return r.kind == "zone" and ForeverData.Zone(r.id).instance == "dungeon"
end))
-- Dungeons by level, lowest first, each with its level range.
local dungeons = ns.Results("is:dungeon", 30)
check("dungeons: ordered by level", (function()
	local last = 0
	for _, r in ipairs(dungeons) do
		local low = ns.ZoneLevels(r.id)
		if low then
			if low < last then return false end
			last = low
		end
	end
	return #dungeons > 0
end)(), (function()
	local t = {}
	for _, r in ipairs(dungeons) do t[#t + 1] = r.name .. " " .. tostring(ns.ZoneLevels(r.id)) end
	return table.concat(t, ", ")
end)())
local rfc
for _, r in ipairs(dungeons) do if r.name == "Ragefire Chasm" then rfc = r end end
check("dungeons: the level range in the subtitle", rfc and ns.Subtitle(rfc):find("^Dungeon · level %d+%-%d+$"), rfc and ns.Subtitle(rfc))
-- Filter words: from:, is:, type:, class:, skill:, and the links to them.
local function all(results, test)
	if #results == 0 then return false end
	for _, r in ipairs(results) do
		if not test(r) then return false end
	end
	return true
end
local function ids(results)
	local out = {}
	for _, r in ipairs(results) do out[#out + 1] = r.kind .. r.id .. " " .. r.name end
	return table.concat(out, "; ")
end
local function contains(results, id)
	for _, r in ipairs(results) do
		for _, x in ipairs(r.ids or { r.id }) do
			if x == id then return true end
		end
	end
	return false
end

local found = ns.Results("from:saltwater-snapjaw", 300)
check("from: the items a creature gives, no grey ones", all(found, function(r) return r.kind == "item" end)
	and contains(found, 8167) and not contains(found, 4556), ids(found))
check("q:poor lets grey items back in", contains(ns.Results("from:saltwater-snapjaw q:poor", 300), 4556))
check("grey items stay out by default", not contains(ns.Results("speckled shell fragment", 30), 4556)
	and contains(ns.Results("speckled shell fragment q:poor", 30), 4556))
check("from: says what it read", ns.Describe("from:saltwater-snapjaw") == "from Saltwater Snapjaw", ns.Describe("from:saltwater-snapjaw"))
found = ns.Results("from:saltwater-snapjaw turtle", 30)
check("from: with words narrows by name, best first", found[1] and found[1].name:find("Turtle") and found[2] and found[2].name:find("Turtle"), ids(found))
check("from: a name that gives nothing finds nothing", #ns.Results("from:zzzzqqq", 30) == 0)
lines = ns.Details("npc", 2505)
check("creature page: and N more drops searches from:", searchLink(lines, "and 207 more") == "from:saltwater-snapjaw", joined(lines))
lines = ns.Details("npc", 4558)
check("vendor page: and N more sold searches from:", searchLink(lines, "and 24 more") == "from:lauren-newcomb", joined(lines))
check("from: a vendor finds all it sells", #ns.Results("from:lauren-newcomb", 100) == 39, #ns.Results("from:lauren-newcomb", 100))

found = ns.Results("is:rare in:the-hinterlands", 100)
check("is:rare: rare creatures there", all(found, function(r)
	local n = ForeverData.Npc(r.id)
	return r.kind == "npc" and (n.rank == 2 or n.rank == 4)
end), ids(found))
check("is:boss finds a world boss", contains(ns.Results("is:boss azuregos", 10), 6109))
-- No raid is open yet: their places, bosses and loot are not shipped.
check("no raid boss", #ns.Results("is:boss ragnaros", 10) == 0 and not ForeverData.Npc(11502))
check("no raid loot", not ForeverData.Item(16800) and #ns.Results("onyxia's lair", 10) == 0)
check("is:elite: elite creatures", all(ns.Results("is:elite in:blackrock-depths", 50), function(r)
	local n = ForeverData.Npc(r.id)
	return r.kind == "npc" and (n.rank == 1 or n.rank == 2)
end))
lines = ns.Details("npc", 2850)
local rankWords = searchLink(lines, "Rare")
check("rare creature page: Rare links to the zone's rares", rankWords and rankWords:find("^npc: is:rare in:"), joined(lines))
check("that link finds Broken Tooth", rankWords and contains(ns.Results(rankWords, 100), 2850), rankWords)

found = ns.Results("type:sword", 100)
check("type:sword: one- and two-handed swords", all(found, function(r)
	local it = ForeverData.Item(r.id)
	return r.kind == "item" and it.class == 2 and (it.subclass == 7 or it.subclass == 8)
end), ids(found))
check("type: says the types", ns.Describe("type:sword") == "One-Handed Swords, Two-Handed Swords", ns.Describe("type:sword"))
check("type:recipe: every recipe", all(ns.Results("type:recipe", 50), function(r) return ForeverData.Item(r.id).class == 9 end))
check("type: of no type finds nothing", #ns.Results("type:zzzz", 30) == 0 and ns.Describe("type:zzzz") == "type: no such item type")

found = ns.Results("class:shaman", 100)
check("class:shaman: shaman quests", all(found, function(r)
	local q = ForeverData.Quest(r.id)
	return r.kind == "quest" and q.classes and math.floor(q.classes / 64) % 2 == 1
end), ids(found))
check("class: a start of the name", ns.Describe("class:sham") == "Shaman quests", ns.Describe("class:sham"))
found = ns.Results("skill:fishing", 100)
check("skill:fishing: quests needing fishing", all(found, function(r) return ForeverData.Quest(r.id).skillLine == 356 end), ids(found))
check("is:repeatable", all(ns.Results("is:repeatable", 50), function(r) return ForeverData.Quest(r.id).repeatable end))
check("is:new", all(ns.Results("is:new in:elwynn", 50), function(r) return ForeverData.Quest(r.id).new end))
check("filter words take the next word", ns.Describe("from: saltwater-snapjaw") == "from Saltwater Snapjaw")

lines = ns.Details("zone", 12)
local range = searchLink(lines, "creatures mostly level 1-11")
check("zone page: the level range searches its creatures", range == "npc: in:elwynn-forest lvl:1-11", joined(lines))
check("that level search finds creatures", range and #ns.Results(range, 30) > 0)

-- Dungeons and raids.
check("a dungeon says so", ns.Subtitle({ kind = "zone", id = 1581, ids = { 1581 } }) == "Dungeon · level 18-20" and ns.KindLabel("zone", 12) == "Zone",
	ns.Subtitle({ kind = "zone", id = 1581, ids = { 1581 } }))
check("is:raid: none open yet", #ns.Results("is:raid", 50) == 0, ids(ns.Results("is:raid", 50)))
check("no Season of Discovery instance", not ForeverData.Zone(16236) and not ForeverData.Zone(15475))
found = ns.Results("is:battleground", 50)
check("is:battleground: the three, and Forever's two", #found == 5 and contains(found, 3277) and contains(found, 16653), ids(found))
check("an instance nothing is known to stand in: its bosses and their loot", (function()
	local r = ns.Results("in:kroldok-stronghold", 30)
	return contains(r, 258964) and #r > 5
end)())
check("a zone and a dungeon of one name: the dungeon", ns.Results("krol'dok str", 5)[1].id == 16842)
check("signposts stay out, unless object: is asked for", ns.Results("goldshire", 5)[1].kind == "zone" and (function()
	for _, r in ipairs(ns.Results("goldshire", 30)) do if r.kind == "object" then return false end end
	return true
end)() and ns.Results("object: goldshire", 5)[1].kind == "object")
check("flight master: by title", (function()
	local r = ns.Results("flight master", 30)
	for _, row in ipairs(r) do
		local t = ForeverData.Npc(row.id).title
		if not (t and (t:find("Master") or t:find("Handler") or t:find("Mistress"))) then return false end
	end
	return #r > 10
end)())
check("a title alone after the names that have it", ns.Results("innkeeper", 5)[1].name:find("^Innkeeper") ~= nil)
check("materials first: linen, silk, thorium", ns.Results("linen", 3)[1].name == "Linen Cloth" and ns.Results("silk", 3)[1].name == "Silk Cloth"
	and contains(ns.Results("thorium", 3), 10620))
check("zones and bosses before items of that name", ns.Results("scarlet", 3)[1].kind == "zone" and contains(ns.Results("scarlet", 3), 796)
	and ns.Results("stormwind", 3)[1].name == "Stormwind City" and ns.Results("deadmines", 3)[1].name == "The Deadmines"
	and ns.Results("whitemane", 3)[1].name == "High Inquisitor Whitemane")
check("junk names stay out", (function()
	for _, q in ipairs({ "doodad", "linen cloth", "ony" }) do
		for _, r in ipairs(ns.Results(q, 30)) do
			if r.name:find("^%[") or r.name:find("^Doodad") then return false end
		end
	end
	return true
end)())
check("an instance's page lists its bosses, loot known or not", (function()
	for _, l in ipairs(ns.Details("zone", 16842)) do
		if type(l) == "string" and l:find("Bosses %(") then return true end
	end
	return false
end)())
check("no near misses padding real matches", #ns.Results("mankrik", 30) == 1)
found = ns.Results("is:dungeon", 50)
check("is:dungeon: dungeons, The Deadmines among them", contains(found, 1581) and not contains(found, 2677), ids(found))
-- The other side's things are left out, as a Horde character.
UnitFactionGroup = function() return "Horde" end
check("side: the other side's quest is left out", not contains(ns.Results("kobold camp cleanup", 30), 7)
	and contains(ns.Results("side:both kobold camp cleanup", 30), 7))
check("side: the other side's people are left out", not contains(ns.Results("marshal mcbride", 30), 197)
	and contains(ns.Results("side:alliance marshal mcbride", 30), 197))
check("side: what both sides may fight stays", contains(ns.Results("kobold vermin", 30), 6))
check("side: says what it read", ns.Describe("side:both wolf") == "both sides", ns.Describe("side:both wolf"))
check("side: a kind alone still finds nothing", #ns.Results("item:", 30) == 0)
-- And the pages leave them out too.
lines = ns.Details("npc", 197)
check("page: the other side's quests are left out", not has(lines, "Starts quests"), joined(lines))
lines = ns.Details("zone", 12)
check("page: a zone's other-side people are left out", not has(lines, "Marshal McBride"), joined(lines))
local elwynnQuests = 0
for _, line in ipairs(lines) do
	local n = string.match(lineText(line), "Quests here %((%d+)%)")
	if n then elwynnQuests = tonumber(n) end
end
check("page: a zone's other-side quests are left out", elwynnQuests < 79, elwynnQuests)
local gladius = ns.Results("gladius", 5)[1]
lines = ns.Details("item", gladius.id)
check("page: the other side's vendors are left out", not has(lines, ForeverData.Npc(54).name), joined(lines))
check("page: side:both in the bar shows the other side's too", has(ns.Details("npc", 197, "side:both kobold"), "Starts quests"))
local function peopleCount(lines)
	for _, line in ipairs(lines) do
		local n = string.match(lineText(line), "People here %((%d+)%)")
		if n then return tonumber(n) end
	end
	return 0
end
check("page: side:alliance in the bar shows that side's people",
	peopleCount(ns.Details("zone", 12, "side:alliance")) > peopleCount(ns.Details("zone", 12)),
	peopleCount(ns.Details("zone", 12, "side:alliance")) .. " vs " .. peopleCount(ns.Details("zone", 12)))
check("page: side:alliance leaves out Horde quests", not has(ns.Details("zone", 3358, "side:alliance"), "Defiler's"),
	joined(ns.Details("zone", 3358, "side:alliance")))
UnitFactionGroup = nil
check("page: out of the game nothing is left out", has(ns.Details("npc", 197), "Starts quests"))

-- Arathi Basin: no unseen credit markers among its people; a repeatable
-- quest says so beside one of the same name and level.
lines = ns.Details("zone", 3358)
check("zone page: quest-only creatures are not people", not has(lines, "Credit Marker"), joined(lines))
check("quest list: a repeatable quest says so", has(lines, "Conquering Arathi Basin · repeatable")
	or has(lines, "Conquering Arathi Basin · repeatable"), joined(lines))
-- An item's page starts with the game's tooltip lines, the name and the
-- sell price left out; same-named sources are one entry.
local WHITE, GREY_C = { r = 1, g = 1, b = 1 }, { r = 0.5, g = 0.5, b = 0.5 }
C_TooltipInfo = { GetItemByID = function(id)
	return { lines = {
		{ type = 22, leftText = "Flurry Axe", leftColor = WHITE },
		{ type = 20, leftText = "Binds when equipped", leftColor = WHITE },
		{ type = 0, leftText = "One-Hand", leftColor = WHITE, rightText = "Axe", rightColor = WHITE },
		{ type = 11, leftText = "Sell Price:", leftColor = WHITE },
		{ type = 31, leftText = "Item Level 47", leftColor = GREY_C },
	} }
end }
lines = ns.Details("item", 871)
check("item page: the tooltip's lines", has(lines, "Binds when equipped") and has(lines, "One-Hand | Axe")
	and has(lines, "Item Level 47"), joined(lines))
check("item page: not its name or sell price", not has(lines, "Flurry Axe") and not has(lines, "Sell Price"), joined(lines))
check("item page: with a tooltip, no level line of its own", not has(lines, "requires level"), joined(lines))
C_TooltipInfo = nil
check("item page: without a tooltip, the level line", has(ns.Details("item", 871), "requires level"), joined(ns.Details("item", 871)))
local mercenaries = 0
for _, line in ipairs(ns.Details("item", 871)) do
	if ns.Unlink(lineText(line)):find("^  Defias Mercenary") then mercenaries = mercenaries + 1 end
end
check("item page: same-named sources are one entry", mercenaries == 1, mercenaries)

-- Abbreviations: alone they find their places first; in: takes them.
found = ns.Results("brd", 30)
check("abbreviation: brd finds Blackrock Depths first", found[1] and found[1].kind == "zone" and found[1].id == 1584, ids(found))
found = ns.Results("dm", 30)
check("abbreviation: dm is The Deadmines and Dire Maul", found[1] and found[2] and found[1].name == "The Deadmines" and found[2].name == "Dire Maul", ids(found))
check("abbreviation: in:brd", ns.Describe("in:brd") == "Blackrock Depths" and #ns.Results("in:brd", 30) > 0, ns.Describe("in:brd"))
-- A raid's abbreviation names a place not shipped: nothing, not a near miss.
check("abbreviation of a raid: in:bwl", ns.Describe("in:bwl") == "no such zone" and #ns.Results("in:bwl", 30) == 0, ns.Describe("in:bwl"))
check("abbreviation of a raid: bwl", #ns.Results("bwl", 30) == 0, ids(ns.Results("bwl", 30)))
check("abbreviation: in:dm is both", ns.Describe("in:dm") == "The Deadmines, Dire Maul", ns.Describe("in:dm"))
found = ns.Results("item: brd", 30)
check("abbreviation: not with another kind", not found[1] or found[1].kind == "item", ids(found))
for word in ("rfc wc dm vc sfk bfd stocks gnomer rfk sm rfd ulda uld zf mara st sunken-temple brd brs lbrs ubrs strat scholo av wsg ab stv epl wpl ungoro tb org sw if uc darn bb xroads"):gmatch("%S+") do
	check("abbreviation names a zone: " .. word, ns.Describe("in:" .. word) ~= "no such zone" and ns.Results(word, 5)[1].kind == "zone", ns.Describe("in:" .. word))
end

-- Only filter words: the lot, grouped: bosses, items, quests, creatures, objects.
found = ns.Results("in:sm", 1000, { grouped = true })
local groups = {}
for _, r in ipairs(found) do
	local g = r.kind == "npc" and ForeverData.Npc(r.id).boss and "boss" or r.kind
	if groups[#groups] ~= g then groups[#groups + 1] = g end
end
check("grouped: bosses, items, quests, creatures, objects", table.concat(groups, " ") == "boss item quest npc object", table.concat(groups, " "))
check("grouped: no heading rows", not found[1].header)
check("grouped: Herod among the bosses", contains(found, 3975), ids(found))
check("grouped: the Scarlet set is there", (function()
	for _, r in ipairs(found) do if r.name == "Scarlet Chestpiece" then return true end end
	return false
end)())
check("not grouped without asking", not ns.Results("in:sm", 30)[1].header)
check("boss: Herod is, a Scarlet Monk is not", ForeverData.Npc(3975).boss == true and ForeverData.Npc(4540).boss ~= true)

check("money", ns.Money(1234567) == "123g 45s 67c" and ns.Money(150) == "1s 50c" and ns.Money(7) == "7c")

-- Sold by, nearest first. A stand-in for the game's map calls: each map is
-- its own continent, 1000 yards across. The player stands in Durotar (1411)
-- at Razor Hill, 53.0, 42.0: Ghrawt (52.98, 41.03) is 10 yards off, Jark
-- (54.39, 42.18) 14; Orgrimmar's vendors are on another map, so no distance.
C_Map = {
	GetBestMapForUnit = function() return 1411 end,
	GetPlayerMapPosition = function() return { x = 0.53, y = 0.42 } end,
	GetWorldPosFromMapPos = function(map, v) return map, { x = v.x * 1000, y = v.y * 1000 } end,
}
function CreateVector2D(x, y) return { x = x, y = y } end
local function vendorLines(item)
	local out, on = {}, false
	for _, line in ipairs(ns.Details("item", item)) do
		local text = ns.Unlink(lineText(line))
		if text:find("^Sold by") then
			on = true
		elseif on and text:find("^  ") then
			out[#out + 1] = text
		elseif on then
			break
		end
	end
	return out
end
local sold = vendorLines(2512)
check("sold by: the nearest vendor first, where and how far", sold[1] and sold[1]:find("^  Ghrawt: ") and sold[1]:find("Durotar 53.0, 41.0, 10 yd", 1, true), table.concat(sold, "\n"))
check("sold by: then the next nearest", sold[2] and sold[2]:find("^  Jark: ") and sold[2]:find("14 yd", 1, true), sold[2])
local function rawLines(lines)
	local out = {}
	for _, line in ipairs(lines) do out[#out + 1] = lineText(line) end
	return out
end
local function firstWith(lines, needle)
	for _, l in ipairs(rawLines(lines)) do
		if ns.Unlink(l):find(needle, 1, true) then return l end
	end
end

-- Places: a click sets a waypoint; the nearest zone first, with its nearest spot.
local boar = firstWith(ns.Details("npc", 3098), "Where:")
check("where: the nearest spot of a many-spot zone, how far", boar and ns.Unlink(boar):find("^Where: Durotar %(%d+, nearest [%d.]+, [%d.]+, %d+ yd%)"), boar and ns.Unlink(boar))
check("where: a spot is a waypoint link", boar and boar:find("|Hfsearch:way:npc:3098:14:%d+:%d+|h"), boar)
-- A quest's giver: Gar'Thok in Razor Hill, 52.0, 43.5 as shipped: 18 yards.
local garthok = firstWith(ns.Details("quest", 825), "Gar'Thok · ")
check("quest giver: nearest spot and how far, clickable", garthok and ns.Unlink(garthok):find("Durotar 52.0, 43.5, 18 yd", 1, true)
	and garthok:find("|Hfsearch:way:npc:3139:14:5200:4350|h", 1, true), garthok)
-- Drop sources: at level 1, creatures of level 4 or less come first.
UnitLevel = function() return 1 end
local firstDrop
local inDrops = false
for _, l in ipairs(rawLines(ns.Details("item", 2589))) do
	if ns.Unlink(l):find("^Drops from") then
		inDrops = true
	elseif inDrops then
		firstDrop = tonumber(l:match("|Hfsearch:npc:(%d+)|h"))
		break
	end
end
UnitLevel = nil
check("drops from: a creature the player can fight first", firstDrop and ForeverData.Npc(firstDrop).minLevel <= 4,
	firstDrop and (ForeverData.Npc(firstDrop).name .. " " .. ForeverData.Npc(firstDrop).minLevel))

-- Waypoints: through TomTom (or ForeverGuide's stand-in), the last one taken
-- down first; without it the game's own map pin.
local added, removed = {}, 0
TomTom = {
	AddWaypoint = function(_, map, x, y, opts) added[#added + 1] = { map, x, y, opts.title }; return #added end,
	RemoveWaypoint = function() removed = removed + 1 end,
}
local set = ns.SetWaypoint("npc", 3165, 14, 52.98, 41.03)
ns.SetWaypoint("npc", 3164, 14, 54.39, 42.18)
check("waypoint: TomTom's arrow, on the zone's map, titled", set and added[1] and added[1][1] == 1411 and math.abs(added[1][2] - 0.5298) < 1e-9
	and added[1][4] == "Ghrawt", added[1] and table.concat({ tostring(added[1][1]), tostring(added[1][2]), tostring(added[1][4]) }, " "))
check("waypoint: the last one taken down first", removed == 1 and #added == 2, removed)
TomTom = nil
local pinned
C_Map.SetUserWaypoint = function(point) pinned = point end
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
check("waypoint: without TomTom the game's pin", ns.SetWaypoint("npc", 3165, 14, 52.98, 41.03) and pinned and pinned.map == 1411)
check("waypoint: none for a zone without a map", not ns.SetWaypoint("npc", 3165, 999999, 50, 50))
UiMapPoint = nil

-- The question behind the item: the lead line and what comes first, as a
-- level-12 Horde player at Razor Hill.
UnitLevel = function() return 12 end
UnitFactionGroup = function() return "Horde" end
local function lead(item)
	for _, l in ipairs(ns.Details("item", item)) do
		local t = ns.Unlink(lineText(l))
		if t:find("^Buy:") or t:find("^For:") or t:find("^Farm:") or t:find("^Get it:") then return t end
	end
end
local function before(item, a, b)
	local ia, ib
	for i, l in ipairs(ns.Details("item", item)) do
		local t = ns.Unlink(lineText(l))
		if not ia and t:find(a, 1, true) then ia = i end
		if not ib and t:find(b, 1, true) then ib = i end
	end
	return ia ~= nil and (ib == nil or ia < ib)
end
check("ammo: buy it from the nearest vendor", (lead(2512) or ""):find("^Buy: Ghrawt: 10c · Durotar"), lead(2512))
check("ammo: vendors before drops", before(2512, "Sold by (", "Drops from ("))
check("cloth: farm the nearest common creature", (lead(2589) or ""):find("^Farm: .- · Durotar"), lead(2589))
check("ore: farm the nearest vein, veins listed first", (lead(2770) or ""):find("^Farm: Copper Vein .- · Durotar") and before(2770, "Found in (", "Drops from ("), lead(2770))
check("quest item: the quest it is for", lead(5203) == "For: The Hunter's Way", lead(5203))
check("quest item: the quest before where it drops", before(5203, "Needed for quests (", "Drops from ("))
check("gear sold: buy it", (lead(2488) or ""):find("^Buy: Uhgar: 5s 36c"), lead(2488))
check("gear rewarded: the quest", lead(4928) == "Get it: reward from From The Wreckage....", lead(4928))
UnitLevel, UnitFactionGroup = nil, nil

check("sold by: no distance without a position", (function()
	C_Map.GetPlayerMapPosition = function() return nil end
	local lines = vendorLines(2512)
	C_Map = nil
	for _, l in ipairs(lines) do if l:find(" yd") then return false end end
	return #lines > 0
end)())

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("ok")
