-- @docclass
g_tooltip = {}

-- private variables
local toolTipLabel
local SpecialToolTipLabel
local currentHoveredWidget
local clientHelpModeActive = false
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

local DEFAULT_TOOLTIP_FONT = 'Verdana Bold-11px'
local WHEEL_TOOLTIP_FONT = 'Verdana Bold-11px-wheel'
local WHEEL_FONT_OTFONT = '/fonts/otfont/Verdana Bold-11px-wheel.otfont'
local WHEEL_GRADE_ICON_SOURCE = '/images/game/wheel/icons-spell-grades'
local WHEEL_GRADE_CLIPS = {
    ['\1'] = '0 0 22 15',
    ['\2'] = '44 0 22 15',
    ['\3'] = '22 0 22 15',
    ['\4'] = '66 0 22 15',
}
local WHEEL_GRADE_ICON_WIDTH = 22
local WHEEL_GRADE_ICON_HEIGHT = 15
local WHEEL_GRADE_LINE_HEIGHT = 17
local WHEEL_GRADE_ICON_GAP = 4

local function ensureWheelTooltipFontLoaded()
    if g_fonts.fontExists(WHEEL_TOOLTIP_FONT) then
        return true
    end
    return g_fonts.importFont(WHEEL_FONT_OTFONT)
end

local function isColoredTextColorToken(value)
    if type(value) ~= 'string' then
        return false
    end
    if value:match('^#(%x+)$') then
        return true
    end
    local named = {
        alpha = true, black = true, white = true, red = true, darkRed = true,
        green = true, darkGreen = true, blue = true, darkBlue = true,
        pink = true, darkPink = true, yellow = true, darkYellow = true,
        teal = true, darkTeal = true, gray = true, darkGray = true,
        lightGray = true, orange = true
    }
    return named[value] == true
end

local function isColoredTextTable(value)
    if type(value) ~= 'table' or #value == 0 then
        return false
    end

    local first = value[1]
    if type(first) ~= 'string' then
        return false
    end

    if first:sub(1, 1) == '{' then
        return true
    end

    return type(value[2]) == 'string' and isColoredTextColorToken(value[2])
end

function g_tooltip.coloredTableHasGradeIcons(data)
    if type(data) ~= 'table' then
        return false
    end
    for i = 1, #data, 2 do
        local text = data[i]
        if type(text) == 'string' and text:find('[\1-\4]') then
            return true
        end
    end
    return false
end

local function parseWheelGradeLines(data)
    local lines = {}
    local line = { icon = nil, segments = {} }

    local function pushLine()
        if line.icon or #line.segments > 0 then
            lines[#lines + 1] = line
        end
        line = { icon = nil, segments = {} }
    end

    for i = 1, #data, 2 do
        local text = tostring(data[i] or '')
        local color = data[i + 1] or '#c0c0c0'
        local pos = 1
        while pos <= #text do
            local nl = text:find('\n', pos, true)
            local chunkEnd = nl and (nl - 1) or #text
            local chunk = text:sub(pos, chunkEnd)
            while #chunk > 0 and WHEEL_GRADE_CLIPS[chunk:sub(1, 1)] do
                line.icon = chunk:sub(1, 1)
                chunk = chunk:sub(2)
            end
            if chunk ~= '' then
                line.segments[#line.segments + 1] = { text = chunk, color = color }
            end
            if nl then
                pushLine()
                pos = nl + 1
            else
                break
            end
        end
    end
    pushLine()
    return lines
end

local function fillWheelGradeRows(parent, lines, textColorFallback)
    local y = 0
    local maxW = 0
    for _, line in ipairs(lines) do
        local x = 2
        local textOffsetY = y
        if line.icon and WHEEL_GRADE_CLIPS[line.icon] then
            local icon = g_ui.createWidget('UIWidget', parent)
            icon:setPhantom(true)
            icon:setSize({ width = WHEEL_GRADE_ICON_WIDTH, height = WHEEL_GRADE_ICON_HEIGHT })
            icon:addAnchor(AnchorTop, 'parent', AnchorTop)
            icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            icon:setMarginTop(y)
            icon:setMarginLeft(x)
            icon:setImageSource(WHEEL_GRADE_ICON_SOURCE)
            icon:setImageClip(WHEEL_GRADE_CLIPS[line.icon])
            icon:setImageSmooth(true)
            x = x + WHEEL_GRADE_ICON_WIDTH + WHEEL_GRADE_ICON_GAP
            textOffsetY = y + 1
        end

        local text = ''
        local color = textColorFallback or '#c0c0c0'
        for _, seg in ipairs(line.segments) do
            text = text .. seg.text
            if seg.color and seg.color ~= 'white' then
                color = seg.color
            end
        end

        if text ~= '' then
            local label = g_ui.createWidget('UILabel', parent)
            label:setPhantom(true)
            label:setFont('Verdana Bold-11px')
            label:setColor(color)
            label:setText(text)
            label:setTextAlign(AlignLeft)
            label:addAnchor(AnchorTop, 'parent', AnchorTop)
            label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            label:setMarginTop(textOffsetY)
            label:setMarginLeft(x)
            label:resizeToText()
            maxW = math.max(maxW, x + label:getWidth())
        else
            maxW = math.max(maxW, x)
        end
        y = y + WHEEL_GRADE_LINE_HEIGHT
    end
    return maxW, y
end

function g_tooltip.renderWheelGrades(widget, data)
    if not widget or widget:isDestroyed() or type(data) ~= 'table' then
        return
    end
    widget:destroyChildren()
    if widget.setText then
        widget:setText('')
    end
    fillWheelGradeRows(widget, parseWheelGradeLines(data), '#c0c0c0')
end

local function getWidgetTooltipFont(widget)
    if not widget then
        return nil
    end

    if widget.tooltipFont and widget.tooltipFont:len() > 0 then
        return widget.tooltipFont
    end

    local parent = widget:getParent()
    if parent and parent ~= widget then
        return getWidgetTooltipFont(parent)
    end

    return nil
end

local function applyTooltipFont(fontName)
    if not toolTipLabel then
        return
    end

    local resolvedFont = fontName or DEFAULT_TOOLTIP_FONT
    if resolvedFont == WHEEL_TOOLTIP_FONT then
        ensureWheelTooltipFontLoaded()
    end
    toolTipLabel:setFont(resolvedFont)
end

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

local function getWidgetTooltipContent(widget)
    if not widget then
        return nil
    end

    local tooltipWidget = widget:getChildById('toolTipWidget')
    local source = tooltipWidget or widget

    if source.tooltip then
        if isColoredTextTable(source.tooltip) then
            if g_tooltip.coloredTableHasGradeIcons(source.tooltip) then
                return source.tooltip, 'grade_icons'
            end
            return source.tooltip, 'colored_table'
        end
        if type(source.tooltip) == 'string' and source.tooltip:len() > 0 then
            return source.tooltip, 'display'
        end
    end
    if source.specialtooltip then
        return source.specialtooltip, 'special'
    end
    if source.parseColoreDisplay and source.parseColoreDisplay:len() > 0 then
        return source.parseColoreDisplay, 'colored'
    end
    return nil
end

local function widgetHasTooltipContent(widget)
    return getWidgetTooltipContent(widget) ~= nil
end

local function cancelPendingHide()
    if pendingHideEvent then
        removeEvent(pendingHideEvent)
        pendingHideEvent = nil
    end
end

local function displayWidgetTooltip(widget)
    if clientHelpModeActive then
        return false
    end

    if not widget or g_mouse.isPressed() then
        return false
    end

    if widget:isDestroyed() or not widget:isVisible() then
        return false
    end

    if not widget:isHovered() and not widget:containsPoint(g_window.getMousePosition()) then
        return false
    end

    local content, contentType = getWidgetTooltipContent(widget)
    if not content then
        return false
    end

    cancelPendingHide()
    currentHoveredWidget = widget

    if contentType == 'display' then
        g_tooltip.display(content, getWidgetTooltipFont(widget))
    elseif contentType == 'special' then
        g_tooltip.displaySpecial(content)
    elseif contentType == 'colored' then
        g_tooltip.parseColoreDisplay(content, getWidgetTooltipFont(widget))
    elseif contentType == 'colored_table' then
        g_tooltip.displayColoredTable(content, getWidgetTooltipFont(widget))
    elseif contentType == 'grade_icons' then
        g_tooltip.displayWheelGrades(content)
    end
    return true
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

local function scheduleTooltip(widget)
    if clientHelpModeActive then
        return
    end

    if not widget or g_mouse.isPressed() then
        return
    end

    if not widgetHasTooltipContent(widget) then
        if widget == pendingHoveredWidget then
            cancelPendingTooltip()
        end
        return
    end

    cancelPendingHide()
    cancelPendingTooltip()

    pendingHoveredWidget = widget

    -- Fluid transition: if a tooltip is already active or in grace window, switch instantly
    local delay = isTooltipActive() and 0 or getWidgetTooltipDelay(widget)

    if delay <= 0 then
        if not displayWidgetTooltip(widget) then
            scheduleHide()
        end
        pendingHoveredWidget = nil
    else
        pendingTooltipEvent = scheduleEvent(function()
            if not displayWidgetTooltip(widget) then
                scheduleHide()
            end
            pendingTooltipEvent = nil
            pendingHoveredWidget = nil
        end, delay)
    end
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
        if widgetHasTooltipContent(widget) and not g_mouse.isPressed() then
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
    if styleNode['tooltip-font'] then
        widget.tooltipFont = styleNode['tooltip-font']
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
        if widget.tooltipFont then
            tooltipWidget.tooltipFont = widget.tooltipFont
            widget.tooltipFont = nil
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
        SpecialToolTipLabel:setBorderColor('#000000ff')
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

function g_tooltip.display(text, fontName)
    if not text then
        return
    end

    if type(text) == "table" then
        if isColoredTextTable(text) then
            if g_tooltip.coloredTableHasGradeIcons(text) then
                g_tooltip.displayWheelGrades(text)
            else
                g_tooltip.displayColoredTable(text, fontName)
            end
            return
        end
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

    applyTooltipFont(fontName or DEFAULT_TOOLTIP_FONT)

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
        g_effects.cancelFade(toolTipLabel)
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

function g_tooltip.parseColoreDisplay(text, fontName)
    if text == nil or text:len() == 0 then
        return
    end
    if not toolTipLabel then
        return
    end

    applyTooltipFont(fontName or DEFAULT_TOOLTIP_FONT)

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
            applyTooltipFont(fontName or DEFAULT_TOOLTIP_FONT)
            toolTipLabel:parseColoredText(text, '#3f3f3f')
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
        toolTipLabel:parseColoredText(text, '#3f3f3f')
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

function g_tooltip.displayColoredTable(text, fontName)
    if not text or not toolTipLabel then
        return
    end

    local resolvedFont = fontName or WHEEL_TOOLTIP_FONT
    ensureWheelTooltipFontLoaded()
    applyTooltipFont(resolvedFont)

    cancelPendingHide()
    cancelPendingTransition()
    if pendingHideScheduleEvent then
        removeEvent(pendingHideScheduleEvent)
        pendingHideScheduleEvent = nil
    end

    local function showColoredTooltip()
        applyTooltipFont(resolvedFont)
        toolTipLabel:setColoredText(text)
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

    local isCurrentlyVisible = toolTipLabel:isVisible() and toolTipLabel:getOpacity() > 0.05

    if isCurrentlyVisible then
        local fadeOutTime = 70
        g_effects.fadeOut(toolTipLabel, fadeOutTime)
        startTrackingMouseMove()

        pendingTransitionEvent = scheduleEvent(function()
            pendingTransitionEvent = nil
            showColoredTooltip()
        end, fadeOutTime)
    else
        g_effects.cancelFade(toolTipLabel)
        showColoredTooltip()
    end
end

function g_tooltip.displayWheelGrades(data)
    if not SpecialToolTipLabel or type(data) ~= 'table' then
        return
    end

    cancelPendingHide()
    cancelPendingSpecialTransition()
    if pendingSpecialHideScheduleEvent then
        removeEvent(pendingSpecialHideScheduleEvent)
        pendingSpecialHideScheduleEvent = nil
    end
    if toolTipLabel then
        g_effects.cancelFade(toolTipLabel)
        toolTipLabel:hide()
    end

    local function applyGradeContent()
        SpecialToolTipLabel:destroyChildren()
        local width, height = fillWheelGradeRows(SpecialToolTipLabel, parseWheelGradeLines(data), '#3f3f3f')
        SpecialToolTipLabel:resize(math.max(width + 8, 40), math.max(height + 4, 16))
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
            applyGradeContent()
        end, fadeOutTime)
    else
        g_effects.cancelFade(SpecialToolTipLabel)
        applyGradeContent()
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
                header:setColor('#3f3f3f')
                header:setFont('Verdana-11px-lowspace-underline')
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
            info:setColor('#3f3f3f')
            info:setFont('Verdana-11px-lowspace')
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

function g_tooltip.setClientHelpMode(active)
    clientHelpModeActive = active == true
    if clientHelpModeActive then
        cancelPendingTooltip()
        g_tooltip.hide(true)
        g_tooltip.hideSpecial(true)
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
