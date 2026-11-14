-- Backdrop.lua: a dark backdrop with soft edges behind the quest tracker,
-- so its text stays readable over bright ground. /fq backdrop <0-100>
--
-- It is a frame of our own behind the tracker, one piece behind the game's
-- sections and the ForeverGuide section under them when that addon runs.
-- Nothing of the game's tracker is written or called to change it: where
-- it is and how far its sections reach is only read, and our frame is moved
-- to match. (A write to the tracker marks it as addon-touched and breaks
-- its redraws in combat; see ForeverGuide's Tracker.lua.)

local _, ns = ...

local TEXTURE = "Interface\\AddOns\\ForeverQuests\\backdrop" -- white, solid middle, soft band around it
local EDGE = 24 / 64 -- the soft band's share of the texture (scripts/make-backdrop-tga.py)
local SOFT = 22 -- height of the soft band above
local SOFT_BOTTOM = 70 -- and below: a longer, gentler fade
local SOFT_SIDE = 70 -- its width at the sides: a longer, gentler fade
local PAD = 4 -- solid dark kept free below the text
local PAD_LEFT = -40 -- the fade starts this far inside the tracker's left edge
local PAD_RIGHT = -10 -- and its right edge, where the text runs further out
local PAD_TOP = -12 -- at the top the dark starts a little inside, clear of what is above the tracker
local DEFAULT = 20 -- percent
local INTERVAL = 0.05 -- seconds between looks at the tracker

local frame
local placed -- what was last applied, to move only on a change

local function Opacity()
	local value = ForeverQuestsDB and ForeverQuestsDB.backdrop
	return type(value) == "number" and value or DEFAULT
end

-- The four edges of a shown region in UIParent's units, or nothing.
local function Rect(region)
	if not (region and region.GetLeft and region:IsShown()) then
		return nil
	end
	local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
	local ours, theirs = UIParent:GetEffectiveScale(), region:GetEffectiveScale()
	local function isNumber(value)
		return type(value) == "number"
	end
	if not (isNumber(left) and isNumber(right) and isNumber(top) and isNumber(bottom) and isNumber(ours) and isNumber(theirs)) then
		return nil -- not laid out yet
	end
	if ours <= 0 or right <= left or top <= bottom then
		return nil
	end
	local scale = theirs / ours
	return left * scale, right * scale, top * scale, bottom * scale
end

local function Piece(u1, u2, v1, v2)
	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetTexture(TEXTURE)
	texture:SetTexCoord(u1, u2, v1, v2)
	texture:SetVertexColor(0, 0, 0)
	return texture
end

local function Create()
	frame = CreateFrame("Frame", "ForeverQuestsBackdrop", UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:Hide()

	local near, far = EDGE, 1 - EDGE
	Piece(near, far, near, far):SetAllPoints(frame)

	local top = Piece(near, far, 0, near)
	top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT")
	top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT")
	top:SetHeight(SOFT)
	local bottom = Piece(near, far, far, 1)
	bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT")
	bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT")
	bottom:SetHeight(SOFT_BOTTOM)
	local left = Piece(0, near, near, far)
	left:SetPoint("TOPRIGHT", frame, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT")
	left:SetWidth(SOFT_SIDE)
	local right = Piece(far, 1, near, far)
	right:SetPoint("TOPLEFT", frame, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT")
	right:SetWidth(SOFT_SIDE)

	local corners = {
		{ "BOTTOMRIGHT", "TOPLEFT", 0, near, 0, near },
		{ "BOTTOMLEFT", "TOPRIGHT", far, 1, 0, near },
		{ "TOPRIGHT", "BOTTOMLEFT", 0, near, far, 1 },
		{ "TOPLEFT", "BOTTOMRIGHT", far, 1, far, 1 },
	}
	for _, c in ipairs(corners) do
		local corner = Piece(c[3], c[4], c[5], c[6])
		corner:SetPoint(c[1], frame, c[2])
		corner:SetSize(SOFT_SIDE, c[2]:find("BOTTOM") and SOFT_BOTTOM or SOFT)
	end
end

local function Follow()
	local opacity = Opacity()
	local left, right, top, bottom
	local tracker = ObjectiveTrackerFrame
	local folded = tracker and tracker.IsCollapsed and tracker:IsCollapsed()
	if opacity > 0 and not folded then
		-- The game's sections: its own (invisible at Edit Mode opacity 0)
		-- background spans exactly what the tracker shows.
		if tracker and tracker.IsShown and tracker:IsShown() then
			left, right, top, bottom = Rect(tracker.NineSlice)
		end
		-- The guide's section under them.
		local gLeft, gRight, gTop, gBottom = Rect(ForeverGuideTracker)
		if gLeft and left then
			left, right = math.min(left, gLeft), math.max(right, gRight)
			top, bottom = math.max(top, gTop), math.min(bottom, gBottom)
		elseif gLeft then
			left, right, top, bottom = gLeft, gRight, gTop, gBottom
		end
	end

	if not left then
		if placed ~= "hidden" then
			placed = "hidden"
			frame:Hide()
		end
		return
	end
	local key = ("%.1f:%.1f:%.1f:%.1f:%d"):format(left, right, top, bottom, opacity)
	if key == placed then
		return
	end
	placed = key
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left - PAD_LEFT, top + PAD_TOP)
	frame:SetSize(math.max(right - left + PAD_LEFT + PAD_RIGHT, 1), math.max(top - bottom + PAD_TOP + PAD, 1))
	frame:SetAlpha(opacity / 100)
	frame:Show()
end

-- /fq backdrop [0-100]
function ns.BackdropCommand(text)
	local value = tonumber(text)
	if value and value >= 0 and value <= 100 then
		ForeverQuestsDB.backdrop = math.floor(value + 0.5)
		if frame then
			Follow()
		end
	elseif text ~= "" then
		ns.Print("/fq backdrop <0-100>: how dark the backdrop behind the quest tracker is; 0 switches it off.")
		return
	end
	local now = Opacity()
	ns.Print(now > 0 and ("tracker backdrop at %d%%. /fq backdrop <0-100> to change, 0 for off."):format(now)
		or "tracker backdrop is off. /fq backdrop <1-100> to switch it on.")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	ForeverQuestsDB = type(ForeverQuestsDB) == "table" and ForeverQuestsDB or {}
	Create()
	Follow()
	C_Timer.NewTicker(INTERVAL, Follow)
end)
