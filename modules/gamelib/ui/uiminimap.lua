local minimapsWithMarks = setmetatable({}, { __mode = 'k' })
local markNames = {
    [0] = 'Check', 'Question', 'Exclamation', 'Star', 'Cross', 'Signal',
    'Mouth', 'Spear', 'Sword', 'Flag', 'Lock', 'Bag', 'Skull', 'Coin',
    'Arrow Up', 'Arrow Down', 'Arrow Right', 'Arrow Left', 'Triangle Up', 'Triangle Down',
    'NPC', 'House',
    passage = 'Passage'
}
local markTextColors = {
    { 'White', '#ffffff' },
    { 'Green', '#78e56b' },
    { 'Orange', '#ffa64d' },
    { 'Blue', '#72b8ff' },
    { 'Red', '#ff6969' },
    { 'Violet', '#ca91ff' },
    { 'Gray', '#b8b8b8' }
}

function UIMinimap:getMarkName(icon)
    return tr(markNames[tonumber(icon) or icon] or 'Custom')
end

local platformType = g_window.getPlatformType()
local markInputUsesUtf8 = platformType == 'ANDROID-EGL' or platformType == 'BROWSER-WEBGL'
local MARK_TEXT_LIMIT = 10
local lowercaseAccents = {}
for code = 192, 222 do
    if code ~= 215 then
        if markInputUsesUtf8 then
            lowercaseAccents[string.char(195, code - 64)] = string.char(195, code - 32)
        else
            lowercaseAccents[string.char(code)] = string.char(code + 32)
        end
    end
end
local uppercaseAccents = markInputUsesUtf8 and '\195[\128-\150\152-\158]' or '[\192-\214\216-\222]'

local function normalizeMarkSearch(text)
    return text:trim():lower():gsub(uppercaseAccents, lowercaseAccents)
end

local function limitMapText(text)
    if not markInputUsesUtf8 then
        return text:sub(1, MARK_TEXT_LIMIT), math.min(#text, MARK_TEXT_LIMIT)
    end
    local count = 0
    for start in text:gmatch('()[^\128-\191]') do
        if count == MARK_TEXT_LIMIT then
            return text:sub(1, start - 1), count
        end
        count = count + 1
    end
    return text, count
end

local function updateMapTextCount(field)
    local input = field:getText()
    local text, count = limitMapText(input)
    if text ~= input and not field.limitMarkTextEvent then
        -- The native text callback can still hold a view of the current input.
        field.limitMarkTextEvent = addEvent(function()
            field.limitMarkTextEvent = nil
            local current = field:getText()
            local limited = limitMapText(current)
            if limited ~= current then
                local cursor = field:getCursorPos()
                field:setText(limited, true)
                field:setCursorPos(math.min(cursor, #limited))
            end
        end)
    end
    field:getParent().mapTextCount:setText(count .. '/' .. MARK_TEXT_LIMIT)
end

local function markPositionKey(pos)
    return pos.x .. ':' .. pos.y .. ':' .. pos.z
end

local function notifyMarksChanged(minimap)
    if minimap.markSearch ~= '' and minimap.onMarksChanged then
        minimap:onMarksChanged()
    end
end

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
    self.flagsByPosition = {}
    self.markSearch = ''
    minimapsWithMarks[self] = true
    self.partyPins = {}
    self.fullMapView = false
    -- CrystalOTC default: render the compact minimap one level closer.
    self.zoomMinimap = 1
    self.zoomFullmap = 0
    self.onAddAutomapFlag = function(pos, icon, description)
        self:addFlag(pos, icon, description)
        notifyMarksChanged(self)
    end
    self.onRemoveAutomapFlag = function(pos)
        self:removeFlag(pos)
        notifyMarksChanged(self)
    end
    connect(g_game, {
        onAddAutomapFlag = self.onAddAutomapFlag,
        onRemoveAutomapFlag = self.onRemoveAutomapFlag
    })
end

function UIMinimap:onDestroy()
    minimapsWithMarks[self] = nil
    if self.setSmoothWalk then
        self:setSmoothWalk(false)
    end
    if self.setHdMode then
        self:setHdMode(false, false)
    end
    if self._smoothZoomEvent then
        removeEvent(self._smoothZoomEvent)
        self._smoothZoomEvent = nil
    end
    self._smoothZoomTargetScale = nil

    disconnect(g_game, {
        onAddAutomapFlag = self.onAddAutomapFlag,
        onRemoveAutomapFlag = self.onRemoveAutomapFlag
    })
    self:destroyFlagWindow()
    self:closeDeleteAllMarksBox()
    self:clearPartyPins()
    self.flags = {}
    self.flagsByPosition = {}
end

function UIMinimap:onVisibilityChange()
    if not self:isVisible() then
        self:finishSmoothZoom(true)
        self:destroyFlagWindow()
        self:closeDeleteAllMarksBox()
    end
    self:updateNearbyPlayerPulse()
end

function UIMinimap:onCameraPositionChange(cameraPos, oldPosition)
    if not cameraPos or not oldPosition or cameraPos.z ~= oldPosition.z then
        self:refreshMarkVisibility()
    end
    self:updateCrossVisibility()
    self:updateAllPartyPinsVisibility()
end

function UIMinimap:isCyclopediaMap()
    local parent = self:getParent()
    return parent and parent:getId() == "MapBase"
end

local PARTY_PIN_MEMBER = '/game_cyclopedia/images/icon-map-player-yellow'
local PARTY_PIN_LEADER = '/game_cyclopedia/images/icon-map-player-red'
local NEARBY_PLAYER_MIN_ZOOM = 2
local PLAYER_PULSE_SIZE = 20

local function positionMarkerAtTile(minimap, marker, displayPos)
    local previous = marker.anchoredMapPosition
    if previous and previous.x == displayPos.x and previous.y == displayPos.y and previous.z == displayPos.z then
        return
    end
    marker.anchoredMapPosition = displayPos
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
    if pin.nearbyPlayer then
        pin:setVisible(cameraPos ~= nil and cameraPos.z == pin.pos.z
            and minimap:getZoom() >= NEARBY_PLAYER_MIN_ZOOM)
        return
    end

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

    local opacity = sameFloorAsView and 1 or (minimap:isCyclopediaMap() and 0.25 or 0.55)
    if pin:getOpacity() ~= opacity then
        pin:setOpacity(opacity)
    end

    pin:show()
    positionMarkerAtTile(minimap, pin, displayPos)
    updatePartyPinFloorLabel(minimap, pin, sameFloorAsPlayer and 0 or deltaZ)
end

function UIMinimap:updateCrossVisibility()
    updateMinimapMarkerVisibility(self, self.cross)
end

function UIMinimap:clearPartyPins()
    if self.nearbyPlayerPulseEvent then
        removeEvent(self.nearbyPlayerPulseEvent)
        self.nearbyPlayerPulseEvent = nil
    end

    if not self.partyPins then
        self.partyPins = {}
        return
    end

    for _, pin in pairs(self.partyPins) do
        if not pin:isDestroyed() then
            destroyPartyPinFloorLabel(pin)
            pin:destroy()
        end
    end

    self.partyPins = {}
end

function UIMinimap:updateNearbyPlayerPulse()
    local options = modules.client_options
    local animate = not options or not options.getOption('disableMinimapAnimations')
    local visible = g_game.isOnline() and not self:isDestroyed() and self:isVisible()
    local haloOpacity = 0
    local haloSize = PLAYER_PULSE_SIZE
    if visible and animate then
        local progress = (g_clock.millis() % 1200) / 1200
        haloSize = 12 + 2 * math.floor(progress * 4 + 0.5)
        haloOpacity = math.sin(math.pi * progress) ^ 0.65
    end

    local hasVisiblePins = false
    if visible and self.partyPins then
        for _, pin in pairs(self.partyPins) do
            if pin.nearbyPlayer and pin:isVisible() then
                hasVisiblePins = true
                local halo = pin.pulseHalo
                if haloOpacity > 0 and halo.pulseSize ~= haloSize then
                    local offset = (PLAYER_PULSE_SIZE - haloSize) / 2
                    halo:setImageRect({ x = offset, y = offset, width = haloSize, height = haloSize })
                    halo.pulseSize = haloSize
                end
                if math.abs(halo:getOpacity() - haloOpacity) > 0.01 then
                    halo:setOpacity(haloOpacity)
                end
            end
        end
    end

    if animate and hasVisiblePins then
        if not self.nearbyPlayerPulseEvent then
            self.nearbyPlayerPulseEvent = scheduleEvent(function()
                self.nearbyPlayerPulseEvent = nil
                self:updateNearbyPlayerPulse()
            end, 50)
        end
    elseif self.nearbyPlayerPulseEvent then
        removeEvent(self.nearbyPlayerPulseEvent)
        self.nearbyPlayerPulseEvent = nil
    end
end

function UIMinimap:updateAllPartyPinsVisibility()
    if not self.partyPins then
        return
    end

    for _, pin in pairs(self.partyPins) do
        updatePartyPinVisibility(self, pin)
    end
    self:updateNearbyPlayerPulse()
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
        if pin and pin.nearbyPlayer ~= data.nearbyPlayer then
            destroyPartyPinFloorLabel(pin)
            pin:destroy()
            pin = nil
        end

        if not pin then
            pin = g_ui.createWidget(data.nearbyPlayer and 'MinimapNearbyPlayerPin' or 'MinimapCross', self)
            pin:setId('partyPin_' .. id)
            pin.nearbyPlayer = data.nearbyPlayer
            if not data.nearbyPlayer then
                pin:setImageSource('')
                pin:setClipping(false)
                pin:setPhantom(false)
                pin:setFocusable(false)
            end
            self.partyPins[id] = pin
        end

        if data.nearbyPlayer then
            local old = pin.pos
            if not old or old.x ~= pos.x or old.y ~= pos.y or old.z ~= pos.z then
                self:centerInPosition(pin, pos)
            end
        else
            pin:setIcon(pinIcon)
            pin:setIconColor('#ffffff')
        end

        pin.pos = {
            x = pos.x,
            y = pos.y,
            z = pos.z
        }
        pin:setTooltip(data.tooltip or data.name or (data.nearbyPlayer and tr('Player') or tr('Party member')))
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

function UIMinimap:finishSmoothZoom(resetHover)
    local targetScale = self._smoothZoomTargetScale
    if resetHover and (self.minimapHoverZoom or self.markHoverZoomHeld) then
        self.minimapHoverZoom = false
        self.markHoverZoomHeld = nil
        targetScale = 2 ^ self:getZoom()
    end

    if self._smoothZoomEvent then
        removeEvent(self._smoothZoomEvent)
        self._smoothZoomEvent = nil
        if self.setZoomAnimating then
            self:setZoomAnimating(false)
        end
    end

    self._smoothZoomTargetScale = nil
    self._smoothZoomFromHover = nil
    if targetScale then
        self:setScale(targetScale)
        if self.onSmoothZoomScaleChange then
            self:onSmoothZoomScaleChange(self:getScale())
        end
    end
end

local MINIMAP_HOVER_SCALE = 1.10

function UIMinimap:setMinimapHoverZoom(hovered)
    if not self.setScale or not self:isVisible() then
        return
    end
    if not hovered then
        local target = g_ui.getRootWidget():recursiveGetChildByPos(g_window.getMousePosition(), false)
        if target and target.isMapMark and target:getParent() == self then
            self.markHoverZoomHeld = true
            if self._smoothZoomFromHover then
                self._smoothZoomTargetScale = nil
                self:finishSmoothZoom()
            end
            return
        end
        hovered = target == self
    end

    local wasHeld = self.markHoverZoomHeld
    self.markHoverZoomHeld = nil
    if not wasHeld and (self.minimapHoverZoom == true) == hovered then
        return
    end
    if hovered then
        local options = modules.client_options
        if (self.fullMapView and not self:isCyclopediaMap())
            or (options and options.getOption and options.getOption('disableMinimapHoverZoom')) then
            return
        end
    end

    self.minimapHoverZoom = hovered
    local scale = 2 ^ self:getZoom()
    self:startSmoothZoom(hovered and scale * MINIMAP_HOVER_SCALE or scale, true)
end

function UIMinimap:applyMinimapPreferences()
    local options = modules.client_options
    if not options or not options.getOption then
        return
    end

    if self.setHdAnimations then
        self:setHdAnimations(not options.getOption('disableMinimapAnimations'))
    end
    if self.setShowFloorItems then
        self:setShowFloorItems(not options.getOption('disableMinimapFloorItems'))
    end
    self:updateNearbyPlayerPulse()
    if (self.minimapHoverZoom or self.markHoverZoomHeld) and options.getOption('disableMinimapHoverZoom') then
        self:finishSmoothZoom(true)
    elseif options.getOption('disableMinimapSmoothZoom') then
        self:finishSmoothZoom()
    end
end

function UIMinimap:smoothZoomBy(step)
    if step == 0 then
        return false
    end
    if not self.setScale then
        return step > 0 and self:zoomIn() or self:zoomOut()
    end

    local targetZoom = self:getZoom() + step
    if targetZoom < self:getMinZoom() or targetZoom > self:getMaxZoom() then
        return false
    end

    local options = modules.client_options
    if options and options.getOption and options.getOption('disableMinimapSmoothZoom') then
        self:finishSmoothZoom()
        if not self:setZoom(targetZoom) then
            return false
        end
        if self.onSmoothZoomScaleChange then
            self:onSmoothZoomScaleChange(self:getScale())
        end
        return true
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

    self:startSmoothZoom(targetScale)
    return true
end

function UIMinimap:startSmoothZoom(targetScale, fromHover)
    if self._smoothZoomEvent then
        self._smoothZoomFromHover = fromHover
        self._smoothZoomTargetScale = targetScale
        return
    end
    if self:getScale() == targetScale then
        return
    end

    self._smoothZoomTargetScale = targetScale
    self._smoothZoomFromHover = fromHover
    if self.setZoomAnimating then
        self:setZoomAnimating(true)
    end
    local lastUpdate = g_clock.millis()
    local frameInterval = 16
    local responseTime = 52

    local function animate()
        if self:isDestroyed() or not self._smoothZoomTargetScale then
            self._smoothZoomEvent = nil
            return
        end

        local now = g_clock.millis()
        local remaining = math.exp(-(now - lastUpdate) / responseTime)
        lastUpdate = now
        local currentScale = self:getScale()
        local targetScale = self._smoothZoomTargetScale
        local delta = math.log(targetScale / currentScale)
        if math.abs(delta * remaining) > 0.003 then
            self:setScale(targetScale * math.exp(-delta * remaining))
            self._smoothZoomEvent = scheduleEvent(animate, frameInterval)
        else
            self:setScale(targetScale)
            self._smoothZoomEvent = nil
            self._smoothZoomTargetScale = nil
            self._smoothZoomFromHover = nil
            if self.setZoomAnimating then
                self:setZoomAnimating(false)
            end
        end

        if self.onSmoothZoomScaleChange then
            self:onSmoothZoomScaleChange(self:getScale())
        end
    end

    self._smoothZoomEvent = scheduleEvent(animate, frameInterval)
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
    self:finishSmoothZoom(true)
    local settings = g_settings.getNode('Minimap')
    if settings then
        if settings.flags then
            for _, flag in pairs(settings.flags) do
                self:addFlag(flag.position, flag.icon, flag.description, false, flag.mapText, flag.textColor)
            end
        end
        self.zoomFullmap = settings.zoomFull or self.zoomMinimap
    end
    self:setZoom(self.zoomMinimap)
end

function UIMinimap:save(keepFullscreenZoom)
    local settings = g_settings.getNode('Minimap') or {}
    settings.flags = {}
    for _, flag in pairs(self.flags) do
        if not flag.temporary then
            table.insert(settings.flags, {
                position = flag.pos,
                icon = flag.icon,
                description = flag.description,
                mapText = flag.mapText,
                textColor = flag.textColor
            })
        end
    end
    if not keepFullscreenZoom then
        settings.zoomFull = self.zoomFullmap
    end
    g_settings.setNode('Minimap', settings)
end

local function changeUserMark(source, pos, icon, description, mapText, textColor, creating)
    for minimap in pairs(minimapsWithMarks) do
        local flag = minimap:getFlag(pos)
        if not icon then
            if flag and not flag.temporary then
                flag:destroy()
            end
        elseif flag then
            if not creating and not flag.temporary then
                minimap:updateFlag(flag, icon, description, mapText, textColor)
            end
        else
            minimap:addFlag(pos, icon, description, false, mapText, textColor)
        end
        notifyMarksChanged(minimap)
    end
    source:save(true)
end

local function cancelFlagHoverEvent(flag)
    if flag.hoverEvent then
        removeEvent(flag.hoverEvent)
        flag.hoverEvent = nil
    end
end

local function setFlagHoverSize(flag, size)
    if flag.hoverSize == size then
        return
    end
    flag.hoverSize = size
    local iconSize = math.floor(size + 0.5)
    if flag.hoverIconSize ~= iconSize then
        flag.hoverIconSize = iconSize
        local offset = -math.floor((iconSize - 11) / 2)
        flag:setClipping(iconSize == 11)
        flag:setIconRect({x = offset, y = offset, width = iconSize, height = iconSize})
        if flag.mapLabel then
            flag.mapLabel:setFontScale(1 + (iconSize - 11) / 24)
        end
    end
end

local function animateFlagHover(flag, hovered)
    cancelFlagHoverEvent(flag)
    if not flag:isVisible() then
        setFlagHoverSize(flag, 11)
        return
    end

    local initialSize = flag.hoverSize or 11
    local targetSize = hovered and 17 or 11
    if initialSize == targetSize then
        return
    end

    local started = g_clock.millis()
    local function animate()
        flag.hoverEvent = nil
        if not flag:isVisible() then
            setFlagHoverSize(flag, 11)
            return
        end
        local progress = math.min((g_clock.millis() - started) / 120, 1)
        local eased = 1 - (1 - progress) ^ 3
        local size = initialSize + (targetSize - initialSize) * eased
        setFlagHoverSize(flag, size)
        if progress < 1 then
            flag.hoverEvent = scheduleEvent(animate, 16)
        end
    end
    animate()
end

local function onFlagHoverChange(flag, hovered)
    if flag:isDestroyed() then
        return
    end
    local minimap = flag:getParent()
    if minimap then
        minimap:setMinimapHoverZoom(false)
    end
    animateFlagHover(flag, hovered)
end

function UIMinimap:closeDeleteAllMarksBox()
    local box = self.deleteAllMarksBox
    if box then
        self.deleteAllMarksBox = nil
        if not box:isDestroyed() then
            box:destroy()
        end
    end
end

function UIMinimap:confirmDeleteAllMarks()
    if self.deleteAllMarksBox then
        return
    end

    local function cancel()
        self:closeDeleteAllMarksBox()
    end
    local function confirm()
        self:closeDeleteAllMarksBox()
        for minimap in pairs(minimapsWithMarks) do
            for i = #minimap.flags, 1, -1 do
                local flag = minimap.flags[i]
                if not flag.temporary then
                    flag:destroy()
                end
            end
            notifyMarksChanged(minimap)
        end
        self:save(true)
    end

    self.deleteAllMarksBox = displayGeneralBox(tr('Delete All Marks'),
        tr('Are you sure you want to delete all saved marks on every floor?'), {
            { text = tr('Cancel'), callback = cancel },
            { text = tr('Delete'), callback = confirm }
        }, nil, cancel)
end

local function showFlagContextMenu(minimap, flag, mousePos, mapPos)
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    if flag then
        menu:addOption(tr('Edit Mark'), function()
            if not flag:isDestroyed() then
                minimap:createFlagWindow(flag.pos, flag)
            end
        end)
        menu:addOption(tr('Delete Mark'), function()
            if flag:isDestroyed() then
                return
            end
            if flag.temporary then
                flag:destroy()
                notifyMarksChanged(minimap)
            else
                changeUserMark(minimap, flag.pos)
            end
        end)
    else
        menu:addOption(tr('Create mark'), function()
            minimap:createFlagWindow(mapPos, minimap:getFlag(mapPos))
        end)
    end

    menu:addSeparator()
    menu:addOption(tr('Delete All Marks'), function()
        if not minimap:isDestroyed() and minimap:isVisible() then
            minimap:confirmDeleteAllMarks()
        end
    end)
    menu:display(mousePos)
end

local function onFlagMouseRelease(widget, pos, button)
    local minimap = widget:getParent()
    if button == MouseRightButton then
        showFlagContextMenu(minimap, widget, pos)
        return true
    end
    if button ~= MouseLeftButton then
        return false
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return false
    end
    if Position.distance(player:getPosition(), widget.pos) > 250 then
        modules.game_textmessage.displayStatusMessage(tr('Destination is out of range.'))
        return false
    end
    if minimap.autowalk then
        if modules.game_walk then
            modules.game_walk.stopChasingWhenMoving()
        end
        player:autoWalk(widget.pos)
    end
    return true
end

function UIMinimap:setCrossPosition(pos)
    local cross = self.cross
    if not self.cross then
        cross = g_ui.createWidget('MinimapCross', self)
        cross:setId('minimapPlayerCross')
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

function UIMinimap:addFlag(pos, icon, description, temporary, mapText, textColor)
    if not pos or not icon then
        return
    end
    local key = markPositionKey(pos)
    if self.flagsByPosition[key] then
        return
    end

    local flag = g_ui.createWidget('MinimapFlag')
    self:insertChild(1, flag)
    flag.pos = pos
    flag.temporary = temporary or false
    flag.isMapMark = true
    flag.onMouseRelease = onFlagMouseRelease
    flag.onHoverChange = onFlagHoverChange
    flag.onDestroy = function()
        cancelFlagHoverEvent(flag)
        if flag.mapLabel and not flag.mapLabel:isDestroyed() then
            flag.mapLabel:destroy()
        end
        flag.mapLabel = nil
        self.flagsByPosition[key] = nil
        local lastIndex = #self.flags
        local lastFlag = self.flags[lastIndex]
        if lastFlag ~= flag then
            self.flags[flag.markIndex] = lastFlag
            lastFlag.markIndex = flag.markIndex
        end
        self.flags[lastIndex] = nil
    end
    flag.markIndex = #self.flags + 1
    self.flags[flag.markIndex] = flag
    self.flagsByPosition[key] = flag
    self:centerInPosition(flag, pos)
    self:updateFlag(flag, icon, description, mapText, textColor)
end

function UIMinimap:updateFlag(flag, icon, description, mapText, textColor)
    if not flag then return end
    flag.icon = tonumber(icon) or icon
    flag.description = description or ''
    flag.mapText = mapText or ''
    flag.textColor = textColor or markTextColors[1][2]
    if type(flag.icon) == 'number' then
        flag:setIcon('/images/game/minimap/flag' .. flag.icon)
    else
        flag:setIcon(resolvepath(icon, 1))
    end
    local name = self:getMarkName(flag.icon)
    local tooltip = tr('Mark') .. ': ' .. name
    if flag.description ~= '' then
        tooltip = tooltip .. '\n' .. flag.description
    end
    flag:setTooltip(tooltip)
    flag.searchLabel = normalizeMarkSearch(flag.mapText)
    flag.searchDescription = normalizeMarkSearch(flag.description)
    flag.searchName = normalizeMarkSearch(name)
    flag.searchOriginalName = normalizeMarkSearch(markNames[flag.icon] or 'Custom')
    flag.searchText = table.concat({flag.searchLabel, flag.searchDescription, flag.searchName, flag.searchOriginalName}, '\n')
    flag.lastSearchQuery = nil

    local label = flag.mapLabel
    if flag.mapText ~= '' then
        if not label then
            label = g_ui.createWidget('MinimapMarkText')
            self:insertChild(1, label)
            self:anchorPosition(label, AnchorLeft, flag.pos, AnchorHorizontalCenter)
            self:anchorPosition(label, AnchorVerticalCenter, flag.pos, AnchorVerticalCenter)
            flag.mapLabel = label
            label.isMapMark = true
            label.onHoverChange = function(_, hovered)
                onFlagHoverChange(flag, hovered)
            end
            label.onMouseRelease = function(_, mousePos, button)
                return onFlagMouseRelease(flag, mousePos, button)
            end
        end
        label:setTooltip(tooltip)
        label:setFontScale(1 + ((flag.hoverIconSize or 11) - 11) / 24)
        label:setColor(flag.textColor)
        label:setText(flag.mapText)
    elseif label then
        label:destroy()
        flag.mapLabel = nil
    end
    self:updateMarkVisibility(flag, self:getCameraPosition())
end

function UIMinimap:getMarkMatchRank(flag)
    local query = self.markSearch
    if flag.lastSearchQuery ~= query then
        flag.lastSearchQuery = query
        flag.searchRank = nil
        if query ~= '' then
            if flag.searchLabel == query then
                flag.searchRank = 0
            elseif flag.searchDescription == query or flag.searchName == query or flag.searchOriginalName == query then
                flag.searchRank = 1
            elseif flag.searchText:find(query, 1, true) then
                flag.searchRank = 2
            end
        end
    end
    return flag.searchRank
end

function UIMinimap:updateMarkVisibility(flag, cameraPos)
    local matches
    if self.markSearch ~= '' then
        -- Searches include every icon type. The icon filter resumes when cleared.
        matches = self:getMarkMatchRank(flag) ~= nil
    else
        matches = not self.enabledMarkIcons or self.enabledMarkIcons[flag.icon] == true
    end
    local visible = cameraPos ~= nil and flag.pos.z == cameraPos.z and matches
    flag:setVisible(visible)
    if not visible and flag.hoverSize then
        cancelFlagHoverEvent(flag)
        setFlagHoverSize(flag, 11)
    end
    if flag.mapLabel then
        flag.mapLabel:setVisible(visible)
    end
end

function UIMinimap:refreshMarkVisibility()
    if not self.flags then
        return
    end
    local cameraPos = self:getCameraPosition()
    for _, flag in ipairs(self.flags) do
        self:updateMarkVisibility(flag, cameraPos)
    end
end

function UIMinimap:setMarkSearch(text)
    local query = normalizeMarkSearch(text)
    if self.markSearch ~= query then
        self.markSearch = query
        self:refreshMarkVisibility()
    end
end

function UIMinimap:setMarkIconFilter(enabledIcons)
    self.enabledMarkIcons = enabledIcons
    if self.markSearch == '' then
        self:refreshMarkVisibility()
    end
end

function UIMinimap:onZoomChange(zoom)
    if self.minimapHoverZoom then
        self:setScale((2 ^ zoom) * MINIMAP_HOVER_SCALE)
    end
    if self._smoothZoomEvent then
        self._smoothZoomTargetScale = self:getScale()
    end

    if self.fullMapView then
        self.zoomFullmap = zoom
    else
        self.zoomMinimap = zoom
    end

    self:updateAllPartyPinsVisibility()
end

function UIMinimap:getFlag(pos)
    return pos and self.flagsByPosition[markPositionKey(pos)]
end

function UIMinimap:removeFlag(pos)
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
        self:smoothZoomBy(1)
        return true
    elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
        self:smoothZoomBy(-1)
        return true
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
            if modules.game_walk then
                modules.game_walk.stopChasingWhenMoving()
            end
            player:autoWalk(mapPos)
        end
        return true
    elseif button == MouseRightButton then
        showFlagContextMenu(self, self:getFlag(mapPos), pos, mapPos)
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
    if self.panByPixels then
        self:panByPixels(pos.x - self.dragReference.x, pos.y - self.dragReference.y)
        self.dragReference = pos
        return true
    end

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
    local mapText = self.flagWindow:getChildById('mapText')
    mapText:setMaxLength(markInputUsesUtf8 and MARK_TEXT_LIMIT * 4 or MARK_TEXT_LIMIT)
    mapText.onTextChange = updateMapTextCount
    mapText.onDestroy = function(field)
        if field.limitMarkTextEvent then
            removeEvent(field.limitMarkTextEvent)
        end
    end
    local palette = self.flagWindow:getChildById('textColorPalette')
    local okButton = self.flagWindow:getChildById('okButton')
    local cancelButton = self.flagWindow:getChildById('cancelButton')

    local flagRadioGroup = UIRadioGroup.create()
    for i = 0, 19 do
        local flagButton = self.flagWindow:getChildById('flag' .. i)
        flagButton.icon = i
        flagRadioGroup:addWidget(flagButton)
        flagButton:setTooltip(tr('Mark') .. ': ' .. self:getMarkName(i))
    end

    local colorRadioGroup = UIRadioGroup.create()
    local selectedColor
    for _, color in ipairs(markTextColors) do
        local swatch = g_ui.createWidget('MinimapMarkColorSwatch', palette)
        swatch.textColor = color[2]
        swatch:getChildById('sample'):setBackgroundColor(color[2])
        swatch:setTooltip(tr(color[1]))
        colorRadioGroup:addWidget(swatch)
        if existingFlag and existingFlag.textColor == color[2] then
            selectedColor = swatch
        end
    end
    colorRadioGroup:selectWidget(selectedColor or colorRadioGroup:getFirstWidget(), true)
    flagRadioGroup:selectWidget(flagRadioGroup:getFirstWidget(), true)
    if existingFlag then
        description:setText(existingFlag.description or '')
        mapText:setText(existingFlag.mapText or '')
        local icon = tonumber(existingFlag.icon)
        if icon then
            local flagButton = self.flagWindow:getChildById('flag' .. icon)
            if flagButton then
                flagRadioGroup:selectWidget(flagButton, true)
            end
        end
    end

    local successFunc = function()
        if not existingFlag and self:getFlag(pos) then
            self:destroyFlagWindow()
            displayInfoBox(tr('Create Mark'), tr('This position already has a mark. Use Edit Mark to change it.'))
            return
        end
        if not existingFlag or not existingFlag:isDestroyed() then
            local icon = flagRadioGroup:getSelectedWidget().icon
            local text = description:getText()
            local label = limitMapText(mapText:getText():trim())
            local color = colorRadioGroup:getSelectedWidget().textColor
            if existingFlag and existingFlag.temporary then
                self:updateFlag(existingFlag, icon, text, label, color)
                notifyMarksChanged(self)
            else
                changeUserMark(self, pos, icon, text, label, color, not existingFlag)
                if self.onUserMarkChange then
                    self:onUserMarkChange(icon)
                end
            end
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
        self.flagWindow = nil
        flagRadioGroup:destroy()
        colorRadioGroup:destroy()
    end
end

function UIMinimap:destroyFlagWindow()
    if self.flagWindow then
        self.flagWindow:destroy()
    end
end
