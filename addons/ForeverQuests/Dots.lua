-- The pfQuest-style marker: a round dot in the quest's colour with a dark
-- rim. Hovering shows what to find there; clicks go through to the map.

local _, ns = ...

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Masked(dot, layer, sublevel)
	local texture = dot:CreateTexture(nil, layer, nil, sublevel)
	local mask = dot:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end

local function OnEnter(dot)
	local target = dot.point and dot.point.target
	if not target then
		return
	end
	local quest = target.quest
	local r, g, b = unpack(quest.color or { 1, 0.82, 0 })
	GameTooltip:SetOwner(dot, "ANCHOR_RIGHT")
	GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(quest.questID) or ("Quest " .. quest.questID), r, g, b)
	if target.source then
		GameTooltip:AddLine(target.source, 1, 1, 1)
	end
	local detail = target.progress or target.label
	if detail and detail ~= target.source then
		GameTooltip:AddLine(detail, 0.8, 0.8, 0.8, true)
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
	local color = point.target.quest.color or { 1, 0.82, 0 }
	dot.fill:SetColorTexture(color[1], color[2], color[3], 1)
end

function ns.CreateDot(parent, size)
	local dot = CreateFrame("Frame", nil, parent)
	dot:SetSize(size, size)
	dot.rim = Masked(dot, "ARTWORK", 1)
	dot.rim:SetAllPoints()
	dot.rim:SetColorTexture(0, 0, 0, 0.85)
	dot.fill = Masked(dot, "ARTWORK", 2)
	local inset = math.max(1, size * 0.17)
	dot.fill:SetPoint("TOPLEFT", inset, -inset)
	dot.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
	dot:SetMouseClickEnabled(false)
	dot:SetMouseMotionEnabled(true)
	dot:SetScript("OnEnter", OnEnter)
	dot:SetScript("OnLeave", OnLeave)
	dot.SetPointData = SetPointData
	return dot
end

-- The dots on one parent, one per spawn point (point.spot), so a dot that
-- stays does not flicker when the set changes. New dots fade in, dots that
-- are no longer wanted fade out and then go back to the free list.
local FADE = 0.2 -- seconds

function ns.DotPool(parent, size)
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
			dot = table.remove(self.free) or ns.CreateDot(parent, size)
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
