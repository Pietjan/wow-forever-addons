-- Menu.lua: the guide menu (the game's context menu) and the /fg command.
local _, ns = ...

local Engine = ns.Engine
local Registry = ns.Registry

local Menu = {}
ns.Menu = Menu

-- Menu pieces that not every client build has are optional.
local function divider(parent)
    if parent.CreateDivider then
        parent:CreateDivider()
    end
end

local function disable(element)
    if element and element.SetEnabled then
        element:SetEnabled(false)
    end
end

local function guideButton(parent, guide)
    local function start()
        Engine:Start(guide.key)
    end
    if parent.CreateRadio then
        parent:CreateRadio(guide.name, function()
            return Engine:Current() == guide
        end, start)
    else
        parent:CreateButton(guide.name, start)
    end
end

local function guideList(parent)
    -- group -> subgroup -> guides, in registry order
    local groups, order = {}, {}
    for _, guide in ipairs(Registry.list) do
        local group = groups[guide.group]
        if not group then
            group = { subs = {}, order = {} }
            groups[guide.group] = group
            order[#order + 1] = guide.group
        end
        local key = guide.subgroup or ""
        if not group.subs[key] then
            group.subs[key] = {}
            group.order[#group.order + 1] = key
        end
        table.insert(group.subs[key], guide)
    end
    if #order == 0 then
        disable(parent:CreateButton("No guides installed"))
        return
    end
    -- One submenu per guide set and no deeper: the tracker sits at the
    -- screen edge, where every further level flips sides and lands on top
    -- of the menu before it. Subgroups are headings in a scrolling list.
    for _, name in ipairs(order) do
        local group = groups[name]
        local menu = parent:CreateButton(name)
        if menu.SetScrollMode then
            menu:SetScrollMode(480)
        end
        for _, key in ipairs(group.order) do
            if key ~= "" and #group.order > 1 then
                menu:CreateTitle(key)
            end
            for _, guide in ipairs(group.subs[key]) do
                guideButton(menu, guide)
            end
        end
    end
end

local function option(parent, text, key)
    local function toggle()
        ns.Set(key, not ns.db[key])
    end
    if parent.CreateCheckbox then
        parent:CreateCheckbox(text, function()
            return ns.db[key]
        end, toggle)
    else
        parent:CreateButton((ns.db[key] and "Turn off: " or "Turn on: ") .. text, toggle)
    end
end

local function build(_, root)
    local guide = Engine:Current()
    local view = Engine.view
    if guide and Engine:Paused() then
        root:CreateTitle(guide.name)
        root:CreateButton("Continue the guide", function()
            Engine:Resume()
        end)
        divider(root)
    elseif guide then
        root:CreateTitle(guide.name)
        if view.step and view.count then
            disable(root:CreateButton(("Step %d of %d"):format(view.step, view.count)))
        end
        local main = view.blocks[1]
        if main and main.id > 0 then
            root:CreateButton("Skip this step", function()
                Engine:CompleteStep(main.id)
            end)
        end
        root:CreateButton("Previous step", function()
            Engine:Back()
        end)
        divider(root)
    else
        root:CreateTitle("Leveling guide")
        local suggestions = Registry.Suggest()
        if #suggestions > 0 then
            for _, suggestion in ipairs(suggestions) do
                root:CreateButton(suggestion.name .. " |cff808080" .. suggestion.group .. "|r", function()
                    Engine:Start(suggestion.key)
                end)
            end
            divider(root)
        end
    end

    guideList(root)

    if guide then
        local leftovers = ns.Cleanup.Leftovers()
        if #leftovers > 0 then
            root:CreateButton(("Clean up the quest log (%d)"):format(#leftovers), function()
                ns.Cleanup.Offer()
            end)
        end
    end

    local options = root:CreateButton("Options")
    option(options, "Direction arrow", "arrow")
    option(options, "Lock the arrow in place", "arrowLocked")
    option(options, "Progress bar", "progress")
    option(options, "Map pin on the current goal", "pin")
    option(options, "Track only the quests of the current step", "watches")
    option(options, "Include group quests", "group")
    option(options, "Skip quests too low for my level", "skipLow")
    option(options, "Accept and turn in guide quests for me", "autoQuest")
    option(options, "Pause inside dungeons", "pauseInDungeon")
    option(options, "Offer to clean up the quest log after a guide", "cleanup")
    option(options, "Continue with the next guide", "autoNext")

    if guide then
        divider(root)
        if not Engine:Paused() then
            root:CreateButton("Pause the guide", function()
                Engine:Pause()
            end)
        end
        root:CreateButton("Restart this guide", function()
            Engine:Start(guide.key, true)
        end)
        root:CreateButton("Stop the guide", function()
            Engine:Stop()
        end)
    end
end

function Menu.Open(owner)
    MenuUtil.CreateContextMenu(owner or UIParent, build)
end

SLASH_FOREVERGUIDE1 = "/fg"
SLASH_FOREVERGUIDE2 = "/foreverguide"
SlashCmdList.FOREVERGUIDE = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "skip" or command == "next" then
        local main = Engine.view.blocks[1]
        if main and main.id > 0 then
            Engine:CompleteStep(main.id)
        end
    elseif command == "back" then
        Engine:Back()
    elseif command == "pause" then
        Engine:Pause()
    elseif command == "resume" or command == "continue" then
        Engine:Resume()
    elseif command == "cleanup" or command == "clean" then
        if not ns.Cleanup.Offer() then
            ns.Print("no quests in your log that the guides are done with.")
        end
    elseif command == "stop" then
        Engine:Stop()
    elseif command == "list" then
        for _, guide in ipairs(Registry.list) do
            print(("  %s  |cff808080%s|r"):format(guide.name, guide.group))
        end
        ns.Print(#Registry.list .. " guides for this character.")
    else
        Menu.Open(UIParent)
    end
end
