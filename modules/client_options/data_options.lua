return {
    vsync                             = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            g_window.setVerticalSync(value)
            if value then
                -- Let the driver pace frames; fall back to a software cap if vsync did not apply.
                g_app.setMaxFps(0)
                scheduleEvent(function()
                    if not modules.client_options.getOption('vsync') then
                        return
                    end
                    if g_window.hasVerticalSyncApplied and not g_window.hasVerticalSyncApplied() then
                        g_app.setMaxFps(100)
                    end
                end, 150)
            else
                local maxFps = options.backgroundFrameRate and options.backgroundFrameRate.value or 100
                local v = maxFps
                if maxFps <= 0 or maxFps >= 501 then
                    v = 0
                end
                g_app.setMaxFps(v)
            end
        end
    },
    showFps                           = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            modules.client_topmenu.setFpsVisible(value)
        end
    },
    showPing                          = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets, force)
            modules.client_topmenu.setPingVisible(value)
            local hud = panels.interfaceHUD
            local panel = hud and hud:recursiveGetChildById('showPingPositionPanel')
            if panel then
                panel:setVisible(value)
                if value then
                    panel:setHeight(22)
                else
                    panel:setHeight(0)
                end
            end
            -- When enabling from the UI, nudge scrollbar. Skip bootstrap (force).
            if value and hud and not force then
                addEvent(function()
                    local scroll = hud:recursiveGetChildById('hudScrollBar')
                    local area = hud:recursiveGetChildById('hudScrollArea')
                    if area then
                        area:updateLayout()
                    end
                    if panel and area and area.ensureChildVisible then
                        area:ensureChildVisible(panel)
                    elseif scroll then
                        local step = 29 -- panel height 22 + margin 7
                        scroll:setValue(math.min(scroll:getMaximum(), scroll:getValue() + step))
                    end
                end)
            end
        end
    },
    showPingPosition                  = {
        value = 1,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_topmenu and modules.client_topmenu.updatePingWidgetPosition then
                -- Pass value: setOption saves option.value AFTER this action runs
                modules.client_topmenu.updatePingWidgetPosition(value)
            end
            local labels = {
                [1] = 'Top Left',
                [2] = 'Top Right',
                [3] = 'Bottom Left',
                [4] = 'Bottom Right'
            }
            local widget = panels.interfaceHUD and panels.interfaceHUD:recursiveGetChildById('showPingPosition')
            if widget then
                widget:setText(tr('Position Show Ping: %s', labels[value] or 'Top Left'))
            end
        end
    },
    fullscreen                        = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            g_window.setFullscreen(value)
        end
    },
    classicControl                    = {
        value = g_platform.isMobile() and true or false,
        action = function(value, options, controller, panels, extraWidgets)
            -- Update the mouseControlMode based on this option
            -- 0 = Regular Controls, 1 = Classic Controls, 2 = Left Smart-Click
            local mouseControlMode = 0
            if value == true then
                mouseControlMode = 1 -- Classic Controls
            elseif options.smartLeftClick.value == true then
                mouseControlMode = 2 -- Left Smart-Click
            else
                mouseControlMode = 0 -- Regular Controls
            end
            
            -- Update the value in options table first
            options.mouseControlMode.value = mouseControlMode
            
            -- Then update settings
            g_settings.set('mouseControlMode', mouseControlMode)
            
            -- Update loot control visibility (only visible for Classic Controls)
            local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')
            if lootControlModeCombobox then
                lootControlModeCombobox:setVisible(mouseControlMode == 1)
            end
            
            -- Update the combobox UI
            local mouseControlModeCombobox = panels.generalPanel:recursiveGetChildById('mouseControlMode')
            if mouseControlModeCombobox then
                mouseControlModeCombobox:setCurrentOptionByData(mouseControlMode, true)
            end
        end
    },
    smartLeftClick                    = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            -- Update the mouseControlMode based on this option
            -- 0 = Regular Controls, 1 = Classic Controls, 2 = Left Smart-Click
            local mouseControlMode = 0
            if options.classicControl.value == true then
                mouseControlMode = 1 -- Classic Controls
            elseif value == true then
                mouseControlMode = 2 -- Left Smart-Click
            else
                mouseControlMode = 0 -- Regular Controls
            end
            
            -- Update the value in options table first
            options.mouseControlMode.value = mouseControlMode
            
            -- Then update settings
            g_settings.set('mouseControlMode', mouseControlMode)
            
            -- Update loot control visibility (only visible for Classic Controls)
            local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')
            if lootControlModeCombobox then
                lootControlModeCombobox:setVisible(mouseControlMode == 1)
            end
            
            -- Update the combobox UI
            local mouseControlModeCombobox = panels.generalPanel:recursiveGetChildById('mouseControlMode')
            if mouseControlModeCombobox then
                mouseControlModeCombobox:setCurrentOptionByData(mouseControlMode, true)
            end
        end
    },
    mouseControlMode                  = {
        value = 0, -- Default to "Regular Controls"
        action = function(value, options, controller, panels, extraWidgets)
            -- Update the underlying options values first
            -- 0 = Regular Controls, 1 = Classic Controls, 2 = Left Smart-Click
            if value == 0 then
                options.classicControl.value = false
                options.smartLeftClick.value = false
                g_settings.set('classicControl', false)
                g_settings.set('smartLeftClick', false)
            elseif value == 1 then
                options.classicControl.value = true
                options.smartLeftClick.value = false
                g_settings.set('classicControl', true)
                g_settings.set('smartLeftClick', false)
            elseif value == 2 then
                options.classicControl.value = false
                options.smartLeftClick.value = true
                g_settings.set('classicControl', false)
                g_settings.set('smartLeftClick', true)
            end
            
            -- Schedule UI updates to ensure they happen after value updates
            scheduleEvent(function()
                -- Update the mouseControlMode combobox
                local mouseControlModeCombobox = panels.generalPanel:recursiveGetChildById('mouseControlMode')
                if mouseControlModeCombobox then
                    -- Force the combobox to select the right option
                    for i = 0, 2 do
                        if i == value then
                            mouseControlModeCombobox:setCurrentOptionByData(i)
                            break
                        end
                    end
                end
                
                -- Update loot control mode visibility (only visible for Classic Controls)
                local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')
                if lootControlModeCombobox then
                    lootControlModeCombobox:setVisible(value == 1)
                end
            end, 50)
        end
    },
    lootControlMode                   = {
        value = 0, -- Default to "Loot: Right"
        action = function(value, options, controller, panels, extraWidgets)
            -- We need a small delay to ensure the UI updates correctly
            scheduleEvent(function()
                -- Update the lootControlMode combobox - get it fresh each time
                local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')
                if lootControlModeCombobox then
                    -- Force the combobox to select the right option
                    for i = 0, 2 do
                        if i == value then
                            lootControlModeCombobox:setCurrentOptionByData(i)
                            break
                        end
                    end
                end
            end, 50)
        end
    },
    smartWalk                         = false,
    alwaysTurnTowardsMoveDirection    = true,
    allowInspect                      = false,
    autoChaseOverride                 = true,
    talkOnRightClick                  = false,
    quickAllCorpses                   = false,
    storeAskBeforeBuyingProducts      = true,
    stowContainer                     = true,
    stayLoggedInforSession            = {
        value = false,
        action = function(value)
            g_settings.set('staylogged', value and true or false)
            if EnterGame and EnterGame.setStayLoggedChecked then
                EnterGame.setStayLoggedChecked(value and true or false)
            elseif modules.client_entergame and modules.client_entergame.setStayLoggedChecked then
                modules.client_entergame.setStayLoggedChecked(value and true or false)
            end
        end
    },
    optimiseConnectionStability       = {
        value = true,
        action = function(value)
            if g_game and g_game.setConnectionStabilityOptimisation then
                g_game.setConnectionStabilityOptimisation(value and true or false)
            elseif g_game and g_game.setPingDelay then
                -- Fallback before C++ rebuild: keep-alive ping interval only.
                g_game.setPingDelay(value and 1000 or 5000)
                if g_game.setNewPingDelay then
                    g_game.setNewPingDelay(value and 250 or 2000)
                end
            end
        end
    },
    quickLogin                        = {
        value = true,
        action = function()
            if type(applyAsyncTextureLoading) == 'function' then
                applyAsyncTextureLoading()
            elseif modules.client_options and modules.client_options.applyAsyncTextureLoading then
                modules.client_options.applyAsyncTextureLoading()
            end
        end
    },
    -- Unchecked (default): hold Ctrl to move the full stack.
    -- Checked: move the full stack without holding Ctrl.
    moveStack                         = false,
    useDefaultKeyboardDelay           = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            local delay = value and 250 or (options.keyboardDelay and options.keyboardDelay.value or 120)
            if type(applyKeyboardDelay) == 'function' then
                applyKeyboardDelay(delay)
            elseif modules.game_interface and modules.game_interface.getRootPanel then
                local panel = modules.game_interface.getRootPanel()
                if panel then
                    panel:setAutoRepeatDelay(delay)
                end
            end
            local delayWidget = panels.generalPanel and panels.generalPanel:recursiveGetChildById('keyboardDelay')
            if delayWidget then
                -- Keep the label enabled so $disabled does not override text color.
                local valueBar = delayWidget:recursiveGetChildById('valueBar')
                if valueBar then
                    valueBar:setEnabled(not value)
                end
                delayWidget:setEnabled(true)
                delayWidget:setOpacity(1.0)
                -- Red when using default (slider locked); orange when custom delay is active.
                delayWidget:setColor(value and '#ff4444ff' or '#df9f4fff')
            end
        end
    },
    keyboardDelay                     = {
        value = 120,
        action = function(value, options, controller, panels, extraWidgets)
            panels.generalPanel:recursiveGetChildById('keyboardDelay'):setText(
                tr('Keyboard Delay: %s ms', value))
            local delayWidget = panels.generalPanel:recursiveGetChildById('keyboardDelay')
            if delayWidget then
                local useDefault = options.useDefaultKeyboardDelay and options.useDefaultKeyboardDelay.value
                delayWidget:setColor(useDefault and '#ff4444ff' or '#df9f4fff')
            end
            if options.useDefaultKeyboardDelay and options.useDefaultKeyboardDelay.value then
                return
            end
            if type(applyKeyboardDelay) == 'function' then
                applyKeyboardDelay(value)
            elseif modules.game_interface and modules.game_interface.getRootPanel then
                local panel = modules.game_interface.getRootPanel()
                if panel then
                    panel:setAutoRepeatDelay(value)
                end
            end
        end
    },
    turnModifierCtrl                  = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            -- Rebind after option.value is updated by setOption.
            scheduleEvent(function()
                if type(rebindTurnKeys) == 'function' then
                    rebindTurnKeys()
                end
            end, 1)
        end
    },
    turnModifierShift                 = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            scheduleEvent(function()
                if type(rebindTurnKeys) == 'function' then
                    rebindTurnKeys()
                end
            end, 1)
        end
    },
    turnModifierAlt                   = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            scheduleEvent(function()
                if type(rebindTurnKeys) == 'function' then
                    rebindTurnKeys()
                end
            end, 1)
        end
    },
    showStatusMessagesInConsole       = true,
    showEventMessagesInConsole        = true,
    showInfoMessagesInConsole         = true,
    showTimestampsInConsole           = true,
    showLevelsInConsole               = true,
    showPrivateMessagesInConsole      = true,
    showOthersStatusMessagesInConsole = true,
    showPrivateMessagesOnScreen       = {
        value = true
    },
    showLootMessagesOnScreen          = {
        value = true
    },
    showMessages                      = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyShowMessagesCascade then
                modules.client_options.applyShowMessagesCascade(value)
            end
        end
    },
    potionSoundEffect                 = {
        value = true
    },
    showSpells                        = {
        value = true
    },
    spellsOthers                      = {
        value = true
    },
    showHotkeyMessagesInConsole       = {
        value = true
    },
    showBoostedMessagesInConsole      = {
        value = true
    },
    trainingProgress                  = {
        value = true
    },
    storeNotification                 = {
        value = true
    },
    lootHighlight                     = {
        value = true
    },
    combatFrames                      = {
        value = true
    },
    pvpFrames                         = {
        value = true
    },
    markTargetVisually                = {
        value = 1,
        action = function(value, options, controller, panels, extraWidgets)
            local index = tonumber(value) or 1
            if index < 1 then index = 1 end
            if index > 4 then index = 4 end
            local box = panels.interfaceGameWindow and panels.interfaceGameWindow:recursiveGetChildById('markTargetVisually')
            if box and box.setCurrentIndex then
                box:setCurrentIndex(index, true)
            end
            if modules.game_battle and modules.game_battle.refreshTargetMark then
                modules.game_battle.refreshTargetMark()
            end
        end
    },
    enableChatHistory                 = true,
    showHighlightedUnderline          = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            local settings = g_settings.getNode('game_console') or {}
            settings.showHighlightedUnderline = value
            g_settings.setNode('game_console', settings)
            if modules and modules.game_console and modules.game_console.setShowHighlightedUnderline then
                modules.game_console.setShowHighlightedUnderline(value)
            end
        end
    },
    showOutfitsOnList                 = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            CharacterList.updateCharactersAppearances(value)
        end
    },
    openMinimized                     = false,
    backgroundFrameRate               = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            local text, v = value, value
            if value <= 0 or value >= 501 then
                text = 'max'
                v = 0
            end

            panels.graphicsPanel:recursiveGetChildById('backgroundFrameRate'):setText(tr('Game framerate limit: %s', text))

            -- VSync already paces rendering; do not fight it with an unlimited software loop.
            if options.vsync and options.vsync.value then
                g_app.setMaxFps(0)
                return
            end

            g_app.setMaxFps(v)
        end
    },
    enableAudio                       = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if g_sounds then
                g_sounds.setAudioEnabled(value)
            end

            if value then
                extraWidgets.audioButton:setIcon('/images/topbuttons/button_mute_up')
            else
                extraWidgets.audioButton:setIcon('/images/topbuttons/button_mute_pressed')
            end
        end
    },
    enableMusicSound                  = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if g_sounds then
                g_sounds.getChannel(SoundChannels.Music):setEnabled(value)
            end
        end
    },
    musicSoundVolume                  = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if g_sounds then
                g_sounds.getChannel(SoundChannels.Music):setGain(value / 100)
            end
            panels.soundPanel:recursiveGetChildById('musicSoundVolume'):setText(tr('Music volume: %d', value))
        end
    },
    enableLights                      = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            panels.gameMapPanel:setDrawLights(value and options.ambientLight.value < 100)
            panels.graphicsEffectsPanel:recursiveGetChildById('ambientLight'):setEnabled(value)
        end
    },
    limitVisibleDimension             = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            panels.gameMapPanel:setLimitVisibleDimension(value)
        end
    },
    floatingEffect                    = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            g_map.setFloatingEffect(value)
        end
    },
    ambientLight                      = {
        value = 0,
        action = function(value, options, controller, panels, extraWidgets)
            panels.graphicsEffectsPanel:recursiveGetChildById('ambientLight'):setText(string.format(
                'Ambient light: %s%%', value))
            panels.gameMapPanel:setMinimumAmbientLight(value / 100)
            panels.gameMapPanel:setDrawLights(options.enableLights.value)
        end
    },
    ownHUDCharacter                   = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            local hud = panels.interfaceHUD
            local children = { 'showOwnBars', 'showOwnName', 'showOwnHealth', 'showOwnMana', 'displayHarmony' }
            if hud then
                for _, id in ipairs(children) do
                    local w = hud:recursiveGetChildById(id)
                    if w then
                        w:setEnabled(value)
                    end
                end
            end
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            end
        end
    },
    showOwnBars                       = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            end
        end
    },
    showOwnName                       = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            end
        end
    },
    showOwnHealth                     = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            end
        end
    },
    showOwnMana                       = {
        value = (function()
            if g_settings.exists('showOwnMana') then
                return g_settings.getBoolean('showOwnMana')
            end
            if g_settings.exists('displayMana') then
                return g_settings.getBoolean('displayMana')
            end
            return true
        end)(),
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            end
            if g_gameConfig.isDrawingInformationByWidget() then
                modules.game_creatureinformation.toggleInformation()
            end
        end
    },
    otherHUDCreatures                 = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            local hud = panels.interfaceHUD
            local children = { 'displayNames', 'displayHealth' }
            if hud then
                for _, id in ipairs(children) do
                    local w = hud:recursiveGetChildById(id)
                    if w then
                        w:setEnabled(value)
                    end
                end
            end
            if modules.client_options and modules.client_options.applyOtherHUD then
                modules.client_options.applyOtherHUD(options, panels)
            end
        end
    },
    displayNames                      = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOtherHUD then
                modules.client_options.applyOtherHUD(options, panels)
            else
                panels.gameMapPanel:setDrawNames(value)
            end

            if g_gameConfig.isDrawingInformationByWidget() then
                modules.game_creatureinformation.toggleInformation()
            end
        end
    },
    displayHealth                     = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOtherHUD then
                modules.client_options.applyOtherHUD(options, panels)
            else
                panels.gameMapPanel:setDrawHealthBars(value)
            end

            if g_gameConfig.isDrawingInformationByWidget() then
                modules.game_creatureinformation.toggleInformation()
            end
        end
    },
    displayMana                       = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            -- Legacy key: keep in sync with showOwnMana / own HUD.
            if options.showOwnMana then
                options.showOwnMana.value = value
            end
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            else
                panels.gameMapPanel:setDrawManaBar(value)
            end

            if g_gameConfig.isDrawingInformationByWidget() then
                modules.game_creatureinformation.toggleInformation()
            end
        end
    },
    displayHarmony                     = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.applyOwnHUD then
                modules.client_options.applyOwnHUD(options, panels)
            else
                panels.gameMapPanel:setDrawHarmony(value)
            end
        end
    },
    showHealthManaCircle              = {
        value = not g_settings.getBoolean('healthcircle_hpcircle') and not g_settings.getBoolean('healthcircle_mpcircle'),
        action = function(value, options, controller, panels, extraWidgets)
            -- Convenience master: toggles both health and mana arcs together.
            modules.client_options.setOption('healthCheckBox', value and true or false, true)
            modules.client_options.setOption('manaCheckBox', value and true or false, true)
        end
    },
    healthCheckBox                    = {
        value = not g_settings.getBoolean('healthcircle_hpcircle'),
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthcircle then
                modules.game_healthcircle.setHealthCircle(value)
            end
            if options.showHealthManaCircle and options.manaCheckBox then
                local bothOn = value and options.manaCheckBox.value
                options.showHealthManaCircle.value = bothOn
                g_settings.set('showHealthManaCircle', bothOn)
                local hud = panels.interfaceHUD
                local master = hud and hud:recursiveGetChildById('showHealthManaCircle')
                if master then
                    master:setChecked(bothOn)
                end
            end
        end
    },
    manaCheckBox                      = {
        value = not g_settings.getBoolean('healthcircle_mpcircle'),
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthcircle then
                modules.game_healthcircle.setManaCircle(value)
            end
            if options.showHealthManaCircle and options.healthCheckBox then
                local bothOn = options.healthCheckBox.value and value
                options.showHealthManaCircle.value = bothOn
                g_settings.set('showHealthManaCircle', bothOn)
                local hud = panels.interfaceHUD
                local master = hud and hud:recursiveGetChildById('showHealthManaCircle')
                if master then
                    master:setChecked(bothOn)
                end
            end
        end
    },
    experienceCheckBox                = {
        value = g_settings.getBoolean('healthcircle_expcircle'),
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthcircle then
                modules.game_healthcircle.setExpCircle(value)
            end
        end
    },
    skillCheckBox                     = {
        value = g_settings.getBoolean('healthcircle_skillcircle'),
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthcircle then
                modules.game_healthcircle.setSkillCircle(value)
            end
        end
    },
    sizeBox                           = {
        value = (function()
            if g_settings.exists('sizeBox') then
                local v = g_settings.getNumber('sizeBox')
                if v >= 1 and v <= 3 then
                    return v
                end
            end
            if g_settings.exists('healthcircle_style') then
                return math.max(1, math.min(3, g_settings.getNumber('healthcircle_style') + 1))
            end
            return 2
        end)(),
        action = function(value, options, controller, panels, extraWidgets)
            local index = tonumber(value) or 2
            if index < 1 then index = 1 end
            if index > 3 then index = 3 end
            if modules.game_healthcircle and modules.game_healthcircle.setArcStyle then
                modules.game_healthcircle.setArcStyle(index - 1)
            end
            local hud = panels.interfaceHUD
            local box = hud and hud:recursiveGetChildById('sizeBox')
            if box and box.setCurrentIndex then
                box:setCurrentIndex(index, true)
            end
        end
    },
    displayText                       = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            g_app.setDrawTexts(value)
        end
    },
    walkTurnDelay                     = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            panels.generalPanel:recursiveGetChildById('walkTurnDelay'):setText(
                tr('Walk delay after turn: %s ms', value))
        end
    },
    walkFirstStepDelay                = {
        value = 80,
        action = function(value, options, controller, panels, extraWidgets)
            panels.generalPanel:recursiveGetChildById('walkFirstStepDelay'):setText(
                tr('Walk delay after first step: %s ms', value))
        end
    },
    walkCtrlTurnDelay                 = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            panels.generalPanel:recursiveGetChildById('walkCtrlTurnDelay'):setText(
                tr('Walk delay after ctrl turn: %s ms', value))
        end
    },
    walkTeleportDelay                 = {
        value = 200,
        action = function(value, options, controller, panels, extraWidgets)
            panels.generalPanel:recursiveGetChildById('walkTeleportDelay'):setText(
                tr('Walk delay after teleport: %s ms', value))
        end
    },
    walkStairsDelay                   = {
        value = 200,
        action = function(value, options, controller, panels, extraWidgets)
            panels.generalPanel:recursiveGetChildById('walkStairsDelay'):setText(
                tr('Walk delay after floor change: %s ms', value))
        end
    },
    crosshair                         = {
        value = 'default',
        action = function(value, options, controller, panels, extraWidgets)
            local crossPath = '/images/game/crosshair/'
            local newValue = value
            if newValue == 'disabled' then
                newValue = nil
            end

            panels.gameMapPanel:setCrosshairTexture(newValue and crossPath .. newValue or nil)
            panels.interface:recursiveGetChildById('crosshair'):setCurrentOptionByData(newValue, true)
        end
    },
    nativeCursor = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            if value then
                -- Disable animated cursor when native cursor is enabled
                if options.showAnimatedCursor.value then
                    options.showAnimatedCursor.value = false
                    g_settings.set('showAnimatedCursor', false)
                    panels.gameMapPanel:setCursorAnimations(false)
                    -- Update the UI checkbox
                    local widget = panels.interface:recursiveGetChildById('showAnimatedCursor')
                    if widget then
                        widget:setChecked(false)
                    end
                end
                -- Set native cursor mode flag
                g_mouse.setUseNativeCursor(true)
                -- Push cursor to mark as changed (prevents game from overriding)
                g_mouse.pushCursor('window')
                -- Then restore to native Windows cursor
                g_window.restoreMouseCursor()
            else
                g_mouse.setUseNativeCursor(false)
                g_mouse.popCursor('window')
            end
        end
    },
    enableHighlightMouseTarget        = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            panels.gameMapPanel:setDrawHighlightTarget(value)
        end
    },
    showAnimatedCursor = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if value then
                -- Disable native cursor when animated cursor is enabled
                if options.nativeCursor.value then
                    options.nativeCursor.value = false
                    g_settings.set('nativeCursor', false)
                    g_mouse.popCursor('window')
                    -- Update the UI checkbox
                    local widget = panels.interface:recursiveGetChildById('nativeCursor')
                    if widget then
                        widget:setChecked(false)
                    end
                end
            end
            panels.gameMapPanel:setCursorAnimations(value)
        end
    },
    showDragIcon        = {
        value = true,
    },
    antialiasingMode                  = {
        value = 2, -- Smooth Retro
        action = function(value, options, controller, panels, extraWidgets)
            panels.gameMapPanel:setAntiAliasingMode(value)
            panels.graphicsPanel:recursiveGetChildById('antialiasingMode'):setCurrentOptionByData(value, true)
        end
    },
    graphicsEngine                    = {
        -- 0 = auto, 1 = DirectX 12 (UI label), 2 = OpenGL, 3 = Vulkan
        -- Persistencia real en config.ini: solo "gl" o "vulkan" (3).
        value = 0,
        action = function(value, options, controller, panels, extraWidgets)
            if not panels or not panels.graphicsPanel then
                return
            end

            local combo = panels.graphicsPanel:recursiveGetChildById('graphicsEngine')
            if combo then
                combo:setCurrentOptionByData(value, true)
            end

            if modules.client_options and modules.client_options.updateGraphicsEngineHelpTooltip then
                modules.client_options.updateGraphicsEngineHelpTooltip(panels, value)
            end
        end
    },
    hdGraphics                        = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            if g_sprites and g_sprites.setScaleFactor then
                g_sprites.setScaleFactor(value and 2 or 1)
            end

            if panels.gameMapPanel then
                panels.gameMapPanel:setAntiAliasingMode(options.antialiasingMode.value)
            end
        end
    },
    shadowFloorIntensity              = {
        value = 30,
        action = function(value, options, controller, panels, extraWidgets)
            panels.graphicsEffectsPanel:recursiveGetChildById('shadowFloorIntensity'):setText(string.format(
                'Shadow floor Intensity: %s%%', value))
            panels.gameMapPanel:setShadowFloorIntensity(1 - (value / 100))
        end
    },
    optimizeFps                       = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            g_app.optimize(value)
        end
    },
    forceEffectOptimization           = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            g_app.forceEffectOptimization(value)
        end
    },
    drawEffectOnTop                   = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            g_app.setDrawEffectOnTop(value)
        end
    },
    floorViewMode                     = {
        value = 1,
        action = function(value, options, controller, panels, extraWidgets)
            panels.gameMapPanel:setFloorViewMode(value)
            panels.graphicsEffectsPanel:recursiveGetChildById('floorViewMode'):setCurrentOptionByData(value, true)

            local fadeMode = value == 1
            panels.graphicsEffectsPanel:recursiveGetChildById('floorFading'):setEnabled(fadeMode)
        end
    },
    floorFading                       = {
        value = 500,
        action = function(value, options, controller, panels, extraWidgets)
            panels.graphicsEffectsPanel:recursiveGetChildById('floorFading'):setText(string.format('Floor Fading: %s ms',
                value))
            panels.gameMapPanel:setFloorFading(tonumber(value))
        end
    },
    asyncTxtLoading                   = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            if g_game.isUsingProtobuf() then
                value = true
                options.asyncTxtLoading.value = true
            elseif g_app.isEncrypted() then
                local asyncWidget = panels.graphicsPanel:recursiveGetChildById('asyncTxtLoading')
                if asyncWidget then
                    asyncWidget:setEnabled(false)
                    asyncWidget:setChecked(false)
                end
                options.asyncTxtLoading.value = false
            end

            if type(applyAsyncTextureLoading) == 'function' then
                applyAsyncTextureLoading()
            elseif modules.client_options and modules.client_options.applyAsyncTextureLoading then
                modules.client_options.applyAsyncTextureLoading()
            else
                g_app.setLoadingAsyncTexture(value)
            end
        end
    },
    hudScale                          = {
        event = nil,
        value = g_platform.isMobile() and 2 or 0,
        action = function(value, options, controller, panels, extraWidgets)
            value = value / 2

            if options.hudScale.event ~= nil then
                removeEvent(options.hudScale.event)
            end

            options.hudScale.event = scheduleEvent(function()
                g_app.setHUDScale(math.max(value + 0.5, 1))
                options.hudScale.event = nil
            end, 250)

            local hudWidget = panels.interfaceHUD:recursiveGetChildById('hudScale')
            hudWidget:setText(string.format('HUD Scale: %sx', math.max(value + 0.5, 1)))
        end
    },
    creatureInformationScale          = {
        value = g_platform.isMobile() and 2 or 0,
        action = function(value, options, controller, panels, extraWidgets)
            if value == 0 then
                value = g_window.getDisplayDensity() - 0.5
            else
                value = value / 2
            end
            g_app.setCreatureInformationScale(math.max(value + 0.5, 1))
            panels.interfaceHUD:recursiveGetChildById('creatureInformationScale'):setText(string.format(
                'Creature Information Scale: %sx', math.max(value + 0.5, 1)))
        end
    },
    staticTextScale                   = {
        value = g_platform.isMobile() and 2 or 0,
        action = function(value, options, controller, panels, extraWidgets)
            if value == 0 then
                value = g_window.getDisplayDensity() - 0.5
            else
                value = value / 2
            end
            g_app.setStaticTextScale(math.max(value + 0.5, 1))
            panels.interfaceHUD:recursiveGetChildById('staticTextScale'):setText(string.format('Message Scale: %sx',
                math.max(value + 0.5, 1)))
        end
    },
    animatedTextScale                 = {
        value = g_platform.isMobile() and 2 or 0,
        action = function(value, options, controller, panels, extraWidgets)
            if value == 0 then
                value = g_window.getDisplayDensity() - 0.5
            else
                value = value / 2
            end
            g_app.setAnimatedTextScale(math.max(value + 0.5, 1))
            panels.interfaceHUD:recursiveGetChildById('animatedTextScale'):setText(
                tr('Animated Message Scale: %sx', math.max(value + 0.5, 1)))
        end
    },
    conditionIconSize                 = {
        value = 2,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthcircle and modules.game_healthcircle.ConditionsHUD then
                modules.game_healthcircle.ConditionsHUD.setIconSize(value)
            end
            local labels = {[1] = 'Small', [2] = 'Medium', [3] = 'Large'}
            panels.interfaceHUD:recursiveGetChildById('conditionIconSize'):setText(
                tr('Condition Icon Size: %s', labels[value] or 'Medium'))
        end
    },
    showConditionInfo                 = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            -- Pass the new value explicitly: setOption updates option.value AFTER this action.
            if modules.game_healthcircle and modules.game_healthcircle.StatusIconBar then
                modules.game_healthcircle.StatusIconBar.refreshIcons(value)
            end
        end
    },
    showLeftExtraPanel                = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            modules.game_interface.getLeftExtraPanel():setOn(value)
            -- Update action bars when left extra panel visibility changes
            if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
                addEvent(function()
                    modules.game_actionbar.updateVisibleWidgetsExternal()
                end)
            end
        end
    },
    showLeftPanel                     = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            modules.game_interface.getLeftPanel():setOn(value)
            -- Update action bars when left panel visibility changes
            if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
                addEvent(function()
                    modules.game_actionbar.updateVisibleWidgetsExternal()
                end)
            end
        end
    },
    showRightExtraPanel               = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            modules.game_interface.getRightExtraPanel():setOn(value)
            -- Update action bars when right extra panel visibility changes
            if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
                addEvent(function()
                    modules.game_actionbar.updateVisibleWidgetsExternal()
                end)
            end
        end
    },
    showSpellGroupCooldowns           = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            modules.game_cooldown.setSpellGroupCooldownsVisible(value)
        end
    },
    dontStretchShrink                 = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            addEvent(function()
                modules.game_interface.updateStretchShrink()
            end)
        end
    },
    setEffectAlphaScroll              = {
        -- Removed from Effects UI; keep full opacity (Own Spell Effects replaces it).
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            g_client.setEffectAlpha(1)
        end
    },
    setMissileAlphaScroll             = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if value < 10 then value = 10 end
            if g_client and g_client.setMissileAlpha then
                g_client.setMissileAlpha(value / 100)
            end
            local panel = panels and panels.graphicsEffectsPanel
            local widget = panel and panel:recursiveGetChildById('setMissileAlphaScroll')
            if widget then
                widget:setText(tr('Opacity Missile: %s%%', value))
            end
        end
    },
    setOwnSpellEffectAlphaScroll = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if value < 10 then value = 10 end
            if g_client and g_client.setOwnSpellEffectAlpha then
                g_client.setOwnSpellEffectAlpha(value / 100)
            end
            local panel = panels and panels.graphicsEffectsPanel
            local widget = panel and panel:recursiveGetChildById('setOwnSpellEffectAlphaScroll')
            if widget then
                widget:setText(tr('Own Spell Effects: %s%%', value))
            end
        end
    },
    setOtherPlayerSpellEffectAlphaScroll = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if value < 10 then value = 10 end
            if g_client and g_client.setOtherPlayerSpellEffectAlpha then
                g_client.setOtherPlayerSpellEffectAlpha(value / 100)
            end
            local panel = panels and panels.graphicsEffectsPanel
            local widget = panel and panel:recursiveGetChildById('setOtherPlayerSpellEffectAlphaScroll')
            if widget then
                widget:setText(tr("Other Players' Effects: %s%%", value))
            end
        end
    },
    setCreatureSpellEffectAlphaScroll = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if value < 10 then value = 10 end
            if g_client and g_client.setCreatureSpellEffectAlpha then
                g_client.setCreatureSpellEffectAlpha(value / 100)
            end
            local panel = panels and panels.graphicsEffectsPanel
            local widget = panel and panel:recursiveGetChildById('setCreatureSpellEffectAlphaScroll')
            if widget then
                widget:setText(tr('Creature Spell Effects: %s%%', value))
            end
        end
    },
    setBossAreaCreatureEffectAlphaScroll = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if value < 10 then value = 10 end
            if g_client and g_client.setBossAreaCreatureEffectAlpha then
                g_client.setBossAreaCreatureEffectAlpha(value / 100)
            end
            local panel = panels and panels.graphicsEffectsPanel
            local widget = panel and panel:recursiveGetChildById('setBossAreaCreatureEffectAlphaScroll')
            if widget then
                widget:setText(tr('Boss Area Creature Spell Effects: %s%%', value))
            end
        end
    },
    distFromCenScrollbar              = {
        value = (function()
            if g_settings.exists('distFromCenScrollbar') then
                return g_settings.getNumber('distFromCenScrollbar')
            end
            if g_settings.exists('healthcircle_distfromcenter') then
                return g_settings.getNumber('healthcircle_distfromcenter')
            end
            return 0
        end)(),
        action = function(value, options, controller, panels, extraWidgets)
            local hud = panels.interfaceHUD
            local bar = hud and hud:recursiveGetChildById('distFromCenScrollbar')
            if bar then
                bar:setText(tr('Distance: %s', value))
            end
            if modules.game_healthcircle then
                modules.game_healthcircle.setDistanceFromCenter(value)
            end
        end
    },
    opacityScrollbar                  = {
        value = (function()
            if g_settings.exists('opacityScrollbar') then
                return g_settings.getNumber('opacityScrollbar')
            end
            if g_settings.exists('healthcircle_opacity') then
                return math.floor(g_settings.getNumber('healthcircle_opacity') * 100)
            end
            return 35
        end)(),
        action = function(value, options, controller, panels, extraWidgets)
            local hud = panels.interfaceHUD
            local bar = hud and hud:recursiveGetChildById('opacityScrollbar')
            if bar then
                bar:setText(tr('Opacity: %s', value / 100))
            end
            if modules.game_healthcircle then
                modules.game_healthcircle.setCircleOpacity(value / 100)
            end
        end
    },
    profile                           = {
        value = 1,
    },
    rightJoystick                     = {
        value = false,
        action = function(value, options, controller, panels, extraWidgets)
            if not g_platform.isMobile() then return end
            if value == true then
                modules.game_shortcuts.getPanel():breakAnchors()
                modules.game_shortcuts.getPanel():addAnchor(AnchorBottom, "parent", AnchorBottom)
                modules.game_shortcuts.getPanel():addAnchor(AnchorLeft, "parent", AnchorLeft)

                modules.game_joystick.getPanel():breakAnchors()
                modules.game_joystick.getPanel():addAnchor(AnchorBottom, "parent", AnchorBottom)
                modules.game_joystick.getPanel():addAnchor(AnchorRight, "parent", AnchorRight)
            else
                modules.game_joystick.getPanel():breakAnchors()
                modules.game_joystick.getPanel():addAnchor(AnchorBottom, "parent", AnchorBottom)
                modules.game_joystick.getPanel():addAnchor(AnchorLeft, "parent", AnchorLeft)

                modules.game_shortcuts.getPanel():breakAnchors()
                modules.game_shortcuts.getPanel():addAnchor(AnchorBottom, "parent", AnchorBottom)
                modules.game_shortcuts.getPanel():addAnchor(AnchorRight, "parent", AnchorRight)
            end
        end
    },
    showExpiryInInvetory              = {
        value = true,
        event = nil,
        action = function(value, options, controller, panels, extraWidgets)
            if options.showExpiryInInvetory.event ~= nil then
                removeEvent(options.showExpiryInInvetory.event)
            end
            options.showExpiryInInvetory.event = scheduleEvent(function()
                if modules.game_inventory and modules.game_inventory.reloadInventory then
                    modules.game_inventory.reloadInventory()
                end
                options.showExpiryInInvetory.event = nil
            end, 100)
        end
    },
    showExpiryInContainers            = {
        value = true,
        event = nil,
        action = function(value, options, controller, panels, extraWidgets)
            if options.showExpiryInContainers.event ~= nil then
                removeEvent(options.showExpiryInContainers.event)
            end
            options.showExpiryInContainers.event = scheduleEvent(function()
                modules.game_containers.reloadContainers()
                options.showExpiryInContainers.event = nil
            end, 100)
        end
    },
    showExpiryOnUnusedItems           = true,
    framesRarity                      = {
        value = 'frames',
        event = nil,
        action = function(value, options, controller, panels, extraWidgets)
            local newValue = value
            if newValue == 'None' then
                newValue = nil
            end
            panels.interface:recursiveGetChildById('frames'):setCurrentOptionByData(newValue, true)
            if options.framesRarity.event ~= nil then
                removeEvent(options.framesRarity.event)
            end
            options.framesRarity.event = scheduleEvent(function()
                modules.game_containers.reloadContainers()
                options.framesRarity.event = nil
            end, 100)
        end
    },
    autoSwitchPreset                  = {
        value = false,
        action = function(value, options, controller, panels)
            -- Both hotkey pages expose this setting. Synchronize them after
            -- setOption stores the new value to avoid recursive change events.
            scheduleEvent(function()
                for _, panel in ipairs({ panels.keybindsPanel, panels.customHotkeys }) do
                    if panel and panel.presets then
                        local widget = panel.presets.autoSwitchPreset
                        if widget and widget:isChecked() ~= value then
                            widget:setChecked(value)
                        end
                    end
                end
            end)
        end
    },
    listKeybindsPanel                 = {
        action = function(value, options, controller, panels, extraWidgets)
            listKeybindsComboBox(value)
        end
    },
    graphicalCooldown = {
        value = true,
        action = function(value)
            modules.game_actionbar.toggleCooldownOption()
        end,
    },
    cooldownSecond = {
        value = true,
        action = function(value)
            modules.game_actionbar.toggleCooldownOption()
        end,
    },
    showSpellAnimation = {
        value = true,
    },
    showOptionsFrameAnimation = {
        value = true,
        action = function(value)
            if modules.client_options.applyOptionsFrameAnimation then
                modules.client_options.applyOptionsFrameAnimation(value ~= false)
            end
        end
    },
    autoAssignSpell = {
        value = true,
    },
    actionBarShowBottom1 = {
        value = true,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar13") or false
            modules.game_actionbar.configureActionBar('actionBarShowBottom1', allBox and value)
        end,
    },
    actionBarShowBottom2 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar13") or false
            modules.game_actionbar.configureActionBar('actionBarShowBottom2', allBox and value)
        end,
    },
    actionBarShowBottom3 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar13") or false
            modules.game_actionbar.configureActionBar('actionBarShowBottom3', allBox and value)
        end,
    },
    actionBarShowLeft1 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar46") or false
            modules.game_actionbar.configureActionBar('actionBarShowLeft1', allBox and value)
        end,
    },
    actionBarShowLeft2 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar46") or false
            modules.game_actionbar.configureActionBar('actionBarShowLeft2', allBox and value)
        end,
    },
    actionBarShowLeft3 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar46") or false
            modules.game_actionbar.configureActionBar('actionBarShowLeft3', allBox and value)
        end,
    },
    actionBarShowRight1 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar79") or false
            modules.game_actionbar.configureActionBar('actionBarShowRight1', allBox and value)
            return true
        end,
    },
    actionBarShowRight2 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar79") or false
            modules.game_actionbar.configureActionBar('actionBarShowRight2', allBox and value)
        end,
    },
    actionBarShowRight3 = {
        value = false,
        action = function(value)
            local allBox = modules.client_options.getOption("allActionBar79") or false
            modules.game_actionbar.configureActionBar('actionBarShowRight3', allBox and value)
        end,
    },
    allActionBar46 = {
        value = false,
        action = function(value)
            local huds = {"actionBarShowLeft1", "actionBarShowLeft2", "actionBarShowLeft3"}
            for _, actionBar in pairs(huds) do
                local hud =  panels.actionbars:recursiveGetChildById(actionBar)
                if value then
                    hud:enable()
                else
                    hud:disable()
                end
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
        end,
    },
    allActionBar13 = {
        value = true,
        action = function(value)
            local huds = {"actionBarShowBottom1", "actionBarShowBottom2", "actionBarShowBottom3"}
            for _, actionBar in pairs(huds) do
                local hud =  panels.actionbars:recursiveGetChildById(actionBar)
                if value then
                    hud:enable()
                else
                    hud:disable()
                end
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
        end,
    },
    allActionBar79 = {
        value = false,
        action = function(value)
            local huds = {"actionBarShowRight1", "actionBarShowRight2", "actionBarShowRight3"}
            for _, actionBar in pairs(huds) do
                local hud = panels.actionbars:recursiveGetChildById(actionBar)
                if value then
                    hud:enable()
                else
                    hud:disable()
                end
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
        end,
    },
    actionTooltip = {
        value = true,
        action = function(value)
            modules.game_actionbar.updateVisibleOptions('tooltip', value)
        end,
    },
    showSpellParameters = {
        value = true,
        action = function(value)
            modules.game_actionbar.updateVisibleOptions('parameter', value)
        end,
    },
    showHKObjectsBars = {
        value = true,
        action = function(value)
            modules.game_actionbar.updateVisibleOptions('amount', value)
        end,
    },
    showAssignedHKButton = {
        value = true,
        action = function(value)
            modules.game_actionbar.updateVisibleOptions('hotkey', value)
        end,
    },
    actionBarBottomLocked = false,
    actionBarLeftLocked = false,
    actionBarRightLocked = false,
    showCustomisableStatusBars = {
        value = (g_settings.getString("statsbar_dimension") ~= "" and g_settings.getString("statsbar_dimension") or "compact") ~= "hide",
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthcircle then
                local currentPlacement = g_settings.getString("statsbar_placement")
                if currentPlacement == "" then currentPlacement = "top" end
                local newDimension = "hide"
                if value then
                    newDimension = g_settings.getString("statsbar_dimension")
                    if newDimension == "" or newDimension == "hide" then
                        newDimension = "compact"
                    end
                end
                modules.game_healthcircle.setStatsBarOption(newDimension, currentPlacement)
                modules.game_healthcircle.updateStatsBar()
            end
        end
    },
    showStatusBars = {
        value = true,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.game_healthinfo and modules.game_healthinfo.healthManaController and modules.game_healthinfo.healthManaController.ui then
                if value then
                    modules.game_healthinfo.healthManaController.ui:show()
                else
                    modules.game_healthinfo.healthManaController.ui:hide()
                end
                if modules.game_healthinfo.iconTopMenu then
                    modules.game_healthinfo.iconTopMenu:setOn(value)
                end
            end
        end
    },
    showInfoBanner = true,

    showAnimationMaster = {
        value = true,
        action = function(value)
            if modules.client_options and modules.client_options.applyAnimationMaster then
                modules.client_options.applyAnimationMaster(value ~= false)
            end
        end
    },
    showAnimationSkillBar = {
        value = true
    },
    showAnimationLevelBar = {
        value = true
    },
    showAnimationHealthBar = {
        value = true
    },
    showAnimationManaBar = {
        value = true
    },
    showAnimationHudHealthBar = {
        value = true,
        action = function()
            if modules.client_options and modules.client_options.syncNameplateBarAnimation then
                modules.client_options.syncNameplateBarAnimation()
            end
        end
    },
    showAnimationHudManaBar = {
        value = true,
        action = function()
            if modules.client_options and modules.client_options.syncNameplateBarAnimation then
                modules.client_options.syncNameplateBarAnimation()
            end
        end
    },
    showAnimationArcs = {
        value = true
    },
    uiBarAnimationSpeed = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            if modules.client_options and modules.client_options.syncNameplateBarAnimation then
                modules.client_options.syncNameplateBarAnimation()
            elseif g_gameConfig and g_gameConfig.setUiBarAnimationSpeed then
                g_gameConfig.setUiBarAnimationSpeed(tonumber(value) or 100)
            end
            local widget = panels.graphicsAnimationPanel and
                panels.graphicsAnimationPanel:recursiveGetChildById('uiBarAnimationSpeed')
            if widget then
                widget:setText(tr('Animation Speed: %s%%', value))
            end
        end
    },

    showOutfitAnimationMaster = {
        value = true,
        action = function(value)
            if modules.client_options and modules.client_options.applyOutfitAnimationMaster then
                modules.client_options.applyOutfitAnimationMaster(value ~= false)
            end
        end
    },
    showOutfitAnimationFloor = {
        value = true
    },
    showOutfitAnimationOutfit = {
        value = true
    },
    showOutfitAnimationAddon = {
        value = true
    },
    showOutfitAnimationMount = {
        value = true
    },
    showOutfitAnimationFamiliar = {
        value = true
    },
    outfitAnimationSpeed = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            local widget = panels.graphicsAnimationPanel and
                panels.graphicsAnimationPanel:recursiveGetChildById('outfitAnimationSpeed')
            if widget then
                widget:setText(tr('Animation Speed: %s%%', value))
            end
        end
    },

    showSlideAnimationMaster = {
        value = true,
        action = function(value)
            if modules.client_options and modules.client_options.applySlideAnimationMaster then
                modules.client_options.applySlideAnimationMaster(value ~= false)
            end
        end
    },
    showOptionsAnimation = {
        value = true
    },
    showStoreAnimation = {
        value = true
    },
    slideAnimationSpeed = {
        value = 100,
        action = function(value, options, controller, panels, extraWidgets)
            local widget = panels.graphicsAnimationPanel and
                panels.graphicsAnimationPanel:recursiveGetChildById('slideAnimationSpeed')
            if widget then
                widget:setText(tr('Animation Speed: %s%%', value))
            end
        end
    },
}
