-- chunkname: @/game_forge/menu/fusion/fusion.lua

Forge.Fusion = {}

local Fusion = Forge.Fusion

Fusion.mainWindow = nil

local DUST_NORMAL_FUSION = 100
local DUST_CONVERGENCE_FUSION = 130
local BASE_FUSION_CHANCE = 50
local IMPROVED_FUSION_CHANCE = 15
local TIER_LOSS_REDUCTION = 50
local DESCRIPTIONS = {
	improveSuccess = "Improve your chances! Click here to raise your chance for a successful fusion from %d%% to %d%% at the cost of one exalted core.",
	selectItemAbove = "Please select an item above to continue.",
	improveSuccessActive = "Click here if you do not want to use the exalted core. This will reduce your chance from %d%% to %d%%.",
	selectItems = "Select an item you want to fuse.",
	reduceTierLoss = "Reduce your losses! Click here to pay one exalted core and with that get a %d%% chance of keeping the tier of the second item in case the fusion fails.",
	selectAllIngredients = "Please select all required ingredients.",
	reduceTierLossActive = "Click here if you do not want to use the exalted core. Note that you will lose the chance to keep the tier on the second item in case the fusion fails.",
	notEnoughIngredients = "You do not have all the ingredients you need.",
	fusionReady = "Click here to start a fusion attempt. This will consume or alter the required ingredients.",
	convergence = "A Convergence fusion uses items of different types but the same classification.",
	dustRequirement = "A fusion requires %d dust. Be warned! The dust will be consumed even if the fusion fails.",
	consumedItem = "You need %s with tier %d to fuse."
}
local REQUIREMENTS_SLOT_IDS = {
	requiredDustHoverArea = "dust",
	tierLossHoverArea = "tierLoss",
	previewFusionHoverArea = "preview",
	improveButton = "improve",
	tierLossButton = "tierLoss",
	improveHoverArea = "improve",
	convergenceDustHoverArea = "dust"
}
local FUSION_ACTION_WIDGET_IDS = {
	fusionButtonProcced = true,
	fusionButtonHoverArea = true,
	fusionActionWrapper = true
}
local TOOLTIP_RESET_IDS = {
	fusionHelpIcon3 = true,
	fusionHelpIcon2 = true,
	fusionHelpIcon1 = true,
	fusionHelpLine4 = true,
	fusionHelpLine3 = true,
	fusionHelpLine2 = true,
	fusionHelpLine1 = true,
	defaultConvergenceDescriptionPanel = true,
	defaultDescriptionPanel = true,
	description = true,
	firstTooltip = true,
	convergenceHelpText4 = true,
	convergenceHelpText3 = true,
	convergenceHelpText2 = true,
	convergenceHelpText1 = true,
	convergenceHelpIcon1 = true,
	convergenceHelpLine4 = true,
	convergenceHelpLine3 = true,
	convergenceHelpLine2 = true,
	convergenceHelpLine1 = true,
	fusionHelpIcon4 = true
}
local ws = {}
local descriptionRefreshEvent
local DESCRIPTION_BY_SLOT = {
	preview = function()
		return Fusion:describePreviewItemRequirement()
	end,
	dust = function()
		return Fusion:describeDustRequirement()
	end,
	improve = function()
		return Fusion:describeImproveSuccess()
	end,
	tierLoss = function()
		return Fusion:describeReduceTierLoss()
	end
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

local function setWidgetsVisible(widgets, visible)
	for _, w in ipairs(widgets) do
		if w then
			w:setVisible(visible)
		end
	end
end

function Fusion:setDescription(text)
	if not text or text == "" then
		self:resetDescription()

		return
	end

	if self.defaultDescriptionPanel then
		self.defaultDescriptionPanel:setVisible(false)
	end

	if self.defaultConvergenceDescriptionPanel then
		self.defaultConvergenceDescriptionPanel:setVisible(false)
	end

	if self.descriptionLabel then
		self.descriptionLabel:setVisible(true)
		self.descriptionLabel:setText(text)
	end
end

function Fusion:resetDescription()
	if self.descriptionLabel then
		self.descriptionLabel:setVisible(false)
		self.descriptionLabel:setText("")
	end

	if self:isConvergenceFusion() then
		if self.defaultDescriptionPanel then
			self.defaultDescriptionPanel:setVisible(false)
		end

		if self.defaultConvergenceDescriptionPanel then
			self.defaultConvergenceDescriptionPanel:setVisible(true)
			self.defaultConvergenceDescriptionPanel:raise()
		end

		return
	end

	if self.defaultConvergenceDescriptionPanel then
		self.defaultConvergenceDescriptionPanel:setVisible(false)
	end

	if self.defaultDescriptionPanel then
		self.defaultDescriptionPanel:setVisible(true)
		self.defaultDescriptionPanel:raise()
	end
end

function Fusion:isConvergenceFusion()
	return self.convergenceWidget and self.convergenceWidget:isChecked()
end

function Fusion:getDustCost()
	if self:isConvergenceFusion() then
		return self.dustConvergenceFusion and self.dustConvergenceFusion > 0 and self.dustConvergenceFusion or DUST_CONVERGENCE_FUSION
	end

	return self.dustNormalFusion and self.dustNormalFusion > 0 and self.dustNormalFusion or DUST_NORMAL_FUSION
end

function Fusion:describePreviewItemRequirement()
	local item = ws.previewFusionItem2 and ws.previewFusionItem2:getItem()

	if not item then
		return DESCRIPTIONS.selectItemAbove
	end

	return string.format(DESCRIPTIONS.consumedItem, getItemDisplayName(item), item:getTier())
end

function Fusion:describeDustRequirement()
	return string.format(DESCRIPTIONS.dustRequirement, self:getDustCost())
end

function Fusion:describeImproveSuccess()
	if Fusion.improveClicked then
		return string.format(DESCRIPTIONS.improveSuccessActive, self:getImprovedTotalChance(), self:getBaseChance())
	end

	return string.format(DESCRIPTIONS.improveSuccess, self:getBaseChance(), self:getImprovedTotalChance())
end

function Fusion:describeReduceTierLoss()
	if Fusion.tierLossClicked then
		return DESCRIPTIONS.reduceTierLossActive
	end

	return string.format(DESCRIPTIONS.reduceTierLoss, self:getTierLossReducedChance())
end

function Fusion:hasConvergenceFusionItemsSelected()
	return self.leftItemId and self.rightItemId and self.fusionTier
end

function Fusion:describeFusionAction()
	if self:isConvergenceFusion() then
		if not self:hasConvergenceFusionItemsSelected() then
			return DESCRIPTIONS.selectAllIngredients
		end

		return self:canProceedFusion() and DESCRIPTIONS.fusionReady or DESCRIPTIONS.notEnoughIngredients
	end

	local firstItem = ws.fusionItem1 and ws.fusionItem1:getItem()
	local secondItem = ws.fusionItem2 and ws.fusionItem2:getItem()

	if not firstItem or not secondItem then
		return DESCRIPTIONS.selectItems
	end

	return self:canProceedFusion() and DESCRIPTIONS.fusionReady or DESCRIPTIONS.notEnoughIngredients
end

function Fusion:proceedFusion()
	if Fusion.fusionClickLocked or not self:canProceedFusion() then
		return
	end

	Fusion.fusionClickLocked = true

	scheduleEvent(function()
		Fusion.fusionClickLocked = false
	end, 500)

	Forge.forceApplyNextOpenSnapshot = true
	self.lastFusionContext = {
		leftItemId = self.leftItemId,
		rightItemId = self.rightItemId,
		fusionTier = self.fusionTier,
		convergence = self.convergenceWidget:isChecked()
	}

	forgeSendAction(0, self.convergenceWidget:isChecked(), self.leftItemId, self.fusionTier, self.rightItemId, self.improveClicked == true, self.tierLossClicked == true)
end

function Fusion.getRequirementsSlotId(widget)
	local current = widget

	while current do
		local slotId = REQUIREMENTS_SLOT_IDS[current:getId()]

		if slotId then
			return slotId
		end

		if current == Fusion.mainWindow then
			break
		end

		current = current:getParent()
	end

	return nil
end

function Fusion.isFusionActionWidget(widget)
	local current = widget

	while current do
		if FUSION_ACTION_WIDGET_IDS[current:getId()] then
			return true
		end

		if current == Fusion.mainWindow then
			break
		end

		current = current:getParent()
	end

	return false
end

local function isRequirementsAreaHovered()
	if not Fusion.mainWindow then
		return false
	end

	local target = Fusion.mainWindow:recursiveGetChildByPos(g_window.getMousePosition(), false)

	return Fusion.getRequirementsSlotId(target) ~= nil or Fusion.isFusionActionWidget(target)
end

local function refreshDescriptionFromMouse()
	if not Fusion.mainWindow or not Fusion.mainWindow:isVisible() then
		return
	end

	local target = Fusion.mainWindow:recursiveGetChildByPos(g_window.getMousePosition(), false)

	if target then
		Fusion.onHover(target)
	else
		Fusion:resetDescription()
	end
end

function Fusion.onDefaultDescriptionHover(widget, hovered)
	if not hovered then
		return
	end

	if not Fusion.mainWindow or not Fusion.mainWindow:isVisible() then
		return
	end

	Fusion:resetDescription()
end

function Fusion.onRequirementsDefaultDescriptionHover(widget, hovered)
	if not hovered then
		return
	end

	if not Fusion.mainWindow or not Fusion.mainWindow:isVisible() then
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
			Fusion:resetDescription()
		end
	end, 1)
end

function Fusion.onHover(widget)
	if not Fusion.mainWindow or not Fusion.mainWindow:isVisible() then
		return
	end

	if not widget or not widget:isVisible() then
		return
	end

	local id = widget:getId()

	if TOOLTIP_RESET_IDS[id] then
		Fusion:resetDescription()

		return
	end

	if Fusion.isFusionActionWidget(widget) then
		Fusion:setDescription(Fusion:describeFusionAction())

		return
	end

	if id == "convergence" then
		Fusion:setDescription(DESCRIPTIONS.convergence)

		return
	end

	local slotId = Fusion.getRequirementsSlotId(widget)
	local descFn = slotId and DESCRIPTION_BY_SLOT[slotId]

	if descFn then
		Fusion:setDescription(descFn())

		return
	end

	Fusion:resetDescription()
end

local function bindDefaultDescriptionHover(widget)
	if not widget then
		return
	end

	function widget.onHoverChange(hovered)
		Fusion.onDefaultDescriptionHover(widget, hovered)
	end
end

local function bindFusionSlotHover(container, itemWidget, description)
	if itemWidget then
		function itemWidget.onHoverChange(hovered)
			if not Fusion.mainWindow or not Fusion.mainWindow:isVisible() then
				return
			end

			if hovered then
				if descriptionRefreshEvent then
					removeEvent(descriptionRefreshEvent)

					descriptionRefreshEvent = nil
				end

				Fusion:setDescription(description)
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

			if not Fusion.mainWindow or not Fusion.mainWindow:isVisible() then
				return
			end

			if itemWidget and itemWidget:isHovered() then
				return
			end

			Fusion:resetDescription()
		end
	end
end

local function bindRequirementsDefaultHover(widget)
	if not widget then
		return
	end

	function widget.onHoverChange(hovered)
		Fusion.onRequirementsDefaultDescriptionHover(widget, hovered)
	end
end

function Fusion.onWidgetHover(widget, hovered)
	if hovered then
		if descriptionRefreshEvent then
			removeEvent(descriptionRefreshEvent)

			descriptionRefreshEvent = nil
		end

		Fusion.onHover(widget)

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
			if hovered and Fusion.mainWindow and Fusion.mainWindow:isVisible() then
				Fusion:resetDescription()
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

function Fusion:setupHovers()
	setupForgeAreaClearHover()

	local mainWindow = self.mainWindow

	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("mainPanel1"))
	bindDefaultDescriptionHover(self.contentPanel)
	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("previewPanel"))
	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("fusionScrollBar"))
	bindDefaultDescriptionHover(mainWindow:recursiveGetChildById("fusionScrollBar2"))
	bindRequirementsDefaultHover(ws.previewPanel2)
end

function Fusion:get()
	return self
end

function Fusion:getBaseChance()
	return self.baseChance and self.baseChance > 0 and self.baseChance or BASE_FUSION_CHANCE
end

function Fusion:getImprovedChanceBonus()
	return self.improvedChance and self.improvedChance > 0 and self.improvedChance or IMPROVED_FUSION_CHANCE
end

function Fusion:getImprovedTotalChance()
	return self:getBaseChance() + self:getImprovedChanceBonus()
end

function Fusion:getTierLossReducedChance()
	return self.tierLossReduction and self.tierLossReduction > 0 and self.tierLossReduction or TIER_LOSS_REDUCTION
end

function Fusion:refreshDustRequirementWidgets()
	local dustCost = self:getDustCost()

	if self:isConvergenceFusion() then
		if ws.convergenceDustCountValue then
			Forge:setWidget(ws.convergenceDustCountValue, dustCost, true)
			Forge:updateWidget("dust", ws.convergenceDustCountValue, dustCost)
		end
	elseif ws.requiredCount then
		Forge:setWidget(ws.requiredCount, dustCost, true)
		Forge:updateWidget("dust", ws.requiredCount, dustCost)
	end
end

function Fusion:refreshChanceWidgets()
	local ib = ws.improveButton
	local tlb = ws.tierLossButton
	local srv = ws.successRateValue
	local tlv = ws.tierLossValue

	if not ib or not tlb or not srv or not tlv then
		return
	end

	ib:setText(string.format("Improve to %d%%", self:getImprovedTotalChance()))
	tlb:setText(string.format("Reduce to %d%%", self:getTierLossReducedChance()))

	if Fusion.improveClicked then
		srv:setColor("#44AD25")
		srv:setText(self:getImprovedTotalChance() .. "%")
	else
		srv:setColor("#F75F5F")
		srv:setText(self:getBaseChance() .. "%")
	end

	if Fusion.tierLossClicked then
		tlv:setColor("#44AD25")
		tlv:setText(self:getTierLossReducedChance() .. "%")
	else
		tlv:setColor("#F75F5F")
		tlv:setText("100%")
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

local function clearPreviewFusionItem()
	local w = ws.previewFusionItem

	if not w then
		return
	end

	local item = w:getItem()

	if item then
		item:setTier(0)
	end

	ItemsDatabase.setTier(w, 0)
	ItemsDatabase.setBigTier(w, 0)
	w:setItem(nil)
	w:setColor(nil)
end

local function clearPreviewFusionForgeItem()
	local w = ws.previewFusionItem2

	if not w then
		return
	end

	local item = w:getItem()

	if item then
		item:setTier(0)
	end

	ItemsDatabase.setTier(w, 0)
	ItemsDatabase.setBigTier(w, 0)
	w:setItem(nil)

	if ws.previewFusionQuestionMark2 then
		ws.previewFusionQuestionMark2:setVisible(true)
	end
end

local function clearFusionButtonPreview()
	updateButtonPreviewSlot(ws.fusionItem1, ws.fusionItem1QuestionMark, nil)
	updateButtonPreviewSlot(ws.fusionItem2, ws.fusionItem2QuestionMark, nil)
end

local function resetFusionSelectionContext(self)
	self.leftItemId = nil
	self.rightItemId = nil
	self.fusionTier = nil
end

local function resetFusionUiState(self)
	clearPreviewFusionItem()
	clearPreviewFusionForgeItem()
	clearFusionButtonPreview()
	resetFusionSelectionContext(self)

	if ws.previewFusionQuestionMark then
		ws.previewFusionQuestionMark:setVisible(true)
	end

	if ws.fusionCost then
		Forge:setWidget(ws.fusionCost, "???", false)
	end
end

function Fusion:canProceedFusion()
	local f1 = ws.fusionItem1 and ws.fusionItem1:getItem()
	local f2 = ws.fusionItem2 and ws.fusionItem2:getItem()

	if not f1 or not f2 then
		return false
	end

	if not self.leftItemId or not self.fusionTier then
		return false
	end

	if self:isConvergenceFusion() and not self.rightItemId then
		return false
	end

	local costText = ws.fusionCost and ws.fusionCost:getText() or "0"
	local cost = tonumber((costText:gsub(",", "")))

	if not cost or cost > Forge:getResourceBalance("money") then
		return false
	end

	if Forge:getResourceBalance("dust") < self:getDustCost() then
		return false
	end

	return true
end

function Fusion:refreshFusionProceedState()
	if not ws.fusionButtonProcced or Forge.preview then
		return
	end

	local canProceed = self:canProceedFusion()

	if ws.chainTransparent then
		ws.chainTransparent:setVisible(not canProceed)

		if not canProceed then
			ws.chainTransparent:raise()
		end
	end

	if ws.fusionRequirementsArrow then
		ws.fusionRequirementsArrow:raise()
	end

	if ws.convergenceRequirementsArrow then
		ws.convergenceRequirementsArrow:raise()
	end
end

function Fusion:createButton()
	local buttonPanel = g_ui.createWidget("ForgeButton", Forge.mainWindow)

	buttonPanel:setId("FusionButton")

	self.buttonPanel = buttonPanel
	self.mainButton = buttonPanel:getChildById("button")

	self.mainButton:setText("Fusion")
	Forge.setupTabButtonIcon(buttonPanel, "/images/icons_big/icon-fusion", 6, 3)
	g_ui.importStyle("fusion")

	self.mainWindow = g_ui.createWidget("FusionWindow", Forge.mainWindow)

	self.mainWindow:setVisible(false)
	self.mainWindow:addAnchor(AnchorTop, "FusionButton", AnchorBottom)
	self.mainWindow:addAnchor(AnchorLeft, "FusionButton", AnchorLeft)
	self.mainWindow:addAnchor(AnchorRight, "parent", AnchorRight)
	self.mainWindow:addAnchor(AnchorBottom, "parent", AnchorBottom)
	self:init()

	function self.mainButton.onClick()
		self:showWindow()
	end
end

function Fusion:showWindowCore()
	if Forge.currentPanel then
		Forge.currentPanel:setVisible(false)
	end

	if Forge.currentButton then
		Forge.currentButton:setEnabled(true)
		Forge.onTabButtonEnabled(Forge.currentButton, nil, true)
	end

	Forge.currentPanel = self.mainWindow
	Forge.currentButton = self.mainButton

	Forge.firstTooltip:setVisible(false)
	self.mainWindow:setVisible(true)
	self.mainWindow:raise()
	self.mainButton:setEnabled(false)
	Forge.onTabButtonEnabled(nil, self.buttonPanel, false)
	self:resetDescription()
end

function Fusion:refreshListView()
	self.activePanels = nil
	self.activePanelList = nil

	if not self.data then
		self:updateWidgets()

		return
	end

	if self.convergenceWidget:isChecked() then
		self:displayConvergence()
	else
		self:displayItems()
	end

	self:refreshFusionProceedState()
end

function Fusion:showWindow()
	self:showWindowCore()
	self:refreshListView()
end

local function toggleCoreOption(self, option)
	local isImprove = option == "improve"
	local thisFlag = isImprove and "improveClicked" or "tierLossClicked"
	local thisButton = isImprove and ws.improveButton or ws.tierLossButton
	local otherButton = isImprove and ws.tierLossButton or ws.improveButton
	local otherCoreVal = isImprove and ws.exaltedCorePanel2Value or ws.exaltedCorePanelValue

	if Fusion[thisFlag] then
		Fusion[thisFlag] = nil

		thisButton:setOn(false)

		if Forge:getResourceBalance("core") >= 1 then
			otherButton:setEnabled(true)
			Forge:setWidget(otherCoreVal, 1, true)
		end
	else
		Fusion[thisFlag] = true

		thisButton:setOn(true)

		if Forge:getResourceBalance("core") < 2 then
			otherButton:setEnabled(false)
			Forge:setWidget(otherCoreVal, 1, false)
		end
	end

	self:refreshChanceWidgets()
	refreshDescriptionFromMouse()
end

function Fusion:init()
	self.data = nil
	self.fusionClickLocked = false
	self.dustNormalFusion = DUST_NORMAL_FUSION
	self.dustConvergenceFusion = DUST_CONVERGENCE_FUSION
	self.baseChance = BASE_FUSION_CHANCE
	self.improvedChance = IMPROVED_FUSION_CHANCE
	self.tierLossReduction = TIER_LOSS_REDUCTION

	local mainPanel1 = self.mainWindow:recursiveGetChildById("mainPanel1")

	self.contentPanel = mainPanel1:recursiveGetChildById("contentPanel")

	local previewPanel = mainPanel1:recursiveGetChildById("previewPanel")

	self.convergenceWidget = previewPanel:recursiveGetChildById("convergence")
	ws.previewFusionItem = previewPanel:recursiveGetChildById("previewItem")
	ws.previewFusionQuestionMark = previewPanel:recursiveGetChildById("previewQuestionMark")

	local pp2 = self.mainWindow:recursiveGetChildById("previewPanel2")

	ws.previewPanel2 = pp2
	ws.fusionContent2 = pp2:recursiveGetChildById("fusionContent2")
	ws.fusionContent2ScrollBar = pp2:recursiveGetChildById("fusionScrollBar2")
	ws.previewFusionForgeItem = pp2:recursiveGetChildById("previewFusionForgeItem")
	ws.requiredForgeItem = pp2:recursiveGetChildById("requiredForgeItem")
	ws.convergenceDustForgeItem = pp2:recursiveGetChildById("convergenceDustForgeItem")
	ws.improveForgePanel = pp2:recursiveGetChildById("improveForgePanel")
	ws.tierLossForgePanel = pp2:recursiveGetChildById("tierLossForgePanel")
	ws.fusionRequirementsArrow = pp2:recursiveGetChildById("fusionRequirementsArrow")
	ws.convergenceRequirementsArrow = pp2:recursiveGetChildById("convergenceRequirementsArrow")
	ws.previewFusionItem2 = pp2:recursiveGetChildById("previewItem")

	if ws.previewFusionItem2 and ws.previewFusionItem2.setFixedItemSize then
		ws.previewFusionItem2:setFixedItemSize(false)
	end

	ws.previewFusionQuestionMark2 = pp2:recursiveGetChildById("previewQuestionMark")
	ws.previewFusionItem2Value = pp2:recursiveGetChildById("previewCount"):recursiveGetChildById("value")

	local fusionBtn = pp2:recursiveGetChildById("fusionButtonProcced")

	ws.fusionButtonProcced = fusionBtn
	ws.chainTransparent = fusionBtn:recursiveGetChildById("chainTransparent")
	ws.fusionItem1 = fusionBtn:recursiveGetChildById("firstButtonPreviewItem")
	ws.fusionItem2 = fusionBtn:recursiveGetChildById("secondButtonPreviewItem")
	ws.fusionItem1QuestionMark = fusionBtn:recursiveGetChildById("firstButtonPreviewQuestionMark")
	ws.fusionItem2QuestionMark = fusionBtn:recursiveGetChildById("secondButtonPreviewQuestionMark")
	ws.fusionButtonHoverArea = pp2:recursiveGetChildById("fusionButtonHoverArea")
	ws.fusionCost = pp2:recursiveGetChildById("requiredFusionMoney")

	local requiredItem = pp2:recursiveGetChildById("requiredItem")

	if requiredItem then
		requiredItem:setItemId(37160)
	end

	local requiredDustIcon = pp2:recursiveGetChildById("requiredDustIcon")

	if requiredDustIcon then
		requiredDustIcon:setSize(tosize("9 6"))
	end

	ws.requiredCount = pp2:recursiveGetChildById("requiredCount"):recursiveGetChildById("value")
	ws.improveButton = pp2:recursiveGetChildById("improveButton")
	ws.exaltedCorePanel = pp2:recursiveGetChildById("exaltedCorePanel")
	ws.exaltedCorePanelValue = ws.exaltedCorePanel:recursiveGetChildById("value")
	ws.successRateValue = pp2:recursiveGetChildById("successRateValue")
	ws.tierLossButton = pp2:recursiveGetChildById("tierLossButton")
	ws.exaltedCorePanel2 = pp2:recursiveGetChildById("exaltedCorePanel2")
	ws.exaltedCorePanel2Value = ws.exaltedCorePanel2:recursiveGetChildById("value")
	ws.tierLossValue = pp2:recursiveGetChildById("tierLossValue")

	local convergenceDustCountPanel = pp2:recursiveGetChildById("convergenceDustCountPanel")

	ws.convergenceDustCountValue = convergenceDustCountPanel:recursiveGetChildById("value")

	local convergenceDustItem = pp2:recursiveGetChildById("convergenceDustItem")

	if convergenceDustItem then
		convergenceDustItem:setItemId(37160)
	end

	local convergenceDustIcon = pp2:recursiveGetChildById("convergenceDustIcon")

	if convergenceDustIcon then
		convergenceDustIcon:setSize(tosize("9 6"))
	end

	local tooltipPanel = self.mainWindow:getChildById("firstTooltip")

	self.defaultDescriptionPanel = tooltipPanel:getChildById("defaultDescriptionPanel")
	self.defaultConvergenceDescriptionPanel = tooltipPanel:getChildById("defaultConvergenceDescriptionPanel")
	self.descriptionLabel = tooltipPanel:getChildById("description")
	self.widgetStorage = ws

	function fusionBtn.onClick()
		Fusion:proceedFusion()
	end

	if ws.fusionButtonHoverArea then
		function ws.fusionButtonHoverArea.onClick()
			Fusion:proceedFusion()
		end
	end

	function ws.improveButton.onClick()
		toggleCoreOption(self, "improve")
	end

	function ws.tierLossButton.onClick()
		toggleCoreOption(self, "tierLoss")
	end

	function self.convergenceWidget.onClick(widget)
		if not widget:isChecked() then
			widget:setChecked(true)
			self:displayConvergence()
			pp2:setText("Further Items Needed For Convergence Fusion")
		else
			widget:setChecked(false)
			self:displayItems()
			pp2:setText("Further Items Needed For Fusion")
		end

		self:resetDescription()
	end

	fusionBtn:raise()
	ws.improveButton:raise()
	ws.tierLossButton:raise()

	if ws.fusionRequirementsArrow then
		ws.fusionRequirementsArrow:raise()
	end

	if ws.convergenceRequirementsArrow then
		ws.convergenceRequirementsArrow:raise()
	end

	self:refreshChanceWidgets()
	self:refreshDustRequirementWidgets()
	clearPreviewFusionForgeItem()
	ws.previewFusionQuestionMark:setVisible(true)
	self:resetDescription()
	self:refreshFusionProceedState()
	self:setupHovers()
end

function Fusion:resetConvergenceMode()
	if not self.convergenceWidget or not self.convergenceWidget:isChecked() then
		return
	end

	self.convergenceWidget:setChecked(false)

	if ws.previewPanel2 then
		ws.previewPanel2:setText("Further Items Needed For Fusion")
	end

	if self.data then
		self:displayItems()
	else
		self:updateWidgets()
	end

	self:resetDescription()
end

local function getConventionalPanels()
	return {
		ws.previewFusionForgeItem,
		ws.requiredForgeItem,
		ws.improveForgePanel,
		ws.tierLossForgePanel,
		ws.fusionRequirementsArrow
	}
end

local function getConvergencePanels()
	return {
		ws.fusionContent2,
		ws.fusionContent2ScrollBar,
		ws.convergenceDustForgeItem,
		ws.convergenceRequirementsArrow
	}
end

function Fusion:updateWidgets()
	local isConvergence = self.convergenceWidget:isChecked()

	setWidgetsVisible(getConventionalPanels(), not isConvergence)
	setWidgetsVisible(getConvergencePanels(), isConvergence)
	ws.previewPanel2:setVisible(true)
	resetFusionUiState(self)
	self:refreshFusionProceedState()
end

function Fusion:setActiveItem(panel, id)
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

local function createFusionListItem(parentPanel, itemId, tier, count, index, onClick)
	local container = g_ui.createWidget("ForgeContainerItem", parentPanel)

	container:setId("container " .. parentPanel:getId())

	local containerPanel = container:getChildById("forgeItem")
	local itemWidget = g_ui.createWidget("FusionListItem", containerPanel)

	Forge.raiseForgeContainerSelectionOverlay(containerPanel)

	local item = Item.create(itemId)

	item:setTier(tier)
	itemWidget:setId("item" .. index)
	itemWidget:setItem(item)
	itemWidget:setDraggable(false)
	itemWidget:setFocusable(true)

	local label = itemWidget:getChildById("charges2")

	if label then
		label:setText(count)
		label:setVisible(true)
	end

	ItemsDatabase.setRarityItem(itemWidget, item, nil, true)
	ItemsDatabase.setTier(itemWidget, item)
	bindFusionSlotHover(container, itemWidget, DESCRIPTIONS.selectItems)

	itemWidget.onClick = onClick

	return container, itemWidget, item
end

local function resetImproveReduceOptions(self)
	scheduleEvent(function()
		self:refreshDustRequirementWidgets()
		Forge:updateWidget("core", ws.exaltedCorePanel2Value, 1)
		Forge:updateWidget("core", ws.exaltedCorePanelValue, 1)
		ws.tierLossButton:setEnabled(true)

		Fusion.tierLossClicked = nil

		ws.tierLossButton:setOn(false)
		ws.improveButton:setEnabled(true)

		Fusion.improveClicked = nil

		ws.improveButton:setOn(false)
		self:refreshChanceWidgets()

		if Forge:getResourceBalance("core") < 1 then
			ws.tierLossButton:setEnabled(false)
			ws.improveButton:setEnabled(false)
		end
	end, 10)
end

function Fusion:displayItems()
	-- Keep the current selection while a live forge refresh rebuilds the list.
	-- The item will be selected again below if it is still present in the new data.
	local selectedItemId = self.leftItemId
	local selectedTier = self.fusionTier
	local restoreSelection

	Forge:setWidget(ws.previewFusionItem2Value, "0/1", false)
	self:updateWidgets()
	resetImproveReduceOptions(self)
	self.contentPanel:destroyChildren()

	if not self.data then
		return
	end

	for i, v in ipairs(self.data.fusionItems) do
		local id = tonumber(v.id)
		local capturedItem, container

		local function selectItem()
			self:setActiveItem(container, container:getId())
			ws.previewFusionQuestionMark:setVisible(false)
			ws.previewFusionQuestionMark2:setVisible(false)
			ws.previewFusionItem2:setItem(capturedItem)
			ItemsDatabase.setBigTier(ws.previewFusionItem2, capturedItem)
			Forge:setWidget(ws.previewFusionItem2Value, v.count .. "/1", true)

			local nextItem = Item.create(id)

			nextItem:setTier(v.tier + 1)
			ws.previewFusionItem:setItem(nextItem)
			ItemsDatabase.setBigTier(ws.previewFusionItem, nextItem)
			ws.previewFusionItem:setColor("black")
			updateButtonPreviewSlot(ws.fusionItem1, ws.fusionItem1QuestionMark, capturedItem)
			updateButtonPreviewSlot(ws.fusionItem2, ws.fusionItem2QuestionMark, nextItem)

			local classification = v.classification or nextItem:getClassification()
			local classificationPrices = self.classificationTable and self.classificationTable[tostring(classification)]
			local cost = classificationPrices and classificationPrices[tostring(v.tier)]
			if not cost then
				cost = 0
			end

			Forge:updateWidget("money", ws.fusionCost, cost)
			ws.fusionCost:setText(Forge:formatNumber(cost))

			self.leftItemId = capturedItem:getId()
			self.rightItemId = self.leftItemId
			self.fusionTier = v.tier

			self:refreshFusionProceedState()
		end

		container, _, capturedItem = createFusionListItem(self.contentPanel, id, v.tier, v.count, i, selectItem)

		if selectedItemId == id and selectedTier == v.tier then
			restoreSelection = selectItem
		end
	end

	if restoreSelection then
		restoreSelection()
	end
end

function Fusion:displayConvergence()
	self:updateWidgets()
	Forge:setWidget(ws.fusionCost, "???", false)
	self:refreshDustRequirementWidgets()
	self.contentPanel:destroyChildren()
	ws.fusionContent2:destroyChildren()

	if not self.data then
		return
	end

	local data = self.data.convergenceFusion

	if not data then
		return
	end

	for i, itemsTable in ipairs(data) do
		for z, v in ipairs(itemsTable) do
			local cost = self.convergenceFusionCost[tostring(v.tier)]
			local container

			container = createFusionListItem(self.contentPanel, v.id, v.tier, v.count, z, function()
				ws.fusionContent2:destroyChildren()
				resetFusionSelectionContext(self)
				ws.previewFusionQuestionMark:setVisible(false)
				ws.previewFusionQuestionMark2:setVisible(false)
				self:setActiveItem(container, container:getId())

				local resultItem = Item.create(v.id)

				resultItem:setTier(v.tier + 1)

				local sourceItem = Item.create(v.id)

				sourceItem:setTier(v.tier)
				ws.previewFusionItem:setItem(resultItem)
				ItemsDatabase.setBigTier(ws.previewFusionItem, resultItem)
				ws.previewFusionItem:setColor("black")
				updateButtonPreviewSlot(ws.fusionItem1, ws.fusionItem1QuestionMark, sourceItem)
				updateButtonPreviewSlot(ws.fusionItem2, ws.fusionItem2QuestionMark, resultItem)
				Forge:updateWidget("money", ws.fusionCost, cost)
				ws.fusionCost:setText(Forge:formatNumber(cost))
				self:refreshFusionProceedState()

				for n, m in ipairs(itemsTable) do
					local canFuse = false

					if m.id == v.id then
						canFuse = m.tier == v.tier and m.count >= 2
					else
						canFuse = m.tier == v.tier
					end

					if canFuse then
						local secondContainer

						secondContainer = createFusionListItem(ws.fusionContent2, m.id, m.tier, m.count, z, function()
							self.leftItemId = v.id
							self.rightItemId = m.id
							self.fusionTier = v.tier

							self:refreshFusionProceedState()
							self:setActiveItem(secondContainer, secondContainer:getId())
						end)
					end
				end
			end)
		end
	end
end

function Fusion:parseData(data)
	self.data = data

	if self.convergenceWidget:isChecked() then
		self:displayConvergence()
	else
		self:displayItems()
	end

	if not Forge.mainWindow:isVisible() then
		Forge.mainWindow:setVisible(true)
		Forge.mainWindow:raise()
		Forge.mainWindow:focus()
		self:showWindowCore()
	elseif not Forge.preview and (not Forge.currentPanel or Forge.currentPanel == self.mainWindow) then
		self:showWindowCore()
	end
end

function Fusion:parseResourcesChange(data)
	self.classificationTable = data.classificationTable

	local config = data.config

	if config then
		self.dustNormalFusion = config.dustNormalFusion and config.dustNormalFusion > 0 and config.dustNormalFusion or DUST_NORMAL_FUSION
		self.dustConvergenceFusion = config.dustConvergenceFusion and config.dustConvergenceFusion > 0 and config.dustConvergenceFusion or DUST_CONVERGENCE_FUSION
		self.baseChance = config.baseChance
		self.improvedChance = config.improvedChance
		self.tierLossReduction = config.tierLossReduction
	end

	self.convergenceFusionCost = data.convergenceFusion

	self:refreshChanceWidgets()
	self:refreshDustRequirementWidgets()
end

function Fusion:parseResult(data)
	if self.mainWindow and self.mainWindow:isVisible() then
		self.mainWindow:setVisible(false)
	end

	if data then
		self:applyFusionResult(data)
	end

	self.lastFusionContext = nil
end

local function adjustFusionListItem(list, id, tier, delta)
	if not list then
		return false
	end

	id = tonumber(id)
	tier = tonumber(tier) or 0
	delta = tonumber(delta) or 0

	if not id or delta == 0 then
		return false
	end

	for i, entry in ipairs(list) do
		if entry.id == id and entry.tier == tier then
			entry.count = entry.count + delta

			if entry.count <= 0 then
				table.remove(list, i)
			end

			return true
		end
	end

	if delta > 0 then
		table.insert(list, {
			id = id,
			tier = tier,
			count = delta
		})

		return true
	end

	return false
end

local function adjustConvergenceListItem(list, id, tier, delta)
	if not list then
		return nil
	end

	id = tonumber(id)
	tier = tonumber(tier) or 0
	delta = tonumber(delta) or 0

	if not id or delta == 0 then
		return nil
	end

	for groupIndex, group in ipairs(list) do
		for itemIndex, entry in ipairs(group) do
			if entry.id == id and entry.tier == tier then
				entry.count = entry.count + delta

				if entry.count <= 0 then
					table.remove(group, itemIndex)
				end

				if #group == 0 then
					table.remove(list, groupIndex)

					return nil
				end

				return groupIndex
			end
		end
	end

	if delta > 0 and list[1] then
		table.insert(list[1], {
			id = id,
			tier = tier,
			count = delta
		})

		return 1
	end

	return nil
end

function Fusion:applyFusionResult(data)
	local ctx = self.lastFusionContext

	if not ctx or not self.data then
		return
	end

	local success = data.success == 1 or data.success == true
	local leftItemId = ctx.leftItemId
	local rightItemId = ctx.rightItemId
	local fusionTier = ctx.fusionTier

	if ctx.convergence then
		local list = self.data.convergenceFusion

		if not list then
			return
		end

		local resultGroup = adjustConvergenceListItem(list, leftItemId, fusionTier, -1)

		if rightItemId ~= leftItemId then
			adjustConvergenceListItem(list, rightItemId, fusionTier, -1)
		else
			adjustConvergenceListItem(list, leftItemId, fusionTier, -1)
		end

		if success then
			local resultTier = data.rightTier or fusionTier + 1

			if resultGroup and list[resultGroup] then
				local found = false

				for _, entry in ipairs(list[resultGroup]) do
					if entry.id == leftItemId and entry.tier == resultTier then
						entry.count = entry.count + 1
						found = true

						break
					end
				end

				if not found then
					table.insert(list[resultGroup], {
						count = 1,
						id = leftItemId,
						tier = resultTier
					})
				end
			else
				adjustConvergenceListItem(list, leftItemId, resultTier, 1)
			end
		end

		return
	end

	local list = self.data.fusionItems

	if not list then
		return
	end

	local sameItem = leftItemId == rightItemId

	if sameItem then
		adjustFusionListItem(list, leftItemId, fusionTier, -2)
	else
		adjustFusionListItem(list, leftItemId, fusionTier, -1)
		adjustFusionListItem(list, rightItemId, fusionTier, -1)
	end

	if success then
		adjustFusionListItem(list, data.rightItemId or leftItemId, data.rightTier or fusionTier + 1, 1)

		return
	end

	if data.leftItemId ~= nil and data.leftTier ~= nil then
		adjustFusionListItem(list, data.leftItemId, data.leftTier, 1)
	end

	if data.rightItemId ~= nil and data.rightTier ~= nil and (data.rightItemId ~= data.leftItemId or data.rightTier ~= data.leftTier) then
		adjustFusionListItem(list, data.rightItemId, data.rightTier, 1)
	end
end
