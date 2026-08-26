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
  local function getGoldBarWidth(text)
    return math.min(240, math.max(150, (#tostring(text) * 7) + 34))
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

    self:show()
    self:toggleMenu("selectImbue")
    context.item.setup(itemId, tier, slots, activeSlots, availableImbuements, needItemsTable, itemName)
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

    self:show()
    self:toggleMenu("scrollImbue")
    context.scroll.setup(availableImbuements, needItemsTable)
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
