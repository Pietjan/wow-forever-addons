-- A community channel that is joined but dead.
--
-- A community's chat shows in the chat windows as a numbered channel
-- (Community:<club>:<stream>), and behind it sits a subscription to that
-- community's stream. The game sometimes logs in with the channel joined
-- and listed in the window but the stream not subscribed: nothing sent
-- there goes out and nothing said there comes in. Seen in game on
-- 2026-11-16, with and without addons: the channel was on number 6 and in
-- the window, C_Club.IsSubscribedToStream said false, and after
-- C_Club.FocusStream it said true and the chat came through.
-- C_Club.AddClubStreamChatChannel did not help. FocusStream is what the
-- Guild & Communities window calls when a stream is picked there.
--
-- That alone is half of it: with only FocusStream, messages could be sent
-- but none arrived in the chat window, though the window listed the
-- channel and the stream read as subscribed. They arrived after
-- C_Club.FocusCommunityStreams(), the call Blizzard's own code makes when
-- chat is switched back on in the settings (ChatConfigFrame.lua). It was
-- only tried after FocusStream, so both are made here, in that order.
--
-- So, out of combat: every joined community channel whose stream is not
-- subscribed gets FocusStream, then FocusCommunityStreams follows once,
-- and one line in chat says so. Only the channel list and C_Club are
-- used; no chat frame is read or written.

local _, ns = ...

local Community = {}
ns.Community = Community

local MAX_CHANNELS = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatChannels) or 20
local MAX_ATTEMPTS = 3 -- per stream and session
local RETRY_SECONDS = 15 -- a subscription takes a moment to arrive
local SETTLE_SECONDS = 5 -- after login or a change, before looking

local state = {
	attempts = {}, -- channel name -> { count, last, gaveUp }
	timer = false,
	afterCombat = false,
}

-- The community channels this character is in: { name, clubId, streamId }.
local function Joined()
	local list = {}
	for i = 1, MAX_CHANNELS do
		local _, name, _, isCommunity = GetChannelName(i)
		if isCommunity and type(name) == "string" then
			local clubId, streamId = name:match("^Community:(%d+):(%d+)$")
			if clubId then
				list[#list + 1] = { name = name, clubId = tonumber(clubId), streamId = tonumber(streamId) }
			end
		end
	end
	return list
end

local function ClubName(clubId)
	local ok, info = pcall(C_Club.GetClubInfo, clubId)
	return ok and type(info) == "table" and info.name or tostring(clubId)
end

-- One pass. Returns how many streams were asked for, for the tests.
function Community.Check(now)
	if InCombatLockdown() then
		state.afterCombat = true
		return 0
	end
	local asked = 0
	for _, channel in ipairs(Joined()) do
		-- Before the game has loaded the communities these calls fail;
		-- a later event brings the pass back.
		local ok, subscribed = pcall(C_Club.IsSubscribedToStream, channel.clubId, channel.streamId)
		local attempt = state.attempts[channel.name]
		if ok and subscribed then
			state.attempts[channel.name] = nil
		elseif ok and subscribed == false then
			if not attempt then
				attempt = { count = 0, last = -math.huge }
				state.attempts[channel.name] = attempt
			end
			if attempt.count >= MAX_ATTEMPTS then
				if not attempt.gaveUp and now - attempt.last >= RETRY_SECONDS then
					attempt.gaveUp = true
					ns.Print("the chat of %s is still not connected. Opening Guild & Communities and picking it there may help.", ClubName(channel.clubId))
				end
			elseif now - attempt.last >= RETRY_SECONDS then
				if attempt.count == 0 then
					ns.Print("the chat of %s was joined but not connected; connecting it.", ClubName(channel.clubId))
				end
				attempt.count = attempt.count + 1
				attempt.last = now
				pcall(C_Club.FocusStream, channel.clubId, channel.streamId)
				asked = asked + 1
			end
		end
	end
	if asked > 0 and type(C_Club.FocusCommunityStreams) == "function" then
		pcall(C_Club.FocusCommunityStreams)
	end
	return asked
end

-- Whether a stream is still waiting for its subscription or another try.
local function Waiting()
	for _, attempt in pairs(state.attempts) do
		if not attempt.gaveUp then
			return true
		end
	end
	return false
end

local function Schedule(seconds)
	if state.timer then
		return
	end
	state.timer = true
	C_Timer.After(seconds, function()
		state.timer = false
		pcall(Community.Check, GetTime())
		if Waiting() then
			Schedule(RETRY_SECONDS)
		end
	end)
end

function Community.Init()
	if type(C_Club) ~= "table" or type(C_Club.IsSubscribedToStream) ~= "function" or type(C_Club.FocusStream) ~= "function"
		or type(C_Club.GetClubInfo) ~= "function" or type(GetChannelName) ~= "function" then
		return
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({
		"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "CHANNEL_UI_UPDATE",
		"INITIAL_CLUBS_LOADED", "CLUB_STREAMS_LOADED", "CLUB_STREAM_UNSUBSCRIBED",
	}) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if not state.afterCombat then
				return
			end
			state.afterCombat = false
		end
		Schedule(SETTLE_SECONDS)
	end)
end
