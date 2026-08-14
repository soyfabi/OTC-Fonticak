t_spelllist = nil

local spellListData = {}
local learnedSpells = {}
local spellListConfig = {}
local spelllistButton = nil
local selectedSpellWidget = nil
local info = nil
local searchFocusEvent = nil
local searchUi = {}
local configLoaded = false
local SETTINGS_NODE = 'game_spellist-filters'

local DEFAULT_CONFIG = {
  showAttackSpellGroup = true,
  showDruidSpells = true,
  showFreeSpells = true,
  showHealingSpellGroup = true,
  showKnightSpells = true,
  showOnlyCurrentLevel = false,
  showOnlyCurrentVocation = false,
  showPaladinSpells = true,
  showPremiumOnlySpells = true,
  showSorcererSpells = true,
  showMonkSpells = true,
  showSupportSpellGroup = true,
  showUnkownSpells = true,
  showRuneSpells = true,
  showInstantSpells = true
}

local VOCATION_OPTION_IDS = {
  showSorcererSpells = {1, 5},
  showDruidSpells = {2, 6},
  showPaladinSpells = {3, 7},
  showKnightSpells = {4, 8},
  showMonkSpells = {9, 10}
}

local function short_text(text, chars_limit)
  text = tostring(text or '')
  if #text <= chars_limit then
    return text
  end
  return text:sub(1, math.max(0, chars_limit - 3)) .. '...'
end

local function isRuneSpell(spell)
  if not spell then
    return false
  end
  if spell.type == 'Conjure' then
    return true
  end
  return tostring(spell.name or ''):lower():find('rune', 1, true) ~= nil
end

local function getSpellMagicType(spell)
  if not spell then
    return '-'
  end
  if spell.magicType and tostring(spell.magicType) ~= '' then
    return tostring(spell.magicType)
  end
  if spell.damagetype then
    local map = {
      DAMAGE_NONE = '-',
      DAMAGE_HIT = 'Physical',
      DAMAGE_PHYSICAL = 'Physical',
      DAMAGE_ENERGY = 'Energy',
      DAMAGE_EARTH = 'Earth',
      DAMAGE_EARTH_DOT = 'Earth',
      DAMAGE_FIRE = 'Fire',
      DAMAGE_FIRE_DOT = 'Fire',
      DAMAGE_DEATH = 'Death',
      DAMAGE_HOLY = 'Holy',
      DAMAGE_HOLY_DOT = 'Holy',
      DAMAGE_ICE = 'Ice',
      DAMAGE_HEALING = 'Healing'
    }
    return map[spell.damagetype] or '-'
  end

  local words = tostring(spell.words or ''):lower()
  local isHealingGroup = spell.group and spell.group[2] ~= nil
  if isHealingGroup or words:find('exura', 1, true) or words:find('adura', 1, true) then
    return 'Healing'
  end
  if words:find('flam', 1, true) then return 'Fire' end
  if words:find('frigo', 1, true) then return 'Ice' end
  if words:find('vis', 1, true) then return 'Energy' end
  if words:find('tera', 1, true) then return 'Earth' end
  if words:find('mort', 1, true) then return 'Death' end
  if words:find('san', 1, true) then return 'Holy' end
  if words:find('exori', 1, true) or words:find('exeta', 1, true) then return 'Physical' end
  return '-'
end

local function loadConfig()
  local saved = g_settings.getNode(SETTINGS_NODE)
  spellListConfig = {}
  for k, v in pairs(DEFAULT_CONFIG) do
    if saved and saved[k] ~= nil then
      spellListConfig[k] = saved[k]
    else
      spellListConfig[k] = v
    end
  end
  configLoaded = true
end

local function saveConfig()
  if configLoaded then
    g_settings.setNode(SETTINGS_NODE, spellListConfig)
  end
end

local function setButtonOn(state)
  if spelllistButton then
    spelllistButton:setOn(state)
  end
end

local function rebuildSpellListData()
  spellListData = {}
  local profile = SpellInfo and SpellInfo['Default']
  if not profile then
    return
  end
  for spellName, spell in pairs(profile) do
    local entry = {}
    for k, v in pairs(spell) do
      entry[k] = v
    end
    entry.name = spell.name or spellName
    spellListData[tostring(spell.clientId or spell.id or spellName)] = entry
  end
end

local function spellHasVocation(spell, vocationIds)
  if not spell.vocations then
    return false
  end
  for _, vocId in ipairs(vocationIds) do
    if table.contains(spell.vocations, vocId) then
      return true
    end
  end
  return false
end

local function getSpellIconClip(spell)
  local iconId = tonumber(spell.clientId)
  if not iconId then
    return '0 0 32 32'
  end
  return Spells.getImageClip(iconId, 'Default')
end

local function getSpellsPanel()
  if not t_spelllist then
    return nil
  end
  return t_spelllist:recursiveGetChildById('spellsPanel')
end

local function getSearchWidgets()
  if not t_spelllist then
    return nil, nil
  end
  return t_spelllist:recursiveGetChildById('searchText'), t_spelllist:recursiveGetChildById('clearSearch')
end

local function stopSearchFocusEvent()
  if searchFocusEvent then
    removeEvent(searchFocusEvent)
    searchFocusEvent = nil
  end
end

local function updateSearchCaret()
  local searchText = searchUi.text
  local caret = searchUi.caret
  local measure = searchUi.caretMeasure
  if not searchText or searchText:isDestroyed() or
      not caret or caret:isDestroyed() or
      not measure or measure:isDestroyed() then
    return
  end

  local text = searchText:getText() or ''
  local cursorPos = math.max(0, searchText:getCursorPos() or #text)
  measure:setText(text:sub(1, cursorPos))
  caret:setMarginLeft(3 + measure:getTextSize().width)
end

local function releaseSearchFocus()
  stopSearchFocusEvent()

  local searchText = searchUi.text
  if not searchText or searchText:isDestroyed() then
    return
  end

  searchText:ungrabKeyboard()
  if t_spelllist and searchText:isFocused() then
    t_spelllist:focusChild(nil, ActiveFocusReason)
  end
  searchText:setBorderWidth(1)
  searchText:setBorderColor('#000000')

  if searchUi.focusBorder then
    searchUi.focusBorder:hide()
  end
  if searchUi.caret then
    searchUi.caret:hide()
  end
end

local function startSearchFocusEvent()
  stopSearchFocusEvent()
  searchFocusEvent = cycleEvent(function()
    local searchText = searchUi.text
    if not t_spelllist or not searchText or searchText:isDestroyed() or not searchText:isVisible() then
      releaseSearchFocus()
      return
    end
    if g_mouse.isPressed(MouseLeftButton) and
        not searchText:containsPoint(g_window.getMousePosition()) then
      releaseSearchFocus()
      return
    end
    if searchUi.caret then
      searchUi.caret:setVisible(math.floor(g_clock.millis() / 333) % 2 == 0)
    end
  end, 20)
end

local function setupInfoLabels()
  info = {}
  local infoPanel = t_spelllist:getChildById('infoPanel')
  if not infoPanel then
    return
  end
  info.panel = infoPanel
  info.name = infoPanel:getChildById('spellName')

  local function bind(id, keyText)
    local entry = infoPanel:getChildById(id)
    if not entry then
      return
    end
    info[id] = entry
    local key = entry:getChildById('key')
    local value = entry:getChildById('value')
    if key then
      key:setText(keyText)
    end
    entry.key = key
    entry.value = value
  end

  bind('formula', 'Formula:')
  bind('vocation', 'Vocation:')
  bind('group', 'Group:')
  bind('type', 'Type:')
  bind('magicType', 'Magic Type:')
  bind('cooldown', 'Cooldown:')
  bind('mana', 'Mana/SP:')
  bind('minLevel', 'Min Level:')
  bind('premium', 'Premium:')
  bind('price', 'Price:')
end

local function setupSearch()
  local searchText, clearSearch = getSearchWidgets()
  searchUi = {
    text = searchText,
    clear = clearSearch,
    focusBorder = t_spelllist and t_spelllist:recursiveGetChildById('searchFocusBorder'),
    caret = t_spelllist and t_spelllist:recursiveGetChildById('searchCaret'),
    caretMeasure = t_spelllist and t_spelllist:recursiveGetChildById('searchCaretMeasure')
  }
  if searchText then
    t_spelllist:setFocusable(true)
    searchText:setFocusable(true)
    searchText:setChangeCursorImage(false)

    searchText.onTextChange = function()
      applySearchFilter()
      updateSearchCaret()
      if searchUi.caret then
        searchUi.caret:show()
      end
    end

    searchText.onFocusChange = function(widget, focused)
      widget:setBorderWidth(1)
      widget:setBorderColor(focused and '#ffffff' or '#000000')
      if searchUi.focusBorder then
        searchUi.focusBorder:setVisible(focused)
      end
      if searchUi.caret then
        searchUi.caret:setVisible(focused)
      end
      if focused then
        widget:setCursorVisible(true)
        widget:setCursorPos(-1)
        widget:blinkCursor()
        updateSearchCaret()
        widget:grabKeyboard()
        startSearchFocusEvent()
      else
        stopSearchFocusEvent()
        widget:ungrabKeyboard()
      end
    end
    searchText.onMousePress = function(widget, mousePos, button)
      if button == MouseLeftButton then
        widget:recursiveFocus(ActiveFocusReason)
        widget:setCursorVisible(true)
        widget:blinkCursor()
        widget:grabKeyboard()
        scheduleEvent(function()
          if widget and not widget:isDestroyed() then
            widget:recursiveFocus(MouseFocusReason)
            widget:setCursorVisible(true)
            widget:blinkCursor()
            updateSearchCaret()
          end
        end)
      end
      return false
    end
    searchText.onKeyPress = function()
      scheduleEvent(updateSearchCaret)
      return false
    end

    t_spelllist.onMousePress = function(widget, mousePos, button)
      if button == MouseLeftButton and not searchText:containsPoint(mousePos) then
        releaseSearchFocus()
      end
      return false
    end

    t_spelllist.onFocusChange = function(widget, focused)
      if not focused then
        releaseSearchFocus()
      end
    end
  end
  if clearSearch and searchText then
    clearSearch:setFocusable(false)
    clearSearch.onClick = function()
      searchText:clearText()
      searchText:recursiveFocus(ActiveFocusReason)
      searchText:grabKeyboard()
    end
  end
end

local function hideUnusedMiniWindowButtons()
  for _, buttonId in ipairs({ 'toggleFilterButton', 'contextMenuButton', 'newWindowButton', 'lockButton' }) do
    local button = t_spelllist:getChildById(buttonId)
    if button then
      button:hide()
    end
  end
end

function init()
  t_spelllist = g_ui.loadUI('game_spellist')
  if not t_spelllist then
    perror('Failed to load Spell List UI')
    return
  end

  t_spelllist:setFocusable(true)
  t_spelllist:setContentMinimumHeight(205)
  t_spelllist:setup()
  t_spelllist:hide()

  hideUnusedMiniWindowButtons()

  local scrollbar = t_spelllist:getChildById('miniwindowScrollBar')
  if scrollbar then
    scrollbar:addAnchor(AnchorBottom, 'infoPanel', AnchorTop)
  end

  setupInfoLabels()
  setupSearch()

  t_spelllist.onMinimize = function()
    if info and info.panel then
      info.panel:hide()
      info.panel:setPhantom(true)
    end
    local searchText, clearSearch = getSearchWidgets()
    if searchText then searchText:hide() end
    if clearSearch then clearSearch:hide() end
  end
  t_spelllist.onMaximize = function()
    if info and info.panel then
      info.panel:show()
      info.panel:setPhantom(true)
    end
    local searchText, clearSearch = getSearchWidgets()
    if searchText then searchText:show() end
    if clearSearch then clearSearch:show() end
  end

  Keybind.new('Windows', 'Show/hide spell list', 'Alt+L', '')
  Keybind.bind('Windows', 'Show/hide spell list', {
    { type = KEY_DOWN, callback = toggle }
  })

  connect(g_game, { onGameStart = online, onGameEnd = offline })
  connect(LocalPlayer, { onSpellsChange = onSpellsChange, onLevelChange = onLevelChange })

  if g_game.isOnline() then
    online()
    if t_spelllist.setupOnStart then
      t_spelllist:setupOnStart()
    end
  end
end

function terminate()
  disconnect(g_game, { onGameStart = online, onGameEnd = offline })
  disconnect(LocalPlayer, { onSpellsChange = onSpellsChange, onLevelChange = onLevelChange })
  Keybind.delete('Windows', 'Show/hide spell list')
  saveConfig()
  releaseSearchFocus()
  if t_spelllist then
    t_spelllist:destroy()
    t_spelllist = nil
  end
  if spelllistButton then
    spelllistButton:destroy()
  end
  spelllistButton = nil
  spellListData = {}
  learnedSpells = {}
  spellListConfig = {}
  configLoaded = false
  selectedSpellWidget = nil
  info = nil
  searchUi = {}
end

function toggle()
  if not t_spelllist then
    return
  end
  if spelllistButton and spelllistButton:isOn() then
    t_spelllist:close()
    setButtonOn(false)
    return
  end
  if not t_spelllist:getParent() then
    local panel = modules.game_interface.findContentPanelAvailable(t_spelllist, t_spelllist:getMinimumHeight())
    if not panel then
      return
    end
    panel:addChild(t_spelllist)
  end
  t_spelllist:open()
  setButtonOn(true)
  onConfigureList()
end

function online()
  loadConfig()
  rebuildSpellListData()
  if not spelllistButton and g_game.getFeature(GameSpellList)
      and modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
    spelllistButton = modules.game_mainpanel.addToggleButton(
      'spelllistButton',
      tr('Spell List') .. ' (Alt+L)',
      '/modules/game_spellist/images/button_spells',
      toggle,
      false,
      4
    )
    if spelllistButton then
      spelllistButton:setOn(false)
    end
  end
  if t_spelllist and t_spelllist.setupOnStart then
    t_spelllist:setupOnStart()
  end
  if t_spelllist and t_spelllist:isVisible() and not t_spelllist:getParent() then
    local panel = modules.game_interface.findContentPanelAvailable(t_spelllist, t_spelllist:getMinimumHeight())
    if panel then
      panel:addChild(t_spelllist)
    end
  end
  setButtonOn(t_spelllist and t_spelllist:isVisible())
  onConfigureList()
end

function offline()
  saveConfig()
  releaseSearchFocus()
  spellListData = {}
  learnedSpells = {}
  selectedSpellWidget = nil
  if t_spelllist then
    -- Logout must not persist closed=true, or the list never reopens.
    t_spelllist:close(true)
  end
  setButtonOn(false)
end

function onMiniWindowClose()
  releaseSearchFocus()
  setButtonOn(false)
end

function onMiniWindowOpen()
  setButtonOn(true)
end

function getSpellListData()
  return spellListData
end

function onSpellsChange(player, list)
  learnedSpells = {}
  if list then
    for _, spellId in pairs(list) do
      learnedSpells[tostring(spellId)] = true
    end
  end
  onConfigureList()
end

function onUpdateSpellListLevel()
  local player = g_game.getLocalPlayer()
  local panel = getSpellsPanel()
  if not player or not panel then
    return
  end
  for _, widget in pairs(panel:getChildren()) do
    local gray = widget:getChildById('gray')
    if gray and widget.spellData then
      gray:setVisible(player:getLevel() < (widget.spellData.level or 0))
    end
  end
end

function applySearchFilter()
  local panel = getSpellsPanel()
  local searchText = t_spelllist and t_spelllist:recursiveGetChildById('searchText')
  if not panel then
    return
  end
  local search = searchText and searchText:getText():trim():lower() or ''
  for _, child in ipairs(panel:getChildren()) do
    if child.spellData then
      local haystack = (tostring(child.spellData.name or '') .. ' ' .. tostring(child.spellData.words or '')):lower()
      child:setVisible(search:len() == 0 or haystack:find(search, 1, true) ~= nil)
    end
  end
end

function onConfigureList()
  if not t_spelllist then
    return
  end
  local player = g_game.getLocalPlayer()
  local panel = getSpellsPanel()
  if not panel then
    return
  end

  selectedSpellWidget = nil
  panel:destroyChildren()

  local sorted = {}
  for _, spell in pairs(spellListData) do
    if matchFilter(spell) then
      table.insert(sorted, spell)
    end
  end
  table.sort(sorted, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)

  local iconSource = SpelllistSettings['Default'].iconFile
  for _, spell in ipairs(sorted) do
    local widget = g_ui.createWidget('TibiaSpellListEntry', panel)
    widget.spellData = spell
    widget:setFocusable(false)
    widget:setBorderWidth(0)
    widget:setBackgroundColor('alpha')

    local icon = widget:getChildById('icon')
    local name = widget:getChildById('name')
    local words = widget:getChildById('words')
    local gray = widget:getChildById('gray')
    local clip = getSpellIconClip(spell)

    if icon then
      icon:setImageSource(iconSource)
      icon:setImageClip(clip)
    end
    if name then
      name:setText(short_text(spell.name, 16))
      if #tostring(spell.name) > 16 then
        name:setTooltip(spell.name)
      end
    end
    if words then
      words:setText(short_text(spell.words, 18))
      if #tostring(spell.words or '') > 18 then
        words:setTooltip(spell.words)
      end
    end
    if gray and player then
      gray:setVisible(player:getLevel() < (spell.level or 0))
    end

    widget.onClick = function()
      selectSpellWidget(widget)
    end
  end

  applySearchFilter()

  for _, child in ipairs(panel:getChildren()) do
    if child:isVisible() then
      selectSpellWidget(child)
      break
    end
  end
end

function selectSpellWidget(widget)
  if not widget or not widget.spellData then
    return
  end
  if selectedSpellWidget and selectedSpellWidget ~= widget and not selectedSpellWidget:isDestroyed() then
    selectedSpellWidget:setBackgroundColor('alpha')
    local oldName = selectedSpellWidget:getChildById('name')
    local oldWords = selectedSpellWidget:getChildById('words')
    if oldName then oldName:setColor('#c0c0c0') end
    if oldWords then oldWords:setColor('#c0c0c0') end
  end

  selectedSpellWidget = widget
  widget:setBackgroundColor('#585858')
  widget:setBorderWidth(0)
  local name = widget:getChildById('name')
  local words = widget:getChildById('words')
  if name then name:setColor('#f4f4f4') end
  if words then words:setColor('#f4f4f4') end
  updateSpellDetails(widget.spellData)
end

function updateSpellDetails(data)
  if not data or not info then
    return
  end
  if info.name then
    info.name:setText(data.name or '')
  end
  local function setValue(entry, text, tooltip)
    if entry and entry.value then
      entry.value:setText(tostring(text or '-'))
      entry.value:setTooltip(tooltip or '')
    end
  end

  setValue(info.formula, data.words or '-')

  local vocationDesc = ''
  if data.vocations then
    for _, v in pairs(data.vocations) do
      local vocName = VocationNames and VocationNames[v]
      if vocName then
        vocationDesc = vocationDesc .. vocName .. ', '
      end
    end
    vocationDesc = string.sub(vocationDesc, 1, -3)
    if #data.vocations >= 8 then
      vocationDesc = 'All'
    end
  end
  if vocationDesc == '' then
    vocationDesc = '-'
  end
  setValue(info.vocation, short_text(vocationDesc, 12), #vocationDesc > 12 and vocationDesc or '')

  local groupDesc = ''
  if data.group then
    for i, _ in pairs(data.group) do
      if SpellGroups and SpellGroups[i] then
        groupDesc = groupDesc .. SpellGroups[i] .. ', '
      end
    end
    groupDesc = string.sub(groupDesc, 1, -3)
  end
  setValue(info.group, groupDesc ~= '' and groupDesc or '-')
  setValue(info.type, data.type or '-')
  setValue(info.magicType, getSpellMagicType(data))

  local cooldownTime = (data.exhaustion or 0) / 1000
  local cooldownDesc = (cooldownTime > 60 and (cooldownTime / 60) .. 'min' or cooldownTime .. 's')
  if data.group then
    for _, v in pairs(data.group) do
      cooldownDesc = cooldownDesc .. ' / ' .. (v / 1000) .. 's'
    end
  end
  setValue(info.cooldown, short_text(cooldownDesc, 14), #cooldownDesc > 14 and cooldownDesc or '')
  setValue(info.mana, tr('%s / %s', data.mana or 0, data.soul or 0))
  setValue(info.minLevel, data.level or 0)
  setValue(info.premium, data.premium and tr('Yes') or tr('No'))
  setValue(info.price, data.price or 0)
end

function onExtraMenu()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  local function addCheck(text, option)
    menu:addCheckBox(text, getSpellOption(option), function(_, checked)
      setSpellOption(option, checked)
      onConfigureList()
    end)
  end
  addCheck('Character Vocation', 'showOnlyCurrentVocation')
  addCheck('Character Level', 'showOnlyCurrentLevel')
  addCheck('Learnt Spells', 'showUnkownSpells')
  menu:addSeparator()
  addCheck('Druid', 'showDruidSpells')
  addCheck('Knight', 'showKnightSpells')
  addCheck('Paladin', 'showPaladinSpells')
  addCheck('Sorcerer', 'showSorcererSpells')
  addCheck('Monk', 'showMonkSpells')
  menu:addCheckBox('All Vocations', canCheckAllVocations(), function()
    checkAllVocations()
    onConfigureList()
  end)
  menu:addSeparator()
  addCheck('Attack', 'showAttackSpellGroup')
  addCheck('Healing', 'showHealingSpellGroup')
  addCheck('Support', 'showSupportSpellGroup')
  menu:addCheckBox('All Spell Groups', canCheckAllGroups(), function()
    checkAllGroups()
    onConfigureList()
  end)
  menu:addSeparator()
  addCheck('Premium Account', 'showPremiumOnlySpells')
  addCheck('Free Account', 'showFreeSpells')
  menu:addSeparator()
  addCheck('Rune Spells', 'showRuneSpells')
  addCheck('Instant Spells', 'showInstantSpells')
  menu:display(g_window.getMousePosition())
  return true
end

function matchFilter(spell)
  local player = g_game.getLocalPlayer()
  if not player then
    return true
  end
  if getSpellOption('showOnlyCurrentVocation') then
    if spell.vocations and not table.contains(spell.vocations, player:getVocation()) then
      return false
    end
  end
  if getSpellOption('showOnlyCurrentLevel') and player:getLevel() < (spell.level or 0) then
    return false
  end
  if not getSpellOption('showUnkownSpells') then
    local id = tostring(spell.clientId or spell.id or '')
    if id ~= '' and not learnedSpells[id] and next(learnedSpells) ~= nil then
      return false
    end
  end
  if not canCheckAllVocations() then
    local matchesEnabled = false
    for option, ids in pairs(VOCATION_OPTION_IDS) do
      if getSpellOption(option) and spellHasVocation(spell, ids) then
        matchesEnabled = true
        break
      end
    end
    if not matchesEnabled then
      return false
    end
  end
  if not canCheckAllGroups() and spell.group then
    local groupOptions = {
      {name = 'showAttackSpellGroup', type = 'Attack'},
      {name = 'showHealingSpellGroup', type = 'Healing'},
      {name = 'showSupportSpellGroup', type = 'Support'}
    }
    local matchesEnabled = false
    for _, k in pairs(groupOptions) do
      if getSpellOption(k.name) then
        for i, _ in pairs(spell.group) do
          if SpellGroups and SpellGroups[i] == k.type then
            matchesEnabled = true
            break
          end
        end
      end
      if matchesEnabled then break end
    end
    if not matchesEnabled then
      return false
    end
  end
  if spell.premium then
    if not getSpellOption('showPremiumOnlySpells') then return false end
  else
    if not getSpellOption('showFreeSpells') then return false end
  end
  local rune = isRuneSpell(spell)
  if rune and not getSpellOption('showRuneSpells') then return false end
  if not rune and not getSpellOption('showInstantSpells') then return false end
  return true
end

function setSpellOption(option, value)
  spellListConfig[option] = value
  saveConfig()
end

function getSpellOption(option)
  return spellListConfig[option]
end

function canCheckAllVocations()
  return getSpellOption('showDruidSpells') and getSpellOption('showKnightSpells')
    and getSpellOption('showPaladinSpells') and getSpellOption('showSorcererSpells')
    and getSpellOption('showMonkSpells')
end

function canCheckAllGroups()
  return getSpellOption('showAttackSpellGroup') and getSpellOption('showHealingSpellGroup')
    and getSpellOption('showSupportSpellGroup')
end

function checkAllVocations()
  local canCheck = not canCheckAllVocations()
  setSpellOption('showDruidSpells', canCheck)
  setSpellOption('showKnightSpells', canCheck)
  setSpellOption('showPaladinSpells', canCheck)
  setSpellOption('showSorcererSpells', canCheck)
  setSpellOption('showMonkSpells', canCheck)
end

function checkAllGroups()
  local canCheck = not canCheckAllGroups()
  setSpellOption('showAttackSpellGroup', canCheck)
  setSpellOption('showHealingSpellGroup', canCheck)
  setSpellOption('showSupportSpellGroup', canCheck)
end

function onLevelChange(localPlayer, level, levelPercent, oldLevel, oldLevelPercent)
  if level ~= oldLevel then
    onUpdateSpellListLevel()
    if getSpellOption('showOnlyCurrentLevel') then
      onConfigureList()
    end
  end
end
