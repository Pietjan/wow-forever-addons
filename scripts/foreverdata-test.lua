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
		npcs = { [2505] = "Saltwater Snapjaw||49|50|0|nn", [54] = "Corina Steele|Weaponsmith|10|10|0|fh", [1] = "No Faction|||||--" },
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
check("npc", n.name == "Corina Steele" and n.title == "Weaponsmith" and n.alliance == "friendly" and n.horde == "hostile" and n.rank == 0)
check("neutral npc", FD.Npc(2505).alliance == "neutral" and FD.Npc(2505).horde == "neutral" and FD.Npc(2505).title == nil)
check("npc without a faction", FD.Npc(1).alliance == nil and FD.Npc(1).horde == nil)
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
check("search: inside a word only from 3 letters", #FD.Search("ne") == 0 and #FD.Search("ine") > 0)
hits = FD.Search("", 3, nil, { filter = function() return true end })
check("search limit", #hits == 3)
check("search prefix first", FD.Search("s")[1].name:sub(1, 1):lower() == "s")
check("search: a typo", FD.Search("tutrle")[1] and FD.Search("tutrle")[1].name == "Turtle Scale")
check("search: letters in order", FD.Search("trtl scl")[1] and FD.Search("trtl scl")[1].name == "Turtle Scale")
check("search: every word must match", #FD.Search("turtle cloth") == 0 and #FD.Search("lnen clth") == 1)
check("search: a word start beats the inside", (function()
	local r = FD.Search("scal")
	return r[1] and r[1].name == "Turtle Scale"
end)())
check("search: a prefix beats a word start", FD.Search("salt")[1].name == "Saltwater Snapjaw" and FD.Search("snap")[1].name == "Saltwater Snapjaw")
local function ids(rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = r.kind .. r.id end
	table.sort(out)
	return table.concat(out, " ")
end
check("filter: quality keeps items of at least it", ids(FD.Search("", nil, nil, { quality = 1 })) == "item2589 item8167", ids(FD.Search("", nil, nil, { quality = 1 })))
check("filter: quality leaves other kinds out", ids(FD.Search("saltwater", nil, nil, { quality = 0 })) == "")
check("filter: level, items by required level (none is 0)", ids(FD.Search("", nil, { "item" }, { level = { 0, 0 } })) == "item2589 item288824 item8167")
check("filter: level, creatures by range", ids(FD.Search("", nil, nil, { level = { 50, 55 } })) == "npc2505", ids(FD.Search("", nil, nil, { level = { 50, 55 } })))
check("filter: level, quests by level", ids(FD.Search("", nil, { "quest" }, { level = { 1, 1 } })) == "quest92479")
check("filter: zone keeps what stands there and what it gives", ids(FD.Search("", nil, nil, { zone = 47 })) == "item8167 npc2505"
	and ids(FD.Search("", nil, nil, { zone = 12 })) == "", ids(FD.Search("", nil, nil, { zone = 47 })))
check("filter: a function", ids(FD.Search("", nil, nil, { filter = function(kind) return kind == "zone" end })) == "zone2257 zone47",
	ids(FD.Search("", nil, nil, { filter = function(kind) return kind == "zone" end })))
check("filter: no text and no filter finds nothing", #FD.Search("") == 0)
FD = fixture()
check("distinct: one row a kind and name", (function()
	local ns2 = { meta = { contract = 1 }, objects = { [1] = "Fire|8", [2] = "Fire|8", [3] = "Fire|8", [4] = "Torch|8" } }
	ForeverData = nil
	load({ "Core.lua" }, ns2)
	local r = ForeverData.Search("", 2, nil, { distinct = true, filter = function() return true end })
	local ok = #r == 2 and r[1].name == "Fire" and #r[1].ids == 3 and r[2].name == "Torch"
	ForeverData = FD
	return ok
end)())
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
	check("real portrait model", FD.Npc(2505).display == 5027 and FD.Npc(11520).display == 7970, FD.Npc(2505).display)
	-- In steps, as ForeverSearch runs it: the same answer, in many steps.
	local steps = 0
	local co = coroutine.create(function() return FD.Search("tutrle scale", 20, nil, { yieldEvery = 3000 }) end)
	local ok, stepped
	repeat
		ok, stepped = coroutine.resume(co)
		steps = steps + 1
	until coroutine.status(co) == "dead"
	local whole = FD.Search("tutrle scale", 20)
	local same = ok and #stepped == #whole
	for i = 1, #whole do
		same = same and stepped[i].id == whole[i].id and stepped[i].kind == whole[i].kind
	end
	check("real search in steps", same and steps > 10, steps)

	-- Quests: who starts and ends them, what they ask, what they give.
	local q = FD.Quest(7)
	check("quest: side", q.side == "alliance", q.side)
	check("quest: starts and ends at Marshal McBride", q.starts[1].kind == "npc" and q.starts[1].id == 197 and q.ends[1].id == 197)
	check("quest: kill Kobold Vermin", q.objectives[1].kind == "npc" and q.objectives[1].id == 6)
	check("quest: reputation with Stormwind", q.reputation[1].faction == 72 and q.reputation[1].value == 100 and FD.Faction(72) == "Stormwind")
	check("quest: chain", q.requiresOne[1] == 783 and q.next == 15)
	check("quest: text", q.text and q.text:find("Kobold Vermin", 1, true) ~= nil, q.text)
	check("quest: started by an item", FD.Quest(2).starts[1].kind == "item" and FD.Quest(2).starts[1].id == 16305)
	check("quest: Horde", FD.Quest(2).side == "horde")
	local roles = {}
	for _, r in ipairs(FD.QuestsOf("npc", 197)) do roles[r.role .. r.quest] = true end
	check("quests of Marshal McBride", roles.start7 and roles.end7)
	roles = {}
	for _, r in ipairs(FD.QuestsOf("item", 16305)) do roles[r.role .. r.quest] = true end
	check("quests of Sharptalon's Claw", roles.start2)
	check("class names", FD.ClassName(1) == "Warrior" and FD.ClassName(11) == "Druid")
	check("profession names", FD.SkillName(164) == "Blacksmithing")
	local sells = {}
	for _, id in ipairs(FD.Sells(54)) do sells[id] = true end
	check("a vendor sells", next(sells) ~= nil)
	local subs = {}
	for _, z in ipairs(FD.Subzones(12)) do subs[z] = true end
	check("Elwynn's subzones: Northshire Valley, Northshire Abbey under it", subs[12] and subs[9] and subs[24])
	check("has loot", FD.HasLoot("npc", 2505) and not FD.HasLoot("npc", 197))
	local inElwynn = {}
	for _, r in ipairs(FD.Search("", 500, { "quest" }, { zone = { 12 } })) do inElwynn[r.id] = true end
	check("quests in a zone, its subzones' too", inElwynn[7] and inElwynn[5805], inElwynn[7])
end

check("instances: a dungeon, a zone; no raid, none open yet", FD.Zone(2677) == nil and FD.Zone(1581).instance == "dungeon"
	and FD.Zone(12).instance == nil)
do
	-- World drops: an item given everywhere, rarely, is no zone's loot.
	local data = {}
	for _, f in ipairs({ "Meta", "Items", "Npcs", "Objects", "Quests", "Zones", "Loot", "Spawns", "Vendors", "Trainers", "Unsearched", "Levels" }) do
		assert(loadfile("addons/ForeverData/Data/" .. f .. ".lua"))("ForeverData", data)
	end
	assert(loadfile("addons/ForeverData/Core.lua"))("ForeverData", data)
	local real = ForeverData
	local function inZone(name, zone)
		for _, r in ipairs(real.Search(name, 20, { "item" }, { zone = zone })) do
			if r.name == name then return true end
		end
		return false
	end
	check("widespread: Fiery War Axe is", real.Item(870).widespread == true and real.Item(16305).widespread ~= true)
	check("world drop: not Scarlet Monastery's loot", not inZone("Fiery War Axe", 796))
	check("world drop: its own set still is", inZone("Scarlet Chestpiece", 796))
	check("world drop: Silk Cloth, common there, still is", inZone("Silk Cloth", 796))
	check("world drop: a boss drop still is", inZone("Ravager", 796))
end
-- The search lists built ahead, and placeholder names left out as the
-- generator marked them.
-- (Searches above built them already: here it only has to say so.)
local slices = 0
repeat
	slices = slices + 1
until ForeverData.PrepareSearch(0.002, os.clock) or slices > 10000
check("search prepared", ForeverData.PrepareSearch(0.002, os.clock) == true, slices)
check("placeholders not found", (function()
	for _, q in ipairs({ "UNUSED", "doodad", "PH" }) do
		for _, r in ipairs(ForeverData.Search(q, 30)) do
			if r.name:find("UNUSED") or r.name:find("^[Dd]oodad") or r.name:find("^%[") then return false end
		end
	end
	return true
end)())

-- Misspelled: names with a word one typo off, through the word index;
-- letters in order (Leatherworking for "leathr") only when there are none.
local function names(q, n)
	local out = {}
	for i, r in ipairs(ForeverData.Search(q, n or 30)) do out[i] = r.name end
	return out
end
local function has(list, name)
	for _, n in ipairs(list) do if n == name then return true end end
	return false
end
check("typo: rough arow is Rough Arrow", names("rough arow")[1] == "Rough Arrow", table.concat(names("rough arow", 3), "; "))
check("typo: linnen finds Linen Cloth", has(names("linnen", 3), "Linen Cloth"), table.concat(names("linnen", 3), "; "))
check("typo: no letters-in-order hits beside typo hits", has(names("leathr"), "Thick Leather") and not has(names("leathr"), "Leatherworking"))
check("letters in order when nothing else: trtl", #ForeverData.Search("trtl", 5) > 0)

-- Zone levels come with the data (Data/Levels.lua), worked out by the
-- generator as ForeverSearch did in game: The Deadmines 18-20.
local low, high, shipped = ForeverData.ZoneLevels(1581)
check("zone levels shipped", shipped == true and low == 18 and high == 20, tostring(low) .. "-" .. tostring(high))

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("ok")
