-- chunkname: @/game_taskboard/menus/weekly_task.lua

TaskBoard.WeeklyTask = {}

local WeeklyTask = TaskBoard.WeeklyTask

WeeklyTask.isWeeklyTaskActive = false

local lastWeeklyTasksState
local WEEKLY_UNLOCK_BUTTON_HEIGHT = 100
local WEEKLY_UNLOCK_BOTTOM_MARGIN = 2
local WEEKLY_SLOTS_MARGIN_UNLOCK = WEEKLY_UNLOCK_BUTTON_HEIGHT + WEEKLY_UNLOCK_BOTTOM_MARGIN + 4

local function syncWeeklyUnlockButton(unlockButton, showUnlock, slotsList)
	if not unlockButton then
		return
	end

	unlockButton:setVisible(showUnlock)
	if unlockButton.setHeight then
		unlockButton:setHeight(showUnlock and WEEKLY_UNLOCK_BUTTON_HEIGHT or 0)
	end

	if slotsList and slotsList.setMarginBottom then
		slotsList:setMarginBottom(showUnlock and WEEKLY_SLOTS_MARGIN_UNLOCK or 4)
	end

	if slotsList and slotsList.getParent then
		local parent = slotsList:getParent()
		if parent and parent.updateLayout then
			parent:updateLayout()
		end
	end
end

local function copyWeeklyTasksState(state)
	if type(state) ~= "table" then
		return nil
	end

	local killEntries = {}
	for _, entry in ipairs(state.killEntries or {}) do
		killEntries[#killEntries + 1] = {
			raceId = entry.raceId,
			creatureName = entry.creatureName,
			outfit = entry.outfit,
			totalMonsterKilleds = entry.totalMonsterKilleds,
			totalKills = entry.totalKills,
			state = entry.state,
		}
	end

	local deliveryEntries = {}
	for _, entry in ipairs(state.deliveryEntries or {}) do
		deliveryEntries[#deliveryEntries + 1] = {
			taskId = entry.taskId,
			taskItemId = entry.taskItemId,
			taskClientId = entry.taskClientId,
			count = entry.count,
			totalItems = entry.totalItems,
			available = entry.available,
			completed = entry.completed,
			state = entry.state,
		}
	end

	return {
		killEntries = killEntries,
		deliveryEntries = deliveryEntries,
		killsAnyMonsters = state.killsAnyMonsters,
		killedsAnyMonsters = state.killedsAnyMonsters,
		kill = state.kill,
		delivery = state.delivery,
		totalPoints = state.totalPoints,
		totalTasksCompleted = state.totalTasksCompleted,
		mondayTime = state.mondayTime,
		weeklyTaskActive = state.weeklyTaskActive,
		unlockedDifficulties = state.unlockedDifficulties,
		killTaskRewardExp = state.killTaskRewardExp,
		deliveryTaskRewardExp = state.deliveryTaskRewardExp,
	}
end

local function buildWeeklyTaskRewardInfo(weeklyTasks)
	if not TaskBoard.weeklyPanel then
		return
	end

	local label = TaskBoard.weeklyPanel:recursiveGetChildById("weeklyTaskRewardInfo")
	if not label then
		return
	end

	local killExp = tonumber(weeklyTasks.killTaskRewardExp) or 0
	local deliveryExp = tonumber(weeklyTasks.deliveryTaskRewardExp) or 0

	label:setText(tr("Each kill task rewards you with %s XP and each delivery task will reward you with %s XP.", TaskBoard:formatNumberWithCommas(killExp), TaskBoard:formatNumberWithCommas(deliveryExp)))
end

function WeeklyTask:updateOverlayVisibility()
	local canShowOverlay = self.isWeeklyTaskActive and TaskBoard.mainWindow and TaskBoard.mainWindow:isVisible() and TaskBoard.weeklyPanel and TaskBoard.weeklyPanel:isVisible() and TaskBoard.chainTransparentWeekly and TaskBoard.weeklyProgressPanel

	if canShowOverlay then
		TaskBoard.chainTransparentWeekly:show()
		TaskBoard.weeklyProgressPanel:show()
		TaskBoard.weeklyProgressPanel:raise()
		TaskBoard.weeklyProgressPanel:focus()

		return
	end

	if TaskBoard.weeklyProgressPanel then
		TaskBoard.weeklyProgressPanel:hide()
	end

	if TaskBoard.chainTransparentWeekly then
		TaskBoard.chainTransparentWeekly:hide()
	end
end

local function capitalizeWords(str)
	return (str or ""):gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
end

local function getKillSlotsList()
	local weeklyPanel = TaskBoard.weeklyPanel

	if not weeklyPanel then
		return nil
	end

	local killTasks = weeklyPanel:recursiveGetChildById("killTasks")

	if not killTasks then
		return nil
	end

	return killTasks:recursiveGetChildById("killSlotsList")
end

local function getDeliverySlotsList()
	local weeklyPanel = TaskBoard.weeklyPanel

	if not weeklyPanel then
		return nil
	end

	local deliveryTasks = weeklyPanel:recursiveGetChildById("deliveryTasks")

	if not deliveryTasks then
		return nil
	end

	return deliveryTasks:recursiveGetChildById("deliverySlotsList")
end

local function weeklyRaceDisplayFromEntry(entry)
	if not entry then
		return nil
	end

	local raceId = tonumber(entry.raceId) or 0
	local raceData = raceId > 0 and g_things and g_things.getRaceData and g_things.getRaceData(raceId)

	if raceData and raceData.raceId ~= 0 then
		return raceData
	end

	if entry.outfit and entry.outfit.type and entry.outfit.type > 0 then
		return {
			raceId = raceId,
			name = entry.creatureName or "?",
			outfit = entry.outfit
		}
	end

	return raceData
end

local function weeklyRaceHasOutfit(raceData)
	return raceData and raceData.outfit and (tonumber(raceData.outfit.type) or 0) > 0
end

local function resolveWeeklyKillDisplay(killEntry, raceId)
	local raceData = killEntry and weeklyRaceDisplayFromEntry(killEntry)
	local rid = tonumber(raceId) or (killEntry and tonumber(killEntry.raceId)) or 0

	if (not raceData or not weeklyRaceHasOutfit(raceData)) and rid > 0 and g_things and g_things.getRaceData then
		local fromThings = g_things.getRaceData(rid)
		if fromThings and fromThings.raceId ~= 0 then
			raceData = fromThings
		end
	end

	local creatureName = "?"
	if raceData and raceData.name and raceData.name ~= "" then
		creatureName = raceData.name
	elseif killEntry and killEntry.creatureName and killEntry.creatureName ~= "" then
		creatureName = killEntry.creatureName
	end

	return raceData, creatureName
end

local WEEKLY_TASK_COMPLETED_ICON = "/modules/game_taskboard/images/checkmark-icon"

local function setKillSlotCreature(panel, raceData)
	local outfitIcon = panel:getChildById("outfitIcon")

	if not outfitIcon then
		return
	end

	if weeklyRaceHasOutfit(raceData) then
		outfitIcon:setOutfit(raceData.outfit)
		if outfitIcon.setFixedCreatureSize then
			outfitIcon:setFixedCreatureSize(true)
		end
		outfitIcon:setVisible(true)

		local c = outfitIcon:getCreature()

		if c then
			c:setStaticWalking(1000)
		end
	else
		outfitIcon:setVisible(true)
		outfitIcon:setImageSource("/modules/game_taskboard/images/icon-arbitrarymonster64x64")
		outfitIcon:setImageSize({
			width = 66,
			height = 66
		})
	end
end

local function isWeeklyKillTaskCompleted(current, target, taskState)
	if (tonumber(taskState) or 0) ~= 0 then
		return true
	end

	local curN = tonumber(current) or 0
	local tgtN = tonumber(target) or 0

	return tgtN > 0 and curN >= tgtN
end

local function fillKillSlot(panel, name, current, target, raceData, taskState)
	if not panel then
		return
	end

	local displayName = capitalizeWords(name or "")

	if #displayName > 17 then
		displayName = displayName:sub(1, 17) .. "..."
	end

	panel:setText(displayName)
	setKillSlotCreature(panel, raceData)

	local curN = tonumber(current) or 0
	local tgtN = tonumber(target) or 0
	local isCompleted = isWeeklyKillTaskCompleted(current, target, taskState)

	local currentLabel = panel:getChildById("killAnyMonstersLabel")
	local ofLabel = panel:getChildById("ofKillLabel")
	local totalLabel = panel:getChildById("totalKillAnyMonstersLabel")
	local completedIcon = panel:getChildById("killCompletedIcon")

	if currentLabel then
		currentLabel:setVisible(not isCompleted)
		currentLabel:setText(TaskBoard:formatNumberWithCommas(current or 0))

		if isCompleted or (tgtN > 0 and curN >= tgtN) then
			currentLabel:setColor("#44cc44")
		else
			currentLabel:setColor("#d33c3c")
		end
	end

	if ofLabel then
		ofLabel:setVisible(not isCompleted)
	end

	if totalLabel then
		totalLabel:setVisible(not isCompleted)
		totalLabel:setText(TaskBoard:formatNumberWithCommas(target or 0))

		if isCompleted or (tgtN > 0 and curN >= tgtN) then
			totalLabel:setColor("#44cc44")
		end
	end

	if completedIcon then
		completedIcon:setImageSource(WEEKLY_TASK_COMPLETED_ICON)
		completedIcon:setVisible(isCompleted)
		if isCompleted and completedIcon.raise then
			completedIcon:raise()
		end
	end
end

local function weeklyDeliveryPreviewItemId(entry)
	local clientId = tonumber(entry.taskClientId or entry.clientId) or 0
	local serverId = tonumber(entry.taskItemId) or 0
	if clientId > 0 then
		return clientId, serverId
	end
	return serverId, serverId
end

local function weeklyDeliveryItemName(entry)
	local previewItemId, serverItemId = weeklyDeliveryPreviewItemId(entry)
	local name = getItemServerName(serverItemId)
	if name == "" then
		name = getItemServerName(previewItemId)
	end
	return name
end

local deliveryNameCatalogRefreshEvent = nil
local deliveryInventoryRefreshEvent = nil
local weeklyKillProgressRefreshEvent = nil
local deliveryServerSyncEvent = nil
local fillDeliverySlot

local function deliveryEntryTracksItemId(entry, itemId)
	if not itemId then
		return false
	end

	local clientId, serverId = weeklyDeliveryPreviewItemId(entry)
	return itemId == clientId or (serverId > 0 and itemId == serverId)
end

local function isDeliveryEntryCompleted(entry)
	if not entry then
		return false
	end

	if (tonumber(entry.completed) or 0) ~= 0 then
		return true
	end

	return (tonumber(entry.state) or 0) ~= 0
end

local function buildOpenContainerItemCounts()
	local counts = {}
	for _, container in pairs(g_game.getContainers()) do
		for _, item in pairs(container:getItems()) do
			if item then
				local id = item:getId()
				if id and id > 0 then
					counts[id] = (counts[id] or 0) + (item:getCount() or 1)
				end
			end
		end
	end
	return counts
end

local function countDeliveryItemFromSnapshot(itemCounts, itemId, alternateItemId)
	itemId = tonumber(itemId) or 0
	alternateItemId = tonumber(alternateItemId) or 0

	local count = 0
	if itemId > 0 then
		count = count + (itemCounts[itemId] or 0)
	end
	if alternateItemId > 0 and alternateItemId ~= itemId then
		count = count + (itemCounts[alternateItemId] or 0)
	end
	return count
end

local function countDeliveryItemInOpenContainers(itemId, alternateItemId)
	if not itemId or itemId <= 0 then
		return 0
	end

	return countDeliveryItemFromSnapshot(buildOpenContainerItemCounts(), itemId, alternateItemId)
end

local function deliveryEntryDisplayCount(entry, itemCounts)
	if not entry or isDeliveryEntryCompleted(entry) then
		return tonumber(entry.count) or 0
	end

	local totalItems = tonumber(entry.totalItems) or 0
	if totalItems <= 0 then
		return tonumber(entry.count) or 0
	end

	local clientItemId, serverItemId = weeklyDeliveryPreviewItemId(entry)
	if clientItemId <= 0 and serverItemId <= 0 then
		return tonumber(entry.count) or 0
	end

	local clientCount = itemCounts
		and countDeliveryItemFromSnapshot(itemCounts, clientItemId, serverItemId)
		or countDeliveryItemInOpenContainers(clientItemId, serverItemId)
	local serverAvailable = tonumber(entry.available)
	local available = clientCount

	if serverAvailable ~= nil then
		available = math.max(clientCount, serverAvailable)
	end

	return math.min(available, totalItems)
end

local function syncDeliveryCountsFromInventory(itemCounts)
	if not lastWeeklyTasksState or not lastWeeklyTasksState.deliveryEntries then
		return false
	end

	itemCounts = itemCounts or buildOpenContainerItemCounts()
	local changed = false
	for _, entry in ipairs(lastWeeklyTasksState.deliveryEntries) do
		if isDeliveryEntryCompleted(entry) then
			goto continue_delivery_sync
		end

		local clientItemId, serverItemId = weeklyDeliveryPreviewItemId(entry)
		local clientCount = countDeliveryItemFromSnapshot(itemCounts, clientItemId, serverItemId)
		local serverAvailable = tonumber(entry.available) or 0

		if clientCount > serverAvailable then
			entry.available = clientCount
			serverAvailable = clientCount
		end

		local newCount = math.min(math.max(clientCount, serverAvailable), tonumber(entry.totalItems) or 0)
		local oldCount = tonumber(entry.count) or 0
		if newCount ~= oldCount then
			entry.count = newCount
			changed = true
		end

		::continue_delivery_sync::
	end

	return changed
end

local function refreshDeliverySlotsFromState(itemCounts)
	local deliverySlotsList = getDeliverySlotsList()
	if not deliverySlotsList or not lastWeeklyTasksState then
		return
	end

	itemCounts = itemCounts or buildOpenContainerItemCounts()
	local children = deliverySlotsList:getChildren()
	local entries = lastWeeklyTasksState.deliveryEntries or {}
	for index, panel in ipairs(children) do
		fillDeliverySlot(panel, entries[index], itemCounts)
	end
end

local function scheduleDeliveryInventoryRefresh()
	if deliveryInventoryRefreshEvent then
		return
	end

	deliveryInventoryRefreshEvent = scheduleEvent(function()
		deliveryInventoryRefreshEvent = nil
		local itemCounts = buildOpenContainerItemCounts()
		syncDeliveryCountsFromInventory(itemCounts)
		refreshDeliverySlotsFromState(itemCounts)
	end, 0)
end

local function cancelDeliveryInventoryRefresh()
	if deliveryInventoryRefreshEvent then
		removeEvent(deliveryInventoryRefreshEvent)
		deliveryInventoryRefreshEvent = nil
	end
end

local function cancelDeliveryServerSync()
	if deliveryServerSyncEvent then
		removeEvent(deliveryServerSyncEvent)
		deliveryServerSyncEvent = nil
	end
end

local function scheduleWeeklyDeliveryServerSync()
	if deliveryServerSyncEvent or not g_game.requestWeeklyTaskData then
		return
	end

	deliveryServerSyncEvent = scheduleEvent(function()
		deliveryServerSyncEvent = nil
		if g_game.isOnline() and lastWeeklyTasksState then
			g_game.requestWeeklyTaskData()
		end
	end, 350)
end

local function tryScheduleDeliveryRefreshForItems(item, oldItem)
	if not lastWeeklyTasksState then
		return
	end

	local trackedIds = {}
	if item and item.getId then
		trackedIds[#trackedIds + 1] = item:getId()
	end
	if oldItem and oldItem.getId then
		trackedIds[#trackedIds + 1] = oldItem:getId()
	end

	if #trackedIds == 0 then
		return
	end

	for _, entry in ipairs(lastWeeklyTasksState.deliveryEntries or {}) do
		if not isDeliveryEntryCompleted(entry) then
			for _, trackedId in ipairs(trackedIds) do
				if deliveryEntryTracksItemId(entry, trackedId) then
					scheduleDeliveryInventoryRefresh()
					scheduleWeeklyDeliveryServerSync()
					return
				end
			end
		end
	end
end

local function onWeeklyDeliveryInventoryChange(player, slot, item, oldItem)
	tryScheduleDeliveryRefreshForItems(item, oldItem)
end

local function onWeeklyDeliveryContainerItemChange(container, slot, item, oldItem)
	tryScheduleDeliveryRefreshForItems(item, oldItem)
end

local function onWeeklyDeliveryContainerOpen()
	if lastWeeklyTasksState then
		scheduleDeliveryInventoryRefresh()
	end
end

local function cancelDeliveryNameCatalogRefresh()
	if deliveryNameCatalogRefreshEvent then
		removeEvent(deliveryNameCatalogRefreshEvent)
		deliveryNameCatalogRefreshEvent = nil
	end
end

local function scheduleDeliverySlotsRefreshAfterCatalog()
	if deliveryNameCatalogRefreshEvent then
		return
	end
	deliveryNameCatalogRefreshEvent = scheduleEvent(function()
		deliveryNameCatalogRefreshEvent = nil
		if lastWeeklyTasksState then
			buildDeliverySlots(lastWeeklyTasksState)
		end
	end, 700)
end

local function ensureDeliveryItemNameCatalog()
	if not modules.game_market or not modules.game_market.requestMarketItemsForCyclopedia then
		return
	end
	if modules.game_market.getCachedCustomMarketItems and modules.game_market.getCachedCustomMarketItems() then
		return
	end
	local ready = modules.game_market.requestMarketItemsForCyclopedia(true)
	if not ready then
		scheduleDeliverySlotsRefreshAfterCatalog()
	end
end

fillDeliverySlot = function(panel, entry, itemCounts)
	if not panel or not entry then
		return
	end

	local previewItemId = weeklyDeliveryPreviewItemId(entry)
	local itemIcon = panel:getChildById("itemIcon")

	if itemIcon and previewItemId > 0 then
		itemIcon:setItemId(previewItemId)
	end

	local itemName = short_text(weeklyDeliveryItemName(entry), 20)
	panel:setText(itemName)

	if itemIcon and itemName ~= "" then
		itemIcon:setTooltip(itemName)
	end

	local currentLabel = panel:getChildById("currentDeliveryLabel")
	local ofLabel = panel:getChildById("ofDeliveryLabel")
	local totalLabel = panel:getChildById("totalDeliveryLabel")

	local totalItems = tonumber(entry.totalItems) or 0
	local isCompleted = isDeliveryEntryCompleted(entry)
	local deliveredCount = isCompleted and (tonumber(entry.count) or 0) or deliveryEntryDisplayCount(entry, itemCounts)

	if isCompleted and totalItems > 0 then
		deliveredCount = totalItems
	end

	local hasRequiredAmount = totalItems > 0 and deliveredCount >= totalItems

	if currentLabel then
		currentLabel:setVisible(not isCompleted)
		currentLabel:setText(TaskBoard:formatNumberWithCommas(deliveredCount))

		if isCompleted or hasRequiredAmount then
			currentLabel:setColor("#44ad25")
		else
			currentLabel:setColor("#d33c3c")
		end
	end

	if ofLabel then
		ofLabel:setVisible(not isCompleted)
	end

	if totalLabel then
		totalLabel:setVisible(not isCompleted)
		totalLabel:setText(TaskBoard:formatNumberWithCommas(totalItems))
		if isCompleted or hasRequiredAmount then
			totalLabel:setColor("#44ad25")
		else
			totalLabel:setColor("#c0c0c0")
		end
	end

	local completedIcon = panel:getChildById("deliveryCompletedIcon")

	if completedIcon then
		completedIcon:setImageSource(WEEKLY_TASK_COMPLETED_ICON)
		completedIcon:setVisible(isCompleted)
		if isCompleted and completedIcon.raise then
			completedIcon:raise()
		end
	end

	local deliverButton = panel:getChildById("deliverButton")

	if deliverButton then
		local taskIndex = tonumber(entry.taskId) or 0
		local canDeliver = not isCompleted and totalItems > 0 and deliveredCount >= totalItems

		deliverButton:setVisible(not isCompleted)
		deliverButton:setEnabled(canDeliver)

		function deliverButton.onClick()
			if isDeliveryEntryCompleted(entry) then
				return
			end

			local liveCount = deliveryEntryDisplayCount(entry)
			if totalItems <= 0 or liveCount < totalItems then
				return
			end

			g_game.sendDeliveryTask(taskIndex)

			entry.completed = 1
			entry.state = 1
			entry.count = totalItems

			if lastWeeklyTasksState then
				lastWeeklyTasksState.delivery = (tonumber(lastWeeklyTasksState.delivery) or 0) + 1
				buildBarProgress(lastWeeklyTasksState)
			end

			refreshDeliverySlotsFromState()
		end
	end
end

local WEEKLY_KILL_TRACKER_MAX_SLOTS = 9
local WEEKLY_ANY_CREATURE_ICON = "/modules/game_taskboard/images/icon-arbitrarymonster"
local WEEKLY_CREATURETRACK_NO_CREATURE_IMG = "/images/game/prey/prey-noprey-small"
local WEEKLY_TRACKER_TOOLTIP_FOOTER = "Click in this window to open the Task Board dialog."

local function formatWeeklyTrackerProgressText(killed, total)
	killed = tonumber(killed) or 0
	total = tonumber(total) or 0

	if total <= 0 then
		return ""
	end

	return string.format("%s/%s", TaskBoard:formatNumberWithCommas(killed), TaskBoard:formatNumberWithCommas(total))
end

local function applyWeeklyTrackerCreatureStyle(creatureWidget)
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

local function buildWeeklyTrackerActiveTooltip(creatureName, killed, total)
	local header = string.format("Creature: %s\nAmount: %s / %s", creatureName, TaskBoard:formatNumberWithCommas(killed), TaskBoard:formatNumberWithCommas(total))

	return header .. "\n\n" .. tr(WEEKLY_TRACKER_TOOLTIP_FOOTER)
end

local function refreshBountyKillTrackerIfAvailable()
	local bounty = modules.game_taskboard and modules.game_taskboard.TaskBoard and modules.game_taskboard.TaskBoard.BountyTask

	if bounty and bounty.refreshKillTracker then
		bounty.refreshKillTracker()
	end
end

local function getWeeklyTrackerSlot(slotIndex)
	local prey = modules.game_prey

	if not prey or not prey.preyTracker or prey.preyTracker:isDestroyed() then
		return nil
	end

	local contents = prey.preyTracker.contentsPanel

	if not contents then
		return nil
	end

	return contents:getChildById("wslot" .. slotIndex)
end

local function setWeeklyKillTrackerUnused(slotIndex)
	local slot = getWeeklyTrackerSlot(slotIndex)

	if not slot then
		return
	end

	slot:setVisible(false)

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")
	local progressLabel = slot:getChildById("weeklyKillProgress")

	if creature then
		creature:setVisible(false)
	end

	if noCreature then
		noCreature:setImageSource(WEEKLY_CREATURETRACK_NO_CREATURE_IMG)
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

	slot:setTooltip("")
end

local function setWeeklyTrackerSelected(slotIndex, raceId, monstersKilled, totalKills, isAnyCreature, killEntry)
	local slot = getWeeklyTrackerSlot(slotIndex)

	if not slot then
		return
	end

	slot:setVisible(true)

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")
	local progressLabel = slot:getChildById("weeklyKillProgress")
	local creatureName = "?"

	if isAnyCreature then
		creatureName = tr("Any Creature")

		if creature then
			creature:setVisible(false)
		end

		if noCreature then
			noCreature:setImageSource(WEEKLY_ANY_CREATURE_ICON)
			noCreature:setImageSize({
				width = 32,
				height = 26
			})
			noCreature:setCenter(true)
			noCreature:setVisible(true)
		end
	else
		local raceData
		raceData, creatureName = resolveWeeklyKillDisplay(killEntry, raceId)

		if creature then
			if weeklyRaceHasOutfit(raceData) then
				creature:setOutfit(raceData.outfit)
				applyWeeklyTrackerCreatureStyle(creature)
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
			noCreature:setImageSource(WEEKLY_CREATURETRACK_NO_CREATURE_IMG)
			noCreature:setVisible(not weeklyRaceHasOutfit(raceData))
		end
	end

	if nameLabel then
		if isAnyCreature then
			nameLabel:setText(capitalizeWords(creatureName))
		elseif modules.game_prey and modules.game_prey.formatKillTrackerCreatureName then
			nameLabel:setText(modules.game_prey.formatKillTrackerCreatureName(creatureName))
		else
			nameLabel:setText(capitalizeWords(creatureName))
		end
	end

	local killed = tonumber(monstersKilled) or 0
	local total = tonumber(totalKills) or 0

	if progressLabel then
		progressLabel:setText(formatWeeklyTrackerProgressText(killed, total))
	end

	if timeBar then
		local percent = 0

		if total > 0 then
			percent = math.min(100, math.floor(killed / total * 100))
		end

		timeBar:setPercent(percent)
	end

	slot:setTooltip(buildWeeklyTrackerActiveTooltip(capitalizeWords(creatureName), killed, total))
end

local function layoutWeeklyKillTrackerSlots(usedCount)
	for i = 1, WEEKLY_KILL_TRACKER_MAX_SLOTS do
		if usedCount < i then
			setWeeklyKillTrackerUnused(i)
		end
	end
end

local function buildKillSlots(weeklyTasks)
	local killSlotsList = getKillSlotsList()

	if not killSlotsList then
		return
	end

	local killEntries = weeklyTasks.killEntries or {}

	killSlotsList:destroyChildren()

	local ok, anyPanel = pcall(g_ui.createWidget, "KillSlots", killSlotsList)

	if not ok then
		g_logger.error("[WeeklyTask] error creating KillSlots (Any Creature): " .. tostring(anyPanel))

		return
	end

	fillKillSlot(anyPanel, "Any Creature", weeklyTasks.killedsAnyMonsters, weeklyTasks.killsAnyMonsters, nil)
	setWeeklyTrackerSelected(1, nil, weeklyTasks.killedsAnyMonsters, weeklyTasks.killsAnyMonsters, true)

	local unlockKillButton = killSlotsList:getParent():getChildById("unlockKillButton")

	syncWeeklyUnlockButton(unlockKillButton, #killEntries <= 5, killSlotsList)

	local maxSpeciesSlots = WEEKLY_KILL_TRACKER_MAX_SLOTS - 1

	for slotIndex, entry in ipairs(killEntries) do
		local ok2, panel = pcall(g_ui.createWidget, "KillSlots", killSlotsList)

		if not ok2 then
			g_logger.error("[WeeklyTask] error creating KillSlots: " .. tostring(panel))

			break
		end

		local raceData = weeklyRaceDisplayFromEntry(entry)
		local raceName = raceData and raceData.name or entry.creatureName or "?"

		fillKillSlot(panel, raceName, entry.totalMonsterKilleds, entry.totalKills, raceData, entry.state)

		if slotIndex <= maxSpeciesSlots then
			setWeeklyTrackerSelected(slotIndex + 1, entry.raceId, entry.totalMonsterKilleds, entry.totalKills, false, entry)
		end
	end

	local usedTrackerSlots = math.min(1 + #killEntries, WEEKLY_KILL_TRACKER_MAX_SLOTS)

	layoutWeeklyKillTrackerSlots(usedTrackerSlots)
	killSlotsList:updateLayout()

	if modules.game_prey and modules.game_prey.updateTrackerHeight then
		modules.game_prey.updateTrackerHeight()
	end

	refreshBountyKillTrackerIfAvailable()
end

local function applyWeeklyKillEntryToState(entry)
	if not lastWeeklyTasksState then
		return false
	end

	local rid = tonumber(entry.raceId) or 0

	if rid == 0 then
		lastWeeklyTasksState.killedsAnyMonsters = entry.totalMonsterKilleds

		if entry.totalKills then
			lastWeeklyTasksState.killsAnyMonsters = entry.totalKills
		end

		return true
	end

	for _, e in ipairs(lastWeeklyTasksState.killEntries or {}) do
		if e.raceId == rid then
			e.totalMonsterKilleds = entry.totalMonsterKilleds
			e.totalKills = entry.totalKills
			e.state = entry.state

			return true
		end
	end

	lastWeeklyTasksState.killEntries = lastWeeklyTasksState.killEntries or {}
	lastWeeklyTasksState.killEntries[#lastWeeklyTasksState.killEntries + 1] = {
		raceId = rid,
		totalMonsterKilleds = entry.totalMonsterKilleds,
		totalKills = entry.totalKills,
		state = entry.state,
	}

	return true
end

local function refreshWeeklyKillProgressFromState()
	if not lastWeeklyTasksState then
		return
	end

	local weeklyTasks = lastWeeklyTasksState
	local killSlotsList = getKillSlotsList()

	if not killSlotsList then
		return
	end

	local children = killSlotsList:getChildren()

	if #children == 0 then
		onWeeklyTasks(weeklyTasks)

		return
	end

	local anyPanel = children[1]

	if anyPanel then
		fillKillSlot(anyPanel, "Any Creature", weeklyTasks.killedsAnyMonsters, weeklyTasks.killsAnyMonsters, nil)
	end

	setWeeklyTrackerSelected(1, nil, weeklyTasks.killedsAnyMonsters, weeklyTasks.killsAnyMonsters, true)

	local killEntries = weeklyTasks.killEntries or {}
	local maxSpeciesSlots = WEEKLY_KILL_TRACKER_MAX_SLOTS - 1

	for slotIndex, entry in ipairs(killEntries) do
		local panel = children[slotIndex + 1]

		if panel then
			local raceData = weeklyRaceDisplayFromEntry(entry)
			local raceName = raceData and raceData.name or entry.creatureName or "?"

			fillKillSlot(panel, raceName, entry.totalMonsterKilleds, entry.totalKills, raceData, entry.state)
		end

		if slotIndex <= maxSpeciesSlots then
			setWeeklyTrackerSelected(slotIndex + 1, entry.raceId, entry.totalMonsterKilleds, entry.totalKills, false, entry)
		end
	end

	local usedTrackerSlots = math.min(1 + #killEntries, WEEKLY_KILL_TRACKER_MAX_SLOTS)

	layoutWeeklyKillTrackerSlots(usedTrackerSlots)
	killSlotsList:updateLayout()

	if modules.game_prey and modules.game_prey.updateTrackerHeight then
		modules.game_prey.updateTrackerHeight()
	end

	refreshBountyKillTrackerIfAvailable()
	buildBarProgress(weeklyTasks)
end

local function scheduleWeeklyKillProgressRefresh()
	if weeklyKillProgressRefreshEvent then
		removeEvent(weeklyKillProgressRefreshEvent)
	end

	weeklyKillProgressRefreshEvent = scheduleEvent(function()
		weeklyKillProgressRefreshEvent = nil
		refreshWeeklyKillProgressFromState()
	end, 0)
end

local function cancelWeeklyKillProgressRefresh()
	if weeklyKillProgressRefreshEvent then
		removeEvent(weeklyKillProgressRefreshEvent)
		weeklyKillProgressRefreshEvent = nil
	end
end

local function buildDeliverySlots(weeklyTasks)
	local deliverySlotsList = getDeliverySlotsList()

	if not deliverySlotsList then
		return
	end

	ensureDeliveryItemNameCatalog()

	deliverySlotsList:destroyChildren()

	local unlockDeliveryButton = deliverySlotsList:getParent():getChildById("unlockDeliveryButton")
	local deliveryCount = weeklyTasks.deliveryEntries and #weeklyTasks.deliveryEntries or 0

	syncWeeklyUnlockButton(unlockDeliveryButton, deliveryCount <= 6, deliverySlotsList)

	if weeklyTasks.deliveryEntries then
		local itemCounts = buildOpenContainerItemCounts()
		for _, entry in ipairs(weeklyTasks.deliveryEntries) do
			local ok, panel = pcall(g_ui.createWidget, "DeliverySlots", deliverySlotsList)

			if not ok then
				g_logger.error("[WeeklyTask] error creating DeliverySlots: " .. tostring(panel))

				break
			end

			fillDeliverySlot(panel, entry, itemCounts)
		end
	end

	deliverySlotsList:updateLayout()
end

local PROGRESS_BAR_INNER_WIDTH = 577
local PROGRESS_BAR_TOTAL_TASKS = 18
local PROGRESS_BAR_FILL_IMAGE = "/images/bars/progressbar-green-large"
local STORE_WEEKLY_OFFER_NAME = "Permanent Weekly Task Expansion"
local STORE_WEEKLY_KILL_BOOST = "Weekly Double Kill Boost (1H)"
local STORE_WEEKLY_REDUCE_ITEMS = "Reduced Weekly Bounty Items"

local function openWeeklyTaskStoreOffer()
	if TaskBoard and TaskBoard.openTaskHuntStoreSearch then
		TaskBoard.openTaskHuntStoreSearch(STORE_WEEKLY_OFFER_NAME)
	end
end

local function wireTaskBoardStoreButton(button, offerName)
	if not button or button._taskBoardStoreBound then
		return
	end

	button._taskBoardStoreBound = true
	button:setTooltip(tr("Open Store: %s", offerName))

	function button.onClick()
		if TaskBoard and TaskBoard.openTaskHuntStoreSearch then
			TaskBoard.openTaskHuntStoreSearch(offerName)
		end
	end
end

local function wireUnlockButton(button)
	if not button then
		return
	end

	button:setTooltip(tr("Open Store: %s", STORE_WEEKLY_OFFER_NAME))

	function button.onClick()
		openWeeklyTaskStoreOffer()
	end
end

local DIFFICULTY_BUTTON_TOOLTIPS = {
	[0] = tr("Beginner tasks include easy creatures."),
	[1] = tr("Adept tasks include easy and medium creatures. (Requires level 30)"),
	[2] = tr("Expert tasks include up to hard creatures. (Requires level 150)"),
	[3] = tr("Master tasks include the hardest creatures. (Requires level 400)")
}

local function wireDifficultyButton(button, difficulty)
	if not button then
		return
	end

	button:setTooltip(DIFFICULTY_BUTTON_TOOLTIPS[difficulty])

	function button.onClick()
		g_game.sendSelectDifficultyWeeklyTasks(difficulty)
	end
end

local function buildBarProgress(weeklyTasks)
	if not TaskBoard.weeklyPanel then
		return
	end

	local progressBar = TaskBoard.weeklyPanel:recursiveGetChildById("progressBar")

	if not progressBar then
		return
	end

	local totalKills = weeklyTasks.kill or 0
	local totalDeliveries = weeklyTasks.delivery or 0
	local total = math.max(0, math.min(totalKills + totalDeliveries, PROGRESS_BAR_TOTAL_TASKS))
	local fillWidth = math.floor(total / PROGRESS_BAR_TOTAL_TASKS * PROGRESS_BAR_INNER_WIDTH + 0.5)
	local fill = progressBar:getChildById("progressFill")

	if not fill then
		fill = g_ui.createWidget("UIWidget", progressBar)

		fill:setId("progressFill")
		fill:setPhantom(true)
		fill:setImageSource(PROGRESS_BAR_FILL_IMAGE)
		fill:setImageRepeated(true)
		fill:addAnchor(AnchorTop, "parent", AnchorTop)
		fill:addAnchor(AnchorLeft, "parent", AnchorLeft)
		fill:addAnchor(AnchorBottom, "parent", AnchorBottom)
		fill:setMarginTop(1)
		fill:setMarginBottom(1)
		fill:setMarginLeft(1)
	end

	fill:setVisible(fillWidth > 0)
	fill:setWidth(fillWidth)
	progressBar:setTooltip(tr("Weekly Progress: %d / %d tasks", total, PROGRESS_BAR_TOTAL_TASKS))
end

local function buildRewards(weeklyTasks)
	local huntingPoints = weeklyTasks.totalPoints or 0
	local soulSealsPoints = weeklyTasks.totalTasksCompleted or 0

	if TaskBoard.weeklyPanel then
		local huntingPointsLabel = TaskBoard.weeklyPanel:recursiveGetChildById("huntingPointsLabel")

		if huntingPointsLabel then
			huntingPointsLabel:setText(huntingPoints)
		end

		local soulSealsPointsLabel = TaskBoard.weeklyPanel:recursiveGetChildById("soulSealsPointsLabel")

		if soulSealsPointsLabel then
			soulSealsPointsLabel:setText(soulSealsPoints)
		end
	end

	local timeStamp = weeklyTasks.mondayTime or 0
	local daysRemainingLabel = TaskBoard.weeklyPanel and TaskBoard.weeklyPanel:recursiveGetChildById("daysRemaining")

	if daysRemainingLabel and timeStamp > 0 then
		local currentTime = os.time()
		local diffSeconds = timeStamp - currentTime
		local daysRemaining = math.floor(diffSeconds / 86400)

		if daysRemaining < 0 then
			daysRemaining = 0
		end

		daysRemainingLabel:setText(daysRemaining)
	end
end

function WeeklyTask:allowDifficultyWeeklyTasks(unlockedDifficulties)
	local panel = TaskBoard.weeklyProgressPanel

	if not panel then
		return
	end

	local unlocked = tonumber(unlockedDifficulties) or 0

	if unlocked < 0 then
		unlocked = 0
	elseif unlocked > 3 then
		unlocked = 3
	end

	local buttons = {
		{
			tier = 0,
			id = "beginnerButton"
		},
		{
			tier = 1,
			id = "adeptButton"
		},
		{
			tier = 2,
			id = "expertButton"
		},
		{
			tier = 3,
			id = "masterButton"
		}
	}

	for _, entry in ipairs(buttons) do
		local btn = panel:recursiveGetChildById(entry.id)

		if btn and btn.setEnabled then
			btn:setEnabled(unlocked >= entry.tier)
		end
	end

	if type(g_ui.updateHoveredWidget) == "function" then
		g_ui.updateHoveredWidget(true)
	end
end

function onWeeklyKillUpdate(entry)
	if type(entry) ~= "table" or entry.raceId == nil then
		return
	end

	if lastWeeklyTasksState then
		applyWeeklyKillEntryToState(entry)
		scheduleWeeklyKillProgressRefresh()

		return
	end

	if g_game.requestWeeklyTaskData then
		g_game.requestWeeklyTaskData()
	end
end

function onWeeklyTasks(weeklyTasks)
	if type(weeklyTasks) ~= "table" then
		return
	end

	lastWeeklyTasksState = copyWeeklyTasksState(weeklyTasks)
	syncDeliveryCountsFromInventory()

	buildKillSlots(lastWeeklyTasksState)
	buildDeliverySlots(lastWeeklyTasksState)
	buildBarProgress(lastWeeklyTasksState)
	buildRewards(lastWeeklyTasksState)
	buildWeeklyTaskRewardInfo(lastWeeklyTasksState)

	WeeklyTask.isWeeklyTaskActive = weeklyTasks.weeklyTaskActive == 1

	WeeklyTask:updateOverlayVisibility()
	WeeklyTask:allowDifficultyWeeklyTasks(weeklyTasks.unlockedDifficulties)
end

-- ADAPTER for our engine: onWeeklyTaskData passes THREE separate structures
-- (header, monsters, items) and uses different field names than the module. We assemble them into
-- the single table that onWeeklyTasks expects.
function onEngineWeeklyTaskData(header, monsters, items)
	header = header or {}

	local killEntries = {}
	local killsAnyMonsters = 0
	local killedsAnyMonsters = 0

	for _, m in ipairs(monsters or {}) do
		if m.raceId == 0 then
			-- the engine prepends a synthetic "any monsters" entry with raceId = 0
			killsAnyMonsters = m.total
			killedsAnyMonsters = m.current
		else
			killEntries[#killEntries + 1] = {
				raceId = m.raceId,
				creatureName = m.creatureName,
				outfit = m.outfit,
				totalMonsterKilleds = m.current,
				totalKills = m.total,
				state = m.state
			}
		end
	end

	local deliveryEntries = {}

	for _, it in ipairs(items or {}) do
		local claimed = tonumber(it.claimed) or 0
		local state = tonumber(it.state) or 0
		local completed = (claimed ~= 0 or state ~= 0) and 1 or 0

		deliveryEntries[#deliveryEntries + 1] = {
			taskId = it.slotIndex,
			taskItemId = it.itemId,
			taskClientId = it.clientId,
			count = it.current,
			totalItems = it.total,
			available = it.available,
			completed = completed,
			state = state ~= 0 and state or completed
		}
	end

	local ok, err = pcall(onWeeklyTasks, {
		killEntries = killEntries,
		deliveryEntries = deliveryEntries,
		killsAnyMonsters = killsAnyMonsters,
		killedsAnyMonsters = killedsAnyMonsters,
		kill = header.completedKillTasks,
		delivery = header.completedDeliveryTasks,
		totalPoints = header.pointsEarned,
		totalTasksCompleted = header.soulsealsEarned,
		killTaskRewardExp = header.killTaskRewardExp,
		deliveryTaskRewardExp = header.deliveryTaskRewardExp,
		mondayTime = header.resetTimestamp,
		weeklyTaskActive = header.weeklyProgressFinished,
		-- the engine reports 1-4, the module counts 0-3
		unlockedDifficulties = math.max(0, (header.unlockedDifficulty or 1) - 1)
	})
	if not ok then
		g_logger.error("[WeeklyTask] onWeeklyTasks failed: " .. tostring(err))
	end

	if TaskBoard and TaskBoard.setWeeklyBoostRemaining then
		TaskBoard.setWeeklyBoostRemaining(header.weeklyKillBoostRemaining, header.weeklyReducedItemsRemaining)
	end
end

function WeeklyTask:init()
	connect(g_game, {
		onWeeklyKillUpdate = onWeeklyKillUpdate,
		onWeeklyTaskData = onEngineWeeklyTaskData
	})

	connect(LocalPlayer, {
		onInventoryChange = onWeeklyDeliveryInventoryChange
	})

	connect(Container, {
		onOpen = onWeeklyDeliveryContainerOpen,
		onAddItem = onWeeklyDeliveryContainerItemChange,
		onRemoveItem = onWeeklyDeliveryContainerItemChange,
		onUpdateItem = onWeeklyDeliveryContainerItemChange
	})

	if TaskBoard.weeklyPanel then
		wireUnlockButton(TaskBoard.weeklyPanel:recursiveGetChildById("unlockKillButton"))
		wireUnlockButton(TaskBoard.weeklyPanel:recursiveGetChildById("unlockDeliveryButton"))
		wireTaskBoardStoreButton(TaskBoard.weeklyPanel:recursiveGetChildById("boostKillsWeekly"), STORE_WEEKLY_KILL_BOOST)
		wireTaskBoardStoreButton(TaskBoard.weeklyPanel:recursiveGetChildById("reduceItemsWeekly"), STORE_WEEKLY_REDUCE_ITEMS)
	end

	if TaskBoard.weeklyProgressPanel then
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("beginnerButton"), 0)
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("adeptButton"), 1)
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("expertButton"), 2)
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("masterButton"), 3)
	end
end

function WeeklyTask:terminate()
	disconnect(g_game, {
		onWeeklyKillUpdate = onWeeklyKillUpdate,
		onWeeklyTaskData = onEngineWeeklyTaskData
	})

	disconnect(LocalPlayer, {
		onInventoryChange = onWeeklyDeliveryInventoryChange
	})

	disconnect(Container, {
		onOpen = onWeeklyDeliveryContainerOpen,
		onAddItem = onWeeklyDeliveryContainerItemChange,
		onRemoveItem = onWeeklyDeliveryContainerItemChange,
		onUpdateItem = onWeeklyDeliveryContainerItemChange
	})

	cancelDeliveryInventoryRefresh()
	cancelDeliveryServerSync()
	cancelDeliveryNameCatalogRefresh()
	cancelWeeklyKillProgressRefresh()
	lastWeeklyTasksState = nil
end
