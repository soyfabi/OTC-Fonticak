-- Syncs harmony/serene from custom server extended opcodes (8.60 Fonticak / Astra).
-- Official protocol 15.x uses GameServerMonkData parsed in C++ (protocolgameparse.cpp).

local function applyMonkData(player, harmony, serene)
    if not player then
        return
    end
    if harmony ~= nil then
        player:setHarmony(harmony)
    end
    if serene ~= nil then
        player:setSerene(serene)
    end
end

local function onHarmonyOpcode(_, _, buffer)
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    applyMonkData(player, tonumber(buffer) or 0, nil)
end

local function onMonkDataOpcode(_, _, data)
    if type(data) ~= 'table' then
        return
    end
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    applyMonkData(player, tonumber(data.harmony) or 0, data.serene == true)
end

function init()
    ProtocolGame.registerExtendedOpcode(ExtendedIds.MonkHarmonyOpcode, onHarmonyOpcode)
    ProtocolGame.registerExtendedJSONOpcode(ExtendedIds.MonkData, onMonkDataOpcode)
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(ExtendedIds.MonkHarmonyOpcode)
    ProtocolGame.unregisterExtendedJSONOpcode(ExtendedIds.MonkData)
end
