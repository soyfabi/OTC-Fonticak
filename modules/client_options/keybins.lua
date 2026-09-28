local actionNameLimit = 39
local changedOptions = {}
local changedKeybinds = {}
local presetWindow = nil
local actionSearchEvent
keyEditWindow = nil
local chatModeGroup
local syncingChatModeUI = false
local categoryExpandedState = {}
local keybindSections = {}
local updatingKeybinds = false
local pendingKeybindsUpdate = false

local function getGeneralHotkeysScroll()
    if not panels or not panels.keybindsPanel then
        return nil
    end
    return panels.keybindsPanel:recursiveGetChildById('keybindsScroll')
end

local function getKeybindSectionParts(section)
    if not section then
        return nil, nil, nil, nil
    end
    local header = section:getChildById('header')
    local rowsPanel = section:getChildById('rowsPanel')
    local title = header and header:getChildById('title')
    local indicator = header and header:getChildById('indicator')
    return header, rowsPanel, title, indicator
end

-- UI-only grouping for General Hotkeys (registration categories are unchanged).
local GENERAL_HOTKEY_UI_SECTIONS = {
    { id = 'windows', title = tr('Windows'), categories = { Windows = true } },
    { id = 'game', title = tr('Game'), categories = { UI = true, Movement = true, ['Battle List'] = true } },
    { id = 'chat', title = tr('Chat'), categories = { Chat = true, ['Chat Channel'] = true, ['Chat Mode'] = true } },
    { id = 'actions', title = tr('Actions'), categories = {
        Misc = true,
        ['Misc.'] = true,
        Dialogs = true,
        Loot = true,
        Containers = true,
        Sound = true,
        Debug = true,
    } },
}

local UI_SECTION_ORDER = { 'windows', 'game', 'chat', 'actions', 'other' }

local function resolveKeybindUiSectionId(category)
    for _, section in ipairs(GENERAL_HOTKEY_UI_SECTIONS) do
        if section.categories[category] then
            return section.id
        end
    end
    return 'other'
end

local function getUiSectionTitle(sectionId)
    if sectionId == 'other' then
        return tr('Other')
    end
    for _, section in ipairs(GENERAL_HOTKEY_UI_SECTIONS) do
        if section.id == sectionId then
            return section.title
        end
    end
    return sectionId
end

local function isKeybindCategoryExpanded(sectionId)
    if categoryExpandedState[sectionId] == nil then
        return true
    end
    return categoryExpandedState[sectionId]
end

local function setKeybindCategoryExpanded(section, expanded)
    categoryExpandedState[section.sectionId] = expanded
    local _, rowsPanel, _, indicator = getKeybindSectionParts(section)
    if rowsPanel then
        rowsPanel:setVisible(expanded)
    end
    if indicator then
        indicator:setText(expanded and tr('▼') or tr('▶'))
    end
end

local function toggleKeybindCategorySection(section)
    setKeybindCategoryExpanded(section, not isKeybindCategoryExpanded(section.sectionId))
end

local function clearGeneralHotkeysList()
    local scroll = getGeneralHotkeysScroll()
    if not scroll then
        return
    end
    scroll:destroyChildren()
    keybindSections = {}
end

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

local function getActiveChatMode()
    if chatModeGroup and panels and panels.keybindsPanel then
        return getChatMode()
    end
    return Keybind.chatMode
end

function updateKeybinds()
    if updatingKeybinds then
        pendingKeybindsUpdate = true
        return
    end
    if not panels or not panels.keybindsPanel then
        return
    end

    updatingKeybinds = true

    local ok, err = pcall(function()
        clearGeneralHotkeysList()

        local scroll = getGeneralHotkeysScroll()
        if not scroll then
            return
        end

        local presetList = panels.keybindsPanel.presets and panels.keybindsPanel.presets.list
        local comboBox = presetList and presetList:getCurrentOption()
        if not comboBox then
            return
        end

        local chatMode = getActiveChatMode()

        local sectionBuckets = {}
        for _, sectionId in ipairs(UI_SECTION_ORDER) do
            sectionBuckets[sectionId] = {}
        end

        for index, _ in pairs(Keybind.defaultKeybinds) do
            local keybind = Keybind.defaultKeybinds[index]
            local sectionId = resolveKeybindUiSectionId(keybind.category)
            table.insert(sectionBuckets[sectionId], keybind)
        end

        for _, sectionId in ipairs(UI_SECTION_ORDER) do
            local entries = sectionBuckets[sectionId]
            if #entries > 0 then
                table.sort(entries, function(a, b)
                    if a.category ~= b.category then
                        return a.category < b.category
                    end
                    return a.action < b.action
                end)

                local section = g_ui.createWidget('KeybindsCategorySection', scroll)
                if not section then
                    g_logger.error('[keybinds] Failed to create KeybindsCategorySection')
                    return
                end

                section.sectionId = sectionId
                local header, rowsPanel, title = getKeybindSectionParts(section)
                if title then
                    title:setText(getUiSectionTitle(sectionId))
                end
                if header then
                    header.onClick = function()
                        toggleKeybindCategorySection(section)
                    end
                end
                if not rowsPanel then
                    g_logger.error('[keybinds] Category section missing rowsPanel')
                    return
                end

                for rowIndex, keybind in ipairs(entries) do
                    local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, comboBox.text,
                        changedOptions['resetKeybinds'])
                    addKeybindRow(rowsPanel, keybind.category, keybind.action, keys.primary, keys.secondary, rowIndex)
                end

                setKeybindCategoryExpanded(section, isKeybindCategoryExpanded(sectionId))
                table.insert(keybindSections, section)
            end
        end

        scroll:updateLayout()

        local searchField = panels.keybindsPanel.search and panels.keybindsPanel.search.field
        if searchField and searchField:getText():len() > 0 then
            performeSearchActions()
        end
    end)

    updatingKeybinds = false

    if not ok then
        g_logger.error('[keybinds] updateKeybinds failed: ' .. tostring(err))
    end

    if pendingKeybindsUpdate then
        pendingKeybindsUpdate = false
        scheduleEvent(updateKeybinds, 0)
    end
end

function addKeybindRow(parent, category, action, primary, secondary, rowIndex)
    local rawText = string.format('%s: %s', category, action)
    local tooltip = nil
    local actionText = action

    if rawText:len() > actionNameLimit then
        tooltip = rawText
        if action:len() > actionNameLimit then
            actionText = action:sub(1, actionNameLimit) .. '...'
        end
    end

    local row = g_ui.createWidget('KeybindsHotkeyRow', parent)
    row.category = category
    row.action = action
    row.rowIndex = rowIndex

    row:getChildById('actionName'):setText(actionText)
    setKeyColumnText(row:getChildByIndex(3), Keybind.formatKeyComboForDisplay(primary))
    setKeyColumnText(row:getChildByIndex(5), Keybind.formatKeyComboForDisplay(secondary))

    if tooltip then
        row:setTooltip(tooltip)
    end

    row:getChildByIndex(3).edit.onClick = editKeybindPrimary
    row:getChildByIndex(5).edit.onClick = editKeybindSecondary

    return row
end

function addKeybind(category, action, primary, secondary)
    local sectionId = resolveKeybindUiSectionId(category)
    for _, section in ipairs(keybindSections) do
        if section.sectionId == sectionId then
            local _, rowsPanel = getKeybindSectionParts(section)
            if rowsPanel then
                addKeybindRow(rowsPanel, category, action, primary, secondary, rowsPanel:getChildCount() + 1)
            end
            return
        end
    end
end

function searchActions(field, text, oldText)
    if actionSearchEvent then
        removeEvent(actionSearchEvent)
    end

    actionSearchEvent = scheduleEvent(performeSearchActions, 50)
end

function performeSearchActions()
    if updatingKeybinds or not panels or not panels.keybindsPanel then
        return
    end

    local searchField = panels.keybindsPanel.search and panels.keybindsPanel.search.field
    if not searchField then
        return
    end

    local searchText = searchField:getText():trim():lower():gsub("%+", "%%+")
    local hasSearch = searchText:len() > 0

    for _, section in ipairs(keybindSections) do
        local sectionVisible = not hasSearch
        local _, rowsPanel = getKeybindSectionParts(section)
        if not rowsPanel then
            goto continue_search_section
        end

        for _, row in ipairs(rowsPanel:getChildren()) do
            if row.category and row.action then
                local actionWidget = row:getChildById('actionName')
                local actionText = actionWidget and actionWidget:getText():lower() or row.action:lower()
                local categoryText = row.category:lower()
                local primaryText = getKeyColumnText(row:getChildByIndex(3)):lower()
                local secondaryText = getKeyColumnText(row:getChildByIndex(5)):lower()
                local matches = not hasSearch
                    or actionText:find(searchText, 1, true)
                    or categoryText:find(searchText, 1, true)
                    or primaryText:find(searchText, 1, true)
                    or secondaryText:find(searchText, 1, true)

                if hasSearch then
                    row:setVisible(matches and true or false)
                    if matches then
                        sectionVisible = true
                    end
                else
                    row:show()
                end
            end
        end

        if hasSearch then
            section:setVisible(sectionVisible)
            if sectionVisible then
                setKeybindCategoryExpanded(section, true)
            end
        else
            section:show()
        end

        ::continue_search_section::
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
    scheduleEvent(function()
        updateKeybinds()
    end, 0)

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

    categoryExpandedState = {}
    keybindSections = {}
    pendingKeybindsUpdate = false
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
