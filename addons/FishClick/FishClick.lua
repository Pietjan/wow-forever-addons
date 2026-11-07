-- FishClick: with a fishing pole in hand, a double-click into the world
-- casts Fishing.
--
-- Casting has to come from a hardware click on a secure button, so the
-- addon cannot simply call the spell. Instead, when the second click of a
-- double-click goes down, it binds that mouse button to its own secure
-- button for the rest of the press: the release then lands on the button,
-- which casts. The binding is removed again as soon as the button comes up.

local ADDON_NAME = ...

local DEFAULTS = {
	enabled = true,
	delay = 0.4, -- seconds between the two clicks, at most
	button = "left", -- "left", "right" or "both"
}

local FISHING = 7620 -- Fishing, rank 1: used for the spell's name only
local MAIN_HAND = INVSLOT_MAINHAND or 16
local WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local FISHING_POLE = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local CAST_BUTTON = "FishClickCast"
local KEYS = { LeftButton = "BUTTON1", RightButton = "BUTTON2" }

local IsSecret = issecretvalue or function() return false end

local db
local poleEquipped = false
local armed = false -- the binding is in place for the current press
local spellPending = false -- the spell changed in combat; apply when it ends
local lastDown, lastButton = 0, nil

local function Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff9999ffFishClick|r " .. msg)
end

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID)
	elseif GetSpellInfo then
		return (GetSpellInfo(spellID))
	end
end

------------------------------------------------------------------------------
-- The secure button that does the casting
------------------------------------------------------------------------------

local owner = CreateFrame("Frame") -- holds the override binding
local cast = CreateFrame("Button", CAST_BUTTON, UIParent, "SecureActionButtonTemplate")
cast:RegisterForClicks("AnyUp")
cast:SetAttribute("type", "spell")
-- The binding is created while the mouse button is already down, so the
-- cast has to happen on the release, whatever the action-button setting.
cast:SetAttribute("useOnKeyDown", false)

local function Disarm()
	if not armed then
		return
	end
	armed = false
	if not InCombatLockdown() then
		ClearOverrideBindings(owner)
	end
	-- The press started the camera turning; its release went to us.
	if IsMouselooking and IsMouselooking() and MouselookStop then
		MouselookStop()
	end
end

cast:SetScript("PostClick", Disarm)

------------------------------------------------------------------------------
-- Which Fishing spell to cast
------------------------------------------------------------------------------

-- The game has several spells called Fishing (old channelled ranks, newer
-- short casts). The one to cast is the non-passive one in the spellbook.
local function FindFishingSpell()
	local name = SpellName(FISHING)
	if not name or IsSecret(name) then
		return nil
	end
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		local spellType = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
		local function Check(slot)
			local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
			if item and item.itemType == spellType and not item.isPassive and item.spellID
				and not IsSecret(item.name) and item.name == name then
				return item.spellID
			end
		end
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info then
				for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local id = Check(slot)
					if id then
						return id
					end
				end
			end
		end
		-- Professions can live outside the skill lines of the spellbook.
		if GetProfessions and GetProfessionInfo then
			local fishing = select(4, GetProfessions())
			if fishing then
				local _, _, _, _, numAbilities, offset = GetProfessionInfo(fishing)
				if numAbilities and offset and not IsSecret(numAbilities) and not IsSecret(offset) then
					for slot = offset + 1, offset + numAbilities do
						local id = Check(slot)
						if id then
							return id
						end
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellBookItemInfo then
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, count = GetSpellTabInfo(tab)
			for slot = offset + 1, offset + count do
				local kind, id = GetSpellBookItemInfo(slot, "spell")
				if kind == "SPELL" and GetSpellBookItemName(slot, "spell") == name
					and not IsPassiveSpell(slot, "spell") then
					return id
				end
			end
		end
	end
	return nil
end

local function UpdateSpell()
	if InCombatLockdown() then
		spellPending = true
		return
	end
	spellPending = false
	local spellID = FindFishingSpell()
	-- Without a match, cast by name and let the game pick.
	cast:SetAttribute("spell", spellID or SpellName(FISHING) or "Fishing")
end

------------------------------------------------------------------------------
-- The pole and the clicks
------------------------------------------------------------------------------

local function UpdatePole()
	poleEquipped = false
	local itemID = GetInventoryItemID("player", MAIN_HAND)
	if not itemID or IsSecret(itemID) then
		return
	end
	local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not getInfo then
		return
	end
	local _, _, _, _, _, classID, subclassID = getInfo(itemID)
	poleEquipped = classID == WEAPON and subclassID == FISHING_POLE
end

local function WantedButton(button)
	if not KEYS[button] then
		return false
	end
	return db.button == "both"
		or (db.button == "left" and button == "LeftButton")
		or (db.button == "right" and button == "RightButton")
end

-- True when the click went into the world rather than onto a frame, and
-- nothing is being dragged on the cursor.
local function ClickedWorld()
	if GetCursorInfo and GetCursorInfo() then
		return false
	end
	if GetMouseFoci then
		for _, frame in ipairs(GetMouseFoci()) do
			if frame ~= WorldFrame then
				return false
			end
		end
		return true
	elseif GetMouseFocus then
		local frame = GetMouseFocus()
		return frame == nil or frame == WorldFrame
	end
	return true
end

local function OnMouseDown(button)
	if not (db.enabled and poleEquipped and WantedButton(button)) or InCombatLockdown() or not ClickedWorld() then
		lastDown = 0
		return
	end
	local now = GetTime()
	if lastButton == button and now - lastDown <= db.delay then
		lastDown = 0
		armed = true
		SetOverrideBindingClick(owner, true, KEYS[button], CAST_BUTTON, "LeftButton")
	else
		lastDown, lastButton = now, button
	end
end

local function OnMouseUp()
	if armed then
		-- Let the release reach the binding first, then take it down.
		C_Timer.After(0, Disarm)
	end
end

------------------------------------------------------------------------------
-- Slash command and events
------------------------------------------------------------------------------

local function Status()
	local spell = cast:GetAttribute("spell")
	Print("%s, %s double-click within %.2f s%s, casting %s", db.enabled and "on" or "off", db.button, db.delay,
		poleEquipped and "" or " (no fishing pole equipped)",
		type(spell) == "number" and ("spell " .. spell) or tostring(spell))
end

SLASH_FISHCLICK1 = "/fish"
SLASH_FISHCLICK2 = "/fishclick"
SlashCmdList.FISHCLICK = function(msg)
	local word = msg:lower():match("^%s*(%S*)")
	local seconds = tonumber(word)
	if word == "" then
		db.enabled = not db.enabled
	elseif word == "on" or word == "off" then
		db.enabled = word == "on"
	elseif word == "left" or word == "right" or word == "both" then
		db.button = word
	elseif seconds then
		db.delay = math.max(0.15, math.min(1, seconds))
	elseif word ~= "status" then
		Print("/fish toggles; /fish on|off; /fish left|right|both picks the mouse button; /fish <seconds> sets the double-click time")
		return
	end
	Status()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
loader:RegisterEvent("SPELLS_CHANGED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("GLOBAL_MOUSE_DOWN")
loader:RegisterEvent("GLOBAL_MOUSE_UP")
loader:SetScript("OnEvent", function(self, event, arg)
	if event == "GLOBAL_MOUSE_DOWN" then
		if db then
			OnMouseDown(arg)
		end
	elseif event == "GLOBAL_MOUSE_UP" then
		OnMouseUp()
	elseif event == "ADDON_LOADED" then
		if arg ~= ADDON_NAME then
			return
		end
		FishClickDB = FishClickDB or {}
		db = FishClickDB
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				db[key] = value
			end
		end
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		UpdatePole()
		UpdateSpell()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if arg == MAIN_HAND then
			UpdatePole()
		end
	elseif event == "SPELLS_CHANGED" then
		UpdateSpell()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if spellPending then
			UpdateSpell()
		end
	end
end)
