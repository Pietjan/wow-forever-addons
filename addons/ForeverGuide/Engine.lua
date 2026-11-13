-- Engine.lua: which steps of the guide are current, and what they show.
--
-- Progress is a set of finished step numbers. On every refresh the steps
-- are walked from the first unfinished one:
--   * a step whose conditions rule it out is passed over (RestedXP: for
--     good; WoW-Pro: until the conditions change),
--   * a sticky step joins the active list and the walk goes on,
--   * the first ordinary step with something left to do is the main step
--     and ends the walk.
-- The result is Engine.view (what the tracker draws), Engine.nav (where
-- the arrow and the map pin go) and Engine.quests (what to track).
local _, ns = ...

local State = ns.State
local Maps = ns.Maps
local Registry = ns.Registry

local Engine = { view = { blocks = {} }, quests = {}, arrivals = {} }
ns.Engine = Engine

local guide, steps, prog

local floor, min = math.floor, math.min

---------------------------------------------------------------------------
-- Element tests: is this part of a step done?
---------------------------------------------------------------------------
local function check(el, fn)
    local list = el.quests
    if not list then
        return fn(el.quest)
    end
    if el.all then
        for i = 1, #list do
            if not fn(list[i]) then
                return false
            end
        end
        return true
    end
    for i = 1, #list do
        if fn(list[i]) then
            return true
        end
    end
    return false
end

local function itemsDone(items)
    for i = 1, #items do
        if State.ItemCount(items[i][1]) < items[i][2] then
            return false
        end
    end
    return true
end

local function zoneTexts()
    return (GetZoneText() or ""):lower(), (GetSubZoneText() or ""):lower(), (GetMinimapZoneText() or ""):lower()
end

local function inArea(areaID)
    local name = areaID and C_Map.GetAreaInfo(areaID)
    if not name then
        return false
    end
    name = name:lower()
    local zone, sub, mini = zoneTexts()
    return name == zone or name == sub or name == mini
end

local tests = {}

-- A quest that is left out (State.Passed) counts as done in every step
-- that is about it.
local function acceptedOrPassed(quest)
    return State.Accepted(quest) or State.Passed(quest)
end

local function turnedInOrPassed(quest)
    return State.TurnedIn(quest) or State.Passed(quest)
end

function tests.accept(el)
    return check(el, acceptedOrPassed)
end

function tests.turnin(el)
    if check(el, turnedInOrPassed) then
        return true
    end
    return el.ifOnQuest and not check(el, State.OnQuest) or false
end

function tests.complete(el)
    local function one(quest)
        if State.Passed(quest) then
            return true
        end
        if el.objectives then
            for i = 1, #el.objectives do
                if not State.ObjectiveDone(quest, el.objectives[i]) then
                    return false
                end
            end
            return true
        elseif el.objective then
            return State.ObjectiveDone(quest, el.objective, el.atLeast)
        end
        return State.TurnedIn(quest) or State.ReadyToTurnIn(quest) or State.Passed(quest)
    end
    if check(el, one) then
        return true
    end
    if el.items and itemsDone(el.items) then
        return true
    end
    return el.ifOnQuest and not check(el, State.OnQuest) or false
end

function tests.collect(el)
    if el.quest and turnedInOrPassed(el.quest) then
        return true
    end
    if el.items then
        return itemsDone(el.items)
    end
    return State.ItemCount(el.item) >= el.count
end

function tests.xp(el)
    return State.Reached(el.level, el.xp)
end

function tests.train(el)
    return State.KnowsSpell(el.spell) == el.known
end

function tests.zone(el)
    return C_Map.GetBestMapForUnit("player") == el.map
end

function tests.area(el)
    return inArea(el.area)
end

function tests.place(el)
    local zone, sub, mini = zoneTexts()
    for _, name in pairs(el.names) do
        if name == zone or name == sub or name == mini then
            return true
        end
    end
    return false
end

function tests.abandon(el)
    return not State.OnQuest(el.quest)
end

function tests.destroy(el)
    return State.ItemCount(el.item) == 0
end

function tests.equip(el)
    return GetInventoryItemID("player", el.slot) == el.item
end

function tests.aura(el)
    return State.HasAura(el.spell) == el.want
end

---------------------------------------------------------------------------
-- Conditions: true means "leave this step out"
---------------------------------------------------------------------------
local conds = {}

local function anyQuest(list, fn)
    for i = 1, #list do
        if fn(list[i]) then
            return true
        end
    end
    return false
end

local function allQuests(list, fn)
    for i = 1, #list do
        if not fn(list[i]) then
            return false
        end
    end
    return true
end

function conds.xp(c)
    return State.Reached(c.level, c.xp) == not c.below
end

function conds.above(c)
    return UnitLevel("player") > c.level
end

function conds.belowLevel(c)
    return UnitLevel("player") < c.level
end

function conds.onQuest(c)
    return anyQuest(c.quests, State.OnQuest) ~= c.want
end

function conds.questReady(c)
    return State.ReadyToTurnIn(c.quest) ~= c.want
end

function conds.turnedIn(c)
    if c.want then
        return not anyQuest(c.quests, State.TurnedIn)
    end
    return allQuests(c.quests, State.TurnedIn)
end

function conds.inMap(c)
    local map = C_Map.GetBestMapForUnit("player")
    if not map then
        return false
    end
    local found = false
    for i = 1, #c.maps do
        found = found or c.maps[i] == map
    end
    return found == c.want
end

function conds.inArea(c)
    return inArea(c.area) == c.want
end

function conds.money(c)
    if GetMoney() >= c.copper then
        return c.more
    end
    return not c.more
end

function conds.items(c)
    local count = 0
    for i = 1, #c.items do
        count = count + State.ItemCount(c.items[i])
    end
    local ok = (c.eq and count == c.total)
        or (c.op == ">" and count > c.total)
        or (c.op == "<" and count < c.total)
        or (c.op == "" and not c.eq and count >= c.total)
    return not ok
end

function conds.spell(c)
    return State.KnowsSpell(c.spell) == c.known
end

function conds.skill(c)
    local rank = State.Skill(c.skill)
    if not rank then
        return false
    end
    return (rank >= c.level) == not c.below
end

function conds.bound(c)
    local name = c.area and C_Map.GetAreaInfo(c.area)
    if not name then
        return false
    end
    return (name == GetBindLocation()) == c.want
end

function conds.cooldown(c)
    local left = State.CooldownLeft(c.what, c.id)
    if not left then
        return false
    end
    if c.less then
        return left < c.seconds
    end
    return left > c.seconds
end

function conds.aura(c)
    local has = State.HasAura(c.spell)
    if has == nil then
        return false
    end
    return has == c.want
end

function conds.itemStat(c)
    local stat
    if c.stat == "QUALITY" then
        stat = GetInventoryItemQuality and GetInventoryItemQuality("player", c.slot)
    else
        local link = GetInventoryItemLink("player", c.slot)
        if link and c.stat == "LEVEL" then
            stat = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
        elseif link then
            local stats = C_Item.GetItemStats and C_Item.GetItemStats(link)
            stat = stats and stats[c.stat]
        end
    end
    if type(stat) ~= "number" or type(c.total) ~= "number" then
        return false
    end
    stat = floor(stat * 10 + 0.5) / 10
    local ok = (c.op == ">" and c.total < stat) or (c.op == "<" and c.total > stat) or (c.op == "" and c.total == stat)
    return not ok
end

-- WoW-Pro
function conds.allTurnedIn(c)
    return allQuests(c.quests, State.TurnedIn)
end

function conds.pre(c)
    if c.all then
        return not allQuests(c.quests, State.TurnedIn)
    end
    return not anyQuest(c.quests, State.TurnedIn)
end

local function available(quest)
    return not State.TurnedIn(quest) and not State.OnQuest(quest)
end

function conds.available(c)
    if c.all then
        return not allQuests(c.quests, available)
    end
    return not anyQuest(c.quests, available)
end

local function inLog(quest)
    if quest < 0 then
        return not State.OnQuest(-quest)
    end
    return State.OnQuest(quest)
end

function conds.active(c)
    if c.all then
        return not allQuests(c.quests, inLog)
    end
    return not anyQuest(c.quests, inLog)
end

function conds.lead(c)
    return anyQuest(c.quests, State.Accepted)
end

function conds.optional(c)
    if c.item then
        return State.ItemCount(c.item) == 0
    end
    if c.quests then
        return not anyQuest(c.quests, State.OnQuest)
    end
    return true
end

function conds.inZone(c)
    local zone, sub, mini = zoneTexts()
    local map = C_Map.GetBestMapForUnit("player")
    local found = false
    for i = 1, #c.zones do
        local z = c.zones[i]
        if z.name and (z.name == zone or z.name == sub or z.name == mini) then
            found = true
        elseif z.id and (z.id == map or inArea(z.id)) then
            found = true
        end
    end
    return found == c.want
end

function conds.taxi(c)
    return State.KnowsTaxi(c.name) == c.want
end

local function skipped(step)
    local list = step.conds
    if list then
        for i = 1, #list do
            local c = list[i]
            local test = conds[c.kind]
            if test and test(c) then
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local function elementDone(index, j, el)
    if prog.latch[index * 100 + j] then
        return true
    end
    local test = tests[el.kind]
    return test and test(el) or false
end

local function hasObjectives(step)
    for _, el in ipairs(step.elements) do
        if el.obj then
            return true
        end
    end
    return false
end

local function complete(index, step)
    for j, el in ipairs(step.elements) do
        if el.obj and not elementDone(index, j, el) then
            return false
        end
    end
    return true
end

-- A step that only takes the character somewhere.
local TRAVEL = { arrive = true, zone = true, area = true, place = true }

local function isTravel(step)
    if step.travel == nil then
        local any, travel = false, true
        for _, el in ipairs(step.elements) do
            if el.obj then
                any = true
                if not (TRAVEL[el.kind] or (el.kind == "latch" and (el.on == "fly" or el.on == "hearth"))) then
                    travel = false
                end
            end
        end
        step.travel = any and travel
    end
    return step.travel
end

-- Is travel step `index` a trip to work that is finished already? It is
-- when the steps between it and the next trip all are; a trip that is
-- followed by another trip goes by what that one leads to.
local function pointless(index)
    local found = false
    for j = index + 1, #steps do
        local step = steps[j]
        if step.sticky or not hasObjectives(step) then
            -- rides along, or only talks: says nothing about the trip
        elseif isTravel(step) then
            if found then
                return true
            end
        elseif prog.done[j] or complete(j, step) then
            found = true
        elseif skipped(step) then
            -- RestedXP drops such a step for good. WoW-Pro may bring it
            -- back, so there it neither proves nor disproves the trip.
            found = found or guide.format == "rxp"
        else
            return false
        end
    end
    return found
end

local function markDone(index, quiet)
    if prog.done[index] then
        return
    end
    prog.done[index] = true
    if not quiet then
        local hist = prog.hist
        hist[#hist + 1] = index
        if #hist > 40 then
            table.remove(hist, 1)
        end
    end
end

---------------------------------------------------------------------------
-- What the tracker shows
---------------------------------------------------------------------------
local LABELS = {
    accept = "New quest", turnin = "Turn in", collect = "Collect", arrive = "Travel",
    zone = "Travel", area = "Travel", place = "Travel", xp = "Level up", train = "Training",
    manual = "Guide", abandon = "Abandon quest", destroy = "Clean up", equip = "Equip", aura = "Buff",
    fly = "Flight master", fp = "Flight path", hearth = "Hearthstone", bind = "Innkeeper",
    vendor = "Vendor", trainer = "Trainer", stable = "Stable master", bank = "Bank",
    death = "Spirit healer", cast = "Cast",
}
local NAMED = { accept = true, turnin = true, fly = true, fp = true, bind = true, vendor = true,
    trainer = true, stable = true, bank = true, train = true }

local function questName(id)
    return State.QuestTitle(id) or ("quest " .. id)
end

local function firstQuest(el)
    if el.quests then
        for i = 1, #el.quests do
            if State.OnQuest(el.quests[i]) then
                return el.quests[i]
            end
        end
        return el.quests[1]
    end
    return el.quest
end

local function title(index, step)
    if step.title then
        return step.title
    end
    for _, el in ipairs(step.elements) do
        if el.obj then
            local kind = el.kind == "latch" and (el.on:match("^cast") and "cast" or el.on) or el.kind
            if kind == "complete" then
                return questName(firstQuest(el))
            end
            local target = step.targets and step.targets[1]
            if target and NAMED[kind] then
                return (target:gsub("::%d+", ""))
            end
            return LABELS[kind] or "Guide"
        end
    end
    local target = step.targets and step.targets[1]
    if target then
        return (target:gsub("::%d+", ""))
    end
    return step.sticky and "On the way" or "Guide"
end

local DEFAULTS = {
    arrive = "Go to the marked location", zone = "Travel to the zone", area = "Travel to the area",
    manual = "Continue", destroy = "Destroy the item", equip = "Equip the item", aura = "Get the buff",
}

-- A quest objective as the game words it, without its count ("3/8 Feather"
-- or "Feather: 3/8" becomes "Feather").
local function withoutCount(text)
    local bare = text:gsub("^%s*%d+/%d+%s+", "")
    bare = bare:gsub("%s*:?%s*%d+/%d+%s*$", "")
    return bare ~= "" and bare or text
end

local function addLines(lines, index, j, el, step)
    local key = "e" .. j
    local done = el.obj and elementDone(index, j, el) or false
    local kind = el.kind
    local text = el.text
    local dynamic = false

    if kind == "accept" or kind == "turnin" or kind == "abandon" then
        if text and text:find("*quest*", 1, true) then
            local name = questName(firstQuest(el))
            text = text:gsub("%*quest%*", function() return name end)
        end
    elseif kind == "complete" then
        local quest = firstQuest(el)
        local objectives = State.Objectives(quest)
        if objectives and #objectives > 0 then
            local wanted = el.objectives or (el.objective and { el.objective })
            local shownAny = false
            for n, o in ipairs(objectives) do
                local use = not wanted
                if wanted then
                    for _, w in ipairs(wanted) do
                        use = use or w == n
                    end
                end
                if use and o.text and o.text ~= "" then
                    -- The guide tracks the quests of its steps, so the count is
                    -- right below in the Quests section, kept current by the
                    -- game. It stays here when that section does not show it:
                    -- watching is off, or the guide sets a lower target.
                    local line = o.text
                    local plain = ns.db.watches and not el.atLeast
                    if plain then
                        line = withoutCount(line)
                    end
                    -- `plain`: says nothing the Quests section does not (see buildBlock).
                    lines[#lines + 1] = { key = key .. "." .. n, text = line, done = done or o.finished or false, obj = el.obj, plain = plain or nil }
                    shownAny = true
                end
            end
            if shownAny then
                return
            end
        end
        text = el.fallback or text or questName(quest)
    elseif kind == "collect" then
        local items = el.items or { { el.item, el.count } }
        for n, item in ipairs(items) do
            local have = State.ItemCount(item[1])
            local name = State.ItemName(item[1]) or "item"
            local line = ("%d/%d %s"):format(min(have, item[2]), item[2], name)
            if text and n == 1 and not step.titleIsObjective then
                line = ("%s (%d/%d)"):format(text, min(have, item[2]), item[2])
            end
            lines[#lines + 1] = { key = key .. "." .. n, text = line, done = done or have >= item[2], obj = el.obj }
        end
        return
    elseif kind == "xp" then
        if not text then
            text = ("Reach level %d"):format(el.level)
            if el.xp and el.xp < 0 then
                text = ("Get within %d experience of level %d"):format(-el.xp, el.level)
            end
            dynamic = true
        end
    elseif kind == "train" then
        if not text then
            text = "Train " .. (State.SpellName(el.spell) or "the new ability")
        end
    end

    text = text or DEFAULTS[kind]
    if not text or text == "" then
        return
    end
    -- A WoW-Pro step is named after its objective; do not say it twice.
    if step.titleIsObjective and el.obj and not dynamic and kind ~= "text" then
        return
    end
    lines[#lines + 1] = { key = key, text = text, done = done, obj = el.obj }
end

local function buildBlock(index, isMain)
    local step = steps[index]
    if step.hidden then
        return nil
    end
    local block = { id = index, main = isMain, lines = {}, title = title(index, step) }
    -- "Talk to Grull Hawkwind" under the header "Grull Hawkwind" says nothing.
    local echo = "talk to " .. block.title:lower()
    for j, el in ipairs(step.elements) do
        local plain = el.kind == "text" and el.text and ns.Text.Plain(el.text):lower():gsub("%.$", "")
        if plain ~= echo then
            addLines(block.lines, index, j, el, step)
        end
    end
    -- A step that says what to do in words needs no bare objective names
    -- under it: those, with their counts, are in the Quests section. A step
    -- without words keeps them, or it would be a title and nothing else.
    local worded = false
    for _, line in ipairs(block.lines) do
        if not line.obj and line.text and line.text ~= "" then
            worded = true
            break
        end
    end
    if worded then
        for i = #block.lines, 1, -1 do
            if block.lines[i].plain then
                table.remove(block.lines, i)
            end
        end
    end
    return block
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function emptyView(titleText, line)
    Engine.view = { blocks = { { id = 0, placeholder = true, title = titleText, lines = { { key = "e1", text = line } } } } }
    Engine.shown = {}
    Engine.nav = nil
    Engine.quests = {}
    Engine.arrivals = {}
end

local refreshing = false

local INSTANCES = { party = true, raid = true, pvp = true, arena = true, scenario = true }

local function inInstance()
    if not IsInInstance then
        return false
    end
    local inside, kind = IsInInstance()
    return inside and INSTANCES[kind] or false
end

local refresh

-- A mistake in one guide step must not freeze the guide: report it once
-- and carry on at the next refresh.
local reported = {}
function Engine:Refresh()
    if refreshing or not ns.char then
        return
    end
    local ok, err = pcall(refresh)
    refreshing = false
    if not ok and not reported[err] then
        reported[err] = true
        ns.Print("problem in this guide step: " .. tostring(err))
    end
end

function refresh()
    if not guide then
        emptyView("Leveling guide", "Click to choose a guide")
        Engine.view.name = "Guide"
        Engine.signature = nil
        ns.Fire("Updated")
        return
    end
    -- Paused, by hand or by walking into a dungeon: the guide keeps its
    -- place and leaves the tracker, the quest watches, the arrow and the
    -- pin alone.
    local inside = inInstance()
    if not inside then
        Engine.override = nil
    end
    local why = ns.char.paused and "paused"
        or (inside and ns.db.pauseInDungeon and not Engine.override and "instance")
    if why then
        if Engine.signature ~= why then
            emptyView("Paused", why == "paused" and "Click to continue" or "Continues when you leave. Click to continue now")
            Engine.view.name = guide.name
            Engine.view.paused = true
            Engine.signature = why
            ns.Fire("Updated")
        end
        return
    end
    refreshing = true

    local done = prog.done
    local count = #steps
    local active = {}
    local main

    while prog.base <= count and done[prog.base] do
        prog.base = prog.base + 1
    end

    for index = prog.base, count do
        if not done[index] then
            local step = steps[index]
            if skipped(step) then
                if guide.format == "rxp" then
                    markDone(index, true)
                end
            elseif step.sticky then
                local finished
                if step.with then
                    finished = done[step.with] or (hasObjectives(step) and complete(index, step))
                elseif guide.format == "rxp" and step.completewith and not hasObjectives(step) then
                    finished = true
                else
                    finished = complete(index, step)
                end
                if finished then
                    markDone(index)
                else
                    active[#active + 1] = index
                end
            elseif complete(index, step) then
                markDone(index)
            elseif isTravel(step) and pointless(index) then
                markDone(index, true)
            else
                main = index
                break
            end
        end
    end

    -- Sticky steps that end together with a step that just finished.
    for n = #active, 1, -1 do
        local step = steps[active[n]]
        if step.with and done[step.with] then
            markDone(active[n])
            table.remove(active, n)
        end
    end
    while prog.base <= count and done[prog.base] do
        prog.base = prog.base + 1
    end

    -- A step may wait for a sticky step before it.
    local blocked = false
    if main then
        local need = steps[main].requires
        if need and need < main and not done[need] then
            for _, index in ipairs(active) do
                blocked = blocked or index == need
            end
        end
    end

    if not main and #active == 0 then
        return Engine:Finished()
    end

    local view = { blocks = {}, name = guide.name, step = main or count, count = count }
    local quests, arrivals = {}, {}
    local shown = {}
    if main and not blocked then
        shown[#shown + 1] = main
    end
    for _, index in ipairs(active) do
        shown[#shown + 1] = index
    end

    local nav
    for n, index in ipairs(shown) do
        local step = steps[index]
        local block = buildBlock(index, index == main)
        if block then
            view.blocks[#view.blocks + 1] = block
        end
        for j, el in ipairs(step.elements) do
            if el.kind == "turnin" or el.kind == "complete" or (el.kind == "collect" and el.quest) then
                if el.quests then
                    for _, quest in ipairs(el.quests) do
                        quests[quest] = true
                    end
                elseif el.quest then
                    quests[el.quest] = true
                end
            end
            if el.point and el.obj and not elementDone(index, j, el) then
                arrivals[#arrivals + 1] = { point = el.point, key = index * 100 + j }
            end
        end
        if step.points and (not nav or (nav.step ~= main and index == main)) then
            nav = { points = step.points, loop = step.loop, step = index, title = block and block.title or title(index, step) }
        end
    end
    if #view.blocks == 0 then
        view.blocks[1] = { id = 0, title = "On the way", lines = { { key = "e1", text = "Follow the arrow" } } }
    end

    Engine.view = view
    Engine.shown = shown
    Engine.nav = nav
    Engine.quests = quests
    Engine.arrivals = arrivals
    refreshing = false

    -- Tell the others only when something they show has changed.
    local parts = { view.name, view.step }
    for _, block in ipairs(view.blocks) do
        parts[#parts + 1] = block.id
        parts[#parts + 1] = block.title
        for _, line in ipairs(block.lines) do
            parts[#parts + 1] = line.done and "x" or "-"
            parts[#parts + 1] = line.text
        end
    end
    local sum = 0
    for quest in pairs(quests) do
        sum = sum + quest
    end
    parts[#parts + 1] = sum
    parts[#parts + 1] = nav and tostring(nav.points) or ""
    local signature = table.concat(parts, "\031")
    if signature ~= Engine.signature then
        Engine.signature = signature
        ns.Fire("Updated")
    end
end

function Engine:Finished()
    local finished = guide
    ns.Fire("Finished", finished)
    local nextGuide = Registry.Next(finished)
    if nextGuide and ns.db.autoNext then
        ns.Print(("%s is done. Next: %s"):format(finished.name, nextGuide.name))
        C_Timer.After(0, function()
            Engine:Start(nextGuide.key)
        end)
        return
    end
    emptyView("Guide complete", nextGuide and ("Click for " .. nextGuide.name) or "Click to choose another")
    Engine.view.name = finished.name
    Engine.view.finished = true
    Engine.view.nextKey = nextGuide and nextGuide.key
    Engine.signature = nil
    ns.Fire("Updated")
end

local pending = false

function Engine:Queue()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        Engine:Refresh()
    end)
end

---------------------------------------------------------------------------
-- Starting and steering
---------------------------------------------------------------------------
local function parse(g)
    if g.format == "rxp" then
        return ns.ParserRXP.Parse(g.text)
    end
    g.map = g.map or Maps.Find(g.zone)
    return ns.ParserWoWPro.Parse(g)
end

-- On a first start, pass over everything before the first quest step that
-- is still open, so a character that is already under way lands in place.
local function fastForward()
    for index, step in ipairs(steps) do
        if not skipped(step) then
            for _, el in ipairs(step.elements) do
                local kind = el.kind
                if el.obj and (kind == "accept" or kind == "turnin" or kind == "complete") and not tests[kind](el) then
                    return index
                end
            end
        end
    end
    return #steps + 1
end

function Engine:Start(key, restart)
    local g = Registry.Get(key)
    if not g then
        return false
    end
    local ok, result = pcall(parse, g)
    if not ok or type(result) ~= "table" then
        ns.Print("could not read the guide " .. g.name .. ": " .. tostring(result))
        return false
    end
    guide, steps = g, result
    Engine.steps = steps
    if ns.char.guide ~= key or restart then
        ns.char.paused = nil
    end
    ns.char.guide = key

    local signature = ("%s:%d:%s"):format(tostring(g.signature or 0), #steps, ns.db.group and "g" or "s")
    prog = ns.char.progress[key]
    if restart or not prog or prog.signature ~= signature then
        prog = { done = {}, latch = {}, hist = {}, base = 1, signature = signature }
        ns.char.progress[key] = prog
        local first = fastForward()
        for index = 1, first - 1 do
            prog.done[index] = true
        end
        prog.base = first
    end
    prog.hist = prog.hist or {}
    Engine.guide = guide
    Engine:Refresh()
    return true
end

function Engine:Stop()
    guide, steps, prog = nil, nil, nil
    Engine.guide = nil
    ns.char.guide = nil
    ns.char.paused = nil
    Engine:Refresh()
end

-- Set the guide aside for a dungeon or some questing with friends. What
-- was done meanwhile is seen when it continues.
function Engine:Pause()
    if guide and not ns.char.paused then
        ns.char.paused = true
        Engine:Refresh()
    end
end

function Engine:Resume()
    if guide and Engine.view.paused then
        if not ns.char.paused then
            -- Paused by the dungeon: carry on in here until we leave.
            Engine.override = true
        end
        ns.char.paused = nil
        Engine:Refresh()
    end
end

function Engine:Paused()
    return guide ~= nil and (ns.char.paused == true or Engine.view.paused == true)
end

-- Every quest a step that is still to come has to do with.
function Engine:RemainingQuests()
    local out = {}
    if not guide or Engine.view.finished then
        return out
    end
    for index = prog.base, #steps do
        if not prog.done[index] then
            for _, el in ipairs(steps[index].elements) do
                if el.quest then
                    out[math.abs(el.quest)] = true
                end
                for _, quest in ipairs(el.quests or {}) do
                    out[math.abs(quest)] = true
                end
            end
        end
    end
    return out
end

-- Do the current steps ask to accept ("accept") or hand in ("turnin")
-- this quest?
function Engine:Wants(kind, quest)
    if not guide or not quest or Engine.view.paused then
        return false
    end
    for _, index in ipairs(Engine.shown or {}) do
        for _, el in ipairs(steps[index].elements) do
            if el.kind == kind then
                if el.quest == quest then
                    return true
                end
                for _, other in ipairs(el.quests or {}) do
                    if other == quest then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Engine:Current()
    return guide
end

-- Finish a step by hand (the check button on its block).
function Engine:CompleteStep(index)
    if guide and steps[index] then
        markDone(index)
        Engine:Refresh()
    end
end

-- Reopen the step that was finished last.
function Engine:Back()
    if not guide then
        return
    end
    local index = table.remove(prog.hist)
    if not index then
        -- Nothing remembered: step back to the previous step in the guide.
        index = (Engine.view.step or prog.base) - 1
        while index >= 1 and steps[index].hidden do
            index = index - 1
        end
    end
    if index < 1 then
        return
    end
    prog.done[index] = nil
    for j = 1, #steps[index].elements do
        prog.latch[index * 100 + j] = nil
    end
    prog.base = min(prog.base, index)
    Engine:Refresh()
end

-- An element that waits for something to happen.
function Engine:LatchKey(key)
    if prog and not prog.latch[key] then
        prog.latch[key] = true
        Engine:Queue()
    end
end

function Engine:Latch(name)
    if not guide then
        return
    end
    local hit = false
    local function try(index)
        for j, el in ipairs(steps[index].elements) do
            if el.kind == "latch" and el.on == name and not prog.latch[index * 100 + j] then
                prog.latch[index * 100 + j] = true
                hit = true
            end
        end
    end
    for _, block in ipairs(Engine.view.blocks) do
        if block.id > 0 then
            try(block.id)
        end
    end
    if hit then
        Engine:Queue()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function queue()
    Engine:Queue()
end

for _, event in ipairs({
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "BAG_UPDATE_DELAYED",
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
    "PLAYER_MONEY", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "QUEST_DATA_LOAD_RESULT",
    "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "HEARTHSTONE_BOUND",
}) do
    ns.On(event, queue)
end

local function latcher(name)
    return function()
        Engine:Latch(name)
    end
end

ns.On("HEARTHSTONE_BOUND", latcher("bind"))
ns.On("MERCHANT_CLOSED", latcher("vendor"))
ns.On("TRAINER_CLOSED", latcher("trainer"))
ns.On("PET_STABLE_CLOSED", latcher("stable"))
ns.On("BANKFRAME_CLOSED", latcher("bank"))
ns.On("PLAYER_UNGHOST", latcher("death"))
ns.On("TAXIMAP_OPENED", latcher("fp"))
ns.On("UI_INFO_MESSAGE", function(_, _, message)
    if message == ERR_NEWTAXIPATH then
        Engine:Latch("fp")
    end
end)
ns.On("PLAYER_CONTROL_LOST", function()
    C_Timer.After(1, function()
        if UnitOnTaxi("player") then
            Engine:Latch("fly")
        end
    end)
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if unit ~= "player" or type(spellID) ~= "number" then
        return
    end
    if issecretvalue and issecretvalue(spellID) then
        return
    end
    if spellID == 8690 or spellID == 556 then
        Engine:Latch("hearth")
    end
    Engine:Latch("cast:" .. spellID)
end)

-- Cooldowns and buffs have no cheap event; look again now and then.
C_Timer.NewTicker(3, function()
    if guide and ns.Quiet() then
        Engine:Queue()
    end
end)

ns.Listen("Setting", function(key)
    if key == "group" and guide then
        Engine:Start(guide.key)
    elseif key == "skipLow" or key == "pauseInDungeon" then
        Engine:Queue()
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    if not Engine.started then
        Engine.started = true
        if not (ns.char.guide and Engine:Start(ns.char.guide)) then
            ns.char.guide = nil
            Engine:Refresh()
        end
    else
        Engine:Queue()
    end
end)
