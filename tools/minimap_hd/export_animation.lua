-- Run offline with AstraClient's HD export bootstrap and matching 8.60 assets.
scheduleEvent(function()
  assert(not g_game.isOnline())
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  assert(g_things.isDatLoaded() and g_sprites.isLoaded())
  g_things.loadOtbForMap('/source-items.otb')
  assert(g_things.isOtbLoaded())
  g_map.clean()
  g_map.loadOtbm('/source-world.otbm')

  local output = '/animation-source'
  assert(g_resources.makeDir(output))
  local dat = g_things.getDatSignature() % 4294967296
  local spr = g_sprites.getSprSignature() % 4294967296
  assert(g_resources.writeFileContents(output .. '/signatures.txt', string.format('%.0f %.0f\n', dat, spr)))
  local types = {}
  local metadata = {}
  local function getType(id)
    if not types[id] then
      local thing = g_things.getThingType(id, ThingCategoryItem)
      local sprites = thing:getSprites()
      local dimensions = {id, thing:getWidth(), thing:getHeight(), thing:getLayers(),
                          thing:getNumPatternX(), thing:getNumPatternY(), thing:getNumPatternZ(),
                          thing:getAnimationPhases(), thing:getDisplacementX(), thing:getDisplacementY()}
      metadata[#metadata + 1] = table.concat(dimensions, ' ') .. ' ' .. table.concat(sprites, ' ')
      types[id] = thing
    end
    return types[id]
  end

  for floor = 0, 15 do
    local tiles = g_map.getTiles(floor)
    table.sort(tiles, function(a, b)
      local p, q = a:getPosition(), b:getPosition()
      return p.y < q.y or (p.y == q.y and p.x < q.x)
    end)
    local ground, middle, top = {}, {}, {}
    for _, tile in ipairs(tiles) do
      local position = tile:getPosition()
      local items = {}
      local hookSouth, hookEast = false, false
      for _, item in ipairs(tile:getItems()) do
        if not item:isPickupable() and not item:isHidden() then
          items[#items + 1] = item
          local thing = getType(item:getId())
          hookSouth = hookSouth or thing:isHookSouth()
          hookEast = hookEast or thing:isHookEast()
        end
      end
      local elevation = 0
      local function add(item, pass)
        local id = item:getId()
        local thing = getType(id)
        local nx, ny, nz = thing:getNumPatternX(), thing:getNumPatternY(), thing:getNumPatternZ()
        local x, y, z = position.x % nx, position.y % ny, floor % nz
        if thing:isHangable() then
          x, y, z = 0, 0, 0
          if hookSouth and nx >= 2 then x = 1
          elseif not hookSouth and hookEast and nx >= 3 then x = 2 end
        elseif thing:isSplash() or thing:isFluidContainer() then
          local color = item:getCountOrSubType()
          if g_game.getFeature(GameNewFluids) then
            local colors = {1, 7, 3, 3, 2, 4, 3, 5, 6, 7, 2, 5, 3, 5, 6, 3, 3}
            color = colors[color] or 0
          end
          x, y, z = (color % 4) % nx, math.floor(color / 4) % ny, 0
        end
        pass[#pass + 1] = table.concat({id, position.x * 32 - elevation, position.y * 32 - elevation, x, y, z}, ' ')
      end
      for _, item in ipairs(items) do
        if item:isGround() or item:isGroundBorder() or item:isOnBottom() then
          add(item, item:isGround() and ground or middle)
          elevation = math.min(elevation + getType(item:getId()):getElevation(), 24)
        end
      end
      for i = #items, 1, -1 do
        local item = items[i]
        if not (item:isGround() or item:isGroundBorder() or item:isOnBottom() or item:isOnTop()) then
          add(item, middle)
          elevation = math.min(elevation + getType(item:getId()):getElevation(), 24)
        end
      end
      for _, item in ipairs(items) do
        if item:isOnTop() then add(item, top) end
      end
    end
    assert(g_resources.writeFileContents(output .. '/' .. floor .. '.txt',
      table.concat({table.concat(ground, '\n'), table.concat(middle, '\n'), table.concat(top, '\n')}, '\n')))
  end
  assert(g_resources.writeFileContents(output .. '/types.txt', table.concat(metadata, '\n')))
  g_logger.info('[HD ANIMATION] OUTPUT: ' .. g_resources.getWriteDir() .. output)
  scheduleEvent(g_app.exit, 500)
end, 1000)
