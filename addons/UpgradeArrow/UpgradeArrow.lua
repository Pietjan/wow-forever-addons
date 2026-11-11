-- UpgradeArrow: Pawn lite. An item's stats (C_Item.GetItemStats) are summed
-- with your class's weights below and compared with what you wear in the
-- slot it goes in; a higher score is an upgrade and gets a green arrow:
--
-- - in Baganator's bags and bank, as an icon corner widget (top right);
-- - on LootRolls bars (it asks UpgradeArrow.IsUpgrade);
-- - in the item tooltip, with both scores. Hold Alt for the stats behind them.
--
-- Rings, trinkets and (when you dual wield) one-handers are compared with
-- the weaker of the two you wear; a two-hander with main and off hand
-- together. An empty slot makes anything usable an upgrade. Only items you
-- can use now count: your class and skills (C_PlayerInfo.CanUseItem) and
-- your level.
--
-- The weights are a rough leveling guess per class, in points per stat
-- (Strength 1 for a warrior). /upgradearrow shows yours; /upgradearrow
-- <stat> <weight> changes one for this character, /upgradearrow reset
-- puts them back.

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
	sp = "ITEM_MOD_SPELL_POWER_SHORT",
	heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
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

local CASTER = { int = 0.6, spi = 0.4, sta = 0.4, armor = 0.005, sp = 1.2, heal = 0.5, mp5 = 1.2, spellhit = 8, spellcrit = 8, dps = 0, rdps = 0.2 }
local DEFAULTS = {
	WARRIOR = { str = 1, agi = 0.6, sta = 0.5, armor = 0.02, ap = 0.5, hit = 10, crit = 10, defense = 0.5, dodge = 5, parry = 5, block = 2, dps = 3.5, rdps = 0.5 },
	PALADIN = { str = 1, agi = 0.5, sta = 0.4, int = 0.4, spi = 0.1, armor = 0.02, ap = 0.5, sp = 0.5, heal = 0.3, mp5 = 0.8, hit = 9, crit = 9, dps = 3, rdps = 0 },
	ROGUE = { str = 0.5, agi = 1, sta = 0.3, armor = 0.01, ap = 0.5, hit = 12, crit = 10, dodge = 3, dps = 3, rdps = 0.5 },
	HUNTER = { agi = 1, int = 0.3, sta = 0.4, spi = 0.1, armor = 0.01, ap = 0.2, rap = 0.5, hit = 10, crit = 10, dps = 0.8, rdps = 3.5 },
	SHAMAN = { str = 1, agi = 0.5, sta = 0.4, int = 0.5, spi = 0.2, armor = 0.01, ap = 0.5, sp = 0.6, heal = 0.3, mp5 = 1, hit = 8, crit = 8, dps = 3, rdps = 0 },
	DRUID = { str = 1, agi = 0.8, sta = 0.5, int = 0.4, spi = 0.2, armor = 0.03, ap = 0.5, sp = 0.4, heal = 0.3, mp5 = 0.8, hit = 8, crit = 8, dodge = 3, dps = 0, rdps = 0 },
	MAGE = CASTER,
	PRIEST = { int = 0.6, spi = 0.6, sta = 0.4, armor = 0.005, sp = 1.1, heal = 0.8, mp5 = 1.3, spellhit = 6, spellcrit = 7, dps = 0, rdps = 0.2 },
	WARLOCK = { int = 0.4, spi = 0.3, sta = 0.6, armor = 0.005, sp = 1.2, mp5 = 0.8, spellhit = 8, spellcrit = 7, dps = 0, rdps = 0.2 },
}

-- Equip location -> the slots it can go in.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local db
local cache = {} -- link -> { upgrade, score, against, againstName }

local function Weights()
	local _, class = UnitClass("player")
	local weights = {}
	for key, value in pairs(DEFAULTS[class] or CASTER) do
		weights[key] = value
	end
	for key, value in pairs(db and db.weights or {}) do
		weights[key] = value
	end
	return weights
end
local weights

-- Score of an item link, and its { stat, amount, points } parts.
local function Score(link, slot)
	local ok, stats = pcall(C_Item.GetItemStats, link)
	if not ok or type(stats) ~= "table" then
		return 0, {}
	end
	local total, parts = 0, {}
	for _, key in ipairs(ORDER) do
		local value = stats[STATS[key]]
		local isDps = key == "dps" or key == "rdps"
		local applies = not isDps or ((key == "rdps") == (slot == 18))
		if applies and type(value) == "number" and not IsSecret(value) and value ~= 0 then
			local points = value * (weights[key] or 0)
			total = total + points
			parts[#parts + 1] = { key, value, points }
		end
	end
	return total, parts
end

local function EquippedScore(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then
		return 0, nil
	end
	return (Score(link, slot)), link
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

-- Works out whether link is an upgrade; nil while the item is not cached.
local function Evaluate(link)
	if type(link) ~= "string" or IsSecret(link) then
		return nil
	end
	local hit = cache[link]
	if hit then
		return hit
	end
	local _, _, _, _, reqLevel, _, _, _, equipLoc = C_Item.GetItemInfo(link)
	if not equipLoc then
		return nil
	end
	local result = { upgrade = false }
	local slots = SLOTS[equipLoc]
	local itemID = C_Item.GetItemInfoInstant(link)
	if not slots or not itemID or not Usable(link, itemID, reqLevel) then
		cache[link] = result
		return result
	end
	if equipLoc == "INVTYPE_WEAPON" and not (CanDualWield and CanDualWield()) then
		slots = { 16 }
	end
	local slot = slots[1] == 18 and 18 or slots[1]
	local score = Score(link, slot)
	result.score = score

	-- What it would replace.
	local against, againstLink
	if equipLoc == "INVTYPE_2HWEAPON" then
		local main, mainLink = EquippedScore(16)
		local off = EquippedScore(17)
		against, againstLink = main + off, mainLink
	else
		local mainLink = GetInventoryItemLink("player", 16)
		local mainEquip = mainLink and select(9, C_Item.GetItemInfo(mainLink))
		if slots[1] == 17 and mainEquip == "INVTYPE_2HWEAPON" then
			cache[link] = result -- an off hand while you hold a two-hander
			return result
		end
		for _, s in ipairs(slots) do
			local equippedLink = GetInventoryItemLink("player", s)
			if equippedLink and C_Item.GetItemInfoInstant(equippedLink) == itemID then
				cache[link] = result -- you already wear one
				return result
			end
			local value = EquippedScore(s)
			if not against or value < against then
				against, againstLink = value, equippedLink
			end
		end
	end
	result.against = against or 0
	result.againstLink = againstLink
	result.upgrade = score > 0 and score > result.against + 0.01
	cache[link] = result
	return result
end

-- The arrow --------------------------------------------------------------

local function SetArrow(texture)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-greenarrow") then
		texture:SetAtlas("bags-greenarrow")
	else
		texture:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
		texture:SetVertexColor(0.2, 1, 0.2)
	end
end

UpgradeArrow = {}

-- True when the item would be an upgrade for you (false while unknown).
function UpgradeArrow.IsUpgrade(link)
	local result = Evaluate(link)
	return result and result.upgrade or false
end

-- An arrow texture on frame (top right), for other addons.
function UpgradeArrow.CreateArrow(frame)
	local arrow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
	SetArrow(arrow)
	arrow:SetSize(14, 14)
	arrow:SetPoint("TOPRIGHT", 2, 2)
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
	if result.upgrade then
		local gain = result.against > 0 and ("+%d%%"):format((result.score / result.against - 1) * 100 + 0.5) or "empty slot"
		tooltip:AddDoubleLine("|cff40c040Upgrade|r " .. gain, ("%.1f vs %.1f"):format(result.score, result.against), 1, 1, 1, 0.6, 0.6, 0.6)
	elseif alt then
		tooltip:AddDoubleLine("Not an upgrade", ("%.1f vs %.1f"):format(result.score, result.against or 0), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	end
	if alt then
		local slot = SLOTS[select(9, C_Item.GetItemInfo(link)) or ""]
		local _, parts = Score(link, slot and slot[1])
		for _, part in ipairs(parts) do
			tooltip:AddDoubleLine(("  %g %s x %g"):format(part[2], part[1], weights[part[1]] or 0), ("%.1f"):format(part[3]), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		end
		if result.againstLink then
			tooltip:AddLine("  vs " .. result.againstLink, 0.6, 0.6, 0.6)
		end
	end
end

-- Baganator --------------------------------------------------------------

local function RegisterBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
		return
	end
	Baganator.API.RegisterCornerWidget("Upgrade arrow", "upgrade_arrow", function(arrow, details)
		local result = Evaluate(details.itemLink)
		if result == nil then
			return nil -- not cached yet; Baganator asks again
		end
		return result.upgrade
	end, function(itemButton)
		local arrow = itemButton:CreateTexture(nil, "OVERLAY")
		SetArrow(arrow)
		arrow:SetSize(14, 14)
		return arrow
	end, { corner = "top_right", priority = 1 })
end

-- Events -----------------------------------------------------------------

local function Invalidate()
	wipe(cache)
	weights = Weights()
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then
			return
		end
		UpgradeArrowDB = UpgradeArrowDB or {}
		db = UpgradeArrowDB
		local key = UnitName("player") .. "-" .. GetRealmName()
		db[key] = db[key] or {}
		db = db[key]
		weights = Weights()
		RegisterBaganator()
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
				pcall(AddTooltip, tooltip, data)
			end)
		end
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		self:RegisterEvent("PLAYER_LEVEL_UP")
		self:RegisterEvent("SKILL_LINES_CHANGED")
	else
		Invalidate()
	end
end)

SLASH_UPGRADEARROW1 = "/upgradearrow"
SlashCmdList.UPGRADEARROW = function(msg)
	local stat, value = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if stat == "reset" then
		db.weights = nil
		Invalidate()
		print("|cff40c040UpgradeArrow|r: weights back to the class defaults")
	elseif STATS[stat] and tonumber(value) then
		db.weights = db.weights or {}
		db.weights[stat] = tonumber(value)
		Invalidate()
		print(("|cff40c040UpgradeArrow|r: %s = %g"):format(stat, tonumber(value)))
	else
		local list = {}
		for _, key in ipairs(ORDER) do
			if (weights[key] or 0) ~= 0 then
				list[#list + 1] = ("%s %g"):format(key, weights[key])
			end
		end
		print("|cff40c040UpgradeArrow|r weights: " .. table.concat(list, ", "))
		print("  /upgradearrow <stat> <weight>  |  /upgradearrow reset   (stats: " .. table.concat(ORDER, " ") .. ")")
	end
end
