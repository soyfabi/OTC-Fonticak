-- Item ID/count picker used by BotItem slots (and any UIItem with selectable+editable).
ItemSelector = ItemSelector or {}

local activeWindow

function ItemSelector.init()
  g_ui.importStyle('ui/itemselector')
  connect(g_game, { onGameEnd = ItemSelector.destroy })
end

function ItemSelector.terminate()
  disconnect(g_game, { onGameEnd = ItemSelector.destroy })
  ItemSelector.destroy()
end

function ItemSelector.destroy()
  if activeWindow then
    activeWindow:destroy()
    activeWindow = nil
  end
end

function ItemSelector.show(itemWidget)
  if not itemWidget then
    return
  end
  if activeWindow then
    ItemSelector.destroy()
  end

  local window = g_ui.createWidget('ItemSelectorWindow', rootWidget)

  local destroy = function()
    window:destroy()
    if window == activeWindow then
      activeWindow = nil
    end
  end
  local doneFunc = function()
    itemWidget:setItem(Item.create(window.item:getItemId(), window.item:getItemCount()))
    destroy()
  end
  local clearFunc = function()
    window.item:setItemId(0)
    window.item:setItemCount(0)
    doneFunc()
  end

  window.clearButton.onClick = clearFunc
  window.okButton.onClick = doneFunc
  window.cancelButton.onClick = destroy
  window.onEnter = doneFunc
  window.onEscape = destroy

  window.item:setItem(Item.create(itemWidget:getItemId(), itemWidget:getItemCount()))
  window.itemId:setValue(itemWidget:getItemId())
  if itemWidget:getItemCount() > 1 then
    window.itemCount:setValue(itemWidget:getItemCount())
  end

  window.itemId.onValueChange = function(widget, value)
    window.item:setItemId(value)
  end
  window.itemCount.onValueChange = function(widget, value)
    window.item:setItemCount(value)
  end

  activeWindow = window
  activeWindow:raise()
  activeWindow:focus()
end

function ItemSelector.hide()
  ItemSelector.destroy()
end

-- Convenience for UIItem / external callers
function showItemSelector(itemWidget)
  ItemSelector.show(itemWidget)
end
