-- Custom forge opcode must be registered in the global gamelib environment (not a module sandbox).

local FORGE_OPCODE_SEND = 0xE3
local FORGE_OPCODE_RESOURCE_BALANCE = 0xEE

local function onForgeOpcode(protocol, msg)
  if type(G.onForgeProtocolMessage) == 'function' then
    return G.onForgeProtocolMessage(protocol, msg)
  end
  g_logger.warning('[Forge] Received forge packet before game_forge module is ready')
  return false
end

local function onForgeResourceOpcode(protocol, msg)
  local resourceType = msg:getU8()
  local value = msg:getU64()
  if ForgeSystem and ForgeSystem.setResourceBalances then
    ForgeSystem.setResourceBalances({[resourceType] = value})
  end
  -- The forge module owns the 0xEE channel on Fonticak, which also carries
  -- the shared bank (0), inventory gold (1) and prey wildcard (10) balances.
  -- Forward those to the local player so native prey (and other resource
  -- based UIs) see them.
  if resourceType == 0 or resourceType == 1 or resourceType == 10 then
    local player = g_game.getLocalPlayer()
    if player and player.setResourceBalance then
      player:setResourceBalance(resourceType, value)
    end
  end
  return true
end

function registerCustomForgeOpcode()
  pcall(function()
    ProtocolGame.unregisterOpcode(FORGE_OPCODE_SEND)
    ProtocolGame.unregisterOpcode(FORGE_OPCODE_RESOURCE_BALANCE)
  end)
  ProtocolGame.registerOpcode(FORGE_OPCODE_SEND, onForgeOpcode)
  ProtocolGame.registerOpcode(FORGE_OPCODE_RESOURCE_BALANCE, onForgeResourceOpcode)
end

function unregisterCustomForgeOpcode()
  ProtocolGame.unregisterOpcode(FORGE_OPCODE_SEND)
  ProtocolGame.unregisterOpcode(FORGE_OPCODE_RESOURCE_BALANCE)
end

registerCustomForgeOpcode()
