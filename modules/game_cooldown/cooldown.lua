-- chunkname: @/game_cooldown/cooldown.lua

local ProgressCallback = {
	finish = 2,
	update = 1
}

cooldownWindow = nil
contentsPanel = nil
cooldownPanel = nil
lastPlayer = nil
cooldown = {}
groupCooldown = {}

local SPELL_ICON_FILE = "/images/game/spells/spell-icons-20x20"

local EXTENDED_SPELL_GROUP_SUFFIXES = {
	Crippling = true,
	Focus = true,
	UltimateStrikes = true,
	GreatBeams = true,
	BurstsOfNature = true,
	Virtue = true
}

local function shouldShowExtendedSpellGroups()
	return g_game.getClientVersion() > 1100 or g_game.getFeature(GameSpellList)
end

local function isGroupIconVisible(iconId, monkFeature)
	if not iconId or iconId:sub(1, 9) ~= "groupIcon" then
		return true
	end
	local suffix = iconId:sub(10)
	if not EXTENDED_SPELL_GROUP_SUFFIXES[suffix] then
		return true
	end
	if suffix == "Virtue" then
		return shouldShowExtendedSpellGroups() and monkFeature
	end
	return shouldShowExtendedSpellGroups()
end

local function stopGroupProgressForIcon(icon, suffix)
	if not contentsPanel or not suffix then
		return
	end

	local progress = contentsPanel:getChildById("progressRect" .. suffix)
	if not progress or progress:isDestroyed() then
		return
	end

	cancelCooldownEvent(progress)
	progress:setPercent(100)
	resetCooldownFillBar(progress)
	progress.icon = nil

	if icon and not icon:isDestroyed() then
		setGroupIconOverlay(icon, true)
	end
end

local function getCooldownFillBarWidth(progressRect)
	if not progressRect or progressRect:isDestroyed() then
		return 0
	end

	local icon = progressRect.icon
	if icon and not icon:isDestroyed() and icon:isVisible() then
		return math.max(icon:getWidth() - 2, 0)
	end

	return math.max(progressRect:getWidth() - 2, 0)
end

local function applySpellGroupIconVisibility()
	if not contentsPanel or contentsPanel:isDestroyed() then
		return
	end
	local monkFeature = g_game.getFeature(GameVocationMonk)
	for _, widget in ipairs(contentsPanel:getChildren()) do
		local id = widget:getId()
		if id and id:sub(1, 9) == "groupIcon" then
			local visible = isGroupIconVisible(id, monkFeature)
			widget:setVisible(visible)
			local progress = contentsPanel:getChildById("progressRect" .. id:sub(10))
			if progress then
				progress:setVisible(visible)
			end
			if not visible then
				stopGroupProgressForIcon(widget, id:sub(10))
			end
		elseif id == "groupIconSeparator" then
			widget:setVisible(shouldShowExtendedSpellGroups())
		end
	end

	local focusIcon = contentsPanel:getChildById("groupIconFocus")
	if not focusIcon or not focusIcon:isVisible() then
		clearFocusMasteryVisual()
	end
end

local function cancelCooldownEvent(progressRect)
	if not progressRect then
		return
	end

	if progressRect.event then
		removeEvent(progressRect.event)

		progressRect.event = nil
	end

	progressRect.callback = nil
	progressRect.cooldownEndTime = nil
	progressRect.cooldownDuration = nil
	progressRect.cooldownStartTime = nil
end

local function releaseProgressRect(progressRect)
	if not progressRect or progressRect:isDestroyed() then
		return
	end

	cancelCooldownEvent(progressRect)

	progressRect.icon = nil
end

local function isCooldownActive(progressRect)
	if not progressRect or progressRect:isDestroyed() then
		return false
	end

	local callback = progressRect.callback

	return callback ~= nil and callback[ProgressCallback.update] ~= nil
end

local function resetCooldownFillBar(progressRect)
	if not progressRect or progressRect:isDestroyed() then
		return
	end

	local bar = progressRect:getChildById("cooldownFillBar")

	if not bar then
		return
	end

	bar:setWidth(0)
	bar:setVisible(false)
end

local function setGroupIconOverlay(icon, visible)
	if not icon or icon:isDestroyed() then
		return
	end

	icon:setOn(not visible)

	local overlay = icon:getChildById("disabledOverlay")

	if overlay then
		overlay:setVisible(visible)
	end
end

local function getSpellCooldownStartTime(icon)
	if not icon or icon:isDestroyed() then
		return math.huge
	end

	local progressRect = icon:getChildById(icon:getId())

	if progressRect and progressRect.cooldownStartTime then
		return progressRect.cooldownStartTime
	end

	return math.huge
end

local function sortSpellCooldownIcons()
	if not cooldownPanel or cooldownPanel:isDestroyed() then
		return
	end

	local children = cooldownPanel:getChildren()

	if not children or #children <= 1 then
		return
	end

	local icons = {}

	for i = 1, #children do
		icons[i] = children[i]
	end

	table.sort(icons, function(a, b)
		local startA = getSpellCooldownStartTime(a)
		local startB = getSpellCooldownStartTime(b)

		if startA ~= startB then
			return startA < startB
		end

		return tostring(a:getId()) < tostring(b:getId())
	end)
	cooldownPanel:reorderChildren(icons)
end

local focusMasteryGlow = nil
local focusMasteryTimerEvent = nil
local FOCUS_MASTERY_WINDOW_MS = 12000

local function getFocusMasteryGlow()
	if focusMasteryGlow and not focusMasteryGlow:isDestroyed() then
		return focusMasteryGlow
	end
	if contentsPanel and not contentsPanel:isDestroyed() then
		focusMasteryGlow = contentsPanel:getChildById("focusMasteryReadyGlow")
	end
	return focusMasteryGlow
end

function clearFocusMasteryVisual()
	if focusMasteryTimerEvent then
		removeEvent(focusMasteryTimerEvent)
		focusMasteryTimerEvent = nil
	end
	local glow = getFocusMasteryGlow()
	if glow then
		glow:setVisible(false)
	end
end

function setFocusMasteryReady(visible, durationMs)
	clearFocusMasteryVisual()
	if not visible then
		return
	end

	local focusIcon = contentsPanel and contentsPanel:getChildById("groupIconFocus")
	if not focusIcon or not focusIcon:isVisible() then
		return
	end

	local glow = getFocusMasteryGlow()
	if glow then
		glow:setVisible(true)
	end
	local duration = (durationMs and durationMs > 0) and durationMs or FOCUS_MASTERY_WINDOW_MS
	focusMasteryTimerEvent = scheduleEvent(function()
		focusMasteryTimerEvent = nil
		local g = getFocusMasteryGlow()
		if g then
			g:setVisible(false)
		end
	end, duration)
end

local function onWheelFocusMasteryOpcode(_, _, data)
	if type(data) ~= "table" then
		return
	end
	local state = data.state
	if state == "armed" then
		setFocusMasteryReady(true, tonumber(data.duration) or FOCUS_MASTERY_WINDOW_MS)
	else
		clearFocusMasteryVisual()
	end
end

function init()
	connect(g_game, {
		onGameEnd = offline,
		onGameStart = online,
		onSpellGroupCooldown = onSpellGroupCooldown,
		onSpellCooldown = onSpellCooldown
	})

	cooldownWindow = g_ui.loadUI("cooldown", modules.game_interface.getBottomActionPanel())
	contentsPanel = cooldownWindow:getChildById("contentsPanel2")
	cooldownPanel = contentsPanel:getChildById("cooldownPanel")
	focusMasteryGlow = contentsPanel:getChildById("focusMasteryReadyGlow")
	refreshConsoleAnchor()

	ProtocolGame.registerExtendedJSONOpcode(ExtendedIds.WheelFocusMastery, onWheelFocusMasteryOpcode)

	for k, v in pairs(SpelllistSettings) do
		g_textures.preload(v.iconFile)
	end

	g_textures.preload(SpellGroupIconFile)
	g_textures.preload("/images/game/spells/slot-mini-spellicon")
	g_textures.preload(SPELL_ICON_FILE)

	if g_game.isOnline() then
		online()
	end

	setSpellGroupCooldownsVisible(modules.client_options.getOption("showSpellGroupCooldowns"))
	applySpellGroupIconVisibility()
	if modules.game_actionbar and modules.game_actionbar.refreshBottomCooldownDock then
		modules.game_actionbar.refreshBottomCooldownDock()
	end
end

function terminate()
	ProtocolGame.unregisterExtendedJSONOpcode(ExtendedIds.WheelFocusMastery)
	clearFocusMasteryVisual()

	disconnect(g_game, {
		onGameEnd = offline,
		onGameStart = online,
		onSpellGroupCooldown = onSpellGroupCooldown,
		onSpellCooldown = onSpellCooldown
	})

	if cooldownPanel then
		for _, icon in ipairs(cooldownPanel:getChildren()) do
			for _, child in ipairs(icon:getChildren()) do
				releaseProgressRect(child)
			end
		end
	end

	cooldownWindow:destroy()

	cooldownWindow = nil
	contentsPanel = nil
	cooldownPanel = nil
end

function loadIcon(iconId)
	if not cooldownPanel or cooldownPanel:isDestroyed() then
		return
	end

	local spell, profile, spellName = Spells.getSpellByIcon(iconId)

	if not spellName then
		return
	end

	if not profile then
		return
	end

	local icon = cooldownPanel:getChildById(iconId)

	if not icon then
		icon = g_ui.createWidget("SpellIcon")
		icon:setId(iconId)
	end

	local iconImage = icon:getChildById("icon")
	local clip = Spells.getSpellCooldownImageClip(spell, profile)

	if iconImage and clip then
		iconImage:setImageSource(SPELL_ICON_FILE)
		iconImage:setImageClip(clip)
	else
		icon:destroy()
		icon = nil
	end

	return icon
end

function onMiniWindowOpen()
	modules.client_options.setOption("showSpellGroupCooldowns", true)
end

function onMiniWindowClose()
	modules.client_options.setOption("showSpellGroupCooldowns", false)
end

function refreshConsoleAnchor()
	local console = modules.game_console and modules.game_console.consolePanel

	if not console or console:isDestroyed() then
		return
	end

	console:removeAnchor(AnchorTop)
	console:addAnchor(AnchorTop, "parent", AnchorTop)
end

function online()
	refreshConsoleAnchor()

	if not g_game.getFeature(GameSpellList) then
		modules.client_options.setOption("showSpellGroupCooldowns", false)

		return
	end

	applySpellGroupIconVisibility()

	refresh()
	lastPlayer = g_game.getCharacterName()
end

function offline()
	local console = modules.game_console.consolePanel

	if console then
		console:removeAnchor(AnchorTop)
		console:fill("parent")
	end

	if contentsPanel then
		for _, child in ipairs(contentsPanel:getChildren()) do
			local id = child:getId()

			if id and id:sub(1, 12) == "progressRect" then
				cancelCooldownEvent(child)
				child:setPercent(100)
				resetCooldownFillBar(child)
			elseif id and id:sub(1, 9) == "groupIcon" then
				setGroupIconOverlay(child, true)
			end
		end
	end

	if cooldownPanel then
		for _, icon in ipairs(cooldownPanel:getChildren()) do
			for _, child in ipairs(icon:getChildren()) do
				releaseProgressRect(child)
			end
		end
	end

	cooldown = {}
	groupCooldown = {}
	clearFocusMasteryVisual()
	refresh()
end

function refresh()
	if cooldownPanel then
		for _, icon in ipairs(cooldownPanel:getChildren()) do
			for _, child in ipairs(icon:getChildren()) do
				releaseProgressRect(child)
			end
		end

		cooldownPanel:destroyChildren()
	end

	cooldown = {}
end

function removeCooldown(progressRect)
	if not progressRect or progressRect:isDestroyed() then
		return
	end

	local icon = progressRect.icon

	releaseProgressRect(progressRect)

	if icon and not icon:isDestroyed() then
		icon:destroy()
	end
end

function turnOffCooldown(progressRect)
	if not progressRect or progressRect:isDestroyed() then
		return
	end

	cancelCooldownEvent(progressRect)
	progressRect:setPercent(100)
	resetCooldownFillBar(progressRect)

	if progressRect.icon then
		setGroupIconOverlay(progressRect.icon, true)

		progressRect.icon = nil
	end
end

function initCooldown(progressRect, updateCallback, finishCallback, duration)
	progressRect:setPercent(0)

	local now = g_clock.millis()
	if duration and duration > 0 then
		if not progressRect.cooldownStartTime then
			progressRect.cooldownStartTime = now
		end
		progressRect.cooldownEndTime = now + duration
		progressRect.cooldownDuration = duration
	else
		progressRect.cooldownStartTime = nil
		progressRect.cooldownEndTime = nil
		progressRect.cooldownDuration = nil
	end

	updateCooldownBar(progressRect)

	progressRect.callback = {}
	progressRect.callback[ProgressCallback.update] = updateCallback
	progressRect.callback[ProgressCallback.finish] = finishCallback

	updateCallback()
end

function updateCooldownBar(progressRect)
	local bar = progressRect:getChildById("cooldownFillBar")

	if not bar then
		return
	end

	local percent = progressRect:getPercent()
	local remainingPercent = 100 - percent

	if remainingPercent <= 0.01 then
		resetCooldownFillBar(progressRect)

		return
	end

	local width = getCooldownFillBarWidth(progressRect)
	local barWidth = math.floor(width * remainingPercent / 100 + 0.0001)

	barWidth = math.max(0, math.min(width, barWidth))

	if barWidth <= 0 then
		resetCooldownFillBar(progressRect)

		return
	end

	bar:setWidth(barWidth)
	bar:setVisible(true)
end

function updateCooldown(progressRect, duration)
	if not isCooldownActive(progressRect) then
		return
	end

	local endTime = progressRect.cooldownEndTime
	local totalDuration = progressRect.cooldownDuration or duration

	if endTime and totalDuration and totalDuration > 0 then
		local remaining = endTime - g_clock.millis()

		if remaining <= 0 then
			progressRect:setPercent(100)
			updateCooldownBar(progressRect)

			local finishCallback = progressRect.callback[ProgressCallback.finish]

			cancelCooldownEvent(progressRect)

			if finishCallback then
				finishCallback()
			end

			return
		end

		local elapsed = totalDuration - remaining
		local percent = elapsed * 100 / totalDuration

		if elapsed <= 0 then
			percent = 0
		end

		progressRect:setPercent(math.min(100, math.max(0, percent)))
	else
		progressRect:setPercent(progressRect:getPercent() + 10000 / duration)
	end

	updateCooldownBar(progressRect)

	if progressRect:getPercent() < 99.99 then
		removeEvent(progressRect.event)

		progressRect.event = scheduleEvent(function()
			if progressRect:isDestroyed() or not isCooldownActive(progressRect) then
				return
			end

			progressRect.callback[ProgressCallback.update]()
		end, 100)
	else
		progressRect:setPercent(100)
		updateCooldownBar(progressRect)

		local finishCallback = progressRect.callback[ProgressCallback.finish]

		cancelCooldownEvent(progressRect)

		if finishCallback then
			finishCallback()
		end
	end
end

function isGroupCooldownIconActive(groupId)
	return groupCooldown[groupId]
end

function isCooldownIconActive(iconId)
	return cooldown[iconId]
end

function onSpellCooldown(iconId, duration)
	if not cooldownWindow or cooldownWindow:isDestroyed() then
		return
	end

	local icon = loadIcon(iconId)

	if not icon then
		return
	end

	icon:setParent(cooldownPanel)

	local progressRect = icon:getChildById(iconId)

	if not progressRect then
		progressRect = g_ui.createWidget("SpellProgressRect", icon)

		progressRect:setId(iconId)

		progressRect.icon = icon

		progressRect:fill("parent")
	else
		cancelCooldownEvent(progressRect)
		progressRect:setPercent(0)
	end

	local function updateFunc()
		local rect = icon:getChildById(iconId)

		if rect and not rect:isDestroyed() then
			updateCooldown(rect, duration)
		end
	end

	local function finishFunc()
		local rect = icon:getChildById(iconId)

		if rect and not rect:isDestroyed() then
			removeCooldown(rect)
		elseif icon and not icon:isDestroyed() then
			icon:destroy()
		end

		cooldown[iconId] = false
	end

	initCooldown(progressRect, updateFunc, finishFunc, duration)
	setGroupIconOverlay(icon, false)

	cooldown[iconId] = true

	sortSpellCooldownIcons()
end

function onSpellGroupCooldown(groupId, duration)
	if not cooldownWindow or cooldownWindow:isDestroyed() then
		return
	end

	if not SpellGroups[groupId] then
		return
	end

	local icon = contentsPanel:getChildById("groupIcon" .. SpellGroups[groupId])
	local progressRect = contentsPanel:getChildById("progressRect" .. SpellGroups[groupId])

	if not icon or not icon:isVisible() then
		return
	end

	if icon then
		removeEvent(icon.event)
	end

	if progressRect then
		progressRect.icon = icon

		cancelCooldownEvent(progressRect)

		local function updateFunc()
			updateCooldown(progressRect, duration)
		end

		local function finishFunc()
			turnOffCooldown(progressRect)

			groupCooldown[groupId] = false
		end

		initCooldown(progressRect, updateFunc, finishFunc, duration)

		if icon then
			setGroupIconOverlay(icon, false)
		end

		groupCooldown[groupId] = true
	end
end

function setSpellGroupCooldownsVisible(visible)
	if not cooldownWindow or cooldownWindow:isDestroyed() then
		return
	end
	if visible then
		cooldownWindow:setHeight(26)
		cooldownWindow:show()
		applySpellGroupIconVisibility()
	else
		cooldownWindow:hide()
		cooldownWindow:setHeight(0)
	end

	if modules.game_actionbar and modules.game_actionbar.refreshBottomCooldownDock then
		modules.game_actionbar.refreshBottomCooldownDock()
	end

	refreshConsoleAnchor()

	if modules.game_interface and modules.game_interface.applyBottomSplitterLayoutHeight then
		modules.game_interface.applyBottomSplitterLayoutHeight()
	end
end
