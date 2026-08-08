local iconTopMenu = nil
local healthManaReady = false

local function setBarWidth(barWidget, targetWidth, percentDelta, optionKey)
    local animateEnabled = true
    if modules.client_options and modules.client_options.isBarAnimationEnabled and optionKey then
        animateEnabled = modules.client_options.isBarAnimationEnabled(optionKey)
    elseif modules.client_options and modules.client_options.getOption and optionKey then
        animateEnabled = modules.client_options.getOption(optionKey) ~= false
    end

    if not healthManaReady or not animateEnabled then
        g_effects.cancelWidth(barWidget)
        barWidget._animWidth = targetWidth
        barWidget:setWidth(math.max(1, math.floor(targetWidth + 0.5)))
    else
        -- Longer vital duration so small HP/MP changes are still visible.
        local duration = nil
        if modules.client_options and percentDelta then
            local speed = modules.client_options.getOption('uiBarAnimationSpeed') or 100
            local factor = 100 / math.max(speed, 1)
            duration = math.max(80, math.floor(math.min(1800, math.max(550, 420 + math.abs(percentDelta) * 18)) * factor + 0.5))
        end
        g_effects.animateWidth(barWidget, targetWidth, duration)
    end
end

local function healthManaEvent()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local health = player:getHealth()
    local maxHealth = math.max(player:getMaxHealth(), 1)
    local mana = player:getMana()
    local maxMana = math.max(player:getMaxMana(), 1)

    healthManaController.ui.health.text:setText(health)
    healthManaController.ui.mana.text:setText(mana)

    local healthTotalW = healthManaController.ui.health.total:getWidth()
    local manaTotalW = healthManaController.ui.mana.total:getWidth()

    local healthPercent = (health / maxHealth) * 100
    local manaPercent = (mana / maxMana) * 100
    local healthWidth = math.max(12, (healthTotalW * health) / maxHealth)
    local manaWidth = math.max(12, (manaTotalW * mana) / maxMana)

    local healthBar = healthManaController.ui.health.current
    local manaBar = healthManaController.ui.mana.current
    local healthDelta = math.abs(healthPercent - (healthBar._animPercent or healthPercent))
    local manaDelta = math.abs(manaPercent - (manaBar._animPercent or manaPercent))
    healthBar._animPercent = healthPercent
    manaBar._animPercent = manaPercent

    setBarWidth(healthBar, healthWidth, healthDelta, 'showAnimationHealthBar')
    setBarWidth(manaBar, manaWidth, manaDelta, 'showAnimationManaBar')
    healthManaReady = true
end

healthManaController = Controller:new()
healthManaController:setUI('healthinfo', modules.game_interface.getMainRightPanel())

function healthManaController:onInit()
end

function healthManaController:onTerminate()
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end
end

function healthManaController:onGameStart()
    healthManaReady = false
    healthManaController:registerEvents(LocalPlayer, {
        onHealthChange = healthManaEvent,
        onManaChange = healthManaEvent
    }):execute()
end

function healthManaController:onGameEnd()
    healthManaReady = false
    if healthManaController.ui then
        g_effects.cancelWidth(healthManaController.ui.health.current)
        g_effects.cancelWidth(healthManaController.ui.mana.current)
    end
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('healthMana', tr('Show health'),
                '/images/topbuttons/healthinfo', toggle)
            iconTopMenu:setOn(healthManaController.ui:isVisible())
            healthManaController.ui:setBorderColor('black')
            healthManaController.ui:setBorderWidth(2)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        healthManaController.ui:setBorderColor('alpha')
        healthManaController.ui:setBorderWidth(0)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if not mainRightPanel:hasChild(healthManaController.ui) then
            mainRightPanel:insertChild(2, healthManaController.ui)
        end
        healthManaController.ui:show()
    end
    healthManaController.ui.moveOnlyToMain = not extendedView
end

function toggle()
    if iconTopMenu:isOn() then
        healthManaController.ui:hide()
        iconTopMenu:setOn(false)
    else
        healthManaController.ui:show()
        iconTopMenu:setOn(true)
    end
end
