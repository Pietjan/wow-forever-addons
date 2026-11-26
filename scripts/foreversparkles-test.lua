-- Offline checks for ForeverSparkles: the game's API stood in for, the
-- addon's files loaded as the game does, its events fired, and whether a
-- herb, ore vein or quest object gets a sparkle checked by the plate the
-- sparkle frame hangs on. Covers the herb/ore Sparkle setting (Automatic,
-- Enabled, Disabled), the profession check behind Automatic, the move from
-- the old checkbox, and the dropdown on the options page.
--   lua5.1 scripts/foreversparkles-test.lua
local dir = "addons/ForeverSparkles/"
local failures, checks = 0, 0

local function check(name, ok, detail)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		io.write("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "") .. "\n")
	end
end

-- The game -------------------------------------------------------------------

function print() end
SlashCmdList = {}
local fighting = false
function InCombatLockdown() return fighting end
C_Timer = { After = function(_, fn) fn() end }

local cvars, cvarAsks = {}, 0
C_CVar = {
	GetCVar = function(name)
		cvarAsks = cvarAsks + 1
		return cvars[name] or "0"
	end,
	SetCVar = function(name, value)
		cvars[name] = tostring(value)
	end,
}

-- Frames and textures: every method nobody needs does nothing.
local frames = {}
local function Object()
	local o = { events = {}, scripts = {} }
	return setmetatable(o, { __index = function(_, key)
		return function() end
	end })
end
local function NewFrame()
	local f = Object()
	f.RegisterEvent = function(self, e) self.events[e] = true end
	f.UnregisterEvent = function(self, e) self.events[e] = nil end
	f.SetScript = function(self, what, fn) self.scripts[what] = fn end
	f.SetParent = function(self, parent) self.parent = parent end
	f.SetPoint = function(self, _, relative, _, x, y) self.anchor, self.x, self.y = relative, x, y end
	f.Show = function(self) self.shown = true end
	f.Hide = function(self) self.shown = false end
	f.CreateTexture = function()
		local t = Object()
		t.SetTexture = function(self, file) self.file = file end
		t.GetTexture = function(self) return self.file end
		return t
	end
	frames[#frames + 1] = f
	return f
end
function CreateFrame() return NewFrame() end
UIParent = NewFrame()

local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

-- What is under the interact key: a game object with this cursor, or nothing.
local cursor
local name -- of the thing under the interact key
function UnitName() return name end
local plate = NewFrame()
function UnitExists() return cursor ~= nil end
function UnitIsGameObject() return cursor ~= nil end
function SetUnitCursorTexture(texture)
	if not cursor then return false end
	texture.file = cursor
	return true
end
local questObject = false
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return questObject end }
C_NamePlate = {
	GetNamePlateForUnit = function() if cursor then return plate end end,
	GetNamePlates = function() return {} end,
}

-- The character's skill lines, as C_SkillInfo gives them.
local skills, skillAsks = {}, 0
C_SkillInfo = {
	GetNumSkillLines = function() skillAsks = skillAsks + 1 return #skills end,
	GetSkillLineInfo = function(i) return skills[i] end,
	GetSkillLineInfoByID = function(id)
		skillAsks = skillAsks + 1
		for _, line in ipairs(skills) do
			if line.skillID == id then return line end
		end
	end,
}
local function learn(...)
	skills = { { name = "Professions", isHeader = true } }
	local lines = {
		herbalism = { name = "Herbalism", skillID = 182, rank = 1 },
		mining = { name = "Mining", skillID = 186, rank = 1 },
		tailoring = { name = "Tailoring", skillID = 197, rank = 1 },
	}
	for _, name in ipairs({ ... }) do
		skills[#skills + 1] = lines[name]
	end
	fire("SKILL_LINES_CHANGED")
end

-- The options window: what each control was made with.
local settings = {}
local function Setting(id, getter, setter)
	local s = { id = id, get = getter, set = setter }
	settings[id] = s
	return s
end
Settings = {
	VarType = { Boolean = "boolean", Number = "number", String = "string" },
	RegisterVerticalLayoutCategory = function(name) return { name = name } end,
	RegisterVerticalLayoutSubcategory = function(_, name) return { name = name } end,
	RegisterProxySetting = function(_, id, _, _, _, getter, setter) return Setting(id, getter, setter) end,
	CreateCheckbox = function(_, setting) setting.control = "checkbox" end,
	CreateSlider = function(_, setting) setting.control = "slider" end,
	CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
	CreateDropdown = function(_, setting, options, tooltip)
		setting.control, setting.options, setting.tooltip = "dropdown", options(), tooltip
	end,
	CreateControlTextContainer = function()
		local data = {}
		return {
			Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
			GetData = function() return data end,
		}
	end,
	RegisterAddOnCategory = function() end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

-- The addon ------------------------------------------------------------------

local function load(saved)
	frames = { UIParent, plate }
	settings, cvars, cursor, skills, fighting = {}, {}, nil, {}, false
	ForeverSparklesDB = saved
	local ns = {}
	for _, file in ipairs({ "ForeverSparkles.lua", "Options.lua" }) do
		assert(loadfile(dir .. file))("ForeverSparkles", ns)
	end
	fire("ADDON_LOADED", "ForeverSparkles")
	fire("PLAYER_LOGIN")
	return ns
end

-- Whether the thing with this cursor gets a sparkle now. -> shown, the sparkle frame
local function sparkles(file, objectName)
	cursor, name = file, objectName
	fire("PLAYER_SOFT_INTERACT_CHANGED")
	for _, f in ipairs(frames) do
		if f.parent == plate and f.shown then
			return true, f
		end
	end
	return false
end

local HERB, ORE, QUEST = "Interface\\Cursor\\GatherHerbs", "Interface\\Cursor\\Mine", "Interface\\Cursor\\Quest"

-- Cases ----------------------------------------------------------------------

local function freshInstall(t)
	local ns = load(nil)
	local db = ForeverSparklesDB
	check(t .. ": herbs start on Automatic", db.categories.herb.mode == "auto", db.categories.herb.mode)
	check(t .. ": ore starts on Automatic", db.categories.ore.mode == "auto", db.categories.ore.mode)
	check(t .. ": herbs keep no checkbox value", db.categories.herb.enabled == nil)
	check(t .. ": quest objects keep their checkbox", db.categories.quest.enabled == true and db.categories.quest.mode == nil)

	learn("tailoring")
	check(t .. ": no Herbalism, Automatic: no herb sparkle", not sparkles(HERB))
	check(t .. ": no Mining, Automatic: no ore sparkle", not sparkles(ORE))
	check(t .. ": quest objects still sparkle", sparkles(QUEST))

	learn("tailoring", "herbalism")
	check(t .. ": Herbalism learned: herb sparkle", sparkles(HERB))
	check(t .. ": Herbalism learned, no Mining: no ore sparkle", not sparkles(ORE))

	learn("mining")
	check(t .. ": Herbalism unlearned: no herb sparkle", not sparkles(HERB))
	check(t .. ": Mining learned: ore sparkle", sparkles(ORE))

	-- Through the options page, as the dropdown sets it.
	local herb = settings.ForeverSparkles_herb_mode
	check(t .. ": herb page has a dropdown", herb and herb.control == "dropdown", herb and herb.control)
	if not herb then return end
	herb.set("on")
	check(t .. ": Enabled without Herbalism: herb sparkle", sparkles(HERB))
	herb.set("off")
	learn("herbalism")
	check(t .. ": Disabled with Herbalism: no herb sparkle", not sparkles(HERB))
	settings.ForeverSparkles_ore_mode.set("off")
	settings.ForeverSparkles_quest_enabled.set(false)
	settings.ForeverSparkles_loot_enabled.set(false)
	check(t .. ": every kind off: the interact key settings go back", cvars.SoftTargetInteract == "0", cvars.SoftTargetInteract)
	herb.set("auto")
	check(t .. ": back to Automatic with Herbalism: herb sparkle", sparkles(HERB))
	check(t .. ": a kind on again: interact key always on", cvars.SoftTargetInteract == "3", cvars.SoftTargetInteract)

	SlashCmdList.FOREVERSPARKLES("reset")
	check(t .. ": reset puts herbs on Automatic", db.categories.herb.mode == "auto")
	check(t .. ": reset leaves herbs without a checkbox value", db.categories.herb.enabled == nil)
	check(t .. ": reset turns quest objects on", db.categories.quest.enabled == true)
end

local function dropdown(t)
	load(nil)
	for _, kind in ipairs({ "herb", "ore" }) do
		local s = settings["ForeverSparkles_" .. kind .. "_mode"]
		local values = {}
		for i, option in ipairs(s and s.options or {}) do
			values[i] = option.value .. "=" .. option.label
		end
		local got = table.concat(values, ",")
		check(t .. ": " .. kind .. " options", got == "auto=Automatic,on=Enabled,off=Disabled", got)
		check(t .. ": " .. kind .. " has no checkbox", settings["ForeverSparkles_" .. kind .. "_enabled"] == nil)
	end
	check(t .. ": herb tooltip names Herbalism", settings.ForeverSparkles_herb_mode.tooltip:find("Herbalism", 1, true) ~= nil)
	check(t .. ": ore tooltip names Mining", settings.ForeverSparkles_ore_mode.tooltip:find("Mining", 1, true) ~= nil)
	local quest = settings.ForeverSparkles_quest_enabled
	check(t .. ": quest page keeps its checkbox", quest and quest.control == "checkbox")
end

-- Saved settings from 1.3 (version 2): ticked becomes Automatic, unticked Disabled.
local function upgrade(t, herbTicked, oreTicked, herbWants, oreWants)
	return function()
		load({ version = 2, enabled = true, saved = {}, categories = {
			herb = { enabled = herbTicked, size = 77 },
			ore = { enabled = oreTicked },
			quest = { enabled = false },
		} })
		local db = ForeverSparklesDB
		check(t .. ": herbs", db.categories.herb.mode == herbWants, db.categories.herb.mode)
		check(t .. ": ore", db.categories.ore.mode == oreWants, db.categories.ore.mode)
		check(t .. ": old herb checkbox value dropped", db.categories.herb.enabled == nil)
		check(t .. ": herb look kept", db.categories.herb.size == 77)
		check(t .. ": quest checkbox kept", db.categories.quest.enabled == false)
		check(t .. ": saved as version 3", db.version == 3)
		-- Loaded again, a choice made since is not undone.
		db.categories.herb.mode = "on"
		load(db)
		check(t .. ": choice survives a reload", ForeverSparklesDB.categories.herb.mode == "on")
	end
end

-- No skill lines to read on this client: Automatic stays on.
local function unreadable(t)
	load(nil)
	C_SkillInfo, GetNumSkillLines, GetSkillLineInfo = nil, nil, nil
	fire("SKILL_LINES_CHANGED")
	check(t .. ": herb sparkle", sparkles(HERB))
	check(t .. ": ore sparkle", sparkles(ORE))
end

-- The Classic skill API instead of C_SkillInfo.
local function classicAPI(t)
	load(nil)
	C_SkillInfo = nil
	local lines = { { "Professions", true }, { "Mining", false } }
	function GetNumSkillLines() return #lines end
	function GetSkillLineInfo(i) return lines[i][1], lines[i][2] end
	fire("SKILL_LINES_CHANGED")
	check(t .. ": Mining found: ore sparkle", sparkles(ORE))
	check(t .. ": no Herbalism: no herb sparkle", not sparkles(HERB))
	GetNumSkillLines, GetSkillLineInfo = nil, nil
end

-- Skill lines change in a fight (weapon skill-ups): the game is not asked
-- until it is over, and a skill-up that changes no profession syncs nothing.
local function combat(t)
	load(nil)
	learn("tailoring")
	check(t .. ": no Herbalism: no herb sparkle", not sparkles(HERB))

	fighting = true
	skillAsks = 0
	learn("tailoring", "herbalism")
	check(t .. ": skill lines not read in combat", skillAsks == 0, skillAsks)
	fire("PLAYER_ENTERING_WORLD")
	check(t .. ": not read on entering the world in combat either", skillAsks == 0, skillAsks)
	check(t .. ": old answer kept in combat", not sparkles(HERB))
	fire("SKILL_LINES_CHANGED")
	check(t .. ": a second change in combat still not read", skillAsks == 0, skillAsks)

	fighting = false
	fire("PLAYER_REGEN_ENABLED")
	check(t .. ": read once after combat", skillAsks > 0, skillAsks)
	check(t .. ": Herbalism seen after combat: herb sparkle", sparkles(HERB))

	skillAsks = 0
	fire("PLAYER_REGEN_ENABLED")
	check(t .. ": nothing changed: not read again after the next fight", skillAsks == 0, skillAsks)

	cvarAsks = 0
	fire("SKILL_LINES_CHANGED") -- a skill going up
	check(t .. ": skill-up out of combat is read", skillAsks > 0, skillAsks)
	check(t .. ": skill-up changing no profession does not sync", cvarAsks == 0, cvarAsks)
end

-- Corpses were tried and dropped: settings left from that go, and a
-- skinnable corpse gets nothing.
local function noCorpses(t)
	load({ version = 3, enabled = true, saved = {}, categories = { skin = { mode = "on" } } })
	check(t .. ": corpse settings removed", ForeverSparklesDB.categories.skin == nil)
	check(t .. ": no corpse page", settings.ForeverSparkles_skin_mode == nil)
	learn("herbalism")
	check(t .. ": skinning cursor: no sparkle", not sparkles("Interface\\Cursor\\Skin"))
	-- /fsparkles says why a herb does or does not sparkle.
	sparkles(HERB)
	local said = {}
	print = function(text) said[#said + 1] = text end
	SlashCmdList.FOREVERSPARKLES("")
	print = function() end
	said = table.concat(said, "\n")
	check(t .. ": /fsparkles names the herb page and its setting",
		said:find("Herbs: sparkles (setting auto, Automatic: herbalism true).", 1, true), said)
end

-- Lootable objects (chests): any of the loot cursors, its own checkbox.
local INTERACT, UNABLE_INTERACT = "Interface\\Cursor\\Interact", "Cursor Crosshair_UnableInteract_64"

-- Lootable objects: everything with the interact cursor (chests and barrels
-- show it, as doors do) except the names on the addon's exclusion list.
local function lootable(t)
	local ns = load(nil)
	local db = ForeverSparklesDB
	check(t .. ": on to start with", db.categories.loot.enabled == true and db.categories.loot.mode == nil)
	local box = settings.ForeverSparkles_loot_enabled
	check(t .. ": its page has a checkbox", box and box.control == "checkbox")

	check(t .. ": Barrel of Milk sparkles", sparkles(INTERACT, "Barrel of Milk"))
	check(t .. ": Battered Chest, out of range (greyed), sparkles", sparkles(UNABLE_INTERACT, "Battered Chest"))
	check(t .. ": a door not on the list sparkles too", sparkles(INTERACT, "Door"))
	check(t .. ": an object the game gives no name sparkles", sparkles(INTERACT, nil))
	-- Chairs are on the list, as a word.
	check(t .. ": Wooden Chair does not", not sparkles(INTERACT, "Wooden Chair"))
	check(t .. ": Chair does not", not sparkles(INTERACT, "Chair"))
	check(t .. ": Dwarven High Back Chair does not", not sparkles(INTERACT, "Dwarven High Back Chair"))
	check(t .. ": Angela's Chair does not", not sparkles(INTERACT, "Angela's Chair"))
	check(t .. ": monastery chair (lower case) does not", not sparkles(UNABLE_INTERACT, "monastery chair"))
	check(t .. ": a word that only starts with chair is not one", sparkles(INTERACT, "Chairman's Chest"))
	check(t .. ": Stone Bench does not", not sparkles(INTERACT, "Stone Bench"))
	check(t .. ": Krastinov's Work Bench does not", not sparkles(INTERACT, "Krastinov's Work Bench"))
	check(t .. ": Bench] (as the data spells it) does not", not sparkles(INTERACT, "Bench]"))
	check(t .. ": Mechanic Stool does not", not sparkles(INTERACT, "Mechanic Stool"))
	check(t .. ": Night Elf Stool does not", not sparkles(UNABLE_INTERACT, "Night Elf Stool"))
	-- A phrase added to the list.
	table.insert(ns.NOT_LOOT, "iron door")
	check(t .. ": a phrase on the list matches", not sparkles(INTERACT, "Large Iron Door"))
	check(t .. ": only the whole phrase", sparkles(INTERACT, "Iron Bound Door Chest"))
	check(t .. ": the list does not touch other objects", sparkles(INTERACT, "Battered Chest"))
	table.remove(ns.NOT_LOOT)

	-- Loot cursors count too; a locked chest does not.
	check(t .. ": LootAll cursor sparkles", sparkles("Interface\\Cursor\\LootAll"))
	check(t .. ": Pickup cursor sparkles", sparkles("Interface\\Cursor\\Pickup"))
	check(t .. ": Classic Pick cursor sparkles", sparkles("Interface\\Cursor\\Pick"))
	check(t .. ": a locked chest does not", not sparkles("Interface\\Cursor\\PickLock"))
	check(t .. ": a mailbox (mail cursor) does not", not sparkles("Interface\\Cursor\\Mail", "Mailbox"))

	-- A chest your quest needs is a quest object: its page decides.
	questObject = true
	box.set(false)
	check(t .. ": quest chest with loot off: sparkles as a quest object", sparkles(INTERACT, "Battered Chest"))
	settings.ForeverSparkles_quest_enabled.set(false)
	check(t .. ": quest chest with quest objects off: none", not sparkles(INTERACT, "Battered Chest"))
	questObject = false
	check(t .. ": loot off: no sparkle", not sparkles(INTERACT, "Barrel of Milk"))
	box.set(true)
	check(t .. ": loot on again: sparkles", sparkles(INTERACT, "Barrel of Milk"))

	-- Settings from 1.3 get the new page switched on.
	load({ version = 2, enabled = true, saved = {}, categories = { herb = { enabled = true } } })
	check(t .. ": 1.3 settings get lootable objects on", ForeverSparklesDB.categories.loot.enabled == true)
end

local saved = C_SkillInfo
freshInstall("fresh install")
dropdown("options page")
combat("combat")
noCorpses("no corpses")
lootable("lootable objects")
upgrade("1.3 ticked", true, true, "auto", "auto")()
upgrade("1.3 unticked herbs", false, true, "off", "auto")()
unreadable("no skill API")
C_SkillInfo = saved
classicAPI("classic skill API")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
