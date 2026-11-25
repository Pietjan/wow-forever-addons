-- ForeverSearch, the data side: what a search finds and what to say about
-- each find, from ForeverData, Auctionator and Syndicator. No frames here
-- (Window.lua draws), so this file runs outside the game too.
local ADDON, ns = ...

local FD -- ForeverData, once it has passed its contract check

ns.KIND_LABEL = { item = "Item", npc = "Creature", object = "Object", quest = "Quest", zone = "Zone" }
local INSTANCE_LABEL = { dungeon = "Dungeon", raid = "Raid", battleground = "Battleground" }

-- KindLabel names what a find is: "Creature", or for a zone "Dungeon" or
-- "Raid" where it is one.
function ns.KindLabel(kind, id)
	if kind == "zone" and FD then
		local z = FD.Zone(id)
		if z and INSTANCE_LABEL[z.instance] then
			return INSTANCE_LABEL[z.instance]
		end
	end
	return ns.KIND_LABEL[kind] or kind
end
local RANK_LABEL = { [1] = "Elite", [2] = "Rare elite", [3] = "Boss", [4] = "Rare" }
local RANK_WORD = { [1] = "elite", [2] = "rare", [3] = "boss", [4] = "rare" }
local STANDING_LABEL = { [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }
local CURRENCY_LABEL = { [3402] = "Merchant's Favor" }
local GREY, GOLD, RED = "|cff9d9d9d", "|cffffd100", "|cffff6040"

-- Frame budget ---------------------------------------------------------------
--
-- Work the window does for a keystroke or a hover runs in a coroutine, a
-- slice a frame (Window.lua). Long loops here call Pause: when the slice's
-- time is used up it gives the frame back (yields), else it returns at
-- once. Outside such a job it does nothing, so the same code runs whole
-- when called plainly (the tests, a tooltip).
local sliceEnd -- debugprofilestop() when the running slice must stop
function ns.SliceUntil(ms)
	sliceEnd = ms
end
function ns.Pause()
	if sliceEnd and debugprofilestop and debugprofilestop() >= sliceEnd and coroutine.running() then
		coroutine.yield()
	end
end
local Pause = ns.Pause

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

-- Currency is so many of a currency (3402 Merchant's Favor) with the
-- game's icon for it, else its name.
function ns.Currency(amount, id)
	local get = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
	local ok, info = false, nil
	if get then
		ok, info = pcall(get, id)
	end
	local icon = ok and type(info) == "table" and info.iconFileID
	if icon then
		return ("%d |T%s:0|t"):format(amount, tostring(icon))
	end
	local name = ok and type(info) == "table" and info.name or CURRENCY_LABEL[id] or ("currency " .. id)
	return ("%d %s"):format(amount, name)
end

-- Money is an amount of copper as the game writes it: with its gold,
-- silver and copper coin icons (GetCoinTextureString), else in letters,
-- "12g 34s 56c".
function ns.Money(copper)
	copper = math.floor(math.abs(copper) + 0.5)
	local coins = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
	if coins then
		local ok, text = pcall(coins, copper)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then
		return ("%dg %02ds %02dc"):format(g, s, c)
	elseif s > 0 then
		return ("%ds %02dc"):format(s, c)
	end
	return ("%dc"):format(c)
end

-- Percent as a whole number; under half a percent "<1%", so a rare drop
-- does not read as never.
local function Percent(chance)
	if chance < 0.5 then
		return "<1%"
	end
	return ("%d%%"):format(math.floor(chance + 0.5))
end

-- A chance for the right-hand column: the percent, or "seen" when the
-- thing is known to come from there without a figure.
local function Chance(row)
	if not row.chance then
		return GREY .. "seen|r"
	end
	return Percent(row.chance)
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

-- Link wraps a thing's name as a link the preview follows:
-- |Hfsearch:npc:2505|h...|h, coloured by item quality or as a place.
local QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
function ns.Link(kind, id)
	local name = ns.NameOf(kind, id)
	local colour = "66bbff"
	if kind == "item" then
		local it = FD and FD.Item(id)
		colour = QUALITY_HEX[it and it.quality or 1] or "ffffff"
	end
	return ("|Hfsearch:%s:%d|h|cff%s%s|r|h"):format(kind, id, colour, name)
end

-- FindLink is a link that puts a search in the bar: the words of query,
-- commas for its spaces in the link (|Hfsearch:find:npc:,in:the-hinterlands|h).
function ns.FindLink(query, label)
	return ("|Hfsearch:find:%s|h|cff66bbff%s|r|h"):format(string.gsub(query, " ", ","), label)
end

-- More is the line under a cut-off list: "and 7 more", searching for the
-- rest, with the words it searches for beside it.
local function More(n, query)
	return "  " .. ns.FindLink(query, ("and %d more"):format(n)) .. GREY .. ": " .. query .. "|r"
end

-- Zone is the in: word of a zone by its ID.
local function Zone(id)
	return ns.InWord(ns.NameOf("zone", id))
end

-- Unlink takes the links, colours and icons out of a line, leaving plain text.
function ns.Unlink(line)
	line = string.gsub(string.gsub(line, "%s?|A.-|a", ""), "%s?|T.-|t", "")
	line = string.gsub(string.gsub(line, "|H.-|h", ""), "|h", "")
	return (string.gsub(string.gsub(line, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
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

-- Distances ---------------------------------------------------------------------
--
-- A spawn's x and y are of its zone's game map (FD.Zone(id).map); the
-- game's map calls turn that, and where the player stands, into a
-- continent and a world position, so a distance is the game's own yards.
-- Anything the game does not give (a secret, an instance, no map) is no
-- distance, never a guess.

-- PlayerWorld is the player's continent and world position, nil unknown.
local function PlayerWorld()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then
		return nil
	end
	local ok, continent, world = pcall(function()
		local map = C_Map.GetBestMapForUnit("player")
		local pos = map and C_Map.GetPlayerMapPosition(map, "player")
		if not pos then
			return nil
		end
		local c, w = C_Map.GetWorldPosFromMapPos(map, pos)
		return c, w and { x = w.x + 0, y = w.y + 0 } -- + 0 fails on a secret
	end)
	if ok and continent and world then
		return continent, world
	end
	return nil
end

-- A map's x and y turn into world positions linearly, so the game is asked
-- for three points of each map once (its corners at 0,0, 1,0 and 0,1) and
-- the rest is arithmetic: a page measures thousands of spots (Linen Cloth's
-- sources stand at 14,090). false: the game gives no position for the map.
local mapToWorld = {}
local function MapToWorld(map)
	local t = mapToWorld[map]
	if t == nil then
		t = false
		local ok, c, o, ex, ey = pcall(function()
			local c0, o0 = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0, 0))
			local _, px = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(1, 0))
			local _, py = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0, 1))
			return c0, { x = o0.x + 0, y = o0.y + 0 }, { x = px.x - o0.x, y = px.y - o0.y }, { x = py.x - o0.x, y = py.y - o0.y }
		end)
		if ok and c and o then
			t = { continent = c, o = o, ex = ex, ey = ey }
		end
		mapToWorld[map] = t
	end
	return t
end

-- SpotWorld is a spawn's continent and world position, nil unknown.
local function SpotWorld(spot)
	local z = spot.x and FD.Zone(spot.zone)
	if not (z and z.map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local t = MapToWorld(z.map)
	if not t then
		return nil
	end
	local x, y = spot.x / 100, spot.y / 100
	return t.continent, { x = t.o.x + x * t.ex.x + y * t.ey.x, y = t.o.y + x * t.ex.y + y * t.ey.y }
end

-- Nearest is the spawn of a creature or object nearest the player and how
-- many yards off it is; yards nil when none is on the player's continent or
-- where either stands is unknown (the spot is then its first).
local function Nearest(kind, id, continent, at)
	local best, best2, first
	for n, spot in ipairs(FD.Spawns(kind, id)) do
		if n % 200 == 0 then
			Pause()
		end
		first = first or spot
		local z = continent and spot.x and FD.Zone(spot.zone)
		local t = z and z.map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and MapToWorld(z.map)
		if t and t.continent == continent then
			local x, y = spot.x / 100, spot.y / 100
			local dx = t.o.x + x * t.ex.x + y * t.ey.x - at.x
			local dy = t.o.y + x * t.ex.y + y * t.ey.y - at.y
			local d2 = dx * dx + dy * dy
			if not best2 or d2 < best2 then
				best, best2 = spot, d2
			end
		end
	end
	return best or first, best2 and math.sqrt(best2)
end

-- A place link sets a waypoint there: |Hfsearch:way:<kind>:<id>:<zone>:<x>:<y>|h,
-- x and y in hundredths of a percent of the zone's map.
local function PlaceLink(kind, id, spot, text)
	if not (spot and spot.x and FD.Zone(spot.zone) and FD.Zone(spot.zone).map) then
		return text
	end
	return ("|Hfsearch:way:%s:%d:%d:%d:%d|h%s|h"):format(kind, id, spot.zone,
		math.floor(spot.x * 100 + 0.5), math.floor(spot.y * 100 + 0.5), text)
end

-- Yards says a distance: "240 yd".
local function Yards(yards)
	return ("%d yd"):format(math.floor(yards + 0.5))
end

-- Where says in grey where a creature's or object's spot is and how far,
-- a click setting a waypoint there: " · Durotar 52.2, 41.0, 240 yd".
local function Where(kind, id, spot, yards)
	if not spot then
		return ""
	end
	local text = ns.NameOf("zone", spot.zone)
	if spot.x then
		text = text .. (" %.1f, %.1f"):format(spot.x, spot.y)
	end
	if yards then
		text = text .. ", " .. Yards(yards)
	end
	return GREY .. " · " .. PlaceLink(kind, id, spot, text) .. "|r"
end

-- SetWaypoint points an arrow at a creature's or object's spot: TomTom's
-- (or ForeverGuide's stand-in for it), else the game's own map pin. The
-- last waypoint set from here is taken down first. False when it could
-- not be set.
local lastWaypoint
function ns.SetWaypoint(kind, id, zoneID, x, y)
	local z = FD and FD.Zone(zoneID)
	if not (z and z.map) then
		return false
	end
	local title = ns.NameOf(kind, id)
	if TomTom and TomTom.AddWaypoint then
		if lastWaypoint and TomTom.RemoveWaypoint then
			pcall(TomTom.RemoveWaypoint, TomTom, lastWaypoint)
		end
		local ok, handle = pcall(TomTom.AddWaypoint, TomTom, z.map, x / 100, y / 100, { title = title, from = "ForeverSearch" })
		if ok and handle then
			lastWaypoint = handle
			return true
		end
	end
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local ok = pcall(function()
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(z.map, x / 100, y / 100))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		end)
		return ok
	end
	return false
end

-- Places a creature or object stands: "Durotar (92, nearest 52.1, 40.2,
-- 120 yd), Orgrimmar (3)", the zone with the nearest spot first; a zone it
-- stands in once or twice gets the spots' coordinates instead. Every
-- coordinate is a click to set a waypoint.
local function Places(kind, id)
	local continent, at = PlayerWorld()
	local byZone, order, near = {}, {}, {}
	for n, spot in ipairs(FD.Spawns(kind, id)) do
		if n % 200 == 0 then
			Pause()
		end
		if not byZone[spot.zone] then
			byZone[spot.zone] = {}
			order[#order + 1] = spot.zone
		end
		table.insert(byZone[spot.zone], spot)
		if continent then
			local c, w = SpotWorld(spot)
			if c == continent then
				local d = math.sqrt((w.x - at.x) ^ 2 + (w.y - at.y) ^ 2)
				if not near[spot.zone] or d < near[spot.zone].yards then
					near[spot.zone] = { spot = spot, yards = d }
				end
			end
		end
	end
	table.sort(order, function(a, b)
		if (near[a] ~= nil) ~= (near[b] ~= nil) then
			return near[a] ~= nil
		end
		if near[a] and near[a].yards ~= near[b].yards then
			return near[a].yards < near[b].yards
		end
		return #byZone[a] > #byZone[b]
	end)
	local parts = {}
	for _, zone in ipairs(order) do
		local spots = byZone[zone]
		if #spots <= 2 and spots[1].x then
			local xy = {}
			for _, spot in ipairs(spots) do
				local text = ("%.1f, %.1f"):format(spot.x, spot.y)
				if near[zone] and near[zone].spot == spot then
					text = text .. ", " .. Yards(near[zone].yards)
				end
				xy[#xy + 1] = PlaceLink(kind, id, spot, text)
			end
			parts[#parts + 1] = ns.Link("zone", zone) .. " " .. GREY .. table.concat(xy, "; ") .. "|r"
		elseif near[zone] then
			local n = near[zone]
			parts[#parts + 1] = ("%s (%d, %s)"):format(ns.Link("zone", zone), #spots, GREY .. PlaceLink(kind, id, n.spot,
				("nearest %.1f, %.1f, %s"):format(n.spot.x, n.spot.y, Yards(n.yards))) .. "|r")
		else
			parts[#parts + 1] = ("%s (%d)"):format(ns.Link("zone", zone), #spots)
		end
	end
	return table.concat(parts, ", ")
end

-- Spot says in a few grey words where to find a quest's giver or target:
-- its nearest spot and how far when that is known (" · Durotar 52.2, 41.0,
-- 240 yd"), else " · Ashenvale 73.2, 61.5" for one spot, " · Ashenvale" for
-- many. A spot is a click to set a waypoint.
local function Spot(kind, id)
	local continent, at = PlayerWorld()
	local spot, yards = Nearest(kind, id, continent, at)
	if yards then
		return Where(kind, id, spot, yards)
	end
	local counts, best = {}, nil
	local spawns = FD.Spawns(kind, id)
	for _, s in ipairs(spawns) do
		counts[s.zone] = (counts[s.zone] or 0) + 1
		if not best or counts[s.zone] > counts[best] then
			best = s.zone
		end
	end
	if not best then
		return ""
	end
	if counts[best] == 1 then
		for _, s in ipairs(spawns) do
			if s.zone == best and s.x then
				return Where(kind, id, s)
			end
		end
	end
	return GREY .. " · " .. ns.NameOf("zone", best) .. "|r"
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

-- Abbreviations players use for places. Not game data: the game has no
-- short names, so this is a list of the usual ones. One may stand for
-- two places (dm: The Deadmines and Dire Maul).
local ABBREVIATIONS = {
	rfc = { "Ragefire Chasm" }, wc = { "Wailing Caverns" }, dm = { "The Deadmines", "Dire Maul" },
	vc = { "The Deadmines" }, sfk = { "Shadowfang Keep" }, bfd = { "Blackfathom Deeps" },
	stocks = { "The Stockade" }, gnomer = { "Gnomeregan" }, rfk = { "Razorfen Kraul" },
	sm = { "Scarlet Monastery" }, rfd = { "Razorfen Downs" }, ulda = { "Uldaman" }, uld = { "Uldaman" },
	zf = { "Zul'Farrak" }, mara = { "Maraudon" }, st = { "The Temple of Atal'Hakkar" },
	["sunken-temple"] = { "The Temple of Atal'Hakkar" }, brd = { "Blackrock Depths" },
	brs = { "Blackrock Spire" }, lbrs = { "Blackrock Spire" }, ubrs = { "Blackrock Spire" },
	strat = { "Stratholme" }, scholo = { "Scholomance" },
	mc = { "Molten Core" }, ony = { "Onyxia's Lair" }, bwl = { "Blackwing Lair" }, zg = { "Zul'Gurub" },
	aq20 = { "Ruins of Ahn'Qiraj" }, aq40 = { "Ahn'Qiraj" }, naxx = { "Naxxramas" },
	av = { "Alterac Valley" }, wsg = { "Warsong Gulch" }, ab = { "Arathi Basin" },
	stv = { "Stranglethorn Vale" }, epl = { "Eastern Plaguelands" }, wpl = { "Western Plaguelands" },
	ungoro = { "Un'Goro Crater" }, tb = { "Thunder Bluff" }, org = { "Orgrimmar" }, sw = { "Stormwind City" },
	["if"] = { "Ironforge" }, uc = { "Undercity" }, darn = { "Darnassus" }, bb = { "Booty Bay" },
	xroads = { "The Crossroads" },
}

-- Abbreviated gives the zones an abbreviation stands for ("brd"): their
-- IDs and names; nil when it is none. An abbreviation of a place
-- ForeverData does not ship (a raid, none open yet: "bwl") gives none.
-- Bare is a name as in:/from: words compare it: lower case, without
-- apostrophes, so in:kroldok-stronghold is Krol'dok Stronghold.
local function Bare(name)
	return (string.gsub(string.lower(name), "'", ""))
end

local function Abbreviated(word)
	local names = ABBREVIATIONS[string.lower(word or "")]
	if not names then
		return nil
	end
	local ids, found = {}, {}
	for _, name in ipairs(names) do
		local id = ns.ZoneByName(name)
		if id then
			ids[#ids + 1], found[#found + 1] = id, name
		end
	end
	return ids, found
end

-- Zones a word names: every zone with a word of its name starting with it
-- ("blackrock": Blackrock Depths, Blackrock Spire, ...); failing that, the
-- best fuzzy match ("hinterlnds"). Spots are filed under whole zones, so
-- when the word names only subzones ("goldshire"), their zones count
-- (Elwynn Forest); when it names a whole zone too, only whole zones do.
local function ZonesNamed(word)
	-- An abbreviation (in:bwl) is the zones it stands for.
	local short, shortNames = Abbreviated(word)
	if short then
		local out, names = {}, {}
		for i, id in ipairs(short) do
			local top = TopZone(id)
			out[#out + 1] = top and top.id or id
			names[#names + 1] = shortNames[i]
		end
		return out, names
	end
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
	local lower = Bare(word)
	local matched = {}
	for _, z in ipairs(found) do
		local name = Bare(z.name)
		if string.sub(name, 1, #lower) == lower or string.find(name, "%W" .. lower:gsub("%W", "%%%0")) then
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
	local lower, best = Bare(name), nil
	for _, z in ipairs(FD.Search(name, 50, { "zone" })) do
		if Bare(z.name) == lower then
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
	return "in:" .. string.gsub(Bare(name), "%s+", "-")
end

-- FromWord writes a creature's, object's or vendor's name as one from:
-- word: "from:saltwater-snapjaw".
function ns.FromWord(name)
	return "from:" .. string.gsub(Bare(name), "%s+", "-")
end

-- What the newer filter words find. Each makes a test, function(kind, id),
-- and a label saying how the word was read; a word naming nothing makes a
-- test nothing passes. Looking up a name is cached: the bar's words are
-- read again on every redraw.
local fromCache, typeCache = {}, {}

-- from:<name>: the items creatures or objects of that name give (drops,
-- skinning, containers) and a vendor of that name sells. The exact name
-- wins; failing that, the best match.
local function FromFilter(word)
	if fromCache[word] then
		return fromCache[word]
	end
	local name = string.gsub(word, "%-", " ")
	local hits = FD.Search(name, 50, { "npc", "object" }, { distinct = true, pause = Pause })
	local chosen = {}
	for _, h in ipairs(hits) do
		if Bare(h.name) == Bare(name) then
			chosen[#chosen + 1] = h
		end
	end
	if #chosen == 0 and hits[1] then
		chosen[1] = hits[1]
	end
	local items, names = {}, {}
	for _, h in ipairs(chosen) do
		names[#names + 1] = h.name
		for _, id in ipairs(h.ids) do
			for _, row in ipairs(FD.Loot(h.kind, id)) do
				items[row.item] = true
			end
			if h.kind == "npc" then
				for _, item in ipairs(FD.Sells(id)) do
					items[item] = true
				end
			end
		end
	end
	local f = {
		test = function(kind, id) return kind == "item" and items[id] == true end,
		label = #names > 0 and ("from " .. table.concat(names, ", ")) or "from: no such creature or object",
	}
	fromCache[word] = f
	return f
end

-- type:<word>: items of a type whose name has a word starting with it, as
-- the game names types: type:sword is One-Handed Swords and Two-Handed
-- Swords, type:recipe every recipe.
local function ItemTypes()
	if typeCache.all then
		return typeCache.all
	end
	local all = {}
	local classInfo = C_Item and C_Item.GetItemClassInfo or GetItemClassInfo
	local subInfo = C_Item and C_Item.GetItemSubClassInfo or GetItemSubClassInfo
	if classInfo and subInfo then
		for class = 0, 20 do
			local name = classInfo(class)
			if name and name ~= "" then
				all[#all + 1] = { class = class, name = name }
				for sub = 0, 25 do
					local subName = subInfo(class, sub)
					if subName and subName ~= "" and subName ~= name then
						all[#all + 1] = { class = class, sub = sub, name = subName }
					end
				end
			end
		end
	end
	typeCache.all = all
	return all
end

local function TypeFilter(word)
	if typeCache[word] then
		return typeCache[word]
	end
	local spaced = string.gsub(word, "%-", " ")
	local pattern = "[^%w]" .. string.gsub(spaced, "%W", "%%%0")
	local classes, subs, names, named = {}, {}, {}, {}
	for _, t in ipairs(ItemTypes()) do
		if string.find(" " .. string.lower(t.name), pattern) then
			if t.sub then
				subs[t.class .. ":" .. t.sub] = true
			else
				classes[t.class] = true
			end
			if not named[t.name] then
				named[t.name] = true
				names[#names + 1] = t.name
			end
		end
	end
	local f = {
		test = function(kind, id)
			if kind ~= "item" then
				return false
			end
			local it = FD.Item(id)
			return it ~= nil and it.class ~= nil
				and (classes[it.class] or subs[it.class .. ":" .. tostring(it.subclass)]) == true
		end,
		label = #names > 0 and table.concat(names, ", ") or "type: no such item type",
	}
	typeCache[word] = f
	return f
end

-- is:<word>: creatures of a rank, quests of a kind.
local function Rank(id, ranks)
	local n = FD.Npc(id)
	return n ~= nil and ranks[n.rank or 0] == true
end
local function Instance(id)
	local z = FD.Zone(id)
	return z and z.instance
end
local IS_FILTER = {
	rare = { kinds = { "npc" }, label = "rare creatures", test = function(kind, id) return kind == "npc" and Rank(id, { [2] = true, [4] = true }) end },
	elite = { kinds = { "npc" }, label = "elite creatures", test = function(kind, id) return kind == "npc" and Rank(id, { [1] = true, [2] = true }) end },
	boss = { kinds = { "npc" }, label = "bosses", test = function(kind, id) return kind == "npc" and Rank(id, { [3] = true }) end },
	repeatable = { kinds = { "quest" }, label = "repeatable quests", test = function(kind, id)
		local q = kind == "quest" and FD.Quest(id)
		return q and q.repeatable == true or false
	end },
	dungeon = { kinds = { "zone" }, label = "dungeons", test = function(kind, id) return kind == "zone" and Instance(id) == "dungeon" end },
	raid = { kinds = { "zone" }, label = "raids", test = function(kind, id) return kind == "zone" and Instance(id) == "raid" end },
	battleground = { kinds = { "zone" }, label = "battlegrounds", test = function(kind, id) return kind == "zone" and Instance(id) == "battleground" end },
	new = { kinds = { "quest" }, label = "quests new in Forever", test = function(kind, id)
		local q = kind == "quest" and FD.Quest(id)
		return q and q.new == true or false
	end },
}

-- class:<name>: quests only that class may take. A start of the name does
-- ("class:sham").
-- LimitedRaces is the races a quest is for when that is part of its side
-- (Undead only, Skyborne only), nil when it is any race or a whole side's:
-- a quest for every Classic race of its side is the side's, whether or not
-- its list names the Skyborne (Classic's data never does).
local CLASSIC_RACES = { alliance = { 1, 3, 4, 7 }, horde = { 2, 5, 6, 8 } }
local function LimitedRaces(q)
	if not (q and q.races and #q.races > 0 and FD.Race) then
		return nil
	end
	local has = {}
	for _, r in ipairs(q.races) do
		has[r] = true
	end
	for _, list in pairs(CLASSIC_RACES) do
		local all = true
		for _, r in ipairs(list) do
			all = all and has[r] == true
		end
		if all then
			return nil
		end
	end
	return q.races
end

-- RaceKey is a race's word, for race: and its art: "nightelf", "skyborne"
-- (both Skyborne).
function ns.RaceKey(name)
	if string.find(name, "Skyborne$") then
		return "skyborne"
	end
	return string.lower((string.gsub(name, "[%s']", "")))
end

-- race:<name>: quests only some races may take, that race among them
-- (race:undead, race:skyborne). A quest any race of its side may take is
-- the side's (side:horde).
local function RaceFilter(word)
	word = string.gsub(string.lower(word), "[%s'%-]", "")
	local want, name = {}, nil
	for _, id in ipairs(FD.Races and FD.Races() or {}) do
		local race = FD.Race(id)
		local key = race and ns.RaceKey(race.name)
		if key and string.sub(key, 1, #word) == word then
			want[id] = true
			name = name or (key == "skyborne" and "Skyborne" or race.name)
		end
	end
	if not name then
		return { kinds = { "quest" }, test = function() return false end, label = "race: no such race" }
	end
	return {
		kinds = { "quest" },
		test = function(kind, id)
			local races = kind == "quest" and LimitedRaces(FD.Quest(id))
			for _, r in ipairs(races or {}) do
				if want[r] then
					return true
				end
			end
			return false
		end,
		label = name .. " quests",
	}
end

local function ClassFilter(word)
	for class = 1, 12 do
		local name = FD.ClassName(class)
		if name and string.sub(string.lower(name), 1, #word) == word then
			local bit = 2 ^ (class - 1)
			return {
				test = function(kind, id)
					local q = kind == "quest" and FD.Quest(id)
					return q and q.classes ~= nil and math.floor(q.classes / bit) % 2 == 1 or false
				end,
				label = name .. " quests",
			}
		end
	end
	return { test = function() return false end, label = "class: no such class" }
end

-- skill:<name>: quests that need that profession.
local function SkillFilter(word)
	local line = FD.SkillLine((string.gsub(word, "%-", " ")))
	if not line then
		return { test = function() return false end, label = "skill: no quest needs that" }
	end
	return {
		test = function(kind, id)
			local q = kind == "quest" and FD.Quest(id)
			return q and q.skillLine == line or false
		end,
		label = FD.SkillName(line) .. " quests",
	}
end

local function NewFilter(key, value)
	if key == "from" then
		return FromFilter(value)
	elseif key == "type" then
		return TypeFilter(value)
	elseif key == "is" then
		return IS_FILTER[value] or { test = function() return false end, label = "is: rare, elite, boss, repeatable, new, dungeon, raid or battleground" }
	elseif key == "race" then
		return RaceFilter(value)
	elseif key == "class" then
		return ClassFilter(value)
	end
	return SkillFilter(value)
end
local NEW_KEY = { from = true, type = true, is = true, class = true, skill = true, race = true }

-- side:<word>: whose things to find. Without it, a search leaves out the
-- other side's: its quests, and the people only it is friendly to.
local SIDE_WORD = { alliance = "alliance", a = "alliance", horde = "horde", h = "horde", both = "both", all = "both" }
local SIDE_DESCRIBED = { alliance = "Alliance side", horde = "Horde side", both = "both sides" }

-- MySide is "alliance" or "horde" for the player's faction, nil out of the game.
local function MySide()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return faction == "Alliance" and "alliance" or faction == "Horde" and "horde" or nil
end

-- OtherSides tells whether a thing is the other side's, seen from side:
-- a quest only it may take, a creature friendly to it and not to side.
local function OtherSides(side, kind, id)
	local other = side == "horde" and "alliance" or "horde"
	if kind == "quest" then
		local q = FD.Quest(id)
		return q ~= nil and q.side == other
	elseif kind == "npc" then
		local n = FD.Npc(id)
		return n ~= nil and n[other] == "friendly" and n[side] ~= "friendly"
	end
	return false
end

-- Theirs tells whether a thing belongs to the other faction than the
-- player's (or the side: typed in the bar); pages leave those out. False
-- out of the game and with side:both.
local pageSide -- side: of the bar while a page is written, nil when not typed
local function Theirs(kind, id)
	if pageSide == "both" then
		return false
	end
	local side = pageSide or MySide()
	return side ~= nil and OtherSides(side, kind, id)
end

-- SideFilter wraps a find filter so it also leaves out the other side's
-- quests and people.
local function SideFilter(side, before)
	return function(kind, id)
		if OtherSides(side, kind, id) then
			return false
		end
		return not before or before(kind, id)
	end
end

-- NoPoorFilter keeps grey items out: vendor trash is rarely what a search
-- is after. q:poor (or any q:) lets them back in.
local function NoPoorFilter(before)
	return function(kind, id)
		if kind == "item" then
			local it = FD.Item(id)
			if it and it.quality == 0 then
				return false
			end
		end
		return not before or before(kind, id)
	end
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
	for _, f in ipairs(options.tests or {}) do
		parts[#parts + 1] = f.label
	end
	if options.side then
		parts[#parts + 1] = SIDE_DESCRIBED[options.side]
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
		if (key == "in" or key == "q" or key == "lvl" or key == "side" or NEW_KEY[key]) and value == "" and list[i + 1] then
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
		elseif key == "side" and SIDE_WORD[value] then
			options.side = SIDE_WORD[value]
		elseif NEW_KEY[key] and value ~= "" then
			options.tests = options.tests or {}
			table.insert(options.tests, ns.Ready() and NewFilter(key, value) or { test = function() return false end, label = key .. ":" .. value })
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
	if options.tests then
		local tests = options.tests
		-- A test that only one kind can pass (is:dungeon, zones) keeps the
		-- search to that kind: the other 48,000 names are not looked at.
		-- (The chips still go by the kinds typed.)
		for _, f in ipairs(tests) do
			if f.kinds then
				local keep = {}
				for _, k in ipairs(f.kinds) do
					local typed = not (options.searchKinds or kinds)
					for _, have in ipairs(options.searchKinds or kinds or {}) do
						typed = typed or have == k
					end
					if typed then
						keep[#keep + 1] = k
					end
				end
				options.searchKinds = keep
			end
		end
		options.filter = function(kind, id)
			for _, f in ipairs(tests) do
				if not f.test(kind, id) then
					return false
				end
			end
			return true
		end
	end
	return table.concat(words, " "), kinds, options
end

-- SetFilter rewrites what was typed with one filter set or lifted: which
-- is "kind" (item, npc, ...), "q" (a quality word or number), "lvl"
-- ("40-50") or "in" (an in: word); value nil lifts it. The other words
-- stay as they were; the filter goes in front. A kind word's text stays
-- ("npc:snapjaw" becomes "item: snapjaw").
local FILTER_KEY = { q = "q", lvl = "lvl", ["in"] = "in", is = "is" }
function ns.SetFilter(typed, which, value)
	local list = {}
	for word in string.gmatch(typed or "", "%S+") do
		list[#list + 1] = word
	end
	local kept, i = {}, 1
	while i <= #list do
		local word = list[i]
		local key, rest = string.match(string.lower(word), "^(%a+):(.*)$")
		local drop = false
		if key and which == "kind" and KIND_WORD[key] then
			drop = true
			if rest ~= "" then
				kept[#kept + 1] = string.match(word, ":(.*)$")
			end
		elseif key and FILTER_KEY[which] == key then
			drop = true
			if rest == "" then
				i = i + 1 -- "in: blackrock": its value is the next word
			end
		end
		if not drop then
			kept[#kept + 1] = word
		end
		i = i + 1
	end
	if value ~= nil then
		local token = which == "kind" and (value .. ":") or which == "in" and value or (which .. ":" .. value)
		table.insert(kept, 1, token)
	end
	local text = table.concat(kept, " ")
	if value ~= nil and #kept == 1 then
		text = text .. " "
	end
	return text
end

-- A grouped list: places, bosses (lowest level first), items, quests,
-- creatures, objects. Items keep the search's order (best quality first).
local GROUP_ORDER = { "zone", "boss", "item", "quest", "npc", "object" }
local function GroupFinds(rows)
	local by = {}
	for _, row in ipairs(rows) do
		local group = row.kind
		if row.kind == "npc" then
			local n = FD.Npc(row.id)
			group = n and n.boss and "boss" or "npc"
		end
		by[group] = by[group] or {}
		table.insert(by[group], row)
	end
	if by.boss then
		table.sort(by.boss, function(a, b)
			local la, lb = FD.Npc(a.id).maxLevel or 0, FD.Npc(b.id).maxLevel or 0
			if la ~= lb then
				return la < lb
			end
			return a.name < b.name
		end)
	end
	-- Creatures and objects as a zone's page has them: what gives loot
	-- first (a Rat, a Chair last), creatures highest level first.
	for _, group in ipairs({ "npc", "object" }) do
		if by[group] then
			local loot, level = {}, {}
			for _, row in ipairs(by[group]) do
				loot[row] = FD.HasLoot(row.kind, row.id) and 1 or 0
				local n = row.kind == "npc" and FD.Npc(row.id)
				level[row] = n and n.maxLevel or 0
			end
			table.sort(by[group], function(a, b)
				if loot[a] ~= loot[b] then
					return loot[a] > loot[b]
				end
				if level[a] ~= level[b] then
					return level[a] > level[b]
				end
				return a.name < b.name
			end)
		end
	end
	local out = {}
	for _, group in ipairs(GROUP_ORDER) do
		if by[group] then
			for _, row in ipairs(by[group]) do
				out[#out + 1] = row
			end
		end
	end
	return out
end

-- What a search finds: rows {kind, id, name, quality, available, ids}, one
-- a kind and name: five Copper Vein objects are one row, its id the one
-- most is known of, ids all of them.
-- typed may hold filter words (see Parse); options go to ForeverData.Search
-- along with them (yieldEvery). With options.grouped the rows come in
-- groups (see GroupFinds).
-- Flight masters go by their mount: "flight master" finds them all.
local FLIGHT_WORDS = { ["flight master"] = true, ["flight masters"] = true, ["flightmaster"] = true, ["fp"] = true, ["flight path"] = true, ["flight paths"] = true }
local FLIGHT_TITLES = {
	["Gryphon Master"] = true, ["Wind Rider Master"] = true, ["Hippogryph Master"] = true, ["Bat Handler"] = true,
	["Flight Master"] = true, ["Flight Mistress"] = true, ["Darnassus Flight Master"] = true, ["Thunder Bluff Flight Master"] = true,
}
local function FlightFilter(inner)
	return function(kind, id)
		local n = kind == "npc" and FD.Npc(id)
		return n and FLIGHT_TITLES[n.title or ""] and (not inner or inner(kind, id)) or false
	end
end

-- Road signs are objects named after the place they point to ("Goldshire"):
-- found, they push the place itself down. Left out unless object: is typed.
local zoneNames
local function Signpost(row)
	if row.kind ~= "object" then
		return false
	end
	if not zoneNames then
		zoneNames = {}
		for _, z in ipairs(FD.Search("", 100000, { "zone" }, { filter = function() return true end })) do
			-- The sign says "Stormwind" for Stormwind City, "Crossroads"
			-- for The Crossroads.
			zoneNames[z.name] = true
			zoneNames[(string.gsub(z.name, "^The ", ""))] = true
			zoneNames[(string.gsub(z.name, " City$", ""))] = true
		end
	end
	if not zoneNames[row.name] then
		return false
	end
	for _, id in ipairs(row.ids or { row.id }) do
		if FD.HasLoot("object", id) then
			return false
		end
	end
	return true
end

-- ZoneLevels is the level of what you fight in a zone: the middle 80% of
-- its hostile creatures that give loot (bosses aside), so a dragon or a
-- rare does not stretch it. low, high; nil with fewer than 3 such
-- creatures. Kept once worked out: it searches the zone's creatures.
local zoneLevels = {}
function ns.ZoneLevels(id)
	-- Shipped with the data: no work in game.
	if FD.ZoneLevels then
		local low, high, shipped = FD.ZoneLevels(id)
		if shipped then
			return low, high
		end
	end
	local known = zoneLevels[id]
	if known == nil then
		known = false
		local levels = {}
		for _, row in ipairs(FD.Search("", 1000, { "npc" }, { zone = { id }, distinct = true, pause = Pause })) do
			local n = FD.Npc(row.id)
			if n and not n.boss and n.alliance ~= "friendly" and n.horde ~= "friendly" and n.maxLevel
				and FD.HasLoot("npc", row.id) then
				levels[#levels + 1] = n.maxLevel
			end
		end
		if #levels >= 3 then
			table.sort(levels)
			known = { levels[math.max(1, math.floor(#levels * 0.1 + 0.5))], levels[math.min(#levels, math.ceil(#levels * 0.9))] }
		end
		zoneLevels[id] = known
	end
	if known then
		return known[1], known[2]
	end
	return nil
end

-- RangeText says a level range: "37-45", or "40" when it is one level.
local function RangeText(low, high)
	return low == high and tostring(low) or ("%d-%d"):format(low, high)
end

function ns.Results(typed, limit, options)
	if not ns.Ready() then
		return {}
	end
	local text, kinds, filters = ns.Parse(typed)
	if FLIGHT_WORDS[string.lower((string.gsub(text, "^%s*(.-)%s*$", "%1")))] then
		text, kinds = "", { "npc" }
		filters.filter = FlightFilter(filters.filter)
	end
	local signsWanted = false
	for _, kind in ipairs(kinds or {}) do
		signsWanted = signsWanted or kind == "object"
	end
	-- What was typed wins: an in: typed overrides the instance's zone.
	for k, v in pairs(options or {}) do
		if filters[k] == nil then
			filters[k] = v
		end
	end
	-- The other side's things stay out unless side: says otherwise. Not with
	-- only a kind typed ("item:"): that finds nothing yet, as before.
	local side = filters.side or MySide()
	filters.side = nil
	if side and side ~= "both" and (text ~= "" or filters.filter or filters.zone or filters.level or filters.quality) then
		filters.filter = SideFilter(side, filters.filter)
	end
	if not filters.quality and (text ~= "" or filters.filter or filters.zone or filters.level) then
		filters.filter = NoPoorFilter(filters.filter)
	end
	filters.distinct = true
	filters.pause = Pause
	local out = {}
	local searchKinds = filters.searchKinds
	filters.searchKinds = nil
	if searchKinds and #searchKinds == 0 then
		return {} -- npc: is:dungeon: no kind passes both
	end
	for _, hit in ipairs(FD.Search(text, limit or 30, searchKinds or kinds, filters)) do
		local row = { kind = hit.kind, id = hit.id, name = hit.name, ids = hit.ids }
		if not signsWanted and Signpost(row) then
			row = nil
		end
		-- Several of one name (five Copper Vein objects): the one most is
		-- known of. Weighing decodes an item's every source, so only then.
		if row and #hit.ids > 1 then
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
	-- Typed just an abbreviation ("bwl"): the places it stands for come first.
	local short = Abbreviated((string.gsub(string.lower(text), "^%s*(.-)%s*$", "%1")))
	if short and #short == 0 then
		-- An abbreviation of a place not shipped: nothing, not a near miss
		-- ("bwl" is not The Dustbowl).
		return {}
	end
	local zonesWanted = not kinds
	for _, kind in ipairs(kinds or {}) do
		zonesWanted = zonesWanted or kind == "zone"
	end
	if short and zonesWanted then
		local first = {}
		for _, id in ipairs(short) do
			first[#first + 1] = { kind = "zone", id = id, name = ns.NameOf("zone", id), ids = { id } }
		end
		for _, row in ipairs(out) do
			local again = false
			for _, f in ipairs(first) do
				again = again or (row.kind == "zone" and row.name == f.name)
			end
			if not again then
				first[#first + 1] = row
			end
		end
		out = first
	end
	for _, row in ipairs(out) do
		if row.kind == "item" then
			local item = FD.Item(row.id)
			row.quality, row.available = item and item.quality, item and item.available
		end
	end
	-- Every instance's level range now, in the job, so drawing the rows'
	-- subtitles does not work them out in one frame.
	for _, row in ipairs(out) do
		local z = row.kind == "zone" and FD.Zone(row.id)
		if z and z.instance then
			ns.ZoneLevels(row.id)
		end
	end
	-- A list of dungeons, raids or battlegrounds asked for by filters alone
	-- (is:dungeon): by their level, lowest first, as one picks the next one.
	local instancesOnly = text == "" and #out > 0
	for _, row in ipairs(out) do
		local z = row.kind == "zone" and FD.Zone(row.id)
		instancesOnly = instancesOnly and z and z.instance ~= nil
	end
	if instancesOnly then
		local low, high = {}, {}
		for _, row in ipairs(out) do
			low[row], high[row] = ns.ZoneLevels(row.id)
		end
		table.sort(out, function(a, b)
			if (low[a] ~= nil) ~= (low[b] ~= nil) then
				return low[a] ~= nil
			end
			if low[a] and low[a] ~= low[b] then
				return low[a] < low[b]
			end
			if high[a] and high[a] ~= high[b] then
				return high[a] < high[b]
			end
			return a.name < b.name
		end)
	end
	if filters.grouped then
		out = GroupFinds(out)
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

-- One line under a find's name: "Turtle · level 49-50 · The Hinterlands",
-- a creature named by its family or type where known.
function ns.Subtitle(row)
	local parts = { ns.KindLabel(row.kind, row.id) }
	local creature = row.kind == "npc" and FD.Npc(row.id)
	if creature and creature.kind then
		parts[1] = creature.kind
	end
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
		if q and q.level and q.level > 0 then -- -1: it has the player's
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
		-- A dungeon, raid or battleground: the level of what you fight there.
		local low, high = nil, nil
		if z and z.instance then
			low, high = ns.ZoneLevels(row.id)
		end
		if low then
			parts[#parts + 1] = "level " .. RangeText(low, high)
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

-- Grouped writes rows by way of getting, likeliest first (or by opts.order),
-- at most PER_METHOD each; label names a row's other side, opts.suffix adds
-- to it after (where it is).
local function Grouped(lines, rows, headings, label, more, opts)
	local byMethod = {}
	for _, row in ipairs(rows) do
		byMethod[row.method] = byMethod[row.method] or {}
		table.insert(byMethod[row.method], row)
	end
	for _, method in ipairs(opts and opts.methods or METHODS) do
		local list = byMethod[method]
		if list then
			table.sort(list, opts and opts.order or ByChance)
			-- Things of one name (two Defias Mercenary creatures) are one
			-- entry: the likeliest, as the list is sorted.
			local seen, kept = {}, {}
			for i, row in ipairs(list) do
				if i % 50 == 0 then
					Pause()
				end
				local key = opts and opts.key and opts.key(row) or ns.Unlink(label(row))
				if not seen[key] then
					seen[key] = true
					kept[#kept + 1] = row
				end
			end
			list = kept
			lines[#lines + 1] = ""
			lines[#lines + 1] = GOLD .. ("%s (%d):|r"):format(headings[method], #list)
			for i = 1, math.min(#list, PER_METHOD) do
				lines[#lines + 1] = { "  " .. label(list[i]) .. (opts and opts.suffix and opts.suffix(list[i]) or ""), Chance(list[i]) }
			end
			if #list > PER_METHOD then
				lines[#lines + 1] = more and More(#list - PER_METHOD, more)
					or GREY .. ("  and %d more|r"):format(#list - PER_METHOD)
			end
		end
	end
end

-- A vendor's price: money, or so many of a currency.
local function Price(v)
	if not v.price then
		return GREY .. "unknown|r"
	end
	if v.currency then
		return ns.Currency(v.price, v.currency)
	end
	return ns.Money(v.price)
end

-- The game's own tooltip of an item, as page lines: what kind of item it
-- is, its stats and effects, coloured as in the tooltip. The first line
-- (the name, the page's heading) and the sell price are left out. nil
-- until the client has the item: it is asked for then. ns.tooltipData is
-- the dataInstanceID of the last tooltip asked for: the game sends
-- TOOLTIP_DATA_UPDATE with it when a lookup it was waiting for has come,
-- and the window draws the page again then, as the game's tooltip does.
local SKIP_LINE = { [11] = true, [22] = true } -- Enum.TooltipDataLineType SellPrice, ItemName

local function Hex(c)
	if type(c) ~= "table" or not c.r then
		return "|cffffffff"
	end
	return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function Plain(text)
	return type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text))
end

local function TooltipLines(id)
	local get = C_TooltipInfo and C_TooltipInfo.GetItemByID
	local data = get and get(id)
	ns.tooltipData = data and data.dataInstanceID
	if not data or not data.lines or #data.lines < 2 then
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(id)
		end
		return nil
	end
	local out = {}
	for i, line in ipairs(data.lines) do
		if i > 1 and not SKIP_LINE[line.type] and Plain(line.leftText) then
			local left = Hex(line.leftColor) .. line.leftText .. "|r"
			if Plain(line.rightText) then
				out[#out + 1] = { left, Hex(line.rightColor) .. line.rightText .. "|r" }
			else
				out[#out + 1] = left
			end
		end
	end
	return out
end

-- Purpose is what an item is most likely searched for, by its class and
-- what it is part of: "buy" (consumables, reagents, ammo, quivers: you
-- want more, from a vendor), "quest" (a quest item or one a quest asks
-- for), "material" (trade goods: farmed or bought), "gear" (weapons and
-- armor: how to get it), else nil (the page as it was).
local PURPOSE_BY_CLASS = { [0] = "buy", [5] = "buy", [6] = "buy", [11] = "buy", [7] = "material", [12] = "quest", [2] = "gear", [4] = "gear" }
local function Purpose(id)
	local item = FD.Item(id)
	local purpose = item and PURPOSE_BY_CLASS[item.class]
	if purpose ~= "quest" then
		for _, row in ipairs(FD.QuestsOf("item", id)) do
			if row.role == "objective" and not Theirs("quest", row.quest) and (purpose == nil or purpose == "material") then
				-- A thing a quest asks for that is not otherwise of use.
				if purpose == nil then
					purpose = "quest"
				end
			end
		end
	end
	return purpose
end

local QuestLines, ByLevel, ItemWays, WaysLines, RewardLines -- below
local function ItemLines(id, lines)
	local item = FD.Item(id)
	if item and not item.available then
		lines[#lines + 1] = RED .. "Not available to players (test, unused or not yet released).|r"
	end
	local tooltip = TooltipLines(id)
	for _, line in ipairs(tooltip or {}) do
		lines[#lines + 1] = line
	end
	if tooltip then
		lines[#lines + 1] = ""
	end
	local facts = {} -- the tooltip says these, when there is one
	if not tooltip and item and item.itemLevel and item.itemLevel > 0 then
		facts[#facts + 1] = "item level " .. item.itemLevel
	end
	if not tooltip and item and item.requiredLevel and item.requiredLevel > 1 then
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

	-- How to get it: built once, and kept a moment for the page's redraws
	-- as the item's tooltip comes in (Linen Cloth's took 30 ms).
	for _, line in ipairs(ItemWays(id)) do
		lines[#lines + 1] = line
	end
end

local WAYS_KEPT = 2 -- seconds
local waysKept = {}
function ItemWays(id)
	local key = id .. ":" .. tostring(pageSide)
	local now = GetTime and GetTime()
	local kept = waysKept[key]
	if kept and now and now - kept.at < WAYS_KEPT then
		return kept.lines
	end
	local lines = {}
	WaysLines(id, lines)
	waysKept = { [key] = now and { at = now, lines = lines } or nil }
	return lines
end

function WaysLines(id, lines)
	-- The question behind the item: what it is for decides what the page
	-- leads with ("Buy:", "For:", "Farm:", "Get it:") and the order of the
	-- ways of getting it after.
	local purpose = Purpose(id)
	local continent, at = PlayerWorld()
	local level = UnitLevel and tonumber(UnitLevel("player"))

	-- Where it comes from. Creatures the player can fight first: none more
	-- than 3 levels above them (a level-60 elite drops Linen Cloth too, and
	-- is no place to get it at 12); then likeliest, then nearest. Each with
	-- its nearest spot.
	local sources = {}
	for i, d in ipairs(FD.Drops(id, Pause)) do
		if i % 25 == 0 then
			Pause()
		end
		if not Theirs(d.kind, d.id) then
			sources[#sources + 1] = d
		end
	end
	-- Where each source stands: its nearest spot and how many spots it has,
	-- over every creature or object of its name (Copper Vein is several).
	local near, byName = {}, {}
	for i, d in ipairs(sources) do
		if i % 25 == 0 then
			Pause()
		end
		if d.kind == "npc" or d.kind == "object" then
			local key = d.kind .. ":" .. ns.NameOf(d.kind, d.id)
			byName[key] = byName[key] or { kind = d.kind, ids = {}, seen = {} }
			if not byName[key].seen[d.id] then
				byName[key].seen[d.id] = true
				table.insert(byName[key].ids, d.id)
			end
			near[d] = byName[key]
		end
	end
	for _, group in pairs(byName) do
		Pause()
		group.spawns = 0
		for _, other in ipairs(group.ids) do
			Pause()
			group.spawns = group.spawns + #FD.Spawns(group.kind, other)
			local spot, yards = Nearest(group.kind, other, continent, at)
			if spot and (not group.spot or (yards and (not group.yards or yards < group.yards))) then
				group.spot, group.yards, group.id = spot, yards, other
			end
		end
	end
	-- Worked out once per source, not in every comparison of the sorts.
	-- The sorts below cannot give the frame back mid-way, so what they
	-- compare is worked out first, as plain fields of each source: reach
	-- (it can be fought), yards (to its nearest spot), farm (chance by how
	-- many stand about).
	for i, d in ipairs(sources) do
		if i % 25 == 0 then
			Pause()
		end
		local n = level and d.kind == "npc" and FD.Npc(d.id)
		d.reach = not (n and n.minLevel and n.minLevel > level + 3)
		d.yards = near[d] and near[d].yards
		d.farm = (d.chance or 0) * math.min(near[d] and near[d].spawns or 0, 20)
		d.key = d.kind .. ns.NameOf(d.kind, d.id)
	end
	local function SourceOrder(a, b)
		if a.reach ~= b.reach then
			return a.reach
		end
		if (a.chance or -1) ~= (b.chance or -1) then
			return ByChance(a, b)
		end
		local ya, yb = a.yards, b.yards
		if (ya ~= nil) ~= (yb ~= nil) then
			return ya ~= nil
		end
		if ya and ya ~= yb then
			return ya < yb
		end
		return ByChance(a, b)
	end
	local function SourceWhere(d)
		local n = near[d]
		return n and Where(d.kind, n.id or d.id, n.spot, n.yards) or ""
	end
	-- Where to farm: creatures one can fight on one's own continent first,
	-- then the most likely catch for the time spent: chance by how many of it
	-- stand about (up to 20; one named creature is no farm), then nearest.
	local function FarmOrder(a, b)
		if a.reach ~= b.reach then
			return a.reach
		end
		local ya, yb = a.yards, b.yards
		if (ya ~= nil) ~= (yb ~= nil) then
			return ya ~= nil
		end
		local sa, sb = a.farm, b.farm
		if sa ~= sb then
			return sa > sb
		end
		if ya and ya ~= yb then
			return ya < yb
		end
		return ByChance(a, b)
	end
	local farming = purpose == "material" or purpose == "quest"
	local sourceOrder = farming and FarmOrder or SourceOrder

	-- Vendors nearest first: who sells it is a question of where to go.
	-- Those on the player's continent by distance, then the rest as listed.
	local vendors = {}
	for i, v in ipairs(FD.Vendors(id)) do
		if not Theirs("npc", v.npc) then
			local spot, yards = Nearest("npc", v.npc, continent, at)
			vendors[#vendors + 1] = { v = v, spot = spot, yards = yards, order = i }
		end
	end
	table.sort(vendors, function(a, b)
		if (a.yards ~= nil) ~= (b.yards ~= nil) then
			return a.yards ~= nil
		end
		if a.yards and a.yards ~= b.yards then
			return a.yards < b.yards
		end
		return a.order < b.order
	end)
	local function VendorLine(near)
		local v = near.v
		local extra = {}
		if v.stock then
			extra[#extra + 1] = v.stock .. " in stock"
		end
		if v.standing then
			extra[#extra + 1] = STANDING_LABEL[v.standing] or ("standing " .. v.standing)
		end
		return ("%s: %s%s%s"):format(ns.Link("npc", v.npc), Price(v),
			#extra > 0 and (GREY .. " (" .. table.concat(extra, ", ") .. ")|r") or "", Where("npc", v.npc, near.spot, near.yards))
	end

	-- The quests it is part of, by role.
	local quests = {}
	for _, row in ipairs(FD.QuestsOf("item", id)) do
		if not Theirs("quest", row.quest) then
			quests[row.role] = quests[row.role] or {}
			table.insert(quests[row.role], row.quest)
		end
	end
	for _, list in pairs(quests) do
		table.sort(list, ByLevel)
	end

	-- The lead.
	local best
	for _, d in ipairs(sources) do
		if d.method ~= "disenchanting" and (not best or sourceOrder(d, best)) then
			best = d
		end
	end
	local function BestSource()
		return ns.Link(best.kind, best.id) .. " " .. Chance(best) .. SourceWhere(best)
	end
	local lead = {}
	if purpose == "quest" and quests.objective then
		lead[#lead + 1] = GOLD .. "For:|r " .. ns.Link("quest", quests.objective[1])
		if best then
			lead[#lead + 1] = GOLD .. "From:|r " .. BestSource()
		end
	elseif (purpose == "buy" or purpose == "material" or purpose == "gear") and vendors[1]
		and not (purpose == "gear" and quests.reward) then
		lead[#lead + 1] = GOLD .. "Buy:|r " .. VendorLine(vendors[1])
	elseif purpose == "gear" and quests.reward then
		lead[#lead + 1] = GOLD .. "Get it:|r reward from " .. ns.Link("quest", quests.reward[1])
	elseif (purpose == "material" or purpose == "gear" or purpose == "buy" or purpose == "quest") and best then
		local item = FD.Item(id)
		local label = purpose == "material" and "Farm:" or "Get it:"
		if purpose == "gear" and item and item.widespread then
			lead[#lead + 1] = GOLD .. label .. "|r world drop; likeliest " .. BestSource()
		else
			lead[#lead + 1] = GOLD .. label .. "|r " .. BestSource()
		end
	end
	if #lead > 0 then
		lines[#lines + 1] = ""
		for _, l in ipairs(lead) do
			lines[#lines + 1] = l
		end
	end

	-- The way of getting it the lead names comes first (Copper Ore: the
	-- veins it is found in before the creatures that carry some).
	local methods = METHODS
	if best then
		methods = { best.method }
		for _, m in ipairs(METHODS) do
			if m ~= best.method then
				methods[#methods + 1] = m
			end
		end
	end

	-- The ways of getting it, in the purpose's order.
	local function Drops()
		Grouped(lines, sources, FROM_HEADING, function(d)
			return ns.Link(d.kind, d.id)
		end, nil, { order = sourceOrder, suffix = SourceWhere, methods = methods, key = function(d) return d.key end })
	end
	local function Sold()
		if #vendors == 0 then
			return
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. ("Sold by (%d):|r"):format(#vendors)
		for i = 1, math.min(#vendors, PER_METHOD) do
			lines[#lines + 1] = "  " .. VendorLine(vendors[i])
		end
		if #vendors > PER_METHOD then
			lines[#lines + 1] = GREY .. ("  and %d more%s|r"):format(#vendors - PER_METHOD, continent and ", further off" or "")
		end
	end
	local function Quests()
		QuestLines(lines, "item", id)
	end
	local order = {
		buy = { Sold, Drops, Quests },
		quest = { Quests, Drops, Sold },
		material = { Drops, Sold, Quests },
		gear = { Quests, Drops, Sold },
	}
	for _, section in ipairs(order[purpose] or { Drops, Sold, Quests }) do
		section()
	end
end

local function LootLines(kind, id, lines)
	Grouped(lines, FD.Loot(kind, id), GIVES_HEADING, function(row)
		return ns.Link("item", row.item)
	end, kind ~= "zone" and ns.FromWord(ns.NameOf(kind, id)) or nil)
end

-- Quests --------------------------------------------------------------------

local function QuestLevel(id)
	local q = FD.Quest(id)
	return q and q.level or 0
end

-- Lower level first, then by name.
function ByLevel(a, b)
	local la, lb = QuestLevel(a), QuestLevel(b)
	if la ~= lb then
		return la < lb
	end
	return ns.NameOf("quest", a) < ns.NameOf("quest", b)
end

-- A list entry for a quest: its link, its level on the right.
-- A quest of the other side has its crest; one of yours, or for both, not.
-- A repeatable one says so too (Arathi Basin's come in a one-time and a
-- repeatable version of one name and level).
local SIDE_SHORT = { alliance = "Alliance", horde = "Horde" }
-- The faction crest, as Forever's unit frames (and CompactTip) show it.
local CREST = { Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance", Horde = "UI-HUD-UnitFrame-SmallCircle-Horde" }

-- Crest is a side's crest as text: 18 px, as the art has a margin, and
-- 3 px down so it sits on the line rather than above it.
local function Crest(side)
	return "|A:" .. CREST[side] .. ":18:18:0:-3|a"
end
-- PageSide is whose a page's thing is, for the crests at the top of its
-- page: "Alliance" or "Horde" for a quest only that side may take or a
-- creature friendly to that side alone; "Both" for a quest either may take
-- or a creature friendly to both (Booty Bay); nil for anything else (a
-- creature friendly to neither, a quest whose side nothing says; items,
-- objects, zones: the data gives them no side).
function ns.PageSide(kind, id)
	if kind == "quest" then
		local q = FD.Quest(id)
		if not q then
			return nil
		end
		if q.side then
			return SIDE_SHORT[q.side]
		end
		-- No race asked for does not make it both sides' (Jitters' Growling
		-- Gut is Duskwood's, given by Alliance people): the side is its
		-- givers'. One side's if each giver is that side's alone, both if
		-- one is both sides', none for an item or object to start it.
		local found
		for _, ref in ipairs(q.starts or {}) do
			local side = ref.kind == "npc" and ns.PageSide("npc", ref.id) or nil
			if not side then
				return nil
			end
			if found and found ~= side then
				return "Both"
			end
			found = side
		end
		return found
	elseif kind == "npc" then
		local n = FD.Npc(id)
		local a, h = n and n.alliance == "friendly", n and n.horde == "friendly"
		if a and h then
			return "Both"
		elseif a then
			return "Alliance"
		elseif h then
			return "Horde"
		end
	end
	return nil
end
ns.CREST = CREST

-- PageClasses is the classes a quest is for, as the game's square class
-- art (classicon-<class>), for the top of its page: {atlas,
-- ...}, empty for a quest any class may take and for anything else. More
-- than MAX_CLASS_ICONS (Vile Familiars: all but Warlock) is no icons: the
-- page's text says which.
local MAX_CLASS_ICONS = 5
function ns.PageClasses(kind, id)
	local q = kind == "quest" and FD.Quest(id)
	local out = {}
	if q and q.classes then
		for class = 1, 12 do
			if math.floor(q.classes / 2 ^ (class - 1)) % 2 == 1 then
				local name = FD.ClassName(class)
				if name then
					out[#out + 1] = "classicon-" .. string.lower(name)
				end
			end
		end
	end
	if #out > MAX_CLASS_ICONS then
		return {}
	end
	return out
end

-- PageRaces is the races a quest is for, as the game's race portraits
-- (raceicon-<race>-<male or female>, the player's own), for the top of its
-- page: {atlas name without its -c60, ...}. Only for a quest part of a
-- side may take (Undead only, Skyborne only): a quest for every Classic
-- race of its side is the side's, which its crest says. Quests from
-- Classic's data leave the Skyborne out of such a list; that is not taken
-- to mean they cannot.
function ns.PageRaces(kind, id)
	local out = {}
	local races = kind == "quest" and LimitedRaces(FD.Quest(id))
	local female = UnitSex and UnitSex("player") == 3
	for _, r in ipairs(races or {}) do
		local race = FD.Race(r)
		if race then
			out[#out + 1] = "raceicon-" .. ns.RaceKey(race.name) .. (female and "-female" or "-male")
		end
	end
	return out
end

-- Standing is a reputation as the game names its steps: points from
-- neutral (3000 friendly, 9000 honored, 21000 revered, 42000 exalted), the
-- points shown too when between steps ("Friendly 5500").
local STANDINGS = {
	{ -42000, "Hated" }, { -6000, "Hostile" }, { -3000, "Unfriendly" }, { 0, "Neutral" },
	{ 3000, "Friendly" }, { 9000, "Honored" }, { 21000, "Revered" }, { 42000, "Exalted" },
}
function ns.Standing(value)
	local name, at = "Hated", -42000
	for _, s in ipairs(STANDINGS) do
		if value >= s[1] then
			name, at = s[2], s[1]
		end
	end
	return value == at and name or ("%s %d"):format(name, value)
end

-- QuestNeeds is what else a quest asks before it is offered, as lines:
-- reputation, items to have, a spell known or not, a specialisation, the
-- quests that open or close it, ranks.
function ns.QuestNeeds(q)
	local out = {}
	local function faction(id) return FD.Faction(id) or ("faction " .. id) end
	if q.minRep then
		out[#out + 1] = ("%s with %s"):format(ns.Standing(q.minRep.value), faction(q.minRep.faction))
	end
	if q.maxRep then
		out[#out + 1] = ("at most %s with %s"):format(ns.Standing(q.maxRep.value), faction(q.maxRep.faction))
	end
	for _, item in ipairs(q.needsItems or {}) do
		out[#out + 1] = "have " .. ns.Link("item", item)
	end
	if q.spell then
		local name = FD.SpellName(math.abs(q.spell)) or ("spell " .. math.abs(q.spell))
		out[#out + 1] = (q.spell > 0 and "know " or "not know ") .. name
	end
	-- A specialisation's spell (Weaponsmith), or a profession's skill line
	-- (202 Engineering): a profession the quest already asks for (the
	-- facts say "Engineering 200") is not said again.
	local spec = q.specialization
	if spec and FD.SkillName(spec) then
		if spec ~= q.skillLine then
			out[#out + 1] = FD.SkillName(spec)
		end
	elseif spec then
		out[#out + 1] = FD.SpellName(spec) or ("specialisation " .. spec)
	end
	if q.fromQuest then
		out[#out + 1] = "offered from " .. ns.Link("quest", q.fromQuest) .. " on"
	end
	if q.untilQuest then
		out[#out + 1] = "offered until " .. ns.Link("quest", q.untilQuest) .. " is done"
	end
	if q.disabledBy then
		out[#out + 1] = "no longer offered once " .. ns.Link("quest", q.disabledBy) .. " is done"
	end
	if q.ranks and #q.ranks > 0 then
		local names = {}
		for _, r in ipairs(q.ranks) do
			names[#names + 1] = FD.SkillName(r.line) or ("skill " .. r.line)
		end
		out[#out + 1] = "ranks of " .. table.concat(names, ", ")
	end
	return out
end

-- The reputation icon (Achievement_Reputation_01: the handshake).
local REPUTATION_ICON = 236681

-- PageBadges is the icons beside a quest page's crest, nearest it first:
-- its classes, its races, its profession, the reputation it needs. Each
-- {atlas or file, crop (a share of each side cut away), query (what a
-- click searches) or nil, label (what hovering names), more (lines under
-- it)}.
function ns.PageBadges(kind, id)
	local out = {}
	for _, atlas in ipairs(ns.PageClasses(kind, id)) do
		local word = string.match(atlas, "^classicon%-(.+)$")
		out[#out + 1] = { atlas = atlas, crop = 0, query = "quest: class:" .. word,
			label = (word:gsub("^%l", string.upper)) .. " quests" }
	end
	for _, atlas in ipairs(ns.PageRaces(kind, id)) do
		local word = string.match(atlas, "^raceicon%-(.-)%-[fe]*male$")
		local named = (word:gsub("^%l", string.upper)):gsub("elf$", " Elf")
		out[#out + 1] = { atlas = atlas, crop = 5 / 64, query = "quest: race:" .. word, label = named .. " quests" }
	end
	local q = kind == "quest" and FD.Quest(id)
	if q and q.skillLine then
		local name = FD.SkillName(q.skillLine)
		local icon = FD.SkillIcon(q.skillLine)
		if name and icon then
			out[#out + 1] = { file = icon, crop = 0.08, query = "quest: skill:" .. string.lower(name),
				label = name .. (q.skill and (" " .. q.skill) or "") }
		end
	end
	if q and (q.minRep or q.maxRep) then
		local more = {}
		if q.minRep then
			more[#more + 1] = ("%s with %s"):format(ns.Standing(q.minRep.value), FD.Faction(q.minRep.faction) or ("faction " .. q.minRep.faction))
		end
		if q.maxRep then
			more[#more + 1] = ("at most %s with %s"):format(ns.Standing(q.maxRep.value), FD.Faction(q.maxRep.faction) or ("faction " .. q.maxRep.faction))
		end
		out[#out + 1] = { file = REPUTATION_ICON, crop = 0.08, label = "Reputation needed", more = more }
	end
	return out
end

local function QuestEntry(id)
	local q = FD.Quest(id)
	local mine = UnitFactionGroup and UnitFactionGroup("player")
	local side = q and q.side and SIDE_SHORT[q.side] ~= mine and SIDE_SHORT[q.side]
	local crest = side and (" " .. Crest(side)) or ""
	local note = q and q.repeatable and (GREY .. " · repeatable|r") or ""
	return { "  " .. ns.Link("quest", id) .. crest .. note, q and q.level and tostring(q.level) or "" }
end

-- The quests a thing is part of, a heading a part: on a creature's page
-- the quests it starts, ends and is killed for, and so on.
local QUEST_ROLES = { "start", "end", "objective", "reward" }
local QUEST_HEADING = {
	npc = { start = "Starts quests", ["end"] = "Ends quests", objective = "Killed for quests" },
	object = { start = "Starts quests", ["end"] = "Ends quests", objective = "Used in quests" },
	item = { start = "Starts a quest", objective = "Needed for quests", reward = "Reward from quests" },
}
local QUESTS_SHOWN = 10
function QuestLines(lines, kind, id)
	local byRole = {}
	for _, row in ipairs(FD.QuestsOf(kind, id)) do
		if not Theirs("quest", row.quest) then
			byRole[row.role] = byRole[row.role] or {}
			table.insert(byRole[row.role], row.quest)
		end
	end
	for _, role in ipairs(QUEST_ROLES) do
		local list, heading = byRole[role], QUEST_HEADING[kind] and QUEST_HEADING[kind][role]
		if list and heading then
			table.sort(list, ByLevel)
			lines[#lines + 1] = ""
			lines[#lines + 1] = GOLD .. ("%s (%d):|r"):format(heading, #list)
			for i = 1, math.min(#list, QUESTS_SHOWN) do
				lines[#lines + 1] = QuestEntry(list[i])
			end
			if #list > QUESTS_SHOWN then
				lines[#lines + 1] = GREY .. ("  and %d more|r"):format(#list - QUESTS_SHOWN)
			end
		end
	end
end

-- A quest's text as the game shows it: $B a new line, $N your name, $C
-- your class, $R your race, $G his:her; the first.
local function QuestText(text)
	local name = UnitName and UnitName("player") or "you"
	local class = UnitClass and UnitClass("player") or "adventurer"
	local race = UnitRace and UnitRace("player") or "adventurer"
	text = string.gsub(text, "%$[Gg]%s*([^:;]*):([^;]*);", "%1")
	text = string.gsub(text, "%$[Bb]", "\n")
	text = string.gsub(text, "%$[Nn]", name)
	text = string.gsub(text, "%$[Cc]", class)
	text = string.gsub(text, "%$[Rr]", race)
	return text
end

-- Who or what a quest is started or ended by, or asks for, with where it is.
local Wanted
local function Party(ref)
	if ref.kind == "npc" or ref.kind == "object" then
		return ns.Link(ref.kind, ref.id) .. Spot(ref.kind, ref.id)
	elseif ref.kind == "item" then
		return Wanted(ref.id)
	end
	return ns.Link(ref.kind, ref.id)
end

-- An item a quest asks for, with where it mostly comes from.
function Wanted(itemID)
	local best
	for _, d in ipairs(FD.Drops(itemID)) do
		if not best or (d.chance or 0) > (best.chance or 0) then
			best = d
		end
	end
	if best then
		return ns.Link("item", itemID) .. GREY .. " · " .. ns.NameOf(best.kind, best.id) .. "|r"
	end
	if #FD.Vendors(itemID) > 0 then
		return ns.Link("item", itemID) .. GREY .. " · sold|r"
	end
	return ns.Link("item", itemID)
end


-- SameParties tells whether two lists of who starts and ends a quest name
-- the same creatures, objects and items, in any order.
local function SameParties(a, b)
	if not a or not b or #a == 0 or #a ~= #b then
		return false
	end
	local in_ = {}
	for _, r in ipairs(a) do
		in_[r.kind .. ":" .. r.id] = true
	end
	for _, r in ipairs(b) do
		if not in_[r.kind .. ":" .. r.id] then
			return false
		end
	end
	return true
end

-- RewardLines writes a quest's rewards as the quest log has them: a
-- "Rewards" heading, the items to choose one of, then what it gives
-- besides (items, experience, money, reputation), each a list of tiles the
-- window draws two to a row: {tiles = {{item, n} or {xp} or {money} or
-- {faction, value}, ...}}. A
-- quest whose sources do not say which items are given and which to choose
-- has them all as given, and so is an only item to choose.
local XP_ICON, MONEY_ICON = 894556, 133784
ns.XP_ICON, ns.MONEY_ICON, ns.REPUTATION_ICON = XP_ICON, MONEY_ICON, REPUTATION_ICON

-- ReputationText is a reputation reward: "+150 Undercity".
function ns.ReputationText(r)
	return ("%+d %s"):format(r.value, FD.Faction(r.faction) or ("faction " .. r.faction))
end
function RewardLines(lines, q)
	local choices, given = q.choices or {}, q.given or {}
	local known = #choices > 0 or #given > 0
	local rest = {}
	for _, r in ipairs(given) do
		rest[#rest + 1] = { item = r.item, n = r.n }
	end
	-- One item "to choose" is no choice: it is given.
	if #choices == 1 then
		rest[#rest + 1] = { item = choices[1].item, n = choices[1].n }
		choices = {}
	end
	if not known then
		for _, item in ipairs(q.rewards or {}) do
			rest[#rest + 1] = { item = item, n = 1 }
		end
	end
	if q.xp then
		rest[#rest + 1] = { xp = q.xp }
	end
	if q.money then
		rest[#rest + 1] = { money = q.money }
	end
	for _, r in ipairs(q.reputation or {}) do
		rest[#rest + 1] = { faction = r.faction, value = r.value }
	end
	if #choices == 0 and #rest == 0 then
		return
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = GOLD .. "Rewards|r"
	if #choices > 0 then
		local tiles = {}
		for _, r in ipairs(choices) do
			tiles[#tiles + 1] = { item = r.item, n = r.n }
		end
		lines[#lines + 1] = GREY .. "You will be able to choose one of these rewards:|r"
		lines[#lines + 1] = { tiles = tiles }
	end
	if #rest > 0 then
		lines[#lines + 1] = GREY .. (#choices > 0 and "You will also receive:" or "You will receive:") .. "|r"
		lines[#lines + 1] = { tiles = rest }
	end
end

local function QuestPage(id, lines)
	local q = FD.Quest(id)
	if not q then
		return
	end
	local facts = {}
	-- "Level 27 requires level 22"; one level when they are the same. A
	-- quest of no level of its own (-1: it has the player's) only requires.
	local level = q.level and q.level > 0 and q.level or nil
	if level and q.requiredLevel and q.requiredLevel ~= level then
		facts[#facts + 1] = ("Level %d requires level %d"):format(level, q.requiredLevel)
	elseif level then
		facts[#facts + 1] = "Level " .. level
	elseif q.requiredLevel then
		facts[#facts + 1] = "Requires level " .. q.requiredLevel
	end
	if q.maxLevel then
		facts[#facts + 1] = "up to level " .. q.maxLevel
	end
	-- The side, the classes and the races are the crest and icons at the
	-- top of the page. Classes only in words when there are more than its
	-- icons show (Vile Familiars: all but Warlock).
	if q.classes and #ns.PageClasses("quest", id) == 0 then
		local names = {}
		for class = 1, 12 do
			if math.floor(q.classes / 2 ^ (class - 1)) % 2 == 1 then
				local name = FD.ClassName(class)
				names[#names + 1] = name and ns.FindLink("quest: class:" .. string.lower(name), name) or ("class " .. class)
			end
		end
		facts[#facts + 1] = table.concat(names, ", ") .. " only"
	end
	if q.skillLine then
		local name = FD.SkillName(q.skillLine)
		facts[#facts + 1] = (name and ns.FindLink("quest: skill:" .. string.lower(name), name) or ("skill " .. q.skillLine))
			.. (q.skill and (" " .. q.skill) or "")
	end
	local inZone = q.zone and (" " .. Zone(q.zone)) or ""
	if q.repeatable then
		facts[#facts + 1] = ns.FindLink("quest: is:repeatable" .. inZone, "repeatable")
	end
	if q.new then
		facts[#facts + 1] = ns.FindLink("quest: is:new" .. inZone, "new in Forever")
	end
	if #facts > 0 then
		lines[#lines + 1] = table.concat(facts, ", ")
	end
	if q.zone then
		lines[#lines + 1] = GOLD .. "Zone:|r " .. ns.Link("zone", q.zone)
	end
	if q.text then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "|cffe0e0e0" .. QuestText(q.text) .. "|r"
	end
	local function Section(heading, list, line)
		if #list == 0 then
			return
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. heading .. ":|r"
		for _, v in ipairs(list) do
			lines[#lines + 1] = "  " .. line(v)
		end
	end
	-- Who gives it and who takes it in: one section when they are the same
	-- (Chemist Fuely gives and takes Melding of Influences).
	if SameParties(q.starts, q.ends) then
		Section("Starts and ends at", q.starts, Party)
	else
		Section("Starts at", q.starts, Party)
		Section("Ends at", q.ends, Party)
	end
	Section("Objectives", q.objectives, function(ref)
		if ref.kind == "item" then
			return Wanted(ref.id)
		elseif ref.kind == "faction" then
			return ("%s%s|r with %s"):format(GOLD, ref.standing and ("reach " .. ref.standing) or "reputation",
				FD.Faction(ref.id) or ("faction " .. ref.id))
		end
		return Party(ref)
	end)
	RewardLines(lines, q)
	Section("Needs", ns.QuestNeeds(q), function(line) return line end)
	Section("Requires", q.requiresAll, function(quest) return ns.Link("quest", quest) end)
	Section("Requires one of", q.requiresOne, function(quest) return ns.Link("quest", quest) end)
	if q.next then
		Section("Leads to", { q.next }, function(quest) return ns.Link("quest", quest) end)
	end
end

-- What a vendor sells, best first, with its price on the right.
local SELLS_SHOWN = 15
local function SellsLines(npcID, lines)
	local items = {}
	for _, id in ipairs(FD.Sells(npcID)) do
		items[#items + 1] = id
	end
	if #items == 0 then
		return
	end
	table.sort(items, function(a, b)
		local ia, ib = FD.Item(a), FD.Item(b)
		local qa, qb = ia and ia.quality or 0, ib and ib.quality or 0
		if qa ~= qb then
			return qa > qb
		end
		return ns.NameOf("item", a) < ns.NameOf("item", b)
	end)
	lines[#lines + 1] = ""
	lines[#lines + 1] = GOLD .. ("Sells (%d):|r"):format(#items)
	for i = 1, math.min(#items, SELLS_SHOWN) do
		local price = ""
		for _, v in ipairs(FD.Vendors(items[i])) do
			if v.npc == npcID then
				price = Price(v)
				break
			end
		end
		lines[#lines + 1] = { "  " .. ns.Link("item", items[i]), price }
	end
	if #items > SELLS_SHOWN then
		lines[#lines + 1] = More(#items - SELLS_SHOWN, ns.FromWord(ns.NameOf("npc", npcID)))
	end
end

-- Zones -----------------------------------------------------------------------

local function LevelText(n)
	if not n or not n.minLevel then
		return ""
	end
	return n.minLevel == n.maxLevel and tostring(n.minLevel) or ("%d-%d"):format(n.minLevel, n.maxLevel or n.minLevel)
end

-- What stands in a zone: the level of what fights there, its quests, the
-- creatures you fight there, the people, its objects (what gives loot or is part of a quest
-- first), at most HERE each. A subzone has none of its own (spots are
-- filed under the zone).
local HERE = 15
-- GivesQuests tells whether a creature starts or ends a quest; one that is
-- only an objective (an unseen "Credit Marker") does not count.
local function GivesQuests(npcID)
	for _, row in ipairs(FD.QuestsOf("npc", npcID)) do
		if row.role == "start" or row.role == "end" then
			return true
		end
	end
	return false
end

local function ZoneLines(id, lines)
	lines[#lines + 1] = ns.FindLink(Zone(id), "Search in " .. ns.NameOf("zone", id))
	-- Creatures you fight (they give loot and are friendly to neither
	-- side), the most common first; and the people worth finding: those
	-- with a title (a vendor, a trainer, a flight master) or a quest.
	local fought, people, spots, bosses = {}, {}, {}, {}
	local inZone = {}
	for _, area in ipairs(FD.Subzones(id)) do
		inZone[area] = true
	end
	for i, row in ipairs(FD.Search("", 1000, { "npc" }, { zone = { id }, distinct = true, pause = Pause })) do
		if i % 50 == 0 then
			Pause()
		end
		local n = FD.Npc(row.id)
		-- An instance's bosses, loot known or not (Scarlet Enclave's is not).
		if n and n.boss then
			bosses[#bosses + 1] = row
		elseif n and n.alliance ~= "friendly" and n.horde ~= "friendly" and FD.HasLoot("npc", row.id) then
			local count = 0
			for _, other in ipairs(row.ids or { row.id }) do
				for _, spot in ipairs(FD.Spawns("npc", other)) do
					if inZone[spot.zone] then
						count = count + 1
					end
				end
			end
			spots[row.id] = count
			fought[#fought + 1] = row
		elseif n and (n.title or GivesQuests(row.id)) and not Theirs("npc", row.id) then
			people[#people + 1] = row
		end
	end
	table.sort(fought, function(a, b)
		if spots[a.id] ~= spots[b.id] then
			return spots[a.id] > spots[b.id]
		end
		return a.name < b.name
	end)
	table.sort(people, function(a, b) return a.name < b.name end)

	-- The level of what you fight there (ns.ZoneLevels).
	local low, high = ns.ZoneLevels(id)
	if low then
		local range = RangeText(low, high)
		lines[#lines + 1] = ns.FindLink("npc: " .. Zone(id) .. " lvl:" .. range,
			(low == high and "creatures level %s" or "creatures mostly level %s"):format(range))
	end

	if #bosses > 0 then
		table.sort(bosses, function(a, b)
			local la, lb = FD.Npc(a.id).maxLevel or 0, FD.Npc(b.id).maxLevel or 0
			if la ~= lb then
				return la < lb
			end
			return a.name < b.name
		end)
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. ("Bosses (%d):|r"):format(#bosses)
		for i = 1, math.min(#bosses, HERE) do
			lines[#lines + 1] = { "  " .. ns.Link("npc", bosses[i].id), LevelText(FD.Npc(bosses[i].id)) }
		end
		if #bosses > HERE then
			lines[#lines + 1] = More(#bosses - HERE, "npc: is:boss " .. Zone(id))
		end
	end

	-- Its quests, its subzones' too (Northshire Valley's are Elwynn Forest's).
	local quests, seen = {}, {}
	for _, area in ipairs(FD.Subzones(id)) do
		for _, row in ipairs(FD.QuestsOf("zone", area)) do
			if not seen[row.quest] and not Theirs("quest", row.quest) then
				seen[row.quest] = true
				quests[#quests + 1] = row.quest
			end
		end
	end
	if #quests > 0 then
		table.sort(quests, ByLevel)
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. ("Quests here (%d):|r"):format(#quests)
		for i = 1, math.min(#quests, HERE) do
			lines[#lines + 1] = QuestEntry(quests[i])
		end
		if #quests > HERE then
			lines[#lines + 1] = More(#quests - HERE, "quest: " .. Zone(id))
		end
	end

	local function Creatures(heading, list)
		if #list == 0 then
			return
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. ("%s (%d):|r"):format(heading, #list)
		for i = 1, math.min(#list, HERE) do
			lines[#lines + 1] = { "  " .. ns.Link("npc", list[i].id), LevelText(FD.Npc(list[i].id)) }
		end
		if #list > HERE then
			lines[#lines + 1] = More(#list - HERE, "npc: " .. Zone(id))
		end
	end
	Creatures("Creatures here", fought)
	Creatures("People here", people)

	local objects = FD.Search("", 1000, { "object" }, { zone = { id }, distinct = true, pause = Pause })
	local useful = {}
	for _, row in ipairs(objects) do
		useful[row.id] = (FD.HasLoot("object", row.id) and 2 or 0) + (#FD.QuestsOf("object", row.id) > 0 and 1 or 0)
	end
	table.sort(objects, function(a, b)
		if useful[a.id] ~= useful[b.id] then
			return useful[a.id] > useful[b.id]
		end
		return a.name < b.name
	end)
	if #objects > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = GOLD .. ("Objects here (%d):|r"):format(#objects)
		for i = 1, math.min(#objects, HERE) do
			lines[#lines + 1] = "  " .. ns.Link("object", objects[i].id)
		end
		if #objects > HERE then
			lines[#lines + 1] = More(#objects - HERE, "object: " .. Zone(id))
		end
	end
end

-- What to say about a find, as lines of text with colour codes. A line
-- that is a table, {left, right}, is a list entry whose right part (a
-- chance) the preview aligns to the right. typed is the bar's text: its
-- side: word, if any, says whose quests and people the page lists.
function ns.Details(kind, id, typed)
	if not ns.Ready() then
		return { RED .. "ForeverData is missing or of another version.|r" }
	end
	local _, _, options = ns.Parse(typed or "")
	pageSide = options.side
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
				-- A link to the others of its rank in its zone.
				local zone = MainZone("npc", id)
				facts[#facts + 1] = ns.FindLink("npc: is:" .. RANK_WORD[n.rank] .. (zone and (" " .. ns.InWord(zone)) or ""), RANK_LABEL[n.rank])
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
		QuestLines(lines, "npc", id)
		SellsLines(id, lines)
		LootLines("npc", id, lines)
	elseif kind == "object" then
		local where = Places("object", id)
		if where ~= "" then
			lines[#lines + 1] = GOLD .. "Where:|r " .. where
		end
		QuestLines(lines, "object", id)
		LootLines("object", id, lines)
	elseif kind == "quest" then
		QuestPage(id, lines)
	elseif kind == "zone" then
		local z = FD.Zone(id)
		if z and z.parent then
			lines[#lines + 1] = "In " .. ns.Link("zone", z.parent)
		end
		ZoneLines(id, lines)
		LootLines("zone", id, lines)
	end
	if #lines == 0 then
		lines[1] = GREY .. "Nothing more known.|r"
	end
	return lines
end
