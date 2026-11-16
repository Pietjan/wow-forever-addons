-- TargetDebuffs: the debuffs you (or your pet) put on your target, as a
-- free-standing row of icons.
--
-- How, within Forever's rules: the same aura container PetAuras uses
-- (Blizzard_AuraContainer: the AuraContainer intrinsic with
-- CustomAuraContainerTemplate). Blizzard's secure code reads the target's
-- auras, keeps the ones that pass the "HARMFUL|PLAYER" filter, sorts, lays
-- out and shows the buttons; this file only hands it the regions to draw
-- into and never sees aura data, so nothing here can trip over a secret
-- value in combat.
--
-- No mouse interaction: every button has its mouse switched off as it is
-- created, so there are no tooltips and clicks go through to the world.
--
-- Moving: the container's size is secret and nothing of ours may be
-- anchored to it, so it hangs from a frame of our own instead, by its top
-- centre. The container resizes itself to the icons it shows after every
-- layout, so the game keeps the row centred on that anchor; a second row
-- starts at the left edge of the first. The anchor is invisible and ignores
-- the mouse until /targetdebuffs unlocks it, which shows a square the size of
-- one icon to drag. /targetdebuffs again locks it.

local ADDON_NAME = ...

local ICON = 30
local SPACING = 3
local PER_ROW = 8
local MAX_DEBUFFS = 16 -- MAX_TARGET_DEBUFFS
local DEFAULT_POINT = { "CENTER", 0, -140 }

local db

------------------------------------------------------------------------------
-- The anchor
------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "TargetDebuffsAnchor", UIParent)
anchor:SetSize(ICON, ICON)
anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3])
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)

local handle = anchor:CreateTexture(nil, "BACKGROUND")
handle:SetAllPoints()
handle:SetColorTexture(0.1, 0.8, 0.2, 0.6)
handle:Hide()

local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
label:SetText("TargetDebuffs: drag to move, /targetdebuffs to lock")
label:Hide()

local function ApplyPosition()
	local point = db.point
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[1], point[2], point[3])
end

local function SetUnlocked(unlocked)
	handle:SetShown(unlocked)
	label:SetShown(unlocked)
	anchor:EnableMouse(unlocked)
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
-- The row
------------------------------------------------------------------------------

-- Called by the container for every button it creates, before it locks the
-- button down. The regions must be children of the button. The looks are
-- the game's own for a debuff: a square icon inside the UI-Debuff-Overlays
-- border, coloured by dispel type.
local function InitButton(button)
	button:SetSize(ICON, ICON)
	button:EnableMouse(false)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button:SetIcon(icon)

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", 3, -1)
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
	cooldown:EnableMouse(false)
	button:SetDurationCooldown(cooldown) -- swipe plus the game's own countdown numbers
end

local container = CreateFrame("AuraContainer", "TargetDebuffsContainer", anchor, "CustomAuraContainerTemplate")
container:SetPoint("TOP", anchor, "TOP", 0, 0)
container:SetFlowLayoutMaximumLineSize(PER_ROW * ICON + (PER_ROW - 1) * SPACING)
container:SetUnit("target")
container:AddAuraGroup("Mine", "HARMFUL|PLAYER", {
	maxFrameCount = MAX_DEBUFFS,
	initializeFrame = InitButton,
	layout = {
		elementSpacing = SPACING,
		lineSpacing = SPACING,
		groupLineSpacing = SPACING,
		elementWidth = ICON,
		elementHeight = ICON,
	},
})

------------------------------------------------------------------------------
-- Events and the slash command
------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
-- A new unit under the same token: ask for a full refresh, as the
-- container's own notes say to do; it does not listen for this itself.
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "PLAYER_TARGET_CHANGED" then
		container:UpdateAllAuras()
	elseif arg == ADDON_NAME then
		TargetDebuffsDB = TargetDebuffsDB or {}
		db = TargetDebuffsDB
		db.point = db.point or { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
		ApplyPosition()
	end
end)

SLASH_TARGETDEBUFFS1 = "/targetdebuffs"
SlashCmdList.TARGETDEBUFFS = function(msg)
	if msg:lower():match("^%s*reset") then
		db.point = { DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3] }
		ApplyPosition()
		return
	end
	SetUnlocked(not handle:IsShown())
end
