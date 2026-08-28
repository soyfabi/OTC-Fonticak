notificationsController = Controller:new()
function notificationsController:onInit()
    self:registerEvents(g_game, {
        onClientEvent = function(...)
            self:onClientEvent(...)
        end,
    })
end
function notificationsController:onTerminate()
    screenshot_onTerminate()
    infoBanner_onTerminate()
end

local playerLevels = {}
local playerSkills = {}
local playerBaseMagicLevel = nil
local notificationTextMessageModes = {}
local notificationTextMessageCallback = nil

local ScreenshotType = {
    ACHIEVEMENT = 1,
    BESTIARY_ENTRY_COMPLETED = 2,
    BESTIARY_ENTRY_UNLOCKED = 3
}

local otcToProtoSkill = {
    [0] = 5, -- Fist
    [1] = 3, -- Club
    [2] = 2, -- Sword
    [3] = 4, -- Axe
    [4] = 6, -- Distance
    [5] = 7, -- Shielding
    [6] = 8  -- Fishing
}

local function getAchievementName(message)
    if not message then
        return nil
    end

    return message:match("[Yy]ou have earned ['\"]([^'\"]+)['\"]") or
           message:match("[Yy]ou earned ['\"]([^'\"]+)['\"]") or
           message:match("[Aa]chievement[ '%\"]+([^'\"]+)['\"]?")
end

local function findBestiaryOutfitByName(name)
    if not name or name == "" then
        return nil, nil
    end
    local cleanName = name:lower():gsub("^['\"%s]+", ""):gsub("['\"%s%.]+$", "")

    if protoData then
        for raceId, outfit in pairs(protoData) do
            if outfit and outfit.name and outfit.name:lower():gsub("^['\"%s]+", ""):gsub("['\"%s%.]+$", "") == cleanName then
                return raceId, outfit
            end
        end
    end

    if g_creatures and g_creatures.getCreatureByName then
        local ok, cType = pcall(function() return g_creatures.getCreatureByName(name) end)
        if ok and cType and not cType:isNull() then
            local outfit = cType:getOutfit()
            if outfit and (outfit.type and outfit.type > 0 or outfit.lookType and outfit.lookType > 0) then
                return 0, outfit
            end
        end
    end

    if g_map and g_game.getLocalPlayer() then
        local localPos = g_game.getLocalPlayer():getPosition()
        if localPos then
            local specs = g_map.getSpectators(localPos, false)
            for _, spec in ipairs(specs) do
                if spec and spec:isMonster() and spec:getName():lower() == cleanName then
                    return 0, spec:getOutfit()
                end
            end
        end
    end

    if g_things and g_things.getRacesByName then
        local ok, races = pcall(function() return g_things.getRacesByName(name) end)
        if ok and races and #races > 0 then
            local r = races[1]
            if r and (r.raceId or r.outfit) then
                return r.raceId, r.outfit
            end
        end
    end
    return nil, nil
end

local function cleanCreatureName(name)
    if not name then return nil end
    name = name:gsub("^['\"%s]+", ""):gsub("['\"%s%.]+$", "")
    return name
end

local function getBestiaryProgressFromMessage(message)
    if not message then
        return nil, nil
    end

    local progressText, creatureName = message:match("[Yy]ou have progressed ['\"](.- for ([^'\"]+))['\"]")
    if progressText and creatureName then
        return progressText, cleanCreatureName(creatureName)
    end

    progressText, creatureName = message:match("[Yy]ou have completed ['\"](.- for ([^'\"]+))['\"]")
    if progressText and creatureName then
        return progressText, cleanCreatureName(creatureName)
    end

    progressText, creatureName = message:match("[Yy]ou have unlocked ['\"](.- for ([^'\"]+))['\"]")
    if progressText and creatureName then
        return progressText, cleanCreatureName(creatureName)
    end

    creatureName = message:match("[Yy]ou [^%s]+ the first [Bb]estiary stage for (.+)")
    if creatureName then
        creatureName = cleanCreatureName(creatureName)
        return string.format("the first Bestiary stage for %s", creatureName), creatureName
    end

    creatureName = message:match("[Yy]ou [^%s]+ the second [Bb]estiary stage for (.+)")
    if creatureName then
        creatureName = cleanCreatureName(creatureName)
        return string.format("the second Bestiary stage for %s", creatureName), creatureName
    end

    creatureName = message:match("[Yy]ou [^%s]+ the completed [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou [^%s]+ [^%s]+ completed [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou completed the [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou have completed the [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou finished the [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou have finished the [Bb]estiary entry for (.+)")
    if creatureName then
        creatureName = cleanCreatureName(creatureName)
        return string.format("the completed Bestiary entry for %s", creatureName), creatureName
    end

    creatureName = message:match("[Yy]ou [^%s]+ the [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou [^%s]+ [^%s]+ [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou unlocked the [Bb]estiary entry for (.+)") or
                   message:match("[Yy]ou have unlocked the [Bb]estiary entry for (.+)")
    if creatureName then
        creatureName = cleanCreatureName(creatureName)
        return string.format("the Bestiary entry for %s", creatureName), creatureName
    end

    progressText = message:match("[Yy]ou have progressed ['\"]([^'\"]+)['\"]") or
                   message:match("[Yy]ou have completed ['\"]([^'\"]+)['\"]") or
                   message:match("[Yy]ou have unlocked ['\"]([^'\"]+)['\"]")
    if progressText then
        creatureName = progressText:match("for (.+)$")
        return progressText, cleanCreatureName(creatureName)
    end

    return nil, nil
end

local function onNotificationTextMessage(mode, message)
    local lowerMessage = message and message:lower() or ""
    if lowerMessage:find("soul", 1, true) and
       (lowerMessage:find("don't have enough", 1, true) or lowerMessage:find("do not have enough", 1, true) or lowerMessage:find("not enough", 1, true)) then
        showOutOfSoulPointsBanner()
    end

    if lowerMessage:find("no ammunition", 1, true) or
       lowerMessage:find("no ammo", 1, true) or
       lowerMessage:find("no arrows", 1, true) or
       lowerMessage:find("no bolts", 1, true) or
       lowerMessage:find("out of ammo", 1, true) or
       lowerMessage:find("out of ammunition", 1, true) or
       lowerMessage:find("need ammunition", 1, true) or
       lowerMessage:find("sin munici", 1, true) then
        showOutOfAmmoBanner()
    end

    local achievementName = getAchievementName(message)
    if achievementName then
        showAchievementBanner(achievementName)
    end

    local bestiaryProgress, creatureName = getBestiaryProgressFromMessage(message)
    if bestiaryProgress then
        local raceId, raceOutfit = findBestiaryOutfitByName(creatureName)
        showBestiaryBanner(raceId or 0, bestiaryProgress, raceOutfit)
    end
end

local function registerNotificationMessageModes()
    notificationTextMessageCallback = notificationTextMessageCallback or onNotificationTextMessage
    notificationTextMessageModes = {
        MessageModes.Failure,
        MessageModes.Game,
        MessageModes.Status,
        MessageModes.Login
    }

    for _, mode in ipairs(notificationTextMessageModes) do
        registerMessageMode(mode, notificationTextMessageCallback)
    end
end

local function unregisterNotificationMessageModes()
    if not notificationTextMessageCallback then
        return
    end

    for _, mode in ipairs(notificationTextMessageModes) do
        unregisterMessageMode(mode, notificationTextMessageCallback)
    end
    notificationTextMessageModes = {}
end

function notificationsController:onGameStart()
    screenshot_onGameStart()

    playerLevels = {}
    playerSkills = {}
    playerBaseMagicLevel = nil
    self.recentAdvanceEvents = {}
    self.activeAdvanceKey = nil
    self.recentClientEvents = {}

    local player = g_game.getLocalPlayer()
    if player then
        local charName = player:getName()
        if charName then
            playerLevels[charName] = player:getLevel()
        end
        playerBaseMagicLevel = player:getBaseMagicLevel()
        for id, protoId in pairs(otcToProtoSkill) do
            playerSkills[protoId] = {
                baseLevel = player:getSkillBaseLevel(id),
                effectiveLevel = player:getSkillLevel(id),
                percent = player:getSkillLevelPercent(id)
            }
        end
    end

    self:registerEvents(LocalPlayer, {
        onTakeScreenshot = function(player, screenshotType)
            if screenshotType == ScreenshotType.ACHIEVEMENT then
                showAchievementBanner()
            end
        end,
        onLevelChange = function(player, level, percent, oldLevel)
            local charName = player:getName()
            oldLevel = playerLevels[charName] or oldLevel
            if not oldLevel or oldLevel == 0 then
                playerLevels[charName] = level
                return
            end
            if level > oldLevel then
                for l = oldLevel + 1, level do
                    self:onClientEvent(4, l)
                    -- Client-side level detection must trigger auto-screenshots
                    -- (many OT servers never send GameServerTakeScreenshot).
                    if type(onScreenShot) == 'function' then
                        onScreenShot(7) -- ScreenshotType.LEVEL_UP
                    end
                end
            end
            playerLevels[charName] = level
        end,
        onBaseMagicLevelChange = function(player, baseMagicLevel, oldBaseMagicLevel)
            oldBaseMagicLevel = playerBaseMagicLevel or oldBaseMagicLevel
            if not oldBaseMagicLevel or oldBaseMagicLevel == 0 then
                playerBaseMagicLevel = baseMagicLevel
                return
            end
            if baseMagicLevel > oldBaseMagicLevel then
                for l = oldBaseMagicLevel + 1, baseMagicLevel do
                    self:onClientEvent(5, 1, l)
                    if type(onScreenShot) == 'function' then
                        onScreenShot(12) -- ScreenshotType.SKILL_UP
                    end
                end
            end
            playerBaseMagicLevel = baseMagicLevel
        end,
        onSkillChange = function(player, id, level, percent)
            local protoId = otcToProtoSkill[id]
            if not protoId then return end

            local skillState = playerSkills[protoId] or {}
            skillState.previousPercent = skillState.percent
            skillState.effectiveLevel = level
            skillState.percent = percent
            skillState.baseLevel = skillState.baseLevel or player:getSkillBaseLevel(id)
            playerSkills[protoId] = skillState
        end,
        onBaseSkillChange = function(player, id, baseLevel, oldBaseLevel)
            local protoId = otcToProtoSkill[id]
            if not protoId then return end
            local skillState = playerSkills[protoId] or {}
            oldBaseLevel = skillState.baseLevel or oldBaseLevel
            if not oldBaseLevel or oldBaseLevel == 0 then
                skillState.baseLevel = baseLevel
                skillState.effectiveLevel = skillState.effectiveLevel or player:getSkillLevel(id)
                skillState.percent = skillState.percent or player:getSkillLevelPercent(id)
                playerSkills[protoId] = skillState
                return
            end

            local oldPercent = skillState.previousPercent
            local currentPercent = player:getSkillLevelPercent(id)
            local accepted = baseLevel > oldBaseLevel and oldPercent ~= nil and currentPercent < oldPercent
            g_logger.debug(string.format(
                "notifications: skill base change skill=%s old=%s new=%s percent=%s oldPercent=%s accepted=%s",
                tostring(protoId),
                tostring(oldBaseLevel),
                tostring(baseLevel),
                tostring(currentPercent),
                tostring(oldPercent),
                tostring(accepted)
            ))

            if baseLevel > oldBaseLevel then
                if accepted then
                    for l = oldBaseLevel + 1, baseLevel do
                        self:onClientEvent(5, protoId, l)
                        if type(onScreenShot) == 'function' then
                            onScreenShot(12) -- ScreenshotType.SKILL_UP
                        end
                    end
                end
            end
            skillState.baseLevel = baseLevel
            skillState.effectiveLevel = player:getSkillLevel(id)
            skillState.percent = currentPercent
            skillState.previousPercent = nil
            playerSkills[protoId] = skillState
        end
    })

    registerNotificationMessageModes()
end

function notificationsController:onGameEnd()
    unregisterNotificationMessageModes()
    screenshot_onGameEnd()
end

function showBestiaryProgress(raceId, progress, raceOutfit)
    local name = raceOutfit and raceOutfit.name or (protoData and protoData[raceId] and protoData[raceId].name) or ""
    local nameSuffix = name ~= "" and (" for " .. name) or ""

    local progressText = ({
        [1] = "the Bestiary entry" .. nameSuffix,
        [2] = "the first Bestiary stage" .. nameSuffix,
        [3] = "the second Bestiary stage" .. nameSuffix,
        [4] = "the completed Bestiary entry" .. nameSuffix
    })[progress] or string.format("Bestiary stage %s%s", tostring(progress), nameSuffix)

    showBestiaryBanner(raceId, progressText, raceOutfit)
end
