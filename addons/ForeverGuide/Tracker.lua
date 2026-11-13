-- Tracker.lua: the guide, drawn to look like a section of the game's
-- objective tracker and placed right under it.
--
-- It is a frame of our own, not a section inside Blizzard's tracker. A
-- section in there cannot be kept clean: asking the tracker to redraw runs
-- every section on the addon's behalf, and the tracker's own bookkeeping
-- stays marked as addon-touched for the rest of the session. From then on
-- any redraw during combat fails in the game's Scenario section ("Auras
-- cannot be accessed when secret while tainted by 'ForeverGuide'"), most
-- visibly on a level-up. Measured in game with issecurevariable on
-- ObjectiveTrackerFrame.topModulePadding and ScenarioObjectiveTracker.state.
--
-- So nothing of Blizzard's tracker is written or called to change it. Its
-- position, size and folded state are only read, a few times a second, and
-- our frame is moved to follow. Everything drawn here is ours, which also
-- means it can be redrawn at any time, combat included.
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
-- The look: the measures and art of Blizzard's tracker sections
-- (Blizzard_ObjectiveTrackerModule.xml and .lua, build 70888).
---------------------------------------------------------------------------
local WIDTH = 260
local HEADER_HEIGHT = 26       -- the header's own height
local HEADER_ROOM = 25         -- the room it takes above the contents
local FROM_HEADER = 10         -- header to first block
local BLOCK_X = 20             -- blocks start this far in
local BETWEEN_BLOCKS = 10
local LINE_SPACING = 4
local BUTTON_ROOM = 20         -- kept free at the right of a step's title for its check box
local BELOW_TRACKER = 10       -- gap between the tracker's last section and ours

local COLOR = {
    title = { 0.75, 0.61, 0 },
    titleHover = { 1, 0.82, 0 },
    line = { 0.8, 0.8, 0.8 },
    done = { 0.6, 0.6, 0.6 },
}
do
    -- The game's own colours, when it has them.
    local shared = OBJECTIVE_TRACKER_COLOR
    local function take(key, name)
        local c = type(shared) == "table" and shared[name]
        if type(c) == "table" and c.r and c.g and c.b then
            COLOR[key] = { c.r, c.g, c.b }
        end
    end
    take("title", "Header")
    take("titleHover", "HeaderHighlight")
    take("line", "Normal")
    take("done", "Complete")
end

local function textHeight(fontString)
    local height = fontString:GetStringHeight()
    return type(height) == "number" and height > 0 and height or 12
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local frame, header, contents, glow
local progress
local blocks, lines = {}, {}   -- pools: every block and line ever made
local usedBlocks, usedLines = 0, 0
local lastMain

local function isCollapsed()
    return ns.char and ns.char.collapsed or false
end

local function onTitleClick(self, mouseButton)
    local data = self.data
    if not data then
        return
    end
    if mouseButton ~= "RightButton" and data.placeholder and Engine.view.paused then
        Engine:Resume()
    elseif mouseButton == "RightButton" or data.placeholder and not Engine.view.nextKey then
        ns.Menu.Open(self)
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

local function onTitleEnter(self)
    local data = self.data
    if not data then
        return
    end
    self.text:SetTextColor(unpack(COLOR.titleHover))
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -8, 0)
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

local function onTitleLeave(self)
    self.text:SetTextColor(unpack(COLOR.title))
    GameTooltip:Hide()
end

-- A step: its title, the check box at its right edge, and its lines below.
local function getBlock()
    usedBlocks = usedBlocks + 1
    local block = blocks[usedBlocks]
    if not block then
        block = CreateFrame("Button", nil, contents)
        block:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        block.text = block:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
        block.text:SetPoint("TOPLEFT")
        block.text:SetJustifyH("LEFT")
        block.text:SetTextColor(unpack(COLOR.title))
        block:SetScript("OnClick", onTitleClick)
        block:SetScript("OnEnter", onTitleEnter)
        block:SetScript("OnLeave", onTitleLeave)
        block.check = CreateFrame("Button", nil, contents, "ForeverGuideStepButtonTemplate")
        blocks[usedBlocks] = block
    end
    block:Show()
    return block
end

-- One line of a step: a dash or a check mark, and the text.
local function getLine()
    usedLines = usedLines + 1
    local line = lines[usedLines]
    if not line then
        line = CreateFrame("Frame", nil, contents)
        line.dash = line:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
        line.dash:SetPoint("TOPLEFT", 0, 1)
        line.dash:SetText(QUEST_DASH or "- ")
        line.text = line:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
        line.text:SetPoint("TOPLEFT", line.dash, "TOPRIGHT", 0, -1)
        line.text:SetJustifyH("LEFT")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetAtlas("ui-questtracker-tracker-check")
        line.icon:SetSize(16, 16)
        line.icon:SetPoint("TOPLEFT", -10, 2)
        lines[usedLines] = line
    end
    line:Show()
    return line
end

local function layout()
    if not frame then
        return
    end
    local view = Engine.view
    header.text:SetText(view.name or "Guide")
    header.minimize:SetNormalAtlas(isCollapsed() and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse")
    header.minimize:SetPushedAtlas(isCollapsed() and "ui-questtrackerbutton-secondary-expand-pressed" or "ui-questtrackerbutton-secondary-collapse-pressed")

    for i = 1, usedBlocks do
        blocks[i]:Hide()
        blocks[i].check:Hide()
        blocks[i].data = nil
    end
    for i = 1, usedLines do
        lines[i]:Hide()
    end
    usedBlocks, usedLines = 0, 0

    if isCollapsed() then
        contents:Hide()
        frame:SetHeight(HEADER_HEIGHT)
        return
    end
    contents:Show()

    local blockWidth = WIDTH - BLOCK_X
    local y = -(HEADER_ROOM + FROM_HEADER) -- where the next thing starts, from the frame's top

    local first = view.blocks[1]
    local showBar = ns.db and ns.db.progress and view.step and view.count and view.count > 0 and not (first and first.placeholder)
    if showBar then
        progress:ClearAllPoints()
        progress:SetPoint("TOPLEFT", frame, "TOPLEFT", BLOCK_X, y)
        progress:SetWidth(blockWidth)
        progress:SetPercent(math.floor((view.step - 1) / view.count * 100))
        progress:Show()
        y = y - progress:GetHeight() - BETWEEN_BLOCKS
    else
        progress:Hide()
    end

    for _, data in ipairs(view.blocks) do
        local block = getBlock()
        block.data = data
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", frame, "TOPLEFT", BLOCK_X, y)
        block.text:SetWidth(blockWidth - BUTTON_ROOM)
        block.text:SetText(data.title or "")
        local height = textHeight(block.text)
        block:SetSize(blockWidth - BUTTON_ROOM, height)
        if data.id > 0 then
            block.check:SetUp(data.id)
            block.check:ClearAllPoints()
            block.check:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y + 2)
            block.check:Show()
        end
        y = y - height

        for _, entry in ipairs(data.lines) do
            local line = getLine()
            local open = entry.obj and not entry.done
            line.dash:SetAlpha(open and 1 or 0) -- hidden, but the text stays lined up
            line.icon:SetShown(entry.obj and entry.done or false)
            local color = entry.done and COLOR.done or COLOR.line
            line.text:SetTextColor(unpack(color))
            line.dash:SetTextColor(unpack(color))
            local dashWidth = line.dash:GetWidth()
            dashWidth = type(dashWidth) == "number" and dashWidth or 10
            line.text:SetWidth(blockWidth - dashWidth)
            line.text:SetText(entry.text or "")
            local lineHeight = textHeight(line.text)
            y = y - LINE_SPACING
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", BLOCK_X, y)
            line:SetSize(blockWidth, lineHeight)
            y = y - lineHeight
        end
        y = y - BETWEEN_BLOCKS
    end

    frame:SetHeight(math.max(HEADER_HEIGHT, -y))

    -- A new main step gets a short glow on the header, as a newly tracked
    -- quest does.
    local main = first and first.main and first.id or nil
    if main and main ~= lastMain and lastMain ~= nil and glow then
        glow.anim:Stop()
        glow.anim:Play()
    end
    lastMain = main or false
end

---------------------------------------------------------------------------
-- Following the game's tracker: read only.
---------------------------------------------------------------------------
-- Where our frame goes: under the tracker's last section; where the tracker
-- would start when it shows nothing; nowhere when the player has folded
-- "All Objectives". Numbers are read and our own frame is moved; no anchor
-- to, and no call into, the tracker.
local placed -- what was last applied, to move only on a change

local function number(value)
    return type(value) == "number" and value or nil
end

local function follow()
    if not frame then
        return
    end
    local tracker = ObjectiveTrackerFrame
    local mode, x, y, scale = "free", nil, nil, 1
    if tracker and tracker.GetLeft then
        local folded = tracker.IsCollapsed and tracker:IsCollapsed()
        local slice = tracker.NineSlice
        local showing = tracker:IsShown() and slice and slice:IsShown()
        local ours, theirs = UIParent:GetEffectiveScale(), tracker:GetEffectiveScale()
        if number(ours) and number(theirs) and ours > 0 then
            scale = theirs / ours
        end
        x = number(tracker:GetLeft())
        if folded then
            mode = "folded"
        elseif showing and number(slice:GetBottom()) then
            mode, y = "below", slice:GetBottom() - BELOW_TRACKER
        else
            mode, y = "top", number(tracker:GetTop())
        end
    end
    if mode == "folded" then
        if placed ~= "folded" then
            placed = "folded"
            frame:Hide()
        end
        return
    end
    if not (x and y) then
        -- No tracker to follow (or not laid out yet): the right edge of the screen.
        mode, x, y, scale = "free", nil, nil, 1
    end
    local key = ("%s:%.1f:%.1f:%.3f"):format(mode, x or 0, y or 0, scale)
    if key == placed then
        return
    end
    placed = key
    frame:SetScale(scale)
    frame:ClearAllPoints()
    if mode == "free" then
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
    frame:Show()
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------
local function create()
    frame = CreateFrame("Frame", "ForeverGuideTracker", UIParent)
    frame:SetSize(WIDTH, HEADER_HEIGHT)
    frame:SetFrameStrata("LOW")

    header = CreateFrame("Button", nil, frame)
    header:SetSize(WIDTH, HEADER_HEIGHT)
    header:SetPoint("TOPLEFT")
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("UI-QuestTracker-Secondary-Objective-Header", true)
    background:SetPoint("CENTER")
    header.text = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
    header.text:SetPoint("LEFT", 7, 0)
    header.text:SetWidth(200)
    header.text:SetMaxLines(1)
    header.text:SetJustifyH("LEFT")
    header:SetScript("OnClick", function(self)
        ns.Menu.Open(self)
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -8, 0)
        GameTooltip:SetText(Engine.view.name or "Guide")
        GameTooltip:AddLine("Click for guide options.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", GameTooltip_Hide)

    glow = header:CreateTexture(nil, "OVERLAY")
    glow:SetAtlas("UI-QuestTracker-OBJFX-BarGlow", true)
    glow:SetPoint("CENTER", -120, 1)
    glow:SetAlpha(0)
    glow.anim = glow:CreateAnimationGroup()
    local fadeIn = glow.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    local fadeOut = glow.anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.6)
    fadeOut:SetOrder(2)

    -- Fold and unfold our own section; kept per character.
    header.minimize = CreateFrame("Button", nil, header)
    header.minimize:SetSize(16, 16)
    header.minimize:SetPoint("RIGHT", 1, 0)
    header.minimize:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
    header.minimize:SetScript("OnClick", function()
        ns.char.collapsed = not isCollapsed() or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        layout()
    end)

    contents = CreateFrame("Frame", nil, frame)
    contents:SetAllPoints()

    progress = CreateFrame("Frame", nil, contents, "ForeverGuideProgressBarTemplate")

    -- Keep up with the tracker: it grows, shrinks, folds and moves.
    local since = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 0.25 then
            since = 0
            follow()
        end
    end)
    -- OnUpdate stops while the frame is hidden (the tracker folded), so a
    -- frame of its own keeps looking for the unfold.
    local watcher = CreateFrame("Frame")
    local idle = 0
    watcher:SetScript("OnUpdate", function(_, elapsed)
        idle = idle + elapsed
        if idle >= 0.25 then
            idle = 0
            if not frame:IsShown() then
                follow()
            end
        end
    end)

    layout()
    follow()
end

ns.On("PLAYER_ENTERING_WORLD", function()
    if not frame then
        create()
    end
end)

-- Our own frame, so it is redrawn whenever the guide changes, combat or not.
ns.Listen("Updated", layout)
ns.Listen("Setting", function(key)
    if key == "progress" then
        layout()
    end
end)

-- For the tests.
ns.Section = { Layout = layout, Follow = follow }
