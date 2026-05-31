CyclopediaOpcode = {
	Info = 0x48,
	Category = 0x49,
	Monster = 0x4A,
	Charm = 0x4C,
	Tracker = 0x4D,
	Send = 0x48
}

protoData = protoData or {}

local BestiaryMessage = 0x00
local BestiaryData = 0x01 -- Main page
local BestiaryOverview = 0x02 -- Category data
local BestiaryMonsterData = 0x03 -- Monster info
local BestiaryTracker = 0x05
local BestiaryProgress = 0x06
local BESTIARY_SEARCH_PREFIX = "__search__:"
local bestiaryContainer
local bestiaryCSelecter = nil
local backCategoryButton = nil
local backPageButton = nil
local pageCountLabel = nil
local nextPageButton = nil

local currentCategoriesList = {}
local currentCategoryPage = 1
local currentMonsterListPage = 1
local currentMonstersList = {}

local charmAmountBestiary
local goldAmountBestiary
local selectedBestiaryRaceId = 0
local trackedCreatures = {}
local bestiaryProtocolRegistered = false
local bestiaryParsersRegistered = false
local bestiaryParsers = {}
local bestiaryTrackerWindow = nil
local bestiaryTrackerButton = nil
local ensureBestiaryTrackerWindow
local trackerEntries = {}
local trackerSortType = g_settings.get('bestiary-tracker-sort-type') or 'percentage'
local trackerSortOrder = g_settings.get('bestiary-tracker-sort-order') or 'asc'
local bestiarySearchInput = nil
local bestiarySearchButton = nil
local bestiarySearchEvent = nil
local currentBestiaryCategory = nil
local currentBestiaryRows = {}
local currentBestiaryEntries = {}
local bestiaryTrackerRefreshEvent = nil
local bestiaryMonsterRefreshEvent = nil
local syncingTrackKillsCheckbox = false
local selectedBestiaryCharmSlot = 1
local scheduleBestiaryMonsterRefresh
local stopBestiaryMonsterRefresh
local bestiaryCategoryImages = {
	["Amphibic"] = 1,
	["Aquatic"] = 2,
	["Bird"] = 3,
	["Construct"] = 4,
	["Demon"] = 5,
	["Dragon"] = 6,
	["Elemental"] = 7,
	["Extra Dimensional"] = 8,
	["Fey"] = 9,
	["Giant"] = 10,
	["Human"] = 11,
	["Humanoid"] = 12,
	["Lycanthrope"] = 13,
	["Magical"] = 14,
	["Mammal"] = 15,
	["Plant"] = 16,
	["Reptile"] = 17,
	["Slime"] = 18,
	["Undead"] = 19,
	["Vermin"] = 20,
	["Inkborn"] = 4
}
starsLevels = {
	[1] = "Difficulty: Trivial",
	[2] = "Difficulty: Easy",
	[3] = "Difficulty: Medium",
	[4] = "Difficulty: Hard",
	[5] = "Difficulty: Challenging",
}

occurenceLevels = {
	[1] = "Occurrence: Common",
	[2] = "Occurrence: Uncommon",
	[3] = "Occurrence: Rare",
	[4] = "Occurrence: Very Rare",
}

lootRarityLevel = {
	[0] = "Common:",
	[1] = "Uncommon:",
	[2] = "Semi-Rare:",
	[3] = "Rare:",
	[4] = "Very Rare:"
}

local function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

local function trimText(text)
	return tostring(text or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function formatLocations(locations)
	local formattedLocations = {}
	for _, location in ipairs(locations) do
		location = trimText(location)
		if location ~= "" then
			formattedLocations[#formattedLocations + 1] = location
		end
	end
	if #formattedLocations == 0 then
		return "?"
	end
	return table.concat(formattedLocations, "\n")
end

local function isBestiaryView()
	return modules.game_cyclopedia and modules.game_cyclopedia.getCurrentType and modules.game_cyclopedia.getCurrentType() == "bestiary"
end

local function setTrackKillsCheckedFromServer(checked)
	if not bestiaryMonster or not bestiaryMonster.trackKills then
		return
	end

	if bestiaryMonster.trackKills:isChecked() == checked then
		return
	end

	syncingTrackKillsCheckbox = true
	bestiaryMonster.trackKills:setChecked(checked)
	syncingTrackKillsCheckbox = false
end

function readCyclopediaCreatureOutfit(msg)
	local name = msg:getString()
	return {
		name = name,
		type = msg:getU16(),
		head = msg:getU8(),
		body = msg:getU8(),
		legs = msg:getU8(),
		feet = msg:getU8(),
		addons = msg:getU8()
	}
end

local function readBestiaryOverviewEntry(msg)
	local raceId = msg:getU16()
	local progressMarker = msg:getU8()
	local entry = {
		raceId = raceId,
		progress = math.max((progressMarker or 0) - 1, 0)
	}

	if progressMarker > 0 then
		entry.progress = msg:getU8()
		entry.outfit = readCyclopediaCreatureOutfit(msg)
		protoData[raceId] = entry.outfit
	end
	return entry
end

local function applyBestiaryCategoryRow(row, entry)
	if not row or not entry then
		return
	end

	row.raceId = entry.raceId
	row.progress = entry.progress or 0
	local bestContainer = row.bestiaryContainer
	if not bestContainer then
		return
	end

	if row.progress > 0 then
		local raceOutfit = entry.outfit
		if raceOutfit then
			bestContainer.creature:setOutfit(raceOutfit)
		end
		bestContainer.hideCreature:hide()
		row:setText(firstToUpper(raceOutfit and raceOutfit.name or "unknown"))

		if row.progress >= 4 then
			row.creatureProgressCheck:show()
			row.creatureProgress:setText("")
		else
			row.creatureProgressCheck:hide()
			row.creatureProgress:setText(math.min(row.progress, 3) .. " / 3")
		end

		bestContainer.creature.onClick = function()
			requestBestiaryMonsterData(entry.raceId)
		end
	else
		bestContainer.hideCreature:show()
		row:setText("Unknown")
		row.creatureProgressCheck:hide()
		row.creatureProgress:setText("?")
		bestContainer.creature.onClick = nil
	end
end

local function openBestiaryMonsterFromTracker(raceId)
	if not raceId or raceId <= 0 then
		return false
	end

	if modules.game_cyclopedia and modules.game_cyclopedia.show then
		modules.game_cyclopedia.show("bestiary")
	end

	requestBestiaryMonsterData(raceId)
	return true
end

local function bindBestiaryTrackerEntryClick(widget, raceId)
	if not widget then
		return
	end

	widget.onMouseRelease = function(self, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton then
			return false
		end

		return openBestiaryMonsterFromTracker(raceId)
	end
end

local function refreshBestiaryCharmDataSoon()
	if requestBestiaryCharmRefresh then
		requestBestiaryCharmRefresh()
	end

	local refreshCurrentMonster = function()
		if selectedBestiaryRaceId > 0 and isBestiaryView() and bestiaryMonster and bestiaryMonster:isVisible() then
			requestBestiaryMonsterData(selectedBestiaryRaceId)
		end
	end

	scheduleEvent(refreshCurrentMonster, 250)
	scheduleEvent(refreshCurrentMonster, 800)
end

local function confirmBestiaryCharmAction(message, callback)
	local confirmWindow
	local yesCallback = function()
		confirmWindow:ok()
		callback()
	end
	local noCallback = function()
		confirmWindow:cancel()
	end

	confirmWindow = displayGeneralBox(tr('Cyclopedia'), message, {
		{text = tr('Yes'), callback = yesCallback},
		{text = tr('No'), callback = noCallback}
	}, yesCallback, noCallback)
end

local function clearBestiaryCharmSlot(slot)
	if not slot then
		return
	end

	slot.charm = nil
	slot:setOpacity(0.5)
	slot:setTooltip("")
	slot.onMouseRelease = nil
	slot:setBorderColor('#161616')
	slot:setBorderWidth(1)
	if slot.charmRune then
		slot.charmRune:hide()
	end
end

local function updateBestiaryCharmSlotSelection()
	if not bestiaryMonster then
		return
	end

	local slots = {bestiaryMonster.charmSlot1, bestiaryMonster.charmSlot2}
	for index, slot in ipairs(slots) do
		if slot then
			if index == selectedBestiaryCharmSlot then
				slot:setBorderColor('white')
				slot:setBorderWidth(2)
			else
				slot:setBorderColor('#161616')
				slot:setBorderWidth(1)
			end
		end
	end
end

local function bindEmptyBestiaryCharmSlot(slot, index)
	if not slot or slot.charm then
		return
	end

	slot.onMouseRelease = function(self, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton then
			return false
		end

		selectedBestiaryCharmSlot = index
		updateBestiaryCharmSlotSelection()
		return true
	end
end

local function setBestiaryCharmSlot(slot, charm)
	if not slot then
		return
	end
	if not charm then
		clearBestiaryCharmSlot(slot)
		return
	end

	slot.charm = charm
	slot:setOpacity(1)
	slot:setTooltip(charm.name)
	slot:setBorderColor('#161616')
	slot:setBorderWidth(1)
	if slot.charmRune then
		slot.charmRune:setImageSource('/images/game/charms/' .. charm.id)
		slot.charmRune:show()
	end

	slot.onMouseRelease = function(self, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton or not self.charm or selectedBestiaryRaceId <= 0 then
			return false
		end

		selectedBestiaryCharmSlot = self == bestiaryMonster.charmSlot2 and 2 or 1
		updateBestiaryCharmSlotSelection()
		local raceId = selectedBestiaryRaceId
		local charmId = self.charm.id
		local message = tr('Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.', self.charm.name, self.charm.removeRuneCost or 0)
		confirmBestiaryCharmAction(message, function()
			if sendBestiaryCharmRemove then
				sendBestiaryCharmRemove(charmId, raceId)
				refreshBestiaryCharmDataSoon()
			end
		end)
		return true
	end
end

function updateBestiaryCharmSlots()
	if not isBestiaryView() or not bestiaryMonster then
		return
	end

	local assignedCharms = {}
	if getBestiaryAssignedCharms and selectedBestiaryRaceId > 0 then
		assignedCharms = getBestiaryAssignedCharms(selectedBestiaryRaceId)
	end

	setBestiaryCharmSlot(bestiaryMonster.charmSlot1, assignedCharms[1])
	setBestiaryCharmSlot(bestiaryMonster.charmSlot2, assignedCharms[2])
	if selectedBestiaryCharmSlot > 2 or (selectedBestiaryCharmSlot == 2 and not bestiaryMonster.charmSlot2) then
		selectedBestiaryCharmSlot = 1
	end
	updateBestiaryCharmSlotSelection()
	bindEmptyBestiaryCharmSlot(bestiaryMonster.charmSlot1, 1)
	bindEmptyBestiaryCharmSlot(bestiaryMonster.charmSlot2, 2)

	local assignButton = bestiaryMonster.assignCharmButton
	if not assignButton then
		return
	end

	local assignableCharms = getBestiaryAssignableCharms and getBestiaryAssignableCharms() or {}
	if #assignedCharms >= 2 or #assignableCharms == 0 then
		assignButton:disable()
		assignButton:setOpacity(0.5)
	else
		assignButton:enable()
		assignButton:setOpacity(1)
	end
end

local function showBestiaryAssignCharmMenu(mousePos)
	if selectedBestiaryRaceId <= 0 or not getBestiaryAssignableCharms then
		return
	end

	local assignableCharms = getBestiaryAssignableCharms()
	if #assignableCharms == 0 then
		displayInfoBox(tr('Cyclopedia'), tr('There are no available charms to assign.'))
		return
	end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)
	for _, charm in ipairs(assignableCharms) do
		menu:addOption(charm.name, function()
			local raceId = selectedBestiaryRaceId
			local message = tr('Do you want to use the Charm %s for this creature?', charm.name)
			confirmBestiaryCharmAction(message, function()
				if sendBestiaryCharmAssign then
					sendBestiaryCharmAssign(charm.id, raceId)
					refreshBestiaryCharmDataSoon()
				end
			end)
		end)
	end
	if not mousePos and bestiaryMonster and bestiaryMonster.assignCharmButton then
		mousePos = bestiaryMonster.assignCharmButton:getPosition()
	end
	menu:display(mousePos)
end

local function applyBestiaryProgressUpdate(entry)
	if not entry then
		return
	end

	if entry.outfit then
		protoData[entry.raceId] = entry.outfit
	end
	currentBestiaryEntries[entry.raceId] = entry

	for i = 1, #currentMonstersList do
		if currentMonstersList[i].raceId == entry.raceId then
			currentMonstersList[i] = entry
			break
		end
	end

	local row = currentBestiaryRows[entry.raceId]
	if row then
		applyBestiaryCategoryRow(row, entry)
	end

	if selectedBestiaryRaceId == entry.raceId and bestiaryMonster and bestiaryMonster:isVisible() then
		requestBestiaryMonsterData(entry.raceId)
	end
end

local function registerOpcode(code, func)
	bestiaryParsers[code] = func
end

local function dispatchBestiaryProtocol(protocol, msg)
	local response = msg:getU8()
	local parser = bestiaryParsers[response]
	if parser then
		parser(protocol, msg)
	end
end

function unregisterBestiaryProtocol()
	if not bestiaryProtocolRegistered then
		return
	end
	ProtocolGame.unregisterOpcode(CyclopediaOpcode.Send)
	bestiaryProtocolRegistered = false
end

function terminateBestiary()
	unregisterBestiaryProtocol()
	if bestiaryTrackerRefreshEvent then
		removeEvent(bestiaryTrackerRefreshEvent)
		bestiaryTrackerRefreshEvent = nil
	end
	if bestiaryMonsterRefreshEvent then
		removeEvent(bestiaryMonsterRefreshEvent)
		bestiaryMonsterRefreshEvent = nil
	end
	if bestiaryTrackerWindow then
		bestiaryTrackerWindow:destroy()
		bestiaryTrackerWindow = nil
	end
end

function onBestiaryGameEnd()
	stopBestiaryMonsterRefresh()
	if bestiaryTrackerRefreshEvent then
		removeEvent(bestiaryTrackerRefreshEvent)
		bestiaryTrackerRefreshEvent = nil
	end
	trackedCreatures = {}
	if bestiaryTrackerWindow then
		bestiaryTrackerWindow:hide()
		local contentsPanel = bestiaryTrackerWindow:recursiveGetChildById('contentsPanel')
		if contentsPanel then
			contentsPanel:destroyChildren()
		end
	end
end

function updatePagination(currentPage, totalPages, isCategoryList)
	if not bestiaryPanel then
		return
	end

	local isDetailView = bestiaryMonster and bestiaryMonster:isVisible()

	if pageCountLabel then
		if isDetailView then
			pageCountLabel:setText("")
		else
			pageCountLabel:setText(currentPage .. " / " .. totalPages)
		end
	end

	if backPageButton then
		backPageButton:setEnabled(not isDetailView and currentPage > 1)
	end

	if nextPageButton then
		nextPageButton:setEnabled(not isDetailView and currentPage < totalPages)
	end

	if backCategoryButton then
		backCategoryButton:setEnabled(isDetailView or not isCategoryList)
	end
end

function showCategoriesPage(page)
	if not isBestiaryView() or not bestiaryCSelecter then
		return
	end

	currentCategoryPage = page
	emptyBestiaryCategories()

	local itemsPerPage = 15
	local totalPages = math.max(1, math.ceil(#currentCategoriesList / itemsPerPage))
	currentCategoryPage = math.max(1, math.min(currentCategoryPage, totalPages))

	updatePagination(currentCategoryPage, totalPages, true)

	local startIndex = (currentCategoryPage - 1) * itemsPerPage + 1
	local endIndex = math.min(startIndex + itemsPerPage - 1, #currentCategoriesList)

	for i = startIndex, endIndex do
		local cat = currentCategoriesList[i]
		local row = g_ui.createWidget('BestiaryCategoryList', bestiaryCSelecter)
	
		row.index = i
		row:setId("bestiaryWidget"..i)
		row.categoryId = i
		row:setText(cat.name)
	
		local bestContainer = row.bestiaryContainer
		bestContainer.bestiaryImage:setImageSource('/images/game/bestiary/'..(bestiaryCategoryImages[cat.name] or i))
		local totalAmount = row.totalAmount
		totalAmount:setText("Total: "..cat.amount)
		local knownAmount = row.knownAmount
		knownAmount:setText("Known: "..cat.discovered)
	
		local bestiaryContainer = row.bestiaryContainer
		local bestiaryMonster = bestiaryContainer.bestiaryImage
		bestiaryMonster.onClick = function(self)
			requestBestiaryCategoryData(cat.name)
		end
	end
end

function showMonstersPage(page)
	if not isBestiaryView() or not bestiaryCSelecter then
		return
	end

	currentMonsterListPage = page
	emptyBestiaryCategories()

	local itemsPerPage = 15
	local totalPages = math.max(1, math.ceil(#currentMonstersList / itemsPerPage))
	currentMonsterListPage = math.max(1, math.min(currentMonsterListPage, totalPages))

	updatePagination(currentMonsterListPage, totalPages, false)

	local startIndex = (currentMonsterListPage - 1) * itemsPerPage + 1
	local endIndex = math.min(startIndex + itemsPerPage - 1, #currentMonstersList)

	for i = startIndex, endIndex do
		local entry = currentMonstersList[i]
		local row = g_ui.createWidget('BestiaryCategory', bestiaryCSelecter)
		row.index = i
		row:setId("BestiaryCategory"..i)
		currentBestiaryRows[entry.raceId] = row
		currentBestiaryEntries[entry.raceId] = entry
		applyBestiaryCategoryRow(row, entry)
	end
end

function registerBestiaryProtocol()
	if bestiaryParsersRegistered then
		if not bestiaryProtocolRegistered then
			ProtocolGame.unregisterOpcode(CyclopediaOpcode.Send)
			ProtocolGame.registerOpcode(CyclopediaOpcode.Send, dispatchBestiaryProtocol)
			bestiaryProtocolRegistered = true
		end
		return
	end
	bestiaryParsersRegistered = true

	registerOpcode(BestiaryData, function(protocol, msg)
		currentCategoriesList = {}
		currentCategoryPage = 1

		local categoryCount = msg:getU16()
		for i = 1, categoryCount do
			local categoryName, categoryAmount, discoveredAmount = msg:getString(), msg:getU16(), msg:getU16()
			table.insert(currentCategoriesList, {
				name = categoryName,
				amount = categoryAmount,
				discovered = discoveredAmount
			})
		end
		
		msg:skipBytes(1) -- Missing byte
		sendBestiaryCharmsData(msg)

		local bestiaryView = isBestiaryView()
		if bestiaryView and bestiaryCSelecter then
			currentBestiaryCategory = nil
			currentBestiaryRows = {}
			currentBestiaryEntries = {}
			showCategoriesPage(1)
		end
	end)
	
	registerOpcode(BestiaryOverview, function(protocol, msg)
		local raceName, raceSize = msg:getString(), msg:getU16()
		currentMonstersList = {}
		currentMonsterListPage = 1

		for i = 1, raceSize do
			currentMonstersList[i] = readBestiaryOverviewEntry(msg)
		end

		if not isBestiaryView() or not bestiaryCSelecter then
			return
		end

		currentBestiaryCategory = raceName
		currentBestiaryRows = {}
		currentBestiaryEntries = {}

		showMonstersPage(1)
	end)
	
	registerOpcode(BestiaryMonsterData, function(protocol, msg)
		if not isBestiaryView() or not bestiaryContainer or not bestiaryMonster then
			return
		end
		bestiaryContainer:hide()
		bestiaryMonster:show()
		updatePagination(currentMonsterListPage, math.max(1, math.ceil(#currentMonstersList / 15)), false)
		
		-- Start of the info
		local raceId, class = msg:getU16(), msg:getString()
		local raceOutfit = readCyclopediaCreatureOutfit(msg)
		protoData[raceId] = raceOutfit
		selectedBestiaryRaceId = raceId
		setTrackKillsCheckedFromServer(trackedCreatures[raceId] == true)
		updateBestiaryCharmSlots()
		bestiaryMonster:setText(firstToUpper(raceOutfit and raceOutfit.name or "unknown"))
		if raceOutfit then
			bestiaryMonster.bestiaryCreature:setOutfit(raceOutfit)
		end
		
		local currentLevel = msg:getU8()
		local killCounter = msg:getU32()
		local bestiaryFirstUnlock = msg:getU16()
		local bestiarySecondUnlock = msg:getU16()
		local bestiaryToUnlock = msg:getU16()
		
		local firstUnlock = math.max(bestiaryFirstUnlock, 1)
		local secondUnlock = math.max(bestiarySecondUnlock, firstUnlock)
		local toUnlock = math.max(bestiaryToUnlock, secondUnlock)
		local cappedKills = math.min(killCounter, toUnlock)
		local progressPercent
		if cappedKills < firstUnlock then
			progressPercent = (cappedKills * 33.33) / firstUnlock
		elseif cappedKills < secondUnlock then
			progressPercent = 33.33 + (((cappedKills - firstUnlock) * 33.33) / math.max(secondUnlock - firstUnlock, 1))
		else
			progressPercent = 66.66 + (((cappedKills - secondUnlock) * 33.34) / math.max(toUnlock - secondUnlock, 1))
		end
		
		bestiaryMonster.totalKillsLabel:setText(killCounter)
		bestiaryMonster.progressBar:setPercent(math.min(100, progressPercent))
		
		-- Bestiary Stars
		local bestiaryStars = msg:getU8()
		for s = 1, 5 do
			starsContainer:getChildById("stars"..s):setTooltip(starsLevels[bestiaryStars])
			
			if (s > bestiaryStars) then
				starsContainer:getChildById("stars"..s):setOn(false)
			else
				starsContainer:getChildById("stars"..s):setOn(true)
			end
		end
	
		-- Bestiary Occurence
		local bestiaryOccurrence = msg:getU8()
		for o = 1, 4 do
			occurrenceContainer:getChildById("occurrence"..o):setTooltip(occurenceLevels[bestiaryOccurrence])
			
			if (o > bestiaryOccurrence) then
				occurrenceContainer:getChildById("occurrence"..o):setOn(false)
			else
				occurrenceContainer:getChildById("occurrence"..o):setOn(true)
			end
		end
	
		local lootList = msg:getU8()
		local tierLoot = {}	
		for i = 1, lootList do
			local itemId = msg:getU16()
			local difficult = msg:getU8()
			local specialEvent = msg:getU8()
			local lootName = ""
			local countMax = 0
			
			if (currentLevel > 1) then
				lootName = msg:getString()
				countMax = msg:getU8()
			end

			table.insert(tierLoot, {
				itemId, difficult, lootName, countMax
			})
		end
		
		-- Loot Setup
		if lootContainer then
			lootContainer:destroyChildren()
		end
		for a = 0, 4 do
			local rarityLoot = g_ui.createWidget('BestiaryLoot', lootContainer)
			rarityLoot.rarityLevel:setText(lootRarityLevel[a])
			
			-- All loot slots
			local lootSlots = {rarityLoot.c_loot01, rarityLoot.c_loot02, rarityLoot.c_loot03, rarityLoot.c_loot04, rarityLoot.c_loot05, rarityLoot.c_loot06, rarityLoot.c_loot07, rarityLoot.c_loot08, rarityLoot.c_loot09, rarityLoot.c_loot10, rarityLoot.c_loot11, rarityLoot.c_loot12, rarityLoot.c_loot13, rarityLoot.c_loot14, rarityLoot.c_loot15}
			
			local difficultyList = {}
			for i = 1, #tierLoot do
				if tierLoot[i][2] == a then
					table.insert(difficultyList, {
						itemId = tierLoot[i][1],
						name = tierLoot[i][3],
						countMax = tierLoot[i][4]
					})
				end
			end
			
			-- Loot calculation
			for i = 1, #lootSlots do
				local slot = lootSlots[i]
				if difficultyList[i] then
					slot:enable()
					if (currentLevel > 1) then
						if slot.image then
							slot.image:setImageSource("/images/ui/34-button")
							slot.image:setImageClip("0 34 34 34")
						end
						slot.item:setItemId(difficultyList[i].itemId)
						slot.item:setTooltip(firstToUpper(difficultyList[i].name))
						slot.countLabel:setText(difficultyList[i].countMax > 1 and "1+" or "1")
						slot.countLabel:show()
					else
						if slot.image then
							slot.image:setImageSource("/images/ui/unkown-button")
							slot.image:setImageClip("0 0 34 34")
						end
						slot.item:setItemId(0)
						slot.countLabel:hide()
					end
				else
					if slot.image then
						slot.image:setImageSource("/images/ui/34-button")
						slot.image:setImageClip("0 0 34 34")
					end
					slot.item:setItemId(0)
					slot.countLabel:hide()
					slot:disable()
				end
			end
			
			rarityLoot:setMarginTop(5 + ((a-1) * 40))
		end
		
		if currentLevel > 1 then
			local charmPoints = msg:getU16()
			local attackMode = msg:getU8()
			local unknownPacket = msg:getU8()
			local healthMax = msg:getU32()
			local experience = msg:getU32()
			local baseSpeed = msg:getU16()
			local armor = msg:getU16()
	
			bestiaryMonster.charmAmount:setText(charmPoints)
			bestiaryMonster.healthAmount:setText(healthMax)
			bestiaryMonster.experienceAmount:setText(experience)
			bestiaryMonster.speedAmount:setText(baseSpeed)
			bestiaryMonster.armorAmount:setText(armor)
		else
			bestiaryMonster.charmAmount:setText("?")
			bestiaryMonster.healthAmount:setText("?")
			bestiaryMonster.experienceAmount:setText("?")
			bestiaryMonster.speedAmount:setText("?")
			bestiaryMonster.armorAmount:setText("?")
			bestiaryMonster.locationTextfield:setText("?")
		end
		
		-- Elements setup
		local elements = {bestiaryMonster.physicalAmount, bestiaryMonster.earthAmount, bestiaryMonster.fireAmount, bestiaryMonster.deathAmount, bestiaryMonster.energyAmount, bestiaryMonster.holyAmount, bestiaryMonster.iceAmount, bestiaryMonster.healingAmount}
		
		if currentLevel > 2 then
			-- Element Table Initialize
			local elementWidgetTable = {
				[0] = bestiaryMonster.physicalAmount,
				[1] = bestiaryMonster.fireAmount,
				[2] = bestiaryMonster.earthAmount,
				[3] = bestiaryMonster.energyAmount,
				[4] = bestiaryMonster.iceAmount,
				[5] = bestiaryMonster.holyAmount,
				[6] = bestiaryMonster.deathAmount,
				[7] = bestiaryMonster.healingAmount
			}
			
			-- Basic setup for all elements
			for a = 1, #elements do 
				elements[a]:setPercent(68) -- Means 100%
			end
			
			-- Actual element Setup
			local elementsList = msg:getU8()
			for b = 1, elementsList do
				local elementId, elementPercent = msg:getU8(), msg:getU16()
				-- We change each element depending on which element has been altered
				if elementWidgetTable[elementId] then
					local elementFormula = (elementPercent / 100)
					if (elementPercent == 0) then
						progressPercent = 0
					elseif (elementPercent == 100) then
						progressPercent = 68
					else
						progressPercent = elementFormula * 68
					end
					
					elementWidgetTable[elementId]:setPercent(progressPercent)
					if (elementPercent > 100) then
						elementWidgetTable[elementId]:setBackgroundColor("#18ce18")
					elseif (elementPercent < 100) then
						elementWidgetTable[elementId]:setBackgroundColor("#ae0f0f")
					elseif (elementPercent == 100) then
						elementWidgetTable[elementId]:setBackgroundColor("#ffffff")
					end
				end
			end
		
			-- Location
			local locations = msg:getU16()
			local locationsList = {}
			for i = 1, locations do
				locationsList[#locationsList + 1] = msg:getString()
			end
			
			bestiaryMonster.locationTextfield:setText(formatLocations(locationsList))
		else
			bestiaryMonster.locationTextfield:setText("?")
			for c = 1, #elements do
				elements[c]:setPercent(0)
			end
		end
		
		-- Charms (Not done)
		if currentLevel > 3 then
			local hascharm = msg:getU8()
			if hascharm > 0 then
				msg:getU8()
				msg:getU32()
			else
				msg:getU8()
			end
		end
		if scheduleBestiaryMonsterRefresh then
			scheduleBestiaryMonsterRefresh()
		end
	  end)

	registerOpcode(BestiaryMessage, function(protocol, msg)
		local message = msg:getString()
		if displayInfoBox then
			displayInfoBox("Cyclopedia", message)
		else
			print(message)
		end
	end)

	registerOpcode(BestiaryTracker, function(protocol, msg)
		updateBestiaryTracker(msg)
	end)

	registerOpcode(BestiaryProgress, function(protocol, msg)
		local raceId = msg:getU16()
		local progress = msg:getU8()
		local killCount = msg:getU32()
		local firstUnlock = msg:getU16()
		local secondUnlock = msg:getU16()
		local toKill = msg:getU16()
		local raceOutfit = readCyclopediaCreatureOutfit(msg)
		local charmAmount = msg:getU32()
		local goldAmount = msg:getU32()

		if modules.game_notifications and modules.game_notifications.showBestiaryProgress then
			modules.game_notifications.showBestiaryProgress(raceId, progress)
		end

		applyBestiaryProgressUpdate({
			raceId = raceId,
			progress = progress,
			kills = killCount,
			firstUnlock = firstUnlock,
			secondUnlock = secondUnlock,
			toKill = toKill,
			outfit = raceOutfit
		})
		BestiaryChangeAmount(charmAmount, goldAmount)
	end)

	ProtocolGame.unregisterOpcode(CyclopediaOpcode.Send)
	ProtocolGame.registerOpcode(CyclopediaOpcode.Send, dispatchBestiaryProtocol)
	bestiaryProtocolRegistered = true
end

function getItemTier(chance)
	local tier = 1
	if (chance < 1000) then
		tier = 4
	elseif (chance >= 1000 and chance < 10000) then
		tier = 3
	elseif (chance >= 10000 and chance < 50000) then
		tier = 2
	elseif (chance >= 50000) then
		tier = 1
	end
return tier
end
local function formatNumber(value)
	local number = math.floor(tonumber(value) or 0)
	local sign = number < 0 and '-' or ''
	local text = tostring(math.abs(number))
	local left, middle, right = text:match('^([^%d]*%d)(%d*)(.-)$')

	if not left then
		return tostring(number)
	end

	return sign .. left .. middle:reverse():gsub('(%d%d%d)', '%1,'):reverse() .. right
end

function BestiaryChangeAmount(amount,secondAmount)
if not isBestiaryView() then
return
end
if charmAmountBestiary then
charmAmountBestiary:setText(formatNumber(amount))
end
if goldAmountBestiary then
goldAmountBestiary:setText(formatNumber(secondAmount))
end
end

function untrackAllBestiaryCreatures()
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return
	end
	for raceId, _ in pairs(trackedCreatures) do
		local msg = OutputMessage.create()
		msg:addU8(CyclopediaOpcode.Tracker)
		msg:addU16(raceId)
		protocolGame:send(msg)
	end
end

local function sortTrackerEntries()
	table.sort(trackerEntries, function(a, b)
		local valA, valB
		if trackerSortType == 'name' then
			valA = a.outfit and a.outfit.name:lower() or "unknown"
			valB = b.outfit and b.outfit.name:lower() or "unknown"
		elseif trackerSortType == 'percentage' then
			valA = math.min(100, math.floor((a.kills * 100) / math.max(a.toKill, 1)))
			valB = math.min(100, math.floor((b.kills * 100) / math.max(b.toKill, 1)))
		elseif trackerSortType == 'remaining_kills' then
			valA = math.max(0, a.toKill - a.kills)
			valB = math.max(0, b.toKill - b.kills)
		end

		if valA == valB then
			local nameA = a.outfit and a.outfit.name:lower() or ""
			local nameB = b.outfit and b.outfit.name:lower() or ""
			return nameA < nameB
		end

		if trackerSortOrder == 'asc' then
			return valA < valB
		else
			return valA > valB
		end
	end)
end

local function redrawBestiaryTracker()
	local window = ensureBestiaryTrackerWindow()
	if not window then
		return
	end

	local contentsPanel = window:recursiveGetChildById('contentsPanel')
	if not contentsPanel then
		return
	end

	contentsPanel:destroyChildren()

	sortTrackerEntries()

	for _, entry in ipairs(trackerEntries) do
		local row = g_ui.createWidget('BestiaryTrackerEntry', contentsPanel)
		if not row then
			return
		end
		row.raceId = entry.raceId
		bindBestiaryTrackerEntryClick(row, entry.raceId)
		bindBestiaryTrackerEntryClick(row.creature, entry.raceId)
		bindBestiaryTrackerEntryClick(row.creatureName, entry.raceId)
		bindBestiaryTrackerEntryClick(row.progressBg, entry.raceId)
		bindBestiaryTrackerEntryClick(row.progressBar, entry.raceId)

		if entry.outfit then
			row.creature:setOutfit(entry.outfit)
			row.creatureName:setText(firstToUpper(entry.outfit.name))
		else
			row.creatureName:setText("Unknown")
		end
		row.progressBar:setPercent(math.min(100, math.floor((entry.kills * 100) / math.max(entry.toKill, 1))))
		row.progressBar:setText(entry.kills)
	end
end

ensureBestiaryTrackerWindow = function()
	if bestiaryTrackerWindow then
		return bestiaryTrackerWindow
	end

	local rightPanel = modules.game_interface and modules.game_interface.getRightPanel and modules.game_interface.getRightPanel()
	if not rightPanel then
		return nil
	end

	bestiaryTrackerWindow = g_ui.createWidget('BestiaryTrackerMini', rightPanel)
	if not bestiaryTrackerWindow then
		return nil
	end

	local toggleFilterButton = bestiaryTrackerWindow:recursiveGetChildById('toggleFilterButton')
	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
		toggleFilterButton:setOn(false)
	end

	local contextMenuButton = bestiaryTrackerWindow:recursiveGetChildById('contextMenuButton')
	local lockButton = bestiaryTrackerWindow:recursiveGetChildById('lockButton')
	local minimizeButton = bestiaryTrackerWindow:recursiveGetChildById('minimizeButton')
	local newWindowButton = bestiaryTrackerWindow:recursiveGetChildById('newWindowButton')

	if contextMenuButton then
		contextMenuButton:setVisible(true)
		if minimizeButton then
			contextMenuButton:breakAnchors()
			contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
			contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
			contextMenuButton:setMarginRight(7)
			contextMenuButton:setMarginTop(0)
		end

		contextMenuButton.onClick = function(widget, mousePos)
			local menu = g_ui.createWidget('PopupMenu')
			menu:setGameMenu(true)
			
			menu:addCheckBox(tr('Sort by name'), trackerSortType == 'name', function(checkBox, checked)
				trackerSortType = 'name'
				g_settings.set('bestiary-tracker-sort-type', trackerSortType)
				redrawBestiaryTracker()
			end)
			menu:addCheckBox(tr('Sort by completion percentage'), trackerSortType == 'percentage', function(checkBox, checked)
				trackerSortType = 'percentage'
				g_settings.set('bestiary-tracker-sort-type', trackerSortType)
				redrawBestiaryTracker()
			end)
			menu:addCheckBox(tr('Sort by remaining kills'), trackerSortType == 'remaining_kills', function(checkBox, checked)
				trackerSortType = 'remaining_kills'
				g_settings.set('bestiary-tracker-sort-type', trackerSortType)
				redrawBestiaryTracker()
			end)

			menu:addSeparator()

			menu:addCheckBox(tr('Sort ascending'), trackerSortOrder == 'asc', function(checkBox, checked)
				trackerSortOrder = 'asc'
				g_settings.set('bestiary-tracker-sort-order', trackerSortOrder)
				redrawBestiaryTracker()
			end)
			menu:addCheckBox(tr('Sort descending'), trackerSortOrder == 'desc', function(checkBox, checked)
				trackerSortOrder = 'desc'
				g_settings.set('bestiary-tracker-sort-order', trackerSortOrder)
				redrawBestiaryTracker()
			end)

			menu:addSeparator()

			menu:addOption(tr('Untrack all'), function()
				untrackAllBestiaryCreatures()
			end)

			menu:display(mousePos)
			return true
		end
	end

	if newWindowButton then
		newWindowButton:setVisible(true)
		if contextMenuButton then
			newWindowButton:breakAnchors()
			newWindowButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
			newWindowButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
			newWindowButton:setMarginRight(2)
			newWindowButton:setMarginTop(0)
		end

		newWindowButton.onClick = function()
			if modules.game_cyclopedia and modules.game_cyclopedia.show then
				modules.game_cyclopedia.show()
			end
			return true
		end
	end

	if lockButton then
		lockButton:setVisible(true)
		if newWindowButton then
			lockButton:breakAnchors()
			lockButton:addAnchor(AnchorTop, newWindowButton:getId(), AnchorTop)
			lockButton:addAnchor(AnchorRight, newWindowButton:getId(), AnchorLeft)
			lockButton:setMarginRight(2)
			lockButton:setMarginTop(0)
		elseif contextMenuButton then
			lockButton:breakAnchors()
			lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
			lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
			lockButton:setMarginRight(2)
			lockButton:setMarginTop(0)
		end
	end

	bestiaryTrackerWindow:setup()
	bestiaryTrackerWindow:hide()
	return bestiaryTrackerWindow
end

function requestBestiaryTrackerToggle(raceId)
	local protocolGame = g_game.getProtocolGame()
	if protocolGame and raceId and raceId > 0 then
		local window = ensureBestiaryTrackerWindow()
		if window then
			window:open()
		end
		local msg = OutputMessage.create()
		msg:addU8(CyclopediaOpcode.Tracker)
		msg:addU16(raceId)
		protocolGame:send(msg)
	end
end

function requestBestiaryTrackerRefresh()
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		local msg = OutputMessage.create()
		msg:addU8(CyclopediaOpcode.Tracker)
		msg:addU16(0)
		protocolGame:send(msg)
	end
end

local function scheduleBestiaryTrackerRefresh()
	if bestiaryTrackerRefreshEvent then
		return
	end

	bestiaryTrackerRefreshEvent = scheduleEvent(function()
		bestiaryTrackerRefreshEvent = nil
		if bestiaryTrackerWindow and bestiaryTrackerWindow:isVisible() and g_game.isOnline() then
			requestBestiaryTrackerRefresh()
			scheduleBestiaryTrackerRefresh()
		end
	end, 1000)
end

function onBestiaryTrackerOpen()
	if bestiaryTrackerButton then
		bestiaryTrackerButton:setOn(true)
	end
	local topMenuButton = modules.game_cyclopedia.bestiaryTrackerButton
	if topMenuButton then
		topMenuButton:setOn(true)
	end
	scheduleBestiaryTrackerRefresh()
end

function onBestiaryTrackerClose()
	if bestiaryTrackerButton then
		bestiaryTrackerButton:setOn(false)
	end
	local topMenuButton = modules.game_cyclopedia.bestiaryTrackerButton
	if topMenuButton then
		topMenuButton:setOn(false)
	end
	if bestiaryTrackerRefreshEvent then
		removeEvent(bestiaryTrackerRefreshEvent)
		bestiaryTrackerRefreshEvent = nil
	end
end

function toggleBestiaryTracker()
	local window = ensureBestiaryTrackerWindow()
	if window then
		if window:isVisible() then
			window:close()
		else
			window:open()
		end
	end
end

stopBestiaryMonsterRefresh = function()
	if bestiaryMonsterRefreshEvent then
		removeEvent(bestiaryMonsterRefreshEvent)
		bestiaryMonsterRefreshEvent = nil
	end
end

scheduleBestiaryMonsterRefresh = function()
	if bestiaryMonsterRefreshEvent then
		return
	end

	bestiaryMonsterRefreshEvent = scheduleEvent(function()
		bestiaryMonsterRefreshEvent = nil
		if g_game.isOnline() and selectedBestiaryRaceId > 0 and isBestiaryView() and bestiaryMonster and bestiaryMonster:isVisible() then
			requestBestiaryMonsterData(selectedBestiaryRaceId)
			scheduleBestiaryMonsterRefresh()
		end
	end, 1500)
end

function updateBestiaryTracker(msg)
	trackedCreatures = {}
	trackerEntries = {}
	local count = msg:getU8()
	for i = 1, count do
		local raceId = msg:getU16()
		local raceOutfit = readCyclopediaCreatureOutfit(msg)
		protoData[raceId] = raceOutfit
		trackerEntries[#trackerEntries + 1] = {
			raceId = raceId,
			outfit = raceOutfit,
			kills = msg:getU32(),
			toKill = msg:getU16(),
			progress = msg:getU8()
		}
		trackedCreatures[raceId] = true
	end

	redrawBestiaryTracker()

	local window = ensureBestiaryTrackerWindow()
	if window then
		if count > 0 then
			if not window:getSettings('closed') then
				window:show()
			end
			scheduleBestiaryTrackerRefresh()
		else
			window:hide()
			if bestiaryTrackerRefreshEvent then
				removeEvent(bestiaryTrackerRefreshEvent)
				bestiaryTrackerRefreshEvent = nil
			end
		end
	end

	if bestiaryMonster and bestiaryMonster:isVisible() and selectedBestiaryRaceId > 0 then
		setTrackKillsCheckedFromServer(trackedCreatures[selectedBestiaryRaceId] == true)
	end
end

function initBestiary(contentContainer)
	if bestiaryPanel then
		bestiaryPanel:show()
		if #currentCategoriesList == 0 then
			requestBestiaryData()
		end
		return
	end

	bestiaryPanel = g_ui.loadUI("styles/bestiary", contentContainer)
	bestiaryPanel:show()
	
	-- Child styles
	bestiaryContainer = bestiaryPanel:recursiveGetChildById('bestiaryContainer')
		bestiaryCSelecter = bestiaryContainer:recursiveGetChildById('bestiaryCSelecter')
		
		charmAmountBestiary = bestiaryPanel:recursiveGetChildById('charmPoints')
		goldAmountBestiary = bestiaryPanel:recursiveGetChildById('goldPoints')
		bestiaryTrackerButton = bestiaryPanel:recursiveGetChildById('bestiaryTracker')
		bestiarySearchButton = bestiaryPanel:recursiveGetChildById('searchButton')
		bestiarySearchInput = bestiaryPanel:recursiveGetChildById('searchInput')

		backCategoryButton = bestiaryPanel:recursiveGetChildById('backCategoryButton')
		backPageButton = bestiaryPanel:recursiveGetChildById('backPageButton')
		pageCountLabel = bestiaryPanel:recursiveGetChildById('pageCountLabel')
		nextPageButton = bestiaryPanel:recursiveGetChildById('nextPageButton')
		
	bestiaryMonster = g_ui.createWidget('BestiaryMonster', bestiaryPanel)
		starsContainer = bestiaryMonster:recursiveGetChildById('starsContainer')
		bestiaryLoot = bestiaryMonster:recursiveGetChildById('BestiaryLoot')
		occurrenceContainer = bestiaryMonster:recursiveGetChildById('occurrenceContainer')
		verticalLocationSB = bestiaryMonster:recursiveGetChildById('verticalLocationSB')
		lootContainer = bestiaryMonster:recursiveGetChildById('lootContainer')
		bestiaryMonster.locationField = bestiaryMonster:recursiveGetChildById('locationField')
		bestiaryMonster.locationTextfield = bestiaryMonster:recursiveGetChildById('locationTextfield')
		bestiaryMonster.trackKills = bestiaryMonster:recursiveGetChildById('trackKills')
		bestiaryMonster.charmSlot1 = bestiaryMonster:recursiveGetChildById('charmSlot1')
		bestiaryMonster.charmSlot2 = bestiaryMonster:recursiveGetChildById('charmSlot2')
		bestiaryMonster.assignCharmButton = bestiaryMonster:recursiveGetChildById('assignCharmButton')

	if backCategoryButton then
		backCategoryButton.onClick = function()
			if bestiaryMonster:isVisible() then
				bestiaryMonster:hide()
				bestiaryContainer:show()
				if currentBestiaryCategory then
					showMonstersPage(currentMonsterListPage)
				else
					showCategoriesPage(currentCategoryPage)
				end
			else
				requestBestiaryData()
			end
		end
	end

	if backPageButton then
		backPageButton.onClick = function()
			if bestiaryMonster:isVisible() then
				return
			end
			if currentBestiaryCategory then
				showMonstersPage(currentMonsterListPage - 1)
			else
				showCategoriesPage(currentCategoryPage - 1)
			end
		end
	end

	if nextPageButton then
		nextPageButton.onClick = function()
			if bestiaryMonster:isVisible() then
				return
			end
			if currentBestiaryCategory then
				showMonstersPage(currentMonsterListPage + 1)
			else
				showCategoriesPage(currentCategoryPage + 1)
			end
		end
	end

	if bestiaryTrackerButton then
		bestiaryTrackerButton.onClick = function()
			toggleBestiaryTracker()
		end
	end

	if bestiaryMonster.assignCharmButton then
		bestiaryMonster.assignCharmButton.onClick = function(widget, mousePos)
			updateBestiaryCharmSlotSelection()
			showBestiaryAssignCharmMenu(mousePos)
		end
	end

	if bestiaryMonster.trackKills then
		bestiaryMonster.trackKills.onCheckChange = function(widget, checked)
			if syncingTrackKillsCheckbox then
				return
			end
			if not selectedBestiaryRaceId or selectedBestiaryRaceId <= 0 then
				return
			end
			trackedCreatures[selectedBestiaryRaceId] = checked or nil
			requestBestiaryTrackerToggle(selectedBestiaryRaceId)
		end
	end

	if bestiarySearchButton then
		bestiarySearchButton.onClick = requestBestiarySearch
	end

	if bestiarySearchInput then
		bestiarySearchInput.onTextChange = function(widget, text)
			if bestiarySearchEvent then
				removeEvent(bestiarySearchEvent)
				bestiarySearchEvent = nil
			end
			bestiarySearchEvent = scheduleEvent(function()
				bestiarySearchEvent = nil
				requestBestiarySearch()
			end, 300)
		end
	end
		
	--- Extras
	connect(g_game, {
		onEnterGame = registerBestiaryProtocol, 
		onPendingGame = registerBestiaryProtocol
	})
	
	if g_game.isOnline() then
        registerBestiaryProtocol()
    end

	-- Protocolling request
	requestBestiaryData() -- We request the bestiary data
end
local function requestBestiaryInfo()
	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
    local msg = OutputMessage.create()
    msg:addU8(CyclopediaOpcode.Info)
    protocolGame:send(msg)
	end  

end
function requestBestiaryData()
	if stopBestiaryMonsterRefresh then
		stopBestiaryMonsterRefresh()
	end
	bestiaryMonster:hide()
	bestiaryContainer:show()
	currentBestiaryCategory = nil
	currentBestiaryRows = {}
	currentBestiaryEntries = {}
	updatePagination(1, 1, true)
	
	requestBestiaryInfo()
end

local bestiaryTable = {
	["Bosses"] = 1,
	["Aquatic"] = 2,
	["Bird"] = 3,
	["Construct"] = 4,
	["Demon"] = 5,
	["Dragon"] = 6,
	["Elemental"] = 7,
	["Extra Dimensional"] = 8,
	["Fey"] = 9,
	["Giant"] = 10,
	["Human"] = 11,
	["Humanoid"] = 12,
	["Lycanthrope"] = 13,
	["Magical"] = 14,
	["Mammal"] = 15,
	["Plant"] = 16,
	["Reptile"] = 17,
	["Slime"] = 18,
	["Undead"] = 19,
	["Vermin"] = 20
}

function requestBestiaryCategoryData(catName)

	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
    local msg = OutputMessage.create()
    msg:addU8(CyclopediaOpcode.Category)
    msg:addU8(0x02)
    msg:addString(catName)
    protocolGame:send(msg)
	end  


end

function requestBestiarySearch()
	local query = trimText(bestiarySearchInput and bestiarySearchInput:getText() or "")
	if query == "" then
		requestBestiaryData()
		return
	end

	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
		local msg = OutputMessage.create()
		msg:addU8(CyclopediaOpcode.Category)
		msg:addU8(0x02)
		msg:addString(BESTIARY_SEARCH_PREFIX .. query)
		protocolGame:send(msg)
	end
end

function requestBestiaryMonsterData(raceId)

	local protocolGame = g_game.getProtocolGame()
	if protocolGame then
    local msg = OutputMessage.create()
    msg:addU8(CyclopediaOpcode.Monster)
    msg:addU16(raceId)
    protocolGame:send(msg)
	end  
end

function emptyBestiaryCategories()
	if not bestiaryCSelecter then
		return
	end
	while bestiaryCSelecter:getChildCount() > 0 do
		local child = bestiaryCSelecter:getLastChild()
		bestiaryCSelecter:destroyChildren(child)
	end
end
