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
check("money", ns.Money(1234567) == "123g 45s 67c" and ns.Money(150) == "1s 50c" and ns.Money(7) == "7c")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("ok")
