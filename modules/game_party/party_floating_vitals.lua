-- Floating party member vitals (name + HP/mana), draggable like free action-bar copies.

local PARTY_FLOAT_DRAG_THRESHOLD = 10
local PARTY_FLOAT_SETTINGS_NODE = 'partyFloatingVitalsByCharacter'

local floatingCopies = {}
local floatingLocks = {}
local partyListDragState
local partyListDragCursorActive
local partyListDragCursorNative
local partyListDragGrabber
local partyListDragGhost
local partyListDragMoveHandler
local beginPartyListDrag
local finishPartyListDrag
local clearPartyListDragCursor
local partyWindowCursorMoveHandler
local partyRestorePlacementsEvent

local function isPlacementEnabled()
	return modules.client_options
		and modules.client_options.getOption('freePartyVitalsPlacement') == true
end

local function getRootPanel()
	if gameRootPanel and not gameRootPanel:isDestroyed() then
		return gameRootPanel
	end

	local iface = modules.game_interface

	return iface and iface.gameRootPanel
end

local function getCharacterSettingsKey()
	local player = g_game.getLocalPlayer()

	return player and player:getName() or ''
end

local function findPartyCreature(creatureId)
	if PartyListRegistry and PartyListRegistry.byId then
		local creature = PartyListRegistry.byId[creatureId]

		if creature then
			return creature
		end
	end

	local panel = modules.game_interface and modules.game_interface.getMapPanel()

	if panel then
		for _, spec in ipairs(panel:getSpectators()) do
			if spec:getId() == creatureId then
				return spec
			end
		end
	end

	return g_map.getCreatureById(creatureId)
end

local function applyVitalsToButton(button, creature)
	if not button or not creature then
		return
	end

	local vitals

	if getPartyVitalsForCreature then
		vitals = getPartyVitalsForCreature(creature)
	end

	if vitals and vitals.health and vitals.health <= 100 then
		button:setLifeBarPercent(vitals.health)
	elseif creature.getHealthPercent then
		button:setLifeBarPercent(creature:getHealthPercent())
	end

	if vitals and vitals.mana and vitals.mana <= 100 then
		button:setManaBarPercent(vitals.mana)
	elseif creature.getManaPercent then
		button:setManaBarPercent(creature:getManaPercent())
	end

	if button.updatePartyShield then
		button:updatePartyShield(creature:getShield())
	end

	if button.updateShowStatus then
		button:updateShowStatus(true)
	end
end

local function pushPartyFloatDragCursor(widget)
	if widget._partyFloatDragCursorActive then
		return
	end

	if partyCreatureButtonHoverChange then
		widget.isHovered = false
		partyCreatureButtonHoverChange(widget, false)
	end

	if modules.client_options and modules.client_options.getOption('nativeCursor') then
		g_window.setSystemCursor('cross')
		widget._partyFloatDragCursorActive = true
		widget._partyFloatDragCursorNative = true
	elseif g_mouse.pushCursor('target') then
		widget._partyFloatDragCursorActive = true
		widget._partyFloatDragCursorNative = false
	end
end

local function popPartyFloatDragCursor(widget)
	if not widget or not widget._partyFloatDragCursorActive then
		return
	end

	if widget._partyFloatDragCursorNative then
		g_window.restoreMouseCursor()
	else
		g_mouse.popCursor('target')
	end

	widget._partyFloatDragCursorActive = false
	widget._partyFloatDragCursorNative = false
end

local function clampPosition(widget, pos)
	local parent = widget:getParent()

	if not parent then
		return pos
	end

	local parentRect = parent:getRect()
	local x = math.min(math.max(parentRect.x, pos.x), parentRect.x + parentRect.width - widget:getWidth())
	local y = math.min(math.max(parentRect.y, pos.y), parentRect.y + parentRect.height - widget:getHeight())

	return {
		x = x,
		y = y
	}
end

local function copyOverlapsPosition(copy, position, placedCopies)
	local width = copy:getWidth()
	local height = copy:getHeight()

	for _, placed in ipairs(placedCopies) do
		local otherPosition = placed:getPosition()

		if position.x < otherPosition.x + placed:getWidth() and position.x + width > otherPosition.x
			and position.y < otherPosition.y + placed:getHeight() and position.y + height > otherPosition.y then
			return true
		end
	end

	return false
end

local function findFreeCopyPosition(copy, preferredPosition, placedCopies)
	local root = getRootPanel()

	if not root then
		return preferredPosition
	end

	local width = copy:getWidth()
	local height = copy:getHeight()
	local rootPosition = root:getPosition()
	local minX = rootPosition.x
	local minY = rootPosition.y
	local maxX = minX + math.max(0, root:getWidth() - width)
	local maxY = minY + math.max(0, root:getHeight() - height)
	local origin = {
		x = math.max(minX, math.min(maxX, preferredPosition.x)),
		y = math.max(minY, math.min(maxY, preferredPosition.y))
	}

	if #placedCopies == 0 then
		return origin
	end

	local overlapsAnotherCopy = copyOverlapsPosition(copy, origin, placedCopies)
	local bestPosition = nil
	local bestDistance = math.huge

	for _, placed in ipairs(placedCopies) do
		local anchor = placed:getPosition()
		local candidates = {
			{
				x = anchor.x,
				y = anchor.y - height
			},
			{
				x = anchor.x,
				y = anchor.y + placed:getHeight()
			},
			{
				x = anchor.x - width,
				y = anchor.y
			},
			{
				x = anchor.x + placed:getWidth(),
				y = anchor.y
			}
		}

		for _, candidate in ipairs(candidates) do
			local inBounds = candidate.x >= minX and candidate.y >= minY and candidate.x <= maxX
				and candidate.y <= maxY

			if inBounds and not copyOverlapsPosition(copy, candidate, placedCopies) then
				local dx = candidate.x - origin.x
				local dy = candidate.y - origin.y
				local distance = dx * dx + dy * dy

				if distance < bestDistance then
					bestDistance = distance
					bestPosition = candidate
				end
			end
		end
	end

	local snapDistance = 12

	if bestPosition and (bestDistance <= snapDistance * snapDistance or overlapsAnotherCopy) then
		return bestPosition
	end

	return origin
end

local function collectOtherFloatingCopies(creatureId)
	local others = {}

	for id, other in pairs(floatingCopies) do
		if id ~= creatureId and other and not other:isDestroyed() then
			others[#others + 1] = other
		end
	end

	return others
end

local function resolvePartyFloatingCopyOverlaps(creatureId)
	local copy = floatingCopies[creatureId]

	if not copy or copy:isDestroyed() then
		return
	end

	local resolved = findFreeCopyPosition(copy, copy:getPosition(), collectOtherFloatingCopies(creatureId))

	copy:setPosition(clampPosition(copy, resolved))
end

function savePartyFloatingVitalsPlacements()
	local key = getCharacterSettingsKey()

	if key == '' then
		return
	end

	local placements = {}

	for creatureId, copy in pairs(floatingCopies) do
		if copy and not copy:isDestroyed() then
			placements[tostring(creatureId)] = {
				x = copy:getX(),
				y = copy:getY(),
				locked = floatingLocks[creatureId] == true
			}
		end
	end

	local all = g_settings.getNode(PARTY_FLOAT_SETTINGS_NODE) or {}

	all[key] = placements
	g_settings.setNode(PARTY_FLOAT_SETTINGS_NODE, all)
end

local function bindFloatingCopyDrag(copy, creatureId)
	copy:setDraggable(true)

	copy.onDragEnter = function(widget, mousePos)
		if floatingLocks[creatureId] then
			return false
		end

		widget:breakAnchors()
		widget.movingReference = {
			x = mousePos.x - widget:getX(),
			y = mousePos.y - widget:getY()
		}
		pushPartyFloatDragCursor(widget)

		return true
	end

	copy.onDragMove = function(widget, mousePos)
		if floatingLocks[creatureId] then
			return false
		end

		local clamped = clampPosition(widget, {
			x = mousePos.x - widget.movingReference.x,
			y = mousePos.y - widget.movingReference.y
		})

		widget:move(clamped.x, clamped.y)

		return true
	end

	copy.onDragLeave = function(widget)
		popPartyFloatDragCursor(widget)
		resolvePartyFloatingCopyOverlaps(creatureId)
		savePartyFloatingVitalsPlacements()

		return true
	end
end

local function bindFloatingCopyContextMenu(copy, creatureId)
	copy.onMouseRelease = function(self, mousePos, mouseButton)
		if mouseButton ~= MouseRightButton then
			if partyCreatureButtonMouseRelease then
				return partyCreatureButtonMouseRelease(self, mousePos, mouseButton)
			end

			return false
		end

		local menu = g_ui.createWidget('PopupMenu')

		menu:setGameMenu(true)

		menu:addOption(floatingLocks[creatureId] and tr('Unlock') or tr('Lock'), function()
			floatingLocks[creatureId] = not floatingLocks[creatureId]

			if copy.lockMarker then
				copy.lockMarker:setVisible(floatingLocks[creatureId])
			end

			copy:setDraggable(not floatingLocks[creatureId])
			savePartyFloatingVitalsPlacements()
		end)

		menu:addOption(tr('Remove'), function()
			removePartyFloatingCopy(creatureId)
			savePartyFloatingVitalsPlacements()
		end)
		menu:display(mousePos)

		return true
	end

	copy.onHoverChange = function(button, hovered)
		button.isHovered = hovered

		if button.update then
			button:update()
		end

		if modules.client_options and modules.client_options.getOption('nativeCursor') then
			if hovered then
				g_window.setSystemCursor('hand')
			else
				g_window.restoreMouseCursor()
			end
		end

		if not hovered then
			clearPartyListDragCursor()

			if CreatureList and CreatureList.clearHoverCursor then
				CreatureList.clearHoverCursor()
			end
		end
	end
end

function removePartyFloatingCopy(creatureId)
	local copy = floatingCopies[creatureId]

	floatingCopies[creatureId] = nil
	floatingLocks[creatureId] = nil

	if copy and not copy:isDestroyed() then
		popPartyFloatDragCursor(copy)
		copy:destroy()
	end
end

function createPartyFloatingCopy(sourceButton, position)
	if not isPlacementEnabled() then
		return false
	end

	local creature = sourceButton and sourceButton.creature

	if not creature or not CreatureList.isRemotePartyMember(creature) then
		return false
	end

	local root = getRootPanel()

	if not root then
		return false
	end

	local creatureId = creature:getId()
	local existing = floatingCopies[creatureId]

	if existing and not existing:isDestroyed() then
		existing:setPosition(clampPosition(existing, position))
		resolvePartyFloatingCopyOverlaps(creatureId)
		existing:setVisible(true)
		applyVitalsToButton(existing, creature)
		savePartyFloatingVitalsPlacements()

		return true
	end

	local copy = g_ui.createWidget('PartyFloatingVitals', root)

	copy:setId('partyFloat.' .. creatureId)
	copy.creatureId = creatureId
	copy:setup(creature, true)
	applyVitalsToButton(copy, creature)

	local pos = clampPosition(copy, position)

	copy:setPosition(pos)

	if not copy.lockMarker then
		local lockMarker = g_ui.createWidget('UIWidget', copy)

		lockMarker:setId('partyFloatLockMarker')
		lockMarker:setSize({
			width = 12,
			height = 12
		})
		lockMarker:setImageSize({
			width = 12,
			height = 12
		})
		lockMarker:addAnchor(AnchorLeft, 'parent', AnchorLeft)
		lockMarker:addAnchor(AnchorTop, 'parent', AnchorTop)
		lockMarker:setImageSource('/images/game/actionbar/locked')
		lockMarker:setPhantom(true)
		lockMarker:setVisible(floatingLocks[creatureId] == true)
		copy.lockMarker = lockMarker
	end

	bindFloatingCopyDrag(copy, creatureId)
	bindFloatingCopyContextMenu(copy, creatureId)

	floatingCopies[creatureId] = copy
	resolvePartyFloatingCopyOverlaps(creatureId)
	savePartyFloatingVitalsPlacements()

	return true
end

function refreshPartyFloatingVitalsBars(creatureId, healthPercent, manaPercent)
	local copy = floatingCopies[creatureId]

	if not copy or copy:isDestroyed() then
		return
	end

	if healthPercent <= 100 and copy.setLifeBarPercent then
		copy:setLifeBarPercent(healthPercent)
	end

	if manaPercent <= 100 and copy.setManaBarPercent then
		copy:setManaBarPercent(manaPercent)
	end

	if copy.updateShowStatus then
		copy:updateShowStatus(true)
	end
end

function syncPartyFloatingTargetAndFollow()
	local attacking = g_game.getAttackingCreature()
	local following = g_game.getFollowingCreature()

	for creatureId, copy in pairs(floatingCopies) do
		if copy and not copy:isDestroyed() and copy.creature then
			local isTarget = attacking and copy.creature == attacking or false
			local isFollowed = following and copy.creature == following or false

			if copy.isTarget ~= isTarget or copy.isFollowed ~= isFollowed then
				copy.isTarget = isTarget
				copy.isFollowed = isFollowed

				if copy.update then
					copy:update()
				end
			end
		end
	end
end

function onPartyMemberLeftFloatingHud(creatureId)
	removePartyFloatingCopy(creatureId)
	savePartyFloatingVitalsPlacements()
end

local function widgetContainsPoint(widget, pos)
	if not widget or widget:isDestroyed() then
		return false
	end

	local rect = widget:getRect()

	return pos.x >= rect.x and pos.x <= rect.x + rect.width and pos.y >= rect.y
		and pos.y <= rect.y + rect.height
end

clearPartyListDragCursor = function()
	if not partyListDragCursorActive then
		return
	end

	if partyListDragCursorNative then
		g_window.restoreMouseCursor()
	else
		g_mouse.popCursor('target')
	end

	partyListDragCursorActive = false
	partyListDragCursorNative = false
end

local function getPartyWindow()
	return modules.game_party and modules.game_party.getPartyWindow
		and modules.game_party.getPartyWindow()
end

local function pushPartyListDragCursor()
	if partyListDragCursorActive then
		return
	end

	if modules.client_options and modules.client_options.getOption('nativeCursor') then
		g_window.setSystemCursor('cross')
		partyListDragCursorActive = true
		partyListDragCursorNative = true
	elseif g_mouse.pushCursor('target') then
		partyListDragCursorActive = true
		partyListDragCursorNative = false
	end
end

local function disconnectPartyListDragMove()
	local root = getRootPanel()

	if root and partyListDragMoveHandler then
		disconnect(root, {
			onMouseMove = partyListDragMoveHandler
		})
	end

	partyListDragMoveHandler = nil
end

local function connectPartyListDragMove()
	local root = getRootPanel()

	if not root or partyListDragMoveHandler then
		return
	end

	partyListDragMoveHandler = function(_, mousePos)
		local state = partyListDragState

		if not state or state.dragging or not isPlacementEnabled() then
			return
		end

		local sourceButton = state.button

		if not sourceButton or sourceButton:isDestroyed() then
			partyListDragState = nil
			disconnectPartyListDragMove()

			return
		end

		local dx = mousePos.x - state.startPos.x
		local dy = mousePos.y - state.startPos.y

		if math.abs(dx) + math.abs(dy) >= PARTY_FLOAT_DRAG_THRESHOLD then
			beginPartyListDrag(sourceButton, mousePos)
			disconnectPartyListDragMove()
		end
	end

	connect(root, {
		onMouseMove = partyListDragMoveHandler
	})
end

local function clearPartyListButtonHover(button)
	if not button then
		return
	end

	button.isHovered = false

	if partyCreatureButtonHoverChange then
		partyCreatureButtonHoverChange(button, false)
	end

	clearPartyListDragCursor()

	if CreatureList and CreatureList.clearHoverCursor then
		CreatureList.clearHoverCursor()
	end
end

local function destroyPartyListDragGhost()
	if partyListDragGhost and not partyListDragGhost:isDestroyed() then
		partyListDragGhost:destroy()
	end

	partyListDragGhost = nil
end

local function stopPartyListDragGrabber()
	if not partyListDragGrabber or partyListDragGrabber:isDestroyed() then
		return
	end

	if g_ui.isMouseGrabbed() then
		partyListDragGrabber:ungrabMouse()
	end

	partyListDragGrabber:hide()
	partyListDragGrabber.onMouseMove = nil
	partyListDragGrabber.onMouseRelease = nil
end

local function ensurePartyListDragGrabber()
	local root = getRootPanel()

	if not root then
		return nil
	end

	if not partyListDragGrabber or partyListDragGrabber:isDestroyed() then
		partyListDragGrabber = g_ui.createWidget('UIWidget', root)
		partyListDragGrabber:setId('partyListDragGrabber')
		partyListDragGrabber:setFocusable(false)
		partyListDragGrabber:setPhantom(false)
		partyListDragGrabber:setOpacity(0.01)
		partyListDragGrabber:addAnchor(AnchorLeft, 'parent', AnchorLeft)
		partyListDragGrabber:addAnchor(AnchorRight, 'parent', AnchorRight)
		partyListDragGrabber:addAnchor(AnchorTop, 'parent', AnchorTop)
		partyListDragGrabber:addAnchor(AnchorBottom, 'parent', AnchorBottom)
	end

	partyListDragGrabber:setParent(root)

	return partyListDragGrabber
end

local function positionPartyListDragGhost(mousePos, sourceButton)
	if not partyListDragGhost or partyListDragGhost:isDestroyed() then
		return
	end

	local width = partyListDragGhost:getWidth()
	local height = partyListDragGhost:getHeight()
	local offsetY = sourceButton and 8 or math.floor(height / 2)

	partyListDragGhost:setPosition({
		x = mousePos.x - math.floor(width / 2),
		y = mousePos.y - offsetY
	})
	partyListDragGhost:raise()
end

finishPartyListDrag = function(mousePos, placeCopy)
	local state = partyListDragState

	if not state then
		disconnectPartyListDragMove()
		stopPartyListDragGrabber()
		destroyPartyListDragGhost()
		clearPartyListDragCursor()

		return false
	end

	partyListDragState = nil
	disconnectPartyListDragMove()
	stopPartyListDragGrabber()
	destroyPartyListDragGhost()
	clearPartyListDragCursor()

	if state and state.button then
		clearPartyListButtonHover(state.button)
	end

	if not state or not placeCopy or not isPlacementEnabled() or not state.button then
		return false
	end

	local partyWin = getPartyWindow()

	if partyWin and widgetContainsPoint(partyWin, mousePos) then
		return false
	end

	createPartyFloatingCopy(state.button, {
		x = mousePos.x - math.floor(state.button:getWidth() / 2),
		y = mousePos.y - 8
	})

	return true
end

beginPartyListDrag = function(button, mousePos)
	if not partyListDragState or partyListDragState.button ~= button or partyListDragState.dragging then
		return
	end

	local root = getRootPanel()

	if not root or not button.creature then
		return
	end

	partyListDragState.dragging = true
	partyListDragState.moved = true
	clearPartyListButtonHover(button)
	pushPartyListDragCursor()

	destroyPartyListDragGhost()
	partyListDragGhost = g_ui.createWidget('PartyFloatingVitals', root)
	partyListDragGhost:setId('partyFloatDragGhost')
	partyListDragGhost.isPartyFloatDragGhost = true
	partyListDragGhost:setOpacity(0.85)
	partyListDragGhost:setPhantom(true)
	partyListDragGhost:setEnabled(false)
	partyListDragGhost:setFocusable(false)
	partyListDragGhost:setup(button.creature, true)
	applyVitalsToButton(partyListDragGhost, button.creature)
	positionPartyListDragGhost(mousePos, button)

	local grabber = ensurePartyListDragGrabber()

	if not grabber then
		finishPartyListDrag(mousePos, false)

		return
	end

	grabber:show()
	grabber:raise()
	partyListDragGhost:raise()

	grabber.onMouseMove = function(_, pos)
		positionPartyListDragGhost(pos, button)

		return true
	end

	grabber.onMouseRelease = function(_, pos, mouseButton)
		if mouseButton == MouseLeftButton then
			finishPartyListDrag(pos, true)

			return true
		end

		if mouseButton == MouseRightButton then
			finishPartyListDrag(pos, false)

			return true
		end

		return false
	end

	grabber:grabMouse()
end

function cancelPartyListDragIfActive()
	if partyListDragState then
		finishPartyListDrag(g_window.getMousePosition(), false)
	end
end

function bindPartyButtonForFloatingPlacement(button)
	if not button or button._partyFloatBound then
		return
	end

	button._partyFloatBound = true

	local originalRelease = button.onMouseRelease
	local originalHover = button.onHoverChange

	button.onHoverChange = function(self, hovered)
		if isPlacementEnabled() then
			self.isHovered = hovered

			if self.update then
				self:update()
			end

			if hovered and self.creature then
				if CreatureList and CreatureList.clearHoverCursor then
					CreatureList.clearHoverCursor()
				end

				g_game.setHoveredCreature(self.creature)
			elseif self.creature then
				g_game.clearHoveredCreature(self.creature)
				clearPartyListButtonHover(self)
			end

			return
		end

		if originalHover then
			originalHover(self, hovered)
		end
	end

	button.onMousePress = function(self, mousePos, mouseButton)
		if mouseButton == MouseLeftButton and isPlacementEnabled() then
			partyListDragState = {
				button = self,
				startPos = {
					x = mousePos.x,
					y = mousePos.y
				},
				moved = false,
				dragging = false
			}
			connectPartyListDragMove()
		end

		return false
	end

	button.onMouseRelease = function(self, mousePosition, mouseButton)
		local drag = partyListDragState

		if drag and drag.dragging and mouseButton == MouseLeftButton then
			finishPartyListDrag(mousePosition, true)

			return true
		end

		if drag and drag.dragging then
			finishPartyListDrag(mousePosition, false)

			return true
		end

		partyListDragState = nil
		disconnectPartyListDragMove()
		clearPartyListDragCursor()

		if originalRelease then
			return originalRelease(self, mousePosition, mouseButton)
		end

		return false
	end
end

function restorePartyFloatingVitals()
	if not g_game.isOnline() or not isPlacementEnabled() then
		return
	end

	local key = getCharacterSettingsKey()
	local all = g_settings.getNode(PARTY_FLOAT_SETTINGS_NODE) or {}
	local placements = all[key]

	if not placements then
		return
	end

	if partyRestorePlacementsEvent then
		removeEvent(partyRestorePlacementsEvent)
		partyRestorePlacementsEvent = nil
	end

	partyRestorePlacementsEvent = scheduleEvent(function()
		partyRestorePlacementsEvent = nil

		for id, placement in pairs(placements) do
			local creatureId = tonumber(id)
			local creature = creatureId and findPartyCreature(creatureId)

			if creature and CreatureList.isRemotePartyMember(creature) then
				floatingLocks[creatureId] = placement.locked == true

				local mainInstance = PartyListManager and PartyListManager.instances
					and PartyListManager.instances[0]
				local source = mainInstance and mainInstance.battleButtons
					and mainInstance.battleButtons[creatureId]

				createPartyFloatingCopy(source or {
					creature = creature
				}, {
					x = tonumber(placement.x) or 100,
					y = tonumber(placement.y) or 100
				})
			end
		end
	end, 600)
end

function clearPartyFloatingVitalsRuntime(skipSave)
	if not skipSave then
		savePartyFloatingVitalsPlacements()
	end

	if partyRestorePlacementsEvent then
		removeEvent(partyRestorePlacementsEvent)
		partyRestorePlacementsEvent = nil
	end

	if partyWindowCursorMoveHandler then
		local root = getRootPanel()

		if root then
			disconnect(root, {
				onMouseMove = partyWindowCursorMoveHandler
			})
		end

		partyWindowCursorMoveHandler = nil

		local partyWin = getPartyWindow()

		if partyWin and not partyWin:isDestroyed() then
			partyWin._partyCursorCleanupBound = false
		end
	end

	for creatureId in pairs(floatingCopies) do
		removePartyFloatingCopy(creatureId)
	end

	cancelPartyListDragIfActive()
end

function setFreePartyVitalsPlacement(enabled)
	for _, copy in pairs(floatingCopies) do
		if copy and not copy:isDestroyed() then
			copy:setVisible(enabled)
		end
	end

	if enabled then
		restorePartyFloatingVitals()
	end
end

function bindPartyWindowCursorCleanup()
	local partyWin = getPartyWindow()

	if not partyWin or partyWin._partyCursorCleanupBound or partyWindowCursorMoveHandler then
		return
	end

	partyWin._partyCursorCleanupBound = true

	local wasInside = false

	partyWindowCursorMoveHandler = function(_, mousePos)
		local window = getPartyWindow()

		if not window or window:isDestroyed() or not window:isVisible() then
			wasInside = false

			return
		end

		local inside = window:containsPoint(mousePos)

		if wasInside and not inside then
			clearPartyListDragCursor()

			if CreatureList and CreatureList.clearHoverCursor then
				CreatureList.clearHoverCursor()
			end
		end

		wasInside = inside
	end

	local root = getRootPanel()

	if root then
		connect(root, {
			onMouseMove = partyWindowCursorMoveHandler
		})
	end
end

function initPartyFloatingVitals()
	g_ui.importStyle('partybutton')
	g_ui.importStyle('partyfloatingvitals')
end

function terminatePartyFloatingVitals()
	clearPartyFloatingVitalsRuntime(false)
end
