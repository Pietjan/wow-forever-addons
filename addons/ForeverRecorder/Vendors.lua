-- Vendors: everything a vendor sells, read when its window opens. A visit
-- replaces what the last one saw: the list is the vendor's whole stock.
-- Limited stock is recorded as "available" (how many it has now, -1
-- unlimited); what a purchase costs besides gold as "costs".
--
-- The prices are what the window shows: after your discounts. So each visit
-- also records what makes them: your standing with the vendor (its
-- reaction to you, 1 hated .. 8 exalted) and your rank in Bartering, the
-- Professions Legacy talent ("Reduces the gold price of items from all
-- vendors by 5%", 2 ranks): spell 1225459, trait node 110286 of trait
-- system 45 (client tables, build 1.60.1.71091). A rank the game does not
-- give is left out and counted as "bartering rank unread".

local _, ns = ...

local BARTERING_SYSTEM, BARTERING_NODE = 45, 110286

-- Bartering is your rank in Bartering, nil when the game does not say.
function ns.Bartering()
	if not (C_Traits and C_Traits.GetConfigIDBySystemID and C_Traits.GetNodeInfo) then
		return nil
	end
	local config = ns.Read("bartering config", C_Traits.GetConfigIDBySystemID, BARTERING_SYSTEM)
	if not config then
		return nil
	end
	local info = ns.Read("bartering node", C_Traits.GetNodeInfo, config, BARTERING_NODE)
	if type(info) ~= "table" then
		return nil
	end
	local rank = ns.Plain(info.activeRank) or ns.Plain(info.currentRank)
	return type(rank) == "number" and rank or nil
end

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
		local bartering = ns.Bartering()
		if not bartering then
			ns.Secret("bartering rank unread")
		end
		ns.db.vendors[id] = {
			seen = ns.Today(),
			standing = ns.Read("standing", UnitReaction, "npc", "player"),
			bartering = bartering,
			items = items,
		}
		ns.Place(key)
	end
end

-- MERCHANT_SHOW comes before the items are all known; MERCHANT_UPDATE when
-- they are. Each reads the window; the last one stands.
ns.On("MERCHANT_SHOW", ns.ReadVendor)
ns.On("MERCHANT_UPDATE", ns.ReadVendor)
