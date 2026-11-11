-- Short channel names, and web addresses you can copy.
--
-- Blizzard builds a chat line as
--   [timestamp]|Hchannel:GUILD|h[Guild]|h |Hplayer:...|h[Name]|h: text
-- and for numbered channels
--   |Hchannel:channel:1|h[1. General - Orgrimmar]|h ...
-- The text between the brackets is display only; the link in front of it
-- is what a click acts on. So only the bracket text is rewritten.
--
-- The rewrite happens after the fact. Replacing AddMessage, or the
-- CHAT_*_GET format strings, would taint Blizzard's message handler, and
-- that handler has to stay clean to format the secret text of boss-fight
-- chat. hooksecurefunc runs our function after Blizzard's AddMessage and
-- throws its taint away, and TransformMessages is the door Blizzard left
-- for addons to change a line that is already in the window.
--
-- The same pass turns web addresses into links. The game cannot open a
-- browser or write to the clipboard, so a click opens a small box with
-- the address selected, ready for Ctrl+C. An address is something with
-- a scheme (https://...), a www. in front, or a name ending in a known
-- top-level domain, with an optional port and path; anything already
-- inside a link, texture or icon escape is left alone.

local _, ns = ...

local Short = {}
ns.Short = Short

-- Chat types whose tag gets a letter. The game's own tag is read from its
-- format string at load, so this follows the client language.
local TAGS = {
	GUILD = "G",
	OFFICER = "O",
	PARTY = "P",
	PARTY_LEADER = "PL",
	PARTY_GUIDE = "DG",
	MONSTER_PARTY = "P",
	RAID = "R",
	RAID_LEADER = "RL",
	INSTANCE_CHAT = "I",
	INSTANCE_CHAT_LEADER = "IL",
	GUILD_DISCORD = "GD",
}
local RAID_WARNING = "RW"

local CHANNEL_LINK = "|Hchannel:([^|]+)|h%[([^%]]*)%]|h"

local shortByLabel = {} -- "Party Leader" -> "PL"
local warningFrom, warningTo -- "[Raid Warning] " -> "[RW] "

-- Values the game marks secret cannot be compared or searched by addon
-- code. These two tell; on a client without secrets everything is open.
local IsSecret = _G.issecretvalue or function() return false end
local CanAccess = _G.canaccessvalue or function() return true end

local function BuildLabels(strings)
	wipe(shortByLabel)
	for chatType, short in pairs(TAGS) do
		local format = strings["CHAT_" .. chatType .. "_GET"]
		local label = type(format) == "string" and format:match("|h%[(.-)%]|h")
		if label then
			shortByLabel[label] = short
		end
	end
	local format = strings.CHAT_RAID_WARNING_GET
	local label = type(format) == "string" and format:match("^%[(.-)%]")
	if label then
		warningFrom, warningTo = "[" .. label .. "] ", "[" .. RAID_WARNING .. "] "
	else
		warningFrom, warningTo = nil, nil
	end
end

local mode = "number"

local function ShortLink(data, label)
	local short
	local number = data:match("^channel:(%d+)$")
	if number then
		if mode == "name" then
			-- "1. General - Orgrimmar" -> "General"
			short = label:gsub("^%d+%.%s*", ""):gsub("%s+%-%s.*$", "")
			if short == "" then
				short = number
			end
		else
			short = number
		end
	else
		short = shortByLabel[label]
	end
	if short and short ~= label then
		return "|Hchannel:" .. data .. "|h[" .. short .. "]|h"
	end
end

-- The shortened line, or nil when there is nothing to shorten.
function Short.Shorten(message, style)
	mode = style or "number"
	if mode == "off" then
		return nil
	end
	local result
	if message:find("|Hchannel:", 1, true) then
		local changed, count = message:gsub(CHANNEL_LINK, ShortLink, 1)
		if count > 0 and changed ~= message then
			result = changed
		end
	elseif warningFrom then
		-- No link on raid warnings. Only the tag in front of the sender
		-- counts: the same words typed into a message come after a link.
		local from, to = message:find(warningFrom, 1, true)
		if from and not message:sub(1, from - 1):find("|h", 1, true) then
			result = message:sub(1, from - 1) .. warningTo .. message:sub(to + 1)
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Web addresses

local URL_COLOR = "|cff6ab8ff"
local TLDS = {}
for tld in ("com net org gg io tv eu nl de uk be fr se no dk fi ch at pl es it ru us ca au nz jp kr br info me dev app gl ly to cc"):gmatch("%a+") do
	TLDS[tld] = true
end
-- Punctuation that ends a sentence rather than an address.
local TRAILING = "[%.,;:!%?%)%]'\"]+$"

-- The address in a word, or nil.
local function AddressIn(word)
	local trailing = word:match(TRAILING) or ""
	local body = word:sub(1, #word - #trailing)
	-- Round brackets around an address: "(see example.com)".
	local leading = body:match("^[%(%[]+") or ""
	body = body:sub(#leading + 1)
	if body == "" then
		return nil
	end
	local ok = false
	if body:match("^%a[%w+.-]*://[^/]") then
		ok = true
	elseif body:match("^www%.[%w%-]+%.%a%a+") then
		ok = true
	else
		local host = body:match("^([%w%-%.]+)") or ""
		local rest = body:sub(#host + 1)
		local tld = host:match("%.(%a+)$")
		if tld and TLDS[tld:lower()] and host:match("^[%w%-]+%.") and not host:match("%.%.")
			and (rest == "" or rest:match("^:%d+$") or rest:match("^:%d+/") or rest:match("^/")) then
			ok = true
		end
	end
	if not ok then
		return nil
	end
	return body, leading, trailing
end

local function LinkWords(text)
	-- Words begin after a space or at the start; a word right after "|"
	-- is an escape ("|cff00ff00", "|r") and the address, if any, comes
	-- after it.
	return text:gsub("()([^%s|]+)", function(start, word)
		local prefix = ""
		if start > 1 and text:sub(start - 1, start - 1) == "|" then
			local code = word:match("^c%x%x%x%x%x%x%x%x") or word:match("^[rn]")
			if not code then
				return nil
			end
			prefix, word = code, word:sub(#code + 1)
		end
		local address, leading, trailing = AddressIn(word)
		if not address then
			return nil
		end
		return prefix .. leading .. "|Hurl:" .. address .. "|h" .. URL_COLOR .. address .. "|r|h" .. trailing
	end)
end

-- The line with its addresses made into links, or nil when it has none.
function Short.LinkAddresses(message)
	if not message:find("%.%a") then
		return nil
	end
	local out, position, changed = {}, 1, false
	while position <= #message do
		-- The next stretch that must not be touched: a link with its
		-- text, a texture, or an atlas icon.
		local from, to
		for _, pattern in ipairs({ "|H.-|h.-|h", "|T.-|t", "|A.-|a" }) do
			local f, t = message:find(pattern, position)
			if f and (not from or f < from) then
				from, to = f, t
			end
		end
		local plain = message:sub(position, (from or #message + 1) - 1)
		if plain ~= "" then
			local linked = LinkWords(plain)
			if linked ~= plain then
				changed = true
			end
			out[#out + 1] = linked
		end
		if not from then
			break
		end
		out[#out + 1] = message:sub(from, to)
		position = to + 1
	end
	if not changed then
		return nil
	end
	return table.concat(out)
end

-- Everything this file does to a line, or nil when nothing applies.
function Short.Rewrite(message, style, links)
	local result = Short.Shorten(message, style)
	if links then
		result = Short.LinkAddresses(result or message) or result
	end
	return result
end

local copy

local function ShowCopy(address)
	if not copy then
		copy = CreateFrame("Frame", "ForeverChatCopyLink", UIParent, "TooltipBackdropTemplate")
		copy:SetFrameStrata("DIALOG")
		copy:SetSize(460, 92)
		copy:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		copy:EnableMouse(true)
		copy:SetMovable(true)
		copy:RegisterForDrag("LeftButton")
		copy:SetScript("OnDragStart", copy.StartMoving)
		copy:SetScript("OnDragStop", copy.StopMovingOrSizing)

		local title = copy:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		title:SetPoint("TOP", 0, -12)
		title:SetText("Copy link")

		local box = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
		box:SetSize(420, 22)
		box:SetPoint("TOP", title, "BOTTOM", 0, -8)
		box:SetAutoFocus(false)
		box:SetFontObject(ChatFontNormal)
		box:SetScript("OnEscapePressed", function()
			copy:Hide()
		end)
		box:SetScript("OnEnterPressed", function()
			copy:Hide()
		end)
		copy.box = box

		local hint = copy:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		hint:SetPoint("TOP", box, "BOTTOM", 0, -6)
		hint:SetText("Ctrl+C copies it. Enter or Escape closes.")

		if type(UISpecialFrames) == "table" then
			tinsert(UISpecialFrames, "ForeverChatCopyLink")
		end
	end
	copy.box:SetText(address)
	copy:Show()
	copy.box:SetFocus()
	copy.box:HighlightText()
end

local function OnLinkClicked(link)
	if IsSecret(link) or not CanAccess(link) or type(link) ~= "string" then
		return
	end
	local address = link:match("^url:(.+)$")
	if address then
		ShowCopy(address)
	end
end

local busy = false

local function OnAddMessage(frame, message)
	if busy or IsSecret(message) or not CanAccess(message) or type(message) ~= "string" then
		return
	end
	local shortened = Short.Rewrite(message, ns.db.short, ns.db.links)
	if not shortened then
		return
	end
	local function IsThisLine(text)
		return not IsSecret(text) and CanAccess(text) and text == message
	end
	local function Replace(_, ...)
		return shortened, ...
	end
	busy = true
	pcall(frame.TransformMessages, frame, IsThisLine, Replace)
	busy = false
end

local hooked = {}

local function HookFrame(frame)
	if hooked[frame] or type(frame.AddMessage) ~= "function" or type(frame.TransformMessages) ~= "function" then
		return
	end
	hooked[frame] = true
	hooksecurefunc(frame, "AddMessage", OnAddMessage)
end

function Short.Init()
	BuildLabels(_G)
	ns.ForEachChatFrame(HookFrame)
	-- Whisper windows are made on demand.
	if type(_G.FCF_OpenTemporaryWindow) == "function" then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			ns.ForEachChatFrame(HookFrame)
		end)
	end
	-- Clicks on links in chat go through SetItemRef.
	if type(_G.SetItemRef) == "function" then
		hooksecurefunc("SetItemRef", OnLinkClicked)
	elseif EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", function(_, _, link)
			OnLinkClicked(link)
		end, Short)
	end
end

-- For the tests.
Short.BuildLabels = BuildLabels
