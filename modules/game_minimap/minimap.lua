local iconTopMenu = nil
-- Exported for OTCv8/vBot cavebot (modules.game_minimap.minimapWidget)
minimapWidget = nil
local otmm = true
local oldPos = nil
local fullscreenWidget
local virtualFloor = 7
local currentDayTime = {
    h = 12,
    m = 0
}

local MIN_VIRTUAL_FLOOR = 0
local MAX_VIRTUAL_FLOOR = 15
-- The indicator strip packs the 16 floors into 4 pixel steps.
local FLOOR_MARK_STEP = 4

local ROSE_DIRECTIONS = {
    ['north'] = { 0, 1 },
    ['north-east'] = { -1, 1 },
    ['east'] = { -1, 0 },
    ['south-east'] = { -1, -1 },
    ['south'] = { 0, -1 },
    ['south-west'] = { 1, -1 },
    ['west'] = { 1, 0 },
    ['north-west'] = { 1, 1 }
}

-- Hold behaviour for the compass: one tile on press, then a repeat that speeds
-- up the longer the button stays down.
local ROSE_HOLD_DELAY = 300
local ROSE_REPEAT_INTERVAL = 40
local ROSE_FULL_SPEED_MS = 900
local ROSE_MAX_STEPS = 6

local function refreshVirtualFloors()
    local ui = mapController and mapController.ui
    if not ui or ui:isDestroyed() or not ui.layersPanel or ui.layersPanel:isDestroyed() then
        return
    end
    if ui.layersPanel.layersMark then
        ui.layersPanel.layersMark:setMarginTop(((virtualFloor + 1) * 4) - 3)
    end
    if ui.layersPanel.automapLayers then
        ui.layersPanel.automapLayers:setImageClip((virtualFloor * 14) .. ' 0 14 67')
    end
end

local function onPositionChange()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local pos = player:getPosition()
    if not pos then
        return
    end

    local ui = mapController.ui
    if not ui or ui:isDestroyed() or not ui.minimapBorder then
        return
    end

    local minimapWidget = ui.minimapBorder.minimap
    if not (minimapWidget) or minimapWidget:isDragging() then
        return
    end

    if not minimapWidget.fullMapView then
        minimapWidget:setCameraPosition(pos)
    end

    minimapWidget:setCrossPosition(pos)
    virtualFloor = pos.z
    refreshVirtualFloors()
end

mapController = Controller:new()
mapController:setUI('minimap', modules.game_interface.getMainRightPanel())

local DEFAULT_LAYOUT_WIDGETS = {
    minimapBorder = true,
    layersPanel = true,
    fullMap = true,
    zoomIn = true,
    zoomOut = true,
    rosePanel = true
}

local function getLayoutRoot(ui, horizontal)
    if not ui or ui:isDestroyed() then
        return nil
    end
    return ui:getChildById(horizontal and 'layoutHorizontal' or 'layoutDefault')
end

local function getLayoutWidget(layoutRoot, widgetId)
    if not layoutRoot or layoutRoot:isDestroyed() then
        return nil
    end
    return layoutRoot:getChildById(widgetId)
end

local function prepareDefaultLayout(ui)
    local defaultRoot = getLayoutRoot(ui, false)
    if not defaultRoot then
        return
    end

    local children = ui:getChildren()
    for i = #children, 1, -1 do
        local child = children[i]
        if child and not child:isDestroyed() and DEFAULT_LAYOUT_WIDGETS[child:getId()] then
            child:setParent(defaultRoot)
        end
    end
end

local function setPhantomBackgroundVisible(ui, visible)
    for _, child in ipairs(ui:getChildren()) do
        if child and not child:isDestroyed() and child:getId() ~= 'layoutDefault'
            and child:getId() ~= 'layoutHorizontal' then
            local source = child.getImageSource and child:getImageSource() or ''
            if source and tostring(source):find('/images/ui/background', 1, true) then
                child:setVisible(visible)
            end
        end
    end
end

local function findMinimapWidget(ui)
    local defaultBorder = getLayoutWidget(getLayoutRoot(ui, false), 'minimapBorder')
    local mini = defaultBorder and defaultBorder:getChildById('minimap')
    if mini and not mini:isDestroyed() then
        return mini
    end

    local horizontalBorder = getLayoutWidget(getLayoutRoot(ui, true), 'minimapBorder')
    return horizontalBorder and horizontalBorder:getChildById('minimap')
end

local function syncMinimapLayoutAliases(layoutRoot)
    local ui = mapController.ui
    if not ui or ui:isDestroyed() or not layoutRoot or layoutRoot:isDestroyed() then
        return
    end
    ui.minimapBorder = getLayoutWidget(layoutRoot, 'minimapBorder')
    ui.layersPanel = getLayoutWidget(layoutRoot, 'layersPanel')
    ui.rosePanel = getLayoutWidget(layoutRoot, 'rosePanel')
end

local function resolveHorizontalSide(container)
    local current = container
    while current do
        local id = current.getId and current:getId() or nil
        if id == 'gameLeftTopPanel' then
            return 'left'
        elseif id == 'gameRightTopPanel' then
            return 'right'
        end
        current = current.getParent and current:getParent() or nil
    end
    return 'right'
end

local function applyHorizontalControlsLayout(horizontalRoot, mirror)
    local layers = getLayoutWidget(horizontalRoot, 'layersPanel')
    local fullMap = getLayoutWidget(horizontalRoot, 'fullMap')
    local zoomInButton = getLayoutWidget(horizontalRoot, 'zoomIn')
    local zoomOutButton = getLayoutWidget(horizontalRoot, 'zoomOut')
    if not layers or not fullMap or not zoomInButton or not zoomOutButton then
        return
    end

    layers:breakAnchors()
    layers:addAnchor(AnchorBottom, 'minimapBorder', AnchorBottom)
    layers:setMarginBottom(3)
    fullMap:breakAnchors()
    fullMap:addAnchor(AnchorBottom, 'layersPanel', AnchorBottom)
    zoomInButton:breakAnchors()
    zoomInButton:addAnchor(AnchorBottom, 'fullMap', AnchorTop)
    zoomInButton:setMarginBottom(2)
    zoomOutButton:breakAnchors()
    zoomOutButton:addAnchor(AnchorBottom, 'zoomIn', AnchorTop)
    zoomOutButton:setMarginBottom(2)

    if mirror then
        layers:addAnchor(AnchorLeft, 'minimapBorder', AnchorLeft)
        layers:setMarginLeft(3)
        layers:setMarginRight(0)
        fullMap:addAnchor(AnchorLeft, 'layersPanel', AnchorRight)
        fullMap:setMarginLeft(4)
        fullMap:setMarginRight(0)
        zoomInButton:addAnchor(AnchorLeft, 'fullMap', AnchorLeft)
        zoomOutButton:addAnchor(AnchorLeft, 'fullMap', AnchorLeft)
    else
        layers:addAnchor(AnchorRight, 'minimapBorder', AnchorRight)
        layers:setMarginRight(3)
        layers:setMarginLeft(0)
        fullMap:addAnchor(AnchorRight, 'layersPanel', AnchorLeft)
        fullMap:setMarginRight(4)
        fullMap:setMarginLeft(0)
        zoomInButton:addAnchor(AnchorRight, 'fullMap', AnchorRight)
        zoomOutButton:addAnchor(AnchorRight, 'fullMap', AnchorRight)
    end
end

local function applyHorizontalPanelLayout(horizontalRoot, side)
    local rose = getLayoutWidget(horizontalRoot, 'rosePanel')
    local drag = getLayoutWidget(horizontalRoot, 'horizontalDragHandle')
    if not rose or not drag then
        return
    end

    local mirror = side == 'left'
    if mirror then
        rose:breakAnchors()
        rose:addAnchor(AnchorTop, 'minimapBorder', AnchorTop)
        rose:addAnchor(AnchorLeft, 'minimapBorder', AnchorLeft)
        rose:setMarginLeft(3)
        rose:setMarginRight(0)
        drag:breakAnchors()
        drag:addAnchor(AnchorTop, 'minimapBorder', AnchorTop)
        drag:addAnchor(AnchorRight, 'minimapBorder', AnchorRight)
        drag:setMarginRight(1)
        drag:setMarginLeft(0)
        drag:setImageSource('/images/ui/miniborder-top-right')
    else
        rose:breakAnchors()
        rose:addAnchor(AnchorTop, 'minimapBorder', AnchorTop)
        rose:addAnchor(AnchorRight, 'minimapBorder', AnchorRight)
        rose:setMarginRight(3)
        rose:setMarginLeft(0)
        drag:breakAnchors()
        drag:addAnchor(AnchorTop, 'minimapBorder', AnchorTop)
        drag:addAnchor(AnchorLeft, 'minimapBorder', AnchorLeft)
        drag:setMarginLeft(1)
        drag:setMarginRight(0)
        drag:setImageSource('/images/ui/miniborder-top-left')
    end
    rose:setMarginTop(3)
    drag:setMarginTop(1)
    applyHorizontalControlsLayout(horizontalRoot, mirror)
end

local function applyLayoutMode(isHorizontal, container)
    local ui = mapController.ui
    local defaultRoot = getLayoutRoot(ui, false)
    local horizontalRoot = getLayoutRoot(ui, true)
    if not defaultRoot or not horizontalRoot then
        return
    end

    local showHorizontal = isHorizontal == true
    local activeRoot = showHorizontal and horizontalRoot or defaultRoot
    local border = getLayoutWidget(activeRoot, 'minimapBorder')
    local mini = findMinimapWidget(ui)

    defaultRoot:setVisible(not showHorizontal)
    horizontalRoot:setVisible(showHorizontal)
    setPhantomBackgroundVisible(ui, not showHorizontal)

    if mini and border and mini:getParent() ~= border then
        mini:setParent(border)
    end
    if mini and border then
        mini:breakAnchors()
        mini:fill('parent')
        mini:setMargin(1)
    end

    syncMinimapLayoutAliases(activeRoot)
    minimapWidget = mini
    refreshVirtualFloors()

    if showHorizontal then
        applyHorizontalPanelLayout(horizontalRoot, resolveHorizontalSide(container))
        local drag = getLayoutWidget(horizontalRoot, 'horizontalDragHandle')
        if drag then
            drag:raise()
        end
    end

    addEvent(function()
        if not ui or ui:isDestroyed() then
            return
        end
        ui:updateLayout()
        if not showHorizontal and ui.minimapBorder then
            ui.minimapBorder:setSize({ width = 115, height = 111 })
        end
    end)
end

local function applyContainerLayout(container)
    if not container or container:isDestroyed() or not mapController.ui then
        return
    end

    local horizontal = container.isHorizontalPanel == true
    if horizontal then
        local height = container:getHeight() - container:getPaddingTop() - container:getPaddingBottom()
        if height > 0 then
            mapController.ui:setHeight(height)
        end
        local width = container:getWidth() - container:getPaddingLeft() - container:getPaddingRight()
        if width > 0 then
            mapController.ui:setWidth(width)
        end
    else
        mapController.ui:setHeight(mapController.ui.panelHeight or 116)
    end
    applyLayoutMode(horizontal, container)
end

-- A saved horizontal slot only exists while its columns are open. If the layout
-- came back with that side closed the minimap would be invisible, so park it in
-- the right panel without persisting, keeping the saved slot for next time.
local function rescueMinimapFromHiddenSlot()
    local ui = mapController.ui
    if not ui or ui:isDestroyed() then
        return
    end

    local parent = ui:getParent()
    if not parent or parent:isDestroyed() or parent.isHorizontalPanel ~= true then
        return
    end

    if parent:isVisible() and parent:getWidth() > 0 then
        return
    end

    local mainRightPanel = modules.game_interface.getMainRightPanel()
    if not mainRightPanel or mainRightPanel:isDestroyed() then
        return
    end

    parent:removeChild(ui)
        mainRightPanel:addChild(ui)
end

local function findMinimapDropTarget(window, mousePos)
    local root = g_ui.getRootWidget()
    if not root or not window then
        return nil
    end

    local children = root:recursiveGetChildrenByPos(mousePos)
    for i = 1, #children do
        local child = children[i]
        if child ~= window and child:getClassName() == 'UIMiniWindowContainer'
            and type(child.onDrop) == 'function' and child:onDrop(window, mousePos) then
            return child
        end
    end
    return nil
end

local function setVirtualFloor(target)
    if type(target) ~= 'number' then
        return
    end

    target = math.max(MIN_VIRTUAL_FLOOR, math.min(MAX_VIRTUAL_FLOOR, target))
    local delta = target - virtualFloor
    if delta == 0 then
        return
    end

    local mini = mapController.ui and mapController.ui.minimapBorder
        and mapController.ui.minimapBorder.minimap
    if not mini or mini:isDestroyed() then
        return
    end

    if delta < 0 then
        mini:floorUp(-delta)
    else
        mini:floorDown(delta)
    end

    virtualFloor = target
    refreshVirtualFloors()
end

local function floorFromMousePos(panel, mousePos)
    local strip = panel:getChildById('automapLayers')
    if not strip or strip:isDestroyed() then
        return nil
    end

    -- The mark is anchored to the strip top, so mirror the offset that
    -- refreshVirtualFloors applies and centre it on the cursor.
    local mark = panel:getChildById('layersMark')
    local markHalf = mark and not mark:isDestroyed() and math.floor(mark:getHeight() / 2) or 0
    local offset = mousePos.y - strip:getY() - markHalf - 1
    return math.floor(offset / FLOOR_MARK_STEP + 0.5)
end

local function setupFloorIndicator(panel)
    if not panel or panel:isDestroyed() then
        return
    end

    function panel.onMousePress(self, mousePos, button)
        if button ~= MouseLeftButton then
            return false
        end
        self._floorDragActive = true
        -- The strip is only 20 px wide, so hold the mouse to keep tracking the
        -- drag once the cursor drifts off it. Never steal an existing grab.
        if not g_ui.isMouseGrabbed() then
            self:grabMouse()
            self._floorDragGrabbed = true
        end
        setVirtualFloor(floorFromMousePos(self, mousePos))
        return true
    end

    function panel.onMouseMove(self, mousePos, mouseMoved)
        if not self._floorDragActive then
            return false
        end
        setVirtualFloor(floorFromMousePos(self, mousePos))
        return true
    end

    function panel.onMouseRelease(self, mousePos, button)
        if button ~= MouseLeftButton or not self._floorDragActive then
            return false
        end
        self._floorDragActive = nil
        if self._floorDragGrabbed then
            self._floorDragGrabbed = nil
            self:ungrabMouse()
        end
        return true
    end

    function panel.onMouseWheel(_, mousePos, direction)
        if direction == MouseWheelUp then
            setVirtualFloor(virtualFloor - 1)
        else
            setVirtualFloor(virtualFloor + 1)
        end
        return true
    end
end

local function roseStepsForHold(elapsed)
    elapsed = (elapsed or 0) - ROSE_HOLD_DELAY
    if elapsed <= 0 then
        return 1
    end

    local ramp = math.min(1, elapsed / ROSE_FULL_SPEED_MS)
    return 1 + math.floor(ramp * (ROSE_MAX_STEPS - 1))
end

local function setupRoseButtons(rosePanel)
    if not rosePanel or rosePanel:isDestroyed() then
        return
    end

    for _, child in ipairs(rosePanel:getChildren()) do
        local direction = child.roseDirection
        if direction and ROSE_DIRECTIONS[direction] then
            g_mouse.bindAutoPress(child, function(_, _, _, elapsed)
                onClickRoseButton(direction, roseStepsForHold(elapsed))
            end, ROSE_HOLD_DELAY, MouseLeftButton, ROSE_REPEAT_INTERVAL)
        end
    end
end

local function setupHorizontalDragHandle(handle)
    if not handle or handle:isDestroyed() then
        return
    end

    local window = mapController.ui
    if not window or window:isDestroyed() then
        return
    end

    function handle.onMousePress(_, mousePos, button)
        if button ~= MouseLeftButton then
            return false
        end
        window:raise()
        window:onDragEnter(mousePos)
        window._horizontalDragActive = true
        return true
    end

    function handle.onMouseMove(_, mousePos, mouseMoved)
        if not window._horizontalDragActive then
            return false
        end
        window:raise()
        return window:onDragMove(mousePos, mouseMoved)
    end

    function handle.onMouseRelease(_, mousePos, button)
        if button ~= MouseLeftButton or not window._horizontalDragActive then
            return false
        end
        window._horizontalDragActive = false
        window:onDragLeave(findMinimapDropTarget(window, mousePos), mousePos)
        return true
    end
end

function onChangeWorldTime(hour, minute)
--[[ 

check 
tfs c++ (old) : void ProtocolGame::sendWorldTime()
tfs lua (new) : function Player.sendWorldTime(self, time)
Canary: void ProtocolGame::sendTibiaTime(int32_t time)
 ]]

    currentDayTime = {
        h = hour % 24,
        m = minute
    }

    mapController:scheduleEvent(function()
        local nextH = currentDayTime.h
        local nextM = currentDayTime.m + 12
        if nextM >= 60 then
            nextH = nextH + 1
            nextM = nextM - 60
        end

        onChangeWorldTime(nextH, nextM)
    end, 30000, 'dayTime')

    local position = math.floor((124 / (24 * 60)) * ((hour * 60) + minute))
    local mainWidth = 31
    local secondaryWidth = 0

    if (position + 31) >= 124 then
        secondaryWidth = ((position + 31) - 124) + 1
        mainWidth = 31 - secondaryWidth
    end

    local rosePanel = mapController.ui and mapController.ui.rosePanel
    if not rosePanel or rosePanel:isDestroyed() or not rosePanel.ambients then
        return
    end

    rosePanel.ambients.main:setWidth(mainWidth)
    rosePanel.ambients.secondary:setWidth(secondaryWidth)

    if secondaryWidth == 0 then
        rosePanel.ambients.secondary:hide()
    else
        rosePanel.ambients.secondary:setImageClip('0 0 ' .. secondaryWidth .. ' 31')
        rosePanel.ambients.secondary:show()
    end

    if mainWidth == 0 then
        rosePanel.ambients.main:hide()
    else
        rosePanel.ambients.main:setImageClip(position .. ' 0 ' .. mainWidth .. ' 31')
        rosePanel.ambients.main:show()
    end
end

function mapController:onInit()
    if not self.ui then
        return
    end

    prepareDefaultLayout(self.ui)
    syncMinimapLayoutAliases(getLayoutRoot(self.ui, false))
    minimapWidget = findMinimapWidget(self.ui)
    if minimapWidget then
        for _, id in ipairs({ 'floorUpButton', 'floorDownButton', 'zoomInButton', 'zoomOutButton', 'resetButton' }) do
            local button = minimapWidget:getChildById(id)
            if button then
                button:hide()
            end
        end
    end

    self.ui.moveOnlyToMain = true
    self.ui.allowHorizontalDrop = true
    self.ui.onContainerChanged = function(_, container)
        applyContainerLayout(container)
    end
    setupHorizontalDragHandle(getLayoutWidget(getLayoutRoot(self.ui, true), 'horizontalDragHandle'))
    -- Both layouts keep their own indicator, so each one needs the slider wiring.
    setupFloorIndicator(getLayoutWidget(getLayoutRoot(self.ui, false), 'layersPanel'))
    setupFloorIndicator(getLayoutWidget(getLayoutRoot(self.ui, true), 'layersPanel'))
    setupRoseButtons(getLayoutWidget(getLayoutRoot(self.ui, false), 'rosePanel'))
    setupRoseButtons(getLayoutWidget(getLayoutRoot(self.ui, true), 'rosePanel'))
    applyContainerLayout(self.ui:getParent())
end

function mapController:onGameStart()
    mapController:registerEvents(g_game, {
        onChangeWorldTime = onChangeWorldTime
    })

    mapController:registerEvents(LocalPlayer, {
        onPositionChange = onPositionChange
    }):execute()

    minimapWidget = findMinimapWidget(self.ui)

    -- Load Map
    g_minimap.clean()

    local minimapFile = '/minimap'
    local loadFnc = nil

    if otmm then
        minimapFile = minimapFile .. '.otmm'
        loadFnc = g_minimap.loadOtmm
    else
        minimapFile = minimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'
        loadFnc = g_map.loadOtcm
    end

    if g_resources.fileExists(minimapFile) then
        loadFnc(minimapFile)
    end

    if self.ui.minimapBorder and self.ui.minimapBorder.minimap then
        self.ui.minimapBorder.minimap:load()
    end

    -- Controller modules never restore their mini window on their own, so the
    -- saved slot (a horizontal top panel or a sidebar column) has to be applied
    -- here or the minimap always reopens where setUI parked it.
    if self.ui.setupOnStart then
        self.ui:setupOnStart()
    end

    addEvent(function()
        if self.ui and not self.ui:isDestroyed() then
            rescueMinimapFromHiddenSlot()
            applyContainerLayout(self.ui:getParent())
        end
    end)
end

function mapController:onGameEnd()
    -- Save Map
    if otmm then
        g_minimap.saveOtmm('/minimap.otmm')
    else
        g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
    end

    if self.ui and self.ui.minimapBorder and self.ui.minimapBorder.minimap then
        self.ui.minimapBorder.minimap:save()
    end

    -- Persist the slot it is sitting in, otherwise closing the client keeps
    -- whatever parent was recorded on the last drag.
    if self.ui and not self.ui:isDestroyed() then
        local parent = self.ui:getParent()
        if parent and not parent:isDestroyed() and parent:getClassName() == 'UIMiniWindowContainer' then
            parent:saveChildren()
        end
    end
end

function mapController:onTerminate()
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end
end

function zoomIn()
    local mini = mapController.ui and mapController.ui.minimapBorder and mapController.ui.minimapBorder.minimap
    if mini then
        mini:zoomIn()
    end
end

function zoomOut()
    local mini = mapController.ui and mapController.ui.minimapBorder and mapController.ui.minimapBorder.minimap
    if mini then
        mini:zoomOut()
    end
end

function openCyclopediaMap()
    if g_game.getClientVersion() >= 1310 then
        modules.game_cyclopedia.toggle('map')
    else
        return fullscreen()
    end
end

function fullscreen()
    local minimapWidget = mapController.ui.minimapBorder.minimap
    if not minimapWidget then
        minimapWidget = fullscreenWidget
    end
    local zoom;

    if not minimapWidget then
        return
    end

    if minimapWidget.fullMapView then
        fullscreenWidget = nil
        minimapWidget:setParent(mapController.ui.minimapBorder)
        minimapWidget:fill('parent')
        mapController.ui:show()
        zoom = minimapWidget.zoomMinimap
        g_keyboard.unbindKeyDown('Escape')
        minimapWidget.fullMapView = false
    else
        fullscreenWidget = minimapWidget
        mapController.ui:hide(true)
        minimapWidget:setParent(modules.game_interface.getRootPanel())
        minimapWidget:fill('parent')
        zoom = minimapWidget.zoomFullmap
        g_keyboard.bindKeyDown('Escape', fullscreen)
        minimapWidget.fullMapView = true
    end

    local pos = oldPos or minimapWidget:getCameraPosition()
    oldPos = minimapWidget:getCameraPosition()
    minimapWidget:setZoom(zoom)
    minimapWidget:setCameraPosition(pos)
end

function upLayer()
    setVirtualFloor(virtualFloor - 1)
end

function downLayer()
    setVirtualFloor(virtualFloor + 1)
end

function onClickRoseButton(dir, steps)
    local vector = ROSE_DIRECTIONS[dir]
    if not vector then
        return
    end

    local mini = mapController.ui and mapController.ui.minimapBorder
        and mapController.ui.minimapBorder.minimap
    if not mini or mini:isDestroyed() then
        return
    end

    steps = steps or 1
    mini:move(vector[1] * steps, vector[2] * steps)
end

function resetMap()
    mapController.ui.minimapBorder.minimap:reset()
    local player = g_game.getLocalPlayer()
    if player then
        virtualFloor = player:getPosition().z
        refreshVirtualFloors()
    end
end

function getMiniMapUi()
    if not minimapWidget and mapController and mapController.ui and mapController.ui.minimapBorder then
        minimapWidget = mapController.ui.minimapBorder.minimap
    end
    return minimapWidget
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('miniMap', tr('Show miniMap'),
                '/images/topbuttons/minimap', toggle)
            iconTopMenu:setOn(mapController.ui:isVisible())
            mapController.ui:setBorderColor('black')
            mapController.ui:setBorderWidth(2)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        mapController.ui:setBorderColor('alpha')
        mapController.ui:setBorderWidth(0)
        -- Leaving extended view only has to rescue the minimap when it is
        -- homeless. Docked in a horizontal top slot is a valid saved spot, so
        -- forcing it back into the right column would undo the restored layout.
        local currentParent = mapController.ui:getParent()
        local dockedInSlot = currentParent and not currentParent:isDestroyed()
            and currentParent.isHorizontalPanel == true
        if not dockedInSlot then
            local mainRightPanel = modules.game_interface.getMainRightPanel()
            if not mainRightPanel:hasChild(mapController.ui) then
                mainRightPanel:addChild(mapController.ui)
            end
        end
        mapController.ui:show()

    end
    mapController.ui.moveOnlyToMain = not extendedView
    mapController.ui.allowHorizontalDrop = true
end

function toggle()
    if iconTopMenu:isOn() then
        mapController.ui:hide()
        iconTopMenu:setOn(false)
    else
        mapController.ui:show()
        iconTopMenu:setOn(true)
    end
end
