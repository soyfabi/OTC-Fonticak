-- private variables
local background
local bgEffectEvent = nil
local toggleState = true  -- controls which effect  is active
local timeLoopBackgroundEffect = 5000 -- 5 seconds

-- public functions
function init()
    background = g_ui.displayUI('background')
    background:lower()

    connect(g_game, {
        onGameStart = hide
    })
    connect(g_game, {
        onGameEnd = show
    })
    startBackgroundEffectLoop() -- start the background effect loop
end

function terminate()
    disconnect(g_game, {
        onGameStart = hide
    })
    disconnect(g_game, {
        onGameEnd = show
    })

    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end
    background:destroy()

    background = nil
end

function hide()
    background:hide()
    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end
end

function show()
    background:show()
    startBackgroundEffectLoop()
end

function getBackground()
    return background
end

-- 🔄 example of how to use the particles widget
function startBackgroundEffectLoop()
    if bgEffectEvent then
        removeEvent(bgEffectEvent)
        bgEffectEvent = nil
    end

    local function switchEffect()
        if not background then
            return
        end

        local particlesWidget = background:getChildById('particles') -- background is the root widget of the background module
        if not particlesWidget then
            return
        end

        if toggleState then
            particlesWidget:setEffect('background-effect')
        else
            particlesWidget:setEffect('background2-effect')
        end
        toggleState = not toggleState

        -- repeat every 5 seconds (adjust the time you want)
        bgEffectEvent = scheduleEvent(switchEffect, timeLoopBackgroundEffect)
    end

    -- start the first effect change
    switchEffect()
end
