-- to-do
-- change to ItemsDatabase.setTier(UIitem) to UIitem:setTier()
ItemsDatabase = {}

ItemsDatabase.serverValues = ItemsDatabase.serverValues or {}

local OPCODE_ITEM_VALUES = 0xC6

ItemsDatabase.rarityColors = {
    ["yellow"] = TextColors.yellow,
    ["purple"] = TextColors.purple,
    ["blue"] = TextColors.blue,
    ["green"] = TextColors.green,
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

    local cyclopediaData = modules.game_cyclopedia and modules.game_cyclopedia.itemsData
    if cyclopediaData and cyclopediaData.serverValues then
        cyclopediaData.serverValues[tostring(itemId)] = value
    end
end

function ItemsDatabase.clearServerItemValues()
    ItemsDatabase.serverValues = {}
end

function ItemsDatabase.getItemPrice(item)
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
        item = g_things.getThingType(item, ThingCategoryItem)
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

function ItemsDatabase.setRarityItem(widget, item, style)
    if not widget then
        return
    end

    if not g_game.getFeature(GameColorizedLootValue) or not item then
        widget:setImageClip(torect("0 0 0 0"))
        widget:setImageSource('/images/ui/item')
        if style then
            widget:setStyle(style)
        end
        return
    end

    local clip, imagePath = ItemsDatabase.getClipAndImagePath(item)

    if not imagePath or not clip then
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

function ItemsDatabase.getColorForRarity(rarity)
    return ItemsDatabase.rarityColors[rarity] or TextColors.white
end

function ItemsDatabase.setColorLootMessage(text, defaultColor)
    if type(text) ~= 'string' then
        return text
    end

    -- CIP loot messages use green as the base color; rarity only recolors item names.
    if text:find('^Loot of ') or text:find('^Loot de ') then
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
    if not g_game.getFeature(GameColorizedLootValue) then
        if msg and msg.getMessageSize and msg.setReadPos then
            msg:setReadPos(msg:getMessageSize())
        end
        return
    end

    local count = msg:getU16()
    for _ = 1, count do
        local itemId = msg:getU16()
        local value = msg:getU32()
        ItemsDatabase.registerServerItemValue(itemId, value)
    end
end

local function registerItemValuesOpcode()
    if not ProtocolGame or not ProtocolGame.registerOpcode then
        return
    end
    pcall(function()
        ProtocolGame.unregisterOpcode(OPCODE_ITEM_VALUES)
    end)
    ProtocolGame.registerOpcode(OPCODE_ITEM_VALUES, onItemValuesOpcode)
end

local function onGameStart()
    ItemsDatabase.clearServerItemValues()
end

local function onGameEnd()
    ItemsDatabase.clearServerItemValues()
end

registerItemValuesOpcode()
connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
})

