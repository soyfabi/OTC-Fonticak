-- chunkname: @/game_questlog/game_questlog.lua
local save -- forward declaration (used before its declaration in the decompiled file)

questLogController = Controller:new()

local trackerMiniWindow, questLogButton, buttonQuestLogTrackerButton
local UICheckBox = {}
local UIlabel = {}
local UITextList = {}
local UITextEdit = {}
local settings = {}
local namePlayer = ""
local currentQuestId
local selectedQuestId
local selectedMissionId
local selectFirstQuestOnOpen = false
local lastSelectedMissionByQuest = {}
local missionToQuestMap = {}
local isNavigating = false
local isUpdatingCheckbox = false
local questLogCache = {
	completed = 0,
	visible = 0,
	hidden = 0,
	items = {}
}
local COLORS = {
	BASE_1 = "#484848",
	SELECTED = "#585858",
	BASE_2 = "#414141"
}
local COMPLETED_QUEST_ICON = "/game_cyclopedia/images/checkmark-icon"
local file = "/settings/questtracking.json"
local DEBUG_QUESTLOG = false
local questLogDebugCounts = {}
local questLogDataLoaded = false
local lastQuestLogSignature, pendingQuestLogApplyEvent, pendingQuestLogData
local isSearchFilterUpdating = false

local function qlog(tag, fmt, ...)
	if not DEBUG_QUESTLOG then
		return
	end

	questLogDebugCounts[tag] = (questLogDebugCounts[tag] or 0) + 1

	local n = questLogDebugCounts[tag]
	local msg = string.format(fmt, ...)

	print(string.format("[questlog][%s #%d] %s", tag, n, msg))
end

local function isIdInTracker(key, id)
	if not settings[key] then
		return false
	end

	return table.findbyfield(settings[key], 1, tonumber(id)) ~= nil
end

local function isMissionCompleted(missionName, missionDescription)
	if missionName and string.find(string.lower(missionName), "%(completed%)") then
		return true
	end

	if missionDescription then
		local desc = string.lower(missionDescription)

		if string.find(desc, "%(completed%)") then
			return true
		end

		if string.find(desc, "complete") and (string.find(desc, "quest") or string.find(desc, "mission")) then
			return true
		end
	end

	return false
end

local function getMissionDisplayName(missionName)
	if not missionName then
		return ""
	end

	local name = missionName:gsub("%s*%([Cc]ompleted%)%s*", "")

	return name:gsub("^%s+", ""):gsub("%s+$", "")
end

local function addUniqueIdQuest(key, questId, missionId, missionName, missionDescription)
	if not settings[key] then
		settings[key] = {}
	end

	if not isIdInTracker(key, missionId) then
		table.insert(settings[key], {
			tonumber(missionId),
			missionName,
			missionDescription or missionName,
			tonumber(questId)
		})
	end
end

local function removeNumber(key, id)
	if settings[key] then
		table.remove_if(settings[key], function(_, v)
			return v[1] == tonumber(id)
		end)
	end
end

local function getQuestMissionId(questId, missionId, missionIndex)
	missionId = tonumber(missionId) or 0
	if missionId > 0 then
		return missionId
	end

	-- Protocol 8.60 does not transmit mission IDs. Create a stable local ID
	-- so multiple missions from the same quest can be tracked independently.
	return (tonumber(questId) or 0) * 1000 + missionIndex
end

local function autoUntrackCompletedQuests()
	if not settings.autoUntrackCompleted or not settings[namePlayer] or not trackerMiniWindow then
		return
	end

	local removedMissionIds = {}

	if trackerMiniWindow.contentsPanel and trackerMiniWindow.contentsPanel.list then
		for i = trackerMiniWindow.contentsPanel.list:getChildCount(), 1, -1 do
			local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildByIndex(i)

			if trackerLabel and trackerLabel.description then
				local description = trackerLabel.description:getText()
				local missionId = tonumber(trackerLabel:getId())
				local isCompleted = description and (string.find(string.lower(description), "%(completed%)") or string.find(string.lower(description), "complete") and (string.find(string.lower(description), "quest") or string.find(string.lower(description), "mission")))

				if isCompleted then
					table.insert(removedMissionIds, missionId)
					removeNumber(namePlayer, missionId)
					trackerLabel:destroy()
				end
			end
		end
	end

	if #removedMissionIds > 0 then
		if trackerMiniWindow.contentsPanel and trackerMiniWindow.contentsPanel.list then
			trackerMiniWindow.contentsPanel.list:getLayout():update()
		end

		save()
	end
end

local function load()
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return g_logger.error("Error while reading profiles file. To fix this problem you can delete storage.json. Details: " .. result)
		end

		return result or {}
	end
end

save = function()
	local status, result = pcall(function()
		return json.encode(settings, 2)
	end)

	if not status then
		return g_logger.error("Error while saving profile settings. Data won't be saved. Details: " .. result)
	end

	if result:len() > 104857600 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end

	g_resources.writeFileContents(file, result)
end

local sortFunctions = {
	["Sort by Name (A-Z)"] = function(a, b)
		return a:getText() < b:getText()
	end,
	["Sort by Name (Z-A)"] = function(a, b)
		return a:getText() > b:getText()
	end,
	["Completed on Top"] = function(a, b)
		local aCompleted = a.isComplete or false
		local bCompleted = b.isComplete or false

		if aCompleted and not bCompleted then
			return true
		elseif not aCompleted and bCompleted then
			return false
		else
			return a:getText() < b:getText()
		end
	end,
	["Completed on Bottom"] = function(a, b)
		local aCompleted = a.isComplete or false
		local bCompleted = b.isComplete or false

		if aCompleted and not bCompleted then
			return false
		elseif not aCompleted and bCompleted then
			return true
		else
			return a:getText() < b:getText()
		end
	end
}

local function sendQuestTracker(listToMap)
	-- Legacy 8.60 servers do not implement the modern tracker request opcode.
	-- Keep tracking local on those clients to avoid sending an unknown packet.
	if g_game.getClientVersion() < 1280 then
		return
	end

	local map = {}

	for _, entry in ipairs(listToMap) do
		map[entry[1]] = entry[2]
	end

	g_game.sendRequestTrackerQuestLog(map)
end

local function rebuildTrackerFromSettings()
	if not trackerMiniWindow or not settings[namePlayer] then
		return
	end

	trackerMiniWindow.contentsPanel.list:destroyChildren()

	for i, entry in ipairs(settings[namePlayer]) do
		local missionId, missionName, missionDescription, questId = unpack(entry)

		if not questId or questId == 0 then
			questId = missionToQuestMap[tonumber(missionId)] or 0
		end

		local trackerLabel = g_ui.createWidget("QuestTrackerLabel", trackerMiniWindow.contentsPanel.list)

		trackerLabel:setId(tostring(missionId))

		trackerLabel.questId = questId
		trackerLabel.missionId = missionId

		trackerLabel.description:setText(missionDescription or missionName)

		if questId and questId == 0 then
			-- block empty
		end
	end

	if settings[namePlayer] and #settings[namePlayer] > 0 then
		sendQuestTracker(settings[namePlayer])
	end

	scheduleEvent(autoUntrackCompletedQuests, 1000)
end

local function findQuestIdForMission(missionId)
	if not UITextList.questLogList then
		return nil
	end

	for i = 1, UITextList.questLogList:getChildCount() do
		local questItem = UITextList.questLogList:getChildByIndex(i)
		local questId = questItem:getId()
	end

	return nil
end

local function debugTrackerLabels()
	if not trackerMiniWindow or not trackerMiniWindow.contentsPanel or not trackerMiniWindow.contentsPanel.list then
		return
	end

	local childCount = trackerMiniWindow.contentsPanel.list:getChildCount()

	for i = 1, childCount do
		local child = trackerMiniWindow.contentsPanel.list:getChildByIndex(i)
		local questId = child.questId
		local missionId = child.missionId
		local widgetId = child:getId()
		local description = child.description:getText()
	end
end

local function destroyWindows(windows)
	if type(windows) == "table" then
		for _, window in pairs(windows) do
			if window and not window:isDestroyed() then
				window:destroy()
			end
		end
	elseif windows and not windows:isDestroyed() then
		windows:destroy()
	end

	return nil
end

local function resetItemCategorySelection(list)
	for _, child in pairs(list:getChildren()) do
		child:setChecked(false)
		child:setBackgroundColor(child.BaseColor)

		if child.iconShow then
			child.iconShow:setVisible(child.isHiddenQuestLog)
		end

		if child.iconPin then
			child.iconPin:setVisible(child.isPinned)
		end
	end
end

local function getQuestListScrollBar()
	local panel = questLogController and questLogController.ui and questLogController.ui.panelQuestLog and questLogController.ui.panelQuestLog.areaPanelQuestList

	return panel and panel.spellsScrollBar
end

local function getCurrentSortOrder()
	if questLogController and questLogController.currentSortOrder then
		return questLogController.currentSortOrder
	end

	local combo = questLogController and questLogController.ui and questLogController.ui.panelQuestLog and questLogController.ui.panelQuestLog.comboBoxFilter

	if combo and combo.getText then
		local text = combo:getText()

		if text and text ~= "" and sortFunctions[text] then
			return text
		end
	end

	return "Sort by Name (A-Z)"
end

local function updateQuestCounter()
	if not UIlabel.numberQuestComplete or not UIlabel.numberQuestHidden then
		return
	end

	UIlabel.numberQuestComplete:setText(questLogCache.completed)
	UIlabel.numberQuestHidden:setText(questLogCache.hidden)
end

local function recolorVisibleItems()
	local visibleIndex = 0

	for _, item in pairs(questLogCache.items) do
		if item:isVisible() then
			if item:isChecked() then
				item:setBackgroundColor(COLORS.SELECTED)
			else
				visibleIndex = visibleIndex + 1

				local color = visibleIndex % 2 == 1 and COLORS.BASE_1 or COLORS.BASE_2

				item:setBackgroundColor(color)

				item.BaseColor = color
			end
		end
	end
end

local function applyListItemSelection(list, item, focus)
	if not list or not item then
		return
	end

	resetItemCategorySelection(list)
	item:setChecked(true)
	item:setBackgroundColor(COLORS.SELECTED)

	if list == UITextList.questLogList then
		recolorVisibleItems()
	end

	if focus and list.focusChild then
		qlog("applyListItemSelection", "focusChild id=%s", item:getId())
		list:focusChild(item)
	end
end

local function restoreQuestListSelection()
	if not currentQuestId or not UITextList.questLogList then
		return
	end

	qlog("restoreQuestListSelection", "questId=%s (sem focusChild)", tostring(currentQuestId))

	local questItem = UITextList.questLogList:getChildById(tostring(currentQuestId))

	if not questItem then
		return
	end

	for _, child in pairs(UITextList.questLogList:getChildren()) do
		child:setChecked(false)
	end

	questItem:setChecked(true)
	recolorVisibleItems()

	if questItem.iconShow then
		questItem.iconShow:setVisible(true)
	end

	if questItem.iconPin then
		questItem.iconPin:setVisible(true)
	end
end

local function getFirstVisibleQuestItem()
	local list = UITextList.questLogList

	if not list then
		return nil
	end

	for _, child in ipairs(list:getChildren()) do
		if child:isVisible() then
			return child
		end
	end

	return nil
end

local function selectFirstQuestInList()
	local item = getFirstVisibleQuestItem()

	if not item then
		return
	end

	qlog("selectFirstQuestInList", "id=%s", item:getId())
	item:onClick()
end

local function scheduleSelectFirstQuestOnOpen()
	scheduleEvent(function()
		if not selectFirstQuestOnOpen then
			return
		end

		if not questLogController.ui or not questLogController.ui:isVisible() then
			selectFirstQuestOnOpen = false

			return
		end

		selectFirstQuestInList()

		selectFirstQuestOnOpen = false
	end, 50)
end

local function createQuestItem(parent, id, text, color, icon)
	local item = g_ui.createWidget("QuestLogLabel", parent)

	item:setId(id)
	item:setText(text)
	item:setBackgroundColor(color)
	item:setPhantom(false)
	item:setFocusable(true)

	item.BaseColor = color
	item.isPinned = false
	item.isComplete = false

	if icon and icon ~= "" then
		item:setIcon(icon)

		item.isComplete = true
	end

	if parent == UITextList.questLogList then
		table.insert(questLogCache.items, item)

		if item.isComplete then
			questLogCache.completed = questLogCache.completed + 1
		end
	end

	return item
end

local function sortQuestList(questList, sortOrder)
	qlog("sortQuestList", "order=%s", tostring(sortOrder))

	questLogController.currentSortOrder = sortOrder

	local scrollBar = getQuestListScrollBar()
	local scrollValue = scrollBar and scrollBar:getValue()
	local pinnedItems = {}
	local regularItems = {}

	for _, child in pairs(questLogCache.items) do
		if child.isPinned then
			table.insert(pinnedItems, child)
		else
			table.insert(regularItems, child)
		end
	end

	local sortFunc = sortFunctions[sortOrder]

	if sortFunc then
		table.sort(regularItems, sortFunc)
	end

	questLogCache.items = {}

	local index = 1

	for _, item in ipairs(pinnedItems) do
		questList:moveChildToIndex(item, index)
		table.insert(questLogCache.items, item)

		index = index + 1
	end

	for _, item in ipairs(regularItems) do
		questList:moveChildToIndex(item, index)
		table.insert(questLogCache.items, item)

		index = index + 1
	end

	recolorVisibleItems()
	updateQuestCounter()

	if scrollBar and scrollValue ~= nil then
		addEvent(function()
			if scrollBar and not scrollBar:isDestroyed() then
				scrollBar:setValue(scrollValue)
			end
		end)
	end
end

local function setupQuestItemClickHandler(item, isQuestList)
	function item:onClick()
		local list = isQuestList and UITextList.questLogList or UITextList.questLogLine

		qlog("onClick", "isQuestList=%s id=%s", tostring(isQuestList), self:getId())
		applyListItemSelection(list, self, true)

		if isQuestList then
			selectedQuestId = tonumber(self:getId())
			currentQuestId = selectedQuestId

			g_game.requestQuestLine(self:getId())
			self.iconShow:setVisible(true)
			self.iconPin:setVisible(true)
		else
			selectedMissionId = tonumber(self:getId())

			if currentQuestId then
				lastSelectedMissionByQuest[currentQuestId] = tonumber(self:getId())
			end

			UITextList.questLogInfo:setText(self.description)

			if not isNavigating then
				local playerName = namePlayer or g_game.getCharacterName():lower()
				local missionId = selectedMissionId or tonumber(self:getId())
				local isThisMissionTracked = false

				if settings[playerName] and settings[playerName] then
					for _, entry in ipairs(settings[playerName]) do
						if entry[1] == missionId then
							isThisMissionTracked = true

							break
						end
					end
				end

				isUpdatingCheckbox = true

				UICheckBox.showInQuestTracker:setChecked(isThisMissionTracked)

				isUpdatingCheckbox = false
			end
		end
	end

	if isQuestList then
		function item.iconPin:onClick(mousePos)
			local parent = self:getParent()

			parent.isPinned = not parent.isPinned

			if parent.isPinned then
				self:setImageColor("#00ff00")

				local list = UITextList.questLogList

				list:removeChild(parent)
				list:insertChild(1, parent)
				table.removevalue(questLogCache.items, parent)
				table.insert(questLogCache.items, 1, parent)
				recolorVisibleItems()
			else
				self:setImageColor("#ffffff")
				self:setVisible(false)
				sortQuestList(UITextList.questLogList, questLogController.currentSortOrder or "Sort by Name (A-Z)")
			end

			return true
		end

		function item.iconShow:onClick(mousePos, mouseButton)
			local parent = self:getParent()

			parent.isHiddenQuestLog = not parent.isHiddenQuestLog

			if parent.isHiddenQuestLog then
				questLogCache.hidden = questLogCache.hidden + 1

				self:setImageColor("#ff0000")

				if not UICheckBox.showShidden:isChecked() then
					parent:setVisible(false)

					questLogCache.visible = questLogCache.visible - 1
				end
			else
				questLogCache.hidden = questLogCache.hidden - 1

				self:setImageColor("#ffffff")

				local isCompleted = parent.isComplete
				local shouldBeVisible = UICheckBox.showComplete:isChecked() or not isCompleted

				parent:setVisible(shouldBeVisible)

				if shouldBeVisible then
					questLogCache.visible = questLogCache.visible + 1
				end
			end

			if parent.iconShow then
				parent.iconShow:setVisible(parent.isHiddenQuestLog)
			end

			if parent.iconPin then
				parent.iconPin:setVisible(parent.isPinned)
			end

			updateQuestCounter()
			recolorVisibleItems()

			return true
		end
	end
end

local function getQuestLogSearchEdit()
	if UITextEdit.search and not UITextEdit.search:isDestroyed() then
		return UITextEdit.search
	end

	return nil
end

local function focusQuestLogSearch()
	local ui = questLogController.ui
	local search = getQuestLogSearchEdit()

	if not ui or not search then
		return
	end

	local panel = ui.panelQuestLog
	local searchPanel = panel and panel.textEditSearchQuest

	if not panel or not searchPanel then
		return
	end

	local function applyFocus()
		if not ui:isVisible() or search:isDestroyed() then
			return
		end

		ui:raise()
		ui:focus()
		ui:grabKeyboard()
		ui:focusChild(panel, KeyboardFocusReason)
		panel:focusChild(searchPanel, KeyboardFocusReason)
		searchPanel:focusChild(search, KeyboardFocusReason)
		search:setCursorVisible(true)
		search:setCursorPos(-1)
	end

	applyFocus()
	scheduleEvent(applyFocus, 50)
end

local function setupQuestLogSearchField()
	local searchPanel = questLogController.ui and questLogController.ui.panelQuestLog and questLogController.ui.panelQuestLog.textEditSearchQuest

	if not searchPanel then
		return
	end

	UITextEdit.search = searchPanel:getChildById("SearchEdit")

	if not UITextEdit.search then
		return
	end

	function UITextEdit.search.onTextChange(widget)
		onSearchTextChange(widget:getText())
	end
end

function clearQuestLogSearch()
	local search = getQuestLogSearchEdit()

	if not search then
		return
	end

	search:setText("")
	onSearchTextChange("")
end

local function hide()
	if not questLogController.ui then
		return
	end

	pcall(function()
		questLogController.ui:ungrabKeyboard()
	end)
	if g_modalManager then
		g_modalManager.hide(questLogController.ui)
	end
	questLogController.ui:hide()
end

function show()
	if not questLogController.ui then
		return
	end

	local childCount = UITextList.questLogList and UITextList.questLogList:getChildCount() or 0

	qlog("show", "loaded=%s childCount=%d", tostring(questLogDataLoaded), childCount)

	if not questLogDataLoaded or childCount == 0 then
		lastQuestLogSignature = nil

		g_game.requestQuestLog()
	else
		qlog("show", "skip requestQuestLog (lista ja carregada)")
	end

	selectFirstQuestOnOpen = true

	questLogController.ui:show()
	if g_modalManager then
		g_modalManager.show(questLogController.ui)
	end
	focusQuestLogSearch()

	if childCount > 0 then
		scheduleSelectFirstQuestOnOpen()
	end
end

local function toggle()
	if not questLogController.ui then
		return
	end

	if questLogController.ui:isVisible() then
		return hide()
	end

	show()
end

local function toggleTracker()
	if trackerMiniWindow:isOn() then
		if trackerMiniWindow.closeAndForgetLayout then
			trackerMiniWindow:closeAndForgetLayout()
		else
			trackerMiniWindow:close()
		end
	else
		if not trackerMiniWindow:getParent() then
			local panel = modules.game_interface.findContentPanelAvailable(trackerMiniWindow, trackerMiniWindow:getMinimumHeight())

			if not panel then
				return
			end

			panel:addChild(trackerMiniWindow)
		end

		trackerMiniWindow:open()
	end
end

local function syncQuestLogTrackerMainPanelButton()
	if not buttonQuestLogTrackerButton or buttonQuestLogTrackerButton:isDestroyed() then
		return
	end

	local on = false

	if trackerMiniWindow and not trackerMiniWindow:isDestroyed() then
		on = trackerMiniWindow:isVisible()
	end

	buttonQuestLogTrackerButton:setOn(on)

	if buttonQuestLogTrackerButton.setTooltip then
		buttonQuestLogTrackerButton:setTooltip(tr(on and "Close Quest Tracker Window" or "Open Quest Tracker Window"))
	end
end

function onOpenTracker()
	syncQuestLogTrackerMainPanelButton()
end

function onCloseTracker()
	syncQuestLogTrackerMainPanelButton()
end

local function showQuestTracker()
	if trackerMiniWindow then
		toggleTracker()

		return
	end

	trackerMiniWindow = g_ui.createWidget("QuestLogTracker")

	local toggleFilterButton = trackerMiniWindow:recursiveGetChildById("toggleFilterButton")

	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
	end

	local menuButton = trackerMiniWindow:getChildById("menuButton")

	if menuButton then
		menuButton:setVisible(false)
	end

	local titleWidget = trackerMiniWindow:getChildById("miniwindowTitle")

	if titleWidget then
		titleWidget:setText("Quest Tracker")
	else
		trackerMiniWindow:setText("Quest Tracker")
	end

	local iconWidget = trackerMiniWindow:getChildById("miniwindowIcon")

	if iconWidget then
		iconWidget:setImageSource("/images/topbuttons/icon-questtracker-widget")
	end

	local contextMenuButton = trackerMiniWindow:recursiveGetChildById("contextMenuButton")
	local minimizeButton = trackerMiniWindow:recursiveGetChildById("minimizeButton")

	if contextMenuButton and minimizeButton then
		contextMenuButton:setVisible(true)
		contextMenuButton:breakAnchors()
		contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
		contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
		contextMenuButton:setMarginRight(5)
		contextMenuButton:setMarginTop(0)
		contextMenuButton:setSize({
			height = 12,
			width = 12
		})
	end

	local newWindowButton = trackerMiniWindow:recursiveGetChildById("newWindowButton")

	if newWindowButton and contextMenuButton then
		newWindowButton:setVisible(true)
		newWindowButton:breakAnchors()
		newWindowButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
		newWindowButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
		newWindowButton:setMarginRight(2)
		newWindowButton:setMarginTop(0)
	end

	local lockButton = trackerMiniWindow:recursiveGetChildById("lockButton")

	if lockButton and newWindowButton then
		lockButton:breakAnchors()
		lockButton:addAnchor(AnchorTop, newWindowButton:getId(), AnchorTop)
		lockButton:addAnchor(AnchorRight, newWindowButton:getId(), AnchorLeft)
		lockButton:setMarginRight(2)
		lockButton:setMarginTop(0)
	end

	if contextMenuButton then
		function contextMenuButton.onClick(widget, mousePos)
			local menu = g_ui.createWidget("PopupMenu")

			menu:setGameMenu(true)
			menu:addOption("Remove all quests", function()
				if settings[namePlayer] then
					local removedMissionIds = {}

					for _, entry in ipairs(settings[namePlayer]) do
						local missionId = entry[1]

						table.insert(removedMissionIds, missionId)
					end

					table.clear(settings[namePlayer])
					table.clear(missionToQuestMap)
					sendQuestTracker(settings[namePlayer])
					trackerMiniWindow.contentsPanel.list:destroyChildren()

					if questLogController.ui and questLogController.ui:isVisible() and UITextList.questLogLine and UITextList.questLogLine:hasChildren() and UITextList.questLogLine:getFocusedChild() then
						local currentMissionId = tonumber(UITextList.questLogLine:getFocusedChild():getId())

						isUpdatingCheckbox = true

						UICheckBox.showInQuestTracker:setChecked(false)

						isUpdatingCheckbox = false
					end

					trackerMiniWindow.contentsPanel.list:getLayout():enableUpdates()
					trackerMiniWindow.contentsPanel.list:getLayout():update()
					save()
				end
			end)
			menu:addOption("Remove completed quests", function()
				if settings[namePlayer] then
					local removedMissionIds = {}
					local completedMissionIds = {}

					for i, entry in ipairs(settings[namePlayer]) do
						local missionId, missionName, missionDescription, questId = unpack(entry)
						local isCompleted = false

						if missionName and string.find(string.lower(missionName), "%(completed%)") then
							isCompleted = true
						end

						if not isCompleted and missionDescription and string.find(string.lower(missionDescription), "%(completed%)") then
							isCompleted = true
						end

						if not isCompleted and trackerMiniWindow and trackerMiniWindow.contentsPanel and trackerMiniWindow.contentsPanel.list then
							local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))

							if trackerLabel and trackerLabel.description then
								local trackerText = trackerLabel.description:getText()

								if trackerText and string.find(string.lower(trackerText), "%(completed%)") then
									isCompleted = true
								end
							end
						end

						if not isCompleted and questId and UITextList.questLogList then
							local questItem = UITextList.questLogList:getChildById(tostring(questId))

							if questItem then
								questItem:onClick()
								scheduleEvent(function()
									if UITextList.questLogLine and UITextList.questLogLine:hasChildren() then
										local missionItem = UITextList.questLogLine:getChildById(tostring(missionId))

										if missionItem then
											local missionText = missionItem:getText()

											if missionText and string.find(string.lower(missionText), "%(completed%)") then
												table.insert(removedMissionIds, missionId)
												table.insert(completedMissionIds, missionId)
											elseif missionItem.isComplete then
												table.insert(removedMissionIds, missionId)
												table.insert(completedMissionIds, missionId)
											end
										end
									end

									if i == #settings[namePlayer] then
										scheduleEvent(function()
											processCompletedMissionRemoval()
										end, 100)
									end
								end, 50)
							end
						end

						if isCompleted then
							table.insert(removedMissionIds, missionId)
							table.insert(completedMissionIds, missionId)
						end
					end

					if #removedMissionIds > 0 then
						scheduleEvent(function()
							processCompletedMissionRemoval()
						end, 100)
					end

					function processCompletedMissionRemoval()
						if #removedMissionIds > 0 then
							for j = #settings[namePlayer], 1, -1 do
								local checkMissionId = settings[namePlayer][j][1]

								for _, removedId in ipairs(removedMissionIds) do
									if checkMissionId == removedId then
										table.remove(settings[namePlayer], j)

										break
									end
								end
							end

							for _, missionId in ipairs(removedMissionIds) do
								if missionToQuestMap[tonumber(missionId)] then
									missionToQuestMap[tonumber(missionId)] = nil
								end
							end

							sendQuestTracker(settings[namePlayer])

							for _, missionId in ipairs(removedMissionIds) do
								local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))

								if trackerLabel then
									trackerLabel:destroy()
								end
							end

							if questLogController.ui and questLogController.ui:isVisible() and UITextList.questLogLine and UITextList.questLogLine:hasChildren() and UITextList.questLogLine:getFocusedChild() then
								local currentMissionId = tonumber(UITextList.questLogLine:getFocusedChild():getId())

								for _, removedId in ipairs(removedMissionIds) do
									if currentMissionId == removedId then
										isUpdatingCheckbox = true

										UICheckBox.showInQuestTracker:setChecked(false)

										isUpdatingCheckbox = false

										break
									end
								end
							end

							trackerMiniWindow.contentsPanel.list:getLayout():enableUpdates()
							trackerMiniWindow.contentsPanel.list:getLayout():update()
							save()
						end
					end
				end
			end)
			menu:addSeparator()
			menu:addCheckBox("Automatically track new quests", settings.autoTrackNewQuests or false, function(widget, checked)
				settings.autoTrackNewQuests = checked

				save()
			end)
			menu:addCheckBox("Automatically untrack completed quests", settings.autoUntrackCompleted or false, function(widget, checked)
				settings.autoUntrackCompleted = checked

				save()

				if checked then
					scheduleEvent(function()
						local function periodicAutoUntrack()
							autoUntrackCompletedQuests()

							if settings.autoUntrackCompleted then
								scheduleEvent(periodicAutoUntrack, 30000)
							end
						end

						periodicAutoUntrack()
					end, 1000)
				end
			end)
			menu:display(mousePos)

			return true
		end
	end

	if newWindowButton then
		function newWindowButton.onClick()
			show()

			return true
		end
	end

	trackerMiniWindow:setContentMinimumHeight(80)
	trackerMiniWindow:setup()

	if settings[namePlayer] and #settings[namePlayer] > 0 then
		rebuildTrackerFromSettings()
	end

	trackerMiniWindow:setupOnStart()
	syncQuestLogTrackerMainPanelButton()

	if settings.autoUntrackCompleted then
		scheduleEvent(function()
			local function periodicAutoUntrack()
				autoUntrackCompletedQuests()

				if settings.autoUntrackCompleted then
					scheduleEvent(periodicAutoUntrack, 30000)
				end
			end

			periodicAutoUntrack()
		end, 5000)
	end
end

local function buildQuestLogSignature(questList)
	local parts = {}

	for i = 1, #questList do
		local id, questName, questCompleted = unpack(questList[i])

		parts[i] = string.format("%s:%s:%s", id, questName, questCompleted and 1 or 0)
	end

	table.sort(parts)

	return table.concat(parts, "|")
end

local function applyQuestLogFromServer(questList)
	if not UITextList.questLogList then
		return
	end

	qlog("applyQuestLogFromServer", "count=%d", #questList)
	UITextList.questLogList:destroyChildren()

	questLogDataLoaded = true
	questLogCache = {
		completed = 0,
		hidden = 0,
		items = {},
		visible = #questList
	}

	local categoryColor = COLORS.BASE_1

	for i = 1, #questList do
		local id, questName, questCompleted = unpack(questList[i])
		local icon = questCompleted and COMPLETED_QUEST_ICON or ""
		local itemCat = createQuestItem(UITextList.questLogList, id, questName, categoryColor, icon)

		setupQuestItemClickHandler(itemCat, true)

		categoryColor = categoryColor == COLORS.BASE_1 and COLORS.BASE_2 or COLORS.BASE_1
	end

	sortQuestList(UITextList.questLogList, getCurrentSortOrder())
	updateQuestCounter()

	local search = getQuestLogSearchEdit()

	if search then
		local text = search:getText() or ""

		if text:len() > 0 then
			onSearchTextChange(text)
		end
	end

	if selectFirstQuestOnOpen and questLogController.ui and questLogController.ui:isVisible() then
		scheduleSelectFirstQuestOnOpen()
	else
		restoreQuestListSelection()
	end
end

local function onQuestLog(questList)
	if not questList or #questList == 0 then
		return
	end

	local signature = buildQuestLogSignature(questList)

	if signature == lastQuestLogSignature then
		qlog("onQuestLog", "SKIP duplicate count=%d", #questList)

		return
	end

	if not questLogDataLoaded or not UITextList.questLogList or UITextList.questLogList:getChildCount() == 0 then
		lastQuestLogSignature = signature

		applyQuestLogFromServer(questList)

		return
	end

	pendingQuestLogData = questList

	if pendingQuestLogApplyEvent then
		removeEvent(pendingQuestLogApplyEvent)
	end

	pendingQuestLogApplyEvent = scheduleEvent(function()
		pendingQuestLogApplyEvent = nil

		local data = pendingQuestLogData

		if not data then
			return
		end

		local sig = buildQuestLogSignature(data)

		if sig == lastQuestLogSignature then
			return
		end

		lastQuestLogSignature = sig

		applyQuestLogFromServer(data)
	end, 100)
end

local function onQuestLine(questId, questMissions)
	qlog("onQuestLine", "questId=%s missions=%d", tostring(questId), #questMissions)

	-- Quest line responses are asynchronous. When the player clicks several
	-- quests quickly, an older response can arrive after the newest one.
	-- Ignore it if it no longer matches the quest currently selected in the UI.
	if selectedQuestId and tonumber(selectedQuestId) ~= tonumber(questId) then
		qlog("onQuestLine", "ignored stale response questId=%s", tostring(questId))
		return
	end

	currentQuestId = questId
	local selectedQuest = UITextList.questLogList and UITextList.questLogList:getFocusedChild()
	if selectedQuest then
		questLogController.ui.panelQuestLineSelected:setText(selectedQuest:getText())
	end

	UITextList.questLogLine:destroyChildren()
	selectedMissionId = nil

	isUpdatingCheckbox = true

	UICheckBox.showInQuestTracker:setChecked(false)

	isUpdatingCheckbox = false

	local categoryColor = COLORS.BASE_1
	local needsTrackerRebuild = false

	for missionIndex, data in ipairs(questMissions) do
		local missionName, missionDescription, missionId = unpack(data)
		missionId = getQuestMissionId(questId, missionId, missionIndex)
		local completed = isMissionCompleted(missionName, missionDescription)
		local displayName = getMissionDisplayName(missionName)
		local icon = completed and COMPLETED_QUEST_ICON or ""
		local itemCat = createQuestItem(UITextList.questLogLine, missionId, displayName, categoryColor, icon)

		itemCat.description = missionDescription

		setupQuestItemClickHandler(itemCat, false)
		missionToQuestMap[missionId] = questId

		categoryColor = categoryColor == COLORS.BASE_1 and COLORS.BASE_2 or COLORS.BASE_1

		if settings.autoTrackNewQuests and not isIdInTracker(namePlayer, missionId) and not completed then
			addUniqueIdQuest(namePlayer, questId, missionId, missionName, missionDescription)
			save()

			needsTrackerRebuild = true
		end
	end

	if needsTrackerRebuild then
		qlog("onQuestLine", "rebuildTrackerFromSettings (1x)")
		rebuildTrackerFromSettings()
	end

	if UITextList.questLogLine:hasChildren() then
		local missionToSelect
		local preferredMissionId = lastSelectedMissionByQuest[questId]

		if preferredMissionId and isIdInTracker(namePlayer, preferredMissionId) then
			missionToSelect = UITextList.questLogLine:getChildById(tostring(preferredMissionId))
		end

		if not missionToSelect then
			for index = 1, UITextList.questLogLine:getChildCount() do
				local candidate = UITextList.questLogLine:getChildByIndex(index)
				if isIdInTracker(namePlayer, tonumber(candidate:getId())) then
					missionToSelect = candidate
					break
				end
			end
		end

		if not missionToSelect and preferredMissionId then
			missionToSelect = UITextList.questLogLine:getChildById(tostring(preferredMissionId))
		end

		missionToSelect = missionToSelect or UITextList.questLogLine:getChildByIndex(1)

		if missionToSelect then
			isNavigating = true

			missionToSelect:onClick()
			isUpdatingCheckbox = true
			UICheckBox.showInQuestTracker:setChecked(isIdInTracker(namePlayer, tonumber(missionToSelect:getId())))
			isUpdatingCheckbox = false
			scheduleEvent(function()
				isNavigating = false
			end, 100)
		end
	end
end

local function onQuestTracker(remainingQuests, missions)
	qlog("onQuestTracker", "missions=%s", missions and tostring(#missions) or "nil")

	if not trackerMiniWindow then
		showQuestTracker()
	end

	if not missions or type(missions[1]) ~= "table" then
		if settings[namePlayer] and #settings[namePlayer] > 0 then
			syncQuestLogTrackerMainPanelButton()

			return
		end

		trackerMiniWindow.contentsPanel.list:destroyChildren()
		syncQuestLogTrackerMainPanelButton()

		return
	end

	local settingsDirty = false
	local trackerLayoutUpdated = false

	for index, mission in ipairs(missions) do
		local questId, missionId, questName, missionName, missionDesc = unpack(mission)
		local missionIdNum = tonumber(missionId)

		if missionIdNum and missionIdNum > 0 then
			missionToQuestMap[missionIdNum] = tonumber(questId)

			local isTracked = isIdInTracker(namePlayer, missionIdNum)
			local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionIdNum))

			if isTracked or trackerLabel then
				if not trackerLabel then
					trackerLabel = g_ui.createWidget("QuestTrackerLabel", trackerMiniWindow.contentsPanel.list)

					trackerLabel:setId(tostring(missionIdNum))
				end

				trackerLabel.questId = questId
				trackerLabel.missionId = missionIdNum

				trackerLabel.description:setText(missionDesc or missionName)

				trackerLayoutUpdated = true

				if settings[namePlayer] then
					for i, entry in ipairs(settings[namePlayer]) do
						if entry[1] == missionIdNum then
							settings[namePlayer][i] = {
								missionIdNum,
								missionName,
								missionDesc or missionName,
								questId
							}
							settingsDirty = true

							break
						end
					end
				end
			end
		end
	end

	if trackerLayoutUpdated then
		local layout = trackerMiniWindow.contentsPanel.list:getLayout()

		if layout then
			layout:update()
		end
	end

	if settingsDirty then
		save()
	end

	if settings.autoUntrackCompleted then
		scheduleEvent(autoUntrackCompletedQuests, 500)
	end

	syncQuestLogTrackerMainPanelButton()
end

local function onUpdateQuestTracker(questId, missionId, questName, missionName, missionDesc)
	if not trackerMiniWindow then
		return
	end

	local missionIdNum = tonumber(missionId)

	if not missionIdNum or missionIdNum <= 0 then
		return
	end

	local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionIdNum))

	if not trackerLabel and settings[namePlayer] and isIdInTracker(namePlayer, missionIdNum) then
		trackerLabel = g_ui.createWidget("QuestTrackerLabel", trackerMiniWindow.contentsPanel.list)

		trackerLabel:setId(tostring(missionIdNum))

		trackerLabel.questId = questId
		trackerLabel.missionId = missionIdNum
	end

	if trackerLabel then
		trackerLabel.description:setText(missionDesc or missionName)

		trackerLabel.questId = questId
		trackerLabel.missionId = missionIdNum

		if settings[namePlayer] then
			for i, entry in ipairs(settings[namePlayer]) do
				if entry[1] == missionIdNum then
					settings[namePlayer][i] = {
						missionIdNum,
						missionName,
						missionDesc or missionName,
						questId
					}

					save()

					break
				end
			end
		end

		local layout = trackerMiniWindow.contentsPanel.list:getLayout()

		if layout then
			layout:update()
		end

		if settings.autoUntrackCompleted then
			local isCompleted = missionDesc and (string.find(string.lower(missionDesc), "%(completed%)") or string.find(string.lower(missionDesc), "complete") and (string.find(string.lower(missionDesc), "quest") or string.find(string.lower(missionDesc), "mission")))

			if isCompleted then
				removeNumber(namePlayer, missionId)
				save()
				trackerLabel:destroy()
				trackerMiniWindow.contentsPanel.list:getLayout():update()
			end
		end
	end
end

function filterQuestList(searchText)
	qlog("filterQuestList", "search=%s", tostring(searchText))

	if not UICheckBox.showComplete or not UICheckBox.showShidden then
		return
	end

	local showComplete = UICheckBox.showComplete:isChecked()
	local showHidden = UICheckBox.showShidden:isChecked()
	local searchPattern = searchText and string.lower(searchText) or nil

	questLogCache.visible = 0

	for _, child in pairs(questLogCache.items) do
		local isCompleted = child.isComplete
		local isHidden = child.isHiddenQuestLog
		local text = child:getText()
		local visible = true

		if searchPattern and text then
			visible = string.find(string.lower(text), searchPattern) ~= nil
		end

		if not showComplete and isCompleted then
			visible = false
		end

		if not showHidden and isHidden then
			visible = false
		end

		child:setVisible(visible)

		if visible then
			questLogCache.visible = questLogCache.visible + 1
		end

		if child.iconShow then
			child.iconShow:setVisible(child.isHiddenQuestLog)
		end
	end

	recolorVisibleItems()
end

function questLogController:onCheckChangeQuestTracker(widget)
	if not widget then
		return
	end

	local isChecked = widget:isChecked()

	if isNavigating then
		return
	end

	if isUpdatingCheckbox then
		return
	end

	if not namePlayer or namePlayer == "" then
		namePlayer = g_game.getCharacterName():lower()
	end

	if not trackerMiniWindow then
		showQuestTracker()
	end

	if not trackerMiniWindow then
		return
	end

	if not UITextList.questLogLine:hasChildren() or not UITextList.questLogLine:getFocusedChild() then
		return
	end

	local focusedChild = UITextList.questLogLine:getFocusedChild()
	local missionId = tonumber(focusedChild:getId())
	local missionName = focusedChild:getText()
	local missionDescription = focusedChild.description or missionName

	if not currentQuestId or currentQuestId == 0 then
		if UITextList.questLogList and UITextList.questLogList:getFocusedChild() then
			currentQuestId = tonumber(UITextList.questLogList:getFocusedChild():getId())
		end

		if not currentQuestId or currentQuestId == 0 then
			return
		end
	end

	if isChecked then
		missionToQuestMap[missionId] = currentQuestId

		if not trackerMiniWindow:isVisible() then
			showQuestTracker()
		end

		addUniqueIdQuest(namePlayer, currentQuestId, missionId, missionName, missionDescription)

		local existingLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))

		if not existingLabel then
			local trackerLabel = g_ui.createWidget("QuestTrackerLabel", trackerMiniWindow.contentsPanel.list)

			trackerLabel:setId(tostring(missionId))

			trackerLabel.questId = currentQuestId
			trackerLabel.missionId = missionId

			trackerLabel.description:setText(missionDescription)
		else
			existingLabel.questId = currentQuestId
			existingLabel.missionId = missionId

			existingLabel.description:setText(missionDescription)
		end
	else
		removeNumber(namePlayer, missionId)

		local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))

		if trackerLabel then
			trackerLabel:destroy()
		end

		missionToQuestMap[missionId] = nil
	end

	if settings[namePlayer] then
		sendQuestTracker(settings[namePlayer])
		rebuildTrackerFromSettings()
	end

	save()
end

function questLogController:onFilterQuestLog(widget, optionText)
	if not widget then
		return
	end

	local sortText = optionText or widget:getText()

	qlog("onFilterQuestLog", "sort=%s current=%s", tostring(sortText), tostring(questLogController.currentSortOrder))

	if not sortText or not sortFunctions[sortText] then
		return
	end

	if questLogController.currentSortOrder == sortText then
		qlog("onFilterQuestLog", "skip (mesmo sort)")

		return
	end

	sortQuestList(UITextList.questLogList, sortText)
end

local function setupQuestLogFilterCombo()
	local combo = questLogController.ui.panelQuestLog.comboBoxFilter

	if not combo then
		return
	end

	qlog("setupQuestLogFilterCombo", "init combo")
	combo:clearOptions()
	combo:addOption("Sort by Name (A-Z)")
	combo:addOption("Sort by Name (Z-A)")
	combo:addOption("Completed on Top")
	combo:addOption("Completed on Bottom")
	combo:setCurrentOption("Sort by Name (A-Z)", true)

	questLogController.currentSortOrder = "Sort by Name (A-Z)"

	function combo.onOptionChange(widget, text)
		qlog("combo.onOptionChange", "text=%s", tostring(text))
		questLogController:onFilterQuestLog(widget, text)
	end
end

function questLogController:close()
	hide()
end

function questLogController:toggleMiniWindowsTracker()
	if not trackerMiniWindow then
		showQuestTracker()
		syncQuestLogTrackerMainPanelButton()

		return
	end

	if trackerMiniWindow:isVisible() then
		if trackerMiniWindow.closeAndForgetLayout then
			trackerMiniWindow:closeAndForgetLayout()
		else
			trackerMiniWindow:close()
		end
		syncQuestLogTrackerMainPanelButton()

		return
	end

	showQuestTracker()
	syncQuestLogTrackerMainPanelButton()
end

function questLogController:filterQuestListShowComplete()
	filterQuestList()
end

function questLogController:filterQuestListShowHidden()
	filterQuestList()
end

function onSearchTextChange(text)
	if isSearchFilterUpdating then
		return
	end

	qlog("onSearchTextChange", "len=%d", text and text:len() or 0)

	if not questLogCache.items or #questLogCache.items == 0 then
		return
	end

	text = text or ""

	if text.trim then
		text = text:trim()
	else
		text = text:gsub("^%s+", ""):gsub("%s+$", "")
	end

	isSearchFilterUpdating = true

	if text:len() > 0 then
		filterQuestList(text)
	else
		filterQuestList()
	end

	isSearchFilterUpdating = false
end

function onQuestLogMousePress(widget, mousePos, mouseButton)
	if mouseButton ~= MouseRightButton then
		return
	end

	local menu = g_ui.createWidget("PopupMenu")

	menu:setGameMenu(true)
	menu:addOption(tr("remove"), function()
		local missionId = widget:getParent():getId()

		removeNumber(namePlayer, missionId)

		if settings[namePlayer] then
			sendQuestTracker(settings[namePlayer])
		end

		widget:getParent():destroy()
		save()

		if missionToQuestMap[tonumber(missionId)] then
			missionToQuestMap[tonumber(missionId)] = nil
		end

		if UITextList.questLogLine:hasChildren() and UITextList.questLogLine:getFocusedChild() then
			local currentId = UITextList.questLogLine:getFocusedChild():getId()

			if tostring(currentId) == tostring(missionId) then
				UICheckBox.showInQuestTracker:setChecked(false)
			end
		end
	end)
	menu:display(mousePos)

	return true
end

function onQuestTrackerDescriptionClick(widget, mousePos, mouseButton)
	if mouseButton == MouseRightButton then
		return onQuestLogMousePress(widget, mousePos, mouseButton)
	elseif mouseButton == MouseLeftButton then
		local trackerLabel = widget:getParent()
		local questId = trackerLabel.questId
		local missionId = trackerLabel.missionId

		if (not questId or questId == 0) and missionId then
			questId = missionToQuestMap[tonumber(missionId)]

			if questId then
				trackerLabel.questId = questId
			end
		end

		local labelIndex = trackerLabel:getParent():getChildIndex(trackerLabel)

		show()

		selectFirstQuestOnOpen = false

		if questId and questId ~= 0 and missionId then
			local function attemptNavigation(attempts)
				attempts = attempts or 0

				if attempts > 20 then
					return
				end

				scheduleEvent(function()
					if UITextList.questLogList and UITextList.questLogList:getChildCount() > 0 then
						local questItem = UITextList.questLogList:getChildById(tostring(questId))

						if questItem then
							questItem:onClick()

							local function attemptMissionSelection(missionAttempts)
								missionAttempts = missionAttempts or 0

								if missionAttempts > 10 then
									return
								end

								scheduleEvent(function()
									if UITextList.questLogLine and UITextList.questLogLine:getChildCount() > 0 then
										local missionItem = UITextList.questLogLine:getChildById(tostring(missionId))

										if missionItem then
											isNavigating = false

											missionItem:onClick()
											scheduleEvent(function()
												isUpdatingCheckbox = true

												UICheckBox.showInQuestTracker:setChecked(true)

												isUpdatingCheckbox = false
											end, 50)
										else
											attemptMissionSelection(missionAttempts + 1)
										end
									else
										attemptMissionSelection(missionAttempts + 1)
									end
								end, 100)
							end

							attemptMissionSelection()
						else
							attemptNavigation(attempts + 1)
						end
					else
						attemptNavigation(attempts + 1)
					end
				end, 100)
			end

			attemptNavigation()
		end

		return true
	end

	return false
end

local function bindQuestLogWidgets()
	local ui = questLogController.ui

	UITextList.questLogList = ui.panelQuestLog.areaPanelQuestList.questList
	UITextList.questLogLine = ui.panelQuestLineSelected.ScrollAreaQuestList.questList
	UITextList.questLogInfo = ui.panelQuestLineSelected.panelQuestInfo.questList

	setupQuestLogSearchField()

	UIlabel.numberQuestComplete = ui.panelQuestLog.filterPanel.lblCompleteNumber
	UIlabel.numberQuestHidden = ui.panelQuestLog.filterPanel.lblHiddenNumber
	UICheckBox.showComplete = ui.panelQuestLog.filterPanel.checkboxShowComplete
	UICheckBox.showShidden = ui.panelQuestLog.filterPanel.checkboxShowShidden
	UICheckBox.showInQuestTracker = ui.panelQuestLineSelected.checkboxShowInQuestTracker
end

local function setupQuestLogFilterCheckboxes()
	function UICheckBox.showComplete.onCheckChange()
		questLogController:filterQuestListShowComplete()
	end

	function UICheckBox.showShidden.onCheckChange()
		questLogController:filterQuestListShowHidden()
	end

	function UICheckBox.showInQuestTracker.onCheckChange(widget)
		questLogController:onCheckChangeQuestTracker(widget)
	end

	UICheckBox.showComplete:setChecked(true, true)
end

function questLogController:onInit()
	questLogController.ui = g_ui.loadUI("game_questlog", g_ui.getRootWidget())

	if not questLogController.ui then
		g_logger.error("[game_questlog] failed to load game_questlog UI")

		return
	end

	bindQuestLogWidgets()
	setupQuestLogFilterCheckboxes()
	setupQuestLogFilterCombo()
	questLogController.ui:centerIn("parent")
	hide()
	questLogController:registerEvents(g_game, {
		onQuestLog = onQuestLog,
		onQuestLine = onQuestLine,
		onQuestTracker = onQuestTracker,
		onUpdateQuestTracker = onUpdateQuestTracker
	})

	questLogButton = modules.game_mainpanel.addToggleButton("questLogButton", tr("Open Quest Log"), "/images/options/button_questlog", function()
		toggle()
	end, false, 1000)

	Keybind.new("Windows", "Show/hide quest Log", "", "")
	Keybind.bind("Windows", "Show/hide quest Log", {
		{
			type = KEY_DOWN,
			callback = function()
				show()
			end
		}
	})
end

function questLogController:onTerminate()
	questLogButton, trackerMiniWindow, buttonQuestLogTrackerButton = destroyWindows({
		questLogButton,
		trackerMiniWindow,
		buttonQuestLogTrackerButton
	})

	Keybind.delete("Windows", "Show/hide quest Log")
end

function questLogController:onGameStart()
	namePlayer = g_game.getCharacterName():lower()
	settings = load() or {}

	if settings.autoTrackNewQuests == nil then
		settings.autoTrackNewQuests = false
	end

	if settings.autoUntrackCompleted == nil then
		settings.autoUntrackCompleted = false
	end

	if not settings[namePlayer] then
		settings[namePlayer] = {}
	end

	-- Remove entries created by the old 8.60 implementation, which used
	-- mission ID 0 for every mission and could not track more than one.
	for index = #settings[namePlayer], 1, -1 do
		local entry = settings[namePlayer][index]
		if type(entry) ~= "table" or tonumber(entry[1]) == nil or tonumber(entry[1]) <= 0 then
			table.remove(settings[namePlayer], index)
		end
	end

	if not buttonQuestLogTrackerButton then
		buttonQuestLogTrackerButton = modules.game_mainpanel.addToggleButton("questTrackerButton", tr("Open Quest Tracker Window"), "/images/options/button_questlog_tracker", function()
			questLogController:toggleMiniWindowsTracker()
		end, false, 1001)
	end

	if trackerMiniWindow then
		trackerMiniWindow:setupOnStart()
		addEvent(function()
			if trackerMiniWindow and not trackerMiniWindow:isDestroyed() then
				rebuildTrackerFromSettings()
			end
		end)
	elseif settings[namePlayer] and #settings[namePlayer] > 0 then
		showQuestTracker()
		rebuildTrackerFromSettings()
	end

	syncQuestLogTrackerMainPanelButton()
end

function questLogController:onGameEnd()
	save()

	hide()

	if trackerMiniWindow then
		trackerMiniWindow:setParent(nil, true)
	end

	missionToQuestMap = {}
	lastSelectedMissionByQuest = {}
	currentQuestId = nil
	selectedQuestId = nil
	selectedMissionId = nil
	questLogDataLoaded = false
	lastQuestLogSignature = nil
	pendingQuestLogData = nil

	if pendingQuestLogApplyEvent then
		removeEvent(pendingQuestLogApplyEvent)

		pendingQuestLogApplyEvent = nil
	end
end
