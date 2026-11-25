-- Creatures: what targeting or pointing at one shows, out of combat: its
-- name, level range, classification ("elite", "rare"...), type and family as
-- the game names them, and how it takes your side's players. Positions
-- are not taken here: the creature may be far off. Loot, vendor and quest
-- windows place what you stand next to.

local _, ns = ...

local REACTION = { [1] = "hostile", [2] = "hostile", [3] = "hostile", [4] = "neutral", [5] = "friendly", [6] = "friendly", [7] = "friendly", [8] = "friendly" }
local SIDE = { Alliance = "a", Horde = "h" }

function ns.ReadCreature(unit)
	if ns.Fighting() then
		return
	end
	-- Only a creature: not a player or a pet, and not when the game will not
	-- say which it is (a secret answer is no answer).
	if not ns.Read("exists", UnitExists, unit) or ns.Read("player controlled", UnitPlayerControlled, unit) ~= false then
		return
	end
	local _, kind, id = ns.Key(ns.Read("creature", UnitGUID, unit))
	if kind ~= "npc" then
		return
	end
	local c = ns.db.creatures[id] or {}
	ns.db.creatures[id] = c
	c.name = ns.Read("creature name", UnitName, unit) or c.name
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

ns.On("PLAYER_TARGET_CHANGED", function()
	ns.ReadCreature("target")
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function()
	ns.ReadCreature("mouseover")
end)
