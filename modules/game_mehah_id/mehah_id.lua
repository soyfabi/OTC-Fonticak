-- Mehah Client Identification Module
-- Sends extended opcode 50 with "Mehah" buffer on game start
-- so the server can identify this specific client.

local OPCODE_MEHAH_ID = 50

function init()
    connect(g_game, {
        onGameStart = onGameStart
    })

    -- If already in game, send immediately
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart
    })
end

function onGameStart()
    scheduleEvent(function()
        local protocolGame = g_game.getProtocolGame()
        if protocolGame then
            protocolGame:sendExtendedOpcode(OPCODE_MEHAH_ID, "Mehah")
        end
    end, 1000)
end
