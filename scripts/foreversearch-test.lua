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

local ns = {}
assert(loadfile("addons/ForeverSearch/Core.lua"))("ForeverSearch", ns)
check("ready", ns.Ready())

local function has(lines, needle)
	for _, line in ipairs(lines) do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

local found = ns.Results("turtle scale")
check("results", #found > 0 and found[1].kind == "item" and found[1].id == 8167 and found[1].quality == 1, found[1] and found[1].name)

local lines = ns.Details("item", 8167)
check("item: drops have their own heading", has(lines, "Drops from (") and has(lines, "Skinned from ("), table.concat(lines, "\n"))
check("item: a counted drop", has(lines, "Stolid Snapjaw: 14.973% of 187"), table.concat(lines, "\n"))
check("item: auction price", has(lines, "Auction:|r 1s 50c"))
check("item: owned", has(lines, "You own:|r 15 (Gorack 12, Pietjan 3)"))
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
check("npc: where", has(lines, "Where:|r The Hinterlands ("), table.concat(lines, "\n"))
check("npc: gives, by way of getting", has(lines, "Drops (") and has(lines, "Skinning (") and has(lines, "Turtle Scale: "))

lines = ns.Details("npc", 54)
check("a vendor: by side", has(lines, "<Weaponsmith>") and has(lines, "friendly to Alliance, hostile to Horde"), lines[1])

lines = ns.Details("object", 1731)
check("object: where and contains", has(lines, "Where:") and has(lines, "Contains (") and has(lines, "Copper Ore: "), table.concat(lines, "\n"))

-- An item sold for Merchant's Favor.
lines = ns.Details("item", 264201)
check("sold for Merchant's Favor", has(lines, "45 Merchant's Favor"), table.concat(lines, "\n"))

local veins = ns.Results("copper vein")
check("one row a kind and name", veins[1] and veins[1].name == "Copper Vein" and #veins[1].ids >= 2 and (veins[2] == nil or veins[2].name ~= "Copper Vein"),
	veins[1] and #veins[1].ids)
check("subtitle of a creature", ns.Subtitle(ns.Results("saltwater snapjaw")[1]) == "Creature · level 49-50 · The Hinterlands", ns.Subtitle(ns.Results("saltwater snapjaw")[1]))
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
check("money", ns.Money(1234567) == "123g 45s 67c" and ns.Money(150) == "1s 50c" and ns.Money(7) == "7c")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("ok")
