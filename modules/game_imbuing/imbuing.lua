local function commaValue(amount)
  if not amount then
    return "0"
  end

  local formatted = tostring(amount)
  while true do
    local nextValue, changes = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    formatted = nextValue
    if changes == 0 then
      break
    end
  end

  return formatted
end

local function capitalize(str)
  if not str or str == "" then
    return str
  end

  return str:sub(1, 1):upper() .. str:sub(2)
end

local COIN_MULTIPLIERS = {
  [3031] = 1,
  [2148] = 1,
  [3035] = 100,
  [2152] = 100,
  [3043] = 10000,
  [2160] = 10000,
}

local function getPlayerBalance()
  local player = g_game.getLocalPlayer()
  if not player then
    return 0
  end

  local bankGold = (ResourceTypes and ResourceTypes.BANK_BALANCE and player:getResourceBalance(ResourceTypes.BANK_BALANCE)) or 0
  local inventoryGold = (ResourceTypes and ResourceTypes.GOLD_EQUIPPED and player:getResourceBalance(ResourceTypes.GOLD_EQUIPPED)) or 0

  local physicalCoins = 0
  for _, container in pairs(g_game.getContainers()) do
    for _, item in pairs(container:getItems()) do
      local mult = COIN_MULTIPLIERS[item:getId()]
      if mult then
        physicalCoins = physicalCoins + ((item:getCount() or 1) * mult)
      end
    end
  end

  local actualInventory = math.max(inventoryGold, physicalCoins)
  local total = bankGold + actualInventory
  if total > 0 then
    return total
  end

  if player.getTotalMoney then
    local money = player:getTotalMoney()
    if money and money > 0 then
      return money
    end
  end

  return 0
end

local function getItemNameById(itemId)
  local function validName(name)
    return name and name ~= "" and name ~= "unnamed" and name ~= "Unknown Item"
  end

  if Item and Item.create then
    local ok, item = pcall(function()
      return Item.create(itemId, 1)
    end)
    if ok and item then
      if item.getName then
        local nameOk, name = pcall(function()
          return item:getName()
        end)
        if nameOk and validName(name) then
          return name
        end
      end

      if item.getMarketData then
        local marketOk, marketData = pcall(function()
          return item:getMarketData()
        end)
        if marketOk and marketData and validName(marketData.name) then
          return marketData.name
        end
      end
    end
  end

  local itemType = g_things.getThingType(itemId, ThingCategoryItem)
  if itemType and itemType.getName and type(itemType.getName) == "function" then
    local name = itemType:getName()
    if validName(name) then
      return name
    end
  end

  return "Unknown Item"
end

local context = {
  commaValue = commaValue,
  capitalize = capitalize,
  getPlayerBalance = getPlayerBalance,
  getItemNameById = getItemNameById,
}

context.imbuement = dofile('imbui')(context)
context.item = dofile('classes/imbuementitem')(context)
context.scroll = dofile('classes/imbuementscroll')(context)
context.selection = dofile('classes/imbuementselection')(context)

local function onGameStart()
  if context.imbuement and context.imbuement.terminate then
    context.imbuement.terminate()
  end
end

local function onGameEnd()
  if context.imbuement and context.imbuement.terminate then
    context.imbuement.terminate()
  end
end

local function onOpenImbuementWindow(...)
  return context.imbuement.onOpenImbuementWindow(...)
end

local function onImbuementItem(...)
  return context.imbuement.onImbuementItem(...)
end

local function onImbuementWindow(itemId, slots, activeSlots, imbuements, needItems)
  return onImbuementItem(itemId, 0, slots, activeSlots, imbuements, needItems)
end

local function onImbuementScroll(...)
  return context.imbuement.onImbuementScroll(...)
end

local function onResourcesBalanceChange(...)
  if context.imbuement and context.imbuement.onResourcesBalanceChange then
    return context.imbuement.onResourcesBalanceChange(...)
  end
end

local function onCloseImbuementWindow()
  if context.imbuement and context.imbuement.close then
    context.imbuement.close()
  end
end

local function onMessageDialog(...)
  if context.imbuement and context.imbuement.onMessageDialog then
    return context.imbuement.onMessageDialog(...)
  end
end

function hide()
  return context.imbuement.hide()
end

function close()
  return context.imbuement.close()
end

function onSelectItem()
  return context.imbuement.onSelectItem()
end

function onSelectScroll()
  return context.imbuement.onSelectScroll()
end

function onItemSlot(widget)
  return context.item.onSelectSlot(widget)
end

function onItemBaseType(selectedButtonId)
  return context.item.selectBaseType(selectedButtonId)
end

function onScrollBaseType(selectedButtonId)
  return context.scroll.selectBaseType(selectedButtonId)
end

function init()
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onOpenImbuementWindow = onOpenImbuementWindow,
    onImbuementWindow = onImbuementWindow,
    onImbuementItem = onImbuementItem,
    onImbuementScroll = onImbuementScroll,
    onResourcesBalanceChange = onResourcesBalanceChange,
    onCloseImbuementWindow = onCloseImbuementWindow,
    onMessageDialog = onMessageDialog
  })

  if context.imbuement and context.imbuement.init then
    context.imbuement.init()
  end

  if g_game.isOnline() then
    addEvent(onGameStart)
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onOpenImbuementWindow = onOpenImbuementWindow,
    onImbuementWindow = onImbuementWindow,
    onImbuementItem = onImbuementItem,
    onImbuementScroll = onImbuementScroll,
    onResourcesBalanceChange = onResourcesBalanceChange,
    onCloseImbuementWindow = onCloseImbuementWindow,
    onMessageDialog = onMessageDialog
  })

  if context.imbuement and context.imbuement.terminate then
    context.imbuement.terminate()
  end
end
