function controllerNpcTrader:onOpenNpcTrade(items, currencyId, currencyName)
    local ui = controllerNpcTrader.ui
    if not ui or not ui:isVisible() then
        controllerNpcTrader:initNpcWindow()
    end
    local isNewSession = not controllerNpcTrader.isTradeOpen
    if isNewSession then
        controllerNpcTrader.isTradeOpen = true
        controllerNpcTrader.widthConsole = controllerNpcTrader.TRADE_CONSOLE_WIDTH
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.currencyId = currencyId or controllerNpcTrader.DEFAULT_CURRENCY_ID
        controllerNpcTrader.currencyName = currencyName or controllerNpcTrader.DEFAULT_CURRENCY_NAME
        if not controllerNpcTrader.isBankerDetected and not controllerNpcTrader.isTravelDetected then
            controllerNpcTrader.isMerchantDetected = true
            controllerNpcTrader.buttons = controllerNpcTrader.buttonsMerchant
        end
        controllerNpcTrader:connectPlayerEvents()
    else
        if currencyId then
            controllerNpcTrader.currencyId = currencyId
        end
        if currencyName then
            controllerNpcTrader.currencyName = currencyName
        end
    end

    if items and type(items) == "table" then
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.selectedItem = nil
        for _, itemData in ipairs(items) do
            local ptr = itemData[1]
            local name = itemData[2]
            local weight = itemData[3] / 100
            local buyPrice = itemData[4]
            local sellPrice = itemData[5]
            if buyPrice > 0 then
                table.insert(controllerNpcTrader.buyItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = buyPrice,
                    count = 1
                })
            end
            if sellPrice > 0 then
                table.insert(controllerNpcTrader.sellItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = sellPrice,
                    count = 1
                })
            end
        end
    end

    local currencyLabel = controllerNpcTrader:findWidget(".tradeCurrencyName")
    if currencyLabel then
        currencyLabel:setText(controllerNpcTrader.currencyName)
    end
    local currencyIcon = controllerNpcTrader:findWidget(".tradeCurrencyIcon")
    if currencyIcon then
        local item = Item.create(controllerNpcTrader.currencyId)
        if item then
            currencyIcon:setItem(item)
        else
            currencyIcon:setItemId(controllerNpcTrader.currencyId)
        end
    end

    if isNewSession then
        -- Initial State
        local initialMode = controllerNpcTrader.BUY
        if #controllerNpcTrader.buyItems > 0 then
            initialMode = controllerNpcTrader.BUY
        elseif #controllerNpcTrader.sellItems > 0 then
            initialMode = controllerNpcTrader.SELL
        end

        controllerNpcTrader.tradeMode = initialMode
        controllerNpcTrader.searchText = ""
        controllerNpcTrader.itemBatchSize = controllerNpcTrader.ITEM_BATCH_SIZE
        controllerNpcTrader.loadedItems = 0
        controllerNpcTrader.currentList = {}

        -- Settings & Sorting
        controllerNpcTrader.sortBy = controllerNpcTrader.DEFAULT_SORT_BY
        controllerNpcTrader.ignoreCapacity = controllerNpcTrader.DEFAULT_IGNORE_CAPACITY
        controllerNpcTrader.buyWithBackpack = controllerNpcTrader.DEFAULT_BUY_WITH_BACKPACK
        controllerNpcTrader.ignoreEquipped = controllerNpcTrader.DEFAULT_IGNORE_EQUIPPED

        controllerNpcTrader:setTradeMode(initialMode)
    else
        controllerNpcTrader.allTradeItems = (controllerNpcTrader.tradeMode == controllerNpcTrader.BUY) and
                                                controllerNpcTrader.buyItems or controllerNpcTrader.sellItems
        controllerNpcTrader:filterTradeList(controllerNpcTrader.searchText or "")
        controllerNpcTrader:refreshPlayerGoods(true)
    end
end

function controllerNpcTrader:setTradeMode(mode)
    self.tradeMode = mode
    self.selectedItem = nil

    local buyTab = self:findWidget("#tabBuy")
    local sellTab = self:findWidget("#tabSell")

    if buyTab then
        buyTab:setEnabled(mode ~= controllerNpcTrader.BUY)
    end
    if sellTab then
        sellTab:setEnabled(mode ~= controllerNpcTrader.SELL)
    end
    local toggleButton = self:findWidget("#toggleButton")
    if toggleButton then
        toggleButton:setText(mode == controllerNpcTrader.BUY and "Buy" or "Sell")
    end

    self.shouldFocusFirst = true
    self:updateListSource()
    self:refreshPlayerGoods(true)
end

function controllerNpcTrader:updateListSource()
    if self.tradeMode == controllerNpcTrader.BUY then
        self.allTradeItems = self.buyItems
    else
        self.allTradeItems = self.sellItems
    end
    self:filterTradeList(self.searchText or "")
end

function controllerNpcTrader:loadNextBatch()
    if not self.currentList then
        return
    end

    local total = #self.currentList
    local current = self.loadedItems
    if current >= total then
        return
    end

    local limit = math.min(total, current + self.itemBatchSize)
    for i = current + 1, limit do
        table.insert(self.tradeItems, self.currentList[i])
    end
    self.loadedItems = limit
end

function controllerNpcTrader:onTradeScroll(widget, offset)
    if self.loadedItems >= #self.currentList then
        return
    end
    local rowHeight = controllerNpcTrader.ITEM_ROW_HEIGHT
    local contentHeight = self.loadedItems * rowHeight
    local viewportHeight = widget:getHeight()
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    local value = offset.y
    if value >= maxScroll - controllerNpcTrader.SCROLL_THRESHOLD then
        self:loadNextBatch()
    end
end

function controllerNpcTrader:onTradeListRendered()
    local list = self:findWidget("#tradeListScroll")
    if list then
        if not list.onScrollEventConnected then
            list.onScrollChange = function(widget, offset)
                self:onTradeScroll(widget, offset)
            end
            list.onScrollEventConnected = true
        end
        for i = 1, list:getChildCount() do
            local child = list:getChildByIndex(i)
            local item = child.tradeitem or child.tradeItem or self.tradeItems[i]
            if item then
                child.tradeitem = item
                local canTrade = self:canTradeItem(item)
                child:setOpacity(canTrade and 1.0 or 0.45)
                local color = canTrade and '#c0c0c0' or '#707070'
                local infoBlock = child:getChildByIndex(2)
                if infoBlock then
                    local nameLabel = infoBlock:getChildById("nameLabel")
                    local infoLabel = infoBlock:getChildById("infoLabel")
                    if nameLabel then
                        nameLabel:setColor(color)
                    end
                    if infoLabel then
                        infoLabel:setColor(color)
                    end
                end

                child.onMouseRelease = function(widget, mousePos, mouseButton)
                    local currentItem = widget.tradeitem or widget.tradeItem or item
                    self:onTradeItemMouseRelease(currentItem, widget, mousePos, mouseButton)
                end
            end
        end
        if self.shouldFocusFirst then
            local firstChild = list:getChildByIndex(1)
            if firstChild then
                local firstItem = firstChild.tradeitem or firstChild.tradeItem or self.tradeItems[1]
                self:selectTradeItem(firstItem, firstChild)
            end
            self.shouldFocusFirst = false
        elseif self.selectedItem then
            for i = 1, list:getChildCount() do
                local child = list:getChildByIndex(i)
                if child.tradeitem == self.selectedItem or child.tradeItem == self.selectedItem then
                    child:focus()
                    break
                end
            end
        end
    end
end

function controllerNpcTrader:onTradeItemMouseRelease(item, widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption("Look", function()
            g_game.inspectNpcTrade(item.ptr)
        end)
        menu:addOption("Inspect", function()
            g_game.inspectionObject(InspectObjectTypes.INSPECT_CYCLOPEDIA, item.ptr:getId())
        end)
        menu:display(mousePos)
        return true
    elseif mouseButton == MouseLeftButton then
        self:selectTradeItem(item, widget)
        return true
    end
    return false
end

function controllerNpcTrader:selectTradeItem(item, widget)
    self.selectedItem = item
    if widget then
        widget:focus()
    end
    self:updateAmount(1)

    local scroll = self:findWidget("#amountScrollBar")
    if scroll then
        scroll:enable()
        scroll:setValue(1)
    end
end

function controllerNpcTrader:updateAmount(amount)
    amount = tonumber(amount) or 1
    if self.selectedItem then
        local maxAmount = controllerNpcTrader.MAX_AMOUNT_NORMAL
        local minAmount = controllerNpcTrader.MIN_AMOUNT
        if self.tradeMode == controllerNpcTrader.BUY then
            local playerMoney = self:getPlayerMoney()
            local maxByMoney = math.floor(playerMoney / self.selectedItem.price)
            local maxByCapacity = controllerNpcTrader.MAX_AMOUNT_NORMAL
            if not self.ignoreCapacity then
                local player = g_game.getLocalPlayer()
                local freeCapacity = player and player:getFreeCapacity() or 0
                local itemWeight = tonumber(self.selectedItem.weight) or 0
                maxByCapacity = itemWeight > 0 and math.floor(freeCapacity / itemWeight) or maxByCapacity
            end
            maxAmount = math.max(minAmount, math.min(controllerNpcTrader.MAX_AMOUNT_NORMAL, maxByMoney, maxByCapacity))
            if self.selectedItem.ptr and self.selectedItem.ptr:isStackable() then
                maxAmount = math.max(minAmount,
                    math.min(controllerNpcTrader.MAX_AMOUNT_STACKABLE, maxByMoney, maxByCapacity))
            end
        else
            local sellable = self:getSellQuantity(self.selectedItem.ptr)
            minAmount = sellable > 0 and controllerNpcTrader.MIN_AMOUNT or 0
            local maxPossible = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
            maxAmount = math.max(minAmount, math.min(maxPossible, sellable))
        end
        if amount > maxAmount then
            amount = maxAmount
        end
        if amount < minAmount then
            amount = minAmount
        end
        local scroll = self:findWidget("#amountScrollBar")
        if scroll then
            scroll:setMaximum(maxAmount)
            scroll:setMinimum(minAmount)
            if scroll:getValue() ~= amount then
                scroll:setValue(amount)
            end
        end
    end
    self.amount = amount
    if self.selectedItem then
        self.totalPrice = self.selectedItem.price * amount
        self.totalWeight = string.format("%.2f", self.selectedItem.weight * amount)
    else
        self.totalPrice = 0
        self.totalWeight = "0.00"
    end

    -- Update gold-after-trade in real time
    local currentMoney = self:getPlayerMoney()
    if self.tradeMode == controllerNpcTrader.BUY then
        self.goldAfterTrade = math.max(0, currentMoney - self.totalPrice)
    else
        self.goldAfterTrade = currentMoney + self.totalPrice
    end
end

function controllerNpcTrader:onAmountScrollBarChange(value)
    self:updateAmount(value)
end

function controllerNpcTrader:onAmountInputChange(event)
    local input = event.target
    local text = input:getText()
    local cleanText = text:gsub("[^%d]", "")
    if cleanText ~= text then
        input:setText(cleanText)
        text = cleanText
    end
    if text == "" then
        text = "1"
    end
    local amount = tonumber(text) or 1
    self:updateAmount(amount)
    local scroll = self:findWidget("#amountScrollBar")
    if scroll then
        if amount ~= self.amount then
            input:setText(tostring(self.amount))
        end
        scroll:setValue(self.amount)
    end
end

function controllerNpcTrader:getPlayerGoldCount()
    local player = g_game.getLocalPlayer()
    if not player then
        return 0
    end
    local gold = player:getItemsCount(3031)
    local platinum = player:getItemsCount(3035)
    local crystal = player:getItemsCount(3043)
    return gold + (platinum * 100) + (crystal * 10000)
end

function controllerNpcTrader:getPlayerMoney()
    if self.playerMoney ~= nil then
        return self.playerMoney
    end
    local player = g_game.getLocalPlayer()
    if not player then
        return 0
    end
    local goldCount = 0
    if self.currencyId == 3031 then
        goldCount = self:getPlayerGoldCount()
    else
        goldCount = player:getItemsCount(self.currencyId)
    end
    return goldCount
end

-- Equipped items with an active imbuement are already excluded from the goods
-- count the server sends (Item::hasMarketAttributes), so subtracting them again
-- here would hide sellable copies the player carries in containers.
function controllerNpcTrader:onUpdateEquippedImbuements(items)
    local counts = {}
    for _, entry in ipairs(items or {}) do
        local ptr = entry.item
        if ptr then
            local hasActiveImbuement = false
            for _, slot in pairs(entry.slots or {}) do
                if slot.duration and slot.duration > 0 then
                    hasActiveImbuement = true
                    break
                end
            end
            if hasActiveImbuement then
                local id = ptr:getId()
                counts[id] = (counts[id] or 0) + ptr:getCount()
            end
        end
    end
    self.equippedImbuedCounts = counts

    if self:isLegacyMode() then
        refreshPlayerGoods()
    elseif self.isTradeOpen then
        self:refreshPlayerGoods()
    end
end

function controllerNpcTrader:getEquippedImbuedCount(itemId)
    return (self.equippedImbuedCounts and self.equippedImbuedCounts[itemId]) or 0
end

function controllerNpcTrader:startEquippedImbuementsTracking()
    self.equippedImbuedCounts = {}
    if g_game.getClientVersion() >= 1100 then
        g_game.imbuementDurations(true)
    end
end

function controllerNpcTrader:stopEquippedImbuementsTracking()
    self.equippedImbuedCounts = {}
    if g_game.getClientVersion() < 1100 or not g_game.isOnline() then
        return
    end
    local tracker = modules.game_imbuementtracker
    local trackerOn = tracker and tracker.imbuementTrackerButton and tracker.imbuementTrackerButton:isOn() or false
    g_game.imbuementDurations(trackerOn)
end

function controllerNpcTrader:onPlayerFreeCapacityChange(player, freeCapacity, oldFreeCapacity)
    self.playerFreeCapacity = freeCapacity
    self:refreshPlayerGoods()
end

function controllerNpcTrader:onPlayerInventoryChange(inventory, item, oldItem)
    self:refreshPlayerGoods()
end

function controllerNpcTrader:connectPlayerEvents()
    if self.playerEventsConnected then
        return
    end

    local player = g_game.getLocalPlayer()
    if player then
        self.playerFreeCapacity = player:getFreeCapacity()
    end

    self.onFreeCapChange = function(p, freeCapacity, oldFreeCapacity)
        self:onPlayerFreeCapacityChange(p, freeCapacity, oldFreeCapacity)
    end
    self.onInvChange = function(inv, item, oldItem)
        self:onPlayerInventoryChange(inv, item, oldItem)
    end
    self.onContUpdate = function(container, slot, item, oldItem)
        self:refreshPlayerGoods()
    end
    self.onContChange = function(container)
        self:refreshPlayerGoods()
    end
    self.onTextMessageCallback = function(mode, text)
        self:onTextMessage(mode, text)
    end

    connect(LocalPlayer, {
        onFreeCapacityChange = self.onFreeCapChange,
        onInventoryChange = self.onInvChange
    })
    connect(Container, {
        onOpen = self.onContChange,
        onClose = self.onContChange,
        onSizeChange = self.onContChange,
        onUpdateItem = self.onContUpdate
    })
    
    registerMessageMode(MessageModes.None, self.onTextMessageCallback)
    registerMessageMode(MessageModes.TradeNpc, self.onTextMessageCallback)
    registerMessageMode(MessageModes.Status, self.onTextMessageCallback)
    
    self.playerEventsConnected = true
end

function controllerNpcTrader:disconnectPlayerEvents()
    if not self.playerEventsConnected then
        return
    end

    disconnect(LocalPlayer, {
        onFreeCapacityChange = self.onFreeCapChange,
        onInventoryChange = self.onInvChange
    })
    disconnect(Container, {
        onOpen = self.onContChange,
        onClose = self.onContChange,
        onSizeChange = self.onContChange,
        onUpdateItem = self.onContUpdate
    })
    
    if self.onTextMessageCallback then
        unregisterMessageMode(MessageModes.None, self.onTextMessageCallback)
        unregisterMessageMode(MessageModes.TradeNpc, self.onTextMessageCallback)
        unregisterMessageMode(MessageModes.Status, self.onTextMessageCallback)
        self.onTextMessageCallback = nil
    end

    self.playerEventsConnected = false
    self.onFreeCapChange = nil
    self.onInvChange = nil
    self.onContUpdate = nil
    self.onContChange = nil
end

function controllerNpcTrader:getSellQuantity(itemPtr)
    if not itemPtr then
        return 0
    end
    local id = itemPtr:getId()
    local subType = itemPtr:getSubType()
    local key = id .. "_" .. subType
    local inventoryTotal = 0

    if self.playerItems and self.playerItems[key] then
        inventoryTotal = self.playerItems[key]
    else
        local player = g_game.getLocalPlayer()
        if player then
            local items = player:getItems(id, subType)
            for i = 1, #items do
                inventoryTotal = inventoryTotal + items[i]:getCount()
            end
        end
    end

    if self.ignoreEquipped then
        local equippedCount = 0
        local player = g_game.getLocalPlayer()
        if player then
            for i = 1, 10 do
                local item = player:getInventoryItem(i)
                if item and item:getId() == id and item:getSubType() == subType then
                    equippedCount = equippedCount + item:getCount()
                end
            end
        end
        equippedCount = math.max(0, equippedCount - self:getEquippedImbuedCount(id))
        return math.max(0, inventoryTotal - equippedCount)
    end

    return inventoryTotal
end

function controllerNpcTrader:canTradeItem(item)
    if self.tradeMode == controllerNpcTrader.BUY then
        local playerMoney = self:getPlayerMoney()
        -- Add capacity check if needed, but for now we'll just check price
        return playerMoney >= item.price
    else
        return self:getSellQuantity(item.ptr) > 0
    end
end

function controllerNpcTrader:onPlayerGoods(money, items)
    self.playerMoney = money
    if items and type(items) == "table" then
        local newPlayerItems = {}
        for _, itemData in ipairs(items) do
            local ptr = itemData[1]
            local key = ptr:getId() .. "_" .. ptr:getSubType()
            local count = itemData[2]
            newPlayerItems[key] = (newPlayerItems[key] or 0) + count
        end
        self.playerItems = newPlayerItems
    end
    self:refreshPlayerGoods()
end

function controllerNpcTrader:refreshPlayerGoods(skipFilter)
    local money = self:getPlayerMoney()

    -- Recompute gold-after-trade with current balance
    if self.selectedItem and self.totalPrice then
        if self.tradeMode == controllerNpcTrader.BUY then
            self.goldAfterTrade = math.max(0, money - self.totalPrice)
        else
            self.goldAfterTrade = money + self.totalPrice
        end
    else
        self.goldAfterTrade = money
    end
    
    -- goldAfterTrade is updated reactively via {{self.goldAfterTrade}} binding
    
    local list = self:findWidget("#tradeListScroll")
    if list then
        for i = 1, list:getChildCount() do
            local child = list:getChildByIndex(i)
            local item = child.tradeitem or child.tradeItem
            if item then
                local canTrade = self:canTradeItem(item)
                child:setOpacity(canTrade and 1.0 or 0.45)
                local color = canTrade and '#c0c0c0' or '#707070'
                local infoBlock = child:getChildByIndex(2)
                if infoBlock then
                    local nameLabel = infoBlock:getChildById("nameLabel")
                    local infoLabel = infoBlock:getChildById("infoLabel")
                    if nameLabel then nameLabel:setColor(color) end
                    if infoLabel then infoLabel:setColor(color) end
                end
            end
        end
    end

    if not skipFilter and self.tradeMode == controllerNpcTrader.SELL then
        self:filterTradeList(self.searchText or "")
    end
    if self.selectedItem then
        self:updateAmount(self.amount)
    end
end

function controllerNpcTrader:onTextMessage(mode, text)
    if not self.isTradeOpen then
        return
    end
    if text:find("Sold ") or text:find("Bought ") or text:find("congrats") or text:find("sorry") or text:find("congratulations") then
        self:appendDialogMessage(text, '#ffaa00')
        
        -- Try to parse sold/bought amount to update balance mathematically
        local soldAmount = text:match("Sold .- for (%d+)")
        local boughtAmount = text:match("Bought .- for (%d+)")
        
        local currentMoney = self:getPlayerMoney()
        if soldAmount then
            self.playerMoney = currentMoney + tonumber(soldAmount)
        elseif boughtAmount then
            self.playerMoney = math.max(0, currentMoney - tonumber(boughtAmount))
        else
            self.playerMoney = nil -- fallback to query next time
        end
        
        self:refreshPlayerGoods()
    end
end

function controllerNpcTrader:clearTradeQueue()
    if self.tradeEvent then
        removeEvent(self.tradeEvent)
        self.tradeEvent = nil
    end
    self.tradeQueue = {}
end

function controllerNpcTrader:processTradeQueue()
    if not self.tradeQueue or #self.tradeQueue == 0 then
        self.tradeEvent = nil
        return
    end

    local action = table.remove(self.tradeQueue, 1)
    if action.type == 'buy' then
        g_game.buyItem(action.itemPtr, action.amount, action.ignoreCapacity, action.buyWithBackpack)
    elseif action.type == 'sell' then
        g_game.sellItem(action.itemPtr, action.amount, action.ignoreEquipped)
    end

    if #self.tradeQueue > 0 then
        self.tradeEvent = scheduleEvent(function()
            self:processTradeQueue()
        end, 1050)
    else
        self.tradeEvent = nil
    end
end

function controllerNpcTrader:executeTrade()
    if not self.selectedItem then
        return
    end
    self:clearTradeQueue()

    local maxAmountPerPacket = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
    local amountToTrade = self.amount
    if self.tradeMode == controllerNpcTrader.BUY then
        while amountToTrade > 0 do
            local chunk = math.min(amountToTrade, maxAmountPerPacket)
            table.insert(self.tradeQueue, {
                type = 'buy',
                itemPtr = self.selectedItem.ptr,
                amount = chunk,
                ignoreCapacity = self.ignoreCapacity,
                buyWithBackpack = self.buyWithBackpack
            })
            amountToTrade = amountToTrade - chunk
        end
    else
        while amountToTrade > 0 do
            local chunk = math.min(amountToTrade, maxAmountPerPacket)
            table.insert(self.tradeQueue, {
                type = 'sell',
                itemPtr = self.selectedItem.ptr,
                amount = chunk,
                ignoreEquipped = self.ignoreEquipped
            })
            amountToTrade = amountToTrade - chunk
        end
    end

    self:processTradeQueue()
end

function controllerNpcTrader:clearSearch()
    local input = self:findWidget(".tradeSearchInput")
    if input then
        input:setText("")
        self:filterTradeList("")
    end
end

function controllerNpcTrader:filterTradeList(searchText)
    if not self.allTradeItems then
        return
    end

    self.searchText = searchText
    local lowerSearch = searchText:lower()
    local filteredItems = {}

    for _, item in ipairs(self.allTradeItems) do
        local includeItem = true
        if searchText ~= "" and not item.name:lower():find(lowerSearch, 1, true) then
            includeItem = false
        end

        if includeItem then
            table.insert(filteredItems, item)
        end
    end

    if self.tradeMode == controllerNpcTrader.SELL then
        table.sort(filteredItems, function(a, b)
            local qtyA = self:getSellQuantity(a.ptr)
            local qtyB = self:getSellQuantity(b.ptr)
            if qtyA ~= qtyB then
                return qtyA > qtyB
            end
            if self.sortBy == 'price' then
                return a.price > b.price
            elseif self.sortBy == 'weight' then
                return a.weight > b.weight
            else
                return a.name:lower() < b.name:lower()
            end
        end)
    else
        self:sortTradeItems(filteredItems)
    end

    self.currentList = filteredItems
    self.tradeItems = {}
    self.loadedItems = 0
    self:loadNextBatch()

    if #self.currentList > 0 then
        local found = false
        if self.selectedItem then
            for _, item in ipairs(self.currentList) do
                if item == self.selectedItem then
                    found = true;
                    break
                end
            end
        end
        if not found then
            self:selectTradeItem(self.tradeItems[1])
        end
    else
        self.selectedItem = nil
        self:updateAmount(0)
    end
end

function controllerNpcTrader:sellAll(delayed, exceptions)
    if type(delayed) == "table" then
        exceptions = delayed
        delayed = false
    end
    exceptions = exceptions or {}

    if self.sellAllWithDelayEvent then
        removeEvent(self.sellAllWithDelayEvent)
        self.sellAllWithDelayEvent = nil
    end

    local queue = {}
    if not self.sellItems or #self.sellItems == 0 then
        return
    end

    for _, entry in ipairs(self.sellItems or {}) do
        local id = entry.ptr:getId()
        if not table.find(exceptions, id) then
            local sellQuantity = self:getSellQuantity(entry.ptr)
            while sellQuantity > 0 do
                local maxPossible = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
                local maxAmount = math.min(sellQuantity, maxPossible)

                if delayed then
                    g_game.sellItem(entry.ptr, maxAmount, self.ignoreEquipped)
                    self.sellAllWithDelayEvent = scheduleEvent(function()
                        self:sellAll(true, exceptions)
                    end, 1100)
                    return
                end

                table.insert(queue, {entry.ptr, maxAmount, self.ignoreEquipped})
                sellQuantity = sellQuantity - maxAmount
            end
        end
    end

    for _, entry in ipairs(queue) do
        g_game.sellItem(entry[1], entry[2], entry[3])
    end
end
