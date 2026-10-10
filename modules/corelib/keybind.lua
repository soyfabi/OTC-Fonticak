
CHAT_MODE = {
  ON = 1,
  OFF = 2
}

Keybind = {
  presets = {},
  presetToIndex = {},
  currentPreset = nil,
  configs = {
    keybinds = {},
    hotkeys = {}
  },
  defaultKeys = {
    [CHAT_MODE.ON] = {},
    [CHAT_MODE.OFF] = {}
  },
  defaultKeybinds = {},
  hotkeys = {
    [CHAT_MODE.ON] = {},
    [CHAT_MODE.OFF] = {}
  },
  chatMode = CHAT_MODE.ON,

  reservedKeys = {
    ["Up"] = true,
    ["Down"] = true,
    ["Left"] = true,
    ["Right"] = true
  },

  -- Old preset node id -> { category, action }
  legacyActionRenames = {
    ["Dialogs_Open Bugreport"] = { "Dialogs", "Open Bug Report" },
    ["Sound_Mute/unmute"] = { "Sound", "Mute/unmute music" },
    ["Windows_show/hide Tasks Windows"] = { "Windows", "Open Tasks Window" },
    ["Windows_Show/hide Tasks Windows"] = { "Windows", "Open Tasks Window" },
    ["Windows_Show/hide Tasks Window"] = { "Windows", "Open Tasks Window" },
    ["Windows_show/hide Shader Windows"] = { "Windows", "Open Shader Window" },
    ["Windows_Show/hide Shader Windows"] = { "Windows", "Open Shader Window" },
    ["Windows_Show/hide Shader Window"] = { "Windows", "Open Shader Window" },
    ["Windows_show/hide inventory"] = { "Windows", "Open Inventory" },
    ["Windows_Show/hide Inventory"] = { "Windows", "Open Inventory" },
    ["Windows_show/hide cyclopedia"] = { "Windows", "Open Cyclopedia" },
    ["Windows_Show/hide Cyclopedia"] = { "Windows", "Open Cyclopedia" },
    ["Windows_show/hide battle list"] = { "Windows", "Open Battle List" },
    ["Windows_Show/hide Battle List"] = { "Windows", "Open Battle List" },
    ["Windows_show/hide VIP list"] = { "Windows", "Open VIP List" },
    ["Windows_Show/hide VIP List"] = { "Windows", "Open VIP List" },
    ["Windows_show/hide skills windows"] = { "Windows", "Open Skills Window" },
    ["Windows_Show/hide Skills Window"] = { "Windows", "Open Skills Window" },
    ["Windows_show/hide spell list"] = { "Windows", "Open Spell List" },
    ["Windows_Show/hide Spell List"] = { "Windows", "Open Spell List" },
    ["Windows_show/hide quest Log"] = { "Windows", "Open Quest Log" },
    ["Windows_Show/hide Quest Log"] = { "Windows", "Open Quest Log" },
    ["Windows_show/hide quest tracker"] = { "Windows", "Open Quest Tracker" },
    ["Windows_Show/hide Quest Tracker"] = { "Windows", "Open Quest Tracker" },
    ["Windows_show/hide prey tracker"] = { "Windows", "Open Prey Tracker" },
    ["Windows_Show/hide Prey Tracker"] = { "Windows", "Open Prey Tracker" },
    ["Windows_show/hide imbuement tracker"] = { "Windows", "Open Imbuement Tracker" },
    ["Windows_Show/hide Imbuement Tracker"] = { "Windows", "Open Imbuement Tracker" },
    ["Windows_show/hide analyser window"] = { "Windows", "Open Analyser Window" },
    ["Windows_Show/hide Analyser Window"] = { "Windows", "Open Analyser Window" },
    ["Windows_show/hide wheel of destiny"] = { "Windows", "Open Wheel of Destiny" },
    ["Windows_Show/hide Wheel of Destiny"] = { "Windows", "Open Wheel of Destiny" },
    ["Windows_show/hide exaltation forge"] = { "Windows", "Open Exaltation Forge" },
    ["Windows_Show/hide Exaltation Forge"] = { "Windows", "Open Exaltation Forge" },
    ["Windows_show/hide reward wall"] = { "Windows", "Open Reward Wall" },
    ["Windows_Show/hide Reward Wall"] = { "Windows", "Open Reward Wall" },
    ["Windows_show/hide store"] = { "Windows", "Open Store" },
    ["Windows_Show/hide Store"] = { "Windows", "Open Store" },
    ["Windows_show/hide Hotkeys"] = { "Windows", "Open Hotkeys" },
    ["Windows_Show/hide Hotkeys"] = { "Windows", "Open Hotkeys" },
    ["Windows_show/hide bestiary tracker"] = { "Windows", "Open Bestiary Tracker" },
    ["Windows_Show/hide Bestiary Tracker"] = { "Windows", "Open Bestiary Tracker" },
    ["Windows_show/hide bosstiary tracker"] = { "Windows", "Open Bosstiary Tracker" },
    ["Windows_Show/hide Bosstiary Tracker"] = { "Windows", "Open Bosstiary Tracker" },
    ["Windows_show/hide bosstiary"] = { "Windows", "Open Bosstiary" },
    ["Windows_Show/hide Bosstiary"] = { "Windows", "Open Bosstiary" },
    ["Windows_show/hide boss slots"] = { "Windows", "Open Boss Slots" },
    ["Windows_Show/hide Boss Slots"] = { "Windows", "Open Boss Slots" },
    ["Windows_show/hide boss slots dialog"] = { "Windows", "Open Boss Slots" },
    ["Windows_Show/hide Boss Slots Dialog"] = { "Windows", "Open Boss Slots" },
  },

  legacyPresetKeysMigrated = false
}

function Keybind.makeIndex(category, action)
  return category .. '_' .. action
end

function Keybind.normalizeKeybindIdentity(category, action)
  if not category or not action then
    return category, action
  end

  local renamed = Keybind.legacyActionRenames[Keybind.makeIndex(category, action)]
  if renamed then
    return renamed[1], renamed[2]
  end

  return category, action
end

function Keybind.getLegacyIndex(category, action)
  local newIndex = Keybind.makeIndex(category, action)
  for oldIndex, identity in pairs(Keybind.legacyActionRenames) do
    if Keybind.makeIndex(identity[1], identity[2]) == newIndex then
      return oldIndex
    end
  end
  return nil
end

function Keybind.migrateLegacyPresetKeys()
  if Keybind.legacyPresetKeysMigrated then
    return
  end
  Keybind.legacyPresetKeysMigrated = true

  for _, preset in ipairs(Keybind.presets) do
    local config = Keybind.configs.keybinds[preset]
    if config then
      local changed = false
      for oldIndex, identity in pairs(Keybind.legacyActionRenames) do
        local newIndex = Keybind.makeIndex(identity[1], identity[2])
        if Keybind.defaultKeybinds[newIndex] then
          local oldNode = config:getNode(oldIndex)
          if oldNode then
            if not config:getNode(newIndex) then
              config:setNode(newIndex, oldNode)
            end
            config:remove(oldIndex)
            changed = true
          end
        end
      end
      if changed then
        config:save()
      end
    end
  end
end

KEY_UP = 1
KEY_DOWN = 2
KEY_PRESS = 3

HOTKEY_ACTION = {
  USE_YOURSELF = 1,
  USE_CROSSHAIR = 2,
  USE_TARGET = 3,
  EQUIP = 4,
  USE = 5,
  TEXT = 6,
  TEXT_AUTO = 7,
  SPELL = 8,
  SMART_CAST = 9
}

function Keybind.init()
  connect(g_game, { onGameStart = Keybind.online, onGameEnd = Keybind.offline })

  Keybind.presets = g_settings.getList("controls-presets")

  if #Keybind.presets == 0 then
    Keybind.presets = { "Druid", "Knight", "Paladin", "Sorcerer", "Monk" }
    Keybind.currentPreset = "Druid"
  else
    Keybind.currentPreset = g_settings.getValue("controls-preset-current")
  end

  for index, preset in ipairs(Keybind.presets) do
    Keybind.presetToIndex[preset] = index
  end

  if not g_resources.directoryExists("/controls") then
    g_resources.makeDir("/controls")
  end

  if not g_resources.directoryExists("/controls/keybinds") then
    g_resources.makeDir("/controls/keybinds")
  end

  if not g_resources.directoryExists("/controls/hotkeys") then
    g_resources.makeDir("/controls/hotkeys")
  end

  for _, preset in ipairs(Keybind.presets) do
    Keybind.configs.keybinds[preset] = g_configs.create("/controls/keybinds/" .. preset .. ".otml")
    Keybind.configs.hotkeys[preset] = g_configs.create("/controls/hotkeys/" .. preset .. ".otml")
  end

  for preset, config in pairs(Keybind.configs.hotkeys) do
    for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
      Keybind.hotkeys[chatMode][preset] = {}
      local hotkeyId = 1
      local hotkeys = config:getNode(chatMode) or config:getNode(tostring(chatMode))

      if hotkeys then
        local hotkey = hotkeys[tostring(hotkeyId)]
        while hotkey do
          if hotkey.data.parameter then
            hotkey.data.parameter = "\"" .. hotkey.data.parameter .. "\"" -- forcing quotes cause OTML is not saving them, just wow
          end

          table.insert(Keybind.hotkeys[chatMode][preset], hotkey)
          hotkeyId = hotkeyId + 1

          hotkey = hotkeys[tostring(hotkeyId)]
        end
      end
    end
  end
end

function Keybind.terminate()
  disconnect(g_game, { onGameStart = Keybind.online, onGameEnd = Keybind.offline })

  for _, preset in ipairs(Keybind.presets) do
    Keybind.configs.keybinds[preset]:save()
    Keybind.configs.hotkeys[preset]:save()
  end

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.setValue("controls-preset-current", Keybind.currentPreset)
  g_settings.save()
end

function Keybind.online()
  for _, hotkey in ipairs(Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]) do
    Keybind.bindHotkey(hotkey.hotkeyId, Keybind.chatMode)
  end
end

function Keybind.offline()
  for _, hotkey in ipairs(Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]) do
    Keybind.unbindHotkey(hotkey.hotkeyId, Keybind.chatMode)
  end
end

function Keybind.new(category, action, primary, secondary, alone)
  local index = category .. '_' .. action
  if Keybind.defaultKeybinds[index] then
    pwarning(string.format("Keybind for [%s: %s] is already in use", category, action))
    return
  end

  local keys = {}
  if type(primary) == "string" then
    keys[CHAT_MODE.ON] = { primary = primary }
    keys[CHAT_MODE.OFF] = { primary = primary }
  else
    keys[CHAT_MODE.ON] = { primary = primary[CHAT_MODE.ON] }
    keys[CHAT_MODE.OFF] = { primary = primary[CHAT_MODE.OFF] }
  end

  if type(secondary) == "string" then
    keys[CHAT_MODE.ON].secondary = secondary
    keys[CHAT_MODE.OFF].secondary = secondary
  else
    keys[CHAT_MODE.ON].secondary = secondary[CHAT_MODE.ON]
    keys[CHAT_MODE.OFF].secondary = secondary[CHAT_MODE.OFF]
  end

  keys[CHAT_MODE.ON].primary = retranslateKeyComboDesc(keys[CHAT_MODE.ON].primary)

  if keys[CHAT_MODE.ON].secondary then
    keys[CHAT_MODE.ON].secondary = retranslateKeyComboDesc(keys[CHAT_MODE.ON].secondary)
  end

  keys[CHAT_MODE.OFF].primary = retranslateKeyComboDesc(keys[CHAT_MODE.OFF].primary)

  if keys[CHAT_MODE.OFF].secondary then
    keys[CHAT_MODE.OFF].secondary = retranslateKeyComboDesc(keys[CHAT_MODE.OFF].secondary)
  end

  if Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].primary] then
    local primaryIndex = Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].primary]
    local primaryKeybind = Keybind.defaultKeybinds[primaryIndex]
    perror(string.format("Default primary key (Chat Mode On) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, primaryKeybind.category, primaryKeybind.action))
    return
  end

  if Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].primary] then
    local primaryIndex = Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].primary]
    local primaryKeybind = Keybind.defaultKeybinds[primaryIndex]
    perror(string.format("Default primary key (Chat Mode Off) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, primaryKeybind.category, primaryKeybind.action))
    return
  end

  if keys[CHAT_MODE.ON].secondary and Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].secondary] then
    local secondaryIndex = Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].secondary]
    local secondaryKeybind = Keybind.defaultKeybinds[secondaryIndex]
    perror(string.format("Default secondary key (Chat Mode On) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, secondaryKeybind.category, secondaryKeybind.action))
    return
  end

  if keys[CHAT_MODE.OFF].secondary and Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].secondary] then
    local secondaryIndex = Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].secondary]
    local secondaryKeybind = Keybind.defaultKeybinds[secondaryIndex]
    perror(string.format("Default secondary key (Chat Mode Off) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, secondaryKeybind.category, secondaryKeybind.action))
    return
  end

  if keys[CHAT_MODE.ON].primary then
    Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].primary] = index
  end

  if keys[CHAT_MODE.OFF].primary then
    Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].primary] = index
  end

  Keybind.defaultKeybinds[index] = {
    category = category,
    action = action,
    keys = keys,
    alone = alone
  }

  if keys[CHAT_MODE.ON].secondary then
    Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].secondary] = index
  end
  if keys[CHAT_MODE.OFF].secondary then
    Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].secondary] = index
  end
end

function Keybind.delete(category, action)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]

  if not keybind then
    return
  end

  Keybind.unbind(category, action)

  local keysOn = keybind.keys[CHAT_MODE.ON]
  local keysOff = keybind.keys[CHAT_MODE.OFF]

  local primaryOn = keysOn.primary and tostring(keysOn.primary) or nil
  local primaryOff = keysOff.primary and tostring(keysOff.primary) or nil
  local secondaryOn = keysOn.secondary and tostring(keysOn.secondary) or nil
  local secondaryOff = keysOff.secondary and tostring(keysOff.secondary) or nil

  if primaryOn and primaryOn:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.ON][primaryOn] = nil
  end
  if secondaryOn and secondaryOn:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.ON][secondaryOn] = nil
  end

  if primaryOff and primaryOff:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.OFF][primaryOff] = nil
  end
  if secondaryOff and secondaryOff:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.OFF][secondaryOff] = nil
  end

  Keybind.defaultKeybinds[index] = nil
end

local function getKeybindMouseWidget(widget)
  if widget and not widget:isDestroyed() then
    return widget
  end
  if modules.game_interface and modules.game_interface.getRootPanel then
    return modules.game_interface.getRootPanel()
  end
  return g_ui.getRootWidget()
end

local function bindKeybindCombo(keyCombo, callbackInfo, widget)
  if not keyCombo then
    return
  end
  keyCombo = tostring(keyCombo)
  if keyCombo:len() == 0 then
    return
  end
  if Keybind.isMouseKeyCombo(keyCombo) then
    if callbackInfo.type == KEY_DOWN or callbackInfo.type == KEY_PRESS then
      Keybind.bindMouseButtonKey(keyCombo, callbackInfo.callback, getKeybindMouseWidget(widget))
    end
    return
  end
  if callbackInfo.type == KEY_UP then
    g_keyboard.bindKeyUp(keyCombo, callbackInfo.callback, widget, callbackInfo.alone)
  elseif callbackInfo.type == KEY_DOWN then
    g_keyboard.bindKeyDown(keyCombo, callbackInfo.callback, widget, callbackInfo.alone)
  elseif callbackInfo.type == KEY_PRESS then
    g_keyboard.bindKeyPress(keyCombo, callbackInfo.callback, widget)
  end
end

local function unbindKeybindCombo(keyCombo, callbackInfo, widget)
  if not keyCombo then
    return
  end
  keyCombo = tostring(keyCombo)
  if keyCombo:len() == 0 then
    return
  end
  if Keybind.isMouseKeyCombo(keyCombo) then
    if callbackInfo.type == KEY_DOWN or callbackInfo.type == KEY_PRESS then
      Keybind.unbindMouseButtonKey(keyCombo, getKeybindMouseWidget(widget))
    end
    return
  end
  if callbackInfo.type == KEY_UP then
    g_keyboard.unbindKeyUp(keyCombo, callbackInfo.callback, widget)
  elseif callbackInfo.type == KEY_DOWN then
    g_keyboard.unbindKeyDown(keyCombo, callbackInfo.callback, widget)
  elseif callbackInfo.type == KEY_PRESS then
    g_keyboard.unbindKeyPress(keyCombo, callbackInfo.callback, widget)
  end
end

function Keybind.bind(category, action, callbacks, widget)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]

  if not keybind then
    return
  end

  keybind.callbacks = callbacks
  keybind.widget = widget

  local keys = Keybind.getKeybindKeys(category, action)

  for _, callback in ipairs(keybind.callbacks) do
    bindKeybindCombo(keys.primary, callback, keybind.widget)
    bindKeybindCombo(keys.secondary, callback, keybind.widget)
  end
end

function Keybind.unbind(category, action)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]

  if not keybind or not keybind.callbacks then
    return
  end

  local keys = Keybind.getKeybindKeys(category, action)

  for _, callback in ipairs(keybind.callbacks) do
    unbindKeybindCombo(keys.primary, callback, keybind.widget)
    unbindKeybindCombo(keys.secondary, callback, keybind.widget)
  end
end

function Keybind.newPreset(presetName)
  if Keybind.presetToIndex[presetName] then
    return
  end

  table.insert(Keybind.presets, presetName)
  Keybind.presetToIndex[presetName] = #Keybind.presets

  Keybind.configs.keybinds[presetName] = g_configs.create("/controls/keybinds/" .. presetName .. ".otml")
  Keybind.configs.hotkeys[presetName] = g_configs.create("/controls/hotkeys/" .. presetName .. ".otml")

  Keybind.hotkeys[CHAT_MODE.ON][presetName] = {}
  Keybind.hotkeys[CHAT_MODE.OFF][presetName] = {}

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()
end

function Keybind.copyPreset(fromPreset, toPreset)
  if Keybind.presetToIndex[toPreset] then
    return false
  end

  table.insert(Keybind.presets, toPreset)
  Keybind.presetToIndex[toPreset] = #Keybind.presets

  Keybind.configs.keybinds[fromPreset]:save()
  Keybind.configs.hotkeys[fromPreset]:save()

  local keybindsConfigPath = Keybind.configs.keybinds[fromPreset]:getFileName()
  local keybindsConfigContent = g_resources.readFileContents(keybindsConfigPath)
  g_resources.writeFileContents("/controls/keybinds/" .. toPreset .. ".otml", keybindsConfigContent)
  Keybind.configs.keybinds[toPreset] = g_configs.create("/controls/keybinds/" .. toPreset .. ".otml")

  local hotkeysConfigPath = Keybind.configs.hotkeys[fromPreset]:getFileName()
  local hotkeysConfigContent = g_resources.readFileContents(hotkeysConfigPath)
  g_resources.writeFileContents("/controls/hotkeys/" .. toPreset .. ".otml", hotkeysConfigContent)
  Keybind.configs.hotkeys[toPreset] = g_configs.create("/controls/hotkeys/" .. toPreset .. ".otml")

  for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
    Keybind.hotkeys[chatMode][toPreset] = {}

    local hotkeyId = 1
    local hotkeys = Keybind.configs.hotkeys[toPreset]:getNode(chatMode)

    if hotkeys then
      local hotkey = hotkeys[tostring(hotkeyId)]
      while hotkey do
        if hotkey.data.parameter then
          hotkey.data.parameter = "\"" .. hotkey.data.parameter .. "\"" -- forcing quotes cause OTML is not saving them, just wow
        end

        table.insert(Keybind.hotkeys[chatMode][toPreset], hotkey)
        hotkeyId = hotkeyId + 1

        hotkey = hotkeys[tostring(hotkeyId)]
      end
    end
  end

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()

  return true
end

function Keybind.renamePreset(oldPresetName, newPresetName)
  if Keybind.currentPreset == oldPresetName then
    Keybind.currentPreset = newPresetName
  end

  local index = Keybind.presetToIndex[oldPresetName]
  Keybind.presetToIndex[oldPresetName] = nil
  Keybind.presetToIndex[newPresetName] = index
  Keybind.presets[index] = newPresetName

  local keybindsConfigPath = Keybind.configs.keybinds[oldPresetName]:getFileName()
  Keybind.configs.keybinds[oldPresetName]:save()
  Keybind.configs.keybinds[oldPresetName] = nil

  local keybindsConfigContent = g_resources.readFileContents(keybindsConfigPath)
  g_resources.deleteFile(keybindsConfigPath)
  g_resources.writeFileContents("/controls/keybinds/" .. newPresetName .. ".otml", keybindsConfigContent)
  Keybind.configs.keybinds[newPresetName] = g_configs.create("/controls/keybinds/" .. newPresetName .. ".otml")

  local hotkeysConfigPath = Keybind.configs.hotkeys[oldPresetName]:getFileName()
  Keybind.configs.hotkeys[oldPresetName]:save()
  Keybind.configs.hotkeys[oldPresetName] = nil

  local hotkeysConfigContent = g_resources.readFileContents(hotkeysConfigPath)
  g_resources.deleteFile(hotkeysConfigPath)
  g_resources.writeFileContents("/controls/hotkeys/" .. newPresetName .. ".otml", hotkeysConfigContent)
  Keybind.configs.hotkeys[newPresetName] = g_configs.create("/controls/hotkeys/" .. newPresetName .. ".otml")

  Keybind.hotkeys[CHAT_MODE.ON][newPresetName] = Keybind.hotkeys[CHAT_MODE.ON][oldPresetName]
  Keybind.hotkeys[CHAT_MODE.OFF][newPresetName] = Keybind.hotkeys[CHAT_MODE.OFF][oldPresetName]

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()
end

function Keybind.removePreset(presetName)
  if #Keybind.presets == 1 then
    return false
  end

  table.remove(Keybind.presets, Keybind.presetToIndex[presetName])
  Keybind.presetToIndex[presetName] = nil

  Keybind.configs.keybinds[presetName] = nil
  g_configs.unload("/controls/keybinds/" .. presetName .. ".otml")
  g_resources.deleteFile("/controls/keybinds/" .. presetName .. ".otml")

  Keybind.configs.hotkeys[presetName] = nil
  g_configs.unload("/controls/hotkeys/" .. presetName .. ".otml")
  g_resources.deleteFile("/controls/hotkeys/" .. presetName .. ".otml")

  if Keybind.currentPreset == presetName then
    Keybind.currentPreset = Keybind.presets[1]
  end

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()

  return true
end

function Keybind.selectPreset(presetName)
  if Keybind.currentPreset == presetName then
    return false
  end

  if not Keybind.presetToIndex[presetName] then
    return false
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.unbind(keybind.category, keybind.action)
    end
  end

  for _, hotkey in ipairs(Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]) do
    Keybind.unbindHotkey(hotkey.hotkeyId, Keybind.chatMode)
  end

  Keybind.currentPreset = presetName

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.bind(keybind.category, keybind.action, keybind.callbacks, keybind.widget)
    end
  end

  for _, hotkey in ipairs(Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]) do
    Keybind.bindHotkey(hotkey.hotkeyId, Keybind.chatMode)
  end

  Keybind.refreshControlButtonTooltips()
  return true
end

function Keybind.getAction(category, action)
  category, action = Keybind.normalizeKeybindIdentity(category, action)
  return Keybind.defaultKeybinds[Keybind.makeIndex(category, action)]
end

function Keybind.setPrimaryActionKey(category, action, preset, keyCombo, chatMode)
  category, action = Keybind.normalizeKeybindIdentity(category, action)
  local index = Keybind.makeIndex(category, action)
  local keybind = Keybind.defaultKeybinds[index]
  if not keybind then
    return false
  end

  local keys = Keybind.configs.keybinds[preset]:getNode(index)
  if not keys then
    local legacyIndex = Keybind.getLegacyIndex(category, action)
    if legacyIndex then
      keys = Keybind.configs.keybinds[preset]:getNode(legacyIndex)
    end
  end
  if not keys then
    keys = table.recursivecopy(keybind.keys)
  else
    chatMode = tostring(chatMode)
  end

  if keybind.callbacks then
    Keybind.unbind(category, action)
  end
  
  if not keys[chatMode] then
    keys[chatMode] = { primary = keyCombo, secondary = keybind.keys[tonumber(chatMode)].secondary }
  end

  keys[chatMode].primary = keyCombo

  local ret = false
  if keys[chatMode].secondary == keyCombo then
    keys[chatMode].secondary = nil
    ret = true
  end

  Keybind.configs.keybinds[preset]:setNode(index, keys)

  local legacyIndex = Keybind.getLegacyIndex(category, action)
  if legacyIndex and legacyIndex ~= index then
    Keybind.configs.keybinds[preset]:remove(legacyIndex)
  end

  if keybind.callbacks then
    Keybind.bind(category, action, keybind.callbacks, keybind.widget)
  end

  Keybind.refreshControlButtonTooltips()
  return ret
end

function Keybind.setSecondaryActionKey(category, action, preset, keyCombo, chatMode)
  category, action = Keybind.normalizeKeybindIdentity(category, action)
  local index = Keybind.makeIndex(category, action)
  local keybind = Keybind.defaultKeybinds[index]
  if not keybind then
    return false
  end

  local keys = Keybind.configs.keybinds[preset]:getNode(index)
  if not keys then
    local legacyIndex = Keybind.getLegacyIndex(category, action)
    if legacyIndex then
      keys = Keybind.configs.keybinds[preset]:getNode(legacyIndex)
    end
  end
  if not keys then
    keys = table.recursivecopy(keybind.keys)
  else
    chatMode = tostring(chatMode)
  end

  if keybind.callbacks then
    Keybind.unbind(category, action)
  end
  
  if not keys[chatMode] then
    keys[chatMode] = { primary = keybind.keys[tonumber(chatMode)].primary, secondary = keyCombo }
  end

  keys[chatMode].secondary = keyCombo

  local ret = false
  if keys[chatMode].primary == keyCombo then
    keys[chatMode].primary = nil
    ret = true
  end

  Keybind.configs.keybinds[preset]:setNode(index, keys)

  local legacyIndex = Keybind.getLegacyIndex(category, action)
  if legacyIndex and legacyIndex ~= index then
    Keybind.configs.keybinds[preset]:remove(legacyIndex)
  end

  if keybind.callbacks then
    Keybind.bind(category, action, keybind.callbacks, keybind.widget)
  end

  Keybind.refreshControlButtonTooltips()
  return ret
end

function Keybind.resetKeybindsToDefault(presetName, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.unbind(keybind.category, keybind.action)
    end
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    local index = keybind.category .. '_' .. keybind.action
    Keybind.configs.keybinds[presetName]:setNode(index, keybind.keys)
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.bind(keybind.category, keybind.action, keybind.callbacks, keybind.widget)
    end
  end

  Keybind.refreshControlButtonTooltips()
end

function Keybind.getKeybindKeys(category, action, chatMode, preset, forceDefault)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  category, action = Keybind.normalizeKeybindIdentity(category, action)

  local index = Keybind.makeIndex(category, action)
  local keybind = Keybind.defaultKeybinds[index]
  local config = Keybind.configs.keybinds[preset or Keybind.currentPreset]
  local keys = config and config:getNode(index)

  if not keys and config then
    local legacyIndex = Keybind.getLegacyIndex(category, action)
    if legacyIndex then
      keys = config:getNode(legacyIndex)
    end
  end

  if not keys or forceDefault then
    if not keybind then
      keys = {
        primary = "",
        secondary = ""
      }
    else
      keys = {
        primary = keybind.keys[chatMode].primary,
        secondary = keybind.keys[chatMode].secondary
      }
    end
  else
    keys = keys[chatMode] or keys[tostring(chatMode)]
  end

  if not keys then
    keys = {
      primary = "",
      secondary = ""
    }
  end

  return keys
end

function Keybind.isKeyComboUsed(keyCombo, category, action, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  if Keybind.reservedKeys[keyCombo] then
    return true
  end

  if category and action then
    local targetKeys = Keybind.getKeybindKeys(category, action, chatMode, Keybind.currentPreset)

    for _, keybind in pairs(Keybind.defaultKeybinds) do
      local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, Keybind.currentPreset)
      if (keys.primary == keyCombo and targetKeys.primary ~= keyCombo) or (keys.secondary == keyCombo and targetKeys.secondary ~= keyCombo) then
        return true
      end
    end
  else
    for _, keybind in pairs(Keybind.defaultKeybinds) do
      local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, Keybind.currentPreset)
      if keys.primary == keyCombo or keys.secondary == keyCombo then
        return true
      end
    end

    if Keybind.hotkeys[chatMode][Keybind.currentPreset] then
      for _, hotkey in ipairs(Keybind.hotkeys[chatMode][Keybind.currentPreset]) do
        if hotkey.primary == keyCombo or hotkey.secondary == keyCombo then
          return true
        end
      end
    end
  end

  return false
end

function Keybind.getKeyComboOverwriteTarget(keyCombo, category, action, chatMode, preset)
  if not keyCombo or keyCombo == '' or Keybind.reservedKeys[keyCombo] then
    return nil
  end

  if not chatMode then
    chatMode = Keybind.chatMode
  end

  preset = preset or Keybind.currentPreset

  if not category or not action then
    return nil
  end

  local targetKeys = Keybind.getKeybindKeys(category, action, chatMode, preset)

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, preset)
    if keys.primary == keyCombo and targetKeys.primary ~= keyCombo then
      return keybind.category, keybind.action
    end
    if keys.secondary == keyCombo and targetKeys.secondary ~= keyCombo then
      return keybind.category, keybind.action
    end
  end

  return nil
end

function Keybind.formatKeyComboOverwriteMessage(keyCombo, category, action, chatMode, preset)
  local conflictCategory, conflictAction = Keybind.getKeyComboOverwriteTarget(keyCombo, category, action, chatMode, preset)
  if not conflictAction then
    return tr('This hotkey is already in use and will be overwritten.')
  end

  return tr('This hotkey is already in use and will be overwritten by \'%s: %s\'.', conflictCategory, conflictAction)
end

function Keybind.saveHotkeys(preset, chatMode)
  preset = preset or Keybind.currentPreset
  chatMode = chatMode or Keybind.chatMode

  if not Keybind.hotkeys[chatMode][preset] then
    Keybind.hotkeys[chatMode][preset] = {}
  end

  for id, hotkey in ipairs(Keybind.hotkeys[chatMode][preset]) do
    hotkey.hotkeyId = id
  end

  Keybind.configs.hotkeys[preset]:setNode(chatMode, Keybind.hotkeys[chatMode][preset])
  Keybind.configs.hotkeys[preset]:save()
end

function Keybind.newHotkey(action, data, primary, secondary, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local hotkey = {
    action = action,
    data = data,
    primary = primary or "",
    secondary = secondary or ""
  }

  if not Keybind.hotkeys[chatMode][Keybind.currentPreset] then
    Keybind.hotkeys[chatMode][Keybind.currentPreset] = {}
  end

  table.insert(Keybind.hotkeys[chatMode][Keybind.currentPreset], hotkey)

  local hotkeyId = #Keybind.hotkeys[chatMode][Keybind.currentPreset]
  hotkey.hotkeyId = hotkeyId
  Keybind.saveHotkeys(Keybind.currentPreset, chatMode)

  Keybind.bindHotkey(hotkeyId, chatMode)
end

function Keybind.removeHotkey(hotkeyId, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  if not Keybind.hotkeys[chatMode][Keybind.currentPreset] then
    return
  end

  Keybind.unbindHotkey(hotkeyId, chatMode)

  table.remove(Keybind.hotkeys[chatMode][Keybind.currentPreset], hotkeyId)
  Keybind.saveHotkeys(Keybind.currentPreset, chatMode)
end

function Keybind.editHotkey(hotkeyId, action, data, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  Keybind.unbindHotkey(hotkeyId, chatMode)

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]
  hotkey.action = action
  hotkey.data = data
  Keybind.saveHotkeys(Keybind.currentPreset, chatMode)

  Keybind.bindHotkey(hotkeyId, chatMode)
end

function Keybind.editHotkeyKeys(hotkeyId, primary, secondary, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  Keybind.unbindHotkey(hotkeyId, chatMode)

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]
  hotkey.primary = primary or ""
  hotkey.secondary = secondary or ""
  Keybind.saveHotkeys(Keybind.currentPreset, chatMode)

  Keybind.bindHotkey(hotkeyId, chatMode)
end

function Keybind.removeAllHotkeys(chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  for _, hotkey in ipairs(Keybind.hotkeys[chatMode][Keybind.currentPreset]) do
    Keybind.unbindHotkey(hotkey.hotkeyId, chatMode)
  end

  Keybind.hotkeys[chatMode][Keybind.currentPreset] = {}

  Keybind.configs.hotkeys[Keybind.currentPreset]:remove(chatMode)
  Keybind.configs.hotkeys[Keybind.currentPreset]:remove(tostring(chatMode))
  Keybind.configs.hotkeys[Keybind.currentPreset]:save()
end

function Keybind.getHotkeyKeys(hotkeyId, preset, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end
  if not preset then
    preset = Keybind.currentPreset
  end

  local keys = { primary = "", secondary = "" }
  if not Keybind.hotkeys[chatMode][preset] then
    return keys
  end

  local hotkey = Keybind.hotkeys[chatMode][preset][hotkeyId]
  if not hotkey then
    return keys
  end

  local config = Keybind.configs.hotkeys[preset]:getNode(chatMode)
  if not config then
    return keys
  end

  return config[tostring(hotkeyId)] or keys
end

function Keybind.hotkeyCallback(hotkeyId, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]

  if not hotkey then
    return
  end

  local action = hotkey.action
  local data = hotkey.data

  if action == HOTKEY_ACTION.USE_YOURSELF then
    if g_game.getClientVersion() < 780 then
      local item = g_game.findPlayerItem(data.itemId, data.subType or -1)

      if item then
        g_game.useWith(item, g_game.getLocalPlayer())
      end
    else
      g_game.useInventoryItemWith(data.itemId, g_game.getLocalPlayer(), data.subType or -1)
    end
  elseif action == HOTKEY_ACTION.USE_CROSSHAIR then
    local item = Item.create(data.itemId)

    if g_game.getClientVersion() < 780 then
      item = g_game.findPlayerItem(data.itemId, data.subType or -1)
    end

    if item then
      modules.game_interface.startUseWith(item, data.subType or -1)
    end
  elseif action == HOTKEY_ACTION.USE_TARGET then
    local attackingCreature = g_game.getAttackingCreature()
    if not attackingCreature then
      local item = Item.create(data.itemId)

      if g_game.getClientVersion() < 780 then
        item = g_game.findPlayerItem(data.itemId, data.subType or -1)
      end

      if item then
        modules.game_interface.startUseWith(item, data.subType or -1)
      end

      return
    end

    if attackingCreature:getTile() then
      if g_game.getClientVersion() < 780 then
        local item = g_game.findPlayerItem(data.itemId, data.subType or -1)
        if item then
          g_game.useWith(item, attackingCreature, data.subType or -1)
        end
      else
        g_game.useInventoryItemWith(data.itemId, attackingCreature, data.subType or -1)
      end
    end
  elseif action == HOTKEY_ACTION.EQUIP then
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer or not data.itemId or data.itemId == 0 then
      return
    end

    local tier = 0
    if g_game.getFeature(GameThingUpgradeClassification) and data.upgradeTier then
      tier = data.upgradeTier
    end

    if localPlayer:getInventoryCount(data.itemId, tier) == 0
        and not localPlayer:hasEquippedItemId(data.itemId, tier) then
      return
    end

    g_game.equipItemId(data.itemId, tier)
  elseif action == HOTKEY_ACTION.USE then
    if g_game.getClientVersion() < 780 then
      local item = g_game.findPlayerItem(data.itemId, data.subType or -1)

      if item then
        g_game.use(item)
      end
    else
      g_game.useInventoryItem(data.itemId)
    end
  elseif action == HOTKEY_ACTION.TEXT then
    local text = hotkey.data.text or ""
    text = text:gsub("^%[Text%]%s*", ""):gsub("^%[Spell%]%s*", "")
    if modules.game_interface.isChatVisible() then
      modules.game_console.setTextEditText(text)
    end
  elseif action == HOTKEY_ACTION.TEXT_AUTO then
    local text = hotkey.data.text or ""
    text = text:gsub("^%[Text%]%s*", ""):gsub("^%[Spell%]%s*", "")
    -- Automatic text hotkeys must use the game channel, never the active
    -- private-chat input.
    g_game.talk(text)
  elseif action == HOTKEY_ACTION.SPELL then
    local text = data.words or ""
    text = text:gsub("^%[Text%]%s*", ""):gsub("^%[Spell%]%s*", "")
    if data.parameter then
      text = text .. " " .. data.parameter
    end

    -- Cast through the game channel even when the private-chat input has focus.
    g_game.talk(text)
  elseif action == HOTKEY_ACTION.SMART_CAST then
    local pos = g_window.getMousePosition()
    local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(pos, false)
    if clickedWidget and clickedWidget:getClassName() == 'UIGameMap' then
      local tile = clickedWidget:getTile(pos)
      if tile then
        local item = Item.create(data.itemId)
        if g_game.getClientVersion() < 780 then
          item = g_game.findPlayerItem(data.itemId, data.subType or -1)
        end
        if item then
          g_game.useWith(item, tile:getTopUseThing(), data.subType or -1)
        end
      end
    end
  end
end

-- ====================================================================
-- Mouse button hotkeys (MB1–MB5)
-- ====================================================================

local MOUSE_KEY_CODES = {
  MB1 = Mouse1Button,
  MB2 = Mouse2Button,
  MB3 = Mouse3Button,
  MB4 = Mouse4Button,
  MB5 = Mouse5Button
}

-- Returns true when keyCombo is an unmodified side/middle mouse hotkey.
function Keybind.isMouseKey(keyCombo)
  return keyCombo ~= nil and MOUSE_KEY_CODES[keyCombo] ~= nil
end

function Keybind.isMouseKeyCombo(keyCombo)
  if not keyCombo or keyCombo == '' then
    return false
  end

  for _, part in ipairs(tostring(keyCombo):split('+')) do
    if MOUSE_KEY_CODES[part:trim()] then
      return true
    end
  end

  return false
end

function Keybind.getMouseKeyCombo(rawButton, keyboardModifiers)
  local button = translateMouseButton(rawButton)
  local keyCode = nil

  for _, code in pairs(MOUSE_KEY_CODES) do
    if button == code then
      keyCode = code
      break
    end
  end

  if not keyCode then
    return nil
  end

  if keyboardModifiers == nil then
    for combo, code in pairs(MOUSE_KEY_CODES) do
      if code == keyCode and (code == Mouse3Button or code == Mouse4Button or code == Mouse5Button) then
        return combo
      end
    end
    keyboardModifiers = KeyboardNoModifier
  end

  return determineKeyComboDesc(keyCode, keyboardModifiers)
end

function Keybind.matchesMouseKeyCombo(keyCombo, mouseButton, keyboardModifiers)
  if not keyCombo or keyCombo == '' then
    return false
  end

  local actual = Keybind.getMouseKeyCombo(mouseButton, keyboardModifiers or KeyboardNoModifier)
  return actual == keyCombo
end

function Keybind.matchesActionMouseInput(category, action, mouseButton, keyboardModifiers, chatMode, preset)
  local keys = Keybind.getKeybindKeys(category, action, chatMode, preset)
  return Keybind.matchesMouseKeyCombo(keys.primary, mouseButton, keyboardModifiers)
      or Keybind.matchesMouseKeyCombo(keys.secondary, mouseButton, keyboardModifiers)
end

function Keybind.formatKeyComboForDisplay(keyCombo)
  if not keyCombo or keyCombo == '' then
    return keyCombo
  end

  local text = tostring(keyCombo)
  text = text:gsub('MB2', 'Right')
  text = text:gsub('MB1', 'Left')
  text = text:gsub('MB3', 'Middle')
  return text
end

function Keybind.formatActionShortcut(category, action, chatMode, preset)
  local keys = Keybind.getKeybindKeys(category, action, chatMode, preset)
  local primary = keys and keys.primary
  if not primary or primary == '' then
    return nil
  end
  return string.format('(%s)', Keybind.formatKeyComboForDisplay(primary))
end

Keybind.controlButtonHotkeys = {
  cyclopediaButton = { 'Windows', 'Open Cyclopedia' },
  bestiaryTrackerButton = { 'Windows', 'Open Bestiary Tracker' },
  bosstiary = { 'Windows', 'Open Bosstiary' },
  bossSlot = { 'Windows', 'Open Boss Slots' },
  bosstiaryTrackerButton = { 'Windows', 'Open Bosstiary Tracker' },
  preyButton = { 'Dialogs', 'Open Prey Dialog' },
  preyTrackerButton = { 'Windows', 'Open Prey Tracker' },
  wheelButton = { 'Windows', 'Open Wheel of Destiny' },
  skillsButton = { 'Windows', 'Open Skills Window' },
  battleButton = { 'Windows', 'Open Battle List' },
  vipListButton = { 'Windows', 'Open VIP List' },
  questLogButton = { 'Windows', 'Open Quest Log' },
  questTrackerButton = { 'Windows', 'Open Quest Tracker' },
  forgeButton = { 'Windows', 'Open Exaltation Forge' },
  rewardWall = { 'Windows', 'Open Reward Wall' },
  spelllistButton = { 'Windows', 'Open Spell List' },
  analyzerButton = { 'Windows', 'Open Analyser Window' },
  imbuementTrackerButton = { 'Windows', 'Open Imbuement Tracker' },
  highscoresButton = { 'Windows', 'Open Highscore Dialog' },
  unjustifiedPointsButton = { 'Windows', 'Open Unjustified Points' },
  manageControlButtons = { 'UI', 'Manage Control Buttons' },
}

function Keybind.registerControlButtonHotkey(buttonId, category, action)
  Keybind.controlButtonHotkeys[buttonId] = { category, action }
end

function Keybind.stripHotkeySuffix(text)
  if not text or text == '' then
    return text
  end
  return text:gsub('%s*%b()$', '')
end

function Keybind.formatTooltipWithHotkey(baseText, category, action, chatMode, preset)
  if not baseText or baseText == '' then
    return baseText
  end

  local keys = Keybind.getKeybindKeys(category, action, chatMode, preset)
  local primary = keys and keys.primary
  if not primary or primary == '' then
    return baseText
  end

  return string.format('%s (%s)', baseText, Keybind.formatKeyComboForDisplay(primary))
end

local function findControlButton(buttonId)
  if modules.game_mainpanel and modules.game_mainpanel.getButton then
    local button = modules.game_mainpanel.getButton(buttonId)
    if button and not button:isDestroyed() then
      return button
    end
  end

  if modules.client_topmenu and modules.client_topmenu.getButton then
    local button = modules.client_topmenu.getButton(buttonId)
    if button and not button:isDestroyed() then
      return button
    end
  end

  return nil
end

function Keybind.applyControlButtonTooltip(button, buttonId)
  if not button or button:isDestroyed() then
    return
  end

  local hotkey = Keybind.controlButtonHotkeys[buttonId]
  if not hotkey then
    return
  end

  local base = button.hotkeyTooltipBase
  if not base or base == '' then
    if button.getTooltip then
      base = Keybind.stripHotkeySuffix(button:getTooltip() or '')
    end
  end

  if not base or base == '' then
    return
  end

  button.hotkeyTooltipBase = base
  button:setTooltip(Keybind.formatTooltipWithHotkey(base, hotkey[1], hotkey[2]))
end

function Keybind.syncToggleButtonTooltip(button, buttonId, openLabel, closeLabel)
  if not button or button:isDestroyed() then
    return
  end

  local on = button:isOn()
  button.hotkeyTooltipBase = tr(on and closeLabel or openLabel)
  Keybind.applyControlButtonTooltip(button, buttonId)
end

function Keybind.refreshControlButtonTooltips()
  if not g_game.isOnline() then
    return
  end

  for buttonId in pairs(Keybind.controlButtonHotkeys) do
    local button = findControlButton(buttonId)
    if button then
      Keybind.applyControlButtonTooltip(button, buttonId)
    end
  end
end

local function mouseKeyPressHandler(self, mousePos, rawButton)
  local combo = Keybind.getMouseKeyCombo(rawButton, g_keyboard.getModifiers())
  if combo then
    local callback = self.mouseKeyBindings and self.mouseKeyBindings[combo]
    if callback then
      return callback(self, translateMouseButton(rawButton))
    end
  end
  return false
end

-- Registers a callback for a mouse-button combo on a widget. Other mouse
-- presses (and unbound MB4/MB5) fall through to the remaining handlers.
function Keybind.bindMouseButtonKey(keyCombo, callback, widget)
  if not widget or not Keybind.isMouseKeyCombo(keyCombo) then
    return
  end
  keyCombo = tostring(keyCombo)
  if not widget.mouseKeyBindings then
    widget.mouseKeyBindings = {}
    connect(widget, { onMousePress = mouseKeyPressHandler })
  end
  widget.mouseKeyBindings[keyCombo] = callback
end

-- Removes a mouse-button binding; the widget hook is dropped once the last
-- binding is gone.
function Keybind.unbindMouseButtonKey(keyCombo, widget)
  if not widget or not widget.mouseKeyBindings then
    return
  end
  widget.mouseKeyBindings[tostring(keyCombo)] = nil
  if not next(widget.mouseKeyBindings) then
    disconnect(widget, { onMousePress = mouseKeyPressHandler })
    widget.mouseKeyBindings = nil
  end
end

-- Actions that fire on key-down instead of key-press.
local function isKeyDownAction(action)
  return action == HOTKEY_ACTION.EQUIP or action == HOTKEY_ACTION.USE or action == HOTKEY_ACTION.TEXT or action == HOTKEY_ACTION.TEXT_AUTO
end

local function bindHotkeyKey(keyCombo, action, callback, widget)
  if Keybind.isMouseKeyCombo(keyCombo) then
    Keybind.bindMouseButtonKey(keyCombo, callback, widget)
  elseif isKeyDownAction(action) then
    g_keyboard.bindKeyDown(keyCombo, callback, widget)
  else
    g_keyboard.bindKeyPress(keyCombo, callback, widget)
  end
end

local function unbindHotkeyKey(keyCombo, action, callback, widget)
  if Keybind.isMouseKeyCombo(keyCombo) then
    Keybind.unbindMouseButtonKey(keyCombo, widget)
  elseif isKeyDownAction(action) then
    g_keyboard.unbindKeyDown(keyCombo, callback, widget)
  else
    g_keyboard.unbindKeyPress(keyCombo, callback, widget)
  end
end

function Keybind.bindHotkey(hotkeyId, chatMode)
  if not chatMode or chatMode ~= Keybind.chatMode then
    return
  end

  if not modules.game_interface then
    return
  end

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]

  if not hotkey then
    return
  end

  local keys = {
    primary = hotkey.primary or '',
    secondary = hotkey.secondary or ''
  }
  local gameRootPanel = modules.game_interface.getRootPanel()
  local action = hotkey.action

  hotkey.callback = function() Keybind.hotkeyCallback(hotkeyId, chatMode) end

  for _, key in ipairs({ keys.primary, keys.secondary }) do
    if key then
      key = tostring(key)
      if key:len() > 0 then
        bindHotkeyKey(key, action, hotkey.callback, gameRootPanel)
      end
    end
  end
end

function Keybind.unbindHotkey(hotkeyId, chatMode)
  if not chatMode or chatMode ~= Keybind.chatMode then
    return
  end

  if not modules.game_interface then
    return
  end

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]

  if not hotkey then
    return
  end

  local keys = {
    primary = hotkey.primary or '',
    secondary = hotkey.secondary or ''
  }
  local gameRootPanel = modules.game_interface.getRootPanel()
  local action = hotkey.action

  for _, key in ipairs({ keys.primary, keys.secondary }) do
    if key then
      key = tostring(key)
      if key:len() > 0 then
        unbindHotkeyKey(key, action, hotkey.callback, gameRootPanel)
      end
    end
  end
end

function Keybind.syncChatModeUI(chatMode)
  if modules.client_options and modules.client_options.syncChatModePanels then
    modules.client_options.syncChatModePanels(chatMode)
  end

  if modules.game_console and modules.game_console.applyChatModeFromKeybind then
    modules.game_console.applyChatModeFromKeybind(chatMode)
  end

  Keybind.refreshControlButtonTooltips()
end

function Keybind.setChatMode(chatMode)
  local modeChanged = Keybind.chatMode ~= chatMode

  if not modeChanged then
    Keybind.syncChatModeUI(chatMode)
    return
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.unbind(keybind.category, keybind.action)
    end
  end

  for _, hotkey in ipairs(Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]) do
    Keybind.unbindHotkey(hotkey.hotkeyId, Keybind.chatMode)
  end

  if modules.game_walking then
    modules.game_walking.unbindTurnKeys()
  end

  Keybind.chatMode = chatMode

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.bind(keybind.category, keybind.action, keybind.callbacks, keybind.widget)
    end
  end

  for _, hotkey in ipairs(Keybind.hotkeys[chatMode][Keybind.currentPreset]) do
    Keybind.bindHotkey(hotkey.hotkeyId, chatMode)
  end

  if modules.game_walking then
    modules.game_walking.bindTurnKeys()
  end

  Keybind.syncChatModeUI(chatMode)
end
