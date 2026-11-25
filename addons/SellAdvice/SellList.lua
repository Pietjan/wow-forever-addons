-- SellAdvice, the sell list: everything your characters own, from
-- Syndicator, with what each item is best turned into and what that
-- brings, most first. /sell shows or hides it.
--
-- - What is counted: every character's bags, bank and mail, and the
--   warband bank. Not what is worn or already listed at the auction house.
-- - Items are put together by item, bound and unbound apart; the verdict is
--   the tooltip's own (SellAdvice.lua's Options) for the whole count, so
--   the list and the tooltip cannot disagree. Disenchanting is judged for
--   the character you are on, as in the tooltip.
-- - Left out: grey items (always the vendor's), and, as for the
--   cheapest-to-drop cross, quest items, bags, tools, fishing poles, bound
--   weapons and armour, and items worth nothing.
-- - Trend: for an item best sold at auction, the last scanned price against
--   the median of the daily lowest prices Auctionator kept. "low today"
--   when it is under 80% of the median (waiting may pay), "high today" when
--   it is over 120% (a good moment). In between, nothing is said.
--
--   a row          the item's tooltip, then every option for the whole
--                  count, the price trend and where the items are;
--                  Shift-click links the item in chat

local ADDON, ns = ...

local WIDTH, HEIGHT = 720, 520
local ROW = 20
local LIST_TOP, LIST_BOTTOM = 52, 40
local LOW, HIGH = 0.8, 1.2
local COLUMNS = { -- left edge, width
	name = { 30, 220 },
	count = { 256, 40 },
	advice = { 306, 130 },
	value = { 440, 80 },
	trend = { 528, 70 },
	where = { 606, 0 },
}

local window
local rows = {}
local offset = 0
local list = {} -- the rows, most first
local kept = {} -- key -> the row made last time (false: not listed), for items the game has dropped
local asked = {} -- itemID -> true while waiting for the game; false once it answered or had nothing: never asked again
local totals = {} -- advice key -> copper
local waiting = 0
local dirty = true

-- "Decayla Vesper-PvE" -> "Decayla": the column is narrow, first names do.
local function Short(who)
	local name = who:gsub("%-.*$", "")
	return name:match("^(%S+)") or name
end

-- Auctionator's kept days. Not part of its API: guarded.
local function Trend(itemID)
	local database = Auctionator and Auctionator.Database
	if not database or type(database.GetPriceHistory) ~= "function" then
		return nil
	end
	local ok, days = pcall(database.GetPriceHistory, database, tostring(itemID))
	if not ok or type(days) ~= "table" then
		return nil
	end
	local lows = {}
	for _, day in ipairs(days) do
		if type(day.minSeen) == "number" and day.minSeen > 0 then
			lows[#lows + 1] = day.minSeen
		end
	end
	if #lows == 0 then
		return nil
	end
	table.sort(lows)
	local middle = (#lows + 1) / 2
	local median = (lows[math.floor(middle)] + lows[math.ceil(middle)]) / 2
	local last = ns.AuctionPrice(itemID)
	return { last = last, median = median, days = #lows, listed = days[1] and days[1].available,
		ratio = last and median > 0 and last / median or nil }
end

-- Everything Syndicator knows of: { who, where, item } for each slot.
local function Owned()
	local out = {}
	local function Add(who, where, item)
		if type(item) == "table" and item.itemID and item.itemLink then
			out[#out + 1] = { who = who, where = where, item = item }
		end
	end
	local api = Syndicator and Syndicator.API
	if not api then
		return out
	end
	for _, name in ipairs(api.GetAllCharacters() or {}) do
		local c = api.GetByCharacterFullName(name)
		if c and not (c.details and c.details.hidden) then
			local who = Short(name)
			for _, bag in ipairs(c.bags or {}) do
				for _, item in ipairs(bag) do Add(who, "bags", item) end
			end
			for _, bag in ipairs(c.bank or {}) do
				for _, item in ipairs(bag) do Add(who, "bank", item) end
			end
			for _, tab in ipairs(c.bankTabs or {}) do
				for _, item in ipairs(tab.slots or {}) do Add(who, "bank", item) end
			end
			for _, item in ipairs(c.mail or {}) do Add(who, "mail", item) end
		end
	end
	local warband = api.GetWarband and api.GetWarband(1)
	for _, tab in ipairs(warband and warband.bank or {}) do
		for _, item in ipairs(tab.slots or {}) do Add("Warband", "bank", item) end
	end
	return out
end

local function Better(a, b)
	if a.value ~= b.value then
		return a.value > b.value
	end
	return a.name < b.name
end

local function Build()
	local groups, order = {}, {}
	for _, owned in ipairs(Owned()) do
		local item = owned.item
		local bound = item.isBound and true or false
		local key = item.itemID .. (bound and ":bound" or "")
		local group = groups[key]
		if not group then
			group = { key = key, id = item.itemID, link = item.itemLink, bound = bound, count = 0, places = {}, at = {} }
			groups[key] = group
			order[#order + 1] = group
		end
		local count = item.itemCount or 1
		group.count = group.count + count
		local place = owned.who .. " " .. owned.where
		if not group.at[place] then
			group.places[#group.places + 1] = place
			group.at[place] = 0
		end
		group.at[place] = group.at[place] + count
	end

	list, totals, waiting = {}, {}, 0
	for _, group in ipairs(order) do
		local name, _, quality, _, _, _, _, _, _, icon, _, classID, subclassID, bindType = C_Item.GetItemInfo(group.link)
		local row
		if not name then
			-- Not loaded: ask once, and show what it was last time.
			if asked[group.id] == nil then
				asked[group.id] = true
				if C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(group.id)
				end
			end
			row = kept[group.key]
			if row == false then
				row = nil
			elseif row then
				row.count, row.places, row.at = group.count, group.places, group.at
				row.value = row.best.value * group.count
			else
				waiting = waiting + 1
			end
		elseif quality == 0 or ns.NeverJunk(group.id, classID, subclassID, bindType, group.bound) then
			asked[group.id] = false
			kept[group.key] = false
		else
			asked[group.id] = false
			local options, missing = ns.Options(group.link, nil, { count = group.count, bound = group.bound })
			if options and options[1] and options[1].value > 0 then
				local best = options[1]
				local advice = ns.LABEL[best.key]
				if not ns.CanDo(best) then
					advice = advice .. (best.key == "smelt" and " (miner)" or " (enchanter)")
				end
				row = {
					key = group.key, id = group.id, link = group.link, name = name, icon = icon, quality = quality,
					count = group.count, places = group.places, at = group.at, bound = group.bound,
					options = options, missing = missing, best = best, advice = advice,
					value = best.value * group.count,
					trend = ns.LISTING[best.key] and Trend(best.item or group.id) or nil,
				}
			end
			kept[group.key] = row or false
		end
		if row then
			list[#list + 1] = row
			totals[row.best.key] = (totals[row.best.key] or 0) + row.value
		end
	end
	table.sort(list, Better)
	dirty = false
end

-- The window -----------------------------------------------------------------------

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

local function TrendText(trend)
	if not trend or not trend.ratio then
		return ""
	elseif trend.ratio < LOW then
		return "|cffff8040low today|r"
	elseif trend.ratio > HIGH then
		return "|cff40c040high today|r"
	end
	return ""
end

local function Status()
	if not (Syndicator and Syndicator.API) then
		return "Needs Syndicator."
	end
	local sum, parts = 0, {}
	for _, key in ipairs({ "auction", "greater", "lesser", "smelt", "disenchant", "vendor" }) do
		if totals[key] then
			sum = sum + totals[key]
			parts[#parts + 1] = ("%s %s"):format(ns.LABEL[key]:lower(), Money(totals[key]))
		end
	end
	local text = ("%d items, %s: %s."):format(#list, Money(sum), table.concat(parts, ", "))
	if waiting > 0 then
		text = text .. (" %d not loaded yet."):format(waiting)
	end
	return text
end

local function Where(row)
	local parts = {}
	for _, place in ipairs(row.places) do
		parts[#parts + 1] = #row.places == 1 and place or (place .. " " .. row.at[place])
	end
	return table.concat(parts, ", ")
end

local GREY = 0.6

local function RowTooltip(self)
	local row = self.row
	if not row then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(row.link)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("All %d%s"):format(row.count, row.bound and ", bound" or ""), 1, 0.82, 0)
	for i, option in ipairs(row.options) do
		local colour = i == 1 and "|cff40c040" or "|cffffffff"
		GameTooltip:AddDoubleLine(colour .. ns.OptionLabel(option) .. "|r", Money(option.value * row.count), 1, 1, 1, 1, 1, 1)
	end
	for _, key in ipairs(ns.KEYS) do
		if row.missing[key] then
			GameTooltip:AddDoubleLine(ns.LABEL[key], row.missing[key], GREY, GREY, GREY, GREY, GREY, GREY)
		end
	end
	local trend = row.trend
	if trend then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Last scan", trend.last and Money(trend.last) or "none", GREY, GREY, GREY, 1, 1, 1)
		GameTooltip:AddDoubleLine(("Median of %d day%s"):format(trend.days, trend.days == 1 and "" or "s"), Money(trend.median), GREY, GREY, GREY, 1, 1, 1)
		if trend.listed then
			GameTooltip:AddDoubleLine("Listed in last scan", trend.listed, GREY, GREY, GREY, 1, 1, 1)
		end
	end
	GameTooltip:AddLine(" ")
	for _, place in ipairs(row.places) do
		GameTooltip:AddDoubleLine(place, row.at[place], 1, 1, 1, 1, 1, 1)
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
	if self.row and IsModifiedClick("CHATLINK") then
		Link(self.row.link)
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
	Text(button, "count", "RIGHT")
	Text(button, "advice")
	Text(button, "value", "RIGHT")
	Text(button, "trend")
	Text(button, "where")
	return button
end

local function FillRow(button, row)
	button.row = row
	local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
	button.icon:SetTexture(row.icon or 134400)
	button.name:SetText(colour and colour.hex and (colour.hex .. row.name .. "|r") or row.name)
	button.count:SetText(row.count)
	button.advice:SetText(row.advice)
	button.value:SetText(Money(row.value))
	button.trend:SetText(TrendText(row.trend))
	button.where:SetText(Where(row))
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
	window = CreateFrame("Frame", "SellAdviceListFrame", UIParent, "DefaultPanelTemplate")
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
		SellAdviceDB.point = { point, relative, x, y }
	end)
	local at = SellAdviceDB.point
	if type(at) == "table" and at[1] then
		window:SetPoint(at[1], UIParent, at[2], at[3], at[4])
	else
		window:SetPoint("CENTER")
	end
	window:Hide()
	window.TitleContainer.TitleText:SetText("Sell list")
	if type(UISpecialFrames) == "table" then
		tinsert(UISpecialFrames, "SellAdviceListFrame") -- Escape closes it
	end

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)

	Header("name", "Item")
	Header("count", "Count", "RIGHT")
	Header("advice", "Best")
	Header("value", "Brings", "RIGHT")
	Header("trend", "Price")
	Header("where", "Where")

	window.thumb = window:CreateTexture(nil, "ARTWORK")
	window.thumb:SetWidth(4)
	window.thumb:SetColorTexture(1, 0.82, 0, 0.6)

	window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.status:SetPoint("BOTTOMLEFT", 12, 14)
	window.status:SetPoint("RIGHT", -14, 0)
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

local function Shown()
	return window ~= nil and window:IsShown()
end

-- Something changed: made again now when shown, else when next opened.
local pending = false
local function Changed()
	dirty = true
	if Shown() and not pending then
		pending = true
		C_Timer.After(0.3, function()
			pending = false
			if Shown() then
				Draw()
			end
		end)
	end
end
ns.ListChanged = Changed

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, arg, arg2)
	if event == "ADDON_LOADED" and arg == ADDON then
		SellAdviceDB = type(SellAdviceDB) == "table" and SellAdviceDB or {}
	elseif event == "PLAYER_LOGIN" then
		local registry = Syndicator and Syndicator.CallbackRegistry
		if registry and registry.RegisterCallback then
			pcall(registry.RegisterCallback, registry, "BagCacheUpdate", Changed, events)
			pcall(registry.RegisterCallback, registry, "MailCacheUpdate", Changed, events)
		end
		local api = Auctionator and Auctionator.API and Auctionator.API.v1
		if api and api.RegisterForDBUpdate then
			pcall(api.RegisterForDBUpdate, ADDON, Changed)
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- Only an item the list waits for, and only when it did load.
		if asked[arg] then
			asked[arg] = false
			if arg2 then
				Changed()
			end
		end
	end
end)

SLASH_SELLADVICELIST1 = "/sell"
SLASH_SELLADVICELIST2 = "/selllist"
SlashCmdList.SELLADVICELIST = function()
	if not SellAdviceDB then
		return
	end
	if not window then
		MakeWindow()
	end
	window:SetShown(not window:IsShown())
end
