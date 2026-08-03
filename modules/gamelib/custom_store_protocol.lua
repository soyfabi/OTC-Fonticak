-- Custom Fantoner store opcode (0xFD) must be registered in the global gamelib
-- environment. In protocol 8.60, 0xFD is also Cip "StoreTransactionHistory";
-- without this bridge the C++ parser eats the Fantoner catalog and leaves
-- Unhandled opcode 0x00 leftovers.

local STORE_OPCODE_SEND = 0xFD

local function onStoreOpcode(protocol, msg)
  if type(G.onStoreProtocolMessage) == 'function' then
    local ok, err = pcall(G.onStoreProtocolMessage, protocol, msg)
    if not ok then
      g_logger.error('[Store] Opcode 0xFD handler error: ' .. tostring(err))
      if msg and msg.getMessageSize and msg.setReadPos then
        msg:setReadPos(msg:getMessageSize())
      end
    end
    return
  end

  -- Consume payload so Cip history parser never sees Fantoner catalog bytes.
  if msg and msg.getMessageSize and msg.setReadPos then
    msg:setReadPos(msg:getMessageSize())
  end
  g_logger.warning('[Store] Received 0xFD before game_store module is ready')
end

function registerCustomStoreOpcode()
  pcall(function()
    ProtocolGame.unregisterOpcode(STORE_OPCODE_SEND)
  end)
  ProtocolGame.registerOpcode(STORE_OPCODE_SEND, onStoreOpcode)
end

function unregisterCustomStoreOpcode()
  ProtocolGame.unregisterOpcode(STORE_OPCODE_SEND)
end

registerCustomStoreOpcode()
