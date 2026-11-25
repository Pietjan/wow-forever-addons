-- BuffDrop: in combat, a pulsing grey icon the moment one of the buffs you
-- keep up on yourself (Battle Shout, a shaman's shield, a seal, Slice and
-- Dice, Inner Fire, an armor, Thorns, an aspect, ...) falls off.
--
-- How, within Forever's rules: in combat the game hides a buff's data from
-- addons, and C_UnitAuras returns nothing for a secret aura, so "no answer"
-- cannot tell "gone" from "hidden". The Lua here never asks. Instead each
-- buff gets one fixed cell with two layers:
--
--   below: our own grey (desaturated) copy of the spell's icon, at full
--          opacity; always drawn while the bar is shown.
--   above: a slot of the game's aura container (Blizzard_AuraContainer,
--          CustomAuraContainerTemplate, AddAuraSlot) on "player", limited to
--          that buff's spell IDs. Blizzard's secure code shows the slot's
--          button, with the lit icon and countdown, while the buff is up,
--          and hides it when the buff goes.
--
-- So while the buff is up you see it lit with its timer; when it falls off
-- the button disappears and the grey icon is what is left, much as
-- GroupDebuffs shows a missing debuff, in the Cooldown Manager's dressing.
-- Spell ID filters on helpful auras on the player are allowed by the
-- container (AuraContainerUtil.CanApplyIdentityCandidateFilters).
--
-- The bar is shown in combat only (BuffNag covers out of combat), and only
-- for the buffs whose spell you know. No mouse: clicks go through.
-- /buffdrop unlocks the bar to drag it, /buffdrop again locks it,
-- /buffdrop reset puts it back.

local ADDON_NAME = ...

-- Sizes as GroupDebuffs has them.
local ICON = 30
local SPACING = 3
local ICON_OUTSET = 0.5 -- the picture reaches this far under the border ring, so it fills the frame
local RING_REACH = { 6, 5 } -- the ring's reach past a 30 px icon, as the Cooldown Manager sizes it
local DEFAULT_POINT = { "CENTER", 0, -190 }
local SHORT_TIME = 30 -- seconds left from which the buff shows its countdown
local PULSE_LOW = 0.3 -- the missing icon's opacity at the dip of its pulse
local PULSE_TIME = 0.6 -- seconds from full to the dip, and again back

-- Trainable ranks from the game's SkillLineAbility table, talents from
-- TraitDefinition (build 1.60.1.71037); each buff on you has the spell ID
-- of the cast (SpellEffect: an aura on the caster). Any rank counts, from
-- you or from someone else. A slot holds one or more families of buffs
-- that exclude each other (a shaman's shields, a paladin's seals): it is
-- lit while any of them is up, and its grey icon is that of the family you
-- last cast, else the first one you know. A slot shows only for a class
-- that knows one of its spells, so the list is every class at once.
local BUFFS = {
	-- warrior
	{ key = "BattleShout", families = {
		{ 6673, 5242, 6192, 11549, 11550, 11551, 25289 },
	} },
	-- shaman
	{ key = "Shield", families = {
		{ 324, 325, 905, 945, 8134, 10431, 10432 }, -- Lightning Shield
		{ 408510 }, -- Water Shield
	} },
	-- paladin: 30 s, used up by Judgement
	{ key = "Seal", families = {
		{ 20154, 20287, 20288, 20289, 20290, 20291, 20293, 20292, 21084 }, -- Righteousness
		{ 20162, 20305, 20306, 20307, 20308, 21082 }, -- the Crusader
		{ 20166, 20356, 20357 }, -- Wisdom
		{ 20165, 20347, 20348, 20349 }, -- Light
		{ 20164 }, -- Justice
		{ 20375, 20915, 20918, 20919, 20920 }, -- Command (talent)
		{ 20163, 20419, 20421, 20422, 20423, 1311656, 1311649 }, -- Fury
		{ 407798, 407799 }, -- Martyrdom
	} },
	-- rogue
	{ key = "SliceAndDice", families = {
		{ 5171, 6774 },
	} },
	-- priest; Shadowguard and Touch of Weakness only for those who learn them
	{ key = "InnerFire", families = {
		{ 588, 7128, 602, 1006, 10951, 10952 },
	} },
	{ key = "Shadowguard", families = {
		{ 18137, 19308, 19309, 19310, 19311, 19312, 28377, 28378, 28379, 28380, 28381, 28382 },
	} },
	{ key = "TouchOfWeakness", families = {
		{ 2652, 2943, 19261, 19262, 19264, 19265, 19266, 19249, 19251, 19252, 19253, 19254 },
	} },
	-- mage
	{ key = "MageArmor", families = {
		{ 7302, 7320, 10219, 10220 }, -- Ice Armor
		{ 6117, 22782, 22783 }, -- Mage Armor
		{ 168, 7300, 7301 }, -- Frost Armor
	} },
	-- warlock
	{ key = "DemonArmor", families = {
		{ 706, 1086, 11733, 11734, 11735 }, -- Demon Armor
		{ 403619 }, -- Fel Armor
		{ 687, 696 }, -- Demon Skin
	} },
	-- druid; Omen of Clarity is not in Forever's talent tree, so it may
	-- never show
	{ key = "Thorns", families = {
		{ 467, 782, 1075, 8914, 9756, 9910 },
	} },
	{ key = "OmenOfClarity", families = {
		{ 16864 },
	} },
	-- hunter: an aspect only ends when you switch, or when a daze knocks
	-- off Cheetah or the Pack
	{ key = "Aspect", families = {
		{ 13165, 14318, 14319, 14320, 14321, 14322, 25296 }, -- the Hawk
		{ 13163 }, -- the Monkey
		{ 5118 }, -- the Cheetah
		{ 13159 }, -- the Pack
		{ 20043, 20190 }, -- the Wild
		{ 13161, 1299445, 1299446, 1299447 }, -- the Beast
		{ 415423 }, -- the Viper
		{ 469145 }, -- the Falcon
	} },
	{ key = "TrueshotAura", families = {
		{ 1299346, 1299348, 19506, 20905, 20906 }, -- talent
	} },
}

-- Every spell ID to its slot and family, and each slot's full list.
local familyOf = {}
for _, buff in ipairs(BUFFS) do
	buff.spells = {}
	for index, family in ipairs(buff.families) do
		for _, id in ipairs(family) do
			buff.spells[#buff.spells + 1] = id
			familyOf[id] = { buff = buff, index = index }
		end
	end
end

local IsSecret = issecretvalue or function() return false end

local db -- account: the position
local charDB -- this character: the family each slot last saw cast
local unlocked = false

------------------------------------------------------------------------------
-- The anchor and the cells
------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "BuffDropAnchor", UIParent)
anchor:SetSize(ICON, ICON)
anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3])
anchor:SetMovable(true)
if ForeverSnap then ForeverSnap.Register(anchor) end -- snaps to the screen and our other frames
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)
anchor:SetAlpha(0)

local handle = anchor:CreateTexture(nil, "BACKGROUND")
handle:SetPoint("TOPLEFT", -4, 4)
handle:SetPoint("BOTTOMRIGHT", 4, -4)
handle:SetColorTexture(0.1, 0.8, 0.2, 0.4)
handle:Hide()

local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
label:SetText("BuffDrop: drag to move, /buffdrop to lock")
label:Hide()

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- The Cooldown Manager's own icon dressing, as GroupDebuffs, CooldownNag
-- and BuffNag wear it: its rounded mask on the pictures and its border ring
-- over them. A plain dark edge stands in on a client without those atlases.
local function Dress(frame, ...)
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = frame:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
		mask:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
		for i = 1, select("#", ...) do
			select(i, ...):AddMaskTexture(mask)
		end
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

local function Picture(frame, layer)
	local texture = frame:CreateTexture(nil, layer)
	texture:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
	texture:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
	return texture
end

-- One cell per buff: the grey icon, below the container.
local function CreateCell(buff)
	local cell = CreateFrame("Frame", nil, anchor)
	cell:SetSize(ICON, ICON)
	cell:SetFrameLevel(anchor:GetFrameLevel() + 1)

	local grey = Picture(cell, "ARTWORK")
	grey:SetDesaturated(true)
	cell.icon = grey
	Dress(cell, grey)

	-- The grey icon pulses all the time; while the buff is up the lit
	-- button covers it, so only a missing buff is seen pulsing. The ring
	-- stays steady.
	local pulse = cell:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetTarget(grey)
	fade:SetFromAlpha(1)
	fade:SetToAlpha(PULSE_LOW)
	fade:SetDuration(PULSE_TIME)
	fade:SetSmoothing("IN_OUT")
	pulse:Play()

	cell.buff = buff
	cell:Hide()
	return cell
end

local cells = {}
for i, buff in ipairs(BUFFS) do
	cells[i] = CreateCell(buff)
end

local function KnowsAny(spells)
	for _, id in ipairs(spells) do
		if IsPlayerSpell(id) then
			return true
		end
	end
	return false
end

-- The family whose icon the slot greys out: the one last cast, if still
-- known, else the first one known.
local function IconFamily(buff)
	local last = charDB and charDB.last[buff.key]
	if last and buff.families[last] and KnowsAny(buff.families[last]) then
		return buff.families[last]
	end
	for _, family in ipairs(buff.families) do
		if KnowsAny(family) then
			return family
		end
	end
	return buff.families[1]
end

-- Lay the known buffs out in a column hanging down from the anchor: the
-- first one sits on it, so the top stays put whatever the class. The slot
-- buttons hang from their cells, so they follow. A class that knows none
-- of them gets the first cell while unlocked, so there is something to drag.
local function Layout()
	local shown = {}
	for _, cell in ipairs(cells) do
		if KnowsAny(cell.buff.spells) then
			shown[#shown + 1] = cell
		else
			cell:Hide()
		end
	end
	if unlocked and #shown == 0 then
		shown[1] = cells[1]
	end
	for i, cell in ipairs(shown) do
		local tex = C_Spell.GetSpellTexture(IconFamily(cell.buff)[1])
		cell.icon:SetTexture(tex)
		cell:ClearAllPoints()
		cell:SetPoint("CENTER", anchor, "CENTER", 0, -(i - 1) * (ICON + SPACING))
		cell:Show()
	end
end

------------------------------------------------------------------------------
-- The live buffs: one container slot per buff, above the cells
------------------------------------------------------------------------------

local container = CreateFrame("AuraContainer", "BuffDropContainer", anchor, "CustomAuraContainerTemplate")
container:SetAllPoints(anchor)
container:SetFrameLevel(anchor:GetFrameLevel() + 5)

-- Remaining seconds to text colour: a step curve, so the text is either
-- fully see-through or plain white.
local function ShortTimeCurve()
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	curve:AddPoint(0, CreateColor(1, 1, 1, 1))
	curve:AddPoint(SHORT_TIME, CreateColor(1, 1, 1, 0))
	return curve
end

-- AddAuraSlot creates and initialises its button at once, so this says
-- which cell the button being created belongs to.
local initCell

-- Called by the container for the slot's button, before it locks the
-- button down. The regions must be children of the button.
local function InitButton(button)
	button:SetSize(ICON, ICON)
	button:EnableMouse(false)
	button:ClearAllPoints()
	button:SetPoint("CENTER", initCell, "CENTER", 0, 0)
	button:Hide() -- until the container assigns the buff to it
	-- No scripts on this button: the game refuses to show or hide it with a
	-- secret ("Cannot be called with secrets due to existing script
	-- handlers"), seen in game 2026-11-21 with OnShow/OnHide hooks.

	local icon = Picture(button, "ARTWORK")
	-- Dressed before the icon is handed over. Should the game object to a
	-- mask on a button of its own, the icon stays square.
	pcall(Dress, button, icon)
	button:SetIcon(icon)

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", 3, -1)
	button:SetApplicationCount(count) -- stack count, from two up; not Lightning Shield's charges

	-- The time left, only once it is short. The game writes the text and
	-- colours it through a curve on the remaining seconds: see invisible
	-- above SHORT_TIME, white from there down. Nothing secret reaches us.
	local duration = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	duration:SetPoint("CENTER", 0, 0)
	if not pcall(button.SetDurationText, button, duration, { textColor = { curve = ShortTimeCurve(), property = Enum.DurationTextBindingProperty.RemainingDuration } }) then
		button:SetDurationText(duration) -- no curve: always show it rather than never
	end
end

container:SetUnit("player")
for _, cell in ipairs(cells) do
	local include = {}
	for _, id in ipairs(cell.buff.spells) do
		include[id] = true
	end
	initCell = cell
	container:AddAuraSlot(cell.buff.key, "HELPFUL", {
		initializeFrame = InitButton,
		candidateFilters = { includeSpellIDs = include },
	})
end
initCell = nil

------------------------------------------------------------------------------
-- Showing, moving, events
------------------------------------------------------------------------------

-- Alpha rather than Show/Hide: the container is the game's, and this
-- leaves its frames alone.
local function UpdateShown()
	anchor:SetAlpha((unlocked or InCombatLockdown()) and 1 or 0)
end

local function ApplyPosition()
	local point = db.point
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[1], point[2], point[3])
end

local function SetUnlocked(on)
	unlocked = on
	handle:SetShown(on)
	label:SetShown(on)
	anchor:EnableMouse(on)
	Layout()
	UpdateShown()
end

anchor:SetScript("OnDragStart", function()
	anchor:StartMoving()
end)
anchor:SetScript("OnDragStop", function()
	anchor:StopMovingOrSizing()
	local point, _, _, x, y = anchor:GetPoint(1)
	db.point = { point, x, y }
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Your own casts are not secret; only the spell ID is used, and only when
-- the game hands it over readable.
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, arg, _, spellID)
	if event == "ADDON_LOADED" then
		if arg == ADDON_NAME then
			BuffDropDB = BuffDropDB or {}
			db = BuffDropDB
			db.point = db.point or { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
			BuffDropCharDB = BuffDropCharDB or {}
			charDB = BuffDropCharDB
			charDB.last = charDB.last or {}
			ApplyPosition()
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local found = spellID and not IsSecret(spellID) and familyOf[spellID]
		if found and charDB.last[found.buff.key] ~= found.index then
			charDB.last[found.buff.key] = found.index
			Layout()
		end
	elseif event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then
		Layout()
		container:UpdateAllAuras()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- InCombatLockdown is still false while this event runs.
		anchor:SetAlpha(1)
	else
		UpdateShown()
	end
end)

SLASH_BUFFDROP1 = "/buffdrop"
SlashCmdList.BUFFDROP = function(msg)
	if msg:lower():match("^%s*reset") then
		db.point = { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
		ApplyPosition()
		return
	end
	SetUnlocked(not unlocked)
end
