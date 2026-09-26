Cyclopedia = Cyclopedia or {}

local DETAIL_LABEL_COLUMN_WIDTH = 150
local DETAIL_ROW_HEIGHT = 20
local ensureCyclopediaTabContent

local function measureDetailRowHeight(value, valueWidth)
	if not Cyclopedia.detailMeasureLabel then
		Cyclopedia.detailMeasureLabel = g_ui.createWidget("Label", g_ui.getRootWidget())
		Cyclopedia.detailMeasureLabel:setVisible(false)
		Cyclopedia.detailMeasureLabel:setPhantom(true)
	end

	local label = Cyclopedia.detailMeasureLabel
	label:setFont("Verdana Bold-11px")
	label:setTextAutoResize(false)
	label:setTextWrap(true)
	label:setWidth(valueWidth)
	label:setText(value or "")

	return math.max(DETAIL_ROW_HEIGHT, label:getTextSize().height + 2)
end

function Cyclopedia.appendDetailKeyValueRow(parent, key, value)
	local row = g_ui.createWidget("UIWidget", parent)
	row:setPhantom(true)

	local parentWidth = parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight()
	if parentWidth <= 0 and parent.getParent then
		local scrollArea = parent:getParent()
		if scrollArea then
			parentWidth = scrollArea:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight() - 8
		end
	end
	if parentWidth <= 0 then
		parentWidth = 425
	end

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

function Cyclopedia.appendDetailCenteredRow(parent, key, value)
	local row = g_ui.createWidget("UIWidget", parent)
	row:setPhantom(true)

	local parentWidth = parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight()
	if parentWidth <= 0 and parent.getParent then
		local scrollArea = parent:getParent()
		if scrollArea then
			parentWidth = scrollArea:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight() - 16
		end
	end
	if parentWidth <= 0 then
		parentWidth = 425
	end

	local text = string.format("%s: %s", key, value)
	local rowHeight = measureDetailRowHeight(text, parentWidth - 8)

	row:setWidth(parentWidth)
	row:setHeight(rowHeight)

	local label = g_ui.createWidget("Label", row)
	label:setText(text)
	label:setColor("#C0C0C0")
	label:setFont("Verdana Bold-11px")
	label:setTextAlign(AlignCenter)
	label:setTextAutoResize(false)
	label:setTextWrap(true)
	label:setWidth(parentWidth)
	label:setHeight(rowHeight)
	label:addAnchor(AnchorLeft, "parent", AnchorLeft)
	label:addAnchor(AnchorTop, "parent", AnchorTop)
end

local OFFENCE_STAT_FONT = "Verdana Bold-11px-new"
local OFFENCE_VALUE_COLUMN_WIDTH = 60
local OFFENCE_STAT_ROW_HEIGHT = 16
local OFFENCE_STAT_COLUMN_GAP = 6
local OFFENCE_SUB_ROW_INDENT = 38
local OFFENCE_CHILD_INDENT = 20

local function formatOffencePercentDisplay(display)
	local absVal = math.abs(display)
	local rounded = math.floor(absVal + 1e-06)
	local isWhole = math.abs(absVal - rounded) < 1e-06
	local formatted

	if isWhole then
		formatted = string.format("%d%%", rounded)
	else
		local numberText = string.format("%.2f", absVal)

		numberText = numberText:gsub("0+$", ""):gsub("%.$", "")
		formatted = numberText .. "%"
	end

	if display > 0 then
		return "+" .. formatted
	elseif display < 0 then
		return "-" .. formatted
	end

	return formatted
end

local function formatOffenceStatValue(value, percent)
	local numericValue = tonumber(value) or 0

	if percent then
		return formatOffencePercentDisplay(numericValue * 100)
	end

	return tostring(numericValue)
end

local function getOffencePanelWidth(parent)
	local parentWidth = parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight()

	if parentWidth <= 0 then
		parentWidth = 230
	end

	return parentWidth
end

function Cyclopedia.appendOffenceStatHeaderRow(parent, text, options)
	options = options or {}

	local row = g_ui.createWidget("Label", parent)

	row:setPhantom(true)
	row:setColor("#C0C0C0")
	row:setFont(OFFENCE_STAT_FONT)
	row:setTextAlign(AlignTopLeft)
	row:setTextAutoResize(true)
	row:setText(text or "")

	if options.indent then
		row:setMarginLeft(OFFENCE_SUB_ROW_INDENT)
	end

	if options.marginLeft then
		row:setMarginLeft(options.marginLeft)
	end

	if options.marginTop then
		row:setMarginTop(options.marginTop)
	end

	return row
end

function Cyclopedia.appendOffenceStatPrincipalRow(parent, name, value, options)
	options = options or {}

	local numericValue = tonumber(value) or 0

	if numericValue == 0 and not options.showZero then
		return nil
	end

	local row = g_ui.createWidget("UIWidget", parent)

	row:setPhantom(not options.blessButton)

	local parentWidth = getOffencePanelWidth(parent)

	row:setWidth(parentWidth)
	row:setHeight(options.height or OFFENCE_STAT_ROW_HEIGHT)

	if options.marginLeft then
		row:setMarginLeft(options.marginLeft)
	end

	if options.marginTop then
		row:setMarginTop(options.marginTop)
	end

	local nameLabel = g_ui.createWidget("Label", row)

	nameLabel:setPhantom(true)
	nameLabel:setColor("#C0C0C0")
	nameLabel:setFont(OFFENCE_STAT_FONT)
	nameLabel:setTextAlign(AlignTopLeft)
	nameLabel:setTextAutoResize(true)
	nameLabel:setText(name or "")
	nameLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
	nameLabel:addAnchor(AnchorTop, "parent", AnchorTop)

	local valueText = options.valueText or formatOffenceStatValue(value, options.percent)
	local valueRightMargin = options.valueMarginRight or 0

	if options.element and Cyclopedia.clientCombat and Cyclopedia.clientCombat[options.element] then
		local iconMarginRight = options.iconMarginRight or -8
		local valueIconGap = options.valueIconGap or 6
		local iconSize = 9
		local icon = g_ui.createWidget("SkillCharacterIcon", row)

		icon:setPhantom(true)
		icon:setMarginTop(2)
		icon:setMarginRight(iconMarginRight)
		icon:addAnchor(AnchorRight, "parent", AnchorRight)

		local element = Cyclopedia.clientCombat[options.element]

		icon:setImageSource(element.path)
		icon:setImageSize({
			width = iconSize,
			height = iconSize
		})

		valueRightMargin = iconMarginRight + iconSize + valueIconGap
	end

	if options.blessButton then
		local buttonMarginRight = options.blessButtonMarginRight or 0
		local button = g_ui.createWidget("CyclopediaBlessButton", row)

		button:addAnchor(AnchorRight, "parent", AnchorRight)
		button:addAnchor(AnchorTop, "parent", AnchorTop)
		button:setMarginTop(options.blessButtonMarginTop or 2)

		if buttonMarginRight ~= 0 then
			button:setMarginRight(buttonMarginRight)
		end

		local blessingImages = {
			[2] = "/images/inventory/button_blessings_gold",
			[3] = "/images/inventory/button_blessings_green"
		}
		local player = g_game.getLocalPlayer()
		local status = player and player.getBlessingsIconColor and player:getBlessingsIconColor() or 0

		button:setImageSource(blessingImages[status] or "/images/inventory/button_blessings_grey")

		function button.onClick()
			if modules.game_blessing and modules.game_blessing.openFromCyclopedia then
				modules.game_blessing.openFromCyclopedia()
			elseif modules.game_blessing and modules.game_blessing.toggle then
				modules.game_blessing.toggle()
			end
		end

		valueRightMargin = buttonMarginRight + 12 + (options.blessButtonGap or 3)
	end

	local valueLabel = g_ui.createWidget("Label", row)

	valueLabel:setPhantom(true)
	valueLabel:setColor(options.color or "#C0C0C0")
	valueLabel:setFont(OFFENCE_STAT_FONT)
	valueLabel:setTextAlign(AlignTopRight)
	valueLabel:setTextAutoResize(true)
	valueLabel:setText(valueText)
	valueLabel:addAnchor(AnchorRight, "parent", AnchorRight)
	valueLabel:addAnchor(AnchorTop, "parent", AnchorTop)

	if valueRightMargin ~= 0 then
		valueLabel:setMarginRight(valueRightMargin)
	end

	return row
end

function Cyclopedia.appendOffenceStatRow(parent, value, description, options)
	options = options or {}

	local numericValue = tonumber(value) or 0

	if numericValue == 0 and not options.showZero then
		return nil
	end

	local row = g_ui.createWidget("UIWidget", parent)

	row:setPhantom(true)

	local parentWidth = getOffencePanelWidth(parent)
	local valueColumnWidth = options.valueColumnWidth or OFFENCE_VALUE_COLUMN_WIDTH
	local descriptionWidth = parentWidth - valueColumnWidth - OFFENCE_STAT_COLUMN_GAP
	local rowHeight = options.height or OFFENCE_STAT_ROW_HEIGHT

	row:setWidth(parentWidth)
	row:setHeight(rowHeight)

	local rowIndent = options.marginLeft

	if rowIndent == nil and options.indent ~= false then
		rowIndent = OFFENCE_SUB_ROW_INDENT
	end

	if rowIndent then
		row:setMarginLeft(rowIndent)
	end

	if options.marginTop then
		row:setMarginTop(options.marginTop)
	end

	local valueText = options.valueText or formatOffenceStatValue(value, options.percent)
	local valueLabel = g_ui.createWidget("Label", row)

	valueLabel:setPhantom(true)
	valueLabel:setColor("#C0C0C0")
	valueLabel:setFont(OFFENCE_STAT_FONT)
	valueLabel:setTextAlign(AlignTopRight)
	valueLabel:setTextAutoResize(false)
	valueLabel:setWidth(valueColumnWidth)
	valueLabel:setHeight(rowHeight)
	valueLabel:setText(valueText)
	valueLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
	valueLabel:addAnchor(AnchorTop, "parent", AnchorTop)

	local descriptionLabel = g_ui.createWidget("Label", row)

	descriptionLabel:setPhantom(true)
	descriptionLabel:setColor("#C0C0C0")
	descriptionLabel:setFont(OFFENCE_STAT_FONT)
	descriptionLabel:setTextAlign(AlignTopLeft)
	descriptionLabel:setTextAutoResize(false)
	descriptionLabel:setWidth(descriptionWidth)
	descriptionLabel:setHeight(rowHeight)
	descriptionLabel:setText(description or "")
	descriptionLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
	descriptionLabel:addAnchor(AnchorTop, "parent", AnchorTop)
	descriptionLabel:setMarginLeft(valueColumnWidth + OFFENCE_STAT_COLUMN_GAP + (options.descriptionIndent or 0))

	return row
end

function Cyclopedia.renderOffenceStatBlock(panel, block)
	if not panel or not block then
		return
	end

	local principalValue = block.principal and tonumber(block.principal.value) or 0
	local hasItemValue = false

	for _, item in ipairs(block.items or {}) do
		if (tonumber(item.value) or 0) ~= 0 or item.showZero then
			hasItemValue = true
			break
		end
	end

	local hasTypeItemValue = false

	for _, section in ipairs(block.typeSections or {}) do
		for _, item in ipairs(section.items or {}) do
			if (tonumber(item.value) or 0) ~= 0 then
				hasTypeItemValue = true
				break
			end
		end

		if hasTypeItemValue then
			break
		end
	end

	if block.principal and principalValue == 0 and not hasItemValue and not hasTypeItemValue and not block.header and not block.subheader and not block.principal.showZero then
		return
	end

	if block.header then
		Cyclopedia.appendOffenceStatHeaderRow(panel, block.header, block.headerOptions)
	end

	if block.principal and (principalValue ~= 0 or block.principal.showZero or block.principal.blessButton or block.principal.valueText) then
		Cyclopedia.appendOffenceStatPrincipalRow(panel, block.principal.name, block.principal.value, block.principal)
	end

	if block.subheader then
		Cyclopedia.appendOffenceStatHeaderRow(panel, block.subheader, {
			indent = true
		})
	end

	for _, item in ipairs(block.items or {}) do
		Cyclopedia.appendOffenceStatRow(panel, item.value, item.description, {
			marginLeft = item.marginLeft,
			marginTop = item.marginTop,
			percent = item.percent,
			valueText = item.valueText,
			valueColumnWidth = item.valueColumnWidth,
			descriptionIndent = item.descriptionIndent,
			height = item.height,
			indent = item.indent,
			showZero = item.showZero
		})
	end

	for _, section in ipairs(block.typeSections or {}) do
		local hasTypeItem = false

		for _, item in ipairs(section.items or {}) do
			if (tonumber(item.value) or 0) ~= 0 then
				hasTypeItem = true
				break
			end
		end

		if hasTypeItem then
			if section.subheader then
				Cyclopedia.appendOffenceStatHeaderRow(panel, section.subheader, {
					marginLeft = section.marginLeft or OFFENCE_CHILD_INDENT,
					marginTop = section.marginTop
				})
			end

			for _, item in ipairs(section.items or {}) do
				local itemOptions = {
					marginLeft = item.marginLeft or section.itemMarginLeft,
					marginTop = item.marginTop or section.itemMarginTop,
					percent = item.percent,
					valueText = item.valueText,
					valueColumnWidth = item.valueColumnWidth,
					descriptionIndent = item.descriptionIndent,
					height = item.height,
					indent = item.indent,
					showZero = item.showZero
				}

				Cyclopedia.appendOffenceStatRow(panel, item.value, item.description, itemOptions)
			end
		end
	end
end

local function onCyclopediaItemDetail(data, legacyDescriptions)
	local itemId, descriptions = data, legacyDescriptions

	if type(data) == "table" then
		itemId = data.item and data.item:getId() or 0
		descriptions = data.descriptions or {}
	end

	if itemId and itemId ~= 0 and Cyclopedia.handleCharacterItemDetail and Cyclopedia.handleCharacterItemDetail(itemId, descriptions) then
		return
	end

	if Cyclopedia and Cyclopedia.receiveItemDetail and Cyclopedia.receiveItemDetail(data) then
		return
	end
end

local function onCyclopediaItemDetails(itemId)
	if Cyclopedia and Cyclopedia.Items and Cyclopedia.Items.onServerItemDetails then
		Cyclopedia.Items.onServerItemDetails(itemId)
	end
end

local window, currentType, backButton, closeButton, horizontalSeparator, manageContainersButton, tabStack, goldBase
local goldValueLabel, charmPointsLabel, echoesPointsLabel
local cyclopediaCharmBalance, cyclopediaMaxCharmBalance, cyclopediaEchoeBalance, cyclopediaMaxEchoeBalance = 0, 0, 0, 0
local moneyRefreshEvent, moneyRefreshPendingEvent
local MONEY_REFRESH_INTERVAL = 200
local MONEY_EVENT_REFRESH_DELAY = 25

local COIN_MULTIPLIERS = {
	[3031] = 1,
	[2148] = 1,
	[3035] = 100,
	[2152] = 100,
	[3043] = 10000,
	[2160] = 10000
}

local function formatCyclopediaGold(value)
	if Cyclopedia.formatGold then
		return Cyclopedia.formatGold(value)
	end

	return comma_value(value or 0)
end

local function getCyclopediaPlayerMoney()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	local bankGold = player:getResourceBalance(ResourceBank or 0) or 0
	local inventoryGold = player:getResourceBalance(ResourceInventary or 1) or 0
	local physicalCoins = 0

	for _, container in pairs(g_game.getContainers()) do
		for _, item in pairs(container:getItems()) do
			local mult = COIN_MULTIPLIERS[item:getId()]

			if mult then
				physicalCoins = physicalCoins + ((item:getCount() or 1) * mult)
			end
		end
	end

	for slot = InventorySlotFirst or 1, InventorySlotLast or 10 do
		local item = player:getInventoryItem(slot)

		if item then
			local mult = COIN_MULTIPLIERS[item:getId()]

			if mult then
				physicalCoins = physicalCoins + ((item:getCount() or 1) * mult)
			end
		end
	end

	-- On 8.60 the equipped-gold resource often lags after pickup/drop. Prefer the live
	-- coin count from inventory slots and open containers; fall back to resource only
	-- when nothing visible is counted (e.g. gold inside a closed backpack).
	local inventoryMoney = physicalCoins > 0 and physicalCoins or inventoryGold
	local total = bankGold + inventoryMoney

	if total > 0 then
		return total
	end

	if player.getTotalMoney then
		return player:getTotalMoney() or 0
	end

	return 0
end

function Cyclopedia.getPlayerMoney()
	return getCyclopediaPlayerMoney()
end

-- Global GoldBase: Character + Map only. Bestiary/Charms keep their own footer bars (see applyBestiaryFooterBalances).
local GOLD_BALANCE_TABS = {
	map = true,
	character = true
}

local function updateCyclopediaMoneyDisplay()
	if not goldBase or goldBase:isDestroyed() or not goldBase:isVisible() then
		return
	end

	if goldValueLabel and not goldValueLabel:isDestroyed() then
		goldValueLabel:setText(formatCyclopediaGold(getCyclopediaPlayerMoney()))
	end

	if charmPointsLabel and not charmPointsLabel:isDestroyed() then
		if cyclopediaMaxCharmBalance and cyclopediaMaxCharmBalance > 0 then
			charmPointsLabel:setText(string.format("%s / %s", formatCyclopediaGold(cyclopediaCharmBalance), formatCyclopediaGold(cyclopediaMaxCharmBalance)))
		else
			charmPointsLabel:setText(formatCyclopediaGold(cyclopediaCharmBalance))
		end
	end

	if echoesPointsLabel and not echoesPointsLabel:isDestroyed() then
		if cyclopediaMaxEchoeBalance and cyclopediaMaxEchoeBalance > 0 then
			echoesPointsLabel:setText(string.format("%s / %s", formatCyclopediaGold(cyclopediaEchoeBalance), formatCyclopediaGold(cyclopediaMaxEchoeBalance)))
		else
			echoesPointsLabel:setText(formatCyclopediaGold(cyclopediaEchoeBalance))
		end
	end

	if currentType == "bestiary" and applyBestiaryFooterBalances then
		applyBestiaryFooterBalances()
	end

	if currentType == "charms" and refreshCharmsFooterBalances then
		refreshCharmsFooterBalances()
	end
end

function Cyclopedia.setCharmResourceBalances(charmBalance, _, echoeBalance, maxCharmBalance, maxEchoeBalance)
	cyclopediaCharmBalance = charmBalance or cyclopediaCharmBalance
	cyclopediaEchoeBalance = echoeBalance or cyclopediaEchoeBalance
	cyclopediaMaxCharmBalance = maxCharmBalance or cyclopediaMaxCharmBalance
	cyclopediaMaxEchoeBalance = maxEchoeBalance or cyclopediaMaxEchoeBalance
	updateCyclopediaMoneyDisplay()
end

function Cyclopedia.refreshMoneyDisplays(requestServerBalance)
	if requestServerBalance and g_game.requestResource then
		g_game.requestResource(ResourceBank or 0)
		g_game.requestResource(ResourceInventary or 1)
	end

	updateCyclopediaMoneyDisplay()
end

local function isCyclopediaCoinItem(item)
	if not item or not item.isItem or not item:isItem() then
		return false
	end

	return COIN_MULTIPLIERS[item:getId()] ~= nil
end

local function scheduleCyclopediaMoneyRefresh()
	updateCyclopediaMoneyDisplay()

	if moneyRefreshPendingEvent then
		removeEvent(moneyRefreshPendingEvent)
	end

	moneyRefreshPendingEvent = scheduleEvent(function()
		moneyRefreshPendingEvent = nil
		updateCyclopediaMoneyDisplay()
	end, MONEY_EVENT_REFRESH_DELAY)
end

local function onCyclopediaTileThingChange(tile, thing)
	if isCyclopediaCoinItem(thing) then
		scheduleCyclopediaMoneyRefresh()
	end
end

local function cyclopediaMoneyRefreshTick()
	moneyRefreshEvent = nil

	if not window or window:isDestroyed() or not window:isVisible() then
		return
	end

	updateCyclopediaMoneyDisplay()
	moneyRefreshEvent = scheduleEvent(cyclopediaMoneyRefreshTick, MONEY_REFRESH_INTERVAL)
end

local function startCyclopediaMoneyRefresh()
	if moneyRefreshEvent then
		return
	end

	moneyRefreshEvent = scheduleEvent(cyclopediaMoneyRefreshTick, MONEY_REFRESH_INTERVAL)
end

local function stopCyclopediaMoneyRefresh()
	if moneyRefreshEvent then
		removeEvent(moneyRefreshEvent)
		moneyRefreshEvent = nil
	end

	if moneyRefreshPendingEvent then
		removeEvent(moneyRefreshPendingEvent)
		moneyRefreshPendingEvent = nil
	end
end

function Cyclopedia.setGoldBaseVisible(visible)
	if not goldBase or goldBase:isDestroyed() then
		return
	end

	goldBase:setVisible(visible)

	if visible then
		goldBase:raise()
		Cyclopedia.refreshMoneyDisplays(true)

		if getStoredCharmResourceBalances then
			local charmBalance, echoeBalance, maxCharmBalance, maxEchoeBalance = getStoredCharmResourceBalances()

			Cyclopedia.setCharmResourceBalances(charmBalance, nil, echoeBalance, maxCharmBalance, maxEchoeBalance)
		end

		if requestBestiaryCharmRefresh then
			requestBestiaryCharmRefresh()
		end
	end
end

function Cyclopedia.setGoldBaseForTab(tabType)
	Cyclopedia.setGoldBaseVisible(GOLD_BALANCE_TABS[tabType] == true)
end

local function onCyclopediaResourcesBalanceChange(value, oldBalance, resourceType)
	if resourceType ~= nil and resourceType ~= 0 and resourceType ~= 1 then
		return
	end

	scheduleCyclopediaMoneyRefresh()
end

local function onCyclopediaInventoryMoneyChange()
	scheduleCyclopediaMoneyRefresh()
end

local function connectCyclopediaMoneyListeners()
	connect(g_game, {
		onResourcesBalanceChange = onCyclopediaResourcesBalanceChange
	})

	connect(LocalPlayer, {
		onInventoryChange = onCyclopediaInventoryMoneyChange
	})

	if Container then
		connect(Container, {
			onOpen = onCyclopediaInventoryMoneyChange,
			onClose = onCyclopediaInventoryMoneyChange,
			onSizeChange = onCyclopediaInventoryMoneyChange,
			onAddItem = onCyclopediaInventoryMoneyChange,
			onUpdateItem = onCyclopediaInventoryMoneyChange,
			onRemoveItem = onCyclopediaInventoryMoneyChange
		})
	end

	if g_game.enableTileThingLuaCallback then
		g_game.enableTileThingLuaCallback(true)
	end

	connect(Tile, {
		onAddThing = onCyclopediaTileThingChange,
		onRemoveThing = onCyclopediaTileThingChange
	})
end

local function disconnectCyclopediaMoneyListeners()
	disconnect(g_game, {
		onResourcesBalanceChange = onCyclopediaResourcesBalanceChange
	})

	disconnect(LocalPlayer, {
		onInventoryChange = onCyclopediaInventoryMoneyChange
	})

	if Container then
		disconnect(Container, {
			onOpen = onCyclopediaInventoryMoneyChange,
			onClose = onCyclopediaInventoryMoneyChange,
			onSizeChange = onCyclopediaInventoryMoneyChange,
			onAddItem = onCyclopediaInventoryMoneyChange,
			onUpdateItem = onCyclopediaInventoryMoneyChange,
			onRemoveItem = onCyclopediaInventoryMoneyChange
		})
	end

	disconnect(Tile, {
		onAddThing = onCyclopediaTileThingChange,
		onRemoveThing = onCyclopediaTileThingChange
	})
end

local DEFAULT_WINDOW_SIZE = { width = 700, height = 538 }
local ITEMS_WINDOW_SIZE = { width = 700, height = 618 }
local CONTENT_MARGIN_BOTTOM = {
	items = 36,
	character = 40,
	map = 40
}

local function setContentFooterLayout(tabType)
	if not window or not contentContainer then
		return
	end

	if tabType == "items" then
		window:setSize(ITEMS_WINDOW_SIZE)

		if manageContainersButton then
			manageContainersButton:setVisible(true)
		end
	else
		window:setSize(DEFAULT_WINDOW_SIZE)

		if manageContainersButton then
			manageContainersButton:setVisible(false)
		end
	end

	contentContainer:setMarginBottom(CONTENT_MARGIN_BOTTOM[tabType] or 0)
end

local function setWindowBottomBarForTab(tabType)
	if closeButton then
		closeButton:setVisible(true)
	end

	if horizontalSeparator then
		horizontalSeparator:setVisible(true)
	end

	if backButton then
		backButton:setVisible(true)
	end

	if bestiaryPanel and not bestiaryPanel:isDestroyed() then
		local embeddedClose = bestiaryPanel:recursiveGetChildById('embeddedCloseButton')

		if embeddedClose then
			embeddedClose:hide()
		end
	end

	if charmsWindow and not charmsWindow:isDestroyed() then
		local embeddedClose = charmsWindow:recursiveGetChildById('embeddedCloseButton')
		local embeddedBack = charmsWindow:recursiveGetChildById('embeddedBackButton')

		if embeddedClose then
			embeddedClose:hide()
		end

		if embeddedBack then
			embeddedBack:hide()
		end
	end

	if bestiaryTrackerButton and not bestiaryTrackerButton:isDestroyed() then
		if tabType == "character" then
			bestiaryTrackerButton:hide()
		else
			bestiaryTrackerButton:show()
		end
	end
end

local cyclopediaCharacterGameEvents
local cyclopediaCharacterEventsConnected = false

local function getCyclopediaCharacterGameEvents()
	if cyclopediaCharacterGameEvents then
		return cyclopediaCharacterGameEvents
	end

	cyclopediaCharacterGameEvents = {
		onParseCyclopediaCharacterGeneralStats = function(data, skills, combats)
			Cyclopedia.loadCharacterGeneralStats(data, skills, combats)
			Cyclopedia.repaintCharacterStatsIfActive(true)
		end,
		onParseCyclopediaCharacterCombatStats = function(data, mitigation, additionalSkillsArray, forgeSkillsArray, perfectShotDamageRanges, combatsArray, concoctionsArray)
			Cyclopedia.loadCharacterCombatStats(data, mitigation, additionalSkillsArray, forgeSkillsArray, perfectShotDamageRanges, combatsArray, concoctionsArray)
		end,
		onParseCyclopediaCharacterBadges = function(showAccountInformation, playerOnline, playerPremium, loyaltyTitle, badgesVector)
			Cyclopedia.loadCharacterBadges(showAccountInformation, playerOnline, playerPremium, loyaltyTitle, badgesVector)
			Cyclopedia.repaintCharacterStatsIfActive(true)
		end,
		onCyclopediaCharacterRecentDeaths = Cyclopedia.loadCharacterRecentDeaths,
		onCyclopediaCharacterRecentKills = Cyclopedia.loadCharacterRecentKills,
		onUpdateCyclopediaCharacterItemSummary = Cyclopedia.loadCharacterItems,
		onParseCyclopediaCharacterAppearances = Cyclopedia.loadCharacterAppearances,
		onParseCyclopediaStoreSummary = Cyclopedia.onParseCyclopediaStoreSummary,
		onParseCyclopediaCharacterAchievements = Cyclopedia.onEngineCharacterAchievements,
		onParseCyclopediaCharacterInspection = Cyclopedia.loadCharacterInspection,
		onParseCyclopediaCharacterTitles = Cyclopedia.onEngineCharacterTitles,
		onPreyActive = Cyclopedia.refreshCharacterPreyIfVisible,
		onPreyInactive = Cyclopedia.refreshCharacterPreyIfVisible,
		onPreyTimeLeft = Cyclopedia.refreshCharacterPreyIfVisible,
		onCyclopediaCharacterOffenceStats = Cyclopedia.onCyclopediaCharacterOffenceStats,
		onCyclopediaCharacterDefenceStats = Cyclopedia.onCyclopediaCharacterDefenceStats,
		onCyclopediaCharacterMiscStats = Cyclopedia.onCyclopediaCharacterMiscStats
	}

	return cyclopediaCharacterGameEvents
end

local function connectCyclopediaCharacterEvents()
	if not g_game.requestCharacterInfo or cyclopediaCharacterEventsConnected then
		return
	end

	connect(g_game, getCyclopediaCharacterGameEvents())
	cyclopediaCharacterEventsConnected = true
end

local function disconnectCyclopediaCharacterEvents()
	if not g_game.requestCharacterInfo or not cyclopediaCharacterEventsConnected then
		return
	end

	disconnect(g_game, getCyclopediaCharacterGameEvents())
	cyclopediaCharacterEventsConnected = false
end

local function setItemsTabLayout(active)
	setContentFooterLayout(active and "items" or nil)
end
cyclopediaButton = nil
bestiaryTrackerButton = nil
local function requestMarketItemsPreload()
	if not g_game.isOnline() then
		return
	end
	if modules.game_market and modules.game_market.requestMarketItemsForCyclopedia then
		modules.game_market.requestMarketItemsForCyclopedia()
	end
end

local function onCyclopediaEnterGame()
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
end

function init()
	
	-- The rest
	connect(g_game, {
		onGameStart = onCyclopediaGameStart,
		onGameEnd = onCyclopediaGameEnd,
		onEnterGame = onCyclopediaEnterGame,
		onPendingGame = registerBestiaryProtocol,
		onParseItemDetail = onCyclopediaItemDetail,
		onItemDetails = onCyclopediaItemDetails
	}, true)

	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end

	g_ui.importStyle('styles/bestiary_tracker')
	g_ui.importStyle('styles/cyclopedia_map_widgets')
	g_ui.importStyle('cyclopedia_widgets')
	g_ui.importStyle('cyclopedia_pages')
	window 	   = g_ui.displayUI('game_cyclopedia')
	
	cyclopediaButton = modules.client_topmenu.addRightGameToggleButton('cyclopediaButton', tr('Cyclopedia'), '/images/topbuttons/ciclopedia', toggle, false, 8)
	bestiaryTrackerButton = modules.client_topmenu.addRightGameToggleButton('bestiaryTrackerButton', tr('Bestiary Tracker'), '/images/options/bestiaryTracker', toggleTracker, false, 9)
	modules.game_cyclopedia.cyclopediaButton = cyclopediaButton
	modules.game_cyclopedia.bestiaryTrackerButton = bestiaryTrackerButton

	window.onVisibilityChange = function(widget, visible)
		if cyclopediaButton then
			cyclopediaButton:setOn(visible)
		end

		if visible then
			Cyclopedia.refreshMoneyDisplays(true)
			startCyclopediaMoneyRefresh()

			if getCurrentType() == "character" and Cyclopedia.refreshCharacterLiveStats then
				Cyclopedia.refreshCharacterLiveStats()
			end
		else
			stopCyclopediaMoneyRefresh()

			if Cyclopedia.onItemsTabHidden then
				Cyclopedia.onItemsTabHidden()
			end
			if modules.game_inspect and modules.game_inspect.hide then
				modules.game_inspect.hide()
			end
			setItemsTabLayout(false)
		end
	end
	contentContainer = window:recursiveGetChildById('contentContainer')
	backButton = nil
	closeButton = nil
	horizontalSeparator = nil
	goldBase = nil

	if window.getChildren then
		for _, child in ipairs(window:getChildren()) do
			local id = child:getId()

			if id == 'backButton' then
				backButton = child
			elseif id == 'closeButton' then
				closeButton = child
			elseif id == 'horizontalSeparator' then
				horizontalSeparator = child
			elseif id == 'GoldBase' then
				goldBase = child
			end
		end
	end

	if not backButton then
		backButton = window:recursiveGetChildById('backButton')
	end

	if not closeButton then
		closeButton = window:recursiveGetChildById('closeButton')
	end

	if backButton and closeButton then
		closeButton:setFont(backButton:getFont())
		closeButton:setColor("#dfdfdfff")
	end

	if not horizontalSeparator then
		horizontalSeparator = window:recursiveGetChildById('horizontalSeparator')
	end

	manageContainersButton = window:recursiveGetChildById('manageContainersButton')

	if not goldBase then
		goldBase = window:recursiveGetChildById('GoldBase')
	end

	if goldBase then
		goldValueLabel = goldBase:recursiveGetChildById('Value')
		charmPointsLabel = goldBase:recursiveGetChildById('charmPoints')
		echoesPointsLabel = goldBase:recursiveGetChildById('echoesPoints')
	end
	tabStack = {}
	buttonSelection = window:recursiveGetChildById('buttonSelection')
		items = buttonSelection:recursiveGetChildById('items')
		bestiary = buttonSelection:recursiveGetChildById('bestiary')
		charms = buttonSelection:recursiveGetChildById('charms')
		map = buttonSelection:recursiveGetChildById('map')
		houses = buttonSelection:recursiveGetChildById('houses')
		character = buttonSelection:recursiveGetChildById('character')

	if character and g_game.requestCharacterInfo then
		character:setVisible(true)
	end

	modules.game_cyclopedia.Cyclopedia = Cyclopedia

	if g_game.isOnline() then
		connectCyclopediaCharacterEvents()
		connectCyclopediaMoneyListeners()
	end
end

function terminate()
	stopCyclopediaMoneyRefresh()
	disconnectCyclopediaMoneyListeners()
	disconnectCyclopediaCharacterEvents()

	if Cyclopedia.clearCharacterUI then
		Cyclopedia.clearCharacterUI()
	end

	disconnect(g_game, {
		onGameStart = onCyclopediaGameStart,
		onGameEnd = onCyclopediaGameEnd,
		onEnterGame = onCyclopediaEnterGame,
		onPendingGame = registerBestiaryProtocol,
		onParseItemDetail = onCyclopediaItemDetail,
		onItemDetails = onCyclopediaItemDetails
	})

	if Cyclopedia.Items and Cyclopedia.Items.terminate then
		Cyclopedia.Items.terminate()
	end
	if Cyclopedia and Cyclopedia.clearMapUI then
		Cyclopedia.clearMapUI()
	end
	
	-- Hooked opcodes
	ProtocolGame.unregisterOpcode(0x29)
	if terminateBestiary then
		terminateBestiary()
	elseif unregisterBestiaryProtocol then
		unregisterBestiaryProtocol()
	else
		ProtocolGame.unregisterOpcode(CyclopediaOpcode and CyclopediaOpcode.Send or 0x39)
	end
	
	if cyclopediaButton then
		cyclopediaButton:destroy()
		cyclopediaButton = nil
	end
	if bestiaryTrackerButton then
		bestiaryTrackerButton:destroy()
		bestiaryTrackerButton = nil
	end
	
	window:destroy()
	
	if buyWindow then
		buyWindow:destroy()
	end

	if Cyclopedia.detailMeasureLabel and not Cyclopedia.detailMeasureLabel:isDestroyed() then
		Cyclopedia.detailMeasureLabel:destroy()
		Cyclopedia.detailMeasureLabel = nil
	end
end

function getContentContainer()
	return contentContainer
end

function getCurrentType()
	return currentType
end

function onCyclopediaGameStart()
	connectCyclopediaMoneyListeners()

	if LoadedPlayer and LoadedPlayer.cacheFromLocalPlayer then
		LoadedPlayer:cacheFromLocalPlayer()
	end
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
	if loadBestiaryUnlockCache then
		loadBestiaryUnlockCache()
	end
	if restoreBestiaryTracker then
		restoreBestiaryTracker()
	end
	if Cyclopedia.Items and Cyclopedia.Items.loadJson then
		Cyclopedia.Items.loadJson()
	end
	requestMarketItemsPreload()
	connectCyclopediaCharacterEvents()
	if character and g_game.requestCharacterInfo then
		character:setVisible(true)
	end
end

function onCyclopediaGameEnd()
	stopCyclopediaMoneyRefresh()
	disconnectCyclopediaMoneyListeners()
	disconnectCyclopediaCharacterEvents()

	if Cyclopedia.resetCharacterStatCaches then
		Cyclopedia.resetCharacterStatCaches()
	end

	if Cyclopedia.clearCharacterUI then
		Cyclopedia.clearCharacterUI()
	end

	if Cyclopedia.Items and Cyclopedia.Items.saveJson then
		Cyclopedia.Items.saveJson()
	end
	if Cyclopedia and Cyclopedia.clearMapUI then
		Cyclopedia.clearMapUI()
	end
	if window then
		window:hide()
	end
	if Cyclopedia.invalidateItemsIndex then
		Cyclopedia.invalidateItemsIndex()
	end
	if onBestiaryGameEnd then
		onBestiaryGameEnd()
	end
end

function toggle(type)
	if window:isVisible() and not type then
		setItemsTabLayout(false)
		window:hide()
	else
		if not window:isVisible() then
			tabStack = {}
			updateBackButton()
		end
		show(type or "bestiary")
	end
end

function updateBackButton()
	if backButton then
		local canBack = currentType == "charms" or (tabStack and #tabStack > 0)
		backButton:setEnabled(canBack)
	end
end

function toggleBack()
	if currentType == "charms" then
		toggleWindow("bestiary", true)
		return
	end

	if currentType == "bestiary" and Cyclopedia.handleBestiaryBack and Cyclopedia.handleBestiaryBack() then
		return
	end

	local previousTab = tabStack and table.remove(tabStack)
	if not previousTab then
		updateBackButton()
		return
	end

	updateBackButton()
	toggleWindow(previousTab, true)
end

function show(type)
	type = type or "bestiary"

	if not window:isVisible() then
		tabStack = {}
		updateBackButton()
	end

	if currentType ~= type then
		toggleWindow(type)
	else
		ensureCyclopediaTabContent(type)
	end

	if not window:isVisible() then
		window:show()
	end

	window:raise()
	window:focus()
end

function Cyclopedia.openBestiaryMonster(raceId)
	if openBestiaryMonster then
		return openBestiaryMonster(raceId)
	end
	return false
end

function Cyclopedia.openBestiaryByRaceIdOrName(raceId, creatureName)
	if openBestiaryByRaceIdOrName then
		return openBestiaryByRaceIdOrName(raceId, creatureName)
	end
	return false
end

function Cyclopedia.rememberBestiaryUnlock(raceId, progress, outfit)
	if rememberBestiaryUnlock then
		rememberBestiaryUnlock(raceId, progress, outfit)
	end
end

function Cyclopedia.openBestiaryCreature(creature)
	if openBestiaryCreature then
		return openBestiaryCreature(creature)
	end
	return false
end

function Cyclopedia.isBestiaryCreatureUnlocked(creature)
	if isBestiaryCreatureUnlocked then
		return isBestiaryCreatureUnlocked(creature)
	end
	return false
end

function Cyclopedia.ensureBestiaryCreatureLookup(creature)
	if ensureBestiaryCreatureLookup then
		ensureBestiaryCreatureLookup(creature)
	end
end

function toggleTracker()
	if toggleBestiaryTracker then
		toggleBestiaryTracker()
	end
end

local function getCyclopediaTabButtons()
	return { items, bestiary, charms, map, houses, character }
end

local function resetCyclopediaTabButtons()
	for _, tab in ipairs(getCyclopediaTabButtons()) do
		if tab then
			tab:enable()
			tab:setOn(false)
		end
	end
end

function emptyContentContainer()
	for _, child in ipairs(contentContainer:getChildren()) do
		child:hide()
	end
end

function ensureCyclopediaTabContent(type)
	if not contentContainer then
		return
	end

	for _, child in ipairs(contentContainer:getChildren()) do
		child:hide()
	end

	if type == "items" then
		setContentFooterLayout("items")
	elseif type then
		setContentFooterLayout(type)
	end

	if type == "character" then
		local panel = contentContainer:recursiveGetChildById("Cat6")

		if panel and not panel:isDestroyed() then
			panel:show()

			if Cyclopedia.ensureCharacterCombatStatListeners then
				Cyclopedia.ensureCharacterCombatStatListeners()
			end

			if Cyclopedia.refreshCharacterLiveStats then
				Cyclopedia.refreshCharacterLiveStats()
			end
		elseif showCharacter then
			showCharacter()
		end
	elseif type == "items" then
		if showItems then
			showItems()
		end
	elseif type == "bestiary" and bestiaryPanel and not bestiaryPanel:isDestroyed() then
		bestiaryPanel:show()
	elseif type == "charms" and charmsWindow and not charmsWindow:isDestroyed() then
		charmsWindow:show()
	elseif type == "map" then
		local mapPanel = contentContainer:recursiveGetChildById("Cat4")

		if mapPanel and not mapPanel:isDestroyed() then
			mapPanel:show()
		elseif initMap then
			initMap(contentContainer)
		end
	end

	if Cyclopedia.setGoldBaseForTab then
		Cyclopedia.setGoldBaseForTab(type)
	end

	setWindowBottomBarForTab(type)
end

function toggleWindow(type, isBackNavigation)
	if currentType == type then
		return
	end

	if currentType == "map" and Cyclopedia and Cyclopedia.clearMapUI then
		Cyclopedia.clearMapUI()
	end

	if currentType == "character" and Cyclopedia.clearCharacterUI then
		Cyclopedia.clearCharacterUI()
	end

	if not isBackNavigation and currentType then
		tabStack = tabStack or {}
		table.insert(tabStack, currentType)
		updateBackButton()
	end

	resetCyclopediaTabButtons()

	-- We empty the container
	emptyContentContainer()
	currentType = type

	local function activateTab(tab)
		if not tab then
			return
		end
		tab:setOn(true)
		tab:disable()
	end
		
	if (type == "items") then
		setContentFooterLayout("items")
		activateTab(items)
		if showItems then
			showItems()
		end
	else
		setContentFooterLayout(type)
	end

	if (type == "bestiary") then
		activateTab(bestiary)

		-- Setup the widget
		initBestiary(contentContainer)
	elseif (type == "charms") then
		activateTab(charms)

		-- Setup the charms
		initCharms(contentContainer)
	elseif (type == "map") then
		activateTab(map)

		-- Setup the widget
		initMap(contentContainer)
	elseif (type == "houses") then
		activateTab(houses)
	elseif (type == "character") then
		activateTab(character)
		if showCharacter then
			showCharacter()
		end
	end

	Cyclopedia.setGoldBaseForTab(type)
	setWindowBottomBarForTab(type)
	updateBackButton()
end

function isVisible()
	return window and window:isVisible()
end
