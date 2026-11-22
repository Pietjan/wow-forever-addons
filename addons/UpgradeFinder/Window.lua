-- UpgradeFinder, the window: the upgrades slot by slot, the best five of
-- each, best first. /upgrades (or /upgradefinder) shows or hides it.
--
--   a slot's name   lists all of that slot's upgrades, or the best five again
--   an item         its tooltip, with every known way to get it
--   the checkbox    also lists items with no known source
--
-- The number is how many points the item scores above what you wear, in
-- UpgradeArrow's points; "empty slot" where you wear nothing. The rows
-- are made once and filled in again on every change.

local ADDON, ns = ...

local WIDTH, HEIGHT = 640, 520
local ROW = 20
local LIST_TOP, LIST_BOTTOM = 30, 40
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
		return ("Asking the game about %d items: %d done"):format(progress.of, progress.at)
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

local function RowClick(self)
	local row = self.row
	if row and row.group then
		all[row.group] = not all[row.group] or nil
		Draw()
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

function Draw()
	BuildList()
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
