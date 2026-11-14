-- ParserRXP.lua: RestedXP guide text -> our step model.
--
-- The model (shared with ParserWoWPro.lua, consumed by Engine.lua):
--
--   step.elements   list of elements, in display order
--   step.points     list of map points (see Maps.lua) with flags
--   step.conds      list of conditions; any one true -> the step is skipped
--   step.sticky     shown beside the following steps, does not block them
--   step.with       index of the step that ends this one (#completewith)
--   step.requires   index of a sticky step that must finish first
--   step.hidden     active but not shown (route-only steps)
--   step.title      header text, when the format gives one
--
--   element.kind    what it is; Engine.lua knows how to test each kind
--   element.obj     true when the step waits for it
--   element.text    display text (may hold "*quest*" for the quest name)
local _, ns = ...

local Text = ns.Text
local Maps = ns.Maps
local trim = Text.trim

local RXP = {}
ns.ParserRXP = RXP

---------------------------------------------------------------------------
-- "<< Horde Warrior/Shaman !Tauren" filters
---------------------------------------------------------------------------
local appliesCache = {}

local function parseFilter(text)
    local p = ns.player
    text = text:gsub("(!?)%(%s*(.-)%s*%)", function(op, inner)
        if parseFilter(inner) ~= (op == "!") then
            return p.class
        end
        return "NULL"
    end)
    local level = UnitLevel("player") or 1
    for alternative in text:gmatch("[^/]+") do
        local all = true
        for entry in alternative:gmatch("!?[%w%d]+") do
            local negate = false
            if entry:sub(1, 1) == "!" then
                entry = entry:sub(2)
                negate = true
            end
            if entry == "Undead" then
                entry = "Scourge"
            end
            local upper = entry:upper()
            local number = tonumber(entry)
            local match = upper == p.class
                or entry == p.race
                or entry == p.faction
                or upper == "FOREVER"
                or entry == p.locale
                or (number ~= nil and level >= number)
                or (upper == "MALE" and UnitSex("player") == 2)
                or (upper == "FEMALE" and UnitSex("player") == 3)
            if match == negate then
                all = false
                break
            end
        end
        if all then
            return true
        end
    end
    return false
end

local function applies(tag)
    if not tag or tag == "" then
        return true
    end
    local known = appliesCache[tag]
    if known == nil then
        known = parseFilter(tag)
        appliesCache[tag] = known
    end
    return known
end
RXP.Applies = applies

---------------------------------------------------------------------------
-- Header: everything before the first step
---------------------------------------------------------------------------
local GAME_TAGS = { "classic", "tbc", "wotlk", "cata", "mop", "df", "retail", "sod" }

function RXP.Header(text)
    local stop = text:find("\n%s*step") or #text
    local h = {}
    for line in text:sub(1, stop):gmatch("[^\r\n]+") do
        line = trim(line:gsub("%-%-.*$", ""))
        if line ~= "" then
            local code, tag = line:match("^(.-)%s*<<%s*(.+)$")
            if tag then
                if code == "" then
                    if not applies(tag) then
                        h.disabled = true
                    end
                    line = ""
                elseif applies(tag) then
                    line = code
                else
                    line = ""
                end
            end
            local key, value = line:match("^#(%S+)%s*(.*)$")
            if key and h[key] == nil then
                h[key] = value
            end
        end
    end
    if not (h.name and h.group) then
        h.disabled = true
    end
    -- A guide tagged for other game versions only is not for us.
    if not h.forever and not h.classic then
        for _, game in ipairs(GAME_TAGS) do
            if h[game] then
                h.disabled = true
            end
        end
    end
    return h
end

---------------------------------------------------------------------------
-- Step commands
---------------------------------------------------------------------------
local lastZone

local function add(step, element)
    step.elements[#step.elements + 1] = element
    return element
end

local function cond(step, c)
    step.conds = step.conds or {}
    step.conds[#step.conds + 1] = c
end

local function note(step, text)
    if text and text ~= "" then
        add(step, { kind = "text", text = text })
    end
end

local function bit1(flags)
    return flags % 2 == 1
end

local function bit2(flags)
    return math.floor(flags / 2) % 2 == 1
end

local function point(zone, x, y)
    if zone then
        lastZone = zone
    else
        zone = lastZone
    end
    x, y = tonumber(x), tonumber(y)
    if not (zone and x and y) then
        return nil
    end
    local map, continent = zone:match("^(.-)/(%d+)$")
    if map then
        -- "map/continent, east-west, north-south" in world yards
        return { map = Maps.Find(map), inst = tonumber(continent), wx = y, wy = x }
    end
    return { map = Maps.Find(zone), x = x, y = y }
end

local function addPoint(step, p)
    if p and p.map then
        step.points = step.points or {}
        step.points[#step.points + 1] = p
    end
    return p
end

local function quests(step, ...)
    local ids = {}
    for i = 1, select("#", ...) do
        local id = tonumber((select(i, ...)))
        if id then
            ids[#ids + 1] = id
        end
    end
    return ids
end

-- An element that completes when something happens in the game (an event),
-- not when a state is reached.
local function latch(name, default)
    return function(step, text)
        add(step, { kind = "latch", on = name, obj = true, text = text or default })
    end
end

local commands = {}

function commands.accept(step, text, id)
    id = tonumber(id)
    if id then
        add(step, { kind = "accept", obj = true, quest = id, text = text or "Accept *quest*" })
    end
end
commands.daily = commands.accept

function commands.turnin(step, text, id)
    id = tonumber(id)
    if id then
        add(step, {
            kind = "turnin", obj = true, quest = math.abs(id), ifOnQuest = id < 0,
            text = text or "Turn in *quest*",
        })
    end
end
commands.dailyturnin = commands.turnin

function commands.complete(step, text, id, objective, atLeast, flags, comment)
    id, objective = tonumber(id), tonumber(objective)
    if not (id and objective) then
        return
    end
    atLeast = tonumber(atLeast)
    if atLeast and atLeast <= 0 then
        atLeast = nil
    end
    local textOnly = bit1(tonumber(flags) or 0)
    add(step, {
        kind = "complete", obj = not textOnly, quest = math.abs(id), ifOnQuest = id < 0,
        objective = objective, atLeast = atLeast, fallback = text or comment,
    })
end

function commands.collect(step, text, id, quantity, quest, objFlags, flags)
    id = tonumber(id and id:match("^%d+"))
    if not id then
        return
    end
    flags = tonumber(flags) or 0
    local textOnly = flags < 0 or bit1(flags)
    add(step, {
        kind = "collect", obj = not textOnly, item = id, count = tonumber(quantity) or 1,
        quest = tonumber(quest), text = text,
        -- No objective flags: the item is only wanted to get the quest.
        forQuest = (tonumber(objFlags) or 0) == 0,
    })
end

commands["goto"] = function(step, text, zone, x, y, radius, optional)
    local p = addPoint(step, point(zone, x, y))
    if not p then
        return
    end
    radius = tonumber(radius)
    if not radius then
        return
    end
    if optional then
        if radius > 0 then
            p.radius, p.route, p.noPin = radius, true, true
        else
            p.low = true
        end
    elseif radius > 0 then
        p.radius = radius
        add(step, { kind = "arrive", obj = true, point = p, text = text })
    elseif radius == 0 then
        p.noArrow = true
    end
end

function commands.waypoint(step, _, zone, x, y, radius)
    local p = addPoint(step, point(zone, x, y))
    if p then
        p.noPin = true
        radius = tonumber(radius)
        if radius and radius ~= 0 then
            p.radius, p.route = math.abs(radius), true
        end
    end
end

function commands.xp(step, text, value, skip)
    local op, level, xp = (value or ""):gsub(" ", ""):match("(<?)(%d+)([%+%.%-]?%d*)")
    level = tonumber(level)
    if not level then
        return
    end
    xp = tonumber(xp)
    skip = tonumber(skip)
    if skip then
        cond(step, { kind = "xp", level = level, xp = xp, below = op == "<" or skip < 0 })
        note(step, text)
    else
        add(step, { kind = "xp", obj = true, level = level, xp = xp, text = text })
    end
end

function commands.maxlevel(step, _, value)
    local level = tonumber((value or ""):match("%d+"))
    if level then
        cond(step, { kind = "above", level = level })
    end
end

function commands.isOnQuest(step, text, ...)
    cond(step, { kind = "onQuest", quests = quests(step, ...), want = true })
    note(step, text)
end

function commands.isNotOnQuest(step, text, ...)
    cond(step, { kind = "onQuest", quests = quests(step, ...), want = false })
    note(step, text)
end

function commands.isQuestComplete(step, text, id)
    cond(step, { kind = "questReady", quest = tonumber(id), want = true })
    note(step, text)
end

function commands.isQuestNotComplete(step, text, id)
    cond(step, { kind = "questReady", quest = tonumber(id), want = false })
    note(step, text)
end

function commands.isQuestTurnedIn(step, text, ...)
    cond(step, { kind = "turnedIn", quests = quests(step, ...), want = true })
    note(step, text)
end

function commands.isQuestAvailable(step, text, ...)
    cond(step, { kind = "turnedIn", quests = quests(step, ...), want = false })
    note(step, text)
end

function commands.zoneskip(step, text, zone, flags)
    local maps = {}
    for name in (zone or ""):gmatch("[^%+/]+") do
        maps[#maps + 1] = Maps.Find(trim(name))
    end
    cond(step, { kind = "inMap", maps = maps, want = not bit1(tonumber(flags) or 0) })
    note(step, text)
end

function commands.subzoneskip(step, text, area, flags)
    cond(step, { kind = "inArea", area = tonumber(area), want = not bit1(tonumber(flags) or 0) })
    note(step, text)
end

function commands.money(step, text, value)
    local amount = tonumber((value or ""):match("(%d+%.?%d*)"))
    if amount then
        cond(step, { kind = "money", copper = amount * 10000, more = value:sub(1, 1) ~= "<" })
    end
    note(step, text)
end

function commands.itemcount(step, text, ids, value)
    local op, eq, total = (value or ""):gsub(" ", ""):match("([<>]?)(=?)(%d+)")
    local items = {}
    for id in (ids or ""):gmatch("%d+") do
        items[#items + 1] = tonumber(id)
    end
    if total and items[1] then
        cond(step, { kind = "items", items = items, total = tonumber(total), op = op, eq = eq == "=" })
    end
    note(step, text)
end

function commands.train(step, text, id, flags)
    id = tonumber(id)
    if not id then
        return note(step, text)
    end
    flags = tonumber(flags) or 0
    local reverse = bit2(flags)
    if bit1(flags) then
        cond(step, { kind = "spell", spell = id, known = not reverse })
        note(step, text)
    else
        add(step, { kind = "train", obj = true, spell = id, known = not reverse, text = text })
    end
end

function commands.skill(step, text, name, value, skip)
    local op, level = (value or ""):gsub(" ", ""):match("(<?)(%d+)")
    level = tonumber(level)
    if level and name and tonumber(skip) then
        cond(step, { kind = "skill", skill = name, level = level, below = op == "<" })
    end
    note(step, text)
end

function commands.bindlocation(step, text, area, flags)
    cond(step, { kind = "bound", area = tonumber(area), want = not bit1(tonumber(flags) or 0) })
    note(step, text)
end

function commands.cooldown(step, text, kind, id, remaining)
    local op, seconds, suffix = (remaining or ""):match("([<>]?)%s*(%d+%p?%d*)%s*([ms]?)")
    seconds = tonumber(seconds) or 0
    if suffix == "m" then
        seconds = seconds * 60
    end
    id = tonumber(id)
    if id and (kind == "item" or kind == "spell") then
        cond(step, { kind = "cooldown", what = kind, id = id, seconds = math.max(seconds, 2), less = op == "<" })
    end
    note(step, text)
end

function commands.aura(step, text, id, duration)
    id = tonumber(id)
    if not id then
        return
    end
    local want = true
    if duration and (duration:find("^<") or duration:find("%-$")) then
        want = false
    end
    if id < 0 then
        id, want = -id, not want
    end
    if text then
        add(step, { kind = "aura", obj = true, spell = id, want = want, text = text })
    else
        cond(step, { kind = "aura", spell = id, want = want })
    end
end

function commands.itemStat(step, text, slot, stat, value)
    slot = tonumber(slot)
    local op, total = (value or ""):gsub(" ", ""):match("([<>]?)(.+)")
    if slot and stat and total then
        cond(step, { kind = "itemStat", slot = slot, stat = stat, op = op, total = tonumber(total) or total })
    end
    note(step, text)
end

function commands.zone(step, text, zone)
    local map = Maps.Find(zone)
    if map then
        add(step, { kind = "zone", obj = true, map = map, text = text or ("Go to " .. zone) })
    else
        note(step, text)
    end
end

function commands.subzone(step, text, area)
    area = tonumber(area)
    if area then
        add(step, { kind = "area", obj = true, area = area, text = text })
    else
        note(step, text)
    end
end

function commands.abandon(step, text, id)
    id = tonumber(id)
    if id then
        add(step, { kind = "abandon", obj = true, quest = id, text = text or "Abandon *quest*" })
    end
end

function commands.destroy(step, text, id)
    id = tonumber(id)
    if id then
        add(step, { kind = "destroy", obj = true, item = id, text = text })
    end
end

function commands.equip(step, text, slot, id)
    slot, id = tonumber(slot), tonumber(id)
    if slot and id then
        add(step, { kind = "equip", obj = true, slot = slot, item = id, text = text })
    end
end

function commands.cast(step, text, id)
    id = tonumber(id)
    if id then
        add(step, { kind = "latch", on = "cast:" .. id, obj = true, spell = id, text = text })
    else
        note(step, text)
    end
end

function commands.fly(step, text, where)
    add(step, { kind = "latch", on = "fly", obj = true, text = text or ("Fly to " .. (where or "")) })
end

function commands.fp(step, text, where, flags)
    flags = tonumber(flags)
    if flags and bit1(flags) then
        return note(step, text)
    end
    add(step, { kind = "latch", on = "fp", obj = true, text = text or ("Get the " .. (where or "") .. " flight path") })
end

commands.hs = latch("hearth", "Use your Hearthstone")
commands.home = latch("bind", "Set your Hearthstone")
commands.vendor = latch("vendor", "Sell junk and resupply")
commands.trainer = latch("trainer", "Train your skills")
commands.stable = latch("stable", "Visit the stable master")
commands.bankdeposit = latch("bank", "Deposit items in your bank")
commands.bankwithdraw = latch("bank", "Withdraw items from your bank")
commands.deathskip = latch("death", "Die and respawn at the graveyard")

function commands.group(step, text, size)
    step.group = true
    size = tonumber(size)
    note(step, text or (size and size > 0 and ("Group quest: bring at least %d players"):format(size)))
end

function commands.solo(step, text)
    step.solo = true
    note(step, text)
end

function commands.dungeon(step, text, name)
    if name and name:sub(1, 1) == "!" then
        note(step, text)
    else
        step.dungeon = true
    end
end

local function names(step, _, ...)
    step.targets = step.targets or {}
    for i = 1, select("#", ...) do
        step.targets[#step.targets + 1] = (select(i, ...))
    end
end
commands.target, commands.mob, commands.unitscan = names, names, names

-- Commands whose only useful part for us is their text.
local function textOnly(step, text)
    note(step, text)
end
for _, name in ipairs({
    "use", "usespell", "link", "macro", "timer", "line", "pin", "loop", "skipgossip",
    "skipgossipid", "gossipoption", "gossip", "addquestitem", "disablecheckbox",
    "clicknext", "showwhiledead", "bronzetube", "blastedLands", "enabledungeon",
    "engrave", "reputation", "xpto60", "openitem", "emote", "vehicle", "buy",
}) do
    commands[name] = textOnly
end

-- Names and links are split on other characters than a comma.
local separators = {
    target = ";", mob = ";", unitscan = ";",
}

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local function parseLine(step, line, comment)
    local tag
    line = line:gsub("%s*<<%s*(.+)$", function(t)
        tag = t
        return ""
    end)
    if tag and not applies(tag) then
        return
    end

    local key, value = line:match("^#(%S+)%s*(.*)$")
    if key then
        if step[key] == nil then
            step[key] = value
        end
        return
    end

    local text
    line = line:gsub("%s*>>%s*(.*)$", function(t)
        if t ~= "" then
            text = Text.RXP(t)
        end
        return ""
    end)

    local command, args = line:match("^%.(%S+)%s*(.*)$")
    if command then
        local handler = commands[command]
        if not handler then
            return note(step, text)
        end
        local list = {}
        if command == "link" then
            list[1] = args
        else
            local separator = separators[command] or ","
            for arg in args:gmatch("[^" .. separator .. "]+") do
                list[#list + 1] = trim(arg)
            end
        end
        if command == "complete" then
            -- The comment usually names the objective ("--Plainstrider Meat (7)").
            return handler(step, text, list[1], list[2], list[3], list[4], comment)
        end
        return handler(step, text, unpack(list))
    end

    local first = line:sub(1, 1)
    if text then
        add(step, { kind = "text", text = text })
    elseif first == "+" then
        add(step, { kind = "manual", obj = true, text = Text.RXP(line:sub(2)) })
    elseif first == "*" then
        add(step, { kind = "text", text = Text.RXP(line:sub(2)) })
    end
end

-- Steps that the player's situation rules out for the whole session.
local function shown(step)
    if step.dungeon then
        return false
    end
    if step.group and not ns.db.group then
        return false
    end
    if step.solo and ns.db.group then
        return false
    end
    -- We play the current phase, on a normal (not hardcore, not seasonal,
    -- not self-found) realm at normal experience rates.
    if step.som or step.hardcore or step.hardcoreserver or step.ssf then
        return false
    end
    if step.season then
        local ok = false
        for season in step.season:gmatch("[^,;%s]+") do
            ok = ok or tonumber(season) == 0
        end
        if not ok then
            return false
        end
    end
    if step.phase then
        local low, high = step.phase:match("(%d+)%-(%d+)")
        low = tonumber(low or step.phase:match("%d+"))
        high = tonumber(high) or 0xffff
        if low and (6 < low or 6 > high) then
            return false
        end
    end
    if step.xprate then
        local op, a, b = step.xprate:match("^([<>]?)%s*(%d+%.?%d*)%-?(%d*%.?%d*)")
        a, b = tonumber(a), tonumber(b)
        if a then
            local low, high = a, b or 0xfff
            if op == "<" then
                low, high = 0, a - 1e-4
            elseif op == ">" then
                low, high = a + 1e-4, 0xfff
            end
            if 1 < low or 1 > high then
                return false
            end
        end
    end
    return true
end

function RXP.Parse(text)
    lastZone = nil
    local steps = {}
    local step
    local skipping = false

    local function close()
        if step and shown(step) then
            steps[#steps + 1] = step
        end
        step = nil
    end

    for line in text:gmatch("[^\r\n]+") do
        local comment
        line = line:gsub("%s*%-%-(.*)$", function(c)
            comment = trim(c)
            return ""
        end)
        line = trim(line)
        if line:sub(1, 4) == "step" then
            close()
            local tag = line:match("<<%s*(.+)$")
            skipping = tag ~= nil and not applies(tag)
            if not skipping then
                step = { elements = {} }
            end
        elseif step and not skipping and line ~= "" then
            parseLine(step, line, comment)
        end
    end
    close()

    -- Link the steps to each other by index.
    local labels = {}
    for i, s in ipairs(steps) do
        if s.label and labels[s.label] == nil then
            labels[s.label] = i
        end
    end
    for i, s in ipairs(steps) do
        if s.completewith then
            s.sticky = true
            if s.completewith == "next" then
                s.with = i + 1
            else
                s.with = labels[s.completewith]
            end
        elseif s.sticky ~= nil then
            s.sticky = true
        end
        if s.requires then
            s.requires = labels[s.requires]
        end
        s.hidden = s.hidewindow ~= nil or nil
        s.loop = s.loop ~= nil or nil
        local level = tonumber(s.level)
        if level then
            cond(s, { kind = "belowLevel", level = level })
        end
    end
    return steps
end
