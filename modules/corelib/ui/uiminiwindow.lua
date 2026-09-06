-- @docclass
UIMiniWindow = extends(UIWindow, 'UIMiniWindow')

-- Free window placement: mini-windows can float over the game area instead of
-- only docking into side panels. Positions are stored as screen fractions per
-- character. Toggle with the "freeWindowPlacement" option (default on).
local FLOATING_SETTINGS_NODE = 'floatingMiniWindows'

local function freePlacementEnabled()
    if not modules.client_options or not modules.client_options.getOption then
        return true
    end

    local v = modules.client_options.getOption('freeWindowPlacement')
    return v == nil or v == true
end

local function floatingStoreKey()
    local char = g_game.getCharacterName()
    if char and #char > 0 then
        return char
    end
    return 'default'
end

local function floatingGameRoot()
    return modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
end

local function saveFloatingPosition(widget)
    if not widget.save then
        return
    end

    local root = floatingGameRoot()
    if not root or root:isDestroyed() then
        return
    end

    local rootSize = root:getSize()
    if rootSize.width <= 0 or rootSize.height <= 0 then
        return
    end

    local pos = widget:getPosition()
    local rootPos = root:getPosition()
    local node = g_settings.getNode(FLOATING_SETTINGS_NODE) or {}
    local key = floatingStoreKey()

    node[key] = node[key] or {}
    node[key][widget:getId()] = {
        fx = (pos.x - rootPos.x) / rootSize.width,
        fy = (pos.y - rootPos.y) / rootSize.height
    }

    g_settings.setNode(FLOATING_SETTINGS_NODE, node)
end

local function eraseFloatingPosition(widget)
    local node = g_settings.getNode(FLOATING_SETTINGS_NODE)
    if not node then
        return
    end

    local key = floatingStoreKey()
    if node[key] then
        node[key][widget:getId()] = nil
        g_settings.setNode(FLOATING_SETTINGS_NODE, node)
    end
end

local function readFloatingPosition(widget)
    local node = g_settings.getNode(FLOATING_SETTINGS_NODE)
    local key = floatingStoreKey()
    if node and node[key] then
        return node[key][widget:getId()]
    end
    return nil
end

function UIMiniWindow.raiseAllFloating()
    local root = floatingGameRoot()
    if not root or root:isDestroyed() then
        return
    end

    for _, child in ipairs(root:getChildren()) do
        if child.floating then
            child:raise()
        end
    end
end

function UIMiniWindow:dockToSidebar()
    removeEvent(self._floatRestoreEvent)
    self._floatRestoreEvent = nil
    self.floating = nil

    local parent = self:getParent()
    if parent and parent:getClassName() == 'UIMiniWindowContainer' then
        return
    end

    local panel
    if modules.game_interface and modules.game_interface.findContentPanelAvailable then
        panel = modules.game_interface.findContentPanelAvailable(self, self:getMinimumHeight())
    end
    if (not panel or panel:isDestroyed()) and modules.game_interface and modules.game_interface.getRightPanel then
        panel = modules.game_interface.getRightPanel()
    end
    if not panel or panel:isDestroyed() then
        return
    end

    if parent then
        parent:removeChild(self)
    end
    panel:addChild(self)
    self:saveParent(panel)
    self:fitOnParent()
end

function UIMiniWindow.dockAllFloating()
    local root = floatingGameRoot()
    if not root or root:isDestroyed() then
        return
    end

    local toDock = {}
    for _, child in ipairs(root:getChildren()) do
        if child and not child:isDestroyed() and child:getClassName() == 'UIMiniWindow' then
            table.insert(toDock, child)
        end
    end

    for _, window in ipairs(toDock) do
        window:dockToSidebar()
    end
end

local OPEN_HIGHLIGHT_COLOR = '#FFFFFF'
local OPEN_HIGHLIGHT_WIDTH = 2
local OPEN_HIGHLIGHT_HOLD_TIME = 90
local OPEN_HIGHLIGHT_FADE_TIME = 420
local OPEN_HIGHLIGHT_DEBOUNCE_TIME = 120
local OPEN_HIGHLIGHT_LOGIN_SUPPRESSION_TIME = 2000
local openHighlightEnabled = g_game.isOnline()
local openHighlightEnableEvent

connect(g_game, {
    onGameStart = function()
        openHighlightEnabled = false
        removeEvent(openHighlightEnableEvent)
        openHighlightEnableEvent = scheduleEvent(function()
            openHighlightEnableEvent = nil
            openHighlightEnabled = true
        end, OPEN_HIGHLIGHT_LOGIN_SUPPRESSION_TIME)
    end,
    onGameEnd = function()
        removeEvent(openHighlightEnableEvent)
        openHighlightEnableEvent = nil
        openHighlightEnabled = false
    end
})

local function clearOpenHighlight(miniwindow)
    removeEvent(miniwindow._openHighlightFadeEvent)
    removeEvent(miniwindow._openHighlightDestroyEvent)
    miniwindow._openHighlightFadeEvent = nil
    miniwindow._openHighlightDestroyEvent = nil

    local overlay = miniwindow._openHighlightOverlay
    if overlay then
        removeEvent(overlay.fadeEvent)
        overlay.fadeEvent = nil
        if not overlay:isDestroyed() then
            overlay:destroy()
        end
        miniwindow._openHighlightOverlay = nil
    end
end

local function playOpenHighlight(miniwindow)
    if not openHighlightEnabled or not g_game.isOnline() or miniwindow:isDestroyed() or not miniwindow:isVisible() then
        return
    end

    local now = g_clock.millis()
    local currentOverlay = miniwindow._openHighlightOverlay
    if currentOverlay and not currentOverlay:isDestroyed() and miniwindow._openHighlightLastStart
        and now - miniwindow._openHighlightLastStart < OPEN_HIGHLIGHT_DEBOUNCE_TIME then
        return
    end

    clearOpenHighlight(miniwindow)
    miniwindow._openHighlightLastStart = now

    local overlay = g_ui.createWidget('UIWidget', miniwindow)
    overlay:setId('miniwindowOpenHighlight')
    overlay._miniwindowOpenHighlight = true
    overlay:setPhantom(true)
    overlay:setFocusable(false)
    overlay:setBorderColor(OPEN_HIGHLIGHT_COLOR)
    overlay:setBorderWidth(OPEN_HIGHLIGHT_WIDTH)
    overlay:setOpacity(1)
    overlay:fill('parent')
    overlay:show()
    overlay:raise()

    miniwindow._openHighlightOverlay = overlay
    miniwindow._openHighlightFadeEvent = scheduleEvent(function()
        if miniwindow:isDestroyed() or overlay:isDestroyed() then
            return
        end
        miniwindow._openHighlightFadeEvent = nil
        g_effects.fadeOut(overlay, OPEN_HIGHLIGHT_FADE_TIME)
    end, OPEN_HIGHLIGHT_HOLD_TIME)

    miniwindow._openHighlightDestroyEvent = scheduleEvent(function()
        if miniwindow:isDestroyed() then
            return
        end
        miniwindow._openHighlightDestroyEvent = nil
        if miniwindow._openHighlightOverlay == overlay then
            removeEvent(overlay.fadeEvent)
            overlay.fadeEvent = nil
            if not overlay:isDestroyed() then
                overlay:destroy()
            end
            miniwindow._openHighlightOverlay = nil
        end
    end, OPEN_HIGHLIGHT_HOLD_TIME + OPEN_HIGHLIGHT_FADE_TIME + 60)
end

function UIMiniWindow.create()
    local miniwindow = UIMiniWindow.internalCreate()
    miniwindow.UIMiniWindowContainer = true
    return miniwindow
end

function UIMiniWindow:open(dontSave)
    self:setVisible(true)
    if not dontSave then
        self:setSettings({
            closed = false
        })
    end
    if not dontSave and not self._restoringOnStart then
        playOpenHighlight(self)
    end
    signalcall(self.onOpen, self)
end

function UIMiniWindow:close(dontSave)
    if not self:isExplicitlyVisible() then
        return
    end

    clearOpenHighlight(self)

    if self.floating then
        self.floating = nil
        eraseFloatingPosition(self)
    end

    self:setVisible(false)

    if not dontSave then
        self:setSettings({
            closed = true
        })
    end

    signalcall(self.onClose, self)
end

function UIMiniWindow:setFloating()
    local root = floatingGameRoot()

    if root and not root:isDestroyed() and self:getParent() ~= root then
        local p = self:getParent()
        if p then
            p:removeChild(self)
        end
        root:addChild(self)
    end

    self.floating = true
    self._fromSidebar = false
    self.oldParentDrag = nil

    self:raise()
    saveFloatingPosition(self)
end

function UIMiniWindow:scheduleFloatingRestore()
    if not freePlacementEnabled() then
        return
    end

    local stored = readFloatingPosition(self)
    if not stored then
        return
    end

    removeEvent(self._floatRestoreEvent)

    self._floatRestoreEvent = scheduleEvent(function()
        self._floatRestoreEvent = nil
        if not freePlacementEnabled() then
            return
        end

        local root = floatingGameRoot()
        if not root or root:isDestroyed() then
            return
        end

        local rootSize = root:getSize()
        local rootPos = root:getPosition()
        if rootSize.width <= 0 or rootSize.height <= 0 then
            return
        end

        self:setFloating()
        self:setPosition({
            x = math.floor(rootPos.x + (stored.fx or 0) * rootSize.width + 0.5),
            y = math.floor(rootPos.y + (stored.fy or 0) * rootSize.height + 0.5)
        })
        self:bindRectToParent()
    end, 650)
end

function UIMiniWindow:minimize(dontSave)
    self:setOn(true)
    self:getChildById('contentsPanel'):hide()
    self:getChildById('miniwindowScrollBar'):hide()
    self:getChildById('bottomResizeBorder'):hide()
    self:getChildById('minimizeButton'):setOn(true)
    self.maximizedHeight = self:getHeight()
    self:setHeight(self.minimizedHeight)

    -- Hide miniborder when minimizing
    local miniborder = self:recursiveGetChildById('miniborder')
    if miniborder then
        miniborder:setVisible(false)
    end

    if not dontSave then
        self:setSettings({
            minimized = true
        })
    end

    signalcall(self.onMinimize, self)
end

function UIMiniWindow:maximize(dontSave)
    self:setOn(false)
    self:getChildById('contentsPanel'):show()
    self:getChildById('miniwindowScrollBar'):show()
    self:getChildById('bottomResizeBorder'):show()
    self:getChildById('minimizeButton'):setOn(false)
    self:setHeight(self:getSettings('height') or self.maximizedHeight)

    -- Show miniborder when maximizing
    local miniborder = self:recursiveGetChildById('miniborder')
    if miniborder then
        miniborder:setVisible(true)
    end

    if not dontSave then
        self:setSettings({
            minimized = false
        })
    end

    local parent = self:getParent()
    if parent and parent:getClassName() == 'UIMiniWindowContainer' then
        parent:fitAll(self)
    end

    signalcall(self.onMaximize, self)
end

function UIMiniWindow:setup()
    self:getChildById('closeButton').onClick = function()
        self:close()
    end

    self:getChildById('minimizeButton').onClick = function()
        if self:isOn() then
            self:maximize()
        else
            self:minimize()
        end
    end

    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton.onClick = function()
            if self:isLocked() then
                self:unlock()
            else
                self:lock()
            end
        end
    end

    self:getChildById('miniwindowTopBar').onDoubleClick = function()
        if self:isOn() then
            self:maximize()
        else
            self:minimize()
        end
    end
end

function UIMiniWindow:setupOnStart()
    self._restoringOnStart = true

    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        self._restoringOnStart = nil
        return
    end

    local oldParent = self:getParent()
    local newParentSet = false
    local settings = g_settings.getNode('CharMiniWindows')

    if not settings then
        settings = {
            [char] = {}
        }
    elseif not settings[char] then
        -- if there are no settings for this character, we'll copy the settings from
        -- another one, so we'll have something better than all the windows randomly positioned
        for k, v in pairs(settings) do
            settings[char] = v
            g_settings.setNode('CharMiniWindows', settings)
            break
        end
    end

    local selfSettings = settings[char][self:getId()]
    if selfSettings then
        if selfSettings.parentId then
            local parent = rootWidget:recursiveGetChildById(selfSettings.parentId)
            -- Horizontal minimap slots can still be hidden while the saved
            -- sidebar columns are being restored. They become visible a moment
            -- later, so do not reject the persisted parent during that window.
            local parentAvailable = parent and
                (parent:isVisible() or (parent.isHorizontalPanel and parent:isOn()))
            if parentAvailable then
                local parentIsSidebar = parent:getClassName() == 'UIMiniWindowContainer'
                if parentIsSidebar and selfSettings.index and parent:isOn() then
                    self.miniIndex = selfSettings.index
                    parent:scheduleInsert(self, selfSettings.index)
                    newParentSet = true
                elseif selfSettings.position and freePlacementEnabled() then
                    self:setParent(parent, true)
                    self:setPosition(topoint(selfSettings.position))
                    newParentSet = true
                end
            end
        end

        if selfSettings.minimized then
            self:minimize(true)
        elseif selfSettings.height then
            if self:isResizeable() then
                self:setHeight(selfSettings.height)
            else
                self:eraseSettings({
                    height = true
                })
            end
        end

        if selfSettings.closed then
            self:close(true)
        else
            self:open(true)
        end

        if selfSettings.locked then
            self:lock(true)
        end
    else
        if self:getId() == "battleWindow" then
            self:open(true)
        end
    end

    local newParent = self:getParent()

    if not oldParent and not newParentSet then
        oldParent = modules.game_interface.getRightPanel()
        self:setParent(oldParent)
    end

    if not freePlacementEnabled() then
        local parent = self:getParent()
        if self.floating or (parent and parent:getClassName() ~= 'UIMiniWindowContainer') then
            self:dockToSidebar()
        end
    end

    self.miniLoaded = true

    if self.save then
        if oldParent and oldParent:getClassName() == 'UIMiniWindowContainer' then
            addEvent(function()
                oldParent:order()
            end)
        end
        if newParent and newParent:getClassName() == 'UIMiniWindowContainer' and newParent ~= oldParent then
            addEvent(function()
                newParent:order()
            end)
        end
    end

    self:fitOnParent()
    if self:getId() == "botWindow" then
        local parent = self:getParent()
        local parentId = parent:getId()

        if parentId == "gameLeftPanel" or
            parentId == "gameLeftExtraPanel" or
            parentId == "gameRightExtraPanel" then
            if parent:isVisible() then
                parent:setWidth(190)
                -- The horizontal top bar is sized from this column, so it must
                -- be recomputed or it keeps the wider default and juts out.
                if modules.game_interface and modules.game_interface.scheduleSidebarLayoutUpdate then
                    modules.game_interface.scheduleSidebarLayoutUpdate()
                end
            end
        end
    end

    self:scheduleFloatingRestore()
    self._restoringOnStart = nil
end

function UIMiniWindow:onVisibilityChange(visible)
    self:fitOnParent()
end

local dropPlaceholder = nil

local function stopPlaceholderPulse(widget)
    if widget and widget._pulseEvent then
        removeEvent(widget._pulseEvent)
        widget._pulseEvent = nil
    end
end

local function startPlaceholderPulse(widget)
    if not widget or widget._pulseEvent then
        return
    end

    local startTime = g_clock.millis()
    local PULSE_PERIOD = 900 -- 900ms per full breathing cycle
    local MIN_OPACITY = 0.40
    local MAX_OPACITY = 0.95

    widget._pulseEvent = cycleEvent(function()
        if not widget or widget:isDestroyed() then
            stopPlaceholderPulse(widget)
            return
        end
        local elapsed = (g_clock.millis() - startTime) % PULSE_PERIOD
        local phase = (elapsed / PULSE_PERIOD) * 2 * math.pi
        local factor = (1 - math.cos(phase)) / 2
        local opacity = MIN_OPACITY + factor * (MAX_OPACITY - MIN_OPACITY)
        widget:setOpacity(opacity)
    end, 25)
end

function UIMiniWindow.getDropPlaceholder()
    return dropPlaceholder
end

function UIMiniWindow.destroyDropPlaceholder()
    if dropPlaceholder then
        stopPlaceholderPulse(dropPlaceholder)
        local p = dropPlaceholder:getParent()
        if p and not p:isDestroyed() then
            p:removeChild(dropPlaceholder)
            if type(p.scheduleSidebarFreeSpaceRefresh) == 'function' then
                p:scheduleSidebarFreeSpaceRefresh()
            end
        end
        if not dropPlaceholder:isDestroyed() then
            dropPlaceholder:destroy()
        end
        dropPlaceholder = nil
    end
end

local function ensureDropPlaceholder(height)
    if dropPlaceholder and not dropPlaceholder:isDestroyed() then
        if height and dropPlaceholder:getHeight() ~= height then
            dropPlaceholder:setHeight(height)
        end
        startPlaceholderPulse(dropPlaceholder)
        return dropPlaceholder
    end

    local ok, widget = pcall(function()
        return g_ui.createWidget('MiniWindowDropPlaceholder')
    end)
    if not ok or not widget then
        widget = g_ui.createWidget('UIWidget')
        widget:setId('miniwindowDropPlaceholder')
        widget:setImageSource('/images/ui/2pixel_up_frame_borderimage_dark_reversed')
        widget:setImageBorder(2)
        widget:setImageRepeated(true)
        widget:setOpacity(0.88)
        widget:setPhantom(true)
        widget:setFocusable(false)
    end

    widget._sidebarPlaceholderWidget = true
    widget:setPhantom(true)
    widget:setFocusable(false)
    if height then
        widget:setHeight(height)
    end
    dropPlaceholder = widget
    startPlaceholderPulse(dropPlaceholder)
    return dropPlaceholder
end

local function isSidebarDropTarget(widget)
    while widget and not widget:isDestroyed() do
        if widget:getClassName() == 'UIMiniWindowContainer' then
            return true
        end
        widget = widget:getParent()
    end
    return false
end

local function canDockInContainer(miniwindow, container)
    if not container or container:isDestroyed() or not container:isVisible() then
        return false
    end
    if container:getClassName() ~= 'UIMiniWindowContainer' then
        return false
    end
    if container.isHorizontalPanel and not miniwindow.allowHorizontalDrop then
        return false
    end
    if container.onlyPhantomDrop and not miniwindow.moveOnlyToMain then
        return false
    end
    if miniwindow.moveOnlyToMain and not container.onlyPhantomDrop
        and not (miniwindow.allowHorizontalDrop and container.isHorizontalPanel) then
        return false
    end
    return true
end

local function findHoveredContainer(miniwindow, mousePos)
    local children = rootWidget:recursiveGetChildrenByMarginPos(mousePos)
    for i = 1, #children do
        local curr = children[i]
        while curr and not curr:isDestroyed() do
            if canDockInContainer(miniwindow, curr) then
                return curr
            end
            curr = curr:getParent()
        end
    end
    return nil
end

local function getDockableChildren(container, draggedWidget)
    local dockables = {}
    local children = container:getChildren()
    for i = 1, #children do
        local child = children[i]
        if child:isVisible() and not child._sidebarFreeSpaceWidget and not child._sidebarPlaceholderWidget and child ~= draggedWidget then
            table.insert(dockables, child)
        end
    end
    return dockables
end

local function determineTargetSlot(container, mousePos, dockables, placeholder)
    if placeholder and placeholder:getParent() == container and placeholder._currentSlot then
        if placeholder:containsPoint(mousePos) then
            return placeholder._currentSlot
        end
    end

    local count = #dockables
    if count == 0 then
        return 1
    end

    for i, child in ipairs(dockables) do
        if container.isHorizontalPanel then
            local midX = child:getX() + child:getWidth() / 2
            if mousePos.x < midX then
                return i
            end
        else
            local midY = child:getY() + child:getHeight() / 2
            if mousePos.y < midY then
                return i
            end
        end
    end

    return count + 1
end

local function placePlaceholderAtSlot(container, placeholder, slot, dockables)
    local count = #dockables
    if count == 0 then
        if placeholder:getParent() ~= container then
            container:insertChild(1, placeholder)
        else
            container:moveChildToIndex(placeholder, 1)
        end
        placeholder._currentSlot = 1
        return
    end

    if placeholder._currentSlot == slot and placeholder:getParent() == container then
        return
    end

    local targetIndex
    if placeholder:getParent() ~= container then
        if slot <= count then
            targetIndex = container:getChildIndex(dockables[slot])
        else
            targetIndex = container:getChildIndex(dockables[count]) + 1
        end
        container:insertChild(targetIndex, placeholder)
    else
        local cur = placeholder._currentSlot or 1
        if slot < cur then
            targetIndex = container:getChildIndex(dockables[slot])
        elseif slot > cur then
            if slot <= count then
                targetIndex = container:getChildIndex(dockables[slot]) - 1
            else
                targetIndex = container:getChildIndex(dockables[count])
            end
        else
            return
        end
        targetIndex = math.max(1, math.min(targetIndex, container:getChildCount()))
        container:moveChildToIndex(placeholder, targetIndex)
    end
    placeholder._currentSlot = slot
end

local function resetContainerDragMargins(container)
    if not container or container:isDestroyed() then
        return
    end

    for _, child in ipairs(container:getChildren()) do
        if child and not child:isDestroyed() and not child._sidebarFreeSpaceWidget and not child._sidebarPlaceholderWidget then
            g_effects.cancelValue(child)
            if child:getMarginTop() ~= 0 then
                child:setMarginTop(0)
            end
            if child:getMarginBottom() ~= 0 then
                child:setMarginBottom(0)
            end
        end
    end
end

function UIMiniWindow:onDragEnter(mousePos)
    local parent = self:getParent()
    if not parent then
        return false
    end

    g_effects.cancelMove(self)
    self.smoothDropActive = nil
    self._fromSidebar = false
    UIMiniWindow.destroyDropPlaceholder()

    if self.floating then
        self._floatDragStart = self:getPosition()
    end

    if parent:getClassName() == 'UIMiniWindowContainer' then
        self._fromSidebar = true
        self.oldParentDrag = parent
        self.oldParentDragIndex = parent:getChildIndex(self)

        local containerParent = parent:getParent()
        parent:removeChild(self)
        if containerParent then
            containerParent:addChild(self)
        else
            rootWidget:addChild(self)
        end
        parent:saveChildren()

        if parent.isHorizontalPanel and type(parent.redistributeChildrenWidths) == 'function' then
            parent:redistributeChildrenWidths()
        else
            local placeholder = ensureDropPlaceholder(self:getHeight())
            local targetIndex = math.min(self.oldParentDragIndex, parent:getChildCount() + 1)
            parent:insertChild(targetIndex, placeholder)
            local dockables = getDockableChildren(parent, self)
            local slot = 1
            for i, d in ipairs(dockables) do
                if parent:getChildIndex(d) > targetIndex then
                    slot = i
                    break
                end
                slot = i + 1
            end
            placeholder._currentSlot = slot
            if type(parent.scheduleSidebarFreeSpaceRefresh) == 'function' then
                parent:scheduleSidebarFreeSpaceRefresh()
            end
        end
    end

    local oldPos = self:getPosition()
    self.movingReference = {
        x = mousePos.x - oldPos.x,
        y = mousePos.y - oldPos.y
    }
    self:setPosition(oldPos)
    self.free = true
    self._origOpacity = self:getOpacity()
    self:setOpacity(0.75)
    return true
end

function UIMiniWindow:onDragLeave(droppedWidget, mousePos)
    if not self.smoothDropActive then
        UIMiniWindow.destroyDropPlaceholder()
    end

    local dropContainer = droppedWidget
    while dropContainer and not dropContainer:isDestroyed() do
        if dropContainer:getClassName() == 'UIMiniWindowContainer' then
            resetContainerDragMargins(dropContainer)
            break
        end
        dropContainer = dropContainer:getParent()
    end
    if self.oldParentDrag and not self.oldParentDrag:isDestroyed() then
        resetContainerDragMargins(self.oldParentDrag)
    end

    local function bounceBackToOrigin()
        if not self.oldParentDrag or self.oldParentDrag:isDestroyed() then
            return false
        end

        local virtualParent = self:getParent()
        if virtualParent then
            virtualParent:removeChild(self)
        end

        local insertIdx = math.min(self.oldParentDragIndex or 1, self.oldParentDrag:getChildCount() + 1)
        self.oldParentDrag:insertChild(insertIdx, self)
        if type(self.oldParentDrag.scheduleSidebarFreeSpaceRefresh) == 'function' then
            self.oldParentDrag:scheduleSidebarFreeSpaceRefresh()
        end
        return true
    end

    local needsBounce = false
    local floatReleaseAllowed = freePlacementEnabled() and not droppedWidget and not self.locked

    if (self.moveOnlyToMain or droppedWidget and droppedWidget.onlyPhantomDrop) and not floatReleaseAllowed then
        local widgetAllowsHorizontal = self.allowHorizontalDrop and droppedWidget and droppedWidget.isHorizontalPanel
        if not widgetAllowsHorizontal and (not droppedWidget or
            (self.moveOnlyToMain and not droppedWidget.onlyPhantomDrop) or
            (not self.moveOnlyToMain and droppedWidget.onlyPhantomDrop)) then
            needsBounce = true
        end
    end

    -- During drag the window is reparented to the game root, so getParent() is
    -- not the sidebar. Use the drop target (and onDrop's smooth-drop flag).
    local landedParent = self:getParent()
    local landedOnSidebar = isSidebarDropTarget(droppedWidget)
        or (landedParent and landedParent:getClassName() == 'UIMiniWindowContainer')

    if self.smoothDropActive then
        landedOnSidebar = true
        needsBounce = false
    end

    local wantsFloat = self._fromSidebar and not landedOnSidebar and not needsBounce and
        freePlacementEnabled() and not self.locked and not (droppedWidget and droppedWidget.onlyPhantomDrop)

    local stayFloating = self.floating and not landedOnSidebar and not needsBounce and freePlacementEnabled()

    -- Classic dock-only: leaving a sidebar without landing on another must bounce.
    if not needsBounce and not wantsFloat and not stayFloating and self._fromSidebar and not landedOnSidebar then
        needsBounce = true
    end

    if wantsFloat or stayFloating then
        self:setFloating()
    elseif needsBounce then
        bounceBackToOrigin()
    elseif landedOnSidebar and self.floating then
        self.floating = nil
        eraseFloatingPosition(self)
    end

    self._fromSidebar = false

    if not self.smoothDropActive then
        self:setOpacity(self._origOpacity or 1.0)
        self._origOpacity = nil
        self:saveParent(self:getParent())
    end

    return true
end

function UIMiniWindow:onDragMove(mousePos, mouseMoved)
    local targetContainer = findHoveredContainer(self, mousePos)
    if targetContainer then
        local placeholder = ensureDropPlaceholder(self:getHeight())
        if targetContainer.isHorizontalPanel then
            local availableHeight = targetContainer:getHeight() - targetContainer:getPaddingTop() - targetContainer:getPaddingBottom()
            placeholder:setHeight(availableHeight)
            placeholder:setWidth(self:getWidth())
        else
            placeholder:setHeight(self:getHeight())
        end

        local prevParent = placeholder:getParent()
        if prevParent and prevParent ~= targetContainer then
            prevParent:removeChild(placeholder)
            placeholder._currentSlot = nil
            if type(prevParent.scheduleSidebarFreeSpaceRefresh) == 'function' then
                prevParent:scheduleSidebarFreeSpaceRefresh()
            end
        end

        local dockables = getDockableChildren(targetContainer, self)
        local slot = determineTargetSlot(targetContainer, mousePos, dockables, placeholder)
        placePlaceholderAtSlot(targetContainer, placeholder, slot, dockables)

        if type(targetContainer.scheduleSidebarFreeSpaceRefresh) == 'function' then
            targetContainer:scheduleSidebarFreeSpaceRefresh()
        end
    else
        if dropPlaceholder and dropPlaceholder:getParent() then
            local prevParent = dropPlaceholder:getParent()
            prevParent:removeChild(dropPlaceholder)
            dropPlaceholder._currentSlot = nil
            if type(prevParent.scheduleSidebarFreeSpaceRefresh) == 'function' then
                prevParent:scheduleSidebarFreeSpaceRefresh()
            end
        end
    end

    local moved = UIWindow.onDragMove(self, mousePos, mouseMoved)

    -- With free placement off, keep moveOnlyToMain windows X-locked to their dock panel.
    -- Windows that may also dock into the horizontal top panels are exempt: those panels
    -- sit outside their origin column, so the lock would pin them in place.
    if self.moveOnlyToMain and not self.allowHorizontalDrop and not freePlacementEnabled()
        and self.oldParentDrag and not self.oldParentDrag:isDestroyed() then
        local cRect = self.oldParentDrag:getPaddingRect()
        local wSize = self:getSize()
        local lockedX = cRect.x
        local minY = cRect.y
        local maxY = cRect.y + math.max(0, cRect.height - wSize.height)
        local clampedY = math.max(minY, math.min(self:getY(), maxY))

        if lockedX ~= self:getX() or clampedY ~= self:getY() then
            self:setPosition({
                x = lockedX,
                y = clampedY
            })
        end
    end

    return moved
end

function UIMiniWindow:onMousePress()
    local parent = self:getParent()
    if not parent then
        return false
    end
    if parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:raise()
        return true
    end
end

function UIMiniWindow:onFocusChange(focused)
    if not focused then
        return
    end
    local parent = self:getParent()
    if parent and parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:raise()
    end
end

function UIMiniWindow:onHeightChange(height)
    if not self:isOn() then
        self:setSettings({
            height = height
        })
    end
    self:fitOnParent()
end

function UIMiniWindow:getSettings(name)
    if not self.save then
        return nil
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return nil
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if settings then
        local selfSettings = settings[char][self:getId()]
        if selfSettings then
            return selfSettings[name]
        end
    end

    return nil
end

function UIMiniWindow:setSettings(data)
    if not self.save then
        return
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings then
        settings = {}
    end
    if not settings[char] then
        settings[char] = {}
    end

    local id = self:getId()
    if not settings[char][id] then
        settings[char][id] = {}
    end

    for key, value in pairs(data) do
        settings[char][id][key] = value
    end

    g_settings.setNode('CharMiniWindows', settings)
end

function UIMiniWindow:eraseSettings(data)
    if not self.save then
        return
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings then
        settings = {}
    end
    if not settings[char] then
        settings[char] = {}
    end

    local id = self:getId()
    if not settings[char][id] then
        settings[char][id] = {}
    end

    for key, value in pairs(data) do
        settings[char][id][key] = nil
    end

    g_settings.setNode('CharMiniWindows', settings)
end

function UIMiniWindow:saveParent(parent)
    local parent = self:getParent()
    if parent then
        if parent:getClassName() == 'UIMiniWindowContainer' then
            parent:saveChildren()
        else
            self:saveParentPosition(parent:getId(), self:getPosition())
        end
        if self._lastSavedContainer ~= parent then
            self._lastSavedContainer = parent
            signalcall(self.onContainerChanged, self, parent)
        end
    end
end

function UIMiniWindow:saveParentPosition(parentId, position)
    local selfSettings = {}
    selfSettings.parentId = parentId
    selfSettings.position = pointtostring(position)
    self:setSettings(selfSettings)
end

function UIMiniWindow:saveParentIndex(parentId, index)
    local selfSettings = {}
    selfSettings.parentId = parentId
    selfSettings.index = index
    self:setSettings(selfSettings)
    self.miniIndex = index
end

function UIMiniWindow:disableResize()
    self:getChildById('bottomResizeBorder'):disable()
end

function UIMiniWindow:enableResize()
    self:getChildById('bottomResizeBorder'):enable()
end

function UIMiniWindow:fitOnParent()
    local parent = self:getParent()
    if self:isVisible() and parent and parent:getClassName() == 'UIMiniWindowContainer' then
        parent:fitAll(self)
    end
end

function UIMiniWindow:setParent(parent, dontsave)
    UIWidget.setParent(self, parent)
    if not dontsave then
        self:saveParent(parent)
    end
    self:fitOnParent()
end

function UIMiniWindow:setHeight(height)
    UIWidget.setHeight(self, height)
    signalcall(self.onHeightChange, self, height)
end

function UIMiniWindow:setContentHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setParentSize(minHeight + height)
end

function UIMiniWindow:setContentMinimumHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setMinimum(minHeight + height)
end

function UIMiniWindow:setContentMaximumHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setMaximum(minHeight + height)
end

function UIMiniWindow:getMinimumHeight()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    return resizeBorder:getMinimum()
end

function UIMiniWindow:getMaximumHeight()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    return resizeBorder:getMaximum()
end

function UIMiniWindow:modifyMaximumHeight(height)
    local resizeBorder = self:getChildById('bottomResizeBorder')
    local newHeight = resizeBorder:getMaximum() + height
    local curHeight = self:getHeight()
    resizeBorder:setMaximum(newHeight)
    if newHeight < curHeight or newHeight - height == curHeight then
        self:setHeight(newHeight)
    end
end

function UIMiniWindow:isResizeable()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    if not resizeBorder then
        return false
    end
    return resizeBorder:isExplicitlyVisible() and resizeBorder:isEnabled()
end

function UIMiniWindow:isLocked()
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        return lockButton:isOn()
    end
    return self.locked == true
end

function UIMiniWindow:lock(dontSave)
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton:setOn(true)
    end
    self.locked = true
    self:setDraggable(false)
    if not dontSave then
        self:setSettings({
            locked = true
        })
    end

    signalcall(self.onLockChange, self)
end

function UIMiniWindow:unlock(dontSave)
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton:setOn(false)
    end
    self.locked = false
    self:setDraggable(true)
    if not dontSave then
        self:setSettings({
            locked = false
        })
    end
    signalcall(self.onLockChange, self)
end
