-- @docclass
UIMiniWindowContainer = extends(UIWidget, 'UIMiniWindowContainer')

local SIDEBAR_FREE_SPACE_IMAGE = '/images/ui/2pixel_up_frame_borderimage'
local SIDEBAR_FREE_SPACE_BORDER = 2

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
        end
    })
    return container
end

local function isSidebarFreeSpaceWidget(widget)
    return widget and widget._sidebarFreeSpaceWidget == true
end

local function isSidebarSystemWidget(widget)
    return isSidebarFreeSpaceWidget(widget)
end

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
    if self._sidebarFreeSpaceRefreshScheduled or self._sidebarFreeSpaceRefreshing then
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
        return
    end

    self._sidebarFreeSpaceRefreshScheduled = nil
    self._sidebarFreeSpaceRefreshing = true

    local function finish()
        self._sidebarFreeSpaceRefreshing = nil
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
            usedHeight = usedHeight + child:getHeight()
        end
    end

    local availableHeight = self:getHeight() - self:getPaddingTop() - self:getPaddingBottom()
    local freeHeight = math.max(0, availableHeight - usedHeight)

    if freeHeight <= 0 then
        if filler and not filler:isDestroyed() then
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

    filler:setWidth(math.max(0, self:getWidth() - self:getPaddingLeft() - self:getPaddingRight()))
    filler:setHeight(freeHeight)
    filler:show()
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
    if (self.onlyPhantomDrop and not (widget.moveOnlyToMain)) or (widget.moveOnlyToMain and not (self.onlyPhantomDrop)) then
        return true
    end

    if widget.UIMiniWindowContainer then
        local floatingParent = widget:getParent()
        if floatingParent == self then
            return true
        end

        local startPos = widget:getPosition()
        local targetIndex

        if widget.movedWidget then
            local index = self:getChildIndex(widget.movedWidget)
            targetIndex = index + widget.movedIndex
        else
            targetIndex = self:getChildCount() + 1
        end

        -- Collapse drag preview margins before layout; leftover top/bottom
        -- margin looks like permanent empty space between docked windows.
        for _, child in ipairs(self:getChildren()) do
            if child and not child:isDestroyed() and not child._sidebarFreeSpaceWidget then
                g_effects.cancelValue(child)
                if child:getMarginTop() ~= 0 then
                    child:setMarginTop(0)
                end
                if child:getMarginBottom() ~= 0 then
                    child:setMarginBottom(0)
                end
            end
        end
        widget.movedWidget = nil
        widget.setMovedChildMargin = nil
        widget.movedOldMargin = nil
        widget.movedIndex = nil

        if floatingParent then
            floatingParent:removeChild(widget)
        end

        self:insertChild(targetIndex, widget)

        local parentId = widget:getParent() and widget:getParent():getId() or ''
        if widget:getId() == 'botWindow' and
            (parentId == 'gameLeftPanel' or parentId:find('^gameLeftExtraPanel') or parentId:find('^gameRightExtraPanel')) then
            widget:getParent():setWidth(190)
        end
        self:fitAll(widget)

        local targetPos = widget:getPosition()
        self:removeChild(widget)

        if floatingParent then
            floatingParent:addChild(widget)
        else
            rootWidget:addChild(widget)
        end

        widget:setPosition(startPos)
        widget.smoothDropActive = true

        g_effects.moveTo(widget, targetPos, 95, function()
            if not widget or widget:isDestroyed() or not widget.smoothDropActive then
                return
            end

            local parent = widget:getParent()
            if parent then
                parent:removeChild(widget)
            end

            self:insertChild(targetIndex, widget)

            local droppedParentId = widget:getParent() and widget:getParent():getId() or ''
            if widget:getId() == 'botWindow' and
                (droppedParentId == 'gameLeftPanel' or droppedParentId:find('^gameLeftExtraPanel') or
                    droppedParentId:find('^gameRightExtraPanel')) then
                widget:getParent():setWidth(190)
            end

            self:fitAll(widget)
            self:saveChildren()
            widget.smoothDropActive = nil

            for _, child in ipairs(self:getChildren()) do
                if child and not child:isDestroyed() and not child._sidebarFreeSpaceWidget then
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

            while true do
                local placed = false
                for nIndex, nWidget in pairs(self.scheduledWidgets) do
                    if nIndex - 1 <= self:getChildCount() then
                        self:insertChild(nIndex, nWidget)
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
