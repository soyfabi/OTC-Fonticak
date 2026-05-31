local itemsPanel
local widgets = {}
local marketItems = {}
local allItems = {}
local selectedCategoryId
local selectedEntry
local selectedRow
local selectedBuyRow
local selectedSellRow
local internalChange = false

CyclopediaItems = CyclopediaItems or {}

local SEARCH_LIMIT = 200
local GOLD_CATEGORY = 30
local UNSORTED_CATEGORY = 31
local WEAPONS_ALL_CATEGORY = 255

local enableCategories = {
	[17] = true, [18] = true, [19] = true, [20] = true, [21] = true, [27] = true,
	[MarketCategoryWeaponsAmmo or -1] = true,
	[MarketCategoryWeaponsAxes or -1] = true,
	[MarketCategoryWeaponsClubs or -1] = true,
	[MarketCategoryWeaponsDistance or -1] = true,
	[MarketCategoryWeaponsSwords or -1] = true,
	[MarketCategoryWeaponsWands or -1] = true,
	[MarketCategoryWeaponsAll or -1] = true
}

local enableClassification = {
	[1] = true, [3] = true, [7] = true, [8] = true, [13] = true, [15] = true,
	[17] = true, [18] = true, [19] = true, [20] = true, [21] = true, [24] = true,
	[25] = true, [27] = true, [31] = true, [32] = true
}

local function ensureItemsData()
	itemsData = itemsData or {}
	itemsData.customSalePrices = itemsData.customSalePrices or {}
	itemsData.primaryLootValueSources = itemsData.primaryLootValueSources or {}
	if modules.game_cyclopedia then
		modules.game_cyclopedia.itemsData = itemsData
	end
	return itemsData
end

local function safeCall(object, method, ...)
	if object and object[method] then
		local args = { ... }
		local ok, result = pcall(function() return object[method](object, unpack(args)) end)
		if ok then
			return result
		end
	end
	return nil
end

local function formatGold(value)
	value = tonumber(value) or 0
	return comma_value and comma_value(value) or tostring(value)
end

local function categoryName(categoryId)
	if categoryId == GOLD_CATEGORY then
		return 'Gold'
	elseif categoryId == UNSORTED_CATEGORY then
		return 'Unsorted'
	elseif categoryId == WEAPONS_ALL_CATEGORY then
		return 'Weapons: All'
	end
	return getMarketCategoryName and getMarketCategoryName(categoryId) or ('Category ' .. tostring(categoryId))
end

local function getItemType(itemId)
	if not itemId or not g_things then
		return nil
	end
	if g_things.getThingType then
		return g_things.getThingType(itemId, ThingCategoryItem)
	end
	return nil
end

local function createItem(itemId)
	if not itemId or not Item or not Item.create then
		return nil
	end
	return Item.create(itemId)
end

local function getItemName(itemId, item, thingType)
	local name = safeCall(item, 'getName') or safeCall(thingType, 'getName')
	if name and name ~= '' then
		return name
	end
	return 'Item ' .. tostring(itemId)
end

local function getMarketData(itemId, thingType)
	thingType = thingType or getItemType(itemId)
	local data = safeCall(thingType, 'getMarketData')
	if type(data) == 'table' then
		return data
	end
	return {}
end

local function bodyPositionName(slot)
	slot = tonumber(slot) or 0
	local names = {
		[InventorySlotHead or -1] = 'Head',
		[InventorySlotNeck or -1] = 'Neck',
		[InventorySlotBack or -1] = 'Back',
		[InventorySlotBody or -1] = 'Body',
		[InventorySlotRight or -1] = 'Right Hand',
		[InventorySlotLeft or -1] = 'Left Hand',
		[InventorySlotLeg or -1] = 'Legs',
		[InventorySlotFeet or -1] = 'Feet',
		[InventorySlotFinger or -1] = 'Finger',
		[InventorySlotAmmo or -1] = 'Ammo'
	}
	return names[slot]
end

local function makeEntry(itemId, name, category, displayId)
	itemId = tonumber(itemId)
	if not itemId then
		return nil
	end

	local thingType = getItemType(itemId)
	local marketData = getMarketData(itemId, thingType)
	local entry = {
		id = itemId,
		displayId = tonumber(displayId or marketData.showAs) or itemId,
		name = name or marketData.name,
		category = tonumber(category or marketData.category) or (MarketCategory and MarketCategory.Others or 9),
		marketData = marketData,
		thingType = thingType
	}

	if not entry.name or entry.name == '' then
		entry.name = getItemName(itemId, nil, thingType)
	end
	return entry
end

local function addEntry(entryById, entry)
	if not entry or entryById[entry.id] then
		return
	end
	entryById[entry.id] = entry
	table.insert(allItems, entry)
	marketItems[entry.category] = marketItems[entry.category] or {}
	table.insert(marketItems[entry.category], entry)
end

local function sortEntries(list)
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
end

local function rebuildItemCache()
	ensureItemsData()
	marketItems = {}
	allItems = {}
	local entryById = {}

	if g_things and g_things.findThingTypeByAttr then
		local types = g_things.findThingTypeByAttr(ThingAttrMarket, ThingCategoryItem)
		if types then
			for _, thingType in pairs(types) do
				local itemId = thingType:getId()
				local marketData = safeCall(thingType, 'getMarketData') or {}
				if type(marketData) == 'table' and not table.empty(marketData) then
					addEntry(entryById, makeEntry(itemId, marketData.name, marketData.category, marketData.showAs))
				end
			end
		end
	end

	local goldItems = {
		{ id = 3031, name = 'gold coin' },
		{ id = 3035, name = 'platinum coin' },
		{ id = 3043, name = 'crystal coin' }
	}
	for _, item in ipairs(goldItems) do
		addEntry(entryById, makeEntry(item.id, item.name, GOLD_CATEGORY, item.id))
	end

	for itemId, price in pairs(itemsData.customSalePrices) do
		if tonumber(price) and tonumber(price) > 0 then
			addEntry(entryById, makeEntry(itemId, nil, UNSORTED_CATEGORY, itemId))
		end
	end

	local customMarketItems = modules.game_cyclopedia and modules.game_cyclopedia.customMarketItems
	if type(customMarketItems) == 'table' then
		for _, entry in ipairs(customMarketItems) do
			addEntry(entryById, makeEntry(entry.id, entry.name, entry.category, entry.id))
		end
	end

	marketItems[WEAPONS_ALL_CATEGORY] = {}
	local weaponCategories = {
		MarketCategory and MarketCategory.Ammunition,
		MarketCategory and MarketCategory.Axes,
		MarketCategory and MarketCategory.Clubs,
		MarketCategory and MarketCategory.DistanceWeapons,
		MarketCategory and MarketCategory.Swords,
		MarketCategory and MarketCategory.WandsRods
	}
	for _, categoryId in ipairs(weaponCategories) do
		for _, entry in ipairs(marketItems[categoryId] or {}) do
			table.insert(marketItems[WEAPONS_ALL_CATEGORY], entry)
		end
	end

	sortEntries(allItems)
	for _, list in pairs(marketItems) do
		sortEntries(list)
	end
end

local function getCategoryList()
	local categories = {}
	for categoryId, entries in pairs(marketItems) do
		if #entries > 0 then
			table.insert(categories, { id = categoryId, name = categoryName(categoryId) })
		end
	end
	table.sort(categories, function(a, b)
		if a.id == MarketCategory.Armors then return true end
		if b.id == MarketCategory.Armors then return false end
		if a.id == WEAPONS_ALL_CATEGORY then return false end
		if b.id == WEAPONS_ALL_CATEGORY then return true end
		return a.name < b.name
	end)
	return categories
end

local function setButtonEnabled(widget, enabled)
	if not widget then
		return
	end
	widget:setEnabled(enabled)
	if not enabled and widget.setChecked then
		widget:setChecked(false)
	end
end

local function clearDetails()
	selectedEntry = nil
	selectedRow = nil
	if widgets.itemImage then widgets.itemImage:setItemId(0) end
	if widgets.emptyLabel then widgets.emptyLabel:show() end
	if widgets.panelitemshide then widgets.panelitemshide:hide() end
	if widgets.header then widgets.header:hide() end
	if widgets.circlenpc then widgets.circlenpc:hide() end
	if widgets.circlemarket then widgets.circlemarket:hide() end
end

local function getEntryItem(entry)
	if not entry then
		return nil
	end
	if not entry.item then
		entry.item = createItem(entry.id)
	end
	return entry.item
end

local function getDefaultValue(entry)
	local item = getEntryItem(entry)
	local value = safeCall(item, 'getDefaultValue')
	if tonumber(value) then return tonumber(value) end
	value = safeCall(item, 'getMeanPrice')
	return tonumber(value) or 0
end

local function getMarketValue(entry)
	local item = getEntryItem(entry)
	local value = safeCall(item, 'getAverageMarketValue')
	if tonumber(value) then return tonumber(value) end
	value = safeCall(item, 'getMeanPrice')
	return tonumber(value) or 0
end

local function getResultingValue(entry)
	if not entry then
		return 0
	end
	local item = getEntryItem(entry)
	return ItemsDatabase and ItemsDatabase.getLootValue and ItemsDatabase.getLootValue(item or entry.id) or 0
end

local function refreshLootValueUsers()
	if saveItemsPriceData then
		saveItemsPriceData()
	end
	if modules.game_containers and modules.game_containers.reloadContainers then
		scheduleEvent(function()
			modules.game_containers.reloadContainers()
		end, 50)
	end
end

local function setColorPreview(value)
	if not widgets.itemColor then
		return
	end
	value = tonumber(value) or 0
	if value <= 0 then
		widgets.itemColor:setImageSource('')
	elseif value >= 1000000 then
		widgets.itemColor:setImageSource('/game_cyclopedia/images/ui/itemcolor/item-gold')
	elseif value >= 100000 then
		widgets.itemColor:setImageSource('/game_cyclopedia/images/ui/itemcolor/item-purple')
	elseif value >= 10000 then
		widgets.itemColor:setImageSource('/game_cyclopedia/images/ui/itemcolor/item-blue')
	elseif value >= 1000 then
		widgets.itemColor:setImageSource('/game_cyclopedia/images/ui/itemcolor/item-green')
	else
		widgets.itemColor:setImageSource('/game_cyclopedia/images/ui/itemcolor/item-gray')
	end
end

local function addSaleRow(parent, text, location, isBuy)
	if not parent then
		return
	end
	local widget = g_ui.createWidget('SaleList', parent)
	local baseColor = parent:getChildCount() % 2 == 0 and '#484848' or '#414141'
	widget.valueLabel:setText(text)
	widget.locationLabel:setText(location or '')
	widget:setBackgroundColor(baseColor)
	widget.baseColor = baseColor
	widget.onClick = function()
		local previous = isBuy and selectedBuyRow or selectedSellRow
		if previous then
			previous:setBackgroundColor(previous.baseColor or '#414141')
			previous.valueLabel:setColor('#c0c0c0')
			previous.locationLabel:setColor('#c0c0c0')
		end
		widget:setBackgroundColor('#585858')
		widget.valueLabel:setColor('#f4f4f4')
		widget.locationLabel:setColor('#f4f4f4')
		if isBuy then
			selectedBuyRow = widget
		else
			selectedSellRow = widget
		end
	end
	if parent:getChildCount() == 1 then
		widget:onClick()
	end
end

local function refreshNpcLists(entry)
	if widgets.sellToList then widgets.sellToList:destroyChildren() end
	if widgets.buyFromList then widgets.buyFromList:destroyChildren() end
	selectedBuyRow = nil
	selectedSellRow = nil

	local item = getEntryItem(entry)
	local data = safeCall(item, 'getNpcSaleData')
	if type(data) ~= 'table' then
		return
	end

	local rashidFound = false
	local yasirFound = false
	for _, npcData in pairs(data) do
		local buyPrice = tonumber(npcData.buyPrice) or 0
		local salePrice = tonumber(npcData.salePrice) or 0
		local npc = npcData.name or ''
		local location = npcData.location or ''
		if npc == 'Rashid' then
			if rashidFound then goto continue end
			rashidFound = true
			location = 'Various Locations'
		elseif npc == 'Yasir' then
			if yasirFound then goto continue end
			yasirFound = true
			location = 'Various Locations'
		end
		if buyPrice > 0 then
			addSaleRow(widgets.sellToList, formatGold(buyPrice) .. ' gp, ' .. npc, 'Residence: ' .. location, true)
		end
		if salePrice > 0 then
			addSaleRow(widgets.buyFromList, formatGold(salePrice) .. ' gp, ' .. npc, 'Residence: ' .. location, false)
		end
		::continue::
	end
end

local function refreshBasicDetails(entry)
	if widgets.basicDetails then
		widgets.basicDetails:destroyChildren()
	end
	if not widgets.basicDetails or not entry then
		return
	end

	local item = getEntryItem(entry)
	local description = safeCall(item, 'getDescription') or safeCall(entry.thingType, 'getDescription')
	local rows = {}
	local customDetails = modules.game_cyclopedia and modules.game_cyclopedia.customItemDetails and modules.game_cyclopedia.customItemDetails[entry.id]
	local hasCustomDetails = false
	if type(customDetails) == 'table' then
		for detailId, detailValue in pairs(customDetails) do
			if detailValue and detailValue ~= '' then
				local detailName = getMarketDescriptionName and getMarketDescriptionName(detailId) or nil
				table.insert(rows, { detailName or ('Detail ' .. tostring(detailId)), detailValue, tonumber(detailId) or 999 })
				hasCustomDetails = true
			end
		end
		table.sort(rows, function(a, b)
			return (a[3] or 999) < (b[3] or 999)
		end)
	end
	local marketData = entry.marketData or {}
	local classification = safeCall(entry.thingType, 'getClassification') or safeCall(item, 'getClassification')
	local bodyPosition = bodyPositionName(safeCall(item, 'getClothSlot'))

	if not hasCustomDetails and tonumber(marketData.armor) and tonumber(marketData.armor) > 0 then
		table.insert(rows, { 'Armor', tostring(marketData.armor) })
	end
	if not hasCustomDetails and tonumber(marketData.attack) and tonumber(marketData.attack) > 0 then
		table.insert(rows, { 'Attack', tostring(marketData.attack) })
	end
	if not hasCustomDetails and tonumber(marketData.defense) and tonumber(marketData.defense) > 0 then
		table.insert(rows, { 'Defense', tostring(marketData.defense) })
	end
	if not hasCustomDetails and tonumber(marketData.imbuingSlots) and tonumber(marketData.imbuingSlots) > 0 then
		table.insert(rows, { 'Imbuements', tostring(marketData.imbuingSlots) })
	end
	local weight = safeCall(item, 'getWeight')
	if not hasCustomDetails and tonumber(weight) and tonumber(weight) > 0 then
		table.insert(rows, { 'Weight', string.format('%.2f oz', tonumber(weight) / 100) })
	end
	if not hasCustomDetails and bodyPosition then
		table.insert(rows, { 'Body Position', bodyPosition })
	end
	if not hasCustomDetails and tonumber(classification) and tonumber(classification) > 0 then
		table.insert(rows, { 'Classification', tostring(classification) })
	end
	if #rows == 0 and description and description ~= '' then
		table.insert(rows, { 'Description', description })
	end
	if #rows == 0 then
		table.insert(rows, { '', 'No basic details available.' })
	end

	for _, row in ipairs(rows) do
		local widget = g_ui.createWidget('InspectLabel', widgets.basicDetails)
		widget.label:setText(row[1] ~= '' and (row[1] .. ':') or '')
		widget.content:setText(row[2] or '')
	end
end

local function updateQuickControls(entry)
	if not entry then
		return
	end
	local quickLoot = modules.game_quickloot and modules.game_quickloot.QuickLoot or QuickLoot
	local hasQuickLoot = quickLoot and quickLoot.lootExists and quickLoot.addLootList and quickLoot.removeLootList
		and quickLoot.data and type(quickLoot.data.loots) == 'table'
		and type(quickLoot.data.loots[1]) == 'table' and type(quickLoot.data.loots[2]) == 'table'
	local skipped = false
	local accepted = false
	if hasQuickLoot then
		local okSkipped, resultSkipped = pcall(function() return quickLoot.lootExists(entry.id, 1) end)
		local okAccepted, resultAccepted = pcall(function() return quickLoot.lootExists(entry.id, 2) end)
		skipped = okSkipped and resultSkipped or false
		accepted = okAccepted and resultAccepted or false
	end
	if widgets.checkLootbox then
		widgets.checkLootbox:setEnabled(hasQuickLoot and true or false)
		widgets.checkLootbox:setChecked(skipped)
	end
	if widgets.quickListbox then
		widgets.quickListbox:setEnabled(hasQuickLoot and true or false)
		widgets.quickListbox:setChecked(accepted)
	end
end

local function updateDropTrackerControl(entry)
	if not widgets.trackDrops or not entry then
		return
	end
	local analyser = modules.game_analyser
	local enabled = analyser and analyser.isInDropTracker and analyser.managerDropTracker
	widgets.trackDrops:setEnabled(enabled and true or false)
	widgets.trackDrops:setChecked(enabled and analyser.isInDropTracker(entry.id) or false)
end

local function showItem(entry, row)
	if not entry then
		clearDetails()
		return
	end

	if selectedRow then
		selectedRow:setBackgroundColor('#404040')
	end
	selectedRow = row
	if selectedRow then
		selectedRow:setBackgroundColor('#585858')
	end

	selectedEntry = entry
	if widgets.emptyLabel then widgets.emptyLabel:hide() end
	if widgets.panelitemshide then widgets.panelitemshide:show() end
	if widgets.header then widgets.header:show() end
	if widgets.circlenpc then widgets.circlenpc:show() end
	if widgets.circlemarket then widgets.circlemarket:show() end
	if widgets.itemImage then widgets.itemImage:setItemId(entry.displayId or entry.id) end

	refreshBasicDetails(entry)
	refreshNpcLists(entry)
	updateQuickControls(entry)
	updateDropTrackerControl(entry)

	local avgMarket = getMarketValue(entry)
	local resulting = getResultingValue(entry)
	local custom = itemsData.customSalePrices[tostring(entry.id)] or itemsData.customSalePrices[entry.id]
	local useMarket = itemsData.primaryLootValueSources[tostring(entry.id)] == true

	if widgets.averageMarketPrice then widgets.averageMarketPrice:setText(formatGold(avgMarket)) end
	if widgets.resultingValue then widgets.resultingValue:setText(formatGold(resulting)) end
	setColorPreview(resulting)

	internalChange = true
	if widgets.customPrice then widgets.customPrice:setText(custom and tostring(custom) or '') end
	if widgets.circlenpc then widgets.circlenpc:setChecked(not useMarket) end
	if widgets.circlemarket then widgets.circlemarket:setChecked(useMarket) end
	internalChange = false
end

local function addItemRow(entry)
	local row = g_ui.createWidget('ItemListLabel', widgets.itemList)
	row.entry = entry
	row.item:setItemId(entry.displayId or entry.id)
	row.name:setText(entry.name)
	if #entry.name >= 20 and row.name.setTextWrap then
		row.name:setTextWrap(true)
	end
	if modules.game_analyser and modules.game_analyser.isInDropTracker and modules.game_analyser.isInDropTracker(entry.id) then
		row.name:setColor('#FF9854')
	end
	row:setBackgroundColor('#404040')
	row.onClick = function()
		showItem(entry, row)
	end
	return row
end

local function renderItemList(entries)
	if not widgets.itemList then
		return
	end
	widgets.itemList:destroyChildren()
	selectedRow = nil

	for _, entry in ipairs(entries) do
		addItemRow(entry)
	end

	widgets.itemList.onChildFocusChange = function(_, selected)
		if selected and selected.entry then
			showItem(selected.entry, selected)
		end
	end

	local firstChild = widgets.itemList:getFirstChild()
	if firstChild then
		widgets.itemList:focusChild(firstChild)
		showItem(firstChild.entry, firstChild)
	else
		clearDetails()
	end
end

local function applyCategoryFilters()
	local entries = marketItems[selectedCategoryId] or {}
	renderItemList(entries)
	setButtonEnabled(widgets.oneHandButton, enableCategories[selectedCategoryId] == true)
	setButtonEnabled(widgets.twoHandButton, enableCategories[selectedCategoryId] == true)
	if widgets.classOptions then
		widgets.classOptions:clearOptions()
		if enableClassification[selectedCategoryId] then
			widgets.classOptions:addOption('All')
			widgets.classOptions:addOption('None')
			widgets.classOptions:addOption('Class 1')
			widgets.classOptions:addOption('Class 2')
			widgets.classOptions:addOption('Class 3')
			widgets.classOptions:addOption('Class 4')
		end
	end
end

local function selectCategory(row)
	if not row or not row.categoryId then
		return
	end
	if widgets.searchText and widgets.searchText:getText() ~= '' then
		internalChange = true
		widgets.searchText:clearText()
		internalChange = false
	end
	for _, child in ipairs(widgets.categoriesList:getChildren()) do
		child:setBackgroundColor(child.baseColor or '#414141')
		child:setColor('#c0c0c0')
	end
	row:setBackgroundColor('#585858')
	row:setColor('#f4f4f4')
	selectedCategoryId = row.categoryId
	applyCategoryFilters()
end

local function showCategories()
	if not widgets.categoriesList then
		return
	end
	widgets.categoriesList:destroyChildren()
	widgets.categoriesList.onChildFocusChange = function(_, selected)
		selectCategory(selected)
	end
	local categories = getCategoryList()
	local firstRow
	for index, category in ipairs(categories) do
		local row = g_ui.createWidget('CategoryItemListLabel', widgets.categoriesList)
		row.categoryId = category.id
		row:setId(category.name)
		row:setText(category.name)
		row.baseColor = index % 2 == 0 and '#414141' or '#484848'
		row:setBackgroundColor(row.baseColor)
		row.onClick = function() selectCategory(row) end
		if category.id == (MarketCategory and MarketCategory.Armors or 1) then
			firstRow = row
		end
		firstRow = firstRow or row
	end
	if firstRow then
		widgets.categoriesList:focusChild(firstRow)
		selectCategory(firstRow)
	end
end

function CyclopediaItems.onSearch(widget)
	if internalChange or not widget then
		return
	end
	local query = widget:getText():lower()
	if query == '' then
		applyCategoryFilters()
		return
	end

	local entries = {}
	local numeric = tonumber(query)
	for _, entry in ipairs(allItems) do
		local matches = numeric and entry.id == numeric or entry.name:lower():find(query, 1, true) or tostring(entry.id):find(query, 1, true)
		if matches then
			table.insert(entries, entry)
			if #entries >= SEARCH_LIMIT then
				break
			end
		end
	end
	renderItemList(entries)
end

function CyclopediaItems.clearSearch(widget)
	local input = widget
	if widget and widget.getParent then
		input = widget:getParent()
	end
	if input and input.clearText then
		input:clearText()
	end
	applyCategoryFilters()
end

function CyclopediaItems.onSourceValueChange(_, useNpcValue)
	if not selectedEntry or internalChange then
		return
	end
	ensureItemsData()
	itemsData.primaryLootValueSources[tostring(selectedEntry.id)] = useNpcValue and nil or true
	refreshLootValueUsers()
	showItem(selectedEntry, selectedRow)
end

function CyclopediaItems.onChangeCustomPrice(widget)
	if internalChange or not selectedEntry or not widget then
		return
	end
	ensureItemsData()
	local text = widget:getText() or ''
	local price = tonumber(text:gsub('[,%s]', ''))
	if price and price > 0 then
		itemsData.customSalePrices[tostring(selectedEntry.id)] = math.floor(price)
	else
		itemsData.customSalePrices[tostring(selectedEntry.id)] = nil
	end
	refreshLootValueUsers()
	showItem(selectedEntry, selectedRow)
end

function CyclopediaItems.updateDropTracker(widget, checked)
	if not selectedEntry or not modules.game_analyser or not modules.game_analyser.managerDropTracker then
		if widget then widget:setChecked(false) end
		return
	end
	modules.game_analyser.managerDropTracker(selectedEntry.id, checked)
	if selectedRow and selectedRow.name then
		selectedRow.name:setColor(checked and '#FF9854' or '#c0c0c0')
	end
end

function CyclopediaItems.manageQuickloot(widget, checked)
	if not selectedEntry then
		return
	end
	local quickLoot = modules.game_quickloot and modules.game_quickloot.QuickLoot or QuickLoot
	if not quickLoot or not quickLoot.addLootList or not quickLoot.removeLootList
		or not quickLoot.data or type(quickLoot.data.loots) ~= 'table' or type(quickLoot.data.loots[1]) ~= 'table' then
		if widget then widget:setChecked(false) end
		return
	end
	if checked then
		pcall(function() quickLoot.addLootList(selectedEntry.id, 1) end)
	else
		pcall(function() quickLoot.removeLootList(selectedEntry.id, 1) end)
	end
end

function CyclopediaItems.manageQuickSellWhitelist(widget, checked)
	if not selectedEntry then
		return
	end
	local quickLoot = modules.game_quickloot and modules.game_quickloot.QuickLoot or QuickLoot
	if not quickLoot or not quickLoot.addLootList or not quickLoot.removeLootList
		or not quickLoot.data or type(quickLoot.data.loots) ~= 'table' or type(quickLoot.data.loots[2]) ~= 'table' then
		if widget then widget:setChecked(false) end
		return
	end
	if checked then
		pcall(function() quickLoot.addLootList(selectedEntry.id, 2) end)
	else
		pcall(function() quickLoot.removeLootList(selectedEntry.id, 2) end)
	end
end

function refreshItemsCyclopedia()
	if not itemsPanel or (modules.game_cyclopedia and modules.game_cyclopedia.getCurrentType and modules.game_cyclopedia.getCurrentType() ~= 'items') then
		return
	end
	rebuildItemCache()
	showCategories()
end

function CyclopediaItems.refreshSelectedItemDetails(itemId)
	if selectedEntry and selectedEntry.id == itemId then
		refreshBasicDetails(selectedEntry)
	end
end

function onCyclopediaMarketEnter(_, _, _, _, customItems)
	if type(customItems) ~= 'table' or not modules.game_cyclopedia then
		return
	end
	modules.game_cyclopedia.customMarketItems = customItems
	if CyclopediaItems.refreshItems then
		CyclopediaItems.refreshItems()
	end
end

function initItems(contentContainer)
	ensureItemsData()
	itemsPanel = g_ui.loadUI('styles/items', contentContainer)
	itemsPanel:show()

	modules.game_cyclopedia.CyclopediaItems = CyclopediaItems
	CyclopediaItems.refreshItems = refreshItemsCyclopedia

	widgets.categoriesList = itemsPanel:recursiveGetChildById('categoriesList')
	widgets.itemList = itemsPanel:recursiveGetChildById('itemList')
	widgets.searchText = itemsPanel:recursiveGetChildById('searchText')
	widgets.itemImage = itemsPanel:recursiveGetChildById('itemImage')
	widgets.panelitemshide = itemsPanel:recursiveGetChildById('panelitemshide')
	widgets.emptyLabel = itemsPanel:recursiveGetChildById('emptyLabel')
	widgets.basicDetails = itemsPanel:recursiveGetChildById('basicDetails')
	widgets.sellToList = itemsPanel:recursiveGetChildById('sellToList')
	widgets.buyFromList = itemsPanel:recursiveGetChildById('buyFromList')
	widgets.averageMarketPrice = itemsPanel:recursiveGetChildById('averageMarketPrice')
	widgets.customPrice = itemsPanel:recursiveGetChildById('customPrice')
	widgets.resultingValue = itemsPanel:recursiveGetChildById('resultingValue')
	widgets.itemColor = itemsPanel:recursiveGetChildById('itemColor')
	widgets.header = itemsPanel:recursiveGetChildById('header')
	widgets.circlenpc = itemsPanel:recursiveGetChildById('circlenpc')
	widgets.circlemarket = itemsPanel:recursiveGetChildById('circlemarket')
	widgets.trackDrops = itemsPanel:recursiveGetChildById('checkbox-track-drops')
	widgets.checkLootbox = itemsPanel:recursiveGetChildById('checkLootbox')
	widgets.quickListbox = itemsPanel:recursiveGetChildById('quickListbox')
	widgets.oneHandButton = itemsPanel:recursiveGetChildById('oneHandButton')
	widgets.twoHandButton = itemsPanel:recursiveGetChildById('twoHandButton')
	widgets.classOptions = itemsPanel:recursiveGetChildById('classOptions')

	if widgets.searchText then
		widgets.searchText.onTextChange = CyclopediaItems.onSearch
	end
	if widgets.customPrice then
		widgets.customPrice.onTextChange = CyclopediaItems.onChangeCustomPrice
	end

	rebuildItemCache()
	showCategories()
end
