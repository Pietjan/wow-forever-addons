-- Enemy targets (/fplates target): every hostile nameplate whose unit has a target shows that
-- target's name under the health bar (under the cast bar while casting): class-coloured for players, so party
-- members are easy to tell apart, YOU when it is you, in Threat colours'
-- colours: green when you are a tank (it should be on you), red otherwise,
-- grey for NPCs and pets.
--
-- How, within Forever's nameplate rules (see Core.lua): the text is a
-- FontString on a frame of this addon's own, parented to the nameplate and
-- anchored under the unit frame's HealthBarsContainer, and moved under
-- its CastBarsContainer while the cast bar shows (HookScript on the cast
-- bar's OnShow/OnHide; that container has no usable position otherwise). No Blizzard function
-- is called, no Blizzard field is written, and nothing on the plate is
-- measured. Per-plate state lives in this file's own table.
--
-- Unit names and identity can be secret to addon code; on Forever "is the
-- plate's target me" (UnitIsUnit) is secret even out of combat. So each
-- plate has two texts, YOU and the name: FontString:SetText takes a secret
-- name as is, and SetAlphaFromBoolean lets the game show one of the two
-- from the secret answer. Colours are made with CreateColor and a full
-- alpha, since the class colour tables have none and the C API wants it.
-- Anything refused just hides the text for that plate (see /fplates target).
--
-- Updates come from UNIT_TARGET on nameplate units, plates being added,
-- and a light 0.2 s sweep, since an NPC's target change does not always
-- fire an event.

local _, ns = ...
local IsSecret, IsTank = ns.IsSecret, ns.IsTank

-- ThreatColor's green and red.
local YOU_TANK = CreateColor(0.20, 0.80, 0.20, 1) -- tank: it should be on you
local YOU_OTHER = CreateColor(1.00, 0.10, 0.10, 1) -- anyone else: it should not
local NPC = CreateColor(0.80, 0.80, 0.80, 1)
local SWEEP = 0.2
local SIZE = 0.85 -- of the nameplate name's height: the same font, a little smaller

local feature
local texts = {} -- nameplate -> our frame
local lastError -- the last error caught, for /fplates target

local function Note(err)
	lastError = tostring(err)
end

-- Put the nameplate font on a plate's texts when it differs from what they
-- have (the nameplate size and style options can change it).
local function ApplyFont(frame)
	local object, height = ns.NamePlateFont()
	local key = object .. ":" .. tostring(height)
	if frame.fontKey == key then
		return
	end
	frame.fontKey = key
	for _, text in ipairs({ frame.text, frame.you }) do
		text:SetFontObject(object)
		if type(height) == "number" and height > 0 then
			text:SetTextHeight(height * SIZE)
		end
	end
end

local function TextFor(plate)
	local frame = texts[plate]
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", nil, plate)
	frame:SetSize(1, 1)
	local okLevel, level = pcall(plate.GetFrameLevel, plate)
	if okLevel and type(level) == "number" and not IsSecret(level) then
		frame:SetFrameLevel(level + 110) -- over the widget container, which shares the spot
	end
	local text = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
	text:SetJustifyH("CENTER")
	text:SetWordWrap(false)
	local you = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
	you:SetText("YOU")
	you:SetPoint("CENTER", text, "CENTER")
	frame.text, frame.you = text, you
	local unitFrame = plate.UnitFrame
	local health = unitFrame and unitFrame.HealthBarsContainer
	local casts = unitFrame and unitFrame.CastBarsContainer
	local castBar = casts and casts.castBar

	-- Under the health bar, or under the cast bar while one shows: the
	-- cast bar area has no usable position when nothing is being cast.
	local function Anchor(casting)
		text:ClearAllPoints()
		if casting and casts then
			text:SetPoint("TOP", casts, "BOTTOM", 0, -1)
		elseif health then
			text:SetPoint("TOP", health, "BOTTOM", 0, -1)
		else
			text:SetPoint("TOP", plate, "BOTTOM", 0, 0)
		end
	end
	Anchor(false)
	if castBar then
		-- HookScript runs after Blizzard's own handler and only moves our
		-- text. Guarded: should Forever refuse it, the text simply stays
		-- under the health bar.
		local okHook, err = pcall(function()
			castBar:HookScript("OnShow", function() Anchor(true) end)
			castBar:HookScript("OnHide", function() Anchor(false) end)
		end)
		frame.castHooked = okHook
		if not okHook then
			Note(err)
		end
		local okShown, shown = pcall(castBar.IsShown, castBar)
		if okShown and not IsSecret(shown) and shown == true then
			Anchor(true)
		end
	end
	frame:Hide()
	texts[plate] = frame
	return frame
end

local classColors = {} -- class file name -> colour with alpha

local function ClassColor(unit)
	if not UnitIsPlayer(unit) then
		return NPC
	end
	local _, class = UnitClass(unit)
	if IsSecret(class) then
		-- The class is secret, but the game will look its colour up and
		-- SetTextColor takes the (secret) result; nothing is cached.
		local ok, game = pcall(C_ClassColor.GetClassColor, class)
		return ok and game or NPC
	end
	if type(class) ~= "string" then
		return NPC
	end
	local color = classColors[class]
	if not color then
		local game = C_ClassColor and C_ClassColor.GetClassColor(class)
		if not game then
			return NPC
		end
		color = CreateColor(game.r, game.g, game.b, 1)
		classColors[class] = color
	end
	return color
end

local function YouColor()
	return IsTank() and YOU_TANK or YOU_OTHER
end

-- Fill one plate's texts; false when there is nothing to show.
local function Fill(frame, unit)
	local text, you = frame.text, frame.you
	ApplyFont(frame)
	if not UnitExists(unit) or not UnitCanAttack("player", unit) then
		return false
	end
	local target = unit .. "target"
	if not UnitExists(target) then
		return false
	end
	text:SetText(UnitName(target))
	text:SetTextColor(ClassColor(target):GetRGB())
	you:SetTextColor(YouColor():GetRGB())
	local isMe = UnitIsUnit(target, "player")
	if IsSecret(isMe) then
		-- The game picks which of the two is visible.
		you:SetAlphaFromBoolean(isMe)
		text:SetAlphaFromBoolean(isMe, 0, 255)
	else
		you:SetAlpha(isMe and 1 or 0)
		text:SetAlpha(isMe and 0 or 1)
	end
	return true
end

local function Update(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	local okFrame, frame = pcall(TextFor, plate)
	if not okFrame then
		Note(frame)
		return
	end
	local ok, shown = pcall(Fill, frame, unit)
	if not ok then
		Note(shown)
	end
	frame:SetShown(ok and shown == true)
end

-- /fplates target: what the feature sees on your target's nameplate.
local function Report()
	local Say = ns.Print
	Say("Enemy targets " .. (feature.db.enabled and "on" or "off; /fplates target on"))
	local plate = C_NamePlate.GetNamePlateForUnit("target")
	if not plate then
		Say("your target has no nameplate (target an enemy with a visible plate)")
	else
		local unitFrame = plate.UnitFrame
		local unit = unitFrame and unitFrame.unit
		Say(("plate unit %s, health bar %s, cast bar %s"):format(
			IsSecret(unit) and "secret" or tostring(unit),
			tostring(unitFrame and unitFrame.HealthBarsContainer ~= nil),
			tostring(unitFrame and unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar ~= nil)))
		local ok, attackable = pcall(UnitCanAttack, "player", "target")
		Say(("attackable %s, has a target %s"):format(tostring(ok and attackable),
			tostring(UnitExists("targettarget"))))
		if UnitExists("targettarget") then
			local isPlayer = UnitIsPlayer("targettarget")
			local _, class = UnitClass("targettarget")
			Say(("its target: player %s, class %s"):format(
				IsSecret(isPlayer) and "secret" or tostring(isPlayer),
				IsSecret(class) and "secret" or tostring(class)))
		end
		local frame = texts[plate]
		if not frame then
			Say("no text made for this plate yet")
		else
			Say(("text shown %s, cast bar hooked %s"):format(tostring(frame:IsShown()), tostring(frame.castHooked)))
		end
	end
	Say("last error: " .. (lastError or "none"))
end

local function UpdateAll()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.UnitFrame and plate.UnitFrame.unit
		if type(unit) == "string" and not IsSecret(unit) then
			Update(unit)
		elseif texts[plate] then
			texts[plate]:Hide()
		end
	end
end

local ticker

feature = ns.Feature({
	key = "target",
	title = "Enemy targets",
	tooltip = "Enemy nameplates show who the enemy is targeting, under the bar (below the cast bar while casting); class colours; YOU when it is you, green for tanks, red otherwise.",
	defaults = { enabled = true },
	events = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_TARGET", "PLAYER_TARGET_CHANGED" },
	Command = Report,
})

function feature.Start()
	ticker = C_Timer.NewTicker(SWEEP, UpdateAll)
	UpdateAll()
end

function feature.Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	for _, frame in pairs(texts) do
		frame:Hide()
	end
end

function feature.OnEvent(event, unit)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and texts[plate] then
			texts[plate]:Hide()
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateAll()
	elseif type(unit) == "string" and not IsSecret(unit) and unit:find("^nameplate") then
		Update(unit)
	end
end
