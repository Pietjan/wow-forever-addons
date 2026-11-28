-- Offline checks for ForeverPlates' quest mark (QuestTarget.lua): a stand-in
-- nameplate with Blizzard's health bar, raid mark and buff list, the addon's
-- files loaded as the game does, and which frame the "!" is anchored to as
-- buffs and the mark come and go. Covers following the buff list (left of
-- the mark), the mark, and the bar. How it looks (offsets) is not checked.
--   lua5.1 scripts/foreverplates-quest-test.lua
local dir = "addons/ForeverPlates/"
local failures, checks = 0, 0

local function check(name, ok, detail)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		io.write("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "") .. "\n")
	end
end

-- The game -------------------------------------------------------------------

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }
Enum = { TooltipDataLineType = { QuestTitle = 1, QuestPlayer = 2, QuestObjective = 3 } }
C_TooltipInfo = { GetUnit = function() return nil end }
local related = true
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return related end }
function UnitName() return "Me" end
function UnitCanAttack() return true end

-- Frames: every method nobody needs does nothing. Show/Hide run the
-- scripts hooked on them, as the game does.
local frames = {}
local function NewFrame(parent)
	local f = { events = {}, scripts = {}, hooks = {}, parent = parent, shown = true, children = 0 }
	setmetatable(f, { __index = function() return function() end end })
	f.RegisterEvent = function(self, e) self.events[e] = true end
	f.RegisterUnitEvent = function(self, e) self.events[e] = true end
	f.UnregisterEvent = function(self, e) self.events[e] = nil end
	f.SetScript = function(self, what, fn) self.scripts[what] = fn end
	f.HookScript = function(self, what, fn)
		self.hooks[what] = self.hooks[what] or {}
		table.insert(self.hooks[what], fn)
	end
	local function run(self, what)
		for _, fn in ipairs(self.hooks[what] or {}) do fn(self) end
	end
	f.Show = function(self)
		if not self.shown then self.shown = true; run(self, "OnShow") end
	end
	f.Hide = function(self)
		if self.shown then self.shown = false; run(self, "OnHide") end
	end
	f.IsShown = function(self) return self.shown end
	f.GetNumChildren = function(self) return self.children end
	f.GetFrameLevel = function() return 1 end
	f.ClearAllPoints = function(self) self.point = nil end
	f.SetPoint = function(self, point, relative, relativePoint, x, y)
		self.point = { point, relative, relativePoint, x, y }
	end
	f.CreateTexture = function() return NewFrame() end
	frames[#frames + 1] = f
	return f
end
function CreateFrame(_, _, parent) return NewFrame(parent) end
function hooksecurefunc(t, name, fn)
	local original = t[name]
	t[name] = function(...)
		local r = original(...)
		fn(...)
		return r
	end
end

local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

-- One nameplate as Blizzard_NamePlates.xml builds it (forever branch).
local function NewPlate()
	local plate = NewFrame()
	local unitFrame = NewFrame(plate)
	plate.UnitFrame = unitFrame
	unitFrame.HealthBarsContainer = NewFrame(unitFrame)
	unitFrame.RaidTargetFrame = NewFrame(unitFrame)
	unitFrame.RaidTargetFrame.shown = false
	local auras = NewFrame(unitFrame)
	unitFrame.AurasFrame = auras
	auras.BuffListFrame = NewFrame(auras)
	auras.BuffListFrame.Layout = function() end -- GridLayoutFrame's
	return plate
end

-- What NamePlateAurasMixin does on an aura change: release every icon
-- (SetParent(nil)), give the list its icons, then Layout if it is shown.
local function setBuffs(plate, n)
	local list = plate.UnitFrame.AurasFrame.BuffListFrame
	list.children = 0
	if list:IsShown() then
		list.children = n
		list:Layout()
	end
end

local plates = {}
C_NamePlate = {
	GetNamePlateForUnit = function(unit) return plates[unit] end,
	GetNamePlates = function() return {} end,
}

-- The addon ------------------------------------------------------------------

local function load()
	frames, plates, related = {}, {}, true
	ForeverPlatesDB = nil
	local ns = { RegisterSettings = function() end }
	for _, file in ipairs({ "Core.lua", "QuestTarget.lua" }) do
		assert(loadfile(dir .. file))("ForeverPlates", ns)
	end
	fire("ADDON_LOADED", "ForeverPlates")
	fire("PLAYER_LOGIN")
end

local function show(unit)
	local plate = NewPlate()
	plates[unit] = plate
	fire("NAME_PLATE_UNIT_ADDED", unit)
	return plate
end

-- The quest mark on this plate, and the frame its right edge is pinned to.
local function mark(plate)
	for _, f in ipairs(frames) do
		if f.parent == plate and rawget(f, "point") then
			return f, f.point[2], f.point[1] .. ">" .. f.point[3]
		end
	end
end

local function name(plate, frame)
	local u = plate.UnitFrame
	if frame == u.HealthBarsContainer then return "bar" end
	if frame == u.RaidTargetFrame then return "raid mark" end
	if frame == u.AurasFrame.BuffListFrame then return "buff list" end
	return tostring(frame)
end

local function pinnedTo(t, plate, want)
	local icon, to, how = mark(plate)
	check(t .. ": quest mark shown", icon and icon.shown == true)
	check(t .. ": pinned to the " .. want, icon and name(plate, to) == want, icon and name(plate, to))
	check(t .. ": its right edge left of it", how == "RIGHT>LEFT", how)
end

-- Cases ----------------------------------------------------------------------

local function bareBar(t)
	load()
	local plate = show("nameplate1")
	pinnedTo(t, plate, "bar")
end

local function buffsComeAndGo(t)
	load()
	local plate = show("nameplate1")
	setBuffs(plate, 1)
	pinnedTo(t .. ", one buff", plate, "buff list")
	setBuffs(plate, 2)
	pinnedTo(t .. ", two buffs", plate, "buff list")
	setBuffs(plate, 0)
	pinnedTo(t .. ", buffs gone", plate, "bar")
end

local function buffsLeftOfRaidMark(t)
	load()
	local plate = show("nameplate1")
	local raid = plate.UnitFrame.RaidTargetFrame
	raid:Show()
	pinnedTo(t .. ", mark set", plate, "raid mark")
	setBuffs(plate, 1)
	pinnedTo(t .. ", mark and a buff", plate, "buff list")
	setBuffs(plate, 0)
	pinnedTo(t .. ", buff gone, mark stays", plate, "raid mark")
	raid:Hide()
	pinnedTo(t .. ", mark cleared", plate, "bar")
end

local function buffsAlreadyThere(t)
	load()
	local plate = NewPlate()
	plate.UnitFrame.AurasFrame.BuffListFrame.children = 2
	plate.UnitFrame.RaidTargetFrame.shown = true
	plates.nameplate1 = plate
	fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	pinnedTo(t, plate, "buff list")
end

local function buffListOff(t)
	-- The buff list is hidden when its aura cvar is off; stale icons then
	-- do not count.
	load()
	local plate = show("nameplate1")
	setBuffs(plate, 1)
	plate.UnitFrame.AurasFrame.BuffListFrame:Hide()
	pinnedTo(t, plate, "bar")
end

local function noOtherPlateMoves(t)
	load()
	local a = show("nameplate1")
	local b = show("nameplate2")
	setBuffs(a, 1)
	pinnedTo(t .. ", buffed plate", a, "buff list")
	pinnedTo(t .. ", other plate", b, "bar")
end

bareBar("bare bar")
buffsComeAndGo("buffs come and go")
buffsLeftOfRaidMark("buffs left of the raid mark")
buffsAlreadyThere("buffs already there when the plate shows")
buffListOff("buff list switched off")
noOtherPlateMoves("one plate's buffs")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
