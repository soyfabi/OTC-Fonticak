local actionNameLimit = 39
local changedOptions = {}
local changedKeybinds = {}
local presetWindow = nil
local actionSearchEvent
keyEditWindow = nil
local chatModeGroup
local syncingChatModeUI = false

local function getKeyColumnText(column)
    if column.value then
        return column.value:getText()
    end
    return column:getText()
end

local function setKeyColumnText(column, text)
    text = text or ''
    if column.value then
        column.value:setText(text)
    else
        column:setText(text)
    end
end

local function clearConflictingGeneralKeybinds(keyCombo, category, action, chatMode, preset)
    if not keyCombo or keyCombo == '' then
        return false
    end

    local cleared = false
    for _, keybind in pairs(Keybind.defaultKeybinds) do
        if keybind.category ~= category or keybind.action ~= action then
            local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, preset)
            if keys.primary == keyCombo then
                Keybind.setPrimaryActionKey(keybind.category, keybind.action, preset, '', chatMode)
                cleared = true
            end
            if keys.secondary == keyCombo then
                Keybind.setSecondaryActionKey(keybind.category, keybind.action, preset, '', chatMode)
                cleared = true
            end
        end
    end

    return cleared
end

local function clearConflictingCustomHotkeys(keyCombo, chatMode, preset)
    if not keyCombo or keyCombo == '' then
        return false
    end

    local hotkeys = Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][preset]
    if not hotkeys then
        return false
    end

    local cleared = false
    for _, hotkey in ipairs(hotkeys) do
        if hotkey.primary == keyCombo or hotkey.secondary == keyCombo then
            local primary = hotkey.primary == keyCombo and '' or hotkey.primary
            local secondary = hotkey.secondary == keyCombo and '' or hotkey.secondary
            Keybind.editHotkeyKeys(hotkey.hotkeyId, primary, secondary, chatMode)
            cleared = true
        end
    end

    if cleared and updateCustomHotkeys then
        updateCustomHotkeys()
    end

    return cleared
end

local function clearConflictingActionbarHotkey(keyCombo)
    if not keyCombo or keyCombo == '' then
        return false
    end

    if modules.game_actionbar and modules.game_actionbar.removeHotkeyFromActionBar then
        modules.game_actionbar.removeHotkeyFromActionBar(keyCombo)
    end

    if modules.game_hotkeys and modules.game_hotkeys.removeHotkeyByCombo then
        modules.game_hotkeys.removeHotkeyByCombo(keyCombo)
    end

    return true
end

-- controls and keybinds
function addNewPreset()
    presetWindow:setText(tr('Add hotkey preset'))

    presetWindow.info:setText(tr('Enter a name for the new preset:'))

    presetWindow.field:clearText()
    presetWindow.field:show()
    presetWindow.field:focus()

    presetWindow:setWidth(360)

    presetWindow.action = 'add'

    presetWindow:show()
    presetWindow:raise()
    presetWindow:focus()

    controller.ui:hide()
end

function copyPreset()
    presetWindow:setText(tr('Copy hotkey preset'))

    presetWindow.info:setText(tr('Enter a name for the new preset:'))

    presetWindow.field:clearText()
    presetWindow.field:show()
    presetWindow.field:focus()

    presetWindow.action = 'copy'

    presetWindow:setWidth(360)
    presetWindow:show()
    presetWindow:raise()
    presetWindow:focus()

    controller.ui:hide()
end

function renamePreset()
    presetWindow:setText(tr('Rename hotkey preset'))

    presetWindow.info:setText(tr('Enter a name for the preset:'))

    presetWindow.field:setText(panels.keybindsPanel.presets.list:getCurrentOption().text)
    presetWindow.field:setCursorPos(1000)
    presetWindow.field:show()
    presetWindow.field:focus()

    presetWindow.action = 'rename'

    presetWindow:setWidth(360)
    presetWindow:show()
    presetWindow:raise()
    presetWindow:focus()

    controller.ui:hide()
end

function removePreset()
    presetWindow:setText(tr('Warning'))

    presetWindow.info:setText(tr('Do you really want to delete the hotkey preset %s?',
        panels.keybindsPanel.presets.list:getCurrentOption().text))
    presetWindow.field:hide()
    presetWindow.action = 'remove'

    presetWindow:setWidth(presetWindow.info:getTextSize().width + presetWindow:getPaddingLeft() +
        presetWindow:getPaddingRight())
    presetWindow:show()
    presetWindow:raise()
    presetWindow:focus()

    controller.ui:hide()
end

function okPresetWindow()
    local presetName = presetWindow.field:getText():trim()
    local selectedPreset = panels.keybindsPanel.presets.list:getCurrentOption().text

    presetWindow:hide()
    show()

    if presetWindow.action == 'add' then
        Keybind.newPreset(presetName)
        if modules.game_actionbar and modules.game_actionbar.createHotkeySet then
            modules.game_actionbar.createHotkeySet(presetName, nil)
        end
        panels.keybindsPanel.presets.list:addOption(presetName)
        panels.keybindsPanel.presets.list:setCurrentOption(presetName)
        if panels.customHotkeys then
            panels.customHotkeys.presets.list:addOption(presetName)
            panels.customHotkeys.presets.list:setCurrentOption(presetName)
        end
    elseif presetWindow.action == 'copy' then
        if not Keybind.copyPreset(selectedPreset, presetName) then
            return
        end
        if modules.game_actionbar and modules.game_actionbar.createHotkeySet then
            modules.game_actionbar.createHotkeySet(presetName, selectedPreset)
        end
        panels.keybindsPanel.presets.list:addOption(presetName)
        panels.keybindsPanel.presets.list:setCurrentOption(presetName)
        if panels.customHotkeys then
            panels.customHotkeys.presets.list:addOption(presetName)
            panels.customHotkeys.presets.list:setCurrentOption(presetName)
        end
    elseif presetWindow.action == 'rename' then
        if selectedPreset ~= presetName then
            panels.keybindsPanel.presets.list:updateCurrentOption(presetName)
            if panels.customHotkeys then
                panels.customHotkeys.presets.list:updateCurrentOption(presetName)
            end
            if changedOptions['currentPreset'] then
                changedOptions['currentPreset'].value = presetName
            end
            Keybind.renamePreset(selectedPreset, presetName)
            if modules.game_actionbar and modules.game_actionbar.renameHotkeySet then
                modules.game_actionbar.renameHotkeySet(selectedPreset, presetName)
            end
        end
    elseif presetWindow.action == 'remove' then
        if Keybind.removePreset(selectedPreset) then
            panels.keybindsPanel.presets.list:removeOption(selectedPreset)
            if panels.customHotkeys then
                panels.customHotkeys.presets.list:removeOption(selectedPreset)
            end
            if modules.game_actionbar and modules.game_actionbar.removeHotkeySet then
                modules.game_actionbar.removeHotkeySet(selectedPreset)
                if modules.game_actionbar.selectHotkeySet then
                    modules.game_actionbar.selectHotkeySet(Keybind.currentPreset)
                end
            end
        end
    end
end

function cancelPresetWindow()
    presetWindow:hide()
    show()
end

-- Shows the combo in the key edit window and highlights it in light yellow
-- while a key is assigned (gray when empty).
function setKeyComboText(keyCombo)
    keyEditWindow.keyCombo:setText(keyCombo)
    if keyCombo == nil or keyCombo == "" then
        keyEditWindow.keyCombo:setColor("#c0c0c0")
    else
        keyEditWindow.keyCombo:setColor("#ffff66")
    end
end

-- Applies a captured combo (keyboard or mouse) to the keybind edit window
-- and runs the conflict checks.
local function disconnectKeyEditListeners()
    disconnect(keyEditWindow, {
        onKeyDown = editKeybindKeyDown
    })
    disconnect(keyEditWindow, {
        onMousePress = editKeybindMouse
    })
end

local function isKeyEditAssignMousePos(widget, mousePos)
    if not widget or not mousePos then
        return false
    end

    local clickedWidget = widget:recursiveGetChildByPos(mousePos, false)
    if not clickedWidget then
        return true
    end

    local current = clickedWidget
    while current and current ~= widget do
        if current.getClassName then
            local className = current:getClassName()
            if className == 'UIButton' or className == 'UICheckBox' or className == 'UIComboBox' then
                return false
            end
        end
        current = current:getParent()
    end

    return true
end

function editKeybindSetCombo(keyCombo)
    setKeyComboText(keyCombo)

    local keybind = keyEditWindow.keybind
    local category = keybind and keybind.category
    local action = keybind and keybind.action
    local chatMode = getChatMode()

    local reserved = Keybind.reservedKeys[keyCombo]
    local keyUsed = not reserved and keyCombo ~= '' and Keybind.isKeyComboUsed(keyCombo, category, action, chatMode)

    keyEditWindow.used:setVisible(reserved or keyUsed)
    if reserved then
        keyEditWindow.used:setText(tr('This hotkey is already in use and cannot be overwritten.'))
        keyEditWindow.buttons.ok:setEnabled(false)
    elseif keyUsed then
        keyEditWindow.used:setText(Keybind.formatKeyComboOverwriteMessage(keyCombo, category, action, chatMode))
        keyEditWindow.buttons.ok:setEnabled(true)
    else
        keyEditWindow.used:setVisible(false)
        keyEditWindow.buttons.ok:setEnabled(true)
    end
end

function editKeybindKeyDown(widget, keyCode, keyboardModifiers)
    editKeybindSetCombo(determineKeyComboDesc(keyCode,
        keyEditWindow.alone:isVisible() and KeyboardNoModifier or keyboardModifiers))
end

function editKeybindMouse(widget, mousePos, button)
    if not isKeyEditAssignMousePos(widget, mousePos) then
        return false
    end

    local keyCombo = Keybind.getMouseKeyCombo(button, g_keyboard.getModifiers())
    if not keyCombo then
        return false
    end
    editKeybindSetCombo(keyCombo)
    return true
end

function editKeybind(keybind)
    keyEditWindow.buttons.cancel.onClick = function()
        disconnectKeyEditListeners()
        keyEditWindow:hide()
        keyEditWindow:ungrabKeyboard()
        show()
    end

    keyEditWindow.info:setText(tr(
        'Click \'Ok\' to assign the keybind. Click \'Clear\' to remove the keybind from \'%s: %s\'.', keybind.category,
        keybind.action))
    keyEditWindow.alone:setVisible(keybind.alone)

    connect(keyEditWindow, {
        onKeyDown = editKeybindKeyDown
    })
    connect(keyEditWindow, {
        onMousePress = editKeybindMouse
    })

    keyEditWindow:show()
    keyEditWindow:raise()
    keyEditWindow:focus()
    keyEditWindow:grabKeyboard()
    hide()
end

function editKeybindPrimary(button)
    local column = button:getParent()
    local row = column:getParent()
    local index = row.category .. '_' .. row.action
    local keybind = Keybind.getAction(row.category, row.action)
    local preset = panels.keybindsPanel.presets.list:getCurrentOption().text

    keyEditWindow.keybind = {
        category = row.category,
        action = row.action
    }

    keyEditWindow:setText(tr('Edit Primary Key for \'%s\'', string.format('%s: %s', keybind.category, keybind.action)))
    editKeybindSetCombo(Keybind.getKeybindKeys(row.category, row.action, getChatMode(), preset).primary)

    editKeybind(keybind)

    keyEditWindow.buttons.ok.onClick = function()
        local keyCombo = keyEditWindow.keyCombo:getText()

        setKeyColumnText(column, Keybind.formatKeyComboForDisplay(keyCombo))

        if not changedKeybinds[preset] then
            changedKeybinds[preset] = {}
        end
        if not changedKeybinds[preset][index] then
            changedKeybinds[preset][index] = {}
        end
        changedKeybinds[preset][index].primary = {
            category = row.category,
            action = row.action,
            keyCombo = keyCombo
        }

        disconnectKeyEditListeners()
        keyEditWindow:hide()
        keyEditWindow:ungrabKeyboard()
        show()
        applyChangedOptions()
    end

    keyEditWindow.buttons.clear.onClick = function()
        if not changedKeybinds[preset] then
            changedKeybinds[preset] = {}
        end
        if not changedKeybinds[preset][index] then
            changedKeybinds[preset][index] = {}
        end
        changedKeybinds[preset][index].primary = {
            category = row.category,
            action = row.action,
            keyCombo = ''
        }

        setKeyColumnText(column, '')

        disconnectKeyEditListeners()
        keyEditWindow:hide()
        keyEditWindow:ungrabKeyboard()
        show()
        applyChangedOptions()
    end
end

function editKeybindSecondary(button)
    local column = button:getParent()
    local row = column:getParent()
    local index = row.category .. '_' .. row.action
    local keybind = Keybind.getAction(row.category, row.action)
    local preset = panels.keybindsPanel.presets.list:getCurrentOption().text

    keyEditWindow.keybind = {
        category = row.category,
        action = row.action
    }

    keyEditWindow:setText(tr('Edit Secondary Key for \'%s\'', string.format('%s: %s', keybind.category, keybind.action)))
    editKeybindSetCombo(Keybind.getKeybindKeys(row.category, row.action, getChatMode(), preset).secondary)

    editKeybind(keybind)

    keyEditWindow.buttons.ok.onClick = function()
        local keyCombo = keyEditWindow.keyCombo:getText()

        setKeyColumnText(column, Keybind.formatKeyComboForDisplay(keyCombo))

        if not changedKeybinds[preset] then
            changedKeybinds[preset] = {}
        end
        if not changedKeybinds[preset][index] then
            changedKeybinds[preset][index] = {}
        end
        changedKeybinds[preset][index].secondary = {
            category = row.category,
            action = row.action,
            keyCombo = keyCombo
        }

        disconnectKeyEditListeners()
        keyEditWindow:hide()
        keyEditWindow:ungrabKeyboard()
        show()
        applyChangedOptions()
    end

    keyEditWindow.buttons.clear.onClick = function()
        if not changedKeybinds[preset] then
            changedKeybinds[preset] = {}
        end
        if not changedKeybinds[preset][index] then
            changedKeybinds[preset][index] = {}
        end
        changedKeybinds[preset][index].secondary = {
            category = row.category,
            action = row.action,
            keyCombo = ''
        }

        setKeyColumnText(column, '')

        disconnectKeyEditListeners()
        keyEditWindow:hide()
        keyEditWindow:ungrabKeyboard()
        show()
        applyChangedOptions()
    end
end

function resetActions()
    changedOptions['resetKeybinds'] = {
        value = panels.keybindsPanel.presets.list:getCurrentOption().text
    }
    updateKeybinds()
    applyChangedOptions()
end

function updateKeybinds()
    panels.keybindsPanel.tablePanel.keybinds:clearData()

    local sortedKeybinds = {}

    for index, _ in pairs(Keybind.defaultKeybinds) do
        table.insert(sortedKeybinds, index)
    end

    table.sort(sortedKeybinds, function(a, b)
        local keybindA = Keybind.defaultKeybinds[a]
        local keybindB = Keybind.defaultKeybinds[b]

        if keybindA.category ~= keybindB.category then
            return keybindA.category < keybindB.category
        end
        return keybindA.action < keybindB.action
    end)


    local comboBox = panels.keybindsPanel.presets.list:getCurrentOption()
    if not comboBox then
        return
    end
    for _, index in ipairs(sortedKeybinds) do
        local keybind = Keybind.defaultKeybinds[index]
        local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, getChatMode(), comboBox.text,
            changedOptions['resetKeybinds'])
        addKeybind(keybind.category, keybind.action, keys.primary, keys.secondary)
    end
end

function addKeybind(category, action, primary, secondary)
    local rawText = string.format('%s: %s', category, action)
    local text = string.format('[color=#ffffff]%s:[/color] %s', category, action)
    local tooltip = nil

    if rawText:len() > actionNameLimit then
        tooltip = rawText
        -- 15 and 8 are length of color codes
        text = text:sub(1, actionNameLimit + 15 + 8) .. '...'
    end

    local row = panels.keybindsPanel.tablePanel.keybinds:addRow({ {
        coloredText = {
            text = text,
            color = '#c0c0c0'
        },
        width = 286
    }, {
        style = 'VerticalSeparator'
    }, {
        style = 'KeybindsPrimaryKeyColumnCell',
        width = 100
    }, {
        style = 'VerticalSeparator'
    }, {
        style = 'KeybindsSecondaryKeyColumnCell',
        width = 127
    } })

    row.category = category
    row.action = action

    setKeyColumnText(row:getChildByIndex(3), Keybind.formatKeyComboForDisplay(primary))
    setKeyColumnText(row:getChildByIndex(5), Keybind.formatKeyComboForDisplay(secondary))

    if tooltip then
        row:setTooltip(tooltip)
    end

    row:getChildByIndex(3).edit.onClick = editKeybindPrimary
    row:getChildByIndex(5).edit.onClick = editKeybindSecondary
end

function searchActions(field, text, oldText)
    if actionSearchEvent then
        removeEvent(actionSearchEvent)
    end

    actionSearchEvent = scheduleEvent(performeSearchActions, 50)
end

function performeSearchActions()
    local searchText = panels.keybindsPanel.search.field:getText():trim():lower():gsub("%+", "%%+")

    local rows = panels.keybindsPanel.tablePanel.keybinds.dataSpace:getChildren()
    if searchText:len() > 0 then
        for _, row in ipairs(rows) do
            row:hide()
        end

        for _, row in ipairs(rows) do
            local actionText = row:getChildByIndex(1):getText():lower()
            local primaryText = getKeyColumnText(row:getChildByIndex(3)):lower()
            local secondaryText = getKeyColumnText(row:getChildByIndex(5)):lower()
            if actionText:find(searchText) or primaryText:find(searchText) or secondaryText:find(searchText) then
                row:show()
            end
        end
    else
        for _, row in ipairs(rows) do
            row:show()
        end
    end

    removeEvent(actionSearchEvent)
    actionSearchEvent = nil
end

function chatModeChange()
    if syncingChatModeUI then
        return
    end

    changedKeybinds = {}

    panels.keybindsPanel.search.field:clearText()

    Keybind.setChatMode(getChatMode())
    updateKeybinds()
end

function syncKeybindsPanelChatMode(chatMode)
    if not chatModeGroup or not panels or not panels.keybindsPanel then
        return
    end

    local widget = chatMode == CHAT_MODE.ON and panels.keybindsPanel.panel.chatMode.on
        or panels.keybindsPanel.panel.chatMode.off
    if chatModeGroup:getSelectedWidget() == widget then
        return
    end

    syncingChatModeUI = true
    chatModeGroup:selectWidget(widget)
    syncingChatModeUI = false

    changedKeybinds = {}
    updateKeybinds()
end

function getChatMode()
    if chatModeGroup:getSelectedWidget() == panels.keybindsPanel.panel.chatMode.on then
        return CHAT_MODE.ON
    end

    return CHAT_MODE.OFF
end

function applyChangedOptions()
    local needKeybindsUpdate = false

    for key, option in pairs(changedOptions) do
        if key == 'resetKeybinds' then
            Keybind.resetKeybindsToDefault(option.value, option.chatMode)
            needKeybindsUpdate = true
        end
    end
    changedOptions = {}

    for preset, keybinds in pairs(changedKeybinds) do
        for index, keybind in pairs(keybinds) do
            local chatMode = getChatMode()
            if keybind.primary then
                local keyCombo = keybind.primary.keyCombo
                if keyCombo and keyCombo ~= '' then
                    if clearConflictingGeneralKeybinds(keyCombo, keybind.primary.category, keybind.primary.action,
                            chatMode, preset) then
                        needKeybindsUpdate = true
                    end
                    if clearConflictingCustomHotkeys(keyCombo, chatMode, preset) then
                        needKeybindsUpdate = true
                    end
                    clearConflictingActionbarHotkey(keyCombo)
                end
                if Keybind.setPrimaryActionKey(keybind.primary.category, keybind.primary.action, preset,
                        keyCombo, chatMode) then
                    needKeybindsUpdate = true
                end
            elseif keybind.secondary then
                local keyCombo = keybind.secondary.keyCombo
                if keyCombo and keyCombo ~= '' then
                    if clearConflictingGeneralKeybinds(keyCombo, keybind.secondary.category, keybind.secondary.action,
                            chatMode, preset) then
                        needKeybindsUpdate = true
                    end
                    if clearConflictingCustomHotkeys(keyCombo, chatMode, preset) then
                        needKeybindsUpdate = true
                    end
                    clearConflictingActionbarHotkey(keyCombo)
                end
                if Keybind.setSecondaryActionKey(keybind.secondary.category, keybind.secondary.action, preset,
                        keyCombo, chatMode) then
                    needKeybindsUpdate = true
                end
            end
        end
    end
    changedKeybinds = {}

    if needKeybindsUpdate then
        updateKeybinds()
    end
    if Keybind.refreshControlButtonTooltips then
        Keybind.refreshControlButtonTooltips()
    end
    g_settings.save()
end

function presetOption(widget, key, value, force)
    if not controller.ui:isVisible() then
        return
    end

    changedOptions[key] = { widget = widget, value = value, force = force }
    if key == "currentPreset" then
        Keybind.selectPreset(value)
        panels.keybindsPanel.presets.list:setCurrentOption(value, true)
    end
end

function init_binds()
    chatModeGroup = UIRadioGroup.create()
    chatModeGroup:addWidget(panels.keybindsPanel.panel.chatMode.on)
    chatModeGroup:addWidget(panels.keybindsPanel.panel.chatMode.off)
    chatModeGroup.onSelectionChange = chatModeChange
    syncingChatModeUI = true
    chatModeGroup:selectWidget(Keybind.chatMode == CHAT_MODE.ON and panels.keybindsPanel.panel.chatMode.on
        or panels.keybindsPanel.panel.chatMode.off)
    syncingChatModeUI = false
    updateKeybinds()

    if Keybind.migrateLegacyPresetKeys then
        Keybind.migrateLegacyPresetKeys()
    end

    keyEditWindow = g_ui.displayUI("styles/controls/key_edit")
    keyEditWindow:hide()
    presetWindow = g_ui.displayUI("styles/controls/preset")
    presetWindow:hide()
    panels.keybindsPanel.presets.add.onClick = addNewPreset
    panels.keybindsPanel.presets.copy.onClick = copyPreset
    panels.keybindsPanel.presets.rename.onClick = renamePreset
    panels.keybindsPanel.presets.remove.onClick = removePreset
    panels.keybindsPanel.buttons.reset.onClick = resetActions
    panels.keybindsPanel.search.field.onTextChange = searchActions
    panels.keybindsPanel.search.clear.onClick = function() panels.keybindsPanel.search.field:clearText() end
    presetWindow.onEnter = okPresetWindow
    presetWindow.onEscape = cancelPresetWindow
    presetWindow.buttons.ok.onClick = okPresetWindow
    presetWindow.buttons.cancel.onClick = cancelPresetWindow
    if g_platform.isMobile() then
        panels.keybindsPanel.tablePanel:hide()
    end
end

function terminate_binds()
    if presetWindow then
        presetWindow:destroy()
        presetWindow = nil
    end

    if chatModeGroup then
        chatModeGroup:destroy()
        chatModeGroup = nil
    end

    if keyEditWindow then
        if keyEditWindow:isVisible() then
            keyEditWindow:ungrabKeyboard()
            disconnect(keyEditWindow, { onKeyDown = editKeybindKeyDown })
        end
        keyEditWindow:destroy()
        keyEditWindow = nil
    end

    if actionSearchEvent then
        removeEvent(actionSearchEvent)
        actionSearchEvent = nil
    end
end

function listKeybindsComboBox(value)
    local widget = panels.keybindsPanel.presets.list
    presetOption(widget, 'currentPreset', value, false)
    if modules.game_actionbar and modules.game_actionbar.selectHotkeySet then
        modules.game_actionbar.selectHotkeySet(value)
    end
    changedKeybinds = {}
    applyChangedOptions()
    updateKeybinds()
    if panels.customHotkeys then
        panels.customHotkeys.presets.list:setCurrentOption(value, true)
        updateCustomHotkeys()
    end
end

function debug()
    local currentOptionText = Keybind.currentPreset
    local chatMode = Keybind.chatMode
    local chatModeText = (chatMode == 1) and "Chat mode ON" or (chatMode == 2) and "Chat mode OFF" or "Unknown chat mode"
    print(string.format("The current configuration is: %s, and the mode is: %s", currentOptionText, chatModeText))
end
