botWindow = nil
botButton = nil
contentsPanel = nil
editWindow = nil

local checkEvent = nil
local loginRefreshEvent = nil
local relogRecoveryEvent = nil
local botWatchEvent = nil
local botLoadGeneration = 0
local defaultsSynced = false

local botStorage = {}
local botStorageFile = nil
local botWebSockets = {}
local botMessages = nil
local botTabs = nil
local botExecutor = nil

local configList = nil
local enableButton = nil
local executeEvent = nil
local statusLabel = nil

function getBotLoadGeneration()
  return botLoadGeneration
end

local updateBotTabsHeight = nil

local function isCurrentBotEnabled()
  if not g_game.isOnline() then
    return false
  end

  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  return settings[index] and settings[index].enabled
end

local function isBotPanelEmpty()
  return botTabs and botTabs.tabs and #botTabs.tabs == 0
end

local function watchBotState()
  if not g_game.isOnline() then
    return
  end

  if isCurrentBotEnabled() and isBotPanelEmpty() then
    refresh()
  end
end

function init()
  dofile("executor")

  g_ui.importStyle("ui/basic.otui")
  g_ui.importStyle("ui/panels.otui")
  g_ui.importStyle("ui/config.otui")
  g_ui.importStyle("ui/icons.otui")
  g_ui.importStyle("ui/container.otui")

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  initCallbacks()

  botButton = modules.game_mainpanel.addToggleButton('botButton', tr('Bot'), '/images/options/bot', toggle, false, 99999)
  botButton:setOn(false)
  botButton:show()

  botWindow = g_ui.loadUI('bot', modules.game_interface.getLeftPanel())
  botWindow:setup()

  -- Hide unwanted miniwindow buttons
  local toggleFilterButton = botWindow:recursiveGetChildById('toggleFilterButton')
  if toggleFilterButton then
    toggleFilterButton:setVisible(false)
  end
  
  local contextMenuButton = botWindow:recursiveGetChildById('contextMenuButton')
  if contextMenuButton then
    contextMenuButton:setVisible(false)
  end
  
  local newWindowButton = botWindow:recursiveGetChildById('newWindowButton')
  if newWindowButton then
    newWindowButton:setVisible(false)
  end

  -- Position lockButton where toggleFilterButton would be (to the left of minimize button)
  local lockButton = botWindow:recursiveGetChildById('lockButton')
  local minimizeButton = botWindow:recursiveGetChildById('minimizeButton')
  
  if lockButton and minimizeButton then
    lockButton:setVisible(true)
    lockButton:breakAnchors()
    lockButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
    lockButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
    lockButton:setMarginRight(7)  -- Same margin as toggleFilterButton would have
    lockButton:setMarginTop(0)
    lockButton:setSize({width = 12, height = 12})
  end

  contentsPanel = botWindow.contentsPanel
  configList = contentsPanel.config
  enableButton = contentsPanel.enableButton
  statusLabel = contentsPanel.statusLabel
  botMessages = contentsPanel.messages
  botTabs = contentsPanel.botTabs
  botTabs:setContentWidget(contentsPanel.botPanel)

  -- Keep header/tabs full-width; scrolling happens in BotPanel below the tabs
  local function disableBotMiniwindowScroll()
    local miniScroll = botWindow:getChildById('miniwindowScrollBar')
    if miniScroll then
      miniScroll:setVisible(false)
      miniScroll:setWidth(0)
      if miniScroll.setOn then
        miniScroll:setOn(false)
      end
    end
    contentsPanel.verticalScrollBar = nil
    if contentsPanel.breakAnchors and contentsPanel.addAnchor then
      contentsPanel:breakAnchors()
      contentsPanel:addAnchor(AnchorTop, 'miniwindowHeader', AnchorBottom)
      contentsPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      contentsPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
      contentsPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      contentsPanel:setMarginLeft(3)
      contentsPanel:setMarginRight(3)
      contentsPanel:setMarginTop(2)
      contentsPanel:setMarginBottom(3)
    end
  end
  disableBotMiniwindowScroll()
  scheduleEvent(disableBotMiniwindowScroll, 50)
  scheduleEvent(disableBotMiniwindowScroll, 300)

  botTabs.onGeometryChange = function(widget, oldRect, newRect)
    updateBotTabsHeight()
    if widget.fitTabs then
      widget.fitTabs()
    end
  end

  editWindow = g_ui.displayUI('edit')
  editWindow:hide()

  loadConfigsList()
  botWatchEvent = cycleEvent(watchBotState, 500)

  if g_game.isOnline() then
    clear()
    online()
  end
end

function terminate()
  save()
  clear()
  removeEvent(relogRecoveryEvent)
  relogRecoveryEvent = nil
  removeEvent(botWatchEvent)
  botWatchEvent = nil

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  terminateCallbacks()
  editWindow:destroy()

  botWindow:destroy()
  botButton:destroy()
end

function clear()
  botLoadGeneration = botLoadGeneration + 1
  botExecutor = nil
  removeEvent(checkEvent)

  -- optimization, callback is not used when not needed
  g_game.enableTileThingLuaCallback(false)

  botTabs:clearTabs()
  botTabs:setOn(false)
  botTabs:setHeight(0)

  botMessages:destroyChildren()
  botMessages:updateLayout()

  for i, socket in pairs(botWebSockets) do
    HTTP.cancel(i)
    botWebSockets[i] = nil
  end

  for i, widget in pairs(g_ui.getRootWidget():getChildren()) do
    if widget.botWidget then
      widget:destroy()
    end
  end
  for i, widget in pairs(modules.game_interface.gameMapPanel:getChildren()) do
    if widget.botWidget then
      widget:destroy()
    end
  end
  for _, widget in pairs({modules.game_interface.getRightPanel(), modules.game_interface.getLeftPanel()}) do
    for i, child in pairs(widget:getChildren()) do
      if child.botWidget then
        child:destroy()
      end
    end
  end

  local gameMapPanel = modules.game_interface.getMapPanel()
  if gameMapPanel then
    gameMapPanel:unlockVisibleFloor()
  end

  if g_sounds then
    g_sounds.getChannel(SoundChannels.Bot):stop()
  end
end

local function cancelLoginRefresh()
  removeEvent(loginRefreshEvent)
  loginRefreshEvent = nil
end

local function scheduleLoginRefresh()
  cancelLoginRefresh()

  local attempts = 0
  local function tryRefresh()
    if not g_game.isOnline() then
      loginRefreshEvent = nil
      return
    end

    attempts = attempts + 1
    refresh()

    if botExecutor or attempts >= 8 then
      loginRefreshEvent = nil
      return
    end

    loginRefreshEvent = scheduleEvent(tryRefresh, 250)
  end

  loginRefreshEvent = scheduleEvent(tryRefresh, 250)
end

function updateBotTabsHeight()
  if not botTabs:isOn() then
    if botTabs:getHeight() ~= 0 then
      botTabs:setHeight(0)
    end
  else
    if botTabs:getHeight() ~= 20 then
      botTabs:setHeight(20)
    end
  end
end

function loadConfigsList()
  if not g_resources.directoryExists("/bot") then
    g_resources.makeDir("/bot")
    if not g_resources.directoryExists("/bot") then return end
  end
  createDefaultConfigs()
  local configs = g_resources.listDirectoryFiles("/bot", false, false)
  configList.onOptionChange = nil
  configList:clearOptions()
  for i=1,#configs do
    configList:addOption(configs[i])
  end
  local settings = g_settings.getNode('bot') or {}
  if g_game.isOnline() then
    local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
    local saved = settings[index]
    if saved then
      configList:setCurrentOption(saved.config)
    end
  end

  enableButton.onClick = function(widget)
    if g_game.isOnline() then
      refresh()
    else
      statusLabel:setOn(true)
      statusLabel:setText("Status: login to enable bot")
    end
  end
  configList.onOptionChange = function(widget)
    if g_game.isOnline() then refresh() end
  end
end

function refresh()
  if not g_game.isOnline() then return end
  save()
  clear()

  loadConfigsList()
  if not configList.options or #configList.options == 0 then
    statusLabel:setOn(true)
    statusLabel:setText("No configs found in " .. g_resources.getWriteDir() .. "bot/")
    return
  end

  -- select active config based on settings
  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  if settings[index] == nil then
    settings[index] = {
      enabled=false,
      config=""
    }
  end

  configList:setCurrentOption(settings[index].config)
  local currentOpt = configList:getCurrentOption()
  if currentOpt and currentOpt.text ~= settings[index].config then
    settings[index].config = currentOpt.text
    settings[index].enabled = false
  end

  enableButton:setOn(settings[index].enabled)

  configList.onOptionChange = function(widget)
    settings[index].config = widget:getCurrentOption().text
    g_settings.setNode('bot', settings)
    g_settings.save()
    refresh()
  end

  enableButton.onClick = function(widget)
    settings[index].enabled = not settings[index].enabled
    g_settings.setNode('bot', settings)
    g_settings.save()
    refresh()
  end

  if not g_game.isOnline() or not settings[index].enabled then
    statusLabel:setOn(true)
    statusLabel:setText("Status: disabled\nPress off button to enable")
    analyzerButton = modules.game_mainpanel.getButton("botAnalyzersButton")
    if analyzerButton then
      analyzerButton:destroy()
    end
    return
  end

  local configName = settings[index].config
  local loadGen = botLoadGeneration

  -- storage
  botStorage = {}

  local path = "/bot/" .. configName .. "/storage/"
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end

  botStorageFile = path.."profile_" .. g_settings.getNumber('profile') .. ".json"
  if g_resources.fileExists(botStorageFile) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(botStorageFile))
    end)
    if not status then
      return onError("Error while reading storage (" .. botStorageFile .. "). To fix this problem you can delete storage.json. Details: " .. result)
    end
    botStorage = result
  end

  statusLabel:setOn(true)
  statusLabel:setText("Status: loading " .. configName .. "...")

  local function onLoadProgress(done, total)
    if loadGen ~= botLoadGeneration then
      return
    end
    statusLabel:setOn(true)
    statusLabel:setText(string.format("Status: loading %s (%d/%d)", configName, done, total))
  end

  local function onLoadComplete()
    if loadGen ~= botLoadGeneration then
      return
    end
    updateBotTabsHeight()
    statusLabel:setOn(false)
    check()
  end

  -- run script (heavy configs finish asynchronously across frames)
  local status, result = pcall(function()
    return executeBot(configName, botStorage, botTabs, message, save, refresh, botWebSockets, onLoadComplete, onLoadProgress)
  end)
  if not status then
    return onError(result)
  end

  botExecutor = result
end

function save()
  if not botExecutor then
    return
  end

  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  if settings[index] == nil then
    return
  end

  local status, result = pcall(function()
    return json.encode(botStorage, 2)
  end)
  if not status then
    return onError("Error while saving bot storage. Storage won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return onError("Storage file is too big, above 100MB, it won't be saved")
  end

  g_resources.writeFileContents(botStorageFile, result)
end

function onMiniWindowClose()
  botButton:setOn(false)
end

function toggle()
  if botButton:isOn() then
    botWindow:close()
    botButton:setOn(false)
  else
    botWindow:open()
    botButton:setOn(true)

    modules.game_interface.checkAndOpenLeftPanel()
  end
end

function online()
  botWindow:setupOnStart()
  -- A character switch can emit onGameStart before the previous onGameEnd.
  -- Cancel its pending recovery; this login gets a fresh normal load attempt.
  removeEvent(relogRecoveryEvent)
  relogRecoveryEvent = nil
  scheduleLoginRefresh()
end

function offline()
  cancelLoginRefresh()
  save()
  clear()
  editWindow:hide()

  -- Some servers complete the next character login before this old-session
  -- onGameEnd callback finishes. In that order, clear() above removes the new
  -- bot UI and cancelLoginRefresh() cancels its loader. Recheck shortly after
  -- the event chain settles and restart only if a new session is already live.
  removeEvent(relogRecoveryEvent)
  relogRecoveryEvent = scheduleEvent(function()
    relogRecoveryEvent = nil
    if g_game.isOnline() then
      scheduleLoginRefresh()
    end
  end, 500)
end

function onError(message)
  statusLabel:setOn(true)
  statusLabel:setText("Error:\n" .. message)
  g_logger.error("[BOT] " .. message)
end

function edit()
  local configs = g_resources.listDirectoryFiles("/bot", false, false)
  editWindow.manager.upload.config:clearOptions()
  for i=1,#configs do
    editWindow.manager.upload.config:addOption(configs[i])
  end
  editWindow.manager.download.config:setText("")
  editWindow.manager.upload.submit:setEnabled(#configs > 0)

  local reloadHint = editWindow.reloadHint or (editWindow.infoPanel and editWindow.infoPanel.reloadHint)
  if reloadHint and reloadHint.setColoredText then
    reloadHint:setColoredText("To reload a config, turn the bot {Off, #FF3333} and {On, #33CC33} again.")
  end

  editWindow:show()
  editWindow:focus()
  editWindow:raise()
end

local function copyFilesRecursively(sourcePath, targetPath, overwriteExisting)
    local files = g_resources.listDirectoryFiles(sourcePath, true, false, false)
    for _, file in ipairs(files) do
        local baseName = file:split("/")
        baseName = baseName[#baseName]
        local targetFilePath = targetPath .. "/" .. baseName

        -- Never touch user runtime data, even on first install of a missing file
        -- after the config folder already exists. On brand-new install, overwriteExisting
        -- is true and these folders are copied once as templates (if present).
        local protected = targetFilePath:find("/storage/")
            or targetFilePath:find("/vBot_configs/")
            or targetFilePath:find("/cavebot_configs/")
            or targetFilePath:find("/targetbot_configs/")

        if g_resources.directoryExists(file) then
            g_resources.makeDir(targetFilePath)
            if not g_resources.directoryExists(targetFilePath) then
                return onError("Can't create directory: " .. targetFilePath)
            end
            copyFilesRecursively(file, targetFilePath, overwriteExisting)
        else
            local exists = g_resources.fileExists(targetFilePath)
            if exists and (protected or not overwriteExisting) then
                -- keep user's file
            else
                local cleanFile = file
                if file:sub(1, 1) == "/" then
                    cleanFile = file:sub(2)
                end
                local ok, contents = pcall(function() return g_resources.readFileContents(file) end)
                if (not ok or not contents or contents:len() == 0) and cleanFile ~= file then
                    ok, contents = pcall(function() return g_resources.readFileContents(cleanFile) end)
                end
                if ok and contents and contents:len() > 0 then
                    g_resources.writeFileContents(targetFilePath, contents)
                end
            end
        end
    end
end

function createDefaultConfigs()
    -- Avoid re-walking the whole tree on every login/config switch (was a big hitch).
    if defaultsSynced then
        return
    end

    -- Public configs shipped with the client. Private packs live in private_configs/ and are not copied.
    local publicConfigs = { "FontiBot-1.0", "vBot_4.8" }
    local available = {}
    for _, name in ipairs(g_resources.listDirectoryFiles("default_configs", false, false)) do
        available[name] = true
    end
    for _, configName in ipairs(publicConfigs) do
        if available[configName] then
            local targetDir = "/bot/" .. configName
            if not g_resources.directoryExists(targetDir) then
                g_resources.makeDir(targetDir)
                if not g_resources.directoryExists(targetDir) then
                    return onError("Can't create directory: " .. targetDir)
                end
                -- Brand new config: install package files once
                copyFilesRecursively("default_configs/" .. configName, targetDir, true)
            else
                -- Existing config: only add missing script files, NEVER overwrite user edits/storage
                copyFilesRecursively("default_configs/" .. configName, targetDir, false)
            end
        end
    end
    defaultsSynced = true
end

local function setConfigTransferEnabled(enabled)
  if editWindow and editWindow.manager then
    editWindow.manager.upload.submit:setEnabled(enabled and editWindow.manager.upload.config:getCurrentOption() ~= nil)
    editWindow.manager.download.submit:setEnabled(enabled)
  end
end

function uploadConfig()
  local option = editWindow.manager.upload.config:getCurrentOption()
  local config = option and option.text
  if not config or config == "" then
    return displayErrorBox(tr("Config upload failed"), tr("No config selected."))
  end

  local archive = compressConfig(config)
  if not archive or archive:len() == 0 then
      return displayErrorBox(tr("Config upload failed"), tr("Config %s is invalid (can't be compressed)", config))
  end
  if archive:len() > ConfigShare.maxBytes then
      return displayErrorBox(tr("Config upload failed"), tr("Config %s is too big, maximum size is 1024KB. Now it has %s KB.", config, math.floor(archive:len() / 1024)))
  end

  local infoBox = displayInfoBox(tr("Uploading config"), tr("Uploading config %s. Please wait.", config))
  setConfigTransferEnabled(false)
  local operation, startError = ConfigShare.upload("bot", config, archive, function(data, err)
    setConfigTransferEnabled(true)
    if infoBox then
      infoBox:destroy()
    end
    local hash, responseError, response = ConfigShare.parseUploadResponse(data, err)
    if not hash then
      return displayErrorBox(tr("Config upload failed"), tr("Error while uploading config %s:\n%s", config, responseError))
    end
    g_window.setClipboardText(hash)
    editWindow.manager.download.config:setText(hash)
    local message = response.message or ("Config hash: " .. hash)
    displayInfoBox(tr("Successful config upload"), tr("Config %s has been uploaded.\n\n%s\n\nHash copied to clipboard. Paste it with Ctrl+V to share.", config, message))
  end)
  if not operation then
    setConfigTransferEnabled(true)
    infoBox:destroy()
    displayErrorBox(tr("Config upload failed"), startError)
  end
end

function downloadConfig()
  local hash = ConfigShare.normalizeHash(editWindow.manager.download.config:getText())
  if not hash then
    return displayErrorBox(tr("Config download error"), tr("Enter a valid 12-character config hash."))
  end

  local infoBox = displayInfoBox(tr("Downloading config"), tr("Downloading config with hash %s. Please wait.", hash))
  setConfigTransferEnabled(false)
  local operation, startError = ConfigShare.download("bot", hash, "zip", function(path, checksum, err)
    setConfigTransferEnabled(true)
    if infoBox then
      infoBox:destroy()
    end
    if err then
      return displayErrorBox(tr("Config download error"), tr("Config with hash %s cannot be downloaded:\n%s", hash, err))
    end

    local filePath = "/downloads/" .. path
    local ok, archive = pcall(function() return g_resources.readFileContents(filePath) end)
    if not ok or type(archive) ~= "string" or archive:sub(1, 2) ~= "PK" then
      return displayErrorBox(tr("Config download error"), tr("This hash is not a valid bot config."))
    end
    local files = g_resources.decompressArchive(archive)
    if type(files) ~= "table" or not next(files) then
      return displayErrorBox(tr("Config download error"), tr("The downloaded bot config is empty or corrupt."))
    end

    modules.client_textedit.show("", {
      title="Enter name for downloaded config",
      description="Config with hash " .. hash .. " is ready. Enter a name for the new config.\nAn existing config with the same name will be replaced.",
      width=500
    }, function(configName)
      local imported, importError = decompressConfig(configName, files)
      if not imported then
        return displayErrorBox(tr("Config download error"), importError)
      end
      refresh()
      edit()
    end)
  end)
  if not operation then
    setConfigTransferEnabled(true)
    infoBox:destroy()
    displayErrorBox(tr("Config download error"), startError)
  end
end

local protectedUploadDirs = {
  storage = true,
}

local function collectConfigFiles(rootPath, excludeRuntime)
  local files = {}
  local function visit(path, relativePath)
    for _, entry in ipairs(g_resources.listDirectoryFiles(path, false, false, false) or {}) do
      local fullPath = path .. "/" .. entry
      local relative = relativePath == "" and entry or (relativePath .. "/" .. entry)
      local rootDir = relative:match("^([^/]+)")
      if not (excludeRuntime and protectedUploadDirs[rootDir]) then
        if g_resources.directoryExists(fullPath) then
          visit(fullPath, relative)
        elseif g_resources.fileExists(fullPath) then
          files[relative] = g_resources.readFileContents(fullPath)
        end
      end
    end
  end
  visit(rootPath, "")
  return files
end

local function removeDirectoryTree(path)
  if not g_resources.directoryExists(path) then
    return true
  end
  for _, entry in ipairs(g_resources.listDirectoryFiles(path, false, false, false) or {}) do
    local fullPath = path .. "/" .. entry
    if g_resources.directoryExists(fullPath) then
      if not removeDirectoryTree(fullPath) then
        return false
      end
    elseif not g_resources.deleteFile(fullPath) then
      return false
    end
  end
  return g_resources.deleteFile(path)
end

local function writeConfigFiles(configName, files)
  local rootPath = "/bot/" .. configName
  if not g_resources.directoryExists(rootPath) then
    g_resources.makeDir(rootPath)
  end
  if not g_resources.directoryExists(rootPath) then
    return false, "Can't create " .. rootPath .. " in " .. g_resources.getWriteDir()
  end

  for file, contents in pairs(files) do
    local relative = tostring(file):gsub("\\", "/"):gsub("^/+", "")
    if relative == "" or relative:find(":", 1, true) then
      return false, "Archive contains an invalid file path."
    end
    local segments = relative:split("/")
    local fileName = table.remove(segments)
    if not fileName or fileName == "" or fileName == "." or fileName == ".." then
      return false, "Archive contains an invalid file name."
    end
    local dirPath = rootPath
    for _, segment in ipairs(segments) do
      if segment == "" or segment == "." or segment == ".." then
        return false, "Archive contains an invalid directory path."
      end
      dirPath = dirPath .. "/" .. segment
      if not g_resources.directoryExists(dirPath) then
        g_resources.makeDir(dirPath)
      end
      if not g_resources.directoryExists(dirPath) then
        return false, "Can't create " .. dirPath .. " in " .. g_resources.getWriteDir()
      end
    end
    if not g_resources.writeFileContents(dirPath .. "/" .. fileName, contents) then
      return false, "Can't write " .. relative
    end
  end
  return true
end

local function sanitizeConfigName(name)
  name = tostring(name or ""):trim()
  if name == "" or name:len() > 64 or name == "." or name == ".." or name:find("[^%w _%-]") then
    return nil
  end
  return name
end

function compressConfig(configName)
  if not g_resources.directoryExists("/bot/" .. configName) then
    return onError("Config " .. configName .. " doesn't exist")
  end
  local forArchive = collectConfigFiles("/bot/" .. configName, true)
  if not next(forArchive) then
    return nil
  end
  return g_resources.createArchive(forArchive)
end

function decompressConfig(configName, archiveOrFiles)
  configName = sanitizeConfigName(configName)
  if not configName then
    return false, tr("Use 1-64 letters, numbers, spaces, underscores or hyphens for the config name.")
  end

  local files = archiveOrFiles
  if type(files) ~= "table" then
    files = g_resources.decompressArchive(archiveOrFiles)
  end
  if type(files) ~= "table" or not next(files) then
    return false, tr("Archive is empty, corrupt or unsafe.")
  end

  local rootPath = "/bot/" .. configName
  local backup = g_resources.directoryExists(rootPath) and collectConfigFiles(rootPath, false) or nil
  if g_resources.directoryExists(rootPath) and not removeDirectoryTree(rootPath) then
    return false, tr("Could not replace existing config \"%s\".", configName)
  end

  local ok, err = writeConfigFiles(configName, files)
  if not ok then
    removeDirectoryTree(rootPath)
    if backup and next(backup) then
      writeConfigFiles(configName, backup)
    end
    return false, err
  end
  return true
end

-- Executor
function message(category, msg)
  local widget = g_ui.createWidget('BotLabel', botMessages)
  widget.added = g_clock.millis()
  if category == 'error' then
    widget:setText(msg)
    widget:setColor("red")
    g_logger.error("[BOT] " .. msg)
  elseif category == 'warn' then
    widget:setText(msg)
    widget:setColor("yellow")
    g_logger.warning("[BOT] " .. msg)
  elseif category == 'info' then
    widget:setText(msg)
    widget:setColor("white")
    g_logger.info("[BOT] " .. msg)
  end

  if botMessages:getChildCount() > 5 then
    botMessages:getFirstChild():destroy()
  end
end

function check()
  removeEvent(checkEvent)
  if not botExecutor then
    return
  end

  checkEvent = scheduleEvent(check, 10)

  local status, result = pcall(function()
    return botExecutor.script()
  end)
  if not status then
    botExecutor = nil -- critical
    return onError(result)
  end

  -- remove old messages
  local widget = botMessages:getFirstChild()
  if widget and widget.added + 5000 < g_clock.millis() then
    widget:destroy()
  end
end

-- Callbacks
function initCallbacks()
  connect(rootWidget, {
    onKeyDown = botKeyDown,
    onKeyUp = botKeyUp,
    onKeyPress = botKeyPress
  })

  connect(g_game, {
    onTalk = botOnTalk,
    onTextMessage = botOnTextMessage,
    onLoginAdvice = botOnLoginAdvice,
    onUse = botOnUse,
    onUseWith = botOnUseWith,
    onChannelList = botChannelList,
    onOpenChannel = botOpenChannel,
    onCloseChannel = botCloseChannel,
    onChannelEvent = botChannelEvent,
    onImbuementWindow = botImbuementWindow,
    onModalDialog = botModalDialog,
    onAttackingCreatureChange = botAttackingCreatureChange,
    onAddItem = botContainerAddItem,
    onRemoveItem = botContainerRemoveItem,
    onEditText = botGameEditText,
    onSpellCooldown = botSpellCooldown,
    onSpellGroupCooldown = botGroupSpellCooldown
  })

  connect(Tile, {
    onAddThing = botAddThing,
    onRemoveThing = botRemoveThing
  })

  connect(Creature, {
    onAppear = botCreatureAppear,
    onDisappear = botCreatureDisappear,
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
  })

  connect(LocalPlayer, {
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
    onManaChange = botManaChange,
    onStatesChange = botStatesChange,
    onInventoryChange = botInventoryChange
  })

  connect(Container, {
    onOpen = botContainerOpen,
    onClose = botContainerClose,
    onUpdateItem = botContainerUpdateItem,
    onAddItem = botContainerAddItem,
    onRemoveItem = botContainerRemoveItem,
  })

  connect(g_map, {
    onMissle = botOnMissle,
    onAnimatedText = botOnAnimatedText,
    onStaticText = botOnStaticText
  })
end

function terminateCallbacks()
  disconnect(rootWidget, {
    onKeyDown = botKeyDown,
    onKeyUp = botKeyUp,
    onKeyPress = botKeyPress
  })

  disconnect(g_game, {
    onTalk = botOnTalk,
    onTextMessage = botOnTextMessage,
    onLoginAdvice = botOnLoginAdvice,
    onUse = botOnUse,
    onUseWith = botOnUseWith,
    onChannelList = botChannelList,
    onOpenChannel = botOpenChannel,
    onCloseChannel = botCloseChannel,
    onChannelEvent = botChannelEvent,
    onImbuementWindow = botImbuementWindow,
    onModalDialog = botModalDialog,
    onAttackingCreatureChange = botAttackingCreatureChange,
    onEditText = botGameEditText,
    onSpellCooldown = botSpellCooldown,
    onSpellGroupCooldown = botGroupSpellCooldown
  })

  disconnect(Tile, {
    onAddThing = botAddThing,
    onRemoveThing = botRemoveThing
  })

  disconnect(Creature, {
    onAppear = botCreatureAppear,
    onDisappear = botCreatureDisappear,
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
  })

  disconnect(LocalPlayer, {
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
    onManaChange = botManaChange,
    onStatesChange = botStatesChange,
    onInventoryChange = botInventoryChange
  })

  disconnect(Container, {
    onOpen = botContainerOpen,
    onClose = botContainerClose,
    onUpdateItem = botContainerUpdateItem,
    onAddItem = botContainerAddItem,
    onRemoveItem = botContainerRemoveItem
  })

  disconnect(g_map, {
    onMissle = botOnMissle,
    onAnimatedText = botOnAnimatedText,
    onStaticText = botOnStaticText
  })
end

function safeBotCall(func)
  if botExecutor and botExecutor.isLoading and botExecutor.isLoading() then
    return
  end
  local status, result = pcall(func)
  if not status then
    onError(result)
  end
end

function botKeyDown(widget, keyCode, keyboardModifiers)
  if botExecutor == nil then return false end
  if keyCode == KeyUnknown then return end
  safeBotCall(function() botExecutor.callbacks.onKeyDown(keyCode, keyboardModifiers) end)
end

function botKeyUp(widget, keyCode, keyboardModifiers)
  if botExecutor == nil then return false end
  if keyCode == KeyUnknown then return end
  safeBotCall(function() botExecutor.callbacks.onKeyUp(keyCode, keyboardModifiers) end)
end

function botKeyPress(widget, keyCode, keyboardModifiers, autoRepeatTicks)
  if botExecutor == nil then return false end
  if keyCode == KeyUnknown then return end
  safeBotCall(function() botExecutor.callbacks.onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks) end)
end

function botOnTalk(name, level, mode, text, channelId, pos)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onTalk(name, level, mode, text, channelId, pos) end)
end

function botOnTextMessage(mode, text)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onTextMessage(mode, text) end)
end

function botOnLoginAdvice(message)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onLoginAdvice(message) end)
end

function botAddThing(tile, thing)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAddThing(tile, thing) end)
end

function botRemoveThing(tile, thing)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onRemoveThing(tile, thing) end)
end

function botCreatureAppear(creature)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreatureAppear(creature) end)
end

function botCreatureDisappear(creature)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreatureDisappear(creature) end)
end

function botCreaturePositionChange(creature, newPos, oldPos)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreaturePositionChange(creature, newPos, oldPos) end)
end

function botCraetureHealthPercentChange(creature, healthPercent)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreatureHealthPercentChange(creature, healthPercent) end)
end

function botOnUse(pos, itemId, stackPos, subType)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onUse(pos, itemId, stackPos, subType) end)
end

function botOnUseWith(pos, itemId, target, subType)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onUseWith(pos, itemId, target, subType) end)
end

function botContainerOpen(container, previousContainer)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onContainerOpen(container, previousContainer) end)
end

function botContainerClose(container)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onContainerClose(container) end)
end

function botContainerUpdateItem(container, slot, item, oldItem)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onContainerUpdateItem(container, slot, item, oldItem) end)
end

function botOnMissle(missle)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onMissle(missle) end)
end

function botOnAnimatedText(thing, text)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAnimatedText(thing, text) end)
end

function botOnStaticText(thing, text)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onStaticText(thing, text) end)
end

function botChannelList(channels)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onChannelList(channels) end)
end

function botOpenChannel(channelId, name)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onOpenChannel(channelId, name) end)
end

function botCloseChannel(channelId)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCloseChannel(channelId) end)
end

function botChannelEvent(channelId, name, event)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onChannelEvent(channelId, name, event) end)
end

function botCreatureTurn(creature, direction)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onTurn(creature, direction) end)
end

function botCreatureWalk(creature, oldPos, newPos)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onWalk(creature, oldPos, newPos) end)
end

function botImbuementWindow(itemId, slots, activeSlots, imbuements, needItems)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onImbuementWindow(itemId, slots, activeSlots, imbuements, needItems) end)
end

function botModalDialog(id, title, message, buttons, enterButton, escapeButton, choices, priority)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onModalDialog(id, title, message, buttons, enterButton, escapeButton, choices, priority) end)
end

function botGameEditText(id, itemId, maxLength, text, writer, time)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onGameEditText(id, itemId, maxLength, text, writer, time) end)
end

function botAttackingCreatureChange(creature, oldCreature)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAttackingCreatureChange(creature,oldCreature) end)
end

function botManaChange(player, mana, maxMana, oldMana, oldMaxMana)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onManaChange(player, mana, maxMana, oldMana, oldMaxMana) end)
end

function botStatesChange(player, states, oldStates)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onStatesChange(player, states, oldStates) end)
end

function botContainerAddItem(container, slot, item, oldItem)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAddItem(container, slot, item, oldItem) end)
end

function botContainerRemoveItem(container, slot, item)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onRemoveItem(container, slot, item) end)
end

function botSpellCooldown(iconId, duration)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onSpellCooldown(iconId, duration) end)
end

function botGroupSpellCooldown(iconId, duration)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onGroupSpellCooldown(iconId, duration) end)
end

function botInventoryChange(player, slot, item, oldItem)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onInventoryChange(player, slot, item, oldItem) end)
end

-- exports for vBot scripts (modules.game_bot.connect, etc.)
local frameworkConnect = connect
local frameworkDisconnect = disconnect

function connect(widget, signals)
  return frameworkConnect(widget, signals)
end

function disconnect(widget, signals)
  return frameworkDisconnect(widget, signals)
end
