-- ForeverSparkles: a cluster of twinkling glints over the herb, ore vein,
-- quest object or lootable corpse you are walking up to. Every kind has its
-- own look, set on its page under Options > AddOns > ForeverSparkles.
--
-- How it finds things: the game's "interact key" targeting (soft targeting)
-- picks the nearest thing you could interact with as the unit "softinteract"
-- and can give it a nameplate. The addon switches that targeting on, asks the
-- game which cursor it would show for the unit (pickaxe, herb, quest ...),
-- and draws its glints on the nameplate. The nameplate is only asked for
-- while the target is something that should sparkle.
--
-- Separately it can keep the game's own loot sparkle on, which the game only
-- draws while Outline Mode is off.

local ADDON_NAME, ns = ...

local IsSecret = issecretvalue or function() return false end
local random, sin, cos, sqrt, pi = math.random, math.sin, math.cos, math.sqrt, math.pi

local UNIT = "softinteract"
local TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Glint"
local SQUASH = 0.7 -- the cluster is this much flatter than it is wide
local FADE_IN = 0.3 -- seconds for a new sparkle to come up
local RECHECK = 0.25 -- seconds between looks at the target, besides the events

ns.ORDER = { "herb", "ore", "quest", "corpse" }
ns.TITLE = { herb = "Herbs", ore = "Ore veins", quest = "Quest objects", corpse = "Corpses with loot" }

ns.DEFAULTS = {
	enabled = true,
	range = 60, -- yards the game is asked to look; it may stop sooner
	arc = "2", -- SoftTargetInteractArc: 0 straight ahead, 1 in front, 2 all around
	lootEffect = true, -- the game's own loot sparkle
	outlineOff = false, -- Outline Mode off, which the game's sparkle needs
}

-- size      width of a glint at its brightest (pixels)
-- spread    radius of the cluster (pixels)
-- count     glints alive at once
-- brightness 1 = a glint just reaches full strength at its peak; above 1 it
--           stays at full strength for longer
-- speed     how fast time runs for the glints
-- life      seconds a glint lasts at speed 1, on average
-- height    from the nameplate to the middle of the cluster (pixels, up is positive)
-- drift     pixels a second a glint floats up
-- unusable  brightness left when the game shows its greyed-out cursor
-- Every kind starts out the same; its page is where it is made to differ.
local function Look()
	return {
		enabled = true, color = "ffffdc5e", size = 34, spread = 46, count = 7,
		brightness = 1, speed = 1, life = 1, height = -40, drift = 10, unusable = 0.4,
	}
end
ns.CATEGORY_DEFAULTS = { herb = Look(), ore = Look(), quest = Look(), corpse = Look() }

-- Version 1 gave each kind a colour of its own, and herbs and ore a bigger
-- look. What was never changed from those moves to the shared defaults.
local VERSION_1_DEFAULTS = {
	herb = { color = "ff9dff7a", size = 50, spread = 70, count = 14 },
	ore = { color = "ffffc070", size = 50, spread = 70, count = 14 },
	quest = { color = "ffffe14d" },
	corpse = { color = "fffff0b0" },
}

local db

local function Print(text)
	print("|cffffd200ForeverSparkles|r " .. text)
end

-- The call's first result, or nil when it fails or the answer is secret.
local function Safe(func, ...)
	if not func then
		return nil
	end
	local ok, result = pcall(func, ...)
	if ok and not IsSecret(result) then
		return result
	end
	return nil
end

------------------------------------------------------------------------------
-- Console variables: what the addon changes it first writes down, and puts
-- back when it no longer needs it.
------------------------------------------------------------------------------

local GATE = "SoftTargetNameplateInteract" -- "Always show nameplates for soft interact target"
local LOOT_EFFECT = "outlineModeShowLootEffectWhenDisabled"
local OUTLINE = { "graphicsOutlineMode", "OutlineEngineMode", "raidGraphicsOutlineMode", "RAIDOutlineEngineMode" }

local pending = {} -- cvar -> value the game refused in combat

local function GetCVarValue(name)
	return Safe(C_CVar.GetCVar, name)
end

local function SetCVarValue(name, value)
	value = tostring(value)
	if GetCVarValue(name) == value then
		pending[name] = nil
		return
	end
	pcall(C_CVar.SetCVar, name, value)
	if GetCVarValue(name) ~= value and InCombatLockdown() then
		pending[name] = value
	else
		pending[name] = nil
	end
end

local function Take(name, value)
	if db.saved[name] == nil then
		db.saved[name] = GetCVarValue(name) or false
	end
	SetCVarValue(name, value)
end

local function Release(name)
	local saved = db.saved[name]
	if saved == nil then
		return
	end
	db.saved[name] = nil
	pending[name] = nil
	if saved then
		SetCVarValue(name, saved)
	end
end

local function Active()
	if not db.enabled then
		return false
	end
	for _, category in ipairs(ns.ORDER) do
		if db.categories[category].enabled then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------
-- What the target is, from the cursor the game would show for it
------------------------------------------------------------------------------

-- Cursor file (Interface\Cursor\<name>, lower case) -> kind.
local CURSOR_KIND = {
	mine = "ore",
	gatherherbs = "herb",
	quest = "quest",
	questrepeatable = "quest",
	campaignquest = "quest",
	legendaryquest = "quest",
	important = "quest",
}
local CURSOR_FOLDERS = { "Interface\\Cursor\\", "Interface\\Cursor\\Crosshair\\" }

local probe -- a texture nobody sees, to ask the game about cursors
local cursorOfFile -- file ID -> { kind, usable }, for clients that answer with IDs

local function Probe()
	if not probe then
		probe = UIParent:CreateTexture(nil, "BACKGROUND")
		probe:SetSize(1, 1)
		probe:Hide()
	end
	return probe
end

-- The game names the cursor as a file ("Interface\Cursor\UnableMine.blp") or
-- as an atlas ("Cursor Crosshair_GatherHerbs_64", seen on Forever): look at
-- each word of it. -> "ore", false
local function KindOfPath(path)
	for word in path:lower():gmatch("%a+") do
		local able = word:gsub("^unable", "")
		if CURSOR_KIND[able] then
			return CURSOR_KIND[able], able == word
		end
	end
	return nil
end

local function BuildCursorTable()
	cursorOfFile = {}
	local texture = Probe()
	for _, folder in ipairs(CURSOR_FOLDERS) do
		for name, kind in pairs(CURSOR_KIND) do
			for _, prefix in ipairs({ "", "Unable" }) do
				texture:SetTexture(nil)
				texture:SetTexture(folder .. prefix .. name)
				local file = Safe(texture.GetTexture, texture)
				if type(file) == "number" then
					cursorOfFile[file] = { kind, prefix == "" }
				end
			end
		end
	end
	texture:SetTexture(nil)
end

-- The kind of cursor the game shows for the unit, whether it is the usable
-- one, and what the game answered (for /fsparkles).
local function CursorKind(unit)
	if not SetUnitCursorTexture then
		return nil
	end
	if not cursorOfFile then
		BuildCursorTable()
	end
	local texture = Probe()
	texture:SetTexture(nil)
	if Safe(SetUnitCursorTexture, texture, unit, nil, true, false) ~= true then
		return nil
	end
	local file = Safe(texture.GetTexture, texture) or Safe(texture.GetAtlas, texture)
	if type(file) == "string" then
		local kind, usable = KindOfPath(file)
		return kind, usable, file
	end
	local known = file and cursorOfFile[file]
	if known then
		return known[1], known[2], file
	end
	return nil, nil, file
end

-- category, usable; nil when the unit is nothing that sparkles.
local function Classify(unit)
	if Safe(UnitIsGameObject, unit) == true then
		local kind, usable = CursorKind(unit)
		if kind == "herb" or kind == "ore" then
			return kind, usable
		end
		if kind == "quest" or Safe(C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true then
			return "quest", usable ~= false
		end
		return nil
	end
	if Safe(UnitIsDead, unit) == true then
		local guid = Safe(UnitGUID, unit)
		if guid and Safe(CanLootUnit, guid) == true then
			return "corpse", true
		end
	end
	return nil
end

------------------------------------------------------------------------------
-- The sparkle: one frame with a pool of glints, moved to whichever nameplate
-- has it
------------------------------------------------------------------------------

local sparkle = { glints = {}, fade = 0 }

local colors = {}
local function Color(hex)
	local color = colors[hex]
	if not color then
		local r, g, b = tostring(hex):match("(%x%x)(%x%x)(%x%x)$")
		if r then
			color = { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
		else
			color = { 1, 1, 1 }
		end
		colors[hex] = color
	end
	return color[1], color[2], color[3]
end

-- A new place and a new life for a glint. Staggered: somewhere before its
-- start, so a fresh cluster does not pulse as one.
local function Reseed(glint, look, staggered)
	local angle, reach = random() * 2 * pi, sqrt(random())
	glint.x = cos(angle) * reach * look.spread
	glint.y = sin(angle) * reach * look.spread * SQUASH
	glint.grow = 0.6 + 0.6 * random()
	glint.turn = random() * 2 * pi
	glint.spin = (random() - 0.5) * 1.5
	glint.span = look.life * (0.6 + 0.8 * random())
	glint.age = staggered and -random() * glint.span or 0
end

-- One frame of a cluster of glints around the middle of `frame`.
-- state: { glints = {}, fade = 0..1, category = kind, usable = bool }; the
-- sparkle on a nameplate is one, the preview in the options window another.
local function Draw(state, frame, elapsed)
	local look = db.categories[state.category]
	if not look then
		return
	end
	if elapsed > 0.1 then
		elapsed = 0.1 -- a hitch should not skip a glint's whole life
	end
	state.fade = math.min(1, state.fade + elapsed / FADE_IN)
	local level = look.brightness * state.fade * (state.usable and 1 or look.unusable)
	local r, g, b = Color(look.color)
	local glints = state.glints
	for i = 1, math.max(look.count, #glints) do
		local glint = glints[i]
		if not glint then
			local texture = frame:CreateTexture(nil, "OVERLAY")
			texture:SetTexture(TEXTURE)
			texture:SetBlendMode("ADD")
			glint = { texture = texture }
			glints[i] = glint
			Reseed(glint, look, true)
		end
		local texture = glint.texture
		if i > look.count then
			texture:Hide()
			glint.span = nil
		else
			if not glint.span then
				Reseed(glint, look, true)
			end
			glint.age = glint.age + elapsed * look.speed
			if glint.age >= glint.span then
				Reseed(glint, look)
			end
			if glint.age < 0 then
				texture:Hide()
			else
				local shine = sin(pi * glint.age / glint.span)
				local size = math.max(look.size * glint.grow * (0.4 + 0.6 * shine), 0.01)
				texture:ClearAllPoints()
				texture:SetPoint("CENTER", frame, "CENTER", glint.x, glint.y + look.drift * glint.age)
				texture:SetSize(size, size)
				texture:SetRotation(glint.turn + glint.spin * glint.age)
				texture:SetVertexColor(r, g, b, math.min(1, level * shine))
				texture:Show()
			end
		end
	end
end
ns.Draw = Draw

local function Animate(frame, elapsed)
	local look = db.categories[sparkle.category]
	if not look then
		return
	end
	if sparkle.height ~= look.height then
		sparkle.height = look.height
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", sparkle.plate, "CENTER", 0, look.height)
	end
	Draw(sparkle, frame, elapsed)
end

local function Detach()
	if not sparkle.plate then
		return
	end
	sparkle.plate, sparkle.category = nil, nil
	sparkle.frame:Hide()
	sparkle.frame:ClearAllPoints()
	sparkle.frame:SetParent(UIParent)
end

local function Attach(plate, category, usable)
	local frame = sparkle.frame
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetSize(1, 1)
		frame:Hide()
		frame:SetScript("OnUpdate", Animate)
		sparkle.frame = frame
	end
	sparkle.usable = usable
	if sparkle.plate == plate and sparkle.category == category then
		return
	end
	local look = db.categories[category]
	sparkle.plate, sparkle.category = plate, category
	sparkle.height = look.height
	sparkle.fade = 0
	for _, glint in ipairs(sparkle.glints) do
		Reseed(glint, look, true)
	end
	-- The frame is the addon's own; it only hangs on the plate, so it moves
	-- and hides with it. The plate itself is not touched.
	frame:SetParent(plate)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", plate, "CENTER", 0, look.height)
	if frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true) -- the plate of a far object is faded
	end
	frame:Show()
end

------------------------------------------------------------------------------
-- Following the target
------------------------------------------------------------------------------

local function FindPlate()
	local plate = Safe(C_NamePlate.GetNamePlateForUnit, UNIT)
	if plate then
		return plate
	end
	for _, candidate in ipairs(Safe(C_NamePlate.GetNamePlates) or {}) do
		local unit = candidate.GetUnit and Safe(candidate.GetUnit, candidate)
		if unit and Safe(UnitIsUnit, unit, UNIT) == true then
			return candidate
		end
	end
	return nil
end

-- What is under the interact key right now: category, usable, cursor answer.
local function Target()
	if Safe(UnitExists, UNIT) == true or Safe(UnitIsGameObject, UNIT) == true then
		return Classify(UNIT)
	end
	return nil
end

local function Evaluate()
	if not db then
		return
	end
	if not Active() then
		Detach()
		return
	end
	local category, usable = Target()
	local look = category and db.categories[category]
	if not (look and look.enabled) then
		Take(GATE, 0)
		Detach()
		return
	end
	Take(GATE, 1)
	local plate = FindPlate()
	if not plate then
		Detach() -- just asked for; NAME_PLATE_UNIT_ADDED brings it
		return
	end
	Attach(plate, category, usable)
end

-- Brings the game's settings in line with the addon's.
local function Sync()
	if Active() then
		Take("SoftTargetInteract", 3) -- 0 off, 1 gamepad, 2 keyboard and mouse, 3 always
		Take("SoftTargetIconGameObject", 1) -- objects you cannot target count too
		Take("SoftTargetInteractOnlyInRange", 0) -- also before you are close enough to use it
		Take("SoftTargetInteractRange", db.range)
		Take("SoftTargetInteractArc", db.arc)
	else
		Release("SoftTargetInteract")
		Release("SoftTargetIconGameObject")
		Release("SoftTargetInteractOnlyInRange")
		Release("SoftTargetInteractRange")
		Release("SoftTargetInteractArc")
		Release(GATE)
	end
	if db.lootEffect then
		Take(LOOT_EFFECT, 1)
	else
		Release(LOOT_EFFECT)
	end
	for _, name in ipairs(OUTLINE) do
		if db.outlineOff then
			Take(name, 0)
		else
			Release(name)
		end
	end
	Evaluate()
end

local function Reset()
	for key, value in pairs(ns.DEFAULTS) do
		db[key] = value
	end
	for category, defaults in pairs(ns.CATEGORY_DEFAULTS) do
		for key, value in pairs(defaults) do
			db.categories[category][key] = value
		end
	end
	Sync()
end

ns.Sync = Sync
ns.GetDB = function() return db end

------------------------------------------------------------------------------
-- /fsparkles
------------------------------------------------------------------------------

local function Status()
	Print(Active() and "is on." or "is off.")
	local exists, object = Safe(UnitExists, UNIT), Safe(UnitIsGameObject, UNIT)
	if exists ~= true and object ~= true then
		Print("Nothing under the interact key right now.")
	else
		local _, _, cursor = CursorKind(UNIT)
		local category, usable = Classify(UNIT)
		Print(("Interact target: %s, %s, cursor %s, %s, nameplate %s."):format(
			tostring(Safe(UnitName, UNIT) or "?"),
			object == true and "an object" or "a unit",
			tostring(cursor),
			category and (ns.TITLE[category] .. (usable and "" or " (greyed out)")) or "nothing that sparkles",
			FindPlate() and "found" or "not there"))
	end
	local names = { "SoftTargetInteract", "SoftTargetIconGameObject", "SoftTargetInteractRange", "SoftTargetInteractArc",
		GATE, LOOT_EFFECT, OUTLINE[1] }
	for i, name in ipairs(names) do
		names[i] = name .. "=" .. tostring(GetCVarValue(name))
	end
	Print(table.concat(names, " "))
end

local function Command(text)
	local cmd = (text or ""):lower():match("^%s*(%S*)")
	if cmd == "reset" then
		Reset()
		Print("Everything is back to how it came.")
	elseif cmd == "" or cmd == "status" then
		Status()
		Print("The settings are under Options > AddOns > ForeverSparkles. /fsparkles reset puts them all back.")
	else
		Print("/fsparkles (what it sees right now), /fsparkles reset")
	end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local function Fill(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		end
	end
end

local syncQueued = false
local function QueueSync()
	if syncQueued then
		return
	end
	syncQueued = true
	C_Timer.After(0, function()
		syncQueued = false
		Sync()
	end)
end

local sinceCheck = 0
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		ForeverSparklesDB = ForeverSparklesDB or {}
		db = ForeverSparklesDB
		Fill(db, ns.DEFAULTS)
		db.saved = db.saved or {}
		db.categories = db.categories or {}
		for category, defaults in pairs(ns.CATEGORY_DEFAULTS) do
			db.categories[category] = db.categories[category] or {}
			Fill(db.categories[category], defaults)
		end
		if db.version == 1 then
			for category, was in pairs(VERSION_1_DEFAULTS) do
				for key, value in pairs(was) do
					if db.categories[category][key] == value then
						db.categories[category][key] = ns.CATEGORY_DEFAULTS[category][key]
					end
				end
			end
		end
		db.version = 2
		SLASH_FOREVERSPARKLES1 = "/fsparkles"
		SlashCmdList.FOREVERSPARKLES = Command
		local ok, err = pcall(ns.RegisterSettings)
		if not ok then
			Print(("options panel unavailable (%s)"):format(tostring(err)))
		end
		self:RegisterEvent("PLAYER_LOGIN")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
		self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		self:RegisterEvent("CVAR_UPDATE")
		-- Events can be missed (the cursor of a node changes when a skill
		-- goes up, for one), so the target is looked at again now and then.
		self:SetScript("OnUpdate", function(_, elapsed)
			sinceCheck = sinceCheck + elapsed
			if sinceCheck >= RECHECK then
				sinceCheck = 0
				Evaluate()
			end
		end)
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		-- Twice: settings kept on the server can arrive after login.
		Sync()
	elseif event == "PLAYER_REGEN_ENABLED" then
		for name, value in pairs(pending) do
			SetCVarValue(name, value)
		end
		Evaluate()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if sparkle.plate and Safe(C_NamePlate.GetNamePlateForUnit, arg1) == sparkle.plate then
			Detach()
		end
		Evaluate()
	elseif event == "CVAR_UPDATE" then
		-- A graphics preset switches the game's loot sparkle off and the
		-- outlines back on.
		if db.lootEffect or db.outlineOff then
			local name = type(arg1) == "string" and arg1:lower() or ""
			if name:find("graphics", 1, true) or name:find("outline", 1, true) then
				QueueSync()
			end
		end
	else
		Evaluate()
	end
end)
