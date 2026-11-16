-- LootFeed: what you just picked up, as a short list of bare lines: a small
-- icon and the game's own text, no panel behind it. An item line shows the
-- name in its quality colour, how many you got and (grey) how many you now
-- carry. Money, reputation, experience and honor get a line each, and so
-- does what a group member loots, with their name in class colour. A line
-- fades after a few seconds; the same thing again while its line is still
-- up adds to that line instead of making a new one.
--
-- Where things come from (Blizzard UI source and GlobalStrings, 1.60.1):
-- - Items: CHAT_MSG_LOOT, matched against the LOOT_ITEM* strings. Chat
--   text can be secret in lockdown (boss fights, PvP matches); a secret
--   line is skipped. An item below the lowest quality you chose gets no
--   line (C_Item.GetItemQualityByID); group loot has a threshold of its own
--   on top of that one. An item whose quality the client cannot tell yet
--   is shown.
-- - Money: the change in GetMoney() on PLAYER_MONEY, gains only, and not
--   while a merchant, the mailbox, the auction house or a trade is open
--   (that money is not loot).
-- - Reputation and honor: CHAT_MSG_COMBAT_FACTION_CHANGE and
--   CHAT_MSG_COMBAT_HONOR_GAIN, matched against FACTION_STANDING_* and
--   COMBATLOG_HONOR*.
-- - Experience: the change in UnitXP on PLAYER_XP_UPDATE.
-- The lines never take the mouse, so they cannot get in the way of a click
-- into the world. No Blizzard function is hooked and no Blizzard field is
-- written.
--
-- /lootfeed: unlock, lock, test, clear, scale <n>, quality <0-4>,
-- groupquality <0-4>, reset.

local ADDON = ...
local IsSecret = issecretvalue or function() return false end

local WIDTH = 240 -- the anchor; a line is as long as its text
local HEIGHT = 22 -- a line
local GAP = 2 -- between lines
local ICON = 20
local TEXT_GAP = 6 -- icon to text
-- The border ring's reach past the icon: a fifth of its size across and a
-- pixel less up and down, the proportion the Cooldown Manager uses.
local RING_X, RING_Y = ICON * 0.2, ICON * 0.2 - 1
local FADE_IN, FADE_OUT = 0.15, 0.6 -- seconds
local TEST_PACE = 0.5 -- seconds between the lines of /lootfeed test
local BUSY_AFTER = 1 -- seconds after a merchant (mail, ...) closes that money still is not loot

local GREY = "|cff808080"
local RED = "|cffff2020"

-- The unlocked anchor: a near-black panel with a gold edge.
local BG = { 0.04, 0.04, 0.05, 0.92 }
local GOLD = { 1.00, 0.82, 0.00, 1 }

-- Interface\Icons, by file ID (all in the client's ManifestInterfaceData).
local ICON_GOLD, ICON_SILVER, ICON_COPPER = 133785, 133787, 133789 -- INV_Misc_Coin_02, _04, _06
local ICON_XP = 894556 -- XP_Icon
local ICON_REP = 236681 -- Achievement_Reputation_01
local ICON_HONOR = { Horde = 463451, Alliance = 463450 } -- PVPCurrency-Honor-*
local ICON_UNKNOWN = 134400 -- INV_Misc_QuestionMark

-- quality, partyQuality: the lowest item quality that gets a line (0 poor, 1
-- common, 2 uncommon, 3 rare, 4 epic), for everything and for group loot.
local DEFAULTS = { duration = 6, max = 8, money = true, rep = true, xp = true, honor = true, party = true, quality = 0, partyQuality = 0 }
local MAX_QUALITY = 4

local db, anchor, unlocked
local Layout
local active = {} -- the lines on screen, oldest first
local pool = {}
local lastMoney, lastXP, lastXPMax
local busy, busyUntil = {}, 0

local function Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

local function Short(name)
	name = Plain(name)
	if type(name) ~= "string" then
		return nil
	end
	return (name:gsub("%-.*$", ""))
end

local function ClassText(name, class)
	class = Plain(class)
	local color = class and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
	if color and color.WrapTextInColorCode then
		return color:WrapTextInColorCode(name)
	end
	return name
end

-- Class of a group member by short name, read from the group units.
local function ClassOf(name)
	local units = {}
	if IsInRaid and IsInRaid() then
		for i = 1, 40 do
			units[#units + 1] = "raid" .. i
		end
	else
		for i = 1, 4 do
			units[#units + 1] = "party" .. i
		end
	end
	for _, unit in ipairs(units) do
		local ok, unitName, class = pcall(function()
			if not UnitExists(unit) then
				return nil
			end
			local n = UnitName(unit)
			local _, c = UnitClass(unit)
			return n, c
		end)
		if ok and Plain(unitName) and Short(unitName) == name then
			return Plain(class)
		end
	end
	return nil
end

local function Edges(frame, color, layer)
	local lines = {}
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, layer or "BORDER")
		t:SetColorTexture(color[1], color[2], color[3], color[4])
		lines[i] = t
	end
	lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
	lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
	lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
	lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
	return lines
end

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

local function Font(name, fallback)
	return _G[name] and name or fallback
end

local function Money(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

local function Signed(amount, what)
	if amount < 0 then
		return ("%s%d %s|r"):format(RED, amount, what)
	end
	return ("+%d %s"):format(amount, what)
end

-- Anchor ----------------------------------------------------------------

local function SavePosition()
	local point, _, relPoint, x, y = anchor:GetPoint(1)
	db.point = { point, relPoint, x, y }
end

local function PlaceAnchor()
	anchor:ClearAllPoints()
	local p = db.point
	if p then
		anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		anchor:SetPoint("CENTER", UIParent, "CENTER", 300, -80)
	end
	anchor:SetScale(db.scale or 1)
end

local function GrowsDown()
	local _, y = anchor:GetCenter()
	local _, top = UIParent:GetCenter()
	if not y or not top then
		return true
	end
	return y * anchor:GetEffectiveScale() > top * UIParent:GetEffectiveScale()
end

local function CreateAnchor()
	anchor = CreateFrame("Frame", "LootFeedAnchor", UIParent)
	anchor:SetSize(WIDTH, HEIGHT)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	anchor:EnableMouse(false)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", anchor.StartMoving)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
		Layout()
	end)
	local bg = anchor:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
	local edges = Edges(anchor, GOLD)
	local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER")
	text:SetText("LootFeed: drag me, then /lootfeed lock")
	anchor.parts = { bg, text, unpack(edges) }
	for _, part in ipairs(anchor.parts) do
		part:Hide()
	end
	PlaceAnchor()
end

-- Lines -----------------------------------------------------------------

local function CreateRow()
	local row = CreateFrame("Frame", nil, anchor)
	row:SetSize(WIDTH, HEIGHT)
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON, ICON)
	icon:SetPoint("LEFT", 1, 0)
	-- The Cooldown Manager's icon dressing, as BuffNag uses it: its rounded
	-- mask and border ring over the uncropped picture. A plain dark square
	-- edge stands in on a client without those atlases.
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = row:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
		local ring = row:CreateTexture(nil, "OVERLAY")
		ring:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -RING_X, RING_Y)
		ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", RING_X, -RING_Y)
	else
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local edge = row:CreateTexture(nil, "BACKGROUND")
		edge:SetColorTexture(0, 0, 0, 1)
		edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	end
	local text = row:CreateFontString(nil, "ARTWORK", Font("GameFontHighlight", "GameFontNormal"))
	text:SetPoint("LEFT", icon, "RIGHT", TEXT_GAP + 1, 0)
	text:SetWordWrap(false)
	row.icon, row.text = icon, text
	return row
end

-- What a line says, from what it holds.
local TEXT = {
	item = function(row)
		local text = row.label
		if row.amount > 1 then
			text = text .. " x" .. row.amount
		end
		if row.who then
			return text .. "  " .. row.who
		end
		if row.total and row.total > 0 then
			text = text .. "  " .. GREY .. "(" .. row.total .. ")|r"
		end
		return text
	end,
	money = function(row)
		return "+" .. Money(row.amount)
	end,
	rep = function(row)
		return Signed(row.amount, row.label)
	end,
	xp = function(row)
		return Signed(row.amount, XP or "XP")
	end,
	honor = function(row)
		return Signed(row.amount, HONOR or "Honor")
	end,
}

local function Carried(link)
	local count = C_Item and C_Item.GetItemCount or GetItemCount
	if not count then
		return nil
	end
	local ok, n = pcall(count, link)
	return ok and Plain(n) or nil
end

local function Refresh(row)
	if row.kind == "item" and not row.who then
		row.total = Carried(row.link)
	elseif row.kind == "money" then
		row.icon:SetTexture(row.amount >= 10000 and ICON_GOLD or row.amount >= 100 and ICON_SILVER or ICON_COPPER)
	end
	row.text:SetText(TEXT[row.kind](row))
end

local function Release(index)
	local row = table.remove(active, index)
	row:Hide()
	pool[#pool + 1] = row
end

function Layout()
	local down = GrowsDown()
	for i, row in ipairs(active) do
		local offset = (i - 1) * (HEIGHT + GAP)
		row:ClearAllPoints()
		if down then
			row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -offset)
		else
			row:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, offset)
		end
	end
end

local function Tick()
	local now = GetTime()
	local gone
	for i = #active, 1, -1 do
		local row = active[i]
		local left = row.expires - now
		if left <= 0 then
			Release(i)
			gone = true
		else
			row:SetAlpha(math.max(0, math.min(1, (now - row.born) / FADE_IN, left / FADE_OUT)))
		end
	end
	if gone then
		Layout()
	end
	if #active == 0 then
		anchor:SetScript("OnUpdate", nil)
	end
end

-- Adds a line, or adds `spec.amount` to the line with the same key.
local function Push(key, spec)
	local now = GetTime()
	for _, row in ipairs(active) do
		if row.key == key then
			row.amount = row.amount + spec.amount
			row.expires = now + db.duration
			Refresh(row)
			return row
		end
	end
	local row = table.remove(pool) or CreateRow()
	row.key, row.kind, row.amount = key, spec.kind, spec.amount
	row.label, row.link, row.who, row.total = spec.label, spec.link, spec.who, nil
	row.born, row.expires = now, now + db.duration
	row.icon:SetTexture(spec.icon or ICON_UNKNOWN)
	Refresh(row)
	row:SetAlpha(0)
	row:Show()
	active[#active + 1] = row
	while #active > db.max do
		Release(1)
	end
	Layout()
	anchor:SetScript("OnUpdate", Tick)
	return row
end

local function Clear()
	while #active > 0 do
		Release(#active)
	end
end

-- An item line. `text` is the item as the chat line has it (a link);
-- `who` is nil for your own loot; `class` is theirs when already known.
local function PushItem(text, count, who, class)
	local id = text:match("|Hitem:(%d+)")
	if not id then
		return
	end
	local floor = who and math.max(db.quality, db.partyQuality) or db.quality
	if floor > 0 then
		local ok, quality = pcall(C_Item.GetItemQualityByID, text)
		quality = ok and Plain(quality)
		if quality and quality < floor then
			return
		end
	end
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(tonumber(id))
	class = who and (class or ClassOf(who))
	Push("item:" .. id .. ":" .. (who or ""), {
		kind = "item", amount = count or 1, icon = icon, link = text,
		label = (text:gsub("|h%[(.-)%]|h", "|h%1|h")), -- the link without its brackets, colour kept
		who = who and ClassText(who, class),
	})
end

-- Chat lines ------------------------------------------------------------

-- A format string as a pattern; `open` leaves the end free, for strings
-- that can carry a bonus note after the part that matters.
local function Pattern(format, open)
	if type(format) ~= "string" then
		return nil
	end
	local p = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	p = p:gsub("%%([sd])", function(kind)
		return kind == "d" and "(%d+)" or "(.+)"
	end)
	return "^" .. p .. (open and "" or "$")
end

-- { global string, what its arguments are in order, ... }. The "x%d" strings
-- go before the plain ones, which would match them too.
local LOOT = {
	{ "LOOT_ITEM_SELF_MULTIPLE", { "item", "count" }, self = true },
	{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", { "item", "count" }, self = true },
	{ "LOOT_ITEM_CREATED_SELF_MULTIPLE", { "item", "count" }, self = true },
	{ "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", { "item", "count" }, self = true },
	{ "LOOT_ITEM_SELF", { "item" }, self = true },
	{ "LOOT_ITEM_PUSHED_SELF", { "item" }, self = true },
	{ "LOOT_ITEM_CREATED_SELF", { "item" }, self = true },
	{ "LOOT_ITEM_BONUS_ROLL_SELF", { "item" }, self = true },
	{ "LOOT_ITEM_MULTIPLE", { "name", "item", "count" } },
	{ "LOOT_ITEM_PUSHED_MULTIPLE", { "name", "item", "count" } },
	{ "LOOT_ITEM_BONUS_ROLL_MULTIPLE", { "name", "item", "count" } },
	{ "LOOT_ITEM", { "name", "item" } },
	{ "LOOT_ITEM_PUSHED", { "name", "item" } },
	{ "LOOT_ITEM_BONUS_ROLL", { "name", "item" } },
}
local REP = {
	{ "FACTION_STANDING_INCREASED", { "faction", "amount" }, open = true, sign = 1 },
	{ "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", { "faction", "amount" }, open = true, sign = 1 },
	{ "FACTION_STANDING_DECREASED", { "faction", "amount" }, open = true, sign = -1 },
	{ "FACTION_STANDING_DECREASED_ACCOUNT_WIDE", { "faction", "amount" }, open = true, sign = -1 },
}
local HONORS = {
	{ "COMBATLOG_HONORGAIN", { "victim", "rank", "amount" }, open = true },
	{ "COMBATLOG_HONORGAIN_NO_RANK", { "victim", "amount" }, open = true },
	{ "COMBATLOG_HONORAWARD", { "amount" }, open = true },
}

local function Compile(list)
	local out = {}
	for _, entry in ipairs(list) do
		local pattern = Pattern(_G[entry[1]], entry.open)
		if pattern then
			out[#out + 1] = { pattern = pattern, fields = entry[2], self = entry.self, sign = entry.sign }
		end
	end
	return out
end

-- The first pattern of `list` that fits: the entry and its fields by name.
local function Match(list, text)
	for _, entry in ipairs(list) do
		local found = { text:match(entry.pattern) }
		if found[1] then
			local fields = {}
			for i, name in ipairs(entry.fields) do
				fields[name] = found[i]
			end
			return entry, fields
		end
	end
	return nil
end

local lootPatterns, repPatterns, honorPatterns

local function OnLoot(text)
	text = Plain(text)
	if type(text) ~= "string" then
		return
	end
	local entry, f = Match(lootPatterns, text)
	if not entry then
		return
	end
	if entry.self then
		PushItem(f.item, tonumber(f.count))
	elseif db.party then
		local who = Short(f.name)
		if who then
			PushItem(f.item, tonumber(f.count), who)
		end
	end
end

local function OnRep(text)
	text = Plain(text)
	if not db.rep or type(text) ~= "string" then
		return
	end
	local entry, f = Match(repPatterns, text)
	if entry then
		Push("rep:" .. f.faction, { kind = "rep", amount = entry.sign * tonumber(f.amount), label = f.faction, icon = ICON_REP })
	end
end

local function OnHonor(text)
	text = Plain(text)
	if not db.honor or type(text) ~= "string" then
		return
	end
	local entry, f = Match(honorPatterns, text)
	if entry then
		local faction = UnitFactionGroup and Plain(UnitFactionGroup("player"))
		Push("honor", { kind = "honor", amount = tonumber(f.amount), icon = ICON_HONOR[faction] or ICON_HONOR.Horde })
	end
end

-- Money and experience ---------------------------------------------------

local function IsBusy()
	return next(busy) ~= nil or GetTime() < busyUntil
end

local function OnMoney()
	local money = Plain(GetMoney())
	if not money then
		return
	end
	local gain = lastMoney and money - lastMoney or 0
	lastMoney = money
	if gain > 0 and db.money and not IsBusy() then
		Push("money", { kind = "money", amount = gain })
	end
end

local function ReadXP()
	return Plain(UnitXP("player")), Plain(UnitXPMax("player"))
end

local function OnXP()
	local xp, max = ReadXP()
	if not xp or not max then
		return
	end
	local gain = 0
	if lastXP then
		-- Less than before means a level went by: the rest of the old bar, then the new one.
		gain = xp >= lastXP and xp - lastXP or (lastXPMax - lastXP) + xp
	end
	lastXP, lastXPMax = xp, max
	if gain > 0 and db.xp then
		Push("xp", { kind = "xp", amount = gain, icon = ICON_XP })
	end
end

-- Windows whose money is not loot: event that opens -> event that closes.
local WINDOWS = {
	MERCHANT_SHOW = "MERCHANT_CLOSED",
	MAIL_SHOW = "MAIL_CLOSED",
	AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
	TRADE_SHOW = "TRADE_CLOSED",
}
local CLOSES = {}
for open, close in pairs(WINDOWS) do
	CLOSES[close] = open
end

-- Settings: the slash command and the options window both change them here.

local function SetUnlocked(on)
	unlocked = on
	anchor:EnableMouse(on)
	for _, part in ipairs(anchor.parts) do
		part:SetShown(on)
	end
	Layout()
end

local function SetScale(scale)
	db.scale = scale
	anchor:SetScale(scale)
end

local function SetMax(max)
	db.max = max
	while #active > max do
		Release(1)
	end
	Layout()
end

local function Reset()
	db.point, db.scale = nil, nil
	PlaceAnchor()
	Layout()
end

local function SetQuality(key, quality)
	db[key] = math.min(MAX_QUALITY, math.max(0, math.floor(quality)))
end

local function QualityName(quality)
	local name = _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and color.hex and (color.hex .. name .. "|r") or name
end

-- id, name, quality, how many: common ones and a green (all in the client's ItemSparse).
local TEST_ITEMS = { { 2589, "Linen Cloth", 1, 3 }, { 2672, "Stringy Wolf Meat", 1, 1 }, { 2447, "Peacebloom", 1, 2 }, { 1189, "Overseer's Ring", 2, 1 } }

-- The item's link, or one put together here while the client does not have the item yet.
local function TestLink(item)
	local id, name, quality = unpack(item)
	local _, link = C_Item.GetItemInfo(id)
	if link then
		return link
	end
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return (color and color.hex or "|cffffffff") .. "|Hitem:" .. id .. "|h[" .. name .. "]|h|r"
end

-- One line of each kind, one after the other the way loot comes in. The
-- item lines obey the quality settings, like real loot.
local function Test()
	local steps = {}
	for _, item in ipairs(TEST_ITEMS) do
		steps[#steps + 1] = function() PushItem(TestLink(item), item[4]) end
	end
	steps[#steps + 1] = function() PushItem(TestLink(TEST_ITEMS[1]), 2, "Thrall", "SHAMAN") end
	steps[#steps + 1] = function() Push("money", { kind = "money", amount = 214 }) end
	steps[#steps + 1] = function() Push("rep:Orgrimmar", { kind = "rep", amount = 75, label = "Orgrimmar", icon = ICON_REP }) end
	steps[#steps + 1] = function() Push("xp", { kind = "xp", amount = 120, icon = ICON_XP }) end
	steps[#steps + 1] = function()
		Push("honor", { kind = "honor", amount = 12, icon = ICON_HONOR[UnitFactionGroup and UnitFactionGroup("player")] or ICON_HONOR.Horde })
	end
	steps[1]()
	for i = 2, #steps do
		C_Timer.After((i - 1) * TEST_PACE, steps[i])
	end
	print("|cffffd100LootFeed|r: test lines. /lootfeed unlock to drag them.")
end

------------------------------------------------------------------------------
-- The game's options window (Options > AddOns): the settings of the slash
-- command as check boxes, sliders and buttons. Optional: without the game's
-- settings API the slash command still does the basics.
------------------------------------------------------------------------------

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown and Settings.RegisterInitializer
		and CreateSettingsButtonInitializer) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("LootFeed")

	local function Proxy(key, kind, name, default, get, set)
		return Settings.RegisterProxySetting(category, "LootFeed_" .. key, kind, name, default,
			get or function() return db[key] end, set or function(value) db[key] = value end)
	end
	local function Checkbox(key, name, tooltip, default, get, set)
		Settings.CreateCheckbox(category, Proxy(key, Settings.VarType.Boolean, name, default, get, set), tooltip)
	end
	-- A slider hands over what its arithmetic gives (0.30000000000000004):
	-- store the step it stands on.
	local function Slider(key, name, tooltip, min, max, step, format, default, get, set)
		set = set or function(value) db[key] = value end
		local setting = Proxy(key, Settings.VarType.Number, name, default, get, function(value)
			set(tonumber(("%.4f"):format(min + math.floor((value - min) / step + 0.5) * step)))
		end)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		Settings.CreateSlider(category, setting, options, tooltip)
	end
	-- choices: { value, label, tooltip } each.
	local function Dropdown(key, name, tooltip, choices, default, get, set)
		local function Choices()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(choices) do
				container:Add(choice[1], choice[2], choice[3])
			end
			return container:GetData()
		end
		Settings.CreateDropdown(category, Proxy(key, Settings.VarType.Number, name, default, get, set), Choices, tooltip)
	end
	local function Button(name, text, click, tooltip)
		Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(name, text, click, tooltip, true))
	end

	Slider("scale", "Size", nil, 0.5, 2, 0.05, function(value) return ("%d%%"):format(value * 100 + 0.5) end, 1,
		function() return db.scale or 1 end, SetScale)
	Slider("duration", "Seconds on screen", "How long a line stays before it fades.", 2, 20, 1,
		function(value) return ("%d s"):format(value) end, DEFAULTS.duration)
	Slider("max", "Lines at most", "The oldest line goes when there are more.", 3, 15, 1,
		function(value) return ("%d"):format(value) end, DEFAULTS.max, nil, SetMax)
	local qualities = {}
	for quality = 0, MAX_QUALITY do
		qualities[#qualities + 1] = { quality, QualityName(quality) }
	end
	Dropdown("quality", "Lowest item quality", "Items below this get no line, yours and your group's.", qualities, DEFAULTS.quality)
	Dropdown("partyQuality", "Lowest quality for group loot", "What your group loots gets a line from this quality up. The setting above counts for it as well.",
		qualities, DEFAULTS.partyQuality)
	Checkbox("money", "Money", "Money you loot or are given. Not what a merchant, the mailbox, the auction house or a trade pays.", DEFAULTS.money)
	Checkbox("rep", "Reputation", "A line per faction.", DEFAULTS.rep)
	Checkbox("xp", "Experience", nil, DEFAULTS.xp)
	Checkbox("honor", "Honor", nil, DEFAULTS.honor)
	Checkbox("party", "Group loot", "What members of your group loot, with their name.", DEFAULTS.party)
	Checkbox("unlocked", "Unlock to move", "Shows the anchor of the lines: drag it where you want them, then lock again.", false,
		function() return unlocked or false end, SetUnlocked)
	Button("Try it", "Test lines", Test, "Shows one line of each kind.")
	Button("Position and size", "Reset", Reset, "Back to the right of the middle of the screen at normal size.")

	Settings.RegisterAddOnCategory(category)
end

-- Events and commands ---------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		LootFeedDB = LootFeedDB or {}
		db = LootFeedDB
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				db[key] = value
			end
		end
		lootPatterns, repPatterns, honorPatterns = Compile(LOOT), Compile(REP), Compile(HONORS)
		CreateAnchor()
		local ok, err = pcall(RegisterSettings)
		if not ok then
			print("|cffffd100LootFeed|r: options panel unavailable (" .. tostring(err) .. "); use /lootfeed instead")
		end
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_LOOT", "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_COMBAT_HONOR_GAIN",
			"PLAYER_MONEY", "PLAYER_XP_UPDATE", "BAG_UPDATE_DELAYED" }) do
			pcall(self.RegisterEvent, self, e)
		end
		for open, close in pairs(WINDOWS) do
			pcall(self.RegisterEvent, self, open)
			pcall(self.RegisterEvent, self, close)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMoney = Plain(GetMoney())
		lastXP, lastXPMax = ReadXP()
	elseif event == "CHAT_MSG_LOOT" then
		pcall(OnLoot, ...)
	elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
		pcall(OnRep, ...)
	elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
		pcall(OnHonor, ...)
	elseif event == "PLAYER_MONEY" then
		OnMoney()
	elseif event == "PLAYER_XP_UPDATE" then
		OnXP()
	elseif event == "BAG_UPDATE_DELAYED" then
		for _, row in ipairs(active) do
			if row.kind == "item" and not row.who then
				Refresh(row)
			end
		end
	elseif WINDOWS[event] then
		busy[event] = true
	elseif CLOSES[event] then
		busy[CLOSES[event]] = nil
		busyUntil = GetTime() + BUSY_AFTER
	end
end)

SLASH_LOOTFEED1 = "/lootfeed"
SlashCmdList.LOOTFEED = function(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "unlock" then
		SetUnlocked(true)
	elseif cmd == "lock" then
		SetUnlocked(false)
	elseif cmd == "test" then
		Test()
	elseif cmd == "scale" and tonumber(arg) then
		SetScale(math.min(2, math.max(0.5, tonumber(arg))))
		print(("|cffffd100LootFeed|r: scale %.2f"):format(db.scale))
	elseif (cmd == "quality" or cmd == "groupquality") and tonumber(arg) then
		local key = cmd == "quality" and "quality" or "partyQuality"
		SetQuality(key, tonumber(arg))
		print(("|cffffd100LootFeed|r: %s from %s up"):format(cmd == "quality" and "items" or "group loot", QualityName(db[key])))
	elseif cmd == "reset" then
		Reset()
	elseif cmd == "clear" then
		Clear()
	else
		print("|cffffd100LootFeed|r: /lootfeed unlock | lock | test | clear | scale 0.5-2 | quality 0-4 | groupquality 0-4 | reset")
	end
end
