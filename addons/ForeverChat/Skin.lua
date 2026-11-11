-- Forever's art on the chat frame.
--
-- Forever reskinned the modern interface with its own set of textures
-- (the atlases ending in "-c60": near-black panels with a thin bronze
-- edge and cut corners, gold for whatever is selected), but the chat
-- frame still wears the 2004 tab, border and input-box textures. This
-- puts the Forever pieces on it:
--
--   tabs         common-internaltab, gold outline on the selected one
--   window       the tooltip's thin bronze border, fading with the
--                background exactly as the game fades that
--   input box    the same border, on a dark fill: a slim extension of
--                the window rather than a separate box
--
-- The buttons beside the chat (menu, channels, voice, friends) are left
-- exactly as the game draws them.
--
-- Blizzard's regions are only ever asked to draw nothing; everything new
-- is a texture of our own, kept in tables here and never in a field of a
-- Blizzard frame. Sizes, anchors, fading, colours and the chat settings
-- stay Blizzard's.

local _, ns = ...

local Skin = {}
ns.Skin = Skin

-- Forever's variant of an atlas when there is one, else the plain one,
-- else nil and the piece that wanted it is left as Blizzard drew it.
local function Atlas(name)
	local getInfo = C_Texture and C_Texture.GetAtlasInfo
	if not getInfo then
		return nil
	end
	if getInfo(name .. "-c60") then
		return name .. "-c60"
	end
	if getInfo(name) then
		return name
	end
	return nil
end

local art = {} -- the atlases found, filled in Init

-- Sizes of some frames are secret values to addon code; none of the chat
-- tabs' should be, but arithmetic on one would be an error.
local IsSecret = _G.issecretvalue or function() return false end

local function Blank(texture)
	if texture and texture.SetTexture then
		texture:SetTexture(nil)
	end
end

---------------------------------------------------------------------------
-- Window border

local BORDER_PIECES = {
	"TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}
local CORNER = 7 -- the tooltip border's corner is 7 by 7
local OUTSET = 2 -- its line sits two pixels in from the corner's edge
local BORDER_STRENGTH = 2.2 -- border alpha against the background's

local borders = {} -- list of { background = texture, alpha = number, pieces = {...} }

-- The eight pieces of the border, drawn by `frame` around `background`,
-- with the line on the background's edge.
local function BuildBorder(frame, background)
	local pieces = {}
	local function Piece(atlas)
		local texture = frame:CreateTexture(nil, "BORDER")
		texture:SetAtlas(atlas)
		pieces[#pieces + 1] = texture
		return texture
	end
	local topLeft = Piece(art.cornerTopLeft)
	topLeft:SetSize(CORNER, CORNER)
	topLeft:SetPoint("TOPLEFT", background, "TOPLEFT", -OUTSET, OUTSET)
	local topRight = Piece(art.cornerTopRight)
	topRight:SetSize(CORNER, CORNER)
	topRight:SetPoint("TOPRIGHT", background, "TOPRIGHT", OUTSET, OUTSET)
	local bottomLeft = Piece(art.cornerBottomLeft)
	bottomLeft:SetSize(CORNER, CORNER)
	bottomLeft:SetPoint("BOTTOMLEFT", background, "BOTTOMLEFT", -OUTSET, -OUTSET)
	local bottomRight = Piece(art.cornerBottomRight)
	bottomRight:SetSize(CORNER, CORNER)
	bottomRight:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", OUTSET, -OUTSET)

	local top = Piece(art.edgeTop)
	top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
	top:SetPoint("BOTTOMRIGHT", topRight, "BOTTOMLEFT")
	local bottom = Piece(art.edgeBottom)
	bottom:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT")
	local left = Piece(art.edgeLeft)
	left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
	left:SetPoint("BOTTOMRIGHT", bottomLeft, "TOPRIGHT")
	local right = Piece(art.edgeRight)
	right:SetPoint("TOPLEFT", topRight, "BOTTOMLEFT")
	right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT")
	return pieces
end

local function AddBorder(frame, background)
	borders[#borders + 1] = { background = background, alpha = -1, pieces = BuildBorder(frame, background) }
end

-- The game fades the chat background in when the mouse is over the chat
-- and back out to the opacity set in the chat settings. The border
-- follows whatever the background is doing.
local function UpdateBorders()
	for _, border in ipairs(borders) do
		local alpha = border.background:GetAlpha() * BORDER_STRENGTH
		if alpha > 1 then
			alpha = 1
		end
		if alpha ~= border.alpha then
			border.alpha = alpha
			for _, piece in ipairs(border.pieces) do
				piece:SetAlpha(alpha)
			end
		end
	end
end

-- Chat lines start at the frame's own left edge, and the game puts the
-- background's edge, where the border is, two pixels left of that. The
-- background is moved out a little further, so the text gets some air.
-- The tabs, the side buttons and the input box hang off the background
-- and move with it; the text and the Edit Mode position do not change.
local BLIZZARD_PAD = 2
local WINDOW_PAD = 3

local padded = {}

local function PadBackground(frame)
	if not padded[frame] then
		return
	end
	local name = frame:GetName()
	local background = name and _G[name .. "Background"]
	if not background then
		return
	end
	local points = {}
	for i = 1, background:GetNumPoints() do
		local point, relativeTo, relativePoint, _, y = background:GetPoint(i)
		if (point == "TOPLEFT" or point == "BOTTOMLEFT") and relativeTo == frame then
			points[#points + 1] = { point, relativePoint, y }
		end
	end
	for _, anchor in ipairs(points) do
		background:SetPoint(anchor[1], frame, anchor[2], -(BLIZZARD_PAD + WINDOW_PAD), anchor[3])
	end
end

local function SkinWindow(frame)
	local name = frame:GetName()
	local background = name and _G[name .. "Background"]
	if not background or not art.border then
		return
	end
	padded[frame] = true
	PadBackground(frame)
	for _, piece in ipairs(BORDER_PIECES) do
		Blank(_G[name .. piece])
		Blank(_G[name .. "ButtonFrame" .. piece])
	end
	Blank(_G[name .. "ButtonFrameBackground"])
	AddBorder(frame, background)
end

---------------------------------------------------------------------------
-- Tabs

local TAB_PIECES = {
	"Left", "Middle", "Right",
	"ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight",
}

local TAB_TOP = 7 -- art inset from the top of the tab button
local TAB_BOTTOM = 0 -- and from its bottom

-- The gold outline of the selected tab and the pale one of the hovered
-- tab are drawn smaller in their textures than the tab itself: laid over
-- the same rectangle they float a few pixels inside the bronze edge, and
-- unevenly so once the tab is stretched to its text. Measured in the
-- 96 by 30 art, the tab's edge runs through 4.5 from the left, right and
-- top, the selected outline through 8, the hover outline through 8.5.
-- So each outline is drawn on a rectangle that much larger than the tab
-- (in art pixels: to each side, and above), scaled with the tab, which
-- puts its line on the tab's edge at any width. The bottoms stay level.
local ART_WIDTH, ART_HEIGHT = 96, 30
local SELECTED_OVERHANG = { side = 4.2, top = 4.77 }
local HOVER_OVERHANG = { side = 4.86, top = 5.58 }

local function PlaceOutline(texture, body, overhang, width, height)
	local side = overhang.side * width / ART_WIDTH
	local top = overhang.top * height / ART_HEIGHT
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", body, "TOPLEFT", -side, top)
	texture:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", side, 0)
end

local tabs = {} -- tab -> { selected = texture }

local function UpdateTab(tab, selected)
	local parts = tabs[tab]
	if not parts then
		return
	end
	parts.selected:SetShown(selected and true or false)
	-- Whisper tabs carry the colour of their chat type; Blizzard has just
	-- put it on the text, and the outline takes it too.
	local color = tab.selectedColorTable
	if color then
		parts.selected:SetDesaturated(true)
		parts.selected:SetVertexColor(color.r, color.g, color.b)
	else
		parts.selected:SetDesaturated(false)
		parts.selected:SetVertexColor(1, 1, 1)
		local text = tab:GetFontString()
		if text and selected then
			text:SetTextColor(1, 1, 1)
		end
	end
end

local function IsTabSelected(frame)
	if not frame.isDocked then
		return true
	end
	local dock = _G.GENERAL_CHAT_DOCK
	return dock ~= nil and _G.FCFDock_GetSelectedWindow ~= nil and FCFDock_GetSelectedWindow(dock) == frame
end

local function SkinTab(frame)
	local name = frame:GetName()
	local tab = name and _G[name .. "Tab"]
	if not tab or tabs[tab] or not art.tab then
		return
	end
	for _, key in ipairs(TAB_PIECES) do
		local piece = tab[key]
		if piece then
			piece:SetAlpha(0)
		end
	end
	-- The tab button is 32 high with its text low in it. The art takes
	-- the lower 25, which puts its foot on the window's top edge.
	local body = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
	body:SetAtlas(art.tab)
	body:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -TAB_TOP)
	body:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, TAB_BOTTOM)

	local selected = tab:CreateTexture(nil, "BORDER", nil, 1)
	selected:SetAtlas(art.tabSelected or art.tab)
	selected:SetAllPoints(body)
	selected:Hide()

	local hover
	if art.tabHover then
		hover = tab:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAtlas(art.tabHover)
		hover:SetAllPoints(body)
		hover:SetBlendMode("ADD")
	end

	-- The game resizes tabs to their names and to the room in the dock.
	local function Layout(_, tabWidth, tabHeight)
		if IsSecret(tabWidth) or IsSecret(tabHeight) or type(tabWidth) ~= "number" or type(tabHeight) ~= "number" then
			return
		end
		local width, height = tabWidth - 2, tabHeight - TAB_TOP - TAB_BOTTOM
		if width <= 0 or height <= 0 then
			return
		end
		if art.tabSelected then
			PlaceOutline(selected, body, SELECTED_OVERHANG, width, height)
		end
		if hover then
			PlaceOutline(hover, body, HOVER_OVERHANG, width, height)
		end
	end
	tab:HookScript("OnSizeChanged", Layout)
	local ok, tabWidth, tabHeight = pcall(tab.GetSize, tab)
	if ok then
		Layout(tab, tabWidth, tabHeight)
	end

	tabs[tab] = { selected = selected }
	UpdateTab(tab, IsTabSelected(frame))
end

---------------------------------------------------------------------------
-- Input box

local EDIT_PIECES = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }
-- The game's input box is 32 high and hangs 2 below the chat frame, 5
-- further left and 16 further right. These insets put the box's border
-- on the window's: the sides in line with the window's sides, and the
-- top on the window's bottom line, so the two share it.
local EDIT_LEFT = 3 - WINDOW_PAD
local EDIT_RIGHT = 1
local EDIT_TOP = 4
local EDIT_BOTTOM = 4
local EDIT_FILL = 0.6 -- black, this opaque, behind what is typed

local editBoxes = {} -- edit box -> { textures = {...}, active = boolean }

-- With the game's default chat style the input box never goes away: it
-- sits under the window at 35% while nothing is being typed. Blizzard
-- shows and hides its focus border as the box is activated and
-- deactivated; our box follows those calls and, unless asked to stay, is
-- only drawn while the box is active.
local function UpdateEditBox(parts)
	local shown = parts.active or ns.db.input == "always"
	for _, texture in ipairs(parts.textures) do
		texture:SetShown(shown)
	end
end

function Skin.UpdateEditBoxes()
	for _, parts in pairs(editBoxes) do
		UpdateEditBox(parts)
	end
end

-- The box keeps its bronze edge whatever is being typed: the chat type
-- already shows in the colour of the header and of the text itself.
local function SkinEditBox(frame)
	local editBox = frame.editBox
	local name = editBox and editBox:GetName()
	if not name or editBoxes[editBox] or not art.border then
		return
	end
	for _, piece in ipairs(EDIT_PIECES) do
		Blank(_G[name .. piece])
	end

	local fill = editBox:CreateTexture(nil, "BACKGROUND")
	fill:SetColorTexture(0, 0, 0, EDIT_FILL)
	fill:SetPoint("TOPLEFT", editBox, "TOPLEFT", EDIT_LEFT, -EDIT_TOP)
	fill:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", -EDIT_RIGHT, EDIT_BOTTOM)
	local textures = BuildBorder(editBox, fill)
	textures[#textures + 1] = fill

	local parts = { textures = textures, active = true }
	editBoxes[editBox] = parts
	if type(editBox.SetFocusRegionsShown) == "function" then
		parts.active = editBox:HasFocus() and true or false
		hooksecurefunc(editBox, "SetFocusRegionsShown", function(_, shown)
			parts.active = shown and true or false
			UpdateEditBox(parts)
		end)
	end
	UpdateEditBox(parts)
end

---------------------------------------------------------------------------
-- Arrow keys in the input box

-- The game's chat box only moves the cursor with Alt held: the plain
-- arrow keys go to the character, so you can keep walking while typing.
-- This gives the arrows to the cursor instead (and Up and Down to the
-- line history), the way every other text field works.
local function ApplyArrowKeys(frame)
	local editBox = frame.editBox
	if editBox and type(editBox.SetAltArrowKeyMode) == "function" then
		editBox:SetAltArrowKeyMode(not ns.db.arrows)
	end
end

function Skin.UpdateArrowKeys()
	ns.ForEachChatFrame(ApplyArrowKeys)
end

-- Independent of the art: works with the skin off too.
function Skin.InitArrowKeys()
	Skin.UpdateArrowKeys()
	if type(_G.FCF_OpenTemporaryWindow) == "function" then
		hooksecurefunc("FCF_OpenTemporaryWindow", Skin.UpdateArrowKeys)
	end
end

---------------------------------------------------------------------------
-- The tab follows the channel

-- Typing /2, /p or /g in the input box changes where the line will go;
-- this brings the tab that shows that channel to the front, when the one
-- in front does not. It happens whenever the box's header changes while
-- the box is open, so pressing Enter on a tab that does not show the
-- current chat type also switches, to where the line would appear.
--
-- Selecting a tab needs no hardware event, but it goes through the same
-- functions a click on the tab runs, and those note the selection in
-- Blizzard's own tables. The one place that matters is the code that
-- opens a whisper tab (chat style "popout"), which reads that note; from
-- addon code the note is tainted, and in a boss fight that could stop a
-- whisper tab from showing its first line. The next click on any tab
-- clears it. /fchat follow off if that trade is not worth it.
local function ShowsChat(frame, chatType, target)
	if chatType == "CHANNEL" then
		local name = target
		if type(target) == "number" and ChatFrameUtil and ChatFrameUtil.GetChannelShortcutName then
			name = ChatFrameUtil.GetChannelShortcutName(target)
		end
		return type(name) == "string" and type(frame.ContainsChannel) == "function" and frame:ContainsChannel(name)
	end
	local group = ChatFrameUtil and ChatFrameUtil.GetChatCategory and ChatFrameUtil.GetChatCategory(chatType) or chatType
	return type(frame.ContainsMessageGroup) == "function" and frame:ContainsMessageGroup(group)
end

local function FollowChannel(editBox)
	if not ns.db.follow or _G.ACTIVE_CHAT_EDIT_BOX ~= editBox then
		return
	end
	local chatType = editBox:GetAttribute("chatType")
	local target = editBox:GetAttribute("channelTarget")
	if IsSecret(chatType) or IsSecret(target) or type(chatType) ~= "string" then
		return
	end
	local dock = _G.GENERAL_CHAT_DOCK
	if not dock or type(_G.FCFDock_GetSelectedWindow) ~= "function" or type(_G.FCF_SelectDockFrame) ~= "function" then
		return
	end
	local selected = FCFDock_GetSelectedWindow(dock)
	if not selected or ShowsChat(selected, chatType, target) then
		return
	end
	for _, frame in ipairs(dock.DOCKED_CHAT_FRAMES or {}) do
		if frame ~= selected and ShowsChat(frame, chatType, target) then
			SELECTED_CHAT_FRAME = frame
			FCF_SelectDockFrame(frame)
			return
		end
	end
end

local following = {}

local function FollowFrom(frame)
	local editBox = frame.editBox
	if not editBox or following[editBox] or type(editBox.UpdateHeader) ~= "function" then
		return
	end
	following[editBox] = true
	hooksecurefunc(editBox, "UpdateHeader", function(self)
		pcall(FollowChannel, self)
	end)
end

-- Independent of the art: works with the skin off too.
function Skin.InitFollow()
	ns.ForEachChatFrame(FollowFrom)
	if type(_G.FCF_OpenTemporaryWindow) == "function" then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			ns.ForEachChatFrame(FollowFrom)
		end)
	end
end

---------------------------------------------------------------------------
-- Combat log tab last

-- The game treats General and Combat Log as fixed tabs: whatever their
-- place in the dock, it lays those two out first and gives the rest of
-- the row to the other tabs. That is decided by a field on the combat
-- log frame which an addon cannot change without tainting the code that
-- opens whisper tabs, so the order is changed on screen only, after
-- Blizzard's layout has run: the row of other tabs starts right after
-- General, and the Combat Log tab is hung after the last of them. The
-- row keeps the width Blizzard gave it, so the tab sizes it worked out
-- still hold. When there are more tabs than fit (the overflow arrow
-- shows), Blizzard's own order is left alone.
local function PlaceCombatLogLast(dock)
	if not ns.db.combatLogLast or dock == nil or dock ~= _G.GENERAL_CHAT_DOCK then
		return
	end
	local general, combat, combatFrame = _G.ChatFrame1Tab, _G.ChatFrame2Tab, _G.ChatFrame2
	local row, overflow = dock.scrollFrame, dock.overflowButton
	if not general or not combat or not combatFrame or not combatFrame.isDocked or not row then
		return
	end
	if overflow and overflow:IsShown() then
		return
	end
	local last
	for _, frame in ipairs(dock.DOCKED_CHAT_FRAMES or {}) do
		if not frame.isStaticDocked then
			last = frame
		end
	end
	local lastTab = last and last:GetName() and _G[last:GetName() .. "Tab"]
	if not lastTab then
		return -- no other tabs: nothing to be last of
	end
	local width = combat:GetWidth()
	if IsSecret(width) or type(width) ~= "number" then
		return
	end
	-- The row first: it was anchored to the Combat Log tab, which is
	-- about to be anchored to a tab inside the row.
	row:SetPoint("LEFT", general, "RIGHT")
	row:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -(width + 1), -1)
	combat:ClearAllPoints()
	combat:SetPoint("LEFT", lastTab, "RIGHT", 1, 0)
end

-- Independent of the art: works with the skin off too.
function Skin.InitTabOrder()
	if type(_G.FCFDock_UpdateTabs) == "function" then
		hooksecurefunc("FCFDock_UpdateTabs", function(dock)
			pcall(PlaceCombatLogLast, dock)
		end)
	end
end

---------------------------------------------------------------------------

local skinned = {}

local function SkinFrame(frame)
	if skinned[frame] then
		return
	end
	skinned[frame] = true
	SkinWindow(frame)
	SkinTab(frame)
	SkinEditBox(frame)
end

local function FindArt()
	art.cornerTopLeft = Atlas("tooltip-nineslice-cornertopleft")
	art.cornerTopRight = Atlas("tooltip-nineslice-cornertopright")
	art.cornerBottomLeft = Atlas("tooltip-nineslice-cornerbottomleft")
	art.cornerBottomRight = Atlas("tooltip-nineslice-cornerbottomright")
	art.edgeTop = Atlas("_tooltip-nineslice-edgetop")
	art.edgeBottom = Atlas("_tooltip-nineslice-edgebottom")
	art.edgeLeft = Atlas("!tooltip-nineslice-edgeleft")
	art.edgeRight = Atlas("!tooltip-nineslice-edgeright")
	art.border = art.cornerTopLeft and art.cornerTopRight and art.cornerBottomLeft and art.cornerBottomRight
		and art.edgeTop and art.edgeBottom and art.edgeLeft and art.edgeRight and true

	art.tab = Atlas("common-internaltab")
	art.tabSelected = Atlas("common-internaltab-selected")
	art.tabHover = Atlas("common-internaltab-hover")

end

function Skin.Init()
	if not ns.db.skin then
		return
	end
	FindArt()
	ns.ForEachChatFrame(SkinFrame)

	if type(_G.FCFTab_UpdateColors) == "function" then
		hooksecurefunc("FCFTab_UpdateColors", UpdateTab)
	end
	if type(_G.FloatingChatFrame_UpdateBackgroundAnchors) == "function" then
		-- Blizzard puts the background back where it wants it.
		hooksecurefunc("FloatingChatFrame_UpdateBackgroundAnchors", PadBackground)
	end
	if type(_G.FCF_OpenTemporaryWindow) == "function" then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			ns.ForEachChatFrame(SkinFrame)
		end)
	end

	if #borders > 0 then
		local driver = CreateFrame("Frame")
		driver:SetScript("OnUpdate", UpdateBorders)
	end
end
