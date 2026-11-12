-- SimpleRaidTargetIcons: a radial menu of the eight raid target icons that
-- opens around the cursor when you modifier-click or double-click a unit.
-- Click the icon you want, right-click to clear, move away to cancel.
--
-- A rewrite of the 2.x addon by MrFIXlT and Zimzarina (concept by Qzot) for
-- WoW Forever. Since patch 12.0 SetRaidTarget() is a protected function, so
-- an icon can only be set by a secure button that the player clicks or
-- presses a key bound to. The menu's icons are such buttons, which also
-- means the menu cannot be opened in combat: protected frames cannot be
-- shown or moved by addon code while fighting. The key bindings work in
-- combat.

local ADDON_NAME = ...

local ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local DEFAULTS = {
	ctrl = true,        -- which modifiers + left click open the menu
	alt = false,
	shift = false,
	double = true,      -- double left click opens the menu
	doubleSpeed = 0.25, -- seconds between the two clicks
	scale = 1.0,
	sounds = true,
}

-- Menu geometry in the menu's own (scaled) pixels, measured from its centre.
local RADIUS, ICON_SIZE, HIT_SIZE = 44, 26, 32
local PORTRAIT_SIZE = 40
local RIM = 1.5           -- width of the bronze edge around a disc
local LINGER_RADIUS = 75  -- beyond this the menu closes after LINGER_TIME
local CANCEL_RADIUS = 200 -- beyond this it closes at once
local LINGER_TIME = 0.75
local FADE_TIME = 0.12

-- Forever's interface colours: near-black panels with a bronze edge, gold
-- for whatever is selected.
local PANEL = { 0.06, 0.05, 0.04 }
local BRONZE = { 0.55, 0.42, 0.22 }
local GOLD = { 1, 0.82, 0.2 }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

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

local function Sound(kit)
	if db.sounds then
		PlaySound(kit, "SFX")
	end
end

local function Exists(unit)
	return unit and UnitExists(unit)
end

-- Values can be secret on this engine; treat those as unknown.
local function GUID(unit)
	local guid = UnitGUID(unit)
	if guid and not IsSecret(guid) then
		return guid
	end
end

------------------------------------------------------------------------------
-- Secure buttons: the only way left to set an icon
------------------------------------------------------------------------------

-- A button whose left click toggles the given icon on a unit and whose right
-- click removes whatever icon the unit has. With no marker it only clears.
-- The unit is "target" unless a state driver is attached (see the binding
-- buttons below).
local function NewMarkButton(name, parent, marker, template)
	local button = CreateFrame("Button", name, parent, template or "SecureActionButtonTemplate")
	-- Mouse clicks act on release; key presses act on press or release
	-- according to the game's own setting, so register for both.
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetAttribute("unit", "target")
	if marker then
		button:SetAttribute("type1", "raidtarget")
		button:SetAttribute("marker", marker)
		button:SetAttribute("action1", "toggle")
	end
	button:SetAttribute("type2", "raidtarget")
	button:SetAttribute("action2", "clear")
	return button
end

------------------------------------------------------------------------------
-- The radial menu
------------------------------------------------------------------------------

local menu = CreateFrame("Button", "SRTIRadialMenu", UIParent)
menu:SetSize(2 * (RADIUS + HIT_SIZE / 2), 2 * (RADIUS + HIT_SIZE / 2))
menu:SetFrameStrata("DIALOG")
menu:SetClampedToScreen(true)
menu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
menu:Hide()

-- A flat disc in one colour: a white texture cut round by a mask, tinted.
local function Disc(parent, sublevel, color)
	local disc = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	disc:SetColorTexture(1, 1, 1)
	disc:SetVertexColor(color[1], color[2], color[3])
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(disc)
	disc:AddMaskTexture(mask)
	return disc
end

-- A dark disc with a thin coloured edge: the rim disc shows around the fill.
local function Socket(parent, size)
	local rim = Disc(parent, 0, BRONZE)
	rim:SetSize(size, size)
	local fill = Disc(parent, 1, PANEL)
	fill:SetPoint("TOPLEFT", rim, "TOPLEFT", RIM, -RIM)
	fill:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -RIM, RIM)
	return rim
end

-- The centre shows the unit; right-clicking it removes the icon.
menu.center = NewMarkButton("SRTIRadialMenuCenter", menu, nil)
menu.center:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
menu.center:SetPoint("CENTER")
menu.ring = Socket(menu.center, PORTRAIT_SIZE + 6)
menu.ring:SetPoint("CENTER")
menu.portrait = menu.center:CreateTexture(nil, "ARTWORK")
menu.portrait:SetAllPoints()
do
	local mask = menu.center:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(menu.portrait)
	menu.portrait:AddMaskTexture(mask)
end

-- Icon i sits at angle 90 - (i - 1) * 45 degrees: star on top, then clockwise.
local function IconAngle(index)
	return math.rad(90 - (index - 1) * 45)
end

-- Which icon a unit has is secret to addon code here: the number can be
-- neither read nor compared, only handed on to the game. To still show the
-- "pass" sign of the loot roll window in place of the icon the unit already
-- has (picking that icon removes it), every icon is a 4x4 sprite sheet of its
-- own: each cell is the icon, except that cell i of icon i is the sign, and
-- the game picks the cell from the unit's number. Cell 9 is the icon again,
-- for a unit without one. See scripts/icon_sheets.py.
local NO_MARK = 9

menu.buttons = {}
for i = 1, 8 do
	local button = NewMarkButton("SRTIRadialMenuIcon" .. i, menu, i)
	button:SetSize(HIT_SIZE, HIT_SIZE)
	local angle = IconAngle(i)
	button:SetPoint("CENTER", menu, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Icon" .. i)
	button.icon:SetSpriteSheetCell(NO_MARK, 4, 4)
	button.icon:SetPoint("CENTER")
	-- A soft dark fade behind the icon, so it reads on bright ground.
	button.shade = menu:CreateTexture(nil, "BACKGROUND", nil, 0)
	button.shade:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Shade")
	button.shade:SetVertexColor(0, 0, 0, 0.7)
	button.shade:SetPoint("CENTER", button.icon)
	menu.buttons[i] = button
end

local function ShowCurrentMark()
	local index = GetRaidTargetIndex("target")
	-- With no icon the number is nil, which the call refuses.
	local marked = IsSecret(index) or index ~= nil
	for _, button in ipairs(menu.buttons) do
		if not (marked and pcall(button.icon.SetSpriteSheetCell, button.icon, index, 4, 4)) then
			button.icon:SetSpriteSheetCell(NO_MARK, 4, 4)
		end
	end
end

local function Close(sound)
	if not menu:IsShown() or menu.state == "hiding" then
		return
	end
	menu.state = "hiding"
	menu.stateSince = GetTime()
	if sound then
		Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
end

-- Draw the icons at a fraction (0..1) of their final distance and size. Only
-- the textures move; the buttons under them stay where they are. The icon
-- under the cursor grows.
local function Layout(progress)
	progress = 1 - (1 - progress) ^ 2 -- ease out
	local radius = RADIUS * (0.45 + 0.55 * progress)
	local grow = 0.5 + 0.5 * progress
	for i, button in ipairs(menu.buttons) do
		local angle = IconAngle(i)
		local x, y = radius * math.cos(angle), radius * math.sin(angle)
		local size = ICON_SIZE * grow * (i == menu.selected and 1.3 or 1)
		button.icon:SetPoint("CENTER", menu, "CENTER", x, y)
		button.icon:SetSize(size, size)
		button.shade:SetSize(size * 2.2, size * 2.2)
	end
end

local function CursorDistance()
	local x, y = GetCursorPosition()
	local scale = menu:GetEffectiveScale()
	local cx, cy = menu:GetCenter()
	local dx, dy = x / scale - cx, y / scale - cy
	return math.sqrt(dx * dx + dy * dy)
end

local function SelectedIcon()
	for i, button in ipairs(menu.buttons) do
		if button:IsMouseOver() then
			return i
		end
	end
	return nil
end

-- Open the menu for the target (the click that opens it also targets the
-- unit). Returns false when it cannot open.
function SRTI.Open()
	if menu:IsShown() then
		return false
	end
	if not Exists("target") then
		return false
	end
	if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		return false
	end
	if InCombatLockdown() then
		if not SRTI.warnedCombat then
			Print("the menu cannot open during combat; the key bindings still work")
			SRTI.warnedCombat = true
		end
		return false
	end

	menu.guid = GUID("target")
	ShowCurrentMark()
	menu.selected = nil
	menu.state = "showing"
	menu.stateSince = GetTime()

	SetPortraitTexture(menu.portrait, "target")
	menu:SetScale(db.scale)
	local x, y = GetCursorPosition()
	local scale = menu:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	menu:SetAlpha(0)
	Layout(0)
	menu:Show()
	Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	return true
end

menu:SetScript("OnUpdate", function(self)
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

	-- The target changed or went away.
	if not Exists("target") or (self.guid and GUID("target") ~= self.guid) then
		Close(true)
		return
	end

	local dist = CursorDistance()
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
	end

	self.selected = SelectedIcon()
	ShowCurrentMark()
	Layout(self.state == "open" and 1 or progress)
end)

-- A click on the menu that lands on no icon just closes it.
menu:SetScript("OnClick", function()
	Close(true)
end)

-- The secure part of a click has run by now; the sound and the closing are
-- ours.
local function AfterClick(self, button)
	if button == "RightButton" then
		Sound(SOUNDKIT.IG_MINIMAP_ZOOM_OUT)
	elseif self.marker then
		Sound(SOUNDKIT.IG_MINIMAP_ZOOM_IN)
	end
	Close(false)
end
menu.center:SetScript("PostClick", AfterClick)
for i, button in ipairs(menu.buttons) do
	button.marker = i
	button:SetScript("PostClick", AfterClick)
end

menu:SetScript("OnHide", function(self)
	self.state = nil
	self.guid = nil
	self.linger = nil
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

-- The frames under the cursor, innermost first.
local function FramesUnderCursor()
	if GetMouseFoci then
		return GetMouseFoci() or {}
	elseif GetMouseFocus then
		return { GetMouseFocus() }
	end
	return {}
end

-- The unit of the unit frame under the cursor, if the cursor is on one.
-- Unit frames carry their unit in the "unit" attribute; a click on one of
-- their children (a health bar, say) is a click on the frame.
local function UnitUnderCursor()
	for _, focus in ipairs(FramesUnderCursor()) do
		local frame = focus
		while frame and frame ~= UIParent and frame ~= WorldFrame do
			-- Protected Blizzard frames (the community invite box, say) are
			-- forbidden to addon code: any method call on them is an error.
			if frame.IsForbidden and frame:IsForbidden() then
				return nil, nil
			end
			if frame == menu or (frame.GetParent and frame:GetParent() == menu) then
				return nil, frame
			end
			local unit = frame.GetAttribute and frame:GetAttribute("unit")
			if unit and not IsSecret(unit) then
				if SecureButton_GetModifiedUnit then
					unit = SecureButton_GetModifiedUnit(frame) or unit
				end
				return unit, frame
			end
			frame = frame:GetParent()
		end
	end
	local top = FramesUnderCursor()[1]
	if top and top.IsForbidden and top:IsForbidden() then
		top = nil
	end
	return nil, top
end

local lastClick = { time = 0, x = 0, y = 0, guid = nil }

-- Every left click on a unit: its frame, or its model or nameplate in the
-- world. The click itself targets the unit; the menu opens a moment later,
-- once that has happened.
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

	if ModifierDown() or double then
		lastClick.time = 0
		C_Timer.After(0, SRTI.Open)
	end
end

local clicks = CreateFrame("Frame")
clicks:RegisterEvent("GLOBAL_MOUSE_UP")
clicks:RegisterEvent("PLAYER_REGEN_DISABLED")
clicks:RegisterEvent("PLAYER_REGEN_ENABLED")
clicks:SetScript("OnEvent", function(_, event, button)
	if event == "PLAYER_REGEN_DISABLED" then
		-- Hide while that is still allowed; the fade would be too late.
		menu:Hide()
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		SRTI.warnedCombat = nil
		return
	end
	if button ~= "LeftButton" then
		return
	end
	local unit, frame = UnitUnderCursor()
	if not unit and Exists("mouseover") then
		unit = "mouseover"
	end
	if db.debug then
		local name = frame and frame.GetName and frame:GetName() or tostring(frame)
		Print("click on %s, unit %s (%s), modifier %s", name, tostring(unit),
			unit and Exists(unit) and tostring(UnitName(unit)) or "-", tostring(ModifierDown()))
	end
	if Exists(unit) then
		UnitClicked(unit)
	end
end)

function SRTI.ShowFromBinding()
	SRTI.Open()
end

------------------------------------------------------------------------------
-- Key bindings: one secure button per icon, acting on the unit under the
-- cursor when there is one, else on the target
------------------------------------------------------------------------------

BINDING_HEADER_SRTI_HEADER = "SimpleRaidTargetIcons"
BINDING_NAME_SRTI_SHOW = "Open the radial menu for the target"
for i = 0, 8 do
	_G["BINDING_NAME_CLICK SRTIMark" .. i .. ":LeftButton"] = i == 0 and "Remove icon" or ("Set " .. ICON_NAMES[i])
end

for i = 0, 8 do
	local button = NewMarkButton("SRTIMark" .. i, UIParent, i > 0 and i or nil,
		"SecureActionButtonTemplate,SecureHandlerStateTemplate")
	if i == 0 then
		button:SetAttribute("type1", "raidtarget")
		button:SetAttribute("action1", "clear")
	end
	-- Keep it a shown, invisible speck so that a bound key always reaches it.
	button:SetSize(1, 1)
	button:SetPoint("BOTTOMLEFT")
	button:SetAlpha(0)
	button:EnableMouse(false)
	button:SetAttribute("_onstate-unit", [[ self:SetAttribute("unit", newstate) ]])
	RegisterStateDriver(button, "unit", "[@mouseover,exists] mouseover; target")
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

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

	Checkbox("ctrl", "Ctrl + left click opens the menu")
	Checkbox("alt", "Alt + left click opens the menu")
	Checkbox("shift", "Shift + left click opens the menu")
	Checkbox("double", "Double left click opens the menu")
	Slider("doubleSpeed", "Double click speed", "Longest pause between the two clicks.", 0.15, 0.5, 0.05,
		function(value) return ("%.2f s"):format(value) end)
	Slider("scale", "Menu size", nil, 0.5, 2.5, 0.1,
		function(value) return ("%d%%"):format(value * 100) end)
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

local function PrintOptions()
	local modifiers = {}
	for _, key in ipairs({ "ctrl", "alt", "shift" }) do
		if db[key] then
			modifiers[#modifiers + 1] = key
		end
	end
	Print("opens on %s + left click; double click %s (%.2f s); scale %d%%; sounds %s",
		#modifiers > 0 and table.concat(modifiers, "/") or "no modifier",
		db.double and "on" or "off", db.doubleSpeed, db.scale * 100, db.sounds and "on" or "off")
end

local function PrintHelp()
	Print("/srti  opens the settings")
	Print("/srti |cffffcc00ctrl|r|alt|shift|double|sounds  toggles that option")
	Print("/srti |cffffcc00speed|r|scale <number>  sets that option")
	Print("/srti |cffffcc00debug|r  reports every click in chat")
	Print("Icons can only be set by clicking the menu or by key: bind keys under Key Bindings > AddOns.")
end

local TOGGLES = { ctrl = "ctrl", alt = "alt", shift = "shift", double = "double", sounds = "sounds" }
local NUMBERS = { speed = { "doubleSpeed", 0.1, 1 }, scale = { "scale", 0.5, 3 } }

SLASH_SRTI1 = "/srti"
SlashCmdList.SRTI = function(msg)
	local word, rest = msg:lower():match("^%s*(%S*)%s*(.-)%s*$")
	if word == "" then
		if not OpenSettings() then
			PrintOptions()
			PrintHelp()
		end
	elseif word == "options" then
		PrintOptions()
	elseif word == "debug" then
		db.debug = not db.debug or nil
		Print("debug output %s", db.debug and "on" or "off")
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
		PrintHelp()
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
