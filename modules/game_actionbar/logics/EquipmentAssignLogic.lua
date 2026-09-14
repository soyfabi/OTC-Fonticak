local EQUIPMENT_ICONS_SHEET = "/images/game/spells/equipment-icons"
local EQUIPMENT_ICON_SIZE = 32
local EQUIPMENT_ICON_UNDETERMINED_INDEX = 0
local EQUIPMENT_ICON_PICKER_COUNT = 6
local EQUIPMENT_ICON_MAX_INDEX = EQUIPMENT_ICON_PICKER_COUNT
local EQUIPMENT_ASSIGN_BACKPACK_SLOT = InventorySlotBack
local EQUIPMENT_TYPE_ICON_BASE = "/game_cyclopedia/images/bestiary/icons/monster-icon-"
local EQUIPMENT_TYPE_OPTIONS = {
    "energy-resist",
    "earth-resist",
    "fire-resist",
    "lifedrain-resist",
    "manadrain-resist",
    "ice-resist",
    "holy-resist",
    "death-resist",
    "spellcaster",
    "armor",
    "physical-resist",
    "melee",
    "ranged",
    "speed",
    "noattack"
}
local EQUIPMENT_TYPE_MAX_INDEX = #EQUIPMENT_TYPE_OPTIONS
local EQUIPMENT_SLOT_DECOR_ICON_SIZE = { height = 9, width = 9 }

local EQUIPMENT_SET_EQUIP_ORDER = {
    InventorySlotHead,
    InventorySlotNeck,
    InventorySlotBody,
    InventorySlotRight,
    InventorySlotLeft,
    InventorySlotLeg,
    InventorySlotFeet,
    InventorySlotFinger,
    InventorySlotAmmo
}

local EQUIPMENT_SET_COOLDOWN_MS = 1000
local EQUIP_SET_ACTION_DELAY_MS = 350
local EQUIP_SET_MAX_STEPS = 32
local EQUIPMENT_SLOT_HOVER_PULSE_MS = 36
local EQUIPMENT_SLOT_HOVER_PULSE_COLOR = "#8CB8E8"
local EQUIPMENT_SLOT_HOVER_PULSE_MIN = 0.12
local EQUIPMENT_SLOT_HOVER_PULSE_MAX = 0.46
local EQUIPMENT_SLOT_HOVER_PULSE_STEP = 0.11
local EQUIPMENT_SLOT_VALID_DRAG_BORDER_COLOR = "#8CB8E8"
local EQUIPMENT_SLOT_INVALID_DRAG_BORDER_COLOR = "#E04040"
local EQUIPMENT_SLOT_DRAG_BORDER_WIDTH = 2
local EQUIPMENT_ASSIGN_SLOT_TOOLTIP = tr('Right-click to select equipment or drag an item here.')
local EQUIPMENT_ASSIGN_BACKPACK_TOOLTIP = tr('Your current backpack.')

local equipmentAssignWindow = nil
local equipmentAssignIconWindow = nil
local equipmentAssignButton = nil
local equipmentAssignDraft = nil
local equipmentAssignPickInvSlot = nil
local equipmentAssignHiddenForPick = false
local equipmentAssignHiddenForIconPicker = false
local equipmentAssignIconIndex = EQUIPMENT_ICON_UNDETERMINED_INDEX
local equipmentAssignDescription = ""
local equipmentAssignIconPickerRevertIndex = EQUIPMENT_ICON_UNDETERMINED_INDEX
local equipmentAssignIconPickerRevertDescription = ""
local equipmentAssignTypeIndex = 0
local equipmentAssignTypePickerRevertIndex = 0
local equipmentAssignTypeRadioGroup
local equipmentSetSharedCooldownUntil = nil
local pendingEquipmentSetEvent = nil
local pendingEquipmentSetActive = false
local pendingEquipmentSetMode = nil
local pendingEquipmentSetCache = nil
local pendingEquipmentSetSteps = 0
local EQUIP_ASSIGN_DEBUG = false
local SERVER_EQUIPMENT_DATA = dofile('/modules/game_actionbar/logics/EquipmentServerSlots.lua')
local SERVER_ITEM_INVENTORY_SLOTS = SERVER_EQUIPMENT_DATA.slots or SERVER_EQUIPMENT_DATA
local SERVER_ITEM_QUIVERS = SERVER_EQUIPMENT_DATA.quivers or {}
local SERVER_ITEM_SHIELDS = SERVER_EQUIPMENT_DATA.shields or {}
local SERVER_ITEM_TWO_HANDED_DISTANCE = SERVER_EQUIPMENT_DATA.twoHandedDistance or {}

EAssign = {}

local function equipAssignDebug(fmt, ...)
    if not EQUIP_ASSIGN_DEBUG then
        return
    end
    if select("#", ...) > 0 then
        print(string.format("[EAssign] " .. fmt, ...))
    else
        print("[EAssign] " .. tostring(fmt))
    end
end

local function isEquipmentAssignVisualBackpackSlot(invSlot)
    return invSlot == EQUIPMENT_ASSIGN_BACKPACK_SLOT
end

local function normalizeEquipmentIconIndex(index)
    if type(index) ~= "number" then
        return EQUIPMENT_ICON_UNDETERMINED_INDEX
    end
    return math.max(EQUIPMENT_ICON_UNDETERMINED_INDEX, math.min(EQUIPMENT_ICON_MAX_INDEX, math.floor(index)))
end

local function isEquipmentAssignIconDetermined()
    return normalizeEquipmentIconIndex(equipmentAssignIconIndex) > EQUIPMENT_ICON_UNDETERMINED_INDEX
end

local function normalizeEquipmentTypeIndex(index)
    if type(index) ~= "number" then
        return 0
    end
    return math.max(0, math.min(EQUIPMENT_TYPE_MAX_INDEX, math.floor(index)))
end

local function destroyEquipmentAssignTypeRadioGroup()
    if not equipmentAssignTypeRadioGroup then
        return
    end
    equipmentAssignTypeRadioGroup.onSelectionChange = nil
    equipmentAssignTypeRadioGroup:destroy()
    equipmentAssignTypeRadioGroup = nil
end

local function equipmentTypeIconSource(typeIndex)
    typeIndex = normalizeEquipmentTypeIndex(typeIndex)
    if typeIndex <= 0 then
        return nil
    end
    local suffix = EQUIPMENT_TYPE_OPTIONS[typeIndex]
    if not suffix then
        return nil
    end
    return EQUIPMENT_TYPE_ICON_BASE .. suffix
end

local function equipmentIconClip(index)
    local i = normalizeEquipmentIconIndex(index)
    return string.format("%d 0 %d %d", i * EQUIPMENT_ICON_SIZE, EQUIPMENT_ICON_SIZE, EQUIPMENT_ICON_SIZE)
end

local function applyEquipmentIconToWidget(widget, index)
    if not widget or widget:isDestroyed() then
        return
    end
    widget:setImageSource(EQUIPMENT_ICONS_SHEET)
    widget:setImageSize(tosize("32 32"))
    widget:setImageClip(equipmentIconClip(index))
    widget:show()
end

function isEquipmentPresetCache(cache)
    if not cache or cache.actionType ~= UseTypes["Equip"] then
        return false
    end
    if cache.isEquipmentPreset then
        return true
    end
    if cache.equipments ~= nil then
        return true
    end
    return type(cache.equipmentIconIndex) == "number" and normalizeEquipmentIconIndex(cache.equipmentIconIndex) > EQUIPMENT_ICON_UNDETERMINED_INDEX
end

function equipmentEntryFromItem(item)
    if not item then
        return nil
    end
    local entry = { itemId = item:getId() }
    if g_game.getFeature(GameThingUpgradeClassification) then
        entry.getTier = item:getTier()
    end
    if item:isFluidContainer() then
        entry.subType = item:getSubType()
    end
    return entry
end

local function equipmentEntryToItem(entry)
    if not entry or not entry.itemId or entry.itemId <= 0 then
        return nil
    end
    local item = Item.create(entry.itemId)
    if not item then
        return nil
    end
    if entry.getTier then
        item:setTier(entry.getTier)
    end
    if entry.subType then
        item:setSubType(entry.subType)
    end
    return item
end

function serializeEquipmentsForJson(equipments)
    if equipments == nil then
        return nil
    end
    local out = {}
    for invSlot, entry in pairs(equipments) do
        if type(invSlot) == "number" and entry and entry.itemId and entry.itemId > 0
            and not isEquipmentAssignVisualBackpackSlot(invSlot) then
            out[tostring(invSlot)] = {
                itemId = entry.itemId,
                getTier = type(entry.getTier) == "number" and entry.getTier or nil,
                subType = type(entry.subType) == "number" and entry.subType or nil
            }
        end
    end
    return out
end

function normalizeEquipmentsFromSetting(equipments)
    if equipments == nil then
        return nil
    end
    if type(equipments) ~= "table" then
        return nil
    end
    local out = {}
    for k, entry in pairs(equipments) do
        if type(entry) == "table" and type(entry.itemId) == "number" and entry.itemId > 0 then
            local invSlot = type(k) == "number" and k or tonumber(k)
            if invSlot and not isEquipmentAssignVisualBackpackSlot(invSlot) then
                out[invSlot] = {
                    itemId = entry.itemId,
                    getTier = type(entry.getTier) == "number" and entry.getTier or nil,
                    subType = type(entry.subType) == "number" and entry.subType or nil
                }
            end
        end
    end
    return out
end

function equipmentAssignDisplayEntry(equipments)
    if not equipments then
        return nil
    end
    local order = {
        InventorySlotBody, InventorySlotHead, InventorySlotLeg, InventorySlotFeet,
        InventorySlotNeck, InventorySlotLeft, InventorySlotRight,
        InventorySlotFinger, InventorySlotAmmo
    }
    for _, invSlot in ipairs(order) do
        local entry = equipments[invSlot]
        if entry and entry.itemId and entry.itemId > 0 then
            return entry
        end
    end
    for _, entry in pairs(equipments) do
        if entry and entry.itemId and entry.itemId > 0 then
            return entry
        end
    end
    return nil
end

local function copyEquipmentAssignDraft(source)
    equipmentAssignDraft = {}
    if not source then
        return
    end
    for invSlot, entry in pairs(source) do
        if not isEquipmentAssignVisualBackpackSlot(invSlot) and entry and entry.itemId and entry.itemId > 0 then
            equipmentAssignDraft[invSlot] = {
                itemId = entry.itemId,
                getTier = entry.getTier,
                subType = entry.subType
            }
        end
    end
end

local function normalizeInventorySlot(invSlot)
    if type(invSlot) == "number" then
        return invSlot
    end
    return tonumber(invSlot)
end

local ARMOR_INVENTORY_SLOTS = {
    [InventorySlotHead] = true,
    [InventorySlotNeck] = true,
    [InventorySlotBody] = true,
    [InventorySlotLeg] = true,
    [InventorySlotFeet] = true,
    [InventorySlotFinger] = true,
}

function EAssign.getMarketCategory(item)
    if not item then
        return nil
    end
    local md = item.getMarketData and item:getMarketData()
    if md and md.category and md.category > 0 then
        return md.category
    end
    local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
    if thingType and thingType.getMarketData then
        md = thingType:getMarketData()
        if md and md.category and md.category > 0 then
            return md.category
        end
    end
    return nil
end

local MARKET_CATEGORY_TO_INVENTORY_SLOT = nil

local function getMarketCategoryInventorySlot(category)
    if not category or not MarketCategory then
        return nil
    end
    if not MARKET_CATEGORY_TO_INVENTORY_SLOT then
        MARKET_CATEGORY_TO_INVENTORY_SLOT = {
            [MarketCategory.Armors] = InventorySlotBody,
            [MarketCategory.Amulets] = InventorySlotNeck,
            [MarketCategory.Boots] = InventorySlotFeet,
            [MarketCategory.HelmetsHats] = InventorySlotHead,
            [MarketCategory.Legs] = InventorySlotLeg,
            [MarketCategory.Rings] = InventorySlotFinger,
            [MarketCategory.Shields] = InventorySlotRight,
            [MarketCategory.Ammunition] = InventorySlotAmmo,
            [MarketCategory.Quivers] = InventorySlotRight,
        }
        if MarketCategory.FistWeapons then
            MARKET_CATEGORY_TO_INVENTORY_SLOT[MarketCategory.FistWeapons] = InventorySlotLeft
        end
    end
    return MARKET_CATEGORY_TO_INVENTORY_SLOT[category]
end

local function usesLegacyEquipmentMetadata()
    return not g_game.getFeature(GameEnterGameShowAppearance)
end

local function getServerItemInventorySlot(item)
    if not item or not SERVER_ITEM_INVENTORY_SLOTS then
        return 0
    end
    return SERVER_ITEM_INVENTORY_SLOTS[item:getId()] or 0
end

local function isServerQuiverItem(item)
    return item and SERVER_ITEM_QUIVERS[item:getId()] == true
end

local function isServerShieldItem(item)
    return item and SERVER_ITEM_SHIELDS[item:getId()] == true
end

local function isServerTwoHandedDistanceItem(item)
    return item and SERVER_ITEM_TWO_HANDED_DISTANCE[item:getId()] == true
end

local function serverItemFitsInventorySlot(item, invSlot)
    local serverSlot = getServerItemInventorySlot(item)
    return serverSlot > 0 and serverSlot == invSlot
end

local ARMOR_SLOT_NAME_HINTS = {
    [InventorySlotHead] = { "helmet", "hat", "mask", "tiara", "crown" },
    [InventorySlotNeck] = { "amulet", "necklace" },
    [InventorySlotBody] = { "armor", "mail", "plate", "robe", "coat", "jacket", "tunic", "cloak", "cape", "hauberk", "brassard" },
    [InventorySlotLeg] = { "legs", "greaves" },
    [InventorySlotFeet] = { "boots", "shoes", "sandals" },
    [InventorySlotFinger] = { "ring" },
}

local function getEquipmentItemLookupName(item)
    if not item then
        return nil
    end
    if item.getName then
        local name = item:getName()
        if type(name) == "string" and name ~= "" then
            return name:lower()
        end
    end
    local md = item.getMarketData and item:getMarketData()
    if md and type(md.name) == "string" and md.name ~= "" then
        return md.name:lower()
    end
    local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
    if thingType then
        if thingType.getName then
            local name = thingType:getName()
            if type(name) == "string" and name ~= "" then
                return name:lower()
            end
        end
        if thingType.getMarketData then
            md = thingType:getMarketData()
            if md and type(md.name) == "string" and md.name ~= "" then
                return md.name:lower()
            end
        end
    end
    local created = Item.create(item:getId())
    if created and created.getName then
        local name = created:getName()
        if type(name) == "string" and name ~= "" then
            return name:lower()
        end
    end
    return nil
end

local function itemNameSuggestsInventorySlot(item, invSlot)
    if not item or not invSlot then
        return false
    end
    local hints = ARMOR_SLOT_NAME_HINTS[invSlot]
    if not hints then
        return false
    end
    local name = getEquipmentItemLookupName(item)
    if not name then
        return false
    end
    for _, hint in ipairs(hints) do
        if invSlot == InventorySlotFinger and hint == "ring" then
            if name == "ring" or name:find(" ring", 1, true) or name:find("^ring ", 1, true) then
                return true
            end
        elseif name:find(hint, 1, true) then
            return true
        end
    end
    return false
end

local function itemNameSuggestsDedicatedArmorSlot(item)
    for invSlot, _ in pairs(ARMOR_SLOT_NAME_HINTS) do
        if itemNameSuggestsInventorySlot(item, invSlot) then
            return invSlot
        end
    end
    return 0
end

local function itemIsWeaponForLeftHand(item)
    if serverItemFitsInventorySlot(item, InventorySlotLeft) then
        return not isServerQuiverItem(item)
            and not isServerShieldItem(item)
            and getServerItemInventorySlot(item) ~= InventorySlotAmmo
    end
    if EAssign.isDualWielding(item) then
        return true
    end
    if EAssign.getWeaponMarketSlots(item) then
        return true
    end
    local cat = EAssign.getMarketCategory(item)
    if MarketCategory and cat then
        if MarketCategoryWeapons and MarketCategoryWeapons[cat] then
            return true
        end
        if cat == MarketCategory.FistWeapons or cat == MarketCategory.Quivers then
            return true
        end
    end
    local clothSlot = item:getClothSlot()
    if clothSlot == InventorySlotLeft or clothSlot == InventorySlotOther then
        if usesLegacyEquipmentMetadata() and itemNameSuggestsDedicatedArmorSlot(item) > 0 then
            return false
        end
        return true
    end
    return false
end

function EAssign.resolveItemInventorySlot(item)
    if not item then
        return 0
    end
    local serverSlot = getServerItemInventorySlot(item)
    if serverSlot > 0 then
        return serverSlot
    end
    local nameSlot = itemNameSuggestsDedicatedArmorSlot(item)
    if nameSlot > 0 then
        return nameSlot
    end
    local cat = EAssign.getMarketCategory(item)
    local categorySlot = getMarketCategoryInventorySlot(cat)
    if categorySlot then
        return categorySlot
    end
    if MarketCategoryWeapons and cat and MarketCategoryWeapons[cat] then
        return InventorySlotLeft
    end
    local clothSlot = item:getClothSlot()
    if clothSlot > 0 then
        if clothSlot == InventorySlotLeft or clothSlot == InventorySlotOther then
            if itemIsWeaponForLeftHand(item) then
                return InventorySlotLeft
            end
            if usesLegacyEquipmentMetadata() then
                return 0
            end
        end
        return clothSlot
    end
    return 0
end

function EAssign.isDualWielding(item)
    if not item then return false end
    if item.isDualWield then
        return item:isDualWield()
    end
    local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
    if thingType and thingType.isDualWield then
        return thingType:isDualWield()
    end
    if thingType and thingType.isDualWielding then
        return thingType:isDualWielding()
    end
    return false
end

function EAssign.isQuiver(item)
    if not item then return false end
    if isServerQuiverItem(item) then
        return true
    end
    if item.isQuiver and item:isQuiver() then
        return true
    end
    local cat = EAssign.getMarketCategory(item)
    return MarketCategory and cat == MarketCategory.Quivers
end

function EAssign.isBowOrCrossbow(item)
    if not item then return false end
    if isServerTwoHandedDistanceItem(item) then
        return true
    end
    local cat = EAssign.getMarketCategory(item)
    if not MarketCategory or cat ~= MarketCategory.DistanceWeapons then
        return false
    end
    return item:getClothSlot() == InventorySlotOther
end

function EAssign.isShield(item)
    if not item or EAssign.isQuiver(item) then return false end
    if isServerShieldItem(item) then
        return true
    end
    if item:getClothSlot() == InventorySlotRight then return true end
    local cat = EAssign.getMarketCategory(item)
    return MarketCategory and cat == MarketCategory.Shields
end

function EAssign.getWeaponMarketSlots(item)
    local cat = EAssign.getMarketCategory(item)
    if cat and MarketCategoryWeapons and MarketCategoryWeapons[cat] then
        return MarketCategoryWeapons[cat].slots
    end
    return nil
end

function EAssign.weaponHandFlags(item)
    local slots = EAssign.getWeaponMarketSlots(item)
    if not slots then return false, false end
    local canOneHand, canTwoHand = false, false
    for _, allowed in ipairs(slots) do
        if allowed == InventorySlotLeft then
            canOneHand = true
        elseif allowed == 255 or allowed == InventorySlotOther then
            canTwoHand = true
        end
    end
    return canOneHand, canTwoHand
end

function EAssign.blocksShieldSlot(item)
    if not item or EAssign.isShield(item) then return false end
    if EAssign.isBowOrCrossbow(item) then return false end
    if EAssign.isDualWielding(item) then return true end
    local canOneHand, canTwoHand = EAssign.weaponHandFlags(item)
    if canTwoHand and not canOneHand then return true end
    if item:getClothSlot() == InventorySlotOther then return true end
    return false
end

function EAssign.draftLeftHandItem()
    local entry = equipmentAssignDraft and equipmentAssignDraft[InventorySlotLeft]
    return entry and equipmentEntryToItem(entry) or nil
end

function EAssign.resolveRightSlotEntry(rightEntry)
    if rightEntry and rightEntry.itemId and rightEntry.itemId > 0 then
        return rightEntry, false
    end
    local leftItem = EAssign.draftLeftHandItem()
    if leftItem and EAssign.isDualWielding(leftItem) then
        return equipmentAssignDraft[InventorySlotLeft], true
    end
    return nil, false
end

function EAssign.reconcileHandSlots()
    if not equipmentAssignDraft then return end
    local leftItem = EAssign.draftLeftHandItem()
    local rightEntry = equipmentAssignDraft[InventorySlotRight]
    if not rightEntry then return end
    local rightItem = equipmentEntryToItem(rightEntry)
    if leftItem and EAssign.isDualWielding(leftItem) then
        equipmentAssignDraft[InventorySlotRight] = nil
        return
    end
    if leftItem and EAssign.blocksShieldSlot(leftItem) then
        equipmentAssignDraft[InventorySlotRight] = nil
        return
    end
    if rightItem and leftItem and EAssign.isBowOrCrossbow(leftItem) and EAssign.isShield(rightItem) then
        equipmentAssignDraft[InventorySlotRight] = nil
    end
end

local function isEquippableActionBarItem(item, debugLabel)
    if not item or item:isContainer() then
        equipAssignDebug("%s equippable reject: missing item or container", debugLabel or "equippable")
        return false
    end
    local clothSlot = item:getClothSlot()
    if clothSlot == InventorySlotBack then
        equipAssignDebug("%s equippable reject: backpack clothSlot", debugLabel or "equippable")
        return false
    end
    local cat = EAssign.getMarketCategory(item)
    local categorySlot = getMarketCategoryInventorySlot(cat)
    local nameSlot = itemNameSuggestsDedicatedArmorSlot(item)
    local serverSlot = getServerItemInventorySlot(item)
    local resolvedSlot = EAssign.resolveItemInventorySlot(item)
    local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
    local isCloth = thingType and thingType.isCloth and thingType:isCloth()
    local isAmmo = item:isAmmo()

    equipAssignDebug(
        "%s equippable itemId=%s name='%s' clothSlot=%s serverSlot=%s marketCat=%s categorySlot=%s nameSlot=%s resolved=%s isCloth=%s isAmmo=%s legacy=%s",
        debugLabel or "equippable",
        tostring(item:getId()),
        tostring(getEquipmentItemLookupName(item)),
        tostring(clothSlot),
        tostring(serverSlot),
        tostring(cat),
        tostring(categorySlot),
        tostring(nameSlot),
        tostring(resolvedSlot),
        tostring(isCloth),
        tostring(isAmmo),
        tostring(usesLegacyEquipmentMetadata())
    )

    if serverSlot > 0 then
        return true
    end
    if nameSlot > 0 then
        return true
    end
    if categorySlot then
        return true
    end
    if resolvedSlot > 0 then
        return true
    end
    if cat and MarketCategoryWeapons and MarketCategoryWeapons[cat] then
        return true
    end
    if MarketCategory and cat and (cat == MarketCategory.FistWeapons or cat == MarketCategory.Quivers
        or cat == MarketCategory.Shields) then
        return true
    end
    if clothSlot > 0 then
        if clothSlot == InventorySlotLeft or clothSlot == InventorySlotOther then
            return itemIsWeaponForLeftHand(item)
        end
        return true
    end
    if isCloth then
        return true
    end
    if isAmmo then
        return true
    end
    equipAssignDebug("%s equippable reject: no equipment signals", debugLabel or "equippable")
    return false
end

local function itemIsDedicatedArmorPiece(item)
    local serverSlot = getServerItemInventorySlot(item)
    if serverSlot > 0 then
        return ARMOR_INVENTORY_SLOTS[serverSlot] == true
    end
    if itemNameSuggestsDedicatedArmorSlot(item) > 0 then
        return true
    end
    local categorySlot = getMarketCategoryInventorySlot(EAssign.getMarketCategory(item))
    return categorySlot ~= nil and ARMOR_INVENTORY_SLOTS[categorySlot] == true
end

local function itemBlocksArmorInventorySlot(item)
    local serverSlot = getServerItemInventorySlot(item)
    if serverSlot > 0 then
        return not ARMOR_INVENTORY_SLOTS[serverSlot]
    end
    if itemIsDedicatedArmorPiece(item) then
        return false
    end
    if EAssign.isDualWielding(item) then
        return true
    end
    if EAssign.getWeaponMarketSlots(item) then
        return true
    end
    local cat = EAssign.getMarketCategory(item)
    if MarketCategory and cat then
        if MarketCategoryWeapons and MarketCategoryWeapons[cat] then
            return true
        end
        if cat == MarketCategory.FistWeapons or cat == MarketCategory.Quivers then
            return true
        end
    end
    if not usesLegacyEquipmentMetadata() then
        local clothSlot = item:getClothSlot()
        if clothSlot == InventorySlotLeft or clothSlot == InventorySlotOther then
            return true
        end
    end
    return false
end

local function itemIsObviousNonArmorEquipment(item)
    return itemBlocksArmorInventorySlot(item)
        or EAssign.isShield(item)
        or EAssign.isQuiver(item)
        or item:isAmmo()
end

local function itemFitsDedicatedArmorSlot(item, invSlot, debugLabel)
    if not ARMOR_INVENTORY_SLOTS[invSlot] then
        equipAssignDebug("%s armor-slot reject: invSlot %s is not a dedicated armor slot",
            debugLabel or "fit", tostring(invSlot))
        return false
    end
    local nameMatch = itemNameSuggestsInventorySlot(item, invSlot)
    local serverSlot = getServerItemInventorySlot(item)
    local categorySlot = getMarketCategoryInventorySlot(EAssign.getMarketCategory(item))
    local clothSlot = item:getClothSlot()
    local obviousNonArmor = itemIsObviousNonArmorEquipment(item)
    local resolvedSlot = EAssign.resolveItemInventorySlot(item)
    equipAssignDebug(
        "%s armor-slot check itemId=%s name='%s' target=%s serverSlot=%s nameMatch=%s marketCat=%s categorySlot=%s clothSlot=%s obviousNonArmor=%s resolved=%s legacy=%s",
        debugLabel or "fit",
        tostring(item:getId()),
        tostring(getEquipmentItemLookupName(item)),
        tostring(invSlot),
        tostring(serverSlot),
        tostring(nameMatch),
        tostring(EAssign.getMarketCategory(item)),
        tostring(categorySlot),
        tostring(clothSlot),
        tostring(obviousNonArmor),
        tostring(resolvedSlot),
        tostring(usesLegacyEquipmentMetadata())
    )
    if serverSlot > 0 and serverSlot == invSlot then
        equipAssignDebug("%s armor-slot accept: server items.xml slot", debugLabel or "fit")
        return true
    end
    if nameMatch then
        equipAssignDebug("%s armor-slot accept: name hint", debugLabel or "fit")
        return true
    end
    if categorySlot == invSlot then
        equipAssignDebug("%s armor-slot accept: market category", debugLabel or "fit")
        return true
    end
    if clothSlot == invSlot then
        equipAssignDebug("%s armor-slot accept: clothSlot", debugLabel or "fit")
        return true
    end
    if obviousNonArmor then
        equipAssignDebug("%s armor-slot reject: treated as non-armor equipment", debugLabel or "fit")
        return false
    end
    local fits = resolvedSlot > 0 and resolvedSlot == invSlot
    equipAssignDebug("%s armor-slot %s: resolved slot match", debugLabel or "fit", fits and "accept" or "reject")
    return fits
end

local function itemFitsEquipmentAssignSlotByExclusion(item, invSlot)
    if item:isAmmo() then
        return invSlot == InventorySlotAmmo
    end
    if invSlot == InventorySlotAmmo then
        return item:isAmmo()
    end
    if invSlot == InventorySlotRight then
        if serverItemFitsInventorySlot(item, invSlot) then
            local leftItem = EAssign.draftLeftHandItem()
            if EAssign.isQuiver(item) then
                if leftItem and EAssign.isBowOrCrossbow(leftItem) then
                    return true
                end
                return not leftItem or not EAssign.blocksShieldSlot(leftItem)
            end
            if leftItem and EAssign.isBowOrCrossbow(leftItem) then
                return false
            end
            if leftItem and EAssign.blocksShieldSlot(leftItem) then
                return false
            end
            return true
        end
        local leftItem = EAssign.draftLeftHandItem()
        if leftItem and EAssign.isBowOrCrossbow(leftItem) then
            return EAssign.isQuiver(item)
        end
        if EAssign.isQuiver(item) then
            return not leftItem or not EAssign.blocksShieldSlot(leftItem)
        end
        if EAssign.isShield(item) then
            return not leftItem or not EAssign.blocksShieldSlot(leftItem)
        end
        return false
    end
    if invSlot == InventorySlotLeft then
        if serverItemFitsInventorySlot(item, invSlot) then
            return not isServerQuiverItem(item)
                and not isServerShieldItem(item)
                and not item:isAmmo()
        end
        if EAssign.isShield(item) or EAssign.isQuiver(item) or item:isAmmo() then
            return false
        end
        if EAssign.isDualWielding(item) then
            return true
        end
        return itemIsWeaponForLeftHand(item)
    end
    if ARMOR_INVENTORY_SLOTS[invSlot] then
        return not itemBlocksArmorInventorySlot(item)
            and not EAssign.isShield(item)
            and not EAssign.isQuiver(item)
            and not item:isAmmo()
    end
    return false
end

local function itemFitsEquipmentAssignSlot(item, invSlot, debugLabel)
    local rawInvSlot = invSlot
    invSlot = normalizeInventorySlot(invSlot)
    equipAssignDebug(
        "%s start itemId=%s rawInvSlot=%s (%s) normalizedInvSlot=%s",
        debugLabel or "fit",
        item and tostring(item:getId()) or "nil",
        tostring(rawInvSlot),
        type(rawInvSlot),
        tostring(invSlot)
    )
    if not item or not invSlot or isEquipmentAssignVisualBackpackSlot(invSlot) then
        equipAssignDebug("%s reject: missing item/invSlot or backpack slot", debugLabel or "fit")
        return false
    end
    if not isEquippableActionBarItem(item, debugLabel) then
        equipAssignDebug("%s reject: not equippable", debugLabel or "fit")
        return false
    end
    local clothSlot = item:getClothSlot()
    if clothSlot == InventorySlotBack then
        equipAssignDebug("%s reject: backpack clothSlot", debugLabel or "fit")
        return false
    end
    if invSlot == InventorySlotRight then
        if serverItemFitsInventorySlot(item, invSlot) then
            local leftItem = EAssign.draftLeftHandItem()
            if EAssign.isQuiver(item) then
                if leftItem and EAssign.isBowOrCrossbow(leftItem) then
                    return true
                end
                return not leftItem or not EAssign.blocksShieldSlot(leftItem)
            end
            if leftItem and EAssign.isBowOrCrossbow(leftItem) then
                return false
            end
            if leftItem and EAssign.blocksShieldSlot(leftItem) then
                return false
            end
            return true
        end
        local leftItem = EAssign.draftLeftHandItem()
        if leftItem and EAssign.isBowOrCrossbow(leftItem) then
            return EAssign.isQuiver(item)
        end
        if EAssign.isQuiver(item) then
            return not leftItem or not EAssign.blocksShieldSlot(leftItem)
        end
        if EAssign.isShield(item) then
            return not leftItem or not EAssign.blocksShieldSlot(leftItem)
        end
        return itemFitsEquipmentAssignSlotByExclusion(item, invSlot)
    end
    if invSlot == InventorySlotLeft then
        if serverItemFitsInventorySlot(item, invSlot) then
            return not isServerQuiverItem(item)
                and not isServerShieldItem(item)
                and not item:isAmmo()
        end
        if EAssign.isShield(item) or EAssign.isQuiver(item) or item:isAmmo() then
            return false
        end
        if EAssign.isDualWielding(item) then
            return true
        end
        return itemIsWeaponForLeftHand(item)
    end
    if ARMOR_INVENTORY_SLOTS[invSlot] then
        return itemFitsDedicatedArmorSlot(item, invSlot, debugLabel)
    end
    if invSlot == InventorySlotAmmo then
        local resolvedSlot = EAssign.resolveItemInventorySlot(item)
        if resolvedSlot > 0 and resolvedSlot == invSlot then
            return true
        end
        return item:isAmmo()
    end
    local resolvedSlot = EAssign.resolveItemInventorySlot(item)
    if resolvedSlot > 0 then
        return resolvedSlot == invSlot
    end
    return false
end

local function forEachEquipmentAssignSlot(callback)
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed() or not callback then
        return
    end
    local panel = equipmentAssignWindow:recursiveGetChildById("equipmentPanel")
    if not panel then return end
    for _, child in ipairs(panel:getChildren()) do
        local invSlot = normalizeInventorySlot(child.inventorySlot)
        if invSlot then callback(child, invSlot) end
    end
end

local function clearEquipmentAssignSlotItemWidget(itemWidget)
    itemWidget:setItem(nil)
    if ItemsDatabase then
        ItemsDatabase.setTier(itemWidget, 0)
    end
end

local function setItemMirrorHorizontal(itemWidget, mirror)
    if itemWidget and itemWidget.setMirrorHorizontal then
        itemWidget:setMirrorHorizontal(mirror)
    end
end

local function refreshEquipmentAssignSlotWidget(slotWidget, entry)
    local itemWidget = slotWidget:getChildById("equippedItem")
    local slotIcon = slotWidget:getChildById("slotIcon")
    if not itemWidget then return end
    local invSlot = normalizeInventorySlot(slotWidget.inventorySlot)
    local mirrorShieldSlot = false
    if invSlot == InventorySlotRight then
        entry, mirrorShieldSlot = EAssign.resolveRightSlotEntry(entry)
    end
    local item = equipmentEntryToItem(entry)
    if item then
        if mirrorShieldSlot then
            local mirrored = item:clone()
            itemWidget:setItem(mirrored)
            item = mirrored
        else
            itemWidget:setItem(item)
        end
        setItemMirrorHorizontal(itemWidget, mirrorShieldSlot)
        if invSlot == InventorySlotRight then
            local opacity = mirrorShieldSlot and 0.6 or 1
            slotWidget:setOpacity(opacity)
            itemWidget:setOpacity(opacity)
        end
        if ItemsDatabase then
            ItemsDatabase.setTier(itemWidget, 0)
        end
        if slotIcon then slotIcon:setVisible(false) end
    else
        setItemMirrorHorizontal(itemWidget, false)
        if invSlot == InventorySlotRight then
            slotWidget:setOpacity(1)
            itemWidget:setOpacity(1)
        end
        clearEquipmentAssignSlotItemWidget(itemWidget)
        if slotIcon then
            slotIcon:setVisible(true)
            slotIcon:raise()
        end
    end
end

function EAssign.refreshHandSlotWidgets()
    forEachEquipmentAssignSlot(function(widget, slotId)
        if slotId == InventorySlotLeft or slotId == InventorySlotRight then
            local entry = equipmentAssignDraft and equipmentAssignDraft[slotId]
            refreshEquipmentAssignSlotWidget(widget, entry)
        end
    end)
end

local function refreshEquipmentAssignBackpackSlot()
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed() then return end
    local backSlot = equipmentAssignWindow:recursiveGetChildById("backSlot")
    if not backSlot then return end
    local player = g_game.getLocalPlayer()
    local entry = player and equipmentEntryFromItem(player:getInventoryItem(EQUIPMENT_ASSIGN_BACKPACK_SLOT))
    refreshEquipmentAssignSlotWidget(backSlot, entry)
end

local function refreshAllEquipmentAssignSlots()
    EAssign.reconcileHandSlots()
    forEachEquipmentAssignSlot(function(widget, invSlot)
        if isEquipmentAssignVisualBackpackSlot(invSlot) then return end
        local entry = equipmentAssignDraft and equipmentAssignDraft[invSlot] or nil
        refreshEquipmentAssignSlotWidget(widget, entry)
    end)
    refreshEquipmentAssignBackpackSlot()
end

local function refreshAssignActionSlotPreview()
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed()
        or equipmentAssignHiddenForPick or equipmentAssignHiddenForIconPicker then
        return
    end
    local slotWidget = equipmentAssignWindow:recursiveGetChildById("assignActionSlot")
    if not slotWidget then return end
    local icon = slotWidget:recursiveGetChildById("equipmentSlotIcon")
    if isEquipmentAssignIconDetermined() then
        applyEquipmentIconToWidget(icon, equipmentAssignIconIndex)
    elseif icon then
        icon:hide()
    end
    local typeIcon = slotWidget:recursiveGetChildById("equipmentTypeIcon")
    if typeIcon then
        local src = equipmentTypeIconSource(equipmentAssignTypeIndex)
        if src then
            typeIcon:setImageSource(src)
            typeIcon:setImageSize(EQUIPMENT_SLOT_DECOR_ICON_SIZE)
            typeIcon:show()
        else
            typeIcon:setVisible(false)
        end
    end
end

local function refreshEquipmentAssignIconPickerSelection()
    if not equipmentAssignIconWindow or equipmentAssignIconWindow:isDestroyed() then return end
    local panel = equipmentAssignIconWindow:recursiveGetChildById("iconScrollPanel")
    if not panel then return end
    for _, child in ipairs(panel:getChildren()) do
        if child.iconIndex ~= nil then
            child:setImageSource("/images/game/actionbar/slot-actionbar-filled")
            child:setImageSize(tosize("34 34"))
            if child.iconIndex == equipmentAssignIconIndex then
                child:setImageClip("0 34 34 34")
            else
                child:setImageClip("0 0 34 34")
            end
        end
    end
end

local function setupEquipmentAssignTypePicker()
    if not equipmentAssignIconWindow or equipmentAssignIconWindow:isDestroyed() then return end
    local panel = equipmentAssignIconWindow:recursiveGetChildById("typeButtonsPanel")
    if not panel then return end
    destroyEquipmentAssignTypeRadioGroup()
    panel:destroyChildren()
    equipmentAssignTypeRadioGroup = UIRadioGroup.create()
    local selectedWidget
    for typeIndex = 0, EQUIPMENT_TYPE_MAX_INDEX do
        local btn = g_ui.createWidget("EquipmentTypeButton", panel)
        btn.typeIndex = typeIndex
        if typeIndex > 0 then
            local suffix = EQUIPMENT_TYPE_OPTIONS[typeIndex]
            if suffix then
                local typeIcon = btn:getChildById("typeIcon")
                typeIcon:setImageSource(EQUIPMENT_TYPE_ICON_BASE .. suffix)
                typeIcon:show()
            end
        end
        equipmentAssignTypeRadioGroup:addWidget(btn)
        if typeIndex == equipmentAssignTypeIndex then
            selectedWidget = btn
        end
    end
    if selectedWidget then
        equipmentAssignTypeRadioGroup:selectWidget(selectedWidget, true)
    end
    function equipmentAssignTypeRadioGroup.onSelectionChange(_, selected)
        if selected and selected.typeIndex ~= nil then
            equipmentAssignTypeIndex = selected.typeIndex
        else
            equipmentAssignTypeIndex = 0
        end
    end
end

function refreshActionBarEquipmentTypeIcon(button)
    if not button or button:isDestroyed() then return end
    local icon = button.equipmentTypeIcon
    if not icon or icon:isDestroyed() then return end
    if not isEquipmentPresetCache(button.cache) then
        icon:setVisible(false)
        return
    end
    local src = equipmentTypeIconSource(button.cache.equipmentTypeIndex)
    if not src then
        icon:setVisible(false)
        return
    end
    icon:setImageSource(src)
    icon:setImageSize(EQUIPMENT_SLOT_DECOR_ICON_SIZE)
    if button.multiIcon and not button.multiIcon:isDestroyed() and button.multiIcon:isVisible() then
        icon:setMarginLeft(12)
    else
        icon:setMarginLeft(1)
    end
    icon:show()
end

function equipmentAssignUpdateButtons()
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed() then return end
    local okBtn = equipmentAssignWindow:getChildById("okButton")
    local applyBtn = equipmentAssignWindow:getChildById("applyButton")
    local canSave = isEquipmentAssignIconDetermined()
    if okBtn then okBtn:setEnabled(canSave) end
    if applyBtn then applyBtn:setEnabled(canSave) end
end

local function copyEquipmentAssignMetaFromButton(button)
    local cache = button and button.cache
    if cache then
        equipmentAssignIconIndex = normalizeEquipmentIconIndex(cache.equipmentIconIndex)
        equipmentAssignDescription = cache.equipmentDescription or ""
        equipmentAssignTypeIndex = normalizeEquipmentTypeIndex(cache.equipmentTypeIndex)
    else
        equipmentAssignIconIndex = EQUIPMENT_ICON_UNDETERMINED_INDEX
        equipmentAssignDescription = ""
        equipmentAssignTypeIndex = 0
    end
end

local function resolvePickItemAtMouse(mousePosition)
    local root = gameRootPanel
    if not root and modules.game_interface and modules.game_interface.getRootPanel then
        root = modules.game_interface.getRootPanel()
    end
    local clickedWidget = root and root:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then return nil end
    if clickedWidget:getClassName() == "UIItem" and not clickedWidget:isVirtual() and clickedWidget:getItem() then
        return clickedWidget:getItem()
    end
    if clickedWidget:getClassName() == "UIGameMap" then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            local thing = tile:getTopUseThing()
            if thing and thing.isItem and thing:isItem() then return thing end
        end
    end
    return nil
end

local function equipmentAssignDraggedItem(draggingWidget)
    if not draggingWidget or draggingWidget:getClassName() ~= "UIItem" or draggingWidget:isVirtual() then
        return nil
    end
    local item = draggingWidget.currentDragThing
    if item and item.isItem and item:isItem() then return item end
    return nil
end

local function equipmentAssignSetSlotItem(invSlot, item, slotWidget)
    if isEquipmentAssignVisualBackpackSlot(invSlot) or not item then return false end
    if slotWidget then
        equipAssignDebug(
            "setSlot widgetId=%s widget.inventorySlot=%s (%s)",
            tostring(slotWidget:getId()),
            tostring(slotWidget.inventorySlot),
            type(slotWidget.inventorySlot)
        )
    end
    if not itemFitsEquipmentAssignSlot(item, invSlot, "setSlot") then
        modules.game_textmessage.displayFailureMessage(tr("This item is not suitable for this equipment slot."))
        return false
    end
    equipmentAssignDraft = equipmentAssignDraft or {}
    equipmentAssignDraft[invSlot] = equipmentEntryFromItem(item)
    EAssign.reconcileHandSlots()
    if invSlot == InventorySlotLeft or invSlot == InventorySlotRight then
        EAssign.refreshHandSlotWidgets()
    elseif slotWidget then
        refreshEquipmentAssignSlotWidget(slotWidget, equipmentAssignDraft[invSlot])
    else
        forEachEquipmentAssignSlot(function(widget, slotId)
            if slotId == invSlot then
                refreshEquipmentAssignSlotWidget(widget, equipmentAssignDraft[invSlot])
            end
        end)
    end
    equipmentAssignUpdateButtons()
    return true
end

local function onEquipmentAssignSlotDrop(slotWidget, draggedWidget, mousePos, invSlot)
    equipAssignDebug(
        "drop invSlot=%s (%s) widgetId=%s widget.inventorySlot=%s",
        tostring(invSlot),
        type(invSlot),
        slotWidget and tostring(slotWidget:getId()) or "nil",
        slotWidget and tostring(slotWidget.inventorySlot) or "nil"
    )
    if isEquipmentAssignVisualBackpackSlot(invSlot) then return false end
    local item = equipmentAssignDraggedItem(draggedWidget)
    if not item then
        equipAssignDebug("drop reject: dragged item is nil")
        return false
    end
    if equipmentAssignSetSlotItem(invSlot, item, slotWidget) then
        clearEquipmentAssignSlotHighlight(slotWidget)
        if draggedWidget then draggedWidget:setBorderWidth(0) end
        return true
    end
    showEquipmentAssignSlotInvalidDrag(slotWidget)
    return false
end

local function equipmentAssignSlotIsEmpty(invSlot)
    local entry = equipmentAssignDraft and equipmentAssignDraft[invSlot]
    return not entry or not entry.itemId or entry.itemId <= 0
end

local function getEquipmentAssignHoverPlaceholder(slotWidget)
    if not slotWidget or slotWidget:isDestroyed() then
        return nil
    end
    return slotWidget:recursiveGetChildById("hoverPlaceholder")
end

local function stopEquipmentAssignSlotHoverPulse(slotWidget)
    if not slotWidget then
        return
    end
    if slotWidget.equipmentHoverPulseEvent then
        removeEvent(slotWidget.equipmentHoverPulseEvent)
        slotWidget.equipmentHoverPulseEvent = nil
    end
    slotWidget.equipmentHoverPulseOn = false
    slotWidget.equipmentHoverPulsePhase = nil
    local overlay = getEquipmentAssignHoverPlaceholder(slotWidget)
    if overlay and not overlay:isDestroyed() then
        overlay:setVisible(false)
        overlay:setOpacity(0)
    end
end

local function equipmentAssignSlotHoverPulseTick(slotWidget)
    if not slotWidget or slotWidget:isDestroyed() or not slotWidget.equipmentHoverPulseOn then
        return
    end
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed() then
        stopEquipmentAssignSlotHoverPulse(slotWidget)
        return
    end
    local overlay = getEquipmentAssignHoverPlaceholder(slotWidget)
    if not overlay or overlay:isDestroyed() then
        stopEquipmentAssignSlotHoverPulse(slotWidget)
        return
    end
    slotWidget.equipmentHoverPulsePhase = (slotWidget.equipmentHoverPulsePhase or 0) + EQUIPMENT_SLOT_HOVER_PULSE_STEP
    if slotWidget.equipmentHoverPulsePhase > math.pi * 2 then
        slotWidget.equipmentHoverPulsePhase = slotWidget.equipmentHoverPulsePhase - math.pi * 2
    end
    local wave = (math.sin(slotWidget.equipmentHoverPulsePhase) + 1) * 0.5
    local opacity = EQUIPMENT_SLOT_HOVER_PULSE_MIN
        + (EQUIPMENT_SLOT_HOVER_PULSE_MAX - EQUIPMENT_SLOT_HOVER_PULSE_MIN) * wave
    overlay:setOpacity(opacity)
    overlay:setVisible(true)
    overlay:raise()
    slotWidget.equipmentHoverPulseEvent = scheduleEvent(function()
        equipmentAssignSlotHoverPulseTick(slotWidget)
    end, EQUIPMENT_SLOT_HOVER_PULSE_MS)
end

local function startEquipmentAssignSlotHoverPulse(slotWidget)
    stopEquipmentAssignSlotHoverPulse(slotWidget)
    slotWidget.equipmentHoverPulseOn = true
    slotWidget.equipmentHoverPulsePhase = 0
    equipmentAssignSlotHoverPulseTick(slotWidget)
end

local function stopAllEquipmentAssignSlotHoverPulses()
    forEachEquipmentAssignSlot(function(widget)
        stopEquipmentAssignSlotHoverPulse(widget)
    end)
end

local function clearEquipmentAssignSlotHighlight(slotWidget)
    if not slotWidget or slotWidget:isDestroyed() then
        return
    end
    slotWidget:setBorderWidth(0)
    stopEquipmentAssignSlotHoverPulse(slotWidget)
end

local function showEquipmentAssignSlotValidDrag(slotWidget)
    stopEquipmentAssignSlotHoverPulse(slotWidget)
    slotWidget:setBorderWidth(EQUIPMENT_SLOT_DRAG_BORDER_WIDTH)
    slotWidget:setBorderColor(EQUIPMENT_SLOT_VALID_DRAG_BORDER_COLOR)
end

local function showEquipmentAssignSlotInvalidDrag(slotWidget)
    stopEquipmentAssignSlotHoverPulse(slotWidget)
    slotWidget:setBorderWidth(EQUIPMENT_SLOT_DRAG_BORDER_WIDTH)
    slotWidget:setBorderColor(EQUIPMENT_SLOT_INVALID_DRAG_BORDER_COLOR)
end

local function onEquipmentAssignSlotHoverChange(slotWidget, hovered, invSlot, draggedWidget)
    if isEquipmentAssignVisualBackpackSlot(invSlot) then
        return
    end

    if not hovered then
        clearEquipmentAssignSlotHighlight(slotWidget)
        return
    end

    local draggingWidget = draggedWidget
    if not draggingWidget and g_ui.getDraggingWidget then
        draggingWidget = g_ui.getDraggingWidget()
    end
    local item = equipmentAssignDraggedItem(draggingWidget)

    if item then
        if itemFitsEquipmentAssignSlot(item, invSlot, "drag") then
            if equipmentAssignSlotIsEmpty(invSlot) then
                slotWidget:setBorderWidth(0)
                startEquipmentAssignSlotHoverPulse(slotWidget)
            else
                showEquipmentAssignSlotValidDrag(slotWidget)
            end
        else
            showEquipmentAssignSlotInvalidDrag(slotWidget)
        end
        return
    end

    slotWidget:setBorderWidth(0)
    if equipmentAssignSlotIsEmpty(invSlot) then
        startEquipmentAssignSlotHoverPulse(slotWidget)
    else
        stopEquipmentAssignSlotHoverPulse(slotWidget)
    end
end

local function clearEquipmentAssignSlotTargetHandlers(target)
    if not target then
        return
    end
    target.onHoverChange = nil
    target.onDragEnter = nil
    target.onDragLeave = nil
    target.onDrop = nil
end

local function bindEquipmentAssignSlotTarget(target, slotWidget, invSlot)
    if not target then
        return
    end
    function target:onHoverChange(hovered)
        onEquipmentAssignSlotHoverChange(slotWidget, hovered, invSlot)
    end
    function target:onDragEnter(draggedWidget, mousePos)
        onEquipmentAssignSlotHoverChange(slotWidget, true, invSlot, draggedWidget)
        return true
    end
    function target:onDragLeave(droppedWidget, mousePos)
        onEquipmentAssignSlotHoverChange(slotWidget, false, invSlot)
        return true
    end
    function target:onDrop(draggedWidget, mousePos)
        return onEquipmentAssignSlotDrop(slotWidget, draggedWidget, mousePos, invSlot)
    end
end

local function equipmentAssignRemoveSlot(invSlot)
    if isEquipmentAssignVisualBackpackSlot(invSlot) then return end
    if not equipmentAssignDraft then equipmentAssignDraft = {} end
    equipmentAssignDraft[invSlot] = nil
    if invSlot == InventorySlotLeft or invSlot == InventorySlotRight then
        EAssign.refreshHandSlotWidgets()
    else
        forEachEquipmentAssignSlot(function(widget, slotId)
            if slotId == invSlot then refreshEquipmentAssignSlotWidget(widget, nil) end
        end)
    end
    equipmentAssignUpdateButtons()
end

local function clearEquipmentAssignSlotHandlers()
    forEachEquipmentAssignSlot(function(widget)
        stopEquipmentAssignSlotHoverPulse(widget)
        widget.onMouseRelease = nil
        clearEquipmentAssignSlotTargetHandlers(widget)
        clearEquipmentAssignSlotTargetHandlers(widget:getChildById("slotIcon"))
        clearEquipmentAssignSlotTargetHandlers(widget:recursiveGetChildById("equippedItem"))
    end)
end

local function cancelEquipmentAssignPickMode()
    if equipmentAssignPickInvSlot == nil then
        return
    end
    equipmentAssignPickInvSlot = nil
    if mouseGrabberWidget and not mouseGrabberWidget:isDestroyed() then
        mouseGrabberWidget:ungrabMouse()
    end
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
end

local function startEquipmentAssignChooseItem(invSlot)
    equipAssignDebug(
        "pick start rawInvSlot=%s (%s) normalized=%s",
        tostring(invSlot),
        type(invSlot),
        tostring(normalizeInventorySlot(invSlot))
    )
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed()
        or isEquipmentAssignVisualBackpackSlot(invSlot) or g_ui.isMouseGrabbed() then
        return
    end
    stopAllEquipmentAssignSlotHoverPulses()
    equipmentAssignPickInvSlot = invSlot
    equipmentAssignWindow:hide()
    equipmentAssignHiddenForPick = true
    if not mouseGrabberWidget then
        equipmentAssignPickInvSlot = nil
        restoreEquipmentAssignWindowAfterPick()
        return
    end
    if onDropActionButton then
        mouseGrabberWidget.onMouseRelease = onDropActionButton
    end
    mouseGrabberWidget:grabMouse()
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
end

local function restoreEquipmentAssignWindowAfterPick()
    if not equipmentAssignHiddenForPick then return end
    equipmentAssignHiddenForPick = false
    if equipmentAssignWindow and not equipmentAssignWindow:isDestroyed() then
        equipmentAssignWindow:show()
        equipmentAssignWindow:raise()
        equipmentAssignWindow:focus()
    end
end

local function onEquipmentAssignChooseItemMouseRelease(self, mousePosition, mouseButton)
    local invSlot = equipmentAssignPickInvSlot
    equipAssignDebug(
        "pick release invSlot=%s (%s) mouseButton=%s",
        tostring(invSlot),
        type(invSlot),
        tostring(mouseButton)
    )
    local item
    if mouseButton == MouseLeftButton then
        item = resolvePickItemAtMouse(mousePosition)
        if item then
            equipAssignDebug("pick selected itemId=%s name='%s'", item:getId(), tostring(getEquipmentItemLookupName(item)))
        else
            equipAssignDebug("pick selected item: nil")
        end
        if item and not itemFitsEquipmentAssignSlot(item, invSlot, "pick") then
            modules.game_textmessage.displayFailureMessage(tr("This item is not suitable for this equipment slot."))
            item = nil
        end
    end
    cancelEquipmentAssignPickMode()
    if item then
        equipmentAssignSetSlotItem(invSlot, item, nil)
    end
    restoreEquipmentAssignWindowAfterPick()
    return true
end

function isEquipmentAssignPicking()
    return equipmentAssignPickInvSlot ~= nil
end

function handleEquipmentAssignPickMouseRelease(self, mousePosition, mouseButton)
    if equipmentAssignPickInvSlot == nil then
        return false
    end
    onEquipmentAssignChooseItemMouseRelease(self, mousePosition, mouseButton)
    return true
end

local function onEquipmentAssignSlotMouseRelease(widget, mousePos, mouseButton, invSlot)
    if mouseButton ~= MouseRightButton or isEquipmentAssignVisualBackpackSlot(invSlot) then
        return false
    end
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Select Equipment'), function() startEquipmentAssignChooseItem(invSlot) end)
    local entry = equipmentAssignDraft and equipmentAssignDraft[invSlot]
    if entry and entry.itemId and entry.itemId > 0 then
        menu:addOption(tr('Remove Equipment'), function() equipmentAssignRemoveSlot(invSlot) end)
    end
    menu:display(mousePos)
    return true
end

local function setupEquipmentAssignSlotHandlers()
    forEachEquipmentAssignSlot(function(widget, invSlot)
        if isEquipmentAssignVisualBackpackSlot(invSlot) then
            widget.onMouseRelease = nil
            widget.onDrop = nil
            widget.onHoverChange = nil
            widget:setTooltip(EQUIPMENT_ASSIGN_BACKPACK_TOOLTIP)
            return
        end
        widget:setTooltip(EQUIPMENT_ASSIGN_SLOT_TOOLTIP)
        function widget.onMouseRelease(w, mousePos, button)
            return onEquipmentAssignSlotMouseRelease(w, mousePos, button, invSlot)
        end
        bindEquipmentAssignSlotTarget(widget, widget, invSlot)
        bindEquipmentAssignSlotTarget(widget:getChildById("slotIcon"), widget, invSlot)
        bindEquipmentAssignSlotTarget(widget:recursiveGetChildById("equippedItem"), widget, invSlot)
    end)
end

local function setupEquipmentAssignIconPicker()
    if not equipmentAssignIconWindow or equipmentAssignIconWindow:isDestroyed() then return end
    local panel = equipmentAssignIconWindow:recursiveGetChildById("iconScrollPanel")
    if not panel then return end
    panel:destroyChildren()
    for i = 1, EQUIPMENT_ICON_PICKER_COUNT do
        local btn = g_ui.createWidget("EquipmentIconPickerOption", panel)
        btn.iconIndex = i
        local iconWidget = btn:getChildById("icon")
        applyEquipmentIconToWidget(iconWidget, i)
        btn.onClick = function()
            equipmentAssignIconIndex = i
            refreshEquipmentAssignIconPickerSelection()
            equipmentAssignUpdateButtons()
        end
    end
    refreshEquipmentAssignIconPickerSelection()
end

local function actionSlotEquippedItemMatches(item, itemId, tier)
    if not item or item:getId() ~= itemId then return false end
    if g_game.getFeature(GameThingUpgradeClassification) then
        local itemTier = item.getTier and item:getTier() or 0
        return itemTier == (tier or 0)
    end
    return true
end

local function presetEntryForSlot(cache, invSlot)
    if not cache or not cache.equipments then return nil end
    local entry = cache.equipments[invSlot] or cache.equipments[tostring(invSlot)]
    if entry and entry.itemId and entry.itemId > 0 then return entry end
    return nil
end

function cancelEquipmentSetQueue()
    if pendingEquipmentSetEvent then
        removeEvent(pendingEquipmentSetEvent)
        pendingEquipmentSetEvent = nil
    end
    pendingEquipmentSetActive = false
    pendingEquipmentSetMode = nil
    pendingEquipmentSetCache = nil
    pendingEquipmentSetSteps = 0
end

local function finishEquipmentSetQueue(onComplete)
    pendingEquipmentSetActive = false
    pendingEquipmentSetMode = nil
    pendingEquipmentSetCache = nil
    pendingEquipmentSetSteps = 0
    pendingEquipmentSetEvent = nil
    if onComplete then
        onComplete()
    end
end

local function queueEquipItemAction(itemId, tier)
    return { itemId = itemId, tier = tier or 0 }
end

local function appendPresetEquipSlotActions(actions, player, cache, invSlot)
    local entry = presetEntryForSlot(cache, invSlot)
    if not entry then
        return
    end

    local equipped = player:getInventoryItem(invSlot)
    if actionSlotEquippedItemMatches(equipped, entry.itemId, entry.getTier or 0) then
        return
    end

    if equipped then
        table.insert(actions, queueEquipItemAction(equipped:getId(),
            equipped.getTier and equipped:getTier() or 0))
    end
    table.insert(actions, queueEquipItemAction(entry.itemId, entry.getTier or 0))
end

local function isEquipmentPresetSetWorn(cache)
    if not isEquipmentPresetCache(cache) then
        return false
    end
    local player = g_game.getLocalPlayer()
    if not player or not player.getInventoryItem then
        return false
    end
    local hasPresetEntry = false
    for _, invSlot in ipairs(EQUIPMENT_SET_EQUIP_ORDER) do
        local entry = presetEntryForSlot(cache, invSlot)
        if entry then
            hasPresetEntry = true
            if not actionSlotEquippedItemMatches(player:getInventoryItem(invSlot), entry.itemId, entry.getTier or 0) then
                return false
            end
        end
    end
    return hasPresetEntry
end

local function hasAnyPresetItemEquipped(cache)
    if not isEquipmentPresetCache(cache) then
        return false
    end
    local player = g_game.getLocalPlayer()
    if not player or not player.getInventoryItem then
        return false
    end
    for _, invSlot in ipairs(EQUIPMENT_SET_EQUIP_ORDER) do
        local entry = presetEntryForSlot(cache, invSlot)
        if entry then
            local equipped = player:getInventoryItem(invSlot)
            if equipped and actionSlotEquippedItemMatches(equipped, entry.itemId, entry.getTier or 0) then
                return true
            end
        end
    end
    return false
end

local function isEquipmentSetFullyActive(cache)
    if not isEquipmentPresetCache(cache) then
        return false
    end
    local player = g_game.getLocalPlayer()
    if not player or not player.getInventoryItem then
        return false
    end
    local hasPresetEntry = false
    for _, invSlot in ipairs(EQUIPMENT_SET_EQUIP_ORDER) do
        local entry = presetEntryForSlot(cache, invSlot)
        if entry then
            hasPresetEntry = true
            if not actionSlotEquippedItemMatches(player:getInventoryItem(invSlot), entry.itemId, entry.getTier or 0) then
                return false
            end
        elseif player:getInventoryItem(invSlot) then
            return false
        end
    end
    return hasPresetEntry
end

local function buildEquipmentSetEquipActions(cache)
    local player = g_game.getLocalPlayer()
    if not player then
        return {}
    end
    local actions = {}
    for _, invSlot in ipairs(EQUIPMENT_SET_EQUIP_ORDER) do
        if not presetEntryForSlot(cache, invSlot) then
            local equipped = player:getInventoryItem(invSlot)
            if equipped then
                table.insert(actions, queueEquipItemAction(equipped:getId(),
                    equipped.getTier and equipped:getTier() or 0))
            end
        end
    end
    for _, invSlot in ipairs(EQUIPMENT_SET_EQUIP_ORDER) do
        appendPresetEquipSlotActions(actions, player, cache, invSlot)
    end
    return actions
end

local function buildEquipmentSetUnequipActions(cache)
    local player = g_game.getLocalPlayer()
    if not player then
        return {}
    end
    local actions = {}
    for i = #EQUIPMENT_SET_EQUIP_ORDER, 1, -1 do
        local invSlot = EQUIPMENT_SET_EQUIP_ORDER[i]
        local entry = presetEntryForSlot(cache, invSlot)
        if entry then
            local equipped = player:getInventoryItem(invSlot)
            if equipped and actionSlotEquippedItemMatches(equipped, entry.itemId, entry.getTier or 0) then
                table.insert(actions, queueEquipItemAction(equipped:getId(),
                    equipped.getTier and equipped:getTier() or 0))
            end
        end
    end
    return actions
end

local function equipmentSetNeedsEquip(cache)
    if not isEquipmentPresetCache(cache) then return false end
    local player = g_game.getLocalPlayer()
    if not player or not player.getInventoryItem then return false end
    for _, invSlot in ipairs(EQUIPMENT_SET_EQUIP_ORDER) do
        local entry = presetEntryForSlot(cache, invSlot)
        if entry and not actionSlotEquippedItemMatches(player:getInventoryItem(invSlot), entry.itemId, entry.getTier or 0) then
            return true
        end
        if not entry and player:getInventoryItem(invSlot) then
            return true
        end
    end
    return false
end

local function buildNextEquipmentSetAction(cache, mode)
    if mode == "unequip" then
        local actions = buildEquipmentSetUnequipActions(cache)
        return actions[1]
    end
    local actions = buildEquipmentSetEquipActions(cache)
    return actions[1]
end

local function equipmentSetGoalReached(cache, mode)
    if mode == "unequip" then
        return not hasAnyPresetItemEquipped(cache)
    end
    return not equipmentSetNeedsEquip(cache)
end

local function runEquipmentSetDynamicStep(onComplete)
    local cache = pendingEquipmentSetCache
    local mode = pendingEquipmentSetMode
    if not pendingEquipmentSetActive or not cache or not mode then
        finishEquipmentSetQueue(onComplete)
        return
    end

    if equipmentSetGoalReached(cache, mode) then
        finishEquipmentSetQueue(onComplete)
        return
    end

    pendingEquipmentSetSteps = pendingEquipmentSetSteps + 1
    if pendingEquipmentSetSteps > EQUIP_SET_MAX_STEPS then
        finishEquipmentSetQueue(onComplete)
        return
    end

    local action = buildNextEquipmentSetAction(cache, mode)
    if not action or not action.itemId or action.itemId <= 0 then
        finishEquipmentSetQueue(onComplete)
        return
    end

    g_game.equipItemId(action.itemId, action.tier or 0)
    pendingEquipmentSetEvent = scheduleEvent(function()
        runEquipmentSetDynamicStep(onComplete)
    end, EQUIP_SET_ACTION_DELAY_MS)
end

local function startEquipmentSetDynamicQueue(cache, mode, onComplete)
    if not cache or not mode then
        return false
    end
    cancelEquipmentSetQueue()
    pendingEquipmentSetActive = true
    pendingEquipmentSetCache = cache
    pendingEquipmentSetMode = mode
    pendingEquipmentSetSteps = 0
    runEquipmentSetDynamicStep(onComplete)
    return true
end

function isEquipmentSetOnCooldown()
    return equipmentSetSharedCooldownUntil and g_clock.millis() < equipmentSetSharedCooldownUntil
end

local function forEachEquipmentPresetButton(callback)
    if not callback then return end
    local bars = activeActionBars or actionBars or {}
    for _, actionbar in pairs(bars) do
        if actionbar and actionbar.tabBar then
            for _, button in pairs(actionbar.tabBar:getChildren()) do
                if button.cache and isEquipmentPresetCache(button.cache) then
                    callback(button)
                end
            end
        end
    end
end

local function clearEquipmentPresetCooldownEvents()
    forEachEquipmentPresetButton(function(button)
        if button.cache and button.cache.removeCooldownEvent then
            removeEvent(button.cache.removeCooldownEvent)
            button.cache.removeCooldownEvent = nil
        end
    end)
end

local function startEquipmentSetActionCooldownVisual(button)
    if not button or not button.cooldown or not updateCooldown then
        return
    end
    if button.cache.removeCooldownEvent then
        removeEvent(button.cache.removeCooldownEvent)
        button.cache.removeCooldownEvent = nil
    end
    updateCooldown(button, EQUIPMENT_SET_COOLDOWN_MS)
    button.cache.removeCooldownEvent = scheduleEvent(function()
        if removeCooldown then
            removeCooldown(button)
        end
    end, EQUIPMENT_SET_COOLDOWN_MS)
end

local function startEquipmentSetActionCooldown()
    equipmentSetSharedCooldownUntil = g_clock.millis() + EQUIPMENT_SET_COOLDOWN_MS
    forEachEquipmentPresetButton(startEquipmentSetActionCooldownVisual)
end

function executeEquipmentPreset(button)
    if not button or not button.cache or not isEquipmentPresetCache(button.cache) then
        return false
    end
    if isEquipmentSetOnCooldown() or pendingEquipmentSetActive then return false end
    if not g_game.getLocalPlayer() then return false end

    local mode
    if isEquipmentPresetSetWorn(button.cache) then
        mode = "unequip"
        if #buildEquipmentSetUnequipActions(button.cache) == 0 then
            return false
        end
    elseif equipmentSetNeedsEquip(button.cache) then
        mode = "equip"
        if #buildEquipmentSetEquipActions(button.cache) == 0 then
            return false
        end
    else
        return false
    end

    startEquipmentSetActionCooldown()
    startEquipmentSetDynamicQueue(button.cache, mode, function()
        if button and not button:isDestroyed() and updateButtonState then
            updateButtonState(button)
        end
    end)
    return true
end

function loadEquipmentPresetDisplay(button)
    if not button or not button.item or not button.cache then return end
    button.cache.isEquipmentPreset = true
    button.cache.actionType = UseTypes["Equip"]
    button.item:setItemId(0, true)
    button.item:setOn(true)
    button.item:setChecked(false)
    if button.item.gray then button.item.gray:setVisible(false) end
    if button.item.text then
        button.item.text:setText("")
        if isEquipmentPresetCache(button.cache) and normalizeEquipmentIconIndex(button.cache.equipmentIconIndex) > 0 then
            button.item.text:setImageSource(EQUIPMENT_ICONS_SHEET)
            button.item.text:setImageClip(equipmentIconClip(button.cache.equipmentIconIndex))
        else
            button.item.text:setImageSource("")
            button.item.text:setImageClip("0 0 0 0")
        end
    end
    if button.item.setDisplayCount and button.item.clearDisplayCount then
        button.item:clearDisplayCount()
    end
    refreshActionBarEquipmentTypeIcon(button)
    updateButtonState(button)
end

function isEquipmentAssignBlockingItemMove()
    return equipmentAssignWindow ~= nil and not equipmentAssignWindow:isDestroyed()
end

function openEquipmentAssignWindow(button)
    if not button then return end
    if closeAllAssignWindows then closeAllAssignWindows('equipment') end
    closeEquipmentAssignWindow()
    equipmentAssignButton = button
    equipmentAssignWindow = g_ui.loadUI('/modules/game_actionbar/assign_equipment', g_ui.getRootWidget())
    if equipmentAssignWindow then
        equipmentAssignWindow:raise()
        equipmentAssignWindow:focus()
    end
    copyEquipmentAssignDraft(button.cache and button.cache.equipments or nil)
    copyEquipmentAssignMetaFromButton(button)
    refreshAllEquipmentAssignSlots()
    setupEquipmentAssignSlotHandlers()
    refreshAssignActionSlotPreview()
    equipmentAssignUpdateButtons()
end

function openEquipmentAssignIconWindow()
    if not equipmentAssignWindow or equipmentAssignWindow:isDestroyed() then return end
    stopAllEquipmentAssignSlotHoverPulses()
    closeEquipmentAssignIconWindow(false)
    equipmentAssignIconPickerRevertIndex = equipmentAssignIconIndex
    equipmentAssignIconPickerRevertDescription = equipmentAssignDescription
    equipmentAssignTypePickerRevertIndex = equipmentAssignTypeIndex
    equipmentAssignWindow:hide()
    equipmentAssignHiddenForIconPicker = true
    equipmentAssignIconWindow = g_ui.loadUI('/modules/game_actionbar/assign_equipment_icon', g_ui.getRootWidget())
    if not equipmentAssignIconWindow then
        equipmentAssignHiddenForIconPicker = false
        equipmentAssignWindow:show()
        return
    end
    equipmentAssignIconWindow:raise()
    equipmentAssignIconWindow:focus()
    local edit = equipmentAssignIconWindow:recursiveGetChildById("descriptionTextEdit")
    if edit then edit:setText(equipmentAssignDescription or "") end
    setupEquipmentAssignIconPicker()
    setupEquipmentAssignTypePicker()
end

function closeEquipmentAssignIconWindow(revert)
    if not equipmentAssignIconWindow then return end
    if revert then
        equipmentAssignIconIndex = equipmentAssignIconPickerRevertIndex
        equipmentAssignDescription = equipmentAssignIconPickerRevertDescription
        equipmentAssignTypeIndex = equipmentAssignTypePickerRevertIndex
        refreshAssignActionSlotPreview()
        equipmentAssignUpdateButtons()
    end
    destroyEquipmentAssignTypeRadioGroup()
    equipmentAssignIconWindow:destroy()
    equipmentAssignIconWindow = nil
    if equipmentAssignHiddenForIconPicker then
        equipmentAssignHiddenForIconPicker = false
        if equipmentAssignWindow and not equipmentAssignWindow:isDestroyed() then
            equipmentAssignWindow:show()
            equipmentAssignWindow:raise()
            equipmentAssignWindow:focus()
        end
    end
end

function equipmentAssignIconOk()
    if equipmentAssignIconWindow then
        local edit = equipmentAssignIconWindow:recursiveGetChildById("descriptionTextEdit")
        if edit then equipmentAssignDescription = edit:getText() or "" end
        if equipmentAssignTypeRadioGroup then
            local selected = equipmentAssignTypeRadioGroup:getSelectedWidget()
            if selected and selected.typeIndex ~= nil then
                equipmentAssignTypeIndex = selected.typeIndex
            end
        end
    end
    closeEquipmentAssignIconWindow(false)
    refreshAssignActionSlotPreview()
    equipmentAssignUpdateButtons()
end

function closeEquipmentAssignWindow()
    stopAllEquipmentAssignSlotHoverPulses()
    cancelEquipmentAssignPickMode()
    clearEquipmentAssignSlotHandlers()
    closeEquipmentAssignIconWindow(false)
    equipmentAssignHiddenForPick = false
    equipmentAssignHiddenForIconPicker = false
    if equipmentAssignWindow and not equipmentAssignWindow:isDestroyed() then
        equipmentAssignWindow:destroy()
    end
    equipmentAssignWindow = nil
    equipmentAssignDraft = nil
    equipmentAssignButton = nil
    equipmentAssignIconIndex = EQUIPMENT_ICON_UNDETERMINED_INDEX
    equipmentAssignDescription = ""
    equipmentAssignTypeIndex = 0
end

function resetEquipmentAssignRuntimeState()
    cancelEquipmentSetQueue()
    equipmentSetSharedCooldownUntil = nil
    clearEquipmentPresetCooldownEvents()
end

function resetEquipmentAssignOnGameEnd()
    resetEquipmentAssignRuntimeState()
end

function resetEquipmentAssignOnModuleTerminate()
    resetEquipmentAssignRuntimeState()
end

local function applyEquipmentAssign(closeAfter)
    local button = equipmentAssignButton
    if not button or not isEquipmentAssignIconDetermined() then
        if closeAfter then closeEquipmentAssignWindow() end
        return
    end
    local barID, buttonID = string.match(button:getId(), "^(%d+)%.(%d+)$")
    if not barID or not buttonID then return end
    if closeCurrentMultiActionPanel then closeCurrentMultiActionPanel() end
    if ApiJson.removeMultiAction then
        ApiJson.removeMultiAction(tonumber(barID), tonumber(buttonID))
    end
    local equipments = {}
    for invSlot, entry in pairs(equipmentAssignDraft or {}) do
        if not isEquipmentAssignVisualBackpackSlot(invSlot) and entry and entry.itemId and entry.itemId > 0 then
            equipments[invSlot] = {
                itemId = entry.itemId,
                getTier = entry.getTier,
                subType = entry.subType
            }
        end
    end
    ApiJson.createOrUpdateEquipmentAction(tonumber(barID), tonumber(buttonID), equipments,
        normalizeEquipmentIconIndex(equipmentAssignIconIndex),
        equipmentAssignDescription or "",
        normalizeEquipmentTypeIndex(equipmentAssignTypeIndex))
    updateButton(button)
    if closeAfter then closeEquipmentAssignWindow() end
end

function equipmentAssignApply()
    applyEquipmentAssign(false)
end

function equipmentAssignOk()
    applyEquipmentAssign(true)
end

function equipmentAssignCopyCurrentSet()
    local player = g_game.getLocalPlayer()
    if not player then return end
    equipmentAssignDraft = {}
    forEachEquipmentAssignSlot(function(widget, invSlot)
        if isEquipmentAssignVisualBackpackSlot(invSlot) then return end
        local entry = equipmentEntryFromItem(player:getInventoryItem(invSlot))
        if entry then equipmentAssignDraft[invSlot] = entry end
    end)
    refreshAllEquipmentAssignSlots()
    equipmentAssignUpdateButtons()
end

function assignEquipment(button)
    openEquipmentAssignWindow(button)
end

function equipmentPresetTooltip(cache)
    if cache.equipmentDescription and cache.equipmentDescription ~= "" then
        return cache.equipmentDescription
    end
    return tr("Equipment set")
end
