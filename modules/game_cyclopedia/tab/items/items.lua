Cyclopedia = Cyclopedia or {}
Cyclopedia.Items = Cyclopedia.Items or {}
Cyclopedia.Items.currentItemId = nil
Cyclopedia.Items.currentItemDescriptions = nil

-- Additional variables for new features
local itemsData = {}
local lastSelectedItem = nil

Cyclopedia.CategoryItems = {
    { id = 1, name = "Armors" },
    { id = 2, name = "Amulets" },
    { id = 3, name = "Boots" },
    { id = 4, name = "Containers" },
    { id = 24, name = "Creature Products" },
    { id = 5, name = "Decoration" },
    { id = 6, name = "Food" },
    { id = 30, name = "Gold" },
    { id = 7, name = "Helmets and Hats" },
    { id = 8, name = "Legs" },
    { id = 9, name = "Others" },
    { id = 10, name = "Potions" },
    { id = 25, name = "Quivers" },
    { id = 11, name = "Rings" },
    { id = 12, name = "Runes" },
    { id = 13, name = "Shields" },
    { id = 26, name = "Soul Cores" },
    { id = 14, name = "Tools" },
    { id = 31, name = "Unsorted" },
    { id = 15, name = "Valuables" },
    { id = 16, name = "Weapons: Ammo" },
    { id = 17, name = "Weapons: Axe" },
    { id = 18, name = "Weapons: Clubs" },
    { id = 19, name = "Weapons: Distance" },
    { id = 20, name = "Weapons: Swords" },
    { id = 21, name = "Weapons: Wands" },
    { id = 1000, name = "Weapons: All" }
}

local UI = nil
local UNSORTED_CATEGORY_ID = 31
local ITEMS_INDEX_RETRY_DELAY_MS = 1000
local ITEMS_PENDING_SEARCH_RETRY_DELAY_MS = 400
local ITEMS_INDEX_MAX_RETRIES = 5
local ITEM_LIST_ROW_HEIGHT = 36
local ITEM_LIST_VISIBLE_ROWS = 5
local ITEM_LIST_DEFAULT_HEIGHT = ITEM_LIST_ROW_HEIGHT * ITEM_LIST_VISIBLE_ROWS + 7
local ITEM_SEARCH_DEBOUNCE_MS = 120
local ITEM_SEARCH_SELECT_DELAY_MS = 80
local ITEM_SEARCH_MIN_LENGTH = 2
local ignoreLootValueSourceCheck = false

local VOCATION_MASK_ENCODING = {
	SERVER = "server", -- OTC ids: 1=sorc, 2=druid, 3=pally, 4=knight, 9=monk
	DAT = "dat", -- CIP PLAYER_PROFESSION: 1=knight, 2=paladin, 3=sorc, 4=druid, 5=monk
}

Cyclopedia.Items.listScroll = Cyclopedia.Items.listScroll or {
	listData = {},
	listPool = {},
	listMin = 0,
	listMax = 0,
	listFit = 6,
	offset = 0,
	indexById = {}
}

local onCyclopediaItemsListScroll
local refreshItemsListView
local selectItemInList

local function cancelItemSearchEvent()
	if Cyclopedia.Items.searchEvent then
		removeEvent(Cyclopedia.Items.searchEvent)
		Cyclopedia.Items.searchEvent = nil
	end
end

local function cancelItemDetailFallback()
	if Cyclopedia.Items.detailFallbackEvent then
		removeEvent(Cyclopedia.Items.detailFallbackEvent)
		Cyclopedia.Items.detailFallbackEvent = nil
	end
end

local function getItemsListScrollbar()
	if not UI or not UI.ItemListBase then
		return nil
	end

	if UI.ItemListBase.ListScrollbar and not UI.ItemListBase.ListScrollbar:isDestroyed() then
		return UI.ItemListBase.ListScrollbar
	end

	UI.ItemListBase.ListScrollbar = UI.ItemListBase:recursiveGetChildById('ListScrollbar')
	return UI.ItemListBase.ListScrollbar
end

local function updateItemsListScrollbarRange()
	local scrollState = Cyclopedia.Items.listScroll
	local scroll = getItemsListScrollbar()
	if not scroll or not scrollState then
		return
	end

	local poolSize = #(scrollState.listPool or {})
	local total = #(scrollState.listData or {})
	local minimum = total > 0 and 1 or 0
	local maximum = math.max(minimum, total - poolSize + 1)

	scroll:setStep(1)
	if scroll.setVisibleItems and scroll.setVirtualChilds then
		scroll:setVisibleItems(poolSize)
		scroll:setVirtualChilds(total)
	end

	scroll:setMinimum(minimum)
	scroll:setMaximum(maximum)
	if scroll:getValue() < minimum then
		scroll:setValue(minimum)
	elseif scroll:getValue() > maximum then
		scroll:setValue(maximum)
	end
end

local function setupItemsListVirtualScroll()
	if not UI or not UI.ItemListBase or not UI.ItemListBase.List then
		return
	end

	local list = UI.ItemListBase.List
	list.updateScrollBars = function()
	end
	list.verticalScrollBar = nil

	local scroll = getItemsListScrollbar()
	if not scroll then
		return
	end

	if not scroll._cyclopediaScrollBound then
		scroll._cyclopediaScrollBound = true
		scroll.onValueChange = function(self, value)
			onCyclopediaItemsListScroll(self, value)
		end

		function list.onMouseWheel(widget, mousePos, wheelDirection)
			if not scroll or scroll:getMaximum() <= scroll:getMinimum() then
				return false
			end

			if wheelDirection == MouseWheelUp then
				scroll:decrement()
			else
				scroll:increment()
			end
			return true
		end
	end
end

local function resolveThingType(entry)
	if not entry then
		return nil
	end
	if entry.thingType then
		return entry.thingType
	end
	if entry.id then
		return g_things.getThingType(entry.id, ThingCategoryItem)
	end
	return entry
end

local function normalizeClientVocationId(vocation)
	vocation = tonumber(vocation) or 0
	if vocation == 5 or vocation == 13 then
		return 1
	elseif vocation == 6 or vocation == 14 then
		return 2
	elseif vocation == 7 or vocation == 12 then
		return 3
	elseif vocation == 8 or vocation == 11 then
		return 4
	elseif vocation == 9 or vocation == 10 or vocation == 15 then
		return 9
	elseif vocation > 10 then
		return vocation - 10
	end
	return vocation
end

local function clientVocationToCipProfession(vocation)
	vocation = normalizeClientVocationId(vocation)
	if vocation == 1 then
		return 3 -- sorcerer
	elseif vocation == 2 then
		return 4 -- druid
	elseif vocation == 3 then
		return 2 -- paladin
	elseif vocation == 4 then
		return 1 -- knight
	elseif vocation == 9 or vocation == 10 then
		return 5 -- monk
	end
	return vocation
end

local function getVocationFilterBitMask(vocation, encoding)
	if encoding == VOCATION_MASK_ENCODING.DAT then
		local profession = clientVocationToCipProfession(vocation)
		if profession <= 0 then
			return 0
		end
		return Bit.bit(profession)
	end

	local normalized = normalizeClientVocationId(vocation)
	if normalized <= 0 then
		return 0
	end
	return Bit.bit(normalized)
end

local function getEntryMarketFilterData(entry, thingType)
	local requiredLevel = entry and tonumber(entry.requiredLevel) or 0
	local restrictVocation = entry and tonumber(entry.restrictVocation) or 0
	local vocationEncoding = nil

	local marketData = {}
	if thingType and thingType.getMarketData then
		marketData = thingType:getMarketData() or {}
	end

	if requiredLevel == 0 then
		requiredLevel = tonumber(marketData.requiredLevel) or 0
	end

	if restrictVocation > 0 then
		vocationEncoding = VOCATION_MASK_ENCODING.SERVER
	elseif tonumber(marketData.restrictVocation) > 0 then
		restrictVocation = tonumber(marketData.restrictVocation)
		vocationEncoding = VOCATION_MASK_ENCODING.DAT
	end

	if requiredLevel == 0 and restrictVocation == 0 and entry and entry.id then
		local item = Item.create(entry.id)
		if item and item.getMarketData then
			local itemMarketData = item:getMarketData() or {}
			requiredLevel = tonumber(itemMarketData.requiredLevel) or requiredLevel
			if tonumber(itemMarketData.restrictVocation) > 0 then
				restrictVocation = tonumber(itemMarketData.restrictVocation)
				vocationEncoding = VOCATION_MASK_ENCODING.DAT
			end
		end
	end

	return requiredLevel, restrictVocation, vocationEncoding
end

local function passesItemFilters(entry)
	local data = resolveThingType(entry)
	if not data then
		return false
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return true
	end

	local vocation = player:getVocation()
	local level = player:getLevel()
	local classification = (entry and entry.classification) or data:getClassification() or 0
	local requiredLevel, restrictVocation, vocationEncoding = getEntryMarketFilterData(entry, data)
	local vocFilter = Cyclopedia.Items.VocFilter
	local levelFilter = Cyclopedia.Items.LevelFilter
	local h1Filter = Cyclopedia.Items.h1Filter
	local h2Filter = Cyclopedia.Items.h2Filter
	local classificationFilter = Cyclopedia.Items.ClassificationFilter

	if vocFilter and restrictVocation > 0 then
		local vocBitMask = getVocationFilterBitMask(vocation, vocationEncoding or VOCATION_MASK_ENCODING.SERVER)
		if vocBitMask <= 0 or not Bit.hasBit(restrictVocation, vocBitMask) then
			return false
		end
	end

	if levelFilter and requiredLevel > 0 and level < requiredLevel then
		return false
	end

	if h1Filter and data:getClothSlot() ~= 6 then
		return false
	end

	if h2Filter and data:getClothSlot() ~= 0 then
		return false
	end

	if classificationFilter == -1 and classification ~= 0 then
		return false
	elseif classificationFilter == 1 and classification ~= 1 then
		return false
	elseif classificationFilter == 2 and classification ~= 2 then
		return false
	elseif classificationFilter == 3 and classification ~= 3 then
		return false
	elseif classificationFilter == 4 and classification ~= 4 then
		return false
	end

	return true
end

local function repaintItemsListPool(selectedItemId)
	local scrollState = Cyclopedia.Items.listScroll
	if not scrollState.listPool then
		return
	end

	selectedItemId = selectedItemId or tonumber(Cyclopedia.Items.currentItemId)
	for _, widget in ipairs(scrollState.listPool) do
		if widget.cyclopediaEntry then
			Cyclopedia.renderItemsListWidget(widget, widget.cyclopediaEntry, selectedItemId)
		end
	end
end

function Cyclopedia.renderItemsListWidget(widget, entry, selectedItemId)
	local data = resolveThingType(entry)
	if not widget or not data then
		return
	end

	local displayName = entry.name or Cyclopedia.getItemDisplayName(data)
	widget:setId(tostring(entry.id))
	widget.cyclopediaEntry = entry
	widget.cyclopediaItemId = entry.id
	widget.Sprite:setItemId(entry.id)
	widget.Name:setText(displayName)
	widget.Value = data:getMeanPrice()
	ItemsDatabase.setRarityItem(widget.Sprite, widget.Sprite:getItem())

	if Cyclopedia.Items.isInDropTracker(entry.id) then
		widget.Name:setColor("#FF9854")
	else
		widget.Name:setColor("#c0c0c0")
	end

	if selectedItemId and selectedItemId == entry.id then
		widget:setBackgroundColor("#585858")
	else
		widget:setBackgroundColor("#00000000")
	end

	if not widget._cyclopediaClickBound then
		widget._cyclopediaClickBound = true
		function widget.onClick(clickedWidget)
			Cyclopedia.selectItemEntry(clickedWidget.cyclopediaEntry, clickedWidget)
		end
	end
end

local function cancelPendingSingleSelect()
	if Cyclopedia.Items.pendingSingleSelectEvent then
		removeEvent(Cyclopedia.Items.pendingSingleSelectEvent)
		Cyclopedia.Items.pendingSingleSelectEvent = nil
	end
end

onCyclopediaItemsListScroll = function(scroll, value)
	local scrollState = Cyclopedia.Items.listScroll
	if not UI or not scrollState.listPool or #scrollState.listPool == 0 or #scrollState.listData == 0 then
		return
	end

	local startIndex = math.max(1, math.floor(tonumber(value) or 1))
	local maxScrollValue = math.max(1, scrollState.listMax - #scrollState.listPool + 1)
	if startIndex > maxScrollValue then
		startIndex = maxScrollValue
	end

	scrollState.offset = 0
	UI.ItemListBase.List:setVirtualOffset({ x = 0, y = 0 })

	local selectedItemId = tonumber(Cyclopedia.Items.currentItemId)
	for i, widget in ipairs(scrollState.listPool) do
		local entry = scrollState.listData[startIndex + i - 1]
		if entry then
			widget:setVisible(true)
			Cyclopedia.renderItemsListWidget(widget, entry, selectedItemId)
		else
			widget:setVisible(false)
			widget.cyclopediaEntry = nil
			widget.cyclopediaItemId = nil
		end
	end
end

refreshItemsListView = function(sourceEntries, options)
	if not UI or UI:isDestroyed() or not UI.ItemListBase or not UI.ItemListBase.List then
		return
	end

	cancelPendingSingleSelect()
	Cyclopedia.Items.listSelectGeneration = (tonumber(Cyclopedia.Items.listSelectGeneration) or 0) + 1

	options = options or {}
	local list = UI.ItemListBase.List
	local scroll = getItemsListScrollbar()
	local scrollState = Cyclopedia.Items.listScroll

	scrollState.listData = sourceEntries or {}
	scrollState.indexById = {}
	for i = 1, #scrollState.listData do
		scrollState.indexById[scrollState.listData[i].id] = i
	end

	local function buildListPool()
		if not UI or UI:isDestroyed() or not UI.ItemListBase or not UI.ItemListBase.List then
			return
		end

		local itemList = UI.ItemListBase.List
		local itemScroll = getItemsListScrollbar()
		local state = Cyclopedia.Items.listScroll

		itemList:destroyChildren()
		state.listPool = {}

		local listHeight = itemList:getHeight()
		if listHeight <= 0 then
			listHeight = UI.ItemListBase:getHeight() - 10
		end
		if listHeight <= 0 then
			listHeight = ITEM_LIST_DEFAULT_HEIGHT
		end

		state.listFit = math.max(ITEM_LIST_VISIBLE_ROWS, math.floor(listHeight / ITEM_LIST_ROW_HEIGHT) + 1)
		local poolCount = math.min(#state.listData, state.listFit)
		for _ = 1, poolCount do
			table.insert(state.listPool, g_ui.createWidget("ItemsListBaseItem", itemList))
		end

		state.listMin = #state.listData > 0 and 1 or 0
		state.listMax = #state.listData
		state.offset = 0

		updateItemsListScrollbarRange()
		if itemScroll then
			itemScroll:setValue(state.listMin)
		end

		itemList:setVirtualOffset({ x = 0, y = 0 })
		if itemScroll then
			onCyclopediaItemsListScroll(itemScroll, state.listMin)
		end

		local autoSelectId = options.autoSelectId or Cyclopedia.Items.pendingOpenItemId
		if autoSelectId then
			selectItemInList(autoSelectId)
		elseif options.selectSingle and #state.listData == 1 then
			local targetItemId = state.listData[1].id
			local selectDelay = tonumber(options.selectDelay) or 0
			local listGeneration = Cyclopedia.Items.listSelectGeneration
			if selectDelay > 0 then
				Cyclopedia.Items.pendingSingleSelectEvent = scheduleEvent(function()
					Cyclopedia.Items.pendingSingleSelectEvent = nil
					if not UI or UI:isDestroyed() then
						return
					end
					if listGeneration ~= Cyclopedia.Items.listSelectGeneration then
						return
					end
					local firstEntry = state.listData[1]
					if not firstEntry or firstEntry.id ~= targetItemId then
						return
					end
					selectItemInList(targetItemId)
				end, selectDelay)
			else
				selectItemInList(targetItemId)
			end
		end
	end

	if options.immediate then
		buildListPool()
		return
	end

	if Cyclopedia.Items.listRenderEvent then
		removeEvent(Cyclopedia.Items.listRenderEvent)
		Cyclopedia.Items.listRenderEvent = nil
	end

	list:destroyChildren()
	scrollState.listPool = {}
	Cyclopedia.Items.listRenderEvent = scheduleEvent(function()
		Cyclopedia.Items.listRenderEvent = nil
		buildListPool()
	end, 50)
end

local function clearPendingItemOpen()
	Cyclopedia.Items.pendingOpenItemId = nil
	Cyclopedia.Items.pendingSearchText = nil
end

local function setPendingItemOpen(itemId, itemName)
	Cyclopedia.Items.pendingOpenItemId = tonumber(itemId)
	Cyclopedia.Items.pendingSearchText = itemName
end

selectItemInList = function(itemId)
	itemId = tonumber(itemId)
	if not itemId or not UI or UI:isDestroyed() then
		return false
	end

	local scrollState = Cyclopedia.Items.listScroll
	local index = scrollState.indexById and scrollState.indexById[itemId]
	if not index then
		return false
	end

	local scroll = getItemsListScrollbar()
	if scroll and #scrollState.listPool > 0 and #scrollState.listData > #scrollState.listPool then
		local targetValue = math.min(index, math.max(1, scrollState.listMax - #scrollState.listPool + 1))
		if scroll:getValue() ~= targetValue then
			scroll:setValue(targetValue)
		else
			onCyclopediaItemsListScroll(scroll, targetValue)
		end
	end

	for _, widget in ipairs(scrollState.listPool or {}) do
		if widget.cyclopediaItemId == itemId and widget.onClick then
			widget.onClick(widget)
			clearPendingItemOpen()
			return true
		end
	end

	local entry = scrollState.listData[index]
	if entry then
		Cyclopedia.selectItemEntry(entry, nil)
		clearPendingItemOpen()
		return true
	end

	return false
end

local function resolveFocusItemName(itemId, itemName)
	if itemName and itemName ~= '' then
		return itemName
	end

	itemId = tonumber(itemId)
	if not itemId then
		return ''
	end

	itemName = getServerMarketItemName(itemId)
	if itemName and itemName ~= '' then
		return itemName
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType then
		itemName = Cyclopedia.getItemDisplayName(thingType)
		if itemName and itemName ~= '' then
			return itemName
		end
	end

	for i = 1, #Cyclopedia.AllItemList do
		if Cyclopedia.AllItemList[i].id == itemId then
			return Cyclopedia.AllItemList[i].name or ''
		end
	end

	return ''
end

local function resolveItemContext(obj)
	if not obj then
		return nil
	end

	local item, thingType, itemId
	if type(obj) == 'number' then
		itemId = obj
		thingType = g_things.getThingType(itemId, ThingCategoryItem)
		item = Item.create(itemId)
	elseif obj.getMarketData then
		thingType = obj
		itemId = thingType:getId()
		item = Item.create(itemId)
	else
		item = obj
		itemId = item:getId()
		thingType = g_things.getThingType(itemId, ThingCategoryItem)
	end

	return item, thingType, itemId
end

local function isMarketLootSource(itemId)
	local sources = itemsData["primaryLootValueSources"]
	return sources and sources[tostring(itemId)] ~= nil
end

local function getCustomLootValue(itemId)
	local prices = itemsData["customSalePrices"]
	if not prices then
		return nil
	end
	return prices[tostring(itemId)]
end

local MARKET_EXCLUDED_ITEM_IDS = {
	[49870] = true,
	[14258] = true
}

focusCategoryList = nil

local function resetItemsDataTable(source)
	for key in pairs(itemsData) do
		itemsData[key] = nil
	end
	if source then
		for key, value in pairs(source) do
			itemsData[key] = value
		end
	end
end

local function getSelectedCyclopediaItemId()
	if Cyclopedia.Items.currentItemId then
		return Cyclopedia.Items.currentItemId
	end

	if UI and UI.selectItem then
		return tonumber(UI.selectItem:getId())
	end

	if lastSelectedItem then
		if lastSelectedItem.Sprite then
			local item = lastSelectedItem.Sprite:getItem()
			if item then
				return item:getId()
			end
		end

		if lastSelectedItem.getId then
			return tonumber(lastSelectedItem:getId())
		end
	end

	return nil
end

function Cyclopedia.getItemListCategory(thingType)
	if not thingType then
		return UNSORTED_CATEGORY_ID
	end
	if thingType:isMarketable() then
		local marketData = thingType:getMarketData()
		if marketData and marketData.category then
			return marketData.category
		end
	end
	return UNSORTED_CATEGORY_ID
end

function Cyclopedia.getItemDisplayName(thingType)
	local marketData = thingType:getMarketData()
	if thingType:isMarketable() and marketData and marketData.name and marketData.name ~= "" then
		return marketData.name
	end

	local name = thingType:getName()
	if name and name ~= "" then
		return name
	end

	return "Item #" .. tostring(thingType:getId())
end

local function getThingTypeFromRef(itemOrType)
	if not itemOrType then
		return nil
	end
	if itemOrType.getMarketData then
		return itemOrType
	end
	if itemOrType.getId then
		return g_things.getThingType(itemOrType:getId(), ThingCategoryItem)
	end
	return nil
end

local function getCachedServerMarketItems()
	if not modules.game_market or not modules.game_market.getCachedCustomMarketItems then
		return nil
	end

	local cached = modules.game_market.getCachedCustomMarketItems()
	if cached and #cached > 0 then
		return cached
	end

	return nil
end

local function getItemsIndexCacheToken()
	local serverItems = getCachedServerMarketItems()
	if serverItems then
		return serverItems, #serverItems
	end

	return nil, 0
end

local function isItemsIndexUpToDate()
	local source, count = getItemsIndexCacheToken()
	if Cyclopedia.Items.indexCacheSource ~= source then
		return false
	end
	if (Cyclopedia.Items.indexCacheCount or 0) ~= count then
		return false
	end
	if not Cyclopedia.ItemList or not Cyclopedia.AllItemList or #Cyclopedia.AllItemList == 0 then
		return false
	end
	return true
end

function Cyclopedia.invalidateItemsIndex()
	Cyclopedia.Items.indexCacheSource = nil
	Cyclopedia.Items.indexCacheCount = nil
end

local function isClassificationDetailKey(key)
	key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub(":%s*$", "")
	return key == "Classification" or key == "Upgrade Classification"
end

local function resolveItemClassification(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return 0
	end

	local serverItems = getCachedServerMarketItems()
	if serverItems then
		for i = 1, #serverItems do
			if serverItems[i].id == itemId then
				local classification = tonumber(serverItems[i].classification) or 0
				if classification > 0 then
					return classification
				end
				break
			end
		end
	end

	if Cyclopedia.ItemList then
		for _, itemList in pairs(Cyclopedia.ItemList) do
			for j = 1, #itemList do
				local entry = itemList[j]
				if entry.id == itemId then
					local classification = tonumber(entry.classification) or 0
					if classification > 0 then
						return classification
					end
				end
			end
		end
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType and thingType.getClassification then
		return tonumber(thingType:getClassification()) or 0
	end

	return 0
end

local function ensureClassificationDescription(itemId, descriptions)
	descriptions = descriptions or {}
	for _, description in ipairs(descriptions) do
		local key = description.key or description[1]
		if key and isClassificationDetailKey(key) then
			return descriptions
		end
	end

	local classification = resolveItemClassification(itemId)
	if classification > 0 then
		descriptions[#descriptions + 1] = { key = "Classification", value = tostring(classification) }
	end

	return descriptions
end

local function getServerMarketItemName(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return nil
	end

	local serverItems = getCachedServerMarketItems()
	if not serverItems then
		return nil
	end

	for i = 1, #serverItems do
		if serverItems[i].id == itemId then
			return serverItems[i].name
		end
	end

	return nil
end

local function isDatMarketItem(thingType)
	if not thingType then
		return false
	end

	local id = thingType:getId()
	if id <= 100 or MARKET_EXCLUDED_ITEM_IDS[id] then
		return false
	end

	local marketData = thingType:getMarketData()
	return marketData and not table.empty(marketData)
end

function Cyclopedia.isListableItem(itemOrType)
	local thingType = getThingTypeFromRef(itemOrType)
	if not thingType then
		return false
	end

	local id = thingType:getId()
	if id <= 100 or MARKET_EXCLUDED_ITEM_IDS[id] then
		return false
	end

	if modules.game_market and modules.game_market.isCustomMarketItem and modules.game_market.isCustomMarketItem(id) then
		return true
	end

	return isDatMarketItem(thingType)
end

function Cyclopedia.canShowInItemsTab(itemOrType)
	return Cyclopedia.isListableItem(itemOrType)
end

local function collectDatMarketItemTypes()
	local types = g_things.findThingTypeByAttr(ThingAttrMarket, ThingCategoryItem)
	if not types then
		return {}
	end

	local result = {}
	for _, thingType in pairs(types) do
		if isDatMarketItem(thingType) then
			result[#result + 1] = thingType
		end
	end

	return result
end

local function normalizeItemCategory(category)
	category = tonumber(category) or UNSORTED_CATEGORY_ID
	if category <= 0 then
		return UNSORTED_CATEGORY_ID
	end
	return category
end

local function buildItemIndexEntry(thingType, id, name, category, classification, requiredLevel, restrictVocation)
	id = tonumber(id) or (thingType and thingType:getId())
	if not id or id <= 100 or MARKET_EXCLUDED_ITEM_IDS[id] then
		return nil
	end

	if not thingType then
		thingType = g_things.getThingType(id, ThingCategoryItem)
	end

	if not name or name == "" then
		name = thingType and Cyclopedia.getItemDisplayName(thingType) or ("Item #" .. tostring(id))
	end

	if not category or category <= 0 then
		category = thingType and Cyclopedia.getItemListCategory(thingType) or UNSORTED_CATEGORY_ID
	end

	if classification == nil then
		classification = thingType and thingType:getClassification() or 0
	end

	return {
		thingType = thingType,
		id = id,
		name = name,
		nameLower = string.lower(name or ""),
		category = normalizeItemCategory(category),
		classification = tonumber(classification) or 0,
		requiredLevel = tonumber(requiredLevel) or 0,
		restrictVocation = tonumber(restrictVocation) or 0
	}
end

local function collectServerMarketEntries()
	local serverItems = getCachedServerMarketItems()
	if not serverItems then
		return nil
	end

	local seen = {}
	local result = {}

	for i = 1, #serverItems do
		local serverItem = serverItems[i]
		local entry = buildItemIndexEntry(
			g_things.getThingType(serverItem.id, ThingCategoryItem),
			serverItem.id,
			serverItem.name,
			serverItem.category,
			serverItem.classification,
			serverItem.requiredLevel,
			serverItem.restrictVocation
		)
		if entry and not seen[entry.id] then
			seen[entry.id] = true
			result[#result + 1] = entry
		end
	end

	return result
end

local function requestServerMarketItems()
	if modules.game_market and modules.game_market.requestMarketItemsForCyclopedia then
		modules.game_market.requestMarketItemsForCyclopedia()
	end
end

local function cancelItemsIndexRetry()
	if Cyclopedia.Items.indexRetryEvent then
		removeEvent(Cyclopedia.Items.indexRetryEvent)
		Cyclopedia.Items.indexRetryEvent = nil
	end
end

local function scheduleItemsIndexRetry()
	if getCachedServerMarketItems() or not g_game.isOnline() then
		cancelItemsIndexRetry()
		return
	end

	if Cyclopedia.Items.indexRetryEvent then
		return
	end

	Cyclopedia.Items.indexRetryEvent = scheduleEvent(function()
		Cyclopedia.Items.indexRetryEvent = nil
		Cyclopedia.Items.indexRetryCount = (Cyclopedia.Items.indexRetryCount or 0) + 1

		if ITEMS_INDEX_MAX_RETRIES > 0 and Cyclopedia.Items.indexRetryCount > ITEMS_INDEX_MAX_RETRIES then
			return
		end

		if getCachedServerMarketItems() then
			Cyclopedia.Items.indexRetryCount = 0
			Cyclopedia.applyItemsIndexRefresh()
			return
		end

		if not g_game.isOnline() then
			return
		end

		requestServerMarketItems()
		scheduleItemsIndexRetry()
	end, Cyclopedia.Items.pendingSearchText and ITEMS_PENDING_SEARCH_RETRY_DELAY_MS or ITEMS_INDEX_RETRY_DELAY_MS)
end

local processItemsById

local function refreshItemsTabView()
	if not UI or UI:isDestroyed() then
		Cyclopedia.Items.pendingMarketRefresh = true
		return
	end

	Cyclopedia.Items.pendingMarketRefresh = false
	Cyclopedia.loadItemsCategories()

	if Cyclopedia.Items.pendingOpenItemId then
		if Cyclopedia.focusItem(Cyclopedia.Items.pendingOpenItemId, Cyclopedia.Items.pendingSearchText) then
			return
		end
	end

	local searchText = UI.SearchEdit and UI.SearchEdit:getText() or ""
	if searchText == "" and Cyclopedia.Items.pendingSearchText then
		searchText = Cyclopedia.Items.pendingSearchText
		Cyclopedia.Items.pendingSearchText = nil
	end

	if searchText ~= "" then
		Cyclopedia.ItemSearch(searchText, false)
	elseif UI.selectedCategory then
		processItemsById(tonumber(UI.selectedCategory:getId()))
	else
		Cyclopedia.selectDefaultItemCategory()
	end
end

-- JSON Data Management Functions
function Cyclopedia.Items.terminate()
	cancelItemsIndexRetry()
	cancelItemSearchEvent()
	cancelItemDetailFallback()
	if Cyclopedia.Items.listRenderEvent then
		removeEvent(Cyclopedia.Items.listRenderEvent)
		Cyclopedia.Items.listRenderEvent = nil
	end
	cancelPendingSingleSelect()
	Cyclopedia.invalidateItemsIndex()
	Cyclopedia.Items.saveJson()
end

function Cyclopedia.onItemsTabHidden()
	cancelItemSearchEvent()
	cancelItemDetailFallback()
	cancelPendingSingleSelect()
	clearPendingItemOpen()
	Cyclopedia.Items.currentItemId = nil
end

function Cyclopedia.Items.loadJson()
	if not LoadedPlayer or not LoadedPlayer:isLoaded() then
		return true
	end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/itemprices.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			g_logger.error("Error while reading characterdata file. Details: " .. result)
			resetItemsDataTable({
				["primaryLootValueSources"] = {},
				["customSalePrices"] = {}
			})
			return
		end

		resetItemsDataTable(result)
	else
		resetItemsDataTable({
			["customSalePrices"] = {},
			["primaryLootValueSources"] = {}
		})
		Cyclopedia.Items.saveJson()
	end

	if table.empty(itemsData) then
		resetItemsDataTable({
			["primaryLootValueSources"] = {},
			["customSalePrices"] = {}
		})
	end

	-- Ensure both required tables exist
	if not itemsData["primaryLootValueSources"] then
		itemsData["primaryLootValueSources"] = {}
	end
	if not itemsData["customSalePrices"] then
		itemsData["customSalePrices"] = {}
	end
	if not itemsData["dropTrackerItems"] then
		itemsData["dropTrackerItems"] = {}
	end

	local useMarketPrice = {}
	for k, v in pairs(itemsData["primaryLootValueSources"]) do
		table.insert(useMarketPrice, k)
	end

	local customPrice = {}
	if g_things.getItemsPrice then
		customPrice = g_things.getItemsPrice()
	end
	
	for k, v in pairs(itemsData["customSalePrices"]) do
		local key = tonumber(k) or k
		customPrice[key] = v
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return true
	end

	if player.setCyclopediaMarketList then
		player:setCyclopediaMarketList(useMarketPrice)
	end
	if player.setCyclopediaCustomPrice then
		player:setCyclopediaCustomPrice(customPrice)
	end
end

function Cyclopedia.Items.saveJson()
	if not LoadedPlayer or not LoadedPlayer:isLoaded() then
		return true
	end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/itemprices.json"
	local status, result = pcall(function() return json.encode(itemsData, 2) end)
	if not status then
		g_logger.error("Error while saving profile itemsData. Data won't be saved. Details: " .. result)
		return
	end

	if result:len() > 100 * 1024 * 1024 then
		g_logger.error("Something went wrong, file is above 100MB, won't be saved")
		return
	end
	g_resources.writeFileContents(file, result)
end

function Cyclopedia.ResetItemCategorySelection(list)
    for i, child in pairs(list:getChildren()) do
        child:setChecked(false)
        child:setBackgroundColor(child.BaseColor)
    end
end

local function getItemSortName(item)
    if not item then
        return ""
    end

    if item.nameLower then
        return item.nameLower
    end

    if item.name then
        return item.name:lower()
    end

    local thingType = resolveThingType(item)
    if thingType then
        return string.lower(Cyclopedia.getItemDisplayName(thingType))
    end

    return ""
end

function Cyclopedia.compareItems(item1, item2)
    return getItemSortName(item1) < getItemSortName(item2)
end

function Cyclopedia.hasHandedFilter(categoryId)
    return categoryId >= 17 and categoryId <= 21 or categoryId == 1000
end

function Cyclopedia.hasClassificationFilter(categoryId)
    local ids = {
        1, 24, 7, 15, 17, 18, 19, 20, 21, 1000
    }

    return table.contains(ids, categoryId)
end

-- Get NPC buy value for a ThingType or Item
-- @param itemOrThingType: The Item or ThingType object (both have getNpcSaleData method)
-- @param useBuyPrice: true for buyPrice (what NPCs pay us), false for salePrice (what NPCs charge us)
function Cyclopedia.Items.getNpcValue(itemOrThingType, useBuyPrice)
	local npcValue = 0
	if useBuyPrice == nil then
		useBuyPrice = true  -- Default to buyPrice for backward compatibility
	end
	
	local npcSaleData = ItemsDatabase and ItemsDatabase.getNpcSaleData and ItemsDatabase.getNpcSaleData(itemOrThingType)
	if npcSaleData and #npcSaleData > 0 then
		if useBuyPrice then
			for _, npcData in ipairs(npcSaleData) do
				if npcData.buyPrice and npcData.buyPrice > npcValue then
					npcValue = npcData.buyPrice
				end
			end
		else
			for _, npcData in ipairs(npcSaleData) do
				if npcData.salePrice and npcData.salePrice > npcValue then
					npcValue = npcData.salePrice
				end
			end
		end
	end
	
	return npcValue
end

-- Function to calculate market offer averages: (sell offers average + buy offers average) / 2
function Cyclopedia.Items.getMarketOfferAverages(itemId)
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType and thingType.getMeanPrice then
		return thingType:getMeanPrice() or 0
	end
	return 0
end

function Cyclopedia.Items.resolveItemLootValues(itemOrThingType)
	local item, thingType, itemId = resolveItemContext(itemOrThingType)
	if not itemId then
		return {
			item = nil,
			thingType = nil,
			itemId = nil,
			avgMarket = 0,
			npcValue = 0,
			isMarketPrice = false,
			customValue = nil,
			resultingValue = 0
		}
	end

	local avgMarket = Cyclopedia.Items.getMarketOfferAverages(itemId)
	local npcValue = Cyclopedia.Items.getNpcValue(thingType or item, true)
	local serverValue = ItemsDatabase and ItemsDatabase.getItemValue and ItemsDatabase.getItemValue(itemId) or 0

	if npcValue == 0 and serverValue > 0 then
		npcValue = serverValue
	end
	if npcValue == 0 then
		npcValue = avgMarket
	end

	local customValue = getCustomLootValue(itemId)
	local isMarketPrice = isMarketLootSource(itemId)
	local resultingValue = customValue or (isMarketPrice and avgMarket or npcValue) or 0

	return {
		item = item,
		thingType = thingType,
		itemId = itemId,
		avgMarket = avgMarket,
		npcValue = npcValue,
		isMarketPrice = isMarketPrice,
		customValue = customValue,
		resultingValue = resultingValue
	}
end

local function updateOwnValuePlaceholder()
	if not (UI and UI.InfoBase and UI.InfoBase.OwnValueEdit and UI.InfoBase.OwnValuePlaceholder) then
		return
	end

	local text = UI.InfoBase.OwnValueEdit:getText() or ""
	UI.InfoBase.OwnValuePlaceholder:setVisible(text:gsub("%s+", "") == "")
end

function Cyclopedia.Items.showItemPrice(obj)
	local resolved = Cyclopedia.Items.resolveItemLootValues(obj)
	if not resolved.itemId then
		return 0
	end

	if UI.InfoBase.MarketGoldPriceBase and UI.InfoBase.MarketGoldPriceBase.Value then
		UI.InfoBase.MarketGoldPriceBase.Value:setText(comma_value(resolved.avgMarket))
	end

	if resolved.customValue and UI.InfoBase.OwnValueEdit then
		UI.InfoBase.OwnValueEdit:setText(tostring(resolved.customValue))
	elseif UI.InfoBase.OwnValueEdit then
		UI.InfoBase.OwnValueEdit:clearText(true)
	end

	updateOwnValuePlaceholder()

	local finalValue = Cyclopedia.Items.updateResultGoldValue(resolved)

	if UI.LootValue then
		ignoreLootValueSourceCheck = true
		UI.LootValue.NpcBuyCheck:setChecked(not resolved.isMarketPrice)
		UI.LootValue.MarketCheck:setChecked(resolved.isMarketPrice)
		ignoreLootValueSourceCheck = false
	end

	return finalValue
end

local function applyItemRarityByPrice(price)
	local rarityPrice = tonumber(price) or 0

	if UI and UI.SelectedItem and UI.SelectedItem.Rarity then
		if rarityPrice > 0 then
			ItemsDatabase.setRarityItemByPrice(UI.SelectedItem.Rarity, rarityPrice)
		else
			UI.SelectedItem.Rarity:setImageSource("")
		end
		ItemsDatabase.syncRarityWidgetVisibility(UI.SelectedItem.Rarity)
	end

	if UI and UI.InfoBase and UI.InfoBase.ResultGoldBase and UI.InfoBase.ResultGoldBase.Rarity then
		if rarityPrice > 0 then
			ItemsDatabase.setRarityItemByPrice(UI.InfoBase.ResultGoldBase.Rarity, rarityPrice)
		else
			UI.InfoBase.ResultGoldBase.Rarity:setImageSource("")
		end
		ItemsDatabase.syncRarityWidgetVisibility(UI.InfoBase.ResultGoldBase.Rarity)
	end
end

function Cyclopedia.Items.getCurrentItemValue(item)
	return Cyclopedia.Items.resolveItemLootValues(item).resultingValue
end

function Cyclopedia.Items.updateResultGoldValue(resolved)
	if not UI.InfoBase.ResultGoldBase or not UI.InfoBase.ResultGoldBase.Value then
		return 0
	end

	local finalValue = resolved.resultingValue or 0

	if UI.InfoBase.OwnValueEdit then
		local ownValueText = (UI.InfoBase.OwnValueEdit:getText() or ""):gsub("%s+", "")
		if #ownValueText > 0 then
			finalValue = tonumber(ownValueText) or finalValue
		elseif not resolved.customValue then
			if resolved.isMarketPrice then
				finalValue = resolved.avgMarket > 0 and resolved.avgMarket or resolved.npcValue
			else
				finalValue = resolved.npcValue
			end
		end
	elseif not resolved.customValue then
		if resolved.isMarketPrice then
			finalValue = resolved.avgMarket > 0 and resolved.avgMarket or resolved.npcValue
		else
			finalValue = resolved.npcValue
		end
	end

	finalValue = tonumber(finalValue) or 0
	UI.InfoBase.ResultGoldBase.Value:setText(comma_value(finalValue))
	applyItemRarityByPrice(finalValue)

	return finalValue
end

function Cyclopedia.Items.onSourceValueChange(checked, npcSource)
	if checked then
		return
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local itemId = getSelectedCyclopediaItemId()
	if not itemId then
		return
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	local item = thingType and Item.create(itemId)
	local currentItemID = tostring(itemId)
	local currentPrice = 0

	if not itemsData["primaryLootValueSources"] then
		itemsData["primaryLootValueSources"] = {}
	end

	if npcSource then
		local newItemList = {}
		newItemList["primaryLootValueSources"] = {}
		for k, v in pairs(itemsData["primaryLootValueSources"]) do
			if k ~= currentItemID then
				newItemList["primaryLootValueSources"][k] = v
			end
		end

		itemsData["primaryLootValueSources"] = newItemList["primaryLootValueSources"]
		currentPrice = Cyclopedia.Items.showItemPrice(thingType or item) or 0
		if player.updateCyclopediaMarketList then
			player:updateCyclopediaMarketList(itemId, true)
		end
	else
		itemsData["primaryLootValueSources"][currentItemID] = "market"
		currentPrice = Cyclopedia.Items.showItemPrice(thingType or item) or 0
		if player.updateCyclopediaMarketList then
			player:updateCyclopediaMarketList(itemId, false)
		end
	end

	if player.updateCyclopediaCustomPrice then
		player:updateCyclopediaCustomPrice(itemId, currentPrice)
	end
	
	-- Update analyzer modules if they exist
	if modules.game_analyser then
		if modules.game_analyser.HuntingAnalyser and modules.game_analyser.HuntingAnalyser.updateLootedItemValue then
			modules.game_analyser.HuntingAnalyser:updateLootedItemValue(itemId, currentPrice)
		end
		if modules.game_analyser.LootAnalyser and modules.game_analyser.LootAnalyser.updateBasePriceFromLootedItems then
			modules.game_analyser.LootAnalyser:updateBasePriceFromLootedItems(itemId, currentPrice)
		end
	end
end

function Cyclopedia.Items.onChangeCustomPrice(widget)
	updateOwnValuePlaceholder()

	local itemId = getSelectedCyclopediaItemId()
	if not itemId then
		return
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local currentText = widget:getText()
	local item = Item.create(itemId)
	local itemIdStr = tostring(itemId)
	
	if not itemsData["customSalePrices"] then
		itemsData["customSalePrices"] = {}
	end

	if #currentText == 0 then
		local newItemList = {}
		newItemList["customSalePrices"] = {}

		for k, v in pairs(itemsData["customSalePrices"]) do
			if k ~= itemIdStr then
				newItemList["customSalePrices"][k] = v
			end
		end

		itemsData["customSalePrices"] = newItemList["customSalePrices"]
		Cyclopedia.Items.showItemPrice(item)
		
		-- Get the current item value (NPC or market based on selection)
		local itemDefaultValue = Cyclopedia.Items.getCurrentItemValue(item)
		
		if player.updateCyclopediaCustomPrice then
			player:updateCyclopediaCustomPrice(itemId, itemDefaultValue)
		end
		
		-- Update analyzer modules if they exist
		if modules.game_analyser then
			if modules.game_analyser.HuntingAnalyser then
				modules.game_analyser.HuntingAnalyser:updateLootedItemValue(itemId, itemDefaultValue)
			end
			if modules.game_analyser.LootAnalyser then
				modules.game_analyser.LootAnalyser:updateBasePriceFromLootedItems(itemId, itemDefaultValue)
			end
		end
		return
	end

	currentText = currentText:gsub("[^%d]", "")
	widget:setText(currentText)

	local numericValue = tonumber(currentText)
	if numericValue then
		if numericValue >= 999999999 then
			currentText = "999999999"
			widget:setText(currentText)
		end
	end

	numericValue = tonumber(currentText)
	if not numericValue then
		widget:setText("0")
		numericValue = 0
	end

	itemsData["customSalePrices"][itemIdStr] = numericValue

	local resolved = Cyclopedia.Items.resolveItemLootValues(item)
	resolved.customValue = numericValue
	resolved.resultingValue = numericValue
	Cyclopedia.Items.updateResultGoldValue(resolved)
	
	if player.updateCyclopediaCustomPrice then
		player:updateCyclopediaCustomPrice(itemId, numericValue)
	end
	
	-- Update analyzer modules if they exist
	if modules.game_analyser then
		if modules.game_analyser.LootAnalyser then
			modules.game_analyser.LootAnalyser:updateBasePriceFromLootedItems(itemId, numericValue)
		end
		if modules.game_analyser.HuntingAnalyser then
			modules.game_analyser.HuntingAnalyser:updateLootedItemValue(itemId, numericValue)
		end
	end
end

function showItems()
    requestServerMarketItems()

    if UI and not UI:isDestroyed() then
        setupItemsListVirtualScroll()
        UI:show()
        refreshItemsTabView()
        if not getCachedServerMarketItems() and g_game.isOnline() then
            scheduleItemsIndexRetry()
        end
        return
    end

    local container = modules.game_cyclopedia.getContentContainer()
    if not container then
        g_logger.error("cyclopedia items: content container is not available")
        return
    end

    UI = g_ui.loadUI("items", container)
    if not UI then
        g_logger.error("cyclopedia items: failed to load items UI")
        return
    end

    setupItemsListVirtualScroll()
    UI:show()
    Cyclopedia.Items.VocFilter = false
    Cyclopedia.Items.LevelFilter = false
    Cyclopedia.Items.h1Filter = false
    Cyclopedia.Items.h2Filter = false
    Cyclopedia.Items.ClassificationFilter = 0
    UI.selectedCategory = nil
    UI.LootValue.NpcBuyCheck:setChecked(true)
    UI.LootValue.MarketCheck:setChecked(false)
    UI.LootValue.NpcBuyCheck.onCheckChange = Cyclopedia.onLootValueSourceChange
    UI.LootValue.MarketCheck.onCheckChange = Cyclopedia.onLootValueSourceChange
    UI.EmptyLabel:setVisible(true)
    UI.InfoBase:setVisible(false)
    UI.LootValue:setVisible(false)
    UI.H1Button:disable()
    UI.H2Button:disable()
    UI.ItemFilter:disable()
    
    -- Initialize itemsData
    if table.empty(itemsData) then
        itemsData = {
            ["primaryLootValueSources"] = {},
            ["customSalePrices"] = {}
        }
    end
    
    -- Load JSON data
    Cyclopedia.Items.loadJson()
    
    if UI.InfoBase and UI.InfoBase.TrackCheck then
        UI.InfoBase.TrackCheck.onCheckChange = Cyclopedia.onItemTrackCheckChange
    end
    local CategoryColor = "#484848"

    for _, data in ipairs(Cyclopedia.CategoryItems) do
        local ItemCat = g_ui.createWidget("ItemCategory", UI.CategoryList)

        ItemCat:setId(data.id)
        ItemCat:setText(data.name)
        ItemCat:setBackgroundColor(CategoryColor)
        ItemCat:setPhantom(false)
        ItemCat.BaseColor = CategoryColor

        function ItemCat:onClick()
            local categoryId = tonumber(self:getId())
            if UI.selectedCategory == self and Cyclopedia.Items.currentCategoryId == categoryId then
                return
            end

            Cyclopedia.ResetItemCategorySelection(UI.CategoryList)
            self:setChecked(true)
            self:setBackgroundColor("#585858")
            Cyclopedia.selectItemCategory(categoryId)
            UI.selectedCategory = self
        end

        CategoryColor = CategoryColor == "#484848" and "#414141" or "#484848"
    end

    Cyclopedia.ItemList = {}
    Cyclopedia.AllItemList = {}

    focusCategoryList = UI.CategoryList

    g_keyboard.bindKeyPress('Down', function()
        focusCategoryList:focusNextChild(KeyboardFocusReason)
    end, focusCategoryList:getParent())

    g_keyboard.bindKeyPress('Up', function()
        focusCategoryList:focusPreviousChild(KeyboardFocusReason)
    end, focusCategoryList:getParent())

    connect(focusCategoryList, {
        onChildFocusChange = function(self, focusedChild)
            if focusedChild == nil then
                return
            end
            focusedChild:onClick()
        end
    })

    refreshItemsTabView()
    if not getCachedServerMarketItems() and g_game.isOnline() then
        scheduleItemsIndexRetry()
    end
end

function Cyclopedia.selectDefaultItemCategory()
    if not UI or not UI.CategoryList then
        return
    end

    if UI.selectedCategory and UI.selectedCategory:getParent() then
        UI.selectedCategory:onClick()
        return
    end

    for _, data in ipairs(Cyclopedia.CategoryItems) do
        local items = Cyclopedia.ItemList[data.id]
        if items and #items > 0 then
            local category = UI.CategoryList:getChildById(tostring(data.id))
            if category then
                category:onClick()
                return
            end
        end
    end

    local firstCategory = UI.CategoryList:getFirstChild()
    if firstCategory then
        firstCategory:onClick()
    end
end

function Cyclopedia.onCategoryChange(widget)
    if not widget then
        return
    end
    if widget.isChecked and not widget:isChecked() then
        return
    end

    local categoryId = tonumber(widget:getId())
    if UI.selectedCategory == widget and Cyclopedia.Items.currentCategoryId == categoryId then
        return
    end

    Cyclopedia.selectItemCategory(categoryId)
    UI.selectedCategory = widget
end

function Cyclopedia.onLootValueSourceChange(widget, checked)
    if ignoreLootValueSourceCheck or not widget or not UI or not UI.LootValue then
        return
    end

    local npcCheck = UI.LootValue.NpcBuyCheck
    local marketCheck = UI.LootValue.MarketCheck
    if not npcCheck or not marketCheck then
        return
    end

    if not checked then
        ignoreLootValueSourceCheck = true
        widget:setChecked(true)
        ignoreLootValueSourceCheck = false
        return
    end

    ignoreLootValueSourceCheck = true
    if widget == npcCheck or widget:getId() == "NpcBuyCheck" then
        marketCheck:setChecked(false)
        Cyclopedia.Items.onSourceValueChange(false, true)
    else
        npcCheck:setChecked(false)
        Cyclopedia.Items.onSourceValueChange(false, false)
    end
    ignoreLootValueSourceCheck = false
end

function Cyclopedia.vocationFilter(value)
    Cyclopedia.Items.VocFilter = value
    Cyclopedia.applyFilters()
end

function Cyclopedia.levelFilter(value)
    Cyclopedia.Items.LevelFilter = value
    Cyclopedia.applyFilters()
end

function Cyclopedia.onItemsFilterButtonClick(widget)
    if not widget then
        return
    end

    local widgetId = widget:getId()
    local checked = not widget:isChecked()
    widget:setChecked(checked)

    if widgetId == "LevelButton" then
        Cyclopedia.levelFilter(checked)
    elseif widgetId == "VocationButton" then
        Cyclopedia.vocationFilter(checked)
    elseif widgetId == "H1Button" then
        Cyclopedia.handFilter(checked, false)
    elseif widgetId == "H2Button" then
        Cyclopedia.handFilter(false, checked)
    end
end

local ignoreRecursiveCalls = false
local function setCheckedWithoutRecursion(h1Val, h2Val)
    ignoreRecursiveCalls = true
    UI.H1Button:setChecked(h1Val)
    UI.H2Button:setChecked(h2Val)
    ignoreRecursiveCalls = false
end

function Cyclopedia.handFilter(h1Val, h2Val)
    Cyclopedia.Items.h1Filter = h1Val
    Cyclopedia.Items.h2Filter = h2Val

    if ignoreRecursiveCalls then
        return
    end

    setCheckedWithoutRecursion(h1Val, h2Val)
    Cyclopedia.applyFilters()
end

function Cyclopedia.classificationFilter(data)
    Cyclopedia.Items.ClassificationFilter = tonumber(data)
    Cyclopedia.applyFilters()
end

local function collectCategoryEntries(categoryId)
    local entries = {}
    local idsToProcess = categoryId == 1000 and { 17, 18, 19, 20, 21 } or { categoryId }

    for i = 1, #idsToProcess do
        local categoryItems = Cyclopedia.ItemList[idsToProcess[i]]
        if categoryItems then
            for j = 1, #categoryItems do
                local entry = categoryItems[j]
                if passesItemFilters(entry) then
                    entries[#entries + 1] = entry
                end
            end
        end
    end

    table.sort(entries, Cyclopedia.compareItems)
    return entries
end

processItemsById = function(id)
    refreshItemsListView(collectCategoryEntries(id), { selectSingle = false })
end

function Cyclopedia.applyFilters()
    if not UI then
        return
    end

    local searchText = UI.SearchEdit and UI.SearchEdit:getText() or ""
    if searchText:match("%S") then
        Cyclopedia.ItemSearch(searchText, false)
        return
    end

    local categoryId = UI.selectedCategory and tonumber(UI.selectedCategory:getId())
    if not categoryId then
        categoryId = Cyclopedia.Items.currentCategoryId
    end

    if categoryId then
        processItemsById(categoryId)
    end
end

function Cyclopedia.selectItemEntry(entry, widget)
    local data = resolveThingType(entry)
    if not data then
        return
    end

    local itemId = entry.id or data:getId()
    if tonumber(Cyclopedia.Items.currentItemId) == itemId then
        if widget and UI.selectItem ~= widget then
            if UI.selectItem then
                UI.selectItem:setBackgroundColor("#00000000")
            end
            widget:setBackgroundColor("#585858")
            UI.selectItem = widget
        end
        return
    end

    UI.InfoBase.SellBase.List:destroyChildren()
    UI.InfoBase.BuyBase.List:destroyChildren()

    local oldSelected = UI.selectItem
    local lootValue = UI.LootValue

    if oldSelected and oldSelected ~= widget then
        oldSelected:setBackgroundColor("#00000000")
    end

    Cyclopedia.Items.currentItemId = itemId
    Cyclopedia.showItemDetailLoading()
    Cyclopedia.scheduleItemDetailFallback(itemId)
    if g_game.isOnline() then
        g_game.inspectionObject(InspectObjectTypes.INSPECT_CYCLOPEDIA, itemId, 1)
    else
        Cyclopedia.loadItemDetail(itemId, Cyclopedia.buildLocalItemDescriptions(itemId))
    end

    if not lootValue:isVisible() then
        lootValue:setVisible(true)
    end

    UI.EmptyLabel:setVisible(false)
    UI.InfoBase:setVisible(true)
    UI.SelectedItem.Sprite:setItemId(itemId)

    lastSelectedItem = widget

    local resultingValue = Cyclopedia.Items.showItemPrice(data) or 0
    if widget then
        widget.Value = resultingValue
        widget:setBackgroundColor("#585858")
        UI.selectItem = widget
    end

    repaintItemsListPool(itemId)

    UI.InfoBase.quickLootCheck.onCheckChange = function(widget, checked)
        Cyclopedia.Items.manageQuickloot(widget, checked)
    end
    Cyclopedia.refreshQuickLootCheck()

    if UI.InfoBase.TrackCheck then
        local originalCallback = UI.InfoBase.TrackCheck.onCheckChange
        UI.InfoBase.TrackCheck.onCheckChange = nil
        UI.InfoBase.TrackCheck.itemId = itemId
        UI.InfoBase.TrackCheck:setChecked(Cyclopedia.Items.isInDropTracker(itemId))
        UI.InfoBase.TrackCheck.onCheckChange = originalCallback
    end

    if UI.InfoBase.OwnValueEdit then
        UI.InfoBase.OwnValueEdit.onTextChange = function(self)
            Cyclopedia.Items.onChangeCustomPrice(self)
        end
    end

    Cyclopedia.refreshNpcSaleLists(itemId)
    if ItemsDatabase and ItemsDatabase.requestServerItemDetails then
        ItemsDatabase.requestServerItemDetails(itemId)
    end
end

function Cyclopedia.ItemSearch(text, clearTextEdit)
    cancelItemSearchEvent()

    if not UI then
        return
    end

    text = text or ""

    if text == "" then
        UI.SelectedItem.Sprite:setItemId(0)
        UI.SelectedItem.Rarity:setImageSource("")

        if UI.selectedCategory then
            processItemsById(tonumber(UI.selectedCategory:getId()))
        else
            refreshItemsListView({})
        end

        if clearTextEdit then
            UI.SearchEdit:setText("")
        end
        return
    end

    UI.SelectedItem.Sprite:setItemId(0)
    UI.SelectedItem.Rarity:setImageSource("")

    local oldSelected = UI.selectedCategory
    if oldSelected then
        oldSelected:setBackgroundColor(oldSelected.BaseColor)
        oldSelected:setChecked(false)
    end

    local searchTermLower = string.lower(text)
    local searchById = tonumber(text)
    local searchedItems = {}
    local totalItems = #Cyclopedia.AllItemList

    if not searchById and totalItems > 500 and #searchTermLower < ITEM_SEARCH_MIN_LENGTH then
        refreshItemsListView({})
        if clearTextEdit then
            UI.SearchEdit:setText("")
        end
        return
    end

    for i = 1, totalItems do
        local entry = Cyclopedia.AllItemList[i]
        local itemNameLower = entry.nameLower or string.lower(entry.name or "")

        if (searchById and entry.id == searchById) or itemNameLower:find(searchTermLower, 1, true) then
            if passesItemFilters(entry) then
                searchedItems[#searchedItems + 1] = entry
            end
        end
    end

    table.sort(searchedItems, Cyclopedia.compareItems)
    refreshItemsListView(searchedItems, {
        autoSelectId = Cyclopedia.Items.pendingOpenItemId,
        selectSingle = true,
        immediate = true,
        selectDelay = ITEM_SEARCH_SELECT_DELAY_MS
    })

    if #searchedItems == 0 and not getCachedServerMarketItems() and g_game.isOnline() then
        Cyclopedia.Items.pendingSearchText = text
        requestServerMarketItems()
        scheduleItemsIndexRetry()
    end

    if clearTextEdit then
        UI.SearchEdit:setText("")
    end
end

function Cyclopedia.selectItemCategory(id)
    id = tonumber(id)
    if Cyclopedia.Items.currentCategoryId == id then
        return
    end

    Cyclopedia.Items.currentCategoryId = id

    setCheckedWithoutRecursion(false, false)
    UI.LevelButton:setChecked(false)
    UI.VocationButton:setChecked(false)
    Cyclopedia.Items.VocFilter = false
    Cyclopedia.Items.LevelFilter = false

    if UI.SearchEdit:getText() ~= "" then
        Cyclopedia.ItemSearch("", true)
    end

    if Cyclopedia.hasClassificationFilter(id) then
        UI.ItemFilter:clearOptions()
        UI.ItemFilter:addOption("All", 0, true)
        UI.ItemFilter:addOption("None", -1, true)

        for class = 1, 4 do
            UI.ItemFilter:addOption("Class " .. class, class, true)
        end

        UI.ItemFilter:enable()
    else
        UI.ItemFilter:clearOptions()
        Cyclopedia.Items.ClassificationFilter = 0
        UI.ItemFilter:disable()
    end

    processItemsById(id)

    if Cyclopedia.hasHandedFilter(id) then
        UI.H1Button:enable()
        UI.H2Button:enable()
    else
        UI.H1Button:disable()
        UI.H2Button:disable()
    end
end

local function appendItemEntry(tempItemList, entry)
    local category = normalizeItemCategory(entry.category)

    if not tempItemList[category] then
        tempItemList[category] = {}
    end

    table.insert(Cyclopedia.AllItemList, entry)
    table.insert(tempItemList[category], entry)
end

function Cyclopedia.loadItemsCategories(force)
    if not force and isItemsIndexUpToDate() then
        return false
    end

    Cyclopedia.ItemList = {}
    Cyclopedia.AllItemList = {}

    local tempItemList = {}
    local seen = {}

    local function tryAddEntry(entry)
        if not entry or seen[entry.id] then
            return
        end
        seen[entry.id] = true
        appendItemEntry(tempItemList, entry)
    end

    local serverEntries = collectServerMarketEntries()
    if serverEntries then
        for i = 1, #serverEntries do
            tryAddEntry(serverEntries[i])
        end
    end

    for _, thingType in pairs(collectDatMarketItemTypes()) do
        if thingType then
            tryAddEntry(buildItemIndexEntry(thingType))
        end
    end

    table.sort(Cyclopedia.AllItemList, Cyclopedia.compareItems)

    for category, itemList in pairs(tempItemList) do
        table.sort(itemList, Cyclopedia.compareItems)
        Cyclopedia.ItemList[category] = itemList
    end

    local source, count = getItemsIndexCacheToken()
    Cyclopedia.Items.indexCacheSource = source
    Cyclopedia.Items.indexCacheCount = count

    if getCachedServerMarketItems() then
        Cyclopedia.Items.indexRetryCount = 0
    end

    return true
end

function Cyclopedia.applyItemsIndexRefresh()
    refreshItemsTabView()
end

function Cyclopedia.onMarketItemsUpdated()
    Cyclopedia.applyItemsIndexRefresh()
end

function Cyclopedia.showItemDetailLoading()
    if not (UI and UI.InfoBase and UI.InfoBase.DetailsBase and UI.InfoBase.DetailsBase.List) then
        return
    end

    Cyclopedia.Items.currentItemDescriptions = nil

    local list = UI.InfoBase.DetailsBase.List
    list:destroyChildren()

    local label = g_ui.createWidget("Label", list)
    label:setText(tr("Status: Loading, please wait..."))
    label:setColor("#C0C0C0")
    label:setFont("Verdana Bold-11px")
    label:setTextAlign(AlignCenter)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
end

local function resolveInspectionItem(data)
    if type(data) ~= "table" then
        return nil
    end

    local item = data.item
    if not item and data.itemId then
        item = Item.create(tonumber(data.itemId))
    elseif type(item) == "number" then
        item = Item.create(item)
    end

    return item
end

function Cyclopedia.buildLocalItemDescriptions(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return {}
    end

    local thingType = g_things.getThingType(itemId, ThingCategoryItem)
    if not thingType then
        return {}
    end

    local descriptions = {}
    local name = getServerMarketItemName(itemId)
    if not name or name == "" then
        name = Cyclopedia.getItemDisplayName(thingType)
    end

    if name and name ~= "" then
        descriptions[#descriptions + 1] = { key = "Name", value = name }
    end

    local description = thingType:getDescription()
    if description and description ~= "" then
        descriptions[#descriptions + 1] = { key = "Description", value = description }
    end

    return ensureClassificationDescription(itemId, descriptions)
end

function Cyclopedia.isItemsTabActive()
    local cyclopediaMod = modules.game_cyclopedia
    if not cyclopediaMod or not cyclopediaMod.getCurrentType or cyclopediaMod.getCurrentType() ~= "items" then
        return false
    end

    if cyclopediaMod.isVisible and not cyclopediaMod.isVisible() then
        return false
    end

    return UI and not UI:isDestroyed()
end

function Cyclopedia.receiveItemDetail(data)
    if not Cyclopedia.isItemsTabActive() then
        return false
    end

    local item = resolveInspectionItem(data)
    local itemId = item and item:getId() or tonumber(Cyclopedia.Items.currentItemId)
    if not itemId or itemId <= 0 then
        return false
    end

    local currentItemId = tonumber(Cyclopedia.Items.currentItemId)
    if currentItemId and itemId ~= currentItemId then
        return false
    end

    local descriptions = data and data.descriptions or {}
    if #descriptions == 0 then
        descriptions = Cyclopedia.buildLocalItemDescriptions(itemId)
    end

    Cyclopedia.loadItemDetail(itemId, descriptions)
    cancelItemDetailFallback()
    return true
end

function Cyclopedia.scheduleItemDetailFallback(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end

    cancelItemDetailFallback()
    Cyclopedia.Items.detailFallbackEvent = scheduleEvent(function()
        Cyclopedia.Items.detailFallbackEvent = nil
        if tonumber(Cyclopedia.Items.currentItemId) ~= itemId then
            return
        end

        if not Cyclopedia.isItemsTabActive() then
            return
        end

        if not (UI and UI.InfoBase and UI.InfoBase.DetailsBase and UI.InfoBase.DetailsBase.List) then
            return
        end

        local list = UI.InfoBase.DetailsBase.List
        if list:getChildCount() ~= 1 then
            return
        end

        local child = list:getFirstChild()
        if not child or not child:getText() or not child:getText():find("Loading", 1, true) then
            return
        end

        Cyclopedia.loadItemDetail(itemId, Cyclopedia.buildLocalItemDescriptions(itemId))
    end, 750)
end

local function getDescriptionPair(data)
    if type(data) ~= "table" then
        return nil, nil
    end

    local key = data.key or data[1]
    local value = data.value or data[2]
    if key == nil or value == nil then
        return nil, nil
    end

    key = tostring(key):gsub("^%s+", ""):gsub("%s+$", "")
    value = tostring(value)
    if key == "" or value == "" then
        return nil, nil
    end

    return key, value
end

local function resolveCyclopediaItemName(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return ""
    end

    if UI and UI.selectItem and UI.selectItem.Name then
        local selectedName = UI.selectItem.Name:getText()
        if selectedName and selectedName ~= "" then
            return selectedName
        end
    end

    local itemName = getServerMarketItemName(itemId)
    if itemName and itemName ~= "" then
        return itemName
    end

    local thingType = g_things.getThingType(itemId, ThingCategoryItem)
    return thingType and Cyclopedia.getItemDisplayName(thingType) or ""
end

local function collectDetailRowsFromDescriptions(descriptions)
    local rows = {}
    if type(descriptions) ~= "table" then
        return rows
    end

    for i = 1, #descriptions do
        local key, value = getDescriptionPair(descriptions[i])
        if key and value then
            rows[#rows + 1] = { key = key, value = value }
        end
    end

    if #rows == 0 then
        for _, data in pairs(descriptions) do
            local key, value = getDescriptionPair(data)
            if key and value then
                rows[#rows + 1] = { key = key, value = value }
            end
        end
    end

    return rows
end

local function collectDetailRowsFromList(list)
    local rows = {}
    if not list then
        return rows
    end

    for _, row in ipairs(list:getChildren()) do
        local children = row:getChildren()
        if #children == 1 and children[1].getText then
            local text = children[1]:getText() or ""
            local key, value = text:match("^([^:]+):%s*(.+)$")
            if key and value and not key:find("Status", 1, true) then
                rows[#rows + 1] = { key = key, value = value }
            end
        elseif #children >= 2 and children[1].getText and children[2].getText then
            local key = (children[1]:getText() or ""):gsub(":%s*$", "")
            local value = children[2]:getText() or ""
            if key ~= "" and value ~= "" and not key:find("Status", 1, true) then
                rows[#rows + 1] = { key = key, value = value }
            end
        elseif row.getText then
            local text = row:getText() or ""
            if text ~= "" and not text:find("Loading", 1, true) and not text:find("No details available", 1, true) then
                local key, value = text:match("^([^:]+):%s*(.+)$")
                if key and value then
                    rows[#rows + 1] = { key = key, value = value }
                end
            end
        end
    end

    return rows
end

local function buildItemDetailsCopyText()
    local rows = {}
    local list = UI and UI.InfoBase and UI.InfoBase.DetailsBase and UI.InfoBase.DetailsBase.List

    if list and list:getChildCount() > 0 then
        rows = collectDetailRowsFromList(list)
    end

    if #rows == 0 then
        rows = collectDetailRowsFromDescriptions(Cyclopedia.Items.currentItemDescriptions)
    end

    local lines = {}
    local itemName = resolveCyclopediaItemName(Cyclopedia.Items.currentItemId)
    if itemName ~= "" then
        lines[#lines + 1] = string.format("You are inspecting: %s", itemName)
    end

    for i = 1, #rows do
        lines[#lines + 1] = string.format("%s: %s", rows[i].key, rows[i].value)
    end

    return table.concat(lines, "\n")
end

function Cyclopedia.copyItemDetailsToClipboard()
    if not g_window or not g_window.setClipboardText then
        return
    end

    local text = buildItemDetailsCopyText()
    if text and text ~= "" then
        g_window.setClipboardText(text)
    end
end

function Cyclopedia.loadItemDetail(itemId, descriptions)
    if not (UI and UI.InfoBase and UI.InfoBase.DetailsBase) then
        return
    end

    UI.InfoBase.DetailsBase.List:destroyChildren()
    descriptions = descriptions or {}
    itemId = tonumber(itemId)

    if #descriptions == 0 and itemId then
        descriptions = Cyclopedia.buildLocalItemDescriptions(itemId)
    elseif itemId then
        descriptions = ensureClassificationDescription(itemId, descriptions)
    end

    local list = UI.InfoBase.DetailsBase.List
    local renderedDescriptions = {}

    for _, description in ipairs(descriptions) do
        local key, value = getDescriptionPair(description)
        if key and value then
            Cyclopedia.appendDetailCenteredRow(list, key, value)
            renderedDescriptions[#renderedDescriptions + 1] = { key = key, value = value }
        end
    end

    if #renderedDescriptions == 0 then
        for _, description in pairs(descriptions) do
            local key, value = getDescriptionPair(description)
            if key and value then
                Cyclopedia.appendDetailCenteredRow(list, key, value)
                renderedDescriptions[#renderedDescriptions + 1] = { key = key, value = value }
            end
        end
    end

    Cyclopedia.Items.currentItemDescriptions = renderedDescriptions

    if list:getChildCount() == 0 then
        Cyclopedia.appendDetailCenteredRow(list, tr("Status"), tr("No details available."))
    end

    local layout = list:getLayout()
    if layout then
        layout:update()
    end
end

function Cyclopedia.onItemTrackCheckChange(widget, checked)
    if widget._suppressTrackCheckChange then
        return
    end

    local itemId = tonumber(Cyclopedia.Items.currentItemId)
    if not itemId then
        return
    end

    if checked then
        Cyclopedia.Items.addToDropTracker(itemId)
    else
        Cyclopedia.Items.removeFromDropTracker(itemId)
    end
end

function Cyclopedia.focusItem(itemId, itemName)
    if not UI or UI:isDestroyed() then
        return false
    end

    itemId = tonumber(itemId)
    itemName = resolveFocusItemName(itemId, itemName)

    if itemId and selectItemInList(itemId) then
        if UI.SearchEdit and itemName ~= '' then
            UI.SearchEdit:setText(itemName)
        end
        return true
    end

    local searchText = itemName ~= '' and itemName or (itemId and tostring(itemId) or '')
    if searchText == '' then
        return false
    end

    if UI.SearchEdit then
        UI.SearchEdit:setText(searchText)
    end
    Cyclopedia.ItemSearch(searchText, false)

    if itemId and selectItemInList(itemId) then
        return true
    end

    if #(Cyclopedia.Items.listScroll.listData or {}) == 1 then
        return selectItemInList(Cyclopedia.Items.listScroll.listData[1].id)
    end

    if itemId then
        setPendingItemOpen(itemId, itemName ~= '' and itemName or nil)
        if not getCachedServerMarketItems() and g_game.isOnline() then
            requestServerMarketItems()
            scheduleItemsIndexRetry()
        end
    end

    return false
end

function Cyclopedia.openItem(arg)
    local itemId
    local itemName

    if type(arg) == 'number' then
        itemId = arg
        local thingType = g_things.getThingType(itemId, ThingCategoryItem)
        if not Cyclopedia.canShowInItemsTab(thingType) then
            return
        end
        itemName = getServerMarketItemName(itemId)
        if not itemName or itemName == '' then
            itemName = thingType and Cyclopedia.getItemDisplayName(thingType) or ''
        end
    else
        itemName = tostring(arg or '')
    end

    if not itemId and itemName == '' then
        return
    end

    setPendingItemOpen(itemId, itemName ~= '' and itemName or nil)
    modules.game_cyclopedia.show('items')

    scheduleEvent(function()
        Cyclopedia.focusItem(itemId, itemName)
    end, 100)
end

local NPC_SALE_COLOR_PRICE = TextColors.yellow
local NPC_SALE_COLOR_NAME = TextColors.lootBlue
local NPC_SALE_COLOR_RESIDENCE = "#90EE90"
local NPC_SALE_COLOR_DEFAULT = "#C0C0C0"

local function sanitizeColoredText(value)
	return tostring(value or ""):gsub("}", "")
end

local function formatNpcSaleRowColored(price, name, location)
	local priceText = sanitizeColoredText(Cyclopedia.formatGold(price))
	local nameText = sanitizeColoredText(name)
	local locationText = sanitizeColoredText(location)

	return {
		priceText, NPC_SALE_COLOR_PRICE,
		" gp, ", NPC_SALE_COLOR_DEFAULT,
		nameText, NPC_SALE_COLOR_NAME,
		"\n", NPC_SALE_COLOR_DEFAULT,
		"Residence", NPC_SALE_COLOR_RESIDENCE,
		": " .. locationText, NPC_SALE_COLOR_DEFAULT,
	}
end

local function setNpcSaleRowText(widget, value)
	if widget.setColoredText then
		widget:setColoredText(value)
	elseif type(value) == "table" then
		local plain = {}
		for i = 1, #value, 2 do
			plain[#plain + 1] = tostring(value[i] or "")
		end
		widget:setText(table.concat(plain))
	else
		widget:setText(value)
	end
end

local function setNpcSaleSectionVisible(label, panel, visible)
	if label then
		label:setVisible(visible)
	end
	if panel then
		panel:setVisible(visible)
	end
end

local function sortSaleRowsByLocationThenName(rows)
    table.sort(rows, function(a, b)
        local locA = string.lower(a.value.various and "Various Locations" or a.value.location or "")
        local locB = string.lower(b.value.various and "Various Locations" or b.value.location or "")

        if locA ~= locB then
            return locA < locB
        end

        return string.lower(a.name) < string.lower(b.name)
    end)
end

function Cyclopedia.refreshNpcSaleLists(itemId)
    if not (UI and UI.InfoBase and UI.InfoBase.SellBase and UI.InfoBase.BuyBase) then
        return
    end

    itemId = tonumber(itemId) or tonumber(Cyclopedia.Items.currentItemId)
    if not itemId then
        return
    end

    UI.InfoBase.SellBase.List:destroyChildren()
    UI.InfoBase.BuyBase.List:destroyChildren()

    local npcSaleData = ItemsDatabase and ItemsDatabase.getNpcSaleData and ItemsDatabase.getNpcSaleData(itemId) or {}
    local buy, sell = Cyclopedia.formatSaleData(npcSaleData)
    local sellColor = "#484848"

    for index, value in ipairs(sell) do
        local t_widget = g_ui.createWidget("UIWidget", UI.InfoBase.SellBase.List)
        t_widget:setId(index)
        setNpcSaleRowText(t_widget, value)
        t_widget:setTextAlign(AlignLeft)
        t_widget:setTextWrap(true)
        t_widget:setHeight(40)
        t_widget:setBackgroundColor(sellColor)
        t_widget.BaseColor = sellColor

        function t_widget:onClick()
            Cyclopedia.ResetItemCategorySelection(UI.InfoBase.SellBase.List)
            self:setChecked(true)
            self:setBackgroundColor("#585858")
        end

        sellColor = sellColor == "#484848" and "#414141" or "#484848"
    end

    local buyColor = "#484848"

    for index, value in ipairs(buy) do
        local t_widget = g_ui.createWidget("UIWidget", UI.InfoBase.BuyBase.List)
        t_widget:setId(index)
        setNpcSaleRowText(t_widget, value)
        t_widget:setTextAlign(AlignLeft)
        t_widget:setTextWrap(true)
        t_widget:setHeight(40)
        t_widget:setBackgroundColor(buyColor)
        t_widget.BaseColor = buyColor

        function t_widget:onClick()
            Cyclopedia.ResetItemCategorySelection(UI.InfoBase.BuyBase.List)
            self:setChecked(true)
            self:setBackgroundColor("#585858")
        end

        buyColor = buyColor == "#484848" and "#414141" or "#484848"
    end

    setNpcSaleSectionVisible(UI.InfoBase.SellLabel, UI.InfoBase.SellBase, #sell > 0)
    setNpcSaleSectionVisible(UI.InfoBase.BuyLabel, UI.InfoBase.BuyBase, #buy > 0)
end

function Cyclopedia.Items.onServerItemDetails(itemId)
    itemId = tonumber(itemId)
    if not itemId or tonumber(Cyclopedia.Items.currentItemId) ~= itemId then
        return
    end

    if not Cyclopedia.isItemsTabActive() then
        return
    end

    Cyclopedia.refreshNpcSaleLists(itemId)
end

function Cyclopedia.formatSaleData(data)
    local sell, buy = {}, {}

    if not data or #data == 0 then
        return buy, sell
    end

    local s, b = {}, {}

    for i = 1, #data do
        local value = data[i]

        if value then
            if value.salePrice > 0 then
                if s[value.name] and value.name == "Rashid" then
                    s[value.name].various = true
                end

                if not s[value.name] then
                    s[value.name] = {
                        various = false,
                        price = value.salePrice,
                        location = value.location
                    }
                end
            end

            if value.buyPrice > 0 then
                if b[value.name] and value.name == "Rashid" then
                    b[value.name].various = true
                end

                if not b[value.name] then
                    b[value.name] = {
                        various = false,
                        price = value.buyPrice,
                        location = value.location
                    }
                end
            end
        end
    end

    local sellRows = {}

    for name, value in pairs(s) do
        table.insert(sellRows, {
            name = name,
            value = value
        })
    end

    sortSaleRowsByLocationThenName(sellRows)

    for _, row in ipairs(sellRows) do
        local name, value = row.name, row.value

        if value.various then
            table.insert(sell, formatNpcSaleRowColored(value.price, name, "Various Locations"))
        else
            table.insert(sell, formatNpcSaleRowColored(value.price, name, value.location))
        end
    end

    local buyRows = {}

    for name, value in pairs(b) do
        table.insert(buyRows, {
            name = name,
            value = value
        })
    end

    sortSaleRowsByLocationThenName(buyRows)

    for _, row in ipairs(buyRows) do
        local name, value = row.name, row.value

        if value.various then
            table.insert(buy, formatNpcSaleRowColored(value.price, name, "Various Locations"))
        else
            table.insert(buy, formatNpcSaleRowColored(value.price, name, value.location))
        end
    end

    return buy, sell
end

function Cyclopedia.formatGold(value)
    return comma_value(value or 0)
end

function Cyclopedia.Items.addToDropTracker(itemId)
    if modules.game_analyser and modules.game_analyser.managerDropTracker then
        modules.game_analyser.managerDropTracker(itemId, true)
    end
    
    -- Also store in our JSON backup
    if not itemsData["dropTrackerItems"] then
        itemsData["dropTrackerItems"] = {}
    end
    itemsData["dropTrackerItems"][tostring(itemId)] = true
    Cyclopedia.Items.saveJson()
    
    -- Update visual feedback for all items with this ID
    Cyclopedia.Items.updateItemVisualFeedback(itemId, true)
end

function Cyclopedia.Items.removeFromDropTracker(itemId)
    if modules.game_analyser and modules.game_analyser.managerDropTracker then
        modules.game_analyser.managerDropTracker(itemId, false)
    end
    
    -- Also remove from our JSON backup
    if itemsData["dropTrackerItems"] then
        itemsData["dropTrackerItems"][tostring(itemId)] = nil
        Cyclopedia.Items.saveJson()
    end
    
    -- Update visual feedback for all items with this ID
    Cyclopedia.Items.updateItemVisualFeedback(itemId, false)
end

function Cyclopedia.Items.updateItemVisualFeedback(itemId, isTracked)
    local scrollState = Cyclopedia.Items.listScroll
    if not scrollState or not scrollState.listPool then
        return
    end

    for _, widget in ipairs(scrollState.listPool) do
        if widget.cyclopediaItemId == itemId and widget.Name then
            widget.Name:setColor(isTracked and "#FF9854" or "#c0c0c0")
        end
    end
end

function Cyclopedia.Items.isInDropTracker(itemId)
    -- First try the game_analyser module
    if modules.game_analyser and modules.game_analyser.isInDropTracker then
        local inAnalyser = modules.game_analyser.isInDropTracker(itemId)
        if inAnalyser then
            return true
        end
    end
    
    -- Fallback to our JSON backup
    if itemsData["dropTrackerItems"] and itemsData["dropTrackerItems"][tostring(itemId)] then
        return true
    end
    
    return false
end

-- Helper functions for Drop Tracker integration (avoiding circular dependencies)
function Cyclopedia.Items.removeFromDropTrackerDirectly(itemId)
    -- Remove from our JSON backup without calling back to game_analyser
    if itemsData["dropTrackerItems"] then
        itemsData["dropTrackerItems"][tostring(itemId)] = nil
        Cyclopedia.Items.saveJson()
    end
    
    -- Update visual feedback for all items with this ID
    Cyclopedia.Items.updateItemVisualFeedback(itemId, false)
end

function Cyclopedia.Items.refreshCurrentItem()
    -- Force refresh the currently displayed item's tracking state
    if UI and UI.InfoBase and UI.InfoBase.TrackCheck and UI.InfoBase.TrackCheck.itemId then
        local itemId = UI.InfoBase.TrackCheck.itemId
        
        -- Temporarily disable the callback to prevent unwanted triggers
        local originalCallback = UI.InfoBase.TrackCheck.onCheckChange
        UI.InfoBase.TrackCheck.onCheckChange = nil
        
        local inTracker = Cyclopedia.Items.isInDropTracker(itemId)
        UI.InfoBase.TrackCheck:setChecked(inTracker)
        
        -- Restore the callback
        UI.InfoBase.TrackCheck.onCheckChange = originalCallback
    end
end

function Cyclopedia.Items.removeAllFromDropTrackerDirectly()
    -- Clear all drop tracker items from our JSON backup without calling back to game_analyser
    if itemsData then
        itemsData["dropTrackerItems"] = {}
        Cyclopedia.Items.saveJson()
    end
    
    repaintItemsListPool()
end

local function getQuickLootModule()
    return modules.game_quickloot and modules.game_quickloot.QuickLoot
end

function Cyclopedia.refreshQuickLootCheck()
    if not Cyclopedia.isItemsTabActive() or not (UI and UI.InfoBase and UI.InfoBase.quickLootCheck) then
        return
    end

    local quickLoot = getQuickLootModule()
    local check = UI.InfoBase.quickLootCheck
    if not quickLoot or not quickLoot.data then
        return
    end

    if quickLoot.data.filter == 2 then
        check:setText(tr("Loot when Quick Looting"))
    else
        check:setText(tr("Skip when Quick Looting"))
    end

    local itemId = tonumber(Cyclopedia.Items.currentItemId)
    local callback = check.onCheckChange
    check.onCheckChange = nil
    if itemId then
        check:setChecked(quickLoot.lootExists(itemId, quickLoot.data.filter))
    else
        check:setChecked(false)
    end
    check.onCheckChange = callback
end

function Cyclopedia.Items.manageQuickloot(widget, checked)
    local quickLoot = getQuickLootModule()
    local itemId = getSelectedCyclopediaItemId()
    if not quickLoot or not itemId then
        if widget then
            widget:setChecked(false)
        end
        return
    end

    if checked then
        quickLoot.addLootList(itemId, quickLoot.data.filter)
    else
        quickLoot.removeLootList(itemId, quickLoot.data.filter)
    end
end

function Cyclopedia.Items.onClickLootContainers()
    local quickLoot = getQuickLootModule()
    if quickLoot and quickLoot.toggle then
        quickLoot.toggle()
    end
end

function Cyclopedia.onSearchClearButtonClick()
    if not UI then
        return
    end

    Cyclopedia.ItemSearch("", true)
end

function Cyclopedia.onItemSearchTextChange(text)
    if not UI then
        return
    end

    cancelItemSearchEvent()
    Cyclopedia.Items.searchEvent = scheduleEvent(function()
        Cyclopedia.Items.searchEvent = nil
        Cyclopedia.ItemSearch(text, false)
    end, ITEM_SEARCH_DEBOUNCE_MS)
end

modules.game_cyclopedia.CyclopediaItems = Cyclopedia.Items
modules.game_cyclopedia.Cyclopedia = Cyclopedia
modules.game_cyclopedia.itemsData = itemsData

-- End of Cyclopedia Items module
