-- ForeverUpgrades, the arrow: Pawn lite. An item's stats (C_Item.GetItemStats) are summed
-- with your class's weights below and compared with what you wear in the
-- slot it goes in; a higher score is an upgrade and gets a green arrow:
--
-- - in Baganator's bags and bank, as an icon corner widget (top right);
-- - on LootRolls bars (it asks UpgradeArrow.IsUpgrade);
-- - on quest reward and choice items, in the quest frame and quest log;
-- - on a vendor's items, for sale and on the buyback tab;
-- - in the tooltip, one line: "Upgrade +1.5 (spec)", the points it scores
--   above what you wear (as the /upgrades list), or "Upgrade, empty slot
--   (spec)"; with Alt held also both scores and the stats behind
--   them, and "Not an upgrade" for one that is not.
--
-- What it is compared with is Blizzard's choice, as in its comparison
-- tooltips (C_TooltipComparison.GetItemComparisonInfo): rings, trinkets
-- and dual-wielded one-handers against the weaker of the two you wear, a
-- two-hander against main and off hand together. An empty slot makes
-- anything usable an upgrade. When the spec has one of the character's
-- equipment sets attached (in the /upgrades window, or /upgradearrow set
-- <name>), items are compared with what that set puts in the slot instead,
-- in the same way; a slot the set ignores is what you wear there. Only items you
-- can use now count: your class and skills (C_PlayerInfo.CanUseItem) and
-- your level.
--
-- Items are scored with the weights of a spec, in points per stat
-- (Strength 1 for a damage warrior). A spec is a named set of weights
-- that belongs to one role (tank, healer, damage); a role can have
-- several, as a shaman's damage has Elemental and Enhancement. Specs are
-- kept per class and shared by all your characters of that class; each
-- class starts with its own, a rough leveling guess, and you can add,
-- copy, rename and delete them (in the /upgrades window).
--
-- Which spec: the one picked by hand, else, automatically, the spec of
-- the role you were given in your group, else of the one ticked in the
-- group finder, else of damage. A role's spec is the one last picked by
-- hand for it on this character, else its first. Talents are not looked
-- at: early points say little about where a character is going.
-- /upgradearrow shows the spec and its weights; /upgradearrow spec
-- <name>|auto picks one; /upgradearrow <stat> <weight> changes one weight
-- of the spec scored for, /upgradearrow reset puts them back.
--
-- A weapon counts by its damage per second and stats only, not by its
-- speed. That is on purpose, to keep the score simple, and it is a known
-- gap for hunters: Aimed Shot and Multi-Shot use the bow's damage roll,
-- so a slower bow hits harder with them (measured in game 2026-11-20:
-- about 6 more per Multi-Shot from a 2.30 bow than from a 1.80 one),
-- while the faster bow's higher dps only shows in Auto Shot. Between
-- bows of similar level this is a point or two, more when Multi-Shot
-- hits several targets.

local ADDON = ...
local IsSecret = issecretvalue or function() return false end

-- Short names for GetItemStats keys.
local STATS = {
	str = "ITEM_MOD_STRENGTH_SHORT",
	agi = "ITEM_MOD_AGILITY_SHORT",
	sta = "ITEM_MOD_STAMINA_SHORT",
	int = "ITEM_MOD_INTELLECT_SHORT",
	spi = "ITEM_MOD_SPIRIT_SHORT",
	armor = "RESISTANCE0_NAME",
	ap = "ITEM_MOD_ATTACK_POWER_SHORT",
	rap = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
	-- "Increases damage and healing done by magical spells" is spell power
	-- and counts as both sp and heal: Witherbite Bracers' +5 is only
	-- ITEM_MOD_SPELL_POWER_SHORT = 5 (seen in game 2026-11-27). Damage only
	-- or healing only counts once. A healer weighs heal and not sp, a damage
	-- caster the other way round.
	sp = { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT" },
	heal = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT" },
	mp5 = "ITEM_MOD_MANA_REGENERATION_SHORT",
	hit = "ITEM_MOD_HIT_RATING_SHORT",
	crit = "ITEM_MOD_CRIT_RATING_SHORT",
	spellhit = "ITEM_MOD_HIT_SPELL_RATING_SHORT",
	spellcrit = "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
	defense = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
	dodge = "ITEM_MOD_DODGE_RATING_SHORT",
	parry = "ITEM_MOD_PARRY_RATING_SHORT",
	block = "ITEM_MOD_BLOCK_RATING_SHORT",
	dps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", -- melee weapons
	rdps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", -- the ranged slot
}
local ORDER = { "str", "agi", "sta", "int", "spi", "armor", "ap", "rap", "sp", "heal", "mp5", "hit", "crit",
	"spellhit", "spellcrit", "defense", "dodge", "parry", "block", "dps", "rdps" }

-- Each class's own specs, in the order they are listed. A class can fill
-- the roles its own specs have, and no others. The id is kept in saved
-- settings: never change one. Hit, crit, dodge, parry and block are per point on the item: 10 hit,
-- 14 crit, 12 dodge, 15 parry or 5 block is 1% at every level
-- (gametables/combatratings.txt, build 1.60.1.70959), so hit 1 makes 1%
-- hit worth 10 Agility. Items carry no separate spell hit or spell crit;
-- casters weigh hit and crit as well.
local CASTER = { int = 0.6, spi = 0.4, sta = 0.4, armor = 0.005, sp = 1.2, heal = 0, mp5 = 1.2, hit = 0.8, crit = 0.6, dps = 0, rdps = 0.2 }
local HEALER = { int = 1, spi = 0.4, sta = 0.3, armor = 0.005, heal = 1, sp = 0, mp5 = 2, crit = 0.6, dps = 0, rdps = 0 }
local PLATE_TANK = { sta = 1, str = 0.5, agi = 0.6, armor = 0.05, ap = 0.2, hit = 0.4, defense = 1.5, dodge = 1, parry = 0.7, block = 0.8, dps = 1, rdps = 0.3 }
local function Own(id, name, role, weights)
	return { id = id, name = name, role = role, weights = weights }
end
local SPECS = {
	WARRIOR = {
		Own("damage", "Arms/Fury", "DAMAGER", { str = 1, agi = 0.6, sta = 0.5, armor = 0.02, ap = 0.5, hit = 1, crit = 0.7, dps = 3.5, rdps = 0.5 }),
		Own("protection", "Protection", "TANK", PLATE_TANK),
	},
	PALADIN = {
		Own("retribution", "Retribution", "DAMAGER", { str = 1, agi = 0.5, sta = 0.4, int = 0.3, spi = 0.1, armor = 0.02, ap = 0.5, sp = 0.3, mp5 = 0.5, hit = 0.9, crit = 0.6, dps = 3, rdps = 0 }),
		Own("protection", "Protection", "TANK", { sta = 1, str = 0.4, agi = 0.4, int = 0.2, armor = 0.05, sp = 0.5, defense = 1.5, dodge = 1, parry = 0.7, block = 0.8, hit = 0.4, dps = 0.5, rdps = 0 }),
		Own("holy", "Holy", "HEALER", { int = 1, spi = 0.2, sta = 0.3, armor = 0.005, heal = 1, sp = 0, mp5 = 2, crit = 0.7, dps = 0, rdps = 0 }),
	},
	ROGUE = { Own("damage", "Damage", "DAMAGER", { str = 0.5, agi = 1, sta = 0.3, armor = 0.01, ap = 0.5, hit = 1.2, crit = 0.7, dodge = 0.3, dps = 3, rdps = 0.5 }) },
	HUNTER = { Own("damage", "Damage", "DAMAGER", { agi = 1, int = 0.3, sta = 0.4, spi = 0.1, armor = 0.01, ap = 0.2, rap = 0.5, hit = 1, crit = 0.7, dps = 0.8, rdps = 3.5 }) },
	SHAMAN = {
		Own("elemental", "Elemental", "DAMAGER", { int = 0.5, spi = 0.2, sta = 0.4, armor = 0.005, sp = 1.2, heal = 0, mp5 = 1, hit = 0.8, crit = 0.6, dps = 0, rdps = 0 }),
		Own("enhancement", "Enhancement", "DAMAGER", { str = 1, agi = 0.6, sta = 0.4, int = 0.2, spi = 0.1, armor = 0.01, ap = 0.5, sp = 0, mp5 = 0.3, hit = 1, crit = 0.7, dps = 3, rdps = 0 }),
		Own("restoration", "Restoration", "HEALER", HEALER),
	},
	DRUID = {
		Own("balance", "Balance", "DAMAGER", { int = 0.6, spi = 0.4, sta = 0.4, armor = 0.005, sp = 1.2, heal = 0, mp5 = 1, hit = 0.8, crit = 0.6, dps = 0, rdps = 0 }),
		Own("cat", "Cat", "DAMAGER", { str = 1, agi = 1, sta = 0.4, int = 0.3, spi = 0.1, armor = 0.02, ap = 0.6, hit = 1, crit = 0.7, dps = 0, rdps = 0 }),
		Own("bear", "Bear", "TANK", { sta = 1, agi = 0.7, str = 0.5, armor = 0.08, ap = 0.2, defense = 1.5, dodge = 1, hit = 0.4, dps = 0, rdps = 0 }),
		Own("restoration", "Restoration", "HEALER", { int = 0.8, spi = 0.5, sta = 0.3, armor = 0.005, heal = 1, sp = 0, mp5 = 2, crit = 0.6, dps = 0, rdps = 0 }),
	},
	MAGE = { Own("damage", "Damage", "DAMAGER", CASTER) },
	PRIEST = {
		Own("shadow", "Shadow", "DAMAGER", { int = 0.5, spi = 0.5, sta = 0.4, armor = 0.005, sp = 1.2, mp5 = 1, hit = 0.8, crit = 0.4, dps = 0, rdps = 0.2 }),
		Own("holy", "Holy", "HEALER", { int = 0.8, spi = 0.7, sta = 0.3, armor = 0.005, heal = 1, sp = 0, mp5 = 2, crit = 0.6, dps = 0, rdps = 0.1 }),
	},
	WARLOCK = { Own("damage", "Damage", "DAMAGER", { int = 0.4, spi = 0.3, sta = 0.6, armor = 0.005, sp = 1.2, mp5 = 0.8, hit = 0.8, crit = 0.5, dps = 0, rdps = 0.2 }) },
}
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local ROLE_ARG = { tank = "TANK", healer = "HEALER", heal = "HEALER", damage = "DAMAGER", dps = "DAMAGER", damager = "DAMAGER" }
local NAME_MAX = 24 -- letters in a spec's name

-- Which equipped item an item is compared with comes from Blizzard
-- (C_TooltipComparison.GetItemComparisonInfo), as in its own comparison
-- tooltips. These are only what that does not say:
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true }
local NOT_GEAR = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_AMMO = true, INVTYPE_BAG = true,
	INVTYPE_QUIVER = true, INVTYPE_NON_EQUIP_IGNORE = true, [""] = true }
-- Slots that come in pairs, where an empty second one beats anything.
local PAIRED = { INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }

local db -- this character's settings: fixed (a spec id), active (role -> spec id)
local store -- this class's specs, shared by its characters: see LoadSpecs
local cache = {} -- spec id -> link -> { upgrade, score, against, againstLinks, empty, set }

local function Own()
	local _, class = UnitClass("player")
	return SPECS[class] or { Own("damage", "Damage", "DAMAGER", CASTER) }
end

local function OwnSpec(id)
	for _, spec in ipairs(Own()) do
		if spec.id == id then
			return spec
		end
	end
end

-- The roles the class can fill: role -> true.
local function ClassRoles()
	local roles = {}
	for _, spec in ipairs(Own()) do
		roles[spec.role] = true
	end
	return roles
end

-- The class's specs in the order they are listed: by role (tank, healer,
-- damage), then as they were made.
local function Ordered()
	local list = {}
	for _, forRole in ipairs(ROLE_ORDER) do
		for _, id in ipairs(store.order) do
			if store.specs[id].role == forRole then
				list[#list + 1] = id
			end
		end
	end
	return list
end

local function FirstOf(forRole)
	for _, id in ipairs(store.order) do
		if store.specs[id].role == forRole then
			return id
		end
	end
end

local function CountOf(forRole)
	local count = 0
	for _, id in ipairs(store.order) do
		if store.specs[id].role == forRole then
			count = count + 1
		end
	end
	return count
end

-- The spec a role is scored with on this character: the one last picked
-- for it, else its first.
local function SpecOf(forRole)
	local id = db.active and db.active[forRole]
	if id and store.specs[id] and store.specs[id].role == forRole then
		return id
	end
	return FirstOf(forRole)
end

-- The role when it is not picked by hand: the role you were given in your
-- group, else the one role ticked in the group finder (tank before healer
-- before damage when several are), else damage.
local function CurrentRole()
	local roles = ClassRoles()
	local ok, assigned = pcall(UnitGroupRolesAssigned, "player")
	if ok and type(assigned) == "string" and not IsSecret(assigned) and roles[assigned] then
		return assigned, "your group role"
	end
	local finder = C_LFGListRoles and C_LFGListRoles.GetRoles
	local okRoles, picked = false, nil
	if finder then
		okRoles, picked = pcall(finder)
	end
	if okRoles and type(picked) == "table" then
		local flags = { TANK = picked.tank, HEALER = picked.healer, DAMAGER = picked.dps }
		for _, role in ipairs(ROLE_ORDER) do
			if flags[role] and roles[role] then
				return role, "ticked in the group finder"
			end
		end
	end
	if roles.DAMAGER then
		return "DAMAGER", "default"
	end
	return next(roles), "default"
end

-- The spec to score with, and why: picked by hand, else its role's.
local function CurrentSpec()
	local id = db.fixed
	if id and store.specs[id] then
		return id, "picked by hand"
	end
	local forRole, source = CurrentRole()
	return SpecOf(forRole), source
end

-- The spec scored with (its id), its role, and why it is that one.
local spec, role, roleSource

-- What a spec's weights start from: the class's own spec it was made from.
local function Base(id)
	local own = store.specs[id] and OwnSpec(store.specs[id].base)
	return own and own.weights or {}
end

local function WeightsOf(id)
	local weights = {}
	for key, value in pairs(Base(id)) do
		weights[key] = value
	end
	for key, value in pairs(store.specs[id].weights) do
		weights[key] = value
	end
	return weights
end

local function Weights()
	spec, roleSource = CurrentSpec()
	role = store.specs[spec].role
	return WeightsOf(spec)
end
local weights

-- The saved specs, made sound whatever is in the file: every one listed
-- once, each with a role the class can fill, a base that is one of the
-- class's own, and a weight table; and every role with at least one. A
-- spec of the class's own that was never there yet (an older file, or a
-- spec added to the addon since) is added once; one you deleted stays
-- gone, unless its role would have none.
local function LoadSpecs(all, class)
	all.classes = type(all.classes) == "table" and all.classes or {}
	local saved = type(all.classes[class]) == "table" and all.classes[class] or {}
	all.classes[class] = saved
	saved.specs = type(saved.specs) == "table" and saved.specs or {}
	saved.seen = type(saved.seen) == "table" and saved.seen or {}
	saved.made = tonumber(saved.made) or 0
	local roles = ClassRoles()
	local order, listed = {}, {}
	for _, id in ipairs(type(saved.order) == "table" and saved.order or {}) do
		if type(saved.specs[id]) == "table" and not listed[id] then
			order[#order + 1], listed[id] = id, true
		end
	end
	for id, value in pairs(saved.specs) do
		if type(value) ~= "table" then
			saved.specs[id] = nil
		elseif not listed[id] then
			order[#order + 1], listed[id] = id, true
		end
	end
	saved.order = order
	-- One of the class's own, under its own id unless that is taken.
	local function Add(own)
		local id = own.id
		if saved.specs[id] then
			saved.made = saved.made + 1
			id = "my" .. saved.made
		end
		saved.specs[id] = { name = own.name, role = own.role, base = own.id, weights = {} }
		order[#order + 1] = id
	end
	for _, own in ipairs(Own()) do
		if not saved.seen[own.id] and not saved.specs[own.id] then
			Add(own)
		end
		saved.seen[own.id] = true
	end
	for i = #order, 1, -1 do
		local id = order[i]
		local value = saved.specs[id]
		if type(value.name) ~= "string" or value.name == "" then
			value.name = id
		end
		if not OwnSpec(value.base) then
			value.base = OwnSpec(id) and id or nil
		end
		if not roles[value.role] then
			value.role = value.base and OwnSpec(value.base).role or nil
		end
		if not value.base and value.role then
			for _, own in ipairs(Own()) do
				if own.role == value.role then
					value.base = own.id
					break
				end
			end
		end
		if not (value.base and value.role) then
			saved.specs[id] = nil
			table.remove(order, i)
		elseif type(value.weights) ~= "table" then
			value.weights = {}
		end
	end
	store = saved
	for _, own in ipairs(Own()) do
		if not FirstOf(own.role) then
			Add(own)
		end
	end
end

-- A new spec, a copy of spec from (its role, base and weights), last in
-- the list. No check of the name.
local function MakeSpec(from, name)
	local source = store.specs[from]
	store.made = store.made + 1
	local id = "my" .. store.made
	local copy = {}
	for key, value in pairs(source.weights) do
		copy[key] = value
	end
	store.specs[id] = { name = name, role = source.role, base = source.base, weights = copy }
	store.order[#store.order + 1] = id
	return id
end

-- Score of an item link, and its { stat, amount, points } parts.
local KNOWN = {} -- GetItemStats key -> the short names it counts as
for short, keys in pairs(STATS) do
	if short ~= "rdps" then
		for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
			KNOWN[key] = KNOWN[key] or {}
			table.insert(KNOWN[key], short)
		end
	end
end

-- Score of an item link, and its { stat, amount, points } parts; stats
-- without a weight come last with the game's own name for them.
local function Score(link, slot, w)
	w = w or weights
	local ok, stats = pcall(C_Item.GetItemStats, link)
	if not ok or type(stats) ~= "table" then
		return 0, {}
	end
	local amounts, unknown = {}, {}
	for key, value in pairs(stats) do
		if type(value) == "number" and not IsSecret(value) and value ~= 0 then
			local shorts = KNOWN[key]
			if shorts then
				for _, short in ipairs(shorts) do
					if short == "dps" and slot == 18 then
						short = "rdps"
					end
					amounts[short] = (amounts[short] or 0) + value
				end
			else
				unknown[#unknown + 1] = { _G[key] or key, value, 0 }
			end
		end
	end
	local total, parts = 0, {}
	for _, short in ipairs(ORDER) do
		local value = amounts[short]
		if value then
			local points = value * (w[short] or 0)
			total = total + points
			parts[#parts + 1] = { short, value, points }
		end
	end
	table.sort(unknown, function(x, y)
		return x[1] < y[1]
	end)
	for _, part in ipairs(unknown) do
		parts[#parts + 1] = part
	end
	return total, parts
end

local function Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

-- A TooltipComparisonItem's link.
local function LinkOf(item)
	if type(item) ~= "table" then
		return nil
	end
	local link = Plain(item.hyperlink)
	if not link and item.guid and C_Item.GetItemLinkByGUID then
		local ok, found = pcall(C_Item.GetItemLinkByGUID, item.guid)
		link = ok and Plain(found) or nil
	end
	return type(link) == "string" and link or nil
end

-- True when one of the slots the item could go in is empty.
local function EmptySlot(equipLoc)
	local slots = PAIRED[equipLoc]
	if equipLoc == "INVTYPE_WEAPON" and CanDualWield and CanDualWield() then
		local main = GetInventoryItemLink("player", 16)
		if not (main and select(9, C_Item.GetItemInfo(main)) == "INVTYPE_2HWEAPON") then
			slots = { 16, 17 }
		end
	end
	for _, slot in ipairs(slots or {}) do
		if not GetInventoryItemLink("player", slot) then
			return true
		end
	end
	return false
end

-- Equipment sets -----------------------------------------------------------
-- A spec can have one of this character's equipment sets (the game's
-- equipment manager, C_EquipmentSet) attached: items are then compared
-- with what that set puts in the slot, not with what you wear, so gear for
-- another spec is not measured against the gear you happen to wear.

-- The slots an item can go in.
local SLOTS = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 } }

-- A set's name, or nil when this character has no set of that id.
local function SetName(setID)
	if not (setID and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo) then
		return nil
	end
	local ok, name = pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
	return ok and type(name) == "string" and name or nil
end

-- The set attached to a spec on this character, while it still exists.
local function SetOf(id)
	local setID = db.sets and db.sets[id]
	return SetName(setID) and setID or nil
end

-- An item's link from its id: as you wear it or carry it in your bags,
-- with its random suffix ("of the Eagle"); else as it was last seen there
-- (the snapshot, db.setItemLinks: item id -> link, kept for the items in your
-- sets, so one put in the bank keeps its suffix); else the plain item.
local function FindLink(itemID)
	local function Seen(link)
		db.setItemLinks[itemID] = link
		return link
	end
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		if link and C_Item.GetItemInfoInstant(link) == itemID then
			return Seen(link)
		end
	end
	local numSlots = C_Container and C_Container.GetContainerNumSlots
	local linkAt = C_Container and C_Container.GetContainerItemLink
	if numSlots and linkAt then
		for bag = 0, NUM_BAG_SLOTS or 4 do
			for slot = 1, numSlots(bag) or 0 do
				local link = linkAt(bag, slot)
				if link and C_Item.GetItemInfoInstant(link) == itemID then
					return Seen(link)
				end
			end
		end
	end
	return db.setItemLinks[itemID] or ("item:" .. itemID)
end

-- Forgets the snapshot of items no longer in any set.
local function PruneSetLinks()
	local inSets = {}
	local ok, ids = false, nil
	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
		ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
	end
	for _, setID in ipairs(ok and type(ids) == "table" and ids or {}) do
		local okItems, items = pcall(C_EquipmentSet.GetItemIDs, setID)
		for _, itemID in pairs(okItems and type(items) == "table" and items or {}) do
			inSets[itemID] = true
		end
	end
	-- No sets at all may be sets not loaded yet: keep the snapshot.
	if not next(inSets) then
		return
	end
	for itemID in pairs(db.setItemLinks) do
		if not inSets[itemID] then
			db.setItemLinks[itemID] = nil
		end
	end
end

-- What a set puts in each slot: slot -> link, or false for nothing. A slot
-- the set leaves alone (ignored when it was saved) is what you wear there.
-- Worked out once per change, kept in setLinks.
local setLinks = {}
local function SetItems(setID)
	if setLinks[setID] then
		return setLinks[setID]
	end
	local ok, ids = pcall(C_EquipmentSet.GetItemIDs, setID)
	ids = ok and type(ids) == "table" and ids or {}
	local okIgnored, ignored = false, nil
	if C_EquipmentSet.GetIgnoredSlots then
		okIgnored, ignored = pcall(C_EquipmentSet.GetIgnoredSlots, setID)
	end
	ignored = okIgnored and type(ignored) == "table" and ignored or {}
	local items = {}
	for slot = 1, 19 do
		local itemID = ids[slot]
		if ignored[slot] or itemID == 1 then -- 1: the old API's "ignored"
			items[slot] = GetInventoryItemLink("player", slot) or false
		elseif type(itemID) == "number" and itemID > 1 then
			items[slot] = FindLink(itemID)
		else
			items[slot] = false
		end
	end
	setLinks[setID] = items
	return items
end

-- What an item is compared with in a set, as Evaluate does with what you
-- wear: returns the links, how they add up ("sum" for a two-hander against
-- main and off hand, else the weaker one), or nil for an empty slot.
local function SetAgainst(setID, equipLoc)
	local items = SetItems(setID)
	local slots = SLOTS[equipLoc]
	if not slots then
		return nil
	end
	local main = items[16]
	local mainIsTwoHand = main and select(9, C_Item.GetItemInfo(main)) == "INVTYPE_2HWEAPON"
	if equipLoc == "INVTYPE_2HWEAPON" then
		if not main and not items[17] then
			return nil
		end
		local links = {}
		links[#links + 1] = main or nil
		links[#links + 1] = items[17] or nil
		return links, "sum"
	elseif slots[1] == 17 and mainIsTwoHand then
		return { main } -- an off hand against the set's two-hander
	elseif equipLoc == "INVTYPE_WEAPON" and not mainIsTwoHand and CanDualWield and CanDualWield() then
		slots = { 16, 17 }
	end
	local links = {}
	for _, slot in ipairs(slots) do
		if not items[slot] then
			return nil
		end
		links[#links + 1] = items[slot]
	end
	return links, "weaker"
end

local function Usable(link, itemID, reqLevel)
	if (reqLevel or 0) > UnitLevel("player") then
		return false
	end
	if C_PlayerInfo and C_PlayerInfo.CanUseItem then
		local ok, usable = pcall(C_PlayerInfo.CanUseItem, itemID)
		if ok and usable == false then
			return false
		end
	end
	return true
end

-- Works out whether link is an upgrade for spec forSpec; nil while the
-- item is not cached.
local function EvaluateFor(link, forSpec)
	if type(link) ~= "string" or IsSecret(link) then
		return nil
	end
	cache[forSpec] = cache[forSpec] or {}
	local cache = cache[forSpec]
	local w = forSpec == spec and weights or WeightsOf(forSpec)
	local hit = cache[link]
	if hit then
		return hit
	end
	local _, _, _, _, reqLevel, _, _, _, equipLoc = C_Item.GetItemInfo(link)
	if not equipLoc then
		return nil
	end
	local result = { upgrade = false }
	local itemID = C_Item.GetItemInfoInstant(link)
	local equippable = not C_Item.IsEquippableItem or C_Item.IsEquippableItem(link)
	if not itemID or NOT_GEAR[equipLoc] or not equippable or not Usable(link, itemID, reqLevel) then
		cache[link] = result
		return result
	end
	local slot = RANGED[equipLoc] and 18 or nil
	local function ScoreOf(l)
		return (Score(l, slot, w))
	end
	result.score = ScoreOf(link)

	-- With an equipment set attached to the spec: what the set puts there.
	local setID = SetOf(forSpec)
	if setID then
		result.set = SetName(setID)
		local links, how = SetAgainst(setID, equipLoc)
		if not links then
			result.empty, result.against, result.againstLinks, result.upgrade = true, 0, {}, true
			cache[link] = result
			return result
		end
		local against, kept = 0, {}
		for i, l in ipairs(links) do
			if C_Item.GetItemInfoInstant(l) == itemID then
				cache[link] = result -- the set has one
				return result
			end
			local value = ScoreOf(l)
			if how == "sum" then
				against, kept[#kept + 1] = against + value, l
			elseif i == 1 or value < against then
				against, kept = value, { l }
			end
		end
		result.against, result.againstLinks = against, kept
		result.upgrade = result.score > 0 and result.score > against + 0.01
		cache[link] = result
		return result
	end

	-- What Blizzard compares it with.
	local info
	if C_TooltipComparison and C_TooltipComparison.GetItemComparisonInfo then
		local ok, found = pcall(C_TooltipComparison.GetItemComparisonInfo, { hyperlink = link })
		info = ok and type(found) == "table" and found or nil
	end
	local methods = Enum.TooltipComparisonMethod or {}
	local method = info and info.method
	local equipped = LinkOf(info and info.item)
	local others = {}
	for _, item in ipairs(info and info.additionalItems or {}) do
		others[#others + 1] = LinkOf(item)
	end

	local against, links = 0, {}
	if not equipped or EmptySlot(equipLoc) then
		result.empty = true
	elseif method == methods.WithBothHands then
		-- A two-hander against main and off hand together.
		against, links = ScoreOf(equipped), { equipped }
		if others[1] then
			against = against + ScoreOf(others[1])
			links[2] = others[1]
		end
	elseif method == methods.WithBagMainHandItem or method == methods.WithBagOffHandItem then
		-- A one-hander against the two-hander you hold (Blizzard pairs it
		-- with a bag item; that one is not counted here).
		against, links = ScoreOf(equipped), { equipped }
	else
		-- One item, and for rings, trinkets and dual wielding the other one
		-- too: the weaker of them is the one to replace.
		against, links = ScoreOf(equipped), { equipped }
		for _, other in ipairs(others) do
			local value = ScoreOf(other)
			if value < against then
				against, links = value, { other }
			end
		end
	end
	for _, l in ipairs(links) do
		if C_Item.GetItemInfoInstant(l) == itemID then
			cache[link] = result -- you already wear one
			return result
		end
	end
	result.against = against
	result.againstLinks = links
	-- Anything you can use beats an empty slot, even with no weighted stats.
	result.upgrade = result.empty or (result.score > 0 and result.score > against + 0.01)
	cache[link] = result
	return result
end

-- For the spec scored with.
local function Evaluate(link)
	return EvaluateFor(link, spec)
end

-- The other specs that have an equipment set attached on this character,
-- in the order they are listed: an item that is an upgrade for one of them
-- gets the arrow too, and a line in the tooltip. Worked out once per change.
local others
local function Others()
	if not others then
		others = {}
		for _, id in ipairs(Ordered()) do
			if id ~= spec and SetOf(id) then
				others[#others + 1] = id
			end
		end
	end
	return others
end

-- True when link is an upgrade for the spec scored with or for one of the
-- others; nil while the item is not cached. The arrows show this.
local function AnyUpgrade(link)
	local result = Evaluate(link)
	if not result then
		return nil
	end
	if result.upgrade then
		return true
	end
	for _, id in ipairs(Others()) do
		local other = EvaluateFor(link, id)
		if other and other.upgrade then
			return true
		end
	end
	return false
end

-- The arrow --------------------------------------------------------------

local ARROW_SIZE = 20

local function SetArrow(texture)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-greenarrow") then
		texture:SetAtlas("bags-greenarrow")
	else
		texture:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
		texture:SetVertexColor(0.2, 1, 0.2)
	end
end

-- The functions for other addons (LootRolls) and for the /upgrades window
-- in Core.lua and Window.lua. The name is from when this was an addon of
-- its own; LootRolls asks for it.
UpgradeArrow = {}

-- True when the item would be an upgrade for you (false while unknown).
-- Also for the other specs that have an equipment set attached.
function UpgradeArrow.IsUpgrade(link)
	return AnyUpgrade(link) or false
end

-- The workings behind IsUpgrade, for other addons: nil while the item is
-- not cached, else { upgrade, score, against, againstLinks, empty }, where
-- score and against are missing for an item you cannot use. Read only.
function UpgradeArrow.Evaluate(link)
	return Evaluate(link)
end

-- Calls fn(reason) after anything that can change the answers: "gear"
-- (something worn changed), "level", "skills" (which also comes with every
-- skill-up), "weights" (the spec scored with, or one of its weights),
-- "set" (an equipment set changed, or the one attached to the spec),
-- "others" (the set attached to another spec: the arrows change, the
-- spec scored with is scored as it was) or
-- "names" (a spec renamed, made, deleted or moved to another role,
-- with the scores as they were).
local listeners = {}
function UpgradeArrow.OnChange(fn)
	listeners[#listeners + 1] = fn
end

-- An arrow texture on frame (top right), for other addons.
function UpgradeArrow.CreateArrow(frame)
	local arrow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
	SetArrow(arrow)
	arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
	arrow:SetPoint("TOPRIGHT", 3, 3)
	arrow:Hide()
	return arrow
end

-- Tooltip ----------------------------------------------------------------

local function AddTooltip(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local ok, _, link = pcall(tooltip.GetItem, tooltip)
	if not ok or type(link) ~= "string" or IsSecret(link) then
		return
	end
	-- An item you wear is not compared with itself.
	if data and data.guid and not IsSecret(data.guid) and C_Item.GetItemLocation then
		local okLoc, location = pcall(C_Item.GetItemLocation, data.guid)
		if okLoc and location and location.IsEquipmentSlot and location:IsEquipmentSlot() then
			return
		end
	end
	local result = Evaluate(link)
	if not result or not result.score then
		return
	end
	local alt = IsAltKeyDown()
	local roleText = " (" .. store.specs[spec].name .. ")"
	-- An upgrade always says so; the rest only while Alt is held.
	-- Points, not a percentage: against a worn item scoring near zero a
	-- percentage runs into the thousands.
	local function UpgradeLine(r, name)
		local gain = r.empty and ", empty slot" or (" +%.1f"):format(r.score - (r.against or 0))
		local line = "|cff40c040Upgrade|r" .. gain .. " (" .. name .. ")"
		if alt then
			tooltip:AddDoubleLine(line, ("%.1f vs %.1f"):format(r.score, r.against or 0), 1, 1, 1, 0.6, 0.6, 0.6)
		else
			tooltip:AddLine(line, 1, 1, 1)
		end
	end
	-- The other specs with a set attached, for which it is an upgrade:
	-- after the spec scored with and, with Alt, its workings.
	local function OtherLines()
		for _, id in ipairs(Others()) do
			local other = EvaluateFor(link, id)
			if other and other.upgrade then
				UpgradeLine(other, store.specs[id].name)
			end
		end
	end
	if result.upgrade then
		UpgradeLine(result, store.specs[spec].name)
	end
	if not alt then
		OtherLines()
		return
	end
	if not result.upgrade then
		tooltip:AddDoubleLine("Not an upgrade" .. roleText, ("%.1f vs %.1f"):format(result.score, result.against or 0), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	end
	local _, parts = Score(link, RANGED[select(9, C_Item.GetItemInfo(link)) or ""] and 18 or nil)
	for _, part in ipairs(parts) do
		tooltip:AddDoubleLine(("  %g %s x %g"):format(part[2], part[1], weights[part[1]] or 0), ("%.1f"):format(part[3]), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	end
	for _, against in ipairs(result.againstLinks or {}) do
		tooltip:AddLine("  vs " .. against, 0.6, 0.6, 0.6)
	end
	if result.set then
		tooltip:AddLine("  from your set " .. result.set, 0.6, 0.6, 0.6)
	end
	OtherLines()
end

-- Baganator --------------------------------------------------------------

local function RegisterBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
		return
	end
	Baganator.API.RegisterCornerWidget("Upgrade arrow", "upgrade_arrow", function(arrow, details)
		return AnyUpgrade(details.itemLink) -- nil: not cached yet; Baganator asks again
	end, function(itemButton)
		local arrow = itemButton:CreateTexture(nil, "OVERLAY")
		SetArrow(arrow)
		arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
		return arrow
	end, { corner = "top_right", priority = 1 })
end

-- Quest rewards ----------------------------------------------------------

-- Our arrows on Blizzard's reward buttons, kept in our own table: no field
-- is written on their frames.
local questArrows = {}
local questRetry = false

local function UpdateQuestRewards()
	local info = QuestInfoFrame
	local rewardsFrame = info and info.rewardsFrame
	local buttons = rewardsFrame and rewardsFrame.RewardButtons
	if type(buttons) ~= "table" then
		return
	end
	local pending = false
	for _, button in ipairs(buttons) do
		local arrow = questArrows[button]
		local show = false
		if button:IsShown() and button.objectType == "item" and (button.type == "choice" or button.type == "reward") then
			local link
			if info.questLog then
				link = GetQuestLogItemLink(button.type, button:GetID())
			else
				link = GetQuestItemLink(button.type, button:GetID())
			end
			local result = link and AnyUpgrade(link)
			if link and result == nil then
				pending = true -- item not cached yet
			end
			show = result or false
		end
		if show and not arrow then
			local icon = button.Icon or button.icon
			arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
			SetArrow(arrow)
			arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
			arrow:SetPoint("TOPRIGHT", icon or button, "TOPRIGHT", 3, 3)
			questArrows[button] = arrow
		end
		if arrow then
			arrow:SetShown(show)
		end
	end
	if pending and not questRetry then
		questRetry = true
		C_Timer.After(0.5, function()
			questRetry = false
			UpdateQuestRewards()
		end)
	end
end

local function HookQuestRewards()
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function()
			pcall(UpdateQuestRewards)
		end)
	end
end

-- Vendor ----------------------------------------------------------------

-- Our arrows on the vendor's item buttons (what is for sale, the buyback
-- tab, and the one buyback item on the first tab), kept in our own table
-- as with the quest rewards: no field is written on the game's frames.
local merchantArrows = {}
local merchantRetry = false

-- Shows or hides the arrow of one button; true when the item is not
-- cached yet and has to be looked at again.
local function MerchantArrow(button, link)
	if not button then
		return false
	end
	local result = link and AnyUpgrade(link) -- nil: not cached yet
	local show = result or false
	local arrow = merchantArrows[button]
	if show and not arrow then
		arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
		SetArrow(arrow)
		arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
		arrow:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
		merchantArrows[button] = arrow
	end
	if arrow then
		arrow:SetShown(show)
	end
	return link ~= nil and result == nil
end

local function UpdateMerchant()
	local frame = MerchantFrame
	if not (frame and frame:IsShown() and GetMerchantItemLink and GetBuybackItemLink) then
		return
	end
	local buyback = frame.selectedTab == 2
	local perPage = buyback and (BUYBACK_ITEMS_PER_PAGE or 12) or (MERCHANT_ITEMS_PER_PAGE or 10)
	local bought = GetNumBuybackItems and GetNumBuybackItems() or 0
	local count = buyback and bought or (GetMerchantNumItems and GetMerchantNumItems() or 0)
	local first = buyback and 0 or ((tonumber(frame.page) or 1) - 1) * perPage
	local pending = false
	for i = 1, math.max(BUYBACK_ITEMS_PER_PAGE or 12, MERCHANT_ITEMS_PER_PAGE or 10) do
		local index = first + i
		local link
		if i <= perPage and index <= count then
			link = buyback and GetBuybackItemLink(index) or GetMerchantItemLink(index)
		end
		pending = MerchantArrow(_G["MerchantItem" .. i .. "ItemButton"], link) or pending
	end
	-- The last item sold, shown under the items for sale.
	local last = not buyback and bought > 0 and GetBuybackItemLink(bought) or nil
	pending = MerchantArrow(MerchantBuyBackItemItemButton, last) or pending

	if pending and not merchantRetry then
		merchantRetry = true
		C_Timer.After(0.5, function()
			merchantRetry = false
			pcall(UpdateMerchant)
		end)
	end
end

local function HookMerchant()
	if MerchantFrame_Update then
		hooksecurefunc("MerchantFrame_Update", function()
			pcall(UpdateMerchant)
		end)
	end
end

-- Events -----------------------------------------------------------------

local function Invalidate(reason)
	wipe(cache)
	wipe(setLinks)
	others = nil
	weights = Weights()
	pcall(UpdateQuestRewards)
	pcall(UpdateMerchant)
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
	for _, fn in ipairs(listeners) do
		pcall(fn, reason)
	end
end


-- Only the names changed: what is scored stays as it was.
local function Renamed()
	for _, fn in ipairs(listeners) do
		pcall(fn, "names")
	end
end

-- After the specs changed: weights when the spec scored with is another
-- one now, else names.
local function Settle()
	if CurrentSpec() ~= spec then
		Invalidate("weights")
	else
		Renamed()
	end
end

-- Settings: the slash command, the options window and other addons change
-- them here. Which spec is picked is this character's; the specs and their
-- weights are the class's.

local function SetSpec(id) -- a spec's id, or nil for automatic
	db.fixed = id
	if id then
		db.active[store.specs[id].role] = id
	end
	Invalidate("weights")
end

-- A weight equal to the base's own is not kept: the base's applies again.
local function SetWeight(stat, value)
	local default = Base(spec)[stat] or 0
	store.specs[spec].weights[stat] = value ~= default and value or nil
	Invalidate("weights")
end

local function ResetWeights()
	wipe(store.specs[spec].weights)
	Invalidate("weights")
end

-- Why a spec could not be made, renamed, deleted or moved.
local ERR_NO_NAME = "a spec needs a name"
local ERR_LONG = ("a spec's name has at most %d letters"):format(NAME_MAX)
local ERR_RESERVED = "\"auto\" is not a spec's name"
local ERR_TAKEN = "there is a spec of that name already"
local ERR_NO_SPEC = "no such spec"
local ERR_LAST = "it is the only spec of its role"
local ERR_ROLE = "your class cannot fill that role"

local function Trim(text)
	return type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
end

-- The name as it will be kept, or nil and why not. self: the spec being
-- renamed, which may keep its name.
local function CheckName(name, self)
	name = Trim(name):gsub("|", "")
	if name == "" then
		return nil, ERR_NO_NAME
	elseif #name > NAME_MAX then
		return nil, ERR_LONG
	elseif name:lower() == "auto" or name:lower() == "automatic" then
		return nil, ERR_RESERVED
	end
	for id, value in pairs(store.specs) do
		if id ~= self and value.name:lower() == name:lower() then
			return nil, ERR_TAKEN
		end
	end
	return name
end

local function Find(name)
	name = Trim(name):lower()
	for _, id in ipairs(Ordered()) do
		if store.specs[id].name:lower() == name then
			return id
		end
	end
end

-- For other addons -----------------------------------------------------------

-- The spec scored with: its id, name, role key ("TANK", "HEALER",
-- "DAMAGER") and role name, and whether it was picked by hand (true) or
-- follows your group (false).
function UpgradeArrow.Spec()
	local value = store.specs[spec]
	return spec, value.name, value.role, ROLE_NAME[value.role], db.fixed ~= nil and store.specs[db.fixed] ~= nil
end

-- The class's specs, by role (tank, healer, damage), each as { id = ,
-- name = , role = , roleName = , base = (the name of the class's own spec
-- its weights start from), only = (true when it is its role's only spec,
-- which cannot be deleted or moved) }.
function UpgradeArrow.Specs()
	local list = {}
	for _, id in ipairs(Ordered()) do
		local value = store.specs[id]
		list[#list + 1] = { id = id, name = value.name, role = value.role, roleName = ROLE_NAME[value.role],
			base = OwnSpec(value.base).name, only = CountOf(value.role) == 1 }
	end
	return list
end

-- Scores with spec id until another is picked, on this character; with nil
-- follows your group again. Picking a spec also makes it its role's spec
-- for when it is automatic.
function UpgradeArrow.SetSpec(id)
	if id == nil or store.specs[id] then
		SetSpec(id)
	end
end

-- A new spec, a copy of the one scored with, which it is then scored
-- with. Returns its id, or nil and why not.
function UpgradeArrow.NewSpec(name)
	local checked, err = CheckName(name)
	if not checked then
		return nil, err
	end
	local id = MakeSpec(spec, checked)
	db.fixed, db.active[store.specs[id].role] = id, id
	Invalidate("names") -- the same weights: nothing to score again
	return id
end

-- Returns true, or nil and why not.
function UpgradeArrow.RenameSpec(id, name)
	if not store.specs[id] then
		return nil, ERR_NO_SPEC
	end
	local checked, err = CheckName(name, id)
	if not checked then
		return nil, err
	end
	store.specs[id].name = checked
	Renamed()
	return true
end

-- For every character of the class. Not the only spec of a role. Returns
-- true, or nil and why not.
function UpgradeArrow.DeleteSpec(id)
	local value = store.specs[id]
	if not value then
		return nil, ERR_NO_SPEC
	elseif CountOf(value.role) == 1 then
		return nil, ERR_LAST
	end
	store.specs[id] = nil
	for i, listed in ipairs(store.order) do
		if listed == id then
			table.remove(store.order, i)
			break
		end
	end
	if db.fixed == id then
		db.fixed = nil
	end
	if db.active[value.role] == id then
		db.active[value.role] = nil
	end
	local hadSet, before = SetOf(id), spec
	db.sets[id] = nil
	others = nil
	Settle()
	if hadSet and spec == before then
		Invalidate("others") -- its arrows go
	end
	return true
end

-- Moves a spec to another role the class can fill; not the only spec of
-- its role. Returns true, or nil and why not.
function UpgradeArrow.SetSpecRole(id, key)
	local value = store.specs[id]
	if not value then
		return nil, ERR_NO_SPEC
	elseif not ClassRoles()[key] then
		return nil, ERR_ROLE
	elseif value.role == key then
		return true
	elseif CountOf(value.role) == 1 then
		return nil, ERR_LAST
	end
	if db.active[value.role] == id then
		db.active[value.role] = nil
	end
	value.role = key
	if db.fixed == id then
		db.active[key] = id
	end
	Settle()
	return true
end

-- This character's equipment sets, by name: a list of { id = , name = }.
function UpgradeArrow.Sets()
	local list = {}
	local ok, ids = false, nil
	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
		ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
	end
	for _, setID in ipairs(ok and type(ids) == "table" and ids or {}) do
		local name = SetName(setID)
		if name then
			list[#list + 1] = { id = setID, name = name }
		end
	end
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	return list
end

-- The equipment set attached to spec id (default: the one scored with) on
-- this character: its id and name, or nil when items are compared with
-- what you wear.
function UpgradeArrow.SpecSet(id)
	local setID = SetOf(id or spec)
	return setID, SetName(setID)
end

-- Attaches equipment set setID to spec id on this character, or with nil
-- compares with what you wear again. Returns true, or nil and why not.
function UpgradeArrow.SetSpecSet(id, setID)
	if not store.specs[id] then
		return nil, ERR_NO_SPEC
	elseif setID ~= nil and not SetName(setID) then
		return nil, "no such equipment set"
	end
	db.sets[id] = setID
	Invalidate(id == spec and "set" or "others")
	return true
end

-- The role scored for: its key and name, and whether the spec was picked
-- by hand (true) or follows your group (false).
function UpgradeArrow.Role()
	local _, _, key, name, fixed = UpgradeArrow.Spec()
	return key, name, fixed
end

-- The roles your class can fill, in order, each as { key = , name = }.
function UpgradeArrow.Roles()
	local list, roles = {}, ClassRoles()
	for _, key in ipairs(ROLE_ORDER) do
		if roles[key] then
			list[#list + 1] = { key = key, name = ROLE_NAME[key] }
		end
	end
	return list
end

-- Scores with a role's spec until another is picked; with nil follows your
-- group again. The same as /upgradearrow role.
function UpgradeArrow.SetRole(key)
	if key == nil then
		SetSpec(nil)
	elseif ClassRoles()[key] then
		SetSpec(SpecOf(key))
	end
end

local STAT_NAME = { dps = "Weapon damage per second, melee", rdps = "Weapon damage per second, ranged" }

local function StatName(stat)
	local key = STATS[stat]
	return STAT_NAME[stat] or _G[type(key) == "table" and key[1] or key] or stat
end

-- For a slider: how far a weight usually goes, and the step it is set by.
-- No class's own weight is above 3.5 (armor 0.08; it counts in hundredths
-- of what the others do). A weight can be set higher than this.
local function Usual(stat)
	if stat == "armor" then
		return 0.2, 0.005
	end
	return 5, 0.1
end

-- The weights of the spec scored with, one entry per stat in the usual
-- order, each as { stat = (its short name), name = (the game's), value = ,
-- default = (the value of the class's own spec it was made from), max =
-- and step = (for a slider from 0, see Usual) }.
function UpgradeArrow.Weights()
	local list, defaults = {}, Base(spec)
	for _, stat in ipairs(ORDER) do
		local max, step = Usual(stat)
		list[#list + 1] = { stat = stat, name = StatName(stat), value = weights[stat] or 0, default = defaults[stat] or 0,
			max = max, step = step }
	end
	return list
end

-- One weight of the spec scored with; the same as /upgradearrow <stat> <weight>.
function UpgradeArrow.SetWeight(stat, value)
	if STATS[stat] and type(value) == "number" and value == value and math.abs(value) < math.huge then
		SetWeight(stat, value)
	end
end

-- The spec scored with back to the weights it was made from; the same as
-- /upgradearrow reset.
function UpgradeArrow.ResetWeights()
	ResetWeights()
end

------------------------------------------------------------------------------
-- The game's options window (Options > AddOns): the spec, and under it a
-- page with the weights of the spec scored with. The Defaults button on
-- that page is /upgradearrow reset. Making, renaming and deleting specs is
-- in the /upgrades window. Optional: without the game's settings API the
-- slash command still does what it does.
------------------------------------------------------------------------------

local function Label(id)
	local value = store.specs[id]
	if value.name == ROLE_NAME[value.role] then
		return value.name
	end
	return value.name .. " (" .. ROLE_NAME[value.role] .. ")"
end

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory
		and Settings.RegisterProxySetting and Settings.CreateSlider and Settings.CreateDropdown) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("ForeverUpgrades")

	local function Choices()
		local container = Settings.CreateControlTextContainer()
		container:Add("auto", "Automatic", "Your role in the group, else the role ticked in the group finder, else damage; "
			.. "with the spec last picked for that role. Now: " .. Label(spec) .. ".")
		for _, id in ipairs(Ordered()) do
			container:Add(id, Label(id))
		end
		return container:GetData()
	end
	local specSetting = Settings.RegisterProxySetting(category, "ForeverUpgrades_spec", Settings.VarType.String, "Score items as", "auto",
		function() return db.fixed and store.specs[db.fixed] and db.fixed or "auto" end,
		function(value) SetSpec(value ~= "auto" and store.specs[value] and value or nil) end)
	Settings.CreateDropdown(category, specSetting, Choices,
		"The spec the upgrade arrows are worked out with, on this character. Specs are shared by your characters of this class; "
		.. "The /upgrades window makes, renames and deletes them.")

	local function Weight(value)
		return ("%g"):format(value)
	end
	local page = Settings.RegisterVerticalLayoutSubcategory(category, "Weights")
	for _, stat in ipairs(ORDER) do
		local name = StatName(stat) .. " (" .. stat .. ")"
		-- Armor counts in hundredths of what the others do.
		local max, step = 20, 0.1
		if stat == "armor" then
			max, step = 0.5, 0.005
		end
		local setting = Settings.RegisterProxySetting(page, "ForeverUpgrades_weight_" .. stat, Settings.VarType.Number, name,
			Base(spec)[stat] or 0,
			function() return weights[stat] or 0 end,
			function(value)
				SetWeight(stat, tonumber(("%.4f"):format(math.floor(value / step + 0.5) * step)))
			end)
		-- The default is that of the spec scored with at the time, not at
		-- load. The setting is this addon's own object.
		setting.GetDefaultValueDerived = function()
			return Base(spec)[stat] or 0
		end
		local options = Settings.CreateSliderOptions(0, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, Weight)
		Settings.CreateSlider(page, setting, options, "Points for one " .. stat .. " on an item, in the spec items are scored with (the line above this page).")
	end

	Settings.RegisterAddOnCategory(category)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then
			return
		end
		-- The addon's one saved table: specs per class (classes), the
		-- picks per character (characters), and the window's (window,
		-- Core.lua's).
		ForeverUpgradesDB = type(ForeverUpgradesDB) == "table" and ForeverUpgradesDB or {}
		local all = ForeverUpgradesDB
		local _, class = UnitClass("player")
		LoadSpecs(all, class or "")
		all.characters = type(all.characters) == "table" and all.characters or {}
		local key = UnitName("player") .. "-" .. GetRealmName()
		all.characters[key] = type(all.characters[key]) == "table" and all.characters[key] or {}
		db = all.characters[key]
		db.active = type(db.active) == "table" and db.active or {}
		-- The equipment set attached to a spec on this character: spec id -> set id.
		db.sets = type(db.sets) == "table" and db.sets or {}
		db.setItemLinks = type(db.setItemLinks) == "table" and db.setItemLinks or {}
		for itemID, link in pairs(db.setItemLinks) do
			if type(itemID) ~= "number" or type(link) ~= "string" then
				db.setItemLinks[itemID] = nil
			end
		end
		for id, setID in pairs(db.sets) do
			if not store.specs[id] or type(setID) ~= "number" then
				db.sets[id] = nil
			end
		end
		weights = Weights()
		local ok, err = pcall(RegisterSettings)
		if not ok then
			print("|cff40c040ForeverUpgrades|r: options panel unavailable (" .. tostring(err) .. "); use /upgradearrow instead")
		end
		RegisterBaganator()
		HookQuestRewards()
		HookMerchant()
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
				pcall(AddTooltip, tooltip, data)
			end)
		end
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		self:RegisterEvent("PLAYER_LEVEL_UP")
		self:RegisterEvent("SKILL_LINES_CHANGED")
		pcall(self.RegisterEvent, self, "EQUIPMENT_SETS_CHANGED")
		for _, e in ipairs({ "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE", "LFG_LIST_ROLE_UPDATE", "LFG_ROLE_UPDATE" }) do
			pcall(self.RegisterEvent, self, e)
		end
	elseif event == "PLAYER_ROLES_ASSIGNED" or event == "GROUP_ROSTER_UPDATE"
		or event == "LFG_LIST_ROLE_UPDATE" or event == "LFG_ROLE_UPDATE" then
		if CurrentSpec() ~= spec then
			Invalidate("weights")
		end
	elseif event == "EQUIPMENT_SETS_CHANGED" then
		PruneSetLinks()
		Invalidate("set")
	else
		Invalidate(event == "PLAYER_EQUIPMENT_CHANGED" and "gear" or event == "PLAYER_LEVEL_UP" and "level" or "skills")
	end
end)

SLASH_UPGRADEARROW1 = "/upgradearrow"
SlashCmdList.UPGRADEARROW = function(msg)
	local command, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()
	local value = rest:lower()
	local prefix = "|cff40c040ForeverUpgrades|r: "
	local function Names()
		local names = {}
		for _, id in ipairs(Ordered()) do
			names[#names + 1] = store.specs[id].name
		end
		return table.concat(names, " | ")
	end
	if command == "spec" then
		local id = Find(rest)
		if value == "auto" then
			SetSpec(nil)
		elseif id then
			SetSpec(id)
		else
			print(prefix .. "/upgradearrow spec " .. Names() .. " | auto")
			return
		end
		print(prefix .. "scoring as " .. Label(spec) .. " (" .. roleSource .. ")")
	elseif command == "role" then
		if value == "auto" then
			SetSpec(nil)
		elseif ROLE_ARG[value] and ClassRoles()[ROLE_ARG[value]] then
			SetSpec(SpecOf(ROLE_ARG[value]))
		else
			local names = {}
			for _, r in ipairs(ROLE_ORDER) do
				if ClassRoles()[r] then
					names[#names + 1] = ROLE_NAME[r]:lower()
				end
			end
			print(prefix .. "/upgradearrow role " .. table.concat(names, " | ") .. " | auto")
			return
		end
		print(prefix .. "scoring as " .. Label(spec) .. " (" .. roleSource .. ")")
	elseif command == "set" then
		local name = store.specs[spec].name
		if value == "none" then
			UpgradeArrow.SetSpecSet(spec, nil)
			print(prefix .. name .. " compares with what you wear")
			return
		end
		for _, set in ipairs(UpgradeArrow.Sets()) do
			if set.name:lower() == value then
				UpgradeArrow.SetSpecSet(spec, set.id)
				print(prefix .. name .. " compares with your set " .. set.name)
				return
			end
		end
		local names = {}
		for _, set in ipairs(UpgradeArrow.Sets()) do
			names[#names + 1] = set.name
		end
		names[#names + 1] = "none"
		print(prefix .. "/upgradearrow set " .. table.concat(names, " | "))
	elseif command == "reset" then
		ResetWeights()
		print(prefix .. store.specs[spec].name .. " weights back to those of " .. OwnSpec(store.specs[spec].base).name)
	elseif STATS[command] and tonumber(value) then
		UpgradeArrow.SetWeight(command, tonumber(value))
		print(("%s%s %s = %g"):format(prefix, store.specs[spec].name, command, tonumber(value)))
	else
		local list = {}
		for _, key in ipairs(ORDER) do
			if (weights[key] or 0) ~= 0 then
				list[#list + 1] = ("%s %g"):format(key, weights[key])
			end
		end
		print(prefix .. Label(spec) .. " (" .. roleSource .. "): " .. table.concat(list, ", "))
		print("  /upgradearrow <stat> <weight>  |  reset  |  spec <name|auto>  |  role <role|auto>  |  set <name|none>   (stats: " .. table.concat(ORDER, " ") .. ")")
		print("  specs: " .. Names())
	end
end
