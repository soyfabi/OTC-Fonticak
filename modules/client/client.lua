local musicFilename = 'sounds/startup'
local musicChannel = nil
local startupGameSignalsConnected = false
if g_sounds then
    musicChannel = g_sounds.getChannel(SoundChannels.Music)
end

function setMusic(filename)
    musicFilename = filename

    if not g_game.isOnline() then
        musicChannel:stop()
        musicChannel:enqueue(musicFilename, 3)
    end
end

local function onStartupGameStart()
    if musicChannel then
        musicChannel:stop(3)
    end
end

local function onStartupGameEnd()
    if g_sounds then
        g_sounds.stopAll()
        if musicChannel then
            musicChannel:enqueue(musicFilename, 3)
        end
    end
end

function startup()
    g_logger.info('[boot] client.startup begin')
    if musicChannel then
        musicChannel:enqueue(musicFilename, 3)
        if not startupGameSignalsConnected then
            connect(g_game, {
                onGameStart = onStartupGameStart,
                onGameEnd = onStartupGameEnd
            })
            startupGameSignalsConnected = true
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
    g_logger.info('[boot] client.startup showing EnterGame')
    if errmsg or errtitle then
        local msgbox = displayErrorBox(errtitle, errmsg)
        msgbox.onOk = function()
            EnterGame.firstShow()
        end
    else
        EnterGame.firstShow()
    end
    g_logger.info('[boot] client.startup done')
    if g_app.hasUpdater() and g_sounds then
        g_sounds.setAudioEnabled(g_settings.getBoolean('enableAudio'))
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
end

function terminate()
    if g_app.hasUpdater() then
        disconnect(g_app, {
            onUpdateFinished = startup,
        })
    else
        disconnect(g_app, {
            onRun = startup,
        })
    end

    if startupGameSignalsConnected then
        disconnect(g_game, {
            onGameStart = onStartupGameStart,
            onGameEnd = onStartupGameEnd
        })
        startupGameSignalsConnected = false
    end
    musicChannel = nil
end
