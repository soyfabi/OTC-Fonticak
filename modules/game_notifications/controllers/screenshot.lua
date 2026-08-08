-- LuaFormatter off
local ScreenshotType = {
    NONE = 0,
    ACHIEVEMENT = 1,
    BESTIARY_ENTRY_COMPLETED = 2,
    BESTIARY_ENTRY_UNLOCKED = 3,
    BOSS_DEFEATED = 4,
    DEATH_PVE = 5,
    DEATH_PVP = 6,
    LEVEL_UP = 7,
    PLAYER_KILL_ASSIST = 8,
    PLAYER_KILL = 9,
    PLAYER_ATTACKING = 10,
    TREASURE_FOUND = 11,
    SKILL_UP = 12,
    HIGHEST_DAMAGE_DEALT = 13,
    HIGHEST_HEALING_DONE = 14,
    LOW_HEALTH = 15,
    GIFT_OF_LIFE_TRIGGERED = 16,
    VALUABLE_LOOT = 17
}

local AutoScreenshotEvents = {
    {id = ScreenshotType.LEVEL_UP, label = "Level Up", enableDefault = true},
    {id = ScreenshotType.SKILL_UP, label = "Skill Up", enableDefault = true},
    {id = ScreenshotType.ACHIEVEMENT, label = "Achievement", enableDefault = true},
    {id = ScreenshotType.BESTIARY_ENTRY_UNLOCKED, label = "Bestiary Entry Unlocked", enableDefault = false},
    {id = ScreenshotType.BESTIARY_ENTRY_COMPLETED, label = "Bestiary Entry Completed", enableDefault = false},
    {id = ScreenshotType.TREASURE_FOUND, label = "Treasure Found", enableDefault = false},
    {id = ScreenshotType.VALUABLE_LOOT, label = "Valuable Loot", enableDefault = false},
    {id = ScreenshotType.BOSS_DEFEATED, label = "Boss Defeated", enableDefault = false},
    {id = ScreenshotType.DEATH_PVE, label = "Death PvE", enableDefault = true},
    {id = ScreenshotType.DEATH_PVP, label = "Death PvP", enableDefault = false},
    {id = ScreenshotType.PLAYER_KILL, label = "Player Kill", enableDefault = false},
    {id = ScreenshotType.PLAYER_KILL_ASSIST, label = "Player Kill Assist", enableDefault = false},
    {id = ScreenshotType.PLAYER_ATTACKING, label = "Player Attacking", enableDefault = false},
    {id = ScreenshotType.HIGHEST_DAMAGE_DEALT, label = "Highest Damage Dealt", enableDefault = false},
    {id = ScreenshotType.HIGHEST_HEALING_DONE, label = "Highest Healing Done", enableDefault = false},
    {id = ScreenshotType.LOW_HEALTH, label = "Low Health", enableDefault = false},
    {id = ScreenshotType.GIFT_OF_LIFE_TRIGGERED, label = "Gift of Life Triggered", enableDefault = true}
}
-- LuaFormatter on

local optionPanel = nil
local screenshotStyleLoaded = false
local screenshotEventsBound = false
local screenshotEventsPopulated = false
local screenshotHotkeyDefined = false
local screenshotHotkeyBound = false
local autoScreenshotDirName = "auto_screenshots"
local autoScreenshotDir = g_resources.getWriteDir() .. "/" .. autoScreenshotDirName
local SCREENSHOT_HOTKEY_CATEGORY = "Misc."
local SCREENSHOT_HOTKEY_ACTION = "Take Screenshot"
local SCREENSHOT_HOTKEY_PRIMARY = "Ctrl+PrintScreen"

local function settingKeyForEvent(screenshotEvent)
    return screenshotEvent.label:gsub("%s+", "")
end

local function readBoolSetting(key, default)
    local value = g_settings.get(key)
    if value == nil then
        return default and true or false
    end
    return g_settings.getBoolean(key)
end

local function loadEventSettings()
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        screenshotEvent.currentBoolean = readBoolSetting(settingKeyForEvent(screenshotEvent), screenshotEvent.enableDefault)
    end
end

local function saveEventSettings()
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        g_settings.set(settingKeyForEvent(screenshotEvent), screenshotEvent.currentBoolean and true or false)
    end
end

local function saveMainSettings()
    if not optionPanel or optionPanel:isDestroyed() then
        return
    end

    local onlyCapture = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
    if onlyCapture then
        g_settings.set("onlyCaptureGameWindow", onlyCapture:isChecked())
    end

    local enable = optionPanel:recursiveGetChildById("enableScreenshots")
    if enable then
        g_settings.set("enableScreenshots", enable:isChecked())
    end
end

function saveScreenshotMainOptions()
    saveMainSettings()
end

function updateScreenshotEventsEnabledState()
    if not optionPanel or optionPanel:isDestroyed() then
        return
    end

    local enable = optionPanel:recursiveGetChildById("enableScreenshots")
    local enabled = enable and enable:isChecked() or false
    local activeColor = '#c0c0c0ff'
    local disabledColor = '#666666ff'

    local eventsLabel = optionPanel:recursiveGetChildById("eventsLabel")
    if eventsLabel then
        eventsLabel:setColor(enabled and activeColor or disabledColor)
    end

    local list = optionPanel.allCheckBox
    if not list then
        return
    end

    for _, row in pairs(list:getChildren()) do
        row:setEnabled(enabled)
        local checkBox = row:getChildById('enabled')
        if checkBox then
            checkBox:setEnabled(enabled)
        end
        local text = row:getChildById('text')
        if text then
            text:setEnabled(enabled)
            text:setColor(enabled and activeColor or disabledColor)
        end
    end
end

local function applyMainSettingsToPanel()
    if not optionPanel or optionPanel:isDestroyed() then
        return
    end

    local onlyCapture = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
    if onlyCapture then
        onlyCapture:setChecked(readBoolSetting("onlyCaptureGameWindow", false))
    end

    local enable = optionPanel:recursiveGetChildById("enableScreenshots")
    if enable then
        enable:setChecked(readBoolSetting("enableScreenshots", false))
    end

    local keepBacklog = optionPanel:recursiveGetChildById("keepBlacklog")
    if keepBacklog then
        keepBacklog:setEnabled(false)
        keepBacklog:setChecked(false)
        keepBacklog:setColor('#666666ff')
        if keepBacklog.setOpacity then
            keepBacklog:setOpacity(0.75)
        end
    end

    updateScreenshotEventsEnabledState()
end

local function populateEventCheckboxes()
    if not optionPanel or optionPanel:isDestroyed() or screenshotEventsPopulated then
        return
    end

    local list = optionPanel.allCheckBox
    if not list then
        return
    end

    list:destroyChildren()
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        local label = g_ui.createWidget("ScreenshotType", list)
        label.text:setText(screenshotEvent.label)
        label.enabled:setChecked(screenshotEvent.currentBoolean and true or false)
        label.enabled.eventId = screenshotEvent.id
    end
    screenshotEventsPopulated = true
    updateScreenshotEventsEnabledState()
end

local function ensureScreenshotDir()
    if not g_resources.directoryExists(autoScreenshotDir) then
        g_resources.makeDir(autoScreenshotDirName)
    end
end

local function unbindScreenshotHotkey()
    if screenshotHotkeyBound then
        pcall(function()
            Keybind.unbind(SCREENSHOT_HOTKEY_CATEGORY, SCREENSHOT_HOTKEY_ACTION)
        end)
        screenshotHotkeyBound = false
    end
end

local function bindScreenshotHotkey()
    if not screenshotHotkeyDefined then
        local ok = pcall(function()
            Keybind.new(SCREENSHOT_HOTKEY_CATEGORY, SCREENSHOT_HOTKEY_ACTION, SCREENSHOT_HOTKEY_PRIMARY, "")
        end)
        screenshotHotkeyDefined = ok and true or screenshotHotkeyDefined
        if not ok then
            -- May already exist from a previous bind attempt in this session.
            screenshotHotkeyDefined = true
        end
    end

    if screenshotHotkeyBound then
        return
    end

    local rootPanel = nil
    if modules.game_interface and modules.game_interface.getRootPanel then
        rootPanel = modules.game_interface.getRootPanel()
    end

    local ok = pcall(function()
        Keybind.bind(SCREENSHOT_HOTKEY_CATEGORY, SCREENSHOT_HOTKEY_ACTION, {
            {
                type = KEY_DOWN,
                callback = takeManualScreenshot
            }
        }, rootPanel)
    end)
    screenshotHotkeyBound = ok and true or false
end

function takeManualScreenshot()
    if not g_game.isOnline() then
        if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
            modules.game_textmessage.displayStatusMessage(tr('You need to be in-game to take a screenshot.'))
        end
        return
    end

    ensureScreenshotDir()

    local player = g_game.getLocalPlayer()
    local name = (player and player:getName()) or "player"
    local level = (player and player:getLevel()) or 1
    local screenshotName = name .. level .. "_Manual_" .. os.date("%Y%m%d%H%M%S") .. ".png"
    takeScreenshot("/" .. autoScreenshotDirName .. "/" .. screenshotName)
end

function ensureScreenshotOptionsPanel()
    if optionPanel and not optionPanel:isDestroyed() then
        if modules.client_options and modules.client_options.panels then
            modules.client_options.panels.miscScreenshot = optionPanel
        end
        return optionPanel
    end

    if not modules.client_options or not modules.client_options.getPanel then
        return nil
    end

    if not screenshotStyleLoaded then
        local okStyle, styleErr = pcall(function()
            g_ui.importStyle('/modules/client_options/styles/misc/screenshot_type')
        end)
        if not okStyle then
            g_logger.error('[screenshots] Failed to import ScreenshotType style: ' .. tostring(styleErr))
            return nil
        end
        screenshotStyleLoaded = true
    end

    local okPanel, panelOrErr = pcall(function()
        return g_ui.loadUI('/modules/client_options/styles/misc/screenshot', modules.client_options.getPanel())
    end)
    if not okPanel or not panelOrErr then
        g_logger.error('[screenshots] Failed to load Screenshots panel: ' .. tostring(panelOrErr))
        return nil
    end

    optionPanel = panelOrErr
    optionPanel:hide()
    optionPanel:setVisible(false)

    if modules.client_options.panels then
        modules.client_options.panels.miscScreenshot = optionPanel
    end

    loadEventSettings()
    applyMainSettingsToPanel()
    populateEventCheckboxes()
    return optionPanel
end

function screenshot_onTerminate()
    saveMainSettings()
    saveEventSettings()
    unbindScreenshotHotkey()
    if screenshotHotkeyDefined then
        pcall(function()
            Keybind.delete(SCREENSHOT_HOTKEY_CATEGORY, SCREENSHOT_HOTKEY_ACTION)
        end)
        screenshotHotkeyDefined = false
    end

    if optionPanel and not optionPanel:isDestroyed() then
        optionPanel:destroy()
    end
    optionPanel = nil
    screenshotEventsPopulated = false
    screenshotEventsBound = false

    if modules.client_options and modules.client_options.panels then
        modules.client_options.panels.miscScreenshot = nil
    end
end

function screenshot_onGameStart()
    loadEventSettings()
    ensureScreenshotDir()
    bindScreenshotHotkey()

    if g_game.getClientVersion() < 1180 then
        return
    end

    if not screenshotEventsBound then
        notificationsController:registerEvents(LocalPlayer, {
            onTakeScreenshot = onScreenShot
        })
        screenshotEventsBound = true
    end

    -- If the Options panel was already opened this session, refresh widgets.
    if optionPanel and not optionPanel:isDestroyed() then
        applyMainSettingsToPanel()
        if not screenshotEventsPopulated then
            populateEventCheckboxes()
        end
    end
end

function screenshot_onGameEnd()
    saveMainSettings()
    saveEventSettings()
    unbindScreenshotHotkey()
end

function onUICheckBox(widget, checked)
    if not widget or not widget.eventId then
        return
    end

    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        if screenshotEvent.id == widget.eventId then
            screenshotEvent.currentBoolean = checked and true or false
            g_settings.set(settingKeyForEvent(screenshotEvent), screenshotEvent.currentBoolean)
            break
        end
    end
end

function resetValues()
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        screenshotEvent.currentBoolean = screenshotEvent.enableDefault and true or false
        g_settings.set(settingKeyForEvent(screenshotEvent), screenshotEvent.currentBoolean)
    end

    if not optionPanel or optionPanel:isDestroyed() then
        return
    end

    local enable = optionPanel:recursiveGetChildById("enableScreenshots")
    if enable then
        enable:setChecked(false)
        g_settings.set("enableScreenshots", false)
    end

    local onlyCapture = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
    if onlyCapture then
        onlyCapture:setChecked(false)
        g_settings.set("onlyCaptureGameWindow", false)
    end

    for _, selectedCheckBox in pairs(optionPanel.allCheckBox:getChildren()) do
        local checkBox = selectedCheckBox:getChildById('enabled')
        if checkBox and checkBox.eventId then
            for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
                if screenshotEvent.id == checkBox.eventId then
                    checkBox:setChecked(screenshotEvent.enableDefault and true or false)
                    break
                end
            end
        end
    end

    updateScreenshotEventsEnabledState()
end

function onScreenShot(typeOrPlayer, maybeType)
    -- LocalPlayer signal may arrive as (player, type) or just (type).
    local screenshotType = maybeType
    if screenshotType == nil then
        screenshotType = typeOrPlayer
    end
    if type(screenshotType) ~= 'number' then
        return
    end

    local enabled = readBoolSetting("enableScreenshots", false)
    if optionPanel and not optionPanel:isDestroyed() then
        local enableWidget = optionPanel:recursiveGetChildById("enableScreenshots")
        if enableWidget then
            enabled = enableWidget:isChecked()
        end
    end
    if not enabled then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local name = player:getName() or "player"
    local level = player:getLevel() or 1
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        if screenshotEvent.id == screenshotType and screenshotEvent.currentBoolean then
            local screenshotName = name .. level .. "_" .. screenshotEvent.label:gsub("%s+", "") .. "_" ..
                                       os.date("%Y%m%d%H%M%S") .. ".png"
            takeScreenshot("/" .. autoScreenshotDirName .. "/" .. screenshotName)
            return
        end
    end
end

function takeScreenshot(name)
    if not g_game.isOnline() then
        return
    end
    if not name:lower():match("%.png$") then
        name = name .. ".png"
    end

    notificationsController:scheduleEvent(function()
        local onlyGameWindow = readBoolSetting("onlyCaptureGameWindow", false)
        if optionPanel and not optionPanel:isDestroyed() then
            local onlyCapture = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
            if onlyCapture then
                onlyGameWindow = onlyCapture:isChecked()
            end
        end

        if onlyGameWindow then
            g_app.doMapScreenshot(name)
        else
            g_app.doScreenshot(name)
        end
    end, 50, 'screenshotScheduleEvent')

    local directory = g_resources.getWriteDir():gsub("[/\\]+", "\\") .. autoScreenshotDirName
    local message = string.format("Screenshot has been saved to '%s'.", directory)
    local console = modules.game_console
    if console and console.addText then
        console.addText(message, console.SpeakTypesSettings, tr("Server Log"))
    end
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
        modules.game_textmessage.displayStatusMessage(message)
    end
end

function OpenFolder()
    ensureScreenshotDir()
    local directory = g_resources.getWriteDir():gsub("[/\\]+", "\\") .. autoScreenshotDirName
    g_platform.openDir(directory)
end
