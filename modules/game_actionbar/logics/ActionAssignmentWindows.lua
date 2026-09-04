-- /*=============================================
-- =            Assign Spell                      =
-- =============================================*/
local function string_empty(str)
    return #str == 0
end

local assignSpellWindow = nil
local assignSpellRadio = nil

function closeAssignSpellWindow()
    if assignSpellRadio then
        assignSpellRadio:destroy()
        assignSpellRadio = nil
    end
    if assignSpellWindow and not assignSpellWindow:isDestroyed() then
        assignSpellWindow:destroy()
    end
    assignSpellWindow = nil
end

function assignSpell(button, multiSlotIndex)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end

    closeAllAssignWindows('spell')

    local ok, window = pcall(function()
        return g_ui.loadUI('/modules/game_actionbar/spells', g_ui.getRootWidget())
    end)
    if not ok or not window then
        perror('Failed to open Assign Spell window: ' .. tostring(window))
        return
    end
    assignSpellWindow = window
    local currentSpellWindow = window
    window.onDestroy = function()
        if assignSpellWindow ~= currentSpellWindow then
            return
        end
        if assignSpellRadio then
            assignSpellRadio:destroy()
            assignSpellRadio = nil
        end
        assignSpellWindow = nil
    end

    local content = window:getChildById('contentPanel') or window.contentPanel
    if not content then
        perror('Assign Spell contentPanel missing')
        closeAssignSpellWindow()
        return
    end

    local spellList = content:getChildById('spellList') or content.spellList
    local previewWidget = content:getChildById('preview') or content.preview
    local paramLabel = content:getChildById('paramLabel') or content.paramLabel
    local paramText = content:getChildById('paramText') or content.paramText
    local searchText = content:getChildById('searchText') or content.searchText
    local clearButton = content:getChildById('clearButton') or content.clearButton
    local checkPanel = content:getChildById('checkPanel') or content.checkPanel
    local tickWidget = checkPanel and (checkPanel:getChildById('tick') or checkPanel.tick)
    local filterVocationWidget = checkPanel and (checkPanel:getChildById('filterVocation') or checkPanel.filterVocation)
    local sortByLevelWidget = checkPanel and (checkPanel:getChildById('sortByLevel') or checkPanel.sortByLevel)
    local buttonOk = content:getChildById('buttonOk') or content.buttonOk
    local buttonClose = content:getChildById('buttonClose') or content.buttonClose
    local buttonShowAll = content:getChildById('buttonShowAll') or content.buttonShowAll
    if not spellList or not previewWidget or not paramLabel or not paramText
        or not buttonOk or not buttonClose or not buttonShowAll then
        perror('Assign Spell widgets missing')
        closeAssignSpellWindow()
        return
    end

    local titleSuffix = multiSlotIndex and (" (Slot " .. multiSlotIndex .. ")") or ""
    window:setText("Assign Spell to Action Button " .. button:getId() .. titleSuffix)
    window:setId("assignSpellWindow")
    window:show()
    window:raise()
    window:focus()

    local playerVocation = player:getVocation()
    local playerLevel = player:getLevel()
    local spells = modules.gamelib.SpellInfo['Default']
    local defaultIconsFolder = SpelllistSettings['Default'].iconFile

    local okFunc = nil

    local function sortSpellWidgets()
        local sortByLevel = sortByLevelWidget and sortByLevelWidget:isChecked()
        return Spells.sortSpellWidgets(spellList, sortByLevel)
    end

    local function applyFilters()
        local search = searchText and searchText:getText() or ''
        local filterLevel = tickWidget and tickWidget:isChecked()
        local filterVocation = filterVocationWidget and filterVocationWidget:isChecked()
        Spells.filterSpellWidgets(spellList, search, playerLevel, filterLevel, playerVocation, filterVocation)
        sortSpellWidgets()
    end

    local function fillSpellList()
        if assignSpellRadio then
            assignSpellRadio:destroy()
        end
        spellList:destroyChildren()
        assignSpellRadio = UIRadioGroup.create()
        for spellName, spellData in pairs(spells) do
            local widget = g_ui.createWidget('SpellPreview', spellList)
            local spellId = spellData.clientId
            local clip = Spells.getImageClip(spellId)
            assignSpellRadio:addWidget(widget)
            widget:setId(spellData.id)
            widget:setText(spellName .. "\n" .. spellData.words)
            widget.words = spellData.words
            widget.voc = spellData.vocations
            widget.param = spellData.parameter
            widget.spellLevel = spellData.level or 0
            widget.source = defaultIconsFolder
            widget.clip = clip
            if widget.image then
                widget.image:setImageSource(widget.source)
                widget.image:setImageClip(widget.clip)
            end
            if spellData.level and widget.levelLabel then
                widget.levelLabel:setVisible(true)
                widget.levelLabel:setText(string.format("Level: %d", spellData.level))
                if widget.image and widget.image.gray then
                    widget.image.gray:setVisible(playerLevel < spellData.level)
                end
            end
            local primaryGroup = Spells.getPrimaryGroup(spellData)
            if primaryGroup ~= -1 and widget.imageGroup then
                local offSet = (primaryGroup == 2 and 20) or (primaryGroup == 3 and 40) or 0
                widget.imageGroup:setImageClip(offSet .. " 0 20 20")
                widget.imageGroup:setVisible(true)
            end

            widget.onDoubleClick = function(self)
                assignSpellRadio:selectWidget(self)
                if okFunc then
                    okFunc()
                end
                return true
            end
        end

        local widgets = sortSpellWidgets()

        assignSpellRadio.onSelectionChange = function(_, selected)
            if selected then
                previewWidget:setText(selected:getText())
                if previewWidget.image then
                    previewWidget.image:setImageSource(selected.source)
                    previewWidget.image:setImageClip(selected.clip)
                end
                paramLabel:setOn(selected.param)
                paramText:setEnabled(selected.param)
                paramText:clearText()
                if selected:getText():lower():find("levitate") then
                    paramText:setText("up|down")
                end
            end
        end

        applyFilters()

        local firstVisible = nil
        for _, widget in ipairs(spellList:getChildren()) do
            if widget:isVisible() then
                firstVisible = widget
                break
            end
        end
        if firstVisible then
            assignSpellRadio:selectWidget(firstVisible)
        end
        return widgets
    end

    local widgets = fillSpellList()

    local preselectSpellData = nil
    local preselectCastParam = nil
    if multiSlotIndex and button.cache and button.cache.multiActions then
        local slot = button.cache.multiActions[multiSlotIndex]
        if slot and slot["chatText"] then
            local spellData, param = Spells.getSpellDataByParamWords(slot["chatText"]:lower())
            if spellData then
                preselectSpellData = spellData
                if param then
                    preselectCastParam = param:gsub('"', '')
                end
            end
        end
    elseif button.cache.spellData and not button.cache.isRuneSpell then
        preselectSpellData = button.cache.spellData
        preselectCastParam = button.cache.castParam
    end

    if preselectSpellData then
        local spellData = preselectSpellData
        local spellId = spellData.clientId
        if not spellId then
            print("Warning Spell ID not found modules/game_actionbar/logics/ActionAssignmentWindows.lua")
            closeAssignSpellWindow()
            return
        end
        local clip = Spells.getImageClip(spellId, 'Default')
        previewWidget:setText((spellData.name or '') .. "\n" .. (spellData.words or ''))
        if previewWidget.image then
            previewWidget.image:setImageSource(defaultIconsFolder)
            previewWidget.image:setImageClip(clip)
        end
        paramLabel:setOn(spellData.parameter)
        paramText:setEnabled(spellData.parameter)
        if spellData.parameter and preselectCastParam then
            paramText:setText(preselectCastParam)
            paramText:setCursorPos(#preselectCastParam)
        end
        for _, k in ipairs(widgets) do
            if k:getId() == tostring(spellData.id) then
                assignSpellRadio:selectWidget(k)
                spellList:ensureChildVisible(k)
                break
            end
        end
    end

    local function isEnterKey(keyCode)
        return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13 or (KeyNumpadEnter and keyCode == KeyNumpadEnter) or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
    end

    if searchText then
        searchText.onTextChange = applyFilters
        searchText.onKeyPress = function(widget, keyCode, keyboardModifiers)
            if isEnterKey(keyCode) then
                if okFunc then
                    okFunc()
                end
                return true
            elseif keyCode == KeyEscape then
                closeAssignSpellWindow()
                return true
            end
            return false
        end
    end
    if paramText then
        paramText.onKeyPress = function(widget, keyCode, keyboardModifiers)
            if isEnterKey(keyCode) then
                if okFunc then
                    okFunc()
                end
                return true
            elseif keyCode == KeyEscape then
                closeAssignSpellWindow()
                return true
            end
            return false
        end
    end
    if clearButton and searchText then
        clearButton.onClick = function()
            searchText:clearText()
        end
    end
    if tickWidget then
        tickWidget.onCheckChange = applyFilters
    end
    if filterVocationWidget then
        filterVocationWidget.onCheckChange = applyFilters
    end
    if sortByLevelWidget then
        sortByLevelWidget.onCheckChange = applyFilters
    end

    okFunc = function()
        local selected = assignSpellRadio and assignSpellRadio:getSelectedWidget()
        if not selected then
            closeAssignSpellWindow()
            return
        end

        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        local param = selected.words or string.match(selected:getText(), "\n(.*)")
        local paramValue = paramText:getText()
        local check = param .. " " .. paramValue
        if check:find("utevo res ina") then
            param = "utevo res ina"
            paramValue = paramValue:gsub("ina ", "")
        end
        if paramValue:lower():find("up|down") then
            paramValue = ""
        end
        if not string_empty(paramValue) then
            param = param .. ' "' .. paramValue:gsub('"', '') .. '"'
        end
        if multiSlotIndex then
            if not button.cache.multiActions then
                button.cache.multiActions = {{}, {}, {}}
            end
            button.cache.multiActions[multiSlotIndex] = {chatText = param, sendAutomatically = true}
            ApiJson.createOrUpdateMultiText(tonumber(barID), tonumber(buttonID), multiSlotIndex, param, true)
            if updateMultiButtonState then
                updateMultiButtonState(button)
            end
            if assignMultiAction then
                assignMultiAction(button, true)
            end
        else
            ApiJson.createOrUpdateText(tonumber(barID), tonumber(buttonID), param, true)
            updateButton(button)
        end

        closeAssignSpellWindow()
    end

    buttonOk.onClick = okFunc
    buttonClose.onClick = closeAssignSpellWindow
    buttonShowAll.onClick = function()
        if filterVocationWidget then
            filterVocationWidget:setChecked(false)
        end
        if tickWidget then
            tickWidget:setChecked(false)
        end
        if searchText then
            searchText:clearText()
        end
        applyFilters()
    end
    window.onEnter = okFunc
    window.onEscape = closeAssignSpellWindow
end
-- /*=============================================
-- =            Assign Text                       =
-- =============================================*/
local assignTextWindow = nil

function closeAssignTextWindow()
    if assignTextWindow and not assignTextWindow:isDestroyed() then
        assignTextWindow:destroy()
    end
    assignTextWindow = nil
end

function assignText(button, multiSlotIndex)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end

    closeAllAssignWindows('text')

    local ok, window = pcall(function()
        return g_ui.loadUI('/modules/game_actionbar/text', g_ui.getRootWidget())
    end)
    if not ok or not window then
        perror('Failed to open Assign Text window: ' .. tostring(window))
        return
    end
    assignTextWindow = window

    local content = window:getChildById('contentPanel') or window.contentPanel
    if not content then
        perror('Assign Text contentPanel missing')
        closeAssignTextWindow()
        return
    end

    local textWidget = content:getChildById('text') or content.text
    local checkPanel = content:getChildById('checkPanel') or content.checkPanel
    local tickWidget = checkPanel and (checkPanel:getChildById('tick') or checkPanel.tick)
    local buttonOk = content:getChildById('buttonOk') or content.buttonOk
    local buttonClose = content:getChildById('buttonClose') or content.buttonClose
    if not textWidget or not tickWidget or not buttonOk or not buttonClose then
        perror('Assign Text widgets missing')
        closeAssignTextWindow()
        return
    end

    local titleSuffix = multiSlotIndex and (" (Slot " .. multiSlotIndex .. ")") or ""
    window:setText("Assign Text to Action Button " .. button:getId() .. titleSuffix)
    window:setId("assignTextWindow")
    window:show()
    window:raise()
    window:focus()

    local param = ''
    local sendAuto = false
    if multiSlotIndex and button.cache and button.cache.multiActions then
        local slot = button.cache.multiActions[multiSlotIndex]
        if slot and slot["chatText"] then
            param = slot["chatText"]
            sendAuto = slot["sendAutomatically"] or false
        end
    else
        param = button.cache.param or ''
        sendAuto = button.cache.sendAutomatic or false
    end

    textWidget:setText(param)
    textWidget:setCursorPos(#param)
    tickWidget:setChecked(#param > 0 and sendAuto or false)

    local function updateButtons()
        buttonOk:setEnabled(textWidget:getText():len() > 0)
    end
    textWidget.onTextChange = updateButtons
    updateButtons()
    textWidget:focus()

    local function saveText()
        local text = textWidget:getText()
        if text:len() == 0 then
            return
        end

        local autoSay = tickWidget:isChecked()
        local formattedText = Spells.getSpellFormatedName(text)
        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        if multiSlotIndex then
            if not button.cache.multiActions then
                button.cache.multiActions = {{}, {}, {}}
            end
            button.cache.multiActions[multiSlotIndex] = {
                chatText = formattedText,
                sendAutomatically = autoSay
            }
            ApiJson.createOrUpdateMultiText(tonumber(barID), tonumber(buttonID), multiSlotIndex, formattedText, autoSay)
            if updateMultiButtonState then
                updateMultiButtonState(button)
            end
            if assignMultiAction then
                assignMultiAction(button, true)
            end
        else
            ApiJson.createOrUpdateText(tonumber(barID), tonumber(buttonID), formattedText, autoSay)
            updateButton(button)
        end

        closeAssignTextWindow()
    end

    local function isEnterKey(keyCode)
        return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13 or (KeyNumpadEnter and keyCode == KeyNumpadEnter) or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
    end

    textWidget.onKeyPress = function(widget, keyCode, keyboardModifiers)
        if isEnterKey(keyCode) then
            saveText()
            return true
        elseif keyCode == KeyEscape then
            closeAssignTextWindow()
            return true
        end
        return false
    end

    buttonOk.onClick = saveText
    buttonClose.onClick = closeAssignTextWindow
    window.onEnter = saveText
    window.onEscape = closeAssignTextWindow
end
-- /*=============================================
-- =            Assign Object                      =
-- =============================================*/
local assignItemWindow = nil
local assignItemRadio = nil

local OBJECT_USE_TYPES = {
    "UseOnYourself",
    "UseOnTarget",
    "UseAtCursorPosition",
    "SelectUseTarget",
    "Equip",
    "Use"
}

local function canEquipItem(item)
    if not item or item:isContainer() then
        return false
    end
    if not g_game.getFeature(GameEnterGameShowAppearance) then
        return true
    end
    local clothSlot = item:getClothSlot()
    if clothSlot == 0 and (item:getClassification() > 0 or item:isAmmo()) then
        return true
    end
    return clothSlot > 0 or (clothSlot == 0 and item:hasWearout())
end

local function canUseActionbarItem(item)
    return item and ((item:isUsable() and not item:isMultiUse()) or item:isContainer())
end

local function isObjectUseTypeEnabled(item, useType)
    if useType == "Equip" then
        return canEquipItem(item)
    end
    if useType == "Use" then
        return canUseActionbarItem(item)
    end
    return item:isMultiUse()
end

local function canAutoSelectObjectUseType(item, useType)
    if useType == "Equip" then
        return true
    end
    local clothSlot = item:getClothSlot()
    return not (clothSlot > 0 or (clothSlot == 0 and item:getClassification() > 0))
end

local function getObjectSlotData(button, multiSlotIndex)
    if not multiSlotIndex or not button.cache or not button.cache.multiActions then
        return nil
    end
    return button.cache.multiActions[multiSlotIndex]
end

local function getObjectSmartMode(button, multiSlotIndex)
    local slot = getObjectSlotData(button, multiSlotIndex)
    if slot then
        return slot["useEquipSmartMode"] and true or false
    end
    return button.cache and button.cache.smartMode or false
end

local function clearCachedItemWidget(button)
    local cache = getButtonCache(button)
    local cachedItem = cachedItemWidget[cache.itemId]
    if not cachedItem then
        return
    end
    for index, widget in pairs(cachedItem) do
        if button == widget then
            table.remove(cachedItem, index)
            return
        end
    end
end

local function resolveButtonItem(button)
    if button.item then
        return button
    end
    local parent = button:getParent()
    local id = button:getId()
    updateButton(button)
    button = parent:getChildById(id)
    if button and button.item then
        return button
    end
    return nil
end

function closeAssignItemWindow()
    if assignItemRadio then
        assignItemRadio:destroy()
        assignItemRadio = nil
    end
    if assignItemWindow and not assignItemWindow:isDestroyed() then
        assignItemWindow:destroy()
    end
    assignItemWindow = nil
end

function closeAllAssignWindows(except)
    if except ~= 'spell' then
        closeAssignSpellWindow()
    end
    if except ~= 'text' then
        closeAssignTextWindow()
    end
    if except ~= 'item' then
        closeAssignItemWindow()
    end
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end
end

function assignItem(button, itemId, itemTier, dragEvent, multiSlotIndex)
    if not isLoaded then
        return true
    end

    button = resolveButtonItem(button)
    if not button then
        return
    end

    local actionbar = button:getParent():getParent()
    if actionbar.locked or (dragEvent and not multiSlotIndex) then
        updateButton(button)
        return
    end

    closeAllAssignWindows('item')

    local ok, window = pcall(function()
        return g_ui.loadUI('/modules/game_actionbar/object', g_ui.getRootWidget())
    end)
    if not ok or not window then
        perror('Failed to open Assign Object window: ' .. tostring(window))
        return
    end
    assignItemWindow = window
    local currentItemWindow = window
    window.onDestroy = function()
        if assignItemWindow ~= currentItemWindow then
            return
        end
        if assignItemRadio then
            assignItemRadio:destroy()
            assignItemRadio = nil
        end
        assignItemWindow = nil
    end

    local content = window:getChildById('contentPanel') or window.contentPanel
    if not content or not content.select or not content.item or not content.checks
        or not content.buttonOk or not content.buttonClose then
        perror('Assign Object widgets missing')
        closeAssignItemWindow()
        return
    end
    assignItemRadio = UIRadioGroup.create()
    local slotData = getObjectSlotData(button, multiSlotIndex)
    local fromSelect = slotData and slotData["useObject"]
        and slotData["useObject"] ~= itemId
        or (not multiSlotIndex and button.item:getItemId() > 0 and button.item:getItemId() ~= itemId)
    local activeActionType = (slotData and slotData["useType"])
        or (button.cache and button.cache.actionType)
        or 0

    local titleSuffix = multiSlotIndex and (" (Slot " .. multiSlotIndex .. ")") or ""
    window:setText("Assign Object to Action Button " .. button:getId() .. titleSuffix)
    window:setId("assignItemWindow")
    window:show()
    window:raise()
    window:focus()

    content.select.onClick = function()
        closeAssignItemWindow()
        assignItemEvent(button, multiSlotIndex)
    end

    local saveSelection = nil
    local function isEnterKey(keyCode)
        return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13 or (KeyNumpadEnter and keyCode == KeyNumpadEnter) or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
    end

    content.item:setItemId(itemId)
    local item = content.item:getItem()
    if not item then
        closeAssignItemWindow()
        return
    end

    content.item.onDoubleClick = function()
        if saveSelection then
            saveSelection()
        end
        return true
    end

    if item:getClassification() == 0 then
        itemTier = 0
    else
        itemTier = itemTier or (button.cache and button.cache.upgradeTier) or 0
    end
    ItemsDatabase.setTier(content.item, itemTier, false)

    local smartWidget = content.checks.smart
    if smartWidget then
        local showSmart = item:getClothSlot() > 0 and item:hasWearout()
        smartWidget:setVisible(showSmart)
        if showSmart then
            smartWidget:setChecked(getObjectSmartMode(button, multiSlotIndex))
        end
        smartWidget.onKeyPress = function(widget, keyCode, keyboardModifiers)
            if isEnterKey(keyCode) then
                if saveSelection then saveSelection() end
                return true
            elseif keyCode == KeyEscape then
                content.buttonClose.onClick()
                return true
            end
            return false
        end
    end

    local function onUseTypeCheckChange(widget)
        if not smartWidget then
            return
        end
        if widget:getId() == "Equip" and not smartWidget:isEnabled() then
            smartWidget:setEnabled(true)
        elseif widget:getId() ~= "Equip" and smartWidget:isEnabled() then
            smartWidget:setChecked(false)
            smartWidget:setEnabled(false)
        end
    end

    for _, useType in ipairs(OBJECT_USE_TYPES) do
        local child = content.checks:getChildById(useType)
        if child then
            assignItemRadio:addWidget(child)
            child:setChecked(false)

            local enabled = isObjectUseTypeEnabled(item, useType)
            child:setEnabled(enabled)
            child.onCheckChange = onUseTypeCheckChange
            child.onDoubleClick = function(self)
                if self:isEnabled() then
                    assignItemRadio:selectWidget(self)
                    if saveSelection then
                        saveSelection()
                    end
                    return true
                end
            end
            child.onKeyPress = function(widget, keyCode, keyboardModifiers)
                if isEnterKey(keyCode) then
                    if saveSelection then
                        saveSelection()
                    end
                    return true
                elseif keyCode == KeyEscape then
                    content.buttonClose.onClick()
                    return true
                end
                return false
            end

            if enabled and not assignItemRadio:getSelectedWidget()
                and canAutoSelectObjectUseType(item, useType)
                and (fromSelect or activeActionType == 0 or activeActionType == useType
                    or activeActionType == UseTypes[useType]) then
                assignItemRadio:selectWidget(child)
            end
        end
    end

    if content.tier then
        local showTier = itemTier and itemTier > 0
        content.tier:setVisible(showTier)
        if showTier and itemTier > 1 then
            content.tier:setImageClip(torect((18 * (itemTier - 1)) .. " 0 18 16"))
        end
    end

    if not assignItemRadio:getSelectedWidget() then
        for _, child in ipairs(content.checks:getChildren()) do
            if child:getId() ~= "smart" and child:isEnabled() then
                assignItemRadio:selectWidget(child)
                break
            end
        end
    end

    content.buttonOk:setEnabled(item:getId() > 100 and assignItemRadio:getSelectedWidget() ~= nil)

    local function closeWindow()
        closeAssignItemWindow()
    end

    saveSelection = function()
        local selectedWidget = assignItemRadio and assignItemRadio:getSelectedWidget()
        if not selectedWidget then
            return
        end

        local selected = selectedWidget:getId()
        local barID, buttonID = string.match(button:getId(), "^(%d+)%.(%d+)$")
        if not barID or not buttonID then
            return
        end

        clearCachedItemWidget(button)

        local smartMode = smartWidget and smartWidget:isVisible() and smartWidget:isChecked() or false
        if multiSlotIndex then
            if not button.cache.multiActions then
                button.cache.multiActions = {{}, {}, {}}
            end
            button.cache.multiActions[multiSlotIndex] = {
                useObject = itemId,
                useType = selected,
                upgradeTier = itemTier,
                useEquipSmartMode = smartMode
            }
            ApiJson.createOrUpdateMultiAction(tonumber(barID), tonumber(buttonID), multiSlotIndex, selected, itemId,
                itemTier, smartMode)
            if updateMultiButtonState then
                updateMultiButtonState(button)
            end
            if assignMultiAction then
                assignMultiAction(button, true)
            end
        else
            button.cache.smartMode = smartMode
            ApiJson.createOrUpdateAction(tonumber(barID), tonumber(buttonID), selected, itemId, itemTier, smartMode)
            updateButton(button)
        end

        closeWindow()
    end

    content.buttonOk.onClick = saveSelection
    content.buttonClose.onClick = function()
        updateButton(button)
        closeWindow()
    end
    window.onEnter = saveSelection
    window.onEscape = content.buttonClose.onClick
    window.onKeyPress = function(widget, keyCode, keyboardModifiers)
        if isEnterKey(keyCode) then
            saveSelection()
            return true
        elseif keyCode == KeyEscape then
            content.buttonClose.onClick()
            return true
        end
        return false
    end

    if actionbar.locked then
        content.buttonClose.onClick()
    end
end
-- /*=============================================
-- =            Passive html Windows          =
-- =============================================*/

function assignPassive(button)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end
    local radio = UIRadioGroup.create()
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end
    ActionBarController:loadHtml('html/passive.html')
    local ui = ActionBarController.ui
    ui:show()
    ui:raise()
    ui:setTitle("Assign Passive to Action Button " .. button:getId())
    local passiveList = ActionBarController:findWidget("#passiveList")
    local previewWidget = ActionBarController:findWidget("#preview")
    local image = ActionBarController:findWidget("#image")
    for id, passiveData in pairs(PassiveAbilities) do
        local widget = g_ui.createWidget('PassivePreview', passiveList)
        radio:addWidget(widget)
        widget:setId(id)
        widget:setText(passiveData.name)
        widget.image:setImageSource(passiveData.icon)
        widget.source = passiveData.icon
    end
    radio.onSelectionChange = function(_, selected)
        if selected then
            previewWidget:setText(selected:getText())
            image:setImageSource(selected.source)
        end
    end
    local passiveChildren = passiveList:getChildren()
    if #passiveChildren > 0 then
        radio:selectWidget(passiveChildren[1])
    end
    local function okFunc(destroy)
        local selected = radio:getSelectedWidget()
        if not selected then
            return
        end
        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        ApiJson.createOrUpdatePassive(tonumber(barID), tonumber(buttonID), tonumber(selected:getId()))
        updateButton(button)
        if destroy then
            ActionBarController:unloadHtml()
        end
    end
    local function cancelFunc()
        ActionBarController:unloadHtml()
    end
    ActionBarController:findWidget("#buttonOk").onClick = function()
        okFunc(true)
    end
    ActionBarController:findWidget("#buttonClose").onClick = cancelFunc
    ui.onEnter = function()
        okFunc(true)
    end
end

function assignSpecialAction(button, mousePos)
    local actionbar = button:getParent():getParent()
    if actionbar.locked then
        alert('Action bar is locked')
        return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    for _, specialAction in ipairs(ActionBarSpecialActions) do
        menu:addOption(specialAction.text, function()
            local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
            ApiJson.createOrUpdateSpecialAction(tonumber(barID), tonumber(buttonID), specialAction.id)
            updateButton(button)
        end)
    end

    if button.cache and button.cache.specialAction then
        menu:addSeparator()
        menu:addOption(tr("Clear Assigned Action"), function()
            clearButton(button, true)
        end)
    end

    menu:display(mousePos)
end

-- /*=============================================
-- =            item Event external          =
-- =============================================*/
function onDropActionButton(self, mousePosition, mouseButton)
    if not g_ui.isMouseGrabbed() then
        return
    end
    -- Restore cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    self:ungrabMouse()
end

function assignItemEvent(button, multiSlotIndex)
    mouseGrabberWidget:grabMouse()
    -- Use native cursor when enabled, otherwise use custom cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
        onAssignItem(self, mousePosition, mouseButton, button, multiSlotIndex)
    end
end

function onAssignItem(self, mousePosition, mouseButton, button, multiSlotIndex)
    mouseGrabberWidget:ungrabMouse()
    -- Restore cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    mouseGrabberWidget.onMouseRelease = onDropActionButton

    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
        return true
    end

    local itemId = 0
    local itemTier = 0
    if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
        itemId = clickedWidget:getItem():getId()
        itemTier = clickedWidget:getItem():getTier()
    elseif clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            itemId = tile:getTopUseThing():getId()
        end
    end

    local itemType = g_things.getThingType(itemId, ThingCategoryItem)
    if not itemType or not itemType:isPickupable() then
        modules.game_textmessage.displayFailureMessage(tr('Invalid object'))
        return true
    end
    assignItem(button, itemId, itemTier, false, multiSlotIndex)
end

-- /*=============================================
-- =            Windows hotkeys html             =
-- =============================================*/
-- in modules\game_actionbar\html\hotkeys.html
