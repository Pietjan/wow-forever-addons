-- CraftProfit, the plan: the crafts you mean to make, and the materials to
-- buy for them. Click a row in the list to plan one more of it, right-click
-- for one fewer; the Materials button opens this pane beside the list.
--
-- One line per material, most to spend first:
--   need    for every planned craft together
--   have    what all your characters own (Syndicator: bags, bank, mail,
--           and the warband bank); none counted without Syndicator
--   buy     need less have
--   each    the cheapest way to get one, as in the list: auction or vendor
--   note    for auction materials, the last scan against the median of the
--           daily lowest prices: "cheap today" under 80%, "dear today" over
--           120%; "vendor" when a vendor sells it for less
--
-- Shopping list puts every material still to buy at auction into
-- Auctionator's shopping list "CraftProfit" (an older one of that name is
-- replaced), as exact searches with the amount to buy; at the auction house
-- Auctionator searches it at once. Vendor materials are left out of it.
-- Clear empties the plan.
--
-- A material that one recipe makes and another uses (a bolt of cloth) is
-- counted as bought, not crafted.

local ADDON, ns = ...

local LOW, HIGH = 0.8, 1.2
local LIST_NAME = "CraftProfit"
local PANE, LINE = 470, 18
local TOP, BOTTOM = 52, 64
local COLUMNS = { -- left edge, width
	name = { 24, 150 },
	need = { 176, 36 },
	have = { 214, 36 },
	buy = { 252, 36 },
	each = { 292, 64 },
	note = { 364, 0 },
}

local pane
local lines = {}
local offset = 0
local materials, summary = {}, {}

function ns.Planned(id)
	return ns.db and ns.db.plan and ns.db.plan[id] or 0
end

local function FindRecipe(id)
	for _, book in pairs(ns.db.characters) do
		for _, entry in pairs(book.professions or {}) do
			local recipe = entry.recipes and entry.recipes[id]
			if recipe then
				return recipe
			end
		end
	end
end

-- How many of an item all your characters own, or nil without Syndicator.
function ns.Owned(itemID)
	local api = Syndicator and Syndicator.API
	if not api or not api.GetInventoryInfoByItemID then
		return nil
	end
	local ok, info = pcall(api.GetInventoryInfoByItemID, itemID, true, true)
	if not ok or type(info) ~= "table" then
		return nil
	end
	local count = 0
	for _, character in ipairs(info.characters or {}) do
		count = count + (character.bags or 0) + (character.bank or 0) + (character.mail or 0)
	end
	for _, inWarband in ipairs(info.warband or {}) do
		count = count + inWarband
	end
	return count
end

function ns.Materials()
	local byItem, list = {}, {}
	local total = { crafts = 0, profit = 0, unpriced = 0, spend = 0, vendor = 0 }
	for id, count in pairs(ns.db.plan or {}) do
		local recipe = FindRecipe(id)
		if recipe then
			total.crafts = total.crafts + count
			local row = ns.Evaluate(recipe)
			if row.profit then
				total.profit = total.profit + row.profit * count
			else
				total.unpriced = total.unpriced + count
			end
			for i, slot in ipairs(recipe.reagents) do
				local part = row.parts[i]
				local material = byItem[part.id]
				if not material then
					material = { id = part.id, need = 0, unit = part.unit, from = part.from }
					byItem[part.id] = material
					list[#list + 1] = material
				end
				material.need = material.need + slot.n * count
			end
		end
	end
	for _, material in ipairs(list) do
		material.have = ns.Owned(material.id) or 0
		material.buy = math.max(0, material.need - material.have)
		material.market = ns.Market(material.id)
		local m = material.market
		material.ratio = material.from == "auction" and m.now and m.median and m.median > 0 and m.now / m.median or nil
		if material.unit then
			material.spend = material.buy * material.unit
			if material.from == "vendor" then
				total.vendor = total.vendor + material.spend
			end
			total.spend = total.spend + material.spend
		end
	end
	table.sort(list, function(a, b)
		local x, y = a.spend or -1, b.spend or -1
		if x ~= y then
			return x > y
		end
		return a.id < b.id
	end)
	return list, total
end

-- Auctionator's shopping list ----------------------------------------------------

function ns.ShoppingList()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not api or not api.CreateShoppingList or not api.ConvertToSearchString then
		return nil, "Auctionator has no shopping list API."
	end
	local terms, unnamed = {}, 0
	for _, material in ipairs(materials) do
		if material.buy > 0 and material.from ~= "vendor" then
			local name = C_Item.GetItemInfo(material.id)
			if name then
				local ok, term = pcall(api.ConvertToSearchString, ADDON, { searchString = name, isExact = true, quantity = material.buy })
				if ok and type(term) == "string" then
					terms[#terms + 1] = term
				end
			else
				unnamed = unnamed + 1
			end
		end
	end
	if #terms == 0 then
		return nil, unnamed > 0 and "Item names not loaded yet; try again." or "Nothing to buy at auction."
	end
	local ok = pcall(api.CreateShoppingList, ADDON, LIST_NAME, terms)
	if not ok then
		return nil, "Auctionator would not make the list."
	end
	local text = ("Shopping list \"%s\": %d material%s."):format(LIST_NAME, #terms, #terms == 1 and "" or "s")
	if unnamed > 0 then
		text = text .. (" %d not loaded, left out."):format(unnamed)
	end
	return #terms, text
end

-- The pane ---------------------------------------------------------------------------

local Money -- from the window, set when the pane is made

local function Note(material)
	if material.from == "vendor" then
		return "|cff999999vendor|r"
	elseif not material.unit then
		return "|cffff8040no price|r"
	elseif material.ratio and material.ratio < LOW then
		return "|cff40c040cheap today|r"
	elseif material.ratio and material.ratio > HIGH then
		return "|cffff8040dear today|r"
	end
	return ""
end

local function LineTooltip(self)
	local material = self.material
	if not material then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local _, link = C_Item.GetItemInfo(material.id)
	if link then
		GameTooltip:SetHyperlink(link)
	else
		GameTooltip:AddLine("item " .. material.id, 1, 1, 1)
	end
	local m = material.market
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Last scan", m.now and Money(m.now) or "none", 0.6, 0.6, 0.6, 1, 1, 1)
	if m.median then
		GameTooltip:AddDoubleLine(("Median of %d day%s"):format(m.days, m.days == 1 and "" or "s"), Money(m.median), 0.6, 0.6, 0.6, 1, 1, 1)
	end
	if m.vendor then
		GameTooltip:AddDoubleLine("Vendor", Money(m.vendor), 0.6, 0.6, 0.6, 1, 1, 1)
	end
	if material.spend then
		GameTooltip:AddDoubleLine(("Buying %d"):format(material.buy), Money(material.spend), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function Text(line, column, justify)
	local text = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	local at = COLUMNS[column]
	text:SetPoint("LEFT", at[1], 0)
	if at[2] > 0 then
		text:SetWidth(at[2])
	else
		text:SetPoint("RIGHT", 0, 0)
	end
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	line[column] = text
end

local function MakeLine(index)
	local line = CreateFrame("Frame", nil, pane)
	line:SetHeight(LINE)
	line:SetPoint("TOPLEFT", 10, -TOP - (index - 1) * LINE)
	line:SetPoint("RIGHT", -12, 0)
	line:EnableMouse(true)
	line:SetScript("OnEnter", LineTooltip)
	line:SetScript("OnLeave", function() GameTooltip:Hide() end)
	line.icon = line:CreateTexture(nil, "ARTWORK")
	line.icon:SetSize(14, 14)
	line.icon:SetPoint("LEFT", 4, 0)
	Text(line, "name")
	Text(line, "need", "RIGHT")
	Text(line, "have", "RIGHT")
	Text(line, "buy", "RIGHT")
	Text(line, "each", "RIGHT")
	Text(line, "note")
	return line
end

local function FillLine(line, material)
	line.material = material
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(material.id)
	local colour = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	name = name or ("item " .. material.id)
	line.icon:SetTexture(icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(material.id)) or 134400)
	line.name:SetText(colour and colour.hex and (colour.hex .. name .. "|r") or name)
	line.need:SetText(material.need)
	line.have:SetText(material.have)
	line.buy:SetText(material.buy > 0 and material.buy or "|cff40c0400|r")
	line.each:SetText(material.unit and Money(material.unit) or "")
	line.note:SetText(Note(material))
	line:Show()
end

local function VisibleLines()
	return math.max(1, math.floor((pane:GetHeight() - TOP - BOTTOM) / LINE))
end

function ns.DrawPlan()
	if not pane or not pane:IsShown() then
		return
	end
	materials, summary = ns.Materials()
	local visible = VisibleLines()
	offset = math.max(0, math.min(offset, #materials - visible))
	for index = 1, math.max(visible, #lines) do
		local material = index <= visible and materials[offset + index] or nil
		if material then
			lines[index] = lines[index] or MakeLine(index)
			FillLine(lines[index], material)
		elseif lines[index] then
			lines[index].material = nil
			lines[index]:Hide()
		end
	end
	if summary.crafts == 0 then
		pane.summary:SetText("Nothing planned: click a recipe in the list to plan one craft, right-click for one fewer.")
	else
		local text = ("%d craft%s. Buying costs %s"):format(summary.crafts, summary.crafts == 1 and "" or "s", Money(summary.spend))
		if summary.vendor > 0 then
			text = text .. (" (%s at a vendor)"):format(Money(summary.vendor))
		end
		text = text .. (". Profit after buying everything: %s."):format(Money(summary.profit))
		if summary.unpriced > 0 then
			text = text .. (" %d without a price."):format(summary.unpriced)
		end
		pane.summary:SetText(text)
	end
end

local function Header(column, label, justify)
	local text = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	local at = COLUMNS[column]
	text:SetPoint("TOPLEFT", 10 + at[1], -TOP + 16)
	if at[2] > 0 then
		text:SetWidth(at[2])
	end
	text:SetJustifyH(justify or "LEFT")
	text:SetText(label)
end

local function Button(label, width, onClick)
	local button = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	return button
end

local function MakePane(window, money)
	Money = money
	pane = CreateFrame("Frame", nil, window, "DefaultPanelTemplate")
	pane:SetSize(PANE, window:GetHeight())
	pane:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, 0)
	pane:EnableMouse(true)
	pane:Hide()
	pane.TitleContainer.TitleText:SetText("Materials")
	local close = CreateFrame("Button", nil, pane, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)

	Header("name", "Material")
	Header("need", "Need", "RIGHT")
	Header("have", "Have", "RIGHT")
	Header("buy", "Buy", "RIGHT")
	Header("each", "Each", "RIGHT")
	Header("note", "")

	pane.summary = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.summary:SetPoint("BOTTOMLEFT", 14, 36)
	pane.summary:SetPoint("RIGHT", -14, 0)
	pane.summary:SetJustifyH("LEFT")
	pane.summary:SetWordWrap(true)

	pane.note = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.note:SetPoint("BOTTOMLEFT", 14, 14)
	pane.note:SetJustifyH("LEFT")

	local clear = Button("Clear", 70, function()
		ns.db.plan = nil
		pane.note:SetText("")
		ns.PlanChanged()
	end)
	clear:SetPoint("BOTTOMRIGHT", -12, 8)
	local shopping = Button("Shopping list", 110, function()
		local _, text = ns.ShoppingList()
		pane.note:SetText(text)
	end)
	shopping:SetPoint("RIGHT", clear, "LEFT", -4, 0)
	pane.note:SetPoint("RIGHT", shopping, "LEFT", -8, 0)

	pane:EnableMouseWheel(true)
	pane:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		ns.DrawPlan()
	end)
	pane:SetScript("OnShow", ns.DrawPlan)
end

function ns.TogglePlan(window, money)
	if not pane then
		MakePane(window, money)
	end
	pane:SetShown(not pane:IsShown())
end

function ns.Plan(id, delta)
	ns.db.plan = ns.db.plan or {}
	local count = math.max(0, (ns.db.plan[id] or 0) + delta)
	ns.db.plan[id] = count > 0 and count or nil
	if next(ns.db.plan) == nil then
		ns.db.plan = nil
	end
	ns.PlanChanged()
end

function ns.PlanChanged()
	ns.Changed() -- the list, for the planned counts, and this pane
end

-- What the pane shows changes with bags and prices too.
local listChanged = ns.Changed
function ns.Changed()
	if listChanged then
		listChanged()
	end
	ns.DrawPlan()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	local registry = Syndicator and Syndicator.CallbackRegistry
	if registry and registry.RegisterCallback then
		pcall(registry.RegisterCallback, registry, "BagCacheUpdate", ns.DrawPlan, events)
		pcall(registry.RegisterCallback, registry, "MailCacheUpdate", ns.DrawPlan, events)
	end
end)
