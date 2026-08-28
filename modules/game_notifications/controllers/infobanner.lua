

local OPEN_FRAMES = {
    "/images/infobanner/animation/anim0",
    "/images/infobanner/animation/anim1",
    "/images/infobanner/animation/anim2", 
    "/images/infobanner/animation/anim3",
    "/images/infobanner/animation/anim4",
    "/images/infobanner/animation/anim5",
    "/images/infobanner/animation/anim6", 
    "/images/infobanner/animation/anim7"
}

local MAX_WIDTH = 289
local BANNER_HEIGHT = 88
local FRAME_MS = 35
local DEFAULT_HOLD_MS = 3000
local FADE_IN_MS = 280
local FADE_OUT_MS = 220
local FADE_INTERVAL_MS = 16
local ICON_SHOW_PROGRESS = 0.25
local ICON_HIDE_PROGRESS = 0.25
local BANNER_MARGIN_OFFSET = 10
local ANIM_OFFSET = 10
local TOTAL_FRAMES = #OPEN_FRAMES
-- Slide the whole banner from left into the centered placement.
local SLIDE_OFFSET = 240
local SLIDE_IN_MS = 280
local SLIDE_OUT_MS = 220

local function easeOutQuad(t)
    return t * (2 - t)
end

local eventCategory = {
    CLIENT_EVENT_TYPE_SIMPLE = 1,
    CLIENT_EVENT_TYPE_ACHIEVEMENT = 2,
    CLIENT_EVENT_TYPE_TITLE = 3,
    CLIENT_EVENT_TYPE_LEVEL = 4,
    CLIENT_EVENT_TYPE_SKILL = 5,
    CLIENT_EVENT_TYPE_BESTIARY = 6,
    CLIENT_EVENT_TYPE_BOSSTIARY = 7,
    CLIENT_EVENT_TYPE_QUEST = 8,
    CLIENT_EVENT_TYPE_COSMETIC = 9,
    CLIENT_EVENT_TYPE_PROFICIENCY = 10,
    CLIENT_EVENT_TYPE_LAST = 11
}

local eventType = {
    CLIENT_EVENT_NONE = 0,
    CLIENT_EVENT_BOSSDEFEATED = 1,
    CLIENT_EVENT_DEATHPVE = 2,
    CLIENT_EVENT_DEATHPVP = 3,
    CLIENT_EVENT_PLAYERKILLASSIST = 4,
    CLIENT_EVENT_PLAYERKILL = 5,
    CLIENT_EVENT_PLAYERATTACKING = 6,
    CLIENT_EVENT_TREASUREFOUND = 7,
    CLIENT_EVENT_GIFTOFLIFE = 8,
    CLIENT_EVENT_ATTACKSTOPPED = 9,
    CLIENT_EVENT_CAPACITYLIMIT = 10,
    CLIENT_EVENT_OUTOFAMMO = 11,
    CLIENT_EVENT_TARGETTOOCLOSE = 12,
    CLIENT_EVENT_OUTOFSOULPOINTS = 13,
    CLIENT_EVENT_TUTORIALCOMPLETE = 14,
    CLIENT_EVENT_LAST = 15
}

local skinType = {
    outfit = 0,
    addon1 = 1,
    addon2 = 2,
    mount = 3
}

local SkillId = {
    Magic = 1,
    Sword = 2,
    Club = 3,
    Axe = 4,
    Fist = 5,
    Distance = 6,
    Shielding = 7,
    Fishing = 8
}

local skillNames = {
    [SkillId.Magic]     = { name = "Magic Level",        icon = "magic" },
    [SkillId.Sword]     = { name = "Sword Fighting",     icon = "sword" },
    [SkillId.Club]      = { name = "Club Fighting",      icon = "club" },
    [SkillId.Axe]       = { name = "Axe Fighting",       icon = "axe" },
    [SkillId.Fist]      = { name = "Fist Fighting",      icon = "fist" },
    [SkillId.Distance]  = { name = "Distance Fighting",  icon = "distance" },
    [SkillId.Shielding] = { name = "Shielding",          icon = "shielding" },
    [SkillId.Fishing]   = { name = "Fishing",            icon = "fishing" }
}

local infoPopUp = {
    [eventCategory.CLIENT_EVENT_TYPE_COSMETIC] = {
        --type(int), lookType(int), skinName(string), skinType(int)
        {
            title = "Outfit Unlocked",
            description = "You have unlocked '%s'", --skinName
            hasCreatureId = true,
            img = "/images/infobanner/icons/unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_BOSSTIARY] = {
        --type(int), raceId(int), progressLevel(int)
        {
            title = "Bosstiary Progress",
            description = "You have progressed '%s'",--progressLevel
            hasRaceId = true,
            img = "/images/infobanner/icons/unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_BESTIARY] = {
        --type(int), raceId(int), progressLevel(int)
        {
            title = "Bestiary Progress",
            description = "You have progressed '%s'", --progressLevel
            hasRaceId = true,
            img = "/images/infobanner/icons/unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_ACHIEVEMENT] = {
        -- type(int), name(string)
        {
            title = "New Achievement",
            description = "You have earned '%s'", --name
            img = "/images/infobanner/icons/achievements"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_TITLE] = {
        -- type(int), name(string)
        {
            title = "Title Gained",
            description = "You have earned '%s'", --name
            img = "/images/infobanner/icons/title"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_PROFICIENCY] = {
        -- type(int), itemId(int), message(string)
        {
            title = "Weapon Proficiency",
            description = "you have improved '%s'", -- message
            hasItemId = true,
            img = "/images/infobanner/icons/unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_QUEST] = {
        -- type(int), questName(string), isCompleted(bool)
        [true] = { -- isCompleted(bool)
            title = "Quest completed",
            description = "You have finished '%s'",
            img = "/images/infobanner/icons/quests"
        },
        [false] = { -- isCompleted(bool)
            title = "Quest started",
            description = "You have begun '%s'",
            img = "/images/infobanner/icons/quests"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_LEVEL] = {
        {
            title = "Level %d!",
            description = "You gained hit points, mana, and capacity.",
            img = "/images/infobanner/icons/levelup"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_SKILL] = {
        -- type(int), skillId(int), level(int)
        {
            title = "%s",
            description = "Your skill has advanced to level %d",
            img = "/images/infobanner/icons/skills/%s"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_SIMPLE] = {
        -- type(int), eventType(int)  
        [eventType.CLIENT_EVENT_CAPACITYLIMIT] = {
            title = "Capacity Limit",
            description = "Remove items before adding new ones.",
            img = "/images/infobanner/icons/quests"
        },
        [eventType.CLIENT_EVENT_OUTOFAMMO] = {
            title = "Out of Ammunition",
            description = "You have no arrow or bolt equipped.",
            img = "/images/infobanner/icons/hint"
        },
        [eventType.CLIENT_EVENT_TARGETTOOCLOSE] = {
            title = "Target Too Close",
            description = "You are using a ranged auto-attack at melee distance.",
            img = "/images/infobanner/icons/hint"
        },
        [eventType.CLIENT_EVENT_OUTOFSOULPOINTS] = {
            title = "Out of Soul Points",
            description = "You don't have enough soul points to cast this spell.",
            img = "/images/infobanner/icons/hint"
        },
        [eventType.CLIENT_EVENT_TUTORIALCOMPLETE] = {
            title = "Off to New Shores",
            description = "Leave the village and set sail to start your real adventure.",
            img = "/images/infobanner/icons/offtonewshores"
        }
    }
}

-- LuaFormatter on

notificationsController.event = nil
notificationsController.state = "idle"
notificationsController.queue = {}
notificationsController.widgets = {}
notificationsController.recentAdvanceEvents = {}
notificationsController.activeAdvanceKey = nil
notificationsController.recentClientEvents = {}

local function getAdvanceKey(eventCat, ...)
    local args = {...}
    if eventCat == eventCategory.CLIENT_EVENT_TYPE_LEVEL then
        return string.format("level:%s", tostring(args[1]))
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_SKILL then
        return string.format("skill:%s:%s", tostring(args[1]), tostring(args[2]))
    end
    return nil
end

local function refreshAdvanceText(item)
    if not item or not item.extraData then
        return
    end

    local extraData = item.extraData
    if extraData.advanceType == "level" then
        local popupTemplate = infoPopUp[eventCategory.CLIENT_EVENT_TYPE_LEVEL][1]
        item.title = popupTemplate.title:format(extraData.level)
        item.desc = popupTemplate.description
        item.img = popupTemplate.img
    elseif extraData.advanceType == "skill" then
        local popupTemplate = infoPopUp[eventCategory.CLIENT_EVENT_TYPE_SKILL][1]
        local data = skillNames[extraData.skillId] or {
            name = "Skill",
            icon = "fist"
        }
        item.title = popupTemplate.title:format(data.name)
        item.desc = popupTemplate.description:format(extraData.level)
        item.img = popupTemplate.img:format(data.icon)
    end
end

local function shouldSkipRecentClientEvent(key)
    if not key then
        return false
    end

    notificationsController.recentClientEvents = notificationsController.recentClientEvents or {}
    if notificationsController.recentClientEvents[key] then
        return true
    end

    notificationsController.recentClientEvents[key] = true
    scheduleEvent(function()
        if notificationsController and notificationsController.recentClientEvents then
            notificationsController.recentClientEvents[key] = nil
        end
    end, 3000)
    return false
end

function showOutOfSoulPointsBanner()
    if shouldSkipRecentClientEvent("simple:out-of-soul") then
        return
    end
    notificationsController:onClientEvent(eventCategory.CLIENT_EVENT_TYPE_SIMPLE, eventType.CLIENT_EVENT_OUTOFSOULPOINTS)
end

function showOutOfAmmoBanner()
    if shouldSkipRecentClientEvent("simple:out-of-ammo") then
        return
    end
    notificationsController:onClientEvent(eventCategory.CLIENT_EVENT_TYPE_SIMPLE, eventType.CLIENT_EVENT_OUTOFAMMO)
end

function showAchievementBanner(name)
    name = name or "an achievement"
    if shouldSkipRecentClientEvent("achievement:" .. name) then
        return
    end
    notificationsController:onClientEvent(eventCategory.CLIENT_EVENT_TYPE_ACHIEVEMENT, name)
end

function showBestiaryBanner(raceId, progressText, raceOutfit)
    progressText = progressText or "Bestiary progress"
    local key = string.format("bestiary:%s:%s", tostring(raceId or 0), tostring(progressText))
    if shouldSkipRecentClientEvent(key) then
        return
    end
    if raceOutfit and raceId then
        protoData = protoData or {}
        protoData[raceId] = raceOutfit
    end
    notificationsController:onClientEvent(eventCategory.CLIENT_EVENT_TYPE_BESTIARY, raceId or 0, progressText, raceOutfit)
end

function notificationsController:onClientEvent(eventCat, ...)
    if not modules.client_options.getOption("showInfoBanner") then
        g_logger.debug("The server has sent infobaner, but the checkbox in client_options is disabled..")
        return
    end
    local args = {...}
    -- Prevent duplicate advance notifications when identical events arrive
    -- in quick succession (e.g., both LocalPlayer and g_game emitting the same).
    local advanceKey = getAdvanceKey(eventCat, ...)
    if advanceKey then
        notificationsController.recentAdvanceEvents = notificationsController.recentAdvanceEvents or {}
        if notificationsController.recentAdvanceEvents[advanceKey] then
            return
        end
        notificationsController.recentAdvanceEvents[advanceKey] = true
        scheduleEvent(function()
            if notificationsController and notificationsController.recentAdvanceEvents then
                notificationsController.recentAdvanceEvents[advanceKey] = nil
            end
        end, 3000)
    end
    local popupTemplate = nil
    if eventCat == eventCategory.CLIENT_EVENT_TYPE_SIMPLE then
        local eventType = args[1]
        popupTemplate = infoPopUp[eventCat] and infoPopUp[eventCat][eventType]

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_QUEST then
        local isCompleted = args[2] == 1 or args[2] == true
        popupTemplate = infoPopUp[eventCat] and infoPopUp[eventCat][isCompleted]

    elseif infoPopUp[eventCat] and infoPopUp[eventCat][1] then
        popupTemplate = infoPopUp[eventCat][1]
    end

    if not popupTemplate then
        return
    end

    local title = popupTemplate.title
    local description = popupTemplate.description
    local img = popupTemplate.img

    local extraData = {}

    if eventCat == eventCategory.CLIENT_EVENT_TYPE_QUEST then
        local questName = args[1]
        title = type(title) == 'string' and title:format(questName) or title
        description = type(description) == 'string' and description:format(questName) or description

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_PROFICIENCY then
        local itemId = args[1]
        local message = args[2]
        description = type(description) == 'string' and description:format(message) or description
        if popupTemplate.hasItemId then
            extraData.itemId = itemId
        end

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_LEVEL then
        local level = args[1]
        extraData.level = level
        extraData.advanceType = "level"
        extraData.advanceKey = advanceKey
        title = nil
        description = nil
        img = nil

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_SKILL then
        local skillId = args[1]
        local level = args[2]
        extraData.skillId = skillId
        extraData.level = level
        extraData.advanceType = "skill"
        extraData.advanceKey = advanceKey
        title = nil
        description = nil
        img = nil

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_COSMETIC then
        local lookType = args[1]
        local skinName = args[2]
        local skinType = tonumber(args[3])
        if skinType == 1 then
            skinName = skinName .. " (Addon 1)"
        elseif skinType == 2 then
            skinName = skinName .. " (Addon 2)"
        end
        description = type(description) == 'string' and description:format(skinName) or description
        if popupTemplate.hasCreatureId then
            extraData.creatureId = lookType
            extraData.skinType = skinType
        end
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_BESTIARY or eventCat == eventCategory.CLIENT_EVENT_TYPE_BOSSTIARY then
        local raceId = args[1]
        local progressLevel = tostring(args[2] or '')
        local raceOutfit = args[3]
        
        if progressLevel:find("^[Yy]ou have") or progressLevel:find("^[Yy]ou ") then
            description = progressLevel
        elseif progressLevel:find("completed", 1, true) then
            description = string.format("You have completed '%s'", progressLevel:gsub("^the completed ", "the "))
        elseif progressLevel:find("the Bestiary entry", 1, true) and not progressLevel:find("stage", 1, true) then
            description = string.format("You have unlocked '%s'", progressLevel)
        else
            description = string.format("You have progressed '%s'", progressLevel)
        end

        if popupTemplate.hasRaceId then
            extraData.raceId = raceId
            extraData.outfit = raceOutfit or (protoData and raceId and protoData[raceId])
        end

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_ACHIEVEMENT then
        local name = args[1]
        description = type(description) == 'string' and description:format(name) or description

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_TITLE then
        local name = args[1]
        description = type(description) == 'string' and description:format(name) or description
    end

    self:show(title, description, img, DEFAULT_HOLD_MS, extraData)
end

function infoBanner_onTerminate()
    notificationsController:hideImmediate()
    if notificationsController.ui and not notificationsController.ui:isDestroyed() then
        notificationsController.ui:destroy()
        notificationsController.ui = nil
    end
end

function notificationsController:ensure()
    if self.ui and not self.ui:isDestroyed() then
        return
    end

    local mapPanel = modules.game_interface.getMapPanel()
    self.ui = g_ui.loadUI("/game_notifications/templates/infobanner", mapPanel)
    if not self.ui then
        return
    end
    self.ui:hide()

    self.widgets = {
        paper = self.ui:getChildById("paper"),
        anim = self.ui:getChildById("animation"),
        content = self.ui:getChildById("content"),
        icon = self.ui:recursiveGetChildById("icon"),
        icon2 = self.ui:recursiveGetChildById("icon2"),
        icon3 = self.ui:recursiveGetChildById("icon3"),
        title = self.ui:recursiveGetChildById("title"),
        desc = self.ui:recursiveGetChildById("desc"),
        append = self.ui:recursiveGetChildById("append"),
    }
    self.widgets.fadeTexts = { self.widgets.title, self.widgets.desc }
    self.widgets.fadeIcons = { self.widgets.icon, self.widgets.icon2, self.widgets.icon3 }
end

function notificationsController:updateBannerPosition()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    -- Safely get the current stats bar widget and its height. Older code
    -- called a non-existent `StatsBar.getHeight()` function which can be nil.
    local statsBarHeight = 0
    local statsBar = modules.game_interface.StatsBar.getCurrentStatsBar()
    if statsBar and not statsBar:isDestroyed() and type(statsBar.getHeight) == 'function' then
        statsBarHeight = statsBar:getHeight()
    end

    local marginTop = statsBarHeight + BANNER_MARGIN_OFFSET
    self.ui:setMarginTop(marginTop)
    -- Banner margin-top set
end

function notificationsController:cancelEvent()
    if self.event then
        removeEvent(self.event)
        self.event = nil
    end
    if self.slideEvent then
        removeEvent(self.slideEvent)
        self.slideEvent = nil
    end
end

function notificationsController:reloadBannerUI()
    if self.ui and not self.ui:isDestroyed() then
        self.ui:destroy()
        self.ui = nil
        self.widgets = {}
    end
    self:ensure()
end

function notificationsController:show(title, desc, img, holdMs, extraData)
    self:ensure()
    -- Adding to queue -> title

    local item = {
        holdMs = holdMs or DEFAULT_HOLD_MS,
        extraData = extraData or {}
    }

    local advanceKey = item.extraData and item.extraData.advanceKey
    if not advanceKey then
        item.title = title
        item.desc = desc
        item.img = img
    end

    if advanceKey then
        if self.activeAdvanceKey == advanceKey then
            return
        end
        for i = 1, #self.queue do
            local q = self.queue[i]
            if q and q.extraData and q.extraData.advanceKey == advanceKey then
                return
            end
        end
        g_logger.debug(string.format("notifications: enqueue %s", advanceKey))
    end

    table.insert(self.queue, item)
    if self.state == "idle" then
        self:processNext()
    end
end

function notificationsController:setWidgetsOpacity(widgets, opacity)
    for _, widget in ipairs(widgets) do
        widget:setOpacity(opacity)
    end
end

function notificationsController:setContentOpacity(opacity)
    if self.widgets.fadeTexts then
        self:setWidgetsOpacity(self.widgets.fadeTexts, opacity)
    end
end

function notificationsController:setLeftIconsOpacity(opacity)
    if self.widgets.fadeIcons then
        self:setWidgetsOpacity(self.widgets.fadeIcons, opacity)
    end
end

function notificationsController:setPaperSize(width)
    local paper = self.widgets.paper
    paper:setWidth(width)
    paper:setImageRect({
        x = 0,
        y = 0,
        width = width,
        height = BANNER_HEIGHT
    })
end

function notificationsController:resetBanner()
    local w = self.ui
    -- Start off-screen to the left and invisible; slide+fade brings it to center.
    w:setOpacity(0)
    w:setMarginLeft(-SLIDE_OFFSET)
    w:show()
    self:setContentOpacity(0)
    self:setLeftIconsOpacity(0)
    self:setPaperSize(0)

    if self.widgets.append then
        self.widgets.append:destroyChildren()
    end

    if self.widgets.title then
        self.widgets.title:setText("")
    end
    if self.widgets.desc then
        self.widgets.desc:setText("")
    end

    local anim = self.widgets.anim
    anim:show()
    anim:setMarginLeft(0)
    anim:setImageSource(OPEN_FRAMES[1])
end

function notificationsController:processNext()
    self:cancelEvent()
    if #self.queue == 0 then
        -- Queue empty. Unloading UI.
        self.state = "idle"
        self.activeAdvanceKey = nil
        if self.ui and not self.ui:isDestroyed() then
            self.ui:destroy()
            self.ui = nil
            self.widgets = {}
        end
        return
    end
    local data = table.remove(self.queue, 1)
    if not data then
        self.state = "idle"
        self.activeAdvanceKey = nil
        if self.ui and not self.ui:isDestroyed() then
            self.ui:destroy()
            self.ui = nil
            self.widgets = {}
        end
        return
    end
    self:reloadBannerUI()
    self:updateBannerPosition()
    if not self.ui or self.ui:isDestroyed() then
        self.state = "idle"
        self.activeAdvanceKey = nil
        return
    end
    self.activeAdvanceKey = data.extraData and data.extraData.advanceKey or nil
    refreshAdvanceText(data)
    if self.activeAdvanceKey then
        g_logger.debug(string.format("notifications: show %s", self.activeAdvanceKey))
    end
    self:resetBanner()
    if data.img then
        self.widgets.icon:setImageSource(data.img)
    end
    self.widgets.title:setText("")
    self.widgets.desc:setText("")
    self.widgets.title:setText(data.title or "")
    self.widgets.desc:setText(data.desc or "")

    if data.extraData and self.widgets.append then
        local appendW = self.widgets.append
        appendW:destroyChildren()

        if data.extraData.itemId then
            local itemId = data.extraData.itemId
            local itemWidget = g_ui.createWidget('UIItem', appendW)
            itemWidget:setSize({width = 64, height = 64})
            itemWidget:setItemId(itemId)
        elseif data.extraData.raceId or data.extraData.outfit then
            local raceId = data.extraData.raceId
            local raceData = (raceId and raceId > 0) and g_things.getRaceData(raceId) or nil
            local outfitData = data.extraData.outfit or ((raceData and raceData.raceId ~= 0 and (raceData.outfit and raceData.outfit.type ~= 0)) and raceData.outfit) or (protoData and raceId and protoData[raceId])
            if outfitData and (outfitData.type and outfitData.type > 0) then
                local outfit = g_ui.createWidget('UICreature', appendW)
                outfit:setSize({width = 64, height = 64})
                outfit:setOutfit(outfitData)
                outfit:setAnimate(true)
                outfit:setCenter(true)
                outfit:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
                outfit:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            end
        elseif data.extraData.creatureId then
            local outfit = g_ui.createWidget('UICreature', appendW)
            outfit:setSize({width = 64, height = 64})
            if data.extraData.skinType == skinType.outfit then
                outfit:setOutfit({
                    type = data.extraData.creatureId
                })
            elseif data.extraData.skinType == skinType.addon1 or data.extraData.skinType == skinType.addon2 then
                outfit:setOutfit({
                    type = data.extraData.creatureId,
                    addons = data.extraData.skinType
                })
            elseif data.extraData.skinType == skinType.mount then
                outfit:setOutfit({
                    type = data.extraData.creatureId
                })
            end
        end
    end

    self.state = "opening"
    self:slideFadeIn()
    self:animateOpen(data.holdMs)
end

function notificationsController:slideFadeIn()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    if self.slideEvent then
        removeEvent(self.slideEvent)
        self.slideEvent = nil
    end

    local startTime = g_clock.millis()
    local startMargin = -SLIDE_OFFSET
    local function step()
        if not self.ui or self.ui:isDestroyed() then
            self.slideEvent = nil
            return
        end
        local t = easeOutQuad(math.min(1, (g_clock.millis() - startTime) / SLIDE_IN_MS))
        self.ui:setMarginLeft(math.floor(startMargin * (1 - t)))
        self.ui:setOpacity(t)
        if t < 1 then
            self.slideEvent = scheduleEvent(step, FADE_INTERVAL_MS)
        else
            self.ui:setMarginLeft(0)
            self.ui:setOpacity(1)
            self.slideEvent = nil
        end
    end
    self.slideEvent = scheduleEvent(step, FADE_INTERVAL_MS)
end

function notificationsController:slideFadeOut(onDone)
    if not self.ui or self.ui:isDestroyed() then
        if onDone then
            onDone()
        end
        return
    end
    if self.slideEvent then
        removeEvent(self.slideEvent)
        self.slideEvent = nil
    end

    local startTime = g_clock.millis()
    local startOpacity = self.ui:getOpacity() or 1
    local function step()
        if not self.ui or self.ui:isDestroyed() then
            self.slideEvent = nil
            if onDone then
                onDone()
            end
            return
        end
        local t = easeOutQuad(math.min(1, (g_clock.millis() - startTime) / SLIDE_OUT_MS))
        self.ui:setOpacity(startOpacity * (1 - t))
        self.ui:setMarginLeft(math.floor(-SLIDE_OFFSET * 0.55 * t))
        if t < 1 then
            self.slideEvent = scheduleEvent(step, FADE_INTERVAL_MS)
        else
            self.slideEvent = nil
            if onDone then
                onDone()
            end
        end
    end
    self.slideEvent = scheduleEvent(step, FADE_INTERVAL_MS)
end

function notificationsController:animateOpen(holdMs)
    local frame = 1
    local iconsShown = false
    local anim = self.widgets.anim
    local function animate()
        if not self.ui or self.ui:isDestroyed() then
            return
        end
        frame = frame + 1
        if frame > TOTAL_FRAMES then
            self:finishOpening(holdMs)
            return
        end
        local progress = (frame - 1) / (TOTAL_FRAMES - 1)
        local currentWidth = MAX_WIDTH * progress
        self:setPaperSize(currentWidth)
        anim:setMarginLeft(currentWidth - ANIM_OFFSET)
        anim:setImageSource(OPEN_FRAMES[frame])
        if not iconsShown and progress >= ICON_SHOW_PROGRESS then
            self:setLeftIconsOpacity(1)
            iconsShown = true
        end
        self.event = scheduleEvent(animate, FRAME_MS)
    end
    self.event = scheduleEvent(animate, FRAME_MS)
end

function notificationsController:finishOpening(holdMs)
    -- Opening finished. Holding.
    self:setPaperSize(MAX_WIDTH)
    self.widgets.anim:hide()
    -- Keep whatever slide-in reached; snap to center if already done.
    if not self.slideEvent then
        self.ui:setMarginLeft(0)
        self.ui:setOpacity(1)
    end
    self.state = "holding"
    self:fadeIn(holdMs)
end

function notificationsController:fadeIn(holdMs)
    local startTime = g_clock.millis()
    local function fadeInText()
        if not self.ui or self.ui:isDestroyed() then
            self:cancelEvent()
            self.state = "idle"
            return
        end
        local elapsed = g_clock.millis() - startTime
        local t = math.min(1, elapsed / FADE_IN_MS)
        self:setContentOpacity(t)
        if t < 1 then
            self.event = scheduleEvent(fadeInText, FADE_INTERVAL_MS)
        else
            self.event = scheduleEvent(function()
                self:close()
            end, holdMs)
        end
    end
    self.event = scheduleEvent(fadeInText, FADE_INTERVAL_MS)
end

function notificationsController:close()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    self:cancelEvent()
    self.state = "closing"
    -- Closing phase.
    self:fadeOut()
end

function notificationsController:fadeOut()
    local startTime = g_clock.millis()
    local function fadeOutText()
        if not self.ui or self.ui:isDestroyed() then
            self:cancelEvent()
            self.state = "idle"
            return
        end
        local elapsed = g_clock.millis() - startTime
        local t = math.min(1, elapsed / FADE_OUT_MS)
        self:setContentOpacity(1 - t)
        if t < 1 then
            self.event = scheduleEvent(fadeOutText, FADE_INTERVAL_MS)
        else
            self:animateClose()
        end
    end
    self.event = scheduleEvent(fadeOutText, FADE_INTERVAL_MS)
end

function notificationsController:animateClose()
    local frame = TOTAL_FRAMES
    local iconsHidden = false
    local anim = self.widgets.anim
    anim:show()
    local function retract()
        if not self.ui or self.ui:isDestroyed() then
            self:cancelEvent()
            self.state = "idle"
            return
        end
        frame = frame - 1
        if frame < 1 then
            -- Retract finished. Slide/fade out of the screen.
            self:setPaperSize(0)
            anim:setMarginLeft(0)
            anim:setImageSource(OPEN_FRAMES[1])
            self:slideFadeOut(function()
                self:exit()
            end)
            return
        end
        local progress = (frame - 1) / (TOTAL_FRAMES - 1)
        local currentWidth = MAX_WIDTH * progress
        self:setPaperSize(currentWidth)
        anim:setMarginLeft(currentWidth - ANIM_OFFSET)
        anim:setImageSource(OPEN_FRAMES[frame])
        if not iconsHidden and progress <= ICON_HIDE_PROGRESS then
            self:setLeftIconsOpacity(0)
            iconsHidden = true
        end
        self.event = scheduleEvent(retract, FRAME_MS)
    end
    self.event = scheduleEvent(retract, FRAME_MS)
end

function notificationsController:exit()
    if not self.ui or self.ui:isDestroyed() then
        self.state = "idle"
        self.activeAdvanceKey = nil
        self:processNext()
        return
    end
    self:cancelEvent()
    self.ui:hide()
    self.ui:setOpacity(1)
    self.ui:setMarginLeft(0)
    self.state = "idle"
    self.activeAdvanceKey = nil
    self:processNext()
end

function notificationsController:hideImmediate()
    self:cancelEvent()
    if self.ui and not self.ui:isDestroyed() then
        self.ui:destroy()
        self.ui = nil
        self.widgets = {}
    end
    self.queue = {}
    self.state = "idle"
    self.activeAdvanceKey = nil
    -- Reset Immediate and Unloaded.
end
