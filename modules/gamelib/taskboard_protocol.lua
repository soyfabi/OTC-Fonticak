-- Server -> client Task Board (opcode 0x53), Forgotten Server extended wire format.

local OPCODE_TASK_BOARD = 0x53

local SUB_BOUNTY = 0x00
local SUB_WEEKLY = 0x01
local SUB_HUNT_SHOP = 0x02
local SUB_SOUL_SEALS = 0x03
local SUB_BOUNTY_KILL = 0x04
local SUB_WEEKLY_KILL = 0x05

-- addU64(0x5441534B424F4152) on wire, or ASCII "TASKBOAR" as two LE u32 words.
local BOUNTY_EXTENSION_MARKER_U32_PAIRS = {
    { 0x424F4152, 0x5441534B },
    { 0x4B534154, 0x52414F42 },
}

local MAX_TASK_BOARD_CHAIN_STEPS = 48
local MAX_MONSTER_NAME_LEN = 512

local function peekU8AtUnreadOffset(msg, byteOffset)
    if not msg or msg:getUnreadSize() < byteOffset + 1 then
        return nil
    end
    if msg.getReadPos and msg.setReadPos then
        local pos = msg:getReadPos()
        msg:setReadPos(pos + byteOffset)
        local value = msg:peekU8()
        msg:setReadPos(pos)
        return value
    end
    if not msg.getBuffer or not msg.getReadSize then
        return nil
    end
    local buffer = msg:getBuffer()
    if type(buffer) ~= 'string' then
        return nil
    end
    local idx = msg:getReadSize() + 1 + byteOffset
    return string.byte(buffer, idx)
end

local function peekU16AtUnreadOffset(msg, byteOffset)
    local b1 = peekU8AtUnreadOffset(msg, byteOffset)
    local b2 = peekU8AtUnreadOffset(msg, byteOffset + 1)
    if b1 == nil or b2 == nil then
        return nil
    end
    return b1 + b2 * 256
end

local function peekU32AtUnreadOffset(msg, byteOffset)
    if not msg or msg:getUnreadSize() < byteOffset + 4 or not msg.peekU32 then
        return nil
    end
    if msg.getReadPos and msg.setReadPos then
        local pos = msg:getReadPos()
        msg:setReadPos(pos + byteOffset)
        local value = msg:peekU32()
        msg:setReadPos(pos)
        return value
    end
    if not msg.getBuffer or not msg.getReadSize then
        return nil
    end
    local buffer = msg:getBuffer()
    if type(buffer) ~= 'string' then
        return nil
    end
    local idx = msg:getReadSize() + 1 + byteOffset
    local b1, b2, b3, b4 = string.byte(buffer, idx, idx + 3)
    if not b4 then
        return nil
    end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function bountyExtensionMarkerAtOffset(msg, byteOffset)
    byteOffset = byteOffset or 0
    if not msg or msg:getUnreadSize() < byteOffset + 8 or not msg.peekU32 then
        return false
    end
    for _, pair in ipairs(BOUNTY_EXTENSION_MARKER_U32_PAIRS) do
        if peekU32AtUnreadOffset(msg, byteOffset) == pair[1]
            and peekU32AtUnreadOffset(msg, byteOffset + 4) == pair[2] then
            return true
        end
    end
    return false
end

local function bountyExtensionMarkerAt(msg)
    return bountyExtensionMarkerAtOffset(msg, 0)
end

local function consumeBountyExtensionMarker(msg)
    if msg:getUnreadSize() < 8 then
        error('bounty extension marker: packet too short')
    end
    local lo = msg:peekU32()
    for _, pair in ipairs(BOUNTY_EXTENSION_MARKER_U32_PAIRS) do
        if lo == pair[1] then
            msg:getU32()
            if msg:peekU32() ~= pair[2] then
                error('bounty extension marker: bad second u32')
            end
            msg:getU32()
            return
        end
    end
    error(string.format('bounty extension marker mismatch (lo=0x%08X)', lo or 0))
end

local function safeTaskBoardSignal(callback, ...)
    if not callback then
        return
    end
    local ok, err = pcall(signalcall, callback, ...)
    if not ok then
        g_logger.error('[TaskBoard] UI handler error: ' .. tostring(err))
    end
end
local REROLL_DAILY_CLAIMABLE = 0

local STATE_ACTIVE = 2
local STATE_COMPLETED = 3

local PREFERRED_UNLOCK_COSTS = { 0, 300, 600, 900, 1200 }

local function usesTaskBoardProtocol()
    if not g_game.getFeature or not g_game.getFeature(GameColorizedLootValue) then
        return false
    end
    local version = g_game.getClientVersion()
    -- Same 8.60 custom window as item-value opcodes; server uses 0x53 for Task Board, not price list.
    return version >= 860 and version < 1200
end

local function readMonsterDisplay(msg)
    if msg:getUnreadSize() < 9 then
        error('monster display: packet too short')
    end
    local nameLen = msg:peekU16()
    if nameLen > MAX_MONSTER_NAME_LEN then
        error(string.format('monster display: invalid name length %s', tostring(nameLen)))
    end
    if msg:getUnreadSize() < 2 + nameLen + 7 then
        error('monster display: truncated entry')
    end
    local name = msg:getString()
    local lookType = msg:getU16()
    local outfit = {
        type = lookType,
        head = msg:getU8(),
        body = msg:getU8(),
        legs = msg:getU8(),
        feet = msg:getU8(),
        addons = msg:getU8(),
    }
    return name, outfit
end

local function skipMonsterDisplay(msg)
    readMonsterDisplay(msg)
end

local function skipMonsterDisplayBounded(msg)
    if msg:getUnreadSize() < 9 then
        return false
    end
    local nameLen = msg:peekU16()
    if nameLen > MAX_MONSTER_NAME_LEN then
        return false
    end
    local need = 2 + nameLen + 2 + 5
    if msg:getUnreadSize() < need then
        return false
    end
    readMonsterDisplay(msg)
    return true
end

local function consumeMonsterDisplay(msg)
    if not skipMonsterDisplayBounded(msg) then
        error('monster display: truncated entry')
    end
end

local function parseBountyAvailableCreaturesBody(msg, allRaceIds)
    consumeBountyExtensionMarker(msg)
    msg:getU16() -- preferredClearCost
    local availableCount = msg:getU16()
    if availableCount > 4096 then
        availableCount = 4096
    end
    local maxFit = math.floor(msg:getUnreadSize() / 9)
    if availableCount > maxFit then
        availableCount = maxFit
    end

    for _ = 1, availableCount do
        if msg:getUnreadSize() < 2 then
            break
        end
        local raceId = msg:getU16()
        local creatureName, creatureOutfit = readMonsterDisplay(msg)
        allRaceIds[#allRaceIds + 1] = {
            raceId = raceId,
            creatureName = creatureName,
            outfit = creatureOutfit,
        }
    end
    return true
end

local function tryParseBountyExtensionAt(msg, allRaceIds, byteOffset)
    if not bountyExtensionMarkerAtOffset(msg, byteOffset) then
        return false
    end
    for _ = 1, byteOffset do
        msg:getU8()
    end
    local ok, err = pcall(parseBountyAvailableCreaturesBody, msg, allRaceIds)
    if not ok then
        g_logger.error('[TaskBoard] bounty extension parse failed: ' .. tostring(err))
    end
    return ok
end

local function tryParseBountyExtension(msg, allRaceIds)
    if tryParseBountyExtensionAt(msg, allRaceIds, 0) then
        return true
    end
    if msg:getUnreadSize() >= 13 and tryParseBountyExtensionAt(msg, allRaceIds, 5) then
        return true
    end
    return false
end

-- Some server builds append a fixed 5-byte footer after preferred lists (no bestiary block).
local function bountyHeaderValidAt(msg, byteOffset)
    byteOffset = byteOffset or 0
    if msg:getUnreadSize() < byteOffset + 3 then
        return false
    end
    if peekU8AtUnreadOffset(msg, byteOffset) ~= SUB_BOUNTY then
        return false
    end
    local state = peekU8AtUnreadOffset(msg, byteOffset + 1)
    local difficulty = peekU8AtUnreadOffset(msg, byteOffset + 2)
    if state == nil or difficulty == nil or state > 3 or difficulty > 3 then
        return false
    end
    -- First creature name length (after subType + state + diff + raceId).
    if msg:getUnreadSize() < byteOffset + 7 then
        return false
    end
    local nameLen = peekU16AtUnreadOffset(msg, byteOffset + 5)
    if nameLen == nil or nameLen > MAX_MONSTER_NAME_LEN then
        return false
    end
    -- raceId(2) + string header + name + outfit(7) + kills block(11)
    local firstCreatureBytes = 2 + 2 + nameLen + 7 + 11
    if msg:getUnreadSize() < byteOffset + 3 + firstCreatureBytes then
        return false
    end
    -- Full bounty without preferred-list extension is ~120+ bytes.
    return msg:getUnreadSize() >= byteOffset + 95
end

local function taskBoardSubTypeLooksValid(msg, byteOffset)
    byteOffset = byteOffset or 0
    if msg:getUnreadSize() < byteOffset + 1 then
        return false
    end
    local subType = peekU8AtUnreadOffset(msg, byteOffset)
    if subType == nil or subType > SUB_WEEKLY_KILL then
        return false
    end
    if subType == SUB_BOUNTY then
        return bountyHeaderValidAt(msg, byteOffset)
    end
    if subType == SUB_BOUNTY_KILL or subType == SUB_WEEKLY_KILL then
        return msg:getUnreadSize() >= byteOffset + 8
    end
    if subType == SUB_WEEKLY then
        if msg:getUnreadSize() < byteOffset + 6 then
            return false
        end
        local killCount = peekU8AtUnreadOffset(msg, byteOffset + 5)
        return killCount ~= nil and killCount <= 32
    end
    return true
end

local function skipToNextInnerTaskBoardOpcode(msg)
    while msg:getUnreadSize() > 0 do
        if msg:peekU8() == OPCODE_TASK_BOARD then
            msg:getU8()
            return msg:getUnreadSize() > 0
        end
        msg:getU8()
    end
    return false
end

local function tryConsumeBountyFooter(msg)
    if msg:getUnreadSize() ~= 5 then
        return false
    end
    msg:getU32()
    msg:getU8()
    return true
end

local function parseBounty(msg)
    local state = msg:getU8()
    local difficulty = msg:getU8()
    if state > 3 or difficulty > 3 then
        error(string.format('invalid bounty header state=%s difficulty=%s', tostring(state), tostring(difficulty)))
    end

    local monsters = {}
    for i = 1, 3 do
        local raceId = msg:getU16()
        local creatureName, creatureOutfit
        if raceId > 0 then
            creatureName, creatureOutfit = readMonsterDisplay(msg)
        else
            consumeMonsterDisplay(msg)
            creatureName, creatureOutfit = '', { type = 0 }
        end
        local kills = msg:getU16()
        local required = msg:getU16()
        local rewardXp = msg:getU16()
        local rewardPoints = msg:getU16()
        local grade = msg:getU8()
        local claimState = msg:getU8()
        local taskIndex = msg:getU8()

        if raceId > 0 then
            local isActive = (state == STATE_ACTIVE or state == STATE_COMPLETED) and i == 1
            local isCompleted = state == STATE_COMPLETED or (required > 0 and kills >= required)
            monsters[#monsters + 1] = {
                taskIndex = taskIndex,
                raceId = raceId,
                creatureName = creatureName,
                outfit = creatureOutfit,
                currentKills = kills,
                totalKills = required,
                rewardXp = rewardXp,
                rewardPoints = rewardPoints,
                -- Server does not send per-task reroll reward; retail UI shows +1 token on claim.
                rewardReroll = 1,
                rarity = grade,
                isActive = isActive and 1 or 0,
                isCompleted = isCompleted and 1 or 0,
            }
        end
    end

    local rerollTokens = msg:getU8()
    local rerollMode = msg:getU8()
    msg:getU32() -- rerollTimestamp
    msg:getU8() -- upgrade

    local talismans = {}
    for i = 1, 4 do
        local tier1 = msg:getU8()
        local tier2 = msg:getU8()
        local upgradeFlag = msg:getU8()
        local ptsToUpgrade = msg:getU16()
        talismans[#talismans + 1] = {
            currentValue = tier1,
            upgradeCost = ptsToUpgrade,
            isActiveUpgrade = upgradeFlag,
        }
    end

    msg:getU8() -- preferredSlots (active count hint)
    local preferredSlots = {}
    for i = 1, 5 do
        local active = msg:getU8()
        local preferred = msg:getU16()
        local unwanted = msg:getU16()
        preferredSlots[#preferredSlots + 1] = {
            slot = i - 1,
            locked = active == 0 and 1 or 0,
            preferred = preferred,
            unwanted = unwanted,
            price = PREFERRED_UNLOCK_COSTS[i] or 0,
        }
    end

    local allRaceIds = {}
    if not tryParseBountyExtension(msg, allRaceIds) then
        tryConsumeBountyFooter(msg)
    end

    local bountyKillBoostRemaining = 0
    if msg:getUnreadSize() >= 4 then
        bountyKillBoostRemaining = msg:getU32()
    end

    local header = {
        difficulty = difficulty + 1,
        rerollPoints = rerollTokens,
        claimDaily = rerollMode == REROLL_DAILY_CLAIMABLE and 1 or 0,
        bountyKillBoostRemaining = bountyKillBoostRemaining,
    }

    safeTaskBoardSignal(g_game.onBountyTaskData, header, monsters, talismans)
    safeTaskBoardSignal(g_game.onBountyPreferredData, preferredSlots, nil, allRaceIds)
    return true
end

local function parseWeekly(msg)
    local anyCurrent = msg:getU16()
    local anyTotal = msg:getU16()

    local monsters = {
        {
            raceId = 0,
            current = anyCurrent,
            total = anyTotal,
            state = (anyTotal > 0 and anyCurrent >= anyTotal) and 1 or 0,
        },
    }

    local killCount = msg:getU8()
    if killCount > 32 then
        error(string.format('weekly: invalid killCount=%s', tostring(killCount)))
    end
    for _ = 1, killCount do
        local raceId = msg:getU16()
        local creatureName, creatureOutfit
        if raceId > 0 then
            creatureName, creatureOutfit = readMonsterDisplay(msg)
        else
            consumeMonsterDisplay(msg)
            creatureName, creatureOutfit = '', { type = 0 }
        end
        local kills = msg:getU16()
        local required = msg:getU16()
        local grade = msg:getU8()
        monsters[#monsters + 1] = {
            raceId = raceId,
            creatureName = creatureName,
            outfit = creatureOutfit,
            current = kills,
            total = required,
            state = (required > 0 and kills >= required) and 1 or grade,
        }
    end

    local items = {}
    local deliveryCount = msg:getU8()
    if deliveryCount > 32 then
        error(string.format('weekly: invalid deliveryCount=%s', tostring(deliveryCount)))
    end
    -- Per delivery: itemId u16 + clientId u16 + amount u8 + required u8 + available u32 + delivered u8 = 11
    local weeklyTailBytes = 26
    if msg:getUnreadSize() < deliveryCount * 11 + weeklyTailBytes then
        error('weekly: truncated delivery block')
    end
    for slotIndex = 0, deliveryCount - 1 do
        local itemId = msg:getU16()
        local clientId = msg:getU16()
        local amount = msg:getU8()
        local required = msg:getU8()
        local available = msg:getU32()
        local delivered = msg:getU8()
        items[#items + 1] = {
            slotIndex = slotIndex,
            itemId = itemId,
            clientId = clientId,
            current = amount,
            total = required,
            available = available,
            claimed = delivered,
            state = delivered,
        }
    end

    local difficulty = msg:getU8()
    local killExp = msg:getU32()
    local deliveryExp = msg:getU32()
    local completedKills = msg:getU8()
    local completedDeliveries = msg:getU8()
    local weeklyProgress = msg:getU8()
    local huntingPts = msg:getU32()
    local soulseals = msg:getU32()
    msg:getU32() -- soulsealsBalance
    msg:getU8() -- needsReward
    msg:getU8() -- hasExpansion

    local weeklyKillBoostRemaining = 0
    local weeklyReducedItemsRemaining = 0
    if msg:getUnreadSize() >= 8 then
        weeklyKillBoostRemaining = msg:getU32()
        weeklyReducedItemsRemaining = msg:getU32()
    end

    local header = {
        completedKillTasks = completedKills,
        completedDeliveryTasks = completedDeliveries,
        pointsEarned = huntingPts,
        soulsealsEarned = soulseals,
        killTaskRewardExp = killExp,
        deliveryTaskRewardExp = deliveryExp,
        resetTimestamp = 0,
        weeklyProgressFinished = weeklyProgress,
        unlockedDifficulty = difficulty + 1,
        weeklyKillBoostRemaining = weeklyKillBoostRemaining,
        weeklyReducedItemsRemaining = weeklyReducedItemsRemaining,
    }

    safeTaskBoardSignal(g_game.onWeeklyTaskData, header, monsters, items)
    return true
end

local function parseHuntShop(msg)
    local taskHuntingPoints = msg:getU32()
    local offerCount = msg:getU8()
    local offers = {}
    for _ = 1, offerCount do
        local id = msg:getU8()
        local title = msg:getString()
        local count = msg:getU16()
        local price = msg:getU32()
        local bought = msg:getU8()
        local offerType = msg:getU8()

        local itemId = 0
        local lookType = 0
        local lookAddons = 0
        if offerType == 0 or offerType == 3 then
            itemId = msg:getU16()
        elseif offerType == 1 then
            lookType = msg:getU16()
        elseif offerType == 2 then
            lookType = msg:getU16()
            lookAddons = msg:getU16()
        elseif offerType == 5 then
            msg:getU8()
        end

        offers[#offers + 1] = {
            id = id,
            title = title,
            description = count > 0 and tostring(count) or "",
            price = price,
            bought = bought,
            offerType = offerType,
            itemId = itemId,
            lookType = lookType,
            lookAddons = lookAddons,
            maxPurchases = 0,
            currentPurchases = bought,
            nextCost = 0,
        }
    end

    safeTaskBoardSignal(g_game.onTaskHuntingShopData, offers, taskHuntingPoints)
    return true
end

local function parseSoulSeals(msg)
    msg:getU32() -- balance
    local count = msg:getU16()
    for _ = 1, count do
        msg:getU16()
        skipMonsterDisplay(msg)
        msg:getU8()
        msg:getU32()
        msg:getU8()
    end
    return true
end

local function parseKillUpdate(msg, weekly)
    local raceId = msg:getU16()
    local current = msg:getU16()
    local total = msg:getU16()
    local completed = msg:getU8()

    if weekly then
        safeTaskBoardSignal(g_game.onWeeklyKillUpdate, {
            raceId = raceId,
            totalMonsterKilleds = current,
            totalKills = total,
            state = completed,
        })
    else
        safeTaskBoardSignal(g_game.onBountyKillUpdate, {
            raceId = raceId,
            monstersKilled = current,
            totalKills = total,
            isCompleted = completed == 1,
        })
    end
    return true
end

local function parseTaskBoardSubPacket(msg, subType)
    if subType == SUB_BOUNTY then
        parseBounty(msg)
    elseif subType == SUB_WEEKLY then
        parseWeekly(msg)
    elseif subType == SUB_HUNT_SHOP then
        parseHuntShop(msg)
    elseif subType == SUB_SOUL_SEALS then
        parseSoulSeals(msg)
    elseif subType == SUB_BOUNTY_KILL then
        parseKillUpdate(msg, false)
    elseif subType == SUB_WEEKLY_KILL then
        parseKillUpdate(msg, true)
    end
end

local function parseOneTaskBoardFrame(msg)
    if msg:getUnreadSize() < 1 then
        return false, 'empty frame'
    end

    if msg:peekU8() == OPCODE_TASK_BOARD then
        msg:getU8()
        if msg:getUnreadSize() < 1 then
            return false, 'empty after inner opcode'
        end
    end

    if not taskBoardSubTypeLooksValid(msg, 0) then
        return false, 'invalid frame header'
    end

    local subType = msg:peekU8()
    if (subType == SUB_BOUNTY_KILL or subType == SUB_WEEKLY_KILL) and msg:getUnreadSize() < 8 then
        return false, 'short kill update'
    end

    subType = msg:getU8()
    local label = 'subType ' .. tostring(subType)
    local ok, err = pcall(parseTaskBoardSubPacket, msg, subType)
    if not ok then
        return false, label .. ': ' .. tostring(err)
    end
    return true
end

local function onTaskBoardOpcode(_, msg)
    if not usesTaskBoardProtocol() then
        return false
    end

    if not msg or not msg.getUnreadSize or not msg.peekU8 then
        return true
    end

    if msg:getUnreadSize() < 1 then
        return true
    end

    local framesParsed = 0
    while framesParsed < MAX_TASK_BOARD_CHAIN_STEPS and msg:getUnreadSize() > 0 do
        if framesParsed > 0 and msg:peekU8() ~= OPCODE_TASK_BOARD then
            break
        end

        local ok, err = parseOneTaskBoardFrame(msg)
        if ok then
            framesParsed = framesParsed + 1
        else
            g_logger.error('[TaskBoard] parse failed (' .. tostring(err) .. ')')
            if not skipToNextInnerTaskBoardOpcode(msg) then
                break
            end
        end
    end

    return true
end

local function registerTaskBoardOpcode()
    if not ProtocolGame or not ProtocolGame.registerOpcode or not usesTaskBoardProtocol() then
        return
    end
    pcall(function()
        ProtocolGame.unregisterOpcode(OPCODE_TASK_BOARD)
    end)
    ProtocolGame.registerOpcode(OPCODE_TASK_BOARD, onTaskBoardOpcode)
end

local function unregisterTaskBoardOpcode()
    if not ProtocolGame or not ProtocolGame.unregisterOpcode then
        return
    end
    pcall(function()
        ProtocolGame.unregisterOpcode(OPCODE_TASK_BOARD)
    end)
end

if g_game then
    if _G._taskBoardProtocolCallbacks then
        disconnect(g_game, _G._taskBoardProtocolCallbacks)
    end
    _G._taskBoardProtocolCallbacks = {
        onGameStart = registerTaskBoardOpcode,
        onGameEnd = unregisterTaskBoardOpcode,
    }
    connect(g_game, _G._taskBoardProtocolCallbacks)
end
registerTaskBoardOpcode()
