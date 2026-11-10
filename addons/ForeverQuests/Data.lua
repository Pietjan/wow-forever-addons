-- Where the objectives of a quest can be done, from QuestieDB: the spawns of
-- the creatures to kill, the objects to use and whatever drops the items to
-- collect, plus the spots of exploration objectives.
--
-- QuestieDB keys spawns by AreaTable ID with 0-100 coordinates on that
-- zone's map. Here they become uiMapID with 0-1 coordinates, the way the
-- game's map API counts.

local _, ns = ...

ns.quests = {} -- questID -> { questID, byMap = { [uiMapID] = { {x, y, target}, ... } }, count }

local areaToUiMap

local function LoadZoneTable(source)
	if type(source) == "string" then
		local chunk = loadstring(source)
		local ok, result = pcall(chunk or error)
		source = ok and result
	end
	return type(source) == "table" and source or nil
end

local function UiMapOfArea(areaID)
	if not areaToUiMap then
		areaToUiMap = {}
		local ok, zones = pcall(LibQuestieDB.Support.Get, "ZoneDB")
		local private = ok and zones and zones.private or {}
		-- The override is Questie's own display policy and wins; 0 means "do not show".
		for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
			for area, uiMap in pairs(LoadZoneTable(private[key]) or {}) do
				areaToUiMap[area] = uiMap
			end
		end
	end
	local uiMap = areaToUiMap[areaID]
	if uiMap and uiMap ~= 0 then
		return uiMap
	end
end

-- spawnList: { [areaID] = { {x, y, phase?}, ... } }
local function AddSpawns(quest, spawnList, target)
	if type(spawnList) ~= "table" then
		return
	end
	for areaID, points in pairs(spawnList) do
		local uiMap = UiMapOfArea(areaID)
		if uiMap and type(points) == "table" then
			local list = quest.byMap[uiMap]
			if not list then
				list = {}
				quest.byMap[uiMap] = list
			end
			for _, point in ipairs(points) do
				local x, y = point[1], point[2]
				-- -1, -1 marks "somewhere inside an instance".
				if x and y and x >= 0 and y >= 0 then
					list[#list + 1] = { x / 100, y / 100, target }
					quest.count = quest.count + 1
				end
			end
		end
	end
end

-- label: what the game's objective text will contain, to read progress by.
-- source: what to go and find there, for the tooltip.
local function Target(quest, label, source)
	local target = { quest = quest, label = label, source = source or label, open = true }
	quest.targets[#quest.targets + 1] = target
	return target
end

local function Build(questID)
	local quest = { questID = questID, byMap = {}, count = 0, targets = {} }
	if not QuestDB.Exists(questID) then
		return quest
	end
	local objectives = QuestDB.objectives(questID) or {}

	for _, objective in ipairs(objectives[1] or {}) do -- creatures to kill
		local name = NpcDB.name(objective[1])
		AddSpawns(quest, NpcDB.spawns(objective[1]), Target(quest, objective[2] or name, name))
	end
	for _, objective in ipairs(objectives[2] or {}) do -- objects to use
		local name = ObjectDB.name(objective[1])
		AddSpawns(quest, ObjectDB.spawns(objective[1]), Target(quest, objective[2] or name, name))
	end
	for _, objective in ipairs(objectives[3] or {}) do -- items to collect
		local item = objective[2] or ItemDB.name(objective[1])
		for _, npc in ipairs(ItemDB.npcDrops(objective[1]) or {}) do
			AddSpawns(quest, NpcDB.spawns(npc), Target(quest, item, NpcDB.name(npc)))
		end
		for _, object in ipairs(ItemDB.objectDrops(objective[1]) or {}) do
			AddSpawns(quest, ObjectDB.spawns(object), Target(quest, item, ObjectDB.name(object)))
		end
	end
	for _, objective in ipairs(objectives[5] or {}) do -- any of several creatures count
		local label = objective[3] or NpcDB.name(objective[2])
		for _, npc in ipairs(objective[1] or {}) do
			AddSpawns(quest, NpcDB.spawns(npc), Target(quest, label, NpcDB.name(npc)))
		end
	end

	local trigger = QuestDB.triggerEnd(questID) -- explore: { text, spawnList }
	if trigger then
		AddSpawns(quest, trigger[2], Target(quest, trigger[1]))
	end
	for _, extra in ipairs(QuestDB.extraObjectives(questID) or {}) do
		local label = extra[3]
		AddSpawns(quest, extra[1], Target(quest, label))
		for _, ref in ipairs(extra[5] or {}) do
			if ref[1] == "monster" then
				AddSpawns(quest, NpcDB.spawns(ref[2]), Target(quest, label, NpcDB.name(ref[2])))
			elseif ref[1] == "object" then
				AddSpawns(quest, ObjectDB.spawns(ref[2]), Target(quest, label, ObjectDB.name(ref[2])))
			end
		end
	end
	return quest
end

function ns.Quest(questID)
	local quest = ns.quests[questID]
	if not quest then
		local ok, result = pcall(Build, questID)
		if not ok then
			ns.Print("could not read quest " .. questID .. " from QuestieDB: " .. tostring(result))
			result = { questID = questID, byMap = {}, count = 0, targets = {} }
		end
		quest = result
		ns.quests[questID] = quest
	end
	return quest
end

-- Whether we have dots to show for this quest at all; without, the game's
-- own quest area stays.
function ns.HasMarkers(questID)
	return ns.ready and ns.Quest(questID).count > 0
end

-- Read progress from the game. A target whose objective the game reports
-- finished gets no dots; a target we cannot match to an objective keeps them.
function ns.UpdateProgress(quest)
	local objectives = C_QuestLog.GetQuestObjectives(quest.questID) or {}
	for _, target in ipairs(quest.targets) do
		target.open, target.progress = true, nil
		for _, objective in ipairs(objectives) do
			if target.label and objective.text and objective.text:find(target.label, 1, true) then
				target.open = not objective.finished
				target.progress = objective.text
				break
			end
		end
	end
end

-- Map positions: an affine transform from one uiMap's 0-1 space to
-- another's, measured once through world coordinates.
local transforms = {}

local function Project(fromMap, x, y, toMap)
	local continent, world = C_Map.GetWorldPosFromMapPos(fromMap, CreateVector2D(x, y))
	if not continent or not world then
		return
	end
	local _, position = C_Map.GetMapPosFromWorldPos(continent, world, toMap)
	if position then
		return position:GetXY()
	end
end

function ns.Transform(fromMap, toMap)
	if fromMap == toMap then
		return 1, 0, 1, 0
	end
	local key = fromMap .. ">" .. toMap
	local t = transforms[key]
	if t == nil then
		t = false
		local ok, x0, y0 = pcall(Project, fromMap, 0, 0, toMap)
		local ok1, x1, y1 = pcall(Project, fromMap, 1, 1, toMap)
		if ok and ok1 and x0 and x1 and x1 ~= x0 and y1 ~= y0 then
			t = { x1 - x0, x0, y1 - y0, y0 }
		end
		transforms[key] = t
	end
	if t then
		return t[1], t[2], t[3], t[4]
	end
end

-- Dots of the active (tracked) quests that fall on a map, cached until the
-- next rebuild.
local pointsOn = {}

function ns.PointsOn(mapID)
	if not mapID then
		return {}
	end
	local list = pointsOn[mapID]
	if list then
		return list
	end
	list = {}
	for _, quest in ipairs(ns.active or {}) do
		for fromMap, spots in pairs(quest.byMap) do
			local ax, bx, ay, by = ns.Transform(fromMap, mapID)
			if ax then
				for _, spot in ipairs(spots) do
					local target = spot[3]
					if target.open then
						local x, y = spot[1] * ax + bx, spot[2] * ay + by
						if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
							list[#list + 1] = { x = x, y = y, target = target, spot = spot }
						end
					end
				end
			end
		end
	end
	pointsOn[mapID] = list
	return list
end

-- Merge points of one quest that lie closer together than cellX (across)
-- and cellY (down) map units, so no two dots of a quest overlap at the
-- current zoom. Each pass joins every group with the nearest earlier group
-- within reach; groups move to their members' average, which can bring
-- them within reach of another, so passes repeat until nothing changes.
-- A merged point keeps its first member's spot (the dot's identity) and
-- lists every target in it.
local MAX_PASSES = 6

local function MergePass(groups, cellX, cellY)
	local grid, merged, changed = {}, {}, false
	for _, group in ipairs(groups) do
		local ux, uy = group.x / cellX, group.y / cellY -- in cells; reach is 1
		local gx, gy = math.floor(ux), math.floor(uy)
		local quest = group.target.quest.questID
		local best, bestDistance = nil, 1
		for dx = -1, 1 do
			for dy = -1, 1 do
				local bucket = grid[quest .. ":" .. (gx + dx) .. ":" .. (gy + dy)]
				for _, other in ipairs(bucket or {}) do
					local distance = (other.x / cellX - ux) ^ 2 + (other.y / cellY - uy) ^ 2
					if distance < bestDistance then
						best, bestDistance = other, distance
					end
				end
			end
		end
		if best then
			changed = true
			local n = best.n + group.n
			best.x = (best.x * best.n + group.x * group.n) / n
			best.y = (best.y * best.n + group.y * group.n) / n
			best.n = n
			for _, target in ipairs(group.targets) do
				if not tContains(best.targets, target) then
					best.targets[#best.targets + 1] = target
				end
			end
		else
			local key = quest .. ":" .. gx .. ":" .. gy
			grid[key] = grid[key] or {}
			table.insert(grid[key], group)
			merged[#merged + 1] = group
		end
	end
	return merged, changed
end

function ns.Cluster(points, cellX, cellY)
	local groups = {}
	for i, point in ipairs(points) do
		groups[i] = { x = point.x, y = point.y, n = 1, target = point.target, spot = point.spot, targets = { point.target } }
	end
	for _ = 1, MAX_PASSES do
		local changed
		groups, changed = MergePass(groups, cellX, cellY)
		if not changed then
			break
		end
	end
	return groups
end

function ns.ForgetPoints()
	wipe(pointsOn)
end
