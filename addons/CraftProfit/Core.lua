-- CraftProfit: which of your characters' recipes make money.
--
-- Recipes: read from the game whenever a character opens one of its own
-- profession windows (not a linked one, a guild's or an NPC's), and kept
-- for all characters in CraftProfitDB. A recipe counts when it makes an
-- item; enchantments put on an item make none and are left out. Only the
-- basic reagents count: optional and finishing reagents are your choice.
--
-- Prices, all from Auctionator:
-- - A material costs the cheapest of the auction price, the vendor price
--   and crafting it with a recipe one of your characters has learned
--   (see Make or buy), over every item that fits its slot. Vendor prices are the ones
--   Auctionator saw at a merchant, so a material bought from a vendor you
--   never opened counts at its auction price.
-- - The item sells for the lower of the last scanned price and the median
--   of the daily lowest prices Auctionator kept (21 days by default). One
--   lone listing at a high price does not make a recipe look good.
-- - What the item brings is that price times the average number a craft
--   makes, less the auction house's 5% cut. The deposit is left out: it is
--   only lost when the item does not sell.
-- - Items that bind when picked up cannot be sold and are left out.
--
-- Profit = what it brings - what the materials cost. A recipe whose item or
-- some material has no price at all is listed at the end, saying which.

local ADDON, ns = ...

local CUT = 0.95 -- the auction house keeps 5%
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
local BIND_ON_PICKUP = 1

ns.db = nil
ns.rows = {} -- the last Collect: one row per recipe, best first
ns.characters = {} -- name -> { profession -> recipe count }, for the status line

local function Api()
	return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.Ready()
	return Api() ~= nil
end

function ns.Character()
	local name = UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
	return (name or "?") .. "-" .. (realm or "?")
end

-- Reading recipes ------------------------------------------------------------

local function TradeSkill()
	local T = C_TradeSkillUI
	if not T then
		return nil
	end
	for _, other in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
		if T[other] and T[other]() then
			return nil
		end
	end
	return T
end

-- Every recipe of the open profession. GetAllRecipeIDs where the game has
-- it; else what the window lists, which its search and filters can narrow.
local function RecipeIDs(T)
	if T.GetAllRecipeIDs then
		local ok, ids = pcall(T.GetAllRecipeIDs)
		if ok and type(ids) == "table" and #ids > 0 then
			return ids, true
		end
	end
	if T.GetFilteredRecipeIDs then
		local ok, ids = pcall(T.GetFilteredRecipeIDs)
		if ok and type(ids) == "table" then
			return ids, false
		end
	end
	return {}, false
end

local function Reagents(schematic)
	local out = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		if slot.reagentType == BASIC and (slot.quantityRequired or 0) > 0 then
			local ids = {}
			for _, reagent in ipairs(slot.reagents or {}) do
				if reagent.itemID then
					ids[#ids + 1] = reagent.itemID
				end
			end
			if #ids > 0 then
				out[#out + 1] = { ids = ids, n = slot.quantityRequired }
			end
		end
	end
	return out
end

function ns.Record()
	local T = TradeSkill()
	if not T or not ns.db then
		return
	end
	local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
	local profession = base and base.professionName
	if not profession or profession == "" then
		return
	end
	local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
	local skill = (child and (child.skillLevel or 0) > 0) and child or base

	local who = ns.Character()
	local book = ns.db.characters[who] or { professions = {} }
	ns.db.characters[who] = book
	local entry = book.professions[profession] or { recipes = {} }
	book.professions[profession] = entry
	entry.skill, entry.max, entry.seen = skill.skillLevel, skill.maxSkillLevel, time()

	local ids, all = RecipeIDs(T)
	for _, id in ipairs(ids) do
		local info = T.GetRecipeInfo(id)
		local schematic = info and T.GetRecipeSchematic(id, false)
		if schematic and schematic.outputItemID then
			-- Recipes are never unlearned: a recipe read before stays.
			entry.recipes[id] = {
				name = schematic.name,
				item = schematic.outputItemID,
				min = schematic.quantityMin or 1,
				max = schematic.quantityMax or schematic.quantityMin or 1,
				reagents = Reagents(schematic),
				learned = info.learned and true or false,
			}
		end
	end
	entry.complete = all or entry.complete
	ns.Invalidate()
end

-- Reading trainers ---------------------------------------------------------------
--
-- What a recipe needs to be learned is not in the client, and the profession
-- window says nothing of it for recipes not learned. A profession trainer's
-- window lists each recipe it teaches with the skill it wants and its cost:
-- kept in CraftProfitDB.trainer[profession][recipe name] = { skill, cost },
-- for every character. The trainer lists only what its filters show
-- (available and unavailable, by default); what one visit missed, another
-- adds.

function ns.RecordTrainer()
	if not ns.db or not GetNumTrainerServices or (IsTradeskillTrainer and not IsTradeskillTrainer()) then
		return
	end
	local changed = false
	for index = 1, GetNumTrainerServices() or 0 do
		local name, kind = GetTrainerServiceInfo(index)
		if name and kind ~= "header" then
			local profession, rank = GetTrainerServiceSkillReq(index)
			local cost = GetTrainerServiceCost and GetTrainerServiceCost(index)
			if profession and type(rank) == "number" then
				local book = ns.db.trainer[profession] or {}
				ns.db.trainer[profession] = book
				local old = book[name]
				if not old or old.skill ~= rank or old.cost ~= cost then
					book[name] = { skill = rank, cost = cost }
					changed = true
				end
			end
		end
	end
	if changed then
		ns.Invalidate()
	end
end

-- Reading vendors ----------------------------------------------------------------
--
-- Auctionator keeps a vendor's prices only for what it sells in unlimited
-- stock, and many vendor patterns come one or two at a time. So patterns
-- (items in Data.lua) are read here whenever a merchant opens, limited or
-- not: CraftProfitDB.vendor[pattern item] = { cost, vendor, limited }, the
-- cheapest seen. Items that cost something other than gold are left out.

local patternItems -- pattern item -> true, from Data.lua
local function IsPattern(item)
	if not patternItems then
		patternItems = {}
		for _, list in pairs(ns.patterns or {}) do
			for i = 1, #list, 2 do
				patternItems[list[i]] = true
			end
		end
	end
	return patternItems[item]
end

local function MerchantItem(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
		end
		return nil
	end
	local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(index)
	return price, stack, available, extended
end

function ns.RecordMerchant()
	if not ns.db or not GetMerchantNumItems then
		return
	end
	local vendor = UnitName("npc") or "a vendor"
	local changed = false
	for index = 1, GetMerchantNumItems() or 0 do
		local item = GetMerchantItemID(index)
		if item and IsPattern(item) then
			local price, stack, available, extended = MerchantItem(index)
			if price and price > 0 and not extended then
				local cost = price / math.max(1, stack or 1)
				local old = ns.db.vendor[item]
				if not old or cost <= old.cost then
					ns.db.vendor[item] = { cost = cost, vendor = vendor, limited = available ~= -1 }
					changed = changed or not old or old.cost ~= cost or old.vendor ~= vendor
				end
			end
		end
	end
	if changed then
		ns.Invalidate()
	end
end

-- Prices -----------------------------------------------------------------------

local market -- per Collect: itemID -> what Auctionator says
-- For the session: itemID -> what the game said of it. The game can drop an
-- item it loaded before; kept here, a row does not lose its icon and name.
local items = {}

local function Call(name, id)
	local api = Api()
	if not api or not api[name] then
		return nil
	end
	local ok, value = pcall(api[name], ADDON, id)
	return ok and type(value) == "number" and value > 0 and value or nil
end

-- Auctionator's kept days, newest first. Not part of its API: guarded.
local function History(id)
	local database = Auctionator and Auctionator.Database
	if not database or type(database.GetPriceHistory) ~= "function" then
		return nil
	end
	local ok, days = pcall(database.GetPriceHistory, database, tostring(id))
	return ok and type(days) == "table" and days or nil
end

local function Median(values)
	if #values == 0 then
		return nil
	end
	table.sort(values)
	local middle = (#values + 1) / 2
	return (values[math.floor(middle)] + values[math.ceil(middle)]) / 2
end

function ns.Market(id)
	local known = market and market[id]
	if known then
		return known
	end
	local m = { now = Call("GetAuctionPriceByItemID", id), vendor = Call("GetVendorPriceByItemID", id) }
	local age = Api() and Api().GetAuctionAgeByItemID and select(2, pcall(Api().GetAuctionAgeByItemID, ADDON, id))
	m.age = type(age) == "number" and age or nil
	local days, lows = History(id), {}
	for _, day in ipairs(days or {}) do
		if type(day.minSeen) == "number" and day.minSeen > 0 then
			lows[#lows + 1] = day.minSeen
		end
	end
	m.median, m.days = Median(lows), #lows
	m.listed = days and days[1] and days[1].available or nil
	m.sell = m.now and m.median and math.min(m.now, m.median) or m.now
	if market then
		market[id] = m
	end
	return m
end

local function ShortName(who)
	return (who:gsub("%-.*$", ""))
end

-- Make or buy -------------------------------------------------------------------
--
-- A material that one of your characters can craft (a learned recipe that
-- makes it) costs the cheaper of buying it and crafting it, crafting at
-- what that recipe's own materials cost, made or bought the same way, per
-- item it makes. A recipe that would need the material it makes, however
-- deep, does not count for it (the essences turn into each other).

local makers -- itemID -> { { recipe, id, who } }: learned recipes only; made again after a change

local function Makers()
	if makers then
		return makers
	end
	makers = {}
	for who, book in pairs(ns.db.characters) do
		for _, entry in pairs(book.professions or {}) do
			for id, recipe in pairs(entry.recipes or {}) do
				if recipe.learned then
					local list = makers[recipe.item] or {}
					makers[recipe.item] = list
					list[#list + 1] = { recipe = recipe, id = id, who = ShortName(who) }
				end
			end
		end
	end
	return makers
end

local costs -- per Collect: itemID -> its cheapest way, or false for none

local ItemCost

-- The cheapest item for one reagent slot: unit, way, which item, maker.
local function SlotCost(ids, visiting)
	local best, which
	for _, id in ipairs(ids) do
		local way = ItemCost(id, visiting)
		if way and (not best or way.unit < best.unit) then
			best, which = way, id
		end
	end
	return best, which or ids[1]
end

-- What one item costs at the cheapest: { unit, from = "auction" | "vendor"
-- | "craft", maker }, or nil when there is no way to get it.
function ItemCost(id, visiting)
	local top = visiting == nil
	if top and costs and costs[id] ~= nil then
		return costs[id] or nil
	end
	visiting = visiting or {}
	local m = ns.Market(id)
	local best
	if m.now then
		best = { unit = m.now, from = "auction" }
	end
	if m.vendor and (not best or m.vendor < best.unit) then
		best = { unit = m.vendor, from = "vendor" }
	end
	if not visiting[id] then
		visiting[id] = true
		for _, maker in ipairs(Makers()[id] or {}) do
			local recipe = maker.recipe
			local makes = (recipe.min + recipe.max) / 2
			local total = 0
			for _, slot in ipairs(recipe.reagents) do
				local way = SlotCost(slot.ids, visiting)
				if not way then
					total = nil
					break
				end
				total = total + way.unit * slot.n
			end
			if total and makes > 0 and (not best or total / makes < best.unit) then
				best = { unit = total / makes, from = "craft", maker = maker }
			end
		end
		visiting[id] = nil
	end
	-- Only a top-level answer is kept: one found inside another's search
	-- may have had a way left out to avoid going round in a circle.
	if top and costs then
		costs[id] = best or false
	end
	return best
end
ns.ItemCost = function(id) return ItemCost(id) end

-- The cheapest way to fill one reagent slot: price each, where, which item,
-- and the recipe when it is crafted.
function ns.UnitCost(ids)
	local way, which = SlotCost(ids)
	if not way then
		return nil, nil, which
	end
	return way.unit, way.from, which, way.maker
end

-- Items asked of the game this session: id -> true while waiting for its
-- answer, false once it said it has none. Each is asked once.
local asked = {}

-- Name, icon, quality, bind type; nil until the game has the item.
-- A bind type never changes, so it is kept in CraftProfitDB.bind: an item
-- the game has not loaded this time still keeps its bind-on-pickup rows out.
local function Item(id)
	local known = items[id]
	if known then
		return known
	end
	local name, link, quality, _, _, _, _, _, _, icon, _, _, _, bind = C_Item.GetItemInfo(id)
	if not name then
		if asked[id] == nil then
			asked[id] = true
			if C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(id)
			end
		end
		return nil
	end
	asked[id] = nil
	if bind then
		ns.db.bind[id] = bind
	end
	known = { name = name, link = link, quality = quality, icon = icon, bind = bind }
	items[id] = known
	return known
end

local function Bind(id, item)
	if item and item.bind then
		return item.bind
	end
	return ns.db.bind[id]
end

-- The game answered an item: true when it was one the list waits for.
function ns.Answered(id, success)
	if not asked[id] then
		return false
	end
	asked[id] = success and nil or false
	return success and true or false
end

function ns.Evaluate(recipe)
	local row = { recipe = recipe, parts = {}, cost = 0 }
	for _, slot in ipairs(recipe.reagents) do
		local unit, from, which, maker = ns.UnitCost(slot.ids)
		row.parts[#row.parts + 1] = { id = which, n = slot.n, unit = unit, from = from, maker = maker }
		if unit then
			row.cost = row.cost + unit * slot.n
		else
			row.missing = row.missing or which
		end
	end
	row.market = ns.Market(recipe.item)
	row.makes = (recipe.min + recipe.max) / 2
	if row.market.sell then
		row.value = row.market.sell * row.makes * CUT
	else
		row.missing = recipe.item
	end
	if not row.missing then
		row.profit = row.value - row.cost
	end
	return row
end

local function Better(a, b)
	if (a.profit ~= nil) ~= (b.profit ~= nil) then
		return a.profit ~= nil
	end
	if a.profit and a.profit ~= b.profit then
		return a.profit > b.profit
	end
	return (a.name or "") < (b.name or "")
end

-- The cheapest pattern that teaches a recipe at this skill and has a price
-- (Data.lua, from the client tables): { item, skill, cost, from, vendor,
-- limited }, or nil. A price: the auction house, Auctionator's vendor
-- prices, or a vendor read here.
local function Pattern(id, skill)
	local list = ns.patterns and ns.patterns[id]
	if not list then
		return nil
	end
	local best
	for i = 1, #list, 2 do
		local item, need = list[i], list[i + 1]
		if need <= skill then
			local m = ns.Market(item)
			local cost, from = m.now, "auction"
			local vendor, limited
			if m.vendor and (not cost or m.vendor < cost) then
				cost, from = m.vendor, "vendor"
			end
			local seen = ns.db.vendor[item]
			if seen and (not cost or seen.cost <= cost) then
				cost, from, vendor, limited = seen.cost, "vendor", seen.vendor, seen.limited
			end
			if cost and (not best or cost < best.cost) then
				best = { item = item, skill = need, cost = cost, from = from, vendor = vendor, limited = limited }
			end
		end
	end
	return best
end

-- Every recipe of every character, one row per recipe with who knows it.
function ns.Collect()
	market, costs = {}, {}
	local byRecipe, rows = {}, {}
	ns.characters = {}
	for who, book in pairs(ns.db.characters) do
		for profession, entry in pairs(book.professions or {}) do
			local count = 0
			for id, recipe in pairs(entry.recipes or {}) do
				if recipe.learned then
					count = count + 1
				end
				-- What a trainer said of it ({ skill, cost }), or a pattern with
				-- a price: learnable when this character's skill is there.
				local trained = not recipe.learned and ns.db.trainer[profession] and ns.db.trainer[profession][recipe.name]
				if trained and (entry.skill or 0) < trained.skill then
					trained = nil
				end
				local pattern = not recipe.learned and not trained and ns.db.show == "learnable" and Pattern(id, entry.skill or 0) or nil
				local learnable = (trained or pattern) and true or false
				if recipe.learned or ns.db.show == "all" or (learnable and ns.db.show == "learnable") then
					local row = byRecipe[id]
					if not row then
						local item = Item(recipe.item)
						if Bind(recipe.item, item) ~= BIND_ON_PICKUP then
							row = ns.Evaluate(recipe)
							row.id, row.profession, row.who, row.item = id, profession, {}, item
							row.name = item and item.name or recipe.name
							-- The icon is in the client's own data, loaded or not.
							row.icon = item and item.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(recipe.item))
							byRecipe[id] = row
							rows[#rows + 1] = row
						end
					end
					if row then
						local name = ShortName(who)
						if recipe.learned then
							row.who[#row.who + 1] = name
						elseif trained then
							row.who[#row.who + 1] = ("%s (learn at %d)"):format(name, trained.skill)
							row.train = trained
						elseif pattern then
							row.who[#row.who + 1] = ("%s (pattern, %d)"):format(name, pattern.skill)
							row.pattern = pattern
						else
							row.who[#row.who + 1] = name .. " (not learned)"
						end
						row.learned = row.learned or recipe.learned
						row.learnable = row.learnable or learnable
					end
				end
			end
			ns.characters[ShortName(who)] = ns.characters[ShortName(who)] or {}
			ns.characters[ShortName(who)][profession] = { count = count, skill = entry.skill, complete = entry.complete }
		end
	end
	for _, row in ipairs(rows) do
		table.sort(row.who)
	end
	table.sort(rows, Better)
	ns.rows = rows
	ns.fresh = true
	return rows
end

-- Events -------------------------------------------------------------------------

local pending = {} -- fn -> true while it waits to run
local function Later(fn)
	if pending[fn] then
		return
	end
	pending[fn] = true
	C_Timer.After(0.3, function()
		pending[fn] = nil
		fn()
	end)
end

-- Something changed: the list is made again the next time it is drawn.
function ns.Invalidate()
	ns.fresh = false
	makers = nil
	if ns.Changed then
		ns.Changed()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("TRAINER_UPDATE")
events:RegisterEvent("MERCHANT_SHOW")
events:SetScript("OnEvent", function(_, event, arg, arg2)
	if event == "ADDON_LOADED" and arg == ADDON then
		CraftProfitDB = type(CraftProfitDB) == "table" and CraftProfitDB or {}
		ns.db = CraftProfitDB
		ns.db.characters = ns.db.characters or {}
		ns.db.bind = ns.db.bind or {}
		ns.db.trainer = ns.db.trainer or {}
		ns.db.vendor = ns.db.vendor or {}
		-- "known", "learnable" or "all"; 1.1's checkbox meant "all".
		if ns.db.unlearned then
			ns.db.show, ns.db.unlearned = "all", nil
		end
		ns.db.show = ns.db.show or "known"
	elseif event == "PLAYER_LOGIN" then
		local api = Api()
		if api and api.RegisterForDBUpdate then
			pcall(api.RegisterForDBUpdate, ADDON, ns.Invalidate)
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
		Later(ns.Record)
	elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		Later(ns.RecordTrainer)
	elseif event == "MERCHANT_SHOW" then
		Later(ns.RecordMerchant)
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- Only an item the list waits for, and only when it did load.
		if ns.Answered(arg, arg2) and ns.Shown and ns.Shown() then
			Later(ns.Invalidate)
		end
	end
end)
