-- GroupFrames party frames: our own, drawn after the agreed mock-up
-- (scratchpad/mockups/gframes.py), in place of Blizzard's.
--
-- The buttons come from a SecureGroupHeaderTemplate header: the game itself
-- decides who is shown, in which order, and lays them out in a row; each is
-- a secure unit button, so a click targets and a right-click opens the
-- unit menu, in combat too. The header resizes itself to the members it
-- shows and hangs by its centre from our anchor, so a party of four is
-- centred without any code of ours. It shows in a party, not in a raid
-- (Blizzard's raid frames stay for now), and solo it shows your own frame.
--
-- What a button shows, all on a plain child frame ("body") so its alpha can
-- fade without touching the secure button:
-- - a 92 x 15 bar in Forever's nameplate art (UI-HUD-CoolDownManager-Bar
--   in its -BG edge, placed as Blizzard_NamePlates places it), class
--   coloured; health is secret in Forever, and a status bar takes secret
--   values for min, max and value, so the numbers are handed on unread;
-- - the role icon centred on the edge's top-left corner, the first name (5
--   letters) along the top edge, dispel-type icons at its right end;
-- - dots at the bar's bottom right for your Renew and anyone's Power Word:
--   Shield, and at the bottom left for a Weakened Soul you applied (Look of
--   the auras: the game's own aura containers, see Auras below);
-- - "Dead" or "Offline" on the bar; a gold edge on your target;
-- - out of range: faded. UnitInRange is secret; SetAlphaFromBoolean takes it.
--
-- Blizzard's party frames are hidden by moving PartyFrame under a hidden
-- frame at login (there is no game setting to hide them). Edit Mode can
-- then no longer select the party frames.

local _, ns = ...

local IsSecret = issecretvalue or function() return false end

local BAR_W, BAR_H = 100, 16 -- 92 x 10, 12, 14 before; the user asked a bit higher and wider
-- The bar is built as Blizzard_NamePlates builds Forever's nameplate bar
-- (the user asked for it "like the nameplate", 2026-11-22): the bar
-- background art (UI-HUD-CoolDownManager-Bar-BG) behind the bar, the fill
-- (UI-HUD-CoolDownManager-Bar) on top of it, nothing over the fill but the
-- nameplate's own inner shadow. The art is at the nameplate's size (1x) and
-- placed as the nameplate places it (2 left, 3 above, 6 right), except 7
-- below instead of 6: at 6 the bottom bronze line fell half under the bar
-- and read dim grey (measured in a true-scale render: 71,56,43 against the
-- nameplate's 149,123,53). The bar is 14 high (10, then 12; the user asked for 14): at this
-- size the user preferred it over the 2x art (2026-11-22).
--
-- The art (c60-2x: atlas file 8165540, 512 x 256, at x 175-439, y 1-39) is
-- cut in nine by texture coordinates (SetTextureSliceMargins' units did not
-- behave as expected in game) at 20 left, 14 top, 20 right, 22 bottom
-- pixels, drawn at half that. The nameplate's own slices put 121 units on
-- the left, made for its 166-wide bar.
local EDGE_FILE, EDGE_FILE_W, EDGE_FILE_H = 8165540, 512, 256
local EDGE_X0, EDGE_X1, EDGE_Y0, EDGE_Y1 = 175, 439, 1, 39
local EDGE_SCALE = 1 -- UI units per 2 pixels of the 2x art
local CUT_L, CUT_T, CUT_R, CUT_B = 20, 14, 20, 22
-- Top 4 instead of the nameplate's 3, as the bottom: the bronze lines clear
-- the fill and its inner shadow by a pixel (user, 2026-11-22).
local EDGE_L, EDGE_T, EDGE_R, EDGE_B = 2, 4, 6, 7
-- The name line runs along the bronze top line (its middle 4 px of the 2x
-- art below the art's top), the role icon sits where it meets the left one
-- (3 px in).
local LINE_Y = EDGE_T - 2
local LINE_X = -EDGE_L + 1.5
local NAME_ABOVE = math.ceil(LINE_Y + 6) -- whole units: the secure setup string takes integers
local BUTTON_W = EDGE_L + BAR_W + EDGE_R
local BUTTON_H = NAME_ABOVE + BAR_H + EDGE_B
local GAP = 6 -- 10 before; the user asked a bit smaller
local ROLE_SIZE = 17 -- 12, then 15; the user asked for it bigger again
local NAME_X = ROLE_SIZE / 2 + 1.5 -- the name starts just right of the icon
local FADED = 0.45

-- The settings on the options page (Options.lua), with what they start as.
local DEFAULTS = {
	soloFrame = true, -- your own frame (and pet) when not in a group
	partyPets = true,
	aggro = true,
	rangeFade = true,
	fadedAlpha = FADED, -- how faded an out-of-range member is
	partyLayout = "rowCentre",
}
local DOT, DOT_GAP = 5, 2
local WEAKENED_SOUL_SECONDS = 15
local FORBEARANCE_SECONDS = 60 -- SpellMisc/SpellDuration for 25771, 1.60.1.71037
local DOT_X, DOT_Y = 3, 3 -- in from the bar's side and up from its bottom (user: 3 and 3)
local DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

-- When each type's icon shows (the dispelShow setting, per type): the
-- filter its aura group takes, or no filter for never (the group is
-- switched off). The game's three dispellable filters: DISPELLABLE (it
-- can be removed at all), RAID_PLAYER_DISPELLABLE (someone in your group
-- can), RAID (you can). All "mine" at first, bleeds too (user,
-- 2026-11-23).
local DISPEL_SHOW = {
	{ key = "always", label = "Always", filter = "HARMFUL" },
	{ key = "any", label = "Dispellable", filter = "HARMFUL|DISPELLABLE" },
	{ key = "group", label = "Dispellable by my group", filter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
	{ key = "mine", label = "Dispellable by me", filter = "HARMFUL|RAID" },
	{ key = "never", label = "Never" },
}
local DISPEL_SHOW_DEFAULT = "mine"
local dispelShowByKey = {}
for _, choice in ipairs(DISPEL_SHOW) do
	dispelShowByKey[choice.key] = choice
end

local DISPEL_ICON = 15 -- 10, then 13; the user asked them bigger again
-- The big defensive in the middle of the bar, sticking out of the frame,
-- dressed as the other addons here dress icons (GroupDebuffs, BuffDrop):
-- the Cooldown Manager's rounded mask and its soft ring, the ring's reach
-- scaled from 6 x 5 at 30. The action button's bronze icon frame was tried
-- and was too much (user, 2026-11-22).
-- The status icon in the middle of the bar, on top of everything (user:
-- "smack em in the center"): Blizzard's centre status art and its raid
-- ready-check marks.
local STATUS_ICON = 20
local READY_CHECK_HOLD = 6 -- seconds the result stays after a ready check, as Blizzard's CUF_READY_CHECK_DECAY_TIME
local STATUS_ATLAS = {
	summonPending = "RaidFrame-Icon-SummonPending",
	summonAccepted = "RaidFrame-Icon-SummonAccepted",
	summonDeclined = "RaidFrame-Icon-SummonDeclined",
	rez = "RaidFrame-Icon-Rez",
	phase = "RaidFrame-Icon-Phasing",
	otherParty = "RaidFrame-Icon-LFR",
	ready = "UI-LFG-ReadyMark-Raid",
	notready = "UI-LFG-DeclineMark-Raid",
	waiting = "UI-LFG-PendingMark-Raid",
}
local BIG_ICON = 28 -- 18, 24, 32, 38, 34 before; 28 with the glow (user)
local ICON_OUTSET = 0.5
local RING_REACH = { 6 * BIG_ICON / 30, 5 * BIG_ICON / 30 }
-- A slight glow round it: perks-list-iconglow, a soft warm glow round a
-- rounded square, one texture centred on the icon at the size it had in
-- the options render the user picked (2026-11-22): 52 for a 40 icon. Tried
-- before: a soft white icon glow (too spread), the nameplate's selection
-- glow cut round the icon (a 1 px gap or overlap on one side however placed).
local GLOW_SIZE = BIG_ICON * 52 / 40
local DEFAULT_POINT = { "CENTER", 0, -180 }
local PET_SCALE = 0.75 -- the pet row: the same frames, smaller
local PET_GAP = 4 -- between the party row and the pet row
local PET_COLOUR = { 0.3, 0.75, 0.3 } -- pets have no class colour of their own

-- The LFG micro icons, gold ring (21 px art). Forever's bronze
-- groupfinder-icon-role-large set was tried 2026-11-22: copper-red next to
-- the edge, its cross squashed. Ask -c60 atlases by their plain name: the
-- "-c60" names showed nothing in game.
local ROLE_ATLAS = {
	TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
	HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
	DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
}

-- Every rank, from the client tables (SpellName, SkillLineAbility; build
-- 1.60.1.71037 names): all "Renew" and all "Power Word: Shield".
local RENEW = { 139, 890, 6074, 6075, 6076, 6077, 6078, 8362, 10927, 10928, 10929, 11640, 22168, 23895, 25058, 25315,
	27606, 28807, 425268, 425269, 425270, 425271, 425272, 425273, 425274, 425275, 425276, 425277, 438341, 450658,
	1232734, 1236151, 1289450 }
local SHIELD = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 11647, 11835, 11974, 17139, 20697, 22187,
	27607, 437930, 1226566, 1236154 }

local OVER_ABSORB_ALPHA = 0.5 -- the over-shield glow at half strength (user: a bit too much)

local COLOURS = {
	-- Incoming heals, as two segments after the health fill.
	healMine = { 0.35, 1, 0.45, 0.6 },
	healOthers = { 0.2, 0.7, 0.3, 0.5 },
	absorb = { 0.55, 0.58, 1, 0.8 }, -- shields, after the heals: Blizzard's lavender blue (pale grey before, user)
	renew = { 0.25, 0.88, 0.35 },
	shield = { 1, 0.83, 0.29 },
	weakened = { 0.88, 0.16, 0.16 },
	forbearance = { 0.68, 0.3, 0.95 }, -- purple (user, 2026-11-23)
	gone = { 0.35, 0.35, 0.35 },
}

local db
local buttons = {} -- every button the header made

local function DispelShow(dispelType)
	local key = db and db.dispelShow and db.dispelShow[dispelType]
	return dispelShowByKey[key] or dispelShowByKey[DISPEL_SHOW_DEFAULT]
end
local byUnit = {} -- unit token -> button

------------------------------------------------------------------------------
-- Auras: the game's aura containers (CustomAuraContainerTemplate). The game
-- reads, filters, lays out and shows them; this file never sees aura data.
-- Weakened Soul cannot be picked by spell ID on a friend (the container
-- refuses it unless C_Secrets.GetSpellAuraSecrecy is 0; 6788 gives 2), so
-- it is "a debuff you applied"; another priest's does not show.
------------------------------------------------------------------------------

local function Set(list)
	local set = {}
	for _, id in ipairs(list) do
		set[id] = true
	end
	return set
end

local function Dot(colour)
	return function(button)
		button:SetSize(DOT, DOT)
		button:EnableMouse(false)
		local rim = button:CreateTexture(nil, "BACKGROUND")
		rim:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		rim:SetPoint("TOPLEFT", -1, 1)
		rim:SetPoint("BOTTOMRIGHT", 1, -1)
		rim:SetVertexColor(0, 0, 0, 1)
		local dot = button:CreateTexture(nil, "ARTWORK")
		dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		dot:SetAllPoints()
		dot:SetVertexColor(colour[1], colour[2], colour[3], 1)
	end
end

local function DispelIcon(button)
	button:SetSize(DISPEL_ICON, DISPEL_ICON)
	button:EnableMouse(false)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button:AddDispelTypeTexture(icon, {
		style = Enum.CustomAuraButtonDispelTypeTextureStyle.Icon,
		showWhenHarmful = true,
		showWhenHelpful = false,
		showWithoutDispelType = false,
	})
end

local function DotLayout()
	return { elementSpacing = DOT_GAP, elementWidth = DOT, elementHeight = DOT }
end

local function Container(parent, level)
	local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	container:SetFrameLevel(level)
	return container
end

-- Which spells the game counts as big defensives: asked once, of every
-- class spell, talent and what they trigger (BigDefensiveData.lua). No
-- client table says; C_UnitAuras.AuraIsBigDefensive does.
local bigDefensives, bigDefensiveCount

local function BigDefensives()
	if bigDefensives then
		return bigDefensives, bigDefensiveCount
	end
	bigDefensives, bigDefensiveCount = {}, 0
	local ask = C_UnitAuras and C_UnitAuras.AuraIsBigDefensive
	if ask then
		for _, id in ipairs(ns.BIG_DEFENSIVE_CANDIDATES or {}) do
			local ok, isBig = pcall(ask, id)
			if ok and isBig == true then
				bigDefensives[id] = true
				bigDefensiveCount = bigDefensiveCount + 1
			end
		end
	end
	return bigDefensives, bigDefensiveCount
end

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- The Cooldown Manager's icon dressing: rounded mask on the picture, its
-- soft ring over it; a plain dark edge without those atlases.
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
		edge:SetPoint("TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", 1, -1)
	end
end

local function Glow(frame)
	if not HasAtlas("perks-list-iconglow") then
		return
	end
	local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	glow:SetAtlas("perks-list-iconglow")
	glow:SetSize(GLOW_SIZE, GLOW_SIZE)
	glow:SetPoint("CENTER", frame, "CENTER")
	return glow
end

local function Picture(frame)
	local texture = frame:CreateTexture(nil, "ARTWORK")
	texture:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
	texture:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
	return texture
end

local function BigDefensiveIcon(button)
	button:SetSize(BIG_ICON, BIG_ICON)
	button:EnableMouse(false)
	local icon = Picture(button)
	pcall(Dress, button, icon) -- should the game refuse a mask here, the icon stays square
	pcall(Glow, button)
	button:SetIcon(icon)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:Show()
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	cooldown:EnableMouse(false)
	pcall(cooldown.SetSwipeTexture, cooldown, "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.6)
	button:SetDurationCooldown(cooldown)
end

local function CreateAuras(btn)
	local level = btn.top:GetFrameLevel() + 1
	local auras = {}

	auras.dispel = Container(btn.body, level)
	-- On the right end of the name line, growing leftward (user, 2026-11-22).
	auras.dispel:SetFlowLayoutAnchorPoint("RIGHT")
	auras.dispel:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
	-- One icon per dispel type, however many debuffs of it (user: three
	-- magic icons said nothing more than one): a group per type, one frame
	-- each. Dispel types may be filtered on friends; only spell IDs may not.
	-- Each type's filter as its setting says (DispelShow); a type set to
	-- never gets a group too, switched off, so the setting can turn it on.
	for _, dispelType in ipairs(DISPEL_TYPES) do
		local show = DispelShow(dispelType)
		auras.dispel:AddAuraGroup("Dispel" .. dispelType, show.filter or "HARMFUL", {
			maxFrameCount = 1,
			initializeFrame = DispelIcon,
			candidateFilters = { includeDispelTypes = { [dispelType] = true } },
			layout = { elementSpacing = 1, elementWidth = DISPEL_ICON, elementHeight = DISPEL_ICON },
		})
	end
	auras.dispel:SetPoint("RIGHT", btn.bar, "TOPRIGHT", -4, LINE_Y)
	for _, dispelType in ipairs(DISPEL_TYPES) do
		if not DispelShow(dispelType).filter then
			auras.dispel:SetAuraGroupEnabled("Dispel" .. dispelType, false)
		end
	end

	auras.dots = Container(btn.body, level)
	auras.dots:SetFlowLayoutAnchorPoint("BOTTOMRIGHT")
	auras.dots:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Up)
	auras.dots:AddAuraGroup("Shield", "HELPFUL", {
		maxFrameCount = 1,
		initializeFrame = Dot(COLOURS.shield),
		candidateFilters = { includeSpellIDs = Set(SHIELD) },
		layout = DotLayout(),
	})
	auras.dots:AddAuraGroup("Renew", "HELPFUL|PLAYER", {
		maxFrameCount = 1,
		initializeFrame = Dot(COLOURS.renew),
		candidateFilters = { includeSpellIDs = Set(RENEW) },
		layout = DotLayout(),
	})
	auras.dots:SetPoint("BOTTOMRIGHT", btn.bar, "BOTTOMRIGHT", -DOT_X, DOT_Y)

	-- The bottom-left dot is your class's: a priest's red Weakened Soul, a
	-- paladin's purple Forbearance, none for the rest. Both are found as "a
	-- short debuff you applied", which on other classes catches other
	-- things: a hunter's own Dazed from Aspect of the Cheetah or the Pack
	-- (15571, 4 s) lit it (user, 2026-11-23). PLAYER is you, your pet or
	-- vehicle (warcraft.wiki.gg, C_UnitAuras.GetAuraDataByIndex).
	local _, class = UnitClass("player")
	auras.weakened = Container(btn.body, level)
	auras.weakened:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
	auras.weakened:SetPoint("BOTTOMLEFT", btn.bar, "BOTTOMLEFT", DOT_X, DOT_Y)
	if class == "PALADIN" then
		-- Your Forbearance: a debuff you applied lasting at most 60 s. Other
		-- paladins' are not read (spell IDs are refused on friends).
		auras.weakened:AddAuraGroup("Forbearance", "HARMFUL|PLAYER", {
			maxFrameCount = 1,
			initializeFrame = Dot(COLOURS.forbearance),
			candidateFilters = { maxDuration = FORBEARANCE_SECONDS },
			layout = DotLayout(),
		})
	end
	if class == "PRIEST" then
		-- Your Weakened Soul: a debuff you applied lasting at most 15 s, its
		-- duration in this build (SpellMisc/SpellDuration, 1.60.1.71037). The
		-- limit keeps your own long debuffs off it: Ghost (permanent; the
		-- container's maxDuration drops permanent auras) lit it while you were
		-- dead (user, 2026-11-22), Recently Bandaged lasts 60 s.
		auras.weakened:AddAuraGroup("WeakenedSoul", "HARMFUL|PLAYER", {
			maxFrameCount = 1,
			initializeFrame = Dot(COLOURS.weakened),
			candidateFilters = { maxDuration = WEAKENED_SOUL_SECONDS },
			layout = DotLayout(),
		})
		-- Another priest's: not readable on a friend (see above), so their
		-- shield stands in for it (user's choice): a Power Word: Shield not cast
		-- by you means their Weakened Soul is almost surely up. Not exact: it
		-- lasts 15 s, the shield up to 30 s or until broken. Both cannot show at
		-- once: your Weakened Soul blocks their shield.
		-- "Not cast by you" is the filter string's negation, "!PLAYER" (the
		-- opposite of the Renew dot's "PLAYER"). The candidate filter
		-- isFromPlayerOrPlayerPet = false was tried first and showed nothing for
		-- another priest's shield (user, 2026-11-22): it means applied by any
		-- player (warcraft.wiki.gg), which every priest's shield is.
		auras.weakened:AddAuraGroup("OthersShield", "HELPFUL|!PLAYER", {
			maxFrameCount = 1,
			initializeFrame = Dot(COLOURS.weakened),
			candidateFilters = { includeSpellIDs = Set(SHIELD) },
			layout = DotLayout(),
		})
	end

	-- The big defensive: one icon in the middle of the bar, on top of
	-- everything (the user's wish for the centre icon), Blizzard's own pick
	-- when there are several.
	auras.big = Container(btn.body, btn.top:GetFrameLevel() + 2)
	auras.big:AddAuraGroup("BigDefensive", "HELPFUL", {
		maxFrameCount = 1,
		initializeFrame = BigDefensiveIcon,
		candidateFilters = { includeSpellIDs = (BigDefensives()) },
		sortMethod = AuraContainerSortMethod.BigDefensive,
		sortDirection = AuraContainerSortDirection.Normal,
		layout = { elementWidth = BIG_ICON, elementHeight = BIG_ICON },
	})
	auras.big:SetPoint("CENTER", btn.bar, "CENTER", 0, 0)

	btn.auras = auras
end

------------------------------------------------------------------------------
-- A button's looks
------------------------------------------------------------------------------

local function Outlined(fontString, size)
	fontString:SetFontObject("GameFontHighlightSmall")
	local font = fontString:GetFont()
	if font then
		fontString:SetFont(font, size, "OUTLINE")
	end
end

-- The edge art in nine pieces around a bar, on a frame's BACKGROUND layer.
-- Corners keep their size; sides and middle stretch.
-- A piece of the 2x art in file 8165540, given as its pixel rect (x0-x1,
-- y0-y1) and its nine-slice cuts, drawn at EDGE_SCALE around the bar at the
-- given offsets (left, top, right, bottom, outward).
local EDGE_SPEC = { x0 = EDGE_X0, x1 = EDGE_X1, y0 = EDGE_Y0, y1 = EDGE_Y1,
	cut = { CUT_L, CUT_T, CUT_R, CUT_B }, off = { EDGE_L, EDGE_T, EDGE_R, EDGE_B } }
-- Gold like the role icon's ring (user, 2026-11-22): the art's pale bronze
-- tinted to the ring's median (188, 140, 55), and a second copy added on top
-- (ADD) in the same gold at half strength for the shine the ring has; picked
-- side by side. The middle, the bar's dark background, is left alone.
local EDGE_TINT = { 1, 0.88, 0.43 }
local EDGE_SHINE = 0.5
-- The band behind the name: tall enough to cover the edge's top line, dark
-- enough to hide it, fading out over the name's last PLATE_FADE at each end.
local PLATE_H, PLATE_ALPHA, PLATE_FADE = 6, 0.8, 2

local function NineSlice(frame, bar, withMiddle, spec, layer)
	local cutL, cutT, cutR, cutB = unpack(spec.cut)
	local offL, offT, offR, offB = unpack(spec.off)
	local cutX = { spec.x0, spec.x0 + cutL, spec.x1 - cutR, spec.x1 }
	local cutY = { spec.y0, spec.y0 + cutT, spec.y1 - cutB, spec.y1 }
	local pieces = {}
	local function Piece(key, col, row)
		local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
		tex:SetTexture(EDGE_FILE)
		tex:SetTexCoord(cutX[col] / EDGE_FILE_W, cutX[col + 1] / EDGE_FILE_W, cutY[row] / EDGE_FILE_H, cutY[row + 1] / EDGE_FILE_H)
		pieces[key] = tex
		return tex
	end
	local k = EDGE_SCALE / 2 -- 2x art pixels to UI units
	local w = { cutL * k, nil, cutR * k }
	local h = { cutT * k, nil, cutB * k }
	local tl, tr = Piece("tl", 1, 1), Piece("tr", 3, 1)
	local bl, br = Piece("bl", 1, 3), Piece("br", 3, 3)
	tl:SetSize(w[1], h[1]); tl:SetPoint("TOPLEFT", bar, "TOPLEFT", -offL, offT)
	tr:SetSize(w[3], h[1]); tr:SetPoint("TOPRIGHT", bar, "TOPRIGHT", offR, offT)
	bl:SetSize(w[1], h[3]); bl:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -offL, -offB)
	br:SetSize(w[3], h[3]); br:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", offR, -offB)
	local t = Piece("t", 2, 1); t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	local b = Piece("b", 2, 3); b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	local l = Piece("l", 1, 2); l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	local r = Piece("r", 3, 2); r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	if withMiddle then
		local m = Piece("m", 2, 2); m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
	end
	return pieces
end

-- Your target: the yellow glow Forever draws round its target's nameplate
-- (Camelot Blizzard_NamePlateConstants: UI-HUD-CoolDownManager-Selected-
-- yellow, untinted, placed on the bar background 3 further left, 2 higher,
-- its bottom 2 up). The 2x art is at x 175-439, y 41-73 of the same file;
-- its angled corners reach 12 px in and 11 px down (measured).
local TARGET_SPEC = { x0 = 175, x1 = 439, y0 = 41, y1 = 73, cut = { 12, 11, 12, 11 },
	off = { EDGE_L + 3, EDGE_T + 2, EDGE_R, EDGE_B - 2 } }
-- Toned down from the nameplate's untinted yellow (user: "a bit yellowy"):
-- a warmer, paler tint at 80%.
local TARGET_TINT = { 1, 0.88, 0.68, 0.8 }

-- Everything a frame shows, on a frame of any kind: the header's secure
-- buttons and the test mode's look-only frames alike.
local function BuildLook(btn)
	local body = CreateFrame("Frame", nil, btn)
	body:SetAllPoints()
	btn.body = body
	local level = body:GetFrameLevel()

	local back = CreateFrame("Frame", nil, body)
	back:SetFrameLevel(level)
	back:SetAllPoints()

	local bar = CreateFrame("StatusBar", nil, body)
	bar:SetFrameLevel(level + 1)
	bar:SetSize(BAR_W, BAR_H)
	bar:SetPoint("TOPLEFT", body, "TOPLEFT", EDGE_L, -NAME_ABOVE)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetAtlas("UI-HUD-CoolDownManager-Bar")
	bar:SetStatusBarTexture(fill)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	btn.bar = bar

	-- The nameplate's slight inner shadow: its deselectedOverlay, at full
	-- strength, 1 over the bar's top and bottom (Blizzard_NamePlates.xml).
	-- Like the nameplate, gone on your target, which gets its edge instead.
	local shadow = bar:CreateTexture(nil, "OVERLAY")
	shadow:SetAtlas("ui-hud-nameplates-deselected-overlay")
	shadow:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 1)
	shadow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -1)
	btn.shadow = shadow

	-- Incoming heals: two bars stacked after the health fill, each hung
	-- from the right edge of the fill before it, as wide as the whole bar,
	-- with health's max. Their values come from the game's heal
	-- prediction calculator, secret and already clamped to the missing
	-- health; nothing is added or compared here.
	local function HealBar(after, colour)
		local heal = CreateFrame("StatusBar", nil, bar)
		heal:SetPoint("TOPLEFT", after, "TOPRIGHT")
		heal:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
		heal:SetWidth(BAR_W)
		local tex = heal:CreateTexture(nil, "ARTWORK")
		tex:SetAtlas("UI-HUD-CoolDownManager-Bar")
		heal:SetStatusBarTexture(tex)
		heal:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4])
		heal:SetMinMaxValues(0, 1)
		heal:SetValue(0)
		return heal
	end
	btn.healMine = HealBar(fill, COLOURS.healMine)
	btn.healOthers = HealBar(btn.healMine:GetStatusBarTexture(), COLOURS.healOthers)
	-- Shields (damage absorbs) after the heals, clamped by the calculator to
	-- the room the heals leave. Shield that does not fit shows as Blizzard
	-- shows it: its over-shield glow at the bar's end (CompactUnitFrame's
	-- overAbsorbGlow: RaidFrame-Shield-Overshield, 7 in, 16 wide, additive).
	btn.absorb = HealBar(btn.healOthers:GetStatusBarTexture(), COLOURS.absorb)
	local over = bar:CreateTexture(nil, "OVERLAY", nil, 1)
	over:SetAtlas("RaidFrame-Shield-Overshield")
	over:SetBlendMode("ADD")
	over:SetPoint("TOPLEFT", bar, "TOPRIGHT", -5, 0)
	over:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", -5, 0)
	over:SetWidth(10) -- Blizzard's 16 at full strength was too much (user)
	over:SetAlpha(0)
	btn.overAbsorb = over

	-- The status icon: one texture in the middle, above everything.
	local statusFrame = CreateFrame("Frame", nil, body)
	statusFrame:SetFrameLevel(level + 8)
	statusFrame:SetAllPoints()
	local statusIcon = statusFrame:CreateTexture(nil, "OVERLAY")
	statusIcon:SetSize(STATUS_ICON, STATUS_ICON)
	statusIcon:SetPoint("CENTER", bar, "CENTER")
	statusIcon:Hide()
	btn.statusIcon = statusIcon

	btn.edge = NineSlice(back, bar, true, EDGE_SPEC)
	btn.edgeShine = NineSlice(back, bar, false, EDGE_SPEC, "BORDER")
	for key, piece in pairs(btn.edge) do
		if key ~= "m" then
			piece:SetVertexColor(unpack(EDGE_TINT))
		end
	end
	for _, piece in pairs(btn.edgeShine) do
		piece:SetBlendMode("ADD")
		piece:SetVertexColor(EDGE_TINT[1], EDGE_TINT[2], EDGE_TINT[3], EDGE_SHINE)
	end

	local top = CreateFrame("Frame", nil, body)
	top:SetFrameLevel(level + 4)
	top:SetAllPoints()
	btn.top = top

	-- On a frame of its own, so one alpha shows or hides all nine pieces;
	-- above the fill but under the name line (it covered the name and role
	-- icon on the top frame, 2026-11-22).
	local target = CreateFrame("Frame", nil, body)
	target:SetFrameLevel(level + 2)
	target:SetAllPoints()
	btn.targetGlow = NineSlice(target, bar, false, TARGET_SPEC, "OVERLAY")
	for _, piece in pairs(btn.targetGlow) do
		piece:SetVertexColor(unpack(TARGET_TINT))
	end
	target:SetAlpha(0)
	btn.target = target

	-- Aggro: the same glow art round the edge, in the threat colour, over
	-- the target glow (aggro wins when both apply), under the name line.
	local aggro = CreateFrame("Frame", nil, body)
	aggro:SetFrameLevel(level + 3)
	aggro:SetAllPoints()
	btn.aggroGlow = NineSlice(aggro, bar, false, TARGET_SPEC, "OVERLAY")
	aggro:SetAlpha(0)
	btn.aggro = aggro

	local role = top:CreateTexture(nil, "ARTWORK")
	role:SetSize(ROLE_SIZE, ROLE_SIZE)
	-- On the ring's top-left corner, where its bronze lines meet.
	-- 1.5 below the name line and 1.5 further in (user, 2026-11-22; half
	-- units work as the icon is not snapped to the pixel grid).
	role:SetPoint("CENTER", bar, "TOPLEFT", LINE_X + 1.5, LINE_Y - 1.5)
	-- Not snapped to the pixel grid: snapping rounds each side on its own,
	-- which can squash a small icon by a pixel one way (a guess for the
	-- squashed cross seen 2026-11-22, not confirmed).
	if role.SetSnapToPixelGrid then
		role:SetSnapToPixelGrid(false)
		role:SetTexelSnappingBias(0)
	end
	btn.role = role

	local name = top:CreateFontString(nil, "ARTWORK")
	-- A font family, not a font file: Friz 12 outlined, with Blizzard's
	-- fonts for Korean, Chinese and Cyrillic names. SetFont with Friz's file
	-- dropped those and drew such a name as empty boxes (raid, 2026-11-22).
	name:SetFontObject(SystemFont_Shadow_Med1_Outline or "GameFontHighlightSmall")
	-- Half a unit below the line (user, 2026-11-22).
	name:SetPoint("LEFT", bar, "TOPLEFT", LINE_X + NAME_X, LINE_Y - 0.5)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	btn.name = name

	-- A dark band behind the name, so the edge's top line does not show
	-- through the letters (inside a D, user 2026-11-22). Anchored to the
	-- name's own ends, so it follows the text without reading its width
	-- (secret names cannot be measured); its ends fade out.
	local function Plate()
		local tex = top:CreateTexture(nil, "BACKGROUND")
		tex:SetColorTexture(1, 1, 1, 1)
		tex:SetHeight(PLATE_H)
		return tex
	end
	local mid, left, right = Plate(), Plate(), Plate()
	-- The fades fall inside the name's ends, not past them (it poked out,
	-- user 2026-11-22).
	mid:SetPoint("LEFT", name, "LEFT", PLATE_FADE, 0)
	-- The text box runs past the last letter: the right end 2 further in.
	mid:SetPoint("RIGHT", name, "RIGHT", -PLATE_FADE - 2, 0)
	mid:SetVertexColor(0, 0, 0, PLATE_ALPHA)
	left:SetPoint("RIGHT", mid, "LEFT")
	left:SetWidth(PLATE_FADE)
	right:SetPoint("LEFT", mid, "RIGHT")
	right:SetWidth(PLATE_FADE)
	if CreateColor and left.SetGradient then
		local clear, dark = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, PLATE_ALPHA)
		left:SetGradient("HORIZONTAL", clear, dark)
		right:SetGradient("HORIZONTAL", dark, clear)
	else
		left:SetVertexColor(0, 0, 0, PLATE_ALPHA / 2)
		right:SetVertexColor(0, 0, 0, PLATE_ALPHA / 2)
	end
	btn.namePlate = { mid = mid, left = left, right = right }

	local status = top:CreateFontString(nil, "ARTWORK")
	Outlined(status, 9)
	status:SetPoint("CENTER", bar, "CENTER", 0, 0)
	status:SetTextColor(0.8, 0.8, 0.8)
	btn.status = status

end

-- Called by the template as the header creates each button.
function GroupFrames_InitButton(btn)
	BuildLook(btn)
	CreateAuras(btn)

	-- Clicks are registered by the template's registerForClicks, not here:
	-- the header can create a button in combat (an invite mid-fight), and
	-- RegisterForClicks from this OnLoad is then blocked (BugGrabber,
	-- 2026-11-22).

	-- The unit's tooltip, as Blizzard's unit frames show it
	-- (UnitFrame_OnEnter/OnLeave: default anchor, SetUnit, the right-click
	-- line); a plain SetUnit where those are missing.
	btn:HookScript("OnEnter", function(self)
		if not self.unit then
			return
		end
		if UnitFrame_OnEnter then
			UnitFrame_OnEnter(self)
		else
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			GameTooltip:SetUnit(self.unit)
			GameTooltip:Show()
		end
	end)
	btn:HookScript("OnLeave", function(self)
		if UnitFrame_OnLeave then
			UnitFrame_OnLeave(self)
		else
			GameTooltip:Hide()
		end
	end)

	btn:HookScript("OnAttributeChanged", function(self, key, value)
		if key == "unit" then
			ns.PartySetUnit(self, value)
		end
	end)
	buttons[#buttons + 1] = btn
end

------------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------------

local function UpdateHealth(btn)
	local unit = btn.unit
	if not unit then
		return
	end
	btn.bar:SetMinMaxValues(0, UnitHealthMax(unit))
	btn.bar:SetValue(UnitHealth(unit))
	local connected, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
	if not IsSecret(connected) and not connected then
		btn.status:SetText("Offline")
	elseif not IsSecret(dead) and dead then
		btn.status:SetText("Dead")
	else
		btn.status:SetText("")
	end
	btn.gone = (not IsSecret(connected) and not connected) or (not IsSecret(dead) and dead) or false
end

-- One calculator for all frames, set up once: incoming heals clamped to
-- the missing health (overflow 1: never past the bar's end), shields to
-- what the heals leave of it.
local calculator

local function Calculator()
	if calculator == nil then
		calculator = false
		if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
			local ok, calc = pcall(CreateUnitHealPredictionCalculator)
			if ok and calc then
				pcall(calc.SetIncomingHealClampMode, calc, Enum.UnitIncomingHealClampMode.MissingHealth)
				pcall(calc.SetIncomingHealOverflowPercent, calc, 1)
				pcall(calc.SetDamageAbsorbClampMode, calc, Enum.UnitDamageAbsorbClampMode.MissingHealth)
				calculator = calc
			end
		end
	end
	return calculator
end

local function UpdateHeals(btn)
	local unit, calc = btn.unit, Calculator()
	if not (unit and calc) then
		return
	end
	local ok = pcall(UnitGetDetailedHealPrediction, unit, "player", calc)
	if not ok then
		btn.healMine:SetValue(0)
		btn.healOthers:SetValue(0)
		btn.absorb:SetValue(0)
		btn.overAbsorb:SetAlpha(0)
		return
	end
	local _, mine, others = calc:GetIncomingHeals()
	local max = UnitHealthMax(unit)
	btn.healMine:SetMinMaxValues(0, max)
	btn.healMine:SetValue(mine)
	btn.healOthers:SetMinMaxValues(0, max)
	btn.healOthers:SetValue(others)
	local absorb, clipped = calc:GetDamageAbsorbs()
	btn.absorb:SetMinMaxValues(0, max)
	btn.absorb:SetValue(absorb)
	if IsSecret(clipped) then
		btn.overAbsorb:SetAlphaFromBoolean(clipped, OVER_ABSORB_ALPHA, 0)
	else
		btn.overAbsorb:SetAlpha(clipped and OVER_ABSORB_ALPHA or 0)
	end
end

local function UpdateColour(btn)
	local colour
	if btn.gone then
		colour = COLOURS.gone
	elseif btn.unit and btn.unit:find("pet") then
		colour = PET_COLOUR
	else
		local _, class = UnitClass(btn.unit)
		if class and not IsSecret(class) then
			local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			colour = c and { c.r, c.g, c.b }
		end
	end
	colour = colour or { 1, 1, 1 }
	btn.bar:SetStatusBarColor(colour[1], colour[2], colour[3])
end

local function UpdateName(btn)
	local first = UnitName(btn.unit)
	if IsSecret(first) then
		btn.name:SetText(first)
	else
		btn.name:SetText(first and ns.Cut(first) or "")
	end
end

local function UpdateRole(btn)
	local role = UnitGroupRolesAssigned(btn.unit)
	local atlas = not IsSecret(role) and ROLE_ATLAS[role]
	if atlas then
		btn.role:SetAtlas(atlas)
		btn.role:SetAlpha(1)
	else
		btn.role:SetAlpha(0)
	end
end

-- Aggro as Blizzard's frames show it (CompactUnitFrame_UpdateAggroHighlight):
-- UnitThreatSituation(unit), shown above 0; levels 1-2 in the "gaining
-- threat" colour, 3 in "high threat". Unlike Blizzard, solo too (the user
-- asked, 2026-11-22): your own and your pet's aggro when alone.
-- Asked with one unit, which the game documents as generally not secret
-- (SecretWhenUnitThreatStateRestricted); a secret answer shows nothing.
local function ThreatColour(status)
	local colour = status >= 3 and HIGH_THREAT_COLOR or GAINING_THREAT_COLOR
	if colour and colour.GetRGB then
		return colour:GetRGB()
	end
	if status >= 3 then
		return 1, 0, 0
	end
	return 1, 0.6, 0
end

local function UpdateAggro(btn)
	if db and not db.aggro then
		btn.aggro:SetAlpha(0)
		return
	end
	local unit = btn.unit
	local ok, status = pcall(UnitThreatSituation, unit)
	if not ok or IsSecret(status) or not status or status <= 0 then
		btn.aggro:SetAlpha(0)
		return
	end
	local r, g, b = ThreatColour(status)
	for _, piece in pairs(btn.aggroGlow) do
		piece:SetVertexColor(r, g, b, 1)
	end
	btn.aggro:SetAlpha(1)
end

local function UpdateTarget(btn)
	local isTarget = UnitIsUnit(btn.unit, "target")
	if IsSecret(isTarget) then
		btn.target:SetAlphaFromBoolean(isTarget, 1, 0)
		btn.shadow:SetAlphaFromBoolean(isTarget, 0, 1)
	else
		btn.target:SetAlpha(isTarget and 1 or 0)
		btn.shadow:SetAlpha(isTarget and 0 or 1)
	end
end

local function UpdateRange(btn)
	local unit = btn.unit
	-- You, and your own pet: the game's range check only covers group
	-- members, and answered "not in range" for your pet (seen faded in
	-- game, 2026-11-22). Both its answers are secret, so whether it checked
	-- cannot be read; your pet is simply shown in full.
	if unit == "player" or unit == "pet" or (db and not db.rangeFade) then
		btn.body:SetAlpha(1)
		return
	end
	local faded = db and db.fadedAlpha or FADED
	local inRange = UnitInRange(unit)
	if IsSecret(inRange) then
		btn.body:SetAlphaFromBoolean(inRange, 1, faded)
	else
		-- Not in a group with them, or no answer: shown in full.
		btn.body:SetAlpha((inRange == false) and faded or 1)
	end
end

-- Which state to show, Blizzard's order (CompactUnitFrame_GetCenterStatusIconState):
-- a ready check while one runs or its result is held, else summon, rez,
-- other phase, public group. UnitPhaseReason is secret when unit identity
-- is restricted; then no phase icon.
local readyCheck = { active = false, held = false }

-- Each frame keeps its member's last ready-check answer: once a check ends
-- the game answers nil (seen in game 2026-11-22: the marks went the moment
-- the check finished), and Blizzard's frames show the kept answer too.
local function StatusState(unit, btn)
	if readyCheck.active then
		local status = GetReadyCheckStatus(unit)
		if status then
			btn.readyStatus = status
		end
	end
	if readyCheck.active or readyCheck.held then
		local status = btn.readyStatus
		if readyCheck.held and status == "waiting" then
			status = "notready"
		end
		if status then
			return status
		end
	end
	if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon(unit) then
		local status = C_IncomingSummon.IncomingSummonStatus(unit)
		if status == Enum.SummonStatus.Pending then
			return "summonPending"
		elseif status == Enum.SummonStatus.Accepted then
			return "summonAccepted"
		elseif status == Enum.SummonStatus.Declined then
			return "summonDeclined"
		end
	end
	if UnitHasIncomingResurrection(unit) then
		return "rez"
	end
	local phase = UnitPhaseReason(unit)
	if phase and not IsSecret(phase) then
		return "phase"
	end
	if UnitInOtherParty(unit) then
		return "otherParty"
	end
end

local function UpdateStatusIcon(btn)
	local unit = btn.unit
	local ok, state = pcall(StatusState, unit, btn)
	local atlas = ok and state and STATUS_ATLAS[state]
	if atlas then
		btn.statusIcon:SetAtlas(atlas)
		btn.statusIcon:Show()
	else
		btn.statusIcon:Hide()
	end
end

local function UpdateAll(btn)
	if not btn.unit then
		return
	end
	UpdateHealth(btn)
	UpdateHeals(btn)
	UpdateColour(btn)
	UpdateName(btn)
	UpdateRole(btn)
	UpdateTarget(btn)
	UpdateAggro(btn)
	UpdateRange(btn)
	UpdateStatusIcon(btn)
	for _, container in pairs(btn.auras) do
		container:UpdateAllAuras()
	end
end

function ns.PartySetUnit(btn, unit)
	if btn.unit and byUnit[btn.unit] == btn then
		byUnit[btn.unit] = nil
	end
	btn.unit = unit
	if unit then
		byUnit[unit] = btn
		for _, container in pairs(btn.auras) do
			container:SetUnit(unit)
		end
		UpdateAll(btn)
	end
end

local events = CreateFrame("Frame")
local UNIT_EVENTS = {
	UNIT_HEALTH = function(btn) UpdateHealth(btn); UpdateHeals(btn); UpdateColour(btn) end,
	UNIT_MAXHEALTH = function(btn) UpdateHealth(btn); UpdateHeals(btn) end,
	UNIT_HEAL_PREDICTION = UpdateHeals,
	UNIT_ABSORB_AMOUNT_CHANGED = UpdateHeals,
	UNIT_CONNECTION = function(btn) UpdateHealth(btn); UpdateColour(btn) end,
	UNIT_FLAGS = function(btn) UpdateHealth(btn); UpdateColour(btn) end,
	UNIT_NAME_UPDATE = UpdateName,
	UNIT_THREAT_SITUATION_UPDATE = UpdateAggro,
	UNIT_THREAT_LIST_UPDATE = UpdateAggro,
	INCOMING_SUMMON_CHANGED = UpdateStatusIcon,
	INCOMING_RESURRECT_CHANGED = UpdateStatusIcon,
	UNIT_PHASE = UpdateStatusIcon,
	UNIT_OTHER_PARTY_CHANGED = UpdateStatusIcon,
	READY_CHECK_CONFIRM = UpdateStatusIcon,
}
for event in pairs(UNIT_EVENTS) do
	events:RegisterEvent(event)
end
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("READY_CHECK_FINISHED")
events:SetScript("OnEvent", function(_, event, unit)
	local handler = UNIT_EVENTS[event]
	if handler then
		local btn = byUnit[unit]
		if btn and btn:IsShown() then
			handler(btn)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		for _, btn in pairs(byUnit) do
			UpdateTarget(btn)
		end
	elseif event == "READY_CHECK" or event == "READY_CHECK_FINISHED" then
		-- The result stays a while after the check ends, then goes.
		readyCheck.active = event == "READY_CHECK"
		readyCheck.held = event == "READY_CHECK_FINISHED"
		if readyCheck.active then
			for _, btn in pairs(byUnit) do
				btn.readyStatus = nil -- a new check: forget the last one's answers
			end
		end
		if readyCheck.held then
			local token = {}
			readyCheck.token = token
			C_Timer.After(READY_CHECK_HOLD, function()
				if readyCheck.token == token then
					readyCheck.held = false
					for _, btn in pairs(byUnit) do
						UpdateStatusIcon(btn)
					end
				end
			end)
		end
		for _, btn in pairs(byUnit) do
			UpdateStatusIcon(btn)
		end
	else
		for _, btn in pairs(byUnit) do
			UpdateAll(btn)
		end
	end
end)

local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed < 0.2 then
		return
	end
	elapsed = 0
	for _, btn in pairs(byUnit) do
		if btn:IsShown() then
			UpdateRange(btn)
		end
	end
end)

------------------------------------------------------------------------------
-- Header, anchor and moving
------------------------------------------------------------------------------

-- How the party is laid out (options page): a row or a column, and which
-- way it grows from the anchor. point/dx/dy are the header's own
-- attributes (each next button hangs by point off the one before); at is
-- where the header hangs from the anchor; pet is where the pet row or
-- column hangs from the party (its point, the party's point, and which way
-- PET_GAP goes). Columns sit 2 apart, rows 6 (user: less vertical than
-- horizontal).
local COLUMN_GAP = 2
local PARTY_LAYOUTS = {
	{ key = "rowCentre", label = "Row, centred", point = "LEFT", dx = GAP, dy = 0, at = "CENTER", pet = { "TOP", "BOTTOM", 0, -1 } },
	{ key = "rowRight", label = "Row, growing right", point = "LEFT", dx = GAP, dy = 0, at = "LEFT", pet = { "TOPLEFT", "BOTTOMLEFT", 0, -1 } },
	{ key = "rowLeft", label = "Row, growing left", point = "RIGHT", dx = -GAP, dy = 0, at = "RIGHT", pet = { "TOPRIGHT", "BOTTOMRIGHT", 0, -1 } },
	{ key = "columnDown", label = "Column, growing down", point = "TOP", dx = 0, dy = -COLUMN_GAP, at = "TOP", pet = { "TOPLEFT", "TOPRIGHT", 1, 0 } },
	{ key = "columnUp", label = "Column, growing up", point = "BOTTOM", dx = 0, dy = COLUMN_GAP, at = "BOTTOM", pet = { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 0 } },
	{ key = "columnCentre", label = "Column, centred", point = "TOP", dx = 0, dy = -COLUMN_GAP, at = "CENTER", pet = { "LEFT", "RIGHT", 1, 0 } },
}
ns.PARTY_LAYOUTS = PARTY_LAYOUTS

local OPPOSITE = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" }

-- Frames one after another, as a group header lays out its buttons: the
-- first by point to the box's point, each next by point to the previous
-- one's opposite side, dx/dy apart. Used for the test frames, so they sit
-- where the real ones would.
function ns.ChainFrames(box, frames, point, dx, dy)
	local previous
	for i, frame in ipairs(frames) do
		frame:ClearAllPoints()
		if i == 1 then
			frame:SetPoint(point, box, point, 0, 0)
		else
			frame:SetPoint(point, previous, OPPOSITE[point], dx, dy)
		end
		frame:Show()
		previous = frame
	end
end

-- The size n frames take, chained as above.
function ns.ChainSize(n, point, dx, dy)
	if n == 0 then
		return 0.1, 0.1
	end
	if point == "LEFT" or point == "RIGHT" then
		return n * BUTTON_W + (n - 1) * math.abs(dx), BUTTON_H
	end
	return BUTTON_W, n * BUTTON_H + (n - 1) * math.abs(dy)
end

-- A header's buttons lose their anchors before its layout attributes
-- change: the header re-anchors them without clearing, so an old anchor
-- would stay on. Not in combat.
function ns.ClearHeaderButtons(h)
	local i = 1
	while true do
		local button = h:GetAttribute("child" .. i)
		if not button then
			return
		end
		button:ClearAllPoints()
		i = i + 1
	end
end

local anchor = CreateFrame("Frame", "GroupFramesPartyAnchor", UIParent)
anchor:SetSize(5 * BUTTON_W + 4 * GAP, BUTTON_H)
anchor:SetMovable(true)
if ForeverSnap then ForeverSnap.Register(anchor) end -- snaps to the screen and our other frames
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)
local handle = anchor:CreateTexture(nil, "BACKGROUND")
handle:SetAllPoints()
handle:SetColorTexture(0.1, 0.8, 0.2, 0.35)
handle:Hide()
local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", anchor, "TOP", 0, 14)
label:SetText("GroupFrames: drag to move, /groupframes to lock")
label:Hide()

local header = CreateFrame("Frame", "GroupFramesParty", anchor, "SecureGroupHeaderTemplate")
header:SetPoint("CENTER", anchor, "CENTER")
header:SetAttribute("template", "GroupFramesUnitButtonTemplate")
header:SetAttribute("templateType", "Button")
header:SetAttribute("showParty", true)
header:SetAttribute("showPlayer", true)
header:SetAttribute("showRaid", false)
header:SetAttribute("showSolo", true) -- your own frame when not in a group
header:SetAttribute("point", "LEFT")
header:SetAttribute("xOffset", GAP)
header:SetAttribute("initialConfigFunction", ([[
	self:SetWidth(%d)
	self:SetHeight(%d)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
]]):format(BUTTON_W, BUTTON_H))
ns.PartyHeader = header

-- Pets: the game's pet header picks your pet and your party members' pets
-- (pet, partypet1..4) and lays them out as the party header does; the same
-- button template, so the same look. The whole header is scaled down (not
-- the buttons: the header sizes itself from its buttons' unscaled size),
-- and hangs by its top centre under the party row, so it centres itself.
local petHeader = CreateFrame("Frame", "GroupFramesPartyPets", anchor, "SecureGroupPetHeaderTemplate")
petHeader:SetScale(PET_SCALE)
petHeader:SetPoint("TOP", header, "BOTTOM", 0, -PET_GAP / PET_SCALE)
petHeader:SetAttribute("template", "GroupFramesUnitButtonTemplate")
petHeader:SetAttribute("templateType", "Button")
petHeader:SetAttribute("showParty", true)
petHeader:SetAttribute("showPlayer", true)
petHeader:SetAttribute("showRaid", false)
petHeader:SetAttribute("showSolo", true) -- your pet beside your solo frame
petHeader:SetAttribute("point", "LEFT")
petHeader:SetAttribute("xOffset", GAP)
petHeader:SetAttribute("initialConfigFunction", header:GetAttribute("initialConfigFunction"))
ns.PetHeader = petHeader

local function PartyLayout()
	local key = db and db.partyLayout
	for _, layout in ipairs(PARTY_LAYOUTS) do
		if layout.key == key then
			return layout
		end
	end
	return PARTY_LAYOUTS[1]
end

-- The drag box follows the shape: a row of five or a column of five.
local function SizeAnchor(layout)
	if layout.point == "LEFT" or layout.point == "RIGHT" then
		anchor:SetSize(5 * BUTTON_W + 4 * GAP, BUTTON_H)
	else
		anchor:SetSize(BUTTON_W, 5 * BUTTON_H + 4 * math.abs(layout.dy))
	end
end

local function ApplyPartyLayout()
	local layout = PartyLayout()
	SizeAnchor(layout)
	for _, h in ipairs({ header, petHeader }) do
		ns.ClearHeaderButtons(h)
		h:SetAttribute("xOffset", layout.dx)
		h:SetAttribute("yOffset", layout.dy)
		h:SetAttribute("point", layout.point)
	end
	header:ClearAllPoints()
	header:SetPoint(layout.at, anchor, layout.at)
	petHeader:ClearAllPoints()
	petHeader:SetPoint(layout.pet[1], header, layout.pet[2],
		layout.pet[3] * PET_GAP / PET_SCALE, layout.pet[4] * PET_GAP / PET_SCALE)
end

-- Shown in a party (and solo), hidden in a raid, where Blizzard's raid
-- frames take over.
local VISIBILITY = "[group:raid] hide; show"

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

local unlocked = false
local soloHidden = false -- test mode hides your solo frame
local testing = false -- test mode is on (ns.PartyTest)
local testCount -- how many test frames

local function ApplySolo()
	local solo = (not db or db.soloFrame) and not soloHidden
	header:SetAttribute("showSolo", solo)
	petHeader:SetAttribute("showSolo", solo)
end

local function ApplyPartyPets()
	if db.partyPets and not testing then
		RegisterStateDriver(petHeader, "visibility", VISIBILITY)
	else
		UnregisterStateDriver(petHeader, "visibility")
		petHeader:Hide()
	end
end

function ns.PartyUnlock(unlock, withoutSolo)
	if InCombatLockdown() then
		return false
	end
	unlocked = unlock
	handle:SetShown(unlock)
	label:SetShown(unlock)
	anchor:EnableMouse(unlock)
	-- Solo you see your own frame (if that setting is on), except in test
	-- mode, whose frames stand in for everyone.
	soloHidden = unlock and withoutSolo or false
	ApplySolo()
	return true
end

function ns.PartyReset()
	db.point = { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
	ApplyPosition()
end

function ns.PartyUnlocked()
	return unlocked
end

-- Blizzard's party frames out of sight: PartyFrame (both the old-style
-- party frames and the raid-style CompactPartyFrame live in it) under a
-- hidden frame.
local hidden = CreateFrame("Frame")
hidden:Hide()

local function HideBlizzardParty()
	if PartyFrame and PartyFrame:GetParent() ~= hidden then
		PartyFrame:SetParent(hidden)
	end
end

-- The bleed filter on every button: aura containers are not protected, so
-- this works in combat too.
-- Every button's dispel groups as the settings say: aura containers are
-- not protected, so this works in combat too.
local function ApplyDispelShow(btn)
	for _, dispelType in ipairs(DISPEL_TYPES) do
		local show, key = DispelShow(dispelType), "Dispel" .. dispelType
		if show.filter then
			btn.auras.dispel:SetAuraGroupFilterString(key, show.filter)
		end
		btn.auras.dispel:SetAuraGroupEnabled(key, show.filter ~= nil)
	end
end

function ns.PartyApplyDispelShow()
	for _, btn in ipairs(buttons) do
		ApplyDispelShow(btn)
	end
end

ns.DISPEL_TYPES = DISPEL_TYPES
ns.DISPEL_SHOW = DISPEL_SHOW
ns.DISPEL_SHOW_DEFAULT = DISPEL_SHOW_DEFAULT

function ns.PartyLogin(saved)
	db = saved
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then
			db[key] = value
		end
	end
	db.point = db.point or { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
	db.allBleeds = nil -- 4f2c050's checkbox, replaced by dispelShow
	db.dispelShow = db.dispelShow or {}
	ApplyPosition()
	HideBlizzardParty()
	ns.PartyApplyDispelShow() -- buttons made before the saved settings were read
	-- How many spells the game named, said once so it can be checked.
	local _, count = BigDefensives()
	if db.bigDefensives ~= count then
		print(("|cffffd100GroupFrames|r: %d spells count as big defensives."):format(count))
		db.bigDefensives = count
	end
	-- In a raid the raid frames take over.
	ApplyPartyLayout()
	RegisterStateDriver(header, "visibility", VISIBILITY)
	ApplyPartyPets()
	ApplySolo()
end

-- After a setting changed (Options.lua). What touches the secure headers
-- waits for the end of combat; the rest shows at once.
local settingsPending = false

function ns.PartyApplySettings()
	for _, btn in pairs(byUnit) do
		UpdateRange(btn)
		UpdateAggro(btn)
	end
	if InCombatLockdown() then
		settingsPending = true
		return false
	end
	settingsPending = false
	ApplyPartyLayout()
	ApplySolo()
	ApplyPartyPets()
	if testing then
		ns.PartyTest(testCount) -- the test frames take the new layout too
	end
	return true
end

function ns.PartySettingsPending()
	return settingsPending
end

ns.PARTY_DEFAULTS = DEFAULTS


------------------------------------------------------------------------------
-- Test mode: look-only frames with made-up members, drawn by BuildLook like
-- the real ones and laid out as the header lays them out (a row, centred on
-- the anchor). They are plain frames: no unit, no clicks. The auras are
-- painted on, since the game's containers only show real auras.
------------------------------------------------------------------------------

local PREVIEW = {
	{ name = "Decayla", class = "PRIEST", role = "HEALER", health = 0.9, dots = { "shield", "renew" }, status = "ready" },
	{ name = "Belle", class = "WARRIOR", role = "TANK", health = 0.62, dots = { "shield" }, weakened = true, target = true, big = 871, absorb = 0.18, aggro = 3 },
	{ name = "Fearonica", class = "WARLOCK", role = "DAMAGER", health = 0.35, dots = { "renew" }, dispel = { "Magic", "Curse" }, heals = { 0.2, 0.12 } },
	{ name = "Arya", class = "HUNTER", role = "DAMAGER", health = 1, overAbsorb = true },
	{ name = "Zulrin", class = "SHAMAN", role = "DAMAGER", health = 0, dead = true, status = "rez" },
}

local previews = {}

local function PaintedDot(frame, colour, x, y, point)
	local rim = frame.top:CreateTexture(nil, "OVERLAY")
	rim:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	rim:SetSize(DOT + 2, DOT + 2)
	rim:SetPoint(point, frame.bar, point, x + (point == "BOTTOMRIGHT" and 1 or -1), y - 1)
	rim:SetVertexColor(0, 0, 0, 1)
	local dot = frame.top:CreateTexture(nil, "OVERLAY", nil, 1)
	dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	dot:SetSize(DOT, DOT)
	dot:SetPoint(point, frame.bar, point, x, y)
	dot:SetVertexColor(colour[1], colour[2], colour[3], 1)
end

-- A look-only frame on parent, painted with a made-up member (data as in
-- PREVIEW). Shared with the raid's test mode (Raid.lua).
function ns.PaintPreview(parent, data)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(BUTTON_W, BUTTON_H)
	BuildLook(frame)

	frame.bar:SetMinMaxValues(0, 1)
	frame.bar:SetValue(data.health)
	if data.heals then
		frame.healMine:SetValue(data.heals[1])
		frame.healOthers:SetValue(data.heals[2])
	end
	frame.absorb:SetValue(data.absorb or 0)
	frame.overAbsorb:SetAlpha(data.overAbsorb and OVER_ABSORB_ALPHA or 0)
	local c = data.dead and { r = COLOURS.gone[1], g = COLOURS.gone[2], b = COLOURS.gone[3] }
		or data.pet and { r = PET_COLOUR[1], g = PET_COLOUR[2], b = PET_COLOUR[3] }
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]) or { r = 1, g = 1, b = 1 }
	frame.bar:SetStatusBarColor(c.r, c.g, c.b)
	frame.name:SetText(ns.Cut(data.name))
	if data.role and ROLE_ATLAS[data.role] then
		frame.role:SetAtlas(ROLE_ATLAS[data.role])
	else
		frame.role:SetAlpha(0)
	end
	frame.status:SetText(data.dead and "Dead" or "")
	if data.status then
		frame.statusIcon:SetAtlas(STATUS_ATLAS[data.status])
		frame.statusIcon:Show()
	end
	frame.target:SetAlpha(data.target and 1 or 0)
	frame.shadow:SetAlpha(data.target and 0 or 1)
	if data.aggro then
		local r, g, b = ThreatColour(data.aggro)
		for _, piece in pairs(frame.aggroGlow) do
			piece:SetVertexColor(r, g, b, 1)
		end
		frame.aggro:SetAlpha(1)
	end

	for i, kind in ipairs(data.dots or {}) do
		PaintedDot(frame, COLOURS[kind], -DOT_X - (i - 1) * (DOT + DOT_GAP), DOT_Y, "BOTTOMRIGHT")
	end
	if data.big then
		local holder = CreateFrame("Frame", nil, frame.body)
		holder:SetFrameLevel(frame.top:GetFrameLevel() + 2)
		holder:SetSize(BIG_ICON, BIG_ICON)
		holder:SetPoint("CENTER", frame.bar, "CENTER", 0, 0)
		local icon = Picture(holder)
		local ok, texture = pcall(C_Spell.GetSpellTexture, data.big)
		icon:SetTexture(ok and texture or "Interface\\Icons\\INV_Misc_QuestionMark")
		pcall(Dress, holder, icon)
		pcall(Glow, holder)
		frame.big = holder
	end
	-- The bottom-left dot as your class shows it (CreateAuras).
	local _, class = UnitClass("player")
	local mark = class == "PRIEST" and COLOURS.weakened or class == "PALADIN" and COLOURS.forbearance
	if data.weakened and mark then
		PaintedDot(frame, mark, DOT_X, DOT_Y, "BOTTOMLEFT")
	end
	for i, dispelType in ipairs(data.dispel or {}) do
		local icon = frame.top:CreateTexture(nil, "OVERLAY")
		icon:SetAtlas("RaidFrame-Icon-Debuff" .. dispelType)
		icon:SetSize(DISPEL_ICON, DISPEL_ICON)
		icon:SetPoint("RIGHT", frame.bar, "TOPRIGHT", -4 - (i - 1) * (DISPEL_ICON + 1), LINE_Y)
	end
	return frame
end

-- Made-up pets, each with the test member it belongs to: shown with the
-- test party when that member is in it and party pets are on.
local PET_PREVIEW = {
	{ owner = 3, name = "Gobnip", pet = true, health = 0.7, dots = { "renew" } },
	{ owner = 4, name = "Stitches", pet = true, health = 1 },
}

local petPreviews = {}
-- The test row stands in for the header (sized to its frames, hung from
-- the anchor as the header is); the pets' holder for the pet header,
-- scaled as it is.
local previewBox = CreateFrame("Frame", nil, anchor)
previewBox:SetSize(0.1, 0.1)
local petHolder = CreateFrame("Frame", nil, anchor)
petHolder:SetScale(PET_SCALE)
petHolder:SetSize(0.1, 0.1)
petHolder:Hide()

local function PreviewFrame(index)
	local frame = previews[index]
	if not frame then
		frame = ns.PaintPreview(anchor, PREVIEW[index])
		previews[index] = frame
	end
	return frame
end

-- count 1 to 5 shows that many, laid out as the party layout lays the real
-- ones; nil ends the test.
function ns.PartyTest(count)
	if count and InCombatLockdown() then
		return false
	end
	-- The real frames make way for the test frames, and come back after.
	-- Not in combat: the header is secure (an ending test is started from
	-- the enter-combat event, before the lockdown).
	if count and not testing then
		UnregisterStateDriver(header, "visibility")
		header:Hide()
		UnregisterStateDriver(petHeader, "visibility")
		petHeader:Hide()
	end
	local wasTesting = testing
	testing = count and true or false
	testCount = count
	if not count and wasTesting then
		RegisterStateDriver(header, "visibility", VISIBILITY)
		ApplyPartyPets()
	end

	local layout = PartyLayout()
	local list = {}
	for i = 1, #PREVIEW do
		local frame = (count and i <= count) and PreviewFrame(i) or previews[i]
		if frame then
			if count and i <= count then
				list[#list + 1] = frame
			else
				frame:Hide()
			end
		end
	end
	previewBox:SetSize(ns.ChainSize(#list, layout.point, layout.dx, layout.dy))
	previewBox:ClearAllPoints()
	previewBox:SetPoint(layout.at, anchor, layout.at)
	ns.ChainFrames(previewBox, list, layout.point, layout.dx, layout.dy)

	-- Their pets, as the pet header would show them (party pets on).
	for _, frame in pairs(petPreviews) do
		frame:Hide()
	end
	local shown = {}
	if count and db and db.partyPets then
		for i, pet in ipairs(PET_PREVIEW) do
			if pet.owner <= count then
				petPreviews[i] = petPreviews[i] or ns.PaintPreview(petHolder, pet)
				shown[#shown + 1] = petPreviews[i]
			end
		end
	end
	petHolder:SetSize(ns.ChainSize(#shown, layout.point, layout.dx, layout.dy))
	petHolder:ClearAllPoints()
	petHolder:SetPoint(layout.pet[1], previewBox, layout.pet[2],
		layout.pet[3] * PET_GAP / PET_SCALE, layout.pet[4] * PET_GAP / PET_SCALE)
	petHolder:SetShown(#shown > 0)
	ns.ChainFrames(petHolder, shown, layout.point, layout.dx, layout.dy)
	return true
end

function ns.PartyTesting()
	return testing
end

ns.Party = { petPreviews = petPreviews, petHolder = petHolder, PET_SCALE = PET_SCALE, previews = previews, buttons = buttons, byUnit = byUnit, header = header, petHeader = petHeader, anchor = anchor, hidden = hidden,
	UpdateAll = UpdateAll, UpdateRange = UpdateRange, BUTTON_W = BUTTON_W, BUTTON_H = BUTTON_H, GAP = GAP, PREVIEW = PREVIEW,
	handleColour = { 0.1, 0.8, 0.2, 0.35 } }
