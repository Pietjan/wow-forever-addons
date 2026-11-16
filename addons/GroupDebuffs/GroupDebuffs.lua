-- GroupDebuffs: the debuffs the classes in your group should keep on the
-- target (Sunder Armor with a warrior, Scorpid Sting with a hunter, ...), as
-- a column of icons: dim while the debuff is missing, lit with its timer and
-- stacks while it is on, whoever cast it.
--
-- How, within Forever's rules: in combat an addon may not know whether a
-- debuff is on the target, but the game's aura container (see TargetDebuffs)
-- may show it. So every debuff gets a cell of our own holding a dim copy of
-- its icon, and on top of that a container with room for one button,
-- filtered to that debuff's spell IDs (Data.lua). Blizzard's secure code
-- shows the button while the debuff is there and hides it when it is not;
-- the dim icon underneath is all that is left then. This file never learns
-- which of the two is showing, so there is no sound or glow for a missing
-- debuff: only what you see.
--
-- Spell-ID filters are honoured for harmful auras on units you cannot
-- assist (AuraContainerUtil.CanApplyIdentityCandidateFilters), so the column
-- only shows while you have a target you can attack.
--
-- Which debuffs: the slots in Data.lua. A slot is one job (lower the
-- target's chance to hit, say) and the debuffs that do it, each tied to a
-- class: Scorpid Sting from a hunter, Insect Swarm from a druid. It shows
-- when one of those classes is in your party or raid (you count; a pet's
-- debuff also needs a pet of the right family out) and the slot is switched
-- on, and lights up for whichever of its debuffs is on the
-- target. A paladin keeps up one judgement and a warlock one curse, so only
-- as many of those slots show as there are paladins or warlocks. Intent is unknowable, so the choice is yours:
-- /groupdebuffs list, /groupdebuffs on <name>, /groupdebuffs off <name>.
--
-- No mouse interaction, as in TargetDebuffs. /groupdebuffs unlocks a square
-- to drag (the column hangs from it and previews without a target),
-- /groupdebuffs again locks it, /groupdebuffs reset puts it back.
--
-- /groupdebuffs test shows every slot whatever your group is, to look at
-- the column, and every few seconds swaps which half of them are "lit". That
-- lit icon is a stand-in of our own: the real one is the game's button and
-- only a real debuff brings it up, so test mode shows the looks and proves
-- nothing about the filter.
--
-- The same settings are in the game's options window (Options > AddOns >
-- GroupDebuffs, or /groupdebuffs options): column or row, unlock, test
-- mode, reset, and a check box per slot.

local ADDON_NAME, ns = ...

local ICON = 30
local SPACING = 3
local DIM_ALPHA = 0.35
local ICON_OUTSET = 0.5 -- the picture reaches this far under the border ring, so it fills the frame
local RING_REACH = { 6, 5 } -- the ring's reach past a 30 px icon, as the Cooldown Manager sizes it
local DEFAULT_POINT = { "CENTER", 0, -180 }

local TEST_PERIOD = 2 -- seconds between swaps of the lit half in test mode
local DEFAULT_LAYOUT = "column"
local CLASS_NAMES = {
	WARRIOR = "warrior", ROGUE = "rogue", DRUID = "druid", HUNTER = "hunter", WARLOCK = "warlock",
	PALADIN = "paladin", PRIEST = "priest", MAGE = "mage", SHAMAN = "shaman",
}

local db
local unlocked = false
local testing = false
local testPhase = 0
local testTicker

local function Print(text, ...)
	print("|cff33ff99GroupDebuffs|r: " .. text:format(...))
end

------------------------------------------------------------------------------
-- The anchor
------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "GroupDebuffsAnchor", UIParent)
anchor:SetSize(ICON, ICON)
anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3])
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)

-- What you drag while unlocked: a green block over the anchor that sticks
-- out above the column, since the first icon covers the anchor itself. The anchor's
-- mouse area is stretched upwards to match it.
local HANDLE_RISE = 16
local handle = anchor:CreateTexture(nil, "BACKGROUND")
handle:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, HANDLE_RISE)
handle:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
handle:SetColorTexture(0.1, 0.8, 0.2, 0.8)
handle:Hide()
anchor:SetHitRectInsets(0, 0, -HANDLE_RISE, 0)

local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", handle, "TOP", 0, 4)
label:SetText("GroupDebuffs: drag to move, /groupdebuffs to lock")
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
-- The cells
------------------------------------------------------------------------------

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- The Cooldown Manager's own icon dressing, as CooldownNag and BuffNag wear
-- it: its rounded mask on the pictures and its border ring over them
-- (CooldownViewerBuffIconItemTemplate). A plain dark edge stands in on a
-- client without those atlases.
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

-- Called by the container for the button it creates, before it locks the
-- button down. The regions must be children of the button.
local function InitButton(button)
	button:SetSize(ICON, ICON)
	button:EnableMouse(false)

	local icon = Picture(button, "ARTWORK")
	-- Dressed before the icon is handed over. Should the game object to a
	-- mask on a button of its own, the icon stays square.
	pcall(Dress, button, icon)
	button:SetIcon(icon)

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", 3, -1)
	button:SetApplicationCount(count) -- shown from two stacks up

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:Show() -- the template starts hidden; without a duration it draws nothing
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(true)
	cooldown:EnableMouse(false)
	-- The Cooldown Manager's rounded swipe, to match the mask.
	pcall(cooldown.SetSwipeTexture, cooldown, "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.7)
	button:SetDurationCooldown(cooldown) -- swipe plus the game's own countdown numbers
end

local function SpellIcon(spellID)
	local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
	return ok and texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- All cells are made at load, shown or hidden later: only frames of our own
-- are touched after that.
local cells = {}
for index, debuff in ipairs(ns.DEBUFFS) do
	local cell = CreateFrame("Frame", nil, anchor)
	cell:SetSize(ICON, ICON)
	cell:Hide()

	local dim = Picture(cell, "ARTWORK")
	dim:SetDesaturated(true)
	dim:SetAlpha(DIM_ALPHA)
	cell.dim = dim -- its icon is set in Refresh: that of the class that is here

	-- Test mode's stand-in for the game's lit button.
	local lit = Picture(cell, "ARTWORK")
	lit:SetDrawLayer("ARTWORK", 1) -- over the dim one
	lit:Hide()
	cell.lit = lit
	Dress(cell, dim, lit)

	local include = {}
	for _, id in ipairs(debuff.ids) do
		include[id] = true
	end

	-- A child of the cell, so it shows, hides and moves with it.
	local container = CreateFrame("AuraContainer", nil, cell, "CustomAuraContainerTemplate")
	container:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
	container:SetFlowLayoutMaximumLineSize(ICON)
	container:SetUnit("target")
	container:AddAuraGroup("Debuff", "HARMFUL", {
		maxFrameCount = 1,
		initializeFrame = InitButton,
		candidateFilters = { includeSpellIDs = include },
		layout = {
			elementSpacing = 0,
			lineSpacing = 0,
			groupLineSpacing = 0,
			elementWidth = ICON,
			elementHeight = ICON,
		},
	})

	cell.container = container
	cells[index] = cell
end

------------------------------------------------------------------------------
-- Which cells show
------------------------------------------------------------------------------

-- Who is in the group: the classes, the families of the hunters' pets
-- (Demoralizing Screech needs a carrion bird, Dust Cloud a tallstrider) and
-- who they are, for their talents further down. The game may keep such
-- things to itself in combat, so this is a snapshot taken out of combat and
-- kept through the fight: someone who joins or swaps pets mid-fight counts
-- from the end of it.
local group = { classes = {}, pets = {}, members = {}, talents = {}, unknown = {}, count = {} }
local snapshotTaken = false

-- Talents. A debuff that takes a talent (Insect Swarm, Vampiric Embrace)
-- counts for a player who has it. Your own are asked of the spellbook;
-- another player's come from inspecting them: NotifyInspect, then, on
-- INSPECT_READY, a walk through their talent tree. One player at a time,
-- out of combat, within inspect range, and never while you have the
-- inspect window open yourself. Until a player's talents are known they
-- get the benefit of the doubt: the class alone decides, as before.
local TALENT_STALE = 600 -- seconds after which a player is inspected again (a respec)
local INSPECT_GAP = 1.5 -- between two inspections
local INSPECT_TIMEOUT = 5 -- without an answer, move on
local INSPECT_RETRY = 30 -- look again for players that were out of reach

local talentSpells = {} -- every talent a slot asks for, as the tree names it
local talentRanks = {} -- class -> tree spell -> the ranks a player can know
local talentsOf = {} -- player GUID -> { at = time, spells = { [tree spell] = true } }
for _, debuff in ipairs(ns.DEBUFFS) do
	for _, source in ipairs(debuff.sources) do
		if source.talents then
			talentRanks[source.class] = talentRanks[source.class] or {}
			for _, spell in ipairs(source.talents) do
				talentSpells[spell] = true
				talentRanks[source.class][spell] = source.talentRanks
			end
		end
	end
end

-- Your own talents, from the spells you know.
local function OwnTalents(class)
	local known = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell
	if not known or not talentRanks[class] then
		return nil
	end
	local spells = {}
	for spell, ranks in pairs(talentRanks[class]) do
		for _, rank in ipairs(ranks) do
			local ok, has = pcall(known, rank)
			if ok and has == true then
				spells[spell] = true
			end
		end
	end
	return spells
end

-- The talents of the player the game has just finished inspecting, or nil
-- when it will not say.
local function InspectedTalents()
	local spells = {}
	local ok = pcall(function()
		assert(C_Traits.HasValidInspectData())
		local configID = Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
		for _, treeID in ipairs(C_Traits.GetConfigInfo(configID).treeIDs) do
			for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
				local node = C_Traits.GetNodeInfo(configID, nodeID)
				if node and node.activeEntry and node.activeRank > 0 then
					local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
					local definition = C_Traits.GetDefinitionInfo(entry.definitionID)
					if definition.spellID and talentSpells[definition.spellID] then
						spells[definition.spellID] = true
					end
				end
			end
		end
	end)
	return ok and spells or nil
end

-- Per class: the talents its members here are known to have, and whether
-- one of them is still unknown.
local function CountTalents()
	group.talents, group.unknown = {}, {}
	for _, member in ipairs(group.members) do
		if talentRanks[member.class] then
			local known = member.guid and talentsOf[member.guid]
			if known then
				group.talents[member.class] = group.talents[member.class] or {}
				for spell in pairs(known.spells) do
					group.talents[member.class][spell] = true
				end
			else
				group.unknown[member.class] = true
			end
		end
	end
end

local function AddUnit(snapshot, unit, petUnit)
	local member = { unit = unit }
	pcall(function()
		local _, class = UnitClass(unit)
		if type(class) == "string" then
			member.class = class
			snapshot.classes[class] = true
		end
	end)
	pcall(function()
		local guid = UnitGUID(unit)
		if type(guid) == "string" then
			member.guid = guid
		end
	end)
	pcall(function()
		local name = UnitName(unit)
		if type(name) == "string" then
			member.name = name
		end
	end)
	pcall(function()
		local _, family = UnitCreatureFamily(petUnit)
		if type(family) == "number" then
			snapshot.pets[family] = true
		end
	end)
	if member.class then
		snapshot.members[#snapshot.members + 1] = member
	end
	return member
end

local ScheduleInspect -- defined with the inspecting, below

local function TakeSnapshot()
	-- In combat only when there is nothing to go on yet (a /reload in combat).
	if InCombatLockdown() and snapshotTaken then
		return
	end
	local snapshot = { classes = {}, pets = {}, members = {}, talents = {}, unknown = {}, count = {} }
	local me = AddUnit(snapshot, "player", "pet")
	if me.guid and me.class then
		local own = OwnTalents(me.class)
		if own then
			talentsOf[me.guid] = { at = GetTime(), spells = own }
		end
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			local ok, isMe = pcall(UnitIsUnit, unit, "player")
			if not (ok and isMe == true) then
				AddUnit(snapshot, unit, "raidpet" .. i)
			end
		end
	else
		for i = 1, 4 do
			AddUnit(snapshot, "party" .. i, "partypet" .. i)
		end
	end
	for _, member in ipairs(snapshot.members) do
		snapshot.count[member.class] = (snapshot.count[member.class] or 0) + 1
	end
	group = snapshot
	snapshotTaken = true
	CountTalents()
	ScheduleInspect(0.5)
end

-- Whether there is a target to keep debuffs on. If the game will not say,
-- show the column rather than hide it.
local function HasEnemyTarget()
	local ok, enemy = pcall(function()
		if UnitExists("target") and UnitCanAttack("player", "target") then
			return true
		end
		return false
	end)
	return not ok or enemy
end

-- The first of a slot's debuffs that someone in the group brings: its class
-- is here and, for a pet's debuff, a pet of that family; for one that takes
-- a talent, a player of that class who has it or is still unknown.
local function Brings(source)
	if not group.classes[source.class] or (source.pet and not group.pets[source.pet]) then
		return false
	end
	if not source.talents or group.unknown[source.class] then
		return true
	end
	local have = group.talents[source.class]
	for _, spell in ipairs(source.talents) do
		if have and have[spell] then
			return true
		end
	end
	return false
end

local function PresentSource(debuff)
	for _, source in ipairs(debuff.sources) do
		if Brings(source) then
			return source
		end
	end
end

-- Your own choice for a slot, or else the catalogue's default.
local function Enabled(debuff)
	local choice = db.enabled[debuff.name]
	if choice == nil then
		return debuff.on
	end
	return choice
end

local function Refresh()
	if not db then
		return
	end
	local showRow = unlocked or testing or HasEnemyTarget()
	local shown = {}
	local taken = {} -- class -> how many of its one-each slots show already
	for index, debuff in ipairs(ns.DEBUFFS) do
		local cell = cells[index]
		local source = PresentSource(debuff) or (testing and debuff.sources[1])
		local show = showRow and source and (testing or Enabled(debuff))
		-- A paladin keeps up one judgement, a warlock one curse: no more of
		-- these slots than there are such players, the first ones that are
		-- switched on.
		if show and debuff.each and not testing then
			taken[debuff.each] = (taken[debuff.each] or 0) + 1
			show = taken[debuff.each] <= (group.count[debuff.each] or 0)
		end
		if show then
			local icon = SpellIcon(source.icon)
			cell.dim:SetTexture(icon)
			cell.lit:SetTexture(icon)
			cell.lit:SetShown(testing and (index + testPhase) % 2 == 0)
			shown[#shown + 1] = cell
		else
			cell:Hide()
		end
	end
	if db.layout == "row" then
		-- Centred on the anchor: the number of cells is ours to know.
		local width = #shown * ICON + math.max(#shown - 1, 0) * SPACING
		for i, cell in ipairs(shown) do
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", anchor, "TOP", (i - 1) * (ICON + SPACING) - width / 2, 0)
			cell:Show()
		end
	else
		-- A column hanging from the anchor, first slot at the top.
		for i, cell in ipairs(shown) do
			cell:ClearAllPoints()
			cell:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (ICON + SPACING))
			cell:Show()
		end
	end
end

-- A new unit under the same token: ask every container for a full refresh,
-- as its own notes say to do; it does not listen for this itself.
local function RefreshAuras()
	for _, cell in ipairs(cells) do
		cell.container:UpdateAllAuras()
	end
end

------------------------------------------------------------------------------
-- Inspecting group members for their talents
------------------------------------------------------------------------------

local pendingGUID -- whose answer we are waiting for
local inspectTurn = 0 -- a newer schedule cancels an older one

local function InspectWindowOpen()
	return InspectFrame and InspectFrame:IsShown() and true or false
end

-- The next member whose talents matter and are unknown or old, and who has
-- not been tried this round.
local function InspectNext()
	pendingGUID = nil
	if InCombatLockdown() or InspectWindowOpen() then
		return -- the next snapshot (end of combat, a change of group) starts again
	end
	local now = GetTime()
	local waiting = false
	for _, member in ipairs(group.members) do
		local known = member.guid and talentsOf[member.guid]
		if member.unit ~= "player" and member.guid and talentRanks[member.class] and (not known or now - known.at > TALENT_STALE) then
			waiting = true
			if not member.tried then
				member.tried = true
				local ok, can = pcall(CanInspect, member.unit)
				if ok and can == true then
					pendingGUID = member.guid
					pcall(NotifyInspect, member.unit)
					ScheduleInspect(INSPECT_TIMEOUT)
					return
				end
			end
		end
	end
	if waiting then
		-- Out of reach for now: go round again later.
		for _, member in ipairs(group.members) do
			member.tried = nil
		end
		ScheduleInspect(INSPECT_RETRY)
	end
end

function ScheduleInspect(delay)
	inspectTurn = inspectTurn + 1
	local turn = inspectTurn
	C_Timer.After(delay, function()
		if turn == inspectTurn then
			InspectNext()
		end
	end)
end

-- Ours or one you asked for yourself: either way the answer is worth having.
local function OnInspectReady(guid)
	local ours = pendingGUID ~= nil and guid == pendingGUID
	for _, member in ipairs(group.members) do
		if member.guid == guid and talentRanks[member.class] and member.unit ~= "player" then
			local spells = InspectedTalents()
			if spells then
				talentsOf[guid] = { at = GetTime(), spells = spells }
				CountTalents()
			end
			break
		end
	end
	if ours then
		if ClearInspectPlayer and not InspectWindowOpen() then
			pcall(ClearInspectPlayer)
		end
		ScheduleInspect(INSPECT_GAP)
	end
end

------------------------------------------------------------------------------
-- What the slash command and the options window both do
------------------------------------------------------------------------------

local function SetUnlocked(value)
	unlocked = value and true or false
	handle:SetShown(unlocked)
	label:SetShown(unlocked)
	anchor:EnableMouse(unlocked)
	Refresh()
end

local function SetTesting(value)
	testing = value and true or false
	if testTicker then
		testTicker:Cancel()
		testTicker = nil
	end
	if testing then
		testTicker = C_Timer.NewTicker(TEST_PERIOD, function()
			testPhase = 1 - testPhase
			Refresh()
		end)
	end
	Refresh()
end

local function ResetPosition()
	db.point = { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
	ApplyPosition()
end

local function SetLayout(layout)
	db.layout = layout == "row" and "row" or "column"
	Refresh()
end

local function SetEnabled(debuff, value)
	db.enabled[debuff.name] = value and true or false
	Refresh()
end

------------------------------------------------------------------------------
-- The game's options window (Options > AddOns). Optional: without the
-- game's settings API the slash command still does everything.
------------------------------------------------------------------------------

local settingsCategory

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.CreateDropdown and Settings.CreateControlTextContainer
		and Settings.RegisterInitializer and CreateSettingsButtonInitializer) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("GroupDebuffs")

	local function Checkbox(key, name, tooltip, default, get, set)
		local setting = Settings.RegisterProxySetting(category, "GroupDebuffs_" .. key, Settings.VarType.Boolean, name, default, get, set)
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	local function Layouts()
		local container = Settings.CreateControlTextContainer()
		container:Add("column", "Column", "Slots under each other, hanging from the place you dragged to.")
		container:Add("row", "Row", "Slots side by side, centred on the place you dragged to.")
		return container:GetData()
	end
	Settings.CreateDropdown(category, Settings.RegisterProxySetting(category, "GroupDebuffs_layout", Settings.VarType.String,
		"Layout", DEFAULT_LAYOUT, function() return db.layout end, SetLayout), Layouts)

	Checkbox("unlocked", "Unlock to move", "Shows a green block to drag, and the slots without a target. Untick to lock.",
		false, function() return unlocked end, SetUnlocked)
	Checkbox("testing", "Test mode",
		"Shows every slot whatever your group is, and swaps which half look lit. The lit icon is a stand-in: it shows the looks, not that a debuff is on.",
		false, function() return testing end, SetTesting)
	Settings.RegisterInitializer(category, CreateSettingsButtonInitializer("Position", "Reset", ResetPosition,
		"Back to under the middle of the screen.", true))

	-- One check box per slot, in the catalogue's order (by class).
	for index, debuff in ipairs(ns.DEBUFFS) do
		local classes = {}
		for _, source in ipairs(debuff.sources) do
			local who = CLASS_NAMES[source.class] or source.class:lower()
			if source.petName then
				who = ("%s with a %s"):format(who, source.petName:lower())
			elseif source.talentName then
				who = ("%s with the talent"):format(who)
			end
			classes[#classes + 1] = ("%s (%s)"):format(source.name, who)
		end
		local tooltip = "Shown with: " .. table.concat(classes, ", ") .. "."
		if debuff.each then
			tooltip = tooltip .. (" One such slot per %s in the group, the first ones that are ticked."):format(CLASS_NAMES[debuff.each] or debuff.each:lower())
		end
		Checkbox("slot" .. index, debuff.name, tooltip,
			debuff.on, function() return Enabled(debuff) end, function(value) SetEnabled(debuff, value) end)
	end

	Settings.RegisterAddOnCategory(category)
	settingsCategory = category
end

------------------------------------------------------------------------------
-- Events and the slash command
------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("INSPECT_READY")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" then
		if arg ~= ADDON_NAME then
			return
		end
		GroupDebuffsDB = GroupDebuffsDB or {}
		db = GroupDebuffsDB
		db.point = db.point or { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
		db.enabled = db.enabled or {} -- only the debuffs you switched yourself
		db.layout = db.layout or DEFAULT_LAYOUT
		ApplyPosition()
		local ok, err = pcall(RegisterSettings)
		if not ok then
			Print("options panel unavailable (%s); use /groupdebuffs instead", tostring(err))
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		RefreshAuras()
	elseif event == "INSPECT_READY" then
		OnInspectReady(arg)
	else
		-- Into the world, a change of group or pet, or the end of a fight.
		TakeSnapshot()
	end
	Refresh()
end)

local function FindDebuff(text)
	text = text:lower()
	for _, debuff in ipairs(ns.DEBUFFS) do
		if debuff.name:lower() == text then
			return debuff
		end
		for _, source in ipairs(debuff.sources) do
			if source.name:lower() == text then
				return debuff
			end
		end
	end
end

SLASH_GROUPDEBUFFS1 = "/groupdebuffs"
SlashCmdList.GROUPDEBUFFS = function(msg)
	local word, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	word = word:lower()
	if word == "" then
		SetUnlocked(not unlocked)
	elseif word == "options" then
		if settingsCategory and Settings.OpenToCategory then
			Settings.OpenToCategory(settingsCategory:GetID())
		else
			Print("no options window here; /groupdebuffs help lists the commands")
		end
	elseif word == "test" then
		SetTesting(not testing)
		if testing then
			Print("test mode on: every slot, the lit ones are a stand-in. /groupdebuffs test to leave")
		else
			Print("test mode off")
		end
	elseif word == "column" or word == "row" then
		SetLayout(word)
	elseif word == "reset" then
		ResetPosition()
	elseif word == "list" then
		for _, debuff in ipairs(ns.DEBUFFS) do
			Print("%s: %s%s", debuff.name, Enabled(debuff) and "on" or "off",
				PresentSource(debuff) and "" or ", nobody in the group brings it")
		end
		for _, member in ipairs(group.members) do
			if talentRanks[member.class] then
				Print("talents of %s (%s): %s", member.name or member.unit, CLASS_NAMES[member.class] or member.class,
					member.guid and talentsOf[member.guid] and "read" or "not read yet, counted as having them")
			end
		end
	elseif word == "on" or word == "off" then
		local debuff = FindDebuff(rest)
		if not debuff then
			Print("no debuff named \"%s\"; /groupdebuffs list shows the names", rest)
			return
		end
		SetEnabled(debuff, word == "on")
		Print("%s: %s", debuff.name, word)
	else
		Print("/groupdebuffs unlocks or locks; /groupdebuffs options; /groupdebuffs column|row; /groupdebuffs list; /groupdebuffs on|off <name>; /groupdebuffs test; /groupdebuffs reset")
	end
end
