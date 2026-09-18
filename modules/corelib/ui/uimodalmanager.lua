-- chunkname: @/corelib/ui/uimodalmanager.lua

g_modalManager = g_modalManager or {}

local DEFAULT_OVERLAY_COLOR = "#00000080"
local TRANSPARENT_COLOR = "#00000000"
local BLOCKER_ID = "modalBlocker"
local modalStack = {}
local MODAL_HOTKEY_BLOCK_SOURCE = "g_modal_manager"
local modalHotkeyBlockId

local function acquireModalHotkeyBlock()
	if modalHotkeyBlockId then
		return
	end

	if HotkeyUtils and HotkeyUtils.disableHotkeys then
		modalHotkeyBlockId = HotkeyUtils.disableHotkeys(MODAL_HOTKEY_BLOCK_SOURCE)
	end

	if modules.game_actionbar and modules.game_actionbar.pauseHotkeys then
		modules.game_actionbar.pauseHotkeys()
	end
end

local function releaseModalHotkeyBlock()
	if not modalHotkeyBlockId then
		return
	end

	if HotkeyUtils and HotkeyUtils.enableHotkeys then
		HotkeyUtils.enableHotkeys(modalHotkeyBlockId)
	end

	modalHotkeyBlockId = nil

	if modules.game_actionbar and modules.game_actionbar.resumeHotkeys then
		modules.game_actionbar.resumeHotkeys()
	end
end

local function pruneStack()
	for i = #modalStack, 1, -1 do
		local entry = modalStack[i]

		if not isWidgetAlive(entry.widget) then
			if entry.blocker and isWidgetAlive(entry.blocker) then
				entry.blocker:destroy()
			end

			table.remove(modalStack, i)
		end
	end
end

local function findIndex(widget)
	for i = #modalStack, 1, -1 do
		if modalStack[i].widget == widget then
			return i
		end
	end

	return nil
end

local function createBlocker(widget, opts)
	local parent = widget:getParent() or rootWidget
	local blocker = g_ui.createWidget("UIWidget", parent)

	blocker:setId(BLOCKER_ID)
	blocker:fill("parent")
	blocker:setPhantom(false)
	blocker:setFocusable(false)

	if opts.darken then
		blocker:setBackgroundColor(opts.color or DEFAULT_OVERLAY_COLOR)
	else
		blocker:setBackgroundColor(TRANSPARENT_COLOR)
	end

	return blocker
end

local function activateTop()
	local top = modalStack[#modalStack]

	if top and isWidgetAlive(top.widget) then
		top.widget:raise()
		top.widget:focus()
		top.widget:grabKeyboard()
	end
end

local function collectActiveBlockers()
	local active = {}

	for _, entry in ipairs(modalStack) do
		if entry.blocker and isWidgetAlive(entry.blocker) then
			active[entry.blocker] = true
		end
	end

	return active
end

local function pruneOrphanBlockersInWidget(widget, activeBlockers)
	if not isWidgetAlive(widget) then
		return
	end

	if widget:getId() == BLOCKER_ID and not activeBlockers[widget] then
		widget:destroy()

		return
	end

	local children = widget:getChildren()

	for i = 1, #children do
		pruneOrphanBlockersInWidget(children[i], activeBlockers)
	end
end

function g_modalManager.pruneOrphanBlockers()
	if not rootWidget then
		return
	end

	pruneStack()
	pruneOrphanBlockersInWidget(rootWidget, collectActiveBlockers())
end

local function ensureModalDestroyCleanup(widget)
	if widget._modalManagerCleanupConnected then
		return
	end

	widget._modalManagerCleanupConnected = true

	connect(widget, {
		onDestroy = function(destroyedWidget)
			g_modalManager.hide(destroyedWidget)
			g_modalManager.pruneOrphanBlockers()
		end
	})
end

local function invokeCloseCallback(entry)
	if not entry or not entry.opts then
		return
	end

	local onClose = entry.opts.onClose

	if type(onClose) ~= "function" then
		return
	end

	pcall(onClose, entry.widget)
end

local function releaseModalEntry(entry, hideWidget, runCloseCallback)
	if not entry then
		return
	end

	if runCloseCallback then
		invokeCloseCallback(entry)
	end

	if entry.blocker and isWidgetAlive(entry.blocker) then
		pcall(function()
			entry.blocker:destroy()
		end)
	end

	if isWidgetAlive(entry.widget) then
		pcall(function()
			entry.widget:ungrabKeyboard()
		end)

		if hideWidget then
			pcall(function()
				entry.widget:hide()
			end)
		end
	end
end

local function suppressModalAutoRaise(widget)
	if widget._modalAutoRaiseSuppressed then
		return
	end

	widget._modalAutoRaiseSuppressed = true

	function widget.onMousePress()
		return false
	end

	function widget.onFocusChange()
		return
	end
end

function g_modalManager.show(widget, opts)
	if not isWidgetAlive(widget) then
		return
	end

	pruneStack()

	if findIndex(widget) then
		activateTop()

		return
	end

	opts = opts or {}

	local ok, blocker = pcall(createBlocker, widget, opts)

	if not ok or not blocker then
		return
	end

	table.insert(modalStack, {
		widget = widget,
		blocker = blocker,
		opts = opts
	})

	if #modalStack == 1 then
		acquireModalHotkeyBlock()
	end

	ensureModalDestroyCleanup(widget)
	suppressModalAutoRaise(widget)
	activateTop()
end

function g_modalManager.hide(widget)
	if not widget then
		return
	end

	local idx = findIndex(widget)

	if not idx then
		pruneStack()

		return
	end

	local entry = table.remove(modalStack, idx)

	releaseModalEntry(entry, false, false)
	pruneStack()

	if #modalStack == 0 then
		releaseModalHotkeyBlock()
	else
		activateTop()
	end

	g_modalManager.pruneOrphanBlockers()
end

function g_modalManager.hideAll()
	pruneStack()

	local entries = {}

	for i = 1, #modalStack do
		entries[i] = modalStack[i]
	end

	modalStack = {}

	releaseModalHotkeyBlock()

	for i = #entries, 1, -1 do
		releaseModalEntry(entries[i], true, true)
	end

	if g_client and g_client.setInputLockWidget then
		pcall(function()
			g_client.setInputLockWidget(nil)
		end)
	end

	g_modalManager.pruneOrphanBlockers()
end

function g_modalManager.isModal(widget)
	return findIndex(widget) ~= nil
end

local ORPHAN_OVERLAY_IDS = {
	storeWindow = true,
	changeNameWindow = true,
	[BLOCKER_ID] = true
}

local function destroyModalWidget(widget)
	if not isWidgetAlive(widget) then
		return
	end

	pcall(function()
		g_modalManager.hide(widget)
	end)
	pcall(function()
		widget:ungrabKeyboard()
	end)
	pcall(function()
		widget:destroy()
	end)
end

local function dismissOrphanOverlays()
	if not rootWidget then
		return
	end

	local children = rootWidget:getChildren()

	for i = #children, 1, -1 do
		local child = children[i]

		if isWidgetAlive(child) and ORPHAN_OVERLAY_IDS[child:getId()] then
			destroyModalWidget(child)
		end
	end
end

function g_modalManager.dismissAll()
	pruneStack()

	local widgetsToClose = {}

	for _, entry in ipairs(modalStack) do
		if isWidgetAlive(entry.widget) then
			table.insert(widgetsToClose, entry.widget)
		end
	end

	while #modalStack > 0 do
		local entry = table.remove(modalStack)

		invokeCloseCallback(entry)

		if entry.blocker and isWidgetAlive(entry.blocker) then
			pcall(function()
				entry.blocker:destroy()
			end)
		end

		if isWidgetAlive(entry.widget) then
			pcall(function()
				entry.widget:ungrabKeyboard()
			end)
		end
	end

	releaseModalHotkeyBlock()

	for _, widget in ipairs(widgetsToClose) do
		destroyModalWidget(widget)
	end

	if g_client and g_client.setInputLockWidget then
		pcall(function()
			g_client.setInputLockWidget(nil)
		end)
	end

	dismissOrphanOverlays()
	g_modalManager.pruneOrphanBlockers()
end

function g_modalManager.clear()
	g_modalManager.dismissAll()
end

local function onGameEndHideModals()
	g_modalManager.hideAll()
end

connect(g_game, {
	onGameEnd = onGameEndHideModals
})
