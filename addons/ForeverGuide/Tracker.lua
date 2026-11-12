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
-- The module
---------------------------------------------------------------------------
local Module = {
    blockTemplate = "ObjectiveTrackerAnimBlockTemplate",
    lineTemplate = "ObjectiveTrackerAnimLineTemplate",
    rightEdgeFrameSpacing = 2,
    stepButtonSettings = {
        template = "ForeverGuideStepButtonTemplate",
        offsetX = 0,
        offsetY = 0,
    },
}

function Module:LayoutContents()
    local State = ObjectiveTrackerAnimLineState
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
    elseif not InCombatLockdown() then
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

local function update()
    if not module then
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
    if not InCombatLockdown() and manager and frame and manager.containers[frame] and not frame.needsSorting then
        create()
        return
    end
    tries = tries + 1
    if tries < 40 or InCombatLockdown() then
        C_Timer.After(0.5, join)
    end
end

ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(0, join)
end)

-- Also in combat, so a count that goes up shows at once, as it does under
-- Quests. This only marks our section as changed: the tracker then redraws
-- the changed sections and skips the rest (ObjectiveTrackerModuleMixin:Update),
-- so no other section's code runs because of it.
ns.Listen("Updated", update)
