-- CompactTip: unit tooltips you can read at a glance.
--
-- In a group the game lists every quest once per party member: a title, a
-- name, that member's count, the next name, and so on. Two quests and four
-- players are twelve lines. This folds them into one line per objective
-- with your own count on it, and a line under it for each other player
-- who still needs it, names in one column and counts in the other:
--
--     Deviate Hides                 3/20
--       Intru                      18/20
--       Nausikaa                    0/20
--     Deviate Scale            Intru 1/5
--     Deviate Eradication           done
--
-- An objective only one other player needs stays on one line, with the
-- name before the count.
-- Names are in class colour, in those lines and on a player's own tooltip.
-- A player's tooltip loses what the colour and the game already tell: the
-- class line, the faction line and the "(Player)" after the race, and
-- its guild line is green. Every other line under a unit's name (level,
-- type, faction and the like) is dimmed, so the name is what you see first.
-- The level number keeps a colour: the one the nameplate gives it for how
-- that level compares with yours.
-- A unit flagged for PvP shows its faction crest at the right of its
-- name instead of a "PvP" line of its own.
-- The game's threat line ("9% Threat") is left out.
-- Item and spell tooltips show their ID while Alt is held.
--
-- How: the game hands a tooltip to addons as typed lines before it draws
-- them, and lets a callback swallow a line. The quest lines are swallowed
-- and the folded ones are added in their place. Nothing of the game's is
-- written to. The tooltip of a world object for a quest (a seed to pick
-- up) has the same quest lines and gets the same folding.
-- Tooltip text can be secret in combat; in a tooltip with a
-- secret quest line the quest lines are left exactly as the game made them.

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

-- The colour of a level against yours, by the rule and in the colours of
-- Forever's own nameplates (NameplateLevelFrameMixin:GetDifficultyColor in
-- Blizzard_NamePlates/Camelot). The game's GetCreatureDifficultyColor is the
-- retail rule: it calls four levels below you yellow where the nameplate
-- shows green.
local DIFFICULTY = {
	TRIVIAL = { r = 0.5, g = 0.5, b = 0.5 },
	EASY = { r = 0.25, g = 0.75, b = 0.25 },
	FAIR = { r = 1, g = 0.82, b = 0 },
	DIFFICULT = { r = 1, g = 0.5, b = 0.25 },
	IMPOSSIBLE = { r = 1, g = 0.1, b = 0.1 },
}

local function DifficultyColour(key)
	local colour = _G[key .. "_DIFFICULTY_COLOR"] -- the game's own, when it has them
	if type(colour) == "table" and type(colour.r) == "number" then
		return colour
	end
	return DIFFICULTY[key]
end

-- level: the unit's, or nil for one too far above yours to be shown ("??").
local function LevelColour(level)
	if not level then
		return DifficultyColour("IMPOSSIBLE")
	end
	local mine = (UnitEffectiveLevel or UnitLevel)("player")
	if type(mine) ~= "number" or Secret(mine) then
		return nil
	end
	local difference = level - mine
	local trivial = C_QuestLog and C_QuestLog.GetTrivialRange and C_QuestLog.GetTrivialRange()
	if type(trivial) == "number" and not Secret(trivial) and difference < -trivial then
		return DifficultyColour("TRIVIAL")
	elseif difference <= -3 then
		return DifficultyColour("EASY")
	elseif difference <= 2 then
		return DifficultyColour("FAIR")
	elseif difference <= 4 then
		return DifficultyColour("DIFFICULT")
	end
	return DifficultyColour("IMPOSSIBLE")
end

-- The level line with its number in that colour. nil when the level is not
-- known or is not in the text.
local function LevelColoured(text, unit)
	if not UnitLevel then
		return nil
	end
	local level = UnitLevel(unit)
	if type(level) ~= "number" or Secret(level) then
		return nil
	end
	local colour, from, to
	if level > 0 then
		colour = LevelColour(level)
		from, to = text:find("%f[%d]" .. level .. "%f[%D]")
	else
		colour = LevelColour(nil)
		from, to = text:find("??", 1, true)
	end
	if not (colour and from) then
		return nil
	end
	return text:sub(1, from - 1)
		.. ("|cff%02x%02x%02x%s|r"):format(colour.r * 255, colour.g * 255, colour.b * 255, text:sub(from, to))
		.. text:sub(to + 1)
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
				local labelColour = objective.mine and WHITE or YELLOW
				local function name(entry)
					return Coloured(entry.name:match("^(%S+)") or entry.name, classes[entry.name])
				end
				-- Yours is first in the list, when you still need it.
				local pending = objective.pending
				local own = pending[1].me and pending[1] or nil
				local others = own and #pending - 1 or #pending
				if not own and others == 1 then
					local entry = pending[1]
					folded[#folded + 1] = {
						left = label, right = entry.count and (name(entry) .. " " .. entry.count) or name(entry),
						leftColour = labelColour, rightColour = WHITE,
					}
				else
					-- The objective with your own count, then the others, a
					-- line each: names at the left so they line up, counts
					-- at the right.
					folded[#folded + 1] = { left = label, right = own and own.count or nil, leftColour = labelColour, rightColour = WHITE }
					for n = own and 2 or 1, #pending do
						local entry = pending[n]
						folded[#folded + 1] = { left = "  " .. name(entry), right = entry.count, leftColour = WHITE, rightColour = WHITE }
					end
				end
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
	local coloured = level and LevelColoured(levelText, unit)
	if coloured then
		levelText = coloured
	end
	if level and (isPlayer or kind or coloured) then
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
-- name and quest lines keep their own colours.
local dim = {}
local BRIGHT = { [Types.UnitName or -1] = true, [TITLE] = true, [PLAYER] = true, [OBJECTIVE] = true }

-- The unit a tooltip is about, as a token the unit functions take. The
-- game finds it from the GUID in the tooltip's data (its own
-- TooltipUtil.GetDisplayedUnit does the same), so the tooltip a unit frame
-- asks for ("party1") is known as well as that of a unit under the mouse
-- in the world. When that gives no token, or a secret one, it is taken to
-- be the unit under the mouse.
local function UnitOf(data)
	local guid = data.guid
	if UnitTokenFromGUID and (Secret(guid) or type(guid) == "string") then
		local ok, unit = pcall(UnitTokenFromGUID, guid)
		if ok and not Secret(unit) and type(unit) == "string" then
			return unit
		end
	end
	if UnitExists("mouseover") then
		return "mouseover"
	end
end

-- Folds the quest lines among `lines`: the first is replaced by the folded
-- rows, the rest by nothing.
local function FoldQuests(lines)
	local ok, taken, folded = pcall(function()
		return Fold(lines, Group())
	end)
	if ok and taken then
		for i, line in ipairs(taken) do
			replace[line] = i == 1 and folded or {}
		end
	end
end

-- A world object you gather or click for a quest (seen in game: kind
-- Object, with the same typed quest lines as a unit): its quest lines are
-- folded too. Nothing else about it is changed.
if Enum.TooltipDataType.Object then
	Processor.AddTooltipPreCall(Enum.TooltipDataType.Object, function(tooltip, data)
		replace, dim = {}, {}
		if tooltip ~= GameTooltip or type(data) ~= "table" or type(data.lines) ~= "table" then
			return
		end
		FoldQuests(data.lines)
	end)
end

Processor.AddTooltipPreCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	replace, dim = {}, {}
	crestFor, crestText = nil, nil
	if tooltip ~= GameTooltip or type(data) ~= "table" or type(data.lines) ~= "table" then
		return
	end
	FoldQuests(data.lines)
	local trimmed = {}
	local unit = UnitOf(data)
	if unit then
		local fine, crest = pcall(Trim, data.lines, unit, trimmed)
		if fine then
			for line, rows in pairs(trimmed) do
				replace[line] = rows
			end
			if crest then
				crestFor, crestText = data, crest
			end
		end
	end
	-- The threat line goes. Its type says what it is; its text, which may
	-- be secret, is not read.
	if Types.UnitThreat then
		for _, line in ipairs(data.lines) do
			if line.type == Types.UnitThreat then
				replace[line] = {}
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
	local unit = type(data) == "table" and UnitOf(data)
	if not unit then
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

---------------------------------------------------------------------------
-- Test mode (/compacttip test): the folded quest lines of a made-up party
-- of four, at the end of every unit's tooltip, so the layout can be judged
-- without a group. They go through the same folding as the game's own
-- lines. Off again with the same command, or a reload.
---------------------------------------------------------------------------
local testing = false

local SAMPLE_CLASSES = { Intru = "MAGE", Ambush = "WARRIOR", Nausikaa = "DRUID" }
local SAMPLE_MINE = { Yourself = true }
local function Sample()
	local function line(kind, text, completed)
		return { type = kind, leftText = text, completed = completed or false }
	end
	return {
		-- three of the four still need it
		line(TITLE, "Deviate Hides"),
		line(PLAYER, "Yourself"), line(OBJECTIVE, "3/20 Deviate Hide"),
		line(PLAYER, "Ambush"), line(OBJECTIVE, "20/20 Deviate Hide", true),
		line(PLAYER, "Intru"), line(OBJECTIVE, "18/20 Deviate Hide"),
		line(PLAYER, "Nausikaa"), line(OBJECTIVE, "0/20 Deviate Hide"),
		-- everyone is done
		line(TITLE, "Deviate Eradication"),
		line(PLAYER, "Yourself"), line(OBJECTIVE, "7/7 Deviate Ravager slain", true),
		line(PLAYER, "Intru"), line(OBJECTIVE, "7/7 Deviate Ravager slain", true),
		-- two objectives: one only you need, one only someone else
		line(TITLE, "Serpentbloom"),
		line(PLAYER, "Yourself"), line(OBJECTIVE, "Serpentbloom: 2/10"), line(OBJECTIVE, "Deviate Scale: 5/5", true),
		line(PLAYER, "Intru"), line(OBJECTIVE, "Serpentbloom: 10/10", true), line(OBJECTIVE, "Deviate Scale: 1/5"),
		-- you are done, two others are not
		line(TITLE, "Leaders of the Fang"),
		line(PLAYER, "Yourself"), line(OBJECTIVE, "4/4 Gem", true),
		line(PLAYER, "Ambush"), line(OBJECTIVE, "1/4 Gem"),
		line(PLAYER, "Nausikaa"), line(OBJECTIVE, "2/4 Gem"),
		-- an objective without a count, yours and someone else's
		line(TITLE, "The Glowing Shard"),
		line(PLAYER, "Yourself"), line(OBJECTIVE, "Speak to the hermit"),
		line(PLAYER, "Intru"), line(OBJECTIVE, "Speak to the hermit"),
	}
end

Processor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
	if not testing or tooltip ~= GameTooltip then
		return
	end
	local ok, taken, folded = pcall(Fold, Sample(), SAMPLE_CLASSES, SAMPLE_MINE)
	if not (ok and taken) then
		return
	end
	for _, row in ipairs(folded) do
		local l = row.leftColour
		if row.right then
			local r = row.rightColour
			tooltip:AddDoubleLine(row.left, row.right, l[1], l[2], l[3], r[1], r[2], r[3])
		else
			tooltip:AddLine(row.left, l[1], l[2], l[3])
		end
	end
end)

---------------------------------------------------------------------------
-- /compacttip dump: prints what the game hands over for each tooltip, its
-- kind and every line with its type, to see how a tooltip is made before
-- changing what is done with it. A tooltip is printed once, not again
-- while it stays the same. Secret text is not read.
---------------------------------------------------------------------------
local dumping = false
local dumped

local function NameOf(enum, value)
	for name, v in pairs(enum or {}) do
		if v == value then
			return name
		end
	end
	return "?"
end

Processor.AddTooltipPreCall(Processor.AllTypes, function(tooltip, data)
	if not dumping or tooltip ~= GameTooltip or type(data) ~= "table" or type(data.lines) ~= "table" then
		return
	end
	local out = { ("tooltip kind %s (%s)"):format(tostring(data.type), NameOf(Enum.TooltipDataType, data.type)) }
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if Secret(text) then
			text = "<secret>"
		end
		out[#out + 1] = ("  [%s %s] %s"):format(tostring(line.type), NameOf(Types, line.type), tostring(text))
	end
	local all = table.concat(out, "\n")
	if all == dumped then
		return
	end
	dumped = all
	for _, text in ipairs(out) do
		print(text)
	end
end)

SLASH_COMPACTTIP1 = "/compacttip"
SlashCmdList.COMPACTTIP = function(msg)
	local word = (msg or ""):lower():match("^%s*(%S*)")
	if word == "dump" then
		dumping = not dumping
		dumped = nil
		print("|cff33ff99CompactTip|r: " .. (dumping and "dump on: each tooltip's kind and lines are printed here. /compacttip dump to leave" or "dump off"))
	elseif word == "test" then
		testing = not testing
		if testing then
			print("|cff33ff99CompactTip|r: test mode on: every unit's tooltip ends with the quest lines of a made-up party of four. /compacttip test to leave")
		else
			print("|cff33ff99CompactTip|r: test mode off")
		end
	else
		print("|cff33ff99CompactTip|r: /compacttip test shows sample quest lines in unit tooltips; /compacttip dump prints how each tooltip is made")
	end
end
