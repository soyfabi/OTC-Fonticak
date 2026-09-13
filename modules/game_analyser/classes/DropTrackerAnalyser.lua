-- Add capitalize function to string library (force override)
function string.capitalize(str)
    if not str or str == "" then
        return str
    end
    
    -- Split by spaces, capitalize each word, then join back
    local words = {}
    for word in str:gmatch("%S+") do
        if word:len() > 0 then
            -- Convert word to lowercase, then capitalize first letter
            local lowerWord = word:lower()
            local capitalizedWord = lowerWord:sub(1, 1):upper() .. lowerWord:sub(2)
            table.insert(words, capitalizedWord)
        end
    end
    
    return table.concat(words, " ")
end

-- Missing utility functions
local function formatMoney(value, separator)
    return comma_value(tostring(value))
end

local function getItemServerName(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return "Unknown Item"
	end

	if modules.game_market and modules.game_market.getMarketItemName then
		local marketName = modules.game_market.getMarketItemName(itemId)
		if marketName and marketName ~= "" and marketName ~= tostring(itemId) then
			return marketName
		end
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType then
		local marketData = thingType:getMarketData()
		if marketData and marketData.name and marketData.name ~= "" then
			return marketData.name
		end

		local name = thingType:getName()
		if name and name ~= "" and name ~= "unnamed" then
			return name
		end
	end

	return "Item #" .. tostring(itemId)
end

local DROP_TRACKER_ITEM_NAME_COLOR = "#F6F6F6"

local function setDropTrackerItemName(label, text)
	if not label then
		return
	end

	if label.setColoredText then
		label:setColoredText({ text, DROP_TRACKER_ITEM_NAME_COLOR })
	else
		label:setText(text)
		label:setColor(DROP_TRACKER_ITEM_NAME_COLOR)
	end
end

local function getCharacterDir()
	if not LoadedPlayer then
		return nil
	end

	LoadedPlayer:cacheFromLocalPlayer()
	return LoadedPlayer:ensureCharacterDir()
end

local function readDropTrackerJsonFile(filePath)
	if not filePath or not g_resources.fileExists(filePath) then
		return nil
	end

	local status, result = pcall(function()
		return json.decode(g_resources.readFileContents(filePath))
	end)

	if status and type(result) == "table" then
		return result
	end

	return nil
end

local function buildTrackedItemEntry(itemId, entry)
	return {
		monsterDrop = {},
		recordStartTimestamp = entry and entry.recordStartTimestamp or os.time(),
		dropCount = entry and entry.dropCount or 0,
		persistent = true,
	}
end

local function mergeTrackedItemsFromConfig(trackedItems, config, preserveSession)
	for _, entry in ipairs((config and config.trackedItems) or {}) do
		local itemId = tonumber(entry.objectType) or entry.objectType
		if itemId then
			local existing = trackedItems[itemId]
			if preserveSession and existing then
				existing.persistent = true
			else
				trackedItems[itemId] = buildTrackedItemEntry(itemId, entry)
			end
		end
	end
end

local function mergeTrackedItemsFromDropTrackerMap(trackedItems, dropTrackerItems, preserveSession)
	for itemIdStr, isTracked in pairs(dropTrackerItems or {}) do
		if isTracked then
			local itemId = tonumber(itemIdStr)
			if itemId and (not preserveSession or not trackedItems[itemId]) then
				trackedItems[itemId] = buildTrackedItemEntry(itemId)
			elseif itemId and trackedItems[itemId] then
				trackedItems[itemId].persistent = true
			end
		end
	end
end

local function resolveDropTrackerItemPanel(widget)
	if not widget then
		return nil
	end

	widget.itemSlot = widget.itemSlot or widget:getChildById("itemSlot")
	widget.itemName = widget.itemName or widget:getChildById("itemName")
	widget.drops = widget.drops or widget:getChildById("drops")
	widget.dropMonster = widget.dropMonster or widget:getChildById("dropMonster")

	return widget
end

local function resolveDropTrackerContents()
	local window = DropTrackerAnalyser and DropTrackerAnalyser.window
	if not window then
		return nil, nil
	end

	local contentsPanel = window.contentsPanel or window:getChildById("contentsPanel")
	if not contentsPanel then
		return nil, nil
	end

	local dropItems = contentsPanel.dropItems or contentsPanel:getChildById("dropItems")
	return contentsPanel, dropItems
end

local function short_text(text, maxLength)
    if not text then
        return ""
    end
    if string.len(text) > maxLength then
        return text:sub(1, maxLength - 3) .. "..."
    end
    return text
end

local function normalizeMonsterName(monsterName)
    return (monsterName or ""):lower()
end

local function findMonsterDropEntry(monsterDropList, monsterName)
    local normalizedName = normalizeMonsterName(monsterName)
    for _, entry in ipairs(monsterDropList) do
        if normalizeMonsterName(entry.monsterName) == normalizedName then
            return entry
        end
    end
    return nil
end

local function addOrMergeMonsterDrop(tracker, monsterName, monsterOutfit, count)
    local existing = findMonsterDropEntry(tracker.monsterDrop, monsterName)
    if existing then
        existing.count = existing.count + count
        existing.time = os.time()
        if monsterOutfit then
            existing.outfit = monsterOutfit
        end
        return existing
    end

    local entry = {
        monsterName = monsterName,
        outfit = monsterOutfit,
        time = os.time(),
        count = count
    }
    tracker.monsterDrop[#tracker.monsterDrop + 1] = entry
    return entry
end

local function consolidateMonsterDrops(monsterDropList)
    local merged = {}
    local order = {}

    for _, entry in ipairs(monsterDropList) do
        local key = normalizeMonsterName(entry.monsterName)
        if merged[key] then
            merged[key].count = merged[key].count + entry.count
            merged[key].time = math.max(merged[key].time, entry.time)
            if entry.outfit then
                merged[key].outfit = entry.outfit
            end
        else
            merged[key] = {
                monsterName = entry.monsterName,
                outfit = entry.outfit,
                time = entry.time,
                count = entry.count
            }
            order[#order + 1] = key
        end
    end

    local result = {}
    for _, key in ipairs(order) do
        result[#result + 1] = merged[key]
    end
    return result
end

if not DropTrackerAnalyser then
	DropTrackerAnalyser = {
		launchTime = 0,
		session = 0,

		trackedItems = {},

		autoTrackAboveValue = 0,

		-- private
		window = nil,
	}
	DropTrackerAnalyser.__index = DropTrackerAnalyser
end

function DropTrackerAnalyser:create()
	DropTrackerAnalyser.window = openedWindows['dropButton']
	
	if not DropTrackerAnalyser.window then
		return
	end

	-- Hide buttons we don't want
	local toggleFilterButton = DropTrackerAnalyser.window:recursiveGetChildById('toggleFilterButton')
	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
	end
	
	local newWindowButton = DropTrackerAnalyser.window:recursiveGetChildById('newWindowButton')
	if newWindowButton then
		newWindowButton:setVisible(false)
	end

	-- Position contextMenuButton where toggleFilterButton was (to the left of minimize button)
	local contextMenuButton = DropTrackerAnalyser.window:recursiveGetChildById('contextMenuButton')
	local minimizeButton = DropTrackerAnalyser.window:recursiveGetChildById('minimizeButton')
	
	if contextMenuButton and minimizeButton then
		contextMenuButton:setVisible(true)
		contextMenuButton:breakAnchors()
		contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
		contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
		contextMenuButton:setMarginRight(7)  -- Same margin as toggleFilterButton had
		contextMenuButton:setMarginTop(0)
		
		-- Set up contextMenuButton click handler to show our menu
		contextMenuButton.onClick = function(widget, mousePos)
			local pos = mousePos or g_window.getMousePosition()
			return onDropTrackerExtra(pos)
		end
	end

	-- Position lockButton to the left of contextMenuButton
	local lockButton = DropTrackerAnalyser.window:recursiveGetChildById('lockButton')
	
	if lockButton and contextMenuButton then
		lockButton:setVisible(true)
		lockButton:breakAnchors()
		lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
		lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
		lockButton:setMarginRight(2)  -- Same margin as in miniwindow style
		lockButton:setMarginTop(0)
	end

	DropTrackerAnalyser.launchTime = g_clock.millis()
	DropTrackerAnalyser.session = 0

	DropTrackerAnalyser.window.onOpen = function()
		DropTrackerAnalyser:loadConfigJson(true)
	end
end

function DropTrackerAnalyser:refreshFromDisk()
	self:loadConfigJson(true)
end

function DropTrackerAnalyser:managerDropItem(itemId, shouldTrack)
	if shouldTrack then
		-- Add item to tracking
		if not DropTrackerAnalyser.trackedItems[itemId] then
			DropTrackerAnalyser.trackedItems[itemId] = {
				monsterDrop = {},
				recordStartTimestamp = os.time(),
				dropCount = 0,
				persistent = true
			}
		else
			-- Make sure existing tracked item is persistent
			DropTrackerAnalyser.trackedItems[itemId].persistent = true
		end
	else
		-- Remove item from tracking
		if DropTrackerAnalyser.trackedItems[itemId] then
			DropTrackerAnalyser.trackedItems[itemId] = nil
		end
	end
	
	-- Update the display
	DropTrackerAnalyser:updateWindow(true)
	
	-- Save the configuration
	DropTrackerAnalyser:saveConfigJson()
end

function DropTrackerAnalyser:checkTracker()
	local needUpdate = false
	for itemId, config in pairs(DropTrackerAnalyser.trackedItems) do
		if not config.persistent and (os.time() - config.recordStartTimestamp > 120) then
			DropTrackerAnalyser.trackedItems[itemId] = nil
			needUpdate = true
		else
			-- check monstertracker
			for id, mInfo in ipairs(config.monsterDrop) do
				if (os.time() - mInfo.time) > 45 then
					needUpdate = true
				end
			end
		end
	end

	if needUpdate then
		DropTrackerAnalyser:updateWindow(true)
	end
end

function DropTrackerAnalyser:reset(isLogin)
	DropTrackerAnalyser.launchTime = g_clock.millis()
	DropTrackerAnalyser.session = 0
	if isLogin then
		return
	end

	DropTrackerAnalyser.autoTrackAboveValue = 0

	for itemId, config in pairs(DropTrackerAnalyser.trackedItems) do
		if config.monsterDrop then
			config.monsterDrop = {}
		end
		-- Reset drop count and update timestamp for new session
		config.dropCount = 0
		config.recordStartTimestamp = os.time()
	end

	DropTrackerAnalyser:updateWindow(true)
end

function DropTrackerAnalyser:updateWindow(ignoreVisible)
	if not DropTrackerAnalyser.window then
		return
	end

	if not DropTrackerAnalyser.window:isVisible() and not ignoreVisible then
		return
	end

	local contentsPanel, dropItems = resolveDropTrackerContents()
	if not contentsPanel or not dropItems then
		return
	end

	-- lets loop through all the items and flag them for removal
	for _, widget in pairs(dropItems:getChildren()) do
		resolveDropTrackerItemPanel(widget)
		widget.toBeRemoved = true
		if widget.dropMonster then
			for _, monsterWidget in pairs(widget.dropMonster:getChildren()) do
				monsterWidget.toBeRemoved = true
			end
		end
	end

	for itemId, config in pairs(DropTrackerAnalyser.trackedItems) do
		if config.monsterDrop and #config.monsterDrop > 1 then
			config.monsterDrop = consolidateMonsterDrops(config.monsterDrop)
			for _, monsterDrop in ipairs(config.monsterDrop) do
				monsterDrop.widget = nil
			end
		end

		local widget = dropItems:getChildById("ItemPanel_" .. itemId)
		if not widget then
			-- unable to find the item, then it most likely is a
			-- new item being tracked, so lets create it
			widget = g_ui.createWidget("DropTrackerItemPanel", dropItems)
			widget:setId("ItemPanel_" .. itemId)
			resolveDropTrackerItemPanel(widget)
			if not widget.itemSlot or not widget.itemName or not widget.drops or not widget.dropMonster then
				g_logger.error("DropTrackerAnalyser: failed to create item panel for item " .. tostring(itemId))
				widget:destroy()
			else
				widget.itemSlot:setItemId(itemId)
				setDropTrackerItemName(
					widget.itemName,
					string.capitalize(short_text(getItemServerName(itemId), 13))
				)
				widget.drops:setText(formatMoney(config.dropCount, ","))

				-- Add right-click context menu
				widget.onMousePress = function(self, mousePos, mouseButton)
					if mouseButton == MouseRightButton then
						DropTrackerAnalyser:showItemContextMenu(self, mousePos, itemId)
						return true
					end
					return false
				end

				for _, monsterDrop in ipairs(config.monsterDrop) do
					local monsterWidget = g_ui.createWidget("DropTrackerMonsterPanel", widget.dropMonster)
					monsterWidget.monster:setOutfit(monsterDrop.outfit)
					local capitalizedName = string.capitalize(monsterDrop.monsterName)
					monsterWidget.name:setText(capitalizedName)
					monsterWidget.drops:setText("(" .. formatMoney(monsterDrop.count, ",") .. ")")
					monsterDrop.widget = monsterWidget
				end

				widget:updateItemPanelSize()
			end
		else
			resolveDropTrackerItemPanel(widget)
			if not widget.itemSlot or not widget.itemName or not widget.drops or not widget.dropMonster then
				widget:destroy()
				DropTrackerAnalyser:updateWindow(ignoreVisible)
				return
			end

			-- if we found the item, and applied updates to it, must must
			-- check it to not be removed
			widget.drops:setText(formatMoney(config.dropCount, ","))
			widget.toBeRemoved = nil

			-- Ensure right-click context menu is available
			if not widget.onMousePress then
				widget.onMousePress = function(self, mousePos, mouseButton)
					if mouseButton == MouseRightButton then
						DropTrackerAnalyser:showItemContextMenu(self, mousePos, itemId)
						return true
					end
					return false
				end
			end

			local toBeRemoved = {}
			for id, monsterDrop in ipairs(config.monsterDrop) do
				local monsterWidget = monsterDrop.widget
				if not monsterWidget then
					-- if there is no monsterWidget set, then we need to create it
					monsterWidget = g_ui.createWidget("DropTrackerMonsterPanel", widget.dropMonster)
					monsterWidget.monster:setOutfit(monsterDrop.outfit)
					local capitalizedName = string.capitalize(monsterDrop.monsterName)
					monsterWidget.name:setText(capitalizedName)
					monsterWidget.drops:setText("(" .. formatMoney(monsterDrop.count, ",") .. ")")
					-- we also save the reference for later on use
					monsterDrop.widget = monsterWidget
				else
					-- if the monsterWidget is already set, then we must check
					-- if it needs to be removed (time > 45s)
					if (os.time() - monsterDrop.time) > 45 then
						-- this is already being done in the
						-- initial part of this function
						-- monsterWidget.toBeRemoved = true

						-- but lets keep track of the ids to
						-- be removed later on (outside of this
						-- loop)
						table.insert(toBeRemoved, id)
					else
						monsterWidget.toBeRemoved = nil
						local capitalizedName = string.capitalize(monsterDrop.monsterName)
						monsterWidget.name:setText(capitalizedName)
						monsterWidget.drops:setText("(" .. formatMoney(monsterDrop.count, ",") .. ")")
					end
				end
			end

			if #toBeRemoved == 0 then
				-- dont need to do the update of the heights
				-- now, since it will be done later on during
				-- the widget removal
				widget:updateItemPanelSize()
			end

			-- there is no need to keep it on monsterDrop
			-- table if its removal was already scheduled
			-- and by keeping it, it would be re-added eventually
			for _, id in ipairs(toBeRemoved) do
				table.remove(config.monsterDrop, id)
			end
		end
	end

	for _, widget in pairs(dropItems:getChildren()) do
		if widget.toBeRemoved then
			widget:destroy()
		end

		if widget.dropMonster then
			local destroyedAtLeastOne = false
			for _, monsterWidget in pairs(widget.dropMonster:getChildren()) do
				if monsterWidget.toBeRemoved then
					monsterWidget:destroy()
					destroyedAtLeastOne = true
				end
			end

			if destroyedAtLeastOne then
				widget:updateItemPanelSize()
			end
		end
	end
end

function DropTrackerAnalyser:sendDropedItems(consoleMessage)
    -- Now that textmessage.lua handles colored formatting for ValuableLoot,
    -- we can use the same colored message for both screen and console
    if g_game.isOnline() then
        modules.game_textmessage.displayMessage(MessageModes.ValuableLoot, consoleMessage)
    end
end

function DropTrackerAnalyser:tryAddingMonsterDrop(item, monsterName, monsterOutfit, dropItems, dropedItems)
	local itemId = item:getId()
	local tracker = DropTrackerAnalyser.trackedItems[itemId]
	local itemPrice = item:getMeanPrice() and item:getMeanPrice() or 0
	
	-- Check if item is explicitly tracked
	if tracker then
		-- Item is explicitly being tracked
		dropedItems[#dropedItems + 1] = itemId
		tracker.dropCount = tracker.dropCount + item:getCount()
		tracker.recordStartTimestamp = os.time()
		addOrMergeMonsterDrop(tracker, monsterName, monsterOutfit, item:getCount())
		return
	end
	
	-- Check if item should be auto-tracked based on value
	if DropTrackerAnalyser.autoTrackAboveValue > 0 and itemPrice >= DropTrackerAnalyser.autoTrackAboveValue then
		-- Auto-track this valuable item (non-persistent)
		DropTrackerAnalyser.trackedItems[itemId] = {monsterDrop = {}, recordStartTimestamp = os.time(), dropCount = 0, persistent = false}
		tracker = DropTrackerAnalyser.trackedItems[itemId]
		
		dropedItems[#dropedItems + 1] = itemId
		tracker.dropCount = tracker.dropCount + item:getCount()
		tracker.recordStartTimestamp = os.time()
		addOrMergeMonsterDrop(tracker, monsterName, monsterOutfit, item:getCount())
	end
end

function DropTrackerAnalyser:checkMonsterKilled(monsterName, monsterOutfit, dropItems)
	if table.empty(DropTrackerAnalyser.trackedItems) and DropTrackerAnalyser.autoTrackAboveValue == 0 then
		return true
	end

	local dropedItems = {}
	for _, item in pairs(dropItems) do
		DropTrackerAnalyser:tryAddingMonsterDrop(item, monsterName, monsterOutfit, dropItems, dropedItems)
	end

	if #dropedItems ~= 0 then
		local consoleMessage = "{Valuable loot:, #f0b400}"
		
		local first = true
		for _, itemId in pairs(dropedItems) do
			local name = getItemServerName(itemId)
			-- Ensure we have valid data before processing
			if not name or name == "" then
				name = "Unknown Item"
			end
			if not itemId or itemId == 0 then
				itemId = 0
			end
			
			if not first then
				consoleMessage = consoleMessage .. "{,, #f0b400}"
			else
				first = false
			end
			
			-- Use the server loot message format that ItemsDatabase.setColorLootMessage expects
			consoleMessage = consoleMessage .. "{ , #f0b400}{" .. itemId .. "|" .. name .. "}"
		end

		consoleMessage = consoleMessage .. "{ dropped by " .. monsterName .. "!, #f0b400}"
		
		DropTrackerAnalyser:sendDropedItems(consoleMessage)
	end

	if not table.empty(dropedItems) then
		DropTrackerAnalyser:updateWindow(true)
	end

	return true
end

function DropTrackerAnalyser:isInDropTracker(itemId)
	local tracker = DropTrackerAnalyser.trackedItems[itemId]
	return tracker and tracker.persistent
end

function DropTrackerAnalyser:removeItem(itemId)
	if DropTrackerAnalyser.trackedItems[itemId] then
		DropTrackerAnalyser.trackedItems[itemId] = nil
	end

	if Cyclopedia and Cyclopedia.Items then
		if Cyclopedia.Items.removeFromDropTrackerDirectly then
			Cyclopedia.Items.removeFromDropTrackerDirectly(itemId)
		end
		if Cyclopedia.Items.refreshCurrentItem then
			Cyclopedia.Items.refreshCurrentItem()
		end
	end
	
	-- Update the display
	DropTrackerAnalyser:updateWindow(true)
	
	-- Save the configuration
	DropTrackerAnalyser:saveConfigJson()
end

function DropTrackerAnalyser:removeAllItems()
	DropTrackerAnalyser.trackedItems = {}

	if Cyclopedia and Cyclopedia.Items then
		if Cyclopedia.Items.removeAllFromDropTrackerDirectly then
			Cyclopedia.Items.removeAllFromDropTrackerDirectly()
		end
		if Cyclopedia.Items.refreshCurrentItem then
			Cyclopedia.Items.refreshCurrentItem()
		end
	end
	
	-- Update the display
	DropTrackerAnalyser:updateWindow(true)
	
	-- Save the configuration
	DropTrackerAnalyser:saveConfigJson()
end

function DropTrackerAnalyser:showItemContextMenu(widget, mousePos, itemId)
	local menu = g_ui.createWidget('PopupMenu')
	
	menu:addOption('Remove', function()
		DropTrackerAnalyser:removeItem(itemId)
	end)
	
	menu:addOption('Remove All', function()
		DropTrackerAnalyser:removeAllItems()
	end)
	
	menu:display(mousePos)
end

function onDropTrackerExtra(mousePosition)
	local window = getConfigPopupWindow("dropButton")
	if not window then return end
	window:show()
	window:setText('Drop Tracker Configuration')
	window.contentPanel.text:setImageSource('/images/game/analyzer/labels/loot-track')

	window.onEnter = function()
		local value = window.contentPanel.target:getText()
		DropTrackerAnalyser.autoTrackAboveValue = tonumber(value)
		window:hide()
	end
	window.contentPanel.target:setText(tonumber(DropTrackerAnalyser.autoTrackAboveValue) or '0')

	window.contentPanel.ok.onClick = function()
		local value = window.contentPanel.target:getText()
		DropTrackerAnalyser.autoTrackAboveValue = tonumber(value)
		window:hide()
	end
	window.contentPanel.cancel.onClick = function()
		window:hide()
	end
end


function DropTrackerAnalyser:loadConfigJson(preserveSession)
	local characterDir = getCharacterDir()
	if not characterDir then
		return false
	end

	local config = readDropTrackerJsonFile(characterDir .. "/itemtracking.json") or {
		autoTrackAboveValue = 0,
		trackedItems = {},
	}
	local prices = readDropTrackerJsonFile(characterDir .. "/itemprices.json")

	if preserveSession then
		mergeTrackedItemsFromConfig(DropTrackerAnalyser.trackedItems, config, true)
		if prices and prices.dropTrackerItems then
			mergeTrackedItemsFromDropTrackerMap(DropTrackerAnalyser.trackedItems, prices.dropTrackerItems, true)
		end
	else
		table.clear(DropTrackerAnalyser.trackedItems)
		mergeTrackedItemsFromConfig(DropTrackerAnalyser.trackedItems, config, false)
		if prices and prices.dropTrackerItems then
			mergeTrackedItemsFromDropTrackerMap(DropTrackerAnalyser.trackedItems, prices.dropTrackerItems, false)
		end
	end

	if preserveSession then
		DropTrackerAnalyser.autoTrackAboveValue = config.autoTrackAboveValue
			or DropTrackerAnalyser.autoTrackAboveValue
			or 0
	else
		DropTrackerAnalyser.autoTrackAboveValue = config.autoTrackAboveValue or 0
	end
	DropTrackerAnalyser:updateWindow(true)

	if Cyclopedia and Cyclopedia.Items and Cyclopedia.Items.refreshCurrentItem then
		Cyclopedia.Items.refreshCurrentItem()
	end

	if not table.empty(DropTrackerAnalyser.trackedItems) then
		DropTrackerAnalyser:saveConfigJson()
		if Cyclopedia and Cyclopedia.Items and Cyclopedia.Items.syncDropTrackerItemsFromAnalyser then
			Cyclopedia.Items.syncDropTrackerItemsFromAnalyser()
		end
	end

	return not table.empty(DropTrackerAnalyser.trackedItems)
end

function DropTrackerAnalyser:saveConfigJson()
	local config = {
		autoTrackAboveValue = DropTrackerAnalyser.autoTrackAboveValue,
		trackedItems = {},
	}

	for itemId, insta in pairs(DropTrackerAnalyser.trackedItems) do
		if insta.persistent then
			config.trackedItems[#config.trackedItems + 1] = {
				dropCount = insta.dropCount or 0,
				objectType = tonumber(itemId) or itemId,
				recordStartTimestamp = insta.recordStartTimestamp or os.time(),
			}
		end
	end

	local characterDir = getCharacterDir()
	if not characterDir then
		return
	end

	local file = characterDir .. "/itemtracking.json"

	if #config.trackedItems == 0 then
		local existing = readDropTrackerJsonFile(file)
		if existing and type(existing.trackedItems) == "table" and #existing.trackedItems > 0 then
			return
		end

		local prices = readDropTrackerJsonFile(characterDir .. "/itemprices.json")
		if prices and prices.dropTrackerItems and not table.empty(prices.dropTrackerItems) then
			return
		end
	end

	local status, result = pcall(function() return json.encode(config, 2) end)
	if not status then
		return g_logger.error("Error while saving profile DropTracker data. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end

	local writeStatus, writeError = pcall(function()
		return g_resources.writeFileContents(file, result)
	end)
	
	if not writeStatus then
		g_logger.error("Error while writing itemtracking.json. Details: " .. tostring(writeError))
	end
end

