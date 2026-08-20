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
  return true
end

function registerCustomForgeOpcode()
  pcall(function()
    ProtocolGame.unregisterOpcode(FORGE_OPCODE_SEND)
  end)
  ProtocolGame.registerOpcode(FORGE_OPCODE_SEND, onForgeOpcode)
  ProtocolGame.registerOpcode(FORGE_OPCODE_RESOURCE_BALANCE, onForgeResourceOpcode)
end

function unregisterCustomForgeOpcode()
  ProtocolGame.unregisterOpcode(FORGE_OPCODE_SEND)
  ProtocolGame.unregisterOpcode(FORGE_OPCODE_RESOURCE_BALANCE)
end

registerCustomForgeOpcode()
