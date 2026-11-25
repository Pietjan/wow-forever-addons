-- ForeverSearch, the bar: a floating search bar near the top of the screen,
-- finds appearing in rows under it as you type, and the chosen find's
-- details in a panel beside them. /find [text] or the key bound under
-- Key Bindings > AddOns (Ctrl-K by default) opens it, Escape closes it.
--
--   typing        searches as you type; words narrow it: item: npc: object:
--                 quest: zone:, q:rare (quality), lvl:40-50, in:hinterlands
--   Up, Down      choose a find (its details show beside the list)
--   Enter         closes, keeping the text for next time
--   Shift-Enter   or Shift-click: links the chosen item in chat
--   mouse         hover or click chooses; the wheel scrolls the finds
--   buttons       under the bar set the filter words: a kind, a quality or
--                 better, your level (Near me), your zone (Here); Tab and
--                 Shift-Tab step through the kinds
--   links         names in the preview show that thing; Back (or the mouse's
--                 back button) returns; hover an item for its tooltip
--   in a dungeon or raid the bar opens with in:<that instance> in front of
--                 the text (in:blackrock-depths), taken off again elsewhere;
--                 a line above the finds says how the filter words were read
local ADDON, ns = ...

local WIDTH = 520
local BAR_HEIGHT = 44
local ROW, ROWS = 36, 10
local ICON = ROW - 8
local RING_X, RING_Y = ICON * 0.2, ICON * 0.2 - 1 -- the ring reaches past the icon

-- HasAtlas tells whether this client has an atlas of that name.
local function HasAtlas(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end
local PREVIEW_WIDTH = 380
local KIND_ICON = {
	npc = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
	object = "Interface\\Icons\\INV_Misc_Bag_10",
	quest = "Interface\\GossipFrame\\AvailableQuestIcon",
	zone = "Interface\\LFGFrame\\LFGIcon-Zone",
	item = "Interface\\Icons\\INV_Misc_QuestionMark",
}
-- The game's own portraits for an instance (the calendar uses the dungeon
-- and raid ones).
local INSTANCE_ICON = {
	dungeon = "Interface\\LFGFrame\\LFGIcon-Dungeon",
	raid = "Interface\\LFGFrame\\LFGIcon-Raid",
	battleground = "Interface\\LFGFrame\\LFGIcon-Battleground",
}
local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local bar, box, list, rows, preview
local SearchFor -- below: puts words in the bar and searches
local finds, offset, chosen = {}, 0, 1
local found, limit = 0, 30 -- how many were found; how many were asked for
-- With only filter words (in:sm, is:raid) the whole lot is wanted, grouped:
-- up to this many, scrolled through.
local FILTER_LIMIT = 1000

-- A search runs in steps over several frames (see ForeverData.Search),
-- starting a moment after the last key, so typing stays smooth.
local PAUSE = 0.1      -- seconds after the last key
local BUDGET = 6       -- milliseconds of searching a frame
local STEP = 500       -- names a step (each may be decoded for a filter)
local job, startAt, jobText, searchTiming
local FILTER_LINE = 20 -- height of the line saying how the filter words were read
local CHIPS_HEIGHT = 30 -- the row of filter buttons under the bar
local KIND_CHIPS = { { nil, "All" }, { "item", "Items" }, { "npc", "Creatures" }, { "object", "Objects" }, { "quest", "Quests" }, { "zone", "Zones" } }
local QUALITY_CHIPS = { { 2, "uncommon" }, { 3, "rare" }, { 4, "epic" }, { 5, "legendary" } }
local chips
local driver = CreateFrame("Frame")
driver:Hide()

local function Panel(name, parent)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	f:SetBackdrop(BACKDROP)
	-- Forever's own panel black (its dropdown fill, common-dropdown-c-bg-c60):
	-- warm, near-black, not the blue-grey of Classic's tooltips.
	f:SetBackdropColor(0.008, 0.006, 0.003, 0.8)
	f:SetBackdropBorderColor(0.55, 0.55, 0.6, 0.9)
	return f
end

local function QualityColour(quality)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

local QUEST_ATLAS = "Calendar_Quest" -- a square parchment tile with a gold "!"

-- Portrait draws a creature's portrait from the model wowhead shows it
-- with (ForeverData's display), as the client draws one of a unit it has
-- not met; false when that model is unknown or this client has no such call.
local function Portrait(texture, id)
	local n = ForeverData.Npc(id)
	if not (n and n.display and SetPortraitTextureFromCreatureDisplayID) then
		return false
	end
	-- Always the game's circle: unlike SetPortraitTexture this call has no
	-- disableMasking argument; the row's black fill shows around it.
	return (pcall(SetPortraitTextureFromCreatureDisplayID, texture, n.display))
end

local function Icon(find)
	if find.kind == "item" and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(find.id) or KIND_ICON.item
	end
	if find.kind == "zone" then
		local z = ForeverData.Zone(find.id)
		return z and INSTANCE_ICON[z.instance] or KIND_ICON.zone
	end
	return KIND_ICON[find.kind]
end

local function ItemLink(id)
	local _, link = C_Item.GetItemInfo(id)
	if not link and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(id) -- the next try has it
	end
	return link
end

local function LinkInChat(find)
	if find and find.kind == "item" then
		local link = ItemLink(find.id)
		if link then
			ChatEdit_InsertLink(link)
		end
	end
end

-- The preview shows one thing's page; following a link in it shows the
-- linked thing's, and Back the one before. history holds the pages left.
local page, history = nil, {}

-- The page is a stack of blocks in preview.content: runs of text lines in
-- one SimpleHTML each (its names are links), and list entries as a row of
-- their own, the name left and its number (a chance, a level, a price)
-- right-aligned beside it.
local RIGHT_WIDTH = 76 -- wide enough for a price, "12g 34s 56c"
local RIGHT_GAP = 8 -- between an entry's name and its number
local blocks = {}
local Block -- made in MakeBar's part, as it needs the link handlers

-- Timing ------------------------------------------------------------------------
--
-- What the last search and the last page cost, measured in the game: the
-- milliseconds of work, over how many frames, the longest frame's share,
-- and for a page the drawing of it. /find time prints them.
ns.timings = {}
local function NewTiming(what)
	return { what = what, work = 0, frames = 0, longest = 0, draw = 0 }
end
local function TimeSlice(t, ms)
	t.work, t.frames, t.longest = t.work + ms, t.frames + 1, math.max(t.longest, ms)
end

-- Pages are built like searches: in a coroutine, a slice a frame
-- (PAGE_BUDGET), so a long page (a zone, Linen Cloth's 700 sources) never
-- holds a frame. The page's heading shows at once; the rest when built. A
-- redraw (keepScroll) leaves the page as it is until the new one is ready.
local PAGE_BUDGET = 5 -- milliseconds a frame
local pageJob
local pageDriver = CreateFrame("Frame")
pageDriver:Hide()
local Render
local Follow -- below: goes to a linked thing, keeping the page left for Back

local function PageHead(kind, id)
	local quality = kind == "item" and ForeverData.Item(id) and ForeverData.Item(id).quality
	local r, g, b = QualityColour(quality)
	local lines = {}
	if #history > 0 then
		local last = history[#history]
		lines[#lines + 1] = ("|Hfsearch:back|h|cff66bbff< Back to %s|r|h"):format(ns.NameOf(last.kind, last.id))
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, ns.NameOf(kind, id))
	lines[#lines + 1] = ("|cff9d9d9d%s %d|r"):format(ns.KindLabel(kind, id), id)
	lines[#lines + 1] = ""
	return lines
end

-- StepPage works on a page for one slice; true once it is drawn (or failed).
local function StepPage(job)
	local start = debugprofilestop()
	ns.SliceUntil(start + PAGE_BUDGET)
	local ok, lines = coroutine.resume(job.co)
	ns.SliceUntil(nil)
	TimeSlice(job.timing, debugprofilestop() - start)
	if not ok then
		geterrorhandler()(lines)
		return true
	end
	if coroutine.status(job.co) ~= "dead" then
		return false
	end
	local all = job.head
	for _, line in ipairs(lines or {}) do
		all[#all + 1] = line
	end
	local drawStart = debugprofilestop()
	Render(all, job.keepScroll)
	job.timing.draw = debugprofilestop() - drawStart
	ns.timings.page = job.timing
	return true
end

-- SetCrest shows the faction crest of a page's quest or creature at the
-- top right of the page (ns.PageSide): one side's, both side by side
-- (Alliance, Horde) for both, or none.
-- The crest, and the class and race icons beside it centred on it. The
-- crest at its art's shape (24 by 27); the art leaves about 2 px clear on
-- each side, so crests touch box to box and the icons sit 2 px off, which
-- shows as the same 4 px between all of them.
local CREST_W, CREST_H = 27, 30
local GAP = 4 -- between icons
local CREST_MARGIN = 2 -- clear art at each side of a crest
local crestsShown, headRoom = 0, 0
local function Crest(texture, side)
	if side and pcall(texture.SetAtlas, texture, ns.CREST[side]) then
		texture:Show()
		return 1
	end
	texture:Hide()
	return 0
end
-- Class and race icons go left of the crests, for a quest only some
-- classes or races may take: the game's square class art and race
-- portraits, dressed as the result rows' icons are (the Cooldown Manager's
-- rounded mask and border ring), made as needed.
local BADGE = 24
local BADGE_STEP = BADGE + GAP

-- Clickable makes a crest or icon a search for its kind (f.query: "quest:
-- class:druid"), named on hover (f.label).
local function Clickable(f)
	f:EnableMouse(true)
	f:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.query then
			SearchFor(self.query)
		end
	end)
	f:SetScript("OnEnter", function(self)
		if self.label then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.label)
			for _, line in ipairs(self.more or {}) do
				GameTooltip:AddLine(line, 1, 1, 1)
			end
			if self.query then
				GameTooltip:AddLine("Click to find them", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local badges = {}
local function Badge(i)
	local b = badges[i]
	if b then
		return b
	end
	b = CreateFrame("Frame", nil, preview.content)
	b:SetSize(BADGE, BADGE)
	Clickable(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = b:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(mask)
		local ring = b:CreateTexture(nil, "OVERLAY")
		ring:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		local rx, ry = BADGE * 0.2, BADGE * 0.2 - 1
		ring:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -rx, ry)
		ring:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", rx, -ry)
	else
		local edge = b:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(0, 0, 0, 1)
		edge:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, -1)
	end
	badges[i] = b
	return b
end

-- SetArt puts an atlas on a texture as its file and its region of it,
-- crop of it (a share of each side) cut away. Not through SetAtlas: the
-- class art set that way showed square in game, the rounded mask not on
-- it, where the race portraits set this way were masked.
local function SetArt(texture, name, crop)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	local file = info and (info.file or info.filename)
	if not file then
		texture:SetAtlas(name)
		return
	end
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local dx, dy = (r - l) * crop, (b - t) * crop
	texture:SetTexture(file)
	texture:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
end

-- Art is Forever's own (its -c60 name) where it has one, else the plain.
local function ArtName(atlas)
	if HasAtlas(atlas .. "-c60") then
		return atlas .. "-c60"
	end
	return HasAtlas(atlas) and atlas or nil
end

local function SetCrest(kind, id)
	local side = ns.PageSide(kind, id)
	if side == "Both" then
		crestsShown = Crest(preview.crest, "Horde") + Crest(preview.crest2, "Alliance")
	else
		crestsShown = Crest(preview.crest, side) + Crest(preview.crest2, nil)
	end
	-- A crest finds that side's quests or people.
	local sides = side == "Both" and { "Horde", "Alliance" } or { side }
	for i, hit in ipairs({ preview.crestHit, preview.crest2Hit }) do
		local s = sides[i]
		hit:SetShown(s ~= nil and (i == 1 and preview.crest or preview.crest2):IsShown())
		if s then
			local what = kind == "npc" and "npc" or "quest"
			hit.query = what .. ": side:" .. string.lower(s)
			hit.label = s .. (what == "npc" and " people" or " quests")
		end
	end
	-- The icons beside the crests (ns.PageBadges): classes, races, the
	-- profession, the reputation needed. Atlas art by its own name or
	-- Forever's -c60 one; an icon file as it is.
	local art = {}
	for _, b in ipairs(ns.PageBadges(kind, id)) do
		local name = b.atlas and ArtName(b.atlas)
		if name or b.file then
			art[#art + 1] = { name = name, file = b.file, crop = b.crop, query = b.query, label = b.label, more = b.more }
		end
	end
	local right = -(crestsShown * CREST_W + (crestsShown > 0 and GAP - CREST_MARGIN or 0))
	for i, a in ipairs(art) do
		local b = Badge(i)
		if a.file then
			b.icon:SetTexture(a.file)
			b.icon:SetTexCoord(a.crop, 1 - a.crop, a.crop, 1 - a.crop)
		else
			SetArt(b.icon, a.name, a.crop)
		end
		b.query, b.label, b.more = a.query, a.label, a.more
		b:ClearAllPoints()
		b:SetPoint("TOPRIGHT", preview.content, "TOPRIGHT", right - (i - 1) * BADGE_STEP, -(CREST_H - BADGE) / 2)
		b:Show()
	end
	for i = #art + 1, #badges do
		badges[i]:Hide()
	end
	local shown = #art
	-- Room the page's first block leaves for them.
	if shown > 0 then
		headRoom = -right + shown * BADGE_STEP
	else
		headRoom = crestsShown * CREST_W
	end
end

local function ShowPage(kind, id, keepScroll)
	page = { kind = kind, id = id }
	SetCrest(kind, id)
	local head = PageHead(kind, id)
	local typed = box:GetText()
	local job = {
		co = coroutine.create(function() return ns.Details(kind, id, typed) end),
		head = head, keepScroll = keepScroll, page = page,
		timing = NewTiming(ns.NameOf(kind, id)),
	}
	-- Most pages take a millisecond: the first slice now, and only a page
	-- that needs more shows its heading and "..." while it is built.
	if StepPage(job) then
		pageJob = nil
		pageDriver:Hide()
		return
	end
	if not keepScroll then
		local waiting = {}
		for i, l in ipairs(head) do waiting[i] = l end
		waiting[#waiting + 1] = "|cff9d9d9d...|r"
		Render(waiting, false)
	end
	pageJob = job
	pageDriver:Show()
end

pageDriver:SetScript("OnUpdate", function(self)
	local job = pageJob
	if not job or job.page ~= page or StepPage(job) then
		pageJob = nil
		self:Hide()
	end
end)

-- Reward tiles, as the quest log draws them: an icon in the result rows'
-- rounded mask and ring, a count on it, the name beside it in its quality
-- colour; two to a row. An item's tile shows its tooltip and opens its page.
local TILE_ICON, TILE_HEIGHT, TILE_GAP = 26, 30, 4
local TILE_INDENT = 8 -- under their heading, as far in as a list's entries
local tiles = {}
local function Tile(i)
	local t = tiles[i]
	if t then
		return t
	end
	t = CreateFrame("Frame", nil, preview.content)
	t:SetHeight(TILE_HEIGHT)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(TILE_ICON, TILE_ICON)
	t.icon:SetPoint("LEFT", 2, 0)
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = t:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints(t.icon)
		t.icon:AddMaskTexture(mask)
		local ring = t:CreateTexture(nil, "OVERLAY")
		ring:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		local rx, ry = TILE_ICON * 0.2, TILE_ICON * 0.2 - 1
		ring:SetPoint("TOPLEFT", t.icon, "TOPLEFT", -rx, ry)
		ring:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", rx, -ry)
	end
	t.count = t:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", 1, -1)
	t.name = t:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	t.name:SetPoint("LEFT", t.icon, "RIGHT", 6, 0)
	t.name:SetPoint("RIGHT", -2, 0)
	t.name:SetJustifyH("LEFT")
	t:EnableMouse(true)
	t:SetScript("OnEnter", function(self)
		if self.item then
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:SetItemByID(self.item)
			GameTooltip:Show()
		end
	end)
	t:SetScript("OnLeave", function() GameTooltip:Hide() end)
	t:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.item then
			if IsShiftKeyDown() then
				LinkInChat({ kind = "item", id = self.item })
			else
				Follow("item", self.item)
			end
		end
	end)
	tiles[i] = t
	return t
end

-- FillTile shows one reward on a tile: an item, experience or money.
local function FillTile(t, r)
	t.item = r.item
	if r.item then
		local quality = ForeverData.Item(r.item) and ForeverData.Item(r.item).quality
		local cr, cg, cb = QualityColour(quality)
		t.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.item) or KIND_ICON.item)
		t.name:SetText(ns.NameOf("item", r.item))
		t.name:SetTextColor(cr, cg, cb)
		t.count:SetText(r.n and r.n > 1 and tostring(r.n) or "")
	elseif r.xp then
		t.icon:SetTexture(ns.XP_ICON)
		t.name:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or tostring(r.xp))
		t.name:SetTextColor(1, 1, 1)
		t.count:SetText("")
	elseif r.money then
		t.icon:SetTexture(ns.MONEY_ICON)
		t.name:SetText(ns.Money(r.money))
		t.name:SetTextColor(1, 1, 1)
		t.count:SetText("")
	elseif r.faction then
		t.icon:SetTexture(ns.REPUTATION_ICON)
		t.name:SetText(ns.ReputationText(r))
		if r.value >= 0 then
			t.name:SetTextColor(0.25, 1, 0.25)
		else
			t.name:SetTextColor(1, 0.38, 0.25)
		end
		t.count:SetText("")
	end
	t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- TextWidth is how wide a line of the page is, unwrapped.
local measure
local function TextWidth(text)
	if not measure then
		measure = preview.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		measure:SetWordWrap(false)
		measure:Hide()
	end
	measure:SetText(text)
	return measure:GetStringWidth()
end

-- Fit is a list entry's text as much of it as fits on one line, "..." where
-- it is cut off.
local function Fit(text, width)
	if TextWidth(text) <= width then
		return text
	end
	local _, all = ns.CutText(text, math.huge)
	local low, high = 0, all -- the most characters that fit, by halves
	while low < high do
		local middle = math.ceil((low + high) / 2)
		if TextWidth((ns.CutText(text, middle))) <= width then
			low = middle
		else
			high = middle - 1
		end
	end
	return (ns.CutText(text, low))
end

function Render(lines, keepScroll)
	-- A tooltip of something on the page (an item link under the mouse)
	-- goes when another page comes: the mouse never leaves a link whose
	-- text is swapped under it, so nothing else would close it. Not on a
	-- redraw of the same page (keepScroll: the item's tooltip data came in),
	-- where the link stays under the mouse.
	local owner = not keepScroll and GameTooltip:GetOwner()
	-- The owner is a link's text, inside a block, on the page: anything
	-- the page holds, at any depth.
	while owner and owner ~= preview.content and owner.GetParent do
		owner = owner:GetParent()
	end
	if owner == preview.content then
		GameTooltip:Hide()
	end
	local used, y, run = 0, 0, {}
	local function Put(text, right)
		used = used + 1
		local block = Block(used)
		block:ClearAllPoints()
		block:SetPoint("TOPLEFT", preview.content, "TOPLEFT", 0, -y)
		-- The first block (the page's name) keeps clear of the crest.
		local crest = used == 1 and headRoom or 0
		local width = PREVIEW_WIDTH - 44 - crest
		-- A list entry is one line: what its number leaves of the width.
		if right then
			width = width - (right ~= "" and math.min(RIGHT_WIDTH, TextWidth(right)) + RIGHT_GAP or 0)
			text = Fit(text, width - 2)
		end
		block.html:SetWidth(width)
		block.html:SetText(text)
		local height = math.max(1, block.html:GetContentHeight())
		block.html:SetHeight(height)
		block.right:SetText(right or "")
		-- The row is as tall as its taller side: a right-hand text that
		-- wraps must not run into the next row.
		if right then
			height = math.max(height, block.right:GetStringHeight())
		end
		block:SetHeight(height)
		block:Show()
		y = y + height + (right and 2 or 0)
	end
	local function Flush()
		if #run > 0 then
			Put(table.concat(run, "\n"))
			run = {}
		end
	end
	local usedTiles = 0
	local function PutTiles(list)
		local width = (PREVIEW_WIDTH - 44 - TILE_INDENT - TILE_GAP) / 2
		for i, r in ipairs(list) do
			usedTiles = usedTiles + 1
			local t = Tile(usedTiles)
			local column = (i - 1) % 2
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", preview.content, "TOPLEFT", TILE_INDENT + column * (width + TILE_GAP), -y)
			t:SetWidth(width)
			FillTile(t, r)
			t:Show()
			if column == 1 or i == #list then
				y = y + TILE_HEIGHT + 2
			end
		end
		y = y + 2
	end
	for _, line in ipairs(lines) do
		if type(line) == "table" and line.tiles then
			Flush()
			PutTiles(line.tiles)
		elseif type(line) == "table" then
			Flush()
			Put(line[1], line[2])
		else
			run[#run + 1] = line
		end
	end
	Flush()
	for i = used + 1, #blocks do
		blocks[i]:Hide()
	end
	for i = usedTiles + 1, #tiles do
		tiles[i]:Hide()
	end
	preview.content:SetHeight(math.max(1, y + 8))
	if not keepScroll then
		preview.scroll:SetVerticalScroll(0)
	end
	preview:Show()
end

local function ShowPreview()
	local find = finds[chosen]
	history = {}
	if not find then
		page = nil
		preview:Hide()
		return
	end
	ShowPage(find.kind, find.id)
end

-- Follow goes to a linked thing, keeping the page left for Back.
function Follow(kind, id)
	if page then
		history[#history + 1] = page
	end
	ShowPage(kind, id)
end

local function Back()
	local last = table.remove(history)
	if last then
		ShowPage(last.kind, last.id)
	end
end

-- UpdateChips lights the buttons whose filter is in the text.
local IsHere -- below, by DrawRows

local function UpdateChips()
	if not chips then
		return
	end
	local _, kinds, options = ns.Parse(box:GetText())
	local kind = kinds and kinds[1]
	for _, chip in ipairs(chips.kinds) do
		chip:SetActive(chip.value == kind)
	end
	for _, chip in ipairs(chips.qualities) do
		chip:SetActive(options.quality == chip.value)
	end
	chips.dungeons:SetActive(string.find(" " .. string.lower(box:GetText()) .. " ", "%sis:dungeon%s") ~= nil)
	chips.near:SetActive(options.level ~= nil)
	chips.here:SetActive(IsHere(options.zone))
end

-- IsHere tells whether the in: zones are the zone you are in (Here lit),
-- not some other in: typed (in:sm somewhere else).
function IsHere(zones)
	if not zones then
		return false
	end
	local _, _, here = ns.Parse(ns.InWord(GetRealZoneText() or ""))
	if not here.zone or #here.zone ~= #zones then
		return false
	end
	for i, id in ipairs(zones) do
		if here.zone[i] ~= id then
			return false
		end
	end
	return true
end

local function DrawRows()
	UpdateChips()
	local shown = math.min(ROWS, #finds - offset)
	-- The filter words as the bar read them, above the finds.
	local text = box:GetText()
	local described = text:match("%S") and ns.Describe(text)
	local top = described and FILTER_LINE or 0
	if described then
		local count = ""
		if job == nil then
			count = found == 0 and "  ·  nothing found" or ("  ·  %d%s found"):format(found, found >= limit and "+" or "")
		end
		list.filters:SetText(described .. count)
		list.filters:Show()
	else
		list.filters:Hide()
	end
	for i, row in ipairs(rows) do
		row:SetPoint("TOPLEFT", 6, -6 - top - (i - 1) * ROW)
		local find = finds[offset + i]
		if find then
			row.find = find
			-- A quest is the calendar's quest tile, an atlas; SetAtlas sets
			-- the texture's coordinates, so the others set theirs back.
			if find.kind == "quest" and HasAtlas(QUEST_ATLAS) then
				row.icon:SetAtlas(QUEST_ATLAS)
			elseif find.kind == "npc" and Portrait(row.icon, find.id) then
				row.icon:SetTexCoord(unpack(row.coords))
			else
				row.icon:SetTexture(Icon(find))
				row.icon:SetTexCoord(unpack(row.coords))
			end
			row.name:SetText(find.name)
			if find.kind == "item" and find.available == false then
				row.name:SetTextColor(0.5, 0.5, 0.5)
			else
				row.name:SetTextColor(QualityColour(find.quality))
			end
			row.sub:SetText(ns.Subtitle(find))
			row.selected:SetShown(offset + i == chosen)
			row:Show()
		else
			row.find = nil
			row:Hide()
		end
	end
	if shown > 0 or described then
		list:SetHeight(math.max(0, shown) * ROW + top + 12)
		list:Show()
	else
		list:Hide()
	end
end

-- Choose picks a find by place.
-- Choose makes a find the chosen one: lit at once, its page shown at once
-- from the keyboard; from the mouse only once it rests on the row
-- (HOVER_DELAY), so passing over rows does not build a page for each. A
-- page already showing that find is not built again.
local HOVER_DELAY = 0.12
local pendingPage
local function ShowChosen()
	pendingPage = nil
	local find = finds[chosen]
	if find and page and page.kind == find.kind and page.id == find.id and #history == 0 then
		return
	end
	ShowPreview()
end
local function Choose(index, hovered)
	if #finds == 0 then
		return
	end
	chosen = math.max(1, math.min(#finds, index))
	if chosen <= offset then
		offset = chosen - 1
	elseif chosen > offset + ROWS then
		offset = chosen - ROWS
	end
	DrawRows()
	if hovered and C_Timer and C_Timer.After then
		local wait = {}
		pendingPage = wait
		C_Timer.After(HOVER_DELAY, function()
			if pendingPage == wait then
				ShowChosen()
			end
		end)
	else
		ShowChosen()
	end
end

local function Show(results)
	finds = results
	found = #results
	offset, chosen = 0, 1
	pendingPage = nil
	DrawRows()
	ShowPreview()
end

-- Search asks for a search of the box's text: a moment later, in steps.
local function Search()
	local text = box:GetText()
	ForeverSearchDB.text = text
	box.hint:SetShown(text == "")
	job = nil
	if not text:match("%S") then
		driver:Hide()
		Show({})
		return
	end
	jobText, startAt = text, GetTime() + PAUSE
	driver:Show()
end

driver:SetScript("OnUpdate", function(self)
	if not job then
		if GetTime() < startAt then
			return
		end
		local text = jobText
		local words = ns.Parse(text)
		local grouped = not words:match("%S")
		limit = grouped and FILTER_LIMIT or 30
		job = coroutine.create(function()
			return ns.Results(text, limit, { yieldEvery = STEP, grouped = grouped })
		end)
		searchTiming = NewTiming(text)
	end
	local start = debugprofilestop()
	local until_ = start + BUDGET
	ns.SliceUntil(until_)
	repeat
		local ok, results = coroutine.resume(job)
		if not ok then
			ns.SliceUntil(nil)
			job = nil
			self:Hide()
			geterrorhandler()(results)
			return
		end
		if coroutine.status(job) == "dead" then
			ns.SliceUntil(nil)
			TimeSlice(searchTiming, debugprofilestop() - start)
			ns.timings.search = searchTiming
			job = nil
			self:Hide()
			Show(results or {})
			return
		end
	until debugprofilestop() >= until_
	ns.SliceUntil(nil)
	TimeSlice(searchTiming, debugprofilestop() - start)
end)

local function Close()
	bar:Hide()
end

-- SearchFor puts words in the bar and searches: a search link's, or a
-- zone's in: word.
function SearchFor(text)
	box:SetText(text)
	box:SetCursorPosition(#text)
	Search()
	startAt = 0
end

local function MakeRow(i)
	local row = CreateFrame("Button", nil, list)
	row:SetSize(WIDTH - 12, ROW)
	row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW)
	row:RegisterForClicks("LeftButtonUp")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(0.3, 0.55, 1, 0.22)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 4, 0)
	-- The Cooldown Manager's icon dressing, as the other addons use it: its
	-- rounded mask and border ring over the uncropped picture. A plain dark
	-- square edge stands in on a client without those atlases.
	if HasAtlas("UI-HUD-CoolDownManager-Mask") and HasAtlas("UI-HUD-CoolDownManager-IconOverlay") then
		local mask = row:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints(row.icon)
		row.icon:AddMaskTexture(mask)
		row.coords = { 0, 1, 0, 1 }
		-- A black fill under the picture: a creature portrait comes as a
		-- circle, and its corners show this instead of the window.
		local fill = row:CreateTexture(nil, "BORDER")
		fill:SetColorTexture(0, 0, 0, 1)
		fill:SetAllPoints(row.icon)
		fill:AddMaskTexture(mask)
		local ring = row:CreateTexture(nil, "OVERLAY")
		ring:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		ring:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -RING_X, RING_Y)
		ring:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", RING_X, -RING_Y)
	else
		row.coords = { 0.08, 0.92, 0.08, 0.92 }
		row.icon:SetTexCoord(unpack(row.coords))
		local edge = row:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(0, 0, 0, 1)
		edge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
	end
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
	row.name:SetPoint("RIGHT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
	row.sub:SetPoint("RIGHT", -6, 0)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		Choose(offset + i, true)
	end)
	row:SetScript("OnClick", function(self)
		if IsShiftKeyDown() then
			LinkInChat(self.find)
		elseif self.find and self.find.kind == "zone" then
			-- A zone's row searches that zone.
			SearchFor(ns.InWord(self.find.name))
		end
		box:SetFocus()
	end)
	return row
end

-- Apply sets or lifts one filter in the text, as a button does, and searches.
local function Apply(which, value)
	local text = ns.SetFilter(box:GetText(), which, value)
	box:SetText(text)
	box:SetCursorPosition(#text)
	Search()
	startAt = 0
	box:SetFocus()
end

-- Chip is a button of the filter row; SetActive lights it.
local function Chip(parent, label, onClick, colour)
	local chip = CreateFrame("Button", nil, parent, "BackdropTemplate")
	chip:SetBackdrop(BACKDROP)
	chip:SetHeight(22)
	chip.text = chip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	chip.text:SetPoint("CENTER")
	chip.text:SetText(label)
	if colour then
		chip.text:SetTextColor(colour[1], colour[2], colour[3])
	end
	chip:SetWidth(chip.text:GetStringWidth() + 18)
	function chip:SetActive(on)
		self.active = on
		self:SetBackdropColor(on and 0.25 or 0.1, on and 0.45 or 0.1, on and 0.8 or 0.12, on and 0.9 or 0.8)
		self:SetBackdropBorderColor(on and 0.5 or 0.35, on and 0.7 or 0.35, on and 1 or 0.4, 0.9)
	end
	chip:SetActive(false)
	chip:SetScript("OnClick", function(self) onClick(self) end)
	return chip
end

local function MakeChips()
	local row = Panel(nil, bar)
	row:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
	row:SetSize(WIDTH + 6 + PREVIEW_WIDTH, CHIPS_HEIGHT) -- spans both columns, like the bar
	row.kinds, row.qualities = {}, {}
	local x = 6
	local function Place(chip, gap)
		chip:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + chip:GetWidth() + (gap or 3)
	end
	for i, k in ipairs(KIND_CHIPS) do
		local chip = Chip(row, k[2], function() Apply("kind", k[1]) end)
		chip.value = k[1]
		row.kinds[#row.kinds + 1] = chip
		Place(chip)
	end
	-- Dungeons: is:dungeon, which only zones pass, so any other kind goes.
	-- It replaces another is: word (is:rare and is:dungeon find nothing).
	row.dungeons = Chip(row, "Dungeons", function(self)
		local text = ns.SetFilter(box:GetText(), "kind", nil)
		text = ns.SetFilter(text, "is", not self.active and "dungeon" or nil)
		box:SetText(text)
		box:SetCursorPosition(#text)
		Search()
		startAt = 0
		box:SetFocus()
	end)
	Place(row.dungeons, 10)
	for i, q in ipairs(QUALITY_CHIPS) do
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q[1]]
		local chip = Chip(row, "", function(self)
			Apply("q", not self.active and q[2] or nil)
		end)
		chip:SetWidth(24)
		chip.swatch = chip:CreateTexture(nil, "ARTWORK")
		chip.swatch:SetSize(10, 10)
		chip.swatch:SetPoint("CENTER")
		chip.swatch:SetColorTexture(c and c.r or 1, c and c.g or 1, c and c.b or 1)
		chip.value = q[1]
		chip:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(q[2] .. " or better")
			GameTooltip:Show()
		end)
		chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.qualities[#row.qualities + 1] = chip
		Place(chip, i == #QUALITY_CHIPS and 10 or 3)
	end
	row.near = Chip(row, "Near me", function(self)
		local level = UnitLevel("player") or 1
		Apply("lvl", not self.active and ("%d-%d"):format(math.max(1, level - 3), level + 3) or nil)
	end)
	Place(row.near)
	row.here = Chip(row, "Here", function(self)
		Apply("in", not self.active and ns.InWord(GetRealZoneText() or "") or nil)
	end)
	Place(row.here)
	return row
end

-- One block of the preview: a SimpleHTML, as its names are links (a click
-- shows that thing, Shift-click an item links it in chat, hovering an item
-- shows it), and a right-aligned string for a list entry's number.
local function OnLinkClick(_, link)
	local kind, id = string.match(link, "^fsearch:(%a+):(%d+)$")
	local query = string.match(link, "^fsearch:find:(.+)$")
	local wayKind, wayID, wayZone, wayX, wayY = string.match(link, "^fsearch:way:(%a+):(%d+):(%d+):(%d+):(%d+)$")
	if link == "fsearch:back" then
		Back()
	elseif wayKind then
		local x, y = tonumber(wayX) / 100, tonumber(wayY) / 100
		if ns.SetWaypoint(wayKind, tonumber(wayID), tonumber(wayZone), x, y) then
			print(("ForeverSearch: waypoint to %s, %s %.1f, %.1f"):format(ns.NameOf(wayKind, tonumber(wayID)), ns.NameOf("zone", tonumber(wayZone)), x, y))
		else
			print("ForeverSearch: no waypoint can be set there")
		end
	elseif query then
		SearchFor((string.gsub(query, ",", " ")))
	elseif kind then
		id = tonumber(id)
		if IsShiftKeyDown() and kind == "item" then
			LinkInChat({ kind = kind, id = id })
		else
			Follow(kind, id)
		end
	end
	box:SetFocus()
end

local function OnLinkEnter(self, link)
	local id = string.match(link, "^fsearch:item:(%d+)$")
	if id then
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetItemByID(tonumber(id))
		GameTooltip:Show()
	end
end

local function OnBackButton(_, button)
	if button == "Button4" then
		Back()
	end
end

function Block(i)
	if blocks[i] then
		return blocks[i]
	end
	local block = CreateFrame("Frame", nil, preview.content)
	block:SetWidth(PREVIEW_WIDTH - 44)
	block.html = CreateFrame("SimpleHTML", nil, block)
	block.html:SetPoint("TOPLEFT")
	block.html:SetFontObject("p", GameFontHighlightSmall)
	block.html:SetJustifyH("p", "LEFT") -- the font object centres
	block.html:SetSpacing("p", 2)
	block.html:SetHyperlinksEnabled(true)
	block.html:SetScript("OnHyperlinkClick", OnLinkClick)
	block.html:SetScript("OnHyperlinkEnter", OnLinkEnter)
	block.html:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
	block.html:SetScript("OnMouseUp", OnBackButton)
	block.right = block:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	block.right:SetPoint("TOPRIGHT")
	block.right:SetWidth(RIGHT_WIDTH)
	block.right:SetJustifyH("RIGHT")
	blocks[i] = block
	return block
end

local function MakeBar()
	bar = Panel("ForeverSearchBar", UIParent)
	-- The bar and the filter buttons span both columns; under them the finds
	-- on the left, the page on the right.
	bar:SetSize(WIDTH + 6 + PREVIEW_WIDTH, BAR_HEIGHT)
	bar:SetPoint("TOP", UIParent, "TOP", 0, -140)
	bar:SetFrameStrata("DIALOG")
	bar:SetToplevel(true)
	bar:EnableMouse(true)
	bar:Hide()
	if type(UISpecialFrames) == "table" then
		tinsert(UISpecialFrames, "ForeverSearchBar") -- Escape closes it
	end

	local glass = bar:CreateTexture(nil, "ARTWORK")
	bar.glass = glass
	glass:SetSize(22, 22)
	glass:SetPoint("LEFT", 12, 0)
	glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

	box = CreateFrame("EditBox", nil, bar)
	box:SetFontObject(GameFontHighlightLarge)
	box:SetPoint("LEFT", glass, "RIGHT", 8, 0)
	box:SetPoint("RIGHT", -14, 0)
	box:SetHeight(BAR_HEIGHT - 12)
	box:SetAutoFocus(false)
	box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
	box.hint:SetPoint("LEFT")
	box.hint:SetText("Items, creatures, objects, quests, zones   (item: q:rare lvl:40-50 in:barrens)")
	box:SetScript("OnTextChanged", function(_, typed)
		if typed then
			Search()
		end
	end)
	box:SetScript("OnArrowPressed", function(_, key)
		if key == "UP" then
			Choose(chosen - 1)
		elseif key == "DOWN" then
			Choose(chosen + 1)
		end
	end)
	box:SetScript("OnEnterPressed", function()
		if IsShiftKeyDown() then
			LinkInChat(finds[chosen])
		else
			Close()
		end
	end)
	box:SetScript("OnEscapePressed", Close)
	-- Tab steps through the kinds (All, Items, Creatures, ...), Shift-Tab back.
	box:SetScript("OnTabPressed", function()
		local _, kinds = ns.Parse(box:GetText())
		local now = 1
		for i, k in ipairs(KIND_CHIPS) do
			if k[1] == (kinds and kinds[1]) then
				now = i
			end
		end
		local step = IsShiftKeyDown() and -1 or 1
		Apply("kind", KIND_CHIPS[(now - 1 + step) % #KIND_CHIPS + 1][1])
	end)

	chips = MakeChips()
	list = Panel(nil, bar)
	list:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -4)
	list:SetWidth(WIDTH)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(math.max(0, #finds - ROWS), offset - delta * 3))
		DrawRows()
	end)
	list:Hide()
	list.filters = list:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	list.filters:SetPoint("TOPLEFT", 12, -9)
	list.filters:SetPoint("RIGHT", -12, 0)
	list.filters:SetJustifyH("LEFT")
	list.filters:SetTextColor(0.4, 0.75, 1)
	rows = {}
	for i = 1, ROWS do
		rows[i] = MakeRow(i)
	end

	preview = Panel(nil, bar)
	preview:SetPoint("TOPRIGHT", chips, "BOTTOMRIGHT", 0, -4)
	preview:SetSize(PREVIEW_WIDTH, ROWS * ROW + 12 + FILTER_LINE)
	preview:EnableMouse(true)
	preview.scroll = CreateFrame("ScrollFrame", nil, preview, "UIPanelScrollFrameTemplate")
	preview.scroll:SetPoint("TOPLEFT", 12, -12)
	preview.scroll:SetPoint("BOTTOMRIGHT", -30, 12)
	preview.content = CreateFrame("Frame", nil, preview.scroll)
	preview.content:SetSize(PREVIEW_WIDTH - 44, 1)
	preview.scroll:SetScrollChild(preview.content)
	preview.crest = preview.content:CreateTexture(nil, "OVERLAY")
	preview.crest:SetSize(CREST_W, CREST_H)
	preview.crest:SetPoint("TOPRIGHT", preview.content, "TOPRIGHT", 0, 0)
	preview.crest:Hide()
	preview.crest2 = preview.content:CreateTexture(nil, "OVERLAY")
	preview.crest2:SetSize(CREST_W, CREST_H)
	preview.crest2:SetPoint("TOPRIGHT", preview.crest, "TOPLEFT", 0, 0)
	for _, which in ipairs({ "crest", "crest2" }) do
		local hit = CreateFrame("Frame", nil, preview.content)
		hit:SetAllPoints(preview[which])
		Clickable(hit)
		hit:Hide()
		preview[which .. "Hit"] = hit
	end
	preview.crest2:Hide()
	preview:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" then
			Back()
		end
		box:SetFocus()
	end)
	preview:Hide()

	bar:SetScript("OnShow", function()
		-- In a dungeon or raid the text starts with in:<that instance>;
		-- anywhere else an in: put there earlier is taken off again.
		local text = ForeverSearchDB.text or ""
		local before = ForeverSearchDB.prefill
		if before and string.sub(text, 1, #before) == before then
			text = string.sub(text, #before + 1)
		end
		local prefill
		local inInstance, kind = IsInInstance()
		local here = GetRealZoneText()
		if inInstance and (kind == "party" or kind == "raid") and ns.ZoneByName(here) then
			prefill = ns.InWord(here) .. " "
			text = prefill .. text
		end
		ForeverSearchDB.prefill = prefill
		box:SetText(text)
		Search()
		startAt = 0 -- reopening: no need to wait
		bar:RegisterEvent("GLOBAL_MOUSE_DOWN")
		box:SetFocus()
		-- Typing replaces the words after the in:, not the in: itself.
		box:SetCursorPosition(#text)
		box:HighlightText(prefill and #prefill or 0, -1)
	end)
	bar:SetScript("OnHide", function()
		box:ClearFocus()
		bar:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		job = nil
		driver:Hide()
	end)

	-- A click outside the window gives the keyboard back to the game (Enter
	-- opens chat), the bar staying open; a click on the window takes it again.
	bar:SetScript("OnEvent", function()
		if not (bar:IsMouseOver() or chips:IsMouseOver() or list:IsMouseOver() or preview:IsMouseOver()) then
			box:ClearFocus()
		end
	end)
	bar:SetScript("OnMouseDown", function() box:SetFocus() end)
	for _, part in ipairs({ list, chips }) do
		part:EnableMouse(true) -- a click between the rows or buttons stays here
		part:SetScript("OnMouseDown", function() box:SetFocus() end)
	end
end

local function Open(text)
	if not ns.Ready() then
		print("|cffffd100ForeverSearch:|r needs ForeverData (contract 1).")
		return
	end
	if not bar then
		MakeBar()
	end
	if text and text ~= "" then
		ForeverSearchDB.text = text
	end
	if bar:IsShown() then
		bar:GetScript("OnShow")()
	else
		bar:Show()
	end
end

-- For the key binding (Bindings.xml).
BINDING_HEADER_FOREVERSEARCH = "ForeverSearch"
BINDING_NAME_FOREVERSEARCH_TOGGLE = "Open or close the search bar"
function ForeverSearch_Toggle()
	if bar and bar:IsShown() then
		Close()
	else
		Open()
	end
end

-- The key is Ctrl-K unless you chose another: bound once for the account's
-- key bindings and once for a character's own, so one you take off stays
-- off. Not over a key of yours for the bar, nor over what Ctrl-K does
-- already. A few seconds after the world is there, so your own bindings are
-- in before they are saved; not in combat, where no key may be bound.
local DEFAULT_KEY, TOGGLE = "CTRL-K", "FOREVERSEARCH_TOGGLE"
local KEY_DELAY = 5 -- seconds
local events = CreateFrame("Frame")
local function BindDefaultKey()
	local given = ForeverSearchDB.keyGiven or {}
	ForeverSearchDB.keyGiven = given
	local set = GetCurrentBindingSet()
	local whose = set == 2 and UnitGUID("player") or "account"
	if given[whose] then
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED") -- when it is over
		return
	end
	given[whose] = true
	local action = GetBindingAction(DEFAULT_KEY)
	if not GetBindingKey(TOGGLE) and (action == nil or action == "") and SetBinding(DEFAULT_KEY, TOGGLE) then
		SaveBindings(set)
	end
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("TOOLTIP_DATA_UPDATE")
-- REDRAWS caps how often one page is drawn again for late tooltip data:
-- drawing asks for the tooltip again, which may start a new lookup.
local REDRAWS = 5
-- The search lists are built after login, a few milliseconds a frame, so
-- the first search does not stall a frame building them (130 ms offline).
local PREPARE_BUDGET = 0.004 -- seconds of work a frame
local preparer = CreateFrame("Frame")
local function Clock()
	return debugprofilestop() / 1000
end
local function StartPreparing()
	if not (ns.Ready() and ForeverData.PrepareSearch and debugprofilestop) then
		return
	end
	preparer:SetScript("OnUpdate", function(self)
		local ok, done = pcall(ForeverData.PrepareSearch, PREPARE_BUDGET, Clock)
		if not ok or done then
			self:SetScript("OnUpdate", nil)
		end
	end)
end
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg)
	if event == "PLAYER_LOGIN" then
		StartPreparing()
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(KEY_DELAY, BindDefaultKey)
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent(event)
		BindDefaultKey()
	elseif event == "ADDON_LOADED" and arg == ADDON then
		ForeverSearchDB = ForeverSearchDB or {}
		self:UnregisterEvent("ADDON_LOADED")
	elseif bar and bar:IsShown() and page and page.kind == "item" and (page.redraws or 0) < REDRAWS
		and (event == "GET_ITEM_INFO_RECEIVED" and page.id == arg
			or event == "TOOLTIP_DATA_UPDATE" and (arg == nil or arg == ns.tooltipData)) then
		-- The item, or a part of its tooltip, came: the page again, where
		-- it was scrolled to.
		local redraws = (page.redraws or 0) + 1
		ShowPage(page.kind, page.id, true)
		page.redraws = redraws
	end
end)

SLASH_FOREVERSEARCH1 = "/find"
SLASH_FOREVERSEARCH2 = "/foreversearch"
-- TimingLine says what one search or page cost.
local function TimingLine(label, t)
	if not t then
		return label .. ": none yet"
	end
	local line = ("%s \"%s\": %.1f ms of work over %d frame%s, at most %.1f ms in one"):format(
		label, t.what, t.work, t.frames, t.frames == 1 and "" or "s", t.longest)
	if t.draw > 0 then
		line = line .. (", drawn in %.1f ms"):format(t.draw)
	end
	return line
end

SlashCmdList.FOREVERSEARCH = function(text)
	text = text and text:match("^%s*(.-)%s*$") or ""
	-- /find time: what the last search and page cost. (To search for the
	-- word itself, type it in the bar.)
	if text == "time" then
		print("ForeverSearch: " .. TimingLine("last search", ns.timings.search))
		print("ForeverSearch: " .. TimingLine("last page", ns.timings.page))
		return
	end
	if text == "" and bar and bar:IsShown() then
		Close()
		return
	end
	Open(text)
end
