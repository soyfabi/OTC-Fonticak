-- /*=============================================
-- =            util             =
-- =============================================*/
local SLOT_IMG_FILLED = '/images/game/actionbar/slot-actionbar-filled'
local SLOT_CLIP_FILLED_NORMAL = '0 0 34 34'
local SLOT_CLIP_FILLED_PRESSED = '0 34 34 34'
local SLOT_COLOR_FILLED_NORMAL = '#ffffff'
local SLOT_COLOR_FILLED_EQUIPPED = '#d8d8d8'
local EQUIP_VISUAL_PENDING_MS = 800
local freeActionButtonCopies = {}
local freeActionButtonLocks = {}
local selectedFreeActionButtonCopies = {}
local freeActionSelectionClickAwayHandler = nil
local previousFreeActionSelectionMouseReleaseHandler = nil

local function clearPendingEquipVisual(cache)
    if not cache then
        return
    end
    cache.pendingEquipVisual = nil
    cache.pendingEquipVisualUntil = nil
end

local function resolveEquipButtonVisual(button, isItemEquipped)
    local cache = button and button.cache
    if not cache or cache.pendingEquipVisual == nil then
        return isItemEquipped
    end

    if isItemEquipped == cache.pendingEquipVisual then
        clearPendingEquipVisual(cache)
        return isItemEquipped
    end

    if cache.pendingEquipVisualUntil and g_clock.millis() < cache.pendingEquipVisualUntil then
        return cache.pendingEquipVisual
    end

    clearPendingEquipVisual(cache)
    return isItemEquipped
end

--- Applies the filled action slot frame clip (normal or pressed/equipped).
function applyActionButtonSlotClip(button, pressed)
    if not button or button:isDestroyed() or not button.item or button.item:isDestroyed() then
        return
    end

    if not button.item:isOn() then
        return
    end

    if button.cache and button.cache.equippedVisual == pressed then
        return
    end

    button.item:setImageSource(SLOT_IMG_FILLED)
    button.item:setImageClip(pressed and SLOT_CLIP_FILLED_PRESSED or SLOT_CLIP_FILLED_NORMAL)
    button.item:setImageColor(pressed and SLOT_COLOR_FILLED_EQUIPPED or SLOT_COLOR_FILLED_NORMAL)
    button.item:setChecked(pressed)

    if button.cache then
        button.cache.equippedVisual = pressed
    end
end

local function setPendingEquipVisual(button, equipped)
    if not button or not button.cache then
        return
    end
    button.cache.pendingEquipVisual = equipped
    button.cache.pendingEquipVisualUntil = g_clock.millis() + EQUIP_VISUAL_PENDING_MS
    applyActionButtonSlotClip(button, equipped)
end

--- checks if string is empty
local function string_empty(str)
    return #str == 0
end

local function lineBreaks(input, lineLength, spaceCount)
    spaceCount = spaceCount or 0
    local result = {}
    local space = string.rep(" ", spaceCount)
    local inputLen = #input
    for pos = 1, inputLen, lineLength do
        local endPos = math.min(pos + lineLength - 1, inputLen)
        result[#result + 1] = input:sub(pos, endPos)
        if endPos < inputLen then
            result[#result + 1] = "\n" .. space
        end
    end
    return table.concat(result)
end

--- Gets a button widget by ID
local function getButtonById(id)
    if not id then
        return nil
    end
    for _, actionbar in pairs(actionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            if button:getId() == id then
                return button
            end
        end
    end
    return nil
end

--- Checks if a button is empty
local function buttonIsEmpty(button)
    return button.item:getItemId() == 0 and string_empty(button.item.text:getText()) and
               string_empty(button.item.text:getImageSource())
end
--- Gets the name of an action type
function getActionName(actionType)
    for k, v in pairs(UseTypes) do
        if v == actionType then
            return k
        end
    end
end

local function resolveMultiUseType(useType)
    if type(useType) == "string" and tonumber(useType) == nil then
        return useType
    end
    return getActionName(tonumber(useType) or useType) or "Use"
end

function hasMultiActions(multiActions)
    if type(multiActions) ~= "table" then
        return false
    end
    for i = 1, 3 do
        if type(multiActions[i]) == "table" and not table.empty(multiActions[i]) then
            return true
        end
    end
    return false
end

--- Persists a single multi-action slot to ApiJson
function persistMultiSlot(barId, buttonId, slotIndex, slotData)
    if not slotData or table.empty(slotData) then
        ApiJson.removeMultiAction(barId, buttonId, slotIndex)
        return
    end
    if slotData["chatText"] then
        ApiJson.createOrUpdateMultiText(barId, buttonId, slotIndex,
            slotData["chatText"], slotData["sendAutomatically"])
    elseif slotData["useObject"] then
        local useTypeName = resolveMultiUseType(slotData["useType"])
        ApiJson.createOrUpdateMultiAction(barId, buttonId, slotIndex,
            useTypeName, slotData["useObject"],
            slotData["upgradeTier"] or 0, slotData["useEquipSmartMode"] or false)
    end
end

--- Gets item name by ID
local function getItemNameById(itemId)
    for _, k in pairs(hotkeyItemList) do
        local item = k[1]
        if item:getId() == itemId then
            return k[2]
        end
    end
    return "this object"
end

--- Checks if player can use a spell
local function playerCanUseSpell(spellData)
    if not g_game.isOnline() then
        return
    end

    if not spellData then
        return false
    end

    if spellData.needLearn and not spellListData[tostring(spellData.id)] then
        return false
    end

    if spellData.mana and (player:getMana() < spellData.mana) then
        return false
    end

    if spellData.level and (player:getLevel() < spellData.level) then
        return false
    end

    if spellData.soul and (player:getSoul() < spellData.soul) then
        return false
    end

    if spellData.vocations and (not table.contains(spellData.vocations, translateVocation(player:getVocation()))) then
        return false
    end

    return true
end
-- /*=============================================
-- =            Hotkeys             =
-- =============================================*/
local function onCheckKeyUp(button)
    local cache = getButtonCache(button)
    if cache.isSpell then
        spellGroupPressed[tostring(button.cache.primaryGroup)] = nil
    end
end
local function bindHotkey(button, hotkey)
    if not gameRootPanel or not button or not hotkey or string_empty(hotkey) then
        return
    end

    local combo = hotkey

    if Keybind and Keybind.isMouseKey and Keybind.isMouseKey(combo) then
        Keybind.bindMouseButtonKey(combo, function()
            onExecuteAction(button, false)
        end, gameRootPanel)
        return
    end

    g_keyboard.bindKeyPress(combo, function()
        if not modules.game_hotkeys.canPerformKeyCombo(combo) then
            return
        end
        onExecuteAction(button, true)
    end, gameRootPanel)

    g_keyboard.bindKeyDown(combo, function()
        if not modules.game_hotkeys.canPerformKeyCombo(combo) then
            return
        end
        onExecuteAction(button, false)
    end, gameRootPanel)

    g_keyboard.bindKeyUp(combo, function()
        if not modules.game_hotkeys.canPerformKeyCombo(combo) then
            return
        end
        onCheckKeyUp(button)
    end, gameRootPanel)
end

local hotkeyCache = {}
local hotkeyCacheValid = false
local cachedChatMode = nil

--- Updates the hotkey cache
local function updateHotkeyCache()
    hotkeyCache = {}
    local currentChatMode = modules.game_console.isChatEnabled() and 'chatOn' or 'chatOff'
    cachedChatMode = currentChatMode
    hotkeyCacheValid = true
    
    if not ApiJson.hasCurrentHotkeySet() then return end
    
    local entries = ApiJson.getHotkeyEntries(currentChatMode)
    if not entries then return end

    for _, data in pairs(entries) do
        if data["actionsetting"] and data["actionsetting"]["action"] then
            local action = data["actionsetting"]["action"]
            local keySequence = data["keysequence"]
            if keySequence and not string_empty(keySequence) then
                hotkeyCache[action] = keySequence
            end
        end
    end
end

--- Clears the hotkey cache
function clearHotkeyCache()
    hotkeyCache = {}
    hotkeyCacheValid = false
    cachedChatMode = nil
end

--- Sets up hotkey for a button
local function setupHotkeyButton(button)
    if not ApiJson.hasCurrentHotkeySet() then
        if button.cache and button.cache.hotkey then
            unbindHotkey(button.cache.hotkey)
            button.cache.hotkey = nil
            if button.hotkeyLabel then
                button.hotkeyLabel:setText('')
            end
        end
        return
    end

    local currentChatMode = modules.game_console.isChatEnabled() and 'chatOn' or 'chatOff'

    -- Invalidate/rebuild cache if needed (you might want a better invalidation strategy later)
    -- For now, we rebuild if it's empty, or we could expose a function to clear it
    if not hotkeyCacheValid or cachedChatMode ~= currentChatMode then 
        updateHotkeyCache()
    end
    
    local actionKey = "TriggerActionButton_" .. button:getId()
    local keySequence = hotkeyCache[actionKey]
    
    if keySequence then
        button.cache.hotkey = keySequence
        unbindHotkey(keySequence)
        bindHotkey(button, keySequence)
    elseif button.cache and button.cache.hotkey then
        -- No hotkey is configured for this button anymore: drop the stale
        -- binding/cache so the button label really clears (e.g. Clear in the
        -- Edit Hotkey dialog on a button without an action).
        unbindHotkey(button.cache.hotkey)
        button.cache.hotkey = nil
    end
end

local function executeSpecialAction(specialActionId)
    if not specialActionId then
        return
    end

    if specialActionId == "toggleWasdChatMode" then
        modules.game_console.toggleChat()
    elseif specialActionId == "attackNext" then
        modules.game_battle.attackNext()
    elseif specialActionId == "attackPrevious" then
        modules.game_battle.attackNext(true)
    elseif specialActionId == "toggleChase" then
        modules.game_hotkeys.toggleChaseMode()
    end
end

local function use_item_at_cursor_position(button)
    if not button or not button.item then
        return false
    end

    local item = button.item:getItem()
    if not item then
        return false
    end

    local subType = button.item:getItemSubType() or -1
    local function safeStartUseWith()
        modules.game_interface.startUseWith(item, subType)
        return false
    end

    local mapPanel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
    if not mapPanel then
        return safeStartUseWith()
    end

    local mousePosition = g_window.getMousePosition()
    if not mapPanel:containsPoint(mousePosition) then
        return safeStartUseWith()
    end

    local mapPosition = mapPanel:getPosition(mousePosition)
    if not mapPosition then
        return safeStartUseWith()
    end

    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and mapPosition.z ~= localPlayer:getPosition().z then
        local dz = mapPosition.z - localPlayer:getPosition().z
        mapPosition.x = mapPosition.x + dz
        mapPosition.y = mapPosition.y + dz
        mapPosition.z = localPlayer:getPosition().z
    end

    local tile = g_map.getTile(mapPosition)
    if not tile then
        return safeStartUseWith()
    end

    local useThing = nil
    if item:isFluidContainer() or item:isMultiUse() then
        useThing = tile:getTopMultiUseThing()
    else
        useThing = tile:getTopUseThing()
    end

    if not useThing then
        return safeStartUseWith()
    end

    g_game.useWith(item, useThing, subType)
    return true
end
-- /*=============================================
-- =            button behavior             =
-- =============================================*/
local function isItemVisibleInOpenContainers(itemId, tier)
    if not itemId or itemId == 0 then
        return false
    end

    for _, container in pairs(g_game.getContainers()) do
        if container then
            for _, item in ipairs(container:getItems()) do
                if item and item:getId() == itemId and item:getTier() == tier then
                    return true
                end
            end
        end
    end

    return false
end

-- Keep Action Bar counts correct with backpack closed: the server snapshot is
-- adjusted here when no open container will report the stack change.
local function consumeHotkeyInventoryCount(button)
    if not player or not button or not button.cache or button.cache.itemId == 0 then
        return
    end
    if not player.adjustInventoryCountCache then
        return
    end

    local tier = 0
    if g_game.getFeature(GameThingUpgradeClassification) then
        tier = button.cache.upgradeTier or 0
    end

    if isItemVisibleInOpenContainers(button.cache.itemId, tier) then
        return
    end

    player:adjustInventoryCountCache(button.cache.itemId, tier, -1)
    updateInventoryItems()
end

--- Executes the action assigned to a button
function onExecuteAction(button, isPress)
    local cache = getButtonCache(button)
    if cache.lastClick > g_clock.millis() then
        return true
    end

    if modules.game_interface.getMainRightPanel():isFocusable() or modules.game_interface.getLeftPanel():isFocusable() then
        return true
    end

    if not isPress then
        button.cache.nextDownKey = g_clock.millis() + 500
    end

    if isPress and button.cache.nextDownKey > g_clock.millis() then
        return true
    end

    local cooldown = isPress and 600 or 150
    button.cache.lastClick = g_clock.millis() + cooldown
    local action = button.cache.actionType
    if action == 0 then
        return true
    end

    if button.cache and button.cache.activeMultiIndex then
        button.cache.lastMultiIndex = button.cache.activeMultiIndex
    end

    if action == UseTypes["Equip"] and button.item then
        if isEquipmentPresetCache and isEquipmentPresetCache(button.cache) then
            if isEquipmentSetOnCooldown and isEquipmentSetOnCooldown() then
                return
            end
            if executeEquipmentPreset then
                executeEquipmentPreset(button)
            end
            return
        end
        local tier = 0
        if g_game.getFeature(GameThingUpgradeClassification) then
            tier = button.cache.upgradeTier
        end
        if player:getInventoryCount(button.cache.itemId, tier) == 0
            and not player:hasEquippedItemId(button.cache.itemId, tier) then
            return
        end
        local isEquipped = player:hasEquippedItemId(button.cache.itemId, tier)
        g_game.equipItemId(button.cache.itemId, tier)
        setPendingEquipVisual(button, not isEquipped)
    end

    if action == UseTypes["Use"] and button.item then
        if (button.item:getItem():isContainer()) then
            g_game.closeContainerByItemId(button.item:getItemId())
        else
            g_game.useInventoryItem(button.item:getItemId())
            consumeHotkeyInventoryCount(button)
        end
    end

    if action == UseTypes["UseOnYourself"] and button.item then
        g_game.useInventoryItemWith(button.item:getItemId(), player, button.item:getItemSubType() or -1)
        consumeHotkeyInventoryCount(button)
    end

    if button.item then
        if action == UseTypes["SelectUseTarget"] then
            modules.game_interface.startUseWith(button.item:getItem(), button.item:getItemSubType() or -1)
        end

        if action == UseTypes["UseAtCursorPosition"] then
            use_item_at_cursor_position(button)
            consumeHotkeyInventoryCount(button)
        end

        if action == UseTypes["UseOnTarget"] then
            local attackingCreature = g_game.getAttackingCreature()
            if not attackingCreature then
                modules.game_interface.startUseWith(button.item:getItem(), button.item:getItemSubType() or -1)
            else
                g_game.useWith(button.item:getItem(), attackingCreature, button.item:getItemSubType() or -1)
                consumeHotkeyInventoryCount(button)
            end
        end
    end

    if action == UseTypes["chatText"] and button.cache.sendAutomatic then
        if button.cache.isSpell then
            spellGroupPressed[tostring(button.cache.primaryGroup)] = true
            g_game.talk(button.cache.param)
        else
            modules.game_console.sendMessage(button.cache.param)
        end

        modules.game_console.getConsole():setText('')
    elseif action == UseTypes["specialAction"] then
        executeSpecialAction(button.cache.specialAction)
    elseif action == UseTypes["chatText"] then
        modules.game_console.getConsole():setText(button.cache.param)
        modules.game_console.getConsole():setCursorPos(#button.cache.param)
    end

    local multiParent = button.parentButton
    if not multiParent and button.cache and hasMultiActions and hasMultiActions(button.cache.multiActions) then
        multiParent = button
    end
    if multiParent and updateMultiButtonState and action ~= 0 then
        updateMultiButtonState(multiParent)
        if refreshOpenMultiActionPanel then
            refreshOpenMultiActionPanel(multiParent)
        end
    end
end

--- Translates hotkey text for display
local function translateDisplayHotkey(text)
    if HotkeyShortcuts[text] then
        text = HotkeyShortcuts[text]
    elseif string.len(text) > 5 then
        text = "..." .. string.sub(text, string.len(text) - 2, string.len(text))
    end
    return text
end

function clearButton(button, removeAction)
    local hotkey = button.cache.hotkey

    if button.cache.cooldownEvent then
        removeEvent(button.cache.cooldownEvent)
    end

    if cacheMultiActionButtons then
        cacheMultiActionButtons[button] = nil
    end
    if clearMultiActionCooldownEvents then
        clearMultiActionCooldownEvents(button:getId())
    end

    removeCooldown(button)
    resetButtonCache(button)

    if hotkey then
        button.cache.hotkey = hotkey
        button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
    end

    setupButtonTooltip(button, true)
    if removeAction then
        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        ApiJson.removeAction(tonumber(barID), tonumber(buttonID))
    end
end

--- Updates the state of a button
function updateButtonState(button)
    if not button then
        return
    end

    if not player then
        player = g_game.getLocalPlayer()
    end

    if not player then
        return
    end
    if not button.item then
        return
    end

    button:recursiveGetChildById('activeSpell'):setVisible(false)
    if button.cache.isSpell then
        setupButtonTooltip(button, false)
        button.item.text.gray:setVisible(not playerCanUseSpell(button.cache.spellData))
        local spellId = 0
        button:recursiveGetChildById('activeSpell'):setVisible(button.cache.spellData.id == spellId)
    elseif isEquipmentPresetCache and isEquipmentPresetCache(button.cache) then
        if button.item.gray then button.item.gray:setVisible(false) end
        setupButtonTooltip(button, false)
        applyActionButtonSlotClip(button, isEquipmentSetFullyActive(button.cache))
    elseif button.cache.itemId ~= 0 then
        local tier = 0
        if g_game.getFeature(GameThingUpgradeClassification) then
            tier = button.cache.upgradeTier
        end
        local isItemEquipped = player:hasEquippedItemId(button.cache.itemId, tier)
        local itemCount = player:getInventoryCount(button.cache.itemId, tier)

        -- Dim missing items on all protocols (GameEnterGameShowAppearance is only
        -- enabled from 12.00+, so Fonticak 8.60 never reached the gray overlay).
        if button.item.gray then
            button.item.gray:setVisible(itemCount == 0)
        end

        if button.cache.actionType == UseTypes["Equip"] then
            applyActionButtonSlotClip(button, resolveEquipButtonVisual(button, isItemEquipped))
        elseif button.cache.equippedVisual then
            clearPendingEquipVisual(button.cache)
            applyActionButtonSlotClip(button, false)
        end
        if button.item.setDisplayCount then
            if modules.client_options.getOption('showHKObjectsBars') then
                -- 0 is a valid display value (missing stack); -1 clears the override
                button.item:setDisplayCount(itemCount)
            elseif button.item.clearDisplayCount then
                button.item:clearDisplayCount()
            else
                button.item:setDisplayCount(-1)
            end
        else
            if modules.client_options.getOption('showHKObjectsBars') then
                button.item:setItemCount(math.max(itemCount, 0))
            else
                button.item:setItemCount(1)
            end
        end
        setupButtonTooltip(button, false)
    end
end

--- Gets or creates the cache for a button
function getButtonCache(button)
    if not button then
        return {
            cooldownEvent = nil,
            cooldownTime = 0,
            isSpell = false,
            isRuneSpell = false,
            isPassive = false,
            spellID = 0,
            spellData = nil,
            specialAction = nil,
            param = "",
            sendAutomatic = false,
            actionType = 0,
            upgradeTier = 0,
            hotkey = nil,
            lastClick = 0,
            nextDownKey = 0,
            isDragging = false,
            buttonIndex = 0,
            buttonParent = nil,
            itemId = 0,
            multiActions = {{}, {}, {}},
            smartMode = false
        }
    end

    if not button.cache or table.empty(button.cache) then
        button.cache = {
            cooldownEvent = nil,
            cooldownTime = 0,
            isSpell = false,
            isRuneSpell = false,
            isPassive = false,
            spellID = 0,
            spellData = nil,
            specialAction = nil,
            param = "",
            sendAutomatic = false,
            actionType = 0,
            upgradeTier = 0,
            hotkey = nil,
            lastClick = 0,
            nextDownKey = 0,
            isDragging = false,
            buttonIndex = 0,
            buttonParent = nil,
            itemId = 0,
            multiActions = {{}, {}, {}},
            smartMode = false
        }
    end

    return button.cache
end

--- Resets the cache of a button
function resetButtonCache(button)
    -- Optimize: Check if we really need to clear the item widget cache
    if button.cache and button.cache.itemId > 0 then
        local cachedItem = cachedItemWidget[button.cache.itemId]
        if cachedItem then
            for index, widget in pairs(cachedItem) do
                if button == widget then
                    table.remove(cachedItem, index)
                    break
                end
            end
        end
    end

    if button.item then
        if button.item:getItemId() ~= 0 then button.item:setItemId(0) end
        if button.item:isOn() then button.item:setOn(false) end
        if button.item:isChecked() then button.item:setChecked(false) end
        if button.item:isDraggable() then button.item:setDraggable(false) end
        
        if button.item.gray and button.item.gray:isVisible() then
            button.item.gray:setVisible(false)
        end
        if button.item.text then
            if button.item.text.gray and button.item.text.gray:isVisible() then
                button.item.text.gray:setVisible(false)
            end
            button.item.text:setImageSource('')
            button.item.text:setText('')
        end
    end

    -- Text updates
    if button.hotkeyLabel then 
    button.hotkeyLabel:setText('')
    end
    if button.parameterText then 
    button.parameterText:setText('')
    end
    if button.cooldown then
        button.cooldown:setPercent(100)
        button.cooldown:setText("")
    end

    -- Event cleanup
    if button.cache and button.cache.removeCooldownEvent then
        removeEvent(button.cache.removeCooldownEvent)
        button.cache.removeCooldownEvent = nil
    end
    
    if not button.cache then
        button.cache = {}
    end
    
    -- Reset fields
    local c = button.cache
    c.cooldownEvent = nil
    c.cooldownTime = 0
    c.isSpell = false
    c.isRuneSpell = false
    c.isPassive = false
    c.spellID = 0
    c.spellData = nil
    c.primaryGroup = nil
    c.specialAction = nil
    c.param = ""
    c.sendAutomatic = false
    c.actionType = 0
    c.upgradeTier = 0
    c.hotkey = nil
    c.lastClick = 0
    c.nextDownKey = 0
    c.isDragging = false
    c.buttonIndex = 0
    c.buttonParent = nil
    c.itemId = 0
    c.multiActions = {{}, {}, {}}
    c.smartMode = false
    c.equipments = nil
    c.equipmentIconIndex = nil
    c.equipmentDescription = nil
    c.equipmentTypeIndex = nil
    c.isEquipmentPreset = false
    c.equippedVisual = nil
    clearPendingEquipVisual(c)
    if button.equipmentTypeIcon then
        button.equipmentTypeIcon:setVisible(false)
    end
    if button.multiIcon then
        button.multiIcon:setVisible(false)
    end
end

-- /*=============================================
-- =       Tooltip    =
-- =============================================*/
--- Sets up the tooltip for a button
function setupButtonTooltip(button, isEmpty)
    if not g_game.isOnline() then
        return true
    end

    if not button or not button.item then
        return true
    end

    -- Honour Action Bars → Show Action Button Tooltip.
    if not modules.client_options.getOption('actionTooltip') then
        if button.item.removeTooltip then
            button.item:removeTooltip()
        else
            button.item:setTooltip('')
        end
        return true
    end

    local cache = getButtonCache(button)
    if isEmpty then
        local tooltip = "Action Button " .. button:getId()
        local hotkeyDesc = cache.hotkey ~= nil and cache.hotkey or "None"
        tooltip = tooltip .. "\n\nAction:  " .. "None"
        tooltip = tooltip .. "\nHotkeys:  " .. hotkeyDesc
        button.item:setTooltip(tooltip)
        return true
    end

    local actionDesc = ""
    local spellData = cache.spellData
    local function spellStatsTooltip(data)
        if not data then
            return ""
        end
        local cooldown = ((data.exhaustion or 0) / 1000)
        local mana = data.mana or 0
        return " Cooldown:  " .. cooldown .. "s\n" .. "         Mana:  " .. mana
    end

    if cache.actionType == UseTypes["chatText"] then
        if not cache.isSpell then
            actionDesc = 'Say: "' .. lineBreaks(cache.param, 44, 36) .. '"\n'
            actionDesc = actionDesc .. "Auto sent:  " .. (cache.sendAutomatic and "Yes" or "No")
        else
            actionDesc = "Cast " .. Spells.getSpellNameByWords(spellData.words) .. "\n"
            actionDesc = actionDesc .. "   Formula:  " .. cache.param .. "\n"
            actionDesc = actionDesc .. spellStatsTooltip(spellData)
        end
    elseif cache.actionType == UseTypes["specialAction"] then
        local specialAction = getActionBarSpecialAction(cache.specialAction)
        actionDesc = specialAction and specialAction.text or "Unknown action"
    elseif cache.actionType == UseTypes["passiveAbility"] then
        actionDesc = "Gift of Life"
    else
        actionDesc = UseTypesTip[cache.actionType]
        if actionDesc == nil then
            actionDesc = "Use %s"
        end

        if cache.actionType == UseTypes["Equip"] and isEquipmentPresetCache and isEquipmentPresetCache(cache) then
            actionDesc = equipmentPresetTooltip and equipmentPresetTooltip(cache) or tr("Equipment set")
        elseif cache.actionType == UseTypes["Equip"] and button.item then
            local item = button.item:getItem()
            local itemId = (item and item:getId()) or button.cache.itemId or button.item:getItemId() or 0
            local itemName = getItemNameById(itemId) ..
                                 ((cache.upgradeTier and cache.upgradeTier > 0) and " (Tier " .. cache.upgradeTier ..
                                     ")" or "")
            actionDesc = tr(actionDesc, (button.item:isChecked() and "Unequip" or "Equip"), itemName)
        elseif button.item and button.item:getItem() then
            actionDesc = tr(actionDesc, getItemNameById(button.item:getItem():getId()))
        end

        if not (isEquipmentPresetCache and isEquipmentPresetCache(cache)) then
            local itemCount = player:getInventoryCount(button.cache.itemId or 0, button.cache.upgradeTier or 0)
            actionDesc = actionDesc .. "\n    Amount:  " .. itemCount
        end
        if cache.isRuneSpell and spellData then
            actionDesc = actionDesc .. "\n" .. spellStatsTooltip(spellData)
        end
    end

    local hotkeyDesc = cache.hotkey ~= nil and cache.hotkey or "None"
    local tooltip = "Action Button " .. button:getId()

    if cache.actionType == UseTypes["passiveAbility"] then
        tooltip = tooltip .. "\n\n Passive Ability:  " .. actionDesc
        tooltip = tooltip .. "\n            Hotkeys:  " .. hotkeyDesc
    else
        tooltip = tooltip .. "\n\n       Action:  " .. actionDesc
        tooltip = tooltip .. "\n   Hotkeys:  " .. hotkeyDesc
    end

    if button.item then
        button.item:setTooltip(tooltip)
    end
end


-- /*=============================================
-- =       Animation Cooldown    =
-- =============================================*/
function checkRemainSpellCooldown(button, spellId)
    if not modules.client_options.getOption("graphicalCooldown") and
        not modules.client_options.getOption("cooldownSecond") then
        return true
    end

    local cooldownData = spellCooldownCache[spellId]
    if not cooldownData then
        return
    end

    if (cooldownData.startTime + cooldownData.exhaustion) < g_clock.millis() then
        return
    end

    button.cache = getButtonCache(button)
    local remainTime = (cooldownData.startTime + cooldownData.exhaustion) - g_clock.millis()

    updateCooldown(button, remainTime)
    if button.cache.removeCooldownEvent then
        removeEvent(button.cache.removeCooldownEvent)
        button.cache.removeCooldownEvent = nil
    end
    button.cache.removeCooldownEvent = scheduleEvent(function()
        removeCooldown(button)
    end, remainTime)
end

function removeCooldown(button)
    if not button or button:isDestroyed() then
        return true
    end

    if button.cache then
        button.cache.removeCooldownEvent = nil
    end
    if button.cooldown and not button.cooldown:isDestroyed() then
        button.cooldown:stop()
        button.cooldown:setPercent(100)
        button.cooldown:setText("")
    end
end

function clearActionBarCooldownVisuals()
    for barId = 1, #actionBars do
        local actionbar = actionBars[barId]
        if actionbar and not actionbar:isDestroyed() and actionbar.tabBar then
            for _, button in pairs(actionbar.tabBar:getChildren()) do
                removeCooldown(button)
            end
        end
    end
    for _, button in pairs(freeActionButtonCopies) do
        removeCooldown(button)
    end
end

function updateCooldown(button, timeMs)
    button.cooldown:showTime(modules.client_options.getOption("cooldownSecond"))
    button.cooldown:showProgress(modules.client_options.getOption("graphicalCooldown"))
    if button.cooldown.setProgressStyle then
        button.cooldown:setProgressStyle(1) -- FrameCharge
    end
    button.cooldown:setDuration(timeMs)
    button.cooldown:start()
end

function updateActionPassive(button)
    if not modules.client_options.getOption("graphicalCooldown") and
        not modules.client_options.getOption("cooldownSecond") then
        return true
    end

    if not button then
        for _, actionbar in pairs(activeActionBars) do
            for _, button in pairs(actionbar.tabBar:getChildren()) do
                local cache = button.cache
                if cache and cache.isPassive then
                    button.item.text.gray:setVisible(passiveData.max == 0)
                    if cache.cooldownEvent == nil then
                        updateCooldown(button, passiveData.cooldown * 1000)
                        if cache.removeCooldownEvent then
                            removeEvent(cache.removeCooldownEvent)
                            cache.removeCooldownEvent = nil
                        end
                        cache.removeCooldownEvent = scheduleEvent(function()
                            removeCooldown(button)
                        end, passiveData.cooldown * 1000)
                    end
                end
            end
        end
        for _, copy in pairs(freeActionButtonCopies) do
            local cache = copy.cache
            if cache and cache.isPassive then
                copy.item.text.gray:setVisible(passiveData.max == 0)
                if cache.cooldownEvent == nil then
                    updateCooldown(copy, passiveData.cooldown * 1000)
                    cache.removeCooldownEvent = scheduleEvent(function()
                        removeCooldown(copy)
                    end, passiveData.cooldown * 1000)
                end
            end
        end
        return true
    else
        if button.cache.isPassive then
            button.item.text.gray:setVisible(passiveData.max == 0)
        end
    end

    if passiveData.max > 0 then
        if button.cache.removeCooldownEvent then
            removeEvent(button.cache.removeCooldownEvent)
            button.cache.removeCooldownEvent = nil
        end
        updateCooldown(button, passiveData.cooldown * 1000)
        button.cache.removeCooldownEvent = scheduleEvent(function()
            removeCooldown(button)
        end, passiveData.cooldown * 1000)
    end
end

-- /*=============================================
-- =       right button in an action bar slot    =
-- =============================================*/
function configureButtonMouseRelease(button)
    button.onMouseRelease = function(button, mousePos, mouseButton)
        button.cache = getButtonCache(button)
        if mouseButton == MouseRightButton then
            local menu = g_ui.createWidget('PopupMenu')
            menu:setGameMenu(true)
            menu:addOption(button.cache.isSpell and tr('Edit Spell') or tr('Assign Spell'), function()
                assignSpell(button)
            end)
            if button.item and button.item:getItemId() > 100 then
                menu:addOption(tr('Edit Object'), function()
                    assignItem(button, button.item:getItemId())
                end)
            else
                menu:addOption(tr('Assign Object'), function()
                    assignItemEvent(button)
                end)
            end

            local buttonText = ""
            if button.item then
                buttonText = button.item.text:getText()
            end

            menu:addOption(buttonText:len() > 0 and tr('Edit Text') or tr('Assign Text'), function()
                assignText(button)
            end)
            menu:addOption(button.cache.isPassive and tr('Edit Passive Ability') or tr('Assign Passive Ability'),
                function()
                    assignPassive(button)
                end)
            menu:addOption(button.cache.specialAction and tr('Edit Action') or tr('Assign Action'), function()
                assignSpecialAction(button, mousePos)
            end)
            menu:addOption(button.cache.hotkey and tr('Edit Hotkey') or tr('Assign Hotkey'), function()
                assignHotkey(button)
            end)
            if button.cache.hotkey then
                menu:addOption(tr('Clear Hotkey'), function()
                    ApiJson.removeHotkey(button:getId())
                    unbindHotkey(button.cache.hotkey)
                    clearHotkeyCache()
                    updateButton(button)
                end)
            end

            local buttonHasMulti = hasMultiActions(button.cache.multiActions)
            local hasMultiIcon = button.multiIcon and button.multiIcon:isVisible()
            local hasMultiActions = buttonHasMulti
            if assignMultiAction then
                local panelOpen = multiPanel and not multiPanel:isDestroyed() and multiPanel.button == button
                if panelOpen then
                    menu:addOption(tr('Close Multi-Action'), function()
                        closeCurrentMultiActionPanel()
                    end)
                else
                    menu:addOption((hasMultiActions or hasMultiIcon) and tr('Edit Multi-Action') or tr('Assign Multi-Action'),
                        function()
                            assignMultiAction(button)
                        end)
                end
            end

            if isEquipmentPresetCache and isEquipmentPresetCache(button.cache) then
                menu:addOption(tr('Edit Equipments'), function()
                    assignEquipment(button)
                end)
            else
                menu:addOption(tr('Assign Equipments'), function()
                    assignEquipment(button)
                end)
            end

            if button.cache.actionType > 0 or hasMultiActions then
                menu:addSeparator()
                menu:addOption(tr('Clear Action'), function()
                    if closeCurrentMultiActionPanel and multiPanel and multiPanel.button == button then
                        closeCurrentMultiActionPanel()
                    end
                    local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
                    if hasMultiActions then
                        for i = 1, 3 do
                            ApiJson.removeMultiAction(tonumber(barID), tonumber(buttonID), i)
                        end
                    end
                    clearButton(button, true)
                end)
            end
            if button.item and button.item:getItemId() > 100 then
                if modules.game_bot then
                    menu:addSeparator()
                    local useThingId = button.item:getItemId()
                    menu:addOption("ID: " .. useThingId, function() g_window.setClipboardText(useThingId) end)
                end
            end
            menu:display(mousePos)
        end
    end
end
-- /*=============================================
-- =       click left in the action bar slot    =
-- =============================================*/
--- Updates the button's visual representation
function updateButton(button)
    local startUpdate = g_clock.millis()
    if not player then
        player = g_game.getLocalPlayer()
    end

    local barID, buttonID = string.match(button:getId(), "(%d+)%.(%d+)")
    local barIndex = tonumber(barID)
    local buttonIndex = tonumber(buttonID)
    local buttonData = nil

    if not button.item then
        local actionId, buttonId = button:getId():match("([^.]+)%.([^.]+)")
        button:destroy()
        local actionbar = actionBars[tonumber(actionId)]
        local layout = tonumber(actionId) < 4 and 'ActionButton' or 'SideActionButton'
        local widget = g_ui.createWidget(layout, actionbar.tabBar)
        actionbar.tabBar:moveChildToIndex(widget, tonumber(buttonId))
        widget:setId(actionId .. "." .. buttonId)
        updateButton(widget)
        return
    end

    if button.multiPanel then
        if closeCurrentMultiActionPanel and multiPanel and button.multiPanel == multiPanel then
            closeCurrentMultiActionPanel()
        else
            button.onGeometryChange = nil
            button.onVisibilityChange = nil
            if not button.multiPanel:isDestroyed() then
                button.multiPanel:destroy()
            end
            button.multiPanel = nil
        end
    end

    buttonData = ApiJson.getMapping(barIndex, buttonIndex)
    
    local isClean = button.cache and button.cache.actionType == 0 and button.item:getItemId() == 0
    local hasNewData = buttonData and buttonData["actionsetting"]
    
    if isClean and not hasNewData then
         setupHotkeyButton(button)
         if button.cache.hotkey then
             button.item.text:setTextOffset("0 8")
             button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
         else
             button.hotkeyLabel:setText('') -- ensure cleared
         end
         
         setupButtonTooltip(button, true)
         button.item:setDraggable(false)
         configureButtonMouseRelease(button)
         return true
    end

    resetButtonCache(button)
    
    button.item.text:setTextOffset("0 0")
    button.cache = getButtonCache(button) -- Ensure cache is grabbed (resetButtonCache ensures it exists)

    if button.item.getItemId and not button.cache.actionType then
        if button.item:getItemId() ~= 0 then -- Optimization check
            button.item:setItemId(0, true)
        end
        if button.item:isOn() then button.item:setOn(false) end
    end

    setupHotkeyButton(button)
    
    if button.cache.hotkey then
        button.item.text:setTextOffset("0 8")
        button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
    end

    if not buttonData or not buttonData["actionsetting"] then
        local startTips = g_clock.millis()
        setupButtonTooltip(button, true)
        local tipsTime = g_clock.millis() - startTips
        
        button.item:setDraggable(false)
        configureButtonMouseRelease(button)
        return true
    end

    local useAction = buttonData["actionsetting"]["useObject"]
    local sendText = buttonData["actionsetting"]["chatText"]
    local passiveAbility = buttonData["actionsetting"]["passiveAbility"]
    local specialAction = buttonData["actionsetting"]["specialAction"]
    local multiActions = buttonData["actionsetting"]["multiActions"]
    local equipmentsSetting = buttonData["actionsetting"]["equipments"]
    local equipmentIconIndex = buttonData["actionsetting"]["equipmentIconIndex"]

    local hasMultiData = type(multiActions) == "table" and hasMultiActions(multiActions) or false

    if buttonData["actionsetting"]["useType"] == "Equip"
        and (equipmentsSetting ~= nil or (type(equipmentIconIndex) == "number" and equipmentIconIndex > 0)) then
        button.cache.actionType = UseTypes["Equip"]
        button.cache.equipments = normalizeEquipmentsFromSetting and normalizeEquipmentsFromSetting(equipmentsSetting) or {}
        button.cache.equipmentIconIndex = equipmentIconIndex or 0
        button.cache.equipmentDescription = buttonData["actionsetting"]["equipmentDescription"] or ""
        button.cache.equipmentTypeIndex = buttonData["actionsetting"]["equipmentTypeIndex"] or 0
        button.cache.isEquipmentPreset = true
        button.cache.smartMode = false
        local display = equipmentAssignDisplayEntry and equipmentAssignDisplayEntry(button.cache.equipments)
        if display then
            button.cache.itemId = display.itemId
            button.cache.upgradeTier = display.getTier or 0
        else
            button.cache.itemId = 0
            button.cache.upgradeTier = 0
        end
        if loadEquipmentPresetDisplay then
            loadEquipmentPresetDisplay(button)
        end
        button.item:setDraggable(true)
        button.item.onClick = function()
            onExecuteAction(button)
        end
        if button.item.text then
            button.item.text.onClick = function()
                onExecuteAction(button)
            end
        end
        configureButtonMouseRelease(button)
        return true
    end

    if hasMultiData then
        button.cache.multiActions = {{}, {}, {}}
        for i = 1, 3 do
            if type(multiActions[i]) == "table" then
                button.cache.multiActions[i] = multiActions[i]
            end
        end
        if button.multiIcon then
            button.multiIcon:setVisible(true)
        end
        if cacheMultiActionButtons then
            cacheMultiActionButtons[button] = true
        end

        if updateMultiButtonState then
            updateMultiButtonState(button)
        end
        if registerMultiActionCooldownEvents then
            registerMultiActionCooldownEvents(button)
        end

        button.item:setDraggable(true)

        local parentButton = button:getParent()
        if parentButton then
            button.cache.buttonIndex = parentButton:getChildIndex(button)
            button.cache.buttonParent = parentButton
        end

        local barIndexLocal = barIndex
        button.item.onDragEnter = function(self, mousePos)
            if ApiJson.isBarLocked(barIndexLocal) then
                return false
            end
            button.cooldown:setBorderWidth(1)
            button.cache.isDragging = true
            dragButton = button
            dragItem = self
            return true
        end
        button.item.onDragMove = function(self, mousePos)
            self:setPhantom(true)
            self:setParent(gameRootPanel)
            self:setX(mousePos.x)
            self:setY(mousePos.y)
            self:setBorderColor('white')
            if lastHighlightWidget then
                lastHighlightWidget:setBorderWidth(0)
                lastHighlightWidget:setBorderColor('alpha')
            end
            local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
            if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
                return true
            end
            lastHighlightWidget = clickedWidget
            lastHighlightWidget:setBorderWidth(1)
            lastHighlightWidget:setBorderColor('white')
        end
        button.item.onDragLeave = function(self, widget, mousePos)
            if not button.cache.isDragging then
                return false
            end
            isLoaded = false
            button.cache.isDragging = false
            onDragItemLeave(self, mousePos, button)
            isLoaded = true
            dragButton = nil
            dragItem = nil
        end

        button.item.onClick = function()
            onExecuteAction(button)
        end
        button.item.text.onClick = function()
            onExecuteAction(button)
        end
        configureButtonMouseRelease(button)
        return true
    end

    if useAction then
        button.item:setItemId(useAction, true)
        button.item:setOn(true)
        local cached = cachedItemWidget[useAction]
        if not cached then
            cachedItemWidget[useAction] = {}
            cached = cachedItemWidget[useAction]
        end
        if not table.contains(cached, button) then
            table.insert(cached, button)
        end
        local spellData = Spells.getRuneSpellByItem(useAction)
        if spellData then
            button.cache.isRuneSpell = true
            button.cache.spellData = spellData
            if spellData.vocations and not table.contains(spellData.vocations, translateVocation(player:getVocation())) then
                button.item.gray:setVisible(true)
            end
        end

        button.cache.itemId = button.item:getItemId()
        button.cache.upgradeTier = buttonData["actionsetting"]["upgradeTier"]
        button.cache.smartMode = buttonData["actionsetting"]["useEquipSmartMode"] or false
        local useTypeName = buttonData["actionsetting"]["useType"]
        button.cache.actionType = UseTypes[useTypeName] or UseTypes["Use"]
        ItemsDatabase.setTier(button.item, button.cache.upgradeTier)
        updateButtonState(button)
    end

    if sendText then
        local spellData, param = Spells.getSpellDataByParamWords(sendText:lower())
        if spellData then
            local source = SpelllistSettings['Default'].iconFile
            local clip = Spells.getSpellImageClip(spellData, 'Default')

            button.item.text:setImageSource(source)
            button.item.text:setImageClip(clip)
            button.cache.isSpell = true
            button.cache.spellID = spellData.id
            button.cache.spellData = spellData
            local groupIds = Spells.getGroupIds(spellData)
            button.cache.primaryGroup = groupIds and groupIds[1] or nil

            if param then
                local formatedParam = param:gsub('"', '')
                button.parameterText:setText(short_text('"' .. formatedParam, 4))
                button.cache.castParam = formatedParam
            end

            if not playerCanUseSpell(spellData) then
                button.item.text.gray:setVisible(true)
            end

            checkRemainSpellCooldown(button, spellData.id)
        else
            button.item.text:setText(short_text(sendText, 15))
        end

        button.item:setOn(true)
        button.cache.param = sendText
        button.cache.sendAutomatic = buttonData["actionsetting"]["sendAutomatically"]
        button.cache.actionType = UseTypes["chatText"]
    end

    if passiveAbility then
        local passive = PassiveAbilities[passiveAbility]
        button.item.text:setImageSource(passive.icon)
        button.item.text:setImageClip("0 0 32 32")
        button.cache.actionType = UseTypes["passiveAbility"]
        button.cache.isPassive = true
        updateActionPassive(button)
    end

    if specialAction then
        local specialActionData = getActionBarSpecialAction(specialAction)
        button.item.text:setText(short_text(specialActionData and specialActionData.text or specialAction, 15))
        button.item:setOn(true)
        button.cache.specialAction = specialAction
        button.cache.actionType = UseTypes["specialAction"]
    end

    button.item:setDraggable(true)
    setupButtonTooltip(button, false)

    local parentButton = button:getParent()
    if parentButton then
        button.cache.buttonIndex = parentButton:getChildIndex(button)
        button.cache.buttonParent = parentButton
    end

    button.item.onDragEnter = function(self, mousePos)
        if ApiJson.isBarLocked(barIndex) then
            return false
        end

        button.cooldown:setBorderWidth(1)
        button.cache.isDragging = true
        dragButton = button
        dragItem = self
        return true
    end
    button.item.onDragMove = function(self, mousePos)
        self:setPhantom(true)
        self:setParent(gameRootPanel)
        self:setX(mousePos.x)
        self:setY(mousePos.y)

        self:setBorderColor('white')

        if lastHighlightWidget then
            lastHighlightWidget:setBorderWidth(0)
            lastHighlightWidget:setBorderColor('alpha')
        end

        local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
        if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
            return true
        end

        lastHighlightWidget = clickedWidget
        lastHighlightWidget:setBorderWidth(1)
        lastHighlightWidget:setBorderColor('white')
    end

    button.item.onDragLeave = function(self, widget, mousePos)
        if not button.cache.isDragging then
            return false
        end
        isLoaded = false
        button.cache.isDragging = false
        onDragItemLeave(self, mousePos, button)
        isLoaded = true
        dragButton = nil
        dragItem = nil
    end

    button.item.onClick = function()
        onExecuteAction(button)
    end
    button.item.text.onClick = function()
        onExecuteAction(button)
    end
    if button.multiIcon then
        button.multiIcon:setVisible(false)
    end
    configureButtonMouseRelease(button)
    ActionBarController:scheduleEvent(function()
        onMultiUseCooldown()
    end, 100)
end
-- /*=============================================
-- =            Mouse Drag Event             =
-- =============================================*/
-- item in UIMap or UIWidget(UIItem) drop in slot actionbar
--- Gets button from widget
local function getButtonFromWidget(widget)
    if not widget then
        return nil
    end

    local widgetId = widget:getId()
    if widgetId and widgetId:match("^%d+%.%d+$") then
        return widget
    end

    return getButtonFromWidget(widget:getParent())
end

--- Resolves dropped item data
local function resolveDroppedItemData(draggedWidget, item)
    if type(item) == 'number' then
        local itemTier = 0
        if draggedWidget and draggedWidget.getItem then
            local draggedItem = draggedWidget:getItem()
            if draggedItem and draggedItem.getTier then
                itemTier = draggedItem:getTier() or 0
            end
        end
        return item, itemTier
    end

    if item and item.getId then
        local itemId = item:getId()
        local itemTier = item.getTier and (item:getTier() or 0) or 0
        return itemId, itemTier
    end

    return nil, 0
end

--- Tries to assign action from a drop event
function tryAssignActionButtonFromDrop(mousePos, draggedWidget, item)
    if not hasAnyActiveActionBar() or not item then
        return false
    end
    if dragButton or not draggedWidget or not gameRootPanel then
        return false
    end

    local className = draggedWidget:getClassName()
    if className ~= 'UIItem' and className ~= 'UIGameMap' then
        return false
    end

    if className == 'UIItem' then
        local parentWidget = draggedWidget:getParent()
        if parentWidget and parentWidget:getId() == 'actionBarPanel' then
            return false
        end
    end

    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
    if not clickedWidget then
        return false
    end

    if clickedWidget:getParent() then
        local parentId = clickedWidget:getParent():getId() or ""
        local targetIndex = tonumber(string.match(parentId, "^actionButton(%d)$"))
        if targetIndex and targetIndex >= 1 and targetIndex <= 3 then
            local panel = clickedWidget:getParent():getParent()
            if panel and panel.button then
                local itemId, itemTier = resolveDroppedItemData(draggedWidget, item)
                if not itemId then
                    return false
                end
                local thingType = g_things.getThingType(itemId, ThingCategoryItem)
                if not thingType or not thingType:isPickupable() then
                    return false
                end
                if assignMultiItem then
                    assignMultiItem(panel.button, targetIndex, itemId, itemTier, true)
                    return true
                end
                return false
            end
        end
    end

    local tabBar = clickedWidget:backwardsGetWidgetById("tabBar")
    if not tabBar or not tabBar:isVisible() then
        return false
    end

    local button = getButtonFromWidget(clickedWidget)
    if not button or not button:isVisible() then
        return false
    end

    local actionBar = tabBar:getParent()
    if not actionBar or not actionBar:isVisible() then
        return false
    end

    local itemId, itemTier = resolveDroppedItemData(draggedWidget, item)
    if not itemId then
        return false
    end

    local thingType = g_things.getThingType(itemId, ThingCategoryItem)
    if not thingType or not thingType:isPickupable() then
        return false
    end

    assignItem(button, itemId, itemTier)
    return true
end

--- Tries to assign a spell from the spell list drag-and-drop
function tryAssignSpellFromDrop(mousePos, spellData)
    if not hasAnyActiveActionBar() or not spellData or not gameRootPanel then
        return false
    end
    if dragButton then
        return false
    end

    local spellText = spellData.words or spellData.name
    if not spellText or spellText == '' then
        return false
    end

    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
    if not clickedWidget then
        return false
    end

    if clickedWidget:getParent() then
        local parentId = clickedWidget:getParent():getId() or ""
        local targetIndex = tonumber(string.match(parentId, "^actionButton(%d)$"))
        if targetIndex and targetIndex >= 1 and targetIndex <= 3 then
            local panel = clickedWidget:getParent():getParent()
            if panel and panel.button then
                local button = panel.button
                local actionbar = button:getParent() and button:getParent():getParent()
                if not actionbar or not actionbar:isVisible() or actionbar.locked then
                    return false
                end

                local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
                if not barID or ApiJson.isBarLocked(tonumber(barID)) then
                    return false
                end

                ApiJson.createOrUpdateMultiText(tonumber(barID), tonumber(buttonID), targetIndex, spellText, true)
                if updateMultiButtonState then
                    updateMultiButtonState(button)
                end
                if assignMultiAction then
                    assignMultiAction(button, true)
                end
                ApiJson.saveData()
                return true
            end
        end
    end

    local tabBar = clickedWidget:backwardsGetWidgetById("tabBar")
    if not tabBar or not tabBar:isVisible() then
        return false
    end

    local button = getButtonFromWidget(clickedWidget)
    if not button or not button:isVisible() then
        return false
    end

    local actionBar = tabBar:getParent()
    if not actionBar or not actionBar:isVisible() or actionBar.locked then
        return false
    end

    local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
    if not barID or ApiJson.isBarLocked(tonumber(barID)) then
        return false
    end

    ApiJson.createOrUpdateText(tonumber(barID), tonumber(buttonID), spellText, true)
    updateButton(button)
    ApiJson.saveData()
    return true
end

-- move button to other slot bar 
--- Resets a dragging widget
function resetDragWidget(self, button)
    button.cache = getButtonCache(button)
    local cachedItem = cachedItemWidget[button.cache.itemId]
    if cachedItem then
        for index, widget in pairs(cachedItem) do
            if button == widget then
                table.remove(cachedItem, index)
            end
        end
    end

    self:destroy()
    local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
    local style = tonumber(barID) > 3 and "SideActionButton" or "ActionButton"

    button:destroy()

    local destBar = actionBars[tonumber(barID)].tabBar
    local widget = g_ui.createWidget(style, destBar)

    if destBar then
        destBar:moveChildToIndex(widget, buttonID)
    end
    widget:setId(barID .. "." .. buttonID)
    updateButton(widget)
end

--- Handles drag item leave event
local function isFreeActionBarPlacementEnabled()
    return modules.client_options and modules.client_options.getOption
        and modules.client_options.getOption('freeActionBarPlacement') == true
end

local function saveFreeActionButtonCopies()
    local placements = {}
    for id, copy in pairs(freeActionButtonCopies) do
        if copy and not copy:isDestroyed() then
            local position = copy:getPosition()
            placements[id] = {
                x = position.x,
                y = position.y,
                locked = freeActionButtonLocks[id] == true
            }
        end
    end
    g_settings.setNode('freeActionBarButtonCopies', placements)
end

local function setFreeActionButtonSelected(id, selected)
    local copy = freeActionButtonCopies[id]
    local state = selectedFreeActionButtonCopies[id]
    if not copy or copy:isDestroyed() then
        selectedFreeActionButtonCopies[id] = nil
        return
    end
    local highlight = copy.item or copy

    if not selected then
        if state and state.event then
            removeEvent(state.event)
        end
        selectedFreeActionButtonCopies[id] = nil
        highlight:setBorderWidth(0)
        highlight:setBorderColor('alpha')
        return
    end

    if state then
        return
    end

    state = { phase = 0 }
    selectedFreeActionButtonCopies[id] = state
    local function pulse()
        if copy:isDestroyed() or selectedFreeActionButtonCopies[id] ~= state then
            return
        end
        state.phase = state.phase + 0.12
        local intensity = math.floor(190 + 65 * (0.5 + 0.5 * math.sin(state.phase)))
        local channel = string.format('%02x', intensity)
        highlight:setBorderWidth(1)
        highlight:setBorderColor('#' .. channel .. channel .. channel)
        state.event = scheduleEvent(pulse, 80)
    end
    pulse()
end

local function clearFreeActionButtonSelection(keepId)
    local ids = {}
    for id in pairs(selectedFreeActionButtonCopies) do
        if id ~= keepId then
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(ids) do
        setFreeActionButtonSelected(id, false)
    end
end

local function removeFreeActionButtonCopy(id)
    local copy = freeActionButtonCopies[id]
    setFreeActionButtonSelected(id, false)
    freeActionButtonCopies[id] = nil
    freeActionButtonLocks[id] = nil
    if copy and not copy:isDestroyed() then
        copy:destroy()
    end
end

local function removeFreeActionButtonCopies(selectedOnly, selectedIds)
    local ids = selectedIds or {}
    if selectedOnly and not selectedIds then
        for id in pairs(selectedFreeActionButtonCopies) do
            ids[#ids + 1] = id
        end
    elseif not selectedOnly then
        for id in pairs(freeActionButtonCopies) do
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(ids) do
        removeFreeActionButtonCopy(id)
    end
    saveFreeActionButtonCopies()
end

local function isFreeActionButtonInWidgetTree(widget, copy)
    local current = widget
    while current do
        if current == copy then
            return true
        end
        current = current:getParent()
    end
    return false
end

local function clearSelectionWhenClickingAway()
    if not gameRootPanel then
        return
    end
    if freeActionSelectionClickAwayHandler
        and gameRootPanel.onMouseRelease == freeActionSelectionClickAwayHandler then
        return
    end
    freeActionSelectionClickAwayHandler = function(root, mousePos, mouseButton)
        if mouseButton == MouseLeftButton and not g_keyboard.isAltPressed() then
            local clickedWidget = root:recursiveGetChildByPos(mousePos, false)
            local clickedCopy = false
            for _, copy in pairs(freeActionButtonCopies) do
                if copy and not copy:isDestroyed() and isFreeActionButtonInWidgetTree(clickedWidget, copy) then
                    clickedCopy = true
                    break
                end
            end
            if not clickedCopy then
                clearFreeActionButtonSelection()
            end
        end
        if previousFreeActionSelectionMouseReleaseHandler then
            return previousFreeActionSelectionMouseReleaseHandler(root, mousePos, mouseButton)
        end
        return false
    end
    previousFreeActionSelectionMouseReleaseHandler = gameRootPanel.onMouseRelease
    gameRootPanel.onMouseRelease = freeActionSelectionClickAwayHandler
end

function clearFreeActionButtonSelectionClickAwayHandler()
    if gameRootPanel and gameRootPanel.onMouseRelease == freeActionSelectionClickAwayHandler then
        gameRootPanel.onMouseRelease = previousFreeActionSelectionMouseReleaseHandler
    end
    freeActionSelectionClickAwayHandler = nil
    previousFreeActionSelectionMouseReleaseHandler = nil
end

function resetFreeActionBarRuntimeCopies()
    saveFreeActionButtonCopies()
    clearFreeActionButtonSelection()
    for id, copy in pairs(freeActionButtonCopies) do
        if copy and not copy:isDestroyed() then
            if copy.cache and copy.cache.removeCooldownEvent then
                removeEvent(copy.cache.removeCooldownEvent)
                copy.cache.removeCooldownEvent = nil
            end
            removeCooldown(copy)
            if resetButtonCache then
                resetButtonCache(copy)
            end
            copy:destroy()
        end
        freeActionButtonCopies[id] = nil
    end
    selectedFreeActionButtonCopies = {}
end

local function copyOverlapsPosition(copy, position, placedCopies)
    local width = copy:getWidth()
    local height = copy:getHeight()
    for _, placed in ipairs(placedCopies) do
        local otherPosition = placed:getPosition()
        if position.x < otherPosition.x + placed:getWidth()
            and position.x + width > otherPosition.x
            and position.y < otherPosition.y + placed:getHeight()
            and position.y + height > otherPosition.y then
            return true
        end
    end
    return false
end

local function findFreeCopyPosition(copy, preferredPosition, placedCopies)
    local width = copy:getWidth()
    local height = copy:getHeight()
    local maxX = math.max(0, gameRootPanel:getWidth() - width)
    local maxY = math.max(0, gameRootPanel:getHeight() - height)
    local origin = {
        x = math.max(0, math.min(maxX, preferredPosition.x)),
        y = math.max(0, math.min(maxY, preferredPosition.y))
    }
    local overlapsAnotherCopy = copyOverlapsPosition(copy, origin, placedCopies)
    if #placedCopies == 0 then
        return origin
    end

    local bestPosition = nil
    local bestDistance = math.huge
    for _, placed in ipairs(placedCopies) do
        local anchor = placed:getPosition()
        local candidates = {
            { x = anchor.x, y = anchor.y - height }, -- above
            { x = anchor.x, y = anchor.y + placed:getHeight() }, -- below
            { x = anchor.x - width, y = anchor.y }, -- left
            { x = anchor.x + placed:getWidth(), y = anchor.y } -- right
        }
        for _, candidate in ipairs(candidates) do
            local inBounds = candidate.x >= 0 and candidate.y >= 0
                and candidate.x <= maxX and candidate.y <= maxY
            if inBounds and not copyOverlapsPosition(copy, candidate, placedCopies) then
                local dx = candidate.x - origin.x
                local dy = candidate.y - origin.y
                local distance = dx * dx + dy * dy
                if distance < bestDistance then
                    bestDistance = distance
                    bestPosition = candidate
                end
            end
        end
    end
    -- Keep free placement unless the drop is close to a neighboring slot.
    -- If the icon overlaps another one, still move it to the nearest free side.
    local snapDistance = 12
    if bestPosition and (bestDistance <= snapDistance * snapDistance or overlapsAnotherCopy) then
        return bestPosition
    end
    return origin
end

local function resolveFreeActionBarCopyOverlaps(preferredId)
    local copy = freeActionButtonCopies[preferredId]
    if not copy or copy:isDestroyed() then
        return
    end

    local otherCopies = {}
    for id, other in pairs(freeActionButtonCopies) do
        if id ~= preferredId and other and not other:isDestroyed() then
            otherCopies[#otherCopies + 1] = other
        end
    end
    copy:setPosition(findFreeCopyPosition(copy, copy:getPosition(), otherCopies))
end

local function createFreeActionButtonCopy(sourceButton, position)
    if not sourceButton or not sourceButton.cache or not sourceButton.cache.actionType
        or sourceButton.cache.actionType == 0 then
        return false
    end

    local id = sourceButton:getId()
    local existing = freeActionButtonCopies[id]
    if existing and not existing:isDestroyed() then
        existing:setPosition(position)
        existing:setVisible(isFreeActionBarPlacementEnabled())
        resolveFreeActionBarCopyOverlaps(id)
        saveFreeActionButtonCopies()
        return true
    end

    local barId = tonumber(string.match(id, '^(%d+)%.'))
    local layout = barId and barId < 4 and 'ActionButton' or 'SideActionButton'
    local copy = g_ui.createWidget(layout, gameRootPanel)
    copy:setId(id)
    copy:setPosition(position)
    copy:setVisible(isFreeActionBarPlacementEnabled())
    updateButton(copy)
    local lockMarker = g_ui.createWidget('UIWidget', copy)
    lockMarker:setId('freeActionBarLockMarker')
    lockMarker:setSize({ width = 12, height = 12 })
    lockMarker:setImageSize({ width = 12, height = 12 })
    lockMarker:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    lockMarker:addAnchor(AnchorTop, 'parent', AnchorTop)
    lockMarker:setImageSource('/images/game/actionbar/locked')
    lockMarker:setPhantom(true)
    lockMarker:setVisible(freeActionButtonLocks[id] == true)
    copy.lockMarker = lockMarker
    copy.onMouseRelease = function(self, mousePos, mouseButton)
        if mouseButton ~= MouseRightButton then
            return false
        end

        if not selectedFreeActionButtonCopies[id] then
            if not g_keyboard.isAltPressed() then
                clearFreeActionButtonSelection()
            end
            setFreeActionButtonSelected(id, true)
        end

        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        local lockOption = g_ui.createWidget(menu:getStyleName() .. 'Button', menu)
        lockOption:setText(freeActionButtonLocks[id] and tr('Unlock') or tr('Lock'))
        lockOption:setTextOffset('20 0')
        lockOption.onClick = function()
            menu:destroy()
            freeActionButtonLocks[id] = not freeActionButtonLocks[id]
            if copy.lockMarker then
                copy.lockMarker:setVisible(freeActionButtonLocks[id])
            end
            if copy.item then
                copy.item:setDraggable(not freeActionButtonLocks[id])
            end
            saveFreeActionButtonCopies()
        end
        local lockIcon = g_ui.createWidget('UIWidget', lockOption)
        lockIcon:setSize({ width = 14, height = 14 })
        lockIcon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        lockIcon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        lockIcon:setMarginLeft(3)
        lockIcon:setImageSource(freeActionButtonLocks[id]
            and '/images/game/actionbar/locked' or '/images/game/actionbar/unlocked')
        lockIcon:setPhantom(true)
        local lockOptionWidth = lockOption:getTextSize().width + lockOption:getMarginLeft()
            + lockOption:getMarginRight() + 30
        menu:setWidth(math.max(menu:getWidth(), lockOptionWidth))
        local selectedIds = {}
        for selectedId in pairs(selectedFreeActionButtonCopies) do
            selectedIds[#selectedIds + 1] = selectedId
        end
        menu:addOption(tr('Remove'), function()
            if freeActionButtonCopies[id] == self then
                removeFreeActionButtonCopy(id)
                saveFreeActionButtonCopies()
            end
        end)
        menu:addOption(tr('Remove All'), function()
            removeFreeActionButtonCopies(#selectedIds > 1, selectedIds)
        end)
        menu:display(mousePos)
        return true
    end
    if copy.item then
        copy.item:setDraggable(not freeActionButtonLocks[id])
        local dragSelection = nil
        local activateAction = copy.item.onClick
        copy.item.onClick = function(...)
            if g_keyboard.isAltPressed() then
                setFreeActionButtonSelected(id, not selectedFreeActionButtonCopies[id])
                return true
            end
            clearFreeActionButtonSelection()
            if activateAction then
                return activateAction(...)
            end
        end
        copy.item.onDragEnter = function(_, mousePos)
            if not isFreeActionBarPlacementEnabled() or freeActionButtonLocks[id] then
                return false
            end
            dragSelection = nil
            if selectedFreeActionButtonCopies[id] then
                local positions = {}
                local minX, minY, maxX, maxY
                for selectedId in pairs(selectedFreeActionButtonCopies) do
                    local selectedCopy = freeActionButtonCopies[selectedId]
                    if selectedCopy and not selectedCopy:isDestroyed() then
                        local position = selectedCopy:getPosition()
                        positions[selectedId] = position
                        minX = math.min(minX or position.x, position.x)
                        minY = math.min(minY or position.y, position.y)
                        maxX = math.max(maxX or (position.x + selectedCopy:getWidth()),
                            position.x + selectedCopy:getWidth())
                        maxY = math.max(maxY or (position.y + selectedCopy:getHeight()),
                            position.y + selectedCopy:getHeight())
                    end
                end
                if table.size(positions) > 1 then
                    dragSelection = {
                        start = mousePos,
                        positions = positions,
                        minX = minX,
                        minY = minY,
                        maxX = maxX,
                        maxY = maxY
                    }
                end
            end
            return true
        end
        copy.item.onDragMove = function(_, mousePos)
            if dragSelection then
                local deltaX = mousePos.x - dragSelection.start.x
                local deltaY = mousePos.y - dragSelection.start.y
                deltaX = math.max(-dragSelection.minX,
                    math.min(gameRootPanel:getWidth() - dragSelection.maxX, deltaX))
                deltaY = math.max(-dragSelection.minY,
                    math.min(gameRootPanel:getHeight() - dragSelection.maxY, deltaY))
                for selectedId, startPosition in pairs(dragSelection.positions) do
                    local selectedCopy = freeActionButtonCopies[selectedId]
                    if selectedCopy and not selectedCopy:isDestroyed() then
                        selectedCopy:setPosition({
                            x = startPosition.x + deltaX,
                            y = startPosition.y + deltaY
                        })
                    end
                end
            else
                copy:setPosition({ x = mousePos.x - 17, y = mousePos.y - 17 })
            end
            return true
        end
        copy.item.onDragLeave = function()
            if dragSelection then
                dragSelection = nil
            else
                resolveFreeActionBarCopyOverlaps(id)
            end
            saveFreeActionButtonCopies()
            return true
        end
    end
    freeActionButtonCopies[id] = copy
    resolveFreeActionBarCopyOverlaps(id)
    saveFreeActionButtonCopies()
    return true
end

function restoreFreeActionButtonCopies()
    local placements = g_settings.getNode('freeActionBarButtonCopies') or {}
    local ids = {}
    for id in pairs(placements) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local position = placements[id]
        if type(id) == 'string' and type(position) == 'table'
            and tonumber(string.match(id, '^(%d+)%.(%d+)$')) then
            freeActionButtonLocks[id] = position.locked == true
            local barId, buttonId = string.match(id, '^(%d+)%.(%d+)$')
            local source = actionBars[tonumber(barId)]
                and actionBars[tonumber(barId)].tabBar:getChildById(id)
            if source then
                createFreeActionButtonCopy(source, { x = tonumber(position.x) or 0, y = tonumber(position.y) or 0 })
            end
        end
    end
    clearSelectionWhenClickingAway()
end

function setFreeActionBarPlacement(enabled)
    for _, copy in pairs(freeActionButtonCopies) do
        if copy and not copy:isDestroyed() then
            copy:setVisible(enabled and true or false)
        end
    end
end

function getFreeActionBarButtonCopies()
    return freeActionButtonCopies
end

function onDragItemLeave(self, mousePos, button)
    if lastHighlightWidget then
        lastHighlightWidget:setBorderWidth(0)
        lastHighlightWidget:setBorderColor('alpha')
    end

    button.cache = getButtonCache(button)

    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)

    if clickedWidget and clickedWidget:getParent() then
        local parentId = clickedWidget:getParent():getId() or ""
        local targetIndex = tonumber(string.match(parentId, "^actionButton(%d)$"))
        if targetIndex and targetIndex >= 1 and targetIndex <= 3 then
            local panel = clickedWidget:getParent():getParent()
            if panel and panel.button then
                local targetButton = panel.button
                if panel.button == button then
                    resetDragWidget(self, button)
                    return true
                end
                local tBarID, tButtonID = string.match(targetButton:getId(), "(.*)%.(.*)")
                local sourceBarID, sourceButtonID = string.match(button:getId(), "(.*)%.(.*)")

                if hasMultiActions(button.cache.multiActions) then
                    targetButton.cache = getButtonCache(targetButton)
                    targetButton.cache.multiActions = {{}, {}, {}}
                    for i = 1, 3 do
                        local slotData = button.cache.multiActions[i] or {}
                        if not table.empty(slotData) then
                            targetButton.cache.multiActions[i] = table.copy(slotData)
                        end
                        persistMultiSlot(tonumber(tBarID), tonumber(tButtonID), i, slotData)
                    end
                elseif button.cache.actionType == UseTypes["chatText"] and button.cache.param and button.cache.param ~= "" then
                    ApiJson.createOrUpdateMultiText(tonumber(tBarID), tonumber(tButtonID), targetIndex,
                        button.cache.param, button.cache.sendAutomatic)
                    targetButton.cache = getButtonCache(targetButton)
                    targetButton.cache.multiActions = targetButton.cache.multiActions or {{}, {}, {}}
                    targetButton.cache.multiActions[targetIndex] = {
                        chatText = button.cache.param,
                        sendAutomatically = button.cache.sendAutomatic
                    }
                elseif button.cache.itemId and button.cache.itemId > 100 then
                    local useTypeName = resolveMultiUseType(button.cache.actionType)
                    ApiJson.createOrUpdateMultiAction(tonumber(tBarID), tonumber(tButtonID), targetIndex, useTypeName,
                        button.cache.itemId, button.cache.upgradeTier or 0, button.cache.smartMode or false)
                    targetButton.cache = getButtonCache(targetButton)
                    targetButton.cache.multiActions = targetButton.cache.multiActions or {{}, {}, {}}
                    targetButton.cache.multiActions[targetIndex] = {
                        useObject = button.cache.itemId,
                        useType = useTypeName,
                        upgradeTier = button.cache.upgradeTier or 0,
                        useEquipSmartMode = button.cache.smartMode or false
                    }
                else
                    resetDragWidget(self, button)
                    return true
                end

                if targetButton.multiIcon then
                    targetButton.multiIcon:setVisible(true)
                end
                if cacheMultiActionButtons then
                    cacheMultiActionButtons[targetButton] = true
                end

                ApiJson.removeAction(tonumber(sourceBarID), tonumber(sourceButtonID))

                if updateMultiButtonState then
                    updateMultiButtonState(targetButton)
                end
                if registerMultiActionCooldownEvents then
                    registerMultiActionCooldownEvents(targetButton)
                end
                if assignMultiAction and multiPanel and multiPanel.button == targetButton then
                    assignMultiAction(targetButton, true)
                end

                resetDragWidget(self, button)
                return true
            end
        end
    end

    if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
        if isFreeActionBarPlacementEnabled() then
            createFreeActionButtonCopy(button, { x = mousePos.x - 17, y = mousePos.y - 17 })
            resetDragWidget(self, button)
            return true
        end
        resetDragWidget(self, button)
        return true
    end

    local destButton = getButtonById(clickedWidget:getParent():getId())
    if not destButton then
        resetDragWidget(self, button)
        return true
    end

    -- Snapshot destination BEFORE updateButton mutates destButton.cache in place.
    -- Without this, swapping writes the moved item back into the source slot (duplicate).
    local destButtonCache = {
        actionType = destButton.cache and destButton.cache.actionType or 0,
        param = destButton.cache and destButton.cache.param or "",
        sendAutomatic = destButton.cache and destButton.cache.sendAutomatic or false,
        specialAction = destButton.cache and destButton.cache.specialAction or nil,
        itemId = destButton.cache and destButton.cache.itemId or 0,
        upgradeTier = destButton.cache and destButton.cache.upgradeTier or 0,
        isPassive = destButton.cache and destButton.cache.isPassive or false
    }

    button.cache = getButtonCache(button)
    local itemId = button.cache.itemId
    local destBarID, destButtonID = string.match(destButton:getId(), "(.*)%.(.*)")
    local draggedBarID, draggedButtonID = string.match(button:getId(), "(.*)%.(.*)")

    local sourceHasMulti = hasMultiActions(button.cache.multiActions)

    if sourceHasMulti then
        local destHasMulti = hasMultiActions(destButton.cache and destButton.cache.multiActions)
        if destHasMulti then
            resetDragWidget(self, button)
            return
        end
        local destHasSingleAction = (destButtonCache.actionType == UseTypes["chatText"] and
                                        destButtonCache.param and destButtonCache.param ~= "") or
                                        (destButtonCache.itemId and destButtonCache.itemId > 100)
        if destHasSingleAction then
            resetDragWidget(self, button)
            return true
        end

        for i = 1, 3 do
            persistMultiSlot(tonumber(destBarID), tonumber(destButtonID), i, button.cache.multiActions[i])
        end

        ApiJson.removeAction(tonumber(draggedBarID), tonumber(draggedButtonID))
        if cacheMultiActionButtons then
            cacheMultiActionButtons[button] = nil
        end
        if clearMultiActionCooldownEvents then
            clearMultiActionCooldownEvents(button:getId())
        end

        updateButton(destButton)
        resetDragWidget(self, button)
        self:setBorderColor('alpha')
        return
    end

    local cachedItem = cachedItemWidget[itemId]
    if cachedItem then
        for index, widget in pairs(cachedItem) do
            if button == widget then
                table.remove(cachedItem, index)
            end
        end
    end

    cachedItem = cachedItemWidget[destButtonCache.itemId]
    if cachedItem then
        for index, widget in pairs(cachedItem) do
            if destButton == widget then
                table.remove(cachedItem, index)
            end
        end
    end
    local isButtonEmpty = buttonIsEmpty(destButton)
    if button.cache.actionType == UseTypes["chatText"] then
        ApiJson.createOrUpdateText(tonumber(destBarID), tonumber(destButtonID), button.cache.param,
            button.cache.sendAutomatic)
    elseif button.cache.actionType == UseTypes["specialAction"] then
        ApiJson.createOrUpdateSpecialAction(tonumber(destBarID), tonumber(destButtonID), button.cache.specialAction)
    elseif itemId ~= 0 then
        ApiJson.createOrUpdateAction(tonumber(destBarID), tonumber(destButtonID),
            getActionName(button.cache.actionType), itemId, button.cache.upgradeTier)
    elseif button.cache.isPassive then
        ApiJson.createOrUpdatePassive(tonumber(destBarID), tonumber(destButtonID), 1)
    end
    updateButton(destButton)
    if isButtonEmpty then
        ApiJson.removeAction(tonumber(draggedBarID), tonumber(draggedButtonID))
        removeCooldown(destButton)
        resetDragWidget(self, button)
    else
        if destButtonCache.actionType == UseTypes["chatText"] then
            ApiJson.createOrUpdateText(tonumber(draggedBarID), tonumber(draggedButtonID), destButtonCache.param,
                destButtonCache.sendAutomatic)
        elseif destButtonCache.actionType == UseTypes["specialAction"] then
            ApiJson.createOrUpdateSpecialAction(tonumber(draggedBarID), tonumber(draggedButtonID),
                destButtonCache.specialAction)
        elseif destButtonCache.itemId ~= 0 then
            ApiJson.createOrUpdateAction(tonumber(draggedBarID), tonumber(draggedButtonID),
                getActionName(destButtonCache.actionType), destButtonCache.itemId, destButtonCache.upgradeTier)
        elseif destButtonCache.isPassive then
            ApiJson.createOrUpdatePassive(tonumber(draggedBarID), tonumber(draggedButtonID), 1)
        end

        removeCooldown(destButton)
        resetDragWidget(self, button)
    end
    self:setBorderColor('alpha')
end
