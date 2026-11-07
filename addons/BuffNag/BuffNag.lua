-- BuffNag: the Cooldown Manager shows a buff's icon while the buff is up.
-- This does the reverse: a bar of icons for the buffs you chose that are
-- missing, on you or on your party, with the minimap ping on a loop until
-- they are back. Click an icon to cast the buff on the first one lacking it.
--
-- It is configured from its own tab in the Cooldown Manager's settings
-- window (Escape > Options > Cooldown Manager, or /bn): the buffs on offer
-- are the ones the game lists for your class there, the group buffs it
-- knows, a food buff, a flask, elixirs and weapon enchants (the last three
-- only when a fitting item is in the bags). Buffs are matched by name,
-- so any rank counts. The bar hides in combat, while resting, mounted, on a
-- flight path or dead.

local ADDON_NAME = ...

local IsSecret = issecretvalue or function() return false end

local DEFAULTS = { -- account wide: the bar and the sound
	party = true, -- also look at party members, for buffs marked for the party
	-- A buff counts as running out at this share of its duration left,
	-- but never more than soonMax seconds before the end nor less than
	-- soonMin; buffs of unknown duration use soonMax.
	soonShare = 0.1,
	soonMax = 120,
	soonMin = 30,
	sound = true, -- ping while something is missing
	pingGap = 0.4, -- seconds between pings
	scale = 1,
	locked = false,
	glow = "flash", -- "flash", "ants" or "off": the Cooldown Manager's alert effect on a missing buff
	glowColor = "gold", -- gold, cyan, red, green or blue
	expiringGlow = true, -- the Cooldown Manager's pandemic border on a buff that is running out
	point = { "CENTER", 0, 200 },
}

-- Class buffs used to seed a new character's choices, and to fill in what
-- the game's own lists leave out. "auras" are spells whose name on a unit
-- satisfies the buff; "know" spells, one of which has to be in the
-- spellbook; "cast" is tried in order on a click. "mana" skips units
-- without mana, "unless" excuses a unit (eating excuses missing food).
local SEEDS = {
	-- priest
	{ scope = "party", auras = { 1243, 21562 }, know = { 1243 }, cast = { 1243 } },
	{ scope = "party", auras = { 14752, 27681 }, know = { 14752 }, cast = { 14752 }, mana = true },
	{ scope = "party", auras = { 976, 27683 }, know = { 976 }, cast = { 976 }, default = false },
	{ scope = "self", auras = { 588 }, know = { 588 }, cast = { 588 } },
	-- mage
	{ scope = "party", auras = { 1459, 23028 }, know = { 1459 }, cast = { 1459 }, mana = true },
	{ scope = "self", label = "Armor", auras = { 168, 7302, 6117 }, know = { 168, 7302, 6117 }, cast = { 6117, 7302, 168 } },
	-- druid
	{ scope = "party", auras = { 1126, 21849 }, know = { 1126 }, cast = { 1126 } },
	{ scope = "self", auras = { 467 }, know = { 467 }, cast = { 467 }, default = false },
	{ scope = "self", auras = { 16864 }, know = { 16864 }, cast = { 16864 } },
	-- paladin
	{ scope = "party", label = "Blessing", auras = { 19740, 19742, 20217, 25782, 25894, 25898 }, know = { 19740, 19742, 20217 }, cast = { 20217, 19742, 19740 } },
	{ scope = "self", label = "Aura", auras = { 465, 7294, 19746, 19876, 19888, 19891, 20218 }, know = { 465, 7294 }, cast = { 465 } },
	{ scope = "self", auras = { 25780 }, know = { 25780 }, cast = { 25780 }, default = false },
	-- shaman
	{ scope = "self", auras = { 324 }, know = { 324 }, cast = { 324 } },
	-- warlock
	{ scope = "self", label = "Demon Armor", auras = { 687, 706 }, know = { 687, 706 }, cast = { 706, 687 } },
	-- warrior
	{ scope = "party", auras = { 6673 }, know = { 6673 }, cast = { 6673 }, default = false },
	-- hunter
	{ scope = "self", label = "Aspect", auras = { 13165, 13163, 5118, 13159, 13161, 20043, 469145, 34074 }, know = { 13165, 13163, 5118 }, cast = { 13165, 13163 } },
	{ scope = "self", auras = { 19506 }, know = { 19506 }, cast = { 19506 } },
}

local WELL_FED, FOOD = 19705, 433

-- Shaman weapon imbues, in order of preference: a shaman who knows one
-- needs nothing from the bags for the main hand.
local IMBUES = { 8232, 8024, 8033, 8017 } -- Windfury, Flametongue, Frostbrand, Rockbiter

-- Items that put a temporary enchant on a weapon, from the game's data,
-- with the weapon subclasses each fits as a bit mask (0: any weapon).
local WEAPON_ITEMS = {
	-- sharpening stones: axes, swords, daggers, polearms
	[2862] = 33219, [287978] = 33219, [2863] = 33219, [2871] = 33219, [7964] = 33219, [12404] = 33219,
	[18262] = 42483, [287980] = 42483, [211845] = 42483, -- elemental and Blackfathom: also blunt
	[23122] = 1097203, -- Consecrated Sharpening Stone
	-- weightstones: maces, staves, fist weapons
	[3239] = 9264, [3240] = 9264, [3241] = 9264, [7965] = 9264, [12643] = 9264,
	-- oils: any weapon
	[20744] = 0, [20745] = 0, [20746] = 0, [287979] = 0, [20747] = 0, [20748] = 0, [20749] = 0, [20750] = 0, [23123] = 0,
	[3824] = 173555, [3829] = 173555, -- Shadow Oil, Frost Oil
	-- warlock stones
	[1254] = 0, [13699] = 0, [13700] = 0, [13701] = 0, [5522] = 0, [13602] = 0, [13603] = 0,
	-- poisons
	[6947] = 173555, [6949] = 173555, [6950] = 173555, [8926] = 173555, [8927] = 173555, [8928] = 173555, [5654] = 173555,
	[2892] = 173555, [2893] = 173555, [8984] = 173555, [8985] = 173555, [20844] = 173555,
	[3775] = 173555, [3776] = 173555, [5237] = 173555, [6951] = 173555, [9186] = 173555,
	[10918] = 173555, [10920] = 173555, [10921] = 173555, [10922] = 173555,
	[217345] = 173555, [217346] = 173555, [217347] = 173555, [226374] = 173555, [234444] = 173555,
	-- scrolls of imbue: staves (1024), daggers (32768), swords (128)
	[277494] = 1024, [277487] = 1024, [277496] = 1024, [277497] = 1024, [277485] = 1024, [277500] = 1024, [277501] = 1024,
	[274947] = 1024, [277502] = 1024, [277495] = 1024, [277503] = 1024, [277486] = 1024,
	[275067] = 32768, [277488] = 32768, [277498] = 32768, [277489] = 128,
}
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

-- Flasks and elixirs, from the game's data: item to the spell of the buff
-- it gives. Only one flask can be up at a time. Elixirs stack, but tiers
-- of one elixir replace each other, so each item names its family.
local FLASKS = {
	[13510] = 17626, -- Flask of the Titans
	[13511] = 17627, -- Flask of Distilled Wisdom
	[13512] = 17628, -- Flask of Supreme Power
	[13513] = 17629, -- Flask of Chromatic Resistance
	[274273] = 1293740, -- Flask of Natural Accuracy
	[274274] = 1293741, -- Flask of Natural Aggression
	[274275] = 1293742, -- Flask of Natural Precision
	[274276] = 1293743, -- Flask of Natural Swiftness
}
local ELIXIRS = {
	[9155] = { 11390, "Arcane Elixir" }, [13454] = { 17539, "Arcane Elixir" }, [217398] = { 439959, "Arcane Elixir" },
	[247754] = { 1245244, "Arcane Elixir" }, [250342] = { 1250971, "Arcane Elixir" },
	[250330] = { 1250922, "Cleric's Elixir" }, [250331] = { 1250924, "Cleric's Elixir" }, [250332] = { 1250925, "Cleric's Elixir" },
	[250333] = { 1250926, "Cleric's Elixir" },
	[2457] = { 2374, "Elixir of Agility" }, [3390] = { 3160, "Elixir of Agility" }, [8949] = { 11328, "Elixir of Agility" },
	[9187] = { 11334, "Elixir of Agility" },
	[13453] = { 17537, "Elixir of Brute Force" },
	[210708] = { 426606, "Elixir of Coalesced Regret" },
	[250328] = { 1250918, "Elixir of Cunning" },
	[3389] = { 3220, "Elixir of Defense" }, [5997] = { 673, "Elixir of Defense" }, [8951] = { 11349, "Elixir of Defense" },
	[13445] = { 11348, "Elixir of Defense" },
	[22192] = { 27653, "Elixir of Dodging" },
	[289334] = { 1328127, "Elixir of Endless Experience" }, [289084] = { 1327738, "Elixir of Endless Healing" },
	[289082] = { 1327736, "Elixir of Endless Intellect" }, [289321] = { 1328032, "Elixir of Endless Mana" },
	[289087] = { 1327753, "Elixir of Endless Opportunity" }, [289083] = { 1327737, "Elixir of Endless Power" },
	[289086] = { 1327751, "Elixir of Endless Rapidity" },
	[250350] = { 1250985, "Elixir of Ferocity" },
	[6373] = { 7844, "Elixir of Fire Power" },
	[247755] = { 1245249, "Elixir of Force" },
	[2458] = { 2378, "Elixir of Fortitude" }, [3825] = { 3593, "Elixir of Fortitude" }, [250334] = { 1250928, "Elixir of Fortitude" },
	[250335] = { 1250931, "Elixir of Fortitude" },
	[17708] = { 21920, "Elixir of Frost Power" },
	[21546] = { 1310077, "Elixir of Holy Power" },
	[9179] = { 11396, "Elixir of Intellect" }, [250353] = { 1250988, "Elixir of Intellect" }, [250354] = { 1250989, "Elixir of Intellect" },
	[250343] = { 1250972, "Elixir of Nature Power" },
	[3391] = { 3164, "Elixir of Ogre Strength" },
	[22193] = { 27652, "Elixir of Resistance" },
	[250338] = { 1250941, "Elixir of the Sages" }, [13447] = { 17535, "Elixir of the Sages" },
	[9264] = { 11474, "Elixir of Shadow Power" },
	[250344] = { 1250974, "Elixir of Spirit" }, [250345] = { 1250976, "Elixir of Spirit" }, [250346] = { 1250978, "Elixir of Spirit" },
	[250347] = { 1250979, "Elixir of Spirit" },
	[2454] = { 2367, "Elixir of Strength" }, [9206] = { 11405, "Elixir of Strength" }, [250349] = { 1250984, "Elixir of Strength" },
	[250336] = { 1250932, "Elixir of Wicked Regeneration" },
	[3383] = { 3166, "Elixir of Wisdom" },
	[250351] = { 1250986, "Elixir of the Grizzly" },
	[13452] = { 17538, "Elixir of the Mongoose" },
	[250337] = { 1250940, "Elixir of the Owl" },
	[250329] = { 1250920, "Elixir of the Phalanx" },
	[250348] = { 1250981, "Elixir of the Whale" },
	[20007] = { 24363, "Mageblood Elixir" }, [250339] = { 1250942, "Mageblood Elixir" }, [250340] = { 1250944, "Mageblood Elixir" },
	[250341] = { 1250948, "Mageblood Elixir" },
	[3382] = { 3219, "Troll's Blood Elixir" }, [3388] = { 3222, "Troll's Blood Elixir" }, [3826] = { 3223, "Troll's Blood Elixir" },
	[20004] = { 24361, "Troll's Blood Elixir" },
}
local FLASK_NAMES, ELIXIR_FAMILY_NAMES = {}, {} -- resolved from the spells once their names load

-- Foods and drinks whose use leaves a Well Fed buff, from the game's data.
local FOODS = {
	[724] = true, [733] = true, [787] = true, [1017] = true, [1082] = true, [2680] = true, [2681] = true, [2682] = true, [2683] = true, [2684] = true,
	[2685] = true, [2687] = true, [2888] = true, [3220] = true, [3662] = true, [3663] = true, [3664] = true, [3665] = true, [3666] = true, [3726] = true,
	[3727] = true, [3728] = true, [3729] = true, [4457] = true, [4592] = true, [4593] = true, [4594] = true, [5095] = true, [5472] = true, [5474] = true,
	[5476] = true, [5477] = true, [5479] = true, [5480] = true, [5527] = true, [6038] = true, [6290] = true, [6316] = true, [6887] = true, [6888] = true,
	[6890] = true, [7806] = true, [7807] = true, [7808] = true, [8364] = true, [8957] = true, [10841] = true, [11584] = true, [12209] = true, [12210] = true,
	[12212] = true, [12213] = true, [12214] = true, [12215] = true, [12216] = true, [12218] = true, [12224] = true, [13851] = true, [13927] = true, [13928] = true,
	[13929] = true, [13930] = true, [13931] = true, [13932] = true, [13933] = true, [13934] = true, [13935] = true, [16971] = true, [17197] = true, [17198] = true,
	[17222] = true, [18045] = true, [18254] = true, [20074] = true, [20452] = true, [21072] = true, [21217] = true, [206177] = true, [238637] = true, [238638] = true,
	[238639] = true, [249865] = true, [249866] = true, [249867] = true, [249868] = true, [249869] = true, [249870] = true, [249871] = true, [249872] = true, [249873] = true,
	[249874] = true, [249875] = true, [249876] = true, [250065] = true, [250066] = true, [250067] = true, [250068] = true, [250069] = true, [250070] = true, [250071] = true,
	[250072] = true, [250073] = true, [250074] = true, [250075] = true, [250076] = true, [250077] = true, [250078] = true, [250079] = true, [250080] = true, [263509] = true,
	[263512] = true, [267341] = true, [268912] = true, [268913] = true, [274971] = true, [274976] = true, [286152] = true, [287973] = true, [287974] = true,
}
local EATING_SPELLS = { 21149 --[[ Egg Nog ]], 5004 --[[ Food ]], 1249906 --[[ Nutritious Drink ]], 1248377 --[[ Nutritious Food ]] }
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local MAIN_HAND, OFF_HAND = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
local WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local FISHING_POLE = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local ICON, GAP = 40, 6
local MAX_ICONS = 16
local QUESTION_MARK = 134400

local db, cdb -- account settings, this character's choices
local knownSpells = {} -- spell name -> true, from the spellbook
local catalog, catalogOrder = {}, {} -- key -> entry, in display order
local nagging = false
local refreshPending = false
local previewing = false

local function Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff9999ffBuffNag|r " .. msg)
end

local function SpellName(spellID)
	local name
	if C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(spellID)
	elseif GetSpellInfo then
		name = GetSpellInfo(spellID)
	end
	if name and not IsSecret(name) then
		return name
	end
end

local function SpellIcon(spellID)
	local ok, icon = pcall(function()
		if C_Spell and C_Spell.GetSpellTexture then
			return C_Spell.GetSpellTexture(spellID)
		elseif GetSpellTexture then
			return GetSpellTexture(spellID)
		end
	end)
	return ok and icon or QUESTION_MARK
end

------------------------------------------------------------------------------
-- The spellbook
------------------------------------------------------------------------------

local function ScanSpellbook()
	wipe(knownSpells)
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		local spellType = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info then
				for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
					if item and item.itemType == spellType and item.name and not IsSecret(item.name) then
						knownSpells[item.name] = true
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellBookItemName then
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, count = GetSpellTabInfo(tab)
			for slot = offset + 1, offset + count do
				local name = GetSpellBookItemName(slot, "spell")
				if name then
					knownSpells[name] = true
				end
			end
		end
	end
end

------------------------------------------------------------------------------
-- The catalogue: everything that can be nagged about
------------------------------------------------------------------------------

-- An entry: key, name, icon, auraNames (set), castNames (list, in order of
-- preference), party (default for a new choice), kind ("aura", "food",
-- "weapon", "offhand"), mana, unlessNames.

local function AddEntry(entry)
	local existing = catalog[entry.key]
	if existing then
		-- Same buff from another source: pool what they know.
		for name in pairs(entry.auraNames) do
			existing.auraNames[name] = true
		end
		for _, name in ipairs(entry.castNames) do
			if not tContains(existing.castNames, name) then
				existing.castNames[#existing.castNames + 1] = name
			end
		end
		existing.party = existing.party or entry.party
		existing.mana = existing.mana or entry.mana
		return existing
	end
	catalog[entry.key] = entry
	catalogOrder[#catalogOrder + 1] = entry.key
	return entry
end

local function SpellEntry(spellID, party, source)
	local name = SpellName(spellID)
	if not name then
		return nil
	end
	return AddEntry({
		key = "spell:" .. name, name = name, icon = SpellIcon(spellID), kind = "aura", source = source,
		auraNames = { [name] = true }, castNames = { name }, party = party, unlessNames = {},
	})
end

local function BuildCatalog()
	wipe(catalog)
	wipe(catalogOrder)

	-- Group buffs the game lists for the class (the Cooldown Manager's
	-- Group Buffs tab): buffs for the party.
	if C_CooldownViewer and C_CooldownViewer.GetGroupBuffItems then
		local ok, items = pcall(C_CooldownViewer.GetGroupBuffItems)
		if ok and type(items) == "table" then
			for _, item in ipairs(items) do
				if item.isKnown and item.displaySpellID then
					local entry = SpellEntry(item.displaySpellID, true, "group")
					if entry and item.iconID then
						entry.icon = item.iconID
					end
				end
			end
		end
	end

	-- Buffs the Cooldown Manager can track for the class: buffs on you. The
	-- same lists hold the debuffs you put on targets; those are left out.
	local function IsBuffOnSelf(info)
		if info.selfAura then
			return true
		end
		local ok, helpful = pcall(function()
			if C_Spell and C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(info.spellID) then
				return false
			end
			return C_Spell and C_Spell.IsSpellHelpful and C_Spell.IsSpellHelpful(info.spellID)
		end)
		return ok and helpful or false
	end
	if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and Enum.CooldownViewerCategory then
		local categories = Enum.CooldownViewerCategory
		for _, category in ipairs({ categories.TrackedBuff, categories.TrackedBar, categories.SpecAgnosticTracked, categories.EquipSlotTracked }) do
			if category then
				local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
				if ok and type(ids) == "table" then
					for _, cooldownID in ipairs(ids) do
						local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
						if okInfo and info and info.isKnown and info.hasAura and not info.isInvisible and info.spellID and IsBuffOnSelf(info) then
							local entry = SpellEntry(info.spellID, false, "cdm")
							if entry then
								for _, linked in ipairs(info.linkedSpellIDs or {}) do
									local name = SpellName(linked)
									if name then
										entry.auraNames[name] = true
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- The seeds: anything above that they describe gets their extra
	-- knowledge (other names, mana); anything missing is added when the
	-- spellbook has the spell.
	for _, seed in ipairs(SEEDS) do
		local auraNames, castNames, known = {}, {}, false
		for _, id in ipairs(seed.auras) do
			local name = SpellName(id)
			if name then
				auraNames[name] = true
			end
		end
		for _, id in ipairs(seed.cast) do
			local name = SpellName(id)
			if name and knownSpells[name] then
				castNames[#castNames + 1] = name
			end
		end
		for _, id in ipairs(seed.know) do
			local name = SpellName(id)
			if name and knownSpells[name] then
				known = true
			end
		end
		local matched
		for _, key in ipairs(catalogOrder) do
			local entry = catalog[key]
			for name in pairs(auraNames) do
				if entry.auraNames[name] then
					matched = entry
					break
				end
			end
			if matched then
				break
			end
		end
		if matched then
			for name in pairs(auraNames) do
				matched.auraNames[name] = true
			end
			for _, name in ipairs(castNames) do
				if not tContains(matched.castNames, name) then
					matched.castNames[#matched.castNames + 1] = name
				end
			end
			matched.mana = matched.mana or seed.mana
			matched.seedDefault = seed.default ~= false
			matched.party = matched.party or seed.scope == "party"
		elseif known then
			local firstName = seed.label or SpellName(seed.cast[1]) or SpellName(seed.auras[1])
			AddEntry({
				key = "spell:" .. firstName, name = firstName, icon = SpellIcon(seed.cast[1]), kind = "aura", source = "seed",
				auraNames = auraNames, castNames = castNames, party = seed.scope == "party", mana = seed.mana,
				unlessNames = {}, seedDefault = seed.default ~= false,
			})
		end
	end

	-- Flask and elixir buff names, by family.
	wipe(FLASK_NAMES)
	for _, spellID in pairs(FLASKS) do
		local name = SpellName(spellID)
		if name then
			FLASK_NAMES[name] = true
		end
	end
	wipe(ELIXIR_FAMILY_NAMES)
	for _, elixir in pairs(ELIXIRS) do
		local name = SpellName(elixir[1])
		if name then
			ELIXIR_FAMILY_NAMES[elixir[2]] = ELIXIR_FAMILY_NAMES[elixir[2]] or {}
			ELIXIR_FAMILY_NAMES[elixir[2]][name] = true
		end
	end

	-- Everyone: a food buff and the weapon enchants. Eating or drinking
	-- right now excuses the missing food buff.
	local wellFed = SpellName(WELL_FED) or "Well Fed"
	local eating = { [SpellName(FOOD) or "Food"] = true, [SpellName(430) or "Drink"] = true }
	for _, spellID in ipairs(EATING_SPELLS) do
		local name = SpellName(spellID)
		if name then
			eating[name] = true
		end
	end
	AddEntry({
		key = "food", name = wellFed, icon = SpellIcon(WELL_FED), kind = "food", source = "extra",
		auraNames = { [wellFed] = true }, castNames = {}, party = false, unlessNames = eating, seedDefault = true,
	})
	local function WeaponIcon(slot)
		local ok, icon = pcall(GetInventoryItemTexture, "player", slot)
		if ok and icon then
			return icon
		end
		local okItem, itemIcon = pcall(function()
			return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(2862)
		end)
		return okItem and itemIcon or QUESTION_MARK
	end
	AddEntry({
		key = "flask", name = "Flask", icon = SpellIcon(17626), kind = "flask", source = "extra",
		auraNames = {}, castNames = {}, party = false, unlessNames = {}, seedDefault = true,
	})
	AddEntry({
		key = "elixir", name = "Elixirs", icon = SpellIcon(17538), kind = "elixir", source = "extra",
		auraNames = {}, castNames = {}, party = false, unlessNames = {}, seedDefault = true,
	})
	AddEntry({
		key = "weapon", name = "Weapon enchant", icon = WeaponIcon(MAIN_HAND), kind = "weapon", source = "extra",
		auraNames = {}, castNames = {}, party = false, unlessNames = {}, seedDefault = true,
	})
	AddEntry({
		key = "offhand", name = "Off-hand enchant", icon = WeaponIcon(OFF_HAND), kind = "offhand", source = "extra",
		auraNames = {}, castNames = {}, party = false, unlessNames = {}, seedDefault = true,
	})
end

-- A new character starts with the class buffs this file knows, food and
-- the weapon enchants.
-- Each default is offered once per character: added the first time it is
-- seen, and left alone afterwards, so removing one sticks.
local function SeedChoices()
	if not cdb.offered then
		cdb.offered = {}
		if cdb.seeded then
			-- Seeded by an earlier version: count everything it had as
			-- offered, except the entries added since.
			for _, key in ipairs(catalogOrder) do
				if key ~= "flask" and key ~= "elixir" then
					cdb.offered[key] = true
				end
			end
		end
	end
	cdb.seeded = true
	for _, key in ipairs(catalogOrder) do
		local entry = catalog[key]
		if entry.seedDefault and not cdb.offered[key] then
			cdb.offered[key] = true
			cdb.nag[key] = { party = entry.party }
		end
	end
end


------------------------------------------------------------------------------
-- Looking at units
------------------------------------------------------------------------------

-- Seconds before the end at which a buff of this duration counts as
-- running out.
local function SoonFor(duration)
	if not duration or duration <= 0 then
		return db.soonMax
	end
	return math.max(db.soonMin, math.min(db.soonMax, duration * db.soonShare))
end

-- Whether a unit has one of the named buffs with enough time left; nil when
-- the game would not let us look. "soon" true applies the running-out
-- margin; false or 0 accepts any time left. The second value says whether
-- the buff is there at all, so a running-out buff can be told from none.
local function UnitHas(unit, names, soon)
	if not next(names) then
		return false, false
	end
	local found, present = false, false
	local ok = pcall(function()
		local now = GetTime()
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			for i = 1, 80 do
				local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
				if not aura then
					break
				end
				if names[aura.name] then
					present = true
					local left = aura.expirationTime and aura.expirationTime > 0 and (aura.expirationTime - now) or math.huge
					local margin = (soon and soon ~= 0) and SoonFor(aura.duration) or 0
					if left > margin then
						found = true
						return
					end
				end
			end
		else
			for i = 1, 80 do
				local name, _, _, _, duration, expirationTime = UnitBuff(unit, i, "HELPFUL")
				if not name then
					break
				end
				if names[name] then
					present = true
					local left = expirationTime and expirationTime > 0 and (expirationTime - now) or math.huge
					local margin = (soon and soon ~= 0) and SoonFor(duration) or 0
					if left > margin then
						found = true
						return
					end
				end
			end
		end
	end)
	if not ok then
		return nil
	end
	return found, present
end

local function UnitUsable(unit)
	if unit == "player" then
		return true
	end
	local ok, usable = pcall(function()
		if not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
			return false
		end
		if UnitInRange then
			local inRange, checked = UnitInRange(unit)
			if checked and not inRange then
				return false
			end
		end
		return true
	end)
	return ok and usable
end

local function UnitHasMana(unit)
	local ok, mana = pcall(function()
		return UnitPowerType(unit) == (Enum.PowerType and Enum.PowerType.Mana or 0)
	end)
	return ok and mana
end

local function ShortName(unit)
	if unit == "player" then
		return "you"
	end
	local ok, name = pcall(function()
		local name = UnitName(unit)
		local _, class = UnitClass(unit)
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then
			return ("|c%s%s|r"):format(color.colorStr or "ffffffff", name)
		end
		return name
	end)
	return ok and name or unit
end

-- A weapon (not a fishing pole) in the slot with no temporary enchant.
local function WeaponMissing(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID or IsSecret(itemID) then
		return false
	end
	local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, _, _, classID, subclassID = getInfo(itemID)
	if classID ~= WEAPON or subclassID == FISHING_POLE then
		return false
	end
	local ok, has, expires = pcall(function()
		local hasMain, mainExpires, _, _, hasOff, offExpires = GetWeaponEnchantInfo()
		if slot == MAIN_HAND then
			return hasMain, mainExpires
		end
		return hasOff, offExpires
	end)
	if not ok then
		return false
	end
	if not has then
		return true, false
	end
	local low = expires ~= nil and expires > 0 and expires / 1000 <= db.soonMax
	return low, low -- missing, and running out rather than absent
end

local function ItemLook(itemID)
	local okIcon, icon = pcall(function()
		return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
	end)
	local okName, name = pcall(function()
		return C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID) or GetItemInfo and GetItemInfo(itemID)
	end)
	return okIcon and icon or nil, okName and name or ("item " .. itemID)
end

-- Calls fn(itemID) for every item in the bags, until it returns true.
local function EachBagItem(fn)
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local itemAt = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	if not (numSlots and itemAt) then
		return
	end
	for bag = 0, NUM_BAGS do
		for bagSlot = 1, numSlots(bag) or 0 do
			local itemID = itemAt(bag, bagSlot)
			if itemID and not IsSecret(itemID) and fn(itemID) then
				return
			end
		end
	end
end

-- What could go on the weapon in a slot: a known imbue spell (main hand
-- only), or an item in the bags that fits the weapon's type. Nothing to
-- apply means nothing to nag about.
local function WeaponCandidates(slot)
	local list = {}
	if slot == MAIN_HAND then
		for _, id in ipairs(IMBUES) do
			local name = SpellName(id)
			if name and knownSpells[name] then
				list[#list + 1] = { kind = "spell", value = name, icon = SpellIcon(id), text = name, slot = slot }
			end
		end
	end
	local itemID = GetInventoryItemID("player", slot)
	if not itemID or IsSecret(itemID) then
		return list
	end
	local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, _, _, _, subclassID = getInfo(itemID)
	if not subclassID or IsSecret(subclassID) then
		return list
	end
	local bitOf = bit.lshift(1, subclassID)
	local seen = {}
	EachBagItem(function(bagItem)
		local mask = WEAPON_ITEMS[bagItem]
		if mask and not seen[bagItem] and (mask == 0 or bit.band(mask, bitOf) ~= 0) then
			seen[bagItem] = true
			local icon, name = ItemLook(bagItem)
			list[#list + 1] = { kind = "item", value = bagItem, icon = icon, text = name, slot = slot }
		end
	end)
	return list
end

-- Well Fed missing, not eating, and food that gives it in the bags.
local function FoodCandidates(entry)
	local list = {}
	local enough, present = UnitHas("player", entry.auraNames, true)
	entry.expiring = present and not enough
	if enough ~= false or UnitHas("player", entry.unlessNames, 0) ~= false then
		return list
	end
	local seen = {}
	EachBagItem(function(itemID)
		if FOODS[itemID] and not seen[itemID] then
			seen[itemID] = true
			local icon, name = ItemLook(itemID)
			list[#list + 1] = { kind = "item", value = itemID, icon = icon, text = name, eat = true }
		end
	end)
	return list
end

-- No flask up (or nearly out) and one in the bags: the fix to drink.
local function FlaskCandidates(entry)
	local list = {}
	local enough, present = UnitHas("player", FLASK_NAMES, true)
	entry.expiring = present and not enough
	if enough ~= false then
		return list
	end
	local seen = {}
	EachBagItem(function(itemID)
		if FLASKS[itemID] and not seen[itemID] then
			seen[itemID] = true
			local icon, name = ItemLook(itemID)
			list[#list + 1] = { kind = "item", value = itemID, icon = icon, text = name }
		end
	end)
	return list
end

-- Elixir families in the bags whose buff is not up: the first to drink,
-- and how many there are.
local function ElixirCandidates(entry)
	local list, families = {}, {}
	local allExpiring = true
	EachBagItem(function(itemID)
		local elixir = ELIXIRS[itemID]
		if elixir and not families[elixir[2]] then
			local names = ELIXIR_FAMILY_NAMES[elixir[2]]
			local enough, present = UnitHas("player", names or {}, true)
			if names and enough == false then
				allExpiring = allExpiring and present
				families[elixir[2]] = true
				local icon, name = ItemLook(itemID)
				list[#list + 1] = { kind = "item", value = itemID, icon = icon, text = name }
			end
		end
	end)
	entry.expiring = #list > 0 and allExpiring
	return list
end

-- The candidate to act on: the one the player picked for this entry by
-- right-clicking, when it is at hand, otherwise the first.
local function Pick(entry, list)
	entry.candidates = list
	if #list == 0 then
		return nil, 0
	end
	local want = cdb.prefer[entry.key]
	for i, candidate in ipairs(list) do
		if candidate.value == want then
			return candidate, i
		end
	end
	return list[1], 1
end

-- Right-click: the next candidate becomes the preferred one.
local function CycleCandidate(entry)
	local list = entry.candidates
	if not list or #list < 2 then
		return
	end
	local index = entry.fixIndex or 1
	local nextCandidate = list[index % #list + 1]
	cdb.prefer[entry.key] = nextCandidate.value
end

-- Moments when buffs are nobody's concern.
local function Idle()
	local ok, idle = pcall(function()
		return UnitIsDeadOrGhost("player") or (IsResting and IsResting()) or (IsMounted and IsMounted()) or UnitOnTaxi("player")
	end)
	return ok and idle
end

------------------------------------------------------------------------------
-- The sound
------------------------------------------------------------------------------

local function Ping()
	if not nagging then
		return
	end
	PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
	C_Timer.After(db.pingGap, Ping)
end

local function StartNag()
	if nagging then
		return
	end
	nagging = true
	Ping()
end

local function StopNag()
	nagging = false
end

------------------------------------------------------------------------------
-- Icons in the Cooldown Manager's style
------------------------------------------------------------------------------

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- The Cooldown Manager's own icon dressing: its rounded mask and border
-- overlay, uncropped, as in CooldownViewerBuffIconItemTemplate. A plain
-- dark edge stands in on a client without those atlases.
local function StyleIcon(button)
	button:SetSize(ICON, ICON)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button.Icon = icon
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = button:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints()
		icon:AddMaskTexture(mask)
		local overlay = button:CreateTexture(nil, "OVERLAY")
		overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		overlay:SetPoint("TOPLEFT", -8, 7)
		overlay:SetPoint("BOTTOMRIGHT", 8, -7)
	else
		local edge = button:CreateTexture(nil, "BACKGROUND")
		edge:SetColorTexture(0, 0, 0, 0.9)
		edge:SetPoint("TOPLEFT", -1.5, 1.5)
		edge:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
	end
	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.Count = count
	local party = button:CreateTexture(nil, "OVERLAY", nil, 2)
	party:SetSize(16, 16)
	party:SetPoint("TOPLEFT", -4, 4)
	if not pcall(party.SetAtlas, party, "socialqueuing-icon-group") then
		party:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
	end
	party:Hide()
	button.Party = party
end

-- A soft pulsing glow around a bar icon, to catch the eye.

-- The Cooldown Manager's own effects, made from its templates: the
-- "visual alert" flash or marching ants (in the game's five colours) for
-- a missing buff, and its pandemic border for one that is running out.
local GLOW_TEMPLATES = {
	flash = { gold = "VisualAlertFlashBaseTemplate", cyan = "VisualAlertFlashCyanTemplate", red = "VisualAlertFlashRedTemplate",
		green = "VisualAlertFlashGreenTemplate", blue = "VisualAlertFlashBlueTemplate" },
	ants = { gold = "VisualAlertMarchingAntsBaseTemplate", cyan = "VisualAlertMarchingAntsCyanTemplate", red = "VisualAlertMarchingAntsRedTemplate",
		green = "VisualAlertMarchingAntsGreenTemplate", blue = "VisualAlertMarchingAntsBlueTemplate" },
}
local PANDEMIC_TEMPLATE = "CooldownPandemicFXTemplate"

local function GlowFrame(button, template)
	button.glows = button.glows or {}
	local frame = button.glows[template]
	if frame == nil then
		local ok, made = pcall(CreateFrame, "Frame", nil, button, template)
		if ok and made then
			frame = made
			if template == PANDEMIC_TEMPLATE then
				frame:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 6)
				frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
			else
				-- Alerts normally live for two seconds and hand themselves
				-- back to the game's manager; ours stay as long as shown.
				if frame.SetManualRelease then
					frame:SetManualRelease(true)
				end
				frame:SetScript("OnUpdate", nil)
				frame:SetPoint("TOPLEFT", button, "TOPLEFT", -8, 8)
				frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 9, -9)
			end
			frame:SetFrameLevel(button:GetFrameLevel() + 2)
			frame:Hide()
		else
			frame = false
		end
		button.glows[template] = frame
	end
	return frame or nil
end

-- state: "missing", "expiring" or nil.
local function ShowGlow(button, state)
	local want
	if state == "expiring" and db.expiringGlow then
		want = PANDEMIC_TEMPLATE
	elseif state and db.glow ~= "off" then
		local styles = GLOW_TEMPLATES[db.glow] or GLOW_TEMPLATES.flash
		want = styles[db.glowColor] or styles.gold
	end
	for template, frame in pairs(button.glows or {}) do
		if frame and template ~= want then
			frame:Hide()
		end
	end
	if want then
		local frame = GlowFrame(button, want)
		if frame then
			frame:Show()
		end
	end
end

------------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------------

local bar = CreateFrame("Frame", "BuffNagBar", UIParent)
bar:SetSize(ICON, ICON)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:Hide()

local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", bar, "TOP", 0, 6)
label:SetText("BuffNag: drag to move")

local icons = {}

local function SavePosition()
	local point, _, _, x, y = bar:GetPoint(1)
	db.point = { point, x, y }
end

local function OnDragStart()
	if not db.locked and not InCombatLockdown() then
		bar:StartMoving()
	end
end

local function OnDragStop()
	bar:StopMovingOrSizing()
	SavePosition()
end

bar:SetScript("OnDragStart", OnDragStart)
bar:SetScript("OnDragStop", OnDragStop)

local Refresh -- defined below; the icons' right-click needs it

local function IconTooltip(button)
	if not button.entry then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
	GameTooltip:SetText(button.entry.name)
	if button.missingText then
		GameTooltip:AddLine("Missing: " .. button.missingText, 1, 1, 1, true)
	end
	if button.applyText then
		GameTooltip:AddLine(button.applyText, 0.6, 0.6, 0.6)
	end
	if button.nextText then
		GameTooltip:AddLine(button.nextText, 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local function BarIcon(i)
	if icons[i] then
		return icons[i]
	end
	local button = CreateFrame("Button", "BuffNagIcon" .. i, bar, "SecureActionButtonTemplate")
	StyleIcon(button)
	button:SetPoint("LEFT", bar, "LEFT", (i - 1) * (ICON + GAP), 0)
	button:RegisterForClicks("AnyDown", "AnyUp")
	-- The right button does nothing secure; it picks the next candidate.
	button:SetAttribute("type2", "none")
	button:SetScript("PostClick", function(self, mouseButton, down)
		if mouseButton == "RightButton" and not down and self.entry and not InCombatLockdown() then
			CycleCandidate(self.entry)
			PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
			Refresh()
			if GameTooltip:GetOwner() == self then
				IconTooltip(self)
			end
		end
	end)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", OnDragStart)
	button:SetScript("OnDragStop", OnDragStop)
	button:SetScript("OnEnter", IconTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	icons[i] = button
	return button
end

local function ApplyLayout()
	bar:SetScale(db.scale)
	bar:ClearAllPoints()
	bar:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
	label:SetShown(not db.locked)
end

-- The units lacking an entry's buff.
local function Missing(entry, choice)
	local missing = {}
	if entry.kind == "flask" or entry.kind == "elixir" or entry.kind == "food" or entry.kind == "weapon" or entry.kind == "offhand" then
		local list
		if entry.kind == "flask" then
			list = FlaskCandidates(entry)
		elseif entry.kind == "elixir" then
			list = ElixirCandidates(entry)
		elseif entry.kind == "food" then
			list = FoodCandidates(entry)
		else
			local slot = entry.kind == "weapon" and MAIN_HAND or OFF_HAND
			local missingEnchant, expiring = WeaponMissing(slot)
			entry.expiring = expiring
			list = missingEnchant and WeaponCandidates(slot) or {}
		end
		entry.fix, entry.fixIndex = Pick(entry, list)
		if entry.fix then
			if entry.kind == "elixir" then
				-- Every missing family counts, not just the one to drink first.
				local labels = {}
				for i, candidate in ipairs(list) do
					labels[i] = candidate.text
				end
				entry.fix.count, entry.fix.list = #list, table.concat(labels, ", ")
			else
				entry.fix.count, entry.fix.list = 1, entry.fix.text
			end
			missing[1] = "player"
		end
		return missing
	end
	-- A buff cast by spell: which spell, when there is a choice (Aspects,
	-- armours, Blessings).
	local list = {}
	for _, name in ipairs(entry.castNames) do
		if knownSpells[name] or (entry.game and #list == 0) then
			list[#list + 1] = { kind = "cast", value = name, icon = SpellIcon(name), text = name }
		end
	end
	entry.fix, entry.fixIndex = Pick(entry, list)
	local inRaid = IsInRaid and IsInRaid()
	local units = (choice.party and db.party and not inRaid) and PARTY_UNITS or { "player" }
	local allExpiring = true
	for _, unit in ipairs(units) do
		if UnitUsable(unit) and (not entry.mana or UnitHasMana(unit)) then
			local has, present = UnitHas(unit, entry.auraNames, true)
			if has == false and not UnitHas(unit, entry.unlessNames, 0) then
				missing[#missing + 1] = unit
				allExpiring = allExpiring and present
			end
		end
	end
	entry.expiring = #missing > 0 and allExpiring
	return missing
end

function Refresh()
	refreshPending = false
	if InCombatLockdown() then
		return
	end
	if Idle() and not previewing then
		bar:Hide()
		StopNag()
		return
	end
	local count = 0
	for _, key in ipairs(catalogOrder) do
		local entry, choice = catalog[key], cdb.nag[key]
		if choice and count < MAX_ICONS then
			local missing = previewing and { "player" } or Missing(entry, choice)
			if #missing > 0 then
				count = count + 1
				local button = BarIcon(count)
				button.entry = entry
				local manyChoices = entry.candidates and #entry.candidates > 1
				button.Icon:SetTexture((entry.fix and (manyChoices or entry.fix.kind ~= "cast") and entry.fix.icon) or entry.icon or QUESTION_MARK)
				local shown = (entry.fix and entry.fix.count) or #missing
				button.Count:SetText(shown > 1 and tostring(shown) or "")
				button.Party:SetShown(choice.party and true or false)
				ShowGlow(button, (previewing or not entry.expiring) and "missing" or "expiring")
				local names = {}
				for i, unit in ipairs(missing) do
					names[i] = ShortName(unit)
				end
				button.missingText = (entry.fix and entry.fix.list) or table.concat(names, ", ")
				button.applyText = nil
				button.nextText = nil
				if manyChoices then
					local nextCandidate = entry.candidates[(entry.fixIndex or 1) % #entry.candidates + 1]
					button.nextText = ("Right-click for the next of %d: %s."):format(#entry.candidates, nextCandidate.text)
				end
				if entry.fix and entry.fix.kind == "spell" then
					button:SetAttribute("type", "spell")
					button:SetAttribute("spell", entry.fix.value)
					button:SetAttribute("unit", "player")
					button.applyText = "Click to cast " .. entry.fix.text .. "."
				elseif entry.fix and entry.fix.kind == "item" then
					button:SetAttribute("type", "macro")
					if entry.fix.slot then
						button:SetAttribute("macrotext", ("/use item:%d\n/use %d"):format(entry.fix.value, entry.fix.slot))
						button.applyText = "Click to apply " .. entry.fix.text .. "."
					else
						button:SetAttribute("macrotext", ("/use item:%d"):format(entry.fix.value))
						button.applyText = (entry.fix.eat and "Click to eat " or "Click to drink ") .. entry.fix.text .. "."
					end
				elseif entry.fix and entry.fix.kind == "cast" then
					button:SetAttribute("type", "spell")
					button:SetAttribute("spell", entry.fix.value)
					button:SetAttribute("unit", missing[1])
					button.applyText = ("Click to cast %s on the first one."):format(entry.fix.text)
				else
					button:SetAttribute("type", nil)
				end
				button:Show()
			end
		end
	end
	for i = count + 1, #icons do
		icons[i]:Hide()
	end
	bar:SetWidth(math.max(ICON, count * (ICON + GAP) - GAP))
	bar:SetShown(count > 0)
	if count > 0 and not previewing and db.sound then
		StartNag()
	else
		StopNag()
	end
end

local function Schedule(delay)
	if refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(delay or 0.3, Refresh)
end

------------------------------------------------------------------------------
-- The tab in the Cooldown Manager's settings
------------------------------------------------------------------------------

local panel -- our page inside the settings window
local settingsTab
local COLUMNS = 7

-- Taint: nothing here may write into the game's own tables (the settings
-- window's fields, its tab list), or the game's code reading them later
-- runs tainted and its protected tables refuse it. The tab lives on a
-- frame of ours, the window's own state is only read, and the window's
-- pages are shown or hidden from hooks that run after its own code.

local function ShowGamePages(settings)
	local mode = settings.displayMode
	if settings.CooldownScroll then
		settings.CooldownScroll:SetShown(mode ~= "groupBuffs")
	end
	if settings.GroupBuffFilter then
		settings.GroupBuffFilter:SetShown(mode == "groupBuffs")
	end
end

local function ShowPanel()
	local settings = CooldownViewerSettings
	if not (settings and panel) then
		return
	end
	for _, tab in ipairs(settings.TabButtons or {}) do
		tab:SetChecked(false)
	end
	if settingsTab then
		settingsTab:SetChecked(true)
	end
	if settings.CooldownScroll then
		settings.CooldownScroll:Hide()
	end
	if settings.GroupBuffFilter then
		settings.GroupBuffFilter:Hide()
	end
	if CooldownViewerSettingsEditAlert then
		CooldownViewerSettingsEditAlert:Hide()
	end
	panel:Show()
end

local function BuildPanel(settings)
	panel = CreateFrame("Frame", "BuffNagSettingsPanel", settings)
	panel:SetPoint("TOPLEFT", 17, -72)
	panel:SetPoint("BOTTOMRIGHT", -30, 29)
	panel:Hide()

	-- Options along the top.
	local function Checkbox(text, x, get, set)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(24, 24)
		box:SetPoint("TOPLEFT", x, 0)
		local caption = box.Text or box.text
		if caption then
			caption:SetText(text)
			caption:SetFontObject("GameFontHighlightSmall")
		end
		box:SetScript("OnShow", function(self)
			self:SetChecked(get())
		end)
		box:SetScript("OnClick", function(self)
			set(self:GetChecked() and true or false)
			if not InCombatLockdown() then
				ApplyLayout()
				Refresh()
			end
		end)
		return box
	end
	Checkbox("Sound", 0, function() return db.sound end, function(v) db.sound = v end)
	Checkbox("Party", 80, function() return db.party end, function(v) db.party = v end)
	Checkbox("Lock bar", 160, function() return db.locked end, function(v) db.locked = v end)
	Checkbox("Glow", 250, function() return db.glow ~= "off" end, function(v) db.glow = v and "flash" or "off" end)
	local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	test:SetSize(70, 22)
	test:SetPoint("TOPRIGHT", 0, -1)
	test:SetText("Show bar")
	test:SetScript("OnClick", function()
		previewing = not previewing
		test:SetText(previewing and "Hide bar" or "Show bar")
		if not InCombatLockdown() then
			Refresh()
		end
	end)

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 4, -28)
	help:SetPoint("RIGHT", -4, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Click a buff to move it between the lists. Right-click a watched buff to also watch your party for it.")

	-- The two lists, in a scroll frame.
	local scroll
	local okScroll = pcall(function()
		scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	end)
	if not okScroll or not scroll then
		scroll = CreateFrame("ScrollFrame", nil, panel)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local range = math.max(0, self:GetScrollChild():GetHeight() - self:GetHeight())
			self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	scroll:SetPoint("TOPLEFT", 0, -58)
	scroll:SetPoint("BOTTOMRIGHT", -16, 0)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(300, 1)
	scroll:SetScrollChild(content)
	panel.content = content

	local headers = {}
	for i = 1, 2 do
		local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header:SetJustifyH("LEFT")
		headers[i] = header
	end
	headers[1]:SetText("Nag when missing")
	headers[2]:SetText("Available")

	local buttons = {}
	local function PanelButton(i)
		if buttons[i] then
			return buttons[i]
		end
		local button = CreateFrame("Button", nil, content)
		StyleIcon(button)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.entry.name)
			local choice = cdb.nag[self.entry.key]
			if choice then
				GameTooltip:AddLine(choice.party and "Watched on you and your party." or "Watched on you.", 1, 1, 1)
				GameTooltip:AddLine("Click to stop watching; right-click to toggle the party.", 0.6, 0.6, 0.6, true)
			else
				GameTooltip:AddLine("Click to watch.", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:SetScript("OnClick", function(self, mouseButton)
			local key = self.entry.key
			if mouseButton == "RightButton" then
				if cdb.nag[key] then
					cdb.nag[key].party = not cdb.nag[key].party
				end
			elseif cdb.nag[key] then
				cdb.nag[key] = nil
			else
				cdb.nag[key] = { party = self.entry.party }
			end
			PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
			panel:Layout()
			if not InCombatLockdown() then
				Refresh()
			end
		end)
		buttons[i] = button
		return button
	end

	function panel:Layout()
		local used = 0
		local y = 0
		local step = ICON + 8
		local function Section(index, keys)
			headers[index]:ClearAllPoints()
			headers[index]:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
			y = y + 22
			if #keys == 0 then
				y = y + 8
			end
			for n, key in ipairs(keys) do
				used = used + 1
				local button = PanelButton(used)
				button.entry = catalog[key]
				button.Icon:SetTexture(button.entry.icon or QUESTION_MARK)
				local choice = cdb.nag[key]
				button.Party:SetShown(choice and choice.party and true or false)
				button.Icon:SetDesaturated(index == 2)
				local column, row = (n - 1) % COLUMNS, math.floor((n - 1) / COLUMNS)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + column * step, -(y + row * step))
				button:Show()
			end
			y = y + math.ceil(#keys / COLUMNS) * step + 16
		end
		local chosen, available = {}, {}
		for _, key in ipairs(catalogOrder) do
			if cdb.nag[key] then
				chosen[#chosen + 1] = key
			else
				available[#available + 1] = key
			end
		end
		Section(1, chosen)
		Section(2, available)
		for i = used + 1, #buttons do
			buttons[i]:Hide()
		end
		content:SetSize(math.max(300, scroll:GetWidth()), math.max(1, y))
	end

	panel:SetScript("OnShow", function(self)
		self:Layout()
	end)
	panel:SetScript("OnHide", function()
		if previewing then
			previewing = false
			test:SetText("Show bar")
			if not InCombatLockdown() then
				Refresh()
			end
		end
	end)
end

local function HookSettings()
	local settings = CooldownViewerSettings
	if not settings or settingsTab then
		return
	end
	BuildPanel(settings)

	-- The tab: made from the game's own tab template for the look, but
	-- parented to a frame of ours so the template does not add it to the
	-- window's tab list.
	local holder = CreateFrame("Frame", "BuffNagSettingsTabHolder", settings)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT")
	local ok = pcall(function()
		settingsTab = CreateFrame("Frame", "BuffNagSettingsTab", holder, "CooldownViewerSettingsTabTemplate")
	end)
	if not ok or not settingsTab then
		settingsTab = nil
		Print("could not add a tab to the Cooldown Manager settings; use /bn to configure")
		return
	end
	settingsTab.tooltipText = "BuffNag: buffs to nag about when missing"
	local anchor = settings.GroupBuffsTab or settings.AurasTab or settings.SpellsTab
	if anchor then
		settingsTab:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
	else
		settingsTab:SetPoint("TOPLEFT", settings, "TOPRIGHT", 0, -200)
	end
	settingsTab.Icon:SetSize(34, 34)
	local _, class = UnitClass("player")
	local atlas = class and ("classicon-" .. class:lower())
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		settingsTab.Icon:SetAtlas(atlas)
	elseif class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
		settingsTab.Icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		settingsTab.Icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
	else
		settingsTab.Icon:SetTexture(SpellIcon(1243))
		settingsTab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	settingsTab:SetChecked(false)
	if settingsTab.SetCustomOnMouseUpHandler then
		settingsTab:SetCustomOnMouseUpHandler(function(_, button, upInside)
			if button == "LeftButton" and upInside then
				ShowPanel()
			end
		end)
	end
	-- A click on one of the game's tabs runs SetDisplayMode, even when it
	-- is the tab that was already current and the game returns early: put
	-- its page back and ours away. Closing the window does the same, so it
	-- reopens on the game's page as usual.
	hooksecurefunc(settings, "SetDisplayMode", function(self)
		if panel:IsShown() then
			panel:Hide()
			settingsTab:SetChecked(false)
			ShowGamePages(self)
			for _, tab in ipairs(self.TabButtons or {}) do
				tab:SetChecked(tab.displayMode == self.displayMode)
			end
		end
	end)
	settings:HookScript("OnHide", function(self)
		if panel:IsShown() then
			panel:Hide()
			settingsTab:SetChecked(false)
			ShowGamePages(self)
		end
	end)
end

local function OpenSettings()
	if not CooldownViewerSettings then
		Print("the Cooldown Manager is not available on this client")
		return
	end
	HookSettings()
	if not CooldownViewerSettings:IsShown() then
		ShowUIPanel(CooldownViewerSettings)
	end
	ShowPanel()
end

------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------

SLASH_BUFFNAG1 = "/bn"
SLASH_BUFFNAG2 = "/buffnag"
SlashCmdList.BUFFNAG = function(msg)
	local word, rest = msg:lower():match("^%s*(%S*)%s*(%S*)")
	if word == "" or word == "config" or word == "options" then
		OpenSettings()
		return
	elseif word == "lock" or word == "unlock" then
		db.locked = word == "lock"
	elseif word == "party" then
		db.party = rest ~= "off"
	elseif word == "glow" then
		if rest == "flash" or rest == "ants" or rest == "off" then
			db.glow = rest
		elseif rest == "on" then
			db.glow = "flash"
		else
			Print("/bn glow flash|ants|off; /bn glowcolor gold|cyan|red|green|blue; /bn expiring on|off")
			return
		end
	elseif word == "glowcolor" then
		if GLOW_TEMPLATES.flash[rest] then
			db.glowColor = rest
		else
			Print("/bn glowcolor gold|cyan|red|green|blue")
			return
		end
	elseif word == "expiring" then
		db.expiringGlow = rest ~= "off"
	elseif word == "sound" then
		db.sound = rest ~= "off"
		if not db.sound then
			StopNag()
		end
	elseif word == "gap" then
		db.pingGap = math.max(0.1, math.min(10, tonumber(rest) or 0.4))
	elseif word == "soon" then
		db.soonMax = math.max(0, math.min(1800, tonumber(rest) or 120))
	elseif word == "soonmin" then
		db.soonMin = math.max(0, math.min(db.soonMax, tonumber(rest) or 30))
	elseif word == "soonshare" then
		db.soonShare = math.max(0, math.min(1, (tonumber(rest) or 10) / 100))
	elseif word == "scale" then
		db.scale = math.max(0.5, math.min(3, tonumber(rest) or 1))
	elseif word == "reset" then
		db.point = { DEFAULTS.point[1], DEFAULTS.point[2], DEFAULTS.point[3] }
	elseif word == "test" then
		previewing = not previewing
		Print("bar preview %s", previewing and "on" or "off")
	elseif word == "list" then
		Print("watching:")
		for _, key in ipairs(catalogOrder) do
			local choice = cdb.nag[key]
			if choice then
				Print("  %s%s", catalog[key].name, choice.party and " (and party)" or "")
			end
		end
		return
	else
		Print("/bn opens the settings; /bn list; /bn lock|unlock; /bn party on|off; /bn sound on|off; /bn glow flash|ants|off; /bn glowcolor <colour>; /bn expiring on|off; /bn gap <seconds>; /bn soon <max seconds>; /bn soonmin <seconds>; /bn soonshare <percent>; /bn scale <n>; /bn test; /bn reset")
		return
	end
	if InCombatLockdown() then
		Print("changes apply after combat")
	else
		ApplyLayout()
		Refresh()
	end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local function Rebuild()
	ScanSpellbook()
	BuildCatalog()
	SeedChoices()
	if panel and panel:IsShown() then
		panel:Layout()
	end
	if not InCombatLockdown() then
		Schedule()
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:RegisterEvent("SPELLS_CHANGED")
loader:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
loader:RegisterEvent("PLAYER_ALIVE")
loader:RegisterEvent("PLAYER_UNGHOST")
loader:RegisterEvent("PLAYER_UPDATE_RESTING")
loader:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
loader:RegisterEvent("PLAYER_CONTROL_GAINED")
loader:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(loader.RegisterEvent, loader, "COOLDOWN_VIEWER_DATA_LOADED")
loader:RegisterUnitEvent("UNIT_AURA", "player", "party1", "party2", "party3", "party4")
loader:SetScript("OnEvent", function(self, event, arg)
	if event == "ADDON_LOADED" then
		if arg == ADDON_NAME then
			BuffNagDB = BuffNagDB or {}
			db = BuffNagDB
			db.off, db.pings = nil, nil -- from earlier versions
			if type(db.sound) == "number" then
				db.sound = db.sound > 0
			end
			db.soon = nil -- replaced by soonShare/soonMax/soonMin
			if db.glow == true then
				db.glow = "flash"
			elseif db.glow == false then
				db.glow = "off"
			end
			for key, value in pairs(DEFAULTS) do
				if db[key] == nil then
					db[key] = type(value) == "table" and CopyTable(value) or value
				end
			end
			BuffNagCharDB = BuffNagCharDB or {}
			cdb = BuffNagCharDB
			cdb.nag = cdb.nag or {}
			cdb.prefer = cdb.prefer or {} -- entry key -> item or spell picked by right-click
		elseif arg == "Blizzard_CooldownViewer" and db then
			HookSettings()
		end
	elseif event == "PLAYER_LOGIN" then
		Rebuild()
		ApplyLayout()
		HookSettings()
		-- Temporary weapon enchants and running-out buffs have no event of
		-- their own: look every few seconds.
		C_Timer.NewTicker(3, function()
			if not InCombatLockdown() then
				Schedule(0)
			end
		end)
	elseif event == "PLAYER_REGEN_DISABLED" then
		bar:Hide()
		StopNag()
	elseif event == "SPELLS_CHANGED" or event == "COOLDOWN_VIEWER_DATA_LOADED" then
		Rebuild()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if arg == MAIN_HAND or arg == OFF_HAND then
			local weapon, offhand = catalog.weapon, catalog.offhand
			if weapon then
				weapon.icon = GetInventoryItemTexture("player", MAIN_HAND) or weapon.icon
			end
			if offhand then
				offhand.icon = GetInventoryItemTexture("player", OFF_HAND) or offhand.icon
			end
		end
		if not InCombatLockdown() then
			Schedule()
		end
	elseif not InCombatLockdown() then
		Schedule()
	end
end)
