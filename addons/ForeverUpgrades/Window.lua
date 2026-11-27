-- ForeverUpgrades, the window: the upgrades slot by slot, the best five of
-- each, best first. /upgrades shows or hides it.
--
--   a slot's name   lists all of that slot's upgrades, or the best five again
--   an item         its tooltip, with every known way to get it;
--                   Shift-click links it in chat
--   the checkbox    also lists items with no known source
--   the spec menu   scores with that spec: the list, and the arrows
--                   and tooltips with it. Automatic follows your
--                   group again, with the spec last picked for its role.
--   Weights         opens a pane beside the window with the spec scored
--                   with: its role, and its weights, one line per stat.
--                   Drag a slider or click its arrows for one step. A
--                   slider stops where weights usually do; a higher one,
--                   set with /upgradearrow or on the options pages, shows
--                   as its number with the slider at its end. A green
--                   number is a weight you changed, Defaults puts back
--                   those of the class's own spec it was made from. New
--                   makes a copy to score with, Rename and Delete do what
--                   they say; a role's only spec cannot be deleted or
--                   moved. Specs are the arrows' too, shared by your
--                   characters of the class: its arrows and tooltips
--                   change with them.
--
-- The number is how many points the item scores above what you wear (or
-- the equipment set attached to the spec), in the arrows' points; "empty
-- slot" where there is nothing. The rows
-- are made once and filled in again on every change.

local ADDON, ns = ...

local WIDTH, HEIGHT = 640, 520
local ROW = 20
local ROLE_TOP = 28 -- the line with the role, under the title
local LIST_TOP, LIST_BOTTOM = 54, 40
local ROLE_BUTTON = 76 -- wide: the Weights button, and the pane's buttons
local SPEC_MENU = 190 -- the spec menu, wide
local ROLE_MENU = 140 -- the pane's role menu, wide
local PANE = 370 -- the weights pane, wide
local SLIDER = 150 -- a weight's slider with its step arrows, wide
local ROLE_LINE = 30 -- the pane's role line, under its title
local SET_LINE = 28 -- the pane's set line, under the role line
local WEIGHTS_TOP = 58 + SET_LINE -- its first weight, under the set line
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
		return "Needs QuestieDB, for where gear comes from."
	elseif ns.phase == "scan" then
		return ("Reading the item list: %d%%"):format(progress.of > 0 and progress.at / progress.of * 100 or 0)
	elseif ns.phase == "load" then
		return ("Going through %d items: %d done"):format(progress.of, progress.at)
	elseif ns.phase ~= "done" then
		return ""
	end
	local _, setName = UpgradeArrow.SpecSet()
	local text = upgrades == 0 and ("Nothing you could get now beats %s."):format(setName and ("your set " .. setName) or "what you wear")
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

-- The spec scored with, as UpgradeArrow.Specs lists it.
local function Current()
	local id = UpgradeArrow.Spec()
	for _, entry in ipairs(UpgradeArrow.Specs()) do
		if entry.id == id then
			return entry
		end
	end
end

-- What a menu shows, as one string: when it changes, the menu is made again.
local function Signature()
	local id, _, _, _, fixed = UpgradeArrow.Spec()
	local parts = { tostring(id), tostring(fixed), tostring((UpgradeArrow.SpecSet())) }
	for _, set in ipairs(UpgradeArrow.Sets()) do
		parts[#parts + 1] = set.id .. "=" .. set.name
	end
	for _, entry in ipairs(UpgradeArrow.Specs()) do
		parts[#parts + 1] = entry.id .. "=" .. entry.name .. "/" .. entry.role
	end
	return table.concat(parts, ";")
end

-- The spec scored with: the pane's title, its role, and its weights.
local function DrawWeights()
	local pane = window.weights
	if not (pane and pane:IsShown()) then
		return
	end
	local entry = Current()
	pane.TitleContainer.TitleText:SetText((entry and entry.name or "?") .. " weights")
	local signature = Signature()
	if pane.roleMenu and pane.drawn ~= signature then
		pane.drawn = signature
		pane.roleMenu:GenerateMenu()
		pane.setMenu:GenerateMenu()
		-- A role's only spec stays where it is; so does any spec of a class
		-- with one role.
		pane.roleMenu:SetEnabled(entry ~= nil and not entry.only and #UpgradeArrow.Roles() > 1)
	end
	pane.delete:SetEnabled(entry ~= nil and not entry.only)
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

-- Naming a spec, new or renamed, and deleting one: the game's popups. Only
-- our entries are added to StaticPopupDialogs: assigning the table itself
-- would mark it as ours, and block the game's popups that lead to a
-- protected action.

local function Typed(dialog)
	local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
	return box and box:GetText() or ""
end

local function Refused(err)
	print("|cff40c040ForeverUpgrades|r: " .. tostring(err) .. ".")
end

-- data: { id = (the spec renamed), name = (its name) }, or {} for a new
-- one. True keeps the popup open: the name was refused.
local function Named(dialog, data)
	local ok, err
	if data and data.id then
		ok, err = UpgradeArrow.RenameSpec(data.id, Typed(dialog))
	else
		ok, err = UpgradeArrow.NewSpec(Typed(dialog))
	end
	if not ok then
		Refused(err)
		return true
	end
	Draw()
end

StaticPopupDialogs.FOREVERUPGRADES_SPEC_NAME = {
	text = "%s",
	button1 = OKAY or "Okay",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 24,
	OnShow = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		if box then
			box:SetText(data and data.name or "")
			box:HighlightText()
		end
	end,
	OnAccept = Named,
	EditBoxOnEnterPressed = function(box, data)
		local dialog = box:GetParent()
		if not Named(dialog, data) then
			dialog:Hide()
		end
	end,
	EditBoxOnEscapePressed = function(box)
		box:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs.FOREVERUPGRADES_SPEC_DELETE = {
	text = "Delete the spec %s? It is gone for all your characters of this class.",
	button1 = DELETE or "Delete",
	button2 = CANCEL or "Cancel",
	OnAccept = function(_, data)
		local ok, err = UpgradeArrow.DeleteSpec(data.id)
		if not ok then
			Refused(err)
		end
		Draw()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function PaneButton(pane, text, right, onClick, tip)
	local button = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
	button:SetSize(ROLE_BUTTON, 22)
	button:SetPoint("BOTTOMRIGHT", -12 - right * (ROLE_BUTTON + 4), 12)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(text, 1, 1, 1)
		GameTooltip:AddLine(tip(), 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- A disabled button still shows why.
	if button.SetMotionScriptsWhileDisabled then
		button:SetMotionScriptsWhileDisabled(true)
	end
	return button
end

local function MakePane()
	local pane = CreateFrame("Frame", nil, window, "DefaultPanelTemplate")
	pane:SetSize(PANE, HEIGHT + SET_LINE)
	pane:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, 0)
	pane:EnableMouse(true)
	pane:Hide()
	pane.lines = {}

	local close = CreateFrame("Button", nil, pane, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	close:SetScript("OnClick", function() ShowPane(false) end)

	-- The spec's role.
	local label = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", 14, -ROLE_LINE - 5)
	label:SetText("Role")
	local menu = CreateFrame("DropdownButton", nil, pane, "WowStyle1DropdownTemplate")
	menu:SetWidth(ROLE_MENU)
	menu:SetPoint("LEFT", label, "RIGHT", 10, 0)
	menu:SetupMenu(function(_, root)
		local entry = Current()
		for _, role in ipairs(UpgradeArrow.Roles()) do
			root:CreateRadio(role.name, function() return entry and entry.role == role.key end, function()
				local ok, err = UpgradeArrow.SetSpecRole(entry.id, role.key)
				if not ok then
					Refused(err)
				end
				Draw()
			end)
		end
	end)
	pane.roleMenu = menu
	local hint = pane:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("LEFT", menu, "RIGHT", 10, 0)
	hint:SetPoint("RIGHT", -12, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Shared by the class")

	-- What items are compared with: what you wear, or one of this
	-- character's equipment sets.
	local setLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	setLabel:SetPoint("TOPLEFT", 14, -ROLE_LINE - SET_LINE - 5)
	setLabel:SetText("Against")
	local setMenu = CreateFrame("DropdownButton", nil, pane, "WowStyle1DropdownTemplate")
	setMenu:SetWidth(ROLE_MENU)
	setMenu:SetPoint("LEFT", setLabel, "RIGHT", 10, 0)
	setMenu:SetupMenu(function(_, root)
		local entry = Current()
		local function Pick(setID)
			return function()
				local ok, err = UpgradeArrow.SetSpecSet(entry.id, setID)
				if not ok then
					Refused(err)
				end
				Draw()
			end
		end
		root:CreateRadio("What you wear", function() return UpgradeArrow.SpecSet(entry.id) == nil end, Pick(nil))
		for _, set in ipairs(UpgradeArrow.Sets()) do
			root:CreateRadio(set.name, function() return UpgradeArrow.SpecSet(entry.id) == set.id end, Pick(set.id))
		end
	end)
	pane.setMenu = setMenu
	local setHint = pane:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	setHint:SetPoint("LEFT", setMenu, "RIGHT", 10, 0)
	setHint:SetPoint("RIGHT", -12, 0)
	setHint:SetJustifyH("LEFT")
	setHint:SetText("Equipment set, this character")

	pane.defaults = PaneButton(pane, "Defaults", 0, function()
		UpgradeArrow.ResetWeights() -- comes back through UpgradeArrow.OnChange
		Draw()
	end, function()
		local entry = Current()
		return ("The weights of %s again."):format(entry and entry.base or "the class's own spec")
	end)
	pane.delete = PaneButton(pane, "Delete", 1, function()
		local entry = Current()
		if entry then
			StaticPopup_Show("FOREVERUPGRADES_SPEC_DELETE", entry.name, nil, { id = entry.id })
		end
	end, function()
		local entry = Current()
		if entry and entry.only then
			return ("%s is the only %s spec, and cannot be deleted."):format(entry.name, entry.roleName:lower())
		end
		return "Deletes this spec, for all your characters of the class."
	end)
	pane.rename = PaneButton(pane, "Rename", 2, function()
		local entry = Current()
		if entry then
			StaticPopup_Show("FOREVERUPGRADES_SPEC_NAME", "A new name for " .. entry.name .. ":", nil, { id = entry.id, name = entry.name })
		end
	end, function() return "A new name for this spec." end)
	pane.new = PaneButton(pane, "New", 3, function()
		local entry = Current()
		StaticPopup_Show("FOREVERUPGRADES_SPEC_NAME", "A name for the new spec, a copy of " .. (entry and entry.name or "this one") .. ":", nil, {})
	end, function() return "A copy of this spec, with its role and weights, to score with from then on." end)

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

-- The spec line -----------------------------------------------------------------

-- The spec UpgradeArrow scores with, and the menu's choice.
local function DrawRole()
	local _, name, _, roleName, fixed = UpgradeArrow.Spec()
	local text = name == roleName and name or (name .. " (" .. roleName .. ")")
	local _, setName = UpgradeArrow.SpecSet()
	window.scoring:SetText(("Scoring as |cffffffff%s|r%s%s"):format(text, fixed and "" or " (automatic)",
		setName and (", against set |cffffffff" .. setName .. "|r") or ""))
	local signature = Signature()
	if window.specMenu and window.specDrawn ~= signature then
		window.specDrawn = signature
		window.specMenu:GenerateMenu()
	end
end

local function SpecPicked(id)
	UpgradeArrow.SetSpec(id or nil) -- comes back through UpgradeArrow.OnChange
	Draw()
end

-- Automatic, then the specs under their role's name.
local function SpecMenu(_, root)
	local _, _, _, _, fixed = UpgradeArrow.Spec()
	local picked = fixed and UpgradeArrow.Spec()
	root:CreateRadio("Automatic", function() return not picked end, SpecPicked, false)
	local heading
	for _, entry in ipairs(UpgradeArrow.Specs()) do
		if entry.roleName ~= heading then
			heading = entry.roleName
			if root.CreateTitle then
				root:CreateTitle(heading)
			end
		end
		root:CreateRadio(entry.name, function() return picked == entry.id end, SpecPicked, entry.id)
	end
end

local function MakeRoles()
	window.scoring = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.scoring:SetPoint("TOPLEFT", 12, -ROLE_TOP - 4)
	window.scoring:SetJustifyH("LEFT")

	local weights = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	weights:SetSize(ROLE_BUTTON, 22)
	weights:SetPoint("TOPRIGHT", -14, -ROLE_TOP)
	weights:SetText("Weights")
	weights:SetScript("OnClick", function()
		ShowPane(not (window.weights and window.weights:IsShown()))
	end)
	window.weightsButton = weights

	-- Left of the Weights button, with a gap.
	local menu = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	menu:SetWidth(SPEC_MENU)
	menu:SetPoint("RIGHT", weights, "LEFT", -10, 0)
	menu:SetupMenu(SpecMenu)
	-- Hooked: the template has its own OnEnter and OnLeave.
	menu:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Score with", 1, 1, 1)
		GameTooltip:AddLine("A spec, until you pick another; or Automatic: your role in the group, else the role ticked in the group finder, "
			.. "else damage, each with the spec last picked for it.", 1, 0.82, 0, true)
		GameTooltip:AddLine("The upgrade arrows and tooltips change with it.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	menu:HookScript("OnLeave", function() GameTooltip:Hide() end)
	window.specMenu = menu
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
	window = CreateFrame("Frame", "ForeverUpgradesFrame", UIParent, "DefaultPanelTemplate")
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
		tinsert(UISpecialFrames, "ForeverUpgradesFrame") -- Escape closes it
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

SLASH_FOREVERUPGRADES1 = "/upgrades"
SlashCmdList.FOREVERUPGRADES = function()
	if not ns.db then
		return
	end
	if not window then
		MakeWindow()
	end
	window:SetShown(not window:IsShown())
end
