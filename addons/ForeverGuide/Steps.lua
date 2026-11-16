-- Steps.lua: a window that lists every step of the running guide, in order,
-- with the text the tracker shows for it. Read-only: it marks what is done
-- and where the guide is, and changes nothing. A frame of our own; nothing
-- of the game's UI is called or written.
local _, ns = ...

local Engine = ns.Engine

local Steps = {}
ns.Steps = Steps

local WIDTH, HEIGHT = 420, 520
local PAD = 12              -- between the window's edge and the list
local TOP = 30              -- room for the title bar
local SCROLLBAR = 22
local NUMBER_WIDTH = 34     -- the column with the step numbers
local LINE_INDENT = 10
local LINE_SPACING = 2
local BETWEEN_STEPS = 10
local ABOVE_CURRENT = 8     -- room above the current step on opening

local COLOR = {
    current = { 1, 0.82, 0 },
    open = { 0.75, 0.61, 0 },
    done = { 0.7, 0.7, 0.7 },
    line = { 0.8, 0.8, 0.8 },
    lineDone = { 0.8, 0.8, 0.8 }, -- as readable as the rest: the title's colour says it is done
}

local frame, scroll, content, marker
local titles, lines = {}, {} -- pools: every row ever made
local shownFor               -- the guide the list was last scrolled for

local function number(value, fallback)
    return type(value) == "number" and value or fallback
end

local function textHeight(fontString)
    local height = fontString:GetStringHeight()
    return type(height) == "number" and height > 0 and height or 12
end

local function row(pool, n, font)
    local r = pool[n]
    if not r then
        r = content:CreateFontString(nil, "ARTWORK", font)
        r:SetJustifyH("LEFT")
        r:SetJustifyV("TOP")
        r:SetWordWrap(true)
        pool[n] = r
    end
    r:Show()
    return r
end

-- The game's scroll bar turns an offset into a share of the scroll range
-- and scrolls to that share. The range only follows the list's new height
-- a frame later, so an offset set right after a layout is measured against
-- the old range (none at all on first opening) and lands at the top or in
-- the wrong place. So: have the range brought up to date first, and set
-- the offset once more on the next frame.
local function scrollTo(offset)
    local function apply()
        if scroll.UpdateScrollChildRect then
            scroll:UpdateScrollChildRect()
        end
        local range = math.max(0, number(content:GetHeight(), 0) - number(scroll:GetHeight(), 0))
        scroll:SetVerticalScroll(math.max(0, math.min(range, offset)))
    end
    apply()
    C_Timer.After(0, function()
        if frame:IsShown() then
            apply()
        end
    end)
end

local function layout()
    if not frame or not frame:IsShown() then
        return
    end
    local list = Engine:Outline()
    local view = Engine.view
    local name = view and view.name or "Leveling guide"
    if frame.SetTitle then
        frame:SetTitle(name)
    elseif frame.title then
        frame.title:SetText(name)
    end

    local width = WIDTH - 2 * PAD - SCROLLBAR
    local textWidth = width - NUMBER_WIDTH
    local usedTitles, usedLines = 0, 0
    local y = 0
    local currentAt

    for _, block in ipairs(list) do
        local current = block.state == "current"
        local past = block.state == "done" or block.state == "left out"
        if current and not currentAt then
            currentAt = y
        end

        usedTitles = usedTitles + 1
        local num = row(titles, usedTitles * 2 - 1, "GameFontNormal")
        local title = row(titles, usedTitles * 2, "GameFontNormal")
        local color = COLOR[current and "current" or past and "done" or "open"]
        num:ClearAllPoints()
        num:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        num:SetWidth(NUMBER_WIDTH)
        num:SetText(block.id .. ".")
        num:SetTextColor(unpack(color))
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", content, "TOPLEFT", NUMBER_WIDTH, -y)
        title:SetWidth(textWidth)
        title:SetText((block.title or "") .. (block.state == "left out" and "  (left out)" or ""))
        title:SetTextColor(unpack(color))
        y = y + textHeight(title)

        for _, entry in ipairs(block.lines) do
            usedLines = usedLines + 1
            local line = row(lines, usedLines, "GameFontHighlightSmall")
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", content, "TOPLEFT", NUMBER_WIDTH + LINE_INDENT, -(y + LINE_SPACING))
            line:SetWidth(textWidth - LINE_INDENT)
            line:SetText(entry.text or "")
            line:SetTextColor(unpack((past or entry.done) and COLOR.lineDone or COLOR.line))
            y = y + LINE_SPACING + textHeight(line)
        end
        y = y + BETWEEN_STEPS
    end

    for n = usedTitles * 2 + 1, #titles do
        titles[n]:Hide()
    end
    for n = usedLines + 1, #lines do
        lines[n]:Hide()
    end
    if #list == 0 then
        local empty = row(titles, 2, "GameFontNormal")
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        empty:SetWidth(width)
        empty:SetText("No guide is running.")
        empty:SetTextColor(unpack(COLOR.line))
        y = textHeight(empty)
    end
    content:SetSize(width, math.max(1, y))

    -- A bar beside the steps the guide is on.
    if currentAt then
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", content, "TOPLEFT", -6, -currentAt)
        marker:SetSize(2, 14)
        marker:Show()
    else
        marker:Hide()
    end

    -- Opened, or another guide: bring the current step into view. After
    -- that the list stays where the reader left it.
    if shownFor ~= name then
        shownFor = name
        scrollTo((currentAt or 0) - ABOVE_CURRENT)
    end
    Steps.count = #list
end

local function create()
    local ok = pcall(function()
        frame = CreateFrame("Frame", "ForeverGuideSteps", UIParent, "DefaultPanelTemplate")
    end)
    if not ok or not frame then
        -- A build without that template: a plain dark panel.
        frame = CreateFrame("Frame", "ForeverGuideSteps", UIParent)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
        frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        frame.title:SetPoint("TOP", 0, -8)
    end
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local close
    if not pcall(function()
        close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    end) or not close then
        close = CreateFrame("Button", nil, frame)
        close:SetSize(20, 20)
        close:SetNormalFontObject("GameFontNormal")
        close:SetText("x")
    end
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    if not pcall(function()
        scroll = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
    end) or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            scrollTo(number(scroll:GetVerticalScroll(), 0) - delta * 40)
        end)
    end
    scroll:SetPoint("TOPLEFT", PAD + 6, -TOP)
    scroll:SetPoint("BOTTOMRIGHT", -(PAD + SCROLLBAR), PAD)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 2 * PAD - SCROLLBAR, 1)
    scroll:SetScrollChild(content)

    marker = content:CreateTexture(nil, "ARTWORK")
    marker:SetColorTexture(1, 0.82, 0, 0.9)
    marker:Hide()

    frame:SetScript("OnShow", function()
        shownFor = nil
        layout()
    end)
end

function Steps.Toggle()
    if not frame then
        create()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        -- OnShow draws it in the game; the offline harness has no OnShow.
        shownFor = nil
        layout()
    end
end

function Steps.Shown()
    return frame ~= nil and frame:IsShown() or false
end

-- Kept current while it is open.
ns.Listen("Updated", layout)
