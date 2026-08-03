local smartWalkDirs = {}
local smartWalkDir = nil
local lastTurn = 0
local firstStep = true
local boundTurnKeys = {}

-- Used by game_bot panels to pause cavebot/attack after manual walking
lastManualWalk = 0

local keys = {
    { "Up",      North },
    { "Right",   East },
    { "Down",    South },
    { "Left",    West },
    { "Numpad8", North },
    { "Numpad9", NorthEast },
    { "Numpad6", East },
    { "Numpad3", SouthEast },
    { "Numpad2", South },
    { "Numpad1", SouthWest },
    { "Numpad4", West },
    { "Numpad7", NorthWest },
}

local turnDirs = {
    { "Up",    North },
    { "Right", East },
    { "Down",  South },
    { "Left",  West },
}

WalkController = Controller:new()

local function getOptionNumber(key, fallback)
    if modules.client_options and modules.client_options.getOption then
        local value = modules.client_options.getOption(key)
        if value ~= nil then
            return value
        end
    end
    local settingsValue = g_settings.getNumber(key)
    if settingsValue and settingsValue > 0 then
        return settingsValue
    end
    return fallback or 0
end

local function getOptionBool(key, fallback)
    if modules.client_options and modules.client_options.getOption then
        local value = modules.client_options.getOption(key)
        if value ~= nil then
            return value
        end
    end
    return fallback
end

--- Applies keyboard auto-repeat delay used for held movement keys.
function applyKeyboardDelay(delay)
    local panel = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if not panel then
        return
    end
    if not delay then
        if modules.client_options and modules.client_options.getKeyboardDelay then
            delay = modules.client_options.getKeyboardDelay()
        elseif getOptionBool('useDefaultKeyboardDelay', false) then
            delay = 250
        else
            delay = getOptionNumber('keyboardDelay', 50)
        end
    end
    panel:setAutoRepeatDelay(math.max(0, delay))
end

--- Stops the smart walking process.
local function stopSmartWalk()
    smartWalkDirs = {}
    smartWalkDir = nil
end

--- Makes the player walk in the given direction.
local function walk(dir)
    if g_keyboard.getModifiers() ~= KeyboardNoModifier then
        return false
    end

    lastManualWalk = g_clock.millis()
    if modules.game_interface then
        modules.game_interface.lastManualWalk = lastManualWalk
    end

    local dire = smartWalkDir or dir
    local isFirst = firstStep
    local walked = g_game.walk(dire, isFirst)
    firstStep = false

    if isFirst then
        local player = g_game.getLocalPlayer()
        local firstDelay = getOptionNumber('walkFirstStepDelay', 50)
        if player and firstDelay > 0 then
            player:lockWalk(firstDelay)
        end
    end

    if not walked then
        local player = g_game.getLocalPlayer()
        if player and player:canWalk() and getOptionBool('alwaysTurnTowardsMoveDirection', true) then
            if not player:isWalking() and player:getDirection() ~= dire then
                if dire == North or dire == East or dire == South or dire == West then
                    g_game.turn(dire)
                end
            end
        end
    end

    return true
end

--- Initiates a smart walk in the given direction.
function smartWalk(dir)
    walk(dir)
end

--- Changes the current walking direction.
local function changeWalkDir(dir, pop)
    while table.removevalue(smartWalkDirs, dir) do end

    if pop then
        if #smartWalkDirs == 0 then
            stopSmartWalk()
            return
        end
    else
        table.insert(smartWalkDirs, 1, dir)
    end

    smartWalkDir = smartWalkDirs[1]

    if getOptionBool('smartWalk', false) and #smartWalkDirs > 1 then
        local diagonalMap = {
            [North] = { [West] = NorthWest, [East] = NorthEast },
            [South] = { [West] = SouthWest, [East] = SouthEast },
            [West]  = { [North] = NorthWest, [South] = SouthWest },
            [East]  = { [North] = NorthEast, [South] = SouthEast }
        }

        for _, d in ipairs(smartWalkDirs) do
            if diagonalMap[smartWalkDir] and diagonalMap[smartWalkDir][d] then
                smartWalkDir = diagonalMap[smartWalkDir][d]
                break
            end
        end
    end
end

--- Handles turning the player.
local function turn(dir, repeated)
    local player = g_game.getLocalPlayer()
    if player:isWalking() and player:getDirection() == dir then
        return
    end

    local ctrlTurnDelay = getOptionNumber('walkCtrlTurnDelay', 0)
    local turnDelay = getOptionNumber('walkTurnDelay', 0)
    local delay = repeated and math.max(ctrlTurnDelay, 50) or math.max(ctrlTurnDelay, 0)
    if delay <= 0 then
        delay = repeated and 50 or 0
    end

    if lastTurn + delay < g_clock.millis() then
        g_game.turn(dir)
        changeWalkDir(dir)
        lastTurn = g_clock.millis()
        local lockDelay = math.max(turnDelay, ctrlTurnDelay)
        if lockDelay > 0 then
            player:lockWalk(lockDelay)
        end
    end
end

local function buildTurnKeyCombos()
    local prefixes = {}
    if getOptionBool('turnModifierCtrl', true) then
        table.insert(prefixes, 'Ctrl')
    end
    if getOptionBool('turnModifierShift', false) then
        table.insert(prefixes, 'Shift')
    end
    if getOptionBool('turnModifierAlt', false) then
        table.insert(prefixes, 'Alt')
    end

    if #prefixes == 0 then
        table.insert(prefixes, 'Ctrl')
    end

    local combos = {}
    for _, prefix in ipairs(prefixes) do
        for _, keyDir in ipairs(turnDirs) do
            table.insert(combos, { prefix .. '+' .. keyDir[1], keyDir[2] })
        end
    end
    return combos
end

local function unbindBoundTurnKeys()
    local gameRootPanel = modules.game_interface.getRootPanel()
    for _, key in ipairs(boundTurnKeys) do
        g_keyboard.unbindKeyDown(key, gameRootPanel)
        g_keyboard.unbindKeyPress(key, gameRootPanel)
        g_keyboard.unbindKeyUp(key, gameRootPanel)
    end
    boundTurnKeys = {}
end

function bindTurnKey(key, dir)
    local gameRootPanel = modules.game_interface.getRootPanel()

    g_keyboard.bindKeyDown(key, function() turn(dir, false) end, gameRootPanel)
    g_keyboard.bindKeyPress(key, function() turn(dir, true) end, gameRootPanel)
    g_keyboard.bindKeyUp(key, function()
        local player = g_game.getLocalPlayer()
        if player then
            local lockDelay = math.max(getOptionNumber('walkTurnDelay', 0), getOptionNumber('walkCtrlTurnDelay', 0))
            if lockDelay > 0 then
                player:lockWalk(lockDelay)
            end
        end
    end, gameRootPanel)
end

function unbindTurnKey(key)
    local gameRootPanel = modules.game_interface.getRootPanel()
    g_keyboard.unbindKeyDown(key, gameRootPanel)
    g_keyboard.unbindKeyPress(key, gameRootPanel)
    g_keyboard.unbindKeyUp(key, gameRootPanel)
end

--- Rebinds turn keys according to Ctrl/Shift/Alt options.
function rebindTurnKeys()
    if not modules.game_interface or not modules.game_interface.getRootPanel then
        return
    end
    unbindBoundTurnKeys()
    for _, keyDir in ipairs(buildTurnKeyCombos()) do
        bindTurnKey(keyDir[1], keyDir[2])
        table.insert(boundTurnKeys, keyDir[1])
    end
end

--- Binds movement keys to their respective directions.
local function bindKeys()
    applyKeyboardDelay()
    for _, keyDir in ipairs(keys) do bindWalkKey(keyDir[1], keyDir[2]) end
    rebindTurnKeys()
end

local function unbindKeys()
    for _, keyDir in ipairs(keys) do unbindWalkKey(keyDir[1]) end
    unbindBoundTurnKeys()
end

--- Handles player teleportation events.
local function onTeleport(player, newPos, oldPos)
    if not newPos or not oldPos then
        return
    end

    local offsetX, offsetY, offsetZ =
        Position.offsetX(newPos, oldPos), Position.offsetY(newPos, oldPos), Position.offsetZ(newPos, oldPos)

    local TELEPORT_DELAY = getOptionNumber('walkTeleportDelay', 0)
    local STAIRS_DELAY = getOptionNumber('walkStairsDelay', 0)

    local delay = (offsetX >= 3 or offsetY >= 3 or offsetZ >= 2) and TELEPORT_DELAY or STAIRS_DELAY
    if delay > 0 then
        player:lockWalk(delay)
    end
end

local function onWalkFinish(player)
end

local function onAutoWalk(player)
end

local function onCancelWalk(player)
    player:lockWalk(50)
end

function WalkController:onInit()
    bindKeys()
end

function WalkController:onTerminate()
    unbindKeys()
end

function WalkController:onGameStart()
    self:registerEvents(g_game, {
        onTeleport = onTeleport,
        onAutoWalk = onAutoWalk
    })

    self:registerEvents(LocalPlayer, {
        onCancelWalk = onCancelWalk,
        onWalkFinish = onWalkFinish,
        onAutoWalk = onAutoWalk
    })

    modules.game_interface.getRootPanel().onFocusChange = stopSmartWalk
    modules.game_joystick.addOnJoystickMoveListener(function(dir) g_game.walk(dir) end)
    applyKeyboardDelay()
    rebindTurnKeys()

    if not g_game.isOfficialTibia() then
        g_game.enableFeature(GameForceFirstAutoWalkStep)
    else
        g_game.disableFeature(GameForceFirstAutoWalkStep)
    end
end

function WalkController:onGameEnd()
    stopSmartWalk()
end

function bindWalkKey(key, dir)
    local gameRootPanel = modules.game_interface.getRootPanel()

    g_keyboard.bindKeyDown(key, function()
        if getOptionBool('autoChaseOverride', true) then
            if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
                g_game.setChaseMode(DontChase)
            end
        end
        firstStep = true
        changeWalkDir(dir)
    end, gameRootPanel, true)

    g_keyboard.bindKeyUp(key, function()
        changeWalkDir(dir, true)
    end, gameRootPanel, true)

    g_keyboard.bindKeyPress(key, function() smartWalk(dir) end, gameRootPanel)
end

function unbindWalkKey(key)
    local gameRootPanel = modules.game_interface.getRootPanel()
    g_keyboard.unbindKeyDown(key, gameRootPanel)
    g_keyboard.unbindKeyUp(key, gameRootPanel)
    g_keyboard.unbindKeyPress(key, gameRootPanel)
end
