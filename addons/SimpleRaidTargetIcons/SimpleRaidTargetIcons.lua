-- SimpleRaidTargetIcons: a radial menu of the eight raid target icons that
-- opens around the cursor when you modifier-click or double-click a unit.
-- Move the mouse towards an icon and click to set it, right-click to clear.
--
-- A rewrite of the 2.x addon by MrFIXlT and Zimzarina (concept by Qzot) for
-- WoW Forever's engine, with the same key binding names so existing binds
-- keep working.

local ADDON_NAME = ...

local ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local ICON_COLORS = { "ffff00", "ff8000", "ff00ff", "7cfc00", "c7c7cf", "00bfff", "ff4500", "ffffff" }
local ICON_WORDS = { -- what /srti accepts
	none = 0, clear = 0, remove = 0, off = 0,
	star = 1, yellow = 1, circle = 2, orange = 2, diamond = 3, purple = 3,
	triangle = 4, green = 4, moon = 5, silver = 5, square = 6, blue = 6,
	cross = 7, x = 7, red = 7, skull = 8, white = 8,
}

local DEFAULTS = {
	ctrl = true,         -- which modifiers + left click open the menu
	alt = false,
	shift = false,
	double = true,       -- double left click opens the menu
	doubleSpeed = 0.25,  -- seconds between the two clicks
	hoverSelect = false, -- pick an icon by resting the cursor on it
	hoverTime = 0.2,     -- seconds of rest before it is picked
	scale = 1.0,
	sounds = true,
}

-- Menu geometry, in the menu's own (scaled) pixels, measured from its centre.
local RADIUS, ICON_SIZE = 36, 18
local DEAD_ZONE = 18     -- closer than this: nothing selected
local SELECT_RADIUS = 50 -- up to here: the icon in that direction is selected
local LINGER_RADIUS = 60 -- beyond this the menu closes after LINGER_TIME
local CANCEL_RADIUS = 200 -- beyond this it closes at once
local LINGER_TIME = 0.75
local FADE_TIME = 0.1

local IsSecret = issecretvalue or function() return false end

local db
local SRTI = {}
_G.SRTI = SRTI

local function Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff9999ffSRTI|r " .. msg)
end

local function IconName(index)
	if index == 0 then
		return "no icon"
	end
	return ("|cff%s%s|r"):format(ICON_COLORS[index], ICON_NAMES[index])
end

local function Sound(kit)
	if db.sounds then
		PlaySound(kit, "SFX")
	end
end

-- Unit helpers. Values can be secret on this engine; treat those as unknown.

local function GUID(unit)
	local guid = UnitGUID(unit)
	if guid and not IsSecret(guid) then
		return guid
	end
end

local function MarkOf(unit)
	local index = GetRaidTargetIndex(unit)
	if IsSecret(index) then
		return nil
	end
	return index or 0
end

local function Exists(unit)
	return unit and UnitExists(unit)
end

local FIXED_UNITS = { "target", "mouseover", "focus", "softenemy", "softfriend", "softinteract" }

-- A unit token that currently refers to the unit with this GUID, or nil.
local function UnitByGUID(guid)
	if not guid then
		return nil
	end
	for _, unit in ipairs(FIXED_UNITS) do
		if Exists(unit) and GUID(unit) == guid then
			return unit
		end
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if Exists(unit) and GUID(unit) == guid then
			return unit
		end
	end
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		for _, unit in ipairs({ prefix .. i, prefix .. i .. "target" }) do
			if Exists(unit) and GUID(unit) == guid then
				return unit
			end
		end
	end
	return nil
end

local function CanMark()
	if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		Print("only the raid leader and assistants can set icons")
		return false
	end
	return true
end

-- Set (or with index 0 remove) the icon of the unit that was clicked. The unit
-- is found again by GUID because the token it had when the menu opened
-- ("mouseover" mostly) may point elsewhere by now.
function SRTI.SetMark(index, guid, fallbackUnit)
	local unit = UnitByGUID(guid) or (Exists(fallbackUnit) and fallbackUnit)
	if not unit then
		Print("that unit is no longer in view")
		return false
	end
	if not CanMark() then
		return false
	end
	local ok, err = pcall(SetRaidTarget, unit, index)
	if not ok then
		Print("could not set the icon: %s", tostring(err))
		return false
	end
	return true
end

-- Mark the unit under the cursor, else the target. Used by the key bindings
-- and the slash command.
function SRTI.MarkFromBinding(index)
	local unit = Exists("mouseover") and "mouseover" or Exists("target") and "target"
	if not unit then
		return
	end
	if index ~= 0 and MarkOf(unit) == index then
		index = 0 -- same icon again removes it, like the game's own menu
	end
	SRTI.SetMark(index, GUID(unit), unit)
end

------------------------------------------------------------------------------
-- The radial menu
------------------------------------------------------------------------------

local menu = CreateFrame("Button", "SRTIRadialMenu", UIParent)
menu:SetSize(2 * (RADIUS + ICON_SIZE), 2 * (RADIUS + ICON_SIZE))
menu:SetFrameStrata("DIALOG")
menu:SetClampedToScreen(true)
menu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
menu:Hide()

menu.backdrop = menu:CreateTexture(nil, "BACKGROUND")
menu.backdrop:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
menu.backdrop:SetVertexColor(0, 0, 0, 0.7)
menu.backdrop:SetSize(56, 56)
menu.backdrop:SetPoint("CENTER")

menu.portrait = menu:CreateTexture(nil, "BORDER")
menu.portrait:SetSize(40, 40)
menu.portrait:SetPoint("CENTER")
do
	local mask = menu:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(menu.portrait)
	menu.portrait:AddMaskTexture(mask)
end

-- Icon i sits at angle 90 - (i - 1) * 45 degrees: star on top, then clockwise.
local function IconAngle(index)
	return math.rad(90 - (index - 1) * 45)
end

menu.icons = {}
for i = 1, 8 do
	local icon = menu:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON_TEXTURE)
	SetRaidTargetIconTexture(icon, i)
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	menu.icons[i] = icon
end

-- A cross over the icon the unit already has: picking it removes the icon.
menu.remove = menu:CreateTexture(nil, "OVERLAY")
menu.remove:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
menu.remove:SetSize(ICON_SIZE, ICON_SIZE)
menu.remove:Hide()

-- Lay the icons out at a fraction (0..1) of their final distance and size.
local function Layout(progress)
	local radius = RADIUS * (0.45 + 0.55 * progress)
	local size = ICON_SIZE * (0.5 + 0.5 * progress)
	for i, icon in ipairs(menu.icons) do
		local angle = IconAngle(i)
		local scale = (i == menu.selected) and 1.4 or 1
		icon:SetPoint("CENTER", menu, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
		icon:SetSize(size * scale, size * scale)
		if i == menu.selected then
			icon:SetAlpha(1)
		else
			icon:SetAlpha(0.6)
		end
	end
	if menu.current and menu.current > 0 then
		local icon = menu.icons[menu.current]
		menu.remove:SetPoint("CENTER", icon)
		menu.remove:SetSize(icon:GetSize())
		menu.remove:Show()
	else
		menu.remove:Hide()
	end
end

local function CursorOffset()
	local x, y = GetCursorPosition()
	local scale = menu:GetEffectiveScale()
	local cx, cy = menu:GetCenter()
	return x / scale - cx, y / scale - cy
end

local function IndexAt(dx, dy)
	local degrees = math.deg(math.atan2(dy, dx))
	return math.floor((90 - degrees) / 45 + 0.5) % 8 + 1
end

local function Close(sound)
	if menu.state == "hiding" then
		return
	end
	menu.state = "hiding"
	menu.stateSince = GetTime()
	if sound then
		Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
end

function SRTI.Open(unit, hoverSelect)
	if not Exists(unit) then
		return
	end
	if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		return
	end
	menu.guid = GUID(unit)
	-- The click that opened the menu also targeted the unit, so "target" is
	-- the safer fallback than "mouseover", which follows the cursor.
	menu.fallbackUnit = (unit == "mouseover") and "target" or unit
	menu.current = MarkOf(unit)
	menu.selected = nil
	menu.selectedSince = nil
	menu.linger = nil
	menu.hoverSelect = hoverSelect
	menu.state = "showing"
	menu.stateSince = GetTime()

	SetPortraitTexture(menu.portrait, unit)
	menu:SetScale(db.scale)
	local x, y = GetCursorPosition()
	local scale = menu:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	menu:SetAlpha(0)
	Layout(0)
	menu:Show()
	Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

menu:SetScript("OnUpdate", function(self, elapsed)
	local now = GetTime()
	local progress = math.min((now - self.stateSince) / FADE_TIME, 1)

	if self.state == "hiding" then
		self:SetAlpha(1 - progress)
		Layout(1 - progress)
		if progress >= 1 then
			self:Hide()
		end
		return
	end

	if self.state == "showing" then
		self:SetAlpha(progress)
		if progress >= 1 then
			self.state = "open"
		end
	end

	-- The unit went away (died and despawned, left the group...).
	if not (UnitByGUID(self.guid) or Exists(self.fallbackUnit)) then
		Close(true)
		return
	end

	local dx, dy = CursorOffset()
	local dist = math.sqrt(dx * dx + dy * dy)
	local selected = self.selected
	if dist > CANCEL_RADIUS then
		Close(true)
		return
	elseif dist > LINGER_RADIUS then
		self.linger = self.linger or now
		if now - self.linger > LINGER_TIME then
			Close(true)
			return
		end
	else
		self.linger = nil
		if dist <= DEAD_ZONE then
			selected = nil
		elseif dist < SELECT_RADIUS then
			selected = IndexAt(dx, dy)
		end
	end

	if selected ~= self.selected then
		self.selected = selected
		self.selectedSince = now
	end
	Layout(self.state == "open" and 1 or progress)

	if self.hoverSelect and self.selected and now - self.selectedSince > db.hoverTime then
		self:Click("LeftButton")
	end
end)

menu:SetScript("OnClick", function(self, button)
	if self.state == "hiding" then
		return
	end
	local index
	if button == "RightButton" then
		index = 0
	elseif self.selected then
		index = (self.selected == self.current) and 0 or self.selected
	end
	if index then
		if index == 0 and self.current == 0 then
			Close(true)
			return
		end
		if SRTI.SetMark(index, self.guid, self.fallbackUnit) then
			Sound(index == 0 and SOUNDKIT.IG_MINIMAP_ZOOM_OUT or SOUNDKIT.IG_MINIMAP_ZOOM_IN)
		end
		Close(false)
	else
		Close(true)
	end
end)

menu:SetScript("OnHide", function(self)
	self.state = nil
	self.guid = nil
	self.fallbackUnit = nil
end)

------------------------------------------------------------------------------
-- Opening the menu: modifier-click or double-click on a unit
------------------------------------------------------------------------------

local function ModifierDown()
	if not (db.ctrl or db.alt or db.shift) then
		return false
	end
	return (db.ctrl and IsControlKeyDown()) or (db.alt and IsAltKeyDown()) or (db.shift and IsShiftKeyDown()) or false
end

local lastClick = { time = 0, x = 0, y = 0, guid = nil }

-- Called on every left click that lands on a unit: the unit's frame, its
-- model or its nameplate in the world.
local function UnitClicked(unit)
	if menu:IsShown() then
		return
	end
	local now = GetTime()
	local x, y = GetCursorPosition()
	local guid = GUID(unit)
	local double = db.double and now - lastClick.time < db.doubleSpeed
		and math.abs(x - lastClick.x) < 20 and math.abs(y - lastClick.y) < 20
		and (guid == nil or guid == lastClick.guid)
	lastClick.time, lastClick.x, lastClick.y, lastClick.guid = now, x, y, guid

	if ModifierDown() then
		lastClick.time = 0
		SRTI.Open(unit, db.hoverSelect)
	elseif double then
		lastClick.time = 0
		SRTI.Open(unit, db.hoverSelect)
	end
end

-- Clicks in the 3D world: models and nameplates. The unit under the cursor
-- is "mouseover" at that moment; a click on empty ground does nothing.
WorldFrame:HookScript("OnMouseUp", function(_, button)
	if button == "LeftButton" and Exists("mouseover") then
		UnitClicked("mouseover")
	end
end)

-- Clicks on unit frames: every Blizzard unit frame, and most addon ones,
-- is a secure unit button and routes its clicks through this function.
if type(SecureUnitButton_OnClick) == "function" then
	hooksecurefunc("SecureUnitButton_OnClick", function(self, button, down)
		if button ~= "LeftButton" then
			return
		end
		-- A frame may report the press, the release or both; act on the
		-- first report of each click.
		local now = GetTime()
		if down then
			self.srtiPressed = now
		elseif self.srtiPressed and now - self.srtiPressed < 1 then
			self.srtiPressed = nil
			return
		end
		local unit = SecureButton_GetModifiedUnit and SecureButton_GetModifiedUnit(self) or self:GetAttribute("unit")
		if Exists(unit) then
			UnitClicked(unit)
		end
	end)
end

function SRTI.ShowFromBinding()
	if not menu:IsShown() and Exists("target") then
		SRTI.Open("target", db.hoverSelect)
	end
end

------------------------------------------------------------------------------
-- Swipe marking: hold a key and move the cursor over enemies
------------------------------------------------------------------------------

-- Which icons each crowd-control class gets, in order of preference.
local CC_MARKS = {
	MAGE = { 5, 6, 2, 1 },
	WARLOCK = { 3, 6 },
	HUNTER = { 4, 6 },
	PRIEST = { 1, 2, 3 },
	DRUID = { 2, 4 },
	SHAMAN = { 6, 4 },
}

-- Which classes can crowd-control each creature type, best first.
local CC_CLASSES = {
	Humanoid = { "MAGE", "HUNTER", "WARLOCK", "PRIEST" },
	Giant = { "HUNTER", "WARLOCK" },
	Beast = { "MAGE", "HUNTER", "DRUID" },
	Dragonkin = { "HUNTER", "DRUID" },
	Demon = { "WARLOCK", "HUNTER" },
	Elemental = { "WARLOCK", "HUNTER" },
	Undead = { "PRIEST", "HUNTER" },
	Mechanical = { "HUNTER" },
}

local CC_IMMUNE = {
	["Gurubashi Champion"] = true, ["Gurubashi Berserker"] = true,
	["Ancient Core Hound"] = true, ["Firelord"] = true, ["Flameguard"] = true, ["Firewalker"] = true,
	["Death Talon Captain"] = true, ["Death Talon Wyrmguard"] = true, ["Death Talon Flamescale"] = true,
	["Death Talon Seether"] = true, ["Death Talon Overseer"] = true, ["Blackwing Spellbinder"] = true,
	["Blackwing Technician"] = true, ["Blackwing Warlock"] = true,
	["Surgical Assistant"] = true,
}

-- Kill-priority mobs always get this icon.
local KILL_MARKS = {
	["Firewalker"] = 8, ["Flameguard"] = 7, ["Lava Elemental"] = 6, ["Lava Reaver"] = 5,
	["Gurubashi Berserker"] = 8,
	["Swarmguard Needler"] = 8, ["Qiraji Warrior"] = 7, ["Qiraji Swarmguard"] = 8,
	["Qiraji Lasher"] = 5, ["Vekniss Soldier"] = 8, ["Qiraji Brainwasher"] = 8, ["Qiraji Champion"] = 4,
	["Venom Stalker"] = 8, ["Dread Creeper"] = 7, ["Carrion Spinner"] = 6, ["Living Monstrosity"] = 8,
	["Mad Scientist"] = 7, ["Frenzied Bat"] = 5, ["Plague Beast"] = 7,
}

-- Packs of the same mob: the first free icon counting down from this one
-- (or, for a negative value, counting up from its absolute value).
local PACK_MARKS = {
	["Firesworn"] = 8, ["Core Hound"] = 5,
	["Flamewaker Healer"] = 4, ["Flamewaker Elite"] = -4, ["Flamewaker Priest"] = -4,
	["Buru Egg"] = 8, ["Spawn of Fankriss"] = -3,
	["Vekniss Warrior"] = 3, ["Vekniss Wasp"] = -3, ["Vekniss Guardian"] = -6,
	["Qiraji Mindslayer"] = -4, ["Qiraji Slayer"] = 3, ["Anubisath Sentinel"] = 4,
	["Naxxramas Follower"] = -2, ["Naxxramas Worshipper"] = 4, ["Naxxramas Acolyte"] = -4,
	["Naxxramas Cultist"] = 4, ["Necro Stalker"] = -2,
}

local swipe = CreateFrame("Frame")
swipe.used = {}       -- icon -> true while it has been handed out this swipe
swipe.given = {}      -- class -> number of icons handed to that class
swipe.summary = {}    -- icon -> class, printed when the swipe ends
swipe.ccers = {}      -- class -> number of group members of that class
swipe.lastMark = 0

local function CountCrowdControllers()
	wipe(swipe.ccers)
	local prefix = IsInRaid() and "raid" or "party"
	local function Count(unit)
		local _, class = UnitClass(unit)
		if class and CC_MARKS[class] then
			swipe.ccers[class] = (swipe.ccers[class] or 0) + 1
		end
	end
	if not IsInRaid() then
		Count("player")
	end
	for i = 1, GetNumGroupMembers() do
		Count(prefix .. i)
	end
end

local function TakeMark(index)
	if swipe.used[index] then
		return false
	end
	local now = GetTime()
	if now - swipe.lastMark < TOOLTIP_UPDATE_TIME then
		return false
	end
	swipe.lastMark = now
	if SRTI.SetMark(index, GUID("mouseover"), "mouseover") then
		swipe.used[index] = true
		return true
	end
	return false
end

local function PackOrder(start)
	local order = {}
	if start > 0 then
		for i = start, 1, -1 do order[#order + 1] = i end
	else
		for i = -start, 8 do order[#order + 1] = i end
	end
	return order
end

local function SwipeMarkMouseover()
	local unit = "mouseover"
	if not Exists(unit) then
		return
	end
	local current = MarkOf(unit)
	if current and current > 0 then
		swipe.used[current] = true -- never take an icon that is already in use
		return
	end
	if not UnitCanAttack("player", unit) or UnitClassification(unit) == "worldboss" or UnitLevel(unit) == -1 then
		return
	end
	local name = UnitName(unit)
	if not name or IsSecret(name) then
		return
	end

	local kill = KILL_MARKS[name]
	if kill then
		TakeMark(kill)
		return
	end
	local pack = PACK_MARKS[name]
	if pack then
		for _, index in ipairs(PackOrder(pack)) do
			if TakeMark(index) then
				return
			end
		end
		return
	end
	if CC_IMMUNE[name] then
		return
	end

	local creatureType = UnitCreatureType(unit)
	local classes = creatureType and not IsSecret(creatureType) and CC_CLASSES[creatureType]
	if not classes then
		return
	end
	for _, class in ipairs(classes) do
		local available = swipe.ccers[class] or 0
		if available > (swipe.given[class] or 0) then
			for _, index in ipairs(CC_MARKS[class]) do
				if TakeMark(index) then
					swipe.given[class] = (swipe.given[class] or 0) + 1
					swipe.summary[index] = class
					return
				end
			end
		end
	end
end

swipe:SetScript("OnEvent", function(self)
	if self.mode == "mark" then
		pcall(SwipeMarkMouseover)
	elseif self.mode == "clear" and Exists("mouseover") then
		local current = MarkOf("mouseover")
		if current and current > 0 then
			SRTI.SetMark(0, GUID("mouseover"), "mouseover")
		end
	end
end)

local function StartSwipe(mode)
	swipe.mode = mode
	wipe(swipe.used)
	wipe(swipe.given)
	wipe(swipe.summary)
	if mode == "mark" then
		CountCrowdControllers()
	end
	swipe:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
end

local function StopSwipe()
	swipe:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	if swipe.mode == "mark" then
		for index = 1, 8 do
			local class = swipe.summary[index]
			if class then
				local color = RAID_CLASS_COLORS[class]
				local className = LOCALIZED_CLASS_NAMES_MALE[class] or class
				Print("%s: %s", IconName(index), color and color:WrapTextInColorCode(className) or className)
			end
		end
	end
	swipe.mode = nil
end

function SRTI.SwipeMark(down)
	if down then
		StartSwipe("mark")
	else
		StopSwipe()
	end
end

function SRTI.SwipeClear(down)
	if down then
		StartSwipe("clear")
	else
		StopSwipe()
	end
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

BINDING_HEADER_SRTI_HEADER = "SimpleRaidTargetIcons"
BINDING_NAME_SRTI_SHOW = "Open the radial menu for the target"
BINDING_NAME_SRTI_CLEAR = "Remove icon"
BINDING_NAME_SRTI_STAR = "Set Star"
BINDING_NAME_SRTI_CIRCLE = "Set Circle"
BINDING_NAME_SRTI_DIAMOND = "Set Diamond"
BINDING_NAME_SRTI_TRIANGLE = "Set Triangle"
BINDING_NAME_SRTI_MOON = "Set Moon"
BINDING_NAME_SRTI_SQUARE = "Set Square"
BINDING_NAME_SRTI_CROSS = "Set Cross"
BINDING_NAME_SRTI_SKULL = "Set Skull"
BINDING_NAME_SRTI_MOUSEOVER = "Hold: swipe over enemies to assign crowd-control icons"
BINDING_NAME_SRTI_MOUSEOVER_CLEAR = "Hold: swipe over enemies to remove icons"

local settingsCategory

-- The game's settings panel, when its addon API is present. Everything here
-- is optional: the slash command can change every option too.
local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory("SimpleRaidTargetIcons")

	local function Register(key, kind, name)
		return Settings.RegisterAddOnSetting(category, "SRTI_" .. key, key, db, kind, name, DEFAULTS[key])
	end
	local function Checkbox(key, name, tooltip)
		Settings.CreateCheckbox(category, Register(key, Settings.VarType.Boolean, name), tooltip)
	end
	local function Slider(key, name, tooltip, min, max, step, format)
		local setting = Register(key, Settings.VarType.Number, name)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		Settings.CreateSlider(category, setting, options, tooltip)
	end
	local function Seconds(value)
		return ("%.2f s"):format(value)
	end
	local function Percent(value)
		return ("%d%%"):format(value * 100)
	end

	Checkbox("ctrl", "Ctrl + left click opens the menu")
	Checkbox("alt", "Alt + left click opens the menu")
	Checkbox("shift", "Shift + left click opens the menu")
	Checkbox("double", "Double left click opens the menu")
	Slider("doubleSpeed", "Double click speed", "Longest pause between the two clicks.", 0.15, 0.5, 0.05, Seconds)
	Checkbox("hoverSelect", "Select by hovering", "Pick an icon by resting the cursor on it instead of clicking.")
	Slider("hoverTime", "Hover time", "How long the cursor rests on an icon before it is picked.", 0.05, 0.5, 0.05, Seconds)
	Slider("scale", "Menu size", nil, 0.5, 2.5, 0.1, Percent)
	Checkbox("sounds", "Play sounds")

	Settings.RegisterAddOnCategory(category)
	settingsCategory = category
end

local function OpenSettings()
	if settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(settingsCategory:GetID())
		return true
	end
	return false
end

local function PrintHelp()
	Print("/srti |cffffcc00<icon>|r  sets the icon of the unit under the cursor, else of the target")
	Print("  icons: 0-8, or star circle diamond triangle moon square cross skull, clear")
	Print("/srti |cffffcc00ctrl|r|alt|shift|double|hover|sounds  toggles that option")
	Print("/srti |cffffcc00speed|r|hovertime|scale <number>  sets that option")
	Print("/srti |cffffcc00options|r  shows the current settings")
end

local function PrintOptions()
	local modifiers = {}
	for _, key in ipairs({ "ctrl", "alt", "shift" }) do
		if db[key] then
			modifiers[#modifiers + 1] = key
		end
	end
	Print("opens on %s + left click; double click %s (%.2f s); hover select %s (%.2f s); scale %d%%; sounds %s",
		#modifiers > 0 and table.concat(modifiers, "/") or "no modifier",
		db.double and "on" or "off", db.doubleSpeed,
		db.hoverSelect and "on" or "off", db.hoverTime,
		db.scale * 100, db.sounds and "on" or "off")
end

local TOGGLES = { ctrl = "ctrl", alt = "alt", shift = "shift", double = "double", hover = "hoverSelect", sounds = "sounds" }
local NUMBERS = { speed = { "doubleSpeed", 0.1, 1 }, hovertime = { "hoverTime", 0.05, 1 }, scale = { "scale", 0.5, 3 } }

SLASH_SRTI1 = "/srti"
SlashCmdList.SRTI = function(msg)
	local word, rest = msg:lower():match("^%s*(%S*)%s*(.-)%s*$")
	if word == "" then
		if not OpenSettings() then
			PrintOptions()
			PrintHelp()
		end
	elseif word == "help" then
		PrintHelp()
	elseif word == "options" then
		PrintOptions()
	elseif TOGGLES[word] then
		db[TOGGLES[word]] = not db[TOGGLES[word]]
		PrintOptions()
	elseif NUMBERS[word] then
		local key, min, max = unpack(NUMBERS[word])
		local value = tonumber(rest)
		if value then
			db[key] = math.max(min, math.min(max, value))
		end
		PrintOptions()
	else
		local index = tonumber(word) or ICON_WORDS[word]
		if index and index >= 0 and index <= 8 then
			SRTI.MarkFromBinding(index)
		else
			PrintHelp()
		end
	end
end

------------------------------------------------------------------------------
-- Start-up
------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	SimpleRaidTargetIconsDB = SimpleRaidTargetIconsDB or {}
	db = SimpleRaidTargetIconsDB
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then
			db[key] = value
		end
	end
	local ok, err = pcall(RegisterSettings)
	if not ok then
		Print("settings panel unavailable (%s); use /srti instead", tostring(err))
	end
end)
