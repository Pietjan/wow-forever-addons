-- Chat history across a reload.
--
-- The game empties every chat window when the interface reloads. At
-- logout (a reload is one, as far as the interface can tell) the lines in
-- each window are written to this character's saved variables, and when
-- the interface comes back they are put back above whatever has been
-- printed since.
--
-- They come back after a reload, and after logging back in within a few
-- minutes, which covers a disconnect. A later login starts clean: chat
-- from an earlier evening is not what anyone wants to read first.
--
-- What is kept is the line as shown (text and colour), links included.
-- Not kept:
--   - the combat log, which the game rebuilds itself;
--   - whisper windows, which do not exist after a reload;
--   - lines whose text is secret to addons (chat during a boss fight or
--     PvP match): those cannot be read, let alone saved.
--
-- Lines are read with the message frame's own GetMessageInfo and put back
-- with BackFillMessage, the function Blizzard provides for adding older
-- lines above the newer ones.
--
-- The input box's own history, the lines you sent that Up and Down step
-- through, is kept as well. The game forgets it at every reload and
-- there is no way to read it back out of the box, so each line is noted
-- as the game adds it (a post-hook on AddHistoryLine) and fed back in at
-- the next load, reload or not. The box holds 32 lines; so does this.
--
-- With the arrow keys given to the cursor (see Skin.lua), the game no
-- longer steps through its history on Up and Down, so that is done here
-- from the same noted lines: Up goes back a line, Down forward, and past
-- the newest line whatever was being typed comes back. While the game's
-- name completion list is open, Up and Down are its.

local _, ns = ...

local History = {}
ns.History = History

local MAX_WINDOWS = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows) or 10
local MAX_LINES = 200 -- per window
local RELOG_SECONDS = 10 * 60

local IsSecret = _G.issecretvalue or function() return false end
local CanAccess = _G.canaccessvalue or function() return true end

local function Readable(value)
	return not IsSecret(value) and CanAccess(value)
end

local function Component(value)
	if Readable(value) and type(value) == "number" then
		return value
	end
	return nil
end

local function IsKept(frame)
	local id = frame:GetID()
	if type(id) ~= "number" or id < 1 or id > MAX_WINDOWS or frame.isTemporary then
		return false
	end
	if type(_G.IsCombatLog) == "function" and IsCombatLog(frame) then
		return false
	end
	return type(frame.GetNumMessages) == "function" and type(frame.GetMessageInfo) == "function"
		and type(frame.BackFillMessage) == "function"
end

-- The lines of one window, oldest first.
local function ReadLines(frame)
	local lines = {}
	local count = frame:GetNumMessages()
	if type(count) ~= "number" then
		return lines
	end
	for index = math.max(1, count - MAX_LINES + 1), count do
		local text, r, g, b = frame:GetMessageInfo(index)
		if Readable(text) and type(text) == "string" and text ~= "" then
			lines[#lines + 1] = { text = text, r = Component(r), g = Component(g), b = Component(b) }
		end
	end
	return lines
end

local function Save()
	if not ns.db.history then
		ns.charDB.history = nil
		return
	end
	local windows = {}
	ns.ForEachChatFrame(function(frame)
		if IsKept(frame) then
			local ok, lines = pcall(ReadLines, frame)
			if ok and #lines > 0 then
				windows[frame:GetID()] = lines
			end
		end
	end)
	ns.charDB.history = { at = time(), windows = windows }
end

local function Restore(isReload)
	local saved = ns.charDB.history
	if not ns.db.history or type(saved) ~= "table" or type(saved.windows) ~= "table" then
		return
	end
	local age = time() - (tonumber(saved.at) or 0)
	if not isReload and (age < 0 or age > RELOG_SECONDS) then
		return
	end
	for id, lines in pairs(saved.windows) do
		local frame = _G["ChatFrame" .. tostring(id)]
		if frame and type(lines) == "table" and IsKept(frame) then
			-- Each line goes in above everything already there, so the
			-- newest saved line first.
			for index = #lines, 1, -1 do
				local line = lines[index]
				if type(line) == "table" and type(line.text) == "string" then
					pcall(frame.BackFillMessage, frame, line.text, line.r, line.g, line.b)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Input history

local INPUT_LINES = 32
local replaying = false

local function Remember(editBox, text)
	if replaying or IsSecret(text) or not CanAccess(text) or type(text) ~= "string" or text == "" then
		return
	end
	local name = editBox:GetName()
	if not name then
		return
	end
	local all = ns.charDB.inputHistory
	if type(all) ~= "table" then
		all = {}
		ns.charDB.inputHistory = all
	end
	local lines = all[name]
	if type(lines) ~= "table" then
		lines = {}
		all[name] = lines
	end
	if lines[#lines] ~= text then
		lines[#lines + 1] = text
	end
	local limit = editBox.GetHistoryLines and editBox:GetHistoryLines() or INPUT_LINES
	if type(limit) ~= "number" or limit < 1 then
		limit = INPUT_LINES
	end
	while #lines > limit do
		table.remove(lines, 1)
	end
end

local inputHooked = {}
local recall = {} -- edit box -> { index = number or nil, draft = string }

local function ResetRecall(editBox)
	recall[editBox] = nil
end

local function OnArrow(editBox, key)
	if not ns.db.arrows or (key ~= "UP" and key ~= "DOWN") then
		return
	end
	local completion = _G.AutoCompleteBox
	if completion and completion:IsShown() and completion.parent == editBox then
		return
	end
	local name = editBox:GetName()
	local lines = name and type(ns.charDB.inputHistory) == "table" and ns.charDB.inputHistory[name]
	if type(lines) ~= "table" or #lines == 0 then
		return
	end
	local state = recall[editBox]
	if not state then
		local draft = editBox:GetText()
		state = { index = #lines + 1, draft = (type(draft) == "string" and not IsSecret(draft)) and draft or "" }
		recall[editBox] = state
	end
	local index = state.index + (key == "UP" and -1 or 1)
	if index < 1 then
		return
	end
	local text
	if index > #lines then
		index = #lines + 1
		text = state.draft
	else
		text = lines[index]
	end
	state.index = index
	editBox:SetText(text)
	editBox:SetCursorPosition(#text)
end

local function TrackInput(frame)
	local editBox = frame.editBox
	if not editBox or inputHooked[editBox] or not IsKept(frame) or type(editBox.AddHistoryLine) ~= "function" then
		return
	end
	inputHooked[editBox] = true
	-- What was sent before this load goes in first, oldest first, so Up
	-- finds the most recent line.
	local name = editBox:GetName()
	local lines = name and type(ns.charDB.inputHistory) == "table" and ns.charDB.inputHistory[name]
	if type(lines) == "table" then
		replaying = true
		for _, text in ipairs(lines) do
			if type(text) == "string" and text ~= "" then
				pcall(editBox.AddHistoryLine, editBox, text)
			end
		end
		replaying = false
	end
	hooksecurefunc(editBox, "AddHistoryLine", Remember)
	hooksecurefunc(editBox, "AddHistoryLine", ResetRecall)
	if type(editBox.HookScript) == "function" then
		editBox:HookScript("OnArrowPressed", OnArrow)
		editBox:HookScript("OnHide", ResetRecall)
		editBox:HookScript("OnTextChanged", function(self, userInput)
			if userInput then
				ResetRecall(self)
			end
		end)
	end
end

function History.Init()
	if ns.db.history then
		ns.ForEachChatFrame(TrackInput)
	end
	local restored = false
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_LOGOUT")
	events:SetScript("OnEvent", function(_, event, _, isReload)
		if event == "PLAYER_LOGOUT" then
			pcall(Save)
		elseif not restored then
			-- The first time only: this event repeats on every loading
			-- screen.
			restored = true
			Restore(isReload)
		end
	end)
end

-- For the tests.
History.Save = Save
History.Restore = Restore
