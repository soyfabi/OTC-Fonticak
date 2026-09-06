-- @docclass
UIMiniWindowContainer = extends(UIWidget, 'UIMiniWindowContainer')

local SIDEBAR_FREE_SPACE_IMAGE = '/images/ui/2pixel_up_frame_borderimage'
local SIDEBAR_FREE_SPACE_BORDER = 2
local BOT_WINDOW_COLUMN_WIDTH = 178

-- The bot window forces its column narrower than the default. The horizontal top
-- bar is sized from the columns below it, so it has to be recomputed afterwards
-- or it keeps the old width and juts out over the column edge.
local function applyBotWindowColumnWidth(widget)
    if not widget or widget:isDestroyed() or widget:getId() ~= 'botWindow' then
        return
    end

    local column = widget:getParent()
    if not column or column:isDestroyed() then
        return
    end

    local columnId = column:getId() or ''
    if columnId ~= 'gameLeftPanel' and not columnId:find('^gameLeftExtraPanel')
        and not columnId:find('^gameRightExtraPanel') then
        return
    end

    column:setWidth(BOT_WINDOW_COLUMN_WIDTH)

    if modules.game_interface and modules.game_interface.scheduleSidebarLayoutUpdate then
        modules.game_interface.scheduleSidebarLayoutUpdate()
    end
end

function UIMiniWindowContainer.create()
    local container = UIMiniWindowContainer.internalCreate()
    container.scheduledWidgets = {}
    container:setFocusable(false)
    container:setPhantom(true)
    connect(container, {
        onGeometryChange = function(widget)
            if type(widget.scheduleSidebarFreeSpaceRefresh) == 'function' then
                widget:scheduleSidebarFreeSpaceRefresh()
            end
            if widget.isHorizontalPanel and type(widget.redistributeChildrenWidths) == 'function' then
                widget:redistributeChildrenWidths()
            end
        end,
        -- Docking or undocking a window leaves the container the same size, so
        -- onGeometryChange never fires and the filler keeps its previous height.
        onLayoutUpdate = function(widget)
            if type(widget.scheduleSidebarFreeSpaceRefresh) == 'function' then
                widget:scheduleSidebarFreeSpaceRefresh()
            end
        end
    })
    return container
end

local function isSidebarFreeSpaceWidget(widget)
    return widget and widget._sidebarFreeSpaceWidget == true
end

local function isSidebarPlaceholderWidget(widget)
    return widget and widget._sidebarPlaceholderWidget == true
end

local function isSidebarSystemWidget(widget)
    return isSidebarFreeSpaceWidget(widget) or isSidebarPlaceholderWidget(widget)
end

UIMiniWindowContainer.isSidebarFreeSpaceWidget = isSidebarFreeSpaceWidget
UIMiniWindowContainer.isSidebarPlaceholderWidget = isSidebarPlaceholderWidget
UIMiniWindowContainer.isSidebarSystemWidget = isSidebarSystemWidget

local function shouldManageSidebarFreeSpace(container)
    if not container or container:isDestroyed() or not container:isVisible() then
        return false
    end

    if container.ignoreFillAll or container.isHorizontalPanel or container.onlyPhantomDrop then
        return false
    end

    return true
end

local function ensureSidebarFreeSpaceWidget(container)
    local widget = container._sidebarFreeSpaceWidget
    if widget and not widget:isDestroyed() then
        return widget
    end

    widget = g_ui.createWidget('UIWidget')
    widget:setId('sidebarFreeSpace')
    widget._sidebarFreeSpaceWidget = true
    widget:setPhantom(true)
    widget:setFocusable(false)
    widget:setImageSource(SIDEBAR_FREE_SPACE_IMAGE)
    widget:setImageBorder(SIDEBAR_FREE_SPACE_BORDER)
    if widget.setImageRepeatedFromBottom then
        widget:setImageRepeatedFromBottom(true)
    end

    container._sidebarFreeSpaceWidget = widget
    return widget
end

function UIMiniWindowContainer:scheduleSidebarFreeSpaceRefresh()
    if self._sidebarFreeSpaceRefreshScheduled then
        return
    end

    -- A refresh in flight resizes the filler, which fires the layout hooks again.
    -- Remember it instead of dropping it or the container keeps the stale size.
    if self._sidebarFreeSpaceRefreshing then
        self._sidebarFreeSpaceRefreshPending = true
        return
    end

    self._sidebarFreeSpaceRefreshScheduled = true
    addEvent(function()
        if self and not self:isDestroyed() and self._sidebarFreeSpaceRefreshScheduled then
            self._sidebarFreeSpaceRefreshScheduled = nil
            self:refreshSidebarFreeSpace()
        end
    end)
end

function UIMiniWindowContainer:refreshSidebarFreeSpace()
    if self._sidebarFreeSpaceRefreshing then
        self._sidebarFreeSpaceRefreshPending = true
        return
    end

    self._sidebarFreeSpaceRefreshScheduled = nil
    self._sidebarFreeSpaceRefreshing = true

    local function finish()
        self._sidebarFreeSpaceRefreshing = nil
        if self._sidebarFreeSpaceRefreshPending then
            self._sidebarFreeSpaceRefreshPending = nil
            self:scheduleSidebarFreeSpaceRefresh()
        end
    end

    local filler = self._sidebarFreeSpaceWidget

    if not shouldManageSidebarFreeSpace(self) then
        if filler and not filler:isDestroyed() then
            filler:destroy()
        end
        self._sidebarFreeSpaceWidget = nil
        finish()
        return
    end

    local usedHeight = 0
    local children = self:getChildren()
    for i = 1, #children do
        local child = children[i]
        if child:isVisible() and not isSidebarFreeSpaceWidget(child) then
            -- Drag previews park a gap on the window margins, so it counts as used
            -- space until the drop settles.
            usedHeight = usedHeight + child:getHeight() + child:getMarginTop() + child:getMarginBottom()
        end
    end

    local availableHeight = self:getHeight() - self:getPaddingTop() - self:getPaddingBottom()
    local freeHeight = math.max(0, availableHeight - usedHeight)

    if freeHeight <= 0 then
        if filler and not filler:isDestroyed() then
            if filler:getParent() == self then
                self:moveChildToIndex(filler, self:getChildCount())
            end
            filler:hide()
            filler:setHeight(0)
        end
        finish()
        return
    end

    filler = ensureSidebarFreeSpaceWidget(self)
    if filler:getParent() ~= self then
        self:addChild(filler)
    else
        self:moveChildToIndex(filler, self:getChildCount())
    end

    -- Only touch the filler when something actually changed: resizing it feeds
    -- the layout hooks that scheduled this refresh in the first place.
    local freeWidth = math.max(0, self:getWidth() - self:getPaddingLeft() - self:getPaddingRight())
    if filler:getWidth() ~= freeWidth then
        filler:setWidth(freeWidth)
    end
    if filler:getHeight() ~= freeHeight then
        filler:setHeight(freeHeight)
    end
    if not filler:isExplicitlyVisible() then
        filler:show()
    end
    finish()
end

function UIMiniWindowContainer:fitAll(noRemoveChild)
    if not self:isVisible() then
        return
    end

    if self.ignoreFillAll then
        return
    end

    if not noRemoveChild then
        local children = self:getChildren()
        for i = #children, 1, -1 do
            if not isSidebarSystemWidget(children[i]) then
                noRemoveChild = children[i]
                break
            end
        end

        if not noRemoveChild then
            self:refreshSidebarFreeSpace()
            return
        end
    end

    local sumHeight = 0
    local children = self:getChildren()
    for i = 1, #children do
        if children[i]:isVisible() and not isSidebarSystemWidget(children[i]) then
            sumHeight = sumHeight + children[i]:getHeight()
        end
    end

    local selfHeight = self:getHeight() - (self:getPaddingTop() + self:getPaddingBottom())
    if sumHeight <= selfHeight then
        self:refreshSidebarFreeSpace()
        return
    end

    local removeChildren = {}

    -- try to resize noRemoveChild
    local maximumHeight = selfHeight - (sumHeight - noRemoveChild:getHeight())
    if noRemoveChild:isResizeable() and noRemoveChild:getMinimumHeight() <= maximumHeight then
        sumHeight = sumHeight - noRemoveChild:getHeight() + maximumHeight
        addEvent(function()
            noRemoveChild:setHeight(maximumHeight)
        end)
    end

    -- try to remove no-save widget
    for i = #children, 1, -1 do
        if sumHeight <= selfHeight then
            break
        end

        local child = children[i]
        if child ~= noRemoveChild and not isSidebarSystemWidget(child) and not child.save then
            local childHeight = child:getHeight()
            sumHeight = sumHeight - childHeight
            table.insert(removeChildren, child)
        end
    end

    -- try to remove save widget
    for i = #children, 1, -1 do
        if sumHeight <= selfHeight then
            break
        end

        local child = children[i]
        if child ~= noRemoveChild and not isSidebarSystemWidget(child) and child:isVisible() then
            local childHeight = child:getHeight()
            sumHeight = sumHeight - childHeight
            table.insert(removeChildren, child)
        end
    end

    for i = 1, #removeChildren do
        removeChildren[i]:close()
    end

    self:refreshSidebarFreeSpace()
end

function UIMiniWindowContainer:redistributeChildrenWidths()
    if not self.isHorizontalPanel then
        return
    end

    if self:isDestroyed() or not self:isVisible() then
        return
    end

    local children = self:getChildren()
    local visibleChildren = {}
    for i = 1, #children do
        if children[i]:isExplicitlyVisible() and not isSidebarSystemWidget(children[i]) then
            visibleChildren[#visibleChildren + 1] = children[i]
        end
    end

    local count = #visibleChildren
    if count == 0 then
        return
    end

    local availableWidth = self:getWidth() - self:getPaddingLeft() - self:getPaddingRight()
    if availableWidth <= 0 then
        return
    end

    local widthPerChild = math.floor(availableWidth / count)
    if widthPerChild <= 0 then
        return
    end

    for i = 1, count do
        visibleChildren[i]:setWidth(widthPerChild)
    end
end

function UIMiniWindowContainer:fits(child, minContentHeight, maxContentHeight)
    if self.ignoreFillAll then
        return 0
    end

    local containerPanel = child:getChildById('contentsPanel')
    local indispensableHeight = containerPanel:getMarginTop() + containerPanel:getMarginBottom() +
        containerPanel:getPaddingTop() + containerPanel:getPaddingBottom()

    local totalHeight = 0
    local children = self:getChildren()
    for i = 1, #children do
        if children[i]:isVisible() and not isSidebarSystemWidget(children[i]) then
            totalHeight = totalHeight + children[i]:getHeight()
        end
    end

    local available = self:getHeight() - (self:getPaddingTop() + self:getPaddingBottom()) - totalHeight

    if maxContentHeight > 0 and available >= (maxContentHeight + indispensableHeight) then
        return maxContentHeight + indispensableHeight
    elseif available >= (minContentHeight + indispensableHeight) then
        return available
    else
        return -1
    end
end

function UIMiniWindowContainer:onDrop(widget, mousePos)
    if self.isHorizontalPanel and not widget.allowHorizontalDrop then
        return true
    end

    if self.onlyPhantomDrop and not widget.moveOnlyToMain then
        return true
    end

    if widget.moveOnlyToMain and not self.onlyPhantomDrop
        and not (widget.allowHorizontalDrop and self.isHorizontalPanel) then
        return true
    end

    if widget.UIMiniWindowContainer then
        local floatingParent = widget:getParent()
        if floatingParent == self then
            if self.isHorizontalPanel and type(self.redistributeChildrenWidths) == 'function' then
                self:redistributeChildrenWidths()
            end
            return true
        end

        if self.isHorizontalPanel then
            if UIMiniWindow and UIMiniWindow.destroyDropPlaceholder then
                UIMiniWindow.destroyDropPlaceholder()
            end
            if floatingParent then
                floatingParent:removeChild(widget)
            end
            self:addChild(widget)
            widget:setOpacity(widget._origOpacity or 1.0)
            widget._origOpacity = nil
            widget.smoothDropActive = nil
            self:redistributeChildrenWidths()
            self:saveChildren()
            signalcall(widget.onContainerChanged, widget, self)
            return true
        end

        local startPos = widget:getPosition()
        local targetIndex

        local placeholder = UIMiniWindow and UIMiniWindow.getDropPlaceholder and UIMiniWindow.getDropPlaceholder()
        local hasPlaceholder = placeholder and not placeholder:isDestroyed() and placeholder:getParent() == self

        if hasPlaceholder then
            targetIndex = self:getChildIndex(placeholder)
        else
            -- Land before the free-space filler, it always has to stay last.
            targetIndex = self:getChildCount() + 1
            local filler = self._sidebarFreeSpaceWidget
            if filler and not filler:isDestroyed() and filler:getParent() == self then
                targetIndex = targetIndex - 1
            end
        end

        -- Collapse drag preview margins before layout; leftover top/bottom
        -- margin looks like permanent empty space between docked windows.
        for _, child in ipairs(self:getChildren()) do
            if child and not child:isDestroyed() and not isSidebarSystemWidget(child) then
                g_effects.cancelValue(child)
                if child:getMarginTop() ~= 0 then
                    child:setMarginTop(0)
                end
                if child:getMarginBottom() ~= 0 then
                    child:setMarginBottom(0)
                end
            end
        end

        local targetPos
        if hasPlaceholder then
            targetPos = placeholder:getPosition()
        else
            if floatingParent then
                floatingParent:removeChild(widget)
            end
            self:insertChild(targetIndex, widget)
            applyBotWindowColumnWidth(widget)
            self:fitAll(widget)
            targetPos = widget:getPosition()
            self:removeChild(widget)
        end

        if floatingParent and widget:getParent() ~= floatingParent then
            floatingParent:addChild(widget)
        elseif not floatingParent and widget:getParent() ~= rootWidget then
            rootWidget:addChild(widget)
        end

        widget:setPosition(startPos)
        widget.smoothDropActive = true

        g_effects.moveTo(widget, targetPos, 95, function()
            if UIMiniWindow and UIMiniWindow.destroyDropPlaceholder then
                UIMiniWindow.destroyDropPlaceholder()
            end

            if not widget or widget:isDestroyed() or not widget.smoothDropActive then
                if widget and not widget:isDestroyed() then
                    widget:setOpacity(widget._origOpacity or 1.0)
                    widget._origOpacity = nil
                end
                return
            end

            local parent = widget:getParent()
            if parent then
                parent:removeChild(widget)
            end

            self:insertChild(targetIndex, widget)

            applyBotWindowColumnWidth(widget)

            self:fitAll(widget)
            self:saveChildren()
            widget:setOpacity(widget._origOpacity or 1.0)
            widget._origOpacity = nil
            widget.smoothDropActive = nil
            signalcall(widget.onContainerChanged, widget, self)

            for _, child in ipairs(self:getChildren()) do
                if child and not child:isDestroyed() and not isSidebarSystemWidget(child) then
                    if child:getMarginTop() ~= 0 then
                        child:setMarginTop(0)
                    end
                    if child:getMarginBottom() ~= 0 then
                        child:setMarginBottom(0)
                    end
                end
            end
        end)

        return true
    end
end

function UIMiniWindowContainer:swapInsert(widget, index)
    local oldParent = widget:getParent()
    local oldIndex = self:getChildIndex(widget)

    if oldParent == self and oldIndex ~= index then
        local oldWidget = self:getChildByIndex(index)
        if oldWidget then
            self:removeChild(oldWidget)
            self:insertChild(oldIndex, oldWidget)
        end
        self:removeChild(widget)
        self:insertChild(index, widget)
    end
end

function UIMiniWindowContainer:scheduleInsert(widget, index)
    if index - 1 > self:getChildCount() then
        if self.scheduledWidgets[index] then
            pdebug('replacing scheduled widget id ' .. widget:getId())
        end
        self.scheduledWidgets[index] = widget
    else
        local oldParent = widget:getParent()
        if oldParent ~= self then
            if oldParent then
                oldParent:removeChild(widget)
            end
            self:insertChild(index, widget)
        else
            local targetIndex = math.min(index, self:getChildCount())
            if targetIndex >= 1 and targetIndex <= self:getChildCount() then
                self:moveChildToIndex(widget, targetIndex)
            end
        end

        while true do
            local placed = false
            for nIndex, nWidget in pairs(self.scheduledWidgets) do
                if nIndex - 1 <= self:getChildCount() then
                    local nOldParent = nWidget:getParent()
                    if nOldParent ~= self then
                        if nOldParent then
                            nOldParent:removeChild(nWidget)
                        end
                        self:insertChild(nIndex, nWidget)
                    else
                        local targetIndex = math.min(nIndex, self:getChildCount())
                        if targetIndex >= 1 and targetIndex <= self:getChildCount() then
                            self:moveChildToIndex(nWidget, targetIndex)
                        end
                    end
                    self.scheduledWidgets[nIndex] = nil
                    placed = true
                    break
                end
            end
            if not placed then
                break
            end
        end
    end
end

function UIMiniWindowContainer:order()
    local children = self:getChildren()
    for i = 1, #children do
        if not children[i].miniLoaded and not isSidebarSystemWidget(children[i]) then
            return
        end
    end

    for i = 1, #children do
        if children[i].miniIndex then
            self:swapInsert(children[i], children[i].miniIndex)
        end
    end
end

function UIMiniWindowContainer:saveChildren()
    local children = self:getChildren()
    local ignoreIndex = 0
    for i = 1, #children do
        if isSidebarSystemWidget(children[i]) then
            ignoreIndex = ignoreIndex + 1
        elseif children[i].save then
            children[i]:saveParentIndex(self:getId(), i - ignoreIndex)
        else
            ignoreIndex = ignoreIndex + 1
        end
    end
end
