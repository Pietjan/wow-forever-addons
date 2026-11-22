-- Dragging a frame of one of our addons: its left, middle and right meet the screen's edges,
-- thirds and middle and the edges and middles of our other shown frames, and the same up and down, with a
-- guide line across the screen where one holds. Shift drags it free. After Spoken's Snap.lua.
--
-- An addon calls ForeverSnap.Register(frame) once (an OptionalDep, so check ForeverSnap first).
-- That swaps the frame's own StartMoving and StopMovingOrSizing for ones that snap, so the
-- addon's drag and save code stays as it is. After the drop the frame hangs from UIParent by the
-- same point it hung from before (BOTTOM for a list that grows up), with relativePoint equal to
-- point: both ways our addons save and restore a position read that back right.
--
-- Every length here is in UIParent units, up from the screen's bottom left.

ForeverSnap = {}

-- How close, in screen pixels, a frame comes before it is drawn to a line.
local REACH = 10
local GUIDE = { 1, 0.82, 0, 0.8 }

-- Where on a frame each anchor point is: share of the width from the left, of the height from
-- the bottom.
local SPOT = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local registered = setmetatable({}, { __mode = "k" }) -- frame -> its own StartMoving, StopMovingOrSizing
local state -- the drag under way, or nil

-- One screen pixel in UIParent units.
local function Pixel()
	local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1
	return factor / UIParent:GetEffectiveScale()
end

-- `frame`'s size against UIParent's units.
local function Scale(frame)
	return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- `frame`'s left, bottom, width and height in UIParent units, or nil while it has no place.
local function Rect(frame)
	local left, bottom, width, height = frame:GetRect()
	if not left then return nil end
	local scale = Scale(frame)
	return left * scale, bottom * scale, width * scale, height * scale
end

-- True when `frame` hangs from or sits inside `dragged`, so moves with it.
local function Follows(frame, dragged)
	local seen = 0
	local queue = { frame }
	while #queue > 0 and seen < 50 do
		local f = table.remove(queue)
		seen = seen + 1
		if f == dragged then return true end
		local parent = f.GetParent and f:GetParent()
		if parent and parent ~= UIParent then table.insert(queue, parent) end
		for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do
			local _, relative = f:GetPoint(i)
			if relative and relative ~= UIParent then table.insert(queue, relative) end
		end
	end
	return false
end

-- The lines the dragged frame may meet, as two lists of { its side, the line }: sides 0, 0.5 and
-- 1 for left, middle and right (bottom, middle and top). The screen's edges meet its own, its
-- middle its middle; another frame's edges meet its edges either way, so it lines up with it or
-- sits beside it, and its middle meets its middle.
local function Lines(dragged)
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local across = { { 0, 0 }, { 0.5, screenWidth / 2 }, { 1, screenWidth } }
	local up = { { 0, 0 }, { 0.5, screenHeight / 2 }, { 1, screenHeight } }
	-- The screen's thirds meet its edges and its middle, so it can sit beside a third or on it.
	for _, third in ipairs({ 1 / 3, 2 / 3 }) do
		for _, side in ipairs({ 0, 0.5, 1 }) do
			table.insert(across, { side, screenWidth * third })
			table.insert(up, { side, screenHeight * third })
		end
	end
	for frame in pairs(registered) do
		if frame ~= dragged and frame:IsVisible() and not Follows(frame, dragged) then
			local left, bottom, width, height = Rect(frame)
			if left then
				for _, side in ipairs({ 0, 1 }) do
					table.insert(across, { 0, left + side * width })
					table.insert(across, { 1, left + side * width })
					table.insert(up, { 0, bottom + side * height })
					table.insert(up, { 1, bottom + side * height })
				end
				table.insert(across, { 0.5, left + width / 2 })
				table.insert(up, { 0.5, bottom + height / 2 })
			end
		end
	end
	return across, up
end

-- The nearest pull of `lines` within `reach` on a span from `low`, `size` long: how far to move,
-- and the line it lands on. 0 and nil where none is near.
local function Pull(lines, low, size, reach)
	local best, line
	for _, option in ipairs(lines) do
		local delta = option[2] - (low + option[1] * size)
		if math.abs(delta) <= reach and (not best or math.abs(delta) < math.abs(best)) then
			best, line = delta, option[2]
		end
	end
	return best or 0, line
end

local guides
local function ShowGuides(lineX, lineY)
	if not lineX and not lineY then
		if guides then guides:Hide() end
		return
	end
	if not guides then
		guides = CreateFrame("Frame", nil, UIParent)
		guides:SetAllPoints(UIParent)
		guides:SetFrameStrata("TOOLTIP")
		guides.across = guides:CreateTexture(nil, "OVERLAY")
		guides.up = guides:CreateTexture(nil, "OVERLAY")
		for _, line in ipairs({ guides.across, guides.up }) do
			line:SetColorTexture(GUIDE[1], GUIDE[2], GUIDE[3], GUIDE[4])
		end
	end
	local thin = Pixel()
	guides.across:SetWidth(thin)
	guides.up:SetHeight(thin)
	guides.across:ClearAllPoints()
	guides.up:ClearAllPoints()
	if lineX then
		guides.across:SetPoint("TOPLEFT", guides, "TOPLEFT", lineX - thin / 2, 0)
		guides.across:SetPoint("BOTTOMLEFT", guides, "BOTTOMLEFT", lineX - thin / 2, 0)
		guides.across:Show()
	else
		guides.across:Hide()
	end
	if lineY then
		guides.up:SetPoint("BOTTOMLEFT", guides, "BOTTOMLEFT", 0, lineY - thin / 2)
		guides.up:SetPoint("BOTTOMRIGHT", guides, "BOTTOMRIGHT", 0, lineY - thin / 2)
		guides.up:Show()
	else
		guides.up:Hide()
	end
	guides:Show()
end

-- Hang `frame` from UIParent by `point` so its bottom left lands on `left`, `bottom`.
local function Place(frame, point, left, bottom, width, height)
	local spot = SPOT[point] or SPOT.TOPLEFT
	local scale = Scale(frame)
	local x = left + spot[1] * width - spot[1] * UIParent:GetWidth()
	local y = bottom + spot[2] * height - spot[2] * UIParent:GetHeight()
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x / scale, y / scale)
end

local driver = CreateFrame("Frame")

local function Move()
	local drag = state
	local frame = drag.frame
	if not frame:IsShown() or (InCombatLockdown() and frame:IsProtected()) then
		ForeverSnap.Stop(frame)
		return
	end
	local ui = UIParent:GetEffectiveScale()
	local _, _, width, height = Rect(frame)
	if not width then return end
	local x, y = GetCursorPosition()
	-- Kept on the screen, as our frames are clamped to it.
	local left = math.max(0, math.min(UIParent:GetWidth() - width, drag.left + (x - drag.x) / ui))
	local bottom = math.max(0, math.min(UIParent:GetHeight() - height, drag.bottom + (y - drag.y) / ui))
	local lineX, lineY
	if not IsShiftKeyDown() then
		local reach = REACH * Pixel()
		local dx, dy
		dx, lineX = Pull(drag.across, left, width, reach)
		dy, lineY = Pull(drag.up, bottom, height, reach)
		left, bottom = left + dx, bottom + dy
	end
	Place(frame, drag.point, left, bottom, width, height)
	ShowGuides(lineX, lineY)
end

--- Start dragging `frame` after the pointer, snapping. Falls back to its own StartMoving for a
--- protected frame in combat, where only that may move it.
function ForeverSnap.Start(frame)
	local own = registered[frame]
	if InCombatLockdown() and frame:IsProtected() then
		if own then own.start(frame) else frame:StartMoving() end
		return
	end
	local left, bottom = Rect(frame)
	if not left then return end
	if state then ForeverSnap.Stop(state.frame) end
	local point = frame:GetPoint(1)
	local x, y = GetCursorPosition()
	-- Other frames' lines are read once: none of them moves while this one does.
	local across, up = Lines(frame)
	state = {
		frame = frame, point = SPOT[point] and point or "TOPLEFT",
		x = x, y = y, left = left, bottom = bottom, across = across, up = up,
	}
	driver:SetScript("OnUpdate", Move)
end

--- Let go of `frame` where it is.
function ForeverSnap.Stop(frame)
	if not state or state.frame ~= frame then
		local own = registered[frame]
		if own then own.stop(frame) else frame:StopMovingOrSizing() end
		return
	end
	state = nil
	driver:SetScript("OnUpdate", nil)
	ShowGuides(nil, nil)
end

--- Make `frame` snap when it is dragged, and a line other dragged frames snap to while shown.
function ForeverSnap.Register(frame)
	if registered[frame] then return end
	registered[frame] = { start = frame.StartMoving, stop = frame.StopMovingOrSizing }
	frame.StartMoving = ForeverSnap.Start
	frame.StopMovingOrSizing = ForeverSnap.Stop
end
