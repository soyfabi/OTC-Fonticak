-- chunkname: @/gamelib/creature_list.lua

CreatureList = {}

local hoveredCreatureButton, hoveredCreatureCursor, hoveredCreatureCursorEvent

CreatureListEventHub = {
	connectCount = 0,
	connected = false,
	managers = {}
}

function CreatureList.tableCopy(t, seen)
	if type(t) ~= "table" then
		return t
	end

	seen = seen or {}

	if seen[t] then
		return seen[t]
	end

	local meta = getmetatable(t)
	local target = {}

	seen[t] = target

	for k, v in pairs(t) do
		target[k] = type(v) == "table" and CreatureList.tableCopy(v, seen) or v
	end

	setmetatable(target, meta)

	return target
end

function CreatureList.tableSize(t)
	if type(t) ~= "table" then
		return 0
	end

	local count = 0

	for _ in pairs(t) do
		count = count + 1
	end

	return count
end

function CreatureList.getDistanceBetween(p1, p2)
	if p2 == nil then
		p2 = {
			y = 0,
			x = 0
		}
	end

	local xd = math.abs(p1.x - p2.x)
	local yd = math.abs(p1.y - p2.y)

	if xd > 0 then
		xd = xd - 1
	end

	if yd > 0 then
		yd = yd - 1
	end

	return xd + yd
end

function CreatureList.canBeSeen(creature)
	return creature and creature:canBeSeen() and creature:getPosition() and modules.game_interface.getMapPanel():isInRange(creature:getPosition())
end

local function getCreatureCursor(creature)
	if not creature then
		return nil
	end

	if g_keyboard.isShiftPressed() then
		return "look"
	elseif CreatureList.isRemotePartyMember(creature) then
		return "look"
	elseif creature:isNpc() then
		return "talk"
	elseif not creature:isLocalPlayer() and not creature:isDead() then
		return "attack"
	end

	return nil
end

local function setCreatureCursor(cursor)
	if cursor == hoveredCreatureCursor then
		return
	end

	if hoveredCreatureCursor then
		g_mouse.popCursor(hoveredCreatureCursor)

		hoveredCreatureCursor = nil
	end

	if cursor and g_mouse.pushCursor(cursor) then
		hoveredCreatureCursor = cursor
	end
end

local function clearCreatureCursor(button)
	if button and hoveredCreatureButton ~= button then
		return
	end

	hoveredCreatureButton = nil

	if hoveredCreatureCursorEvent then
		removeEvent(hoveredCreatureCursorEvent)

		hoveredCreatureCursorEvent = nil
	end

	setCreatureCursor(nil)
end

local function creatureListButtonHovered(button)
	if not button or button:isDestroyed() then
		return false
	end

	local hoverState = button.isHovered
	if type(hoverState) == 'boolean' then
		if hoverState then
			return true
		end

		if button.containsPoint then
			local mousePos = g_window.getMousePosition()
			if mousePos and button:containsPoint(mousePos) then
				return true
			end
		end

		return false
	end

	local ok, hovered = pcall(function()
		return button:isHovered(true)
	end)

	return ok and hovered or false
end

local function updateCreatureCursor()
	local button = hoveredCreatureButton

	if not button or button:isDestroyed() or not creatureListButtonHovered(button) or not button.creature then
		clearCreatureCursor(button)

		return
	end

	setCreatureCursor(getCreatureCursor(button.creature))
end

local function showCreatureCursor(button)
	if hoveredCreatureButton ~= button then
		clearCreatureCursor()

		hoveredCreatureButton = button
	end

	setCreatureCursor(getCreatureCursor(button.creature))

	if hoveredCreatureButton and not hoveredCreatureCursorEvent then
		hoveredCreatureCursorEvent = cycleEvent(updateCreatureCursor, 25)
	end
end

function CreatureList.onButtonHoverChange(button, hovered)
	if not button or not button.creature then
		return
	end

	if hovered then
		g_game.setHoveredCreature(button.creature)
		showCreatureCursor(button)
	else
		g_game.clearHoveredCreature(button.creature)
		clearCreatureCursor(button)
	end
end

function CreatureList.syncHoveredCreature(manager, hoveredCreature)
	if not manager or not manager.instances then
		return
	end

	local hoveredId = hoveredCreature and hoveredCreature:getId() or nil

	for _, instance in pairs(manager.instances) do
		for creatureId, button in pairs(instance.battleButtons or {}) do
			local isHovered = hoveredId ~= nil and creatureId == hoveredId

			if button.hoveredMark ~= isHovered then
				button.hoveredMark = isHovered

				button:update()
			end
		end
	end
end

function CreatureList.isPartyInvitePendingShield(shield)
	return shield == ShieldWhiteYellow or shield == ShieldWhiteBlue
end

function CreatureList.isConfirmedPartyMemberShield(shield)
	return shield == ShieldBlue or shield == ShieldYellow or shield == ShieldBlueSharedExp or shield == ShieldYellowSharedExp or shield == ShieldBlueNoSharedExpBlink or shield == ShieldYellowNoSharedExpBlink or shield == ShieldBlueNoSharedExp or shield == ShieldYellowNoSharedExp
end

function CreatureList.isPartyMemberShield(shield)
	return CreatureList.isPartyInvitePendingShield(shield) or CreatureList.isConfirmedPartyMemberShield(shield)
end

function CreatureList.isRemotePartyMember(creature)
	if not creature or not creature:isPlayer() or creature:isLocalPlayer() then
		return false
	end

	return CreatureList.isConfirmedPartyMemberShield(creature:getShield())
end

function CreatureList.isPartyLeaderShield(shield)
	return shield == ShieldWhiteYellow or shield == ShieldYellow or shield == ShieldYellowSharedExp or shield == ShieldYellowNoSharedExpBlink or shield == ShieldYellowNoSharedExp
end

function CreatureList.isRemotePartyLeader(creature)
	if not CreatureList.isRemotePartyMember(creature) then
		return false
	end

	return CreatureList.isPartyLeaderShield(creature:getShield())
end

local vocationNamesByServerId = {
	[VocationsServer.None] = "No Vocation",
	[VocationsServer.Sorcerer] = "Sorcerer",
	[VocationsServer.Druid] = "Druid",
	[VocationsServer.Paladin] = "Paladin",
	[VocationsServer.Knight] = "Knight",
	[VocationsServer.MasterSorcerer] = "Master Sorcerer",
	[VocationsServer.ElderDruid] = "Elder Druid",
	[VocationsServer.RoyalPaladin] = "Royal Paladin",
	[VocationsServer.EliteKnight] = "Elite Knight",
	[VocationsServer.Monk] = "Monk",
	[VocationsServer.ExaltedMonk] = "Exalted Monk",
}

function CreatureList.getPartyMemberVocationName(creature)
	if not creature or not creature.getVocation then
		return "Unknown Vocation"
	end

	if creature:isLocalPlayer() and creature.getVocationNameByClientId then
		return creature:getVocationNameByClientId()
	end

	local vocation = creature:getVocation()
	local name = vocationNamesByServerId[vocation]

	if name then
		return name
	end

	if vocationNamesByClientId and vocationNamesByClientId[vocation] then
		return vocationNamesByClientId[vocation]
	end

	return "Unknown Vocation"
end

function CreatureList.getPartyMemberLevel(creature)
	if not creature or not creature.getId then
		return nil
	end

	local cached

	if modules.game_party and modules.game_party.getPartyVitalsCacheTable then
		cached = modules.game_party.getPartyVitalsCacheTable()[creature:getId()]
	else
		cached = PartyVitalsCache and PartyVitalsCache[creature:getId()]
	end

	if cached and cached.level and cached.level > 0 then
		return cached.level
	end

	return nil
end

function CreatureList.getPartyMemberVocationNameByServerId(vocationId)
	return vocationNamesByServerId[vocationId] or "Unknown Vocation"
end

function CreatureList.buildPartyMemberPinTooltip(creature)
	if not creature then
		return tr("Party member")
	end

	local name = creature:getName() or tr("Party member")
	local level = CreatureList.getPartyMemberLevel(creature)
	local title = level and string.format("%s (%d)", name, level) or name
	local vocation = CreatureList.getPartyMemberVocationName(creature)

	return string.format("%s\n%s: %s", title, tr("Vocation"), vocation)
end

function CreatureList.buildPartyMemberPinTooltipFromCache(creatureId)
	local cached

	if modules.game_party and modules.game_party.getPartyVitalsCacheTable then
		cached = modules.game_party.getPartyVitalsCacheTable()[creatureId]
	else
		cached = PartyVitalsCache and PartyVitalsCache[creatureId]
	end

	if not cached then
		return tr("Party member")
	end

	local name = cached.name or tr("Party member")
	local level = cached.level
	local title = level and level > 0 and string.format("%s (%d)", name, level) or name
	local vocation = CreatureList.getPartyMemberVocationNameByServerId(cached.vocation or 0)

	return string.format("%s\n%s: %s", title, tr("Vocation"), vocation)
end

function CreatureList.isPartyMemberLeavingShield(shield)
	return shield == ShieldNone or shield == ShieldGray
end

function CreatureList.BSComparator(a, b)
	return b < a and -1 or a < b and 1 or 0
end

function CreatureList.BSComparatorSortType(a, b, sortType, id)
	local comparatorA, comparatorB

	if sortType == "distance" then
		comparatorA, comparatorB = a.distance, type(b) == "table" and b.distance or b
	elseif sortType == "health" then
		comparatorA, comparatorB = a.healthpercent, type(b) == "table" and b.healthpercent or b
	elseif sortType == "age" then
		comparatorA, comparatorB = a.age, type(b) == "table" and b.age or b
	elseif sortType == "name" then
		comparatorA, comparatorB = a.name:lower(), type(b) == "table" and b.name:lower() or b
	end

	if comparatorA == nil or comparatorB == nil then
		return 0
	end

	if comparatorB < comparatorA then
		return -1
	elseif comparatorA < comparatorB then
		return 1
	else
		if id and b and b.id then
			return a.id > b.id and -1 or a.id < b.id and 1 or 0
		end

		return 0
	end
end

function CreatureList.binarySearch(tbl, value, comparator, ...)
	comparator = comparator or CreatureList.BSComparator

	local mini, maxi = 1, #tbl

	while mini <= maxi do
		local mid = math.floor((maxi + mini) / 2)
		local tmpValue = comparator(tbl[mid], value, ...)

		if tmpValue == 0 then
			return mid
		elseif tmpValue < 0 then
			maxi = mid - 1
		else
			mini = mid + 1
		end
	end

	return nil
end

function CreatureList.binaryInsert(tbl, value, comparator, ...)
	comparator = comparator or CreatureList.BSComparator

	local mini, maxi = 1, #tbl
	local state, mid = 0, 1

	while mini <= maxi do
		mid = math.floor((maxi + mini) / 2)

		if comparator(tbl[mid], value, ...) < 0 then
			maxi, state = mid - 1, 0
		else
			mini, state = mid + 1, 1
		end
	end

	table.insert(tbl, mid + state, value)

	return mid + state
end

CreatureList.DEFAULT_FILTERS = {
	sortDescByDistance = false,
	sortAscByDistance = false,
	sortDescByDisplayTime = false,
	sortAscByDisplayTime = true,
	sortDescByName = false,
	sortAscByName = false,
	sortDescByHitPoints = false,
	sortAscByHitPoints = false
}
CreatureList.Instance = {
	lastAge = 0,
	name = "Creature List",
	binaryTree = {},
	battleButtons = {},
	settings = {}
}

function CreatureList.Instance:new(manager, id, customName)
	local instance = {}

	setmetatable(instance, {
		__index = self
	})

	instance.manager = manager
	instance.id = id or manager.nextId
	instance.binaryTree = {}
	instance.battleButtons = {}
	instance.lastBattleButtonSwitched = nil
	instance.lastAge = 0
	instance.name = customName or manager.config.defaultTitle
	instance.settings = {
		sortOrder = "A",
		hidingFilters = false,
		sortType = "name",
		filters = CreatureList.tableCopy(CreatureList.DEFAULT_FILTERS),
		customName = instance.name
	}

	return instance
end

function CreatureList.Instance:getSettingsKey()
	if self.id == 0 then
		return self.manager.config.settingsPrefix
	end

	return self.manager.config.settingsPrefix .. "_" .. self.id
end

function CreatureList.Instance:loadFilters()
	local settings = g_settings.getNode(self:getSettingsKey())

	if not settings or not settings.filters then
		return CreatureList.tableCopy(CreatureList.DEFAULT_FILTERS)
	end

	return settings.filters
end

function CreatureList.Instance:saveFilters()
	g_settings.mergeNode(self:getSettingsKey(), {
		filters = self:loadFilters()
	})
end

function CreatureList.Instance:saveHideButtonStates()
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

function CreatureList.Instance:saveLockState()
	if self.window then
		local isLocked = self.window:getSettings("locked") or false
		local lockButton = self.window:getChildById("lockButton")

		if lockButton then
			isLocked = lockButton:isOn()
		end

		g_settings.mergeNode(self:getSettingsKey(), {
			isLocked = isLocked
		})
	end
end

function CreatureList.Instance:loadLockState()
	if not self.window then
		return false
	end

	local settings = g_settings.getNode(self:getSettingsKey())

	if settings and settings.isLocked ~= nil then
		local isLocked = settings.isLocked
		local lockButton = self.window:getChildById("lockButton")

		if isLocked then
			self.window:lock(true)

			if lockButton then
				lockButton:setOn(true)
			end
		else
			self.window:unlock(true)

			if lockButton then
				lockButton:setOn(false)
			end
		end

		return isLocked
	end

	return false
end

function CreatureList.Instance:loadHideButtonStates()
	if not self.hideButtons then
		return
	end

	local settings = g_settings.getNode(self:getSettingsKey())
	local saved = settings and settings.hideButtons
	local format = settings and settings.hideButtonsFormat
	local legacyInvert = not format or format < self.manager.config.hideButtonsFormat

	for _, buttonName in ipairs(self.manager.config.hideButtonOptions) do
		local button = self.hideButtons[buttonName]

		if button then
			local v = saved and saved[buttonName]

			if v ~= nil then
				button:setChecked(legacyInvert and not v or v)
			else
				button:setChecked(true)
			end
		end
	end

	if self.manager.refreshFilterTooltips then
		self.manager:refreshFilterTooltips(self)
	end
end

function CreatureList.Instance:getFilter(filter)
	local filters = self:loadFilters()
	local value = filters[filter]

	if value ~= nil then
		return value
	end

	return CreatureList.DEFAULT_FILTERS[filter] or false
end

function CreatureList.Instance:setFilter(filter)
	local filters = self:loadFilters()
	local value = filters[filter]

	if value == nil then
		value = CreatureList.DEFAULT_FILTERS[filter]

		if value == nil then
			return false
		end
	end

	if filter:find("sortAscBy") or filter:find("sortDescBy") then
		for filterName, _ in pairs(CreatureList.DEFAULT_FILTERS) do
			if filterName ~= filter and (filterName:find("sortAscBy") or filterName:find("sortDescBy")) then
				filters[filterName] = false
			end
		end
	end

	filters[filter] = not value

	g_settings.mergeNode(self:getSettingsKey(), {
		filters = filters
	})
	scheduleEvent(function()
		self:checkCreatures()
	end, 50)

	return true
end

function CreatureList.Instance:getSortType()
	local filters = self:loadFilters()

	for filterName, isActive in pairs(filters) do
		if isActive and (filterName:find("sortAscBy") or filterName:find("sortDescBy")) then
			if filterName:find("DisplayTime") then
				return "age"
			elseif filterName:find("Distance") then
				return "distance"
			elseif filterName:find("HitPoints") then
				return "health"
			elseif filterName:find("Name") then
				return "name"
			end
		end
	end

	return "name"
end

function CreatureList.Instance:getSortOrder()
	local filters = self:loadFilters()

	for filterName, isActive in pairs(filters) do
		if isActive and (filterName:find("sortAscBy") or filterName:find("sortDescBy")) then
			return filterName:find("sortAscBy") and "A" or "D"
		end
	end

	return "A"
end

function CreatureList.Instance:isSortAsc()
	return self:getSortOrder() == "A"
end

function CreatureList.Instance:getName()
	local settings = g_settings.getNode(self:getSettingsKey())

	if settings and settings.customName then
		return settings.customName
	end

	return self.manager.config.defaultTitle
end

function CreatureList.Instance:setName(name)
	local settings = g_settings.getNode(self:getSettingsKey()) or {}

	settings.customName = (name == nil or name == "") and self.manager.config.defaultTitle or name

	g_settings.mergeNode(self:getSettingsKey(), settings)
	self:updateTitle()

	if self.id ~= 0 and not self.manager.isRestoring then
		self.manager:saveInstancesState()
	end
end

function CreatureList.Instance:updateTitle()
	if self.window then
		local titleLabel = self.window:recursiveGetChildById("miniwindowTitle")

		if titleLabel then
			local title = self:getName()

			if string.len(title) > 11 then
				title = string.sub(title, 1, 8) .. "..."
			end

			titleLabel:setText(title)
		end
	end
end

function CreatureList.Instance:setHidingFilters(state)
	g_settings.mergeNode(self:getSettingsKey(), {
		hidingFilters = state
	})
end

function CreatureList.Instance:isHidingFilters()
	local settings = g_settings.getNode(self:getSettingsKey())

	if not settings then
		return false
	end

	return settings.hidingFilters
end

function CreatureList.Instance:getScrollbarMarginTopWithFilters()
	local h = self.filterPanel and self.filterPanel:getHeight() or 0

	if h <= 0 then
		h = 46
	end

	return 17 + h - 1 + 1
end

function CreatureList.Instance:hideFilterPanel()
	self.filterPanel.originalHeight = self.filterPanel:getHeight()

	self.filterPanel:setHeight(0)

	if self.toggleFilterButton then
		self.toggleFilterButton:getParent():setMarginTop(0)
		self.toggleFilterButton:setOn(false)
	end

	self:setHidingFilters(true)

	local sep = self.window:recursiveGetChildById("HorizontalSeparator")

	if sep then
		sep:setVisible(false)
	end

	self.filterPanel:setVisible(false)

	local contentsPanel = self.window:recursiveGetChildById("contentsPanel")

	if contentsPanel then
		contentsPanel:setMarginTop(self.manager.config.filtersHiddenContentsMarginTop)
	end

	local scrollbar = self.window:getChildById("miniwindowScrollBar")

	if scrollbar then
		scrollbar:setMarginTop(self.manager.config.filtersHiddenScrollbarMarginTop)
	end
end

function CreatureList.Instance:showFilterPanel()
	if self.toggleFilterButton then
		self.toggleFilterButton:getParent():setMarginTop()
		self.toggleFilterButton:setOn(true)
	end

	if not self.filterPanel.originalHeight then
		self.filterPanel.originalHeight = 40
	end

	self.filterPanel:setHeight(self.filterPanel.originalHeight)
	self:setHidingFilters(false)

	local sep = self.window:recursiveGetChildById("HorizontalSeparator")

	if sep then
		sep:setVisible(true)
	end

	self.filterPanel:setVisible(true)

	local contentsPanel = self.window:recursiveGetChildById("contentsPanel")

	if contentsPanel then
		contentsPanel:setMarginTop(0)
	end

	local scrollbar = self.window:getChildById("miniwindowScrollBar")

	if scrollbar then
		scrollbar:setMarginTop(self:getScrollbarMarginTopWithFilters())
	end
end

function CreatureList.Instance:toggleFilterPanel()
	if self.filterPanel:isVisible() then
		self:hideFilterPanel()
	else
		self:showFilterPanel()
	end
end

function CreatureList.Instance:onFilterButtonClick(button)
	button:setChecked(not button:isChecked())

	if self.manager.refreshFilterTooltips then
		self.manager:refreshFilterTooltips(self)
	end

	self:saveHideButtonStates()
	self:checkCreatures()
end

function CreatureList.Instance:getAttributeByOrderType(battleButton, orderType)
	if battleButton.data then
		local data = battleButton.data

		if orderType == "distance" then
			return {
				distance = data.distance
			}
		elseif orderType == "health" then
			return {
				healthpercent = data.healthpercent
			}
		elseif orderType == "age" then
			return {
				age = data.age
			}
		else
			return {
				name = data.name
			}
		end
	end

	return false
end

function CreatureList.Instance:correctBattleButtons(sortOrder)
	self.panel:disableUpdateTemporarily()

	sortOrder = sortOrder or self:getSortOrder()

	local start = sortOrder == "A" and 1 or #self.binaryTree
	local finish = #self.binaryTree - start + 1
	local increment = start <= finish and 1 or -1
	local index = 1

	for i = start, finish, increment do
		local v = self.binaryTree[i]
		local battleButton = self.battleButtons[v.id]

		if battleButton ~= nil then
			self.panel:moveChildToIndex(battleButton, index)

			index = index + 1
		end
	end

	return true
end

function CreatureList.Instance:reSort(oldSortType, newSortType, oldSortOrder, newSortOrder)
	if #self.binaryTree > 1 then
		if newSortType and newSortType ~= oldSortType then
			self:checkCreatures()
		end

		if newSortOrder then
			self:correctBattleButtons(newSortOrder)
		end
	end

	return true
end

function CreatureList.Instance:swap(index, newIndex)
	local highest = newIndex
	local lowest = index

	if newIndex < index then
		highest = index
		lowest = newIndex
	end

	local tmp = self.binaryTree[lowest]

	self.binaryTree[lowest] = self.binaryTree[highest]
	self.binaryTree[highest] = tmp
end

function CreatureList.Instance:removeAllCreatures()
	self:removeCreature(false, true)
end

function CreatureList.Instance:removeCreature(creature, all)
	if all then
		self.binaryTree = {}
		self.lastBattleButtonSwitched = nil

		for _, v in pairs(self.battleButtons) do
			self.manager.buttonPool:release(v)
		end

		self.battleButtons = {}

		return true
	end

	local creatureId = creature:getId()
	local battleButton = self.battleButtons[creatureId]

	if not battleButton then
		return false
	end

	if self.lastBattleButtonSwitched == battleButton then
		self.lastBattleButtonSwitched = nil
	end

	local sortType = self:getSortType()
	local valuetoSearch = self:getAttributeByOrderType(battleButton, sortType)

	if not valuetoSearch then
		return false
	end

	valuetoSearch.id = creatureId

	local index = CreatureList.binarySearch(self.binaryTree, valuetoSearch, CreatureList.BSComparatorSortType, sortType, creatureId)

	if index == nil or creatureId ~= self.binaryTree[index].id then
		for i, entry in ipairs(self.binaryTree) do
			if entry.id == creatureId then
				index = i

				break
			end
		end
	end

	if index ~= nil and creatureId == self.binaryTree[index].id then
		local creatureListSize = #self.binaryTree

		if index < creatureListSize then
			for i = index, creatureListSize - 1 do
				local tmp = self.binaryTree[i]

				self.binaryTree[i] = self.binaryTree[i + 1]
				self.binaryTree[i + 1] = tmp
			end
		end

		self.binaryTree[creatureListSize] = nil

		self.manager.buttonPool:release(battleButton)

		self.battleButtons[creatureId] = nil

		return true
	end

	return false
end

function CreatureList.Instance:addCreature(creature, sortType)
	local cfg = self.manager.config
	local creatureId = creature:getId()
	local battleButton = self.battleButtons[creatureId]

	if battleButton then
		if battleButton.creature then
			battleButton:update()
		end

		if cfg.afterButtonUpdate then
			cfg.afterButtonUpdate(self, battleButton, creature)
		end
	else
		if cfg.requiresPosition and creature:getPosition() == nil then
			return
		end

		local newCreature = {}

		newCreature.id = creatureId
		newCreature.name = creature:getName():lower()
		newCreature.healthpercent = creature:getHealthPercent()

		local playerPos = g_game.getLocalPlayer() and g_game.getLocalPlayer():getPosition()
		local creaturePos = creature:getPosition()

		if playerPos and creaturePos then
			newCreature.distance = CreatureList.getDistanceBetween(playerPos, creaturePos)
		else
			newCreature.distance = cfg.offMapDistance or 9999
		end

		newCreature.age = self.lastAge + 1
		self.lastAge = self.lastAge + 1
		sortType = sortType or self:getSortType()

		local newIndex = CreatureList.binaryInsert(self.binaryTree, newCreature, CreatureList.BSComparatorSortType, sortType, true)

		battleButton = self.manager.buttonPool:get()

		battleButton:setup(creature, true)

		if cfg.afterButtonSetup then
			cfg.afterButtonSetup(self, battleButton, creature)
		end

		battleButton.data = {}

		for i, v in pairs(newCreature) do
			battleButton.data[i] = v
		end

		self.battleButtons[creatureId] = battleButton

		if creature == g_game.getAttackingCreature() then
			battleButton.isTarget = true

			if battleButton.creature then
				battleButton:update()
			end
		end

		if creature == g_game.getFollowingCreature() then
			battleButton.isFollowed = true

			if battleButton.creature then
				battleButton:update()
			end
		end

		if self:isSortAsc() then
			self.panel:insertChild(newIndex, battleButton)
		else
			self.panel:insertChild(#self.binaryTree - newIndex + 1, battleButton)
		end
	end

	local visible = cfg.getButtonVisibility and cfg.getButtonVisibility(self, creature) or CreatureList.canBeSeen(creature)

	battleButton:setVisible(visible)
	self.panel:getLayout():update()
end

function CreatureList.Instance:checkCreatures()
	if not self.panel or not g_game.isOnline() then
		return false
	end

	self.panel:disableUpdateTemporarily()

	local player = g_game.getLocalPlayer()

	if not player then
		return false
	end

	if self.manager.config.requiresPlayerPosition and not player:getPosition() then
		return false
	end

	self:removeAllCreatures()

	local sortType = self:getSortType()
	local creatures = self.manager.config.collectCreatures(self)

	for _, creature in ipairs(creatures) do
		if self:doCreatureFitFilters(creature) then
			self:addCreature(creature, sortType)
		end
	end
end

function CreatureList.Instance:destroy(saveSettings)
	if not saveSettings then
		local settingsKey = self:getSettingsKey()

		g_settings.mergeNode(settingsKey, {})

		if self.id ~= 0 then
			self.manager:removeSavedInstanceState(self.id)
		end
	else
		self:saveFilters()
		self:saveHideButtonStates()
		self:saveLockState()
	end

	for _, v in pairs(self.battleButtons) do
		self.manager.buttonPool:release(v)
	end

	self.binaryTree = {}
	self.battleButtons = {}
	self.lastBattleButtonSwitched = nil
	self.settings = nil

	if self.window and self.id ~= 0 then
		self.window:destroy()

		self.window = nil
	end

	self.panel = nil
	self.filterPanel = nil
	self.toggleFilterButton = nil
	self.hideButtons = nil
	self.manager.instances[self.id] = nil
end

function CreatureList.createButtonPool(config)
	local bindHandlers = config.bindButtonHandlers

	if not ObjectPool then
		return {
			get = function()
				local widget = g_ui.createWidget(config.buttonWidget)

				widget:show()
				widget:setOn(true)

				if bindHandlers then
					bindHandlers(widget)
				end

				return widget
			end,
			release = function(obj)
				if obj and obj:getParent() then
					obj:getParent():removeChild(obj)
				end
			end
		}
	end

	return ObjectPool.new(function()
		local widget = g_ui.createWidget(config.buttonWidget)

		widget:show()
		widget:setOn(true)

		if bindHandlers then
			bindHandlers(widget)
		end

		return widget
	end, function(obj)
		if obj.data then
			obj.data = nil
		end

		if obj.resetState then
			obj:resetState()
		end

		local parent = obj:getParent()

		if parent then
			parent:removeChild(obj)
		end
	end)
end

function CreatureList.createManager(config)
	local manager = {
		nextId = 1,
		isRestoring = false,
		config = config,
		instances = {}
	}
	local InstanceClass = {}

	setmetatable(InstanceClass, {
		__index = CreatureList.Instance
	})

	function InstanceClass:doCreatureFitFilters(creature)
		if config.doCreatureFitFilters then
			return config.doCreatureFitFilters(self, creature)
		end

		return false
	end

	manager.InstanceClass = InstanceClass
	manager.buttonPool = CreatureList.createButtonPool(config)

	function manager:getMainInstance()
		return self.instances[0]
	end

	function manager:register()
		for _, m in ipairs(CreatureListEventHub.managers) do
			if m == self then
				return
			end
		end

		table.insert(CreatureListEventHub.managers, self)
	end

	function manager:saveInstancesState()
		if not config.instancesSettingsKey then
			return
		end

		local instancesData = {}

		for id, instance in pairs(self.instances) do
			if id ~= 0 then
				local windowPos = instance.window and instance.window:getPosition()
				local windowSize = instance.window and instance.window:getSize()
				local isLocked = false
				local isMinimized = false

				if instance.window then
					isLocked = instance.window:getSettings("locked") or false

					local lockButton = instance.window:getChildById("lockButton")

					if lockButton then
						isLocked = lockButton:isOn()
					end

					if instance.window:isVisible() then
						isMinimized = instance.window:isOn()
					end
				end

				instancesData[id] = {
					id = instance.id,
					name = instance:getName(),
					isOpen = instance.window and instance.window:isVisible(),
					isMinimized = isMinimized,
					windowPos = windowPos,
					windowSize = windowSize,
					isHidingFilters = instance:isHidingFilters(),
					isLocked = isLocked
				}

				instance:saveFilters()
				instance:saveHideButtonStates()
				instance:saveLockState()
			end
		end

		local mainInstance = self.instances[0]

		if mainInstance then
			mainInstance:saveLockState()
			mainInstance:saveFilters()
			mainInstance:saveHideButtonStates()
		end

		g_settings.mergeNode(config.instancesSettingsKey, instancesData)
	end

	function manager:removeSavedInstanceState(id)
		if not config.instancesSettingsKey then
			return
		end

		local instancesData = g_settings.getNode(config.instancesSettingsKey) or {}

		instancesData[tostring(id)] = nil

		g_settings.mergeNode(config.instancesSettingsKey, instancesData)
	end

	function manager:startPeriodicSave()
		self:stopPeriodicSave()

		self.autoSaveEvent = scheduleEvent(function()
			if g_game.isOnline() and not self.isRestoring then
				self:saveInstancesState()
				self:startPeriodicSave()
			end
		end, 30000)
	end

	function manager:stopPeriodicSave()
		if self.autoSaveEvent then
			removeEvent(self.autoSaveEvent)

			self.autoSaveEvent = nil
		end
	end

	function manager:createInstance(id, customName)
		return InstanceClass:new(self, id, customName)
	end

	manager:register()

	return manager
end

function CreatureListEventHub.connect()
	CreatureListEventHub.connectCount = CreatureListEventHub.connectCount + 1

	if CreatureListEventHub.connected then
		return
	end

	connect(LocalPlayer, {
		onPositionChange = CreatureListEventHub.onCreaturePositionChange
	})
	connect(Creature, {
		onSkullChange = CreatureListEventHub.onSkullChange,
		onEmblemChange = CreatureListEventHub.onEmblemChange,
		onOutfitChange = CreatureListEventHub.onOutfitChange,
		onHealthPercentChange = CreatureListEventHub.onHealthPercentChange,
		onManaPercentChange = CreatureListEventHub.onManaPercentChange,
		onShowStatusChange = CreatureListEventHub.onShowStatusChange,
		onVocationChange = CreatureListEventHub.onVocationChange,
		onShieldChange = CreatureListEventHub.onShieldChange,
		onPositionChange = CreatureListEventHub.onCreaturePositionChange,
		onAppear = CreatureListEventHub.onCreatureAppear,
		onDisappear = CreatureListEventHub.onCreatureDisappear
	})
	connect(UIMap, {
		onZoomChange = CreatureListEventHub.onZoomChange
	})

	CreatureListEventHub.connected = true

	for _, manager in ipairs(CreatureListEventHub.managers) do
		for _, instance in pairs(manager.instances) do
			instance:checkCreatures()
		end
	end
end

function CreatureListEventHub.disconnect()
	if CreatureListEventHub.connectCount > 0 then
		CreatureListEventHub.connectCount = CreatureListEventHub.connectCount - 1
	end

	if CreatureListEventHub.connectCount > 0 or not CreatureListEventHub.connected then
		return
	end

	disconnect(LocalPlayer, {
		onPositionChange = CreatureListEventHub.onCreaturePositionChange
	})
	disconnect(Creature, {
		onSkullChange = CreatureListEventHub.onSkullChange,
		onEmblemChange = CreatureListEventHub.onEmblemChange,
		onOutfitChange = CreatureListEventHub.onOutfitChange,
		onHealthPercentChange = CreatureListEventHub.onHealthPercentChange,
		onManaPercentChange = CreatureListEventHub.onManaPercentChange,
		onShowStatusChange = CreatureListEventHub.onShowStatusChange,
		onVocationChange = CreatureListEventHub.onVocationChange,
		onShieldChange = CreatureListEventHub.onShieldChange,
		onPositionChange = CreatureListEventHub.onCreaturePositionChange,
		onAppear = CreatureListEventHub.onCreatureAppear,
		onDisappear = CreatureListEventHub.onCreatureDisappear
	})
	disconnect(UIMap, {
		onZoomChange = CreatureListEventHub.onZoomChange
	})

	CreatureListEventHub.connected = false
end

function CreatureListEventHub.forEachInstance(callback)
	for _, manager in ipairs(CreatureListEventHub.managers) do
		local instances = manager.instances

		if instances then
			for _, instance in pairs(instances) do
				callback(manager, instance)
			end
		end
	end
end

function CreatureListEventHub.onSkullChange(creature, skullId)
	CreatureListEventHub.forEachInstance(function(_, instance)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.updateSkull then
			btn:updateSkull(skullId)
		end
	end)
end

function CreatureListEventHub.onEmblemChange(creature, emblemId)
	CreatureListEventHub.forEachInstance(function(_, instance)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.updateEmblem then
			btn:updateEmblem(emblemId)
		end
	end)
end

function CreatureListEventHub.onManaPercentChange(creature, manaPercent)
	CreatureListEventHub.forEachInstance(function(manager, instance)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.setManaBarPercent then
			btn:setManaBarPercent(manaPercent)
		end

		if manager.config.onManaPercentChange then
			manager.config.onManaPercentChange(manager, instance, creature, manaPercent)
		end
	end)
end

function CreatureListEventHub.onShowStatusChange(creature, showStatus)
	CreatureListEventHub.forEachInstance(function(manager, instance)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.updateShowStatus then
			btn:updateShowStatus(showStatus)
		end

		if manager.config.onShowStatusChange then
			manager.config.onShowStatusChange(manager, instance, creature, showStatus)
		end
	end)
end

function CreatureListEventHub.onVocationChange(creature, vocation)
	CreatureListEventHub.forEachInstance(function(manager, instance)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.creature then
			local creatureWidget = btn:getChildById("creature")

			if btn.updateOutfitPreview then
				btn:updateOutfitPreview(creature:getOutfit())
			elseif creatureWidget then
				creatureWidget:setOutfit(creature:getOutfit())
			end
		end

		if manager.config.onVocationChange then
			manager.config.onVocationChange(manager, instance, creature, vocation)
		end
	end)
end

function CreatureListEventHub.onShieldChange(creature, shieldId)
	CreatureListEventHub.forEachInstance(function(manager, instance)
		local btn = instance.battleButtons[creature:getId()]

		if btn and btn.updatePartyShield then
			btn:updatePartyShield(shieldId)
		end

		if manager.config.onShieldChange then
			manager.config.onShieldChange(manager, instance, creature, shieldId)
		end
	end)
end

function CreatureListEventHub.onHealthPercentChange(creature, healthPercent, oldHealthPercent)
	CreatureListEventHub.forEachInstance(function(manager, instance)
		local creatureId = creature:getId()
		local battleButton = instance.battleButtons[creatureId]

		if not battleButton then
			return
		end

		local sortType = instance:getSortType()
		local newHealthPercent = healthPercent or 0
		local previousHealthPercent = oldHealthPercent

		if previousHealthPercent == nil and battleButton.data then
			previousHealthPercent = battleButton.data.healthpercent
		end

		if previousHealthPercent == nil then
			previousHealthPercent = newHealthPercent
		end

		if newHealthPercent <= 0 then
			instance:removeCreature(creature)

			if manager.config.onCreatureRemoved then
				manager.config.onCreatureRemoved(manager, creature)
			end

			return
		end

		if battleButton.setLifeBarPercent then
			battleButton:setLifeBarPercent(newHealthPercent)
		end

		if battleButton.data then
			battleButton.data.healthpercent = newHealthPercent
		end

		if sortType == "health" and newHealthPercent ~= previousHealthPercent then
			local index = CreatureList.binarySearch(instance.binaryTree, {
				healthpercent = previousHealthPercent,
				id = creatureId
			}, CreatureList.BSComparatorSortType, "health", true)

			if index ~= nil and creatureId == instance.binaryTree[index].id then
				instance.binaryTree[index].healthpercent = newHealthPercent

				if previousHealthPercent < newHealthPercent then
					if index < #instance.binaryTree then
						for i = index, #instance.binaryTree - 1 do
							local a = instance.binaryTree[i]
							local b = instance.binaryTree[i + 1]

							if a.healthpercent > b.healthpercent or a.healthpercent == b.healthpercent and a.id > b.id then
								local tmp = instance.binaryTree[i]

								instance.binaryTree[i] = instance.binaryTree[i + 1]
								instance.binaryTree[i + 1] = tmp
							end
						end
					end
				elseif newHealthPercent < previousHealthPercent and index > 1 then
					for i = index, 2, -1 do
						local a = instance.binaryTree[i - 1]
						local b = instance.binaryTree[i]

						if a.healthpercent > b.healthpercent or a.healthpercent == b.healthpercent and a.id > b.id then
							local tmp = instance.binaryTree[i - 1]

							instance.binaryTree[i - 1] = instance.binaryTree[i]
							instance.binaryTree[i] = tmp
						end
					end
				end

				instance:correctBattleButtons()
			end
		end

		if battleButton.creature then
			battleButton:update()
		end
	end)
end

function CreatureListEventHub.onCreatureAppear(creature)
	if creature:isLocalPlayer() and modules.game_battle and modules.game_battle.updateStaticSquare then
		addEvent(modules.game_battle.updateStaticSquare)
	end

	CreatureListEventHub.forEachInstance(function(manager, instance)
		if instance:doCreatureFitFilters(creature) then
			instance:addCreature(creature, instance:getSortType())
		elseif manager.config.onCreatureAppear then
			manager.config.onCreatureAppear(manager, instance, creature)
		end
	end)
end

function CreatureListEventHub.onCreatureDisappear(creature)
	CreatureListEventHub.forEachInstance(function(manager, instance)
		if manager.config.shouldRemoveOnDisappear and not manager.config.shouldRemoveOnDisappear(instance, creature) then
			return
		end

		instance:removeCreature(creature)
	end)
end

function CreatureListEventHub.onOutfitChange(creature)
	CreatureListEventHub.forEachInstance(function(_, instance)
		local battleButton = instance.battleButtons[creature:getId()]
		local fit = instance:doCreatureFitFilters(creature)

		if battleButton ~= nil and not fit then
			instance:removeCreature(creature)
		elseif battleButton == nil and fit then
			instance:addCreature(creature)
		elseif battleButton then
			local creatureWidget = battleButton:getChildById("creature")

			if battleButton.updateOutfitPreview then
				battleButton:updateOutfitPreview(creature:getOutfit())
			elseif creatureWidget then
				creatureWidget:setOutfit(creature:getOutfit())
			end
		end
	end)
end

function CreatureListEventHub.onZoomChange()
	removeEvent(CreatureListEventHub.zoomEvent)

	CreatureListEventHub.zoomEvent = scheduleEvent(function()
		CreatureListEventHub.forEachInstance(function(_, instance)
			instance:checkCreatures()
		end)
	end, 1000)
end

function CreatureListEventHub.onCreaturePositionChange(creature, newPos, oldPos)
	local localPlayer = g_game.getLocalPlayer()

	if not localPlayer then
		return
	end

	local position = localPlayer:getPosition()

	if not position then
		return
	end

	CreatureListEventHub.forEachInstance(function(manager, instance)
		if not instance.panel then
			return
		end

		instance.panel:disableUpdateTemporarily()

		local sortType = instance:getSortType()

		if creature:isLocalPlayer() then
			if manager.config.handleLocalPlayerMove then
				manager.config.handleLocalPlayerMove(instance, newPos, oldPos, sortType)
			end
		elseif manager.config.handleCreatureMove then
			manager.config.handleCreatureMove(instance, creature, newPos, oldPos, sortType)
		end
	end)
end
