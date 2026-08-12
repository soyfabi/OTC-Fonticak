if not g_client.setInputLockWidget then
  g_client.setInputLockWidget = function(...) end
end

if UICreature and not UICreature.isColoredMount then
  function UICreature:isColoredMount()
    local creature = self:getCreature()
    if not creature then return false end
    local mountId = creature:getOutfit().mount
    if mountId and mountId > 0 then
      local thingType = g_things.getThingType(mountId, ThingCategoryCreature)
      return thingType and thingType:getLayers() > 1
    end
    return false
  end
end

if UICreature then
  if not UICreature.getOutfit then
    function UICreature:getOutfit()
      local creature = self:getCreature()
      if creature then
        return creature:getOutfit()
      end
      return {}
    end
  end
  if not UICreature.setAnimate then
    function UICreature:setAnimate(animate)
      local creature = self:getCreature()
      if creature then
        creature:setAnimate(animate)
      end
    end
  end
  if not UICreature.setIdleAnimate then
    function UICreature:setIdleAnimate(animate)
      local creature = self:getCreature()
      if creature then
        creature:setAnimate(animate)
      end
    end
  end
  if not UICreature.setStaticWalking then
    function UICreature:setStaticWalking(speed)
      local creature = self:getCreature()
      if creature then
        local walkingSpeed = speed
        if type(speed) == "boolean" then
          walkingSpeed = speed and 1000 or 0
        end
        creature:setStaticWalking(walkingSpeed)
      end
    end
  end
end

if UIWidget then
  if not UIWidget.isTextWraped then
    function UIWidget:isTextWraped()
      if not self.getWrappedLinesCount then return false end
      return self:getWrappedLinesCount() > 1
    end
  end
  if not UIWidget.getActionId then
    function UIWidget:getActionId()
      return self.actionId or 0
    end
    function UIWidget:setActionId(id)
      self.actionId = id
    end
  end
end

local window = nil

local appearanceGroup = nil
local colorModeGroup = nil
local colorBoxGroup = nil

local movementCheck = nil
local showFloorCheck = nil
local showOutfitCheck = nil
local showMountCheck = nil
local showAuraCheck = nil
local auraCheck = nil

local previewCreature = nil
local previewFamiliar = nil
local familiarPreviewShown = false
local familiarPreviewAnim = {}

local FAMILIAR_SHIFT_MARGIN = 63
local FAMILIAR_MARGIN_LEFT_HIDDEN = 28
local FAMILIAR_MARGIN_LEFT_SHOWN = 47
local FAMILIAR_ANIM_MS = 280
local PREVIEW_TRANSITION_MS = 280
local CREATURE_MARGIN_TOP_DEFAULT = -30

local suppressPreviewTransition = false
local previewTransitionAnim = {}

local tempOutfit = {}

local pendingSelectionFill = nil
local selectionFillToken = 0
local selectionLoadingAnim = nil
local activeSelectionQueue = nil
local SELECTION_BATCH_SIZE = 24
local SELECTION_BATCH_DELAY_MS = 1
local SELECTION_LOADING_ANIM_MS = 280
local SELECTION_LOADING_FRAMES = { '.', '..', '...' }

local pendingColorFill = nil
local pendingColorDebounce = nil
local colorFillToken = 0
local COLOR_BATCH_SIZE = 24
local COLOR_BATCH_DELAY_MS = 1
local COLOR_DEBOUNCE_MS = 30

local pendingSearchRebuild = nil
local SEARCH_DEBOUNCE_MS = 120

local function cancelPendingSearchRebuild()
  if pendingSearchRebuild then
    removeEvent(pendingSearchRebuild)
    pendingSearchRebuild = nil
  end
end

local function cancelSelectionLoadingAnim()
  if selectionLoadingAnim then
    removeEvent(selectionLoadingAnim)
    selectionLoadingAnim = nil
  end
end

local function cancelPendingColorFill()
  if pendingColorDebounce then
    removeEvent(pendingColorDebounce)
    pendingColorDebounce = nil
  end
  if pendingColorFill then
    removeEvent(pendingColorFill)
    pendingColorFill = nil
  end
  colorFillToken = colorFillToken + 1
end

local function cancelPendingSelectionFill()
  if pendingSelectionFill then
    removeEvent(pendingSelectionFill)
    pendingSelectionFill = nil
  end
  selectionFillToken = selectionFillToken + 1
  activeSelectionQueue = nil
  cancelSelectionLoadingAnim()
  cancelPendingColorFill()
  cancelPendingSearchRebuild()
end

local function startSelectionLoadingAnim()
  if selectionLoadingAnim then
    return
  end

  local frame = 1
  local function tick()
    selectionLoadingAnim = nil
    if not window or window:isDestroyed() or not activeSelectionQueue then
      return
    end

    local text = SELECTION_LOADING_FRAMES[frame]
    frame = frame % #SELECTION_LOADING_FRAMES + 1

    local queue = activeSelectionQueue
    local hasPending = false
    for i = queue.index, #queue.items do
      local button = queue.items[i].button
      local loading = button and not button:isDestroyed() and button.loading
      if loading and not loading:isDestroyed() then
        loading:setText(text)
        hasPending = true
      end
    end

    if hasPending then
      selectionLoadingAnim = scheduleEvent(tick, SELECTION_LOADING_ANIM_MS)
    end
  end

  selectionLoadingAnim = scheduleEvent(tick, SELECTION_LOADING_ANIM_MS)
end

local function markSelectionButtonLoading(button)
  if not button then
    return
  end
  button.appliedOutfit = nil
  if button.outfit and not button.outfit:isDestroyed() then
    button.outfit:hide()
  end
  if button.loading and not button.loading:isDestroyed() then
    button.loading:setText(SELECTION_LOADING_FRAMES[1])
    button.loading:show()
  end
end

local function markSelectionButtonReady(button)
  if not button then
    return
  end
  if button.loading and not button.loading:isDestroyed() then
    button.loading:hide()
  end
  if button.outfit and not button.outfit:isDestroyed() then
    button.outfit:show()
  end
end

local function fillSelectionBatch(queue, token)
  pendingSelectionFill = nil
  if token ~= selectionFillToken or not window or window:isDestroyed() then
    return
  end

  local list = window.ScrollBar and window.ScrollBar.selectionList
  if not list or list:isDestroyed() then
    return
  end

  local last = math.min(queue.index + SELECTION_BATCH_SIZE - 1, #queue.items)
  for i = queue.index, last do
    local entry = queue.items[i]
    local button = entry.button
    if button and not button:isDestroyed() then
      entry.apply(button)
      markSelectionButtonReady(button)
    end
  end

  queue.index = last + 1
  if queue.index <= #queue.items then
    pendingSelectionFill = scheduleEvent(function()
      fillSelectionBatch(queue, token)
    end, SELECTION_BATCH_DELAY_MS)
  else
    cancelSelectionLoadingAnim()
  end
end

local function startSelectionFill(items)
  cancelPendingSelectionFill()
  if not items or #items == 0 then
    return
  end

  local token = selectionFillToken
  local queue = { items = items, index = 1 }
  activeSelectionQueue = queue
  startSelectionLoadingAnim()
  fillSelectionBatch(queue, token)
end

-- Recolours already-built tiles instead of rebuilding the whole grid, which is
-- what made every colour click rebuild (and reload) the full selection list.
local function recolorSelectionButton(button)
  local outfit = button.appliedOutfit
  if not outfit then
    return
  end

  local kind = button.selectionKind
  if kind == 'mount' then
    outfit.head = tempOutfit.mountHead or 0
    outfit.body = tempOutfit.mountBody or 0
    outfit.legs = tempOutfit.mountLegs or 0
    outfit.feet = tempOutfit.mountFeet or 0
  elseif kind == 'outfit' or kind == 'aura' then
    outfit.head = tempOutfit.head or 0
    outfit.body = tempOutfit.body or 0
    outfit.legs = tempOutfit.legs or 0
    outfit.feet = tempOutfit.feet or 0
  else
    return
  end

  button.outfit:setOutfit(outfit)
end

local function recolorBatch(buttons, index, token)
  pendingColorFill = nil
  if token ~= colorFillToken or not window or window:isDestroyed() then
    return
  end

  local last = math.min(index + COLOR_BATCH_SIZE - 1, #buttons)
  for i = index, last do
    local button = buttons[i]
    if button and not button:isDestroyed() then
      recolorSelectionButton(button)
    end
  end

  if last < #buttons then
    pendingColorFill = scheduleEvent(function()
      recolorBatch(buttons, last + 1, token)
    end, COLOR_BATCH_DELAY_MS)
  end
end

-- Tiles still queued in the initial fill read tempOutfit when their turn comes,
-- so only the ones already drawn need an explicit refresh.
local function refreshSelectionColors()
  if not window or window:isDestroyed() then
    return
  end

  local list = window.ScrollBar and window.ScrollBar.selectionList
  if not list or list:isDestroyed() then
    return
  end

  local buttons = {}
  for _, child in ipairs(list:getChildren()) do
    if child.appliedOutfit then
      table.insert(buttons, child)
    end
  end

  if #buttons == 0 then
    return
  end

  colorFillToken = colorFillToken + 1
  recolorBatch(buttons, 1, colorFillToken)
end

function scheduleSelectionColorRefresh()
  if pendingColorDebounce then
    removeEvent(pendingColorDebounce)
  end
  if pendingColorFill then
    removeEvent(pendingColorFill)
    pendingColorFill = nil
  end

  pendingColorDebounce = scheduleEvent(function()
    pendingColorDebounce = nil
    refreshSelectionColors()
  end, COLOR_DEBOUNCE_MS)
end

local function prioritizeSelectionItem(items, focusedId)
  if not focusedId or #items == 0 then
    return
  end
  for i, entry in ipairs(items) do
    if entry.id == focusedId then
      if i > 1 then
        local focused = table.remove(items, i)
        table.insert(items, 1, focused)
      end
      return
    end
  end
end

local function isOutfitAnimEnabled(optionKey)
  if modules.client_options and modules.client_options.isOutfitAnimationEnabled then
    return modules.client_options.isOutfitAnimationEnabled(optionKey)
  end
  return true
end

local function outfitAnimDuration(baseMs)
  if modules.client_options and modules.client_options.getOutfitAnimationDuration then
    return modules.client_options.getOutfitAnimationDuration(baseMs)
  end
  return baseMs
end

local function cancelFamiliarPreviewAnim()
  if g_effects then
    g_effects.cancelValue(familiarPreviewAnim)
  end
end

local function cancelPreviewTransitions()
  if g_effects then
    g_effects.cancelValue(previewTransitionAnim)
  end
  if previewCreature and not previewCreature:isDestroyed() then
    previewCreature:setMarginTop(CREATURE_MARGIN_TOP_DEFAULT)
  end
end

-- Soft settle nudge (no opacity fade) when outfit/mount/addons/floor toggle.
local function animatePreviewTransition(applyChange, options)
  options = options or {}
  if applyChange then
    applyChange()
  end

  local optionKey = options.optionKey
  if optionKey and not isOutfitAnimEnabled(optionKey) then
    return
  end

  if suppressPreviewTransition or not previewCreature or previewCreature:isDestroyed() or not g_effects then
    return
  end

  local nudgeTop = options.nudgeTop or 0
  if nudgeTop == 0 then
    return
  end

  g_effects.cancelValue(previewTransitionAnim)
  previewCreature:setMarginTop(CREATURE_MARGIN_TOP_DEFAULT + nudgeTop)
  g_effects.animateValue(previewTransitionAnim, nudgeTop, 0, outfitAnimDuration(PREVIEW_TRANSITION_MS), function(offset)
    if not previewCreature or previewCreature:isDestroyed() then
      return
    end
    previewCreature:setMarginTop(CREATURE_MARGIN_TOP_DEFAULT + math.floor(offset + 0.5))
  end)
end

local function applyFloorImage(showFloor)
  if not window or not window.preview or not window.preview.previewoutfit then
    return
  end
  if showFloor then
    window.preview.previewoutfit:setImageSource('/images/game/outfit_ground')
  else
    window.preview.previewoutfit:setImageSource('/images/game/cyclopedia/ui/panel-background')
  end
end

local function animateFloorTransition(showFloor)
  applyFloorImage(showFloor)
  animatePreviewTransition(nil, {
    nudgeTop = showFloor and 5 or -5,
    optionKey = 'showOutfitAnimationFloor'
  })
end

local function applyFamiliarPreviewProgress(progress)
  progress = math.max(0, math.min(1, progress or 0))

  if previewCreature and not previewCreature:isDestroyed() then
    previewCreature:setMarginRight(math.floor(FAMILIAR_SHIFT_MARGIN * progress + 0.5))
  end

  if not previewFamiliar or previewFamiliar:isDestroyed() then
    return
  end

  local marginLeft = FAMILIAR_MARGIN_LEFT_HIDDEN +
    (FAMILIAR_MARGIN_LEFT_SHOWN - FAMILIAR_MARGIN_LEFT_HIDDEN) * progress
  previewFamiliar:setMarginLeft(math.floor(marginLeft + 0.5))
  previewFamiliar:setOpacity(progress)

  if progress > 0.01 then
    previewFamiliar:setVisible(true)
  else
    previewFamiliar:setVisible(false)
    previewFamiliar:setOpacity(1)
    previewFamiliar:setMarginLeft(FAMILIAR_MARGIN_LEFT_SHOWN)
  end
end

local function setFamiliarPreviewLook(familiarId, direction)
  if not previewFamiliar or previewFamiliar:isDestroyed() then
    return
  end
  if familiarId and familiarId > 0 then
    previewFamiliar:setOutfit({ type = familiarId })
  end
  if direction ~= nil then
    previewFamiliar:setDirection(direction)
  end
end

local function animateFamiliarPreview(show, familiarId, direction)
  setFamiliarPreviewLook(familiarId, direction)

  if suppressPreviewTransition or not previewFamiliar or not g_effects or not isOutfitAnimEnabled('showOutfitAnimationFamiliar') then
    applyFamiliarPreviewProgress(show and 1 or 0)
    familiarPreviewShown = show and true or false
    return
  end

  local from = 0
  if previewCreature and not previewCreature:isDestroyed() then
    from = (previewCreature:getMarginRight() or 0) / FAMILIAR_SHIFT_MARGIN
  elseif familiarPreviewShown then
    from = 1
  end

  if show then
    previewFamiliar:setVisible(true)
  end

  familiarPreviewShown = show and true or false
  g_effects.animateValue(familiarPreviewAnim, from, show and 1 or 0, outfitAnimDuration(FAMILIAR_ANIM_MS), function(progress)
    applyFamiliarPreviewProgress(progress)
  end)
end

local currentColorBox = nil
local globalRandomMount = nil
local lastFocusPreset = nil
local renamePresetWindow = nil
local showFamiliarCheck = nil
local editingPresetIndex = nil

ignoreNextOutfitWindow = 0

local function nowTimestamp()
  return os.time()
end

local function formatPresetTime(ts)
  ts = tonumber(ts)
  if not ts or ts <= 0 then
    return tr('Unknown')
  end
  return os.date('%Y-%m-%d %H:%M', ts)
end

local function getPresetBaseName(data)
  if type(data) == 'string' then
    return data
  end
  return (data and data.name) or 'Preset'
end

local function getPresetDisplayName(index, data)
  return string.format('%d. %s', index, getPresetBaseName(data))
end

local function getPresetTooltip(data)
  local created = formatPresetTime(data and data.createdAt)
  local updated = formatPresetTime(data and (data.updatedAt or data.createdAt))
  return tr('Created: %s\nLast edit: %s', created, updated)
end

local function ensurePresetTimestamps(data)
  if not data then
    return
  end
  if not data.createdAt then
    data.createdAt = nowTimestamp()
  end
  if not data.updatedAt then
    data.updatedAt = data.createdAt
  end
end

local presetList = {}
local pendingStoreTryOn = nil
local currentPlayerId = nil

local tempFamiliar = {type = 0}
local ServerData = {
  currentOutfit = {},
  outfits = {},
  mounts = {},
  familiars = {},
  wings = {},
  auras = {},
  shaders = {},
  healthBars = {},
  manaBars = {}
}

local AppearanceData = {
  "preset",
  "outfit",
  "mount",
  "familiar",
  "aura"
}

local function normalizeStoreTryOn(data)
  if type(data) ~= "table" then
    return nil
  end

  local kind = data.kind
  local id = tonumber(data.id) or 0
  if id <= 0 or (kind ~= "outfit" and kind ~= "mount") then
    return nil
  end

  return {
    kind = kind,
    id = id,
    offerId = tonumber(data.offerId) or 0,
    name = data.name or (kind == "mount" and "Store Mount" or "Store Outfit"),
    addons = tonumber(data.addons) or 3
  }
end

function setStoreTryOn(data)
  pendingStoreTryOn = normalizeStoreTryOn(data)
end

function clearStoreTryOn()
  pendingStoreTryOn = nil
end

local function consumeStoreTryOn()
  local data = pendingStoreTryOn
  pendingStoreTryOn = nil
  return data
end

local function hasAppearanceEntry(list, id)
  for _, data in ipairs(list or {}) do
    if tonumber(data[1]) == id then
      return true
    end
  end

  return false
end

local function applyStoreTryOn(data)
  if not data then
    return nil
  end

  if data.kind == "outfit" then
    if not hasAppearanceEntry(ServerData.outfits, data.id) then
      table.insert(ServerData.outfits, {data.id, data.name, data.addons, 1, data.offerId})
    end

    tempOutfit.type = data.id
    tempOutfit.addons = data.addons
    return window.appearance.outfitCheck
  end

  if not hasAppearanceEntry(ServerData.mounts, data.id) then
    table.insert(ServerData.mounts, {data.id, data.name, data.offerId})
  end

  tempOutfit.mount = data.id
  showMountCheck:setEnabled(true)
  showMountCheck:setChecked(true)
  if window.appearance.mountCheck then
    window.appearance.mountCheck:setEnabled(true)
  end
  return window.appearance.mountCheck
end

local function getOutfitStoreInfo(data)
  local mode = tonumber(data[4]) or 0
  local offerId = tonumber(data[5]) or 0

  if data[5] == nil then
    offerId = mode
    mode = offerId > 0 and 1 or 0
  end

  return mode, offerId
end

local function getStoreOutfitInfo(outfitId)
  outfitId = tonumber(outfitId) or 0
  for _, data in pairs(ServerData.outfits) do
    if tonumber(data[1]) == outfitId then
      return getOutfitStoreInfo(data)
    end
  end

  return 0, 0
end

local function openStoreOutfit(offerId)
  offerId = tonumber(offerId) or 0
  window:hide()
  g_game.openStore()
  if offerId > 0 then
    g_game.requestStoreOffers(4, "", offerId)
  else
    g_game.requestStoreOffers(2, "Outfits", 0)
  end
end

function init()
  connect(
    g_game,
    {
      onOpenOutfitWindow = create,
      onGameEnd = destroy
    }
  )
end

local function matchText(input, target)
    input = input:lower()
    target = target:lower()

    if input == target then
        return true
    end

    if #input >= 1 and target:find(input, 1, true) then
        return true
    end
    return false
end

function terminate()
  disconnect(
    g_game,
    {
      onOpenOutfitWindow = create,
      onGameEnd = destroy
    }
  )
  destroy()
end

function onMovementChange(checkBox, checked)
  g_settings.set('outfit_movement', checked)
  local creature = previewCreature:getCreature()
  if creature then
    creature:setStaticWalking(checked and 1000 or 0)
    creature:setAnimate(true)
  end
end

function onShowFloorChange(checkBox, checked)
  g_settings.set('outfit_showFloor', checked)
  animateFloorTransition(checked)
end

function onShowFamiliarChange(checkBox, checked)
  g_settings.set('outfit_showFamiliar', checked)
  if checked then
    local familiarId = tonumber(tempOutfit and tempOutfit.familiar) or 0
    if familiarId == 0 and tempFamiliar then
      familiarId = tonumber(tempFamiliar.type) or 0
    end
    if familiarId == 0 and ServerData and ServerData.familiars then
      for _, familiarData in ipairs(ServerData.familiars) do
        familiarId = tonumber(familiarData[1]) or 0
        if familiarId > 0 then
          break
        end
      end
    end
    if familiarId > 0 then
      tempOutfit.familiar = familiarId
      tempFamiliar = { type = familiarId }
    end
  end
  updatePreview()
end

function onShowAuraChange(checkBox, checked)
  g_settings.set('outfit_showAura', checked)
  updatePreview()
end

function onOnlyMineThings()
  if window.appearance.outfitCheck:isChecked() then
    showOutfits()
  elseif window.appearance.mountCheck:isChecked() then
    showMounts()
  end
end

function onMountCheckChange(checkBox, checked)
  g_settings.set('outfit_mountCheck', checked)
  showOutfitCheck:setEnabled(checked)
  if checked and showAuraCheck and showAuraCheck:isChecked() then
    showAuraCheck.onCheckChange = nil
    showAuraCheck:setChecked(false)
    showAuraCheck.onCheckChange = onShowAuraChange
    g_settings.set('outfit_showAura', false)
  end

  animatePreviewTransition(function()
    updatePreview()
  end, { nudgeTop = checked and -10 or 8, optionKey = 'showOutfitAnimationMount' })
end

function onShowOutfitCheckChange(checkBox, checked)
  g_settings.set('outfit_showOutfit', checked)
  animatePreviewTransition(function()
    updatePreview(not checked)
  end, { nudgeTop = checked and 6 or -6, optionKey = 'showOutfitAnimationOutfit' })
end

function create(player, outfitList, creatureMount, mountList, familiarList, wingList, auraList, effectsList, shaderList, healthBarList, manaBarList)
  if ignoreNextOutfitWindow and g_clock.millis() < ignoreNextOutfitWindow + 1000 then
    return
  end

  local currentOutfit = player and player:getOutfit() or {}
  outfitList = outfitList or {}
  mountList = mountList or {}
  familiarList = familiarList or {}
  wingList = wingList or {}
  auraList = auraList or {}
  effectsList = effectsList or {}
  shaderList = shaderList or {}
  healthBarList = healthBarList or {}
  manaBarList = manaBarList or {}

  currentOutfit.addons = tonumber(currentOutfit.addons) or 0
  currentOutfit.mount = tonumber(currentOutfit.mount) or 0
  currentOutfit.familiar = tonumber(currentOutfit.familiar) or 0
  currentOutfit.aura = tonumber(currentOutfit.aura) or 0
  currentOutfit.auraCategory = tonumber(currentOutfit.auraCategory) or 0
  currentOutfit.auraId = tonumber(currentOutfit.auraId) or 0

  if window then
    destroy()
  end

  loadSettings()

  for i = 1, #auraList do
    local auraData = auraList[i]
    if auraData[3] == currentOutfit.aura then
      currentOutfit.auraId = auraData[1]
      break
    end
  end

  ServerData = {
    currentOutfit = currentOutfit,
    outfits = outfitList,
    mounts = mountList,
    familiars = familiarList,
    wings = wingList,
    auras = auraList,
    shaders = shaderList,
    healthBars = healthBarList,
    manaBars = manaBarList
  }

  window = g_ui.displayUI("outfitwindow")
  g_client.setInputLockWidget(window)

  for _, appKey in ipairs(AppearanceData) do
    updateAppearanceText(appKey, "None")
  end

  previewCreature = window.preview.previewoutfit.creature
  previewFamiliar = window.preview.previewoutfit.familiar
  cancelFamiliarPreviewAnim()
  familiarPreviewShown = false
  previewFamiliar:setVisible(false)
  previewFamiliar:setOpacity(1)
  previewFamiliar:setMarginLeft(FAMILIAR_MARGIN_LEFT_SHOWN)
  if previewCreature then
    previewCreature:setMarginRight(0)
  end

  window.preview.previewoutfit.onMouseWheel = function(widget, mousePos, mouseWheelDirection)
    if mouseWheelDirection == MouseWheelUp then
      rotate(1)
    elseif mouseWheelDirection == MouseWheelDown then
      rotate(-1)
    end
    return true
  end

  if currentOutfit.familiar == 0 and not table.empty(familiarList) then
    tempFamiliar = {type = familiarList[1][1]}
    currentOutfit.familiar = familiarList[1][1]
    previewFamiliar:setOutfit(tempFamiliar)
  else
    tempFamiliar = {type = currentOutfit.familiar}
    previewFamiliar:setOutfit(tempFamiliar)
  end

  tempOutfit = table.copy(currentOutfit)

  if g_game.getFeature(GamePlayerMounts) then
    local isMount = g_game.getLocalPlayer():isMounted()
    local savedMount = g_settings.getBoolean('outfit_mountCheck', false)
    if isMount then
      window.configure.mount.mountCheck:setEnabled(true)
      window.configure.mount.mountCheck:setChecked(true)
    else
      window.configure.mount.mountCheck:setEnabled(#mountList > 0)
      window.configure.mount.mountCheck:setChecked(savedMount and currentOutfit.mount > 0)
    end
  end

  if currentOutfit.addons == 3 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif currentOutfit.addons == 2 then
    window.configure.addon1.addon1Check:setChecked(false)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif currentOutfit.addons == 1 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(false)
  end
  window.configure.addon1.addon1Check.onCheckChange = onAddonChange
  window.configure.addon2.addon2Check.onCheckChange = onAddonChange

  window.configure.randommount.randomCheck:setChecked(false)
  globalRandomMount = false

  window.configure.randommount.randomCheck.onCheckChange = onRandomMountChange

  configureAddons(currentOutfit.addons)
  local storeTryOn = consumeStoreTryOn()

  movementCheck = window.preview.movement.movementCheck
  showFloorCheck = window.preview.showfloor.showfloorCheck
  showOutfitCheck = window.preview.showoutfit.showoutfitCheck
  showMountCheck = window.configure.mount.mountCheck
  showFamiliarCheck = window.preview.showfamiliar.showfamiliarCheck
  showAuraCheck = window.preview.showAura.showAuraCheck
  auraCheck = window.configure.aura.auraCheck

  showOutfitCheck.onCheckChange = onShowOutfitCheckChange
  showMountCheck.onCheckChange = onMountCheckChange
  movementCheck.onCheckChange = onMovementChange
  showFloorCheck.onCheckChange = onShowFloorChange
  showFamiliarCheck.onCheckChange = onShowFamiliarChange
  showAuraCheck.onCheckChange = onShowAuraChange

  local familiarId = tonumber(currentOutfit.familiar) or 0
  local hasFamiliarList = type(familiarList) == 'table' and not table.empty(familiarList)
  local hasFamiliarOptions = hasFamiliarList or familiarId > 0 or g_game.getFeature(GamePlayerFamiliars)
  -- Keep Show Familiar clickable when familiars are supported / available.
  showFamiliarCheck:setEnabled(hasFamiliarOptions)
  if not hasFamiliarList and familiarId == 0 then
    window.appearance.familiarCheck:setEnabled(false)
  else
    window.appearance.familiarCheck:setEnabled(true)
  end

  showAuraCheck:setEnabled(not table.empty(auraList))
  auraCheck:setEnabled(not table.empty(auraList))
  if table.empty(auraList) then
    window.appearance.auraCheck:setEnabled(false)
  else
    window.appearance.auraCheck:setEnabled(true)
  end

  -- Avoid transition animations while restoring the initial checkbox state.
  suppressPreviewTransition = true

  showOutfitCheck:setChecked(g_settings.getBoolean('outfit_showOutfit', true))
  showMountCheck:setChecked(g_settings.getBoolean('outfit_mountCheck', false) and currentOutfit.mount > 0)
  showFamiliarCheck:setChecked(g_settings.getBoolean('outfit_showFamiliar', false))
  showAuraCheck:setChecked(g_settings.getBoolean('outfit_showAura', false))
  movementCheck:setChecked(g_settings.getBoolean('outfit_movement', false))
  window.configure.aura.auraCheck:setChecked(currentOutfit.aura > 0)
  
  -- Apply Show Floor visual state properly after checkboxes are wired up
  local showFloor = g_settings.getBoolean('outfit_showFloor', true)
  showFloorCheck:setChecked(showFloor)
  if not showFloor then
    applyFloorImage(false)
  end
  
  -- Restore last selected preset name if it exists
  local savedPresetName = g_settings.get('outfit_lastPresetName', '')
  if savedPresetName ~= '' then
    updateAppearanceText('preset', savedPresetName)
  end
  local storeTryOnAppearance = applyStoreTryOn(storeTryOn)

  colorBoxGroup = UIRadioGroup.create()
  for j = 0, 6 do
    for i = 0, 18 do
      local colorBox = g_ui.createWidget("ColorBox", window.appearance.panelcolor)
      local outfitColor = getOutfitColor(j * 19 + i)
      colorBox:setBackgroundColor(outfitColor)
      colorBox:setId("colorBox" .. j * 19 + i)
      colorBox.colorId = j * 19 + i
      
      colorBox.onHoverChange = function(widget, hovered)
        if hovered and g_mouse.isPressed(MouseLeftButton) then
          colorBoxGroup:selectWidget(widget)
        end
      end

      if colorBox.colorId == currentOutfit.head then
        currentColorBox = colorBox
        colorBox:setChecked(true)
        currentColorBox:setBorderWidth(1)
        currentColorBox:setBorderColor("white")
      end
      colorBoxGroup:addWidget(colorBox)
    end
  end

  showOutfitCheck:setEnabled(creatureMount)
  colorBoxGroup.onSelectionChange = onColorCheckChange

  appearanceGroup = UIRadioGroup.create()
  appearanceGroup:addWidget(window.appearance.presetCheck)
  appearanceGroup:addWidget(window.appearance.outfitCheck)
  appearanceGroup:addWidget(window.appearance.mountCheck)
  appearanceGroup:addWidget(window.appearance.familiarCheck)
  appearanceGroup:addWidget(window.appearance.auraCheck)

  appearanceGroup.onSelectionChange = onAppearanceChange

  colorModeGroup = UIRadioGroup.create()
  colorModeGroup:addWidget(window.appearance.panelbar.HeadButton)
  colorModeGroup:addWidget(window.appearance.panelbar.PrimaryButton)
  colorModeGroup:addWidget(window.appearance.panelbar.SecondaryButton)
  colorModeGroup:addWidget(window.appearance.panelbar.DetailButton)

  colorModeGroup.onSelectionChange = onColorModeChange
  colorModeGroup:selectWidget(window.appearance.panelbar.HeadButton)
  appearanceGroup:selectWidget(window.appearance.outfitCheck)

  updatePreview()
  updateAppearanceTexts(currentOutfit)
  suppressPreviewTransition = false

  if not table.empty(ServerData.auras) then
    if currentOutfit.auraId == 0 then
      local data = ServerData.auras[1]
      currentOutfit.aura = data[3]
      currentOutfit.auraCategory = data[2]
      currentOutfit.auraId = data[1]
      updateAppearanceText("aura", data[4])
    end
  end

  appearanceGroup:selectWidget(storeTryOnAppearance or window.appearance.outfitCheck)
end

function destroy()
  if window then
    cancelPendingSelectionFill()
    cancelFamiliarPreviewAnim()
    cancelPreviewTransitions()
    familiarPreviewShown = false
    suppressPreviewTransition = false
    g_client.setInputLockWidget()
    window:destroy()
    window = nil

    movementCheck = nil
    showFloorCheck = nil
    showOutfitCheck = nil
    showMountCheck = nil
    showFamiliarCheck = nil
    showAuraCheck = nil
    previewCreature = nil
    previewFamiliar = nil

    currentColorBox = nil
    lastFocusPreset = nil
    editingPresetIndex = nil

    if appearanceGroup then
      appearanceGroup:destroy()
    end
    appearanceGroup = nil
    if colorModeGroup then
      colorModeGroup:destroy()
    end
    colorModeGroup = nil
    if colorBoxGroup then
      colorBoxGroup:destroy()
    end
    colorBoxGroup = nil

    ServerData = {
      currentOutfit = {},
      outfits = {},
      mounts = {},
      familiars = {},
      wings = {},
      auras = {},
      shaders = {},
      healthBars = {},
      manaBars = {},
    }

    saveSettings()
    settings = {}
  end
end

function configureAddons(addons)
  local hasAddon1 = addons == 1 or addons == 3
  local hasAddon2 = addons == 2 or addons == 3
  window.configure.addon1.addon1Check:setEnabled(hasAddon1)
  window.configure.addon2.addon2Check:setEnabled(hasAddon2)

  window.configure.addon1.addon1Check.onCheckChange = nil
  window.configure.addon2.addon2Check.onCheckChange = nil
  window.configure.addon1.addon1Check:setChecked(false)
  window.configure.addon2.addon2Check:setChecked(false)
  if tempOutfit.addons == 3 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif tempOutfit.addons == 2 then
    window.configure.addon1.addon1Check:setChecked(false)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif tempOutfit.addons == 1 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(false)
  end
  window.configure.addon1.addon1Check.onCheckChange = onAddonChange
  window.configure.addon2.addon2Check.onCheckChange = onAddonChange
end

function newPreset()
  local outfitPreset = presetList["customiseCharacterPresets"]
  local now = nowTimestamp()
  outfitPreset[#outfitPreset + 1] = {
    ["mount"] = {
      ["color"] = { ["detail"] = tempOutfit.mountFeet, ["head"] = tempOutfit.mountHead, ["legs"] = tempOutfit.mountLegs, ["torso"] = tempOutfit.mountBody},
      ["id"] = window.configure.mount.mountCheck:isChecked() and tempOutfit.mount or 0
    },
    ["name"] = "Preset",
    ["createdAt"] = now,
    ["updatedAt"] = now,
    ["outfit"] = {
      ["color"] = { ["detail"] = tempOutfit.feet, ["head"] = tempOutfit.head, ["legs"] = tempOutfit.legs, ["torso"] = tempOutfit.body},
      ["id"] = tempOutfit.type,
      ["firstAddOn"] = window.configure.addon1.addon1Check:isChecked(),
      ["secondAddOn"] = window.configure.addon2.addon2Check:isChecked(),
    },
    ["summon"] = { ["id"] = showFamiliarCheck:isChecked() and tempOutfit.familiar or 0}
  }

  showPresets()
  saveSettings()
end

function savePreset()
  if not lastFocusPreset and not editingPresetIndex then
    return
  end
  local widgetIndex = editingPresetIndex or (lastFocusPreset and lastFocusPreset:getActionId())
  local outfitPreset = presetList["customiseCharacterPresets"]
  
  if outfitPreset and outfitPreset[widgetIndex] then
    local current = outfitPreset[widgetIndex]
    ensurePresetTimestamps(current)
    local currentName = current["name"]
    local createdAt = current["createdAt"] or nowTimestamp()
    outfitPreset[widgetIndex] = {
      ["mount"] = {
        ["color"] = { ["detail"] = tempOutfit.mountFeet, ["head"] = tempOutfit.mountHead, ["legs"] = tempOutfit.mountLegs, ["torso"] = tempOutfit.mountBody},
        ["id"] = window.configure.mount.mountCheck:isChecked() and tempOutfit.mount or 0
      },
      ["name"] = currentName,
      ["createdAt"] = createdAt,
      ["updatedAt"] = nowTimestamp(),
      ["outfit"] = {
        ["color"] = { ["detail"] = tempOutfit.feet, ["head"] = tempOutfit.head, ["legs"] = tempOutfit.legs, ["torso"] = tempOutfit.body},
        ["id"] = tempOutfit.type,
        ["firstAddOn"] = window.configure.addon1.addon1Check:isChecked(),
        ["secondAddOn"] = window.configure.addon2.addon2Check:isChecked(),
      },
      ["summon"] = { ["id"] = showFamiliarCheck:isChecked() and tempOutfit.familiar or 0}
    }

    local focusAfterSave = widgetIndex
    editingPresetIndex = focusAfterSave
    saveSettings()

    -- Return to presets view with updated thumbnail.
    if appearanceGroup then
      appearanceGroup:selectWidget(window.appearance.presetCheck)
    else
      showPresets()
    end
  end
end

function editPreset()
  if not lastFocusPreset then
    return
  end

  editingPresetIndex = lastFocusPreset:getActionId()
  window.appearance.grayHover:setVisible(false)
  window.presetBar.saveButton:setEnabled(true)
  window.presetBar.editButton:setEnabled(false)

  -- Jump to outfit list so the player can change type/addons/colors, then Save.
  if appearanceGroup then
    appearanceGroup:selectWidget(window.appearance.outfitCheck)
  end

  -- Keep Save available while editing from the Outfit tab.
  window.presetBar:setVisible(true)
  window.presetBar.newButton:setEnabled(false)
  window.presetBar.renameButton:setEnabled(false)
  window.presetBar.deleteButton:setEnabled(false)
  window.presetBar.saveButton:setEnabled(true)
  window.presetBar.editButton:setEnabled(false)
end

function deletePreset()
  if not lastFocusPreset then
    return
  end

  local widgetIndex = lastFocusPreset:getActionId()
  table.remove( presetList["customiseCharacterPresets"], widgetIndex)
  window.presetBar.renameButton:setEnabled(false)
  window.presetBar.saveButton:setEnabled(false)
  window.presetBar.editButton:setEnabled(false)
  window.presetBar.deleteButton:setEnabled(false)
  window.okButton:setEnabled(true)
  lastFocusPreset:setBorderColor("alpha")
  lastFocusPreset:setBorderWidth("0")
  updateAppearanceText("preset", "None")
  g_settings.set('outfit_lastPresetName', '')
  lastFocusPreset = nil
  editingPresetIndex = nil
  showPresets()
  saveSettings()
end

function renamePreset()
  if not lastFocusPreset then
    return
  end

  local presetData = presetList["customiseCharacterPresets"][lastFocusPreset:getActionId()]
  local baseName = getPresetBaseName(presetData)

	window:hide()
	renamePresetWindow = g_ui.loadUI('renamePreset', g_ui.getRootWidget())
	renamePresetWindow:setText("Rename Preset")
	renamePresetWindow.contentPanel.text:setVisible(false)

  renamePresetWindow.contentPanel.target:setText(baseName)
	renamePresetWindow.contentPanel.okButton.onClick = function()
		local text = renamePresetWindow.contentPanel.target:getText()
		if #text == 0 then
			text = "Preset"
		end

    local index = lastFocusPreset:getActionId()
    presetList["customiseCharacterPresets"][index]["name"] = text
    ensurePresetTimestamps(presetList["customiseCharacterPresets"][index])
    presetList["customiseCharacterPresets"][index]["updatedAt"] = nowTimestamp()

    local displayName = getPresetDisplayName(index, presetList["customiseCharacterPresets"][index])
    updateAppearanceText("preset", displayName)
    lastFocusPreset.name:setText(displayName)
    lastFocusPreset:setTooltip(getPresetTooltip(presetList["customiseCharacterPresets"][index]))
		renamePresetWindow:destroy()
		window:show()
    saveSettings()
	end

	renamePresetWindow.contentPanel.cancelButton.onClick = function()
		renamePresetWindow:destroy()
		window:show()
	end
end

function onAppearanceChange(widget, selectedWidget)
  local id = selectedWidget:getId()
  window.filter_outfits.onlyCheck:setChecked(false)

  if id == "presetCheck" then
    showPresets()
  elseif id == "outfitCheck" then
    showOutfits()
  elseif id == "mountCheck" then
    showMounts()
  elseif id == "familiarCheck" then
    showFamiliars()
  elseif id == "auraCheck" then
    showAuras()
  end
end

function onHidePresetWindow()
  window.presetList.selectionList:destroyChildren()
  window.presetList:setVisible(false)
  window.ScrollBar:setVisible(true)
  window.okButton:setEnabled(true)
  window.appearance.grayHover:setVisible(false)

  if editingPresetIndex then
    -- Keep Save bar visible while editing; hide filter to avoid overlap.
    window.filter_outfits:setVisible(false)
    window.presetBar:setVisible(true)
    window.presetBar.newButton:setEnabled(false)
    window.presetBar.renameButton:setEnabled(false)
    window.presetBar.deleteButton:setEnabled(false)
    window.presetBar.editButton:setEnabled(false)
    window.presetBar.saveButton:setEnabled(true)
  else
    window.filter_outfits:setVisible(true)
    window.presetBar:setVisible(false)
    window.presetBar.renameButton:setEnabled(false)
    window.presetBar.saveButton:setEnabled(false)
    window.presetBar.editButton:setEnabled(false)
    window.presetBar.deleteButton:setEnabled(false)
  end
end

function showPresets()
  cancelPendingSelectionFill()
  window.ScrollBar.selectionList:destroyChildren()
  window.presetList.selectionList:destroyChildren()
  window.ScrollBar:setVisible(false)
  window.filter_outfits:setVisible(false)
  window.presetList:setVisible(true)
  window.presetBar:setVisible(true)
  window.presetBar.newButton:setEnabled(true)

  local focusIndex = editingPresetIndex
  editingPresetIndex = nil
  lastFocusPreset = nil

  local outfitPreset = presetList["customiseCharacterPresets"]
  local focusedWidget = nil
  for i, data in ipairs(outfitPreset) do
    ensurePresetTimestamps(data)
    local widget = g_ui.createWidget("PresetButton", window.presetList.selectionList)

    widget:setActionId(i)
    widget.outfit:setOutfit(getPresetOutfit(data))
    widget.name:setText(getPresetDisplayName(i, data))
    widget:setTooltip(getPresetTooltip(data))

    local summonId = data["summon"] and (tonumber(data["summon"]["id"]) or 0) or 0
    if summonId > 0 then
      widget.outfit:setMarginRight(32)
      widget.familiar:setOutfit({type = summonId})
      widget.familiar:setVisible(true)
    end

    local storeMount = getStoreMount(widget.outfit:getOutfit().mount)
    local storeOutfitMode = getStoreOutfitInfo(widget.outfit:getOutfit().type)
    if storeMount > 0 or storeOutfitMode ~= 0 then
      widget:setImageSource("/images/ui/big-dark-button")
      widget.info:setVisible(true)
    end

    widget.onClick = onPresetSelect
    if focusIndex and i == focusIndex then
      focusedWidget = widget
    end
  end

  window.presetList.selectionList:focusChild(nil)
  window.presetBar.renameButton:setEnabled(false)
  window.presetBar.saveButton:setEnabled(false)
  window.presetBar.editButton:setEnabled(false)
  window.presetBar.deleteButton:setEnabled(false)

  if focusedWidget then
    -- Re-select without wiping the outfit the player just edited/saved.
    lastFocusPreset = focusedWidget
    lastFocusPreset:setBorderColor("white")
    lastFocusPreset:setBorderWidth("1")
    window.presetBar.renameButton:setEnabled(true)
    window.presetBar.saveButton:setEnabled(false)
    window.presetBar.editButton:setEnabled(true)
    window.presetBar.deleteButton:setEnabled(true)
    updateAppearanceText('preset', focusedWidget.name:getText())
  end
end

function showOutfits(searchText)
  onHidePresetWindow()
  cancelPendingSelectionFill()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(true)

  local onlyMine = window.filter_outfits.onlyCheck:isChecked()

  local availableOutfits = {}
  local lockedOutfits = {}
  for _, data in pairs(ServerData.outfits) do
    local storeMode = getOutfitStoreInfo(data)
    if storeMode == 0 then
        table.insert(availableOutfits, data)
    else
        table.insert(lockedOutfits, data)
    end
  end

  if not onlyMine then
    for _, data in ipairs(lockedOutfits) do
    table.insert(availableOutfits, data)
    end
  end

  local focused = nil
  local fillItems = {}
  local baseOutfit = table.copy(previewCreature:getOutfit())
  baseOutfit.mount = 0

  for _, outfitData in ipairs(availableOutfits) do
    if searchText and not matchText(searchText, outfitData[2]) then
      goto continue
    end

    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(outfitData[1])
    button.selectionKind = 'outfit'
    button.name:setText(outfitData[2])
    markSelectionButtonLoading(button)

    local storeMode, storeOffer = getOutfitStoreInfo(outfitData)
    if storeMode ~= 0 then
        button:setImageSource("/images/ui/large_blue_button")
        button.storeMode = storeMode
        button.storeOfferId = storeOffer
        if storeOffer > 0 then
          button:setActionId(storeOffer)
        end
    end

    if tempOutfit.type == outfitData[1] then
      focused = outfitData[1]
      configureAddons(outfitData[3])
    end

    local outfitType = outfitData[1]
    local outfitAddons = outfitData[3]
    table.insert(fillItems, {
      id = outfitType,
      button = button,
      apply = function(btn)
        local outfit = table.copy(baseOutfit)
        outfit.type = outfitType
        outfit.addons = outfitAddons
        outfit.mount = 0
        outfit.head = tempOutfit.head
        outfit.body = tempOutfit.body
        outfit.legs = tempOutfit.legs
        outfit.feet = tempOutfit.feet
        btn.outfit:setOutfit(outfit)
        btn.appliedOutfit = outfit
      end
    })

    :: continue ::
  end

  prioritizeSelectionItem(fillItems, focused)
  startSelectionFill(fillItems)

  local focusedWidget = focused and window.ScrollBar.selectionList[focused] or nil

  window.appearance.grayHover:setVisible(false)
  window.ScrollBar.selectionList.onChildFocusChange = onOutfitSelect
  window.ScrollBar.selectionList:show()
  if focusedWidget then
    focusedWidget:focus()
    window.ScrollBar.selectionList:ensureChildVisible(focusedWidget, {x = 0, y = 196})
    onOutfitSelect(window.ScrollBar.selectionList, focusedWidget, nil, KeyboardFocusReason)
  end
end

function showMounts(searchText)
  onHidePresetWindow()
  cancelPendingSelectionFill()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(true)

  local onlyMine = window.filter_outfits.onlyCheck:isChecked()

  local availableMounts = {}
  local lockedMounts = {}
  for _, data in pairs(ServerData.mounts) do
    if (tonumber(data[3]) or 0) == 0 then
      table.insert(availableMounts, data)
    else
      table.insert(lockedMounts, data)
    end
  end

  if not onlyMine then
    for _, data in ipairs(lockedMounts) do
      table.insert(availableMounts, data)
    end
  end

  local focused = nil
  local fillItems = {}
  for _, mountData in ipairs(availableMounts) do
    if searchText and not matchText(searchText, mountData[2]) then
      goto continue
    end

    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(mountData[1])
    button.selectionKind = 'mount'
    button.name:setText(mountData[2])
    markSelectionButtonLoading(button)

    local storeOffer = tonumber(mountData[3]) or 0
    if storeOffer > 0 then
        button:setImageSource("/images/ui/large_blue_button")
        button:setActionId(storeOffer)
    end

    if tempOutfit.mount == mountData[1] then
      focused = mountData[1]
    end

    local mountType = mountData[1]
    local wrapName = button.name:isTextWraped()
    table.insert(fillItems, {
      id = mountType,
      button = button,
      apply = function(btn)
        local outfit = {
          type = mountType,
          head = tempOutfit.mountHead,
          body = tempOutfit.mountBody,
          legs = tempOutfit.mountLegs,
          feet = tempOutfit.mountFeet
        }
        btn.outfit:setOutfit(outfit)
        btn.appliedOutfit = outfit
        btn.outfit:setCenter(true)
        if wrapName then
          btn.outfit:setMarginBottom(24)
        end
        if focused == mountType and not btn.outfit:isColoredMount() then
          window.appearance.grayHover:setVisible(true)
        end
      end
    })

    :: continue ::
  end

  prioritizeSelectionItem(fillItems, focused)
  startSelectionFill(fillItems)

  if #ServerData.mounts == 1 then
    window.ScrollBar.selectionList:focusChild(nil)
  end

  local focusedWidget = focused and window.ScrollBar.selectionList[focused] or nil

  window.ScrollBar.selectionList.onChildFocusChange = onMountSelect
  window.ScrollBar.selectionList:show()
  if focusedWidget then
    focusedWidget:focus()
    window.ScrollBar.selectionList:ensureChildVisible(focusedWidget, {x = 0, y = 196})
    onMountSelect(window.ScrollBar.selectionList, focusedWidget, nil, KeyboardFocusReason)
  end
end

function showFamiliars()
  onHidePresetWindow()
  cancelPendingSelectionFill()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(false)

  local focused = nil
  local fillItems = {}
  for _, mountData in ipairs(ServerData.familiars) do
    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(mountData[1])
    button.selectionKind = 'familiar'
    button.name:setText(mountData[2])
    markSelectionButtonLoading(button)

    if tempOutfit.familiar == mountData[1] then
      focused = mountData[1]
    end

    local familiarType = mountData[1]
    table.insert(fillItems, {
      id = familiarType,
      button = button,
      apply = function(btn)
        btn.outfit:setOutfit({type = familiarType})
        btn.outfit:setCenter(true)
      end
    })
  end

  prioritizeSelectionItem(fillItems, focused)
  startSelectionFill(fillItems)

  if #ServerData.familiars == 1 then
    window.ScrollBar.selectionList:focusChild(nil)
  end

  if focused ~= nil then
    local w = window.ScrollBar.selectionList[focused]
    w:focus()
    window.ScrollBar.selectionList:ensureChildVisible(w, {x = 0, y = 196})
  end

  window.appearance.grayHover:setVisible(true)
  window.ScrollBar.selectionList.onChildFocusChange = onFamiliarSelect
  window.ScrollBar.selectionList:show()
end

function showAuras()
  onHidePresetWindow()
  cancelPendingSelectionFill()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(false)

  local focused = nil
  local fillItems = {}
  local baseOutfit = table.copy(previewCreature:getOutfit())

  for _, auraData in ipairs(ServerData.auras) do
    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(auraData[1])
    button.selectionKind = 'aura'
    button.aura = auraData[3]
    button.auraCategory = auraData[2]
    button.name:setText(auraData[4])
    markSelectionButtonLoading(button)

    if tempOutfit.aura == auraData[3] then
      focused = auraData[1]
    end

    local auraId = auraData[3]
    local auraCategory = auraData[2]
    local buttonId = auraData[1]
    table.insert(fillItems, {
      id = buttonId,
      button = button,
      apply = function(btn)
        local outfit = table.copy(baseOutfit)
        outfit.head = tempOutfit.head
        outfit.body = tempOutfit.body
        outfit.legs = tempOutfit.legs
        outfit.feet = tempOutfit.feet
        outfit.aura = auraId
        outfit.auraCategory = auraCategory
        btn.outfit:setOutfit(outfit)
        btn.appliedOutfit = outfit
        btn.outfit:setCenter(true)
        btn.outfit:setAnimate(true)
      end
    })
  end

  prioritizeSelectionItem(fillItems, focused)
  startSelectionFill(fillItems)

  if #ServerData.auras == 1 then
    window.ScrollBar.selectionList:focusChild(nil)
  end

  window.appearance.grayHover:setVisible(true)
  window.ScrollBar.selectionList.onChildFocusChange = onAuraSelect
  window.ScrollBar.selectionList:show()

  if focused ~= nil then
    local w = window.ScrollBar.selectionList[focused]
    w:focus()
    window.ScrollBar.selectionList:ensureChildVisible(w, {x = 0, y = 196})
  else
    if not table.empty(ServerData.auras) then
      if tempOutfit.aura == 0 then
        updateAppearanceText("aura", ServerData.auras[1][4])
        window.ScrollBar.selectionList:focusChild(window.ScrollBar.selectionList:getFirstChild())
      end
    end
  end

end

function onPresetSelect(widget)
  if not widget then
    return true
  end

  if widget == lastFocusPreset then
    return true
  end

  if lastFocusPreset then
    lastFocusPreset:setBorderColor("alpha")
    lastFocusPreset:setBorderWidth("0")
  end

  lastFocusPreset = widget
  lastFocusPreset:setBorderColor("white")
  lastFocusPreset:setBorderWidth("1")

  tempOutfit = table.copy(widget.outfit:getOutfit())

  if (tempOutfit.mount or 0) > 0 then
    showMountCheck:setChecked(true)
  else
    showMountCheck:setChecked(false)
  end

  if (tempOutfit.familiar or 0) > 0 then
    showFamiliarCheck:setChecked(true)
  else
    showFamiliarCheck:setChecked(false)
  end

  if (tempOutfit.aura or 0) > 0 then
    showAuraCheck:setChecked(true)
  else
    showAuraCheck:setChecked(false)
  end

  local storeMount = getStoreMount(tempOutfit.mount)
  if storeMount > 0 then
    window.appearance.mount:setImageSource("/images/ui/hlarge-blue-button")
    window.appearance.mount.purse:setVisible(true)
    window.appearance.mount.onClick = function() window:hide() g_game.openStore() g_game.requestStoreOffers(4, "", storeMount) end
  else
    window.appearance.mount:setImageSource("/images/ui/pressed-large-button")
    window.appearance.mount.purse:setVisible(false)
    window.appearance.mount.onClick = nil
  end

  local storeOutfitMode, storeOutfit = getStoreOutfitInfo(tempOutfit.type)
  if storeOutfitMode ~= 0 then
    window.appearance.outfit:setImageSource("/images/ui/hlarge-blue-button")
    window.appearance.outfit.purse:setVisible(true)
    window.appearance.outfit.onClick = function() openStoreOutfit(storeOutfit) end
  else
    window.appearance.outfit:setImageSource("/images/ui/pressed-large-button")
    window.appearance.outfit.purse:setVisible(false)
    window.appearance.outfit.onClick = nil
  end

  window.okButton:setEnabled(true)
  if storeMount > 0 or storeOutfit > 0 then
    window.okButton:setEnabled(false)
  end

  window.presetBar.renameButton:setEnabled(true)
  window.presetBar.saveButton:setEnabled(false)
  window.presetBar.editButton:setEnabled(true)
  window.presetBar.deleteButton:setEnabled(true)
  window.appearance.grayHover:setVisible(true)

  updatePreview()
  updateAppearanceTexts(tempOutfit)
  updateAppearanceText('preset', widget.name:getText())
  g_settings.set('outfit_lastPresetName', widget.name:getText())
end

function onOutfitSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    local outfitType = tonumber(focusedChild:getId())
    local outfit = focusedChild.appliedOutfit or focusedChild.outfit:getOutfit()
    if not outfit.type or outfit.type == 0 then
      outfit.type = outfitType
      for _, outfitData in pairs(ServerData.outfits) do
        if tonumber(outfitData[1]) == outfitType then
          outfit.addons = outfitData[3]
          break
        end
      end
    end
    tempOutfit.type = outfit.type
    tempOutfit.addons = outfit.addons
    showOutfitCheck:setChecked(true)

    configureAddons(outfit.addons)
    updatePreview()

    updateAppearanceText("outfit", focusedChild.name:getText())
		window.ScrollBar.selectionList:ensureChildVisible(focusedChild, {x = 0, y = 2})

    local storeMode = tonumber(focusedChild.storeMode) or 0
    local storeOffer = tonumber(focusedChild.storeOfferId) or focusedChild:getActionId() or 0
		if storeMode ~= 0 or storeOffer > 0 then
			window.appearance.outfit:setImageSource("/images/ui/hlarge-blue-button")
      window.appearance.outfit.purse:setVisible(true)
      window.appearance.outfit.onClick = function() openStoreOutfit(storeOffer) end
      window.okButton:setEnabled(false)
		else
			window.appearance.outfit:setImageSource("/images/ui/pressed-large-button")
      window.appearance.outfit.purse:setVisible(false)
      window.appearance.outfit.onClick = nil
      window.okButton:setEnabled(true)
		end
  end

  window.appearance.grayHover:setVisible(false)
end

function onMountSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    local mountType = tonumber(focusedChild:getId())
    tempOutfit.mount = mountType
    showOutfitCheck:setChecked(true)
    showMountCheck:setEnabled(true)

    if showMountCheck:isChecked() then
      updatePreview()
    end

    updateAppearanceText("mount", focusedChild.name:getText())
    window.ScrollBar.selectionList:ensureChildVisible(focusedChild, {x = 0, y = 2})

		if focusedChild:getActionId() > 0 then
			window.appearance.mount:setImageSource("/images/ui/hlarge-blue-button")
      window.appearance.mount.purse:setVisible(true)
      window.appearance.mount.onClick = function() window:hide() g_game.openStore() g_game.requestStoreOffers(4, "", focusedChild:getActionId()) end
      window.okButton:setEnabled(false)
		else
			window.appearance.mount:setImageSource("/images/ui/pressed-large-button")
      window.appearance.mount.purse:setVisible(false)
      window.appearance.mount.onClick = nil
      window.okButton:setEnabled(true)
		end

    window.appearance.grayHover:setVisible(false)
    if focusedChild.appliedOutfit and not focusedChild.outfit:isColoredMount() then
      window.appearance.grayHover:setVisible(true)
    end
  end
end

function onFamiliarSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    local mountType = tonumber(focusedChild:getId())
    tempOutfit.familiar = mountType
    tempFamiliar.type = mountType
    updatePreview()
    updateAppearanceText("familiar", focusedChild.name:getText())
  end
end

function onAuraSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    tempOutfit.aura = focusedChild.aura
    tempOutfit.auraCategory = focusedChild.auraCategory
    tempOutfit.auraId = tonumber(focusedChild:getId())

    if showAuraCheck:isChecked() then
      updatePreview()
    end

    updateAppearanceText("aura", focusedChild.name:getText())
  end
end

function updateAppearanceText(widget, text)
  if widget == "preset" and text == "None" or type(text) == number then
    text = "No Preset"
  end

  local wText = window.appearance:recursiveGetChildById(widget).name
  if not wText then
    wText = window.appearance:recursiveGetChildById(widget)
  end

  wText:setText(text)
end

function updateAppearanceTexts(outfit)
  for key, value in pairs(outfit) do
    local newKey = key
    local appKey = key
    if key == "type" then
      newKey = "outfits"
      appKey = "outfit"
    else
      newKey = key .. "s"
      appKey = key
    end

    local dataTable = ServerData[newKey]
    if dataTable then
      for _, data in ipairs(dataTable) do
        if outfit[key] == data[1] or outfit[key] == data[2] then
          updateAppearanceText(appKey, data[2])
        elseif data[4] and not tonumber(data[4]) then
          updateAppearanceText(appKey, data[4])
        elseif appKey == "aura" and outfit[key] ~= 0 then
          updateAppearanceText(appKey, data[4])
        end
      end
    end
  end
end

function onAddonChange(widget, checked)
  local addonId = widget:getParent():getId()

  local addons = tempOutfit.addons
  if addonId == "addon1" then
    addons = checked and addons + 1 or addons - 1
  elseif addonId == "addon2" then
    addons = checked and addons + 2 or addons - 2
  end

  tempOutfit.addons = addons
  animatePreviewTransition(function()
    updatePreview()
  end, { nudgeTop = checked and -5 or 5, optionKey = 'showOutfitAnimationAddon' })
end

function onRandomMountChange(widget, checked)
  globalRandomMount = checked
end

function onColorModeChange(widget, selectedWidget)
  local colorMode = selectedWidget:getId()
  if colorMode == "HeadButton" then
    selectedWidget:getParent():setImageClip("0 0 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.mountHead or 0)])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.head])
    end
  elseif colorMode == "PrimaryButton" then
    selectedWidget:getParent():setImageClip("0 18 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.mountBody or 0)])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.body])
    end
  elseif colorMode == "SecondaryButton" then
    selectedWidget:getParent():setImageClip("0 36 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.mountLegs or 0)])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.legs])
    end
  elseif colorMode == "DetailButton" then
    selectedWidget:getParent():setImageClip("0 54 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.mountFeet or 0)])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.feet])
    end
  end
end

function onColorCheckChange(widget, selectedWidget)
  local colorId = selectedWidget.colorId

  if currentColorBox then
    currentColorBox:setBorderWidth(0)
    currentColorBox:setBorderColor("alpha")
    currentColorBox:setChecked(false)
  end

  selectedWidget:setBorderWidth(1)
  selectedWidget:setBorderColor("white")
  currentColorBox = selectedWidget

  local colorMode = colorModeGroup:getSelectedWidget():getId()
  if colorMode == "HeadButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountHead = colorId
    else
      tempOutfit.head = colorId
    end
  elseif colorMode == "PrimaryButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountBody = colorId
    else
      tempOutfit.body = colorId
    end
  elseif colorMode == "SecondaryButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountLegs = colorId
    else
      tempOutfit.legs = colorId
    end
  elseif colorMode == "DetailButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountFeet = colorId
    else
      tempOutfit.feet = colorId
    end
  end

  updatePreview()
  scheduleSelectionColorRefresh()
end

function updatePreview(onlyMount)
  local direction = previewCreature and previewCreature:getDirection() or 0
  local previewOutfit = tempOutfit and table.copy(tempOutfit) or {}

  if previewCreature then
    previewCreature:show()
  end

  if showMountCheck and not showMountCheck:isChecked() then
    previewOutfit.mount = 0
  end

  -- Familiar is a separate UICreature beside the character (not part of outfit draw).
  local familiarId = 0
  if showFamiliarCheck and showFamiliarCheck:isChecked() then
    familiarId = tonumber(tempOutfit and tempOutfit.familiar) or 0
    if familiarId == 0 and tempFamiliar then
      familiarId = tonumber(tempFamiliar.type) or 0
    end
  end
  if previewFamiliar then
    local wantShow = familiarId > 0
    if wantShow then
      if familiarPreviewShown then
        -- Already visible: only refresh outfit/direction (no re-animation).
        setFamiliarPreviewLook(familiarId, direction)
        if not familiarPreviewAnim.valueEvent then
          applyFamiliarPreviewProgress(1)
        end
      else
        animateFamiliarPreview(true, familiarId, direction)
      end
    elseif familiarPreviewShown then
      animateFamiliarPreview(false, familiarId, direction)
    else
      applyFamiliarPreviewProgress(0)
    end
  end

  if showAuraCheck and showAuraCheck:isChecked() then
    previewOutfit.aura = ServerData.currentOutfit.aura
    previewOutfit.auraCategory = ServerData.currentOutfit.auraCategory
    previewOutfit.auraId = ServerData.currentOutfit.auraId
    if previewCreature then
      previewCreature:setIdleAnimate(true)
    end
    if showMountCheck and showMountCheck:isChecked() then
      showMountCheck:setChecked(false)
    end
  else
    previewOutfit.aura = 0
    previewOutfit.auraCategory = 0
    previewOutfit.auraId = 0
  end

  if onlyMount and previewCreature then
    local tmpOutfit = table.copy(previewOutfit)
    tmpOutfit.type = tmpOutfit.mount
    tmpOutfit.mount = 0
    previewCreature:setOutfit(tmpOutfit)
  elseif previewCreature then
    previewCreature:setOutfit(previewOutfit)
  end

  if previewCreature then
    previewCreature:setDirection(direction)
  end

  if movementCheck and previewCreature then
    local creature = previewCreature:getCreature()
    if creature then
      creature:setStaticWalking(movementCheck:isChecked() and 1000 or 0)
      creature:setAnimate(true)
    end
  end

  if showAuraCheck and showAuraCheck:isChecked() and previewCreature then
    previewCreature:setAnimate(true)
  end
end

function rotate(value)
  local direction = previewCreature:getDirection()
  direction = direction + value
  if direction < Directions.North then
    direction = Directions.West
  elseif direction > Directions.West then
    direction = Directions.North
  end
  previewCreature:setDirection(direction)
  if previewFamiliar:isVisible() then
    previewFamiliar:setDirection(direction)
  end
end

function onFilterSearch(widget)
  local searchText = widget:getText()
  cancelPendingSearchRebuild()

  pendingSearchRebuild = scheduleEvent(function()
    pendingSearchRebuild = nil
    if not window or window:isDestroyed() then
      return
    end
    if window.appearance.outfitCheck:isChecked() then
      showOutfits(searchText)
    elseif window.appearance.mountCheck:isChecked() then
      showMounts(searchText)
    end
  end, SEARCH_DEBOUNCE_MS)
end

function onClearFilterSearch(widget)
  widget:clearText()
  cancelPendingSearchRebuild()
  if window.appearance.outfitCheck:isChecked() then
    showOutfits()
  elseif window.appearance.mountCheck:isChecked() then
    showMounts()
  end
end

function saveSettings()
  if not currentPlayerId then return end
  local characterDataFolder = "/characterdata/".. currentPlayerId .."/"
  if not g_resources.directoryExists("/characterdata/") then
    g_resources.makeDir("/characterdata/")
  end
  if not g_resources.directoryExists(characterDataFolder) then
    g_resources.makeDir(characterDataFolder)
  end
  local folder = characterDataFolder .. "outfitdialog.json"
	local status, result = pcall(function() return json.encode(presetList, 2) end)
	if not status then
		return onError("Error while saving outfits profile settings. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
	  return onError("Something went wrong, file is above 100MB, won't be saved")
	end

	g_resources.writeFileContents(folder, result)
end

function loadSettings()
  local player = g_game.getLocalPlayer()
  if player then
    currentPlayerId = player:getName()
  end
  if not currentPlayerId then return end
  local folder = "/characterdata/".. currentPlayerId .."/outfitdialog.json"
  if g_resources.fileExists(folder) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(folder))
		end)

		if not status then
			return false
		end
		presetList = result
		if presetList and presetList["customiseCharacterPresets"] then
			for _, data in ipairs(presetList["customiseCharacterPresets"]) do
				ensurePresetTimestamps(data)
			end
		end
		return true
  else
    loadDefaultSettings()
	end
end

function loadDefaultSettings()
  presetList = {
    ["configureShowOffSocketPresets"] = {},
    ["customiseCharacterPresets"] = {}
  }

end

function getPresetOutfit(data)
  local firstAddon = data["outfit"]["firstAddOn"]
  local secondAddon = data["outfit"]["secondAddOn"]

  local addons = 0
  if firstAddon and secondAddon then
    addons = 3
  elseif firstAddon and not secondAddon then
    addons = 1
  elseif not firstAddon and secondAddon then
    addons = 2
  end

  local outfit = {
    type = data["outfit"]["id"],
    head = data["outfit"]["color"]["head"],
    body = data["outfit"]["color"]["torso"],
    legs = data["outfit"]["color"]["legs"],
    feet = data["outfit"]["color"]["detail"],
    addons = addons,
    mount = data["mount"]["id"],
    mountBody = data["mount"]["color"]["torso"],
    mountHead = data["mount"]["color"]["head"],
    mountLegs = data["mount"]["color"]["legs"],
    mountFeet = data["mount"]["color"]["detail"],
    familiar = data["summon"]["id"]
  }

  return outfit
end

function getStoreMount(mountId)
  for _, data in pairs(ServerData.mounts) do
    local storeOffer = tonumber(data[3]) or 0
    if storeOffer ~= 0 and data[1] == mountId then
      return storeOffer
    end
  end
  return 0
end

function getStoreOutfit(outfitId)
  local _, storeOffer = getStoreOutfitInfo(outfitId)
  return storeOffer
end

function copyAll()
  local data = {
    type = tempOutfit.type or 0,
    addons = tempOutfit.addons or 0,
    head = tempOutfit.head or 0,
    body = tempOutfit.body or 0,
    legs = tempOutfit.legs or 0,
    feet = tempOutfit.feet or 0,
    mount = tempOutfit.mount or 0,
    aura = tempOutfit.aura or 0,
    familiar = tempOutfit.familiar or 0
  }
  g_window.setClipboardText(json.encode(data))
end

function copyColours()
  local data = {
    head = tempOutfit.head or 0,
    body = tempOutfit.body or 0,
    legs = tempOutfit.legs or 0,
    feet = tempOutfit.feet or 0
  }
  g_window.setClipboardText(json.encode(data))
end

function paste()
  local text = g_window.getClipboardText()
  if not text or text == "" then return end
  
  local status, data = pcall(function() return json.decode(text) end)
  if not status or type(data) ~= "table" then return end

  if data.head then tempOutfit.head = tonumber(data.head) or 0 end
  if data.body then tempOutfit.body = tonumber(data.body) or 0 end
  if data.legs then tempOutfit.legs = tonumber(data.legs) or 0 end
  if data.feet then tempOutfit.feet = tonumber(data.feet) or 0 end

  if data.type then tempOutfit.type = tonumber(data.type) or 0 end
  if data.addons then tempOutfit.addons = tonumber(data.addons) or 0 end
  if data.mount then tempOutfit.mount = tonumber(data.mount) or 0 end
  if data.aura then tempOutfit.aura = tonumber(data.aura) or 0 end
  if data.familiar then tempOutfit.familiar = tonumber(data.familiar) or 0 end

  updatePreview()
  
  if colorBoxGroup and colorModeGroup then
    local colorMode = colorModeGroup:getSelectedWidget():getId()
    if colorMode == "HeadButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.head or 0)])
    elseif colorMode == "PrimaryButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.body or 0)])
    elseif colorMode == "SecondaryButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.legs or 0)])
    elseif colorMode == "DetailButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.feet or 0)])
    end
  end
  configureAddons(tempOutfit.addons)
end

function randomizeColors()
  tempOutfit.head = math.random(0, 132)
  tempOutfit.body = math.random(0, 132)
  tempOutfit.legs = math.random(0, 132)
  tempOutfit.feet = math.random(0, 132)

  updatePreview()

  if colorBoxGroup and colorModeGroup then
    local colorMode = colorModeGroup:getSelectedWidget():getId()
    if colorMode == "HeadButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.head or 0)])
    elseif colorMode == "PrimaryButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.body or 0)])
    elseif colorMode == "SecondaryButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.legs or 0)])
    elseif colorMode == "DetailButton" then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. (tempOutfit.feet or 0)])
    end
  end
end

function randomizeOutfit()
  local owned = {}
  for _, data in pairs(ServerData.outfits) do
    local storeMode = getOutfitStoreInfo(data)
    if storeMode == 0 then
      table.insert(owned, data)
    end
  end

  if #owned == 0 then
    return
  end

  local data = owned[math.random(1, #owned)]
  tempOutfit.type = tonumber(data[1]) or tempOutfit.type
  tempOutfit.addons = tonumber(data[3]) or 0

  configureAddons(tempOutfit.addons)
  updatePreview()
  updateAppearanceText("outfit", data[2])

  if window and window.ScrollBar and window.ScrollBar.selectionList then
    local widget = window.ScrollBar.selectionList[data[1]]
    if widget then
      window.ScrollBar.selectionList:focusChild(widget)
      window.ScrollBar.selectionList:ensureChildVisible(widget, {x = 0, y = 196})
    end
  end
end

function onRandomizeClick(widget)
  local menu = g_ui.createWidget('PopupMenu')
  menu:addOption(tr('Randomize Outfit'), function()
    randomizeOutfit()
  end)
  menu:addOption(tr('Randomize Colors'), function()
    randomizeColors()
  end)

  local pos = { x = widget:getX(), y = widget:getY() + widget:getHeight() }
  menu:display(pos)
end

function accept()
  if g_game.getFeature(GamePlayerMounts) then
    local isMountedChecked = showMountCheck and showMountCheck:isChecked() or false
    if not isMountedChecked then
      tempOutfit.mount = 0;
    end
    g_game.mount(isMountedChecked)

    local isAuraChecked = window.configure.aura.auraCheck:isChecked()
    if not isAuraChecked then
      tempOutfit.auraId = 0
    else
      if tempOutfit.auraId == 0 then
        tempOutfit.aura = ServerData.currentOutfit.aura
        tempOutfit.auraCategory = ServerData.currentOutfit.auraCategory
        tempOutfit.auraId = ServerData.currentOutfit.auraId
      end
    end
  end

  g_game.changeOutfit(tempOutfit, globalRandomMount)
  g_client.setInputLockWidget()
  destroy()
end
