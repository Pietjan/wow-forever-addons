-- One chat setup for every character.
--
-- The game keeps chat settings per character (chat-cache.txt in the
-- character's WTF folder): the windows and tabs, their names, font size
-- and background, which message types and channels each shows, where
-- loose windows sit, and the colour of every chat type. This keeps one
-- copy of all that in the account-wide saved variables:
--
--   /fchat save   on the character whose chat is right, once.
--   login         any character that differs is given the saved setup.
--   logout        what the character has then becomes the saved setup,
--                 so a change made anywhere reaches the others.
--
-- Everything is read and written through the game's own chat-settings
-- functions (GetChatWindowInfo, AddChatWindowMessages, ChangeChatColor
-- and the like), never through Blizzard's frames. Colours take effect at
-- once: the game announces them and Blizzard's code repaints. Windows are
-- only read by Blizzard's code when the game announces UPDATE_CHAT_WINDOWS
-- at login, so the setup is written as early as possible, before that;
-- if it turns out to have been written too late, a reload makes Blizzard
-- read it, and a small prompt offers one.
--
-- What is deliberately not shared:
--   - Where the main chat window sits and how big it is. That is Edit
--     Mode's, and Edit Mode layouts are account-wide already.
--   - Which tab was in front at logout.
--   - Channels a character has not joined. A channel is only taken out of
--     a window where some character had joined it and was not showing it
--     there, and only put into a window on characters that are in it. So
--     a guild or community channel on one character survives a visit to
--     a character that is not a member.
--   - Channel colours by number. They are kept by channel name, since the
--     same channel has different numbers on different characters.

local _, ns = ...

local Sync = {}
ns.Sync = Sync

local MAX_WINDOWS = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows) or 10
local PROFILE_VERSION = 1

local function Flag(value)
	return value and true or false
end

local function Near(a, b, tolerance)
	return math.abs((a or 0) - (b or 0)) <= (tolerance or 0.004)
end

-- The settings functions are old globals; any of them missing or failing
-- must not take the rest down.
local function Call(name, ...)
	local func = _G[name]
	if type(func) ~= "function" then
		return false
	end
	return pcall(func, ...)
end

---------------------------------------------------------------------------
-- Reading the character's settings

local function ReadWindow(index)
	local name, size, r, g, b, a, shown, locked, docked, uninteractable = GetChatWindowInfo(index)
	local window = {
		name = name or "",
		size = size or 0,
		r = r or 0, g = g or 0, b = b or 0, a = a or 0,
		shown = Flag(shown),
		locked = Flag(locked),
		docked = (type(docked) == "number" and docked > 0) and docked or false,
		uninteractable = Flag(uninteractable),
		messages = {},
		channels = {},
		zones = {},
	}
	for _, group in ipairs({ GetChatWindowMessages(index) }) do
		window.messages[group] = true
	end
	local channels = { GetChatWindowChannels(index) }
	for i = 1, #channels, 2 do
		local channel, zone = channels[i], channels[i + 1]
		if type(channel) == "string" then
			window.channels[channel] = true
			if type(zone) == "number" and zone > 0 then
				window.zones[channel] = true
			end
		end
	end
	if type(_G.GetChatWindowSavedPosition) == "function" then
		window.point, window.x, window.y = GetChatWindowSavedPosition(index)
	end
	if type(_G.GetChatWindowSavedDimensions) == "function" then
		window.width, window.height = GetChatWindowSavedDimensions(index)
	end
	return window
end

-- The channels this character is in right now: name -> number.
local function ReadJoined()
	local joined = {}
	if type(_G.GetChannelList) ~= "function" then
		return joined
	end
	local list = { GetChannelList() }
	for i = 1, #list, 3 do
		local id, name = list[i], list[i + 1]
		if type(id) == "number" and type(name) == "string" then
			joined[name] = id
		end
	end
	return joined
end

local function IsNumberedChannelType(chatType)
	return chatType:match("^CHANNEL%d+$") ~= nil
end

local function ReadColor(chatType)
	local info = ChatTypeInfo and ChatTypeInfo[chatType]
	if type(info) == "table" and info.r and info.g and info.b then
		return { r = info.r, g = info.g, b = info.b, class = Flag(info.colorNameByClass) }
	end
	return nil
end

---------------------------------------------------------------------------
-- Saving: the character's settings become the shared setup

local function Capture(previous, joined)
	previous = previous or {}
	local profile = {
		version = PROFILE_VERSION,
		savedBy = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"),
		savedAt = date("%Y-%m-%d %H:%M"),
		windows = {},
		zoneChannels = {},
		colors = {},
		channelColors = {},
	}
	for name in pairs(previous.zoneChannels or {}) do
		profile.zoneChannels[name] = true
	end
	for name, color in pairs(previous.channelColors or {}) do
		profile.channelColors[name] = color
	end

	for index = 1, MAX_WINDOWS do
		local window = ReadWindow(index)
		local before = previous.windows and previous.windows[index]
		-- true: shown in this window. false: a character was in the
		-- channel and did not show it here. Absent: nobody knows.
		local channels = {}
		for name, wanted in pairs(before and before.channels or {}) do
			channels[name] = wanted
		end
		for name in pairs(joined) do
			channels[name] = false
		end
		for name in pairs(window.channels) do
			channels[name] = true
		end
		for name in pairs(window.zones) do
			profile.zoneChannels[name] = true
		end
		window.channels = channels
		window.zones = nil
		if window.docked and before then
			-- Which docked tab was in front is not part of the setup.
			window.shown = Flag(before.shown)
		end
		profile.windows[index] = window
	end

	if type(ChatTypeInfo) == "table" then
		for chatType in pairs(ChatTypeInfo) do
			if type(chatType) == "string" and chatType ~= "REPLY" and not IsNumberedChannelType(chatType) then
				profile.colors[chatType] = ReadColor(chatType)
			end
		end
	end
	for name, id in pairs(joined) do
		local color = ReadColor("CHANNEL" .. id)
		if color then
			profile.channelColors[name] = color
		end
	end
	return profile
end

---------------------------------------------------------------------------
-- Applying: the shared setup goes onto the character

local function ApplyWindowSettings(index, wanted, current, Changed)
	if wanted.name ~= "" and wanted.name ~= current.name then
		Call("SetChatWindowName", index, wanted.name)
		Changed("name")
	end
	if wanted.size ~= current.size then
		Call("SetChatWindowSize", index, wanted.size)
		Changed("font size")
	end
	if not (Near(wanted.r, current.r) and Near(wanted.g, current.g) and Near(wanted.b, current.b)) then
		Call("SetChatWindowColor", index, wanted.r, wanted.g, wanted.b)
		Changed("background")
	end
	if not Near(wanted.a, current.a) then
		Call("SetChatWindowAlpha", index, wanted.a)
		Changed("opacity")
	end
	if wanted.uninteractable ~= current.uninteractable then
		Call("SetChatWindowUninteractable", index, wanted.uninteractable)
		Changed("interactable")
	end
	if wanted.docked ~= current.docked then
		Call("SetChatWindowDocked", index, wanted.docked or nil)
		Changed(wanted.docked and "docked" or "undocked")
	end
	if not wanted.docked then
		-- Docked tabs are locked by the game, and only the one in front
		-- counts as shown; neither says anything about the setup.
		if wanted.shown ~= current.shown then
			Call("SetChatWindowShown", index, wanted.shown)
			Changed("shown")
		end
		if wanted.locked ~= current.locked then
			Call("SetChatWindowLocked", index, wanted.locked)
			Changed("lock")
		end
		if index ~= 1 and wanted.point and wanted.x and wanted.y then
			if wanted.point ~= current.point or not Near(wanted.x, current.x, 0.0005) or not Near(wanted.y, current.y, 0.0005) then
				Call("SetChatWindowSavedPosition", index, wanted.point, wanted.x, wanted.y)
				Changed("position")
			end
		end
		if index ~= 1 and wanted.width and wanted.height then
			if not Near(wanted.width, current.width, 0.5) or not Near(wanted.height, current.height, 0.5) then
				Call("SetChatWindowSavedDimensions", index, wanted.width, wanted.height)
				Changed("size")
			end
		end
	end

	for group in pairs(wanted.messages) do
		if not current.messages[group] then
			Call("AddChatWindowMessages", index, group)
			Changed("shows " .. group)
		end
	end
	for group in pairs(current.messages) do
		if not wanted.messages[group] then
			Call("RemoveChatWindowMessages", index, group)
			Changed("hides " .. group)
		end
	end
end

-- Makes window `index` match the setup, noting what it had to change in
-- words for the player. With `only` (a set of channel names) nothing but
-- those channels is looked at.
local function ApplyWindow(profile, index, wanted, joined, changes, only)
	local current = ReadWindow(index)
	local label = "window " .. index
	local function Changed(what)
		changes[#changes + 1] = label .. " " .. what
	end

	local active = wanted.shown or wanted.docked
	if only then
		if not active then
			return
		end
	elseif not active then
		-- Closed in the setup. Close it here; what a closed window would
		-- show does not matter.
		if current.docked then
			Call("SetChatWindowDocked", index, nil)
			Changed("closed")
		end
		if current.shown then
			Call("SetChatWindowShown", index, false)
			if not current.docked then
				Changed("closed")
			end
		end
		return
	else
		ApplyWindowSettings(index, wanted, current, Changed)
	end

	for name, show in pairs(wanted.channels) do
		if only and not only[name] then
			-- not asked about
		elseif show and not current.channels[name] then
			-- Zone channels (General, Trade...) can be set before they
			-- are joined; others only once this character is in them.
			if profile.zoneChannels[name] or joined[name] then
				Call("AddChatWindowChannel", index, name)
				Changed("shows channel " .. name)
			end
		elseif not show and current.channels[name] then
			Call("RemoveChatWindowChannel", index, name)
			Changed("hides channel " .. name)
		end
	end
end

local function ApplyWindows(profile, joined, only)
	local changes = {}
	for index = 1, MAX_WINDOWS do
		local wanted = profile.windows and profile.windows[index]
		if wanted then
			-- A window that cannot be read (settings not loaded yet) is
			-- skipped; the check a few seconds into the session retries.
			pcall(ApplyWindow, profile, index, wanted, joined, changes, only)
		end
	end
	return changes
end

local function ApplyColor(chatType, wanted)
	local current = ReadColor(chatType)
	if not current then
		return false
	end
	local changed = false
	if not (Near(wanted.r, current.r) and Near(wanted.g, current.g) and Near(wanted.b, current.b)) then
		Call("ChangeChatColor", chatType, wanted.r, wanted.g, wanted.b)
		changed = true
	end
	if wanted.class ~= nil and wanted.class ~= current.class then
		Call("SetChatColorNameByClass", chatType, wanted.class)
		changed = true
	end
	return changed
end

-- Colours of the joined channels, or of those named in `only`.
local function ApplyChannelColors(profile, joined, only)
	local count = 0
	for name, id in pairs(joined) do
		local wanted = profile.channelColors and profile.channelColors[name]
		if wanted and (not only or only[name]) and ApplyColor("CHANNEL" .. id, wanted) then
			count = count + 1
		end
	end
	return count
end

-- The game keeps a channel's colour under the channel's number, and the
-- numbers move: a channel is left and the ones after it shift up, a channel
-- is rejoined, the list is dragged into another order. The colour then
-- stays behind on the number, under whatever channel sits there next. So
-- for the length of a session the colours are held by channel name
-- (`colors`: name -> colour) and put back on every change of the list.
--
-- A channel that has no colour on record, in the session or in the shared
-- setup, has never been coloured by the player: it gets the game's own
-- channel colour instead of what the number last carried.
local DEFAULT_CHANNEL_COLOR = { r = 1, g = 192 / 255, b = 192 / 255 }

local function FollowChannels(profile, joined, colors)
	local count = 0
	for name, id in pairs(joined) do
		local wanted = colors[name] or (profile.channelColors and profile.channelColors[name]) or DEFAULT_CHANNEL_COLOR
		colors[name] = wanted
		if ApplyColor("CHANNEL" .. id, wanted) then
			count = count + 1
		end
	end
	return count
end

-- The player picks another colour for a channel, or switches its class
-- colours: that is the channel's colour from now on. `change` is
-- { r, g, b } or { class = flag }.
local function NoteChannelColor(chatType, change, joined, colors)
	local id = type(chatType) == "string" and tonumber(chatType:match("^CHANNEL(%d+)$"))
	if not id then
		return
	end
	for name, number in pairs(joined) do
		if number == id then
			local known = colors[name] or ReadColor(chatType) or DEFAULT_CHANNEL_COLOR
			local color = { r = known.r, g = known.g, b = known.b, class = known.class }
			if change.class ~= nil then
				color.class = change.class
			else
				color.r, color.g, color.b = change.r, change.g, change.b
			end
			colors[name] = color
		end
	end
end

local function ApplyColors(profile, joined)
	local count = 0
	for chatType, wanted in pairs(profile.colors or {}) do
		if chatType ~= "REPLY" and not IsNumberedChannelType(chatType) and ApplyColor(chatType, wanted) then
			count = count + 1
		end
	end
	return count + ApplyChannelColors(profile, joined)
end

---------------------------------------------------------------------------
-- The reload prompt

local prompt

local function Reload()
	local reload = (C_UI and C_UI.Reload) or ReloadUI
	reload()
end

local function ShowPrompt(message)
	if not prompt then
		prompt = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
		prompt:SetFrameStrata("DIALOG")
		prompt:SetPoint("TOP", UIParent, "TOP", 0, -180)
		prompt:SetSize(360, 110)
		prompt:EnableMouse(true)

		prompt.title = prompt:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		prompt.title:SetPoint("TOP", 0, -14)
		prompt.title:SetText("ForeverChat")

		prompt.text = prompt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		prompt.text:SetPoint("TOP", prompt.title, "BOTTOM", 0, -8)
		prompt.text:SetWidth(320)

		local reload = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
		reload:SetSize(120, 22)
		reload:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -6, 14)
		reload:SetText("Reload now")
		reload:SetScript("OnClick", Reload)

		local later = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
		later:SetSize(120, 22)
		later:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 6, 14)
		later:SetText("Later")
		later:SetScript("OnClick", function()
			prompt:Hide()
		end)
	end
	prompt.text:SetText(message)
	prompt:SetHeight(math.max(110, prompt.text:GetStringHeight() + 84))
	prompt:Show()
end

---------------------------------------------------------------------------
-- When what happens

local state = {
	ready = false, -- login has settled; logout may save
	unread = false, -- windows were written and Blizzard has not read them since
	changes = {}, -- what was written this session
	joined = {},
	seen = {}, -- channels already dealt with this session
	colors = {}, -- channel name -> its colour this session (see FollowChannels)
	verified = false,
	timer = false,
}

function Sync.IsEnabled()
	return ns.charDB.sync ~= false
end

local function Profile()
	local profile = ns.db.profile
	if type(profile) == "table" and type(profile.windows) == "table" then
		return profile
	end
	return nil
end

local function Summary(changes)
	local shown = {}
	for i = 1, math.min(#changes, 6) do
		shown[i] = changes[i]
	end
	local text = table.concat(shown, ", ")
	if #changes > #shown then
		text = text .. " and " .. (#changes - #shown) .. " more"
	end
	return text
end

-- Windows were written while Blizzard's chat code was not looking. Offer
-- the reload that makes it look, unless a reload was already tried for
-- exactly these changes: then the game is not keeping them, and asking
-- again every login would be a loop.
local function OfferReload(changes, insist, message)
	local unique, seen = {}, {}
	for _, change in ipairs(changes) do
		if not seen[change] then
			seen[change] = true
			unique[#unique + 1] = change
		end
	end
	table.sort(unique)
	changes = unique
	local key = table.concat(changes, ";")
	local char = ns.charDB
	if not insist and key ~= "" and char.asked == key then
		if char.refused ~= key then
			char.refused = key
			ns.Print("the game did not keep part of the shared chat setup on this character (%s). Left as it is.", Summary(changes))
		end
		return
	end
	char.asked = key
	ShowPrompt(message or "This character now has your shared chat setup.\nReload the interface to show it.")
end

local function Write(joined, only)
	local profile = Profile()
	if not profile then
		return {}
	end
	local changes = ApplyWindows(profile, joined, only)
	if #changes > 0 then
		state.unread = true
		for _, change in ipairs(changes) do
			state.changes[#state.changes + 1] = change
		end
	end
	return changes
end

-- A few seconds into the session: is the character on the shared setup,
-- and has Blizzard's chat code seen it?
local function Verify()
	state.verified = true
	local profile = Profile()
	if not profile then
		state.ready = true
		return
	end
	if not Sync.IsEnabled() then
		state.ready = true
		return
	end
	state.joined = ReadJoined()
	for name in pairs(state.joined) do
		state.seen[name] = true
	end
	Write(state.joined)
	ApplyColors(profile, state.joined)
	FollowChannels(profile, state.joined, state.colors)
	if state.unread then
		OfferReload(state.changes)
	else
		ns.charDB.asked, ns.charDB.refused = nil, nil
	end
	state.ready = true
end

-- Channels are joined some seconds after login, and Trade and the like
-- come and go with the zone. A channel seen for the first time this
-- session gets its place in the windows, and every channel gets its colour
-- back (kept by name) in case its number moved. Nothing else is touched
-- after login: from then on the settings are the player's to change, and
-- logout saves what they made of them.
local function OnChannelsChanged()
	state.timer = false
	local profile = Profile()
	if not state.ready then
		return
	end
	state.joined = ReadJoined()
	local fresh
	for name in pairs(state.joined) do
		if not state.seen[name] then
			state.seen[name] = true
			fresh = fresh or {}
			fresh[name] = true
		end
	end
	if not profile or not Sync.IsEnabled() then
		return
	end
	-- Every channel, not only the new ones: the numbers may have moved.
	FollowChannels(profile, state.joined, state.colors)
	if not fresh then
		return
	end
	local changes = Write(state.joined, fresh)
	if #changes > 0 then
		OfferReload(state.changes)
	end
end

local function Save()
	local joined = ReadJoined()
	if next(joined) == nil then
		joined = state.joined
	end
	ns.db.profile = Capture(Profile(), joined)
end

function Sync.Save()
	Save()
	ns.charDB.sync = true
	ns.charDB.asked, ns.charDB.refused = nil, nil
	state.ready = true
	local windows = 0
	for _, window in pairs(ns.db.profile.windows) do
		if window.shown or window.docked then
			windows = windows + 1
		end
	end
	ns.Print("saved. This character's chat (%d windows, their messages, channels and colours) is now the setup every character gets at login.", windows)
end

function Sync.Load()
	local profile = Profile()
	if not profile then
		ns.Print("nothing saved yet. Type |cffffd100/fchat save|r on the character whose chat you like.")
		return
	end
	state.joined = ReadJoined()
	for name in pairs(state.joined) do
		state.seen[name] = true
	end
	local changes = Write(state.joined)
	state.colors = {}
	local colors = ApplyColors(profile, state.joined)
	colors = colors + FollowChannels(profile, state.joined, state.colors)
	if #changes > 0 or state.unread then
		OfferReload(state.changes, true)
	elseif colors > 0 then
		ns.Print("%d colours set from the shared setup.", colors)
	else
		ns.Print("this character already has the shared setup.")
	end
end

function Sync.SetEnabled(enabled)
	ns.charDB.sync = enabled
	if enabled then
		ns.Print("this character follows the shared chat setup again. |cffffd100/fchat load|r puts it on now.")
	else
		ns.Print("this character keeps its own chat setup: nothing is applied at login or saved at logout.")
	end
end

---------------------------------------------------------------------------
-- A starting layout

-- /fchat layout: three tabs beside General and the combat log.
--
--   General  keeps what it has, minus what the new tabs take over: the
--            public channels and the loot and progress messages. So it
--            is left with people talking to you.
--   World    General, LocalDefense, LookingForGroup.
--   Trade    Trade, Trade (Services), Trade (Local).
--   Loot     loot, money, currency, skill-ups, experience, reputation,
--            honour, trade skills.
--
-- The Combat Log tab is moved behind them (see Skin.lua for how).
-- World and Trade also show whispers, so a reply to something answered
-- there is seen without switching tabs. Channels the game does not know
-- and custom or community channels are not touched. A tab that already
-- exists under the same name is reused, so running it twice is harmless.
local LOOT_GROUPS = {
	"LOOT", "MONEY", "CURRENCY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_FACTION_CHANGE",
	"COMBAT_HONOR_GAIN", "GUILD_ITEM_LOOTED", "TRADESKILLS",
}
local WHISPER_GROUPS = { "WHISPER", "BN_WHISPER" }
-- The game's own channels by their ID in its channel table, with the
-- English name in case the lookup is missing.
local LAYOUT_TABS = {
	{ name = "World", groups = WHISPER_GROUPS, channels = { { 1, "General" }, { 22, "LocalDefense" }, { 26, "LookingForGroup" } } },
	{ name = "Trade", groups = WHISPER_GROUPS, channels = { { 2, "Trade" }, { 42, "Services" }, { 46, "TradeLocal" } } },
	{ name = "Loot", groups = LOOT_GROUPS, channels = {} },
}

local function ChannelName(channel)
	local lookup = C_ChatInfo and C_ChatInfo.GetChannelShortcutForChannelID
	if lookup then
		local ok, name = pcall(lookup, channel[1])
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	return channel[2]
end

local function KnownGroups(groups)
	local known = {}
	for _, group in ipairs(groups) do
		if type(ChatTypeGroup) ~= "table" or ChatTypeGroup[group] then
			known[group] = true
		end
	end
	return known
end

-- The layout as window settings, in the shape a saved setup has, for the
-- windows it concerns. Returns nil and the tab's name when there is no
-- free window left for it.
local function BuildLayout()
	local reserved = 3
	if C_ChatInfo and C_ChatInfo.GetNumReservedChatWindows then
		reserved = C_ChatInfo.GetNumReservedChatWindows() or reserved
	end
	local current, lastDock = {}, 0
	for index = 1, MAX_WINDOWS do
		current[index] = ReadWindow(index)
		if current[index].docked and current[index].docked > lastDock then
			lastDock = current[index].docked
		end
	end

	local layout = { windows = {}, zoneChannels = {} }
	local main = current[1]
	local taken = {}
	local mainChannels = {}

	for _, tab in ipairs(LAYOUT_TABS) do
		local index
		for candidate = reserved + 1, MAX_WINDOWS do
			if current[candidate].name == tab.name and not taken[candidate] then
				index = candidate
				break
			end
		end
		if not index then
			for candidate = reserved + 1, MAX_WINDOWS do
				local window = current[candidate]
				if not window.shown and not window.docked and not taken[candidate] then
					index = candidate
					break
				end
			end
		end
		if not index then
			return nil, tab.name
		end
		taken[index] = true

		local existing = current[index]
		local docked = existing.docked
		local loose = existing.shown and not existing.docked -- the player pulled it out of the dock
		if not docked and not loose then
			lastDock = lastDock + 1
			docked = lastDock
		end
		local channels = {}
		for _, channel in ipairs(tab.channels) do
			local name = ChannelName(channel)
			channels[name] = true
			mainChannels[name] = false
			layout.zoneChannels[name] = true
		end
		layout.windows[index] = {
			name = tab.name,
			size = main.size, r = main.r, g = main.g, b = main.b, a = main.a,
			shown = loose and true or false,
			locked = not loose or existing.locked,
			docked = docked,
			uninteractable = main.uninteractable,
			messages = KnownGroups(tab.groups),
			channels = channels,
		}
	end

	-- General: as it is, without what moved out.
	local messages = {}
	for group in pairs(main.messages) do
		messages[group] = true
	end
	for _, group in ipairs(LOOT_GROUPS) do
		messages[group] = nil
	end
	main.messages = messages
	main.channels = mainChannels
	main.zones = nil
	main.point, main.x, main.y, main.width, main.height = nil, nil, nil, nil, nil
	layout.windows[1] = main
	return layout
end

function Sync.Layout()
	local layout, noRoom = BuildLayout()
	if not layout then
		ns.Print("no free chat window left for the %s tab. Close one (right-click its tab) and try again.", noRoom)
		return
	end
	local movedCombatLog = not ns.db.combatLogLast
	ns.db.combatLogLast = true
	state.joined = ReadJoined()
	local changes = ApplyWindows(layout, state.joined)
	if #changes == 0 then
		if movedCombatLog then
			ns.Print("the tabs were already set up; the Combat Log tab goes last after a /reload.")
		else
			ns.Print("the World, Trade and Loot tabs are already set up.")
		end
		return
	end
	state.unread = true
	for _, change in ipairs(changes) do
		state.changes[#state.changes + 1] = change
	end
	local followUp = Profile() and Sync.IsEnabled() and "your other characters get them at their next login"
		or "type |cffffd100/fchat save|r when you are happy with them, to share them with your other characters"
	ns.Print("World, Trade and Loot tabs set up; after the reload, %s.", followUp)
	if not state.joined[ChannelName({ 26, "LookingForGroup" })] then
		ns.Print("this character is not in LookingForGroup; |cffffd100/join LookingForGroup|r to see it in World.")
	end
	OfferReload(state.changes, true, "The World, Trade and Loot tabs are set up.\nReload the interface to show them.")
end

function Sync.Status()
	local profile = Profile()
	if profile then
		print(("  Shared setup: saved from %s, %s."):format(profile.savedBy or "?", profile.savedAt or "?"))
	else
		print("  Shared setup: none yet. Type /fchat save on the character whose chat you like.")
	end
end

function Sync.Init()
	-- What the player changes in the chat settings, by channel name. These
	-- run after Blizzard's functions and read only their arguments.
	if type(hooksecurefunc) == "function" then
		if type(_G.ChangeChatColor) == "function" then
			hooksecurefunc("ChangeChatColor", function(chatType, r, g, b)
				if state.ready and type(r) == "number" and type(g) == "number" and type(b) == "number" then
					NoteChannelColor(chatType, { r = r, g = g, b = b }, state.joined, state.colors)
				end
			end)
		end
		if type(_G.SetChatColorNameByClass) == "function" then
			hooksecurefunc("SetChatColorNameByClass", function(chatType, flag)
				if state.ready then
					NoteChannelColor(chatType, { class = Flag(flag) }, state.joined, state.colors)
				end
			end)
		end
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("UPDATE_CHAT_WINDOWS")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_LOGOUT")
	events:RegisterEvent("CHANNEL_UI_UPDATE")
	events:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_CHAT_WINDOWS" then
			-- Blizzard's chat frames are reading the settings right now.
			state.unread = false
		elseif event == "PLAYER_ENTERING_WORLD" then
			if not state.verified and not state.timer then
				state.timer = true
				C_Timer.After(3, function()
					state.timer = false
					Verify()
				end)
			end
		elseif event == "CHANNEL_UI_UPDATE" then
			if state.ready and not state.timer then
				state.timer = true
				C_Timer.After(2, OnChannelsChanged)
			end
		elseif event == "PLAYER_LOGOUT" then
			if state.ready and Sync.IsEnabled() and Profile() then
				pcall(Save)
			end
		end
	end)

	-- The early write. The chat settings are plain client data, so they
	-- can be set before the player is in the world; if this runs before
	-- the game tells the chat frames to read them, nothing more is needed.
	if Sync.IsEnabled() and Profile() then
		pcall(Write, {})
	end
end

-- For the tests.
Sync.BuildLayout = BuildLayout
Sync.Capture = Capture
Sync.ApplyWindows = ApplyWindows
Sync.ApplyColors = ApplyColors
Sync.FollowChannels = FollowChannels
Sync.NoteChannelColor = NoteChannelColor
