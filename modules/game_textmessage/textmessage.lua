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
        color = '#f0b400',
        consoleTab = 'Loot',
        screenTarget = 'middleCenterLabel',
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

local CENTER_LABEL_SLOTS = { 'highCenterLabel', 'middleCenterLabel', 'lowCenterLabel' }
local LOOT_CENTER_LABEL = 'lowCenterLabel'
local VALUABLE_LOOT_CENTER_LABEL = 'middleCenterLabel'
local NON_LOOT_CENTER_LABEL_SLOTS = { 'highCenterLabel', 'middleCenterLabel' }
local MAX_CENTER_MESSAGES_PER_MODE = 1
local PROTECTED_CENTER_MESSAGE_MODES = {
    [MessageModes.Loot] = true,
    [MessageModes.ValuableLoot] = true
}
local labelMessageSequence = 0

local function isLootMessageText(text)
    if type(text) ~= 'string' then
        return false
    end
    local lower = text:lower()
    return lower:find('^loot of') ~= nil or lower:find('^loot de') ~= nil
end

local function isUiWidgetValid(widget)
    if not widget then
        return false
    end
    if widget.isDestroyed then
        return not widget:isDestroyed()
    end
    return true
end

local function isCenterScreenTarget(targetId)
    for _, slotId in ipairs(CENTER_LABEL_SLOTS) do
        if slotId == targetId then
            return true
        end
    end
    return false
end

local function hideLabelMessage(label)
    if not isUiWidgetValid(label) then
        return
    end
    label:hide()
    removeEvent(label.hideEvent)
    label.hideEvent = nil
    label.gameMessageSeq = nil
    label.gameMessageMode = nil
    label.gameMessageIsLoot = nil
end

local function raiseMessagesPanel()
    if isUiWidgetValid(messagesPanel) then
        messagesPanel:raise()
    end
end

local function getCenterLabelById(labelId)
    if not messagesPanel or not labelId then
        return nil
    end
    return messagesPanel:recursiveGetChildById(labelId)
end

local function isProtectedCenterLabel(label)
    if not label then
        return false
    end
    if label.gameMessageIsLoot then
        return true
    end
    if PROTECTED_CENTER_MESSAGE_MODES[label.gameMessageMode] then
        return true
    end
    return isLootMessageText(label:getText())
end

local function findOldestVisibleCenterLabel(excludeProtected)
    local oldestLabel, oldestSeq
    for _, slotId in ipairs(CENTER_LABEL_SLOTS) do
        local label = getCenterLabelById(slotId)
        if label and label:isVisible() and label.gameMessageSeq then
            if excludeProtected and isProtectedCenterLabel(label) then
                goto continue
            end
            if not oldestSeq or label.gameMessageSeq < oldestSeq then
                oldestLabel = label
                oldestSeq = label.gameMessageSeq
            end
        end
        ::continue::
    end
    return oldestLabel
end

local function allocateCenterLabel(preferredOrder, excludeProtected)
    preferredOrder = preferredOrder or CENTER_LABEL_SLOTS
    for _, slotId in ipairs(preferredOrder) do
        local label = getCenterLabelById(slotId)
        if label and not label:isVisible() then
            return label
        end
    end

    local oldestLabel = findOldestVisibleCenterLabel(excludeProtected)
    if oldestLabel then
        hideLabelMessage(oldestLabel)
        return oldestLabel
    end

    return getCenterLabelById(preferredOrder[1])
end

local function getVisibleCenterLabels()
    local labels = {}
    for _, slotId in ipairs(CENTER_LABEL_SLOTS) do
        local label = getCenterLabelById(slotId)
        if label and label:isVisible() then
            table.insert(labels, label)
        end
    end
    return labels
end

local function findCenterLabelByText(text, excludeProtected)
    for _, label in ipairs(getVisibleCenterLabels()) do
        if excludeProtected and isProtectedCenterLabel(label) then
            goto continue
        end
        if label:getText() == text then
            return label
        end
        ::continue::
    end
    return nil
end

local function findCenterLabelsByMode(modeNum, excludeProtected)
    local labels = {}
    for _, label in ipairs(getVisibleCenterLabels()) do
        if excludeProtected and isProtectedCenterLabel(label) then
            goto continue
        end
        if label.gameMessageMode == modeNum then
            table.insert(labels, label)
        end
        ::continue::
    end
    table.sort(labels, function(a, b)
        return (a.gameMessageSeq or 0) > (b.gameMessageSeq or 0)
    end)
    return labels
end

local function resolveCenterLabel(modeNum, text)
    local excludeProtected = not PROTECTED_CENTER_MESSAGE_MODES[modeNum]

    local sameTextLabel = findCenterLabelByText(text, excludeProtected)
    if sameTextLabel then
        return sameTextLabel
    end

    local modeLabels = findCenterLabelsByMode(modeNum, excludeProtected)
    if #modeLabels >= MAX_CENTER_MESSAGES_PER_MODE then
        return modeLabels[1]
    end

    local preferredSlots = excludeProtected and NON_LOOT_CENTER_LABEL_SLOTS or CENTER_LABEL_SLOTS
    return allocateCenterLabel(preferredSlots, excludeProtected)
end

local function getStorageModeNum(modeNum, isLootMsg)
    if not isLootMsg then
        return modeNum
    end
    if modeNum == MessageModes.ValuableLoot then
        return MessageModes.ValuableLoot
    end
    return MessageModes.Loot
end

local function showScreenMessage(label, text, color, useColoredLoot, modeNum, isLootMsg)
    if not isUiWidgetValid(label) then
        return
    end

    label:setColor(color or TextColors.white)
    if useColoredLoot then
        local coloredText = ItemsDatabase.setColorLootMessage(text, color or TextColors.green)
        if type(coloredText) == 'string' and coloredText:find('{.-,.+}') then
            label:setColoredText(coloredText)
        else
            label:setText(type(coloredText) == 'string' and coloredText or text)
        end
    else
        label:setText(text)
    end

    label:setVisible(true)
    raiseMessagesPanel()
    removeEvent(label.hideEvent)

    labelMessageSequence = labelMessageSequence + 1
    label.gameMessageSeq = labelMessageSequence
    label.gameMessageIsLoot = isLootMsg or false
    local storageModeNum = getStorageModeNum(modeNum, isLootMsg)
    if storageModeNum ~= nil then
        label.gameMessageMode = storageModeNum
    end

    label.hideEvent = scheduleEvent(function()
        hideLabelMessage(label)
    end, calculateVisibleTime(text))
end

local function isHotkeyUsageText(text)
    if type(text) ~= 'string' then
        return false
    end
    local lower = text:lower()
    return lower:find('^using one of') ~= nil
        or lower:find('^using the last') ~= nil
end

local function showCenterScreenMessage(modeNum, text, msgtype, isLootMsg)
    local displayColor = msgtype.color
    local useColoredLoot = false

    if isLootMsg then
        displayColor = msgtype.color or TextColors.green
        useColoredLoot = true
    elseif modeNum == MessageModes.HotkeyUse
        or msgtype == MessageSettings.centerHKGreen
        or isHotkeyUsageText(text) then
        displayColor = TextColors.green
    end

    local label
    if modeNum == MessageModes.ValuableLoot then
        label = getCenterLabelById(VALUABLE_LOOT_CENTER_LABEL)
    elseif isLootMsg then
        label = getCenterLabelById(LOOT_CENTER_LABEL)
    else
        label = resolveCenterLabel(modeNum, text)
    end

    if not label then
        return
    end

    showScreenMessage(label, text, displayColor, useColoredLoot, modeNum, isLootMsg)
end

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

local function getLootConsoleSpeaktype(msgtype)
    if msgtype and msgtype.colored then
        return msgtype
    end
    return {
        color = (msgtype and msgtype.color) or TextColors.green,
        consoleTab = msgtype and msgtype.consoleTab,
        consoleOption = msgtype and msgtype.consoleOption,
        colored = true
    }
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
            local lootSpeaktype = getLootConsoleSpeaktype(msgtype)
            local serverLogTab = tr("Server Log")
            local lootTab = tr(msgtype.consoleTab or 'Loot')
            modules.game_console.addText(lootColoredText, lootSpeaktype, serverLogTab)
            if lootTab ~= serverLogTab then
                modules.game_console.addText(lootColoredText, lootSpeaktype, lootTab)
            end
        else
            modules.game_console.addText(text, msgtype, tr(msgtype.consoleTab))
        end
    end

    local screenTargetId = msgtype.screenTarget
    if isLootMsg and not screenTargetId then
        screenTargetId = CENTER_LABEL_SLOTS[1]
    end

    if screenTargetId then
        -- Master switch for on-screen messages (Game Window → Show Messages).
        if not isOptionEnabled('showMessages', true) then
            return
        end

        if isLootMsg and not isOptionEnabled('showLootMessagesOnScreen', true) then
            return
        end
        if msgtype == MessageSettings.statusBoosted
            and not isOptionEnabled('showBoostedMessagesInConsole', true) then
            return
        end
        if msgtype == MessageSettings.training
            and not isOptionEnabled('trainingProgress', true) then
            return
        end
        if msgtype == MessageSettings.store
            and not isOptionEnabled('storeNotification', true) then
            return
        end

        if isLootMsg or isCenterScreenTarget(screenTargetId) then
            showCenterScreenMessage(modeNum, text, msgtype, isLootMsg)
        else
            local label = messagesPanel:recursiveGetChildById(screenTargetId)
            if not label then
                return
            end

            local displayColor = msgtype.color
            if isHotkeyMsg then
                displayColor = TextColors.green
            end

            showScreenMessage(label, text, displayColor, false)
        end
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
    
    showScreenMessage(label, text, msgtype.color, false)
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
    labelMessageSequence = 0

    if not messagesPanel then
        return
    end

    for _i, child in pairs(messagesPanel:recursiveGetChildren()) do
        if child:getId():match('Label') then
            child:hide()
            removeEvent(child.hideEvent)
            child.hideEvent = nil
            child.gameMessageSeq = nil
            child.gameMessageMode = nil
            child.gameMessageIsLoot = nil
        end
    end
end

function LocalPlayer:onAutoWalkFail(player)
    modules.game_textmessage.displayFailureMessage(tr('There is no way.'))
end
