stashWindow = nil
itemsPanel = nil
stashSelectAmount = nil
searchEdit = nil
stashItems = {}
stashItemTiers = {}

local protocolRegistered = false
local SUPPLY_STASH_ITEM_ID = 28750
local stashOpenRequested = false
local OPCODE_SUPPLY_STASH_REQUEST = 0x28
local OPCODE_SUPPLY_STASH_SEND = 0x29
local SUPPLY_STASH_DETAILS_MARKER = 0x5354
local ACTION_OPEN = 1
local ACTION_STOW_ALL = 2
local ACTION_WITHDRAW = 3

local function sendSupplyRequest(action, itemId, count, tier)
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return
	end

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_SUPPLY_STASH_REQUEST)
	msg:addU8(action)
	if action == ACTION_WITHDRAW then
		if not itemId or not count then
			return
		end

		msg:addU16(itemId)
		msg:addU32(count)
		msg:addU8(tier or 0)
	end
	protocolGame:send(msg)
end

local function parseSupplyStashDetails(msg)
	if msg:getUnreadSize() < 2 then
		return
	end

	local marker = msg:peekU16()
	if marker ~= SUPPLY_STASH_DETAILS_MARKER and marker ~= 0x5353 and marker ~= 0x0053 and marker ~= 0x5300 then
		return
	end

	msg:getU16()
	if msg:getUnreadSize() < 2 then
		return
	end

	local detailCount = msg:getU16()
	for _ = 1, detailCount do
		if msg:getUnreadSize() < 5 then
			break
		end

		msg:getU16()
		msg:getString()
		msg:getU16()
		msg:getU8()
		if msg:getUnreadSize() >= 4 then
			msg:getU32()
		end
	end
end

local function onSupplyStashPacket(protocol, msg)
	local items = {}
	local count = msg:getU16()
	for _ = 1, count do
		if msg:getUnreadSize() < 7 then
			break
		end

		table.insert(items, {
			msg:getU16(),
			msg:getU32(),
			msg:getU8()
		})
	end

	if msg:getUnreadSize() >= 2 then
		msg:getU16()
	end

	parseSupplyStashDetails(msg)

	local showWindow = stashOpenRequested
	stashOpenRequested = false

	if msg:getUnreadSize() >= 1 then
		showWindow = showWindow or msg:getU8() == 1
	end

	if msg.skipBytes and msg:getUnreadSize() > 0 then
		msg:skipBytes(msg:getUnreadSize())
	end

	if showWindow then
		openStash(items)
	else
		refreshStash(items)
	end
	return true
end

local function onStashUse(_pos, itemId)
	if itemId == SUPPLY_STASH_ITEM_ID then
		stashOpenRequested = true
	end
end

local function registerProtocol()
	if protocolRegistered then
		return
	end

	ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
	ProtocolGame.registerOpcode(OPCODE_SUPPLY_STASH_SEND, onSupplyStashPacket)
	protocolRegistered = true
end

local function unregisterProtocol()
	if not protocolRegistered then
		return
	end

	ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
	protocolRegistered = false
end

local function onStashGameEnd()
	stashOpenRequested = false
	unregisterProtocol()
	onSupplyStashClose()
end

local uiItemDragLeaveHooked = false
local originalUIItemOnDragLeave

local function getDraggedStashItem(widget)
	local item = widget and widget.currentDragThing
	if item and item.isItem and item:isItem() then
		return item
	end

	if widget and widget.getItem then
		local ok, widgetItem = pcall(function()
			return widget:getItem()
		end)
		if ok and widgetItem and widgetItem.isItem and widgetItem:isItem() then
			return widgetItem
		end
	end

	return nil
end

local function isMouseOverStashWindow(mousePos)
	if not stashWindow or stashWindow:isHidden() or not mousePos then
		return false
	end

	if itemsPanel and itemsPanel:containsPoint(mousePos) then
		return true
	end

	return stashWindow:containsPoint(mousePos)
end

local function stowDraggedItem(item)
	if not item then
		return false
	end

	if modules.game_interface and modules.game_interface.stashItem then
		modules.game_interface.stashItem(item)
	else
		local count = item:getCount() or 1
		g_game.stashStowItem(item:getPosition(), item:getId(), count, item:getStackPos(), 0)
	end

	return true
end

local function tryStowDraggedItem(draggedWidget, mousePos)
	if not isMouseOverStashWindow(mousePos) then
		return false
	end

	return stowDraggedItem(getDraggedStashItem(draggedWidget))
end

local function setupStashDropTarget(widget)
	if not widget or widget._stashDropHooked then
		return
	end

	widget._stashDropHooked = true

	function widget:onDrop(draggedWidget, mousePos)
		if tryStowDraggedItem(draggedWidget, mousePos) then
			return true
		end

		return false
	end
end

local function setupStashDragHooks()
	if uiItemDragLeaveHooked or not UIItem then
		return
	end

	uiItemDragLeaveHooked = true
	originalUIItemOnDragLeave = UIItem.onDragLeave

	function UIItem:onDragLeave(droppedWidget, mousePos)
		if not droppedWidget and tryStowDraggedItem(self, mousePos) then
			if originalUIItemOnDragLeave then
				originalUIItemOnDragLeave(self, droppedWidget, mousePos)
			end
			return true
		end

		if originalUIItemOnDragLeave then
			return originalUIItemOnDragLeave(self, droppedWidget, mousePos)
		end

		return false
	end
end
STASH_SLOT_BATCH_SIZE = 20
STASH_CHUNKED_THRESHOLD = 20
STASH_COMBO_DISPLAY_CHAR_LIMIT = 24

local stashRenderEvent
local stashRenderGeneration = 0
local stashPendingSearchFocus = false
local stashOverlayReturn = false
local stashOverlayCyclopediaHide
local stashOverlayMarketHooked = false
local clearStashOverlayHooks, restoreStashFromOverlay, hideStashForOverlay

local function cancelStashRender()
	if stashRenderEvent then
		removeEvent(stashRenderEvent)

		stashRenderEvent = nil
	end

	if itemsPanel then
		local layout = itemsPanel:getLayout()

		if layout and layout:isUpdateDisabled() then
			layout:enableUpdates()
		end
	end
end

local function formatStashComboDisplayText(text)
	if not text then
		return ""
	end

	if #text <= STASH_COMBO_DISPLAY_CHAR_LIMIT then
		return text
	end

	return string.sub(text, 1, STASH_COMBO_DISPLAY_CHAR_LIMIT) .. "..."
end

local function refreshStashComboDisplay(comboBox)
	if not comboBox then
		return
	end

	local option = comboBox:getCurrentOption()

	if option and option.text then
		comboBox:setText(formatStashComboDisplayText(option.text))
		comboBox:setTooltip(option.text)
	else
		comboBox:setTooltip("")
	end
end

local function applyStashComboMenuOptionTooltips(menu, options)
	if not menu or not options then
		return
	end

	local optionWidgets

	if menu.scrollArea then
		optionWidgets = menu.scrollArea:getChildren()
	else
		optionWidgets = menu:getChildren()
	end

	for i, widget in ipairs(optionWidgets) do
		local fullText = options[i] and options[i].text

		if fullText and #fullText > STASH_COMBO_DISPLAY_CHAR_LIMIT then
			widget:setTooltip(fullText)
		else
			widget:setTooltip("")
		end
	end
end

local function openStashComboPopupMenu(comboBox)
	local menu

	if comboBox.menuScroll then
		menu = g_ui.createWidget(comboBox:getStyleName() .. "PopupScrollMenu")

		menu:setHeight(comboBox.menuHeight)

		if comboBox.menuScrollStep > 0 then
			menu:setScrollbarStep(comboBox.menuScrollStep)
		end
	else
		menu = g_ui.createWidget(comboBox:getStyleName() .. "PopupMenu")
	end

	menu:setId(comboBox:getId() .. "PopupMenu")

	for _, option in ipairs(comboBox.options) do
		menu:addOption(formatStashComboDisplayText(option.text), function()
			comboBox:setCurrentOption(option.text)
		end)
	end

	applyStashComboMenuOptionTooltips(menu, comboBox.options)
	menu:setWidth(comboBox:getWidth())
	menu:display({
		x = comboBox:getX(),
		y = comboBox:getY() + comboBox:getHeight()
	})
	connect(menu, {
		onDestroy = function()
			comboBox:setOn(false)
		end
	})
	comboBox:setOn(true)
end

local function releaseStashWindowFocus()
	if searchEdit and not searchEdit:isDestroyed() then
		pcall(function()
			searchEdit:ungrabKeyboard()
		end)
		pcall(function()
			searchEdit:setCursorVisible(false)
		end)
	end

	if stashWindow and not stashWindow:isDestroyed() then
		pcall(function()
			stashWindow:ungrabKeyboard()
		end)
	end

	pcall(function()
		modules.game_interface.getRootPanel():focus()
	end)
end

local function focusStashSearchEdit()
	if not searchEdit or searchEdit:isDestroyed() then
		return
	end

	if not stashWindow or stashWindow:isHidden() then
		return
	end

	searchEdit:setFocusable(true)
	stashWindow:raise()
	searchEdit:focus()
	pcall(function()
		searchEdit:grabKeyboard()
	end)
	pcall(function()
		searchEdit:setEditable(true)
		searchEdit:setCursorVisible(true)
		searchEdit:setCursorPos(-1)
	end)
end

local function setupStashSearchEdit()
	if not searchEdit or searchEdit._stashSearchSetup then
		return
	end

	searchEdit._stashSearchSetup = true

	searchEdit:setFocusable(true)

	function searchEdit.onFocusChange(widget, focused)
		if focused then
			stashPendingSearchFocus = false

			pcall(function()
				widget:grabKeyboard()
			end)
			pcall(function()
				widget:setCursorVisible(true)
			end)
		else
			pcall(function()
				widget:ungrabKeyboard()
			end)
		end
	end

	function searchEdit.onKeyDown(widget, keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardNoModifier then
			return false
		end

		if keyCode == KeyEscape then
			onSupplyStashClose()

			return true
		end

		return false
	end
end

local function setupStashComboDisplayTruncation(comboBox)
	if not comboBox or comboBox._stashDisplayTruncationHooked then
		return
	end

	comboBox._stashDisplayTruncationHooked = true

	local baseSetCurrentOption = comboBox.setCurrentOption

	function comboBox:setCurrentOption(text, dontSignal)
		baseSetCurrentOption(self, text, dontSignal)
		refreshStashComboDisplay(self)
	end

	local baseSetCurrentIndex = comboBox.setCurrentIndex

	function comboBox:setCurrentIndex(index)
		baseSetCurrentIndex(self, index)
		refreshStashComboDisplay(self)
	end

	function comboBox:onMousePress(mousePos, mouseButton)
		openStashComboPopupMenu(self)

		return true
	end

	refreshStashComboDisplay(comboBox)
end

filterSearch = nil
filterTraderNpc = nil
filterOrganize = nil
filterCategoryMap = {}
STASH_TRADER_NPCS = {
	"Alaistar",
	"Alesar",
	"Alexander",
	"Arkulius",
	"Asnarus",
	"Asphota",
	"Augustin",
	"Avan",
	"Brengus",
	"Chondur",
	"Dal the Huntress",
	"Domizian",
	"Esrik",
	"Fadil",
	"Fiona",
	"Flint",
	"Gladys",
	"Gnomission",
	"Grizzly Adams",
	"Haroun",
	"Inigo",
	"Irmana",
	"Khanna",
	"Kiru",
	"Lailene",
	"Luna",
	"Malunga",
	"Mugruu",
	"Nah'bob",
	"Rafzan",
	"Rashid",
	"Rock in a Hard Place",
	"Tallia",
	"Tamoril",
	"Tamru",
	"Tarun",
	"Telas",
	"Tothdral",
	"Valindara",
	"Yaman",
	"Yasir"
}

function populateTraderNpcComboBox(comboBox, options)
	if not comboBox then
		return
	end

	options = options or {}

	local allOption = options.allOption or tr("No Trader Selected")
	local sellToPrefix = options.sellToPrefix == true

	comboBox:clearOptions()
	comboBox:addOption(allOption)

	for _, name in ipairs(STASH_TRADER_NPCS) do
		local label = sellToPrefix and tr("Sell to " .. name) or name

		comboBox:addOption(label)
	end

	if options.setCurrent ~= false then
		comboBox:setCurrentOption(allOption, true)
	end
end

function itemCanBeSoldToTrader(thingType, traderNpcName)
	if not traderNpcName or traderNpcName == "" then
		return true
	end

	if not thingType or not thingType.getNpcSaleData then
		return false
	end

	local npcSaleData = thingType:getNpcSaleData()

	if not npcSaleData then
		return false
	end

	local traderNpc = traderNpcName:lower()

	for _, npcData in pairs(npcSaleData) do
		if type(npcData.name) == "string" and npcData.name:lower() == traderNpc and npcData.buyPrice and npcData.buyPrice > 0 then
			return true
		end
	end

	return false
end

local STASH_FILTER_OPTIONS_ORDER = {
	"Show All",
	"Show Amulets",
	"Show Armors",
	"Show Boots",
	"Show Containers",
	"Show Creature Products",
	"Show Decoration",
	"Show Food",
	"Show Helmets and Hats",
	"Show Legs",
	"Show Others",
	"Show Potions",
	"Show Rings",
	"Show Runes",
	"Show Shields",
	"Show Soul Cores",
	"Show Tools",
	"Show Valuables",
	"Show Weapons: All",
	"Show Weapons: Ammo",
	"Show Weapons: Axes",
	"Show Weapons: Clubs",
	"Show Weapons: Distance",
	"Show Weapons: Fist",
	"Show Weapons: Swords",
	"Show Weapons: Wands"
}
local STASH_CATEGORY_ID_TO_KEY = {
	[MarketCategory.CreatureProducts or MarketCategory.CreatureProducs] = "creature products",
	[MarketCategory.SoulCores or MarketCategory.SoulCore] = "soul cores"
}

if MarketCategory.FistWeapons then
	STASH_CATEGORY_ID_TO_KEY[MarketCategory.FistWeapons] = "fist weapons"
end
local filterCategorys = {
	["soul cores"] = "Show Soul Cores",
	["creature products"] = "Show Creature Products",
	["wands and rods"] = "Show Weapons: Wands",
	swords = "Show Weapons: Swords",
	["distance weapons"] = "Show Weapons: Distance",
	clubs = "Show Weapons: Clubs",
	axes = "Show Weapons: Axes",
	ammunition = "Show Weapons: Ammo",
	weapons = "Show Weapons: All",
	valuables = "Show Valuables",
	tools = "Show Tools",
	shields = "Show Shields",
	runes = "Show Runes",
	rings = "Show Rings",
	potions = "Show Potions",
	others = "Show Others",
	legs = "Show Legs",
	["helmets and hats"] = "Show Helmets and Hats",
	food = "Show Food",
	decoration = "Show Decoration",
	containers = "Show Containers",
	boots = "Show Boots",
	armors = "Show Armors",
	amulets = "Show Amulets",
	["fist weapons"] = "Show Weapons: Fist"
}
local weaponCategoryKeys = {
	"ammunition",
	"axes",
	"clubs",
	"distance weapons",
	"fist weapons",
	"swords",
	"wands and rods"
}

local function getStashCategoryKey(categoryId)
	if STASH_CATEGORY_ID_TO_KEY[categoryId] then
		return STASH_CATEGORY_ID_TO_KEY[categoryId]
	end

	if MarketCategoryStrings and MarketCategoryStrings[categoryId] then
		return MarketCategoryStrings[categoryId]:lower()
	end

	return ""
end

local digitKeys = {
	["2"] = true,
	["1"] = true,
	["0"] = true,
	Numpad9 = "9",
	Numpad8 = "8",
	Numpad7 = "7",
	Numpad6 = "6",
	Numpad5 = "5",
	Numpad4 = "4",
	Numpad3 = "3",
	Numpad2 = "2",
	Numpad1 = "1",
	Numpad0 = "0",
	["Num+9"] = "9",
	["Num+8"] = "8",
	["Num+7"] = "7",
	["Num+6"] = "6",
	["Num+5"] = "5",
	["Num+4"] = "4",
	["Num+3"] = "3",
	["Num+2"] = "2",
	["Num+1"] = "1",
	["Num+0"] = "0",
	["9"] = true,
	["8"] = true,
	["7"] = true,
	["6"] = true,
	["5"] = true,
	["4"] = true,
	["3"] = true
}

local function getStashSlotItemWidget(slotWidget)
	if not slotWidget then
		return nil
	end

	if slotWidget.item and slotWidget.item:getClassName() == "UIItem" then
		return slotWidget.item
	end

	return nil
end

local function applyStashSlotAmount(slotWidget, amount)
	local amountLabel = slotWidget and slotWidget.amount

	if not amountLabel then
		return
	end

	if amount and amount > 0 then
		amountLabel:setText(tostring(amount))
		amountLabel:setVisible(true)
	else
		amountLabel:setText("")
		amountLabel:setVisible(false)
	end
end

local function applyStashSlotVisuals(slotWidget, itemId, amount, tier)
	if not slotWidget then
		return
	end

	local itemUi = getStashSlotItemWidget(slotWidget)

	if not itemUi then
		return
	end

	itemUi:setVirtual(true)

	local item = Item.create(itemId)

	if modules.game_containers and modules.game_containers.applyContainerSlotVisuals then
		modules.game_containers.applyContainerSlotVisuals(slotWidget, item)
	else
		itemUi:setItem(item)

		if slotWidget.rarity then
			ItemsDatabase.setRarityItem(slotWidget.rarity, item)
			ItemsDatabase.applyContainerRarityStackOrder(slotWidget)
		end

		local itemTier = tier or stashItemTiers[itemId] or 0
		if itemTier > 0 then
			ItemsDatabase.setTier(slotWidget, itemTier)
		else
			ItemsDatabase.setTier(slotWidget, item)
		end
	end

	applyStashSlotAmount(slotWidget, amount)
end

local function getStashMarketValue(thingType)
	if not thingType then
		return 0
	end

	if thingType.getMeanPrice then
		local success, result = pcall(function()
			return thingType:getMeanPrice()
		end)

		if success and result then
			return result
		end
	end

	if thingType.getId then
		local itemId = thingType:getId()
		local cyclopediaItems = modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia and modules.game_cyclopedia.Cyclopedia.Items

		if itemId and cyclopediaItems and cyclopediaItems.getMarketOfferAverages then
			return cyclopediaItems.getMarketOfferAverages(itemId) or 0
		end
	end

	return 0
end

local otherOptions = {
	{
		name = "Name (A-Z)",
		func = function(a, b)
			local thingTypeA = g_things.getThingType(a, 0)
			local thingTypeB = g_things.getThingType(b, 0)
			local nameA = thingTypeA and thingTypeA:getName():lower() or ""
			local nameB = thingTypeB and thingTypeB:getName():lower() or ""

			return nameA < nameB
		end
	},
	{
		name = "Name (Z-A)",
		func = function(a, b)
			local thingTypeA = g_things.getThingType(a, 0)
			local thingTypeB = g_things.getThingType(b, 0)
			local nameA = thingTypeA and thingTypeA:getName():lower() or ""
			local nameB = thingTypeB and thingTypeB:getName():lower() or ""

			return nameB < nameA
		end
	},
	{
		name = "Market Value (High to Low)",
		func = function(a, b)
			local valueA = getStashMarketValue(g_things.getThingType(a, 0))
			local valueB = getStashMarketValue(g_things.getThingType(b, 0))

			return valueB < valueA
		end
	},
	{
		name = "Market Value (Low to High)",
		func = function(a, b)
			local valueA = getStashMarketValue(g_things.getThingType(a, 0))
			local valueB = getStashMarketValue(g_things.getThingType(b, 0))

			return valueA < valueB
		end
	},
	{
		name = "Total Market Value (High to Low)",
		func = function(a, b)
			local valueA = getStashMarketValue(g_things.getThingType(a, 0)) * (stashItems[a] or 0)
			local valueB = getStashMarketValue(g_things.getThingType(b, 0)) * (stashItems[b] or 0)

			return valueB < valueA
		end
	},
	{
		name = "Total Market Value (Low to High)",
		func = function(a, b)
			local valueA = getStashMarketValue(g_things.getThingType(a, 0)) * (stashItems[a] or 0)
			local valueB = getStashMarketValue(g_things.getThingType(b, 0)) * (stashItems[b] or 0)

			return valueA < valueB
		end
	},
	{
		name = "Sell To Value (High to Low)",
		func = function(a, b)
			local valueA = getHighestNpcSaleValue(g_things.getThingType(a, 0))
			local valueB = getHighestNpcSaleValue(g_things.getThingType(b, 0))

			return valueB < valueA
		end
	},
	{
		name = "Sell To Value (Low to High)",
		func = function(a, b)
			local valueA = getHighestNpcSaleValue(g_things.getThingType(a, 0))
			local valueB = getHighestNpcSaleValue(g_things.getThingType(b, 0))

			return valueA < valueB
		end
	},
	{
		name = "Total Sell To Value (High to Low)",
		func = function(a, b)
			local valueA = getHighestNpcSaleValue(g_things.getThingType(a, 0)) * (stashItems[a] or 0)
			local valueB = getHighestNpcSaleValue(g_things.getThingType(b, 0)) * (stashItems[b] or 0)

			return valueB < valueA
		end
	},
	{
		name = "Total Sell To Value (Low to High)",
		func = function(a, b)
			local valueA = getHighestNpcSaleValue(g_things.getThingType(a, 0)) * (stashItems[a] or 0)
			local valueB = getHighestNpcSaleValue(g_things.getThingType(b, 0)) * (stashItems[b] or 0)

			return valueA < valueB
		end
	},
	{
		name = "Quantity (High to Low)",
		func = function(a, b)
			return (stashItems[a] or 0) > (stashItems[b] or 0)
		end
	},
	{
		name = "Quantity (Low to High)",
		func = function(a, b)
			return (stashItems[a] or 0) < (stashItems[b] or 0)
		end
	}
}

local function applyStashOrganizeSort(sortedItemIds)
	local organize = filterOrganize and filterOrganize:lower() or "name (a-z)"

	for _, option in ipairs(otherOptions) do
		if option.name:lower() == organize then
			table.sort(sortedItemIds, option.func)

			break
		end
	end
end

function init()
	g_ui.importStyle("game_stash")
	connect(g_game, {
		onEnterGame = registerProtocol,
		onPendingGame = registerProtocol,
		onGameStart = registerProtocol,
		onGameEnd = onStashGameEnd,
		onUse = onStashUse
	})
	connect(LocalPlayer, {
		onPositionChange = onPositionChange
	})

	stashWindow = g_ui.createWidget("StashWindow", rootWidget)

	stashWindow:hide()

	function stashWindow:onKeyDown(keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardNoModifier then
			return false
		end

		if keyCode == KeyEscape then
			onSupplyStashClose()

			return true
		end

		return false
	end

	itemsPanel = stashWindow:recursiveGetChildById("itemsPanel")
	searchEdit = stashWindow:recursiveGetChildById("searchEdit")

	setupStashSearchEdit()
	setupStashComboDisplayTruncation(stashWindow:recursiveGetChildById("showFilterComboBox"))
	setupStashComboDisplayTruncation(stashWindow:recursiveGetChildById("showTraderNpc"))
	setupStashComboDisplayTruncation(stashWindow:recursiveGetChildById("showOrganize"))
	setupStashDragHooks()
	setupStashDropTarget(stashWindow)
	setupStashDropTarget(stashWindow:recursiveGetChildById("mainTabContent"))
	setupStashDropTarget(itemsPanel)

	if g_game.isOnline() then
		registerProtocol()
	end
end

function terminate()
	disconnect(g_game, {
		onEnterGame = registerProtocol,
		onPendingGame = registerProtocol,
		onGameStart = registerProtocol,
		onGameEnd = onStashGameEnd,
		onUse = onStashUse
	})
	disconnect(LocalPlayer, {
		onPositionChange = onPositionChange
	})

	stashOverlayReturn = false

	unregisterProtocol()
	clearStashOverlayHooks()
	cancelStashRender()

	if stashWindow then
		g_modalManager.hide(stashWindow)
		stashWindow:destroy()
	end
end

function onPositionChange(creature, newPos, oldPos)
	if creature == g_game.getLocalPlayer() then
		stashOverlayReturn = false

		clearStashOverlayHooks()
		g_modalManager.hide(stashWindow)
		stashWindow:hide()
		resetSelectAmount()
		releaseStashWindowFocus()
	end
end

function getHighestNpcSaleValue(thingType)
	local maxValue = 0

	if thingType and thingType.getNpcSaleData then
		local npcSaleData = thingType:getNpcSaleData()

		if npcSaleData then
			for _, npcData in pairs(npcSaleData) do
				if npcData.buyPrice and maxValue < npcData.buyPrice then
					maxValue = npcData.buyPrice
				end
			end
		end
	end

	return maxValue
end

local function rebuildFilterCategoryMap()
	filterCategoryMap = {}

	for _, option in ipairs(STASH_FILTER_OPTIONS_ORDER) do
		filterCategoryMap[#filterCategoryMap + 1] = option
	end
end

local function populateStashComboBoxSilently(comboBox, options, selectedOption)
	if not comboBox then
		return
	end

	local savedHandler = comboBox.onOptionChange

	comboBox.onOptionChange = nil

	comboBox:clearOptions()

	for _, option in ipairs(options) do
		comboBox:addOption(option)
	end

	if selectedOption then
		comboBox:setCurrentOption(selectedOption, true)
		refreshStashComboDisplay(comboBox)
	end

	comboBox.onOptionChange = savedHandler
end

local function resetStashFilters()
	filterSearch = nil
	filterTraderNpc = nil
	filterOrganize = nil

	if not stashWindow or stashWindow:isDestroyed() then
		return
	end

	local showFilterComboBox = stashWindow:recursiveGetChildById("showFilterComboBox")

	if showFilterComboBox and showFilterComboBox:getOptionsCount() > 0 then
		showFilterComboBox:setCurrentOption(tr("Show All"), true)
		refreshStashComboDisplay(showFilterComboBox)
	end

	local showTraderNpcComboBox = stashWindow:recursiveGetChildById("showTraderNpc")

	if showTraderNpcComboBox and showTraderNpcComboBox:getOptionsCount() > 0 then
		showTraderNpcComboBox:setCurrentOption(tr("No Trader Selected"), true)
		refreshStashComboDisplay(showTraderNpcComboBox)
	end

	local showOrganizeComboBox = stashWindow:recursiveGetChildById("showOrganize")

	if showOrganizeComboBox and showOrganizeComboBox:getOptionsCount() > 0 then
		showOrganizeComboBox:setCurrentOption(tr("Name (A-Z)"), true)
		refreshStashComboDisplay(showOrganizeComboBox)
	end
end

local function setStashItemsFromPacket(items)
	stashItems = {}
	stashItemTiers = {}

	for i = 1, #items do
		local itemId = items[i][1]
		local amount = items[i][2]
		local tier = items[i][3] or 0

		stashItems[itemId] = amount
		if tier > 0 then
			stashItemTiers[itemId] = tier
		end
	end
end

function refreshStash(items)
	setStashItemsFromPacket(items)

	if stashWindow and not stashWindow:isHidden() then
		renderItems(0)
	end
end

function openStash(items)
	resetStashFilters()
	setStashItemsFromPacket(items)

	rebuildFilterCategoryMap()

	local filterOptions = {}

	for _, v in ipairs(filterCategoryMap) do
		filterOptions[#filterOptions + 1] = tr(v)
	end

	populateStashComboBoxSilently(stashWindow:recursiveGetChildById("showFilterComboBox"), filterOptions, tr("Show All"))

	local organizeOptions = {}

	for _, v in ipairs(otherOptions) do
		organizeOptions[#organizeOptions + 1] = tr(v.name)
	end

	showOrganizeComboBox = stashWindow:recursiveGetChildById("showOrganize")

	populateStashComboBoxSilently(showOrganizeComboBox, organizeOptions, tr("Name (A-Z)"))

	if stashWindow:isHidden() then
		stashWindow:show()
	end

	g_modalManager.show(stashWindow)

	stashPendingSearchFocus = true

	scheduleEvent(function()
		focusStashSearchEdit()
	end, 0)
	renderItems(0)
end

function resetSelectAmount()
	if stashSelectAmount then
		g_modalManager.hide(stashSelectAmount)
		stashSelectAmount:destroy()

		stashSelectAmount = nil
	end
end

function resetItems()
	cancelStashRender()

	if itemsPanel then
		itemsPanel:destroyChildren()
	end
end

function prepareRetrieveAmount(itemId, itemAmount, onConfirm, options)
	options = options or {}

	if not itemId or not itemAmount or itemAmount <= 0 then
		return
	end

	if itemAmount == 1 then
		if onConfirm then
			onConfirm(1)
		end

		return
	end

	if options.hideStashOnOpen and stashWindow and not stashWindow:isHidden() then
		g_modalManager.hide(stashWindow)
		stashWindow:hide()
	end

	resetSelectAmount()

	stashSelectAmount = g_ui.createWidget("StashSelectAmount", rootWidget)

	g_modalManager.show(stashSelectAmount)

	local itemSlot = stashSelectAmount:getChildById("itemSlot")

	applyStashSlotVisuals(itemSlot, itemId, itemAmount)

	local itemUi = getStashSlotItemWidget(itemSlot)
	local scrollbar = stashSelectAmount:getChildById("countScrollBar")

	scrollbar:setMaximum(itemAmount)
	scrollbar:setMinimum(1)
	scrollbar:setValue(itemAmount)
	g_keyboard.bindKeyPress("Up", function()
		scrollbar:setValue(scrollbar:getValue() + 10)
	end, stashSelectAmount)
	g_keyboard.bindKeyPress("Down", function()
		scrollbar:setValue(scrollbar:getValue() - 10)
	end, stashSelectAmount)
	g_keyboard.bindKeyPress("Right", function()
		scrollbar:onIncrement()
	end, stashSelectAmount)
	g_keyboard.bindKeyPress("Left", function()
		scrollbar:onDecrement()
	end, stashSelectAmount)
	g_keyboard.bindKeyPress("PageUp", function()
		scrollbar:setValue(scrollbar:getMaximum())
	end, stashSelectAmount)
	g_keyboard.bindKeyPress("PageDown", function()
		scrollbar:setValue(scrollbar:getMinimum())
	end, stashSelectAmount)

	local typedNumber = ""
	local typingEvent

	local function resetTypedNumber()
		typedNumber = ""
	end

	for key, digit in pairs(digitKeys) do
		if digit == true then
			digit = key
		end

		g_keyboard.bindKeyPress(key, function()
			typedNumber = typedNumber .. digit

			local val = tonumber(typedNumber)

			if val and val > 0 then
				if val > itemAmount then
					val = itemAmount
				end

				scrollbar:setValue(val)
			end

			if typingEvent then
				removeEvent(typingEvent)
			end

			typingEvent = scheduleEvent(function()
				typedNumber = ""
			end, 250)
		end, stashSelectAmount)
	end

	function scrollbar:onIncrement()
		resetTypedNumber()
		self:setValue(self:getValue() + 1)
	end

	function scrollbar:onDecrement()
		resetTypedNumber()
		self:setValue(self:getValue() - 1)
	end

	function scrollbar:onValueChange(value)
		resetTypedNumber()
		applyStashSlotVisuals(itemSlot, itemId, value)
	end

	local okButton = stashSelectAmount:getChildById("buttonOk")

	local function confirmFunc()
		local count = scrollbar:getValue()
		if not count or count < 1 then
			count = itemAmount
		end

		resetSelectAmount()

		if onConfirm then
			onConfirm(count)
		end
	end

	local function cancelFunc()
		resetSelectAmount()

		if options.onCancel then
			options.onCancel()
		end
	end

	stashSelectAmount.onEnter = confirmFunc
	stashSelectAmount.onEscape = cancelFunc
	okButton.onClick = confirmFunc
	stashSelectAmount:getChildById("buttonCancel").onClick = cancelFunc
end

local function showStashWindow()
	if not stashWindow or stashWindow:isDestroyed() then
		return
	end

	if stashWindow:isHidden() then
		stashWindow:show()
	end

	g_modalManager.show(stashWindow)
end

function prepareWithdraw(itemId, itemAmount)
	prepareRetrieveAmount(itemId, itemAmount, function(count)
		sendSupplyRequest(ACTION_WITHDRAW, itemId, count, stashItemTiers[itemId] or 0)
		showStashWindow()
	end)
end

function clearStashOverlayHooks()
	local cyc = modules.game_cyclopedia

	if cyc and stashOverlayCyclopediaHide then
		cyc.hide = stashOverlayCyclopediaHide
		stashOverlayCyclopediaHide = nil
	end

	if stashOverlayMarketHooked then
		disconnect(g_game, {
			onMarketLeave = onStashOverlayMarketLeave
		})

		stashOverlayMarketHooked = false
	end
end

function restoreStashFromOverlay()
	if not stashOverlayReturn then
		clearStashOverlayHooks()

		return
	end

	stashOverlayReturn = false

	clearStashOverlayHooks()

	if not g_game.isOnline() then
		return
	end

	if not stashWindow or stashWindow:isDestroyed() then
		return
	end

	if not next(stashItems) then
		return
	end

	stashWindow:show()
	g_modalManager.show(stashWindow)
	scheduleEvent(function()
		focusStashSearchEdit()
	end, 0)
end

function onStashOverlayMarketLeave()
	if stashOverlayReturn then
		addEvent(restoreStashFromOverlay)
	end
end

function hideStashForOverlay(target)
	if stashWindow and not stashWindow:isDestroyed() and not stashWindow:isHidden() then
		g_modalManager.hide(stashWindow)
		stashWindow:hide()
	end

	stashOverlayReturn = true

	clearStashOverlayHooks()

	if target == "cyclopedia" then
		local cyc = modules.game_cyclopedia

		if cyc and cyc.hide and not stashOverlayCyclopediaHide then
			stashOverlayCyclopediaHide = cyc.hide

			function cyc.hide(...)
				stashOverlayCyclopediaHide(...)

				if stashOverlayReturn then
					addEvent(restoreStashFromOverlay)
				end
			end
		end
	elseif target == "market" then
		connect(g_game, {
			onMarketLeave = onStashOverlayMarketLeave
		})

		stashOverlayMarketHooked = true
	end
end

local function showStashItemInMarket(itemId)
	local market = modules.game_market

	if not market then
		return
	end

	local item = Item.create(itemId, 1)

	if not item then
		return
	end

	hideStashForOverlay("market")

	if market.showItemInMarket then
		market.showItemInMarket(item)
	elseif market.onRedirect then
		g_game.sendMarketAction(1)
		scheduleEvent(function()
			if market.show then
				market.show()
			end

			market.onRedirect(item)
		end, 400)
	end
end

local function openStashItemContextMenu(mousePos, slotInfo)
	local menu = g_ui.createWidget("GamePopupMenu")

	menu:setGameMenu(true)

	local itemId = slotInfo.itemId
	local amount = slotInfo.amount
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)

	menu:addOption(tr("Retrieve"), function()
		prepareWithdraw(itemId, amount)
	end)

	local modCyc = modules.game_cyclopedia
	local cycApi = modCyc and modCyc.Cyclopedia

	if thingType and cycApi and cycApi.openItem and (not cycApi.canShowInItemsTab or cycApi.canShowInItemsTab(thingType)) then
		menu:addSeparator()
		menu:addOption(tr("Cyclopedia"), function()
			hideStashForOverlay("cyclopedia")

			if modCyc.show then
				modCyc.show("items")
			end

			cycApi.openItem(itemId)
		end)
	end

	local isMarketable = thingType and thingType.isMarketable and thingType:isMarketable()

	if isMarketable and modules.game_market and modules.game_market.onRedirect then
		menu:addSeparator()
		menu:addOption(tr("Show in Market"), function()
			showStashItemInMarket(itemId)
		end)
	end

	if g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot and modules.game_quickloot.QuickLoot then
		local quickLoot = modules.game_quickloot.QuickLoot
		local lootExists = quickLoot.lootExists(itemId)

		menu:addSeparator()

		if lootExists then
			menu:addOption(tr("Remove from Loot List"), function()
				quickLoot.removeLootList(itemId)
			end)
		else
			menu:addOption(tr("Add to Loot List"), function()
				quickLoot.addLootList(itemId)
			end)
		end
	end

	menu:display(mousePos)
end

local function createStashSlotWidget(slotInfo)
	local slotWidget = g_ui.createWidget("ContainerItemSlot", itemsPanel)

	slotWidget:setMargin(0)
	applyStashSlotVisuals(slotWidget, slotInfo.itemId, slotInfo.amount, slotInfo.tier)

	if slotInfo.itemName then
		slotWidget:setTooltip(slotInfo.itemName)
	else
		slotWidget:setTooltip("Loading...")
	end

	g_mouse.bindPress(slotWidget, function(mousePos, mouseButton)
		if mouseButton == MouseRightButton or g_keyboard.isCtrlPressed() then
			openStashItemContextMenu(mousePos, slotInfo)

			return
		end

		if mouseButton == MouseLeftButton then
			prepareWithdraw(slotInfo.itemId, slotInfo.amount)
		end
	end)
end

function onStashSearchTextChange()
	renderItems()
end

function renderItems(filter)
	if not g_game.isOnline() then
		stashPendingSearchFocus = false

		return
	end

	cancelStashRender()

	stashRenderGeneration = stashRenderGeneration + 1

	local renderGeneration = stashRenderGeneration

	if itemsPanel then
		itemsPanel:destroyChildren()
	end

	local searchFilter = searchEdit:getText():lower()
	local filterText = filterSearch and filterSearch:lower() or "show all"
	local traderNpc = filterTraderNpc and filterTraderNpc:lower() or "no trader selected"
	local sortedItemIds = {}

	for itemId, _ in pairs(stashItems) do
		table.insert(sortedItemIds, itemId)
	end

	if filter == 2 then
		local prefix = "sell to "

		if traderNpc:sub(1, #prefix) == prefix then
			traderNpc = traderNpc:sub(#prefix + 1)
		end

		if traderNpc == "no trader selected" then
			filter = 0
		end
	end

	applyStashOrganizeSort(sortedItemIds)

	local pendingSlots = {}

	for _, itemId in ipairs(sortedItemIds) do
		local amount = stashItems[itemId]
		local thingType = g_things.getThingType(itemId, 0)

		if thingType then
			local itemName = thingType:getName()

			if not itemName or itemName:lower():find(searchFilter) then
				local categoryName = ""

				if thingType.getMarketData then
					local md = thingType:getMarketData()

					if md and md.category then
						categoryName = getStashCategoryKey(md.category)
					end
				end

				local show = false

				if filterText == "show all" and filter ~= 2 then
					show = true
				elseif filter == 2 then
					if itemCanBeSoldToTrader(thingType, traderNpc) then
						show = true
					end
				elseif filterText == (filterCategorys[categoryName] and filterCategorys[categoryName]:lower()) then
					show = true
				elseif filterText == "show weapons: all" then
					for _, weaponKey in ipairs(weaponCategoryKeys) do
						if categoryName == weaponKey then
							show = true

							break
						end
					end
				end

				if show then
					pendingSlots[#pendingSlots + 1] = {
						itemId = itemId,
						amount = amount,
						tier = stashItemTiers[itemId] or 0,
						itemName = itemName
					}
				end
			end
		end
	end

	local layout = itemsPanel:getLayout()

	layout:disableUpdates()

	local function finishStashRender()
		layout:enableUpdates()
		layout:update()

		if stashPendingSearchFocus then
			stashPendingSearchFocus = false

			scheduleEvent(function()
				if searchEdit and not searchEdit:isFocused() then
					focusStashSearchEdit()
				end
			end, 0)
		end
	end

	local count = #pendingSlots

	if count <= STASH_CHUNKED_THRESHOLD then
		for _, slotInfo in ipairs(pendingSlots) do
			createStashSlotWidget(slotInfo)
		end

		finishStashRender()
	else
		local index = 1

		local function createNextBatch()
			if renderGeneration ~= stashRenderGeneration then
				return
			end

			local endIndex = math.min(index + STASH_SLOT_BATCH_SIZE - 1, count)

			for i = index, endIndex do
				createStashSlotWidget(pendingSlots[i])
			end

			index = endIndex + 1

			if index <= count then
				stashRenderEvent = addEvent(createNextBatch)
			else
				stashRenderEvent = nil

				finishStashRender()
			end
		end

		createNextBatch()
	end
end

function onSupplyStashClose()
	stashItems = {}
	stashItemTiers = {}
	stashPendingSearchFocus = false
	stashOverlayReturn = false

	clearStashOverlayHooks()
	resetStashFilters()
	resetItems()
	resetSelectAmount()

	if searchEdit then
		searchEdit:setText("")
	end

	if not stashWindow:isHidden() then
		g_modalManager.hide(stashWindow)
		stashWindow:hide()
	end

	releaseStashWindowFocus()
end

function onShowFilterOptionChange(option)
	if not searchEdit then
		return
	end

	local filter = option:getCurrentOption().text

	filterSearch = filter:lower()

	renderItems(1)
end

function onShowTraderNpcOptionChange(option)
	if not searchEdit then
		return
	end

	local filter = option:getCurrentOption().text

	filterTraderNpc = filter:lower()

	renderItems(2)
end

function onShowOrganizeOptionChange(option)
	if not searchEdit then
		return
	end

	local filter = option:getCurrentOption().text

	filterOrganize = filter:lower()

	renderItems(3)
end
