-- CompactTip: unit tooltips you can read at a glance.
--
-- In a group the game lists every quest once per party member: a title, a
-- name, that member's count, the next name, and so on. Two quests and four
-- players are twelve lines. This folds them into one line per objective
-- that names only the people who still need it:
--
--     Deviate Hides           Intru 18/20
--     Deviate Eradication            done
--
-- Names are in class colour, in those lines and on a player's own tooltip.
-- A player's tooltip loses what the colour and the game already tell: the
-- class line, the faction line and the "(Player)" after the race, and
-- its guild line is green. Every other line under a unit's name (level,
-- type, faction and the like) is dimmed, so the name is what you see first.
-- A unit flagged for PvP shows its faction crest at the right of its
-- name instead of a "PvP" line of its own.
-- Item and spell tooltips show their ID while Alt is held.
--
-- How: the game hands a tooltip to addons as typed lines before it draws
-- them, and lets a callback swallow a line. The quest lines are swallowed
-- and the folded ones are added in their place. Nothing of the game's is
-- written to. Tooltip text can be secret in combat; a tooltip with a
-- secret quest line is left exactly as the game made it.

local Processor = TooltipDataProcessor
local Types = Enum and Enum.TooltipDataLineType
if not (Processor and Processor.AddTooltipPreCall and Processor.AddLinePreCall and Processor.AddLinePostCall and Processor.AllTypes and Types
	and Types.QuestTitle and Types.QuestPlayer and Types.QuestObjective) then
	return
end

local TITLE, PLAYER, OBJECTIVE = Types.QuestTitle, Types.QuestPlayer, Types.QuestObjective

local GREY = { 0.5, 0.5, 0.5 }
local WHITE = { 1, 1, 1 }
local YELLOW = { 1, 0.82, 0 }
local DIM = { 0.7, 0.7, 0.7 } -- secondary lines: readable, but behind the name
local GUILD = { 0.25, 1, 0.25 } -- the green of guild chat
local YOU = "you"
local DONE = "done"

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function Plain(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------------------
-- Who is who: the names of the group, each with its class, and your own.
-- On Forever the second value of UnitName is a surname and the tooltip
-- shows "First Surname", so a name is filed under each way it may be shown.
---------------------------------------------------------------------------
local function Names(unit, into, value)
	local name, extra = UnitName(unit)
	if not name or Secret(name) or Secret(extra) then
		return
	end
	into[name] = value
	if extra and extra ~= "" then
		into[name .. " " .. extra] = value
		into[name .. "-" .. extra] = value
	end
end

local function Group()
	local classes, mine = {}, {}
	Names("player", mine, true)
	local prefix, count = "party", 4
	if IsInRaid and IsInRaid() then
		prefix, count = "raid", 40
	end
	for i = 1, count do
		local unit = prefix .. i
		if UnitExists(unit) then
			local class = UnitClassBase and UnitClassBase(unit)
			if class and not Secret(class) then
				Names(unit, classes, class)
			end
		end
	end
	return classes, mine
end

local function Coloured(text, class)
	local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not colour then
		return text
	end
	return ("|cff%02x%02x%02x%s|r"):format(colour.r * 255, colour.g * 255, colour.b * 255, text)
end

---------------------------------------------------------------------------
-- Folding
---------------------------------------------------------------------------

-- "18/20 Deviate Hide" or "Deviate Hide: 18/20" -> the count and the words.
local function Split(text)
	local count, words = text:match("^(%d+/%d+)%s+(.+)$")
	if not count then
		words, count = text:match("^(.-):?%s+(%d+/%d+)$")
	end
	return count, words or text
end

-- Reads the quest lines of a tooltip. Returns the list of data lines that
-- were read and the folded lines to show for them, or nil when there is
-- nothing to fold or something could not be read.
local function Fold(lines, classes, mine)
	local taken, quests = {}, {}
	local quest, who
	for _, line in ipairs(lines) do
		local kind = line.type
		if kind == TITLE or kind == PLAYER or kind == OBJECTIVE then
			local text = line.leftText
			if Secret(text) or type(text) ~= "string" or Secret(line.completed) then
				return nil
			end
			taken[#taken + 1] = line
			text = Plain(text)
			if kind == TITLE then
				quest = { title = text, objectives = {}, byWords = {} }
				quests[#quests + 1] = quest
				who = nil
			elseif not quest then
				return nil
			elseif kind == PLAYER then
				who = text
			else
				local count, words = Split(text)
				local objective = quest.byWords[words]
				if not objective then
					objective = { words = words, pending = {} }
					quest.byWords[words] = objective
					quest.objectives[#quest.objectives + 1] = objective
				end
				if not line.completed then
					local me = who == nil or mine[who] == true
					local entry = { me = me, name = who, count = count }
					if me then
						table.insert(objective.pending, 1, entry)
						objective.mine = true
					else
						objective.pending[#objective.pending + 1] = entry
					end
				end
			end
		end
	end
	if #quests == 0 then
		return nil
	end

	local folded = {}
	for _, q in ipairs(quests) do
		-- A title with no objective under it is kept as it was.
		if #q.objectives == 0 then
			folded[#folded + 1] = { left = q.title, leftColour = YELLOW }
		end
		for _, objective in ipairs(q.objectives) do
			local label = #q.objectives == 1 and q.title or objective.words
			if #objective.pending == 0 then
				folded[#folded + 1] = { left = label, right = DONE, leftColour = GREY, rightColour = GREY }
			else
				local parts = {}
				for _, entry in ipairs(objective.pending) do
					local name
					if entry.me then
						name = YOU
					else
						name = Coloured(entry.name:match("^(%S+)") or entry.name, classes[entry.name])
					end
					parts[#parts + 1] = entry.count and (name .. " " .. entry.count) or name
				end
				folded[#folded + 1] = {
					left = label,
					right = table.concat(parts, "  "),
					leftColour = objective.mine and WHITE or YELLOW,
					rightColour = WHITE,
				}
			end
		end
	end
	return taken, folded
end

---------------------------------------------------------------------------
-- A unit's own lines
---------------------------------------------------------------------------

-- The crest shown for a unit flagged for PvP, as text the tooltip can
-- draw: the icons Forever's own unit frames use.
local CREST = {
	Horde = "UI-HUD-UnitFrame-SmallCircle-Horde",
	Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}

local function Crest(unit)
	local group = UnitFactionGroup(unit)
	local free = UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit)
	local atlas
	if not Secret(free) and free then
		atlas = CREST.FFA
	elseif not Secret(group) then
		atlas = CREST[group]
	end
	return atlas and ("|A:" .. atlas .. ":16:16|a")
end

-- Finds the lines to change on a unit's tooltip. `into` maps a data line
-- to the rows shown in its place; no rows means the line just goes.
--   any unit: the "PvP" line goes and its faction crest sits at the right
--             of the name instead
--   a mob:    its kind ("Humanoid") joins the level line
--   a player: the guild line turns green with the rank at its right,
--             "(Player)" goes, and so do the
--             class and faction lines
-- Class, faction and PvP lines are only looked for below the level line,
-- so a guild called "Horde" above it stays. A line that cannot be read
-- (secret, in combat) is left as it is, and nothing is dropped whose
-- replacement could not be drawn.
local function Trim(lines, unit, into)
	local isPlayer = UnitIsPlayer(unit)
	if Secret(isPlayer) then
		return
	end
	local class, faction, guild, rank, tag
	if isPlayer then
		class = UnitClass(unit)
		local _
		_, faction = UnitFactionGroup(unit)
		guild, rank = GetGuildInfo(unit)
		if Secret(class) then class = nil end
		if Secret(faction) then faction = nil end
		if Secret(guild) or guild == "" then guild = nil end
		if Secret(rank) or rank == "" then rank = nil end
		-- _G: PLAYER above is the line type.
		local word = _G.PLAYER
		tag = type(word) == "string" and ("(" .. word .. ")")
	end
	local creature
	if not isPlayer then
		creature = UnitCreatureType(unit)
		if Secret(creature) or creature == "" then creature = nil end
	end
	local levelWord = _G.LEVEL
	local pvpWord = _G.PVP_ENABLED or _G.PVP

	local level, levelText, pvp, kind
	for i, line in ipairs(lines) do
		local text = line.leftText
		if i > 1 and not line.rightText and type(text) == "string" and not Secret(text) then
			local plain = Plain(text)
			if level then
				if plain == class or plain == faction then
					into[line] = {}
				elseif pvpWord and plain == pvpWord then
					pvp = line
				elseif not kind and creature and plain == creature then
					kind = line
				end
			else
				local from, to
				if tag then
					from, to = plain:find(tag, 1, true)
				end
				if from then
					level, levelText = line, Plain(plain:sub(1, from - 1) .. plain:sub(to + 1))
				elseif not isPlayer and (line.type == Types.UnitLevel
					or (type(levelWord) == "string" and plain:find(levelWord, 1, true))) then
					level, levelText = line, text
				elseif guild and plain:find(guild, 1, true) == 1 then
					into[line] = { { left = plain, right = rank, leftColour = GUILD, rightColour = DIM } }
				end
			end
		end
	end

	if kind then
		into[kind] = {}
		levelText = levelText .. " " .. creature
	end
	if level and (isPlayer or kind) then
		into[level] = { { left = levelText, leftColour = DIM } }
	end
	-- The crest goes on the name line, which the game has not drawn yet:
	-- it is handed back and put there once the tooltip is built.
	local crest = pvp and GameTooltipTextRight1 and Crest(unit)
	if crest then
		into[pvp] = {}
	end
	return crest
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

-- Filled when a unit tooltip starts, read as its lines go by: a data line
-- that is a key here is swallowed and its rows are added in its place.
-- Keyed by the data lines themselves, so what is left over from another
-- tooltip matches nothing.
local replace = {}

-- The crest waiting to go on the name line of the tooltip built from
-- this data.
local crestFor, crestText

-- The lines to dim once the game has drawn them, keyed the same way. Only
-- the colour is set, the text is not read, so a secret line is fine. The
-- name, the threat line and quest lines keep their own colours.
local dim = {}
local BRIGHT = { [Types.UnitName or -1] = true, [Types.UnitThreat or -1] = true, [TITLE] = true, [PLAYER] = true, [OBJECTIVE] = true }

Processor.AddTooltipPreCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	replace, dim = {}, {}
	crestFor, crestText = nil, nil
	if tooltip ~= GameTooltip or type(data) ~= "table" or type(data.lines) ~= "table" then
		return
	end
	local ok, taken, folded = pcall(function()
		return Fold(data.lines, Group())
	end)
	if ok and taken then
		for i, line in ipairs(taken) do
			replace[line] = i == 1 and folded or {}
		end
	end
	local trimmed = {}
	if UnitExists("mouseover") then
		local fine, crest = pcall(Trim, data.lines, "mouseover", trimmed)
		if fine then
			for line, rows in pairs(trimmed) do
				replace[line] = rows
			end
			if crest then
				crestFor, crestText = data, crest
			end
		end
	end
	for i, line in ipairs(data.lines) do
		if i > 1 and not replace[line] and not BRIGHT[line.type] then
			dim[line] = true
		end
	end
end)

Processor.AddLinePostCall(Processor.AllTypes, function(tooltip, line)
	if tooltip ~= GameTooltip or not dim[line] then
		return
	end
	local text = _G["GameTooltipTextLeft" .. tooltip:NumLines()]
	if text then
		text:SetTextColor(DIM[1], DIM[2], DIM[3])
	end
end)

Processor.AddLinePreCall(Processor.AllTypes, function(tooltip, line)
	local rows = tooltip == GameTooltip and replace[line]
	if not rows then
		return
	end
	for _, row in ipairs(rows) do
		local l = row.leftColour
		if row.right then
			local r = row.rightColour
			tooltip:AddDoubleLine(row.left, row.right, l[1], l[2], l[3], r[1], r[2], r[3])
		else
			tooltip:AddLine(row.left, l[1], l[2], l[3])
		end
	end
	return true
end)

-- The name line, once the tooltip is built: the PvP crest at its right,
-- and a player's name in class colour. The name itself is not read or
-- rewritten, so a secret name is fine.
Processor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	if tooltip ~= GameTooltip or not GameTooltipTextLeft1 then
		return
	end
	if crestText and crestFor == data and GameTooltipTextRight1 then
		GameTooltipTextRight1:SetText(crestText)
		GameTooltipTextRight1:Show()
	end
	crestFor, crestText = nil, nil
	local unit = "mouseover"
	if not UnitExists(unit) then
		return
	end
	local isPlayer = UnitIsPlayer(unit)
	if Secret(isPlayer) or not isPlayer then
		return
	end
	local class = UnitClassBase and UnitClassBase(unit)
	if not class or Secret(class) then
		return
	end
	local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if colour then
		GameTooltipTextLeft1:SetTextColor(colour.r, colour.g, colour.b)
	end
end)

---------------------------------------------------------------------------
-- Item and spell IDs, while Alt is held. An aura's tooltip shows the ID
-- of its spell. The line is added when the tooltip is drawn, so hold Alt
-- and then point; a secret ID (combat) is skipped.
---------------------------------------------------------------------------
local function IDLine(label)
	return function(tooltip, data)
		if not IsAltKeyDown() or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
			return
		end
		local id = type(data) == "table" and data.id
		if Secret(id) or type(id) ~= "number" then
			return
		end
		tooltip:AddDoubleLine(label, tostring(id), GREY[1], GREY[2], GREY[3], 1, 1, 1)
	end
end

Processor.AddTooltipPostCall(Enum.TooltipDataType.Item, IDLine("Item ID"))
Processor.AddTooltipPostCall(Enum.TooltipDataType.Spell, IDLine("Spell ID"))
if Enum.TooltipDataType.UnitAura then
	Processor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, IDLine("Spell ID"))
end
