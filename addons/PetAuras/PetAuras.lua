-- PetAuras: the pet's buffs and debuffs as small icons under the pet frame.
--
-- The pet frame has aura code of its own (PartyMemberAuraMixin in
-- Blizzard_UnitFrame): one row of at most four debuffs, 15 px, at 48,-42,
-- which is narrowed to the debuffs you can dispel while the showDispelDebuffs
-- CVar is on; buffs only exist in the tooltip of the frame. Turning that into
-- a full display would mean writing its fields (showBuffs) and the globals
-- MAX_PARTY_BUFFS/DEBUFFS, which taints the frame. So that row is hidden and
-- this addon puts its own in its place.
--
-- How, within Forever's rules: the game ships an aura container for addons
-- (Blizzard_AuraContainer: the AuraContainer intrinsic with
-- CustomAuraContainerTemplate, and CustomAuraButtonTemplate for its
-- buttons). The container reads the auras, sorts, lays out and shows the
-- buttons from Blizzard's own secure code; this file only hands it the
-- regions to draw into (icon, count, border, cooldown) and never sees aura
-- data, so nothing here can trip over a secret value in combat. Tooltips
-- come from the button intrinsic.
--
-- The container is a child of PetFrame, anchored to it: it moves with the
-- frame in Edit Mode, takes its scale, and hides with it when there is no
-- pet. No Blizzard field is written and no Blizzard function is called on
-- the frame; the one call on a Blizzard region is Hide() on the pet frame's
-- own debuff row.
--
-- Looks: the icon is the one the pet frame itself uses for its debuffs
-- (PartyAuraFrameTemplate: 15 px, 2 px apart, count in NumberFontNormalSmall,
-- the UI-Debuff-Overlays border coloured by dispel type, a reversed cooldown
-- swipe without numbers). The arrangement is the target frame's for a
-- friendly unit: buffs first, debuffs starting a new line, wrapping rows.

local ICON = 18 -- the game's party aura icons are 15; slightly larger here
local SPACING = 2 -- PetFrame.AuraFrameContainer
local PER_ROW = 4
local MAX_BUFFS = 32 -- MAX_TARGET_BUFFS
local MAX_DEBUFFS = 16 -- MAX_TARGET_DEBUFFS
local BAR_GAP = 8 -- between the pet's power bar and the first row
local OFFSET_X, OFFSET_Y = 48, -45 -- from the pet frame's top left, when there is no bar to hang from

local petFrame = PetFrame
if not petFrame then
	return
end

-- Called by the container for every button it creates, before it locks the
-- button down. The regions must be children of the button.
local function InitButton(button)
	button:SetSize(ICON, ICON)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button:SetIcon(icon)

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", 5, 0)
	button:SetApplicationCount(count) -- shown from two stacks up

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	button:AddDispelTypeTexture(border, {
		-- Keep the texture, colour it by dispel type: AuraUtil.SetAuraBorderColor.
		style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
		showWhenHarmful = true,
		showWhenHelpful = false,
		showWithoutDispelType = true,
	})

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:Show() -- the template starts hidden; without a duration it draws nothing
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(true)
	cooldown:SetHideCountdownNumbers(true)
	button:SetDurationCooldown(cooldown)
end

local function GroupOptions(maxFrameCount, newLine)
	return {
		maxFrameCount = maxFrameCount,
		initializeFrame = InitButton,
		layout = {
			elementSpacing = SPACING,
			lineSpacing = SPACING,
			groupLineSpacing = SPACING,
			forceNewLine = newLine,
			elementWidth = ICON,
			elementHeight = ICON,
		},
	}
end

local container = CreateFrame("AuraContainer", "PetAurasContainer", petFrame, "CustomAuraContainerTemplate")
-- Under the bars, starting at their left edge. The bar is only an anchor
-- here; without it the row falls back to an offset from the frame's corner.
local bar = _G.PetFrameManaBar
if bar then
	container:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -BAR_GAP)
else
	container:SetPoint("TOPLEFT", petFrame, "TOPLEFT", OFFSET_X, OFFSET_Y)
end
container:SetFlowLayoutMaximumLineSize(PER_ROW * ICON + (PER_ROW - 1) * SPACING)
container:SetUnit(petFrame.unit or "pet")
container:AddAuraGroup("Buffs", "HELPFUL", GroupOptions(MAX_BUFFS, false))
container:AddAuraGroup("Debuffs", "HARMFUL", GroupOptions(MAX_DEBUFFS, true))

local events = CreateFrame("Frame")

-- The pet frame's own debuff row would sit under ours and show the same
-- debuffs twice. Blizzard only ever shows the buttons in it, never the row
-- itself, so hiding it once holds. Should the row count as protected, wait
-- for the end of combat (only a /reload in combat gets here in combat).
local function HideOwnRow()
	local row = petFrame.AuraFrameContainer
	if not row then
		return
	end
	if InCombatLockdown() and row:IsProtected() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	row:Hide()
end
HideOwnRow()

-- The pet frame shows the player while in a vehicle; follow whatever unit it
-- is given.
hooksecurefunc("UnitFrame_SetUnit", function(frame, unit)
	if frame == petFrame and type(unit) == "string" then
		container:SetUnit(unit)
	end
end)

-- A new pet under the same unit token: ask for a full refresh, as the
-- container's own notes say to do when the unit behind a token changes.
events:RegisterUnitEvent("UNIT_PET", "player")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent(event)
		HideOwnRow()
	else
		container:UpdateAllAuras()
	end
end)
