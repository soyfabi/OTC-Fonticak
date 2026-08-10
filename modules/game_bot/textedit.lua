-- Text editor dialog used by bot UIs.
-- Uses core InputBox styles so it works even when custom OTUI styles fail to load.
BotTextEditor = BotTextEditor or {}

local activeWindow

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

  local window
  if options.multiline then
    window = UIInputBox.create(title, onOk, onCancel)
    if description ~= '' then
      window:addLabel(description)
    end
    local edit = window:addTextEdit(nil, text, nil, 12)
    window:display()
    if edit and edit.focus then
      edit:focus()
      if edit.grabKeyboard then
        edit:grabKeyboard()
      end
    end
  else
    window = displayInputBox(title, description, onOk, onCancel, text)
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
