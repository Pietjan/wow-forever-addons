-- Creatures: what targeting or pointing at one shows, out of combat: its
-- name, level range, classification ("elite", "rare"...), type and family as
-- the game names them, and how it takes your side's players; where the
-- game keeps which creature it is secret inside an instance, by its name
-- in that instance instead. Positions are not taken here: the creature may
-- be far off. Loot, vendor and quest windows place what you stand next to.

local _, ns = ...

local REACTION = { [1] = "hostile", [2] = "hostile", [3] = "hostile", [4] = "neutral", [5] = "friendly", [6] = "friendly", [7] = "friendly", [8] = "friendly" }
local SIDE = { Alliance = "a", Horde = "h" }

-- Instance is the map ID of the instance the player is in, nil outside one
-- or when the game does not say.
local function Instance()
	local ok, _, kind, _, _, _, _, _, instance = pcall(GetInstanceInfo)
	instance = ok and ns.Plain(instance)
	if instance and kind ~= "none" then
		return instance
	end
	return nil
end

-- Fill takes into c what the game shows of unit.
local function Fill(c, unit)
	local level = ns.Read("level", UnitLevel, unit)
	if level and level > 0 then
		c.min = math.min(c.min or level, level)
		c.max = math.max(c.max or level, level)
	end
	c.class = ns.Read("classification", UnitClassification, unit) or c.class
	c.type = ns.Read("creature type", UnitCreatureType, unit) or c.type
	c.family = ns.Read("creature family", UnitCreatureFamily, unit) or c.family
	local side = SIDE[ns.Read("faction", UnitFactionGroup, "player") or ""]
	local reaction = REACTION[ns.Read("reaction", UnitReaction, unit, "player") or 0]
	if side and reaction then
		c[side] = reaction
	end
end

function ns.ReadCreature(unit)
	if ns.Fighting() then
		return
	end
	-- Only a creature: not a player or a pet, and not when the game will not
	-- say which it is (a secret answer is no answer).
	if not ns.Read("exists", UnitExists, unit) or ns.Read("player controlled", UnitPlayerControlled, unit) ~= false
		or ns.Read("player", UnitIsPlayer, unit) ~= false then
		return
	end
	local guid = ns.Read("creature", UnitGUID, unit)
	if guid == nil then
		-- The game keeps which creature it is from addons here (an
		-- instance's map can): filed by its name in the instance instead.
		local instance, name = Instance(), ns.Read("creature name", UnitName, unit)
		if instance and type(name) == "string" and name ~= "" then
			local key = "i" .. instance
			local named = ns.db.named[key] or {}
			ns.db.named[key] = named
			named[name] = named[name] or {}
			Fill(named[name], unit)
		end
		return
	end
	local _, kind, id = ns.Key(guid)
	if kind ~= "npc" then
		return
	end
	local c = ns.db.creatures[id] or {}
	ns.db.creatures[id] = c
	c.name = ns.Read("creature name", UnitName, unit) or c.name
	Fill(c, unit)
end

ns.On("PLAYER_TARGET_CHANGED", function()
	ns.ReadCreature("target")
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function()
	ns.ReadCreature("mouseover")
end)
