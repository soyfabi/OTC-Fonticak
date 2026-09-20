Cyclopedia = Cyclopedia or {}

local DETAIL_LABEL_COLUMN_WIDTH = 150
local DETAIL_ROW_HEIGHT = 20

local function measureDetailRowHeight(value, valueWidth)
	if not Cyclopedia.detailMeasureLabel then
		Cyclopedia.detailMeasureLabel = g_ui.createWidget("Label", g_ui.getRootWidget())
		Cyclopedia.detailMeasureLabel:setVisible(false)
		Cyclopedia.detailMeasureLabel:setPhantom(true)
	end

	local label = Cyclopedia.detailMeasureLabel
	label:setFont("Verdana Bold-11px")
	label:setTextAutoResize(false)
	label:setTextWrap(true)
	label:setWidth(valueWidth)
	label:setText(value or "")

	return math.max(DETAIL_ROW_HEIGHT, label:getTextSize().height + 2)
end

function Cyclopedia.appendDetailKeyValueRow(parent, key, value)
	local row = g_ui.createWidget("UIWidget", parent)
	row:setPhantom(true)

	local parentWidth = parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight()
	if parentWidth <= 0 and parent.getParent then
		local scrollArea = parent:getParent()
		if scrollArea then
			parentWidth = scrollArea:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight() - 8
		end
	end
	if parentWidth <= 0 then
		parentWidth = 425
	end

	local valueWidth = parentWidth - DETAIL_LABEL_COLUMN_WIDTH - 8
	local rowHeight = measureDetailRowHeight(value, valueWidth)

	row:setWidth(parentWidth)
	row:setHeight(rowHeight)

	local keyLabel = g_ui.createWidget("Label", row)
	keyLabel:setText(key .. ":")
	keyLabel:setColor("#C0C0C0")
	keyLabel:setFont("Verdana Bold-11px")
	keyLabel:setTextAlign(AlignTopRight)
	keyLabel:setTextAutoResize(false)
	keyLabel:setWidth(DETAIL_LABEL_COLUMN_WIDTH)
	keyLabel:setHeight(rowHeight)
	keyLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
	keyLabel:addAnchor(AnchorTop, "parent", AnchorTop)

	local valueLabel = g_ui.createWidget("Label", row)
	valueLabel:setColor("#C0C0C0")
	valueLabel:setFont("Verdana Bold-11px")
	valueLabel:setTextAlign(AlignTopLeft)
	valueLabel:setTextAutoResize(false)
	valueLabel:setWidth(valueWidth)
	valueLabel:setHeight(rowHeight)
	valueLabel:setTextWrap(true)
	valueLabel:setText(value)
	valueLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
	valueLabel:addAnchor(AnchorTop, "parent", AnchorTop)
	valueLabel:setMarginLeft(DETAIL_LABEL_COLUMN_WIDTH + 8)
end

function Cyclopedia.appendDetailCenteredRow(parent, key, value)
	local row = g_ui.createWidget("UIWidget", parent)
	row:setPhantom(true)

	local parentWidth = parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight()
	if parentWidth <= 0 and parent.getParent then
		local scrollArea = parent:getParent()
		if scrollArea then
			parentWidth = scrollArea:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight() - 16
		end
	end
	if parentWidth <= 0 then
		parentWidth = 425
	end

	local text = string.format("%s: %s", key, value)
	local rowHeight = measureDetailRowHeight(text, parentWidth - 8)

	row:setWidth(parentWidth)
	row:setHeight(rowHeight)

	local label = g_ui.createWidget("Label", row)
	label:setText(text)
	label:setColor("#C0C0C0")
	label:setFont("Verdana Bold-11px")
	label:setTextAlign(AlignCenter)
	label:setTextAutoResize(false)
	label:setTextWrap(true)
	label:setWidth(parentWidth)
	label:setHeight(rowHeight)
	label:addAnchor(AnchorLeft, "parent", AnchorLeft)
	label:addAnchor(AnchorTop, "parent", AnchorTop)
end

local function onCyclopediaItemDetail(data)
	if Cyclopedia and Cyclopedia.receiveItemDetail and Cyclopedia.receiveItemDetail(data) then
		return
	end
end

local function onCyclopediaItemDetails(itemId)
	if Cyclopedia and Cyclopedia.Items and Cyclopedia.Items.onServerItemDetails then
		Cyclopedia.Items.onServerItemDetails(itemId)
	end
end

local window, currentType, backButton, manageContainersButton, tabStack, goldBase
local moneyRefreshEvent, moneyRefreshPendingEvent
local MONEY_REFRESH_INTERVAL = 200
local MONEY_EVENT_REFRESH_DELAY = 25

local COIN_MULTIPLIERS = {
	[3031] = 1,
	[2148] = 1,
	[3035] = 100,
	[2152] = 100,
	[3043] = 10000,
	[2160] = 10000
}

local function formatCyclopediaGold(value)
	if Cyclopedia.formatGold then
		return Cyclopedia.formatGold(value)
	end

	return comma_value(value or 0)
end

local function getCyclopediaPlayerMoney()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	local bankGold = player:getResourceBalance(ResourceBank or 0) or 0
	local inventoryGold = player:getResourceBalance(ResourceInventary or 1) or 0
	local physicalCoins = 0

	for _, container in pairs(g_game.getContainers()) do
		for _, item in pairs(container:getItems()) do
			local mult = COIN_MULTIPLIERS[item:getId()]

			if mult then
				physicalCoins = physicalCoins + ((item:getCount() or 1) * mult)
			end
		end
	end

	for slot = InventorySlotFirst or 1, InventorySlotLast or 10 do
		local item = player:getInventoryItem(slot)

		if item then
			local mult = COIN_MULTIPLIERS[item:getId()]

			if mult then
				physicalCoins = physicalCoins + ((item:getCount() or 1) * mult)
			end
		end
	end

	local total = bankGold + math.max(inventoryGold, physicalCoins)

	if total > 0 then
		return total
	end

	if player.getTotalMoney then
		return player:getTotalMoney() or 0
	end

	return 0
end

function Cyclopedia.getPlayerMoney()
	return getCyclopediaPlayerMoney()
end

local function updateCyclopediaMoneyDisplay()
	if goldBase and not goldBase:isDestroyed() and goldBase:isVisible() then
		local valueLabel = goldBase.Value

		if valueLabel and not valueLabel:isDestroyed() then
			valueLabel:setText(formatCyclopediaGold(getCyclopediaPlayerMoney()))
		end
	end

	if Cyclopedia.refreshCharmsGoldDisplay then
		Cyclopedia.refreshCharmsGoldDisplay()
	end

	if Cyclopedia.refreshBestiaryGoldDisplay then
		Cyclopedia.refreshBestiaryGoldDisplay()
	end
end

function Cyclopedia.refreshMoneyDisplays(requestServerBalance)
	if requestServerBalance and g_game.requestResource then
		g_game.requestResource(ResourceBank or 0)
		g_game.requestResource(ResourceInventary or 1)
	end

	updateCyclopediaMoneyDisplay()
end

local function scheduleCyclopediaMoneyRefresh()
	if moneyRefreshPendingEvent then
		removeEvent(moneyRefreshPendingEvent)
	end

	moneyRefreshPendingEvent = scheduleEvent(function()
		moneyRefreshPendingEvent = nil
		updateCyclopediaMoneyDisplay()
	end, MONEY_EVENT_REFRESH_DELAY)
end

local function cyclopediaMoneyRefreshTick()
	moneyRefreshEvent = nil

	if not window or window:isDestroyed() or not window:isVisible() then
		return
	end

	updateCyclopediaMoneyDisplay()
	moneyRefreshEvent = scheduleEvent(cyclopediaMoneyRefreshTick, MONEY_REFRESH_INTERVAL)
end

local function startCyclopediaMoneyRefresh()
	if moneyRefreshEvent then
		return
	end

	moneyRefreshEvent = scheduleEvent(cyclopediaMoneyRefreshTick, MONEY_REFRESH_INTERVAL)
end

local function stopCyclopediaMoneyRefresh()
	if moneyRefreshEvent then
		removeEvent(moneyRefreshEvent)
		moneyRefreshEvent = nil
	end

	if moneyRefreshPendingEvent then
		removeEvent(moneyRefreshPendingEvent)
		moneyRefreshPendingEvent = nil
	end
end

function Cyclopedia.setGoldBaseVisible(visible)
	if not goldBase or goldBase:isDestroyed() then
		return
	end

	goldBase:setVisible(visible)

	if visible then
		Cyclopedia.refreshMoneyDisplays(true)
	end
end

local function onCyclopediaResourcesBalanceChange(value, oldBalance, resourceType)
	if resourceType ~= nil and resourceType ~= 0 and resourceType ~= 1 then
		return
	end

	scheduleCyclopediaMoneyRefresh()
end

local function onCyclopediaInventoryMoneyChange()
	scheduleCyclopediaMoneyRefresh()
end

local function connectCyclopediaMoneyListeners()
	connect(g_game, {
		onResourcesBalanceChange = onCyclopediaResourcesBalanceChange
	})

	connect(LocalPlayer, {
		onInventoryChange = onCyclopediaInventoryMoneyChange
	})

	if Container then
		connect(Container, {
			onOpen = onCyclopediaInventoryMoneyChange,
			onAddItem = onCyclopediaInventoryMoneyChange,
			onUpdateItem = onCyclopediaInventoryMoneyChange,
			onRemoveItem = onCyclopediaInventoryMoneyChange
		})
	end
end

local function disconnectCyclopediaMoneyListeners()
	disconnect(g_game, {
		onResourcesBalanceChange = onCyclopediaResourcesBalanceChange
	})

	disconnect(LocalPlayer, {
		onInventoryChange = onCyclopediaInventoryMoneyChange
	})

	if Container then
		disconnect(Container, {
			onOpen = onCyclopediaInventoryMoneyChange,
			onAddItem = onCyclopediaInventoryMoneyChange,
			onUpdateItem = onCyclopediaInventoryMoneyChange,
			onRemoveItem = onCyclopediaInventoryMoneyChange
		})
	end
end

local DEFAULT_WINDOW_SIZE = { width = 700, height = 538 }
local ITEMS_WINDOW_SIZE = { width = 700, height = 618 }
local ITEMS_CONTENT_MARGIN_BOTTOM = 36

local function setItemsTabLayout(active)
	if not window or not contentContainer then
		return
	end

	if active then
		window:setSize(ITEMS_WINDOW_SIZE)
		contentContainer:setMarginBottom(ITEMS_CONTENT_MARGIN_BOTTOM)
		if manageContainersButton then
			manageContainersButton:setVisible(true)
		end
	else
		window:setSize(DEFAULT_WINDOW_SIZE)
		contentContainer:setMarginBottom(0)
		if manageContainersButton then
			manageContainersButton:setVisible(false)
		end
	end
end
cyclopediaButton = nil
bestiaryTrackerButton = nil
local function requestMarketItemsPreload()
	if not g_game.isOnline() then
		return
	end
	if modules.game_market and modules.game_market.requestMarketItemsForCyclopedia then
		modules.game_market.requestMarketItemsForCyclopedia()
	end
end

local function onCyclopediaEnterGame()
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
end

function init()
	
	-- The rest
	connect(g_game, {
		onGameStart = onCyclopediaGameStart,
		onGameEnd = onCyclopediaGameEnd,
		onEnterGame = onCyclopediaEnterGame,
		onPendingGame = registerBestiaryProtocol,
		onParseItemDetail = onCyclopediaItemDetail,
		onItemDetails = onCyclopediaItemDetails
	}, true)

	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end

	g_ui.importStyle('styles/bestiary_tracker')
	g_ui.importStyle('styles/cyclopedia_map_widgets')
	window 	   = g_ui.displayUI('game_cyclopedia')
	
	cyclopediaButton = modules.client_topmenu.addRightGameToggleButton('cyclopediaButton', tr('Cyclopedia'), '/images/topbuttons/ciclopedia', toggle, false, 8)
	bestiaryTrackerButton = modules.client_topmenu.addRightGameToggleButton('bestiaryTrackerButton', tr('Bestiary Tracker'), '/images/options/bestiaryTracker', toggleTracker, false, 9)
	modules.game_cyclopedia.cyclopediaButton = cyclopediaButton
	modules.game_cyclopedia.bestiaryTrackerButton = bestiaryTrackerButton

	window.onVisibilityChange = function(widget, visible)
		if cyclopediaButton then
			cyclopediaButton:setOn(visible)
		end

		if visible then
			Cyclopedia.refreshMoneyDisplays(true)
			startCyclopediaMoneyRefresh()
		else
			stopCyclopediaMoneyRefresh()

			if Cyclopedia.onItemsTabHidden then
				Cyclopedia.onItemsTabHidden()
			end
			if modules.game_inspect and modules.game_inspect.hide then
				modules.game_inspect.hide()
			end
			setItemsTabLayout(false)
		end
	end
	contentContainer = window:recursiveGetChildById('contentContainer')
	backButton = window:recursiveGetChildById('backButton')
	manageContainersButton = window:recursiveGetChildById('manageContainersButton')
	goldBase = window:recursiveGetChildById('GoldBase')
	tabStack = {}
	buttonSelection = window:recursiveGetChildById('buttonSelection')
		items = buttonSelection:recursiveGetChildById('items')
		bestiary = buttonSelection:recursiveGetChildById('bestiary')
		charms = buttonSelection:recursiveGetChildById('charms')
		map = buttonSelection:recursiveGetChildById('map')
		houses = buttonSelection:recursiveGetChildById('houses')
		character = buttonSelection:recursiveGetChildById('character')

	modules.game_cyclopedia.Cyclopedia = Cyclopedia

	if g_game.isOnline() then
		connectCyclopediaMoneyListeners()
	end
end

function terminate()
	stopCyclopediaMoneyRefresh()
	disconnectCyclopediaMoneyListeners()

	disconnect(g_game, {
		onGameStart = onCyclopediaGameStart,
		onGameEnd = onCyclopediaGameEnd,
		onEnterGame = onCyclopediaEnterGame,
		onPendingGame = registerBestiaryProtocol,
		onParseItemDetail = onCyclopediaItemDetail,
		onItemDetails = onCyclopediaItemDetails
	})

	if Cyclopedia.Items and Cyclopedia.Items.terminate then
		Cyclopedia.Items.terminate()
	end
	if Cyclopedia and Cyclopedia.clearMapUI then
		Cyclopedia.clearMapUI()
	end
	
	-- Hooked opcodes
	ProtocolGame.unregisterOpcode(0x29)
	if terminateBestiary then
		terminateBestiary()
	elseif unregisterBestiaryProtocol then
		unregisterBestiaryProtocol()
	else
		ProtocolGame.unregisterOpcode(CyclopediaOpcode and CyclopediaOpcode.Send or 0x39)
	end
	
	if cyclopediaButton then
		cyclopediaButton:destroy()
		cyclopediaButton = nil
	end
	if bestiaryTrackerButton then
		bestiaryTrackerButton:destroy()
		bestiaryTrackerButton = nil
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

function onCyclopediaGameStart()
	connectCyclopediaMoneyListeners()

	if LoadedPlayer and LoadedPlayer.cacheFromLocalPlayer then
		LoadedPlayer:cacheFromLocalPlayer()
	end
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
	if loadBestiaryUnlockCache then
		loadBestiaryUnlockCache()
	end
	if restoreBestiaryTracker then
		restoreBestiaryTracker()
	end
	if Cyclopedia.Items and Cyclopedia.Items.loadJson then
		Cyclopedia.Items.loadJson()
	end
	requestMarketItemsPreload()
end

function onCyclopediaGameEnd()
	stopCyclopediaMoneyRefresh()
	disconnectCyclopediaMoneyListeners()

	if Cyclopedia.Items and Cyclopedia.Items.saveJson then
		Cyclopedia.Items.saveJson()
	end
	if Cyclopedia and Cyclopedia.clearMapUI then
		Cyclopedia.clearMapUI()
	end
	if window then
		window:hide()
	end
	if Cyclopedia.invalidateItemsIndex then
		Cyclopedia.invalidateItemsIndex()
	end
	if onBestiaryGameEnd then
		onBestiaryGameEnd()
	end
end

function toggle(type)
	if window:isVisible() and not type then
		setItemsTabLayout(false)
		window:hide()
	else
		if not window:isVisible() then
			tabStack = {}
			updateBackButton()
		end
		show(type or "bestiary")
	end
end

function updateBackButton()
	if backButton then
		backButton:setEnabled(tabStack and #tabStack > 0)
	end
end

function toggleBack()
	if currentType == "bestiary" and Cyclopedia.handleBestiaryBack and Cyclopedia.handleBestiaryBack() then
		return
	end

	local previousTab = tabStack and table.remove(tabStack)
	if not previousTab then
		updateBackButton()
		return
	end

	updateBackButton()
	toggleWindow(previousTab, true)
end

function show(type)
	type = type or "bestiary"

	if not window:isVisible() then
		tabStack = {}
		updateBackButton()
	end

	if currentType ~= type then
		toggleWindow(type)
	end

	if not window:isVisible() then
		window:show()
	end

	window:raise()
	window:focus()
end

function Cyclopedia.openBestiaryMonster(raceId)
	if openBestiaryMonster then
		return openBestiaryMonster(raceId)
	end
	return false
end

function Cyclopedia.openBestiaryByRaceIdOrName(raceId, creatureName)
	if openBestiaryByRaceIdOrName then
		return openBestiaryByRaceIdOrName(raceId, creatureName)
	end
	return false
end

function Cyclopedia.rememberBestiaryUnlock(raceId, progress, outfit)
	if rememberBestiaryUnlock then
		rememberBestiaryUnlock(raceId, progress, outfit)
	end
end

function Cyclopedia.openBestiaryCreature(creature)
	if openBestiaryCreature then
		return openBestiaryCreature(creature)
	end
	return false
end

function Cyclopedia.isBestiaryCreatureUnlocked(creature)
	if isBestiaryCreatureUnlocked then
		return isBestiaryCreatureUnlocked(creature)
	end
	return false
end

function Cyclopedia.ensureBestiaryCreatureLookup(creature)
	if ensureBestiaryCreatureLookup then
		ensureBestiaryCreatureLookup(creature)
	end
end

function toggleTracker()
	if toggleBestiaryTracker then
		toggleBestiaryTracker()
	end
end

local function getCyclopediaTabButtons()
	return { items, bestiary, charms, map, houses, character }
end

local function resetCyclopediaTabButtons()
	for _, tab in ipairs(getCyclopediaTabButtons()) do
		if tab then
			tab:enable()
			tab:setOn(false)
		end
	end
end

function emptyContentContainer()
	for _, child in ipairs(contentContainer:getChildren()) do
		child:hide()
	end
end

function toggleWindow(type, isBackNavigation)
	if currentType == type then
		return
	end

	if currentType == "map" and Cyclopedia and Cyclopedia.clearMapUI then
		Cyclopedia.clearMapUI()
	end

	if not isBackNavigation and currentType then
		tabStack = tabStack or {}
		table.insert(tabStack, currentType)
		updateBackButton()
	end

	resetCyclopediaTabButtons()

	-- We empty the container
	emptyContentContainer()
	currentType = type

	local function activateTab(tab)
		if not tab then
			return
		end
		tab:setOn(true)
		tab:disable()
	end
		
	if (type == "items") then
		setItemsTabLayout(true)
		activateTab(items)
		if showItems then
			showItems()
		end
	else
		setItemsTabLayout(false)
	end

	if (type == "bestiary") then
		activateTab(bestiary)

		-- Setup the widget
		initBestiary(contentContainer)
	elseif (type == "charms") then
		activateTab(charms)

		-- Setup the charms
		initCharms(contentContainer)
	elseif (type == "map") then
		activateTab(map)

		-- Setup the widget
		initMap(contentContainer)
	elseif (type == "houses") then
		activateTab(houses)
	elseif (type == "character") then
		activateTab(character)
	end
end

function isVisible()
	return window and window:isVisible()
end
