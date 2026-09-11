-- Shared Monk / Harmony helpers for UI modules.

function isMonkFeatureEnabled()
    return g_game.getFeature(GameVocationMonk)
end

function isMonkPlayer(creature)
    return creature and creature:isMonk() and isMonkFeatureEnabled()
end

function readDisplayHarmonySetting()
    if g_settings.exists('displayHarmony') then
        return g_settings.getBoolean('displayHarmony')
    end
    if g_settings.exists('healthcircle_harmony') then
        return g_settings.getBoolean('healthcircle_harmony')
    end
    return true
end

function isDisplayHarmonyEnabled()
    if modules.client_options and modules.client_options.getOption then
        return modules.client_options.getOption('displayHarmony') ~= false
    end
    return readDisplayHarmonySetting()
end

function isMapHarmonyBarEnabled()
    local map = modules.game_interface and modules.game_interface.getMapPanel()
    if map and map.isDrawingOwnHarmonyBar then
        return map:isDrawingOwnHarmonyBar()
    end
    if modules.client_options and modules.client_options.getOption then
        if modules.client_options.getOption('ownHUDCharacter') == false then
            return false
        end
    end
    return isDisplayHarmonyEnabled()
end
