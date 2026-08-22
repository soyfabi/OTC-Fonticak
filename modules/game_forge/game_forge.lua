-- chunkname: @/game_forge/game_forge.lua
local onFadeComplete -- forward declaration (used before its declaration in the decompiled file)

Forge = {}

-- CrystalOTC exposes this helper in gamelib; Fonticak's client does not.
if ItemsDatabase and not ItemsDatabase.setBigTier then
	function ItemsDatabase.setBigTier(widget, item)
		if not widget then
			return
		end

		local bigtier = widget.bigtier or widget:getChildById("bigtier")
		if not bigtier then
			return
		end

		local tier = type(item) == "number" and item or (item and item:getTier()) or 0
		if tier > 0 then
			bigtier:setImageClip({
				height = 16,
				width = 18,
				y = 0,
				x = (math.min(math.max(tier, 1), 10) - 1) * 18
			})
			bigtier:setVisible(true)
		else
			bigtier:setVisible(false)
		end
	end
end

function Forge.getForgeContainerHighlightTarget(container)
	local slot = container:getChildById("forgeItem")

	if not slot then
		return nil
	end

	return slot:getChildById("selectionOverlay") or slot
end

function Forge.raiseForgeContainerSelectionOverlay(forgeItemSlot)
	local overlay = forgeItemSlot:getChildById("selectionOverlay")

	if overlay then
		overlay:raise()
	end
end

function Forge.updateTabButtonIconState(buttonPanel, pressed)
	if not buttonPanel or not buttonPanel.forgeIconReleased then
		return
	end

	local button = buttonPanel:getChildById("button")

	if not button then
		return
	end

	local offset = pressed and buttonPanel.forgeIconPressed or buttonPanel.forgeIconReleased

	button:setIconOffset(topoint(offset.left .. " " .. offset.top))
end

function Forge.setupTabButtonIcon(buttonPanel, iconPath, releasedLeft, releasedTop, onlyVertical)
	local button = buttonPanel:getChildById("button")

	button:setIcon(iconPath)

	releasedTop = releasedTop - 3
	buttonPanel.forgeIconReleased = {
		left = releasedLeft,
		top = releasedTop
	}
	buttonPanel.forgeIconPressed = {
		left = onlyVertical and releasedLeft or releasedLeft + 1,
		top = releasedTop + 1
	}

	Forge.updateTabButtonIconState(buttonPanel, button:isDisabled())
end

function Forge.onTabButtonIconPress(buttonPanel)
	Forge.updateTabButtonIconState(buttonPanel, true)
end

function Forge.onTabButtonIconRelease(buttonPanel)
	local button = buttonPanel:getChildById("button")

	if button and not button:isDisabled() then
		Forge.updateTabButtonIconState(buttonPanel, false)
	end
end

function Forge.onTabButtonEnabled(previousButton, nextButtonPanel, enabled)
	if previousButton then
		Forge.updateTabButtonIconState(previousButton:getParent(), false)
	end

	if nextButtonPanel and enabled == false then
		Forge.updateTabButtonIconState(nextButtonPanel, true)
	end
end

Forge.resourceTypes = {
	sliver = 71,
	dust = 70,
	money = 0,
	core = 72
}
Forge.colors = {
	missing = "#D33C3C",
	enough = "#C0C0C0"
}
Forge.forceApplyNextOpenSnapshot = false
Forge.customBalances = {
	bank = 0,
	inventory = 0,
	dust = 0,
	slivers = 0,
	cores = 0
}
Forge.liveRefreshEvent = nil

local FORGE_RESULT_SILHOUETTE_SHADER = "forge_result_silhouette"

ACTION_FUSION_TYPE = 0
ACTION_TRANSFER_TYPE = 1
ACTION_DUST_TO_SILVER = 2
ACTION_SILVER_TO_CORE = 3
ACTION_INCREASE_DUST_LIMIT = 4

local Fusion, Transfer, Conversion, History

-- ADAPTERS: our C++ (protocolgameparse) emits different event names and a different table shape
-- than the ported client - we translate them here so we do not touch the engine

local function toKeyedPrices(list)
	local t = {}

	for _, e in ipairs(list or {}) do
		t[tostring(e.tier)] = e.price
	end

	return t
end

function onEngineForgeConfig(cfg)
	if type(cfg) ~= "table" then
		return
	end

	local data = {
		classificationTable = {},
		exaltedCores = {},
		convergenceFusion = toKeyedPrices(cfg.convergenceFusionPrices),
		convergenceTransfer = toKeyedPrices(cfg.convergenceTransferPrices),
		config = {
			maxDust = math.max(0, (cfg.maxDustLevel or 100) - 100),
			dustPercentUpgrade = cfg.dustPercentUpgrade,
			dustNormalFusion = cfg.normalDustFusion,
			dustConvergenceFusion = cfg.convergenceDustFusion,
			dustNormalTransfer = cfg.normalDustTransfer,
			dustConvergenceTransfer = cfg.convergenceDustTransfer,
			baseChance = cfg.fusionChanceBase,
			improvedChance = cfg.fusionChanceImproved,
			tierLossReduction = cfg.fusionReduceTierLoss
		}
	}

	for _, class in ipairs(cfg.classPrices or {}) do
		data.classificationTable[tostring(class.classId)] = toKeyedPrices(class.tiers)
	end

	for _, grade in ipairs(cfg.fusionGrades or {}) do
		data.exaltedCores[tostring(grade.tier)] = grade.exaltedCores
	end

	onPlayerResourcesChange(data)
end

function onEngineForgeResult(res)
	if type(res) ~= "table" then
		return
	end

	-- our C++ pushes success/convergence as boolean, the module compares against 1
	local bonus = res.bonus or 0
	local isExtra = bonus >= 4 and bonus <= 8

	onResultExaltationForge({
		actionType = res.actionType,
		convergence = res.convergence and 1 or 0,
		success = res.success and 1 or 0,
		leftItemId = res.leftItemId,
		leftTier = res.leftTier,
		rightItemId = res.rightItemId,
		rightTier = res.rightTier,
		bonus = res.bonus,
		coreCount = res.coreCount,
		extraItemId = isExtra and res.leftItemId or 0,
		extraTier = isExtra and res.leftTier or 0
	})
end

function onEngineForgeHistory(page, lastPage, count, list)
	local rows = {}

	for i, h in ipairs(list or {}) do
		rows[i] = {
			date = h.createdAt,
			action = h.actionType,
			details = h.description,
			bonus = h.bonus
		}
	end

	onForgeHistory(page, lastPage, rows)
end

function init()
	Forge.mainButton = modules.game_mainpanel.addToggleButton("forgeButton", tr("Open Exaltation Forge"), "/images/options/button_exaltation_forge", function()
		Forge:displayPreview()
	end, false, 17)

	Forge.mainButton:setOn(false)

	Forge.mainWindow = g_ui.displayUI("game_forge")

	Forge.mainWindow:setId("forge")
	Forge.mainWindow:setVisible(false)

	function Forge.mainWindow.onVisibilityChange(widget, visible)
		if not g_modalManager then
			return
		end

		if visible then
			g_modalManager.show(widget)
		else
			g_modalManager.hide(widget)
		end
	end

	Forge.firstTooltip = Forge.mainWindow:getChildById("firstTooltip")
	Forge.goldBalancePanel = Forge.mainWindow:getChildById("goldBalancePanel")
	Forge.goldBalanceValue = Forge.goldBalancePanel:getChildById("value")
	Forge.dustBalancePanel = Forge.mainWindow:getChildById("dustBalancePanel")
	Forge.dustBalanceValue = Forge.dustBalancePanel:getChildById("value")
	Forge.sliverBalancePanel = Forge.mainWindow:getChildById("sliverBalancePanel")
	Forge.sliverBalanceValue = Forge.sliverBalancePanel:getChildById("value")
	Forge.coreBalancePanel = Forge.mainWindow:getChildById("coreBalancePanel")
	Forge.coreBalanceValue = Forge.coreBalancePanel:getChildById("value")

	local closeWidget = Forge.mainWindow:getChildById("close")

	function closeWidget:onClick()
		Forge:close()
	end

	Fusion = Forge.Fusion:get()
	Transfer = Forge.Transfer
	Conversion = Forge.Conversion
	History = Forge.History:get()

	Forge.Fusion:createButton()
	Forge.Transfer:createButton()
	Forge.Conversion:createButton()
	Forge.History:createButton()
	-- our engine emits different event names than the ported client (see adapters below)
	connect(g_game, {
		onOpenForge = onOpenExaltationForge,
		forgeData = onEngineForgeConfig,
		forgeResultData = onEngineForgeResult,
		onBrowseForgeHistory = onEngineForgeHistory,
		onResourcesBalanceChange = onResourceBalance,
		onCloseForgeCloseWindows = function()
			Forge:close()
		end,
		onGameEnd = function()
			Forge:close()
		end
	})
	connect(LocalPlayer, {
		onInventoryChange = function()
			Forge:requestLiveRefresh()
		end
	})
	-- Some clients expose Container only after game_containers finishes loading.
	scheduleEvent(function()
		if Container then
			connect(Container, {
				onUpdateItem = function()
					Forge:requestLiveRefresh()
				end
			})
		end
	end, 300)
	g_shaders.createFragmentShader(FORGE_RESULT_SILHOUETTE_SHADER, "menu/shaders/silhouette.frag", false)
end

function onResourceBalance()
	Forge:updateResources()

	if Conversion and Forge.data and Forge.data.config then
		Conversion:parseResourcesChange(Forge.data)
	end
end

function Forge:requestLiveRefresh()
	if not g_game.useCustomForgeProtocol() or not self.mainWindow or not self.mainWindow:isVisible() then
		return
	end

	if self.liveRefreshEvent then
		return
	end

	self.liveRefreshEvent = scheduleEvent(function()
		self.liveRefreshEvent = nil
		if self.mainWindow and self.mainWindow:isVisible() and ForgeProtocol then
			ForgeProtocol.sendOpen()
		end
	end, 100)
end

function Forge:getDustLevel()
	return math.max(0, self.dustLevel or 0)
end

function Forge:updateResources()
	self.goldBalanceValue:setText(self:formatNumber(self:getResourceBalance("money")))

	local dustLevel = self:getDustLevel()
	local dustMax = 100 + dustLevel * 20

	self.dustBalanceValue:setText(self:formatNumber(self:getResourceBalance("dust")) .. "/" .. self:formatNumber(dustMax))
	self.sliverBalanceValue:setText(self:getResourceBalance("sliver"))
	self.coreBalanceValue:setText(self:getResourceBalance("core"))
end

function Forge:resetConvergenceModes()
	if Forge.Fusion and Forge.Fusion.resetConvergenceMode then
		Forge.Fusion:resetConvergenceMode()
	end

	if Forge.Transfer and Forge.Transfer.resetConvergenceMode then
		Forge.Transfer:resetConvergenceMode()
	end
end

function Forge:close()
	self:resetConvergenceModes()
	self.mainWindow:setVisible(false)
	self.lastDataSignature = nil
	if self.liveRefreshEvent then
		removeEvent(self.liveRefreshEvent)
		self.liveRefreshEvent = nil
	end

	if self.mainButton then
		self.mainButton:setOn(false)
	end

	if self.resultWindow then
		self.resultWindow:setVisible(false)
	end

	Forge.preview = false
end

function Forge:get()
	return self
end

function Forge:displayPreview()
	if not self.mainWindow:isVisible() then
		forgeOpenRequest()

		Forge.preview = true

		self.mainWindow:setVisible(true)
		self:startLiveRefresh()
		self.mainWindow:focus()
		Conversion:showWindow()
		Transfer:updateWidgets()
		self:updateResources()

		if Conversion and self.data and self.data.config then
			Conversion:parseResourcesChange(self.data)
		end

		if Transfer and self.data then
			Transfer:parseResourcesChange(self.data)
		end
	else
		Forge:close()
	end
end

function Forge:startLiveRefresh()
	if self.liveRefreshEvent or not g_game.useCustomForgeProtocol() then
		return
	end

	local function refreshLoop()
		self.liveRefreshEvent = nil
		if not self.mainWindow or not self.mainWindow:isVisible() then
			return
		end

		if ForgeProtocol then
			ForgeProtocol.sendOpen()
		end
		-- Fallback for money changes, which are not always exposed as an item event.
		self.liveRefreshEvent = scheduleEvent(refreshLoop, 300)
	end

	self.liveRefreshEvent = scheduleEvent(refreshLoop, 250)
end

function Forge:formatNumber(n)
	n = math.floor(tonumber(n) or 0)

	local str = string.format("%.0f", n)
	local result = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()

	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end

	return result
end

function Forge:updateWidget(resourceType, widget, value, _disabled)
	local balance = Forge:getResourceBalance(resourceType)

	value = tonumber(value)

	if value <= balance then
		widget:setColor(Forge.colors.enough)

		if _disabled then
			widget:setEnabled(false)
		end
	else
		widget:setColor(Forge.colors.missing)

		if _disabled then
			widget:setEnabled(true)
		end
	end
end

function Forge:setWidget(widget, value, boolean)
	widget:setText(value)

	if boolean then
		widget:setColor(Forge.colors.enough)
	else
		widget:setColor(Forge.colors.missing)
	end
end

function Forge:getResourceBalance(str)
	local t = self.resourceTypes[str]

	if not t then
		return 0
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	if str == "money" then
		if g_game.useCustomForgeProtocol() and self.customBalances then
			return self.customBalances.inventory or 0
		end
		return player:getTotalMoney()
	end

	if g_game.useCustomForgeProtocol() and self.customBalances then
		if str == "dust" then
			return self.customBalances.dust or 0
		elseif str == "sliver" then
			return self.customBalances.slivers or 0
		elseif str == "core" then
			return self.customBalances.cores or 0
		end
	end

	return player:getResourceBalance(t)
end

local function getResultBigTier(widget)
	if not widget then
		return nil
	end

	return widget:getChildById("bigtier") or widget.bigtier
end

local function setResultBigTier(widget, tier)
	if not widget then
		return
	end

	local bigtier = getResultBigTier(widget)

	if not bigtier then
		return
	end

	tier = tonumber(tier) or 0

	if tier > 0 then
		local xOffset = (math.min(math.max(tier, 1), 10) - 1) * 18

		bigtier:setImageClip({
			width = 18,
			y = 0,
			height = 16,
			x = xOffset
		})
		bigtier:setMarginRight(-1)
		bigtier:setVisible(true)
	else
		bigtier:setVisible(false)
	end
end

local function setResultItemShader(widget, item, shaderName)
	local shader = shaderName or ""

	if widget and widget.setShader then
		widget:setShader(shader)
	elseif item then
		item:setShader(shaderName)
	end

	local bigtier = getResultBigTier(widget)

	if bigtier and bigtier.setShader then
		if shaderName then
			bigtier:setShader(shaderName)
		else
			bigtier:setShader("")
		end
	end
end

local FORGE_RESULT_INITIAL_DELAY_MS = 1250
local FORGE_RESULT_PULSE_SLOW_MS = 200
local FORGE_RESULT_PULSE_FAST_MS = 100
local FORGE_RESULT_FINAL_FLASH_MS = 500
local FORGE_RESULT_FADE_MS = 800
local FORGE_RESULT_SHADER_CREATE_MS = 50
local FORGE_RESULT_STEPS = {
	{
		on = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		pause = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		fill = 1,
		on = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		pause = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		fill = 2,
		on = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		pause = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		fill = 3,
		on = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		pause = FORGE_RESULT_PULSE_SLOW_MS
	},
	{
		unfill = 1,
		on = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		pause = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		on = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		pause = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		unfill = 2,
		on = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		pause = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		on = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		pause = FORGE_RESULT_PULSE_FAST_MS
	},
	{
		final = true,
		unfill = 3,
		on = FORGE_RESULT_FINAL_FLASH_MS
	}
}

local function buildForgeResultTimeline(steps, initialDelayMs)
	local t = initialDelayMs
	local flashes = {}

	for _, step in ipairs(steps) do
		if step.pause then
			t = t + step.pause
		else
			table.insert(flashes, {
				at = t,
				onMs = step.on,
				fill = step.fill,
				unfill = step.unfill,
				final = step.final
			})

			t = t + step.on
		end
	end

	return flashes, t
end

local FORGE_RESULT_FLASHES, FORGE_RESULT_FADE_START_MS = buildForgeResultTimeline(FORGE_RESULT_STEPS, FORGE_RESULT_INITIAL_DELAY_MS)
local FORGE_RESULT_FINAL_FLASH = FORGE_RESULT_FLASHES[#FORGE_RESULT_FLASHES]
local FORGE_RESULT_BLINK_SHADER = "Item - ForgeBlink"
local FORGE_RESULT_BLINK_RED_SHADER = "Item - ForgeBlinkRed"
local FORGE_RESULT_FADE_OUT_SHADER = "Item - ForgeFadeOut"
local FORGE_RESULT_FADE_IN_SHADER = "Item - ForgeFadeIn"
local FORGE_RESULT_FADE_OUT_RED_SHADER = "Item - ForgeFadeOutRed"

local function recreateForgeResultShader(shaderName, shaderPath)
	if g_shaders.removeShader then
		g_shaders.removeShader(shaderName)
	end
	g_shaders.createFragmentShader(shaderName, shaderPath, false)
end

local function applyShaderWhenReady(shaderName, applyFn, attempt)
	if g_shaders.getShader(shaderName) then
		applyFn()

		return
	end

	if (attempt or 0) < 20 then
		scheduleEvent(function()
			applyShaderWhenReady(shaderName, applyFn, (attempt or 0) + 1)
		end, 16)
	end
end

local function applyResultSilhouette(widget, onApplied)
	if not widget then
		if onApplied then
			onApplied()
		end

		return
	end

	if not g_shaders.getShader(FORGE_RESULT_SILHOUETTE_SHADER) then
		g_shaders.createFragmentShader(FORGE_RESULT_SILHOUETTE_SHADER, "menu/shaders/silhouette.frag", false)
	end

	applyShaderWhenReady(FORGE_RESULT_SILHOUETTE_SHADER, function()
		widget:setColor("white")
		setResultItemShader(widget, widget:getItem(), FORGE_RESULT_SILHOUETTE_SHADER)

		if widget.updateLayout then
			widget:updateLayout()
		end

		if widget.repaint then
			widget:repaint()
		end

		if onApplied then
			onApplied()
		end
	end, 0)
end

local function buildForgeResultText(prefix, success)
	local gray = "#C0C0C0"
	local word = success and "successful" or "failed"
	local wordColor = success and "#44AD25" or "#D33C3C"

	return string.format("{%s, %s}{%s, %s}{., %s}", prefix, gray, word, wordColor, gray)
end

local function setResultCloseLocked(closeWidget, locked)
	if not closeWidget then
		return
	end

	closeWidget:setEnabled(not locked)

	if locked then
		local currentText = closeWidget:getText()

		if currentText and currentText ~= "" then
			closeWidget.resultActionText = currentText
		elseif not closeWidget.resultActionText then
			closeWidget.resultActionText = "Close"
		end

		closeWidget:setText("")
	else
		closeWidget:setText(closeWidget.resultActionText or "Close")
	end

	local dither = closeWidget:getChildById("closeDither")

	if dither then
		dither:setVisible(locked)

		if locked then
			dither:raise()
		end
	end
end

local function playFusionSuccessParticles(resultWindow, descWidget, offsetX, offsetY)
	if not resultWindow or not descWidget then
		return
	end

	local textPos = descWidget:getPosition()
	local center = {
		x = textPos.x + math.floor(descWidget:getWidth() / 2) + (offsetX or 0),
		y = textPos.y + math.floor(descWidget:getHeight() / 2) + (offsetY or 0)
	}

	for i = 1, 26 do
		local particle = g_ui.createWidget("UIWidget", resultWindow)
		local angle = (math.pi * 2 * i / 26) + math.random() * 0.35
		local distance = 48 + math.random(0, 38)
		local start = { x = center.x - 4, y = center.y - 4 }
		local target = {
			x = math.floor(start.x + math.cos(angle) * distance),
			y = math.floor(start.y + math.sin(angle) * distance)
		}

		particle:setSize({ width = 8, height = 8 })
		particle:setImageSource("/particles/particle.png")
		particle:setColor("#FFD83D")
		particle:setOpacity(1)
		particle:setPosition(start)
		particle:raise()

		local startedAt = g_clock.millis()
		local function animateParticle()
			if not particle or particle:isDestroyed() then
				return
			end

			local progress = math.min((g_clock.millis() - startedAt) / 800, 1)
			local eased = 1 - math.pow(1 - progress, 3)
			particle:setPosition({
				x = math.floor(start.x + (target.x - start.x) * eased),
				y = math.floor(start.y + (target.y - start.y) * eased)
			})
			particle:setOpacity(1 - progress)

			if progress < 1 then
				scheduleEvent(animateParticle, 16)
			else
				particle:destroy()
			end
		end

		animateParticle()
	end
end

local function revealResultOutcomeUi(descWidget, description, closeWidget, success, resultWindow)
	if descWidget then
		descWidget:setColoredText(description)
		descWidget:setVisible(true)
	end

	if success then
		local function burst()
			if not resultWindow or resultWindow:isDestroyed() then
				return
			end

			playFusionSuccessParticles(
				resultWindow,
				descWidget,
				math.random(-48, 48),
				math.random(-12, 12)
			)
		end

		burst()
		scheduleEvent(burst, 200)
		scheduleEvent(burst, 400)
	end

	setResultCloseLocked(closeWidget, false)
end

local function scheduleForgeResultDryPhase(leftWidget, leftItem, blinkShader, arrows)
	local emptyIcon = "/images/game/forge/icon-arrow-rightlarge"
	local filledIcon = "/images/game/forge/icon-arrow-rightlarge-filled"

	if arrows then
		for _, arrow in ipairs(arrows) do
			if arrow then
				arrow:setImageSource(emptyIcon)
			end
		end
	end

	for _, flash in ipairs(FORGE_RESULT_FLASHES) do
		if not flash.final then
			scheduleEvent(function()
				setResultItemShader(leftWidget, leftItem, blinkShader)
				scheduleEvent(function()
					setResultItemShader(leftWidget, leftItem, nil)
				end, flash.onMs)
			end, flash.at)
		end

		if arrows and flash.fill then
			scheduleEvent(function()
				local arrow = arrows[flash.fill]

				if arrow then
					arrow:setImageSource(filledIcon)
				end
			end, flash.at)
		end

		if arrows and flash.unfill then
			scheduleEvent(function()
				local arrow = arrows[flash.unfill]

				if arrow then
					arrow:setImageSource(emptyIcon)
				end
			end, flash.at)
		end
	end
end

local function prepareResultRightItem(widget2, item2, revealTier)
	if not widget2 or not item2 then
		return
	end

	setResultItemShader(widget2, item2, nil)
	widget2:setColor("white")
	widget2:setItem(item2)

	if revealTier and revealTier > 0 then
		item2:setTier(revealTier)
		widget2:setTier(revealTier)
		setResultBigTier(widget2, revealTier)
	elseif item2:getTier() > 0 then
		setResultBigTier(widget2, item2:getTier())
	end
end

local function playResultFade(leftWidget, leftItem, rightWidget, rightItem, leftFadeShader, leftFadePath, rightFadeShader, rightFadePath, onComplete, onFadeComplete)
	recreateForgeResultShader(leftFadeShader, leftFadePath)
	recreateForgeResultShader(rightFadeShader, rightFadePath)

	local function applyFadeShaders(attempt)
		if not g_shaders.getShader(leftFadeShader) or not g_shaders.getShader(rightFadeShader) then
			if (attempt or 0) < 20 then
				scheduleEvent(function()
					applyFadeShaders((attempt or 0) + 1)
				end, 16)
			else
				if onFadeComplete then
					onFadeComplete()
				end

				if onComplete then
					onComplete()
				end
			end

			return
		end

		setResultItemShader(leftWidget, leftItem, leftFadeShader)
		setResultItemShader(rightWidget, rightItem, rightFadeShader)
		scheduleEvent(function()
			if onFadeComplete then
				onFadeComplete()
			end

			if onComplete then
				onComplete()
			end

			setResultItemShader(leftWidget, leftItem, nil)
			setResultItemShader(rightWidget, rightItem, nil)
			leftWidget:setColor("white")
		end, FORGE_RESULT_FADE_MS)
	end

	scheduleEvent(function()
		applyFadeShaders(0)
	end, FORGE_RESULT_SHADER_CREATE_MS)
end

local function setupResultPreviewItem(widget, item, showTier)
	if not widget or not item then
		return
	end

	if widget.setFixedItemSize then
		widget:setFixedItemSize(false)
	end
	widget:setItem(item)

	if showTier == false then
		setResultBigTier(widget, 0)
	else
		setResultBigTier(widget, item:getTier())
	end
end

local function resolveTransferRevealTier(success, convergence, leftTier, rightTier)
	if not success or not leftTier or leftTier <= 0 then
		return nil
	end

	if rightTier and rightTier > 0 then
		return rightTier
	end

	if convergence == 1 then
		return leftTier
	end

	return math.max(0, leftTier - 1)
end

local FORGE_DUST_ITEM_ID = 37160
local FORGE_CORE_ITEM_ID = 37110
local FORGE_GOLD_ITEM_ID = 3031
local FORGE_ICON_DUST = string.char(164)
local FORGE_ICON_EXALTED = string.char(166)
local FORGE_ICON_GOLD = string.char(167)
local FORGE_BONUS_TEXT_COLOR = "#C0C0C0"
local FORGE_BONUS_ICON_COLOR = "#FFFFFF"

local function resolveFusionGoldCost(itemId, tier)
	if not Fusion or not Fusion.classificationTable then
		return 0
	end

	local probe = Item.create(itemId)

	if not probe then
		return 0
	end

	local byClass = Fusion.classificationTable[tostring(probe:getClassification())]

	if not byClass then
		return 0
	end

	return tonumber(byClass[tostring(tier or 0)]) or 0
end

local function forgeBonusColoredText(text)
	local iconSet = {
		[FORGE_ICON_DUST] = true,
		[FORGE_ICON_EXALTED] = true,
		[FORGE_ICON_GOLD] = true
	}
	local parts = {}
	local buffer = {}

	local function flushBuffer()
		if #buffer == 0 then
			return
		end

		parts[#parts + 1] = string.format("{%s, %s}", table.concat(buffer), FORGE_BONUS_TEXT_COLOR)
		buffer = {}
	end

	for i = 1, #text do
		local ch = text:sub(i, i)

		if iconSet[ch] then
			flushBuffer()

			parts[#parts + 1] = string.format("{%s, %s}", ch, FORGE_BONUS_ICON_COLOR)
		else
			buffer[#buffer + 1] = ch
		end
	end

	flushBuffer()

	return table.concat(parts)
end

local function buildForgeBonusPresentation(bonus, leftItemId, leftTier, coreCount, extraItemId, extraTier)
	bonus = tonumber(bonus) or 0

	if bonus <= 0 then
		return nil
	end

	leftItemId = tonumber(leftItemId) or 0
	leftTier = tonumber(leftTier) or 0
	coreCount = tonumber(coreCount) or 0
	extraItemId = tonumber(extraItemId) or 0
	extraTier = tonumber(extraTier) or 0

	local bonusItemId = extraItemId > 0 and extraItemId or leftItemId

	if bonus == 1 then
		local text = string.format("Neat! The used 100%s were not consumed.", FORGE_ICON_DUST)

		return {
			count = 1,
			tier = 0,
			itemId = FORGE_DUST_ITEM_ID,
			text = text,
			coloredText = forgeBonusColoredText(text)
		}
	elseif bonus == 2 then
		local text = string.format("Great! The used%s was not consumed.", FORGE_ICON_EXALTED)

		return {
			tier = 0,
			itemId = FORGE_CORE_ITEM_ID,
			count = math.max(coreCount, 1),
			text = text,
			coloredText = forgeBonusColoredText(text)
		}
	elseif bonus == 3 then
		local goldCost = resolveFusionGoldCost(leftItemId, leftTier)
		local text = string.format("Awesome! The used %s%s were not consumed.", Forge:formatNumber(goldCost), FORGE_ICON_GOLD)

		return {
			count = 100,
			tier = 0,
			itemId = FORGE_GOLD_ITEM_ID,
			text = text,
			coloredText = forgeBonusColoredText(text)
		}
	elseif bonus >= 4 and bonus <= 8 then
		local texts = {
			nil,
			nil,
			nil,
			"What luck! Your item only lost one tier instead of being\nconsumed.",
			"Lucky you! You kept the second item and its tier.",
			"Terrific! Both of your items gained an additional tier.",
			"Unbelievable! You must be blessed by the Tibian gods!\nYour fused item gained two instead of one tier!",
			"Stroke of luck! The second item was not consumed."
		}

		return {
			count = 1,
			itemId = bonusItemId,
			tier = extraTier,
			text = texts[bonus]
		}
	end

	return nil
end

local function hideResultFusionWidgets(resultWindow)
	if not resultWindow then
		return
	end

	for _, id in ipairs({
		"previewItem1",
		"previewItem2",
		"arrowsIcon1",
		"arrowsIcon2",
		"arrowsIcon3"
	}) do
		local widget = resultWindow:recursiveGetChildById(id)

		if widget then
			widget:setVisible(false)
		end
	end

	local dragonHeader = resultWindow:recursiveGetChildById("dragonHeader")

	if dragonHeader then
		dragonHeader:setVisible(true)
		dragonHeader:raise()
	end
end

function Forge:showResultBonus(bonusInfo)
	local resultWindow = self.resultWindow

	if not resultWindow or not bonusInfo then
		return
	end

	hideResultFusionWidgets(resultWindow)

	local bonusWidget = resultWindow:recursiveGetChildById("bonusItem")
	local descWidget = resultWindow:recursiveGetChildById("resultText")
	local closeWidget = resultWindow:getChildById("close")

	if bonusWidget and bonusInfo.itemId and bonusInfo.itemId > 0 then
		local item = Item.create(bonusInfo.itemId)

		if item then
			local count = math.max(tonumber(bonusInfo.count) or 1, 1)

			if item.setCount then
				item:setCount(count)
			end

			if (bonusInfo.tier or 0) > 0 then
				item:setTier(bonusInfo.tier)
			end

			bonusWidget:setVisible(true)
			if bonusWidget.setFixedItemSize then
				bonusWidget:setFixedItemSize(false)
			end

			if bonusWidget.setShowCount then
				bonusWidget:setShowCount(false)
			end

			setupResultPreviewItem(bonusWidget, item, (bonusInfo.tier or 0) > 0)
		end
	end

	if descWidget then
		local text = bonusInfo.text or ""
		local line1, line2 = text:match("^(.-)\n(.*)$")

		if not line1 then
			line1 = text
			line2 = nil
		end

		local descWidget2 = resultWindow:recursiveGetChildById("resultText2")

		descWidget:breakAnchors()
		descWidget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
		descWidget:addAnchor(AnchorTop, "bonusItem", AnchorBottom)
		descWidget:setMarginTop(10)
		descWidget:setMarginLeft(0)
		descWidget:setMarginRight(0)

		if descWidget.setTextWrap then
			descWidget:setTextWrap(false)
		end

		descWidget:setColor(FORGE_BONUS_TEXT_COLOR)

		if bonusInfo.coloredText and not line2 then
			descWidget:setColoredText(bonusInfo.coloredText)
		else
			descWidget:setText(line1)
		end

		descWidget:setVisible(true)

		if descWidget2 then
			if line2 and line2 ~= "" then
				descWidget2:setColor(FORGE_BONUS_TEXT_COLOR)
				descWidget2:setText(line2)
				descWidget2:setVisible(true)
			else
				descWidget2:setText("")
				descWidget2:setVisible(false)
			end
		end
	end

	if closeWidget then
		closeWidget.resultActionText = "Close"
		closeWidget.pendingBonus = nil

		setResultCloseLocked(closeWidget, false)
	end
end

function Forge:ProcessFlash(item, widget, startDelay, item2, widget2, descWidget, description, success, revealTier, closeWidget)
	local animationId = Forge.resultAnimationId

	local function isAnimationActive()
		return animationId == Forge.resultAnimationId and Forge.resultWindow ~= nil
	end

	local animationStartDelay = startDelay or 10
	local finalFlashAt = FORGE_RESULT_FINAL_FLASH.at
	local finalFlashOnMs = FORGE_RESULT_FINAL_FLASH.onMs
	local totalDuration = FORGE_RESULT_FADE_START_MS + FORGE_RESULT_SHADER_CREATE_MS + FORGE_RESULT_FADE_MS + 200

	recreateForgeResultShader(FORGE_RESULT_BLINK_SHADER, "menu/shaders/blink_white.frag")

	local arrows

	if Forge.resultWindow then
		arrows = {
			Forge.resultWindow:recursiveGetChildById("arrowsIcon1"),
			Forge.resultWindow:recursiveGetChildById("arrowsIcon2"),
			Forge.resultWindow:recursiveGetChildById("arrowsIcon3")
		}
	end

	scheduleEvent(function()
		if not isAnimationActive() then
			return
		end

		scheduleForgeResultDryPhase(widget, item, FORGE_RESULT_BLINK_SHADER, arrows)
		scheduleEvent(function()
			if not isAnimationActive() then
				return
			end

			if success then
				prepareResultRightItem(widget2, item2, revealTier)
				widget:setColor("white")
				setResultItemShader(widget, item, FORGE_RESULT_BLINK_SHADER)
				setResultItemShader(widget2, item2, FORGE_RESULT_BLINK_SHADER)
			else
				recreateForgeResultShader(FORGE_RESULT_BLINK_RED_SHADER, "menu/shaders/blink_red.frag")
				widget:setColor("white")
				setResultItemShader(widget, item, FORGE_RESULT_BLINK_SHADER)
				applyShaderWhenReady(FORGE_RESULT_BLINK_RED_SHADER, function()
					setResultItemShader(widget2, item2, FORGE_RESULT_BLINK_RED_SHADER)
				end, 0)
			end

			scheduleEvent(function()
				if not isAnimationActive() then
					return
				end

				onFadeComplete = function()
					revealResultOutcomeUi(descWidget, description, closeWidget, success, Forge.resultWindow)
				end

				if success then
					playResultFade(widget, item, widget2, item2, FORGE_RESULT_FADE_OUT_SHADER, "menu/shaders/fade_out_white.frag", FORGE_RESULT_FADE_IN_SHADER, "menu/shaders/fade_in_white.frag", function()
						widget:setVisible(false)
					end, onFadeComplete)
				else
					playResultFade(widget, item, widget2, item2, FORGE_RESULT_FADE_IN_SHADER, "menu/shaders/fade_in_white.frag", FORGE_RESULT_FADE_OUT_SHADER, "menu/shaders/fade_out_white.frag", function()
						widget2:setVisible(false)
					end, onFadeComplete)
				end
			end, finalFlashOnMs)
		end, finalFlashAt)
	end, animationStartDelay)
	scheduleEvent(function()
		if g_shaders.removeShader then
			g_shaders.removeShader(FORGE_RESULT_BLINK_SHADER)
			g_shaders.removeShader(FORGE_RESULT_BLINK_RED_SHADER)
			g_shaders.removeShader(FORGE_RESULT_FADE_OUT_SHADER)
			g_shaders.removeShader(FORGE_RESULT_FADE_IN_SHADER)
			g_shaders.removeShader(FORGE_RESULT_FADE_OUT_RED_SHADER)
		end
	end, animationStartDelay + totalDuration)
end

function Forge:displayResult(actionType, convergence, success, leftItemId, rightItemId, leftTier, rightTier, bonus, coreCount, extraItemId, extraTier)
	if self.resultWindow then
		self.resultWindow:destroy()

		self.resultWindow = nil
	end

	Forge.resultAnimationId = (Forge.resultAnimationId or 0) + 1
	self.resultWindow = g_ui.displayUI("result")

	self.resultWindow:setVisible(false)

	local resultWindow = self.resultWindow
	local descWidget = resultWindow:recursiveGetChildById("resultText")

	if descWidget then
		descWidget:setVisible(false)
	end

	local descWidget2 = resultWindow:recursiveGetChildById("resultText2")

	if descWidget2 then
		descWidget2:setVisible(false)
	end

	local bonusInfo

	if actionType == ACTION_FUSION_TYPE then
		bonusInfo = buildForgeBonusPresentation(bonus, leftItemId, leftTier, coreCount, extraItemId, extraTier)
	end

	local closeWidget = resultWindow:getChildById("close")

	if closeWidget then
		closeWidget.pendingBonus = bonusInfo
		closeWidget.resultActionText = bonusInfo and "Next" or "Close"
	end

	setResultCloseLocked(closeWidget, true)

	function closeWidget.onClick(widget)
		if widget.pendingBonus then
			local pending = widget.pendingBonus

			widget.pendingBonus = nil

			Forge:showResultBonus(pending)

			return
		end

		if self.resultWindow then
			self.resultWindow:destroy()

			self.resultWindow = nil
		end

		self:close()
		self:displayPreview()
	end

	local function beginResultAnimation(leftItem, leftWidget, rightItem, rightWidget, revealTier, resultText)
		scheduleEvent(function()
			self:ProcessFlash(leftItem, leftWidget, false, rightItem, rightWidget, descWidget, resultText, success, revealTier, closeWidget)
		end, 200)
		self.resultWindow:setVisible(true)
	end

	if actionType == ACTION_FUSION_TYPE then
		if convergence == 1 then
			resultWindow:setText("Convergence Fusion Result")
		else
			resultWindow:setText("Fusion Result")
		end

		local text = buildForgeResultText("Your fusion attempt was ", success)
		local rightItem = Item.create(rightItemId)
		local rightWidget = resultWindow:recursiveGetChildById("previewItem2")
		local leftWidget = resultWindow:recursiveGetChildById("previewItem1")
		local leftItem = Item.create(leftItemId)

		rightItem:setTier(rightTier)
		leftItem:setTier(leftTier)
		setupResultPreviewItem(rightWidget, rightItem)
		setupResultPreviewItem(leftWidget, leftItem)
		applyResultSilhouette(rightWidget, function()
			beginResultAnimation(leftItem, leftWidget, rightItem, rightWidget, nil, text)
		end)
	elseif actionType == ACTION_TRANSFER_TYPE then
		if convergence == 1 then
			resultWindow:setText("Convergence Tier Transfer Result")
		else
			resultWindow:setText("Tier Transfer Result")
		end

		local text = buildForgeResultText("Your transfer was ", success)
		local rightItem = Item.create(rightItemId)
		local rightWidget = resultWindow:recursiveGetChildById("previewItem2")

		rightItem:setTier(0)
		setupResultPreviewItem(rightWidget, rightItem, false)

		local leftWidget = resultWindow:recursiveGetChildById("previewItem1")
		local leftItem = Item.create(leftItemId)

		leftItem:setTier(leftTier)
		setupResultPreviewItem(leftWidget, leftItem, true)
		beginResultAnimation(leftItem, leftWidget, rightItem, rightWidget, resolveTransferRevealTier(success, convergence, leftTier, rightTier), text)
	end
end

local function getForgeDataSignature(value, buffer)
	buffer = buffer or {}
	local valueType = type(value)

	if valueType == "table" then
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)

		table.insert(buffer, "{")
		for _, key in ipairs(keys) do
			table.insert(buffer, tostring(key))
			table.insert(buffer, "=")
			getForgeDataSignature(value[key], buffer)
			table.insert(buffer, ";")
		end
		table.insert(buffer, "}")
	elseif valueType == "nil" then
		table.insert(buffer, "nil")
	else
		table.insert(buffer, tostring(value))
	end

	return table.concat(buffer)
end

function onOpenExaltationForge(data)
	Forge.preview = false
	-- the server (0x87) sends the dust level counted from 100
	Forge.dustLevel = math.max(0, (data.dustLevel or 0) - 100)

	Forge:updateResources()

	if Conversion and Forge.data and Forge.data.config then
		Conversion:parseResourcesChange(Forge.data)
	end

	local fusionCount = data.fusionItems and #data.fusionItems or 0
	local transferCount = data.transfers and #data.transfers or 0
	local convergenceCount = data.convergenceTransfers and #data.convergenceTransfers or 0
	local incomingHasItems = fusionCount > 0 or transferCount > 0 or convergenceCount > 0
	local dataSignature = getForgeDataSignature(data)
	local hadFusionItems = Fusion and Fusion.data and Fusion.data.fusionItems and #Fusion.data.fusionItems > 0
	local hadTransfers = Transfer and (Transfer.transfers and #Transfer.transfers > 0 or Transfer.convergenceTransfers and #Transfer.convergenceTransfers > 0)

	if not incomingHasItems and (hadFusionItems or hadTransfers) and not Forge.forceApplyNextOpenSnapshot then
		return
	end

	-- Balances above are still refreshed every time, but avoid rebuilding all
	-- Forge widgets when the inventory snapshot is unchanged.
	if Forge.lastDataSignature == dataSignature and not Forge.forceApplyNextOpenSnapshot then
		return
	end
	Forge.lastDataSignature = dataSignature

	Fusion:parseData(data)
	Transfer:parseData(data)

	Forge.forceApplyNextOpenSnapshot = false
end

function onPlayerResourcesChange(data)
	Forge.data = data

	if data.config and data.config.maxDust ~= nil then
		Forge.dustLevel = data.config.maxDust
	end

	Forge:updateResources()
	Fusion:parseResourcesChange(data)
	Conversion:parseResourcesChange(data)
	Transfer:parseResourcesChange(data)
end

function onResultExaltationForge(data)
	local success

	if data.success == 1 then
		success = true
	end

	scheduleEvent(function()
		Forge.mainWindow:setVisible(false)
	end, 10)
	Forge:displayResult(data.actionType, data.convergence, success, data.leftItemId, data.rightItemId, data.leftTier, data.rightTier, data.bonus, data.coreCount, data.extraItemId, data.extraTier)

	if data.actionType == ACTION_FUSION_TYPE then
		Fusion:parseResult(data)

		return
	end

	if data.actionType == ACTION_TRANSFER_TYPE then
		Transfer:parseResult(data)
	end
end

function onForgeHistory(currentPage, lastPage, data)
	History:parse(currentPage, lastPage, data)
end

function terminate()
	if Forge.liveRefreshEvent then
		removeEvent(Forge.liveRefreshEvent)
		Forge.liveRefreshEvent = nil
	end
end
