local options = dofile("data_options")
local autoSwitchPresetEvent = nil
local turnModifierIds = { 'turnModifierCtrl', 'turnModifierShift', 'turnModifierAlt' }

panels = {
    generalPanel = nil,
    graphicsPanel = nil,
    soundPanel = nil,
    gameMapPanel = nil,
    graphicsEffectsPanel = nil,
    interfaceHUD = nil,
    interfaceGameWindow = nil,
    interface = nil,
    misc = nil,
    miscGameplay = nil,
    miscHelp = nil,
    keybindsPanel = nil,
    customHotkeys = nil
}

local GAME_WINDOW_MESSAGE_CHILDREN = {
    'showPrivateMessagesOnScreen',
    'potionSoundEffect',
    'showSpells',
    'spellsOthers',
    'showHotkeyMessagesInConsole',
    'showLootMessagesOnScreen',
    'showBoostedMessagesInConsole',
    'trainingProgress',
    'storeNotification'
}
local showMessagesCascadeLock = false

-- Hook into application exit to ensure settings are saved
local function onAppExit()
    g_settings.save()
end

-- Register the exit hook when the module is loaded
connect(g_app, { onExit = onAppExit })

-- LuaFormatter off
local buttons = { {

    text = "Controls",
    icon = "/images/icons/icon_controls",
    open = "generalPanel",
    subCategories = { {
        text = "General Hotk...",
        open = "keybindsPanel"
    }, {
        text = "Custom Hotk...",
        open = "customHotkeys"
    } }
}, {
    text = "Interface",
    icon = "/images/icons/icon_interface",
    open = "interface",
    subCategories = { {
        text = "HUD",
        open = "interfaceHUD"
    }, {
        text = "Game Window",
        open = "interfaceGameWindow"
    }, {
        text = "Console",
        open = "interfaceConsole"
    }, {
        text = "Action Bars",
        open = "actionbars"
    } }
}, {
    text = "Graphics",
    icon = "/images/icons/icon_graphics",
    open = "graphicsPanel",
    subCategories = { {
        text = "Effects",
        open = "graphicsEffectsPanel"
    } }
}, {
    text = "Sound",
    icon = "/images/icons/icon_sound",
    open = "soundPanel"
    --[[     subCategories = {{
        text = "Battle Sounds",
        open = "Battle_Sounds"
    }, {
        text = "UI Sounds",
        open = "UI_Sounds"
    }} ]]
}, {
    text = "Misc.",
    icon = "/images/icons/icon_misc",
    open = "misc",
    subCategories = { {
        text = "Gameplay",
        open = "miscGameplay"
    }, {
        text = "Help",
        open = "miscHelp"
    } }
} }

-- LuaFormatter on
local extraWidgets = {
    audioButton = nil,
    optionsButton = nil,
    logoutButton = nil,
    optionsButtons = nil
}

local function toggleDisplays()
    local manaKey = options['showOwnMana'] and 'showOwnMana' or 'displayMana'
    if options['displayNames'].value and options['displayHealth'].value and options[manaKey].value and options['displayHarmony'].value then
        setOption('displayNames', false)
    elseif options['displayHealth'].value then
        setOption('displayHealth', false)
        setOption(manaKey, false)
        setOption('displayHarmony', false)
    else
        if not options['displayNames'].value and not options['displayHealth'].value then
            setOption('displayNames', true)
        else
            setOption('displayHealth', true)
            setOption(manaKey, true)
            setOption('displayHarmony', true)
        end
    end
end

local function toggleOption(key)
    setOption(key, not getOption(key))
end

local function setupComboBox()
    local crosshairCombo = panels.interface:recursiveGetChildById('crosshair')
    local antialiasingModeCombobox = panels.graphicsPanel:recursiveGetChildById('antialiasingMode')
    local floorViewModeCombobox = panels.graphicsEffectsPanel:recursiveGetChildById('floorViewMode')
    local framesRarityCombobox = panels.interface:recursiveGetChildById('frames')
    local vocationPresetsCombobox = panels.keybindsPanel:recursiveGetChildById('list')
    local listKeybindsPanel = panels.keybindsPanel:recursiveGetChildById('list')
    local mouseControlModeCombobox = panels.generalPanel:recursiveGetChildById('mouseControlMode')
    local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')

    for k, v in pairs({ { 'Disabled', 'disabled' }, { 'Default', 'default' }, { 'Full', 'full' }, { 'Animation', 'animation' } }) do
        crosshairCombo:addOption(v[1], v[2])
    end

    crosshairCombo.onOptionChange = function(comboBox, option)
        setOption('crosshair', comboBox:getCurrentOption().data)
    end

    mouseControlModeCombobox:addOption('Regular Controls', 0)
    mouseControlModeCombobox:addOption('Classic Controls', 1)
    mouseControlModeCombobox:addOption('Left Smart-Click', 2)

    lootControlModeCombobox:addOption('Loot: Right', 0)
    lootControlModeCombobox:addOption('Loot: SHIFT+Right', 1)
    lootControlModeCombobox:addOption('Loot: Left', 2)
    
    lootControlModeCombobox.onOptionChange = function(comboBox, option)
        setOption('lootControlMode', comboBox:getCurrentOption().data)
    end

    mouseControlModeCombobox.onOptionChange = function(comboBox, option)
        local selectedOption = comboBox:getCurrentOption().data
        setOption('mouseControlMode', selectedOption)
        
        -- The mouseControlMode action handler will take care of updating
        -- classicControl and smartLeftClick, and their UI visibility
    end

    for k, t in pairs({ 'None', 'Antialiasing', 'Smooth Retro' }) do
        antialiasingModeCombobox:addOption(t, k - 1)
    end

    antialiasingModeCombobox.onOptionChange = function(comboBox, option)
        setOption('antialiasingMode', comboBox:getCurrentOption().data)
    end

    local sizeBox = panels.interfaceHUD and panels.interfaceHUD:recursiveGetChildById('sizeBox')
    if sizeBox then
        sizeBox:addOption(tr('Small Size'), 1)
        sizeBox:addOption(tr('Default Size'), 2)
        sizeBox:addOption(tr('Large Size'), 3)
        sizeBox.onOptionChange = function(comboBox, option)
            setOption('sizeBox', comboBox.currentIndex)
        end
    end

    local markTargetBox = panels.interfaceGameWindow and panels.interfaceGameWindow:recursiveGetChildById('markTargetVisually')
    if markTargetBox then
        markTargetBox:addOption(tr('Frame & Highlight'), 1)
        markTargetBox:addOption(tr('Frame Only'), 2)
        markTargetBox:addOption(tr('Highlight Only'), 3)
        markTargetBox:addOption(tr('None'), 4)
        markTargetBox.onOptionChange = function(comboBox, option)
            setOption('markTargetVisually', comboBox.currentIndex)
        end
    end


    for k, t in pairs({ 'Normal', 'Fade', 'Locked', 'Always', 'Always with transparency' }) do
        floorViewModeCombobox:addOption(t, k - 1)
    end

    floorViewModeCombobox.onOptionChange = function(comboBox, option)
        setOption('floorViewMode', comboBox:getCurrentOption().data)
    end

    for k, v in pairs({ { 'None', 'none' }, { 'Frames', 'frames' }, { 'Corners', 'corners' } }) do
        framesRarityCombobox:addOption(v[1], v[2])
    end

    framesRarityCombobox.onOptionChange = function(comboBox, option)
        setOption('framesRarity', comboBox:getCurrentOption().data)
    end

    local profileCombobox = panels.misc:recursiveGetChildById('profile')

    for i = 1, 10 do
        profileCombobox:addOption(tostring(i), i)
    end

    profileCombobox.onOptionChange = function(comboBox, option)
        setOption('profile', comboBox:getCurrentOption().data)
    end

    for _, preset in ipairs(Keybind.presets) do
        listKeybindsPanel:addOption(preset)
    end
    listKeybindsPanel.onOptionChange = function(comboBox, option)
        setOption('listKeybindsPanel', option)
    end
    panels.keybindsPanel.presets.list:setCurrentOption(Keybind.currentPreset)
end

local function setup()
    panels.gameMapPanel = modules.game_interface.getMapPanel()

    setupComboBox()

    -- load options
    for k, obj in pairs(options) do
        local v = obj.value

        if k ~= 'classicControl' and k ~= 'smartLeftClick' and k ~= 'mouseControlMode' and k ~= 'showHealthManaCircle' then
            if type(v) == 'boolean' then
                local value = g_settings.getBoolean(k)
                setOption(k, value, true)
            elseif type(v) == 'number' then
                local value = g_settings.getNumber(k)
                setOption(k, value, true)
            elseif type(v) == 'string' then
                local value = g_settings.getString(k)
                setOption(k, value, true)
            end
        end
    end

    -- Sync arc master checkbox from individual HP/MP without forcing arcs off/on.
    if options.showHealthManaCircle and options.healthCheckBox and options.manaCheckBox then
        local bothOn = options.healthCheckBox.value and options.manaCheckBox.value
        options.showHealthManaCircle.value = bothOn
        g_settings.set('showHealthManaCircle', bothOn)
        local hud = panels.interfaceHUD
        local master = hud and hud:recursiveGetChildById('showHealthManaCircle')
        if master then
            master:setChecked(bothOn)
        end
    end
    
    -- Special handling for mouseControlMode to ensure it's in sync with the underlying options
    local classicControl = g_settings.getBoolean('classicControl')
    local smartLeftClick = g_settings.getBoolean('smartLeftClick')
    local mouseControlMode = 0
    if classicControl then
        mouseControlMode = 1
    elseif smartLeftClick then
        mouseControlMode = 2
    end
    setOption('mouseControlMode', mouseControlMode, true)

    -- Keep only one turn modifier selected (Ctrl / Shift / Alt).
    local selectedTurn = nil
    for _, id in ipairs(turnModifierIds) do
        if options[id] and options[id].value then
            if selectedTurn then
                setOption(id, false, true)
            else
                selectedTurn = id
            end
        end
    end
    if not selectedTurn then
        setOption('turnModifierCtrl', true, true)
    end
    
    -- Schedule combobox updates to ensure they happen after UI setup is complete
    scheduleEvent(function()
        local mouseControlModeCombobox = panels.generalPanel:recursiveGetChildById('mouseControlMode')
        local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')
        
        if mouseControlModeCombobox then
            -- Use setCurrentOptionByData for more precise control
            for i = 0, 2 do
                if i == options.mouseControlMode.value then
                    mouseControlModeCombobox:setCurrentOptionByData(i)
                    break
                end
            end
        end
        
        if lootControlModeCombobox then
            -- Use setCurrentOptionByData for more precise control
            for i = 0, 2 do
                if i == options.lootControlMode.value then
                    lootControlModeCombobox:setCurrentOptionByData(i)
                    break
                end
            end
        end
        
        -- Update loot control mode visibility
        if lootControlModeCombobox and mouseControlModeCombobox then
            if options.mouseControlMode.value == 1 then
                lootControlModeCombobox:setVisible(true)
            else
                lootControlModeCombobox:setVisible(false)
            end
        end
    end, 100)

    local talkOnRightClick = panels.miscGameplay and panels.miscGameplay:recursiveGetChildById('talkOnRightClick')
    if talkOnRightClick then
        local parent = talkOnRightClick:getParent()
        if g_game.getClientVersion() > 1511 then
            parent:setVisible(false)
            parent:setHeight(0)
            parent:setMarginTop(0)
        end
    end
end


controller = Controller:new()
controller:setUI('options')

function controller:onInit()
    for k, obj in pairs(options) do
        if type(obj) ~= "table" then
            obj = { value = obj }
            options[k] = obj
        end
        g_settings.setDefault(k, obj.value)
    end

    extraWidgets.audioButton = modules.client_topmenu.addTopRightToggleButton('audioButton', tr('Audio'),
        '/images/topbuttons/button_mute_up', function() toggleOption('enableAudio') end)

    extraWidgets.optionsButton = modules.client_topmenu.addTopRightToggleButton('optionsButton', tr('Options'),
        '/images/topbuttons/button_options', toggle)

    extraWidgets.logoutButton = modules.client_topmenu.addTopRightToggleButton('logoutButton', tr('Exit'),
        '/images/topbuttons/logout', toggle)

    panels.generalPanel = g_ui.loadUI('styles/controls/general', controller.ui.optionsTabContent)
    panels.keybindsPanel = g_ui.loadUI('styles/controls/keybinds', controller.ui.optionsTabContent)
    panels.customHotkeys = g_ui.loadUI('styles/controls/custom_hotkeys', controller.ui.optionsTabContent)

    panels.graphicsPanel = g_ui.loadUI('styles/graphics/graphics', controller.ui.optionsTabContent)
    panels.graphicsEffectsPanel = g_ui.loadUI('styles/graphics/effects', controller.ui.optionsTabContent)

    panels.interface = g_ui.loadUI('styles/interface/interface', controller.ui.optionsTabContent)
    panels.interfaceConsole = g_ui.loadUI('styles/interface/console', controller.ui.optionsTabContent)
    panels.interfaceHUD = g_ui.loadUI('styles/interface/HUD', controller.ui.optionsTabContent)
    panels.interfaceGameWindow = g_ui.loadUI('styles/interface/gameWindow', controller.ui.optionsTabContent)
    panels.actionbars = g_ui.loadUI('styles/interface/actionbars', controller.ui.optionsTabContent)

    panels.soundPanel = g_ui.loadUI('styles/sound/audio', controller.ui.optionsTabContent)

    panels.misc = g_ui.loadUI('styles/misc/misc', controller.ui.optionsTabContent)
    panels.miscGameplay = g_ui.loadUI('styles/misc/gameplay', controller.ui.optionsTabContent)
    panels.miscHelp = g_ui.loadUI('styles/misc/help', controller.ui.optionsTabContent)

    self.ui:hide()

    configureCharacterCategories()
    addEvent(setup)
    g_game.shouldShowLootHighlightEffect = shouldShowLootHighlightEffect
    g_game.shouldShowCombatFrames = shouldShowCombatFrames
    g_game.shouldShowPvpFrames = shouldShowPvpFrames
    
    -- Add a special delayed event to update comboboxes after everything is loaded
    scheduleEvent(function()
        local mouseControlModeCombobox = panels.generalPanel:recursiveGetChildById('mouseControlMode')
        local lootControlModeCombobox = panels.generalPanel:recursiveGetChildById('lootControlMode')
        
        if mouseControlModeCombobox then
            for i = 0, 2 do
                if i == options.mouseControlMode.value then
                    mouseControlModeCombobox:setCurrentOptionByData(i)
                    break
                end
            end
        end
        
        if lootControlModeCombobox then
            for i = 0, 2 do
                if i == options.lootControlMode.value then
                    lootControlModeCombobox:setCurrentOptionByData(i)
                    break
                end
            end
        end
    end, 1000)  -- 1 second delay to make sure everything is loaded
    
    init_binds()
    init_custom_hotkeys()

    Keybind.new("UI", "Toggle Fullscreen", "Ctrl+Shift+F", "")
    Keybind.bind("UI", "Toggle Fullscreen", {
        {
            type = KEY_DOWN,
            callback = function() toggleOption('fullscreen') end,
        }
    })
    Keybind.new("UI", "Show/hide FPS / lag indicator", "", "")
    Keybind.bind("UI", "Show/hide FPS / lag indicator", { {
        type = KEY_DOWN,
        callback = function()
            toggleOption('showPing')
            toggleOption('showFps')
        end
    } })
    Keybind.new("UI", "Show/hide connection ping", "Shift+R", "")
    Keybind.bind("UI", "Show/hide connection ping", { {
        type = KEY_DOWN,
        callback = function() toggleOption('showPing') end
    } })

    Keybind.new("UI", "Show/hide Creature Names and Bars", "Ctrl+N", "")
    Keybind.bind("UI", "Show/hide Creature Names and Bars", {
        {
            type = KEY_DOWN,
            callback = toggleDisplays,
        }
    })

    Keybind.new("Sound", "Mute/unmute", "", "")
    Keybind.bind("Sound", "Mute/unmute", {
        {
            type = KEY_DOWN,
            callback = function() toggleOption('enableAudio') end,
        }
    })
end

function controller:onTerminate()
    if autoSwitchPresetEvent then
        removeEvent(autoSwitchPresetEvent)
        autoSwitchPresetEvent = nil
    end

    -- Make sure all settings are saved before terminating
    g_settings.save()

    g_game.shouldShowLootHighlightEffect = nil
    g_game.shouldShowCombatFrames = nil
    g_game.shouldShowPvpFrames = nil
    
    -- Disconnect from app exit
    disconnect(g_app, { onExit = onAppExit })
    
    extraWidgets.optionsButton:destroy()
    extraWidgets.audioButton:destroy()
    panels = {}
    extraWidgets = {}
    buttons = {}
    Keybind.delete("UI", "Toggle Fullscreen")
    Keybind.delete("UI", "Show/hide Creature Names and Bars")
    Keybind.delete("UI", "Show/hide FPS / lag indicator")
    Keybind.delete("Sound", "Mute/unmute")

    terminate_binds()
    terminate_custom_hotkeys()
end

local function findPresetIgnoringCase(name)
    if not name or name == '' then
        return nil
    end

    local normalizedName = name:lower()
    for _, preset in ipairs(Keybind.presets) do
        if preset:lower() == normalizedName then
            return preset
        end
    end

    return nil
end

local function getCharacterVocationPreset(player)
    local vocationNames = {
        { name = 'Druid', check = 'isDruid' },
        { name = 'Knight', check = 'isKnight' },
        { name = 'Paladin', check = 'isPaladin' },
        { name = 'Sorcerer', check = 'isSorcerer' },
        { name = 'Monk', check = 'isMonk' }
    }

    for _, vocation in ipairs(vocationNames) do
        local check = player[vocation.check]
        if check and check(player) then
            return findPresetIgnoringCase(vocation.name)
        end
    end

    return nil
end

local function getAutomaticPreset(player)
    -- Character-specific presets take priority. The vocation fallback makes
    -- the default Druid/Knight/Paladin/Sorcerer/Monk presets useful as-is.
    return findPresetIgnoringCase(player:getName()) or getCharacterVocationPreset(player)
end

local function updatePresetWidgets(preset)
    if panels.keybindsPanel and panels.keybindsPanel.presets then
        panels.keybindsPanel.presets.list:setCurrentOption(preset, true)
        updateKeybinds()
    end

    if panels.customHotkeys and panels.customHotkeys.presets then
        panels.customHotkeys.presets.list:setCurrentOption(preset, true)
        updateCustomHotkeys()
    end
end

local function applyAutomaticPreset(attempt)
    autoSwitchPresetEvent = nil

    if not g_game.isOnline() or not g_settings.getBoolean("autoSwitchPreset") then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player or not player:getName() or player:getName() == '' then
        if attempt < 25 then
            autoSwitchPresetEvent = scheduleEvent(function()
                applyAutomaticPreset(attempt + 1)
            end, 200)
        end
        return
    end

    local preset = getAutomaticPreset(player)
    if not preset then
        -- The character name is available before vocation information on
        -- some protocols. Keep waiting so the vocation fallback can resolve.
        if attempt < 25 then
            autoSwitchPresetEvent = scheduleEvent(function()
                applyAutomaticPreset(attempt + 1)
            end, 200)
        else
            g_logger.warning(string.format(
                "[client_options] Auto-switch found no preset for character '%s' (vocation %s).",
                player:getName(), tostring(player:getVocation())))
        end
        return
    end

    if preset and (Keybind.currentPreset == preset or Keybind.selectPreset(preset)) then
        updatePresetWidgets(preset)
        g_settings.setValue("controls-preset-current", preset)

        if modules.game_actionbar and modules.game_actionbar.selectHotkeySet then
            if not modules.game_actionbar.selectHotkeySet(preset) then
                g_logger.warning(string.format("[client_options] Failed to sync action bar hotkey set '%s' on startup.", preset))
            end
        end
    end
end

function controller:onGameStart()
    if autoSwitchPresetEvent then
        removeEvent(autoSwitchPresetEvent)
    end

    -- onGameStart may fire while g_game still exposes the previous character
    -- name. Wait for the new local player object before resolving the preset.
    autoSwitchPresetEvent = scheduleEvent(function()
        applyAutomaticPreset(1)
    end, 100)

    -- When entering the game, the login screen buttons may have left 'pointerbutton'
    -- entries in the mouse cursor stack (from UIButton:onHoverChange). This makes
    -- g_mouse.isCursorChanged() return true, which blocks mapview.cpp from changing
    -- the animated cursor. We drain the stack here so cursor animations work immediately.
    if options.showAnimatedCursor.value then
        -- Pop any leftover cursors from the login screen buttons.
        -- We do this in a loop because multiple buttons could have been hovered.
        for _ = 1, 20 do
            if not g_mouse.isCursorChanged() then break end
            g_mouse.popCursor('pointerbutton')
            g_mouse.popCursor('window')
        end
    end

    -- Re-apply setCursorAnimations to ensure the map panel has the correct value.
    local gameMapPanel = modules.game_interface and modules.game_interface.getMapPanel()
    if gameMapPanel then
        gameMapPanel:setCursorAnimations(options.showAnimatedCursor.value)
    end

    if options.optimiseConnectionStability then
        setOption('optimiseConnectionStability', options.optimiseConnectionStability.value, true)
    end
    if type(applyAsyncTextureLoading) == 'function' then
        applyAsyncTextureLoading()
    end
end

function controller:onGameEnd()
    if autoSwitchPresetEvent then
        removeEvent(autoSwitchPresetEvent)
        autoSwitchPresetEvent = nil
    end
end

function onTurnModifierCheckChange(widget)
    if not widget or widget._turnModifierLock then
        return
    end

    local parent = widget:getParent()
    if not parent then
        return
    end

    -- Radio-style: keep exactly one modifier selected.
    if not widget:isChecked() then
        local anyOther = false
        for _, id in ipairs(turnModifierIds) do
            if id ~= widget:getId() then
                local other = parent:getChildById(id)
                if other and other:isChecked() then
                    anyOther = true
                    break
                end
            end
        end
        if not anyOther then
            widget._turnModifierLock = true
            widget:setChecked(true)
            widget._turnModifierLock = false
            return
        end
        setOption(widget:getId(), false)
        return
    end

    for _, id in ipairs(turnModifierIds) do
        if id ~= widget:getId() then
            local other = parent:getChildById(id)
            if other then
                other._turnModifierLock = true
                if other:isChecked() then
                    other:setChecked(false)
                end
                other._turnModifierLock = false
            end
            setOption(id, false)
        end
    end

    setOption(widget:getId(), true)
end

function setOption(key, value, force)
    if not modules.game_interface then
        return
    end

    -- Ignore checkbox events fired while visually syncing Show Messages children.
    if showMessagesCascadeLock then
        return
    end

    local option = options[key]
    if option == nil then
        g_logger.warning(string.format("[client_options] Attempted to set unknown option: '%s'", key))
        return
    end
    
    if not force and option.value == value then
        return
    end

    -- Update value before action so helpers like applyOwnHUD/applyOtherHUD
    -- read the new state (otherwise toggles apply inverted / stale values).
    option.value = value

    if option.action then
        option.action(value, options, controller, panels, extraWidgets, force)
    end


    -- Sync checkbox/scrollbar widgets across panels that share the same option id.
    -- Do not touch ComboBoxes here: setCurrentIndex/setCurrentOption retriggers
    -- onOptionChange and can freeze (e.g. mouseControlMode).
    for _, panel in pairs(panels) do
        if panel and not panel:isDestroyed() then
            local widget = panel:recursiveGetChildById(key)
            if widget then
                local styleClass = widget:getStyle().__class
                if styleClass == 'UICheckBox' or styleClass == 'QtCheckBox' then
                    -- Keep Show Messages children visually unchecked while master is off
                    -- (only in Game Window panel; Console shares some option ids).
                    if panel == panels.interfaceGameWindow
                        and key ~= 'showMessages'
                        and table.contains(GAME_WINDOW_MESSAGE_CHILDREN, key)
                        and options.showMessages and not options.showMessages.value then
                        widget:setChecked(false)
                        widget:setEnabled(false)
                        widget:setOpacity(0.5)
                    else
                        widget:setChecked(value)
                    end
                elseif styleClass == 'UIScrollBar' then
                    widget:setValue(value)
                elseif widget:recursiveGetChildById('valueBar') then
                    widget:recursiveGetChildById('valueBar'):setValue(value)
                end
            end
        end
    end

    g_settings.set(key, value)
end

function setupOptionsMainButton()
    if extraWidgets.optionsButtons then
        return
    end

    extraWidgets.optionsButtons = modules.game_mainpanel.addSpecialToggleButton('optionsMainButton', tr('Options'),
        '/images/options/button_options', toggle, true)
end

function getOption(key)
    local option = options[key]
    if option == nil then
        g_logger.warning(string.format("[client_options] Attempted to get unknown option: '%s'", key))
        return nil
    end
    return option.value
end

-- Safe boolean read for modules that must not treat nil as "on".
function getBoolOption(key, defaultValue)
    local value = getOption(key)
    if value == nil then
        if defaultValue == nil then
            return false
        end
        return defaultValue and true or false
    end
    return value and true or false
end

function applyOwnHUD(opts, panelTable)
    opts = opts or options
    panelTable = panelTable or panels
    local map = panelTable.gameMapPanel
    if not map then
        return
    end

    local ownEnabled = opts.ownHUDCharacter and opts.ownHUDCharacter.value
    if not ownEnabled then
        if map.setDrawPlayerBars then map:setDrawPlayerBars(false) end
        if map.setDrawPlayerNames then map:setDrawPlayerNames(false) end
        map:setDrawManaBar(false)
        map:setDrawHarmony(false)
        if g_gameConfig.isDrawingInformationByWidget() and modules.game_creatureinformation then
            modules.game_creatureinformation.toggleInformation()
        end
        return
    end

    local showBars = opts.showOwnBars and opts.showOwnBars.value
    local showHealth = opts.showOwnHealth and opts.showOwnHealth.value
    local showName = opts.showOwnName and opts.showOwnName.value
    local showMana = opts.showOwnMana and opts.showOwnMana.value
    local showHarmony = opts.displayHarmony and opts.displayHarmony.value

    -- Each of Health / Mana / Harmony is independent.
    -- Show Bars is only a master switch for those three.
    if not showBars then
        if map.setDrawPlayerBars then map:setDrawPlayerBars(false) end
        map:setDrawManaBar(false)
        map:setDrawHarmony(false)
    else
        if map.setDrawPlayerBars then
            map:setDrawPlayerBars(showHealth)
        end
        map:setDrawManaBar(showMana)
        map:setDrawHarmony(showHarmony)
    end
    if map.setDrawPlayerNames then
        map:setDrawPlayerNames(showName)
    end

    -- Keep legacy displayMana key in sync.
    if opts.displayMana then
        opts.displayMana.value = showMana
        g_settings.set('displayMana', showMana)
    end

    if g_gameConfig.isDrawingInformationByWidget() and modules.game_creatureinformation then
        modules.game_creatureinformation.toggleInformation()
    end
end

function applyOtherHUD(opts, panelTable)
    opts = opts or options
    panelTable = panelTable or panels
    local map = panelTable.gameMapPanel
    if not map then
        return
    end

    local othersEnabled = opts.otherHUDCreatures and opts.otherHUDCreatures.value
    if not othersEnabled then
        map:setDrawNames(false)
        map:setDrawHealthBars(false)
    else
        map:setDrawNames(opts.displayNames and opts.displayNames.value)
        map:setDrawHealthBars(opts.displayHealth and opts.displayHealth.value)
    end

    if g_gameConfig.isDrawingInformationByWidget() and modules.game_creatureinformation then
        modules.game_creatureinformation.toggleInformation()
    end
end

function applyShowMessagesCascade(enabled)
    local panel = panels.interfaceGameWindow
    if not panel then
        return
    end

    showMessagesCascadeLock = true
    for _, id in ipairs(GAME_WINDOW_MESSAGE_CHILDREN) do
        local widget = panel:recursiveGetChildById(id)
        if widget then
            widget:setEnabled(enabled)
            if enabled then
                local stored = options[id] and options[id].value
                if stored ~= nil then
                    widget:setChecked(stored and true or false)
                end
                widget:setOpacity(1.0)
            else
                -- Visual only: look unchecked while master is off, keep option.value.
                widget:setChecked(false)
                widget:setOpacity(0.5)
            end
        end
    end
    showMessagesCascadeLock = false
end

function resetGameWindow()
    setOption('displayText', true, true)
    setOption('showMessages', true, true)
    setOption('showPrivateMessagesInConsole', true, true)
    setOption('showPrivateMessagesOnScreen', true, true)
    setOption('potionSoundEffect', true, true)
    setOption('showSpells', true, true)
    setOption('spellsOthers', true, true)
    setOption('showHotkeyMessagesInConsole', true, true)
    setOption('showLootMessagesOnScreen', true, true)
    setOption('lootHighlight', true, true)
    setOption('showBoostedMessagesInConsole', true, true)
    setOption('trainingProgress', true, true)
    setOption('storeNotification', true, true)
    setOption('combatFrames', true, true)
    setOption('pvpFrames', true, true)
    setOption('markTargetVisually', 1, true)
end

function resetConsole()
    setOption('showInfoMessagesInConsole', true, true)
    setOption('showEventMessagesInConsole', true, true)
    setOption('showStatusMessagesInConsole', true, true)
    setOption('showOthersStatusMessagesInConsole', true, true)
    setOption('showTimestampsInConsole', true, true)
    setOption('showLevelsInConsole', true, true)
    setOption('enableChatHistory', true, true)
    setOption('showHighlightedUnderline', false, true)
end

function resetHUD()
    setOption('ownHUDCharacter', true, true)
    setOption('showOwnBars', true, true)
    setOption('showOwnName', true, true)
    setOption('showOwnHealth', true, true)
    setOption('showOwnMana', true, true)
    setOption('displayHarmony', true, true)
    setOption('otherHUDCreatures', true, true)
    setOption('displayNames', true, true)
    setOption('displayHealth', true, true)

    -- Arcs: Health + Mana on; Experience/Skill off (CIP-like defaults).
    setOption('healthCheckBox', true, true)
    setOption('manaCheckBox', true, true)
    setOption('showHealthManaCircle', true, true)
    setOption('experienceCheckBox', false, true)
    setOption('skillCheckBox', false, true)
    setOption('sizeBox', 2, true)
    setOption('distFromCenScrollbar', 0, true)
    setOption('opacityScrollbar', 35, true)

    setOption('showCustomisableStatusBars', true, true)
    setOption('showStatusBars', true, true)
    setOption('displayText', true, true)
    setOption('showPing', false, true)
    setOption('showPingPosition', 1, true)
    setOption('showConditionInfo', true, true)
    setOption('conditionIconSize', 2, true)

    local hudScaleDefault = g_platform.isMobile() and 2 or 0
    setOption('hudScale', hudScaleDefault, true)
    setOption('creatureInformationScale', hudScaleDefault, true)
    setOption('staticTextScale', hudScaleDefault, true)
    setOption('animatedTextScale', hudScaleDefault, true)

    if g_platform.isMobile() then
        setOption('rightJoystick', false, true)
    end
end

function shouldShowLootHighlightEffect()
    if g_settings.exists('lootHighlight') then
        return g_settings.getBoolean('lootHighlight')
    end
    return getBoolOption('lootHighlight', true)
end

function shouldShowCombatFrames()
    if g_settings.exists('combatFrames') then
        return g_settings.getBoolean('combatFrames')
    end
    return getBoolOption('combatFrames', true)
end

function shouldShowPvpFrames()
    if g_settings.exists('pvpFrames') then
        return g_settings.getBoolean('pvpFrames')
    end
    return getBoolOption('pvpFrames', true)
end

function resetGraphics()
    setOption('antialiasingMode', 2, true) -- Smooth Retro
    setOption('fullscreen', false, true)
    setOption('vsync', true, true)
    setOption('showFps', false, true)
    setOption('backgroundFrameRate', 100, true)
    setOption('optimizeFps', true, true)
    setOption('forceEffectOptimization', false, true)
    setOption('asyncTxtLoading', false, true)
    setOption('hdGraphics', false, true)
    setOption('dontStretchShrink', false, true)
end

function resetEffects()
    setOption('enableLights', true, true)
    setOption('ambientLight', 0, true)
    setOption('shadowFloorIntensity', 30, true)
    setOption('floorFading', 500, true)
    setOption('floorViewMode', 1, true)
    setOption('drawEffectOnTop', false, true)
    setOption('limitVisibleDimension', false, true)
    setOption('floatingEffect', false, true)
    setOption('setMissileAlphaScroll', 100, true)
    setOption('setOwnSpellEffectAlphaScroll', 100, true)
    setOption('setOtherPlayerSpellEffectAlphaScroll', 100, true)
    setOption('setCreatureSpellEffectAlphaScroll', 100, true)
    setOption('setBossAreaCreatureEffectAlphaScroll', 100, true)
end

function resetActionBars()
    setOption('allActionBar13', true, true)
    setOption('actionBarShowBottom1', true, true)
    setOption('actionBarShowBottom2', false, true)
    setOption('actionBarShowBottom3', false, true)
    setOption('allActionBar46', false, true)
    setOption('actionBarShowLeft1', false, true)
    setOption('actionBarShowLeft2', false, true)
    setOption('actionBarShowLeft3', false, true)
    setOption('allActionBar79', false, true)
    setOption('actionBarShowRight1', false, true)
    setOption('actionBarShowRight2', false, true)
    setOption('actionBarShowRight3', false, true)
    setOption('showAssignedHKButton', true, true)
    setOption('showHKObjectsBars', true, true)
    setOption('showSpellParameters', true, true)
    setOption('graphicalCooldown', true, true)
    setOption('cooldownSecond', true, true)
    setOption('showSpellAnimation', true, true)
    setOption('autoAssignSpell', true, true)
    setOption('actionTooltip', true, true)
end

function resetInterface()
    setOption('enableHighlightMouseTarget', true, true)
    setOption('nativeCursor', false, true)
    setOption('showAnimatedCursor', true, true)
    setOption('showDragIcon', true, true)
    setOption('showLeftPanel', true, true)
    setOption('showRightExtraPanel', false, true)
    setOption('showSpellGroupCooldowns', true, true)
    setOption('showInfoBanner', true, true)
    setOption('crosshair', 'default', true)
    setOption('framesRarity', 'frames', true)
    setOption('showExpiryInInvetory', true, true)
    setOption('showExpiryInContainers', true, true)
    setOption('showExpiryOnUnusedItems', true, true)
end

function resetControls()
    setOption('mouseControlMode', 0, true)
    setOption('lootControlMode', 0, true)
    setOption('smartWalk', false, true)
    setOption('alwaysTurnTowardsMoveDirection', true, true)
    setOption('moveStack', false, true)
    setOption('openMinimized', false, true)
    resetWalkAndKeyboardDelays()
end

function resetGameplay()
    setOption('allowInspect', false, true)
    setOption('autoChaseOverride', true, true)
    setOption('talkOnRightClick', false, true)
    setOption('quickAllCorpses', false, true)
end

function applyAsyncTextureLoading()
    if not g_app or not g_app.setLoadingAsyncTexture then
        return
    end

    -- Quick Login prioritizes entering the world ASAP (async textures).
    -- Graphics "Async texture loading" also requests async. Either one enables it.
    local wantAsync = false
    if options.quickLogin and options.quickLogin.value then
        wantAsync = true
    end
    if options.asyncTxtLoading and options.asyncTxtLoading.value then
        wantAsync = true
    end

    -- Protobuf always forces async; encrypted clients block it (handled in C++).
    if g_game and g_game.isUsingProtobuf and g_game.isUsingProtobuf() then
        wantAsync = true
    elseif g_app.isEncrypted and g_app.isEncrypted() then
        wantAsync = false
        local asyncWidget = panels.graphicsPanel and panels.graphicsPanel:recursiveGetChildById('asyncTxtLoading')
        if asyncWidget then
            asyncWidget:setEnabled(false)
            asyncWidget:setChecked(false)
        end
    end

    g_app.setLoadingAsyncTexture(wantAsync)
end

function resetMisc()
    setOption('storeAskBeforeBuyingProducts', true, true)
    setOption('stowContainer', true, true)
    setOption('stayLoggedInforSession', false, true)
    setOption('optimiseConnectionStability', true, true)
    setOption('quickLogin', true, true)
end

function resetWalkAndKeyboardDelays()
    -- Defaults from data_options.lua (walk delays + keyboard delay only).
    setOption('keyboardDelay', 120, true)
    setOption('useDefaultKeyboardDelay', true, true)
    setOption('walkTurnDelay', 100, true)
    setOption('walkFirstStepDelay', 80, true)
    setOption('walkCtrlTurnDelay', 100, true)
    setOption('walkTeleportDelay', 200, true)
    setOption('walkStairsDelay', 200, true)
end

function getKeyboardDelay()
    if getOption('useDefaultKeyboardDelay') then
        return 250
    end
    return getOption('keyboardDelay') or 120
end

function show()
    controller.ui:show()
    controller.ui:raise()
    controller.ui:focus()
end

function showCustomHotkeys()
    if not controller or not controller.ui then
        return
    end

    show()

    scheduleEvent(function()
        local controlsCategory = controller.ui.optionsTabBar:getChildByIndex(1)
        if controlsCategory and controlsCategory.Button then
            controlsCategory.Button:onClick()
            local customHotkeysCategory = controlsCategory:getChildById(2)
            if customHotkeysCategory and customHotkeysCategory.Button then
                customHotkeysCategory.Button:onClick()
            end
        elseif panels.customHotkeys then
            if controller.ui.selectedOption then
                controller.ui.selectedOption:hide()
            end
            panels.customHotkeys:show()
            panels.customHotkeys:setVisible(true)
            controller.ui.selectedOption = panels.customHotkeys
        end

        updateCustomHotkeys()
    end, 1)
end

function hide()
    -- Save all settings when closing the options window
    g_settings.save()
    controller.ui:hide()
end

function saveOptions()
    g_settings.save()
end

function toggle()
    if controller.ui:isVisible() then
        hide()
        return
    end
    if not controller.ui.openedCategory then
        local firstCategory = controller.ui.optionsTabBar:getChildByIndex(1)
        controller.ui.openedCategory = firstCategory
        firstCategory.Button:onClick()
        local panelToShow = panels[firstCategory.open]
        if panelToShow then
            panelToShow:show()
            controller.ui.selectedOption = panelToShow
        end
    end
    show()
    updateKeybinds()
    updateCustomHotkeys()
end

function addTab(name, panel, icon)
    -- deprecated: options use addButton categories instead of tabs
end

function removeTab(v)
    -- deprecated: options use addButton categories instead of tabs
end

local function toggleSubCategories(parent, isOpen)
    for subId, _ in ipairs(parent.subCategories) do
        local subWidget = parent:getChildById(subId)
        if subWidget then
            subWidget:setVisible(isOpen)
        end
    end
    parent:setHeight(isOpen and parent.openedSize or parent.closedSize)
    parent.opened = isOpen
    parent.Button.Arrow:setVisible(not isOpen)
end

local function close(parent)
    if parent.subCategories then
        toggleSubCategories(parent, false)
    end
end

local function open(parent)
    local oldOpen = controller.ui.openedCategory
    if oldOpen and oldOpen ~= parent then
        close(oldOpen)
    end
    toggleSubCategories(parent, true)
    controller.ui.openedCategory = parent
end

function selectCharacterPage()
    local selectedOption = controller.ui.selectedOption
    if selectedOption then
        selectedOption:hide()
    end
    if controller.ui.InfoBase then
        controller.ui.InfoBase:setVisible(true)
        controller.ui.InfoBase:show()
    end
end

local function createSubWidget(parent, subId, subButton)
    local subWidget = g_ui.createWidget("OptionsCategory", parent)
    subWidget:setId(subId)
    subWidget.Button.Icon:setIcon(subButton.icon)
    subWidget.Button.Title:setText(subButton.text)
    subWidget.Button.Title:setFont('Verdana Bold-11px')
    subWidget.Button.Title:setHeight(15)
    subWidget:setVisible(false)
    subWidget.open = subButton.open
    subWidget.callbackFunc = subButton.callbackFunc

    function subWidget.Button.onClick()
        local selectedOption = controller.ui.selectedOption
        closeCharacterButtons()
        parent.Button:setChecked(false)
        parent.Button.Arrow:setVisible(true)
        parent.Button.Arrow:setImageSource("")
        subWidget.Button:setChecked(true)
        subWidget.Button.Arrow:setVisible(true)
        subWidget.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-right")

        if selectedOption then
            selectedOption:hide()
        end

        local panelToShow = panels[subWidget.open]
        if panelToShow then
            panelToShow:show()
            panelToShow:setVisible(true)
            controller.ui.selectedOption = panelToShow
        else
            print("Error: panelToShow is nil or does not exist in panels")
        end
        if subWidget.callbackFunc then
            subWidget.callbackFunc()
        end
    end

    subWidget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
    if subId == 1 then
        subWidget:addAnchor(AnchorTop, "parent", AnchorTop)
        subWidget:setMarginTop(20)
    else
        subWidget:addAnchor(AnchorTop, "prev", AnchorBottom)
        subWidget:setMarginTop(-1)
    end

    return subWidget
end

function configureCharacterCategories()
    controller.ui.optionsTabBar:destroyChildren()

    for id, button in ipairs(buttons) do
        local widget = g_ui.createWidget("OptionsCategory", controller.ui.optionsTabBar)
        widget:setId(id)
        widget.Button.Icon:setIcon(button.icon)
        widget.Button.Title:setText(button.text)
        widget.open = button.open

        if button.subCategories then
            widget.subCategories = button.subCategories
            widget.subCategoriesSize = #button.subCategories
            widget.Button.Arrow:setVisible(true)

            for subId, subButton in ipairs(button.subCategories) do
                local subWidget = createSubWidget(widget, subId, subButton)
                if button.text == "Controls" or subButton.text == "Control Butt..." then
                    -- Leave room for the selection arrow without truncating
                    -- longer labels (General/Custom Hotk..., Control Butt...).
                    subWidget.Button.Title:setMarginLeft(4)
                    subWidget.Button.Title:setMarginRight(16)
                end
            end
        end

        widget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
        if id == 1 then
            widget:addAnchor(AnchorTop, "parent", AnchorTop)
            widget:setMarginTop(10)
        else
            widget:addAnchor(AnchorTop, "prev", AnchorBottom)
            widget:setMarginTop(10)
        end

        function widget.Button.onClick()
            local parent = widget
            local oldOpen = controller.ui.openedCategory

            if oldOpen and oldOpen ~= parent then
                if oldOpen.Button then
                    oldOpen.Button:setChecked(false)
                    oldOpen.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-down")
                end

                close(oldOpen)
            end

            if parent.subCategoriesSize then
                parent.closedSize = parent.closedSize or parent:getHeight() / (parent.subCategoriesSize + 1) + 15
                parent.openedSize = parent.openedSize or parent:getHeight() * (parent.subCategoriesSize + 1) - 6

                if not parent.opened then
                    open(parent)
                end
            end

            widget.Button:setChecked(true)
            widget.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-right")
            widget.Button.Arrow:setVisible(true)

            if controller.ui.selectedOption then
                controller.ui.selectedOption:hide()
            end

            local panelToShow = panels[parent.open]
            if panelToShow then
                closeCharacterButtons()
                panelToShow:show()
                panelToShow:setVisible(true)
                controller.ui.selectedOption = panelToShow
            else
                print("Error: panelToShow is nil or does not exist in panels")
            end

            controller.ui.openedCategory = parent
        end
    end
end

function closeCharacterButtons()
    for i = 1, controller.ui.optionsTabBar:getChildCount() do
        local widget = controller.ui.optionsTabBar:getChildByIndex(i)
        if widget and widget.subCategories then
            for subId, _ in ipairs(widget.subCategories) do
                local subWidget = widget:getChildById(subId)
                if subWidget then
                    subWidget.Button:setChecked(false)
                    subWidget.Button.Arrow:setVisible(false)
                end
            end
        end
    end
end

function createCategory(text, icon, openPanel, subCategories)
    local newCategory = {
        text = text,
        icon = icon,
        open = type(openPanel) == "string" and openPanel or getPanelName(openPanel),
        subCategories = subCategories
    }
    table.insert(buttons, newCategory)
    if type(openPanel) ~= "string" then
        panels[getPanelName(openPanel)] = openPanel
    end
    configureCharacterCategories()
end

function removeCategory(categoryText, subcategoryText)
    for i, category in ipairs(buttons) do
        if category.text == categoryText then
            if subcategoryText then
                if category.subCategories then
                    for j, subcategory in ipairs(category.subCategories) do
                        if subcategory.text == subcategoryText then
                            panels[subcategory.open] = nil
                            table.remove(category.subCategories, j)
                            break
                        end
                    end
                end
            else
                panels[category.open] = nil
                if category.subCategories then
                    for _, subcategory in ipairs(category.subCategories) do
                        panels[subcategory.open] = nil
                    end
                end
                table.remove(buttons, i)
            end
            configureCharacterCategories()
            return
        end
    end
end

function removeButton(categoryText, buttonText)
    for _, category in ipairs(buttons) do
        if category.text == categoryText then
            if category.subCategories then
                for i, subcategory in ipairs(category.subCategories) do
                    if subcategory.text == buttonText then
                        panels[subcategory.open] = nil
                        table.remove(category.subCategories, i)
                        configureCharacterCategories()
                        return
                    end
                end
            end
        end
    end
end

function addButton(categoryText, buttonText, openPanel, callback)
    for _, category in ipairs(buttons) do
        if category.text == categoryText then
            if not category.subCategories then
                category.subCategories = {}
            end
            local panelName = type(openPanel) == "string" and openPanel or getPanelName(openPanel)
            table.insert(category.subCategories, {
                text = buttonText,
                open = panelName,
                callbackFunc = callback
            })
            if type(openPanel) ~= "string" then
                panels[panelName] = openPanel
            end
            configureCharacterCategories()
            return
        end
    end
end

function getPanelName(panel)
    for name, p in pairs(panels) do
        if p == panel then
            return name
        end
    end
    return "panel_" .. tostring(panel):match("userdata: 0x(%x+)")
end

function addSubcategoryToCategory(categoryText, newSubcategory)
    addButtonToCategory(categoryText, newSubcategory)
end

function getPanel()
    return controller.ui.optionsTabContent
end

function openOptionsCategory(category, subcategory)
    if not controller.ui:isVisible() then
        show()
    end
    for i = 1, controller.ui.optionsTabBar:getChildCount() do
        local widget = controller.ui.optionsTabBar:getChildByIndex(i)
        if widget and widget.Button.Title:getText() == category then
            widget.Button:onClick()
            if subcategory and widget.subCategories then
                for subId, _ in ipairs(widget.subCategories) do
                    local subWidget = widget:getChildById(subId)
                    if subWidget and subWidget.Button.Title:getText() == subcategory then
                        subWidget.Button:onClick()
                        return true
                    end
                end
            end
            return true
        end
    end
    return false
end
