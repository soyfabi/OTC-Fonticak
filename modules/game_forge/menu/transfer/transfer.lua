-- chunkname: @/game_forge/menu/transfer/transfer.lua

Forge.Transfer = {}

local Transfer = Forge.Transfer

Transfer.mainWindow = nil

local DUST_NORMAL_TRANSFER = 100
local DUST_CONVERGENCE_TRANSFER = 160
local DESCRIPTIONS = {
	dustRequirement = "A transfer requires %d dust.",
	receiverList = "Select the item to which you want to transfer the tier.",
	coreRequirement = "A transfer requires %d exalted cores.",
	donorList = "Select an item whose tier you want to transfer. Warning! This item will be consumed during the transfer.",
	coreRequirementNotEnough = "A transfer requires %d exalted cores. Unfortunately, you do not have that many.",
	selectItems = "Select a tiered item as source on the left and a classification 4 item on the right to receive its tier.",
	selectBothItems = "Please select both the item whose tier you wish to transfer and the item you want to transfer the tier to.",
	defaultConvergence = "You can transfer the tier of a classification 4 item to another item of the same classification. To do this, you must have at least one tier 1 item that will be consumed during the transfer and additional resources. The other item will receive the tier of the consumed item.",
	notEnoughIngredients = "You do not have all the ingredients you need.",
	default = "You can transfer the tier of an item to another item of the same classification. To do so, you need at least a tier 2 item that will be consumed during the transfer and additional resources. The other item will receive the consumed item's tier reduced by one.",
	transferReady = "Click here to carry out the transfer. This will consume all required ingredients.",
	consumedItem = "%s with tier %d will be consumed during the transfer.",
	selectItemAbove = "Please select an item above to continue.",
	convergence = "A Convergence transfer does not reduce the tier of the consumed item."
}
local REQUIREMENTS_SLOT_IDS = {
	previewTransferHoverArea = "preview",
	requiredCoreHoverArea = "core",
	requiredDustHoverArea = "dust"
}
local TRANSFER_ACTION_WIDGET_IDS = {
	transferButtonHoverArea = true,
	transferActionWrapper = true,
	transferButtonProcced = true
}

local function getItemDisplayName(item)
	if not item then
		return "item"
	end

	if modules.game_analysers and modules.game_analysers.getItemServerName then
		return modules.game_analysers.getItemServerName(item:getId()):lower()
	end

	local thing = g_things.getThingType(item:getId(), ThingCategoryItem)

	return thing and thing:getName():lower() or "item"
end

function Transfer:setDescription(text)
	if self.descriptionLabel then
		self.descriptionLabel:setText(text or "")
	end
end

function Transfer:resetDescription()
	if self:isConvergenceTransfer() then
		self:setDescription(DESCRIPTIONS.defaultConvergence)
	else
		self:setDescription(DESCRIPTIONS.default)
	end
end

function Transfer:getDonorItem()
	local ws = self.widgetStorage

	if not ws then
		return nil
	end

	if ws.previewTransferItem then
		local item = ws.previewTransferItem:getItem()

		if item then
			return item
		end
	end

	if ws.firstButtonPreviewItem then
		return ws.firstButtonPreviewItem:getItem()
	end

	return nil
end

function Transfer:hasDonorItemSelected()
	return self:getDonorItem() ~= nil
end

function Transfer:describePreviewItemRequirement()
	local item = self:getDonorItem()

	if not item then
		return DESCRIPTIONS.selectItemAbove
	end

	return string.format(DESCRIPTIONS.consumedItem, getItemDisplayName(item), item:getTier())
end

function Transfer:describeDustRequirement()
	return string.format(DESCRIPTIONS.dustRequirement, self:getDustCost())
end

function Transfer:describeCoreRequirement()
	if not self:hasDonorItemSelected() then
		return DESCRIPTIONS.selectItemAbove
	end

	local ws = self.widgetStorage
	local coreText = ws.requiredTransferCoreCount and ws.requiredTransferCoreCount:getText() or "0"
	local coreCost = tonumber(coreText)

	if not coreCost then
		return DESCRIPTIONS.selectItemAbove
	end

	if coreCost > Forge:getResourceBalance("core") then
		return string.format(DESCRIPTIONS.coreRequirementNotEnough, coreCost)
	end

	return string.format(DESCRIPTIONS.coreRequirement, coreCost)
end

function Transfer.getRequirementsSlotId(widget)
	local current = widget

	while current do
		local id = current:getId()
		local slotId = REQUIREMENTS_SLOT_IDS[id]

		if slotId then
			return slotId
		end

		if current == Transfer.mainWindow then
			break
		end

		current = current:getParent()
	end

	return nil
end

function Transfer.isTransferActionWidget(widget)
	local current = widget

	while current do
		if TRANSFER_ACTION_WIDGET_IDS[current:getId()] then
			return true
		end

		if current == Transfer.mainWindow then
			break
		end

		current = current:getParent()
	end

	return false
end

function Transfer:hasTransferResources()
	local ws = self.widgetStorage

	if not ws or not Forge.data then
		return false
	end

	local firstItem = ws.firstButtonPreviewItem and ws.firstButtonPreviewItem:getItem()

	if not firstItem then
		return false
	end

	local dustCost = self:getDustCost()

	if dustCost > Forge:getResourceBalance("dust") then
		return false
	end

	local coreCost = self:getTransferCoreCost(firstItem:getTier())

	if not coreCost or coreCost > Forge:getResourceBalance("core") then
		return false
	end

	local cost = self:getTransferGoldCost(firstItem, firstItem:getTier())

	if not cost or cost > Forge:getResourceBalance("money") then
		return false
	end

	return true
end

function Transfer:describeTransferAction()
	local ws = self.widgetStorage

	if not ws then
		return ""
	end

	local firstItem = ws.firstButtonPreviewItem and ws.firstButtonPreviewItem:getItem()
	local secondItem = ws.secondButtonPreviewItem and ws.secondButtonPreviewItem:getItem()

	if not firstItem or not secondItem then
		return DESCRIPTIONS.selectBothItems
	end

	if not self:hasTransferResources() then
		return DESCRIPTIONS.notEnoughIngredients
	end

	return DESCRIPTIONS.transferReady
end

local descriptionRefreshEvent

local function isRequirementsAreaHovered()
	if not Transfer.mainWindow then
		return false
	end

	local target = Transfer.mainWindow:recursiveGetChildByPos(g_window.getMousePosition(), false)

	return Transfer.getRequirementsSlotId(target) ~= nil or Transfer.isTransferActionWidget(target)
end

local function refreshDescriptionFromMouse()
	if not Transfer.mainWindow or not Transfer.mainWindow:isVisible() then
		return
	end

	local target = Transfer.mainWindow:recursiveGetChildByPos(g_window.getMousePosition(), false)

	if target then
		Transfer.onHover(target)
	else
		Transfer:resetDescription()
	end
end

function Transfer.onDefaultDescriptionHover(widget, hovered)
	if not hovered then
		return
	end

	if not Transfer.mainWindow or not Transfer.mainWindow:isVisible() then
		return
	end

	Transfer:resetDescription()
end

function Transfer.onRequirementsDefaultDescriptionHover(widget, hovered)
	if not hovered then
		return
	end

	if not Transfer.mainWindow or not Transfer.mainWindow:isVisible() then
		return
	end

	if descriptionRefreshEvent then
		removeEvent(descriptionRefreshEvent)
	end

	descriptionRefreshEvent = scheduleEvent(function()
		descriptionRefreshEvent = nil

		if isRequirementsAreaHovered() then
			refreshDescriptionFromMouse()
		else
			Transfer:resetDescription()
		end
	end, 1)
end

function Transfer.onHover(widget)
	if not Transfer.mainWindow or not Transfer.mainWindow:isVisible() then
		return
	end

	if not widget or not widget:isVisible() then
		return
	end

	local id = widget:getId()

	if id == "transferPanel" or id == "firstTooltip" or id == "description" then
		Transfer:resetDescription()

		return
	end

	if Transfer.isTransferActionWidget(widget) then
		Transfer:setDescription(Transfer:describeTransferAction())

		return
	end

	if id == "transferConvergence" then
		Transfer:setDescription(DESCRIPTIONS.convergence)

		return
	end

	local requirementsSlotId = Transfer.getRequirementsSlotId(widget)

	if requirementsSlotId == "preview" then
		Transfer:setDescription(Transfer:describePreviewItemRequirement())

		return
	end

	if requirementsSlotId == "dust" then
		Transfer:setDescription(Transfer:describeDustRequirement())

		return
	end

	if requirementsSlotId == "core" then
		Transfer:setDescription(Transfer:describeCoreRequirement())

		return
	end

	Transfer:resetDescription()
end

local function bindDefaultDescriptionHover(widget)
	if not widget then
		return
	end

	function widget.onHoverChange(hovered)
		Transfer.onDefaultDescriptionHover(widget, hovered)
	end
end

local function bindTransferSlotHover(container, itemWidget, description)
	if itemWidget then
		function itemWidget.onHoverChange(hovered)
			if not Transfer.mainWindow or not Transfer.mainWindow:isVisible() then
				return
			end

			if hovered then
				if descriptionRefreshEvent then
					removeEvent(descriptionRefreshEvent)

					descriptionRefreshEvent = nil
				end

				Transfer:setDescription(description)
			else
				if descriptionRefreshEvent then
					removeEvent(descriptionRefreshEvent)
				end

				descriptionRefreshEvent = scheduleEvent(function()
					descriptionRefreshEvent = nil

					refreshDescriptionFromMouse()
				end, 1)
			end
		end
	end

	if container then
		function container.onHoverChange(hovered)
			if not hovered then
				return
			end

			if not Transfer.mainWindow or not Transfer.mainWindow:isVisible() then
				return
			end

			if itemWidget and itemWidget:isHovered() then
				return
			end

			Transfer:resetDescription()
		end
	end
end

local function bindRequirementsDefaultHover(widget)
	if not widget then
		return
	end

	function widget.onHoverChange(hovered)
		Transfer.onRequirementsDefaultDescriptionHover(widget, hovered)
	end
end

function Transfer.onWidgetHover(widget, hovered)
	if hovered then
		if descriptionRefreshEvent then
			removeEvent(descriptionRefreshEvent)

			descriptionRefreshEvent = nil
		end

		Transfer.onHover(widget)

		return
	end

	if descriptionRefreshEvent then
		removeEvent(descriptionRefreshEvent)
	end

	descriptionRefreshEvent = scheduleEvent(function()
		descriptionRefreshEvent = nil

		refreshDescriptionFromMouse()
	end, 1)
end

local function setupForgeAreaClearHover()
	local forgeWindow = Forge.mainWindow

	if not forgeWindow then
		return
	end

	local function clearOnEnter(widget)
		if not widget then
			return
		end

		function widget.onHoverChange(hovered)
			if hovered and Transfer.mainWindow and Transfer.mainWindow:isVisible() then
				Transfer:resetDescription()
			end
		end
	end

	for _, widgetId in ipairs({
		"headerPainel",
		"goldBalancePanel",
		"dustBalancePanel",
		"sliverBalancePanel",
		"coreBalancePanel",
		"close",
		"separator",
		"FusionButton",
		"TransferButton",
		"ConversionButton",
		"HistoryButton"
	}) do
		clearOnEnter(forgeWindow:getChildById(widgetId))
	end
end

function Transfer:setupHovers()
	setupForgeAreaClearHover()

	local mainWindow = self.mainWindow

	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("transferWindow1"))
	bindDefaultDescriptionHover(self.widgetStorage.firstItemPanel)
	bindDefaultDescriptionHover(self.widgetStorage.secondItemPanel)
	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("previewTransferPanel"))
	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("transferScrollBar"))
	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("transferScrollBar2"))
	bindRequirementsDefaultHover(self.widgetStorage.transferRequirements)
end

function Transfer:createButton()
	local buttonPanel = g_ui.createWidget("ForgeButton", Forge.mainWindow)

	buttonPanel:addAnchor(AnchorTop, "FusionButton", AnchorTop)
	buttonPanel:addAnchor(AnchorLeft, "FusionButton", AnchorRight)
	buttonPanel:setId("TransferButton")

	self.buttonPanel = buttonPanel
	self.mainButton = buttonPanel:getChildById("button")

	Forge.setupTabButtonIcon(buttonPanel, "/images/icons_big/icon-transfer", 6, 3)

	if not self.mainWindow then
		g_ui.importStyle("Transfer")

		self.mainWindow = g_ui.createWidget("TransferWindow", Forge.mainWindow)

		self.mainWindow:addAnchor(AnchorTop, "TransferButton", AnchorBottom)
		self.mainWindow:addAnchor(AnchorLeft, "FusionButton", AnchorLeft)
		self.mainWindow:addAnchor(AnchorRight, "parent", AnchorRight)
		self.mainWindow:addAnchor(AnchorBottom, "parent", AnchorBottom)
	end

	self:init()

	function self.mainButton.onClick(widget, mousePos, mouseButton)
		self:showWindow()
	end
end

function Transfer:resetConvergenceMode()
	if not self.widgetStorage or not self.widgetStorage.convergence then
		return
	end

	if not self.widgetStorage.convergence:isChecked() then
		return
	end

	self.widgetStorage.convergence:setChecked(false)
	self:updateWidgets()

	if self.transfers then
		self:displayItems()
	end

	self:updateRequirementsTitle()
	self:resetDescription()
end

function Transfer:updateRequirementsTitle()
	if not self.widgetStorage or not self.widgetStorage.transferRequirements then
		return
	end

	if self.widgetStorage.convergence:isChecked() then
		self.widgetStorage.transferRequirements:setText("Convergence Transfer Requirements")
	else
		self.widgetStorage.transferRequirements:setText("Transfer Requirements")
	end
end

function Transfer:refreshListView()
	if not self.widgetStorage then
		return
	end

	self.activePanels = nil
	self.activePanelList = nil

	self:updateWidgets()

	if self.widgetStorage.convergence:isChecked() then
		if self.convergenceTransfers then
			self:displayConvergence()
		end
	elseif self.transfers then
		self:displayItems()
	end
end

function Transfer:showWindow()
	if Forge.currentPanel then
		Forge.currentPanel:setVisible(false)
	end

	if Forge.currentButton then
		Forge.currentButton:setEnabled(true)
		Forge.onTabButtonEnabled(Forge.currentButton, nil, true)
	end

	Forge.currentPanel = self.mainWindow
	Forge.currentButton = self.mainButton

	if self.widgetStorage and self.widgetStorage.requiredTransferCoreItem then
		self.widgetStorage.requiredTransferCoreItem:setItemId(37110)
	end

	self.mainWindow:setVisible(true)
	self.mainWindow:raise()
	self.mainButton:setEnabled(false)
	Forge.onTabButtonEnabled(nil, self.buttonPanel, false)
	Forge.firstTooltip:setVisible(false)
	self:resetDescription()
	self:updateRequirementsTitle()
	self:refreshListView()
end

local delay = 250
local lastClick = 0

function Transfer:canProceedTransfer()
	local ws = self.widgetStorage

	if not ws then
		return false
	end

	local firstItem = ws.firstButtonPreviewItem and ws.firstButtonPreviewItem:getItem()
	local secondItem = ws.secondButtonPreviewItem and ws.secondButtonPreviewItem:getItem()

	if not firstItem or not secondItem then
		return false
	end

	return self:hasTransferResources()
end

function Transfer:refreshTransferProceedState()
	local ws = self.widgetStorage

	if not ws then
		return
	end

	local canProceed = self:canProceedTransfer()

	if ws.chainTransparent then
		ws.chainTransparent:setVisible(not canProceed)

		if not canProceed then
			ws.chainTransparent:raise()
		end
	end
end

local function updateButtonPreviewSlot(itemWidget, questionMarkWidget, item)
	if not itemWidget then
		return
	end

	if item then
		itemWidget:setVisible(true)
		itemWidget:setItem(item)
		ItemsDatabase.setTier(itemWidget, item)

		if questionMarkWidget then
			questionMarkWidget:setVisible(false)
		end
	else
		itemWidget:setItem(nil)
		ItemsDatabase.setTier(itemWidget, 0)
		itemWidget:setVisible(false)

		if questionMarkWidget then
			questionMarkWidget:setVisible(true)
		end
	end
end

function Transfer:init()
	self.widgetStorage = {}
	self.transferClickLocked = false
	self.dustNormalTransfer = DUST_NORMAL_TRANSFER
	self.dustConvergenceTransfer = DUST_CONVERGENCE_TRANSFER

	local mainPanel = self.mainWindow

	self.widgetStorage.mainButton = self.mainButton

	local tooltipPanel = mainPanel:getChildById("firstTooltip")

	self.descriptionLabel = tooltipPanel:getChildById("description")

	self:resetDescription()

	local convergence = mainPanel:recursiveGetChildById("transferConvergence")

	function convergence.onClick(widget)
		if widget:isChecked() then
			widget:setChecked(false)
			self:updateWidgets()
			self:displayItems()
		else
			widget:setChecked(true)
			self:updateWidgets()
			self:displayConvergence()
		end

		self:updateRequirementsTitle()
		self:resetDescription()
	end

	self.widgetStorage.convergence = convergence
	self.widgetStorage.transferRequirements = mainPanel:recursiveGetChildById("transferRequirements")
	self.widgetStorage.firstItemPanel = mainPanel:recursiveGetChildById("transferContent")
	self.widgetStorage.secondItemPanel = mainPanel:recursiveGetChildById("transferContent2")

	local transferButtonProcess = mainPanel:recursiveGetChildById("transferButtonProcced")

	self.widgetStorage.transferButtonProcess = transferButtonProcess
	self.widgetStorage.transferButtonHoverArea = mainPanel:recursiveGetChildById("transferButtonHoverArea")

	local firstButtonPreviewItem = transferButtonProcess:recursiveGetChildById("firstButtonPreviewItem")

	self.widgetStorage.firstButtonPreviewItem = firstButtonPreviewItem

	local secondButtonPreviewItem = transferButtonProcess:recursiveGetChildById("secondButtonPreviewItem")

	self.widgetStorage.secondButtonPreviewItem = secondButtonPreviewItem
	self.widgetStorage.firstButtonPreviewQuestionMark = transferButtonProcess:recursiveGetChildById("firstButtonPreviewQuestionMark")
	self.widgetStorage.secondButtonPreviewQuestionMark = transferButtonProcess:recursiveGetChildById("secondButtonPreviewQuestionMark")

	local previewTransferItem = mainPanel:recursiveGetChildById("previewTransferItem")

	self.widgetStorage.previewTransferItem = previewTransferItem

	if previewTransferItem and previewTransferItem.setFixedItemSize then
		previewTransferItem:setFixedItemSize(false)
	end

	local previewTransferItemCount = mainPanel:recursiveGetChildById("previewTransferItemCount")

	self.widgetStorage.previewTransferItemCount = previewTransferItemCount
	self.widgetStorage.previewTransferQuestionMark = mainPanel:recursiveGetChildById("previewTransferQuestionMark")
	self.widgetStorage.requiredTransferDust = mainPanel:recursiveGetChildById("requiredTransferCount1")
	self.widgetStorage.requiredTransferCoreItem = mainPanel:recursiveGetChildById("requiredCoreItem")
	self.widgetStorage.requiredTransferCoreCount = mainPanel:recursiveGetChildById("requiredCoreCount")
	self.widgetStorage.requiredTransferMoney = mainPanel:recursiveGetChildById("requiredTransferMoney")

	local requiredItem = mainPanel:recursiveGetChildById("requiredItem")

	if requiredItem then
		requiredItem:setItemId(37160)
	end

	local requiredDustIcon = mainPanel:recursiveGetChildById("requiredDustIcon")

	if requiredDustIcon then
		requiredDustIcon:setSize(tosize("9 6"))
	end

	self.widgetStorage.requiredTransferCoreItem:setItemId(37110)

	local chainTransparent = mainPanel:recursiveGetChildById("chainTransparent")

	self.widgetStorage.chainTransparent = chainTransparent

	local function proceedTransfer()
		if self.transferClickLocked then
			return
		end

		if not self:canProceedTransfer() then
			return
		end

		local firstWidget = self.widgetStorage.firstButtonPreviewItem
		local firstItem = firstWidget and firstWidget:getItem()

		if not firstWidget or not firstItem then
			return
		end

		local leftItemId = firstItem:getId()
		local leftItemTier = firstItem:getTier()
		local secondWidget = self.widgetStorage.secondButtonPreviewItem
		local secondItem = secondWidget and secondWidget:getItem()

		if not secondWidget or not secondItem then
			return
		end

		local rightItemId = secondItem:getId()

		self.transferClickLocked = true

		scheduleEvent(function()
			self.transferClickLocked = false
		end, 500)

		Forge.forceApplyNextOpenSnapshot = true
		self.lastTransferContext = {
			donorId = leftItemId,
			donorTier = leftItemTier,
			receiverId = rightItemId,
			convergence = self.widgetStorage.convergence:isChecked()
		}

		forgeSendAction(1, self.widgetStorage.convergence:isChecked(), leftItemId, leftItemTier, rightItemId)
	end

	transferButtonProcess.onClick = proceedTransfer

	if self.widgetStorage.transferButtonHoverArea then
		self.widgetStorage.transferButtonHoverArea.onClick = proceedTransfer
	end

	transferButtonProcess:raise()
	self:refreshTransferProceedState()
	self:setupHovers()
end

local function clearPreviewTransferItem(widgetStorage)
	if not widgetStorage or not widgetStorage.previewTransferItem then
		return
	end

	local previewTransferItem = widgetStorage.previewTransferItem
	local item = previewTransferItem:getItem()

	if item then
		item:setTier(0)
	end

	ItemsDatabase.setTier(previewTransferItem, 0)
	ItemsDatabase.setBigTier(previewTransferItem, 0)
	previewTransferItem:setItem(nil)
end

function Transfer:getDustCost()
	if self.widgetStorage.convergence:isChecked() then
		return self.dustConvergenceTransfer
	end

	return self.dustNormalTransfer
end

function Transfer:isConvergenceTransfer()
	return self.widgetStorage and self.widgetStorage.convergence and self.widgetStorage.convergence:isChecked()
end

function Transfer:getTransferCoreCost(donorTier)
	if not Forge.data or not Forge.data.exaltedCores or not donorTier then
		return nil
	end

	local tierKey = donorTier

	if not self:isConvergenceTransfer() then
		tierKey = donorTier - 1
	end

	return Forge.data.exaltedCores[tostring(tierKey)]
end

function Transfer:getTransferGoldCost(item, donorTier)
	if not Forge.data or not item or not donorTier then
		return nil
	end

	if self:isConvergenceTransfer() then
		local convergenceCosts = Forge.data.convergenceTransfer

		return convergenceCosts and convergenceCosts[tostring(donorTier)]
	end

	local classification = tostring(item:getClassification())
	local costTable = Forge.data.classificationTable and Forge.data.classificationTable[classification]

	return costTable and costTable[tostring(donorTier - 1)]
end

function Transfer:parseResourcesChange(data)
	if not data or not data.config then
		return
	end

	local config = data.config

	if config.dustNormalTransfer and config.dustNormalTransfer > 0 then
		self.dustNormalTransfer = config.dustNormalTransfer
	else
		self.dustNormalTransfer = DUST_NORMAL_TRANSFER
	end

	if config.dustConvergenceTransfer and config.dustConvergenceTransfer > 0 then
		self.dustConvergenceTransfer = config.dustConvergenceTransfer
	else
		self.dustConvergenceTransfer = DUST_CONVERGENCE_TRANSFER
	end
end

function Transfer:updateWidgets()
	Forge:setWidget(self.widgetStorage.previewTransferItemCount, "0/1", false)

	local dustCost = self:getDustCost()

	Forge:setWidget(self.widgetStorage.requiredTransferDust, dustCost)
	Forge:setWidget(self.widgetStorage.requiredTransferCoreCount, "???", false)
	Forge:updateWidget("dust", self.widgetStorage.requiredTransferDust, dustCost)
	self.widgetStorage.firstItemPanel:destroyChildren()
	self.widgetStorage.secondItemPanel:destroyChildren()
	Forge:setWidget(self.widgetStorage.requiredTransferMoney, "???", false)
	updateButtonPreviewSlot(self.widgetStorage.firstButtonPreviewItem, self.widgetStorage.firstButtonPreviewQuestionMark, nil)
	updateButtonPreviewSlot(self.widgetStorage.secondButtonPreviewItem, self.widgetStorage.secondButtonPreviewQuestionMark, nil)
	clearPreviewTransferItem(self.widgetStorage)
	self.widgetStorage.previewTransferQuestionMark:setVisible(true)
	self:refreshTransferProceedState()
end

function Transfer:setActiveItem(panel, id)
	if not self.activePanels then
		self.activePanels = {}
	end

	if self.activePanels[id] then
		local prev = Forge.getForgeContainerHighlightTarget(self.activePanels[id])

		if prev then
			prev:setBorderColor("alpha")
			prev:setBorderWidth(0)
		end

		self.activePanels[id]:setOpacity(1)
	end

	local highlight = Forge.getForgeContainerHighlightTarget(panel)

	if highlight then
		highlight:setBorderColor("white")
		highlight:setBorderWidth(1)
	end

	self.activePanels[id] = panel

	if not self.activePanelList then
		self.activePanelList = {}
	end

	self.activePanelList[id] = panel
end

function Transfer:displayItems()
	local data = self.transfers

	if not data then
		return
	end

	local widgetData = self.widgetStorage
	local firstItemPanel = widgetData.firstItemPanel
	local secondItemPanel = widgetData.secondItemPanel
	local firstButtonPreviewItem = widgetData.firstButtonPreviewItem
	local secondButtonPreviewItem = widgetData.secondButtonPreviewItem
	local previewTransferItem = widgetData.previewTransferItem
	local previewTransferItemCount = widgetData.previewTransferItemCount
	local previewTransferQuestionMark = widgetData.previewTransferQuestionMark
	local requiredTransferCoreCount = widgetData.requiredTransferCoreCount
	local requiredTransferMoney = widgetData.requiredTransferMoney
	local firstButtonPreviewQuestionMark = widgetData.firstButtonPreviewQuestionMark
	local secondButtonPreviewQuestionMark = widgetData.secondButtonPreviewQuestionMark

	for i, v in ipairs(data) do
		for z, donor in ipairs(v.donors) do
			local id = donor.id
			local count = donor.count
			local tier = donor.tier
			local container = g_ui.createWidget("ForgeContainerItem", firstItemPanel)

			container:setId("container " .. firstItemPanel:getId())

			local containerPanel = container:getChildById("forgeItem")
			local itemWidget = g_ui.createWidget("TransferListItem", containerPanel)

			Forge.raiseForgeContainerSelectionOverlay(containerPanel)

			local item = Item.create(id)

			item:setTier(tier)
			itemWidget:setId("item" .. z)
			itemWidget:setItem(item)
			itemWidget:setDraggable(false)
			itemWidget:setFocusable(true)
			ItemsDatabase.setRarityItem(itemWidget, item)
			ItemsDatabase.setTier(itemWidget, item)

			local label = itemWidget:getChildById("charges2")

			if label then
				label:setText(count)
				label:setVisible(true)
			end

			bindTransferSlotHover(container, itemWidget, DESCRIPTIONS.donorList)

			function itemWidget.onClick()
				secondItemPanel:destroyChildren()
				self:setActiveItem(container, container:getId())
				previewTransferItem:setItem(item)
				ItemsDatabase.setBigTier(previewTransferItem, item)
				updateButtonPreviewSlot(firstButtonPreviewItem, firstButtonPreviewQuestionMark, item)
				previewTransferQuestionMark:setVisible(false)
				Forge:setWidget(previewTransferItemCount, count .. "/" .. 1, true)

				local coreCost = self:getTransferCoreCost(tier)

				Forge:setWidget(requiredTransferCoreCount, coreCost)
				Forge:updateWidget("core", requiredTransferCoreCount, coreCost)

				local cost = self:getTransferGoldCost(item, tier)

				Forge:setWidget(requiredTransferMoney, cost)
				Forge:updateWidget("money", requiredTransferMoney, cost)
				requiredTransferMoney:setText(Forge:formatNumber(cost))
				self:refreshTransferProceedState()

				for n, receiver in ipairs(v.receivers) do
					local id2 = receiver.id

					if id2 ~= id then
						local count = receiver.count
						local tier = receiver.tier
						local container = g_ui.createWidget("ForgeContainerItem", secondItemPanel)

						container:setId("container " .. secondItemPanel:getId())

						local containerPanel = container:getChildById("forgeItem")
						local itemWidget = g_ui.createWidget("TransferListItem", containerPanel)

						Forge.raiseForgeContainerSelectionOverlay(containerPanel)

						local item = Item.create(id2)

						item:setTier(tier)
						itemWidget:setId("item" .. z)
						itemWidget:setItem(item)
						itemWidget:setDraggable(false)
						itemWidget:setFocusable(true)
						ItemsDatabase.setRarityItem(itemWidget, item)
						ItemsDatabase.setTier(itemWidget, item)

						local label = itemWidget:getChildById("charges2")

						if label then
							label:setText(count)
							label:setVisible(true)
						end

						bindTransferSlotHover(container, itemWidget, DESCRIPTIONS.receiverList)

						function itemWidget.onClick()
							self:setActiveItem(container, container:getId())
							item:setTier(donor.tier - 1)
							updateButtonPreviewSlot(secondButtonPreviewItem, secondButtonPreviewQuestionMark, item)
							self:refreshTransferProceedState()
						end
					end
				end
			end
		end
	end
end

function Transfer:displayConvergence()
	local data = self.convergenceTransfers

	if not data then
		return
	end

	local widgetData = self.widgetStorage
	local firstItemPanel = widgetData.firstItemPanel
	local secondItemPanel = widgetData.secondItemPanel
	local firstButtonPreviewItem = widgetData.firstButtonPreviewItem
	local secondButtonPreviewItem = widgetData.secondButtonPreviewItem
	local previewTransferItem = widgetData.previewTransferItem
	local previewTransferItemCount = widgetData.previewTransferItemCount
	local previewTransferQuestionMark = widgetData.previewTransferQuestionMark
	local requiredTransferCoreCount = widgetData.requiredTransferCoreCount
	local requiredTransferMoney = widgetData.requiredTransferMoney
	local firstButtonPreviewQuestionMark = widgetData.firstButtonPreviewQuestionMark
	local secondButtonPreviewQuestionMark = widgetData.secondButtonPreviewQuestionMark

	for i, v in ipairs(data) do
		for z, donor in ipairs(v.donors) do
			local id = donor.id
			local count = donor.count
			local tier = donor.tier
			local container = g_ui.createWidget("ForgeContainerItem", firstItemPanel)

			container:setId("container " .. firstItemPanel:getId())

			local containerPanel = container:getChildById("forgeItem")
			local itemWidget = g_ui.createWidget("TransferListItem", containerPanel)

			Forge.raiseForgeContainerSelectionOverlay(containerPanel)

			local item = Item.create(id)

			item:setTier(tier)
			itemWidget:setId("item" .. z)
			itemWidget:setItem(item)
			itemWidget:setDraggable(false)
			itemWidget:setFocusable(true)
			ItemsDatabase.setRarityItem(itemWidget, item)
			ItemsDatabase.setTier(itemWidget, item)

			local label = itemWidget:getChildById("charges2")

			if label then
				label:setText(count)
				label:setVisible(true)
			end

			bindTransferSlotHover(container, itemWidget, DESCRIPTIONS.donorList)

			function itemWidget.onClick()
				updateButtonPreviewSlot(secondButtonPreviewItem, secondButtonPreviewQuestionMark, nil)
				secondItemPanel:destroyChildren()
				self:setActiveItem(container, container:getId())
				previewTransferItem:setItem(item)
				ItemsDatabase.setBigTier(previewTransferItem, item)
				updateButtonPreviewSlot(firstButtonPreviewItem, firstButtonPreviewQuestionMark, item)
				previewTransferQuestionMark:setVisible(false)
				Forge:setWidget(previewTransferItemCount, count .. "/" .. 1, true)

				local coreCost = self:getTransferCoreCost(tier)

				Forge:setWidget(requiredTransferCoreCount, coreCost)
				Forge:updateWidget("core", requiredTransferCoreCount, coreCost)

				local cost = self:getTransferGoldCost(item, tier)

				Forge:setWidget(requiredTransferMoney, cost)
				Forge:updateWidget("money", requiredTransferMoney, cost)
				requiredTransferMoney:setText(Forge:formatNumber(cost))
				self:refreshTransferProceedState()

				for n, receiver in ipairs(v.receivers) do
					local id2 = receiver.id

					if id2 ~= id then
						local count = receiver.count
						local tier = receiver.tier
						local container = g_ui.createWidget("ForgeContainerItem", secondItemPanel)

						container:setId("container " .. secondItemPanel:getId())

						local containerPanel = container:getChildById("forgeItem")
						local itemWidget = g_ui.createWidget("TransferListItem", containerPanel)

						Forge.raiseForgeContainerSelectionOverlay(containerPanel)

						local item = Item.create(id2)

						item:setTier(receiver.tier)
						itemWidget:setId("item" .. z)
						itemWidget:setItem(item)
						itemWidget:setDraggable(false)
						itemWidget:setFocusable(true)
						ItemsDatabase.setRarityItem(itemWidget, item)
						ItemsDatabase.setTier(itemWidget, item)

						local label = itemWidget:getChildById("charges2")

						if label then
							label:setText(count)
							label:setVisible(true)
						end

						bindTransferSlotHover(container, itemWidget, DESCRIPTIONS.receiverList)

						function itemWidget.onClick()
							local item = Item.create(id2)

							item:setTier(donor.tier)
							updateButtonPreviewSlot(secondButtonPreviewItem, secondButtonPreviewQuestionMark, item)
							self:setActiveItem(container, container:getId())
							self:refreshTransferProceedState()
						end
					end
				end
			end
		end
	end
end

function Transfer:parseData(data)
	if Forge.data then
		self:parseResourcesChange(Forge.data)
	end

	scheduleEvent(function()
		self:updateWidgets()

		self.transfers = data.transfers
		self.convergenceTransfers = data.convergenceTransfers

		if self.widgetStorage.convergence:isChecked() then
			self:displayConvergence()
		else
			self:displayItems()
		end
	end, 10)
end

function Transfer:applyTransferResult(data)
	local ctx = self.lastTransferContext

	if not ctx or not data then
		return
	end

	local transferList = ctx.convergence and self.convergenceTransfers or self.transfers

	if not transferList then
		return
	end

	local donorId = ctx.donorId
	local donorTier = ctx.donorTier
	local receiverId = ctx.receiverId
	local receiverTier = data.rightTier

	for i = #transferList, 1, -1 do
		local group = transferList[i]
		local donorMatched = false

		for j = #group.donors, 1, -1 do
			local donor = group.donors[j]

			if donor.id == donorId and donor.tier == donorTier then
				donor.count = donor.count - 1

				if donor.count <= 0 then
					table.remove(group.donors, j)
				end

				donorMatched = true

				break
			end
		end

		if donorMatched then
			if #group.donors == 0 then
				table.remove(transferList, i)

				break
			end

			for _, receiver in ipairs(group.receivers) do
				if receiver.id == receiverId then
					receiver.tier = receiverTier
				end
			end

			break
		end
	end
end

function Transfer:parseResult(data)
	if self.mainWindow and self.mainWindow:isVisible() then
		self.mainWindow:setVisible(false)
	end

	if data and data.success == 1 then
		self:applyTransferResult(data)
	end

	self.lastTransferContext = nil
end
