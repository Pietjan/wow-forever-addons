-- CooldownNag: BuffNag's bar, for cooldowns. An icon pops up a few seconds
-- before an ability you chose comes off cooldown, counts down, and once the
-- ability is ready stays a moment longer with a glow and a sound, then goes
-- away. Nothing on it is clickable: it is a reminder, not an action bar, so
-- it keeps working in combat.
--
-- It is configured from its own tab in the Cooldown Manager's settings
-- window (Escape > Options > Cooldown Manager, or /cdn): the abilities on
-- offer are the spells in your spellbook with a cooldown of ten seconds or
-- more, with the ones the Cooldown Manager calls essential for your class
-- first. A new character starts out watching those.
--
-- In combat (and in encounters, dungeons on a timer and PvP) the game keeps
-- cooldown numbers secret from addons: they cannot be compared, only handed
-- back to the game to draw. So the bar keeps a clock of its own: when you
-- cast a watched ability it notes the time and the ability's cooldown
-- length, and counts down from there. Whenever the game's own numbers are
-- readable (out of combat) they overrule the clock, and the real length of
-- each cooldown is remembered for the next reckoning. What the clock can
-- miss is a cooldown the game shortens behind its back mid-fight, such as a
-- reset from Cold Snap or Preparation.

local ADDON_NAME = ...

local IsSecret = issecretvalue or function() return false end

local DEFAULTS = { -- account wide
	soon = 5, -- seconds before ready at which the icon appears
	linger = 3, -- seconds it stays once ready
	sound = true, -- a sound when an ability comes ready
	soundKit = 353392, -- the Cooldown Manager's "Bell Strike"
	glow = "flash", -- "flash", "ants" or "off": the Cooldown Manager's alert effect on a ready ability
	glowColor = "gold", -- gold, cyan, red, green or blue
	minCooldown = 10, -- abilities with a shorter cooldown stay out of the list
	scale = 1,
	locked = false,
	point = { "CENTER", 0, 150 },
}

local PING = SOUNDKIT and SOUNDKIT.MAP_PING or 3175
local GCD_MAX = 1.6 -- a cooldown no longer than this is the global cooldown
local ICON, GAP = 40, 6
local ICON_OUTSET = 0.5 -- the picture reaches this far under the border ring, so it fills the frame
local MAX_ICONS = 16
local QUESTION_MARK = 134400
local TAB_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local db, cdb -- account settings, this character's choices
local book = {} -- spell name -> { spellID, icon }, from the spellbook, highest rank last
local bookOrder = {}
local catalog, catalogOrder = {}, {} -- name -> entry, in display order
local watched = {} -- the watched entries, in display order; each has its own icon slot
local previewing = false
local evaluateToken = 0

local function Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff9999ffCooldownNag|r " .. msg)
end

local function SpellName(spellID)
	local ok, name = pcall(C_Spell.GetSpellName, spellID)
	if ok and name and not IsSecret(name) then
		return name
	end
end

local function SpellIcon(spellID)
	local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
	return ok and icon or QUESTION_MARK
end

-- "30s", "1.5m", "2h".
local function CooldownText(seconds)
	if not seconds then
		return "?"
	elseif seconds >= 3600 then
		return ("%gh"):format(math.floor(seconds / 360 + 0.5) / 10)
	elseif seconds >= 60 then
		return ("%gm"):format(math.floor(seconds / 6 + 0.5) / 10)
	end
	return ("%gs"):format(seconds)
end

------------------------------------------------------------------------------
-- The spellbook, and what each spell's cooldown is
------------------------------------------------------------------------------

local function ScanSpellbook()
	wipe(book)
	wipe(bookOrder)
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo) then
		return
	end
	local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
	local spellType = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
				if item and item.itemType == spellType and not item.isPassive and item.name and not IsSecret(item.name) then
					local spellID = item.spellID or item.actionID
					if spellID and not IsSecret(spellID) then
						if not book[item.name] then
							bookOrder[#bookOrder + 1] = item.name
						end
						-- Ranks are listed lowest first; the last one wins.
						book[item.name] = { spellID = spellID, icon = item.iconID or SpellIcon(spellID) }
					end
				end
			end
		end
	end
end

local UNITS = { sec = 1, secs = 1, second = 1, seconds = 1, min = 60, mins = 60, minute = 60, minutes = 60,
	hr = 3600, hrs = 3600, hour = 3600, hours = 3600, day = 86400, days = 86400 }

-- The cooldown printed on the spell's tooltip ("2 min cooldown"), in
-- seconds. English wording; the game's own data is asked first.
local function TooltipCooldown(spellID)
	local ok, seconds = pcall(function()
		local data = C_TooltipInfo and C_TooltipInfo.GetSpellByID and C_TooltipInfo.GetSpellByID(spellID)
		if not (data and data.lines) then
			return nil
		end
		for _, line in ipairs(data.lines) do
			local text = line.rightText
			if type(text) == "string" and not IsSecret(text) and text:lower():find("cooldown", 1, true) then
				local amount, unit = text:match("^([%d%.,]+)%s*(%a+)")
				local factor = unit and UNITS[unit:lower()]
				amount = amount and tonumber((amount:gsub(",", "")))
				if amount and factor then
					return amount * factor
				end
			end
		end
	end)
	return ok and seconds or nil
end

-- A spell's cooldown length in seconds, or nil when it has none the game
-- will tell about: from the game's data, else the tooltip, else what was
-- seen when it was last cast.
local function BaseCooldown(name, spellID)
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, spellID)
		if ok and type(ms) == "number" and not IsSecret(ms) and ms > 0 then
			return ms / 1000
		end
	end
	return TooltipCooldown(spellID) or cdb.learned[name]
end

------------------------------------------------------------------------------
-- The catalogue: the abilities that can be watched
------------------------------------------------------------------------------

-- An entry: name, spellID, icon, cooldown (seconds from spell data, maybe
-- nil), essential; then what is known of its state: armed (on a cooldown
-- that is worth announcing the end of), endsAt (when, as far as is known),
-- total (that cooldown's length), exact (the game said so, rather than our
-- clock), lingerUntil.

local function BuildCatalog()
	wipe(catalog)
	wipe(catalogOrder)
	-- The Cooldown Manager's lists for the class come first, in its order.
	if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and Enum.CooldownViewerCategory then
		local categories = Enum.CooldownViewerCategory
		for _, category in ipairs({ categories.Essential, categories.SpecAgnosticEssential, categories.Utility }) do
			local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, false)
			if ok and type(ids) == "table" then
				for _, cooldownID in ipairs(ids) do
					local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
					if okInfo and info and info.isKnown and not info.isInvisible then
						local name = SpellName(info.overrideSpellID or info.spellID)
						if name and book[name] and not catalog[name] then
							local essential = category ~= categories.Utility
							catalog[name] = { name = name, spellID = book[name].spellID, icon = book[name].icon, essential = essential }
							catalogOrder[#catalogOrder + 1] = name
						end
					end
				end
			end
		end
	end
	-- Then everything else in the book with a long enough cooldown, the
	-- longest first.
	local rest = {}
	for _, name in ipairs(bookOrder) do
		local entry = catalog[name]
		local cooldown = BaseCooldown(name, book[name].spellID)
		if entry then
			entry.cooldown = cooldown
		elseif cdb.extra[name] or (cooldown and cooldown >= db.minCooldown) then
			rest[#rest + 1] = { name = name, spellID = book[name].spellID, icon = book[name].icon, cooldown = cooldown }
		end
	end
	table.sort(rest, function(a, b)
		if (a.cooldown or 0) ~= (b.cooldown or 0) then
			return (a.cooldown or 0) > (b.cooldown or 0)
		end
		return a.name < b.name
	end)
	for _, entry in ipairs(rest) do
		catalog[entry.name] = entry
		catalogOrder[#catalogOrder + 1] = entry.name
	end
end

-- A new character starts out watching what the Cooldown Manager calls
-- essential. Done once, so unwatching sticks.
local function SeedChoices()
	if cdb.seeded then
		return
	end
	local any = false
	for _, name in ipairs(catalogOrder) do
		any = true
		if catalog[name].essential then
			cdb.watch[name] = true
		end
	end
	if any then
		cdb.seeded = true
	end
end

------------------------------------------------------------------------------
-- Reading cooldowns
------------------------------------------------------------------------------

-- What the game says about an ability's cooldown:
--   "ready"             nothing is running;
--   "open", left, total the seconds left and the cooldown's length;
--   "secret", duration  it is running but the numbers are secret: here is the
--                       duration object, for the game to draw from;
--   nil                 nothing can be known this moment.
local function ReadCooldown(name)
	if C_Spell.GetSpellCooldownDuration then
		local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, name, true) -- true: the global cooldown does not count
		if not ok or not duration then
			return "ready"
		end
		local okSecret, secret = pcall(duration.HasSecretValues, duration)
		if okSecret and not secret then
			local okRead, zero, left, total = pcall(function()
				return duration:IsZero(), duration:GetRemainingDuration(), duration:GetTotalDuration()
			end)
			if okRead then
				if zero or left <= 0 or total <= 0 then
					return "ready"
				end
				return "open", left, total
			end
		end
		-- Secret numbers; whether there is a cooldown at all may still be plain.
		local okZero, zero = pcall(function()
			if duration:IsZero() then
				return true
			end
			return false
		end)
		if okZero and zero then
			return "ready"
		end
		return "secret", duration
	end
	-- Older client: plain numbers, or nothing.
	local ok, left, total = pcall(function()
		local info = C_Spell.GetSpellCooldown(name)
		if not info or info.isEnabled == false or info.duration <= 0 then
			return 0, 0
		end
		local onGCD = info.isOnGCD
		if onGCD == nil then
			onGCD = info.duration <= GCD_MAX
		end
		if onGCD then
			return 0, 0
		end
		return info.startTime + info.duration - GetTime(), info.duration
	end)
	if ok and type(left) == "number" and not IsSecret(left) and not IsSecret(total) then
		if left <= 0 then
			return "ready"
		end
		return "open", left, total
	end
	return nil
end

-- Spells the game would not tell the cooldown of are learned when they
-- are seen on one.
local catalogDirty = false
local function LearnCooldowns()
	for _, name in ipairs(bookOrder) do
		if not catalog[name] and not cdb.learned[name] then
			local kind, _, total = ReadCooldown(name)
			if kind == "open" and total >= db.minCooldown then
				cdb.learned[name] = total
				catalogDirty = true
			end
		end
	end
end

------------------------------------------------------------------------------
-- Icons in the Cooldown Manager's style
------------------------------------------------------------------------------

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- The Cooldown Manager's own icon dressing: its rounded mask and border
-- overlay, uncropped, as in CooldownViewerBuffIconItemTemplate. A plain
-- dark edge stands in on a client without those atlases.
local OVERLAY_REACH = { [50] = { 9, 8 }, [40] = { 8, 7 }, [30] = { 6, 5 } }

local function StyleIcon(frame, size)
	size = size or ICON
	frame:SetSize(size, size)
	local reach = OVERLAY_REACH[size] or { size * 0.2, size * 0.2 - 1 }
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
	icon:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
	frame.Icon = icon
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = frame:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetPoint("TOPLEFT", -ICON_OUTSET, ICON_OUTSET)
		mask:SetPoint("BOTTOMRIGHT", ICON_OUTSET, -ICON_OUTSET)
		icon:AddMaskTexture(mask)
		local overlay = frame:CreateTexture(nil, "OVERLAY")
		overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		overlay:SetPoint("TOPLEFT", -reach[1], reach[2])
		overlay:SetPoint("BOTTOMRIGHT", reach[1], -reach[2])
	else
		local edge = frame:CreateTexture(nil, "BACKGROUND")
		edge:SetColorTexture(0, 0, 0, 0.9)
		edge:SetPoint("TOPLEFT", -1.5, 1.5)
		edge:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
	end
	local count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.Count = count
end

-- The Cooldown Manager's own alert effects, made from its templates: the
-- "visual alert" flash or marching ants, in the game's five colours.
local GLOW_TEMPLATES = {
	flash = { gold = "VisualAlertFlashBaseTemplate", cyan = "VisualAlertFlashCyanTemplate", red = "VisualAlertFlashRedTemplate",
		green = "VisualAlertFlashGreenTemplate", blue = "VisualAlertFlashBlueTemplate" },
	ants = { gold = "VisualAlertMarchingAntsBaseTemplate", cyan = "VisualAlertMarchingAntsCyanTemplate", red = "VisualAlertMarchingAntsRedTemplate",
		green = "VisualAlertMarchingAntsGreenTemplate", blue = "VisualAlertMarchingAntsBlueTemplate" },
}

local function GlowFrame(frame, template)
	frame.glows = frame.glows or {}
	local glow = frame.glows[template]
	if glow == nil then
		local ok, made = pcall(CreateFrame, "Frame", nil, frame, template)
		if ok and made then
			glow = made
			-- Alerts normally live for two seconds and hand themselves
			-- back to the game's manager; ours stay as long as shown.
			if glow.SetManualRelease then
				glow:SetManualRelease(true)
			end
			glow:SetScript("OnUpdate", nil)
			glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 8)
			glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -8)
			glow:SetFrameLevel(frame:GetFrameLevel() + 2)
			glow:Hide()
		else
			glow = false
		end
		frame.glows[template] = glow
	end
	return glow or nil
end

local function ShowGlow(frame, on)
	local want
	if on and db.glow ~= "off" then
		local styles = GLOW_TEMPLATES[db.glow] or GLOW_TEMPLATES.flash
		want = styles[db.glowColor] or styles.gold
	end
	for template, glow in pairs(frame.glows or {}) do
		if glow and template ~= want then
			glow:Hide()
		end
	end
	if want then
		local glow = GlowFrame(frame, want)
		if glow then
			glow:Show()
		end
	end
end

------------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------------

local bar = CreateFrame("Frame", "CooldownNagBar", UIParent)
bar:SetSize(ICON, ICON)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:RegisterForDrag("LeftButton")
bar:EnableMouse(false)
bar:Hide()

local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("BOTTOM", bar, "TOP", 0, 6)
label:SetText("CooldownNag: drag to move")
label:Hide()

local icons = {}

local function SavePosition()
	local point, _, _, x, y = bar:GetPoint(1)
	db.point = { point, x, y }
end

bar:SetScript("OnDragStart", function()
	if not db.locked then
		bar:StartMoving()
	end
end)
bar:SetScript("OnDragStop", function()
	bar:StopMovingOrSizing()
	SavePosition()
end)

local function BarIcon(i)
	if icons[i] then
		return icons[i]
	end
	local frame = CreateFrame("Frame", "CooldownNagIcon" .. i, bar)
	StyleIcon(frame)
	frame.Count:Hide()
	-- The last seconds of the cooldown, as the Cooldown Manager draws
	-- them: a sweep with the game's own countdown on it.
	local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	cooldown:SetHideCountdownNumbers(false)
	pcall(cooldown.SetSwipeTexture, cooldown, "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.7)
	cooldown:SetFrameLevel(frame:GetFrameLevel() + 1)
	frame.Cooldown = cooldown
	frame:SetPoint("LEFT", bar, "LEFT", (i - 1) * (ICON + GAP), 0)
	icons[i] = frame
	return frame
end

-- The bar can be dragged only while it is being previewed: the rest of
-- the time it takes no clicks, as it comes and goes on its own.
local function ApplyLayout()
	bar:SetScale(db.scale)
	bar:ClearAllPoints()
	bar:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
	label:SetShown(previewing and not db.locked)
	bar:EnableMouse(previewing and not db.locked)
end

-- The watched entries, in catalogue order.
local function ListWatched()
	wipe(watched)
	for _, name in ipairs(catalogOrder) do
		if cdb.watch[name] and #watched < MAX_ICONS then
			watched[#watched + 1] = catalog[name]
		end
	end
end

local function PlayReadySound()
	if not db.sound then
		return
	end
	pcall(PlaySound, db.soundKit or PING)
end

-- shown: list of { entry, state }, state "soon" (the last seconds, with
-- the sweep and countdown) or "ready" (the glow).
local function Draw(shown)
	for i, item in ipairs(shown) do
		local frame = BarIcon(i)
		local entry = item.entry
		frame.Icon:SetTexture(entry.icon or QUESTION_MARK)
		if item.state == "soon" then
			frame.Icon:SetDesaturated(true)
			frame.Cooldown:SetCooldown(entry.endsAt - entry.total, entry.total)
			ShowGlow(frame, false)
		else
			frame.Icon:SetDesaturated(false)
			frame.Cooldown:Clear()
			ShowGlow(frame, true)
		end
		frame:Show()
	end
	for i = #shown + 1, #icons do
		icons[i]:Hide()
	end
	bar:SetWidth(math.max(ICON, #shown * (ICON + GAP) - GAP))
	bar:SetShown(#shown > 0 or previewing)
end

------------------------------------------------------------------------------
-- Watching
------------------------------------------------------------------------------

local Evaluate

-- While something is on the bar, or the game is drawing it, look every
-- tenth of a second; otherwise wake up when the first watched ability
-- gets close.
local driver = CreateFrame("Frame")
local elapsedSince = 0
local function OnUpdate(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince >= 0.1 then
		elapsedSince = 0
		Evaluate()
	end
end

local function WakeAt(when)
	evaluateToken = evaluateToken + 1
	local token = evaluateToken
	C_Timer.After(math.max(0.05, when - GetTime() + 0.02), function()
		if token == evaluateToken then
			Evaluate()
		end
	end)
end

local function Ready(entry, now)
	entry.armed = false
	entry.endsAt = nil
	entry.exact = nil
	entry.lingerUntil = now + db.linger
end

-- The cooldown length to reckon with: the real one, once seen, else the
-- spell data's.
local function Length(entry)
	return cdb.lengths[entry.name] or entry.cooldown
end

function Evaluate()
	local now = GetTime()
	local shown = {}
	local nextAt
	local announce = false
	for _, entry in ipairs(watched) do
		local state
		if previewing then
			state = "ready"
		else
			local kind, left, total = ReadCooldown(entry.name)
			if kind == "open" then
				-- The game's own numbers: they overrule the clock, and the
				-- real length is kept for the next reckoning.
				entry.armed = true -- it will come ready, and that is worth telling
				entry.endsAt = now + left
				entry.total = total
				entry.exact = true
				entry.lingerUntil = nil
				if total > GCD_MAX then
					cdb.lengths[entry.name] = total
				end
			elseif kind == "ready" then
				if entry.armed then
					Ready(entry, now)
					announce = true
				end
				entry.endsAt = nil
			end
			-- From here the clock decides, whoever set it.
			if entry.armed and entry.endsAt then
				if now >= entry.endsAt then
					Ready(entry, now)
					announce = true
				elseif entry.endsAt - now <= db.soon then
					state = "soon"
				else
					local at = entry.endsAt - db.soon
					nextAt = (nextAt and nextAt < at) and nextAt or at
				end
			end
			if not state then
				if entry.lingerUntil and now < entry.lingerUntil then
					state = "ready"
				else
					entry.lingerUntil = nil
				end
			end
		end
		if state then
			shown[#shown + 1] = { entry = entry, state = state }
		end
	end
	if announce then
		PlayReadySound()
	end
	Draw(shown)
	if #shown > 0 then
		driver:SetScript("OnUpdate", OnUpdate)
	else
		driver:SetScript("OnUpdate", nil)
		if nextAt then
			WakeAt(nextAt)
		end
	end
end

-- A cast of a watched ability starts the clock, unless the game is telling
-- the numbers itself right now.
local function NoteCast(spellID)
	local name = SpellName(spellID)
	local entry = name and catalog[name]
	if not (entry and cdb.watch[name]) then
		return
	end
	local length = Length(entry)
	if not (length and length > GCD_MAX) then
		return
	end
	local kind = ReadCooldown(name)
	if kind == "secret" or kind == nil then
		entry.armed = true
		entry.endsAt = GetTime() + length
		entry.total = length
		entry.exact = nil
		entry.lingerUntil = nil
	end
end

------------------------------------------------------------------------------
-- Sounds: the Cooldown Manager's own list, by name
------------------------------------------------------------------------------

local function EachSound(fn)
	local data = CooldownViewerSoundData
	if type(data) ~= "table" then
		return false
	end
	local categories = {}
	for category in pairs(data) do
		categories[#categories + 1] = category
	end
	table.sort(categories)
	for _, category in ipairs(categories) do
		for _, sound in ipairs(data[category]) do
			if sound.soundKitID and type(sound.text) == "string" then
				fn(sound.text, sound.soundKitID, category)
			end
		end
	end
	return true
end

local function SoundName(kit)
	if kit == PING then
		return "ping"
	end
	local found
	EachSound(function(text, soundKitID)
		if soundKitID == kit then
			found = text
		end
	end)
	return found or tostring(kit)
end

local function FindSound(words)
	if words == "ping" then
		return PING
	end
	local exact, partial
	EachSound(function(text, soundKitID)
		local lower = text:lower()
		if lower == words then
			exact = soundKitID
		elseif lower:find(words, 1, true) then
			partial = partial or soundKitID
		end
	end)
	return exact or partial
end

------------------------------------------------------------------------------
-- The tab in the Cooldown Manager's settings
------------------------------------------------------------------------------

local panel -- our page inside the settings window
local settingsTab
local COLUMNS = 7

-- Taint: nothing here may write into the game's own tables (the settings
-- window's fields, its tab list), or the game's code reading them later
-- runs tainted and its protected tables refuse it. The tab lives on a
-- frame of ours, the window's own state is only read, and the window's
-- pages are shown or hidden from hooks that run after its own code.

local function ShowGamePages(settings)
	local mode = settings.displayMode
	if settings.CooldownScroll then
		settings.CooldownScroll:SetShown(mode ~= "groupBuffs")
	end
	if settings.GroupBuffFilter then
		settings.GroupBuffFilter:SetShown(mode == "groupBuffs")
	end
end

local function ShowPanel()
	local settings = CooldownViewerSettings
	if not (settings and panel) then
		return
	end
	for _, tab in ipairs(settings.TabButtons or {}) do
		tab:SetChecked(false)
	end
	-- BuffNag's tab, when it has one, is not in the game's list.
	if BuffNagSettingsTab and BuffNagSettingsTab.SetChecked then
		BuffNagSettingsTab:SetChecked(false)
	end
	if BuffNagSettingsPanel then
		BuffNagSettingsPanel:Hide()
	end
	if settingsTab then
		settingsTab:SetChecked(true)
	end
	if settings.CooldownScroll then
		settings.CooldownScroll:Hide()
	end
	if settings.GroupBuffFilter then
		settings.GroupBuffFilter:Hide()
	end
	if CooldownViewerSettingsEditAlert then
		CooldownViewerSettingsEditAlert:Hide()
	end
	panel:Show()
end

local function HidePanel(settings)
	if panel and panel:IsShown() then
		panel:Hide()
		settingsTab:SetChecked(false)
		ShowGamePages(settings)
	end
end

local function SetPreview(on)
	previewing = on
	ApplyLayout()
	Evaluate()
end

local function BuildPanel(settings)
	panel = CreateFrame("Frame", "CooldownNagSettingsPanel", settings)
	panel:SetPoint("TOPLEFT", 17, -72)
	panel:SetPoint("BOTTOMRIGHT", -30, 29)
	panel:Hide()

	local function Checkbox(text, x, y, get, set)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(24, 24)
		box:SetPoint("TOPLEFT", x, y)
		local caption = box.Text or box.text
		if caption then
			caption:SetText(text)
			caption:SetFontObject("GameFontHighlightSmall")
		end
		box:SetScript("OnShow", function(self)
			self:SetChecked(get())
		end)
		box:SetScript("OnClick", function(self)
			set(self:GetChecked() and true or false)
			ApplyLayout()
			Evaluate()
		end)
		return box
	end
	Checkbox("Sound", 0, 0, function() return db.sound end, function(v) db.sound = v end)
	Checkbox("Glow", 90, 0, function() return db.glow ~= "off" end, function(v) db.glow = v and "flash" or "off" end)
	Checkbox("Lock bar", 180, 0, function() return db.locked end, function(v) db.locked = v end)
	local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	test:SetSize(70, 22)
	test:SetPoint("TOPRIGHT", 0, -1)
	test:SetText("Show bar")
	test:SetScript("OnClick", function()
		if not previewing and #watched == 0 then
			Print("nothing is watched yet: click an ability below")
			return
		end
		SetPreview(not previewing)
		test:SetText(previewing and "Hide bar" or "Show bar")
	end)

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 4, -30)
	help:SetPoint("RIGHT", -4, 0)
	help:SetJustifyH("LEFT")
	panel.help = help
	function panel:RefreshHelp()
		help:SetText(("Click an ability to watch it or stop. A watched ability pops up %g seconds before it is ready and stays %g seconds once it is (/cdn soon, /cdn linger). Sound: %s (/cdn sound)."):format(
			db.soon, db.linger, db.sound and SoundName(db.soundKit) or "off"))
	end

	local scroll
	local okScroll = pcall(function()
		scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	end)
	if not okScroll or not scroll then
		scroll = CreateFrame("ScrollFrame", nil, panel)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local range = math.max(0, self:GetScrollChild():GetHeight() - self:GetHeight())
			self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	scroll:SetPoint("TOPLEFT", 0, -74)
	scroll:SetPoint("BOTTOMRIGHT", -16, 0)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(300, 1)
	scroll:SetScrollChild(content)

	-- Two sections, headed like the Cooldown Manager's own categories.
	local SECTIONS = { { watched = true, label = "Watched" }, { watched = false, label = "Not Displayed" } }
	local sections = {}
	for i, def in ipairs(SECTIONS) do
		local section = CreateFrame("Frame", nil, content)
		section:SetPoint("LEFT", content, "LEFT", 0, 0)
		section:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		local header
		local okHeader = pcall(function()
			header = CreateFrame("Button", nil, section, "ListHeaderThreeSliceTemplate")
		end)
		if okHeader and header and header.Name then
			header:SetHeight(22)
			header.Name:SetText(def.label)
			header:SetScript("OnClick", nil)
			header:EnableMouse(false)
			pcall(header.UpdateCollapsedState, header, false)
		else
			header = CreateFrame("Frame", nil, section)
			header:SetHeight(22)
			local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			text:SetPoint("LEFT", 10, 0)
			text:SetText(def.label)
		end
		header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
		header:SetPoint("TOPRIGHT", section, "TOPRIGHT", -4, 0)
		sections[i] = section
	end

	local buttons = {}
	local function PanelButton(i)
		if buttons[i] then
			return buttons[i]
		end
		local button = CreateFrame("Button", nil, content)
		StyleIcon(button)
		button.Count:SetFontObject("NumberFontNormalSmall")
		button:RegisterForClicks("LeftButtonUp")
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.entry.name)
			GameTooltip:AddLine(self.entry.cooldown and ("%s cooldown"):format(CooldownText(self.entry.cooldown)) or "Cooldown unknown until cast", 1, 1, 1)
			GameTooltip:AddLine(cdb.watch[self.entry.name] and "Watched. Click to stop." or "Click to watch.", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:SetScript("OnClick", function(self)
			local name = self.entry.name
			if cdb.watch[name] then
				cdb.watch[name] = nil
			else
				cdb.watch[name] = true
			end
			PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
			panel:Layout()
			ListWatched()
			Evaluate()
		end)
		buttons[i] = button
		return button
	end

	function panel:Layout()
		local used = 0
		local y = 0
		local step = ICON + 8
		local function Fill(section, names, dimmed)
			section:ClearAllPoints()
			section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			section:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
			local top = y
			y = y + 22 + 12
			for n, name in ipairs(names) do
				used = used + 1
				local button = PanelButton(used)
				button.entry = catalog[name]
				button.Icon:SetTexture(button.entry.icon or QUESTION_MARK)
				button.Icon:SetDesaturated(dimmed)
				button.Count:SetText(button.entry.cooldown and CooldownText(button.entry.cooldown) or "")
				local column, row = (n - 1) % COLUMNS, math.floor((n - 1) / COLUMNS)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + column * step, -(y + row * step))
				button:Show()
			end
			y = y + math.max(1, math.ceil(#names / COLUMNS)) * step + 8
			section:SetHeight(y - top)
		end
		local on, off = {}, {}
		for _, name in ipairs(catalogOrder) do
			if cdb.watch[name] then
				on[#on + 1] = name
			else
				off[#off + 1] = name
			end
		end
		Fill(sections[1], on, false)
		Fill(sections[2], off, true)
		for i = used + 1, #buttons do
			buttons[i]:Hide()
		end
		content:SetSize(math.max(300, scroll:GetWidth()), math.max(1, y))
		self:RefreshHelp()
	end

	panel:SetScript("OnShow", function(self)
		self:Layout()
	end)
	panel:SetScript("OnHide", function()
		if previewing then
			SetPreview(false)
			test:SetText("Show bar")
		end
	end)
end

local function HookSettings()
	local settings = CooldownViewerSettings
	if not settings or settingsTab then
		return
	end
	BuildPanel(settings)

	-- The tab: made from the game's own tab template for the look, but
	-- parented to a frame of ours so the template does not add it to the
	-- window's tab list.
	local holder = CreateFrame("Frame", "CooldownNagSettingsTabHolder", settings)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT")
	local ok = pcall(function()
		settingsTab = CreateFrame("Frame", "CooldownNagSettingsTab", holder, "CooldownViewerSettingsTabTemplate")
	end)
	if not ok or not settingsTab then
		settingsTab = nil
		Print("could not add a tab to the Cooldown Manager settings; use /cdn to configure")
		return
	end
	settingsTab.tooltipText = "CooldownNag: abilities to announce when they come off cooldown"
	-- Below BuffNag's tab when it is there, else below the game's last.
	local anchor = BuffNagSettingsTab or settings.GroupBuffsTab or settings.AurasTab or settings.SpellsTab
	if anchor then
		settingsTab:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
	else
		settingsTab:SetPoint("TOPLEFT", settings, "TOPRIGHT", 0, -250)
	end
	settingsTab.Icon:SetSize(34, 34)
	settingsTab.Icon:SetTexture(TAB_ICON)
	settingsTab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	settingsTab:SetChecked(false)
	if settingsTab.SetCustomOnMouseUpHandler then
		settingsTab:SetCustomOnMouseUpHandler(function(_, button, upInside)
			if button == "LeftButton" and upInside then
				ShowPanel()
			end
		end)
	end
	-- A click on one of the game's tabs runs SetDisplayMode, even when it
	-- is the tab that was already current and the game returns early: put
	-- its page back and ours away. Closing the window does the same, so it
	-- reopens on the game's page as usual.
	hooksecurefunc(settings, "SetDisplayMode", HidePanel)
	settings:HookScript("OnHide", HidePanel)
	-- BuffNag's tab, clicked, shows its own page over ours.
	if BuffNagSettingsPanel then
		BuffNagSettingsPanel:HookScript("OnShow", function()
			if panel:IsShown() then
				panel:Hide()
				settingsTab:SetChecked(false)
			end
		end)
	end
end

local function OpenSettings()
	if not CooldownViewerSettings then
		Print("the Cooldown Manager is not available on this client")
		return
	end
	HookSettings()
	if not CooldownViewerSettings:IsShown() then
		ShowUIPanel(CooldownViewerSettings)
	end
	ShowPanel()
end

------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------

local function Rebuild()
	ScanSpellbook()
	BuildCatalog()
	SeedChoices()
	catalogDirty = false
	if panel and panel:IsShown() then
		panel:Layout()
	end
	ListWatched()
	Evaluate()
end

-- A spell from the book by name, case blind.
local function BookSpell(words)
	if book[words] then
		return words
	end
	words = words:lower()
	for _, name in ipairs(bookOrder) do
		if name:lower() == words then
			return name
		end
	end
end

-- What the game is willing to tell right now, and what the clock says, for
-- when the bar does not behave.
local function Debug()
	local okSecret, secret = pcall(function()
		return C_Secrets and C_Secrets.ShouldCooldownsBeSecret and C_Secrets.ShouldCooldownsBeSecret()
	end)
	Print("cooldowns secret now: %s; in combat: %s", okSecret and tostring(secret) or "unknown", tostring(InCombatLockdown()))
	local now = GetTime()
	for _, entry in ipairs(watched) do
		local kind, left, total = ReadCooldown(entry.name)
		local game = tostring(kind)
		if kind == "open" then
			game = ("%.1f of %.1f s left"):format(left, total)
		end
		local clock = "idle"
		if entry.armed and entry.endsAt then
			clock = ("%.1f s left (%s)"):format(entry.endsAt - now, entry.exact and "from the game" or "reckoned")
		elseif entry.lingerUntil then
			clock = "lingering"
		end
		Print("  %s: game says %s; clock %s; length %s", entry.name, game, clock, CooldownText(Length(entry)))
	end
end

SLASH_COOLDOWNNAG1 = "/cdn"
SLASH_COOLDOWNNAG2 = "/cooldownnag"
SlashCmdList.COOLDOWNNAG = function(msg)
	local word, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	word = word:lower()
	if word == "" or word == "config" or word == "options" then
		OpenSettings()
		return
	elseif word == "soon" then
		db.soon = math.max(1, math.min(60, tonumber(rest) or DEFAULTS.soon))
		Print("icons appear %g seconds before an ability is ready", db.soon)
	elseif word == "linger" then
		db.linger = math.max(0, math.min(60, tonumber(rest) or DEFAULTS.linger))
		Print("icons stay %g seconds once it is", db.linger)
	elseif word == "sound" then
		local lower = rest:lower()
		if lower == "on" or lower == "off" then
			db.sound = lower == "on"
		elseif lower == "list" then
			if not EachSound(function() end) then
				Print("the Cooldown Manager's sound list is not loaded; /cdn sound ping is always there")
				return
			end
			local lines, current = {}, nil
			EachSound(function(text, _, category)
				if category ~= current then
					current = category
					lines[#lines + 1] = {}
				end
				local line = lines[#lines]
				line[#line + 1] = text
			end)
			Print("sounds (/cdn sound <name>, or ping):")
			for _, line in ipairs(lines) do
				Print("  " .. table.concat(line, ", "))
			end
			return
		elseif lower == "test" or lower == "" then
			pcall(PlaySound, db.soundKit or PING)
			Print("sound: %s%s", SoundName(db.soundKit), db.sound and "" or " (off)")
			return
		else
			local kit = FindSound(lower)
			if not kit then
				Print("no sound called %q; /cdn sound list", rest)
				return
			end
			db.soundKit = kit
			db.sound = true
			pcall(PlaySound, kit)
			Print("sound: %s", SoundName(kit))
		end
	elseif word == "glow" then
		if rest == "flash" or rest == "ants" or rest == "off" then
			db.glow = rest
		elseif rest == "on" then
			db.glow = "flash"
		else
			Print("/cdn glow flash|ants|off; /cdn glowcolor gold|cyan|red|green|blue")
			return
		end
	elseif word == "glowcolor" then
		if GLOW_TEMPLATES.flash[rest:lower()] then
			db.glowColor = rest:lower()
		else
			Print("/cdn glowcolor gold|cyan|red|green|blue")
			return
		end
	elseif word == "lock" or word == "unlock" then
		db.locked = word == "lock"
	elseif word == "scale" then
		db.scale = math.max(0.5, math.min(3, tonumber(rest) or 1))
	elseif word == "min" then
		db.minCooldown = math.max(1, math.min(3600, tonumber(rest) or DEFAULTS.minCooldown))
		Print("abilities with a cooldown of %g seconds or more are listed", db.minCooldown)
		Rebuild()
		return
	elseif word == "watch" or word == "unwatch" then
		local name = BookSpell(rest)
		if not name then
			Print("no spell called %q in the spellbook", rest)
			return
		end
		if word == "watch" then
			cdb.extra[name] = true
			cdb.watch[name] = true
			Print("watching %s", name)
		else
			cdb.watch[name] = nil
			cdb.extra[name] = nil
			Print("no longer watching %s", name)
		end
		Rebuild()
		return
	elseif word == "list" then
		Print("watching:")
		for _, entry in ipairs(watched) do
			Print("  %s (%s)", entry.name, CooldownText(Length(entry)))
		end
		return
	elseif word == "test" then
		SetPreview(not previewing)
		Print("bar preview %s", previewing and "on" or "off")
		return
	elseif word == "debug" then
		Debug()
		return
	elseif word == "reset" then
		db.point = { DEFAULTS.point[1], DEFAULTS.point[2], DEFAULTS.point[3] }
	else
		Print("/cdn opens the settings; /cdn soon <seconds>; /cdn linger <seconds>; /cdn sound on|off|list|test|<name>; /cdn glow flash|ants|off; /cdn glowcolor <colour>; /cdn lock|unlock; /cdn scale <n>; /cdn min <seconds>; /cdn watch|unwatch <spell>; /cdn list; /cdn test; /cdn debug; /cdn reset")
		return
	end
	ApplyLayout()
	if panel and panel:IsShown() then
		panel:RefreshHelp()
	end
	Evaluate()
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("SPELLS_CHANGED")
loader:RegisterEvent("SPELL_UPDATE_COOLDOWN")
pcall(loader.RegisterEvent, loader, "SPELL_UPDATE_CHARGES")
pcall(loader.RegisterEvent, loader, "COOLDOWN_VIEWER_DATA_LOADED")
pcall(loader.RegisterUnitEvent, loader, "UNIT_SPELLCAST_SUCCEEDED", "player")
local learnedAt = 0
loader:SetScript("OnEvent", function(self, event, arg, _, spellID)
	if event == "ADDON_LOADED" then
		if arg == ADDON_NAME then
			CooldownNagDB = CooldownNagDB or {}
			db = CooldownNagDB
			for key, value in pairs(DEFAULTS) do
				if db[key] == nil then
					db[key] = type(value) == "table" and CopyTable(value) or value
				end
			end
			CooldownNagCharDB = CooldownNagCharDB or {}
			cdb = CooldownNagCharDB
			cdb.watch = cdb.watch or {} -- spell name -> true
			cdb.extra = cdb.extra or {} -- spells added by /cdn watch, listed whatever their cooldown
			cdb.learned = cdb.learned or {} -- spell name -> cooldown seconds seen
			cdb.lengths = cdb.lengths or {} -- spell name -> the real cooldown length last seen
		elseif arg == "Blizzard_CooldownViewer" and db then
			HookSettings()
		end
	elseif not db then
		return
	elseif event == "PLAYER_LOGIN" then
		Rebuild()
		ApplyLayout()
		HookSettings()
		if #watched == 0 then
			Print("nothing watched yet: /cdn to pick abilities")
		end
	elseif event == "SPELLS_CHANGED" or event == "COOLDOWN_VIEWER_DATA_LOADED" then
		Rebuild()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		pcall(NoteCast, spellID)
		Evaluate()
	elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
		local now = GetTime()
		if now - learnedAt > 0.5 then
			learnedAt = now
			LearnCooldowns()
			if catalogDirty then
				Rebuild()
				return
			end
		end
		Evaluate()
	else
		Evaluate()
	end
end)
