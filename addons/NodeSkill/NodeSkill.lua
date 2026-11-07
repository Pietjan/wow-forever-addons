-- NodeSkill: on the minimap tooltip, a gathering node's name turns red when
-- your skill is not high enough to gather it.
--
-- The client's data does not say which skill a node needs: that comes from
-- the server, and the only place it shows is the node's own tooltip in the
-- world ("Requires Herbalism (15)"). So this addon learns the requirement
-- the first time you mouse over a node out in the world and remembers it in
-- its saved variables. A seed of the Classic Era values makes it useful from
-- the start; whatever the game says replaces the seed.

local ADDON_NAME = ...

local RED = { 1, 0.25, 0.25 }

local IsSecret = issecretvalue or function() return false end

-- Classic Era requirements, by node name: { profession, level }. Spelled as
-- the game spells them, which is also how the minimap names them.
local SEED = {
	-- Herbalism
	["Peacebloom"] = { "Herbalism", 1 },
	["Silverleaf"] = { "Herbalism", 1 },
	["Earthroot"] = { "Herbalism", 15 },
	["Mageroyal"] = { "Herbalism", 50 },
	["Briarthorn"] = { "Herbalism", 70 },
	["Swiftthistle"] = { "Herbalism", 70 },
	["Stranglekelp"] = { "Herbalism", 85 },
	["Bruiseweed"] = { "Herbalism", 100 },
	["Wild Steelbloom"] = { "Herbalism", 115 },
	["Grave Moss"] = { "Herbalism", 120 },
	["Kingsblood"] = { "Herbalism", 125 },
	["Liferoot"] = { "Herbalism", 150 },
	["Fadeleaf"] = { "Herbalism", 160 },
	["Goldthorn"] = { "Herbalism", 170 },
	["Khadgar's Whisker"] = { "Herbalism", 185 },
	["Wintersbite"] = { "Herbalism", 195 },
	["Firebloom"] = { "Herbalism", 205 },
	["Purple Lotus"] = { "Herbalism", 210 },
	["Arthas' Tears"] = { "Herbalism", 220 },
	["Sungrass"] = { "Herbalism", 230 },
	["Blindweed"] = { "Herbalism", 235 },
	["Ghost Mushroom"] = { "Herbalism", 245 },
	["Gromsblood"] = { "Herbalism", 250 },
	["Golden Sansam"] = { "Herbalism", 260 },
	["Dreamfoil"] = { "Herbalism", 270 },
	["Mountain Silversage"] = { "Herbalism", 280 },
	["Plaguebloom"] = { "Herbalism", 285 },
	["Icecap"] = { "Herbalism", 290 },
	["Black Lotus"] = { "Herbalism", 300 },
	-- Mining
	["Copper Vein"] = { "Mining", 1 },
	["Tin Vein"] = { "Mining", 65 },
	["Incendicite Mineral Vein"] = { "Mining", 65 },
	["Silver Vein"] = { "Mining", 75 },
	["Lesser Bloodstone Deposit"] = { "Mining", 75 },
	["Iron Deposit"] = { "Mining", 125 },
	["Indurium Mineral Vein"] = { "Mining", 150 },
	["Gold Vein"] = { "Mining", 155 },
	["Mithril Deposit"] = { "Mining", 175 },
	["Ooze Covered Mithril Deposit"] = { "Mining", 175 },
	["Truesilver Deposit"] = { "Mining", 230 },
	["Ooze Covered Truesilver Deposit"] = { "Mining", 230 },
	["Dark Iron Deposit"] = { "Mining", 230 },
	["Small Thorium Vein"] = { "Mining", 245 },
	["Ooze Covered Thorium Vein"] = { "Mining", 245 },
	["Hakkari Thorium Vein"] = { "Mining", 275 },
	["Rich Thorium Vein"] = { "Mining", 275 },
	["Ooze Covered Rich Thorium Vein"] = { "Mining", 275 },
	["Small Obsidian Chunk"] = { "Mining", 305 },
	["Large Obsidian Chunk"] = { "Mining", 305 },
}

local db -- NodeSkillDB.nodes: name -> { profession, level }, learned in game

local function Requirement(name)
	return (db and db.nodes[name]) or SEED[name]
end

-- The player's current rank in a profession, by its displayed name, through
-- whichever of the two skill APIs this client has.
local function SkillRank(profession)
	if GetProfessions and GetProfessionInfo then
		for i = 1, 6 do
			local index = select(i, GetProfessions())
			if index then
				local name, _, rank = GetProfessionInfo(index)
				if name == profession and not IsSecret(rank) then
					return rank
				end
			end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank = GetSkillLineInfo(i)
			if not isHeader and name == profession and not IsSecret(rank) then
				return rank
			end
		end
	end
	return nil
end

------------------------------------------------------------------------------
-- Learning from the world tooltip: "Requires Herbalism (15)"
------------------------------------------------------------------------------

-- A Lua pattern built from the game's own format string, so it matches in
-- every language.
local REQUIRES_PATTERN
do
	local escaped = (ITEM_MIN_SKILL or "Requires %s (%d)"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	REQUIRES_PATTERN = "^" .. escaped:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)") .. "$"
end

local function Learn(name, profession, level)
	if not (name and profession and level) or IsSecret(name) or IsSecret(profession) or IsSecret(level) then
		return
	end
	local known = db.nodes[name]
	if known and known[1] == profession and known[2] == level then
		return
	end
	db.nodes[name] = { profession, level }
end

local function LearnFromTooltip(tooltip)
	local first = _G[tooltip:GetName() .. "TextLeft1"]
	local name = first and first:GetText()
	if not name or IsSecret(name) then
		return
	end
	for i = 2, tooltip:NumLines() do
		local line = _G[tooltip:GetName() .. "TextLeft" .. i]
		local text = line and line:GetText()
		if text and not IsSecret(text) then
			local profession, level = text:match(REQUIRES_PATTERN)
			if profession then
				Learn(name, profession, tonumber(level))
				return
			end
		end
	end
end

------------------------------------------------------------------------------
-- Colouring the minimap tooltip
------------------------------------------------------------------------------

local function ColourMinimapTooltip(tooltip)
	local ranks = {}
	for i = 1, tooltip:NumLines() do
		local line = _G[tooltip:GetName() .. "TextLeft" .. i]
		local text = line and line:GetText()
		if text and not IsSecret(text) then
			local requirement = Requirement(text)
			if requirement then
				local profession, level = requirement[1], requirement[2]
				if ranks[profession] == nil then
					ranks[profession] = SkillRank(profession) or false
				end
				local rank = ranks[profession]
				if rank and rank < level then
					line:SetTextColor(RED[1], RED[2], RED[3])
				end
			end
		end
	end
end

local function IsMinimapTooltip(tooltip)
	local owner = tooltip:GetOwner()
	return owner == Minimap or (owner and owner.GetParent and owner:GetParent() == Minimap)
end

local function Setup()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		local types = Enum.TooltipDataType
		if types.MinimapMouseover then
			TooltipDataProcessor.AddTooltipPostCall(types.MinimapMouseover, ColourMinimapTooltip)
		end
		if types.Object then
			TooltipDataProcessor.AddTooltipPostCall(types.Object, LearnFromTooltip)
		end
		if types.MinimapMouseover and types.Object then
			return
		end
	end
	-- Older tooltip system, or one of the types is missing: look at every
	-- tooltip as it is shown.
	GameTooltip:HookScript("OnShow", function(self)
		if IsMinimapTooltip(self) then
			ColourMinimapTooltip(self)
		else
			LearnFromTooltip(self)
		end
	end)
	GameTooltip:HookScript("OnUpdate", function(self)
		if IsMinimapTooltip(self) then
			ColourMinimapTooltip(self)
		end
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	NodeSkillDB = NodeSkillDB or {}
	db = NodeSkillDB
	db.nodes = db.nodes or {}
	Setup()
end)

SLASH_NODESKILL1 = "/nodeskill"
SlashCmdList.NODESKILL = function()
	local names = {}
	for name in pairs(db.nodes) do
		names[#names + 1] = name
	end
	table.sort(names)
	print(("|cff9999ffNodeSkill|r %d node(s) learned from the game:"):format(#names))
	for _, name in ipairs(names) do
		local requirement = db.nodes[name]
		print(("  %s: %s (%d)"):format(name, requirement[1], requirement[2]))
	end
end
