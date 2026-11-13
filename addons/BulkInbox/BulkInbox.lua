-- BulkInbox, the window: a frame of the addon's own to the right of the
-- mail frame, as tall as it is, with one row per item and per sum of
-- money in the inbox. It opens with the inbox tab when there is something
-- to take and goes with it. /bulkinbox shows or hides it at a mailbox.
--
--   click        mark or unmark the row
--   Alt-click    mark or unmark every row of the same item (or all money)
--   Shift-click  take that row now
--   headers      sort by that column; again to reverse
--   search       rows whose name holds the text; Take All and Take Money
--                then take only what is listed
--
-- Blizzard's mail frames are only read and anchored to. Nothing is written
-- on them and none of their functions is replaced; the hooks are
-- post-hooks on their show and hide. The rows are made once and filled in
-- again on every change, so the list does not jump or blink while taking.

local ADDON, ns = ...

local WIDTH = 480
local ROW = 20
local LIST_TOP, LIST_BOTTOM = 76, 64
local COLUMNS = {
	{ key = "name", label = "Item", x = 48, width = 160, justify = "LEFT" },
	{ key = "qty", label = "Qty", x = 212, width = 84, justify = "RIGHT" },
	{ key = "sender", label = "Sender", x = 304, width = 96, justify = "LEFT" },
	{ key = "days", label = "Days", x = 402, width = 36, justify = "RIGHT" },
	{ key = "mail", label = "#", x = 440, width = 24, justify = "RIGHT" },
}

local window
local rows = {} -- the row buttons, made as the height asks for them
local list = {} -- what is listed: the inbox rows after search and sort
local offset = 0
local sortKey, sortReversed = "mail", false
local closed, opened, wasAtMailbox = false, false, false

local function SortValue(row, key)
	if key == "name" then
		return row.label:lower()
	elseif key == "qty" then
		-- items by count, then money by amount
		return row.kind == "money" and (1e9 + row.money) or row.count
	elseif key == "sender" then
		return row.sender:lower()
	elseif key == "days" then
		return row.daysLeft
	end
	return row.mail
end

local function BuildList()
	list = {}
	for _, row in ipairs(ns.snap.rows) do
		if ns.Matches(row) then
			list[#list + 1] = row
		end
	end
	table.sort(list, function(a, b)
		local va, vb = SortValue(a, sortKey), SortValue(b, sortKey)
		if va ~= vb then
			if sortReversed then
				return va > vb
			end
			return va < vb
		end
		if a.mail ~= b.mail then
			return a.mail < b.mail
		end
		return a.slot < b.slot
	end)
end

local function Days(daysLeft)
	if daysLeft >= 1 then
		return ("%dd"):format(math.floor(daysLeft))
	end
	return ("|cffff2020%dh|r"):format(math.floor(daysLeft * 24))
end

local function RowTooltip(self)
	local row = self.row
	if not row then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if row.kind == "item" then
		GameTooltip:SetInboxItem(row.mail, row.slot)
	else
		GameTooltip:SetText(row.label, 1, 1, 1)
		GameTooltip:AddLine(GetMoneyString(row.money), 1, 1, 1)
	end
	if row.blocked == "cod" then
		GameTooltip:AddLine("C.O.D. " .. GetMoneyString(row.cod) .. ": open the mail to pay for it.", 1, 0.3, 0.3, true)
	elseif row.blocked == "gm" then
		GameTooltip:AddLine("From a game master: open the mail to take it.", 1, 0.3, 0.3, true)
	end
	GameTooltip:Show()
end

local function RowClick(self)
	local row = self.row
	if not row or ns.Running() then
		return
	end
	if IsShiftKeyDown() then
		if not row.blocked then
			ns.Start("one", row.key)
		end
		return
	elseif IsAltKeyDown() then
		ns.ToggleMarkAlike(row)
	else
		ns.ToggleMark(row)
	end
	ns.Changed()
end

local function MakeRow(index)
	local button = CreateFrame("Button", nil, window)
	button:SetHeight(ROW)
	button:SetPoint("TOPLEFT", 8, -LIST_TOP - (index - 1) * ROW)
	button:SetPoint("RIGHT", -12, 0)
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", RowClick)
	button:SetScript("OnEnter", RowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)
	button.marked = button:CreateTexture(nil, "BACKGROUND")
	button.marked:SetAllPoints()
	button.marked:SetColorTexture(1, 0.82, 0, 0.18)

	button.box = button:CreateTexture(nil, "ARTWORK")
	button.box:SetSize(18, 18)
	button.box:SetPoint("LEFT", 0, 0)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(16, 16)
	button.icon:SetPoint("LEFT", 20, 0)

	button.cells = {}
	for _, column in ipairs(COLUMNS) do
		local cell = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		cell:SetPoint("LEFT", column.x - 8, 0)
		cell:SetWidth(column.width)
		cell:SetJustifyH(column.justify)
		cell:SetWordWrap(false)
		button.cells[column.key] = cell
	end
	return button
end

local function FillRow(button, row)
	button.row = row
	local marked = ns.marks[row.key] ~= nil
	button.marked:SetShown(marked)
	button.box:SetTexture(marked and "Interface\\Buttons\\UI-CheckBox-Check" or "Interface\\Buttons\\UI-CheckBox-Up")
	button.box:SetShown(not row.blocked)
	button.icon:SetTexture(row.kind == "money" and "Interface\\Icons\\INV_Misc_Coin_01" or row.texture)

	local name = row.label ~= "" and row.label or "..."
	if row.blocked then
		name = "|cff808080" .. name .. "|r"
	elseif row.kind == "item" then
		local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
		if colour and colour.hex then
			name = colour.hex .. name .. "|r"
		end
	end
	local cells = button.cells
	cells.name:SetText(name)
	if row.blocked == "cod" then
		cells.qty:SetText("|cffff2020C.O.D.|r")
	elseif row.kind == "money" then
		cells.qty:SetText(GetMoneyString(row.money))
	else
		cells.qty:SetText(row.count)
	end
	cells.sender:SetText(row.sender ~= "" and row.sender or UNKNOWN)
	cells.days:SetText(Days(row.daysLeft))
	cells.mail:SetText(row.mail)
	button:Show()
end

local function VisibleRows()
	return math.max(1, math.floor((window:GetHeight() - LIST_TOP - LIST_BOTTOM) / ROW))
end

local function Draw()
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
		window.thumb:SetPoint("TOPRIGHT", -5, -LIST_TOP - (track - window.thumb:GetHeight()) * offset / (#list - visible))
		window.thumb:Show()
	else
		window.thumb:Hide()
	end

	local snap = ns.snap
	local title = ("%s: %d mails, %s"):format(ADDON, snap.numMails, GetMoneyString(snap.money))
	if snap.waiting > 0 then
		title = title .. (", %d more not loaded yet"):format(snap.waiting)
	end
	window.TitleContainer.TitleText:SetText(title)

	for _, column in ipairs(COLUMNS) do
		local header = window.headers[column.key]
		header.text:SetTextColor(1, column.key == sortKey and 1 or 0.82, column.key == sortKey and 1 or 0)
	end

	local running = ns.Running()
	local marks = 0
	for _ in pairs(ns.marks) do
		marks = marks + 1
	end
	if running then
		window.status:SetText("Taking...")
	elseif ns.status ~= "" then
		window.status:SetText(ns.status)
	elseif #list == 0 then
		window.status:SetText(ns.filter ~= "" and "Nothing matches the search." or "Nothing to take.")
	else
		window.status:SetText("Click marks, Alt-click marks all alike, Shift-click takes.")
	end
	window.takeAll:SetEnabled(not running and #list > 0)
	window.takeMoney:SetEnabled(not running and snap.money > 0)
	window.takeSelected:SetText(marks > 0 and ("Take Selected (%d)"):format(marks) or "Take Selected")
	window.takeSelected:SetEnabled(not running and marks > 0)
	window.clear:SetShown(not running)
	window.clear:SetEnabled(marks > 0)
	window.cancel:SetShown(running)
end

-- Beside the open letter when one is shown, else beside the mail frame.
local function Anchor()
	local beside = OpenMailFrame and OpenMailFrame:IsShown() and OpenMailFrame or MailFrame
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", beside, "TOPRIGHT", 4, 0)
	window:SetPoint("BOTTOMLEFT", beside, "BOTTOMRIGHT", 4, 0)
end

local function MakeButton(text, width, onClick)
	local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function MakeWindow()
	window = CreateFrame("Frame", "BulkInboxFrame", UIParent, "DefaultPanelTemplate")
	window:SetWidth(WIDTH)
	window:SetFrameStrata("MEDIUM")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:Hide()

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	close:SetScript("OnClick", function()
		closed = true
		ns.Changed()
	end)

	local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	search:SetSize(150, 20)
	search:SetPoint("TOPRIGHT", -12, -28)
	search:HookScript("OnTextChanged", function(self)
		ns.SetFilter(self:GetText())
	end)

	window.headers = {}
	for _, column in ipairs(COLUMNS) do
		local header = CreateFrame("Button", nil, window)
		header:SetSize(column.width, 18)
		header:SetPoint("TOPLEFT", column.x, -54)
		header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		header.text:SetAllPoints()
		header.text:SetJustifyH(column.justify)
		header.text:SetText(column.label)
		header:SetScript("OnClick", function()
			if sortKey == column.key then
				sortReversed = not sortReversed
			else
				sortKey, sortReversed = column.key, false
			end
			ns.Changed()
		end)
		window.headers[column.key] = header
	end

	window.thumb = window:CreateTexture(nil, "ARTWORK")
	window.thumb:SetWidth(4)
	window.thumb:SetColorTexture(1, 0.82, 0, 0.6)

	window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.status:SetPoint("BOTTOMLEFT", 12, 38)
	window.status:SetPoint("RIGHT", -12, 0)
	window.status:SetJustifyH("LEFT")
	window.status:SetWordWrap(false)

	window.takeAll = MakeButton("Take All", 90, function() ns.Start("all") end)
	window.takeAll:SetPoint("BOTTOMLEFT", 10, 10)
	window.takeMoney = MakeButton("Take Money", 100, function() ns.Start("money") end)
	window.takeMoney:SetPoint("LEFT", window.takeAll, "RIGHT", 4, 0)
	window.takeSelected = MakeButton("Take Selected", 140, function() ns.Start("marked") end)
	window.takeSelected:SetPoint("LEFT", window.takeMoney, "RIGHT", 4, 0)
	window.clear = MakeButton("Clear", 70, function()
		ns.ClearMarks()
		ns.Changed()
	end)
	window.clear:SetPoint("BOTTOMRIGHT", -10, 10)
	window.cancel = MakeButton("Cancel", 70, function() ns.Stop("Cancelled.") end)
	window.cancel:SetPoint("BOTTOMRIGHT", -10, 10)

	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Draw()
	end)
	window:SetScript("OnSizeChanged", Draw)
	window:SetScript("OnHide", function()
		ns.Stop("Stopped: the list was closed.")
	end)

	-- Follow the inbox tab and the open letter. Post-hooks: Blizzard's own
	-- handlers run first and untouched.
	InboxFrame:HookScript("OnShow", ns.Changed)
	InboxFrame:HookScript("OnHide", ns.Changed)
	if OpenMailFrame then
		OpenMailFrame:HookScript("OnShow", ns.Changed)
		OpenMailFrame:HookScript("OnHide", ns.Changed)
	end
end

function ns.Changed()
	if ns.atMailbox and not wasAtMailbox then
		closed, opened, offset = false, false, 0
	end
	wasAtMailbox = ns.atMailbox
	if not window then
		if not (ns.atMailbox and MailFrame and InboxFrame) then
			return
		end
		MakeWindow()
	end
	local show = ns.atMailbox and not closed and InboxFrame:IsVisible()
		and (opened or #ns.snap.rows > 0)
	if not show then
		window:Hide()
		return
	end
	opened = true
	Anchor()
	window:Show()
	Draw()
end

SLASH_BULKINBOX1 = "/bulkinbox"
SlashCmdList.BULKINBOX = function()
	if not ns.atMailbox then
		print(ADDON .. ": only at a mailbox.")
		return
	end
	closed = not closed
	opened = true
	ns.Changed()
end
