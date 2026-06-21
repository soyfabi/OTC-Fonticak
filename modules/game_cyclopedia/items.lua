CyclopediaItems = CyclopediaItems or {}
Cyclopedia = Cyclopedia or {}
modules.game_cyclopedia = modules.game_cyclopedia or {}

local OPCODE_ITEM_DETAILS = 0xC7
local GOLD_CATEGORY = 30
local UNSORTED_CATEGORY = 31
local WEAPONS_ALL_CATEGORY = 106

local panel
local marketItems = {}
local currentCategory
local currentItem
local currentDescriptions = {}
local pendingItemDetails = {}
local updatingPriceFields = false

local itemsData = modules.game_cyclopedia.itemsData or {
  primaryLootValueSources = {},
  customSalePrices = {},
  serverValues = {},
  serverBuyPrices = {},
  serverAverageMarketPrices = {},
  serverNpcSaleData = {},
  serverDetails = {}
}

itemsData.primaryLootValueSources = itemsData.primaryLootValueSources or {}
itemsData.customSalePrices = itemsData.customSalePrices or {}
itemsData.serverValues = itemsData.serverValues or {}
itemsData.serverBuyPrices = itemsData.serverBuyPrices or {}
itemsData.serverAverageMarketPrices = itemsData.serverAverageMarketPrices or {}
itemsData.serverNpcSaleData = itemsData.serverNpcSaleData or {}
itemsData.serverDetails = itemsData.serverDetails or {}

modules.game_cyclopedia.CyclopediaItems = CyclopediaItems
modules.game_cyclopedia.itemsData = itemsData
Cyclopedia.Items = CyclopediaItems

local function call(object, method, ...)
  if object and object[method] then
    return object[method](object, ...)
  end
  return nil
end

local function getItemId(item)
  if type(item) == 'number' then
    return item
  end
  return call(item, 'getId') or call(item, 'getServerId') or 0
end

local function makeItem(itemId)
  if itemId and Item and Item.create then
    return Item.create(itemId)
  end
  return nil
end

local function asNumber(value)
  value = tonumber(value)
  return value and math.max(0, math.floor(value)) or 0
end

local function formatGold(value)
  value = asNumber(value)
  if value <= 0 then
    return '0'
  end
  local formatted = tostring(value)
  while true do
    local nextValue, replacements = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
    formatted = nextValue
    if replacements == 0 then
      break
    end
  end
  return formatted
end

local function getThingType(item)
  if not item then
    return nil
  end
  return item.thingType or call(item, 'getThingType')
end

local function getMarketData(item)
  local thingType = getThingType(item)
  if thingType and thingType.getMarketData then
    return thingType:getMarketData()
  end
  return nil
end

local function getItemName(item)
  local itemId = getItemId(item)
  if getItemServerName then
    local ok, name = pcall(getItemServerName, itemId)
    if ok and name and name ~= '' then
      return name
    end
  end

  local marketData = getMarketData(item)
  if marketData and marketData.name and marketData.name ~= '' then
    return marketData.name
  end

  local name = call(item, 'getName')
  if name and name ~= '' then
    return name
  end

  local created = makeItem(itemId)
  name = call(created, 'getName')
  if name and name ~= '' then
    return name
  end

  return 'Item ' .. tostring(itemId)
end

local function getCategoryName(category)
  if getObjectCategoryName then
    local ok, name = pcall(getObjectCategoryName, category)
    if ok and name and name ~= '' then
      return name
    end
  end
  if category == GOLD_CATEGORY then
    return tr('Gold')
  elseif category == UNSORTED_CATEGORY then
    return tr('Unsorted')
  elseif category == WEAPONS_ALL_CATEGORY then
    return tr('Weapons: All')
  elseif getMarketCategoryName then
    local ok, name = pcall(getMarketCategoryName, category)
    if ok and name and name ~= '' then
      return name
    end
  end
  return tostring(category)
end

local function getNpcSaleData(item)
  local itemId = getItemId(item)
  local serverData = itemsData.serverNpcSaleData[tostring(itemId)] or itemsData.serverNpcSaleData[itemId]
  if type(serverData) == 'table' and #serverData > 0 then
    return serverData
  end
  local data = call(item, 'getNpcSaleData') or call(item, 'getNPCSaleData')
  return data or {}
end

local function getNpcValue(item)
  local best = 0
  for _, entry in pairs(getNpcSaleData(item)) do
    best = math.max(best, asNumber(entry.buyPrice or entry.buy or entry.sellPrice or entry.price))
  end
  return best
end

local function getMeanPrice(item)
  local itemId = getItemId(item)
  local serverAverage = asNumber(itemsData.serverAverageMarketPrices[tostring(itemId)] or itemsData.serverAverageMarketPrices[itemId])
  if serverAverage > 0 then
    return serverAverage
  end
  local value = asNumber(call(item, 'getMeanPrice'))
  if value > 0 then
    return value
  end
  return asNumber(call(item, 'getAverageMarketValue'))
end

local function getDatabaseValue(item)
  if ItemsDatabase and ItemsDatabase.getItemValue then
    return asNumber(ItemsDatabase.getItemValue(item))
  end
  return 0
end

local function getDefaultValue(item)
  local itemId = getItemId(item)
  local serverValue = asNumber(itemsData.serverValues[tostring(itemId)] or itemsData.serverValues[itemId])
  if serverValue > 0 then return serverValue end
  local defaultValue = asNumber(call(item, 'getDefaultValue'))
  if defaultValue > 0 then return defaultValue end
  local value = getNpcValue(item)
  if value > 0 then return value end
  value = getDatabaseValue(item)
  if value > 0 then return value end
  return getMeanPrice(item)
end

local function getCurrentItemValue(item)
  local itemId = tostring(getItemId(item))
  local custom = asNumber(itemsData.customSalePrices[itemId])
  if custom > 0 then
    return custom
  end
  if itemsData.primaryLootValueSources[itemId] then
    local market = getMeanPrice(item)
    if market > 0 then
      return market
    end
  end
  return getDefaultValue(item)
end

local function getItemPriceColor(value)
  value = asNumber(value)
  if value >= 1000000 then return 'item-purple' end
  if value >= 100000 then return 'item-blue' end
  if value >= 10000 then return 'item-green' end
  if value > 0 then return 'item-gold' end
  return 'item-gray'
end

local function getMarketRange()
  local first = MarketCategory and MarketCategory.First or 1
  local last = MarketCategory and MarketCategory.Last or 22
  return first, last
end

local function sortItems(items)
  table.sort(items, function(a, b)
    return getItemName(a):lower() < getItemName(b):lower()
  end)
end

local function addItem(category, item)
  if not item then
    return
  end
  marketItems[category] = marketItems[category] or {}
  table.insert(marketItems[category], item)
end

local function createMarketItem(thingType)
  if not thingType then
    return nil
  end
  local itemId = thingType:getId()
  local item = makeItem(itemId)
  if not item then
    return nil
  end
  item.thingType = thingType
  item.realItemId = itemId
  local marketData = thingType:getMarketData()
  if marketData and marketData.showAs and marketData.showAs > 0 and marketData.showAs ~= itemId then
    item.displayItem = makeItem(marketData.showAs)
  end
  return item
end

local function resolveRealItem(item)
  if item and item.realItemId then
    local realItem = makeItem(item.realItemId)
    if realItem then
      realItem.thingType = item.thingType
      return realItem
    end
  end
  return item
end

local function setItemWidget(widget, item)
  if not widget or not item then
    return
  end
  local displayItem = item.displayItem or item
  if widget.setItem then
    widget:setItem(displayItem)
  elseif widget.setItemId then
    widget:setItemId(getItemId(displayItem))
  end
  if ItemsDatabase and ItemsDatabase.setRarityItem then
    ItemsDatabase.setRarityItem(widget, resolveRealItem(item))
  end
end

local function normalizeDescriptions(descriptions)
  local result = {}
  if type(descriptions) == 'table' then
    for _, entry in ipairs(descriptions) do
      if type(entry) == 'table' then
        table.insert(result, {
          detail = entry.detail or entry[1] or '',
          description = entry.description or entry[2] or ''
        })
      end
    end
  end
  return result
end

local function getFallbackDescriptions(item)
  local itemId = getItemId(item)
  local cached = itemsData.serverDetails[tostring(itemId)] or itemsData.serverDetails[itemId]
  if cached then
    local descriptions = normalizeDescriptions(cached.descriptions or cached)
    if #descriptions > 0 then
      return descriptions
    end
  end

  if ItemsDatabase and ItemsDatabase.getServerItemDetails then
    local details = ItemsDatabase.getServerItemDetails(itemId)
    if details then
      local descriptions = normalizeDescriptions(details.descriptions or details)
      if #descriptions > 0 then
        return descriptions
      end
    end
  end

  return {
    { detail = tr('Name'), description = getItemName(item) },
    { detail = tr('Description'), description = call(item, 'getDescription') or tr('No server details available.') }
  }
end

local function getCachedServerDescriptions(item)
  local itemId = getItemId(item)
  local cached = itemsData.serverDetails[tostring(itemId)] or itemsData.serverDetails[itemId]
  if cached then
    local descriptions = normalizeDescriptions(cached.descriptions or cached)
    if #descriptions > 0 then
      return descriptions
    end
  end

  if ItemsDatabase and ItemsDatabase.getServerItemDetails then
    local details = ItemsDatabase.getServerItemDetails(itemId)
    if details then
      local descriptions = normalizeDescriptions(details.descriptions or details)
      if #descriptions > 0 then
        return descriptions
      end
    end
  end

  return nil
end

local function saveData()
  modules.game_cyclopedia.itemsData = itemsData
  if not LoadedPlayer or not LoadedPlayer.isLoaded or not LoadedPlayer:isLoaded() then
    return
  end
  local playerId = LoadedPlayer:getId()
  local dir = '/characterdata/' .. playerId
  if g_resources and g_resources.makeDir then
    g_resources.makeDir(dir)
  end
  if json and g_resources and g_resources.writeFileContents then
    local ok, encoded = pcall(json.encode, itemsData)
    if ok then
      g_resources.writeFileContents(dir .. '/itemprices.json', encoded)
    end
  end
end

local function loadData()
  if not LoadedPlayer or not LoadedPlayer.isLoaded or not LoadedPlayer:isLoaded() then
    return
  end
  local file = '/characterdata/' .. LoadedPlayer:getId() .. '/itemprices.json'
  if g_resources and g_resources.fileExists and g_resources.fileExists(file) and json then
    local ok, decoded = pcall(json.decode, g_resources.readFileContents(file))
    if ok and type(decoded) == 'table' then
      itemsData = decoded
    end
  end
  itemsData.primaryLootValueSources = itemsData.primaryLootValueSources or {}
  itemsData.customSalePrices = itemsData.customSalePrices or {}
  itemsData.serverValues = itemsData.serverValues or {}
  itemsData.serverBuyPrices = itemsData.serverBuyPrices or {}
  itemsData.serverAverageMarketPrices = itemsData.serverAverageMarketPrices or {}
  itemsData.serverNpcSaleData = itemsData.serverNpcSaleData or {}
  itemsData.serverDetails = itemsData.serverDetails or {}
  modules.game_cyclopedia.itemsData = itemsData
  if ItemsDatabase then
    ItemsDatabase.serverValues = ItemsDatabase.serverValues or itemsData.serverValues
    ItemsDatabase.serverDetails = ItemsDatabase.serverDetails or itemsData.serverDetails
  end
end

function CyclopediaItems.loadItems()
  marketItems = {}
  local first, last = getMarketRange()
  for category = first, last do
    marketItems[category] = {}
  end
  marketItems[GOLD_CATEGORY] = {}
  marketItems[UNSORTED_CATEGORY] = {}
  marketItems[WEAPONS_ALL_CATEGORY] = {}

  if g_things and g_things.findThingTypeByAttr and ThingAttrMarket and ThingCategoryItem then
    local thingTypes = g_things.findThingTypeByAttr(ThingAttrMarket, ThingCategoryItem) or {}
    for _, thingType in pairs(thingTypes) do
      local marketData = thingType:getMarketData()
      if marketData and marketData.name and marketData.category then
        local item = createMarketItem(thingType)
        addItem(marketData.category, item)
      end
    end
  end

  for _, id in ipairs({3031, 3035, 3043}) do
    addItem(GOLD_CATEGORY, makeItem(id))
  end

  if g_game and g_game.getUnsortedCyclopediaItems then
    for _, id in pairs(g_game.getUnsortedCyclopediaItems() or {}) do
      addItem(UNSORTED_CATEGORY, makeItem(id))
    end
  end

  local weaponCategories = {
    MarketCategory and MarketCategory.Ammunition,
    MarketCategory and MarketCategory.Axes,
    MarketCategory and MarketCategory.Clubs,
    MarketCategory and MarketCategory.DistanceWeapons,
    MarketCategory and MarketCategory.Swords,
    MarketCategory and MarketCategory.WandsRods,
    MarketCategory and MarketCategory.FistWeapons
  }
  for _, category in ipairs(weaponCategories) do
    for _, item in ipairs(marketItems[category] or {}) do
      addItem(WEAPONS_ALL_CATEGORY, item)
    end
  end

  for _, items in pairs(marketItems) do
    sortItems(items)
  end
end

local function getPanel()
  return panel
end

local function getQuickLoot()
  if modules.game_quickloot and modules.game_quickloot.QuickLoot then
    return modules.game_quickloot.QuickLoot
  end
  return QuickLoot
end

local function getQuickLootFilter()
  local quickLoot = getQuickLoot()
  return quickLoot and quickLoot.data and quickLoot.data.filter or nil
end

function CyclopediaItems.showItemDescription(descriptions)
  currentDescriptions = normalizeDescriptions(descriptions)
  if #currentDescriptions == 0 and currentItem then
    currentDescriptions = getFallbackDescriptions(currentItem)
  end

  local list = panel and panel:recursiveGetChildById('basicDetails')
  if not list then
    return
  end
  list:destroyChildren()
  for _, entry in ipairs(currentDescriptions) do
    local widget = g_ui.createWidget('InspectLabel', list)
    if widget.label then
      widget.label:setText((entry.detail or '') .. ':')
    end
    if widget.content then
      widget.content:setText(entry.description or '')
    end
    if widget.content and widget.content.isTextWraped and widget.content:isTextWraped() then
      local wrappedLines = widget.content:getWrappedLinesCount()
      if wrappedLines == 1 then
        widget:setSize(tosize('270 ' .. 19 * (wrappedLines + 1)))
      else
        widget:setSize(tosize('270 ' .. 21 * wrappedLines))
      end
    end
  end
end

function CyclopediaItems.showNpcData(item)
  local sellToList = panel:recursiveGetChildById('sellToList')
  local buyFromList = panel:recursiveGetChildById('buyFromList')
  if sellToList then sellToList:destroyChildren() end
  if buyFromList then buyFromList:destroyChildren() end

  for _, entry in pairs(getNpcSaleData(item)) do
    if sellToList and asNumber(entry.buyPrice or entry.buy or entry.sellPrice or entry.price) > 0 then
      local widget = g_ui.createWidget('SaleList', sellToList)
      widget.valueLabel:setText(formatGold(entry.buyPrice or entry.buy or entry.sellPrice or entry.price) .. ' gp')
      widget.locationLabel:setText((entry.name or 'NPC') .. ', ' .. (entry.location or tr('Unknown Location')))
    end
    if buyFromList and asNumber(entry.salePrice or entry.sellPriceNpc or entry.sellPrice) > 0 then
      local widget = g_ui.createWidget('SaleList', buyFromList)
      widget.valueLabel:setText(formatGold(entry.salePrice or entry.sellPriceNpc or entry.sellPrice) .. ' gp')
      widget.locationLabel:setText((entry.name or 'NPC') .. ', ' .. (entry.location or tr('Unknown Location')))
    end
  end
end

function CyclopediaItems.showItemPrice(item)
  local marketValue = getMeanPrice(item)
  local npcValue = getDefaultValue(item)
  local customValue = asNumber(itemsData.customSalePrices[tostring(getItemId(item))])
  local resultingValue = getCurrentItemValue(item)
  local colorName = getItemPriceColor(resultingValue)

  local average = panel:recursiveGetChildById('averageMarketPrice')
  local custom = panel:recursiveGetChildById('customPrice')
  local resulting = panel:recursiveGetChildById('resultingValue')
  local itemColor = panel:recursiveGetChildById('itemColor')
  local header = panel:recursiveGetChildById('header')
  local npcSource = panel:recursiveGetChildById('circlenpc')
  local marketSource = panel:recursiveGetChildById('circlemarket')
  local hasValueSource = npcValue > 0 or marketValue > 0

  updatingPriceFields = true
  if average then average:setText(formatGold(marketValue)) end
  if custom then custom:setText(customValue > 0 and tostring(customValue) or '') end
  if resulting then resulting:setText(formatGold(resultingValue)) end
  if itemColor then itemColor:setImageSource('/game_cyclopedia/images/ui/itemcolor/' .. colorName) end
  if header then header:setVisible(hasValueSource) end
  if npcSource then npcSource:setVisible(hasValueSource and npcValue > 0) end
  if marketSource then marketSource:setVisible(hasValueSource and marketValue > 0) end
  updatingPriceFields = false
end

function CyclopediaItems.requestServerItemData(item)
  if not g_game then
    CyclopediaItems.showItemDescription(getFallbackDescriptions(item))
    return
  end

  local realItem = resolveRealItem(item)
  local itemId = getItemId(realItem)
  if itemId <= 0 then
    CyclopediaItems.showItemDescription(getFallbackDescriptions(item))
    return
  end

  if pendingItemDetails[itemId] and g_clock.millis() - pendingItemDetails[itemId] < 2000 then
    return
  end
  pendingItemDetails[itemId] = g_clock.millis()

  if OutputMessage and OutputMessage.create and g_game.getProtocolGame then
    local protocol = g_game.getProtocolGame()
    if protocol and protocol.send then
      pcall(function()
        local msg = OutputMessage.create()
        msg:addU8(OPCODE_ITEM_DETAILS)
        msg:addU16(itemId)
        protocol:send(msg)
      end)
    end
  end

  if not g_game.requestItemInfo then
    CyclopediaItems.showItemDescription(getFallbackDescriptions(item))
    return
  end

  local ok = pcall(function()
    g_game.requestItemInfo(realItem, 0)
  end)
  if not ok then
    CyclopediaItems.showItemDescription(getFallbackDescriptions(item))
  else
    scheduleEvent(function()
      if pendingItemDetails[itemId] and currentItem and getItemId(resolveRealItem(currentItem)) == itemId then
        pendingItemDetails[itemId] = nil
        CyclopediaItems.showItemDescription(getFallbackDescriptions(item))
      end
    end, 800)
  end
end

function CyclopediaItems.onItemDetails(protocol, msg)
  local ok, itemId = pcall(function() return msg:getU16() end)
  if not ok or not itemId or itemId <= 0 then
    return
  end

  local defaultValue = asNumber(msg:getU32())
  local defaultBuyPrice = asNumber(msg:getU32())
  local averageMarketPrice = asNumber(msg:getU32())
  local descriptions = {}
  local descriptionsSize = asNumber(msg:getU8())
  for i = 1, descriptionsSize do
    descriptions[#descriptions + 1] = {
      detail = msg:getString(),
      description = msg:getString()
    }
  end

  local npcSaleData = {}
  local npcSaleDataSize = asNumber(msg:getU16())
  for i = 1, npcSaleDataSize do
    npcSaleData[#npcSaleData + 1] = {
      name = msg:getString(),
      location = msg:getString(),
      buyPrice = asNumber(msg:getU32()),
      salePrice = asNumber(msg:getU32()),
      currencyQuestFlagDisplayName = msg:getString()
    }
  end

  pendingItemDetails[itemId] = nil
  itemsData.serverValues[tostring(itemId)] = defaultValue
  itemsData.serverBuyPrices[tostring(itemId)] = defaultBuyPrice
  itemsData.serverAverageMarketPrices[tostring(itemId)] = averageMarketPrice
  itemsData.serverNpcSaleData[tostring(itemId)] = npcSaleData
  itemsData.serverDetails[tostring(itemId)] = { descriptions = descriptions }

  if ItemsDatabase then
    if ItemsDatabase.registerServerItemValue and defaultValue > 0 then
      ItemsDatabase.registerServerItemValue(itemId, defaultValue)
    end
    ItemsDatabase.serverDetails = ItemsDatabase.serverDetails or {}
    ItemsDatabase.serverDetails[itemId] = { descriptions = descriptions }
  end

  saveData()

  if currentItem and getItemId(resolveRealItem(currentItem)) == itemId then
    CyclopediaItems.showItemDescription(descriptions)
    CyclopediaItems.showNpcData(resolveRealItem(currentItem))
    CyclopediaItems.showItemPrice(resolveRealItem(currentItem))
  end
end

function CyclopediaItems.onParseItemDetail(itemId, descriptions)
  pendingItemDetails[itemId] = nil
  itemsData.serverDetails[tostring(itemId)] = { descriptions = descriptions }
  if ItemsDatabase then
    ItemsDatabase.serverDetails = ItemsDatabase.serverDetails or {}
    ItemsDatabase.serverDetails[itemId] = { descriptions = descriptions }
  end
  if currentItem and getItemId(resolveRealItem(currentItem)) == itemId then
    CyclopediaItems.showItemDescription(descriptions)
  end
end

local function showEmptyState(empty)
  local emptyLabel = panel and panel:recursiveGetChildById('emptyLabel')
  local details = panel and panel:recursiveGetChildById('panelitemshide')
  if emptyLabel then emptyLabel:setVisible(empty) end
  if details then details:setVisible(not empty) end
end

function CyclopediaItems.itemListChildFocus(list, focusedChild)
  if not focusedChild then
    showEmptyState(true)
    return
  end

  currentItem = focusedChild.itemData
  local item = currentItem
  showEmptyState(false)

  local image = panel:recursiveGetChildById('itemImage')
  if image then setItemWidget(image, item) end

  CyclopediaItems.showNpcData(resolveRealItem(item))
  CyclopediaItems.showItemPrice(resolveRealItem(item))
  local cachedDescriptions = getCachedServerDescriptions(resolveRealItem(item))
  if cachedDescriptions then
    CyclopediaItems.showItemDescription(cachedDescriptions)
  else
    local detailsList = panel:recursiveGetChildById('basicDetails')
    if detailsList then
      detailsList:destroyChildren()
    end
  end
  CyclopediaItems.requestServerItemData(resolveRealItem(item))

  local drop = panel:recursiveGetChildById('checkbox-track-drops')
  if drop and modules.game_analyser and modules.game_analyser.isInDropTracker then
    drop:setChecked(modules.game_analyser.isInDropTracker(getItemId(resolveRealItem(item))))
  end

  local quickLoot = getQuickLoot()
  local quickLootBox = panel:recursiveGetChildById('checkLootbox')
  if quickLootBox and quickLoot and quickLoot.lootExists then
    quickLootBox:setChecked(quickLoot.lootExists(getItemId(resolveRealItem(item)), getQuickLootFilter()))
  end

  local quickSell = panel:recursiveGetChildById('quickListbox')
  if quickSell then
    local itemId = getItemId(resolveRealItem(item))
    local isWhitelisted = modules.game_npctrade and modules.game_npctrade.inWhiteList and modules.game_npctrade.inWhiteList(itemId)
    quickSell:setChecked(isWhitelisted == true)
  end

  local npcSource = panel:recursiveGetChildById('circlenpc')
  local marketSource = panel:recursiveGetChildById('circlemarket')
  local useMarket = itemsData.primaryLootValueSources[tostring(getItemId(resolveRealItem(item)))] == true
  if npcSource then npcSource:setChecked(not useMarket) end
  if marketSource then marketSource:setChecked(useMarket) end
end

local function passesFilters(item)
  local marketData = getMarketData(item)
  if not marketData or not panel then
    return true
  end

  local levelButton = panel:recursiveGetChildById('levelButton')
  if levelButton and levelButton:isChecked() then
    local level = asNumber(marketData.requiredLevel)
    local player = g_game.getLocalPlayer and g_game.getLocalPlayer()
    if player and level > 0 and player:getLevel() < level then
      return false
    end
  end

  local vocButton = panel:recursiveGetChildById('vocButton')
  if vocButton and vocButton:isChecked() and marketData.restrictVocation and marketData.restrictVocation > 0 then
    local player = g_game.getLocalPlayer and g_game.getLocalPlayer()
    if player and translateWheelVocation then
      local vocation = translateWheelVocation(player:getVocation())
      if tonumber(vocation) and tonumber(vocation) ~= tonumber(marketData.restrictVocation) then
        return false
      end
    end
  end

  return true
end

function CyclopediaItems.categoryListChildFocus(list, focusedChild)
  if not focusedChild then
    return
  end

  currentCategory = focusedChild.category
  local itemList = panel:recursiveGetChildById('itemList')
  itemList:destroyChildren()
  itemList.onChildFocusChange = CyclopediaItems.itemListChildFocus

  for _, item in ipairs(marketItems[currentCategory] or {}) do
    if passesFilters(item) then
      local widget = g_ui.createWidget('ItemListLabel', itemList)
      widget.itemData = item
      setItemWidget(widget.item, item)
      widget.name:setText(getItemName(item))
    end
  end

  local first = itemList:getFirstChild()
  if first then
    itemList:focusChild(first)
  else
    showEmptyState(true)
  end
end

function CyclopediaItems.showCategories()
  local categoriesList = panel:recursiveGetChildById('categoriesList')
  categoriesList:destroyChildren()
  categoriesList.onChildFocusChange = CyclopediaItems.categoryListChildFocus

  local first, last = getMarketRange()
  local categories = {}
  for category = first, last do
    if marketItems[category] and #marketItems[category] > 0 then
      table.insert(categories, category)
    end
  end
  for _, category in ipairs({GOLD_CATEGORY, UNSORTED_CATEGORY, WEAPONS_ALL_CATEGORY}) do
    if marketItems[category] and #marketItems[category] > 0 then
      table.insert(categories, category)
    end
  end

  for _, category in ipairs(categories) do
    local widget = g_ui.createWidget('CategoryItemListLabel', categoriesList)
    widget.category = category
    widget:setText(getCategoryName(category))
  end

  local firstChild = categoriesList:getFirstChild()
  if firstChild then
    categoriesList:focusChild(firstChild)
  end
end

function CyclopediaItems.onSearch(widget)
  local text = widget:getText():lower()
  local clearButton = widget:getParent() and widget:getParent():recursiveGetChildById('clearSearchButton')
  if clearButton then clearButton:setVisible(text ~= '') end
  CyclopediaItems.showSearchResult(text)
end

function CyclopediaItems.showSearchResult(text)
  if not panel or text == '' then
    if currentCategory then
      CyclopediaItems.categoryListChildFocus(nil, { category = currentCategory })
    end
    return
  end

  local itemList = panel:recursiveGetChildById('itemList')
  itemList:destroyChildren()
  itemList.onChildFocusChange = CyclopediaItems.itemListChildFocus

  for _, items in pairs(marketItems) do
    for _, item in ipairs(items) do
      if getItemName(item):lower():find(text, 1, true) then
        local widget = g_ui.createWidget('ItemListLabel', itemList)
        widget.itemData = item
        setItemWidget(widget.item, item)
        widget.name:setText(getItemName(item))
      end
    end
  end

  local first = itemList:getFirstChild()
  if first then
    itemList:focusChild(first)
  else
    showEmptyState(true)
  end
end

function CyclopediaItems.clearSearch(parent)
  local search = parent and parent:recursiveGetChildById('searchText')
  if search then
    search:setText('')
  end
end

function CyclopediaItems.onSortFields()
  if currentCategory and panel then
    CyclopediaItems.categoryListChildFocus(nil, { category = currentCategory })
  end
end

function CyclopediaItems.onSourceValueChange(checked, useNpc)
  if not checked or not currentItem then
    return
  end
  local itemId = tostring(getItemId(resolveRealItem(currentItem)))
  itemsData.primaryLootValueSources[itemId] = not useNpc
  saveData()
  CyclopediaItems.showItemPrice(resolveRealItem(currentItem))
end

function CyclopediaItems.onChangeCustomPrice(widget)
  if updatingPriceFields then
    return
  end
  if not currentItem then
    return
  end
  local itemId = tostring(getItemId(resolveRealItem(currentItem)))
  local value = asNumber(widget:getText())
  if value > 0 then
    itemsData.customSalePrices[itemId] = value
  else
    itemsData.customSalePrices[itemId] = nil
  end
  saveData()
  CyclopediaItems.showItemPrice(resolveRealItem(currentItem))
end

function CyclopediaItems.updateDropTracker(widget, checked)
  if currentItem and modules.game_analyser and modules.game_analyser.managerDropTracker then
    modules.game_analyser.managerDropTracker(getItemId(resolveRealItem(currentItem)), checked)
  end
end

function CyclopediaItems.manageQuickloot(widget, checked)
  local quickLoot = getQuickLoot()
  if not currentItem or not quickLoot then
    return
  end
  local itemId = getItemId(resolveRealItem(currentItem))
  if checked and quickLoot.addLootList then
    quickLoot.addLootList(itemId, getQuickLootFilter())
  elseif not checked and quickLoot.removeLootList then
    quickLoot.removeLootList(itemId, getQuickLootFilter())
  end
end

function CyclopediaItems.manageQuickSellWhitelist(widget, checked)
  if not currentItem or not modules.game_npctrade then
    if widget then widget:setChecked(false) end
    return
  end
  local itemId = getItemId(resolveRealItem(currentItem))
  if checked and modules.game_npctrade.addToWhitelist then
    modules.game_npctrade.addToWhitelist(itemId)
  elseif not checked and modules.game_npctrade.removeItemInList then
    modules.game_npctrade.removeItemInList(itemId)
  elseif widget then
    widget:setChecked(false)
  end
end

function CyclopediaItems.onClickLootContainers()
  local quickLoot = getQuickLoot()
  if quickLoot and quickLoot.show then
    quickLoot.show()
  elseif modules.game_quickloot and modules.game_quickloot.show then
    modules.game_quickloot.show()
  end
end

function CyclopediaItems.onRedirect(itemId)
  if itemId then
    show('items')
    scheduleEvent(function()
      CyclopediaItems.showSearchResult(getItemName(makeItem(itemId)):lower())
    end, 50)
  end
end

function CyclopediaItems.getCurrentItemValue(item)
  return getCurrentItemValue(item)
end

function CyclopediaItems.sendPartyLootItems()
  if g_game and g_game.sendPartyLootPrice then
    g_game.sendPartyLootPrice(itemsData.customSalePrices)
  end
end

function CyclopediaItems.loadJson()
  loadData()
end

function CyclopediaItems.saveJson()
  saveData()
end

function initItems(parent)
  loadData()
  CyclopediaItems.loadItems()
  CyclopediaItems.registerProtocol()

  if not panel then
    panel = g_ui.createWidget('ItemDataPanel', parent)
    local classOptions = panel:recursiveGetChildById('classOptions')
    if classOptions and classOptions.addOption then
      classOptions:addOption(tr('All'))
      classOptions:addOption(tr('Weapons'))
      classOptions:addOption(tr('Armors'))
      classOptions:addOption(tr('Others'))
    end
  else
    panel:setParent(parent)
    panel:show()
  end

  local search = panel:recursiveGetChildById('searchText')
  if search then
    search:setText('')
  end

  CyclopediaItems.showCategories()
end

function terminateItems()
  saveData()
  CyclopediaItems.unregisterProtocol()
  if panel then
    panel:destroy()
    panel = nil
  end
end

function CyclopediaItems.registerProtocol()
  if ProtocolGame and ProtocolGame.registerOpcode then
    ProtocolGame.unregisterOpcode(OPCODE_ITEM_DETAILS)
    ProtocolGame.registerOpcode(OPCODE_ITEM_DETAILS, CyclopediaItems.onItemDetails)
  end
end

function CyclopediaItems.unregisterProtocol()
  if ProtocolGame and ProtocolGame.unregisterOpcode then
    ProtocolGame.unregisterOpcode(OPCODE_ITEM_DETAILS)
  end
end
