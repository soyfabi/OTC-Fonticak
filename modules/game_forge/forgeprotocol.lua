ForgeProtocol = {}

local protocol = nil
local silent = false

local ForgeOpcode = {
  Request = 0xE2,
  Send = 0xE3
}

local ForgeRequest = {
  Open = 1,
  Close = 2,
  Fusion = 3,
  Transfer = 4,
  Convert = 5,
  History = 6
}

local ForgeResponse = {
  Message = 0,
  Init = 1,
  Data = 2,
  Fusion = 3,
  Transfer = 4,
  History = 5,
  Close = 6
}

local function send(msg)
  if not protocol then
    protocol = g_game.getProtocolGame()
  end
  if protocol and not silent then
    protocol:send(msg)
  end
end

local function readPriceTable(msg)
  local result = {}
  local classCount = msg:getU8()

  for i = 1, classCount do
    local classification = msg:getU8()
    local tierPrices = {}
    local tierCount = msg:getU8()

    for j = 1, tierCount do
      tierPrices[msg:getU8()] = msg:getU64()
    end

    result[classification] = {
      [2] = tierPrices
    }
  end

  return result
end

local function readNumberMap(msg)
  local result = {}
  local count = msg:getU8()

  for i = 1, count do
    result[msg:getU8()] = msg:getU64()
  end

  return result
end

local function readByteMap(msg)
  local result = {}
  local count = msg:getU8()

  for i = 1, count do
    result[msg:getU8()] = msg:getU8()
  end

  return result
end

local function readForgeItems(msg)
  local result = {}
  local count = msg:getU16()

  for i = 1, count do
    local entry = {
      msg:getU16(),
      msg:getU8(),
      msg:getU16(),
      {},
      msg:getU8(),
      msg:getU8()
    }

    local subItemCount = msg:getU16()
    for j = 1, subItemCount do
      entry[4][msg:getU16()] = msg:getU16()
    end

    table.insert(result, entry)
  end

  return result
end

local function parseInit(msg)
  ForgeSystem.init(
    readPriceTable(msg),
    readByteMap(msg),
    readNumberMap(msg),
    readNumberMap(msg),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU8(),
    msg:getU8(),
    msg:getU8()
  )
end

local function parseData(msg)
  local maxPlayerDust = msg:getU16()
  local balances = {
    [ResourceBank] = msg:getU64(),
    [ResourceInventory] = msg:getU64(),
    [ResourceForgeDust] = msg:getU64(),
    [ResourceForgeSlivers] = msg:getU64(),
    [ResourceForgeExaltedCore] = msg:getU64()
  }

  if ForgeSystem.setResourceBalances then
    ForgeSystem.setResourceBalances(balances)
  end

  ForgeSystem.onForgeData(
    readForgeItems(msg),
    readForgeItems(msg),
    readForgeItems(msg),
    readForgeItems(msg),
    maxPlayerDust
  )
end

local function parseFusion(msg)
  ForgeSystem.onForgeFusion(
    msg:getU8() ~= 0,
    msg:getU8() ~= 0,
    msg:getU16(),
    msg:getU8(),
    msg:getU16(),
    msg:getU8(),
    msg:getU8(),
    msg:getU16(),
    msg:getU8(),
    msg:getU16()
  )
end

local function parseTransfer(msg)
  ForgeSystem.onForgeTransfer(
    msg:getU8() ~= 0,
    msg:getU8() ~= 0,
    msg:getU16(),
    msg:getU8(),
    msg:getU16(),
    msg:getU8()
  )
end

local function parseHistory(msg)
  local history = {}
  local count = msg:getU16()

  for i = 1, count do
    table.insert(history, {
      msg:getU32(),
      msg:getU8(),
      msg:getString()
    })
  end

  ForgeSystem.onForgeHistory(history)
end

local function parseForgeMessage(protocolGame, msg)
  local response = msg:getU8()

  if response == ForgeResponse.Message then
    if displayInfoBox then
      displayInfoBox(tr('Forge'), msg:getString())
    end
  elseif response == ForgeResponse.Init then
    parseInit(msg)
  elseif response == ForgeResponse.Data then
    parseData(msg)
  elseif response == ForgeResponse.Fusion then
    parseFusion(msg)
  elseif response == ForgeResponse.Transfer then
    parseTransfer(msg)
  elseif response == ForgeResponse.History then
    parseHistory(msg)
  elseif response == ForgeResponse.Close then
    if offlineForge then
      offlineForge()
    end
  end

  return true
end

ForgeProtocol.gameEvents = {
  onGameStart = ForgeProtocol.registerProtocol,
  onGameEnd = ForgeProtocol.unregisterProtocol
}

function initProtocol()
  G.onForgeProtocolMessage = parseForgeMessage
  if registerCustomForgeOpcode then
    registerCustomForgeOpcode()
  else
    ForgeProtocol.registerProtocol()
  end

  connect(g_game, ForgeProtocol.gameEvents)

  if g_game.isOnline() then
    protocol = g_game.getProtocolGame()
  end

  ForgeProtocol.silent(false)
end

function terminateProtocol()
  disconnect(g_game, ForgeProtocol.gameEvents)
  G.onForgeProtocolMessage = nil
  protocol = nil
end

function ForgeProtocol.registerProtocol()
  G.onForgeProtocolMessage = parseForgeMessage
  if registerCustomForgeOpcode then
    registerCustomForgeOpcode()
  else
    ProtocolGame.unregisterOpcode(ForgeOpcode.Send)
    ProtocolGame.registerOpcode(ForgeOpcode.Send, parseForgeMessage)
  end
  protocol = g_game.getProtocolGame()
end

function ForgeProtocol.unregisterProtocol()
  G.onForgeProtocolMessage = nil
  protocol = nil
end

function ForgeProtocol.silent(mode)
  silent = mode
end

local function sendRequest(action)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(action)
  send(msg)
end

function ForgeProtocol.sendOpen()
  sendRequest(ForgeRequest.Open)
end

function ForgeProtocol.sendClose()
  sendRequest(ForgeRequest.Close)
end

function ForgeProtocol.sendHistory()
  sendRequest(ForgeRequest.History)
end

function ForgeProtocol.sendForgeFusion(convergence, itemId, tier, secondItemId, boostSuccess, protectTierLoss)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(ForgeRequest.Fusion)
  msg:addU8(convergence and 1 or 0)
  msg:addU16(itemId)
  msg:addU8(tier)
  msg:addU16(secondItemId)
  msg:addU8(boostSuccess and 1 or 0)
  msg:addU8(protectTierLoss and 1 or 0)
  send(msg)
end

function ForgeProtocol.sendForgeTransfer(convergence, itemId, tier, secondItemId)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(ForgeRequest.Transfer)
  msg:addU8(convergence and 1 or 0)
  msg:addU16(itemId)
  msg:addU8(tier)
  msg:addU16(secondItemId)
  send(msg)
end

function ForgeProtocol.sendForgeConverter(action)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(ForgeRequest.Convert)
  msg:addU8(action)
  send(msg)
end
