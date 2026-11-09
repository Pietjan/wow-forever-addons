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

-- A growable set of dots on one parent.
function ns.DotPool(parent, size)
	local pool = { dots = {}, used = 0 }
	function pool:Acquire(point)
		self.used = self.used + 1
		local dot = self.dots[self.used]
		if not dot then
			dot = ns.CreateDot(parent, size)
			self.dots[self.used] = dot
		end
		dot:SetPointData(point)
		dot:Show()
		return dot
	end
	function pool:Begin()
		self.used = 0
	end
	function pool:Finish()
		for i = self.used + 1, #self.dots do
			local dot = self.dots[i]
			if dot:IsShown() then
				OnLeave(dot)
				dot:Hide()
			end
		end
	end
	return pool
end
