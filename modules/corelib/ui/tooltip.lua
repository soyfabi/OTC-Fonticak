-- @docclass
g_tooltip = {}

-- private variables
local toolTipLabel
local SpecialToolTipLabel
local currentHoveredWidget
local isTrackingMouse = false
local isTrackingSpecialMouse = false
local pendingHoveredWidget = nil
local pendingTooltipEvent = nil
local pendingHideEvent = nil
local pendingHideScheduleEvent = nil
local pendingSpecialHideScheduleEvent = nil
local pendingTransitionEvent = nil
local pendingTransitionText = nil
local pendingSpecialTransitionEvent = nil

-- private functions
local function moveToolTip(first)
    if not first and (not toolTipLabel:isVisible() or toolTipLabel:getOpacity() < 0.01) then
        return
    end

    local pos = g_window.getMousePosition()
    local windowSize = g_window.getSize()
    local labelSize = toolTipLabel:getSize()

    pos.x = pos.x + 1
    pos.y = pos.y + 1

    if windowSize.width - (pos.x + labelSize.width) < 10 then
        pos.x = pos.x - labelSize.width - 3
    else
        pos.x = pos.x + 10
    end

    if windowSize.height - (pos.y + labelSize.height) < 10 then
        pos.y = pos.y - labelSize.height - 3
    else
        pos.y = pos.y + 10
    end

    if pos.x < 4 then
        pos.x = 4
    end
    if pos.y < 4 then
        pos.y = 4
    end

    toolTipLabel:setPosition(pos)
end

local function moveSpecialToolTip(first)
    if not first and (not SpecialToolTipLabel:isVisible() or SpecialToolTipLabel:getOpacity() < 0.01) then
        return
    end

    local pos = g_window.getMousePosition()
    local windowSize = g_window.getSize()
    local labelSize = SpecialToolTipLabel:getSize()

    pos.x = pos.x + 1
    pos.y = pos.y + 1

    if windowSize.width - (pos.x + labelSize.width) < 10 then
        pos.x = pos.x - labelSize.width - 3
    else
        pos.x = pos.x + 10
    end

    if windowSize.height - (pos.y + labelSize.height) < 10 then
        pos.y = pos.y - labelSize.height - 3
    else
        pos.y = pos.y + 10
    end

    if pos.x < 4 then
        pos.x = 4
    end
    if pos.y < 4 then
        pos.y = 4
    end

    SpecialToolTipLabel:setPosition(pos)
end

local function startTrackingMouseMove()
    if not isTrackingMouse then
        isTrackingMouse = true
        connect(rootWidget, {
            onMouseMove = moveToolTip
        })
    end
end

local function stopTrackingMouseMove()
    if isTrackingMouse then
        isTrackingMouse = false
        disconnect(rootWidget, {
            onMouseMove = moveToolTip
        })
    end
end

local function startTrackingSpecialMouseMove()
    if not isTrackingSpecialMouse then
        isTrackingSpecialMouse = true
        connect(rootWidget, {
            onMouseMove = moveSpecialToolTip
        })
    end
end

local function stopTrackingSpecialMouseMove()
    if isTrackingSpecialMouse then
        isTrackingSpecialMouse = false
        disconnect(rootWidget, {
            onMouseMove = moveSpecialToolTip
        })
    end
end

local defaultTooltipDelay = 500

local function getWidgetTooltipDelay(widget)
    if not widget then
        return defaultTooltipDelay
    end
    if widget.tooltipDelay then
        return tonumber(widget.tooltipDelay) or defaultTooltipDelay
    end
    return defaultTooltipDelay
end

local function cancelPendingTransition()
    if pendingTransitionEvent then
        removeEvent(pendingTransitionEvent)
        pendingTransitionEvent = nil
    end
    pendingTransitionText = nil
end

local function cancelPendingSpecialTransition()
    if pendingSpecialTransitionEvent then
        removeEvent(pendingSpecialTransitionEvent)
        pendingSpecialTransitionEvent = nil
    end
end

local function isTooltipActive()
    if pendingTransitionEvent ~= nil or pendingSpecialTransitionEvent ~= nil then
        return true
    end
    if pendingHideEvent ~= nil then
        return true
    end
    if toolTipLabel and toolTipLabel:isVisible() and toolTipLabel:getOpacity() > 0.05 then
        return true
    end
    if SpecialToolTipLabel and SpecialToolTipLabel:isVisible() and SpecialToolTipLabel:getOpacity() > 0.05 then
        return true
    end
    return false
end

local function cancelPendingTooltip()
    if pendingTooltipEvent then
        removeEvent(pendingTooltipEvent)
        pendingTooltipEvent = nil
    end
    pendingHoveredWidget = nil
end

local function cancelPendingHide()
    if pendingHideEvent then
        removeEvent(pendingHideEvent)
        pendingHideEvent = nil
    end
end

local function displayWidgetTooltip(widget)
    if not widget or g_mouse.isPressed() then
        return
    end

    if widget:isDestroyed() or not widget:isVisible() then
        return
    end

    if not widget:isHovered() and not widget:containsPoint(g_window.getMousePosition()) then
        return
    end

    cancelPendingHide()
    currentHoveredWidget = widget

    if widget.tooltip then
        g_tooltip.display(widget.tooltip)
    elseif widget.specialtooltip then
        g_tooltip.displaySpecial(widget.specialtooltip)
    elseif widget.parseColoreDisplay then
        g_tooltip.parseColoreDisplay(widget.parseColoreDisplay)
    end
end

local function scheduleTooltip(widget)
    if not widget or g_mouse.isPressed() then
        return
    end

    cancelPendingHide()
    cancelPendingTooltip()

    pendingHoveredWidget = widget

    -- Fluid transition: if a tooltip is already active or in grace window, switch instantly
    local delay = isTooltipActive() and 0 or getWidgetTooltipDelay(widget)

    if delay <= 0 then
        displayWidgetTooltip(widget)
        pendingHoveredWidget = nil
    else
        pendingTooltipEvent = scheduleEvent(function()
            displayWidgetTooltip(widget)
            pendingTooltipEvent = nil
            pendingHoveredWidget = nil
        end, delay)
    end
end

local function scheduleHide(instant)
    cancelPendingHide()
    if instant then
        cancelPendingTransition()
        cancelPendingSpecialTransition()
        g_tooltip.hide(true)
        g_tooltip.hideSpecial(true)
        return
    end

    -- 80ms grace window prevents flickering when crossing margins/borders between adjacent items
    pendingHideEvent = scheduleEvent(function()
        pendingHideEvent = nil
        if not currentHoveredWidget or not currentHoveredWidget:isHovered() then
            g_tooltip.hide()
            g_tooltip.hideSpecial()
        end
    end, 80)
end

local function onWidgetDestroy(widget)
    if widget == pendingHoveredWidget then
        cancelPendingTooltip()
    end
    if widget == currentHoveredWidget then
        cancelPendingHide()
        cancelPendingTransition()
        cancelPendingSpecialTransition()
        g_tooltip.hide(true)
        g_tooltip.hideSpecial(true)
    end
end

local function onWidgetVisibilityChange(widget, visible)
    if not visible then
        if pendingHoveredWidget and (pendingHoveredWidget == widget or pendingHoveredWidget:isDestroyed() or not pendingHoveredWidget:isVisible()) then
            cancelPendingTooltip()
        end
        if currentHoveredWidget and (currentHoveredWidget == widget or currentHoveredWidget:isDestroyed() or not currentHoveredWidget:isVisible()) then
            cancelPendingHide()
            cancelPendingTransition()
            cancelPendingSpecialTransition()
            g_tooltip.hide(true)
            g_tooltip.hideSpecial(true)
        end
    end
end

local function onWidgetMousePress(widget, mousePos, button)
    cancelPendingTooltip()
    cancelPendingHide()
    cancelPendingTransition()
    cancelPendingSpecialTransition()
    if currentHoveredWidget then
        g_tooltip.hide(true)
        g_tooltip.hideSpecial(true)
    end
end

local function onWidgetHoverChange(widget, hovered)
    if hovered then
        if (widget.tooltip or widget.specialtooltip or widget.parseColoreDisplay) and not g_mouse.isPressed() then
            scheduleTooltip(widget)
        end
    else
        if widget == pendingHoveredWidget then
            cancelPendingTooltip()
        end
        if widget == currentHoveredWidget then
            scheduleHide()
        end
    end
end

local function onWidgetStyleApply(widget, styleName, styleNode)
    if styleNode.tooltip then
        widget.tooltip = styleNode.tooltip
    end
    if styleNode.specialtooltip then
        widget.specialtooltip = {{header = '', info = styleNode.specialtooltip}}
    end
    if styleNode['tooltip-delay'] then
        widget.tooltipDelay = tonumber(styleNode['tooltip-delay'])
    end

    local tooltipWidget = widget:getChildById('toolTipWidget')
    if widget:getId() == 'toolTipWidget' then
        tooltipWidget = widget
        widget = widget:getParent()
    end
    if tooltipWidget then
        if widget.tooltip then
            tooltipWidget.tooltip = widget.tooltip
            widget.tooltip = nil
        end
        if widget.specialtooltip then
            tooltipWidget.specialtooltip = widget.specialtooltip
            widget.specialtooltip = nil
        end
        if widget.parseColoreDisplay then
            tooltipWidget.parseColoreDisplay = widget.parseColoreDisplay
            widget.parseColoreDisplay = nil
        end
        if tooltipWidget.tooltip or tooltipWidget.specialtooltip or widget.parseColoreDisplay then
            tooltipWidget:setOpacity(1)
        else
            tooltipWidget:setOpacity(0.4)
        end
    end
end

-- public functions
function g_tooltip.init()
    connect(UIWidget, {
        onStyleApply = onWidgetStyleApply,
        onHoverChange = onWidgetHoverChange,
        onDestroy = onWidgetDestroy,
        onVisibilityChange = onWidgetVisibilityChange,
        onMousePress = onWidgetMousePress
    })

    addEvent(function()
        toolTipLabel = g_ui.createWidget('UILabel', rootWidget)
        toolTipLabel:setId('toolTip')
        toolTipLabel:setFont('Verdana Bold-11px')
        toolTipLabel:setBackgroundColor('#c0c0c0')
        toolTipLabel:setTextAlign(AlignLeft)
        toolTipLabel:setColor('#3f3f3f')
        toolTipLabel:setBorderColor('#000000')
        toolTipLabel:setBorderWidth(1)
        toolTipLabel:setTextOffset(topoint('4 2'))
        toolTipLabel:hide()
        toolTipLabel:setPhantom(true)
    end)

    addEvent(function()
        SpecialToolTipLabel = g_ui.createWidget('UIWidget', rootWidget)
        SpecialToolTipLabel:setBackgroundColor('#c0c0c0ff')
        SpecialToolTipLabel:setBorderColor("#4c4c4cff")
        SpecialToolTipLabel:setBorderWidth(1)
        SpecialToolTipLabel:setWidth(455)
        SpecialToolTipLabel:setPaddingTop(2)
        SpecialToolTipLabel:hide()
        SpecialToolTipLabel:setPhantom(true)
    end)
end

function g_tooltip.terminate()
    disconnect(UIWidget, {
        onStyleApply = onWidgetStyleApply,
        onHoverChange = onWidgetHoverChange,
        onDestroy = onWidgetDestroy,
        onVisibilityChange = onWidgetVisibilityChange,
        onMousePress = onWidgetMousePress
    })

    cancelPendingTooltip()
    cancelPendingHide()
    cancelPendingTransition()
    cancelPendingSpecialTransition()
    stopTrackingMouseMove()
    stopTrackingSpecialMouseMove()

    if pendingHideScheduleEvent then
        removeEvent(pendingHideScheduleEvent)
        pendingHideScheduleEvent = nil
    end
    if pendingSpecialHideScheduleEvent then
        removeEvent(pendingSpecialHideScheduleEvent)
        pendingSpecialHideScheduleEvent = nil
    end

    currentHoveredWidget = nil
    if toolTipLabel then
        toolTipLabel:destroy()
        toolTipLabel = nil
    end
    if SpecialToolTipLabel then
        SpecialToolTipLabel:destroy()
        SpecialToolTipLabel = nil
    end

    g_tooltip = nil
end

function g_tooltip.display(text)
    if not text then
        return
    end

    if type(text) == "table" then
        g_tooltip.displaySpecial(text)
        return
    end

    -- Convert to string if not already
    if type(text) ~= "string" then
        text = tostring(text)
    end

    if text:len() == 0 then
        return
    end

    if not toolTipLabel then
        return
    end

    cancelPendingHide()
    cancelPendingTransition()
    if pendingHideScheduleEvent then
        removeEvent(pendingHideScheduleEvent)
        pendingHideScheduleEvent = nil
    end

    local isCurrentlyVisible = toolTipLabel:isVisible() and toolTipLabel:getOpacity() > 0.05
    local isSameText = isCurrentlyVisible and (toolTipLabel:getText() == text)

    if isSameText then
        g_effects.cancelFade(toolTipLabel)
        toolTipLabel:setOpacity(1.0)
        toolTipLabel:show()
        moveToolTip(true)
        startTrackingMouseMove()
        return
    end

    if isCurrentlyVisible then
        -- Changing tooltip: smooth fade-out first, then switch text and fade-in
        local fadeOutTime = 70
        g_effects.fadeOut(toolTipLabel, fadeOutTime)
        startTrackingMouseMove()

        pendingTransitionText = text
        pendingTransitionEvent = scheduleEvent(function()
            pendingTransitionEvent = nil
            if pendingTransitionText ~= text then
                return
            end
            pendingTransitionText = nil

            toolTipLabel:setFont('Verdana Bold-11px')
            toolTipLabel:setColor('#3f3f3f')
            toolTipLabel:setBackgroundColor('#c0c0c0')
            toolTipLabel:setBorderColor('#000000')
            toolTipLabel:setBorderWidth(1)
            toolTipLabel:setText(text)
            toolTipLabel:resizeToText()
            toolTipLabel:resize(toolTipLabel:getWidth() + 8, toolTipLabel:getHeight() + 4)
            toolTipLabel:show()
            toolTipLabel:raise()
            toolTipLabel:enable()
            toolTipLabel:setOpacity(0)
            moveToolTip(true)
            g_effects.fadeIn(toolTipLabel, 70)
        end, fadeOutTime)
    else
        g_effects.cancelFade(toolTipLabel)
        toolTipLabel:setFont('Verdana Bold-11px')
        toolTipLabel:setColor('#3f3f3f')
        toolTipLabel:setBackgroundColor('#c0c0c0')
        toolTipLabel:setBorderColor('#000000')
        toolTipLabel:setBorderWidth(1)
        toolTipLabel:setText(text)
        toolTipLabel:resizeToText()
        toolTipLabel:resize(toolTipLabel:getWidth() + 8, toolTipLabel:getHeight() + 4)
        toolTipLabel:show()
        toolTipLabel:raise()
        toolTipLabel:enable()
        toolTipLabel:setOpacity(0)
        moveToolTip(true)
        g_effects.fadeIn(toolTipLabel, 70)
        startTrackingMouseMove()
    end
end

function g_tooltip.parseColoreDisplay(text)
    if text == nil or text:len() == 0 then
        return
    end
    if not toolTipLabel then
        return
    end

    cancelPendingHide()
    cancelPendingTransition()
    if pendingHideScheduleEvent then
        removeEvent(pendingHideScheduleEvent)
        pendingHideScheduleEvent = nil
    end

    local isCurrentlyVisible = toolTipLabel:isVisible() and toolTipLabel:getOpacity() > 0.05

    if isCurrentlyVisible then
        local fadeOutTime = 70
        g_effects.fadeOut(toolTipLabel, fadeOutTime)
        startTrackingMouseMove()

        pendingTransitionEvent = scheduleEvent(function()
            pendingTransitionEvent = nil
            toolTipLabel:parseColoredText(text)
            toolTipLabel:resizeToText()
            toolTipLabel:resize(toolTipLabel:getWidth() + 4, toolTipLabel:getHeight() + 4)
            toolTipLabel:show()
            toolTipLabel:raise()
            toolTipLabel:enable()
            toolTipLabel:setOpacity(0)
            moveToolTip(true)
            g_effects.fadeIn(toolTipLabel, 70)
        end, fadeOutTime)
    else
        g_effects.cancelFade(toolTipLabel)
        toolTipLabel:parseColoredText(text)
        toolTipLabel:resizeToText()
        toolTipLabel:resize(toolTipLabel:getWidth() + 4, toolTipLabel:getHeight() + 4)
        toolTipLabel:show()
        toolTipLabel:raise()
        toolTipLabel:enable()
        toolTipLabel:setOpacity(0)
        moveToolTip(true)
        g_effects.fadeIn(toolTipLabel, 70)
        startTrackingMouseMove()
    end
end

function g_tooltip.displaySpecial(special)
    if not SpecialToolTipLabel then
        return
    end

    cancelPendingHide()
    cancelPendingSpecialTransition()
    if pendingSpecialHideScheduleEvent then
        removeEvent(pendingSpecialHideScheduleEvent)
        pendingSpecialHideScheduleEvent = nil
    end

    local function applySpecialContent()
        local width = 4
        local height = 4
        SpecialToolTipLabel:destroyChildren()
        for index, data in ipairs(special) do
            local headerW = 0
            local headerH = 0
            if string.len(data.header) > 0 then
                local header = g_ui.createWidget('UILabel', SpecialToolTipLabel)
                if index == 1 then
                    header:addAnchor(AnchorTop, 'parent', AnchorTop)
                else
                    header:addAnchor(AnchorTop, 'prev', AnchorBottom)
                end
                header:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                header:setText(data.header)
                header:setTextAlign(AlignLeft)
                header:setColor("#4c4c4cff")
                header:setFont('verdana-11px-monochrome-underline')
                header:setTextOffset(topoint('5 0'))
                header:resizeToText()
                header:resize(header:getWidth(), header:getHeight())
                headerW = header:getWidth()
                headerH = header:getHeight()
            end

            local info = g_ui.createWidget('UILabel', SpecialToolTipLabel)
            if string.len(data.header) > 0 then
                info:addAnchor(AnchorTop, 'prev', AnchorBottom)
            else
                info:addAnchor(AnchorTop, 'parent', AnchorTop)
            end
            info:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            info:setText(data.info:wrap(445))
            info:setTextAlign(AlignLeft)
            info:setColor("#4c4c4cff")
            info:setTextOffset(topoint('5 0'))
            info:resizeToText()
            info:resize(info:getWidth(), info:getHeight())
            width = width + math.max(headerW, info:getWidth())
            height = height + headerH + info:getHeight()
        end

        SpecialToolTipLabel:resize(width, height)
        SpecialToolTipLabel:show()
        SpecialToolTipLabel:raise()
        SpecialToolTipLabel:enable()
        SpecialToolTipLabel:setOpacity(0)
        moveSpecialToolTip(true)
        g_effects.fadeIn(SpecialToolTipLabel, 70)
        startTrackingSpecialMouseMove()
    end

    local isCurrentlyVisible = SpecialToolTipLabel:isVisible() and SpecialToolTipLabel:getOpacity() > 0.05

    if isCurrentlyVisible then
        local fadeOutTime = 70
        g_effects.fadeOut(SpecialToolTipLabel, fadeOutTime)
        startTrackingSpecialMouseMove()

        pendingSpecialTransitionEvent = scheduleEvent(function()
            pendingSpecialTransitionEvent = nil
            applySpecialContent()
        end, fadeOutTime)
    else
        g_effects.cancelFade(SpecialToolTipLabel)
        applySpecialContent()
    end
end

function g_tooltip.hide(instant)
    cancelPendingTooltip()
    cancelPendingTransition()
    cancelPendingHide()
    if pendingHideScheduleEvent then
        removeEvent(pendingHideScheduleEvent)
        pendingHideScheduleEvent = nil
    end

    currentHoveredWidget = nil
    if toolTipLabel then
        if instant then
            g_effects.cancelFade(toolTipLabel)
            toolTipLabel:setOpacity(0)
            toolTipLabel:hide()
            stopTrackingMouseMove()
        else
            g_effects.fadeOut(toolTipLabel, 80)
            pendingHideScheduleEvent = scheduleEvent(function()
                pendingHideScheduleEvent = nil
                if toolTipLabel and not currentHoveredWidget then
                    toolTipLabel:hide()
                    stopTrackingMouseMove()
                end
            end, 90)
        end
    else
        stopTrackingMouseMove()
    end
end

function g_tooltip.hideSpecial(instant)
    cancelPendingTooltip()
    cancelPendingSpecialTransition()
    cancelPendingHide()
    if pendingSpecialHideScheduleEvent then
        removeEvent(pendingSpecialHideScheduleEvent)
        pendingSpecialHideScheduleEvent = nil
    end

    currentHoveredWidget = nil
    if SpecialToolTipLabel then
        if instant then
            g_effects.cancelFade(SpecialToolTipLabel)
            SpecialToolTipLabel:setOpacity(0)
            SpecialToolTipLabel:hide()
            stopTrackingSpecialMouseMove()
        else
            g_effects.fadeOut(SpecialToolTipLabel, 80)
            pendingSpecialHideScheduleEvent = scheduleEvent(function()
                pendingSpecialHideScheduleEvent = nil
                if SpecialToolTipLabel and not currentHoveredWidget then
                    SpecialToolTipLabel:hide()
                    stopTrackingSpecialMouseMove()
                end
            end, 90)
        end
    else
        stopTrackingSpecialMouseMove()
    end
end

-- @docclass UIWidget @{

-- UIWidget extensions
function UIWidget:setTooltip(text)
    local tooltipWidget = self:getChildById('toolTipWidget')
    if tooltipWidget then
        tooltipWidget.tooltip = text
    else
        self.tooltip = text
    end
end

function UIWidget:parseColoreDisplayToolTip(text)
    local tooltipWidget = self:getChildById('toolTipWidget')
    if tooltipWidget then
        tooltipWidget.parseColoreDisplay = text
    else
        self.parseColoreDisplay = text
    end
end

function UIWidget:setSpecialToolTip(special)
    if type(special) == "string" then
        special = {{header = '', info = special}}
    end
    self.specialtooltip = special
end

function UIWidget:removeTooltip()
    self.tooltip = nil
    self.specialtooltip = nil
    self.parseColoreDisplay = nil
end

function UIWidget:getTooltip()
    return self.tooltip
end

function UIWidget:getSpecialTooltip()
    return self.specialtooltip
end

function UIWidget:setTooltipDelay(delay)
    self.tooltipDelay = tonumber(delay)
end

function UIWidget:getTooltipDelay()
    return self.tooltipDelay
end

-- @}

g_tooltip.init()
connect(g_app, {
    onTerminate = g_tooltip.terminate
})
