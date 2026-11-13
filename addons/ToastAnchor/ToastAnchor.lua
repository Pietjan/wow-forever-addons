-- ToastAnchor: the game's alert popups ("You won", achievements, other
-- loot toasts) all stack upward from one point at the bottom centre of the
-- screen. This moves that point to where you want it.
--
-- /toastanchor         show or hide a marker; drag it where the lowest
--                      popup should sit
-- /toastanchor reset   back to the game's own place
--
-- How: every popup hangs off one frame, AlertFrame, which the game anchors
-- once (128 up from the bottom centre) and never moves again; each popup is
-- anchored to it, or to the popup below, as it appears. So AlertFrame itself
-- is given another anchor point. That is all that is done to it: no field of
-- the game's is written and nothing of its layout is hooked or replaced.
-- Until you have placed the marker, the addon does not touch it at all.
--
-- Two game windows (the shop and the Trading Post) borrow the popups'
-- anchor while they are open and give it back when they close; that is the
-- game's doing and is left alone.

local ADDON_NAME = ...

local DEFAULT_Y = 128 -- the game's own: bottom centre, this far up

local db
local marker

-- Where the popups should start: the bottom centre of the marker, in
-- UIParent's coordinates from its bottom left corner.
local function Apply()
	local alerts = AlertFrame
	if not (alerts and db) then
		return
	end
	if db.x and db.y then
		alerts:ClearAllPoints()
		alerts:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", db.x, db.y)
	elseif db.moved then
		-- Reset after it had been moved: the game's own anchor again.
		alerts:ClearAllPoints()
		alerts:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, DEFAULT_Y)
		db.moved = nil
	end
end

local function PlaceMarker()
	marker:ClearAllPoints()
	if db.x and db.y then
		marker:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", db.x, db.y)
	else
		marker:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, DEFAULT_Y)
	end
end

local function CreateMarker()
	marker = CreateFrame("Frame", "ToastAnchorMarker", UIParent)
	marker:SetSize(260, 44)
	marker:SetFrameStrata("DIALOG")
	marker:SetClampedToScreen(true)
	marker:SetMovable(true)
	marker:EnableMouse(true)
	marker:RegisterForDrag("LeftButton")
	marker:Hide()

	local fill = marker:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0, 0, 0, 0.6)
	local edge = marker:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(2)
	edge:SetColorTexture(1, 0.82, 0, 1)

	local title = marker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", 0, -6)
	title:SetText("Alert popups start here")
	local hint = marker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOM", 0, 7)
	hint:SetText("Drag me. /toastanchor to hide.")

	marker:SetScript("OnDragStart", marker.StartMoving)
	marker:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter(), self:GetBottom()
		if type(x) == "number" and type(y) == "number" then
			db.x, db.y, db.moved = x, y, true
			PlaceMarker()
			Apply()
		end
	end)
end

SLASH_TOASTANCHOR1 = "/toastanchor"
SlashCmdList.TOASTANCHOR = function(message)
	if not db then
		return
	end
	local command = (message or ""):lower():match("^%s*(%S*)")
	if command == "reset" then
		db.x, db.y = nil, nil
		Apply()
		PlaceMarker()
		print("|cffffd100ToastAnchor|r: alert popups are back at the game's own place.")
	elseif marker:IsShown() then
		marker:Hide()
	else
		PlaceMarker()
		marker:Show()
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == ADDON_NAME then
			ToastAnchorDB = ToastAnchorDB or {}
			db = ToastAnchorDB
			CreateMarker()
		end
	elseif event == "PLAYER_LOGIN" then
		Apply()
	end
end)
