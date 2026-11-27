-- ForeverUpgrades, the list: every piece of gear that would be an upgrade,
-- slot by slot, with where it comes from. /upgrades opens it.
--
-- This file is the workings; Window.lua draws them.
--
-- - What exists and where it comes from is QuestieDB's: its item list, and
--   per item the quests that reward it, the mobs, chests and containers
--   that drop it and the vendors that sell it. What professions make is in
--   Data.lua, from the client's recipe tables.
-- - What an item is (slot, stats, who can wear it) is asked of the game,
--   item by item: half of the gear is not in the client's files and only
--   the running game knows it. That takes a while the first time in a
--   session.
-- - Whether it is an upgrade, and by how much, is Arrow.lua's answer
--   (UpgradeArrow.Evaluate): the same spec and the same comparison with
--   what you wear as the arrows.
--
-- Listed is what you could get now: an item you can equip at your level,
-- from a quest you can still do (your race and class, its level reached,
-- not handed in yet), a vendor of your side, a drop from a mob not far
-- above your level (see ABOVE), a chest or a recipe.
-- An item with no known source is left out unless asked for, and test and
-- other items that are not for players (by their names) always, as are
-- the items listed in Ignore.lua. A recipe
-- counts for an item that binds when picked up only when the profession
-- is your own: nobody else can make that one for you. A vendor or a
-- container does not count for an item with no level requirement whose
-- item level is far above your level (see ABOVE).
--
-- What the game said about an item, and whether it is an upgrade, is kept
-- for the session. An item is looked at again only when its answer can
-- have changed: something worn in its slot changed, or your weights, role
-- or level did; after a skill change only the items you could not use.
-- Opening the window when nothing changed costs nothing.
--
-- Nothing is weighed before the game answers for everything you wear, and
-- never in the middle of a gear change: a worn item that has not loaded
-- scores nothing, and the first items looked at would all seem to beat it.
--
-- Not known here: drop chances, the skill a recipe needs, and the random
-- "of the ..." stats a world drop can roll (it is scored without them).

local ADDON, ns = ...

local TICK = 0.05
local BUDGET = 8 -- milliseconds of work per tick
local ASK_PER_TICK = 40 -- items asked of the game per tick
local WAITING_MAX = 200 -- asked and not answered yet, at most
local GIVE_UP = 8 -- seconds to wait for an item the game does not answer for
local WARM_UP = 3 -- seconds to wait, at most, for what you wear to answer
local CONTRACT = 4 -- QuestieDB's: race masks and class keys

ns.GROUPS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
	"Finger", "Trinket", "Weapon", "Off hand", "Ranged" }
local GROUP_OF = {
	INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands",
	INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger",
	INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "Weapon", INVTYPE_2HWEAPON = "Weapon",
	INVTYPE_WEAPONMAINHAND = "Weapon", INVTYPE_WEAPONOFFHAND = "Off hand", INVTYPE_SHIELD = "Off hand",
	INVTYPE_HOLDABLE = "Off hand", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
	INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged",
}
-- Worn slot -> the groups it decides. A hand decides both hand groups: a
-- two-hander is weighed against main and off hand together.
local GROUPS_OF_SLOT = {
	[1] = { "Head" }, [2] = { "Neck" }, [3] = { "Shoulder" }, [15] = { "Back" }, [5] = { "Chest" },
	[9] = { "Wrist" }, [10] = { "Hands" }, [6] = { "Waist" }, [7] = { "Legs" }, [8] = { "Feet" },
	[11] = { "Finger" }, [12] = { "Finger" }, [13] = { "Trinket" }, [14] = { "Trinket" },
	[16] = { "Weapon", "Off hand" }, [17] = { "Weapon", "Off hand" }, [18] = { "Ranged" },
}
local WEAPON, ARMOR = 2, 4 -- item classes
local BIND_ON_PICKUP = 1 -- GetItemInfo's bindType
-- How far above your level counts as out of reach.
--
-- In mob levels, for a drop: a mob more than this over you does not count.
-- In QuestieDB (1.1.3) 1,852 of the 8,282 pieces of gear with a source
-- have no level requirement, and without this a level 18 character was
-- shown what a level 63 raid boss drops.
--
-- In item levels, for a vendor or a container selling or holding an item
-- with no level requirement: one more than this over your level does not
-- count. QuestieDB (1.1.3) lists
-- 144 armor items of item level 55 to 66, none with a level requirement,
-- as sold by four city NPCs; the one looked at in game, Virtuous Sandals,
-- is not sold at all but comes from a quest that needs level 58, which
-- QuestieDB does not link to it. What a vendor asks is not known here, so
-- item level stands in for it. Among QuestieDB's gear that does have a
-- level requirement, item level is at most 5 above it for four in five.
local ABOVE = 5
local SKULL = 9999 -- QuestieDB's level for 180 NPCs, bosses among them: taken as not known
-- Names (in lower case) of items that are not for players.
local JUNK = { "deprecated", "depricated", "^monster %- ", "%[ph%]", "%f[%a]dnt%f[%A]", "debug", "unused",
	"placeholder", "%f[%a]test%f[%A]", "%f[%a]testing%f[%A]", "^%d+ epic ", "^%d+ rare ", "^%d+ green " }

local db
local ready = false -- both addons this one leans on are there
-- Ignore.lua's list. Empty when that file did not load: a file new to an
-- addon may need the game restarted, not only /reload.
local ignore = ns.ignore or {}
local me = {} -- level, side ("A" or "H"), raceBit, classBit

ns.results = {} -- group -> { entry, ... }, unsorted; made by ns.Collect
ns.phase = "idle" -- "scan", "load", "done"
ns.progress = { at = 0, of = 0, silent = 0 }

function ns.Changed() end -- the window's, once it is made

local function Now()
	return debugprofilestop()
end

-- Not bit.band: the race masks go past 32 bits.
local function HasBit(mask, bit)
	return math.floor(mask / bit) % 2 == 1
end

-- Where from --------------------------------------------------------------

local function QuestDone(quest)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted(quest)
	end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(quest) or false
end

-- A quest you could still do now.
local function QuestOpen(quest)
	if not QuestDB.Exists(quest) or QuestDone(quest) then
		return false
	end
	if (QuestDB.requiredLevel(quest) or 0) > me.level then
		return false
	end
	local oldest = QuestDB.requiredMaxLevel(quest) or 0
	if oldest ~= 0 and oldest < me.level then
		return false
	end
	local races = QuestDB.requiredRaces(quest) or 0
	if races ~= 0 and me.raceBit and not HasBit(races, me.raceBit) then
		return false
	end
	local classes = QuestDB.requiredClasses(quest) or 0
	if classes ~= 0 and me.classBit and not HasBit(classes, me.classBit) then
		return false
	end
	return true
end

-- A mob you could kill, or see killed: not more than ABOVE levels over
-- you, going by the lowest level it comes in. One whose level is not
-- known (none given, or SKULL) counts: no telling.
local function MobInReach(npc)
	local low = NpcDB.minLevel(npc) or 0
	return low <= 0 or low >= SKULL or low <= me.level + ABOVE
end

-- The ways to get an item that are open to you, as { kind, id } with the
-- handiest first, and whether any way at all is known.
local function Ways(id)
	local ways, known = {}, false
	for _, npc in ipairs(ItemDB.vendors(id) or {}) do
		known = true
		local side = NpcDB.friendlyToFaction(npc)
		if not side or side:find(me.side, 1, true) then
			ways[#ways + 1] = { "vendor", npc }
		end
	end
	for _, quest in ipairs(ItemDB.questRewards(id) or {}) do
		known = true
		if QuestOpen(quest) then
			ways[#ways + 1] = { "quest", quest }
		end
	end
	if ns.crafted[id] then
		known = true
		ways[#ways + 1] = { "craft", ns.crafted[id] }
	end
	for _, npc in ipairs(ItemDB.npcDrops(id) or {}) do
		known = true
		if MobInReach(npc) then
			ways[#ways + 1] = { "drop", npc }
		end
	end
	for _, object in ipairs(ItemDB.objectDrops(id) or {}) do
		known = true
		ways[#ways + 1] = { "object", object }
	end
	for _, item in ipairs(ItemDB.itemDrops(id) or {}) do
		known = true
		ways[#ways + 1] = { "inside", item }
	end
	return ways, known
end

local RANK = { "elite", "rare elite", "boss", "rare" }

local function Place(area)
	local name = area and area > 0 and C_Map.GetAreaInfo(area) or nil
	return name and (", " .. name) or ""
end

local function Mob(npc)
	local low, high = NpcDB.minLevel(npc) or 0, NpcDB.maxLevel(npc) or 0
	local note = low > 0 and (high > low and (low .. "-" .. high) or tostring(low)) or nil
	local rank = RANK[NpcDB.rank(npc) or 0]
	if rank then
		note = note and (note .. " " .. rank) or rank
	end
	return (NpcDB.name(npc) or ("NPC " .. npc)) .. (note and (" (" .. note .. ")") or "") .. Place(NpcDB.zoneID(npc))
end

-- One way, in words.
function ns.Describe(way)
	local kind, id = way[1], way[2]
	if kind == "vendor" then
		return "Vendor: " .. (NpcDB.name(id) or ("NPC " .. id)) .. Place(NpcDB.zoneID(id))
	elseif kind == "quest" then
		local level = QuestDB.questLevel(id) or 0
		return "Quest: " .. (QuestDB.name(id) or ("quest " .. id)) .. (level > 0 and (" [" .. level .. "]") or "")
			.. Place(QuestDB.zoneOrSort(id))
	elseif kind == "craft" then
		return "Crafted: " .. (ns.professions[id] or "a profession")
	elseif kind == "drop" then
		return "Drop: " .. Mob(id)
	elseif kind == "object" then
		return "Found in: " .. (ObjectDB.name(id) or ("object " .. id)) .. Place(ObjectDB.zoneID(id))
	end
	return "Found in: " .. (ItemDB.name(id) or ("item " .. id))
end

-- The handiest way, and how many others there are.
function ns.Headline(entry)
	local ways = entry.ways
	if #ways == 0 then
		return "Source unknown"
	end
	return ns.Describe(ways[1]) .. (#ways > 1 and (" +" .. (#ways - 1)) or "")
end

-- What is kept ----------------------------------------------------------------

local candidates = {} -- item ID -> its ways: the gear in reach, from the scan
local order = {} -- the candidates, in the order they are gone through
local skip = {} -- item ID -> true: never a candidate (not gear, not in the game, junk)
local info = {} -- item ID -> what the game said: { name, link, quality, icon, group, bop, level, needs }; false: no gear after all
local verdict = {} -- item ID -> { entry or false, unusable, and the three counts below as they were }
local silent, silentCount = {}, 0 -- item ID -> true: the game never answered for it

-- A verdict holds while these stand as they were when it was given.
local epoch = 0 -- weights, role, level
local slotEpoch = {} -- group -> what is worn there
local skillEpoch = 0 -- skills; only a verdict of "cannot use" depends on it
local worn = {} -- slot -> the link last seen there, false for none

local dirty = true -- ns.results is behind the verdicts

local function Fresh(v, group)
	return v.epoch == epoch and v.slotEpoch == (slotEpoch[group] or 0)
		and (not v.unusable or v.skillEpoch == skillEpoch)
end

-- Notes what is worn; true when a gear slot holds something else than last time.
local function LookAtGear()
	local changed = false
	for slot, groups in pairs(GROUPS_OF_SLOT) do
		local link = GetInventoryItemLink("player", slot) or false
		if worn[slot] ~= link then
			worn[slot] = link
			for _, group in ipairs(groups) do
				slotEpoch[group] = (slotEpoch[group] or 0) + 1
			end
			changed = true
		end
	end
	return changed
end

-- Does the game answer for everything you wear? Asking is also what makes
-- it load what it has not.
local function WornAnswers()
	local all = true
	for slot in pairs(GROUPS_OF_SLOT) do
		local link = worn[slot]
		if link then
			local ok, stats = pcall(C_Item.GetItemStats, link)
			if not ok or type(stats) ~= "table" then
				all = false
			end
		end
	end
	return all
end

-- The item has loaded: what the game says it is.
local function Learn(id)
	local name, link, quality, level, needs, _, _, _, equipLoc, icon, _, _, _, bind = C_Item.GetItemInfo(id)
	local group = GROUP_OF[equipLoc or ""]
	info[id] = link and group and {
		name = name or ("item " .. id), link = link, quality = quality, icon = icon, group = group,
		bop = bind == BIND_ON_PICKUP, level = level or 0, needs = needs or 0,
	} or false
	return info[id]
end

-- Is the profession (a skill line) yours? Asked once, until your skills change.
local mine = {}
local function Mine(line)
	if mine[line] == nil then
		local skills, rank = C_SkillInfo, 0
		local function look(found)
			if type(found) == "table" and not found.isHeader and type(found.rank) == "number"
				and (found.skillID == line or found.parentSkillLineID == line) then
				rank = math.max(rank, found.rank)
			end
		end
		if not (skills and skills.GetNumSkillLines and skills.GetSkillLineInfo) then
			return true -- no telling: the recipe stays
		end
		if skills.GetSkillLineInfoByID then
			look(skills.GetSkillLineInfoByID(line)) -- also found under a folded header
		end
		for i = 1, skills.GetNumSkillLines() do
			look(skills.GetSkillLineInfo(i))
		end
		mine[line] = rank > 0
	end
	return mine[line]
end

-- The candidate's ways, less those that are no use to you:
-- - a recipe for an item that binds when picked up, unless the profession
--   is yours: it cannot be made for you by someone else;
-- - a vendor or a container for an item with no level requirement (none,
--   or 1) whose item level is more than ABOVE over your level.
local function OpenWays(id)
	local ways, known = candidates[id], info[id]
	if not known then
		return ways
	end
	local far = known.needs <= 1 and known.level > me.level + ABOVE
	if not (known.bop or far) then
		return ways
	end
	local open, cut = {}, false
	for _, way in ipairs(ways) do
		local kind = way[1]
		if kind == "craft" and known.bop and not Mine(way[2]) then
			cut = true
		elseif far and (kind == "vendor" or kind == "inside") then
			cut = true
		else
			open[#open + 1] = way
		end
	end
	return cut and open or ways
end

-- Is it an upgrade? Asked of UpgradeArrow only when the last answer no longer holds.
local function Judge(id)
	local known, old = info[id], verdict[id]
	if old and Fresh(old, known.group) then
		return
	end
	local result = UpgradeArrow.Evaluate(known.link)
	if not result then
		return -- not cached after all; the next pass asks again
	end
	local entry = false
	if result.upgrade then
		local score = result.score or 0
		entry = {
			id = id, name = known.name, link = known.link, quality = known.quality, icon = known.icon,
			group = known.group, empty = result.empty,
			gain = result.empty and score or score - (result.against or 0),
		}
	end
	verdict[id] = {
		entry = entry, unusable = result.score == nil,
		epoch = epoch, slotEpoch = slotEpoch[known.group] or 0, skillEpoch = skillEpoch,
	}
	if entry or (old and old.entry) then
		dirty = true
	end
end

-- Brings ns.results up to the verdicts.
function ns.Collect()
	if not dirty then
		return
	end
	dirty = false
	local results = {}
	for _, id in ipairs(order) do
		local entry = verdict[id] and verdict[id].entry
		local ways = entry and OpenWays(id)
		-- With its only ways closed it is out of reach, not of unknown source.
		if entry and (#ways > 0 or #candidates[id] == 0) then
			entry.ways = ways
			local list = results[entry.group]
			if not list then
				list = {}
				results[entry.group] = list
			end
			list[#list + 1] = entry
		end
	end
	ns.results = results
end

-- The search ---------------------------------------------------------------

local ticker
local ids, index -- QuestieDB's item list and where the scan is in it
local at, waiting, waitingCount -- the pass: next in order, asked -> when
local warmUntil -- the pass waits for what you wear until then, at most
local needScan, needPass = true, true
local levelSeen = 0 -- from PLAYER_LEVEL_UP, which can come before UnitLevel follows

local function Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Junk(name)
	name = name:lower()
	for _, pattern in ipairs(JUNK) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

-- Gear at all, and not on the ignore list? That does not change, so it is
-- asked once per item.
local function Gear(id)
	if ignore[id] then
		return false
	end
	-- QuestieDB lists items the game does not have; those never load.
	if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id) then
		return false
	end
	local _, _, _, equipLoc, _, class = C_Item.GetItemInfoInstant(id)
	if class == nil then
		class, equipLoc = ItemDB.class(id), nil -- the slot comes with the item
	end
	if class ~= WEAPON and class ~= ARMOR then
		return false
	end
	if equipLoc and not GROUP_OF[equipLoc] then
		return false
	end
	return not Junk(ItemDB.name(id) or "")
end

-- Gear, wearable at your level, with a way to get it.
local function Consider(id)
	if skip[id] then
		return
	end
	if skip[id] == nil then
		skip[id] = not Gear(id)
		if skip[id] then
			return
		end
	end
	if (ItemDB.requiredLevel(id) or 0) > me.level then
		return
	end
	local ways, known = Ways(id)
	if #ways == 0 and (known or not db.unknown) then
		return
	end
	candidates[id] = ways
	order[#order + 1] = id
end

local function Loaded(id)
	return C_Item.GetItemInfo(id) ~= nil
end

local function BeginPass()
	ns.phase, at, waiting, waitingCount = "load", 1, {}, 0
	warmUntil = GetTime() + WARM_UP
	ns.progress = { at = 0, of = #order, silent = silentCount }
end

local function Tick()
	local stop = Now() + BUDGET
	if ns.phase == "scan" then
		while Now() < stop do
			local id = ids[index]
			if not id then
				dirty = true
				BeginPass()
				break
			end
			index = index + 1
			Consider(id)
		end
		if ns.phase == "scan" then
			ns.progress.at = index - 1
		end
	elseif ns.phase == "load" then
		local time = GetTime()
		if warmUntil then
			if not WornAnswers() and time < warmUntil then
				return
			end
			warmUntil = nil
		end
		for id, since in pairs(waiting) do
			local loaded = Loaded(id)
			if loaded or time - since > GIVE_UP then
				waiting[id] = nil
				waitingCount = waitingCount - 1
				if not loaded then
					silent[id] = true
					silentCount = silentCount + 1
				elseif Learn(id) then
					Judge(id)
				end
			end
		end
		local asked = 0
		while at <= #order and asked < ASK_PER_TICK and waitingCount < WAITING_MAX and Now() < stop do
			local id = order[at]
			at = at + 1
			local known = info[id]
			if known == nil and not silent[id] then
				if Loaded(id) then
					known = Learn(id)
				else
					asked = asked + 1
					if C_Item.RequestLoadItemDataByID then
						C_Item.RequestLoadItemDataByID(id)
					end
					waiting[id] = time
					waitingCount = waitingCount + 1
				end
			end
			if known then
				Judge(id)
			end
		end
		ns.progress.at, ns.progress.silent = at - 1 - waitingCount, silentCount
		if at > #order and waitingCount == 0 then
			ns.phase = "done"
			Stop()
		end
	end
	ns.Changed()
end

-- Brings the list up to date, when something changed since it was made.
function ns.Run()
	if not ready then
		return
	end
	if LookAtGear() then
		needPass = true -- a change no event told of
	end
	if not (needScan or needPass) then
		return
	end
	if ns.phase == "scan" and not needScan then
		needPass = false -- the scan under way ends in a pass of its own
		return
	end
	Stop()
	if needScan then
		local _, class = UnitClass("player")
		local _, _, race = UnitRace("player")
		me.level = math.max(UnitLevel("player"), levelSeen)
		me.side = UnitFactionGroup("player") == "Alliance" and "A" or "H"
		me.raceBit = LibQuestieDB.Enum.raceMaskById[race]
		me.classBit = LibQuestieDB.Enum.classKeys[class]
		candidates, order = {}, {}
		ids, index = ItemDB.GetAllIds(), 1
		ns.phase = "scan"
		ns.progress = { at = 0, of = #ids, silent = silentCount }
	else
		BeginPass()
	end
	needScan, needPass = false, false
	-- The work starts on the next tick, not here: this can be the middle of
	-- a gear change.
	ticker = C_Timer.NewTicker(TICK, Tick)
	ns.Changed()
end

-- Something changed: the answers (a pass), or also what is in reach (a
-- scan). The work waits until the window is looked at.
function ns.Stale(scan)
	needScan = needScan or scan or false
	needPass = true
	if ns.Shown and ns.Shown() then
		ns.Run()
	end
end

-- UpgradeArrow says something changed, and what kind of thing.
local function ArrowChanged(reason)
	if reason == "names" or reason == "others" then
		ns.Changed() -- a spec's name or role, or another spec's set: the scores are as they were
		return
	end
	local stale = LookAtGear()
	if reason == "skills" then
		skillEpoch = skillEpoch + 1
		mine, dirty = {}, true -- a profession may have come or gone
		stale = true
	elseif reason ~= "gear" then
		epoch = epoch + 1 -- weights, role, level, or a reason not known here
		stale = true
	end
	if stale then
		ns.Stale(false)
	end
end

-- A quest handed in gives its rewards no more.
local function QuestGone(quest)
	local kept, changed = {}, false
	for _, id in ipairs(order) do
		local ways, had = candidates[id], false
		for i = #ways, 1, -1 do
			if ways[i][1] == "quest" and ways[i][2] == quest then
				table.remove(ways, i)
				had = true
			end
		end
		if had and #ways == 0 then
			candidates[id] = nil
		else
			kept[#kept + 1] = id
		end
		changed = changed or had
	end
	if changed then
		order, dirty = kept, true
		ns.Stale(false)
		ns.Changed()
	end
end

function ns.ShowUnknown(show)
	db.unknown = show and true or false
	ns.Stale(true)
end

function ns.Ready()
	return ready
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		-- The window's settings, in the addon's one saved table; Arrow.lua
		-- keeps the specs beside them.
		ForeverUpgradesDB = type(ForeverUpgradesDB) == "table" and ForeverUpgradesDB or {}
		ForeverUpgradesDB.window = type(ForeverUpgradesDB.window) == "table" and ForeverUpgradesDB.window or {}
		db = ForeverUpgradesDB.window
		ns.db = db
		-- Without QuestieDB the arrows still work; the window says what it needs.
		if not (LibQuestieDB and ItemDB and QuestDB and NpcDB and ObjectDB) then
			return
		end
		local ok, message = LibQuestieDB.RequireContract(CONTRACT)
		if not ok then
			print("|cff40c040ForeverUpgrades|r: " .. tostring(message))
			return
		end
		ready = true
		UpgradeArrow.OnChange(ArrowChanged)
		self:RegisterEvent("PLAYER_LEVEL_UP")
		self:RegisterEvent("QUEST_TURNED_IN")
	elseif event == "PLAYER_LEVEL_UP" then
		-- A level opens items and quests, and can change every answer.
		levelSeen = tonumber(name) or 0
		epoch = epoch + 1
		ns.Stale(true)
	else
		QuestGone(tonumber(name) or 0)
	end
end)
