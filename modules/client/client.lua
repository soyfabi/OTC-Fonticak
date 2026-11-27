local musicFilename = 'sounds/startup'
local musicChannel = nil
if g_sounds then
    musicChannel = g_sounds.getChannel(SoundChannels.Music)
end

local startupSplash
local startupSplashEvent

local function closeStartupSplash()
    if startupSplashEvent then
        removeEvent(startupSplashEvent)
        startupSplashEvent = nil
    end

    if startupSplash then
        startupSplash:destroy()
        startupSplash = nil
    end
end

local function showStartupSplash()
    if startupSplash then
        return
    end

    startupSplash = g_ui.displayUI('startup_splash')
    if not startupSplash then
        return
    end

    local content = startupSplash:getChildById('splashContent')
    local ring = content:getChildById('splashRing')
    local startedAt = g_clock.millis()
    local fadeInDuration, fadeOutStart, fadeOutDuration = 260, 1200, 300
    local turnDuration = 1050
    local fadeInComplete = false
    content:setOpacity(0)
    startupSplashEvent = cycleEvent(function()
        local elapsed = g_clock.millis() - startedAt
        if elapsed >= fadeOutStart + fadeOutDuration then
            closeStartupSplash()
            return
        end

        if not fadeInComplete then
            fadeInComplete = elapsed >= fadeInDuration
            content:setOpacity(math.min(elapsed / fadeInDuration, 1))
        end
        ring:setRotation((elapsed % turnDuration) * 360 / turnDuration)
        if elapsed > fadeOutStart then
            startupSplash:setOpacity(1 - (elapsed - fadeOutStart) / fadeOutDuration)
        end
    end, 16)
end

local function onGameStart()
    closeStartupSplash()
    if not musicChannel then
        return
    end

    musicChannel:stop(3)
end

local function onGameEnd()
    if not musicChannel then
        return
    end

    g_sounds.stopAll()
    if modules.client_options and modules.client_options.getOption('soundAnthem') then
        musicChannel:enqueue(musicFilename, 3)
    end
end

function setMusic(filename)
    musicFilename = filename

    if not g_game.isOnline() then
        musicChannel:stop()
        if modules.client_options and modules.client_options.getOption('soundAnthem') then
            musicChannel:enqueue(musicFilename, 3)
        end
    end
end

function reloadMusic()
    if not musicChannel then
        return
    end

    if not g_game.isOnline() then
        musicChannel:stop()
        if modules.client_options and modules.client_options.getOption('soundAnthem') then
            musicChannel:enqueue(musicFilename, 3)
        end
    end
end

function startup()
    if musicChannel then
        if modules.client_options and modules.client_options.getOption('soundAnthem') then
            musicChannel:enqueue(musicFilename, 3)
        end
    end

    -- Check for startup errors
    local errtitle = nil
    local errmsg = nil

    if g_graphics.getRenderer():lower():match('gdi generic') then
        errtitle = tr('Graphics card driver not detected')
        errmsg = tr(
            'No graphics card detected, everything will be drawn using the CPU,\nthus the performance will be really bad.\nPlease update your graphics driver to have a better performance.')
    end

    -- Show entergame
    if errmsg or errtitle then
        local msgbox = displayErrorBox(errtitle, errmsg)
        msgbox.onOk = function()
            EnterGame.firstShow()
        end
    else
        EnterGame.firstShow()
        if not modules.client_locales.needsStartupLocaleSelection() then
            showStartupSplash()
        end
    end
    if g_app.hasUpdater() and g_sounds then
        g_sounds.setAudioEnabled(g_settings.getBoolean('enableAudio', true))
    end
end

function init()
    if g_app.hasUpdater() then
        connect(g_app, {
            onUpdateFinished = startup,
        })
    else
        connect(g_app, {
            onRun = startup,
        })
    end

    if musicChannel then
        g_sounds.preload(musicFilename)
    end
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
end

function terminate()
    closeStartupSplash()

    if g_app.hasUpdater() then
        disconnect(g_app, {
            onUpdateFinished = startup,
        })
    else
        disconnect(g_app, {
            onRun = startup,
        })
    end

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
end
