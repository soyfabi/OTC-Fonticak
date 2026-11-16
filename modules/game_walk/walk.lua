local smartWalkDirs = {}
local smartWalkDir = nil
local lastTurn = 0
local heldWalkEvent
local heldWalkWaitingForServer = false
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

local diagonalMap = {
    [North] = { [West] = NorthWest, [East] = NorthEast },
    [South] = { [West] = SouthWest, [East] = SouthEast },
    [West]  = { [North] = NorthWest, [South] = SouthWest },
    [East]  = { [North] = NorthEast, [South] = SouthEast }
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

local function getKeyboardDelay()
    if modules.client_options and modules.client_options.getKeyboardDelay then
        return modules.client_options.getKeyboardDelay()
    end
    return getOptionBool('useDefaultKeyboardDelay', false) and 250 or getOptionNumber('keyboardDelay', 50)
end

--- Applies keyboard auto-repeat delay used for held movement keys.
function applyKeyboardDelay(delay)
    local panel = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if panel then
        panel:setAutoRepeatDelay(math.max(0, delay or getKeyboardDelay()))
    end
end

local function cancelHeldWalk()
    removeEvent(heldWalkEvent)
    heldWalkEvent = nil
    heldWalkWaitingForServer = false
end

--- Stops the smart walking process.
local function stopSmartWalk()
    cancelHeldWalk()
    smartWalkDirs = {}
    smartWalkDir = nil
end

function stopChasingWhenMoving()
    if getOptionBool('autoChaseOverride', true) and g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
        g_game.setChaseMode(DontChase)
    end
end

--- Makes the player walk in the given direction.
local function walk(dir, bufferStep, fromIdle)
    local player = g_game.getLocalPlayer()
    if not player or g_keyboard.getModifiers() ~= KeyboardNoModifier then
        return false
    end

    lastManualWalk = g_clock.millis()
    if modules.game_interface then
        modules.game_interface.lastManualWalk = lastManualWalk
    end

    stopChasingWhenMoving()
    local walked = g_game.walk(dir, bufferStep)

    if fromIdle and walked then
        local firstDelay = getOptionNumber('walkFirstStepDelay', 50)
        if firstDelay > 0 then
            player:lockWalk(firstDelay)
        end
    end

    if not walked and player:canWalk() and not player:isWalking() and player:getDirection() ~= dir
        and getOptionBool('alwaysTurnTowardsMoveDirection', true)
        and (dir == North or dir == East or dir == South or dir == West) then
        g_game.turn(dir)
    end

    return walked
end

local function scheduleHeldWalk(minDelay)
    local player = g_game.getLocalPlayer()
    if not player or not smartWalkDir then
        return
    end

    local delay = math.max(minDelay or 0, player:getWalkDelay())
    if delay == 0 and player:isPreWalking() then
        heldWalkWaitingForServer = true
        return
    end

    heldWalkEvent = scheduleEvent(function()
        heldWalkEvent = nil
        local held = smartWalkDirs[1]
        local panel = modules.game_interface.getRootPanel()
        if not held or not g_window.hasFocus() or not panel:isFocused() or g_ui.isKeyboardGrabbed()
            or not g_keyboard.isKeyPressed(held.key) or g_keyboard.getModifiers() ~= KeyboardNoModifier
            or player:isDead() or player:isAutoWalking() then
            return
        end

        if player:isPreWalking() or player:getWalkDelay() > 0 then
            scheduleHeldWalk()
        elseif walk(smartWalkDir, false) then
            scheduleHeldWalk()
        end
    end, math.max(1, delay))
end

--- Initiates a smart walk in the given direction.
function smartWalk(dir)
    walk(smartWalkDir or dir, false)
end

--- Changes the current walking direction.
local function changeWalkDir(key, dir, pop)
    for i, entry in ipairs(smartWalkDirs) do
        if entry.key == key then
            table.remove(smartWalkDirs, i)
            break
        end
    end

    if pop then
        if #smartWalkDirs == 0 then
            stopSmartWalk()
            return
        end
    else
        table.insert(smartWalkDirs, 1, {key = key, dir = dir})
    end

    smartWalkDir = smartWalkDirs[1].dir

    local diagonals = diagonalMap[smartWalkDir]
    if diagonals and getOptionBool('smartWalk', false) then
        for _, entry in ipairs(smartWalkDirs) do
            if diagonals[entry.dir] then
                smartWalkDir = diagonals[entry.dir]
                break
            end
        end
    end
end

--- Handles turning the player.
local function turn(dir, repeated)
    local player = g_game.getLocalPlayer()
    if not player or (player:isWalking() and player:getDirection() == dir) then
        return
    end

    local ctrlTurnDelay = getOptionNumber('walkCtrlTurnDelay', 0)
    local turnDelay = getOptionNumber('walkTurnDelay', 0)
    local now = g_clock.millis()
    if not repeated or now - lastTurn >= math.max(ctrlTurnDelay, 50) then
        cancelHeldWalk()
        g_game.cancelScheduledWalk()
        g_game.turn(dir)
        lastTurn = now
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
    for _, key in ipairs(boundTurnKeys) do
        unbindTurnKey(key)
    end
    boundTurnKeys = {}
end

function bindTurnKey(key, dir)
    local gameRootPanel = modules.game_interface.getRootPanel()

    g_keyboard.bindKeyDown(key, function() turn(dir, false) end, gameRootPanel)
    g_keyboard.bindKeyPress(key, function(_, _, autoRepeatTicks)
        if autoRepeatTicks > 0 then
            turn(dir, true)
        end
    end, gameRootPanel)
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
    cancelHeldWalk()
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

local function onServerWalk()
    if heldWalkWaitingForServer then
        heldWalkWaitingForServer = false
        scheduleHeldWalk()
    end
end

local function onCancelWalk(player)
    cancelHeldWalk()
    player:lockWalk(50)
end

function WalkController:onInit()
    bindKeys()
end

function WalkController:onTerminate()
    stopSmartWalk()
    g_game.cancelScheduledWalk()
    unbindKeys()
end

function WalkController:onGameStart()
    self:registerEvents(g_game, {
        onTeleport = onTeleport,
        onAutoWalk = cancelHeldWalk,
        onDeath = stopSmartWalk
    })

    self:registerEvents(LocalPlayer, {
        onCancelWalk = onCancelWalk,
        onWalk = onServerWalk
    })

    self:registerEvents(modules.game_interface.getRootPanel(), {
        onFocusChange = function(_, focused)
            if not focused then
                stopSmartWalk()
                g_game.cancelScheduledWalk()
            end
        end
    })
    modules.game_joystick.addOnJoystickMoveListener(function(dir)
        stopChasingWhenMoving()
        g_game.walk(dir)
    end)
    applyKeyboardDelay()
    rebindTurnKeys()
end

function WalkController:onGameEnd()
    stopSmartWalk()
    modules.game_joystick.addOnJoystickMoveListener(nil)
end

function bindWalkKey(key, dir)
    local gameRootPanel = modules.game_interface.getRootPanel()

    g_keyboard.bindKeyDown(key, function()
        cancelHeldWalk()
        changeWalkDir(key, dir)
    end, gameRootPanel, true)

    g_keyboard.bindKeyUp(key, function()
        local previousDir = smartWalkDir
        changeWalkDir(key, dir, true)
        if smartWalkDir and smartWalkDir ~= previousDir then
            cancelHeldWalk()
            g_game.cancelScheduledWalk()
            if g_keyboard.getModifiers() == KeyboardNoModifier then
                scheduleHeldWalk()
            end
        end
    end, gameRootPanel, true)

    g_keyboard.bindKeyPress(key, function(_, _, autoRepeatTicks)
        local isFirst = autoRepeatTicks == 0
        if not smartWalkDir or (not isFirst and (heldWalkEvent or heldWalkWaitingForServer)) then
            return
        end

        local player = g_game.getLocalPlayer()
        if not player then
            return
        end

        -- A new direction replaces any buffered step, even if it hits a wall.
        if isFirst then
            g_game.cancelScheduledWalk()
        end
        local fromIdle = isFirst and #smartWalkDirs == 1 and not player:isWalking() and player:canWalk()
        local walked = walk(smartWalkDir, isFirst, fromIdle)
        if walked or player:isPreWalking() or player:getWalkDelay() > 0 then
            local delay = fromIdle and walked and not getOptionBool('dashWalk', false) and getKeyboardDelay() or 0
            scheduleHeldWalk(delay)
        end
    end, gameRootPanel)
end

function unbindWalkKey(key)
    changeWalkDir(key, nil, true)
    local gameRootPanel = modules.game_interface.getRootPanel()
    g_keyboard.unbindKeyDown(key, gameRootPanel)
    g_keyboard.unbindKeyUp(key, gameRootPanel)
    g_keyboard.unbindKeyPress(key, gameRootPanel)
end
