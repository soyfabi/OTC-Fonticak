-- LuaFormatter off
blockedKeys = {
    'Up',
    'Left',
    'Right',
    'Down',
    'NEnd',
    'NDown',
    'NPgDown',
    'NLeft',
    'NRight',
    'NHome',
    'NUp',
    'NPgUp',
    'Alt+F4'
}

HotkeyShortcuts = {
    ["Ctrl+F1"] = "CF1",
    ["Ctrl+F2"] = "CF2",
    ["Ctrl+F3"] = "CF3",
    ["Ctrl+F4"] = "CF4",
    ["Ctrl+F5"] = "CF5",
    ["Ctrl+F6"] = "CF6",
    ["Ctrl+F7"] = "CF7",
    ["Ctrl+F8"] = "CF8",
    ["Ctrl+F9"] = "CF9",
    ["Ctrl+F10"] = "CF10",
    ["Ctrl+F11"] = "CF11",
    ["Ctrl+F12"] = "CF12",
    ["Shift+F1"] = "SF1",
    ["Shift+F2"] = "SF2",
    ["Shift+F3"] = "SF3",
    ["Shift+F4"] = "SF4",
    ["Shift+F5"] = "SF5",
    ["Shift+F6"] = "SF6",
    ["Shift+F7"] = "SF7",
    ["Shift+F8"] = "SF8",
    ["Shift+F9"] = "SF9",
    ["Shift+F10"] = "SF10",
    ["Shift+F11"] = "SF11",
    ["Shift+F12"] = "SF12",
    ["Escape"] = "Esc",
    ["Insert"] = "Ins",
    ["Delete"] = "Del",
    ["PageUp"] = "PgUp",
    ["Ctrl+PageUp"] = "CPgUp",
    ["Shift+PageUp"] = "SPgUp",
    ["Alt+PageUp"] = "APgUp",
    ["Num+Plus"] = "N+",
    ["Num+Enter"] = "NEnter",
    ["HalfQuote"] = "'",
    ["Num+/"] = "N/",
    ["Num+*"] = "N*",
    ["Num+-"] = "N-",
    ["Num+,"] = "N,",
    ["Mouse4"] = "MB4",
    ["Mouse5"] = "MB5",
    ["MouseUp"] = "MUp",
    ["MouseDown"] = "MDown"
}

function translateVocation(id)
    if id == VocationsServer.Sorcerer or id == VocationsServer.MasterSorcerer or id == 13 then
        return VocationsServer.MasterSorcerer -- Master Sorcerer (5)
    elseif id == VocationsServer.Druid or id == VocationsServer.ElderDruid or id == 14 then
        return VocationsServer.ElderDruid -- Elder Druid (6)
    elseif id == VocationsServer.Paladin or id == VocationsServer.RoyalPaladin or id == 12 then
        return VocationsServer.RoyalPaladin -- Royal Paladin (7)
    elseif id == VocationsServer.Knight or id == VocationsServer.EliteKnight or id == 11 then
        return VocationsServer.EliteKnight -- Elite Knight (8)
    elseif id == VocationsServer.Monk or id == VocationsServer.ExaltedMonk or id == 15 then
        return VocationsServer.ExaltedMonk -- Exalted Monk (10)
    end
    return 0
end

local UseTypeUseOnYourself = 1
local UseTypeUseOnTarget = 2
local UseTypeSelectUseTarget = 3
local UseTypeEquip = 4
local UseTypeUse = 5
local UseTypeChatText = 6
local UseTypePassiveAbility = 7
local UseTypeSpecialAction = 8
local UseTypeUseAtCursorPosition = 9

UseTypes = {
    ["UseOnYourself"] = UseTypeUseOnYourself,
    ["UseOnTarget"] = UseTypeUseOnTarget,
    ["SelectUseTarget"] = UseTypeSelectUseTarget,
    ["Equip"] = UseTypeEquip,
    ["Use"] = UseTypeUse,
    ["chatText"] = UseTypeChatText,
    ["passiveAbility"] = UseTypePassiveAbility,
    ["specialAction"] = UseTypeSpecialAction,
    ["UseAtCursorPosition"] = UseTypeUseAtCursorPosition,
}

UseTypesTip = {
    [UseTypeUseOnYourself] = "Use %s on Yourself",
    [UseTypeUseOnTarget] = "Use %s on Attack Target",
    [UseTypeSelectUseTarget] = "Use %s with Crosshair",
    [UseTypeUseAtCursorPosition] = "Use %s at Cursor Position",
    [UseTypeEquip] = "%s %s",
    [UseTypeUse] = "Use %s"
}

PassiveAbilities = {
    [1] = {
        name = "Gift of Life",
        exhaustion = 60 * 60 * 30 * 1000, --ms
        type = 'Passive',
        icon = '/images/game/spells/passiveability-icons-32x32'
    }
}

ActionBarSpecialActions = {{
    id = "toggleWasdChatMode",
    text = tr("Toggle WASD chat mode")
}, {
    id = "attackNext",
    text = tr("Attack next creature in battle list")
}, {
    id = "attackPrevious",
    text = tr("Attack previous creature in battle list")
}, {
    id = "toggleChase",
    text = tr("Toggle chase mode")
}}

function getActionBarSpecialAction(actionId)
    for _, specialAction in ipairs(ActionBarSpecialActions) do
        if specialAction.id == actionId then
            return specialAction
        end
    end

    return nil
end
-- LuaFormatter on
