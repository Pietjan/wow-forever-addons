-- ForeverRecorder: records what the game shows, for wow-forever-data's
-- offline database. Game facts only: creature, object, item and quest IDs,
-- counts, prices, levels and map positions. Never a character's name, a
-- realm or a GUID (a GUID is read for the IDs in it and dropped).
--
-- Unit identity (UnitGUID, UnitCreatureType) is secret to addon code while
-- addon restrictions are on: in combat, in a boss encounter, in a PvP match
-- (API docs, AddOnRestrictionType). So nothing is read in a fight: loot,
-- vendor and quest windows and targeting out of combat are what this
-- records. Every value is checked with issecretvalue; one that is secret
-- is not recorded, and counted under "secret" for /recorder.
--
-- ForeverRecorderDB, account-wide (the format wow-forever-data reads):
--   version  this format, 1
--   build    the game build it was last written in ("1.60.1.71037")
--   loot[key][method] = { looted = sources opened, items = { [item] = { n = times, q = amount } } }
--            key "n<creature>" or "o<object>"; for fishing "a<uiMap>"; method
--            drop, skinning, pickpocketing, gathering, fishing, contained
--   vendors[creature] = { seen = "YYYY-MM-DD", items = { [item] = { price, stack, available, costs } } }
--            price copper per purchase (0 when it costs only items or currency),
--            available -1 unlimited, costs "i<item>:<n>,c<currency>:<n>" or nil
--   quests[quest] = { starts = { [key] = true }, ends = { [key] = true },
--            rewards = { [item] = n }, choices = { [item] = n }, money = copper }
--            key "n<creature>" or "o<object>"
--   creatures[creature] = { name, min, max (levels), class (classification), type, family,
--            a, h (reaction to Alliance, Horde: hostile/neutral/friendly) }
--   spots[key] = { ["<uiMap>:<x>:<y>"] = times } in tenths of a percent;
--            "i<instance map>" for inside an instance, where the map gives no position
--   secret[what] = times a value was secret and left out

local ADDON, ns = ...

local IsSecret = issecretvalue or function() return false end
ns.FORMAT = 1

-- Plain is v unless it is secret (then nil).
function ns.Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

-- Secret counts a value the game would not give, by what it was.
function ns.Secret(what)
	local s = ns.db and ns.db.secret
	if s then
		s[what] = (s[what] or 0) + 1
	end
end

-- Read calls fn in a pcall and gives its first result unless it failed or
-- was secret, counting that under what.
function ns.Read(what, fn, ...)
	local ok, v = pcall(fn, ...)
	if not ok then
		return nil
	end
	if v ~= nil and IsSecret(v) then
		ns.Secret(what)
		return nil
	end
	return v
end

-- Key is the recorder's key for a GUID ("n2505", "o1731") and the kind:
-- creatures (and vehicles) and game objects; nil for players, pets, items.
function ns.Key(guid)
	guid = ns.Plain(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" then
		return "n" .. id, "npc", tonumber(id)
	elseif kind == "GameObject" then
		return "o" .. id, "object", tonumber(id)
	end
	return nil
end

-- ItemID is the item ID in an item link.
function ns.ItemID(link)
	link = ns.Plain(link)
	return type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
end

-- Spot is where the player stands, as the recorder files it: "<uiMap>:<x>:<y>"
-- in tenths of a percent of that map, or "i<instance map>" inside an
-- instance whose map gives no position; nil when neither is known.
function ns.Spot()
	local map = ns.Read("map", C_Map.GetBestMapForUnit, "player")
	if map then
		local pos = ns.Read("position", C_Map.GetPlayerMapPosition, map, "player")
		if pos then
			local ok, x, y = pcall(pos.GetXY, pos)
			x, y = ok and ns.Plain(x), ok and ns.Plain(y)
			if x and y and (x > 0 or y > 0) then
				return string.format("%d:%d:%d", map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5))
			end
		end
	end
	local ok, _, kind, _, _, _, _, _, instance = pcall(GetInstanceInfo)
	instance = ok and ns.Plain(instance)
	if instance and kind ~= "none" then
		return "i" .. instance
	end
	return nil
end

-- Place files the player's spot under key, once more.
function ns.Place(key)
	local spot = key and ns.Spot()
	if not spot then
		return
	end
	local spots = ns.db.spots
	spots[key] = spots[key] or {}
	spots[key][spot] = (spots[key][spot] or 0) + 1
end

-- Fighting is true while addon restrictions may make identity secret.
function ns.Fighting()
	return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

function ns.Today()
	return date("%Y-%m-%d")
end

-- Events ----------------------------------------------------------------------

local handlers = {}
local frame = CreateFrame("Frame")
ns.frame = frame

-- On calls fn(...) on event, once the database is ready.
function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

local function Load()
	local db = type(ForeverRecorderDB) == "table" and ForeverRecorderDB or {}
	ForeverRecorderDB = db
	db.version = ns.FORMAT
	for _, t in ipairs({ "loot", "vendors", "quests", "creatures", "spots", "secret" }) do
		db[t] = type(db[t]) == "table" and db[t] or {}
	end
	local ok, version, build = pcall(GetBuildInfo)
	if ok and version and build then
		db.build = version .. "." .. build
	end
	ns.db = db
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			Load()
		end
		return
	end
	if not ns.db then
		return
	end
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			ns.Secret("error " .. event)
			ns.lastError = err
		end
	end
end)

-- /recorder -------------------------------------------------------------------

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

function ns.Summary()
	local db = ns.db
	local sources, opened = 0, 0
	for _, methods in pairs(db.loot) do
		sources = sources + 1
		for _, m in pairs(methods) do
			opened = opened + (m.looted or 0)
		end
	end
	local lines = {
		string.format("ForeverRecorder (build %s): %d creatures, objects and places looted (%d times), %d vendors, %d quests, %d creatures seen, %d spots",
			db.build or "?", sources, opened, Count(db.vendors), Count(db.quests), Count(db.creatures), Count(db.spots)),
	}
	local refused = {}
	for what, n in pairs(db.secret) do
		refused[#refused + 1] = what .. " " .. n
	end
	table.sort(refused)
	lines[#lines + 1] = #refused > 0 and ("Not given (secret or failed): " .. table.concat(refused, ", ")) or "Nothing was refused."
	if ns.lastError then
		lines[#lines + 1] = "Last error: " .. tostring(ns.lastError)
	end
	return lines
end

SLASH_FOREVERRECORDER1 = "/recorder"
SlashCmdList.FOREVERRECORDER = function()
	if not ns.db then
		return
	end
	for _, line in ipairs(ns.Summary()) do
		print(line)
	end
end
