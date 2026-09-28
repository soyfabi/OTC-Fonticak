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
local pendingKeybindsRefresh = false
local KEYBIND_ROW_HEIGHT = 20
local KEYBIND_HEADER_HEIGHT = 20
local inlineKeyEditSession = nil
local inlineKeyCaptureWidget = nil
local inlineKeyDismissConnected = false
local inlineKeyConfirmationKey = nil
local keyColumnPulseEvent = nil
local keyColumnPulseColumn = nil
local KEY_COLUMN_PLACEHOLDER_COLOR = '#787878'
local KEY_COLUMN_ASSIGNED_COLOR = '#c0c0c0'
local KEY_COLUMN_LISTEN_COLOR = '#ffffff'
local KEY_COLUMN_OVERWRITE_TEXT_COLOR = '#ffff66'
local KEY_COLUMN_OVERWRITE_BACKGROUND = '#5a5028'
local KEY_COLUMN_OVERWRITE_BORDER = '#a88828'
local KEY_COLUMN_BLOCKED_COLOR = '#f75f5f'
local cancelPendingInlineKeybindCommit
local showKeyColumnConflictCell
local hotkeyConflictPulseEvent = nil
local hotkeyConflictPulseColumn = nil

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
local TREE_HELP_WIDGET_ID = 'treeHelpSection'
local KEYBIND_CATEGORY_COLOR = '#8cb4d9'

local function keyColumnPlaceholderText()
    return tr('[Press Key]')
end

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
        return false
    end
    return categoryExpandedState[sectionId]
end

local function shouldRefreshGeneralHotkeysList()
    if not panels or not panels.keybindsPanel then
        return false
    end
    if not controller or not controller.ui or not controller.ui:isVisible() then
        return false
    end
    return panels.keybindsPanel:isVisible()
end

local function refreshKeybindSectionHeight(section, expanded)
    local entryCount = section.entryCount or 0
    local _, rowsPanel = getKeybindSectionParts(section)
    local rowsHeight = expanded and (entryCount * KEYBIND_ROW_HEIGHT) or 0
    if rowsPanel then
        rowsPanel:setHeight(rowsHeight)
    end
    section:setHeight(KEYBIND_HEADER_HEIGHT + rowsHeight)
end

local KEYBIND_CATEGORY_EXPANDED_ICON = '/images/arrows/icon-arrow7x7-down'
local KEYBIND_CATEGORY_COLLAPSED_ICON = '/images/arrows/icon-arrow7x7-right'

local function setKeybindCategoryExpanded(section, expanded)
    categoryExpandedState[section.sectionId] = expanded
    local _, rowsPanel, _, indicator = getKeybindSectionParts(section)
    if rowsPanel then
        rowsPanel:setVisible(expanded)
    end
    if indicator then
        indicator:setImageSource(expanded and KEYBIND_CATEGORY_EXPANDED_ICON or KEYBIND_CATEGORY_COLLAPSED_ICON)
    end
    refreshKeybindSectionHeight(section, expanded)
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

local function addGeneralHotkeysTreeHelp(scroll)
    local help = g_ui.createWidget('KeybindsTreeHelpSection', scroll)
    if help then
        help:setId(TREE_HELP_WIDGET_ID)
    end
end

local function setGeneralHotkeysTreeHelpVisible(visible)
    local scroll = getGeneralHotkeysScroll()
    if not scroll then
        return
    end
    local help = scroll:getChildById(TREE_HELP_WIDGET_ID)
    if help then
        help:setVisible(visible)
    end
end

local function getKeyColumnText(column)
    local text = ''
    if column.value then
        text = column.value:getText()
    else
        text = column:getText()
    end
    if text == keyColumnPlaceholderText() then
        return ''
    end
    return text
end

local function setKeyColumnText(column, text)
    text = text or ''
    if column.value then
        column.value:setText(text)
    else
        column:setText(text)
    end
end

local function listenPulseIntensity(phase)
    local p = phase % 1
    local first = math.max(0, math.sin(p * math.pi * 2))
    local second = math.max(0, math.sin(p * math.pi * 4 + 0.55)) * 0.45
    return math.min(1, first * 0.9 + second)
end

local function listenPulseTextColor(intensity)
    local v = math.floor(175 + intensity * 80)
    return string.format('#%02x%02x%02x', v, v, v)
end

local function listenPulseBackgroundColor(intensity)
    local v = math.floor(62 + intensity * 38)
    return string.format('#%02x%02x%02x', v, v, v)
end

local function listenPulseBorderColor(intensity)
    local v = math.floor(48 + intensity * 72)
    return string.format('#%02x%02x%02x', v, v, v)
end

local function applyKeyColumnPulseFrame(column, phase)
    if not column or not column.value then
        return
    end
    local intensity = listenPulseIntensity(phase)
    column.value:setColor(listenPulseTextColor(intensity))
    column:setBackgroundColor(listenPulseBackgroundColor(intensity))
    column:setBorderColor(listenPulseBorderColor(intensity))
end

local function stopKeyColumnPulse(column)
    if keyColumnPulseEvent then
        removeEvent(keyColumnPulseEvent)
        keyColumnPulseEvent = nil
    end
    local target = column or keyColumnPulseColumn
    if target and target.value then
        target.value:setOpacity(1.0)
    end
    if target then
        target:setBackgroundColor('#363636')
        target:setBorderColor('#272727')
    end
    if not column or keyColumnPulseColumn == column then
        keyColumnPulseColumn = nil
    end
end

local function getGeneralHotkeysScrollBar()
    if not panels or not panels.keybindsPanel or not panels.keybindsPanel.tablePanel then
        return nil
    end
    return panels.keybindsPanel.tablePanel.scrollBar
end

local function startKeyColumnPulse(column)
    stopKeyColumnPulse(column)
    if not column or not column.value then
        return
    end

    keyColumnPulseColumn = column
    local phase = 0
    applyKeyColumnPulseFrame(column, phase)

    keyColumnPulseEvent = cycleEvent(function()
        if not inlineKeyEditSession or inlineKeyEditSession.column ~= column then
            stopKeyColumnPulse(column)
            return
        end

        phase = phase + 0.022
        if phase > 1 then
            phase = phase - 1
        end
        applyKeyColumnPulseFrame(column, phase)
    end, 48)
end

local function clearKeyColumnTooltip(column)
    if column and column.setTooltip then
        column:setTooltip('')
    end
end

local function setKeyColumnDisplay(column, keyCombo)
    stopKeyColumnPulse(column)
    clearKeyColumnTooltip(column)
    local display = Keybind.formatKeyComboForDisplay(keyCombo)
    local isEmpty = not keyCombo or keyCombo == '' or not display or display == ''
    if isEmpty then
        display = keyColumnPlaceholderText()
    end
    setKeyColumnText(column, display)
    if column.value then
        column.value:setColor(isEmpty and KEY_COLUMN_PLACEHOLDER_COLOR or KEY_COLUMN_ASSIGNED_COLOR)
        column.value:setOpacity(1.0)
    end
    column:setBackgroundColor('#363636')
    column:setBorderColor('#272727')
end

local function setKeyColumnListening(column, keyCombo)
    clearKeyColumnTooltip(column)
    local display = Keybind.formatKeyComboForDisplay(keyCombo)
    if not display or display == '' then
        display = keyColumnPlaceholderText()
    end
    setKeyColumnText(column, display)
    column:setBackgroundColor('#585858')
    startKeyColumnPulse(column)
end

local function resolveKeybindColumnWidget(widget)
    if not widget then
        return nil
    end
    if widget.value then
        return widget
    end
    local parent = widget:getParent()
    if parent and parent.value then
        return parent
    end
    return nil
end

local function bindKeybindColumnCell(column, editCallback)
    column.onMousePress = function(_, mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
            editCallback(column)
            return true
        end
        return false
    end
end

local function inlineKeybindDismissPress(widget, mousePos, mouseButton)
    if not inlineKeyEditSession then
        return false
    end
    if mouseButton ~= MouseLeftButton then
        return false
    end

    local column = inlineKeyEditSession.column
    if column and column:containsPoint(mousePos) then
        return false
    end

    cancelGeneralHotkeyInlineEdit()
    return false
end

local function stopInlineKeyDismissPress()
    if not inlineKeyDismissConnected or not panels or not panels.keybindsPanel then
        return
    end
    disconnect(panels.keybindsPanel, {
        onMousePress = inlineKeybindDismissPress
    })
    inlineKeyDismissConnected = false
end

local function startInlineKeyDismissPress()
    if inlineKeyDismissConnected or not panels or not panels.keybindsPanel then
        return
    end
    connect(panels.keybindsPanel, {
        onMousePress = inlineKeybindDismissPress
    })
    inlineKeyDismissConnected = true
end

local function stopInlineKeybindCapture()
    stopInlineKeyDismissPress()
    if inlineKeyCaptureWidget then
        local captureWidget = inlineKeyCaptureWidget
        disconnect(captureWidget, {
            onKeyDown = inlineKeybindKeyDown
        })
        disconnect(captureWidget, {
            onMousePress = inlineKeybindMouse
        })
        inlineKeyCaptureWidget = nil
        scheduleEvent(function()
            if inlineKeyCaptureWidget then
                return
            end
            disconnect(captureWidget, {
                onKeyPress = inlineKeybindKeyPress
            })
            if captureWidget.ungrabKeyboard then
                captureWidget:ungrabKeyboard()
            end
        end, 0)
    end
end

local function getGeneralHotkeyConflictNotice()
    if not panels or not panels.keybindsPanel or not panels.keybindsPanel.tablePanel then
        return nil
    end
    return panels.keybindsPanel.tablePanel:recursiveGetChildById('overwriteNotice')
end

local function getGeneralHotkeyConflictNoticeIcon()
    if not panels or not panels.keybindsPanel or not panels.keybindsPanel.tablePanel then
        return nil
    end
    return panels.keybindsPanel.tablePanel:recursiveGetChildById('overwriteNoticeIcon')
end

local function setGeneralHotkeyConflictNoticeSpace(height)
    local tablePanel = panels and panels.keybindsPanel and panels.keybindsPanel.tablePanel
    if not tablePanel then
        return
    end

    local scroll = tablePanel.keybindsScroll
    local scrollBar = tablePanel.scrollBar
    if scroll then
        scroll:setMarginTop(height)
    end
    if scrollBar then
        scrollBar:setMarginTop(height)
    end
end

local function stopGeneralHotkeyConflictPulse()
    if hotkeyConflictPulseEvent then
        removeEvent(hotkeyConflictPulseEvent)
        hotkeyConflictPulseEvent = nil
    end
    hotkeyConflictPulseColumn = nil
end

local function hideGeneralHotkeyConflictNotice()
    stopGeneralHotkeyConflictPulse()
    local notice = getGeneralHotkeyConflictNotice()
    if not notice then
        return
    end
    notice:setVisible(false)
    notice:setHeight(0)
    notice:setText('')
    setGeneralHotkeyConflictNoticeSpace(0)

    local icon = getGeneralHotkeyConflictNoticeIcon()
    if icon then
        icon:setVisible(false)
    end
end

local function startGeneralHotkeyConflictPulse(column)
    stopGeneralHotkeyConflictPulse()
    hotkeyConflictPulseColumn = column
    local phase = 0

    hotkeyConflictPulseEvent = cycleEvent(function()
        if not inlineKeyEditSession or not inlineKeyEditSession.pendingKeyCombo then
            stopGeneralHotkeyConflictPulse()
            return
        end

        phase = (phase + 0.022) % 1
        local intensity = math.max(0, math.sin(phase * math.pi * 2))
        local red = 240 + math.floor(intensity * 15)
        local green = 192 + math.floor(intensity * 48)
        local color = string.format('#%02x%02x00', red, green)

        if hotkeyConflictPulseColumn and hotkeyConflictPulseColumn.value then
            hotkeyConflictPulseColumn.value:setColor(color)
            hotkeyConflictPulseColumn:setBorderColor(color)
        end
    end, 48)
end

local function showGeneralHotkeyConflictNotice(text, height)
    local notice = getGeneralHotkeyConflictNotice()
    if not notice then
        return
    end
    notice:setText(text)
    notice:setColor('#f0c040')
    notice:setHeight(height or 20)
    notice:setVisible(true)
    setGeneralHotkeyConflictNoticeSpace(height or 20)

    local icon = getGeneralHotkeyConflictNoticeIcon()
    if icon then
        local textWidth = notice:getTextSize().width
        local textStart = math.floor((notice:getWidth() - textWidth) / 2)
        icon:setMarginLeft(math.max(2, textStart - icon:getWidth() - 2))
        icon:setMarginTop(4)
        icon:setVisible(true)
    end
end

local function formatGeneralHotkeyConflictNotice(conflictMessage)
    local notice = getGeneralHotkeyConflictNotice()
    local confirmMessage = tr('Press [Enter] to confirm or [Esc] to cancel.')
    local singleLine = tr('This hotkey is already in use. %s %s', conflictMessage, confirmMessage)
    if not notice then
        return singleLine, 20
    end

    notice:setText(singleLine)
    if notice:getTextSize().width <= notice:getWidth() then
        return singleLine, 20
    end

    local twoLines = tr('This hotkey is already in use. %s\n%s', conflictMessage, confirmMessage)
    notice:setText(twoLines)
    if notice:getTextSize().width <= notice:getWidth() then
        return twoLines, 30
    end

    return tr('This hotkey is already in use.\n%s\n%s', conflictMessage, confirmMessage), 42
end

function cancelGeneralHotkeyInlineEdit()
    if not inlineKeyEditSession then
        return
    end
    cancelPendingInlineKeybindCommit()
    local session = inlineKeyEditSession
    inlineKeyEditSession = nil
    stopKeyColumnPulse(session.column)
    stopInlineKeybindCapture()
    setKeyColumnDisplay(session.column, session.previousKeyCombo)
end

local function isInlineEnterKey(keyCode)
    return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13
        or (KeyNumpadEnter and keyCode == KeyNumpadEnter)
        or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
end

local function clearInlineKeyOverwriteConfirmUI(session)
    hideGeneralHotkeyConflictNotice()
end

local function showInlineKeyOverwriteConfirm(session, keyCombo, feedback)
    session.pendingKeyCombo = keyCombo
    showKeyColumnConflictCell(session.column, keyCombo, feedback)
    local text, height = formatGeneralHotkeyConflictNotice(feedback.message)
    showGeneralHotkeyConflictNotice(text, height)
    startGeneralHotkeyConflictPulse(session.column)
end

local function flashInlineKeyBlockedNotice(column, keyCombo, feedback, previousKeyCombo)
    showKeyColumnConflictCell(column, keyCombo, feedback)
    showGeneralHotkeyConflictNotice(feedback.message or feedback.tooltip
        or tr('This hotkey is already in use and cannot be overwritten.'))

    scheduleEvent(function()
        if not inlineKeyEditSession or inlineKeyEditSession.column ~= column or inlineKeyEditSession.pendingKeyCombo then
            return
        end
        hideGeneralHotkeyConflictNotice()
        setKeyColumnListening(column, previousKeyCombo)
    end, 350)
end

showKeyColumnConflictCell = function(column, keyCombo, feedback)
    stopKeyColumnPulse(column)
    local display = Keybind.formatKeyComboForDisplay(keyCombo)
    if not display or display == '' then
        display = keyColumnPlaceholderText()
    end
    setKeyColumnText(column, display)
    if column.value then
        column.value:setColor(feedback.blocked and KEY_COLUMN_BLOCKED_COLOR or KEY_COLUMN_OVERWRITE_TEXT_COLOR)
        column.value:setOpacity(1.0)
    end
    if feedback.blocked then
        column:setBackgroundColor('#585858')
        column:setBorderColor(KEY_COLUMN_BLOCKED_COLOR)
    else
        column:setBackgroundColor(KEY_COLUMN_OVERWRITE_BACKGROUND)
        column:setBorderColor(KEY_COLUMN_OVERWRITE_BORDER)
    end
    column:setTooltip(feedback.tooltip or '')
end

local function hasCustomHotkeyConflictForCombo(keyCombo, chatMode, preset)
    if not keyCombo or keyCombo == '' then
        return false
    end

    local hotkeys = Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][preset]
    if not hotkeys then
        return false
    end

    for _, hotkey in ipairs(hotkeys) do
        if hotkey.primary == keyCombo or hotkey.secondary == keyCombo then
            return true
        end
    end

    return false
end

local function hasActionbarHotkeyConflictForCombo(keyCombo)
    if not keyCombo or keyCombo == '' then
        return false
    end

    if modules.game_hotkeys and modules.game_hotkeys.isHotkeyUsedByManager and modules.game_hotkeys.isHotkeyUsedByManager(keyCombo) then
        return true
    end

    local actionbarApi = modules.game_actionbar and modules.game_actionbar.ApiJson
    if actionbarApi and actionbarApi.hasCurrentHotkeySet and actionbarApi.hasCurrentHotkeySet() then
        local chatMode = modules.game_console and modules.game_console.isChatEnabled and modules.game_console.isChatEnabled() and 'chatOn' or 'chatOff'
        if actionbarApi.getHotkeyEntries then
            for _, data in ipairs(actionbarApi.getHotkeyEntries(chatMode)) do
                if data['actionsetting'] and data['keysequence'] and data['keysequence']:lower() == keyCombo:lower() then
                    return true
                end
            end
        end
    end

    return false
end

local function getInlineKeyConflictFeedback(keyCombo, category, action)
    if not keyCombo or keyCombo == '' then
        return nil
    end

    if Keybind.reservedKeys[keyCombo] then
        return {
            blocked = true,
            warn = false,
            message = tr('This hotkey is already in use and cannot be overwritten.'),
            tooltip = tr('This hotkey is already in use and cannot be overwritten.')
        }
    end

    local presetOption = panels.keybindsPanel.presets.list:getCurrentOption()
    if not presetOption then
        return nil
    end

    local chatMode = getChatMode()
    local preset = presetOption.text
    local conflictCategory, conflictAction = Keybind.getKeyComboOverwriteTarget(keyCombo, category, action, chatMode, preset)
    if conflictAction then
        local message = tr("'%s: %s' will be overwritten.", conflictCategory, conflictAction)
        return {
            blocked = false,
            warn = true,
            message = message,
            tooltip = message
        }
    end

    if hasCustomHotkeyConflictForCombo(keyCombo, chatMode, preset) or hasActionbarHotkeyConflictForCombo(keyCombo) then
        local message = tr('This hotkey will be overwritten.')
        return {
            blocked = false,
            warn = true,
            message = message,
            tooltip = message
        }
    end

    return nil
end

cancelPendingInlineKeybindCommit = function()
    if inlineKeyEditSession then
        clearInlineKeyOverwriteConfirmUI(inlineKeyEditSession)
        inlineKeyEditSession.pendingKeyCombo = nil
    end
end

local function performInlineKeybindCommit(keyCombo)
    local session = inlineKeyEditSession
    if not session then
        return
    end

    clearInlineKeyOverwriteConfirmUI(session)
    session.pendingKeyCombo = nil

    keyCombo = keyCombo or ''
    local row = session.row
    local column = session.column
    local presetOption = panels.keybindsPanel.presets.list:getCurrentOption()
    if not presetOption then
        cancelGeneralHotkeyInlineEdit()
        return
    end

    local preset = presetOption.text
    local index = row.category .. '_' .. row.action

    inlineKeyEditSession = nil
    stopKeyColumnPulse(column)
    stopInlineKeybindCapture()

    setKeyColumnDisplay(column, keyCombo)

    if not changedKeybinds[preset] then
        changedKeybinds[preset] = {}
    end
    if not changedKeybinds[preset][index] then
        changedKeybinds[preset][index] = {}
    end

    local binding = {
        category = row.category,
        action = row.action,
        keyCombo = keyCombo
    }
    if session.isSecondary then
        changedKeybinds[preset][index].secondary = binding
    else
        changedKeybinds[preset][index].primary = binding
    end

    applyChangedOptions()
end

local function commitInlineKeybindChange(keyCombo)
    local session = inlineKeyEditSession
    if not session then
        return
    end

    if session.pendingKeyCombo then
        return
    end

    keyCombo = keyCombo or ''
    if keyCombo == '' then
        performInlineKeybindCommit('')
        return
    end

    local feedback = getInlineKeyConflictFeedback(keyCombo, session.row.category, session.row.action)
    if feedback and feedback.blocked then
        return
    end

    if feedback and feedback.warn then
        showInlineKeyOverwriteConfirm(session, keyCombo, feedback)
        return
    end

    performInlineKeybindCommit(keyCombo)
end

local function getInlineKeyCaptureWidget()
    if panels.keybindsPanel and panels.keybindsPanel.tablePanel then
        return panels.keybindsPanel.tablePanel
    end
    return panels.keybindsPanel
end

local function beginInlineKeybindEdit(column, isSecondary)
    if inlineKeyEditSession and inlineKeyEditSession.column == column then
        return
    end

    cancelGeneralHotkeyInlineEdit()

    local row = column:getParent()
    if not row or not row.category or not row.action then
        return
    end

    local presetOption = panels.keybindsPanel.presets.list:getCurrentOption()
    if not presetOption then
        return
    end

    local keys = Keybind.getKeybindKeys(row.category, row.action, getChatMode(), presetOption.text)
    local previous = isSecondary and keys.secondary or keys.primary
    local keybind = Keybind.getAction(row.category, row.action)

    inlineKeyEditSession = {
        column = column,
        row = row,
        isSecondary = isSecondary,
        previousKeyCombo = previous,
        alone = keybind and keybind.alone or false
    }

    setKeyColumnListening(column, previous)

    inlineKeyCaptureWidget = getInlineKeyCaptureWidget()
    connect(inlineKeyCaptureWidget, {
        onKeyDown = inlineKeybindKeyDown
    })
    connect(inlineKeyCaptureWidget, {
        onMousePress = inlineKeybindMouse
    })
    connect(inlineKeyCaptureWidget, {
        onKeyPress = inlineKeybindKeyPress
    })
    inlineKeyCaptureWidget:focus()
    inlineKeyCaptureWidget:grabKeyboard()
    startInlineKeyDismissPress()
end

function inlineKeybindKeyDown(widget, keyCode, keyboardModifiers)
    if not inlineKeyEditSession then
        return false
    end

    if inlineKeyEditSession.pendingKeyCombo then
        if isInlineEnterKey(keyCode) then
            inlineKeyConfirmationKey = keyCode
            performInlineKeybindCommit(inlineKeyEditSession.pendingKeyCombo)
            return true
        end
        if keyCode == KeyEscape then
            inlineKeyConfirmationKey = keyCode
            cancelGeneralHotkeyInlineEdit()
            return true
        end
        if keyCode == KeyDelete or keyCode == KeyBackspace then
            cancelPendingInlineKeybindCommit()
            setKeyColumnListening(inlineKeyEditSession.column, inlineKeyEditSession.previousKeyCombo)
            return true
        end

        -- A different key replaces the pending conflict candidate, allowing the
        -- player to choose another shortcut without cancelling the edit first.
        cancelPendingInlineKeybindCommit()
        setKeyColumnListening(inlineKeyEditSession.column, inlineKeyEditSession.previousKeyCombo)
    end

    if keyCode == KeyEscape then
        inlineKeyConfirmationKey = keyCode
        cancelGeneralHotkeyInlineEdit()
        return true
    end

    if keyCode == KeyDelete or keyCode == KeyBackspace then
        commitInlineKeybindChange('')
        return true
    end

    local modifiers = inlineKeyEditSession.alone and KeyboardNoModifier or keyboardModifiers
    local keyCombo = determineKeyComboDesc(keyCode, modifiers)

    if keyCombo == 'Shift' or keyCombo == 'Ctrl' or keyCombo == 'Alt' then
        return true
    end

    if keyCombo and keyCombo ~= '' and Keybind.reservedKeys[keyCombo] then
        local column = inlineKeyEditSession.column
        local feedback = getInlineKeyConflictFeedback(keyCombo, inlineKeyEditSession.row.category,
            inlineKeyEditSession.row.action)
        flashInlineKeyBlockedNotice(column, keyCombo, feedback or {
            blocked = true,
            message = tr('This hotkey is already in use and cannot be overwritten.'),
            tooltip = tr('This hotkey is already in use and cannot be overwritten.')
        }, inlineKeyEditSession.previousKeyCombo)
        return true
    end

    commitInlineKeybindChange(keyCombo or '')
    return true
end

function inlineKeybindKeyPress(widget, keyCode)
    if inlineKeyConfirmationKey ~= keyCode then
        return false
    end

    inlineKeyConfirmationKey = nil
    return true
end

function inlineKeybindMouse(widget, mousePos, mouseButton)
    if not inlineKeyEditSession then
        return false
    end

    if inlineKeyEditSession.pendingKeyCombo then
        if not inlineKeyEditSession.column:containsPoint(mousePos) then
            cancelGeneralHotkeyInlineEdit()
            return false
        end
        return true
    end

    local column = inlineKeyEditSession.column
    if not column:containsPoint(mousePos) then
        cancelGeneralHotkeyInlineEdit()
        return false
    end

    local keyCombo = Keybind.getMouseKeyCombo(mouseButton, g_keyboard.getModifiers())
    if not keyCombo then
        return false
    end

    if Keybind.reservedKeys[keyCombo] then
        local feedback = getInlineKeyConflictFeedback(keyCombo, inlineKeyEditSession.row.category,
            inlineKeyEditSession.row.action)
        flashInlineKeyBlockedNotice(column, keyCombo, feedback or {
            blocked = true,
            message = tr('This hotkey is already in use and cannot be overwritten.'),
            tooltip = tr('This hotkey is already in use and cannot be overwritten.')
        }, inlineKeyEditSession.previousKeyCombo)
        return true
    end

    local feedback = getInlineKeyConflictFeedback(keyCombo, inlineKeyEditSession.row.category,
        inlineKeyEditSession.row.action)
    if feedback and feedback.warn then
        showInlineKeyOverwriteConfirm(inlineKeyEditSession, keyCombo, feedback)
        return true
    end

    commitInlineKeybindChange(keyCombo)
    return true
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

function editKeybindPrimary(column)
    beginInlineKeybindEdit(resolveKeybindColumnWidget(column), false)
end

function editKeybindSecondary(column)
    beginInlineKeybindEdit(resolveKeybindColumnWidget(column), true)
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
    if not shouldRefreshGeneralHotkeysList() then
        pendingKeybindsRefresh = true
        return
    end
    pendingKeybindsRefresh = false

    updatingKeybinds = true

    cancelGeneralHotkeyInlineEdit()

    local ok, err = pcall(function()
        local scrollBar = getGeneralHotkeysScrollBar()
        local savedScrollValue = scrollBar and scrollBar:getValue() or nil

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
                section.entryCount = #entries
                local header, rowsPanel, title = getKeybindSectionParts(section)
                if title then
                    title:setText(getUiSectionTitle(sectionId))
                    title:setColor(KEYBIND_CATEGORY_COLOR)
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

        addGeneralHotkeysTreeHelp(scroll)

        local searchField = panels.keybindsPanel.search and panels.keybindsPanel.search.field
        if searchField and searchField:getText():len() > 0 then
            performeSearchActions()
        else
            setGeneralHotkeysTreeHelpVisible(true)
        end

        if savedScrollValue and scrollBar then
            local function restoreScroll()
                if scrollBar:getParent() then
                    local maximum = scrollBar:getMaximum()
                    if maximum >= 0 then
                        scrollBar:setValue(math.min(savedScrollValue, maximum))
                    end
                end
            end
            scheduleEvent(restoreScroll, 0)
            scheduleEvent(restoreScroll, 50)
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
    local primaryCol = row:getChildByIndex(3)
    local secondaryCol = row:getChildByIndex(5)
    setKeyColumnDisplay(primaryCol, primary)
    setKeyColumnDisplay(secondaryCol, secondary)

    if tooltip then
        row:setTooltip(tooltip)
    end

    bindKeybindColumnCell(primaryCol, editKeybindPrimary)
    bindKeybindColumnCell(secondaryCol, editKeybindSecondary)

    return row
end

local function refreshGeneralHotkeysKeyDisplays()
    if not shouldRefreshGeneralHotkeysList() or #keybindSections == 0 then
        return
    end

    local presetOption = panels.keybindsPanel.presets.list:getCurrentOption()
    if not presetOption then
        return
    end

    local chatMode = getActiveChatMode()
    local preset = presetOption.text

    for _, section in ipairs(keybindSections) do
        local _, rowsPanel = getKeybindSectionParts(section)
        if not rowsPanel then
            goto continue_refresh_section
        end

        for _, row in ipairs(rowsPanel:getChildren()) do
            if row.category and row.action then
                local keys = Keybind.getKeybindKeys(row.category, row.action, chatMode, preset,
                    changedOptions['resetKeybinds'])
                setKeyColumnDisplay(row:getChildByIndex(3), keys.primary)
                setKeyColumnDisplay(row:getChildByIndex(5), keys.secondary)
            end
        end

        ::continue_refresh_section::
    end
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

    setGeneralHotkeysTreeHelpVisible(not hasSearch)

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
        if #keybindSections == 0 then
            updateKeybinds()
        else
            refreshGeneralHotkeysKeyDisplays()
        end
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
        end
        keyEditWindow:destroy()
        keyEditWindow = nil
    end

    if actionSearchEvent then
        removeEvent(actionSearchEvent)
        actionSearchEvent = nil
    end

    cancelGeneralHotkeyInlineEdit()
    stopKeyColumnPulse()

    categoryExpandedState = {}
    keybindSections = {}
    pendingKeybindsUpdate = false
    pendingKeybindsRefresh = false
end

function refreshGeneralHotkeysListIfNeeded()
    if pendingKeybindsRefresh or #keybindSections == 0 then
        updateKeybinds()
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
