-- CombatScroll: scrolling combat text in two columns. What you take
-- (damage, heals, misses) falls down a column on the left; what you deal
-- and heal rises up a column on the right.
--
-- Where things come from (Blizzard UI source, 1.60.1 build 70888; not yet
-- verified in game):
-- - Every number comes from UNIT_COMBAT (unit, event, flags, amount,
--   school). The amount is a secret value: it can be put on screen with
--   FontString:SetFormattedText but not compared or added up. The event
--   ("WOUND", "HEAL", "DODGE", ...), the flags ("CRITICAL", ...) and the
--   school mask are plain.
-- - Incoming: UNIT_COMBAT for "player", and for "pet" (its damage
--   taken, smaller).
-- - Outgoing: UNIT_COMBAT does not say who made a hit, and the combat log
--   itself is closed to addons. What an addon can see is COMBAT_LOG_MESSAGE,
--   the event that adds a line to the Combat Log tab: its text is
--   protected, but its colour is not, and it arrives in the same frame as
--   the hit. With the combat log filter set to "my actions" (me and my
--   pet) and each kind of line given a colour of its own, a line of a given
--   colour says "you just did this kind of thing"; it is paired with a
--   UNIT_COMBAT of that kind on an enemy (damage, miss) or a friend (heal)
--   from the same frame. A hit with no line of yours is someone else's and
--   is not shown. Where several hits of one kind land in one frame, the
--   pairing goes by order and can pick the wrong one.
-- - /cscroll setup writes that filter into Blizzard's own saved combat log
--   filters (Blizzard_CombatLog_Filters, account-wide) and reloads, so that
--   Blizzard reads it untainted. /cscroll undo takes it out again.
-- - /cscroll setup also switches Blizzard's own floating combat text off
--   (the game options in BLIZZARD_TEXT), keeping what each was;
--   /cscroll undo puts them back.
-- - Blizzard switches combat log lines off whenever the Combat Log tab is
--   hidden (COMBATLOG OnHide calls C_CombatLog.SetFilteredEventsEnabled
--   (false)); this addon switches them back on after it.
--
-- Icons on your own hits: see the Icons section. Icons on the hits you
-- take: see Hits you take.
--
-- /cscroll: unlock, lock, test, setup, undo, scale <n>, reset, stats,
-- debug, window <0-3>.

local ADDON, ns = ...
local CanAccess = canaccessvalue or function() return true end

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local SIZE, CRIT_SIZE = 15, 24
local PET_SIZE, PET_CRIT_SIZE = 13, 18 -- your pet's damage taken
local DISTANCE = 220 -- how far a line travels before it is gone
local SPEED = 95 -- pixels a second
local SPACING = 26 -- the closest two lines may be; above ICON_SIZE so icons do not overlap
local FADE_FROM = 0.7 -- share of DISTANCE after which a line fades out
local LANE_WIDTH = 160
local STACK_WINDOW = 0.8 -- seconds in which hits of one spell share a line
-- Sticky crits: a crit does not scroll. It lands at STICKY_AT along its
-- column with an impact (see CritImpact: it punches in to POW times its
-- size, springs back with a small bounce, flashes white and shakes),
-- holds still for STICKY_HOLD seconds and fades out in place over
-- STICKY_FADE. A newer crit takes the spot and pushes older ones outward.
-- Text height is animated with SetTextHeight, as Blizzard's combat text
-- does for its crits.
local STICKY_AT = 100
-- ...and STICKY_SIDE pixels to the side, away from the screen centre, so
-- the scrolling lines pass beside a crit instead of over it.
local STICKY_SIDE = 70
local POW = 2.3 -- peak size, times the crit's resting size
local POW_IN = 0.07 -- seconds to reach the peak
local SPRING_DAMP, SPRING_FREQ = 16, 22 -- the bounce back: decay, radians a second
local SETTLED = 0.4 -- seconds after which the bounce is done
local FLASH, FLASH_OUT = 0.08, 0.08 -- white for this long, then back to colour over this long
local SHAKE, SHAKE_PX, SHAKE_FREQ = 0.22, 4, 90 -- seconds, pixels, radians a second
local STICKY_HOLD, STICKY_FADE = 1.5, 0.4

-- A crit's size (times its resting size), colour mix towards white and
-- sideways shake, t seconds after it landed.
local function CritImpact(t)
	local scale
	if t < POW_IN then
		local u = t / POW_IN
		scale = 1 + (POW - 1) * (1 - (1 - u) * (1 - u)) -- ease out
	else
		local tau = t - POW_IN
		scale = 1 + (POW - 1) * math.exp(-SPRING_DAMP * tau) * math.cos(SPRING_FREQ * tau)
	end
	local white = t < FLASH and 1 or math.max(0, 1 - (t - FLASH) / FLASH_OUT)
	local shake = t < SHAKE and SHAKE_PX * (1 - t / SHAKE) * math.sin(SHAKE_FREQ * t) or 0
	return scale, white, shake
end

-- How many frames apart a combat log line and its hit may arrive (saved as
-- db.window). The other addon that does this says "the same instant";
-- /cscroll debug shows whether that holds, /cscroll window <n> widens it.
local WINDOW = 0
-- Unmatched lines and hits are thrown away once they are this many frames
-- older than WINDOW allows.
local KEEP = 2

local FILTER_NAME = "CombatScroll"

-- The line colour Blizzard gives each combat log event in our filter
-- (settings.lineColoring with lineColorPriority 3 = by event). Each is
-- unique, so the colour of a COMBAT_LOG_MESSAGE names its event; they
-- also stay readable in the Combat Log tab.
local EVENT_COLORS = {
	SWING_DAMAGE = { 0.93, 0.93, 0.93, "damage" },
	RANGE_DAMAGE = { 0.93, 0.93, 0.78, "damage" },
	SPELL_DAMAGE = { 1.00, 0.82, 0.30, "damage" },
	SPELL_PERIODIC_DAMAGE = { 0.90, 0.68, 0.30, "damage" },
	DAMAGE_SHIELD = { 0.90, 0.58, 0.58, "damage" },
	DAMAGE_SPLIT = { 0.84, 0.52, 0.52, "damage" },
	SWING_MISSED = { 0.60, 0.60, 0.68, "miss" },
	RANGE_MISSED = { 0.60, 0.64, 0.68, "miss" },
	SPELL_MISSED = { 0.64, 0.60, 0.68, "miss" },
	SPELL_PERIODIC_MISSED = { 0.64, 0.64, 0.72, "miss" },
	DAMAGE_SHIELD_MISSED = { 0.56, 0.56, 0.64, "miss" },
	SPELL_HEAL = { 0.30, 1.00, 0.30, "heal" },
	SPELL_PERIODIC_HEAL = { 0.30, 0.84, 0.42, "heal" },
}
local COLOR_TOLERANCE = 0.01
for event, c in pairs(EVENT_COLORS) do
	c.event = event
end
-- Blizzard looks a spell miss's colour up under SPELL_MISSED_<miss type>,
-- not SPELL_MISSED (Blizzard_CombatLogProcessor.lua, build 70959; the
-- other _MISSED events keep their name unless the filter asks for full
-- text). Without a colour under that name the line turns a default grey.
-- The types are those the game has an ACTION_SPELL_MISSED_ string for.
local SPELL_MISS_TYPES = { "ABSORB", "BLOCK", "DEFLECT", "DODGE", "EVADE", "IMMUNE", "MISFIRE", "MISS", "PARRY", "REFLECT", "RESIST" }

-- UNIT_COMBAT events that are a miss of some kind (CombatFeedback.lua).
local MISS_TEXT = {
	MISS = "COMBAT_TEXT_MISS",
	DODGE = "COMBAT_TEXT_DODGE",
	PARRY = "COMBAT_TEXT_PARRY",
	BLOCK = "COMBAT_TEXT_BLOCK",
	RESIST = "COMBAT_TEXT_RESIST",
	IMMUNE = "COMBAT_TEXT_IMMUNE",
	EVADE = "COMBAT_TEXT_EVADE",
	DEFLECT = "COMBAT_TEXT_DEFLECT",
	REFLECT = "COMBAT_TEXT_REFLECT",
	ABSORB = "COMBAT_TEXT_ABSORB",
}
-- WOUND flags that mean (part of) the hit did not land.
local WOUND_WORDS = { ABSORB = true, BLOCK = true, RESIST = true }

-- Text colours, matched to the bars of the user's unit frame and nameplate
-- (sampled from screenshots, 2026-11-18). Those bars run dark to light;
-- their light right ends set the character: strongly saturated (OKLCH
-- chroma about 0.19) at mid lightness (L 0.52 to 0.71). Heals are the
-- health bar's right end; damage, dealt or taken, has its school's colour; holy and
-- physical are the frame's name gold and name white. The other schools sit
-- in the same band; frost takes the mana bar's hue, lifted to read as
-- text; nature is emerald (h 160) to stay clear of the heal green (h 136).
local SCHOOL_COLORS = {
	[1] = { 0.97, 0.97, 0.97 }, -- physical: name white #f8f8f8
	[2] = { 0.97, 0.82, 0.00 }, -- holy: name gold #f8d000
	[4] = { 0.97, 0.44, 0.01 }, -- fire: L 0.70, C 0.19, h 48
	[8] = { 0.04, 0.79, 0.52 }, -- nature: L 0.74, C 0.17, h 160
	[16] = { 0.22, 0.53, 1.00 }, -- frost: L 0.64, C 0.19, h 259 (mana bar hue)
	[32] = { 0.61, 0.38, 0.92 }, -- shadow: L 0.62, C 0.20, h 300
	[64] = { 0.90, 0.31, 0.69 }, -- arcane: L 0.66, C 0.21, h 345
}
-- A mixed school takes the colour of its first non-physical school.
local SCHOOL_ORDER = { 2, 4, 8, 16, 32, 64, 1 }
local HEAL = { 0.41, 0.74, 0.18 } -- health bar's right end #68bc2d
local MISS = { 0.69, 0.69, 0.69 } -- L 0.76, grey
-- A line with an icon: the icon already says what it was, so the number
-- stays plain instead of taking the colours above. Heals stay green.
local PLAIN = SCHOOL_COLORS[1]

local BG = { 0.04, 0.04, 0.05, 0.85 }

local DEFAULTS = {
	scale = 1,
	window = WINDOW,
}

local db
local lanes = {}
local unlocked = false
local debug = false

local function Debug(...)
	if debug then
		print("|cffffd100CombatScroll|r", ...)
	end
end

-- Matching state ---------------------------------------------------------

local frameNo, frameTime = 0, nil
local lines = {} -- { frame, kind, used }
local hits = {} -- { frame, event, flags, amount, school, role, used }
local stats = { lines = 0, hits = 0, matched = 0, lostLines = 0, lostHits = 0 }

-- The frame an event belongs to. GetTime() stays the same for a whole
-- frame, so events from one frame share a number whether they come before
-- or after this addon's OnUpdate.
local function CurrentFrame()
	local t = GetTime()
	if t ~= frameTime then
		frameTime = t
		frameNo = frameNo + 1
	end
	return frameNo
end

local function Word(event)
	local key = MISS_TEXT[event]
	local text = key and _G[key]
	if text then
		return text
	end
	return event:sub(1, 1) .. event:sub(2):lower()
end

local function SchoolColor(school)
	if not CanAccess(school) or type(school) ~= "number" then
		return SCHOOL_COLORS[1]
	end
	for _, bitValue in ipairs(SCHOOL_ORDER) do
		if bit.band(school, bitValue) ~= 0 then
			return SCHOOL_COLORS[bitValue]
		end
	end
	return SCHOOL_COLORS[1]
end

local function IsZero(amount)
	return CanAccess(amount) and amount == 0
end

-- Lanes -------------------------------------------------------------------

local Spawn -- defined below the lanes
local IconFor -- defined below, with the icons

local function SavePosition(lane)
	local point, _, relPoint, x, y = lane.anchor:GetPoint(1)
	db[lane.key] = { point, relPoint, x, y }
end

local function PlaceLane(lane)
	local a = lane.anchor
	a:ClearAllPoints()
	local p = db[lane.key]
	if p then
		a:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		a:SetPoint("CENTER", UIParent, "CENTER", lane.x, lane.y)
	end
	a:SetScale(db.scale or 1)
end

-- Icon dressing ----------------------------------------------------------
--
-- The Cooldown Manager's icon dressing, as BuffNag, LootFeed and the other
-- addons here use it: its rounded mask and border ring over the uncropped
-- picture, the ring reaching a fifth of the icon's size past it across and
-- a pixel less up and down. A cropped picture with a thin dark edge stands
-- in on a client without those atlases.

local ICON_GAP = 1 -- between the icon (with its ring) and the text
local ICON_SIZE, CRIT_ICON_SIZE = 24, 32 -- larger than the text beside them

local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

local rounded
local function Rounded()
	if rounded == nil then
		rounded = HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay")
	end
	return rounded
end

local function CreateLine(lane)
	local a = lane.anchor
	local line = { fs = a:CreateFontString(nil, "OVERLAY"), tex = a:CreateTexture(nil, "OVERLAY") }
	if Rounded() then
		local mask = a:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints(line.tex)
		line.tex:AddMaskTexture(mask)
		line.ring = a:CreateTexture(nil, "OVERLAY", nil, 1)
		line.ring:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
	else
		line.edge = a:CreateTexture(nil, "ARTWORK")
		line.edge:SetColorTexture(0, 0, 0, 1)
		line.edge:SetPoint("TOPLEFT", line.tex, "TOPLEFT", -1, 1)
		line.edge:SetPoint("BOTTOMRIGHT", line.tex, "BOTTOMRIGHT", 1, -1)
	end
	return line
end

-- size: the line's text height; the icon is line.iconScale times that, so
-- a crit's icon grows and bounces with its number.
local function SizeIcon(line, size)
	size = size * (line.iconScale or 1)
	local tex, ring = line.tex, line.ring
	tex:SetSize(size, size)
	local reach = ring and size * 0.2 or 1
	tex:ClearAllPoints()
	tex:SetPoint("RIGHT", line.fs, "LEFT", -(ICON_GAP + reach), 0)
	if ring then
		ring:ClearAllPoints()
		ring:SetPoint("TOPLEFT", tex, "TOPLEFT", -reach, reach - 1)
		ring:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", reach, -(reach - 1))
	end
end

local function ShowIcon(line, shown)
	line.tex:SetShown(shown)
	if line.ring then
		line.ring:SetShown(shown)
	end
	if line.edge then
		line.edge:SetShown(shown)
	end
end

local function IconAlpha(line, alpha)
	line.tex:SetAlpha(alpha)
	if line.ring then
		line.ring:SetAlpha(alpha)
	end
	if line.edge then
		line.edge:SetAlpha(alpha)
	end
end

local function OnLaneUpdate(lane, elapsed)
	local active = lane.active
	local i = 1
	while i <= #active do
		local line = active[i]
		if line.sticky then
			line.age = line.age + elapsed
		else
			line.offset = line.offset + SPEED * elapsed
		end
		if (line.sticky and line.age >= STICKY_HOLD + STICKY_FADE) or (not line.sticky and line.offset >= DISTANCE) then
			line.fs:Hide()
			ShowIcon(line, false)
			line.stack, line.sticky = nil, nil
			table.insert(lane.pool, line)
			table.remove(active, i)
		elseif line.sticky then
			local alpha = line.age < STICKY_HOLD and 1 or 1 - (line.age - STICKY_HOLD) / STICKY_FADE
			line.fs:SetAlpha(alpha)
			IconAlpha(line, alpha)
			local shake = 0
			if not line.settled then
				local scale, white
				scale, white, shake = CritImpact(line.age)
				local height = line.size * scale
				line.fs:SetTextHeight(height)
				SizeIcon(line, height)
				local c = line.color
				line.fs:SetTextColor(c[1] + (1 - c[1]) * white, c[2] + (1 - c[2]) * white, c[3] + (1 - c[3]) * white)
				if line.age >= SETTLED then
					line.fs:SetTextHeight(line.size)
					SizeIcon(line, line.size)
					line.settled = true
				end
			end
			line.fs:ClearAllPoints()
			line.fs:SetPoint(lane.dir > 0 and "BOTTOM" or "TOP", lane.anchor, lane.dir > 0 and "TOP" or "BOTTOM", lane.side * STICKY_SIDE + shake, lane.dir * (STICKY_AT + line.offset))
			i = i + 1
		else
			local share = line.offset / DISTANCE
			local alpha = share < FADE_FROM and 1 or (1 - share) / (1 - FADE_FROM)
			line.fs:SetAlpha(alpha)
			IconAlpha(line, alpha)
			line.fs:ClearAllPoints()
			line.fs:SetPoint(lane.dir > 0 and "BOTTOM" or "TOP", lane.anchor, lane.dir > 0 and "TOP" or "BOTTOM", 0, lane.dir * line.offset)
			i = i + 1
		end
	end
	if #active == 0 and not unlocked then
		lane.anchor:SetScript("OnUpdate", nil)
	end
end

local function CreateLane(key, label, dir, x, y)
	local a = CreateFrame("Frame", "CombatScroll" .. key, UIParent)
	a:SetSize(LANE_WIDTH, 20)
	a:SetFrameStrata("MEDIUM")
	a:SetMovable(true)
	a:SetClampedToScreen(true)
	a:EnableMouse(false)
	a:RegisterForDrag("LeftButton")
	local lane = { key = key, dir = dir, x = x, y = y, side = x < 0 and -1 or 1, anchor = a, active = {}, pool = {}, stacks = {} }
	a:SetScript("OnDragStart", a.StartMoving)
	a:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(lane)
	end)
	local bg = a:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
	local text = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER")
	text:SetText(label)
	a.parts = { bg, text }
	for _, part in ipairs(a.parts) do
		part:Hide()
	end
	lane.update = function(_, elapsed)
		OnLaneUpdate(lane, elapsed)
	end
	PlaceLane(lane)
	return lane
end

-- Put a line on a lane. value may be secret: it only ever goes through
-- SetFormattedText.
-- icon: nil, a texture file ID, or "pet" for your pet's portrait.
-- stack: a key naming the source (spell and damage or heal). Another hit
-- with the same key within STACK_WINDOW seconds of the first does not get
-- a line of its own: the first line counts it ("95 x3") and shows the
-- latest amount. The amounts are secret, so they cannot be added up.
-- Crits always get a line of their own.
function Spawn(lane, format, value, color, crit, pet, icon, stack)
	local now = GetTime()
	if stack and not crit and value ~= nil then
		local held = lane.stacks[stack]
		if held and held.line.stack == stack and now - held.time <= STACK_WINDOW then
			held.count = held.count + 1
			held.line.fs:SetFormattedText(format .. " x%d", value, held.count)
			return
		end
	end
	-- Make room: if the newest line is still too close to the start, push
	-- every line along so the new one never covers another.
	local nearest
	for _, line in ipairs(lane.active) do
		if not line.sticky and (not nearest or line.offset < nearest) then
			nearest = line.offset
		end
	end
	if not crit and nearest and nearest < SPACING then
		local push = SPACING - nearest
		for _, line in ipairs(lane.active) do
			if not line.sticky then
				line.offset = line.offset + push
			end
		end
	end
	local line = table.remove(lane.pool)
	if not line then
		line = CreateLine(lane)
	end
	local fs, tex = line.fs, line.tex
	local size = pet and (crit and PET_CRIT_SIZE or PET_SIZE) or (crit and CRIT_SIZE or SIZE)
	fs:SetFont(FONT, size, "OUTLINE")
	if value == nil then
		fs:SetText(format)
	else
		fs:SetFormattedText(format, value)
	end
	fs:SetAlpha(1)
	fs:ClearAllPoints()
	fs:SetPoint(lane.dir > 0 and "BOTTOM" or "TOP", lane.anchor, lane.dir > 0 and "TOP" or "BOTTOM", 0, 0)
	fs:Show()
	local hasIcon = false
	-- The file ID is secret if the spell ID was (an enemy's cast): it may
	-- be handed to SetTexture but not tested or compared.
	local known = CanAccess(icon)
	local portrait = known and icon == "pet"
	if portrait then
		SetPortraitTexture(tex, "pet")
		hasIcon = true
	elseif not known or icon then
		-- A refusal just means no icon.
		hasIcon = pcall(tex.SetTexture, tex, icon)
	end
	if hasIcon then
		-- Under the rounded mask the whole picture shows; the plain edge
		-- crops off the icon's own border.
		if line.ring or portrait then
			tex:SetTexCoord(0, 1, 0, 1)
		else
			tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
	end
	if hasIcon and color ~= HEAL then
		color = PLAIN
	end
	fs:SetTextColor(color[1], color[2], color[3])
	ShowIcon(line, hasIcon)
	if crit then
		line.iconScale = CRIT_ICON_SIZE / CRIT_SIZE
	else
		line.iconScale = ICON_SIZE / SIZE
	end
	SizeIcon(line, size)
	IconAlpha(line, 1)
	line.offset = 0
	line.stack = nil
	line.sticky, line.settled = nil, nil
	if crit then
		-- Sticky: older crits move outward to make room at the spot.
		for _, other in ipairs(lane.active) do
			if other.sticky then
				other.offset = other.offset + math.max(size, CRIT_ICON_SIZE) + 6
			end
		end
		line.sticky, line.age, line.size, line.color = true, 0, size, color
		fs:SetFont(FONT, size, "THICKOUTLINE")
		fs:SetTextHeight(size)
		fs:SetTextColor(1, 1, 1)
		fs:ClearAllPoints()
		fs:SetPoint(lane.dir > 0 and "BOTTOM" or "TOP", lane.anchor, lane.dir > 0 and "TOP" or "BOTTOM", lane.side * STICKY_SIDE, lane.dir * STICKY_AT)
	end
	if stack and not crit and value ~= nil then
		line.stack = stack
		lane.stacks[stack] = { line = line, time = now, count = 1 }
	end
	table.insert(lane.active, line)
	lane.anchor:SetScript("OnUpdate", lane.update)
end

-- What to show ------------------------------------------------------------

local function IsCrit(flags)
	return flags == "CRITICAL" or flags == "CRUSHING"
end

-- icon: for a heal on you that is yours, your spell's icon; for a hit you
-- take, see Hits you take.
local function ShowIncoming(event, flags, amount, school, icon)
	local lane = lanes.incoming
	if event == "WOUND" then
		if WOUND_WORDS[flags] then
			if IsZero(amount) then
				Spawn(lane, Word(flags), nil, MISS, false, false, icon)
			else
				Spawn(lane, "-%s (" .. Word(flags) .. ")", amount, SchoolColor(school), false, false, icon)
			end
		else
			Spawn(lane, "-%s", amount, SchoolColor(school), IsCrit(flags), false, icon)
		end
	elseif event == "HEAL" then
		Spawn(lane, "+%s", amount, HEAL, IsCrit(flags), false, icon)
	elseif MISS_TEXT[event] then
		Spawn(lane, Word(event), nil, MISS, false, false, icon)
	end
end

local function ShowOutgoing(hit, kind, icon, key)
	local lane = lanes.outgoing
	if hit.event == "HEAL" then
		Spawn(lane, "+%s", hit.amount, HEAL, IsCrit(hit.flags), false, icon, key and "heal" .. key)
	elseif hit.event == "WOUND" then
		if WOUND_WORDS[hit.flags] and (kind == "miss" or IsZero(hit.amount)) then
			Spawn(lane, Word(hit.flags), nil, MISS, false, false, icon)
		else
			Spawn(lane, "%s", hit.amount, SchoolColor(hit.school), IsCrit(hit.flags), false, icon, key and "hit" .. key)
		end
	elseif MISS_TEXT[hit.event] then
		Spawn(lane, Word(hit.event), nil, MISS, false, false, icon)
	end
end

-- Icons ------------------------------------------------------------------
--
-- Which spell made a hit is not reported either; it is worked out from
-- your own and your pet's casts (UNIT_SPELLCAST_SUCCEEDED, and
-- UNIT_SPELLCAST_CHANNEL_START for channels), the kind of
-- combat log line, and each spell's school, direct hit and tick period
-- from the game's own tables (Data.lua, see scripts/combat-scroll-data.py):
-- - melee: the Attack icon, or your pet's portrait while you are not
--   auto-attacking yourself and have a pet;
-- - ranged: the icon of the weapon in your ranged slot;
-- - a damage shield: the item or aura that has one (see ShieldIcon);
-- - a direct spell hit or heal: a cast of a spell that hits directly
--   in that school, from the last DIRECT_WINDOW seconds: the oldest one
--   not used yet (a projectile is still in the air), else the latest one
--   (an area spell hits many). A channel such as Arcane Missiles hits
--   every `every` seconds for as long as CHANNEL_WINDOW;
-- - a spell that misses outright: your latest cast (see MissIcon);
-- - a tick: of the spells that tick in that school and that you put out in
--   the last MAX_DOT seconds, the one whose schedule (every period seconds
--   from its cast) this tick lands on. Two DoTs of one school, such as
--   Corruption and Bane of Agony, are told apart this way.
-- Only spells in the data count for a hit or a heal: a cast that does no
-- damage or healing (switching tracking, a buff) never claims one, it can
-- only claim a miss. A hit nothing explains (a proc, a poison, an item's
-- spell) gets no icon.

local DIRECT_WINDOW = 3 -- seconds from cast to hit
local AOE_WINDOW = 1.5 -- an area spell's later hits
local CHANNEL_WINDOW = 10
local MAX_DOT = 40 -- longest a DoT or HoT is followed
local NOT_CASTS = { [6603] = true, [75] = true, [5019] = true } -- Attack, Auto Shot, Shoot

local data = ns.spells or {}
local casts = {} -- { id, icon, time, used }, newest last
local applied = {} -- spellID -> its latest cast
local meleeing = false

-- A school the hit may be checked against, or nil when it says nothing:
-- secret, or 0.
local function Plain(school)
	return CanAccess(school) and type(school) == "number" and school ~= 0 and school or nil
end

-- Whether a spell can have made a hit of this school.
local function SameSchool(spell, school)
	return spell[1] == 0 or not school or bit.band(spell[1], school) ~= 0
end

local CAST_TWICE = 0.3 -- a channel may report its start both ways

local function OnCast(unit, _, id)
	if not CanAccess(id) then
		Debug("cast by " .. unit .. ": spell ID is secret")
		return
	end
	if NOT_CASTS[id] then
		Debug(("cast %d by %s: an auto attack, not followed"):format(id, unit))
		return
	end
	local now = GetTime()
	local last = casts[#casts]
	if last and last.id == id and now - last.time < CAST_TWICE then
		return
	end
	local spell = data[id]
	if spell then
		Debug(("cast %d by %s: school %d, direct %d, tick %g, every %g"):format(id, unit, spell[1], spell[2], spell[3], spell[4]))
	else
		Debug(("cast %d by %s: not a damage or heal spell, counts for a miss only"):format(id, unit))
	end
	local cast = { id = id, icon = C_Spell.GetSpellTexture(id), time = now }
	table.insert(casts, cast)
	if spell and spell[3] > 0 then
		applied[id] = cast
	end
	while casts[1] and now - casts[1].time > CHANNEL_WINDOW do
		table.remove(casts, 1)
	end
	for spellID, a in pairs(applied) do
		if now - a.time > MAX_DOT then
			applied[spellID] = nil
		end
	end
end

local function DirectIcon(school, now)
	local oldestFree, latest
	for _, cast in ipairs(casts) do
		local age = now - cast.time
		local spell = data[cast.id]
		-- A cast that is not in the data never claims a hit or a heal.
		if spell and age >= 0 and SameSchool(spell, school) then
			if spell[4] > 0 then
				-- A channel: each of its hits, as long as it may last.
				if age <= CHANNEL_WINDOW then
					latest = cast
				end
			elseif spell[2] == 1 and age <= DIRECT_WINDOW then
				if not cast.used and not oldestFree then
					oldestFree = cast
				end
				if age <= AOE_WINDOW then
					latest = cast
				end
			end
		end
	end
	local cast = oldestFree or latest
	if not cast then
		return nil
	end
	cast.used = true
	return cast.icon, cast.id
end

-- A spell that misses outright: your latest cast, whatever the spell does.
-- Scorpid Sting does no damage and Serpent Sting only ticks, so neither is
-- a direct spell in the data, yet both can fail on an immune target. The
-- hit's school is not used: Scorpid Sting (nature) on an immune target came
-- as IMMUNE, school 1, in game, 2026-11-19.
local function MissIcon(now)
	for i = #casts, 1, -1 do
		local cast = casts[i]
		local age = now - cast.time
		local spell = data[cast.id]
		local window = spell and spell[4] > 0 and CHANNEL_WINDOW or DIRECT_WINDOW
		if age >= 0 and age <= window then
			cast.used = true
			return cast.icon, cast.id
		end
	end
	return nil
end

local function TickIcon(school, now)
	local best, bestOff
	for id, cast in pairs(applied) do
		local spell = data[id]
		local age = now - cast.time
		if age > 0 and age <= MAX_DOT and SameSchool(spell, school) then
			local period = spell[3]
			local phase = age % period
			local off = math.min(phase, period - phase)
			if not bestOff or off < bestOff then
				best, bestOff = cast, off
			end
		end
	end
	if not best then
		return nil
	end
	return best.icon, best.id
end

local RANGED_SLOT = 18

-- Damage shields ("when struck, inflicts damage to the attacker"): an
-- equipped item whose equip spell is one, of the hit's school (Sporid
-- Cape: nature), gets that item's icon; else a Thorns or Fire Shield aura
-- on you of that school. Both lists come from Data.lua. Your own auras may
-- be unreadable in combat (SecretWhenUnitAuraRestricted); then no icon.
local shieldSlots = {} -- inventory slot -> school mask

local function ScanShieldItems()
	for slot in pairs(shieldSlots) do
		shieldSlots[slot] = nil
	end
	local items = ns.shieldItems or {}
	for slot = 1, 19 do
		local id = GetInventoryItemID("player", slot)
		if id and items[id] then
			shieldSlots[slot] = items[id]
		end
	end
end

local function SchoolFits(mask, school)
	return mask == 0 or not school or bit.band(mask, school) ~= 0
end

local function ShieldIcon(school)
	for slot, mask in pairs(shieldSlots) do
		if SchoolFits(mask, school) then
			return GetInventoryItemTexture("player", slot), "item" .. slot
		end
	end
	for id, mask in pairs(ns.shieldSpells or {}) do
		if SchoolFits(mask, school) then
			local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
			if ok and CanAccess(aura) and aura then
				return C_Spell.GetSpellTexture(id), id
			end
		end
	end
	return nil
end

-- Returns the icon (a file ID or "pet") and a key naming the source, for
-- stacking: a spell ID, "melee", "pet" or "ranged".
function IconFor(logEvent, hit)
	if not logEvent then
		return nil
	end
	local school, now = Plain(hit.school), hit.time or GetTime()
	-- A heal's UNIT_COMBAT reports school 1 (physical) whatever the spell:
	-- Mend Pet (nature) ticks came as school 1 in game, 2026-11-18. So a
	-- heal is matched on timing alone.
	if hit.event == "HEAL" then
		school = nil
	end
	if logEvent == "SPELL_MISSED" and MISS_TEXT[hit.event] then
		return MissIcon(now)
	end
	if logEvent:find("^SWING") then
		if not meleeing and UnitExists("pet") then
			return "pet", "pet"
		end
		return C_Spell.GetSpellTexture(6603), "melee"
	elseif logEvent:find("^RANGE") then
		return GetInventoryItemTexture("player", RANGED_SLOT) or C_Spell.GetSpellTexture(75), "ranged"
	elseif logEvent:find("^SPELL_PERIODIC") then
		return TickIcon(school, now)
	elseif logEvent:find("^SPELL") then
		return DirectIcon(school, now)
	elseif logEvent:find("^DAMAGE_SHIELD") then
		return ShieldIcon(school)
	end
	return nil -- split damage
end

-- Hits you take -----------------------------------------------------------
--
-- A hit on you names neither the attacker nor the spell (UNIT_COMBAT), so
-- its icon is a guess from timing (API documentation of build 70959; not
-- yet seen in game):
-- - enemy casts are watched on your target and on every nameplate
--   (UNIT_SPELLCAST_SUCCEEDED, and UNIT_SPELLCAST_CHANNEL_START/_STOP for
--   channels). Their spell ID is secret (SecretWhenUnitSpellCastRestricted),
--   but C_Spell.GetSpellTexture and Texture:SetTexture are documented to
--   take secret values, so the icon can be drawn. Its school, and whether
--   the spell does damage at all, cannot be read from a secret ID;
-- - a hit on you takes the oldest cast of the last ENEMY_WINDOW seconds
--   that no hit has taken yet; failing that, a channel still running, for
--   every hit until it stops. A cast by an enemy that is targeting someone
--   else only counts for a hit that is not physical (an area spell), so a
--   melee hit does not take the spell another enemy casts at the tank;
-- - a physical hit, or a miss, dodge, parry or block, that no cast explains
--   is taken to be melee and gets the Attack icon, in combat only (a fall
--   is physical too). A bleed's tick gets it as well;
-- - anything else (a DoT's tick, a caster without a nameplate) gets no
--   icon. With several enemies casting, the icon can be the wrong one.
-- A hit waits for the next frame before it is shown, so that a cast
-- reported later in the same frame still counts. /cscroll debug prints
-- every enemy cast seen and what each hit took.

local ENEMY_WINDOW = 1.5 -- seconds from an enemy's cast to its hit on you
local CHANNEL_END = 0.3 -- a channel's last hit may come this long after its stop
local MELEE_MISS = { MISS = true, DODGE = true, PARRY = true, BLOCK = true }

local enemyCasts = {} -- { unit, icon, hasIcon, time, atMe, channel, stop, used }, newest last
local taken = {} -- hits on you, waiting for their frame to end

-- A yes or no from the game; nil when it could not be told (an error, or
-- a secret answer).
local function Flag(fn, ...)
	local ok, value = pcall(fn, ...)
	if ok and CanAccess(value) then
		return value and true or false
	end
	return nil
end

local function OnEnemyCast(unit, event, id)
	-- Your target's nameplate reports the same cast.
	if unit == "target" and C_NamePlate.GetNamePlateForUnit("target") then
		return
	end
	if Flag(UnitCanAttack, unit, "player") == false then
		return
	end
	local now = GetTime()
	if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		for _, cast in ipairs(enemyCasts) do
			if cast.unit == unit and cast.channel and not cast.stop then
				cast.stop = now
			end
		end
		return
	end
	local channel = event == "UNIT_SPELLCAST_CHANNEL_START"
	-- A channel may report its start both ways: one cast, and a channel.
	for i = #enemyCasts, 1, -1 do
		local cast = enemyCasts[i]
		if now - cast.time >= CAST_TWICE then
			break
		end
		if cast.unit == unit and (channel or cast.channel) then
			cast.channel = true
			return
		end
	end
	-- The spell ID and the file ID it gives are only handed on, never
	-- looked at: either may be secret.
	local ok, icon = pcall(C_Spell.GetSpellTexture, id)
	local hasIcon = ok and (not CanAccess(icon) or icon ~= nil)
	local cast = { unit = unit, time = now, atMe = Flag(UnitIsUnit, unit .. "target", "player"), channel = channel, hasIcon = hasIcon }
	if hasIcon then
		cast.icon = icon
	end
	table.insert(enemyCasts, cast)
	while enemyCasts[1] and now - enemyCasts[1].time > CHANNEL_WINDOW do
		table.remove(enemyCasts, 1)
	end
	Debug(("enemy %s by %s: spell %s, icon %s, targeting %s"):format(
		channel and "channel" or "cast", unit, CanAccess(id) and tostring(id) or "secret", hasIcon and "yes" or "no",
		cast.atMe == nil and "unknown" or cast.atMe and "you" or "someone else"))
end

-- A frame per unit token, so the caster is known without reading the
-- event's own unit, which may be secret.
local listeners = {}
local function Listen(unit)
	if listeners[unit] then
		return
	end
	local f = CreateFrame("Frame")
	listeners[unit] = f
	f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
	f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
	f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
	f:SetScript("OnEvent", function(_, event, _, _, id)
		OnEnemyCast(unit, event, id)
	end)
end

-- The enemy cast a hit on you is taken to come from, if any.
local function EnemyCast(hit)
	local school = Plain(hit.school)
	local magic = school and bit.band(school, 1) == 0
	local running
	for _, cast in ipairs(enemyCasts) do
		local age = hit.time - cast.time
		if age >= 0 and (cast.atMe ~= false or magic) then
			if cast.channel then
				if age <= CHANNEL_WINDOW and (not cast.stop or hit.time - cast.stop <= CHANNEL_END) then
					running = cast
				end
			elseif not cast.used and age <= ENEMY_WINDOW then
				cast.used = true
				return cast
			end
		end
	end
	return running
end

local function TakenIcon(hit)
	local cast = EnemyCast(hit)
	if cast then
		Debug(("taken %s: the %s by %s%s"):format(hit.event, cast.channel and "channel" or "cast", cast.unit, cast.hasIcon and "" or ", which has no icon"))
		return cast.icon
	end
	local school = Plain(hit.school)
	local melee
	if hit.event == "WOUND" then
		melee = school == 1
	else
		melee = MELEE_MISS[hit.event] and (not school or school == 1)
	end
	if melee and Flag(UnitAffectingCombat, "player") ~= false then
		Debug(("taken %s: no cast, so melee"):format(hit.event))
		return C_Spell.GetSpellTexture(6603)
	end
	Debug(("taken %s: no cast, no icon"):format(hit.event))
	return nil
end

local function ShowTaken()
	local now = CurrentFrame()
	while taken[1] and taken[1].frame < now do
		local hit = table.remove(taken, 1)
		ShowIncoming(hit.event, hit.flags, hit.amount, hit.school, TakenIcon(hit))
	end
end

-- Matching ---------------------------------------------------------------

-- Which kind of combat log line a UNIT_COMBAT can pair with, and how good
-- a pair it is (lower is better).
local function Fit(kind, hit)
	if kind == "heal" then
		if hit.event ~= "HEAL" then
			return nil
		end
		-- Your own heal on yourself is shown on the left already; it still
		-- takes its line so that line cannot claim someone else's heal.
		if hit.role == "self" then
			return 0
		elseif hit.role == "group" then
			return 1
		end
		return 2
	end
	if hit.event == "HEAL" or hit.role == "self" or hit.role == "group" then
		return nil
	end
	if kind == "damage" then
		return hit.event == "WOUND" and 0 or nil
	end
	-- kind == "miss": a full absorb, block or resist can come as a WOUND.
	if MISS_TEXT[hit.event] then
		return 0
	end
	return hit.event == "WOUND" and 1 or nil
end

local function Match()
	local now = CurrentFrame()
	local matched = 0
	for _, line in ipairs(lines) do
		-- Only once every hit that could belong to this line has arrived.
		if not line.used and line.frame + WINDOW < now then
			local best, bestScore
			for _, hit in ipairs(hits) do
				if not hit.used and hit.frame < now and math.abs(hit.frame - line.frame) <= WINDOW then
					local fit = Fit(line.kind, hit)
					if fit then
						local score = math.abs(hit.frame - line.frame) * 10 + fit
						if not bestScore or score < bestScore then
							best, bestScore = hit, score
						end
					end
				end
			end
			if best then
				line.used, best.used = true, true
				matched = matched + 1
				local icon, key = IconFor(line.event, best)
				if best.role == "self" then
					-- Your heal on yourself: on the left, with its icon.
					ShowIncoming(best.event, best.flags, best.amount, best.school, icon)
				else
					ShowOutgoing(best, line.kind, icon, key)
				end
			end
		end
	end
	stats.matched = stats.matched + matched

	-- Drop what can no longer pair.
	local lostLines, lostHits = 0, 0
	for i = #lines, 1, -1 do
		local line = lines[i]
		if line.used or line.frame + WINDOW + KEEP < now then
			if not line.used then
				lostLines = lostLines + 1
			end
			table.remove(lines, i)
		end
	end
	for i = #hits, 1, -1 do
		local hit = hits[i]
		if hit.used or hit.frame + WINDOW + KEEP < now then
			if not hit.used and hit.role == "self" then
				-- A heal on you that is not yours: shown plain.
				ShowIncoming(hit.event, hit.flags, hit.amount, hit.school)
			elseif not hit.used then
				lostHits = lostHits + 1
			end
			table.remove(hits, i)
		end
	end
	stats.lostLines = stats.lostLines + lostLines
	stats.lostHits = stats.lostHits + lostHits
	if matched + lostLines + lostHits > 0 then
		Debug(("frame %d: %d paired, %d of your lines without a hit, %d hits not yours"):format(now, matched, lostLines, lostHits))
	end
end

local function KindOfColor(r, g, b)
	if not (CanAccess(r) and CanAccess(g) and CanAccess(b)) then
		return nil
	end
	for _, c in pairs(EVENT_COLORS) do
		if math.abs(c[1] - r) < COLOR_TOLERANCE and math.abs(c[2] - g) < COLOR_TOLERANCE and math.abs(c[3] - b) < COLOR_TOLERANCE then
			return c[4], c.event
		end
	end
	return nil
end

-- Which unit tokens to listen to, so that one hit is not counted twice
-- under two names. nil: ignore this token.
local function Role(unit)
	if unit == "player" then
		return "self"
	elseif unit == "target" then
		-- The same unit's nameplate reports it too.
		if C_NamePlate.GetNamePlateForUnit("target") then
			return nil
		end
		return "other"
	elseif unit:match("^nameplate%d+$") then
		return "other"
	elseif unit == "pet" or unit:match("^raid%d+$") or unit:match("^raidpet%d+$") then
		return "group"
	elseif unit:match("^party%d$") or unit:match("^partypet%d$") then
		-- In a raid the raid tokens already cover your party.
		return not IsInRaid() and "group" or nil
	end
	return nil
end

-- Your pet's damage taken: the left column, smaller, with its portrait.
-- Heals on your pet stay where they are (yours on the right).
local function ShowPetHit(event, flags, amount)
	local lane = lanes.incoming
	if event == "WOUND" then
		if WOUND_WORDS[flags] and IsZero(amount) then
			Spawn(lane, Word(flags), nil, MISS, false, true, "pet")
		else
			Spawn(lane, "-%s", amount, PLAIN, IsCrit(flags), true, "pet")
		end
	elseif MISS_TEXT[event] then
		Spawn(lane, Word(event), nil, MISS, false, true, "pet")
	end
end

local function OnUnitCombat(unit, event, flags, amount, school)
	if not (CanAccess(unit) and CanAccess(event) and CanAccess(flags)) then
		return
	end
	local role = Role(unit)
	if not role then
		return
	end
	if role == "self" then
		-- A heal on you waits a frame or two for a line of yours, which
		-- gives it your spell's icon (see Match). Anything else waits a
		-- frame for an enemy's cast (see Hits you take).
		if event ~= "HEAL" then
			table.insert(taken, { frame = CurrentFrame(), time = GetTime(), event = event, flags = flags, amount = amount, school = school })
			return
		end
	elseif unit == "pet" and event ~= "HEAL" then
		ShowPetHit(event, flags, amount)
		return
	end
	stats.hits = stats.hits + 1
	table.insert(hits, { frame = CurrentFrame(), time = GetTime(), event = event, flags = flags, amount = amount, school = school, role = role })
	Debug(("hit %s %s %s school %s"):format(unit, event, flags or "", CanAccess(school) and tostring(school) or "secret"))
end

local function OnCombatLogMessage(_, r, g, b, order)
	-- Oldest: Blizzard refilling the tab from history, not something new.
	if order ~= Enum.CombatLogMessageOrder.Newest then
		return
	end
	local kind, logEvent = KindOfColor(r, g, b)
	if not kind then
		Debug("a combat log line in a colour that is not ours")
		return
	end
	stats.lines = stats.lines + 1
	table.insert(lines, { frame = CurrentFrame(), kind = kind, event = logEvent })
	Debug("line " .. logEvent)
end

-- The combat log filter ----------------------------------------------------

local function Filters()
	local f = _G.Blizzard_CombatLog_Filters
	return type(f) == "table" and type(f.filters) == "table" and f or nil
end

local function OurFilterIndex()
	local f = Filters()
	if not f then
		return nil
	end
	for i, filter in ipairs(f.filters) do
		if filter.name == FILTER_NAME then
			return i
		end
	end
	return nil
end

local function FilterActive()
	local f, i = Filters(), OurFilterIndex()
	return i ~= nil and f.currentFilter == i
end

local function BuildFilter()
	local eventList, coloring = {}, {}
	for event, c in pairs(EVENT_COLORS) do
		eventList[event] = true
		coloring[event] = { a = 1, r = c[1], g = c[2], b = c[3] }
	end
	-- A spell miss under each name Blizzard looks it up by, all in the
	-- colour of SPELL_MISSED. The event list keeps the plain name.
	local c = EVENT_COLORS.SPELL_MISSED
	for _, miss in ipairs(SPELL_MISS_TYPES) do
		coloring["SPELL_MISSED_" .. miss] = { a = 1, r = c[1], g = c[2], b = c[3] }
	end
	local settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS)
	settings.lineColoring = true
	settings.lineColorPriority = 3 -- colour each line by its event
	settings.lineHighlighting = false -- would brighten some lines
	local colors = CopyTable(COMBATLOG_DEFAULT_COLORS)
	colors.eventColoring = coloring
	return {
		name = FILTER_NAME,
		hasQuickButton = true,
		quickButtonName = FILTER_NAME,
		quickButtonDisplay = { solo = true, party = true, raid = true },
		tooltip = "Your own and your pet's hits, misses and heals, coloured by kind. CombatScroll reads the colours.",
		settings = settings,
		colors = colors,
		filters = {
			[1] = {
				eventList = eventList,
				sourceFlags = { [COMBATLOG_FILTER_MINE] = true, [COMBATLOG_FILTER_MY_PET] = true },
				destFlags = nil,
			},
		},
	}
end

local function Say(text)
	print("|cffffd100CombatScroll|r: " .. text)
end

-- Blizzard's own floating combat text, which shows the same numbers: game
-- options (account-wide), so /cscroll setup turns them off and keeps what
-- each was in db.blizzardText for /cscroll undo.
local BLIZZARD_TEXT = {
	{ "floatingCombatTextCombatDamage_v2", "damage on your target" },
	{ "floatingCombatTextCombatHealing_v2", "healing on your target" },
	{ "enableFloatingCombatText", "combat text about you" },
}

-- Says what changed now, or, when a reload follows, after it.
local function Report(text, reloading)
	if reloading then
		db.pendingNote = text
	else
		Say(text)
	end
end

local function HideBlizzardText(reloading)
	db.blizzardText = db.blizzardText or {}
	local off = {}
	for _, cvar in ipairs(BLIZZARD_TEXT) do
		local name, label = cvar[1], cvar[2]
		local current = C_CVar.GetCVar(name)
		if current ~= nil and current ~= "0" then
			if db.blizzardText[name] == nil then
				db.blizzardText[name] = current
			end
			C_CVar.SetCVar(name, "0")
			off[#off + 1] = label
		end
	end
	if #off > 0 then
		Report("turned Blizzard's floating " .. table.concat(off, ", ") .. " off; /cscroll undo turns it back on.", reloading)
	end
end

local function RestoreBlizzardText(reloading)
	local saved = db.blizzardText
	if not saved or next(saved) == nil then
		return false
	end
	local on = {}
	for _, cvar in ipairs(BLIZZARD_TEXT) do
		local name, label = cvar[1], cvar[2]
		if saved[name] ~= nil then
			C_CVar.SetCVar(name, saved[name])
			on[#on + 1] = label
		end
	end
	db.blizzardText = nil
	Report("turned Blizzard's floating " .. table.concat(on, ", ") .. " back on.", reloading)
	return true
end

local function Setup()
	if InCombatLockdown() then
		Say("not in combat; try again after the fight")
		return
	end
	local f = Filters()
	HideBlizzardText(f and COMBATLOG_DEFAULT_SETTINGS and true)
	if not f or not COMBATLOG_DEFAULT_SETTINGS then
		Say("Blizzard's combat log is not loaded. It loads with the Combat Log chat tab; open that tab (or make one), then try again.")
		return
	end
	local i = OurFilterIndex() or (#f.filters + 1)
	f.filters[i] = BuildFilter()
	f.currentFilter = i
	ReloadUI()
end

local function Undo()
	if InCombatLockdown() then
		Say("not in combat; try again after the fight")
		return
	end
	local f, i = Filters(), OurFilterIndex()
	local restored = RestoreBlizzardText(i ~= nil)
	if not i then
		if not restored then
			Say("the CombatScroll combat log filter is not there; nothing to undo")
		end
		return
	end
	table.remove(f.filters, i)
	if f.currentFilter == i or f.currentFilter > #f.filters then
		f.currentFilter = 1
	elseif f.currentFilter > i then
		f.currentFilter = f.currentFilter - 1
	end
	ReloadUI()
end

-- Blizzard turns combat log lines off while its tab is hidden; we need them.
local function KeepLinesOn()
	if FilterActive() and not C_CombatLog.AreFilteredEventsEnabled() then
		C_CombatLog.SetFilteredEventsEnabled(true)
	end
end

local hooked = false
local function HookCombatLog()
	if hooked or not _G.COMBATLOG then
		return
	end
	hooked = true
	_G.COMBATLOG:HookScript("OnHide", KeepLinesOn)
end

local function CheckFilter()
	if not Filters() then
		Say("outgoing numbers need Blizzard's combat log, which loads with the Combat Log chat tab.")
	elseif not OurFilterIndex() then
		Say("outgoing numbers need a combat log filter of their own. /cscroll setup adds it (it is Blizzard's setting, account-wide) and reloads; /cscroll undo takes it out.")
	elseif not FilterActive() then
		Say("the Combat Log tab shows another filter, so outgoing numbers are off. Click the CombatScroll button above the Combat Log to turn them back on.")
	end
end

-- Commands -----------------------------------------------------------------

local function SetUnlocked(on)
	unlocked = on
	for _, lane in pairs(lanes) do
		lane.anchor:EnableMouse(on)
		for _, part in ipairs(lane.anchor.parts) do
			part:SetShown(on)
		end
	end
end

local function Test()
	-- A spell of each school for its icon: Attack, Fireball, Frostbolt,
	-- Shadow Bolt, Lightning Bolt, Smite, Arcane Missiles.
	local samples = { { 1, 6603 }, { 4, 133 }, { 16, 116 }, { 32, 686 }, { 8, 403 }, { 2, 585 }, { 64, 5143 } }
	for i, sample in ipairs(samples) do
		C_Timer.After(i * 0.25, function()
			Spawn(lanes.outgoing, "%s", 100 * i + 23, SchoolColor(sample[1]), i == 3, false, C_Spell.GetSpellTexture(sample[2]))
			if i % 2 == 0 then
				Spawn(lanes.incoming, "-%s", 40 * i, SchoolColor(sample[1]), i == 4, false, C_Spell.GetSpellTexture(sample[2]))
			end
		end)
	end
	C_Timer.After(2.0, function()
		Spawn(lanes.outgoing, "+%s", 480, HEAL, false, false, C_Spell.GetSpellTexture(2050)) -- Lesser Heal
		Spawn(lanes.incoming, "+%s", 300, HEAL, true)
		Spawn(lanes.incoming, Word("DODGE"), nil, MISS)
		Spawn(lanes.outgoing, Word("PARRY"), nil, MISS)
	end)
end

local function Reset()
	db.incoming, db.outgoing, db.scale = nil, nil, 1
	for _, lane in pairs(lanes) do
		PlaceLane(lane)
	end
end

-- Events -------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "UNIT_COMBAT" then
		OnUnitCombat(...)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		OnCast(...)
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		ScanShieldItems()
	elseif event == "PLAYER_ENTER_COMBAT" then
		meleeing = true
	elseif event == "PLAYER_LEAVE_COMBAT" then
		meleeing = false
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local unit = ...
		if CanAccess(unit) and type(unit) == "string" then
			Listen(unit)
		end
	elseif event == "COMBAT_LOG_MESSAGE" then
		OnCombatLogMessage(...)
	elseif event == "ADDON_LOADED" then
		local name = ...
		if name == "Blizzard_CombatLog" then
			HookCombatLog()
			KeepLinesOn()
		elseif name == ADDON then
			CombatScrollDB = CombatScrollDB or {}
			db = CombatScrollDB
			for key, value in pairs(DEFAULTS) do
				if db[key] == nil then
					db[key] = value
				end
			end
			WINDOW = db.window
			lanes.incoming = CreateLane("incoming", "CombatScroll: taken", -1, -280, 120)
			lanes.outgoing = CreateLane("outgoing", "CombatScroll: dealt", 1, 280, -100)
			self:RegisterEvent("UNIT_COMBAT")
			self:RegisterEvent("COMBAT_LOG_MESSAGE")
			self:RegisterEvent("PLAYER_ENTERING_WORLD")
			self:RegisterEvent("PLAYER_REGEN_DISABLED")
			self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
			self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "pet") -- Mend Pet, Drain Life
			self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
			self:RegisterEvent("PLAYER_ENTER_COMBAT") -- auto-attack on
			self:RegisterEvent("PLAYER_LEAVE_COMBAT") -- and off
			self:RegisterEvent("NAME_PLATE_UNIT_ADDED") -- enemy casts, per nameplate
			Listen("target")
			HookCombatLog()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		local login, reload = ...
		ScanShieldItems()
		HookCombatLog()
		KeepLinesOn()
		if login or reload then
			if db.pendingNote then
				Say(db.pendingNote)
				db.pendingNote = nil
			end
			CheckFilter()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		KeepLinesOn()
	end
end)

-- Pairs lines with hits once their frame is complete.
events:SetScript("OnUpdate", function()
	if #lines > 0 or #hits > 0 then
		Match()
	end
	if #taken > 0 then
		ShowTaken()
	end
end)

SLASH_COMBATSCROLL1 = "/cscroll"
SLASH_COMBATSCROLL2 = "/combatscroll"
SlashCmdList.COMBATSCROLL = function(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "unlock" then
		SetUnlocked(true)
	elseif cmd == "lock" then
		SetUnlocked(false)
	elseif cmd == "test" then
		Test()
	elseif cmd == "setup" then
		Setup()
	elseif cmd == "undo" then
		Undo()
	elseif cmd == "scale" and tonumber(arg) then
		db.scale = math.min(2, math.max(0.5, tonumber(arg)))
		for _, lane in pairs(lanes) do
			lane.anchor:SetScale(db.scale)
		end
		Say(("scale %.2f"):format(db.scale))
	elseif cmd == "reset" then
		Reset()
	elseif cmd == "stats" then
		Say(("filter %s, lines on: %s. Your lines %d, hits seen %d, paired %d, lines without a hit %d, hits not yours %d"):format(
			FilterActive() and "active" or "NOT active", tostring(C_CombatLog.AreFilteredEventsEnabled()),
			stats.lines, stats.hits, stats.matched, stats.lostLines, stats.lostHits))
	elseif cmd == "window" and tonumber(arg) then
		WINDOW = math.min(3, math.max(0, math.floor(tonumber(arg))))
		db.window = WINDOW
		Say(("a line and its hit may be %d frame(s) apart"):format(WINDOW))
	elseif cmd == "debug" then
		debug = not debug
		Say("debug " .. (debug and "on" or "off"))
	else
		Say("/cscroll unlock | lock | test | setup | undo | scale 0.5-2 | reset | stats | debug | window 0-3")
	end
end
