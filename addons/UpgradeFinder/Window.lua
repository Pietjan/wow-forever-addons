-- UpgradeFinder, the window: the upgrades slot by slot, the best five of
-- each, best first. /upgrades (or /upgradefinder) shows or hides it.
--
--   a slot's name   lists all of that slot's upgrades, or the best five again
--   an item         its tooltip, with every known way to get it;
--                   Shift-click links it in chat
--   the checkbox    also lists items with no known source
--   a role button   scores as that role: the list, and UpgradeArrow's
--                   arrows and tooltips with it. Automatic follows your
--                   group again. A class with one role has no buttons.
--   Weights         opens a pane beside the window with the weights of
--                   the role scored for, one line per stat. Drag a
--                   slider or click its arrows for one step. A slider
--                   stops where weights usually do; a higher one, set
--                   with /upgradearrow or on the options pages, shows
--                   as its number with the slider at its end. A green
--                   number is a weight you changed, Defaults puts the
--                   class's own back. They are UpgradeArrow's weights:
--                   its arrows and tooltips change with them.
--
-- The number is how many points the item scores above what you wear, in
-- UpgradeArrow's points; "empty slot" where you wear nothing. The rows
-- are made once and filled in again on every change.

local ADDON, ns = ...

local WIDTH, HEIGHT = 640, 520
local ROW = 20
local ROLE_TOP = 28 -- the line with the role, under the title
local LIST_TOP, LIST_BOTTOM = 54, 40
local ROLE_BUTTON = 76 -- wide; the Weights button too
local PANE = 370 -- the weights pane, wide
local SLIDER = 150 -- a weight's slider with its step arrows, wide
local WEIGHTS_TOP = 30 -- its first line, under its title
local WEIGHT_ROW = 20
local BEST = 5 -- per slot, until its name is clicked
local WAYS_IN_TIP = 8

local window
local rows = {} -- the row buttons, made as the height asks for them
local list = {} -- what is listed: { group, count } and { entry } rows
local offset = 0
local all = {} -- group -> true: every upgrade of that slot is listed
local upgrades, slots = 0, 0

local function Better(a, b)
	if a.gain ~= b.gain then
		return a.gain > b.gain
	end
	return a.name < b.name
end

local function BuildList()
	ns.Collect()
	list, upgrades, slots = {}, 0, 0
	for _, group in ipairs(ns.GROUPS) do
		local entries = ns.results[group]
		if entries and #entries > 0 then
			table.sort(entries, Better)
			upgrades, slots = upgrades + #entries, slots + 1
			list[#list + 1] = { group = group, count = #entries }
			for i = 1, all[group] and #entries or math.min(BEST, #entries) do
				list[#list + 1] = { entry = entries[i] }
			end
		end
	end
end

local function Count(number, word)
	return ("%d %s%s"):format(number, word, number == 1 and "" or "s")
end

local function Status()
	local progress = ns.progress
	if not ns.Ready() then
		return "Needs UpgradeArrow and QuestieDB."
	elseif ns.phase == "scan" then
		return ("Reading the item list: %d%%"):format(progress.of > 0 and progress.at / progress.of * 100 or 0)
	elseif ns.phase == "load" then
		return ("Going through %d items: %d done"):format(progress.of, progress.at)
	elseif ns.phase ~= "done" then
		return ""
	end
	local text = upgrades == 0 and "Nothing you could get now beats what you wear."
		or ("%s in %s."):format(Count(upgrades, "upgrade"), Count(slots, "slot"))
	if progress.silent > 0 then
		text = text .. (" %s did not answer."):format(Count(progress.silent, "item"))
	end
	return text
end

local function RowTooltip(self)
	local entry = self.row and self.row.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(entry.link)
	GameTooltip:AddLine(" ")
	if #entry.ways == 0 then
		GameTooltip:AddLine("Source unknown", 0.6, 0.6, 0.6)
	end
	for i, way in ipairs(entry.ways) do
		if i > WAYS_IN_TIP then
			GameTooltip:AddLine(("and %d more"):format(#entry.ways - WAYS_IN_TIP), 0.6, 0.6, 0.6)
			break
		end
		GameTooltip:AddLine(ns.Describe(way), 1, 0.82, 0, true)
	end
	GameTooltip:Show()
end

local Draw

-- Into the chat line being typed, or a new one when none is open.
local function Link(link)
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		if not ChatFrameUtil.InsertLink(link) and ChatFrameUtil.OpenChat then
			ChatFrameUtil.OpenChat(link)
		end
	elseif ChatEdit_InsertLink and not ChatEdit_InsertLink(link) and ChatFrame_OpenChat then
		ChatFrame_OpenChat(link)
	end
end

local function RowClick(self)
	local row = self.row
	if row and row.group then
		all[row.group] = not all[row.group] or nil
		Draw()
	elseif row and row.entry and IsModifiedClick("CHATLINK") then
		Link(row.entry.link)
	end
end

local function MakeRow(index)
	local button = CreateFrame("Button", nil, window)
	button:SetHeight(ROW)
	button:SetPoint("TOPLEFT", 10, -LIST_TOP - (index - 1) * ROW)
	button:SetPoint("RIGHT", -14, 0)
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", RowClick)
	button:SetScript("OnEnter", RowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)

	button.slot = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	button.slot:SetPoint("LEFT", 2, 0)
	button.slot:SetJustifyH("LEFT")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(16, 16)
	button.icon:SetPoint("LEFT", 12, 0)
	button.name = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.name:SetPoint("LEFT", 34, 0)
	button.name:SetWidth(200)
	button.gain = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.gain:SetPoint("LEFT", 238, 0)
	button.gain:SetWidth(66)
	button.source = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.source:SetPoint("LEFT", 312, 0)
	button.source:SetPoint("RIGHT", 0, 0)
	for _, text in ipairs({ button.name, button.gain, button.source }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	button.gain:SetJustifyH("RIGHT")
	return button
end

local function FillRow(button, row)
	button.row = row
	local entry = row.entry
	button.slot:SetShown(not entry)
	button.icon:SetShown(entry ~= nil)
	button.name:SetShown(entry ~= nil)
	button.gain:SetShown(entry ~= nil)
	button.source:SetShown(entry ~= nil)
	if not entry then
		local text = ("%s  |cffffffff%d|r"):format(row.group, row.count)
		if row.count > BEST then
			text = text .. (all[row.group] and "  |cff808080click for the best %d|r" or "  |cff808080click for all|r"):format(BEST)
		end
		button.slot:SetText(text)
	else
		local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
		button.icon:SetTexture(entry.icon)
		button.name:SetText(colour and colour.hex and (colour.hex .. entry.name .. "|r") or entry.name)
		button.gain:SetText(entry.empty and "|cff40c040empty slot|r" or ("|cff40c040+%.1f|r"):format(entry.gain))
		button.source:SetText(#entry.ways == 0 and "|cff808080Source unknown|r" or ns.Headline(entry))
	end
	button:Show()
end

local function VisibleRows()
	return math.max(1, math.floor((window:GetHeight() - LIST_TOP - LIST_BOTTOM) / ROW))
end

-- The weights pane -------------------------------------------------------------

local function Number(value)
	return ("%g"):format(value)
end

local function WeightTooltip(self)
	local weight = self.weight
	if not weight then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(weight.name, 1, 1, 1)
	GameTooltip:AddLine(("Points for one %s on an item."):format(weight.stat), 1, 0.82, 0, true)
	GameTooltip:AddLine(weight.value ~= weight.default and ("Your class's own: " .. Number(weight.default))
		or "This is your class's own.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- A value as the slider's steps have it: 0.3, not 0.30000001.
local function OnStep(value, step)
	return tonumber(("%.4f"):format(math.floor(value / step + 0.5) * step))
end

-- The slider was moved by hand: where it stands is the new weight.
local function WeightSlid(line, value)
	local weight = line.weight
	if line.muted or not weight then
		return
	end
	value = OnStep(value, weight.step)
	if value ~= weight.value then
		UpgradeArrow.SetWeight(weight.stat, value) -- comes back through UpgradeArrow.OnChange
		Draw()
	end
end

local function MakeWeightLine(pane, index, weight)
	local line = CreateFrame("Frame", nil, pane)
	line:SetHeight(WEIGHT_ROW)
	line:SetPoint("TOPLEFT", 14, -WEIGHTS_TOP - (index - 1) * WEIGHT_ROW)
	line:SetPoint("RIGHT", -12, 0)
	line:EnableMouse(true)
	line:SetScript("OnEnter", WeightTooltip)
	line:SetScript("OnLeave", function() GameTooltip:Hide() end)

	line.name = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	line.name:SetPoint("LEFT", 0, 0)
	line.name:SetPoint("RIGHT", -62 - SLIDER, 0)
	line.name:SetJustifyH("LEFT")
	line.name:SetWordWrap(false)

	line.number = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	line.number:SetPoint("RIGHT", -2, 0)
	line.number:SetWidth(44)
	line.number:SetJustifyH("RIGHT")

	-- The game's slider with step arrows, as on its options pages, from 0
	-- to where weights usually go.
	local slider = CreateFrame("Frame", nil, line, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(SLIDER, 19)
	slider:SetPoint("RIGHT", line.number, "LEFT", -10, 0)
	slider:Init(0, 0, weight.max, math.floor(weight.max / weight.step + 0.5))
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, WeightSlid, line)
	line.slider = slider
	line.muted = false -- true while the slider is moved from here, not by hand

	pane.lines[index] = line
	return line
end

-- The weights of the role scored for; the pane's title names the role.
local function DrawWeights()
	local pane = window.weights
	if not (pane and pane:IsShown()) then
		return
	end
	local _, name = UpgradeArrow.Role()
	pane.TitleContainer.TitleText:SetText((name or "?") .. " weights")
	for i, weight in ipairs(UpgradeArrow.Weights()) do
		local line = pane.lines[i] or MakeWeightLine(pane, i, weight)
		line.weight = weight
		-- The slider follows the weight, as far as it goes. Moved from here
		-- it sets nothing: a weight set higher elsewhere stays what it is.
		local at = OnStep(math.max(0, math.min(weight.value, weight.max)), weight.step)
		if OnStep(line.slider.Slider:GetValue(), weight.step) ~= at then
			line.muted = true
			line.slider:SetValue(at)
			line.muted = false
		end
		line.name:SetText((weight.value == 0 and "|cff808080" or "|cffffffff") .. weight.name .. "|r")
		line.number:SetText(Number(weight.value))
		if weight.value ~= weight.default then
			line.number:SetTextColor(0.25, 0.75, 0.25) -- yours, not the class's own
		else
			line.number:SetTextColor(1, 1, 1)
		end
	end
end

local ShowPane

local function MakePane()
	local pane = CreateFrame("Frame", nil, window, "DefaultPanelTemplate")
	pane:SetSize(PANE, HEIGHT)
	pane:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, 0)
	pane:EnableMouse(true)
	pane:Hide()
	pane.lines = {}

	local close = CreateFrame("Button", nil, pane, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	close:SetScript("OnClick", function() ShowPane(false) end)

	local defaults = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
	defaults:SetSize(ROLE_BUTTON, 22)
	defaults:SetPoint("BOTTOMRIGHT", -12, 12)
	defaults:SetText("Defaults")
	defaults:SetScript("OnClick", function()
		UpgradeArrow.ResetWeights() -- comes back through UpgradeArrow.OnChange
		Draw()
	end)
	pane.defaults = defaults

	window.weights = pane
	return pane
end

function ShowPane(show)
	local pane = window.weights or MakePane()
	pane:SetShown(show)
	-- The window cannot be dragged so far right that the pane leaves the screen.
	window:SetClampRectInsets(0, show and PANE or 0, 0, 0)
	if show then
		window.weightsButton:LockHighlight()
	else
		window.weightsButton:UnlockHighlight()
	end
	Draw()
end

-- The role line -----------------------------------------------------------------

-- The role UpgradeArrow scores for, and which button that is.
local function DrawRole()
	local key, name, fixed = UpgradeArrow.Role()
	window.scoring:SetText(("Scoring as |cffffffff%s|r%s"):format(name or "?", fixed and "" or " (automatic)"))
	for _, button in ipairs(window.roles) do
		if button.role == (fixed and key) then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
end

-- button.role: a role's key, or false for automatic.
local function RoleClick(self)
	local key, _, fixed = UpgradeArrow.Role()
	if self.role == (fixed and key) then
		return -- it is that already
	end
	UpgradeArrow.SetRole(self.role or nil) -- comes back through UpgradeArrow.OnChange
	Draw()
end

local function RoleTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(self.role and ("Score as " .. self:GetText():lower()) or "Follow your group", 1, 1, 1)
	GameTooltip:AddLine(self.role and "Until you pick another." or "Your role in the group, else the role ticked in the group finder, else damage.", 1, 0.82, 0, true)
	GameTooltip:AddLine("UpgradeArrow's arrows and tooltips change with it.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function MakeRoles()
	window.scoring = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.scoring:SetPoint("TOPLEFT", 12, -ROLE_TOP - 4)
	window.scoring:SetJustifyH("LEFT")
	window.roles = {}

	local weights = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	weights:SetSize(ROLE_BUTTON, 22)
	weights:SetPoint("TOPRIGHT", -14, -ROLE_TOP)
	weights:SetText("Weights")
	weights:SetScript("OnClick", function()
		ShowPane(not (window.weights and window.weights:IsShown()))
	end)
	window.weightsButton = weights

	local roles = UpgradeArrow.Roles()
	if #roles < 2 then
		return -- nothing to pick
	end
	local choices = { { key = false, name = "Automatic" } }
	for _, role in ipairs(roles) do
		choices[#choices + 1] = role
	end
	for i, choice in ipairs(choices) do
		local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
		button:SetSize(ROLE_BUTTON, 22)
		-- Left of the Weights button, with a gap.
		button:SetPoint("TOPRIGHT", -14 - (ROLE_BUTTON + 10) - (#choices - i) * (ROLE_BUTTON + 2), -ROLE_TOP)
		button:SetText(choice.name)
		button.role = choice.key
		button:SetScript("OnClick", RoleClick)
		button:SetScript("OnEnter", RoleTooltip)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		window.roles[i] = button
	end
end

function Draw()
	BuildList()
	if window.scoring then
		DrawRole()
		DrawWeights()
	end
	local visible = VisibleRows()
	offset = math.max(0, math.min(offset, #list - visible))
	for index = 1, math.max(visible, #rows) do
		local row = index <= visible and list[offset + index] or nil
		if row then
			rows[index] = rows[index] or MakeRow(index)
			FillRow(rows[index], row)
		elseif rows[index] then
			rows[index].row = nil
			rows[index]:Hide()
		end
	end

	-- Where the listed part sits in the whole list.
	local track = visible * ROW
	if #list > visible then
		window.thumb:SetHeight(math.max(12, track * visible / #list))
		window.thumb:SetPoint("TOPRIGHT", -6, -LIST_TOP - (track - window.thumb:GetHeight()) * offset / (#list - visible))
		window.thumb:Show()
	else
		window.thumb:Hide()
	end
	window.status:SetText(Status())
end

local function MakeWindow()
	window = CreateFrame("Frame", "UpgradeFinderFrame", UIParent, "DefaultPanelTemplate")
	window:SetSize(WIDTH, HEIGHT)
	window:SetFrameStrata("MEDIUM")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	if ForeverSnap then ForeverSnap.Register(window) end -- snaps to the screen and our other frames
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relative, x, y = self:GetPoint(1)
		ns.db.point = { point, relative, x, y }
	end)
	local at = ns.db.point
	if type(at) == "table" and at[1] then
		window:SetPoint(at[1], UIParent, at[2], at[3], at[4])
	else
		window:SetPoint("CENTER")
	end
	window:Hide()
	window.TitleContainer.TitleText:SetText(ADDON)
	if type(UISpecialFrames) == "table" then
		tinsert(UISpecialFrames, "UpgradeFinderFrame") -- Escape closes it
	end

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)

	if ns.Ready() then
		MakeRoles()
	end

	window.thumb = window:CreateTexture(nil, "ARTWORK")
	window.thumb:SetWidth(4)
	window.thumb:SetColorTexture(1, 0.82, 0, 0.6)

	window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.status:SetPoint("BOTTOMLEFT", 12, 14)
	window.status:SetJustifyH("LEFT")
	window.status:SetWordWrap(false)

	local box = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint("BOTTOMRIGHT", -190, 8)
	local caption = box.Text or box.text
	if caption then
		caption:SetText("Also items with no known source")
		caption:SetFontObject("GameFontHighlightSmall")
	end
	box:SetChecked(ns.db.unknown and true or false)
	box:SetScript("OnClick", function(self)
		ns.ShowUnknown(self:GetChecked())
	end)
	window.status:SetPoint("RIGHT", box, "LEFT", -8, 0)

	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Draw()
	end)
	window:SetScript("OnShow", function()
		ns.Run()
		Draw()
	end)
end

function ns.Shown()
	return window ~= nil and window:IsShown()
end

function ns.Changed()
	if ns.Shown() then
		Draw()
	end
end

SLASH_UPGRADEFINDER1 = "/upgrades"
SLASH_UPGRADEFINDER2 = "/upgradefinder"
SlashCmdList.UPGRADEFINDER = function()
	if not ns.db then
		return
	end
	if not window then
		MakeWindow()
	end
	window:SetShown(not window:IsShown())
end
