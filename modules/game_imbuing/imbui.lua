return function(context)
  local imbuementApi = {
    window = nil,
    selectItemOrScroll = nil,
    scrollImbue = nil,
    selectImbue = nil,
    clearImbue = nil,

    messageWindow = nil,

    bankGold = 0,
    inventoryGold = 0,
  }

  imbuementApi.__index = imbuementApi

  imbuementApi.MessageDialog = {
    ImbuementSuccess = 0,
    ImbuementError = 1,
    ImbuementRollFailed = 2,
    ImbuingStationNotFound = 3,
    ClearingCharmSuccess = 10,
    ClearingCharmError = 11,
    PreyMessage = 20,
    PreyError = 21,
  }

  local self = imbuementApi
  local EMPTY_ARROW = "/images/game/forge/icon-arrow-rightlarge"
  local FILLED_ARROW = "/images/game/forge/icon-arrow-rightlarge-filled"
  local IMBUING_BLINK_SHADER = "Item - ImbueBlink"

  local function ensureBlinkShader()
    if g_shaders and g_shaders.getShader and not g_shaders.getShader(IMBUING_BLINK_SHADER) then
      g_shaders.createFragmentShader(IMBUING_BLINK_SHADER, "/modules/game_forge/menu/shaders/blink_white.frag", false)
    end
  end

  local function setWidgetShader(widget, shaderName)
    if not widget then return end
    local shader = shaderName or ""
    if widget.setShader then
      widget:setShader(shader)
    end
    if widget.getItem and widget:getItem() and widget:getItem().setShader then
      widget:getItem():setShader(shaderName)
    end
  end

  local function getGoldBarWidth(text)
    return math.min(240, math.max(150, (#tostring(text) * 7) + 34))
  end

  function imbuementApi.playTimeBarParticles(window)
    local targetWindow = window or self.clearImbue or self.window
    if not targetWindow then
      return
    end

    local timeWidget = targetWindow:recursiveGetChildById("time") or targetWindow:recursiveGetChildById("timeRemaining")
    if not timeWidget then
      return
    end

    local timePos = timeWidget:getPosition()
    local centerX = timePos.x + math.floor(timeWidget:getWidth() / 2)
    local centerY = timePos.y + math.floor(timeWidget:getHeight() / 2)
    local width = timeWidget:getWidth()

    local colors = { "#FFD83D", "#FFFFFF", "#FFF2A8", "#FFA834" }

    local function burst(count, spreadX)
      if not targetWindow or targetWindow:isDestroyed() then
        return
      end

      for i = 1, count do
        local particle = g_ui.createWidget("UIWidget", targetWindow)
        local angle = (math.pi * 2 * i / count) + (math.random() * 0.4 - 0.2)
        local distance = 18 + math.random(0, 32)
        local startX = centerX + math.random(-math.floor(spreadX / 2), math.floor(spreadX / 2))
        local startY = centerY + math.random(-4, 4)
        local targetX = math.floor(startX + math.cos(angle) * distance)
        local targetY = math.floor(startY + math.sin(angle) * distance)

        particle:setSize({ width = 8, height = 8 })
        particle:setImageSource("/particles/particle.png")
        particle:setColor(colors[math.random(1, #colors)])
        particle:setOpacity(1)
        particle:setPosition({ x = startX, y = startY })
        particle:raise()

        local startedAt = g_clock.millis()
        local function animateParticle()
          if not particle or particle:isDestroyed() then
            return
          end

          local progress = math.min((g_clock.millis() - startedAt) / 750, 1)
          local eased = 1 - math.pow(1 - progress, 3)
          particle:setPosition({
            x = math.floor(startX + (targetX - startX) * eased),
            y = math.floor(startY + (targetY - startY) * eased)
          })
          particle:setOpacity(1 - progress)

          if progress < 1 then
            scheduleEvent(animateParticle, 16)
          else
            particle:destroy()
          end
        end

        animateParticle()
      end
    end

    burst(28, math.floor(width * 0.75))
    scheduleEvent(function() burst(22, math.floor(width * 0.85)) end, 120)
    scheduleEvent(function() burst(16, math.floor(width * 0.6)) end, 240)
  end

  local function getAnimationItemWidgets(targetWindow)
    local widgets = {}
    if not targetWindow then
      return widgets
    end

    local requiredItems = targetWindow:recursiveGetChildById("requiredItems")
    if requiredItems then
      for _, child in ipairs(requiredItems:getChildren()) do
        if child:isVisible() then
          local itemChild = child.item or child:getChildById("item")
          if itemChild and itemChild.getItemId and itemChild:getItemId() > 0 then
            table.insert(widgets, itemChild)
          elseif child.getItemId and child:getItemId() > 0 then
            table.insert(widgets, child)
          end
        end
      end
    end

    local itemScroll = targetWindow:recursiveGetChildById("itemScroll")
    if itemScroll and itemScroll:isVisible() then
      table.insert(widgets, itemScroll)
    end

    local itemOrScrollContent = targetWindow:recursiveGetChildById("itemOrScrollContent")
    if itemOrScrollContent then
      local mainItem = itemOrScrollContent:getChildById("item")
      if mainItem and mainItem:isVisible() then
        table.insert(widgets, mainItem)
      end
    end

    return widgets
  end

  function imbuementApi.playArrowAnimation(window)
    local targetWindow = window or self.window
    if not targetWindow then
      return
    end

    local arrow1 = targetWindow:recursiveGetChildById("horizontalArrow1")
    local arrow2 = targetWindow:recursiveGetChildById("horizontalArrow2")
    if not arrow1 or not arrow2 then
      return
    end

    ensureBlinkShader()
    local itemWidgets = getAnimationItemWidgets(targetWindow)

    if arrow1.animEvents then
      for _, ev in ipairs(arrow1.animEvents) do
        removeEvent(ev)
      end
    end
    arrow1.animEvents = {}
    self.isAnimatingArrows = true

    local function flashItem(on)
      local shader = on and IMBUING_BLINK_SHADER or nil
      for _, widget in ipairs(itemWidgets) do
        setWidgetShader(widget, shader)
      end
    end

    local function addAnim(fn, delay)
      local ev = scheduleEvent(function()
        if arrow1 and arrow2 then
          fn()
        end
      end, delay)
      table.insert(arrow1.animEvents, ev)
    end

    arrow1:setImageSource(EMPTY_ARROW)
    arrow2:setImageSource(EMPTY_ARROW)
    flashItem(false)

    -- Wave 1 (Fast / energetic start)
    addAnim(function() arrow1:setImageSource(FILLED_ARROW); flashItem(true) end, 20)
    addAnim(function() arrow1:setImageSource(EMPTY_ARROW); arrow2:setImageSource(FILLED_ARROW); flashItem(false) end, 110)
    addAnim(function() arrow2:setImageSource(EMPTY_ARROW) end, 200)

    -- Wave 2 (Medium speed)
    addAnim(function() arrow1:setImageSource(FILLED_ARROW); flashItem(true) end, 240)
    addAnim(function() arrow1:setImageSource(EMPTY_ARROW); arrow2:setImageSource(FILLED_ARROW); flashItem(false) end, 370)
    addAnim(function() arrow2:setImageSource(EMPTY_ARROW) end, 500)

    -- Wave 3 (Slower / decelerating)
    addAnim(function() arrow1:setImageSource(FILLED_ARROW); flashItem(true) end, 560)
    addAnim(function() arrow1:setImageSource(EMPTY_ARROW); arrow2:setImageSource(FILLED_ARROW); flashItem(false) end, 730)
    addAnim(function() arrow2:setImageSource(EMPTY_ARROW) end, 900)

    -- Final confirmation glow (solid hold + bright white flash)
    addAnim(function()
      arrow1:setImageSource(FILLED_ARROW)
      arrow2:setImageSource(FILLED_ARROW)
      flashItem(true)
    end, 970)

    addAnim(function()
      arrow1:setImageSource(EMPTY_ARROW)
      arrow2:setImageSource(EMPTY_ARROW)
      flashItem(false)
      self.isAnimatingArrows = false
      if self.pendingUpdate then
        local cb = self.pendingUpdate
        self.pendingUpdate = nil
        cb()
        imbuementApi.playTimeBarParticles(self.clearImbue)
      end
    end, 1250)
  end

  function imbuementApi.ensureWindow()
    if self.window then
      return
    end

    self.window = g_ui.displayUI('imbui')
    self.selectItemOrScroll = self.window:recursiveGetChildById('selectItemOrScroll')
    self.scrollImbue = self.window:recursiveGetChildById('scrollImbue')
    self.selectImbue = self.window:recursiveGetChildById('selectImbue')
    self.clearImbue = self.window:recursiveGetChildById('clearImbue')
    self:hide()
  end

  function imbuementApi.destroyWindow()
    self.selectItemOrScroll = nil
    self.scrollImbue = nil
    self.selectImbue = nil
    self.clearImbue = nil

    if self.window then
      self.window:destroy()
      self.window = nil
    end
  end

  function imbuementApi.init()
  end

  function imbuementApi.terminate()
    if self.messageWindow then
      self.messageWindow:destroy()
      self.messageWindow = nil
    end

    if context.item then
      context.item:shutdown()
    end
    if context.selection then
      context.selection:shutdown()
    end
    if context.scroll then
      context.scroll:shutdown()
    end
    self.destroyWindow()
  end

  function imbuementApi.online()
    self:hide()
    if self.messageWindow then
      self.messageWindow:destroy()
      self.messageWindow = nil
    end
  end

  function imbuementApi.offline()
    self:hide()
    if context.item then
      context.item:shutdown()
    end
    if context.scroll then
      context.scroll:shutdown()
    end
    if context.selection then
      context.selection:shutdown()
    end
    if self.messageWindow then
      self.messageWindow:destroy()
      self.messageWindow = nil
    end
    self.destroyWindow()
  end

  function imbuementApi:startLiveRefresh()
    if self.liveRefreshEvent then
      return
    end

    self.liveRefreshEvent = cycleEvent(function()
      if not self.window or not self.window:isVisible() then
        self:stopLiveRefresh()
        return
      end

      self:updateGold()

      if context.item and context.item.refreshSelected then
        context.item.refreshSelected()
      end
      if context.scroll and context.scroll.refreshSelected then
        context.scroll.refreshSelected()
      end
    end, 200)
  end

  function imbuementApi:stopLiveRefresh()
    if self.liveRefreshEvent then
      removeEvent(self.liveRefreshEvent)
      self.liveRefreshEvent = nil
    end
  end

  function imbuementApi.show()
    self.ensureWindow()
    self:updateGold()
    self.window:show(true)
    self.window:raise()
    self.window:focus()
    self:startLiveRefresh()
    if self.messageWindow then
      self.messageWindow:destroy()
      self.messageWindow = nil
    end
  end

  function imbuementApi.hide()
    self:stopLiveRefresh()
    if self.window then
      self.window:hide()
    end
  end

  function imbuementApi.close()
    self:stopLiveRefresh()
    if g_game.isOnline() then
      g_game.closeImbuingWindow()
    end
    if self.window then
      self.window:hide()
    end
  end

  function imbuementApi:updateGold()
    if not self.window then
      return
    end

    local totalGold = context.getPlayerBalance()
    local formattedGold = context.commaValue(totalGold)
    local goldPanel = self.window.contentPanel and self.window.contentPanel.gold
    if goldPanel then
      goldPanel:setWidth(getGoldBarWidth(formattedGold))
      if goldPanel.gold then
        goldPanel.gold:setText(formattedGold)
      end
    end
  end

  function imbuementApi:toggleMenu(menu)
    self.currentMenu = menu
    local panels = {
      selectItemOrScroll = self.selectItemOrScroll,
      scrollImbue = self.scrollImbue,
      selectImbue = self.selectImbue,
      clearImbue = self.clearImbue,
    }

    for key, widget in pairs(panels) do
      if widget and widget.show and widget.hide then
        if key == menu then
          widget:show()
          local itemBtn = widget:recursiveGetChildById('itemButton')
          local scrollBtn = widget:recursiveGetChildById('scrollButton')

          if menu == 'selectItemOrScroll' then
            self.window:setHeight(388)
            if itemBtn then itemBtn:setOn(false) end
            if scrollBtn then scrollBtn:setOn(false) end
          elseif menu == 'scrollImbue' then
            self.window:setHeight(655)
            if itemBtn then itemBtn:setOn(false) end
            if scrollBtn then scrollBtn:setOn(true) end
          elseif menu == 'selectImbue' then
            self.window:setHeight(528)
            if itemBtn then itemBtn:setOn(true) end
            if scrollBtn then scrollBtn:setOn(false) end
          elseif menu == 'clearImbue' then
            self.window:setHeight(502)
            if itemBtn then itemBtn:setOn(true) end
            if scrollBtn then scrollBtn:setOn(false) end
          end
        else
          widget:hide()
        end
      end
    end
  end

  function imbuementApi.onOpenImbuementWindow()
    self.ensureWindow()
    self:show()

    self:toggleMenu("selectItemOrScroll")
  end

  function imbuementApi.onResourcesBalanceChange(_, _, resourceType)
    if resourceType == ResourceTypes.BANK_BALANCE or resourceType == ResourceTypes.GOLD_EQUIPPED then
      self:updateGold()
    end
  end

  function imbuementApi.onImbuementItem(itemId, tier, slots, activeSlots, availableImbuements, needItems, itemName)
    self.ensureWindow()
    local needItemsTable = {}

    for _, item in ipairs(needItems) do
      if item and item.getId then
        local itemId = item:getId()
        local count = item:getCount() or 0
        needItemsTable[itemId] = count
      end
    end

    local function applyUpdate()
      self:show()
      self:toggleMenu("selectImbue")
      context.item.setup(itemId, tier, slots, activeSlots, availableImbuements, needItemsTable, itemName)
    end

    if self.isAnimatingArrows then
      self.pendingUpdate = applyUpdate
    else
      applyUpdate()
    end
  end

  function imbuementApi.onImbuementScroll(availableImbuements, needItems)
    self.ensureWindow()
    local needItemsTable = {}

    for _, item in ipairs(needItems) do
      if item and item.getId then
        local itemId = item:getId()
        local count = item:getCount() or 0
        needItemsTable[itemId] = count
      end
    end

    local function applyUpdate()
      self:show()
      self:toggleMenu("scrollImbue")
      context.scroll.setup(availableImbuements, needItemsTable)
    end

    if self.isAnimatingArrows then
      self.pendingUpdate = applyUpdate
    else
      applyUpdate()
    end
  end

  function imbuementApi.onSelectItem()
    self:hide()
    context.selection:selectItem()
  end

  function imbuementApi.onSelectScroll()
    if self.currentMenu == 'scrollImbue' then
      return
    end
    g_game.selectImbuementScroll()
  end

  function imbuementApi.onMessageDialog(type, content)
    if not self.window then
      return
    end

    if self.messageWindow then
      self.messageWindow:destroy()
      self.messageWindow = nil
    end

    local function confirm()
      if self.messageWindow then
        self.messageWindow:destroy()
        self.messageWindow = nil
      end
    end

    self.messageWindow = displayGeneralBox(tr('Message Dialog'), content or "",
      { { text=tr('Ok'), callback=confirm },
      }, confirm, confirm)
  end

  return imbuementApi
end
