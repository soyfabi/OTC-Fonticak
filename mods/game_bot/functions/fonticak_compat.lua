-- Fonticak/mehah compatibility for ANY bot config (OTCv8 / vBot / custom).
-- Loaded from mods/game_bot/functions so every config benefits.
local context = G.botContext

-- ---------------------------------------------------------------------------
-- Bit / bit aliases (OTCv8: bit.* | Fonticak: Bit.*)
-- ---------------------------------------------------------------------------
if Bit then
  context.Bit = Bit
end
if not context.Bit and context.bit then
  context.Bit = context.bit
end
if context.Bit and not context.bit then
  context.bit = context.Bit
end

-- ---------------------------------------------------------------------------
-- Walk: Fonticak drops mid-step walks when 2nd arg is false.
-- Force schedule/prewalk like holding a movement key (any bot config).
-- ---------------------------------------------------------------------------
do
  local realWalk = g_game.walk
  local gameProxy = {}
  setmetatable(gameProxy, {
    __index = g_game,
    __newindex = function(_, k, v)
      g_game[k] = v
    end
  })
  function gameProxy.walk(dir, isKeyDown)
    if isKeyDown == nil or isKeyDown == false then
      isKeyDown = true
    end
    return realWalk(dir, isKeyDown)
  end
  context.g_game = gameProxy
end

-- ---------------------------------------------------------------------------
-- CaveBot: multi-step paths use autoWalk (Map Click speed) without requiring
-- the "Use map click" toggle. Reuses each config's own walking.lua state.
-- ---------------------------------------------------------------------------
local function patchCaveBotWalking()
  local CaveBot = rawget(context, "CaveBot")
  if type(CaveBot) ~= "table" or type(CaveBot.walkTo) ~= "function" then
    return
  end
  if CaveBot._fonticakWalkPatched then
    return
  end
  CaveBot._fonticakWalkPatched = true

  local originalWalkTo = CaveBot.walkTo
  CaveBot.walkTo = function(dest, maxDist, params)
    local mapClick = CaveBot.Config and CaveBot.Config.get and CaveBot.Config.get("mapClick")
    if mapClick then
      return originalWalkTo(dest, maxDist, params)
    end

    local path = context.getPath(context.player:getPosition(), dest, maxDist, params)
    if path and #path > 1 and CaveBot.Config and CaveBot.Config.values then
      -- Temporarily use map-click path so expectedDirs/isWalking stay in sync
      local values = CaveBot.Config.values
      local prev = values.mapClick
      values.mapClick = true
      local ok, ret = pcall(originalWalkTo, dest, maxDist, params)
      values.mapClick = prev
      if ok then
        return ret
      end
      return originalWalkTo(dest, maxDist, params)
    end

    return originalWalkTo(dest, maxDist, params)
  end
end

-- ---------------------------------------------------------------------------
-- Grids: flow+narrow panel collapses to 1 column on Fonticak. Force 2 cols.
-- ---------------------------------------------------------------------------
local function forceTwoColumnButtons(panel)
  if not panel then
    return
  end
  local buttons = panel.buttons
  if not buttons and panel.getChildById then
    buttons = panel:getChildById("buttons")
  end
  if not buttons or not buttons.getLayout then
    return
  end
  local layout = buttons:getLayout()
  if not layout or not layout.isUIGridLayout or not layout:isUIGridLayout() then
    return
  end
  if layout.setFlow then
    layout:setFlow(false)
  end
  if layout.setNumColumns then
    layout:setNumColumns(2)
  end
  if layout.setCellSize then
    layout:setCellSize({ width = 85, height = 20 })
  end
  if layout.setCellSpacing then
    layout:setCellSpacing(2)
  end
  if layout.update then
    layout:update()
  end
end

local function patchCaveBotGrids()
  local root = g_ui.getRootWidget()
  if not root or not root.recursiveGetChildById then
    return
  end
  forceTwoColumnButtons(root:recursiveGetChildById("cavebotEditor"))

  local function scan(widget)
    if not widget or not widget.getChildren then
      return
    end
    for _, child in ipairs(widget:getChildren()) do
      if child.getText and child:getText() == "CaveBot Control Panel" then
        forceTwoColumnButtons(child:getParent())
      end
      scan(child)
    end
  end
  scan(root)
end

context._applyFonticakCompat = function()
  patchCaveBotWalking()
  if context.schedule then
    context.schedule(150, patchCaveBotGrids)
    context.schedule(600, patchCaveBotGrids)
  end
end
