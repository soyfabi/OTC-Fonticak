function init()
    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })
    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })
    offline()
    if Keybind.defaultKeybinds['Movement_Mount/dismount'] then
        Keybind.delete('Movement', 'Mount/dismount')
    end
end

local function getGameRootPanel()
    if modules.game_interface and modules.game_interface.getRootPanel then
        return modules.game_interface.getRootPanel()
    end
    return nil
end

function online()
    if not g_game.getFeature(GamePlayerMounts) then
        return
    end

    -- Register once; reconnects only need re-bind to the (new) game root panel.
    local index = 'Movement_Mount/dismount'
    if not Keybind.defaultKeybinds[index] then
        Keybind.new('Movement', 'Mount/dismount', 'Ctrl+R', '')
    end

    local gameRootPanel = getGameRootPanel()
    Keybind.bind('Movement', 'Mount/dismount', {
        {
            type = KEY_DOWN,
            callback = toggleMount,
        }
    }, gameRootPanel)
end

function offline()
    if Keybind.defaultKeybinds['Movement_Mount/dismount'] then
        Keybind.unbind('Movement', 'Mount/dismount')
    end
end

function toggleMount()
    local player = g_game.getLocalPlayer()
    if player then
        player:toggleMount()
    end
end

function mount()
    local player = g_game.getLocalPlayer()
    if player then
        player:mount()
    end
end

function dismount()
    local player = g_game.getLocalPlayer()
    if player then
        player:dismount()
    end
end
