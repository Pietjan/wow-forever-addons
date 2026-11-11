-- SellAdvice: one line in an item's tooltip saying what brings the most
-- for it: disenchanting, the vendor or the auction house, and a dim line
-- with the other two to compare.
--
-- - Vendor: the item's sell price from the client.
-- - Auction: Auctionator's last scanned price, less the house's 5% cut.
--   Not for items that bind on pickup, are quest items, or are bound.
-- - Disenchant: the average materials (Data.lua, made by
--   scripts/sell-advice-data.py) at Auctionator's prices, less the 5% cut
--   for selling them. A lesser essence counts as a third of a greater one
--   when that is worth more, and the other way round. Characters without
--   Disenchant see it too, marked "on an enchanter".
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

-- Average worth of disenchanting one item, after the cut; nil if it cannot
-- be disenchanted or no material has a price yet.
local function DisenchantValue(itemID, classID, quality, level)
	if ns.noDisenchant[itemID] then
		return nil
	end
	for _, entry in ipairs(ns.disenchant) do
		if entry[1] == classID and entry[2] == quality and level >= entry[3] and level <= entry[4] then
			local total, priced = 0, false
			local gives = entry[5]
			for i = 1, #gives, 2 do
				local price = MaterialPrice(gives[i])
				if price > 0 then
					priced = true
				end
				total = total + gives[i + 1] * price
			end
			return priced and math.floor(total * CUT) or nil
		end
	end
	return nil
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

local function Money(copper)
	copper = math.floor(copper + 0.5)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return C_CurrencyInfo.GetCoinTextureString(copper)
end

local LABEL = { disenchant = "Disenchant", auction = "Auction", vendor = "Vendor" }

local function AddAdvice(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local ok, _, link = pcall(tooltip.GetItem, tooltip)
	link = ok and Plain(link)
	if type(link) ~= "string" then
		return
	end
	local _, _, quality, level, _, _, _, _, _, _, sellPrice, classID, _, bindType = C_Item.GetItemInfo(link)
	if not quality then
		return -- not cached yet; the tooltip refreshes once it is
	end
	local itemID = C_Item.GetItemInfoInstant(link)

	local options = {}
	if sellPrice and sellPrice > 0 then
		options[#options + 1] = { key = "vendor", value = sellPrice }
	end
	-- 1 binds on pickup, 4 is a quest item.
	if bindType ~= 1 and bindType ~= 4 and not IsBound(data) then
		local price = AuctionPrice(link)
		if price then
			options[#options + 1] = { key = "auction", value = math.floor(price * CUT) }
		end
	end
	local canDisenchant = (classID == 2 or classID == 4) and quality >= 2 and quality <= 4
	if canDisenchant and itemID then
		local value = DisenchantValue(itemID, classID, quality, level or 0)
		if value then
			options[#options + 1] = { key = "disenchant", value = value }
		end
	end
	if #options < 2 then
		return -- nothing to choose between
	end

	table.sort(options, function(a, b)
		return a.value > b.value
	end)
	local best = options[1]
	local label = LABEL[best.key]
	if best.key == "disenchant" and not (IsPlayerSpell and IsPlayerSpell(DISENCHANT_SPELL)) then
		label = label .. " (on an enchanter)"
	end
	tooltip:AddDoubleLine("|cff40c040" .. label .. "|r", Money(best.value), 1, 1, 1, 1, 1, 1)
	local others = {}
	for i = 2, #options do
		others[#others + 1] = LABEL[options[i].key]:lower() .. " " .. Money(options[i].value)
	end
	tooltip:AddLine(table.concat(others, "  ·  "), 0.6, 0.6, 0.6)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		pcall(AddAdvice, tooltip, data)
	end)
end
