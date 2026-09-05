local function getUsedHotkeyButton(key)
    if not key or key == "" then
        return nil
    end

    local normalizedKey = key:lower()
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            local hotkey = button.cache and button.cache.hotkey
            if hotkey and hotkey:lower() == normalizedKey then
                return button
            end
        end
    end
    return nil
end

local function invalidateHotkeyButtonCache()
    if clearHotkeyCache then
        clearHotkeyCache()
    end
end

local function isHotkeyUsedInternal(key, chatType, checkSecondary)
    if not key or not ApiJson.hasCurrentHotkeySet() then
        return false
    end

    for _, data in ipairs(ApiJson.getHotkeyEntries(chatType)) do
        if data["actionsetting"] and data["keysequence"] then
            local keyMatch = data["keysequence"]:lower() == key:lower()
            if checkSecondary then
                if data["secondary"] and keyMatch then
                    return true
                end
            elseif not data["secondary"] and keyMatch then
                return true
            end
        end
    end
    return false
end

local function isHotkeyUsed(key, secondary)
    if not secondary then
        secondary = false
    end

    local chatMode = modules.game_console.isChatEnabled() and 'chatOn' or 'chatOff'
    return isHotkeyUsedInternal(key, chatMode, secondary)
end

local assignHotkeyWindow = nil

function closeAssignHotkeyWindow()
    if assignHotkeyWindow and not assignHotkeyWindow:isDestroyed() then
        assignHotkeyWindow:destroy()
    end
    assignHotkeyWindow = nil
end

-- check game_hotkeys
local function isHotkeyUsedByGameHotkeys(keyCombo)
    if not keyCombo or keyCombo == "" then
        return false
    end

    if modules.game_hotkeys and modules.game_hotkeys.isHotkeyUsedByManager then
        return modules.game_hotkeys.isHotkeyUsedByManager(keyCombo)
    end

    return false
end

local function removeHotkeyFromGameHotkeys(keyCombo)
    if not keyCombo or keyCombo == "" then
        return false
    end

    if modules.game_hotkeys and modules.game_hotkeys.removeHotkeyByCombo then
        return modules.game_hotkeys.removeHotkeyByCombo(keyCombo)
    end

    return false
end

-- check keybind
local function isHotkeyUsedByKeybinds(keyCombo)
    if not keyCombo or keyCombo == "" then
        return false
    end

    if Keybind and Keybind.isKeyComboUsed then
        if Keybind.isKeyComboUsed(keyCombo, nil, nil, CHAT_MODE.ON) then
            return true
        end
        if Keybind.isKeyComboUsed(keyCombo, nil, nil, CHAT_MODE.OFF) then
            return true
        end
    end

    return false
end

function removeHotkeyFromActionBar(keyCombo)
    if not keyCombo or keyCombo == "" then
        return false
    end
    local button = getUsedHotkeyButton(keyCombo)
    if button then
        ApiJson.removeHotkey(button:getId())
        unbindHotkey(keyCombo)
        invalidateHotkeyButtonCache()
        updateButton(button)
        return true
    end
    return false
end
function assignHotkey(button)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end

    closeAssignHotkeyWindow()
    if closeAllAssignWindows then
        closeAllAssignWindows('hotkey')
    end

    local ok, assignWindow = pcall(function()
        return g_ui.loadUI('/modules/game_actionbar/assign_hotkey', g_ui.getRootWidget())
    end)
    if not ok or not assignWindow then
        perror('Failed to open Assign Hotkey window: ' .. tostring(assignWindow))
        return
    end

    assignHotkeyWindow = assignWindow
    assignWindow.hotkeyBlock = modules.game_hotkeys.createHotkeyBlock("actionbar_assign_hotkey")
    assignWindow.onDestroy = function()
        if assignHotkeyWindow ~= assignWindow then
            return
        end
        if assignWindow.hotkeyBlock then
            assignWindow.hotkeyBlock:release()
            assignWindow.hotkeyBlock = nil
        end
        assignHotkeyWindow = nil
    end

    local barN = button:getParent():getParent().n
    local barDesc
    if barN < 4 then
        barDesc = "Bottom"
    elseif barN < 7 then
        barDesc = "Left"
    else
        barDesc = "Right"
    end

    barDesc = barDesc .. " Action Bar: Action Button " .. button:getId()
    assignWindow:setText('Edit Hotkey for "' .. barDesc .. '"')

    local content = assignWindow:getChildById('contentPanel') or assignWindow.contentPanel
    local chatMode = content and (content:getChildById('chatMode') or content.chatMode)
    local display = assignWindow:recursiveGetChildById('comboPreview')
    local desc = content and (content:getChildById('desc') or content.desc)
    local warning = content and (content:getChildById('warning') or content.warning)
    local buttonOk = content and (content:getChildById('buttonOk') or content.buttonOk)
    local buttonClear = content and (content:getChildById('buttonClear') or content.buttonClear)
    local buttonClose = content and (content:getChildById('buttonClose') or content.buttonClose)
    if not chatMode or not display or not desc or not warning or not buttonOk or not buttonClear or not buttonClose then
        perror('Assign Hotkey widgets missing')
        closeAssignHotkeyWindow()
        return
    end

    desc:setText('Click "Ok" to assign the hotkey. Click "Clear" to remove the hotkey from "' .. barDesc .. '".')

    -- comboPreview is an OTUI Label, so setText renders the captured key
    -- directly. While a combo is shown it is highlighted in light yellow.
    local pendingCombo = ""
    local function setDisplayText(text)
        text = text or ""
        display:setText(text)
        if text == "" then
            display:setColor("#909090")
        else
            display:setColor("#ffff66")
        end
        display:resizeToText()
    end

    local currentHotkey = (button.cache and button.cache.hotkey) or ""
    pendingCombo = currentHotkey
    setDisplayText(currentHotkey)

    local chatOn = modules.game_console.isChatEnabled()
    chatMode:setText(chatOn and 'Mode: "Chat On"' or 'Mode: "Chat Off"')

    assignWindow:show()
    assignWindow:raise()
    assignWindow:focus()
    assignWindow:centerIn('parent')
    assignWindow:grabKeyboard()

    local resetCombo = { Shift = true, Ctrl = true, Alt = true }

    -- Previews a captured combo in the assign dialog: updates the display,
    -- runs the conflict checks and toggles Ok accordingly. Both the keyboard
    -- and the mouse capture go through here.
    local function previewCombo(keyCombo, displayText)
        if resetCombo[keyCombo] then
            pendingCombo = ''
            setDisplayText('')
            warning:setVisible(false)
            buttonOk:setEnabled(true)
            return true
        end

        pendingCombo = keyCombo
        setDisplayText(displayText or keyCombo)
        warning:setVisible(false)
        buttonOk:setEnabled(true)

        if isHotkeyUsed(keyCombo) then
            warning:setVisible(true)
            warning:setText("This hotkey is already in use in Action Bar and will be overwritten.")
        end

        -- check game_hotkeys
        if isHotkeyUsedByGameHotkeys(keyCombo) then
            warning:setVisible(true)
            warning:setText("This hotkey is already in use in Hotkeys Manager and will be overwritten.")
        end

        -- check keybinds
        if isHotkeyUsedByKeybinds(keyCombo) then
            warning:setVisible(true)
            warning:setText("This hotkey is already in use in Keybinds and will be overwritten.")
            buttonOk:disable()
            return true
        end
        if table.contains(blockedKeys, keyCombo) then
            warning:setVisible(true)
            warning:setText("This hotkey is already in use and cannot be overwritten.")
            buttonOk:setEnabled(false)
        end
        return true
    end

    assignWindow.onKeyDown = function(window, keyCode, keyboardModifiers, keyText)
        local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
        if keyCombo then
            local shortCut = (keyCombo == "HalfQuote" and "'" or keyCombo)
            previewCombo(keyCombo, shortCut)
        end
        return true
    end

    assignWindow.onMousePress = function(window, mousePos, rawButton)
        local keyCombo = Keybind.getMouseKeyCombo(rawButton)
        if not keyCombo then
            return false
        end
        return previewCombo(keyCombo)
    end

    local okFunc = function()
        local lastHotkey = (button.cache and button.cache.hotkey) or ""
        local hotkey = pendingCombo or ""

        if hotkey == "" then
            if lastHotkey ~= "" then
                ApiJson.removeHotkey(button:getId())
                unbindHotkey(lastHotkey)
                invalidateHotkeyButtonCache()
                updateButton(button)
            end

            closeAssignHotkeyWindow()
            return true
        end

        ApiJson.clearHotkey(hotkey)
       if isHotkeyUsedByGameHotkeys(hotkey) then
            removeHotkeyFromGameHotkeys(hotkey)
        end
        local usedButton = getUsedHotkeyButton(hotkey)
        if usedButton then
            ApiJson.removeHotkey(usedButton:getId())
            unbindHotkey(hotkey)
        else
            unbindHotkey(hotkey)
        end

        if lastHotkey ~= "" and lastHotkey ~= hotkey then
            ApiJson.removeHotkey(button:getId())
            unbindHotkey(lastHotkey)
        end

        ApiJson.updateActionBarHotkey("TriggerActionButton_" .. button:getId(), hotkey)
        invalidateHotkeyButtonCache()
        if usedButton and usedButton ~= button then
            updateButton(usedButton)
        end
        updateButton(button)

        closeAssignHotkeyWindow()
    end

    local clearFunc = function()
        local assignedHotkey = (button.cache and button.cache.hotkey) or ""
        ApiJson.removeHotkey(button:getId())
        if assignedHotkey ~= '' then
            unbindHotkey(assignedHotkey)
        end

        invalidateHotkeyButtonCache()
        updateButton(button)
        pendingCombo = ''
        setDisplayText('')
        closeAssignHotkeyWindow()
    end

    local closeFunc = function()
        closeAssignHotkeyWindow()
    end

    buttonOk.onClick = okFunc
    buttonClear.onClick = clearFunc
    buttonClose.onClick = closeFunc

    assignWindow.onEnter = okFunc
    assignWindow.onEscape = closeFunc
end

function unbindHotkey(hotkey)
    if not gameRootPanel or not hotkey or hotkey == '' then
        return
    end

    if Keybind and Keybind.isMouseKey and Keybind.isMouseKey(hotkey) then
        Keybind.unbindMouseButtonKey(hotkey, gameRootPanel)
        return
    end

    g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
    g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
    g_keyboard.unbindKeyUp(hotkey, nil, gameRootPanel)
end
