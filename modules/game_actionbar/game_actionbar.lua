ApiJson = dofile('logics/ApiJson.lua')

player = nil --localplayer
-- @array
passiveData = {
    cooldown = 0,
    max = 0
}
hotkeyItemList = {} --[ItemPtr, desc]
spellListData = {} -- [[SpellsIdLearn]]
spellCooldownCache = {--[[     
    [SpellId] = { 
        ["startTime"] = ms,
        ["exhaustion"] = ms
    } 
]]
}
spellGroupCooldownCache = {--[[
    [GroupId] = {
        ["startTime"] = ms,
        ["exhaustion"] = ms
    }
]]
}
spellGroupPressed = {--[[ 
    [GroupId] = bool -- Tracks if spell group is currently pressed
]]
}
cachedItemWidget = { --[[
     [ItemID] = { 
        [SlotId] = Widget1,
        [SlotId] = Widget2,
     ]]
}
actionBars = { --[[ 
    -- ActionBarId=1-3: bottom
    -- ActionBarId=4-6: left
    -- ActionBarId=7-9: right
    [ActionBarId] = widget
]]
}
activeActionBars = {--[[ 
    [VisibleActionBarId] = widget
 ]]
}

-- @ widgets
dragButton = nil
dragItem = nil
mouseGrabberWidget = nil
gameRootPanel = nil
lastHighlightWidget = nil
-- @ boolean
isLoaded = false
local areEventsConnected = false

--- checks if action bar is visible
local function isActionBarVisible(actionBar)
    return actionBar and actionBar:isVisible()
end

--- Adds an action bar to the active list
function addActiveActionBar(actionBar)
    if not actionBar then
        return false
    end

    for _, activeBar in ipairs(activeActionBars) do
        if activeBar == actionBar then
            return false
        end
    end

    table.insert(activeActionBars, actionBar)
    return true
end
--- Rebuilds the list of active action bars
local function rebuildActiveActionBars()
    local previousCount = #activeActionBars
    local visibleCount = 0

    for _, actionBar in ipairs(actionBars) do
        if isActionBarVisible(actionBar) then
            visibleCount = visibleCount + 1
            activeActionBars[visibleCount] = actionBar
        end
    end

    for index = visibleCount + 1, previousCount do
        activeActionBars[index] = nil
    end

    return visibleCount > 0
end
--- Removes an action bar from the active list
function removeActiveActionBar(actionBar)
    if not actionBar then
        return false
    end

    local removed = false
    local index = 1
    while index <= #activeActionBars do
        if activeActionBars[index] == actionBar then
            table.remove(activeActionBars, index)
            removed = true
        else
            index = index + 1
        end
    end

    return removed
end

--- Checks if there are any active action bars
function hasAnyActiveActionBar()
    if not g_game.isOnline() then
        return false
    end

    if rebuildActiveActionBars() then
        return true
    end

    return false
end

--- Sets up an action bar by index
function setupActionBar(n)
    local actionbar = actionBars[n]
    local barState = ApiJson.getActionBar(n) or {}
    local visible = barState.isVisible and true or false
    actionbar:setVisible(visible)
    actionbar:setOn(visible)
    local locked = barState.isLocked and true or false
    actionbar.tabBar.onMouseWheel = nil
    actionbar.locked = locked
    local items = {}
    for i = 1, 50 do
        local layout = n < 4 and 'ActionButton' or 'SideActionButton'
        local widget = actionbar.tabBar:getChildById(n .. "." .. i)
        
           if not widget then
               local hasMapping = ApiJson.getMapping(n, i)
           
           if hasMapping then
               widget = g_ui.createWidget(layout, actionbar.tabBar)
               widget:setId(n .. "." .. i)
           else
               widget = g_ui.createWidget('UIWidget', actionbar.tabBar)
               widget:setId(n .. "." .. i)
               widget:setSize({width = 34, height = 34})
               widget:setMarginLeft(2)
               widget:setImageSource('/images/game/actionbar/actionbarslot')
               widget:setDraggable(false)
               
               widget.onDrop = function(self, draggedWidget, mousePos)
                    if draggedWidget and draggedWidget.currentDragThing then
                        if tryAssignActionButtonFromDrop(mousePos, draggedWidget, draggedWidget.currentDragThing) then
                            return true
                        end
                    end
               end
               
               widget.onMouseRelease = function(self, mousePos, mouseButton)
                    if mouseButton == MouseRightButton then
                        local parent = self:getParent()
                        local id = self:getId()
                        updateButton(self)
                        local newButton = parent:getChildById(id)
                        if newButton and newButton.onMouseRelease then
                            newButton.onMouseRelease(newButton, mousePos, mouseButton)
                        end
                        return true
                    end
               end
           end
        end
        
        -- Only update if it's a real button
        if widget:getChildById('item') and g_game.isOnline() then
             updateButton(widget)
        end
         
         if widget.cooldown then
             widget.cooldown:stop()
         end
         if widget.item and widget.item:getItemId() > 100 then
             table.insert(items, widget.item:getItem())
         end
    end
end

--- Gets the count of active bottom action bars
function getActiveBottomBars()
    if #actionBars == 0 then
        return 0
    end
    local count = 0
    for i = 1, 3 do
        local state = ApiJson.getActionBar(i) or {}
        if state.isVisible then
            count = count + 1
        end
    end
    return count
end

--- Gets the count of active right action bars
function getActiveRightBars()
    if #actionBars == 0 then
        return 0
    end
    local count = 0
    for i = 7, 9 do
        local state = ApiJson.getActionBar(i) or {}
        if state.isVisible then
            count = count + 1
        end
    end
    return count
end

function getActiveLeftBars()
    if #actionBars == 0 then
        return 0
    end
    local count = 0
    for i = 4, 6 do
        local state = ApiJson.getActionBar(i) or {}
        if state.isVisible then
            count = count + 1
        end
    end
    return count
end

local function onUpdateActionBarStatus()
    if #activeActionBars == 0 then
        return true
    end

    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            updateButtonState(button)
        end
    end
end

-- /*=============================================
-- =            Event             =
-- =============================================*/


local pendingInventoryItemsUpdate = nil

local function scheduleInventoryItemsUpdate()
    if pendingInventoryItemsUpdate then
        return
    end

    pendingInventoryItemsUpdate = scheduleEvent(function()
        pendingInventoryItemsUpdate = nil
        updateInventoryItems()
    end, 50)
end

local function normalizeItemCountName(name)
    if not name or name == '' then
        return ''
    end
    name = name:lower()
    name = name:gsub('%.+$', ''):gsub('%s+$', ''):gsub('^%s+', '')
    if #name > 1 and name:sub(-1) == 's' then
        name = name:sub(1, -2)
    end
    return name
end

local function getActionBarItemName(itemId)
    if not itemId or itemId == 0 then
        return nil
    end

    local ok, item = pcall(function()
        return Item.create(itemId)
    end)
    if not ok or not item then
        return nil
    end

    if item.getMarketData then
        local market = item:getMarketData()
        if market and market.name and market.name ~= '' then
            return market.name
        end
    end

    if item.getName then
        return item:getName()
    end

    return nil
end

-- Servers without opcode 0xF5 (PlayerInventory) never fill the count cache.
-- Fall back to the classic "Using one of N ..." status text, like many OT clients.
local function onSupplyUseTextMessage(mode, text)
    if type(text) ~= 'string' then
        return
    end

    local amount, itemName = text:match('[Uu]sing one of (%d+) (.+)')
    if not amount or not itemName then
        return
    end

    amount = tonumber(amount)
    if not amount or not player or not player.setInventoryCountCacheEntry then
        return
    end

    local needle = normalizeItemCountName(itemName)
    if needle == '' then
        return
    end

    local updated = false
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            local itemId = button.cache and button.cache.itemId or 0
            if itemId ~= 0 then
                local buttonName = normalizeItemCountName(getActionBarItemName(itemId))
                if buttonName ~= '' and buttonName == needle then
                    local tier = 0
                    if g_game.getFeature(GameThingUpgradeClassification) then
                        tier = button.cache.upgradeTier or 0
                    end
                    -- Status text carries the server-side total ("Using one of 97 ...").
                    player:setInventoryCountCacheEntry(itemId, tier, amount)
                    updated = true
                end
            end
        end
    end

    if updated then
        scheduleInventoryItemsUpdate()
    end
end

--- Connects player events
local function connecting()
    if areEventsConnected then
        return
    end

    connect(LocalPlayer, {
        onManaChange = onUpdateActionBarStatus,
        onSoulChange = onUpdateActionBarStatus,
        onLevelChange = onUpdateLevel,
        onSpellsChange = onSpellsChange,
        onInventoryChange = scheduleInventoryItemsUpdate
    })
    connect(Container, {
        -- onOpen covers the initial onAddItems burst when a backpack is opened
        onOpen = scheduleInventoryItemsUpdate,
        onAddItem = scheduleInventoryItemsUpdate,
        onUpdateItem = scheduleInventoryItemsUpdate,
        onRemoveItem = scheduleInventoryItemsUpdate
    })
    connect(g_game, {
        onItemInfo = onHotkeyItems,
        onPassiveData = onPassiveData,
        onSpellCooldown = onSpellCooldown,
        onMultiUseCooldown = onMultiUseCooldown,
        onSpellGroupCooldown = onSpellGroupCooldown,
        updateInventoryItems = updateInventoryItems
    })
    registerMessageMode(MessageModes.HotkeyUse, onSupplyUseTextMessage)
    registerMessageMode(MessageModes.Status, onSupplyUseTextMessage)

    areEventsConnected = true
end

--- Disconnects player events
local function disconnecting()
    if not areEventsConnected then
        return
    end

    if pendingInventoryItemsUpdate then
        removeEvent(pendingInventoryItemsUpdate)
        pendingInventoryItemsUpdate = nil
    end

    disconnect(LocalPlayer, {
        onManaChange = onUpdateActionBarStatus,
        onSoulChange = onUpdateActionBarStatus,
        onLevelChange = onUpdateLevel,
        onSpellsChange = onSpellsChange,
        onInventoryChange = scheduleInventoryItemsUpdate
    })
    disconnect(Container, {
        onOpen = scheduleInventoryItemsUpdate,
        onAddItem = scheduleInventoryItemsUpdate,
        onUpdateItem = scheduleInventoryItemsUpdate,
        onRemoveItem = scheduleInventoryItemsUpdate
    })
    disconnect(g_game, {
        onItemInfo = onHotkeyItems,
        onPassiveData = onPassiveData,
        onSpellCooldown = onSpellCooldown,
        onMultiUseCooldown = onMultiUseCooldown,
        onSpellGroupCooldown = onSpellGroupCooldown,
        updateInventoryItems = updateInventoryItems
    })
    unregisterMessageMode(MessageModes.HotkeyUse, onSupplyUseTextMessage)
    unregisterMessageMode(MessageModes.Status, onSupplyUseTextMessage)

    areEventsConnected = false
end

--- Updates event subscriptions based on active bars
function updateActionBarEventSubscriptions()
    if hasAnyActiveActionBar() then
        connecting()
        return
    end

    disconnecting()
end

-- /*=============================================
-- =            Controller             =
-- =============================================*/
ActionBarController = Controller:new()

local function cleanupMultiActionState()
    if closeCurrentMultiActionPanel then
        closeCurrentMultiActionPanel()
    end
    if multiActionCooldownEvents then
        for buttonId, events in pairs(multiActionCooldownEvents) do
            for _, eventId in pairs(events) do
                removeEvent(eventId)
            end
            multiActionCooldownEvents[buttonId] = nil
        end
    end
    cacheMultiActionButtons = {}
    if pendingMultiButtonUpdate then
        removeEvent(pendingMultiButtonUpdate)
        pendingMultiButtonUpdate = nil
        pendingMultiButtons = {}
        pendingMultiButtonsTracker = {}
    end
end

--- Initializes the action bar controller
function ActionBarController:onInit()
    g_ui.importStyle("otui/style.otui")
    g_ui.importStyle("otui/multiaction.otui")
    gameRootPanel = modules.game_interface.getRootPanel()
    mouseGrabberWidget = g_ui.createWidget('UIWidget')
    mouseGrabberWidget:setVisible(false)
    mouseGrabberWidget:setFocusable(false)
    mouseGrabberWidget.onMouseRelease = onDropActionButton
end

--- Handles termination event
function ActionBarController:onTerminate()
    ApiJson.saveData()
    closeAllAssignWindows()
    cleanupMultiActionState()
    for _, actionbar in pairs(actionBars) do
        if actionbar and not actionbar:isDestroyed() then
            actionbar:destroy()
        end
    end
    if mouseGrabberWidget then
        mouseGrabberWidget:destroy()
        mouseGrabberWidget = nil
    end
    if lastHighlightWidget then
        lastHighlightWidget:destroy()
        lastHighlightWidget = nil
    end
    if dragButton then
        dragButton:destroy()
        dragButton = nil
    end
    if dragItem then
        dragItem:destroy()
        dragItem = nil
    end
    actionBars = {}
    activeActionBars = {}
    disconnecting()
end

--- Handles game start event
function ActionBarController:onGameStart()
    onCreateActionBars()
    
    -- Ensure fresh cache
    if clearHotkeyCache then clearHotkeyCache() end
    updateActionBarEventSubscriptions()
    dragItem = nil
    dragButton = nil
    cachedItemWidget = {}
    player = g_game.getLocalPlayer()
    hotkeyItemList = {}
    spellGroupPressed = {}
    spellGroupCooldownCache = {}
    for i = 1, #actionBars do
        setupActionBar(i)
    end
    ActionBarController:scheduleEvent(function()
        onMultiUseCooldown()
        onUpdateActionBarStatus()
        updateInventoryItems()
        updateActionPassive()
        updateVisibleWidgets()
        isLoaded = true
    end, 300, "update_items")

    -- Backpack open + player inventory opcode can arrive after the first pass
    ActionBarController:scheduleEvent(updateInventoryItems, 800, "update_items_retry")
    ActionBarController:scheduleEvent(updateInventoryItems, 1500, "update_items_retry2")
end

function ActionBarController:onGameEnd()
    isLoaded = false
    closeAllAssignWindows()
    cleanupMultiActionState()
    spellGroupCooldownCache = {}
    for _, actionbar in pairs(activeActionBars) do
        unbindActionBarEvent(actionbar)
    end
    activeActionBars = {}
    hotkeyItemList = {}
    if g_tooltip then
        g_tooltip.hide()
        g_tooltip.hideSpecial()
    end
    updateActionBarEventSubscriptions()
end
-- /*=============================================
-- =            Events Call            =
-- =============================================*/


--- Handles spell cooldown events
local pendingMultiButtonUpdate = nil
local pendingMultiButtons = {}
local pendingMultiButtonsTracker = {}

local function schedulePendingMultiButtonUpdate()
    if pendingMultiButtonUpdate then
        return
    end
    pendingMultiButtonUpdate = scheduleEvent(function()
        for _, button in ipairs(pendingMultiButtons) do
            if button and not button:isDestroyed() then
                updateMultiButtonState(button)
            end
        end
        pendingMultiButtons = {}
        pendingMultiButtonsTracker = {}
        pendingMultiButtonUpdate = nil
    end, 50)
end

local function addPendingMultiButton(button)
    if not pendingMultiButtonsTracker[button] then
        pendingMultiButtons[#pendingMultiButtons + 1] = button
        pendingMultiButtonsTracker[button] = true
    end
end

function onSpellCooldown(spellId, delay)
    local showProgress = modules.client_options.getOption("graphicalCooldown")
    local showTime = modules.client_options.getOption("cooldownSecond")
    if not showProgress and not showTime then
        return true
    end
    local cooldownStart = g_clock.millis()
    local isRune = Spells.isRuneSpell(spellId)
    spellCooldownCache[spellId] = {
        exhaustion = delay,
        startTime = cooldownStart
    }

    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            local cache = getButtonCache(button)
            if cache and cache.multiActions and not table.empty(cache.multiActions) then
                for _, actionData in pairs(cache.multiActions) do
                    if actionData and actionData["chatText"] then
                        local spellData = Spells.getSpellDataByParamWords(actionData["chatText"]:lower())
                        if spellData and spellData.id == spellId then
                            addPendingMultiButton(button)
                            if scheduleMultiActionCooldownEvent then
                                local effectiveDelay = math.max(delay, spellData.exhaustion or 0)
                                scheduleMultiActionCooldownEvent(button, "spell_" .. spellId, effectiveDelay)
                            end
                            break
                        end
                    elseif actionData and actionData["useObject"] then
                        local runeSpellData = Spells.getRuneSpellByItem(actionData["useObject"])
                        if runeSpellData and runeSpellData.id == spellId then
                            addPendingMultiButton(button)
                            if scheduleMultiActionCooldownEvent then
                                local effectiveDelay = math.max(delay, runeSpellData.exhaustion or 0)
                                scheduleMultiActionCooldownEvent(button, "rune_" .. spellId, effectiveDelay)
                            end
                            break
                        end
                    end
                end
            end

            if cache and (cache.isSpell or cache.isRuneSpell) then
                local shouldUpdate = true
                if cache.isRuneSpell and not isRune then
                    shouldUpdate = false
                elseif cache.isRuneSpell and
                    (not cache.spellData or cache.spellData.id ~= spellId) then
                    shouldUpdate = false
                elseif not cache.isRuneSpell and cache.spellID ~= spellId then
                    shouldUpdate = false
                elseif cache.cooldownEvent ~= nil and button.cooldown:getTimeElapsed() > delay then
                    shouldUpdate = false
                end
                if shouldUpdate then
                    updateCooldown(button, delay)
                    if cache.removeCooldownEvent then
                        removeEvent(button.cache.removeCooldownEvent)
                        button.cache.removeCooldownEvent = nil
                    end
                    button.cache.removeCooldownEvent = scheduleEvent(function()
                        removeCooldown(button)
                    end, delay)
                end
            end
        end
    end

    schedulePendingMultiButtonUpdate()
end

function onSpellGroupCooldown(groupId, delay)
    local showProgress = modules.client_options.getOption("graphicalCooldown")
    local showTime = modules.client_options.getOption("cooldownSecond")
    if not showProgress and not showTime then
        return true
    end
    spellGroupCooldownCache[groupId] = {
        exhaustion = delay,
        startTime = g_clock.millis()
    }

    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            local cache = getButtonCache(button)
            if cache and cache.multiActions and not table.empty(cache.multiActions) then
                for _, actionData in pairs(cache.multiActions) do
                    if actionData and actionData["chatText"] then
                        local spellData = Spells.getSpellDataByParamWords(actionData["chatText"]:lower())
                        if spellData and
                            (Spells.getCooldownByGroup(spellData, groupId) or
                                Spells.getCooldownBySecondaryGroup(spellData, groupId)) then
                            addPendingMultiButton(button)
                            if scheduleMultiActionCooldownEvent then
                                scheduleMultiActionCooldownEvent(button, "group_" .. groupId .. "_spell_" .. spellData.id,
                                    delay)
                            end
                            break
                        end
                    elseif actionData and actionData["useObject"] then
                        local runeSpellData = Spells.getRuneSpellByItem(actionData["useObject"])
                        if runeSpellData and
                            (Spells.getCooldownByGroup(runeSpellData, groupId) or
                                Spells.getCooldownBySecondaryGroup(runeSpellData, groupId)) then
                            addPendingMultiButton(button)
                            if scheduleMultiActionCooldownEvent then
                                scheduleMultiActionCooldownEvent(button, "group_" .. groupId .. "_rune_" .. runeSpellData.id,
                                    delay)
                            end
                            break
                        end
                    end
                end
            end

            if cache and (not cache.isRuneSpell and cache.spellData) then
                if Spells.getCooldownByGroup(cache.spellData, groupId) then
                    local resttime = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
                    if resttime < delay then
                        updateCooldown(button, delay)
                        if button.cache.removeCooldownEvent then
                            removeEvent(button.cache.removeCooldownEvent)
                            button.cache.removeCooldownEvent = nil
                        end
                        button.cache.removeCooldownEvent = scheduleEvent(function()
                            removeCooldown(button)
                        end, delay)
                    end
                end
                if Spells.getCooldownBySecondaryGroup(cache.spellData, groupId) then
                    local resttime = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
                    if resttime < delay then
                        updateCooldown(button, delay)
                        if button.cache.removeCooldownEvent then
                            removeEvent(button.cache.removeCooldownEvent)
                            button.cache.removeCooldownEvent = nil
                        end
                        button.cache.removeCooldownEvent = scheduleEvent(function()
                            removeCooldown(button)
                        end, delay)
                    end
                end
            end
        end
    end

    schedulePendingMultiButtonUpdate()
end

--- Handles passive ability data updates
function onPassiveData(currentCooldown, maxCooldown, canDecay)
    passiveData = {
        cooldown = currentCooldown,
        max = maxCooldown
    }
    updateActionPassive()
end

--- Handles spell list changes
function onSpellsChange(player, list)
    spellListData = {}
    for _, spellId in pairs(list) do
        local spell = Spells.getSpellByClientId(spellId)
        if spell then
            spellListData[tostring(spell.id)] = spell
        end
    end
end

function onHotkeyItems(itemList)
    for _, data in pairs(itemList) do
        table.insert(hotkeyItemList, data)
    end
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            if button.item and button.item:getItemId() >= 100 then
                setupButtonTooltip(button, false)
            end
        end
    end
end

local spellsByVocation = {
    [1] = { -- Sorcerer
        { level = 10, spell = "exana pox" },
        { level = 12, spell = "exani hur" },
        { level = 12, spell = "exori vis" },
        { level = 13, spell = "exori tera" },
        { level = 14, spell = "utevo gran lux" },
        { level = 14, spell = "exevo pan" },
        { level = 14, spell = "utamo vita" },
        { level = 14, spell = "utani hur" },
        { level = 14, spell = "exori flam" },
        { level = 16, spell = "exori mort" },
        { level = 18, spell = "exevo flam hur" },
        { level = 20, spell = "utani gran hur" },
        { level = 20, spell = "exura gran" },
        { level = 23, spell = "exevo vis lux" },
        { level = 26, spell = "utevo vis lux" },
        { level = 30, spell = "exura vita" },
        { level = 35, spell = "utana vid" },
        { level = 38, spell = "exevo vis hur" },
        { level = 50, spell = "utura" },
        { level = 60, spell = "exevo gran mas flam" },
    },
    [2] = { -- Druid
        { level = 10, spell = "exana pox" },
        { level = 12, spell = "exani hur" },
        { level = 12, spell = "exori vis" },
        { level = 13, spell = "exori tera" },
        { level = 14, spell = "utevo gran lux" },
        { level = 14, spell = "exevo pan" },
        { level = 14, spell = "utamo vita" },
        { level = 14, spell = "utani hur" },
        { level = 15, spell = "exori frigo" },
        { level = 18, spell = "exevo frigo hur" },
        { level = 18, spell = "exura sio" },
        { level = 20, spell = "exura gran" },
        { level = 22, spell = "exana vis" },
        { level = 26, spell = "utevo vis lux" },
        { level = 30, spell = "exura vita" },
        { level = 35, spell = "utana vid" },
        { level = 36, spell = "exura gran mas res" },
        { level = 38, spell = "exevo tera hur" },
        { level = 55, spell = "exevo gran mas tera" },
        { level = 60, spell = "exevo gran mas frigo" },
    },
    [3] = { -- Paladin
        { level = 10, spell = "exana pox" },
        { level = 12, spell = "exani hur" },
        { level = 13, spell = "utevo gran lux" },
        { level = 13, spell = "exevo con" },
        { level = 14, spell = "utani hur" },
        { level = 16, spell = "exevo con pox" },
        { level = 17, spell = "exevo con mort" },
        { level = 20, spell = "exura gran" },
        { level = 23, spell = "exori con" },
        { level = 24, spell = "exevo con hur" },
        { level = 25, spell = "exevo con flam" },
        { level = 35, spell = "exura san" },
        { level = 40, spell = "exori san" },
        { level = 45, spell = "exeta con" },
        { level = 50, spell = "exevo mas san" },
        { level = 55, spell = "utamo tempo san" },
        { level = 60, spell = "utito tempo san" },
        { level = 60, spell = "exura gran san" },
        { level = 150, spell = "exevo gran con grav" },
    },
    [4] = { -- Knight
        { level = 10, spell = "exana pox" },
        { level = 12, spell = "exani hur" },
        { level = 14, spell = "utani hur" },
        { level = 25, spell = "utani tempo hur" },
        { level = 28, spell = "exori hur" },
        { level = 33, spell = "exori mas" },
        { level = 35, spell = "exori" },
        { level = 45, spell = "exana kor" },
        { level = 60, spell = "utito tempo" },
        { level = 80, spell = "exura gran ico" },
        { level = 90, spell = "exori gran" },
    },
}

local function flySpellAnimation(spellName, targetButton, onFinish)
    local root = modules.game_interface.getRootPanel()
    if not root then
        if onFinish then onFinish() end
        return
    end

    local spellData = Spells.getSpellDataByParamWords(spellName:lower())
    if not spellData then
        if onFinish then onFinish() end
        return
    end

    local spellId = spellData.clientId
    if not spellId then
        if onFinish then onFinish() end
        return
    end

    local source = SpelllistSettings['Default'].iconFile
    local clip = Spells.getImageClip(spellId, 'Default')

    -- Create temporary flying widget on the root panel
    local flyWidget = g_ui.createWidget('UIWidget', root)
    flyWidget:setSize({width = 32, height = 32})
    flyWidget:setImageSource(source)
    flyWidget:setImageClip(clip)
    flyWidget:setPhantom(true)
    flyWidget:setOpacity(0.0)
    local startX = root:getWidth() / 2 - 16
    local startY = root:getHeight() * 0.75 - 16
    flyWidget:setPosition({x = startX, y = startY})
    local targetPos = targetButton:getPosition()
    local targetX = targetPos.x + (targetButton:getWidth() - 32) / 2
    local targetY = targetPos.y + (targetButton:getHeight() - 32) / 2

    local duration = 650
    local stepTime = 20
    local steps = duration / stepTime
    local currentStep = 0

    local function animate()
        if not flyWidget or flyWidget:isDestroyed() then
            return
        end

        if currentStep >= steps then
            flyWidget:destroy()
            if onFinish then onFinish() end
            return
        end

        currentStep = currentStep + 1
        local t = currentStep / steps

        local opacity = math.min(t / 0.3, 1.0)
        flyWidget:setOpacity(opacity)

        local arcHeight = -100
        local arcY = 4 * arcHeight * t * (1 - t)

        local currentX = startX + (targetX - startX) * t
        local currentY = startY + (targetY - startY) * t + arcY

        -- Scale effect (starts at 2.0x, shrinks down to 1.0x)
        local scale = 2.0 - 1.0 * t
        flyWidget:setSize({width = 32 * scale, height = 32 * scale})
        flyWidget:setPosition({x = currentX, y = currentY})

        scheduleEvent(animate, stepTime)
    end

    animate()
end

local function autoAssignSpell(spellName)
    for barId = 1, 9 do
        for buttonId = 1, 50 do
            local mapping = ApiJson.getMapping(barId, buttonId)
            if mapping and mapping["actionsetting"] and mapping["actionsetting"]["chatText"] == spellName then
                return false
            end
        end
    end

    local showAnimation = true
    if modules.client_options and modules.client_options.getOption then
        showAnimation = modules.client_options.getOption('showSpellAnimation')
        if showAnimation == nil then
            showAnimation = true
        end
    end

    for barId = 1, 9 do
        local actionbar = actionBars[barId]
        if actionbar then
            if actionbar:isVisible() then
                for buttonId = 1, 50 do
                    local mapping = ApiJson.getMapping(barId, buttonId)
                    if not mapping or not mapping["actionsetting"] then
                        ApiJson.createOrUpdateText(barId, buttonId, spellName, true)
                        local button = actionbar.tabBar:getChildById(barId .. "." .. buttonId)
                        if button then
                            if showAnimation then
                                flySpellAnimation(spellName, button, function()
                                    updateButton(button)
                                    ApiJson.saveData()
                                end)
                            else
                                updateButton(button)
                                ApiJson.saveData()
                            end
                        else
                            ApiJson.saveData()
                        end
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Handles level updates
function onUpdateLevel(localPlayer, level, levelPercent, oldLevel, oldLevelPercent)
    if level ~= oldLevel then
        onUpdateActionBarStatus()
        local autoAssign = true
        if modules.client_options and modules.client_options.getOption then
            autoAssign = modules.client_options.getOption('autoAssignSpell')
            if autoAssign == nil then
                autoAssign = true
            end
        end
        if not autoAssign then
            return
        end
        local vocationId = localPlayer:getVocation()
        local vocationSpells = spellsByVocation[vocationId]
        if vocationSpells then
            for _, data in ipairs(vocationSpells) do
                if level >= data.level and oldLevel < data.level then
                    autoAssignSpell(data.spell)
                end
            end
        end
    end
end

--- Handles multi-use cooldown updates
function onMultiUseCooldown(multiUseCooldown)
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            updateButtonState(button)
            if multiUseCooldown and button.item and button.cache and button.cache.itemId then
                local item = button.item:getItem()
                if item and item:isMultiUse() then
                    local marketArray = {MarketCategory.Potions, MarketCategory.Runes, MarketCategory.Tools}
                    if table.contains(marketArray, item:getMarketData().category) then
                        updateCooldown(button, multiUseCooldown)
                    end
                end
            end
        end
    end
end

function updateInventoryItems(_)
    local refreshed = false
    for _, widgetList in pairs(cachedItemWidget) do
        for _, widget in pairs(widgetList) do
            updateButtonState(widget)
            refreshed = true
        end
    end

    -- Fallback for login/reconnect when the item cache is still empty
    if not refreshed then
        for _, actionbar in pairs(activeActionBars) do
            for _, button in pairs(actionbar.tabBar:getChildren()) do
                if button.cache and button.cache.itemId and button.cache.itemId ~= 0 then
                    updateButtonState(button)
                end
            end
        end
    end
end

--- Updates visible widgets externally
function updateVisibleWidgetsExternal()
    updateVisibleWidgets()
end

function selectHotkeySet(name)
    if not ApiJson or not ApiJson.setCurrentHotkeySetName then
        return false
    end

    if not ApiJson.setCurrentHotkeySetName(name) then
        return false
    end

    if clearHotkeyCache then
        clearHotkeyCache()
    end

    ApiJson.saveData()

    if #actionBars == 0 then
        return true
    end

    for _, actionbar in pairs(actionBars) do
        if actionbar and not actionbar:isDestroyed() then
            unbindActionBarEvent(actionbar)
        end
    end

    for i = 1, #actionBars do
        setupActionBar(i)
    end

    updateVisibleWidgets()
    updateActionBarEventSubscriptions()

    return true
end

function createHotkeySet(name, sourceName)
    if not ApiJson or not ApiJson.createHotkeySet then
        return false
    end

    local ok = ApiJson.createHotkeySet(name, sourceName)
    if ok then
        ApiJson.saveData()
    end
    return ok
end

function renameHotkeySet(oldName, newName)
    if not ApiJson or not ApiJson.renameHotkeySet then
        return false
    end

    local ok = ApiJson.renameHotkeySet(oldName, newName)
    if ok then
        ApiJson.saveData()
    end
    return ok
end

function removeHotkeySet(name)
    if not ApiJson or not ApiJson.removeHotkeySet then
        return false
    end

    local ok = ApiJson.removeHotkeySet(name)
    if ok then
        ApiJson.saveData()
    end
    return ok
end

--- Toggles cooldown display options
function toggleCooldownOption()
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            if button.cooldown and button.cooldown:getPercent() < 100 then
                 local remaining = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
                 if remaining > 0 then
                     updateCooldown(button, remaining) 
                 end
            end
        end
    end
end

function configureActionBar(key, value)
    local map = {
        actionBarShowBottom1 = 1,
        actionBarShowBottom2 = 2,
        actionBarShowBottom3 = 3,
        actionBarShowLeft1 = 4,
        actionBarShowLeft2 = 5,
        actionBarShowLeft3 = 6,
        actionBarShowRight1 = 7,
        actionBarShowRight2 = 8,
        actionBarShowRight3 = 9
    }
    local n = map[key]
    if not n then return end
    local actionbar = actionBars[n]
    if actionbar then
        ApiJson.setBarVisibility(n, key, value)
        actionbar:setVisible(value)
        actionbar:setOn(value)
        if value then
            addActiveActionBar(actionbar)
            setupActionBar(n)
        else
            removeActiveActionBar(actionbar)
        end
        if resizeLockButtons then
            resizeLockButtons()
        end
        if ActionBarController then
            ActionBarController:scheduleEvent(onUpdateActionBarStatus)
        end
    end
end

--- Updates visible options
function updateVisibleOptions(type, value)
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            if type == 'hotkey' and button.hotkeyLabel then
                button.hotkeyLabel:setVisible(value)
            elseif type == 'parameter' and button.parameterText then
                button.parameterText:setVisible(value)
            elseif type == 'tooltip' then
                local isEmpty = not button.cache or not button.cache.actionType
                    or button.cache.actionType == 0
                setupButtonTooltip(button, isEmpty)
            elseif type == 'amount' then
                updateButtonState(button)
            end
        end
    end
end

--- Resets a specific action bar
function resetAction(barId)
    local actionbar = actionBars[barId]
    if not actionbar then return end
    
    for i = 1, 50 do
        ApiJson.removeAction(barId, i)
        
        local button = actionbar.tabBar:getChildById(barId .. "." .. i)
        if button then
            updateButton(button)
        end
    end
end

--- Resets all action bars
function resetActionBars()
    for i = 1, 9 do
        resetAction(i)
    end
end
