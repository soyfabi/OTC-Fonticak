-- Client -> server Task Board actions (opcode 0x5F), Forgotten Server wire format.

local OPCODE_TASK_BOARD_ACTION = 0x5F

local ACTION_OPEN_BOUNTY = 0
local ACTION_OPEN_WEEKLY = 1
local ACTION_CHANGE_DIFFICULTY = 2
local ACTION_REROLL_TASKS = 3
local ACTION_CLAIM_DAILY = 4
local ACTION_SELECT_TASK = 5
local ACTION_CLAIM_REWARD = 6
local ACTION_TALISMAN_UPGRADE = 7
local ACTION_WEEKLY_DELIVER = 8
local ACTION_WEEKLY_SELECT_DIFFICULTY = 9
local ACTION_OPEN_HUNT_SHOP = 10
local ACTION_BUY_SHOP_OFFER = 11
local ACTION_UNLOCK_PREFERRED = 12
local ACTION_CLEAR_PREFERRED = 13
local ACTION_CLEAR_UNWANTED = 14
local ACTION_ASSIGN_PREFERRED = 15
local ACTION_ASSIGN_UNWANTED = 16
local ACTION_OPEN_PREFERRED = 18

-- UI uses 0-based slot rows; server bounty preferred actions use slots 1..5.
local function preferredListSlotIndex(uiSlot)
    return (tonumber(uiSlot) or 0) + 1
end

local function sendTaskBoardAction(option, value, extraValue)
    if not g_game.isOnline() then
        return false
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return false
    end

    value = value or 0
    extraValue = extraValue or 0

    local msg = OutputMessage.create()
    msg:addU8(OPCODE_TASK_BOARD_ACTION)
    msg:addU8(option)

    if option == ACTION_CHANGE_DIFFICULTY or option == ACTION_SELECT_TASK or option == ACTION_TALISMAN_UPGRADE or
        option == ACTION_WEEKLY_DELIVER or option == ACTION_WEEKLY_SELECT_DIFFICULTY then
        msg:addU8(value)
    elseif option == ACTION_BUY_SHOP_OFFER then
        msg:addU8(value)
    elseif option == ACTION_UNLOCK_PREFERRED or option == ACTION_CLEAR_PREFERRED or option == ACTION_CLEAR_UNWANTED then
        msg:addU16(value)
    elseif option == ACTION_ASSIGN_PREFERRED or option == ACTION_ASSIGN_UNWANTED then
        msg:addU16(value)
        msg:addU16(extraValue)
    end

    protocol:send(msg)
    return true
end

local function installTaskBoardSendCompat()
    g_game.sendOpenMenuTaskBoardAction = function(tab)
        local map = {
            [0] = ACTION_OPEN_BOUNTY,
            [1] = ACTION_OPEN_WEEKLY,
            [2] = ACTION_OPEN_HUNT_SHOP,
        }
        return sendTaskBoardAction(map[tab] or ACTION_OPEN_BOUNTY)
    end

    g_game.requestWeeklyTaskData = function()
        return sendTaskBoardAction(ACTION_OPEN_WEEKLY)
    end

    g_game.sendRerollTasks = function()
        return sendTaskBoardAction(ACTION_REROLL_TASKS)
    end

    g_game.sendClaimDaily = function()
        return sendTaskBoardAction(ACTION_CLAIM_DAILY)
    end

    g_game.sendClaimReward = function()
        return sendTaskBoardAction(ACTION_CLAIM_REWARD)
    end

    g_game.sendSelectTask = function(taskIndex)
        return sendTaskBoardAction(ACTION_SELECT_TASK, taskIndex)
    end

    g_game.sendSelectTaskDifficulty = function(difficulty)
        return sendTaskBoardAction(ACTION_CHANGE_DIFFICULTY, difficulty)
    end

    g_game.sendUpgradeTalisman = function(pathIndex)
        return sendTaskBoardAction(ACTION_TALISMAN_UPGRADE, pathIndex)
    end

    g_game.sendDeliveryTask = function(taskIndex)
        return sendTaskBoardAction(ACTION_WEEKLY_DELIVER, taskIndex)
    end

    g_game.sendSelectDifficultyWeeklyTasks = function(difficulty)
        return sendTaskBoardAction(ACTION_WEEKLY_SELECT_DIFFICULTY, difficulty)
    end

    g_game.sendOnBuyHuntingTaskShop = function(offerIndex)
        return sendTaskBoardAction(ACTION_BUY_SHOP_OFFER, offerIndex)
    end

    g_game.sendPreferredListUnlockSlots = function(slot)
        return sendTaskBoardAction(ACTION_UNLOCK_PREFERRED, preferredListSlotIndex(slot))
    end

    g_game.sendPreferredListClearPreferred = function(slot)
        return sendTaskBoardAction(ACTION_CLEAR_PREFERRED, preferredListSlotIndex(slot))
    end

    g_game.sendPreferredListClearUnwanted = function(slot)
        return sendTaskBoardAction(ACTION_CLEAR_UNWANTED, preferredListSlotIndex(slot))
    end

    g_game.sendPreferredListPreferred = function(slot, raceId)
        return sendTaskBoardAction(ACTION_ASSIGN_PREFERRED, preferredListSlotIndex(slot), raceId)
    end

    g_game.sendPreferredListUnwanted = function(slot, raceId)
        return sendTaskBoardAction(ACTION_ASSIGN_UNWANTED, preferredListSlotIndex(slot), raceId)
    end

    g_game.sendOpenPreferredList = function()
        return sendTaskBoardAction(ACTION_OPEN_PREFERRED)
    end

    g_game.sendResourceBalance = function()
        -- Balances are pushed by the server (0xEE) when opening task board tabs.
        return true
    end
end

installTaskBoardSendCompat()
