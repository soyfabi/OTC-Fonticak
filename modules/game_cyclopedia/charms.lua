protoData = protoData or {}

local MAX_ASSIGNED_CHARMS = 6

local charmsWindow
local widgets = {}
local bestiaryCharmCache = {}
local finishedMonsters = {}
local selectedCharmId = nil
local selectedRaceId = 0
local selectedMenu = 'major'
local charmBalance = 0
local goldBalance = 0
local resetAllCost = 0

local majorCharmIds = {
	[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
	[7] = true, [8] = true, [15] = true, [16] = true, [19] = true,
	[22] = true, [23] = true, [24] = true
}

local minorCharmIds = {
	[6] = true, [9] = true, [10] = true, [11] = true, [12] = true,
	[13] = true, [14] = true, [17] = true, [18] = true, [20] = true, [21] = true
}

local staticCharms = {
	[0] = { name = 'Wound', unlockPrice = 600 },
	[1] = { name = 'Enflame', unlockPrice = 600 },
	[2] = { name = 'Poison', unlockPrice = 600 },
	[3] = { name = 'Freeze', unlockPrice = 600 },
	[4] = { name = 'Zap', unlockPrice = 600 },
	[5] = { name = 'Curse', unlockPrice = 600 },
	[6] = { name = 'Cripple', unlockPrice = 500 },
	[7] = { name = 'Parry', unlockPrice = 700 },
	[8] = { name = 'Dodge', unlockPrice = 700 },
	[9] = { name = 'Adrenaline Burst', unlockPrice = 500 },
	[10] = { name = 'Numb', unlockPrice = 500 },
	[11] = { name = 'Cleanse', unlockPrice = 500 },
	[12] = { name = 'Bless', unlockPrice = 500 },
	[13] = { name = 'Scavenge', unlockPrice = 500 },
	[14] = { name = 'Gut', unlockPrice = 500 },
	[15] = { name = 'Low Blow', unlockPrice = 1200 },
	[16] = { name = 'Divine Wrath', unlockPrice = 1500 },
	[17] = { name = 'Vampiric Embrace', unlockPrice = 500 },
	[18] = { name = "Void's Call", unlockPrice = 500 },
	[19] = { name = 'Savage Blow', unlockPrice = 1200 },
	[20] = { name = 'Fatal Hold', unlockPrice = 500 },
	[21] = { name = 'Void Inversion', unlockPrice = 500 },
	[22] = { name = 'Carnage', unlockPrice = 2000 },
	[23] = { name = 'Overpower', unlockPrice = 2000 },
	[24] = { name = 'Overflux', unlockPrice = 2000 }
}

local function requestBestiaryInfo()
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return
	end

	local msg = OutputMessage.create()
	msg:addU8(CyclopediaOpcode.Info)
	protocolGame:send(msg)
end

local function parseSendBuyCharmRune(runeId, action, raceId)
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return
	end

	local msg = OutputMessage.create()
	msg:addU8(CyclopediaOpcode.Charm)
	msg:addU8(runeId)
	msg:addU8(action)
	msg:addU16(raceId or 0)
	protocolGame:send(msg)
end

local function readCharmCreatureOutfit(msg)
	if readCyclopediaCreatureOutfit then
		return readCyclopediaCreatureOutfit(msg)
	end

	return {
		name = msg:getString(),
		type = msg:getU16(),
		head = msg:getU8(),
		body = msg:getU8(),
		legs = msg:getU8(),
		feet = msg:getU8(),
		addons = msg:getU8()
	}
end

local function firstToUpper(text)
	if not text or text == '' then
		return ''
	end
	return text:gsub('^%l', string.upper)
end

local function isCharmsView()
	return modules.game_cyclopedia and modules.game_cyclopedia.getCurrentType and modules.game_cyclopedia.getCurrentType() == 'charms'
end

local function registerCharmsProtocol()
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
end

local function getCharmById(id)
	for _, charm in ipairs(bestiaryCharmCache) do
		if charm.id == id then
			return charm
		end
	end

	local fallback = staticCharms[id]
	if not fallback then
		return nil
	end

	return {
		id = id,
		name = fallback.name,
		description = fallback.description or '',
		unlockPrice = fallback.unlockPrice or 0,
		activated = 0,
		asignedStatus = false,
		raceId = 0,
		removeRuneCost = 0
	}
end

local function formatNumber(value)
	local number = math.floor(tonumber(value) or 0)
	local sign = number < 0 and '-' or ''
	local text = tostring(math.abs(number))
	local left, middle, right = text:match('^([^%d]*%d)(%d*)(.-)$')

	if not left then
		return tostring(number)
	end

	return sign .. left .. middle:reverse():gsub('(%d%d%d)', '%1,'):reverse() .. right
end

local function setEnabled(widget, enabled)
	if not widget then
		return
	end

	if enabled then
		widget:enable()
		widget:setOpacity(1)
	else
		widget:disable()
		widget:setOpacity(0.45)
	end
end

local function isLeftClick(mouseButton)
	return not mouseButton or mouseButton == MouseLeftButton
end

local function confirmAction(text, callback)
	local confirmWindow
	local yesCallback = function()
		confirmWindow:ok()
		callback()
	end
	local noCallback = function()
		confirmWindow:cancel()
	end

	confirmWindow = displayGeneralBox(tr('Charm'), text, {
		{ text = tr('Yes'), callback = yesCallback },
		{ text = tr('No'), callback = noCallback }
	}, yesCallback, noCallback)
end

local function refreshAfterAction()
	if updateBestiaryCharmSlots then
		updateBestiaryCharmSlots()
	end

	requestBestiaryInfo()
	scheduleEvent(function()
		requestBestiaryInfo()
	end, 250)
end

local function getCharmIdsForCurrentMenu()
	local source = selectedMenu == 'minor' and minorCharmIds or majorCharmIds
	local ids = {}

	for id in pairs(source) do
		ids[#ids + 1] = id
	end

	table.sort(ids)
	return ids
end

local function getAssignedCount()
	local count = 0
	for _, charm in ipairs(bestiaryCharmCache) do
		if charm.activated > 0 and charm.asignedStatus then
			count = count + 1
		end
	end
	return count
end

local function updateBalances()
	if widgets.charmAmount then
		widgets.charmAmount:setText(formatNumber(charmBalance))
	end
	if widgets.goldPoints then
		widgets.goldPoints:setText(formatNumber(goldBalance))
	end
	if widgets.goldResetAmount then
		widgets.goldResetAmount:setText(formatNumber(resetAllCost))
	end
	if widgets.resetText then
		local remaining = math.max(0, MAX_ASSIGNED_CHARMS - getAssignedCount())
		widgets.resetText:setText(tr('You can assign\n%d more Charms', remaining))
	end
end

local function updateCharmCostIcon()
	if not widgets.charmCostIcon then
		return
	end

	if selectedMenu == 'minor' then
		widgets.charmCostIcon:setImageSource('/images/game/cyclopedia/ui/minor-charm-echoes')
	else
		widgets.charmCostIcon:setImageSource('/images/game/cyclopedia/ui/charm-points')
	end
end

local function updateCreaturePreview(outfit)
	if not widgets.creature then
		return
	end

	if outfit then
		widgets.creature:show()
		widgets.creature:setOutfit(outfit)
	else
		widgets.creature:hide()
	end
end

local function refreshSelectButton()
	local charm = selectedCharmId and getCharmById(selectedCharmId) or nil
	local canSelect = charm and charm.activated > 0 and not charm.asignedStatus and selectedRaceId > 0
	setEnabled(widgets.selectCreatureButton, canSelect)
end

local function refreshMonsterList()
	if not widgets.monsterList then
		return
	end

	widgets.monsterList:destroyChildren()
	selectedRaceId = 0
	updateCreaturePreview(nil)

	local searchText = ''
	if widgets.searchTextCharm then
		searchText = widgets.searchTextCharm:getText():lower()
	end

	table.sort(finishedMonsters, function(a, b)
		return (a.name or '') < (b.name or '')
	end)

	for index, monster in ipairs(finishedMonsters) do
		local name = firstToUpper(monster.name or '')
		if searchText == '' or name:lower():find(searchText, 1, true) then
			local row = g_ui.createWidget('CharmListLabel', widgets.monsterList)
			row:setId('monsterWidget' .. index)
			row:setText(name)
			row.raceId = monster.raceId
			row.onMouseRelease = function(self, mousePosition, mouseButton)
				if not isLeftClick(mouseButton) then
					return false
				end

				selectedRaceId = self.raceId or 0
				self:focus()
				updateCreaturePreview(protoData[selectedRaceId])
				refreshSelectButton()
				return true
			end
		end
	end

	refreshSelectButton()
end

local function setupCharmDetails(charm)
	if not charm then
		return
	end

	selectedCharmId = charm.id
	selectedRaceId = 0
	local unlocked = charm.activated > 0
	local assigned = unlocked and charm.asignedStatus

	if widgets.title then
		widgets.title:setText(charm.name or tr('Charm Information'))
	end
	if widgets.informationText then
		local description = charm.description
		if not description or description == '' then
			description = tr('No description available for this charm.')
		end
		widgets.informationText:setText(description)
	end
	if widgets.charmImage then
		widgets.charmImage:setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-' .. charm.id)
	end
	if widgets.level then
		widgets.level:setVisible(unlocked)
	end
	if widgets.charmInfoAmount then
		widgets.charmInfoAmount:setText(formatNumber(charm.unlockPrice))
		widgets.charmInfoAmount:setColor(charm.unlockPrice <= charmBalance and '#c0c0c0' or '#d33c3c')
	end
	if widgets.goldClearAmount then
		widgets.goldClearAmount:setText(formatNumber(charm.removeRuneCost))
	end

	if widgets.unlockButton then
		if unlocked then
			widgets.unlockButton:setText(tr('Unlock'))
			setEnabled(widgets.unlockButton, false)
		else
			widgets.unlockButton:setText(tr('Unlock'))
			setEnabled(widgets.unlockButton, charm.unlockPrice <= charmBalance)
			widgets.unlockButton.onClick = function()
				confirmAction(tr('Do you want to unlock the Charm %s? This will cost you %d Charm Points?', charm.name, charm.unlockPrice), function()
					parseSendBuyCharmRune(charm.id, 0, nil)
					refreshAfterAction()
				end)
			end
		end
	end

	if widgets.clearButton then
		setEnabled(widgets.clearButton, assigned)
		widgets.clearButton.onClick = function()
			if not assigned then
				return
			end
			confirmAction(tr('Do you want to remove the Charm %s from this creature? This will cost you %d gold pieces.', charm.name, charm.removeRuneCost), function()
				parseSendBuyCharmRune(charm.id, 2, charm.raceId)
				refreshAfterAction()
			end)
		end
	end

	if assigned and protoData[charm.raceId] then
		updateCreaturePreview(protoData[charm.raceId])
	else
		updateCreaturePreview(nil)
	end

	refreshMonsterList()
	refreshSelectButton()
end

local function refreshCharmGrid()
	if not charmsWindow or not widgets.charmListPanel then
		return
	end

	widgets.charmListPanel:destroyChildren()

	local firstWidget = nil
	for _, id in ipairs(getCharmIdsForCurrentMenu()) do
		local charm = getCharmById(id)
		if charm then
			local row = g_ui.createWidget('CharmWidget', widgets.charmListPanel)
			row:setId('charmWidget' .. id)
			row:setText(charm.name)
			row.charm = charm

			local image = row:recursiveGetChildById('charmImage')
			if image then
				image:setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-' .. id)
			end

			local opacityItem = row:recursiveGetChildById('opacityItem')
			if opacityItem then
				opacityItem:setVisible(charm.activated == 0)
			end

			local level = row:recursiveGetChildById('level')
			if level then
				level:setVisible(charm.activated > 0)
			end

			local creature = row:recursiveGetChildById('creature')
			if creature and charm.asignedStatus and protoData[charm.raceId] then
				creature:setOutfit(protoData[charm.raceId])
				creature:show()
			elseif creature then
				creature:hide()
			end

			row.onMouseRelease = function(self, mousePosition, mouseButton)
				if not isLeftClick(mouseButton) then
					return false
				end

				self:focus()
				setupCharmDetails(self.charm)
				return true
			end

			if selectedCharmId == id then
				firstWidget = row
			elseif not firstWidget then
				firstWidget = row
			end
		end
	end

	if firstWidget then
		firstWidget:focus()
		setupCharmDetails(firstWidget.charm)
	end
end

local function loadCharmMenu(menu)
	selectedMenu = menu
	selectedCharmId = nil

	if widgets.majorMenu then
		widgets.majorMenu:setOn(menu == 'major')
	end
	if widgets.minorMenu then
		widgets.minorMenu:setOn(menu == 'minor')
	end

	updateCharmCostIcon()
	refreshCharmGrid()
end

function sendBestiaryCharmsData(msg)
	charmBalance = msg:getU32()
	goldBalance = msg:getU64()

	if BestiaryChangeAmount then
		BestiaryChangeAmount(charmBalance, goldBalance)
	end

	local charmsList = {}
	local charms = msg:getU8()
	for i = 1, charms do
		local runeId = msg:getU8()
		local runeName = msg:getString()
		local runeDescription = msg:getString()
		msg:getU8()
		local unlockPoints = msg:getU16()
		local activatedStatus = msg:getU8()
		local asignedStatus = false
		local raceId = 0
		local removeRuneCost = 0

		if activatedStatus > 0 then
			local asigned = msg:getU8()
			if asigned > 0 then
				asignedStatus = true
				raceId = msg:getU16()
				removeRuneCost = msg:getU32()
				protoData[raceId] = readCharmCreatureOutfit(msg)
			end
		else
			msg:getU8()
		end

		table.insert(charmsList, {
			id = runeId,
			name = runeName,
			description = runeDescription,
			unlockPrice = unlockPoints,
			activated = activatedStatus,
			asignedStatus = asignedStatus,
			raceId = raceId,
			removeRuneCost = removeRuneCost
		})
	end

	bestiaryCharmCache = charmsList
	msg:getU8()
	resetAllCost = 0

	finishedMonsters = {}
	local finishedMonstersSize = msg:getU16()
	for i = 1, finishedMonstersSize do
		local raceId = msg:getU16()
		local outfit = readCharmCreatureOutfit(msg)
		outfit.name = outfit.name or ''
		protoData[raceId] = outfit
		table.insert(finishedMonsters, {
			raceId = raceId,
			name = outfit.name,
			outfit = outfit
		})
	end

	if updateBestiaryCharmSlots then
		updateBestiaryCharmSlots()
	end

	if isCharmsView() and charmsWindow then
		updateBalances()
		refreshCharmGrid()
	end
end

function getBestiaryAssignedCharms(raceId)
	local assignedCharms = {}
	if not raceId or raceId <= 0 then
		return assignedCharms
	end

	for _, charm in ipairs(bestiaryCharmCache) do
		if charm.activated > 0 and charm.asignedStatus and charm.raceId == raceId then
			assignedCharms[#assignedCharms + 1] = charm
		end
	end

	table.sort(assignedCharms, function(a, b)
		return a.id < b.id
	end)
	return assignedCharms
end

function getBestiaryAssignableCharms()
	local assignableCharms = {}
	for _, charm in ipairs(bestiaryCharmCache) do
		if charm.activated > 0 and not charm.asignedStatus then
			assignableCharms[#assignableCharms + 1] = charm
		end
	end

	table.sort(assignableCharms, function(a, b)
		return (a.name or '') < (b.name or '')
	end)
	return assignableCharms
end

function sendBestiaryCharmAssign(runeId, raceId)
	parseSendBuyCharmRune(runeId, 1, raceId)
	refreshAfterAction()
end

function sendBestiaryCharmRemove(runeId, raceId)
	parseSendBuyCharmRune(runeId, 2, raceId)
	refreshAfterAction()
end

function requestBestiaryCharmRefresh()
	requestBestiaryInfo()
end

function initCharms()
	if charmsWindow then
		charmsWindow:show()
		updateBalances()
		refreshCharmGrid()
		return
	end

	charmsWindow = g_ui.loadUI('styles/charms', getContentContainer())
	charmsWindow:show()

	widgets.title = charmsWindow:recursiveGetChildById('title')
	widgets.informationText = charmsWindow:recursiveGetChildById('informationText')
	local charmPanel = charmsWindow:recursiveGetChildById('charmPanel')
	widgets.charmImage = charmPanel and charmPanel:recursiveGetChildById('charmImage')
	local charmBgSlot = charmsWindow:recursiveGetChildById('charmBgSlot')
	widgets.charmCostIcon = charmBgSlot and charmBgSlot:recursiveGetChildById('imagetType')
	widgets.level = charmsWindow:recursiveGetChildById('informationPanel'):recursiveGetChildById('level')
	widgets.unlockButton = charmsWindow:recursiveGetChildById('unlockButton')
	widgets.charmInfoAmount = charmsWindow:recursiveGetChildById('charmInfoAmount')
	widgets.clearButton = charmsWindow:recursiveGetChildById('clearButton')
	widgets.goldClearAmount = charmsWindow:recursiveGetChildById('goldClearAmount')
	widgets.searchTextCharm = charmsWindow:recursiveGetChildById('searchTextCharm')
	widgets.clearSlotButton = charmsWindow:recursiveGetChildById('clearSlotButton')
	widgets.monsterList = charmsWindow:recursiveGetChildById('monsterList')
	widgets.selectCreatureButton = charmsWindow:recursiveGetChildById('selectCreatureButton')
	local creatureWidget = charmsWindow:recursiveGetChildById('creatureWidget')
	widgets.creature = creatureWidget and creatureWidget:recursiveGetChildById('creature')
	widgets.resetText = charmsWindow:recursiveGetChildById('resetText')
	widgets.resetCharmsButton = charmsWindow:recursiveGetChildById('resetCharmsButton')
	widgets.goldResetAmount = charmsWindow:recursiveGetChildById('goldResetAmount')
	widgets.majorMenu = charmsWindow:recursiveGetChildById('majorMenu')
	widgets.minorMenu = charmsWindow:recursiveGetChildById('minorMenu')
	widgets.charmListPanel = charmsWindow:recursiveGetChildById('charmListPanel')
	widgets.goldPoints = charmsWindow:recursiveGetChildById('goldPoints')
	widgets.charmAmount = charmsWindow:recursiveGetChildById('charmAmount')
	widgets.backButton = charmsWindow:recursiveGetChildById('backButton')
	widgets.openStore = charmsWindow:recursiveGetChildById('openStore')

	if widgets.majorMenu then
		widgets.majorMenu.onClick = function()
			loadCharmMenu('major')
		end
	end
	if widgets.minorMenu then
		widgets.minorMenu.onClick = function()
			loadCharmMenu('minor')
		end
	end
	if widgets.searchTextCharm then
		widgets.searchTextCharm.onTextChange = function()
			refreshMonsterList()
		end
	end
	if widgets.clearSlotButton then
		widgets.clearSlotButton.onClick = function()
			widgets.searchTextCharm:setText('')
			refreshMonsterList()
		end
	end
	if widgets.selectCreatureButton then
		widgets.selectCreatureButton.onClick = function()
			local charm = selectedCharmId and getCharmById(selectedCharmId) or nil
			if not charm or selectedRaceId <= 0 then
				return
			end
			confirmAction(tr('Do you want to use the Charm %s for this creature?', charm.name), function()
				parseSendBuyCharmRune(charm.id, 1, selectedRaceId)
				refreshAfterAction()
			end)
		end
	end
	if widgets.resetCharmsButton then
		setEnabled(widgets.resetCharmsButton, false)
	end
	if widgets.openStore then
		setEnabled(widgets.openStore, false)
	end
	if widgets.backButton then
		widgets.backButton.onClick = function()
			if toggleWindow then
				toggleWindow('bestiary')
			end
		end
	end

	connect(g_game, {
		onEnterGame = registerCharmsProtocol,
		onPendingGame = registerCharmsProtocol
	})

	registerCharmsProtocol()
	updateBalances()
	loadCharmMenu('major')
	requestBestiaryInfo()
end

function resetCharmsData()
	if widgets.charmListPanel then
		widgets.charmListPanel:destroyChildren()
	end
	if widgets.monsterList then
		widgets.monsterList:destroyChildren()
	end
	requestBestiaryInfo()
end
