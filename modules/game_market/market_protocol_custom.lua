local CustomMarketOpcode = 0xDB

local CustomMarketResponse = {
    Message = 0,
    Enter = 1,
    Leave = 2,
    Browse = 3,
    Detail = 4,
}

local CustomMarketSendOpcode = {
    Browse = 0xF6,
    Create = 0xF7,
    Cancel = 0xE0,
    Accept = 0xE1,
    Detail = 0xFA,
    Leave = 0xF5,
    Enter = 0xFC
}

local customMarketEnter = nil

function parseCustomMarketMessage(protocol, msg)
    local response = msg:getU8()

    if response == CustomMarketResponse.Message then
        local text = msg:getString()
        if modules.game_textmessage then
            modules.game_textmessage.displayFailureMessage(text)
        end

    elseif response == CustomMarketResponse.Enter then
        local balance = msg:getU64()
        local offers = msg:getU16()
        local chunkIndex = msg:getU16()
        local lastChunk = msg:getU8() ~= 0
        local itemsCount = msg:getU16()

        if not customMarketEnter then
            customMarketEnter = { depotItems = {}, items = {}, balance = balance, offers = offers }
        end

        for i = 1, itemsCount do
            local itemId = msg:getU16()
            local category = msg:getU8()
            local name = msg:getString()
            local amount = msg:getU16()

            table.insert(customMarketEnter.items, { id = itemId, category = category, name = name })
            table.insert(customMarketEnter.depotItems, {itemId, amount})
        end

        if lastChunk then
            if g_game.onMarketEnter then
                signalcall(g_game.onMarketEnter, customMarketEnter.depotItems, customMarketEnter.offers, customMarketEnter.balance, -1, customMarketEnter.items)
            end
            customMarketEnter = nil
        end

    elseif response == CustomMarketResponse.Leave then
        if g_game.onMarketLeave then signalcall(g_game.onMarketLeave) end

    elseif response == CustomMarketResponse.Browse then
        local var = msg:getU16()
        local mappedVar = (var == 0xFFFF and 1 or (var == 0xFFFE and 2 or var))

        local function readOffers(type)
            local count = msg:getU16()
            for i = 1, count do
                local offerId = msg:getU32()
                local timestamp = msg:getU32()
                local itemId = msg:getU16()
                local amount = msg:getU16()
                local price = msg:getU32()
                local playerName = msg:getString()
                local state = msg:getU8()
                
                if g_game.onMarketReadOffer then
                    signalcall(g_game.onMarketReadOffer, type, amount, offerId, itemId, playerName, price, state, timestamp, mappedVar, 0)
                end
            end
        end

        readOffers(0) -- Buy
        readOffers(1) -- Sell

        if g_game.onMarketBrowse then signalcall(g_game.onMarketBrowse, {}, {}, mappedVar) end

    elseif response == CustomMarketResponse.Detail then
        local itemId = msg:getU16()
        local descriptions = {}
        local descriptionCount = msg:getU8()

        for i = 1, descriptionCount do
            descriptions[msg:getU8()] = msg:getString()
        end

        local function readStatistics(action)
            local stats = {}
            local count = msg:getU8()
            for i = 1, count do
                local timestamp = msg:getU32()
                local transactions = msg:getU32()
                local totalPrice = msg:getU32()
                local highestPrice = msg:getU32()
                local lowestPrice = msg:getU32()
                table.insert(stats, {timestamp, action, transactions, totalPrice, highestPrice, lowestPrice})
            end
            return stats
        end

        if g_game.onMarketDetail then
            signalcall(g_game.onMarketDetail, itemId, descriptions, readStatistics(0), readStatistics(1))
        end
    end

    return true
end

ProtocolGame.registerOpcode(CustomMarketOpcode, parseCustomMarketMessage)

function sendMarketLeave()
    local p = g_game.getProtocolGame()
    if p then
        local msg = OutputMessage.create()
        msg:addU8(CustomMarketSendOpcode.Leave)
        p:send(msg)
    end
end

function sendMarketEnter()
    local p = g_game.getProtocolGame()
    if p then
        local msg = OutputMessage.create()
        msg:addU8(CustomMarketSendOpcode.Enter)
        p:send(msg)
    end
end

function sendMarketBrowse(browseId)
    local p = g_game.getProtocolGame()
    if p then
        local msg = OutputMessage.create()
        msg:addU8(CustomMarketSendOpcode.Browse)
        msg:addU16(browseId)
        p:send(msg)
    end
end

function sendMarketAction(action, itemId, tier)
    if action == 3 and itemId then sendMarketBrowse(itemId)
    elseif action == 2 then sendMarketBrowse(0xFFFE)
    elseif action == 1 then sendMarketBrowse(0xFFFF)
    end
end

function sendMarketCreateOffer(offerType, itemId, tier, amount, price, anonymous)
    local p = g_game.getProtocolGame()
    if p then
        local msg = OutputMessage.create()
        msg:addU8(CustomMarketSendOpcode.Create)
        msg:addU8(offerType)
        msg:addU16(itemId)
        msg:addU16(amount)
        msg:addU32(price)
        msg:addU8(anonymous and 1 or 0)
        p:send(msg)
    end
end

function sendMarketCancelOffer(timestamp, counter)
    local p = g_game.getProtocolGame()
    if p then
        local msg = OutputMessage.create()
        msg:addU8(CustomMarketSendOpcode.Cancel)
        msg:addU32(counter)
        p:send(msg)
    end
end

function sendMarketAcceptOffer(timestamp, counter, amount)
    local p = g_game.getProtocolGame()
    if p then
        local msg = OutputMessage.create()
        msg:addU8(CustomMarketSendOpcode.Accept)
        msg:addU32(counter)
        msg:addU16(amount)
        p:send(msg)
    end
end

ProtocolGame.registerOpcode(0x2F, function(p, m) m:skipBytes(12) return true end)
ProtocolGame.registerOpcode(0x0E, function(p, m)
    m:getU8()
    local text = m:getString()
    if modules.game_textmessage then modules.game_textmessage.displayFailureMessage(text) end
    return true
end)
