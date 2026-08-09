local targetBotLure = false
local targetCount = 0
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local lastCall = now
local delayFrom = nil
local dynamicLureDelay = false

function getWalkableTilesCount(position)
  local count = 0

  for i, tile in pairs(getNearTiles(position)) do
      if tile:isWalkable() or tile:hasCreatures() then
          count = count + 1
      end
  end

  return count
end

function rePosition(minTiles)
  minTiles = minTiles or 8
  if now - lastCall < 500 then return end
  local pPos = player:getPosition()
  local tiles = getNearTiles(pPos)
  local playerTilesCount = getWalkableTilesCount(pPos)
  local tilesTable = {}

  if playerTilesCount > minTiles then return end
  for i, tile in ipairs(tiles) do
      tilesTable[tile] = not tile:hasCreatures() and tile:isWalkable() and getWalkableTilesCount(tile:getPosition()) or nil
  end

  local best = 0
  local target = nil
  for k,v in pairs(tilesTable) do
      if v > best and v > playerTilesCount then
          best = v
          target = k:getPosition()
      end
  end

  if target then
      lastCall = now
      return CaveBot.GoTo(target, 0)
  end
end

TargetBot.Creature.attack = function(params, targets, isLooting) -- params {config, creature, danger, priority}
  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature

  if g_game.getAttackingCreature() ~= creature then
    g_game.attack(creature)
  end

  if not isLooting then -- walk only when not looting
    TargetBot.Creature.walk(creature, config, targets)
  end

  -- attacks (defaults match creature_editor; nil checks so old configs still cast)
  local mana = player:getMana()
  local attackSpell = type(config.attackSpell) == "string" and config.attackSpell:trim() or ""
  local groupSpell = type(config.groupAttackSpell) == "string" and config.groupAttackSpell:trim() or ""
  local minMana = config.minMana or 0
  local minManaGroup = config.minManaGroup or 0
  local groupRadius = config.groupAttackRadius or 1
  local groupTargets = config.groupAttackTargets or 2
  local groupDelay = config.groupAttackDelay or 5000
  local groupRuneRadius = config.groupRuneAttackRadius or 1
  local groupRuneTargets = config.groupRuneAttackTargets or 2
  local groupRuneDelay = config.groupRuneAttackDelay or 5000
  local spellDelay = config.attackSpellDelay or 2000
  local runeDelay = config.attackRuneDelay or 2000
  local groupRune = tonumber(config.groupAttackRune) or 0
  local attackRune = tonumber(config.attackRune) or 0

  if config.useGroupAttack and groupSpell:len() > 1 and mana > minManaGroup then
    local creatures = g_map.getSpectatorsInRange(player:getPosition(), false, groupRadius, groupRadius)
    local playersAround = false
    local monsters = 0
    for _, spectator in ipairs(creatures) do
      if not spectator:isLocalPlayer() and spectator:isPlayer() and (not config.groupAttackIgnoreParty or spectator:getShield() <= 2) then
        playersAround = true
      elseif spectator:isMonster() then
        monsters = monsters + 1
      end
    end
    if monsters >= groupTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.sayAttackSpell(groupSpell, groupDelay) then
        return
      end
    end
  end

  if config.useGroupAttackRune and groupRune > 100 then
    local creatures = g_map.getSpectatorsInRange(creature:getPosition(), false, groupRuneRadius, groupRuneRadius)
    local playersAround = false
    local monsters = 0
    for _, spectator in ipairs(creatures) do
      if not spectator:isLocalPlayer() and spectator:isPlayer() and (not config.groupAttackIgnoreParty or spectator:getShield() <= 2) then
        playersAround = true
      elseif spectator:isMonster() then
        monsters = monsters + 1
      end
    end
    if monsters >= groupRuneTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.useAttackItem(groupRune, 0, creature, groupRuneDelay) then
        return
      end
    end
  end

  if config.useSpellAttack and attackSpell:len() > 1 and mana >= minMana then
    if TargetBot.sayAttackSpell(attackSpell, spellDelay) then
      return
    end
  end

  if config.useRuneAttack and attackRune > 100 then
    if TargetBot.useAttackItem(attackRune, 0, creature, runeDelay) then
      return
    end
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()

  local isTrapped = true
  local pos = player:getPosition()
  local dirs = {{-1,1}, {0,1}, {1,1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}}
  for i=1,#dirs do
    local tile = g_map.getTile({x=pos.x-dirs[i][1],y=pos.y-dirs[i][2],z=pos.z})
    if tile and tile:isWalkable(false) then
      isTrapped = false
    end
  end

  -- data for external dynamic lure
  if config.lureMin and config.lureMax and config.dynamicLure then
    if config.lureMin >= targets then
      targetBotLure = true
    elseif targets >= config.lureMax then
      targetBotLure = false
    end
  end
  targetCount = targets
  delayValue = config.lureDelay

  if config.lureMax then
    lureMax = config.lureMax
  end

  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  -- luring
  if config.closeLure and config.closeLureAmount <= getMonsters(1) then
    return TargetBot.allowCaveBot(150)
  end
  if TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and not (creature:getHealthPercent() < (storage.extras.killUnder or 30)) and not isTrapped then
    if targetBotLure then
      anchorPosition = nil
      return TargetBot.allowCaveBot(150)
    else
      if targets < config.lureCount then
        if config.lureCavebot then
          anchorPosition = nil
          return TargetBot.allowCaveBot(150)
        else
          local path = findPath(pos, cpos, 5, {ignoreNonPathable=true, precision=2})
          if path then
            return TargetBot.walkTo(cpos, 10, {marginMin=5, marginMax=6, ignoreNonPathable=true})
          end
        end
      end
    end
  end

  local currentDistance = findPath(pos, cpos, 10, {ignoreCreatures=true, ignoreNonPathable=true, ignoreCost=true})
  if (not config.chase or #currentDistance == 1) and not config.avoidAttacks and not config.keepDistance and config.rePosition and (creature:getHealthPercent() >= storage.extras.killUnder) then
    return rePosition(config.rePositionAmount or 6)
  end
  if ((storage.extras.killUnder > 1 and (creature:getHealthPercent() < storage.extras.killUnder)) or config.chase) and not config.keepDistance then
    if #currentDistance > 1 then
      return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=1})
    end
  elseif config.keepDistance then
    if not anchorPosition or distanceFromPlayer(anchorPosition) > config.anchorRange then
      anchorPosition = pos
    end
    if #currentDistance ~= config.keepDistanceRange and #currentDistance ~= config.keepDistanceRange + 1 then
      if config.anchor and anchorPosition and getDistanceBetween(pos, anchorPosition) <= config.anchorRange*2 then
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=config.keepDistanceRange, marginMax=config.keepDistanceRange + 1, maxDistanceFrom={anchorPosition, config.anchorRange}})
      else
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=config.keepDistanceRange, marginMax=config.keepDistanceRange + 1})
      end
    end
  end

  --target only movement
  if config.avoidAttacks then
    local diffx = cpos.x - pos.x
    local diffy = cpos.y - pos.y
    local candidates = {}
    if math.abs(diffx) == 1 and diffy == 0 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x, y=pos.y+1, z=pos.z}}
    elseif diffx == 0 and math.abs(diffy) == 1 then
      candidates = {{x=pos.x-1, y=pos.y, z=pos.z}, {x=pos.x+1, y=pos.y, z=pos.z}}
    end
    for _, candidate in ipairs(candidates) do
      local tile = g_map.getTile(candidate)
      if tile and tile:isWalkable() then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  elseif config.faceMonster then
    local diffx = cpos.x - pos.x
    local diffy = cpos.y - pos.y
    local candidates = {}
    if diffx == 1 and diffy == 1 then
      candidates = {{x=pos.x+1, y=pos.y, z=pos.z}, {x=pos.x, y=pos.y-1, z=pos.z}}
    elseif diffx == -1 and diffy == 1 then
      candidates = {{x=pos.x-1, y=pos.y, z=pos.z}, {x=pos.x, y=pos.y-1, z=pos.z}}
    elseif diffx == -1 and diffy == -1 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x-1, y=pos.y, z=pos.z}}
    elseif diffx == 1 and diffy == -1 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x+1, y=pos.y, z=pos.z}}
    else
      local dir = player:getDirection()
      if diffx == 1 and dir ~= 1 then turn(1)
      elseif diffx == -1 and dir ~= 3 then turn(3)
      elseif diffy == 1 and dir ~= 2 then turn(2)
      elseif diffy == -1 and dir ~= 0 then turn(0)
      end
    end
    for _, candidate in ipairs(candidates) do
      local tile = g_map.getTile(candidate)
      if tile and tile:isWalkable() then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  end
end

onPlayerPositionChange(function(newPos, oldPos)
  if CaveBot.isOff() then return end
  if TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end

  if targetCount < (delayFrom or lureMax/2) or not target() then return end
  CaveBot.delay(delayValue or 0)
end)
