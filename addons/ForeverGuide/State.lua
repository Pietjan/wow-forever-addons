-- State.lua: questions about the character that guide steps ask.
local _, ns = ...

local State = {}
ns.State = State

local QL = C_QuestLog

function State.OnQuest(id)
    return QL.IsOnQuest(id)
end

function State.TurnedIn(id)
    return QL.IsQuestFlaggedCompleted(id)
end

function State.Accepted(id)
    return QL.IsOnQuest(id) or QL.IsQuestFlaggedCompleted(id)
end

-- In the log with every objective done.
function State.ReadyToTurnIn(id)
    return QL.IsOnQuest(id) and (QL.IsComplete(id) or false)
end

function State.Objectives(id)
    if not QL.IsOnQuest(id) then
        return nil
    end
    return QL.GetQuestObjectives(id)
end

-- Is objective `index` of the quest done? `atLeast` lowers the bar ("kill
-- 4 of the 10 here"). A quest that is turned in or complete counts.
function State.ObjectiveDone(id, index, atLeast)
    if QL.IsQuestFlaggedCompleted(id) then
        return true
    end
    if not QL.IsOnQuest(id) then
        return false
    end
    if QL.IsComplete(id) then
        return true
    end
    local objectives = QL.GetQuestObjectives(id)
    local o = objectives and index and objectives[index]
    if not o then
        return false
    end
    if o.finished then
        return true
    end
    if atLeast and o.numFulfilled and o.numFulfilled >= atLeast then
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Quests that are not worth doing any more
---------------------------------------------------------------------------
-- The level of a quest and what it needs first come from QuestieDB, when
-- that is installed; the game itself only knows the level of quests that
-- are in the log.
local levels, needs = {}, {}

local function field(name, id)
    local db = _G.QuestDB
    local get = db and db[name]
    if not get then
        return nil
    end
    local ok, value = pcall(get, id)
    return ok and value or nil
end

-- The quest's level, or false when it is unknown or the quest must not be
-- judged by it (class quests teach abilities whatever their level).
local function questLevel(id)
    local level = levels[id]
    if level == nil then
        if not _G.QuestDB then
            return false
        end
        level = field("questLevel", id)
        if type(level) ~= "number" or level <= 0 then
            level = false
        elseif (field("requiredClasses", id) or 0) ~= 0 then
            level = false
        end
        levels[id] = level
    end
    return level
end

local function trivialRange()
    local range = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")
        or GetQuestGreenRange and GetQuestGreenRange()
    if type(range) == "number" then
        return range
    end
    local level = UnitLevel("player")
    return level < 6 and 4 or math.min(5 + math.floor(level / 10), 12)
end

-- Grey in the quest log: it pays next to no experience.
function State.Trivial(id)
    local level = questLevel(id)
    return level and UnitLevel("player") - level > trivialRange() or false
end

local function prerequisites(id)
    local need = needs[id]
    if need == nil then
        if not _G.QuestDB then
            return { any = false, all = false }
        end
        local any, all = field("preQuestSingle", id), field("preQuestGroup", id)
        need = {
            any = type(any) == "table" and #any > 0 and any or false,
            all = type(all) == "table" and #all > 0 and all or false,
        }
        needs[id] = need
    end
    return need
end

-- What the quest needs first: { any = list or false, all = list or false }.
function State.Needs(id)
    return prerequisites(id)
end

-- Can the quest be accepted as far as what it needs first goes? True when
-- QuestieDB is not there to say.
function State.CanAccept(id)
    local need = prerequisites(id)
    if need.all then
        for i = 1, #need.all do
            if not QL.IsQuestFlaggedCompleted(need.all[i]) then
                return false
            end
        end
    end
    if need.any then
        for i = 1, #need.any do
            if QL.IsQuestFlaggedCompleted(need.any[i]) then
                return true
            end
        end
        return false
    end
    return true
end

-- Is this a quest the guide should leave out: one the character never
-- took and that is grey by now, or one that can only follow such a quest?
-- A quest that is in the log is always carried through.
function State.Passed(id, depth)
    if not (ns.db and ns.db.skipLow) then
        return false
    end
    if QL.IsOnQuest(id) or QL.IsQuestFlaggedCompleted(id) then
        return false
    end
    if State.Trivial(id) then
        return true
    end
    depth = depth or 0
    if depth > 8 then
        return false
    end
    local need = prerequisites(id)
    if need.all then
        for i = 1, #need.all do
            if State.Passed(need.all[i], depth + 1) then
                return true
            end
        end
    end
    if need.any then
        for i = 1, #need.any do
            if not State.Passed(need.any[i], depth + 1) then
                return false
            end
        end
        return true
    end
    return false
end

local titleRequested = {}

function State.QuestTitle(id)
    local title = QL.GetTitleForQuestID(id)
    if not title and not titleRequested[id] and QL.RequestLoadQuestByID then
        titleRequested[id] = true
        QL.RequestLoadQuestByID(id)
    end
    return title
end

local itemCount = C_Item and C_Item.GetItemCount or GetItemCount

function State.ItemCount(id)
    return itemCount(id) or 0
end

local itemRequested = {}

function State.ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if not name and not itemRequested[id] then
        itemRequested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    return name
end

function State.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

-- Hunter pet abilities: a guide names either the spell the hunter knows
-- (Beast Training) or the one the pet casts, and wants that exact rank. A
-- hunter who can teach that rank or a higher one has it covered, whichever
-- pet is out. petRanks[id] lists the hunter's spells that cover `id`.
local petRanks

local function coveringRanks(id)
    if not petRanks then
        petRanks = {}
        for _, ranks in ipairs(ns.PET_RANKS) do
            for rank, pair in ipairs(ranks) do
                local covering = {}
                for higher = rank, #ranks do
                    covering[#covering + 1] = ranks[higher][1]
                end
                petRanks[pair[1]], petRanks[pair[2]] = covering, covering
            end
        end
    end
    return petRanks[id]
end

local function knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then
        return true
    end
    if IsSpellKnown and IsSpellKnown(id) then
        return true
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then
        return true
    end
    return false
end

function State.KnowsSpell(id)
    if knows(id) then
        return true
    end
    local covering = coveringRanks(id)
    if covering then
        for _, spell in ipairs(covering) do
            if knows(spell) then
                return true
            end
        end
    end
    return false
end

-- Has the character reached `level`, or a point relative to it?
--   xp nil/0      the level itself
--   xp < 0        within -xp experience of it
--   0 < xp < 1    that fraction into the level
--   xp >= 1       that much experience into the level
function State.Reached(level, xp)
    local current = UnitLevel("player")
    if not level then
        return false
    end
    xp = xp or 0
    if current > level then
        return true
    end
    local have, max = UnitXP("player"), UnitXPMax("player")
    if xp < 0 then
        return current >= level or (current == level - 1 and have >= max + xp)
    elseif xp >= 1 then
        return current == level and have >= xp
    elseif xp > 0 then
        return current == level and have >= max * xp
    end
    return current >= level
end

-- Profession and secondary skill ranks, by the short names RestedXP uses.
local SKILL_NAMES = {
    riding = "Riding", firstaid = "First Aid", cooking = "Cooking", fishing = "Fishing",
    mining = "Mining", herbalism = "Herbalism", skinning = "Skinning",
    alchemy = "Alchemy", blacksmithing = "Blacksmithing", enchanting = "Enchanting",
    engineering = "Engineering", leatherworking = "Leatherworking", tailoring = "Tailoring",
}

-- Their skill lines in the game's tables (SkillLine); a profession can also
-- have a line of its own under that one, so both are looked at.
local SKILL_IDS = {
    riding = 762, firstaid = 129, cooking = 185, fishing = 356, mining = 186, herbalism = 182,
    skinning = 393, alchemy = 171, blacksmithing = 164, enchanting = 333, engineering = 202,
    leatherworking = 165, tailoring = 197,
}

-- Returns nil when the rank cannot be read on this client.
function State.Skill(name)
    local key = name:lower():gsub("%s", "")
    local wanted = (SKILL_NAMES[key] or name):lower()
    local id = SKILL_IDS[key]
    local info = C_SkillInfo
    if info and info.GetNumSkillLines and info.GetSkillLineInfo then
        local best = 0
        local function look(line)
            if type(line) == "table" and not line.isHeader and type(line.rank) == "number"
                and ((id and (line.skillID == id or line.parentSkillLineID == id))
                    or (type(line.name) == "string" and line.name:lower() == wanted)) then
                best = math.max(best, line.rank)
            end
        end
        if id and info.GetSkillLineInfoByID then
            look(info.GetSkillLineInfoByID(id)) -- also found under a folded header
        end
        for i = 1, info.GetNumSkillLines() do
            look(info.GetSkillLineInfo(i))
        end
        return best
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, rank = GetSkillLineInfo(i)
            if skillName and not isHeader and skillName:lower() == wanted then
                return rank
            end
        end
        return 0
    end
    return nil
end

function State.HasAura(spellID)
    -- Auras are hidden in combat; do not even ask.
    if not ns.Quiet() or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return nil
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then
        return nil
    end
    return aura ~= nil
end

-- Seconds left on an item or spell cooldown; nil when it cannot be read
-- (the numbers are secret in combat).
function State.CooldownLeft(kind, id)
    if not ns.Quiet() then
        return nil
    end
    local ok, start, duration = pcall(function()
        if kind == "item" then
            local s, d = C_Item.GetItemCooldown(id)
            return s, d
        elseif kind == "spell" then
            local info = C_Spell.GetSpellCooldown(id)
            return info and info.startTime, info and info.duration
        end
    end)
    if not ok or type(start) ~= "number" or type(duration) ~= "number" then
        return nil
    end
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
        return nil
    end
    if duration == 0 then
        return 0
    end
    local ok2, left = pcall(function()
        return math.max(0, start + duration - GetTime())
    end)
    return ok2 and left or nil
end

-- Known flight points, remembered whenever the flight map is open. Used
-- by guide steps that differ for players who can already fly somewhere.
function State.KnowsTaxi(name)
    local known = ns.char and ns.char.taxi
    if not known then
        return false
    end
    name = name:lower()
    for node in pairs(known) do
        if node:find(name, 1, true) then
            return true
        end
    end
    return false
end

ns.On("TAXIMAP_OPENED", function()
    if not (ns.char and NumTaxiNodes and TaxiNodeName) then
        return
    end
    ns.char.taxi = ns.char.taxi or {}
    for i = 1, NumTaxiNodes() do
        local kind = TaxiNodeGetType and TaxiNodeGetType(i)
        local name = TaxiNodeName(i)
        if name and kind ~= "DISTANT" and kind ~= "NONE" then
            ns.char.taxi[name:lower()] = true
        end
    end
end)
