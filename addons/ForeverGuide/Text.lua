-- Text.lua: turn the markup of both guide formats into plain WoW text.
local _, ns = ...

local Text = {}
ns.Text = Text

-- Both formats colour names and warnings inside a line (RestedXP with
-- |cRXP_<KIND>_ ... |r, WoW-Pro with [color=rrggbb]). The tracker has no
-- colours of its own inside a line, and coloured text is hard to read over
-- the world (orange on Durotar's ground), so every such colour becomes the
-- tracker's white: the name stands out from the grey line and no more.
local EMPHASIS = "ffffffff"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
Text.trim = trim

function Text.RXP(s)
    if not s then
        return nil
    end
    s = s:gsub("|c[Rr][Xx][Pp]_%u+_", "|c" .. EMPHASIS)
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
    s = s:gsub("%[color=%x%x%x%x%x%x%]", "|c" .. EMPHASIS)
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
