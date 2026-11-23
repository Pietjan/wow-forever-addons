-- Offline checks for ForeverData: loads the addon's files as the game
-- does (each chunk gets the addon's name and namespace), then calls its API.
--   lua5.1 scripts/foreverdata-test.lua            fixture data only
--   lua5.1 scripts/foreverdata-test.lua real       the generated Data/ too
local dir = "addons/ForeverData/"
local failures = 0

local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

local function load(files, ns)
	for _, file in ipairs(files) do
		local chunk = assert(loadfile(dir .. file))
		chunk("ForeverData", ns)
	end
end

-- Fixture: the formats as `forever addon` writes them.
local function fixture()
	ForeverData = nil
	local ns = {
		meta = { contract = 1, sources = { client = "1.60.1.71037" } },
		items = { [8167] = "Turtle Scale|1|7|6|39|0|1", [288824] = "Arcanist Leggings|||||||0", [2589] = "Linen Cloth|1|7|5|5|0|1" },
		npcs = { [2505] = "Saltwater Snapjaw||49|50|0|", [54] = "Corina Steele|Weaponsmith|10|10|0|A" },
		objects = { [1731] = "Copper Vein|3" },
		quests = { [17] = "|42|||0", [92479] = "A Scribbled Letter|1|1|1" },
		zones = { [47] = "The Hinterlands|", [2257] = "Deeprun Tram|" },
		loot = {
			n = { [2505] = "8167,k,50.5,4822,f;8167,d,0.679,6189,f;2589,d,,,v" },
			o = { [1731] = "2770,c,100,,c" },
		},
		drops = { [8167] = "n2505", [2770] = "o1731" },
		spawns = { n = { [2505] = "47:kokm;2257:" } },
		vendors = { [4355] = "2399,1650,,1,6;256733,45,3402,," },
		trainers = { [2385] = "2399,197,10,,50" },
	}
	load({ "Core.lua" }, ns)
	return ForeverData
end

local FD = fixture()
check("contract", FD.RequireContract(1) and not FD.RequireContract(2))
local it = FD.Item(8167)
check("item", it and it.name == "Turtle Scale" and it.quality == 1 and it.itemLevel == 39 and it.available)
check("item not available", FD.Item(288824).available == false and FD.Item(288824).quality == nil)
check("item cached", FD.Item(8167) == it)
check("unknown item", FD.Item(1) == nil)
local n = FD.Npc(54)
check("npc", n.name == "Corina Steele" and n.title == "Weaponsmith" and n.reacts == "A" and n.rank == 0)
check("hostile npc", FD.Npc(2505).reacts == nil and FD.Npc(2505).title == nil)
check("quest without a name", FD.Quest(17).name == nil and FD.Quest(17).level == 42 and FD.Quest(17).new == false)
check("new quest", FD.Quest(92479).new)
local loot = FD.Loot("npc", 2505)
check("loot rows", #loot == 3 and loot[1].method == "skinning" and loot[1].chance == 50.5 and loot[1].sample == 4822 and loot[1].basis == "forever")
check("loot seen, no chance", loot[3].chance == nil and loot[3].basis == "seen" and loot[3].item == 2589)
check("no loot", #FD.Loot("npc", 54) == 0 and #FD.Loot("nope", 1) == 0)
local drops = FD.Drops(8167)
check("drops", #drops == 2 and drops[1].kind == "npc" and drops[1].id == 2505 and drops[2].chance == 0.679)
check("drops from an object", FD.Drops(2770)[1].kind == "object" and FD.Drops(2770)[1].basis == "classic")
local sp = FD.Spawns("npc", 2505)
check("spawns", #sp == 2 and sp[1].zone == 47 and sp[1].x == 74.4 and sp[1].y == 74.2, sp[1] and (sp[1].x .. "," .. sp[1].y))
check("spawn without a map", sp[2].zone == 2257 and sp[2].x == nil)
local v = FD.Vendors(4355)
check("vendors", #v == 2 and v[1].price == 1650 and v[1].stock == 1 and v[1].standing == 6 and v[1].currency == nil)
check("vendor in a currency", v[2].currency == 3402 and v[2].price == 45 and v[2].stock == nil)
check("trainers", FD.Trainers(2385)[1].skill == 10 and FD.Trainers(2385)[1].level == nil and FD.Trainers(2385)[1].cost == 50)
local hits = FD.Search("scale")
check("search", #hits == 1 and hits[1].kind == "item" and hits[1].id == 8167)
hits = FD.Search("LINEN")
check("search any case", #hits == 1 and hits[1].name == "Linen Cloth")
hits = FD.Search("e", 3)
check("search limit", #hits == 3)
check("search prefix first", FD.Search("s")[1].name:sub(1, 1):lower() == "s")
check("search by kind", #FD.Search("copper", nil, { "npc" }) == 0 and #FD.Search("copper", nil, { "object" }) == 1)

if arg[1] == "real" then
	ForeverData = nil
	local ns = {}
	collectgarbage("collect")
	local before, start = collectgarbage("count"), os.clock()
	load({ "Data/Meta.lua", "Data/Items.lua", "Data/Npcs.lua", "Data/Objects.lua", "Data/Quests.lua", "Data/Zones.lua",
		"Data/Loot.lua", "Data/Spawns.lua", "Data/Vendors.lua", "Data/Trainers.lua", "Core.lua" }, ns)
	collectgarbage("collect")
	print(string.format("real data: loaded in %.2f s, %.1f MB in memory", os.clock() - start, (collectgarbage("count") - before) / 1024))
	FD = ForeverData
	check("real contract", FD.RequireContract(1))
	check("real Turtle Scale", FD.Item(8167).name == "Turtle Scale")
	local best
	for _, d in ipairs(FD.Drops(8167)) do
		if d.kind == "npc" and d.id == 2505 and d.method == "drop" then best = d end
	end
	check("real Snapjaw drop", best and best.chance == 0.679 and best.sample == 6189 and best.basis == "forever", best and best.chance)
	start = os.clock()
	local found = FD.Search("copper")
	print(string.format("first search: %.2f s, %d hits, first %s %s", os.clock() - start, #found, found[1] and found[1].kind, found[1] and found[1].name))
	start = os.clock()
	FD.Search("turtle")
	print(string.format("next search: %.3f s", os.clock() - start))
	check("real spawns", #FD.Spawns("npc", 2505) > 10)
end

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("ok")
