local standModeBox
local chaseModeBox
local optionsAmount = 0
local specialsAmount = 0
local storeAmount = 0

local chaseModeRadioGroup
local optionPanel = nil
local buttonConfigs = {}
local buttonOrder = {}
local configLoaded = false

local COLORS = {
    BASE_1 = "#484848",
    BASE_2 = "#414141"
}

local PANEL_CONSTANTS = {
    ICON_WIDTH = 18,
    ICON_HEIGHT = 18,
    MAX_ICONS_PER_ROW = {
        OPTIONS = 5,
        SPECIALS = 2,
        STORE = 1
    },
    MULTI_STORE_HEIGHT = 20,
    HEIGHT_EXTRA_ONPANEL = -5,
    HEIGHT_EXTRA_SHRINK = 5
}

local optionsShrink = false

ControlButtonNames = {
    skillsButton = 'Skills',
    battleButton = 'Battle List',
    vipListButton = 'VIP List',
    unjustifiedPointsButton = 'Unjustified Points',
    questLogButton = 'Quest Log',
    questTrackerButton = 'Quest Tracker',
    highscoresButton = 'Highscores',
    ProficiencyButton = 'Weapon Proficiency',
    forgeButton = 'Exaltation Forge',
    wheelButton = 'Wheel of Destiny',
    imbuementTrackerButton = 'Imbuement Tracker',
    rewardWall = 'Reward Wall',
    spelllistButton = 'Spell List',
    analyzerButton = 'Analytics Selector',
    botAnalyzersButton = 'vBot Analyzers',
    manageControlButtons = 'Manage Control Buttons',
    optionsMainButton = 'Options',
    preyButton = 'Prey Dialog',
    cyclopediaButton = 'Cyclopedia',
    bestiaryTrackerButton = 'Bestiary Tracker',
    botButton = 'Bot Hub',
}

local MANAGE_CONTROL_BUTTONS_ID = 'manageControlButtons'
local MANAGE_CONTROL_BUTTONS_INDEX = 9999

local function getControlButtonDisplayName(id, button)
    if ControlButtonNames[id] then
        return ControlButtonNames[id]
    end
    if button and button.getTooltip then
        local tooltip = button:getTooltip()
        if type(tooltip) == 'string' and tooltip ~= '' then
            return tooltip:gsub('%s*%b()$', '')
        end
    end
    return id
end

local function calculatePanelHeight(panel, max_icons_per_row)
    local icon_count = 0
    for _, icon in ipairs(panel:getChildren()) do
        if icon:isVisible() then
            icon_count = icon_count + 1
        end
    end
    local rows = math.ceil(icon_count / max_icons_per_row)
    local height = (rows * PANEL_CONSTANTS.ICON_HEIGHT) + (rows * 3)
    return height, icon_count
end

function reloadMainPanelSizes()
    local main_panel = modules.game_interface.getMainRightPanel()
    local right_panel = modules.game_interface.getRightPanel()
    if not main_panel or not right_panel then
        return
    end
    local total_height = 1
    for _, panel in ipairs(main_panel:getChildren()) do
        if panel.panelHeight ~= nil then
            if panel:isVisible() then
                panel:setHeight(panel.panelHeight)
                total_height = total_height + panel.panelHeight
                if panel:getId() == 'mainoptionspanel' then
                    if panel:isOn() then
                        local options_panel = optionsController.ui.onPanel.options
                        local options_height, options_count =
                            calculatePanelHeight(options_panel, PANEL_CONSTANTS.MAX_ICONS_PER_ROW.OPTIONS)
                        local specials_panel = optionsController.ui.onPanel.specials
                        local specials_height, specials_count =
                            calculatePanelHeight(specials_panel, PANEL_CONSTANTS.MAX_ICONS_PER_ROW.SPECIALS)
                        local store_panel = panel.onPanel.store
                        local store_height, store_count = calculatePanelHeight(store_panel,
                            PANEL_CONSTANTS.MAX_ICONS_PER_ROW.STORE)
                        if store_count > 0 then
                            store_height = store_count * PANEL_CONSTANTS.MULTI_STORE_HEIGHT + (store_count - 1) * 2
                        end
                        local combined_height = store_height + math.max(options_height, specials_height)
                        local extra_height = PANEL_CONSTANTS.HEIGHT_EXTRA_ONPANEL
                        if store_count >= 2 then
                            extra_height = extra_height - (store_count - 1) * 5
                        end
                        combined_height = combined_height + extra_height
                        store_panel:setHeight(store_height)
                        panel:setHeight(combined_height + panel.panelHeight)
                        total_height = total_height + combined_height
                    else
                        total_height = total_height + PANEL_CONSTANTS.HEIGHT_EXTRA_SHRINK
                    end
                end
            else
                panel:setHeight(0)
            end
        end
    end
    main_panel:setHeight(total_height)
    right_panel:fitAll()
end

local function refreshOptionsSizes()
    if optionsShrink then
        optionsController.ui:setOn(false)
        optionsController.ui.offPanel:show()
    else
        optionsController.ui:setOn(true)
        optionsController.ui.offPanel:hide()
    end
    reloadMainPanelSizes()
end

local function createButton_large(id, description, image, callback, special, front)
    local panel = optionsController.ui.onPanel.store

    storeAmount = storeAmount + 1

    local button = panel:getChildById(id)
    if not button then
        button = g_ui.createWidget('largeToggleButton')
        if front then
            panel:insertChild(1, button)
        else
            panel:addChild(button)
        end
    end
    button:setId(id)
    button:setTooltip(description)
    button:setImageSource(image)
    button:setImageClip('0 0 108 20')
    if button.setImageBorder then
        button:setImageBorder(0)
    end
    button.onMouseRelease = function(widget, mousePos, mouseButton)
        if widget:containsPoint(mousePos) and mouseButton ~= MouseMidButton then
            callback()
            return true
        end
    end

    -- APNG shine overlay (same effect as AstraClient Battle Pass button)
    if not button:getChildById('storeBright') then
        local bright = g_ui.createWidget('UIWidget', button)
        bright:setId('storeBright')
        bright:setPhantom(true)
        bright:fill('parent')
        bright:setImageSource('/images/store/button-store-bright')
    end

    -- Gold frame around the Store button (Astra battlePassBorder)
    local onPanel = optionsController.ui.onPanel
    if onPanel and not onPanel:getChildById('storeBorder') then
        local border = g_ui.createWidget('UIWidget', onPanel)
        border:setId('storeBorder')
        border:setPhantom(true)
        border:setWidth(111)
        border:setHeight(22)
        border:addAnchor(AnchorTop, 'store', AnchorTop)
        border:addAnchor(AnchorLeft, 'store', AnchorLeft)
        border:setMarginTop(-1)
        border:setMarginLeft(-1)
        border:setImageSource('/images/store/rectangle-highlight')
        border:raise()
    end

    return button
end

local function createGoldFrame(panel, targetId, borderId)
    if not panel or panel:isDestroyed() or panel:getChildById(borderId) then
        return
    end

    local target = panel:getChildById(targetId)
    if not target or target:isDestroyed() then
        return
    end

    local border = g_ui.createWidget('UIWidget', panel)
    border:setId(borderId)
    border:setPhantom(true)
    border:addAnchor(AnchorTop, targetId, AnchorTop)
    border:addAnchor(AnchorLeft, targetId, AnchorLeft)
    border:addAnchor(AnchorBottom, targetId, AnchorBottom)
    border:addAnchor(AnchorRight, targetId, AnchorRight)
    border:setMarginTop(-1)
    border:setMarginLeft(-1)
    border:setMarginBottom(-1)
    border:setMarginRight(-1)
    border:setImageSource('/images/store/rectangle-highlight')
    -- El marco tiene 1px de grosor: sin 9-slice el escalado horizontal borra los lados
    border:setImageBorder(1)
    border:raise()
end

local function sortOptionsButtons()
    if not optionsController or not optionsController.ui then
        return
    end
    local panel = optionsController.ui.onPanel.options
    if not panel then
        return
    end
    local children = panel:getChildren()
    for i, child in ipairs(children) do
        child._stableOrder = child._stableOrder or i
    end
    table.sort(children, function(a, b)
        local aIdx = a.index or 1000
        local bIdx = b.index or 1000
        if aIdx ~= bIdx then
            return aIdx < bIdx
        end
        return (a._stableOrder or 0) < (b._stableOrder or 0)
    end)
    if #children == #panel:getChildren() then
        panel:reorderChildren(children)
    end
end

local function createButton(id, description, image, callback, special, front, index)
    local panel
    if special then
        panel = optionsController.ui.onPanel.specials
        specialsAmount = specialsAmount + 1
    else
        panel = optionsController.ui.onPanel.options
        optionsAmount = optionsAmount + 1
    end

    local button = panel:getChildById(id)
    if not button then
        button = g_ui.createWidget('MainToggleButton')
        if front then
            panel:insertChild(1, button)
        else
            panel:addChild(button)
        end
    end

    button:setId(id)
    button:setTooltip(description)
    button:setSize('20 20')
    button:setImageSource(image)
    button:setImageClip('0 0 20 20')
    button.onMouseRelease = function(widget, mousePos, mouseButton)
        if widget:containsPoint(mousePos) and mouseButton ~= MouseMidButton then
            callback()
            return true
        end
    end
    if not button.index and type(index) == 'number' then
        button.index = index or 1000
    end

    if not special and g_game.isOnline() then
        scheduleControlButtonsSync()
    elseif not special and not configLoaded then
        sortOptionsButtons()
    end
    refreshOptionsSizes()
    return button
end


optionsController = Controller:new()
optionsController:setUI('mainoptionspanel', modules.game_interface.getMainRightPanel())

function optionsController:onInit()
    createButton_large('Store shop', tr('Store shop'), '/images/store/button-store-up', toggleStore,
    false, 8)
    createGoldFrame(optionsController.ui.onPanel, 'resizer', 'resizerBorder')
    createGoldFrame(optionsController.ui.offPanel, 'collapsedResizer', 'collapsedResizerBorder')

    if not optionPanel then
        optionPanel = g_ui.loadUI('option_control_buttons', modules.client_options:getPanel())
        modules.client_options.addButton("Interface", "Control Butt...", optionPanel, function() initControlButtons() end)
        bindControlButtonsPanelEvents()
    end
end

local function updateMoveToDisplayedButtonState(button, hasAvailableButtons)
    if not button then
        return
    end

    button:setEnabled(hasAvailableButtons)
    if button.setOpacity then
        button:setOpacity(hasAvailableButtons and 1.0 or 0.35)
    end
end

function bindControlButtonsPanelEvents()
    if not optionPanel or optionPanel.controlButtonsEventsBound then
        return
    end

    optionPanel.controlButtonsEventsBound = true
    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local availableList = optionPanel.panelAvailableButtons.displayedAvailableButtonsList

    if displayedList then
        displayedList.onChildFocusChange = function()
            updateControlButtonsActionStates()
        end
    end

    if availableList then
        availableList.onChildFocusChange = function()
            updateControlButtonsActionStates()
        end
    end
end

function updateControlButtonsActionStates()
    if not optionPanel then
        return
    end

    local availableList = optionPanel.panelAvailableButtons.displayedAvailableButtonsList
    local moveToDisplayedBtn = optionPanel.panelAvailableButtons.moveToDisplayedButtonsList
    local availableCount = availableList and #availableList:getChildren() or 0

    updateMoveToDisplayedButtonState(moveToDisplayedBtn, availableCount > 0)
end

function toggleStore()
    modules.game_store.toggle()
end

function optionsController:onTerminate()
    if optionPanel then
        optionPanel:destroy()
        optionPanel = nil
        modules.client_options.removeButton("Interface", "Control Butt...")  -- hot reload
    end
end

function optionsController:onGameStart()
    optionsShrink = g_settings.getBoolean('mainpanel_shrink_options')
    local config = loadButtonConfig()
    buttonConfigs = config.buttons or {}
    buttonOrder = config.order or {}

    refreshOptionsSizes()
    modules.game_interface.setupOptionsMainButton()
    modules.client_options.setupOptionsMainButton()

    optionsController:scheduleEvent(function()
        syncControlButtons(true)
        if optionPanel then
            updateDisplayedButtonsList()
            updateAvailableButtonsList()
        end
        configLoaded = true
    end, 50, "onGameStart")

    optionsController:scheduleEvent(function()
        syncControlButtons(true)
        if optionPanel then
            updateDisplayedButtonsList()
            updateAvailableButtonsList()
        end
    end, 300, "onGameStartLateSync")
end

function optionsController:onGameEnd()
    configLoaded = false
end

function changeOptionsSize()
    optionsShrink = not optionsShrink
    g_settings.set('mainpanel_shrink_options', optionsShrink)
    refreshOptionsSizes()
end

function addToggleButton(id, description, image, callback, front, index)
    return createButton(id, description, image, callback, false, front, index)
end

function addSpecialToggleButton(id, description, image, callback, front, index)
    return createButton(id, description, image, callback, true, front, index)
end

function addStoreButton(id, description, image, callback, front)
    return createButton_large(id, description, image, callback, true, front)
end

function getButton(id)
    return optionsController.ui.onPanel.options:recursiveGetChildById(id)
end

function ensureControlButtonVisible(id)
    if not id or not g_game.isOnline() then
        return false
    end

    local optionsPanel = optionsController and optionsController.ui and optionsController.ui.onPanel and
        optionsController.ui.onPanel.options
    if not optionsPanel then
        return false
    end

    local button = optionsPanel:getChildById(id)
    if not button then
        return false
    end

    if not buttonConfigs[id] then
        buttonConfigs[id] = {
            visible = true,
            tooltip = getControlButtonDisplayName(id, button)
        }
    else
        buttonConfigs[id].visible = true
    end

    if not table.find(buttonOrder, id) then
        table.insert(buttonOrder, id)
    end

    button:setVisible(true)
    reorderButtons()
    reloadMainPanelSizes()
    saveButtonConfig()
    return true
end

function toggleExtendedViewButtons(extended)
    local optionsPanel = optionsController.ui.onPanel.options
    local specialsPanel = optionsController.ui.onPanel.store
    local rightGamePanel = modules.client_topmenu.getRightGameButtonsPanel()
    if extended then
        local optionChildren = optionsPanel:getChildren()
        for _, button in ipairs(optionChildren) do
            if not button:isDestroyed() then
                button.originalPanel = "options"
                rightGamePanel:addChild(button)
            end
        end
        local specialChildren = specialsPanel:getChildren()
        for _, button in ipairs(specialChildren) do
            if not button:isDestroyed() then
                button.originalPanel = "specials"
                rightGamePanel:addChild(button)
            end
        end
        optionsController.ui:hide()
        optionsController.ui:setHeight(0)
    else
        local children = rightGamePanel:getChildren()
        for _, button in ipairs(children) do
            if not button:isDestroyed() then
                if button.originalPanel == "options" then
                    optionsPanel:addChild(button)
                elseif button.originalPanel == "specials" then
                    specialsPanel:addChild(button)
                end
            end
        end
        optionsController.ui:show()
        optionsController.ui:setHeight(28)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if mainRightPanel:hasChild(optionsController.ui) then
            mainRightPanel:moveChildToIndex(optionsController.ui, 4)
        end
    end
    refreshOptionsSizes()
end

function saveButtonConfig()
    local config = {
        buttons = {},
        order = {}
    }
    for id, buttonConfig in pairs(buttonConfigs) do
        if type(id) == "string" and type(buttonConfig) == "table" then
            config.buttons[id] = {
                visible = buttonConfig.visible,
                tooltip = buttonConfig.tooltip
            }
        end
    end
    for i, id in ipairs(buttonOrder) do
        config.order[tostring(i)] = id
    end
    g_settings.setNode('control_buttons', config)
end

function loadButtonConfig()
    local config = g_settings.getNode('control_buttons') or {
        buttons = {},
        order = {}
    }
    local orderArray = {}
    if config.order then
        local keys = {}
        for k in pairs(config.order) do
            table.insert(keys, tonumber(k))
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            table.insert(orderArray, config.order[tostring(k)])
        end
    end

    return {
        buttons = config.buttons or {},
        order = orderArray
    }
end

local function updateList(listWidget, isVisibleList)
    if not g_game.isOnline() or not listWidget then
        return
    end
    local focusedItem = listWidget:getFocusedChild()
    local focusedId = focusedItem and focusedItem.buttonId
    local existingItems = {}
    for _, child in ipairs(listWidget:getChildren()) do
        existingItems[child.buttonId] = child
    end
    local displayButtons = {}
    for id, config in pairs(buttonConfigs) do
        if (config.visible == true) == isVisibleList then
            table.insert(displayButtons, {
                id = id,
                config = config
            })
        end
    end
    if isVisibleList then
        table.sort(displayButtons, function(a, b)
            local indexA = table.find(buttonOrder, a.id) or 999
            local indexB = table.find(buttonOrder, b.id) or 999
            if indexA ~= indexB then
                return indexA < indexB
            end
            return a.id < b.id
        end)
    end
    for buttonId, item in pairs(existingItems) do
        local shouldBeInList = false
        for _, buttonData in ipairs(displayButtons) do
            if buttonData.id == buttonId then
                shouldBeInList = true
                break
            end
        end
        if not shouldBeInList then
            item:destroy()
            existingItems[buttonId] = nil
        end
    end

    local currentChildren = {}
    for i, buttonData in ipairs(displayButtons) do
        local buttonId = buttonData.id
        local buttonConfig = buttonData.config
        local item = existingItems[buttonId]
        if not item then
            item = g_ui.createWidget('HotkeyListLabel', listWidget)
            item:setId(buttonId)
            item.buttonId = buttonId
            item:setText(buttonConfig.tooltip)
            item:setTextAlign(AlignLeft)
        end
        if not item:isFocused() then
            item:setBackgroundColor((i % 2 == 0) and COLORS.BASE_1 or COLORS.BASE_2)
        end

        item.onDoubleClick = function(widget)
            widget:focus()
            if isVisibleList then
                moveToAvailable()
            else
                moveToDisplayed()
            end
        end

        item.onFocusChange = function()
            updateControlButtonsActionStates()
        end

        table.insert(currentChildren, item)
    end
    local panelChildren = listWidget:getChildren()
    if #currentChildren == #panelChildren then
        listWidget:reorderChildren(currentChildren)
    end
    if focusedId then
        for _, child in ipairs(listWidget:getChildren()) do
            if child.buttonId == focusedId then
                child:focus()
                break
            end
        end
    end
    updateControlButtonsActionStates()
end

function updateDisplayedButtonsList()
    updateList(optionPanel.panelDisplayedButtons.displayedButtonsList, true)
end

function updateAvailableButtonsList()
    updateList(optionPanel.panelAvailableButtons.displayedAvailableButtonsList, false)
end

function moveToAvailable()
    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local selectedItem = displayedList:getFocusedChild()

    if not selectedItem then
        return
    end

    local buttonId = selectedItem.buttonId
    local optionsPanel = optionsController.ui.onPanel.options
    local button = optionsPanel:getChildById(buttonId)
    if button then
        button:setVisible(false)
        buttonConfigs[buttonId].visible = false
        table.removevalue(buttonOrder, buttonId)
        updateDisplayedButtonsList()
        updateAvailableButtonsList()
        saveButtonConfig()
        reloadMainPanelSizes()
        displayedList:focusNextChild(KeyboardFocusReason)
    end
end

function moveToDisplayed()
    local availableList = optionPanel.panelAvailableButtons.displayedAvailableButtonsList
    local selectedItem = availableList:getFocusedChild()

    if not selectedItem then
        return
    end

    local buttonId = selectedItem.buttonId
    local optionsPanel = optionsController.ui.onPanel.options
    local button = optionsPanel:getChildById(buttonId)

    if button then
        button:setVisible(true)
        buttonConfigs[buttonId].visible = true
        table.insert(buttonOrder, buttonId)
        updateDisplayedButtonsList()
        updateAvailableButtonsList()
        reorderButtons()
        saveButtonConfig()
        reloadMainPanelSizes()
        availableList:focusNextChild(KeyboardFocusReason)
    end
end

function moveButtonUp()
    if not g_game.isOnline() then
        return
    end

    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local selectedItem = displayedList:getFocusedChild()

    if not selectedItem then
        return
    end

    local buttonId = selectedItem.buttonId
    local index = table.find(buttonOrder, buttonId)

    if index and index > 1 then
        buttonOrder[index], buttonOrder[index - 1] = buttonOrder[index - 1], buttonOrder[index]
        updateDisplayedButtonsList()
        reorderButtons()
        saveButtonConfig()
        local focusedChild = displayedList:getFocusedChild()
        if focusedChild then
            displayedList:ensureChildVisible(focusedChild)
        end
    end
end

function moveButtonDown()
    if not g_game.isOnline() then
        return
    end

    local displayedList = optionPanel.panelDisplayedButtons.displayedButtonsList
    local selectedItem = displayedList:getFocusedChild()

    if not selectedItem then
        return
    end

    local buttonId = selectedItem.buttonId
    local index = table.find(buttonOrder, buttonId)

    if index and index < #buttonOrder then
        buttonOrder[index], buttonOrder[index + 1] = buttonOrder[index + 1], buttonOrder[index]

        updateDisplayedButtonsList()
        reorderButtons()
        saveButtonConfig()
        local focusedChild = displayedList:getFocusedChild()
        if focusedChild then
            displayedList:ensureChildVisible(focusedChild)
        end
    end
end

function reorderButtons()
    if not g_game.isOnline() then
        return
    end
    local optionsPanel = optionsController.ui.onPanel.options
    if not optionsPanel then
        return
    end

    local panelChildren = optionsPanel:getChildren()
    local children = {}
    local seen = {}

    for _, id in ipairs(buttonOrder) do
        if not seen[id] then
            local button = optionsPanel:getChildById(id)
            if button then
                table.insert(children, button)
                seen[id] = true
            end
        end
    end

    for _, button in ipairs(panelChildren) do
        local id = button:getId()
        if id and not seen[id] then
            table.insert(children, button)
            seen[id] = true
        end
    end

    if #children == #panelChildren then
        optionsPanel:reorderChildren(children)
    end
end

local pendingControlButtonsSync = false

function scheduleControlButtonsSync()
    if pendingControlButtonsSync or not g_game.isOnline() then
        return
    end

    pendingControlButtonsSync = true
    scheduleEvent(function()
        pendingControlButtonsSync = false
        syncControlButtons(true)
    end, 0)
end

function syncControlButtons(persist)
    if not g_game.isOnline() then
        return
    end

    local optionsPanel = optionsController and optionsController.ui and optionsController.ui.onPanel and optionsController.ui.onPanel.options
    if not optionsPanel then
        return
    end

    local changed = false
    local knownIds = {}

    for _, button in ipairs(optionsPanel:getChildren()) do
        local id = button:getId()
        if id then
            knownIds[id] = true
            if not button.index and id == MANAGE_CONTROL_BUTTONS_ID then
                button.index = MANAGE_CONTROL_BUTTONS_INDEX
            end
            if not buttonConfigs[id] then
                buttonConfigs[id] = {
                    visible = table.find(buttonOrder, id) ~= nil or button:isVisible(),
                    tooltip = getControlButtonDisplayName(id, button)
                }
                changed = true
            end
            button:setVisible(buttonConfigs[id].visible)
        end
    end

    local panelButtonCount = 0
    for _ in pairs(knownIds) do
        panelButtonCount = panelButtonCount + 1
    end

    local orderKnownCount = 0
    for _, id in ipairs(buttonOrder) do
        if knownIds[id] then
            orderKnownCount = orderKnownCount + 1
        end
    end

    if orderKnownCount > 0 and orderKnownCount < panelButtonCount and buttonOrder[1] == MANAGE_CONTROL_BUTTONS_ID then
        local repaired = {}
        local seen = {}
        for _, id in ipairs(buttonOrder) do
            if id ~= MANAGE_CONTROL_BUTTONS_ID and knownIds[id] and buttonConfigs[id].visible then
                table.insert(repaired, id)
                seen[id] = true
            end
        end
        local missing = {}
        for id in pairs(knownIds) do
            if not seen[id] and id ~= MANAGE_CONTROL_BUTTONS_ID and buttonConfigs[id].visible then
                local button = optionsPanel:getChildById(id)
                table.insert(missing, {
                    id = id,
                    index = button and button.index or 1000
                })
            end
        end
        table.sort(missing, function(a, b)
            return a.index < b.index
        end)
        for _, entry in ipairs(missing) do
            table.insert(repaired, entry.id)
            seen[entry.id] = true
        end
        if knownIds[MANAGE_CONTROL_BUTTONS_ID] and buttonConfigs[MANAGE_CONTROL_BUTTONS_ID].visible then
            table.insert(repaired, MANAGE_CONTROL_BUTTONS_ID)
        end
        buttonOrder = repaired
        changed = true
    end

    local missingManage = false
    local missingOthers = {}
    for id in pairs(knownIds) do
        if not table.find(buttonOrder, id) and buttonConfigs[id].visible then
            if id == MANAGE_CONTROL_BUTTONS_ID then
                missingManage = true
            else
                local button = optionsPanel:getChildById(id)
                table.insert(missingOthers, {
                    id = id,
                    index = button and button.index or 1000
                })
            end
        end
    end

    table.sort(missingOthers, function(a, b)
        return a.index < b.index
    end)

    for _, entry in ipairs(missingOthers) do
        table.insert(buttonOrder, entry.id)
        changed = true
    end

    if missingManage then
        if not buttonConfigs[MANAGE_CONTROL_BUTTONS_ID] then
            local button = optionsPanel:getChildById(MANAGE_CONTROL_BUTTONS_ID)
            buttonConfigs[MANAGE_CONTROL_BUTTONS_ID] = {
                visible = button and button:isVisible() or true,
                tooltip = getControlButtonDisplayName(MANAGE_CONTROL_BUTTONS_ID, button)
            }
        end
        table.insert(buttonOrder, MANAGE_CONTROL_BUTTONS_ID)
        changed = true
    end

    for i = #buttonOrder, 1, -1 do
        if not knownIds[buttonOrder[i]] or not buttonConfigs[buttonOrder[i]].visible then
            table.remove(buttonOrder, i)
            changed = true
        end
    end

    reorderButtons()
    reloadMainPanelSizes()

    if persist and changed then
        saveButtonConfig()
    end
end

function reset()
    g_settings.setNode('control_buttons', {})
    buttonConfigs = {}
    buttonOrder = {}
    local optionsPanel = optionsController.ui.onPanel.options
    if optionsPanel then
        for _, button in ipairs(optionsPanel:getChildren()) do
            local id = button:getId()
            if id then
                button:setVisible(true)
                buttonConfigs[id] = {
                    visible = true,
                    tooltip = getControlButtonDisplayName(id, button)
                }
                table.insert(buttonOrder, id)
            end
        end
        for i, id in ipairs(buttonOrder) do
            if id == MANAGE_CONTROL_BUTTONS_ID then
                table.remove(buttonOrder, i)
                table.insert(buttonOrder, MANAGE_CONTROL_BUTTONS_ID)
                break
            end
        end
    end
    updateDisplayedButtonsList()
    updateAvailableButtonsList()
    reorderButtons()
    reloadMainPanelSizes()
end

function initControlButtons()
    local config = loadButtonConfig()
    buttonConfigs = config.buttons or {}
    buttonOrder = config.order or {}
    local currentButtons = {}
    for _, button in ipairs(optionsController.ui.onPanel.options:getChildren()) do
        local id = button:getId()
        if id then
            currentButtons[id] = true
            if not buttonConfigs[id] then
                buttonConfigs[id] = {
                    visible = button:isVisible(),
                    tooltip = getControlButtonDisplayName(id, button)
                }

                if button:isVisible() and not table.find(buttonOrder, id) and id ~= MANAGE_CONTROL_BUTTONS_ID then
                    table.insert(buttonOrder, id)
                end
            else
                button:setVisible(buttonConfigs[id].visible)
            end
        end
    end

    local toRemove = {}
    for id in pairs(buttonConfigs) do
        if not currentButtons[id] then
            table.insert(toRemove, id)
        end
    end

    for _, id in ipairs(toRemove) do
        buttonConfigs[id] = nil
        for i, orderId in ipairs(buttonOrder) do
            if orderId == id then
                table.remove(buttonOrder, i)
                break
            end
        end
    end
    updateDisplayedButtonsList()
    updateAvailableButtonsList()
    syncControlButtons(false)
    reloadMainPanelSizes()
end
