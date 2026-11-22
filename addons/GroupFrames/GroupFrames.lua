-- GroupFrames: party frames (Party.lua) and raid frames (Raid.lua) of our
-- own. First names are also written on Blizzard's raid frames, should they
-- ever show.
--
-- /groupframes          unlock (a green box to drag) or lock again
-- /groupframes reset    back to the starting place
-- /groupframes test [n] n look-only frames with made-up members (1 to 5,
--                       default 5), unlocked to drag; /groupframes ends it
-- /groupframes test raid 10|25|40
--                       the same for a raid of that size
-- /groupframes raidpets raid pets on or off for the raid layout shown now
--                       (10, 25 or 40; off at first)
--
-- The same and more on the options page (Options.lua: Options > AddOns).
--
-- First names: Forever characters are "First Surname"; Blizzard's
-- CompactUnitFrame_UpdateName writes both. UnitName returns the two apart,
-- so the first, cut to 5 letters, is written back over them, in a hook
-- that runs after Blizzard's own function.

local ADDON_NAME, ns = ...

local IsSecret = issecretvalue or function() return false end

-- Blizzard's raid unit frames by their global names. Nameplates also go
-- through the compact unit frame functions; they are left alone.
local function IsRaidFrame(frame)
	if not frame or frame:IsForbidden() then
		return false
	end
	local name = frame:GetName()
	if not name then
		return false
	end
	return name:match("^CompactRaidFrame%d+$") or name:match("^CompactRaidGroup%d+Member%d+$") or false
end

-- At most this many characters (not bytes: names can hold accented
-- letters, two bytes each in UTF-8).
local NAME_CHARS = 5
local UTF8_CHAR = "[%z\1-\127\192-\247][\128-\191]*"

function ns.Cut(name)
	local out, count = {}, 0
	for char in name:gmatch(UTF8_CHAR) do
		count = count + 1
		if count > NAME_CHARS then
			break
		end
		out[count] = char
	end
	return table.concat(out)
end

local function OnUpdateName(frame)
	if not IsRaidFrame(frame) or not frame.name or not frame.unit then
		return
	end
	local first = UnitName(frame.unit)
	-- A secret name can only be handed on, not tested or cut.
	if IsSecret(first) then
		frame.name:SetText(first)
	elseif first then
		frame.name:SetText(ns.Cut(first))
	end
end

-- GroupFrames 2.0 switched these raid frame options for its restyle of
-- Blizzard's frames; that restyle is gone, so put the game's defaults back,
-- once, where they still hold what 2.0 set.
local RESTORE = {
	{ "raidFramesDisplayBuffs", "0", "1" },
	{ "raidFramesDisplayDebuffs", "0", "1" },
	{ "raidFramesDispelIndicatorType", "0", "2" },
}

local function RestoreCVars(db)
	if db.restoredCVars then
		return
	end
	for _, cvar in ipairs(RESTORE) do
		if GetCVar(cvar[1]) == cvar[2] then
			SetCVar(cvar[1], cvar[3])
		end
	end
	db.restoredCVars = true
end

local function Say(text)
	print("|cffffd100GroupFrames|r: " .. text)
end

SLASH_GROUPFRAMES1 = "/groupframes"
SlashCmdList.GROUPFRAMES = function(message)
	local command, rest = (message or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if InCombatLockdown() then
		Say("not in combat.")
		return
	end
	if command == "reset" then
		ns.PartyReset()
		ns.RaidReset()
		Say("party and raid frames back at their starting places.")
		return
	end
	if command == "raidpets" then
		-- For the layout shown now (10, 25 or 40).
		local size = ns.RaidCurrentSize()
		local on = not ns.RaidPetsShown(size)
		ns.RaidPets(on, size)
		Say(("raid pets in the %d layout %s."):format(size, on and "shown" or "hidden"))
		return
	end
	if command == "test" and rest == "raid" then
		local count = tonumber((message or ""):match("raid%s+(%d+)") or "25")
		if count ~= 10 and count ~= 25 and count ~= 40 then
			Say("/groupframes test raid 10, 25 or 40.")
			return
		end
		if ns.PartyTesting() then
			ns.PartyTest(nil)
		end
		ns.RaidTest(count)
		ns.PartyUnlock(true, true)
		ns.RaidUnlock(true)
		Say(("test: a raid of %d. Drag the blue box; /groupframes to end."):format(count))
		return
	end
	if command == "test" and rest ~= "off" then
		local count = tonumber(rest ~= "" and rest or "5")
		if not count or count < 1 or count > 5 or count % 1 ~= 0 then
			Say("/groupframes test 1 to 5.")
			return
		end
		if ns.RaidTesting() then
			ns.RaidTest(nil)
			ns.RaidUnlock(false)
		end
		ns.PartyTest(count)
		ns.PartyUnlock(true, true)
		Say(("test: %d made-up members. Drag the green box; /groupframes to end."):format(count))
		return
	end
	if ns.PartyTesting() or ns.RaidTesting() then
		ns.PartyTest(nil)
		ns.RaidTest(nil)
		ns.PartyUnlock(false)
		ns.RaidUnlock(false)
		Say("test over, locked.")
		return
	end
	local unlock = not ns.PartyUnlocked()
	ns.PartyUnlock(unlock)
	ns.RaidUnlock(unlock)
	Say(unlock and "unlocked: drag the green box (party) or the blue one (raid). /groupframes to lock." or "locked.")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
-- A test running into combat ends, so the real frames are back for the
-- fight; this event comes before the combat lockdown.
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == ADDON_NAME then
			GroupFramesDB = GroupFramesDB or {}
			if type(CompactUnitFrame_UpdateName) == "function" then
				hooksecurefunc("CompactUnitFrame_UpdateName", OnUpdateName)
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Settings changed in combat that touch the secure headers.
		if ns.PartySettingsPending() then
			ns.PartyApplySettings()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if ns.PartyTesting() or ns.RaidTesting() then
			ns.PartyTest(nil)
			ns.RaidTest(nil)
			ns.PartyUnlock(false)
			ns.RaidUnlock(false)
			Say("test ended: combat.")
		end
	elseif event == "PLAYER_LOGIN" then
		RestoreCVars(GroupFramesDB)
		ns.PartyLogin(GroupFramesDB)
		ns.RaidLogin(GroupFramesDB)
		local ok, err = pcall(ns.RegisterSettings, GroupFramesDB)
		if not ok then
			Say("options page unavailable (" .. tostring(err) .. "); /groupframes still works")
		end
	end
end)
