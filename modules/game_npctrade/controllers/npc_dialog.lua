local showHighlightedUnderline = false
local NPC_DIALOG_HEADER_COLOR = "white"

local function findCreatureByName(name)
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then return nil end
    local spectators = g_map.getSpectators(localPlayer:getPosition(), false) or {}
    for _, spec in ipairs(spectators) do
        if spec:getName():lower() == name:lower() then
            return spec
        end
    end
    return nil
end

local function findNearestNpc()
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then return nil end
    local spectators = g_map.getSpectators(localPlayer:getPosition(), false) or {}
    local nearestNpc = nil
    local minDistance = 9999
    local playerPos = localPlayer:getPosition()
    for _, spec in ipairs(spectators) do
        if spec:isNpc() and spec ~= localPlayer then
            local specPos = spec:getPosition()
            local dist = math.max(math.abs(playerPos.x - specPos.x), math.abs(playerPos.y - specPos.y))
            if dist < minDistance then
                minDistance = dist
                nearestNpc = spec
            end
        end
    end
    return nearestNpc
end

local function getHighlightedText(text, color, highlightColor)
    color = color or "white"
    highlightColor = highlightColor or "#1f9ffe"
    local firstBrace = text:find("{", 1, true)
    if not firstBrace then
        return string.format("{%s, %s}", text, color)
    end
    local parts = {}
    local lastPos = 1
    for startPos, content, endPos in text:gmatch("()%{([^}]*)%}()") do
        if startPos > lastPos then
            parts[#parts + 1] = string.format("{%s, %s}", text:sub(lastPos, startPos - 1), color)
        end
        local textPart = content:match("([^,]+)") or content
        local trimmed = textPart
        local highlighted = trimmed
        if showHighlightedUnderline then
            highlighted = string.format("[text-event]%s[/text-event]", trimmed)
        else
            highlighted = string.format("[text-event]%s%s[/text-event]", string.char(1), trimmed)
        end
        parts[#parts + 1] = string.format("{%s, %s}", highlighted, highlightColor)
        lastPos = endPos
    end
    if lastPos <= #text then
        parts[#parts + 1] = string.format("{%s, %s}", text:sub(lastPos), color)
    end
    return table.concat(parts)
end

local function createDialogLabel(consoleBuffer, entry)
    local label = g_ui.createWidget('ConsoleLabel', consoleBuffer)
    label:setId("consoleLabel" .. consoleBuffer:getChildCount())

    if entry.coloredData then
        label:setColoredText(entry.coloredData)
        label.coloredData = entry.coloredData
    else
        label:setText(entry.text or "")
    end

    if entry.color then
        label:setColor(entry.color)
    end

    if entry.name then
        label.name = entry.name
    end

    if entry.clickable and not label:hasEventListener(EVENT_TEXT_CLICK) then
        label:setEventListener(EVENT_TEXT_CLICK)
        connect(label, {
            onTextClick = function(w, t)
                controllerNpcTrader:onConsoleTextClicked(w, t)
            end
        })
    end

    return label
end

local function buildTalkingToEntry(npcName, timestamp)
    local prefix = timestamp and (timestamp .. " ") or ""
    return {
        text = prefix .. "Talking to " .. npcName .. ".",
        color = NPC_DIALOG_HEADER_COLOR
    }
end

function controllerNpcTrader:ensureDialogHeader(consoleBuffer)
    if not consoleBuffer or consoleBuffer:getChildCount() > 0 or not self.creatureName or self.creatureName == "" then
        return
    end

    createDialogLabel(consoleBuffer, buildTalkingToEntry(self.creatureName, os.date('%H:%M')))
end

function controllerNpcTrader:onConsoleTextClicked(widget, text)
    if type(widget) == "string" and not text then
        text = widget
        widget = nil
    end

    if not text or text == "" then
        return
    end

    local npcTab = modules.game_console.consoleTabBar:getTab("NPCs")
    if npcTab then
        modules.game_console.sendMessage(text, npcTab)
        onNpcTalk(g_game.getCharacterName(), 0, MessageModes.NpcTo, text)
    end
    if text == "bye" then
        controllerNpcTrader:onCloseNpcTrade()
    end
end

function controllerNpcTrader:closeWindow()
    local npcTab = modules.game_console and modules.game_console.consoleTabBar and modules.game_console.consoleTabBar:getTab("NPCs")
    if npcTab and g_game.isOnline() then
        self:onConsoleTextClicked(nil, "bye")
    else
        self:onCloseNpcTrade()
    end
end

function controllerNpcTrader:cloneConsoleMessages()
    local consoleBuffer = self:findWidget("#consoleBuffer")

    if consoleBuffer then
        consoleBuffer:destroyChildren()
        self:ensureDialogHeader(consoleBuffer)
    end
end

function controllerNpcTrader:appendDialogMessage(text, color)
    local consoleBuffer = self:findWidget("#consoleBuffer")
    if consoleBuffer then
        self:ensureDialogHeader(consoleBuffer)
        createDialogLabel(consoleBuffer, {
            text = text,
            color = color or '#ffaa00',
            clickable = false
        })
    end
end

-- temp fix. can't drag the left panel to move the window.
function controllerNpcTrader:setupWindowDragBehavior()
    if not self.ui then
        return
    end
    local dragHandle = self:findWidget("#dragHandle")
    if not dragHandle then
        return
    end
    dragHandle:setDraggable(true)
    dragHandle.onDragEnter = function(widget, mousePos)
        return self.ui:onDragEnter(mousePos)
    end
    dragHandle.onDragMove = function(widget, mousePos, mouseMoved)
        self.ui:onDragMove(mousePos, mouseMoved)
        return true
    end
    dragHandle.onDragLeave = function(widget, droppedWidget, mousePos)
        self.ui:onDragLeave(droppedWidget, mousePos)
        return true
    end
end

function controllerNpcTrader:checkNpcDistance()
    if self:isLegacyMode() then return end
    
    local player = g_game.getLocalPlayer()
    if not player then return end

    if not self.npcCreature and self.creatureName and self.creatureName ~= "" and self.creatureName ~= "Unknown" then
        self.npcCreature = findCreatureByName(self.creatureName)
    end
    if not self.npcCreature then
        self.npcCreature = findNearestNpc()
    end

    if self.npcCreature then
        local playerPos = player:getPosition()
        local npcPos = self.npcCreature:getPosition()
        if playerPos and npcPos then
            if playerPos.z ~= npcPos.z or math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y)) > 4 then
                self:onCloseNpcTrade()
            end
        else
            self:onCloseNpcTrade()
        end
    else
        self:onCloseNpcTrade()
    end
end

function controllerNpcTrader:initNpcWindow(creature, buttons)
    if self:isLegacyMode() then
        return
    end
    self:connectNpcTalkEvent()
    self.widthConsole = self.DEFAULT_CONSOLE_WIDTH
    self.isTradeOpen = false
    if creature then
        self.creatureName = creature:getName() or "Unknown"
        self.outfit = creature:getOutfit()
        self.npcCreature = creature
    else
        local foundCreature = findNearestNpc()
        if not foundCreature and self.lastNpcName then
            foundCreature = findCreatureByName(self.lastNpcName)
        end

        if foundCreature then
            self.creatureName = foundCreature:getName()
            self.outfit = foundCreature:getOutfit()
            self.npcCreature = foundCreature
        else
            self.creatureName = self.lastNpcName or "Unknown"
            self.outfit = "/game_npctrade/assets/images/icon-npcdialog-multiplenpcs"
            self.npcCreature = nil
        end
    end

    if not self.positionChangeConnected then
        self.onPlayerPositionChange = function(p, newPos, oldPos)
            self:checkNpcDistance()
        end
        connect(LocalPlayer, { onPositionChange = self.onPlayerPositionChange })
        self.positionChangeConnected = true
    end

    if buttons and #buttons > 0 then
        self.buttons = buttons
    elseif not self.buttons or #self.buttons == 0 then
        self.buttons = self.buttonsDefault
    end
    self:updateChatButton()
    if not self.ui or not self.ui:isVisible() then
        self:loadHtml('templates/game_npctrader.html')
    end
    if self.ui then
        self.ui.onFocusChange = function(widget, focused)
            local opacity = focused and 1.0 or 0.6
            widget:setOpacity(opacity)
            for _, child in ipairs(widget:recursiveGetChildren()) do
                child:setOpacity(opacity)
            end
        end
        local opacity = self.ui:isFocused() and 1.0 or 0.6
        self.ui:setOpacity(opacity)
        for _, child in ipairs(self.ui:recursiveGetChildren()) do
            child:setOpacity(opacity)
        end
    end
    self:setupWindowDragBehavior()

    local npcNameLabel = self:findWidget("#npcNameLabel")
    if npcNameLabel then
        npcNameLabel:setText(self.creatureName)
    end

    local creatureOutfit = self:findWidget("#creatureOutfit")
    if creatureOutfit then
        if type(self.outfit) == "string" then
            creatureOutfit:setImageSource(self.outfit)
        else
            creatureOutfit:setOutfit(self.outfit)
        end
    end
    self:cloneConsoleMessages()
end

function onNpcChatWindow(data)
    if controllerNpcTrader:isLegacyMode() then
        controllerNpcTrader:legacy_show()
        return
    end
    if type(data) ~= "table" or type(data.npcIds) ~= "table" or #data.npcIds == 0 then
        return
    end
    -- The server appends every greeting NPC to the list and builds the buttons from the
    -- LAST id (the active conversation); npcIds[1] is the oldest, e.g. a bystander that
    -- happened to be in talk range. Showing npcIds[1] paints the wrong name and outfit.
    local creature = g_map.getCreatureById(data.npcIds[#data.npcIds])
    if creature then
        controllerNpcTrader:initNpcWindow(creature, data.buttons)
    end
end

function controllerNpcTrader:onConsoleKeyPress(event)
    if event.value == KeyEnter then
        local input = controllerNpcTrader:findWidget(".inputConsole")
        if input then
            local text = input:getText()
            if text and #text > 0 then
                controllerNpcTrader:onConsoleTextClicked(nil, text)
                input:clearText()
            end
        end
    end
end

function onNpcTalk(name, level, mode, text, channelId, creaturePos)
    if not controllerNpcTrader.ui or not controllerNpcTrader.ui:isVisible() then
        return
    end

    if mode == MessageModes.NpcTo or mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
        local consoleBuffer = controllerNpcTrader:findWidget("#consoleBuffer")
        if consoleBuffer then
            controllerNpcTrader:ensureDialogHeader(consoleBuffer)
            local consoleModule = modules.game_console
            local SpeakTypes = consoleModule and consoleModule.SpeakTypes or {}
            local color = '#5FF7F7'
            if SpeakTypes[mode] and SpeakTypes[mode].color then
                color = SpeakTypes[mode].color
            end
            local fullText = text
            if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
                fullText = name .. " says: " .. text
            elseif mode == MessageModes.NpcTo then
                fullText = name .. ": " .. text
            end
            local entry = {
                text = fullText,
                color = color,
                name = mode == MessageModes.NpcTo and g_game.getCharacterName() or name,
                clickable = true
            }
            if getHighlightedText then
                entry.coloredData = getHighlightedText(fullText, color, "#1f9ffe")
            end
            createDialogLabel(consoleBuffer, entry)
        end

        -- Auto-detect NPC type from dialogue
        if (mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock) then
            local lowerText = text:lower()
            local lowerName = name and name:lower() or ""
            
            if not controllerNpcTrader.isBankerDetected and not controllerNpcTrader.isTravelDetected and not controllerNpcTrader.isMerchantDetected then
                local isTravel = false
                if lowerName:find("captain", 1, true) then
                    isTravel = true
                else
                    for _, keyword in ipairs(controllerNpcTrader.TRAVEL_KEYWORDS) do
                        if lowerText:find(keyword, 1, true) then
                            isTravel = true
                            break
                        end
                    end
                end

                if isTravel then
                    controllerNpcTrader.isTravelDetected = true
                    controllerNpcTrader.buttons = controllerNpcTrader.buttonsTravel
                else
                    local isBanker = false
                    for _, keyword in ipairs(controllerNpcTrader.BANK_KEYWORDS) do
                        if lowerText:find(keyword, 1, true) then
                            isBanker = true
                            break
                        end
                    end

                    if isBanker then
                        controllerNpcTrader.isBankerDetected = true
                        controllerNpcTrader.buttons = controllerNpcTrader.buttonsBanker
                    else
                        for _, keyword in ipairs(controllerNpcTrader.TRADE_KEYWORDS) do
                            if lowerText:find(keyword, 1, true) then
                                controllerNpcTrader.isMerchantDetected = true
                                controllerNpcTrader.buttons = controllerNpcTrader.buttonsMerchant
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

function controllerNpcTrader:updateChatButton()
    local isChatEnabled = modules.game_console.isChatEnabled()
    self.chatMode = isChatEnabled and tr('Chat On') or tr('Chat Off')
    local inputConsole = self:findWidget(".inputConsole")
    if inputConsole then
        inputConsole:setEnabled(isChatEnabled)
    end
end

function controllerNpcTrader:toggleChatMode()
    modules.game_console.toggleChat()
    self:updateChatButton()
end
