-- Weapon Proficiency Module
-- Implements the Weapon Proficiency system from Summer Update 2025
-- credits: cipsoft
if not WeaponProficiency then
    WeaponProficiency = {}
    WeaponProficiency.__index = WeaponProficiency

    WeaponProficiency.window = nil
    WeaponProficiency.displayItemPanel = nil
    WeaponProficiency.perkPanel = nil
    WeaponProficiency.bonusDetailPanel = nil
    WeaponProficiency.starProgressPanel = nil
    WeaponProficiency.optionFilter = nil
    WeaponProficiency.itemListScroll = nil
    WeaponProficiency.vocationWarning = nil
    WeaponProficiency.warningWindow = nil
    WeaponProficiency.button = nil
    WeaponProficiency.modifyButton = nil
    WeaponProficiency.modifyCost = nil
    WeaponProficiency.modifyCostText = nil

    WeaponProficiency.itemList = {}
    WeaponProficiency.cacheList = {} -- [itemId] = {experience, perks}

    WeaponProficiency.allProficiencyRequested = false
    WeaponProficiency.firstItemRequested = nil
    WeaponProficiency.saveWeaponMissing = false

    WeaponProficiency.ItemCategory = {
        Axes = 17,
        Clubs = 18,
        DistanceWeapons = 19,
        Swords = 20,
        WandsRods = 21,
        FistWeapons = 27
    }

    WeaponProficiency.perkPanelsName = {"oneBonusIconPanel", "twoBonusIconPanel", "threeBonusIconPanel"}

    WeaponProficiency.filters = {
        ["levelButton"] = false,
        ["vocButton"] = false,
        ["oneButton"] = false,
        ["twoButton"] = false
    }

    -- Search filter
    WeaponProficiency.searchFilter = nil

    -- Scrollable settings
    WeaponProficiency.listWidgetHeight = 34
    WeaponProficiency.listCapacity = 0
    WeaponProficiency.listMinWidgets = 0
    WeaponProficiency.listMaxWidgets = 0
    WeaponProficiency.offset = 0
    WeaponProficiency.listPool = {}
    WeaponProficiency.listData = {}
end

WeaponProficiency = WeaponProficiency or {}
WeaponProficiency.__index = WeaponProficiency

WeaponProficiency.itemList = WeaponProficiency.itemList or {}
WeaponProficiency.cacheList = WeaponProficiency.cacheList or {}
WeaponProficiency.ItemCategory = WeaponProficiency.ItemCategory or {
    Axes = 17,
    Clubs = 18,
    DistanceWeapons = 19,
    Swords = 20,
    WandsRods = 21,
    FistWeapons = 27
}
WeaponProficiency.perkPanelsName = WeaponProficiency.perkPanelsName or
                                       {"oneBonusIconPanel", "twoBonusIconPanel", "threeBonusIconPanel"}
WeaponProficiency.filters = WeaponProficiency.filters or {}
WeaponProficiency.filters["levelButton"] = WeaponProficiency.filters["levelButton"] or false
WeaponProficiency.filters["vocButton"] = WeaponProficiency.filters["vocButton"] or false
WeaponProficiency.filters["oneButton"] = WeaponProficiency.filters["oneButton"] or false
WeaponProficiency.filters["twoButton"] = WeaponProficiency.filters["twoButton"] or false
WeaponProficiency.listPool = WeaponProficiency.listPool or {}
WeaponProficiency.listData = WeaponProficiency.listData or {}
WeaponProficiency.listWidgetHeight = WeaponProficiency.listWidgetHeight or 34
WeaponProficiency.listCapacity = WeaponProficiency.listCapacity or 0
WeaponProficiency.listMinWidgets = WeaponProficiency.listMinWidgets or 0
WeaponProficiency.listMaxWidgets = WeaponProficiency.listMaxWidgets or 0
WeaponProficiency.offset = WeaponProficiency.offset or 0

local function getNumericCall(obj, methodName)
    if not obj or not obj[methodName] then
        return 0
    end

    local ok, value = pcall(function()
        return obj[methodName](obj)
    end)
    if not ok then
        return 0
    end
    return tonumber(value) or 0
end

local function getLeftSlotItem()
    local player = g_game.getLocalPlayer()
    return player and player:getInventoryItem(InventorySlotLeft) or nil
end

local PROFICIENCY_MODULE_HIGHLIGHT_DEBUG = false

local function debugModuleHighlight(message)
    if PROFICIENCY_MODULE_HIGHLIGHT_DEBUG then
        print(string.format('[WeaponProficiency.highlight] %s', message))
    end
end

local WEAPON_MARKET_CATEGORIES = {
    [17] = true,
    [18] = true,
    [19] = true,
    [20] = true,
    [21] = true,
    [27] = true
}

local function equippedItemMatchesProficiencyHighlight(item)
    if not item or not item.getId then
        return false
    end

    local itemId = item:getId()

    if WeaponProficiency.unusedPerkItemId and WeaponProficiency.unusedPerkItemId == itemId then
        debugModuleHighlight(string.format('equippedWeapon: server perk itemId=%s', tostring(itemId)))
        return true
    end

    if WeaponProficiency.cacheList[itemId] then
        debugModuleHighlight(string.format('equippedWeapon: cache itemId=%s', tostring(itemId)))
        return true
    end

    if type(canOpenForItem) == 'function' and canOpenForItem(item) then
        debugModuleHighlight(string.format('equippedWeapon: canOpen itemId=%s', tostring(itemId)))
        return true
    end

    local thingType = item.getThingType and item:getThingType() or g_things.getThingType(itemId, ThingCategoryItem)
    if thingType then
        if getNumericCall(thingType, 'getProficiencyId') > 0 or getNumericCall(thingType, 'getWeaponType') > 0 then
            debugModuleHighlight(string.format('equippedWeapon: thingType itemId=%s', tostring(itemId)))
            return true
        end

        local marketData = thingType.getMarketData and thingType:getMarketData() or nil
        if marketData and WEAPON_MARKET_CATEGORIES[marketData.category] then
            debugModuleHighlight(string.format('equippedWeapon: marketCat itemId=%s', tostring(itemId)))
            return true
        end
    end

    debugModuleHighlight(string.format('equippedWeapon: no match itemId=%s', tostring(itemId)))
    return false
end

local function equippedWeaponSupportsProficiencyHighlight()
    local item = getLeftSlotItem()
    if not item then
        debugModuleHighlight('equippedWeapon: no left-hand item')
        return false
    end

    return equippedItemMatchesProficiencyHighlight(item)
end

local function hasUnusedPerkHighlightFlag()
    local flag = WeaponProficiency.hasUnusedPerk
    if flag == true or flag == 1 then
        return true
    end
    if type(flag) == 'number' and flag ~= 0 then
        return true
    end
    return false
end

local function shouldShowProficiencyModuleButtonHighlight()
    local windowVisible = WeaponProficiency.window and WeaponProficiency.window:isVisible()
    local weaponOk = equippedWeaponSupportsProficiencyHighlight()
    local unusedPerk = hasUnusedPerkHighlightFlag()

    if windowVisible then
        debugModuleHighlight(string.format('shouldShow=false (window open) unusedPerk=%s', tostring(WeaponProficiency.hasUnusedPerk)))
        return false
    end

    if not weaponOk then
        debugModuleHighlight(string.format('shouldShow=false (weapon) unusedPerk=%s raw=%s', tostring(unusedPerk),
            tostring(WeaponProficiency.hasUnusedPerk)))
        return false
    end

    if not unusedPerk then
        debugModuleHighlight(string.format('shouldShow=false (no unused perk) raw=%s type=%s', tostring(WeaponProficiency.hasUnusedPerk),
            type(WeaponProficiency.hasUnusedPerk)))
        return false
    end

    debugModuleHighlight('shouldShow=true')
    return true
end

local function onPlayerInventoryChange(player, slot, item, oldItem)
    if slot ~= InventorySlotLeft then
        return
    end

    debugModuleHighlight(string.format('inventory left slot: item=%s old=%s hasUnusedPerk=%s',
        item and tostring(item:getId()) or 'nil',
        oldItem and tostring(oldItem:getId()) or 'nil',
        tostring(WeaponProficiency.hasUnusedPerk)))

    refreshEquippedProficiencyStatusBar(nil, true)
end

local function hasWeaponProficiencyProtocol()
    return type(g_game.sendWeaponProficiencyAction) == 'function' and
               type(g_game.sendWeaponProficiencyApply) == 'function'
end

local function sendWeaponProficiencyAction(actionType, itemId)
    if not hasWeaponProficiencyProtocol() then
        return false
    end

    g_game.sendWeaponProficiencyAction(actionType, itemId or 0)
    return true
end

local function sendWeaponProficiencyApply(itemId, levels, perkPositions)
    if not hasWeaponProficiencyProtocol() then
        return false
    end

    g_game.sendWeaponProficiencyApply(itemId, levels, perkPositions)
    return true
end

local function findMarketItemByAnyId(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return nil
    end
    for _, marketItem in ipairs(WeaponProficiency.itemList or {}) do
        local originalId = tonumber(marketItem.originalId)
        if originalId == itemId then
            return marketItem
        end
        local displayId = tonumber(marketItem.displayId)
        if displayId == itemId then
            return marketItem
        end
        if marketItem.displayItem then
            if marketItem.displayItem:getId() == itemId then
                return marketItem
            end
        end
    end
    return nil
end

local function getProficiencyCacheKey(itemId)
    local marketItem = findMarketItemByAnyId(itemId)
    if marketItem and marketItem.originalId then
        return tonumber(marketItem.originalId) or marketItem.originalId
    end
    return tonumber(itemId) or itemId
end

local function getWeaponProficiencyCache(itemId)
    local key = getProficiencyCacheKey(itemId)
    local cache = WeaponProficiency.cacheList[key]
    if cache then
        return cache, key
    end
    cache = WeaponProficiency.cacheList[itemId]
    if cache then
        WeaponProficiency.cacheList[key] = cache
        return cache, key
    end
    return nil, key
end

local function setWeaponProficiencyCache(itemId, cacheEntry)
    local key = getProficiencyCacheKey(itemId)
    WeaponProficiency.cacheList[key] = cacheEntry
    local marketItem = findMarketItemByAnyId(itemId)
    if marketItem and marketItem.displayItem then
        local clientId = marketItem.displayItem:getId()
        if clientId and clientId ~= key then
            WeaponProficiency.cacheList[clientId] = cacheEntry
        end
    end
    local numericId = tonumber(itemId)
    if numericId and numericId ~= key then
        WeaponProficiency.cacheList[numericId] = cacheEntry
    end
end

local function getProtocolItemId(marketItem, fallbackItemId)
    if marketItem and marketItem.displayItem then
        return marketItem.displayItem:getId()
    end
    if marketItem and marketItem.displayId then
        return tonumber(marketItem.displayId) or marketItem.displayId
    end
    return fallbackItemId
end

local function proficiencyItemsMatch(selectedItemId, incomingItemId)
    if not selectedItemId or not incomingItemId then
        return false
    end
    return getProficiencyCacheKey(selectedItemId) == getProficiencyCacheKey(incomingItemId)
end

local function getPlayerWheelVocation()
    local player = g_game.getLocalPlayer()
    if not player then
        return 0
    end

    if translateWheelVocation then
        return translateWheelVocation(player:getVocation())
    end

    local vocation = player:getVocation()
    return vocation > 10 and vocation - 10 or vocation
end

local function hasBit(mask, bitMask)
    if Bit and Bit.hasBit then
        return Bit.hasBit(mask, bitMask)
    end
    return math.floor(mask / bitMask) % 2 == 1
end

local function vocationBit(vocation)
    if vocation <= 0 then
        return 0
    end
    if Bit and Bit.bit then
        return Bit.bit(vocation)
    end
    return 2 ^ (vocation - 1)
end

local function vocationRestrictionMatches(restrictVocation, playerVocation)
    if not restrictVocation or restrictVocation == 0 then
        return true
    end

    if type(restrictVocation) == "table" then
        for _, vocationId in pairs(restrictVocation) do
            local normalized = vocationId > 10 and vocationId - 10 or vocationId
            if normalized == playerVocation then
                return true
            end
        end
        return false
    end

    local bitMask = vocationBit(playerVocation)
    return bitMask > 0 and hasBit(restrictVocation, bitMask)
end

local function categoryMatchesPlayerVocation(category)
    local requiredMask = WeaponCategoryVocation and WeaponCategoryVocation[category] or 0
    if requiredMask == 0 then
        return true
    end

    local bitMask = vocationBit(getPlayerWheelVocation())
    return bitMask > 0 and hasBit(requiredMask, bitMask)
end

local function getVocationWarningDecision(marketData, thingType)
    local player = g_game.getLocalPlayer()
    local rawVocation = player and player:getVocation() or 0
    local playerLevel = player and player:getLevel() or 0
    local playerVocation = getPlayerWheelVocation()
    local playerBit = vocationBit(playerVocation)
    local category = marketData and marketData.category or nil
    local requiredMask = WeaponCategoryVocation and WeaponCategoryVocation[category] or 0
    local restrictVocation = marketData and marketData.restrictVocation or 0
    local minimumLevel = getNumericCall(thingType, "getMinimumLevel")
    if minimumLevel == 0 and marketData and marketData.requiredLevel then
        minimumLevel = tonumber(marketData.requiredLevel) or 0
    end

    local categoryMatch = categoryMatchesPlayerVocation(category)
    local hasRestrictVocation = restrictVocation and restrictVocation ~= 0
    local restrictMatch = vocationRestrictionMatches(restrictVocation, playerVocation)
    local levelMatch = minimumLevel == 0 or playerLevel >= minimumLevel
    local vocationMatch = hasRestrictVocation and restrictMatch or categoryMatch

    local showWarning = not vocationMatch or not levelMatch

    return {
        rawVocation = rawVocation,
        playerLevel = playerLevel,
        playerVocation = playerVocation,
        playerBit = playerBit,
        category = category,
        requiredMask = requiredMask,
        categoryMatch = categoryMatch,
        restrictVocation = restrictVocation,
        hasRestrictVocation = hasRestrictVocation,
        restrictMatch = restrictMatch,
        vocationMatch = vocationMatch,
        minimumLevel = minimumLevel,
        levelMatch = levelMatch,
        showWarning = showWarning
    }
end

function init()
    g_ui.importStyle('proficiency_modify.otui')

    -- Load proficiency JSON data
    if ProficiencyData:loadProficiencyJson() then
        -- Create item cache from market data
        WeaponProficiency:createItemCache()
    end

    -- Connect to game events
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onWeaponProficiencyCatalogItem = onWeaponProficiencyCatalogItem,
        onWeaponProficiencyCatalogReady = onWeaponProficiencyCatalogReady,
        onWeaponProficiency = onWeaponProficiency,
        onWeaponProficiencyExperience = onWeaponProficiencyExperience,
        onWeaponProficiencyReshape = onWeaponProficiencyReshape,
        onResourcesBalanceChange = onWeaponProficiencyResourceBalanceChange
    })

    connect(LocalPlayer, {
        onInventoryChange = onPlayerInventoryChange
    })

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    cancelProficiencyButtonInit()
    cancelTopBarProficiencyInit()
    cancelEquippedProficiencyRefreshTimers()
    cancelAutoSelect()
    if WeaponProficiency.itemListRenderEvent then
        removeEvent(WeaponProficiency.itemListRenderEvent)
        WeaponProficiency.itemListRenderEvent = nil
    end
    WeaponProficiency._itemListRenderGeneration = (WeaponProficiency._itemListRenderGeneration or 0) + 1

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onWeaponProficiencyCatalogItem = onWeaponProficiencyCatalogItem,
        onWeaponProficiencyCatalogReady = onWeaponProficiencyCatalogReady,
        onWeaponProficiency = onWeaponProficiency,
        onWeaponProficiencyExperience = onWeaponProficiencyExperience,
        onWeaponProficiencyReshape = onWeaponProficiencyReshape,
        onResourcesBalanceChange = onWeaponProficiencyResourceBalanceChange
    })

    disconnect(LocalPlayer, {
        onInventoryChange = onPlayerInventoryChange
    })

    if WeaponProficiency.window then
        WeaponProficiency.window:destroy()
        WeaponProficiency.window = nil
    end

    if WeaponProficiency.warningWindow then
        WeaponProficiency.warningWindow:destroy()
        WeaponProficiency.warningWindow = nil
    end

    if WeaponProficiency.closeReshapeDialog then
        WeaponProficiency:closeReshapeDialog()
    end
end

local function setProficiencyButtonState(state)
    if not WeaponProficiency.button then
        return
    end

    local button = WeaponProficiency.button:getChildById('button')
    if button then
        button:setOn(state)
        button:setImageClip(state and '0 20 20 20' or '0 0 20 20')
    elseif WeaponProficiency.button.setOn then
        WeaponProficiency.button:setOn(state)
    end
end

local function createProficiencyButton()
    WeaponProficiency.buttonOwned = false

    if modules.game_sidebuttons then
        local button = modules.game_sidebuttons.proficiencyButton
        if not button and modules.game_sidebuttons.buttonsWindow then
            button = modules.game_sidebuttons.buttonsWindow:recursiveGetChildById('proficiencyButton')
        end
        if button then
            button:setTooltip(tr('Open Weapon Proficiency'))
            button.onClick = toggle
            return button
        end
    end

    if modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
        WeaponProficiency.buttonOwned = true
        return modules.game_mainpanel.addToggleButton('ProficiencyButton', tr('Open Weapon Proficiency'),
            '/images/options/button_proficiency', toggle, false, 21, true)
    end

    if modules.client_topmenu and modules.client_topmenu.addRightGameToggleButton then
        WeaponProficiency.buttonOwned = true
        return modules.client_topmenu.addRightGameToggleButton('ProficiencyButton', tr('Open Weapon Proficiency'),
            '/images/options/button_proficiency', toggle, false, 21)
    end

    return nil
end

function cancelProficiencyButtonInit()
    if WeaponProficiency.buttonInitEvent then
        removeEvent(WeaponProficiency.buttonInitEvent)
        WeaponProficiency.buttonInitEvent = nil
    end
end

function initProficiencyButton(attempts)
    attempts = attempts or 0
    local maxRetries = 15

    cancelProficiencyButtonInit()

    if WeaponProficiency.button and not WeaponProficiency.button:isDestroyed() then
        setProficiencyButtonState(false)
        refreshProficiencyModuleButtonHighlight()
        return
    end

    WeaponProficiency.button = createProficiencyButton()
    if WeaponProficiency.button then
        if modules.game_mainpanel and modules.game_mainpanel.ensureControlButtonVisible then
            modules.game_mainpanel.ensureControlButtonVisible('ProficiencyButton')
        end
        setProficiencyButtonState(false)
        refreshProficiencyModuleButtonHighlight()
        return
    end

    if attempts < maxRetries then
        WeaponProficiency.buttonInitEvent = scheduleEvent(function()
            WeaponProficiency.buttonInitEvent = nil
            if g_game.isOnline() then
                initProficiencyButton(attempts + 1)
            end
        end, 100)
    end
end

function cancelTopBarProficiencyInit()
    if WeaponProficiency.topBarInitEvent then
        removeEvent(WeaponProficiency.topBarInitEvent)
        WeaponProficiency.topBarInitEvent = nil
    end
end

function cancelAutoSelect()
    if WeaponProficiency.autoSelectEvent then
        removeEvent(WeaponProficiency.autoSelectEvent)
        WeaponProficiency.autoSelectEvent = nil
    end
end

function scheduleAutoSelect(delay)
    cancelAutoSelect()
    WeaponProficiency.autoSelectEvent = scheduleEvent(function()
        WeaponProficiency.autoSelectEvent = nil
        autoSelectItem()
    end, delay)
end

function onGameStart()
    WeaponProficiency.allProficiencyRequested = false
    WeaponProficiency.saveWeaponMissing = false
    WeaponProficiency.firstItemRequested = nil
    WeaponProficiency.cacheList = {}
    WeaponProficiency.currentEquippedExp = 0
    WeaponProficiency.currentEquippedMaxExp = 0

    -- Client version can change after module init; reload before rebuilding the item cache.
    ProficiencyData:loadProficiencyJson(true)

    -- Recreate item cache on each login (may have been cleared by reset())
    WeaponProficiency:createItemCache()

    initProficiencyButton()

    if not hasWeaponProficiencyProtocol() then
        return
    end

    -- Initialize topbar proficiency widget
    initTopBarProficiency()
    requestAllWeaponProficiencyDataIfNeeded()
    scheduleEvent(function()
        if g_game.isOnline() then
            updateTopBarProficiency()
        end
    end, 0)
end

function requestAllWeaponProficiencyDataIfNeeded()
    if not hasWeaponProficiencyProtocol() then
        return false
    end
    if WeaponProficiency.allProficiencyRequested then
        return true
    end
    if sendWeaponProficiencyAction(1) then
        WeaponProficiency.allProficiencyRequested = true
        return true
    end
    return false
end

-- Initialize the proficiency widget in the top stats bar
function initTopBarProficiency(attempts)
    attempts = attempts or 0
    local maxRetries = 15

    -- Delay initialization to ensure StatsBar is fully loaded
    cancelTopBarProficiencyInit()
    WeaponProficiency.topBarInitEvent = scheduleEvent(function()
        WeaponProficiency.topBarInitEvent = nil
        -- Access StatsBar through modules.game_interface
        local StatsBarModule = modules.game_interface and modules.game_interface.StatsBar
        if not StatsBarModule then
            if attempts < maxRetries then
                initTopBarProficiency(attempts + 1)
            end
            return
        end

        local statsBar = StatsBarModule.getCurrentStatsBarWithPosition and
                             StatsBarModule.getCurrentStatsBarWithPosition()
        if statsBar then
            local profWidget = statsBar:recursiveGetChildById('proficiencyTopBar')
                or statsBar:recursiveGetChildById('compactTopCenterRow')
                or statsBar:recursiveGetChildById('largeTopCenterRow')
            if profWidget then
                profWidget:setVisible(true)

                requestAllWeaponProficiencyDataIfNeeded()
                requestEquippedWeaponProficiencyData()
                refreshEquippedProficiencyStatusBar(WeaponProficiency.hasUnusedPerk, true)
            end
        else
            if attempts < maxRetries then
                initTopBarProficiency(attempts + 1)
            end
        end
    end, 500) -- 500ms delay
end

local equippedProficiencyRefreshGeneration = 0
local equippedProficiencyDebounceEvent = nil
local equippedProficiencyFollowUpEvent = nil
local lastEquippedProficiencyCacheKey = nil

local function cancelEquippedProficiencyRefreshTimers()
    if equippedProficiencyDebounceEvent then
        removeEvent(equippedProficiencyDebounceEvent)
        equippedProficiencyDebounceEvent = nil
    end
    if equippedProficiencyFollowUpEvent then
        removeEvent(equippedProficiencyFollowUpEvent)
        equippedProficiencyFollowUpEvent = nil
    end
end

local function resolveEquippedProficiencyContext()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local leftSlotItem = player:getInventoryItem(InventorySlotLeft)
    if not leftSlotItem then
        return nil
    end

    local itemId = leftSlotItem:getId()
    local thingType = leftSlotItem.getThingType and leftSlotItem:getThingType()
        or g_things.getThingType(itemId, ThingCategoryItem)
    local marketItem = WeaponProficiency.findMarketItem and WeaponProficiency:findMarketItem(itemId)
    local cacheId = itemId
    local displayItem = leftSlotItem
    local marketData = thingType and thingType.getMarketData and thingType:getMarketData() or nil

    if marketItem then
        cacheId = marketItem.originalId or cacheId
        if marketItem.displayItem then
            displayItem = marketItem.displayItem
        end
        if marketItem.thingType then
            thingType = marketItem.thingType
        end
        if marketItem.marketData then
            marketData = marketItem.marketData
        end
    end

    local cacheData = WeaponProficiency.cacheList[cacheId] or WeaponProficiency.cacheList[itemId]

    return {
        leftSlotItem = leftSlotItem,
        itemId = itemId,
        cacheId = cacheId,
        cacheData = cacheData,
        displayItem = displayItem,
        thingType = thingType,
        marketData = marketData
    }
end

local function proficiencyItemMatchesEquipped(itemId)
    if not itemId then
        return false
    end
    local context = resolveEquippedProficiencyContext()
    if not context then
        return false
    end
    return itemId == context.itemId or itemId == context.cacheId
end

local function refreshEquippedUnusedPerkState(itemId)
    local context = resolveEquippedProficiencyContext()
    if not context or not context.cacheData then
        return
    end
    if itemId and not proficiencyItemMatchesEquipped(itemId) then
        return
    end

    local cache = context.cacheData
    local hasUnused = false
    if ProficiencyData and ProficiencyData.hasUnspentPerk then
        hasUnused = ProficiencyData:hasUnspentPerk(cache.exp, cache.perks, context.displayItem, context.thingType,
            context.marketData)
    end

    WeaponProficiency.hasUnusedPerk = hasUnused
    if hasUnused then
        WeaponProficiency.unusedPerkItemId = context.cacheId
    elseif proficiencyItemMatchesEquipped(WeaponProficiency.unusedPerkItemId) then
        WeaponProficiency.unusedPerkItemId = nil
    end
end

function requestEquippedWeaponProficiencyData()
    if not hasWeaponProficiencyProtocol() then
        return
    end

    local context = resolveEquippedProficiencyContext()
    if not context or not context.leftSlotItem then
        return
    end

    if not canOpenForItem(context.leftSlotItem) and not equippedWeaponSupportsProficiencyHighlight() then
        local weaponType = getNumericCall(context.leftSlotItem, 'getWeaponType')
        if weaponType <= 0 then
            return
        end
    end

    requestAllWeaponProficiencyDataIfNeeded()
    sendWeaponProficiencyAction(0, context.cacheId)
end

local function syncEquippedProficiencyStatusBar(hasHighlight)
    local statsBar = modules.game_interface and modules.game_interface.StatsBar
    if not statsBar or not statsBar.onUpdateProficiencyData then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local context = resolveEquippedProficiencyContext()
    if not context then
        statsBar.onUpdateProficiencyData(nil, false, nil)
        return
    end

    if not context.thingType then
        return
    end

    if context.cacheData then
        if hasHighlight == nil then
            refreshEquippedUnusedPerkState()
            hasHighlight = WeaponProficiency.hasUnusedPerk
        end
        statsBar.onUpdateProficiencyData(context.cacheData, hasHighlight, context.thingType)
    else
        updateTopBarProficiency()
        requestEquippedWeaponProficiencyData()
    end
end

local function flushEquippedProficiencyStatusBar()
    syncEquippedProficiencyStatusBar(nil)
    updateProficiencyHighlight()
end

function refreshEquippedProficiencyStatusBar(hasHighlight, requestServer)
    equippedProficiencyRefreshGeneration = equippedProficiencyRefreshGeneration + 1
    local generation = equippedProficiencyRefreshGeneration

    cancelEquippedProficiencyRefreshTimers()

    local context = resolveEquippedProficiencyContext()
    local cacheKey = context and tostring(context.cacheId) or 'none'
    if cacheKey ~= lastEquippedProficiencyCacheKey then
        lastEquippedProficiencyCacheKey = cacheKey
        if not context or not context.cacheData then
            WeaponProficiency.hasUnusedPerk = false
            WeaponProficiency.unusedPerkItemId = nil
        end
    end

    if requestServer ~= false and context then
        requestEquippedWeaponProficiencyData()
    end

    equippedProficiencyDebounceEvent = scheduleEvent(function()
        equippedProficiencyDebounceEvent = nil
        if generation ~= equippedProficiencyRefreshGeneration or not g_game.isOnline() then
            return
        end
        flushEquippedProficiencyStatusBar()
    end, 100)

    equippedProficiencyFollowUpEvent = scheduleEvent(function()
        equippedProficiencyFollowUpEvent = nil
        if generation ~= equippedProficiencyRefreshGeneration or not g_game.isOnline() then
            return
        end
        flushEquippedProficiencyStatusBar()
    end, 400)
end

local TOP_BAR_PROFICIENCY_PLACEHOLDER = '---'

local function setTopBarProficiencyProgressBar(progressBar, percent)
    if not progressBar then
        return
    end
    if progressBar.setOn then
        progressBar:setOn(true)
    end
    if progressBar.setPercent then
        progressBar:setPercent(percent)
    elseif progressBar.setValue then
        progressBar:setValue(percent, 0, 100)
    end
    if progressBar.updateBackground then
        progressBar:updateBackground()
    end
end

local function applyTopBarProficiencyPlaceholder(statsBar)
    if not statsBar then
        return
    end
    local progressPanel = statsBar:recursiveGetChildById('proficiencyPanel')
    if progressPanel then
        progressPanel:show()
    end
    local progressBar = statsBar:recursiveGetChildById('proficiencyProgress')
    local label = statsBar:recursiveGetChildById('proficiencyLabel')
    local bg = statsBar:recursiveGetChildById('proficiencyBg')
    if progressBar then
        if progressBar.setPercent then
            progressBar:setPercent(0)
        end
        if progressBar.setOn then
            progressBar:setOn(false)
        end
        if progressBar.updateBackground then
            progressBar:updateBackground()
        end
    end
    if label then
        label:setText(TOP_BAR_PROFICIENCY_PLACEHOLDER)
    end
    if bg then
        bg:setTooltip(tr('Proficiency Progress: loading'))
    end
end

-- Update the proficiency progress bar in the top bar
function updateTopBarProficiency()
    -- Access StatsBar through modules.game_interface
    local StatsBarModule = modules.game_interface and modules.game_interface.StatsBar
    if not StatsBarModule then
        return
    end

    local statsBar = StatsBarModule.getCurrentStatsBarWithPosition and StatsBarModule.getCurrentStatsBarWithPosition()
    if not statsBar then
        return
    end

    local context = resolveEquippedProficiencyContext()
    if not context then
        -- No weapon equipped - show 0%
        local progressBar = statsBar:recursiveGetChildById('proficiencyProgress')
        local label = statsBar:recursiveGetChildById('proficiencyLabel')
        local progressPanel = statsBar:recursiveGetChildById('proficiencyPanel')
        if progressPanel then
            progressPanel:hide()
        end
        setTopBarProficiencyProgressBar(progressBar, 0)
        if label then
            label:setText('0%')
        end
        updateProficiencyHighlight()
        return
    end

    local itemId = context.cacheId
    local cacheData = context.cacheData

    if cacheData then
        local progressPanel = statsBar:recursiveGetChildById('proficiencyPanel')
        if progressPanel then
            progressPanel:show()
        end
        local exp = cacheData.exp or 0
        local displayItem = context.displayItem
        local thingType = context.thingType
        local marketData = context.marketData

        local percent = 0
        local targetStarExp = 0

        if ProficiencyData and ProficiencyData.getNextStarProgress then
            percent, _, _, targetStarExp = ProficiencyData:getNextStarProgress(exp, displayItem, thingType, marketData)
        end

        percent = math.min(100, math.max(0, percent))

        local progressBar = statsBar:recursiveGetChildById('proficiencyProgress')
        local label = statsBar:recursiveGetChildById('proficiencyLabel')
        local bg = statsBar:recursiveGetChildById('proficiencyBg')
        if progressBar and progressBar.setOn then
            progressBar:setOn(true)
        end
        setTopBarProficiencyProgressBar(progressBar, percent)
        if label then
            label:setText(percent .. '%')
        end
        local tooltipText = nil
        if bg then
            if percent >= 100 and targetStarExp > 0 and exp >= targetStarExp then
                tooltipText = tr('Mastery achieved')
            else
                tooltipText = string.format("%s / %s", comma_value(exp), comma_value(targetStarExp or 0))
            end
            bg:setTooltip(tooltipText)
        end
        local proficiencyButtonIds = {
            'proficiencyButton',
            'proficiencyButtonCompact',
            'proficiencyButtonLarge'
        }
        for _, buttonId in ipairs(proficiencyButtonIds) do
            local profButton = statsBar:recursiveGetChildById(buttonId)
            if profButton then
                if tooltipText then
                    profButton:setTooltip(tooltipText)
                else
                    profButton:setTooltip(tr('Open Weapon Proficiency Dialog'))
                end
            end
        end

        -- Store for reference
        WeaponProficiency.currentEquippedExp = exp
        WeaponProficiency.currentEquippedMaxExp = targetStarExp
    else
        applyTopBarProficiencyPlaceholder(statsBar)
    end
end

function onGameEnd()
    equippedProficiencyRefreshGeneration = equippedProficiencyRefreshGeneration + 1
    cancelEquippedProficiencyRefreshTimers()
    lastEquippedProficiencyCacheKey = nil
    cancelProficiencyButtonInit()
    cancelTopBarProficiencyInit()
    cancelAutoSelect()

    if WeaponProficiency.window then
        WeaponProficiency.window:hide()
    end

    if WeaponProficiency.button then
        if WeaponProficiency.buttonOwned then
            WeaponProficiency.button:destroy()
        else
            setProficiencyButtonState(false)
        end
        WeaponProficiency.button = nil
    end
    WeaponProficiency.buttonOwned = false

    WeaponProficiency:reset()
    WeaponProficiency.selectedModifySlot = nil
end

function onWeaponProficiencyCatalogItem(itemId, marketCategory, name, proficiencyId)
    WeaponProficiency:addCatalogItem(itemId, marketCategory, name, proficiencyId)
end

function onWeaponProficiencyCatalogReady()
    sortWeaponProficiency(MarketCategory.WeaponsAll)
    for _, categoryId in pairs(WeaponProficiency.ItemCategory) do
        sortWeaponProficiency(categoryId)
    end

    if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        WeaponProficiency:refreshItemList()
    end

    requestEquippedWeaponProficiencyData()
    refreshEquippedProficiencyStatusBar(nil, false)
end

-- Called when server sends proficiency info (opcode 0xC4)
function onWeaponProficiency(itemId, experience, perks, marketCategory, modifiedSlots)
    -- Ensure perks is a table
    if type(perks) ~= "table" then
        perks = {}
    end

    -- IMPORTANT: Server sends perks in 0-indexed format, convert to 1-indexed for Lua
    -- Also filter out invalid perks (values >= 200 are clearly invalid, likely from uninitialized data)
    local convertedPerks = {}
    for _, perk in ipairs(perks) do
        if type(perk) == "table" and #perk >= 2 then
            local level = perk[1]
            local perkPos = perk[2]
            -- Filter out invalid values (255 becomes 256 after +1, which is invalid)
            -- Valid levels are 0-6 (0-indexed), valid perk positions are 0-2 (0-indexed)
            if level >= 0 and level <= 10 and perkPos >= 0 and perkPos <= 10 then
                -- Convert from 0-indexed (server) to 1-indexed (Lua)
                table.insert(convertedPerks, {level + 1, perkPos + 1})
            end
        end
    end

    local convertedModifiers = {}
    for _, modifier in ipairs(modifiedSlots or {}) do
        local grade = tonumber(modifier.grade)
        local slot = tonumber(modifier.slot)
        if grade and slot then
            convertedModifiers[#convertedModifiers + 1] = {
                grade = grade + 1,
                slot = slot + 1,
                modifierEnum = tonumber(modifier.modifierEnum) or 0,
                refineLevel = tonumber(modifier.refineLevel) or 0
            }
        end
    end

    local existingCache = getWeaponProficiencyCache(itemId)
    local perksForCache = convertedPerks
    local modifiersForCache = convertedModifiers
    if #modifiersForCache == 0 and #convertedPerks == 0 and existingCache and existingCache.modifiers
        and #existingCache.modifiers > 0 then
        modifiersForCache = existingCache.modifiers
    end

    setWeaponProficiencyCache(itemId, {
        exp = experience,
        perks = perksForCache,
        modifiers = modifiersForCache
    })

    local cachePerks = perksForCache

    -- Re-sort the item list when we receive new proficiency data
    if marketCategory then
        sortWeaponProficiency(marketCategory)
        sortWeaponProficiency(MarketCategory.WeaponsAll)
    end

    if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        -- Update stars only (lighter than full rebuild)
        WeaponProficiency:updateVisibleItemStars()

        WeaponProficiency:onUpdateSelectedProficiency(itemId)

        -- If this is the currently selected item, update display with cached perks
        if proficiencyItemsMatch(WeaponProficiency.selectedItemId, itemId) then
            local cacheKey = getProficiencyCacheKey(itemId)
            WeaponProficiency:displayProficiencyData(cacheKey, experience, cachePerks)
        end
        WeaponProficiency:updateModifyButtonState()
        WeaponProficiency:updateModifyCost()
    end

    if proficiencyItemMatchesEquipped(itemId) then
        refreshEquippedUnusedPerkState(itemId)
        refreshEquippedProficiencyStatusBar(nil, false)
    end
end

function onWeaponProficiencyExperience(itemId, experience, hasUnusedPerk)
    local itemCache = WeaponProficiency.cacheList[itemId]
    if not itemCache then
        WeaponProficiency.cacheList[itemId] = {
            exp = experience,
            perks = {}
        }
    else
        itemCache.exp = experience
    end

    -- Re-sort all categories when experience changes
    sortWeaponProficiency(MarketCategory.WeaponsAll)
    for _, categoryId in pairs(WeaponProficiency.ItemCategory) do
        sortWeaponProficiency(categoryId)
    end

    -- Store the unused perk state globally
    WeaponProficiency.hasUnusedPerk = hasUnusedPerk
    if hasUnusedPerk then
        WeaponProficiency.unusedPerkItemId = itemId
    else
        WeaponProficiency.unusedPerkItemId = nil
    end

    debugModuleHighlight(string.format('onWeaponProficiencyExperience itemId=%s exp=%s hasUnusedPerk=%s type=%s',
        tostring(itemId), tostring(experience), tostring(hasUnusedPerk), type(hasUnusedPerk)))

    if proficiencyItemMatchesEquipped(itemId) then
        refreshEquippedProficiencyStatusBar(nil, false)
    else
        updateProficiencyHighlight()
    end

    -- Update item stars if window is visible (lighter than full rebuild)
    if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        WeaponProficiency:updateVisibleItemStars()
        WeaponProficiency:updateModifyCost()
        WeaponProficiency:updateModifyButtonState()
    end
end

function onWeaponProficiencyResourceBalanceChange(value, oldBalance, resourceType)
    if resourceType == ResourceTypes.WEAPON_PROFICIENCY_FORGE_DUST then
        WeaponProficiency:updateForgeDustBalance()
        WeaponProficiency:updateModifyCost()
        WeaponProficiency:updateModifyButtonState()
    end
end

function WeaponProficiency:updateForgeDustBalance()
    if not self.window then return end

    local balancePanel = self.window:recursiveGetChildById('forgeDustBalance')
    local balanceLabel = balancePanel and balancePanel:getChildById('text')
    if not balanceLabel then return end

    local player = g_game.getLocalPlayer()
    local balance = player and player:getResourceBalance(ResourceTypes.WEAPON_PROFICIENCY_FORGE_DUST) or 0
    local dustLevel = Forge and Forge.getDustLevel and Forge:getDustLevel() or 0
    local maximum = 100 + dustLevel * 20
    local formatNumber = Forge and Forge.formatNumber and function(value) return Forge:formatNumber(value) end
        or function(value) return tostring(math.floor(tonumber(value) or 0)) end
    balanceLabel:setText(formatNumber(balance) .. '/' .. formatNumber(maximum))
end

local function getProficiencyModuleToggleButton()
    if WeaponProficiency.button and not WeaponProficiency.button:isDestroyed() then
        return WeaponProficiency.button
    end

    if modules.game_mainpanel and modules.game_mainpanel.getButton then
        local button = modules.game_mainpanel.getButton('ProficiencyButton')
        if button and not button:isDestroyed() then
            WeaponProficiency.button = button
            return button
        end
    end

    return nil
end

local function setProficiencyModuleButtonAttention(visible)
    local toggleButton = getProficiencyModuleToggleButton()
    if not toggleButton then
        debugModuleHighlight(string.format('setAttention(%s): ProficiencyButton widget not found', tostring(visible)))
        return
    end

    debugModuleHighlight(string.format('setAttention(%s): buttonId=%s class=%s', tostring(visible),
        tostring(toggleButton:getId()), tostring(toggleButton:getClassName())))

    local highlight = toggleButton:getChildById('highlight')
    if not highlight then
        highlight = g_ui.createWidget('UIWidget', toggleButton)
        highlight:setId('highlight')
        highlight:setSize('22 22')
        highlight:setPhantom(true)
        highlight:setFocusable(false)
        highlight:setVisible(false)
        highlight:setImageSource('/images/topbuttons/highlight')
        highlight:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        highlight:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    end

    local bright = toggleButton:getChildById('brightButton')
    if not bright then
        bright = g_ui.createWidget('UIWidget', toggleButton)
        bright:setId('brightButton')
        bright:setSize('20 20')
        bright:setPhantom(true)
        bright:setFocusable(false)
        bright:setVisible(false)
        bright:setImageSource('/images/ui/bright-x20')
        bright:addAnchor(AnchorTop, 'parent', AnchorTop)
        bright:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    end

    highlight:setVisible(visible)
    bright:setVisible(visible)
    highlight:raise()
    bright:raise()

    debugModuleHighlight(string.format('widgets highlight=%s bright=%s highlightVisible=%s brightVisible=%s',
        highlight and 'ok' or 'nil', bright and 'ok' or 'nil',
        highlight and tostring(highlight:isVisible()) or 'n/a',
        bright and tostring(bright:isVisible()) or 'n/a'))
end

function refreshProficiencyModuleButtonHighlight()
    setProficiencyModuleButtonAttention(shouldShowProficiencyModuleButtonHighlight())
end

-- Update highlights: module button (reward wall style) + stats bar perk indicators
function updateProficiencyHighlight()
    local shouldShow = shouldShowProficiencyModuleButtonHighlight()
    refreshProficiencyModuleButtonHighlight()

    local statsBar = modules.game_interface and modules.game_interface.StatsBar
    if statsBar and statsBar.setProficiencyHighlight then
        statsBar.setProficiencyHighlight(shouldShow)
    end
end

function WeaponProficiency.hasModuleButtonHighlightActive()
    return shouldShowProficiencyModuleButtonHighlight()
end

-- Public function to open the proficiency window
function show()
    if not WeaponProficiency.window then
        if not createWindow() then
            return false
        end
    end

    if not WeaponProficiency.window then
        return false
    end

    -- Reset search filter and clear search text
    WeaponProficiency.searchFilter = nil
    local searchText = WeaponProficiency.window:recursiveGetChildById('searchText')
    if searchText then
        searchText:setText('')
    end

    -- Reset filter buttons visual state (but keep filter state)
    -- The filters persist across open/close

    WeaponProficiency.window:show()
    WeaponProficiency.window:raise()
    WeaponProficiency.window:focus()

    setProficiencyButtonState(true)
    setProficiencyModuleButtonAttention(false)

    local statsBar = modules.game_interface and modules.game_interface.StatsBar
    if statsBar and statsBar.setProficiencyHighlight then
        statsBar.setProficiencyHighlight(false)
    end

    -- Refresh item list to show all items
    WeaponProficiency:refreshItemList()

    -- Auto-select item when window opens (equipped weapon or first in list)
    -- Use longer delay to ensure items are loaded, with retry
    WeaponProficiency.autoSelectRetries = 0
    scheduleAutoSelect(300)
    return true
end

-- Auto-select an item (equipped weapon or first in list)
function autoSelectItem()
    if not WeaponProficiency.window or not WeaponProficiency.window:isVisible() then
        return
    end

    -- Already has a selected item with perks displayed? Skip
    if WeaponProficiency.selectedMarketItem and WeaponProficiency.selectedMarketItem.displayItem then
        local perkPanel = WeaponProficiency.perkPanel
        if perkPanel and perkPanel:getChildCount() > 0 then
            return
        end
    end

    local targetItemId = nil
    local targetMarketItem = nil

    -- Get all items from all categories
    local allItems = WeaponProficiency.itemList[MarketCategory.WeaponsAll] or {}

    -- First, check if player has an equipped weapon
    local player = g_game.getLocalPlayer()
    if player then
        local leftSlotItem = player:getInventoryItem(InventorySlotLeft)
        if leftSlotItem then
            local equippedId = leftSlotItem:getId()
            -- Search for this item in our list
            for _, marketItem in ipairs(allItems) do
                local itemId = marketItem.originalId or (marketItem.displayItem and marketItem.displayItem:getId())
                local displayId = marketItem.displayId or itemId
                if itemId == equippedId or displayId == equippedId then
                    targetItemId = itemId
                    targetMarketItem = marketItem
                    break
                end
            end
        end
    end

    -- If no equipped weapon found, select first item from the allItems list
    if not targetItemId and #allItems > 0 then
        -- Just take the first item from the list
        local firstItem = allItems[1]
        if firstItem then
            targetItemId = firstItem.originalId or (firstItem.displayItem and firstItem.displayItem:getId())
            targetMarketItem = firstItem
        end
    end

    -- Fallback: check UI item list if allItems is empty
    if not targetItemId then
        local itemList = WeaponProficiency.window:recursiveGetChildById("itemList")
        if itemList then
            local children = itemList:getChildren()
            for _, child in ipairs(children) do
                local itemWidget = child:getChildById('item')
                if itemWidget then
                    local displayItem = itemWidget:getItem()
                    if displayItem and displayItem:getId() > 0 then
                        local displayItemId = displayItem:getId()
                        -- Find the marketItem for this display
                        for _, marketItem in ipairs(allItems) do
                            local mItemId = marketItem.originalId or
                                                (marketItem.displayItem and marketItem.displayItem:getId())
                            local mDisplayId = marketItem.displayId or mItemId
                            if mDisplayId == displayItemId or mItemId == displayItemId then
                                targetItemId = mItemId
                                targetMarketItem = marketItem
                                break
                            end
                        end
                        if targetItemId then
                            break
                        end
                    end
                end
            end
        end
    end

    -- Select the target item
    if targetItemId and targetMarketItem then
        WeaponProficiency:selectItem(targetItemId, targetMarketItem)
    else
        -- Retry if no item found yet (cache might not be ready)
        WeaponProficiency.autoSelectRetries = (WeaponProficiency.autoSelectRetries or 0) + 1
        if WeaponProficiency.autoSelectRetries < 5 then
            scheduleAutoSelect(200)
        end
    end
end

function hide()
    if not WeaponProficiency.window then
        return
    end

    cancelAutoSelect()

    -- Close window
    WeaponProficiency.window:hide()

    setProficiencyButtonState(false)

    -- Re-show highlight if there are still unused perks
    updateProficiencyHighlight()

    -- Reset selected item state so auto-select works on next open
    WeaponProficiency.selectedItemId = nil
    WeaponProficiency.selectedDisplayId = nil
    WeaponProficiency.selectedMarketItem = nil
end

function WeaponProficiency:onCloseWindow()
    local hasPending = self.pendingSelections and next(self.pendingSelections) ~= nil
    if not hasPending then
        hide()
        return true
    end

    if self.warningWindow then
        self.warningWindow:destroy()
        self.warningWindow = nil
    end

    local yesButton = function()
        if self.warningWindow then
            self.warningWindow:destroy()
            self.warningWindow = nil
        end
        self:applyPendingSelections()
        hide()
    end

    local noButton = function()
        if self.warningWindow then
            self.warningWindow:destroy()
            self.warningWindow = nil
        end
        self.pendingSelections = {}
        self:updateApplyButtonState()
        hide()
    end

    self.warningWindow = displayGeneralBox('Save?',
        "You did not save the changes you have made to your perks.\n\nWould you like to save your perks?", {{
            text = tr('Yes'),
            callback = yesButton
        }, {
            text = tr('No'),
            callback = noButton
        }}, yesButton, noButton)
    return false
end

function toggle()
    if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        WeaponProficiency:onCloseWindow()
    else
        requestOpenWindow()
    end
end

function canOpenForItem(item)
    if not item or not item.getId then
        return false
    end

    if item.isItem and not item:isItem() then
        -- Equipped/inventory items are not always flagged as Item in the UI sense.
        local thingType = item.getThingType and item:getThingType() or
            g_things.getThingType(item:getId(), ThingCategoryItem)
        if not thingType then
            return false
        end
    end

    if getNumericCall(item, "getProficiencyId") > 0 then
        return true
    end

    local thingType = item.getThingType and item:getThingType() or
        g_things.getThingType(item:getId(), ThingCategoryItem)
    if not thingType then
        return false
    end

    local typeProficiencyId = getNumericCall(thingType, "getProficiencyId")
    if typeProficiencyId > 0 or getNumericCall(thingType, "getWeaponType") > 0 then
        return true
    end

    local marketData = thingType.getMarketData and thingType:getMarketData() or nil
    local weaponCategories = {
        [17] = true, -- Axes
        [18] = true, -- Clubs
        [19] = true, -- Distance weapons
        [20] = true, -- Swords
        [21] = true, -- Wands and rods
        [27] = true -- Fist weapons
    }
    if marketData and weaponCategories[marketData.category] then
        return true
    end

    WeaponProficiency:ensureItemCache()
    return WeaponProficiency:findMarketItem(item:getId()) ~= nil
end

-- Request to open proficiency window with optional item redirect
function requestOpenWindow(redirectItem)
    WeaponProficiency:ensureItemCache()

    local category = "Weapons: All"
    local targetItemId = nil
    local targetMarketItem = nil

    -- Check left hand slot for equipped weapon
    local leftSlotItem = getLeftSlotItem()
    if leftSlotItem then
        local weaponType = getNumericCall(leftSlotItem, "getWeaponType")
        if weaponType > 0 then
            category = getWeaponCategoryString(weaponType)
        end
        targetItemId = leftSlotItem:getId()
    end

    if redirectItem then
        local weaponType = getNumericCall(redirectItem, "getWeaponType")
        if weaponType > 0 then
            category = getWeaponCategoryString(weaponType)
        end
        targetItemId = redirectItem:getId()
    end

    if not targetItemId and WeaponProficiency.firstItemRequested then
        targetItemId = WeaponProficiency.firstItemRequested:getId()
        local weaponType = WeaponProficiency.firstItemRequested.getWeaponType and
                               WeaponProficiency.firstItemRequested:getWeaponType() or 0
        category = getWeaponCategoryString(weaponType)
    end

    if targetItemId then
        targetMarketItem = WeaponProficiency:findMarketItem(targetItemId)
    end

    if not requestAllWeaponProficiencyDataIfNeeded() then
        return
    end
    if redirectItem then
        WeaponProficiency.firstItemRequested = redirectItem
    end

    if not show() then
        return
    end

    if WeaponProficiency.optionFilter and category then
        WeaponProficiency.optionFilter:setCurrentOption(category, true)
        WeaponProficiency:refreshItemList()
    end

    if targetMarketItem then
        scheduleEvent(function()
            if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
                local displayId = targetMarketItem.displayId or targetMarketItem.originalId or targetItemId
                WeaponProficiency:selectItem(displayId, targetMarketItem)
            end
        end, 50)
    end
end

-- Helper function to get weapon category string
function getWeaponCategoryString(weaponType)
    if WeaponCategoryToString[weaponType] then
        return WeaponCategoryToString[weaponType]
    end

    local categoryMap = {
        [1] = "Weapons: Clubs", -- WEAPON_CLUB
        [2] = "Weapons: Axes", -- WEAPON_AXE
        [3] = "Weapons: Swords", -- WEAPON_SWORD
        [4] = "Weapons: Wands", -- WEAPON_WANDROD
        [7] = "Weapons: Distance", -- WEAPON_BOW
        [8] = "Weapons: Distance", -- WEAPON_THROW
        [9] = "Weapons: Distance", -- WEAPON_CROSSBOW
        [0] = "Weapons: Fist" -- WEAPON_FIST
    }
    return categoryMap[weaponType] or "Weapons: All"
end

-- Create the proficiency window
function createWindow()
    WeaponProficiency.window = g_ui.displayUI('proficiency')
    if not WeaponProficiency.window then
        return false
    end
    WeaponProficiency.window:hide()

    WeaponProficiency.displayItemPanel = WeaponProficiency.window:recursiveGetChildById("itemPanel")
    WeaponProficiency.modifyButton = WeaponProficiency.window:recursiveGetChildById("modifyButton")
    WeaponProficiency.modifyCost = WeaponProficiency.window:recursiveGetChildById("modifyCost")
    WeaponProficiency.modifyCostText = WeaponProficiency.window:recursiveGetChildById("modifyCostText")
    WeaponProficiency.perkPanel = WeaponProficiency.window:recursiveGetChildById("bonusProgressBackground")
    WeaponProficiency.bonusDetailPanel = WeaponProficiency.window:recursiveGetChildById("bonusDetailBackground")
    WeaponProficiency.optionFilter = WeaponProficiency.window:recursiveGetChildById("classFilter")
    WeaponProficiency.starProgressPanel = WeaponProficiency.window:recursiveGetChildById("starsPanelBackground")
    WeaponProficiency.itemListScroll = WeaponProficiency.window:recursiveGetChildById("itemListScroll")
    WeaponProficiency.vocationWarning = WeaponProficiency.window:recursiveGetChildById("vocationWarning")
    WeaponProficiency:updateForgeDustBalance()
    WeaponProficiency:updateModifyCost()
    WeaponProficiency:updateModifyButtonState()

    -- Debug: verify panels are found

    -- Setup category dropdown options
    if WeaponProficiency.optionFilter then
        WeaponProficiency.optionFilter:clearOptions()
        WeaponProficiency.optionFilter:addOption("Weapons: All")
        WeaponProficiency.optionFilter:addOption("Weapons: Swords")
        WeaponProficiency.optionFilter:addOption("Weapons: Axes")
        WeaponProficiency.optionFilter:addOption("Weapons: Clubs")
        WeaponProficiency.optionFilter:addOption("Weapons: Distance")
        WeaponProficiency.optionFilter:addOption("Weapons: Wands")
        WeaponProficiency.optionFilter:addOption("Weapons: Fist")
        WeaponProficiency.optionFilter.onOptionChange = function(widget, option)
            WeaponProficiency:refreshItemList()
        end
    end

    -- Setup search text handler
    local searchText = WeaponProficiency.window:recursiveGetChildById('searchText')
    if searchText then
        searchText.onTextChange = function(widget, text)
            WeaponProficiency.searchFilter = text
            WeaponProficiency:refreshItemList()
        end
    end

    -- Setup clear search button
    local clearButton = WeaponProficiency.window:recursiveGetChildById('clearSearchButton')
    if clearButton then
        clearButton.onClick = function()
            local searchWidget = WeaponProficiency.window:recursiveGetChildById('searchText')
            if searchWidget then
                searchWidget:setText('')
                WeaponProficiency.searchFilter = nil
                WeaponProficiency:refreshItemList()
            end
        end
    end

    -- Skip initial refreshItemList here; show() will call it
    return true
end

-- Reset proficiency data
function WeaponProficiency:reset()
    cancelAutoSelect()
    if self.itemListRenderEvent then
        removeEvent(self.itemListRenderEvent)
        self.itemListRenderEvent = nil
    end
    self._itemListRenderGeneration = (self._itemListRenderGeneration or 0) + 1
    self.cacheList = {}
    self.allProficiencyRequested = false
    self.itemList = {}
    self.catalogItems = {}
    self.selectedItemId = nil
    self.selectedDisplayId = nil
    self.selectedMarketItem = nil
    self.pendingSelections = {}
    self.hasUnusedPerk = false
    self.unusedPerkItemId = nil
    self.autoSelectRetries = 0
    self._itemCacheReady = false
end

function WeaponProficiency:ensureItemCache()
    if self._itemCacheReady then
        return
    end
    self:createItemCache()
end

-- Create item cache from proficiency things
function WeaponProficiency:createItemCache()
    self.itemList = {}
    self.catalogItems = {}
    self.itemList[MarketCategory.WeaponsAll] = {}
    self.ItemCategory = self.ItemCategory or {
        Axes = 17,
        Clubs = 18,
        DistanceWeapons = 19,
        Swords = 20,
        WandsRods = 21,
        FistWeapons = 27
    }

    for _, v in pairs(self.ItemCategory) do
        self.itemList[v] = {}
    end

    -- Weapon categories that support proficiency
    local weaponCategories = {
        [MarketCategory.Axes] = true,
        [MarketCategory.Clubs] = true,
        [MarketCategory.DistanceWeapons] = true,
        [MarketCategory.Swords] = true,
        [MarketCategory.WandsRods] = true,
        [MarketCategory.FistWeapons] = true
    }

    local itemTypes = {}
    local useProficiencyThings = g_things.getProficiencyThings ~= nil
    if useProficiencyThings then
        itemTypes = g_things.getProficiencyThings()
    end

    for _, itemType in pairs(itemTypes) do
        local marketData = itemType.getMarketData and itemType:getMarketData() or {}

        local category = marketData and marketData.category or nil
        if not weaponCategories[category] then
            category = getUnknownMarketCategory(itemType)
        end

        if self.itemList[category] and (useProficiencyThings or weaponCategories[category]) then
            local originalId = itemType:getId()
            local showAs = marketData and marketData.showAs or nil
            if not showAs or showAs == 0 then
                showAs = originalId
            end

            local name = marketData and marketData.name or nil
            if (not name or name == "") and g_things.getCyclopediaItemName then
                name = g_things.getCyclopediaItemName(originalId)
            end
            if not name or name == "" then
                name = itemType.getName and itemType:getName() or tostring(originalId)
            end

            local item = Item.create(originalId)
            item:setId(showAs)

            marketData = marketData or {}
            marketData.category = category
            marketData.showAs = showAs
            marketData.name = name

            local marketItem = {
                displayItem = item,
                thingType = itemType,
                marketData = marketData,
                originalId = originalId,
                displayId = showAs
            }

            table.insert(self.itemList[category], marketItem)
            table.insert(self.itemList[MarketCategory.WeaponsAll], marketItem)
            self.catalogItems[originalId] = true
        end
    end

    -- Sort by name initially
    local function sortByName(a, b)
        local nameA = (a.marketData.name or ""):lower()
        local nameB = (b.marketData.name or ""):lower()
        return nameA < nameB
    end

    for _, v in pairs(self.itemList) do
        table.sort(v, sortByName)
    end

    if not self.firstItemRequested and self.itemList[MarketCategory.WeaponsAll][1] then
        self.firstItemRequested = self.itemList[MarketCategory.WeaponsAll][1].displayItem
    end

    self._itemCacheReady = true
end

function WeaponProficiency:addCatalogItem(itemId, category, name, proficiencyId)
    if not self._itemCacheReady then
        self:createItemCache()
    end
    if self.catalogItems[itemId] then
        return
    end

    category = tonumber(category) or MarketCategory.WeaponsAll
    if not self.itemList[category] then
        category = MarketCategory.WeaponsAll
    end

    local item = Item.create(itemId)
    if not item then
        return
    end

    local marketItem = {
        displayItem = item,
        thingType = g_things.getThingType(itemId, ThingCategoryItem),
        marketData = {
            category = category,
            showAs = itemId,
            name = name or tostring(itemId),
            proficiencyId = tonumber(proficiencyId) or 0
        },
        originalId = itemId,
        displayId = itemId
    }

    if category ~= MarketCategory.WeaponsAll then
        table.insert(self.itemList[category], marketItem)
    end
    table.insert(self.itemList[MarketCategory.WeaponsAll], marketItem)
    self.catalogItems[itemId] = true

    if not self.firstItemRequested then
        self.firstItemRequested = item
    end
end

-- Sort weapons by experience (highest first), then by name
function sortWeaponProficiency(marketCategory)
    if not WeaponProficiency.itemList then
        return
    end

    local itemList = WeaponProficiency.itemList[marketCategory]
    if not itemList then
        return
    end

    table.sort(itemList, function(a, b)
        local idA = a.originalId or a.displayId or (a.marketData and a.marketData.showAs)
        local idB = b.originalId or b.displayId or (b.marketData and b.marketData.showAs)

        local expA = WeaponProficiency.cacheList[idA] and WeaponProficiency.cacheList[idA].exp or 0
        local expB = WeaponProficiency.cacheList[idB] and WeaponProficiency.cacheList[idB].exp or 0

        if expA == expB then
            local nameA = (a.marketData.name or ""):lower()
            local nameB = (b.marketData.name or ""):lower()
            return nameA < nameB
        end
        return expA > expB
    end)
end

function WeaponProficiency:findMarketItem(itemId)
    local allItems = self.itemList[MarketCategory.WeaponsAll] or {}
    for _, marketItem in ipairs(allItems) do
        local originalId = marketItem.originalId
        local displayId = marketItem.displayId
        local showAs = marketItem.marketData and marketItem.marketData.showAs
        if itemId == originalId or itemId == displayId or itemId == showAs then
            return marketItem
        end
    end
    return nil
end

-- Check if mastery is achieved for an item
function isMasteryAchieved(displayItem, cacheId, thingType, marketData)
    if not displayItem then
        return false
    end

    local itemId = cacheId or displayItem:getId()
    local weaponEntry = WeaponProficiency.cacheList[itemId]
    local currentExperience = weaponEntry and weaponEntry.exp or 0

    -- Get proficiency data
    local tt = thingType
    if not tt and displayItem.getThingType then
        tt = displayItem:getThingType()
    end
    if not tt then
        tt = g_things.getThingType(displayItem:getId(), ThingCategoryItem)
    end
    local proficiencyId = ProficiencyData:getProficiencyIdForItem(displayItem, tt, marketData)
    local perkCount = ProficiencyData:getPerkLaneCount(proficiencyId)
    local maxExperience = ProficiencyData:getMaxExperience(perkCount, displayItem, tt, marketData)

    return currentExperience >= maxExperience
end

-- Get unknown market category for item
function getUnknownMarketCategory(itemType)
    local weaponType = getNumericCall(itemType, "getWeaponType")
    if WeaponCategoryToString[weaponType] then
        return weaponType
    end
    return UnknownCategories[weaponType] or MarketCategory.WeaponsAll
end

-- Update selected proficiency display
function WeaponProficiency:onUpdateSelectedProficiency(itemId)
    if not self.displayItemPanel then
        return
    end

    if not proficiencyItemsMatch(self.selectedItemId, itemId) then
        return
    end

    -- Get display item from selected market item
    local displayItem = self.selectedMarketItem and self.selectedMarketItem.displayItem
    if not displayItem then
        return
    end

    local currentData = getWeaponProficiencyCache(itemId) or {
        exp = 0,
        perks = {}
    }
    self:updateExperienceProgress(currentData.exp, displayItem)
end

-- Update experience progress display
function WeaponProficiency:updateExperienceProgress(currentExp, displayItem)
    if not self.window then
        return
    end
    if not displayItem then
        return
    end

    local experienceWidget = self.window:recursiveGetChildById("progressDescription")
    local experienceLeftWidget = self.window:recursiveGetChildById("nextLevelDescription")
    local totalProgressWidget = self.window:recursiveGetChildById("proficiencyProgress")

    if not experienceWidget or not experienceLeftWidget then
        return
    end

    local thingType = self.selectedMarketItem and self.selectedMarketItem.thingType
    local marketData = self.selectedMarketItem and self.selectedMarketItem.marketData
    local proficiencyId = ProficiencyData:getProficiencyIdForItem(displayItem, thingType, marketData)
    local perkCount = ProficiencyData:getPerkLaneCount(proficiencyId)
    local currentCeilExperience = ProficiencyData:getCurrentCeilExperience(currentExp, displayItem, thingType,
        marketData)
    local maxExperience = ProficiencyData:getMaxExperience(perkCount, displayItem, thingType, marketData)
    local masteryAchieved = currentExp >= maxExperience

    experienceWidget:setText(string.format("%s / %s", comma_value(currentExp), comma_value(currentCeilExperience)))

    if masteryAchieved then
        experienceLeftWidget:setText("Mastery achieved")
    else
        experienceLeftWidget:setText(string.format("%s XP for next level",
            comma_value(currentCeilExperience - currentExp)))
    end

    if totalProgressWidget then
        totalProgressWidget:setPercent(ProficiencyData:getTotalPercent(currentExp, perkCount, displayItem, thingType,
            marketData))
    end
end

-- Toggle filter option (Level, Voc, 1H, 2H buttons)
function WeaponProficiency:toggleFilterOption(button)
    if not button then
        return
    end

    local buttonId = button:getId()

    if buttonId == "oneButton" and self.filters["twoButton"] then
        self.filters["twoButton"] = false
        local twoButton = self.window and self.window:recursiveGetChildById("twoButton")
        if twoButton then
            twoButton:setOn(false)
        end
    elseif buttonId == "twoButton" and self.filters["oneButton"] then
        self.filters["oneButton"] = false
        local oneButton = self.window and self.window:recursiveGetChildById("oneButton")
        if oneButton then
            oneButton:setOn(false)
        end
    end

    self.filters[buttonId] = not self.filters[buttonId]

    -- Update button visual state
    if self.filters[buttonId] then
        button:setOn(true)
    else
        button:setOn(false)
    end

    -- Refresh item list with new filters
    self:refreshItemList()
end

-- Refresh item list based on current filters and category
function WeaponProficiency:refreshItemList(preserveScroll)
    if not self.window then
        return
    end

    local itemList = self.window:recursiveGetChildById('itemList')
    if not itemList then
        return
    end

    if self.itemListRenderEvent then
        removeEvent(self.itemListRenderEvent)
        self.itemListRenderEvent = nil
    end
    self._itemListRenderGeneration = (self._itemListRenderGeneration or 0) + 1
    local renderGeneration = self._itemListRenderGeneration

    local scrollValue = self.itemListScroll and self.itemListScroll:getValue() or 0

    -- Get current category from dropdown
    local categoryDropdown = self.window:recursiveGetChildById('classFilter')
    local currentCategory = MarketCategory.WeaponsAll

    if categoryDropdown then
        local selectedText = categoryDropdown:getText()
        currentCategory = WeaponStringToCategory[selectedText] or MarketCategory.WeaponsAll
    end

    -- Sort items by experience (highest first)
    sortWeaponProficiency(currentCategory)

    -- Get items for current category
    local items = self.itemList[currentCategory] or {}

    -- Apply filters
    items = self:applyLevelFilter(items)
    items = self:applyVocationFilter(items)

    -- Apply 1H/2H filters
    local oneActive = self.filters["oneButton"]
    local twoActive = self.filters["twoButton"]

    if oneActive and not twoActive then
        -- Only show one-handed weapons
        local filteredItems = {}
        for _, item in ipairs(items) do
            local thingType = item.thingType
            if thingType then
                local slotType = thingType.getClothSlot and thingType:getClothSlot() or 0
                if slotType == 6 then
                    table.insert(filteredItems, item)
                end
            else
                table.insert(filteredItems, item)
            end
        end
        items = filteredItems
    elseif twoActive and not oneActive then
        -- Only show two-handed weapons
        local filteredItems = {}
        for _, item in ipairs(items) do
            local thingType = item.thingType
            if thingType then
                local slotType = thingType.getClothSlot and thingType:getClothSlot() or 0
                if slotType == 0 then
                    table.insert(filteredItems, item)
                end
            end
        end
        items = filteredItems
    end
    -- If both active or neither, show all

    -- Apply search text filter
    if self.searchFilter and self.searchFilter ~= '' then
        local searchLower = string.lower(self.searchFilter)
        local filteredItems = {}
        for _, item in ipairs(items) do
            local itemName = item.marketData and item.marketData.name or ""
            if string.find(string.lower(itemName), searchLower, 1, true) then
                table.insert(filteredItems, item)
            end
        end
        items = filteredItems
    end

    itemList:destroyChildren()

    -- Create widgets in small batches so a large weapon catalog doesn't block
    -- the interface while the window opens or the filters change.
    local index = 1
    local batchSize = 24
    local function renderBatch()
        self.itemListRenderEvent = nil
        if renderGeneration ~= self._itemListRenderGeneration or not self.window or
            not self.window:isVisible() then
            return
        end

        local lastIndex = math.min(index + batchSize - 1, #items)
        for itemIndex = index, lastIndex do
            local marketItem = items[itemIndex]
            local child = g_ui.createWidget("ItemBox", itemList, "widget_" .. index)
            local itemWidget = child and child:getChildById('item')
            if itemWidget and marketItem.displayItem then
                -- Use stored displayId (guaranteed non-zero) instead of displayItem:getId()
                local displayId = marketItem.displayId or marketItem.originalId
                local cacheId = marketItem.originalId or displayId
                itemWidget:setItemId(displayId)
                if ItemsDatabase and ItemsDatabase.setRarityItem then
                    ItemsDatabase.setRarityItem(itemWidget, itemWidget:getItem())
                end
                -- Add tooltip with item name
                child:setTooltip(marketItem.marketData.name or "")

                -- Add stars based on proficiency level
                local starPanel = child:getChildById('starsBackground')
                if starPanel then
                    starPanel:destroyChildren()

                    -- Get experience and calculate level
                    local cacheEntry = self.cacheList[cacheId]
                    local exp = cacheEntry and cacheEntry.exp or 0
                    local weaponLevel = ProficiencyData:getCurrentLevelByExp(marketItem.displayItem, exp, false,
                        marketItem.thingType, marketItem.marketData) or 0

                    -- Create star widgets for each level achieved
                    if weaponLevel > 0 then
                        local mastery = isMasteryAchieved(marketItem.displayItem, cacheId, marketItem.thingType,
                            marketItem.marketData)
                        for i = 1, weaponLevel do
                            local star = g_ui.createWidget("MiniStar", starPanel)
                            if star and mastery then
                                star:setImageSource(proficiencyImage("icon-star-tiny-gold"))
                            end
                        end
                    end
                end

                -- Add click handler
                child.onClick = function()
                    WeaponProficiency:selectItem(displayId, marketItem)
                end
            end

            index = index + 1
        end

        if index <= #items then
            self.itemListRenderEvent = scheduleEvent(renderBatch, 1)
        end
    end

    renderBatch()

    if self.itemListScroll then
        if preserveScroll then
            self.itemListScroll:setValue(scrollValue)
        else
            self.itemListScroll:setValue(0)
        end
    end
end

-- Lightweight function to update only the star indicators on already-rendered items
-- This avoids the expensive destroy-and-recreate cycle of refreshItemList
function WeaponProficiency:updateVisibleItemStars()
    if not self.window then
        return
    end

    local itemList = self.window:recursiveGetChildById('itemList')
    if not itemList then
        return
    end

    local children = itemList:getChildren()
    if not children then
        return
    end

    for _, child in ipairs(children) do
        local itemWidget = child:getChildById('item')
        if itemWidget then
            local item = itemWidget:getItem()
            local displayId = item and item:getId() or 0
            if displayId > 0 then
                -- Find the marketItem for this displayId
                local cacheId = nil
                local allItems = self.itemList[MarketCategory.WeaponsAll] or {}
                local marketItem = nil
                for _, mi in ipairs(allItems) do
                    if (mi.displayId or mi.originalId) == displayId then
                        marketItem = mi
                        cacheId = mi.originalId or displayId
                        break
                    end
                end

                if cacheId then
                    local starPanel = child:getChildById('starsBackground')
                    if starPanel then
                        starPanel:destroyChildren()

                        local cacheEntry = self.cacheList[cacheId]
                        local exp = cacheEntry and cacheEntry.exp or 0
                        local weaponLevel = 0
                        if marketItem then
                            weaponLevel = ProficiencyData:getCurrentLevelByExp(
                                marketItem.displayItem, exp, false,
                                marketItem.thingType, marketItem.marketData) or 0
                        end

                        if weaponLevel > 0 then
                            local mastery = isMasteryAchieved(
                                marketItem.displayItem, cacheId,
                                marketItem.thingType, marketItem.marketData)
                            for i = 1, weaponLevel do
                                local star = g_ui.createWidget("MiniStar", starPanel)
                                if star and mastery then
                                    star:setImageSource(proficiencyImage("icon-star-tiny-gold"))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Handle category change from dropdown
function WeaponProficiency:onCategoryChange(dropdown)
    self:refreshItemList()
end

-- Select an item from the list
function WeaponProficiency:selectItem(itemId, marketItem)
    if not self.window then
        return
    end

    -- Use originalId for cache lookups (server uses this ID)
    local cacheId = marketItem.originalId or itemId
    self.selectedModifySlot = nil

    self.selectedItemId = cacheId -- Use cacheId for proficiency data lookup
    self.selectedDisplayId = itemId -- Keep display ID for UI
    self.selectedMarketItem = marketItem

    -- Get the item panel
    local itemPanel = self.window:recursiveGetChildById('itemPanel')
    if not itemPanel then
        return
    end

    -- Update item display panel
    local itemNameLabel = itemPanel:getChildById('itemNameTitle')
    local itemIconWidget = itemPanel:recursiveGetChildById('item')
    local displayItem = marketItem.displayItem

    -- Ensure displayItem has a valid ID (fix for items where showAs was 0)
    local actualDisplayId = marketItem.displayId or marketItem.originalId
    if displayItem and displayItem:getId() == 0 and actualDisplayId > 0 then
        displayItem:setId(actualDisplayId)
    end

    if itemNameLabel and marketItem then
        itemNameLabel:setText(marketItem.marketData.name or "Unknown Item")
    end

    -- Set item using setItem method
    if itemIconWidget and displayItem then
        itemIconWidget:setItem(displayItem)
    end

    -- Destroy and recreate perk panels for fresh display
    if self.perkPanel then
        self.perkPanel:destroyChildren()
    end
    if self.bonusDetailPanel then
        self.bonusDetailPanel:destroyChildren()
    end
    if self.starProgressPanel then
        self.starProgressPanel:destroyChildren()
    end

    -- Initialize cache entry if not exists
    if not self.cacheList[cacheId] then
        self.cacheList[cacheId] = {
            exp = 0,
            perks = {}
        }
    end

    local currentData = self.cacheList[cacheId]
    local thingType = marketItem.thingType
    local marketData = marketItem.marketData

    local vocationDecision = getVocationWarningDecision(marketData, thingType)
    if self.vocationWarning then
        self.vocationWarning:setVisible(vocationDecision.showWarning)
    end

    -- Get proficiency ID using wrapper function, passing thingType and marketData for proper category lookup
    local proficiencyId = ProficiencyData:getProficiencyIdForItem(displayItem, thingType, marketData)
    local profEntry = ProficiencyData:getContentById(proficiencyId)

    if profEntry then
        -- Update experience display
        self:updateExperienceProgress(currentData.exp, displayItem)

        -- Create star widgets
        for i = 1, #profEntry.Levels do
            local starWidget = g_ui.createWidget('StarWidget', self.starProgressPanel)
            if starWidget then
                starWidget:setId('starWidget' .. i)
            end
        end

        -- Create perk column panels
        for i, levelData in ipairs(profEntry.Levels) do
            local perkColumn = g_ui.createWidget('BonusSelectPanel', self.perkPanel)
            if perkColumn then
                perkColumn:setId('perkColumn_' .. i)
                local progress = perkColumn:getChildById('bonusSelectProgress')
                if progress then
                    progress:setPercent(0)
                end
            end

            local bonusDetail = g_ui.createWidget('BonusDetailPanel', self.bonusDetailPanel)
            if bonusDetail then
                bonusDetail:setId('bonusDetail_' .. i)
            end
        end

        -- Load saved perks into pendingSelections for UI display
        self.pendingSelections = {}
        if currentData.perks and #currentData.perks > 0 then
            for i, perk in ipairs(currentData.perks) do
                if type(perk) == "table" and #perk >= 2 then
                    local level = perk[1]
                    local perkPos = perk[2]
                    self.pendingSelections[level] = perkPos
                end
            end
        end

        -- Display perks and update UI
        self:displayPerks(cacheId, currentData.perks, displayItem)
    else
        -- Fallback: show basic info without perks
        self:updateExperienceProgress(currentData.exp, displayItem)
    end

    -- Request proficiency info from server (protocol expects client item id)
    sendWeaponProficiencyAction(0, getProtocolItemId(marketItem, cacheId))
    self:updateModifyButtonState()
    self:updateModifyCost()
end

-- Display proficiency data for selected item
function WeaponProficiency:displayProficiencyData(itemId, experience, perks)
    if not self.window then
        return
    end
    if not proficiencyItemsMatch(self.selectedItemId, itemId) then
        return
    end

    local displayItem = self.selectedMarketItem and self.selectedMarketItem.displayItem
    local thingType = self.selectedMarketItem and self.selectedMarketItem.thingType
    if not displayItem then
        return
    end

    -- Update experience display
    self:updateExperienceProgress(experience, displayItem)

    -- Get proficiency content using wrapper function (with thingType and marketData)
    local marketData = self.selectedMarketItem and self.selectedMarketItem.marketData
    local proficiencyId = ProficiencyData:getProficiencyIdForItem(displayItem, thingType, marketData)
    local profEntry = ProficiencyData:getContentById(proficiencyId)

    if not profEntry then
        return
    end

    local levels = profEntry.Levels or {}
    local currentLevel = ProficiencyData:getCurrentLevelByExp(displayItem, experience, false, thingType, marketData)
    local maxExperience = ProficiencyData:getMaxExperience(#levels, displayItem, thingType, marketData)
    local masteryAchieved = experience >= maxExperience

    -- Update perk columns for each level
    for i, levelData in ipairs(levels) do
        local perkColumn = self.perkPanel:getChildById('perkColumn_' .. i)
        local starWidget = self.starProgressPanel:getChildById('starWidget' .. i)

        if perkColumn then
            self:updatePerkColumn(perkColumn, levelData, i, currentLevel, perks, experience, displayItem,
                masteryAchieved, thingType, marketData)
        end

        if starWidget then
            self:updateStarWidget(starWidget, i, currentLevel, experience, displayItem, masteryAchieved, thingType,
                marketData)
        end
    end

    -- Update bonus detail panels
    self:updateBonusDetails(profEntry, perks)

    -- Update item frame
    self:updateItemAddons(experience, displayItem, masteryAchieved, thingType, marketData)
    self:updateModifyButtonState()
    self:updateModifyCost()
end

-- Display perks in the perk panel
function WeaponProficiency:displayPerks(itemId, perks, displayItem)
    if not self.window or not self.perkPanel then
        return
    end

    if not displayItem then
        return
    end

    -- Get proficiency content using wrapper function (with thingType and marketData for proper category lookup)
    local thingType = self.selectedMarketItem and self.selectedMarketItem.thingType
    local marketData = self.selectedMarketItem and self.selectedMarketItem.marketData
    local proficiencyId = ProficiencyData:getProficiencyIdForItem(displayItem, thingType, marketData)
    local proficiencyContent = ProficiencyData:getContentById(proficiencyId)

    if not proficiencyContent then
        return
    end

    -- Use cacheId (originalId) for cache lookups
    local cacheId = self.selectedMarketItem and self.selectedMarketItem.originalId or itemId

    local levels = proficiencyContent.Levels or {}
    local experience = self.cacheList[cacheId] and self.cacheList[cacheId].exp or 0

    -- Calculate current level based on experience (starts at 0 if no experience)
    local currentLevel = ProficiencyData:getCurrentLevelByExp(displayItem, experience, false, thingType, marketData)

    -- Check if mastery is achieved
    local maxExperience = ProficiencyData:getMaxExperience(#levels, displayItem, thingType, marketData)
    local masteryAchieved = experience >= maxExperience

    -- Update perk columns for each level
    for i, levelData in ipairs(levels) do
        local perkColumn = self.perkPanel:getChildById('perkColumn_' .. i)
        local starWidget = self.starProgressPanel:getChildById('starWidget' .. i)

        if perkColumn and levelData then
            self:updatePerkColumn(perkColumn, levelData, i, currentLevel, perks, experience, displayItem,
                masteryAchieved, thingType, marketData)
        end

        -- Update star widget
        if starWidget then
            self:updateStarWidget(starWidget, i, currentLevel, experience, displayItem, masteryAchieved, thingType,
                marketData)
        end
    end

    -- Update bonus detail panels
    self:updateBonusDetails(proficiencyContent, perks)

    -- Update item frame/addons based on level
    self:updateItemAddons(experience, displayItem, masteryAchieved, thingType, marketData)
end

-- Update a single star widget - matching RTC implementation
function WeaponProficiency:updateStarWidget(starWidget, levelIndex, currentLevel, experience, displayItem,
    masteryAchieved, thingType, marketData)
    if not starWidget then
        return
    end

    local starProgress = starWidget:getChildById('starProgress')
    local starIcon = starWidget:getChildById('star')

    if starProgress then
        -- Calculate percent for this level (same as perk column)
        local percent = ProficiencyData:getLevelPercent(experience or 0, levelIndex, displayItem, thingType, marketData)
        starProgress:setPercent(percent)

        -- Set tooltip with experience info
        local maxLevelExp = ProficiencyData:getMaxExperienceByLevel(levelIndex, displayItem, thingType, marketData)
        starProgress:setTooltip(string.format("%s / %s", comma_value(experience or 0), comma_value(maxLevelExp or 0)))
    end

    -- Update star icon color based on completion (100% = complete)
    if starIcon then
        local percent = ProficiencyData:getLevelPercent(experience or 0, levelIndex, displayItem, thingType, marketData)
        if percent >= 100 then
            -- Level complete - show gold or silver star
            local iconType = masteryAchieved and "gold" or "silver"
            starIcon:setImageSource(proficiencyImage('icon-star-tiny-' .. iconType))
        else
            -- Level not complete - show dark star
            starIcon:setImageSource(proficiencyImage('icon-star-dark'))
        end
    end
end

-- Update item frame/addons based on weapon level
function WeaponProficiency:updateItemAddons(currentExp, displayItem, masteryAchieved, thingType, marketData)
    if not self.window then
        return
    end
    if not displayItem then
        return
    end

    local weaponLevel = math.min(7, ProficiencyData:getCurrentLevelByExp(displayItem, currentExp, false, thingType,
        marketData) or 0)
    local iconLevelWidget = self.window:recursiveGetChildById("iconMasteryLevel")
    local weaponLevelWidget = self.window:recursiveGetChildById("itemMasteryLevel")

    if iconLevelWidget then
        iconLevelWidget:setImageSource(proficiencyImage("icon-masterylevel-" .. weaponLevel))
    end

    if weaponLevelWidget then
        weaponLevelWidget:setVisible(weaponLevel > 0)
        if weaponLevel > 0 then
            local color = masteryAchieved and "gold" or "silver"
            weaponLevelWidget:setImageSource(proficiencyImage(
                string.format("icon-masterylevel-%d-%s", weaponLevel, color)))
        end
    end
end

-- Update a single perk column
local function findCachedModifier(cacheOrItemId, grade, slot)
    local cache = cacheOrItemId
    if type(cacheOrItemId) ~= 'table' then
        cache = getWeaponProficiencyCache(cacheOrItemId)
    end
    for _, modifier in ipairs((cache and cache.modifiers) or {}) do
        if modifier.grade == grade and modifier.slot == slot then
            return modifier
        end
    end
    return nil
end

local function getSelectedPerkIndexForLevel(self, levelIndex)
    if self.pendingSelections and self.pendingSelections[levelIndex] ~= nil then
        return self.pendingSelections[levelIndex]
    end
    local cache = self.selectedItemId and getWeaponProficiencyCache(self.selectedItemId)
    if not cache then
        return nil
    end
    for _, perk in ipairs(cache.perks or {}) do
        if type(perk) == 'table' and perk[1] == levelIndex then
            return perk[2]
        end
    end
    return nil
end

local function getDisplayPerkDataForLevelSlot(self, levelIndex, perkIndex, basePerkData)
    if not basePerkData then
        return nil
    end
    local modifier = findCachedModifier(self.selectedItemId, levelIndex, perkIndex)
    if modifier then
        return ProficiencyData:getModifierPerkData(modifier.modifierEnum, modifier.refineLevel) or basePerkData
    end
    return basePerkData
end

local function updateManipulateRankWidget(bonusIcon, modifier, active)
    local rankWidget = bonusIcon and bonusIcon:getChildById('manipulateRank')
    if not rankWidget then
        return
    end
    if not modifier then
        rankWidget:setVisible(false)
        return
    end

    rankWidget:setVisible(true)
    rankWidget:setImageSource(proficiencyImage(active and 'backdrop_manipulation_rank' or
        'backdrop_manipulation_rank_disabled'))
    local rankValue = rankWidget:getChildById('rankValue')
    if rankValue then
        rankValue:setText(tostring(modifier.refineLevel or 0))
    end
end

-- Active tree border asset is optional in this client; shaped perks keep the default frame.
local function setPerkTreeBorderImage(borderWidget, isSelected, isLevelUnlocked, hasModifier)
    if not borderWidget then
        return
    end
    local useActiveBorder = isSelected and isLevelUnlocked and not hasModifier
    borderWidget:setImageSource(proficiencyImage(useActiveBorder and 'border-weaponmasterytreeicons-active' or
        'border-weaponmasterytreeicons-inactive'))
end

local function applyBonusIconPerkVisual(bonusIcon, perkData)
    if not bonusIcon or not perkData then
        return
    end

    local imagePath, imageClip = ProficiencyData:getImageSourceAndClip(perkData)
    local iconWidget = bonusIcon:getChildById('icon')
    local iconGreyWidget = bonusIcon:getChildById('icon-grey')
    local clipX, clipY = imageClip:match("(%d+)%s+(%d+)")
    clipX = tonumber(clipX) or 0
    clipY = tonumber(clipY) or 0

    if iconWidget then
        iconWidget:setImageSource(imagePath)
        iconWidget:setImageClip({x = clipX, y = clipY, width = 64, height = 64})
    end

    if iconGreyWidget then
        if perkData.Type == PERK_SPELL_AUGMENT then
            iconGreyWidget:setImageSource(imagePath .. "-off")
            iconGreyWidget:setImageClip({x = clipX, y = clipY, width = 64, height = 64})
        else
            iconGreyWidget:setImageSource(imagePath)
            iconGreyWidget:setImageClip({x = clipX, y = clipY + 64, width = 64, height = 64})
        end
    end

    local iconPerks = bonusIcon:getChildById('iconPerks')
    local iconPerksGrey = bonusIcon:getChildById('iconPerks-grey')
    if perkData.Type == PERK_SPELL_AUGMENT and perkData.AugmentType then
        local augmentClip = ProficiencyData:getAugmentIconClip(perkData)
        local augX = tonumber(augmentClip:match("(%d+)")) or 0
        if iconPerks then
            iconPerks:setVisible(true)
            iconPerks:setImageClip({x = augX, y = 0, width = 32, height = 32})
        end
        if iconPerksGrey then
            iconPerksGrey:setVisible(true)
            iconPerksGrey:setImageClip({x = augX, y = 32, width = 32, height = 32})
        end
    else
        if iconPerks then iconPerks:setVisible(false) end
        if iconPerksGrey then iconPerksGrey:setVisible(false) end
    end
end

function WeaponProficiency:updatePerkColumn(perkColumn, levelData, levelIndex, currentLevel, selectedPerks, experience,
    displayItem, masteryAchieved, thingType, marketData)
    if not perkColumn or not levelData then
        return
    end

    local perksData = levelData.Perks or {}
    local perkCount = #perksData

    -- Show appropriate panel based on perk count
    local oneBonusPanel = perkColumn:getChildById('oneBonusIconPanel')
    local twoBonusPanel = perkColumn:getChildById('twoBonusIconPanel')
    local threeBonusPanel = perkColumn:getChildById('threeBonusIconPanel')

    if oneBonusPanel then
        oneBonusPanel:setVisible(perkCount == 1)
    end
    if twoBonusPanel then
        twoBonusPanel:setVisible(perkCount == 2)
    end
    if threeBonusPanel then
        threeBonusPanel:setVisible(perkCount == 3)
    end

    -- Determine which panel to use
    local activePanel = nil
    if perkCount == 1 and oneBonusPanel then
        activePanel = oneBonusPanel
    elseif perkCount == 2 and twoBonusPanel then
        activePanel = twoBonusPanel
    elseif perkCount == 3 and threeBonusPanel then
        activePanel = threeBonusPanel
    end

    if not activePanel then
        return
    end

    -- Store currentPerkPanel reference for later use
    perkColumn.currentPerkPanel = activePanel

    -- Level is unlocked if we have enough experience
    local isLevelUnlocked = levelIndex <= currentLevel

    -- Update progress bar for this column.
    local progressBar = perkColumn:getChildById('bonusSelectProgress')
    if progressBar then
        local percent = ProficiencyData:getLevelPercent(experience or 0, levelIndex, displayItem, thingType, marketData)
        progressBar:setPercent(percent)

        -- Unlock perks if this level is complete (100%)
        if percent >= 100 then
            for _, widget in pairs(activePanel:getChildren()) do
                if widget.blocked then
                    widget.blocked = false
                end
            end
        end
    end

    -- Update each perk icon
    for perkIndex, perkData in ipairs(perksData) do
        local bonusIcon = activePanel:getChildById('bonusIcon' .. (perkIndex - 1))
        if bonusIcon then
            local iconWidget = bonusIcon:getChildById('icon')
            local iconGreyWidget = bonusIcon:getChildById('icon-grey')
            local lockedWidget = bonusIcon:getChildById('locked-perk')
            local borderWidget = bonusIcon:getChildById('border')
            local highlightWidget = bonusIcon:getChildById('highlight')
            -- Check if this perk is selected
            local isSelected = false
            if selectedPerks and type(selectedPerks) == "table" then
                -- Format 1: Array format from server/cache: {{level, perkPos}, ...} (1-indexed)
                if #selectedPerks > 0 and type(selectedPerks[1]) == "table" then
                    for _, perk in ipairs(selectedPerks) do
                        if type(perk) == "table" and #perk >= 2 and perk[1] == levelIndex and perk[2] == perkIndex then
                            isSelected = true
                            break
                        end
                    end
                    -- Format 2: Indexed format from pendingSelections: {[levelIndex] = perkIndex} (1-indexed)
                elseif selectedPerks[levelIndex] ~= nil then
                    isSelected = (selectedPerks[levelIndex] == perkIndex)
                end
            end

            local originalPerkData = perkData
            local modifier = findCachedModifier(self.selectedItemId, levelIndex, perkIndex)
            local displayPerkData = perkData
            if modifier then
                displayPerkData = ProficiencyData:getModifierPerkData(modifier.modifierEnum, modifier.refineLevel) or perkData
            end
            local isPerkActive = isSelected and isLevelUnlocked
            applyBonusIconPerkVisual(bonusIcon, displayPerkData)

            -- Show/hide based on unlock state and selection
            local showColorIcon = isPerkActive
            local showGreyIcon = not isLevelUnlocked or (isLevelUnlocked and not isSelected)

            if iconWidget then
                iconWidget:setVisible(showColorIcon)
            end

            if iconGreyWidget then
                iconGreyWidget:setVisible(showGreyIcon)
                iconGreyWidget:setOpacity(1.0)
            end

            if displayPerkData.Type == PERK_SPELL_AUGMENT then
                local iconPerks = bonusIcon:getChildById('iconPerks')
                local iconPerksGrey = bonusIcon:getChildById('iconPerks-grey')
                if iconPerks then
                    iconPerks:setVisible(showColorIcon)
                end
                if iconPerksGrey then
                    iconPerksGrey:setVisible(showGreyIcon)
                    iconPerksGrey:setOpacity(1.0)
                end
            end

            -- Show locked icon if level not reached
            if lockedWidget then
                lockedWidget:setVisible(not isLevelUnlocked)
            end

            setPerkTreeBorderImage(borderWidget, isSelected, isLevelUnlocked, modifier ~= nil)

            -- Highlight selected perk
            if highlightWidget then
                highlightWidget:setVisible(isPerkActive)
                highlightWidget:setImageSource(proficiencyImage(modifier and 'backdrop_weaponmastery_manipulate_highlight' or 'backdrop_weaponmastery_highlight'))
            end

            local selectedWidget = bonusIcon:getChildById('selected')
            if selectedWidget then
                selectedWidget:setVisible(isPerkActive)
            end
            updateManipulateRankWidget(bonusIcon, modifier, isPerkActive)

            -- Set tooltip
            local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(displayPerkData)
            bonusIcon:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))

            -- Store base perk data for later visual updates (shape / selection)
            bonusIcon.perkData = originalPerkData
            bonusIcon.originalPerkData = originalPerkData
            bonusIcon.blocked = not isLevelUnlocked
            bonusIcon.locked = false
            bonusIcon.active = isSelected
            bonusIcon.levelIndex = levelIndex
            bonusIcon.perkIndex = perkIndex

            -- Add click handler for selecting perk
            bonusIcon.onClick = function(widget)
                if widget.blocked then
                    return
                end
                WeaponProficiency:onPerkClick(widget)
            end
        end
    end
end

-- Handle perk icon click
function WeaponProficiency:onPerkClick(bonusIcon)
    if not bonusIcon then
        return
    end

    local levelIndex = bonusIcon.levelIndex
    local perkIndex = bonusIcon.perkIndex

    -- Initialize pending selections if not exists
    if not self.pendingSelections then
        self.pendingSelections = {}
    end

    -- Get currently saved perk for this level from cache
    local savedPerk = nil
    if self.selectedItemId and getWeaponProficiencyCache(self.selectedItemId) then
        local cachedPerks = getWeaponProficiencyCache(self.selectedItemId).perks or {}
        for _, perk in ipairs(cachedPerks) do
            if type(perk) == "table" and perk[1] == levelIndex then
                savedPerk = perk[2]
                break
            end
        end
    end

    -- Bind the shape button to the perk the player just clicked.
    self.selectedModifySlot = nil
    -- Shaping is only available for a perk already saved on the server.
    if savedPerk == perkIndex then
        self.selectedModifySlot = {grade = levelIndex, slot = perkIndex}
    end

    -- Determine if this click changes from saved state
    local currentSelection = self.pendingSelections[levelIndex] or savedPerk

    if currentSelection == perkIndex then
        -- Clicking on already selected perk - check if we should deselect or revert to saved
        if savedPerk == perkIndex then
            -- This is the saved perk, clicking it again does nothing (can't deselect saved perks)
        else
            -- This was a pending selection, deselect it (revert to saved or none)
            self.pendingSelections[levelIndex] = nil
        end
    else
        -- Selecting a different perk for this level
        if perkIndex == savedPerk then
            -- Reverting to saved perk - remove from pending
            self.pendingSelections[levelIndex] = nil
        else
            -- New selection different from saved
            self.pendingSelections[levelIndex] = perkIndex
        end
    end

    self:updateSelectedPerkVisuals()
    self:updateModifyButtonState()
    self:updateModifyCost()

    -- Update button states
    self:updateApplyButtonState()
end

function WeaponProficiency:updateModifyCost()
    local costText = self.modifyCostText
    if not costText then return end

    local cache = self.selectedItemId and getWeaponProficiencyCache(self.selectedItemId)
    local modifiers = cache and cache.modifiers or {}
    local cost = #modifiers >= 1 and 1000 or 250
    costText:setText(tostring(cost))

    local player = g_game.getLocalPlayer()
    local dust = player and player:getResourceBalance(ResourceTypes.WEAPON_PROFICIENCY_FORGE_DUST) or 0
    costText:setColor(dust < cost and '#d33c3c' or '#c0c0c0')
end

function WeaponProficiency:updateModifyButtonState()
    local button = self.modifyButton
    local costPanel = self.modifyCost
    if not button then return end

    local cache = self.selectedItemId and getWeaponProficiencyCache(self.selectedItemId)
    local modifiers = cache and cache.modifiers or {}
    local selected = self.selectedModifySlot
    local selectedModifier = nil
    if selected then
        for _, modifier in ipairs(modifiers) do
            if modifier.grade == selected.grade and modifier.slot == selected.slot then
                selectedModifier = modifier
                break
            end
        end
    end

    if selectedModifier then
        button:setStyle('ShapeButton')
        if costPanel then costPanel:setVisible(false) end
        button:setEnabled(type(g_game.sendWeaponProficiencySlotAction) == 'function')
        button:setTooltip('Shape selected weapon proficiency slot')
        return
    end

    if #modifiers >= 2 then
        button:setStyle('ModifyButtonLarge')
        button:setEnabled(false)
        button:setTooltip('Action not possible:\nOnly 2 perks can be modified.')
        if costPanel then costPanel:setVisible(false) end
        return
    end

    button:setStyle('ModifyButton')
    if costPanel then costPanel:setVisible(true) end
    local selectedApplied = false
    if selected and cache then
        for _, perk in ipairs(cache.perks or {}) do
            if perk[1] == selected.grade and perk[2] == selected.slot then
                selectedApplied = true
                break
            end
        end
    end

    local selectedIcon
    if selected and self.perkPanel then
        local column = self.perkPanel:getChildById('perkColumn_' .. selected.grade)
        selectedIcon = column and column.currentPerkPanel and column.currentPerkPanel:getChildById('bonusIcon' .. (selected.slot - 1))
    end
    local player = g_game.getLocalPlayer()
    local dust = player and player:getResourceBalance(ResourceTypes.WEAPON_PROFICIENCY_FORGE_DUST) or 0
    local cost = #modifiers >= 1 and 1000 or 250
    local enoughLevels = false
    if self.selectedMarketItem and cache then
        local item = self.selectedMarketItem
        local currentLevel = ProficiencyData:getCurrentLevelByExp(item.displayItem, cache.exp or 0, false, item.thingType, item.marketData) or 0
        enoughLevels = currentLevel >= 3
    end
    local canModify = selectedApplied == true and selectedIcon ~= nil and not selectedIcon.blocked and enoughLevels and dust >= cost
    button:setEnabled(canModify and type(g_game.sendWeaponProficiencySlotAction) == 'function')

    if not selectedApplied then
        button:setTooltip('Action not possible:\nSelect an applied perk.')
    elseif selectedIcon and selectedIcon.blocked then
        button:setTooltip('Action not possible:\nPerk is not unlocked.')
    elseif not enoughLevels then
        button:setTooltip('Action not possible:\nUnlock at least 3 proficiency levels.')
    elseif dust < cost then
        button:setTooltip('Action not possible:\nNot enough forge dust.')
    else
        button:setTooltip('Modify selected weapon proficiency perk')
    end
end

local function getModifiedSlot(cache, slot)
    for _, modifier in ipairs((cache and cache.modifiers) or {}) do
        if modifier.grade == slot.grade and modifier.slot == slot.slot then
            return modifier
        end
    end
    return nil
end

local function sendShapeAction(action, itemId, slot, offerIndex)
    if type(g_game.sendWeaponProficiencySlotAction) == 'function' then
        g_game.sendWeaponProficiencySlotAction(action, itemId, slot.grade - 1, slot.slot - 1, offerIndex or 0)
    end
end

local function destroyShapeWindowWidget(window)
    if not window or window:isDestroyed() then
        return
    end
    if g_modalManager then
        g_modalManager.hide(window)
    end
    window:destroy()
end

local function dismissShapeWindow(window)
    if not window then
        return
    end
    if WeaponProficiency.shapeWindow == window then
        WeaponProficiency.shapeWindow = nil
    end
    destroyShapeWindowWidget(window)
end

local function displayShapeBox(title, message, buttons)
    local box
    local function dismiss()
        dismissShapeWindow(box)
        box = nil
    end
    for _, button in ipairs(buttons) do
        local callback = button.callback
        button.callback = function()
            dismiss()
            if callback then callback() end
        end
    end
    box = displayGeneralBox(title, message, buttons, dismiss, dismiss)
    return box
end

local RESHAPE_PERK_TITLE_MAX_LEN = 29
local RESHAPE_PERK_TITLE_TRUNCATED_LEN = 26

local function formatPerkBonusTitle(name, maxLen, truncatedLen)
    name = name or ''
    maxLen = maxLen or RESHAPE_PERK_TITLE_MAX_LEN
    truncatedLen = truncatedLen or RESHAPE_PERK_TITLE_TRUNCATED_LEN
    if maxLen >= #name then
        return name, ''
    end
    return name:sub(1, truncatedLen) .. '...', name
end

local function populateShapePerkPreview(previewWidget, perkData, modifierEntry)
    if not previewWidget or not perkData then
        return
    end

    local icon = previewWidget:getChildById('icon')
    local borderWidget = previewWidget:getChildById('border')
    local augmentIcon = previewWidget:getChildById('iconPerks')

    if icon then
        local imagePath, imageClip = ProficiencyData:getImageSourceAndClip(perkData)
        local clipX, clipY = imageClip:match('(%d+)%s+(%d+)')
        clipX = tonumber(clipX) or 0
        clipY = tonumber(clipY) or 0
        icon:setImageSource(imagePath)
        icon:setImageClip({x = clipX, y = clipY, width = 64, height = 64})
    end

    if borderWidget then
        borderWidget:setImageSource(proficiencyImage('border-weaponmasterytreeicons-active'))
    end

    if augmentIcon then
        if perkData.Type == PERK_SPELL_AUGMENT and perkData.AugmentType then
            local augmentClip = ProficiencyData:getAugmentIconClip(perkData)
            local augX = tonumber(augmentClip:match('(%d+)')) or 0
            augmentIcon:setVisible(true)
            augmentIcon:setImageClip({x = augX, y = 0, width = 32, height = 32})
        else
            augmentIcon:setVisible(false)
        end
    end

    updateManipulateRankWidget(previewWidget, modifierEntry, true)
end

local function populateReshapePerkPanel(panel, modifierEnum, refineLevel)
    if not panel or not modifierEnum then
        return
    end

    local perkData = ProficiencyData:getModifierPerkData(modifierEnum, refineLevel)
    if not perkData then
        return
    end

    local modifierEntry = {
        modifierEnum = modifierEnum,
        refineLevel = refineLevel or 0
    }
    local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(perkData)
    local displayName, titleTooltip = formatPerkBonusTitle(bonusName)
    local panelTitle = panel:getChildById('panelTitle')
    if panelTitle then
        panelTitle:setText(displayName)
        panelTitle:setTooltip(titleTooltip)
    end

    local perkPreview = panel:getChildById('perkPreview')
    if perkPreview then
        populateShapePerkPreview(perkPreview, perkData, modifierEntry)
    end

    local perkBonusText = panel:recursiveGetChildById('perkBonusText')
    if perkBonusText then
        perkBonusText:setText(bonusTooltip or '')
    end
end

local function closeShapeMessageBox()
    dismissShapeWindow(WeaponProficiency.shapeWindow)
end

function WeaponProficiency:closeReshapeDialog()
    local dialog = self.shapeWindow
    if not dialog or dialog:isDestroyed() or dialog:getId() ~= 'reshapeDialog' then
        local root = g_ui.getRootWidget()
        dialog = root and root:recursiveGetChildById('reshapeDialog')
    end
    dismissShapeWindow(dialog)
    self.reshapeData = nil
end

function WeaponProficiency:confirmReshapeReplace(optionIndex)
    local data = self.reshapeData
    if not data then
        return
    end

    local slot = {grade = data.grade, slot = data.slot}
    sendShapeAction(8, data.itemId, slot, optionIndex)

    if optionIndex >= 0 and optionIndex <= 2 then
        local option = data.options[optionIndex + 1]
        if option then
            local cacheEntry = self.cacheList[data.itemId]
            if cacheEntry then
                local modifierEntry = findCachedModifier(cacheEntry, data.grade, data.slot)
                if modifierEntry then
                    modifierEntry.modifierEnum = option.modifierEnum
                    modifierEntry.refineLevel = option.refineLevel
                end
            end
        end
    end

    self.reshapeData = nil
    self:updateSelectedPerkVisuals()
end

function WeaponProficiency:openReshapeDialog()
    local data = self.reshapeData
    if not data then
        return
    end

    local root = g_ui.getRootWidget()
    if not root then
        return
    end

    closeShapeMessageBox()

    local existing = root:recursiveGetChildById('reshapeDialog')
    if existing and not existing:isDestroyed() then
        dismissShapeWindow(existing)
    end

    local dialog = g_ui.createWidget('ReshapeDialog', root)
    dialog:setId('reshapeDialog')

    local modifierEntry = findCachedModifier(self.cacheList[data.itemId], data.grade, data.slot)
    if modifierEntry then
        populateReshapePerkPanel(dialog:recursiveGetChildById('currentPerkPanel'), modifierEntry.modifierEnum,
            modifierEntry.refineLevel)
    end

    local optionIds = {'reshapeOption1', 'reshapeOption2', 'reshapeOption3'}
    local replaceIds = {'reshapeReplace1', 'reshapeReplace2', 'reshapeReplace3'}
    for i, optionId in ipairs(optionIds) do
        local optionPanel = dialog:recursiveGetChildById(optionId)
        local option = data.options[i]
        local replaceContainer = dialog:recursiveGetChildById(replaceIds[i])
        if optionPanel and option then
            populateReshapePerkPanel(optionPanel, option.modifierEnum, option.refineLevel)
            optionPanel:setVisible(true)
            if replaceContainer then
                replaceContainer:setVisible(true)
                local replaceButton = replaceContainer:recursiveGetChildById('replaceButton')
                if replaceButton then
                    replaceButton.onClick = function()
                        self:onReshapeOptionSelected(i - 1)
                    end
                end
            end
        else
            if optionPanel then
                optionPanel:setVisible(false)
            end
            if replaceContainer then
                replaceContainer:setVisible(false)
            end
        end
    end

    dialog:show()
    self.shapeWindow = dialog
    if g_modalManager then
        g_modalManager.show(dialog)
    end
end

function WeaponProficiency:onReshapeDialogKeyBlock()
    return
end

function WeaponProficiency:onReshapeKeepClicked()
    self:confirmReshapeReplace(3)
    self:closeReshapeDialog()
end

function WeaponProficiency:onReshapeOptionSelected(optionIndex)
    local data = self.reshapeData
    if not data then
        return
    end

    local option = data.options[optionIndex + 1]
    if not option then
        return
    end

    local modifierEntry = findCachedModifier(self.cacheList[data.itemId], data.grade, data.slot)
    local currentModifier = modifierEntry and modifierEntry.modifierEnum
    if currentModifier and currentModifier == option.modifierEnum then
        self:confirmReshapeReplace(optionIndex)
        self:closeReshapeDialog()
        return
    end

    self:confirmReshapeReplace(optionIndex)
    self:closeReshapeDialog()
end

function WeaponProficiency:openShapeMenu()
    local slot = self.selectedModifySlot
    local itemId = self.selectedItemId
    if not slot or not itemId then return end
    local cache = self.cacheList[itemId]
    local modifier = getModifiedSlot(cache, slot)
    if not modifier then
        local modifierCount = #(cache and cache.modifiers or {})
        local cost = modifierCount == 0 and 250 or 1000
        local confirm = displayShapeBox(tr('Modify perk'), tr('Spend %d forge dust to add a modifier to this perk?', cost), {{
            text = tr('Modify'), callback = function() sendShapeAction(4, itemId, slot) end
        }, {text = tr('Cancel'), callback = function() end}})
        self.shapeWindow = confirm
        return
    end

    local perkData = ProficiencyData:getModifierPerkData(modifier.modifierEnum, modifier.refineLevel)
    local name, tooltip = perkData and ProficiencyData:getBonusNameAndTooltip(perkData) or tr('Unknown modifier'), ''
    local text = string.format('%s\n%s\nRank %d / 10\n\nChoose an action. Maximise is currently disabled by the server.', name, tooltip, modifier.refineLevel or 0)
    local function openMoreActions()
        self.shapeWindow = displayShapeBox(tr('More shaping actions'), text, {
            {text = tr('Maximise'), callback = function() sendShapeAction(6, itemId, slot) end},
            {text = tr('Clear'), callback = function()
                self.shapeWindow = displayShapeBox(tr('Clear modifier'), tr('Remove the modifier from this perk?'), {
                    {text = tr('Clear'), callback = function() sendShapeAction(9, itemId, slot) end},
                    {text = tr('Cancel'), callback = function() end}
                })
            end},
            {text = tr('Back'), callback = function() self:openShapeMenu() end}
        })
    end

    self.shapeWindow = displayShapeBox(tr('Shape perk'), text, {
        {text = tr('Refine'), callback = function() sendShapeAction(5, itemId, slot) end},
        {text = tr('Reshape'), callback = function()
            self.shapeWindow = displayShapeBox(tr('Reshape perk'), tr('Spend 250 forge dust to generate three modifier options? The dust is consumed when you continue.'), {
                {text = tr('Reshape'), callback = function() sendShapeAction(7, itemId, slot) end},
                {text = tr('Cancel'), callback = function() end}
            })
        end},
        {text = tr('More'), callback = openMoreActions},
        {text = tr('Cancel'), callback = function() end}
    })
end

function WeaponProficiency:onModifyClick()
    self:updateModifyButtonState()
    if self.modifyButton and self.modifyButton:isEnabled() then
        self:openShapeMenu()
    end
end

function onWeaponProficiencyReshape(itemId, level, position, offers)
    level, position = tonumber(level), tonumber(position)
    itemId = tonumber(itemId)
    if not level or not position or not itemId then
        return
    end

    local options = {}
    for _, offer in ipairs(offers or {}) do
        local modifierEnum = tonumber(offer[1])
        if modifierEnum then
            options[#options + 1] = {
                modifierEnum = modifierEnum,
                refineLevel = tonumber(offer[2]) or 0
            }
        end
    end

    WeaponProficiency.reshapeData = {
        itemId = itemId,
        grade = level + 1,
        slot = position + 1,
        options = options
    }

    WeaponProficiency:openReshapeDialog()
end

-- Refresh perk selection / modify visuals for every proficiency level column
function WeaponProficiency:updateSelectedPerkVisuals()
    if not self.perkPanel then
        return
    end

    for _, child in ipairs(self.perkPanel:getChildren()) do
        local id = child:getId() or ''
        local levelIndex = tonumber(id:match('^perkColumn_(%d+)$'))
        if levelIndex then
            self:updatePerkVisualState(levelIndex)
        end
    end
end

-- Update visual state for perks in a level column
function WeaponProficiency:updatePerkVisualState(levelIndex)
    local perkColumn = self.perkPanel:getChildById('perkColumn_' .. levelIndex)
    if not perkColumn or not perkColumn.currentPerkPanel then
        return
    end

    -- Get pending selection first, then fall back to cached perk
    local selectedPerkIndex = self.pendingSelections and self.pendingSelections[levelIndex]

    -- If no pending selection, check cached perks
    if not selectedPerkIndex and self.selectedItemId and getWeaponProficiencyCache(self.selectedItemId) then
        local cachedPerks = getWeaponProficiencyCache(self.selectedItemId).perks or {}
        for _, perk in ipairs(cachedPerks) do
            if type(perk) == "table" and perk[1] == levelIndex then
                selectedPerkIndex = perk[2]
                break
            end
        end
    end

    -- Update each perk icon in this column
    for perkIdx = 0, 2 do
        local bonusIcon = perkColumn.currentPerkPanel:getChildById('bonusIcon' .. perkIdx)
        if bonusIcon then
            local isSelected = (selectedPerkIndex == (perkIdx + 1))
            local isLevelUnlocked = not bonusIcon.blocked
            local modifier = findCachedModifier(self.selectedItemId, levelIndex, perkIdx + 1)
            local basePerkData = bonusIcon.originalPerkData or bonusIcon.perkData
            local displayPerkData = basePerkData
            if modifier then
                displayPerkData = ProficiencyData:getModifierPerkData(modifier.modifierEnum, modifier.refineLevel) or basePerkData
            end
            local isPerkActive = isSelected and isLevelUnlocked
            if displayPerkData then
                applyBonusIconPerkVisual(bonusIcon, displayPerkData)
                if isPerkActive then
                    local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(displayPerkData)
                    bonusIcon:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))
                end
            end

            local iconWidget = bonusIcon:getChildById('icon')
            local iconGreyWidget = bonusIcon:getChildById('icon-grey')
            local borderWidget = bonusIcon:getChildById('border')
            local highlightWidget = bonusIcon:getChildById('highlight')

            -- Show color icon only if unlocked AND selected
            if iconWidget then
                iconWidget:setVisible(isLevelUnlocked and isSelected)
            end

            if iconGreyWidget then
                iconGreyWidget:setVisible(not isSelected or not isLevelUnlocked)
            end

            setPerkTreeBorderImage(borderWidget, isSelected, isLevelUnlocked, modifier ~= nil)

            -- Highlight selected
            if highlightWidget then
                highlightWidget:setVisible(isPerkActive)
                highlightWidget:setImageSource(proficiencyImage(modifier and 'backdrop_weaponmastery_manipulate_highlight' or 'backdrop_weaponmastery_highlight'))
            end

            local selectedWidget = bonusIcon:getChildById('selected')
            if selectedWidget then
                selectedWidget:setVisible(isPerkActive)
            end
            updateManipulateRankWidget(bonusIcon, modifier, isPerkActive)

            bonusIcon.active = isSelected
        end
    end

    -- Update bonus detail panel
    self:updateBonusDetailForLevel(levelIndex)
end

-- Update bonus detail panel for a specific level
function WeaponProficiency:updateBonusDetailForLevel(levelIndex)
    local bonusDetailPanel = self.window:recursiveGetChildById('bonusDetailBackground')
    if not bonusDetailPanel then
        return
    end

    local detailPanel = bonusDetailPanel:getChildById('bonusDetail_' .. levelIndex)
    if not detailPanel then
        return
    end

    local bonusNameWidget = detailPanel:getChildById('bonusName')
    if not bonusNameWidget then
        return
    end

    local selectedPerkIndex = getSelectedPerkIndexForLevel(self, levelIndex)

    if selectedPerkIndex then
        local perkColumn = self.perkPanel:getChildById('perkColumn_' .. levelIndex)
        if perkColumn and perkColumn.currentPerkPanel then
            local bonusIcon = perkColumn.currentPerkPanel:getChildById('bonusIcon' .. (selectedPerkIndex - 1))
            local basePerkData = bonusIcon and (bonusIcon.originalPerkData or bonusIcon.perkData)
            local displayPerkData = getDisplayPerkDataForLevelSlot(self, levelIndex, selectedPerkIndex, basePerkData)
            if displayPerkData then
                local _, tooltip = ProficiencyData:getBonusNameAndTooltip(displayPerkData)
                bonusNameWidget:setText(tooltip)
                bonusNameWidget:setTooltip(tooltip)
                bonusNameWidget:setImageSource("")
                return
            end
        end
    end

    -- No selection - show lock icon
    bonusNameWidget:setText("")
    bonusNameWidget:setImageSource(proficiencyImage("icon-lock-grey"))
end

-- Update bonus detail panels at the bottom
function WeaponProficiency:updateBonusDetails(proficiencyContent, selectedPerks)
    local bonusDetailPanel = self.window:recursiveGetChildById('bonusDetailBackground')
    if not bonusDetailPanel then
        return
    end

    local levels = proficiencyContent.Levels or {}

    for i = 1, #levels do
        local detailPanel = bonusDetailPanel:getChildById('bonusDetail_' .. i)
        if detailPanel then
            local bonusNameWidget = detailPanel:getChildById('bonusName')
            local levelData = levels[i]

            if bonusNameWidget and levelData then
                -- Find selected perk for this level
                local selectedPerkIndex = nil
                if selectedPerks and type(selectedPerks) == "table" then
                    -- Check array format first: {{level, perkPos}, ...} (from cache/server)
                    local isArrayFormat = false
                    if #selectedPerks > 0 and type(selectedPerks[1]) == "table" then
                        isArrayFormat = true
                        for _, perk in ipairs(selectedPerks) do
                            if type(perk) == "table" and #perk >= 2 and perk[1] == i then
                                selectedPerkIndex = perk[2] -- Already 1-indexed from cache
                                break
                            end
                        end
                    end

                    -- Check indexed format: {[levelIndex] = perkIndex} (from pendingSelections)
                    if not isArrayFormat and not selectedPerkIndex then
                        local key = i -- pendingSelections uses 1-indexed level
                        if selectedPerks[key] ~= nil then
                            local value = selectedPerks[key]
                            if type(value) == "number" then
                                selectedPerkIndex = value -- Already 1-indexed from pendingSelections
                            end
                        end
                    end
                end

                if selectedPerkIndex then
                    local perksData = levelData.Perks or {}
                    local perkData
                    local perkColumn = self.perkPanel:getChildById('perkColumn_' .. i)
                    local icon = perkColumn and perkColumn.currentPerkPanel and perkColumn.currentPerkPanel:getChildById('bonusIcon' .. (selectedPerkIndex - 1))
                    local basePerkData = icon and (icon.originalPerkData or icon.perkData) or perksData[selectedPerkIndex]
                    local perkData = getDisplayPerkDataForLevelSlot(self, i, selectedPerkIndex, basePerkData)
                    if perkData then
                        local _, tooltip = ProficiencyData:getBonusNameAndTooltip(perkData)
                        bonusNameWidget:setText(tooltip)
                        bonusNameWidget:setTooltip(tooltip)
                        bonusNameWidget:setImageSource("") -- Hide lock icon
                    else
                        bonusNameWidget:setText("")
                        bonusNameWidget:setImageSource(proficiencyImage("icon-lock-grey"))
                    end
                else
                    bonusNameWidget:setText("")
                    bonusNameWidget:setImageSource(proficiencyImage("icon-lock-grey"))
                end
            elseif bonusNameWidget then
                bonusNameWidget:setText("")
                bonusNameWidget:setImageSource(proficiencyImage("icon-lock-grey"))
            end
        end
    end
end

-- Handle item box click in the list
function WeaponProficiency:onItemBoxClick(widget)
    if not widget then
        return
    end

    local itemWidget = widget:getChildById('item')
    if not itemWidget then
        return
    end

    local itemId = itemWidget:getItemId()
    if not itemId or itemId == 0 then
        return
    end

    -- Find the market item data
    local categoryDropdown = self.window:recursiveGetChildById('classFilter')
    local currentCategory = MarketCategory.WeaponsAll

    if categoryDropdown then
        local selectedText = categoryDropdown:getText()
        currentCategory = WeaponStringToCategory[selectedText] or MarketCategory.WeaponsAll
    end

    local items = self.itemList[currentCategory] or {}
    local marketItem = nil

    for _, item in ipairs(items) do
        if item.displayItem and item.displayItem:getId() == itemId then
            marketItem = item
            break
        end
    end

    if marketItem then
        self:selectItem(itemId, marketItem)
    end
end

-- Apply filter for Level button
function WeaponProficiency:applyLevelFilter(items)
    if not self.filters["levelButton"] then
        return items
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return items
    end

    local playerLevel = player:getLevel()
    local filteredItems = {}

    for _, item in ipairs(items) do
        local requiredLevel = getNumericCall(item.thingType, "getMinimumLevel")
        if requiredLevel == 0 then
            requiredLevel = item.marketData.requiredLevel or 0
        end
        if playerLevel >= requiredLevel then
            table.insert(filteredItems, item)
        end
    end

    return filteredItems
end

-- Apply filter for Vocation button
function WeaponProficiency:applyVocationFilter(items)
    if not self.filters["vocButton"] then
        return items
    end

    local playerVocation = getPlayerWheelVocation()
    local filteredItems = {}

    for _, item in ipairs(items) do
        local restrictVocation = item.marketData and item.marketData.restrictVocation or 0
        local category = item.marketData and item.marketData.category or nil

        if restrictVocation and restrictVocation ~= 0 then
            if vocationRestrictionMatches(restrictVocation, playerVocation) then
                table.insert(filteredItems, item)
            end
        elseif categoryMatchesPlayerVocation(category) then
            table.insert(filteredItems, item)
        end
    end

    return filteredItems
end

-- Apply filter for 1H (one-handed) weapons
function WeaponProficiency:applyOneHandedFilter(items)
    if not self.filters["oneButton"] then
        return items
    end

    local filteredItems = {}
    for _, item in ipairs(items) do
        local thingType = item.thingType
        if thingType then
            local slotType = thingType:getClothSlot() or 0
            if slotType == 6 then
                table.insert(filteredItems, item)
            end
        end
    end
    return filteredItems
end

-- Apply filter for 2H (two-handed) weapons
function WeaponProficiency:applyTwoHandedFilter(items)
    if not self.filters["twoButton"] then
        return items
    end

    local filteredItems = {}
    for _, item in ipairs(items) do
        local thingType = item.thingType
        if thingType then
            local slotType = thingType:getClothSlot() or 0
            if slotType == 0 then
                table.insert(filteredItems, item)
            end
        end
    end
    return filteredItems
end

-- Apply button click handler
function WeaponProficiency:onApplyClick()
    local success, err = pcall(function()
        self:applyPendingSelections()
    end)
    if not success then
        -- Log error with context before clearing
        warn("Failed to apply pending selections: " .. tostring(err))
        -- Clear pending selections on error to allow closing
        self.pendingSelections = {}
        self:updateApplyButtonState()
    end
end

-- Ok button click handler
function WeaponProficiency:onOkClick()
    -- Apply pending selections if any
    if self.pendingSelections and next(self.pendingSelections) ~= nil then
        local success, err = pcall(function()
            self:applyPendingSelections()
        end)
        if not success then
            -- Log error with context before clearing
            warn("Failed to apply pending selections in onOkClick: " .. tostring(err))
            -- Clear on error to allow closing
            self.pendingSelections = {}
        end
    end
    -- Always close window, even if there was an error
    hide()
end

-- Reset button click handler
function WeaponProficiency:onResetClick()
    self.pendingSelections = {}

    local itemId = self.selectedItemId
    if not itemId then
        return
    end

    local protocolItemId = getProtocolItemId(self.selectedMarketItem, itemId)
    -- Action 2 = reset perk selections only; shaped modifiers stay (CrystalOTC behaviour).
    sendWeaponProficiencyAction(2, protocolItemId)

    if self.selectedMarketItem then
        local displayItem = self.selectedMarketItem.displayItem
        local cacheData = getWeaponProficiencyCache(itemId)
        if displayItem and cacheData then
            cacheData.perks = {}
            setWeaponProficiencyCache(itemId, cacheData)
            self:displayPerks(itemId, cacheData.perks, displayItem)
            self:updateSelectedPerkVisuals()
            local proficiencyId = ProficiencyData:getProficiencyIdForItem(displayItem,
                self.selectedMarketItem.thingType, self.selectedMarketItem.marketData)
            local profEntry = proficiencyId and ProficiencyData:getContentById(proficiencyId)
            if profEntry then
                self:updateBonusDetails(profEntry, cacheData.perks)
            end
        end
    end

    self.selectedModifySlot = nil
    self:updateModifyButtonState()
    self:updateApplyButtonState()

    scheduleEvent(function()
        if proficiencyItemsMatch(WeaponProficiency.selectedItemId, itemId) then
            sendWeaponProficiencyAction(0, protocolItemId)
        end
    end, 200)
end

-- Apply pending perk selections to server
function WeaponProficiency:applyPendingSelections()
    if not self.selectedItemId then
        return
    end

    -- Build complete perk selection list for server
    -- Start with cached perks (already saved on server)
    local allPerks = {} -- {[levelIndex] = perkIndex} in 1-indexed format

    local cacheEntry = getWeaponProficiencyCache(self.selectedItemId)

    -- First, load existing cached perks
    if cacheEntry and cacheEntry.perks then
        for _, perk in ipairs(cacheEntry.perks) do
            if type(perk) == "table" and #perk >= 2 then
                allPerks[perk[1]] = perk[2] -- level -> perkIndex (1-indexed)
            end
        end
    end

    -- Then, merge with pending selections (these override cached perks)
    if self.pendingSelections then
        for levelIndex, perkIndex in pairs(self.pendingSelections) do
            allPerks[levelIndex] = perkIndex -- level -> perkIndex (1-indexed)
        end
    end

    -- Shaped slots must keep their perk index or the server drops the modifier.
    if cacheEntry and cacheEntry.modifiers then
        for _, modifier in ipairs(cacheEntry.modifiers) do
            allPerks[modifier.grade] = modifier.slot
        end
    end

    -- Convert to array format for sending: {level (0-indexed), perkPosition (0-indexed)}
    local selections = {}
    for levelIndex, perkIndex in pairs(allPerks) do
        table.insert(selections, {levelIndex - 1, perkIndex - 1})
    end

    -- Sort by level for consistency
    table.sort(selections, function(a, b)
        return a[1] < b[1]
    end)

    if #selections == 0 then
        return
    end

    -- Build two parallel arrays for C++ (levels and perkPositions)
    local levels = {}
    local perkPositions = {}

    -- Log selection details (0-indexed in Lua, will be converted to 1-indexed in C++)
    for i, sel in ipairs(selections) do
        table.insert(levels, sel[1])
        table.insert(perkPositions, sel[2])
    end

    -- Send to server using the protocol function with two parallel arrays
    -- g_game.sendWeaponProficiencyApply(itemId, levelsArray, perkPositionsArray)
    local protocolItemId = getProtocolItemId(self.selectedMarketItem, self.selectedItemId)
    sendWeaponProficiencyApply(protocolItemId, levels, perkPositions)

    -- Update cache with ALL applied perks (convert back to server format: 1-indexed)
    -- This includes both cached perks and new pending selections
    if cacheEntry then
        local appliedPerks = {}
        for _, sel in ipairs(selections) do
            table.insert(appliedPerks, {sel[1] + 1, sel[2] + 1}) -- Convert back to 1-indexed for cache
        end
        cacheEntry.perks = appliedPerks
        setWeaponProficiencyCache(self.selectedItemId, cacheEntry)

        -- Clear pendingSelections - perks are now saved in cache, no longer "pending"
        self.pendingSelections = {}

        -- Update UI immediately with applied perks (using cache format)
        -- This keeps the visual selection active
        if self.selectedMarketItem and self.selectedMarketItem.displayItem then
            self:displayPerks(self.selectedItemId, appliedPerks, self.selectedMarketItem.displayItem)
        end

        -- Update button states (Apply should be disabled since we just applied)
        self:updateApplyButtonState()

        -- Clear the hasUnusedPerk flag and hide highlight after applying
        -- The user has now used their perks, so no notification needed
        self.hasUnusedPerk = false
        updateProficiencyHighlight()

        -- Request updated proficiency info from server to confirm
        scheduleEvent(function()
            if self.selectedItemId then
                sendWeaponProficiencyAction(0, getProtocolItemId(self.selectedMarketItem, self.selectedItemId))
            end
        end, 200)
    end

    -- Pending selections already cleared above
end

-- Update Apply/Ok/Reset button enabled state based on pending selections
function WeaponProficiency:updateApplyButtonState()
    if not self.window then
        return
    end

    local applyBtn = self.window:getChildById('apply')
    local okBtn = self.window:getChildById('ok')
    local resetBtn = self.window:getChildById('reset')

    local hasPendingSelections = self.pendingSelections and next(self.pendingSelections) ~= nil

    -- Check if there are applied perks in cache
    local hasAppliedPerks = false
    if self.selectedItemId and getWeaponProficiencyCache(self.selectedItemId) then
        local cachedPerks = getWeaponProficiencyCache(self.selectedItemId).perks
        hasAppliedPerks = cachedPerks and #cachedPerks > 0
    end

    -- Apply/Ok: enabled when there are pending selections (changes to apply)
    if applyBtn then
        applyBtn:setEnabled(hasPendingSelections)
    end
    if okBtn then
        okBtn:setEnabled(true) -- Always enabled to allow closing
    end

    -- Reset: enabled when there are applied perks
    if resetBtn then
        resetBtn:setEnabled(hasAppliedPerks)
    end
end
