-- Miniwindow that hosts optional side buttons (used by some bot UIs).
BotButtons = BotButtons or {}

BotButtons.window = nil
BotButtons.panel = nil

function BotButtons.init()
  BotButtons.window = g_ui.loadUI('ui/buttons', modules.game_interface.getRightPanel())
  if not BotButtons.window then
    return
  end
  BotButtons.window:disableResize()
  BotButtons.window:setup()
  BotButtons.panel = BotButtons.window.contentsPanel
  if not BotButtons.window.forceOpen or not BotButtons.panel or not BotButtons.panel.buttons then
    BotButtons.window:close()
  end

  -- Keep legacy module name working for old configs.
  package.loaded['game_buttons'] = package.loaded['game_buttons'] or {}
  local legacy = package.loaded['game_buttons']
  legacy.buttonsWindow = BotButtons.window
  legacy.takeButton = BotButtons.takeButton
  legacy.takeButtons = BotButtons.takeButtons
  legacy.updateOrder = BotButtons.updateOrder
end

function BotButtons.terminate()
  if BotButtons.window and not BotButtons.window:isDestroyed() then
    BotButtons.window:destroy()
  end
  BotButtons.window = nil
  BotButtons.panel = nil
  if package.loaded['game_buttons'] then
    package.loaded['game_buttons'].buttonsWindow = nil
  end
end

function BotButtons.takeButtons(buttons)
  if not BotButtons.window or not BotButtons.window.forceOpen or not BotButtons.panel or not BotButtons.panel.buttons then
    return
  end
  for _, button in ipairs(buttons) do
    BotButtons.takeButton(button, true)
  end
  BotButtons.updateOrder()
end

function BotButtons.takeButton(button, dontUpdateOrder)
  if not BotButtons.window or not BotButtons.window.forceOpen or not BotButtons.panel or not BotButtons.panel.buttons then
    return
  end
  button:setParent(BotButtons.panel.buttons)
  if not dontUpdateOrder then
    BotButtons.updateOrder()
  end
end

function BotButtons.updateOrder()
  if not BotButtons.panel or not BotButtons.panel.buttons then
    return
  end
  local children = BotButtons.panel.buttons:getChildren()
  table.sort(children, function(a, b)
    return (a.index or 1000) < (b.index or 1000)
  end)
  BotButtons.panel.buttons:reorderChildren(children)
  local visibleCount = 0
  for _, child in ipairs(children) do
    if child:isVisible() then
      visibleCount = visibleCount + 1
    end
  end
  if visibleCount > 6 and BotButtons.window and BotButtons.window:getHeight() < 30 then
    BotButtons.window:setHeight(BotButtons.window:getHeight() + 22)
  end
end

-- Flat aliases on game_bot module
function takeButton(...)
  return BotButtons.takeButton(...)
end

function takeButtons(...)
  return BotButtons.takeButtons(...)
end

-- Analyzer and old scripts read modules.game_buttons.buttonsWindow
function getButtonsWindow()
  return BotButtons.window
end
