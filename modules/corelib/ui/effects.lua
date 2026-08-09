-- @docclass
g_effects = {}

function g_effects.fadeIn(widget, time, elapsed)
    if not elapsed then
        elapsed = 0
    end
    if not time then
        time = 300
    end
    widget:setOpacity(math.min(elapsed / time, 1))
    removeEvent(widget.fadeEvent)
    if elapsed < time then
        removeEvent(widget.fadeEvent)
        widget.fadeEvent = scheduleEvent(function()
            g_effects.fadeIn(widget, time, elapsed + 30)
        end, 30)
    else
        widget.fadeEvent = nil
    end
end

function g_effects.fadeOut(widget, time, elapsed)
    if not elapsed then
        elapsed = 0
    end
    if not time then
        time = 300
    end
    elapsed = math.max((1 - widget:getOpacity()) * time, elapsed)
    removeEvent(widget.fadeEvent)
    widget:setOpacity(math.max((time - elapsed) / time, 0))
    if elapsed < time then
        widget.fadeEvent = scheduleEvent(function()
            g_effects.fadeOut(widget, time, elapsed + 30)
        end, 30)
    else
        widget.fadeEvent = nil
    end
end

function g_effects.cancelFade(widget)
    removeEvent(widget.fadeEvent)
    widget.fadeEvent = nil
end

local function easeOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

local function animationSpeedFactor()
    if modules.client_options and modules.client_options.getOption then
        local speed = modules.client_options.getOption('uiBarAnimationSpeed')
        if type(speed) == 'number' and speed > 0 then
            return 100 / speed
        end
    end
    return 1
end

local function scaledDuration(baseMs)
    return math.max(80, math.floor(baseMs * animationSpeedFactor() + 0.5))
end

-- Longer ease-out for HP/MP so small heals/hits stay visible.
local function vitalDurationMs(percentDelta)
    percentDelta = math.abs(percentDelta or 0)
    return scaledDuration(math.min(1800, math.max(550, 420 + percentDelta * 18)))
end

local function progressDurationMs(percentDelta)
    percentDelta = math.abs(percentDelta or 0)
    return scaledDuration(math.min(1400, math.max(250, percentDelta * 28)))
end

function g_effects.moveTo(widget, targetPos, time, onFinish)
    if not widget or widget:isDestroyed() then
        return
    end

    time = time or 140
    local startPos = widget:getPosition()
    local startTime = g_clock.millis()

    removeEvent(widget.moveEvent)

    local function animate()
        if not widget or widget:isDestroyed() then
            return
        end

        local elapsed = g_clock.millis() - startTime
        local progress = math.min(elapsed / time, 1)
        local eased = easeOutCubic(progress)
        local x = math.floor(startPos.x + (targetPos.x - startPos.x) * eased + 0.5)
        local y = math.floor(startPos.y + (targetPos.y - startPos.y) * eased + 0.5)

        widget:setPosition({ x = x, y = y })

        if progress < 1 then
            widget.moveEvent = scheduleEvent(animate, 16)
        else
            widget:setPosition(targetPos)
            widget.moveEvent = nil
            if onFinish then
                onFinish(widget)
            end
        end
    end

    animate()
end

function g_effects.cancelMove(widget)
    if not widget or widget:isDestroyed() then
        return
    end

    removeEvent(widget.moveEvent)
    widget.moveEvent = nil
end

function g_effects.cancelPercent(widget)
    if not widget or widget:isDestroyed() then
        return
    end

    removeEvent(widget.percentEvent)
    widget.percentEvent = nil
end

-- Ease-out fill for ProgressBar widgets. Duration scales with |delta| unless given.
function g_effects.animatePercent(widget, targetPercent, duration)
    if not widget or widget:isDestroyed() or not widget.setPercent then
        return
    end

    targetPercent = math.max(0, math.min(100, targetPercent))
    local from = widget.getPercent and widget:getPercent() or 0

    if math.abs(targetPercent - from) < 0.05 then
        g_effects.cancelPercent(widget)
        widget:setPercent(targetPercent)
        return
    end

    duration = duration or progressDurationMs(math.abs(targetPercent - from))

    g_effects.cancelPercent(widget)
    local startTime = g_clock.millis()

    local function animate()
        if not widget or widget:isDestroyed() then
            return
        end

        local elapsed = g_clock.millis() - startTime
        local progress = math.min(elapsed / duration, 1)
        local eased = easeOutCubic(progress)
        widget:setPercent(from + (targetPercent - from) * eased)

        if progress < 1 then
            widget.percentEvent = scheduleEvent(animate, 16)
        else
            widget:setPercent(targetPercent)
            widget.percentEvent = nil
        end
    end

    animate()
end

function g_effects.cancelStatsBar(statsBar)
    if not statsBar or statsBar:isDestroyed() then
        return
    end

    removeEvent(statsBar.statsBarEvent)
    statsBar.statsBarEvent = nil
end

-- Ease-out fill for UIStatsBar (experience/skill lines). Calls applyValue each frame.
function g_effects.animateStatsBar(statsBar, targetValue, total, duration)
    if not statsBar or statsBar:isDestroyed() or not statsBar.applyValue then
        return
    end

    targetValue = math.min(total, math.max(0, targetValue))
    local from = statsBar.currentValue or 0

    if math.abs(targetValue - from) < 0.05 then
        g_effects.cancelStatsBar(statsBar)
        statsBar:applyValue(targetValue, total)
        return
    end

    local percentDelta = math.abs(targetValue - from) / math.max(total, 1) * 100
    local isVital = statsBar.statsType == 'health' or statsBar.statsType == 'mana' or statsBar.statsType == 'manashield'
    duration = duration or (isVital and vitalDurationMs(percentDelta) or progressDurationMs(percentDelta))

    g_effects.cancelStatsBar(statsBar)
    local startTime = g_clock.millis()

    local function animate()
        if not statsBar or statsBar:isDestroyed() then
            return
        end

        local elapsed = g_clock.millis() - startTime
        local progress = math.min(elapsed / duration, 1)
        local eased = easeOutCubic(progress)
        statsBar:applyValue(from + (targetValue - from) * eased, total)

        if progress < 1 then
            statsBar.statsBarEvent = scheduleEvent(animate, 16)
        else
            statsBar:applyValue(targetValue, total)
            statsBar.statsBarEvent = nil
        end
    end

    animate()
end

function g_effects.cancelWidth(widget)
    if not widget or widget:isDestroyed() then
        return
    end

    removeEvent(widget.widthEvent)
    widget.widthEvent = nil
end

-- Ease-out width animation (healthinfo HP/MP fill bars). Works both up and down.
function g_effects.animateWidth(widget, targetWidth, duration)
    if not widget or widget:isDestroyed() then
        return
    end

    targetWidth = math.max(0, targetWidth)
    local from = widget._animWidth
    if from == nil then
        from = widget:getWidth() or 0
    end

    if math.abs(targetWidth - from) < 0.05 then
        g_effects.cancelWidth(widget)
        widget._animWidth = targetWidth
        widget:setWidth(math.max(1, math.floor(targetWidth + 0.5)))
        return
    end

    -- Prefer explicit duration (percent-based from caller); pixel fallback is a last resort.
    duration = duration or vitalDurationMs(math.abs(targetWidth - from) / math.max(widget:getParent() and widget:getParent():getWidth() or 100, 1) * 100)

    g_effects.cancelWidth(widget)
    local startTime = g_clock.millis()

    local function animate()
        if not widget or widget:isDestroyed() then
            return
        end

        local elapsed = g_clock.millis() - startTime
        local progress = math.min(elapsed / duration, 1)
        local eased = easeOutCubic(progress)
        local width = from + (targetWidth - from) * eased
        widget._animWidth = width
        widget:setWidth(math.max(1, math.floor(width + 0.5)))

        if progress < 1 then
            widget.widthEvent = scheduleEvent(animate, 16)
        else
            widget._animWidth = targetWidth
            widget:setWidth(math.max(1, math.floor(targetWidth + 0.5)))
            widget.widthEvent = nil
        end
    end

    animate()
end

function g_effects.cancelValue(owner)
    if not owner then
        return
    end

    removeEvent(owner.valueEvent)
    owner.valueEvent = nil
end

-- Generic ease-out numeric tween. onUpdate(currentValue) each frame.
-- Optional wrap: if to < from and wrap=true, jump to 0 then ease to `to`.
-- Optional interval: ms between ticks (default 16); use a higher value for
-- cheap updates that don't need 60 Hz.
function g_effects.animateValue(owner, from, to, duration, onUpdate, wrap, interval)
    if not owner or not onUpdate then
        return
    end
    interval = interval or 16

    from = from or 0
    to = to or 0

    if wrap and to < from - 0.05 then
        g_effects.cancelValue(owner)
        from = 0
        onUpdate(0)
    end

    if math.abs(to - from) < 0.05 then
        g_effects.cancelValue(owner)
        onUpdate(to)
        return
    end

    duration = duration or progressDurationMs(math.abs(to - from))

    g_effects.cancelValue(owner)
    local startTime = g_clock.millis()

    local function animate()
        local elapsed = g_clock.millis() - startTime
        local progress = math.min(elapsed / duration, 1)
        local eased = easeOutCubic(progress)
        onUpdate(from + (to - from) * eased)

        if progress < 1 then
            owner.valueEvent = scheduleEvent(animate, interval)
        else
            onUpdate(to)
            owner.valueEvent = nil
        end
    end

    animate()
end

function g_effects.startBlink(widget, duration, interval, clickCancel)
    duration = duration or 0 -- until stop is called
    interval = interval or 500
    clickCancel = clickCancel or true

    removeEvent(widget.blinkEvent)
    removeEvent(widget.blinkStopEvent)

    widget.blinkEvent = cycleEvent(function()
        widget:setOn(not widget:isOn())
    end, interval)

    if duration > 0 then
        widget.blinkStopEvent = scheduleEvent(function()
            g_effects.stopBlink(widget)
        end, duration)
    end

    connect(widget, {
        onClick = g_effects.stopBlink
    })
end

function g_effects.stopBlink(widget)
    disconnect(widget, {
        onClick = g_effects.stopBlink
    })
    removeEvent(widget.blinkEvent)
    removeEvent(widget.blinkStopEvent)
    widget.blinkEvent = nil
    widget.blinkStopEvent = nil
    widget:setOn(false)
end
