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

local RESOURCE_BOUNTY_POINTS = 0x56
local RESOURCE_SOULSEALS_POINTS = 0x57

local function onForgeResourceOpcode(protocol, msg)
  local resourceType = msg:getU8()
  local value
  if resourceType == RESOURCE_BOUNTY_POINTS or resourceType == RESOURCE_SOULSEALS_POINTS then
    value = msg:getU32()
  else
    value = msg:getU64()
  end
  if ForgeSystem and ForgeSystem.setResourceBalances then
    ForgeSystem.setResourceBalances({[resourceType] = value})
  end
  -- Forward resource balances to the local player so all modules and UI
  -- (prey, skills, forge, inventory) see them.
  local player = g_game.getLocalPlayer()
  if player and player.setResourceBalance then
    player:setResourceBalance(resourceType, value)
  end
  if Forge and Forge.updateButtonHighlight then
    Forge:updateButtonHighlight()
  end
  if g_game.onResourceBalance then
    signalcall(g_game.onResourceBalance, resourceType, value)
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
