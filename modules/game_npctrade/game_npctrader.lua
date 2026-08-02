controllerNpcTrader = Controller:new()
controllerNpcTrader.widthConsole = controllerNpcTrader.DEFAULT_CONSOLE_WIDTH
controllerNpcTrader.creatureName = ""
controllerNpcTrader.outfit = nil
controllerNpcTrader.buttons = {}
controllerNpcTrader.isTradeOpen = false
controllerNpcTrader.legacyMode = false
controllerNpcTrader.npcTalkConnected = false
controllerNpcTrader.isMerchantDetected = false

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

controllerNpcTrader.short_text = short_text
_G.short_text = short_text

function controllerNpcTrader:isLegacyMode()
    return self.legacyMode
end

function controllerNpcTrader:onInit()

end

function controllerNpcTrader:onGameStart()
    self.legacyMode = not g_game.getFeature(GameNpcWindowRedesign)
    if self:isLegacyMode() then
        self:legacy_init()
    end

    self:registerEvents(g_game, {
        onTalk = function(name, level, mode, text, channelId, creaturePos)
            local shouldOpen = false
            if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
                self.lastNpcName = name
                if not self.ui or not self.ui:isVisible() then
                    local now = os.clock()
                    if not self.closedAt or (now - self.closedAt) > 2 then
                        shouldOpen = true
                    end
                end
            elseif mode == MessageModes.NpcTo then
                local lowerText = text:lower()
                if lowerText == "hi" or lowerText == "hello" or lowerText == "hola" then
                    if not self.ui or not self.ui:isVisible() then
                        shouldOpen = true
                    end
                end
            end

            if shouldOpen and not self:isLegacyMode() then
                addEvent(function()
                    self:initNpcWindow()
                    if onNpcTalk then
                        onNpcTalk(name, level, mode, text, channelId, creaturePos)
                    end
                end)
            end
        end,
        onNpcChatWindow = function(data)
            onNpcChatWindow(data)
        end,
        onOpenNpcTrade = function(...)
            self:startEquippedImbuementsTracking()
            if self:isLegacyMode() then
                onOpenNpcTrade(...)
            else
                self:onOpenNpcTrade(...)
            end
        end,
        onPlayerGoods = function(money, items)
            if self:isLegacyMode() then
                onPlayerGoods(money, items)
            else
                self:onPlayerGoods(money, items)
            end
        end,
        onUpdateImbuementTracker = function(items)
            self:onUpdateEquippedImbuements(items)
        end,
        onNpcChatWindowClose = function()
            self:stopEquippedImbuementsTracking()
            if self:isLegacyMode() then
                self:legacy_hide()
            else
                self:onCloseNpcTrade()
            end
        end,
        onCloseNpcTrade = function()
            self:stopEquippedImbuementsTracking()
            if self:isLegacyMode() then
                self:legacy_hide()
            else
                self:onCloseNpcTrade()
            end
        end
    })
end

function controllerNpcTrader:connectNpcTalkEvent()
    if self:isLegacyMode() or self.npcTalkConnected then
        return
    end

    connect(g_game, {
        onTalk = onNpcTalk
    })
    self.npcTalkConnected = true
end

function controllerNpcTrader:disconnectNpcTalkEvent()
    if not self.npcTalkConnected then
        return
    end

    disconnect(g_game, {
        onTalk = onNpcTalk
    })
    self.npcTalkConnected = false
end

function controllerNpcTrader:onTerminate()
    if self:isLegacyMode() then
        self:legacy_terminate()
    else
        self:onCloseNpcTrade()
    end
end

function controllerNpcTrader:onGameEnd()
    self:stopEquippedImbuementsTracking()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:onCloseNpcTrade()
    end
end

function controllerNpcTrader:onCloseNpcTrade()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:disconnectNpcTalkEvent()
        self:disconnectPlayerEvents()
        if self.positionChangeConnected then
            disconnect(LocalPlayer, { onPositionChange = self.onPlayerPositionChange })
            self.positionChangeConnected = false
            self.onPlayerPositionChange = nil
        end
        if g_tooltip then
            g_tooltip.hide()
            g_tooltip.hideSpecial()
        end
        if controllerNpcTrader.ui and controllerNpcTrader.ui:isVisible() then
            controllerNpcTrader:unloadHtml()
        end
        controllerNpcTrader.isTradeOpen = false
        if controllerNpcTrader.sellAllWithDelayEvent then
            removeEvent(controllerNpcTrader.sellAllWithDelayEvent)
            controllerNpcTrader.sellAllWithDelayEvent = nil
        end
        if controllerNpcTrader.clearTradeQueue then
            controllerNpcTrader:clearTradeQueue()
        end
        -- Clean up state
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.playerItems = {}
        controllerNpcTrader.playerMoney = nil
        controllerNpcTrader.selectedItem = nil
        controllerNpcTrader.tradeItems = {}
        controllerNpcTrader.currentList = {}
        controllerNpcTrader.allTradeItems = {}
        controllerNpcTrader.isBankerDetected = false
        controllerNpcTrader.isTravelDetected = false
        controllerNpcTrader.isMerchantDetected = false
        controllerNpcTrader.npcCreature = nil
        controllerNpcTrader.buttons = {}
        controllerNpcTrader.closedAt = os.clock()
    end
end

function sellAll(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        sellAllLegacy(...)
    else
        controllerNpcTrader:sellAll(...)
    end
end

function isTrading(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return isTradingLegacy(...)
    end

    return controllerNpcTrader.isTradeOpen == true
end

function getSellItems(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getSellItemsLegacy(...)
    end

    return controllerNpcTrader.sellItems or {}
end

function getBuyItems(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getBuyItemsLegacy(...)
    end

    return controllerNpcTrader.buyItems or {}
end

function getSellQuantity(item) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getSellQuantityLegacy(item)
    end

    if type(item) == 'number' then
        item = Item.create(item)
    end

    return controllerNpcTrader:getSellQuantity(item)
end

function canTradeItem(item) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return canTradeItemLegacy(item)
    end

    if type(item) == 'number' then
        item = Item.create(item)
    end

    local tradeEntry = item
    if item and not item.ptr then
        for _, entry in ipairs(controllerNpcTrader.sellItems or {}) do
            if entry.ptr:getId() == item:getId() and entry.ptr:getSubType() == item:getSubType() then
                tradeEntry = entry
                break
            end
        end

        if tradeEntry == item then
            for _, entry in ipairs(controllerNpcTrader.buyItems or {}) do
                if entry.ptr:getId() == item:getId() and entry.ptr:getSubType() == item:getSubType() then
                    tradeEntry = entry
                    break
                end
            end
        end
    end

    if not tradeEntry or not tradeEntry.ptr then
        return false
    end

    return controllerNpcTrader:canTradeItem(tradeEntry)
end

function closeNpcTrade(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return closeNpcTradeLegacy(...)
    end

    return g_game.closeNpcTrade()
end
