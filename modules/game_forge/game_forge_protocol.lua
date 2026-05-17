-- Bridges Forgotten Server custom forge protocol (0xE2/0xE3) to the Mehah HTML forge UI.

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

  ForgeController._pendingForgeConfig = config
  addEvent(ForgeController.applyPendingForgeConfig)
end

function ForgeSystem.setResourceBalances(balances)
  if not balances then
    return
  end

  local cached = ForgeController.forgeBalances
  cached.bank = balances[ResourceBank] or cached.bank
  cached.inventory = balances[ResourceInventory] or cached.inventory
  cached.dust = balances[ResourceForgeDust] or cached.dust
  cached.slivers = balances[ResourceForgeSlivers] or cached.slivers
  cached.cores = balances[ResourceForgeExaltedCore] or cached.cores

  ForgeController:updateResourceBalances()
end

function ForgeSystem.onForgeData(fusionData, fusionConvergenceData, transferData, transferConvergenceData, maxPlayerDust)
  local payload = {
    fusionItems = convertFusionEntries(fusionData),
    convergenceFusion = convertConvergenceFusion(fusionConvergenceData),
    transfers = convertTransferEntries(transferData),
    convergenceTransfers = convertTransferEntries(transferConvergenceData),
    dustLevel = maxPlayerDust
  }

  ForgeController._pendingForgeOpenData = payload
  addEvent(ForgeController.applyPendingForgeOpenData)
end

function ForgeSystem.onForgeFusion(convergence, success, otherItem, otherTier, itemId, tier, resultType, itemResult,
                                   tierResult, count)
  ForgeController._pendingForgeResult = {
    leftItemId = otherItem,
    leftTier = otherTier,
    rightItemId = itemId,
    rightTier = tier,
    success = success,
    bonus = resultType,
    coreCount = count or 0,
    convergence = convergence
  }
  addEvent(ForgeController.applyPendingForgeResult)
end

function ForgeSystem.onForgeTransfer(convergence, success, otherItem, otherTier, itemId, tier)
  ForgeController._pendingForgeResult = {
    leftItemId = otherItem,
    leftTier = otherTier,
    rightItemId = itemId,
    rightTier = tier,
    success = success,
    bonus = 0,
    convergence = convergence
  }
  addEvent(ForgeController.applyPendingForgeResult)
end

function ForgeSystem.onForgeHistory(history)
  local historyList = {}
  for _, entry in ipairs(history or {}) do
    table.insert(historyList, {
      createdAt = entry[1],
      actionType = entry[2],
      description = entry[3]
    })
  end

  ForgeController._pendingForgeHistory = historyList
  addEvent(ForgeController.applyPendingForgeHistory)
end

function ForgeSystem.show()
  addEvent(ForgeController.showForgeWindow)
end

function offlineForge()
  ForgeController:hide()
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
