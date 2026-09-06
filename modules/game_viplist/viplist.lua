-- chunkname: @/game_viplist/viplist.lua

vipWindow = nil
vipButton = nil
addVipWindow = nil
editVipWindow = nil
vipInfo = {}
addGroupWindow = nil
groupColorRadioGroup = nil
vipGroups = {}
maxVipGroups = 5
editableGroupCount = 1
currentSelectedGroupId = 0

local VIP_GROUP_COLORS = {
	{ color = "#ffffff", name = "White" },
	{ color = "#9e9e9e", name = "Gray" },
	{ color = "#ff4444", name = "Red" },
	{ color = "#ff8800", name = "Orange" },
	{ color = "#ffff44", name = "Yellow" },
	{ color = "#44ff44", name = "Green" },
	{ color = "#00bb55", name = "Dark Green" },
	{ color = "#00e5ff", name = "Cyan" },
	{ color = "#4488ff", name = "Blue" },
	{ color = "#b844ff", name = "Purple" },
	{ color = "#ff44aa", name = "Pink" }
}

local function getHoverHighlightColor(hexColor)
	if not hexColor or hexColor == "" then
		return "#ffffff"
	end
	if hexColor:sub(1, 1) == "#" and #hexColor >= 7 then
		local r = tonumber(hexColor:sub(2, 3), 16) or 255
		local g = tonumber(hexColor:sub(4, 5), 16) or 255
		local b = tonumber(hexColor:sub(6, 7), 16) or 255
		local hr = math.min(255, math.floor(r + (255 - r) * 0.45))
		local hg = math.min(255, math.floor(g + (255 - g) * 0.45))
		local hb = math.min(255, math.floor(b + (255 - b) * 0.45))
		return string.format("#%02x%02x%02x", hr, hg, hb)
	end
	return "#ffffff"
end

local globalSettings = {
	hideOfflineVips = false,
	showGrouped = false,
	groupViewMode = "list",
	vipSortOrder = {}
}

local function normalizeVipSortForSave(value)
	if value == "type" or value == "byType" then
		return "byType"
	elseif value == "status" or value == "byState" then
		return "byState"
	end

	return "byName"
end

function getVipWidgetConfig()
	return {
		hideOfflineVips = globalSettings.hideOfflineVips == true,
		showGrouped = globalSettings.showGrouped == true,
		groupViewMode = globalSettings.groupViewMode or "list",
		vipSortOrder = normalizeVipSortForSave(globalSettings.vipSortOrder and globalSettings.vipSortOrder[1])
	}
end

local function loadVipWidgetConfigFromSidebar()
	globalSettings.showGrouped = false
	globalSettings.groupViewMode = "list"
	globalSettings.hideOfflineVips = false
	globalSettings.vipSortOrder = {}

	if not SidebarPersistence or not SidebarPersistence.getSection then
		return
	end

	local section = SidebarPersistence.getSection("vipWidgetOptions")

	if type(section) ~= "table" then
		return
	end

	globalSettings.showGrouped = section.showGrouped == true
	globalSettings.groupViewMode = section.groupViewMode or "list"
	globalSettings.hideOfflineVips = section.hideOfflineVips == true

	if type(section.vipSortOrder) == "string" and section.vipSortOrder ~= "" then
		globalSettings.vipSortOrder = {
			section.vipSortOrder
		}
	end
end

local function saveVipWidgetConfigToSidebar()
	if not SidebarPersistence or not SidebarPersistence.active then
		return
	end

	if type(SidebarPersistence.document) ~= "table" then
		return
	end

	local section = SidebarPersistence.document.vipWidgetOptions

	if type(section) ~= "table" then
		section = {}
		SidebarPersistence.document.vipWidgetOptions = section
	end

	local cfg = getVipWidgetConfig()

	section.hideOfflineVips = cfg.hideOfflineVips
	section.showGrouped = cfg.showGrouped
	section.groupViewMode = cfg.groupViewMode
	section.vipSortOrder = cfg.vipSortOrder
end

local syncVipMainPanelButton

local function vipStatusDisplayText(vipState)
	if vipState == VipState.Online then
		return tr("Online")
	elseif vipState == VipState.Pending then
		return tr("Pending")
	elseif vipState == VipState.Offline then
		return tr("Offline")
	elseif vipState == VipState.Training then
		return tr("Exercise Dummy Training")
	end

	return tr("Offline")
end

local function getStoredVipDescription(widget)
	local desc = widget.vipDescription

	if desc and desc ~= "" then
		return desc
	end

	local t = widget:getTooltip() or ""

	if t == "" or t:find("Status:", 1, true) then
		return ""
	end

	return t
end

local function applyVipListLabelTooltip(widget)
	if not widget or widget:isDestroyed() then
		return
	end

	local name = widget:getText()

	if not name or name == "" then
		return
	end

	local lines = {
		tr("Name: %s", name),
		tr("Status: %s", vipStatusDisplayText(widget.vipState))
	}
	local desc = widget.vipDescription

	if desc and desc ~= "" then
		table.insert(lines, desc)
	end

	widget.tooltipDelay = 80
	widget:setTooltip(table.concat(lines, "\n"))
end

controllerVip = Controller:new()

function controllerVip:onInit()
	Keybind.new("Windows", "Show/hide VIP list", "Ctrl+P", "")
	Keybind.bind("Windows", "Show/hide VIP list", {
		{
			type = KEY_DOWN,
			callback = toggle
		}
	})

	vipButton = modules.game_mainpanel.addToggleButton("vipListButton", tr("Open VIP List"), "/images/options/button_vip_list", toggle, false, 3)
	vipWindow = g_ui.loadUI("viplist")

	controllerVip:registerEvents(g_game, {
		onAddVip = onAddVip,
		onVipStateChange = onVipStateChange,
		onVipGroupChange = onVipGroupChange
	})
	refresh()
	vipWindow:setup()

	local toggleFilterButton = vipWindow:recursiveGetChildById("toggleFilterButton")

	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
		toggleFilterButton:setOn(false)
	end

	local contextMenuButton = vipWindow:recursiveGetChildById("contextMenuButton")
	local minimizeButton = vipWindow:recursiveGetChildById("minimizeButton")

	if contextMenuButton and minimizeButton then
		contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
		contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
		contextMenuButton:setMarginRight(5)

		function contextMenuButton.onClick(widget, mousePos, mouseButton)
			return onVipListMousePress(widget, mousePos or widget:getPosition(), MouseRightButton)
		end
	end

	local lockButton = vipWindow:recursiveGetChildById("lockButton")

	if lockButton and contextMenuButton then
		lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
		lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
		lockButton:setMarginRight(2)
	end

	local newWindowButton = vipWindow:recursiveGetChildById("newWindowButton")

	if newWindowButton then
		newWindowButton:setVisible(false)
	end

	if g_game.isOnline() then
		vipWindow:setupOnStart()
	end

	connect(vipWindow, {
		onGeometryChange = function()
			if globalSettings.showGrouped and globalSettings.groupViewMode == "buttons" then
				updateGroupScroll(0)
			end
		end
	})

	syncVipMainPanelButton()
end

function controllerVip:onTerminate()
	Keybind.delete("Windows", "Show/hide VIP list")

	local ArrayWidgets = {
		addVipWindow,
		editVipWindow,
		vipWindow,
		vipButton,
		addGroupWindow
	}

	for _, widget in ipairs(ArrayWidgets) do
		if widget ~= nil or widget then
			widget:destroy()

			widget = nil
		end
	end

	vipInfo = {}
end

function controllerVip:onGameStart()
	loadVipWidgetConfigFromSidebar()

	if not g_game.getFeature(GameAdditionalVipInfo) then
		loadVipInfo()
	end

	if not g_game.getFeature(GameVipGroups) then
		vipWindow.miniborder:show()
		maxVipGroups = 20
	else
		vipInfo = {}
	end

	vipWindow:setupOnStart()
	refresh()
	syncVipMainPanelButton()
end

function controllerVip:onGameEnd()
	saveVipWidgetConfigToSidebar()

	if not g_game.getFeature(GameVipGroups) then
		saveVipInfo()
	end

	if not SidebarPersistence or not SidebarPersistence.lastSessionActive then
		vipWindow:setParent(nil, true)
	end

	clear()

	if editVipWindow then
		editVipWindow:destroy()

		editVipWindow = nil
	end

	if addGroupWindow then
		addGroupWindow:destroy()

		addGroupWindow = nil
	end
end

local function normalizePlayerGroups(val, jsonVal)
	if jsonVal and type(jsonVal) == "string" and #jsonVal > 0 then
		local ok, decoded = pcall(json.decode, jsonVal)
		if ok and type(decoded) == "table" then
			local res = {}
			for _, g in pairs(decoded) do
				local num = tonumber(g)
				if num then
					table.insert(res, num)
				end
			end
			return res
		end
	end

	if type(val) == "table" then
		local res = {}
		for _, g in pairs(val) do
			local num = tonumber(g)
			if num then
				table.insert(res, num)
			end
		end
		return res
	elseif type(val) == "number" then
		return { val }
	elseif type(val) == "string" and #val > 0 then
		local res = {}
		for num in val:gmatch("%S+") do
			local n = tonumber(num)
			if n then
				table.insert(res, n)
			end
		end
		return res
	end

	return {}
end

function loadVipInfo()
	local settings = g_settings.getNode("VipList")

	if not settings then
		vipInfo = {}
		if not g_game.getFeature(GameVipGroups) then
			vipGroups = {
				{ 1, "Friends", true, "#ffffff" },
				{ 2, "Enemies", true, "#ffffff" }
			}
			maxVipGroups = 20
			globalSettings.showGrouped = true
		end

		return
	end

	vipInfo = settings.VipInfo or {}
	for name, data in pairs(vipInfo) do
		if type(data) == "table" then
			data.vipGroups = normalizePlayerGroups(data.vipGroups, data.vipGroupsJson)
		end
	end

	if not g_game.getFeature(GameVipGroups) then
		local loadedGroups = nil
		if settings.VipGroupsJson and type(settings.VipGroupsJson) == "string" and #settings.VipGroupsJson > 0 then
			local ok, decoded = pcall(json.decode, settings.VipGroupsJson)
			if ok and type(decoded) == "table" then
				loadedGroups = decoded
			end
		end

		if (not loadedGroups or #loadedGroups == 0) and type(settings.VipGroups) == "table" then
			loadedGroups = {}
			for k, g in pairs(settings.VipGroups) do
				if type(g) == "table" then
					local gid = tonumber(g[1] or g["1"] or k)
					local gname = tostring(g[2] or g["2"] or g.name or "")
					local gedit = g[3] ~= false and g["3"] ~= false
					local gcolor = tostring(g[4] or g["4"] or g.color or "#ffffff")
					if gid and gname ~= "" then
						table.insert(loadedGroups, { gid, gname, gedit, gcolor })
					end
				end
			end
			table.sort(loadedGroups, function(a, b)
				return a[1] < b[1]
			end)
		end

		if loadedGroups and #loadedGroups > 0 then
			for _, g in ipairs(loadedGroups) do
				if not g[4] or g[4] == "" then
					g[4] = "#ffffff"
				end
			end
			vipGroups = loadedGroups
		else
			vipGroups = {
				{ 1, "Friends", true, "#ffffff" },
				{ 2, "Enemies", true, "#ffffff" }
			}
		end

		maxVipGroups = 20
		if settings.showGrouped ~= nil then
			globalSettings.showGrouped = settings.showGrouped
		else
			globalSettings.showGrouped = true
		end
		if settings.groupViewMode ~= nil then
			globalSettings.groupViewMode = settings.groupViewMode
		else
			globalSettings.groupViewMode = "list"
		end
	end
end

function saveVipInfo()
	if not g_game.getFeature(GameAdditionalVipInfo) then
		if not g_settings.getNode("VipList") then
			g_settings.setNode("VipList", {})
		end

		local saveInfo = {}
		for name, data in pairs(vipInfo) do
			if type(data) == "table" then
				local groupsArr = normalizePlayerGroups(data.vipGroups, data.vipGroupsJson)
				saveInfo[name] = {
					playerId = data.playerId,
					playerName = data.playerName or name,
					vipState = data.vipState,
					vipDesc = data.vipDesc or data.description or "",
					description = data.description or data.vipDesc or "",
					icon = data.icon or data.iconId or 0,
					iconId = data.iconId or data.icon or 0,
					hasNotify = data.hasNotify or data.notifyLogin or false,
					notifyLogin = data.notifyLogin or data.hasNotify or false,
					vipGroups = table.concat(groupsArr, " "),
					vipGroupsJson = json.encode(groupsArr)
				}
			end
		end

		local settings = {
			VipInfo = saveInfo,
			VipGroups = vipGroups,
			VipGroupsJson = json.encode(vipGroups),
			showGrouped = globalSettings.showGrouped,
			groupViewMode = globalSettings.groupViewMode or "list"
		}

		g_settings.mergeNode("VipList", settings)
		g_settings.save()
	end
end

function refresh()
	clear()

	for id, vip in pairs(g_game.getVips()) do
		local name = vip[1]
		local state = vip[2]
		local description = vip[3]
		local iconId = vip[4]
		local notify = vip[5]
		local groupID = vip[6]

		if not vipInfo[name] then
			local savedGroups = normalizePlayerGroups(groupID)
			vipInfo[name] = {
				playerId = id,
				playerName = name,
				vipState = state,
				vipDesc = description or "",
				description = description or "",
				icon = iconId or 0,
				iconId = iconId or 0,
				hasNotify = notify or false,
				notifyLogin = notify or false,
				vipGroups = savedGroups,
				vipGroupsJson = json.encode(savedGroups)
			}
		else
			vipInfo[name].playerId = id
			vipInfo[name].vipState = state
		end
	end

	showGroups()
	vipWindow:setContentMinimumHeight(38)
end

function clear()
	local vipList = vipWindow:getChildById("contentsPanel")

	vipList:destroyChildren()

	if not g_game.isOnline() and g_game.getFeature(GameAdditionalVipInfo) then
		vipInfo = {}
		vipGroups = {}
	end

	if editVipWindow ~= nil or editVipWindow then
		editVipWindow:hide()
	end
end

function syncVipMainPanelButton()
	if SidebarWidgetOptions and SidebarWidgetOptions.syncToggleButton then
		SidebarWidgetOptions.syncToggleButton(vipWindow, vipButton, "Open VIP List", "Close VIP List")

		return
	end

	if not vipButton or vipButton:isDestroyed() then
		return
	end

	local on = false

	if vipWindow and not vipWindow:isDestroyed() then
		on = vipWindow:isVisible()
	end

	vipButton:setOn(on)

	if vipButton.setTooltip then
		vipButton:setTooltip(tr(on and "Close VIP List" or "Open VIP List"))
	end
end

function toggle()
	if vipButton:isOn() then
		vipWindow:closeAndForgetLayout()
	else
		if not vipWindow:getParent() then
			local panel = modules.game_interface.findContentPanelAvailable(vipWindow, vipWindow:getMinimumHeight())

			if not panel then
				return
			end

			panel:addChild(vipWindow)
		end

		vipWindow:open()
	end

	syncVipMainPanelButton()
end

function onMiniWindowOpen()
	syncVipMainPanelButton()
	if globalSettings.showGrouped and globalSettings.groupViewMode == "buttons" then
		updateGroupScroll(0)
	end
end

function onMiniWindowClose()
	syncVipMainPanelButton()
end

local function focusFloatingNameInput(window, nameInput, selectAll)
	if not window or window:isDestroyed() or not nameInput or nameInput:isDestroyed() then
		return
	end

	window:raise()
	window:focus()
	window:grabKeyboard()
	window:focusChild(nameInput, KeyboardFocusReason)

	if selectAll then
		nameInput:selectAll()
	else
		nameInput:setCursorPos(-1)
	end
end

function createAddWindow()
	if addVipWindow then
		addVipWindow:destroy()

		addVipWindow = nil
	end

	addVipWindow = g_ui.displayUI("addvip")
	if not addVipWindow then
		return
	end

	addVipWindow:show()

	local nameInput = addVipWindow:getChildById("name")

	nameInput:setText("")
	focusFloatingNameInput(addVipWindow, nameInput)
	scheduleEvent(function()
		focusFloatingNameInput(addVipWindow, nameInput)
	end, 50)

	local function closeWindow()
		pcall(function()
			addVipWindow:ungrabKeyboard()
		end)
		nameInput:setText("")
		addVipWindow:setVisible(false)
		addVipWindow:destroy()

		addVipWindow = nil
	end

	function addVipWindow.buttonOk.onClick()
		local playerName = nameInput:getText()

		if playerName and playerName ~= "" then
			g_game.addVip(playerName)
		end

		closeWindow()
	end

	addVipWindow.closeButton.onClick = closeWindow
	addVipWindow.onEscape = closeWindow

	function nameInput.onKeyDown(widget, keyCode, keyboardModifiers)
		if g_keyboard.isEnterKey(keyCode) then
			addVipWindow.buttonOk.onClick()

			return true
		elseif keyCode == KeyEscape then
			closeWindow()

			return true
		end

		return false
	end
end

function createEditWindow(widget)
	if editVipWindow then
		return
	end

	editVipWindow = g_ui.displayUI("editvip")
	if not editVipWindow then
		return
	end

	local name = widget:getText()
	local id = widget:getId():sub(4)

	local editVipBaseWidth = 285
	local editVipBaseHeight = 340
	local editVipHeightPerGroup = 18

	editVipWindow.groups:destroyChildren()
	table.sort(vipGroups, function(a, b)
		return a[1] < b[1]
	end)

	for _, group in ipairs(vipGroups) do
		local groupBox = g_ui.createWidget("VipGroupBox", editVipWindow.groups)

		groupBox:setText(group[2])
		if group[4] and group[4] ~= "" then
			groupBox:setColor(group[4])
		end

		groupBox.id = group[1]

		groupBox:setChecked(checkPlayerGroup(name, group[1]))
	end

	local numGroups = #vipGroups
	if numGroups == 0 then
		if editVipWindow.groupsLabel then editVipWindow.groupsLabel:hide() end
		if editVipWindow.groups then editVipWindow.groups:hide() end
		if editVipWindow.separator2 then editVipWindow.separator2:hide() end
		editVipWindow:setSize(string.format("%d %d", editVipBaseWidth, 290))
	else
		if editVipWindow.groupsLabel then editVipWindow.groupsLabel:show() end
		if editVipWindow.groups then editVipWindow.groups:show() end
		if editVipWindow.separator2 then editVipWindow.separator2:show() end
		editVipWindow:setSize(string.format("%d %d", editVipBaseWidth, editVipBaseHeight + editVipHeightPerGroup * numGroups))
	end

	local okButton = editVipWindow:getChildById("buttonOK")
	local cancelButton = editVipWindow:getChildById("buttonCancel")
	local nameLabel = editVipWindow:getChildById("nameLabel")

	nameLabel:setText(name)

	local descriptionText = editVipWindow:getChildById("descriptionText")
	local descriptionWarnLabel = editVipWindow:getChildById("descriptionWarnLabel")

	local function updateDescriptionValidation()
		if not descriptionText or not descriptionWarnLabel then
			return
		end

		local text = descriptionText:getText()
		local len = #text
		if len >= 1 then
			descriptionWarnLabel:setColoredText("{" .. tr("Characters:") .. " , #c0c0c0}{(" .. len .. "/40), #ffffff}")
		else
			descriptionWarnLabel:setText("")
		end
		if okButton then
			okButton:setEnabled(true)
		end
	end

	if descriptionText then
		descriptionText:setMaxLength(40)
		descriptionText:appendText(getStoredVipDescription(widget))
		descriptionText.onTextChange = function(w, newText, oldText)
			updateDescriptionValidation()
		end
	end

	updateDescriptionValidation()

	local notifyCheckBox = editVipWindow:recursiveGetChildById("checkBoxNotify")

	notifyCheckBox:setChecked(widget.notifyLogin)

	local iconRadioGroup = UIRadioGroup.create()

	for i = VipIconFirst, VipIconLast do
		iconRadioGroup:addWidget(editVipWindow:recursiveGetChildById("icon" .. i))
	end

	if not widget.iconId then
		widget.iconId = 0
	end

	iconRadioGroup:selectWidget(editVipWindow:recursiveGetChildById("icon" .. widget.iconId))

	local function cancelFunction()
		editVipWindow:destroy()
		iconRadioGroup:destroy()

		editVipWindow = nil
	end

	local function saveFunction()
		local vipList = vipWindow:getChildById("contentsPanel")

		if not widget then
			cancelFunction()

			return
		end

		local description = descriptionText and descriptionText:getText() or ""

		local name = widget:getText()
		local state = widget.vipState
		local iconId = tonumber(iconRadioGroup:getSelectedWidget():getId():sub(5))

		iconId = iconId or 0

		local notify = notifyCheckBox:isChecked()
		local groups = {}

		for _, child in pairs(editVipWindow.groups:getChildren()) do
			if child:isChecked() then
				table.insert(groups, tonumber(child.id) or child.id)
			end
		end

		if g_game.getFeature(GameAdditionalVipInfo) then
			g_game.editVip(id, description, iconId, notify, groups)
		else
			vipInfo[name] = {
				playerId = id,
				playerName = name,
				vipState = state,
				vipDesc = description,
				description = description,
				icon = iconId,
				iconId = iconId,
				hasNotify = notify,
				notifyLogin = notify,
				vipGroups = groups,
				vipGroupsJson = json.encode(groups)
			}
			saveVipInfo()
		end

		widget:destroy()
		onAddVip(id, name, state, description, iconId, notify, groups, nil)

		if iconRadioGroup then
			iconRadioGroup:destroy()

			iconRadioGroup = nil
		end

		if editVipWindow then
			editVipWindow:destroy()

			editVipWindow = nil
		end
	end

	cancelButton.onClick = cancelFunction
	okButton.onClick = saveFunction
	editVipWindow.onEscape = cancelFunction
	editVipWindow.onEnter = saveFunction
end

function destroyAddWindow()
	if addVipWindow then
		addVipWindow:setVisible(false)
		addVipWindow:destroy()

		addVipWindow = nil
	end
end

function addVip()
	if addVipWindow then
		local nameInput = addVipWindow:getChildById("name")
		local playerName = nameInput:getText()

		if playerName and playerName ~= "" then
			g_game.addVip(playerName)
			destroyAddWindow()
		end
	end
end

local function removeVipFromInfo(playerId, name)
	if g_game.getFeature(GameAdditionalVipInfo) then
		for key, data in pairs(vipInfo) do
			if type(data) == "table" and tonumber(data.playerId) == playerId then
				vipInfo[key] = nil

				return
			end
		end
	end

	if name then
		vipInfo[name] = nil
	end
end

function removeVip(widgetOrName)
	if not widgetOrName then
		return
	end

	local widget
	local vipList = vipWindow:getChildById("contentsPanel")

	if type(widgetOrName) == "string" then
		local entries = vipList:getChildren()

		for i = 1, #entries do
			if entries[i]:getText():lower() == widgetOrName:lower() then
				widget = entries[i]

				break
			end
		end

		if not widget then
			return
		end
	else
		widget = widgetOrName
	end

	if widget then
		local id = tonumber(widget:getId():sub(4))

		if not id then
			return
		end

		local name = widget:getText()

		g_game.removeVip(id)
		removeVipFromInfo(id, name)
		saveVipInfo()
		refresh()
	end
end

function hideOffline(state)
	globalSettings.hideOfflineVips = state

	refresh()
end

function isHiddingOffline()
	local settings = g_settings.getNode("VipList")

	if not settings then
		return false
	end

	return settings.hideOffline
end

function getSortedBy()
	if g_game.getFeature(GameAdditionalVipInfo) then
		if not globalSettings.vipSortOrder then
			return ""
		end

		return globalSettings.vipSortOrder[1]
	else
		local settings = g_settings.getNode("VipList")

		if not settings or not settings.sortedBy then
			return "status"
		end

		return settings.sortedBy
	end
end

function sortBy(state)
	if not g_game.getFeature(GameAdditionalVipInfo) then
		local settings = {}

		settings.sortedBy = state

		g_settings.mergeNode("VipList", settings)
	end

	for i, v in ipairs(globalSettings.vipSortOrder) do
		if v == state then
			table.remove(globalSettings.vipSortOrder, i)

			break
		end
	end

	table.insert(globalSettings.vipSortOrder, 1, state)

	local contentPanel = vipWindow:getChildById("contentsPanel")
	if not contentPanel then
		return
	end

	if globalSettings.showGrouped and globalSettings.groupViewMode == "list" then
		for _, groupWidget in ipairs(contentPanel:getChildren()) do
			if groupWidget:getId():find("group") == 1 then
				local groupPanel = groupWidget:getChildById("panel")
				if groupPanel then
					local children = groupPanel:getChildren()
					table.sort(children, compareVips)
					for i, child in ipairs(children) do
						groupPanel:moveChildToIndex(child, i)
					end
				end
			end
		end
	else
		local children = contentPanel:getChildren()
		table.sort(children, compareVips)
		for i, child in ipairs(children) do
			contentPanel:moveChildToIndex(child, i)
		end
	end

	contentPanel:updateLayout()
end

function compareVips(a, b)
	for _, orderType in ipairs(globalSettings.vipSortOrder) do
		if orderType == "byState" or orderType == "status" then
			if a.vipState ~= nil and b.vipState ~= nil and a.vipState ~= b.vipState then
				return a.vipState > b.vipState
			end
		elseif orderType == "byName" or orderType == "name" then
			if a:getText() ~= nil and b:getText() ~= nil and a:getText():lower() ~= b:getText():lower() then
				return a:getText():lower() < b:getText():lower()
			end
		elseif (orderType == "byType" or orderType == "type") and a.iconId ~= nil and b.iconId ~= nil and a.iconId ~= b.iconId then
			return a.iconId > b.iconId
		end
	end

	return false
end

function onAddVip(id, name, state, description, iconId, notify, groupID, bool)
	if g_game.getFeature(GameAdditionalVipInfo) then
		vipInfo[name] = {
			playerId = id,
			playerName = name,
			vipState = state,
			vipDesc = description,
			icon = iconId,
			hasNotify = notify,
			vipGroups = groupID
		}

		if globalSettings.showGrouped then
			showGroups()

			return
		end
	else
		local tmp = vipInfo[name] or {}
		local savedGroups = normalizePlayerGroups(tmp.vipGroups, tmp.vipGroupsJson)
		if #savedGroups == 0 and groupID then
			savedGroups = normalizePlayerGroups(groupID)
		end

		vipInfo[name] = {
			playerId = id,
			playerName = name,
			vipState = state,
			vipDesc = tmp.description or tmp.vipDesc or description or "",
			description = tmp.description or tmp.vipDesc or description or "",
			icon = tmp.iconId or tmp.icon or iconId or 0,
			iconId = tmp.iconId or tmp.icon or iconId or 0,
			hasNotify = (tmp.notifyLogin ~= nil and tmp.notifyLogin) or (tmp.hasNotify ~= nil and tmp.hasNotify) or notify or false,
			notifyLogin = (tmp.notifyLogin ~= nil and tmp.notifyLogin) or (tmp.hasNotify ~= nil and tmp.hasNotify) or notify or false,
			vipGroups = savedGroups,
			vipGroupsJson = json.encode(savedGroups)
		}

		if globalSettings.showGrouped then
			showGroups()

			return
		end
	end

	local vipList = vipWindow:getChildById("contentsPanel")
	local childrenContentPanel = vipList:getChildCount()

	if bool then
		for i = 1, childrenContentPanel do
			local vipName = vipList:getChildByIndex(i)

			if vipName:getText() == name then
				setVipState(vipName, state)

				if state == VipState.Online then
					vipName:setVisible(true)
				elseif state == VipState.Offline and globalSettings.hideOfflineVips then
					vipName:setVisible(false)
				end

				return
			end
		end
	end

	for j = 1, childrenContentPanel do
		if vipList:getChildByIndex(j):getText() == name then
			return
		end
	end

	local label = g_ui.createWidget("VipListLabel")

	label.onMousePress = onVipListLabelMousePress

	label:setId("vip" .. id)
	label:setText(name)

	if not g_game.getFeature(GameAdditionalVipInfo) then
		local tmpVipInfo = vipInfo[name]

		label.iconId = 0
		label.notifyLogin = false
		label.vipDescription = ""

		if tmpVipInfo then
			if tmpVipInfo.iconId then
				label:setImageClip(torect(tmpVipInfo.iconId * 12 .. " 0 12 12"))

				label.iconId = tmpVipInfo.iconId
			end

			if tmpVipInfo.description then
				label.vipDescription = tmpVipInfo.description
			end

			label.notifyLogin = tmpVipInfo.notifyLogin or false
		end
	else
		label.vipDescription = description or ""

		label:setImageClip(torect(iconId * 12 .. " 0 12 12"))

		label.iconId = iconId
		label.notifyLogin = notify
	end

	setVipState(label, state)
	label:setPhantom(false)
	connect(label, {
		onDoubleClick = function()
			g_game.openPrivateChannel(label:getText())

			return true
		end
	})

	if state == VipState.Offline and globalSettings.hideOfflineVips then
		label:setVisible(false)
	end

	local nameLower = name:lower()
	local childrenCount = vipList:getChildCount()

	for i = 1, childrenCount do
		local child = vipList:getChildByIndex(i)

		if state == VipState.Online and child.vipState ~= VipState.Online and getSortedBy() == "status" or label.iconId > child.iconId and getSortedBy() == "type" then
			vipList:insertChild(i, label)

			return
		end

		if (state ~= VipState.Online and child.vipState ~= VipState.Online or state == VipState.Online and child.vipState == VipState.Online) and getSortedBy() == "status" or label.iconId == child.iconId and getSortedBy() == "type" or getSortedBy() == "name" then
			local childText = child:getText():lower()
			local length = math.min(childText:len(), nameLower:len())

			for j = 1, length do
				if nameLower:byte(j) < childText:byte(j) then
					vipList:insertChild(i, label)

					return
				elseif nameLower:byte(j) > childText:byte(j) then
					break
				elseif j == nameLower:len() then
					vipList:insertChild(i, label)

					return
				end
			end
		end
	end

	vipList:insertChild(childrenCount + 1, label)
end

function onVipStateChange(id, state, groupID)
	if globalSettings.showGrouped then
		local name, description, iconId, notify = searchPlayerbyId(id)

		onAddVip(id, name, state, description, iconId, notify, groupID, true)
	else
		local vipList = vipWindow:getChildById("contentsPanel")
		local label = vipList:getChildById("vip" .. id)
		if not label then
			return
		end
		local name = label:getText()
		local description = getStoredVipDescription(label)
		local iconId = label.iconId
		local notify = label.notifyLogin

		label:destroy()
		onAddVip(id, name, state, description, iconId, notify)
	end

	if notify and state ~= VipState.Pending then
		modules.game_textmessage.displayFailureMessage(state == VipState.Online and tr("%s has logged in.", name) or tr("%s has logged out.", name))
	end
end

function onVipListMousePress(widget, mousePos, mouseButton)
	if mouseButton ~= MouseRightButton then
		return
	end

	local vipList = vipWindow:getChildById("contentsPanel")
	local menu = g_ui.createWidget("PopupMenu")

	menu:setGameMenu(true)
	menu:addOption(tr("Add new VIP"), function()
		createAddWindow()
	end)
	menu:addSeparator()

	menu:addOption(tr("Add new group"), function()
		createAddGroupWindow()
	end)

	menu:addSeparator()
	menu:addOption(tr("Sort by name"), function()
		sortBy("name")
	end)
	menu:addOption(tr("Sort by type"), function()
		sortBy("type")
	end)
	menu:addOption(tr("Sort by status"), function()
		sortBy("status")
	end)

	if not globalSettings.hideOfflineVips then
		menu:addOption(tr("Hide offline VIPs"), function()
			hideOffline(true)
		end)
	else
		menu:addOption(tr("Show offline VIPs"), function()
			hideOffline(false)
		end)
	end

	if not globalSettings.showGrouped then
		menu:addOption(tr("Show groups"), function()
			globalSettings.showGrouped = true
			if not g_game.getFeature(GameVipGroups) then
				saveVipInfo()
			end
			refresh()
		end)
	else
		menu:addOption(tr("Hide groups"), function()
			globalSettings.showGrouped = false
			if not g_game.getFeature(GameVipGroups) then
				saveVipInfo()
			end
			refresh()
		end)

		if globalSettings.groupViewMode == "buttons" then
			menu:addOption(tr("Groups List"), function()
				globalSettings.groupViewMode = "list"
				if not g_game.getFeature(GameVipGroups) then
					saveVipInfo()
				end
				refresh()
			end)
		else
			menu:addOption(tr("Groups Buttons"), function()
				globalSettings.groupViewMode = "buttons"
				if not g_game.getFeature(GameVipGroups) then
					saveVipInfo()
				end
				refresh()
			end)
		end
	end

	local menuPos = {
		x = mousePos.x,
		y = mousePos.y
	}
	local menuSize = menu:getSize()
	local screenSize = g_window.getSize()

	if menuPos.x + menuSize.width > screenSize.width then
		menuPos.x = screenSize.width - menuSize.width
	end

	if menuPos.y + menuSize.height > screenSize.height then
		menuPos.y = screenSize.height - menuSize.height
	end

	if menuPos.x < 0 then
		menuPos.x = 0
	end

	if menuPos.y < 0 then
		menuPos.y = 0
	end

	menu:display(menuPos)

	return true
end

function onVipListLabelMousePress(widget, mousePos, mouseButton)
	if mouseButton ~= MouseRightButton then
		return
	end

	local vipList = vipWindow:getChildById("contentsPanel")
	local isGroup = string.find(widget:getId(), "group")
	local isVip = string.find(widget:getId(), "vip")
	local menu = g_ui.createWidget("PopupMenu")

	menu:setGameMenu(true)

	if not isGroup then
		if isVip and widget.vipState == VipState.Online then
			menu:addOption(tr("Exiva %s", widget:getText()), function()
				g_game.talk(string.format("exiva \"%s\"", widget:getText()), true)
			end)
		end

		menu:addOption(tr("Edit %s", widget:getText()), function()
			if widget then
				createEditWindow(widget)
			end
		end)
		menu:addOption(tr("Remove %s", widget:getText()), function()
			if widget then
				removeVip(widget)
			end
		end)

		if isVip and widget.vipState == VipState.Online then
			menu:addOption(tr("Message to %s", widget:getText()), function()
				g_game.openPrivateChannel(widget:getText())
			end)
			menu:addOption(tr("Invite %s to Party", widget:getText()), function()
				g_game.partyInvite(tonumber(widget:getId():sub(4)))
			end)
		end
	end

	menu:addOption(tr("Add new VIP"), function()
		createAddWindow()
	end)

	menu:addSeparator()

	if isGroup and widget.editable then
		local groupName = widget:getTooltip() and widget:getTooltip() or widget.group:getText()

		menu:addOption(tr("Edit group %s", groupName), function()
			createEditGroupWindow(groupName, widget.groupId)
		end)
		menu:addOption(tr("Remove group %s", groupName), function()
			clientRemoveVipGroup(widget.groupId)
		end)
	end

	menu:addOption(tr("Add new group"), function()
		createAddGroupWindow()
	end)

	menu:addSeparator()
	menu:addOption(tr("Sort by name"), function()
		sortBy("name")
	end)
	menu:addOption(tr("Sort by type"), function()
		sortBy("type")
	end)
	menu:addOption(tr("Sort by status"), function()
		sortBy("status")
	end)

	if not globalSettings.hideOfflineVips then
		menu:addOption(tr("Hide offline VIPs"), function()
			hideOffline(true)
		end)
	else
		menu:addOption(tr("Show offline VIPs"), function()
			hideOffline(false)
		end)
	end

	if not globalSettings.showGrouped then
		menu:addOption(tr("Show groups"), function()
			globalSettings.showGrouped = true
			if not g_game.getFeature(GameVipGroups) then
				saveVipInfo()
			end
			refresh()
		end)
	else
		menu:addOption(tr("Hide groups"), function()
			globalSettings.showGrouped = false
			if not g_game.getFeature(GameVipGroups) then
				saveVipInfo()
			end
			refresh()
		end)

		if globalSettings.groupViewMode == "buttons" then
			menu:addOption(tr("Groups List"), function()
				globalSettings.groupViewMode = "list"
				if not g_game.getFeature(GameVipGroups) then
					saveVipInfo()
				end
				refresh()
			end)
		else
			menu:addOption(tr("Groups Buttons"), function()
				globalSettings.groupViewMode = "buttons"
				if not g_game.getFeature(GameVipGroups) then
					saveVipInfo()
				end
				refresh()
			end)
		end
	end

	if not isGroup then
		menu:addSeparator()
		menu:addOption(tr("Copy Name"), function()
			g_window.setClipboardText(widget:getText())
		end)
	end

	local menuPos = {
		x = mousePos.x,
		y = mousePos.y
	}
	local menuSize = menu:getSize()
	local screenSize = g_window.getSize()

	if menuPos.x + menuSize.width > screenSize.width then
		menuPos.x = screenSize.width - menuSize.width
	end

	if menuPos.y + menuSize.height > screenSize.height then
		menuPos.y = screenSize.height - menuSize.height
	end

	if menuPos.x < 0 then
		menuPos.x = 0
	end

	if menuPos.y < 0 then
		menuPos.y = 0
	end

	menu:display(menuPos)

	return true
end

function onVipGroupChange(vipGroupsArray, groupsAmountLeft)
	vipGroups = vipGroupsArray
	maxVipGroups = groupsAmountLeft
	editableGroupCount = groupsAmountLeft

	refresh()
end

function clientAddVipGroup(groupName, color)
	if not groupName or groupName == "" then
		return
	end

	if g_game.getFeature(GameVipGroups) then
		g_game.editVipGroups(1, 0, groupName)
		return
	end

	local nextId = 1
	for _, g in ipairs(vipGroups) do
		if g[1] >= nextId then
			nextId = g[1] + 1
		end
	end

	table.insert(vipGroups, { nextId, groupName, true, color or "#ffffff" })
	saveVipInfo()
	refresh()
end

function clientEditVipGroup(groupId, newGroupName, color)
	if not newGroupName or newGroupName == "" then
		return
	end

	if g_game.getFeature(GameVipGroups) then
		g_game.editVipGroups(2, groupId, newGroupName)
		return
	end

	for _, g in ipairs(vipGroups) do
		if g[1] == groupId then
			g[2] = newGroupName
			if color and color ~= "" then
				g[4] = color
			end
			break
		end
	end

	saveVipInfo()
	refresh()
end

function clientRemoveVipGroup(groupId)
	if g_game.getFeature(GameVipGroups) then
		g_game.editVipGroups(3, groupId, "")
		return
	end

	if currentSelectedGroupId == groupId then
		currentSelectedGroupId = 0
	end

	for i, g in ipairs(vipGroups) do
		if g[1] == groupId then
			table.remove(vipGroups, i)
			break
		end
	end

	for _, v in pairs(vipInfo) do
		if v.vipGroups then
			for j, gid in ipairs(v.vipGroups) do
				if gid == groupId then
					table.remove(v.vipGroups, j)
					break
				end
			end
		end
	end

	saveVipInfo()
	refresh()
end

local function setupGroupColorPalette(window, selectedColor)
	if groupColorRadioGroup then
		groupColorRadioGroup:destroy()
		groupColorRadioGroup = nil
	end

	local colorPanel = window:getChildById("colorPanel")
	if not colorPanel then
		return
	end

	colorPanel:destroyChildren()
	groupColorRadioGroup = UIRadioGroup.create()

	local targetColor = (selectedColor or "#ffffff"):lower()
	local selectedWidget = nil

	for _, col in ipairs(VIP_GROUP_COLORS) do
		local colorBox = g_ui.createWidget("ColorBox", colorPanel)
		colorBox:setBackgroundColor(col.color)
		colorBox.tooltipDelay = 80
		colorBox:setTooltip(tr(col.name))
		colorBox.colorHex = col.color

		colorBox.onHoverChange = function(widget, hovered)
			if groupColorRadioGroup and widget ~= groupColorRadioGroup:getSelectedWidget() then
				if hovered then
					widget:setBorderWidth(1)
					widget:setBorderColor("#d0d0d0")
				else
					widget:setBorderWidth(0)
					widget:setBorderColor("alpha")
				end
			end
		end

		groupColorRadioGroup:addWidget(colorBox)

		if col.color:lower() == targetColor then
			selectedWidget = colorBox
		end
	end

	groupColorRadioGroup.onSelectionChange = function(self, newWidget, oldWidget)
		if oldWidget then
			oldWidget:setChecked(false)
			oldWidget:setBorderWidth(0)
			oldWidget:setBorderColor("alpha")
		end
		if newWidget then
			newWidget:setChecked(true)
			newWidget:setBorderWidth(1)
			newWidget:setBorderColor("white")
		end
	end

	if not selectedWidget then
		selectedWidget = groupColorRadioGroup:getFirstWidget()
	end

	if selectedWidget then
		groupColorRadioGroup:selectWidget(selectedWidget)
	end
end

function createAddGroupWindow()
	if not g_game.getFeature(GameVipGroups) then
		maxVipGroups = 20
	end

	if maxVipGroups < 1 then
		displayInfoBox(tr("Maximum of User-Created Groups Reached"), "You have already reached the maximum of groups you can create yourself.")

		return
	end

	if addGroupWindow then
		destroyAddGroupWindow()
	end

	addGroupWindow = g_ui.displayUI("addgroup")
	if not addGroupWindow then
		return
	end

	addGroupWindow:show()
	setupGroupColorPalette(addGroupWindow, "#ffffff")

	local nameInput = addGroupWindow:getChildById("name")
	local nameWarnLabel = addGroupWindow:getChildById("nameWarnLabel")
	local okButton = addGroupWindow:getChildById("buttonOk")

	local function updateGroupNameValidation()
		if not nameInput or not nameWarnLabel then
			return
		end

		local text = nameInput:getText()
		local len = #text
		if len >= 1 then
			nameWarnLabel:setColoredText("{" .. tr("Characters:") .. " , #c0c0c0}{(" .. len .. "/15), #ffffff}")
		else
			nameWarnLabel:setText("")
		end
		if okButton then
			okButton:setEnabled(len > 0)
		end
	end

	nameInput:setMaxLength(15)
	nameInput:setText("")
	updateGroupNameValidation()

	nameInput.onTextChange = function(widget, newText)
		updateGroupNameValidation()
	end

	focusFloatingNameInput(addGroupWindow, nameInput)
	scheduleEvent(function()
		focusFloatingNameInput(addGroupWindow, nameInput)
	end, 50)

	local function closeWindow()
		destroyAddGroupWindow()
	end

	addGroupWindow.closeButton.onClick = closeWindow
	addGroupWindow.onEscape = closeWindow

	function nameInput.onKeyDown(widget, keyCode, keyboardModifiers)
		if g_keyboard.isEnterKey(keyCode) then
			if #widget:getText():trim() > 0 then
				addGroup()
			end

			return true
		elseif keyCode == KeyEscape then
			closeWindow()

			return true
		end

		return false
	end
end

function createEditGroupWindow(groupName, groupId)
	if addGroupWindow then
		destroyAddGroupWindow()
	end

	addGroupWindow = g_ui.displayUI("addgroup")
	if not addGroupWindow then
		return
	end

	addGroupWindow:show()

	local headerLabel = addGroupWindow:getChildById("headerLabel")

	if headerLabel then
		headerLabel:setText(tr("Edit VIP Group"))
	end

	local currentColor = "#ffffff"
	for _, g in ipairs(vipGroups) do
		if g[1] == groupId and g[4] then
			currentColor = g[4]
			break
		end
	end
	setupGroupColorPalette(addGroupWindow, currentColor)

	local nameInput = addGroupWindow:getChildById("name")
	local nameWarnLabel = addGroupWindow:getChildById("nameWarnLabel")
	local okButton = addGroupWindow:getChildById("buttonOk")

	local function updateGroupNameValidation()
		if not nameInput or not nameWarnLabel then
			return
		end

		local text = nameInput:getText()
		local len = #text
		if len >= 1 then
			nameWarnLabel:setColoredText("{" .. tr("Characters:") .. " , #c0c0c0}{(" .. len .. "/15), #ffffff}")
		else
			nameWarnLabel:setText("")
		end
		if okButton then
			okButton:setEnabled(len > 0)
		end
	end

	nameInput:setMaxLength(15)
	nameInput:setText(groupName or "")
	updateGroupNameValidation()

	nameInput.onTextChange = function(widget, newText)
		updateGroupNameValidation()
	end

	focusFloatingNameInput(addGroupWindow, nameInput, true)
	scheduleEvent(function()
		focusFloatingNameInput(addGroupWindow, nameInput, true)
	end, 50)

	local function closeWindow()
		destroyAddGroupWindow()
	end

	function addGroupWindow.buttonOk.onClick()
		local newGroupName = nameInput:getText():trim()
		local selectedWidget = groupColorRadioGroup and groupColorRadioGroup:getSelectedWidget()
		local groupColor = selectedWidget and selectedWidget.colorHex or "#ffffff"

		if newGroupName and newGroupName ~= "" then
			if #newGroupName > 15 then
				newGroupName = newGroupName:sub(1, 15)
			end
			clientEditVipGroup(groupId, newGroupName, groupColor)
		end

		closeWindow()
	end

	addGroupWindow.closeButton.onClick = closeWindow
	addGroupWindow.onEscape = closeWindow

	function nameInput.onKeyDown(widget, keyCode, keyboardModifiers)
		if g_keyboard.isEnterKey(keyCode) then
			if #widget:getText():trim() > 0 then
				addGroupWindow.buttonOk.onClick()
			end

			return true
		elseif keyCode == KeyEscape then
			closeWindow()

			return true
		end

		return false
	end
end

function addGroup()
	if addGroupWindow then
		local nameInput = addGroupWindow:getChildById("name")
		local groupName = nameInput:getText():trim()
		local selectedWidget = groupColorRadioGroup and groupColorRadioGroup:getSelectedWidget()
		local groupColor = selectedWidget and selectedWidget.colorHex or "#ffffff"

		if groupName and groupName ~= "" then
			if #groupName > 15 then
				groupName = groupName:sub(1, 15)
			end
			clientAddVipGroup(groupName, groupColor)
			destroyAddGroupWindow()
		end
	end
end

function destroyAddGroupWindow()
	if groupColorRadioGroup then
		groupColorRadioGroup:destroy()
		groupColorRadioGroup = nil
	end

	if addGroupWindow then
		pcall(function()
			addGroupWindow:ungrabKeyboard()
		end)
		addGroupWindow:destroy()

		addGroupWindow = nil
	end
end

function editGroup(groupId)
	if addGroupWindow then
		local nameInput = addGroupWindow:getChildById("name")
		local groupName = nameInput:getText():trim()
		local selectedWidget = groupColorRadioGroup and groupColorRadioGroup:getSelectedWidget()
		local groupColor = selectedWidget and selectedWidget.colorHex or "#ffffff"
		if groupName and groupName ~= "" then
			if #groupName > 15 then
				groupName = groupName:sub(1, 15)
			end
			clientEditVipGroup(groupId, groupName, groupColor)
		end
		destroyAddGroupWindow()
	end
end

function getPlayersByGroup(groupId)
	local playerFromGroupID = {}
	local targetGid = tonumber(groupId)

	for id, data in pairs(vipInfo) do
		local grps = normalizePlayerGroups(data.vipGroups, data.vipGroupsJson)
		for _, gid in ipairs(grps) do
			if tonumber(gid) == targetGid then
				table.insert(playerFromGroupID, data)
				break
			end
		end
	end

	return playerFromGroupID
end

function getPlayersNoGroup()
	local playerFromNoGroup = {}

	for id, data in pairs(vipInfo) do
		local grps = normalizePlayerGroups(data.vipGroups, data.vipGroupsJson)
		if #grps == 0 then
			table.insert(playerFromNoGroup, data)
		end
	end

	return playerFromNoGroup
end

function updateGroupButtons()
	if not vipWindow then
		return
	end

	local groupsPanel = vipWindow:getChildById("groupsPanel")
	if not groupsPanel then
		return
	end

	groupsPanel:destroyChildren()

	if not globalSettings.showGrouped or globalSettings.groupViewMode ~= "buttons" then
		groupsPanel:hide()
		groupsPanel:setHeight(0)
		groupsPanel:setMarginTop(0)
		return
	else
		groupsPanel:show()
		groupsPanel:setHeight(20)
		groupsPanel:setMarginTop(2)
	end

	if currentSelectedGroupId and currentSelectedGroupId ~= 0 then
		local found = false
		for _, g in ipairs(vipGroups) do
			if g[1] == currentSelectedGroupId then
				found = true
				break
			end
		end
		if not found then
			currentSelectedGroupId = 0
		end
	end

	-- 1. All button
	local allBtn = g_ui.createWidget("VipGroupButton", groupsPanel)
	allBtn:setText(tr("All"))
	allBtn.groupId = 0
	allBtn.groupColor = "#dfdfdf"
	allBtn:setColor("#dfdfdf")
	allBtn.tooltipDelay = 80
	allBtn:setTooltip(tr("Show all VIPs"))
	local allWidth = allBtn:getTextSize().width
	allBtn:setWidth(math.max(26, allWidth + 10))
	allBtn:setOn(currentSelectedGroupId == 0 or currentSelectedGroupId == nil)

	allBtn.onHoverChange = function(widget, hovered)
		widget:setColor(hovered and "#ffffff" or (widget.groupColor or "#dfdfdf"))
	end
	allBtn.onStyleApply = function(widget)
		widget:setColor(widget.groupColor or "#dfdfdf")
	end

	allBtn.onClick = function()
		selectVipGroup(0)
	end

	allBtn.onMousePress = function(widget, mousePos, mouseButton)
		if mouseButton == MouseRightButton then
			onVipGroupButtonRightClick(widget, mousePos)
			return true
		end
	end

	-- 2. Each group in vipGroups
	local displayGroups = {}
	for _, g in ipairs(vipGroups) do
		table.insert(displayGroups, g)
	end
	table.sort(displayGroups, function(a, b)
		return a[1] < b[1]
	end)

	for _, group in ipairs(displayGroups) do
		local gId = group[1]
		local gName = group[2]
		local gColor = group[4] or "#ffffff"

		local btn = g_ui.createWidget("VipGroupButton", groupsPanel)
		btn:setText(gName)
		btn.groupId = gId
		btn.groupColor = gColor
		btn.highlightColor = getHoverHighlightColor(gColor)
		btn:setColor(gColor)
		btn.tooltipDelay = 80
		btn:setTooltip(gName)
		local w = btn:getTextSize().width
		btn:setWidth(math.max(28, w + 10))
		btn:setOn(currentSelectedGroupId == gId)

		btn.onHoverChange = function(widget, hovered)
			widget:setColor(hovered and widget.highlightColor or widget.groupColor)
		end
		btn.onStyleApply = function(widget)
			widget:setColor(widget:isHovered() and widget.highlightColor or widget.groupColor)
		end

		btn.onClick = function()
			selectVipGroup(gId)
		end

		btn.onMousePress = function(widget, mousePos, mouseButton)
			if mouseButton == MouseRightButton then
				onVipGroupButtonRightClick(widget, mousePos)
				return true
			end
		end
	end

	-- 3. Add group [+]
	local addBtn = g_ui.createWidget("VipAddGroupButton", groupsPanel)
	addBtn.tooltipDelay = 80
	addBtn:setTooltip(tr("Add new group"))
	addBtn.onClick = function()
		createAddGroupWindow()
	end

	updateGroupScroll(0)
end

function onVipGroupButtonRightClick(widget, mousePos)
	local menu = g_ui.createWidget("PopupMenu")
	menu:setGameMenu(true)

	if widget.groupId and widget.groupId ~= 0 then
		local gId = widget.groupId
		local gName = widget:getText()
		menu:addOption(tr("Edit group %s", gName), function()
			createEditGroupWindow(gName, gId)
		end)
		menu:addOption(tr("Remove group %s", gName), function()
			clientRemoveVipGroup(gId)
		end)
		menu:addSeparator()
	end

	menu:addOption(tr("Add new group"), function()
		createAddGroupWindow()
	end)
	menu:addOption(tr("Add new VIP"), function()
		createAddWindow()
	end)
	menu:addSeparator()

	menu:addOption(tr("Hide groups"), function()
		globalSettings.showGrouped = false
		if not g_game.getFeature(GameVipGroups) then
			saveVipInfo()
		end
		refresh()
	end)

	if globalSettings.groupViewMode == "buttons" then
		menu:addOption(tr("Groups List"), function()
			globalSettings.groupViewMode = "list"
			if not g_game.getFeature(GameVipGroups) then
				saveVipInfo()
			end
			refresh()
		end)
	else
		menu:addOption(tr("Groups Buttons"), function()
			globalSettings.groupViewMode = "buttons"
			if not g_game.getFeature(GameVipGroups) then
				saveVipInfo()
			end
			refresh()
		end)
	end

	local menuPos = {
		x = mousePos.x,
		y = mousePos.y
	}
	menu:display(menuPos)
end

local function renderGroupButtonsContent()
	if not vipWindow then
		return
	end

	local contentsPanel = vipWindow:getChildById("contentsPanel")
	if not contentsPanel then
		return
	end

	contentsPanel:destroyChildren()

	local vips = g_game.getVips()
	for id, vip in pairs(vips) do
		local name = vip[1]
		local state = vip[2]
		local description = vip[3]
		local iconId = vip[4]
		local notify = vip[5]

		local shouldShow = true
		if currentSelectedGroupId and currentSelectedGroupId ~= 0 then
			shouldShow = checkPlayerGroup(name, currentSelectedGroupId)
		end

		if shouldShow then
			local label = g_ui.createWidget("VipListLabel", contentsPanel)
			label.onMousePress = onVipListLabelMousePress
			label:setId("vip" .. id)
			label:setText(name)

			local tmpVipInfo = vipInfo[name] or {}
			local finalIcon = tmpVipInfo.iconId or tmpVipInfo.icon or iconId or 0
			label:setImageClip(torect(finalIcon * 12 .. " 0 12 12"))
			label.iconId = finalIcon
			label.notifyLogin = (tmpVipInfo.notifyLogin ~= nil and tmpVipInfo.notifyLogin) or (tmpVipInfo.hasNotify ~= nil and tmpVipInfo.hasNotify) or notify or false
			label.vipDescription = tmpVipInfo.description or tmpVipInfo.vipDesc or description or ""

			setVipState(label, state)
			label:setPhantom(false)

			connect(label, {
				onDoubleClick = function()
					g_game.openPrivateChannel(label:getText())
					return true
				end
			})

			if state == VipState.Offline and globalSettings.hideOfflineVips then
				label:setVisible(false)
			end
		end
	end

	sortBy(getSortedBy())
end

function selectVipGroup(groupId)
	currentSelectedGroupId = groupId or 0

	local groupsPanel = vipWindow:getChildById("groupsPanel")
	if groupsPanel then
		for _, child in ipairs(groupsPanel:getChildren()) do
			if child.groupId ~= nil then
				child:setOn(child.groupId == currentSelectedGroupId)
				child:setColor(child:isHovered() and (child.highlightColor or "#ffffff") or (child.groupColor or "#dfdfdf"))
			end
		end
	end

	renderGroupButtonsContent()
end

local currentGroupScrollX = 0

function updateGroupScroll(delta)
	if not vipWindow then
		return
	end

	local groupsPanel = vipWindow:getChildById("groupsPanel")
	local prevBtn = vipWindow:getChildById("prevGroupButton")
	local nextBtn = vipWindow:getChildById("nextGroupButton")

	if not groupsPanel or not groupsPanel:isVisible() or not globalSettings.showGrouped or globalSettings.groupViewMode ~= "buttons" then
		if prevBtn then
			prevBtn:hide()
			prevBtn:setWidth(0)
		end
		if nextBtn then
			nextBtn:hide()
			nextBtn:setWidth(0)
		end
		return
	end

	local children = groupsPanel:getChildren()
	local totalWidth = 0
	for i, child in ipairs(children) do
		totalWidth = totalWidth + child:getWidth() + (i > 1 and 2 or 0)
	end

	local scrollBar = vipWindow:getChildById("miniwindowScrollBar")
	local scrollBarWidth = (scrollBar and scrollBar:isVisible()) and scrollBar:getWidth() or 14
	local fullAvailableWidth = vipWindow:getWidth() - scrollBarWidth - 6

	if totalWidth <= fullAvailableWidth then
		if prevBtn then
			prevBtn:hide()
			prevBtn:setWidth(0)
		end
		if nextBtn then
			nextBtn:hide()
			nextBtn:setWidth(0)
		end
		groupsPanel:addAnchor(AnchorLeft, "parent", AnchorLeft)
		groupsPanel:addAnchor(AnchorRight, "miniwindowScrollBar", AnchorLeft)
		groupsPanel:setMarginLeft(3)
		groupsPanel:setMarginRight(1)

		currentGroupScrollX = 0
		groupsPanel:setVirtualOffset({ x = 0, y = 0 })
		return
	end

	-- Total width exceeds available width: scrolling is needed.
	local maxScroll = math.max(0, totalWidth - (fullAvailableWidth - 16))

	if delta then
		currentGroupScrollX = math.max(0, math.min(maxScroll, currentGroupScrollX + delta))
	else
		currentGroupScrollX = math.max(0, math.min(maxScroll, currentGroupScrollX))
	end

	local canScrollLeft = currentGroupScrollX > 0
	local canScrollRight = currentGroupScrollX < maxScroll

	if canScrollLeft then
		if prevBtn then
			prevBtn:show()
			prevBtn:setWidth(14)
		end
		groupsPanel:addAnchor(AnchorLeft, "prevGroupButton", AnchorRight)
		groupsPanel:setMarginLeft(2)
	else
		if prevBtn then
			prevBtn:hide()
			prevBtn:setWidth(0)
		end
		groupsPanel:addAnchor(AnchorLeft, "parent", AnchorLeft)
		groupsPanel:setMarginLeft(3)
	end

	if canScrollRight then
		if nextBtn then
			nextBtn:show()
			nextBtn:setWidth(14)
		end
		groupsPanel:addAnchor(AnchorRight, "nextGroupButton", AnchorLeft)
		groupsPanel:setMarginRight(2)
	else
		if nextBtn then
			nextBtn:hide()
			nextBtn:setWidth(0)
		end
		groupsPanel:addAnchor(AnchorRight, "miniwindowScrollBar", AnchorLeft)
		groupsPanel:setMarginRight(1)
	end

	groupsPanel:setVirtualOffset({ x = currentGroupScrollX, y = 0 })
end

function renderGroupButtonsMode()
	if not vipWindow then
		return
	end

	local contentsPanel = vipWindow:getChildById("contentsPanel")
	if not contentsPanel then
		return
	end

	local groupsPanel = vipWindow:getChildById("groupsPanel")
	if groupsPanel then
		groupsPanel:show()
		groupsPanel:setHeight(20)
		groupsPanel:setMarginTop(2)
	end
	contentsPanel:addAnchor(AnchorTop, "groupsPanel", AnchorBottom)
	contentsPanel:setMarginTop(2)

	local prevBtn = vipWindow:getChildById("prevGroupButton")
	local nextBtn = vipWindow:getChildById("nextGroupButton")
	if prevBtn then
		prevBtn.onClick = function()
			updateGroupScroll(-45)
		end
	end
	if nextBtn then
		nextBtn.onClick = function()
			updateGroupScroll(45)
		end
	end
	if groupsPanel then
		groupsPanel.onMouseWheel = function(widget, mousePos, mouseWheel)
			if mouseWheel == MouseWheelUp then
				updateGroupScroll(-35)
			elseif mouseWheel == MouseWheelDown then
				updateGroupScroll(35)
			end
			return true
		end
	end

	updateGroupButtons()
	renderGroupButtonsContent()
	updateGroupScroll(0)
end

function renderFlatMode()
	if not vipWindow then
		return
	end

	local contentsPanel = vipWindow:getChildById("contentsPanel")
	if not contentsPanel then
		return
	end

	local prevBtn = vipWindow:getChildById("prevGroupButton")
	local nextBtn = vipWindow:getChildById("nextGroupButton")
	if prevBtn then
		prevBtn:hide()
		prevBtn:setWidth(0)
	end
	if nextBtn then
		nextBtn:hide()
		nextBtn:setWidth(0)
	end

	local groupsPanel = vipWindow:getChildById("groupsPanel")
	if groupsPanel then
		groupsPanel:hide()
		groupsPanel:setHeight(0)
		groupsPanel:setMarginTop(0)
	end
	contentsPanel:addAnchor(AnchorTop, "miniwindowHeader", AnchorBottom)
	contentsPanel:setMarginTop(2)

	contentsPanel:destroyChildren()

	local vips = g_game.getVips()
	for id, vip in pairs(vips) do
		local name = vip[1]
		local state = vip[2]
		local description = vip[3]
		local iconId = vip[4]
		local notify = vip[5]

		local label = g_ui.createWidget("VipListLabel", contentsPanel)
		label.onMousePress = onVipListLabelMousePress
		label:setId("vip" .. id)
		label:setText(name)

		local tmpVipInfo = vipInfo[name] or {}
		local finalIcon = tmpVipInfo.iconId or tmpVipInfo.icon or iconId or 0
		label:setImageClip(torect(finalIcon * 12 .. " 0 12 12"))
		label.iconId = finalIcon
		label.notifyLogin = (tmpVipInfo.notifyLogin ~= nil and tmpVipInfo.notifyLogin) or (tmpVipInfo.hasNotify ~= nil and tmpVipInfo.hasNotify) or notify or false
		label.vipDescription = tmpVipInfo.description or tmpVipInfo.vipDesc or description or ""

		setVipState(label, state)
		label:setPhantom(false)

		connect(label, {
			onDoubleClick = function()
				g_game.openPrivateChannel(label:getText())
				return true
			end
		})

		if state == VipState.Offline and globalSettings.hideOfflineVips then
			label:setVisible(false)
		end
	end

	sortBy(getSortedBy())
end

function renderGroupListMode()
	if not vipWindow then
		return
	end

	local contentsPanel = vipWindow:getChildById("contentsPanel")
	if not contentsPanel then
		return
	end

	local prevBtn = vipWindow:getChildById("prevGroupButton")
	local nextBtn = vipWindow:getChildById("nextGroupButton")
	if prevBtn then
		prevBtn:hide()
		prevBtn:setWidth(0)
	end
	if nextBtn then
		nextBtn:hide()
		nextBtn:setWidth(0)
	end

	local groupsPanel = vipWindow:getChildById("groupsPanel")
	if groupsPanel then
		groupsPanel:hide()
		groupsPanel:setHeight(0)
		groupsPanel:setMarginTop(0)
	end
	contentsPanel:addAnchor(AnchorTop, "miniwindowHeader", AnchorBottom)
	contentsPanel:setMarginTop(2)

	contentsPanel:destroyChildren()

	local function createPlayerWidget(groupWidget, player)
		local playerName = player.playerName or player.name or ""
		if playerName == "" then
			return nil
		end
		local playerId = player.playerId or 0

		local playerWidget = g_ui.createWidget("VipListLabel", groupWidget.panel)
		playerWidget.onMousePress = onVipListLabelMousePress
		playerWidget:setId("vip" .. (playerId ~= 0 and playerId or playerName))
		playerWidget:setText(playerName)

		local finalIcon = player.iconId or player.icon or 0
		playerWidget:setImageClip(torect(finalIcon * 12 .. " 0 12 12"))
		playerWidget.iconId = finalIcon
		playerWidget.notifyLogin = (player.notifyLogin ~= nil and player.notifyLogin) or (player.hasNotify ~= nil and player.hasNotify) or false
		playerWidget.vipDescription = player.description or player.vipDesc or ""

		setVipState(playerWidget, player.vipState or VipState.Offline)
		playerWidget:setPhantom(false)

		connect(playerWidget, {
			onDoubleClick = function()
				g_game.openPrivateChannel(playerWidget:getText())
				return true
			end
		})

		return playerWidget
	end

	local sortedGroups = {}
	for _, g in ipairs(vipGroups) do
		table.insert(sortedGroups, g)
	end
	table.sort(sortedGroups, function(a, b)
		return (a[2] or ""):lower() < (b[2] or ""):lower()
	end)

	for _, group in ipairs(sortedGroups) do
		local groupId, groupName, isEditable, groupColor = group[1], group[2], group[3], group[4]
		local playersInGroup = getPlayersByGroup(groupId)

		if #playersInGroup > 0 then
			local groupWidget = g_ui.createWidget("VipGroupList", contentsPanel)
			groupWidget.group:setText(groupName)
			local finalColor = (groupColor and groupColor ~= "") and groupColor or "#ffffff"
			groupWidget.group.groupColor = finalColor
			groupWidget.group.highlightColor = getHoverHighlightColor(finalColor)
			groupWidget.group:setColor(finalColor)
			groupWidget.group.onHoverChange = function(w, hovered)
				w:setColor(hovered and w.highlightColor or w.groupColor)
			end
			groupWidget.group.onStyleApply = function(w)
				w:setColor(w:isHovered() and w.highlightColor or w.groupColor)
			end

			groupWidget.onHoverChange = function(w, hovered)
				if w.group and w.group.groupColor then
					w.group:setColor(hovered and w.group.highlightColor or w.group.groupColor)
				end
			end

			if #groupName >= 18 then
				groupWidget.tooltipDelay = 80
				groupWidget:setTooltip(groupName)
			end
			groupWidget:setId("group-" .. groupId)
			groupWidget.onMousePress = onVipListLabelMousePress
			groupWidget.groupId = groupId
			groupWidget.editable = isEditable

			groupWidget.group.onMousePress = function(w, mousePos, mouseButton)
				return onVipListLabelMousePress(groupWidget, mousePos, mouseButton)
			end

			local visiblePlayers = 0
			for _, player in ipairs(playersInGroup) do
				local playerWidget = createPlayerWidget(groupWidget, player)
				if playerWidget then
					if player.vipState == VipState.Offline and globalSettings.hideOfflineVips then
						playerWidget:setVisible(false)
					else
						visiblePlayers = visiblePlayers + 1
					end
				end
			end

			if visiblePlayers == 0 then
				groupWidget:hide()
				groupWidget:setHeight(0)
			else
				groupWidget:show()
				groupWidget:setSize("156 " .. (16 * visiblePlayers + 19))
			end
		end
	end

	local playersNoGroup = getPlayersNoGroup()
	if #playersNoGroup > 0 then
		local noGroupWidget = g_ui.createWidget("VipGroupList", contentsPanel)
		noGroupWidget.onMousePress = onVipListLabelMousePress
		noGroupWidget:setId("group")
		noGroupWidget.editable = false
		noGroupWidget.group:setText(tr("No Group"))
		noGroupWidget.group.groupColor = "#c0c0c0"
		noGroupWidget.group.highlightColor = "#ffffff"
		noGroupWidget.group:setColor("#c0c0c0")
		noGroupWidget.group.onHoverChange = function(w, hovered)
			w:setColor(hovered and w.highlightColor or w.groupColor)
		end
		noGroupWidget.group.onStyleApply = function(w)
			w:setColor(w:isHovered() and w.highlightColor or w.groupColor)
		end
		noGroupWidget.onHoverChange = function(w, hovered)
			if w.group and w.group.groupColor then
				w.group:setColor(hovered and w.group.highlightColor or w.group.groupColor)
			end
		end

		noGroupWidget.group.onMousePress = function(w, mousePos, mouseButton)
			return onVipListLabelMousePress(noGroupWidget, mousePos, mouseButton)
		end

		local visiblePlayers = 0
		for _, player in ipairs(playersNoGroup) do
			local playerWidget = createPlayerWidget(noGroupWidget, player)
			if playerWidget then
				if player.vipState == VipState.Offline and globalSettings.hideOfflineVips then
					playerWidget:setVisible(false)
				else
					visiblePlayers = visiblePlayers + 1
				end
			end
		end

		if visiblePlayers == 0 then
			noGroupWidget:hide()
			noGroupWidget:setHeight(0)
		else
			noGroupWidget:show()
			noGroupWidget:setSize("156 " .. (16 * visiblePlayers + 19))
		end
	end

	sortBy(getSortedBy())
end

function showGroups(sortType)
	if not globalSettings.showGrouped then
		renderFlatMode()
	elseif globalSettings.groupViewMode == "buttons" then
		renderGroupButtonsMode()
	else
		renderGroupListMode()
	end
end

function refreshVipList()
	showGroups()
end

function setVipState(widget, vipState)
	widget.vipState = vipState

	if vipState == VipState.Online then
		widget:setColor("#5ff75f")
	end

	if vipState == VipState.Pending then
		widget:setColor("#ffca38")
	elseif vipState == VipState.Offline then
		widget:setColor("#f75f5f")
	elseif vipState == VipState.Training then
		widget:setColor("#9966cc")
	end

	applyVipListLabelTooltip(widget)
end

function getPlayerGroups(playerName)
	if vipInfo[playerName] and vipInfo[playerName].vipGroups then
		return normalizePlayerGroups(vipInfo[playerName].vipGroups, vipInfo[playerName].vipGroupsJson)
	end

	local playerGroups = {}

	for id, vip in pairs(g_game.getVips()) do
		if vip[1] == playerName then
			playerGroups = vip[6] or {}

			break
		end
	end

	return playerGroups
end

function checkPlayerGroup(playerName, groupId)
	local targetGid = tonumber(groupId)
	if vipInfo[playerName] and vipInfo[playerName].vipGroups then
		local grps = normalizePlayerGroups(vipInfo[playerName].vipGroups, vipInfo[playerName].vipGroupsJson)
		for _, playerGroup in ipairs(grps) do
			if tonumber(playerGroup) == targetGid then
				return true
			end
		end
	end

	local vips = g_game.getVips()

	for _, vip in pairs(vips) do
		if vip[1] == playerName then
			local playerGroups = vip[6]
			if playerGroups then
				for _, playerGroup in ipairs(playerGroups) do
					if tonumber(playerGroup) == targetGid then
						return true
					end
				end
			end

			return false
		end
	end

	return false
end

function searchPlayerbyId(playerId)
	for key, idCache in pairs(vipInfo) do
		if tonumber(idCache.playerId) == playerId then
			local name = idCache.playerName
			local description = idCache.vipDesc
			local iconId = idCache.icon
			local notify = idCache.hasNotify

			return name, description, iconId, notify
		end
	end
end
