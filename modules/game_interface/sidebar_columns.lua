-- Dynamic multi-column sidebars (ported from CrystalOTC).
-- Allows N extra left/right columns via +/- and paints empty columns via sidebarFreeSpace.

local SIDEBAR_COLUMN_WIDTH = 198
local ABSOLUTE_MIN_MAP_WIDTH = 160
local MAX_HORIZONTAL_SIDEBAR_COLUMNS = 2
local VERTICAL_COLUMNS_UNDER_HORIZONTAL = 2
local pendingSidebarLayoutEvent = nil
local restoringSidebarCounts = false

gameLeftExtraPanels = gameLeftExtraPanels or {}
gameRightExtraPanels = gameRightExtraPanels or {}

local function notifyActionBars()
    if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
        addEvent(function()
            modules.game_actionbar.updateVisibleWidgetsExternal()
        end)
    end
end

local function getRequiredCenterWidth()
    return ABSOLUTE_MIN_MAP_WIDTH
end

local function getMapContentWidth()
    if not gameMapPanel or gameMapPanel:isDestroyed() then
        return 0
    end
    local rect = gameMapPanel:getPaddingRect()
    return rect.width or 0
end

local function visibleSidebarWidth(panel)
    if not panel or panel:isDestroyed() or not panel:isVisible() then
        return 0
    end
    if not panel:isOn() then
        return 0
    end
    return panel:getWidth()
end

local function isSidebarPanelOpen(panel)
    return visibleSidebarWidth(panel) > 0
end

local function getSideExtraPanelList(side)
    return side == 'left' and gameLeftExtraPanels or gameRightExtraPanels
end

local function getOrderedLeftPanels()
    local panels = {}
    if gameLeftPanel and not gameLeftPanel:isDestroyed() then
        table.insert(panels, gameLeftPanel)
    end
    for _, panel in ipairs(gameLeftExtraPanels) do
        if panel and not panel:isDestroyed() then
            table.insert(panels, panel)
        end
    end
    return panels
end

local function getOrderedRightPanelsFromMap()
    local panels = {}
    for i = #gameRightExtraPanels, 1, -1 do
        local panel = gameRightExtraPanels[i]
        if panel and not panel:isDestroyed() then
            table.insert(panels, panel)
        end
    end
    if gameRightPanel and not gameRightPanel:isDestroyed() then
        table.insert(panels, gameRightPanel)
    end
    return panels
end

function isGameSidePanelId(panelId)
    return panelId == 'gameLeftPanel' or panelId == 'gameRightPanel'
        or panelId:find('^gameLeftExtraPanel') ~= nil
        or panelId:find('^gameRightExtraPanel') ~= nil
end

function getLeftMapEdgePanel()
    local lastVisible = gameLeftPanel
    for _, panel in ipairs(getOrderedLeftPanels()) do
        if isSidebarPanelOpen(panel) then
            lastVisible = panel
        end
    end
    return lastVisible
end

function getRightMapEdgePanel()
    for _, panel in ipairs(getOrderedRightPanelsFromMap()) do
        if isSidebarPanelOpen(panel) then
            return panel
        end
    end
    return gameRightPanel
end

function countVisibleExtraPanels(side)
    local count = 0
    for _, panel in ipairs(getSideExtraPanelList(side)) do
        if panel and not panel:isDestroyed() and panel:isOn() then
            count = count + 1
        end
    end
    return count
end

local function getTotalSidebarWidth(panels)
    local width = 0
    for _, panel in ipairs(panels) do
        width = width + visibleSidebarWidth(panel)
    end
    return width
end

local function getOccupiedSidebarWidth(side)
    local panels = side == 'left' and getOrderedLeftPanels() or getOrderedRightPanelsFromMap()
    return getTotalSidebarWidth(panels)
end

local function getTotalOccupiedSidebarWidth()
    return getOccupiedSidebarWidth('left') + getOccupiedSidebarWidth('right')
end

local function getMaxTotalSidebarWidth()
    if not gameRootPanel or gameRootPanel:isDestroyed() then
        return 0
    end
    return math.max(0, gameRootPanel:getWidth() - getRequiredCenterWidth())
end

local function gameRootFitsSidebarWidth(side, columnsToAdd)
    if not gameRootPanel or gameRootPanel:isDestroyed() then
        return false
    end

    columnsToAdd = columnsToAdd or 1
    local extraWidth = SIDEBAR_COLUMN_WIDTH * columnsToAdd
    local leftWidth = getOccupiedSidebarWidth('left')
    local rightWidth = getOccupiedSidebarWidth('right')

    if side == 'left' then
        leftWidth = leftWidth + extraWidth
    else
        rightWidth = rightWidth + extraWidth
    end

    return leftWidth + rightWidth + getRequiredCenterWidth() <= gameRootPanel:getWidth()
end

local function getSidebarExpansionSlack()
    local mapWidth = getMapContentWidth()
    if mapWidth <= 0 then
        -- Before map is laid out, allow at least the first extras.
        return SIDEBAR_COLUMN_WIDTH * 4
    end
    return math.max(0, mapWidth - getRequiredCenterWidth())
end

function canAddSidebarColumn(side)
    if getSidebarExpansionSlack() < SIDEBAR_COLUMN_WIDTH then
        return false
    end
    return gameRootFitsSidebarWidth(side, 1)
end

local function canIncreaseLeftSidePanels()
    if getSidebarExpansionSlack() < SIDEBAR_COLUMN_WIDTH then
        return false
    end
    if not modules.client_options.getOption('showLeftPanel') then
        return true
    end
    return canAddSidebarColumn('left')
end

local function canIncreaseRightSidePanels()
    return canAddSidebarColumn('right')
end

local function setSidebarPanelVisible(panel, visible)
    if not panel or panel:isDestroyed() then
        return false
    end
    panel:setOn(visible)
    panel:setVisible(visible)
    return true
end

local function hideSidebarPanel(panel)
    if panel and not panel:isDestroyed() and panel:isOn() then
        return setSidebarPanelVisible(panel, false)
    end
    return false
end

local function hideLastOverflowSidebarColumn()
    for index = #gameRightExtraPanels, 1, -1 do
        if hideSidebarPanel(gameRightExtraPanels[index]) then
            return true
        end
    end
    for index = #gameLeftExtraPanels, 1, -1 do
        if hideSidebarPanel(gameLeftExtraPanels[index]) then
            return true
        end
    end
    return false
end

local function clampSidebarPanelsToAvailableSpace()
    if not gameRootPanel or gameRootPanel:isDestroyed() then
        return false
    end

    local maxSidebarWidth = getMaxTotalSidebarWidth()
    local changed = false
    while maxSidebarWidth < getTotalOccupiedSidebarWidth() do
        if not hideLastOverflowSidebarColumn() then
            break
        end
        changed = true
    end
    return changed
end

local function closeSidebarMiniwindows(mainpanel)
    if not mainpanel or mainpanel:isDestroyed() then
        return
    end

    local children = mainpanel:getChildren()
    for i = #children, 1, -1 do
        local widget = children[i]
        if widget and not widget:isDestroyed() and widget.UIMiniWindowContainer
            and not widget._sidebarFreeSpaceWidget and widget.close and widget:isExplicitlyVisible() then
            widget:close()
        end
    end
end

local function isHorizontalBarActive(side)
    local topPanel = side == 'left' and gameLeftTopPanel or gameRightTopPanel
    if not topPanel or topPanel:isDestroyed() or not topPanel:isOn() then
        return false
    end
    return topPanel:getWidth() > 0 and topPanel:getHeight() > 0
end

local function applyVerticalSidebarAnchors(panel, side, columnIndex, chainHookId)
    if not panel or panel:isDestroyed() or not panel:isOn() then
        return
    end

    local topPanelId = side == 'left' and 'gameLeftTopPanel' or 'gameRightTopPanel'
    local underHorizontal = isHorizontalBarActive(side) and columnIndex <= VERTICAL_COLUMNS_UNDER_HORIZONTAL

    panel:breakAnchors()

    if side == 'left' then
        if columnIndex == 1 then
            panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        else
            panel:addAnchor(AnchorLeft, chainHookId, AnchorRight)
        end
        if underHorizontal then
            panel:addAnchor(AnchorTop, topPanelId, AnchorBottom)
        else
            panel:addAnchor(AnchorTop, 'parent', AnchorTop)
        end
        panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        panel:setMarginTop(underHorizontal and 1 or 0)
        if columnIndex > 1 then
            panel:setMarginLeft(1)
        else
            panel:setMarginLeft(0)
        end
    else
        if columnIndex == 1 then
            -- Keep Fonticak's stacked main-right + right panel layout.
            if panel == gameRightPanel and gameMainRightPanel and not gameMainRightPanel:isDestroyed() then
                panel:addAnchor(AnchorRight, 'parent', AnchorRight)
                panel:addAnchor(AnchorTop, 'gameMainRightPanel', AnchorBottom)
                panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
                panel:setMarginTop(0)
            else
                panel:addAnchor(AnchorRight, chainHookId or 'parent', AnchorRight)
                if underHorizontal then
                    panel:addAnchor(AnchorTop, topPanelId, AnchorBottom)
                else
                    panel:addAnchor(AnchorTop, 'parent', AnchorTop)
                end
                panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
                panel:setMarginTop(underHorizontal and 1 or 0)
            end
        else
            panel:addAnchor(AnchorRight, chainHookId, AnchorLeft)
            if underHorizontal then
                panel:addAnchor(AnchorTop, topPanelId, AnchorBottom)
            else
                panel:addAnchor(AnchorTop, 'parent', AnchorTop)
            end
            panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
            panel:setMarginRight(1)
            panel:setMarginTop(underHorizontal and 1 or 0)
        end
    end
end

function reanchorVerticalSidebarPanels(side)
    if side == 'left' then
        if gameLeftPanel and not gameLeftPanel:isDestroyed() and gameLeftPanel:isOn() then
            applyVerticalSidebarAnchors(gameLeftPanel, 'left', 1, nil)
        end

        local hookId = gameLeftPanel and not gameLeftPanel:isDestroyed() and gameLeftPanel:isOn() and gameLeftPanel:getId() or nil
        local columnIndex = 1
        for _, panel in ipairs(gameLeftExtraPanels) do
            if panel and not panel:isDestroyed() and panel:isOn() then
                columnIndex = columnIndex + 1
                local chainHookId = hookId or (gameLeftPanel and gameLeftPanel:getId())
                if chainHookId then
                    applyVerticalSidebarAnchors(panel, 'left', columnIndex, chainHookId)
                    hookId = panel:getId()
                end
            end
        end
        return
    end

    if gameRightPanel and not gameRightPanel:isDestroyed() and gameRightPanel:isOn() then
        applyVerticalSidebarAnchors(gameRightPanel, 'right', 1, 'parent')
    end

    local hookId = gameRightPanel and not gameRightPanel:isDestroyed() and gameRightPanel:isOn() and gameRightPanel:getId() or nil
    local columnIndex = 1
    for _, panel in ipairs(gameRightExtraPanels) do
        if panel and not panel:isDestroyed() and panel:isOn() then
            columnIndex = columnIndex + 1
            local chainHookId = hookId or (gameRightPanel and gameRightPanel:getId())
            if chainHookId then
                applyVerticalSidebarAnchors(panel, 'right', columnIndex, chainHookId)
                hookId = panel:getId()
            end
        end
    end
end

local function reanchorMainRightPanel()
    if not gameMainRightPanel or gameMainRightPanel:isDestroyed() then
        return
    end

    gameMainRightPanel:breakAnchors()
    gameMainRightPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    if isHorizontalBarActive('right') and gameRightTopPanel and not gameRightTopPanel:isDestroyed() then
        gameMainRightPanel:addAnchor(AnchorTop, 'gameRightTopPanel', AnchorBottom)
        gameMainRightPanel:setMarginTop(1)
    else
        gameMainRightPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
        gameMainRightPanel:setMarginTop(0)
    end
end

local function horizontalSidebarColumns(side)
    local candidates
    if side == 'left' then
        candidates = { gameLeftPanel, gameLeftExtraPanels[1] }
    else
        candidates = { gameRightPanel, gameRightExtraPanels[1] }
    end

    local columns = {}
    for i = 1, #candidates do
        local panel = candidates[i]
        if panel and not panel:isDestroyed() and isSidebarPanelOpen(panel) then
            columns[#columns + 1] = panel
            if #columns >= MAX_HORIZONTAL_SIDEBAR_COLUMNS then
                break
            end
        end
    end
    return columns
end

-- The bar has to end exactly where the columns below it end, so measure their
-- real widths and gutters instead of assuming every column is SIDEBAR_COLUMN_WIDTH.
local function horizontalPanelWidth(side)
    local columns = horizontalSidebarColumns(side)
    if #columns == 0 then
        return 0
    end

    local width = 0
    for i = 1, #columns do
        local panel = columns[i]
        width = width + panel:getWidth()
        if i > 1 then
            width = width + panel:getMarginLeft() + panel:getMarginRight()
        end
    end
    return width
end

function updateHorizontalPanelWidths()
    if gameLeftTopPanel and not gameLeftTopPanel:isDestroyed() then
        local leftWidth = horizontalPanelWidth('left')
        if leftWidth <= 0 then
            gameLeftTopPanel:setWidth(0)
            gameLeftTopPanel:setVisible(false)
        else
            gameLeftTopPanel:setWidth(leftWidth)
            if gameLeftTopPanel:isOn() then
                gameLeftTopPanel:setVisible(true)
            end
            if type(gameLeftTopPanel.redistributeChildrenWidths) == 'function' then
                gameLeftTopPanel:redistributeChildrenWidths()
            end
        end
    end

    if gameRightTopPanel and not gameRightTopPanel:isDestroyed() then
        local rightWidth = horizontalPanelWidth('right')
        if rightWidth <= 0 then
            gameRightTopPanel:setWidth(0)
            gameRightTopPanel:setVisible(false)
        else
            gameRightTopPanel:setWidth(rightWidth)
            if gameRightTopPanel:isOn() then
                gameRightTopPanel:setVisible(true)
            end
            if type(gameRightTopPanel.redistributeChildrenWidths) == 'function' then
                gameRightTopPanel:redistributeChildrenWidths()
            end
        end
    end
end

local function raiseHorizontalPanels()
    if gameLeftTopPanel and not gameLeftTopPanel:isDestroyed() and gameLeftTopPanel:isVisible() then
        gameLeftTopPanel:raise()
    end
    if gameRightTopPanel and not gameRightTopPanel:isDestroyed() and gameRightTopPanel:isVisible() then
        gameRightTopPanel:raise()
    end
end

local function raiseSidebarControlButtons()
    if leftIncreaseSidePanels and not leftIncreaseSidePanels:isDestroyed() then
        leftIncreaseSidePanels:raise()
    end
    if leftDecreaseSidePanels and not leftDecreaseSidePanels:isDestroyed() then
        leftDecreaseSidePanels:raise()
    end
    if rightIncreaseSidePanels and not rightIncreaseSidePanels:isDestroyed() then
        rightIncreaseSidePanels:raise()
    end
    if rightDecreaseSidePanels and not rightDecreaseSidePanels:isDestroyed() then
        rightDecreaseSidePanels:raise()
    end
end

local function reanchorAllVerticalSidebarPanels()
    reanchorMainRightPanel()
    reanchorVerticalSidebarPanels('left')
    reanchorVerticalSidebarPanels('right')
end

function reanchorCenterToSidebars()
    if not gameRootPanel or gameRootPanel:isDestroyed() then
        return
    end

    local leftEdge = getLeftMapEdgePanel()
    local rightEdge = getRightMapEdgePanel()
    if not leftEdge or not rightEdge then
        return
    end

    local leftId = leftEdge:getId()
    local rightId = rightEdge:getId()

    if gameLeftActionPanel and not gameLeftActionPanel:isDestroyed() then
        gameLeftActionPanel:breakAnchors()
        gameLeftActionPanel:addAnchor(AnchorLeft, leftId, AnchorRight)
        gameLeftActionPanel:addAnchor(AnchorTop, 'gameTopPanel', AnchorBottom)
        gameLeftActionPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
        gameLeftActionPanel:setMarginLeft(1)
    end

    if gameRightActionPanel and not gameRightActionPanel:isDestroyed() then
        gameRightActionPanel:breakAnchors()
        gameRightActionPanel:addAnchor(AnchorRight, rightId, AnchorLeft)
        gameRightActionPanel:addAnchor(AnchorTop, 'gameTopPanel', AnchorBottom)
        gameRightActionPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
        gameRightActionPanel:setMarginRight(1)
    end

    if gameMapPanel and not gameMapPanel:isDestroyed() then
        gameMapPanel:breakAnchors()
        gameMapPanel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
        gameMapPanel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
        gameMapPanel:addAnchor(AnchorTop, 'gameTopPanel', AnchorBottom)
        gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
        gameMapPanel:setMarginTop(1)
        gameMapPanel:setMarginBottom(1)
    end

    -- Keep Fonticak bottom panel stacking (cooldown/action/console); do not reparent it.
    if gameTopPanel and not gameTopPanel:isDestroyed() then
        gameTopPanel:breakAnchors()
        gameTopPanel:addAnchor(AnchorLeft, leftId, AnchorRight)
        gameTopPanel:addAnchor(AnchorRight, rightId, AnchorLeft)
        gameTopPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    end

    if gameBottomStatsBarPanel and not gameBottomStatsBarPanel:isDestroyed() then
        gameBottomStatsBarPanel:breakAnchors()
        gameBottomStatsBarPanel:addAnchor(AnchorLeft, leftId, AnchorRight)
        gameBottomStatsBarPanel:addAnchor(AnchorRight, rightId, AnchorLeft)
        gameBottomStatsBarPanel:addAnchor(AnchorTop, 'bottomSplitter', AnchorBottom)
        gameBottomStatsBarPanel:setMarginLeft(1)
        gameBottomStatsBarPanel:setMarginRight(1)
    end

    if bottomSplitter and not bottomSplitter:isDestroyed() then
        bottomSplitter:breakAnchors()
        bottomSplitter:addAnchor(AnchorLeft, leftId, AnchorRight)
        bottomSplitter:addAnchor(AnchorRight, rightId, AnchorLeft)
        bottomSplitter:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    end

    if leftIncreaseSidePanels and not leftIncreaseSidePanels:isDestroyed() then
        leftIncreaseSidePanels:breakAnchors()
        leftIncreaseSidePanels:addAnchor(AnchorLeft, leftId, AnchorRight)
        leftIncreaseSidePanels:addAnchor(AnchorTop, 'parent', AnchorTop)
    end

    if rightIncreaseSidePanels and not rightIncreaseSidePanels:isDestroyed() then
        rightIncreaseSidePanels:breakAnchors()
        rightIncreaseSidePanels:addAnchor(AnchorRight, rightId, AnchorLeft)
        rightIncreaseSidePanels:addAnchor(AnchorTop, 'parent', AnchorTop)
    end
end

local function fitAllVerticalSidebars()
    local function fitPanel(panel)
        if not panel or panel:isDestroyed() or not panel:isOn() then
            return
        end
        if panel.getClassName and panel:getClassName() ~= 'UIMiniWindowContainer' then
            return
        end
        if type(panel.fitAll) == 'function' then
            panel:fitAll()
        end
    end

    fitPanel(gameRightPanel)
    for _, panel in ipairs(gameRightExtraPanels or {}) do
        fitPanel(panel)
    end
    fitPanel(gameLeftPanel)
    for _, panel in ipairs(gameLeftExtraPanels or {}) do
        fitPanel(panel)
    end
end

local MAP_ASPECT_RATIO = 15 / 11

local function getMapAspectRatio()
    if gameMapPanel and not gameMapPanel:isDestroyed() then
        local dim = gameMapPanel:getVisibleDimension()
        if dim and dim.width and dim.height and dim.height > 0 then
            return dim.width / dim.height
        end
    end
    return MAP_ASPECT_RATIO
end

local function getBottomAreaMinMargin()
    local actionBars = 0
    if modules.game_actionbar and modules.game_actionbar.getActiveBottomBars then
        actionBars = modules.game_actionbar.getActiveBottomBars() or 0
    end
    return 125 + (35 * actionBars)
end

-- When side columns change map width, shrink/grow the map height via the bottom
-- splitter so the main view stays top-aligned at the correct aspect ratio.
function fitMapHeightToAspectRatio()
    if currentViewMode and currentViewMode ~= 0 then
        return
    end

    if modules.client_options and modules.client_options.getOption('dontStretchShrink') then
        return
    end

    if not gameMapPanel or gameMapPanel:isDestroyed() then
        return
    end
    if not bottomSplitter or bottomSplitter:isDestroyed() then
        return
    end

    local aspect = getMapAspectRatio()
    if aspect <= 0 then
        return
    end

    local widgetWidth = gameMapPanel:getWidth()
    local paddingH = gameMapPanel:getPaddingLeft() + gameMapPanel:getPaddingRight()
    local paddingV = gameMapPanel:getPaddingTop() + gameMapPanel:getPaddingBottom()
    local internalWidth = widgetWidth - paddingH
    if internalWidth <= 0 then
        return
    end

    local idealInternalHeight = math.floor(internalWidth / aspect + 0.5)
    local idealWidgetHeight = idealInternalHeight + paddingV
    local currentWidgetHeight = gameMapPanel:getHeight()
    local currentMargin = bottomSplitter:getMarginBottom()
    local totalHeight = currentWidgetHeight + currentMargin
    local targetMargin = totalHeight - idealWidgetHeight

    local parent = bottomSplitter:getParent()
    local parentH = parent and parent:getHeight() or 0
    local minM = getBottomAreaMinMargin()
    local maxM = math.max(minM, parentH - 150)
    targetMargin = math.max(minM, math.min(targetMargin, maxM))

    if math.abs(targetMargin - currentMargin) > 1 then
        bottomSplitter:setMarginBottom(targetMargin)
    end
end

function updateSidebarControlStates()
    if not leftIncreaseSidePanels or leftIncreaseSidePanels:isDestroyed() then
        return
    end

    local leftPrimaryOn = modules.client_options.getOption('showLeftPanel')
    leftIncreaseSidePanels:setEnabled(canIncreaseLeftSidePanels())
    if g_platform.isMobile() then
        leftDecreaseSidePanels:setEnabled(false)
    else
        leftDecreaseSidePanels:setEnabled(leftPrimaryOn or countVisibleExtraPanels('left') > 0)
    end
    rightIncreaseSidePanels:setEnabled(canIncreaseRightSidePanels())
    rightDecreaseSidePanels:setEnabled(countVisibleExtraPanels('right') > 0)
end

-- Keep old name used by gameinterface.lua
function updateSidePanelButtons()
    updateSidebarControlStates()
end

function refreshSidebarLayout()
    if not g_game.isOnline() then
        return
    end

    updateHorizontalPanelWidths()
    reanchorAllVerticalSidebarPanels()
    local clamped = clampSidebarPanelsToAvailableSpace()
    if clamped then
        updateHorizontalPanelWidths()
        reanchorAllVerticalSidebarPanels()
    end

    reanchorCenterToSidebars()
    updateSidebarControlStates()
    raiseHorizontalPanels()
    raiseSidebarControlButtons()
    addEvent(function()
        fitMapHeightToAspectRatio()
        fitAllVerticalSidebars()
        raiseHorizontalPanels()
        raiseSidebarControlButtons()
        -- Second pass after anchors settle to the new column widths.
        scheduleEvent(fitMapHeightToAspectRatio, 50)
    end)

    if clamped then
        saveSidebarColumnCounts()
    end
end

function scheduleSidebarLayoutUpdate()
    if not g_game.isOnline() then
        return
    end
    if pendingSidebarLayoutEvent then
        return
    end

    pendingSidebarLayoutEvent = addEvent(function()
        pendingSidebarLayoutEvent = nil
        if not g_game.isOnline() then
            return
        end
        refreshSidebarLayout()
    end)
end

local function unregisterPanelEntry(panel, checkbox)
    for index, entry in ipairs(panelsList) do
        if entry.panel == panel then
            table.remove(panelsList, index)
            break
        end
    end
    if panelsRadioGroup and checkbox and not checkbox:isDestroyed() then
        panelsRadioGroup:removeWidget(checkbox)
        checkbox:destroy()
    end
end

local function registerPanelEntry(panel, checkbox)
    table.insert(panelsList, {
        panel = panel,
        checkbox = checkbox
    })
    if panelsRadioGroup and checkbox then
        panelsRadioGroup:addWidget(checkbox)
        connect(checkbox, {
            onCheckChange = onSelectPanel
        })
    end
    connect(panel, {
        onVisibilityChange = scheduleSidebarLayoutUpdate
    })
end

local function createSelectColumnButton(panel)
    local checkbox = g_ui.createWidget('SelectColumnButton', gameRootPanel)
    checkbox:setId(panel:getId() .. 'Select')
    checkbox:addAnchor(AnchorRight, panel:getId(), AnchorRight)
    checkbox:addAnchor(AnchorBottom, panel:getId(), AnchorBottom)
    registerPanelEntry(panel, checkbox)
    return checkbox
end

local function destroySideExtraPanel(side, index)
    local list = getSideExtraPanelList(side)
    local panel = list[index]
    if not panel or index <= 1 then
        return false
    end

    closeSidebarMiniwindows(panel)
    local checkbox = gameRootPanel:recursiveGetChildById(panel:getId() .. 'Select')
    unregisterPanelEntry(panel, checkbox)
    panel:destroy()
    table.remove(list, index)
    refreshSidebarLayout()
    saveSidebarColumnCounts()
    notifyActionBars()
    return true
end

local function insertSideExtraPanelForRestore(side)
    local list = getSideExtraPanelList(side)
    local index = #list + 1
    local panel = g_ui.createWidget('GameSidePanel', gameRootPanel)
    panel:setId((side == 'left' and 'gameLeftExtraPanel_' or 'gameRightExtraPanel_') .. index)
    panel:setPaddingTop(0)
    setSidebarPanelVisible(panel, true)
    table.insert(list, panel)
    createSelectColumnButton(panel)
    return panel
end

local function insertSideExtraPanel(side)
    if not canAddSidebarColumn(side) then
        return nil
    end
    return insertSideExtraPanelForRestore(side)
end

function createSideExtraPanel(side)
    local panel = insertSideExtraPanel(side)
    if not panel then
        return nil
    end
    refreshSidebarLayout()
    saveSidebarColumnCounts()
    notifyActionBars()
    return panel
end

function saveSidebarColumnCounts()
    local settings = g_settings.getNode('game_interface') or {}
    settings.leftExtraPanelCount = countVisibleExtraPanels('left')
    settings.rightExtraPanelCount = countVisibleExtraPanels('right')
    if bottomSplitter and not bottomSplitter:isDestroyed() then
        settings.splitterMarginBottom = bottomSplitter:getMarginBottom()
    end
    g_settings.setNode('game_interface', settings)
end

function restoreSidebarColumnCounts(leftCount, rightCount)
    restoringSidebarCounts = true

    if leftCount == nil and rightCount == nil then
        local settings = g_settings.getNode('game_interface') or {}
        leftCount = tonumber(settings.leftExtraPanelCount) or 0
        rightCount = tonumber(settings.rightExtraPanelCount) or 0
        if leftCount == 0 and modules.client_options.getOption('showLeftExtraPanel') then
            leftCount = 1
        end
        if rightCount == 0 and modules.client_options.getOption('showRightExtraPanel') then
            rightCount = 1
        end
    else
        leftCount = tonumber(leftCount) or 0
        rightCount = tonumber(rightCount) or 0
    end

    while leftCount > #gameLeftExtraPanels do
        insertSideExtraPanelForRestore('left')
    end
    while rightCount > #gameRightExtraPanels do
        insertSideExtraPanelForRestore('right')
    end

    for index, panel in ipairs(gameLeftExtraPanels) do
        setSidebarPanelVisible(panel, index <= leftCount)
    end
    for index, panel in ipairs(gameRightExtraPanels) do
        setSidebarPanelVisible(panel, index <= rightCount)
    end

    modules.client_options.setOption('showLeftExtraPanel', leftCount > 0, true)
    modules.client_options.setOption('showRightExtraPanel', rightCount > 0, true)
    restoringSidebarCounts = false
    refreshSidebarLayout()
end

function initSidebarColumns()
    gameLeftExtraPanels = { gameLeftExtraPanel }
    gameRightExtraPanels = { gameRightExtraPanel }

    if gameRootPanel then
        local previous = gameRootPanel.onGeometryChange
        gameRootPanel.onGeometryChange = function(...)
            if previous then
                previous(...)
            end
            scheduleSidebarLayoutUpdate()
        end
    end

    -- Mouse wheel on the +/- sidebar buttons:
    -- wheel up = right arrow (increase), wheel down = left arrow (decrease).
    local function bindSidePanelWheel(increaseBtn, decreaseBtn, onIncrease, onDecrease)
        local function onWheel(widget, mousePos, direction)
            if direction == MouseWheelUp then
                onIncrease()
            elseif direction == MouseWheelDown then
                onDecrease()
            end
            return true
        end

        if increaseBtn and not increaseBtn:isDestroyed() then
            increaseBtn.onMouseWheel = onWheel
        end
        if decreaseBtn and not decreaseBtn:isDestroyed() then
            decreaseBtn.onMouseWheel = onWheel
        end
    end

    bindSidePanelWheel(leftIncreaseSidePanels, leftDecreaseSidePanels, onIncreaseLeftPanels, onDecreaseLeftPanels)
    bindSidePanelWheel(rightIncreaseSidePanels, rightDecreaseSidePanels, onIncreaseRightPanels, onDecreaseRightPanels)

    updateHorizontalPanelWidths()
    raiseHorizontalPanels()
    raiseSidebarControlButtons()
end

function terminateSidebarColumns()
    for index = #gameLeftExtraPanels, 2, -1 do
        local panel = gameLeftExtraPanels[index]
        if panel and not panel:isDestroyed() then
            local checkbox = gameRootPanel and gameRootPanel:recursiveGetChildById(panel:getId() .. 'Select')
            unregisterPanelEntry(panel, checkbox)
            panel:destroy()
        end
        table.remove(gameLeftExtraPanels, index)
    end
    for index = #gameRightExtraPanels, 2, -1 do
        local panel = gameRightExtraPanels[index]
        if panel and not panel:isDestroyed() then
            local checkbox = gameRootPanel and gameRootPanel:recursiveGetChildById(panel:getId() .. 'Select')
            unregisterPanelEntry(panel, checkbox)
            panel:destroy()
        end
        table.remove(gameRightExtraPanels, index)
    end
end

function onIncreaseLeftPanels()
    if not canIncreaseLeftSidePanels() then
        return
    end

    if not modules.client_options.getOption('showLeftPanel') then
        modules.client_options.setOption('showLeftPanel', true, true)
        refreshSidebarLayout()
        saveSidebarColumnCounts()
        notifyActionBars()
        return
    end

    for _, panel in ipairs(gameLeftExtraPanels) do
        if panel and not panel:isDestroyed() and not panel:isOn() then
            if canAddSidebarColumn('left') then
                setSidebarPanelVisible(panel, true)
                modules.client_options.setOption('showLeftExtraPanel', true, true)
                refreshSidebarLayout()
                saveSidebarColumnCounts()
                notifyActionBars()
            end
            return
        end
    end

    if createSideExtraPanel('left') then
        modules.client_options.setOption('showLeftExtraPanel', true, true)
    end
end

function onDecreaseLeftPanels()
    for index = #gameLeftExtraPanels, 1, -1 do
        local panel = gameLeftExtraPanels[index]
        if panel and not panel:isDestroyed() and panel:isOn() then
            if index > 1 then
                destroySideExtraPanel('left', index)
            else
                closeSidebarMiniwindows(panel)
                setSidebarPanelVisible(panel, false)
                scheduleSidebarLayoutUpdate()
            end
            modules.client_options.setOption('showLeftExtraPanel', countVisibleExtraPanels('left') > 0, true)
            saveSidebarColumnCounts()
            notifyActionBars()
            return
        end
    end

    if not g_platform.isMobile() and modules.client_options.getOption('showLeftPanel') then
        modules.client_options.setOption('showLeftPanel', false)
        closeSidebarMiniwindows(gameLeftPanel)
        refreshSidebarLayout()
        saveSidebarColumnCounts()
        notifyActionBars()
    end
end

function onIncreaseRightPanels()
    if not canIncreaseRightSidePanels() then
        return
    end

    for _, panel in ipairs(gameRightExtraPanels) do
        if panel and not panel:isDestroyed() and not panel:isOn() then
            if canAddSidebarColumn('right') then
                setSidebarPanelVisible(panel, true)
                modules.client_options.setOption('showRightExtraPanel', true, true)
                refreshSidebarLayout()
                saveSidebarColumnCounts()
                notifyActionBars()
            end
            return
        end
    end

    if createSideExtraPanel('right') then
        modules.client_options.setOption('showRightExtraPanel', true, true)
    end
end

function onDecreaseRightPanels()
    for index = #gameRightExtraPanels, 1, -1 do
        local panel = gameRightExtraPanels[index]
        if panel and not panel:isDestroyed() and panel:isOn() then
            if index > 1 then
                destroySideExtraPanel('right', index)
            else
                closeSidebarMiniwindows(panel)
                setSidebarPanelVisible(panel, false)
                scheduleSidebarLayoutUpdate()
            end
            modules.client_options.setOption('showRightExtraPanel', countVisibleExtraPanels('right') > 0, true)
            saveSidebarColumnCounts()
            notifyActionBars()
            return
        end
    end
end

function setExtraPanelsFromOption(side, enabled)
    if restoringSidebarCounts then
        return
    end

    local list = getSideExtraPanelList(side)
    if enabled then
        if countVisibleExtraPanels(side) == 0 and list[1] then
            setSidebarPanelVisible(list[1], true)
        end
    else
        for index = #list, 1, -1 do
            local panel = list[index]
            if panel and not panel:isDestroyed() and panel:isOn() then
                closeSidebarMiniwindows(panel)
                if index > 1 then
                    local checkbox = gameRootPanel:recursiveGetChildById(panel:getId() .. 'Select')
                    unregisterPanelEntry(panel, checkbox)
                    panel:destroy()
                    table.remove(list, index)
                else
                    setSidebarPanelVisible(panel, false)
                end
            end
        end
    end
    scheduleSidebarLayoutUpdate()
    saveSidebarColumnCounts()
    notifyActionBars()
end

function applyExtraPanelsViewMode(extendedView, showLeftExtra, showRightExtra)
    for _, panel in ipairs(gameLeftExtraPanels or {}) do
        if panel and not panel:isDestroyed() then
            if extendedView then
                setSidebarPanelVisible(panel, false)
            else
                panel:setImageColor('white')
            end
        end
    end
    for _, panel in ipairs(gameRightExtraPanels or {}) do
        if panel and not panel:isDestroyed() then
            if extendedView then
                setSidebarPanelVisible(panel, false)
            else
                panel:setImageColor('white')
            end
        end
    end

    if not extendedView then
        if gameLeftExtraPanels[1] then
            setSidebarPanelVisible(gameLeftExtraPanels[1], showLeftExtra)
        end
        if gameRightExtraPanels[1] then
            setSidebarPanelVisible(gameRightExtraPanels[1], showRightExtra)
        end
        scheduleSidebarLayoutUpdate()
    end
end
