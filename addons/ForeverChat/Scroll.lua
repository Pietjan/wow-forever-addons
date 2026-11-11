-- Back to the newest line.
--
-- A chat window that has been scrolled up stays there until it is
-- scrolled down again, and meanwhile shows nothing new. This returns it
-- to the bottom once it has been left alone for a while (30 seconds
-- unless set otherwise).
--
-- "Left alone" means: the mouse is not over the window, and nobody has
-- scrolled it. New messages do not count as scrolling, although they do
-- move the window's scroll position: while scrolled up, the game shifts
-- it by one for every line that arrives, to keep the same text in view.
-- So lines added since the last look are counted, and a shift of at most
-- that many is put down to them.
--
-- The windows are looked at once a second. Nothing of Blizzard's is
-- replaced: the scroll position is read, and ScrollToBottom is the
-- message frame's own function, the one behind the jump-to-bottom button.

local _, ns = ...

local Scroll = {}
ns.Scroll = Scroll

local IsSecret = _G.issecretvalue or function() return false end

local tracked = {} -- frame -> { offset, added, since }

local function Track(frame)
	local entry = tracked[frame]
	if entry ~= nil then
		return entry
	end
	if type(frame.GetScrollOffset) ~= "function" or type(frame.ScrollToBottom) ~= "function" then
		tracked[frame] = false
		return false
	end
	entry = { offset = 0, added = 0, since = nil }
	tracked[frame] = entry
	if type(frame.AddMessage) == "function" then
		hooksecurefunc(frame, "AddMessage", function()
			entry.added = entry.added + 1
		end)
	end
	return entry
end

-- One look at one window. Returns true when it was sent to the bottom.
local function Check(frame, entry, now, delay)
	local offset = frame:GetScrollOffset()
	local added = entry.added
	entry.added = 0
	if IsSecret(offset) or type(offset) ~= "number" then
		return false
	end
	if offset <= 0 then
		entry.offset, entry.since = 0, nil
		return false
	end
	local previous = entry.offset
	entry.offset = offset
	local untouched = previous > 0 and offset >= previous and offset <= previous + added
	local watched = frame:IsVisible() and frame:IsMouseOver()
	if not entry.since or not untouched or watched then
		entry.since = now
		return false
	end
	if now - entry.since < delay then
		return false
	end
	frame:ScrollToBottom()
	entry.offset, entry.since = 0, nil
	return true
end

function Scroll.Init()
	C_Timer.NewTicker(1, function()
		local delay = tonumber(ns.db.scrollDown) or 0
		if delay <= 0 then
			return
		end
		local now = GetTime()
		ns.ForEachChatFrame(function(frame)
			local entry = Track(frame)
			if entry then
				pcall(Check, frame, entry, now, delay)
			end
		end)
	end)
end

-- For the tests.
Scroll.Track = Track
Scroll.Check = Check
