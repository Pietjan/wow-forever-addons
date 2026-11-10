-- The pfQuest-style marker: a round dot in the quest's colour with a dark
-- rim. Hovering shows what to find there; clicks go through to the map.

local _, ns = ...

local TEXTURE = "Interface\\AddOns\\ForeverQuests\\dot" -- white disc, dark rim; tinted per quest
-- The game's own turn-in pin: a dark round button with the "?" on top.
local TURN_IN_BUTTON = "UI-QuestPoi-QuestNumber"
local TURN_IN_ICON = "UI-QuestIcon-TurnIn-Normal"
-- The plain yellow "?" on its own, for small markers (minimap).
local TURN_IN_PLAIN = "QuestTurnin"
local MAX_LINES = 5

local function AddUnique(lines, seen, text)
	if text and not seen[text] and #lines < MAX_LINES then
		seen[text] = true
		lines[#lines + 1] = text
	end
end

local function OnEnter(dot)
	local point = dot.point
	if not point then
		return
	end
	local quest = point.target.quest
	local r, g, b = unpack(quest.color or { 0.95, 0.95, 0.95 })
	GameTooltip:SetOwner(dot, "ANCHOR_RIGHT")
	GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(quest.questID) or ("Quest " .. quest.questID), r, g, b)
	if point.target.turnIn then
		GameTooltip:AddLine("Turn in: " .. (point.target.source or "?"), 1, 1, 1)
		GameTooltip:Show()
		return
	end
	local sources, objectives, seen = {}, {}, {}
	for _, target in ipairs(point.targets or { point.target }) do
		AddUnique(sources, seen, target.source)
		local detail = target.progress or target.label
		if detail ~= target.source then
			AddUnique(objectives, seen, detail)
		end
	end
	for _, text in ipairs(sources) do
		GameTooltip:AddLine(text, 1, 1, 1)
	end
	for _, text in ipairs(objectives) do
		GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
	end
	if point.n and point.n > 1 then
		GameTooltip:AddLine(point.n .. " spawns here", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function OnLeave(dot)
	if GameTooltip:GetOwner() == dot then
		GameTooltip:Hide()
	end
end

local function SetPointData(dot, point)
	dot.point = point
	if point.target.turnIn then
		if dot.style ~= "turnIn" then
			dot.style = "turnIn"
			dot.texture:SetVertexColor(1, 1, 1, 1)
			if dot.plainTurnIn then
				dot.texture:SetAtlas(TURN_IN_PLAIN)
			else
				dot.texture:SetAtlas(TURN_IN_BUTTON)
				dot.icon:SetAtlas(TURN_IN_ICON)
				dot.icon:Show()
			end
			dot:SetSize(dot.turnInSize, dot.turnInSize)
		end
		return
	end
	if dot.style ~= "dot" then
		dot.style = "dot"
		dot.texture:SetTexture(TEXTURE, "CLAMP", "CLAMP", "TRILINEAR")
		dot.texture:SetTexCoord(0, 1, 0, 1)
		dot.icon:Hide()
		dot:SetSize(dot.size, dot.size)
	end
	local color = point.target.quest.color or { 0.95, 0.95, 0.95 }
	dot.texture:SetVertexColor(color[1], color[2], color[3], 1)
end

function ns.CreateDot(parent, size, turnInSize, plainTurnIn)
	local dot = CreateFrame("Frame", nil, parent)
	dot.size = size
	dot.turnInSize = turnInSize or size
	dot.plainTurnIn = plainTurnIn
	dot.style = "dot"
	dot:SetSize(size, size)
	dot.texture = dot:CreateTexture(nil, "ARTWORK")
	dot.texture:SetAllPoints()
	dot.texture:SetTexture(TEXTURE, "CLAMP", "CLAMP", "TRILINEAR")
	dot.icon = dot:CreateTexture(nil, "OVERLAY")
	dot.icon:SetAllPoints()
	dot.icon:Hide()
	dot:SetMouseClickEnabled(false)
	dot:SetMouseMotionEnabled(true)
	dot:SetScript("OnEnter", OnEnter)
	dot:SetScript("OnLeave", OnLeave)
	dot.SetPointData = SetPointData
	return dot
end

-- Blizzard's map ping ripple (MapPinPingTemplate): a ring that grows and
-- flashes twice per loop. Played on a turn-in marker when the game pings
-- its quest.
local RIPPLE_TEXTURE = "Interface\\Minimap\\UI-Minimap-Ping-Expand"
local RIPPLE_SIZE = 1.5 -- times the marker size
local RIPPLE_LOOPS = 2

local function Alpha(group, target, from, to, delay)
	local anim = group:CreateAnimation("Alpha")
	anim:SetTarget(target)
	anim:SetFromAlpha(from)
	anim:SetToAlpha(to)
	anim:SetStartDelay(delay)
	anim:SetDuration(0.2)
	anim:SetOrder(1)
end

function ns.PlayRipple(dot)
	local ripple = dot.ripple
	if not ripple then
		ripple = dot:CreateTexture(nil, "BACKGROUND")
		ripple:SetTexture(RIPPLE_TEXTURE)
		ripple:SetPoint("CENTER")
		ripple:SetAlpha(0)
		local driver = dot:CreateAnimationGroup()
		Alpha(driver, ripple, 0, 1, 0)
		Alpha(driver, ripple, 1, 0, 0.45)
		Alpha(driver, ripple, 0, 1, 0.575)
		Alpha(driver, ripple, 1, 0, 0.95)
		local grow = dot:CreateAnimationGroup()
		grow:SetLooping("REPEAT")
		local scale = grow:CreateAnimation("Scale")
		scale:SetTarget(ripple)
		scale:SetScaleFrom(0.5, 0.5)
		scale:SetScaleTo(1.2, 1.2)
		scale:SetDuration(0.575)
		driver:SetScript("OnFinished", function()
			grow:Stop()
			dot.rippleLoops = dot.rippleLoops - 1
			if dot.rippleLoops > 0 then
				driver:Play()
				grow:Play()
			end
		end)
		ripple.driver, ripple.grow = driver, grow
		dot.ripple = ripple
	end
	local size = dot:GetWidth() * RIPPLE_SIZE
	ripple:SetSize(size, size)
	ripple.driver:Stop()
	ripple.grow:Stop()
	dot.rippleLoops = RIPPLE_LOOPS
	ripple.driver:Play()
	ripple.grow:Play()
end

-- The dots on one parent, one per spawn point (point.spot), so a dot that
-- stays does not flicker when the set changes. New dots fade in, dots that
-- are no longer wanted fade out and then go back to the free list.
local FADE = 0.2 -- seconds

-- size: dot size; turnInSize: size of the turn-in "?" markers; plainTurnIn:
-- a bare "?" instead of the game's round quest pin.
function ns.DotPool(parent, size, turnInSize, plainTurnIn)
	local pool = { active = {}, free = {}, fading = {} }
	local driver = CreateFrame("Frame", nil, parent)

	local function Fade(_, elapsed)
		local step = elapsed / FADE
		for dot in pairs(pool.fading) do
			local alpha = dot:GetAlpha()
			if dot.wanted then
				alpha = math.min(1, alpha + step)
			else
				alpha = math.max(0, alpha - step)
			end
			dot:SetAlpha(alpha)
			if dot.wanted and alpha >= 1 then
				pool.fading[dot] = nil
			elseif not dot.wanted and alpha <= 0 then
				pool.fading[dot] = nil
				pool.active[dot.key] = nil
				dot:Hide()
				dot.key, dot.point = nil, nil
				pool.free[#pool.free + 1] = dot
			end
		end
		if not next(pool.fading) then
			driver:SetScript("OnUpdate", nil)
		end
	end

	local function StartFade(dot, wanted)
		dot.wanted = wanted
		dot:SetMouseMotionEnabled(wanted)
		if wanted and not dot:IsShown() then
			dot:SetAlpha(0)
			dot:Show()
		end
		if wanted then
			if dot:GetAlpha() >= 1 then
				return
			end
		elseif not wanted and OnLeave then
			OnLeave(dot)
		end
		pool.fading[dot] = true
		driver:SetScript("OnUpdate", Fade)
	end

	function pool:Begin()
		for _, dot in pairs(self.active) do
			dot.seen = false
		end
	end

	function pool:Acquire(point)
		local key = point.spot or point
		local dot = self.active[key]
		if not dot then
			dot = table.remove(self.free) or ns.CreateDot(parent, size, turnInSize, plainTurnIn)
			dot.key = key
			dot.wanted = false
			dot:Hide()
			self.active[key] = dot
		end
		dot.seen = true
		dot:SetPointData(point)
		if not dot.wanted then
			StartFade(dot, true)
		end
		return dot
	end

	-- Drop every dot at once, for when the map underneath changes.
	function pool:Clear()
		for key, dot in pairs(self.active) do
			OnLeave(dot)
			dot:Hide()
			dot.key, dot.point, dot.wanted = nil, nil, false
			self.active[key] = nil
			self.fading[dot] = nil
			self.free[#self.free + 1] = dot
		end
	end

	function pool:Finish()
		for _, dot in pairs(self.active) do
			if not dot.seen and dot.wanted then
				StartFade(dot, false)
			end
		end
	end

	return pool
end
