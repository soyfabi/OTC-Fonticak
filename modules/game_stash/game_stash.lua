local function debugLog(msg)
end

local window
withdrawWindow = nil
local protocolRegistered = false
local currentItemData = {}
local currentSizeLeft = 0
local itemNameCache = {}
local itemInfoCache = {}
local getItemInfo -- Forward declaration for protocol callback
local searchInput
local categoryFilter
local currentCategoryFilter = "all"
local OPCODE_SUPPLY_STASH_REQUEST = 0x28
local OPCODE_SUPPLY_STASH_SEND = 0x29
local SUPPLY_STASH_DETAILS_MARKER = 0x5353
local SUPPLY_STASH_ITEM_ID = 28750
local ACTION_OPEN = 1
local ACTION_STOW_ALL = 2
local ACTION_WITHDRAW = 3

local CATEGORY_ARMORS = MarketCategory and MarketCategory.Armors or 1
local CATEGORY_AMULETS = MarketCategory and MarketCategory.Amulets or 2
local CATEGORY_BOOTS = MarketCategory and MarketCategory.Boots or 3
local CATEGORY_FOOD = MarketCategory and MarketCategory.Food or 6
local CATEGORY_HELMETS = MarketCategory and MarketCategory.HelmetsHats or 7
local CATEGORY_LEGS = MarketCategory and MarketCategory.Legs or 8
local CATEGORY_OTHERS = MarketCategory and MarketCategory.Others or 9
local CATEGORY_POTIONS = MarketCategory and MarketCategory.Potions or 10
local CATEGORY_RUNES = MarketCategory and MarketCategory.Runes or 12
local CATEGORY_SHIELDS = MarketCategory and MarketCategory.Shields or 13
local CATEGORY_TOOLS = MarketCategory and MarketCategory.Tools or 14
local CATEGORY_VALUABLES = MarketCategory and MarketCategory.Valuables or 15
local CATEGORY_AMMUNITION = MarketCategory and MarketCategory.Ammunition or 16
local CATEGORY_AXES = MarketCategory and MarketCategory.Axes or 17
local CATEGORY_CLUBS = MarketCategory and MarketCategory.Clubs or 18
local CATEGORY_DISTANCE = MarketCategory and MarketCategory.DistanceWeapons or 19
local CATEGORY_SWORDS = MarketCategory and MarketCategory.Swords or 20
local CATEGORY_WANDS = MarketCategory and MarketCategory.WandsRods or 21
local CATEGORY_CREATURE_PRODUCTS = MarketCategory and MarketCategory.CreatureProducs or 24
local CATEGORY_FISTS = MarketCategory and MarketCategory.Unknown1 or 25

local weaponCategories = {
	[CATEGORY_AMMUNITION] = true,
	[CATEGORY_AXES] = true,
	[CATEGORY_CLUBS] = true,
	[CATEGORY_DISTANCE] = true,
	[CATEGORY_SWORDS] = true,
	[CATEGORY_WANDS] = true,
	[CATEGORY_FISTS] = true
}

local categoryOptions = {
	{text = "Show all", data = "all"},
	{text = "Show stackable", data = "stackable"},
	{text = "Show weapons", data = "weapons"},
	{text = "Show ammunition", data = CATEGORY_AMMUNITION},
	{text = "Show axes", data = CATEGORY_AXES},
	{text = "Show clubs", data = CATEGORY_CLUBS},
	{text = "Show distance weapons", data = CATEGORY_DISTANCE},
	{text = "Show swords", data = CATEGORY_SWORDS},
	{text = "Show wands and rods", data = CATEGORY_WANDS},
	{text = "Show fist weapons", data = CATEGORY_FISTS},
	{text = "Show food", data = CATEGORY_FOOD},
	{text = "Show potions", data = CATEGORY_POTIONS},
	{text = "Show runes", data = CATEGORY_RUNES},
	{text = "Show armors", data = CATEGORY_ARMORS},
	{text = "Show amulets", data = CATEGORY_AMULETS},
	{text = "Show boots", data = CATEGORY_BOOTS},
	{text = "Show helmets and hats", data = CATEGORY_HELMETS},
	{text = "Show legs", data = CATEGORY_LEGS},
	{text = "Show shields", data = CATEGORY_SHIELDS},
	{text = "Show tools", data = CATEGORY_TOOLS},
	{text = "Show valuables", data = CATEGORY_VALUABLES},
	{text = "Show creature products", data = CATEGORY_CREATURE_PRODUCTS},
	{text = "Show others", data = CATEGORY_OTHERS}
}


local function sendSupplyRequest(action, itemId, count)
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		debugLog("sendSupplyRequest aborted: protocolGame is nil (action=" .. tostring(action) .. ")")
		return
	end

	debugLog("sendSupplyRequest action=" .. tostring(action) .. ", itemId=" .. tostring(itemId) .. ", count=" .. tostring(count))

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_SUPPLY_STASH_REQUEST)
	msg:addU8(action)
	if action == ACTION_WITHDRAW then
		if not itemId or not count then
			return
		end

		msg:addU16(itemId)
		msg:addU32(count)
	end
	protocolGame:send(msg)
	debugLog("packet sent with opcode=" .. tostring(OPCODE_SUPPLY_STASH_REQUEST))
end

local function getDraggedItem(widget)
	local item = widget and widget.currentDragThing
	if item and item:isItem() then
		return item
	end

	if widget and widget.getItem then
		local ok, widgetItem = pcall(function()
			return widget:getItem()
		end)
		if ok and widgetItem and widgetItem:isItem() then
			return widgetItem
		end
	end

	return nil
end

local isMouseOverSupplyStash

local function showStashDropBlockedMessage()
	if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
		modules.game_textmessage.displayFailureMessage("Put items inside Depot Locker boxes 1 to 15, then use Stow All.")
	end
	return true
end

local function markSupplyStashDropBlocked(widget)
	if widget then
		widget.supplyStashDropBlocked = true
	end
end

local function isSupplyStashWidget(widget)
	while widget do
		if widget == window or widget == itemsContainer or widget == supplyItems or widget.supplyStashDropBlocked then
			return true
		end

		if not widget.getParent then
			break
		end
		widget = widget:getParent()
	end
	return false
end

local function isSupplyStashItemWidget(widget)
	local item = widget and widget.getItem and widget:getItem()
	return item and item:isItem() and item:getId() == SUPPLY_STASH_ITEM_ID
end

function shouldBlockItemDrop(targetWidget, draggedWidget, mousePos)
	if not window or not window:isVisible() then
		return isSupplyStashItemWidget(targetWidget) and getDraggedItem(draggedWidget) ~= nil and showStashDropBlockedMessage()
	end

	local item = getDraggedItem(draggedWidget)
	if not item then
		return false
	end

	if targetWidget and targetWidget.setBorderWidth then
		targetWidget:setBorderWidth(0)
	end

	if isSupplyStashItemWidget(targetWidget) or isSupplyStashWidget(targetWidget) or isMouseOverSupplyStash(mousePos) then
		return showStashDropBlockedMessage()
	end
	return false
end

local function onSupplyDrop(self, widget, mousePos)
	return shouldBlockItemDrop(self, widget, mousePos)
end

function blockItemDrop(self, widget, mousePos)
	return shouldBlockItemDrop(self, widget, mousePos)
end

isMouseOverSupplyStash = function(mousePos)
	if not window or not window:isVisible() or not mousePos then
		return false
	end

	if supplyItems and supplyItems:containsPoint(mousePos) then
		return true
	end
	if itemsContainer and itemsContainer:containsPoint(mousePos) then
		return true
	end
	return window:containsPoint(mousePos)
end

function handleItemDragLeave(draggedWidget, droppedWidget, mousePos)
	if droppedWidget then
		return false
	end
	if not isMouseOverSupplyStash(mousePos) then
		return false
	end

	local item = getDraggedItem(draggedWidget)
	if not item then
		debugLog("dragLeave over stash ignored: dragged widget has no item")
		return false
	end

	return showStashDropBlockedMessage()
end

local function requestOpen()
	debugLog("requestOpen called")
	sendSupplyRequest(ACTION_OPEN)
end

local function setupCategoryFilter()
	if not categoryFilter then
		return
	end

	categoryFilter.onOptionChange = nil
	categoryFilter:clearOptions()
	for _, option in ipairs(categoryOptions) do
		categoryFilter:addOption(option.text, option.data)
	end
	categoryFilter:setCurrentOption("Show all", true)
	categoryFilter.onOptionChange = function(widget, option, data)
		currentCategoryFilter = data or "all"
		debugLog("category changed: " .. tostring(option) .. " data=" .. tostring(currentCategoryFilter))
		refreshItemList()
	end
end

local function showWindow()
	debugLog("showWindow")
	window:show()
	window:raise()
	window:focus()
	modules.game_interface.getRootPanel():focus()
	window:lock()
end

local function hideWindow()
	debugLog("hideWindow")
	window:hide()
	window:unlock()
	modules.game_interface.getRootPanel():focus()
end

local function registerProtocol()
	print(">>> STASH registerProtocol called <<<")
	print(">>> ProtocolGame: " .. tostring(ProtocolGame))
	print(">>> ProtocolGame.registerOpcode: " .. tostring(ProtocolGame.registerOpcode))
	print(">>> ProtocolGame.onOpcode: " .. tostring(ProtocolGame.onOpcode))
	
	if protocolRegistered then
		return
	end

	debugLog("registerProtocol: registering opcode " .. tostring(OPCODE_SUPPLY_STASH_SEND))
	ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
	ProtocolGame.registerOpcode(OPCODE_SUPPLY_STASH_SEND,
        function(protocol, msg)
			pcall(function()
				local itemData = {}
				local count = msg:getU16()
				for i = 1, count do
					if msg:getUnreadSize() < 6 then break end
					table.insert(itemData, {
						itemId = msg:getU16(),
						amount = msg:getU32()
					})
				end

				local sizeLeft = msg:getU16()
				
				-- Try to parse details if present
				if msg:getUnreadSize() >= 2 then
					local peek = msg:peekU16()
					if peek == SUPPLY_STASH_DETAILS_MARKER or peek == 0x0053 or peek == 0x5300 then
						msg:getU16() -- consume marker
						local detailCount = msg:getU16()
						for i = 1, detailCount do
							if msg:getUnreadSize() < 5 then break end
							local id = msg:getU16()
							local name = msg:getString()
							local cat = msg:getU16()
							local stack = msg:getU8()
							getItemInfo(id, {name = name, category = cat, stackable = stack == 1})
						end
					elseif peek == count and count > 0 then
						local detailCount = msg:getU16() -- consume detailCount
						for i = 1, detailCount do
							if msg:getUnreadSize() < 5 then break end
							local id = msg:getU16()
							local name = msg:getString()
							local cat = msg:getU16()
							local stack = msg:getU8()
							getItemInfo(id, {name = name, category = cat, stackable = stack == 1})
						end
					end
				end

				setup(itemData, sizeLeft)
			end)
			return true
        end
    )
	protocolRegistered = true
end

local function unregisterProtocol()
	if not protocolRegistered then
		return
	end

	debugLog("unregisterProtocol: unregistering opcode " .. tostring(OPCODE_SUPPLY_STASH_SEND))
	ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
	protocolRegistered = false
end

function init()	
	debugLog("init start")
	
	-- Main stash window
	window 	   = g_ui.displayUI('game_stash')
	if not window then
		g_logger.error("game_stash: could not load game_stash.otui")
		return
	end
	debugLog("UI loaded: game_stash")
	freeSlots = window:recursiveGetChildById('freeSlots')
	
	-- Selecter for charms
	itemsContainer = window:recursiveGetChildById('itemsContainer')
	supplyItems = itemsContainer:recursiveGetChildById('supplyItems')
	searchInput = window:recursiveGetChildById('searchInput')
	categoryFilter = window:recursiveGetChildById('categoryFilter') or window:recursiveGetChildById('itemTypes')
	setupCategoryFilter()
	if searchInput then
		searchInput.onTextChange = function()
			refreshItemList()
		end
	end
	window.onDrop = onSupplyDrop
	itemsContainer.onDrop = onSupplyDrop
	supplyItems.onDrop = onSupplyDrop
	markSupplyStashDropBlocked(window)
	markSupplyStashDropBlocked(itemsContainer)
	markSupplyStashDropBlocked(supplyItems)
	debugLog("UI refs resolved: freeSlots=" .. tostring(freeSlots ~= nil) .. ", itemsContainer=" .. tostring(itemsContainer ~= nil) .. ", supplyItems=" .. tostring(supplyItems ~= nil))
	
	connect(
        g_game,
        {
            onEnterGame = registerProtocol,
            onPendingGame = registerProtocol,
            onGameStart = registerProtocol,
            onGameEnd = unregisterProtocol
        }
    )
	
	createwithdrawWindow()
	debugLog("withdraw window created")
	
    if g_game.isOnline() then
		debugLog("game is online during init; registering protocol now")
        registerProtocol()
	else
		debugLog("game offline during init; waiting on onEnterGame/onPendingGame/onGameStart")
    end
end

function terminate()
	debugLog("terminate")
	disconnect(
        g_game,
        {
            onEnterGame = registerProtocol,
            onPendingGame = registerProtocol,
            onGameStart = registerProtocol,
            onGameEnd = unregisterProtocol
        }
    )

    unregisterProtocol()
	window:destroy()
	withdrawWindow:destroy()
end

function toggle()
	debugLog("toggle called; window visible=" .. tostring(window and window:isVisible() or false))
	if window:isVisible() then
		hideWindow()
	else
		requestOpen()
	end
end

function createwithdrawWindow()
	if withdrawWindow then return end
	withdrawWindow = g_ui.displayUI('withdraw')
	if withdrawWindow then
		withdrawWindow:hide()
		debugLog("withdraw window UI loaded")
	else
		g_logger.error("game_stash: could not load withdraw.otui")
	end
end

function withdrawHide()
	withdrawWindow:hide()
end	

function placeholder()
	refreshItemList()
end

function stowAll()
	debugLog("stowAll clicked")
	sendSupplyRequest(ACTION_STOW_ALL)
end

function emptyItemList()
	while supplyItems:getChildCount() > 0 do
		local child = supplyItems:getLastChild()
		child:destroy()
	end
end

local function inferCategoryFromName(name)
	name = (name or ""):lower()
	if name == "" then
		return nil
	end

	if name:find("sword", 1, true) or name:find("blade", 1, true) or name:find("sabre", 1, true) or name:find("katana", 1, true) then
		return CATEGORY_SWORDS
	end
	if name:find("fist", 1, true) or name:find("claw", 1, true) or name:find("knuckle", 1, true) then
		return CATEGORY_FISTS
	end
	if name:find("axe", 1, true) or name:find("hatchet", 1, true) then
		return CATEGORY_AXES
	end
	if name:find("club", 1, true) or name:find("mace", 1, true) or name:find("hammer", 1, true) then
		return CATEGORY_CLUBS
	end
	if name:find("bow", 1, true) or name:find("crossbow", 1, true) or name:find("spear", 1, true) then
		return CATEGORY_DISTANCE
	end
	if name:find("wand", 1, true) or name:find("rod", 1, true) then
		return CATEGORY_WANDS
	end
	if name:find("arrow", 1, true) or name:find("bolt", 1, true) then
		return CATEGORY_AMMUNITION
	end
	if name:find("helmet", 1, true) or name:find("hat", 1, true) then
		return CATEGORY_HELMETS
	end
	if name:find("armor", 1, true) or name:find("mail", 1, true) or name:find("plate", 1, true) then
		return CATEGORY_ARMORS
	end
	if name:find("legs", 1, true) then
		return CATEGORY_LEGS
	end
	if name:find("boots", 1, true) then
		return CATEGORY_BOOTS
	end
	if name:find("shield", 1, true) then
		return CATEGORY_SHIELDS
	end
	if name:find("amulet", 1, true) or name:find("necklace", 1, true) then
		return CATEGORY_AMULETS
	end
	if name:find("potion", 1, true) or name:find("fluid", 1, true) then
		return CATEGORY_POTIONS
	end
	if name:find("rune", 1, true) then
		return CATEGORY_RUNES
	end
	if name:find("ring", 1, true) then
		return MarketCategory and MarketCategory.Rings or 11
	end
	if name:find("food", 1, true) or name:find("ham", 1, true) or name:find("meat", 1, true) or name:find("fish", 1, true) or name:find("bread", 1, true) then
		return CATEGORY_FOOD
	end
	return nil
end

getItemInfo = function(itemId, rowData)
	itemId = tonumber(itemId) or 0
	local cachedInfo = itemInfoCache[itemId]
	if rowData then
		local serverName = rowData.name or rowData.itemName
		local serverCategory = tonumber(rowData.category or rowData.itemCategory)
		local serverStackable = rowData.stackable
		if (serverName and serverName ~= "") or (serverCategory and serverCategory > 0) or serverStackable ~= nil then
			local info = cachedInfo or {
				name = nil,
				category = nil,
				stackable = false
			}
			if serverName and serverName ~= "" then
				info.name = serverName
			end
			if serverCategory and serverCategory > 0 then
				info.category = serverCategory
			end
			if serverStackable ~= nil then
				info.stackable = serverStackable and true or false
			end
			info.name = info.name or ("Item " .. tostring(itemId))
			if not info.category or info.category == 0 then
				info.category = inferCategoryFromName(info.name)
			end
			itemInfoCache[itemId] = info
			itemNameCache[itemId] = info.name
			return info
		end
	end
	if cachedInfo then
		return itemInfoCache[itemId]
	end

	local info = {
		name = nil,
		category = nil,
		stackable = false
	}

	if Item and Item.create then
		local okItem, item = pcall(function()
			return Item.create(itemId)
		end)
		if okItem and item then
			if item.isStackable then
				local okStackable, stackable = pcall(function()
					return item:isStackable()
				end)
				info.stackable = okStackable and stackable or false
			end

			local okMarket, marketData = pcall(function()
				return item:getMarketData()
			end)
			if okMarket and marketData then
				if marketData.name and marketData.name ~= "" then
					info.name = marketData.name
				end
				info.category = marketData.category
			end

			if not info.name and item.getName then
				local okName, itemName = pcall(function()
					return item:getName()
				end)
				if okName and itemName and itemName ~= "" then
					info.name = itemName
				end
			end
		end
	end

	info.name = info.name or ("Item " .. tostring(itemId))
	if not info.category or info.category == 0 then
		info.category = inferCategoryFromName(info.name)
	end
	itemInfoCache[itemId] = info
	itemNameCache[itemId] = info.name
	return info
end

local function getItemDisplayName(itemId, rowData)
	return getItemInfo(itemId, rowData).name
end

local function itemMatchesCategory(itemId, rowData)
	if currentCategoryFilter == "all" then
		return true
	end

	local info = getItemInfo(itemId, rowData)
	if currentCategoryFilter == "stackable" then
		return info.stackable
	end
	if currentCategoryFilter == "weapons" then
		return weaponCategories[info.category] == true
	end
	if type(currentCategoryFilter) == "number" then
		return info.category == currentCategoryFilter
	end
	return true
end

local function itemMatchesSearch(itemId, name)
	if not searchInput then
		return true
	end

	local text = searchInput:getText()
	if not text or text == "" then
		return true
	end

	text = text:lower()
	return name:lower():find(text, 1, true) ~= nil or tostring(itemId):find(text, 1, true) ~= nil
end

local function openWithdrawWindow(itemId, amount)
	hideWindow()
	withdrawWindow:show()
	withdrawWindow:raise()
	withdrawWindow:focus()
	withdrawWindow:unlock()
	modules.game_interface.getRootPanel():focus()

	withdrawWindow.item:setItemId(itemId)
	withdrawWindow.item:setItemCount(amount)
	withdrawWindow.amountTextEdit:setText(1)
	withdrawWindow.amountScrollBar:setMinimum(1)
	withdrawWindow.amountScrollBar:setMaximum(amount)
	withdrawWindow.amountScrollBar:setValue(1)
	withdrawWindow.amountScrollBar.onValueChange = function(widget, value)
		if tonumber(withdrawWindow.amountTextEdit:getText()) ~= value then
			withdrawWindow.amountTextEdit:setText(value)
		end
	end
	
	withdrawWindow.amountTextEdit.onTextChange = function(widget, text)
		local val = tonumber(text)
		if val then
			if val > amount then val = amount end
			if val < 1 then val = 1 end
			if withdrawWindow.amountScrollBar:getValue() ~= val then
				withdrawWindow.amountScrollBar:setValue(val)
			end
		end
	end

	withdrawWindow.buttonCancel.onClick = function(self)
		withdrawHide()
		requestOpen()
	end

	withdrawWindow.buttonOk.onClick = function(self)
		local count = tonumber(withdrawWindow.amountTextEdit:getText()) or 0
		sendSupplyRequest(ACTION_WITHDRAW, itemId, count)
		withdrawHide()
		modules.game_interface.getRootPanel():focus()
	end
end

function refreshItemList()
	if not supplyItems then
		return
	end

	emptyItemList()
	for i = 1, #currentItemData do
		local rowData = currentItemData[i]
		local itemId = rowData.itemId or rowData[1]
		local amount = rowData.amount or rowData[2]
		local name = getItemDisplayName(itemId, rowData)
		if itemMatchesCategory(itemId, rowData) and itemMatchesSearch(itemId, name) then
			local row = g_ui.createWidget('StashItem', supplyItems)
			row.index = i
			row:setId("stashItem" .. i)
			row.categoryId = i
			row:setItemId(itemId)
			row:setDraggable(false)
			row:setTooltip(name)
			markSupplyStashDropBlocked(row)

			local countText = row:recursiveGetChildById('itemCountLabel')
			countText:setText(tostring(amount))
			markSupplyStashDropBlocked(countText)

			row.onClick = function(self)
				openWithdrawWindow(itemId, amount)
			end
			row.onDrop = onSupplyDrop
		end
	end

	if freeSlots then
		freeSlots:setText("Free slots: " .. currentSizeLeft)
	end
end

function setup(itemData, sizeLeft)
	itemData = itemData or {}
	debugLog("setup start: items=" .. tostring(#itemData) .. ", sizeLeft=" .. tostring(sizeLeft))
	showWindow()
	currentItemData = itemData
	currentSizeLeft = sizeLeft or 0
	refreshItemList()
end
