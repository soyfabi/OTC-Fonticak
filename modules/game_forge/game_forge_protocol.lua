-- Bridges Fantoner-Server custom forge protocol (0xE2/0xE3) to the CrystalOTC forge UI.

ResourceBank = 0
ResourceInventory = 1
ResourceForgeDust = 20
ResourceForgeSlivers = 21
ResourceForgeExaltedCore = 22

ForgeSystem = {}

local function mapClassPrices(classPrice)
  local classPrices = {}
  for classId, data in pairs(classPrice or {}) do
    local tiers = {}
    for tierId, price in pairs(data[2] or {}) do
      table.insert(tiers, { tier = tierId, price = price })
    end
    table.insert(classPrices, { classId = classId, tiers = tiers })
  end
  return classPrices
end

local function mapTierPrices(priceMap)
  local prices = {}
  for tierId, price in pairs(priceMap or {}) do
    table.insert(prices, { tier = tierId, price = price })
  end
  return prices
end

local function mapFusionGrades(transferMap)
  local grades = {}
  for tierId, cores in pairs(transferMap or {}) do
    table.insert(grades, { tier = tierId, exaltedCores = cores })
  end
  return grades
end

local function convertFusionEntries(entries)
  local items = {}
  for _, entry in ipairs(entries or {}) do
    table.insert(items, {
      id = entry[1],
      tier = entry[2],
      count = entry[3],
      classification = entry[5] or 0,
      category = entry[6] or 0
    })
  end
  return items
end

local function convertConvergenceFusion(entries)
  local grouped = {}
  for index, entry in ipairs(entries or {}) do
    local slot = entry[6] or entry[5] or index
    grouped[slot] = grouped[slot] or {}
    table.insert(grouped[slot], {
      id = entry[1],
      tier = entry[2],
      count = entry[3],
      classification = entry[5] or 0,
      category = entry[6] or 0
    })
  end
  return grouped
end

local function convertTransferEntries(entries)
  local transfers = {}
  for index, entry in ipairs(entries or {}) do
    local donor = {
      id = entry[1],
      tier = entry[2],
      count = entry[3],
      classification = entry[5] or 0,
      category = entry[6] or 0
    }
    local receivers = {}
    for itemId, count in pairs(entry[4] or {}) do
      if itemId ~= entry[1] then
        table.insert(receivers, {
          id = itemId,
          tier = math.max(0, (entry[2] or 0) - 1),
          count = count
        })
      end
    end
    table.insert(transfers, {
      donors = { donor },
      receivers = receivers,
      slot = index
    })
  end
  return transfers
end

function ForgeSystem.init(classPrice, transferMap, fusionPrices, transferPrices, baseMultipier, slivers, totalSlivers,
                          dustCost, dustPrice, maxDust, dustFusion, convergenceDustFusion, dustTransfer,
                          convergenceDustTransfer, success, improveRateSuccess, tierLoss)
  local config = {
    classPrices = mapClassPrices(classPrice),
    classPriceRaw = classPrice,
    convergenceFusionPrices = mapTierPrices(fusionPrices),
    convergenceFusionPricesRaw = fusionPrices,
    convergenceTransferPrices = mapTierPrices(transferPrices),
    convergenceTransferPricesRaw = transferPrices,
    fusionGrades = mapFusionGrades(transferMap),
    normalDustFusion = dustFusion,
    convergenceFusionDust = convergenceDustFusion,
    normalDustTransfer = dustTransfer,
    convergenceDustTransfer = convergenceDustTransfer,
    fusionReduceTierLoss = tierLoss,
    fusionChanceImproved = improveRateSuccess,
    fusionChanceBase = success,
    hasConvergence = true,
    dustToSilver = slivers,
    sliverToCore = totalSlivers,
    maxDustCap = maxDust,
    maxDustLevel = dustPrice,
    dustLevel = dustPrice
  }

  onEngineForgeConfig(config)
end

function ForgeSystem.setResourceBalances(balances)
  if not balances then
    return
  end

  local player = g_game.getLocalPlayer()
  local dustVal = balances[ResourceForgeDust] or balances[20] or balances[23] or balances[70]
  local sliverVal = balances[ResourceForgeSlivers] or balances[21] or balances[24] or balances[71]
  local coreVal = balances[ResourceForgeExaltedCore] or balances[22] or balances[25] or balances[72]
  local bankVal = balances[ResourceBank] or balances[0]
  local invVal = balances[ResourceInventory] or balances[1]
  local limitVal = balances[88]

  if Forge then
    Forge.customBalances = Forge.customBalances or {}
    if bankVal ~= nil then Forge.customBalances.bank = bankVal end
    if invVal ~= nil then Forge.customBalances.inventory = invVal end
    if dustVal ~= nil then Forge.customBalances.dust = dustVal end
    if sliverVal ~= nil then Forge.customBalances.slivers = sliverVal end
    if coreVal ~= nil then Forge.customBalances.cores = coreVal end
    if limitVal ~= nil and limitVal >= 100 then
      Forge.dustLevel = math.max(0, math.floor((limitVal - 100) / 20))
    end
    if Forge.updateButtonHighlight then
      Forge:updateButtonHighlight()
    end
  end

  if not player then
    return
  end

  if dustVal ~= nil then
    player:setResourceBalance(70, dustVal)
    player:setResourceBalance(23, dustVal)
    player:setResourceBalance(20, dustVal)
  end
  if sliverVal ~= nil then
    player:setResourceBalance(71, sliverVal)
    player:setResourceBalance(24, sliverVal)
    player:setResourceBalance(21, sliverVal)
  end
  if coreVal ~= nil then
    player:setResourceBalance(72, coreVal)
    player:setResourceBalance(25, coreVal)
    player:setResourceBalance(22, coreVal)
  end

  onResourceBalance()
  if Forge and Forge.updateButtonHighlight then
    Forge:updateButtonHighlight()
  end
end

function ForgeSystem.onForgeData(fusionData, fusionConvergenceData, transferData, transferConvergenceData, maxPlayerDust)
  local payload = {
    fusionItems = convertFusionEntries(fusionData),
    convergenceFusion = convertConvergenceFusion(fusionConvergenceData),
    transfers = convertTransferEntries(transferData),
    convergenceTransfers = convertTransferEntries(transferConvergenceData),
    dustLevel = maxPlayerDust
  }

  onOpenExaltationForge(payload)
end

function ForgeSystem.onForgeFusion(convergence, success, otherItem, otherTier, itemId, tier, resultType, itemResult,
                                   tierResult, count)
  onEngineForgeResult({
    actionType = ACTION_FUSION_TYPE,
    leftItemId = otherItem,
    leftTier = otherTier,
    rightItemId = itemId,
    rightTier = tier,
    success = success,
    bonus = resultType,
    coreCount = count or 0,
    convergence = convergence
  })
end

function ForgeSystem.onForgeTransfer(convergence, success, otherItem, otherTier, itemId, tier)
  onEngineForgeResult({
    actionType = ACTION_TRANSFER_TYPE,
    leftItemId = otherItem,
    leftTier = otherTier,
    rightItemId = itemId,
    rightTier = tier,
    success = success,
    bonus = 0,
    convergence = convergence
  })
end

function ForgeSystem.onForgeHistory(currentPage, lastPage, history)
  local historyList = {}
  for _, entry in ipairs(history or {}) do
    table.insert(historyList, {
      date = os.date("%Y-%m-%d %H:%M", tonumber(entry[1]) or 0),
      action = entry[2],
      details = entry[3]
    })
  end

  onForgeHistory(currentPage, lastPage, historyList)
end

function ForgeSystem.show()
  forgeOpenRequest()
end

function offlineForge()
  Forge:close()
end

function forgeOpenRequest()
  if g_game.useCustomForgeProtocol() then
    ForgeProtocol.sendOpen()
  else
    g_game.openPortableForgeRequest()
  end
end

function forgeSendHistory(page)
  if g_game.useCustomForgeProtocol() then
    ForgeProtocol.sendHistory(page)
  else
    g_game.sendForgeHistory(page)
  end
end

function forgeSendAction(action, convergence, firstItem, firstTier, secondItem, improveChance, tierLoss)
  if not g_game.useCustomForgeProtocol() then
    return g_game.sendForgeAction(action, convergence, firstItem, firstTier, secondItem, improveChance, tierLoss)
  end

  if action == ACTION_FUSION_TYPE then
    return ForgeProtocol.sendForgeFusion(convergence, firstItem, firstTier, secondItem, improveChance, tierLoss)
  elseif action == ACTION_TRANSFER_TYPE then
    return ForgeProtocol.sendForgeTransfer(convergence, firstItem, firstTier, secondItem)
  end

  return ForgeProtocol.sendForgeConverter(action)
end

function initForgeProtocolBridge()
  initProtocol()
  if registerCustomForgeOpcode then
    registerCustomForgeOpcode()
  end
end

function terminateForgeProtocolBridge()
  terminateProtocol()
end
