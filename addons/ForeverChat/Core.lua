-- ForeverChat: Blizzard's chat, kept as it is and finished off.
--
-- Five parts, each in its own file and each working on the default chat
-- frames, so the game's chat settings, tabs, Edit Mode and other addons
-- keep working:
--
--   Short.lua  short channel names: [1] [G] [P] [RL] instead of
--              [1. General - Orgrimmar] [Guild] [Party] [Raid Leader];
--              web addresses as links that open a copy box.
--   Skin.lua   Forever's own art on the chat frame: the bronze-edged dark
--              panels and gold tabs the rest of the interface uses, in
--              place of the 2004 tab, border and input-box textures.
--   Sync.lua   one chat setup for the whole account. The game stores
--              windows, tabs, message types, channels and colours per
--              character; this copies one saved setup to every character
--              at login and takes changes back at logout.
--   History.lua  the lines in the chat windows survive a reload.
--   Scroll.lua   a window left scrolled up goes back to the newest line.
--
-- On Forever, chat text and sender names are secret values to addon code
-- during boss fights and PvP matches, and Blizzard's chat code only works
-- on them while it runs untainted. So nothing here replaces a Blizzard
-- function or writes a Blizzard table: messages are touched in a post-hook
-- after Blizzard is done with them, art is added as new textures, and the
-- shared setup is written through the game's own chat-settings API and
-- read back by Blizzard's code.

local ADDON_NAME, ns = ...

local DEFAULTS = {
	short = "number", -- "number" [1], "name" [General], "off"
	links = true, -- web addresses in chat are links; a click offers to copy
	skin = true,
	input = "active", -- input box drawn only while typing ("active") or "always"
	history = true, -- chat lines come back after a reload
	arrows = true, -- arrow keys move the cursor in the input box without Alt
	follow = true, -- the tab that shows the chosen channel comes to the front
	scrollDown = 30, -- seconds before a scrolled-up window returns to the bottom; 0 is never
}

ns.defaults = DEFAULTS

-- The one place a setting changes: the slash command and the options window
-- (Options.lua) both come through here.
local AFTER = {
	arrows = function() ns.Skin.UpdateArrowKeys() end,
	input = function() ns.Skin.UpdateEditBoxes() end,
}

function ns.Set(key, value)
	ns.db[key] = value
	if AFTER[key] then
		AFTER[key]()
	end
end

local PREFIX = "|cffd9b77aForeverChat|r: "

function ns.Print(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	print(PREFIX .. text)
end

-- All chat frames that exist right now: the ten windows plus any whisper
-- windows opened since.
function ns.ForEachChatFrame(func)
	local names = _G.CHAT_FRAMES
	if not names then
		return
	end
	for _, name in ipairs(names) do
		local frame = _G[name]
		if frame then
			func(frame)
		end
	end
end

local function Usage()
	local db = ns.db
	ns.Print("the default chat, in Forever's style.")
	print("  |cffffd100/fchat save|r  make this character's chat setup the one all characters share")
	print("  |cffffd100/fchat load|r  put the shared setup on this character now")
	print("  |cffffd100/fchat layout|r  set up World, Trade and Loot tabs beside General on this character")
	print("  |cffffd100/fchat sync on|off|r  whether this character follows the shared setup (" .. (ns.Sync.IsEnabled() and "on" or "off") .. ")")
	print("  |cffffd100/fchat channels number|name|off|r  [1], [General] or the game's own names (" .. db.short .. ")")
	print("  |cffffd100/fchat links on|off|r  web addresses in chat open a copy box when clicked (" .. (db.links and "on" or "off") .. ")")
	print("  |cffffd100/fchat skin on|off|r  Forever art on the chat frame (" .. (db.skin and "on" or "off") .. ")")
	print("  |cffffd100/fchat combatlog last|second|r  where the Combat Log tab sits (" .. (db.combatLogLast and "last" or "second") .. ")")
	print("  |cffffd100/fchat scrolldown <seconds>|off|r  return a scrolled-up window to the newest line (" .. (db.scrollDown > 0 and (db.scrollDown .. " s") or "off") .. ")")
	print("  |cffffd100/fchat history on|off|r  keep the chat lines across a reload (" .. (db.history and "on" or "off") .. ")")
	print("  |cffffd100/fchat follow on|off|r  typing /2, /p, /g brings the tab that shows it to the front (" .. (db.follow and "on" or "off") .. ")")
	print("  |cffffd100/fchat arrows on|off|r  arrow keys move the cursor in the input box without Alt (" .. (db.arrows and "on" or "off") .. ")")
	print("  |cffffd100/fchat input active|always|r  show the input box only while typing, or always (" .. db.input .. ")")
	ns.Sync.Status()
end

local function Command(text)
	local command, argument = (text or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	local db = ns.db
	if command == "save" then
		ns.Sync.Save()
	elseif command == "load" then
		ns.Sync.Load()
	elseif command == "layout" then
		ns.Sync.Layout()
	elseif command == "sync" and (argument == "on" or argument == "off") then
		ns.Sync.SetEnabled(argument == "on")
	elseif command == "channels" and (argument == "number" or argument == "name" or argument == "off") then
		ns.Set("short", argument)
		ns.Print("channel names: %s. New messages use it; lines already in the window stay as they are.", argument)
	elseif command == "links" and (argument == "on" or argument == "off") then
		ns.Set("links", argument == "on")
		ns.Print(db.links and "web addresses in new chat lines can be clicked to copy." or "web addresses are left as text.")
	elseif command == "skin" and (argument == "on" or argument == "off") then
		ns.Set("skin", argument == "on")
		ns.Print("skin %s. Type /reload to see it.", argument)
	elseif command == "combatlog" and (argument == "last" or argument == "second") then
		ns.Set("combatLogLast", argument == "last")
		ns.Print("Combat Log tab %s. Type /reload to see it.", argument == "last" and "after the other tabs" or "back in second place")
	elseif command == "scrolldown" and (argument == "off" or tonumber(argument)) then
		local seconds = argument == "off" and 0 or math.floor(tonumber(argument))
		if seconds ~= 0 and (seconds < 5 or seconds > 600) then
			ns.Print("between 5 and 600 seconds, or off.")
		else
			ns.Set("scrollDown", seconds)
			ns.Print(seconds == 0 and "scrolled-up chat windows stay where you leave them."
				or ("a scrolled-up chat window returns to the newest line after " .. seconds .. " seconds."))
		end
	elseif command == "history" and (argument == "on" or argument == "off") then
		ns.Set("history", argument == "on")
		ns.Print(db.history and "chat lines are kept across a reload." or "chat windows start empty after a reload.")
	elseif command == "follow" and (argument == "on" or argument == "off") then
		ns.Set("follow", argument == "on")
		ns.Print(db.follow and "the tab that shows the channel you type to comes to the front." or "tabs stay where they are while you type.")
	elseif command == "arrows" and (argument == "on" or argument == "off") then
		ns.Set("arrows", argument == "on")
		ns.Print(db.arrows and "arrow keys move the cursor in the input box." or "arrow keys need Alt in the input box, as the game has it.")
	elseif command == "input" and (argument == "active" or argument == "always") then
		ns.Set("input", argument)
		ns.Print(argument == "active" and "the input box shows only while you type." or "the input box always shows.")
	else
		Usage()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")

	ForeverChatDB = ForeverChatDB or {}
	ForeverChatCharDB = ForeverChatCharDB or {}
	ns.db = ForeverChatDB
	ns.charDB = ForeverChatCharDB
	for key, value in pairs(DEFAULTS) do
		if ns.db[key] == nil then
			ns.db[key] = value
		end
	end

	-- The shared setup goes first: the earlier it is written, the better
	-- the odds that Blizzard's chat code reads it on its first pass.
	ns.Sync.Init()
	ns.Short.Init()
	ns.Skin.Init()
	ns.Skin.InitTabOrder()
	ns.Skin.InitArrowKeys()
	ns.Skin.InitFollow()
	ns.History.Init()
	ns.Scroll.Init()

	SLASH_FOREVERCHAT1 = "/fchat"
	SLASH_FOREVERCHAT2 = "/foreverchat"
	SlashCmdList.FOREVERCHAT = Command

	local ok, err = pcall(ns.RegisterSettings)
	if not ok then
		ns.Print("options panel unavailable (%s); use /fchat instead", tostring(err))
	end
end)
