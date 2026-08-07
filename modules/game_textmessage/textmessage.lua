MessageSettings = {
    none = {},
    consoleYellow = {
        color = TextColors.yellow,
        consoleTab = 'Local Chat'
    },
    consoleRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat'
    },
    consoleOrange = {
        color = TextColors.orange,
        consoleTab = 'Local Chat'
    },
    consoleBlue = {
        color = TextColors.blue,
        consoleTab = 'Local Chat'
    },
    centerRed = {
        color = TextColors.red,
        consoleTab = 'Server Log',
        screenTarget = 'lowCenterLabel'
    },
    centerGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole'
    },
    centerHKGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showHotkeyMessagesInConsole'
    },
    centerWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'middleCenterLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    bottomWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    status = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusOwn = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusBoosted = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showBoostedMessagesInConsole'
    },
    othersStatus = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showOthersStatusMessagesInConsole'
    },
    statusSmall = {
        color = TextColors.white,
        screenTarget = 'statusLabel'
    },
    private = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        screenTarget = 'privateLabel'
    },
    privateRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToPlayer = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToNpc = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    privateNpcToPlayer = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    channelYellow = {
        color = TextColors.yellow
    },
    channelWhite = {
        color = TextColors.white
    },
    channelRed = {
        color = TextColors.red
    },
    channelOrange = {
        color = TextColors.orange
    },
    monsterSay = {
        color = TextColors.orange,
        hideInConsole = true
    },
    monsterYell = {
        color = TextColors.orange,
        hideInConsole = true
    },
    potion = {
        color = TextColors.orange,
        hideInConsole = true
    },
    loot = {
        color = TextColors.green,
        consoleTab = 'Loot',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    },
    valuableLoot = {
        color = TextColors.green,
        consoleTab = 'Loot',
        screenTarget = 'statusLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    },
    training = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'middleCenterLabel',
        consoleOption = 'trainingProgress'
    },
    store = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'middleCenterLabel',
        consoleOption = 'storeNotification'
    }
}

MessageTypes = {
    [MessageModes.Say] = MessageSettings.consoleYellow,
    [MessageModes.Whisper] = MessageSettings.consoleYellow,
    [MessageModes.Yell] = MessageSettings.consoleYellow,
    [MessageModes.MonsterSay] = MessageSettings.monsterSay,
    [MessageModes.MonsterYell] = MessageSettings.monsterYell,
    [MessageModes.BarkLow] = MessageSettings.consoleOrange,
    [MessageModes.BarkLoud] = MessageSettings.consoleOrange,
    [MessageModes.Failure] = MessageSettings.statusSmall,
    [MessageModes.Login] = MessageSettings.bottomWhite,
    [MessageModes.Game] = MessageSettings.centerWhite,
    [MessageModes.Status] = MessageSettings.status,
    [MessageModes.Warning] = MessageSettings.centerRed,
    [MessageModes.Look] = MessageSettings.centerGreen,
    [MessageModes.Loot] = MessageSettings.loot,
    [MessageModes.Red] = MessageSettings.consoleRed,
    [MessageModes.Blue] = MessageSettings.consoleBlue,
    [MessageModes.PrivateFrom] = MessageSettings.private,
    [MessageModes.PrivateTo] = MessageSettings.privatePlayerToPlayer,
    [MessageModes.GamemasterPrivateFrom] = MessageSettings.privateRed,
    [MessageModes.NpcTo] = MessageSettings.privatePlayerToNpc,
    [MessageModes.NpcFrom] = MessageSettings.privateNpcToPlayer,
    [MessageModes.NpcFromStartBlock] = MessageSettings.privateNpcToPlayer,
    [MessageModes.Channel] = MessageSettings.channelYellow,
    [MessageModes.ChannelManagement] = MessageSettings.channelWhite,
    [MessageModes.GamemasterChannel] = MessageSettings.channelRed,
    [MessageModes.ChannelHighlight] = MessageSettings.channelOrange,
    [MessageModes.Spell] = MessageSettings.consoleYellow,
    [MessageModes.RVRChannel] = MessageSettings.channelWhite,
    [MessageModes.RVRContinue] = MessageSettings.consoleYellow,

    [MessageModes.GamemasterBroadcast] = MessageSettings.consoleRed,

    [MessageModes.DamageDealed] = MessageSettings.statusOwn,
    [MessageModes.DamageReceived] = MessageSettings.statusOwn,
    [MessageModes.Heal] = MessageSettings.statusOwn,
    [MessageModes.Exp] = MessageSettings.statusOwn,

    [MessageModes.DamageOthers] = MessageSettings.statusOwn,
    [MessageModes.HealOthers] = MessageSettings.statusOwn,
    [MessageModes.ExpOthers] = MessageSettings.statusOwn,
    [MessageModes.Potion] = MessageSettings.potion,

    [MessageModes.TradeNpc] = MessageSettings.centerGreen,
    [MessageModes.Guild] = MessageSettings.statusOwn,
    [MessageModes.Party] = MessageSettings.statusOwn,
    [MessageModes.PartyManagement] = MessageSettings.centerGreen,
    [MessageModes.TutorialHint] = MessageSettings.statusSmall,
    [MessageModes.BeyondLast] = MessageSettings.centerWhite,
    [MessageModes.Report] = MessageSettings.centerWhite,
    [MessageModes.GameHighlight] = MessageSettings.centerRed,
    [MessageModes.HotkeyUse] = MessageSettings.centerHKGreen,
    [MessageModes.Attention] = MessageSettings.bottomWhite,
    [MessageModes.BoostedCreature] = MessageSettings.statusBoosted,
    [MessageModes.OfflineTrainning] = MessageSettings.training,
    [MessageModes.Transaction] = MessageSettings.store,
    [MessageModes.ValuableLoot] = MessageSettings.valuableLoot,

    [254] = MessageSettings.private
}

messagesPanel = nil

function init()
    for messageMode, _ in pairs(MessageTypes) do
        registerMessageMode(messageMode, displayMessage)
    end

    connect(g_game, 'onGameEnd', clearMessages)
    messagesPanel = g_ui.loadUI('textmessage', modules.game_interface.getRootPanel())
end

function terminate()
    for messageMode, _ in pairs(MessageTypes) do
        unregisterMessageMode(messageMode, displayMessage)
    end

    disconnect(g_game, 'onGameEnd', clearMessages)
    clearMessages()
    messagesPanel:destroy()
    messagesPanel = nil
end

function calculateVisibleTime(text)
    return math.max(#text * 50, 4000)
end

local function isOptionEnabled(key, defaultValue)
    -- Live option.value mirrors the checkbox; prefer it over g_settings.
    if modules.client_options and modules.client_options.getBoolOption then
        return modules.client_options.getBoolOption(key, defaultValue)
    end
    if g_settings.exists(key) then
        return g_settings.getBoolean(key)
    end
    return defaultValue and true or false
end

local function isHotkeyUsageText(text)
    if type(text) ~= 'string' then
        return false
    end
    local lower = text:lower()
    return lower:find('^using one of') ~= nil
        or lower:find('^using the last') ~= nil
end

local function isLootMessageText(text)
    if type(text) ~= 'string' then
        return false
    end
    local lower = text:lower()
    return lower:find('^loot of') ~= nil or lower:find('^loot de') ~= nil
end

function displayMessage(mode, text)

    if not g_game.isOnline() then
        return
    end
    if g_game.getClientVersion() >= 1300 then
        MessageTypes[MessageModes.Loot] = MessageSettings.loot
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.valuableLoot
        MessageTypes[MessageModes.Guild] = MessageSettings.statusOwn
        MessageTypes[MessageModes.Party] = MessageSettings.statusOwn
    else
        MessageTypes[MessageModes.Loot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Guild] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Party] = MessageSettings.centerGreen
        MessageTypes[MessageModes.MonsterSay] = MessageSettings.consoleOrange
        MessageTypes[MessageModes.MonsterYell] = MessageSettings.consoleOrange
    end
    local modeNum = tonumber(mode) or mode
    local msgtype = MessageTypes[modeNum] or MessageTypes[mode]
    if not msgtype then
        return
    end

    if msgtype == MessageSettings.none then
        return
    end

    -- Hotkey usage: some servers send HotkeyUse, others Look/Status with the same text.
    local isHotkeyMsg = modeNum == MessageModes.HotkeyUse
        or msgtype == MessageSettings.centerHKGreen
        or isHotkeyUsageText(text)
    if isHotkeyMsg and not isOptionEnabled('showHotkeyMessagesInConsole', true) then
        return
    end

    local isLootMsg = modeNum == MessageModes.Loot or modeNum == MessageModes.ValuableLoot
        or msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot
        or isLootMessageText(text)

    if msgtype.consoleTab ~= nil and
        (msgtype.consoleOption == nil or isOptionEnabled(msgtype.consoleOption, true)) then
        if isLootMsg then
            local lootColoredText = ItemsDatabase.setColorLootMessage(text)
            modules.game_console.addText(lootColoredText, msgtype, tr("Server Log"))
            modules.game_console.addText(lootColoredText, msgtype, tr(msgtype.consoleTab or 'Loot'))
        else
            modules.game_console.addText(text, msgtype, tr(msgtype.consoleTab))
        end
    end

    if msgtype.screenTarget then
        -- Master switch for on-screen messages (Game Window → Show Messages).
        if not isOptionEnabled('showMessages', true) then
            return
        end

        local label = messagesPanel:recursiveGetChildById(msgtype.screenTarget)
        if not label then
            return
        end

        if isLootMsg then
            if not isOptionEnabled('showLootMessagesOnScreen', true) then
                return
            end
            -- setColoredText uses the widget color as base for unmarked text.
            local lootColor = (msgtype.color) or TextColors.green
            label:setColor(lootColor)
            local coloredText = ItemsDatabase.setColorLootMessage(text, lootColor)
            if type(coloredText) == 'string' and coloredText:find('{.-,.+}') then
                label:setColoredText(coloredText)
            else
                label:setText(type(coloredText) == 'string' and coloredText or text)
            end
        elseif isHotkeyMsg then
            label:setText(text)
            label:setColor(TextColors.green)
        elseif msgtype == MessageSettings.statusBoosted then
            if not isOptionEnabled('showBoostedMessagesInConsole', true) then
                return
            end
            label:setText(text)
            label:setColor(msgtype.color)
        elseif msgtype == MessageSettings.training then
            if not isOptionEnabled('trainingProgress', true) then
                return
            end
            label:setText(text)
            label:setColor(msgtype.color)
        elseif msgtype == MessageSettings.store then
            if not isOptionEnabled('storeNotification', true) then
                return
            end
            label:setText(text)
            label:setColor(msgtype.color)
        else
            label:setText(text)
            label:setColor(msgtype.color)
        end

        label:setVisible(true)
        removeEvent(label.hideEvent)
        label.hideEvent = scheduleEvent(function()
            label:setVisible(false)
        end, calculateVisibleTime(text))
    end
end

function displayPrivateMessage(text)
    if not g_game.isOnline() then
        return
    end

    if not isOptionEnabled('showMessages', true) then
        return
    end
    if not isOptionEnabled('showPrivateMessagesOnScreen', true) then
        return
    end
    
    local msgtype = MessageSettings.private
    if not msgtype or not msgtype.screenTarget then
        return
    end
    
    local label = messagesPanel:recursiveGetChildById(msgtype.screenTarget)
    if not label then
        return
    end
    
    label:setText(text)
    label:setColor(msgtype.color)
    label:setVisible(true)
    removeEvent(label.hideEvent)
    label.hideEvent = scheduleEvent(function()
        label:setVisible(false)
    end, calculateVisibleTime(text))
end

function displayStatusMessage(text)
    displayMessage(MessageModes.Status, text)
end

function displayFailureMessage(text)
    displayMessage(MessageModes.Failure, text)
end

function displayGameMessage(text)
    displayMessage(MessageModes.Game, text)
end

function displayBroadcastMessage(text)
    displayMessage(MessageModes.Warning, text)
end

function clearMessages()
    for _i, child in pairs(messagesPanel:recursiveGetChildren()) do
        if child:getId():match('Label') then
            child:hide()
            removeEvent(child.hideEvent)
        end
    end
end

function LocalPlayer:onAutoWalkFail(player)
    modules.game_textmessage.displayFailureMessage(tr('There is no way.'))
end
