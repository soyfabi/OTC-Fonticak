local DETAIL_LABEL_COLUMN_WIDTH = 150
local DETAIL_VALUE_COLUMN_GAP = 7
local DETAIL_ROW_HEIGHT = 20
local detailMeasureLabel

local function measureDetailRowHeight(value, valueWidth)
    if not detailMeasureLabel then
        detailMeasureLabel = g_ui.createWidget("Label", g_ui.getRootWidget())
        detailMeasureLabel:setVisible(false)
        detailMeasureLabel:setPhantom(true)
    end
    detailMeasureLabel:setFont("Verdana Bold-11px")
    detailMeasureLabel:setTextAutoResize(false)
    detailMeasureLabel:setTextWrap(true)
    detailMeasureLabel:setWidth(valueWidth)
    detailMeasureLabel:setText(value or "")
    return math.max(DETAIL_ROW_HEIGHT, detailMeasureLabel:getTextSize().height + 2)
end

local function appendDetailRow(parent, key, value)
    local cyclopedia = modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia
    if cyclopedia and cyclopedia.appendDetailKeyValueRow then
        cyclopedia.appendDetailKeyValueRow(parent, key, value)
        return
    end
    local row = g_ui.createWidget("UIWidget", parent)
    row:setPhantom(true)
    local parentWidth = parent:getWidth() > 0 and parent:getWidth() or 425
    local valueWidth = parentWidth - DETAIL_LABEL_COLUMN_WIDTH - 8
    local rowHeight = measureDetailRowHeight(value, valueWidth)
    row:setWidth(parentWidth)
    row:setHeight(rowHeight)
    local keyLabel = g_ui.createWidget("Label", row)
    keyLabel:setText(key .. ":")
    keyLabel:setColor("#C0C0C0")
    keyLabel:setFont("Verdana Bold-11px")
    keyLabel:setTextAlign(AlignTopRight)
    keyLabel:setTextAutoResize(false)
    keyLabel:setWidth(DETAIL_LABEL_COLUMN_WIDTH)
    keyLabel:setHeight(rowHeight)
    keyLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
    keyLabel:addAnchor(AnchorTop, "parent", AnchorTop)
    local valueLabel = g_ui.createWidget("Label", row)
    valueLabel:setColor("#C0C0C0")
    valueLabel:setFont("Verdana Bold-11px")
    valueLabel:setTextAlign(AlignTopLeft)
    valueLabel:setTextAutoResize(false)
    valueLabel:setWidth(valueWidth)
    valueLabel:setHeight(rowHeight)
    valueLabel:setTextWrap(true)
    valueLabel:setText(value)
    valueLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
    valueLabel:addAnchor(AnchorTop, "parent", AnchorTop)
    valueLabel:setMarginLeft(DETAIL_LABEL_COLUMN_WIDTH + 8)
end

local function getDescriptionPair(data)
    if type(data) ~= "table" then
        return nil, nil
    end
    local key = data.key or data[1]
    local value = data.value or data[2]
    if key == nil or value == nil or value == "" then
        return nil, nil
    end
    return tostring(key), tostring(value)
end

local function normalizeCategoryLabel(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub(":%s*$", "")
end

local function isInspectDescriptionCategory(text)
    local label = normalizeCategoryLabel(text)
    if label == "" then
        return false
    end
    local lower = label:lower()
    if lower == "level" or lower == "vocation" or lower == "outfit" then
        return true
    end
    if lower:match("^active prey %d+$") then
        return true
    end
    if lower == "weight" or lower == "description" or lower == "tradeable" then
        return true
    end
    if lower:find("position", 1, true) then
        return true
    end
    if lower == "attack" or lower == "defence" or lower == "defense" or lower == "def" or lower == "armor" or lower == "protection" then
        return true
    end
    if lower == "tier" or lower:find("imbuement", 1, true) then
        return true
    end
    if lower == "capacity" or lower == "classification" or lower == "upgrade classification" then
        return true
    end
    if lower == "weapon type" or lower == "extra def" or lower == "charges" or lower == "duration" then
        return true
    end
    if lower == "range" or lower == "required level" or lower == "required magic level" or lower == "hit points" or lower == "hit chance" or lower == "magic level" or lower == "speed" or lower == "professions" then
        return true
    end
    if lower == "max hit points" or lower == "max mana points" or lower == "soul" or lower == "capacity" then
        return true
    end
    if lower:find("leech", 1, true) or lower:find("critical", 1, true) or lower == "skill bonus" then
        return true
    end
    if lower:match("^protection ") or lower:match("^elemental ") or lower:match("^skill ") or lower:match("^mana ") then
        return true
    end
    return false
end

local function looksLikeInspectDescriptionValue(text)
    text = normalizeCategoryLabel(text)
    if text == "" then
        return false
    end
    if text:match("^%-?%d+$") then
        return true
    end
    if text:match("^[%+%-]?%d") then
        return true
    end
    if text:lower() == "yes" or text:lower() == "no" then
        return true
    end
    if text:match("^[%a%-]+$") and text:lower() == text then
        return true
    end
    return false
end

local function getPlayerInspectDescriptionPair(data)
    if type(data) ~= "table" then
        return nil, nil
    end
    local wireKey = data.key or data[1]
    local wireValue = data.value or data[2]
    if wireKey == nil or wireValue == nil or wireValue == "" then
        return nil, nil
    end
    wireKey = tostring(wireKey)
    wireValue = tostring(wireValue)
    if isInspectDescriptionCategory(wireKey) then
        return wireKey, wireValue
    end
    if isInspectDescriptionCategory(wireValue) then
        return wireValue, wireKey
    end
    if looksLikeInspectDescriptionValue(wireKey) and not looksLikeInspectDescriptionValue(wireValue) then
        return wireValue, wireKey
    end
    return wireKey, wireValue
end

tibiaInspect = nil
tibiaInspectCharacter = nil

local inspectedItem, inspectedItemName, inspectedDescriptions, characterInspectData, characterInspectTargetId
local characterInspectPendingOpen = false
local characterInspectReturnData
local characterInventoryBySlot = {}
local characterPlayerDescriptions = {}
local characterInspectionOutfit, selectedCharacterSlot, selectedCharacterSlotWidget
local characterInfoItemSelected = false
local CHARACTER_BUTTON_ICON_OFFSET = {
    player = { idle = "0 0", pressed = "1 1" },
    outfit = { idle = "-1 0", pressed = "0 1" }
}
local INSPECT_SLOT_WIDGETS = {
    [InventorySlotHead] = "headSlot",
    [InventorySlotNeck] = "neckSlot",
    [InventorySlotBack] = "backSlot",
    [InventorySlotBody] = "bodySlot",
    [InventorySlotRight] = "rightSlot",
    [InventorySlotLeft] = "leftSlot",
    [InventorySlotLeg] = "legSlot",
    [InventorySlotFeet] = "feetSlot",
    [InventorySlotFinger] = "ringSlot",
    [InventorySlotAmmo] = "ammoSlot"
}

local function hideItemQuickLootIcon(itemWidget)
    if not itemWidget then return end
    local quicklootIcon = itemWidget:recursiveGetChildById("quickloot")
    if quicklootIcon then
        quicklootIcon:setVisible(false)
    end
end

local function isCharacterSelfInspect()
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then return false end
    if characterInspectTargetId and characterInspectTargetId == localPlayer:getId() then
        return true
    end
    if characterInspectData and characterInspectData.playerName then
        return characterInspectData.playerName:lower() == localPlayer:getName():lower()
    end
    return false
end

local function updateCharacterSelfInspectActions()
    if not tibiaInspectCharacter then return end
    local cyclopediaButton = tibiaInspectCharacter:recursiveGetChildById("cyclopediaButton")
    local proficiencyButton = tibiaInspectCharacter:recursiveGetChildById("proficiencyButton")
    local selfInspect = isCharacterSelfInspect()
    if cyclopediaButton then
        cyclopediaButton:setVisible(selfInspect)
    end
    local showProficiency = false
    if selfInspect and characterInfoItemSelected and selectedCharacterSlot then
        local cached = characterInventoryBySlot[selectedCharacterSlot]
        local item = cached and cached.item
        if item and item.getProficiencyId and item:getProficiencyId() > 0 then
            showProficiency = true
        end
    end
    if proficiencyButton then
        proficiencyButton:setVisible(showProficiency)
    end
end

local function isTierDetailKey(key)
    key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return key == "Tier" or key:match("^Tier:?%s*$") ~= nil
end

local function isImbuementSlotsDetailKey(key)
    return tostring(key or ""):find("Imbuement Slots", 1, true) ~= nil
end

local function isBodyPositionDetailKey(key)
    return tostring(key or ""):lower():find("body position", 1, true) ~= nil
end

local function isClassificationDetailKey(key)
    key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub(":%s*$", "")
    return key == "Classification" or key == "Upgrade Classification" or key:match("^Classification:?%s*$") ~= nil or key:match("^Upgrade Classification:?%s*$") ~= nil
end

local IMBUE_SLOT_BY_POSITION = { 1, 3, 2 }
local ITEM_INFO_WIDTH = 450
local ITEM_INFO_HEIGHT_DEFAULT = 299
local ITEM_INFO_HEIGHT_WITH_IMBUEMENT = 246

local function setCharacterInspectDetailLayout(withImbuements)
    if not tibiaInspectCharacter then return end
    local itemInfo = tibiaInspectCharacter:recursiveGetChildById("itemInfo")
    if itemInfo then
        itemInfo:setSize({
            width = ITEM_INFO_WIDTH,
            height = withImbuements and ITEM_INFO_HEIGHT_WITH_IMBUEMENT or ITEM_INFO_HEIGHT_DEFAULT
        })
    end
end

local function getCharacterSelectedItemTier()
    if not selectedCharacterSlot or not tibiaInspectCharacter then return 0 end
    local panel = tibiaInspectCharacter.contentPanel.equipmentPanel
    local slotWidget = panel and panel[INSPECT_SLOT_WIDGETS[selectedCharacterSlot]]
    local itemWidget = slotWidget and slotWidget:getChildById("equippedItem")
    local item = itemWidget and itemWidget:getItem()
    if not item or not item.getTier then return 0 end
    return item:getTier() or 0
end

local function buildPlayerDescriptionRows(descriptions)
    local cyclopedia = modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia
    local level, vocation, outfit
    local preyRows = {}
    for _, desc in ipairs(descriptions or {}) do
        local key, value = getPlayerInspectDescriptionPair(desc)
        if key and value and value ~= "" then
            if key == "Level" or key:match("^Level:?%s*$") then
                level = value
            elseif key == "Vocation" or key:match("^Vocation:?%s*$") then
                vocation = value
            elseif key == "Outfit" or key:match("^Outfit:?%s*$") then
                outfit = value
            elseif key:match("^Active Prey ") then
                local serverSlot = tonumber(key:match("Active Prey (%d+)"))
                preyRows[#preyRows + 1] = {
                    order = serverSlot or 0,
                    slot = serverSlot and serverSlot - 1 or 0,
                    value = value
                }
            end
        end
    end
    table.sort(preyRows, function(a, b) return a.order < b.order end)
    if cyclopedia and cyclopedia.buildCharacterDescriptionRowsFromParts then
        return cyclopedia.buildCharacterDescriptionRowsFromParts(level, vocation, preyRows, outfit)
    end
    local rows = {}
    if level and level ~= "" then
        rows[#rows + 1] = { tr("Level"), level }
    end
    if vocation and vocation ~= "" then
        rows[#rows + 1] = { tr("Vocation"), vocation }
    end
    for _, prey in ipairs(preyRows) do
        rows[#rows + 1] = { tr("Active Prey %d", prey.slot), prey.value }
    end
    if outfit then
        rows[#rows + 1] = { tr("Outfit"), outfit }
    end
    return rows
end

local function prepareCharacterItemDescriptionRows(descriptions)
    local rows = {}
    local hasClassification = false
    for _, description in ipairs(descriptions or {}) do
        local key, value = getPlayerInspectDescriptionPair(description)
        if key and not isTierDetailKey(key) and value ~= nil and value ~= "" then
            rows[#rows + 1] = { key, value }
            if isClassificationDetailKey(key) then
                hasClassification = true
            end
        end
    end
    if hasClassification then
        local tierRow = { tr("Tier"), tostring(getCharacterSelectedItemTier()) }
        local insertAt = #rows + 1
        for i, row in ipairs(rows) do
            if isBodyPositionDetailKey(row[1]) then
                insertAt = i
                break
            end
        end
        table.insert(rows, insertAt, tierRow)
    end
    return rows
end

local function hideCharacterInspectImbuements()
    if not tibiaInspectCharacter then return end
    for i = 1, 3 do
        local widget = tibiaInspectCharacter:recursiveGetChildById("imbuiSlot" .. i)
        if widget then
            widget:setVisible(false)
            local resource = widget:getChildById("resource")
            if resource then
                resource:setImageClip("0 0 64 64")
                resource:setImageSource("")
            end
        end
    end
    local inspectLabel = tibiaInspectCharacter:recursiveGetChildById("inspectLabel")
    if inspectLabel then
        inspectLabel:setWidth(450)
    end
    setCharacterInspectDetailLayout(false)
end

local function updateCharacterInspectImbuements(entry)
    hideCharacterInspectImbuements()
    if not entry then return end
    local imbuements = entry.imbuements or {}
    local imbuementCount = #imbuements
    if imbuementCount == 0 then return end
    setCharacterInspectDetailLayout(true)
    local inspectLabel = tibiaInspectCharacter:recursiveGetChildById("inspectLabel")
    if inspectLabel then
        if imbuementCount == 3 then
            inspectLabel:setWidth(170)
        elseif imbuementCount == 2 then
            inspectLabel:setWidth(240)
        elseif imbuementCount == 1 then
            inspectLabel:setWidth(315)
        end
    end
    local imbNames = {}
    for _, desc in ipairs(entry.descriptions or {}) do
        local key, value = getDescriptionPair(desc)
        if key and value then
            local slotNum = key:match("^Imbuement Slot (%d+)$")
            if slotNum then
                imbNames[tonumber(slotNum)] = value
            end
        end
    end
    for index, iconId in ipairs(imbuements) do
        local slotId = IMBUE_SLOT_BY_POSITION[3 - imbuementCount + index]
        if not slotId then break end
        local widget = tibiaInspectCharacter:recursiveGetChildById("imbuiSlot" .. slotId)
        if widget then
            widget:setVisible(true)
            local resource = widget:getChildById("resource")
            if resource then
                if iconId > 0 then
                    resource:setImageSource(InspectConst.SLOT_ACTIVE_SOURCE_PREFIX .. iconId)
                else
                    resource:setImageSource("")
                    resource:setImageClip("0 0 64 64")
                end
            end
            local name = imbNames[index]
            local tooltipText = (name and name ~= "(Empty Slot)") and name or tr("Empty Slot")
            function widget.onHoverChange(self, hovered)
                if hovered then
                    g_tooltip.display(tooltipText)
                else
                    g_tooltip.hide()
                end
            end
        end
    end
end

local function updateCharacterDetailScroll()
    local list = tibiaInspectCharacter and tibiaInspectCharacter:recursiveGetChildById("itemInfoList")
    if not list or list:isDestroyed() then return end
    addEvent(function()
        if list and not list:isDestroyed() then
            list:updateScrollBars()
        end
    end)
end

local function renderCharacterDetailRows(rows)
    local list = tibiaInspectCharacter and tibiaInspectCharacter:recursiveGetChildById("itemInfoList")
    if not list then return end
    list:destroyChildren()
    for _, row in ipairs(rows or {}) do
        appendDetailRow(list, row[1], row[2])
    end
    updateCharacterDetailScroll()
end

local function renderCharacterPlayerDetails()
    if not tibiaInspectCharacter or not characterInspectData then return end
    characterInfoItemSelected = false
    selectedCharacterSlot = nil
    selectedCharacterSlotWidget = nil
    local inspectLabel = tibiaInspectCharacter:recursiveGetChildById("inspectLabel")
    if inspectLabel then
        inspectLabel:setText(tr("You are inspecting:") .. " " .. (characterInspectData.playerName or ""))
    end
    hideCharacterInspectImbuements()
    renderCharacterDetailRows(buildPlayerDescriptionRows(characterPlayerDescriptions))
end

local function clearCharacterInventorySelection()
    if selectedCharacterSlotWidget and not selectedCharacterSlotWidget:isDestroyed() then
        selectedCharacterSlotWidget:setBorderWidth(0)
    end
    selectedCharacterSlotWidget = nil
    selectedCharacterSlot = nil
    characterInfoItemSelected = false
    updateCharacterSelfInspectActions()
end

local function setCharacterInventorySlotSelected(widget, selected)
    if not widget or widget:isDestroyed() then return end
    if selected then
        widget:setBorderWidth(1)
        widget:setBorderColor("#FFFFFF")
    else
        widget:setBorderWidth(0)
    end
end

local function refreshCharacterButtonIconOffset(widget, pressed)
    if not widget or widget:isDestroyed() then return end
    local mode = widget.state == 2 and "outfit" or "player"
    local offsetKey = pressed and "pressed" or "idle"
    widget:setIconOffset(topoint(CHARACTER_BUTTON_ICON_OFFSET[mode][offsetKey]))
end

local function bindCharacterButtonIcon(widget)
    if not widget or widget:isDestroyed() then return end
    refreshCharacterButtonIconOffset(widget, false)
    function widget:onMousePress(mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
            refreshCharacterButtonIconOffset(self, true)
        end
        return false
    end
    function widget:onMouseRelease(mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
            refreshCharacterButtonIconOffset(self, false)
        end
        return false
    end
end

local function applyCharacterOutfitPreview(spriteWidget)
    if not spriteWidget or spriteWidget:isDestroyed() then return end
    spriteWidget:setSize({ height = 192, width = 192 })
    spriteWidget:setCenter(true)
    spriteWidget:setFixedCreatureSize(true)
    spriteWidget:setBaseScale(true)
    spriteWidget:setIgnoreDisplacementShift(true)
end

local function setCharacterInspectionOutfit(outfit)
    if not outfit or (outfit.type or 0) == 0 then
        characterInspectionOutfit = nil
        return
    end
    characterInspectionOutfit = {
        familiar = 0, mount = 0,
        type = outfit.type, auxType = outfit.auxType or 0,
        head = outfit.head or 0, body = outfit.body or 0,
        legs = outfit.legs or 0, feet = outfit.feet or 0,
        addons = outfit.addons or 0
    }
end

local function applyCharacterOutfitWidget()
    if not tibiaInspectCharacter or not characterInspectionOutfit then return end
    local sprite = tibiaInspectCharacter.contentPanel.outfitPanel and tibiaInspectCharacter.contentPanel.outfitPanel.Sprite
    if sprite then
        sprite:setOutfit(characterInspectionOutfit)
        applyCharacterOutfitPreview(sprite)
    end
end

local function setInspectEquipmentSlot(slot, entry)
    if not tibiaInspectCharacter then return end
    local panel = tibiaInspectCharacter.contentPanel.equipmentPanel
    local widgetId = INSPECT_SLOT_WIDGETS[slot]
    local slotWidget = widgetId and panel and panel[widgetId]
    if not slotWidget then return end
    local slotIcon = slotWidget:getChildById("slotIcon")
    local itemWidget = slotWidget:getChildById("equippedItem")
    if entry and entry.item then
        if slotIcon then slotIcon:setVisible(false) end
        if itemWidget then
            itemWidget:setVisible(true)
            itemWidget:setItem(entry.item)
            hideItemQuickLootIcon(itemWidget)
            if ItemsDatabase and ItemsDatabase.setTier and entry.item.getTier then
                ItemsDatabase.setTier(itemWidget, entry.item:getTier() or 0)
            end
        end
    else
        if slotIcon then slotIcon:setVisible(true) end
        if itemWidget then
            itemWidget:setItem(nil)
            if ItemsDatabase and ItemsDatabase.setTier then
                ItemsDatabase.setTier(itemWidget, 0)
            end
        end
    end
end

local function clearInspectEquipmentSlots()
    for slot = InventorySlotFirst, InventorySlotLast do
        setInspectEquipmentSlot(slot, nil)
    end
end

local function onCharacterInventorySlotClick(slot, widget)
    if not tibiaInspectCharacter or not tibiaInspectCharacter:isVisible() then return end
    local itemWidget = widget:getChildById("equippedItem")
    local item = itemWidget and itemWidget:getItem()
    if not item then
        clearCharacterInventorySelection()
        renderCharacterPlayerDetails()
        return
    end
    if selectedCharacterSlot == slot then
        clearCharacterInventorySelection()
        renderCharacterPlayerDetails()
        return
    end
    clearCharacterInventorySelection()
    selectedCharacterSlot = slot
    selectedCharacterSlotWidget = widget
    characterInfoItemSelected = true
    setCharacterInventorySlotSelected(widget, true)
    local cached = characterInventoryBySlot[slot]
    local itemName = cached and cached.name or item:getName()
    local inspectLabel = tibiaInspectCharacter:recursiveGetChildById("inspectLabel")
    if itemName and itemName ~= "" and inspectLabel then
        inspectLabel:setText(tr("You are inspecting:") .. " " .. itemName)
    end
    if cached then
        updateCharacterInspectImbuements(cached)
        if cached.descriptions and #cached.descriptions > 0 then
            renderCharacterDetailRows(prepareCharacterItemDescriptionRows(cached.descriptions))
        else
            renderCharacterDetailRows({})
        end
    else
        hideCharacterInspectImbuements()
        renderCharacterDetailRows({})
    end
    updateCharacterSelfInspectActions()
end

local function bindCharacterInventorySlots()
    if not tibiaInspectCharacter then return end
    local panel = tibiaInspectCharacter.contentPanel.equipmentPanel
    if not panel then return end
    for slot, widgetId in pairs(INSPECT_SLOT_WIDGETS) do
        local slotWidget = panel[widgetId]
        if slotWidget then
            function slotWidget.onMouseRelease(widget, mousePos, mouseButton)
                if mouseButton == MouseLeftButton then
                    onCharacterInventorySlotClick(slot, widget)
                end
                return false
            end
        end
    end
end

local function populateCharacterInspect(data)
    characterInspectData = data
    characterInventoryBySlot = {}
    characterPlayerDescriptions = data.playerDescriptions or {}
    if data.inventoryItems then
        for _, entry in ipairs(data.inventoryItems) do
            if entry.slot ~= nil then
                characterInventoryBySlot[entry.slot] = entry
            end
        end
    end
    setCharacterInspectionOutfit(data.outfit)
    applyCharacterOutfitWidget()
    clearInspectEquipmentSlots()
    for slot = InventorySlotFirst, InventorySlotLast do
        setInspectEquipmentSlot(slot, characterInventoryBySlot[slot])
    end
    bindCharacterInventorySlots()
    renderCharacterPlayerDetails()
    local playerName = data.playerName or ""
    tibiaInspectCharacter:setText(tr("Inspect Character %s", playerName))
    local characterButton = tibiaInspectCharacter:recursiveGetChildById("characterButton")
    if characterButton then
        characterButton.state = 1
        characterButton:setIcon("/game_cyclopedia/images/icon-playerdetails")
        characterButton:setTooltip(tr("Show character outfit"))
        bindCharacterButtonIcon(characterButton)
    end
    tibiaInspectCharacter.contentPanel.equipmentPanel:setVisible(true)
    tibiaInspectCharacter.contentPanel.outfitPanel:setVisible(false)
    updateCharacterSelfInspectActions()
end

local function buildCharacterInspectCopyText()
    local inspectName = characterInspectData and characterInspectData.playerName or ""
    if characterInfoItemSelected and selectedCharacterSlot then
        local cached = characterInventoryBySlot[selectedCharacterSlot]
        if cached and cached.name and cached.name ~= "" then
            inspectName = cached.name
        end
    end
    local lines = { string.format("You are inspecting: %s", inspectName) }
    if characterInfoItemSelected and selectedCharacterSlot then
        local cached = characterInventoryBySlot[selectedCharacterSlot]
        if cached and cached.descriptions then
            for _, row in ipairs(prepareCharacterItemDescriptionRows(cached.descriptions)) do
                lines[#lines + 1] = string.format("%s: %s", row[1], row[2])
            end
        end
    else
        for _, row in ipairs(buildPlayerDescriptionRows(characterPlayerDescriptions)) do
            lines[#lines + 1] = string.format("%s: %s", row[1], row[2])
        end
    end
    return table.concat(lines, "\n")
end

function copyCharacterInfo()
    if not g_window or not g_window.setClipboardText then return end
    local text = buildCharacterInspectCopyText()
    if text and text ~= "" then
        g_window.setClipboardText(text)
    end
end

function setInspectTargetId(creatureId)
    characterInspectTargetId = creatureId
end

function beginCharacterInspectRequest(creatureId)
    characterInspectTargetId = creatureId
    characterInspectPendingOpen = true
end

local function hideCharacterForWheel()
    if not tibiaInspectCharacter then return end
    characterInspectReturnData = {
        data = characterInspectData,
        targetId = characterInspectTargetId
    }
    hideCharacterInspectImbuements()
    if g_modalManager then
        g_modalManager.hide(tibiaInspectCharacter)
    end
    tibiaInspectCharacter:hide()
    clearCharacterInventorySelection()
end

function openSelfInspectCyclopedia()
    if not isCharacterSelfInspect() then return end
    hideCharacter()
    if modules.game_cyclopedia and modules.game_cyclopedia.show then
        modules.game_cyclopedia.show("character")
    end
end

function openSelfInspectProficiency()
    if not isCharacterSelfInspect() or not selectedCharacterSlot then return end
    local cached = characterInventoryBySlot[selectedCharacterSlot]
    local item = cached and cached.item
    if not item then return end
    local proficiencyId = item.getProficiencyId and item:getProficiencyId() or 0
    if proficiencyId <= 0 then return end
    hideCharacterForWheel()
    local proficiencyMod = modules.game_proficiency
    if proficiencyMod and proficiencyMod.requestOpenWindow then
        proficiencyMod.requestOpenWindow(item)
    end
end

function openInspectCharacterWheel()
    if not g_game.isOnline() then return end
    local targetId = characterInspectTargetId
    if not targetId then return end
    hideCharacterForWheel()
    if modules.game_wheel and modules.game_wheel.openForPlayer then
        modules.game_wheel.openForPlayer(targetId)
    elseif g_game.openWheel then
        g_game.openWheel(targetId)
    end
end

function toggleCharacterView(widget)
    if not tibiaInspectCharacter or not widget then return end
    if widget.state == 1 then
        widget.state = 2
        widget:setIcon("/game_cyclopedia/images/icon-equipmentdetails")
        widget:setTooltip(tr("Show equipment"))
        refreshCharacterButtonIconOffset(widget, false)
        clearCharacterInventorySelection()
        hideCharacterInspectImbuements()
        renderCharacterPlayerDetails()
        tibiaInspectCharacter.contentPanel.equipmentPanel:setVisible(false)
        tibiaInspectCharacter.contentPanel.outfitPanel:setVisible(true)
        applyCharacterOutfitWidget()
    else
        widget.state = 1
        widget:setIcon("/game_cyclopedia/images/icon-playerdetails")
        widget:setTooltip(tr("Show character outfit"))
        refreshCharacterButtonIconOffset(widget, false)
        tibiaInspectCharacter.contentPanel.equipmentPanel:setVisible(true)
        tibiaInspectCharacter.contentPanel.outfitPanel:setVisible(false)
        bindCharacterInventorySlots()
    end
end

function hideCharacter()
    if not tibiaInspectCharacter then return end
    hideCharacterInspectImbuements()
    if g_modalManager then
        g_modalManager.hide(tibiaInspectCharacter)
    end
    tibiaInspectCharacter:hide()
    characterInspectData = nil
    characterInspectTargetId = nil
    characterInspectPendingOpen = false
    characterInspectReturnData = nil
    characterInventoryBySlot = {}
    characterPlayerDescriptions = {}
    characterInspectionOutfit = nil
    clearCharacterInventorySelection()
end

function returnToCharacterInspect()
    if not characterInspectReturnData or not characterInspectReturnData.data then return false end
    local snapshot = characterInspectReturnData
    characterInspectReturnData = nil
    showCharacter(snapshot.data)
    if snapshot.targetId then
        characterInspectTargetId = snapshot.targetId
    end
    return true
end

function showCharacter(data)
    if not tibiaInspectCharacter or not data then return end
    hide()
    populateCharacterInspect(data)
    tibiaInspectCharacter:show(true)
    if g_modalManager then
        g_modalManager.show(tibiaInspectCharacter)
    end
    tibiaInspectCharacter:raise()
    tibiaInspectCharacter:focus()
end

local function onParseCyclopediaCharacterInspection(data)
    if not data or not data.playerName then return end
    if not characterInspectPendingOpen then return end
    characterInspectPendingOpen = false
    showCharacter(data)
end

local function hideAll()
    hide()
    hideCharacter()
end

local function buildInspectCopyText()
    local lines = { string.format("You are inspecting: %s", inspectedItemName or "") }
    for _, data in ipairs(inspectedDescriptions or {}) do
        local key, value = getDescriptionPair(data)
        if key and value then
            lines[#lines + 1] = string.format("%s: %s", key, value)
        end
    end
    return table.concat(lines, "\n")
end

function copyInfo()
    if not g_window or not g_window.setClipboardText then return end
    local text = buildInspectCopyText()
    if text and text ~= "" then
        g_window.setClipboardText(text)
    end
end

function openProficiency()
    if not inspectedItem then return end
    local proficiencyMod = modules.game_proficiency
    if not proficiencyMod or not proficiencyMod.requestOpenWindow then return end
    local item = inspectedItem
    hide()
    proficiencyMod.requestOpenWindow(item)
end

local function normalizeItem(item)
    return type(item) == "number" and Item and Item.create and Item.create(item) or item
end

local function onParseItemDetailHandler(data)
    if type(data) ~= "table" then return end
    local item = normalizeItem(data.item or data.itemId)
    onInspection(data.inspectionType or 0, data.itemName or data.name or "", item,
        data.descriptions or {}, data.imbuements or {})
end

function init()
    tibiaInspect = g_ui.displayUI("styles/inspectItem")
    if not tibiaInspect then
        g_logger.error("[game_inspect] failed to load styles/inspectItem.otui")
        return
    end
    hide()
    tibiaInspectCharacter = g_ui.displayUI("styles/inspectCharacter")
    if not tibiaInspectCharacter then
        g_logger.error("[game_inspect] failed to load styles/inspectCharacter.otui")
        return
    end
    hideCharacter()

    local function bindInstantTooltip(widget, text)
        function widget.onHoverChange(self, hovered)
            if hovered then
                g_tooltip.display(text)
            else
                g_tooltip.hide()
            end
        end
    end
    bindInstantTooltip(tibiaInspect:recursiveGetChildById("copyInfo"), tr("Copy information to clipboard"))
    bindInstantTooltip(tibiaInspectCharacter:recursiveGetChildById("copyInfo"), tr("Copy information to clipboard"))

    connect(g_game, {
        onParseItemDetail = onParseItemDetailHandler,
        onParseCharacterInspection = onParseCyclopediaCharacterInspection,
        onParseCyclopediaCharacterInspection = onParseCyclopediaCharacterInspection,
        onGameStart = hideAll,
        onGameEnd = hideAll
    })
end

function terminate()
    if tibiaInspect then
        tibiaInspect:destroy()
        tibiaInspect = nil
    end
    if tibiaInspectCharacter then
        tibiaInspectCharacter:destroy()
        tibiaInspectCharacter = nil
    end
    disconnect(g_game, {
        onParseItemDetail = onParseItemDetailHandler,
        onParseCharacterInspection = onParseCyclopediaCharacterInspection,
        onParseCyclopediaCharacterInspection = onParseCyclopediaCharacterInspection,
        onGameStart = hideAll,
        onGameEnd = hideAll
    })
end

function toggle()
    if tibiaInspect:isVisible() then
        hide()
    else
        show()
    end
end

function hide()
    if not tibiaInspect then return end
    if g_modalManager then
        g_modalManager.hide(tibiaInspect)
    end
    tibiaInspect:hide()
    inspectedItem = nil
    inspectedItemName = nil
    inspectedDescriptions = nil
end

function show()
    if not tibiaInspect then return end
    tibiaInspect:show(true)
    if g_modalManager then
        g_modalManager.show(tibiaInspect)
    end
    tibiaInspect:raise()
    tibiaInspect:focus()
end

function onInspection(inspectType, itemName, item, descriptions, imbuements)
    if not item then
        g_logger.warning("[game_inspect] onInspection without item")
        return
    end
    imbuements = imbuements or {}
    descriptions = descriptions or {}
    hideCharacter()
    show()
    inspectedItem = item
    inspectedItemName = itemName or ""
    inspectedDescriptions = descriptions
    local proficiencyButton = tibiaInspect:recursiveGetChildById("proficiencyButton")
    if proficiencyButton then
        local proficiencyId = item.getProficiencyId and item:getProficiencyId() or 0
        proficiencyButton:setVisible(proficiencyId > 0)
    end
    local imbuementCount = #imbuements
    if imbuementCount == 3 then
        tibiaInspect.contentPanel.name:setWidth(170)
    elseif imbuementCount == 2 then
        tibiaInspect.contentPanel.name:setWidth(240)
    elseif imbuementCount == 1 then
        tibiaInspect.contentPanel.name:setWidth(315)
    else
        tibiaInspect.contentPanel.name:setWidth(380)
    end
    tibiaInspect.contentPanel.item:setItemId(item:getId())
    hideItemQuickLootIcon(tibiaInspect.contentPanel.item)
    local displayItem = tibiaInspect.contentPanel.item:getItem()
    if displayItem and item.getTier then
        displayItem:setTier(item:getTier())
    end
    tibiaInspect.contentPanel.name:setText(tr("You are inspecting:") .. " " .. (itemName or ""))
    for i = 1, 3 do
        local widget = tibiaInspect:recursiveGetChildById("imbuiSlot" .. i)
        if widget then
            widget:setVisible(false)
            local resource = widget:getChildById("resource")
            if resource then
                resource:setImageClip("0 0 64 64")
                resource:setImageSource("")
            end
        end
    end
    local slotCount = #imbuements

    local imbNames = {}
    for _, desc in ipairs(descriptions) do
        local key, value = getDescriptionPair(desc)
        if key and value then
            local slotNum = key:match("^Imbuement Slot (%d+)$")
            if slotNum then
                imbNames[tonumber(slotNum)] = value
            end
        end
    end

    for index, iconId in ipairs(imbuements) do
        local actualSlot = IMBUE_SLOT_BY_POSITION[3 - slotCount + index]
        if not actualSlot then break end
        local widget = tibiaInspect:recursiveGetChildById("imbuiSlot" .. actualSlot)
        if widget then
            widget:setVisible(true)
            if iconId > 0 then
                local resource = widget:getChildById("resource")
                if resource then
                    resource:setImageSource(InspectConst.SLOT_ACTIVE_SOURCE_PREFIX .. iconId)
                end
            end
            local name = imbNames[index]
            local tooltipText = (name and name ~= "(Empty Slot)") and name or tr("Empty Slot")
            function widget.onHoverChange(self, hovered)
                if hovered then
                    g_tooltip.display(tooltipText)
                else
                    g_tooltip.hide()
                end
            end
        end
    end
    local list = tibiaInspect:recursiveGetChildById("itemInfoList")
    if not list then
        g_logger.warning("[game_inspect] itemInfoList not found")
        return
    end
    list:destroyChildren()
    for _, data in ipairs(descriptions) do
        local key, value = getDescriptionPair(data)
        if key and value then
            appendDetailRow(list, key, value)
        end
    end
    addEvent(function()
        if list and not list:isDestroyed() then
            list:updateScrollBars()
        end
    end)
end
