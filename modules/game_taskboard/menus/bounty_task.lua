-- chunkname: @/game_taskboard/menus/bounty_task.lua

TaskBoard.BountyTask = {}

local BountyTask = TaskBoard.BountyTask

CLAIMED_DAILY_TASK_STATE = false
local STORE_BOUNTY_KILL_BOOST = "Bounty Double Kill Boost (1H)"
local MAX_REROLL_TOKENS = 10

local BACKDROP_BY_STARS = {
	[0] = "/modules/game_taskboard/images/backdrop_tasksystem_normal_task",
	"/modules/game_taskboard/images/backdrop_tasksystem_silver_task",
	"/modules/game_taskboard/images/backdrop_tasksystem_gold_task"
}

local function capitalizeWords(str)
	return (str or ""):gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
end

local function applyStarsBackdrop(starsWidget, stars)
	if not starsWidget then
		return
	end

	local starTier = tonumber(stars) or 0

	if starTier > 0 then
		starsWidget:setSize(tosize("279 44"))
	end

	starsWidget:setImageSource(BACKDROP_BY_STARS[starTier] or BACKDROP_BY_STARS[0])
end

local BOUNTY_TRACKER_TOOLTIP_FOOTER = "Click in this window to open the Task Board dialog."
local BOUNTY_TRACKER_TOOLTIP_INACTIVE = "Inactive Task.\n\nClick in this window to open Task Board dialog. Select a monster to start a new task."
local lastBountyTrackerData

local function buildBountyTrackerActiveTooltip(creatureName, killed, total)
	local header = string.format("Creature: %s\nAmount: %s / %s", capitalizeWords(creatureName), TaskBoard:formatNumberWithCommas(killed), TaskBoard:formatNumberWithCommas(total))

	return header .. "\n\n" .. tr(BOUNTY_TRACKER_TOOLTIP_FOOTER)
end

local function formatBountyTrackerCreatureName(creatureName)
	if modules.game_prey and modules.game_prey.formatKillTrackerCreatureName then
		return modules.game_prey.formatKillTrackerCreatureName(creatureName)
	end

	return capitalizeWords(creatureName or "")
end

local function formatBountyTrackerProgressText(killed, total)
	killed = tonumber(killed) or 0
	total = tonumber(total) or 0

	if total <= 0 then
		return ""
	end

	return string.format("%s/%s", TaskBoard:formatNumberWithCommas(killed), TaskBoard:formatNumberWithCommas(total))
end

local function getBountyTrackerSlot()
	local prey = modules.game_prey

	if not prey or not prey.preyTracker or prey.preyTracker:isDestroyed() then
		return nil
	end

	local contents = prey.preyTracker.contentsPanel

	if not contents then
		return nil
	end

	return contents:getChildById("bslot1")
end

local function setBountyTrackerTooltip(slot, text)
	if not slot then
		return
	end

	slot:setTooltip(text)
end

local function setBountyTrackerInactive()
	local slot = getBountyTrackerSlot()

	if not slot then
		return
	end

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")
	local progressLabel = slot:getChildById("bountyKillProgress")

	if creature then
		creature:setVisible(false)
	end

	if noCreature then
		noCreature:setVisible(true)
	end

	if nameLabel then
		nameLabel:setText(tr("Inactive"))
	end

	if progressLabel then
		progressLabel:setText("")
	end

	if timeBar then
		timeBar:setPercent(0)
	end

	setBountyTrackerTooltip(slot, tr(BOUNTY_TRACKER_TOOLTIP_INACTIVE))
end

local function applyBountyCreatureWidgetStyle(creatureWidget)
	if not creatureWidget then
		return
	end

	if creatureWidget.setCenter then
		creatureWidget:setCenter(true)
	end
	if creatureWidget.setFixedCreatureSize then
		creatureWidget:setFixedCreatureSize(true)
	end
	if creatureWidget.setBaseScale then
		creatureWidget:setBaseScale(true)
	end
	if creatureWidget.setIgnoreDisplacementShift then
		creatureWidget:setIgnoreDisplacementShift(true)
	end
end

local function resolveBountyCreatureDisplay(data)
	local raceId = tonumber(data and data.raceId) or 0
	local name = data and data.creatureName
	local outfit = data and data.outfit

	if raceId > 0 and type(BountyTask.engineRaceCatalog) == "table" then
		for _, entry in ipairs(BountyTask.engineRaceCatalog) do
			if tonumber(entry.raceId) == raceId then
				name = name or entry.creatureName or entry.name
				outfit = outfit or entry.outfit
				break
			end
		end
	end

	if raceId > 0 and g_things and g_things.getRaceData then
		local raceData = g_things.getRaceData(raceId)

		if raceData and raceData.raceId ~= 0 then
			name = raceData.name or name
			outfit = raceData.outfit or outfit
		end
	end

	if not name or name == "" then
		name = "?"
	end

	return name, outfit
end

local function mergeBountyTrackerPayload(incoming)
	if type(incoming) ~= "table" then
		return nil
	end

	local merged = {
		raceId = tonumber(incoming.raceId) or 0,
		creatureName = incoming.creatureName,
		outfit = incoming.outfit,
		monstersKilled = tonumber(incoming.monstersKilled) or 0,
		totalKills = tonumber(incoming.totalKills) or 0,
		isCompleted = incoming.isCompleted,
		isActive = incoming.isActive,
	}

	if lastBountyTrackerData then
		local sameRace = merged.raceId == 0 or merged.raceId == tonumber(lastBountyTrackerData.raceId)

		if sameRace then
			if merged.raceId == 0 then
				merged.raceId = tonumber(lastBountyTrackerData.raceId) or 0
			end

			merged.creatureName = merged.creatureName or lastBountyTrackerData.creatureName
			merged.outfit = merged.outfit or lastBountyTrackerData.outfit
		end
	end

	local resolvedName, resolvedOutfit = resolveBountyCreatureDisplay(merged)

	if resolvedName and resolvedName ~= "?" then
		merged.creatureName = resolvedName
	end

	if resolvedOutfit then
		merged.outfit = resolvedOutfit
	end

	return merged
end

local function getBountyTrackerSlotData(slots)
	if type(slots) ~= "table" then
		return nil
	end

	if #slots == 1 then
		return mergeBountyTrackerPayload(slots[1])
	end

	for _, slot in ipairs(slots) do
		if slot.isActive then
			return mergeBountyTrackerPayload(slot)
		end
	end

	for _, slot in ipairs(slots) do
		local total = tonumber(slot.totalKills) or 0

		if total > 0 then
			return mergeBountyTrackerPayload(slot)
		end
	end

	return nil
end

local function refreshBountyTaskPanelKills(trackerData)
	if not trackerData or not TaskBoard.bountyTaskPanel then
		return
	end

	local container = TaskBoard.bountyTaskPanel:recursiveGetChildById("dailyTasks")

	if not container then
		return
	end

	local raceId = tonumber(trackerData.raceId) or 0
	local killed = tonumber(trackerData.monstersKilled) or 0
	local total = tonumber(trackerData.totalKills) or 0

	for _, panel in ipairs(container:getChildren()) do
		local slotData = panel.bountySlotData

		if not slotData then
			goto continue
		end

		local panelRaceId = tonumber(slotData.raceId) or 0

		if raceId > 0 and panelRaceId ~= raceId then
			goto continue
		end

		slotData.monstersKilled = killed
		slotData.totalKills = total

		local cur = panel:getChildById("killsCurrentValue")
		local tgt = panel:getChildById("killsTargetValue")

		if cur then
			cur:setText(TaskBoard:formatNumberWithCommas(killed))
		end

		if tgt then
			tgt:setText(TaskBoard:formatNumberWithCommas(total))
		end

		local btn = panel:getChildById("selectTaskButton")

		if btn and (slotData.isCompleted or (total > 0 and killed >= total)) then
			btn:setText(tr("Claim Reward"))
			btn:setEnabled(killed >= total)
		end

		::continue::
	end
end

local function setBountyTrackerSelected(data)
	local slot = getBountyTrackerSlot()

	if not slot or not data then
		return
	end

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")
	local progressLabel = slot:getChildById("bountyKillProgress")
	local creatureName, outfit = resolveBountyCreatureDisplay(data)

	if creature then
		if outfit and outfit.type and outfit.type > 0 then
			creature:setOutfit(outfit)
			applyBountyCreatureWidgetStyle(creature)

			local c = creature:getCreature()

			if c then
				c:setStaticWalking(1000)
			end

			creature:setVisible(true)
		else
			creature:setVisible(false)
		end
	end

	if noCreature then
		noCreature:setVisible(false)
	end

	local killed = tonumber(data.monstersKilled) or 0
	local total = tonumber(data.totalKills) or 0

	if nameLabel then
		nameLabel:setText(formatBountyTrackerCreatureName(creatureName))
	end

	if progressLabel then
		progressLabel:setText(formatBountyTrackerProgressText(killed, total))
	end

	if timeBar then
		local percent = 0

		if total > 0 then
			percent = math.min(100, math.floor(killed / total * 100))
		end

		timeBar:setPercent(percent)
	end

	local tooltip = buildBountyTrackerActiveTooltip(creatureName, killed, total)

	setBountyTrackerTooltip(slot, tooltip)
	scheduleEvent(function()
		local trackerSlot = getBountyTrackerSlot()

		if trackerSlot then
			setBountyTrackerTooltip(trackerSlot, tooltip)
		end
	end, 0)
end

local function updateBountyKillTracker(slots)
	local trackerData = getBountyTrackerSlotData(slots)

	if trackerData then
		lastBountyTrackerData = trackerData
		setBountyTrackerSelected(trackerData)
		refreshBountyTaskPanelKills(trackerData)
	else
		lastBountyTrackerData = nil
		setBountyTrackerInactive()
	end

	if modules.game_prey and modules.game_prey.updateTrackerHeight then
		modules.game_prey.updateTrackerHeight()
	end
end

function onBountyKillUpdate(data)
	if type(data) ~= "table" then
		return
	end

	local trackerData = mergeBountyTrackerPayload({
		raceId = data.raceId,
		monstersKilled = data.monstersKilled,
		totalKills = data.totalKills,
		isCompleted = data.isCompleted,
		isActive = true,
	})

	if not trackerData then
		return
	end

	lastBountyTrackerData = trackerData
	setBountyTrackerSelected(trackerData)
	refreshBountyTaskPanelKills(trackerData)

	if modules.game_prey and modules.game_prey.updateTrackerHeight then
		modules.game_prey.updateTrackerHeight()
	end
end

function BountyTask.requestTrackerData()
	if not g_game.isOnline() then
		return
	end

	if g_game.sendOpenMenuTaskBoardAction then
		g_game.sendOpenMenuTaskBoardAction(0)
	end
end

local function refreshBountyKillTrackerFromCache()
	if lastBountyTrackerData then
		setBountyTrackerSelected(lastBountyTrackerData)
	else
		setBountyTrackerInactive()
	end
end

function BountyTask.refreshKillTracker()
	refreshBountyKillTrackerFromCache()
end

function BountyTask:fillSlotPanel(panel, data, selected)
	if not panel or not data then
		return
	end

	panel.bountySlotData = data

	local starsBox = panel:getChildById("stars")

	applyStarsBackdrop(starsBox, data.stars)

	local creature = panel:recursiveGetChildById("slotCreature")
	local creatureName, outfit = resolveBountyCreatureDisplay(data)

	if outfit and outfit.type and outfit.type > 0 and creature then
		creature:setOutfit(outfit)
		applyBountyCreatureWidgetStyle(creature)
		creature:setVisible(true)

		local c = creature:getCreature()

		if c then
			c:setStaticWalking(1000)
		end
	elseif creature then
		creature:setVisible(false)

		local c = creature:getCreature()

		if c then
			c:setStaticWalking(0)
		end
	end

	local nameLabel = starsBox and starsBox:getChildById("creatureName")
	local cur = panel:getChildById("killsCurrentValue")
	local tgt = panel:getChildById("killsTargetValue")
	local expL = panel:getChildById("experienceLabel")
	local bpL = panel:getChildById("bountyPointsLabel")

	nameLabel:setText(capitalizeWords(creatureName))
	cur:setText(TaskBoard:formatNumberWithCommas(data.monstersKilled or 0))
	tgt:setText(TaskBoard:formatNumberWithCommas(data.totalKills or 0))
	expL:setText(TaskBoard:formatNumberWithCommas(data.experiencePoints or 0))
	bpL:setText(TaskBoard:formatNumberWithCommas(data.bountyPoints or 0))

	local btn = panel:getChildById("selectTaskButton")

	if selected then
		btn:setText(tr("Claim Reward"))

		if data.monstersKilled < data.totalKills then
			btn:setEnabled(false)
			btn:setTooltip(tr("Finish the task to claim the reward."))
		else
			btn:setEnabled(true)
		end
	end

	function btn.onClick()
		if selected then
			g_game.sendClaimReward()
		else
			BountyTask:onSelectSlot(panel)
		end
	end

	local container = panel:getParent()

	if not container then
		return
	end

	local children = container:getChildren()

	if selected then
		children[1]:setMarginLeft(325)
	else
		for i = 2, #children do
			local child = children[i]

			child:addAnchor(AnchorLeft, "prev", AnchorRight)
			child:addAnchor(AnchorTop, "parent", AnchorTop)
			child:setMarginLeft(11)
		end
	end
end

function BountyTask:onSelectSlot(panel)
	local data = panel and panel.bountySlotData

	if not data then
		return
	end

	local trackerData = mergeBountyTrackerPayload({
		raceId = data.raceId,
		creatureName = data.creatureName,
		outfit = data.outfit,
		monstersKilled = data.monstersKilled or 0,
		totalKills = data.totalKills or 0,
		isActive = true,
	})

	if trackerData then
		if BountyTask.upsertEngineRaceEntry then
			BountyTask.upsertEngineRaceEntry(trackerData)
		end

		lastBountyTrackerData = trackerData
		setBountyTrackerSelected(trackerData)
	end

	g_game.sendSelectTask(data.taskId)
end

function BountyTask:selectDifficulty(difficulty)
	local difficulties = {
		Expert = 2,
		Adept = 1,
		Beginner = 0,
		Master = 3
	}

	g_game.sendSelectTaskDifficulty(difficulties[difficulty])
end

local bountyCreatureCache, selectedBountyRow, selectedBountyRace, pendingSelectedRaceId, listBuildEvent

local function getActiveBountyRaceSelection()
	if selectedBountyRace and selectedBountyRace.raceId then
		return selectedBountyRace
	end

	local raceId = pendingSelectedRaceId
	if not raceId then
		return nil
	end

	for _, race in ipairs(getBountyCreaturesSorted()) do
		if race.raceId == raceId then
			selectedBountyRace = race
			return race
		end
	end

	return nil
end
local BOUNTY_COLOR_EVEN = "#484848"
local BOUNTY_COLOR_ODD = "#414141"
local BOUNTY_COLOR_SELECTED = "#585858"
local BOUNTY_BATCH_SIZE = 10

local function reindexListColors(list)
	if not list then
		return
	end

	local children = list:getChildren()
	local idx = 0

	for _, row in ipairs(children) do
		local base = idx % 2 == 0 and BOUNTY_COLOR_EVEN or BOUNTY_COLOR_ODD

		row.bountyBaseColor = base

		if row ~= selectedBountyRow then
			row:setBackgroundColor(base)
		end

		idx = idx + 1
	end
end

local function getBountyList()
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return nil
	end

	local leftPanel = preferredListPanel:getChildById("leftPanel")

	if not leftPanel then
		return nil
	end

	return leftPanel:getChildById("list")
end

local function appendRaceEntry(filtered, raceId)
	raceId = tonumber(raceId) or 0
	if raceId <= 0 or not g_things or not g_things.getRaceData then
		return
	end

	local raceData = g_things.getRaceData(raceId)
	if not raceData or raceData.raceId == 0 or not raceData.name or raceData.name == "" then
		return
	end

	if raceData.boss then
		return
	end

	filtered[#filtered + 1] = {
		raceId = raceData.raceId,
		name = raceData.name,
		outfit = raceData.outfit,
		boss = raceData.boss,
	}
end

local function normalizeRaceDisplayEntry(entry)
	if type(entry) ~= "table" then
		return nil
	end

	local raceId = tonumber(entry.raceId) or 0
	if raceId <= 0 then
		return nil
	end

	local name = entry.creatureName or entry.name
	local outfit = entry.outfit

	if not name or name == "" then
		if g_things and g_things.getRaceData then
			local raceData = g_things.getRaceData(raceId)
			if raceData and raceData.raceId ~= 0 then
				name = raceData.name
				outfit = outfit or raceData.outfit
			end
		end
	end

	if not name or name == "" then
		name = string.format("Race %d", raceId)
	end

	return {
		raceId = raceId,
		name = name,
		outfit = outfit,
		boss = false,
	}
end

function BountyTask.upsertEngineRaceEntry(race)
	local normalized = normalizeRaceDisplayEntry(race)
	if not normalized then
		return
	end

	if type(BountyTask.engineRaceCatalog) ~= "table" then
		BountyTask.engineRaceCatalog = {}
	end

	for i, entry in ipairs(BountyTask.engineRaceCatalog) do
		if tonumber(entry.raceId) == normalized.raceId then
			BountyTask.engineRaceCatalog[i] = {
				raceId = normalized.raceId,
				creatureName = normalized.name,
				name = normalized.name,
				outfit = normalized.outfit or entry.outfit,
			}
			bountyCreatureCache = nil
			return
		end
	end

	BountyTask.engineRaceCatalog[#BountyTask.engineRaceCatalog + 1] = {
		raceId = normalized.raceId,
		creatureName = normalized.name,
		name = normalized.name,
		outfit = normalized.outfit,
	}
	bountyCreatureCache = nil
end

local function resolveBountyRaceDisplay(raceId)
	raceId = tonumber(raceId) or 0
	if raceId <= 0 then
		return nil
	end

	if bountyCreatureCache then
		for _, race in ipairs(bountyCreatureCache) do
			if race.raceId == raceId then
				return race
			end
		end
	end

	if type(BountyTask.engineRaceCatalog) == "table" then
		for _, entry in ipairs(BountyTask.engineRaceCatalog) do
			if tonumber(entry.raceId) == raceId then
				return normalizeRaceDisplayEntry(entry)
			end
		end
	end

	if g_things and g_things.getRaceData then
		local raceData = g_things.getRaceData(raceId)
		if raceData and raceData.raceId ~= 0 and raceData.name and raceData.name ~= "" then
			return {
				raceId = raceData.raceId,
				name = raceData.name,
				outfit = raceData.outfit,
				boss = raceData.boss,
			}
		end
	end

	return nil
end

local function mergeEngineRaceCatalog(allRaceIds)
	if type(allRaceIds) ~= "table" or #allRaceIds == 0 then
		return false
	end

	local byId = {}

	for _, entry in ipairs(BountyTask.engineRaceCatalog or {}) do
		local id = tonumber(entry.raceId) or 0
		if id > 0 then
			byId[id] = entry
		end
	end

	for _, entry in ipairs(allRaceIds) do
		if type(entry) == "table" then
			local id = tonumber(entry.raceId) or 0
			if id > 0 then
				byId[id] = entry
			end
		else
			local id = tonumber(entry) or 0
			if id > 0 and not byId[id] then
				byId[id] = { raceId = id }
			end
		end
	end

	local merged = {}
	local raceIds = {}

	for id, entry in pairs(byId) do
		merged[#merged + 1] = entry
		raceIds[#raceIds + 1] = id
	end

	table.sort(merged, function(a, b)
		local nameA = (a.creatureName or a.name or ""):lower()
		local nameB = (b.creatureName or b.name or ""):lower()
		return nameA < nameB
	end)

	BountyTask.engineRaceCatalog = merged
	BountyTask.engineRaceIds = raceIds
	bountyCreatureCache = nil

	return true
end

local function buildBountyCreatureCache()
	local filtered = {}
	local engineCatalog = BountyTask.engineRaceCatalog

	if type(engineCatalog) == "table" and #engineCatalog > 0 then
		for _, entry in ipairs(engineCatalog) do
			local raceId = tonumber(entry.raceId) or 0
			local name = entry.creatureName or entry.name
			local outfit = entry.outfit

			if raceId > 0 and name and name ~= "" then
				filtered[#filtered + 1] = {
					raceId = raceId,
					name = name,
					outfit = outfit,
					boss = false,
				}
			else
				appendRaceEntry(filtered, raceId)
			end
		end
	else
		local engineRaceIds = BountyTask.engineRaceIds

		if type(engineRaceIds) == "table" and #engineRaceIds > 0 then
			for _, raceId in ipairs(engineRaceIds) do
				appendRaceEntry(filtered, tonumber(raceId) or 0)
			end
		else
		local allRaces = {}

		if g_things and g_things.getMonsterList then
			allRaces = g_things.getMonsterList() or {}
		elseif g_things and g_things.getRacesByName then
			local ok, races = pcall(function()
				return g_things.getRacesByName("")
			end)

			if ok and type(races) == "table" then
				allRaces = races
			end
		end

		for _, race in ipairs(allRaces) do
			if race.raceId and race.raceId > 0 and not race.boss and race.name and race.name ~= "" then
				filtered[#filtered + 1] = race
			end
		end
		end
	end

	table.sort(filtered, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	bountyCreatureCache = filtered
end

local function getBountyCreaturesSorted()
	if not bountyCreatureCache then
		buildBountyCreatureCache()
	end

	return bountyCreatureCache
end

local function selectBountyRow(row, race)
	if selectedBountyRow and selectedBountyRow ~= row then
		selectedBountyRow:setBackgroundColor(selectedBountyRow.bountyBaseColor or BOUNTY_COLOR_EVEN)
	end

	selectedBountyRow = row
	selectedBountyRace = race
	pendingSelectedRaceId = race and race.raceId

	if row then
		row:setBackgroundColor(BOUNTY_COLOR_SELECTED)
	end
end

local function applyBountyCreaturePreview(creatureWidget, outfit, animate)
	if not creatureWidget or not outfit then
		return
	end

	creatureWidget:setOutfit(outfit)

	if animate then
		local c = creatureWidget:getCreature()

		if c then
			c:setStaticWalking(1000)
		end
	end
end

local function setSlotCreature(slotWidget, race)
	if not slotWidget or not race then
		return
	end

	local creature = slotWidget:getChildById("slotCreature")

	if creature and race.outfit then
		applyBountyCreaturePreview(creature, race.outfit, true)
		creature:setVisible(true)
	end

	slotWidget.assignedRaceId = race.raceId
end

local function cancelListBuild()
	if listBuildEvent then
		removeEvent(listBuildEvent)

		listBuildEvent = nil
	end
end

local function createBountyRow(list, race, rowIndex)
	local row = g_ui.createWidget("BountyCreatureRow", list)

	if not row then
		return
	end

	local base = rowIndex % 2 == 0 and BOUNTY_COLOR_EVEN or BOUNTY_COLOR_ODD

	row.bountyBaseColor = base
	row.bountyRace = race

	row:setBackgroundColor(base)

	local sprite = row:getChildById("creatureSprite")

	if sprite and race.outfit then
		applyBountyCreaturePreview(sprite, race.outfit, false)
	end

	local nameLabel = row:getChildById("creatureName")

	if nameLabel then
		nameLabel:setText(capitalizeWords(race.name))
	end

	function row.onClick()
		selectBountyRow(row, race)
	end

	function row.onMousePress(_, mousePos, mouseButton)
		if mouseButton == MouseLeftButton then
			selectBountyRow(row, race)
			return true
		end
	end
end

local function populateBountyCreatureList(filterText, excludeRaceIds)
	cancelListBuild()

	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	local leftPanel = preferredListPanel:getChildById("leftPanel")

	if not leftPanel then
		return
	end

	local list = leftPanel:getChildById("list")

	if not list then
		return
	end

	local preserveRaceId = pendingSelectedRaceId
		or (selectedBountyRace and selectedBountyRace.raceId)

	selectedBountyRow = nil

	list:destroyChildren()

	local creatures = getBountyCreaturesSorted()
	local lowerFilter = filterText and filterText:lower() or ""
	local excludeSet = {}

	for _, id in ipairs(excludeRaceIds or {}) do
		excludeSet[id] = true
	end

	local toCreate = {}

	for _, race in ipairs(creatures) do
		if not excludeSet[race.raceId] and (lowerFilter == "" or race.name:lower():find(lowerFilter, 1, true)) then
			toCreate[#toCreate + 1] = race
		end
	end

	local idx = 1
	local total = #toCreate

	local function createNextBatch()
		listBuildEvent = nil

		if not list or list:isDestroyed() then
			return
		end

		local layout = list:getLayout()

		if layout then
			layout:disableUpdates()
		end

		local endIdx = math.min(idx + BOUNTY_BATCH_SIZE - 1, total)

		for i = idx, endIdx do
			createBountyRow(list, toCreate[i], i - 1)
		end

		idx = endIdx + 1

		if layout then
			layout:enableUpdates()
			layout:update()
		end

		if idx <= total then
			listBuildEvent = addEvent(createNextBatch)
		else
			if preserveRaceId then
				for _, child in ipairs(list:getChildren()) do
					local rowRace = child.bountyRace

					if rowRace and rowRace.raceId == preserveRaceId then
						selectBountyRow(child, rowRace)
						break
					end
				end
			end
		end
	end

	createNextBatch()
end

local function getExcludedRaceIds()
	local ids = {}
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return ids
	end

	local rightPanel = preferredListPanel:getChildById("rightPanel")

	if not rightPanel then
		return ids
	end

	local slotsList = rightPanel:getChildById("slotsList")

	if not slotsList then
		return ids
	end

	for _, row in ipairs(slotsList:getChildren()) do
		local prefSlot = row:getChildById("preferredSlot")

		if prefSlot and prefSlot.assignedRaceId then
			ids[#ids + 1] = prefSlot.assignedRaceId
		end

		local unwSlot = row:getChildById("unwantedSlot")

		if unwSlot and unwSlot.assignedRaceId then
			ids[#ids + 1] = unwSlot.assignedRaceId
		end
	end

	return ids
end

function BountyTask:filterPreferredList(text)
	populateBountyCreatureList(text, getExcludedRaceIds())
end

function BountyTask:clearPreferredSearch()
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	local leftPanel = preferredListPanel:getChildById("leftPanel")

	if not leftPanel then
		return
	end

	local search = leftPanel:getChildById("search")

	if search then
		search:setText("")
	end

	populateBountyCreatureList("", getExcludedRaceIds())
end

function BountyTask:showPreferredList()
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	bountyCreatureCache = nil
	selectedBountyRow = nil
	selectedBountyRace = nil
	pendingSelectedRaceId = nil

	if g_game.sendOpenPreferredList then
		g_game.sendOpenPreferredList()
	end

	populateBountyCreatureList("", getExcludedRaceIds())

	preferredListPanel:show()
	preferredListPanel:raise()
	preferredListPanel:focus()

	local chainTransparent = TaskBoard.chainTransparent

	if chainTransparent then
		chainTransparent:show()
		chainTransparent:lower()
		preferredListPanel:raise()
	end
end

function BountyTask:closePreferredList()
	cancelListBuild()

	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	preferredListPanel:hide()

	local chainTransparent = TaskBoard.chainTransparent

	if chainTransparent then
		chainTransparent:hide()
	end
end

local PREFERRED_CLEAR_COST = 10
local lastPreferredListData = nil
local PREFERRED_UNLOCK_COSTS = {
	300,
	600,
	900,
	1200
}

local function setPreferredCostPanelValue(costPanel, cost)
	if not costPanel then
		return
	end

	local valueLabel = costPanel:getChildById("preferredCostValue") or costPanel:getChildById("unwantedCostValue")

	if valueLabel then
		valueLabel:setText(TaskBoard:formatNumberWithCommas(cost or PREFERRED_CLEAR_COST))
	end
end

local function patchPreferredListSlot(slotIndex, isUnwanted)
	if not lastPreferredListData then
		return
	end

	local entry = lastPreferredListData[slotIndex + 1]

	if not entry then
		return
	end

	if isUnwanted then
		entry.unwanted = 0
	else
		entry.preferred = 0
	end
end

local function clearSlotWidget(slotWidget)
	if not slotWidget then
		return
	end

	local creature = slotWidget:getChildById("slotCreature")

	if creature then
		creature:setVisible(false)

		local c = creature:getCreature()

		if c then
			c:setStaticWalking(0)
		end
	end

	slotWidget.assignedRaceId = nil
end

local function wireSlotAssignButton(row, btn, costPanel, slotIndex, isUnwanted)
	if not btn then
		return
	end

	btn:setText(tr("Assign"))
	btn:setEnabled(true)

	if costPanel then
		costPanel:setVisible(false)
	end
end

function BountyTask:onPreferredAssignClick(button)
	local row = button and button:getParent()

	if not row then
		return
	end

	self:assignToRow(row, row.bountyPreferredUiSlot or 0, false)
end

function BountyTask:onUnwantedAssignClick(button)
	local row = button and button:getParent()

	if not row then
		return
	end

	self:assignToRow(row, row.bountyPreferredUiSlot or 0, true)
end

local function wireSlotClearButton(row, slotWidget, btn, costPanel, slotIndex, isUnwanted)
	btn:setText(tr("Clear"))
	setPreferredCostPanelValue(costPanel, PREFERRED_CLEAR_COST)

	if costPanel then
		costPanel:setVisible(true)
	end

	btn.onClick = function()
		if isUnwanted then
			BountyTask:onUnwantedClearClick(btn)
		else
			BountyTask:onPreferredClearClick(btn)
		end
	end
end

function BountyTask:assignToRow(row, slotIndex, isUnwanted)
	local race = getActiveBountyRaceSelection()

	if not race then
		if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
			modules.game_textmessage.displayFailureMessage(tr("Select a creature from the list first."))
		end

		return
	end

	local slotId = isUnwanted and "unwantedSlot" or "preferredSlot"
	local btnId = isUnwanted and "unwantedButton" or "preferredButton"
	local costId = isUnwanted and "unwantedCostPanel" or "preferredCostPanel"
	local slotWidget = row:getChildById(slotId)
	local btn = row:getChildById(btnId)
	local costPanel = row:getChildById(costId)

	BountyTask.upsertEngineRaceEntry(race)
	setSlotCreature(slotWidget, race)

	if isUnwanted then
		g_game.sendPreferredListUnwanted(slotIndex, race.raceId)
	else
		g_game.sendPreferredListPreferred(slotIndex, race.raceId)
	end

	if selectedBountyRow then
		selectedBountyRow:destroy()

		selectedBountyRow = nil
	end

	selectedBountyRace = nil
	pendingSelectedRaceId = nil

	reindexListColors(getBountyList())
	wireSlotClearButton(row, slotWidget, btn, costPanel, slotIndex, isUnwanted)
end

function BountyTask:onPreferredClearClick(button)
	local row = button and button:getParent()
	local slotIndex = row and row.bountyPreferredUiSlot or 0
	local slotWidget = row and row:getChildById("preferredSlot")
	local costPanel = row and row:getChildById("preferredCostPanel")

	if not row or not button then
		return
	end

	g_game.sendPreferredListClearPreferred(slotIndex)
	patchPreferredListSlot(slotIndex, false)
	clearSlotWidget(slotWidget)
	wireSlotAssignButton(row, button, costPanel, slotIndex, false)
	button.onClick = function()
		BountyTask:onPreferredAssignClick(button)
	end

	if costPanel then
		costPanel:setVisible(false)
	end
	populateBountyCreatureList("", getExcludedRaceIds())
end

function BountyTask:onUnwantedClearClick(button)
	local row = button and button:getParent()
	local slotIndex = row and row.bountyPreferredUiSlot or 0
	local slotWidget = row and row:getChildById("unwantedSlot")
	local costPanel = row and row:getChildById("unwantedCostPanel")

	if not row or not button then
		return
	end

	g_game.sendPreferredListClearUnwanted(slotIndex)
	patchPreferredListSlot(slotIndex, true)
	clearSlotWidget(slotWidget)
	wireSlotAssignButton(row, button, costPanel, slotIndex, true)
	button.onClick = function()
		BountyTask:onUnwantedAssignClick(button)
	end

	if costPanel then
		costPanel:setVisible(false)
	end
	populateBountyCreatureList("", getExcludedRaceIds())
end

local function buildPreferredSlotRow(container, slotIndex, data)
	local row = g_ui.createWidget("PreferredSlotRow", container)

	if not row then
		return
	end

	row.bountyPreferredUiSlot = slotIndex

	local prefSlot = row:getChildById("preferredSlot")
	local prefBtn = row:getChildById("preferredButton")
	local prefCost = row:getChildById("preferredCostPanel")
	local unwSlot = row:getChildById("unwantedSlot")
	local unwBtn = row:getChildById("unwantedButton")
	local unwCost = row:getChildById("unwantedCostPanel")

	if data.preferred and data.preferred ~= 0 then
		local raceData = resolveBountyRaceDisplay(data.preferred)

		if raceData then
			setSlotCreature(prefSlot, raceData)
		else
			prefSlot.assignedRaceId = data.preferred
		end

		wireSlotClearButton(row, prefSlot, prefBtn, prefCost, slotIndex, false)
	else
		wireSlotAssignButton(row, prefBtn, prefCost, slotIndex, false)
	end

	if data.unwanted and data.unwanted ~= 0 then
		local raceData = resolveBountyRaceDisplay(data.unwanted)

		if raceData then
			setSlotCreature(unwSlot, raceData)
		else
			unwSlot.assignedRaceId = data.unwanted
		end

		wireSlotClearButton(row, unwSlot, unwBtn, unwCost, slotIndex, true)
	else
		wireSlotAssignButton(row, unwBtn, unwCost, slotIndex, true)
	end
end

local function buildPreferredLockedRow(container, slotIndex)
	local row = g_ui.createWidget("PreferredLockedRow", container)

	if not row then
		return
	end

	local costLabel = row:recursiveGetChildById("unlockCostValue")
	local unlockCost = PREFERRED_UNLOCK_COSTS[slotIndex] or slotIndex * 300

	if costLabel then
		costLabel:setText(TaskBoard:formatNumberWithCommas(unlockCost))
	end

	local btn = row:getChildById("unlockButton")

	if btn then
		function btn.onClick()
			-- our engine requires the slot number (bountyPreferredAction BUY_SLOT ignores slot == 0),
			-- while the module had it only in the closure and never passed it anywhere
			g_game.sendPreferredListUnlockSlots(slotIndex)
		end
	end
end

local function updatePreferredList(preferredListData)
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	local rightPanel = preferredListPanel:getChildById("rightPanel")

	if not rightPanel then
		return
	end

	local slotsList = rightPanel:getChildById("slotsList")

	if not slotsList then
		return
	end

	slotsList:destroyChildren()

	if type(preferredListData) ~= "table" then
		return
	end

	local snapshot = {}

	for i, data in ipairs(preferredListData) do
		snapshot[i] = {
			slot = data.slot,
			unlocked = data.unlocked,
			preferred = data.preferred,
			unwanted = data.unwanted,
			price = data.price
		}
	end

	lastPreferredListData = snapshot

	local lockedIndex = 1

	for i, data in ipairs(snapshot) do
		local isUnlocked = data.unlocked or i == 1

		if isUnlocked then
			buildPreferredSlotRow(slotsList, i - 1, data)
		else
			buildPreferredLockedRow(slotsList, lockedIndex)

			lockedIndex = lockedIndex + 1
		end
	end

	if preferredListPanel:isVisible() then
		local search = preferredListPanel:recursiveGetChildById("search")
		local filterText = search and search:getText() or ""
		populateBountyCreatureList(filterText, getExcludedRaceIds())
	end
end

function BountyTask:rerollTasks()
	local rerollTokens = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollPanel")
	local rerollButton = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollButton")
	local valueLabel = rerollTokens and rerollTokens:getChildById("value")
	local tokens = valueLabel and tonumber(valueLabel:getText()) or 0

	if tokens == 1 and rerollButton then
		rerollButton:setEnabled(false)
		rerollButton:setTooltip(tr("You don't have more reroll tokens."))
	end

	g_game.sendRerollTasks()
end

function BountyTask:claimDaily()
	if not CLAIMED_DAILY_TASK_STATE then
		return
	end

	local rerollBox = TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	local claimButton = rerollBox:getChildById("claimButton")

	claimButton:setEnabled(false)
	claimButton:setImageClip("0 40 108 20")
	claimButton:setTooltip(tr("Already claimed today."))

	CLAIMED_DAILY_TASK_STATE = false

	g_game.sendClaimDaily()
end

function BountyTask:updateTalisman(talismanId)
	g_game.sendUpgradeTalisman(talismanId)
end

local function bountyDifficultyOptionText(index)
	local i = tonumber(index) or 0
	local names = {
		tr("Beginner"),
		tr("Adept"),
		tr("Expert"),
		tr("Master")
	}

	return names[i + 1] or names[1]
end

local function getTalismanBonus(talismanId, level)
	local percent = 2.5

	level = tonumber(level) or 0
	talismanId = tonumber(talismanId) or 0

	if talismanId <= 2 then
		local lvl1 = math.min(level, 15)

		percent = percent + lvl1 * 0.5

		if level > 15 then
			local lvl2 = math.min(level - 15, 40)

			percent = percent + lvl2 * 0.25
		end

		if level > 55 then
			percent = percent + (level - 55) * 0.1
		end

		return math.min(percent, 50)
	end

	percent = 5

	if talismanId == 3 then
		local lvl1 = math.min(level, 15)

		percent = percent + lvl1 * 1

		if level > 15 then
			local lvl2 = math.min(level - 15, 40)

			percent = percent + lvl2 * 0.5
		end

		if level > 55 then
			percent = percent + (level - 55) * 0.2
		end

		return math.min(percent, 100)
	end

	return 0
end

local function applyBountyTalismanRow(talismanId, data, labelWidget, upgradeButton, bountyPointsPanel)
	if not data then
		return
	end

	local level = tonumber(data.talismaLevel) or 0
	local price = tonumber(data.upgradePrice) or 0
	local can = data.canUpgrade == true

	if labelWidget then
		labelWidget:setText(string.format("%.1f", getTalismanBonus(talismanId, level)))
	end

	if bountyPointsPanel then
		local v = bountyPointsPanel:getChildById("value")

		if v then
			v:setText(TaskBoard:formatNumberWithCommas(price))
		end
	end

	if upgradeButton then
		upgradeButton:setEnabled(can)

		if can then
			local nextTier = getTalismanBonus(talismanId, level + 1)

			upgradeButton:setText(tr("Upgrade to %.1f %%", nextTier))
		else
			local nextTier = getTalismanBonus(talismanId, level + 1)

			upgradeButton:setText(tr("Upgrade to %.1f %%", nextTier))
			upgradeButton:setTooltip(tr("You do not have enough Bounty Points."))
		end
	end
end

function onBountyTasksDaily(slots, rerollTokens, claimUnlocked, difficultyBountyTask, talismanData, preferredListData)
	updateBountyKillTracker(slots)

	local container = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("dailyTasks")

	if not container then
		if preferredListData ~= nil and type(preferredListData) == "table" then
			updatePreferredList(preferredListData)
		end
		return
	end

	container:destroyChildren()

	if #slots == 1 then
		local panel = g_ui.createWidget("BountyTaskSlotPanel", container)

		if panel then
			BountyTask:fillSlotPanel(panel, slots[1], true)
		end
	else
		for _, slotData in ipairs(slots) do
			local panel = g_ui.createWidget("BountyTaskSlotPanel", container)

			if panel then
				BountyTask:fillSlotPanel(panel, slotData)
			end
		end
	end

	container:updateLayout()

	local bountyPanel = container:getParent()

	if bountyPanel then
		bountyPanel:updateLayout()
	end

	local rerollBox = TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")

	if not rerollBox then
		if preferredListData ~= nil and type(preferredListData) == "table" then
			updatePreferredList(preferredListData)
		end
		return
	end

	local filterDifficulty = rerollBox:getChildById("showFilterDifficulty")
	local rerollButton = rerollBox:getChildById("rerollButton")
	local rerollTokensLabel = rerollBox:getChildById("rerollPanel")
	local rerollTokensValue = rerollTokensLabel and rerollTokensLabel:getChildById("value")
	local claimButton = rerollBox:getChildById("claimButton")
	local claimWarning = rerollBox:getChildById("claimDailyWarning")
	local tokenCount = tonumber(rerollTokens) or 0

	filterDifficulty:setCurrentOption(bountyDifficultyOptionText(difficultyBountyTask), true)
	rerollTokensValue:setText(rerollTokens and tostring(rerollTokens) or "0")

	if claimWarning then
		claimWarning:setVisible(tokenCount >= MAX_REROLL_TOKENS)
	end

	if not rerollTokens or tonumber(rerollTokens) == 0 then
		rerollButton:setEnabled(false)
		rerollButton:setImageClip("0 40 108 20")
		rerollButton:setTooltip(tr("You have no rerolls left."))
	else
		rerollButton:setEnabled(true)
		rerollButton:setImageClip("0 0 108 20")
	end

	if tonumber(claimUnlocked) == 0 then
		claimButton:setEnabled(tokenCount < MAX_REROLL_TOKENS)
		claimButton:setImageClip(tokenCount < MAX_REROLL_TOKENS and "0 0 108 20" or "0 40 108 20")
		if tokenCount >= MAX_REROLL_TOKENS then
			claimButton:setTooltip(tr("You have reached the maximum of 10 Reroll Tokens."))
		else
			claimButton:setTooltip("")
		end

		CLAIMED_DAILY_TASK_STATE = tokenCount < MAX_REROLL_TOKENS
	elseif tonumber(claimUnlocked) == 1 then
		claimButton:setEnabled(false)
		claimButton:setImageClip("0 40 108 20")
		claimButton:setTooltip(tr("Already claimed today."))

		CLAIMED_DAILY_TASK_STATE = false
	elseif tonumber(claimUnlocked) == 2 then
		claimButton:setEnabled(false)
		claimButton:setImageClip("0 40 108 20")
		claimButton:setTooltip(tr("Limit reached."))

		CLAIMED_DAILY_TASK_STATE = false
	end

	local talismanPanel = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("bountyTalismans")

	if talismanPanel and type(talismanData) == "table" and #talismanData >= 4 then
		local damageTalisman = talismanPanel:recursiveGetChildById("damageAgainst")
		local damageButton = talismanPanel:getChildById("damageButton")
		local bountyDamagePanel = talismanPanel:getChildById("bountyPointsDamagePanel")

		applyBountyTalismanRow(0, talismanData[1], damageTalisman, damageButton, bountyDamagePanel)

		local lifeLeechTalisman = talismanPanel:recursiveGetChildById("LifeLeechAgainst")
		local lifeLeechButton = talismanPanel:getChildById("lifeLeechButton")
		local bountyLifeLeechPanel = talismanPanel:getChildById("bountyPointsLifeLeechPanel")

		applyBountyTalismanRow(1, talismanData[2], lifeLeechTalisman, lifeLeechButton, bountyLifeLeechPanel)

		local moreLootTalisman = talismanPanel:recursiveGetChildById("MoreLootAgainst")
		local moreLootButton = talismanPanel:getChildById("moreLootButton")
		local bountyMoreLootPanel = talismanPanel:getChildById("bountyPointsMoreLootPanel")

		applyBountyTalismanRow(2, talismanData[3], moreLootTalisman, moreLootButton, bountyMoreLootPanel)

		local bestiaryTalisman = talismanPanel:recursiveGetChildById("BestiaryAgainst")
		local bestiaryButton = talismanPanel:getChildById("bestiaryButton")
		local bountyBestiaryPanel = talismanPanel:getChildById("bountyPointsBestiaryPanel")

		applyBountyTalismanRow(3, talismanData[4], bestiaryTalisman, bestiaryButton, bountyBestiaryPanel)
	end

	if preferredListData ~= nil and type(preferredListData) == "table" then
		updatePreferredList(preferredListData)
	end
end

local bountyGameStartEvent1 = nil
local bountyGameStartEvent2 = nil

local function cancelBountyGameStartEvents()
	if bountyGameStartEvent1 then
		removeEvent(bountyGameStartEvent1)
		bountyGameStartEvent1 = nil
	end
	if bountyGameStartEvent2 then
		removeEvent(bountyGameStartEvent2)
		bountyGameStartEvent2 = nil
	end
end

local function onGameStartBounty()
	bountyCreatureCache = nil
	cancelBountyGameStartEvents()
	bountyGameStartEvent1 = scheduleEvent(buildBountyCreatureCache, 500)
	bountyGameStartEvent2 = scheduleEvent(function()
		bountyGameStartEvent2 = nil
		BountyTask.requestTrackerData()
	end, 500)
end

local function onGameEndBounty()
	cancelListBuild()
	cancelBountyGameStartEvents()
	pendingBountyData = nil

	bountyCreatureCache = nil
	selectedBountyRow = nil
	selectedBountyRace = nil
	pendingSelectedRaceId = nil
	lastBountyTrackerData = nil

	setBountyTrackerInactive()
end

-- ADAPTER for our engine.
-- The engine splits bounty data into TWO events always arriving in pairs and always in this order:
-- onBountyTaskData (header + monsters + talismans), followed immediately by onBountyPreferredData
-- (preference list slots). The module expects everything at once in onBountyTasksDaily, so
-- we stash the first packet in a cache and only call the handler on the second one.
local pendingBountyData = nil

local BOUNTY_ENGINE_STARS = { [0] = 0, [1] = 1, [2] = 2 }

function onEngineBountyTaskData(header, monsters, talismans)
	local slots = {}

	for _, m in ipairs(monsters or {}) do
		if BountyTask.upsertEngineRaceEntry then
			BountyTask.upsertEngineRaceEntry({
				raceId = m.raceId,
				creatureName = m.creatureName,
				name = m.creatureName,
				outfit = m.outfit,
			})
		end

		slots[#slots + 1] = {
			taskId = m.taskIndex,
			raceId = m.raceId,
			creatureName = m.creatureName,
			outfit = m.outfit,
			monstersKilled = m.currentKills,
			totalKills = m.totalKills,
			experiencePoints = m.rewardXp,
			bountyPoints = m.rewardPoints,
			rerollPoints = m.rewardReroll,
			stars = BOUNTY_ENGINE_STARS[m.rarity] or 0,
			isActive = m.isActive == 1,
			isCompleted = m.isCompleted == 1
		}
	end

	local talismanData = {}

	for _, t in ipairs(talismans or {}) do
		talismanData[#talismanData + 1] = {
			talismaLevel = t.currentValue,
			upgradePrice = t.upgradeCost,
			-- the module expects a boolean, the engine gives 0/1
			canUpgrade = t.isActiveUpgrade == 1
		}
	end

	pendingBountyData = {
		slots = slots,
		talismanData = talismanData,
		-- the engine reports difficulty on a 1-4 scale, the module counts 0-3
		difficulty = math.max(0, (header and header.difficulty or 1) - 1),
		rerollTokens = header and header.rerollPoints or 0,
		-- engine: claimDaily == 1 means "can be claimed"; module: 0 means "unlocked"
		claimUnlocked = (header and header.claimDaily == 1) and 0 or 1
	}

	if TaskBoard and TaskBoard.setBountyKillBoostRemaining and header then
		TaskBoard.setBountyKillBoostRemaining(header.bountyKillBoostRemaining)
	end
end

local function normalizeEngineRaceCatalog(raceList)
	local catalog = {}
	local raceIds = {}

	if type(raceList) ~= "table" then
		return catalog, raceIds
	end

	for _, entry in ipairs(raceList) do
		if type(entry) == "table" then
			local raceId = tonumber(entry.raceId) or 0
			if raceId > 0 then
				catalog[#catalog + 1] = entry
				raceIds[#raceIds + 1] = raceId
			end
		else
			local raceId = tonumber(entry) or 0
			if raceId > 0 then
				raceIds[#raceIds + 1] = raceId
			end
		end
	end

	return catalog, raceIds
end

function onEngineBountyPreferredData(preferredSlots, _, allRaceIds)
	local data = pendingBountyData or {
		slots = {},
		talismanData = {},
		difficulty = 0,
		rerollTokens = 0,
		claimUnlocked = 1
	}

	pendingBountyData = nil

	local preferredListData = {}

	for _, s in ipairs(preferredSlots or {}) do
		preferredListData[#preferredListData + 1] = {
			slot = s.slot,
			-- the engine sends locked (1 = locked), the module reads unlocked
			unlocked = s.locked == 0,
			preferred = s.preferred,
			unwanted = s.unwanted,
			price = s.price
		}
	end

	if not mergeEngineRaceCatalog(allRaceIds) then
		for _, slot in ipairs(preferredListData) do
			if slot.preferred and slot.preferred ~= 0 then
				BountyTask.upsertEngineRaceEntry({ raceId = slot.preferred })
			end
			if slot.unwanted and slot.unwanted ~= 0 then
				BountyTask.upsertEngineRaceEntry({ raceId = slot.unwanted })
			end
		end
	end

	onBountyTasksDaily(data.slots, data.rerollTokens, data.claimUnlocked, data.difficulty,
		data.talismanData, preferredListData)

	local preferredListPanel = TaskBoard.preferredListPanel
	if preferredListPanel and preferredListPanel:isVisible() then
		local search = preferredListPanel:recursiveGetChildById("search")
		local filterText = search and search:getText() or ""
		populateBountyCreatureList(filterText, getExcludedRaceIds())
	end
end

local function wireBountyBoostKillsButton()
	local rerollBox = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	local boostButton = rerollBox and rerollBox:getChildById("boostKills")

	if not boostButton or boostButton._taskBoardStoreBound then
		return
	end

	boostButton._taskBoardStoreBound = true
	boostButton:setTooltip(tr("Open Store: %s", STORE_BOUNTY_KILL_BOOST))

	function boostButton.onClick()
		if TaskBoard and TaskBoard.openTaskHuntStoreSearch then
			TaskBoard.openTaskHuntStoreSearch(STORE_BOUNTY_KILL_BOOST)
		end
	end
end

function BountyTask:init()
	connect(g_game, {
		onBountyKillUpdate = onBountyKillUpdate,
		onBountyTaskData = onEngineBountyTaskData,
		onBountyPreferredData = onEngineBountyPreferredData,
		onGameStart = onGameStartBounty,
		onGameEnd = onGameEndBounty
	})
	wireBountyBoostKillsButton()
	scheduleEvent(refreshBountyKillTrackerFromCache, 0)
end

function BountyTask:terminate()
	disconnect(g_game, {
		onBountyKillUpdate = onBountyKillUpdate,
		onBountyTaskData = onEngineBountyTaskData,
		onBountyPreferredData = onEngineBountyPreferredData,
		onGameStart = onGameStartBounty,
		onGameEnd = onGameEndBounty
	})
	onGameEndBounty()
end
