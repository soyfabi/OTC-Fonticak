blessingWindow = nil
historyWindow = nil

local blessSheet = "/images/game/blessings/blessings-icons"
local ICON_SIZE = 64
local blessingIcons = {
    ["4"] = 3,
    ["2"] = 8,
    ["256"] = 7,
    ["128"] = 6,
    ["64"] = 1,
    ["32"] = 4,
    ["16"] = 2,
    ["8"] = 5
}

local function isAlive(widget)
    return widget and not widget:isDestroyed()
end

local function showModal(widget)
    if g_modalManager then
        g_modalManager.show(widget)
    end
end

local function hideModal(widget)
    if g_modalManager then
        g_modalManager.hide(widget)
    end
end

local function destroyWindows()
    if isAlive(blessingWindow) then
        hideModal(blessingWindow)

        pcall(function()
            blessingWindow:ungrabKeyboard()
        end)
        blessingWindow:destroy()
    end

    blessingWindow = nil

    if isAlive(historyWindow) then
        hideModal(historyWindow)

        pcall(function()
            historyWindow:ungrabKeyboard()
        end)
        historyWindow:destroy()
    end

    historyWindow = nil
end

local function ensureWindows()
    g_ui.importStyle("style.otui")

    if not isAlive(blessingWindow) then
        blessingWindow = g_ui.displayUI("blessing")
        blessingWindow:hide()
    end

    if not isAlive(historyWindow) then
        historyWindow = g_ui.displayUI("history")
        historyWindow:hide()
    end
end

local function getBlessingsPanel()
    ensureWindows()

    local mini = blessingWindow:recursiveGetChildById("miniWindowBlessing")
    return mini and mini:getChildById("blessings")
end

local function getPromotionLabel()
    ensureWindows()

    local mini = blessingWindow:recursiveGetChildById("miniWindowPromotion")
    return mini and mini:getChildById("label")
end

local function getInfoLabel(id)
    ensureWindows()

    local mini = blessingWindow:recursiveGetChildById("miniWindowInfo")
    return mini and mini:getChildById(id)
end

local function getHistoryList()
    ensureWindows()

    local mini = historyWindow:recursiveGetChildById("miniWindowBlessing")
    return mini and mini:getChildById("historyList")
end

local function updateHistoryList(logs)
    local historyList = getHistoryList()
    if not historyList then
        return
    end

    historyList:destroyChildren()

    local headerRow = g_ui.createWidget("historyData", historyList)
    headerRow:setBackgroundColor("#363636")
    headerRow:setBorderColor("#00000077")
    headerRow:setBorderWidth(1)
    headerRow.rank:setText("Date")
    headerRow.name:setText("Event")
    headerRow.rank:setColor("#c0c0c0")
    headerRow.name:setColor("#c0c0c0")

    for index, entry in ipairs(logs or {}) do
        local row = g_ui.createWidget("historyData", historyList)
        local date = os.date("%Y-%m-%d, %H:%M:%S", entry.timestamp)
        row:setBackgroundColor(index % 2 == 0 and "#ffffff12" or "#00000012")
        row.rank:setText(date)
        row.name:setText(entry.historyMessage)
    end
end

function init()
    ensureWindows()
    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onUpdateBlessDialog = onBlessingDialog,
        onBlessingsChange = onBlessingsChange
    })
end

function toggle()
    ensureWindows()

    if blessingWindow:isVisible() then
        closeBlessing()
    else
        showBlessingModal()
    end

    if modules.game_inventory and modules.game_inventory.refreshBlessingsIcon then
        modules.game_inventory.refreshBlessingsIcon()
    end
end

local function syncModalPosition(from, to)
    to:breakAnchors()
    to:setPosition({
        x = from:getX(),
        y = from:getY()
    })
end

function history()
    ensureWindows()

    if blessingWindow:isVisible() then
        hideModal(blessingWindow)
        blessingWindow:hide()
        syncModalPosition(blessingWindow, historyWindow)
        historyWindow:show()
        showModal(historyWindow)
    else
        hideModal(historyWindow)
        historyWindow:hide()
        syncModalPosition(historyWindow, blessingWindow)
        blessingWindow:show()
        showModal(blessingWindow)
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onUpdateBlessDialog = onBlessingDialog,
        onBlessingsChange = onBlessingsChange
    })
    destroyWindows()
end

function showBlessingModal()
    g_game.requestBless()
end

function closeBlessing()
    if not isAlive(blessingWindow) then
        return
    end

    hideModal(blessingWindow)
    blessingWindow:hide()

    if isAlive(historyWindow) and historyWindow:isVisible() then
        hideModal(historyWindow)
        historyWindow:hide()
    end
end

function openStoreFromBlessings()
    closeBlessing()

    if modules.game_store and modules.game_store.openCategory then
        modules.game_store.openCategory("Blessings")
    elseif modules.game_store and modules.game_store.toggle then
        modules.game_store.toggle()
    end
end

function closeBlessHistory()
    if not isAlive(historyWindow) then
        return
    end

    hideModal(historyWindow)
    historyWindow:hide()
end

function online()
    destroyWindows()
    ensureWindows()
end

function offline()
    if isAlive(blessingWindow) then
        hideModal(blessingWindow)
        blessingWindow:hide()
    end

    if isAlive(historyWindow) then
        hideModal(historyWindow)
        historyWindow:hide()
    end

    destroyWindows()
end

local function updateBlessLayout(total)
    local panel = getBlessingsPanel()
    if not panel then
        return
    end

    local cols = total == 8 and 8 or 7
    local width = cols * 66 + (cols - 1) * 5
    panel:setWidth(width)
end

function onBlessingDialog(data)
    ensureWindows()

    local blessingsPanel = getBlessingsPanel()
    if not blessingsPanel then
        return
    end

    blessingWindow:show(true)
    blessingWindow:raise()
    blessingWindow:focus()
    showModal(blessingWindow)
    blessingsPanel:destroyChildren()

    for _, bless in ipairs(data.blesses or {}) do
        local widget = g_ui.createWidget("BlessingWidget", blessingsPanel)
        local index = blessingIcons[tostring(bless.blessBitwise)]

        if index then
            widget.containerImage.image:setImageSource(blessSheet)
            widget.containerImage.image:setImageClip(string.format("%d 0 %d %d", index * ICON_SIZE, ICON_SIZE, ICON_SIZE))
        end

        widget.containerCount:setText(string.format("%d (%d)", bless.playerBlessCount, bless.store))

        if bless.playerBlessCount < 1 then
            widget.containerCount:setVisible(false)
            widget.storeButton:setVisible(true)
        end
    end

    local promotionLabel = getPromotionLabel()
    if promotionLabel then
        promotionLabel:parseColoredText("\nYour character is promoted and your account has Premium\nstatus. As a result, your XP loss is reduced by [color=#f75f5f]" .. (data.promotion or 0) .. "%[/color]", "#c0c0c0")
    end

    local bullet = string.char(149)
    local nbsp = string.char(160)

    local pvpDeath = getInfoLabel("pvpDeath")
    if pvpDeath then
        pvpDeath:parseColoredText(bullet .. " Depending on the fair fight rules, you will lose between [color=#f75f5f]" .. (data.pvpMinXpLoss or 0) .. "[/color] and [color=#f75f5f]" .. (data.pvpMaxXpLoss or 0) .. "%[/color] less XP and skill\n" .. nbsp .. nbsp .. nbsp .. "points upon your next PvP death.", "#c0c0c0")
    end

    local pveDeath = getInfoLabel("pveDeath")
    if pveDeath then
        pveDeath:parseColoredText(bullet .. " You will lose [color=#f75f5f]" .. (data.pveExpLoss or 0) .. "%[/color] less XP and skill points upon your next PvE death.", "#c0c0c0")
    end

    local pvpDrop = getInfoLabel("pvpDrop")
    if pvpDrop then
        pvpDrop:parseColoredText(bullet .. " There is a [color=#f75f5f]" .. (data.equipPvpLoss or 0) .. "%[/color] chance that you will lose your equipped container on your next\n" .. nbsp .. nbsp .. nbsp .. "death.", "#c0c0c0")
    end

    local pveDrop = getInfoLabel("pveDrop")
    if pveDrop then
        pveDrop:parseColoredText(bullet .. " There is a [color=#f75f5f]" .. (data.equipPveLoss or 0) .. "%[/color] chance that you will lose items upon your next death.", "#c0c0c0")
    end

    updateBlessLayout(data.totalBless or #(data.blesses or {}))
    updateHistoryList(data.logs)

    if modules.game_inventory and modules.game_inventory.refreshBlessingsIcon then
        modules.game_inventory.refreshBlessingsIcon()
    end
end

function onBlessingsChange(blessings, blessVisualState)
    if modules.game_inventory and modules.game_inventory.onBlessingsChange then
        modules.game_inventory.onBlessingsChange(blessings, blessVisualState)
    end
end
