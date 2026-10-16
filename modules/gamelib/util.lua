function postostring(pos)
    return pos.x .. ' ' .. pos.y .. ' ' .. pos.z
end

function dirtostring(dir)
    for k, v in pairs(Directions) do
        if v == dir then
            return k
        end
    end
end

function comma_value(n)
    if not n then return '0' end
    n = tostring(n)
    local left, num, right = string.match(n, '^([^%d]*%d)(%d*)(.-)$')
    if not left or not num or not right then
        return n
    end
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

function formatTimeBySeconds(totalSeconds)
    local hours = math.floor(totalSeconds / 3600)
    local remainingSeconds = totalSeconds % 3600
    local minutes = math.floor(remainingSeconds / 60)
    return string.format("%02d:%02d", hours, minutes)
end

function formatTimeByMinutes(totalMinutes)
    local totalSeconds = totalMinutes * 60
    local hours = math.floor(totalSeconds / 3600)
    local remainingSeconds = totalSeconds % 3600
    local minutes = math.floor(remainingSeconds / 60)
    return string.format("%02d:%02d", hours, minutes)
end

function math.cround(value, rd)
    local _round = math.floor(value / rd)
    return _round * rd
end

function formatMoney(amount, separator)
  local patternSeparator = string.format("%%1%s%%2", separator)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", patternSeparator)
    if (k==0) then
      break
    end
  end
  return formatted
end

if not setStringColor then
  function setStringColor(str, color)
    return str  -- ignora a cor e retorna o texto puro
  end
end

function convertLongGold(amount, shortValue, normalized)
    local hasBillion = false
    local hasTrillion = false
  
    local fomarType = 0
    if normalized and amount >= 1000000 then
      amount = math.floor(amount / 1000000)
      fomarType = 1
    elseif normalized and amount >= 10000 then
      amount = math.floor(amount / 1000)
      fomarType = 2
    elseif shortValue and amount > 10000000 then
        fomarType = 1
      amount = math.floor(amount / 1000000)
    elseif shortValue and amount > 1000000 then
        fomarType = 2
      amount = math.floor(amount / 1000)
    elseif amount > 999999999 then
      fomarType = 1
      amount = math.floor(amount / 1000000)
    elseif amount > 99999999 then
      fomarType = 2
      amount = math.floor(amount / 1000)
    end
  
    local formatted = amount
    while true do
      formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
      if (k==0) then
        break
      end
    end
  
    if fomarType == 1 then
      formatted = formatted .. " kk"
    elseif fomarType == 2 then
      formatted = formatted .. " k"
    end
  
    return formatted
end

function translateWheelVocation(id)
	-- Sprawdź czy id jest stringiem i spróbuj przekonwertować
	if type(id) == "string" then
		id = tonumber(id)
	end

	if id == 4 or id == 8 or id == 11 then
		return 1 -- ek
	elseif id == 3 or id == 7 or id == 12 then
		return 2 -- rp
	elseif id == 1 or id == 5 or id == 13 then
		return 3 -- ms
	elseif id == 2 or id == 6 or id == 14 then
		return 4 -- ed
	elseif id == 9 or id == 10 or id == 15 then
		return 5 -- em
	end
	return 0
end

-- servers may have different id's, change if not working properly (only for protocols 910+)
function getVocationSt(id)
	if id == 4 or id == 8 or id == 11 then
		return "K0"
	elseif id == 3 or id == 7 or id == 12 then
		return "P0"
	elseif id == 1 or id == 5 or id == 13 then
		return "S0"
	elseif id == 2 or id == 6 or id == 14 then
		return "D0"
	elseif id == 9 or id == 10 or id == 15 then
		return "M0"
	end
	return "N"
end

function getVocationId(name)
  if string.find(name:lower(), "knight") then
    return 11 -- Elite Knight
  elseif string.find(name:lower(), "paladin") then
    return 12 -- Royal Paladin
  elseif string.find(name:lower(), "sorcerer") or string.find(name:lower(), "mag") then
    return 13 -- Master Sorcerer
  elseif string.find(name:lower(), "druid") then
    return 14 -- Elder Druid
  elseif string.find(name:lower(), "monk") then
    return 15 -- Elder Monk
  end

  return 0
end

function roundToTwoDecimalPlaces(num)
  return math.floor(num * 100 + 0.5) / 100
end

function short_text(text, chars_limit)
  if not text then
    return ""
  end

  chars_limit = chars_limit or 20

  if string.len(text) <= chars_limit then
    return text
  end

  return string.sub(text, 1, chars_limit - 3) .. "..."
end

_G.short_text = short_text

local function isUsableItemDisplayName(name)
	return name and name ~= "" and name:lower() ~= "unnamed"
end

local cachedMarketItemsRef = nil
local cachedMarketItemNamesById = nil
local resolvedItemServerNames = {}
local resolvedWithMarketCatalog = {}

local function lookupServerMarketItemName(itemId)
	if modules.game_market and modules.game_market.getCachedCustomMarketItems then
		local serverItems = modules.game_market.getCachedCustomMarketItems()
		if serverItems then
			if serverItems ~= cachedMarketItemsRef then
				cachedMarketItemsRef = serverItems
				cachedMarketItemNamesById = {}
				for i = 1, #serverItems do
					local entry = serverItems[i]
					if entry and entry.id and isUsableItemDisplayName(entry.name) then
						cachedMarketItemNamesById[entry.id] = entry.name
					end
				end
			end
			return cachedMarketItemNamesById[itemId] or "", true
		end
	end
	return "", false
end

local function lookupThingTypeItemName(itemId)
	if itemId <= 0 then
		return ""
	end

	if g_things.findItemTypeByClientId then
		local itemType = g_things.findItemTypeByClientId(itemId)
		if itemType and itemType.getName then
			local name = itemType:getName()
			if isUsableItemDisplayName(name) then
				return name
			end
		end
	end

	if g_things.getItemType then
		local itemType = g_things.getItemType(itemId)
		if itemType then
			if itemType.getName then
				local name = itemType:getName()
				if isUsableItemDisplayName(name) then
					return name
				end
			end
			if itemType.getClientId and g_things.findItemTypeByClientId then
				local clientType = g_things.findItemTypeByClientId(itemType:getClientId())
				if clientType and clientType.getName then
					local name = clientType:getName()
					if isUsableItemDisplayName(name) then
						return name
					end
				end
			end
		end
	end

	if g_things.getCyclopediaItemName then
		local name = g_things.getCyclopediaItemName(itemId)
		if isUsableItemDisplayName(name) then
			return name
		end
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType then
		if Cyclopedia and Cyclopedia.getItemDisplayName then
			local name = Cyclopedia.getItemDisplayName(thingType)
			if isUsableItemDisplayName(name) then
				return name
			end
		end
		if thingType.getMarketData then
			local marketData = thingType:getMarketData()
			if marketData and isUsableItemDisplayName(marketData.name) then
				return marketData.name
			end
		end
		if thingType.getName then
			local name = thingType:getName()
			if isUsableItemDisplayName(name) then
				return name
			end
		end
	end

	return ""
end

function getItemServerName(itemId)
	itemId = tonumber(itemId) or 0
	if itemId <= 0 then
		return ""
	end

	if resolvedWithMarketCatalog[itemId] then
		return resolvedItemServerNames[itemId] or ""
	end

	local name, marketCatalogReady = lookupServerMarketItemName(itemId)
	if name ~= "" then
		local formatted = string.capitalize(name)
		resolvedItemServerNames[itemId] = formatted
		resolvedWithMarketCatalog[itemId] = true
		return formatted
	end

	if not marketCatalogReady and resolvedItemServerNames[itemId] then
		return resolvedItemServerNames[itemId]
	end

	name = lookupThingTypeItemName(itemId)
	if name ~= "" then
		local formatted = string.capitalize(name)
		resolvedItemServerNames[itemId] = formatted
		if marketCatalogReady then
			resolvedWithMarketCatalog[itemId] = true
		end
		return formatted
	end

	if Item and Item.create then
		local ok, item = pcall(Item.create, itemId)
		if ok and item then
			if item.getMarketData then
				local marketData = item:getMarketData()
				if marketData and isUsableItemDisplayName(marketData.name) then
					local formatted = string.capitalize(marketData.name)
					resolvedItemServerNames[itemId] = formatted
					if marketCatalogReady then
						resolvedWithMarketCatalog[itemId] = true
					end
					return formatted
				end
			end
			if item.getName then
				local itemName = item:getName()
				if isUsableItemDisplayName(itemName) then
					local formatted = string.capitalize(itemName)
					resolvedItemServerNames[itemId] = formatted
					if marketCatalogReady then
						resolvedWithMarketCatalog[itemId] = true
					end
					return formatted
				end
			end
		end
	end

	if marketCatalogReady then
		resolvedItemServerNames[itemId] = ""
		resolvedWithMarketCatalog[itemId] = true
	end

	return ""
end

_G.getItemServerName = getItemServerName

