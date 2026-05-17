-- Custom forge opcode must be registered in the global gamelib environment (not a module sandbox).

local FORGE_OPCODE_SEND = 0xE3

local function onForgeOpcode(protocol, msg)
  if type(G.onForgeProtocolMessage) == 'function' then
    return G.onForgeProtocolMessage(protocol, msg)
  end
  g_logger.warning('[Forge] Received forge packet before game_forge module is ready')
  return false
end

function registerCustomForgeOpcode()
  pcall(function()
    ProtocolGame.unregisterOpcode(FORGE_OPCODE_SEND)
  end)
  ProtocolGame.registerOpcode(FORGE_OPCODE_SEND, onForgeOpcode)
end

function unregisterCustomForgeOpcode()
  ProtocolGame.unregisterOpcode(FORGE_OPCODE_SEND)
end

registerCustomForgeOpcode()
