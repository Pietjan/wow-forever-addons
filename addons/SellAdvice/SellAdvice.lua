-- SellAdvice: one line in an item's tooltip saying what brings the most
-- for it: disenchanting, the vendor or the auction house. The options that
-- lost show only while Alt is held. Among quest choices, the one worth the
-- most gets a gold coin on its icon. In Baganator, when the bags are full,
-- a red cross marks the bag item that is cheapest to drop.
--
-- - Vendor: the item's sell price from the client.
-- - Auction: Auctionator's last scanned price, less the house's 5% cut.
--   Not for items that bind on pickup, are quest items, or are bound.
--   And only when it pays: what the stack brings over the next best option
--   has to be more than the deposit, which is lost when it does not sell.
--   The deposit is the game's own figure for the longest listing.
-- - Disenchant: the average materials (Data.lua, made by
--   scripts/sell-advice-data.py) at Auctionator's prices, less the 5% cut
--   for selling them. A lesser essence counts as a third of a greater one
--   when that is worth more, and the other way round. Characters without
--   Disenchant see it too, marked "on an enchanter", unless the item is
--   bound (binds on pickup, quest item or soulbound) and so cannot be sent.
-- - Essences: also the auction in their other form, three lesser for one
--   greater and back, as "Convert to greater" or "Convert to lesser". It
--   is the advice when it brings more than listing them as they are.
--
-- Amounts are for the stack the tooltip is about. Lesser essences count as
-- thirds of a greater one, also in a stack that does not divide by three:
-- converting takes them from every bag.
--
-- Hold Alt for every option, why one has no value, and the disenchant
-- materials with their prices.
--
-- Tooltip contents can be secret in combat; a secret value is skipped.

local ADDON, ns = ...
local IsSecret = issecretvalue or function() return false end

local CUT = 0.95 -- the auction house keeps 5%
local DISENCHANT_SPELL = 13262

local function Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

local function AuctionPrice(link)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not api then
		return nil
	end
	local ok, price
	if type(link) == "number" then
		ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, link)
	else
		ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
	end
	return ok and type(price) == "number" and price > 0 and price or nil
end

local greaterOf = {}
for lesser, greater in pairs(ns.essences) do
	greaterOf[greater] = lesser
end

-- A disenchanting material's worth: its own price, or what it converts to.
local function MaterialPrice(itemID)
	local own = AuctionPrice(itemID) or 0
	local greater = ns.essences[itemID]
	if greater then
		return math.max(own, (AuctionPrice(greater) or 0) / 3)
	end
	local lesser = greaterOf[itemID]
	if lesser then
		return math.max(own, (AuctionPrice(lesser) or 0) * 3)
	end
	return own
end

-- An essence's other form: its item ID, how many of it `per` of this one
-- make, and the key of the option to list it that way.
local function OtherForm(itemID)
	if ns.essences[itemID] then
		return ns.essences[itemID], 1, 3, "greater"
	elseif greaterOf[itemID] then
		return greaterOf[itemID], 3, 1, "lesser"
	end
end

-- Average worth of disenchanting one item, after the cut, and the
-- materials it was worked out from ({ item ID, average amount, price });
-- nil and why not when there is no value.
local function DisenchantValue(itemID, classID, quality, level)
	if ns.noDisenchant[itemID] then
		return nil, "cannot be disenchanted"
	end
	for _, entry in ipairs(ns.disenchant) do
		if entry[1] == classID and entry[2] == quality and level >= entry[3] and level <= entry[4] then
			local total, priced, parts = 0, false, {}
			local gives = entry[5]
			for i = 1, #gives, 2 do
				local price = MaterialPrice(gives[i])
				if price > 0 then
					priced = true
				end
				total = total + gives[i + 1] * price
				parts[#parts + 1] = { gives[i], gives[i + 1], price }
			end
			if not priced then
				return nil, "no material prices scanned", parts
			end
			return math.floor(total * CUT), nil, parts
		end
	end
	return nil, ("no bracket for item level %d"):format(level)
end

local function IsBound(data)
	local guid = data and Plain(data.guid)
	if not guid or not (C_Item.GetItemLocation and C_Item.IsBound) then
		return false
	end
	local ok, bound = pcall(function()
		local location = C_Item.GetItemLocation(guid)
		return location and location:IsValid() and C_Item.IsBound(location)
	end)
	return ok and bound == true
end

-- How many the tooltip is about: the stack in the bag, else one.
local function StackCount(data)
	local guid = data and Plain(data.guid)
	if not guid or not (C_Item.GetItemLocation and C_Item.GetStackCount) then
		return 1
	end
	local ok, count = pcall(function()
		local location = C_Item.GetItemLocation(guid)
		return location and location:IsValid() and C_Item.GetStackCount(location)
	end)
	count = ok and Plain(count)
	return type(count) == "number" and count >= 1 and count or 1
end

-- What listing `count` of an item costs up front, for the longest listing.
-- The game works it out (C_AuctionHouse.CalculateCommodityDeposit answers
-- away from the auction house too). Where it gives nothing, the rule that
-- its answers for a 5 copper item fit: 60% of the vendor price, at least
-- one copper.
local LONGEST = 3
local MIN_DEPOSIT = 1

local function Deposit(itemID, count, sellPrice)
	local calculate = C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit
	if calculate and itemID then
		local ok, deposit = pcall(calculate, itemID, LONGEST, count)
		deposit = ok and Plain(deposit)
		if type(deposit) == "number" and deposit > 0 then
			return deposit
		end
	end
	return math.max(MIN_DEPOSIT, math.floor((sellPrice or 0) * count * 0.6))
end

local function Money(copper)
	copper = math.floor(copper + 0.5)
	if copper <= 0 then
		return "0"
	end
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return C_CurrencyInfo.GetCoinTextureString(copper)
end

local function ItemName(itemID)
	return C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

local LABEL = { disenchant = "Disenchant", auction = "Auction", greater = "Convert to greater", lesser = "Convert to lesser", vendor = "Vendor" }
-- The options that are an auction listing: as it is, or in its other form.
local LISTING = { auction = true, greater = true, lesser = true }
local GREY = 0.6

-- Alt held: every option with its value or why it has none, and the
-- disenchant materials with their amounts and prices.
local function AddDetails(tooltip, options, missing, parts, level, count)
	tooltip:AddLine("SellAdvice" .. (level and (" (item level " .. level .. ")") or "") .. (count > 1 and (" x" .. count) or ""), 1, 0.82, 0)
	for i, option in ipairs(options) do
		local color = i == 1 and "|cff40c040" or "|cffffffff"
		tooltip:AddDoubleLine(color .. LABEL[option.key] .. "|r", Money(option.value * count), 1, 1, 1, 1, 1, 1)
	end
	for _, key in ipairs({ "disenchant", "auction", "greater", "lesser", "vendor" }) do
		if missing[key] then
			tooltip:AddDoubleLine(LABEL[key], missing[key], GREY, GREY, GREY, GREY, GREY, GREY)
		end
	end
	if parts then
		for _, part in ipairs(parts) do
			local itemID, amount, price = unpack(part)
			tooltip:AddDoubleLine(("  %.2f x %s"):format(amount, ItemName(itemID)),
				price > 0 and Money(amount * price) .. " (" .. Money(price) .. " each)" or "no price",
				GREY, GREY, GREY, GREY, GREY, GREY)
		end
	end
end

-- What an item can bring: options sorted best first ({ key, value }, the
-- value for one item), why the others have no value, the disenchant
-- materials, the item level and how many the tooltip is about. Nil while
-- the item is not cached. `slot` ({ count, bound }) describes a bag slot
-- read from the container instead of from tooltip data.
local function Options(link, data, slot)
	local _, _, quality, level, _, _, _, _, _, _, sellPrice, classID, _, bindType = C_Item.GetItemInfo(link)
	if not quality then
		return nil
	end
	local itemID = C_Item.GetItemInfoInstant(link)
	local options, missing, parts = {}, {}, nil
	if sellPrice and sellPrice > 0 then
		options[#options + 1] = { key = "vendor", value = sellPrice }
	else
		missing.vendor = "cannot be sold"
	end
	-- 1 binds on pickup, 4 is a quest item.
	local bound = bindType == 1 or bindType == 4 or (slot and slot.bound) or IsBound(data)
	if bindType == 1 or bindType == 4 then
		missing.auction = bindType == 1 and "binds on pickup" or "quest item"
	elseif bound then
		missing.auction = "soulbound"
	else
		local price = AuctionPrice(link)
		if price then
			options[#options + 1] = { key = "auction", value = math.floor(price * CUT) }
		else
			missing.auction = Auctionator and "no price scanned" or "Auctionator not loaded"
		end
		-- An essence can be listed in its other form too.
		local other, makes, per, key = OtherForm(itemID)
		if other then
			local otherPrice = AuctionPrice(other)
			if otherPrice then
				options[#options + 1] = { key = key, value = math.floor(otherPrice * makes / per * CUT), item = other, makes = makes, per = per }
			else
				missing[key] = Auctionator and "no price scanned" or "Auctionator not loaded"
			end
		end
	end
	local canDisenchant = IsPlayerSpell and IsPlayerSpell(DISENCHANT_SPELL)
	if bound and not canDisenchant then
		-- It cannot be sent to an enchanter.
		missing.disenchant = "bound, and you cannot disenchant"
	elseif (classID == 2 or classID == 4) and quality >= 2 and quality <= 4 and itemID then
		local value, why
		value, why, parts = DisenchantValue(itemID, classID, quality, level or 0)
		if value then
			options[#options + 1] = { key = "disenchant", value = value }
		else
			missing.disenchant = why
		end
	else
		missing.disenchant = "not uncommon+ armour or weapon"
	end
	table.sort(options, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		-- Level: an essence stays as it is.
		return a.item == nil and b.item ~= nil
	end)
	-- The auction has to pay for its risk: a listing that does not sell
	-- costs the deposit. It is weighed against the best option that is not
	-- a listing; an essence's two listings do not rule each other out.
	local count = slot and slot.count or StackCount(data)
	local ruledOut = false
	while options[1] and LISTING[options[1].key] do
		local top, other = options[1], nil
		for i = 2, #options do
			if not LISTING[options[i].key] then
				other = options[i]
				break
			end
		end
		local otherValue = other and other.value or 0
		local gain = (top.value - otherValue) * count
		local deposit
		if top.item then
			-- Listed in its other form: that item's deposit, for as many as
			-- these make.
			local _, _, _, _, _, _, _, _, _, _, otherSell = C_Item.GetItemInfo(top.item)
			deposit = Deposit(top.item, math.max(1, math.floor(count * top.makes / top.per)), otherSell)
		else
			deposit = Deposit(itemID, count, sellPrice)
		end
		if gain > deposit then
			break
		end
		table.remove(options, 1)
		ruledOut = true
		missing[top.key] = ("%s more than %s, deposit %s"):format(Money(gain), otherValue > 0 and LABEL[other.key]:lower() or "nothing", Money(deposit))
	end
	return options, missing, parts, level, count, ruledOut
end

local function AddAdvice(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local ok, _, link = pcall(tooltip.GetItem, tooltip)
	link = ok and Plain(link)
	if type(link) ~= "string" then
		return
	end
	-- On a recipe the tooltip's hyperlink is the crafted item's, while its
	-- ID is the recipe's (Auctionator works around the same thing): price
	-- the recipe.
	local id = data and Plain(data.id)
	if type(id) == "number" and C_Item.GetItemInfoInstant(link) ~= id then
		local _, recipeLink = C_Item.GetItemInfo(id)
		if not recipeLink then
			return -- not cached yet; the tooltip refreshes once it is
		end
		link = Plain(recipeLink)
	end
	local options, missing, parts, level, count, ruledOut = Options(link, data)
	if not options then
		return -- not cached yet; the tooltip refreshes once it is
	end
	if IsAltKeyDown() then
		AddDetails(tooltip, options, missing, parts, level, count)
		return
	end
	-- One option and no other was weighed: nothing to choose between. An
	-- auction that was ruled out for its deposit was a choice, so say what won.
	if #options < 1 or (#options < 2 and not ruledOut) then
		return
	end
	local best = options[1]
	local label = LABEL[best.key]
	if best.key == "disenchant" and not (IsPlayerSpell and IsPlayerSpell(DISENCHANT_SPELL)) then
		label = label .. " (on an enchanter)"
	end
	tooltip:AddDoubleLine("|cff40c040" .. label .. "|r", Money(best.value * count), 1, 1, 1, 1, 1, 1)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		pcall(AddAdvice, tooltip, data)
	end)
end

-- Quest choices -------------------------------------------------------------

-- A gold coin on the quest choice worth the most: the best of vendor,
-- auction and disenchant for each. Textures are kept in our own table; no
-- field is written on Blizzard's reward buttons.
local coins = {}
local retrying = false

local function UpdateQuestChoices()
	local info = QuestInfoFrame
	local rewardsFrame = info and info.rewardsFrame
	local buttons = rewardsFrame and rewardsFrame.RewardButtons
	if type(buttons) ~= "table" then
		return
	end
	local best, bestValue, choices, pending = nil, 0, 0, false
	for _, button in ipairs(buttons) do
		if button:IsShown() and button.objectType == "item" and button.type == "choice" then
			choices = choices + 1
			local link
			if info.questLog then
				link = GetQuestLogItemLink("choice", button:GetID())
			else
				link = GetQuestItemLink("choice", button:GetID())
			end
			local options = link and Options(link)
			if link and not options then
				pending = true
			end
			local value = options and options[1] and options[1].value or 0
			if value > bestValue then
				best, bestValue = button, value
			end
		end
	end
	if choices < 2 then
		best = nil -- nothing to choose between
	end
	for _, button in ipairs(buttons) do
		local coin = coins[button]
		if button == best and not coin then
			coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
			coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
			coin:SetSize(16, 16)
			coin:SetPoint("TOPLEFT", button.Icon or button.icon or button, "TOPLEFT", -3, 3)
			coins[button] = coin
		end
		if coin then
			coin:SetShown(button == best)
		end
	end
	if pending and not retrying then
		retrying = true
		C_Timer.After(0.5, function()
			retrying = false
			pcall(UpdateQuestChoices)
		end)
	end
end

if QuestInfo_Display then
	hooksecurefunc("QuestInfo_Display", function()
		pcall(UpdateQuestChoices)
	end)
end

-- Cheapest to drop ------------------------------------------------------------

-- When the bags are full, the bag item worth least for the whole stack
-- (the best of vendor, auction and disenchant, as in the tooltip) gets a
-- red cross in Baganator. Grey items first; with no grey left, any item but
-- quest items, bags, tools, fishing poles and soulbound weapons or armour.
-- Items worth nothing anywhere are left alone: they are usually special
-- (keys, shards, the hearthstone).
local FIRST_BAG, LAST_BAG = 0, NUM_BAG_SLOTS or 4
local cheapest -- { bag, slot } or nil
local rescanning = false

local function NeverJunk(itemID, classID, subclassID, bindType, bound)
	return classID == 12 or bindType == 4 -- quest
		or classID == 1 or classID == 11 -- bags and quivers
		or ns.tools[itemID]
		or (classID == 2 and subclassID == 20) -- fishing pole
		or ((classID == 2 or classID == 4) and bound)
end

-- True when no general bag has a free slot (a herb or soul bag's free slots
-- do not take loot of other kinds).
local function BagsFull()
	for bag = FIRST_BAG, LAST_BAG do
		local free, family = C_Container.GetContainerNumFreeSlots(bag)
		if Plain(free) and free > 0 and Plain(family) == 0 then
			return false
		end
	end
	return true
end

-- The cheapest item to drop, and whether some item was not cached yet.
local function FindCheapest()
	if not BagsFull() then
		return nil, false
	end
	local best = { [true] = nil, [false] = nil } -- grey -> { bag, slot, value }
	local pending = false
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and Plain(info.hyperlink)
			if link then
				local _, _, quality, _, _, _, _, _, _, _, _, classID, subclassID, bindType = C_Item.GetItemInfo(link)
				local itemID = C_Item.GetItemInfoInstant(link)
				local bound = Plain(info.isBound) == true
				if not quality then
					pending = true
				elseif not NeverJunk(itemID, classID, subclassID, bindType, bound) then
					local options = Options(link, nil, { count = Plain(info.stackCount) or 1, bound = bound })
					if not options then
						pending = true
					elseif options[1] then
						local value = options[1].value * (Plain(info.stackCount) or 1)
						local grey = quality == 0
						if not best[grey] or value < best[grey][3] then
							best[grey] = { bag, slot, value }
						end
					end
				end
			end
		end
	end
	return best[true] or best[false], pending
end

local function Rescan()
	local ok, found, pending = pcall(FindCheapest)
	if not ok then
		found, pending = nil, false
	end
	local changed = (found and found[1]) ~= (cheapest and cheapest[1]) or (found and found[2]) ~= (cheapest and cheapest[2])
	cheapest = found
	if changed and Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh({ Baganator.Constants.RefreshReason.ItemWidgets })
	end
	if pending and not rescanning then
		rescanning = true
		C_Timer.After(0.5, function()
			rescanning = false
			Rescan()
		end)
	end
end

local function RegisterBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
		return
	end
	Baganator.API.RegisterCornerWidget("Cheapest to drop (SellAdvice)", "selladvice_drop", function(cross, details)
		local location = details.itemLocation
		return cheapest ~= nil and location ~= nil
			and location.bagID == cheapest[1] and location.slotIndex == cheapest[2]
	end, function(itemButton)
		local cross = itemButton:CreateTexture(nil, "OVERLAY")
		cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
		cross:SetSize(16, 16)
		return cross
	end, { corner = "top_left", priority = 1 })
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		pcall(RegisterBaganator)
		self:RegisterEvent("BAG_UPDATE_DELAYED")
	end
	Rescan()
end)
