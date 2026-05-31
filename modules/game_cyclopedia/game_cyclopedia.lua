local window, previousType, currentType
local bestiaryPanel
cyclopediaButton = nil
bestiaryTrackerButton = nil
itemsData = itemsData or {
	customSalePrices = {},
	primaryLootValueSources = {}
}
CyclopediaItems = CyclopediaItems or {}

local function getItemId(item)
	if type(item) == 'number' then
		return item
	end
	if item and item.getId then
		local ok, id = pcall(function() return item:getId() end)
		if ok then
			return id
		end
	end
	return nil
end

local function getPricesFile()
	local player = g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
	local playerId = player and player.getId and player:getId() or nil
	if playerId then
		return '/characterdata/' .. playerId .. '/itemprices.json', '/characterdata/' .. playerId
	end

	local characterName = g_game.getCharacterName and g_game.getCharacterName() or ''
	if not characterName or characterName == '' then
		return nil
	end
	characterName = characterName:gsub('[^%w_%- ]', '_')
	return '/characterdata/' .. characterName .. '/itemprices.json', '/characterdata/' .. characterName
end

local function ensureItemsData()
	itemsData.customSalePrices = itemsData.customSalePrices or {}
	itemsData.primaryLootValueSources = itemsData.primaryLootValueSources or {}
	modules.game_cyclopedia.itemsData = itemsData
	return itemsData
end

function loadItemsPriceData()
	ensureItemsData()
	local file = getPricesFile()
	if not file or not g_resources.fileExists(file) then
		return
	end

	local ok, result = pcall(function()
		return json.decode(g_resources.readFileContents(file))
	end)
	if ok and type(result) == 'table' then
		itemsData = result
		ensureItemsData()
	else
		g_logger.warning('Unable to load cyclopedia item prices: ' .. tostring(result))
	end
end

function saveItemsPriceData()
	ensureItemsData()
	local file, directory = getPricesFile()
	if not file then
		return
	end

	local ok, result = pcall(function() return json.encode(itemsData, 2) end)
	if not ok then
		g_logger.warning('Unable to encode cyclopedia item prices: ' .. tostring(result))
		return
	end
	pcall(function() g_resources.makeDir('/characterdata') end)
	if directory then
		pcall(function() g_resources.makeDir(directory) end)
	end
	g_resources.writeFileContents(file, result)
end

function CyclopediaItems.getCurrentItemValue(item)
	ensureItemsData()
	local itemId = getItemId(item)
	if not itemId then
		return 0
	end

	local customPrice = itemsData.customSalePrices[tostring(itemId)] or itemsData.customSalePrices[itemId]
	if customPrice then
		return tonumber(customPrice) or 0
	end

	local defaultValue = 0
	if item and item.getDefaultValue then
		local ok, value = pcall(function() return item:getDefaultValue() end)
		if ok then defaultValue = tonumber(value) or 0 end
	end

	local averageMarketValue = 0
	if item and item.getAverageMarketValue then
		local ok, value = pcall(function() return item:getAverageMarketValue() end)
		if ok then averageMarketValue = tonumber(value) or 0 end
	elseif item and item.getMeanPrice then
		local ok, value = pcall(function() return item:getMeanPrice() end)
		if ok then averageMarketValue = tonumber(value) or 0 end
	end

	if itemsData.primaryLootValueSources[tostring(itemId)] then
		return averageMarketValue > 0 and averageMarketValue or defaultValue
	end
	return defaultValue > 0 and defaultValue or averageMarketValue
end

function onItemsPriceList(items)
	ensureItemsData()
	for _, item in ipairs(items) do
		local id, name, price, type = unpack(item)
		if id and price then
			itemsData.customSalePrices[tostring(id)] = tonumber(price) or price
		end
	end
	saveItemsPriceData()

	if modules.game_containers and modules.game_containers.reloadContainers then
		scheduleEvent(function()
			modules.game_containers.reloadContainers()
		end, 50)
	end

	if refreshItemsCyclopedia then
		scheduleEvent(function()
			refreshItemsCyclopedia()
		end, 50)
	end
end

function init()
	modules.game_cyclopedia.itemsData = itemsData
	modules.game_cyclopedia.CyclopediaItems = CyclopediaItems
	
	-- The rest
	connect(g_game, { 
		onGameStart = loadItemsPriceData,
		onItemsPriceList = onItemsPriceList,
		onMarketEnter = onCyclopediaMarketEnter,
		onEnterGame = registerBestiaryProtocol,
		onPendingGame = registerBestiaryProtocol,
		onGameEnd = onCyclopediaGameEnd
	})
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
    
	g_ui.importStyle('styles/bestiary_tracker')
	window 	   = g_ui.displayUI('game_cyclopedia')
	
	cyclopediaButton = modules.client_topmenu.addRightGameToggleButton('cyclopediaButton', tr('Cyclopedia'), '/images/topbuttons/ciclopedia', toggle, false, 8)
	bestiaryTrackerButton = modules.client_topmenu.addRightGameToggleButton('bestiaryTrackerButton', tr('Bestiary Tracker'), '/images/topbuttons/bestiaryTracker', toggleTracker, false, 9)
	contentContainer = window:recursiveGetChildById('contentContainer')
	buttonSelection = window:recursiveGetChildById('buttonSelection')
		items = buttonSelection:recursiveGetChildById('items')
		bestiary = buttonSelection:recursiveGetChildById('bestiary')
		charms = buttonSelection:recursiveGetChildById('charms')
		map = buttonSelection:recursiveGetChildById('map')
		houses = buttonSelection:recursiveGetChildById('houses')
		character = buttonSelection:recursiveGetChildById('character')

	modules.game_cyclopedia = modules.game_cyclopedia
end

function terminate()
	saveItemsPriceData()
	disconnect(g_game, { 
		onGameStart = loadItemsPriceData,
		onItemsPriceList = onItemsPriceList,
		onMarketEnter = onCyclopediaMarketEnter,
		onEnterGame = registerBestiaryProtocol,
		onPendingGame = registerBestiaryProtocol,
		onGameEnd = onCyclopediaGameEnd
	})
	
	-- Internal protocols
	-- disconnect(g_game, {onEnterGame = registerBestiaryProtocol, onPendingGame = registerBestiaryProtocol})
	
	-- Hooked opcodes
	ProtocolGame.unregisterOpcode(0x29)
	if terminateBestiary then
		terminateBestiary()
	elseif unregisterBestiaryProtocol then
		unregisterBestiaryProtocol()
	else
		ProtocolGame.unregisterOpcode(0x48)
	end
	
	if cyclopediaButton then
		cyclopediaButton:destroy()
		cyclopediaButton = nil
	end
	if bestiaryTrackerButton then
		bestiaryTrackerButton:destroy()
		bestiaryTrackerButton = nil
	end
	if terminateMap then
		terminateMap()
	end
	
	window:destroy()
	
	if buyWindow then
		buyWindow:destroy()
	end
end

function getContentContainer()
	return contentContainer
end

function getCurrentType()
	return currentType
end

function onCyclopediaGameEnd()
	saveItemsPriceData()
	if window then
		window:hide()
	end
	if onBestiaryGameEnd then
		onBestiaryGameEnd()
	end
end

function toggle()
	if window:isVisible() then
		window:hide()
	else
		show("bestiary") -- We init on bestiary
	end
end

function show(type)
	type = type or "bestiary"

	if currentType ~= type then
		toggleWindow(type)
	end

	if not window:isVisible() then
		window:show()
	end

	window:raise()
	window:focus()
end

function toggleTracker()
	if toggleBestiaryTracker then
		toggleBestiaryTracker()
	end
end

function emptyContentContainer()
	while contentContainer:getChildCount() > 0 do
		local child = contentContainer:getLastChild()
		contentContainer:destroyChildren(child)
	end
end

function changePreviousType(type)
	previousType = type
end

function toggleWindow(type)
	if previousType then
		previousType:enable()
		previousType:setOn(false)
	end
	
	-- We empty the container
	emptyContentContainer()
	currentType = type
		
	if (type == "items") then
		items:setOn(true)
		items:disable()
		changePreviousType(items)

		if initItems then
			initItems(contentContainer)
		end
	elseif (type == "bestiary") then
		bestiary:setOn(true)
		bestiary:disable()
		changePreviousType(bestiary)
		
		-- Setup the widget
		initBestiary(contentContainer)
	elseif (type == "charms") then
		charms:setOn(true)
		charms:disable()
		changePreviousType(charms)
		
		-- Setup the charms
		initCharms(contentContainer)
	elseif (type == "map") then
		map:setOn(true)
		map:disable()
		changePreviousType(map)
		
		-- Setup the widget
		initMap(contentContainer)
	elseif (type == "houses") then
		houses:setOn(true)
		houses:disable()
		changePreviousType(houses)
	elseif (type == "character") then
		character:setOn(true)
		character:disable()
		changePreviousType(character)
	end
end
