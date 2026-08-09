TargetBot.Creature.edit = function(config, callback) -- callback = function(newConfig)
  config = config or {}

  local editor = UI.createWindow('TargetBotCreatureEditorWindow')
  local values = {} -- (key, function returning value of key)

  editor.name:setText(config.name or "")
  table.insert(values, {"name", function() return editor.name:getText() end})

  local addScrollBar = function(id, title, min, max, defaultValue)
    local widget = UI.createWidget('TargetBotCreatureEditorScrollBar', editor.content.left)
    widget.scroll.onValueChange = function(scroll, value)
      widget.text:setText(title .. ": " .. value)
    end
    widget.scroll:setRange(min, max)
    if max-min > 1000 then
      widget.scroll:setStep(100)
    elseif max-min > 100 then
      widget.scroll:setStep(10)
    end
    widget.scroll:setValue(config[id] or defaultValue)
    widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
    table.insert(values, {id, function() return widget.scroll:getValue() end})
  end

  local addTextEdit = function(id, title, defaultValue)
    local widget = UI.createWidget('TargetBotCreatureEditorTextEdit', editor.content.right)
    widget.text:setText(title)
    widget.textEdit:setText(config[id] or defaultValue or "")

    local openEditor = function()
      if not modules.client_textedit or not modules.client_textedit.show then
        return
      end
      local window = modules.client_textedit.show(widget.textEdit, {
        title = title,
        description = "Edit " .. title
      })
      if window then
        schedule(50, function()
          if window and window.raise and not window:isDestroyed() then
            window:raise()
            window:focus()
          end
        end)
      end
    end

    -- TextEdit inside ScrollablePanel often ignores keyboard; open popup editor instead
    widget.textEdit.onMouseRelease = function(w, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        openEditor()
        return true
      end
    end
    widget.onMouseRelease = function(w, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        openEditor()
        return true
      end
    end

    table.insert(values, {id, function() return widget.textEdit:getText() end})
  end

  local addCheckBox = function(id, title, defaultValue)
    local widget = UI.createWidget('TargetBotCreatureEditorCheckBox', editor.content.right)
    widget.onClick = function()
      widget:setOn(not widget:isOn())
    end
    widget:setText(title)
    if config[id] == nil then
      widget:setOn(defaultValue)
    else
      widget:setOn(config[id])
    end
    table.insert(values, {id, function() return widget:isOn() end})
  end

  local addItem = function(id, title, defaultItem)
    local widget = UI.createWidget('TargetBotCreatureEditorItem', editor.content.right)
    widget.text:setText(title)
    widget.item:setItemId(config[id] or defaultItem)
    table.insert(values, {id, function() return widget.item:getItemId() end})
  end

  editor.cancel.onClick = function()
    editor:destroy()
  end
  editor.onEscape = editor.cancel.onClick

  editor.ok.onClick = function()
    local newConfig = {}
    for _, value in ipairs(values) do
      newConfig[value[1]] = value[2]()
    end
    if newConfig.name:len() < 1 then return end

    newConfig.regex = ""
    for part in string.gmatch(newConfig.name, "[^,]+") do
      if newConfig.regex:len() > 0 then
        newConfig.regex = newConfig.regex .. "|"
      end
      newConfig.regex = newConfig.regex .. "^" .. part:trim():lower():gsub("%*", ".*"):gsub("%?", ".?") .. "$"
    end

    editor:destroy()
    callback(newConfig)
  end

  -- values
  addScrollBar("priority", "Priority", 0, 10, 1)
  addScrollBar("danger", "Danger", 0, 10, 1)
  addScrollBar("maxDistance", "Max distance", 1, 10, 10)
  addScrollBar("keepDistanceRange", "Keep distance", 1, 5, 1)
  addScrollBar("anchorRange", "Anchoring Range", 1, 10, 3)
  addScrollBar("lureCount", "Classic Lure", 0, 5, 1)
  addScrollBar("lureMin", "Dynamic lure min", 0, 29, 1)
  addScrollBar("lureMax", "Dynamic lure max", 1, 30, 3)
  addScrollBar("lureDelay", "Dynamic lure delay", 100, 1000, 250)
  addScrollBar("delayFrom", "Start delay when monsters", 1, 29, 2)
  addScrollBar("rePositionAmount", "Min tiles to rePosition", 0, 7, 5)
  addScrollBar("closeLureAmount", "Close Pull Until", 0, 8, 3)

  -- Attack options
  addScrollBar("minMana", "Min. mana for attack spell", 0, 3000, 200)
  addScrollBar("attackSpellDelay", "Attack spell delay", 200, 5000, 2500)
  addScrollBar("minManaGroup", "Min. mana for group attack", 0, 3000, 1500)
  addScrollBar("groupAttackTargets", "Min. targets for group attack", 1, 10, 2)
  addScrollBar("groupAttackRadius", "Radius of group attack spell", 1, 7, 1)
  addScrollBar("groupAttackDelay", "Group attack spell delay", 200, 60000, 5000)
  addScrollBar("runeAttackDelay", "Rune attack delay", 200, 5000, 2000)
  addScrollBar("groupRuneAttackTargets", "Min. targets for group rune attack", 1, 10, 2)
  addScrollBar("groupRuneAttackRadius", "Radius of group rune attack", 1, 7, 1)
  addScrollBar("groupRuneAttackDelay", "Group rune attack delay", 200, 60000, 5000)

  addCheckBox("chase", "Chase", true)
  addCheckBox("keepDistance", "Keep Distance", false)
  addCheckBox("anchor", "Anchoring", false)
  addCheckBox("dontLoot", "Don't loot", false)
  addCheckBox("lure", "Lure", false)
  addCheckBox("lureCavebot", "Lure using cavebot", false)
  addCheckBox("faceMonster", "Face monsters", false)
  addCheckBox("avoidAttacks", "Avoid wave attacks", false)
  addCheckBox("dynamicLure", "Dynamic lure", false)
  addCheckBox("dynamicLureDelay", "Dynamic lure delay", false)
  addCheckBox("diamondArrows", "D-Arrows priority", false)
  addCheckBox("rePosition", "rePosition to better tile", false)
  addCheckBox("closeLure", "Close Pulling Monsters", false)
  addCheckBox("rpSafe", "RP PVP SAFE - (DA)", false)

  addCheckBox("useSpellAttack", "Use attack spell", false)
  addTextEdit("attackSpell", "Attack spell", "")
  addCheckBox("useRuneAttack", "Use attack rune", false)
  addItem("attackRune", "Attack rune:", 0)
  addCheckBox("useGroupAttack", "Use group attack spell", false)
  addTextEdit("groupAttackSpell", "Group attack spell", "")
  addCheckBox("useGroupAttackRune", "Use group attack rune", false)
  addItem("groupAttackRune", "Group attack rune:", 0)
  addCheckBox("groupAttackIgnorePlayers", "Ignore players in group attack", false)
  addCheckBox("groupAttackIgnoreParty", "Ignore party in group attack", false)
end
