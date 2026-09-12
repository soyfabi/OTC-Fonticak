local bottomMenu
local calendarWindow
local activeScheduleEvent
local upcomingScheduleEvent
local eventSchedulerYears
local calendarCurrentMonth
local calendarPrevButton
local calendarNextButton
local calendarCurrentDate
local showOffWindow

local eventSchedulerTimestamp
local eventSchedulerCalendar
local eventSchedulerCalendarYearIndex
local eventSchedulerCalendarMonth

local boostedWindow
local creaturePanel
local bossPanel
local creatureHitArea
local bossHitArea
local monsterOutfit
local monsterImage
local bossOutfit
local bossImage
local pendingBoostedData
local BOOSTED_WALK_SPEED = 1000

local default_info = {
    -- hint 1
    {
        image = "images/randomhint",
        Title = "Enabling Boosted Creature Panel",
        description = "Boosted creatures panel requires configuring a webservice (init.lua) and preloading a client version by either setting one server in Servers_init (init.lua) or by altering entergame.lua.\n\nFor more hints, visit:\t\t https://github.com/mehah/otclient/wiki"
    },

    -- hint 2
    -- {image = "image of label", Title = "title", description = "your hint here"},
}

function init()
    g_ui.importStyle('calendar')
    bottomMenu = g_ui.displayUI('bottommenu')

    calendarWindow = g_ui.createWidget('CalendarGrid', rootWidget)
    calendarCurrentMonth = calendarWindow:recursiveGetChildById('calendarCurrentMonth')
    calendarCurrentDate = calendarWindow:recursiveGetChildById('calendarCurrentDate')
    calendarPrevButton = calendarWindow:recursiveGetChildById('calendarPrevButton')
    calendarNextButton = calendarWindow:recursiveGetChildById('calendarNextButton')
    calendarWindow:hide()

    showOffWindow = bottomMenu:recursiveGetChildById('showOffWindow')
    showOffWindow.title = showOffWindow:recursiveGetChildById('showOffWindowText')
    activeScheduleEvent = bottomMenu:recursiveGetChildById('activeScheduleEvent')
    upcomingScheduleEvent = bottomMenu:recursiveGetChildById('upcomingScheduleEvent')
    upcomingScheduleEvent:recursiveGetChildById('fill'):setOn(false)
    eventSchedulerCalendarYearIndex = 1
    eventSchedulerCalendarMonth = tonumber(os.date("%m"))

    boostedWindow = bottomMenu:recursiveGetChildById('boostedWindow')
    creaturePanel = boostedWindow:recursiveGetChildById('creaturePanel')
    bossPanel = boostedWindow:recursiveGetChildById('bossPanel')
    creatureHitArea = boostedWindow:recursiveGetChildById('creatureHitArea')
    bossHitArea = boostedWindow:recursiveGetChildById('bossHitArea')
    monsterOutfit = boostedWindow:recursiveGetChildById('creature')
    bossOutfit = boostedWindow:recursiveGetChildById('boss')

    monsterImage = boostedWindow:recursiveGetChildById('monsterImage')
    bossImage = boostedWindow:recursiveGetChildById('bossImage')

    local hasBoostedSource = hasBoostedCreatureSource()
    if not hasBoostedSource and default_info then
        local scrollable = showOffWindow:recursiveGetChildById('contentsPanel')
        local widget = g_ui.createWidget('ShowOffWidget', scrollable)
        local description = widget:recursiveGetChildById('description')
        local image = widget:recursiveGetChildById('image')

        math.randomseed(os.time())
        local randomIndex = math.random(1, #default_info)
        local randomItem = default_info[randomIndex]
        showOffWindow.title:setText(tr(randomItem.Title))
        image:setImageSource(randomItem.image)
        description:setText(tr(randomItem.description))
        monsterOutfit:setVisible(false)
        bossOutfit:setVisible(false)
        widget:resize(widget:getWidth(), description:getHeight())

        monsterImage:setImageSource("images/icon-questionmark")
        monsterImage:setVisible(true)
        bossImage:setImageSource("images/icon-questionmark")
        bossImage:setVisible(true)
    elseif monsterImage and bossImage then
        monsterImage:setVisible(false)
        bossImage:setVisible(false)
    end
    if g_game.isOnline() then
        hide()
    end
end

function terminate()
    bottomMenu:destroy()
    calendarWindow:destroy()
end

function hide()
    bottomMenu:hide()
    bottomMenu:lower()

    if not calendarWindow:isHidden() then
        onClickCloseCalendar()
    end
end

function show()
    bottomMenu:show()
    bottomMenu:raise()
    bottomMenu:focus()
end

-- @ Store showoff
function setShowOffData(data)
    local widget = g_ui.createWidget('ShowOffWidget', showOffWindow)
    local image = widget:recursiveGetChildById('image')

    if data.image and data.image:sub(1, 4):lower() == "http" then
        HTTP.downloadImage(data.image, function(path, err)
            if err then
                g_logger.warning("HTTP error: " .. err .. " - " .. data.image)
                return
            end
            image:setImageSource(path)
        end)
    else
        image:setImage(data.image)
    end

    local description = widget:recursiveGetChildById('description')

    showOffWindow.title:setText(tr(data.title))
    description:setText(tr(data.description))
end

-- @ Calendar/Events scheduler
function onClickOnCalendar()
    if eventSchedulerYears == nil or #eventSchedulerYears == 0 then
        return
    end

    calendarWindow:show()
    calendarWindow:raise()
    calendarWindow:centerIn('parent')
    calendarWindow:removeAnchor(AnchorHorizontalCenter)
    calendarWindow:removeAnchor(AnchorVerticalCenter)
    reloadEventsSchedulerCurrentPage()

    g_keyboard.bindKeyPress('Escape', onClickCloseCalendar)
end

function onClickCloseCalendar()
    calendarWindow:hide()
    calendarWindow:lower()

    g_keyboard.unbindKeyPress('Escape', onClickCloseCalendar)
end

function setEventsSchedulerTimestamp(time)
    eventSchedulerTimestamp = time
    calendarCurrentDate:setText(os.date("%Y-%m-%d, %H:%M CET", eventSchedulerTimestamp))
end

function getCalendarEventWidgetByDay(day, month, year, weekOffset, forceLine)
    local weekIndex = getDayOfWeek(day, month, year)
    local row = calendarWindow:recursiveGetChildById('row' .. weekIndex)
    if not row then
        return nil
    end

    local lineIndex = nil
    if forceLine ~= nil then
        lineIndex = forceLine
    else
        lineIndex = (math.floor(((weekOffset + day) - 1) / 7))
    end
    local line = row:recursiveGetChildById('line' .. lineIndex)
    if not line then
        return nil
    end

    return line
end

function reloadEventsSchedulerCurrentPage()
    local firstDayOffset = getDayOfWeek(1)
    if firstDayOffset == 0 then
        firstDayOffset = 7
    end
    local weekOffset = firstDayOffset - 1

    -- Days before the day 1 of this month
    if weekOffset > 0 then
        local previousYearIndex = eventSchedulerCalendarYearIndex
        local previousMonth = eventSchedulerCalendarMonth
        if previousMonth == 1 then
            previousYearIndex = previousYearIndex - 1
            previousMonth = 12
        else
            previousMonth = previousMonth - 1
        end
        if previousYearIndex >= 0 then
            local previousDays = eventSchedulerYears[previousYearIndex][previousMonth]
            local amountsLeft = weekOffset
            local i = #previousDays
            while (amountsLeft > 0) do
                local widget = getCalendarEventWidgetByDay(i, previousMonth, tonumber(os.date("%Y", os.time())) +
                    (previousYearIndex - 1), weekOffset, 0)
                if widget then
                    widget:clearEvents()
                    widget.dayOfTheWeek = i
                    widget:recursiveGetChildById('dayAndSeason'):setOn(true)
                    widget:recursiveGetChildById('day'):setText(i)
                    widget:recursiveGetChildById('day'):setWidth(string.len(
                        widget:recursiveGetChildById('day'):getText()) * 10)
                    widget:recursiveGetChildById('fill'):setOn(false)
                    for _, event in ipairs(previousDays[i]) do
                        widget:addScheduleEvent(event, false, nil)
                    end
                end
                amountsLeft = amountsLeft - 1
                i = i - 1
            end
        end
    end

    -- Days after the last day of this month
    local days = eventSchedulerYears[eventSchedulerCalendarYearIndex][eventSchedulerCalendarMonth]
    local lastDayOffset = getDayOfWeek(#days)
    if lastDayOffset == 0 then
        lastDayOffset = 7
    end
    local nextWeekOffset = 7 - lastDayOffset
    local nextYearIndex = eventSchedulerCalendarYearIndex
    local nextMonth = eventSchedulerCalendarMonth
    if nextMonth == 12 then
        nextYearIndex = nextYearIndex + 1
        nextMonth = 1
    else
        nextMonth = nextMonth + 1
    end
    if nextYearIndex <= 2 then
        local nextDays = eventSchedulerYears[nextYearIndex][nextMonth]
        local amountsLeft = nextWeekOffset
        local i = 1
        local forceLine = 4
        if firstDayOffset >= 5 then
            forceLine = 5
        end
        if firstDayOffset <= 5 then
            amountsLeft = amountsLeft + 7
        end
        while (amountsLeft > 0) do
            if forceLine == 4 and amountsLeft == 7 then
                forceLine = 5
            end
            local widget = getCalendarEventWidgetByDay(i, nextMonth,
                tonumber(os.date("%Y", os.time())) + (nextYearIndex - 1), nextWeekOffset, forceLine)
            if widget then
                widget:clearEvents()
                widget.dayOfTheWeek = i
                widget:recursiveGetChildById('dayAndSeason'):setOn(true)
                widget:recursiveGetChildById('day'):setText(i)
                widget:recursiveGetChildById('day'):setWidth(
                    string.len(widget:recursiveGetChildById('day'):getText()) * 10)
                widget:recursiveGetChildById('fill'):setOn(false)
                for _, event in ipairs(nextDays[i]) do
                    widget:addScheduleEvent(event, false, nil)
                end
            end
            amountsLeft = amountsLeft - 1
            i = i + 1
        end
    end

    for day, events in ipairs(days) do
        local widget = getCalendarEventWidgetByDay(day, nil, nil, weekOffset, nil)
        if widget then
            widget:clearEvents()
            widget.dayOfTheWeek = day
            widget:recursiveGetChildById('dayAndSeason'):setOn(true)
            widget:recursiveGetChildById('day'):setText(tr(day))
            widget:recursiveGetChildById('day'):setWidth(string.len(widget:recursiveGetChildById('day'):getText()) * 10)
            widget:recursiveGetChildById('fill'):setOn(true)
            for _, event in ipairs(events) do
                widget:addScheduleEvent(event, true, nil)
            end
        end
    end

    calendarCurrentMonth:setText(os.date("%B", os.time {
        year = 2023,
        month = eventSchedulerCalendarMonth,
        day = 1
    }) .. " " .. (tonumber(os.date("%Y", os.time())) + (eventSchedulerCalendarYearIndex - 1)))
end

function reloadEventsSchedulerCalender()
    eventSchedulerYears = {}
    table.insert(eventSchedulerYears, createCalendar(tonumber(os.date("%Y", os.time()))))
    table.insert(eventSchedulerYears, createCalendar(tonumber(os.date("%Y", os.time())) + 1))

    if eventSchedulerCalendar == nil or #eventSchedulerCalendar == 0 then
        return
    end

    for _, info in ipairs(eventSchedulerCalendar) do
        local days = getCalendarDays(info.startdate, info.enddate)
        for index, day in ipairs(days) do
            table.insert(day, {
                active = (info.colorlight .. "ff"),
                inactive = (info.colordark .. "ff"),
                description = info.description,
                priority = info.displaypriority,
                season = info.isseasonal,
                name = info.name,
                special = info.specialevent,
                firstDay = index == 1,
                lastDay = index == #days
            })
        end
    end

    activeScheduleEvent:clearEvents()
    local currentDay = getCalendarDays(os.time(), os.time())
    if #currentDay > 0 then
        for _, event in ipairs(currentDay[1]) do
            activeScheduleEvent:addScheduleEvent(event, true, onClickOnCalendar)
        end
    end

    upcomingScheduleEvent:clearEvents()
    local nextDay = getCalendarDays(os.time() + 86400, os.time() + 86400)
    if #nextDay > 0 then
        for _, event in ipairs(nextDay[1]) do
            upcomingScheduleEvent:addScheduleEvent(event, false, onClickOnCalendar)
        end
    end
end

function setEventsSchedulerCalender(calender)
    eventSchedulerCalendar = calender
    reloadEventsSchedulerCalender()
end

function createCalendar(year)
    local calendar = {}

    for month = 1, 12 do
        calendar[month] = {}
        local daysInMonth = 31
        if month == 2 then
            if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
                daysInMonth = 29
            else
                daysInMonth = 28
            end
        elseif month == 4 or month == 6 or month == 9 or month == 11 then
            daysInMonth = 30
        end

        for day = 1, daysInMonth do
            calendar[month][day] = {}
        end
    end

    return calendar
end

function getCalendarDays(startTimestamp, endTimestamp)
    local currentYear = tonumber(os.date("%Y", os.time()))
    local startYear = tonumber(os.date("%Y", startTimestamp))
    local endYear = tonumber(os.date("%Y", endTimestamp))
    local daysInRange = {}

    if startYear ~= currentYear and startYear ~= (currentYear + 1) then
        return daysInRange
    end

    if endYear ~= currentYear and endYear ~= (currentYear + 1) then
        return daysInRange
    end

    local startMonth = tonumber(os.date("%m", startTimestamp))
    local startDay = tonumber(os.date("%d", startTimestamp))
    local endMonth = tonumber(os.date("%m", endTimestamp))
    local endDay = tonumber(os.date("%d", endTimestamp))

    if startYear == currentYear then
        for month = startMonth, endMonth do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[1][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[1][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[1][month][day])
                    end
                end
            end
        end
    else
        for month = startMonth, 12 do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[1][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[1][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[1][month][day])
                    end
                end
            end
        end
        for month = 1, endMonth do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[2][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[2][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[2][month][day])
                    end
                end
            end
        end
    end

    return daysInRange
end

function getDayOfWeek(day, month, year)
    if not year then
        year = tonumber(os.date("%Y", os.time())) + (eventSchedulerCalendarYearIndex - 1)
    end
    if not month then
        month = eventSchedulerCalendarMonth
    end
    local timestamp = os.time {
        year = year,
        month = month,
        day = day
    }
    local weekday = tonumber(os.date("%w", timestamp))
    -- 0: Sunday
    -- 6: Saturday
    return weekday
end

function onClickOnPreviousCalendar()
    if eventSchedulerCalendarMonth == 1 then
        if eventSchedulerCalendarYearIndex == 1 then
            return
        end
        eventSchedulerCalendarMonth = 12
        eventSchedulerCalendarYearIndex = eventSchedulerCalendarYearIndex - 1
    else
        eventSchedulerCalendarMonth = eventSchedulerCalendarMonth - 1
    end

    calendarNextButton:setEnabled(true)
    if eventSchedulerCalendarYearIndex == 1 and eventSchedulerCalendarMonth == (tonumber(os.date("%m", os.time())) - 1) then
        calendarPrevButton:setEnabled(false)
    else
        calendarPrevButton:setEnabled(true)
    end

    reloadEventsSchedulerCurrentPage()
end

function onClickOnNextCalendar()
    if eventSchedulerCalendarMonth == 12 then
        if eventSchedulerCalendarYearIndex == 2 then
            return
        end
        eventSchedulerCalendarMonth = 1
        eventSchedulerCalendarYearIndex = eventSchedulerCalendarYearIndex + 1
    else
        eventSchedulerCalendarMonth = eventSchedulerCalendarMonth + 1
    end

    calendarPrevButton:setEnabled(true)
    if eventSchedulerCalendarYearIndex == 2 and eventSchedulerCalendarMonth == (tonumber(os.date("%m", os.time())) - 1) then
        calendarNextButton:setEnabled(false)
    else
        calendarNextButton:setEnabled(true)
    end

    reloadEventsSchedulerCurrentPage()
end

function hasBoostedCreatureSource()
    if Services and Services.status and Services.status ~= '' then
        return true
    end

    if not BoostedCreatures then
        return false
    end

    return (BoostedCreatures.creatureraceid or BoostedCreatures.raceid or BoostedCreatures.creatureLookType or BoostedCreatures.creaturelooktype)
        or (BoostedCreatures.bossraceid or BoostedCreatures.bossLookType or BoostedCreatures.bosslooktype)
end

local function normalizeBoostedData(data)
    if not data then
        return nil
    end

    local creature = data.creature
    local boss = data.boss

    return {
        creatureRaceId = data.creatureraceid or data.raceid or (creature and (creature.raceId or creature.raceid)),
        bossRaceId = data.bossraceid or (boss and (boss.raceId or boss.raceid)),
        creatureLookType = data.creaturelooktype or data.creatureLookType or (creature and creature.type),
        bossLookType = data.bosslooktype or data.bossLookType or (boss and boss.type),
        creatureOutfit = creature and creature.outfit,
        bossOutfit = boss and boss.outfit,
    }
end

local function resolveBoostedOutfit(raceId, lookType)
    if raceId and raceId > 0 then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.raceId ~= 0 and raceData.outfit and raceData.outfit.type and raceData.outfit.type > 0 then
            return raceData.outfit
        end
    end

    if lookType and lookType > 0 then
        return { type = lookType }
    end

    return nil
end

local function clearBoostedTooltip(panel)
    if not panel then
        return
    end

    if panel.removeTooltip then
        panel:removeTooltip()
    else
        panel:setTooltip('')
    end
end

local function resolveBoostedName(entry, raceId, lookType)
    if entry and entry.name and entry.name ~= '' then
        return entry.name
    end

    if raceId and raceId > 0 then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.name and raceData.name ~= '' then
            return raceData.name
        end
    end

    return nil
end

local function applyBoostedTooltip(hitArea, titleLine, bodyLine)
    if not hitArea then
        return
    end

    if titleLine and bodyLine and titleLine ~= '' and bodyLine ~= '' then
        hitArea:setSpecialToolTip({
            { header = titleLine, info = bodyLine }
        })
        hitArea:setTooltipDelay(0)
    else
        clearBoostedTooltip(hitArea)
    end
end

local function setBoostedCreatureTooltip(name)
    if name and name ~= '' then
        applyBoostedTooltip(
            creatureHitArea,
            tr("Today's boosted creature: %s", name),
            tr('Boosted creatures yield more experience points, carry more loot than usual and respawn at a faster rate.')
        )
    else
        applyBoostedTooltip(creatureHitArea, nil, nil)
    end
end

local function setBoostedBossTooltip(name)
    if name and name ~= '' then
        applyBoostedTooltip(
            bossHitArea,
            tr("Today's boosted boss: %s", name),
            tr('Boosted boss contain more loot and count more kills for your bosstiary.')
        )
    else
        applyBoostedTooltip(bossHitArea, nil, nil)
    end
end

local function updateBoostedTooltips(data)
    if not data then
        setBoostedCreatureTooltip(nil)
        setBoostedBossTooltip(nil)
        return
    end

    local creature = data.creature
    local boss = data.boss
    local normalized = normalizeBoostedData(data)

    setBoostedCreatureTooltip(resolveBoostedName(creature, normalized and normalized.creatureRaceId, normalized and normalized.creatureLookType))
    setBoostedBossTooltip(resolveBoostedName(boss, normalized and normalized.bossRaceId, normalized and normalized.bossLookType))
end

local function startBoostedAnimation(outfitWidget)
    local creature = outfitWidget and outfitWidget.getCreature and outfitWidget:getCreature()
    if not creature then
        return
    end

    creature:setAnimate(true)
    creature:setStaticWalking(BOOSTED_WALK_SPEED)
end

-- (internal) set creature/boss to boosted slot
local function applyToBoostedSlot(raceId, lookType, outfitData, outfitWidget, imageWidget, label)
    if not outfitWidget or not imageWidget then
        return false
    end

    local outfit = outfitData
    if not outfit or not outfit.type or outfit.type <= 0 then
        outfit = resolveBoostedOutfit(raceId, lookType)
    end
    if not outfit then
        if raceId or lookType then
            g_logger.warning(string.format('[bottommenu] Boosted %s not found (raceId=%s, lookType=%s).',
                label or 'creature', tostring(raceId), tostring(lookType)))
        end
        return false
    end

    outfitWidget:setOutfit(outfit)
    outfitWidget:setVisible(true)
    imageWidget:setVisible(false)
    startBoostedAnimation(outfitWidget)

    local hitArea = outfitWidget == monsterOutfit and creatureHitArea or (outfitWidget == bossOutfit and bossHitArea or nil)
    if hitArea and hitArea.raise then
        hitArea:raise()
    end

    return true
end

local function tryApplyBoostedData(data)
    if not data or not monsterOutfit or not bossOutfit then
        return false
    end

    if not modules.game_things or not modules.game_things.isLoaded or not modules.game_things.isLoaded() then
        return false
    end

    local normalized = normalizeBoostedData(data)
    if not normalized then
        return false
    end

    applyToBoostedSlot(normalized.creatureRaceId, normalized.creatureLookType, normalized.creatureOutfit, monsterOutfit, monsterImage, 'creature')
    applyToBoostedSlot(normalized.bossRaceId, normalized.bossLookType, normalized.bossOutfit, bossOutfit, bossImage, 'boss')
    return true
end

function onThingsLoaded()
    if pendingBoostedData then
        tryApplyBoostedData(pendingBoostedData)
    end
end

function setBoostedCreatureAndBoss(data)
    pendingBoostedData = data
    updateBoostedTooltips(data)
    if not tryApplyBoostedData(data) then
        scheduleEvent(function()
            tryApplyBoostedData(pendingBoostedData)
        end, 250)
    end
end

function applyConfiguredBoostedCreatures()
    if BoostedCreatures then
        setBoostedCreatureAndBoss(BoostedCreatures)
    end
end
