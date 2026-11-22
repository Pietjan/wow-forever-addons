-- HealerMana: the mana of the healers in your party or raid, as a column of
-- rows: class icon in the Cooldown Manager's border (as BuffNag wears it),
-- next to it the name in class colour, small, over the mana as a
-- percentage, large ("Dead" or "Offline" in its place). While the healer
-- carries a soulstone, its icon covers the class icon; Innervate covers
-- that, and a drink covers both, each with a pulsing glow around the
-- border. The drink goes when the mana reads 100%, Innervate when it ends.
--
-- How, within Forever's rules: in combat a unit's mana is a secret value.
-- An addon may not compare it or calculate with it, but may hand it to a
-- font string, which is all this file does with it: UnitPowerPercent
-- (scaled to 100 by the game's own curve) into FontString:SetFormattedText.
-- So there is no sorting by mana and no low-mana sound: only what you see.
-- The colour of the percentage (white from 70%, yellow under it, orange
-- under 40%, red under 20%) is the game's doing as well: it turns the
-- percentage into a colour through a curve of ours. Hiding the drink at full mana goes the same way: the
-- game turns the percentage into an alpha through a curve of ours (1 below
-- full, 0 at full) and that alpha is set on the drink's layer unseen.
--
-- The three icons are auras, which an addon may not read either: each row
-- has the game's aura container (see TargetDebuffs) on the healer, filtered
-- to the spell IDs below. Spell-ID filters are honoured for helpful auras
-- on group members (AuraContainerUtil.CanApplyIdentityCandidateFilters).
--
-- Who is a healer: the members whose assigned role is healer. In a group
-- where nobody has a role at all, the classes that can heal instead
-- (priest, druid, paladin, shaman). Names, classes and roles may be kept
-- from addons too, so the list is read when the group changes and at the
-- end of a fight, and when the game will not say, the last list stays.
--
-- No mouse interaction. /healermana unlocks a block to drag (the column
-- hangs from it), /healermana again locks it, /healermana reset puts it
-- back. /healermana test adds yourself as a healer, also without a group,
-- and under you four stand-ins, one per healing class: one low on mana, one
-- drinking, one dead and one offline. The stand-ins are made up, their
-- drink icon included: they show the looks and prove nothing about what
-- the game does for a real healer.

local ADDON_NAME = ...

local ICON = 30 -- the class icon
local ICON_OUTSET = 0.5 -- the picture reaches this far under the border ring, so it fills the frame
local RING_REACH = { 6, 5 } -- the ring's reach past a 30 px icon, as the Cooldown Manager sizes it
local HEIGHT = ICON
local ROW_GAP = 8 -- between rows: the ring takes most of it
local TEXT_GAP = 6 -- from the icon to the text, just clear of the ring
local TEXT_WIDTH = 90 -- longer names are cut off
local WIDTH = ICON + TEXT_GAP + TEXT_WIDTH
local OUT_ALPHA = 0.5 -- a dead or offline healer's row
local DEFAULT_POINT = { "CENTER", -300, 0 }

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local HEALING_CLASSES = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

-- Every spell ID named exactly "Drink", "Innervate" or "Soulstone
-- Resurrection" in the client's SpellName table (the copy in
-- scratchpad/groupdebuffs), so every rank is covered. Food that also gives
-- mana goes by other names and is not in here.
local DRINK_SPELLS = {
	430, 431, 432, 1133, 1135, 1137, 10250, 22734, 24355, 25696, 26261, 26402, 26473, 26475, 29007,
	446714, 468767, 1330734,
}
local INNERVATE_SPELLS = { 29166, 456195 }
local SOULSTONE_SPELLS = { 20707, 20762, 20763, 20764, 20765 } -- Soulstone Resurrection
local GLOW_COLOR = { 0.4, 0.8, 1 } -- the glow of a drink or Innervate: mana coming back

-- Mana as a fraction in, the drink layer's alpha out: there below full,
-- gone from where the text rounds to 100%. Nil on a client without curves;
-- the drink then shows for as long as it lasts.
-- Mana as a fraction in, the colour of the percentage out. The steps sit
-- where the text rounds up to the next whole number, so "70%" is never
-- yellow. Nil on a client without curves; the text is then white.
local VALUE_COLORS = {
	{ 0, 1, 0.2, 0.2 }, -- red
	{ 0.195, 1, 0.55, 0.1 }, -- orange from 20%
	{ 0.395, 1, 0.9, 0.2 }, -- yellow from 40%
	{ 0.695, 1, 1, 1 }, -- white from 70%
}
local valueColorCurve
pcall(function()
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	for _, step in ipairs(VALUE_COLORS) do
		curve:AddPoint(step[1], CreateColor(step[2], step[3], step[4], 1))
	end
	valueColorCurve = curve
end)

local FULL = 0.995
local drinkAlphaCurve
pcall(function()
	local curve = C_CurveUtil.CreateCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	curve:AddPoint(0, 1)
	curve:AddPoint(FULL, 0)
	drinkAlphaCurve = curve
end)

-- Test mode's stand-ins.
local FAKES = {
	{ name = "Priest", class = "PRIEST", percent = 23 },
	{ name = "Druid", class = "DRUID", percent = 61, drinking = true },
	{ name = "Paladin", class = "PALADIN", status = "Dead" },
	{ name = "Shaman", class = "SHAMAN", status = "Offline" },
}
local DRINK_ICON = 430 -- the spell whose picture a stand-in's drink shows

local db
local unlocked = false
local testing = false

local function Print(text, ...)
	print("|cff33ff99HealerMana|r: " .. text:format(...))
end

------------------------------------------------------------------------------
-- The anchor
------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "HealerManaAnchor", UIParent)
anchor:SetSize(WIDTH, HEIGHT)
anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3])
anchor:SetMovable(true)
if ForeverSnap then ForeverSnap.Register(anchor) end -- snaps to the screen and our other frames
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)

-- What you drag while unlocked: a green block over the anchor that sticks
-- out above the column, since the first row covers the anchor itself. The
-- anchor's mouse area is stretched upwards to match it.
local HANDLE_RISE = 16
local handle = anchor:CreateTexture(nil, "BACKGROUND")
handle:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, HANDLE_RISE)
handle:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
handle:SetColorTexture(0.1, 0.8, 0.2, 0.8)
handle:Hide()
anchor:SetHitRectInsets(0, 0, -HANDLE_RISE, 0)

local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", handle, "TOP", 0, 4)
label:SetText("HealerMana: drag to move, /healermana to lock")
label:Hide()

local function ApplyPosition()
	local point = db.point
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[1], point[2], point[3])
end

anchor:SetScript("OnDragStart", function()
	anchor:StartMoving()
end)
anchor:SetScript("OnDragStop", function()
	anchor:StopMovingOrSizing()
	local point, _, _, x, y = anchor:GetPoint(1)
	db.point = { point, x, y }
end)

------------------------------------------------------------------------------
-- The rows
------------------------------------------------------------------------------

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- The Cooldown Manager's own icon dressing, as BuffNag and GroupDebuffs
-- wear it: its rounded mask on the picture and its border ring over it
-- (CooldownViewerBuffIconItemTemplate). A plain dark edge stands in on a
-- client without those atlases.
local function Dress(frame, picture)
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = frame:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
		mask:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
		picture:AddMaskTexture(mask)
		local ring = frame:CreateTexture(nil, "OVERLAY")
		ring:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		ring:SetPoint("TOPLEFT", -RING_REACH[1], RING_REACH[2])
		ring:SetPoint("BOTTOMRIGHT", RING_REACH[1], -RING_REACH[2])
	else
		local edge = frame:CreateTexture(nil, "BACKGROUND")
		edge:SetColorTexture(0, 0, 0, 0.9)
		edge:SetPoint("TOPLEFT", -1.5, 1.5)
		edge:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
	end
end

-- A glow around the border that fades in and out: the Cooldown Manager's
-- own alert flash (VisualAlertFlashBaseTemplate), or the old action button
-- glow on a client without that atlas. It is a region of the game's aura
-- button, so it is there exactly as long as the aura is; this file never
-- learns when.
local function Glow(button)
	local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
	if HasAtlas("UI-CooldownManager-VisualAlert-Glow") then
		glow:SetAtlas("UI-CooldownManager-VisualAlert-Glow")
		glow:SetPoint("TOPLEFT", -RING_REACH[1], RING_REACH[2])
		glow:SetPoint("BOTTOMRIGHT", RING_REACH[1], -RING_REACH[2])
	else
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetSize(ICON * 1.7, ICON * 1.7)
		glow:SetPoint("CENTER")
	end
	glow:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.25)
	fade:SetToAlpha(1)
	fade:SetDuration(0.5)
	fade:SetSmoothing("IN_OUT")
	pulse:Play()
end

-- Called by the container for every button it creates, before it locks the
-- button down. The regions must be children of the button.
local function InitButton(button, glows)
	button:SetSize(ICON, ICON)
	button:EnableMouse(false)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
	icon:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
	-- Dressed like the class icon it covers, before it is handed over.
	-- Should the game object to a mask on a button of its own, the icon
	-- stays square.
	pcall(Dress, button, icon)
	button:SetIcon(icon)

	if glows then
		pcall(Glow, button)
	end
end

local function InitGlowingButton(button)
	InitButton(button, true)
end

local function Set(ids)
	local set = {}
	for _, id in ipairs(ids) do
		set[id] = true
	end
	return set
end
local LAYERS = { -- bottom to top
	{ Set(SOULSTONE_SPELLS), InitButton },
	{ Set(INNERVATE_SPELLS), InitGlowingButton },
	{ Set(DRINK_SPELLS), InitGlowingButton, hidesAtFull = true },
}


-- Made as they are needed and kept: row i is the i-th healer of the list.
-- A row is a table of our own holding its regions, not a frame.
local rows = {}

local function Row(index)
	local row = rows[index]
	if row then
		return row
	end
	row = {}

	local frame = CreateFrame("Frame", nil, anchor)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(index - 1) * (HEIGHT + ROW_GAP))
	frame:Hide()
	row.frame = frame

	-- The class's picture: one cell of the game's sheet of class icons.
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetSize(ICON, ICON)
	holder:SetPoint("LEFT", 0, 0)
	local icon = holder:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
	icon:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
	icon:SetTexture(CLASS_ICONS)
	Dress(holder, icon)
	row.icon = icon
	row.holder = holder

	local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOPLEFT", holder, "TOPRIGHT", TEXT_GAP, 0)
	name:SetWidth(TEXT_WIDTH)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.name = name

	-- The percentage, or "Dead" / "Offline" in its place.
	local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	value:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", TEXT_GAP, 0)
	value:SetWidth(TEXT_WIDTH)
	value:SetJustifyH("LEFT")
	row.value = value

	-- Over the class icon and children of its holder, so they draw on top
	-- of it and show, hide and move with the row. Three layers, each with
	-- room for one button: Soulstone, over it Innervate, over that the drink.
	row.containers = {}
	-- The drink's layer sits in a frame of our own, whose alpha hides it at
	-- full mana.
	local drinkLayer = CreateFrame("Frame", nil, holder)
	drinkLayer:SetAllPoints()
	drinkLayer:SetFrameLevel(holder:GetFrameLevel() + #LAYERS)
	row.drinkLayer = drinkLayer
	for layer, spec in ipairs(LAYERS) do
		local container = CreateFrame("AuraContainer", nil, spec.hidesAtFull and drinkLayer or holder, "CustomAuraContainerTemplate")
		container:SetFrameLevel(holder:GetFrameLevel() + layer)
		container:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		container:SetFlowLayoutMaximumLineSize(ICON)
		container:AddAuraGroup("Status", "HELPFUL", {
			maxFrameCount = 1,
			initializeFrame = spec[2],
			candidateFilters = { includeSpellIDs = spec[1] },
			layout = {
				elementSpacing = 0,
				lineSpacing = 0,
				groupLineSpacing = 0,
				elementWidth = ICON,
				elementHeight = ICON,
			},
		})
		row.containers[layer] = container
	end

	rows[index] = row
	return row
end

-- A stand-in's drink: a picture and glow of our own where the game's
-- button would be. Made the first time a row needs it.
local function StandIn(row)
	if not row.standIn then
		local frame = CreateFrame("Frame", nil, row.holder)
		frame:SetAllPoints()
		frame:SetFrameLevel(row.holder:GetFrameLevel() + #LAYERS + 1)
		local picture = frame:CreateTexture(nil, "ARTWORK")
		picture:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
		picture:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
		local ok, texture = pcall(function()
			return C_Spell.GetSpellTexture(DRINK_ICON)
		end)
		picture:SetTexture(ok and texture or "Interface\\Icons\\INV_Drink_07")
		Dress(frame, picture)
		pcall(Glow, frame)
		row.standIn = frame
	end
	return row.standIn
end

-- unit token -> its row, for the rows that show.
local rowOf = {}

-- "Dead" or "Offline", or nil. Neither is documented as secret; should the
-- game refuse all the same, the healer counts as alive and here.
local function Status(unit)
	local status
	pcall(function()
		if UnitIsConnected(unit) == false then
			status = "Offline"
		elseif UnitIsDeadOrGhost(unit) == true then
			status = "Dead"
		end
	end)
	return status
end

-- Mana into the text. The value may be secret: it goes from the game's
-- function straight into a setter that takes it, and is never looked at
-- here.
local function UpdateMana(row)
	if row.fake then
		if not row.status then
			row.value:SetFormattedText("%.0f%%", row.fake.percent)
			pcall(function()
				row.value:SetTextColor(valueColorCurve:Evaluate(row.fake.percent / 100):GetRGB())
			end)
		end
		return
	end
	local unit = row.unit
	if drinkAlphaCurve then
		pcall(function()
			row.drinkLayer:SetAlpha(UnitPowerPercent(unit, MANA, false, drinkAlphaCurve))
		end)
	end
	if row.status then
		return
	end
	local ok = pcall(function()
		row.value:SetFormattedText("%.0f%%", UnitPowerPercent(unit, MANA, false, CurveConstants.ScaleTo100))
	end)
	if not ok then
		row.value:SetText("")
	end
	-- The colour is a table of the game's whose numbers may be secret: they
	-- go straight on into the setter.
	if valueColorCurve then
		pcall(function()
			row.value:SetTextColor(UnitPowerPercent(unit, MANA, false, valueColorCurve):GetRGB())
		end)
	end
end

local function UpdateStatus(row)
	if row.fake then
		row.status = row.fake.status
	else
		row.status = Status(row.unit)
	end
	row.frame:SetAlpha(row.status and OUT_ALPHA or 1)
	row.icon:SetDesaturated(row.status ~= nil)
	if row.status then
		row.value:SetText(row.status)
		row.value:SetTextColor(1, 1, 1)
	end
	UpdateMana(row)
end

------------------------------------------------------------------------------
-- Who the healers are
------------------------------------------------------------------------------

local healers = {} -- { unit, name, class } in the group's own order
local listed = false -- a list has been read at least once

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- What the game says about a unit: nil when there is nobody there, false
-- when it will not say (a secret value, or a comparison that fails on one,
-- which the pcall catches), or the member.
local function ReadMember(unit)
	local member
	local ok = pcall(function()
		if not UnitExists(unit) then
			return
		end
		local name = UnitName(unit)
		local _, class = UnitClass(unit)
		local role = UnitGroupRolesAssigned(unit)
		assert(not (IsSecret(name) or IsSecret(class) or IsSecret(role)))
		member = {
			unit = unit,
			name = name ~= nil and name ~= "" and name or unit,
			class = class,
			healer = role == "HEALER",
			hasRole = role == "HEALER" or role == "TANK" or role == "DAMAGER",
			canHeal = HEALING_CLASSES[class] == true,
		}
	end)
	if not ok then
		return false
	end
	return member
end

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			units[#units + 1] = "raid" .. i -- you are one of these
		end
	elseif IsInGroup() then
		units[1] = "player"
		for i = 1, 4 do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

-- The new list, or nil when the game kept something to itself.
local function ReadHealers()
	local members = {}
	local anyRole = false
	for _, unit in ipairs(GroupUnits()) do
		local member = ReadMember(unit)
		if member == false then
			return nil
		end
		if member then
			members[#members + 1] = member
			anyRole = anyRole or member.hasRole
		end
	end
	local list = {}
	local hasPlayer = false
	for _, member in ipairs(members) do
		if (anyRole and member.healer) or (not anyRole and member.canHeal) then
			list[#list + 1] = member
			local ok, isMe = pcall(UnitIsUnit, member.unit, "player")
			hasPlayer = hasPlayer or (ok and isMe == true)
		end
	end
	if testing and not hasPlayer then
		local me = ReadMember("player")
		if me == false then
			return nil
		end
		if me then
			table.insert(list, 1, me)
		end
	end
	if testing then
		for _, fake in ipairs(FAKES) do
			list[#list + 1] = { name = fake.name, class = fake.class, fake = fake }
		end
	end
	return list
end

local function ClassColor(class)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local function Refresh()
	if not db then
		return
	end
	local list = ReadHealers()
	if list then
		healers = list
		listed = true
	elseif not listed then
		healers = {}
	end
	rowOf = {}
	for index, healer in ipairs(healers) do
		local row = Row(index)
		row.unit = healer.unit -- nil for a stand-in
		row.fake = healer.fake
		if healer.unit then
			rowOf[healer.unit] = row
		end
		if row.standIn or (healer.fake and healer.fake.drinking) then
			StandIn(row):SetShown(healer.fake ~= nil and healer.fake.drinking == true)
		end
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[healer.class]
		if coords then
			row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		end
		row.name:SetText(healer.name)
		row.name:SetTextColor(ClassColor(healer.class))
		-- A new unit under the same token gets no refresh by itself.
		for _, container in ipairs(row.containers) do
			container:SetUnit(healer.unit or "none") -- "none": the unit that is nobody
			container:UpdateAllAuras()
		end
		UpdateStatus(row)
		row.frame:Show()
	end
	for index = #healers + 1, #rows do
		rows[index].unit = nil
		rows[index].fake = nil
		if rows[index].standIn then
			rows[index].standIn:Hide()
		end
		rows[index].frame:Hide()
	end
end

------------------------------------------------------------------------------
-- Events and the slash command
------------------------------------------------------------------------------

local function SetUnlocked(value)
	unlocked = value and true or false
	handle:SetShown(unlocked)
	label:SetShown(unlocked)
	anchor:EnableMouse(unlocked)
end

local function ResetPosition()
	db.point = { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
	ApplyPosition()
end

local UNIT_EVENTS = {
	UNIT_POWER_UPDATE = UpdateMana,
	UNIT_MAXPOWER = UpdateMana,
	UNIT_CONNECTION = UpdateStatus,
	UNIT_HEALTH = UpdateStatus, -- dying and coming back
	UNIT_FLAGS = UpdateStatus,
}

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
for event in pairs(UNIT_EVENTS) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, arg)
	local update = UNIT_EVENTS[event]
	if update then
		local row = rowOf[arg]
		if row then
			update(row)
		end
	elseif event == "ADDON_LOADED" then
		if arg ~= ADDON_NAME then
			return
		end
		HealerManaDB = HealerManaDB or {}
		db = HealerManaDB
		db.point = db.point or { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
		ApplyPosition()
	else
		-- Into the world, a change of group or roles, or the end of a fight.
		Refresh()
	end
end)

SLASH_HEALERMANA1 = "/healermana"
SlashCmdList.HEALERMANA = function(msg)
	local word = msg:lower():match("^%s*(%S*)")
	if word == "" then
		SetUnlocked(not unlocked)
	elseif word == "test" then
		testing = not testing
		Refresh()
		Print(testing and "test mode on: you and four stand-ins. /healermana test to leave" or "test mode off")
	elseif word == "reset" then
		ResetPosition()
	else
		Print("/healermana unlocks or locks; /healermana test; /healermana reset")
	end
end
