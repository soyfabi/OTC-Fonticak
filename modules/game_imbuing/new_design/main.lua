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

local function getPlayerBalance()
  local player = g_game.getLocalPlayer()
  if not player then
    return 0
  end

  local bankGold = player:getResourceBalance(ResourceTypes.BANK_BALANCE) or 0
  local inventoryGold = player:getResourceBalance(ResourceTypes.GOLD_EQUIPPED) or 0
  return bankGold + inventoryGold
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

context.imbuement = dofile('t_imbui')(context)
context.item = dofile('classes/imbuementitem')(context)
context.scroll = dofile('classes/imbuementscroll')(context)
context.selection = dofile('classes/imbuementselection')(context)

local api = {}

function api.init()
  return context.imbuement.init()
end

function api.terminate()
  return context.imbuement.terminate()
end

function api.close()
  return context.imbuement.close()
end

function api.hide()
  return context.imbuement.hide()
end

function api.onOpenImbuementWindow(...)
  return context.imbuement.onOpenImbuementWindow(...)
end

function api.onImbuementItem(...)
  return context.imbuement.onImbuementItem(...)
end

function api.onImbuementScroll(...)
  return context.imbuement.onImbuementScroll(...)
end

function api.onMessageDialog(...)
  return context.imbuement.onMessageDialog(...)
end

function api.onResourcesBalanceChange(...)
  return context.imbuement.onResourcesBalanceChange(...)
end

function api.onSelectItem()
  return context.imbuement.onSelectItem()
end

function api.onSelectScroll()
  return context.imbuement.onSelectScroll()
end

function api.onItemSlot(widget)
  return context.item.onSelectSlot(widget)
end

function api.onItemBaseType(selectedButtonId)
  return context.item.selectBaseType(selectedButtonId)
end

function api.onScrollBaseType(selectedButtonId)
  return context.scroll.selectBaseType(selectedButtonId)
end

return api
