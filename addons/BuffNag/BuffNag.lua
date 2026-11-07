-- BuffNag: a small list of what is missing: the buffs your class hands out
-- (on you and on your party), your self buffs, a food buff and a weapon
-- enchant. Each line is a button: click it to cast that buff on the first
-- person who lacks it. A sound nags now and then while the list is not
-- empty. Everything is out of combat only; the list hides in combat.
--
-- Buffs are matched by spell name, so any rank counts, and a buff is only
-- asked for when your spellbook holds a spell that provides it.

local ADDON_NAME = ...

local IsSecret = issecretvalue or function() return false end

local DEFAULTS = {
	party = true, -- also look at party members
	soon = 30, -- seconds left at which a buff counts as missing
	sound = true, -- ping while something is missing
	pingGap = 0.4, -- seconds between pings
	scale = 1,
	locked = false,
	off = {}, -- buff keys the player turned off
	point = { "CENTER", 0, 200 },
}

-- What to watch. "auras" are spells whose name on a unit satisfies the
-- buff (any rank, single or group version). "know" are spells one of which
-- has to be in the spellbook for the buff to be asked for at all; without
-- it the buff is for everyone (food). "cast" is tried in order on a click:
-- the first one the player knows. "mana" skips units without mana.
-- "unless" are auras that excuse a unit (eating excuses missing food).
local BUFFS = {
	-- priest
	{ key = "fortitude", scope = "party", auras = { 1243, 21562 }, know = { 1243 }, cast = { 1243 } },
	{ key = "spirit", scope = "party", auras = { 14752, 27681 }, know = { 14752 }, cast = { 14752 }, mana = true },
	{ key = "shadowprot", scope = "party", auras = { 976, 27683 }, know = { 976 }, cast = { 976 }, default = false },
	{ key = "innerfire", scope = "self", auras = { 588 }, know = { 588 }, cast = { 588 } },
	-- mage
	{ key = "intellect", scope = "party", auras = { 1459, 23028 }, know = { 1459 }, cast = { 1459 }, mana = true },
	{ key = "magearmor", scope = "self", label = "Armor", auras = { 168, 7302, 6117 }, know = { 168, 7302, 6117 }, cast = { 6117, 7302, 168 } },
	-- druid
	{ key = "wild", scope = "party", auras = { 1126, 21849 }, know = { 1126 }, cast = { 1126 } },
	{ key = "thorns", scope = "self", auras = { 467 }, know = { 467 }, cast = { 467 }, default = false },
	{ key = "omen", scope = "self", auras = { 16864 }, know = { 16864 }, cast = { 16864 } },
	-- paladin
	{ key = "blessing", scope = "party", label = "Blessing", auras = { 19740, 19742, 20217, 25782, 25894, 25898 },
		know = { 19740, 19742, 20217 }, cast = { 20217, 19742, 19740 } },
	{ key = "aura", scope = "self", label = "Aura", auras = { 465, 7294, 19746, 19876, 19888, 19891, 20218 },
		know = { 465, 7294 }, cast = { 465 } },
	{ key = "righteousfury", scope = "self", auras = { 25780 }, know = { 25780 }, cast = { 25780 }, default = false },
	-- shaman
	{ key = "lightningshield", scope = "self", auras = { 324 }, know = { 324 }, cast = { 324 } },
	-- warlock
	{ key = "demonarmor", scope = "self", label = "Demon Armor", auras = { 687, 706 }, know = { 687, 706 }, cast = { 706, 687 } },
	-- warrior
	{ key = "battleshout", scope = "party", auras = { 6673 }, know = { 6673 }, cast = { 6673 }, default = false },
	-- hunter
	{ key = "aspect", scope = "self", label = "Aspect", auras = { 13165, 13163, 5118, 13159, 13161, 20043, 469145, 34074 },
		know = { 13165, 13163, 5118 }, cast = { 13165, 13163 } },
	{ key = "trueshot", scope = "self", auras = { 19506 }, know = { 19506 }, cast = { 19506 } },
	-- everyone
	{ key = "food", scope = "self", auras = { 19705 }, unless = { 433 } },
	{ key = "weapon", scope = "self", label = "Weapon enchant", weapon = "main" },
	{ key = "offhand", scope = "self", label = "Off-hand enchant", weapon = "off" },
}

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local MAIN_HAND, OFF_HAND = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
local WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local FISHING_POLE = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local MAX_LINES = 12

local db
local knownSpells = {} -- localized spell name -> true, from the spellbook
local nagging = false
local refreshPending = false

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

local function Enabled(buff)
	if db.off[buff.key] ~= nil then
		return not db.off[buff.key]
	end
	return buff.default ~= false
end

------------------------------------------------------------------------------
-- Names: resolved once the client has the spell data
------------------------------------------------------------------------------

local function ResolveNames()
	for _, buff in ipairs(BUFFS) do
		buff.auraNames = {}
		for _, id in ipairs(buff.auras or {}) do
			local name = SpellName(id)
			if name then
				buff.auraNames[name] = true
			end
		end
		buff.unlessNames = {}
		for _, id in ipairs(buff.unless or {}) do
			local name = SpellName(id)
			if name then
				buff.unlessNames[name] = true
			end
		end
		buff.knowNames = {}
		for _, id in ipairs(buff.know or {}) do
			local name = SpellName(id)
			if name then
				buff.knowNames[#buff.knowNames + 1] = name
			end
		end
		buff.castNames = {}
		for _, id in ipairs(buff.cast or {}) do
			local name = SpellName(id)
			if name then
				buff.castNames[#buff.castNames + 1] = name
			end
		end
		buff.text = buff.label or (buff.auras and SpellName(buff.auras[1])) or buff.key
	end
end

-- Every spell name in the spellbook, so a buff is only asked for when the
-- player can give it, whatever its rank.
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

local function CanProvide(buff)
	if not buff.know then
		return true
	end
	for _, name in ipairs(buff.knowNames) do
		if knownSpells[name] then
			return true
		end
	end
	return false
end

local function CastName(buff)
	for _, name in ipairs(buff.castNames) do
		if knownSpells[name] then
			return name
		end
	end
end

------------------------------------------------------------------------------
-- Looking at units
------------------------------------------------------------------------------

-- Whether a unit has one of the named buffs with enough time left; nil when
-- the game would not let us look (secret values).
local function UnitHas(unit, names, soon)
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

-- The weapon enchant check: an item in the slot that is a weapon (not a
-- fishing pole) and has no temporary enchant.
local function WeaponMissing(which)
	local slot = which == "main" and MAIN_HAND or OFF_HAND
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
		if which == "main" then
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

------------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "BuffNagFrame", UIParent)
frame:SetSize(200, 20)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
header:SetText("BuffNag (drag to move, /bn lock)")

local lines = {}

local function SavePosition()
	local point, _, _, x, y = frame:GetPoint(1)
	db.point = { point, x, y }
end

local function OnDragStart()
	if not db.locked and not InCombatLockdown() then
		frame:StartMoving()
	end
end

local function OnDragStop()
	frame:StopMovingOrSizing()
	SavePosition()
end

frame:SetScript("OnDragStart", OnDragStart)
frame:SetScript("OnDragStop", OnDragStop)

local function Line(i)
	if lines[i] then
		return lines[i]
	end
	local button = CreateFrame("Button", "BuffNagLine" .. i, frame, "SecureActionButtonTemplate")
	button:SetSize(200, 16)
	button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * 16)
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", OnDragStart)
	button:SetScript("OnDragStop", OnDragStop)
	button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", 4, 0)
	text:SetJustifyH("LEFT")
	button.text = text
	lines[i] = button
	return button
end

local function ApplyLayout()
	frame:SetScale(db.scale)
	frame:ClearAllPoints()
	frame:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
	header:SetShown(not db.locked)
end

-- The nag: the minimap ping, over and over with a short gap, for as long
-- as the list is showing.
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

local testing = false

-- Work out the missing buffs and show them. Called out of combat only.
local function Refresh()
	refreshPending = false
	if InCombatLockdown() then
		return
	end
	if UnitIsDeadOrGhost("player") and not testing then
		frame:Hide()
		StopNag()
		return
	end
	local inRaid = IsInRaid and IsInRaid()
	local count = 0
	for _, buff in ipairs(BUFFS) do
		if Enabled(buff) and CanProvide(buff) then
			local missing = {}
			if buff.weapon then
				if WeaponMissing(buff.weapon) then
					missing[1] = "player"
				end
			else
				local units = (buff.scope == "party" and db.party and not inRaid) and PARTY_UNITS or { "player" }
				for _, unit in ipairs(units) do
					if UnitUsable(unit) and (not buff.mana or UnitHasMana(unit)) then
						local has = UnitHas(unit, buff.auraNames, db.soon)
						if has == false and not UnitHas(unit, buff.unlessNames, 0) then
							missing[#missing + 1] = unit
						end
					end
				end
			end
			if #missing > 0 and count < MAX_LINES then
				count = count + 1
				local line = Line(count)
				local names = {}
				for i, unit in ipairs(missing) do
					names[i] = ShortName(unit)
				end
				line.text:SetText(("|cffffd100%s|r  %s"):format(buff.text, table.concat(names, ", ")))
				local spell = CastName(buff)
				if spell then
					line:SetAttribute("type", "spell")
					line:SetAttribute("spell", spell)
					line:SetAttribute("unit", missing[1])
				else
					line:SetAttribute("type", nil)
				end
				line:Show()
			end
		end
	end
	if testing and count == 0 then
		count = 1
		local line = Line(1)
		line.text:SetText("|cffffd100Nothing missing|r  (test)")
		line:SetAttribute("type", nil)
		line:Show()
	end
	for i = count + 1, #lines do
		lines[i]:Hide()
	end
	frame:SetHeight(math.max(1, count * 16))
	frame:SetShown(count > 0)
	if count > 0 and not testing and db.sound then
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
-- Slash command
------------------------------------------------------------------------------

local function ListBuffs()
	Print("buffs (|cff00ff00on|r / |cffff0000off|r; /bn <name> toggles):")
	for _, buff in ipairs(BUFFS) do
		local state = Enabled(buff) and "|cff00ff00on|r" or "|cffff0000off|r"
		local can = CanProvide(buff) and "" or " |cff808080(not yours)|r"
		Print("  %s  %s: %s%s", state, buff.key, buff.text or buff.key, can)
	end
	Print("party %s, warn %d s before a buff runs out, pings %s (every %.1f s), scale %.2f, %s",
		db.party and "on" or "off", db.soon, db.sound and "on" or "off", db.pingGap, db.scale, db.locked and "locked" or "unlocked")
end

SLASH_BUFFNAG1 = "/bn"
SLASH_BUFFNAG2 = "/buffnag"
SlashCmdList.BUFFNAG = function(msg)
	local word, rest = msg:lower():match("^%s*(%S*)%s*(%S*)")
	if word == "" or word == "list" then
		ListBuffs()
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
		testing = not testing
		Print("test display %s", testing and "on" or "off")
	else
		local found
		for _, buff in ipairs(BUFFS) do
			if buff.key == word then
				found = buff
			end
		end
		if not found then
			Print("/bn  lists the buffs; /bn <name> toggles one; /bn lock|unlock; /bn party on|off; /bn sound on|off; /bn gap <seconds>; /bn soon <seconds>; /bn scale <n>; /bn test; /bn reset")
			return
		end
		db.off[found.key] = Enabled(found) -- toggle
		Print("%s %s", found.text, Enabled(found) and "on" or "off")
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
loader:RegisterUnitEvent("UNIT_AURA", "player", "party1", "party2", "party3", "party4")
loader:SetScript("OnEvent", function(self, event, arg)
	if event == "ADDON_LOADED" then
		if arg ~= ADDON_NAME then
			return
		end
		BuffNagDB = BuffNagDB or {}
		db = BuffNagDB
		if type(db.sound) == "number" then
			db.sound = db.sound > 0
		end
		db.pings = nil
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				if type(value) == "table" then
					local copy = {}
					for k, v in pairs(value) do
						copy[k] = v
					end
					db[key] = copy
				else
					db[key] = value
				end
			end
		end
	elseif event == "PLAYER_LOGIN" then
		ResolveNames()
		ScanSpellbook()
		ApplyLayout()
		-- Temporary weapon enchants and running-out buffs have no event of
		-- their own: look every few seconds.
		C_Timer.NewTicker(3, function()
			if not InCombatLockdown() then
				Schedule(0)
			end
		end)
	elseif event == "PLAYER_REGEN_DISABLED" then
		frame:Hide()
		StopNag()
	elseif event == "SPELLS_CHANGED" then
		ScanSpellbook()
		if not InCombatLockdown() then
			Schedule()
		end
	elseif not InCombatLockdown() then
		Schedule()
	end
end)
