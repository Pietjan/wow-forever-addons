-- BuffNag: the Cooldown Manager shows a buff's icon while the buff is up.
-- This does the reverse: a bar of icons for the buffs you chose that are
-- missing, on you or on your party, with the minimap ping on a loop until
-- they are back. Click an icon to cast the buff on the first one lacking it.
--
-- It is configured from its own tab in the Cooldown Manager's settings
-- window (Escape > Options > Cooldown Manager, or /bn): the buffs on offer
-- are the ones the game lists for your class there, the group buffs it
-- knows, a food buff and weapon enchants (shown only when a stone, oil,
-- poison or imbue spell is at hand to put on). Buffs are matched by name,
-- so any rank counts. The bar hides in combat, while resting, mounted, on a
-- flight path or dead.

local ADDON_NAME = ...

local IsSecret = issecretvalue or function() return false end

local DEFAULTS = { -- account wide: the bar and the sound
	party = true, -- also look at party members, for buffs marked for the party
	soon = 30, -- seconds left at which a buff counts as missing
	sound = true, -- ping while something is missing
	pingGap = 0.4, -- seconds between pings
	scale = 1,
	locked = false,
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

	-- Buffs the Cooldown Manager can track for the class: buffs on you.
	if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and Enum.CooldownViewerCategory then
		local categories = Enum.CooldownViewerCategory
		for _, category in ipairs({ categories.TrackedBuff, categories.TrackedBar, categories.SpecAgnosticTracked, categories.EquipSlotTracked }) do
			if category then
				local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
				if ok and type(ids) == "table" then
					for _, cooldownID in ipairs(ids) do
						local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
						if okInfo and info and info.isKnown and info.hasAura and not info.isInvisible and info.spellID then
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

	-- Everyone: a food buff and the weapon enchants.
	local wellFed = SpellName(WELL_FED) or "Well Fed"
	local food = SpellName(FOOD) or "Food"
	AddEntry({
		key = "food", name = wellFed, icon = SpellIcon(WELL_FED), kind = "food", source = "extra",
		auraNames = { [wellFed] = true }, castNames = {}, party = false, unlessNames = { [food] = true }, seedDefault = true,
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
local function SeedChoices()
	if cdb.seeded then
		return
	end
	cdb.seeded = true
	for _, key in ipairs(catalogOrder) do
		local entry = catalog[key]
		if entry.seedDefault then
			cdb.nag[key] = { party = entry.party }
		end
	end
end

local function CastName(entry)
	for _, name in ipairs(entry.castNames) do
		if knownSpells[name] then
			return name
		end
	end
	return entry.castNames[1]
end

------------------------------------------------------------------------------
-- Looking at units
------------------------------------------------------------------------------

-- Whether a unit has one of the named buffs with enough time left; nil when
-- the game would not let us look.
local function UnitHas(unit, names, soon)
	if not next(names) then
		return false
	end
	local found = false
	local ok = pcall(function()
		local now = GetTime()
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			for i = 1, 80 do
				local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
				if not aura then
					break
				end
				if names[aura.name] then
					local left = aura.expirationTime and aura.expirationTime > 0 and (aura.expirationTime - now) or math.huge
					if left > soon then
						found = true
						return
					end
				end
			end
		else
			for i = 1, 80 do
				local name, _, _, _, _, expirationTime = UnitBuff(unit, i, "HELPFUL")
				if not name then
					break
				end
				if names[name] then
					local left = expirationTime and expirationTime > 0 and (expirationTime - now) or math.huge
					if left > soon then
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
	return found
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
		return true
	end
	return expires ~= nil and expires > 0 and expires / 1000 <= db.soon
end

-- What could go on the weapon in a slot: a known imbue spell (main hand
-- only), or an item in the bags that fits the weapon's type. Nothing to
-- apply means nothing to nag about.
local function WeaponFix(slot)
	if slot == MAIN_HAND then
		for _, id in ipairs(IMBUES) do
			local name = SpellName(id)
			if name and knownSpells[name] then
				return "spell", name, SpellIcon(id), name
			end
		end
	end
	local itemID = GetInventoryItemID("player", slot)
	if not itemID or IsSecret(itemID) then
		return nil
	end
	local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, _, _, _, subclassID = getInfo(itemID)
	if not subclassID or IsSecret(subclassID) then
		return nil
	end
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local itemAt = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	if not (numSlots and itemAt) then
		return nil
	end
	local bitOf = bit.lshift(1, subclassID)
	for bag = 0, NUM_BAGS do
		for bagSlot = 1, numSlots(bag) or 0 do
			local bagItem = itemAt(bag, bagSlot)
			local mask = bagItem and not IsSecret(bagItem) and WEAPON_ITEMS[bagItem]
			if mask and (mask == 0 or bit.band(mask, bitOf) ~= 0) then
				local okIcon, icon = pcall(function()
					return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(bagItem)
				end)
				local okName, name = pcall(function()
					return C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(bagItem) or GetItemInfo and GetItemInfo(bagItem)
				end)
				return "item", bagItem, okIcon and icon or nil, okName and name or ("item " .. bagItem)
			end
		end
	end
	return nil
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

local function StyleIcon(button)
	button:SetSize(ICON, ICON)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button.Icon = icon
	pcall(function()
		local mask = button:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints()
		icon:AddMaskTexture(mask)
		local overlay = button:CreateTexture(nil, "OVERLAY")
		overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		overlay:SetPoint("TOPLEFT", -8, 7)
		overlay:SetPoint("BOTTOMRIGHT", 8, -7)
	end)
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
	if entry.kind == "weapon" or entry.kind == "offhand" then
		local slot = entry.kind == "weapon" and MAIN_HAND or OFF_HAND
		entry.fix = nil
		if WeaponMissing(slot) then
			local kind, value, icon, text = WeaponFix(slot)
			if kind then
				entry.fix = { kind = kind, value = value, icon = icon, text = text, slot = slot }
				missing[1] = "player"
			end
		end
		return missing
	end
	local inRaid = IsInRaid and IsInRaid()
	local units = (choice.party and db.party and not inRaid) and PARTY_UNITS or { "player" }
	for _, unit in ipairs(units) do
		if UnitUsable(unit) and (not entry.mana or UnitHasMana(unit)) then
			local has = UnitHas(unit, entry.auraNames, db.soon)
			if has == false and not UnitHas(unit, entry.unlessNames, 0) then
				missing[#missing + 1] = unit
			end
		end
	end
	return missing
end

local function Refresh()
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
				button.Icon:SetTexture((entry.fix and entry.fix.icon) or entry.icon or QUESTION_MARK)
				button.Count:SetText(#missing > 1 and tostring(#missing) or "")
				button.Party:SetShown(choice.party and true or false)
				local names = {}
				for i, unit in ipairs(missing) do
					names[i] = ShortName(unit)
				end
				button.missingText = table.concat(names, ", ")
				local spell = CastName(entry)
				button.applyText = nil
				if entry.fix and entry.fix.kind == "spell" then
					button:SetAttribute("type", "spell")
					button:SetAttribute("spell", entry.fix.value)
					button:SetAttribute("unit", "player")
					button.applyText = "Click to cast " .. entry.fix.text .. "."
				elseif entry.fix and entry.fix.kind == "item" then
					button:SetAttribute("type", "macro")
					button:SetAttribute("macrotext", ("/use item:%d\n/use %d"):format(entry.fix.value, entry.fix.slot))
					button.applyText = "Click to apply " .. entry.fix.text .. "."
				elseif spell then
					button:SetAttribute("type", "spell")
					button:SetAttribute("spell", spell)
					button:SetAttribute("unit", missing[1])
					button.applyText = "Click to cast on the first one."
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

local function ShowPanel()
	local settings = CooldownViewerSettings
	if not (settings and panel) then
		return
	end
	settings.displayMode = "buffnag"
	for _, tab in ipairs(settings.TabButtons or {}) do
		tab:SetChecked(tab.displayMode == "buffnag")
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

	-- The tab: made from the game's own tab template so it joins the
	-- others; selecting another tab unchecks it.
	local ok = pcall(function()
		settingsTab = CreateFrame("Frame", "BuffNagSettingsTab", settings, "CooldownViewerSettingsTabTemplate")
	end)
	if not ok or not settingsTab then
		settingsTab = nil
		Print("could not add a tab to the Cooldown Manager settings; use /bn to configure")
		return
	end
	settingsTab.displayMode = "buffnag"
	settingsTab.tooltipText = "BuffNag: buffs to nag about when missing"
	local anchor = settings.GroupBuffsTab or settings.AurasTab or settings.SpellsTab
	if anchor then
		settingsTab:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
	else
		settingsTab:SetPoint("TOPLEFT", settings, "TOPRIGHT", 0, -200)
	end
	settingsTab.Icon:SetSize(34, 34)
	settingsTab.Icon:SetTexture(SpellIcon(1243))
	settingsTab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	settingsTab:SetChecked(false)
	if settingsTab.SetCustomOnMouseUpHandler then
		settingsTab:SetCustomOnMouseUpHandler(function(_, button, upInside)
			if button == "LeftButton" and upInside then
				ShowPanel()
			end
		end)
	end
	-- Hidden by the game's own tabs; forgotten when the window closes, so
	-- it reopens on the game's first tab as usual.
	hooksecurefunc(settings, "SetDisplayMode", function(_, mode)
		panel:Hide()
		if mode ~= "buffnag" then
			settingsTab:SetChecked(false)
		end
	end)
	settings:HookScript("OnHide", function(self)
		if self.displayMode == "buffnag" then
			self.displayMode = nil
			panel:Hide()
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
	elseif word == "sound" then
		db.sound = rest ~= "off"
		if not db.sound then
			StopNag()
		end
	elseif word == "gap" then
		db.pingGap = math.max(0.1, math.min(10, tonumber(rest) or 0.4))
	elseif word == "soon" then
		db.soon = math.max(0, math.min(600, tonumber(rest) or 30))
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
		Print("/bn opens the settings; /bn list; /bn lock|unlock; /bn party on|off; /bn sound on|off; /bn gap <seconds>; /bn soon <seconds>; /bn scale <n>; /bn test; /bn reset")
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
			for key, value in pairs(DEFAULTS) do
				if db[key] == nil then
					db[key] = type(value) == "table" and CopyTable(value) or value
				end
			end
			BuffNagCharDB = BuffNagCharDB or {}
			cdb = BuffNagCharDB
			cdb.nag = cdb.nag or {}
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
