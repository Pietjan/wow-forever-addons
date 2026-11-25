-- Vendors: everything a vendor sells, read when its window opens. A visit
-- replaces what the last one saw: the list is the vendor's whole stock.
-- Limited stock is recorded as "available" (how many it has now, -1
-- unlimited); what a purchase costs besides gold as "costs".

local _, ns = ...

local function MerchantItem(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = ns.Read("vendor item", C_MerchantFrame.GetItemInfo, index)
		if type(info) == "table" then
			return ns.Plain(info.price), ns.Plain(info.stackCount), ns.Plain(info.numAvailable), ns.Plain(info.hasExtendedCost)
		end
		return nil
	end
	local ok, _, _, price, stack, available, _, _, extended = pcall(GetMerchantItemInfo, index)
	if not ok then
		return nil
	end
	return ns.Plain(price), ns.Plain(stack), ns.Plain(available), ns.Plain(extended)
end

-- Costs besides gold: "i<item>:<n>,c<currency>:<n>".
local function Costs(index)
	local n = ns.Read("vendor costs", GetMerchantItemCostInfo, index) or 0
	local parts = {}
	for j = 1, n do
		local ok, _, value, link, currency = pcall(GetMerchantItemCostItem, index, j)
		value, link = ok and ns.Plain(value), ok and ns.Plain(link)
		local item = ns.ItemID(link)
		local cur = type(link) == "string" and tonumber(string.match(link, "currency:(%d+)"))
		if item and value then
			parts[#parts + 1] = "i" .. item .. ":" .. value
		elseif cur and value then
			parts[#parts + 1] = "c" .. cur .. ":" .. value
		elseif currency and value then
			parts[#parts + 1] = "c?" .. tostring(ns.Plain(currency)) .. ":" .. value
		end
	end
	return #parts > 0 and table.concat(parts, ",") or nil
end

function ns.ReadVendor()
	if ns.Fighting() then
		return
	end
	local key, kind, id = ns.Key(ns.Read("vendor", UnitGUID, "npc"))
	if kind ~= "npc" then
		return
	end
	local items = {}
	for index = 1, ns.Read("vendor items", GetMerchantNumItems) or 0 do
		local item = ns.Read("vendor item id", GetMerchantItemID, index)
		if item then
			local price, stack, available, extended = MerchantItem(index)
			items[item] = { price = price or 0, stack = stack or 1, available = available or -1, costs = extended and Costs(index) or nil }
		end
	end
	if next(items) then
		ns.db.vendors[id] = { seen = ns.Today(), items = items }
		ns.Place(key)
	end
end

-- MERCHANT_SHOW comes before the items are all known; MERCHANT_UPDATE when
-- they are. Each reads the window; the last one stands.
ns.On("MERCHANT_SHOW", ns.ReadVendor)
ns.On("MERCHANT_UPDATE", ns.ReadVendor)
