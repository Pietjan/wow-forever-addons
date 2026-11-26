-- GroupFrames raid frames: the party's frames (same button template, so the
-- same look and everything on them), one group per row.
--
-- Each size (10, 25, 40) has its own saved place; the raid moves there when
-- the layout changes, and /groupframes test raid N unlocks N's place.
--
-- Eight SecureGroupHeaderTemplate headers, one per raid group
-- (groupFilter "1".."8"), each a row like the party's and hung by its top
-- centre under the one before, so every row is centred and an empty group
-- takes no room. All eight sit in one block that is scaled by the raid's
-- size (user, 2026-11-22; scratchpad/groupframes/raid*.png): up to 10 at
-- the party's size, up to 25 at 84%, more at 70%. Scaling keeps the look
-- the party's; the frames are never resized. Secure frames cannot be
-- rearranged in combat, so a roster change mid-fight takes effect when
-- combat ends.
--
-- Rows are 6 apart sideways and 2 apart downwards (user: less vertical
-- than horizontal). Shown in a raid only; the party frames hide there.
-- Blizzard's raid frames (CompactRaidFrameManager and its container) are
-- moved under the same hidden frame as its party frames.

local _, ns = ...

local GROUPS = 8
local ROW_GAP = 2
local SIZES = { { 10, 1 }, { 25, 0.84 }, { 40, 0.7 } } -- raid size up to, scale
local DEFAULT_POINT = { "TOP", 0, -120 }
local VISIBILITY = "[group:raid] show; hide"

local P = ns.Party
local W, H, GAP = P.BUTTON_W, P.BUTTON_H, P.GAP

-- How each raid size is laid out (options page). member: the group header's
-- own attributes (each next button hangs by point off the one before);
-- first: how group 1 hangs from the block; chain: how each next group hangs
-- from the one before; at: where the block hangs from the anchor; pets:
-- where the pet grid hangs from the last group, and which way its rows or
-- columns follow on. Frames sit 6 apart side by side and 2 apart one above
-- the other (user). Centred columns are left out: centring them needs the
-- number of groups with people, which can change in combat.
local G, R = GAP, ROW_GAP
local RAID_LAYOUTS = {
	{ key = "rowsDownCentre", label = "Groups as rows, stacked down, centred",
		member = { "LEFT", G, 0 }, first = { "TOP", "TOP" }, chain = { "TOP", "BOTTOM", 0, -R }, at = "TOP",
		pets = { "TOP", "BOTTOM", 0, -4, "TOP", R } },
	{ key = "rowsDownLeft", label = "Groups as rows, stacked down, left-aligned",
		member = { "LEFT", G, 0 }, first = { "TOPLEFT", "TOPLEFT" }, chain = { "TOPLEFT", "BOTTOMLEFT", 0, -R }, at = "TOPLEFT",
		pets = { "TOPLEFT", "BOTTOMLEFT", 0, -4, "TOP", R } },
	{ key = "rowsDownRight", label = "Groups as rows, stacked down, right-aligned",
		member = { "RIGHT", -G, 0 }, first = { "TOPRIGHT", "TOPRIGHT" }, chain = { "TOPRIGHT", "BOTTOMRIGHT", 0, -R }, at = "TOPRIGHT",
		pets = { "TOPRIGHT", "BOTTOMRIGHT", 0, -4, "TOP", R } },
	{ key = "rowsUpCentre", label = "Groups as rows, stacked up, centred",
		member = { "LEFT", G, 0 }, first = { "BOTTOM", "BOTTOM" }, chain = { "BOTTOM", "TOP", 0, R }, at = "BOTTOM",
		pets = { "BOTTOM", "TOP", 0, 4, "BOTTOM", R } },
	{ key = "rowsUpLeft", label = "Groups as rows, stacked up, left-aligned",
		member = { "LEFT", G, 0 }, first = { "BOTTOMLEFT", "BOTTOMLEFT" }, chain = { "BOTTOMLEFT", "TOPLEFT", 0, R }, at = "BOTTOMLEFT",
		pets = { "BOTTOMLEFT", "TOPLEFT", 0, 4, "BOTTOM", R } },
	{ key = "rowsUpRight", label = "Groups as rows, stacked up, right-aligned",
		member = { "RIGHT", -G, 0 }, first = { "BOTTOMRIGHT", "BOTTOMRIGHT" }, chain = { "BOTTOMRIGHT", "TOPRIGHT", 0, R }, at = "BOTTOMRIGHT",
		pets = { "BOTTOMRIGHT", "TOPRIGHT", 0, 4, "BOTTOM", R } },
	{ key = "columnsRightDown", label = "Groups as columns, rightward, members down",
		member = { "TOP", 0, -R }, first = { "TOPLEFT", "TOPLEFT" }, chain = { "TOPLEFT", "TOPRIGHT", G, 0 }, at = "TOPLEFT",
		pets = { "TOPLEFT", "TOPRIGHT", G, 0, "LEFT", G } },
	{ key = "columnsLeftDown", label = "Groups as columns, leftward, members down",
		member = { "TOP", 0, -R }, first = { "TOPRIGHT", "TOPRIGHT" }, chain = { "TOPRIGHT", "TOPLEFT", -G, 0 }, at = "TOPRIGHT",
		pets = { "TOPRIGHT", "TOPLEFT", -G, 0, "RIGHT", G } },
	{ key = "columnsRightUp", label = "Groups as columns, rightward, members up",
		member = { "BOTTOM", 0, R }, first = { "BOTTOMLEFT", "BOTTOMLEFT" }, chain = { "BOTTOMLEFT", "BOTTOMRIGHT", G, 0 }, at = "BOTTOMLEFT",
		pets = { "BOTTOMLEFT", "BOTTOMRIGHT", G, 0, "LEFT", G } },
	{ key = "columnsLeftUp", label = "Groups as columns, leftward, members up",
		member = { "BOTTOM", 0, R }, first = { "BOTTOMRIGHT", "BOTTOMRIGHT" }, chain = { "BOTTOMRIGHT", "BOTTOMLEFT", -G, 0 }, at = "BOTTOMRIGHT",
		pets = { "BOTTOMRIGHT", "BOTTOMLEFT", -G, 0, "RIGHT", G } },
}
ns.RAID_LAYOUTS = RAID_LAYOUTS

local db

-- The layout for a headcount: its size (10, 25 or 40) and scale.
-- The scale is the options page's (db.raidScales) where set.
local function LayoutFor(count)
	local pick = SIZES[#SIZES]
	for _, size in ipairs(SIZES) do
		if count <= size[1] then
			pick = size
			break
		end
	end
	local scale = db and db.raidScales and db.raidScales[pick[1]] or pick[2]
	return pick[1], scale
end

local function ScaleFor(count)
	local _, scale = LayoutFor(count)
	return scale
end

local currentSize = 10 -- the layout shown now; its position is the one used and dragged
local testing = false -- a raid test is running (ns.RaidTest)
local testCount -- its size

------------------------------------------------------------------------------
-- Anchor, block, headers
------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "GroupFramesRaidAnchor", UIParent)
-- LOW strata, under MEDIUM popups such as the totem flyout (fstack, user,
-- 2026-11-26); set before any child, so the headers and buttons inherit it.
anchor:SetFrameStrata("LOW")
anchor:SetSize(5 * W + 4 * GAP, H)
anchor:SetMovable(true)
if ForeverSnap then ForeverSnap.Register(anchor) end -- snaps to the screen and our other frames
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)
local handle = anchor:CreateTexture(nil, "BACKGROUND")
handle:SetAllPoints()
handle:SetColorTexture(0.2, 0.5, 0.9, 0.35)
handle:Hide()
local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", anchor, "TOP", 0, 14)
label:SetText("GroupFrames raid: drag to move, /groupframes to lock")
label:Hide()

-- The scaled block: the raid's top centre is the anchor's.
local block = CreateFrame("Frame", "GroupFramesRaid", anchor)
block:SetSize(5 * W + 4 * GAP, H)
block:SetPoint("TOP", anchor, "TOP")

local headers = {}
for group = 1, GROUPS do
	local header = CreateFrame("Frame", "GroupFramesRaidGroup" .. group, block, "SecureGroupHeaderTemplate")
	if group == 1 then
		header:SetPoint("TOP", block, "TOP")
	else
		header:SetPoint("TOP", headers[group - 1], "BOTTOM", 0, -ROW_GAP)
	end
	header:SetAttribute("template", "GroupFramesUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	header:SetAttribute("showRaid", true)
	header:SetAttribute("groupFilter", tostring(group))
	header:SetAttribute("point", "LEFT")
	header:SetAttribute("xOffset", GAP)
	header:SetAttribute("initialConfigFunction", P.header:GetAttribute("initialConfigFunction"))
	headers[group] = header
end

-- Raid pets (optional, off by default; /groupframes raidpets): the game's
-- pet header for the raid, its pets in rows of 5 (a grid: 5 to a "column"
-- laid out to the right, new rows under the last), at the party pets' 75%,
-- hung by its top centre under the last group row. Inside the block, so
-- it scales with the raid's size.
local PET_SCALE = 0.75
local pets = CreateFrame("Frame", "GroupFramesRaidPets", block, "SecureGroupPetHeaderTemplate")
pets:SetScale(PET_SCALE)
pets:SetPoint("TOP", headers[GROUPS], "BOTTOM", 0, -4 / PET_SCALE)
pets:SetAttribute("template", "GroupFramesUnitButtonTemplate")
pets:SetAttribute("templateType", "Button")
pets:SetAttribute("showRaid", true)
pets:SetAttribute("point", "LEFT")
pets:SetAttribute("xOffset", GAP)
pets:SetAttribute("unitsPerColumn", 5)
pets:SetAttribute("maxColumns", 8)
pets:SetAttribute("columnAnchorPoint", "TOP")
pets:SetAttribute("columnSpacing", ROW_GAP)
pets:SetAttribute("initialConfigFunction", P.header:GetAttribute("initialConfigFunction"))

local petsPending = false

local function ApplyPets()
	if InCombatLockdown() then
		petsPending = true
		return false
	end
	petsPending = false
	-- Per raid size (user, 2026-11-22): the layout shown now decides.
	if db.raidPetsBySize[currentSize] then
		RegisterStateDriver(pets, "visibility", VISIBILITY)
	else
		UnregisterStateDriver(pets, "visibility")
		pets:Hide()
	end
	return true
end

-- size: 10, 25 or 40; the layout shown now when left out.
function ns.RaidPets(on, size)
	db.raidPetsBySize[size or currentSize] = on and true or false
	if testing then
		return true -- shown when the test ends
	end
	return ApplyPets()
end

function ns.RaidPetsShown(size)
	return db and db.raidPetsBySize and db.raidPetsBySize[size or currentSize] or false
end

function ns.RaidCurrentSize()
	return currentSize
end

------------------------------------------------------------------------------
-- Size
------------------------------------------------------------------------------

local pendingScale = false
local ApplyPosition

local function RaidLayout(size)
	local key = db and db.raidLayouts and db.raidLayouts[size]
	for _, layout in ipairs(RAID_LAYOUTS) do
		if layout.key == key then
			return layout
		end
	end
	return RAID_LAYOUTS[1]
end

local function IsRows(layout)
	return layout.member[1] == "LEFT" or layout.member[1] == "RIGHT"
end

-- Headers, block, pets and drag box arranged for a size's layout. Not in
-- combat: the headers are secure.
local function ApplyGroupLayout(size)
	local layout = RaidLayout(size)
	local point, dx, dy = layout.member[1], layout.member[2], layout.member[3]
	if IsRows(layout) then
		anchor:SetSize(5 * W + 4 * GAP, H)
	else
		anchor:SetSize(W, 5 * H + 4 * ROW_GAP)
	end
	block:ClearAllPoints()
	block:SetPoint(layout.at, anchor, layout.at)
	for group, header in ipairs(headers) do
		ns.ClearHeaderButtons(header)
		header:SetAttribute("xOffset", dx)
		header:SetAttribute("yOffset", dy)
		header:SetAttribute("point", point)
		header:ClearAllPoints()
		if group == 1 then
			header:SetPoint(layout.first[1], block, layout.first[2])
		else
			header:SetPoint(layout.chain[1], headers[group - 1], layout.chain[2], layout.chain[3], layout.chain[4])
		end
	end
	local p = layout.pets
	ns.ClearHeaderButtons(pets)
	pets:SetAttribute("xOffset", dx)
	pets:SetAttribute("yOffset", dy)
	pets:SetAttribute("columnAnchorPoint", p[5])
	pets:SetAttribute("columnSpacing", p[6])
	pets:SetAttribute("point", point)
	pets:ClearAllPoints()
	pets:SetPoint(p[1], headers[GROUPS], p[2], p[3] / PET_SCALE, p[4] / PET_SCALE)
end

-- Scale and place the raid for a headcount. Each size keeps a place of its
-- own (user, 2026-11-22). Not in combat: the block holds secure frames.
local function ApplyLayout(count)
	local size, scale = LayoutFor(count)
	currentSize = size
	block:SetScale(scale)
	ApplyGroupLayout(size)
	label:SetText(("GroupFrames raid (%d): drag to move, /groupframes to lock"):format(size))
	ApplyPosition()
	if db and not testing then
		ApplyPets()
	end
end

local function ApplyScale()
	if InCombatLockdown() then
		pendingScale = true
		return
	end
	pendingScale = false
	ApplyLayout(GetNumGroupMembers and GetNumGroupMembers() or 0)
end

------------------------------------------------------------------------------
-- Position and moving
------------------------------------------------------------------------------

function ApplyPosition()
	if not db then
		return
	end
	local point = db.raidPoints[currentSize] or DEFAULT_POINT
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[1], point[2], point[3])
end

anchor:SetScript("OnDragStart", function()
	anchor:StartMoving()
end)
anchor:SetScript("OnDragStop", function()
	anchor:StopMovingOrSizing()
	local point, _, _, x, y = anchor:GetPoint(1)
	db.raidPoints[currentSize] = { point, x, y }
end)

function ns.RaidUnlock(unlock)
	handle:SetShown(unlock)
	label:SetShown(unlock)
	anchor:EnableMouse(unlock)
end

function ns.RaidReset()
	db.raidPoints = {}
	ApplyPosition()
end

------------------------------------------------------------------------------
-- Blizzard's raid frames out of sight
------------------------------------------------------------------------------

local function HideBlizzardRaid()
	for _, name in ipairs({ "CompactRaidFrameManager", "CompactRaidFrameContainer" }) do
		local frame = _G[name]
		if frame and frame:GetParent() ~= P.hidden then
			frame:SetParent(P.hidden)
		end
	end
end

------------------------------------------------------------------------------
-- Test mode: /groupframes test raid 10|25|40
------------------------------------------------------------------------------

local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "SHAMAN", "PALADIN" }
local NAMES = { "Thokar", "Mirelle", "Zulrin", "Grosh", "Kaelani", "Vexmar", "Tilda", "Ombra", "Brannoc", "Sefira",
	"Ruukan", "Neshka", "Dorrin", "Halvar", "Imeria", "Quillo", "Zantha", "Pellow", "Gobrik", "Lunara", "Moskar",
	"Nerith", "Orlana", "Pashka", "Rokkar", "Sylas", "Tuvoka", "Ulmara", "Varek", "Wenda", "Xillia", "Yorin",
	"Zebbek", "Aldor", "Brixel" }

-- The made-up raid: the party's five test members first, then a varied
-- rest (a tank and a healer per group, some hurt, some with dots).
local function RaidMember(i)
	if P.PREVIEW[i] then
		return P.PREVIEW[i]
	end
	local slot = (i - 1) % 5
	local role = slot == 0 and "TANK" or slot == 1 and "HEALER" or "DAMAGER"
	local health = ({ 1, 0.85, 0.6, 1, 0.4, 1, 0.92 })[i % 7 + 1]
	local dots = ({ {}, { "shield" }, {}, { "renew" }, { "shield", "renew" } })[i % 5 + 1]
	return { name = NAMES[(i - 6) % #NAMES + 1], class = CLASSES[i % #CLASSES + 1], role = role, health = health, dots = dots }
end

local previews = {}
local PET_NAMES = { "Stitches", "Gobnip", "Fangor", "Imp", "Snarla", "Voidy", "Claw", "Grimm" }
local petPreviews = {}
local petHolder = CreateFrame("Frame", nil, block)
petHolder:SetScale(P.PET_SCALE)
petHolder:SetSize(0.1, 0.1)
petHolder:Hide()
local groupBoxes, petBoxes = {}, {}

-- count 10, 25 or 40 shows that many; nil ends the test.
function ns.RaidTest(count)
	if count and InCombatLockdown() then
		return false
	end
	if count and not testing then
		for _, header in ipairs(headers) do
			UnregisterStateDriver(header, "visibility")
			header:Hide()
		end
		UnregisterStateDriver(pets, "visibility")
		pets:Hide()
	elseif not count and testing then
		for _, header in ipairs(headers) do
			RegisterStateDriver(header, "visibility", VISIBILITY)
		end
		ApplyPets()
	end
	testing = count and true or false
	testCount = count
	if count then
		ApplyLayout(count)
	else
		ApplyScale()
	end
	-- Laid out as the layout lays the real raid: a box per group standing
	-- in for its header, the members chained in it, the boxes chained as
	-- the headers are.
	local layout = RaidLayout(currentSize)
	local point, dx, dy = layout.member[1], layout.member[2], layout.member[3]
	for _, box in ipairs(groupBoxes) do
		box:Hide()
	end
	local lastBox
	for group = 1, count and math.ceil(count / 5) or 0 do
		local box = groupBoxes[group]
		if not box then
			box = CreateFrame("Frame", nil, block)
			groupBoxes[group] = box
		end
		local members = {}
		for i = (group - 1) * 5 + 1, math.min(group * 5, count) do
			if not previews[i] then
				previews[i] = ns.PaintPreview(block, RaidMember(i))
			end
			members[#members + 1] = previews[i]
		end
		box:SetSize(ns.ChainSize(#members, point, dx, dy))
		box:ClearAllPoints()
		if group == 1 then
			box:SetPoint(layout.first[1], block, layout.first[2])
		else
			box:SetPoint(layout.chain[1], groupBoxes[group - 1], layout.chain[2], layout.chain[3], layout.chain[4])
		end
		box:Show()
		ns.ChainFrames(box, members, point, dx, dy)
		lastBox = box
	end
	for i = (count or 0) + 1, 40 do
		if previews[i] then
			previews[i]:Hide()
		end
	end

	-- With raid pets on for this size, a pet for each made-up hunter and
	-- warlock, in a grid of 5 as the raid's pet header lays them out.
	for _, frame in pairs(petPreviews) do
		frame:Hide()
	end
	for _, box in ipairs(petBoxes) do
		box:Hide()
	end
	local shown = {}
	if count and db and db.raidPetsBySize[currentSize] then
		for i = 1, count do
			local member = RaidMember(i)
			if member.class == "HUNTER" or member.class == "WARLOCK" then
				local key = #shown + 1
				petPreviews[key] = petPreviews[key] or ns.PaintPreview(petHolder,
					{ name = PET_NAMES[(key - 1) % #PET_NAMES + 1], pet = true, health = 1 })
				shown[key] = petPreviews[key]
			end
		end
	end
	local p = layout.pets
	petHolder:ClearAllPoints()
	if lastBox then
		petHolder:SetPoint(p[1], lastBox, p[2], p[3] / P.PET_SCALE, p[4] / P.PET_SCALE)
	end
	petHolder:SetShown(#shown > 0 and lastBox ~= nil)
	for chunk = 1, math.ceil(#shown / 5) do
		local box = petBoxes[chunk]
		if not box then
			box = CreateFrame("Frame", nil, petHolder)
			petBoxes[chunk] = box
		end
		local list = {}
		for i = (chunk - 1) * 5 + 1, math.min(chunk * 5, #shown) do
			list[#list + 1] = shown[i]
		end
		box:SetSize(ns.ChainSize(#list, point, dx, dy))
		box:ClearAllPoints()
		if chunk == 1 then
			box:SetPoint(p[1], petHolder, p[1])
		else
			local spacing = p[6]
			local ox = (p[5] == "LEFT" and spacing) or (p[5] == "RIGHT" and -spacing) or 0
			local oy = (p[5] == "TOP" and -spacing) or (p[5] == "BOTTOM" and spacing) or 0
			box:SetPoint(p[1], petBoxes[chunk - 1], p[2], ox, oy)
		end
		box:Show()
		ns.ChainFrames(box, list, point, dx, dy)
	end
	return true
end

-- After a setting changed (Options.lua): the raid's size and pets, now
-- or when combat ends. A running test shows its own size.
function ns.RaidApplySettings()
	if testing then
		ns.RaidTest(testCount) -- the test takes the new layout and size
		return true
	end
	ApplyScale()
	ApplyPets()
	return not InCombatLockdown()
end

function ns.RaidDefaultScale(size)
	for _, s in ipairs(SIZES) do
		if s[1] == size then
			return s[2]
		end
	end
end

function ns.RaidTesting()
	return testing
end

------------------------------------------------------------------------------
-- Login and events
------------------------------------------------------------------------------

function ns.RaidLogin(saved)
	db = saved
	db.raidLayouts = db.raidLayouts or {}
	-- Raid pets per size; the one setting from before goes to all three.
	if not db.raidPetsBySize then
		db.raidPetsBySize = {}
		for _, size in ipairs(SIZES) do
			db.raidPetsBySize[size[1]] = db.raidPets or false
		end
		db.raidPets = nil
	end
	-- One place per size; a place saved before sizes had their own goes
	-- to all three.
	if not db.raidPoints then
		db.raidPoints = {}
		if db.raidPoint then
			for _, size in ipairs(SIZES) do
				db.raidPoints[size[1]] = { db.raidPoint[1], db.raidPoint[2], db.raidPoint[3] }
			end
		end
		db.raidPoint = nil
	end
	HideBlizzardRaid()
	ApplyScale()
	for _, header in ipairs(headers) do
		RegisterStateDriver(header, "visibility", VISIBILITY)
	end
	ApplyPets()
end

local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
	if event == "GROUP_ROSTER_UPDATE" then
		if not testing then
			ApplyScale()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingScale and not testing then
			ApplyScale()
		end
		if petsPending and not testing then
			ApplyPets()
		end
	elseif event == "ADDON_LOADED" and name == "Blizzard_CompactRaidFrames" and db then
		HideBlizzardRaid()
	end
end)

ns.Raid = { groupBoxes = groupBoxes, petBoxes = petBoxes, petPreviews = petPreviews, petHolder = petHolder, anchor = anchor, block = block, headers = headers, pets = pets, previews = previews, ScaleFor = ScaleFor, label = label,
	ROW_GAP = ROW_GAP, VISIBILITY = VISIBILITY }
