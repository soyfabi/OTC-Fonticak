local frameTime = 16
local trailDuration = 140
local trailSpacing = 9
local maxTrailDots = 12
local bounceDuration = 180
local trail = {}
local trailSource
local lastTrailPoint
local trailEvent
local bounces = {}

local function isEffectEnabled(optionKey)
    local options = modules.client_options
    return not options or options.getOption(optionKey) ~= false
end

local function createEffectWidget(style, parent)
    local widget = g_ui.createWidget(style, parent)
    widget:setPhantom(true)
    widget:setFocusable(false)
    return widget
end

local function fadeTrail()
    trailEvent = nil
    local now = g_clock.millis()
    local enabled = isEffectEnabled('showAnimationDrag')
    for i = #trail, 1, -1 do
        local dot = trail[i]
        local progress = (now - dot.started) / trailDuration
        if progress >= 1 or dot.widget:isDestroyed() or not enabled then
            if not dot.widget:isDestroyed() then
                dot.widget:destroy()
            end
            table.remove(trail, i)
        else
            dot.widget:setOpacity(0.45 * (1 - progress))
        end
    end
    if #trail > 0 then
        trailEvent = scheduleEvent(fadeTrail, frameTime)
    end
end

local function addTrailDot(point)
    if #trail == maxTrailDots then
        table.remove(trail, 1).widget:destroy()
    end
    local dot = createEffectWidget('UIWidget', gameRootPanel)
    dot:setRect({ x = math.floor(point.x) - 1, y = math.floor(point.y) - 1, width = 3, height = 3 })
    dot:setBackgroundColor('#e7e7e7')
    dot:setOpacity(0.45)
    trail[#trail + 1] = { widget = dot, started = g_clock.millis() }
    if not trailEvent then
        trailEvent = scheduleEvent(fadeTrail, frameTime)
    end
end

function startActionBarDragTrail(source, mousePos)
    if not isEffectEnabled('showAnimationDrag') or not gameRootPanel or not gameRootPanel:isVisible()
        or not hasAnyActiveActionBar() then
        return
    end
    trailSource = source
    lastTrailPoint = mousePos
end

function updateActionBarDragTrail(source, mousePos)
    if source ~= trailSource or not isEffectEnabled('showAnimationDrag') or not gameRootPanel or gameRootPanel:isDestroyed() then
        return
    end
    local start = lastTrailPoint
    local dx, dy = mousePos.x - start.x, mousePos.y - start.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local steps = math.floor(distance / trailSpacing)
    for i = math.max(1, steps - maxTrailDots + 1), steps do
        local t = i * trailSpacing / distance
        lastTrailPoint = { x = start.x + dx * t, y = start.y + dy * t }
        addTrailDot(lastTrailPoint)
    end
end

function finishActionBarDragTrail(source, mousePos)
    if source == trailSource then
        -- The engine passes (0, 0) when the source disappears mid-drag.
        if mousePos and (mousePos.x ~= 0 or mousePos.y ~= 0) then
            updateActionBarDragTrail(source, mousePos)
        end
        trailSource = nil
        lastTrailPoint = nil
    end
end

local function clearBounce(id)
    local bounce = bounces[id]
    if not bounce then
        return
    end
    if bounce.event then
        removeEvent(bounce.event)
    end
    if bounce.widget and not bounce.widget:isDestroyed() then
        bounce.widget:destroy()
    end
    bounces[id] = nil
end

local function copySlotImage(target, source)
    local image = source:getImageSource()
    if image ~= '' then
        target:setImageSource(image)
        target:setImageClip(source:getImageClip())
        target:setImageColor(source:getImageColor())
    end
end

function bounceActionBarSlot(button)
    if not isEffectEnabled('showActionBarMaster') then
        return
    end
    local id = button:getId()
    local barId = tonumber(id:match('^(%d+)%.%d+$'))
    local bar = barId and actionBars[barId]
    if not bar or not g_game.isOnline() or not gameRootPanel or not gameRootPanel:isVisible() then
        return
    end
    clearBounce(id)

    local bounce = {}
    bounces[id] = bounce
    -- Assigning to an empty slot can replace its widget before the next frame.
    bounce.event = scheduleEvent(function()
        bounce.event = nil
        local slot = not bar:isDestroyed() and bar.tabBar:getChildById(id)
        if not slot or not slot:isVisible() or not slot.item or not gameRootPanel:isVisible()
            or not isEffectEnabled('showActionBarMaster') then
            clearBounce(id)
            return
        end
        local item = slot.item
        local overlay = createEffectWidget('UIItem', gameRootPanel)
        bounce.widget = overlay
        overlay:setDraggable(false)
        overlay.onDrop = function() return false end
        overlay:setShowCount(false)
        overlay:setPadding(1)
        overlay:setSize(slot:getSize())
        copySlotImage(overlay, item)
        local thing = item:getItem()
        if thing and item:isItemVisible() then
            overlay:setItem(thing:clone())
            overlay:setColor(item:getColor())
            overlay:setDisplayCount(0)
        end

        local label = createEffectWidget('UIWidget', overlay)
        label:setSize(slot:getSize())
        copySlotImage(label, item.text)
        label:setFont('verdana-7px-rounded')
        label:setTextAlign(item.text:getTextAlign())
        label:setTextWrap(true)
        label:setColor(item.text:getColor())
        label:setText(item.text:getText())

        local started = g_clock.millis()
        local function animate()
            bounce.event = nil
            local progress = (g_clock.millis() - started) / bounceDuration
            if progress >= 1 or overlay:isDestroyed() or slot:isDestroyed() or not slot:isVisible()
                or not isEffectEnabled('showActionBarMaster') then
                clearBounce(id)
                return
            end
            local scale = 1 + 0.12 * math.sin(math.pi * progress) * (1.5 - progress)
            local width, height = slot:getWidth(), slot:getHeight()
            local extraX = math.floor((width * (scale - 1)) / 2 + 0.5)
            local extraY = math.floor((height * (scale - 1)) / 2 + 0.5)
            local x, y = slot:getX() - extraX, slot:getY() - extraY
            overlay:setRect({ x = x, y = y, width = width + 2 * extraX, height = height + 2 * extraY })
            label:setRect({ x = x + 1, y = y + 1, width = overlay:getWidth() - 2, height = overlay:getHeight() - 2 })
            overlay:setOpacity(math.min(1, (1 - progress) * 4))
            bounce.event = scheduleEvent(animate, frameTime)
        end
        animate()
    end, frameTime)
end

function clearActionBarEffects()
    if trailEvent then
        removeEvent(trailEvent)
        trailEvent = nil
    end
    for _, dot in ipairs(trail) do
        if not dot.widget:isDestroyed() then
            dot.widget:destroy()
        end
    end
    trail = {}
    trailSource = nil
    lastTrailPoint = nil
    for id in pairs(bounces) do
        clearBounce(id)
    end
end
