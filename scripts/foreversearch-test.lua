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
for _, f in ipairs({ "Meta", "Items", "Npcs", "Objects", "Quests", "Zones", "Loot", "Spawns", "Vendors", "Trainers", "Levels", "Worth", "Recipes" }) do
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
-- A line as text: a list entry "left | right"; reward tiles "[tile: Name
-- x5] [tile: 1250 xp] [tile: money 2500]".
local function lineText(line)
	if type(line) == "table" and line.tiles then
		local out = {}
		for _, t in ipairs(line.tiles) do
			if t.item then
				out[#out + 1] = "[tile: " .. ns.NameOf("item", t.item) .. (t.n and t.n > 1 and (" x" .. t.n) or "") .. " |Hfsearch:item:" .. t.item .. "|h]"
			elseif t.xp then
				out[#out + 1] = "[tile: " .. t.xp .. " xp]"
			elseif t.faction then
				out[#out + 1] = "[tile: " .. ns.ReputationText(t) .. "]"
			else
				out[#out + 1] = "[tile: money " .. t.money .. "]"
			end
		end
		return table.concat(out, " ")
	end
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
check("item: a drop, the chance on its own", has(lines, "Stolid Snapjaw 1-2 · Maraudon | 15%"), joined(lines))
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
check("npc: level, no reaction in words (the crest shows it)", has(lines, "level 49-50") and not has(lines, "neutral"), joined(lines))
check("npc: where", has(lines, "Where: The Hinterlands ("), joined(lines))
check("npc: gives, by way of getting", has(lines, "Drops (") and has(lines, "Skinning (") and has(lines, "Turtle Scale 1-2 | "))

lines = ns.Details("npc", 54)
check("a vendor: no sides in words", not has(lines, "friendly") and not has(lines, "hostile"), joined(lines))
check("the title on its own line, first, no brackets", lines[1] == "Weaponsmith" and not has(lines, "<"), joined(lines))
check("the title in a list entry, no brackets", ns.Subtitle({ kind = "npc", id = 54, ids = { 54 } }):find(" · Weaponsmith · ", 1, true) ~= nil
	and not ns.Subtitle({ kind = "npc", id = 54, ids = { 54 } }):find("<", 1, true), ns.Subtitle({ kind = "npc", id = 54, ids = { 54 } }))

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
check("quest page: facts, the side not in words (the crest says it)", has(lines, "Level 2 requires level 1") and not has(lines, "Alliance only"), joined(lines))
check("quest page: starts at, with where", (ns.Unlink(joined(lines)) .. "\n"):find("Marshal McBride · Elwynn Forest\n", 1, true), joined(lines))
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
check("zone page: level range", has(lines, "creatures mostly level 2-11"), joined(lines))
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
check("zone page: and N more searches for the rest", ns.Unlink(joined(lines)):find("and %d+ more: quest: in:the%-hinterlands") ~= nil
	and searchLink(lines, (ns.Unlink(joined(lines)):match("and %d+ more"))) == "quest: in:the-hinterlands", joined(lines))
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
local dungeons = ns.Results("is:dungeon", 1000) -- as many as the window asks for
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
-- Scarlet Monastery is listed as its four wings, and one filters by either.
local wingRow = {}
for _, r in ipairs(dungeons) do wingRow[r.name] = r end
check("wings: the four are listed, the whole is not", wingRow["Scarlet Monastery - Graveyard"] and wingRow["Scarlet Monastery - Library"]
	and wingRow["Scarlet Monastery - Armory"] and wingRow["Scarlet Monastery - Cathedral"] and not wingRow["Scarlet Monastery"])
check("wings: Dire Maul's and the Spire's are, the wholes are not", wingRow["Dire Maul - East"] and wingRow["Dire Maul - West"] and wingRow["Dire Maul - North"]
	and wingRow["Lower Blackrock Spire"] and wingRow["Upper Blackrock Spire"] and not wingRow["Dire Maul"] and not wingRow["Blackrock Spire"])
check("wings: a wing's subtitle", wingRow["Scarlet Monastery - Library"]
	and ns.Subtitle(wingRow["Scarlet Monastery - Library"]):find("^Dungeon · level %d+%-%d+$"), ns.Subtitle(wingRow["Scarlet Monastery - Library"]))
check("wings: the whole is found by name, first", ns.Results("scarlet monastery", 10)[1].id == 796, ns.Results("scarlet monastery", 10)[1].name)
local function zonesOf(typed)
	local _, _, options = ns.Parse(typed)
	return table.concat(options.zone or {}, " ")
end
for typed, want in pairs({
	["in:sm"] = "796", ["in:scarlet-monastery"] = "796", ["in:scarlet"] = "796", ["in:library"] = "796002",
	["in:armory"] = "796003", ["in:cathedral"] = "796004", ["in:graveyard"] = "796001",
	[ns.InWord("Scarlet Monastery - Armory")] = "796003", ["in:lbrs"] = "1583001", ["in:ubrs"] = "1583002", ["in:brs"] = "1583",
	["in:spire"] = "1583", ["in:upper-blackrock"] = "1583002", ["in:dire-maul"] = "2557", [ns.InWord("Dire Maul - North")] = "2557003",
	[ns.InWord("Blackrock Spire")] = "1583", [ns.InWord("Dire Maul")] = "2557", ["in:goldshire"] = "12", ["in:dun-morogh"] = "1",
}) do
	check("wings: " .. typed, zonesOf(typed) == want, zonesOf(typed))
end
check("wings: a wing's in: word", ns.InWord("Scarlet Monastery - Armory") == "in:scarlet-monastery-armory", ns.InWord("Scarlet Monastery - Armory"))
check("wings: where the game says you are is the whole", zonesOf(ns.InWord("Scarlet Monastery")) == "796")
local function wingPage(id)
	local t = {}
	for _, line in ipairs(ns.Details("zone", id)) do
		t[#t + 1] = type(line) == "table" and table.concat({ line[1] or "", line[2] or "" }, " | ") or line
	end
	return table.concat(t, "\n")
end
local wholePage, armoryPage = wingPage(796), wingPage(796003)
check("wings: the whole's page links them, with levels", wholePage:find("Wings %(4%):|r\n[^\n]*|Hfsearch:zone:796001|h[^\n]* | %d+%-%d+\n[^\n]*|Hfsearch:zone:796002|h"), wholePage)
check("wings: the whole's page has all the bosses", wholePage:find("Hfsearch:npc:3975|", 1, true) and wholePage:find("Hfsearch:npc:3983|", 1, true))
check("wings: a wing's page has its own boss", armoryPage:find("Bosses (1)", 1, true) and armoryPage:find("Hfsearch:npc:3975|", 1, true), armoryPage)
check("wings: and is in the whole, with no wings", armoryPage:find("In |", 1, true) == 1 and armoryPage:find("Hfsearch:zone:796|", 1, true)
	and not armoryPage:find("Wings (", 1, true), armoryPage)
check("wings: and lists its quests", armoryPage:find("Hfsearch:quest:1048|", 1, true) ~= nil, armoryPage)
check("outside: Razorfen Kraul's page lists its quests", wingPage(491):find("Quests here (6)", 1, true) and wingPage(491):find("Hfsearch:quest:1101|", 1, true) ~= nil,
	wingPage(491))
check("wings: a creature's page says its wing", wingPage and (function()
	for _, line in ipairs(ns.Details("npc", 3975)) do
		if type(line) == "string" and line:find("Where:", 1, true) then
			return line:find("Hfsearch:zone:796003|", 1, true) ~= nil
		end
	end
end)())
-- Worked out in game, for data that ships none, a zone's levels come out as
-- the generator's: no critters (Elwynn Forest, Moonglade's and Darnassus'
-- rats and frogs alone).
do
	local shipped = ForeverData.ZoneLevels
	for id, name in pairs({ [12] = "Elwynn Forest", [493] = "Moonglade", [1657] = "Darnassus", [47] = "The Hinterlands" }) do
		ForeverData.ZoneLevels = function() return nil, nil, false end
		local low, high = ns.ZoneLevels(id)
		ForeverData.ZoneLevels = shipped
		local a, b = shipped(id)
		check("levels: " .. name .. " worked out in game as shipped", low == a and high == b,
			("%s-%s / %s-%s"):format(tostring(low), tostring(high), tostring(a), tostring(b)))
	end
	check("levels: Moonglade has none, only critters below its one", shipped(493) == nil)
end
-- How many come at once, after the name, when it is more than one.
do
	local real, realDrops = ForeverData.Loot, ForeverData.Drops
	ForeverData.Loot = function()
		return { { item = 2589, method = "drop", chance = 30, low = 1, high = 2 }, { item = 2592, method = "drop", chance = 20, low = 3, high = 3 },
			{ item = 8167, method = "drop", chance = 10 }, { item = 4306, method = "drop", chance = 5, low = 1, high = 1 } }
	end
	ForeverData.Drops = function(id)
		return id == 2589 and { { kind = "npc", id = 40, method = "drop", chance = 30, low = 1, high = 2 }, { kind = "npc", id = 3098, method = "drop", chance = 20 } } or realDrops(id)
	end
	local function left(kind, id, name)
		for _, l in ipairs(ns.Details(kind, id)) do
			if type(l) == "table" and l[1] and ns.Unlink(l[1]):find(name, 1, true) then return ns.Unlink(l[1]), l[2] end
		end
	end
	for name, want in pairs({ ["Linen Cloth"] = "  Linen Cloth 1-2", ["Wool Cloth"] = "  Wool Cloth 3", ["Turtle Scale"] = "  Turtle Scale", ["Silk Cloth"] = "  Silk Cloth" }) do
		check("amounts: on a creature's page, " .. want, left("npc", 46, name) == want, left("npc", 46, name))
	end
	check("amounts: the chance stays at the right", ns.Unlink(select(2, left("npc", 46, "Linen Cloth")) or "") == "30%", select(2, left("npc", 46, "Linen Cloth")))
	local miner, boar = left("item", 2589, "Kobold Miner"), left("item", 2589, "Mottled Boar")
	check("amounts: on the item's page, before the place", miner and miner:find("^  Kobold Miner 1%-2 · ") ~= nil, miner)
	check("amounts: one of it says nothing", boar and boar:find("^  Mottled Boar · ") ~= nil, boar)
	ForeverData.Loot, ForeverData.Drops = real, realDrops
	local silk
	for _, r in ipairs(ForeverData.Loot("npc", 4286)) do if r.item == 4306 then silk = r end end
	check("amounts: a Scarlet Soldier's silk, really", silk and silk.low and silk.high > 1, silk and silk.high)
end
-- How an item is made: each recipe, its reagents, what teaches it.
do
	local function created(id)
		local out, on = {}, false
		for _, l in ipairs(ns.Details("item", id)) do
			local t = ns.Unlink(lineText(l))
			if t == "Created by:" then on = true elseif on and t == "" then break end
			if on then out[#out + 1] = t end
		end
		return table.concat(out, "\n")
	end
	check("created by: Barbaric Bracers, by its pattern", created(18948) == "Created by:\n  Leatherworking | 130\n    8 Heavy Leather\n    2 Cured Heavy Hide\n"
		.. "    1 Raptor Hide\n    4 Small Lustrous Pearl\n    4 Large Fang\n    Learned from Pattern: Barbaric Bracers", created(18948))
	check("created by: nothing for a drop", created(8167) == "", created(8167))
	local real = ForeverData.CreatedBy
	ForeverData.CreatedBy = function()
		return { { spell = 2385, name = "Old Name", skillLine = 197, skill = 10, reagents = { { item = 2589, count = 1 } }, patterns = { 8167 } } }
	end
	check("created by: a recipe of another name, a pattern or a trainer", created(18948) == "Created by:\n  Tailoring · Old Name | 10\n    1 Linen Cloth\n"
		.. "    Learned from Turtle Scale or a trainer", created(18948))
	ForeverData.CreatedBy = real
end

-- What a reagent is used in: each recipe when they are few, else the
-- professions; uses: finds what they make.
do
	local function used(id)
		local out, on = {}, false
		for _, l in ipairs(ns.Details("item", id)) do
			local t = ns.Unlink(lineText(l))
			if t:find("^Used in") then on = true end
			if on then out[#out + 1] = t end
		end
		return table.concat(out, "\n")
	end
	check("used in: few, each recipe", used(8167):find("^Used in %(5%):\n  Turtle Scale Gloves · takes 8 · Leatherworking | 180\n"), used(8167))
	local real = ForeverData.UsedIn
	ForeverData.UsedIn = function()
		return { { spell = 1, name = "Enchant Boots", skillLine = 333, skill = 50, count = 1 }, { spell = 2, name = "x", skillLine = 165, item = 8167, count = 3 } }
	end
	check("used in: an enchantment by name, one of it not said, no skill", used(8167) == "Used in (2):\n  Enchant Boots · Enchanting | 50\n  Turtle Scale · takes 3 · Leatherworking | ", used(8167))
	ForeverData.UsedIn = function()
		local out = {}
		for i = 1, 9 do out[i] = { spell = i, name = "e" .. i, skillLine = i < 3 and 165 or 333, item = i < 3 and 8167 or nil } end
		return out
	end
	check("used in: many, by profession, most first", used(8167) == "Used in (9):\n  Enchanting | 7\n  Leatherworking | 2", used(8167))
	local raws = {}
	for _, l in ipairs(ns.Details("item", 8167)) do raws[#raws + 1] = lineText(l) end
	raws = table.concat(raws, "\n")
	check("used in: a profession that makes items searches them", raws:find("|Hfsearch:find:item:,uses:turtle-scale/leatherworking|h", 1, true) ~= nil, raws)
	check("used in: one of enchantments only does not", not raws:find("uses:turtle-scale/enchanting", 1, true))
	ForeverData.UsedIn = nil
	check("used in: with data that has none", used(8167) == "" and ns.Describe("uses:copper-bar") == "uses: needs a newer ForeverData")
	ForeverData.UsedIn = real
	check("used in: not a reagent", used(4928) == "", used(4928))
	local copper, smith = ns.Results("item: uses:copper-bar", 1000), ns.Results("item: uses:copper-bar/blacksmithing", 1000)
	check("uses: what is made with it", #copper > 40 and #smith > 30 and #smith < #copper, #copper .. " " .. #smith)
	check("uses: it makes them all", allOf(smith, function(r)
		for _, u in ipairs(real(2840)) do if u.item == r.id and u.skillLine == 164 then return true end end
	end))
	check("uses: described", ns.Describe("uses:copper-bar/blacksmithing") == "made with Copper Bar by Blacksmithing" and ns.Describe("uses:zzzz") == "uses: no such reagent"
		and ns.Describe("uses:copper-bar/zzzz") == "made with Copper Bar by no such profession" and #ns.Results("uses:copper-bar/zzzz", 10) == 0)
	check("uses: the exact name before another", ns.Describe("uses:leather") ~= nil and ns.Describe("uses:heavy-leather") == "made with Heavy Leather", ns.Describe("uses:heavy-leather"))
	local web = used(3182) -- Spider's Silk: in two professions, searched from its page
	local link
	for _, l in ipairs(ns.Details("item", 3182)) do link = link or lineText(l):match("|Hfsearch:find:(item:,uses:[^|]*)|h") end
	check("uses: an apostrophe, from the page's own link", link and ns.Describe((link:gsub(",", " "))):find("made with Spider's Silk by ", 1, true) ~= nil,
		web .. " / " .. tostring(link))
	check("uses: that link finds as many as the page says", link and #ns.Results((link:gsub(",", " ")), 1000) == tonumber(web:match("\n  %a+ | (%d+)")), web)
end
-- What a kill is worth, on a creature's page.
do
	local function worth(w, id, side)
		local real, faction = ForeverData.Worth, UnitFactionGroup
		ForeverData.Worth = w and function() return w end or nil
		UnitFactionGroup = function() return side end
		local found, at = nil, nil
		for i, l in ipairs(ns.Details("npc", id)) do
			if type(l) == "string" and l:find("Worth per kill", 1, true) then found, at = ns.Unlink(l), i end
		end
		ForeverData.Worth, UnitFactionGroup = real, faction
		return found, at
	end
	for text, w in pairs({
		["Worth per kill: 25c (items 17c, coin 8c)"] = { items = 17, coin = 8, basis = "forever" },
		["Worth per kill: 17c (items)"] = { items = 17, coin = 0, basis = "forever" },
		["Worth per kill: 8c (coin)"] = { items = 0, coin = 8 },
		["Worth per kill: 1s 10c (items 1s 00c, coin 10c, drops counted in Classic Era)"] = { items = 100, coin = 10, basis = "classic_era" },
		["Worth per kill: 10c (items, Classic's drops)"] = { items = 10, coin = 0, basis = "classic_table" },
	}) do
		check("worth: " .. text, worth(w, 40, "Horde") == text, worth(w, 40, "Horde"))
	end
	local some = { items = 17, coin = 8, basis = "forever" }
	check("worth: not of one friendly to you (Gar'Thok)", worth(some, 3139, "Horde") == nil and worth(some, 3139, "Alliance") ~= nil)
	check("worth: with data that has none", worth(nil, 40, "Horde") == nil)
	check("worth: the real Kobold Miner's", (function()
		for _, l in ipairs(ns.Details("npc", 40)) do
			if type(l) == "string" and ns.Unlink(l):find("^Worth per kill: %d+c %(items %d+c, coin %d+c%)$") then return true end
		end
	end)())
end
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

-- The words about an item and about a quest giver, and the pages' "and N
-- more" lines that search them: each finds as many as its list counts
-- (quests of one name are one find, so their ids are counted).
local function heading(lines, title)
	for _, l in ipairs(lines) do
		local n = ns.Unlink(lineText(l)):match("^" .. title .. " %((%d+)%):$")
		if n then return tonumber(n) end
	end
end
local function finds(query)
	local n = 0
	for _, r in ipairs(ns.Results((query:gsub(",", " ")), 2000)) do n = n + #(r.ids or { r.id }) end
	return n, #ns.Results((query:gsub(",", " ")), 2000)
end
local function moreLink(lines, title)
	local on = false
	for _, l in ipairs(lines) do
		local t = lineText(l)
		if ns.Unlink(t):find("^" .. title .. " %(") then on = true elseif on and ns.Unlink(t) == "" then return nil end
		if on and ns.Unlink(t):find("^  and %d+ more") then return t:match("|Hfsearch:find:([^|]*)|h") or false end
	end
end
lines = ns.Details("item", 2589)
local link = moreLink(lines, "Drops from")
check("drops: Linen Cloth's droppers link", link == "npc:,drops:linen-cloth", link)
check("drops: as many as the page lists", select(2, finds(link or "")) == heading(lines, "Drops from"), select(2, finds(link or "")))
check("drops: only creatures that drop it", all(ns.Results("drops:linen-cloth", 50), function(r)
	if r.kind ~= "npc" then return false end
	for _, d in ipairs(ForeverData.Drops(2589)) do if d.kind == "npc" and d.id == r.id and d.method == "drop" then return true end end
	return false
end))
check("drops: says what it read", ns.Describe("drops:linen-cloth") == "dropping Linen Cloth", ns.Describe("drops:linen-cloth"))
lines = ns.Details("item", 2770)
link = moreLink(lines, "Found in")
check("contains: Copper Ore's veins and lockboxes link", link == "contains:copper-ore", link)
check("contains: as many as the page lists, items holding it too", select(2, finds(link or "")) == heading(lines, "Found in")
	and contains(ns.Results("contains:copper-ore", 50), 1731), select(2, finds(link or "")))
lines = ns.Details("item", 2512)
link = moreLink(lines, "Sold by")
check("sells: Rough Arrow's vendors link", link == "npc:,sells:rough-arrow", link)
check("sells: as many as the page lists", select(2, finds(link or "")) == heading(lines, "Sold by"), select(2, finds(link or "")))
lines = ns.Details("item", 2318)
check("skinning: no word for it, the rest in plain text", moreLink(lines, "Skinned from") == false, moreLink(lines, "Skinned from"))
lines = ns.Details("npc", 4949)
link = moreLink(lines, "Starts quests")
check("starts: Thrall's quests link", link == "quest:,starts:thrall", link)
check("starts: as many as the page lists", finds(link or "") == heading(lines, "Starts quests"), finds(link or ""))
link = moreLink(lines, "Ends quests")
check("ends: as many as the page lists", link == "quest:,ends:thrall" and finds(link) == heading(lines, "Ends quests"), link)
check("starts: says what it read", ns.Describe("starts:thrall") == "quests started by Thrall", ns.Describe("starts:thrall"))
lines = ns.Details("item", 4306)
link = moreLink(lines, "Needed for quests")
check("needs: Silk Cloth's quests link", link == "quest:,needs:silk-cloth" and finds(link) == heading(lines, "Needed for quests"), link)
check("needs: the exact name, though no quest needs it", ns.Describe("needs:turtle-scale") == "quests needing Turtle Scale"
	and #ns.Results("needs:turtle-scale", 10) == 0, ns.Describe("needs:turtle-scale"))
check("rewards: the quest that gives it", (function()
	local word = ns.ItemWord("rewards", ForeverData.Item(4928).name)
	for _, row in ipairs(ForeverData.QuestsOf("item", 4928)) do
		if row.role == "reward" and not contains(ns.Results(word, 10), row.quest) then return false end
	end
	return #ns.Results(word, 10) >= 1 and ns.Describe(word) == "quests rewarding " .. ForeverData.Item(4928).name
end)(), ns.Describe(ns.ItemWord("rewards", ForeverData.Item(4928).name)))
check("an item word keeps its apostrophe", ns.ItemWord("drops", "Spider's Silk") == "drops:spider's-silk"
	and ns.Describe("drops:spider's-silk") == "dropping Spider's Silk", ns.Describe("drops:spider's-silk"))
check("a giver word drops it, as from: does", ns.GiverWord("starts", "Gri'lek") == "starts:grilek")
-- drops: and contains: give each find its chance: shown on the right, and
-- with no other words the order, highest first, all of them.
do
	local rows = ns.Results("npc: drops:silk-cloth", 1000)
	local sorted, shown = #rows > 100, true
	for i, r in ipairs(rows) do
		if i > 1 and (r.chance or -1) > (rows[i - 1].chance or -1) then sorted = false end
		shown = shown and r.right ~= nil and r.right:find("%%$") ~= nil
	end
	check("drops: highest chance first", sorted, rows[1] and rows[1].name)
	check("drops: each find's chance on the right", shown, rows[1] and rows[1].right)
	local best = 0
	for _, d in ipairs(ForeverData.Drops(4306)) do
		if d.kind == "npc" and d.method == "drop" then best = math.max(best, d.chance or 0) end
	end
	check("drops: the first is the likeliest", rows[1] and rows[1].chance == best, rows[1] and rows[1].chance)
	check("drops: the likeliest of all, not of the search's first 30", (ns.Results("npc: drops:silk-cloth", 30)[1] or {}).chance == best,
		(ns.Results("npc: drops:silk-cloth", 30)[1] or {}).chance)
	check("drops: words keep their order, the chance still shown", (function()
		local r = ns.Results("drops:silk-cloth defias", 30)
		return #r > 0 and r[1].right ~= nil
	end)())
	check("contains: by chance too", (ns.Results("contains:copper-ore", 50)[1] or {}).right ~= nil)
	check("sells: no chance", (ns.Results("sells:rough-arrow", 50)[1] or {}).right == nil)
end

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
local range = searchLink(lines, "creatures mostly level 2-11")
check("zone page: the level range searches its creatures", range == "npc: in:elwynn-forest lvl:2-11", joined(lines))
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

-- Cutting a line off: by what one sees, its codes whole.
do
	local line = "|cff66bbff|Hfsearch:npc:1|hDún Morogh|h|r |A:crest:18:18|a · x||y"
	for n, want in pairs({ [0] = "|cff66bbff|Hfsearch:npc:1|h...|h|r", [2] = "|cff66bbff|Hfsearch:npc:1|hDú...|h|r",
		[12] = "|cff66bbff|Hfsearch:npc:1|hDún Morogh|h|r |A:crest:18:18|a...", [99] = line }) do
		check("cut: " .. n, ns.CutText(line, n) == want, (ns.CutText(line, n)))
	end
	check("cut: how many there are", select(2, ns.CutText(line, 99)) == 18, select(2, ns.CutText(line, 99)))
end

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
check("sold by: the nearest vendor first, its zone and nothing more", sold[1] and sold[1]:find("^  Ghrawt · Durotar$"), table.concat(sold, "\n"))
check("sold by: then the next nearest", sold[2] and sold[2]:find("^  Jark · Durotar$"), sold[2])
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
local ghrawt = firstWith(ns.Details("item", 2512), "  Ghrawt")
check("sold by: the zone is a waypoint to the vendor", ghrawt and ghrawt:find("|Hfsearch:way:npc:%d+:14:5300:4100|hDurotar|h"), ghrawt)
-- The price once, at the top, never per vendor.
local function count(item, text)
	local n = 0
	for _, l in ipairs(ns.Details("item", item)) do
		if ns.Unlink(lineText(l)):find(text, 1, true) then n = n + 1 end
	end
	return n
end
check("vendor price: once, at the top", firstWith(ns.Details("item", 2512), "Vendor:") and ns.Unlink(firstWith(ns.Details("item", 2512), "Vendor:")) == "Vendor: 10c"
	and count(2512, "10c") == 1, joined(ns.Details("item", 2512)))
local shipped = ForeverData.Vendors
ForeverData.Vendors = function(id)
	local rows = shipped(id)
	if id ~= 2512 then return rows end
	local out = {}
	for i, r in ipairs(rows) do out[i] = { npc = r.npc, price = i > 1 and r.price or nil, stock = r.npc == 3165 and 3 or nil } end
	return out
end
check("vendor price: the known one, where the first vendor's is not", ns.Unlink(firstWith(ns.Details("item", 2512), "Vendor:") or "none") == "Vendor: 10c"
	and count(2512, "10c") == 1, joined(ns.Details("item", 2512)))
check("vendor price: not on the vendors' lines, stock still is", vendorLines(2512)[1] == "  Ghrawt (3 in stock) · Durotar"
	and vendorLines(2512)[2] == "  Jark · Durotar" and count(2512, "unknown") == 0, table.concat(vendorLines(2512), "\n"))
ForeverData.Vendors = function(id)
	local out = {}
	for i, r in ipairs(shipped(id)) do out[i] = { npc = r.npc } end
	return out
end
check("vendor price: unknown where no vendor's is known", ns.Unlink(firstWith(ns.Details("item", 2512), "Vendor:") or "none") == "Vendor: unknown"
	and count(2512, "unknown") == 1)
ForeverData.Vendors = shipped
UnitFactionGroup = function() return "Horde" end
local theirs = {}
ForeverData.Vendors = function(id)
	local out = {}
	for i, r in ipairs(shipped(id)) do
		local n = ForeverData.Npc(r.npc)
		out[i] = { npc = r.npc, price = n and n.horde == "hostile" and 99 or r.price }
		if n and n.horde == "hostile" then theirs[#theirs + 1] = r.npc end
	end
	return out
end
local ours = ns.Unlink(firstWith(ns.Details("item", 2512), "Vendor:") or "none")
check("vendor price: the other side's does not count", #theirs > 0 and ours == "Vendor: 10c", #theirs .. " " .. ours)
ForeverData.Vendors, UnitFactionGroup = shipped, nil
check("vendor price: none where no one sells it", not firstWith(ns.Details("item", 2589), "Vendor:"))
-- A quest's giver: Gar'Thok in Razor Hill, 52.0, 43.5 as shipped.
local garthok = firstWith(ns.Details("quest", 825), "Gar'Thok · ")
check("quest giver: its zone, a click to its nearest spot", garthok and ns.Unlink(garthok):find("Gar'Thok · Durotar$")
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

-- The question behind the item: what comes first, and no lead line, as a
-- level-12 Horde player at Razor Hill.
UnitLevel = function() return 12 end
UnitFactionGroup = function() return "Horde" end
local function lead(item)
	for _, l in ipairs(ns.Details("item", item)) do
		local t = ns.Unlink(lineText(l))
		if t:find("^Buy:") or t:find("^For:") or t:find("^From:") or t:find("^Farm:") or t:find("^Get it:") then return t end
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
for _, item in ipairs({ 2512, 2589, 2770, 5203, 2488, 4928, 18948 }) do
	check("no lead line: " .. item, lead(item) == nil, lead(item))
end
check("ammo: vendors before drops", before(2512, "Sold by (", "Drops from ("))
check("ore: veins listed first", before(2770, "Found in (", "Drops from ("))
check("quest item: the quest before where it drops", before(5203, "Needed for quests (", "Drops from ("))
UnitLevel, UnitFactionGroup = nil, nil

check("sold by: no nearest without a position", (function()
	C_Map.GetPlayerMapPosition = function() return nil end
	local lines = vendorLines(2512)
	C_Map = nil
	for _, l in ipairs(lines) do if l:find("further off") then return false end end
	return #lines > 0 and lines[1]:find(" · [%a' ]+$") ~= nil
end)())

-- The crest at the top of a page: a quest only one side may take, a
-- creature friendly to one side alone; none for both, monsters or items.
check("crest: a Horde quest", ns.PageSide("quest", 825) == "Horde", ns.PageSide("quest", 825))
check("crest: a Horde creature", ns.PageSide("npc", 3139) == "Horde", ns.PageSide("npc", 3139))
check("crest: none for a monster", ns.PageSide("npc", 3098) == nil)
check("crest: none for an item", ns.PageSide("item", 2589) == nil)
check("crest: both for a creature friendly to both", ns.PageSide("npc", 2483) == "Both", ns.PageSide("npc", 2483))
check("crest: a quest with no race side takes its giver's", ns.PageSide("quest", 5) == "Alliance", ns.PageSide("quest", 5))
check("crest: both for a quest either side's people give", ns.PageSide("quest", 8948) == "Both", ns.PageSide("quest", 8948))

-- Class icons at the top of a class quest's page.
local function icons(q) return table.concat(ns.PageClasses("quest", q), " ") end
check("class icons: one class", icons(26) == "classicon-druid", icons(26))
check("class icons: two", icons(5301) == "classicon-warrior classicon-paladin", icons(5301))
check("class icons: none for any class", icons(2) == "")
check("class icons: none past five (all but Warlock)", icons(792) == "", icons(792))

-- Race portraits at the top of a quest for part of its side.
local function races(q) return table.concat(ns.PageRaces("quest", q), " ") end
check("race icons: one race", races(5627) == "raceicon-nightelf-male", races(5627))
check("race icons: two races", races(6365) == "raceicon-orc-male raceicon-troll-male", races(6365))
check("race icons: Forever's Skyborne", races(92551) == "raceicon-skyborne-male", races(92551))
check("race icons: none for a quest for a whole side", races(825) == "", races(825))
UnitSex = function() return 3 end
check("race icons: the player's gender", races(5627) == "raceicon-nightelf-female", races(5627))
UnitSex = nil
check("a Skyborne quest is its side's", ns.PageSide("quest", 92551) == "Alliance", ns.PageSide("quest", 92551))

check("quest page: classes not in words beside their icons", not has(ns.Details("quest", 26), "Druid only"), joined(ns.Details("quest", 26)))
check("quest page: classes in words past five icons", has(ns.Details("quest", 792), "only"), joined(ns.Details("quest", 792)))

-- race: what a race icon's click searches: quests for part of a side,
-- that race among them.
local function questsWith(q, icon)
	local found = ns.Results(q, 1000)
	if #found == 0 then return false, 0 end
	for _, r in ipairs(found) do
		if r.kind ~= "quest" or not table.concat(ns.PageRaces("quest", r.id), " "):find(icon, 1, true) then return false, r.id end
	end
	return true, #found
end
local ok, n = questsWith("quest: race:tauren", "raceicon-tauren")
check("race:tauren finds the Tauren quests, only those", ok, n)
ok, n = questsWith("quest: race:skyborne side:both", "raceicon-skyborne")
check("race:skyborne finds both Skyborne's quests", ok and n >= 24, n)
check("race: no such race finds nothing", #ns.Results("quest: race:murloc", 30) == 0)

-- Money and currencies: in letters out of the game; with the game's icons
-- where it gives them (its coin string, a currency's icon).
check("money in letters", ns.Money(150) == "1s 50c", ns.Money(150))
check("a currency by name", ns.Currency(45, 3402) == "45 Merchant's Favor", ns.Currency(45, 3402))
GetCoinTextureString = function(c) return "<coins " .. c .. ">" end
C_CurrencyInfo = { GetCurrencyInfo = function(id) return id == 3402 and { name = "Merchant's Favor", iconFileID = 4696085 } or nil end }
check("money with the game's coin icons", ns.Money(150) == "<coins 150>", ns.Money(150))
check("a currency with its icon", ns.Currency(45, 3402) == "45 |T4696085:0|t", ns.Currency(45, 3402))
check("a vendor's price in a currency on the page", raw(ns.Details("item", 249476), "45 |T4696085:0|t"), joined(ns.Details("item", 249476)))
check("a currency the game does not know, by our name", ns.Currency(3, 1) == "3 currency 1", ns.Currency(3, 1))
GetCoinTextureString, C_CurrencyInfo = nil, nil

-- What else a quest asks before it is offered (QuestieDB's fields 19-21,
-- 30-36), on its page and as icons.
check("standing: a step", ns.Standing(9000) == "Honored" and ns.Standing(0) == "Neutral" and ns.Standing(-3000) == "Unfriendly",
	ns.Standing(9000) .. " " .. ns.Standing(0) .. " " .. ns.Standing(-3000))
check("standing: between steps, the points", ns.Standing(5500) == "Friendly 5500", ns.Standing(5500))
local function needs(q) return table.concat(ns.QuestNeeds(ForeverData.Quest(q)), " / ") end
local function plain(q) return ns.Unlink(needs(q)) end
check("needs: a minimum reputation", plain(8584):find("^Neutral with %a"), plain(8584))
check("needs: a maximum reputation", plain(7898):find("at most Friendly 5500 with %a"), plain(7898))
check("needs: items to have, linked", needs(8240):find("have |Hfsearch:item:", 1, true), needs(8240))
check("needs: a spell not to know", plain(97899):find("^not know "), plain(97899))
check("needs: a specialisation, by name", plain(5307) == "Weaponsmith", plain(5307))
check("needs: the Gnomish Engineer specialisation", plain(3645):find("Gnomish Engineer", 1, true), plain(3645))
-- 202 in the specialisation field is Engineering's skill line, not spell
-- 202 (Two-Handed Swords); Goblin Engineering asks Engineering 200 already.
check("needs: a profession it already asks for is not said again", plain(3526) == "", plain(3526))
check("no Two-Handed Swords on Goblin Engineering's page", not has(ns.Details("quest", 3526), "Two-Handed Swords"), joined(ns.Details("quest", 3526)))
check("needs: offered until a quest is done", needs(2300):find("offered until |Hfsearch:quest:2281|h", 1, true), needs(2300))
check("needs: offered from a quest on", needs(1918):find("offered from |Hfsearch:quest:25|h", 1, true), needs(1918))
check("needs: no longer offered after a quest", needs(9422):find("no longer offered once |Hfsearch:quest:9416|h", 1, true), needs(9422))
-- Ranks: only Omarion's Handbook (9233) asks them, a Naxxramas quest not
-- shipped while raids are closed: a quest as its data reads.
local ranks = ns.Unlink(table.concat(ns.QuestNeeds({ ranks = { { line = 197, value = -4 }, { line = 164, value = -4 }, { line = 165, value = -4 } } }), " / "))
check("needs: ranks", ranks == "ranks of Tailoring, Blacksmithing, Leatherworking", ranks)
check("needs: on the page", has(ns.Details("quest", 2300), "Needs (1):") or has(ns.Details("quest", 2300), "Needs:"), joined(ns.Details("quest", 2300)))
check("max level among the facts", has(ns.Details("quest", 98910), "up to level 39"), joined(ns.Details("quest", 98910)))
check("no max level from a spell (the old field 30)", not has(ns.Details("quest", 97899), "up to level"), joined(ns.Details("quest", 97899)))
local function badge(q, test)
	for _, b in ipairs(ns.PageBadges("quest", q)) do
		if test(b) then return b end
	end
end
local eng = badge(3526, function(b) return b.file == 136243 end)
check("a profession's icon, a search for its quests", eng and eng.query == "quest: skill:engineering" and eng.label == "Engineering 200",
	eng and (tostring(eng.query) .. " " .. tostring(eng.label)))
local rep = badge(8584, function(b) return b.file == 236681 end)
check("the reputation icon, naming what is needed", rep and rep.query == nil and rep.more and rep.more[1]:find("^Neutral with"),
	rep and rep.more and rep.more[1])
check("no reputation icon where none is needed", badge(26, function(b) return b.file == 236681 end) == nil)

-- One section for a quest given and taken in by the same: Melding of
-- Influences (4642), Chemist Fuely. Two where they differ: Meats to
-- Orgrimmar (6365), Zargh to Devrak.
local melding = ns.Details("quest", 4642)
check("starts and ends at the same: one section", has(melding, "Starts and ends at (") or has(melding, "Starts and ends at:"),
	joined(melding))
check("starts and ends at the same: not twice", not has(melding, "Starts at") and not has(melding, "Ends at"), joined(melding))
local meats = ns.Details("quest", 6365)
check("starts and ends apart: both", has(meats, "Starts at") and has(meats, "Ends at") and not has(meats, "Starts and ends at"),
	joined(meats))

-- Season of Discovery's Emerald Wardens missions say they are gone ("This
-- quest is no longer available within the game."): not shipped, not found.
check("a quest no longer in the game is not shipped", ForeverData.Quest(81855) == nil and ForeverData.Quest(81786) == nil)
check("nor found", #ns.Results("quest: feralas mission", 30) == 0 and #ns.Results("quest: hinterlands mission", 30) == 0,
	#ns.Results("quest: feralas mission", 30))

-- (Reputation is among the rewards: no section of its own.)
-- Rewards as the quest log shows them (ForeverDB's guide, seen in Forever):
-- Centaur Bracers (855) lets choose one of three weapons and gives 1,250
-- experience; Raptor Horns (865) gives five Raptor Punch and a cloak.
local function rewardText(q)
	local out, on = {}, false
	for _, line in ipairs(ns.Details("quest", q)) do
		local t = ns.Unlink(lineText(line))
		if t == "Rewards" then on = true elseif on and t == "" then break end
		if on then out[#out + 1] = t end
	end
	return table.concat(out, " / ")
end
local bracers = rewardText(855)
check("rewards: a heading, the choice, then what else", bracers:find("^Rewards / You will be able to choose one of these rewards: / %[tile: Orcish Battle Bow") ~= nil
	and bracers:find("You will also receive: / [tile: 1250 xp]", 1, true) ~= nil, bracers)
check("rewards: three to choose from", select(2, bracers:gsub("%[tile: [^%]]-Orcish Battle Bow", "")) + select(2, bracers:gsub("Pointed Axe", "")) + select(2, bracers:gsub("Stonewood Hammer", "")) == 3, bracers)
local horns = rewardText(865)
check("rewards: given, with how many, under You will receive", horns:find("You will receive: / [tile: Raptor Punch x5", 1, true) ~= nil
	and horns:find("Barkeeper's Cloak", 1, true) ~= nil and not horns:find("choose", 1, true), horns)

-- Reputation among what a quest gives: Melding of Influences (4642) +150
-- Undercity, after its items; no Reputation section.
local melding = rewardText(4642)
-- No source says whether its two items are given or to choose: as given.
check("rewards: items of no known kind are given", melding:find("^Rewards / You will receive: / %[tile: Chemist's ") ~= nil
	and not melding:find("sources", 1, true), melding)
check("rewards: reputation among what one receives", melding:find("[tile: +150 Undercity]", 1, true) ~= nil, melding)
check("rewards: no reputation section of its own", not has(ns.Details("quest", 4642), "Reputation:"), joined(ns.Details("quest", 4642)))
-- A quest that gives only reputation still has a Rewards section, and one
-- that takes some away shows it as a loss.
local only, loss
for id in pairs(data.quests) do
	local q = ForeverData.Quest(id)
	local nothingElse = #q.rewards == 0 and #q.choices == 0 and #q.given == 0 and not q.xp and not q.money
	for _, r in ipairs(q.reputation) do
		if r.value < 0 and (not loss or id < loss) then loss = id end
		if nothingElse and r.value > 0 and (not only or id < only) then only = id end
	end
end
check("rewards: a quest with only reputation to give", only and rewardText(only):find("You will receive: / [tile: +", 1, true) ~= nil,
	only and (only .. " " .. rewardText(only)) or "no such quest")
check("rewards: a loss reads as a minus", loss and rewardText(loss):find("%[tile: %-%d+ ") ~= nil, loss and (loss .. " " .. rewardText(loss)) or "no such quest")

-- One item to choose is no choice: every quest with a single one has it as
-- given (Making Repairs, 91316); with two or more it stays a choice.
local singles, wrong, lost = 0, {}, {}
for id in pairs(data.quests) do
	local q = ForeverData.Quest(id)
	if #q.choices == 1 then
		singles = singles + 1
		local text = rewardText(id)
		if text:find("choose", 1, true) then wrong[#wrong + 1] = id end
		if not text:find(ForeverData.Item(q.choices[1].item).name, 1, true) then lost[#lost + 1] = id end
	end
end
check("rewards: a single choice is given, not to choose", singles > 0 and #wrong == 0, singles .. " singles, wrong " .. table.concat(wrong, ","))
check("rewards: a single choice is still shown", #lost == 0, table.concat(lost, ","))
check("rewards: Making Repairs", rewardText(91316):find("^Rewards / You will receive: / %[tile: Salvaged Wooden Tower Shield") ~= nil, rewardText(91316))
check("rewards: several stay a choice", rewardText(855):find("choose one of these", 1, true) ~= nil)

-- The level line, whole: "Level 27 requires level 22", one level when they
-- are the same, and what is known when only one is.
local function factsLine(q)
	return ns.Unlink(lineText(ns.Details("quest", q)[1] or ""))
end
check("levels: level and required", factsLine(6571) == "Level 27 requires level 22", factsLine(6571))
check("levels: the same, once", factsLine(16) == "Level 1, repeatable", factsLine(16))
check("levels: only its own", factsLine(84319):find("^Level 58") ~= nil and not factsLine(84319):find("requires"), factsLine(84319))
check("levels: only the required one", factsLine(8856):find("^Requires level 60") ~= nil, factsLine(8856))
check("levels: none of its own (-1) is not said", factsLine(1472):find("^Requires level 20") ~= nil and not factsLine(1472):find("%-1"), factsLine(1472))
check("levels: neither, no level line", not factsLine(8152):lower():find("level"), factsLine(8152))
check("levels: then the rest", factsLine(98910) == "Level 39 requires level 30, up to level 39", factsLine(98910))

-- The result list: a quest's level, none for one without its own (-1).
local function questRow(id) return ns.Subtitle({ kind = "quest", id = id, ids = { id } }) end
check("result list: a quest's level", questRow(6571) == "Quest · level 27", questRow(6571))
local noLevel, shown = 0, {}
for id in pairs(data.quests) do
	local level = ForeverData.Quest(id).level
	if level and level <= 0 then
		noLevel = noLevel + 1
		if questRow(id):find("level", 1, true) then shown[#shown + 1] = id .. " " .. questRow(id) end
	end
end
check("result list: no level -1", noLevel > 0 and #shown == 0, noLevel .. " quests, shown: " .. table.concat(shown, "; "))

-- The quest lists on the pages of who gives and takes a quest: its level at
-- the right, nothing there for one without its own (-1).
local entries, minus = 0, {}
for id in pairs(data.quests) do
	local q = ForeverData.Quest(id)
	if q.level and q.level <= 0 then
		for _, refs in ipairs({ q.starts, q.ends }) do
			for _, ref in ipairs(refs) do
				if ref.kind == "npc" or ref.kind == "object" then
					for _, line in ipairs(ns.Details(ref.kind, ref.id, "side:both")) do
						if type(line) == "table" and line[1] and line[1]:find("|Hfsearch:quest:" .. id .. "|h", 1, true) then
							entries = entries + 1
							if line[2] ~= "" then minus[#minus + 1] = id .. " on " .. ref.kind .. ref.id .. ": " .. line[2] end
						end
					end
				end
			end
		end
	end
end
check("quest lists: no level -1", entries > 0 and #minus == 0, entries .. " entries; " .. table.concat(minus, "; "))
local locke
for _, line in ipairs(ns.Details("npc", ForeverData.Quest(6571).starts[1].id, "side:both")) do
	if type(line) == "table" and line[1] and line[1]:find("|Hfsearch:quest:6571|h", 1, true) then locke = line[2] end
end
check("quest lists: a quest's level at the right", locke == "27", locke)

-- Quests that require more than their own level: a level-1 repeatable
-- turn-in says only what it requires, on its page and in the lists; the
-- others (priests' 4 and 5, warlocks' 58 and 60) keep both.
local turnIns, both, bad = 0, 0, {}
for id in pairs(data.quests) do
	local q = ForeverData.Quest(id)
	if q.level and q.level > 0 and q.requiredLevel and q.requiredLevel > q.level then
		local line, row = factsLine(id), questRow(id)
		if q.level == 1 then
			turnIns = turnIns + 1
			if not line:find("^Requires level " .. q.requiredLevel) or row:find("level", 1, true) then bad[#bad + 1] = id .. ": " .. line .. " / " .. row end
		else
			both = both + 1
			if not line:find(("^Level %d requires level %d"):format(q.level, q.requiredLevel)) or not row:find("level " .. q.level, 1, true) then
				bad[#bad + 1] = id .. ": " .. line .. " / " .. row
			end
		end
	end
end
check("levels: 15 turn-ins only require, 15 others say both", turnIns == 15 and both == 15 and #bad == 0, turnIns .. ", " .. both .. "; " .. table.concat(bad, "; "))
check("levels: Rocknot's Ale", factsLine(4295):find("^Requires level 42") ~= nil, factsLine(4295))
local ale
for _, ref in ipairs(ForeverData.Quest(4295).starts) do
	for _, line in ipairs(ns.Details(ref.kind, ref.id, "side:both")) do
		if type(line) == "table" and line[1] and line[1]:find("|Hfsearch:quest:4295|h", 1, true) then ale = line[2] end
	end
end
check("levels: no 1 beside it in a page's quest list", ale == "", ale)
-- A level-1 quest that asks no more keeps its level: Give Gerard a Drink,
-- repeatable, requires 1.
check("levels: an ordinary level 1 is said", questRow(16):find("level 1", 1, true) ~= nil, questRow(16))

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("ok")
