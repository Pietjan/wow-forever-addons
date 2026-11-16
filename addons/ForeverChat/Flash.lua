-- One whisper, one notification.
--
-- A tab flashes when a whisper arrives in a window that is not in front,
-- and the game stops that flash only when that same window is shown. With
-- whispers in several tabs (General, World and Trade after /fchat layout)
-- each of the others flashes on its own and has to be visited to go quiet.
--
-- Here the windows that show whispers count as one:
--   - when one of them comes to the front, the flash stops on the rest;
--   - when a whisper arrives while one of them is in front, the rest do
--     not start flashing, as the game already has it for the one in front.
--
-- A whisper window of its own (chat style "new tab") shows one
-- conversation and is left alone.
--
-- Both happen in post-hooks on the game's own start and stop functions.
-- Those functions are not called from here: the flash is stopped with the
-- same ChatFrameUtil calls they make, which keep their state in tables
-- read through securecallfunction, made for callers like this one. What
-- is skipped is the fade bookkeeping (shared with every fading frame) and
-- the pulse on the dock's overflow arrow, which the game works out again
-- at its next tab update.

local _, ns = ...

local Flash = {}
ns.Flash = Flash

local function ShowsWhispers(frame)
	return not frame.chatType and type(frame.ContainsMessageGroup) == "function"
		and (frame:ContainsMessageGroup("WHISPER") or frame:ContainsMessageGroup("BN_WHISPER")) and true or false
end

local function Quiet(frame)
	local tab = _G[frame:GetName() .. "Tab"]
	if not tab or not ChatFrameUtil.IsTabAlerting(tab) then
		return
	end
	local glow = tab.glow
	if glow and glow.FlashAnim then
		ChatFrameUtil.StopFlash(glow, glow.FlashAnim, false)
	end
	glow = frame.minFrame and frame.minFrame.glow
	if glow and glow.FlashAnim then
		ChatFrameUtil.StopFlash(glow, glow.FlashAnim, false)
	end
	ChatFrameUtil.SetTabAlerting(tab, false)

	-- Only a docked tab that is not in front can be flashing, so these are
	-- the alphas of such a tab at rest.
	local mouseOver = _G.CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA or 0.6
	local noMouse = _G.CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA or 0.2
	ChatFrameUtil.SetTabAlphas(tab, mouseOver, noMouse)
	tab:SetAlpha(frame.hasBeenFaded and mouseOver or noMouse)
end

-- A window that shows whispers has been shown: the others have been read.
function Flash.Stopped(frame)
	if not ShowsWhispers(frame) then
		return
	end
	ns.ForEachChatFrame(function(other)
		if other ~= frame and ShowsWhispers(other) then
			Quiet(other)
		end
	end)
end

-- A tab starts flashing: not if the whisper is already in front elsewhere.
function Flash.Started(frame)
	if not ShowsWhispers(frame) then
		return
	end
	local inFront = false
	ns.ForEachChatFrame(function(other)
		if other ~= frame and other:IsShown() and ShowsWhispers(other) then
			inFront = true
		end
	end)
	if inFront then
		Quiet(frame)
	end
end

function Flash.Init()
	local util = _G.ChatFrameUtil
	if not util or not util.IsTabAlerting or not util.SetTabAlerting or not util.SetTabAlphas or not util.StopFlash
		or type(_G.FCF_StartAlertFlash) ~= "function" or type(_G.FCF_StopAlertFlash) ~= "function" then
		return
	end
	hooksecurefunc("FCF_StopAlertFlash", function(frame)
		pcall(Flash.Stopped, frame)
	end)
	hooksecurefunc("FCF_StartAlertFlash", function(frame)
		pcall(Flash.Started, frame)
	end)
end
