-- Text.lua: turn the markup of both guide formats into plain WoW text.
local _, ns = ...

local Text = {}
ns.Text = Text

-- Both formats colour names and warnings inside a line. RestedXP says what
-- kind of thing a name is (|cRXP_<KIND>_ ... |r); that is worth keeping: who
-- to talk to, what to kill, what to loot. Its own colours are made for a
-- dark panel and are hard to read over the world (orange on Durotar's
-- ground), so each kind gets a light colour from the game's own palette.
-- Warnings often run a whole sentence; they are the tracker's white.
local EMPHASIS = "ffffffff"
local KIND = {
    FRIENDLY = "ff7fe57f", -- someone to talk to: the green of friendly names
    ENEMY = "ffff8273",    -- something to kill: a light hostile red
    LOOT = "ff82c5ff",     -- an item: the light blue of links
    BUY = "ff82c5ff",
    PICK = "ffe0b0ff",     -- something in the world to use or pick up
    WARN = EMPHASIS,
}

-- WoW-Pro gives plain rrggbb colours, mostly pure red. Lightened towards
-- white they stay apart from each other and readable.
local function lighten(hex)
    local out = "ff"
    for part in hex:gmatch("%x%x") do
        local value = tonumber(part, 16)
        out = out .. ("%02x"):format(value + (255 - value) * 0.45)
    end
    return out
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
Text.trim = trim

function Text.RXP(s)
    if not s then
        return nil
    end
    s = s:gsub("|c[Rr][Xx][Pp]_(%u+)_", function(kind)
        return "|c" .. (KIND[kind] or EMPHASIS)
    end)
    -- "Name::12345" carries an npc id for targeting.
    s = s:gsub("::%d+", "")
    -- Inline textures are given a fixed pixel size; let the font decide.
    s = s:gsub("(|T[^|]-):%d+|t", "%1:0|t")
    s = s:gsub("\\n", "\n")
    return trim(s)
end

function Text.WoWPro(s)
    if not s then
        return nil
    end
    s = s:gsub("%[color=(%x%x%x%x%x%x)%]", function(hex)
        return "|c" .. lighten(hex)
    end)
    s = s:gsub("%[/color%]", "|r")
    s = s:gsub("%[(%l+)=([^%]]+)%]", function(kind, value)
        if kind == "money" then
            local copper = tonumber(value)
            if copper and GetCoinTextureString then
                return GetCoinTextureString(copper)
            end
            return value
        end
        -- [item=123/Name], [spell=123/Name], [quest=123/Name]
        local name = value:match("/(.+)$")
        return name or value
    end)
    s = s:gsub("\\n", "\n")
    -- We finish these steps ourselves, or offer a check box for them.
    s = s:gsub("|cff%x%x%x%x%x%xNOTE:%s*|r%s*Manually check this step off to continue%.?", "")
    return trim(s)
end

-- Text with every colour and texture removed, for menus and comparisons.
function Text.Plain(s)
    if not s then
        return ""
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|T.-|t", "")
    return trim(s)
end
