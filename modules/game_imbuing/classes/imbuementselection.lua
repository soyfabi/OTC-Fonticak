return function(context)
  local selectionApi = {
    pickItem = nil,
    isSelectingScroll = false,
    isSelecting = false,
  }

  selectionApi.__index = selectionApi

  local self = selectionApi

  local function setTargetCursor()
    if modules.client_options and modules.client_options.getOption and modules.client_options.getOption('nativeCursor') then
      g_window.setSystemCursor('cross')
    else
      g_mouse.pushCursor('target')
    end
  end

  local function restoreCursor()
    if modules.client_options and modules.client_options.getOption and modules.client_options.getOption('nativeCursor') then
      g_window.restoreMouseCursor()
    end
    g_mouse.popCursor('target')
  end

  function selectionApi.startUp()
    self.pickItem = g_ui.createWidget('UIWidget')
    self.pickItem:setVisible(false)
    self.pickItem:setFocusable(false)
    self.pickItem.onMouseRelease = self.onChooseItemMouseRelease
  end

  function selectionApi:shutdown()
    if self.pickItem then
      self.pickItem:ungrabMouse()
      self.pickItem:destroy()
      self.pickItem = nil
    end

    if self.isSelecting then
      restoreCursor()
    end
    self.isSelectingScroll = false
    self.isSelecting = false
  end

  function selectionApi:selectItem()
    if not self.pickItem then
      self:startUp()
    end

    if g_mouse.isPressed() or self.isSelecting then
      return
    end

    self.isSelectingScroll = false
    self.isSelecting = true
    self.pickItem:grabMouse()
    setTargetCursor()
  end

  function selectionApi:selectScroll()
    if not self.pickItem then
      self:startUp()
    end

    if g_mouse.isPressed() or self.isSelecting then
      return
    end

    self.isSelectingScroll = true
    self.isSelecting = true
    self.pickItem:grabMouse()
    setTargetCursor()
  end

  function selectionApi.onChooseItemMouseRelease(widget, mousePosition, mouseButton)
    if mouseButton == MouseRightButton then
      self.pickItem:ungrabMouse()
      restoreCursor()
      self.isSelectingScroll = false
      self.isSelecting = false
      if context.imbuement and context.imbuement.show then
        context.imbuement.show()
      end
      return true
    end

    local item = nil
    if mouseButton == MouseLeftButton then
      local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
      if clickedWidget then
        if clickedWidget:getClassName() == 'UIGameMap' then
          local tile = clickedWidget:getTile(mousePosition)
          if tile then
            local thing = tile:getTopMoveThing()
            if thing and thing:isItem() then
              item = thing
            end
          end
        elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
          item = clickedWidget:getItem()
        end
      end
    end

    if item and item:isPickupable() then
      local pos = item:getPosition()
      local itemId = item:getId()
      local stackPos = item:getStackPos()

      if self.isSelectingScroll then
        g_game.selectImbuementScroll()
      else
        g_game.selectImbuementItem(itemId, pos, stackPos)
      end

      self.pickItem:ungrabMouse()
      restoreCursor()
      self.isSelectingScroll = false
      self.isSelecting = false

      return true
    else
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      if context.imbuement and context.imbuement.show then
        context.imbuement.show()
      end
    end

    self.pickItem:ungrabMouse()
    restoreCursor()
    self.isSelectingScroll = false
    self.isSelecting = false
    return true
  end

  return selectionApi
end
