local iconTopMenu = nil
-- Exported for OTCv8/vBot cavebot (modules.game_minimap.minimapWidget)
minimapWidget = nil
local MINIMAP_FILE = '/minimap.otmm'
local oldPos = nil
local fullscreenWidget
local pendingCreaturePinRefresh
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

local function updateSidebarCameraControls(widget)
    local freeView = widget:getChildById('freeViewButton')
    local center = widget:getChildById('centerMapButton')
    local player = g_game.getLocalPlayer()
    local position = player and player:getPosition()
    local camera = widget:getCameraPosition()
    local show = g_game.isOnline() and not widget.fullMapView and position ~= nil

    freeView:setVisible(show)
    freeView:setOn(widget.sidebarFreeView == true)
    center:setVisible(show and camera ~= nil and (widget.sidebarCameraHasPixelOffset == true
        or camera.x ~= position.x or camera.y ~= position.y or camera.z ~= position.z))
    freeView:raise()
    center:raise()
end

local function updateSidebarCamera(forceCenter)
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

    local widget = ui.minimapBorder.minimap
    if not widget or widget:isDestroyed() then
        return
    end

    if forceCenter or (not widget.sidebarFreeView and not widget:isDragging() and not widget.fullMapView) then
        widget.sidebarCameraHasPixelOffset = false
        widget:setCameraPosition(pos)
    end

    widget:setCrossPosition(pos)
    virtualFloor = widget:getCameraPosition().z
    refreshVirtualFloors()
    queueMinimapPartyPinsRefresh()
    updateSidebarCameraControls(widget)
end

local function onPositionChange()
    updateSidebarCamera(false)
end

function centerMinimapOnPlayer()
    updateSidebarCamera(true)
end

function toggleMinimapFreeView()
    local widget = minimapWidget
    if not widget or widget:isDestroyed() or widget.fullMapView or not g_game.isOnline() then
        return
    end

    widget.sidebarFreeView = not widget.sidebarFreeView
    if widget.setSmoothWalk then
        widget:setSmoothWalk(not widget.sidebarFreeView)
    end
    updateSidebarCamera(not widget.sidebarFreeView)
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

local function getPartyVitalsCache()
    if modules.game_party and modules.game_party.getPartyVitalsCacheTable then
        return modules.game_party.getPartyVitalsCacheTable()
    end

    return PartyVitalsCache
end

local function isLocalPlayerInParty(localPlayer)
    if not localPlayer then
        return false
    end

    if localPlayer.isPartyMember and localPlayer:isPartyMember() then
        return true
    end

    if not CreatureList or not CreatureList.isConfirmedPartyMemberShield then
        return false
    end

    local shield = localPlayer:getShield()

    return CreatureList.isConfirmedPartyMemberShield(shield)
        or CreatureList.isPartyLeaderShield(shield)
end

local function collectMinimapPartyMembers()
    local memberById = {}

    if not g_game.isOnline() or not CreatureList then
        return memberById
    end

    local localPlayer = g_game.getLocalPlayer()
    if not isLocalPlayerInParty(localPlayer) then
        return memberById
    end

    local localId = localPlayer:getId()
    local localIsPartyLeader = localPlayer.isPartyLeader and localPlayer:isPartyLeader()
    local vitalsCache = getPartyVitalsCache()

    local function addPartyPin(creatureId, creature, cached)
        if not creatureId or creatureId == localId then
            return
        end

        local pos

        if creature and not creature:isRemoved() then
            pos = creature:getPosition()
        end

        if not pos and cached and cached.pos then
            pos = cached.pos
        end

        if not pos then
            return
        end

        local isRemoteLeader = cached and cached.isLeader

        if creature and CreatureList.isRemotePartyMember(creature) then
            isRemoteLeader = CreatureList.isRemotePartyLeader(creature)
        end

        local showAsLeader = isRemoteLeader and not localIsPartyLeader
        local pinIcon = showAsLeader
            and '/game_cyclopedia/images/icon-map-player-red'
            or '/game_cyclopedia/images/icon-map-player-yellow'

        local tooltip

        if creature and CreatureList.isRemotePartyMember(creature) then
            tooltip = CreatureList.buildPartyMemberPinTooltip(creature)
        else
            tooltip = CreatureList.buildPartyMemberPinTooltipFromCache(creatureId)
        end

        memberById[creatureId] = {
            name = (creature and creature:getName()) or (cached and cached.name),
            pinIcon = pinIcon,
            tooltip = tooltip,
            pos = {
                x = pos.x,
                y = pos.y,
                z = pos.z
            }
        }
    end

    if vitalsCache then
        for creatureId, cached in pairs(vitalsCache) do
            addPartyPin(creatureId, g_map.getCreatureById(creatureId), cached)
        end
    end

    local mapPanel = modules.game_interface.getMapPanel()

    if mapPanel then
        for _, creature in ipairs(mapPanel:getSpectators()) do
            if CreatureList.isRemotePartyMember(creature) then
                if PartyListRegistry then
                    PartyListRegistry:add(creature)
                end

                addPartyPin(creature:getId(), creature, vitalsCache and vitalsCache[creature:getId()])
            end
        end
    end

    if PartyListRegistry and PartyListRegistry.byId then
        for id, creature in pairs(PartyListRegistry.byId) do
            if creature and not creature:isRemoved() and CreatureList.isRemotePartyMember(creature) then
                if not memberById[id] then
                    addPartyPin(id, creature, vitalsCache and vitalsCache[id])
                end
            else
                PartyListRegistry.byId[id] = nil
            end
        end
    end

    return memberById
end

local function foreachMinimapWidget(callback)
    local ui = mapController and mapController.ui
    if not ui or ui:isDestroyed() or not callback then
        return
    end

    for _, useHorizontal in ipairs({ false, true }) do
        local border = getLayoutWidget(getLayoutRoot(ui, useHorizontal), 'minimapBorder')
        local mini = border and border:getChildById('minimap')
        if mini and not mini:isDestroyed() then
            callback(mini)
        end
    end
end

local function showNearbyPlayers()
    local options = modules.client_options
    return not options or options.getOption('showNearbyMinimapPlayers')
end

local function collectNearbyPlayerPins(pins)
    local localPlayer = g_game.getLocalPlayer()
    local mapPanel = modules.game_interface.getMapPanel()
    local playerPos = localPlayer and localPlayer:getPosition()
    if not showNearbyPlayers() or not playerPos or not mapPanel then
        return
    end

    local options = modules.client_options
    local limit = options and options.getOption('nearbyMinimapPlayerLimit') or 8
    limit = math.max(2, math.min(40, math.floor(limit)))
    local candidates = {}
    for _, creature in ipairs(mapPanel:getSightSpectators(false)) do
        if creature:isPlayer() and not creature:isLocalPlayer() and not creature:isRemoved()
            and not creature:isInvisible() then
            local id = creature:getId()
            local pos = creature:getPosition()
            if not pins[id] and pos and pos.z == playerPos.z then
                local dx, dy = pos.x - playerPos.x, pos.y - playerPos.y
                candidates[#candidates + 1] = { id = id, creature = creature, pos = pos, distance = dx * dx + dy * dy }
            end
        end
    end

    if #candidates > limit then
        table.sort(candidates, function(a, b)
            return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
        end)
    end
    for i = 1, math.min(limit, #candidates) do
        local candidate = candidates[i]
        pins[candidate.id] = { nearbyPlayer = true, name = candidate.creature:getName(), pos = candidate.pos }
    end
end

function refreshMinimapPartyPins()
    local pins = {}
    if g_game.isOnline() then
        pins = collectMinimapPartyMembers()
        collectNearbyPlayerPins(pins)
    end

    local function applyPins(mini)
        if mini and not mini:isDestroyed() and mini.updatePartyPins then
            mini:updatePartyPins(pins)
        end
    end

    foreachMinimapWidget(applyPins)

    local cyclopediaMini

    if modules.game_cyclopedia then
        if modules.game_cyclopedia.getMapMinimapWidget then
            cyclopediaMini = modules.game_cyclopedia.getMapMinimapWidget()
        elseif modules.game_cyclopedia.Cyclopedia and modules.game_cyclopedia.Cyclopedia.getMapMinimapWidget then
            cyclopediaMini = modules.game_cyclopedia.Cyclopedia.getMapMinimapWidget()
        end
    end

    applyPins(cyclopediaMini)
end

local function creatureHasPartyPin(creatureId)
    if not creatureId then
        return false
    end

    local found = false

    foreachMinimapWidget(function(mini)
        if mini.partyPins and mini.partyPins[creatureId] then
            found = true
        end
    end)

    return found
end

function queueMinimapPartyPinsRefresh()
    if not pendingCreaturePinRefresh and g_game.isOnline() then
        pendingCreaturePinRefresh = addEvent(function()
            pendingCreaturePinRefresh = nil
            refreshMinimapPartyPins()
        end)
    end
end

local function onMinimapCreatureEvent(creature)
    if not creature or creature:isLocalPlayer() or not creature:isPlayer() then
        return
    end

    if not showNearbyPlayers() and CreatureList and not CreatureList.isRemotePartyMember(creature)
        and not creatureHasPartyPin(creature:getId()) then
        return
    end

    queueMinimapPartyPinsRefresh()
end

local function onPartyMinimapShieldEvent(creature)
    if not creature or creature:isLocalPlayer() or not creature:isPlayer() then
        return
    end

    queueMinimapPartyPinsRefresh()
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

function refreshMinimapFogOfWar()
    local widget = fullscreenWidget or minimapWidget
    if not widget or widget:isDestroyed() then
        return
    end

    local enabled = g_settings.getBoolean('minimapFogOfWar', true)
    local supported = widget.setFogOfWar ~= nil
    local button = widget:getChildById('fogOfWarButton')
    if button then
        button:setVisible(supported and not widget.fullMapView)
        button:setOn(supported and enabled)
        button:raise()
    end
    if supported then
        widget:setFogOfWar(enabled)
    end
end

function toggleMinimapFogOfWar()
    g_settings.set('minimapFogOfWar', not g_settings.getBoolean('minimapFogOfWar', true))
    refreshMinimapFogOfWar()
    local cyclopedia = modules.game_cyclopedia
    if cyclopedia and cyclopedia.refreshMapFogOfWar then
        cyclopedia.refreshMapFogOfWar()
    end
end

local function isHdMapInstalled(options)
    if options and options.isMinimapHdMapInstalled then
        return options.isMinimapHdMapInstalled()
    end
    return g_resources.fileExists('/data/minimap_hd/index.txt')
end

local function applyMinimapHd(widget, enabled)
    if not widget or widget:isDestroyed() then
        return
    end

    widget:applyMinimapPreferences()
    refreshMinimapFogOfWar()
    local options = modules.client_options
    local hdDisabled = options and options.getOption('disableMinimapHd')
    enabled = enabled and not hdDisabled and isHdMapInstalled(options)
    local supported = widget.setHdMode ~= nil
    local button = widget:getChildById('hdButton')
    if button then
        button:setEnabled(supported and not hdDisabled)
        button:setOn(supported and enabled)
        if hdDisabled then
            button:setTooltip(tr('HD map is disabled in Minimap settings'))
        else
            button:setTooltip(supported and tr('Toggle HD minimap') or tr('HD minimap requires the updated client'))
        end
        button:raise()
    end
    if supported then
        widget:setHdMode(enabled, not widget.fullMapView)
    end
end

function refreshMinimapPreferences()
    applyMinimapHd(fullscreenWidget or minimapWidget, g_game.isOnline() and g_settings.getBoolean('minimapHd', true))
    refreshMinimapDownloadOverlay()
end

local function stopDownloadHourglass(panel)
    if panel.hourglassEvent then
        removeEvent(panel.hourglassEvent)
        panel.hourglassEvent = nil
    end
    if not panel:isDestroyed() then
        panel.hourglass:setRotation(0)
    end
end

local function animateDownloadHourglass(panel)
    if panel.hourglassEvent then
        return
    end

    local startedAt = g_clock.millis()
    panel.hourglassEvent = cycleEvent(function()
        if panel:isDestroyed() or not panel:isVisible() then
            stopDownloadHourglass(panel)
            return
        end
        local elapsed = g_clock.millis() - startedAt
        local cycle = math.floor(elapsed / 1600)
        local turn = math.min(math.max((elapsed % 1600 - 1200) / 400, 0), 1)
        local eased = turn * turn * (3 - 2 * turn)
        local angle = (cycle % 2 + eased) * 180 % 360
        if panel.hourglass:getRotation() ~= angle then
            panel.hourglass:setRotation(angle)
        end
    end, 25)
end

function refreshMapDownloadOverlay(widget, offline)
    if not widget or widget:isDestroyed() then
        return
    end
    local button = widget:getChildById('downloadPackButton')
    local panel = widget:getChildById('downloadPackProgress')
    if not button or not panel then
        return
    end

    local options = modules.client_options
    local hd, animations
    if options and options.getMinimapPackDownloadState then
        hd, animations = options.getMinimapPackDownloadState()
    end
    local active = hd == 'downloading' or hd == 'canceling'
        or animations == 'downloading' or animations == 'canceling'
    local showOverlay = not offline and hd ~= nil and animations ~= nil and g_game.isOnline()
        and not widget.fullMapView and not options.getOption('disableMinimapHd')
    panel:setVisible(showOverlay and active)
    button:setVisible(showOverlay and not active and (hd ~= 'installed' or animations ~= 'installed'))
    if showOverlay and active then
        animateDownloadHourglass(panel)
    elseif panel.hourglassEvent then
        stopDownloadHourglass(panel)
    end
    if not showOverlay then
        return
    end

    if active then
        local percent = g_minimap.getPackDownloadProgress()
        local canceling = hd == 'canceling' or animations == 'canceling'
        panel.progressBar:setPercent(percent)
        panel.progressText:setText(canceling and tr('Canceling...') or tr('%d%%', percent))
        panel:raise()
    elseif hd ~= 'installed' or animations ~= 'installed' then
        local downloadAnimations = hd == 'installed'
        button:setFont(downloadAnimations and 'Verdana-8px' or 'Verdana Bold-10px')
        button:setText(downloadAnimations and tr('Download Map Animation') or tr('Download Map HD'))
        button:raise()
    end
end

function refreshMinimapDownloadOverlay(offline)
    refreshMapDownloadOverlay(minimapWidget, offline)
end

function downloadMinimapPack()
    local options = modules.client_options
    if not options or not options.getMinimapPackDownloadState then
        return
    end
    local hd, animations = options.getMinimapPackDownloadState()
    if hd == nil or animations == nil then
        return
    end
    local status = hd ~= 'installed' and hd or animations
    if status ~= 'installed' and status ~= 'downloading' and status ~= 'canceling' then
        options.toggleMinimapPackDownload(hd == 'installed')
    end
end

function toggleMinimapHd()
    local widget = fullscreenWidget or minimapWidget
    if not widget or not widget.setHdMode or not g_game.isOnline() then
        return
    end
    local options = modules.client_options
    if options and options.getOption('disableMinimapHd') then
        return
    end

    if not isHdMapInstalled(options) then
        if options and options.showMinimapOptions then
            options.showMinimapOptions()
        end
        displayInfoBox(tr('HD Map'), tr('You need to download the HD map to use this feature.'))
        return
    end

    local enabled = not g_settings.getBoolean('minimapHd', true)
    g_settings.set('minimapHd', enabled)
    applyMinimapHd(widget, enabled)
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

local function resolveMinimapSide(container)
    local current = container
    while current do
        local id = current.getId and current:getId() or nil
        if id == 'gameLeftTopPanel' or id == 'gameLeftPanel' or id == 'gameLeftExtraPanel' then
            return 'left'
        elseif id == 'gameRightTopPanel' or id == 'gameRightPanel' or id == 'gameRightExtraPanel' then
            return 'right'
        end
        current = current.getParent and current:getParent() or nil
    end
    return 'right'
end

local function positionMinimapHdButton(widget, side)
    local button = widget and widget:getChildById('hdButton')
    if not button then
        return
    end

    button:breakAnchors()
    button:setMargin(3)
    local horizontalEdge = AnchorRight
    if side == 'right' and not widget.fullMapView then
        horizontalEdge = AnchorLeft
        button:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        button:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    else
        button:addAnchor(AnchorRight, 'parent', AnchorRight)
        local verticalEdge = widget.fullMapView and AnchorTop or AnchorBottom
        button:addAnchor(verticalEdge, 'parent', verticalEdge)
    end

    local freeView = widget:getChildById('freeViewButton')
    local center = widget:getChildById('centerMapButton')
    local fog = widget:getChildById('fogOfWarButton')
    if fog then
        fog:breakAnchors()
        fog:addAnchor(horizontalEdge, 'hdButton', horizontalEdge)
        fog:addAnchor(AnchorBottom, 'hdButton', AnchorTop)
    end
    freeView:breakAnchors()
    freeView:addAnchor(horizontalEdge, 'hdButton', horizontalEdge)
    local belowFreeView = fog and widget.setFogOfWar and 'fogOfWarButton' or 'hdButton'
    freeView:addAnchor(AnchorBottom, belowFreeView, AnchorTop)
    center:breakAnchors()
    center:addAnchor(horizontalEdge, 'freeViewButton', horizontalEdge)
    center:addAnchor(AnchorBottom, 'freeViewButton', AnchorTop)
    updateSidebarCameraControls(widget)
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

    local side = resolveMinimapSide(container)
    positionMinimapHdButton(mini, side)
    if showHorizontal then
        applyHorizontalPanelLayout(horizontalRoot, side)
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

-- If the saved top slot is hidden, use the other visible top slot temporarily.
-- The minimap never falls back into the lower sidebar columns.
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

    local otherId = parent:getId() == 'gameRightTopPanel' and 'gameLeftTopPanel' or 'gameRightTopPanel'
    local otherSlot = rootWidget:recursiveGetChildById(otherId)
    if not otherSlot or otherSlot:isDestroyed() or not otherSlot:isVisible() or otherSlot:getWidth() <= 0 then
        return
    end

    parent:removeChild(ui)
    otherSlot:addChild(ui)
    otherSlot:redistributeChildrenWidths()
end

local function findMinimapDropTarget(window, mousePos)
    local root = g_ui.getRootWidget()
    if not root or not window then
        return nil
    end

    local children = root:recursiveGetChildrenByPos(mousePos)
    for i = 1, #children do
        local child = children[i]
        local isMinimapSlot = child:getId() == 'gameRightTopPanel' or child:getId() == 'gameLeftTopPanel'
        if isMinimapSlot and child ~= window and child:getClassName() == 'UIMiniWindowContainer'
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
        local baseCameraChange = minimapWidget.onCameraPositionChange
        function minimapWidget.onCameraPositionChange(widget, position, oldPosition)
            baseCameraChange(widget, position, oldPosition)
            if not widget:isDragging() then
                widget.sidebarCameraHasPixelOffset = false
            end
            updateSidebarCameraControls(widget)
        end

        local baseDragMove = minimapWidget.onDragMove
        function minimapWidget.onDragMove(widget, position, moved)
            local handled = baseDragMove(widget, position, moved)
            if handled and not widget.fullMapView then
                local viewport = widget:getPaddingRect()
                local center = widget:getTilePoint(widget:getCameraPosition())
                widget.sidebarCameraHasPixelOffset = center.x ~= math.floor(viewport.x + viewport.width / 2)
                    or center.y ~= math.floor(viewport.y + viewport.height / 2)
                updateSidebarCameraControls(widget)
            end
            return handled
        end

        if minimapWidget.setSmoothWalk then
            minimapWidget:setSmoothWalk(true)
        end
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
        modules.game_interface.scheduleSidebarLayoutUpdate()
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

    mapController:registerEvents(Creature, {
        onPositionChange = onMinimapCreatureEvent,
        onAppear = onMinimapCreatureEvent,
        onDisappear = onMinimapCreatureEvent,
        onOutfitChange = onMinimapCreatureEvent,
        onShieldChange = onPartyMinimapShieldEvent
    }):execute()

    minimapWidget = findMinimapWidget(self.ui)

    if minimapWidget and minimapWidget.setSmoothWalk then
        minimapWidget:setSmoothWalk(true)
    end

    if g_resources.fileExists(MINIMAP_FILE) then
        g_minimap.loadOtmm(MINIMAP_FILE)
    end

    if self.ui.minimapBorder and self.ui.minimapBorder.minimap then
        self.ui.minimapBorder.minimap:load()
    end
    applyMinimapHd(minimapWidget, g_settings.getBoolean('minimapHd', true))
    refreshMinimapDownloadOverlay()

    -- The default minimap slot is above the right sidebar, not inside the
    -- inventory column below it. Migrate the former default once, preserving
    -- any other explicitly saved placement.
    local char = g_game.getCharacterName()
    if char and char ~= '' then
        local settings = g_settings.getNode('CharMiniWindows') or {}
        settings[char] = settings[char] or {}
        local saved = settings[char].mainmappanel or {}
        if not saved.defaultTopPositionInitialized
            or (saved.parentId ~= 'gameRightTopPanel' and saved.parentId ~= 'gameLeftTopPanel') then
            if saved.parentId ~= 'gameRightTopPanel' and saved.parentId ~= 'gameLeftTopPanel' then
                saved.parentId = 'gameRightTopPanel'
                saved.index = 1
                saved.position = nil
            end
            saved.closed = false
            saved.defaultTopPositionInitialized = true
            settings[char].mainmappanel = saved
            g_settings.setNode('CharMiniWindows', settings)
        end
    end

    -- Controller modules never restore their mini window on their own, so the
    -- saved slot (a horizontal top panel or a sidebar column) has to be applied
    -- here or the minimap always reopens where setUI parked it.
    if self.ui.setupOnStart then
        self.ui:setupOnStart()
    end

    addEvent(function()
        if self.ui and not self.ui:isDestroyed() then
            modules.game_interface.refreshSidebarLayout()
            rescueMinimapFromHiddenSlot()
            applyContainerLayout(self.ui:getParent())
        end
    end)

    queueMinimapPartyPinsRefresh()
end

function mapController:onGameEnd()
    removeEvent(pendingCreaturePinRefresh)
    pendingCreaturePinRefresh = nil
    if fullscreenWidget and fullscreenWidget.fullMapView then
        fullscreen()
    end
    if minimapWidget and not minimapWidget:isDestroyed() then
        minimapWidget:finishSmoothZoom()
        minimapWidget.sidebarFreeView = false
        minimapWidget.sidebarCameraHasPixelOffset = false
        if minimapWidget.setSmoothWalk then
            minimapWidget:setSmoothWalk(false)
        end
        updateSidebarCameraControls(minimapWidget)
    end
    applyMinimapHd(minimapWidget, false)
    refreshMinimapDownloadOverlay(true)
    refreshMinimapPartyPins()

    -- Save Map
    g_minimap.saveOtmm(MINIMAP_FILE)
    g_minimap.clean()

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
    refreshMinimapDownloadOverlay(true)
    if pendingCreaturePinRefresh then
        removeEvent(pendingCreaturePinRefresh)
        pendingCreaturePinRefresh = nil
    end
    applyMinimapHd(fullscreenWidget or minimapWidget, false)
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end
end

function zoomIn()
    local mini = mapController.ui and mapController.ui.minimapBorder and mapController.ui.minimapBorder.minimap
    if mini then
        mini:smoothZoomBy(1)
    end
end

function zoomOut()
    local mini = mapController.ui and mapController.ui.minimapBorder and mapController.ui.minimapBorder.minimap
    if mini then
        mini:smoothZoomBy(-1)
    end
end

function openCyclopediaMap()
    if modules.game_cyclopedia and modules.game_cyclopedia.show then
        modules.game_cyclopedia.show('map')
        return
    end
    return fullscreen()
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

    minimapWidget:finishSmoothZoom()
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
    if minimapWidget.setSmoothWalk then
        minimapWidget:setSmoothWalk(not minimapWidget.fullMapView and not minimapWidget.sidebarFreeView)
    end
    positionMinimapHdButton(minimapWidget, resolveMinimapSide(mapController.ui:getParent()))
    applyMinimapHd(minimapWidget, g_game.isOnline() and g_settings.getBoolean('minimapHd', true))
    refreshMinimapDownloadOverlay()
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
