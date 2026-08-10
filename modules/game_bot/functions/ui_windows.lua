local context = G.botContext
if type(context.UI) ~= "table" then
  context.UI = {}
end
local UI = context.UI

UI.EditorWindow = function(text, options, callback)
  --[[
    Available options:
    title = text
    description = text
    multiline = true / false
    width = number
    validation = text (regex)
    examples = {{name, text}, {name, text}}
  ]]--
  local window = modules.game_bot.editText(text, options, callback)
  if window then
    window.botWidget = true
  end
  return window
end

UI.SinglelineEditorWindow = function(text, options, callback)
  options = options or {}
  options.multiline = false
  return UI.EditorWindow(text, options, callback)
end

UI.MultilineEditorWindow = function(text, options, callback)
  options = options or {}
  options.multiline = true
  return UI.EditorWindow(text, options, callback)
end

UI.ConfirmationWindow = function(title, question, callback)
  local window = nil
  local onConfirm = function()
    window:destroy()
    callback()
  end
  local closeWindow = function()
    window:destroy()
  end
  window = context.displayGeneralBox(title, question, {
    { text=tr('No'), callback=closeWindow },
    { text=tr('Yes'), callback=onConfirm },
    anchor=AnchorHorizontalCenter}, onConfirm, closeWindow)
  window.botWidget = true
  return window
end
