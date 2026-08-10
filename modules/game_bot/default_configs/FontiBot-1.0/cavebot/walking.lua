-- walking
local expectedDirs = {}
local isWalking = false
local walkPath = {}
local walkPathIter = 0

-- Fonticak drops mid-step walks when the 2nd arg is false (unlike OTCv8 prewalk).
-- Pass true so the next step is scheduled like holding a movement key.
local function botWalk(dir)
  return g_game.walk(dir, true)
end

-- Send the next step slightly before the current one ends (prewalk window).
local function stepDelay(dir)
  local step = player:getStepDuration(false, dir)
  if not step or step < 1 then
    step = 50
  end
  local pre = math.min(70, math.floor(step / 3))
  return CaveBot.Config.get("walkDelay") + math.max(15, step - pre)
end

CaveBot.resetWalking = function()
  expectedDirs = {}
  walkPath = {}
  walkPathIter = 0
  isWalking = false
end

CaveBot.doWalking = function()
  if CaveBot.Config.get("mapClick") then
    return false
  end
  if #expectedDirs == 0 then
    return false
  end
  if #expectedDirs >= 3 then
    CaveBot.resetWalking()
    return false
  end
  local dir = walkPath[walkPathIter]
  if not dir then
    return false
  end

  local walked = botWalk(dir)
  if walked then
    table.insert(expectedDirs, dir)
    walkPathIter = walkPathIter + 1
  end
  CaveBot.delay(stepDelay(dir))
  return true
end

-- called when player position has been changed (step has been confirmed by server)
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end

  local dirs = {{NorthWest, North, NorthEast}, {West, 8, East}, {SouthWest, South, SouthEast}}
  local dir = dirs[newPos.y - oldPos.y + 2]
  if dir then
    dir = dir[newPos.x - oldPos.x + 2]
  end
  if not dir then
    dir = 8 -- 8 is invalid dir, it's fine
  end

  if not isWalking or not expectedDirs[1] then
    -- some other walk action is taking place (for example use on ladder), wait
    walkPath = {}
    CaveBot.delay(CaveBot.Config.get("ping") + player:getStepDuration(false, dir) + 100)
    return
  end

  if expectedDirs[1] ~= dir then
    CaveBot.delay(stepDelay(dir))
    return
  end

  table.remove(expectedDirs, 1)
  if CaveBot.Config.get("mapClick") and #expectedDirs > 0 then
    CaveBot.delay(CaveBot.Config.get("mapClickDelay") + player:getStepDuration(false, dir))
  end
end)

CaveBot.walkTo = function(dest, maxDist, params)
  local path = getPath(player:getPosition(), dest, maxDist, params)
  if not path or not path[1] then
    return false
  end
  local dir = path[1]

  if CaveBot.Config.get("mapClick") then
    local ret = autoWalk(path)
    if ret then
      isWalking = true
      expectedDirs = path
      CaveBot.delay(CaveBot.Config.get("mapClickDelay") + math.max(CaveBot.Config.get("ping") + player:getStepDuration(false, dir), player:getStepDuration(false, dir) * 2))
    end
    return ret
  end

  -- Multi-step: use autoWalk for continuous server-side path (OTCv8-like speed)
  -- without requiring the "Use map click" toggle. Single step still uses walk.
  if #path > 1 then
    local ret = autoWalk(path)
    if ret then
      isWalking = true
      expectedDirs = path
      walkPath = path
      walkPathIter = 2
      CaveBot.delay(stepDelay(dir))
      return true
    end
  end

  local walked = botWalk(dir)
  if not walked then
    -- Not ready yet; keep trying soon instead of waiting a full step.
    CaveBot.delay(math.max(15, CaveBot.Config.get("walkDelay")))
    return true
  end

  isWalking = true
  walkPath = path
  walkPathIter = 2
  expectedDirs = { dir }
  CaveBot.delay(stepDelay(dir))
  return true
end
