-- CraftProfit, the farm list: raw goods worth gathering or looting to sell,
-- most per item first. /farm shows or hides it.
--
-- The goods: Data.lua's farmable list (trade goods no recipe makes: cloth,
-- leather and hides, ore and stone, meat and fish, herbs, elementals), each
-- with at least MIN_DAYS days of Auctionator's price history. What sells is
-- not known (Auctionator keeps asking prices, not sales), so demand is read
-- from the history:
--   Each     what one brings: the lower of the last scan and the median of
--            the daily lowest prices, less the auction house's 5% cut, or the
--            vendor price when that is more
--   Listed   how many were up in the last scan
--   Price    this week against last week, by calendar day: the median of the
--            daily lowest prices of the last 7 days (today included) against
--            the 7 days before. Only when each week has WEEK_DAYS days with a
--            price, so scans you skipped do not stretch the span, and whole
--            weeks cancel out weekday swings.
--   Supply   the same weeks: the mean of how many were listed each day
--   Note     "vendor it" when the vendor pays more; "rising" when the price
--            is up RISING or more and supply up no more than FLOOD;
--            "falling" when the price is down by FALLING or more
--
--   My level / All   goods up to 10 item levels above your level, or all
--   a row            its tooltip with the numbers; Shift-click links it

local ADDON, ns = ...

local CUT = 0.95
local MIN_DAYS = 6 -- days with a price before a good is listed at all
local WEEK_DAYS = 3 -- days with a price each week needs for a trend
local RISING, FALLING, FLOOD = 0.2, -0.2, 0.5
local ABOVE = 10 -- "My level": item levels above yours still listed

local WIDTH, HEIGHT = 720, 520
local ROW = 20
local LIST_TOP, LIST_BOTTOM = 52, 40
local COLUMNS = { -- left edge, width
	name = { 30, 190 },
	kind = { 226, 64 },
	level = { 292, 36 },
	each = { 334, 70 },
	listed = { 410, 56 },
	price = { 472, 56 },
	supply = { 534, 60 },
	note = { 604, 0 },
}

local window
local rows = {}
local offset = 0
local list = {}
local dirty = true

local function Mean(values)
	local sum = 0
	for _, v in ipairs(values) do
		sum = sum + v
	end
	return #values > 0 and sum / #values or nil
end

local function Slice(values, from, to)
	local out = {}
	for i = from, to do
		out[#out + 1] = values[i]
	end
	return out
end

-- Today as Auctionator counts days, or nil when it cannot be worked out.
local function Today()
	local day0 = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
	if type(day0) ~= "number" then
		return nil
	end
	return math.floor((time() - day0) / 86400)
end

-- One farmable good from its price history, or nil with too little of it.
function ns.FarmRow(id, info)
	local days = ns.History and ns.History(id)
	if not days then
		return nil
	end
	local lows, listed = {}, {} -- newest first
	local today = Today()
	local week = { { lows = {}, listed = {} }, { lows = {}, listed = {} } } -- this week, last week
	for _, day in ipairs(days) do
		if type(day.minSeen) == "number" and day.minSeen > 0 then
			lows[#lows + 1] = day.minSeen
			listed[#listed + 1] = day.available or 0
			local age = today and tonumber(day.rawDay) and today - tonumber(day.rawDay)
			local bucket = age and age >= 0 and week[math.floor(age / 7) + 1]
			if bucket then
				bucket.lows[#bucket.lows + 1] = day.minSeen
				bucket.listed[#bucket.listed + 1] = day.available or 0
			end
		end
	end
	if #lows < MIN_DAYS then
		return nil
	end
	local kind, level, sell, quality, name = info[1], info[2], info[3], info[4], info[5]
	local median = ns.Median(Slice(lows, 1, #lows))
	local price = math.min(lows[1], median)
	local priceTrend, supplyTrend
	if #week[1].lows >= WEEK_DAYS and #week[2].lows >= WEEK_DAYS then
		local now, before = ns.Median(week[1].lows), ns.Median(week[2].lows)
		priceTrend = before > 0 and now / before - 1 or nil
		local supplyNow, supplyBefore = Mean(week[1].listed), Mean(week[2].listed)
		supplyTrend = supplyBefore > 0 and supplyNow / supplyBefore - 1 or nil
	end
	local row = {
		id = id, name = name, kind = kind, level = level, quality = quality, vendor = sell,
		last = lows[1], median = median, listed = listed[1], days = #lows,
		auction = price * CUT,
		priceTrend = priceTrend,
		supplyTrend = supplyTrend,
	}
	row.each = math.max(row.auction, sell or 0)
	if sell and sell > row.auction then
		row.note = "vendor"
	elseif row.priceTrend and row.priceTrend >= RISING and (row.supplyTrend or 0) <= FLOOD then
		row.note = "rising"
	elseif row.priceTrend and row.priceTrend <= FALLING then
		row.note = "falling"
	end
	return row
end

local function Build()
	list = {}
	local cap = (UnitLevel("player") or 60) + ABOVE
	for id, info in pairs(ns.farmable or {}) do
		if ns.db.farmAll or info[2] <= cap then
			local row = ns.FarmRow(id, info)
			if row then
				list[#list + 1] = row
			end
		end
	end
	table.sort(list, function(a, b)
		if a.each ~= b.each then
			return a.each > b.each
		end
		return a.name < b.name
	end)
	dirty = false
end

-- The window ----------------------------------------------------------------------

local function Money(copper)
	copper = math.floor(copper + 0.5)
	if copper <= 0 then
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

local function Percent(value)
	if not value then
		return ""
	end
	local text = ("%+d%%"):format(math.floor(value * 100 + 0.5))
	if value >= RISING then
		return "|cff40c040" .. text .. "|r"
	elseif value <= FALLING then
		return "|cffff8040" .. text .. "|r"
	end
	return text
end

local NOTE = {
	vendor = "|cff999999vendor it|r",
	rising = "|cff40c040rising|r",
	falling = "|cffff8040falling|r",
}

local function Status()
	local where = ns.db.farmAll and "all levels" or ("up to item level %d"):format((UnitLevel("player") or 60) + ABOVE)
	return ("%d goods with %d+ days of prices, %s. Prices are asking prices, not sales."):format(#list, MIN_DAYS, where)
end

local function Link(id)
	local _, link = C_Item.GetItemInfo(id)
	if not link then
		return
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		if not ChatFrameUtil.InsertLink(link) and ChatFrameUtil.OpenChat then
			ChatFrameUtil.OpenChat(link)
		end
	elseif ChatEdit_InsertLink and not ChatEdit_InsertLink(link) and ChatFrame_OpenChat then
		ChatFrame_OpenChat(link)
	end
end

local GREY = 0.6

local function RowTooltip(self)
	local row = self.row
	if not row then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. row.id)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Last scan", Money(row.last), GREY, GREY, GREY, 1, 1, 1)
	GameTooltip:AddDoubleLine(("Median of %d days"):format(row.days), Money(row.median), GREY, GREY, GREY, 1, 1, 1)
	GameTooltip:AddDoubleLine("After the 5% cut", Money(row.auction), GREY, GREY, GREY, 1, 1, 1)
	GameTooltip:AddDoubleLine("Vendor", Money(row.vendor or 0), GREY, GREY, GREY, 1, 1, 1)
	GameTooltip:AddDoubleLine("Listed in last scan", row.listed, GREY, GREY, GREY, 1, 1, 1)
	if row.priceTrend then
		GameTooltip:AddDoubleLine("Price, this week against last", Percent(row.priceTrend), GREY, GREY, GREY, 1, 1, 1)
		GameTooltip:AddDoubleLine("Supply, this week against last", Percent(row.supplyTrend), GREY, GREY, GREY, 1, 1, 1)
	else
		GameTooltip:AddLine(("No trend: each week needs %d days of prices."):format(WEEK_DAYS), GREY, GREY, GREY)
	end
	GameTooltip:Show()
end

local function RowClick(self)
	if self.row and IsModifiedClick("CHATLINK") then
		Link(self.row.id)
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
	Text(button, "kind")
	Text(button, "level", "RIGHT")
	Text(button, "each", "RIGHT")
	Text(button, "listed", "RIGHT")
	Text(button, "price", "RIGHT")
	Text(button, "supply", "RIGHT")
	Text(button, "note")
	return button
end

local function FillRow(button, row)
	button.row = row
	local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
	button.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.id) or 134400)
	button.name:SetText(colour and colour.hex and (colour.hex .. row.name .. "|r") or row.name)
	button.kind:SetText(row.kind)
	button.level:SetText(row.level)
	button.each:SetText(Money(row.each))
	button.listed:SetText(row.listed)
	button.price:SetText(Percent(row.priceTrend))
	button.supply:SetText(Percent(row.supplyTrend))
	button.note:SetText(NOTE[row.note] or "")
	button:Show()
end

local function VisibleRows()
	return math.max(1, math.floor((window:GetHeight() - LIST_TOP - LIST_BOTTOM) / ROW))
end

local function Draw()
	if dirty then
		Build()
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
	local track = visible * ROW
	if #list > visible then
		window.thumb:SetHeight(math.max(12, track * visible / #list))
		window.thumb:SetPoint("TOPRIGHT", -6, -LIST_TOP - (track - window.thumb:GetHeight()) * offset / (#list - visible))
		window.thumb:Show()
	else
		window.thumb:Hide()
	end
	window.status:SetText(Status())
	window.mine:SetEnabled(ns.db.farmAll and true or false)
	window.all:SetEnabled(not ns.db.farmAll)
	if ns.db.farmAll then
		window.all:LockHighlight()
		window.mine:UnlockHighlight()
	else
		window.mine:LockHighlight()
		window.all:UnlockHighlight()
	end
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

local function Choice(label, all)
	local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	button:SetSize(76, 22)
	button:SetText(label)
	button:SetScript("OnClick", function()
		ns.db.farmAll = all or nil
		dirty = true
		Draw()
	end)
	return button
end

local function MakeWindow()
	window = CreateFrame("Frame", "CraftProfitFarmFrame", UIParent, "DefaultPanelTemplate")
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
		ns.db.farmPoint = { point, relative, x, y }
	end)
	local at = ns.db.farmPoint
	if type(at) == "table" and at[1] then
		window:SetPoint(at[1], UIParent, at[2], at[3], at[4])
	else
		window:SetPoint("CENTER")
	end
	window:Hide()
	window.TitleContainer.TitleText:SetText("Farm list")
	if ForeverSnap then ForeverSnap.Register(window) end -- snaps to the screen and our other frames
	if type(UISpecialFrames) == "table" then
		tinsert(UISpecialFrames, "CraftProfitFarmFrame") -- Escape closes it
	end
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)

	Header("name", "Item")
	Header("kind", "Type")
	Header("level", "Lvl", "RIGHT")
	Header("each", "Each", "RIGHT")
	Header("listed", "Listed", "RIGHT")
	Header("price", "Price", "RIGHT")
	Header("supply", "Supply", "RIGHT")
	Header("note", "")

	window.thumb = window:CreateTexture(nil, "ARTWORK")
	window.thumb:SetWidth(4)
	window.thumb:SetColorTexture(1, 0.82, 0, 0.6)

	window.all = Choice("All", true)
	window.all:SetPoint("BOTTOMRIGHT", -12, 8)
	window.mine = Choice("My level", false)
	window.mine:SetPoint("RIGHT", window.all, "LEFT", -2, 0)

	window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.status:SetPoint("BOTTOMLEFT", 12, 14)
	window.status:SetPoint("RIGHT", window.mine, "LEFT", -8, 0)
	window.status:SetJustifyH("LEFT")
	window.status:SetWordWrap(false)

	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Draw()
	end)
	window:SetScript("OnShow", function()
		dirty = true
		Draw()
	end)
end

-- New prices or a new level: made again when next drawn.
local listChanged = ns.Changed
function ns.Changed()
	if listChanged then
		listChanged()
	end
	dirty = true
	if window and window:IsShown() then
		Draw()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function()
	dirty = true
end)

SLASH_CRAFTPROFITFARM1 = "/farm"
SLASH_CRAFTPROFITFARM2 = "/farmlist"
SlashCmdList.CRAFTPROFITFARM = function()
	if not ns.db then
		return
	end
	if not window then
		MakeWindow()
	end
	window:SetShown(not window:IsShown())
end
