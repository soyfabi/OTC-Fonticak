ItemsDatabase = {}

ItemsDatabase.serverValues = ItemsDatabase.serverValues or {}
ItemsDatabase.serverNpcSaleData = ItemsDatabase.serverNpcSaleData or {}

local OPCODE_ITEM_VALUES = 0xC6
local OPCODE_ITEM_DETAILS = 0xC7

ItemsDatabase.rarityColors = {
    ["yellow"] = TextColors.lootYellow,
    ["purple"] = TextColors.lootPurple,
    ["blue"] = TextColors.lootBlue,
    ["green"] = TextColors.lootGreen,
    ["grey"] = TextColors.grey,
}

local function resolveItemId(item)
    if type(item) == 'number' then
        return item
    end
    if not item then
        return 0
    end
    if item.getId then
        return item:getId() or 0
    end
    if item.getServerId then
        return item:getServerId() or 0
    end
    return 0
end

local function usesCustomItemValueProtocol()
    if not g_game.getFeature(GameColorizedLootValue) then
        return false
    end

    local version = g_game.getClientVersion()
    -- 0xC6/0xC7 are custom item-value opcodes on 8.60 servers only.
    -- On 12.x+ the same opcodes are native cyclopedia house packets.
    return version >= 860 and version < 1200
end

function ItemsDatabase.getItemValue(item)
    local itemId = resolveItemId(item)
    if itemId <= 0 then
        return 0
    end
    return tonumber(ItemsDatabase.serverValues[itemId]) or 0
end

function ItemsDatabase.registerServerItemValue(itemId, value)
    itemId = tonumber(itemId) or 0
    value = tonumber(value) or 0
    if itemId <= 0 or value <= 0 then
        return
    end
    ItemsDatabase.serverValues[itemId] = value
end

function ItemsDatabase.clearServerItemValues()
    ItemsDatabase.serverValues = {}
    ItemsDatabase.serverNpcSaleData = {}
end

function ItemsDatabase.registerServerNpcSaleData(itemId, npcSaleData)
    itemId = tonumber(itemId) or 0
    if itemId <= 0 or type(npcSaleData) ~= 'table' then
        return
    end
    ItemsDatabase.serverNpcSaleData[itemId] = npcSaleData
end

local function getDatNpcSaleData(itemId)
    itemId = tonumber(itemId) or 0
    if itemId <= 0 then
        return {}
    end

    local thingType = g_things.getThingType(itemId, ThingCategoryItem)
    if thingType and thingType.getNpcSaleData then
        local success, npcSaleData = pcall(function()
            return thingType:getNpcSaleData()
        end)
        if success and npcSaleData then
            return npcSaleData
        end
    end
    return {}
end

local function enrichNpcSaleLocations(serverData, datData)
    if not serverData or #serverData == 0 then
        return serverData
    end

    local locationByName = {}
    for _, entry in ipairs(datData or {}) do
        if entry and entry.name and entry.location and entry.location ~= '' then
            locationByName[entry.name:lower()] = entry.location
        end
    end

    if not next(locationByName) then
        return serverData
    end

    for _, entry in ipairs(serverData) do
        if entry and entry.name then
            local location = entry.location
            if not location or location == '' or location == 'Unknown Location' then
                entry.location = locationByName[entry.name:lower()] or location
            end
        end
    end

    return serverData
end

function ItemsDatabase.getNpcSaleData(itemOrId)
    local itemId = resolveItemId(itemOrId)
    if itemId <= 0 then
        return {}
    end

    local serverData = ItemsDatabase.serverNpcSaleData[itemId]
    if serverData and #serverData > 0 then
        return enrichNpcSaleLocations(serverData, getDatNpcSaleData(itemId))
    end

    if type(itemOrId) ~= 'number' and itemOrId and itemOrId.getNpcSaleData then
        local success, npcSaleData = pcall(function()
            return itemOrId:getNpcSaleData()
        end)
        if success and npcSaleData and #npcSaleData > 0 then
            return npcSaleData
        end
    end

    return getDatNpcSaleData(itemId)
end

function ItemsDatabase.requestServerItemDetails(itemId)
    if not usesCustomItemValueProtocol() or not g_game.isOnline() then
        return false
    end

    itemId = tonumber(itemId) or 0
    if itemId <= 0 then
        return false
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return false
    end

    local msg = OutputMessage.create()
    msg:addU8(OPCODE_ITEM_DETAILS)
    msg:addU16(itemId)
    protocol:send(msg)
    return true
end

local function getCyclopediaItemLootValue(itemId)
    if not itemId or itemId <= 0 then
        return 0
    end

    local itemsApi = Cyclopedia and Cyclopedia.Items
        or (modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia and modules.game_cyclopedia.Cyclopedia.Items)

    if itemsApi and itemsApi.getCurrentItemValue then
        return tonumber(itemsApi.getCurrentItemValue(itemId)) or 0
    end

    return 0
end

function ItemsDatabase.getItemPrice(item)
    local itemId = resolveItemId(item)
    if itemId > 0 then
        local cyclopediaValue = getCyclopediaItemLootValue(itemId)
        if cyclopediaValue > 0 then
            return cyclopediaValue
        end
    end

    local value = ItemsDatabase.getItemValue(item)
    if value > 0 then
        return value
    end

    if type(item) == 'number' then
        local thingType = g_things.getThingType(item, ThingCategoryItem)
        if thingType and thingType.getMeanPrice then
            return thingType:getMeanPrice() or 0
        end
        return 0
    end

    if item and item.getMeanPrice then
        return item:getMeanPrice() or 0
    end

    return 0
end

local function getColorForValue(value)
    if value >= 1000000 then
        return "yellow"
    elseif value >= 100000 then
        return "purple"
    elseif value >= 10000 then
        return "blue"
    elseif value >= 1000 then
        return "green"
    elseif value >= 50 then
        return "grey"
    else
        return "white"
    end
end

local function clipfunction(value)
    if value >= 1000000 then
        return "128 0 32 32"
    elseif value >= 100000 then
        return "96 0 32 32"
    elseif value >= 10000 then
        return "64 0 32 32"
    elseif value >= 1000 then
        return "32 0 32 32"
    elseif value >= 50 then
        return "0 0 32 32"
    end
    return ""
end

function ItemsDatabase.getClipAndImagePath(item)
    if not item then
        return nil, nil, nil
    end

    local frameOption = modules.client_options.getOption('framesRarity')
    if frameOption == "none" then
        return nil, nil, nil
    end
    local imagePath = '/images/ui/item'
    local clip = nil

    if type(item) == "number" then
        local thingType = g_things.getThingType(item, ThingCategoryItem)
        if thingType and thingType.getId and thingType:getId() == item then
            item = thingType
        else
            return nil, nil, nil
        end
    end

    if not item then
        return nil, nil, nil
    end

    if item then
        local price = ItemsDatabase.getItemPrice(item)
        local itemRarity = getColorForValue(price)
        if itemRarity then
            clip = clipfunction(price)
            if clip ~= "" then
                if frameOption == "frames" then
                    imagePath = "/images/ui/rarity_frames"
                elseif frameOption == "corners" then
                    imagePath = "/images/ui/containerslot-coloredges"
                end
            else
                clip = nil
            end
        end
    end

    local clipObject = nil
    if clip then
        local x, y, w, h = clip:match("(%d+) (%d+) (%d+) (%d+)")
        clipObject = { x = tonumber(x), y = tonumber(y), width = tonumber(w), height = tonumber(h) }
    end

    return clip, imagePath, clipObject
end

local function applyRarityToWidget(widget, price, style)
    if not widget then
        return
    end

    if not g_game.getFeature(GameColorizedLootValue) or not price or price <= 0 then
        widget:setImageClip(torect("0 0 0 0"))
        widget:setImageSource('/images/ui/item')
        if style then
            widget:setStyle(style)
        end
        return
    end

    local frameOption = modules.client_options.getOption('framesRarity')
    if frameOption == "none" then
        widget:setImageClip(torect("0 0 0 0"))
        widget:setImageSource('/images/ui/item')
        if style then
            widget:setStyle(style)
        end
        return
    end

    local clip = clipfunction(price)
    local imagePath = '/images/ui/item'
    if clip ~= "" then
        if frameOption == "frames" then
            imagePath = "/images/ui/rarity_frames"
        elseif frameOption == "corners" then
            imagePath = "/images/ui/containerslot-coloredges"
        end
    else
        clip = nil
    end

    if not clip then
        widget:setImageClip(torect("0 0 0 0"))
        widget:setImageSource('/images/ui/item')
        if style then
            widget:setStyle(style)
        end
        return
    end

    widget:setImageClip(torect(clip))
    widget:setImageSource(imagePath)
    if style then
        widget:setStyle(style)
    end
end

function ItemsDatabase.syncRarityWidgetVisibility(rarityWidget)
    if not rarityWidget then
        return
    end

    local imageSource = rarityWidget:getImageSource()

    rarityWidget:setVisible(imageSource and imageSource ~= "" and imageSource ~= "/images/ui/item")
end

local function resolveSlotRarityWidget(slotWidget)
    if slotWidget.rarity and slotWidget.rarity.getClassName then
        return slotWidget.rarity
    end

    return slotWidget:getChildById("rarity")
end

local function resolveSlotItemWidget(slotWidget)
    local itemUi = slotWidget:getChildById("item")

    if itemUi then
        return itemUi
    end

    if slotWidget.item and slotWidget.item.getClassName then
        return slotWidget.item
    end

    return nil
end

function ItemsDatabase.applyContainerRarityStackOrder(slotWidget, extraOverlayIds)
    if not slotWidget then
        return
    end

    local rarity = resolveSlotRarityWidget(slotWidget)
    local itemUi = resolveSlotItemWidget(slotWidget)

    if not rarity or not itemUi or itemUi:getClassName() ~= "UIItem" then
        return
    end

    local frameOption = modules.client_options and modules.client_options.getOption("framesRarity") or "frames"
    local hasItemSlot = slotWidget.itemSlot ~= nil
    local rarityIndex = hasItemSlot and 2 or 1
    local itemIndex = hasItemSlot and 3 or 2

    if frameOption == "corners" then
        rarityIndex = hasItemSlot and 3 or 2
        itemIndex = hasItemSlot and 2 or 1
    end

    if slotWidget.itemSlot then
        slotWidget:moveChildToIndex(slotWidget.itemSlot, 1)
    end

    slotWidget:moveChildToIndex(rarity, rarityIndex)
    slotWidget:moveChildToIndex(itemUi, itemIndex)

    local overlayIds = {
        "tier",
        "amount",
        "charges",
        "duration",
        "quickloot",
        "boxed"
    }

    if extraOverlayIds then
        for _, id in ipairs(extraOverlayIds) do
            table.insert(overlayIds, id)
        end
    end

    local overlayIndex = itemIndex + 1

    for _, id in ipairs(overlayIds) do
        local overlay = slotWidget[id]

        if overlay then
            slotWidget:moveChildToIndex(overlay, overlayIndex)

            overlayIndex = overlayIndex + 1
        end
    end
end

function ItemsDatabase.setRarityItem(widget, item, style)
    if not item then
        applyRarityToWidget(widget, 0, style)
        return
    end

    applyRarityToWidget(widget, ItemsDatabase.getItemPrice(item), style)
end

function ItemsDatabase.setRarityItemByPrice(widget, price, style)
    applyRarityToWidget(widget, tonumber(price) or 0, style)
end

function ItemsDatabase.getColorForRarity(rarity)
    return ItemsDatabase.rarityColors[rarity] or TextColors.white
end

function ItemsDatabase.applyLootRarityHighlight(widget, enabled)
    if widget and widget.setLootRarityHighlight then
        widget:setLootRarityHighlight(enabled == true)
    end
end

function ItemsDatabase.setColorLootMessage(text, defaultColor)
    if type(text) ~= 'string' then
        return text
    end

    -- CIP loot messages use green as the base color; rarity only recolors item names.
    if text:find('Loot of ') or text:find('Loot de ') then
        defaultColor = TextColors.green
    else
        defaultColor = defaultColor or TextColors.white
    end

    local function coloringLootName(match)
        -- Server formats: {itemId:value|name} (TFS/Astra) or {itemId|name} (CrystalServer)
        local itemId, inlineValue, itemName = match:match('^(%d+):(%d+)|(.+)$')
        if not itemId then
            itemId, itemName = match:match('^(%d+)|(.+)$')
        end
        if not itemId or not itemName then
            return "{" .. match .. "}"
        end

        itemId = tonumber(itemId)
        if not itemId then
            return "{" .. (itemName or match) .. ", " .. defaultColor .. "}"
        end

        local itemValue = tonumber(inlineValue) or 0
        if itemValue <= 0 then
            itemValue = ItemsDatabase.getItemPrice(itemId)
        end

        if itemValue > 0 then
            local color = ItemsDatabase.getColorForRarity(getColorForValue(itemValue))
            return "{" .. itemName .. ", " .. color .. "}"
        end

        return "{" .. itemName .. ", " .. defaultColor .. "}"
    end

    local colored = text:gsub("{(.-)}", coloringLootName)
    local firstBrace = colored:find('{', 1, true)
    if firstBrace and firstBrace > 1 then
        local prefix = colored:sub(1, firstBrace - 1)
        if prefix ~= '' and not prefix:find('{', 1, true) then
            colored = string.format('{%s, %s}%s', prefix, defaultColor, colored:sub(firstBrace))
        end
    end
    return colored
end

function ItemsDatabase.getTierClip(tier)
    local xOffset = (math.min(math.max(tier, 1), 10) - 1) * 9
    return {
        x = xOffset,
        y = 0,
        width = 10,
        height = 9
    }
end

function ItemsDatabase.setTier(widget, item, isSmall)
    if not g_game.getFeature(GameThingUpgradeClassification) or not widget or not widget.tier then
        return
    end
    if isSmall == nil then
        isSmall = true
    end
    local tier = type(item) == "number" and item or (item and item:getTier()) or 0
    if tier <= 0 then
        widget.tier:setVisible(false)
        return
    end
    local config
    if isSmall then
        local normalizedTier = math.min(math.max(tier, 1), 10)
        config = {
            xOffset = (normalizedTier - 1) * 9,
            width = 10,
            height = 9,
            size = "10 9",
            source = '/images/inventory/tiers-strip'
        }
    else
        local normalizedTier = math.min(math.max(tier, 1), 18)
        local xOffset = (normalizedTier - 1) * 18 + 1
        config = {
            xOffset = xOffset,
            width = 18,
            height = 16,
            size = "18 16",
            source = '/images/inventory/tiers-strip-big'
        }
    end

    widget.tier:setImageClip({
        x = config.xOffset,
        y = 0,
        width = config.width,
        height = config.height
    })
    widget.tier:setSize(config.size)
    widget.tier:setImageSource(config.source)
    widget.tier:setImageSize(config.size)
    widget.tier:setVisible(true)
end

function ItemsDatabase.applyExpiryDisplay(itemWidget, optionKey)
    if not itemWidget then
        return
    end

    local show = modules.client_options.getOption(optionKey)
    itemWidget:setShowDuration((g_game.getFeature(GameDisplayItemDuration) or g_game.getFeature(GameThingClock)) and show)
    itemWidget:setShowCharges((g_game.getFeature(GameDisplayItemCharges) or g_game.getFeature(GameThingCounter)) and show)
end

local function onItemValuesOpcode(_, msg)
    if not usesCustomItemValueProtocol() then
        return false
    end

    local count = msg:getU16()
    for _ = 1, count do
        local itemId = msg:getU16()
        local value = msg:getU32()
        ItemsDatabase.registerServerItemValue(itemId, value)
    end
    return true
end

local function onItemDetailsOpcode(_, msg)
    if not usesCustomItemValueProtocol() then
        return false
    end

    local itemId = msg:getU16()
    if not itemId or itemId <= 0 then
        return true
    end

    local defaultValue = msg:getU32()
    msg:getU32() -- default buy price
    msg:getU32() -- average market price

    local descriptionsSize = msg:getU8()
    for _ = 1, descriptionsSize do
        msg:getString()
        msg:getString()
    end

    local npcSaleData = {}
    local npcSaleDataSize = msg:getU16()
    for _ = 1, npcSaleDataSize do
        local name = msg:getString()
        local location = msg:getString()
        local buyPrice = msg:getU32()
        local salePrice = msg:getU32()
        local currencyQuestFlagDisplayName = msg:getString()
        npcSaleData[#npcSaleData + 1] = {
            name = name,
            location = location,
            buyPrice = buyPrice,
            salePrice = salePrice,
            currencyQuestFlagDisplayName = currencyQuestFlagDisplayName
        }
    end

    if defaultValue > 0 then
        ItemsDatabase.registerServerItemValue(itemId, defaultValue)
    end

    if #npcSaleData > 0 then
        ItemsDatabase.registerServerNpcSaleData(itemId, npcSaleData)
    end

    if g_game.onItemDetails then
        g_game.onItemDetails(itemId, defaultValue, npcSaleData)
    end
    return true
end

local function registerCustomItemOpcodes()
    if not ProtocolGame or not ProtocolGame.registerOpcode or not usesCustomItemValueProtocol() then
        return
    end
    pcall(function()
        ProtocolGame.unregisterOpcode(OPCODE_ITEM_VALUES)
        ProtocolGame.unregisterOpcode(OPCODE_ITEM_DETAILS)
    end)
    ProtocolGame.registerOpcode(OPCODE_ITEM_VALUES, onItemValuesOpcode)
    ProtocolGame.registerOpcode(OPCODE_ITEM_DETAILS, onItemDetailsOpcode)
end

local function unregisterCustomItemOpcodes()
    if not ProtocolGame or not ProtocolGame.unregisterOpcode then
        return
    end
    pcall(function()
        ProtocolGame.unregisterOpcode(OPCODE_ITEM_VALUES)
        ProtocolGame.unregisterOpcode(OPCODE_ITEM_DETAILS)
    end)
end

local function onGameStart()
    ItemsDatabase.clearServerItemValues()
    registerCustomItemOpcodes()
end

local function onGameEnd()
    ItemsDatabase.clearServerItemValues()
    unregisterCustomItemOpcodes()
end

connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onEnterGame = registerCustomItemOpcodes
})

