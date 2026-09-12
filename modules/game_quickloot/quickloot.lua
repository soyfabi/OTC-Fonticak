QuickLoot = {}

local function showModal(widget)
    if g_modalManager then
        g_modalManager.show(widget)
    end
end

local function hideModal(widget)
    if g_modalManager then
        g_modalManager.hide(widget)
    end
end

local CLEAR_ICON = "/images/ui/button-clear-20x20-up.png"
local CHAINED_CLEAR_ICON = "/modules/game_quickloot/images/button-chain-clear-20x20-up.png"

local function getQuickLootFilterItemName(itemId)
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if not thingType then
		return ""
	end

	local marketData = thingType:getMarketData()
	if marketData and marketData.name and marketData.name ~= "" then
		return marketData.name:lower()
	end

	local name = thingType:getName()
	if name and name ~= "" then
		return name:lower()
	end

	return ""
end

function QuickLoot.getConfiguredLootFlags(itemId)
	if not itemId or itemId <= 0 then
		return 0, 0
	end

	local lootFlags, obtainFlags = 0, 0

	for _, container in ipairs(QuickLoot.lootContainers or {}) do
		local category = container[1]
		local obtainId = container[2]
		local lootId = container[3]
		local bitFlag = bit.lshift(1, category)

		if lootId == itemId then
			lootFlags = bit.bor(lootFlags, bitFlag)
		end

		if obtainId == itemId then
			obtainFlags = bit.bor(obtainFlags, bitFlag)
		end
	end

	return lootFlags, obtainFlags
end

local function refreshSlotQuickLootIcon(slotWidget, item)
	if not slotWidget then
		return
	end

	local icon = slotWidget.quickloot or slotWidget:getChildById("quickloot")
	if not icon then
		return
	end

	local show = false
	local tooltip = ""

	if item and item:isContainer() then
		local lootFlags, obtainFlags = QuickLoot.getConfiguredLootFlags(item:getId())
		show = lootFlags ~= 0 or obtainFlags ~= 0

		if show and QuickLoot.getQuickLootIconTooltip then
			tooltip = QuickLoot.getQuickLootIconTooltip(lootFlags, obtainFlags)
		end
	end

	icon:setVisible(show)
	icon:setTooltip(tooltip)
end

function QuickLoot.refreshAllQuickLootIcons()
	if modules.game_inventory and modules.game_inventory.refreshInventoryQuickLootIcons then
		modules.game_inventory.refreshInventoryQuickLootIcons()
	end

	if modules.game_containers and modules.game_containers.refreshAllContainerQuickLootIcons then
		modules.game_containers.refreshAllContainerQuickLootIcons()
	end
end

local function upsertLootContainerSlot(categoryId, field, value)
	QuickLoot.lootContainers = QuickLoot.lootContainers or {}

	for _, container in ipairs(QuickLoot.lootContainers) do
		if container[1] == categoryId then
			if field == "obtain" then
				container[2] = value
			elseif field == "loot" then
				container[3] = value
			end

			return
		end
	end

	table.insert(QuickLoot.lootContainers, {
		categoryId,
		field == "obtain" and value or 0,
		field == "loot" and value or 0
	})
end

local function updateManageContainerRow(parent, actionsId, item)
	if not parent or not item then
		return
	end

	local itemId = item:getId()
	local categoryId = tonumber(parent:getId())

	if actionsId == 0 then
		parent.item2:setItem(item)
		parent.removeBag2:setEnabled(true)
		parent.removeBag2:setIcon(CLEAR_ICON)
		upsertLootContainerSlot(categoryId, "loot", itemId)
	elseif actionsId == SET_OBTAIN_CONTAINER_ACTION then
		parent.item:setItem(item)
		parent.removeBag:setEnabled(true)
		parent.removeBag:setIcon(CLEAR_ICON)
		upsertLootContainerSlot(categoryId, "obtain", itemId)
	end
end

local function applyQuickLootFilterSlotVisuals(slotWidget, itemOrId)
    if not slotWidget then
        return
    end

    local itemUi = slotWidget.item

    if not itemUi or itemUi:getClassName() ~= "UIItem" then
        itemUi = slotWidget:getChildById("item")
    end

    if not itemUi then
        return
    end

    local rarityWidget = slotWidget.rarity or slotWidget:getChildById("rarity")

    if type(itemOrId) == "number" then
        if itemOrId > 0 then
            itemUi:setItemId(itemOrId)
        else
            itemUi:setItemId(0)
        end
    elseif itemOrId then
        itemUi:setVirtual(false)
        itemUi:setItem(itemOrId)
    else
        itemUi:setItemId(0)
    end

    local item = itemUi:getItem()

    if rarityWidget then
        if item and item:getId() > 0 then
            ItemsDatabase.setRarityItem(rarityWidget, item)
            ItemsDatabase.syncRarityWidgetVisibility(rarityWidget)
        else
            ItemsDatabase.setRarityItem(rarityWidget, nil)
            rarityWidget:setVisible(false)
        end

        ItemsDatabase.applyContainerRarityStackOrder(slotWidget)
    end
end

local GOLD_POUCH_ITEM_ID = 23721
local SET_OBTAIN_CONTAINER_ACTION = 4

local function getFilter(id)
    local filter = {
        [1] = 0,
        [2] = 1
    }

    return filter[id]
end

local QUICKLOOT_CATEGORY_NAMES = {
    "Armors",
    "Amulets",
    "Boots",
    "Containers",
    "Decoration",
    "Food",
    "Helmets\nand Hats",
    "Legs",
    "Others",
    "Potions",
    "Rings",
    "Runes",
    "Shields",
    "Tools",
    "Valuables",
    "Weapons:\nAmmo",
    "Weapons:\nAxes",
    "Weapons:\nClubs",
    "Weapons:\nDistance",
    "Weapons:\nSwords",
    "Weapons:\nWands",
    nil,
    nil,
    "Creature\nProducts",
    "Quivers",
    nil,
    "Weapons:\nFist",
    nil,
    nil,
    "Gold",
    "Unassigned"
}

local function quickLootBuildIconTooltip(lootFlags, obtainFlags)
    lootFlags = lootFlags or 0
    obtainFlags = obtainFlags or 0

    if lootFlags == 0 and obtainFlags == 0 then
        return ""
    end

    local function collectSortedNames(flags)
        local list = {}

        for i = 0, 31 do
            if bit.band(flags, bit.lshift(1, i)) ~= 0 then
                local raw = QUICKLOOT_CATEGORY_NAMES[i]

                if raw then
                    table.insert(list, (raw:gsub("\n", " ")))
                end
            end
        end

        table.sort(list)

        return list
    end

    local lines = {}

    if lootFlags ~= 0 then
        table.insert(lines, (tr("Loot container for:")))

        for _, name in ipairs(collectSortedNames(lootFlags)) do
            table.insert(lines, name)
        end
    end

    if obtainFlags ~= 0 then
        if #lines > 0 then
            table.insert(lines, "")
        end

        table.insert(lines, (tr("Obtain container for:")))

        for _, name in ipairs(collectSortedNames(obtainFlags)) do
            table.insert(lines, name)
        end
    end

    return table.concat(lines, "\n")
end

quickLootController = Controller:new()

quickLootController:setUI("quickloot")

function quickLootController:onInit()
    QuickLoot.Define()

    QuickLoot.data = {
        filter = 1,
        loots = {
            [0] = {},
            {}
        }
    }
    QuickLoot.getQuickLootIconTooltip = quickLootBuildIconTooltip

    quickLootController.ui:hide()
    quickLootController:registerEvents(g_game, {
        onQuickLootContainers = QuickLoot.start
    })
    Keybind.new("Loot", "Quick Loot Nearby Corpses", "Alt+Q", "")
    Keybind.bind("Loot", "Quick Loot Nearby Corpses", {
        {
            type = KEY_DOWN,
            callback = function()
                g_game.sendQuickLoot(2)
            end
        }
    })
    g_game.openContainerQuickLoot(3, nil, {}, nil, nil, true)
end

function quickLootController:onTerminate()
    Keybind.delete("Loot", "Quick Loot Nearby Corpses")

    if QuickLoot.mouseGrabberWidget then
        QuickLoot.mouseGrabberWidget:destroy()

        QuickLoot.mouseGrabberWidget = nil
    end

    if QuickLoot.invalidLootContainerWindow then
        hideModal(QuickLoot.invalidLootContainerWindow)
        QuickLoot.invalidLootContainerWindow:destroy()

        QuickLoot.invalidLootContainerWindow = nil
    end

    if quickLootController.ui then
        hideModal(quickLootController.ui)
    end

    QuickLoot = {}
    QuickLoot.getQuickLootIconTooltip = quickLootBuildIconTooltip
end

function quickLootController:onGameStart()
    if not g_game.isQuickLootEnabled() then
        return
    end

    QuickLoot.getQuickLootIconTooltip = quickLootBuildIconTooltip

    if not QuickLoot.mouseGrabberWidget then
        QuickLoot.mouseGrabberWidget = g_ui.createWidget("UIWidget")
    end

    QuickLoot.mouseGrabberWidget:setVisible(false)
    QuickLoot.mouseGrabberWidget:setFocusable(false)

    QuickLoot.mouseGrabberWidget.onMouseRelease = QuickLoot.onChooseItem
    QuickLoot.lastSelectBag = nil

    quickLootController.ui.information.vipPanel.premium:setOn(not g_game.getLocalPlayer():isPremium())
    QuickLoot.load()
    g_game.requestQuickLootBlackWhiteList(getFilter(QuickLoot.data.filter), #QuickLoot.data.loots[QuickLoot.data.filter], QuickLoot.data.loots[QuickLoot.data.filter])
    scheduleEvent(function()
        QuickLoot.refreshAllQuickLootIcons()
    end, 100)
end

function quickLootController:onGameEnd()
    if not g_game.isQuickLootEnabled() then
        return
    end

    QuickLoot.save()
    QuickLoot.toggle()

    if QuickLoot.invalidLootContainerWindow then
        hideModal(QuickLoot.invalidLootContainerWindow)
        QuickLoot.invalidLootContainerWindow:destroy()

        QuickLoot.invalidLootContainerWindow = nil
    end

    if quickLootController.ui:isVisible() then
        hideModal(quickLootController.ui)
        quickLootController.ui:hide()
    end
end

function QuickLoot.Define()
    function QuickLoot.filter(widget, isChecked)
        widget:setChecked(true)

        isChecked = true

        local accepted = quickLootController.ui.filters.accepted
        local skipped = quickLootController.ui.filters.skipped
        local add_text = string.format("Add to %s Loot List", widget:getId():gsub("^%l", string.upper))
        local clear_text = string.format("Clear %s Loot List", widget:getId():gsub("^%l", string.upper))

        if widget == skipped and isChecked then
            quickLootController.ui.filters.accepted:setChecked(false)
            quickLootController.ui.filters.add:setText(add_text)
            quickLootController.ui.filters.clear:setText(clear_text)

            QuickLoot.data.filter = 1
        end

        if widget == accepted and isChecked then
            quickLootController.ui.filters.skipped:setChecked(false)
            quickLootController.ui.filters.add:setText(add_text)
            quickLootController.ui.filters.clear:setText(clear_text)

            QuickLoot.data.filter = 2
        end

        g_game.requestQuickLootBlackWhiteList(getFilter(QuickLoot.data.filter), #QuickLoot.data.loots[QuickLoot.data.filter], QuickLoot.data.loots[QuickLoot.data.filter])
        QuickLoot.loadFilterItems()
    end

    function QuickLoot.lootExists(itemId, filter)
        filter = filter or QuickLoot.data.filter

        return table.contains(QuickLoot.data.loots[filter], itemId)
    end

    function QuickLoot.addLootList(itemId, filter)
        filter = filter or QuickLoot.data.filter

        if table.contains(QuickLoot.data.loots[filter], itemId) then
            return
        end

        table.insert(QuickLoot.data.loots[filter], itemId)
        g_game.requestQuickLootBlackWhiteList(getFilter(filter), #QuickLoot.data.loots[filter], QuickLoot.data.loots[filter])

        if quickLootController.ui:isVisible() then
            QuickLoot.loadFilterItems()
        end
    end

    function QuickLoot.clearFilterItems()
        QuickLoot.data.loots[QuickLoot.data.filter] = {}

        g_game.requestQuickLootBlackWhiteList(getFilter(QuickLoot.data.filter), #QuickLoot.data.loots[QuickLoot.data.filter], QuickLoot.data.loots[QuickLoot.data.filter])
        QuickLoot.loadFilterItems()
    end

    function QuickLoot.removeLootList(itemId, filter)
        filter = filter or QuickLoot.data.filter

        if not table.contains(QuickLoot.data.loots[filter], itemId) then
            return
        end

        table.removevalue(QuickLoot.data.loots[filter], itemId)
        g_game.requestQuickLootBlackWhiteList(getFilter(filter), #QuickLoot.data.loots[filter], QuickLoot.data.loots[filter])

        if quickLootController.ui:isVisible() then
            QuickLoot.loadFilterItems()
        end
    end

    function QuickLoot.load()
        local file = string.format("/settings/%s_containers.json", g_game.getLocalPlayer():getName():lower():gsub("%s+", "_"))

        if g_resources.fileExists(file) then
            local status, result = pcall(function()
                return json.decode(g_resources.readFileContents(file))
            end)

            if not status then
                return g_logger.error("Error while reading containers settings file. " .. result)
            end

            if result == nil then
                QuickLoot.data = {
                    filter = 1,
                    loots = {
                        {},
                        {}
                    }
                }
            else
                QuickLoot.data = result
            end
        else
            QuickLoot.data = {
                filter = 1,
                loots = {
                    {},
                    {}
                }
            }
        end
    end

    function QuickLoot.save()
        local file = string.format("/settings/%s_containers.json", g_game.getLocalPlayer():getName():lower():gsub("%s+", "_"))
        local status, result = pcall(function()
            return json.encode(QuickLoot.data, 2)
        end)

        if not status then
            return g_logger.warning("Error while saving QuickLoot settings. Data won't be saved. Details: " .. result)
        end

        if result:len() > 104857600 then
            return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
        end

        local writeStatus, writeError = pcall(function()
            return g_resources.writeFileContents(file, result)
        end)

        if not writeStatus then
            g_logger.debug("Could not save QuickLoot settings during logout: " .. tostring(writeError))
        end
    end

    function QuickLoot.start(quickLootFallbackToMainContainer, lootContainers)
        local player = g_game.getLocalPlayer()
        local vipPanel = quickLootController.ui.information.vipPanel
        local loots = lootContainers
        local fallback = quickLootFallbackToMainContainer

        QuickLoot.lastQuickLootFallback = fallback
        QuickLoot.lootContainers = {}

        if lootContainers then
            for i, container in ipairs(lootContainers) do
                QuickLoot.lootContainers[i] = {
                    container[1],
                    container[2],
                    container[3]
                }
            end
        end

        QuickLoot.loadFilterItems()

        local filter = {
            [1] = "skipped",
            [2] = "accepted"
        }

        QuickLoot.filter(quickLootController.ui.filters[filter[QuickLoot.data.filter]], true)
        quickLootController.ui.list:getLayout():disableUpdates()
        quickLootController.ui.list:destroyChildren()
        quickLootController.ui.fallbackPanel.checkbox:setChecked(fallback)

        local slotBags = {
            { name = "Unassigned", type = 31, color = "#484848" },
            { name = "Gold", type = 30, color = "#414141" },
            { name = "Armors", type = 1, color = "#484848" },
            { name = "Amulets", type = 2, color = "#414141" },
            { name = "Boots", type = 3, color = "#484848" },
            { name = "Containers", type = 4, color = "#414141" },
            { name = "Creature\nProducts", type = 24, color = "#484848" },
            { name = "Decoration", type = 5, color = "#414141" },
            { name = "Food", type = 6, color = "#484848" },
            { name = "Helmets\nand Hats", type = 7, color = "#414141" },
            { name = "Legs", type = 8, color = "#484848" },
            { name = "Others", type = 9, color = "#414141" },
            { name = "Potions", type = 10, color = "#414141" },
            { name = "Rings", type = 11, color = "#484848" },
            { name = "Runes", type = 12, color = "#414141" },
            { name = "Shields", type = 13, color = "#484848" },
            { name = "Tools", type = 14, color = "#414141" },
            { name = "Valuables", type = 15, color = "#484848" },
            { name = "Weapons:\nAmmo", type = 16, color = "#414141" },
            { name = "Weapons:\nAxes", type = 17, color = "#484848" },
            { name = "Weapons:\nClubs", type = 18, color = "#414141" },
            { name = "Weapons:\nDistance", type = 19, color = "#484848" },
            { name = "Weapons:\nFist", type = 27, color = "#414141" },
            { name = "Weapons:\nSwords", type = 20, color = "#484848" },
            { name = "Weapons:\nWands", type = 21, color = "#414141" },
            { name = "Quivers", type = 25, color = "#484848" }
        }

        for _, slot in ipairs(slotBags) do
            local hasItem = false
            local hasItem2 = false
            local widget = g_ui.createWidget("QuicklootBagLabel", quickLootController.ui.list)
            local id = slot.type and slot.type or 0

            widget:setId(id)
            widget:setBackgroundColor(slot.color)
            widget.label:setText(slot.name)

            for _, container in pairs(lootContainers) do
                if container[1] == id then
                    local lootContainerId = container[3]
                    local obtainerContainerId = container[2]

                    if lootContainerId and lootContainerId > 0 then
                        widget.item:setItemId(lootContainerId)
                    else
                        widget.item:setItemId(0)
                    end

                    if obtainerContainerId and obtainerContainerId > 0 then
                        widget.item2:setItemId(obtainerContainerId)
                    else
                        widget.item2:setItemId(0)
                    end

					if lootContainerId and lootContainerId > 0 then
						hasItem = true
					end

					if obtainerContainerId and obtainerContainerId > 0 then
						hasItem2 = true
					end

					break
				end
			end

			if not hasItem then
                widget.removeBag:setEnabled(false)
                widget.removeBag:setIcon(CHAINED_CLEAR_ICON)
            else
                widget.removeBag:setEnabled(true)
                widget.removeBag:setIcon(CLEAR_ICON)
            end

            if not hasItem2 then
                widget.removeBag2:setEnabled(false)
                widget.removeBag2:setIcon(CHAINED_CLEAR_ICON)
            else
                widget.removeBag2:setEnabled(true)
                widget.removeBag2:setIcon(CLEAR_ICON)
            end
        end

		quickLootController.ui.list:getLayout():enableUpdates()
		quickLootController.ui.list:getLayout():update()

		QuickLoot.refreshAllQuickLootIcons()
	end

    function QuickLoot.loadFilterItems()
        quickLootController.ui.ignoreList:destroyChildren()

        local color = "#484848"

        for _, itemId in ipairs(QuickLoot.data.loots[QuickLoot.data.filter]) do
            local widget = g_ui.createWidget("QuicLootIgnoreItem", quickLootController.ui.ignoreList)

            widget:setId(itemId)
            widget:setBackgroundColor(color)
            widget.label:setText(getQuickLootFilterItemName(itemId))
            applyQuickLootFilterSlotVisuals(widget.itemSlot, itemId)

            color = color == "#484848" and "#414141" or "#484848"
        end
    end

    function QuickLoot.search(text)
        text = text:lower():trim()

        quickLootController.ui.ignoreList:destroyChildren()

        if text == "" then
            QuickLoot.loadFilterItems()

            return
        end

        local color = "#484848"

        for _, itemId in ipairs(QuickLoot.data.loots[QuickLoot.data.filter]) do
            local itemName = getQuickLootFilterItemName(itemId)

            if itemName:find(text, 1, true) then
                local widget = g_ui.createWidget("QuicLootIgnoreItem", quickLootController.ui.ignoreList)

                widget:setId(itemId)
                widget:setBackgroundColor(color)
                widget.label:setText(itemName)
                applyQuickLootFilterSlotVisuals(widget.itemSlot, itemId)

                color = color == "#484848" and "#414141" or "#484848"
            end
        end
    end

    function QuickLoot.clearSearch()
        local search = quickLootController.ui.search

        search:clearText()
    end

    function QuickLoot.fallback(widget, isChecked)
        g_game.openContainerQuickLoot(3, nil, {}, nil, nil, isChecked)
    end

    function QuickLoot:chooseItem()
        if g_ui.isMouseGrabbed() then
            return
        end

        QuickLoot.mouseGrabberWidget:grabMouse()
        if modules.client_options and modules.client_options.getOption('nativeCursor') then
            g_window.setSystemCursor('cross')
        else
            g_mouse.pushCursor("target")
        end

        QuickLoot.lastSelectBag = self:getParent()
        QuickLoot.actionsId = self.Select

        hideModal(quickLootController.ui)
        quickLootController.ui:hide()
    end

    function QuickLoot:onChooseItem(mousePosition, mouseButton)
        local item
        local userClickedSomething = false
        local validSelection = false
        local invalidSelectionMessage

        if mouseButton == MouseLeftButton then
            local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)

            if clickedWidget then
                if clickedWidget:getClassName() == "UIGameMap" then
                    local tile = clickedWidget:getTile(mousePosition)

                    if tile then
                        local thing = tile:getTopMoveThing()

                        if thing then
                            userClickedSomething = true
                        end
                    end
                elseif clickedWidget:getClassName() == "UIItem" and not clickedWidget:isVirtual() then
                    local clickedItem = clickedWidget:getItem()

                    if clickedItem then
                        userClickedSomething = true

                        local pos = clickedItem:getPosition()
                        local inInventory = pos and pos.x == 65535
                        local isGoldPouchForObtain = clickedItem:getId() == GOLD_POUCH_ITEM_ID and QuickLoot.actionsId == SET_OBTAIN_CONTAINER_ACTION

                        if isGoldPouchForObtain then
                            invalidSelectionMessage = tr("You can only set the Gold Pouch as a loot container.")
                        elseif clickedItem:isContainer() and inInventory then
                            item = clickedItem
                            validSelection = true

                            updateManageContainerRow(QuickLoot.lastSelectBag, QuickLoot.actionsId, item)
                            g_game.openContainerQuickLoot(QuickLoot.actionsId, QuickLoot.lastSelectBag:getId(), item:getPosition(), item:getId(), item:getStackPos())
                            QuickLoot.refreshAllQuickLootIcons()
                        end
                    end
                end
            end
        end

        if modules.client_options and modules.client_options.getOption('nativeCursor') then
            g_window.restoreMouseCursor()
        else
            g_mouse.popCursor("target")
        end
        self:ungrabMouse()

        if userClickedSomething and not validSelection then
            QuickLoot.showInvalidLootContainerError(invalidSelectionMessage)
        elseif quickLootController.ui then
            quickLootController.ui:show()
            showModal(quickLootController.ui)
        end

        return true
    end

    function QuickLoot.showInvalidLootContainerError(message)
        if QuickLoot.invalidLootContainerWindow then
            return
        end

        if quickLootController.ui then
            hideModal(quickLootController.ui)
            quickLootController.ui:hide()
        end

        local window = g_ui.createWidget("InvalidLootContainerWindow", rootWidget)

        if message then
            window.errorMessage:setText(message)
        end

        QuickLoot.invalidLootContainerWindow = window

        showModal(window)
    end

    function QuickLoot.hideInvalidLootContainerError()
        local window = QuickLoot.invalidLootContainerWindow

        QuickLoot.invalidLootContainerWindow = nil

        if window then
            hideModal(window)
            window:destroy()
        end

        if quickLootController.ui then
            quickLootController.ui:show()
            showModal(quickLootController.ui)
        end
    end

    function QuickLoot:openContainer()
        for _, container in pairs(g_game.getContainers()) do
            if container:getContainerItem():getId() == self:getItemId() then
                return false
            end
        end

        g_game.openContainerQuickLoot(self.click, self:getParent():getId(), {}, nil, nil, nil)

        return true
    end

	function QuickLoot:clearItem()
		local parent = self:getParent()

		local categoryId = tonumber(parent:getId())

		if self.borrar == 1 then
			parent.item2:setItemId(0)
			parent.removeBag2:setEnabled(false)
			parent.removeBag2:setIcon(CHAINED_CLEAR_ICON)
			upsertLootContainerSlot(categoryId, "loot", 0)
		else
			parent.item:setItemId(0)
			parent.removeBag:setEnabled(false)
			parent.removeBag:setIcon(CHAINED_CLEAR_ICON)
			upsertLootContainerSlot(categoryId, "obtain", 0)
		end

		g_game.openContainerQuickLoot(self.borrar, parent:getId(), {}, nil, nil, nil)
		QuickLoot.refreshAllQuickLootIcons()
	end

    function QuickLoot:clearFilterItem()
        local parent = self:getParent()
        local itemUi = parent.itemSlot and parent.itemSlot.item

        if itemUi then
            QuickLoot.removeLootList(itemUi:getItemId())
        end

        QuickLoot.loadFilterItems()
    end

    function QuickLoot.toggle()
        if not quickLootController.ui then
            return
        end

        if quickLootController.ui:isVisible() then
            return QuickLoot.hide()
        end

        QuickLoot.show()
        QuickLoot.loadFilterItems()

        if QuickLoot.data.filter == 2 and not quickLootController.ui.filters.accepted:isChecked() then
            quickLootController.ui.filters.accepted:onClick()
        end
    end

    function QuickLoot.show()
        if not quickLootController.ui then
            return
        end

        quickLootController.ui:show()
        showModal(quickLootController.ui)
    end

    function QuickLoot.hide()
        if not quickLootController.ui then
            return
        end

        hideModal(quickLootController.ui)
        quickLootController.ui:hide()
    end
end
