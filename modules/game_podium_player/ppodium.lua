local podiumWindow
local outfitList
local previewGround
local previewCreature
local searchField
local addon1Check
local addon2Check
local colorGrid
local colorBoxGroup
local currentColorBox
local colorMode = 'head'

local playerPodiumContext = {}

local showoffOutfit = {}
local position
local showCreature
local podiumVisible
local podiumDirection
local thingID
local thingStackPos = 0

local outfitEntries = {}
local currentOutfit
local lastChecked
local maxUnlockedAddons = 0

function getPodiumSendContext()
	return playerPodiumContext
end

local function normalizeOutfit(outfit)
	if not outfit or type(outfit) ~= 'table' then
		return nil
	end

	local lookType = outfit.type or 0
	local auxType = outfit.auxType or 0
	if lookType <= 0 and auxType <= 0 then
		return nil
	end

	return {
		type = lookType,
		auxType = auxType,
		head = outfit.head or 0,
		body = outfit.body or 0,
		legs = outfit.legs or 0,
		feet = outfit.feet or 0,
		addons = outfit.addons or 0,
		mount = outfit.mount or 0,
	}
end

local function isOutfitRenderable(outfit)
	outfit = normalizeOutfit(outfit)
	if not outfit or not g_things or not g_things.getThingType then
		return outfit ~= nil
	end

	if outfit.type > 0 then
		local thingType = g_things.getThingType(outfit.type, ThingCategoryCreature)
		return thingType and not (thingType.isNull and thingType:isNull())
	end

	return false
end

local function applyPreview(spriteWidget)
	if not spriteWidget then
		return
	end
	if spriteWidget.setCenter then
		spriteWidget:setCenter(true)
	end
	if spriteWidget.setCreatureSize then
		spriteWidget:setCreatureSize(64)
	end
	if spriteWidget.setAnimate then
		spriteWidget:setAnimate(false)
	end
	if spriteWidget.setIdleAnimate then
		spriteWidget:setIdleAnimate(false)
	end
end

local function getSelectedAddons()
	local addons = 0
	if addon1Check and addon1Check:isChecked() and addon1Check:isEnabled() then
		addons = addons + 1
	end
	if addon2Check and addon2Check:isChecked() and addon2Check:isEnabled() then
		addons = addons + 2
	end
	return addons
end

local function syncAddonChecks(unlockedAddons, wornAddons)
	maxUnlockedAddons = unlockedAddons or 0
	wornAddons = wornAddons or (currentOutfit and currentOutfit.addons) or 0
	if not addon1Check or not addon2Check then
		return
	end

	addon1Check:setEnabled(maxUnlockedAddons >= 1)
	addon2Check:setEnabled(maxUnlockedAddons >= 2)
	addon1Check:setChecked(maxUnlockedAddons >= 1 and wornAddons % 2 == 1)
	addon2Check:setChecked(maxUnlockedAddons >= 2 and wornAddons >= 2)
	if currentOutfit then
		currentOutfit.addons = getSelectedAddons()
	end
end

local function refreshPreviewCreature()
	if not previewCreature then
		return
	end

	if showCreature and currentOutfit and isOutfitRenderable(currentOutfit) then
		local preview = table.copy(currentOutfit)
		preview.addons = getSelectedAddons()
		previewCreature:setVisible(true)
		previewCreature:setOutfit(preview)
		previewCreature:setDirection(podiumDirection or 2)
		applyPreview(previewCreature)
	else
		previewCreature:setVisible(false)
	end
end

local function bindOutfitWidget(widget, entry)
	local outfit = normalizeOutfit({
		type = entry.lookType,
		head = entry.head,
		body = entry.body,
		legs = entry.legs,
		feet = entry.feet,
		addons = entry.addons,
	})
	if not outfit or not isOutfitRenderable(outfit) then
		return false
	end
	widget.entry = entry
	widget:setOutfit(outfit)
	applyPreview(widget)
	return true
end

local function selectColorBoxForMode()
	if not colorBoxGroup or not colorGrid or not currentOutfit then
		return
	end

	local colorId = currentOutfit[colorMode] or 0
	local box = colorGrid:getChildById('colorBox' .. colorId)
	if box then
		colorBoxGroup:selectWidget(box)
	end
end

local function setupColorPicker()
	if not colorGrid or colorBoxGroup then
		return
	end

	colorBoxGroup = UIRadioGroup.create()
	colorGrid:destroyChildren()

	for j = 0, 6 do
		for i = 0, 18 do
			local colorId = j * 19 + i
			local colorBox = g_ui.createWidget('ColorBox', colorGrid)
			colorBox:setId('colorBox' .. colorId)
			colorBox.colorId = colorId
			colorBox:setSize('11 11')
			if getOutfitColor then
				colorBox:setBackgroundColor(getOutfitColor(colorId))
			end
			colorBoxGroup:addWidget(colorBox)
		end
	end

	colorBoxGroup.onSelectionChange = function(_, selectedWidget)
		if not selectedWidget or not currentOutfit then
			return
		end
		currentColorBox = selectedWidget
		currentOutfit[colorMode] = selectedWidget.colorId
		refreshPreviewCreature()
	end

	setColorMode('head')
end

function setColorMode(mode)
	colorMode = mode or 'head'
	selectColorBoxForMode()
end

function onAddonChange()
	if currentOutfit then
		currentOutfit.addons = getSelectedAddons()
	end
	refreshPreviewCreature()
end

function init()
	podiumWindow = g_ui.displayUI('ppodium')
	podiumWindow:hide()
	previewGround = podiumWindow:recursiveGetChildById('PreviewGround')
	previewCreature = podiumWindow:recursiveGetChildById('previewCreature')
	applyPreview(previewCreature)
	outfitList = podiumWindow:recursiveGetChildById('monsterList')
	searchField = podiumWindow:recursiveGetChildById('searchfilteroutfits')
	addon1Check = podiumWindow:recursiveGetChildById('addon1')
	addon2Check = podiumWindow:recursiveGetChildById('addon2')
	colorGrid = podiumWindow:recursiveGetChildById('podiumColorGrid')
	setupColorPicker()
end

function terminate()
	if colorBoxGroup then
		colorBoxGroup:destroy()
		colorBoxGroup = nil
	end
	if podiumWindow then
		podiumWindow:destroy()
		podiumWindow = nil
	end
end

function hide()
	if previewCreature then
		previewCreature:setVisible(false)
		previewCreature:setOutfit({})
	end
	if searchField then
		searchField:clearText()
	end
	currentOutfit = nil
	lastChecked = nil
	playerPodiumContext = {}
	if podiumWindow and podiumWindow:isVisible() then
		podiumWindow:hide()
	end
end

function onParsePlayerPodium(podiumOutfit, outfits, pos, itemID, stackPos, showPodium, isShowingCreature, direction)
	if not podiumWindow then
		return
	end

	playerPodiumContext = {
		position = pos,
		itemClientId = itemID,
		stackpos = stackPos,
	}

	if not podiumWindow:isVisible() then
		podiumWindow:show()
		podiumWindow:focus()
	end

	showoffOutfit = podiumOutfit or {}
	position = pos
	thingID = itemID
	thingStackPos = stackPos or 0
	showCreature = isShowingCreature
	podiumVisible = showPodium
	podiumDirection = direction
	outfitEntries = outfits or {}
	currentOutfit = normalizeOutfit(showoffOutfit)

	previewGround.item:setItemId(itemID)

	local creatureShow = podiumWindow:recursiveGetChildById('creatureShow')
	if creatureShow then
		creatureShow:setChecked(showCreature)
	end
	local podiumShow = podiumWindow:recursiveGetChildById('podium')
	if podiumShow then
		podiumShow:setChecked(podiumVisible)
	end

	local unlockedAddons = 0
	if currentOutfit then
		for _, entry in ipairs(outfitEntries) do
			if entry.lookType == currentOutfit.type then
				unlockedAddons = entry.addons or 0
				break
			end
		end
		if unlockedAddons == 0 and #outfitEntries > 0 then
			unlockedAddons = outfitEntries[1].addons or 0
		end
	end
	syncAddonChecks(unlockedAddons, currentOutfit and currentOutfit.addons or 0)
	selectColorBoxForMode()
	showPlayerPodium()
end

function showPlayerPodium(filter)
	if not previewCreature or not previewGround or not previewGround.item then
		return
	end

	currentOutfit = normalizeOutfit(showoffOutfit) or currentOutfit
	refreshPreviewCreature()
	previewGround.item:setVisible(podiumVisible)

	if outfitList then
		outfitList:destroyChildren()
	end

	for _, entry in ipairs(outfitEntries) do
		local name = entry.name or ''
		if filter and filter ~= '' and not name:lower():find(filter:lower(), 1, true) then
			goto continue
		end

		local widget = g_ui.createWidget('PodiumCreatureBox', outfitList)
		widget.checkBox.name:setText(name)
		if not bindOutfitWidget(widget.checkBox.creature, entry) then
			widget:destroy()
			goto continue
		end

		::continue::
	end
end

function showCreatureOutfit(checked)
	showCreature = checked
	refreshPreviewCreature()
end

function showPodiumItem(checked)
	podiumVisible = checked
	previewGround.item:setVisible(checked)
end

function showFloor(checked)
	if checked then
		previewGround:setImageSource('/modules/game_podium_monster/images/ui/panel-background')
	else
		previewGround:setImageSource('')
	end
end

function onCheckBox(widget, parentClick)
	local current = widget
	if parentClick then
		current = widget:recursiveGetChildById('creature')
		if lastChecked then
			lastChecked:setChecked(false)
		end
		lastChecked = widget
		widget:setChecked(true)
	else
		if lastChecked then
			lastChecked:setChecked(false)
		end
		lastChecked = widget:getParent()
		lastChecked:setChecked(true)
	end

	local entry = current.entry
	if not entry then
		return
	end

	local preserved = currentOutfit or showoffOutfit or {}
	currentOutfit = normalizeOutfit({
		type = entry.lookType,
		head = preserved.head or entry.head,
		body = preserved.body or entry.body,
		legs = preserved.legs or entry.legs,
		feet = preserved.feet or entry.feet,
		addons = preserved.addons or 0,
		mount = preserved.mount or showoffOutfit.mount,
	})

	if not showCreature then
		showCreature = true
		local creatureShow = podiumWindow:recursiveGetChildById('creatureShow')
		if creatureShow then
			creatureShow:setChecked(true)
		end
	end

	syncAddonChecks(entry.addons or 0, currentOutfit.addons or 0)
	selectColorBoxForMode()
	refreshPreviewCreature()
end

function onChangeDirection(isRight)
	local currentDirection = podiumDirection or 2
	if isRight then
		if currentDirection == 0 then
			podiumDirection = 3
		else
			podiumDirection = currentDirection - 1
		end
	else
		if currentDirection >= 3 then
			podiumDirection = 0
		else
			podiumDirection = currentDirection + 1
		end
	end
	previewCreature:setDirection(podiumDirection)
end

function onSelectOutfit()
	local outfit = table.copy(currentOutfit or {})
	outfit.addons = getSelectedAddons()

	if not showCreature then
		outfit.type = 0
	elseif not outfit.type or outfit.type <= 0 then
		g_logger.warning('Player podium: select an outfit before confirming.')
		return
	end

	local pos = playerPodiumContext.position or position
	local itemId = playerPodiumContext.itemClientId or thingID
	local stackPos = playerPodiumContext.stackpos or thingStackPos

	if not pos or pos.x == 65535 then
		g_logger.warning('Player podium: invalid podium position.')
		return
	end

	if g_game.changeOutfitPodium then
		g_game.changeOutfitPodium(outfit, pos, itemId, stackPos, podiumDirection or 2, podiumVisible, showCreature)
	else
		local lookType = showCreature and (outfit.type or 0) or 0
		g_game.sendPlayerPodiumOutfit(lookType, outfit.head or 0, outfit.body or 0, outfit.legs or 0, outfit.feet or 0,
			outfit.addons or 0, outfit.mount or 0, pos, itemId, stackPos, podiumDirection or 2, podiumVisible,
			showCreature)
	end
	hide()
end

function onSearchChange(self)
	if outfitList then
		outfitList:destroyChildren()
	end
	local text = self:getText()
	if text == '' then
		showPlayerPodium()
	else
		showPlayerPodium(text)
	end
end
