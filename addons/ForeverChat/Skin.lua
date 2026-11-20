-- Forever's art on the chat frame.
--
-- Forever reskinned the modern interface with its own set of textures
-- (the atlases ending in "-c60": near-black panels with a thin bronze
-- edge and cut corners, gold for whatever is selected), but the chat
-- frame still wears the 2004 tab, border and input-box textures. This
-- puts the Forever pieces on it:
--
--   tabs         the auction house's: bronze, gold when selected
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

-- The auction house's tabs (PanelTabButtonTemplate): three pieces each,
-- uiframe-tab at rest (Forever's bronze c60), uiframe-activetab when
-- selected (gold; Forever has no c60 of it, the auction house shows the
-- plain one too), and on hover the rest pieces once more, added at 40%.
-- The selected tab has no hover, as the auction house disables it.
--
-- Chat tabs stand on top of their window, so they are drawn the way the
-- auction house draws the tabs above its lists (Auctions, Bids;
-- PanelTopTabButtonMixin): the art upside down with its top quarter
-- left off, standing on the tab's bottom. Offsets and sizes are that
-- template's; the ends hang a little past the button, which is shadow.

local TAB_PIECES = {
	"Left", "Middle", "Right",
	"ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight",
}

local TOP_TAB_HEIGHT = 0.75 -- of the art's height, as the auction house's top tabs
-- The auction house's selected top tab stands 4.5 above the others;
-- on the chat window that is too much, so it is cut lower, to this.
local ACTIVE_RISE = 2
local HOVER_ALPHA = 0.4

-- Where the art's ends sit, against the tab button's left and right.
local REST_SIDES = { left = -3, right = 7 }
local ACTIVE_SIDES = { left = -1, right = 8 }

-- Atlas sizes, from the game when it says, else those of build 1.60.1.
local FALLBACK_SIZE = {
	["uiframe-tab-left"] = { 35, 36 }, ["uiframe-tab-right"] = { 37, 36 }, ["_uiframe-tab-center"] = { 1, 36 },
	["uiframe-activetab-left"] = { 35, 42 }, ["uiframe-activetab-right"] = { 37, 42 }, ["_uiframe-activetab-center"] = { 1, 42 },
}

local function AtlasSize(atlas, plain)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	if type(info) == "table" and type(info.width) == "number" and type(info.height) == "number"
		and not IsSecret(info.width) and not IsSecret(info.height) then
		return info.width, info.height
	end
	local size = FALLBACK_SIZE[plain]
	return size[1], size[2]
end

-- One tab's worth of a piece set: left, middle and right textures.
local function MakeSet(tab, layer, sublevel, names, sides, rise)
	local set = { sides = sides }
	for _, key in ipairs({ "left", "middle", "right" }) do
		local atlas = names[key]
		local texture = tab:CreateTexture(nil, layer, nil, sublevel)
		texture:SetAtlas(atlas.name)
		local width, height = AtlasSize(atlas.name, atlas.plain)
		set[key] = texture
		set[key .. "Width"] = width
		set.artHeight = height
	end
	-- The rest tab's height, plus the rise, of this set's art.
	local _, restArtHeight = AtlasSize(art.tabRest.left.name, art.tabRest.left.plain)
	local restHeight = restArtHeight * TOP_TAB_HEIGHT
	local height = math.min(restHeight + (rise or 0), set.artHeight)
	set.cut = 1 - height / set.artHeight
	for _, key in ipairs({ "left", "middle", "right" }) do
		set[key]:SetHeight(height)
	end
	set.left:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", sides.left, 0)
	set.right:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", sides.right, 0)
	set.middle:SetPoint("BOTTOMLEFT", set.left, "BOTTOMRIGHT")
	set.middle:SetPoint("BOTTOMRIGHT", set.right, "BOTTOMLEFT")
	return set
end

-- The ends at their own widths while they fit, as the auction house has
-- them. A chat tab can be narrower than the two ends together (it is
-- sized to its name, from 32 up); then each end gives up part of its
-- inner side, so the outer edges and corners still show whole.
local function LayoutSet(set, tabWidth)
	local span = tabWidth - set.sides.left + set.sides.right
	local leftWidth, rightWidth = set.leftWidth, set.rightWidth
	local ends = leftWidth + rightWidth
	if span < ends then
		leftWidth = math.max(span, 0) * leftWidth / ends
		rightWidth = math.max(span, 0) - leftWidth
	end
	set.left:SetWidth(leftWidth)
	set.right:SetWidth(rightWidth)
	set.left:SetTexCoord(0, leftWidth / set.leftWidth, 1, set.cut)
	set.right:SetTexCoord(1 - rightWidth / set.rightWidth, 1, 1, set.cut)
	set.middle:SetTexCoord(0, 1, 1, set.cut)
	set.hasMiddle = span > ends
end

local function ShowSet(set, shown)
	set.left:SetShown(shown)
	set.right:SetShown(shown)
	set.middle:SetShown(shown and set.hasMiddle or false)
end

local function ForSet(set, fn, ...)
	fn(set.left, ...)
	fn(set.middle, ...)
	fn(set.right, ...)
end

local tabs = {} -- tab -> { rest = set, active = set, hover = set }

local function UpdateTab(tab, selected)
	local parts = tabs[tab]
	if not parts then
		return
	end
	selected = selected and true or false
	ShowSet(parts.rest, not selected)
	ShowSet(parts.active, selected)
	ShowSet(parts.hover, not selected)
	-- Whisper tabs carry the colour of their chat type; Blizzard has just
	-- put it on the text, and the gold of the selected tab takes it too.
	local color = tab.selectedColorTable
	if color then
		ForSet(parts.active, function(texture)
			texture:SetDesaturated(true)
			texture:SetVertexColor(color.r, color.g, color.b)
		end)
	else
		ForSet(parts.active, function(texture)
			texture:SetDesaturated(false)
			texture:SetVertexColor(1, 1, 1)
		end)
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
	if not tab or tabs[tab] or not art.tabRest then
		return
	end
	for _, key in ipairs(TAB_PIECES) do
		local piece = tab[key]
		if piece then
			piece:SetAlpha(0)
		end
	end

	local parts = {
		rest = MakeSet(tab, "BACKGROUND", 1, art.tabRest, REST_SIDES),
		active = MakeSet(tab, "BACKGROUND", 2, art.tabActive or art.tabRest, ACTIVE_SIDES, ACTIVE_RISE),
		hover = MakeSet(tab, "HIGHLIGHT", 0, art.tabRest, REST_SIDES),
	}
	ForSet(parts.hover, function(texture)
		texture:SetBlendMode("ADD")
		texture:SetAlpha(HOVER_ALPHA)
	end)

	-- The game resizes tabs to their names and to the room in the dock.
	local function Layout(_, tabWidth)
		if IsSecret(tabWidth) or type(tabWidth) ~= "number" then
			return
		end
		for _, set in pairs(parts) do
			LayoutSet(set, tabWidth)
		end
		UpdateTab(tab, IsTabSelected(frame))
	end
	tabs[tab] = parts
	tab:HookScript("OnSizeChanged", Layout)
	local ok, tabWidth = pcall(tab.GetWidth, tab)
	Layout(tab, ok and tabWidth or 0)
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

	-- The auction house's tabs; see Tabs.
	local function TabSet(prefix)
		local set = {}
		for key, plain in pairs({ left = prefix .. "-left", middle = "_" .. prefix .. "-center", right = prefix .. "-right" }) do
			local name = Atlas(plain)
			if not name then
				return nil
			end
			set[key] = { name = name, plain = plain }
		end
		return set
	end
	art.tabRest = TabSet("uiframe-tab")
	art.tabActive = TabSet("uiframe-activetab")

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
