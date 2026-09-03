-- chunkname: @/game_forge/menu/conversion/conversion.lua

ACTION_FUSION_TYPE = 0
ACTION_TRANSFER_TYPE = 1
ACTION_DUST_TO_SILVER = 2
ACTION_SILVER_TO_CORE = 3
ACTION_INCREASE_DUST_LIMIT = 4
Forge.Conversion = {}

local Conversion = Forge.Conversion

Conversion.mainWindow = nil

local DUST_REQUIRED = 60
local DUST_REWARD = 3
local SILVER_REQUIRED = 50
local SILVER_REWARD = 1
local LIMIT_BASE_COST = 25
local DESCRIPTIONS = {
	notEnoughSliverForCore = "You do not have enough slivers to generate an exalted core.",
	notEnoughDustForLimit = "You do not have enough dust to raise the limit.",
	notEnoughDustForSliver = "You do not have enough dust to generate a sliver.",
	convertSliver = "Convert slivers into exalted cores. Exalted cores are useful for fusions and transfers.",
	convertDust = "Convert your dust into slivers. Slivers are used to create exalted cores which are useful for fusions and transfers."
}

local function setItemWidgetAnimate(itemWidget, animate)
	if not itemWidget then
		return
	end

	local item = itemWidget:getItem()

	if item then
		item:setAnimate(animate)
	end
end

function Conversion:setDescription(text)
	if self.descriptionLabel then
		self.descriptionLabel:setText(text or "")
	end
end

function Conversion:resetDescription()
	self:setDescription("")
end

function Conversion.getPanelId(widget)
	local current = widget

	while current do
		local id = current:getId()

		if id == "convertDustPanel" or id == "convertSilverPanel" or id == "dustLimitPanel" then
			return id
		end

		if current == Conversion.mainWindow then
			break
		end

		current = current:getParent()
	end

	return nil
end

function Conversion.onHover(widget)
	if not Conversion.mainWindow or not Conversion.mainWindow:isVisible() then
		return
	end

	if not widget or not widget:isVisible() then
		return
	end

	local id = widget:getId()

	if id == "conversionWindow" or id == "firstTooltip" or id == "description" then
		Conversion:setDescription("")

		return
	end

	if id == "convertDustProcced" then
		Conversion:setDescription(Conversion:describeConvertDustCost())

		return
	end

	if id == "silverButtonProcced" then
		Conversion:setDescription(Conversion:describeConvertSliverCost())

		return
	end

	if id == "DustLimitProcced" then
		Conversion:setDescription(Conversion:describeIncreaseDustLimitCost())

		return
	end

	local panelId = Conversion.getPanelId(widget)

	if panelId == "convertDustPanel" then
		Conversion:setDescription(DESCRIPTIONS.convertDust)
	elseif panelId == "convertSilverPanel" then
		Conversion:setDescription(DESCRIPTIONS.convertSliver)
	elseif panelId == "dustLimitPanel" then
		Conversion:setDescription(Conversion:describeIncreaseDustLimit())
	end
end

local descriptionRefreshEvent

function Conversion.onWidgetHover(widget, hovered)
	if hovered then
		Conversion.onHover(widget)

		return
	end

	if descriptionRefreshEvent then
		removeEvent(descriptionRefreshEvent)
	end

	descriptionRefreshEvent = scheduleEvent(function()
		descriptionRefreshEvent = nil

		if not Conversion.mainWindow or not Conversion.mainWindow:isVisible() then
			return
		end

		local target = Conversion.mainWindow:recursiveGetChildByPos(g_window.getMousePosition(), false)

		if target then
			Conversion.onHover(target)
		else
			Conversion:resetDescription()
		end
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
			if hovered and Conversion.mainWindow and Conversion.mainWindow:isVisible() then
				Conversion:resetDescription()
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

function Conversion:describeConvertDustCost()
	if Forge:getResourceBalance("dust") < DUST_REQUIRED then
		return DESCRIPTIONS.notEnoughDustForSliver
	end

	return string.format("Click here to convert %d dust into %d slivers.", DUST_REQUIRED, DUST_REWARD)
end

function Conversion:describeConvertSliverCost()
	if Forge:getResourceBalance("sliver") < SILVER_REQUIRED then
		return DESCRIPTIONS.notEnoughSliverForCore
	end

	return string.format("Click here to convert %d slivers into one exalted core.", SILVER_REQUIRED)
end

function Conversion:describeIncreaseDustLimit()
	local dustMax = 100 + Forge:getDustLevel() * 20

	return string.format("Use dust to increase permanently the amount of the dust you can gather (currently %d).", dustMax)
end

function Conversion:describeIncreaseDustLimitCost()
	local currentLevel = Forge:getDustLevel()
	local cost = LIMIT_BASE_COST + currentLevel
	local currentLimit = 100 + currentLevel * 20
	local newLimit = 100 + (currentLevel + 1) * 20

	if cost > Forge:getResourceBalance("dust") then
		return DESCRIPTIONS.notEnoughDustForLimit
	end

	return string.format("Click here to spend %d dust to increase your limit from %d to %d.", cost, currentLimit, newLimit)
end

function Conversion:setupHovers()
	setupForgeAreaClearHover()
end

function Conversion:createButton()
	local buttonPanel = g_ui.createWidget("ForgeButton", Forge.mainWindow)

	buttonPanel:addAnchor(AnchorTop, "FusionButton", AnchorTop)
	buttonPanel:addAnchor(AnchorLeft, "TransferButton", AnchorRight)
	buttonPanel:setId("ConversionButton")

	self.buttonPanel = buttonPanel
	self.mainButton = buttonPanel:getChildById("button")

	self.mainButton:setText("Conversion")
	Forge.setupTabButtonIcon(buttonPanel, "/images/icons_big/icon-conversion", 6, 3)

	if not self.mainWindow then
		g_ui.importStyle("Conversion")

		self.mainWindow = g_ui.createWidget("ConversionWindow", Forge.mainWindow)

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

function Conversion:updateLimitCost(currentLevel, percent)
	currentLevel = math.max(0, currentLevel or 0)

	local value = LIMIT_BASE_COST + currentLevel
	local dustEnough = value <= Forge:getResourceBalance("dust")
	local newCostWidget = self.widgetStorage.limitCost
	local button = self.widgetStorage.DustLimitProcced

	self.widgetStorage.limitCost:setText(value)
	self.widgetStorage.newLimit:setText(string.format("to %d", 100 + (currentLevel + 1) * 20))
	self.widgetStorage.currentLimit:setText(100 + currentLevel * 20)

	if dustEnough then
		newCostWidget:setColor(Forge.colors.enough)
		button:setEnabled(true)
		self.widgetStorage.chainTransparent3:setVisible(false)
		setItemWidgetAnimate(self.widgetStorage.dustLimitItem1, true)
		setItemWidgetAnimate(self.widgetStorage.dustLimitItem2, true)
	else
		newCostWidget:setColor(Forge.colors.missing)
		button:setEnabled(false)
		self.widgetStorage.chainTransparent3:setVisible(true)
		setItemWidgetAnimate(self.widgetStorage.dustLimitItem1, false)
		setItemWidgetAnimate(self.widgetStorage.dustLimitItem2, false)
	end
end

function Conversion:updateConversion(dustRequired, dustReward, silverRequired, silverReward, currentLevel, percent)
	local dustRequiredWidget = self.widgetStorage.dustRequired
	local dustRewardWidget = self.widgetStorage.dustReward
	local dustButtonProcced = self.widgetStorage.dustButtonProcced

	dustRequiredWidget:setText(dustRequired)
	dustRewardWidget:setText(string.format("Generate %d", dustReward))

	local dustEnough = dustRequired > 0 and dustReward > 0 and dustRequired <= Forge:getResourceBalance("dust")

	if not dustEnough then
		dustRequiredWidget:setColor(Forge.colors.missing)
		dustButtonProcced:setEnabled(false)
		self.widgetStorage.chainTransparent1:setVisible(true)
		setItemWidgetAnimate(self.widgetStorage.dustRewardWidget, false)
	else
		dustRequiredWidget:setColor(Forge.colors.enough)
		dustButtonProcced:setEnabled(true)
		self.widgetStorage.chainTransparent1:setVisible(false)
		setItemWidgetAnimate(self.widgetStorage.dustRewardWidget, true)
	end

	local silverRequiredWidget = self.widgetStorage.silverRequired
	local sliverRewardWidget = self.widgetStorage.silverReward
	local silverButtonProcced = self.widgetStorage.silverButtonProcced

	silverRequiredWidget:setText(silverRequired)
	sliverRewardWidget:setText(string.format("Generate %d", silverReward))

	local silverEnough = silverRequired > 0 and silverReward > 0 and silverRequired <= Forge:getResourceBalance("sliver")

	if not silverEnough then
		silverRequiredWidget:setColor(Forge.colors.missing)
		silverButtonProcced:setEnabled(false)
		self.widgetStorage.chainTransparent2:setVisible(true)
		setItemWidgetAnimate(self.widgetStorage.silverRewardWidget, false)
	else
		silverRequiredWidget:setColor(Forge.colors.enough)
		silverButtonProcced:setEnabled(true)
		self.widgetStorage.chainTransparent2:setVisible(false)
		setItemWidgetAnimate(self.widgetStorage.silverRewardWidget, true)
	end

	self:updateLimitCost(currentLevel, percent)
end

function Conversion:init()
	self.widgetStorage = {}

	local mainWindow = self.mainWindow
	local tooltipPanel = mainWindow:getChildById("firstTooltip")

	self.descriptionLabel = tooltipPanel:getChildById("description")

	local convert_dustPanel = mainWindow:getChildById("convertDustPanel")
	local dust_forgeItemWidget = convert_dustPanel:getChildById("forgeItem")
	local dust_forgeItem = dust_forgeItemWidget:getChildById("item")

	dust_forgeItem:setItemId(37160)

	local dust_countPanel = dust_forgeItemWidget:getChildById("countPanel")
	local dust_countValue = dust_countPanel:getChildById("value")
	local dust_countIcon = dust_countPanel:getChildById("icon")

	dust_countIcon:setImageSource("/images/icons/icon-currency-dust")
	dust_countIcon:setSize(tosize("9 6"))

	local dust_rewardAmountWidget = convert_dustPanel:getChildById("forgeTextWithIcon")
	local dust_rewardAmountValue = dust_rewardAmountWidget:getChildById("value")

	self.widgetStorage.dustRequired = dust_countValue
	self.widgetStorage.dustReward = dust_rewardAmountValue

	local dust_buttonProcced = convert_dustPanel:getChildById("convertDustProcced")
	local dust_rewardWidget = dust_buttonProcced:getChildById("rewardItem")

	dust_rewardWidget:setItemId(37109)

	self.widgetStorage.chainTransparent1 = dust_buttonProcced:getChildById("chainTransparent1")
	self.widgetStorage.dustRewardWidget = dust_rewardWidget
	self.widgetStorage.dustButtonProcced = dust_buttonProcced

	local function triggerDustConversion()
		g_logger.info("[Forge] Dust conversion requested")
		forgeSendAction(ACTION_DUST_TO_SILVER, false, nil, nil, nil)
	end

	dust_buttonProcced.onClick = triggerDustConversion
	dust_buttonProcced:raise()

	local dustTextWithIcon = convert_dustPanel:getChildById("forgeTextWithIcon")
	if dustTextWithIcon then
		dustTextWithIcon.onClick = triggerDustConversion
		dustTextWithIcon:raise()
		local val = dustTextWithIcon:getChildById("value")
		if val then val.onClick = triggerDustConversion end
		local icon = dustTextWithIcon:getChildById("icon")
		if icon then icon.onClick = triggerDustConversion end
	end

	local convert_silverPanel = mainWindow:getChildById("convertSilverPanel")
	local silver_forgeItemWidget = convert_silverPanel:getChildById("forgeItem")
	local silver_forgeItem = silver_forgeItemWidget:getChildById("item")

	silver_forgeItem:setItemId(37109)

	self.widgetStorage.silver_forgeItem = silver_forgeItem

	local silver_buttonProcced = convert_silverPanel:getChildById("silverButtonProcced")
	local silver_rewardWidget = silver_buttonProcced:getChildById("rewardItem")

	self.widgetStorage.silverRewardWidget = silver_rewardWidget
	self.widgetStorage.chainTransparent2 = silver_buttonProcced:getChildById("chainTransparent2")

	local silver_rewardAmountWidget = convert_silverPanel:getChildById("forgeTextWithIcon")
	local silver_rewardAmountValue = silver_rewardAmountWidget:getChildById("value")
	local silver_rewardAmountIcon = silver_rewardAmountWidget:getChildById("icon")

	silver_rewardAmountIcon:setImageSource("/images/icons/icon-currency-exaltedcore")
	silver_rewardAmountIcon:setMarginLeft(6)

	local silver_countPanel = silver_forgeItemWidget:getChildById("countPanel")

	self.widgetStorage.silverRequired = silver_countPanel:getChildById("value")
	self.widgetStorage.silverReward = silver_rewardAmountValue
	self.widgetStorage.silverButtonProcced = silver_buttonProcced

	local function triggerSilverConversion()
		g_logger.info("[Forge] Silver conversion requested")
		forgeSendAction(ACTION_SILVER_TO_CORE, false, nil, nil, nil)
	end

	silver_buttonProcced.onClick = triggerSilverConversion
	silver_buttonProcced:raise()

	if silver_rewardAmountWidget then
		silver_rewardAmountWidget.onClick = triggerSilverConversion
		silver_rewardAmountWidget:raise()
		if silver_rewardAmountValue then silver_rewardAmountValue.onClick = triggerSilverConversion end
		if silver_rewardAmountIcon then silver_rewardAmountIcon.onClick = triggerSilverConversion end
	end

	local dustLimitPanel = mainWindow:getChildById("dustLimitPanel")
	local dustLimit_forgeItemWidget = dustLimitPanel:getChildById("forgeItem")
	local dustLimit_forgeItem = dustLimit_forgeItemWidget:getChildById("item")

	dustLimit_forgeItem:setItemId(37160)

	local dustLimit_countPanel = dustLimit_forgeItemWidget:getChildById("countPanel")
	local dustLimit_countIcon = dustLimit_countPanel:getChildById("icon")

	dustLimit_countIcon:setImageSource("/images/icons/icon-currency-dust")
	dustLimit_countIcon:setSize(tosize("9 6"))

	self.widgetStorage.limitCost = dustLimit_countPanel:getChildById("value")

	local dustLimit_raiseLimitPanel = dustLimitPanel:getChildById("ForgeTextWithIcon2")
	local dustLimit_raiseLimitFirstIcon = dustLimit_raiseLimitPanel:getChildById("icon")

	dustLimit_raiseLimitFirstIcon:setImageSource("/images/icons/icon-currency-dust")
	dustLimit_raiseLimitFirstIcon:setSize(tosize("9 6"))

	local dustLimit_raiseLimitSecondIcon = dustLimit_raiseLimitPanel:getChildById("icon2")

	dustLimit_raiseLimitSecondIcon:setImageSource("/images/icons/icon-currency-dust")
	dustLimit_raiseLimitSecondIcon:setSize(tosize("9 6"))

	self.widgetStorage.currentLimit = dustLimit_raiseLimitPanel:getChildById("value")
	self.widgetStorage.newLimit = dustLimit_raiseLimitPanel:getChildById("value2")

	local DustLimitProcced = dustLimitPanel:getChildById("DustLimitProcced")
	local dustLimitItem1 = DustLimitProcced:getChildById("DustLimitButtonItem1")
	local dustLimitItem2 = DustLimitProcced:getChildById("DustLimitButtonItem2")

	dustLimitItem1:setItemId(37160)
	dustLimitItem2:setItemId(37160)

	self.widgetStorage.dustLimitItem1 = dustLimitItem1
	self.widgetStorage.dustLimitItem2 = dustLimitItem2
	self.widgetStorage.chainTransparent3 = DustLimitProcced:getChildById("chainTransparent3")
	self.widgetStorage.DustLimitProcced = DustLimitProcced

	local function triggerLimitConversion()
		g_logger.info("[Forge] Dust limit increase requested")
		forgeSendAction(ACTION_INCREASE_DUST_LIMIT, false, nil, nil, nil)
	end

	DustLimitProcced.onClick = triggerLimitConversion
	DustLimitProcced:raise()

	if dustLimit_raiseLimitPanel then
		dustLimit_raiseLimitPanel.onClick = triggerLimitConversion
		dustLimit_raiseLimitPanel:raise()
		local val1 = dustLimit_raiseLimitPanel:getChildById("value")
		if val1 then val1.onClick = triggerLimitConversion end
		local val2 = dustLimit_raiseLimitPanel:getChildById("value2")
		if val2 then val2.onClick = triggerLimitConversion end
	end

	self:setupHovers()
	self:updateResources()
end

function Conversion:showWindow()
	if Forge.currentPanel then
		Forge.currentPanel:setVisible(false)
	end

	if Forge.currentButton then
		Forge.currentButton:setEnabled(true)
		Forge.onTabButtonEnabled(Forge.currentButton, nil, true)
	end

	Forge.currentPanel = self.mainWindow
	Forge.currentButton = self.mainButton

	self.mainWindow:setVisible(true)
	self.mainWindow:raise()
	self.mainButton:setEnabled(false)
	Forge.onTabButtonEnabled(nil, self.buttonPanel, false)
	Forge.firstTooltip:setVisible(false)
	self:resetDescription()

	if self.widgetStorage then
		if self.widgetStorage.dustRewardWidget then
			self.widgetStorage.dustRewardWidget:setItemId(37109)
		end

		if self.widgetStorage.silverRewardWidget then
			self.widgetStorage.silverRewardWidget:setItemId(37110)
		end

		if self.widgetStorage.silver_forgeItem then
			self.widgetStorage.silver_forgeItem:setItemId(37109)
		end
	end

	self:updateResources()

	if Forge.data and Forge.data.config then
		self:parseResourcesChange(Forge.data)
	end
end

function Conversion:updateResources()
	local currentLevel = Forge:getDustLevel()
	local percent = (Forge.data and Forge.data.config and Forge.data.config.dustPercentUpgrade) or 0
	self:updateConversion(DUST_REQUIRED, DUST_REWARD, SILVER_REQUIRED, SILVER_REWARD, currentLevel, percent)
end

function Conversion:parseResourcesChange(data)
	local config = data.config
	local dustPercentUpgrade = config.dustPercentUpgrade
	local currentLevel = Forge:getDustLevel()

	self:updateConversion(DUST_REQUIRED, DUST_REWARD, SILVER_REQUIRED, SILVER_REWARD, currentLevel, dustPercentUpgrade)
end
