-- CraftProfit, the window: every recipe your characters know that makes an
-- item, best profit first. /profit (or /craftprofit) shows or hides it.
--
--   a row          its tooltip: the item, where the price comes from, each
--                  material with its price and where to get it, the sums;
--                  Shift-click links the item in chat
--   the checkbox   also lists recipes a character has seen in its
--                  profession window but not learned
--
-- Columns: profit per craft, what the item brings after the cut, what the
-- materials cost, how many were listed in the last scan, who knows it.

local ADDON, ns = ...

local WIDTH, HEIGHT = 720, 520
local ROW = 20
local LIST_TOP, LIST_BOTTOM = 52, 40
local COLUMNS = { -- left edge, width
	name = { 30, 220 },
	profit = { 256, 80 },
	value = { 342, 80 },
	cost = { 428, 80 },
	listed = { 514, 50 },
	who = { 572, 0 },
}

local window
local rows = {}
local offset = 0

local function Money(copper)
	copper = math.floor(math.abs(copper) + 0.5)
	if copper == 0 then
		return "0"
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then
		return ("%dg %02ds"):format(g, s)
	elseif s > 0 then
		return ("%ds %02dc"):format(s, c)
	end
	return ("%dc"):format(c)
end

local function Signed(copper)
	if copper >= 0 then
		return "|cff40c040" .. Money(copper) .. "|r"
	end
	return "|cffff4040-" .. Money(copper) .. "|r"
end

local function ItemName(id)
	local name = C_Item.GetItemInfo(id)
	return name or ("item " .. id)
end

local function Status()
	if not ns.Ready() then
		return "Needs Auctionator."
	end
	local names = {}
	for who, professions in pairs(ns.characters) do
		local list = {}
		for profession in pairs(professions) do
			list[#list + 1] = profession
		end
		table.sort(list)
		names[#names + 1] = ("%s (%s)"):format(who, table.concat(list, ", "))
	end
	table.sort(names)
	if #names == 0 then
		return "No recipes yet: open a profession window on each character that crafts."
	end
	local priced = 0
	for _, row in ipairs(ns.rows) do
		if row.profit then
			priced = priced + 1
		end
	end
	return ("%d recipes, %d priced. From %s."):format(#ns.rows, priced, table.concat(names, "; "))
end

local function RowTooltip(self)
	local row = self.row
	if not row then
		return
	end
	local m = row.market
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if row.item and row.item.link then
		GameTooltip:SetHyperlink(row.item.link)
	else
		GameTooltip:AddLine(row.name, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("%s, known by %s"):format(row.profession, table.concat(row.who, ", ")), 0.6, 0.6, 0.6, true)
	if m.sell then
		GameTooltip:AddDoubleLine("Sells for", Money(m.sell) .. " each", 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("  last scan", m.now and Money(m.now) or "none", 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		if m.median then
			GameTooltip:AddDoubleLine(("  median of %d day%s"):format(m.days, m.days == 1 and "" or "s"), Money(m.median), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		end
		if m.listed then
			GameTooltip:AddDoubleLine("  listed in last scan", m.listed, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		end
		if m.age and m.age > 0 then
			GameTooltip:AddDoubleLine("  price is", ("%d day%s old"):format(m.age, m.age == 1 and "" or "s"), 0.6, 0.6, 0.6, 1, 0.5, 0.25)
		end
	else
		GameTooltip:AddLine("No auction price for the item.", 1, 0.5, 0.25)
	end
	GameTooltip:AddLine(" ")
	for _, part in ipairs(row.parts) do
		local left = ("%d x %s"):format(part.n, ItemName(part.id))
		local right = part.unit and ("%s  |cff999999%s|r"):format(Money(part.unit * part.n), part.from) or "|cffff8040no price|r"
		GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	if row.value then
		local makes = row.makes == 1 and "" or (" (makes %g)"):format(row.makes)
		GameTooltip:AddDoubleLine("Brings after the 5% cut" .. makes, Money(row.value), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Materials", Money(row.cost), 1, 0.82, 0, 1, 1, 1)
	if row.profit then
		GameTooltip:AddDoubleLine("Profit", Signed(row.profit), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
end

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
	if row and row.item and row.item.link and IsModifiedClick("CHATLINK") then
		Link(row.item.link)
	end
end

local function Text(button, column, justify)
	local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	local at = COLUMNS[column]
	text:SetPoint("LEFT", at[1], 0)
	if at[2] > 0 then
		text:SetWidth(at[2])
	else
		text:SetPoint("RIGHT", 0, 0)
	end
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	button[column] = text
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

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(16, 16)
	button.icon:SetPoint("LEFT", 8, 0)
	Text(button, "name")
	Text(button, "profit", "RIGHT")
	Text(button, "value", "RIGHT")
	Text(button, "cost", "RIGHT")
	Text(button, "listed", "RIGHT")
	Text(button, "who")
	return button
end

local function FillRow(button, row)
	button.row = row
	local item = row.item
	local colour = item and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
	button.icon:SetTexture(row.icon or 134400) -- the question mark
	local name = colour and colour.hex and (colour.hex .. row.name .. "|r") or row.name
	button.name:SetText(row.learned and name or ("|cff808080" .. row.name .. "|r"))
	if row.profit then
		button.profit:SetText(Signed(row.profit))
	else
		button.profit:SetText("|cff808080no price|r")
	end
	button.value:SetText(row.value and Money(row.value) or "")
	button.cost:SetText(Money(row.cost))
	button.listed:SetText(row.market.listed and tostring(row.market.listed) or "")
	button.who:SetText(row.missing and ("|cffff8040no price: %s|r"):format(ItemName(row.missing)) or table.concat(row.who, ", "))
	button:Show()
end

local function VisibleRows()
	return math.max(1, math.floor((window:GetHeight() - LIST_TOP - LIST_BOTTOM) / ROW))
end

local function Draw()
	if not ns.fresh and ns.Ready() then
		ns.Collect()
	end
	local list = ns.rows
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

local function Header(column, label, justify)
	local text = window:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	local at = COLUMNS[column]
	text:SetPoint("TOPLEFT", 10 + at[1], -LIST_TOP + 16)
	if at[2] > 0 then
		text:SetWidth(at[2])
	end
	text:SetJustifyH(justify or "LEFT")
	text:SetText(label)
end

local function MakeWindow()
	window = CreateFrame("Frame", "CraftProfitFrame", UIParent, "DefaultPanelTemplate")
	window:SetSize(WIDTH, HEIGHT)
	window:SetFrameStrata("MEDIUM")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
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
		tinsert(UISpecialFrames, "CraftProfitFrame") -- Escape closes it
	end

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)

	Header("name", "Item")
	Header("profit", "Profit", "RIGHT")
	Header("value", "Brings", "RIGHT")
	Header("cost", "Materials", "RIGHT")
	Header("listed", "Listed", "RIGHT")
	Header("who", "Known by")

	window.thumb = window:CreateTexture(nil, "ARTWORK")
	window.thumb:SetWidth(4)
	window.thumb:SetColorTexture(1, 0.82, 0, 0.6)

	window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.status:SetPoint("BOTTOMLEFT", 12, 14)
	window.status:SetJustifyH("LEFT")
	window.status:SetWordWrap(false)

	local box = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint("BOTTOMRIGHT", -150, 8)
	local caption = box.Text or box.text
	if caption then
		caption:SetText("Also not learned")
		caption:SetFontObject("GameFontHighlightSmall")
	end
	box:SetChecked(ns.db.unlearned and true or false)
	box:SetScript("OnClick", function(self)
		ns.db.unlearned = self:GetChecked() and true or nil
		ns.Invalidate()
	end)
	window.status:SetPoint("RIGHT", box, "LEFT", -8, 0)

	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Draw()
	end)
	window:SetScript("OnShow", function()
		ns.fresh = false
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

SLASH_CRAFTPROFIT1 = "/profit"
SLASH_CRAFTPROFIT2 = "/craftprofit"
SlashCmdList.CRAFTPROFIT = function()
	if not ns.db then
		return
	end
	if not window then
		MakeWindow()
	end
	window:SetShown(not window:IsShown())
end
