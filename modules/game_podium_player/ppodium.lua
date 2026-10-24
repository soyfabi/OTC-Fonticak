local podiumWindow
local outfitList
local previewGround
local previewCreature
local searchField

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

function init()
	podiumWindow = g_ui.displayUI('ppodium')
	podiumWindow:hide()
	previewGround = podiumWindow:recursiveGetChildById('PreviewGround')
	previewCreature = podiumWindow:recursiveGetChildById('previewCreature')
	applyPreview(previewCreature)
	outfitList = podiumWindow:recursiveGetChildById('monsterList')
	searchField = podiumWindow:recursiveGetChildById('searchfilteroutfits')
end

function terminate()
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
	if podiumWindow and podiumWindow:isVisible() then
		podiumWindow:hide()
	end
end

function onParsePlayerPodium(podiumOutfit, outfits, pos, itemID, stackPos, showPodium, isShowingCreature, direction)
	if not podiumWindow then
		return
	end

	if not podiumWindow:isVisible() then
		podiumWindow:show()
		podiumWindow:focus()
	end

	showoffOutfit = podiumOutfit or {}
	position = pos
	thingID = itemID
	thingStackPos = stackPos
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

	showPlayerPodium()
end

function showPlayerPodium(filter)
	if not previewCreature or not previewGround or not previewGround.item then
		return
	end

	if showoffOutfit.type ~= 128 then
		currentOutfit = normalizeOutfit(showoffOutfit)
	end

	if outfitList then
		outfitList:destroyChildren()
	end

	if showCreature and currentOutfit and isOutfitRenderable(currentOutfit) then
		previewCreature:setVisible(true)
		previewCreature:setOutfit(currentOutfit)
		previewCreature:setDirection(podiumDirection or 2)
		applyPreview(previewCreature)
	else
		previewCreature:setVisible(false)
	end

	previewGround.item:setVisible(podiumVisible)

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
	if checked and currentOutfit and isOutfitRenderable(currentOutfit) then
		previewCreature:setVisible(true)
		previewCreature:setOutfit(currentOutfit)
		previewCreature:setDirection(podiumDirection or 2)
	else
		previewCreature:setVisible(false)
	end
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

	currentOutfit = normalizeOutfit({
		type = entry.lookType,
		head = entry.head,
		body = entry.body,
		legs = entry.legs,
		feet = entry.feet,
		addons = entry.addons,
	})
	if currentOutfit and isOutfitRenderable(currentOutfit) then
		previewCreature:setOutfit(currentOutfit)
		previewCreature:setDirection(podiumDirection or 2)
		if showCreature then
			previewCreature:setVisible(true)
		end
	end
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
	local outfit = currentOutfit or {}
	if g_game.changeOutfitPodium then
		g_game.changeOutfitPodium(outfit, position, thingID, thingStackPos, podiumDirection or 2, podiumVisible,
			showCreature)
	else
		local lookType = showCreature and (outfit.type or 0) or 0
		g_game.sendPlayerPodiumOutfit(lookType, outfit.head or 0, outfit.body or 0, outfit.legs or 0, outfit.feet or 0,
			outfit.addons or 0, outfit.mount or 0, position, thingID, thingStackPos, podiumDirection or 2, podiumVisible,
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
