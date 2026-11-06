local podiumWindow
local monsterList
local previewGround
local previewCreature
local searchField

local showoffOutfit = {}
local isBossPoduim
local position
local showCreature
local podiumVisible
local podiumDirection
local thingID
local thingStackPos = 0

local podiumItem
local currentOutfit
local lastChecked
local currentRaceID = 0

local bossList = {}
local creatureList = {}
local bossOutfitByRace = {}

function setBossOutfits(outfits)
	bossOutfitByRace = outfits or {}
end

local function matchText(text, search)
	if not search or search == '' then
		return true
	end

	return text:find(search, 1, true) ~= nil
end

local function capitalize(text)
	if not text or text == '' then
		return ''
	end

	return text:sub(1, 1):upper() .. text:sub(2)
end

local function normalizePodiumOutfit(outfit)
	if not outfit or type(outfit) ~= 'table' then
		return nil
	end

	local lookType = outfit.type or 0
	local auxType = outfit.auxType or 0
	if lookType <= 0 and auxType <= 0 then
		return nil
	end

	local normalized = {
		type = lookType,
		auxType = auxType,
		head = outfit.head or 0,
		body = outfit.body or 0,
		legs = outfit.legs or 0,
		feet = outfit.feet or 0,
		addons = outfit.addons or 0,
	}

	if outfit.category ~= nil then
		normalized.category = outfit.category
	elseif lookType > 0 then
		normalized.category = ThingCategoryCreature
	elseif auxType > 0 then
		normalized.category = ThingCategoryItem
	end

	return normalized
end

local function isPodiumOutfitRenderable(outfit)
	outfit = normalizePodiumOutfit(outfit)
	if not outfit or not g_things or not g_things.getThingType then
		return outfit ~= nil
	end

	if outfit.type and outfit.type > 0 then
		local thingType = g_things.getThingType(outfit.type, ThingCategoryCreature)
		if not thingType or (thingType.isNull and thingType:isNull()) then
			return false
		end
		return true
	end

	if outfit.auxType and outfit.auxType > 0 then
		local thingType = g_things.getThingType(outfit.auxType, ThingCategoryItem)
		if not thingType or (thingType.isNull and thingType:isNull()) then
			return false
		end
		return true
	end

	return false
end

local function listEntryToOutfit(entry)
	if not entry then
		return nil
	end

	return normalizePodiumOutfit({
		type = entry[2] or 0,
		auxType = entry[3] or 0,
		head = entry[4] or 0,
		body = entry[5] or 0,
		legs = entry[6] or 0,
		feet = entry[7] or 0,
		addons = entry[8] or 0,
	})
end

local function outfitsMatch(stored, current)
	if not stored or not current then
		return false
	end

	if current.type and current.type ~= 0 then
		return stored.type == current.type and (stored.head or 0) == (current.head or 0) and
			(stored.body or 0) == (current.body or 0) and (stored.legs or 0) == (current.legs or 0) and
			(stored.feet or 0) == (current.feet or 0) and (stored.addons or 0) == (current.addons or 0)
	end

	if current.auxType and current.auxType ~= 0 then
		return (stored.auxType or 0) == current.auxType
	end

	return false
end

local function findStaticRaceName(raceId)
	if not g_things or not g_things.getRacesByName then
		return nil
	end

	local ok, races = pcall(function()
		return g_things.getRacesByName('')
	end)
	if not ok or not races then
		return nil
	end

	for _, race in ipairs(races) do
		if race.raceId == raceId and race.name and race.name ~= '' then
			return race.name
		end
	end

	return nil
end

local function getRaceListEntry(raceId)
	raceId = tonumber(raceId) or 0
	if raceId <= 0 then
		return nil
	end

	local serverOutfit = normalizePodiumOutfit(bossOutfitByRace[raceId])
	local serverName = bossList[raceId]
	if serverOutfit and serverName and serverName ~= '' and isPodiumOutfitRenderable(serverOutfit) then
		return {
			serverName,
			serverOutfit.type or 0,
			serverOutfit.auxType or 0,
			serverOutfit.head or 0,
			serverOutfit.body or 0,
			serverOutfit.legs or 0,
			serverOutfit.feet or 0,
			serverOutfit.addons or 0,
		}
	end

	if g_things and g_things.getRaceData then
		local raceData = g_things.getRaceData(raceId)
		if raceData and raceData.raceId and raceData.raceId ~= 0 and raceData.name and raceData.name ~= '' then
			local podiumOutfit = normalizePodiumOutfit(raceData.outfit)
			if podiumOutfit and isPodiumOutfitRenderable(podiumOutfit) then
				return {
					raceData.name,
					podiumOutfit.type or 0,
					podiumOutfit.auxType or 0,
					podiumOutfit.head or 0,
					podiumOutfit.body or 0,
					podiumOutfit.legs or 0,
					podiumOutfit.feet or 0,
					podiumOutfit.addons or 0,
				}
			end
		end
	end

	local bossOutfit = normalizePodiumOutfit(bossOutfitByRace[raceId])
	local bossName = bossList[raceId]
	if bossOutfit and bossName and isPodiumOutfitRenderable(bossOutfit) then
		return {
			bossName,
			bossOutfit.type or 0,
			bossOutfit.auxType or 0,
			bossOutfit.head or 0,
			bossOutfit.body or 0,
			bossOutfit.legs or 0,
			bossOutfit.feet or 0,
			bossOutfit.addons or 0,
		}
	end

	-- Forgotten Server raceIds often match lookType; staticdata race banks may not.
	local lookTypeFallback = normalizePodiumOutfit({ type = raceId })
	if lookTypeFallback and isPodiumOutfitRenderable(lookTypeFallback) then
		local name = bossList[raceId] or findStaticRaceName(raceId) or ('Race ' .. raceId)
		return {
			name,
			lookTypeFallback.type or 0,
			lookTypeFallback.auxType or 0,
			lookTypeFallback.head or 0,
			lookTypeFallback.body or 0,
			lookTypeFallback.legs or 0,
			lookTypeFallback.feet or 0,
			lookTypeFallback.addons or 0,
		}
	end

	return nil
end

local function findCurrentRaceId(outfit, podiumBoss, bosses, monsters)
	if not outfit or ((outfit.type or 0) == 0 and (outfit.auxType or 0) == 0) then
		return 0
	end

	if podiumBoss then
		for raceId in pairs(bosses or {}) do
			local entry = getRaceListEntry(raceId)
			if entry and outfitsMatch(listEntryToOutfit(entry), outfit) then
				return raceId
			end
		end
	else
		for _, raceId in ipairs(monsters or {}) do
			local entry = getRaceListEntry(raceId)
			if entry and outfitsMatch(listEntryToOutfit(entry), outfit) then
				return raceId
			end
		end
	end

	return 0
end

local function applyPodiumCreaturePreview(spriteWidget)
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

	local creature = spriteWidget.getCreature and spriteWidget:getCreature()
	if creature and creature.setStaticWalking then
		creature:setStaticWalking(0)
	end
end

local function bindCreatureRace(widget, raceId, outfit)
	widget.raceId = raceId

	outfit = normalizePodiumOutfit(outfit)
	if not outfit or not isPodiumOutfitRenderable(outfit) then
		return false
	end

	widget:setOutfit(outfit)
	applyPodiumCreaturePreview(widget)
	return true
end

function init()
	podiumWindow = g_ui.displayUI('mpodium')
	podiumWindow:hide()

	previewGround = podiumWindow:recursiveGetChildById('PreviewGround')
	previewCreature = podiumWindow:recursiveGetChildById('previewCreature')
	applyPodiumCreaturePreview(previewCreature)
	monsterList = podiumWindow:recursiveGetChildById('monsterList')
	searchField = podiumWindow:recursiveGetChildById('searchfiltercreatures')
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
	currentRaceID = 0

	if podiumWindow and podiumWindow:isVisible() then
		podiumWindow:hide()
	end
end

function requestMonsterData(thing)
	thingID = thing:getId()
	thingStackPos = thing:getStackPos()
	g_game.use(thing)
	monsterList:destroyChildren()
end

function onParseMonsterPodium(currentOutfit, currentID, podiumBoss, bosses, monsters, pos, itemID, stackPos, showPodium,
	isShowingCreature, direction)
	if not podiumWindow then
		return
	end

	if not podiumWindow:isVisible() then
		podiumWindow:show()
		podiumWindow:focus()
	end

	showoffOutfit = currentOutfit
	isBossPoduim = podiumBoss
	position = pos
	thingID = itemID
	thingStackPos = stackPos
	showCreature = isShowingCreature
	podiumVisible = showPodium
	podiumDirection = direction

	bossList = bosses or {}
	creatureList = monsters or {}
	currentRaceID = currentID ~= 0 and currentID or findCurrentRaceId(currentOutfit, podiumBoss, bossList, creatureList)

	previewGround.item:setItemId(itemID)
	podiumItem = previewGround.item:getItem()

	local showFloor = podiumWindow:recursiveGetChildById('ShowFloor')

	if showFloor and showFloor.floor then
		showFloor.floor:setChecked(true)
	end

	local creatureShow = podiumWindow:recursiveGetChildById('creatureShow')

	if creatureShow then
		creatureShow:setChecked(showCreature)
	end

	local podiumShow = podiumWindow:recursiveGetChildById('podium')

	if podiumShow then
		podiumShow:setChecked(podiumVisible)
	end

	showMonsterPodium()
end

function showMonsterPodium(filter)
	podiumItem = previewGround.item:getItem()

	if not podiumItem or not previewCreature then
		return
	end

	if monsterList then
		monsterList:destroyChildren()
	end

	if showoffOutfit.type ~= 128 then
		currentOutfit = showoffOutfit
	end

	if showCreature and currentOutfit then
		local previewOutfit = normalizePodiumOutfit(currentOutfit)
		if previewOutfit and isPodiumOutfitRenderable(previewOutfit) then
			previewCreature:setVisible(true)
			previewCreature:setOutfit(previewOutfit)
			previewCreature:setDirection(podiumDirection)
			applyPodiumCreaturePreview(previewCreature)
		else
			previewCreature:setVisible(false)
		end
	else
		previewCreature:setVisible(false)
	end

	previewGround.item:setVisible(podiumVisible)

	if isBossPoduim then
		for k, v in pairs(bossList) do
			local currentRace = getRaceListEntry(k)
			if not currentRace then
				goto continue
			end

			local name = capitalize(v ~= '' and v or currentRace[1])

			if filter and not matchText(name:lower(), filter:lower()) then
				goto continue
			end

			local widget = g_ui.createWidget('PodiumCreatureBox', monsterList)

			widget.checkBox.name:setText(name)

			if widget.checkBox.name:isTextWraped() then
				widget.checkBox.name:setMarginTop(32)
			end

			if not bindCreatureRace(widget.checkBox.creature, k, listEntryToOutfit(currentRace)) then
				widget:destroy()
				goto continue
			end

			::continue::
		end
	else
		for _, v in ipairs(creatureList) do
			local currentRace = getRaceListEntry(v)

			if not currentRace then
				goto continue
			end

			if filter and not matchText(currentRace[1]:lower(), filter:lower()) then
				goto continue
			end

			local widget = g_ui.createWidget('PodiumCreatureBox', monsterList)

			widget.checkBox.name:setText(currentRace[1])

			if widget.checkBox.name:isTextWraped() then
				widget.checkBox.name:setMarginTop(32)
			end

			if not bindCreatureRace(widget.checkBox.creature, v, listEntryToOutfit(currentRace)) then
				widget:destroy()
				goto continue
			end

			::continue::
		end
	end
end

function showFloor(checked)
	if checked then
		previewGround:setImageSource('/images/game/outfit_ground')
	else
		previewGround:setImageSource('/modules/game_podium_monster/images/ui/panel-background')
	end
end

function showCreatureOutfit(checked)
	showCreature = checked

	if not previewCreature then
		return
	end

	if checked then
		local previewOutfit = normalizePodiumOutfit(currentOutfit)
		if previewOutfit and isPodiumOutfitRenderable(previewOutfit) then
			previewCreature:setVisible(true)
			previewCreature:setOutfit(previewOutfit)
			previewCreature:setDirection(podiumDirection)
			applyPodiumCreaturePreview(previewCreature)
		else
			previewCreature:setVisible(false)
		end
	else
		previewCreature:setVisible(false)
	end
end

function showPodiumItem(checked)
	podiumVisible = checked
	previewGround.item:setVisible(checked)
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

	currentOutfit = normalizePodiumOutfit(current:getOutfit())
	currentRaceID = current.raceId or 0
	if currentOutfit and isPodiumOutfitRenderable(currentOutfit) then
		previewCreature:setOutfit(currentOutfit)
		applyPodiumCreaturePreview(previewCreature)
		previewCreature:setDirection(podiumDirection or 2)
	end

	if showCreature then
		previewCreature:setVisible(true)
	end
end

function onChangeDirection(isRight)
	if not previewCreature then
		return
	end

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

function onSelectCreature()
	if not podiumItem then
		return
	end

	if not currentRaceID or currentRaceID == 0 then
		previewCreature:setVisible(false)
	end

	if not showCreature then
		currentRaceID = 0
	end

	g_game.sendMonsterPodiumOutfit(currentRaceID, position, thingID, thingStackPos, podiumDirection, podiumVisible,
		showCreature)
	hide()
end

function onSearchChange(self)
	monsterList:destroyChildren()

	if #self:getText() == 0 then
		showMonsterPodium()

		return
	end

	showMonsterPodium(self:getText())
end
