local mouseGrabberWidget = nil
local chatModeGroup = nil
local spellWindow = nil
local objectWindow = nil
local textWindow = nil
local spellRadio = nil
local objectRadio = nil
local activeRow = nil
local customHotkeySearchEvent = nil

local ActionTexts = {
  [HOTKEY_ACTION.USE_YOURSELF] = "(use object on yourself)",
  [HOTKEY_ACTION.USE_CROSSHAIR] = "use object with crosshair",
  [HOTKEY_ACTION.USE_TARGET] = "(use object on target)",
  [HOTKEY_ACTION.EQUIP] = "(equip/unequip object)",
  [HOTKEY_ACTION.USE] = "(use object)",
  [HOTKEY_ACTION.SMART_CAST] = "(use object on cursor position)"
}

local ActionColors = {
  [HOTKEY_ACTION.USE_YOURSELF] = "#b0ffb0",
  [HOTKEY_ACTION.USE_CROSSHAIR] = "#c87d7d",
  [HOTKEY_ACTION.USE_TARGET] = "#ffb0b0",
  [HOTKEY_ACTION.EQUIP] = "#bfbf00",
  [HOTKEY_ACTION.USE] = "#b0b0ff",
  [HOTKEY_ACTION.TEXT] = "#dfdfdf",
  [HOTKEY_ACTION.TEXT_AUTO] = "#dfdfdf",
  [HOTKEY_ACTION.SPELL] = "#ffda34",
  [HOTKEY_ACTION.SMART_CAST] = "#e788fb"
}

local function isStringEmpty(text)
  return not text or tostring(text):trim():len() == 0
end

local function isCustomHotkeyConflict(keyCombo, currentHotkeyId)
  if isStringEmpty(keyCombo) then
    return false
  end

  local hotkeys = Keybind.hotkeys[Keybind.chatMode] and Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]
  if not hotkeys then
    return false
  end

  for _, hotkey in ipairs(hotkeys) do
    if hotkey.hotkeyId ~= currentHotkeyId and (hotkey.primary == keyCombo or hotkey.secondary == keyCombo) then
      return true
    end
  end

  return false
end

local function clearConflictingCustomHotkeys(keyCombo, currentHotkeyId)
  if isStringEmpty(keyCombo) then
    return
  end

  local hotkeys = Keybind.hotkeys[Keybind.chatMode] and Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]
  if not hotkeys then
    return
  end

  for _, hotkey in ipairs(hotkeys) do
    if hotkey.hotkeyId ~= currentHotkeyId and (hotkey.primary == keyCombo or hotkey.secondary == keyCombo) then
      local primary = hotkey.primary == keyCombo and "" or hotkey.primary
      local secondary = hotkey.secondary == keyCombo and "" or hotkey.secondary
      Keybind.editHotkeyKeys(hotkey.hotkeyId, primary, secondary, Keybind.chatMode)
    end
  end
end

local function clearConflictingActionbarHotkey(keyCombo)
  if isStringEmpty(keyCombo) then
    return
  end

  if modules.game_actionbar and modules.game_actionbar.removeHotkeyFromActionBar then
    modules.game_actionbar.removeHotkeyFromActionBar(keyCombo)
  end

  if modules.game_hotkeys and modules.game_hotkeys.removeHotkeyByCombo then
    modules.game_hotkeys.removeHotkeyByCombo(keyCombo)
  end
end

local function isActionbarHotkeyConflict(keyCombo)
  if isStringEmpty(keyCombo) then
    return false
  end

  if modules.game_hotkeys and modules.game_hotkeys.isHotkeyUsedByManager and modules.game_hotkeys.isHotkeyUsedByManager(keyCombo) then
    return true
  end

  local actionbarApi = modules.game_actionbar and modules.game_actionbar.ApiJson
  if actionbarApi and actionbarApi.hasCurrentHotkeySet and actionbarApi.hasCurrentHotkeySet() then
    local chatMode = modules.game_console and modules.game_console.isChatEnabled and modules.game_console.isChatEnabled() and 'chatOn' or 'chatOff'
    if actionbarApi.getHotkeyEntries then
      for _, data in ipairs(actionbarApi.getHotkeyEntries(chatMode)) do
        if data["actionsetting"] and data["keysequence"] and data["keysequence"]:lower() == keyCombo:lower() then
          return true
        end
      end
    end
  end

  return false
end

local function isDefaultKeybindConflict(keyCombo)
  if isStringEmpty(keyCombo) then
    return false
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, Keybind.chatMode, Keybind.currentPreset)
    if keys.primary == keyCombo or keys.secondary == keyCombo then
      return true
    end
  end

  return false
end

local function clearConflictingDefaultKeybinds(keyCombo)
  if isStringEmpty(keyCombo) then
    return
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, Keybind.chatMode, Keybind.currentPreset)
    if keys.primary == keyCombo then
      Keybind.setPrimaryActionKey(keybind.category, keybind.action, Keybind.currentPreset, "", Keybind.chatMode)
    end
    if keys.secondary == keyCombo then
      Keybind.setSecondaryActionKey(keybind.category, keybind.action, Keybind.currentPreset, "", Keybind.chatMode)
    end
  end
end

local function updateKeyEditConflictState(keyCombo, currentHotkeyId)
  local reserved = Keybind.reservedKeys[keyCombo]
  local used = reserved or isDefaultKeybindConflict(keyCombo) or isCustomHotkeyConflict(keyCombo, currentHotkeyId) or isActionbarHotkeyConflict(keyCombo)

  keyEditWindow.used:setVisible(used)
  if reserved then
    keyEditWindow.used:setText(tr("This hotkey is already in use and cannot be overwritten."))
  elseif used then
    keyEditWindow.used:setText(tr("This hotkey is already in use and will be overwritten."))
  end
  keyEditWindow.buttons.ok:setEnabled(not reserved)
end

local function editCustomHotkeyKey(row, secondary)
  local column = secondary and 5 or 3
  local otherColumn = secondary and 3 or 5
  keyEditWindow:setText(secondary and tr("Edit Secondary Key") or tr("Edit Primary Key"))
  keyEditWindow.info:setText(tr("Click 'Ok' to assign the keybind. Click 'Clear' to remove it."))
  keyEditWindow.alone:setVisible(false)
  keyEditWindow.used:setVisible(false)
  keyEditWindow.keyCombo:setText(row:getChildByIndex(column):getText())
  keyEditWindow.buttons.ok:setEnabled(true)

  local rowCaptureCallback = function(assignWindow, keyCode, keyboardModifiers, keyText)
    local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
    if keyCombo == "Shift" or keyCombo == "Ctrl" or keyCombo == "Alt" then
      keyCombo = ""
    end

    keyEditWindow.keyCombo:setText(keyCombo)
    updateKeyEditConflictState(keyCombo, row.hotkeyId)
    return true
  end

  local closeWindow = function()
    disconnect(keyEditWindow, { onKeyDown = rowCaptureCallback })
    keyEditWindow:hide()
    keyEditWindow:ungrabKeyboard()
    show()
  end

  connect(keyEditWindow, { onKeyDown = rowCaptureCallback })

  keyEditWindow.buttons.ok.onClick = function()
    local keyCombo = keyEditWindow.keyCombo:getText()
    if Keybind.reservedKeys[keyCombo] then
      return
    end

    clearConflictingCustomHotkeys(keyCombo, row.hotkeyId)
    clearConflictingDefaultKeybinds(keyCombo)
    clearConflictingActionbarHotkey(keyCombo)

    if secondary then
      Keybind.editHotkeyKeys(row.hotkeyId, row:getChildByIndex(otherColumn):getText(), keyCombo, Keybind.chatMode)
    else
      Keybind.editHotkeyKeys(row.hotkeyId, keyCombo, row:getChildByIndex(otherColumn):getText(), Keybind.chatMode)
    end

    closeWindow()
    updateCustomHotkeys()
  end

  keyEditWindow.buttons.clear.onClick = function()
    if secondary then
      Keybind.editHotkeyKeys(row.hotkeyId, row:getChildByIndex(otherColumn):getText(), "", Keybind.chatMode)
    else
      Keybind.editHotkeyKeys(row.hotkeyId, "", row:getChildByIndex(otherColumn):getText(), Keybind.chatMode)
    end

    closeWindow()
    updateCustomHotkeys()
  end

  keyEditWindow.buttons.cancel.onClick = closeWindow

  keyEditWindow:show()
  keyEditWindow:raise()
  keyEditWindow:focus()
  keyEditWindow:grabKeyboard()
  hide()
end

local function spellMatchesPlayerVocation(spellData, player)
  if not player or not spellData or not spellData.vocations then
    return true
  end

  local vocations = spellData.vocations
  if type(vocations) ~= 'table' then
    return true
  end

  local vocationId = player:getVocation()
  local vocationText = tostring(vocationId):lower()
  if translateVocation then
    vocationText = tostring(translateVocation(vocationId)):lower()
  end

  for _, vocation in pairs(vocations) do
    local value = tostring(vocation):lower()
    if value == vocationText or value == tostring(vocationId) or value == 'all' or value == 'none' then
      return true
    end
  end

  return false
end

local function getThingClassification(item)
  if item and item.getClassification then
    return item:getClassification()
  end

  return 0
end

local function showInvalidObjectMessage()
  if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
    modules.game_textmessage.displayFailureMessage(tr('Invalid object!'))
  else
    pwarning('Invalid object!')
  end
end

local function closeSpellDialog()
  if spellRadio then
    spellRadio:destroy()
    spellRadio = nil
  end
  if spellWindow and not spellWindow:isDestroyed() then
    spellWindow:destroy()
  end
  spellWindow = nil
end

local function closeObjectDialog()
  if objectRadio then
    objectRadio:destroy()
    objectRadio = nil
  end
  if objectWindow and not objectWindow:isDestroyed() then
    objectWindow:destroy()
  end
  objectWindow = nil
end

function init_custom_hotkeys()
  g_ui.importStyle('styles/controls/assign_spell')
  g_ui.importStyle('styles/controls/assign_object')
  g_ui.importStyle('styles/controls/assign_text')

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  mouseGrabberWidget.onMouseRelease = onChooseObjectMouseRelease

  chatModeGroup = UIRadioGroup.create()
  chatModeGroup:addWidget(panels.customHotkeys.panel.chatMode.on)
  chatModeGroup:addWidget(panels.customHotkeys.panel.chatMode.off)
  chatModeGroup.onSelectionChange = onCustomChatModeChange

  panels.customHotkeys.presets.add.onClick = addNewPreset
  panels.customHotkeys.presets.copy.onClick = copyPreset
  panels.customHotkeys.presets.rename.onClick = renamePreset
  panels.customHotkeys.presets.remove.onClick = removePreset

  panels.customHotkeys.presets.list.onOptionChange = function(comboBox, option)
    listKeybindsComboBox(option)
  end

  panels.customHotkeys.buttons.newAction.onClick = newCustomHotkeyAction
  panels.customHotkeys.buttons.reset.onClick = resetCustomHotkeys

  panels.customHotkeys.tablePanel.keybindsData.onMouseRelease = function(widget, pos, button)
    if button == MouseRightButton then
      newCustomHotkeyAction()
      return true
    end
  end

  panels.customHotkeys.search.field.onTextChange = searchCustomHotkeys
  panels.customHotkeys.search.clear.onClick = function()
    panels.customHotkeys.search.field:clearText()
  end

  -- Sync current preset combo
  for _, preset in ipairs(Keybind.presets) do
    panels.customHotkeys.presets.list:addOption(preset)
  end
  panels.customHotkeys.presets.list:setCurrentOption(Keybind.currentPreset)

  chatModeGroup:selectWidget(Keybind.chatMode == CHAT_MODE.ON and panels.customHotkeys.panel.chatMode.on or panels.customHotkeys.panel.chatMode.off)

  panels.customHotkeys.onVisibilityChange = function(widget, visible)
    if visible then
      updateCustomHotkeys()
    end
  end

  updateCustomHotkeys()
end

function terminate_custom_hotkeys()
  if customHotkeySearchEvent then
    removeEvent(customHotkeySearchEvent)
    customHotkeySearchEvent = nil
  end

  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end

  if chatModeGroup then
    chatModeGroup:destroy()
    chatModeGroup = nil
  end

  closeSpellDialog()
  closeObjectDialog()

  if textWindow then
    textWindow:destroy()
    textWindow = nil
  end
end

function onCustomChatModeChange()
  local mode = chatModeGroup:getSelectedWidget() == panels.customHotkeys.panel.chatMode.on and CHAT_MODE.ON or CHAT_MODE.OFF
  Keybind.setChatMode(mode)

  -- Sync general keybinds chat mode checkbox if possible
  if panels.keybindsPanel then
    if mode == CHAT_MODE.ON then
      panels.keybindsPanel.panel.chatMode.on:setChecked(true)
    else
      panels.keybindsPanel.panel.chatMode.off:setChecked(true)
    end
  end

  updateCustomHotkeys()
end

function updateCustomHotkeys()
  if not panels.customHotkeys or not panels.customHotkeys:isVisible() then
    return
  end

  panels.customHotkeys.tablePanel.keybinds:clearData()

  local chatMode = Keybind.chatMode
  local preset = Keybind.currentPreset

  if Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][preset] then
    for _, hotkey in ipairs(Keybind.hotkeys[chatMode][preset]) do
      addCustomHotkeyRow(hotkey.hotkeyId, hotkey.action, hotkey.data, hotkey.primary, hotkey.secondary)
    end
  end
end

function addCustomHotkeyRow(hotkeyId, action, data, primary, secondary)
  local isItem = (action <= 5 or action == HOTKEY_ACTION.SMART_CAST)
  local actionText = ""
  local color = ActionColors[action] or "#dfdfdf"

  if isItem then
    actionText = ActionTexts[action] or "(use object)"
  else
    if action == HOTKEY_ACTION.SPELL then
      actionText = data.words or ""
      if data.parameter and #data.parameter > 0 then
        actionText = actionText .. " " .. data.parameter
      end
    else
      actionText = data.text or ""
    end
    actionText = actionText:gsub("^%[Text%]%s*", ""):gsub("^%[Spell%]%s*", "")
  end

  local row = panels.customHotkeys.tablePanel.keybinds:addRow({ {
    style = 'EditableCustomHotkeysTableColumn',
    width = 286
  }, {
    style = 'VerticalSeparator'
  }, {
    style = 'EditableCustomKeysTableColumn',
    text = primary or "",
    width = 100
  }, {
    style = 'VerticalSeparator'
  }, {
    style = 'EditableCustomKeysTableColumn',
    text = secondary or "",
    width = 90
  } })

  row.hotkeyId = hotkeyId
  row.actionType = action
  row.hotkeyData = data

  local spellData = nil
  if not isItem then
    if action == HOTKEY_ACTION.SPELL then
      if data.words and #data.words > 0 then
        spellData = Spells.getSpellDataByParamWords(data.words:lower()) or Spells.getSpellDataByWords(data.words:lower())
      end
      if not spellData and data.id then
        spellData = Spells.getSpellDataById(data.id)
      end
    end
    if not spellData and actionText and #actionText > 0 then
      spellData = Spells.getSpellDataByParamWords(actionText:lower()) or Spells.getSpellDataByWords(actionText:lower())
    end
  end

  if spellData then
    color = "#ffda34"
  end

  local actionCol = row:getChildByIndex(1)
  actionCol:setText(actionText)
  actionCol:setColor(color)

  if isItem and data.itemId then
    actionCol.item:setItemId(data.itemId)
    if data.upgradeTier and data.upgradeTier > 0 and actionCol.item:getItem() then
      actionCol.item:getItem():setTier(data.upgradeTier)
    end
    actionCol.item:setVisible(true)
    -- Square border around the object, same color as the action text
    actionCol.item:setBorderWidth(1)
    actionCol.item:setBorderColor(color)
    if actionCol.spellIcon then
      actionCol.spellIcon:setVisible(false)
      actionCol.spellIcon:setBorderWidth(0)
      actionCol.spellIcon:setBorderColor('alpha')
    end
    actionCol:setTextOffset({ x = 28, y = 0 })
  elseif spellData and spellData.clientId then
    actionCol.item:setVisible(false)
    actionCol.item:setBorderWidth(0)
    actionCol.item:setBorderColor('alpha')
    if actionCol.spellIcon then
      local iconId = tonumber(spellData.clientId)
      local source = SpelllistSettings['Default'].iconFile
      local clip = Spells.getImageClip(iconId, 'Default')
      if SpellIcons and SpellIcons[spellData.name] and SpelllistSettings['Default'].iconsFolder and Spells.getImageClipNormal then
        source = SpelllistSettings['Default'].iconsFolder .. SpellIcons[spellData.name][1]
        clip = Spells.getImageClipNormal(SpellIcons[spellData.name][2])
      end
      actionCol.spellIcon:setImageSource(source)
      actionCol.spellIcon:setImageClip(clip)
      actionCol.spellIcon:setBorderWidth(1)
      actionCol.spellIcon:setBorderColor(color)
      actionCol.spellIcon:setVisible(true)
    end
    actionCol:setTextOffset({ x = 28, y = 0 })
  else
    actionCol.item:setVisible(false)
    actionCol.item:setBorderWidth(0)
    actionCol.item:setBorderColor('alpha')
    if actionCol.spellIcon then
      actionCol.spellIcon:setVisible(false)
      actionCol.spellIcon:setBorderWidth(0)
      actionCol.spellIcon:setBorderColor('alpha')
    end
    actionCol:setTextOffset({ x = 2, y = 0 })
  end

  actionCol.edit.onClick = function() editCustomHotkeyAction(row) end
  actionCol.onMouseRelease = function(widget, pos, button)
    if button == MouseRightButton then
      editCustomHotkeyAction(row)
      return true
    end
  end
  row:getChildByIndex(3).edit.onClick = function() editCustomHotkeyPrimary(row) end
  row:getChildByIndex(5).edit.onClick = function() editCustomHotkeySecondary(row) end
end

-- Key assignment
function editCustomHotkeyPrimary(row)
  editCustomHotkeyKey(row, false)
end

function editCustomHotkeySecondary(row)
  editCustomHotkeyKey(row, true)
end

-- New and editing actions
function newCustomHotkeyAction()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Assign Spell'), function() assignSpellDialog(nil) end)
  menu:addSeparator()
  menu:addOption(tr('Assign Object'), function() assignObjectDialogEvent(nil) end)
  menu:addSeparator()
  menu:addOption(tr('Assign Text'), function() assignTextDialog(nil) end)
  menu:display(g_window.getMousePosition())
end

function editCustomHotkeyAction(row)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  local isSpell = (row.actionType == HOTKEY_ACTION.SPELL)
  local isItem = (row.actionType <= 5 or row.actionType == HOTKEY_ACTION.SMART_CAST)
  local isText = (row.actionType == HOTKEY_ACTION.TEXT or row.actionType == HOTKEY_ACTION.TEXT_AUTO)

  menu:addOption(isSpell and tr('Edit Spell') or tr('Assign Spell'), function() assignSpellDialog(row) end)
  menu:addSeparator()
  if isItem and row.hotkeyData and row.hotkeyData.itemId then
    menu:addOption(tr('Edit Object'), function() assignObjectDialog(row, row.hotkeyData.itemId, row.hotkeyData.upgradeTier) end)
  else
    menu:addOption(tr('Assign Object'), function() assignObjectDialogEvent(row) end)
  end
  menu:addSeparator()
  menu:addOption(isText and tr('Edit Text') or tr('Assign Text'), function() assignTextDialog(row) end)
  menu:addSeparator()
  menu:addOption(tr('Clear Action'), function()
    Keybind.removeHotkey(row.hotkeyId, Keybind.chatMode)
    updateCustomHotkeys()
  end)
  menu:display(g_window.getMousePosition())
end

-- Spell Selection Window
function assignSpellDialog(row)
  closeSpellDialog()

  spellWindow = g_ui.createWidget('SpellMainWindow', g_ui.getRootWidget())
  local currentSpellWindow = spellWindow
  spellWindow.onDestroy = function()
    if spellWindow ~= currentSpellWindow then
      return
    end
    if spellRadio then
      spellRadio:destroy()
      spellRadio = nil
    end
    spellWindow = nil
  end
  spellWindow:show()
  spellWindow:raise()
  spellWindow:focus()
  controller.ui:hide()

  local okFunc = nil
  spellRadio = UIRadioGroup.create()
  local spells = modules.gamelib.SpellInfo['Default']
  local player = g_game.getLocalPlayer()

  for spellName, spellData in pairs(spells) do
    if not player then break end

    local widget = g_ui.createWidget('CustomHotkeySpellPreview', spellWindow.contentPanel.spellList)
    local iconId = tonumber(spellData.clientId)

    spellRadio:addWidget(widget)
    widget:setId(spellData.id)
    widget:setText(spellName.."\n"..spellData.words)
    widget.words = spellData.words
    widget.voc = spellData.vocations
    widget.param = spellData.parameter
    widget.spellLevel = spellData.level or 0
    widget.source = SpelllistSettings['Default'].iconFile
    widget.clip = Spells.getImageClip(iconId, 'Default')
    if SpellIcons and SpellIcons[spellName] and SpelllistSettings['Default'].iconsFolder and Spells.getImageClipNormal then
      widget.source = SpelllistSettings['Default'].iconsFolder .. SpellIcons[spellName][1]
      widget.clip = Spells.getImageClipNormal(SpellIcons[spellName][2])
    end
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if player:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    widget.onDoubleClick = function(self)
      spellRadio:selectWidget(self)
      if okFunc then
        okFunc()
      end
      return true
    end
  end

  local playerLevel = player and player:getLevel() or 0
  local playerVocation = player and player:getVocation() or 0
  local spellList = spellWindow.contentPanel.spellList
  local tickWidget = spellWindow.contentPanel.checkPanel.tick
  local filterVocationWidget = spellWindow.contentPanel.checkPanel.filterVocation
  local sortByLevelWidget = spellWindow.contentPanel.checkPanel.sortByLevel

  local function sortSpellWidgets()
    local sortByLevel = sortByLevelWidget and sortByLevelWidget:isChecked()
    Spells.sortSpellWidgets(spellList, sortByLevel)
  end

  local filterSpells = function()
    local search = spellWindow.contentPanel.searchText:getText()
    local filterLevel = tickWidget and tickWidget:isChecked()
    local filterVocation = filterVocationWidget and filterVocationWidget:isChecked()
    Spells.filterSpellWidgets(spellList, search, playerLevel, filterLevel, playerVocation, filterVocation)
    sortSpellWidgets()
  end
  spellWindow.contentPanel.searchText.onTextChange = filterSpells
  if tickWidget then
    tickWidget.onCheckChange = filterSpells
  end
  if filterVocationWidget then
    filterVocationWidget.onCheckChange = filterSpells
  end
  if sortByLevelWidget then
    sortByLevelWidget.onCheckChange = filterSpells
  end
  spellWindow.contentPanel.clearButton.onClick = function()
    spellWindow.contentPanel.searchText:clearText()
  end
  filterSpells()

  spellRadio.onSelectionChange = function(_, selected)
    if selected then
      spellWindow.contentPanel.preview:setText(selected:getText())
      spellWindow.contentPanel.preview.image:setImageSource(selected.source)
      spellWindow.contentPanel.preview.image:setImageClip(selected.clip)
      spellWindow.contentPanel.paramLabel:setOn(selected.param)
      spellWindow.contentPanel.paramText:setEnabled(selected.param)
      spellWindow.contentPanel.paramText:clearText()
      if selected.words and selected.words:lower():find("levitate") then
        spellWindow.contentPanel.paramText:setText("up|down")
      end
    end
  end

  if spellWindow.contentPanel.spellList:getChildCount() > 0 then
    spellRadio:selectWidget(spellWindow.contentPanel.spellList:getChildByIndex(1))
  end

  local function isEnterKey(keyCode)
    return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13 or (KeyNumpadEnter and keyCode == KeyNumpadEnter) or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
  end

  okFunc = function()
    local selected = spellRadio and spellRadio:getSelectedWidget()
    if not selected then return end

    local paramText = spellWindow.contentPanel.paramText:getText()
    local words = selected.words
    if paramText:lower():find("up|down") then
      paramText = ""
    end
    if (words .. " " .. paramText):find("utevo res ina") then
      words = "utevo res ina"
      paramText = paramText:gsub("ina ", "")
    end
    local spellData = { words = words, parameter = paramText }

    if row then
      Keybind.editHotkey(row.hotkeyId, HOTKEY_ACTION.SPELL, spellData, Keybind.chatMode)
    else
      Keybind.newHotkey(HOTKEY_ACTION.SPELL, spellData, "", "", Keybind.chatMode)
    end

    closeSpellDialog()
    controller.ui:show()
    updateCustomHotkeys()
  end

  local cancelFunc = function()
    closeSpellDialog()
    controller.ui:show()
  end

  if spellWindow.contentPanel.searchText then
    spellWindow.contentPanel.searchText.onKeyPress = function(widget, keyCode, keyboardModifiers)
      if isEnterKey(keyCode) then
        okFunc()
        return true
      elseif keyCode == KeyEscape then
        cancelFunc()
        return true
      end
      return false
    end
  end

  if spellWindow.contentPanel.paramText then
    spellWindow.contentPanel.paramText.onKeyPress = function(widget, keyCode, keyboardModifiers)
      if isEnterKey(keyCode) then
        okFunc()
        return true
      elseif keyCode == KeyEscape then
        cancelFunc()
        return true
      end
      return false
    end
  end

  spellWindow.contentPanel.buttonOk.onClick = okFunc
  spellWindow.contentPanel.buttonClose.onClick = cancelFunc
  spellWindow.onEnter = okFunc
  spellWindow.onEscape = cancelFunc
end

-- Object selection
function assignObjectDialogEvent(row)
  controller.ui:hide()
  activeRow = row
  mouseGrabberWidget:grabMouse()
  if modules.client_options and modules.client_options.getOption('nativeCursor') then
    g_window.setSystemCursor('cross')
  else
    g_mouse.pushCursor('target')
  end
end

function onChooseObjectMouseRelease(self, mousePosition, mouseButton)
  if mouseButton ~= MouseLeftButton then
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
      g_window.restoreMouseCursor()
    else
      g_mouse.popCursor('target')
    end
    self:ungrabMouse()
    controller.ui:show()
    return true
  end

  local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
  local itemId = 0
  local itemTier = 0
  if clickedWidget then
    if clickedWidget:getClassName() == 'UIGameMap' then
      local tile = clickedWidget:getTile(mousePosition)
      if tile then
        local thing = tile:getTopUseThing()
        if thing and thing:isItem() then
          itemId = thing:getId()
        end
      end
    elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
      local item = clickedWidget:getItem()
      itemId = item:getId()
      if item.getTier then
        itemTier = item:getTier()
      end
    end
  end

  if modules.client_options and modules.client_options.getOption('nativeCursor') then
    g_window.restoreMouseCursor()
  else
    g_mouse.popCursor('target')
  end
  self:ungrabMouse()

  if itemId == 0 then
    controller.ui:show()
    return true
  end

  local itemType = g_things.getThingType(itemId)
  if not itemType or not itemType:isPickupable() then
    controller.ui:show()
    showInvalidObjectMessage()
    return true
  end

  assignObjectDialog(activeRow, itemId, itemTier)
  return true
end

function assignObjectDialog(row, itemId, itemTier)
  closeObjectDialog()

  objectWindow = g_ui.createWidget('CustomObjectWindow', g_ui.getRootWidget())
  local currentObjectWindow = objectWindow
  objectWindow.onDestroy = function()
    if objectWindow ~= currentObjectWindow then
      return
    end
    if objectRadio then
      objectRadio:destroy()
      objectRadio = nil
    end
    objectWindow = nil
  end
  objectWindow:show()
  objectWindow:raise()
  objectWindow:focus()

  objectWindow.contentPanel.item:setItemId(itemId)
  if itemTier and itemTier > 0 and objectWindow.contentPanel.item:getItem() then
    objectWindow.contentPanel.item:getItem():setTier(itemTier)
  end

  itemTier = (itemTier and itemTier > 0) and itemTier or (row and row.hotkeyData and row.hotkeyData.upgradeTier or 0)
  objectWindow.contentPanel.tier:setVisible(itemTier > 0)
  if itemTier > 0 then
    objectWindow.contentPanel.tier:setImageClip(tostring(18 * (itemTier - 1)) .. " 0 18 16")
  end

  objectRadio = UIRadioGroup.create()
  local item = objectWindow.contentPanel.item:getItem()

  -- Smart mode checkbox visibility
  objectWindow.contentPanel.checks.smart:setVisible(false)
  objectWindow.contentPanel.checks.smart:setEnabled(false)
  objectWindow.contentPanel.checks.smart:setChecked(false)
  if item and item:getClothSlot() > 0 and item.hasExpireStop and item:hasExpireStop() then
    objectWindow.contentPanel.checks.smart:setVisible(true)
    if row and row.hotkeyData and row.hotkeyData.smartMode then
      objectWindow.contentPanel.checks.smart:setChecked(true)
    end
  end

  local okFunc = nil
  local function isEnterKey(keyCode)
    return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13 or (KeyNumpadEnter and keyCode == KeyNumpadEnter) or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
  end

  local cancelFunc = function()
    closeObjectDialog()
    controller.ui:show()
  end

  objectWindow.contentPanel.item.onDoubleClick = function()
    if okFunc then
      okFunc()
    end
    return true
  end

  local checks = {
    [1] = objectWindow.contentPanel.checks.UseOnYourself,
    [2] = objectWindow.contentPanel.checks.UseOnTarget,
    [3] = objectWindow.contentPanel.checks.UseAtCursorPosition,
    [4] = objectWindow.contentPanel.checks.SelectUseTarget,
    [5] = objectWindow.contentPanel.checks.Equip,
    [7] = objectWindow.contentPanel.checks.Use
  }

  for i, child in pairs(checks) do
    objectRadio:addWidget(child)
    child:setEnabled(false)

    child.onDoubleClick = function(self)
      if self:isEnabled() then
        objectRadio:selectWidget(self)
        if okFunc then
          okFunc()
        end
        return true
      end
    end

    child.onKeyPress = function(widget, keyCode, keyboardModifiers)
      if isEnterKey(keyCode) then
        if okFunc then
          okFunc()
        end
        return true
      elseif keyCode == KeyEscape then
        cancelFunc()
        return true
      end
      return false
    end

    if i <= 4 and item and item:isMultiUse() then
      child:setEnabled(true)
      if not objectRadio:getSelectedWidget() then
        objectRadio:selectWidget(child)
      end
    end

    if (i == 5 and item and item:getClothSlot() > 0) or (i == 5 and item and item:getClothSlot() == 0 and (getThingClassification(item) > 0 or item:isAmmo())) then
      child:setEnabled(true)
      if not objectRadio:getSelectedWidget() then
        objectRadio:selectWidget(child)
      end
    end

    if i == 7 and item and item:isUsable() and not item:isMultiUse() then
      child:setEnabled(true)
      if not objectRadio:getSelectedWidget() then
        objectRadio:selectWidget(child)
      end
    end

    child.onCheckChange = function(self)
      if self:getId() == "Equip" and not objectWindow.contentPanel.checks.smart:isEnabled() then
        objectWindow.contentPanel.checks.smart:setEnabled(true)
      elseif self:getId() ~= "Equip" and objectWindow.contentPanel.checks.smart:isEnabled() then
        objectWindow.contentPanel.checks.smart:setChecked(false)
        objectWindow.contentPanel.checks.smart:setEnabled(false)
      end
    end
  end

  if row and row.actionType then
    local childId = nil
    if row.actionType == HOTKEY_ACTION.USE_YOURSELF then childId = "UseOnYourself"
    elseif row.actionType == HOTKEY_ACTION.USE_TARGET then childId = "UseOnTarget"
    elseif row.actionType == HOTKEY_ACTION.SMART_CAST then childId = "UseAtCursorPosition"
    elseif row.actionType == HOTKEY_ACTION.USE_CROSSHAIR then childId = "SelectUseTarget"
    elseif row.actionType == HOTKEY_ACTION.EQUIP then childId = "Equip"
    elseif row.actionType == HOTKEY_ACTION.USE then childId = "Use"
    end
    if childId then
      local child = objectWindow.contentPanel.checks[childId]
      if child and child:isEnabled() then
        objectRadio:selectWidget(child)
      end
    end
  end

  okFunc = function()
    local selected = objectRadio and objectRadio:getSelectedWidget()
    if not selected then return end

    local actionType = HOTKEY_ACTION.USE
    local id = selected:getId()
    if id == "UseOnYourself" then actionType = HOTKEY_ACTION.USE_YOURSELF
    elseif id == "UseOnTarget" then actionType = HOTKEY_ACTION.USE_TARGET
    elseif id == "UseAtCursorPosition" then actionType = HOTKEY_ACTION.SMART_CAST
    elseif id == "SelectUseTarget" then actionType = HOTKEY_ACTION.USE_CROSSHAIR
    elseif id == "Equip" then actionType = HOTKEY_ACTION.EQUIP
    end

    local smartMode = false
    if objectWindow.contentPanel.checks.smart:isVisible() then
      smartMode = objectWindow.contentPanel.checks.smart:isChecked()
    end

    if item and getThingClassification(item) == 0 then
      itemTier = 0
    end

    local itemData = { itemId = itemId, upgradeTier = itemTier, smartMode = smartMode }

    if row then
      Keybind.editHotkey(row.hotkeyId, actionType, itemData, Keybind.chatMode)
    else
      Keybind.newHotkey(actionType, itemData, "", "", Keybind.chatMode)
    end

    closeObjectDialog()
    controller.ui:show()
    updateCustomHotkeys()
  end

  objectWindow.contentPanel.select.onClick = function()
    closeObjectDialog()
    assignObjectDialogEvent(row)
  end

  objectWindow.contentPanel.buttonOk.onClick = okFunc
  objectWindow.contentPanel.buttonClose.onClick = cancelFunc
  objectWindow.onEnter = okFunc
  objectWindow.onEscape = cancelFunc
  objectWindow.onKeyPress = function(widget, keyCode, keyboardModifiers)
    if isEnterKey(keyCode) then
      okFunc()
      return true
    elseif keyCode == KeyEscape then
      cancelFunc()
      return true
    end
    return false
  end
end

-- Text assignment
function assignTextDialog(row)
  if textWindow then
    local w = textWindow
    textWindow = nil
    w:destroy()
  end

  textWindow = g_ui.createWidget('CustomTextWindow', g_ui.getRootWidget())
  textWindow:show()
  textWindow:raise()
  textWindow:focus()
  controller.ui:hide()

  if row and (row.actionType == HOTKEY_ACTION.TEXT or row.actionType == HOTKEY_ACTION.TEXT_AUTO) then
    textWindow.contentPanel.text:setText(row.hotkeyData.text or "")
    textWindow.contentPanel.checkPanel.tick:setChecked(row.actionType == HOTKEY_ACTION.TEXT_AUTO)
  else
    textWindow.contentPanel.checkPanel.tick:setChecked(true)
  end

  local updateButtons = function()
    local enabled = not isStringEmpty(textWindow.contentPanel.text:getText())
    textWindow.contentPanel.buttonOk:setEnabled(enabled)
  end
  textWindow.contentPanel.text.onTextChange = updateButtons
  updateButtons()
  textWindow.contentPanel.text:focus()
  textWindow.contentPanel.text:setCursorPos(textWindow.contentPanel.text:getText():len())

  local okFunc = function()
    local text = textWindow.contentPanel.text:getText()
    if isStringEmpty(text) then
      return
    end

    if Spells and Spells.getSpellFormatedName then
      text = Spells.getSpellFormatedName(text)
    end

    local autoSay = textWindow.contentPanel.checkPanel.tick:isChecked()
    local actionType = autoSay and HOTKEY_ACTION.TEXT_AUTO or HOTKEY_ACTION.TEXT
    local textData = { text = text }

    if row then
      Keybind.editHotkey(row.hotkeyId, actionType, textData, Keybind.chatMode)
    else
      Keybind.newHotkey(actionType, textData, "", "", Keybind.chatMode)
    end

    textWindow:destroy()
    textWindow = nil
    controller.ui:show()
    updateCustomHotkeys()
  end

  local function isEnterKey(keyCode)
    return keyCode == KeyEnter or keyCode == KeyReturn or keyCode == 5 or keyCode == 13 or (KeyNumpadEnter and keyCode == KeyNumpadEnter) or (g_keyboard and g_keyboard.isEnterKey and g_keyboard.isEnterKey(keyCode))
  end

  textWindow.contentPanel.text.onKeyPress = function(widget, keyCode, keyboardModifiers)
    if isEnterKey(keyCode) then
      okFunc()
      return true
    elseif keyCode == KeyEscape then
      cancelFunc()
      return true
    end
    return false
  end

  textWindow.contentPanel.buttonOk.onClick = okFunc
  textWindow.contentPanel.buttonClose.onClick = cancelFunc
  textWindow.onEnter = okFunc
  textWindow.onEscape = cancelFunc
end

function searchCustomHotkeys()
  if customHotkeySearchEvent then
    removeEvent(customHotkeySearchEvent)
  end

  customHotkeySearchEvent = scheduleEvent(performCustomHotkeySearch, 50)
end

function performCustomHotkeySearch()
  local searchField = panels.customHotkeys.search.field
  local searchText = searchField:getText():trim():lower():gsub("%+", "%%+")
  local rows = panels.customHotkeys.tablePanel.keybinds.dataSpace:getChildren()

  if searchText:len() > 0 then
    for _, row in ipairs(rows) do
      row:hide()
    end
    for _, row in ipairs(rows) do
      local actionCol = row:getChildByIndex(1)
      local actionText = actionCol:getText():lower()
      local primary = row:getChildByIndex(3):getText():lower()
      local secondary = row:getChildByIndex(5):getText():lower()
      if actionText:find(searchText) or primary:find(searchText) or secondary:find(searchText) then
        row:show()
      end
    end
  else
    for _, row in ipairs(rows) do
      row:show()
    end
  end

  removeEvent(customHotkeySearchEvent)
  customHotkeySearchEvent = nil
end

function resetCustomHotkeys()
  Keybind.removeAllHotkeys(Keybind.chatMode)
  updateCustomHotkeys()
end
