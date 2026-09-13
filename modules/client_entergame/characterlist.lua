-- chunkname: @/client_entergame/characterlist.lua

CharacterList = {}

local charactersWindow, loadBox, characterList, errorBox, waitingWindow, updateWaitEvent, resendWaitEvent, loginEvent, autoReconnectButton
local restoreCharacterListEvent
local WORLD_TYPE_NAMES = {
	[0] = "Open PvP",
	"Optional PvP",
	"Hardcore PvP",
	"Retro Open PvP",
	"Retro Hardcore PvP"
}

local function getWorldTypeName(worldTypeId)
	local name = WORLD_TYPE_NAMES[worldTypeId]

	if not name then
		return nil
	end

	return tr(name)
end

local autoReconnectEvent
local lastLogout = 0
local manualLogoutPending = false
local autoReconnectAttempt = false
local reconnectAttemptCount = 0
local suppressLogoutTimestamp = false
local lastScheduleReconnectAt = 0
local RECONNECT_SCHEDULE_DEBOUNCE_MS = 500
local levelSortOrder = "desc"
local AUTO_RECONNECT_MAX_TRIES = 120
local AUTO_RECONNECT_FORCE_LOGOUT_AFTER = 20
local PINNED_CHARACTERS_SETTING = "pinned-characters"
local LEGACY_PINNED_CHARACTERS_SETTING = "characterlist-pinned-characters"
local HIDDEN_CHARACTERS_SETTING = "hidden-characters"
local PIN_CLIP_OUTLINE = "0 0 12 12"
local PIN_CLIP_ACTIVE = "0 12 12 12"
local pendingFocusCharacterKey, pinnedCharactersData, hiddenCharactersData, currentMainCharacterKey

local function makeCharacterKey(characterInfo)
	return string.format("%s|%s|%s", G.account or "", characterInfo.name or "", characterInfo.worldName or "")
end

local savePinnedCharacters

local function migrateLegacyPinKey(key)
	if not key or key == "" then
		return nil
	end

	local account = G.account or ""
	if account == "" then
		return key
	end

	local accountPrefix = account .. "|"
	if key:sub(1, #accountPrefix) == accountPrefix then
		return key
	end

	return string.format("%s|%s", account, key)
end

local function appendPinnedKey(data, key)
	local migratedKey = migrateLegacyPinKey(key)
	if not migratedKey or data.map[migratedKey] then
		return
	end

	data.map[migratedKey] = true
	table.insert(data.order, migratedKey)
	data.orderIndex[migratedKey] = #data.order
end

local function loadLegacyPinnedCharacters(data)
	local rawPinnedCharacters = g_settings.getNode(LEGACY_PINNED_CHARACTERS_SETTING)
	if type(rawPinnedCharacters) ~= "table" then
		return false
	end

	local migrated = false

	for key, value in pairs(rawPinnedCharacters) do
		local pinKey

		if type(key) == "number" then
			if type(value) == "string" and value ~= "" then
				pinKey = value
			end
		elseif type(key) == "string" then
			local pinned = false

			if value == true then
				pinned = true
			elseif type(value) == "number" and value ~= 0 then
				pinned = true
			elseif type(value) == "string" then
				local normalizedValue = string.lower(value)
				pinned = normalizedValue == "true" or normalizedValue == "1"
			end

			if pinned then
				pinKey = key
			end
		end

		if pinKey then
			appendPinnedKey(data, pinKey)
			migrated = true
		end
	end

	if migrated then
		g_settings.setNode(LEGACY_PINNED_CHARACTERS_SETTING, nil)
	end

	return migrated
end

local function loadPinnedCharacters()
	local data = {
		map = {},
		order = {},
		orderIndex = {}
	}
	local keys = g_settings.getList(PINNED_CHARACTERS_SETTING)

	if type(keys) == "table" and #keys > 0 then
		for index, key in ipairs(keys) do
			if type(key) == "string" and key ~= "" then
				data.map[key] = true

				table.insert(data.order, key)

				data.orderIndex[key] = index
			end
		end

		return data
	end

	local raw = g_settings.get(PINNED_CHARACTERS_SETTING)

	if not raw or raw == "" then
		return data
	end

	local ok, decoded = pcall(function()
		return json.decode(raw)
	end)

	if not ok or type(decoded) ~= "table" then
		return data
	end

	local migratedOrder = {}

	for index, key in ipairs(decoded) do
		if type(key) == "string" and key ~= "" then
			data.map[key] = true

			table.insert(data.order, key)

			data.orderIndex[key] = index

			table.insert(migratedOrder, key)
		end
	end

	if #migratedOrder > 0 then
		savePinnedCharacters(migratedOrder)

		return data
	end

	if loadLegacyPinnedCharacters(data) and #data.order > 0 then
		savePinnedCharacters(data.order)
	end

	return data
end

local saveSettingsEvent

local function scheduleSaveSettings()
	if saveSettingsEvent then
		removeEvent(saveSettingsEvent)
	end

	saveSettingsEvent = scheduleEvent(function()
		saveSettingsEvent = nil
		g_settings.save()
	end, 500)
end

local function flushSaveSettings()
	if saveSettingsEvent then
		removeEvent(saveSettingsEvent)
		saveSettingsEvent = nil
		g_settings.save()
	end
end

savePinnedCharacters = function(orderArray)
	g_settings.setList(PINNED_CHARACTERS_SETTING, orderArray or {})
	scheduleSaveSettings()
end

local function loadHiddenCharacters()
	local map = {}
	local raw = g_settings.getList(HIDDEN_CHARACTERS_SETTING)

	if type(raw) == "table" and #raw > 0 then
		for _, key in ipairs(raw) do
			if type(key) == "string" and key ~= "" then
				map[key] = true
			end
		end
		return map
	end

	local rawStr = g_settings.get(HIDDEN_CHARACTERS_SETTING)
	if type(rawStr) == "string" and rawStr ~= "" then
		for key in rawStr:gmatch("([^;]+)") do
			map[key] = true
		end
	end

	return map
end

local function saveHiddenCharacters(map)
	local list = {}
	for key, val in pairs(map) do
		if val then
			table.insert(list, key)
		end
	end
	g_settings.setList(HIDDEN_CHARACTERS_SETTING, list)
	scheduleSaveSettings()
end

local function isCharacterHidden(key, hiddenData)
	hiddenData = hiddenData or hiddenCharactersData

	return hiddenData and hiddenData[key] == true
end

local function isCharacterPinned(key, pinnedData)
	pinnedData = pinnedData or pinnedCharactersData

	if not pinnedData or not pinnedData.map then
		return false
	end

	if pinnedData.map[key] then
		return true
	end

	local parts = {}
	for part in string.gmatch(key or "", "([^|]+)") do
		table.insert(parts, part)
	end

	if #parts >= 3 then
		local legacyWorldKey = string.format("%s|%s", parts[2], parts[3])

		if pinnedData.map[legacyWorldKey] then
			return true
		end

		if pinnedData.map[parts[2]] then
			return true
		end
	end

	return false
end

local function isFirstPinnedCharacter(key)
	return currentMainCharacterKey ~= nil and currentMainCharacterKey == key
end

local function getPinSortIndex(key, pinnedData)
	pinnedData = pinnedData or pinnedCharactersData

	local index = pinnedData and pinnedData.orderIndex[key]

	if index then
		return index
	end

	return math.huge
end

local function updateDailyRewardWidget(widget, dailyRewardState)
	if not widget then
		return
	end

	local statusDailyReward = widget:recursiveGetChildById("statusDailyReward")
	if not statusDailyReward then
		return
	end

	statusDailyReward:setVisible(true)

	if dailyRewardState == 0 then
		statusDailyReward:setImageSource("/images/game/entergame/dailyreward_collected")
		statusDailyReward:setTooltip(tr("Either you have already collected your daily reward or you have not reached main continent yet."))
	elseif dailyRewardState == 1 or dailyRewardState == nil then
		statusDailyReward:setImageSource("/images/game/entergame/dailyreward_notcollected")
		statusDailyReward:setTooltip(tr("Your daily reward has not been collected, yet."))
	else
		statusDailyReward:setImageSource("/images/game/entergame/dailyreward_deactivated")
		statusDailyReward:setTooltip(tr("Daily rewards are deactivated on this gameworld."))
	end
end

local function updateCharacterActionWidgets(widget, isFocused, pinnedData, hiddenData)
	if not widget then
		return
	end

	local pin = widget:getChildById("characterPin")
	local hideBtn = widget:getChildById("characterHideButton")
	local main = widget:getChildById("mainCharacter")
	local statusHidden = widget:recursiveGetChildById("statusHidden")
	local key = widget.characterKey
	local pinned = isCharacterPinned(key, pinnedData)
	local hidden = isCharacterHidden(key, hiddenData) or (widget.characterInfo and widget.characterInfo.hidden == true)

	if pin then
		if pinned then
			pin:setVisible(true)
			pin:setImageClip(PIN_CLIP_ACTIVE)
			pin:setTooltip(tr("Unpin this character"))
		elseif isFocused then
			pin:setVisible(true)
			pin:setImageClip(PIN_CLIP_OUTLINE)
			pin:setTooltip(tr("Pin this character to keep it at the top of the list"))
		else
			pin:setVisible(false)
		end
	end

	if hideBtn then
		if hidden then
			hideBtn:setVisible(true)
			hideBtn:setImageClip("2 20 14 14")
			hideBtn:setTooltip(tr("Show Character"))
		elseif isFocused then
			hideBtn:setVisible(true)
			hideBtn:setImageClip("2 2 14 14")
			hideBtn:setTooltip(tr("Hide Character"))
		else
			hideBtn:setVisible(false)
		end
	end

	if statusHidden then
		if hidden then
			statusHidden:setImageSource("/images/game/entergame/hidden")
			statusHidden:setTooltip(tr("Hidden Character"))
			statusHidden:setVisible(true)
		else
			statusHidden:setImageSource("")
			statusHidden:setVisible(false)
		end
	end

	if main then
		local isFirstPinned = isFirstPinnedCharacter(key)
		local isMain = isFirstPinned or (not currentMainCharacterKey and widget.characterInfo and widget.characterInfo.main == true)
		if isMain then
			main:setImageSource("/images/game/entergame/maincharacter")
			main:setTooltip(tr("Main Character"))
			main:setVisible(true)
		else
			main:setImageSource("")
			main:setVisible(false)
		end
	end
end

local function refreshCharacterActionWidgets()
	if not characterList then
		return
	end

	local focused = characterList:getFocusedChild()

	for _, widget in ipairs(characterList:getChildren()) do
		updateCharacterActionWidgets(widget, widget == focused, pinnedCharactersData, hiddenCharactersData)
	end
end

local function compareCharacterInfo(a, b, pinnedData)
	local aKey = makeCharacterKey(a)
	local bKey = makeCharacterKey(b)
	local aPinIndex = getPinSortIndex(aKey, pinnedData)
	local bPinIndex = getPinSortIndex(bKey, pinnedData)

	if aPinIndex ~= bPinIndex then
		return aPinIndex < bPinIndex
	end

	local aLevel = tonumber(a.level) or 0
	local bLevel = tonumber(b.level) or 0

	if aLevel ~= bLevel then
		if levelSortOrder == "asc" then
			return aLevel < bLevel
		else
			return aLevel > bLevel
		end
	end

	local aName = (a.name or ""):lower()
	local bName = (b.name or ""):lower()

	if aName ~= bName then
		return aName < bName
	end

	return (a.__originalIndex or 0) < (b.__originalIndex or 0)
end

local function sortCharacters(characters, pinnedData)
	local sorted = {}

	for i, characterInfo in ipairs(characters) do
		characterInfo.__originalIndex = characterInfo.__originalIndex or i

		table.insert(sorted, characterInfo)
	end

	table.sort(sorted, function(a, b)
		return compareCharacterInfo(a, b, pinnedData)
	end)

	return sorted
end

local CHARACTER_LIST_HEADER_COLOR = "#c0c0c0"
local CHARACTER_LIST_HEADER_HIGHLIGHT = "#ffffff"

local function setCharacterTableHeaderLabelColor(label, hovered)
	if label and not label:isDestroyed() then
		label:setColor(hovered and CHARACTER_LIST_HEADER_HIGHLIGHT or CHARACTER_LIST_HEADER_COLOR)
	end
end

local function bindCharacterTableHeaderHighlight(cell, label)
	if not cell or not label then
		return
	end

	local originalHover = cell.onHoverChange
	cell.onHoverChange = function(widget, hovered)
		if originalHover then
			originalHover(widget, hovered)
		end
		setCharacterTableHeaderLabelColor(label, hovered)
	end
end

local function setupCharacterTableHeaderHighlights()
	if not charactersWindow then
		return
	end

	local headers = {
		{ cell = "characterHeaderCell", label = "characterHeaderLabel" },
		{ cell = "statusHeaderCell", label = "statusHeaderLabel" },
		{ cell = "levelHeaderCell", label = "levelHeaderLabel" },
		{ cell = "vocationHeaderCell", label = "vocationHeaderLabel" },
		{ cell = "worldHeaderCell", label = "worldHeaderLabel" }
	}

	for _, entry in ipairs(headers) do
		local cell = charactersWindow:recursiveGetChildById(entry.cell)
		local label = charactersWindow:recursiveGetChildById(entry.label)
		bindCharacterTableHeaderHighlight(cell, label)
	end

	local sortButton = charactersWindow:recursiveGetChildById("characterSortButton")
	local characterHeaderLabel = charactersWindow:recursiveGetChildById("characterHeaderLabel")
	if sortButton and characterHeaderLabel then
		local originalSortHover = sortButton.onHoverChange
		sortButton.onHoverChange = function(widget, hovered)
			if originalSortHover then
				originalSortHover(widget, hovered)
			end
			setCharacterTableHeaderLabelColor(characterHeaderLabel, hovered)
		end
	end
end

local function updateSortButton()
	if not charactersWindow then
		return
	end

	local sortButton = charactersWindow:recursiveGetChildById("characterSortButton")

	if not sortButton then
		return
	end

	if levelSortOrder == "asc" then
		sortButton:setImageClip("0 0 7 4")
		sortButton:setTooltip(tr("Sort by level: Lowest to Highest"))
	else
		sortButton:setImageClip("0 4 7 4")
		sortButton:setTooltip(tr("Sort by level: Highest to Lowest"))
	end
end

local function reorderCharacterListWidgets()
	if not characterList then
		return
	end

	local widgets = characterList:getChildren()
	if #widgets < 2 then
		updateSortButton()
		return
	end

	pinnedCharactersData = pinnedCharactersData or loadPinnedCharacters()

	table.sort(widgets, function(a, b)
		local aInfo = a.characterInfo
		local bInfo = b.characterInfo

		if not aInfo or not bInfo then
			return false
		end

		return compareCharacterInfo(aInfo, bInfo, pinnedCharactersData)
	end)

	characterList:reorderChildren(widgets)
	updateSortButton()

	if characterList.updateScrollBars then
		characterList:updateScrollBars()
	end
end

local function removeAutoReconnectEvent()
	if autoReconnectEvent then
		removeEvent(autoReconnectEvent)

		autoReconnectEvent = nil
	end
end

local function updateAutoReconnectButton()
	if not autoReconnectButton then
		return
	end

	local autoReconnect = g_settings.getBoolean("autoReconnect", false)

	autoReconnectButton:setOn(autoReconnect)

	local reconnectStatus = autoReconnect and tr("On") or tr("Off")

	autoReconnectButton:setText(tr("Auto reconnect: %s", reconnectStatus))
end

local function cancelRestoreCharacterListEvent()
	if restoreCharacterListEvent then
		removeEvent(restoreCharacterListEvent)

		restoreCharacterListEvent = nil
	end
end

local function destroyTrackedErrorBox()
	local box = errorBox

	errorBox = nil

	if not isWidgetAlive(box) then
		return
	end

	if g_modalManager and g_modalManager.hide then
		g_modalManager.hide(box)
	end

	box:destroy()
end

local function clearStaleErrorBox()
	if not errorBox then
		return
	end

	if isWidgetAlive(errorBox) and errorBox:isVisible() then
		return
	end

	destroyTrackedErrorBox()
end

local function trackErrorBox(box)
	destroyTrackedErrorBox()

	errorBox = box

	connect(box, {
		onDestroy = function(destroyedBox)
			if errorBox == destroyedBox then
				errorBox = nil
			end
		end
	})

	return box
end

local function resetReconnectBackoff()
	reconnectAttemptCount = 0
	autoReconnectAttempt = false
end

local function getReconnectDelay()
	if reconnectAttemptCount <= 3 then
		return 2500
	elseif reconnectAttemptCount <= 6 then
		return 5000
	elseif reconnectAttemptCount <= 10 then
		return 10000
	end

	return 15000
end

local function tryLogin(charInfo, tries)
	tries = tries or 1

	local maxTries = autoReconnectAttempt and AUTO_RECONNECT_MAX_TRIES or 50

	if maxTries < tries then
		if autoReconnectAttempt and g_game.isOnline() then
			g_logger.warning("[reconnect] still online after force logout, retrying later")

			autoReconnectAttempt = false

			scheduleAutoReconnect()
		end

		return
	end

	if g_game.isOnline() then
		if autoReconnectAttempt and tries > AUTO_RECONNECT_FORCE_LOGOUT_AFTER then
			g_game.forceLogout()
		elseif tries == 1 then
			g_game.safeLogout()
		end

		if loginEvent then
			removeEvent(loginEvent)

			loginEvent = nil
		end

		loginEvent = scheduleEvent(function()
			tryLogin(charInfo, tries + 1)
		end, 100)

		return
	end

	CharacterList.hide()

	loadBox = displayCancelBox(tr("Connecting"), tr("Connecting to the game world. Please wait."))

	connect(loadBox, {
		onCancel = function()
			loadBox = nil

			g_game.cancelLogin()
			resetReconnectBackoff()
			CharacterList.show()
		end
	})

	g_game.loginWorld(G.account, G.password, charInfo.worldName, charInfo.worldHost, charInfo.worldPort, charInfo.characterName, G.authenticatorToken, G.sessionKey)

	if g_game.isOnline() then
		CharacterList.destroyLoadBox()
	end

	g_settings.set("last-used-character", charInfo.characterName)
	g_settings.set("last-used-world", charInfo.worldName)
	removeAutoReconnectEvent()
end

local function updateWait(timeStart, timeEnd)
	if waitingWindow then
		local time = g_clock.seconds()

		if time <= timeEnd then
			local percent = (time - timeStart) / (timeEnd - timeStart) * 100
			local timeStr = string.format("%.0f", timeEnd - time)
			local progressBar = waitingWindow:getChildById("progressBar")

			progressBar:setPercent(percent)

			local label = waitingWindow:getChildById("timeLabel")

			label:setText(tr("Trying to reconnect in %s seconds.", timeStr))

			updateWaitEvent = scheduleEvent(function()
				updateWait(timeStart, timeEnd)
			end, 1000)

			return true
		end
	end

	if updateWaitEvent then
		updateWaitEvent:cancel()

		updateWaitEvent = nil
	end
end

local function resendWait()
	if waitingWindow then
		waitingWindow:destroy()

		waitingWindow = nil

		if updateWaitEvent then
			updateWaitEvent:cancel()

			updateWaitEvent = nil
		end

		if charactersWindow then
			local selected = characterList:getFocusedChild()

			if selected then
				local charInfo = {
					worldHost = selected.worldHost,
					worldPort = selected.worldPort,
					worldName = selected.worldName,
					characterName = selected.characterName,
					characterLevel = selected.characterLevel,
					main = selected.main,
					dailyreward = selected.dailyreward,
					hidden = selected.hidden,
					outfitid = selected.outfitid,
					headcolor = selected.headcolor,
					torsocolor = selected.torsocolor,
					legscolor = selected.legscolor,
					detailcolor = selected.detailcolor,
					addonsflags = selected.addonsflags,
					characterVocation = selected.characterVocation
				}

				tryLogin(charInfo)
			end
		end
	end
end

local function onLoginWait(message, time)
	CharacterList.destroyLoadBox()

	waitingWindow = g_ui.displayUI("waitinglist")

	local label = waitingWindow:getChildById("infoLabel")

	label:setText(message)

	updateWaitEvent = scheduleEvent(function()
		updateWait(g_clock.seconds(), g_clock.seconds() + time)
	end, 0)
	resendWaitEvent = scheduleEvent(resendWait, time * 1000)
end

function onGameLoginError(message, msgType)
	CharacterList.destroyLoadBox()

	msgType = tonumber(msgType) or 0

	local function onLoginErrorOk()
		errorBox = nil

		if msgType == 1 then
			CharacterList.hide(true)
		elseif msgType == 2 then
			if g_app and g_app.restart then
				g_app.restart()
			else
				CharacterList.hide(true)
			end
		else
			CharacterList.showAgain()
		end
	end

	local box = trackErrorBox(displayErrorBox(tr("Sorry"), message))

	box.onOk = onLoginErrorOk
end

function onGameSessionEnd(reason)
	CharacterList.destroyLoadBox()

	if g_game.isOnline() then
		suppressLogoutTimestamp = true

		g_game.forceLogout()

		suppressLogoutTimestamp = false

		return
	end

	CharacterList.showAgain()
end

function onGameConnectionError(message, code)
	CharacterList.destroyLoadBox()

	code = tonumber(code) or 0

	if g_settings.getBoolean("autoReconnect") and isRecoverableConnectionError(code) then
		if not g_game.isOnline() then
			CharacterList.showAgain()
		end
	else
		local text = translateNetworkError(code, g_game.getProtocolGame() and g_game.getProtocolGame():isConnecting(), message)
		local box = trackErrorBox(displayErrorBox(tr("Connection Error"), text))

		function box.onOk()
			errorBox = nil

			CharacterList.showAgain()
		end
	end
end

function onGameUpdateNeeded(signature)
	CharacterList.destroyLoadBox()

	local box = trackErrorBox(displayErrorBox(tr("Update needed"), tr("Enter with your account again to update your client.")))

	function box.onOk()
		errorBox = nil

		CharacterList.showAgain()
	end
end

local function onGameStart()
	CharacterList.destroyLoadBox()
	cancelRestoreCharacterListEvent()

	manualLogoutPending = false

	resetReconnectBackoff()
end

local function onGameEnd()
	CharacterList.destroyLoadBox()
	cancelRestoreCharacterListEvent()

	restoreCharacterListEvent = addEvent(function()
		restoreCharacterListEvent = nil

		if CharacterList and not g_game.isOnline() and not g_game.isLogging() then
			CharacterList.showAgain()
		end
	end)
end

function CharacterList.init()
	connect(g_game, {
		onLoginError = onGameLoginError
	})
	connect(g_game, {
		onSessionEnd = onGameSessionEnd
	})
	connect(g_game, {
		onUpdateNeeded = onGameUpdateNeeded
	})
	connect(g_game, {
		onConnectionError = onGameConnectionError
	})
	connect(g_game, {
		onGameStart = onGameStart
	})
	connect(g_game, {
		onLoginWait = onLoginWait
	})
	connect(g_game, {
		onGameEnd = onGameEnd
	})
	connect(g_game, {
		onLogout = onLogout
	})

	if G.characters then
		CharacterList.create(G.characters, G.characterAccount)
	end
end

function CharacterList.terminate()
	cancelRestoreCharacterListEvent()
	disconnect(g_game, {
		onLoginError = onGameLoginError
	})
	disconnect(g_game, {
		onSessionEnd = onGameSessionEnd
	})
	disconnect(g_game, {
		onUpdateNeeded = onGameUpdateNeeded
	})
	disconnect(g_game, {
		onConnectionError = onGameConnectionError
	})
	disconnect(g_game, {
		onGameStart = onGameStart
	})
	disconnect(g_game, {
		onLoginWait = onLoginWait
	})
	disconnect(g_game, {
		onGameEnd = onGameEnd
	})
	disconnect(g_game, {
		onLogout = onLogout
	})

	if charactersWindow then
		characterList = nil
		autoReconnectButton = nil

		charactersWindow:destroy()

		charactersWindow = nil
	end

	if loadBox then
		g_game.cancelLogin()
		loadBox:destroy()

		loadBox = nil
	end

	if waitingWindow then
		waitingWindow:destroy()

		waitingWindow = nil
	end

	if updateWaitEvent then
		removeEvent(updateWaitEvent)

		updateWaitEvent = nil
	end

	if resendWaitEvent then
		removeEvent(resendWaitEvent)

		resendWaitEvent = nil
	end

	if loginEvent then
		removeEvent(loginEvent)

		loginEvent = nil
	end

	destroyTrackedErrorBox()
	removeAutoReconnectEvent()
	resetReconnectBackoff()
	flushSaveSettings()

	manualLogoutPending = false

	destroyCreateAccount()

	CharacterList = nil
end

function CharacterList.create(characters, account, otui)
	otui = otui or "characterlist"

	if charactersWindow then
		if isWidgetAlive(charactersWindow) then
			charactersWindow:destroy()
		end

		charactersWindow = nil
		characterList = nil
		autoReconnectButton = nil
	end

	charactersWindow = g_ui.displayUI(otui)
	characterList = charactersWindow:recursiveGetChildById("characters")
	autoReconnectButton = charactersWindow:getChildById("autoReconnect")

	if autoReconnectButton then
		updateAutoReconnectButton()

		autoReconnectButton.onClick = function()
			g_settings.set("autoReconnect", not g_settings.getBoolean("autoReconnect", false))
			updateAutoReconnectButton()
		end
	end

	if not characterList then
		return
	end

	local sortButton = charactersWindow:recursiveGetChildById("characterSortButton")

	if sortButton then
		function sortButton.onClick()
			CharacterList.toggleSortOrder()

			return true
		end
	end

	local headerCell = charactersWindow:recursiveGetChildById("characterHeaderCell")
	if headerCell then
		function headerCell.onClick()
			CharacterList.toggleSortOrder()

			return true
		end
	end

	updateSortButton()
	setupCharacterTableHeaderHighlights()

	G.characters = characters
	G.characterAccount = account

	characterList:destroyChildren()

	local accountStatusLabel = charactersWindow:getChildById("accountStatusLabel")
	local accountStatusIcon = charactersWindow:getChildById("accountStatusIcon")
	local recoverySetupLabel = charactersWindow:getChildById("recoverySetupLabel")
	local hiddenCharacterBox = charactersWindow:getChildById("hiddenCharacterBox")
	local focusLabel
	local focusKey = pendingFocusCharacterKey

	pendingFocusCharacterKey = nil
	pinnedCharactersData = loadPinnedCharacters()
	hiddenCharactersData = loadHiddenCharacters()

	local sortedCharacters = sortCharacters(characters, pinnedCharactersData)

	currentMainCharacterKey = nil
	for _, characterInfo in ipairs(sortedCharacters) do
		local key = makeCharacterKey(characterInfo)
		if isCharacterPinned(key, pinnedCharactersData) then
			currentMainCharacterKey = key
			break
		end
	end

	for i, characterInfo in ipairs(sortedCharacters) do
		local widget = g_ui.createWidget("CharacterWidget", characterList)

		for key, value in pairs(characterInfo) do
			if key ~= "outfit" then
				local subWidget = widget:recursiveGetChildById(key)

				if subWidget then
					if key == "worldPvpType" then
						local name = getWorldTypeName(value)

						if name then
							subWidget:setText(string.format("(%s)", name))
						end
					else
						local text = value

						if subWidget.baseText and subWidget.baseTranslate then
							text = tr(subWidget.baseText, text)
						elseif subWidget.baseText then
							text = string.format(subWidget.baseText, text)
						end

						subWidget:setText(text)
					end
				end
			end
		end

		local creatureDisplay = widget:recursiveGetChildById("outfitCreatureBox")
		local outfit = characterInfo.outfit
		if not outfit and characterInfo.outfitid then
			outfit = {
				type = characterInfo.outfitid,
				head = characterInfo.headcolor or 0,
				body = characterInfo.torsocolor or 0,
				legs = characterInfo.legscolor or 0,
				feet = characterInfo.detailcolor or 0,
				addons = characterInfo.addonsflags or 0
			}
		end

		if outfit and outfit.type and outfit.type > 0 and creatureDisplay then
			local creature = Creature.create()
			creature:setOutfit(outfit)
			creature:setDirection(2)
			creature:setAnimate(false)
			creatureDisplay:setCreature(creature)
			creatureDisplay:show()
		elseif creatureDisplay then
			creatureDisplay:hide()
		end

		local charKey = makeCharacterKey(characterInfo)
		local isHidden = isCharacterHidden(charKey, hiddenCharactersData) or (characterInfo.hidden == true)

		updateDailyRewardWidget(widget, characterInfo.dailyreward)

		local levelWidget = widget:recursiveGetChildById("level")
		if levelWidget and (not characterInfo.level or characterInfo.level == 0) then
			levelWidget:setText("-")
		end

		local vocationWidget = widget:recursiveGetChildById("vocation")
		if vocationWidget and (not characterInfo.vocation or characterInfo.vocation == "") then
			vocationWidget:setText("-")
		end

		local worldWidget = widget:recursiveGetChildById("worldName")
		if worldWidget and (not characterInfo.worldName or characterInfo.worldName == "") then
			worldWidget:setText("-")
		end

		widget.characterName = characterInfo.name
		widget.worldName = characterInfo.worldName
		widget.worldHost = characterInfo.worldHost or characterInfo.worldIp
		widget.worldPort = characterInfo.worldPort
		widget.hidden = isHidden
		widget.dailyreward = characterInfo.dailyreward
		widget.characterInfo = characterInfo
		widget.characterKey = charKey

		local characterPin = widget:getChildById("characterPin")
		if characterPin then
			function characterPin.onClick()
				CharacterList.toggleCharacterPin(widget)

				return true
			end
		end

		local characterHideButton = widget:getChildById("characterHideButton")
		if characterHideButton then
			function characterHideButton.onClick()
				CharacterList.toggleHideCharacter(widget)

				return true
			end
		end

		widget.onHoverChange = function(w, hovered)
			local focused = w:isFocused()
			local pin = w:getChildById("characterPin")
			local hideBtn = w:getChildById("characterHideButton")
			local key = w.characterKey
			local pinned = isCharacterPinned(key, pinnedCharactersData)
			local hidden = isCharacterHidden(key, hiddenCharactersData) or (w.characterInfo and w.characterInfo.hidden == true)

			if pin and not pinned then
				pin:setVisible(hovered or focused)
				if hovered or focused then
					pin:setImageClip(PIN_CLIP_OUTLINE)
				end
			end

			if hideBtn and not hidden then
				hideBtn:setVisible(hovered or focused)
				if hovered or focused then
					hideBtn:setImageClip("2 2 14 14")
				end
			end
		end

		updateCharacterActionWidgets(widget, false, pinnedCharactersData, hiddenCharactersData)

		if isHidden and hiddenCharacterBox and not hiddenCharacterBox:isChecked() then
			widget:hide()
		end

		connect(widget, {
			onDoubleClick = function()
				CharacterList.doLogin()

				return true
			end
		})

		if focusKey and widget.characterKey == focusKey then
			focusLabel = widget
		elseif not focusKey and not isHidden and (i == 1 or g_settings.get("last-used-character") == widget.characterName and g_settings.get("last-used-world") == widget.worldName) then
			focusLabel = widget
		end
	end

	if focusLabel and focusLabel:isVisible() then
		characterList:focusChild(focusLabel, KeyboardFocusReason)
		addEvent(function()
			characterList:ensureChildVisible(focusLabel)
		end)
	else
		for _, child in ipairs(characterList:getChildren()) do
			if child:isVisible() then
				characterList:focusChild(child, KeyboardFocusReason)
				addEvent(function()
					characterList:ensureChildVisible(child)
				end)
				break
			end
		end
	end

	refreshCharacterActionWidgets()

	function characterList.onChildFocusChange()
		removeAutoReconnectEvent()
		refreshCharacterActionWidgets()
	end

	local listScrollBar = charactersWindow:getChildById("characterListScrollBar")

	if listScrollBar and characterList.setVerticalScrollBar then
		characterList:setVerticalScrollBar(listScrollBar)
	end

	if characterList.updateScrollBars then
		characterList:updateScrollBars()
	end

	local showOutfitBox = charactersWindow:getChildById("showOutfitBox")
	if showOutfitBox then
		toggleShowOutfit(showOutfitBox:isChecked())
	end

	local hiddenCharacterBox = charactersWindow:getChildById("hiddenCharacterBox")
	if hiddenCharacterBox then
		hiddenCharacterBox.onCheckChange = function(w)
			toggleHiddenCharacters(w:isChecked())
		end
	end

	local recoveryComplete = account and (account.recoverySetupComplete == true or account.recoverySetupComplete == 1 or account.recoverySetupComplete == "true" or account.recoverySetupComplete == "1")
	local recoveryIncomplete = not recoveryComplete

	if recoverySetupLabel then
		if recoveryIncomplete then
			recoverySetupLabel:setText(tr("You need to complete the recovery setup process!"))
			recoverySetupLabel:setVisible(true)
		else
			recoverySetupLabel:setVisible(false)
			recoverySetupLabel:setText("")
		end
	end

	local status = ""

	if account.status == AccountStatus.Frozen then
		status = tr(" (Frozen)")
	elseif account.status == AccountStatus.Suspended then
		status = tr(" (Suspended)")
	end

	local premiumButton = charactersWindow:getChildById("getPremiumButton")

	local accountStatusTooltip

	if account.subStatus == SubscriptionStatus.Free then
		accountStatusLabel:setText(("%s%s"):format(tr("Free Account"), status))
		accountStatusTooltip = tr("Get a Premium account to enjoy exclusive benefits. Click 'Get Premium' to upgrade.")

		if accountStatusIcon ~= nil then
			accountStatusIcon:setImageSource("/images/game/entergame/nopremium")
		end

		if premiumButton then
			premiumButton:setVisible(true)
		end
	elseif account.subStatus == SubscriptionStatus.Premium then
		if account.premDays == 0 or account.premDays == 65535 then
			accountStatusLabel:setText(("%s%s"):format(tr("Gratis Premium Account"), status))
			accountStatusTooltip = tr("You are enjoying Premium account benefits.")
		else
			local color = account.premDays >= 10 and "#c0c0c0" or "#f86060"

			accountStatusLabel:setColoredText(("%s%s"):format(tr("{Premium Account, #c0c0c0} {(%s days left), " .. color .. "}", account.premDays), status))
			if account.premDays < 10 then
				accountStatusTooltip = tr("Your Premium is about to expire. Click 'Get Premium' to extend it.")
			else
				accountStatusTooltip = tr("You are enjoying Premium account benefits.")
			end
		end

		if accountStatusIcon ~= nil then
			accountStatusIcon:setImageSource("/images/game/entergame/premium")
		end

		if premiumButton then
			premiumButton:setVisible(account.premDays > 0 and account.premDays < 10)
		end
	elseif premiumButton then
		premiumButton:setVisible(false)
	end

	if accountStatusTooltip then
		if accountStatusIcon then
			accountStatusIcon:setTooltip(accountStatusTooltip)
		end

		if accountStatusLabel then
			accountStatusLabel:setTooltip(accountStatusTooltip)
		end
	end

	if account.premDays > 0 and account.premDays < 10 then
		accountStatusLabel:setOn(true)
	else
		accountStatusLabel:setOn(false)
	end
end

function CharacterList.toggleSortOrder()
	if not G.characters or not G.characterAccount then
		return
	end

	if levelSortOrder == "desc" then
		levelSortOrder = "asc"
	else
		levelSortOrder = "desc"
	end

	if characterList and characterList:getChildCount() > 0 then
		reorderCharacterListWidgets()
		return
	end

	local focused = characterList and characterList:getFocusedChild()
	if focused then
		pendingFocusCharacterKey = focused.characterKey
	end

	CharacterList.create(G.characters, G.characterAccount)
end

function CharacterList.toggleHideCharacter(widget)
	if not widget or not widget.characterKey then
		return
	end

	local key = widget.characterKey
	hiddenCharactersData = hiddenCharactersData or loadHiddenCharacters()
	hiddenCharactersData[key] = not hiddenCharactersData[key]
	if not hiddenCharactersData[key] then
		hiddenCharactersData[key] = nil
	end
	saveHiddenCharacters(hiddenCharactersData)

	local isHidden = (hiddenCharactersData[key] == true)
	widget.hidden = isHidden

	local hiddenCharacterBox = charactersWindow and charactersWindow:getChildById("hiddenCharacterBox")
	local showHidden = hiddenCharacterBox and hiddenCharacterBox:isChecked()

	if g_tooltip and g_tooltip.hide then
		g_tooltip.hide(true)
		if g_tooltip.hideSpecial then
			g_tooltip.hideSpecial(true)
		end
	end

	if isHidden and not showHidden then
		if widget:isFocused() and characterList then
			for _, child in ipairs(characterList:getChildren()) do
				if child ~= widget and child:isVisible() then
					characterList:focusChild(child, KeyboardFocusReason)
					break
				end
			end
		end
		widget:hide()
	else
		widget:show()
		updateCharacterActionWidgets(widget, widget:isFocused(), pinnedCharactersData, hiddenCharactersData)
	end

	if characterList and characterList.updateScrollBars then
		characterList:updateScrollBars()
	end
end

function CharacterList.toggleCharacterPin(widget)
	if not widget or not widget.characterKey then
		return
	end

	if not G.characters or not G.characterAccount then
		return
	end

	local key = widget.characterKey
	local pinnedData = loadPinnedCharacters()
	local newOrder = {}

	for _, existingKey in ipairs(pinnedData.order) do
		table.insert(newOrder, existingKey)
	end

	if pinnedData.map[key] then
		for i = #newOrder, 1, -1 do
			if newOrder[i] == key then
				table.remove(newOrder, i)

				break
			end
		end
	else
		table.insert(newOrder, key)
	end

	savePinnedCharacters(newOrder)

	pendingFocusCharacterKey = key

	CharacterList.create(G.characters, G.characterAccount)
	CharacterList.show()
end

function CharacterList.destroy()
	flushSaveSettings()
	CharacterList.hide(true)

	if charactersWindow then
		characterList = nil
		autoReconnectButton = nil

		charactersWindow:destroy()

		charactersWindow = nil
	end
end

function CharacterList.show()
	clearStaleErrorBox()

	if loadBox or errorBox or not isWidgetAlive(charactersWindow) then
		return false
	end

	-- Fade the window in (appear effect). Hiding stays synchronous so ESC->login works.
	charactersWindow:show()
	charactersWindow:raise()
	charactersWindow:focus()
	updateAutoReconnectButton()
	g_effects.fadeIn(charactersWindow, 80)

	return true
end

function CharacterList.hide(showLogin)
	removeAutoReconnectEvent()
	flushSaveSettings()

	showLogin = showLogin or false

	if isWidgetAlive(charactersWindow) then
		g_effects.cancelFade(charactersWindow)
		charactersWindow:hide()
		charactersWindow:setOpacity(1)
	end

	if showLogin and EnterGame and not g_game.isOnline() then
		EnterGame.show()
	end
end

function CharacterList.showAgain()
	clearStaleErrorBox()

	if errorBox then
		return false
	end

	if (not isWidgetAlive(characterList) or not characterList:hasChildren()) and type(G.characters) == "table" and type(G.characterAccount) == "table" then
		CharacterList.create(G.characters, G.characterAccount)
	end

	if isWidgetAlive(characterList) and characterList:hasChildren() and CharacterList.show() then
		scheduleAutoReconnect()

		return true
	end

	if EnterGame and not g_game.isOnline() and not g_game.isLogging() then
		g_logger.warning("[character-list] cached character list unavailable; showing account login")
		EnterGame.show()
	end

	return false
end

function CharacterList.isVisible()
	if isWidgetAlive(charactersWindow) and charactersWindow:isVisible() then
		return true
	end

	return false
end

function CharacterList.doLogin(fromAutoReconnect)
	if loadBox or g_game.isLogging() then
		return
	end

	cancelRestoreCharacterListEvent()
	removeAutoReconnectEvent()

	if not fromAutoReconnect then
		autoReconnectAttempt = false
		manualLogoutPending = false
	end

	local selected = characterList:getFocusedChild()

	if selected then
		local charInfo = {
			worldHost = selected.worldHost,
			worldPort = selected.worldPort,
			worldName = selected.worldName,
			characterName = selected.characterName
		}

		charactersWindow:hide()

		if loginEvent then
			removeEvent(loginEvent)

			loginEvent = nil
		end

		tryLogin(charInfo)
	else
		displayErrorBox(tr("Error"), tr("You must select a character to login!"))
	end
end

function CharacterList.destroyLoadBox()
	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	if destroyCreateAccount then
		destroyCreateAccount()
	end
end

function CharacterList.cancelWait()
	if waitingWindow then
		waitingWindow:destroy()

		waitingWindow = nil
	end

	if updateWaitEvent then
		removeEvent(updateWaitEvent)

		updateWaitEvent = nil
	end

	if resendWaitEvent then
		removeEvent(resendWaitEvent)

		resendWaitEvent = nil
	end

	CharacterList.destroyLoadBox()
	CharacterList.showAgain()
end

function CharacterList.onGetPremiumClick()
	if Services and Services.getCoinsUrl and Services.getCoinsUrl ~= "" then
		g_platform.openUrl(Services.getCoinsUrl)

		return
	end

	if Services and Services.premium and Services.premium ~= "" then
		g_platform.openUrl(Services.premium)

		return
	end

	displayInfoBox(tr("Information"), tr("Premium URL not configured. Please contact the server administrator."))
end

function CharacterList.updateCharactersAppearances(showOutfits)
	if not charactersWindow then
		return
	end

	local showOutfitBox = charactersWindow:getChildById("showOutfitBox")
	if showOutfitBox and showOutfits ~= showOutfitBox:isChecked() then
		showOutfitBox:setChecked(showOutfits)
	else
		toggleShowOutfit(showOutfits)
	end
end

function onLogout()
	if modules.game_interface and modules.game_interface.saveSidebarsBeforeLogout then
		modules.game_interface.saveSidebarsBeforeLogout()
	end

	if autoReconnectAttempt or suppressLogoutTimestamp then
		return
	end

	manualLogoutPending = true
	lastLogout = g_clock.millis()
end

function scheduleAutoReconnect()
	if not g_settings.getBoolean("autoReconnect") or manualLogoutPending or lastLogout + 2000 > g_clock.millis() then
		return
	end

	local now = g_clock.millis()
	local isDuplicateSchedule = autoReconnectEvent ~= nil or now - lastScheduleReconnectAt < RECONNECT_SCHEDULE_DEBOUNCE_MS

	if not isDuplicateSchedule then
		reconnectAttemptCount = reconnectAttemptCount + 1
	end

	lastScheduleReconnectAt = now

	local delay = getReconnectDelay()

	g_logger.info(string.format("[reconnect] scheduling attempt %d in %d ms", reconnectAttemptCount, delay))
	removeAutoReconnectEvent()

	autoReconnectEvent = scheduleEvent(executeAutoReconnect, delay)
end

function executeAutoReconnect()
	if not g_settings.getBoolean("autoReconnect") then
		return
	end

	if loadBox then
		g_logger.info("[reconnect] login already in progress, skipping")

		return
	end

	if errorBox then
		errorBox:destroy()

		errorBox = nil
	end

	autoReconnectAttempt = true

	g_logger.info(string.format("[reconnect] executing attempt %d", reconnectAttemptCount))
	CharacterList.doLogin(true)
end

function toggleShowOutfit(checked)
	if not charactersWindow then
		return
	end

	local characterList = charactersWindow:recursiveGetChildById("characters")
	if not characterList then
		return
	end

	local characterHeaderLabel = charactersWindow:recursiveGetChildById("characterHeaderLabel")
	if characterHeaderLabel then
		characterHeaderLabel:setMarginLeft(checked and 68 or 8)
	end

	local rowHeight = checked and 66 or 22

	for _, child in ipairs(characterList:getChildren()) do
		child:setHeight(rowHeight)

		local outfit = child:getChildById("outfit")
		if outfit then
			outfit:setWidth(checked and (outfit.baseWidth or 70) or 0)
			outfit:setVisible(checked)
		end

		local name = child:getChildById("name")
		if name then
			name:breakAnchors()

			if checked then
				name:addAnchor(AnchorTop, "parent", AnchorTop)
				name:addAnchor(AnchorLeft, "prev", AnchorRight)
				name:setMarginLeft(-2)
			else
				name:addAnchor(AnchorVerticalCenter, "parent", AnchorVerticalCenter)
				name:addAnchor(AnchorLeft, "parent", AnchorLeft)
				name:setMarginLeft(8)
			end
		end

		local worldName = child:recursiveGetChildById("worldName")
		if worldName then
			worldName:setMarginTop(checked and -7 or 0)
		end

		local worldPvpType = child:recursiveGetChildById("worldPvpType")
		if worldPvpType then
			worldPvpType:setVisible(checked)
		end

		local hideBtn = child:getChildById("characterHideButton")
		if hideBtn then
			if checked then
				hideBtn:addAnchor(AnchorTop, "characterPin", AnchorBottom)
				hideBtn:addAnchor(AnchorLeft, "characterPin", AnchorLeft)
				hideBtn:setMarginTop(2)
				hideBtn:setMarginLeft(-1)
			else
				hideBtn:addAnchor(AnchorTop, "parent", AnchorTop)
				hideBtn:addAnchor(AnchorLeft, "parent", AnchorLeft)
				hideBtn:setMarginTop(2)
				hideBtn:setMarginLeft(248)
			end
		end

	end

	if characterList.updateScrollBars then
		characterList:updateScrollBars()
	end
end

modules.client_entergame.toggleShowOutfit = toggleShowOutfit

function toggleHiddenCharacters(checked)
	if not charactersWindow then
		return
	end

	local characterList = charactersWindow:recursiveGetChildById("characters")

	if not characterList then
		return
	end

	for _, child in ipairs(characterList:getChildren()) do
		if child.hidden then
			child:setVisible(checked)
		end
	end

	local focused = characterList:getFocusedChild()
	if focused and not focused:isVisible() then
		for _, child in ipairs(characterList:getChildren()) do
			if child:isVisible() then
				characterList:focusChild(child, KeyboardFocusReason)
				break
			end
		end
	end

	if characterList.updateScrollBars then
		characterList:updateScrollBars()
	end
end

modules.client_entergame.toggleHiddenCharacters = toggleHiddenCharacters

function CharacterList.createCharacter()
	if Services and Services.createAccount then
		if createWidgetAccount then
			createWidgetAccount()
			return
		end
	end

	local charList = charactersWindow and charactersWindow:recursiveGetChildById("characters")
	if charList then
		for _, child in ipairs(charList:getChildren()) do
			if child.characterName and child.characterName:lower():find("account manager") then
				charList:focusChild(child)
				CharacterList.doLogin()
				return
			end
		end
	end

	if Services and Services.websites then
		g_platform.openUrl(Services.websites)
	elseif Services and Services.website then
		g_platform.openUrl(Services.website)
	end
end

function CharacterList.manageAccount()
	if Services and Services.websites then
		g_platform.openUrl(Services.websites)
	elseif Services and Services.website then
		g_platform.openUrl(Services.website)
	else
		CharacterList.hide(true)
	end
end

