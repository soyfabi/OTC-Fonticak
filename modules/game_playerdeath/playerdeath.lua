deathController = Controller:new()
function deathController:onInit()
    deathController:registerEvents(g_game, {
        onDeath = display,
    })
end

function deathController:onTerminate()
   deathController.ui = destroyWindows()
end

function deathController:onGameEnd()
    deathController.ui = destroyWindows()
end

function destroyWindows()
    if deathController.ui and not deathController.ui:isDestroyed() then
        if g_modalManager then
            g_modalManager.hide(deathController.ui)
        end
        deathController.ui:destroy()
    end
    return nil
end

function display(deathType, penalty)
    displayDeadMessage()
    openWindow(deathType, penalty)
    scheduleReconnect()
end

function displayDeadMessage()
    local advanceLabel = modules.game_interface.getRootPanel():recursiveGetChildById('middleCenterLabel')
    if advanceLabel:isVisible() then
        return
    end

    modules.game_textmessage.displayGameMessage(tr('You are dead.'))
end

function openWindow(deathType, penalty)
    deathController.ui = destroyWindows()
    deathController.ui = g_ui.displayUI('deathwindow', rootWidget)

    local window = deathController.ui
    local textLabel = window:getChildById('labelText')
    local message = {}
    local function addText(text, color)
        table.insert(message, '{' .. text .. ', ' .. color .. '}')
    end

    local unfairDeath = deathType == DeathType.Regular and penalty ~= nil and penalty ~= 100
    addText('Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto the world in exchange for a small sacrifice\n\n', '#c0c0c0')
    if unfairDeath then
        addText('This death penalty has been reduced by ' .. tostring(100 - penalty) .. '%\nbecause it was an unfair fight.\n\n', '#c0c0c0')
    elseif deathType == DeathType.Blessed then
        addText('This death penalty has been reduced by 100%\nbecause you are blessed with the Adventurer\'s Blessing\n\n', '#c0c0c0')
    end
    addText('Simply click on ', '#c0c0c0')
    addText('Ok ', '#ffffff')
    addText('to resume your journeys in game\nor on ', '#c0c0c0')
    addText('Cancel ', '#ffffff')
    addText('to get to your character list!\n\nClick on ', '#c0c0c0')
    addText('Store ', '#ffffff')
    addText('to resume your journeys and to shop\nblessings to ease the pain if you are unfortunate\nenough to lose another fight!', '#c0c0c0')

    window:setWidth(window.baseWidth or 369)
    local expandedMessage = unfairDeath or deathType == DeathType.Blessed
    window:setHeight((window.baseHeight or 217) + (expandedMessage and 46 or 15))
    textLabel:setColoredText(table.concat(message))

    if g_modalManager then
        g_modalManager.show(window)
    end

    local storeButton = window:getChildById('buttonStore')
    local okButton = window:getChildById('buttonOk')
    local cancelButton = window:getChildById('buttonCancel')

    local okFunc = function()
        CharacterList.doLogin()
        deathController.ui = destroyWindows()
    end
    local cancelFunc = function()
        g_game.safeLogout()
        deathController.ui = destroyWindows()
    end

    local storeFunc = function()
        if g_game.setDead then
            g_game.setDead(false)
        end
        if modules.game_store and modules.game_store.show then
            modules.game_store.show()
        end
        deathController.ui = destroyWindows()
    end

    deathController.ui.onEnter = okFunc
    deathController.ui.onEscape = cancelFunc

    okButton.onClick = okFunc
    cancelButton.onClick = cancelFunc
    storeButton.onClick = storeFunc
end

function scheduleReconnect()
    if not g_settings.getBoolean('autoReconnect') then
        return
    end
    deathController:scheduleEvent(function()
        deathController.ui = destroyWindows()
        g_game.cancelLogin()
        CharacterList.doLogin()
    end, 2000, 'scheduleAutoReconnect')
end
