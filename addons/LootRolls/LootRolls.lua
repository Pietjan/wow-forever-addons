-- LootRolls: group loot rolls as movable bars, laid out like XLoot: the
-- item icon on the left, a timer bar to its right with the item name, and
-- Need / Greed (or Transmog) / Disenchant / Pass at the right end of the
-- bar. Each button counts who chose it; hovering it lists them in class
-- colours. The bar goes as soon as you have rolled (or the time is up).
--
-- Where things come from (Blizzard UI source, 1.60.1):
-- - START_LOOT_ROLL(rollID, rollTime ms) starts a roll; GetLootRollItemInfo
--   describes it; RollOnLoot(rollID, type) rolls (0 pass, 1 need, 2 greed,
--   3 disenchant, 4 transmog). CANCEL_LOOT_ROLL ends it for you, which
--   happens as soon as you have chosen. BoP confirmations stay Blizzard's
--   (its CONFIRM_LOOT_ROLL popup is untouched).
-- - What others chose: C_LootHistory drops (player, class, state, roll;
--   nothing there is marked secret in the API docs) and, as a
--   fallback, the CHAT_MSG_LOOT lines built from LOOT_ROLL_* strings. Chat
--   text can be secret in lockdown, so a secret line is skipped.
-- - Blizzard's own roll frames are kept from opening by unregistering
--   START_LOOT_ROLL from the frames that listen to it. No Blizzard function
--   is called and no Blizzard field is written (see NameOnly/PlateTarget).
--
-- /lootrolls: unlock, lock, test, scale <n>, reset, blizzard.

local ADDON = ...
local IsSecret = issecretvalue or function() return false end

local WIDTH, GAP = 330, 6
local HEIGHT = 46 -- a row
local ICON = 34 -- as in Blizzard's group loot frame
-- The loot toast border is 58px with a 7.5px rim all round (a 43px
-- opening), so at 45px its opening just overlaps a 34px icon.
local BORDER = 45
local ICON_GAP = 6 -- between the icon border and the name and bar
local SHADE = 0.6 -- the backdrop's darkness at the icon
local SHADE_INSET = 1 -- from the row's top and bottom
local SHADE_FADE = 5 -- rows over which its top and bottom edges fade
local NUDGE = 4 -- the name and bar sit this much higher than centred on the icon
local BAR_END = 4 -- the bar ends this far left of the last count's edge
local BAR_HEIGHT = 8 -- the fill; its frame is drawn around it
local BUTTON = 22 -- a roll button
local SLOT = BUTTON + 6 -- a button and the gap to the next

-- The unlocked anchor: a near-black panel with a gold edge.
local BG = { 0.04, 0.04, 0.05, 0.92 }
local GOLD = { 1.00, 0.82, 0.00, 1 }

local ROLL = { PASS = 0, NEED = 1, GREED = 2, DISENCHANT = 3, TRANSMOG = 4 }
local KINDS = { -- right to left at the end of the bar
	{ key = "pass", type = ROLL.PASS, atlas = "pass", label = PASS or "Pass" },
	{ key = "disenchant", type = ROLL.DISENCHANT, atlas = "disenchant", label = ROLL_DISENCHANT or "Disenchant" },
	{ key = "greed", type = ROLL.GREED, atlas = "greed", label = GREED or "Greed" },
	{ key = "transmog", type = ROLL.TRANSMOG, atlas = "transmog", label = TRANSMOGRIFICATION or "Transmog" },
	{ key = "need", type = ROLL.NEED, atlas = "need", label = NEED or "Need" },
}

-- Enum.EncounterLootDropRollState -> button key (NoRoll = still deciding).
local function StateKey(state)
	local states = Enum and Enum.EncounterLootDropRollState
	if not states then
		return nil
	end
	if state == states.NeedMainSpec or state == states.NeedOffSpec then
		return "need"
	elseif state == states.Greed then
		return "greed"
	elseif state == states.Transmog then
		return "transmog"
	elseif state == states.Pass then
		return "pass"
	end
	return nil
end

local db
local anchor
local rows = {} -- rollID -> row
local pool = {}
local claimed = {} -- "encounterID:lootListKey" -> rollID
local unlocked = false
local Layout, Release, Refresh

-- Helpers ---------------------------------------------------------------

local function Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

local function Atlas(name)
	if C_Texture and C_Texture.GetAtlasInfo then
		if C_Texture.GetAtlasInfo(name .. "-c60") then
			return name .. "-c60"
		end
		if C_Texture.GetAtlasInfo(name) then
			return name
		end
	end
	return nil
end

local function Short(name)
	name = Plain(name)
	if type(name) ~= "string" then
		return nil
	end
	return (name:gsub("%-.*$", ""))
end

local function ItemString(link)
	link = Plain(link)
	return type(link) == "string" and link:match("|H(item:[^|]+)|h") or nil
end

-- Same item: compare the item ID plus the rest of the item string; fall
-- back to the ID alone, since the history link can carry other bonus data.
local function SameItem(a, b)
	local sa, sb = ItemString(a), ItemString(b)
	if not sa or not sb then
		return false
	end
	if sa == sb then
		return true
	end
	return sa:match("^item:(%d+)") == sb:match("^item:(%d+)")
end

local function QualityColor(quality)
	local data = ColorManager and ColorManager.GetColorDataForItemQuality and ColorManager.GetColorDataForItemQuality(quality)
	if data and data.r then
		return data.r, data.g, data.b
	end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
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
	local units = { "player" }
	if IsInRaid() then
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
	function lines:SetColor(r, g, b, a)
		for i = 1, 4 do
			self[i]:SetColorTexture(r, g, b, a or 1)
		end
	end
	return lines
end

local function Font(name, fallback)
	return _G[name] and name or fallback
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
		anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
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
	anchor = CreateFrame("Frame", "LootRollsAnchor", UIParent)
	anchor:SetSize(WIDTH, HEIGHT)
	anchor:SetFrameStrata("HIGH")
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
	anchor.edges = Edges(anchor, GOLD)
	local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER")
	text:SetText("LootRolls: drag me, then /lootrolls lock")
	anchor.parts = { bg, text, unpack(anchor.edges) }
	for _, part in ipairs(anchor.parts) do
		part:Hide()
	end
	PlaceAnchor()
end

local function SetUnlocked(on)
	unlocked = on
	anchor:EnableMouse(on)
	for _, part in ipairs(anchor.parts) do
		part:SetShown(on)
	end
	Layout()
end

-- Rows ------------------------------------------------------------------

-- The roll buttons' own tooltip, in Blizzard's tooltip style, so its
-- first line's font can be set without touching GameTooltip.
local buttonTip
local function ButtonTip()
	if not buttonTip then
		buttonTip = CreateFrame("GameTooltip", "LootRollsButtonTooltip", UIParent, "GameTooltipTemplate")
	end
	return buttonTip
end

local function ButtonTooltip(button)
	local row = button.row
	local tip = ButtonTip()
	tip:SetOwner(button, "ANCHOR_TOP")
	if button.reason then
		tip:AddLine(button.reason, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
	end
	local names = {}
	for name, choice in pairs(row.choices) do
		if choice.key == button.kind.key then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local choice = row.choices[name]
		local left = ClassText(name, choice.class)
		if choice.roll then
			tip:AddDoubleLine(left, tostring(choice.roll), 1, 1, 1, 0.8, 0.8, 0.8)
		else
			tip:AddLine(left, 1, 1, 1)
		end
	end
	if #names == 0 then
		tip:AddLine("Nobody", 0.5, 0.5, 0.5)
	end
	local waiting = {}
	for name, class in pairs(row.waiting) do
		waiting[#waiting + 1] = ClassText(name, class)
	end
	if #waiting > 0 then
		table.sort(waiting)
		tip:AddLine(" ")
		tip:AddLine("Waiting on: " .. table.concat(waiting, ", "), 0.6, 0.6, 0.6, true)
	end
	-- A tooltip's first line is its title, in a larger font; here every
	-- line is a name, so all get the normal one.
	for _, side in ipairs({ "Left", "Right" }) do
		local line = _G[tip:GetName() .. "Text" .. side .. "1"]
		if line then
			line:SetFontObject(GameTooltipText)
		end
	end
	tip:Show()
end

local function OnButtonClick(button)
	local row = button.row
	if not button:IsEnabled() then
		return
	end
	if row.fake then
		Release(row)
		return
	end
	-- CANCEL_LOOT_ROLL then removes the bar (after Blizzard's BoP
	-- confirmation, when the item asks for one).
	RollOnLoot(row.rollID, button.kind.type)
end

-- Quality border round the icon: Blizzard's own loot toast borders.
local BORDERS = {
	[0] = "loottoast-itemborder-gray", [1] = "loottoast-itemborder-gray",
	[2] = "loottoast-itemborder-green", [3] = "loottoast-itemborder-blue",
	[4] = "loottoast-itemborder-purple", [5] = "loottoast-itemborder-orange",
	[6] = "loottoast-itemborder-artifact", [7] = "loottoast-itemborder-heirloom",
}

local function BorderAtlas(quality)
	local ok, atlas = pcall(function()
		return ColorManager and ColorManager.GetAtlasDataForLootBorderItemQuality
			and ColorManager.GetAtlasDataForLootBorderItemQuality(quality)
	end)
	if ok and type(atlas) == "string" and Atlas(atlas) then
		return Atlas(atlas)
	end
	return Atlas(BORDERS[quality] or BORDERS[2])
end

-- A row, in the pieces of Forever's own buff bars (cooldown manager):
--   [icon]  Item name                      BoP  [need]2 [greed]4 [pass]1
--           [=========== timer bar ==========|                ]
local function CreateRow()
	local row = CreateFrame("Frame", nil, anchor)
	row:SetSize(WIDTH, HEIGHT)
	row:EnableMouse(true)
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function()
		if unlocked then
			anchor:StartMoving()
		end
	end)
	row:SetScript("OnDragStop", function()
		if unlocked then
			anchor:GetScript("OnDragStop")(anchor)
		end
	end)

	local icon = CreateFrame("Button", nil, row)
	icon:SetSize(ICON, ICON)
	icon:SetPoint("LEFT", (BORDER - ICON) / 2, 0)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- without the icon's own dark edge
	icon.border = icon:CreateTexture(nil, "OVERLAY")
	icon.border:SetSize(BORDER, BORDER)
	icon.border:SetPoint("CENTER")
	icon.count = icon:CreateFontString(nil, "OVERLAY", Font("NumberFontNormal", "GameFontHighlight"))
	icon.count:SetPoint("BOTTOMRIGHT", -3, 2)
	-- UpgradeArrow's green arrow when the item is an upgrade for you.
	if UpgradeArrow and UpgradeArrow.CreateArrow then
		icon.upgrade = UpgradeArrow.CreateArrow(icon)
	end
	icon:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if row.fake then
			if row.link then
				GameTooltip:SetHyperlink(row.link)
			end
		else
			GameTooltip:SetLootRollItem(row.rollID)
		end
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", GameTooltip_Hide)
	icon:SetScript("OnClick", function()
		if row.link then
			pcall(HandleModifiedItemClick, row.link)
		end
	end)
	row.icon = icon

	-- Timer bar: the cooldown manager's bar, fill and pip.
	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetHeight(BAR_HEIGHT)
	-- Its frame's left line (2 units left of the fill) starts ICON_GAP after
	-- the icon border (5.5 right of the icon), and its bottom line (3 below the
	-- fill) meets the border's bottom (5.5 below the icon).
	local unit = BAR_HEIGHT / 8
	bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", (BORDER - ICON) / 2 + 2 * unit + ICON_GAP, 3 * unit - (BORDER - ICON) / 2 + 1 + NUDGE)
	bar:SetPoint("RIGHT", -6 - BAR_END, 0)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	local fillAtlas = Atlas("ui-hud-cooldownmanager-bar")
	if fillAtlas then
		fill:SetAtlas(fillAtlas)
	else
		fill:SetColorTexture(1, 1, 1, 1)
	end
	bar:SetStatusBarTexture(fill)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	local bgAtlas = Atlas("ui-hud-cooldownmanager-bar-bg")
	if bgAtlas then
		barBg:SetAtlas(bgAtlas)
		-- The art is 132x19: its frame lines are row 1 and 12 and columns
		-- 1 and 126, with shadow below and right, so the opening is rows
		-- 2-11, columns 2-125. The fill sits in it with 1px to spare all
		-- round (rows 3-10, columns 3-124); a fill as tall as the opening
		-- rounds onto the frame lines at most UI scales.
		barBg:SetPoint("TOPLEFT", -3 * unit, 3 * unit)
		barBg:SetPoint("BOTTOMRIGHT", 7 * unit, -8 * unit)
	else
		barBg:SetAllPoints()
		barBg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
	end
	local pipAtlas = Atlas("ui-hud-cooldownmanager-bar-pip")
	if pipAtlas then
		local pip = bar:CreateTexture(nil, "OVERLAY")
		pip:SetAtlas(pipAtlas)
		pip:SetSize(5, BAR_HEIGHT * 2.4)
		pip:SetPoint("CENTER", fill, "RIGHT", 0, 0)
		bar.pip = pip
	end
	row.bar = bar

	-- A soft shadow from the icon to the end of the bar, fading out to the
	-- right, so the text reads over bright ground.
	-- A texture fades one way only, so the top and bottom edges are thin
	-- strips of their own, each a little fainter towards the edge.
	local function Strip(topOffset, height, strength)
		local strip = row:CreateTexture(nil, "BACKGROUND", nil, -8)
		-- From 3 in from the icon border's left (the row's left) to the bar
		-- frame's right line (3 units right of the fill).
		strip:SetPoint("TOPLEFT", 3, -topOffset)
		strip:SetPoint("TOPRIGHT", -6 - BAR_END + 3 * BAR_HEIGHT / 8, -topOffset)
		strip:SetHeight(height)
		strip:SetColorTexture(1, 1, 1, 1)
		strip:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, SHADE * strength), CreateColor(0, 0, 0, 0))
	end
	local inner = HEIGHT - 2 * SHADE_INSET
	for i = 1, SHADE_FADE do
		local strength = i / (SHADE_FADE + 1)
		Strip(SHADE_INSET + i - 1, 1, strength) -- top edge, fading in
		Strip(SHADE_INSET + inner - i, 1, strength) -- bottom edge
	end
	Strip(SHADE_INSET + SHADE_FADE, inner - 2 * SHADE_FADE, 1)

	-- The line above the bar: name on the left, buttons on the right.
	local top = CreateFrame("Frame", nil, row)
	top:SetPoint("TOPLEFT", icon, "TOPRIGHT", (BORDER - ICON) / 2 + ICON_GAP, NUDGE) -- text starts at the bar frame's left line
	top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", BAR_END, 2) -- buttons keep their place

	row.buttons = {}
	for _, kind in ipairs(KINDS) do
		local button = CreateFrame("Button", nil, top)
		-- Pass's glyph fills more of its square than the dice and coin.
		local size = kind.key == "pass" and BUTTON - 4 or BUTTON
		button:SetSize(size, size)
		button:SetMotionScriptsWhileDisabled(true)
		local up = Atlas("lootroll-toast-icon-" .. kind.atlas .. "-up")
		if up then
			button:SetNormalAtlas(up)
			button:SetPushedAtlas(Atlas("lootroll-toast-icon-" .. kind.atlas .. "-down") or up)
			button:SetHighlightAtlas(Atlas("lootroll-toast-icon-" .. kind.atlas .. "-highlight") or up, "ADD")
		end
		-- The count sits on the icon, bottom right, as on action buttons.
		local counter = CreateFrame("Frame", nil, button)
		counter:SetAllPoints()
		counter:SetFrameLevel(button:GetFrameLevel() + 2)
		button.count = counter:CreateFontString(nil, "OVERLAY", Font("NumberFontNormalSmall", "GameFontHighlightSmall"))
		button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3 + (BUTTON - size) / 2, -2 - (BUTTON - size) / 2)
		button.count:SetJustifyH("RIGHT")
		button.kind, button.row = kind, row
		-- A soft pale glow behind the icon while the mouse is on it (the
		-- bonus roll chest's glow), on top of the button's own highlight.
		local glowAtlas = Atlas("BonusChest-CircleGlow")
		if glowAtlas then
			local glow = button:CreateTexture(nil, "BACKGROUND")
			glow:SetAtlas(glowAtlas)
			glow:SetSize(BUTTON * 1.9, BUTTON * 1.9)
			glow:SetPoint("CENTER")
			glow:SetBlendMode("ADD")
			glow:SetVertexColor(1, 0.94, 0.78, 0.55) -- a pale, soft gold
			glow:Hide()
			button.glow = glow
		end
		button:SetScript("OnEnter", function(self)
			if self.glow and self:IsEnabled() then
				self.glow:Show()
			end
			ButtonTooltip(self)
		end)
		button:SetScript("OnLeave", function(self)
			if self.glow then
				self.glow:Hide()
			end
			ButtonTip():Hide()
		end)
		button:SetScript("OnClick", OnButtonClick)
		row.buttons[kind.key] = button
	end

	local bop = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bop:SetText("BoP")
	bop:SetTextColor(1, 0.45, 0.2)
	row.bop = bop

	local name = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("LEFT", 0, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.name = name
	row.top = top

	row:SetScript("OnUpdate", function(self, elapsed)
		self.tick = (self.tick or 0) + elapsed
		if self.tick < 0.03 then
			return
		end
		self.tick = 0
		local left = self.endTime - GetTime()
		self.bar:SetValue(math.max(0, left))
		if self.bar.pip then
			self.bar.pip:SetShown(left > 0)
		end
		if left < -1 then
			Release(self) -- time is up and no CANCEL_LOOT_ROLL came
		end
	end)
	return row
end

-- Place the visible buttons right to left on the top line, each with room
-- for its count; BoP and the name go to their left.
local function PlaceButtons(row)
	local right = -2
	for _, kind in ipairs(KINDS) do
		local button = row.buttons[kind.key]
		if button:IsShown() then
			-- Centred in a BUTTON-wide cell, whatever its own size.
			button:ClearAllPoints()
			button:SetPoint("CENTER", row.top, "RIGHT", right - BUTTON / 2, 1)
			right = right - SLOT
		end
	end
	local edge = right + SLOT - BUTTON - 6
	row.bop:ClearAllPoints()
	row.bop:SetPoint("RIGHT", row.top, "RIGHT", edge, 0)
	if row.bop:IsShown() then
		edge = edge - row.bop:GetStringWidth() - 6
	end
	row.name:SetPoint("RIGHT", row.top, "RIGHT", edge, 0)
end

local function EnableButton(button, on, reason)
	button:SetEnabled(on)
	button:SetAlpha(on and 1 or 0.35)
	local normal = button:GetNormalTexture()
	if normal then
		normal:SetDesaturated(not on)
	end
	button.reason = reason
end

-- The counts on the buttons.
function Refresh(row)
	local counts = {}
	for _, choice in pairs(row.choices) do
		counts[choice.key] = (counts[choice.key] or 0) + 1
	end
	for key, button in pairs(row.buttons) do
		local n = counts[key] or 0
		button.count:SetText(n > 0 and n or "")
	end
end

function Release(row)
	if rows[row.rollID] ~= row then
		return -- already released
	end
	row:Hide()
	if GameTooltip:IsOwned(row.icon) then
		GameTooltip:Hide()
	end
	for _, button in pairs(row.buttons) do
		if ButtonTip():IsOwned(button) then
			ButtonTip():Hide()
		end
		if button.glow then
			button.glow:Hide()
		end
	end
	if row.rollID then
		rows[row.rollID] = nil
	end
	for key, id in pairs(claimed) do
		if id == row.rollID then
			claimed[key] = nil
		end
	end
	row.rollID = nil
	pool[#pool + 1] = row
	Layout()
end

function Layout()
	local list = {}
	for _, row in pairs(rows) do
		list[#list + 1] = row
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	local down = GrowsDown()
	local offset = unlocked and (HEIGHT + GAP) or 0
	for _, row in ipairs(list) do
		row:ClearAllPoints()
		if down then
			row:SetPoint("TOP", anchor, "TOP", 0, -offset)
		else
			row:SetPoint("BOTTOM", anchor, "BOTTOM", 0, offset)
		end
		offset = offset + HEIGHT + GAP
	end
end

local order = 0

-- info: texture, name, count, quality, bop, canNeed, canGreed,
-- canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, canTransmog.
local function ShowRow(rollID, duration, info, fake)
	local row = table.remove(pool) or CreateRow()
	order = order + 1
	row.order = order
	row.rollID, row.fake = rollID, fake
	row.link = info.link
	row.choices, row.waiting = {}, {}
	row.historyKey, row.chatID = nil, nil
	row.endTime = GetTime() + duration

	local r, g, b = QualityColor(info.quality)
	row.icon.texture:SetTexture(info.texture)
	local border = BorderAtlas(info.quality)
	row.icon.border:SetShown(border ~= nil)
	if border then
		row.icon.border:SetAtlas(border)
	end
	row.icon.count:SetText((info.count or 1) > 1 and info.count or "")
	if row.icon.upgrade then
		row.icon.upgrade:SetShown(info.link and UpgradeArrow.IsUpgrade(info.link) or false)
	end
	row.name:SetText(info.name or "")
	row.name:SetTextColor(r, g, b)
	row.bop:SetShown(info.bop and true or false)
	row.bar:SetMinMaxValues(0, math.max(duration, 1))
	row.bar:SetValue(duration)
	row.bar:SetStatusBarColor(r, g, b, 1)

	local reason = function(n)
		return n and _G["LOOT_ROLL_INELIGIBLE_REASON" .. n] or nil
	end
	local buttons = row.buttons
	buttons.need:Show()
	EnableButton(buttons.need, info.canNeed, not info.canNeed and reason(info.reasonNeed) or nil)
	buttons.transmog:SetShown(info.canTransmog and true or false)
	buttons.greed:SetShown(not info.canTransmog)
	EnableButton(buttons.transmog, true)
	EnableButton(buttons.greed, info.canGreed, not info.canGreed and reason(info.reasonGreed) or nil)
	buttons.disenchant:SetShown(info.canDisenchant and true or false)
	EnableButton(buttons.disenchant, info.canDisenchant, nil)
	buttons.pass:Show()
	EnableButton(buttons.pass, true)
	PlaceButtons(row)

	rows[rollID] = row
	row:Show()
	Refresh(row)
	Layout()
	return row
end

-- Loot history ----------------------------------------------------------

local function ApplyDrop(row, drop)
	row.waiting = {}
	for _, info in ipairs(drop.rollInfos or {}) do
		local name = Short(info.playerName)
		if name then
			local key = StateKey(Plain(info.state))
			local class = Plain(info.playerClass)
			if key then
				row.choices[name] = { key = key, class = class, roll = Plain(info.roll) }
			elseif not row.choices[name] then
				row.waiting[name] = class or false
			end
		end
	end
	Refresh(row)
end

local function CheckDrop(encounterID, lootListKey)
	if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then
		return
	end
	local ok, drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListKey)
	if not ok or type(drop) ~= "table" then
		return
	end
	local key = encounterID .. ":" .. lootListKey
	local rollID = claimed[key]
	local row = rollID and rows[rollID]
	if not row then
		-- The oldest unmatched roll of this item.
		local best
		for _, candidate in pairs(rows) do
			if not candidate.fake and not candidate.historyKey and SameItem(candidate.link, drop.itemHyperlink)
				and (not best or candidate.order < best.order) then
				best = candidate
			end
		end
		row = best
		if not row or Plain(drop.winner) or Plain(drop.allPassed) then
			return -- an older drop of the same item, already decided
		end
		local now = C_LootHistory.GetLootHistoryTime and Plain(C_LootHistory.GetLootHistoryTime())
		local start, duration = Plain(drop.startTime), Plain(drop.duration)
		if type(now) == "number" and type(start) == "number" and type(duration) == "number" and duration > 0
			and now - start > duration + 5 then
			return -- its roll ended before
		end
		row.historyKey = key
		claimed[key] = row.rollID
	end
	pcall(ApplyDrop, row, drop)
end

local function ScanHistory()
	if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then
		return
	end
	local ok, encounters = pcall(C_LootHistory.GetAllEncounterInfos)
	if not ok or type(encounters) ~= "table" then
		return
	end
	for _, encounter in ipairs(encounters) do
		local id = Plain(encounter.encounterID)
		local okDrops, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, id)
		if id and okDrops and type(drops) == "table" then
			for _, drop in ipairs(drops) do
				local key = Plain(drop.lootListKey)
				if key then
					CheckDrop(id, key)
				end
			end
		end
	end
end

-- Chat fallback ---------------------------------------------------------

-- Lua pattern from a format string; captures in the order of the %s/%d.
local function Pattern(format)
	if type(format) ~= "string" then
		return nil
	end
	local p = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	p = p:gsub("%%d", "(%%d+)"):gsub("%%s", "(.+)")
	return "^" .. p .. "$"
end

-- name/item/roll/id positions per string.
local CHAT = {
	{ "LOOT_ROLL_NEED", "need", { "id", "name", "item" } },
	{ "LOOT_ROLL_GREED", "greed", { "id", "name", "item" } },
	{ "LOOT_ROLL_TRANSMOG", "transmog", { "id", "name", "item" } },
	{ "LOOT_ROLL_PASSED", "pass", { "id", "name", "item" } },
	{ "LOOT_ROLL_DISENCHANT", "disenchant", { "name", "item" } },
	{ "LOOT_ROLL_NEED_SELF", "need", { "id", "item" }, true },
	{ "LOOT_ROLL_GREED_SELF", "greed", { "id", "item" }, true },
	{ "LOOT_ROLL_TRANSMOG_SELF", "transmog", { "id", "item" }, true },
	{ "LOOT_ROLL_PASSED_SELF", "pass", { "id", "item" }, true },
	{ "LOOT_ROLL_ROLLED_NEED", "need", { "id", "roll", "item", "name" } },
	{ "LOOT_ROLL_ROLLED_GREED", "greed", { "id", "roll", "item", "name" } },
}
local chatPatterns

local function BuildChatPatterns()
	chatPatterns = {}
	for _, entry in ipairs(CHAT) do
		local format = _G[entry[1]]
		local pattern = Pattern(format)
		if pattern then
			-- Strings without the history link (Disenchant) have no id.
			local fields = entry[3]
			if fields[1] == "id" and not format:find("^|HlootHistory") then
				fields = { select(2, unpack(fields)) }
			end
			chatPatterns[#chatPatterns + 1] = { pattern = pattern, key = entry[2], fields = fields, self = entry[4] }
		end
	end
	-- "You passed on: x" also fits "%s passed on: %s" (with "You" as the
	-- name), so the strings about yourself go first, then the longer ones.
	table.sort(chatPatterns, function(a, b)
		if (a.self or false) ~= (b.self or false) then
			return a.self or false
		end
		return #a.pattern > #b.pattern
	end)
end

local function RowForChat(id, item, name)
	for _, row in pairs(rows) do
		if not row.fake and id and row.chatID == id then
			return row
		end
	end
	local best
	for _, row in pairs(rows) do
		if not row.fake and not row.chatID and SameItem(row.link, item)
			and not (name and row.choices[name])
			and (not best or row.order < best.order) then
			best = row
		end
	end
	if best then
		best.chatID = id
	end
	return best
end

local function OnChat(text)
	if Plain(text) == nil or type(text) ~= "string" then
		return
	end
	if not chatPatterns then
		BuildChatPatterns()
	end
	for _, entry in ipairs(chatPatterns) do
		local captures = { text:match(entry.pattern) }
		if #captures > 0 then
			local got = {}
			for i, field in ipairs(entry.fields) do
				got[field] = captures[i]
			end
			local name = entry.self and Short(UnitName("player")) or Short(got.name)
			local row = RowForChat(got.id, got.item, not got.roll and name or nil)
			if not row then
				return
			end
			if name then
				local choice = row.choices[name] or { class = ClassOf(name) }
				choice.key = entry.key
				if got.roll then
					choice.roll = tonumber(got.roll)
				end
				row.choices[name] = choice
				row.waiting[name] = nil
				Refresh(row)
			end
			return
		end
	end
end

-- Rolls -----------------------------------------------------------------

local function StartRoll(rollID, rollTime, retried)
	if rows[rollID] then
		return
	end
	local texture, name, count, quality, bop, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, _, canTransmog = GetLootRollItemInfo(rollID)
	if not name then
		if not retried then
			C_Timer.After(0.3, function()
				StartRoll(rollID, rollTime, true)
			end)
		end
		return
	end
	local left = GetLootRollTimeLeft and GetLootRollTimeLeft(rollID)
	local seconds = ((Plain(left) or rollTime or 60000) / 1000)
	ShowRow(rollID, seconds, {
		texture = texture, name = name, count = count, quality = quality, bop = bop,
		canNeed = canNeed, canGreed = canGreed, canDisenchant = canDisenchant, canTransmog = canTransmog,
		reasonNeed = reasonNeed, reasonGreed = reasonGreed, reasonDisenchant = reasonDisenchant,
		link = GetLootRollItemLink and GetLootRollItemLink(rollID),
	})
	ScanHistory()
end

-- Ends the roll for you: you chose, or it ran out. The bar goes.
local function CancelRoll(rollID)
	local row = rows[rollID]
	if row and not row.fake then
		Release(row)
	end
end

local function RefreshActive()
	if not GetActiveLootRollIDs then
		return
	end
	local ok, ids = pcall(GetActiveLootRollIDs)
	if ok and type(ids) == "table" then
		for _, id in ipairs(ids) do
			local duration = C_Loot and C_Loot.GetLootRollDuration and C_Loot.GetLootRollDuration(id)
			StartRoll(id, duration)
		end
	end
end

-- Blizzard's frames ---------------------------------------------------------

local muted = {}
local events = CreateFrame("Frame") -- ours: START_LOOT_ROLL stays registered here

local function MuteBlizzard(on)
	if on then
		local ok, frames = pcall(function()
			return { GetFramesRegisteredForEvent("START_LOOT_ROLL") }
		end)
		if not ok then
			return
		end
		for _, frame in ipairs(frames) do
			if frame ~= events and not muted[frame] then
				if pcall(frame.UnregisterEvent, frame, "START_LOOT_ROLL") then
					muted[frame] = true
				end
			end
		end
	else
		for frame in pairs(muted) do
			pcall(frame.RegisterEvent, frame, "START_LOOT_ROLL")
			muted[frame] = nil
		end
	end
end

-- Test mode ---------------------------------------------------------------

local FAKE_PLAYERS = {
	{ "Thrall", "SHAMAN" }, { "Jaina", "MAGE" }, { "Uther", "PALADIN" },
	{ "Valeera", "ROGUE" }, { "Rexxar", "HUNTER" }, { "Malfurion", "DRUID" },
}
local FAKE_ITEMS = { -- itemID, quality, bop, can need
	{ 19019, 5, true, true },
	{ 18832, 4, true, true },
	{ 13965, 3, false, false },
	{ 2042, 2, false, true }, -- Staff of Westfall: an uncommon, bind on equip
}
local fakeID = -1

local function Test()
	for i, item in ipairs(FAKE_ITEMS) do
		local id, quality, bop, canNeed = unpack(item)
		local name, link, _, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
		if not texture then
			texture = select(5, C_Item.GetItemInfoInstant(id))
		end
		local rollID = fakeID
		fakeID = fakeID - 1
		local row = ShowRow(rollID, 35 - i * 5, {
			texture = texture or 134400, name = name or ("Test item " .. id), count = 1, quality = quality,
			bop = bop, canNeed = canNeed, canGreed = true, reasonNeed = 2,
			link = link or ("item:" .. id),
		}, true)
		-- Others choose over a few seconds.
		for p, player in ipairs(FAKE_PLAYERS) do
			C_Timer.After(p * 0.7 + i * 0.3, function()
				if rows[rollID] == row then
					local key = (p + i) % 3 == 0 and "pass" or ((p % 2 == 0 and canNeed) and "need" or "greed")
					row.choices[player[1]] = { key = key, class = player[2], roll = key ~= "pass" and math.random(1, 100) or nil }
					Refresh(row)
				end
			end)
		end
	end
	print("|cffffd100LootRolls|r: four test rolls; click a button to dismiss one. /lootrolls unlock to drag them.")
end

-- Settings: the slash command and the options window both change them here.

local function SetScale(scale)
	db.scale = scale
	anchor:SetScale(scale)
end

local function SetBlizzard(on)
	db.blizzard = on
	MuteBlizzard(not on)
end

local function Reset()
	db.point, db.scale = nil, nil
	PlaceAnchor()
	Layout()
end

------------------------------------------------------------------------------
-- The game's options window (Options > AddOns): the settings of the slash
-- command as check boxes, a slider and buttons. Optional: without the
-- game's settings API the slash command still does everything.
------------------------------------------------------------------------------

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.CreateSlider and Settings.RegisterInitializer and CreateSettingsButtonInitializer) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("LootRolls")

	local function Proxy(key, kind, name, default, get, set)
		return Settings.RegisterProxySetting(category, "LootRolls_" .. key, kind, name, default,
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
	local function Button(name, text, click, tooltip)
		Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(name, text, click, tooltip, true))
	end

	Slider("scale", "Size", nil, 0.5, 2, 0.05, function(value) return ("%d%%"):format(value * 100 + 0.5) end, 1,
		function() return db.scale or 1 end, SetScale)
	Checkbox("blizzard", "Blizzard's roll frames as well", "Leaves the game's own roll frames on beside these.", false, nil, SetBlizzard)
	Checkbox("unlocked", "Unlock to move", "Shows the anchor of the roll frames: drag it where you want them, then lock again.", false,
		function() return unlocked end, SetUnlocked)
	Button("Try it", "Test rolls", Test, "Shows four test rolls; click a button on one to dismiss it.")
	Button("Position and size", "Reset", Reset, "Back to the middle of the screen at normal size.")

	Settings.RegisterAddOnCategory(category)
end

-- Events and commands ---------------------------------------------------

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		LootRollsDB = LootRollsDB or {}
		db = LootRollsDB
		if db.blizzard == nil then
			db.blizzard = false
		end
		CreateAnchor()
		local ok, err = pcall(RegisterSettings)
		if not ok then
			print("|cffffd100LootRolls|r: options panel unavailable (" .. tostring(err) .. "); use /lootrolls instead")
		end
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS",
			"MAIN_SPEC_NEED_ROLL", "LOOT_HISTORY_UPDATE_DROP", "CHAT_MSG_LOOT" }) do
			pcall(self.RegisterEvent, self, e)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not db.blizzard then
			MuteBlizzard(true)
		end
		RefreshActive()
	elseif event == "START_LOOT_ROLL" then
		local rollID, rollTime = ...
		StartRoll(rollID, rollTime)
		if not db.blizzard then
			MuteBlizzard(true) -- in case a Blizzard frame registered after login
		end
	elseif event == "CANCEL_LOOT_ROLL" then
		CancelRoll(...)
	elseif event == "CANCEL_ALL_LOOT_ROLLS" then
		for _, row in pairs(rows) do
			if not row.fake then
				Release(row)
			end
		end
	elseif event == "MAIN_SPEC_NEED_ROLL" then
		local rollID, roll = ...
		local row = rows[rollID]
		local me = Short(UnitName("player"))
		if row and me and Plain(roll) then
			local choice = row.choices[me] or { key = "need", class = select(2, UnitClass("player")) }
			choice.roll = roll
			row.choices[me] = choice
			Refresh(row)
		end
	elseif event == "LOOT_HISTORY_UPDATE_DROP" then
		local encounterID, lootListKey = ...
		if Plain(encounterID) and Plain(lootListKey) then
			CheckDrop(encounterID, lootListKey)
		end
	elseif event == "CHAT_MSG_LOOT" then
		pcall(OnChat, ...)
	end
end)

SLASH_LOOTROLLS1 = "/lootrolls"
SLASH_LOOTROLLS2 = "/lr"
SlashCmdList.LOOTROLLS = function(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "unlock" then
		SetUnlocked(true)
	elseif cmd == "lock" then
		SetUnlocked(false)
	elseif cmd == "test" then
		Test()
	elseif cmd == "scale" and tonumber(arg) then
		SetScale(math.min(2, math.max(0.5, tonumber(arg))))
		print(("|cffffd100LootRolls|r: scale %.2f"):format(db.scale))
	elseif cmd == "reset" then
		Reset()
	elseif cmd == "blizzard" then
		SetBlizzard(not db.blizzard)
		print("|cffffd100LootRolls|r: Blizzard's roll frames " .. (db.blizzard and "on (as well)" or "off"))
	elseif cmd == "clear" then
		for _, row in pairs(rows) do
			Release(row)
		end
	else
		print("|cffffd100LootRolls|r: /lootrolls unlock | lock | test | clear | scale 0.5-2 | reset | blizzard")
	end
end
