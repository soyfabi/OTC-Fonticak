function UIMinimap:onCreate()
    self.autowalk = true
end

function UIMinimap:onSetup()
    self.flagWindow = nil
    self.floorUpWidget = self:getChildById('floorUpButton')
    self.floorDownWidget = self:getChildById('floorDownButton')
    self.zoomInWidget = self:getChildById('zoomInButton')
    self.zoomOutWidget = self:getChildById('zoomOutButton')
    self.flags = {}
    self.partyPins = {}
    self.fullMapView = false
    -- CrystalOTC default: render the compact minimap one level closer.
    self.zoomMinimap = 1
    self.zoomFullmap = 0
    self.alternatives = {}
    self.onAddAutomapFlag = function(pos, icon, description)
        self:addFlag(pos, icon, description)
    end
    self.onRemoveAutomapFlag = function(pos, icon, description)
        self:removeFlag(pos, icon, description)
    end
    connect(g_game, {
        onAddAutomapFlag = self.onAddAutomapFlag,
        onRemoveAutomapFlag = self.onRemoveAutomapFlag
    })
end

function UIMinimap:onDestroy()
    if self._smoothZoomEvent then
        removeEvent(self._smoothZoomEvent)
        self._smoothZoomEvent = nil
    end

    for _, widget in pairs(self.alternatives) do
        widget:destroy()
    end
    self.alternatives = {}
    disconnect(g_game, {
        onAddAutomapFlag = self.onAddAutomapFlag,
        onRemoveAutomapFlag = self.onRemoveAutomapFlag
    })
    self:destroyFlagWindow()
    self:clearPartyPins()
    self.flags = {}
end

function UIMinimap:onVisibilityChange()
    if not self:isVisible() then
        self:destroyFlagWindow()
    end
end

function UIMinimap:onCameraPositionChange(cameraPos)
    self:updateCrossVisibility()
    self:updateAllPartyPinsVisibility()
end

function UIMinimap:isCyclopediaMap()
    local parent = self:getParent()
    return parent and parent:getId() == "MapBase"
end

local PARTY_PIN_MEMBER = '/game_cyclopedia/images/icon-map-player-yellow'
local PARTY_PIN_LEADER = '/game_cyclopedia/images/icon-map-player-red'

local function positionMarkerAtTile(minimap, marker, displayPos)
    marker:breakAnchors()
    minimap:anchorPosition(marker, AnchorRight, displayPos, AnchorHorizontalCenter)
    minimap:anchorPosition(marker, AnchorBottom, displayPos, AnchorVerticalCenter)
end

local function destroyPartyPinFloorLabel(pin)
    if not pin or not pin.floorDeltaLabel or pin.floorDeltaLabel:isDestroyed() then
        return
    end

    pin.floorDeltaLabel:destroy()
    pin.floorDeltaLabel = nil
end

local function updatePartyPinFloorLabel(minimap, pin, deltaZ)
    if not pin or not minimap then
        return
    end

    if pin:isDestroyed() or pin:isHidden() or deltaZ == 0 then
        destroyPartyPinFloorLabel(pin)
        return
    end

    local label = pin.floorDeltaLabel

    if not label or label:isDestroyed() then
        label = g_ui.createWidget('Label', minimap)
        label:setId('partyPinFloorDelta')
        label:setPhantom(true)
        label:setFocusable(false)
        label:setTextAlign(AlignLeft)
        pin.floorDeltaLabel = label
    end

    label:setText(string.format('%+d', deltaZ))
    label:resizeToText()
    label:breakAnchors()

    local pinPos = pin:getPosition()
    local pinSize = pin:getSize()
    local labelSize = label:getSize()

    local floorLabelOffsetX = 1
    local floorLabelOffsetY = 6 -- screen Y grows downward: increase to move text lower

    if minimap:isCyclopediaMap() then
        floorLabelOffsetX = 2
        floorLabelOffsetY = 4
        label:setFont('verdana-11px-rounded')
        label:setColor('#FFFF66')
    else
        label:setFont('verdana-11px-monochrome')
        label:setColor('#FFFFFF')
    end

    label:setPosition({
        x = pinPos.x + pinSize.width + floorLabelOffsetX,
        y = pinPos.y + math.floor((pinSize.height - labelSize.height) / 2) + floorLabelOffsetY
    })
    label:show()
    label:raise()
end

local function updateMinimapMarkerVisibility(minimap, marker)
    if not marker or not marker.pos then
        return
    end

    local cameraPos = minimap:getCameraPosition()
    if not cameraPos then
        marker:hide()
        return
    end

    local markerZ = marker.pos.z
    local viewZ = cameraPos.z
    local displayPos = {
        x = marker.pos.x,
        y = marker.pos.y,
        z = viewZ
    }

    if not minimap:isCyclopediaMap() then
        if viewZ ~= markerZ then
            marker:hide()
            return
        end

        marker:setOpacity(1)
        marker:show()
        positionMarkerAtTile(minimap, marker, displayPos)
        return
    end

    if viewZ < 0 or viewZ > 15 then
        marker:hide()
        return
    end

    marker:setOpacity(viewZ == markerZ and 1 or 0.25)
    marker:show()
    positionMarkerAtTile(minimap, marker, displayPos)
end

local function updatePartyPinVisibility(minimap, pin)
    if not pin or not pin.pos then
        return
    end

    local cameraPos = minimap:getCameraPosition()
    if not cameraPos then
        pin:hide()
        destroyPartyPinFloorLabel(pin)
        return
    end

    local markerZ = pin.pos.z
    local viewZ = cameraPos.z
    local playerZ = viewZ

    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and localPlayer:getPosition() then
        playerZ = localPlayer:getPosition().z
    end

    -- Tibia floors: lower Z is up. Member above you => +N, below you => -N.
    local deltaZ = playerZ - markerZ
    local displayPos = {
        x = pin.pos.x,
        y = pin.pos.y,
        z = viewZ
    }

    if viewZ < 0 or viewZ > 15 then
        pin:hide()
        destroyPartyPinFloorLabel(pin)
        return
    end

    local sameFloorAsView = viewZ == markerZ
    local sameFloorAsPlayer = playerZ == markerZ

    if minimap:isCyclopediaMap() then
        pin:setOpacity(sameFloorAsView and 1 or 0.25)
    else
        pin:setOpacity(sameFloorAsView and 1 or 0.55)
    end

    pin:show()
    positionMarkerAtTile(minimap, pin, displayPos)
    updatePartyPinFloorLabel(minimap, pin, sameFloorAsPlayer and 0 or deltaZ)
end

function UIMinimap:updateCrossVisibility()
    updateMinimapMarkerVisibility(self, self.cross)
end

function UIMinimap:clearPartyPins()
    if not self.partyPins then
        self.partyPins = {}
        return
    end

    for _, pin in pairs(self.partyPins) do
        destroyPartyPinFloorLabel(pin)
        pin:destroy()
    end

    self.partyPins = {}
end

function UIMinimap:updateAllPartyPinsVisibility()
    if not self.partyPins then
        return
    end

    for _, pin in pairs(self.partyPins) do
        updatePartyPinVisibility(self, pin)
    end
end

function UIMinimap:updatePartyPins(memberById)
    memberById = memberById or {}
    self.partyPins = self.partyPins or {}

    for id, pin in pairs(self.partyPins) do
        if not memberById[id] then
            destroyPartyPinFloorLabel(pin)
            pin:destroy()
            self.partyPins[id] = nil
        end
    end

    for id, data in pairs(memberById) do
        local pos = data.pos
        if not pos then
            goto continue
        end

        local pinIcon = data.pinIcon or PARTY_PIN_MEMBER
        local pin = self.partyPins[id]
        if not pin then
            pin = g_ui.createWidget('MinimapCross', self)
            pin:setId('partyPin_' .. id)
            pin:setImageSource('')
            pin:setClipping(false)
            pin:setPhantom(false)
            pin:setFocusable(false)
            self.partyPins[id] = pin
        end

        pin:setIcon(pinIcon)
        pin:setIconColor('#ffffff')

        pin.pos = {
            x = pos.x,
            y = pos.y,
            z = pos.z
        }
        pin:setTooltip(data.tooltip or data.name or tr('Party member'))
        ::continue::
    end

    self:updateAllPartyPinsVisibility()

    if self.cross and not self.cross:isDestroyed() then
        self.cross:raise()
    end

    for _, pin in pairs(self.partyPins) do
        if pin.floorDeltaLabel and not pin.floorDeltaLabel:isDestroyed() and pin.floorDeltaLabel:isVisible() then
            pin.floorDeltaLabel:raise()
        end
    end
end

function UIMinimap:getVisibleTileBounds()
    local cameraPos = self:getCameraPosition()
    if not cameraPos then
        return nil
    end

    local padding = self:getPaddingRect()
    if not padding or padding.width <= 0 or padding.height <= 0 then
        return nil
    end

    local topLeft = self:getTilePosition({
        x = padding.x,
        y = padding.y
    })
    local bottomRight = self:getTilePosition({
        x = padding.x + padding.width - 1,
        y = padding.y + padding.height - 1
    })

    if not topLeft or not bottomRight then
        return nil
    end

    local margin = 4
    return {
        minX = math.min(topLeft.x, bottomRight.x) - margin,
        maxX = math.max(topLeft.x, bottomRight.x) + margin,
        minY = math.min(topLeft.y, bottomRight.y) - margin,
        maxY = math.max(topLeft.y, bottomRight.y) + margin,
        z = cameraPos.z
    }
end

function UIMinimap:setLevelSeparatorIntensity(value)
    if not self.setFloorSeparatorOpacity then
        return
    end

    if value < 0 then
        self:setFloorSeparatorOpacity(1)
        return
    end

    self:setFloorSeparatorOpacity(value)
end

function UIMinimap:smoothZoomBy(step, mousePos)
    if not self.setScale or step == 0 then
        return step > 0 and self:zoomIn() or self:zoomOut()
    end

    local targetZoom = self:getZoom() + step
    if targetZoom < self:getMinZoom() or targetZoom > self:getMaxZoom() then
        return false
    end

    if self._smoothZoomEvent then
        removeEvent(self._smoothZoomEvent)
        self._smoothZoomEvent = nil
    end

    local startScale = self:getScale()
    if not self:setZoom(targetZoom) then
        return false
    end

    local targetScale = self:getScale()
    self:setScale(startScale)

    if self.onSmoothZoomScaleChange then
        self:onSmoothZoomScaleChange(self:getScale())
    end

    local startedAt = g_clock.millis()
    local duration = 300

    local function animate()
        if self:isDestroyed() then
            return
        end

        local progress = math.min(1, (g_clock.millis() - startedAt) / duration)
        local eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10)

        self:setScale(startScale * math.pow(targetScale / startScale, eased))

        if self.onSmoothZoomScaleChange then
            self:onSmoothZoomScaleChange(self:getScale())
        end

        if progress < 1 then
            self._smoothZoomEvent = scheduleEvent(animate, 16)
        else
            self:setScale(targetScale)
            if self.onSmoothZoomScaleChange then
                self:onSmoothZoomScaleChange(self:getScale())
            end
            self._smoothZoomEvent = nil
        end
    end

    self._smoothZoomEvent = scheduleEvent(animate, 16)
    return true
end

function UIMinimap:hideFloor()
    self.floorUpWidget:hide()
    self.floorDownWidget:hide()
end

function UIMinimap:hideZoom()
    self.zoomInWidget:hide()
    self.zoomOutWidget:hide()
end

function UIMinimap:disableAutoWalk()
    self.autowalk = false
end

function UIMinimap:load()
    local settings = g_settings.getNode('Minimap')
    if settings then
        if settings.flags then
            for _, flag in pairs(settings.flags) do
                self:addFlag(flag.position, flag.icon, flag.description)
            end
        end
        self.zoomFullmap = settings.zoomFull or self.zoomMinimap
    end
    self:setZoom(self.zoomMinimap)
end

function UIMinimap:save()
    local settings = {
        flags = {}
    }
    for _, flag in pairs(self.flags) do
        if not flag.temporary then
            table.insert(settings.flags, {
                position = flag.pos,
                icon = flag.icon,
                description = flag.description
            })
        end
    end
    settings.zoomFull = self.zoomFullmap
    g_settings.setNode('Minimap', settings)
end

local function onFlagMouseRelease(widget, pos, button)
    if button == MouseLeftButton then
        local player = g_game.getLocalPlayer()
        if Position.distance(player:getPosition(), widget.pos) > 250 then
            modules.game_textmessage.displayStatusMessage(tr('Destination is out of range.'))
            return false
        end

        if widget:getParent().autowalk then
            player:autoWalk(widget.pos)
        end
        return true

    elseif button == MouseRightButton then
        local minimap = widget:getParent()
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('Edit Mark'), function()
            minimap:createFlagWindow(widget.pos, widget)
        end)
        menu:addOption(tr('Delete Mark'), function()
            widget:destroy()
        end)
        menu:display(pos)
        return true
    end
    return false
end

function UIMinimap:setCrossPosition(pos)
    local cross = self.cross
    if not self.cross then
        cross = g_ui.createWidget('MinimapCross', self)
        cross:setImageSource('')
        cross:setIcon('/game_cyclopedia/images/icon-map-player-green')
        self.cross = cross
    end

    if not pos then
        cross.pos = nil
        cross:breakAnchors()
        cross:hide()
        return
    end

    cross.pos = {
        x = pos.x,
        y = pos.y,
        z = pos.z
    }
    cross:setTooltip(tr('You are here'))
    self:updateCrossVisibility()
    self:updateAllPartyPinsVisibility()

    if self.cross and not self.cross:isDestroyed() then
        self.cross:raise()
    end
end

function UIMinimap:addFlag(pos, icon, description, temporary)
    if not pos or not icon then
        return
    end
    local flag = self:getFlag(pos, icon, description)
    if flag or not icon then
        return
    end
    temporary = temporary or false

    flag = g_ui.createWidget('MinimapFlag')
    self:insertChild(1, flag)
    flag.pos = pos
    flag.description = description
    flag.icon = icon
    flag.temporary = temporary
    if type(tonumber(icon)) == 'number' then
        flag:setIcon('/images/game/minimap/flag' .. icon)
    else
        flag:setIcon(resolvepath(icon, 1))
    end
    flag:setTooltip(description)
    flag.onMouseRelease = onFlagMouseRelease
    flag.onDestroy = function()
        table.removevalue(self.flags, flag)
    end
    table.insert(self.flags, flag)
    self:centerInPosition(flag, pos)
end

function UIMinimap:updateFlag(flag, icon, description)
    if not flag then return end
    flag.icon = icon
    flag.description = description
    if type(tonumber(icon)) == 'number' then
        flag:setIcon('/images/game/minimap/flag' .. icon)
    else
        flag:setIcon(resolvepath(icon, 1))
    end
    flag:setTooltip(description)
end

function UIMinimap:setAlternativeWidgetsVisible(show)
    local layout = self:getLayout()
    layout:disableUpdates()
    for _, widget in pairs(self.alternatives) do
        if show then
            self:insertChild(1, widget)
            self:centerInPosition(widget, widget.pos)
        else
            self:removeChild(widget)
        end
    end
    layout:enableUpdates()
    layout:update()
end

function UIMinimap:onZoomChange(zoom)
    if self.fullMapView then
        self.zoomFullmap = zoom
    else
        self.zoomMinimap = zoom
    end

    for _, widget in pairs(self.alternatives) do
        if (not widget.minZoom or widget.minZoom >= zoom) and widget.maxZoom <= zoom then
            widget:show()
        else
            widget:hide()
        end
    end

    self:updateAllPartyPinsVisibility()
end

function UIMinimap:getFlag(pos)
    for _, flag in pairs(self.flags) do
        if flag.pos.x == pos.x and flag.pos.y == pos.y and flag.pos.z == pos.z then
            return flag
        end
    end
    return nil
end

function UIMinimap:removeFlag(pos, icon, description)
    local flag = self:getFlag(pos)
    if flag then
        flag:destroy()
    end
end

function UIMinimap:reset()
    local player = g_game.getLocalPlayer()
    if player then
        self:setCameraPosition(player:getPosition())
    end
end

function UIMinimap:move(x, y)
    local cameraPos = self:getCameraPosition()
    local scale = self:getScale()
    if scale > 1 then
        scale = 1
    end
    local dx = x / scale
    local dy = y / scale
    local pos = {
        x = cameraPos.x - dx,
        y = cameraPos.y - dy,
        z = cameraPos.z
    }
    self:setCameraPosition(pos)
end

function UIMinimap:onMouseWheel(mousePos, direction)
    local keyboardModifiers = g_keyboard.getModifiers()
    if direction == MouseWheelUp and keyboardModifiers == KeyboardNoModifier then
        if self:isCyclopediaMap() then
            self:smoothZoomBy(1, mousePos)
            return true
        end
        self:zoomIn()
    elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
        if self:isCyclopediaMap() then
            self:smoothZoomBy(-1, mousePos)
            return true
        end
        self:zoomOut()
    elseif direction == MouseWheelDown and keyboardModifiers == KeyboardCtrlModifier then
        self:floorUp(1)
    elseif direction == MouseWheelUp and keyboardModifiers == KeyboardCtrlModifier then
        self:floorDown(1)
    end
end

function UIMinimap:onMousePress(pos, button)
    if not self:isDragging() then
        self.allowNextRelease = true
    end
end

function UIMinimap:onMouseRelease(pos, button)
    if not self.allowNextRelease then
        return true
    end
    self.allowNextRelease = false

    local mapPos = self:getTilePosition(pos)
    if not mapPos then
        return false
    end

    if button == MouseLeftButton then
        local player = g_game.getLocalPlayer()
        if g_game.getClientVersion() > 1288 and g_keyboard.isCtrlPressed() and g_keyboard.isShiftPressed() then
            return g_game.sendGmTeleport(mapPos)
        end
        if Position.distance(player:getPosition(), mapPos) > 250 then
            modules.game_textmessage.displayStatusMessage(tr('Destination is out of range.'))
            return false
        end

        if self.autowalk then
            player:autoWalk(mapPos)
        end
        return true
    elseif button == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('Create mark'), function()
            self:createFlagWindow(mapPos)
        end)
        menu:display(pos)
        return true
    end
    return false
end

function UIMinimap:onDragEnter(pos)
    self.dragReference = pos
    self.dragCameraReference = self:getCameraPosition()
    return true
end

function UIMinimap:onDragMove(pos, moved)
    local scale = self:getScale()
    local dx = (self.dragReference.x - pos.x) / scale
    local dy = (self.dragReference.y - pos.y) / scale
    local pos = {
        x = self.dragCameraReference.x + dx,
        y = self.dragCameraReference.y + dy,
        z = self.dragCameraReference.z
    }
    self:setCameraPosition(pos)
    return true
end

function UIMinimap:onDragLeave(widget, pos)
    return true
end

function UIMinimap:onStyleApply(styleName, styleNode)
    for name, value in pairs(styleNode) do
        if name == 'autowalk' then
            self.autowalk = value
        end
    end
end

function UIMinimap:createFlagWindow(pos, existingFlag)
    if self.flagWindow then
        return
    end
    if not pos then
        return
    end

    self.flagWindow = g_ui.createWidget('MinimapFlagWindow', rootWidget)
    self.flagWindow:setText(tr(existingFlag and 'Edit Mark' or 'Create Mark'))

    local description = self.flagWindow:getChildById('description')
    local okButton = self.flagWindow:getChildById('okButton')
    local cancelButton = self.flagWindow:getChildById('cancelButton')

    local flagRadioGroup = UIRadioGroup.create()
    for i = 0, 19 do
        local flagButton = self.flagWindow:getChildById('flag' .. i)
        flagButton.icon = i
        flagRadioGroup:addWidget(flagButton)
    end

    if existingFlag then
        description:setText(existingFlag.description or '')
        local icon = tonumber(existingFlag.icon)
        if icon then
            local flagButton = self.flagWindow:getChildById('flag' .. icon)
            if flagButton then
                flagRadioGroup:selectWidget(flagButton, true)
            end
        end
    else
        flagRadioGroup:selectWidget(flagRadioGroup:getFirstWidget())
    end

    local successFunc = function()
        local icon = flagRadioGroup:getSelectedWidget().icon
        local text = description:getText()
        if existingFlag then
            self:updateFlag(existingFlag, icon, text)
        else
            self:addFlag(pos, icon, text)
        end
        self:destroyFlagWindow()
    end

    local cancelFunc = function()
        self:destroyFlagWindow()
    end

    okButton.onClick = successFunc
    cancelButton.onClick = cancelFunc

    self.flagWindow.onEnter = successFunc
    self.flagWindow.onEscape = cancelFunc

    self.flagWindow.onDestroy = function()
        flagRadioGroup:destroy()
    end
end

function UIMinimap:destroyFlagWindow()
    if self.flagWindow then
        self.flagWindow:destroy()
        self.flagWindow = nil
    end
end
