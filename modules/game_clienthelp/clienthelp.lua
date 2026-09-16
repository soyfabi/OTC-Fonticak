local clientHelpActive = false
local helpPanel = nil
local helpHighlight = nil
local helpTitleLabel = nil
local helpBodyLabel = nil
local helpFooterLabel = nil
local lensHelpButton = nil
local currentHelpWidget = nil
local currentHelpEntry = nil
local currentHelpMode = nil
local mouseRootWidget = nil
local mouseHooksBound = false

local MAP_HIGHLIGHT_MIN_SIZE = 28

local function isHelpPanelWidget(widget)
  if not helpPanel or not widget then
    return false
  end

  if widget == helpPanel or widget == helpHighlight then
    return true
  end

  local parent = widget:getParent()
  while parent do
    if parent == helpPanel or parent == helpHighlight then
      return true
    end
    parent = parent:getParent()
  end

  return false
end

local function getHelpText(helpId)
  if helpId then
    return ClientHelpTexts[helpId]
  end
  return nil
end

local function findHelpEntry(widget)
  local current = widget
  while current and not current:isDestroyed() do
    local entry = getHelpText(current.clientHelpId)
    if entry then
      return entry, current
    end

    local id = current:getId()
    if id then
      entry = getHelpText(ClientHelpWidgetIds[id])
      if entry then
        return entry, current
      end
    end

    if current.getItem then
      local item = current:getItem()
      if item then
        entry = getHelpText(ClientHelpLockerShortcutIds[item:getId()])
        if entry then
          return entry, current
        end
      end
    end

    current = current:getParent()
  end

  return nil, nil
end

local function getWidgetAbsoluteRect(widget)
  if not widget or widget:isDestroyed() then
    return nil
  end

  local rect = widget:getRect()
  if not rect then
    return nil
  end

  local width = rect.width or widget:getWidth() or 0
  local height = rect.height or widget:getHeight() or 0
  if width <= 0 or height <= 0 then
    return nil
  end

  return {
    x = rect.x or 0,
    y = rect.y or 0,
    width = width,
    height = height
  }
end

local function widgetContainsMouse(widget, mousePos)
  if not widget or widget:isDestroyed() then
    return false
  end

  if widget:containsPoint(mousePos) then
    return true
  end

  local rect = getWidgetAbsoluteRect(widget)
  if not rect then
    return false
  end

  return mousePos.x >= rect.x and mousePos.x <= rect.x + rect.width
    and mousePos.y >= rect.y and mousePos.y <= rect.y + rect.height
end

local function hideHelpHighlight()
  if helpHighlight and not helpHighlight:isDestroyed() then
    helpHighlight:hide()
  end
end

local function hideHelpPanel()
  currentHelpWidget = nil
  currentHelpEntry = nil
  currentHelpMode = nil
  hideHelpHighlight()
  if helpPanel and not helpPanel:isDestroyed() then
    helpPanel:hide()
  end
end

local function setWidgetTreePhantom(widget)
  if not widget or widget:isDestroyed() then
    return
  end

  widget:setPhantom(true)
  for _, child in ipairs(widget:getChildren()) do
    setWidgetTreePhantom(child)
  end
end

local function syncLensHelpCursor()
  if not clientHelpActive then
    return
  end

  local lensHelpId = g_mouse.getCursorId('lenshelp')
  if not lensHelpId or lensHelpId < 0 then
    return
  end

  if not g_mouse.isCursorChanged() then
    g_mouse.pushCursor('lenshelp')
  else
    g_window.setMouseCursor(lensHelpId)
  end
end

local function showHelpHighlight(highlightRect)
  if not helpHighlight or helpHighlight:isDestroyed() or not highlightRect then
    hideHelpHighlight()
    return
  end

  helpHighlight:breakAnchors()
  helpHighlight:setRect(highlightRect)
  helpHighlight:show()
  helpHighlight:raise()

  if helpPanel and not helpPanel:isDestroyed() then
    helpPanel:raise()
  end
end

local function positionHelpPanel(anchorWidget, highlightRect)
  if not helpPanel or helpPanel:isDestroyed() or not anchorWidget or anchorWidget:isDestroyed() then
    return
  end

  helpTitleLabel:setWidth(250)
  helpBodyLabel:setWidth(250)
  helpTitleLabel:resizeToText()
  helpBodyLabel:resizeToText()

  local width = math.max(helpTitleLabel:getWidth(), helpBodyLabel:getWidth(), 220) + 16
  local height = helpTitleLabel:getHeight() + helpBodyLabel:getHeight()
    + (helpFooterLabel and helpFooterLabel:getHeight() or 16) + 24
  helpPanel:resize(width, height)

  local panelSize = helpPanel:getSize()
  local anchorRect = highlightRect or getWidgetAbsoluteRect(anchorWidget)
  if not anchorRect then
    return
  end

  local windowSize = g_window.getSize()
  local gap = 8
  local x
  local y

  if highlightRect then
    x = anchorRect.x + anchorRect.width + gap
    y = anchorRect.y + math.floor(anchorRect.height / 2) - math.floor(panelSize.height / 2)

    if x + panelSize.width > windowSize.width - 4 then
      x = anchorRect.x - panelSize.width - gap
    end
  else
    x = anchorRect.x - panelSize.width - gap
    if x < 4 then
      x = anchorRect.x + anchorRect.width + gap
    end
    if x + panelSize.width > windowSize.width - 4 then
      x = windowSize.width - panelSize.width - 4
    end

    y = anchorRect.y
  end

  if y + panelSize.height > windowSize.height - 4 then
    y = windowSize.height - panelSize.height - 4
  end
  if y < 4 then
    y = 4
  end

  helpPanel:breakAnchors()
  helpPanel:setPosition({ x = x, y = y })
  helpPanel:raise()
end

local function getMapObjectHighlightRect(map, mousePos)
  local mapRect = getWidgetAbsoluteRect(map)
  if not mapRect then
    return nil
  end

  local visibleDim = map:getVisibleDimension()
  local tileW = mapRect.width / math.max(visibleDim.width, 1)
  local tileH = mapRect.height / math.max(visibleDim.height, 1)
  local size = math.max(MAP_HIGHLIGHT_MIN_SIZE, math.min(tileW, tileH))

  return {
    x = math.floor(mousePos.x - size / 2),
    y = math.floor(mousePos.y - size / 2),
    width = math.floor(size),
    height = math.floor(size)
  }
end

local function getMapCreatureHelpEntry(creature)
  if not creature then
    return nil
  end

  if creature:isLocalPlayer() then
    return ClientHelpTexts.yourCharacter
  end
  if creature:isNpc() then
    return ClientHelpTexts.npcs
  end
  if creature:isPlayer() then
    return ClientHelpTexts.otherPlayers
  end
  if creature:isMonster() then
    return ClientHelpTexts.monsters
  end

  return nil
end

local function getGameMapPanel()
  if not modules.game_interface or not modules.game_interface.getGameMapPanel then
    return nil
  end

  local map = modules.game_interface.getGameMapPanel()
  if not map or map:isDestroyed() then
    return nil
  end

  return map
end

local function getMapCreatureUnderMouse(mousePos)
  local map = getGameMapPanel()
  if not map or not widgetContainsMouse(map, mousePos) then
    return nil, nil
  end

  local tile = map:getTile(mousePos)
  if not tile then
    return nil, nil
  end

  local offset = map:getPositionOffset(mousePos)
  local topCreature = tile:getTopCreatureEx(offset)
  if not topCreature then
    local collisionId = tile:getCollisionCreatureId()
    if collisionId and collisionId > 0 then
      topCreature = g_map.getCreatureById(collisionId)
    end
  end

  if not topCreature then
    return nil, nil
  end

  local entry = getMapCreatureHelpEntry(topCreature)
  if not entry then
    return nil, nil
  end

  return map, entry
end

local function isDepotLockerItem(item)
  return item and item.isItem and item:isItem()
    and ClientHelpDepotLockerWorldIds[item:getId()] == true
end

local function getMapDepotLockerUnderMouse(mousePos)
  local map = getGameMapPanel()
  if not map or not widgetContainsMouse(map, mousePos) then
    return nil, nil
  end

  local tile = map:getTile(mousePos)
  if not tile then
    return nil, nil
  end

  for _, item in ipairs(tile:getItems()) do
    if isDepotLockerItem(item) then
      return map, ClientHelpTexts.depotLocker
    end
  end

  if isDepotLockerItem(tile:getTopUseThing()) then
    return map, ClientHelpTexts.depotLocker
  end

  if isDepotLockerItem(tile:getTopLookThingEx(map:getPositionOffset(mousePos))) then
    return map, ClientHelpTexts.depotLocker
  end

  return nil, nil
end

local function showHelpPanel(entry, anchorWidget, highlightRect)
  if not helpPanel or not entry or not anchorWidget or anchorWidget:isDestroyed() then
    return
  end

  if highlightRect then
    showHelpHighlight(highlightRect)
    currentHelpMode = 'mapObject'
  else
    showHelpHighlight(getWidgetAbsoluteRect(anchorWidget))
    currentHelpMode = 'widget'
  end

  if currentHelpEntry == entry and currentHelpWidget == anchorWidget and helpPanel:isVisible() then
    positionHelpPanel(anchorWidget, highlightRect)
    syncLensHelpCursor()
    return
  end

  currentHelpEntry = entry
  currentHelpWidget = anchorWidget
  helpTitleLabel:setText(entry.title or '')
  helpBodyLabel:setText(entry.text or '')
  helpPanel:show()
  positionHelpPanel(anchorWidget, highlightRect)
  syncLensHelpCursor()
end

local function tryShowMapObjectHelp(mousePos)
  local map, entry = getMapCreatureUnderMouse(mousePos)
  if not map then
    map, entry = getMapDepotLockerUnderMouse(mousePos)
  end

  if not map or not entry then
    return false
  end

  showHelpPanel(entry, map, getMapObjectHighlightRect(map, mousePos))
  return true
end

local function updateHelpAtPosition(mousePos)
  if currentHelpWidget and currentHelpWidget:isDestroyed() then
    hideHelpPanel()
  end

  local root = mouseRootWidget or modules.game_interface.getRootPanel() or g_ui.getRootWidget()
  if not root then
    hideHelpPanel()
    return
  end

  if currentHelpMode == 'mapObject' and tryShowMapObjectHelp(mousePos) then
    return
  end

  if tryShowMapObjectHelp(mousePos) then
    return
  end

  local target = root:recursiveGetChildByPos(mousePos, false)
  if isHelpPanelWidget(target) then
    return
  end

  if target then
    local entry, anchorWidget = findHelpEntry(target)
    if entry and anchorWidget then
      showHelpPanel(entry, anchorWidget)
      return
    end
  end

  if currentHelpWidget and currentHelpEntry and currentHelpMode == 'widget'
      and not currentHelpWidget:isDestroyed()
      and widgetContainsMouse(currentHelpWidget, mousePos) then
    showHelpPanel(currentHelpEntry, currentHelpWidget)
    return
  end

  hideHelpPanel()
end

local function onClientHelpMouseMove(widget, mousePos, mouseMoved)
  if not clientHelpActive then
    return
  end

  updateHelpAtPosition(mousePos)
  syncLensHelpCursor()
end

local function isLensHelpToggleWidget(widget)
  while widget do
    local id = widget:getId()
    if id == 'lensHelpButton' or id == 'clientHelpBtn' then
      return true
    end
    widget = widget:getParent()
  end
  return false
end

local function onClientHelpMousePress(widget, mousePos, button)
  if not clientHelpActive then
    return false
  end

  if isHelpPanelWidget(widget) then
    return true
  end

  if isLensHelpToggleWidget(widget) then
    return false
  end

  updateHelpAtPosition(mousePos)
  return true
end

local function setupLensHelpButtonIcon(button)
  if not button or button:isDestroyed() then
    return
  end

  local icon = button:getChildById('lensHelpIcon')
  if not icon then
    icon = g_ui.createWidget('UIWidget', button)
    icon:setId('lensHelpIcon')
    icon:setPhantom(true)
    icon:setSize({ width = 20, height = 20 })
    icon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    icon:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  end

  icon:setImageSource('/images/ui/lenshelp_icon')
  icon:raise()
end

local function syncLensHelpButton()
  if lensHelpButton and not lensHelpButton:isDestroyed() then
    lensHelpButton:setOn(clientHelpActive)
  end
end

function isClientHelpActive()
  return clientHelpActive
end

function setClientHelpActive(active)
  active = active == true
  if clientHelpActive == active then
    syncLensHelpButton()
    return
  end

  clientHelpActive = active

  if g_tooltip.setClientHelpMode then
    g_tooltip.setClientHelpMode(active)
  end

  if active then
    g_mouse.pushCursor('lenshelp')
    syncLensHelpCursor()
    g_keyboard.bindKeyDown('Escape', deactivateClientHelp)
    hideHelpPanel()
  else
    g_mouse.popCursor('lenshelp')
    g_keyboard.unbindKeyDown('Escape', deactivateClientHelp)
    hideHelpPanel()
  end

  syncLensHelpButton()
end

function deactivateClientHelp()
  setClientHelpActive(false)
end

function toggleClientHelp()
  setClientHelpActive(not clientHelpActive)
end

function registerClientHelpWidget(widget, helpId)
  if not widget or not helpId then
    return
  end

  widget.clientHelpId = helpId
end

local function bindMouseHooks()
  if mouseHooksBound then
    return
  end

  mouseRootWidget = modules.game_interface.getRootPanel() or g_ui.getRootWidget()
  if not mouseRootWidget then
    return
  end

  connect(mouseRootWidget, {
    onMouseMove = onClientHelpMouseMove,
    onMousePress = onClientHelpMousePress
  })
  mouseHooksBound = true
end

local function unbindMouseHooks()
  if not mouseHooksBound or not mouseRootWidget then
    mouseRootWidget = nil
    mouseHooksBound = false
    return
  end

  disconnect(mouseRootWidget, {
    onMouseMove = onClientHelpMouseMove,
    onMousePress = onClientHelpMousePress
  })
  mouseRootWidget = nil
  mouseHooksBound = false
end

local function onGameStart()
  bindMouseHooks()
end

local function onGameEnd()
  setClientHelpActive(false)
  unbindMouseHooks()
end

function init()
  g_ui.importStyle('clienthelp')

  local rootWidget = g_ui.getRootWidget()
  helpHighlight = g_ui.createWidget('ClientHelpHighlight', rootWidget)
  helpHighlight:setBackgroundColor('#c0c0c066')
  helpHighlight:setBorderColor('#ffffff88')
  helpHighlight:setBorderWidth(1)
  helpHighlight:setPhantom(true)
  helpHighlight:breakAnchors()
  helpHighlight:hide()

  helpPanel = g_ui.createWidget('ClientHelpPanel', rootWidget)
  helpPanel:setBackgroundColor('#00000077')
  helpPanel:setBorderWidth(1)
  helpPanel:setBorderColor('#b0b0b0')
  setWidgetTreePhantom(helpPanel)
  helpTitleLabel = helpPanel:getChildById('helpTitle')
  helpBodyLabel = helpPanel:getChildById('helpBody')
  helpFooterLabel = helpPanel:getChildById('helpFooter')

  lensHelpButton = modules.game_mainpanel.addToggleButton(
    'lensHelpButton',
    tr('Client Help'),
    '/images/options/button_empty',
    toggleClientHelp,
    false,
    50
  )
  setupLensHelpButtonIcon(lensHelpButton)

  Keybind.new('UI', 'Show Lens Help', '', '')
  Keybind.bind('UI', 'Show Lens Help', {
    {
      type = KEY_DOWN,
      callback = toggleClientHelp
    }
  })

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  setClientHelpActive(false)
  unbindMouseHooks()

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  Keybind.delete('UI', 'Show Lens Help')

  if helpHighlight and not helpHighlight:isDestroyed() then
    helpHighlight:destroy()
  end

  if helpPanel and not helpPanel:isDestroyed() then
    helpPanel:destroy()
  end

  helpHighlight = nil
  helpPanel = nil
  helpTitleLabel = nil
  helpBodyLabel = nil
  helpFooterLabel = nil
  lensHelpButton = nil
  currentHelpWidget = nil
  currentHelpEntry = nil
  currentHelpMode = nil
end
