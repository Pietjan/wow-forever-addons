-- ParserWoWPro.lua: WoW-Pro guide text -> our step model (see ParserRXP.lua).
--
-- A WoW-Pro step is one line: an action letter, a name, then |TAG|value|
-- pairs: "A The Hunt Begins|QID|747|M|44.46,77.53|Z|1412; Mulgore|N|From Grull.|"
local _, ns = ...

local Text = ns.Text
local Maps = ns.Maps
local trim = Text.trim

local WP = {}
ns.ParserWoWPro = WP

-- Tags without a value; every other known tag takes the next field.
local FLAGS = {}
for flag in ("O CC CS CN CHAT EAB ELITE I H NC NA NOCACHE NOAUTO RARE DUNGEON V AP FAIL RUNE US S S!US CT MS TOF"):gmatch("%S+") do
    FLAGS[flag] = true
end
local VALUES = {}
for tag in ("QID MID PRE AVAILABLE LEAD ACTIVE NPC CCOUNT ERROR M Z TZ IZ L QO SO ITEM EQUIPPED QG T U ACH BUFF BUILDING COV DATE DFREN EX FLY GROUP GUIDE ILVL JUMP LVL P PET REN REP RECIPE SPELL TAXI TWWREN HOA DEAD PET1 PET2 PET3 SELECT STRATEGY SWITCH C FACTION GEN N R RANK"):gmatch("%S+") do
    VALUES[tag] = true
end

local TITLES = {
    A = "Accept: %s", a = "Accept: %s", T = "Turn in: %s", t = "Turn in: %s",
    C = "%s", K = "Kill: %s", R = "Go to %s", H = "Hearth to %s", h = "Set your home: %s",
    F = "Fly to %s", f = "Flight path: %s", b = "Travel to %s", P = "Portal to %s",
    B = "Buy: %s", U = "Use: %s", l = "Loot: %s", ["*"] = "Destroy: %s",
}

local RACES = { undead = "scourge", nightelf = "nightelf" }

-- "Warlock,Rogue" / "-Druid": does the list allow `mine`?
local function allows(list, mine, alias)
    mine = mine:lower()
    local positive, hit, banned = false, false, false
    for entry in list:gmatch("[^,;&%^]+") do
        entry = trim(entry):lower():gsub("%s", "")
        local negate = entry:sub(1, 1) == "-" or entry:sub(1, 1) == "!"
        if negate then
            entry = entry:sub(2)
        end
        entry = alias and alias[entry] or entry
        if negate then
            banned = banned or entry == mine
        else
            positive = true
            hit = hit or entry == mine
        end
    end
    if banned then
        return false
    end
    return hit or not positive
end

-- "12^34" (any) or "12&34" (all) -> { ids = {12, 34}, all = bool }
local function questList(value)
    local list = { ids = {}, all = value:find("&", 1, true) ~= nil }
    for id in value:gmatch("%-?%d+") do
        list.ids[#list.ids + 1] = tonumber(id)
    end
    return list.ids[1] and list or nil
end

local function cond(step, c)
    step.conds = step.conds or {}
    step.conds[#step.conds + 1] = c
end

local function add(step, element)
    step.elements[#step.elements + 1] = element
    return element
end

-- "4755" or "4742 10" or "1 2;3 4" -> { {item, count}, ... }
local function itemList(value)
    local items = {}
    for entry in value:gmatch("[^;]+") do
        local id, count = entry:match("(%d+)%s*(%d*)")
        if id then
            items[#items + 1] = { tonumber(id), tonumber(count) or 1 }
        end
    end
    return items[1] and items or nil
end

local function parseLine(line, guide)
    local fields = { strsplit("|", line) }
    local first = fields[1]
    if #first < 3 or first:sub(2, 2) ~= " " then
        return nil
    end
    local action = first:sub(1, 1)
    local name = Text.WoWPro(first:sub(3))
    local t = {}
    local i = 2
    while i <= #fields do
        local tag = trim(fields[i])
        if FLAGS[tag] then
            t[tag] = true
        elseif VALUES[tag] then
            i = i + 1
            t[tag] = fields[i] and trim(fields[i]) or ""
        elseif tag:sub(1, 1) == ";" then
            break
        end
        i = i + 1
    end

    -- Steps that are not for this character at all.
    local p = ns.player
    if t.C and not allows(t.C, p.class) then
        return nil
    end
    if t.R and not allows(t.R, p.race, RACES) then
        return nil
    end
    if t.FACTION and (t.FACTION == "Alliance" or t.FACTION == "Horde") and t.FACTION ~= p.faction then
        return nil
    end
    if t.DUNGEON or t.P or (tonumber(t.RANK) or 0) > 2 then
        return nil
    end
    if t.GROUP and not ns.db.group then
        return nil
    end

    local step = { elements = {} }
    step.title = (TITLES[action] or "%s"):format(name)
    if t.ELITE then
        step.title = step.title .. " (Elite)"
    end
    if t.S or t["S!US"] then
        step.sticky = true
    end

    -- Where.
    local last
    if t.M and t.M ~= "PLAYER" then
        local map = Maps.Find(t.Z ~= "" and t.Z or nil) or guide.map
        if map then
            step.points = {}
            for x, y in t.M:gmatch("(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)") do
                last = { map = map, x = tonumber(x), y = tonumber(y) }
                step.points[#step.points + 1] = last
            end
            for index = 1, #step.points - 1 do
                local p2 = step.points[index]
                p2.radius, p2.route, p2.noPin = 20, true, true
            end
            if not last then
                step.points = nil
            end
        end
    end

    -- What finishes it.
    local quests = t.QID and questList(t.QID)
    local items = t.L and itemList(t.L)
    local objective
    if action == "A" or action == "a" then
        if quests then
            objective = add(step, { kind = "accept", obj = true, quests = quests.ids, all = quests.all })
        end
    elseif action == "T" or action == "t" then
        if quests then
            objective = add(step, {
                kind = "turnin", obj = true, quests = quests.ids, all = quests.all, ifOnQuest = action == "t",
            })
        end
    elseif (action == "C" or action == "K") and quests then
        local objectives
        if t.QO then
            objectives = {}
            for index in t.QO:gmatch("%d+") do
                objectives[#objectives + 1] = tonumber(index)
            end
            if not t.QO:match("^[%d;%s]+$") then
                objectives = nil
            end
        end
        objective = add(step, {
            kind = "complete", obj = true, quests = quests.ids, all = quests.all,
            objectives = objectives, items = items,
        })
    elseif action == "L" and t.LVL then
        -- "3;-500" is 500 experience short of finishing level 3.
        local level, offset = t.LVL:match("^%-?(%d+);?(%-?%d*)")
        level, offset = tonumber(level), tonumber(offset)
        if level then
            if offset and offset < 0 then
                level = level + 1
            end
            objective = add(step, { kind = "xp", obj = true, level = level, xp = offset })
        end
    elseif items then
        objective = add(step, { kind = "collect", obj = true, items = items })
    elseif action == "R" or action == "F" or action == "b" or action == "H" or action == "P" then
        objective = add(step, {
            kind = "place", obj = true, names = { name:lower(), t.TZ and t.TZ:lower() or nil },
            point = (action == "R" and not t.CN) and last or nil,
        })
        if last and action == "R" then
            last.radius = 25
        end
    elseif action == "h" then
        objective = add(step, { kind = "latch", on = "bind", obj = true })
    elseif action == "f" then
        objective = add(step, { kind = "latch", on = "fp", obj = true })
    elseif action == "r" then
        objective = add(step, { kind = "latch", on = "vendor", obj = true })
    elseif action == "=" and name:lower():find("train") then
        objective = add(step, { kind = "latch", on = "trainer", obj = true })
    end
    if not objective then
        if (t.CC or t.CS) and last then
            last.radius = last.radius or 15
            objective = add(step, { kind = "arrive", obj = true, point = last })
        else
            objective = add(step, { kind = "manual", obj = true })
        end
    end
    -- The objective line reads as the step's own name unless the game has
    -- better text for it (quest objectives).
    objective.text = objective.text or name
    step.titleIsObjective = true

    if t.N and t.N ~= "" then
        add(step, { kind = "text", text = Text.WoWPro(t.N) })
    end
    if t.T and t.T ~= "" then
        step.targets = { (strsplit(";", t.T)) }
    end

    -- When it is skipped.
    if quests and action ~= "A" and action ~= "a" and action ~= "T" and action ~= "t" and objective.kind ~= "complete" then
        cond(step, { kind = "allTurnedIn", quests = quests.ids })
    end
    if t.PRE then
        local list = questList(t.PRE)
        if list then
            cond(step, { kind = "pre", quests = list.ids, all = not t.PRE:find("^", 1, true) })
        end
    end
    if t.AVAILABLE then
        local list = questList(t.AVAILABLE)
        if list then
            cond(step, { kind = "available", quests = list.ids, all = list.all })
        end
    end
    if t.ACTIVE then
        local list = questList(t.ACTIVE)
        if list then
            cond(step, { kind = "active", quests = list.ids, all = list.all })
        end
    end
    if t.LEAD then
        local list = questList(t.LEAD)
        if list then
            cond(step, { kind = "lead", quests = list.ids })
        end
    end
    if t.O then
        local item = tonumber(t.U and t.U:match("%d+")) or (items and items[1][1])
        cond(step, { kind = "optional", item = item, quests = quests and quests.ids })
    end
    if t.LVL and action ~= "L" then
        local level = tonumber(t.LVL:match("^%-?%d+"))
        if level and level > 0 then
            cond(step, { kind = "belowLevel", level = level })
        elseif level and level < 0 then
            cond(step, { kind = "above", level = -level - 1 })
        end
    end
    if t.IZ and t.IZ ~= "" then
        local value, flip = t.IZ, false
        if value:sub(1, 1) == "-" then
            value, flip = value:sub(2), true
        end
        local zones = {}
        for entry in value:gmatch("[^%^]+") do
            local id, zoneName = entry:match("^%s*%-?(%d+)%s*;?%s*(.-)%s*$")
            if id then
                zones[#zones + 1] = { id = tonumber(id), name = zoneName ~= "" and zoneName:lower() or nil }
            else
                for part in entry:gmatch("[^;]+") do
                    zones[#zones + 1] = { name = trim(part):gsub("^%-", ""):lower() }
                end
            end
        end
        cond(step, { kind = "inZone", zones = zones, want = flip })
    end
    if t.TAXI and t.TAXI ~= "" then
        local negate = t.TAXI:sub(1, 1) == "-"
        cond(step, { kind = "taxi", name = negate and t.TAXI:sub(2) or t.TAXI, want = negate })
    end
    if t.SPELL then
        local id, flip = t.SPELL:match(";(%d+);?(.*)$")
        if id then
            cond(step, { kind = "spell", spell = tonumber(id), known = flip ~= nil and flip ~= "" and flip ~= "0" })
        end
    end
    return step
end

function WP.Parse(guide)
    local text = guide.source()
    local steps = {}
    for line in text:gmatch("[^\r\n]+") do
        line = trim(line)
        if line ~= "" and line:sub(1, 1) ~= ";" then
            local step = parseLine(line, guide)
            if step then
                steps[#steps + 1] = step
            end
        end
    end
    return steps
end
