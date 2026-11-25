-- Offline checks for ForeverSearch's window (Window.lua): the game's frames,
-- textures, text, tooltip, timers and events stood in for, the addon
-- loaded as the game does on ForeverData's real data, and the window
-- driven as a player would (open, type, hover, click, wait frames). It
-- checks what the window does, not how it looks: sizes and art are only
-- as the code asks for them.
--   lua5.1 scripts/foreversearch-window-test.lua
local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		io.write("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "") .. "\n")
	end
end

-- The game: widgets -------------------------------------------------------------
--
-- A widget keeps what is set on it and answers what is asked of it; a
-- method it does not know does nothing (the look: fonts, colours, layers).

local widgets = {}
local Widget = {}
local function NewWidget(kind, parent, name)
	local w = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, points = {}, width = 0, height = 0, events = {} }, Widget)
	widgets[#widgets + 1] = w
	if name then
		_G[name] = w
	end
	return w
end
Widget.__index = function(_, key)
	local m = rawget(Widget, key)
	if m then
		return m
	end
	-- A method (Capitalised) it does not know does nothing; a field it
	-- does not have is nil.
	if type(key) == "string" and key:match("^%u") then
		return function() end
	end
	return nil
end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript(name, fn)
	local before = self.scripts[name]
	self.scripts[name] = function(...)
		if before then before(...) end
		fn(...)
	end
end
function Widget:Run(name, ...)
	local fn = self.scripts[name]
	if fn then
		return fn(self, ...)
	end
end
function Widget:Show()
	if not self.shown then
		self.shown = true
		self:Run("OnShow")
	end
end
function Widget:Hide()
	if self.shown then
		self.shown = false
		self:Run("OnHide")
	end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible()
	local w = self
	while w do
		if not w.shown then return false end
		w = w.parent
	end
	return true
end
function Widget:GetParent() return self.parent end
function Widget:SetParent(p) self.parent = p end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text or "" end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetStringWidth() return #(self.text or "") * 6 end
function Widget:GetStringHeight() return 12 end
function Widget:GetContentHeight()
	local _, lines = string.gsub(self.text or "", "\n", "")
	return (lines + 1) * 12
end
function Widget:CreateTexture() return NewWidget("Texture", self) end
function Widget:CreateFontString() return NewWidget("FontString", self) end
function Widget:CreateMaskTexture() return NewWidget("MaskTexture", self) end
function Widget:SetAtlas(name) self.atlas, self.file = name, nil end
function Widget:GetAtlas() return self.atlas end
function Widget:SetTexture(file) self.file, self.atlas = file, nil end
function Widget:SetTexCoord(...) self.coords = { ... } end
function Widget:AddMaskTexture(m)
	self.masks = self.masks or {}
	self.masks[#self.masks + 1] = m
end
function Widget:EnableMouse(on) self.mouse = on end
function Widget:IsMouseOver() return self.mouseOver == true end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:SetFocus() self.focus = true end
function Widget:ClearFocus() self.focus = false end

function CreateFrame(kind, name, parent) return NewWidget(kind, parent, name) end
UIParent = NewWidget("Frame")

-- The tooltip: its owner, what it shows, whether it is shown.
GameTooltip = NewWidget("GameTooltip")
GameTooltip.shown = false
function GameTooltip:SetOwner(owner) self.owner, self.item, self.lines = owner, nil, {} end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetItemByID(id) self.item = id end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:Hide()
	self.shown = false
	self.owner = nil
end

-- Time, frames, timers and events.
local now = 100
function GetTime() return now end
function debugprofilestop() return os.clock() * 1000 end
local timers = {}
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
local function Frames(n)
	for _ = 1, n or 1 do
		now = now + 1 / 60
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= now then
				due[#due + 1] = table.remove(timers, i)
			end
		end
		for i = #due, 1, -1 do
			due[i].fn()
		end
		for _, w in ipairs(widgets) do
			if w.shown and w.scripts.OnUpdate then
				w.scripts.OnUpdate(w, 1 / 60)
			end
		end
	end
end
local function Fire(event, ...)
	for _, w in ipairs(widgets) do
		if w.events[event] and w.scripts.OnEvent then
			w.scripts.OnEvent(w, event, ...)
		end
	end
end

-- The rest of the game the window asks of.
local printed = {}
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	printed[#printed + 1] = table.concat(parts, " ")
end
function geterrorhandler() return function(e) error(e, 2) end end
function issecretvalue() return false end
SlashCmdList = {}
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
UISpecialFrames = {}
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
GameFontNormal, GameFontNormalSmall, GameFontHighlightLarge, GameFontHighlightSmall, GameFontDisableLarge, GameFontDisableSmall = {}, {}, {}, {}, {}, {}
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 12 end
function UnitSex() return 2 end
function UnitName() return "Tester" end
function UnitClass() return "Hunter" end
function UnitRace() return "Orc" end
function IsShiftKeyDown() return false end
function IsInInstance() return false, "none" end
function GetRealZoneText() return "Durotar" end
function SetPortraitTextureFromCreatureDisplayID() end
function CreateVector2D(x, y) return { x = x, y = y } end
-- Standing in Razor Hill, Durotar 53.0, 42.0; each game map its own
-- continent, 1000 yards across.
C_Map = {
	GetBestMapForUnit = function() return 1411 end,
	GetPlayerMapPosition = function() return { x = 0.53, y = 0.42 } end,
	GetWorldPosFromMapPos = function(map, v) return map, { x = v.x * 1000, y = v.y * 1000 } end,
}
-- Atlases the client has (the ones the window asks for); a -c60 name only
-- for Forever's own Skyborne art.
local function Atlas(name)
	local known = name:match("^UI%-HUD%-CoolDownManager%-") or name:match("^UI%-HUD%-UnitFrame%-SmallCircle%-")
		or (name:match("^classicon%-") and not name:match("%-c60$")) or name == "Calendar_Quest"
		or (name:match("^raceicon%-") and (not name:match("%-c60$") or name:match("skyborne")))
	if not known then
		return nil
	end
	return { file = "atlas/" .. name, leftTexCoord = 0.25, rightTexCoord = 0.5, topTexCoord = 0, bottomTexCoord = 0.25 }
end
C_Texture = { GetAtlasInfo = Atlas }
C_Item = {
	GetItemIconByID = function() return 134400 end,
	GetItemInfo = function(id) return "item " .. id end,
	RequestLoadItemDataByID = function() end,
}
-- An item's tooltip: its name, then a line, with a data instance to
-- redraw on.
C_TooltipInfo = {
	GetItemByID = function(id)
		return { dataInstanceID = 7000 + id, lines = { { leftText = "item " .. id, type = 22 }, { leftText = "Trade Goods", type = 0 } } }
	end,
}

-- The addons ---------------------------------------------------------------------

local data = {}
for _, f in ipairs({ "Meta", "Items", "Npcs", "Objects", "Quests", "Zones", "Loot", "Spawns", "Vendors", "Trainers", "Unsearched", "Levels" }) do
	assert(loadfile("addons/ForeverData/Data/" .. f .. ".lua"))("ForeverData", data)
end
assert(loadfile("addons/ForeverData/Core.lua"))("ForeverData", data)
local ns = {}
for _, f in ipairs({ "Core.lua", "Window.lua" }) do
	assert(loadfile("addons/ForeverSearch/" .. f))("ForeverSearch", ns)
end
Fire("ADDON_LOADED", "ForeverSearch")
Fire("PLAYER_LOGIN")
Frames(200) -- the search lists, built in slices after login

-- Finding the window's parts: the bar's edit box, the page's text blocks.
local function Find(test)
	for _, w in ipairs(widgets) do
		if test(w) then return w end
	end
end
local function All(test)
	local out = {}
	for _, w in ipairs(widgets) do
		if test(w) then out[#out + 1] = w end
	end
	return out
end
local function Within(w, root)
	while w do
		if w == root then return true end
		w = w.parent
	end
	return false
end

-- Driving it -----------------------------------------------------------------

SlashCmdList.FOREVERSEARCH("")
local box = Find(function(w) return w.kind == "EditBox" end)
check("opened: the bar and its box", box ~= nil)
local content = Find(function(w) return w.kind == "Frame" and w.parent and w.parent.kind == "ScrollFrame" end)
check("the page's content frame", content ~= nil)

local function Type(text)
	box:SetText(text)
	box:Run("OnTextChanged", true)
	Frames(60)
end
-- The page's text, shown blocks top to bottom.
local function PageText()
	local out = {}
	for _, w in ipairs(widgets) do
		if w.kind == "SimpleHTML" and w:IsVisible() and Within(w, content) then
			out[#out + 1] = w.text or ""
		end
	end
	return table.concat(out, "\n")
end
local function PageHas(needle) return string.find(PageText(), needle, 1, true) ~= nil end
-- The page's text block holding a link, to hover or click it.
local function LinkBlock(link)
	for _, w in ipairs(widgets) do
		if w.kind == "SimpleHTML" and w:IsVisible() and Within(w, content) and string.find(w.text or "", "|H" .. link .. "|h", 1, true) then
			return w
		end
	end
end

-- A search shows its finds and the first one's page.
Type("linen cloth")
check("search: the page of the first find", PageHas("Linen Cloth"), PageText():sub(1, 200))

-- Tooltips: an item link's tooltip goes when another page comes, and stays
-- when the same page is drawn again (its tooltip data came in).
Type("quest: from the wreckage")
check("quest page shown", PageHas("From The Wreckage"), PageText():sub(1, 200))
local reward = LinkBlock("fsearch:item:4928")
check("the quest's reward is a link on its page", reward ~= nil)
if reward then
	reward:Run("OnHyperlinkEnter", "fsearch:item:4928")
	check("hovering the reward shows its tooltip", GameTooltip.shown and GameTooltip.item == 4928 and GameTooltip.owner == reward)
	reward:Run("OnHyperlinkClick", "fsearch:item:4928")
	Frames(30)
	check("the reward's page", PageHas("Sandrunner Wristguards"), PageText():sub(1, 200))
	check("going to the reward's page closes its tooltip", not GameTooltip.shown, GameTooltip.item)
end

-- An item page is drawn again when its tooltip data comes in: a link on it
-- being hovered keeps its tooltip. (Bolt of Linen Cloth's page links
-- Tightly Sealed Trunk.)
Type("bolt of linen cloth")
check("an item page shown", PageHas("Bolt of Linen Cloth"), PageText():sub(1, 200))
local trunk = LinkBlock("fsearch:item:20708")
check("it links another item", trunk ~= nil)
if trunk then
	trunk:Run("OnHyperlinkEnter", "fsearch:item:20708")
	check("hovering it shows its tooltip", GameTooltip.shown and GameTooltip.item == 20708)
	local before = 0
	for _, w in ipairs(widgets) do if w.kind == "SimpleHTML" then before = before + 1 end end
	Fire("TOOLTIP_DATA_UPDATE", 7000 + 2996)
	Frames(5)
	check("the page was drawn again", ns.timings.page and ns.timings.page.what == "Bolt of Linen Cloth")
	check("a redraw of the same page keeps the tooltip", GameTooltip.shown and GameTooltip.item == 20708)
end

-- Hovering a find shows its page only once the mouse rests.
Type("linen")
local rows = All(function(w) return w.kind == "Button" and w.scripts.OnEnter and w.parent and w.parent.kind == "Frame" and w.find end)
check("finds in rows", #rows >= 2, #rows)
if #rows >= 2 then
	local first = PageText()
	rows[2]:Run("OnEnter")
	Frames(1)
	check("passing over a row does not build its page", PageText() == first)
	Frames(12)
	check("resting on it does", PageText() ~= first and PageHas(rows[2].find.name), rows[2].find.name)
end

-- Crests and icons: a druid quest for Tauren, its side's crest, the class
-- and race icons, each a search for its kind.
Type("quest: a lesson to learn")
local function Shown(test)
	return All(function(w) return w:IsVisible() and Within(w, content) and test(w) end)
end
local crests = Shown(function(w) return w.kind == "Texture" and w.atlas and w.atlas:match("SmallCircle") end)
check("the Horde crest", #crests == 1 and crests[1].atlas:match("Horde"), #crests)
local function Art(w) return w.file or w.atlas or "" end
local icons = Shown(function(w) return w.kind == "Texture" and (Art(w):match("classicon") or Art(w):match("raceicon")) end)
check("a class and a race icon", #icons == 2, #icons)
for _, icon in ipairs(icons) do
	local art = Art(icon)
	check("icon set by file and region, not atlas: SetAtlas drops the mask (" .. art .. ")", icon.atlas == nil and icon.coords ~= nil)
	check("icon masked (" .. art .. ")", icon.masks and #icon.masks == 1)
	check("race portrait cropped, class art whole (" .. art .. ")", icon.coords and
		(art:match("raceicon") and icon.coords[1] > 0.25 or art:match("classicon") and icon.coords[1] == 0.25), icon.coords and icon.coords[1])
end
local badges = Shown(function(w) return w.kind == "Frame" and w.query end)
local queries = {}
for _, b in ipairs(badges) do queries[#queries + 1] = b.query end
table.sort(queries)
check("icons and crest search their kind", table.concat(queries, "; ") == "quest: class:druid; quest: race:tauren; quest: side:horde", table.concat(queries, "; "))
local druid = Find(function(w) return w.query == "quest: class:druid" end)
if druid then
	druid:Run("OnEnter")
	check("hovering an icon names what a click finds", GameTooltip.shown and GameTooltip.lines[1] == "Druid quests", GameTooltip.lines and GameTooltip.lines[1])
	druid:Run("OnLeave")
	druid:Run("OnMouseUp", "LeftButton")
	check("clicking it searches", box:GetText() == "quest: class:druid", box:GetText())
end

-- A slow page shows its heading at once and fills in over frames; no frame
-- longer than the budget allows.
Type("zone: durotar")
check("a zone page, built", PageHas("Durotar") and PageHas("Search in"), PageText():sub(1, 200))
check("/find time knows the last page", ns.timings and ns.timings.page and ns.timings.page.frames >= 1)
SlashCmdList.FOREVERSEARCH("time")
check("/find time prints both", printed[#printed - 1] and printed[#printed - 1]:find("last search") and printed[#printed]:find("last page"),
	printed[#printed])

if failures > 0 then
	io.write(failures .. " failed\n")
	os.exit(1)
end
io.write("ok\n")
