-- CaveBot minimap integration (OTCv8 + Fonticak/mehah compatible)
local function resolveMinimap()
  local mm = modules.game_minimap
  if not mm then
    return nil
  end
  if mm.minimapWidget then
    return mm.minimapWidget
  end
  if mm.getMiniMapUi then
    return mm.getMiniMapUi()
  end
  return nil
end

local function bindMinimap(minimap)
  if not minimap then
    return false
  end
  if minimap._cavebotBound then
    return true
  end
  minimap._cavebotBound = true

  minimap.onMouseRelease = function(widget, pos, button)
    if not minimap.allowNextRelease then return true end
    minimap.allowNextRelease = false

    local mapPos = minimap:getTilePosition(pos)
    if not mapPos then return end

    if button == 1 then
      local player = g_game.getLocalPlayer()
      if minimap.autowalk and player then
        player:autoWalk(mapPos)
      end
      return true
    elseif button == 2 then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setId("minimapMenu")
      menu:setGameMenu(true)
      menu:addOption(tr('Create mark'), function()
        if minimap.createFlagWindow then
          minimap:createFlagWindow(mapPos)
        end
      end)
      menu:addOption(tr('Add CaveBot GoTo'), function()
        if CaveBot and CaveBot.addAction then
          CaveBot.addAction("goto", mapPos.x .. "," .. mapPos.y .. "," .. mapPos.z, true)
          CaveBot.save()
        end
      end)
      menu:display(pos)
      return true
    end
    return false
  end
  return true
end

-- Minimap UI may not be ready when bot config loads; retry a few times
local attempts = 0
local function tryBind()
  attempts = attempts + 1
  local minimap = resolveMinimap()
  if bindMinimap(minimap) then
    return
  end
  if attempts < 20 then
    schedule(250, tryBind)
  end
end

tryBind()
