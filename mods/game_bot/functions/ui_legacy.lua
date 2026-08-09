local context = G.botContext

-- DO NOT USE THIS CODE.
-- IT'S ONLY HERE FOR BACKWARD COMPATIBILITY, MAY BE REMOVED IN THE FUTURE

context.createWidget = function(name, parent)
  if parent == nil then
    parent = context.panel
  end
  g_ui.createWidget(name, parent)
end

context.setupUI = function(otml, parent)
  if parent == nil then
    parent = context.panel
  end
  local widget = g_ui.loadUIFromString(otml, parent)
  widget.botWidget = true
  return widget
end

context.importStyle = function(otml)
  if type(otml) ~= "string" then
    return error("Invalid parameter for importStyle, should be string")
  end
  if otml:find(".otui") and not otml:find("\n") then
    -- normalize "/cavebot/x.otui" → configDir/cavebot/x.otui (avoid // which breaks some clients)
    local relative = otml:gsub("^/+", "")
    return g_ui.importStyle(context.configDir .. "/" .. relative)
  end
  return g_ui.importStyleFromString(otml)
end

-- Prefer Verdana; only step down when labels do not fit up to the bar limit
local TAB_FONTS = {
  "verdana-11px-antialised",
  "small-9px",
  "verdana-8px-rounded",
  "verdana-7px-rounded",
}

local function fitBotTabs()
  local tabsWidget = context.tabs
  if not tabsWidget or not tabsWidget.tabs then
    return
  end

  tabsWidget.fitTabs = fitBotTabs

  local tabs = tabsWidget.tabs
  local count = #tabs
  if count == 0 then
    return
  end

  local spacing = tabsWidget.tabSpacing or 1
  local gaps = math.max(0, count - 1) * spacing
  -- Limit = full tab bar width (ends where content meets the right edge / scrollbar)
  local available = (tabsWidget.buttonsPanel or tabsWidget):getWidth()
  if not available or available <= 0 then
    available = tabsWidget:getWidth()
  end
  if not available or available <= 0 then
    return
  end
  available = math.max(0, available - gaps)

  local padL = count >= 7 and 1 or 2
  local padR = count >= 7 and 1 or 2

  local function measure(fontName)
    local widths = {}
    local total = 0
    for i, t in ipairs(tabs) do
      t:setFont(fontName)
      if t.setTextHorizontalAutoResize then
        t:setTextHorizontalAutoResize(false)
      end
      if t.setPaddingLeft then
        t:setPaddingLeft(padL)
        t:setPaddingRight(padR)
      end
      t:setMarginLeft(i == 1 and 0 or spacing)
      widths[i] = math.max(12, t:getTextSize().width + padL + padR)
      total = total + widths[i]
    end
    return widths, total
  end

  local function applyWidths(widths, total)
    if not (total > 0 and available > 0) then
      return widths
    end
    if available >= total then
      local extra = available - total
      local used = 0
      for i = 1, count - 1 do
        local grow = math.floor(extra * (widths[i] / total))
        widths[i] = widths[i] + grow
        used = used + widths[i]
      end
      widths[count] = available - used
    else
      local scale = available / total
      local used = 0
      for i = 1, count - 1 do
        widths[i] = math.max(12, math.floor(widths[i] * scale))
        used = used + widths[i]
      end
      widths[count] = math.max(12, available - used)
    end
    return widths
  end

  -- 1) Verdana if it fits the limit. 2) Else small-9px, then smaller.
  local widths, total = measure(TAB_FONTS[1])
  if total > available then
    for i = 2, #TAB_FONTS do
      widths, total = measure(TAB_FONTS[i])
      if total <= available then
        break
      end
    end
  end
  widths = applyWidths(widths, total)

  for i, t in ipairs(tabs) do
    t:breakAnchors()
    t:addAnchor(AnchorTop, "parent", AnchorTop)
    if i == 1 then
      t:addAnchor(AnchorLeft, "parent", AnchorLeft)
    else
      t:addAnchor(AnchorLeft, "prev", AnchorRight)
    end
    t:setWidth(widths[i])
  end
end

context.addTab = function(name)
  local tab = context.tabs:getTab(name)
  if tab then -- return existing tab
    return tab.tabPanel.content
  end

  local newTab = context.tabs:addTab(name, g_ui.createWidget("BotPanel")).tabPanel.content
  context.tabs:setOn(true)
  fitBotTabs()
  context.scheduleEvent(fitBotTabs, 50)
  context.scheduleEvent(fitBotTabs, 250)

  return newTab
end
context.getTab = context.addTab
context.fitBotTabs = fitBotTabs
if context.tabs then
  context.tabs.fitTabs = fitBotTabs
end

context.setDefaultTab = function(name)
  local tab = context.addTab(name)
  context.panel = tab
end

context.addSwitch = function(id, text, onClickCallback, parent)
  if not parent then
    parent = context.panel
  end
  local switch = g_ui.createWidget('BotSwitch', parent)
  switch:setId(id)
  switch:setText(text)
  switch.onClick = onClickCallback
  return switch
end

context.addButton = function(id, text, onClickCallback, parent)
  if not parent then
    parent = context.panel
  end
  local button = g_ui.createWidget('BotButton', parent)
  button:setId(id)
  button:setText(text)
  button.onClick = onClickCallback
  return button
end

context.addLabel = function(id, text, parent)
  if not parent then
    parent = context.panel
  end
  local label = g_ui.createWidget('BotLabel', parent)
  label:setId(id)
  label:setText(text)
  return label
end

context.addTextEdit = function(id, text, onTextChangeCallback, parent)
  if not parent then
    parent = context.panel
  end
  local widget = g_ui.createWidget('BotTextEdit', parent)
  widget:setId(id)
  widget.onTextChange = onTextChangeCallback
  widget:setText(text)
  return widget
end

context.addSeparator = function(id, parent)
  if not parent then
    parent = context.panel
  end
  local separator = g_ui.createWidget('BotSeparator', parent)
  separator:setId(id)
  return separator
end

context._addMacroSwitch = function(name, keys, parent)
  if not parent then
    parent = context.panel
  end
  local text = name
  if keys:len() > 0 then
    text = name .. " [" .. keys .. "]"
  end
  local switch = context.addSwitch("macro_" .. #context._macros, text, function(widget)
    context.storage._macros[name] = not context.storage._macros[name]
    widget:setOn(context.storage._macros[name])
  end, parent)
  switch:setOn(context.storage._macros[name])
  return switch
end

context._addHotkeySwitch = function(name, keys, parent)
  if not parent then
    parent = context.panel
  end
  local text = name
  if keys:len() > 0 then
    text = name .. " [" .. keys .. "]"
  end
  local switch = context.addSwitch("hotkey_" .. #context._hotkeys, text, nil, parent)
  switch:setOn(false)
  return switch
end
