-- Tracker.lua: the guide as a section of the game's objective tracker.
--
-- This is a regular tracker module, like Quests or Achievements: built
-- from Blizzard's module, block and line templates and handed to the
-- ObjectiveTrackerManager, which lays it out, collapses it and sizes it
-- with the rest. It sits just above the Quests section.
--
-- Joining the tracker waits until combat is over. Marking our section as
-- changed does not: see the "Updated" listener at the end.
local _, ns = ...

local Engine = ns.Engine

---------------------------------------------------------------------------
-- The check box at the right edge of a step: finish the step by hand.
-- (Template in Tracker.xml.)
---------------------------------------------------------------------------
ForeverGuideStepButtonMixin = {}

function ForeverGuideStepButtonMixin:SetUp(stepIndex)
    self.stepIndex = stepIndex
end

function ForeverGuideStepButtonMixin:OnClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    Engine:CompleteStep(self.stepIndex)
end

function ForeverGuideStepButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Step done")
    GameTooltip:AddLine("Mark this step as done and move on.", 1, 1, 1, true)
    GameTooltip:Show()
end

function ForeverGuideStepButtonMixin:OnLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- The progress line above the steps. (Template in Tracker.xml.)
---------------------------------------------------------------------------
ForeverGuideProgressBarMixin = {}

-- Forever's own art for a small bar: the bronze frame with cut corners
-- (131 x 26 with its shadow, around a 117 x 12 bar), drawn at half size.
-- The frame is one fixed picture, so it is laid out as two end caps and a
-- stretched middle to fit the tracker's width.
local FRAME, FRAME_W, FRAME_H, CAP, SCALE = "legacy-progressbar-frame", 131, 26, 16, 0.5

local function art(name)
    for _, try in ipairs({ name .. "-c60", name }) do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(try)
        if info then
            return try, info
        end
    end
end

function ForeverGuideProgressBarMixin:OnLoad()
    local bar = self.Bar
    local _, info = art(FRAME)
    if info and info.file and info.leftTexCoord then
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local cap = (r - l) * CAP / FRAME_W
        local function piece(from, to)
            local texture = bar:CreateTexture(nil, "OVERLAY")
            texture:SetTexture(info.file)
            texture:SetTexCoord(from, to, t, b)
            texture:SetHeight(FRAME_H * SCALE)
            return texture
        end
        local left, mid, right = piece(l, l + cap), piece(l + cap, r - cap), piece(r - cap, r)
        left:SetWidth(CAP * SCALE)
        left:SetPoint("LEFT", self, "LEFT", 0, 0)
        right:SetWidth(CAP * SCALE)
        right:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        mid:SetPoint("LEFT", left, "RIGHT")
        mid:SetPoint("RIGHT", right, "LEFT")
        bar.Border:Hide()
    end
    local track = art("legacy-progressbar-bg")
    if track then
        bar.Track:SetAtlas(track)
    end
    local fill = art("common-stat-bar-white")
    if fill then
        bar:SetStatusBarTexture(fill)
        bar:SetStatusBarColor(1, 0.82, 0)
    end
end

function ForeverGuideProgressBarMixin:SetPercent(percent)
    self.percent = percent
    self.Bar:SetValue(percent)
end

function ForeverGuideProgressBarMixin:OnEnter()
    local view = Engine.view
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -8, 0)
    GameTooltip:SetText(view.name or "Guide")
    if view.step and view.count then
        GameTooltip:AddLine(("Step %d of %d (%d%%)"):format(view.step, view.count, self.percent or 0), 1, 1, 1)
    end
    GameTooltip:Show()
end

function ForeverGuideProgressBarMixin:OnLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------
local Module = {
    blockTemplate = "ObjectiveTrackerAnimBlockTemplate",
    lineTemplate = "ObjectiveTrackerAnimLineTemplate",
    progressBarTemplate = "ForeverGuideProgressBarTemplate",
    rightEdgeFrameSpacing = 2,
    stepButtonSettings = {
        template = "ForeverGuideStepButtonTemplate",
        offsetX = 0,
        offsetY = 0,
    },
}

-- How far along the guide is: a thin gold line in a block of its own above
-- the steps (template in Tracker.xml). block:AddProgressBar hangs a bar
-- under a text line; this block has none, so the same few steps are done
-- here against the block itself.
function Module:LayoutProgress()
    local view = Engine.view
    local first = view.blocks[1]
    if not (ns.db and ns.db.progress and view.step and view.count and view.count > 0) or (first and first.placeholder) then
        return true
    end
    local block = self:GetBlock("progress")
    block.foreverGuide = nil
    local bar = self:GetProgressBar(block)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    local width = block:GetWidth()
    if width and width > 0 then
        bar:SetWidth(width)
    end
    bar:SetPercent(math.floor((view.step - 1) / view.count * 100))
    bar.parentLine = nil
    block.height = bar.height
    block.lastRegion = bar
    block:OnAddedRegion(bar, true)
    return self:LayoutBlock(block)
end

function Module:LayoutContents()
    local State = ObjectiveTrackerAnimLineState
    if not self:LayoutProgress() then
        return
    end
    for _, data in ipairs(Engine.view.blocks) do
        local block = self:GetBlock(data.id)
        block.foreverGuide = data
        if data.id > 0 then
            block:AddRightEdgeFrame(self.stepButtonSettings, data.id)
        end
        block:SetHeader(data.title)
        for _, entry in ipairs(data.lines) do
            local dash = (entry.obj and not entry.done) and OBJECTIVE_DASH_STYLE_SHOW or OBJECTIVE_DASH_STYLE_HIDE
            local color = entry.done and OBJECTIVE_TRACKER_COLOR["Complete"] or nil
            local line = block:AddObjective(entry.key, entry.text, nil, true, dash, color)
            if not entry.obj then
                line:SetNoIcon(true)
            elseif entry.done then
                if line.state == State.Present then
                    line:SetState(State.Completing)
                elseif line.state == nil then
                    line:SetState(State.Completed)
                end
            elseif line.state ~= State.Present then
                line:SetState(State.Present)
            end
        end
        if not self:LayoutBlock(block) then
            return
        end
    end
end

function Module:OnBlockHeaderClick(block, mouseButton)
    local data = block.foreverGuide
    if not data then
        return
    end
    if mouseButton ~= "RightButton" and data.placeholder and Engine.view.paused then
        Engine:Resume()
    elseif mouseButton == "RightButton" or data.placeholder and not Engine.view.nextKey then
        ns.Menu.Open(self:GetContextMenuParent())
    elseif data.placeholder then
        Engine:Start(Engine.view.nextKey)
    elseif ns.Quiet() then
        -- Show where this step is.
        local target = ns.Nav.target
        if target and target.map then
            OpenWorldMap(target.map)
        end
    end
end

function Module:OnBlockHeaderEnter(block)
    local data = block.foreverGuide
    if not data then
        return
    end
    GameTooltip:SetOwner(block, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPRIGHT", block, "TOPLEFT", -8, 0)
    local view = Engine.view
    GameTooltip:SetText(view.name or "Guide")
    if view.step and view.count then
        GameTooltip:AddLine(("Step %d of %d"):format(view.step, view.count), 1, 1, 1)
    end
    if not data.placeholder then
        GameTooltip:AddLine("Click to show it on the map.", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Right-click for guide options.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function Module:OnBlockHeaderLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Joining the tracker
---------------------------------------------------------------------------
local module
local lastMain

local function apply()
    if not module or not ns.Guard("tracker") then
        return
    end
    local view = Engine.view
    module:SetHeader(view.name or "Guide")
    -- A new main step gets the glow a newly tracked quest gets.
    local first = view.blocks[1]
    local main = first and first.main and first.id or nil
    if main and main ~= lastMain and lastMain ~= nil then
        module:SetNeedsFanfare(main)
    end
    lastMain = main or false
    module:MarkDirty()
end

-- Through the gate: marking the section as changed makes the tracker redraw
-- on the next frame, and that is Blizzard code running for us. So during a
-- fight the section keeps what it showed and catches up afterwards.
local function update()
    if module then
        ns.AfterCombat("tracker", apply)
    end
end

-- Puts the section into the tracker's list, right before Quests.
--
-- Not through ObjectiveTrackerManager:SetModuleContainer. That asks the
-- tracker to sort its list again, and a sort that involves our section
-- leaves the whole list, and the "needs sorting" flag, marked as touched by
-- an addon. From then on every tracker update runs on our behalf from its
-- first line. That breaks when the game redraws all sections during combat
-- (it does on a level-up): the Scenario section, first in the list, looks
-- at an aura (ShouldShowMawBuffs), which the game refuses to code running
-- for an addon in combat ("Auras cannot be accessed when secret while
-- tainted by 'ForeverGuide'").
--
-- Placed by hand, only our own entry and the ones after it carry the mark;
-- Scenario and the others before us keep running as the game's own code.
local function place(section, container)
    local list = container.modules
    local at = #list + 1
    for index, other in ipairs(list) do
        if other == QuestObjectiveTracker or (other.uiOrder or 0) > section.uiOrder then
            at = index
            break
        end
    end
    table.insert(list, at, section)
    section:SetContainer(container)
end
ns.PlaceTrackerSection = place

local function create()
    module = CreateFrame("Frame", "ForeverGuideTracker", ObjectiveTrackerFrame, "ObjectiveTrackerModuleTemplate")
    Mixin(module, Module)
    module.uiOrder = 3.5
    module:SetHeader("Guide")

    -- The section header opens the guide menu.
    local button = CreateFrame("Button", nil, module.Header)
    button:SetPoint("TOPLEFT")
    button:SetPoint("BOTTOMRIGHT", module.Header.MinimizeButton, "BOTTOMLEFT", -4, 0)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function()
        ns.Menu.Open(module:GetContextMenuParent())
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -8, 0)
        GameTooltip:SetText(Engine.view.name or "Guide")
        GameTooltip:AddLine("Click for guide options.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    place(module, ObjectiveTrackerFrame)
    update()
end

local tries = 0
local function join()
    if module then
        return
    end
    local manager = ObjectiveTrackerManager
    -- Only once the game has put its own sections in and sorted them.
    local frame = ObjectiveTrackerFrame
    if ns.Quiet() and manager and frame and manager.containers[frame] and not frame.needsSorting then
        create()
        return
    end
    tries = tries + 1
    if tries < 40 or not ns.Quiet() then
        C_Timer.After(0.5, join)
    end
end

ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(0, join)
end)

ns.Listen("Updated", update)
ns.Listen("Setting", function(key)
    if key == "progress" then
        update()
    end
end)
