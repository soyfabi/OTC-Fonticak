-- Text editor dialog used by bot UIs.
-- Uses core InputBox styles so it works even when custom OTUI styles fail to load.
BotTextEditor = BotTextEditor or {}

local activeWindow
local DEFAULT_WIDTH = 420

function BotTextEditor.init()
  connect(g_game, { onGameEnd = BotTextEditor.destroy })
end

function BotTextEditor.terminate()
  disconnect(g_game, { onGameEnd = BotTextEditor.destroy })
  BotTextEditor.destroy()
end

function BotTextEditor.destroy()
  if activeWindow and not activeWindow:isDestroyed() then
    activeWindow:destroy()
  end
  activeWindow = nil
end

local function normalizeArgs(text, options, callback)
  if type(text) == 'userdata' then
    local widget = text
    callback = function(newText)
      if widget and not widget:isDestroyed() then
        widget:setText(newText)
      end
    end
    text = widget:getText()
  elseif type(text) == 'number' then
    text = tostring(text)
  elseif type(text) == 'nil' then
    text = ''
  elseif type(text) ~= 'string' then
    error("Invalid text type for BotTextEditor: " .. type(text))
  end

  if type(options) == 'function' then
    callback = options
    options = {}
  end
  options = options or {}
  return text, options, callback
end

-- InputBoxLabel is fixed-size and does not wrap. Long text paints outside the window.
local function addDescriptionLabels(window, description)
  local labels = {}
  if not description or description == '' then
    return labels
  end
  for line in description:gmatch('[^\r\n]+') do
    table.insert(labels, window:addLabel(line))
  end
  return labels
end

local function fitDescriptionLabels(window, labels)
  local padding = (window:getPaddingLeft() or 0) + (window:getPaddingRight() or 0)
  local contentWidth = math.max(80, window:getWidth() - padding)

  for _, label in ipairs(labels) do
    if label and not label:isDestroyed() then
      label:setFixedSize(false)
      label:setTextWrap(true)
      label:setTextHorizontalAutoResize(false)
      label:setTextVerticalAutoResize(true)
      label:setWidth(contentWidth)
    end
  end
end

-- also works as BotTextEditor.show(text, callback)
function BotTextEditor.show(text, options, callback) -- callback = function(newText)
  text, options, callback = normalizeArgs(text, options, callback)

  BotTextEditor.destroy()

  local title = options.title or tr('Edit text')
  local description = options.description or ''

  local function onOk(newText)
    activeWindow = nil
    if callback then
      callback(tostring(newText or ''))
    end
  end

  local function onCancel()
    activeWindow = nil
  end

  local window = UIInputBox.create(title, onOk, onCancel)
  local labels = addDescriptionLabels(window, description)

  local edit
  if options.multiline then
    edit = window:addTextEdit(nil, text, nil, options.rows or 12)
  else
    edit = window:addLineEdit(nil, text, options.maxLength)
  end

  -- display() reapplies InputBoxWindow style (default width 260); set size after that
  window:display()
  window:setWidth(options.width or DEFAULT_WIDTH)
  if options.height then
    window:setHeight(options.height)
  end
  fitDescriptionLabels(window, labels)

  if edit and edit.focus then
    edit:focus()
    if options.multiline and edit.grabKeyboard then
      edit:grabKeyboard()
    end
  end

  activeWindow = window
  if activeWindow then
    activeWindow:raise()
    activeWindow:focus()
  end
  return activeWindow
end

function BotTextEditor.hide()
  BotTextEditor.destroy()
end

function BotTextEditor.edit(...)
  return BotTextEditor.show(...)
end

function BotTextEditor.singlelineEditor(text, callback)
  return BotTextEditor.show(text, {}, callback)
end

function BotTextEditor.multilineEditor(description, text, callback)
  return BotTextEditor.show(text, { description = description, multiline = true }, callback)
end

function showTextEdit(...)
  return BotTextEditor.show(...)
end

function editText(...)
  return BotTextEditor.edit(...)
end

function hideTextEdit()
  return BotTextEditor.hide()
end

function singlelineEditor(...)
  return BotTextEditor.singlelineEditor(...)
end

function multilineEditor(...)
  return BotTextEditor.multilineEditor(...)
end

-- Old bot configs in %APPDATA% still call modules.client_textedit.*
package.loaded['client_textedit'] = {
  show = showTextEdit,
  edit = editText,
  hide = hideTextEdit,
  singlelineEditor = singlelineEditor,
  multilineEditor = multilineEditor
}
