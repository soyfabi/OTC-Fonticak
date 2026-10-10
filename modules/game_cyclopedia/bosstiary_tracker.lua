Cyclopedia = Cyclopedia or {}

local BT_DEBUG = false
local TRACKER_POLL_MS = 900
local TRACKER_REQUEST_MIN_MS = 350

function Cyclopedia.bosstiaryTrackerDebug(msg)
	if not BT_DEBUG then
		return
	end
	print("[BosstiaryTracker] " .. tostring(msg))
end

local function btDebug(msg)
	if Cyclopedia.bosstiaryTrackerDebug then
		Cyclopedia.bosstiaryTrackerDebug(msg)
	end
end

local TRACKER_TYPE_BOSSTIARY = 1
local TRACKER_TITLE = "Bosstiary Tra..."

local bosstiaryTrackerWindow = nil
local bosstiaryTrackerTopButton = nil
local bosstiaryTrackerEventsConnected = false
local bosstiaryTrackerPollEvent = nil
local trackerLastRequestAt = 0
local trackerRequestDeferEvent = nil
local lastTrackerRenderSignature = nil
local bosstiaryTrackerSortType = g_settings.get("bosstiary-tracker-sort-type") or "remaining_kills"
local bosstiaryTrackerSortOrder = g_settings.get("bosstiary-tracker-sort-order") or "asc"

local function normalizeTrackerData(data)
	if not data or type(data) ~= "table" then
		return {}
	end

	local normalized = {}

	for _, entry in ipairs(data) do
		if type(entry) == "table" and entry[1] then
			normalized[#normalized + 1] = {
				tonumber(entry[1]) or entry[1],
				tonumber(entry[2]) or 0,
				tonumber(entry[3]) or 0,
				tonumber(entry[4]) or 0,
				tonumber(entry[5]) or 0,
				entry[6]
			}
		end
	end

	if #normalized == 0 then
		for _, entry in pairs(data) do
			if type(entry) == "table" and entry[1] then
				normalized[#normalized + 1] = {
					tonumber(entry[1]) or entry[1],
					tonumber(entry[2]) or 0,
					tonumber(entry[3]) or 0,
					tonumber(entry[4]) or 0,
					tonumber(entry[5]) or 0,
					entry[6]
				}
			end
		end
	end

	return normalized
end

function Cyclopedia.rememberBosstiaryTrackerMeta(raceId, name, outfit)
	raceId = tonumber(raceId)
	if not raceId or raceId <= 0 then
		return
	end

	Cyclopedia.Bosstiary = Cyclopedia.Bosstiary or {}
	Cyclopedia.Bosstiary.TrackerMetaByRaceId = Cyclopedia.Bosstiary.TrackerMetaByRaceId or {}
	local meta = Cyclopedia.Bosstiary.TrackerMetaByRaceId[raceId] or {}

	if name and name ~= "" and name ~= "?" then
		meta.name = name
	end
	if outfit and (outfit.type or 0) > 0 then
		meta.outfit = outfit
	end

	Cyclopedia.Bosstiary.TrackerMetaByRaceId[raceId] = meta
end

local function sendBosstiaryTrackerServerRequest()
	if not g_game.isOnline() then
		return false
	end

	if Cyclopedia.requestBosstiaryDataForTracker then
		return Cyclopedia.requestBosstiaryDataForTracker()
	end

	if Cyclopedia.requestBosstiaryData then
		return Cyclopedia.requestBosstiaryData()
	end

	return false
end

local function requestBosstiaryTrackerRefreshImmediate(reason)
	btDebug("request immediate reason=" .. tostring(reason))
	trackerLastRequestAt = g_clock.millis()
	return sendBosstiaryTrackerServerRequest()
end

local function flushThrottledTrackerRequest(reason)
	trackerRequestDeferEvent = nil
	if not g_game.isOnline() then
		return
	end

	local now = g_clock.millis()
	local waitMs = TRACKER_REQUEST_MIN_MS - (now - trackerLastRequestAt)
	if waitMs > 0 then
		trackerRequestDeferEvent = scheduleEvent(function()
			flushThrottledTrackerRequest(reason)
		end, waitMs)
		return
	end

	btDebug("request throttled reason=" .. tostring(reason))
	trackerLastRequestAt = now
	sendBosstiaryTrackerServerRequest()
end

local function requestBosstiaryTrackerRefreshThrottled(reason)
	if trackerRequestDeferEvent then
		return
	end
	flushThrottledTrackerRequest(reason)
end

local function scheduleBosstiaryTrackerPoll()
	if bosstiaryTrackerPollEvent then
		return
	end

	bosstiaryTrackerPollEvent = scheduleEvent(function()
		bosstiaryTrackerPollEvent = nil
		local window = bosstiaryTrackerWindow
		if window and not window:isDestroyed() and window:isVisible() and g_game.isOnline() then
			local tracked = Cyclopedia.storedBosstiaryTrackerData
			if tracked and #tracked > 0 then
				requestBosstiaryTrackerRefreshThrottled("poll")
			end
			scheduleBosstiaryTrackerPoll()
		end
	end, TRACKER_POLL_MS)
end

local function stopBosstiaryTrackerPoll()
	if bosstiaryTrackerPollEvent then
		removeEvent(bosstiaryTrackerPollEvent)
		bosstiaryTrackerPollEvent = nil
		btDebug("poll stopped")
	end
end

local function resolveTrackerBossOutfit(raceId)
	raceId = tonumber(raceId)
	if not raceId or raceId <= 0 then
		return nil
	end

	local bosstiary = Cyclopedia.Bosstiary
	if bosstiary and bosstiary.TrackerMetaByRaceId and bosstiary.TrackerMetaByRaceId[raceId] then
		local metaOutfit = bosstiary.TrackerMetaByRaceId[raceId].outfit
		if metaOutfit and (metaOutfit.type or 0) > 0 then
			return metaOutfit
		end
	end

	local bosstiary = Cyclopedia.Bosstiary
	if bosstiary and bosstiary.OutfitsByRaceId and bosstiary.OutfitsByRaceId[raceId] then
		local outfit = bosstiary.OutfitsByRaceId[raceId]
		if (outfit.type or 0) > 0 then
			return outfit
		end
	end

	if protoData and protoData[raceId] and (protoData[raceId].type or 0) > 0 then
		return protoData[raceId]
	end

	local raceData = g_things.getRaceData(raceId)
	if raceData and raceData.outfit and (raceData.outfit.type or 0) > 0 then
		return raceData.outfit
	end

	return nil
end

local function resolveTrackerBossName(raceId)
	raceId = tonumber(raceId)
	if not raceId then
		return "?"
	end

	local bosstiary = Cyclopedia.Bosstiary
	if bosstiary and bosstiary.TrackerMetaByRaceId and bosstiary.TrackerMetaByRaceId[raceId] then
		local metaName = bosstiary.TrackerMetaByRaceId[raceId].name
		if metaName and metaName ~= "" then
			return metaName
		end
	end

	if bosstiary and bosstiary.NamesByRaceId and bosstiary.NamesByRaceId[raceId] then
		return bosstiary.NamesByRaceId[raceId]
	end

	if protoData and protoData[raceId] and protoData[raceId].name and protoData[raceId].name ~= "" then
		return protoData[raceId].name
	end

	local raceData = g_things.getRaceData(raceId)
	if raceData and raceData.name and raceData.name ~= "" then
		return raceData.name
	end

	return "?"
end

local function findTrackedRaceIdForMonsterName(monsterName)
	if not monsterName or monsterName == "" then
		return nil
	end

	local nameLower = monsterName:lower()
	for _, entry in ipairs(Cyclopedia.storedBosstiaryTrackerData or {}) do
		local raceId = tonumber(entry[1])
		local bossName = resolveTrackerBossName(raceId)
		if bossName and bossName ~= "?" and bossName:lower() == nameLower then
			return raceId
		end
	end

	return nil
end

local function updateTrackerRowProgress(raceId, kills, maxKills)
	local window = bosstiaryTrackerWindow
	if not window or window:isDestroyed() then
		return
	end

	local contentsPanel = window:recursiveGetChildById("contentsPanel")
	if not contentsPanel then
		return
	end

	local row = contentsPanel:getChildById(tostring(raceId))
	if not row or not row.progressBar then
		return
	end

	local killCount = tonumber(kills) or 0
	local masteryGoal = math.max(tonumber(maxKills) or 1, 1)
	row.progressBar:setPercent(math.min(100, math.floor(killCount * 100 / masteryGoal)))
	row.progressBar:setText(tostring(killCount))
end

local function bumpStoredTrackerKill(raceId, delta)
	delta = delta or 1
	raceId = tonumber(raceId)
	if not raceId then
		return
	end

	for _, entry in ipairs(Cyclopedia.storedBosstiaryTrackerData or {}) do
		if tonumber(entry[1]) == raceId then
			entry[2] = (tonumber(entry[2]) or 0) + delta
			updateTrackerRowProgress(raceId, entry[2], entry[5])
			lastTrackerRenderSignature = trackerRenderSignature(Cyclopedia.storedBosstiaryTrackerData)
			return
		end
	end
end

local function trackerRenderSignature(data)
	local parts = {}
	for _, entry in ipairs(data) do
		parts[#parts + 1] = string.format("%s:%s", tostring(entry[1]), tostring(entry[2]))
	end
	return table.concat(parts, "|")
end

local function canPatchTrackerContents(data, contentsPanel)
	if not contentsPanel or contentsPanel:getChildCount() ~= #data then
		return false
	end

	for i, entry in ipairs(data) do
		local child = contentsPanel:getChildByIndex(i)
		if not child or tostring(entry[1]) ~= child:getId() then
			return false
		end
	end

	return true
end

local function bindBosstiaryTrackerEntryClick(widget, raceId)
	if not widget then
		return
	end

	widget.onMouseRelease = function(_, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton then
			return false
		end

		if Cyclopedia.openBosstiaryFromTracker then
			return Cyclopedia.openBosstiaryFromTracker(raceId)
		end

		return false
	end
end

local function sortBosstiaryTrackerData(data)
	table.sort(data, function(a, b)
		local raceIdA, killsA = a[1], a[2] or 0
		local raceIdB, killsB = b[1], b[2] or 0
		local maxA = math.max(a[5] or 1, 1)
		local maxB = math.max(b[5] or 1, 1)
		local valA
		local valB

		if bosstiaryTrackerSortType == "name" then
			valA = resolveTrackerBossName(raceIdA):lower()
			valB = resolveTrackerBossName(raceIdB):lower()
		elseif bosstiaryTrackerSortType == "percentage" then
			valA = math.min(100, math.floor(killsA * 100 / maxA))
			valB = math.min(100, math.floor(killsB * 100 / maxB))
		else
			valA = math.max(0, maxA - killsA)
			valB = math.max(0, maxB - killsB)
		end

		if valA == valB then
			return resolveTrackerBossName(raceIdA):lower() < resolveTrackerBossName(raceIdB):lower()
		end

		if bosstiaryTrackerSortOrder == "desc" then
			return valA > valB
		end

		return valA < valB
	end)

	return data
end

local function untrackAllBosstiaryBosses()
	local data = normalizeTrackerData(Cyclopedia.storedBosstiaryTrackerData or {})
	for _, entry in ipairs(data) do
		if sendBosstiaryTrackerStatus then
			sendBosstiaryTrackerStatus(entry[1], false)
		elseif Cyclopedia.removeFromTracker then
			Cyclopedia.removeFromTracker(TRACKER_TYPE_BOSSTIARY, entry[1])
		end
	end

	if #data == 0 and Cyclopedia.onParseBosstiaryTracker then
		Cyclopedia.onParseBosstiaryTracker({})
	end
end

local function redrawBosstiaryTracker()
	if Cyclopedia.storedBosstiaryTrackerData then
		Cyclopedia.onParseBosstiaryTracker(Cyclopedia.storedBosstiaryTrackerData)
	end
end

local function setupBosstiaryTrackerChromeButtons(window)
	if not window then
		return
	end

	local toggleFilterButton = window:recursiveGetChildById("toggleFilterButton")
	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
		toggleFilterButton:setOn(false)
	end

	local menuButton = window:recursiveGetChildById("menuButton")
	if menuButton then
		menuButton:setVisible(false)
	end

	local contextMenuButton = window:recursiveGetChildById("contextMenuButton")
	local lockButton = window:recursiveGetChildById("lockButton")
	local minimizeButton = window:recursiveGetChildById("minimizeButton")
	local newWindowButton = window:recursiveGetChildById("newWindowButton")

	if contextMenuButton then
		contextMenuButton:setVisible(true)
		if minimizeButton then
			contextMenuButton:breakAnchors()
			contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
			contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
			contextMenuButton:setMarginRight(7)
			contextMenuButton:setMarginTop(0)
		end

		contextMenuButton.onClick = function(_, mousePos)
			local menu = g_ui.createWidget("PopupMenu")
			menu:setGameMenu(true)

			menu:addCheckBox(tr("Sort by name"), bosstiaryTrackerSortType == "name", function()
				bosstiaryTrackerSortType = "name"
				g_settings.set("bosstiary-tracker-sort-type", bosstiaryTrackerSortType)
				redrawBosstiaryTracker()
			end)
			menu:addCheckBox(tr("Sort by completion percentage"), bosstiaryTrackerSortType == "percentage", function()
				bosstiaryTrackerSortType = "percentage"
				g_settings.set("bosstiary-tracker-sort-type", bosstiaryTrackerSortType)
				redrawBosstiaryTracker()
			end)
			menu:addCheckBox(tr("Sort by remaining kills"), bosstiaryTrackerSortType == "remaining_kills", function()
				bosstiaryTrackerSortType = "remaining_kills"
				g_settings.set("bosstiary-tracker-sort-type", bosstiaryTrackerSortType)
				redrawBosstiaryTracker()
			end)

			menu:addSeparator()

			menu:addCheckBox(tr("Sort ascending"), bosstiaryTrackerSortOrder == "asc", function()
				bosstiaryTrackerSortOrder = "asc"
				g_settings.set("bosstiary-tracker-sort-order", bosstiaryTrackerSortOrder)
				redrawBosstiaryTracker()
			end)
			menu:addCheckBox(tr("Sort descending"), bosstiaryTrackerSortOrder == "desc", function()
				bosstiaryTrackerSortOrder = "desc"
				g_settings.set("bosstiary-tracker-sort-order", bosstiaryTrackerSortOrder)
				redrawBosstiaryTracker()
			end)

			menu:addSeparator()
			menu:addOption(tr("Untrack all"), untrackAllBosstiaryBosses)

			menu:display(mousePos)
			return true
		end
	end

	if newWindowButton then
		newWindowButton:setVisible(true)
		if contextMenuButton then
			newWindowButton:breakAnchors()
			newWindowButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
			newWindowButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
			newWindowButton:setMarginRight(2)
			newWindowButton:setMarginTop(0)
		end

		newWindowButton.onClick = function()
			if modules.game_cyclopedia and modules.game_cyclopedia.show then
				modules.game_cyclopedia.show("bosstiary")
			end
			return true
		end
	end

	if lockButton then
		lockButton:setVisible(true)
		if newWindowButton then
			lockButton:breakAnchors()
			lockButton:addAnchor(AnchorTop, newWindowButton:getId(), AnchorTop)
			lockButton:addAnchor(AnchorRight, newWindowButton:getId(), AnchorLeft)
			lockButton:setMarginRight(2)
			lockButton:setMarginTop(0)
		elseif contextMenuButton then
			lockButton:breakAnchors()
			lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
			lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
			lockButton:setMarginRight(2)
			lockButton:setMarginTop(0)
		end
	end
end

local function ensureBosstiaryTrackerWindow()
	if bosstiaryTrackerWindow and not bosstiaryTrackerWindow:isDestroyed() then
		return bosstiaryTrackerWindow
	end

	local rightPanel = modules.game_interface and modules.game_interface.getRightPanel and modules.game_interface.getRightPanel()
	if not rightPanel then
		return nil
	end

	bosstiaryTrackerWindow = g_ui.createWidget("BestiaryTrackerMini", rightPanel)
	if not bosstiaryTrackerWindow then
		return nil
	end

	bosstiaryTrackerWindow:setId("BosstiaryTrackerWindow")

	bosstiaryTrackerWindow:setText(TRACKER_TITLE)

	local titleWidget = bosstiaryTrackerWindow:getChildById("miniwindowTitle")
	if titleWidget then
		titleWidget:setText(tr(TRACKER_TITLE))
		titleWidget:setMarginRight(85)
	end

	local iconWidget = bosstiaryTrackerWindow:getChildById("miniwindowIcon")
	if iconWidget then
		iconWidget:setImageSource("/images/icons/icon-bosstiarytracker-widget")
	end

	setupBosstiaryTrackerChromeButtons(bosstiaryTrackerWindow)

	function bosstiaryTrackerWindow.onOpen()
		setupBosstiaryTrackerChromeButtons(bosstiaryTrackerWindow)
		Cyclopedia.syncBosstiaryTrackerButton()
		requestBosstiaryTrackerRefreshImmediate("window-open")
		scheduleBosstiaryTrackerPoll()
		Cyclopedia.applyStoredBosstiaryTracker()
	end

	function bosstiaryTrackerWindow.onClose()
		Cyclopedia.syncBosstiaryTrackerButton()
		stopBosstiaryTrackerPoll()
	end

	bosstiaryTrackerWindow:setup()
	bosstiaryTrackerWindow:hide()
	bosstiaryTrackerWindow:setupOnStart()

	return bosstiaryTrackerWindow
end

function Cyclopedia.syncBosstiaryTrackerButton()
	local visible = bosstiaryTrackerWindow and not bosstiaryTrackerWindow:isDestroyed() and bosstiaryTrackerWindow:isVisible()

	if bosstiaryTrackerTopButton and not bosstiaryTrackerTopButton:isDestroyed() then
		bosstiaryTrackerTopButton:setOn(visible)
	end
end

function Cyclopedia.applyStoredBosstiaryTracker()
	if Cyclopedia.storedBosstiaryTrackerData then
		Cyclopedia.onParseBosstiaryTracker(Cyclopedia.storedBosstiaryTrackerData)
	end
end

function Cyclopedia.onParseBosstiaryTracker(data)
	data = normalizeTrackerData(data)
	data = sortBosstiaryTrackerData(data)

	local signature = trackerRenderSignature(data)
	if signature == lastTrackerRenderSignature then
		Cyclopedia.storedBosstiaryTrackerData = data
		return
	end

	Cyclopedia.storedBosstiaryTrackerData = data

	local window = ensureBosstiaryTrackerWindow()
	if not window or window:isDestroyed() then
		return
	end

	local contentsPanel = window:recursiveGetChildById("contentsPanel")
	if not contentsPanel then
		return
	end

	if canPatchTrackerContents(data, contentsPanel) then
		for _, entry in ipairs(data) do
			updateTrackerRowProgress(entry[1], entry[2], entry[5])
		end
		lastTrackerRenderSignature = signature
		return
	end

	lastTrackerRenderSignature = signature
	contentsPanel:destroyChildren()

	for _, entry in ipairs(data) do
		local raceId, kills, _, _, maxKills = entry[1], entry[2], entry[3], entry[4], entry[5]
		local outfit = resolveTrackerBossOutfit(raceId)
		local name = resolveTrackerBossName(raceId)

		local row = g_ui.createWidget("BestiaryTrackerEntry", contentsPanel)

		row:setId(tostring(raceId))
		row.raceId = raceId

		bindBosstiaryTrackerEntryClick(row, raceId)
		bindBosstiaryTrackerEntryClick(row.creature, raceId)
		bindBosstiaryTrackerEntryClick(row.creatureName, raceId)
		bindBosstiaryTrackerEntryClick(row.progressBg, raceId)
		bindBosstiaryTrackerEntryClick(row.progressBar, raceId)

		if outfit and row.creature then
			row.creature:setOutfit(outfit)
			if row.creature.getCreature then
				local creature = row.creature:getCreature()
				if creature and creature.setStaticWalking then
					creature:setStaticWalking(1000)
				end
			end
		end

		if row.creatureName then
			local displayName = name and name ~= "?" and name or string.format("Boss #%d", raceId)
			if displayName:len() > 0 then
				displayName = displayName:sub(1, 1):upper() .. displayName:sub(2)
			end
			row.creatureName:setText(displayName)
		end

		local killCount = tonumber(kills) or 0
		local masteryGoal = math.max(tonumber(maxKills) or 1, 1)
		if row.progressBar then
			row.progressBar:setPercent(math.min(100, math.floor(killCount * 100 / masteryGoal)))
			row.progressBar:setText(tostring(killCount))
		end
	end
end

function Cyclopedia.openBosstiaryFromTracker(raceId)
	raceId = tonumber(raceId)
	if not raceId or raceId <= 0 then
		return false
	end

	Cyclopedia._pendingBosstiaryRaceId = raceId

	if modules.game_cyclopedia and modules.game_cyclopedia.show then
		modules.game_cyclopedia.show("bosstiary")
	elseif showBosstiary then
		showBosstiary()
	end

	if Cyclopedia.focusBosstiaryRaceId and Cyclopedia.focusBosstiaryRaceId(raceId) then
		Cyclopedia._pendingBosstiaryRaceId = nil
		return true
	end

	if Cyclopedia.applyPendingBosstiaryShortcut then
		Cyclopedia.applyPendingBosstiaryShortcut()
	end

	return true
end

function Cyclopedia.removeFromTracker(trackerType, raceId)
	if trackerType ~= TRACKER_TYPE_BOSSTIARY then
		return
	end

	raceId = tonumber(raceId)
	if not raceId then
		return
	end

	local data = normalizeTrackerData(Cyclopedia.storedBosstiaryTrackerData or {})
	local filtered = {}

	for _, entry in ipairs(data) do
		if tonumber(entry[1]) ~= raceId then
			filtered[#filtered + 1] = entry
		end
	end

	Cyclopedia._bosstiaryTrackerOverrides = Cyclopedia._bosstiaryTrackerOverrides or {}
	Cyclopedia._bosstiaryTrackerOverrides[raceId] = 0

	if Cyclopedia.Bosstiary and Cyclopedia.Bosstiary.Creatures then
		for _, page in pairs(Cyclopedia.Bosstiary.Creatures) do
			for _, creature in ipairs(page) do
				if creature.raceId == raceId then
					creature.isTrackerActived = 0
				end
			end
		end
	end

	Cyclopedia.onParseBosstiaryTracker(filtered)
end

function Cyclopedia.onTrackerClose()
end

function Cyclopedia.restoreBosstiaryTracker()
	local char = g_game.getCharacterName()
	local settings = g_settings.getNode("CharMiniWindows")
	local saved = char and settings and settings[char] and settings[char].BosstiaryTrackerWindow
	local windowWasOpen = saved and not saved.closed

	if not bosstiaryTrackerWindow and not windowWasOpen then
		if g_game.isOnline() then
			scheduleEvent(function()
				requestBosstiaryTrackerRefreshImmediate("restore-delayed")
			end, 500)
		end
		return
	end

	local window = ensureBosstiaryTrackerWindow()
	if not window then
		return
	end

	if window.setupOnStart then
		window:setupOnStart()
	end

	Cyclopedia.syncBosstiaryTrackerButton()

	if g_game.isOnline() then
		requestBosstiaryTrackerRefreshImmediate("restore")
	end

	if window:isVisible() then
		scheduleBosstiaryTrackerPoll()
		Cyclopedia.applyStoredBosstiaryTracker()
	end
end

function Cyclopedia.onBosstiaryTrackerGameEnd()
	stopBosstiaryTrackerPoll()
	if trackerRequestDeferEvent then
		removeEvent(trackerRequestDeferEvent)
		trackerRequestDeferEvent = nil
	end
	lastTrackerRenderSignature = nil

	if bosstiaryTrackerWindow and not bosstiaryTrackerWindow:isDestroyed() then
		bosstiaryTrackerWindow:close(true)
		local contentsPanel = bosstiaryTrackerWindow:recursiveGetChildById("contentsPanel")
		if contentsPanel then
			contentsPanel:destroyChildren()
		end
	end
end

function Cyclopedia.toggleBosstiaryTracker()
	local window = ensureBosstiaryTrackerWindow()
	if not window then
		return
	end

	if window:isVisible() then
		window:close()
	else
		requestBosstiaryTrackerRefreshImmediate("toggle-open")
		scheduleBosstiaryTrackerPoll()
		Cyclopedia.applyStoredBosstiaryTracker()
		window:open()
	end

	Cyclopedia.syncBosstiaryTrackerButton()
end

local function onKillTracker(monsterName)
	local raceId = findTrackedRaceIdForMonsterName(monsterName)
	if not raceId then
		return
	end

	bumpStoredTrackerKill(raceId, 1)
	requestBosstiaryTrackerRefreshThrottled("kill")
end

local function onParseCyclopediaTracker(trackerType, data)
	btDebug(string.format("onParseCyclopediaTracker type=%s entries=%s", tostring(trackerType), tostring(data and #data or 0)))

	if trackerType == TRACKER_TYPE_BOSSTIARY then
		Cyclopedia.onParseBosstiaryTracker(data)
		return
	end

	if trackerType == 0 and g_game.getFeature and g_game.getFeature(GameBosstiaryTracker) and data and #data > 0 then
		local stored = Cyclopedia.storedBosstiaryTrackerData
		if stored and #stored > 0 then
			local tracked = {}
			for _, entry in ipairs(stored) do
				tracked[tonumber(entry[1])] = true
			end
			local matchesBosstiaryTracker = true
			for _, entry in ipairs(data) do
				if not tracked[tonumber(entry[1])] then
					matchesBosstiaryTracker = false
					break
				end
			end
			if matchesBosstiaryTracker then
				btDebug("onParseCyclopediaTracker: treating type=0 as bosstiary")
				Cyclopedia.onParseBosstiaryTracker(data)
			else
				btDebug("onParseCyclopediaTracker: type=0 did not match stored tracker")
			end
		end
	end
end

function initBosstiaryTracker()
	Cyclopedia.storedBosstiaryTrackerData = Cyclopedia.storedBosstiaryTrackerData or {}
	btDebug("initBosstiaryTracker")

	if not bosstiaryTrackerEventsConnected then
		connect(g_game, {
			onParseCyclopediaTracker = onParseCyclopediaTracker,
			onKillTracker = onKillTracker
		})
		bosstiaryTrackerEventsConnected = true
		btDebug("game events connected (tracker + kill)")
	end

	if not bosstiaryTrackerTopButton and modules.client_topmenu and modules.client_topmenu.addRightGameToggleButton then
		bosstiaryTrackerTopButton = modules.client_topmenu.addRightGameToggleButton(
			"bosstiaryTrackerButton",
			tr(TRACKER_TITLE),
			"/images/options/bosstiaryTracker",
			Cyclopedia.toggleBosstiaryTracker,
			false,
			10
		)
		modules.game_cyclopedia.bosstiaryTrackerButton = bosstiaryTrackerTopButton
	end
end

function terminateBosstiaryTracker()
	if bosstiaryTrackerEventsConnected then
		stopBosstiaryTrackerPoll()
		if trackerRequestDeferEvent then
			removeEvent(trackerRequestDeferEvent)
			trackerRequestDeferEvent = nil
		end
		disconnect(g_game, {
			onParseCyclopediaTracker = onParseCyclopediaTracker,
			onKillTracker = onKillTracker
		})
		bosstiaryTrackerEventsConnected = false
	end

	if bosstiaryTrackerTopButton then
		bosstiaryTrackerTopButton:destroy()
		bosstiaryTrackerTopButton = nil
	end

	if bosstiaryTrackerWindow and not bosstiaryTrackerWindow:isDestroyed() then
		bosstiaryTrackerWindow:destroy()
		bosstiaryTrackerWindow = nil
	end
end
