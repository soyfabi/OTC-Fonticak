-- chunkname: @/game_taskboard/game_taskboard.lua

TaskBoard = {}

local TAB_BOUNTY = "bounty"
local TAB_WEEKLY = "weekly"
local TAB_SHOP = "shop"
local CLIENT_EVENT_TYPE_BOUNTY_TASK = 11
local BOUNTY_SHORTCUT_HIGHLIGHT_ID = "taskBoardShortcutHighlight"
local bountyShortcutHighlightActive = false
local TASK_BOARD_BUTTON_IMAGE = "/modules/game_taskboard/images/icon-bountytasks"
local taskBoardPanelButton = nil

local function toggleTaskBoardWindow()
	TaskBoard:toggleWindow()
end

local function showTaskBoardModal(widget)
	if g_modalManager then
		g_modalManager.show(widget)
	end
end

local function hideTaskBoardModal(widget)
	if g_modalManager then
		g_modalManager.hide(widget)
	end
end

local function ensureTaskBoardPanelButton()
	if not modules.game_mainpanel or not modules.game_mainpanel.addToggleButton then
		return
	end

	if taskBoardPanelButton and not taskBoardPanelButton:isDestroyed() then
		TaskBoard.mainButton = taskBoardPanelButton
		return
	end

	taskBoardPanelButton = modules.game_mainpanel.addToggleButton(
		"taskBoard",
		tr("Open Task Board"),
		TASK_BOARD_BUTTON_IMAGE,
		toggleTaskBoardWindow,
		false,
		22
	)
	TaskBoard.mainButton = taskBoardPanelButton
end

local function destroyTaskBoardPanelButton()
	if taskBoardPanelButton and not taskBoardPanelButton:isDestroyed() then
		taskBoardPanelButton:destroy()
	end

	taskBoardPanelButton = nil
	TaskBoard.mainButton = nil
end

local function getTaskBoardMainButton()
	if not modules.game_mainpanel or not modules.game_mainpanel.getButton then
		return nil
	end

	local button = modules.game_mainpanel.getButton("taskBoard")

	if not button or button:isDestroyed() then
		return nil
	end

	TaskBoard.mainButton = button

	return button
end

local function syncBountyShortcutHighlight()
	local button = getTaskBoardMainButton()

	if not button then
		return
	end

	local highlight = button:recursiveGetChildById(BOUNTY_SHORTCUT_HIGHLIGHT_ID)

	if not highlight then
		highlight = g_ui.createWidget("UIWidget", button)

		if not highlight then
			return
		end

		highlight:setId(BOUNTY_SHORTCUT_HIGHLIGHT_ID)
		highlight:setSize({
			width = 23,
			height = 23
		})
		highlight:setPhantom(true)
		highlight:setClipping(false)
		highlight:setImageSource("/images/animations/button-highlight-23x23")
		highlight:breakAnchors()
		highlight:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
		highlight:addAnchor(AnchorVerticalCenter, "parent", AnchorVerticalCenter)
	end

	highlight:setVisible(bountyShortcutHighlightActive)
end

function TaskBoard:setBountyShortcutHighlightVisible(show)
	bountyShortcutHighlightActive = show == true or show == 1

	syncBountyShortcutHighlight()
end

function TaskBoard:clearBountyShortcutHighlight()
	self:setBountyShortcutHighlightVisible(false)
end

local function onTaskBoardClientEvent(eventType)
	if eventType == CLIENT_EVENT_TYPE_BOUNTY_TASK then
		TaskBoard:setBountyShortcutHighlightVisible(true)
	end
end

local function onTaskBoardGameStart()
	ensureTaskBoardPanelButton()
	scheduleEvent(syncBountyShortcutHighlight, 0)
end

local function onTaskBoardGameEnd()
	destroyTaskBoardPanelButton()
end

TaskBoard.resourceTypes = {
	soulSeals = 87,
	bountyPoints = 86,
	taskHunting = 50
}

function TaskBoard:formatNumberWithCommas(n)
	local s = tostring(n)
	local pos = string.len(s) % 3

	if pos == 0 then
		pos = 3
	end

	local t = s:sub(1, pos)

	for i = pos + 1, #s, 3 do
		t = t .. "," .. s:sub(i, i + 2)
	end

	return t
end

function TaskBoard:getResourceBalance(str)
	local t = self.resourceTypes[str]

	if not t then
		return 0
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	return player:getResourceBalance(t)
end

function TaskBoard:updateMenuSelection(tab)
	local bountyOn = tab == TAB_BOUNTY
	local weeklyOn = tab == TAB_WEEKLY
	local shopOn = tab == TAB_SHOP

	if self.menuBounty then
		self.menuBounty:setChecked(bountyOn)
		self.menuBounty:setOn(bountyOn)
	end

	if self.menuWeekly then
		self.menuWeekly:setChecked(weeklyOn)
		self.menuWeekly:setOn(weeklyOn)
	end

	if self.menuShop then
		self.menuShop:setChecked(shopOn)
		self.menuShop:setOn(shopOn)
	end
end

local function onTaskBoardGameEnd()
	TaskBoard:clearBountyShortcutHighlight()

	if TaskBoard.mainWindow then
		TaskBoard.mainWindow:setVisible(false)
	end

	if TaskBoard.mainButton then
		TaskBoard.mainButton:setOn(false)
	end
end

local function onTaskBoardResourceBalance()
	if not TaskBoard.BountyTaskPoints or not TaskBoard.TaskHuntingPoints or not TaskBoard.SoulSealsPoints then
		return
	end

	TaskBoard.BountyTaskPoints:getChildById("value"):setText(TaskBoard:formatNumberWithCommas(TaskBoard:getResourceBalance("bountyPoints")))
	TaskBoard.TaskHuntingPoints:getChildById("value"):setText(TaskBoard:formatNumberWithCommas(TaskBoard:getResourceBalance("taskHunting")))
	TaskBoard.SoulSealsPoints:getChildById("value"):setText(TaskBoard:formatNumberWithCommas(TaskBoard:getResourceBalance("soulSeals")))
end

function TaskBoard:showTab(tab)
	self:updateMenuSelection(tab)

	if self.bountyTaskPanel then
		self.bountyTaskPanel:setVisible(tab == TAB_BOUNTY)
	end

	if self.weeklyPanel then
		self.weeklyPanel:setVisible(tab == TAB_WEEKLY)
	end

	if self.taskShopPanel then
		self.taskShopPanel:setVisible(tab == TAB_SHOP)
	end

	if self.WeeklyTask and self.WeeklyTask.updateOverlayVisibility then
		self.WeeklyTask:updateOverlayVisibility()
	end
end

function TaskBoard:showBountyTab()
	self:clearBountyShortcutHighlight()
	self:showTab(TAB_BOUNTY)
	if g_game.isOnline() and g_game.sendOpenMenuTaskBoardAction then
		g_game.sendOpenMenuTaskBoardAction(0)
	end
end

function TaskBoard:showWeeklyTab()
	self:showTab(TAB_WEEKLY)
	if g_game.isOnline() and g_game.sendOpenMenuTaskBoardAction then
		g_game.sendOpenMenuTaskBoardAction(1)
	end
end

function TaskBoard:showTaskShopTab()
	self:showTab(TAB_SHOP)
	if g_game.isOnline() and g_game.sendOpenMenuTaskBoardAction then
		g_game.sendOpenMenuTaskBoardAction(2)
	end
end

function init()
	connect(g_game, {
		onGameStart = onTaskBoardGameStart,
		onGameEnd = onTaskBoardGameEnd,
		onResourceBalance = onTaskBoardResourceBalance,
		onClientEvent = onTaskBoardClientEvent
	})
	g_ui.importStyle("taskboard_vars")
	g_ui.importStyle("menus/bounty_task")
	g_ui.importStyle("menus/weekly_task")
	g_ui.importStyle("menus/task_shop")

	TaskBoard.mainWindow = g_ui.displayUI("game_taskboard")

	TaskBoard.mainWindow:setId("taskboard")
	TaskBoard.mainWindow:setVisible(false)

	TaskBoard.menuBounty = TaskBoard.mainWindow:recursiveGetChildById("BountyTaskMenu")
	TaskBoard.menuWeekly = TaskBoard.mainWindow:recursiveGetChildById("WeeklyTaskMenu")
	TaskBoard.menuShop = TaskBoard.mainWindow:recursiveGetChildById("TaskShopMenu")
	TaskBoard.bountyTaskPanel = TaskBoard.mainWindow:recursiveGetChildById("bountyTaskPanel")
	TaskBoard.weeklyPanel = TaskBoard.mainWindow:recursiveGetChildById("weeklyPanel")
	TaskBoard.taskShopPanel = TaskBoard.mainWindow:recursiveGetChildById("taskShopPanel")
	TaskBoard.preferredListPanel = TaskBoard.mainWindow:recursiveGetChildById("preferredListPanel")
	TaskBoard.chainTransparent = TaskBoard.mainWindow:recursiveGetChildById("chainTransparent")
	TaskBoard.chainTransparentWeekly = TaskBoard.mainWindow:recursiveGetChildById("chainTransparentWeekly")
	TaskBoard.weeklyProgressPanel = TaskBoard.mainWindow:recursiveGetChildById("weeklyProgressPanel")

	if not TaskBoard.weeklyProgressPanel then
		print("[Warning] weeklyProgressPanel is nil! Check that the ID 'weeklyProgressPanel' is correct in weekly_task.otui and that the file is imported before displayUI.")
	end

	if not TaskBoard.chainTransparentWeekly then
		print("[Warning] chainTransparentWeekly is nil! Check that the ID 'chainTransparentWeekly' is correct in weekly_task.otui and that the file is imported before displayUI.")
	end

	TaskBoard.BountyTaskPoints = TaskBoard.mainWindow:recursiveGetChildById("bountyPointsPanel")
	TaskBoard.TaskHuntingPoints = TaskBoard.mainWindow:recursiveGetChildById("huntingPointsPanel")
	TaskBoard.SoulSealsPoints = TaskBoard.mainWindow:recursiveGetChildById("soulSealsPanel")

	TaskBoard:showTab(TAB_BOUNTY)
	TaskBoard.BountyTask:init()
	TaskBoard.TaskShop:init()
	TaskBoard.WeeklyTask:init()
	scheduleEvent(syncBountyShortcutHighlight, 0)
	ensureTaskBoardPanelButton()

	modules.game_taskboard.TaskBoard = TaskBoard
end

function terminate()
	disconnect(g_game, {
		onGameStart = onTaskBoardGameStart,
		onGameEnd = onTaskBoardGameEnd,
		onResourceBalance = onTaskBoardResourceBalance,
		onClientEvent = onTaskBoardClientEvent
	})
	TaskBoard:clearBountyShortcutHighlight()
	destroyTaskBoardPanelButton()
	TaskBoard.BountyTask:terminate()
	TaskBoard.TaskShop:terminate()
	TaskBoard.WeeklyTask:terminate()
end

function TaskBoard:toggleWindow(mode)
	if not self.mainWindow:isVisible() then
		g_game.sendResourceBalance()
		self.mainWindow:setVisible(true)
		self.mainWindow:focus()

		if mode == "weekly" then
			self:showWeeklyTab()
		elseif mode == "shop" then
			self:showTaskShopTab()
		else
			self:showBountyTab()
		end

		g_game.sendOpenMenuTaskBoardAction(0)
		g_game.sendOpenMenuTaskBoardAction(1)
		g_game.sendOpenMenuTaskBoardAction(2)
		showTaskBoardModal(self.mainWindow)

		local button = getTaskBoardMainButton()
		if button then
			button:setOn(true)
		end
	else
		self.mainWindow:setVisible(false)

		if self.mainButton then
			self.mainButton:setOn(false)
		end

		hideTaskBoardModal(self.mainWindow)
	end
end
