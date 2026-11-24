-- ForeverSearch, the bar: a floating search bar near the top of the screen,
-- finds appearing in rows under it as you type, and the chosen find's
-- details in a panel beside them. /find [text] or the key bound under
-- Key Bindings > AddOns opens it, Escape closes it.
--
--   typing        searches as you type; words narrow it: item: npc: object:
--                 quest: zone:, q:rare (quality), lvl:40-50, in:hinterlands
--   Up, Down      choose a find (its details show beside the list)
--   Enter         closes, keeping the text for next time
--   Shift-Enter   or Shift-click: links the chosen item in chat
--   mouse         hover or click chooses; the wheel scrolls the finds
--   in a dungeon or raid the bar opens with in:<that instance> in front of
--                 the text (in:blackrock-depths), taken off again elsewhere;
--                 a line above the finds says how the filter words were read
local ADDON, ns = ...

local WIDTH = 520
local BAR_HEIGHT = 44
local ROW, ROWS = 36, 10
local PREVIEW_WIDTH = 380
local KIND_ICON = {
	npc = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
	object = "Interface\\Icons\\INV_Misc_Bag_10",
	quest = "Interface\\GossipFrame\\AvailableQuestIcon",
	zone = "Interface\\Icons\\INV_Misc_Map_01",
	item = "Interface\\Icons\\INV_Misc_QuestionMark",
}
local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local bar, box, list, rows, preview
local finds, offset, chosen = {}, 0, 1

-- A search runs in steps over several frames (see ForeverData.Search),
-- starting a moment after the last key, so typing stays smooth.
local PAUSE = 0.1      -- seconds after the last key
local BUDGET = 6       -- milliseconds of searching a frame
local STEP = 500       -- names a step (each may be decoded for a filter)
local job, startAt, jobText
local FILTER_LINE = 20 -- height of the line saying how the filter words were read
local driver = CreateFrame("Frame")
driver:Hide()

local function Panel(name, parent)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
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

local function Icon(find)
	if find.kind == "item" and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(find.id) or KIND_ICON.item
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

local function ShowPreview()
	local find = finds[chosen]
	if not find then
		preview:Hide()
		return
	end
	local r, g, b = QualityColour(find.quality)
	local head = ("|cff%02x%02x%02x%s|r\n|cff9d9d9d%s %d|r"):format(r * 255, g * 255, b * 255, find.name,
		ns.KIND_LABEL[find.kind] or find.kind, find.id)
	preview.text:SetText(head .. "\n\n" .. table.concat(ns.Details(find.kind, find.id), "\n"))
	preview.child:SetHeight(preview.text:GetStringHeight() + 8)
	preview.scroll:SetVerticalScroll(0)
	preview:Show()
end

local function DrawRows()
	local shown = math.min(ROWS, #finds - offset)
	-- The filter words as the bar read them, above the finds.
	local text = box:GetText()
	local described = text:match("%S") and ns.Describe(text)
	local top = described and FILTER_LINE or 0
	if described then
		list.filters:SetText(described .. (#finds == 0 and job == nil and "  ·  nothing found" or ""))
		list.filters:Show()
	else
		list.filters:Hide()
	end
	for i, row in ipairs(rows) do
		row:SetPoint("TOPLEFT", 6, -6 - top - (i - 1) * ROW)
		local find = finds[offset + i]
		if find then
			row.find = find
			row.icon:SetTexture(Icon(find))
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

local function Choose(index)
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
	ShowPreview()
end

local function Show(results)
	finds = results
	offset, chosen = 0, 1
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
		job = coroutine.create(function()
			return ns.Results(text, 30, { yieldEvery = STEP })
		end)
	end
	local until_ = debugprofilestop() + BUDGET
	repeat
		local ok, results = coroutine.resume(job)
		if not ok then
			job = nil
			self:Hide()
			geterrorhandler()(results)
			return
		end
		if coroutine.status(job) == "dead" then
			job = nil
			self:Hide()
			Show(results or {})
			return
		end
	until debugprofilestop() >= until_
end)

local function Close()
	bar:Hide()
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
	row.icon:SetSize(ROW - 8, ROW - 8)
	row.icon:SetPoint("LEFT", 4, 0)
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
	row:SetScript("OnEnter", function() Choose(offset + i) end)
	row:SetScript("OnClick", function(self)
		if IsShiftKeyDown() then
			LinkInChat(self.find)
		end
		box:SetFocus()
	end)
	return row
end

local function MakeBar()
	bar = Panel("ForeverSearchBar", UIParent)
	bar:SetSize(WIDTH, BAR_HEIGHT)
	bar:SetPoint("TOP", UIParent, "TOP", -(PREVIEW_WIDTH + 6) / 2, -140)
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

	list = Panel(nil, bar)
	list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
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
	preview:SetPoint("TOPLEFT", bar, "TOPRIGHT", 6, 0)
	preview:SetSize(PREVIEW_WIDTH, BAR_HEIGHT + 4 + ROWS * ROW + 12)
	preview:EnableMouse(true)
	preview.scroll = CreateFrame("ScrollFrame", nil, preview, "UIPanelScrollFrameTemplate")
	preview.scroll:SetPoint("TOPLEFT", 12, -12)
	preview.scroll:SetPoint("BOTTOMRIGHT", -30, 12)
	preview.child = CreateFrame("Frame", nil, preview.scroll)
	preview.child:SetSize(PREVIEW_WIDTH - 44, 1)
	preview.scroll:SetScrollChild(preview.child)
	preview.text = preview.child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	preview.text:SetPoint("TOPLEFT")
	preview.text:SetWidth(PREVIEW_WIDTH - 44)
	preview.text:SetJustifyH("LEFT")
	preview.text:SetJustifyV("TOP")
	preview.text:SetSpacing(2)
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
		box:SetFocus()
		-- Typing replaces the words after the in:, not the in: itself.
		box:SetCursorPosition(#text)
		box:HighlightText(prefill and #prefill or 0, -1)
	end)
	bar:SetScript("OnHide", function()
		box:ClearFocus()
		job = nil
		driver:Hide()
	end)
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
	if name == ADDON then
		ForeverSearchDB = ForeverSearchDB or {}
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

SLASH_FOREVERSEARCH1 = "/find"
SLASH_FOREVERSEARCH2 = "/foreversearch"
SlashCmdList.FOREVERSEARCH = function(text)
	text = text and text:match("^%s*(.-)%s*$") or ""
	if text == "" and bar and bar:IsShown() then
		Close()
		return
	end
	Open(text)
end
