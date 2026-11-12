-- Arrow.lua: the direction arrow. It is the game's own gold quest arrow
-- (the one on the minimap edge), turned towards the current goal, with the
-- distance under it in the tracker's font. What the goal is stands in the
-- tracker already (and in the arrow's tooltip).
local _, ns = ...

local Maps = ns.Maps
local Nav = ns.Nav

local ARROW = "minimap-questarrow"
local HERE = "Waypoint-MapPin-Tracked"
local ELSEWHERE = "Waypoint-MapPin-Untracked"

local frame = CreateFrame("Frame", "ForeverGuideArrow", UIParent)
frame:SetSize(56, 56)
frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
frame:SetFrameStrata("LOW")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:Hide()

local arrow = frame:CreateTexture(nil, "ARTWORK")
arrow:SetPoint("CENTER")
arrow:SetSize(48, 48)

local detail = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
detail:SetPoint("TOP", frame, "BOTTOM", 0, 2)
detail:SetTextColor(0.8, 0.8, 0.8)

local shownAtlas
local function setAtlas(atlas, size)
    if shownAtlas ~= atlas then
        shownAtlas = atlas
        arrow:SetAtlas(atlas)
        arrow:SetSize(size, size)
        arrow:SetRotation(0)
    end
end

local sinceNav, sinceDraw = 1, 1
local inst, px, py

local function draw()
    local target = Nav.target
    if not target then
        frame:Hide()
        return
    end
    local distance, bearing = Maps.Distance(target, inst, px, py)
    local facing = GetPlayerFacing()
    if not distance or not facing then
        -- Another continent, or a place where the game hides positions.
        setAtlas(ELSEWHERE, 30)
        detail:SetText(Maps.Name(target.map) or "")
        return
    end
    if distance <= math.max(8, math.min(target.radius or 8, 15)) then
        setAtlas(HERE, 34)
    else
        setAtlas(ARROW, 48)
        arrow:SetRotation(bearing - facing)
    end
    detail:SetFormattedText("%d yd", distance)
end

frame:SetScript("OnUpdate", function(_, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sinceDraw < 0.05 then
        return
    end
    sinceNav = sinceNav + sinceDraw
    sinceDraw = 0
    if sinceNav >= 0.25 then
        sinceNav = 0
        inst, px, py = Nav:Update()
    else
        inst, px, py = Maps.Player()
    end
    draw()
end)

-- Keeps the navigation going (arrival checks) while the arrow is hidden.
local ticker = CreateFrame("Frame")
local idle = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    if frame:IsShown() then
        return
    end
    idle = idle + elapsed
    if idle >= 0.5 then
        idle = 0
        Nav:Update()
    end
end)

local function refresh()
    if not ns.db then
        return
    end
    local target = Nav.target
    if target and ns.db.arrow then
        sinceNav, sinceDraw = 1, 1
        frame:Show()
    else
        frame:Hide()
    end
    frame:EnableMouse(not ns.db.arrowLocked)
end

ns.Listen("Target", refresh)
ns.Listen("Updated", refresh)
ns.Listen("Setting", refresh)

---------------------------------------------------------------------------
-- Moving it
---------------------------------------------------------------------------
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if not ns.db.arrowLocked then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relative, x, y = self:GetPoint(1)
    ns.db.arrowPos = { point, relative, x, y }
end)
frame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and ns.Menu then
        ns.Menu.Open(self)
    end
end)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -18)
    GameTooltip:SetText(Nav.title or "Guide")
    GameTooltip:AddLine("Drag to move. Right-click for guide options.", 1, 1, 1)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", GameTooltip_Hide)

ns.Listen("Loaded", function()
    local pos = ns.db.arrowPos
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end)
