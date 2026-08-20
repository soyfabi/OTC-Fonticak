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
  if Forge then
    Forge.customBalances = Forge.customBalances or {}
    Forge.customBalances.bank = balances[ResourceBank] or Forge.customBalances.bank or 0
    Forge.customBalances.inventory = balances[ResourceInventory] or Forge.customBalances.inventory or 0
    Forge.customBalances.dust = balances[ResourceForgeDust] or Forge.customBalances.dust or 0
    Forge.customBalances.slivers = balances[ResourceForgeSlivers] or Forge.customBalances.slivers or 0
    Forge.customBalances.cores = balances[ResourceForgeExaltedCore] or Forge.customBalances.cores or 0
  end

  if not player then
    return
  end

  player:setResourceBalance(ResourceForgeDust + 50, balances[ResourceForgeDust] or 0)
  player:setResourceBalance(ResourceForgeSlivers + 50, balances[ResourceForgeSlivers] or 0)
  player:setResourceBalance(ResourceForgeExaltedCore + 50, balances[ResourceForgeExaltedCore] or 0)
  onResourceBalance()
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
