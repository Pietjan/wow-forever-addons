-- BulkInbox: a list of every item and every sum of money in the mailbox,
-- next to the inbox, to take in bulk: everything, the money only, or the
-- rows you marked. This file reads the inbox and does the taking;
-- BulkInbox.lua draws the window.
--
-- What taking in bulk has to get right, and how it is done here:
--
-- - One command at a time. The next one goes out only when the game says
--   no mail command is pending and the row that was asked for is gone from
--   the inbox, plus the short pause Blizzard's own Open All keeps.
-- - Mail indices are never kept. A mail that empties can disappear, and
--   every mail after it moves up. So the inbox is read again before each
--   command, and the row to take is looked up in what was just read.
-- - A mail has no ID. A row is known by its mail's sender, subject, C.O.D.
--   amount and returned flag, by which of the mails that look alike it is
--   (counted from the oldest), and by its attachment slot. When one of
--   those look-alikes disappears because of a take made here, the marks on
--   the others are renumbered. The game removes an emptied mail in an
--   inbox update of its own, a moment after the one that confirms the take
--   (0.15 s later in the trace of 2026-11-13), so an emptied mail is
--   expected to go, and while marks depend on it the next command waits
--   for that. When the number of look-alikes changes for any other reason,
--   or in a way that leaves it unclear which one went, the marks on them
--   are dropped: taking nothing beats taking the wrong thing.
-- - C.O.D. mails and mails from a game master are listed but never taken.
-- - A take that fails is not tried again: the game names the item
--   (MAIL_FAILED), and every row of that item is left alone for the rest
--   of the run, as Open All does. A take that is neither confirmed nor
--   refused gets one more try and is then left alone, so a run always
--   ends.
-- - Full bags stop the items; money is still taken.
-- - Closing the mailbox, leaving the inbox tab or changing the search text
--   stops the run.
--
-- Every run leaves a trace in the saved variable BulkInboxDB.runs: each
-- command sent, each answer of the game (inbox update, MAIL_SUCCESS,
-- MAIL_FAILED, error text), timeouts, marks renumbered or dropped, and why
-- it stopped, with the seconds since the run began. The last few runs are
-- kept. The file is written on /reload or logout; it is there to read when
-- a run went wrong, nothing in the game shows it.

local _, ns = ...
local IsSecret = issecretvalue or function() return false end

local SLOTS = ATTACHMENTS_MAX_RECEIVE or 16
local PAUSE = 0.15 -- between commands, as Blizzard's Open All
local CONFIRM_TIMEOUT = 5 -- no answer either way: count a try
local PENDING_TIMEOUT = 15 -- the game keeps saying "pending": give up
local MAX_TRIES = 2
local SEP = "\031"
local LEAVE_WAIT = 0.5 -- at least this long for an emptied mail to go
local TRACE_TAIL = 5 -- the trace goes on this long after a run
local KEEP_RUNS = 20
local KEEP_LINES = 400 -- per run

ns.atMailbox = false
ns.marks = {} -- row key -> { fp, ord, slot }
ns.filter = ""
ns.status = ""
ns.snap = { rows = {}, mails = {}, sigs = {}, money = 0, numMails = 0, waiting = 0 }

local run -- the take in progress, nil when idle

local leaving = {} -- emptied mails expected to go: { fp, ord, at, wait }
local log, logStart, logUntil -- the trace of the latest run

local function Trace(text, ...)
	if not log or #log >= KEEP_LINES or (not run and GetTime() > logUntil) then
		return
	end
	log[#log + 1] = ("%.2f "):format(GetTime() - logStart) .. text:format(...)
end

local function Describe(row)
	local what = row.kind == "money" and ("money %d"):format(row.money)
		or ("slot %d item %d x%d"):format(row.slot, row.itemID, row.count)
	return ("mail %d %s from %q %q"):format(row.mail, what, row.sender, row.label)
end

local function Num(v)
	if v == nil or IsSecret(v) or type(v) ~= "number" then
		return 0
	end
	return v
end

local function Text(v)
	if v == nil or IsSecret(v) or type(v) ~= "string" then
		return ""
	end
	return v
end

local function Key(fp, ord, slot)
	return fp .. SEP .. "#" .. ord .. ":" .. slot
end

local function AddRow(snap, row)
	row.key = Key(row.fp, row.ord, row.slot)
	snap.sigs[row.sig] = (snap.sigs[row.sig] or 0) + 1
	snap.rows[#snap.rows + 1] = row
end

-- Reads the whole inbox. Rows come out last mail first, which is also the
-- order they are taken in.
local function ReadInbox()
	local snap = { rows = {}, mails = {}, sigs = {}, money = 0, numMails = 0, waiting = 0 }
	if not ns.atMailbox then
		return snap
	end
	local shown, total = GetInboxNumItems()
	shown = Num(shown)
	snap.numMails = shown
	snap.waiting = math.max(0, Num(total) - shown)
	for mail = shown, 1, -1 do
		local _, _, sender, subject, money, cod, daysLeft, itemCount, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(mail)
		sender, subject, money, cod = Text(sender), Text(subject), Num(money), Num(cod)
		local fp = table.concat({ sender, subject, cod, wasReturned and 1 or 0 }, SEP)
		local ord = (snap.mails[fp] or 0) + 1
		snap.mails[fp] = ord
		local blocked = (cod > 0 and "cod") or (isGM and "gm") or nil
		if money > 0 then
			AddRow(snap, {
				kind = "money", fp = fp, ord = ord, slot = 0, mail = mail,
				sig = fp .. SEP .. "0" .. SEP .. money,
				label = subject ~= "" and subject or (MONEY or "Money"), money = money,
				sender = sender, daysLeft = Num(daysLeft), cod = cod, blocked = blocked,
			})
			if not blocked then
				snap.money = snap.money + money
			end
		end
		if Num(itemCount) > 0 then
			for slot = 1, SLOTS do
				if HasInboxItem(mail, slot) then
					local name, itemID, texture, count, quality = GetInboxItem(mail, slot)
					itemID, count = Num(itemID), Num(count)
					AddRow(snap, {
						kind = "item", fp = fp, ord = ord, slot = slot, mail = mail,
						sig = fp .. SEP .. slot .. SEP .. itemID .. SEP .. count,
						label = Text(name), itemID = itemID, count = count,
						quality = Num(quality), texture = texture,
						sender = sender, daysLeft = Num(daysLeft), cod = cod, blocked = blocked,
					})
				end
			end
		end
	end
	return snap
end

function ns.Matches(row)
	return ns.filter == "" or row.label:lower():find(ns.filter, 1, true) ~= nil
end

local function Changed()
	if ns.Changed then
		ns.Changed()
	end
end

-- Marks live in ns.marks; a shift-click take has a set of its own.
local function EachKeySet(fn)
	fn(ns.marks)
	if run and run.keys then
		fn(run.keys)
	end
end

local function DropMails(set, fp)
	for key, mark in pairs(set) do
		if mark.fp == fp then
			set[key] = nil
		end
	end
end

-- The look-alike mail number `gone` has disappeared: the ones counted
-- after it are each one lower now.
local function Renumber(set, fp, gone)
	local moved = {}
	for key, mark in pairs(set) do
		if mark.fp == fp and mark.ord >= gone then
			set[key] = nil
			if mark.ord > gone then
				moved[#moved + 1] = { fp = fp, ord = mark.ord - 1, slot = mark.slot }
			end
		end
	end
	for _, mark in ipairs(moved) do
		set[Key(mark.fp, mark.ord, mark.slot)] = mark
	end
end

-- Which of the look-alike mails `fp` are expected to go, highest first.
local function Expected(fp)
	local ords = {}
	for _, entry in ipairs(leaving) do
		if entry.fp == fp then
			ords[#ords + 1] = entry.ord
		end
	end
	table.sort(ords, function(a, b) return a > b end)
	return ords
end

-- It is no longer known which look-alike is which.
local function Forget(fp)
	EachKeySet(function(set) DropMails(set, fp) end)
	for i = #leaving, 1, -1 do
		if leaving[i].fp == fp then
			table.remove(leaving, i)
		end
	end
end

-- Look-alike number `ord` has left the inbox.
local function Gone(fp, ord)
	EachKeySet(function(set) Renumber(set, fp, ord) end)
	for i = #leaving, 1, -1 do
		local entry = leaving[i]
		if entry.fp == fp then
			if entry.ord == ord then
				table.remove(leaving, i)
			elseif entry.ord > ord then
				entry.ord = entry.ord - 1
			end
		end
	end
	local pending = run and run.pending
	if pending and pending.fp == fp and pending.ord > ord then
		pending.ord = pending.ord - 1
		pending.key = Key(fp, pending.ord, pending.slot)
	end
end

local function HasRows(snap, fp, ord)
	for _, row in ipairs(snap.rows) do
		if row.fp == fp and row.ord == ord then
			return true
		end
	end
	return false
end

local function HasMarks(fp)
	local found = false
	EachKeySet(function(set)
		for _, mark in pairs(set) do
			if mark.fp == fp then
				found = true
			end
		end
	end)
	return found
end

-- Reads the inbox again and brings the marks and the pending take in line
-- with it.
local function Refresh()
	local old, snap = ns.snap, ReadInbox()
	ns.snap = snap
	local time = GetTime()
	for i = #leaving, 1, -1 do
		if time - leaving[i].at > leaving[i].wait then
			Trace("an emptied mail of %q stayed", (leaving[i].fp:gsub(SEP, " / ")))
			table.remove(leaving, i)
		end
	end
	local pending = run and run.pending
	local settled -- the mail kind whose change the pending take explains
	if pending and (snap.sigs[pending.sig] or 0) < pending.sigsBefore then
		local fp = pending.fp
		local now = snap.mails[fp] or 0
		local fewer, expected = pending.mailsBefore - now, Expected(fp)
		local note = ""
		EachKeySet(function(set) set[pending.key] = nil end)
		if fewer == 0 then
			if not HasRows(snap, fp, pending.ord) then
				-- Three round trips of grace, for a slow connection.
				leaving[#leaving + 1] = { fp = fp, ord = pending.ord, at = time,
					wait = math.max(LEAVE_WAIT, 3 * (time - pending.sentAt)) }
				note = ", it is empty now and expected to go"
			end
		elseif fewer == 1 and #expected == 0 then
			Gone(fp, pending.ord)
			note = ", marks renumbered"
		elseif fewer == #expected + 1 then
			-- this mail and every emptied one before it
			local own, done = pending.ord, false
			for _, ord in ipairs(expected) do
				if not done and own > ord then
					Gone(fp, own)
					done = true
				end
				Gone(fp, ord)
			end
			if not done then
				Gone(fp, own)
			end
			note = ", marks renumbered"
		else
			Forget(fp)
			note = ", unclear which went: marks on them dropped"
		end
		Trace("confirmed: %s; mails like it %d -> %d%s", pending.what, pending.mailsBefore, now, note)
		settled = fp
		run.pending = nil
		run.taken = run.taken + 1
		run.nextAt = time + PAUSE
	end
	local seen = {}
	for _, counts in ipairs({ old.mails, snap.mails }) do
		for fp in pairs(counts) do
			if not seen[fp] then
				seen[fp] = true
				local before, now = old.mails[fp] or 0, snap.mails[fp] or 0
				if fp ~= settled and before ~= now then
					local expected = Expected(fp)
					if #expected > 0 and before - now == #expected then
						for _, ord in ipairs(expected) do
							Gone(fp, ord)
						end
						Trace("mails like %q %d -> %d: the emptied mail went, marks renumbered",
							(fp:gsub(SEP, " / ")), before, now)
					else
						Trace("mails like %q %d -> %d, not by this run: marks on them dropped",
							(fp:gsub(SEP, " / ")), before, now)
						Forget(fp)
					end
					if pending and pending.fp == fp then
						pending.mailsBefore = now
					end
				end
			end
		end
	end
	-- A mark on a row that is no longer there means nothing.
	local present = {}
	for _, row in ipairs(snap.rows) do
		present[row.key] = true
	end
	EachKeySet(function(set)
		for key in pairs(set) do
			if not present[key] then
				set[key] = nil
			end
		end
	end)
	return snap
end

local function Wanted(row)
	if run.mode == "all" then
		return ns.Matches(row)
	elseif run.mode == "money" then
		return row.kind == "money" and ns.Matches(row)
	elseif run.mode == "marked" then
		return ns.marks[row.key] ~= nil
	end
	return run.keys[row.key] ~= nil
end

-- Why a wanted row is not taken, nil when it can be.
local function Refused(row)
	if row.blocked then
		return row.blocked
	elseif row.kind == "item" and run.bagsFull then
		return "full"
	elseif run.failedSig[row.sig] or (row.kind == "item" and run.failedItem[row.itemID]) then
		return "failed"
	elseif (run.tries[row.sig] or 0) >= MAX_TRIES then
		return "failed"
	end
	return nil
end

function ns.Running()
	return run ~= nil
end

local driver = CreateFrame("Frame")

function ns.Stop(why)
	if not run then
		return
	end
	local left = { full = 0, failed = 0, cod = 0, gm = 0 }
	for _, row in ipairs(ns.snap.rows) do
		if Wanted(row) then
			local reason = Refused(row)
			if reason then
				left[reason] = left[reason] + 1
			end
		end
	end
	local parts = { ("Took %d."):format(run.taken) }
	if why then
		parts[#parts + 1] = why
	end
	if left.full > 0 then
		parts[#parts + 1] = ("Bags full, %d left."):format(left.full)
	end
	if left.failed > 0 then
		parts[#parts + 1] = ("%d could not be taken."):format(left.failed)
	end
	if left.cod + left.gm > 0 and run.mode == "marked" then
		parts[#parts + 1] = ("%d skipped (C.O.D. or game master)."):format(left.cod + left.gm)
	end
	ns.status = table.concat(parts, " ")
	Trace("stop: %s", ns.status)
	logUntil = GetTime() + TRACE_TAIL
	run = nil
	driver:SetScript("OnUpdate", nil)
	Changed()
end

local function Advance()
	if not run then
		return
	end
	if not ns.atMailbox then
		return ns.Stop("Mailbox closed.")
	end
	local now = GetTime()
	if C_Mail.IsCommandPending() then
		if now - run.waitingSince > PENDING_TIMEOUT then
			Trace("a command is still pending after %d s", PENDING_TIMEOUT)
			ns.Stop("The mail server is not answering.")
		end
		return
	end
	local snap = Refresh()
	local pending = run.pending
	if pending then
		if pending.failed then
			Trace("refused: %s%s", pending.what, run.bagsFull and " (bags full)" or "")
			if not (run.bagsFull and pending.itemID) then
				run.failedSig[pending.sig] = true
				if pending.itemID then
					run.failedItem[pending.itemID] = true
				end
			end
		elseif now - pending.sentAt > CONFIRM_TIMEOUT then
			run.tries[pending.sig] = (run.tries[pending.sig] or 0) + 1
			Trace("no answer in %d s, try %d: %s", CONFIRM_TIMEOUT, run.tries[pending.sig], pending.what)
		else
			return
		end
		run.pending = nil
		run.nextAt = now + PAUSE
	end
	if now < run.nextAt then
		return
	end
	-- An emptied mail is about to go and marks hang on which look-alike
	-- is which: let it go first.
	for _, entry in ipairs(leaving) do
		if HasMarks(entry.fp) then
			return
		end
	end
	if not run.bagsFull and C_Container.CalculateTotalNumberOfFreeBagSlots() == 0 then
		run.bagsFull = true
		Trace("no free bag slot: items are left from here on")
	end
	for _, row in ipairs(snap.rows) do
		if Wanted(row) and not Refused(row) then
			run.pending = {
				key = row.key, sig = row.sig, fp = row.fp, ord = row.ord, slot = row.slot,
				itemID = row.kind == "item" and row.itemID or nil,
				sigsBefore = snap.sigs[row.sig], mailsBefore = snap.mails[row.fp],
				sentAt = now, what = Describe(row),
			}
			Trace("send: %s", run.pending.what)
			run.waitingSince = now
			if row.kind == "money" then
				TakeInboxMoney(row.mail)
			else
				TakeInboxItem(row.mail, row.slot)
			end
			Changed()
			return
		end
	end
	ns.Stop()
end

-- mode: "all", "money", "marked", or "one" with the key of the row to take.
function ns.Start(mode, key)
	if run or not ns.atMailbox then
		return
	end
	run = {
		mode = mode, taken = 0, nextAt = 0, waitingSince = GetTime(),
		failedSig = {}, failedItem = {}, tries = {},
		startedAt = GetTime(), log = {},
	}
	if mode == "one" then
		local mark
		for _, row in ipairs(ns.snap.rows) do
			if row.key == key then
				mark = { fp = row.fp, ord = row.ord, slot = row.slot }
			end
		end
		if not mark then
			run = nil
			return
		end
		run.keys = { [key] = mark }
	end
	ns.status = ""
	BulkInboxDB = type(BulkInboxDB) == "table" and BulkInboxDB or {}
	BulkInboxDB.runs = type(BulkInboxDB.runs) == "table" and BulkInboxDB.runs or {}
	local runs = BulkInboxDB.runs
	runs[#runs + 1] = { date = date("%Y-%m-%d %H:%M:%S"), mode = mode, filter = ns.filter, log = run.log }
	log, logStart = run.log, run.startedAt
	while #runs > KEEP_RUNS do
		table.remove(runs, 1)
	end
	Trace("start: %s, %d mails, %d rows, %d free bag slots", mode, ns.snap.numMails, #ns.snap.rows,
		C_Container.CalculateTotalNumberOfFreeBagSlots())
	driver:SetScript("OnUpdate", Advance)
	Advance()
	Changed()
end

function ns.SetFilter(text)
	text = (text or ""):lower()
	if text == ns.filter then
		return
	end
	-- What "all" means has just changed under a running take.
	ns.Stop("Stopped: the search changed.")
	ns.filter = text
	Changed()
end

function ns.ToggleMark(row, on)
	if row.blocked then
		return
	end
	if on == nil then
		on = ns.marks[row.key] == nil
	end
	ns.marks[row.key] = on and { fp = row.fp, ord = row.ord, slot = row.slot } or nil
end

-- Marks, or unmarks, every listed row of the same item (or all the money).
function ns.ToggleMarkAlike(row)
	local on = ns.marks[row.key] == nil
	for _, other in ipairs(ns.snap.rows) do
		if other.kind == row.kind and other.itemID == row.itemID and ns.Matches(other) then
			ns.ToggleMark(other, on)
		end
	end
end

function ns.ClearMarks()
	for key in pairs(ns.marks) do
		ns.marks[key] = nil
	end
end

driver:RegisterEvent("MAIL_SHOW")
driver:RegisterEvent("MAIL_CLOSED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("MAIL_INBOX_UPDATE")
driver:RegisterEvent("MAIL_FAILED")
driver:RegisterEvent("MAIL_SUCCESS")
driver:RegisterEvent("UI_ERROR_MESSAGE")
driver:SetScript("OnEvent", function(_, event, first, message)
	if event == "MAIL_SHOW" then
		ns.atMailbox = true
		ns.status = ""
		ns.ClearMarks()
		leaving = {}
		Refresh()
	elseif event == "MAIL_CLOSED" or event == "PLAYER_ENTERING_WORLD" then
		-- MAIL_CLOSED is not certain to come when a loading screen takes
		-- the mailbox away, so entering the world counts as closing it.
		ns.atMailbox = false
		Trace(event)
		ns.Stop("Mailbox closed.")
		ns.ClearMarks()
		Refresh()
	elseif event == "MAIL_INBOX_UPDATE" then
		Trace("MAIL_INBOX_UPDATE")
		Refresh()
	elseif event == "MAIL_SUCCESS" then
		Trace("MAIL_SUCCESS %s", tostring(Num(first)))
		return
	elseif event == "MAIL_FAILED" then
		Trace("MAIL_FAILED %s", tostring(Num(first)))
		if run and run.pending then
			run.pending.failed = true
		end
		return
	elseif event == "UI_ERROR_MESSAGE" then
		if run and not IsSecret(message) then
			Trace("UI_ERROR_MESSAGE %q", Text(message))
			if message == ERR_INV_FULL then
				run.bagsFull = true
			end
		end
		return
	end
	Changed()
end)
