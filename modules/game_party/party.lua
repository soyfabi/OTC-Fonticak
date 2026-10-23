-- chunkname: @/game_party/party.lua

local partyWindow, partyButton, partyPanel, filterPanel, toggleFilterButton, hideButtons
local partyEventsConnected = false

PartyListRegistry = {
	byId = {}
}

local PARTY_HIDE_BUTTONS_FORMAT = 2
local PARTY_HIDE_BUTTON_OPTIONS = {
	"hideParty",
	"hideKnights",
	"hidePaladins",
	"hideDruids",
	"hideSorcerers",
	"hideMonks",
	"hideSummons"
}
local PARTY_FILTER_BUTTON_TOOLTIPS = {
	hideParty = {
		show = "Show Players",
		hide = "Hide Players"
	},
	hideKnights = {
		show = "Show Knight",
		hide = "Hide Knight"
	},
	hidePaladins = {
		show = "Show Paladin",
		hide = "Hide Paladin"
	},
	hideDruids = {
		show = "Show Druid",
		hide = "Hide Druid"
	},
	hideSorcerers = {
		show = "Show Sorcerer",
		hide = "Hide Sorcerer"
	},
	hideMonks = {
		show = "Show Monk",
		hide = "Hide Monk"
	},
	hideSummons = {
		show = "Show Summons",
		hide = "Hide Summons"
	}
}
local PARTY_LIST_FILTERS_HIDDEN_CONTENTS_MARGIN_TOP = -3
local PARTY_LIST_FILTERS_HIDDEN_SCROLLBAR_MARGIN_TOP = 15

local function getPartyListScrollbarMarginTopWithFilters(filterPanel)
	local h = filterPanel and filterPanel:getHeight() or 0

	if h <= 0 then
		h = 46
	end

	return 17 + h - 22
end

local function partyFilterHideActive(button)
	return button and button:isChecked()
end

local function togglePartyFilterButton(button)
	if not button then
		return
	end

	local active = not button:isChecked()

	button:setChecked(active)
	button:setOn(active)
end

local function setupPartyFilterPanelOverrides(instance)
	local baseHideFilterPanel = CreatureList.Instance.hideFilterPanel
	local baseShowFilterPanel = CreatureList.Instance.showFilterPanel

	function instance:saveHideButtonStates()
		if not self.hideButtons then
			return
		end

		local hideButtonStates = {}

		for buttonName, button in pairs(self.hideButtons) do
			if button then
				hideButtonStates[buttonName] = button:isChecked()
			end
		end

		g_settings.mergeNode(self:getSettingsKey(), {
			hideButtons = hideButtonStates,
			hideButtonsFormat = self.manager.config.hideButtonsFormat
		})
	end

	function instance:loadHideButtonStates()
		if not self.hideButtons then
			return
		end

		local settings = g_settings.getNode(self:getSettingsKey())
		local saved = settings and settings.hideButtons

		for _, buttonName in ipairs(PARTY_HIDE_BUTTON_OPTIONS) do
			local button = self.hideButtons[buttonName]

			if button then
				local active = saved and saved[buttonName] == true

				button:setOn(active)
				button:setChecked(active)
			end
		end

		if self.manager.refreshFilterTooltips then
			self.manager:refreshFilterTooltips(self)
		end
	end

	function instance:hideFilterPanel()
		baseHideFilterPanel(self)

		local contentsPanel = self.window:recursiveGetChildById("contentsPanel")

		if contentsPanel then
			contentsPanel:breakAnchors()
			contentsPanel:addAnchor(AnchorTop, "miniwindowHeader", AnchorBottom)
			contentsPanel:setMarginTop(2)
			contentsPanel:addAnchor(AnchorLeft, "parent", AnchorLeft)
			contentsPanel:addAnchor(AnchorRight, "miniwindowScrollBar", AnchorLeft)
			contentsPanel:addAnchor(AnchorBottom, "parent", AnchorBottom)
			contentsPanel:setMarginLeft(3)
			contentsPanel:setMarginRight(1)
			contentsPanel:setMarginBottom(3)
		end

		local scrollbar = self.window:getChildById("miniwindowScrollBar")

		if scrollbar then
			scrollbar:setMarginTop(PARTY_LIST_FILTERS_HIDDEN_SCROLLBAR_MARGIN_TOP)
		end
	end

	function instance:showFilterPanel()
		baseShowFilterPanel(self)

		local contentsPanel = self.window:recursiveGetChildById("contentsPanel")

		if contentsPanel then
			contentsPanel:breakAnchors()
			contentsPanel:addAnchor(AnchorTop, "HorizontalSeparator", AnchorBottom)
			contentsPanel:setMarginTop(0)
			contentsPanel:addAnchor(AnchorLeft, "parent", AnchorLeft)
			contentsPanel:addAnchor(AnchorRight, "miniwindowScrollBar", AnchorLeft)
			contentsPanel:addAnchor(AnchorBottom, "parent", AnchorBottom)
			contentsPanel:setMarginLeft(3)
			contentsPanel:setMarginRight(1)
			contentsPanel:setMarginBottom(3)
		end

		local scrollbar = self.window:getChildById("miniwindowScrollBar")

		if scrollbar then
			scrollbar:setMarginTop(getPartyListScrollbarMarginTopWithFilters(self.filterPanel))
		end
	end
end

local function refreshPartyFilterButtonTooltip(button)
	if not button then
		return
	end

	local t = PARTY_FILTER_BUTTON_TOOLTIPS[button:getId()]

	if not t then
		return
	end

	if partyFilterHideActive(button) then
		button:setTooltip(tr(t.show))
	else
		button:setTooltip(tr(t.hide))
	end
end

local function partyFilterButtonOnHoverChange(button, hovered)
	refreshPartyFilterButtonTooltip(button)
	g_tooltip.onWidgetHoverChange(button, hovered)
end

local function refreshAllPartyFilterButtonTooltips(instance)
	if not instance or not instance.hideButtons then
		return
	end

	for _, name in ipairs(PARTY_HIDE_BUTTON_OPTIONS) do
		local b = instance.hideButtons[name]

		if b then
			refreshPartyFilterButtonTooltip(b)
		end
	end
end

function PartyListRegistry:add(creature)
	if not creature or not creature.getId then
		return
	end

	local id = creature:getId()

	self.byId[id] = creature
end

function PartyListRegistry:remove(creature)
	if not creature then
		return
	end

	self.byId[creature:getId()] = nil
end

function PartyListRegistry:clear()
	self.byId = {}
end

local function partyCollectCreatures()
	local result = {}
	local seen = {}

	for id, creature in pairs(PartyListRegistry.byId) do
		if creature and not creature:isRemoved() and CreatureList.isRemotePartyMember(creature) then
			seen[id] = true

			table.insert(result, creature)
		else
			PartyListRegistry.byId[id] = nil
		end
	end

	if g_game.isOnline() then
		local spectators = modules.game_interface.getMapPanel():getSpectators()

		for _, creature in ipairs(spectators) do
			if CreatureList.isRemotePartyMember(creature) then
				PartyListRegistry:add(creature)

				if not seen[creature:getId()] then
					seen[creature:getId()] = true

					table.insert(result, creature)
				end
			end
		end
	end

	return result
end

local function isPartyListPartyMemberShield(shield)
	return shield == ShieldYellow or shield == ShieldYellowSharedExp or shield == ShieldYellowNoSharedExp or shield == ShieldBlue or shield == ShieldBlueNoSharedExpBlink or shield == ShieldBlueSharedExp or shield == ShieldYellowNoSharedExpBlink or shield == ShieldBlueNoSharedExp
end

local function partyCreatureMatchesHideFilter(filterId, creature)
	if not creature:isPlayer() then
		return filterId == "hideSummons" and creature:isSummon()
	end

	if filterId == "hideParty" then
		return isPartyListPartyMemberShield(creature:getShield())
	elseif filterId == "hideKnights" then
		return creature:isKnight()
	elseif filterId == "hidePaladins" then
		return creature:isPaladin()
	elseif filterId == "hideDruids" then
		return creature:isDruid()
	elseif filterId == "hideSorcerers" then
		return creature:isSorcerer()
	elseif filterId == "hideMonks" then
		return creature:isMonk()
	elseif filterId == "hideSummons" then
		return creature:isSummon()
	end

	return false
end

local function partyDoCreatureFitFilters(instance, creature)
	if not CreatureList.isRemotePartyMember(creature) then
		return false
	end

	if creature:isDead() or creature:getHealthPercent() <= 0 then
		return false
	end

	for filterId, button in pairs(instance.hideButtons or {}) do
		if partyFilterHideActive(button) and partyCreatureMatchesHideFilter(filterId, creature) then
			return false
		end
	end

	return true
end

local function migratePartyFilterButtonStates(instance)
	if not instance or not instance.hideButtons then
		return
	end

	local settingsKey = instance:getSettingsKey()
	local settings = g_settings.getNode(settingsKey)

	if settings and settings.partyFilterLogicFixed then
		return
	end

	if settings and settings.hideButtons then
		for _, name in ipairs(PARTY_HIDE_BUTTON_OPTIONS) do
			local button = instance.hideButtons[name]

			if button then
				local active = not button:isOn()

				button:setOn(active)
				button:setChecked(active)
			end
		end
	else
		for _, name in ipairs(PARTY_HIDE_BUTTON_OPTIONS) do
			local button = instance.hideButtons[name]

			if button then
				button:setOn(false)
				button:setChecked(false)
			end
		end
	end

	g_settings.mergeNode(settingsKey, {
		partyFilterLogicFixed = true
	})
	instance:saveHideButtonStates()
	refreshAllPartyFilterButtonTooltips(instance)
end

local function onPartyButtonMouseRelease(self, mousePosition, mouseButton)
	if not self.creature then
		return false
	end

	if mouseButton == MouseLeftButton and g_keyboard.isShiftPressed() then
		g_game.look(self.creature, true)

		return true
	elseif mouseButton == MouseLeftButton then
		if self.isTarget then
			g_game.cancelAttack()
		else
			g_game.attack(self.creature)
		end

		return true
	elseif mouseButton == MouseRightButton and self.creature then
		modules.game_interface.createBattleListCreatureMenu(mousePosition, self.creature)

		return true
	end

	return false
end

local function onPartyButtonHoverChange(button, hovered)
	if button.isPartyButton then
		button.isHovered = hovered
		if button.update then
			button:update()
		end
		CreatureList.onButtonHoverChange(button, hovered)
	end
end

local function onHoveredCreatureChange(creature)
	CreatureList.syncHoveredCreature(PartyListManager, creature)
end

local function bindPartyButtonHandlers(widget)
	widget.onHoverChange = onPartyButtonHoverChange
	widget.onMouseRelease = onPartyButtonMouseRelease
end

local function partyAfterButtonSetup(_, button, creature)
	PartyListRegistry:add(creature)

	if applyCachedPartyVitals then
		applyCachedPartyVitals(creature)
	end

	local vitals = getPartyVitalsForCreature and getPartyVitalsForCreature(creature)

	if vitals and vitals.health and vitals.health <= 100 then
		button:setLifeBarPercent(vitals.health)
	else
		button:setLifeBarPercent(creature:getHealthPercent())
	end

	if vitals and vitals.mana and vitals.mana <= 100 then
		button:setManaBarPercent(vitals.mana)
	else
		button:setManaBarPercent(creature:getManaPercent())
	end

	button:updatePartyShield(creature:getShield())
	button:updateShowStatus(true)
end

local function partyAfterButtonUpdate(_, button, creature)
	if applyCachedPartyVitals then
		applyCachedPartyVitals(creature)
	end

	local vitals = getPartyVitalsForCreature and getPartyVitalsForCreature(creature)

	if vitals and vitals.health and vitals.health <= 100 then
		button:setLifeBarPercent(vitals.health)
	else
		button:setLifeBarPercent(creature:getHealthPercent())
	end

	if vitals and vitals.mana and vitals.mana <= 100 then
		button:setManaBarPercent(vitals.mana)
	else
		button:setManaBarPercent(creature:getManaPercent())
	end
	button:updatePartyShield(creature:getShield())
	button:updateShowStatus(true)
end

local function partyOnShieldChange(manager, instance, creature, shieldId)
	local isMember = CreatureList.isRemotePartyMember(creature)
	local btn = instance.battleButtons[creature:getId()]

	if isMember then
		PartyListRegistry:add(creature)

		if instance:doCreatureFitFilters(creature) then
			if not btn then
				instance:addCreature(creature, instance:getSortType())
			else
				btn:updatePartyShield(shieldId)
			end
		end
	else
		PartyListRegistry:remove(creature)

		if btn then
			instance:removeCreature(creature)
		end
	end
end

local function partyShouldRemoveOnDisappear(instance, creature)
	if CreatureList.isRemotePartyMember(creature) then
		return false
	end

	return true
end

local function partyOnCreatureRemoved(_, creature)
	PartyListRegistry:remove(creature)
end

local function syncPartyMainPanelButton()
	if SidebarWidgetOptions and SidebarWidgetOptions.syncToggleButton then
		SidebarWidgetOptions.syncToggleButton(partyWindow, partyButton, "Open Party List", "Close Party List")

		return
	end

	if not partyButton or partyButton:isDestroyed() then
		return
	end

	local on = partyWindow and not partyWindow:isDestroyed() and partyWindow:isVisible()

	partyButton:setOn(on)
	Keybind.syncControlButtonTooltip(partyButton, 'partyWidget')
end

PartyListManager = CreatureList.createManager({
	settingsPrefix = "PartyList",
	offMapDistance = 9999,
	requiresPlayerPosition = false,
	requiresPosition = false,
	buttonWidget = "PartyButton",
	defaultTitle = tr("Party List"),
	hideButtonsFormat = PARTY_HIDE_BUTTONS_FORMAT,
	hideButtonOptions = PARTY_HIDE_BUTTON_OPTIONS,
	filtersHiddenContentsMarginTop = PARTY_LIST_FILTERS_HIDDEN_CONTENTS_MARGIN_TOP,
	filtersHiddenScrollbarMarginTop = PARTY_LIST_FILTERS_HIDDEN_SCROLLBAR_MARGIN_TOP,
	bindButtonHandlers = bindPartyButtonHandlers,
	collectCreatures = partyCollectCreatures,
	doCreatureFitFilters = partyDoCreatureFitFilters,
	afterButtonSetup = partyAfterButtonSetup,
	afterButtonUpdate = partyAfterButtonUpdate,
	onShowStatusChange = function(_, instance, creature)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.updateShowStatus then
			btn:updateShowStatus(true)
		end
	end,
	onShieldChange = partyOnShieldChange,
	shouldRemoveOnDisappear = partyShouldRemoveOnDisappear,
	onCreatureRemoved = partyOnCreatureRemoved,
	getButtonVisibility = function()
		return true
	end,
	refreshFilterTooltips = refreshAllPartyFilterButtonTooltips,
	handleLocalPlayerMove = function(instance, newPos, oldPos, sortType)
		for _, button in pairs(instance.battleButtons) do
			if button and button.update then
				button:update()
			end
		end
	end,
	handleCreatureMove = function(instance, creature, newPos, oldPos, sortType)
		local button = instance.battleButtons[creature:getId()]

		if button and button.update then
			button:update()
		end
	end
})
PartyListManager.refreshFilterTooltips = refreshAllPartyFilterButtonTooltips

function onFilterButtonClick(button)
	local mainInstance = PartyListManager.instances[0]

	if not mainInstance then
		return
	end

	-- @onClick runs before the checkable widget toggles; flip state explicitly (same as battle list).
	togglePartyFilterButton(button)

	if PartyListManager.refreshFilterTooltips then
		PartyListManager:refreshFilterTooltips(mainInstance)
	end

	mainInstance:saveHideButtonStates()
	mainInstance:checkCreatures()
	refreshPartyFilterButtonTooltip(button)
end

local function partyConnecting()
	if partyEventsConnected then
		return
	end

	CreatureListEventHub.connect()

	partyEventsConnected = true

	for _, instance in pairs(PartyListManager.instances) do
		instance:checkCreatures()
	end
end

local function partyDisconnecting()
	if not partyEventsConnected then
		return
	end

	CreatureListEventHub.disconnect()

	partyEventsConnected = false
end

function onOpen()
	syncPartyMainPanelButton()
	partyConnecting()

	local mainInstance = PartyListManager.instances[0]

	if mainInstance then
		local filters = mainInstance:loadFilters()
		local hasAnySortFilter = false

		for filterName, isActive in pairs(filters) do
			if isActive and (filterName:find("sortAscBy") or filterName:find("sortDescBy")) then
				hasAnySortFilter = true

				break
			end
		end

		if not hasAnySortFilter then
			filters.sortAscByDisplayTime = true

			g_settings.mergeNode(mainInstance:getSettingsKey(), {
				filters = filters
			})
			scheduleEvent(function()
				mainInstance:checkCreatures()
			end, 100)
		else
			mainInstance:checkCreatures()
		end
	end
end

function onClose()
	syncPartyMainPanelButton()
end

function toggle()
	if partyButton:isOn() then
		partyWindow:closeAndForgetLayout()
	else
		if g_game.isOnline() then
			partyConnecting()
		end

		if not partyWindow:getParent() then
			local panel = modules.game_interface.findContentPanelAvailable(partyWindow, partyWindow:getMinimumHeight())

			if not panel then
				return
			end

			panel:addChild(partyWindow)
		end

		partyWindow:open()
	end

	syncPartyMainPanelButton()
end

function init()
	if initPartyVitalsProtocol then
		initPartyVitalsProtocol()
	end

	g_ui.importStyle("partybutton")

	partyButton = modules.game_mainpanel.addToggleButton("partyWidget", tr("Party List"), "/images/options/button_party_list", toggle, false, 2)
	partyWindow = g_ui.loadUI("party")

	local mainInstance = PartyListManager:createInstance(0, tr("Party List"))

	mainInstance.window = partyWindow
	PartyListManager.instances[0] = mainInstance
	partyPanel = partyWindow:recursiveGetChildById("partyPanel")
	mainInstance.panel = partyPanel
	filterPanel = partyWindow:recursiveGetChildById("filterPanel")
	mainInstance.filterPanel = filterPanel
	toggleFilterButton = partyWindow:recursiveGetChildById("toggleFilterButton")
	mainInstance.toggleFilterButton = toggleFilterButton

	Keybind.new("Windows", "Open Party List", "Ctrl+Shift+P", "")
	Keybind.bind("Windows", "Open Party List", {
		{
			type = KEY_DOWN,
			callback = toggle
		}
	})
	Keybind.syncControlButtonTooltip(partyButton, 'partyWidget')

	local scrollbar = partyWindow:getChildById("miniwindowScrollBar")

	if scrollbar then
		scrollbar:mergeStyle({
			["$!on"] = {}
		})
	end

	hideButtons = {}

	for _, v in ipairs(PARTY_HIDE_BUTTON_OPTIONS) do
		hideButtons[v] = partyWindow:recursiveGetChildById(v)

		if hideButtons[v] then
			hideButtons[v].onHoverChange = partyFilterButtonOnHoverChange
			hideButtons[v].onClick = function(btn)
				onFilterButtonClick(btn)
			end
		end
	end

	mainInstance.hideButtons = hideButtons

	setupPartyFilterPanelOverrides(mainInstance)
	mainInstance:loadHideButtonStates()
	migratePartyFilterButtonStates(mainInstance)

	local settings = g_settings.getNode(mainInstance:getSettingsKey())

	if settings and settings.hidingFilters then
		mainInstance:hideFilterPanel()
	else
		local sb = partyWindow:getChildById("miniwindowScrollBar")

		if sb and filterPanel then
			sb:setMarginTop(getPartyListScrollbarMarginTopWithFilters(filterPanel))
		end
	end

	if toggleFilterButton then
		function toggleFilterButton.onClick()
			mainInstance:toggleFilterPanel()
		end
	end

	local newWindowButton = partyWindow:recursiveGetChildById("newWindowButton")

	if newWindowButton then
		newWindowButton:setVisible(false)
	end

	local contextMenuButton = partyWindow:recursiveGetChildById("contextMenuButton")

	if contextMenuButton then
		function contextMenuButton.onClick(widget, mousePos, mouseButton)
			local menu = g_ui.createWidget("PartyListSubMenu")

			menu:setGameMenu(true)

			for _, choice in ipairs(menu:getChildren()) do
				local choiceId = choice:getId()

				if choiceId and choiceId ~= "HorizontalSeparator" then
					choice:setChecked(mainInstance:getFilter(choiceId))

					function choice.onCheckChange()
						mainInstance:setFilter(choiceId)
						menu:destroy()
					end
				end
			end

			menu:display(mousePos or widget:getPosition())

			return true
		end
	end

	local mainLockButton = partyWindow:getChildById("lockButton")

	if mainLockButton then
		local originalOnClick = mainLockButton.onClick

		function mainLockButton.onClick()
			if originalOnClick then
				originalOnClick()
			end

			scheduleEvent(function()
				mainInstance:saveLockState()
			end, 10)
		end
	end

	mainInstance:loadLockState()
	partyWindow:setContentMinimumHeight(80)
	partyWindow:setup()
	connect(g_game, {
		onAttackingCreatureChange = onPartyAttack,
		onFollowingCreatureChange = onPartyFollow,
		onHoveredCreatureChange = onHoveredCreatureChange,
		onGameEnd = onGameEnd,
		onGameStart = onGameStart
	})

	if g_game.isOnline() then
		partyWindow:setupOnStart()
		partyConnecting()
	end

	syncPartyMainPanelButton()
end

function onPartyAttack(creature)
	for _, instance in pairs(PartyListManager.instances) do
		for _, battleButton in pairs(instance.battleButtons) do
			local isTarget = creature and battleButton.creature == creature or false

			if battleButton.isTarget ~= isTarget then
				battleButton.isTarget = isTarget

				battleButton:update()
			end
		end
	end
end

function onPartyFollow(creature)
	for _, instance in pairs(PartyListManager.instances) do
		for _, battleButton in pairs(instance.battleButtons) do
			local isFollowed = creature and battleButton.creature == creature or false

			if battleButton.isFollowed ~= isFollowed then
				battleButton.isFollowed = isFollowed

				battleButton:update()
			end
		end
	end
end

function onGameStart()
	partyWindow:setupOnStart()

	if g_game.isOnline() then
		partyConnecting()
	end

	local mainInstance = PartyListManager.instances[0]

	if mainInstance then
		mainInstance:loadLockState()
		mainInstance:updateTitle()
		scheduleEvent(function()
			mainInstance:checkCreatures()
		end, 500)
	end
end

function onGameEnd()
	PartyListRegistry:clear()

	local mainInstance = PartyListManager.instances[0]

	if mainInstance then
		mainInstance:removeAllCreatures()
	end

	if not SidebarPersistence or not SidebarPersistence.lastSessionActive then
		partyWindow:setParent(nil, true)
	end

	partyDisconnecting()
end

function terminate()
	if terminatePartyVitalsProtocol then
		terminatePartyVitalsProtocol()
	end

	local mainInstance = PartyListManager.instances[0]

	if mainInstance then
		mainInstance:saveFilters()
		mainInstance:saveHideButtonStates()
		mainInstance:saveLockState()
		mainInstance:destroy(true)
	end

	PartyListManager.instances = {}

	PartyListRegistry:clear()
	disconnect(g_game, {
		onAttackingCreatureChange = onPartyAttack,
		onFollowingCreatureChange = onPartyFollow,
		onHoveredCreatureChange = onHoveredCreatureChange,
		onGameEnd = onGameEnd,
		onGameStart = onGameStart
	})
	Keybind.delete("Windows", "Open Party List")

	if partyButton then
		partyButton:destroy()

		partyButton = nil
	end

	if partyWindow then
		partyWindow:destroy()

		partyWindow = nil
	end

	partyPanel = nil
	filterPanel = nil
	toggleFilterButton = nil
	hideButtons = nil
	partyEventsConnected = false
end
