local updateNpcTradePlayerBalanceLabel -- forward declaration (used before its declaration in the decompiled file)
local onCloseNpcTrade

mainNpcModal = nil
local BuyNpcTradeItems = {}
local SellNpcTradeItems = {}
local playerItems = {}
local npcOutfit = nil
local multiNpc = nil
local npcNameLabel = nil

local sayButtonsActive = {}
local NPC_MODAL_MIN_W = 307
local NPC_MODAL_MIN_H = 332
local NPC_MODAL_MAX_W = 837
local NPC_MODAL_MAX_H = 653
local NPC_MODAL_DEFAULT_W = 439
local NPC_MODAL_DEFAULT_H = 424
local MINIBORDER_RESIZE_CURSOR = "diagonal-nw"
local npcModalResizeState
local NPC_MODAL_DRAG_MOVE_OPACITY = 0.8
local NPC_MODAL_TRADE_EXTRA_W = 204
local npcModalTrade = false
local LOOT_POUCH_ITEM_ID = 23721
local GOLD_COIN_ITEM_ID = 3031
local npcTradeCurrencyId, menuButton, sep1, label1, currencyName, item, buyButton, sellButton, itemsSelling, searchEdit, clearSearch, countScrollBar, label3, label4, label5, labelPrice, playerBalance, userInput, item2, BuySellButton
local itemsPanel, readOnlyPanel, itemsPanelScrollBar, npcTradeItemsPanel, search2Edit, search3Edit
local npcTradePlayerMoney = 0
local npcTradeFilterText = ""
local NPC_MODAL_SETTINGS_FILE = "/settings/npc_modal.json"
local sortByName = true
local sortByPrice = false
local sortByWeight = false
local buyInShoppingBags = false
local ignoreCapacity = false
local sellEquipped = false
local showSearchField = true
local doNotShowWarningLargeAmounts = true
local npcTradeSelectedEntry, npcTradeLookThing
local npcTradeCurrentUnitPrice = 0
local npcTradeQuantity = 0
local sellAllModal, sellAllButton
local stopSellAllAutoRefresh = function() end
local scheduleSellAllAutoRefresh = function() end

local lootPouchItems = {}
local sellAllIgnoredItems = {}

local FilterText2 = ""
local FilterText3 = ""
local npcModalClosedAt = 0

local defaultNpcButtons = {
	{ text = "yes", id = 7 },
	{ text = "no", id = 8 },
	{ text = "bye", id = 9 },
	{ text = "trade", id = 0 }
}

local function findCreatureByName(name)
	local localPlayer = g_game.getLocalPlayer()
	if not localPlayer or not name or name == "" then return nil end
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

local activeNpcCreature = nil
local currentNpcIds = {}

local function findNearbyNpcs(maxDist)
	maxDist = maxDist or 3
	local localPlayer = g_game.getLocalPlayer()
	if not localPlayer then return {} end
	local spectators = g_map.getSpectators(localPlayer:getPosition(), false) or {}
	local npcs = {}
	local playerPos = localPlayer:getPosition()
	for _, spec in ipairs(spectators) do
		if spec:isNpc() and spec ~= localPlayer then
			local specPos = spec:getPosition()
			if specPos.z == playerPos.z then
				local dist = math.max(math.abs(playerPos.x - specPos.x), math.abs(playerPos.y - specPos.y))
				if dist <= maxDist then
					table.insert(npcs, { creature = spec, dist = dist })
				end
			end
		end
	end
	table.sort(npcs, function(a, b) return a.dist < b.dist end)
	local result = {}
	for _, item in ipairs(npcs) do
		table.insert(result, item.creature)
	end
	return result
end

local function addNpcToModal(creature)
	if not creature or not mainNpcModal then return end
	local creatureId = creature:getId()
	if not currentNpcIds then currentNpcIds = {} end
	for _, id in ipairs(currentNpcIds) do
		if id == creatureId then
			return
		end
	end
	table.insert(currentNpcIds, creatureId)

	local npcNames = ""
	local npcCount = 0
	for i = 1, #currentNpcIds do
		local c = g_map.getCreatureById(currentNpcIds[i])
		if c then
			npcCount = npcCount + 1
			if npcNames == "" then
				npcNames = c:getName()
			else
				npcNames = npcNames .. " and " .. c:getName()
			end
		end
	end

	if npcCount > 1 then
		if multiNpc then
			multiNpc:show()
		end
		if npcOutfit then
			npcOutfit:hide()
		end
	elseif npcCount == 1 then
		if multiNpc then
			multiNpc:hide()
		end
		if npcOutfit then
			npcOutfit:setOutfit(creature:getOutfit())
			npcOutfit:show()
		end
	end

	if npcNameLabel then
		npcNameLabel:setText(npcNames)
		npcNameLabel:show()
	end
end

local function npcIconClip(index, row)
	row = row or 0
	return string.format("%d %d %d %d", index * 35, row * 35, 35, 35)
end

local imageClips = {
	[0] = {
		normal = npcIconClip(0, 0),
		pressed = npcIconClip(0, 1)
	},
	{
		normal = npcIconClip(1, 0),
		pressed = npcIconClip(1, 1)
	},
	{
		normal = npcIconClip(2, 0),
		pressed = npcIconClip(2, 1)
	},
	{
		normal = npcIconClip(3, 0),
		pressed = npcIconClip(3, 1)
	},
	{
		normal = npcIconClip(4, 0),
		pressed = npcIconClip(4, 1)
	},
	{
		normal = npcIconClip(5, 0),
		pressed = npcIconClip(5, 1)
	},
	{
		normal = npcIconClip(6, 0),
		pressed = npcIconClip(6, 1)
	},
	{
		normal = npcIconClip(7, 0),
		pressed = npcIconClip(7, 1)
	},
	{
		normal = npcIconClip(8, 0),
		pressed = npcIconClip(8, 1)
	},
	{
		normal = npcIconClip(9, 0),
		pressed = npcIconClip(9, 1)
	}
}

local function getButtonIconId(button)
	if not button then
		return 0
	end

	if button.id and button.id >= 0 and button.id <= 9 then
		return button.id
	end

	local text = button.text and button.text:lower() or ""
	if text == "yes" then
		return 7
	elseif text == "no" then
		return 8
	elseif text == "bye" or text == "farewell" then
		return 9
	elseif text == "sail" or text == "passage" or text == "travel" then
		return 3
	elseif text == "deposit" or text == "deposit all" then
		return 4
	elseif text == "withdraw" then
		return 5
	elseif text == "balance" then
		return 6
	elseif text == "potion" or text == "potions" or text == "runes" or text == "magic" then
		return 1
	elseif text == "equipment" or text == "armors" or text == "weapons" then
		return 2
	elseif text == "trade" or text == "offers" or text == "wares" then
		return 0
	end

	return 0
end

local function detectNpcButtons(npcName, text, creature)
	local lowerName = tostring(npcName or ""):lower()
	local lowerText = tostring(text or ""):lower()

	if not creature and activeNpcCreature then
		creature = activeNpcCreature
	end
	if not creature and lowerName ~= "" then
		creature = findCreatureByName(npcName)
	end
	if creature then
		local cName = creature:getName():lower()
		if lowerName == "" then
			lowerName = cName
		end
	end

	-- 1. Travel / Sail / Passage
	local isTravel = false
	if lowerName:find("captain", 1, true) or lowerName:find("sailor", 1, true) or lowerName:find("boat", 1, true)
	   or lowerName:find("ferry", 1, true) or lowerName:find("navigator", 1, true)
	   or lowerName == "charon" or lowerName == "buddel" or lowerName == "pemaret"
	   or lowerName == "dalbrect" or lowerName == "chemar" or lowerName == "fenech"
	   or lowerName == "lorek" or lowerName == "nielson" or lowerName == "tibra"
	   or lowerName == "charles" or lowerName == "brodrosch" or lowerName == "harbour master" then
		isTravel = true
	end

	if lowerText:find("sail", 1, true) or lowerText:find("passage", 1, true)
	   or lowerText:find("travel", 1, true) or lowerText:find("board", 1, true)
	   or lowerText:find("destination", 1, true) or lowerText:find("trip", 1, true)
	   or lowerText:find("ferry", 1, true) or lowerText:find("ship", 1, true)
	   or lowerText:find("boat", 1, true) or lowerText:find("carpet", 1, true) then
		isTravel = true
	end

	if isTravel then
		return {
			{ text = "yes", id = 7 },
			{ text = "no", id = 8 },
			{ text = "bye", id = 9 },
			{ text = "sail", id = 3 }
		}
	end

	-- 2. Bank / Banker
	local isBank = false
	if lowerName:find("bank", 1, true) or lowerName == "eva" or lowerName == "jaffar"
	   or lowerName == "suzy" or lowerName == "zetholf" or lowerName == "serafin"
	   or lowerName == "finarfin" or lowerName == "chephan" or lowerName == "aruda" then
		isBank = true
	end

	if lowerText:find("bank", 1, true) or (lowerText:find("deposit", 1, true) and lowerText:find("withdraw", 1, true))
	   or lowerText:find("balance", 1, true) or lowerText:find("account", 1, true) then
		isBank = true
	end

	if isBank then
		return {
			{ text = "yes", id = 7 },
			{ text = "no", id = 8 },
			{ text = "bye", id = 9 },
			{ text = "balance", id = 6 },
			{ text = "deposit all", id = 4 },
			{ text = "withdraw", id = 5 }
		}
	end

	-- 3. Trade categories
	local isPotion = false
	local isEquipment = false

	if lowerText:find("potion", 1, true) or lowerText:find("rune", 1, true)
	   or lowerText:find("magic", 1, true) or lowerText:find("fluid", 1, true)
	   or lowerText:find("wand", 1, true) or lowerText:find("rod", 1, true)
	   or lowerName:find("magic", 1, true) or lowerName:find("alchemist", 1, true)
	   or lowerName:find("sorcerer", 1, true) or lowerName:find("druid", 1, true) then
		isPotion = true
	end

	if lowerText:find("armor", 1, true) or lowerText:find("armour", 1, true)
	   or lowerText:find("weapon", 1, true) or lowerText:find("shield", 1, true)
	   or lowerText:find("helmet", 1, true) or lowerText:find("sword", 1, true)
	   or lowerText:find("axe", 1, true) or lowerText:find("club", 1, true)
	   or lowerText:find("bow", 1, true) or lowerText:find("crossbow", 1, true)
	   or lowerText:find("legs", 1, true) or lowerText:find("boots", 1, true)
	   or lowerName:find("smith", 1, true) or lowerName:find("armorer", 1, true) then
		isEquipment = true
	end

	if isPotion then
		return {
			{ text = "yes", id = 7 },
			{ text = "no", id = 8 },
			{ text = "bye", id = 9 },
			{ text = "trade", id = 1 }
		}
	elseif isEquipment then
		return {
			{ text = "yes", id = 7 },
			{ text = "no", id = 8 },
			{ text = "bye", id = 9 },
			{ text = "trade", id = 2 }
		}
	end

	-- 4. Default / General merchant trade
	return {
		{ text = "yes", id = 7 },
		{ text = "no", id = 8 },
		{ text = "bye", id = 9 },
		{ text = "trade", id = 0 }
	}
end

local currentModalButtonsKey = ""

local function getButtonsKey(buttons)
	if not buttons then return "" end
	local parts = {}
	for _, b in ipairs(buttons) do
		table.insert(parts, string.format("%s:%s", tostring(b.text), tostring(b.id)))
	end
	return table.concat(parts, "|")
end

local function updateNpcModalButtons(buttons)
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	if not buttons or #buttons == 0 then
		buttons = defaultNpcButtons
	end

	local key = getButtonsKey(buttons)
	if key == currentModalButtonsKey and #sayButtonsActive == #buttons then
		return
	end
	currentModalButtonsKey = key

	for _, w in pairs(sayButtonsActive) do
		if w and not w:isDestroyed() then
			w:destroy()
		end
	end

	sayButtonsActive = {}

	for i = 1, #buttons do
		local button = buttons[i]
		local sayButton = g_ui.createWidget("SayButton", mainNpcModal)

		sayButton:setTooltip(button.text)

		local iconId = getButtonIconId(button)
		local clip = imageClips[iconId] or imageClips[0]

		if clip then
			sayButton:setImageClip(clip.normal)
		else
			sayButton:setImageClip(imageClips[0].normal)
		end

		sayButton:setMarginLeft(40 * (i - 1))

		function sayButton.onMousePress()
			if g_tooltip then
				g_tooltip.hide(true)
			end
			local curIconId = getButtonIconId(button)
			local curClip = imageClips[curIconId] or imageClips[0]

			if curClip and curClip.pressed then
				sayButton:setImageClip(curClip.pressed)
			end
		end

		function sayButton.onMouseRelease()
			if g_tooltip then
				g_tooltip.hide(true)
			end
			local curIconId = getButtonIconId(button)
			local curClip = imageClips[curIconId] or imageClips[0]

			if curClip and curClip.normal then
				sayButton:setImageClip(curClip.normal)

				if modules.game_console and modules.game_console.sendNpcModalReply then
					modules.game_console.sendNpcModalReply(button.text)
				end

				if button.text and (button.text:lower() == "bye" or button.text:lower() == "farewell") then
					closeNpcModal()
				end
			end
		end

		table.insert(sayButtonsActive, sayButton)
	end
end

local function isAnyNpcModalVisible()
	return (mainNpcModal and mainNpcModal:isVisible()) or (sellAllModal and sellAllModal:isVisible())
end

local function checkNpcDistance()
	if not isAnyNpcModalVisible() then
		return
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local playerPos = player:getPosition()
	if not playerPos then
		return
	end

	local currentNpc = activeNpcCreature or findNearestNpc()
	if currentNpc then
		local npcPos = currentNpc:getPosition()
		if npcPos then
			if playerPos.z ~= npcPos.z or math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y)) > 4 then
				closeNpcModal()
			end
			return
		end
	end
end

local currentNpcId = nil

local function formatNpcHighlightedText(text, color, highlightColor)
	color = color or "#5ff7f7"
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
		local trimmed = textPart:match("^%s*(.-)%s*$")
		local highlighted = string.format("[text-event]%s%s[/text-event]", string.char(1), trimmed)
		parts[#parts + 1] = string.format("{%s, %s}", highlighted, highlightColor)
		lastPos = endPos
	end

	if lastPos <= #text then
		parts[#parts + 1] = string.format("{%s, %s}", text:sub(lastPos), color)
	end

	return table.concat(parts)
end

local measureLabel = nil

local function getMeasureLabel(font)
	if not measureLabel or measureLabel:isDestroyed() then
		measureLabel = g_ui.createWidget("UILabel", g_ui.getRootWidget())
		measureLabel:setVisible(false)
	end
	measureLabel:setFont(font or "verdana-11px-antialised")
	return measureLabel
end

local function measureTextWidth(str, font)
	local ml = getMeasureLabel(font)
	local clean = str:gsub("%{([^}]*)%}", "%1")
	ml:setText(clean)
	return ml:getTextSize().width
end

local function tokenizeDialogText(str)
	local tokens = {}
	local i = 1
	local len = #str

	while i <= len do
		local sStart, sEnd = str:find("^%s+", i)
		if sStart then
			i = sEnd + 1
		end

		if i <= len then
			if str:sub(i, i) == "{" then
				local closePos = str:find("}", i, true)
				if closePos then
					local endPos = closePos
					while endPos + 1 <= len and not str:sub(endPos + 1, endPos + 1):match("%s") do
						endPos = endPos + 1
					end
					table.insert(tokens, str:sub(i, endPos))
					i = endPos + 1
				else
					local nextSpace = str:find("%s", i) or (len + 1)
					table.insert(tokens, str:sub(i, nextSpace - 1))
					i = nextSpace
				end
			else
				local nextSpace = str:find("%s", i) or (len + 1)
				table.insert(tokens, str:sub(i, nextSpace - 1))
				i = nextSpace
			end
		end
	end

	return tokens
end

local function wrapDialogLineWithHangingIndent(prefix, text, maxWidth, indentSpaces, font)
	indentSpaces = indentSpaces or "  "
	maxWidth = maxWidth or 300

	if text:find("\n", 1, true) then
		local resultLines = {}
		local segments = string.split(text, "\n")
		for idx, segment in ipairs(segments) do
			local p = (idx == 1) and prefix or indentSpaces
			table.insert(resultLines, wrapDialogLineWithHangingIndent(p, segment, maxWidth, indentSpaces, font))
		end
		return table.concat(resultLines, "\n")
	end

	local tokens = tokenizeDialogText(text or "")
	if #tokens == 0 then
		return prefix
	end

	local lines = {}
	local currentLine = prefix .. tokens[1]

	for t = 2, #tokens do
		local token = tokens[t]
		local candidate = currentLine .. " " .. token
		if measureTextWidth(candidate, font) <= maxWidth then
			currentLine = candidate
		else
			table.insert(lines, currentLine)
			currentLine = indentSpaces .. token
		end
	end
	table.insert(lines, currentLine)

	return table.concat(lines, "\n")
end

local function getNpcModalItemsPanelWidth()
	if itemsPanel and not itemsPanel:isDestroyed() and itemsPanel:getWidth() > 80 then
		return itemsPanel:getWidth() - 10
	end

	if readOnlyPanel and not readOnlyPanel:isDestroyed() and readOnlyPanel:getWidth() > 100 then
		return readOnlyPanel:getWidth() - 26
	end

	if mainNpcModal and mainNpcModal:getWidth() > 150 then
		local extra = (npcModalTrade and 220 or 16)
		return mainNpcModal:getWidth() - extra - 38
	end

	return 320
end

local function rewrapNpcModalDialogLines()
	if not itemsPanel or itemsPanel:isDestroyed() then return end
	local maxWidth = getNpcModalItemsPanelWidth()
	for _, child in ipairs(itemsPanel:getChildren()) do
		if child._rawPrefix and child._rawText then
			local fullText = wrapDialogLineWithHangingIndent(child._rawPrefix, child._rawText, maxWidth, "  ", child:getFont())
			local coloredData = formatNpcHighlightedText(fullText, child._color, child._highlightColor)
			child:setColoredText(coloredData)
			child.coloredData = coloredData
		end
	end
end

local function clearItemsPanelSelection(panel)
	if not panel then return end
	for _, child in ipairs(panel:getChildren()) do
		if child.clearSelection then
			child:clearSelection()
		end
	end
	panel.selectionText = nil
	panel.selection = nil
end

local function selectAllItemsPanel(panel)
	if not panel then return end
	clearItemsPanelSelection(panel)
	local text = {}
	local children = panel:getChildren()
	if #children > 0 then
		for _, child in ipairs(children) do
			if child.selectAll and child.getSelection then
				child:selectAll()
				table.insert(text, child:getSelection())
			end
		end
		panel.selectionText = table.concat(text, "\n")
		panel.selection = {
			first = 1,
			last = #children
		}
	end
end

local function setupNpcModalLabelSelection(label, itemsPanel)
	label.onMousePress = function(self, mousePos, button)
		if button == MouseLeftButton then
			clearItemsPanelSelection(itemsPanel)
		end
	end

	label.onDragEnter = function(self, mousePos)
		clearItemsPanelSelection(itemsPanel)
		return true
	end

	label.onDragLeave = function(self, droppedWidget, mousePos)
		if itemsPanel.selection then
			local text = {}
			for i = itemsPanel.selection.first, itemsPanel.selection.last do
				local child = itemsPanel:getChildByIndex(i)
				if child and child.getSelection then
					table.insert(text, child:getSelection())
				end
			end
			itemsPanel.selectionText = table.concat(text, "\n")
		end
		return true
	end

	label.onDragMove = function(self, mousePos, mouseMoved)
		local parent = self:getParent()
		if not parent then return false end
		local parentRect = parent:getPaddingRect()
		local selfIndex = parent:getChildIndex(self)
		local child = parent:getChildByPos(mousePos)

		if not child then
			if mousePos.y < self:getY() then
				for index = selfIndex - 1, 1, -1 do
					local l = parent:getChildByIndex(index)
					if l:getY() + l:getHeight() > parentRect.y then
						if (mousePos.y >= l:getY() and mousePos.y <= l:getY() + l:getHeight()) or index == 1 then
							child = l
							break
						end
					else
						child = parent:getChildByIndex(index + 1)
						break
					end
				end
			elseif mousePos.y > self:getY() + self:getHeight() then
				for index = selfIndex + 1, parent:getChildCount(), 1 do
					local l = parent:getChildByIndex(index)
					if l:getY() < parentRect.y + parentRect.height then
						if (mousePos.y >= l:getY() and mousePos.y <= l:getY() + l:getHeight()) or index == parent:getChildCount() then
							child = l
							break
						end
					else
						child = parent:getChildByIndex(index - 1)
						break
					end
				end
			else
				child = self
			end
		end

		if not child then return false end

		local childIndex = parent:getChildIndex(child)
		clearItemsPanelSelection(parent)

		local textBegin = self:getTextPos(self:getLastClickPosition())
		local textPos = self:getTextPos(mousePos)
		self:setSelection(textBegin, textPos)

		parent.selection = {
			first = math.min(selfIndex, childIndex),
			last = math.max(selfIndex, childIndex)
		}

		if child ~= self then
			for selIdx = parent.selection.first + 1, parent.selection.last - 1 do
				local l = parent:getChildByIndex(selIdx)
				if l and l.selectAll then
					l:selectAll()
				end
			end

			local pos = child:getTextPos(mousePos)
			if childIndex > selfIndex then
				child:setSelection(0, pos)
			else
				child:setSelection(string.len(child:getText()), pos)
			end
		end

		local text = {}
		for selIdx = parent.selection.first, parent.selection.last do
			local l = parent:getChildByIndex(selIdx)
			if l and l.getSelection then
				table.insert(text, l:getSelection())
			end
		end
		parent.selectionText = table.concat(text, "\n")
		return true
	end

	label.onDoubleClick = function(self, mousePos)
		clearItemsPanelSelection(itemsPanel)
		self:selectAll()
		itemsPanel.selection = {
			first = itemsPanel:getChildIndex(self),
			last = itemsPanel:getChildIndex(self)
		}
		itemsPanel.selectionText = self:getSelection()
		return true
	end

	label.onMouseRelease = function(self, mousePos, mouseButton)
		if mouseButton == MouseRightButton then
			local menu = g_ui.createWidget("PopupMenu")
			menu:setGameMenu(true)

			local selection = itemsPanel and itemsPanel.selectionText
			if selection and #selection > 0 then
				menu:addOption(tr("Copy"), function()
					g_window.setClipboardText(selection)
				end, "(Ctrl+C)")
			end

			local fullMsg = self:getText()
			if fullMsg and #fullMsg > 0 then
				menu:addOption(tr("Copy message"), function()
					g_window.setClipboardText(fullMsg)
				end)
			end

			menu:addOption(tr("Select all"), function()
				selectAllItemsPanel(itemsPanel)
			end)

			menu:display(mousePos)
			return true
		end
	end
end

local lastDialogLine = { fullCheck = "", time = 0 }
local currentTalkingToNpc = ""

function addNpcDialogHeader(npcName)
	if not mainNpcModal then
		return
	end
	if not npcName or npcName == "" then
		return
	end

	if currentTalkingToNpc == npcName:lower() then
		return
	end
	currentTalkingToNpc = npcName:lower()

	if not itemsPanel then
		return
	end

	local label = g_ui.createWidget("ConsoleLabel", itemsPanel)
	label:setId("npcModalHeader" .. itemsPanel:getChildCount())
	label:setFocusable(false)

	local showTimestamps = true
	if modules.client_options and modules.client_options.getOption then
		showTimestamps = modules.client_options.getOption("showTimestampsInConsole")
		if showTimestamps == nil then
			showTimestamps = true
		end
	end

	local timeStr = showTimestamps and (os.date("%H:%M:%S") .. " ") or ""
	local headerText = string.format("%sTalking to %s", timeStr, npcName)

	label:setText(headerText)
	label:setColor("#FFFFFF")

	setupNpcModalLabelSelection(label, itemsPanel)

	local scrollBar = itemsPanelScrollBar
	if scrollBar then
		addEvent(function()
			if scrollBar and not scrollBar:isDestroyed() then
				scrollBar:setValue(scrollBar:getMaximum())
			end
		end)
	end
end

function addNpcDialogLine(name, text, isPlayer)
	if not mainNpcModal then
		return
	end

	local now = os.clock()
	local speaker = name or (isPlayer and g_game.getCharacterName()) or ""
	local fullCheck = speaker .. ":" .. (text or "")
	if lastDialogLine.fullCheck == fullCheck and (now - lastDialogLine.time) < 0.5 then
		return
	end
	lastDialogLine.fullCheck = fullCheck
	lastDialogLine.time = now

	if not isPlayer and speaker and speaker ~= "" and currentTalkingToNpc ~= speaker:lower() then
		addNpcDialogHeader(speaker)
	end

	if not itemsPanel then
		return
	end

	local label = g_ui.createWidget("ConsoleLabel", itemsPanel)
	label:setId("npcModalLine" .. itemsPanel:getChildCount())
	label:setFocusable(false)

	local color = isPlayer and "#9F9DFD" or "#5FF7F7"

	local showTimestamps = true
	if modules.client_options and modules.client_options.getOption then
		showTimestamps = modules.client_options.getOption("showTimestampsInConsole")
		if showTimestamps == nil then
			showTimestamps = true
		end
	end

	local timeStr = showTimestamps and (os.date("%H:%M:%S") .. " ") or ""

	local player = g_game.getLocalPlayer()
	local level = (player and player:getLevel()) or 0
	local showLevel = modules.client_options and modules.client_options.getOption and modules.client_options.getOption("showLevelsInConsole")

	local prefix
	if isPlayer then
		if showLevel and level > 0 then
			prefix = string.format("%s%s [%d]: ", timeStr, speaker, level)
		else
			prefix = string.format("%s%s: ", timeStr, speaker)
		end
	else
		prefix = string.format("%s%s: ", timeStr, speaker)
	end

	local maxWidth = getNpcModalItemsPanelWidth()
	local fullText = wrapDialogLineWithHangingIndent(prefix, text or "", maxWidth, "  ", label:getFont())

	label._rawPrefix = prefix
	label._rawText = text or ""
	label._color = color
	label._highlightColor = "#1f9ffe"

	local coloredData = formatNpcHighlightedText(fullText, color, "#1f9ffe")
	label:setColoredText(coloredData)
	label.coloredData = coloredData
	label:setEventListener(EVENT_TEXT_CLICK)
	label:setEventListener(EVENT_TEXT_HOVER)
	connect(label, {
		onTextClick = function(widget, clickedText)
			if clickedText and #clickedText > 0 then
				if clickedText:byte(1) == 1 then
					clickedText = clickedText:sub(2)
				end
				if modules.game_console and modules.game_console.sendNpcModalReply then
					modules.game_console.sendNpcModalReply(clickedText)
				elseif modules.game_console and modules.game_console.onConsoleTextClicked then
					modules.game_console.onConsoleTextClicked(widget, clickedText)
				end
			end
		end,
		onTextHoverChange = function(widget, hoveredText, hovered)
			if modules.game_console and modules.game_console.onConsoleTextHovered then
				modules.game_console.onConsoleTextHovered(widget, hoveredText, hovered)
			end
		end
	})

	setupNpcModalLabelSelection(label, itemsPanel)

	local scrollBar = itemsPanelScrollBar
	if scrollBar then
		addEvent(function()
			if scrollBar and not scrollBar:isDestroyed() then
				scrollBar:setValue(scrollBar:getMaximum())
			end
		end)
	end
end

local function isNpcFarewellText(text)
	if not text then return false end
	local lower = text:lower()

	-- If it's a greeting, question, or trade offer, it is NOT a farewell
	if lower:find("hello", 1, true) or lower:find("welcome", 1, true) or lower:find("greetings", 1, true)
		or lower:find("to see you", 1, true) or lower:find("what i offer", 1, true) or lower:find("what do you want", 1, true)
		or lower:find("how can i help", 1, true) or lower:find("here is what", 1, true) or lower:find("trade", 1, true) then
		return false
	end

	if lower == "bye" or lower == "goodbye" or lower == "farewell" or lower == "cya" then
		return true
	end

	if lower:find("goodbye", 1, true) or lower:find("farewell", 1, true) then
		return true
	end

	if lower:find("see you later", 1, true) or lower:find("see you soon", 1, true) or lower:find("see you around", 1, true) then
		return true
	end

	if lower:match("^bye[%p%s]*$") or lower:match("^bye,") or lower:match("^bye%.") or lower:match("^bye!") then
		return true
	end

	return false
end

local function onGameTalk(name, level, mode, text, channelId, creaturePos)
	local lowerText = text and text:lower() or ""
	if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
		local creature = findCreatureByName(name) or activeNpcCreature or findNearestNpc()
		local detectedButtons = detectNpcButtons(name, text, creature)

		if not isAnyNpcModalVisible() then
			local now = os.clock()
			if (now - npcModalClosedAt) > 1.5 then
				if creature then
					local nearby = findNearbyNpcs(3)
					local ids = {}
					if #nearby > 1 then
						table.insert(ids, creature:getId())
						for _, npc in ipairs(nearby) do
							if npc:getId() ~= creature:getId() then
								table.insert(ids, npc:getId())
							end
						end
					else
						ids = { creature:getId() }
					end
					sendNpcModal({ npcIds = ids, buttons = detectedButtons })
				end
			end
		else
			if mainNpcModal and mainNpcModal:isVisible() then
				if creature then
					addNpcToModal(creature)
				end
				updateNpcModalButtons(detectedButtons)
			end
		end

		if isNpcFarewellText(text) then
			addNpcDialogLine(name, text, false)
			scheduleEvent(function() closeNpcModal() end, 400)
			return
		end

		addNpcDialogLine(name, text, false)
	elseif mode == MessageModes.NpcTo then
		if lowerText == "bye" or lowerText == "adios" or lowerText == "cya" or lowerText == "farewell" then
			if isAnyNpcModalVisible() then
				addNpcDialogLine(g_game.getCharacterName(), text, true)
				scheduleEvent(function() closeNpcModal() end, 400)
				return
			end
		end

		if lowerText == "hi" or lowerText == "hello" or lowerText == "hola" then
			if not isAnyNpcModalVisible() then
				local nearby = findNearbyNpcs(3)
				if #nearby > 1 then
					local ids = {}
					for _, npc in ipairs(nearby) do
						table.insert(ids, npc:getId())
					end
					local detectedButtons = detectNpcButtons(nearby[1]:getName(), "", nearby[1])
					sendNpcModal({ npcIds = ids, buttons = detectedButtons })
				elseif #nearby == 1 then
					local detectedButtons = detectNpcButtons(nearby[1]:getName(), "", nearby[1])
					sendNpcModal({ npcIds = { nearby[1]:getId() }, buttons = detectedButtons })
				end
			end
		end

		if isAnyNpcModalVisible() then
			addNpcDialogLine(g_game.getCharacterName(), text, true)
		end
	end
end

local function isSameNpcTradeItem(itemA, itemB)
	if not itemA or not itemB then
		return false
	end

	if itemA:getId() ~= itemB:getId() then
		return false
	end

	return itemA:getSubType() == itemB:getSubType()
end

local function setNpcTradeItemIcon(icon, item)
	if not icon or not item or not item:getId() or item:getId() == 0 then
		return
	end

	icon:setItem(Item.create(item:getId(), item:getCountOrSubType()))
end

local function updateNpcTradeItem2QuantityPreview(quantity)
	local item2w = item2

	if not item2w or item2w:isDestroyed() or not npcTradeSelectedEntry then
		return
	end

	local tradeItem = npcTradeSelectedEntry.item

	if tradeItem:isFluidContainer() then
		return
	end

	local isChargeable = false
	local itemType = g_things.getThingType(tradeItem:getId(), ThingCategoryItem)

	if itemType then
		isChargeable = itemType:isChargeable()
	end

	if tradeItem:isStackable() or isChargeable then
		if quantity < 1 then
			return
		end

		item2w:setItemCount(quantity)
	end
end

local function wireEscapeToClose(widget, onEscape)
	if not widget or widget:isDestroyed() then
		return
	end

	function widget:onKeyDown(keyCode, keyboardModifiers)
		if keyboardModifiers == KeyboardNoModifier and keyCode == KeyEscape then
			onEscape()

			return true
		end

		if keyboardModifiers == KeyboardCtrlModifier and (keyCode == KeyC or keyCode == 67) then
			local itemsPanel = widget:recursiveGetChildById("itemsPanel")
			if itemsPanel and itemsPanel.selectionText and #itemsPanel.selectionText > 0 then
				g_window.setClipboardText(itemsPanel.selectionText)
				return true
			end
		end

		return false
	end

	local function wireTextEditChildren(parent)
		if not parent or parent:isDestroyed() then
			return
		end

		if parent.getClassName and parent:getClassName() == "UITextEdit" then
			connect(parent, {
				onKeyDown = function(_, keyCode, keyboardModifiers)
					if keyboardModifiers == KeyboardNoModifier and keyCode == KeyEscape then
						onEscape()

						return true
					end

					return false
				end
			})
		end

		for _, child in ipairs(parent:getChildren()) do
			wireTextEditChildren(child)
		end
	end

	wireTextEditChildren(widget)
end

local function capitalizeWords(str)
	return (str:gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

local function formatNumberWithCommas(n)
	local s = tostring(n)
	local pos = string.len(s) % 3

	if pos == 0 then
		pos = 3
	end

	local t = s:sub(1, pos)

	for i = pos + 1, #s, 3 do
		t = t .. "," .. s:sub(i, i + 2)
	end

	return t
end

local function getPlayerInventoryMoney()
	local total = 0
	local containers = g_game.getContainers()
	if containers then
		for _, container in pairs(containers) do
			for slot = 0, container:getCapacity() - 1 do
				local it = container:getItem(slot)
				if it then
					local id = it:getId()
					local count = it:getCount() or 1
					if id == 3031 then
						total = total + count
					elseif id == 3035 then
						total = total + count * 100
					elseif id == 3043 then
						total = total + count * 10000
					end
				end
			end
		end
	end

	local player = g_game.getLocalPlayer()
	if player then
		for slot = 1, 10 do
			local it = player:getInventoryItem(slot)
			if it then
				local id = it:getId()
				local count = it:getCount() or 1
				if id == 3031 then
					total = total + count
				elseif id == 3035 then
					total = total + count * 100
				elseif id == 3043 then
					total = total + count * 10000
				end
			end
		end
	end

	return total
end

local function getPlayerMoney()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	local invMoney = getPlayerInventoryMoney()
	if invMoney > 0 then
		return invMoney
	end

	if npcTradePlayerMoney and npcTradePlayerMoney > 0 then
		return npcTradePlayerMoney
	end

	return player:getTotalMoney() or 0
end

local function isNpcTradeGoldCurrency()
	return npcTradeCurrencyId == nil or npcTradeCurrencyId == GOLD_COIN_ITEM_ID
end

local function getNpcTradeBalance()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	if isNpcTradeGoldCurrency() then
		local invMoney = getPlayerInventoryMoney()
		if invMoney > 0 then
			return invMoney
		end

		if npcTradePlayerMoney and npcTradePlayerMoney > 0 then
			return npcTradePlayerMoney
		end

		return player:getTotalMoney() or 0
	end

	if npcTradeCurrencyId == 0 then
		return player:getResourceBalance(ResourceTypes.NPC_CURRENCY_AMOUNT) or 0
	end

	local balance = player:getResourceBalance(ResourceTypes.CURRENCY_CUSTOM_EQUIPPED) or 0

	if player.getInventoryCount then
		local inventoryCount = player:getInventoryCount(npcTradeCurrencyId, 0) or 0

		return math.max(balance, inventoryCount)
	end

	return balance
end

local function playerHasLootPouch()
	local player = g_game.getLocalPlayer()

	if player and player.getInventoryCount and player:getInventoryCount(LOOT_POUCH_ITEM_ID, 0) > 0 then
		return true
	end

	if g_game.findPlayerItem and g_game.findPlayerItem(LOOT_POUCH_ITEM_ID, -1, 0) then
		return true
	end

	return next(lootPouchItems) ~= nil
end

local function refreshSellAllButtonVisibility()
	if not sellAllButton or sellAllButton:isDestroyed() then
		return
	end

	local isSelling = sellButton and sellButton:isOn()
	local shouldShow = (npcModalTrade == true and isSelling)
	sellAllButton:setVisible(shouldShow)

	if itemsSelling then
		if shouldShow then
			itemsSelling:setMarginTop(26)
		else
			itemsSelling:setMarginTop(6)
		end
	end
end

local function updateBuySellButtonTooltip()
	if not BuySellButton or BuySellButton:isDestroyed() then
		return
	end

	local isSelling = sellButton and sellButton:isOn()
	if isSelling then
		BuySellButton:setTooltip(tr("Please select an item you want to sell"))
	else
		BuySellButton:setTooltip(tr("Please select an item you want to buy"))
	end
end

local function getEquippedItemCounts()
	local counts = {}
	local player = g_game.getLocalPlayer()

	if not player then
		return counts
	end

	local firstSlot = InventorySlotFirst or 1
	local lastSlot = InventorySlotLast or 10

	for slot = firstSlot, lastSlot do
		local invItem = player:getInventoryItem(slot)

		if invItem then
			local id = invItem:getId()
			local qty = invItem:getCount() or 1

			if qty < 1 then
				qty = 1
			end

			counts[id] = (counts[id] or 0) + qty
		end
	end

	return counts
end

local function countPlayerActualItem(itemId)
	local count = 0
	local containers = g_game.getContainers()
	if containers then
		for _, container in pairs(containers) do
			for slot = 0, container:getCapacity() - 1 do
				local it = container:getItem(slot)
				if it and it:getId() == itemId then
					count = count + (it:isStackable() and it:getCount() or 1)
				end
			end
		end
	end

	local player = g_game.getLocalPlayer()
	if player then
		for slot = 1, 10 do
			local it = player:getInventoryItem(slot)
			if it and it:getId() == itemId then
				count = count + (it:isStackable() and it:getCount() or 1)
			end
		end
	end

	return count
end

local function getSellablePlayerItemCount(itemId)
	if not itemId or itemId <= 0 then
		return 0
	end

	local total = (playerItems and playerItems[itemId]) or 0

	local actualCount = countPlayerActualItem(itemId)
	if actualCount > total then
		total = actualCount
	end

	-- Guard against server sending ghost counts for non-stackable items (like ice rapier) when player has none
	if total > 0 and actualCount == 0 then
		local containers = g_game.getContainers()
		local hasOpenContainers = containers and (next(containers) ~= nil)
		if hasOpenContainers then
			local itemType = g_things.getThingType(itemId, ThingCategoryItem)
			if itemType and not itemType:isStackable() then
				total = 0
			end
		end
	end

	if total <= 0 then
		return 0
	end

	if sellEquipped then
		return total
	end

	local equipped = getEquippedItemCounts()[itemId] or 0
	local effective = total - equipped

	if effective < 0 then
		effective = 0
	end

	return effective
end

local function saveNpcModalSettings()
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	pcall(function()
		if not g_resources.directoryExists("/settings/") then
			g_resources.makeDir("/settings/")
		end
	end)

	local data = {}

	if g_resources.fileExists(NPC_MODAL_SETTINGS_FILE) then
		local ok, decoded = pcall(function()
			return json.decode(g_resources.readFileContents(NPC_MODAL_SETTINGS_FILE))
		end)

		if ok and type(decoded) == "table" then
			data = decoded
		end
	end

	local pos = mainNpcModal:getPosition()
	local size = mainNpcModal:getSize()
	local saveW = size.width

	if npcModalTrade then
		saveW = saveW - NPC_MODAL_TRADE_EXTRA_W
	end

	saveW = math.min(NPC_MODAL_MAX_W, math.max(NPC_MODAL_MIN_W, saveW))

	local saveH = math.min(NPC_MODAL_MAX_H, math.max(NPC_MODAL_MIN_H, size.height))

	data.npcDialogOptions = {
		x = pos.x,
		y = pos.y,
		width = saveW,
		height = saveH
	}

	data.npcTradeOptions = {
		sortByName = sortByName,
		sortByPrice = sortByPrice,
		sortByWeight = sortByWeight,
		buyInShoppingBags = buyInShoppingBags,
		ignoreCapacity = ignoreCapacity,
		sellEquipped = sellEquipped,
		showSearchField = showSearchField,
		doNotShowWarningLargeAmounts = doNotShowWarningLargeAmounts
	}

	local ok, serialized = pcall(function()
		return json.encode(data, 2)
	end)

	if ok and serialized then
		pcall(function()
			g_resources.writeFileContents(NPC_MODAL_SETTINGS_FILE, serialized)
		end)
	end
end

local function applySearchFieldVisibility()
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end
	if not searchEdit or not clearSearch or not itemsSelling then
		return
	end

	if showSearchField then
		searchEdit:show()
		clearSearch:show()
		itemsSelling:setMarginBottom(103)
	else
		searchEdit:hide()
		clearSearch:hide()
		itemsSelling:setMarginBottom(78)
	end
end

local function loadNpcModalSettings()
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	if not g_resources.fileExists(NPC_MODAL_SETTINGS_FILE) then
		return
	end

	local ok, decoded = pcall(function()
		return json.decode(g_resources.readFileContents(NPC_MODAL_SETTINGS_FILE))
	end)

	if ok and type(decoded) == "table" then
		local settingsData = decoded
		local npcOpts = settingsData.npcDialogOptions

		if not npcOpts and settingsData.height and tonumber(settingsData.height) then
			npcOpts = settingsData
		end

		if npcOpts then
			local nx = tonumber(npcOpts.x)
			local ny = tonumber(npcOpts.y)
			local hasPos = nx ~= nil and ny ~= nil

			if hasPos then
				mainNpcModal:breakAnchors()
			end

			local w = tonumber(npcOpts.width)
			local h = tonumber(npcOpts.height)
			local validW = w and w >= NPC_MODAL_MIN_W and w <= NPC_MODAL_MAX_W
			local validH = h and h >= NPC_MODAL_MIN_H and h <= NPC_MODAL_MAX_H

			if validW and validH then
				mainNpcModal:setWidth(w)
				mainNpcModal:setHeight(h)
			else
				mainNpcModal:setWidth(NPC_MODAL_DEFAULT_W)
				mainNpcModal:setHeight(NPC_MODAL_DEFAULT_H)
			end

			if hasPos then
				mainNpcModal:setPosition({
					x = nx,
					y = ny
				})
				mainNpcModal:bindRectToParent()
			end
		end

		local tradeOpts = settingsData.npcTradeOptions
		if type(tradeOpts) == "table" then
			if type(tradeOpts.sortByName) == "boolean" then
				sortByName = tradeOpts.sortByName
			end
			if type(tradeOpts.sortByPrice) == "boolean" then
				sortByPrice = tradeOpts.sortByPrice
			end
			if type(tradeOpts.sortByWeight) == "boolean" then
				sortByWeight = tradeOpts.sortByWeight
			end
			if type(tradeOpts.buyInShoppingBags) == "boolean" then
				buyInShoppingBags = tradeOpts.buyInShoppingBags
			end
			if type(tradeOpts.ignoreCapacity) == "boolean" then
				ignoreCapacity = tradeOpts.ignoreCapacity
			end
			if type(tradeOpts.sellEquipped) == "boolean" then
				sellEquipped = tradeOpts.sellEquipped
			end
			if type(tradeOpts.showSearchField) == "boolean" then
				showSearchField = tradeOpts.showSearchField
			end
			if type(tradeOpts.doNotShowWarningLargeAmounts) == "boolean" then
				doNotShowWarningLargeAmounts = tradeOpts.doNotShowWarningLargeAmounts
			end
			applySearchFieldVisibility()
		end

		return decoded
	end

	return nil
end

local function sellAllGetCharacterName()
	local p = g_game.getLocalPlayer()

	if not p then
		return nil
	end

	local ok, name = pcall(function()
		return p:getName()
	end)

	if ok and type(name) == "string" and name ~= "" then
		return name
	end

	return nil
end

local function saveSellAllIgnoreList()
	pcall(function()
		if not g_resources.directoryExists("/settings/") then
			g_resources.makeDir("/settings/")
		end
	end)

	local data = {}

	if g_resources.fileExists(NPC_MODAL_SETTINGS_FILE) then
		local ok, decoded = pcall(function()
			return json.decode(g_resources.readFileContents(NPC_MODAL_SETTINGS_FILE))
		end)

		if ok and type(decoded) == "table" then
			data = decoded
		end
	end

	local characterName = sellAllGetCharacterName()

	if not characterName then
		return
	end

	local ids = {}
	local seen = {}

	for itemId, active in pairs(sellAllIgnoredItems) do
		local id = tonumber(itemId)

		if id and active == true and not seen[id] then
			seen[id] = true

			table.insert(ids, id)
		end
	end

	table.sort(ids)

	local byIds = data.sellAllIgnoreIdsByCharacter

	if type(byIds) ~= "table" then
		byIds = {}
		data.sellAllIgnoreIdsByCharacter = byIds
	end

	byIds[characterName] = ids

	local legacyByChar = data.sellAllIgnoreListByCharacter

	if type(legacyByChar) == "table" then
		legacyByChar[characterName] = nil

		if next(legacyByChar) == nil then
			data.sellAllIgnoreListByCharacter = nil
		end
	end

	data.sellAllIgnoreList = nil

	local ok, serialized = pcall(function()
		return json.encode(data, 2)
	end)

	if ok and serialized then
		pcall(function()
			g_resources.writeFileContents(NPC_MODAL_SETTINGS_FILE, serialized)
		end)
	end
end

local function loadSellAllIgnoreList()
	for k in pairs(sellAllIgnoredItems) do
		sellAllIgnoredItems[k] = nil
	end

	local characterName = sellAllGetCharacterName()

	if not characterName then
		return
	end

	if not g_resources.fileExists(NPC_MODAL_SETTINGS_FILE) then
		return
	end

	local ok, decoded = pcall(function()
		return json.decode(g_resources.readFileContents(NPC_MODAL_SETTINGS_FILE))
	end)

	if not ok or type(decoded) ~= "table" then
		return
	end

	local function tableNonempty(t)
		return type(t) == "table" and next(t) ~= nil
	end

	local needResaveFormat = false
	local mergedIds = {}
	local got = {}

	local function addIgnoredId(itId)
		itId = tonumber(itId)

		if itId and not got[itId] then
			got[itId] = true
			mergedIds[#mergedIds + 1] = itId
		end
	end

	local byIds = decoded.sellAllIgnoreIdsByCharacter

	if type(byIds) == "table" and tableNonempty(byIds[characterName]) then
		local block = byIds[characterName]

		if #block > 0 then
			for _, v in ipairs(block) do
				addIgnoredId(v)
			end
		elseif next(block) then
			for _, v in pairs(block) do
				addIgnoredId(v)
			end
		end
	end

	local legacyQtyByChar = decoded.sellAllIgnoreListByCharacter
	local hasLegacyQtyForChar = type(legacyQtyByChar) == "table" and tableNonempty(legacyQtyByChar[characterName])

	if hasLegacyQtyForChar then
		needResaveFormat = true

		for k in pairs(legacyQtyByChar[characterName]) do
			addIgnoredId(k)
		end
	end

	local hasPersonalIdsLoaded = #mergedIds > 0 or hasLegacyQtyForChar
	local globalLegacy = decoded.sellAllIgnoreList

	if not hasPersonalIdsLoaded and type(globalLegacy) == "table" and next(globalLegacy) ~= nil then
		needResaveFormat = true

		for k, amt in pairs(globalLegacy) do
			if tonumber(amt) and tonumber(amt) > 0 then
				addIgnoredId(k)
			end
		end
	end

	table.sort(mergedIds)

	for _, itId in ipairs(mergedIds) do
		sellAllIgnoredItems[itId] = true
	end

	if needResaveFormat then
		saveSellAllIgnoreList()
	end
end

local refreshNpcTradeItemList, revalidateNpcTradeQuantity

local function onNpcModalFreeCapacityChange(player, freeCapacity)
	if not npcModalTrade then
		return
	end

	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	revalidateNpcTradeQuantity()
end

local function onNpcModalInventoryChange(player, slot, item, oldItem)
	if not npcModalTrade and not (sellAllModal and sellAllModal:isVisible()) then
		return
	end

	if sellAllModal and sellAllModal:isVisible() then
		refreshSellAllModalLists()
	end

	if not mainNpcModal or mainNpcModal:isDestroyed() or not mainNpcModal:isVisible() then
		return
	end

	refreshNpcTradeItemList()
	revalidateNpcTradeQuantity()
	refreshSellAllButtonVisibility()
	updateNpcTradePlayerBalanceLabel()
end

local npcModalContainerUpdateEvent = nil
local function onNpcModalContainerChange()
	if not npcModalTrade and not (sellAllModal and sellAllModal:isVisible()) then
		return
	end

	if npcModalContainerUpdateEvent then
		removeEvent(npcModalContainerUpdateEvent)
	end

	npcModalContainerUpdateEvent = scheduleEvent(function()
		npcModalContainerUpdateEvent = nil
		if not npcModalTrade and not (sellAllModal and sellAllModal:isVisible()) then
			return
		end

		if sellAllModal and sellAllModal:isVisible() then
			refreshSellAllModalLists()
		end

		if not mainNpcModal or mainNpcModal:isDestroyed() or not mainNpcModal:isVisible() then
			return
		end

		refreshNpcTradeItemList()
		revalidateNpcTradeQuantity()
		refreshSellAllButtonVisibility()
		updateNpcTradePlayerBalanceLabel()
	end, 100)
end

local function bindNpcModalPlayerInventoryListener()
	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	disconnect(player, {
		onInventoryChange = onNpcModalInventoryChange
	})
	connect(player, {
		onInventoryChange = onNpcModalInventoryChange
	})
end

local function unbindNpcModalPlayerInventoryListener()
	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	disconnect(player, {
		onInventoryChange = onNpcModalInventoryChange
	})
end

local function npcModalOnSellAllGameStart()
	lootPouchItems = {}

	refreshSellAllButtonVisibility()
	loadSellAllIgnoreList()
	bindNpcModalPlayerInventoryListener()
	addEvent(function()
		if mainNpcModal and not mainNpcModal:isDestroyed() then
			bindNpcModalPlayerInventoryListener()
		end
	end)
end

local function updateNpcTradePriceLabel(price)
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	if not labelPrice or labelPrice:isDestroyed() then
		return
	end

	local priceToShow = 0

	if price and price > 0 then
		priceToShow = price
	end

	labelPrice:setText(formatNumberWithCommas(priceToShow))
end

local function getNpcTradeSelectedBuyEntry()
	if not npcTradeSelectedEntry or not buyButton or not buyButton:isOn() then
		return nil
	end

	return npcTradeSelectedEntry
end

local function getNpcTradeCapacityMaxBuyCount()
	if ignoreCapacity then
		return 10000
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	local entry = getNpcTradeSelectedBuyEntry()
	local weight = entry and entry.weight or 0

	if weight <= 0 then
		return 10000
	end

	local freeCapacity = player:getFreeCapacity() or 0

	return math.floor(freeCapacity / weight)
end

local function computeNpcTradeQuantityRange()
	if not npcTradeSelectedEntry or (npcTradeCurrentUnitPrice or 0) <= 0 then
		return 0, 0
	end

	if not buyButton or not countScrollBar then
		return 1, 1
	end

	local unit = npcTradeCurrentUnitPrice

	if buyButton:isOn() then
		local playerMoney = getNpcTradeBalance()
		local moneyMax = math.floor(playerMoney / unit)
		local capacityMax = getNpcTradeCapacityMaxBuyCount()
		local q = math.min(moneyMax, capacityMax)

		if q < 1 then
			return 0, 0
		end

		return 1, math.min(q, 10000)
	else
		local itemCount = getSellablePlayerItemCount(npcTradeSelectedEntry.item:getId())

		if itemCount < 1 then
			return 0, 0
		end

		return 1, math.min(itemCount, 10000)
	end
end

local function isNpcTradeQuantityAvailable()
	return npcTradeSelectedEntry ~= nil and (npcTradeCurrentUnitPrice or 0) > 0
end

local isChangingQuantity = false

local function setNpcTradeAmountScrollRange(scrollBar, minVal, maxVal)
	if not scrollBar or scrollBar:isDestroyed() then
		return
	end

	if scrollBar:getMinimum() ~= minVal or scrollBar:getMaximum() ~= maxVal then
		scrollBar:setRange(minVal, maxVal)
	end

	local slider = scrollBar:getChildById("sliderButton")

	if slider then
		local shouldBeVisible = (minVal < maxVal and maxVal > 1)
		if slider:isVisible() ~= shouldBeVisible then
			slider:setVisible(shouldBeVisible)
		end
	end
end

local function clearNpcTradeQuantity()
	npcTradeQuantity = 0

	isChangingQuantity = true
	if countScrollBar and not countScrollBar:isDestroyed() then
		setNpcTradeAmountScrollRange(countScrollBar, 0, 0)
		countScrollBar:setValue(0)
	end

	if userInput and not userInput:isDestroyed() then
		userInput:setText("")
	end
	isChangingQuantity = false
end

local function applyNpcTradeQuantity(n)
	if not countScrollBar or not userInput or countScrollBar:isDestroyed() or userInput:isDestroyed() or not npcModalTrade then
		return
	end

	if not isNpcTradeQuantityAvailable() then
		clearNpcTradeQuantity()
		updateNpcTradePriceLabel(nil)

		return
	end

	local minV, maxV = computeNpcTradeQuantityRange()

	if minV == 0 and maxV == 0 then
		clearNpcTradeQuantity()
		updateNpcTradePriceLabel(0)

		return
	end

	n = math.floor(tonumber(n) or 1)
	n = math.max(minV, math.min(maxV, n))

	setNpcTradeAmountScrollRange(countScrollBar, minV, maxV)

	isChangingQuantity = true
	if countScrollBar:getValue() ~= n then
		countScrollBar:setValue(n)
	end
	if userInput:getText() ~= tostring(n) then
		userInput:setText(tostring(n))
	end
	isChangingQuantity = false

	updateNpcTradeItem2QuantityPreview(n)
	updateNpcTradePriceLabel(npcTradeCurrentUnitPrice * n)

	npcTradeQuantity = n
end

function revalidateNpcTradeQuantity()
	if not userInput or userInput:isDestroyed() then
		return
	end

	if not isNpcTradeQuantityAvailable() then
		clearNpcTradeQuantity()

		return
	end

	local n = tonumber(userInput:getText())

	n = n or 1

	applyNpcTradeQuantity(n)
end

updateNpcTradePlayerBalanceLabel = function()
	if not mainNpcModal or mainNpcModal:isDestroyed() or not npcModalTrade then
		return
	end

	if not playerBalance or playerBalance:isDestroyed() then
		return
	end

	if label5 and not label5:isDestroyed() then
		if isNpcTradeGoldCurrency() then
			label5:setText(tr("Gold:"))
		else
			label5:setText(tr("Stock:"))
		end
	end

	playerBalance:setText(tr("%s", formatNumberWithCommas(getNpcTradeBalance())))

	if isNpcTradeQuantityAvailable() then
		revalidateNpcTradeQuantity()
	end
end

local function refreshNpcTradeCurrencyState()
	if not mainNpcModal or mainNpcModal:isDestroyed() or not npcModalTrade then
		return
	end

	updateNpcTradePlayerBalanceLabel()
	refreshNpcTradeItemList()
end

local function setupNpcTradeQuantityBindings()
	if not countScrollBar or not userInput then
		return
	end

	function countScrollBar:onValueChange(value, delta)
		if isChangingQuantity then
			return
		end

		if not isNpcTradeQuantityAvailable() then
			return
		end

		isChangingQuantity = true
		if userInput:getText() ~= tostring(value) then
			userInput:setText(tostring(value))
		end
		isChangingQuantity = false

		npcTradeQuantity = value
		updateNpcTradeItem2QuantityPreview(value)
		updateNpcTradePriceLabel(npcTradeCurrentUnitPrice * value)
	end

	function userInput:onTextChange()
		if isChangingQuantity then
			return
		end

		local raw = self:getText() or ""

		if raw:len() == 0 then
			return
		end

		local n = tonumber(raw:match("^%d+"))

		if not n then
			if isNpcTradeQuantityAvailable() then
				applyNpcTradeQuantity(1)
			else
				clearNpcTradeQuantity()
			end

			return
		end

		applyNpcTradeQuantity(n)
	end
end

local function onNpcModalResourcesBalanceChange(value, oldBalance, resourceType)
	if not npcModalTrade then
		return
	end

	if isNpcTradeGoldCurrency() then
		if resourceType ~= ResourceTypes.BANK_BALANCE and resourceType ~= ResourceTypes.GOLD_EQUIPPED then
			return
		end
	elseif npcTradeCurrencyId == 0 then
		if resourceType ~= ResourceTypes.NPC_CURRENCY_AMOUNT then
			return
		end
	elseif resourceType ~= ResourceTypes.CURRENCY_CUSTOM_EQUIPPED then
		return
	end

	refreshNpcTradeCurrencyState()
end

local function setNpcTradeRowHighlight(panel, selectedBox)
	if not panel or panel:isDestroyed() then
		return
	end

	for _, child in pairs(panel:getChildren()) do
		if not child:isDestroyed() and child.setBackgroundColor then
			child:setBackgroundColor("#00000000")
		end
	end

	if selectedBox and not selectedBox:isDestroyed() and selectedBox.setBackgroundColor then
		selectedBox:setBackgroundColor("#585858")
	end
end

local function clearNpcTradeItem2Preview()
	if not mainNpcModal then
		return
	end

	npcTradeCurrentUnitPrice = 0

	if item2 and not item2:isDestroyed() then
		item2:clearItem()
	end

	updateNpcTradePriceLabel(nil)
	clearNpcTradeQuantity()
end

local function applyNpcTradeItem2Preview(entry, price)
	if not entry or not entry.item:getId() or entry.item:getId() == 0 then
		clearNpcTradeItem2Preview()

		return
	end

	if not mainNpcModal then
		return
	end

	if not item2 or item2:isDestroyed() then
		return
	end

	setNpcTradeItemIcon(item2, entry.item)

	npcTradeCurrentUnitPrice = price and price > 0 and price or 0

	if price and price > 0 then
		updateNpcTradePriceLabel(price)
	else
		updateNpcTradePriceLabel(nil)
	end

	if sellButton and sellButton:isOn() then
		local _, maxV = computeNpcTradeQuantityRange()

		applyNpcTradeQuantity(maxV > 0 and maxV or 1)
	else
		applyNpcTradeQuantity(1)
	end
end

local function shortenNpcTradeText(s, maxLen)
	s = tostring(s or "")

	if maxLen < 4 then
		return s
	end

	if maxLen >= #s then
		return s
	end

	return s:sub(1, maxLen - 3) .. "..."
end

local function hideTradeWindowChildrens()
	menuButton:hide()
	sep1:hide()
	label1:hide()
	currencyName:hide()
	item:hide()
	buyButton:hide()
	sellButton:hide()
	itemsSelling:hide()
	searchEdit:hide()
	countScrollBar:hide()
	clearSearch:hide()
	label3:hide()
	label4:hide()
	label5:hide()
	labelPrice:hide()
	playerBalance:hide()
	userInput:hide()
	item2:hide()
	BuySellButton:hide()
	sellAllButton:hide()
end

local function showTradeWindowChildrens()
	menuButton:show()
	sep1:show()
	label1:show()
	currencyName:show()
	item:show()

	if item and (item:getItemId() == 0 or not item:getItem()) then
		item:setItemId(GOLD_COIN_ITEM_ID)
		item:setItemCount(100)
		item:setTooltip("Gold Coin")
	end
	if currencyName and (currencyName:getText() == "" or not currencyName:getText()) then
		currencyName:setText(tr("Gold Coin"))
	end

	buyButton:show()
	sellButton:show()
	itemsSelling:show()
	applySearchFieldVisibility()
	countScrollBar:show()
	label3:show()
	label4:show()
	label5:show()
	labelPrice:show()
	playerBalance:show()
	userInput:show()
	item2:show()
	BuySellButton:show()
	updateBuySellButtonTooltip()
	refreshSellAllButtonVisibility()
end

function refreshNpcTradeItemList()
	local panel = itemsSelling:getChildById("npcTradeItemsPanel")

	if not panel then
		return
	end

	local buying = buyButton:isOn()
	local items = buying and BuyNpcTradeItems or SellNpcTradeItems
	local rows = {}

	for _, entry in ipairs(items) do
		local price = buying and entry.buyPrice or entry.sellPrice
		local show = true

		if npcTradeFilterText ~= "" then
			local haystack = (entry.name or ""):lower()

			show = haystack:find(npcTradeFilterText, 1, true) ~= nil
		end

		if show then
			table.insert(rows, {
				entry = entry,
				price = price
			})
		end
	end

	local function compareRows(a, b)
		if sortByName then
			local na = (a.entry.name or ""):lower()
			local nb = (b.entry.name or ""):lower()
			if na ~= nb then
				return na < nb
			end
			return (a.entry.item:getId() or 0) < (b.entry.item:getId() or 0)
		elseif sortByPrice then
			if a.price ~= b.price then
				return a.price < b.price
			end
			local na = (a.entry.name or ""):lower()
			local nb = (b.entry.name or ""):lower()
			if na ~= nb then
				return na < nb
			end
			return (a.entry.item:getId() or 0) < (b.entry.item:getId() or 0)
		elseif sortByWeight then
			local wa = a.entry.weight or 0
			local wb = b.entry.weight or 0
			if wa ~= wb then
				return wa < wb
			end
			local na = (a.entry.name or ""):lower()
			local nb = (b.entry.name or ""):lower()
			if na ~= nb then
				return na < nb
			end
			return (a.entry.item:getId() or 0) < (b.entry.item:getId() or 0)
		end
		return (a.entry.item:getId() or 0) < (b.entry.item:getId() or 0)
	end

	table.sort(rows, compareRows)

	local countCache = {}
	for _, row in ipairs(rows) do
		local id = row.entry.item:getId()
		if countCache[id] == nil then
			countCache[id] = getSellablePlayerItemCount(id)
		end
	end

	if not buying then
		table.sort(rows, function(a, b)
			local idA, idB = a.entry.item:getId(), b.entry.item:getId()
			local hasA = (countCache[idA] or 0) > 0
			local hasB = (countCache[idB] or 0) > 0

			if hasA and not hasB then
				return true
			elseif not hasA and hasB then
				return false
			end

			return compareRows(a, b)
		end)
	end

	local existingBoxes = panel:getChildren()
	local existingCount = #existingBoxes
	local neededCount = #rows

	if existingCount > neededCount then
		for i = existingCount, neededCount + 1, -1 do
			existingBoxes[i]:destroy()
		end
	end

	local selectedBox

	for i, row in ipairs(rows) do
		local entry = row.entry
		local price = row.price
		local box
		if i <= existingCount then
			box = existingBoxes[i]
		else
			box = g_ui.createWidget("NpcItemBox", panel)
		end

		if box.setBackgroundColor then
			box:setBackgroundColor("#00000000")
		end

		if npcTradeSelectedEntry and isSameNpcTradeItem(entry.item, npcTradeSelectedEntry.item) then
			selectedBox = box
		end

		local entryId = entry.item:getId()
		local ownedCount = countCache[entryId] or getSellablePlayerItemCount(entryId) or 0
		local sellableCount = not buying and ownedCount or 0
		local disabled = false

		local icon = box:getChildById("itemIcon")
		if icon then
			setNpcTradeItemIcon(icon, entry.item)
			if icon.setShowCount then
				icon:setShowCount(true)
			end
			if icon.setDisplayCount then
				icon:setDisplayCount(ownedCount)
			end
		end

		local nameLbl = box:getChildById("nameLabel")
		local infoLbl = box:getChildById("infoLabel")

		if not buying then
			disabled = sellableCount <= 0
		elseif buying and price > getNpcTradeBalance() then
			disabled = true
		end

		if nameLbl then
			nameLbl:setText(shortenNpcTradeText(entry.name or "", 26))

			if disabled then
				nameLbl:setColor("#707070")
			else
				nameLbl:setColor("#c0c0c0")
			end
		end

		if infoLbl then
			local line = tr("Price %d, %.2f oz", price, entry.weight or 0)

			infoLbl:setText(shortenNpcTradeText(line, 36))

			if disabled then
				infoLbl:setColor("#707070")
			else
				infoLbl:setColor("#c0c0c0")
			end
		end

		local function onRowMousePress(widget, mousePos, mouseButton)
			local keyboardModifiers = g_keyboard.getModifiers()
			if keyboardModifiers == KeyboardShiftModifier then
				if g_game.inspectNpcTrade then
					g_game.inspectNpcTrade(entry.item)
				else
					g_game.look(entry.item)
				end
				return true
			end

			if mouseButton ~= MouseLeftButton then
				if mouseButton == MouseRightButton then
					npcTradeLookThing = entry.item

					showMenuFilters(true)
				end

				return false
			end

			npcTradeSelectedEntry = entry

			applyNpcTradeItem2Preview(entry, price)
			setNpcTradeRowHighlight(panel, box)

			return true
		end

		box.onMousePress = onRowMousePress

		if icon then
			icon.onMousePress = onRowMousePress
		end

		if nameLbl then
			nameLbl.onMousePress = onRowMousePress
		end

		if infoLbl then
			infoLbl.onMousePress = onRowMousePress
		end
	end

	if npcTradeSelectedEntry then
		if selectedBox then
			for _, row in ipairs(rows) do
				if isSameNpcTradeItem(row.entry.item, npcTradeSelectedEntry.item) then
					applyNpcTradeItem2Preview(row.entry, row.price)

					break
				end
			end
		else
			npcTradeSelectedEntry = nil

			clearNpcTradeItem2Preview()
		end
	end

	setNpcTradeRowHighlight(panel, selectedBox)
	addEvent(function()
		if not mainNpcModal or mainNpcModal:isDestroyed() then
			return
		end
		if not itemsSelling or itemsSelling:isDestroyed() then
			return
		end

		local p = itemsSelling:getChildById("npcTradeItemsPanel")

		if not p or p:isDestroyed() then
			return
		end

		if p.updateScrollBars then
			p:updateScrollBars()
		end
	end)
end

function search(text, type)
	if text == nil and mainNpcModal then
		local w

		if type == 1 then
			w = searchEdit
		elseif type == 2 then
			w = sellAllModal:recursiveGetChildById("search2")
		elseif type == 3 then
			w = sellAllModal:recursiveGetChildById("search3")
		end

		text = w and w:getText() or ""
	end

	text = tostring(text or ""):lower():trim()

	if type == 1 then
		npcTradeFilterText = text

		refreshNpcTradeItemList()
	elseif type == 2 then
		FilterText2 = text

		refreshSellAllModalLists()
	elseif type == 3 then
		FilterText3 = text

		refreshSellAllModalLists()
	end
end

function clearTradeSearch(type)
	if type == 1 then
		if mainNpcModal then
			if searchEdit then
				searchEdit:clearText()
			end
		end

		npcTradeFilterText = ""

		refreshNpcTradeItemList()
	elseif type == 2 then
		if sellAllModal then
			local w = sellAllModal:recursiveGetChildById("search2")

			if w then
				w:clearText()
			end
		end

		FilterText2 = ""

		refreshSellAllModalLists()
	elseif type == 3 then
		if sellAllModal then
			local w = sellAllModal:recursiveGetChildById("search3")

			if w then
				w:clearText()
			end
		end

		FilterText3 = ""

		refreshSellAllModalLists()
	end
end

function onNpcTradeBuyClick()
	buyButton:setOn(true)
	sellButton:setOn(false)
	BuySellButton:setText(tr("Buy"))
	updateBuySellButtonTooltip()
	refreshSellAllButtonVisibility()
	refreshNpcTradeItemList()
end

function onNpcTradeSellClick()
	sellButton:setOn(true)
	buyButton:setOn(false)
	BuySellButton:setText(tr("Sell"))
	updateBuySellButtonTooltip()
	refreshSellAllButtonVisibility()
	refreshNpcTradeItemList()
end

function onConfirmTrade()
	if not npcTradeSelectedEntry or not npcTradeSelectedEntry.item or npcTradeSelectedEntry.item:getId() == 0 then
		return
	end

	local item = npcTradeSelectedEntry.item
	local amount = math.floor(npcTradeQuantity or 0)

	if amount < 1 then
		return
	end

	amount = math.min(amount, 65535)

	if buyButton:isOn() then
		local itemPrice = npcTradeSelectedEntry.buyPrice or 0
		local totalPrice = itemPrice * amount
		local playerMoney = getNpcTradeBalance()

		if playerMoney < totalPrice then
			return
		end

		if not ignoreCapacity then
			local capacityMax = getNpcTradeCapacityMaxBuyCount()

			if capacityMax < amount then
				return
			end
		end

		local maxAmountPerPacket = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
		local remBuy = amount
		while remBuy > 0 do
			local chunk = math.min(remBuy, maxAmountPerPacket)
			g_game.buyItem(item, chunk, ignoreCapacity, buyInShoppingBags)
			remBuy = remBuy - chunk
		end

		local itemId = item:getId()
		if playerItems then
			playerItems[itemId] = (playerItems[itemId] or 0) + amount
		end

		if npcTradePlayerMoney and isNpcTradeGoldCurrency() then
			npcTradePlayerMoney = math.max(0, npcTradePlayerMoney - totalPrice)
		end
		updateNpcTradePlayerBalanceLabel()
		refreshNpcTradeItemList()
		revalidateNpcTradeQuantity()
	else
		local itemId = item:getId()
		local itemCount = getSellablePlayerItemCount(itemId)

		if not itemCount or itemCount < amount then
			return
		end

		local maxAmountPerPacket = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
		local remSell = amount
		while remSell > 0 do
			local chunk = math.min(remSell, maxAmountPerPacket)
			g_game.sellItem(item, chunk, not sellEquipped)
			remSell = remSell - chunk
		end

		if playerItems and playerItems[itemId] then
			playerItems[itemId] = math.max(0, playerItems[itemId] - amount)
		end

		local itemPrice = npcTradeSelectedEntry.sellPrice or 0
		if npcTradePlayerMoney and isNpcTradeGoldCurrency() then
			npcTradePlayerMoney = npcTradePlayerMoney + (itemPrice * amount)
		end
		updateNpcTradePlayerBalanceLabel()

		local remaining = getSellablePlayerItemCount(itemId)
		if remaining <= 0 then
			clearNpcTradeItem2Preview()
		end

		refreshNpcTradeItemList()
		revalidateNpcTradeQuantity()
	end
end

function onMiniborderRightHover(widget, hovered)
	if hovered then
		if g_mouse.isCursorChanged() or g_mouse.isPressed() then
			return
		end

		g_mouse.pushCursor(MINIBORDER_RESIZE_CURSOR)

		widget._npcModalMiniborderHover = true
	elseif not widget:isPressed() and widget._npcModalMiniborderHover then
		g_mouse.popCursor(MINIBORDER_RESIZE_CURSOR)

		widget._npcModalMiniborderHover = false
	end
end

local function setupNpcModalResizeGrip()
	local grip = mainNpcModal and mainNpcModal:recursiveGetChildById("miniborderRight")

	if not grip then
		return
	end

	function grip.onMousePress(widget, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton then
			return false
		end

		local win = widget:getParent()

		npcModalResizeState = {
			startX = mousePos.x,
			startY = mousePos.y,
			w0 = win:getWidth(),
			h0 = win:getHeight(),
			window = win
		}

		return true
	end

	function grip.onMouseMove(widget, mousePos, mouseMoved)
		if not npcModalResizeState then
			return false
		end

		local s = npcModalResizeState
		local win = s.window

		if not win then
			npcModalResizeState = nil

			return false
		end

		local dx = mousePos.x - s.startX
		local dy = mousePos.y - s.startY
		local nw = math.min(NPC_MODAL_MAX_W, math.max(npcModalTrade and 509 or NPC_MODAL_MIN_W, s.w0 + dx))
		local nh = math.min(NPC_MODAL_MAX_H, math.max(NPC_MODAL_MIN_H, s.h0 + dy))

		win:setWidth(nw)
		win:setHeight(nh)
		win:bindRectToParent()

		return true
	end

	function grip.onMouseRelease(widget, mousePos, mouseButton)
		if npcModalResizeState then
			npcModalResizeState = nil
			addEvent(function()
				if mainNpcModal and not mainNpcModal:isDestroyed() then
					rewrapNpcModalDialogLines()
				end
			end)
		end

		if not widget:isHovered() and widget._npcModalMiniborderHover then
			g_mouse.popCursor(MINIBORDER_RESIZE_CURSOR)

			widget._npcModalMiniborderHover = false
		end

		saveNpcModalSettings()

		return false
	end
end

local function setupNpcModalWindowHeaderDrag()
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	mainNpcModal:setDraggable(false)

	local header = mainNpcModal:recursiveGetChildById("windowMoveHeader")

	if not header or header:isDestroyed() then
		return
	end

	header:setDraggable(true)

	function header:onDragEnter(mousePos)
		local win = self:getParent()

		if not win or win:isDestroyed() then
			return false
		end

		win._npcModalOpacityBeforeDrag = win:getOpacity()

		win:setOpacity(NPC_MODAL_DRAG_MOVE_OPACITY)
		win:breakAnchors()

		win.movingReference = {
			x = mousePos.x - win:getX(),
			y = mousePos.y - win:getY()
		}

		return true
	end

	function header:onDragMove(mousePos, mouseMoved)
		local win = self:getParent()

		if not win or win:isDestroyed() or not win.movingReference then
			return false
		end

		local pos = {
			x = mousePos.x - win.movingReference.x,
			y = mousePos.y - win.movingReference.y
		}

		win:setPosition(pos)
		win:bindRectToParent()

		return true
	end

	function header:onDragLeave(droppedWidget, mousePos)
		local win = self:getParent()

		if win and not win:isDestroyed() then
			win.movingReference = nil

			if win._npcModalOpacityBeforeDrag ~= nil then
				win:setOpacity(win._npcModalOpacityBeforeDrag)

				win._npcModalOpacityBeforeDrag = nil
			end
		end

		saveNpcModalSettings()

		return true
	end
end


function setWindowOpacity(opacity)
	if mainNpcModal then
		mainNpcModal:setOpacity(opacity)
	end
end

function init()
	g_ui.importStyle("game_npcmodal")
	connect(g_game, {
		onGameStart = npcModalOnSellAllGameStart,
		onGameEnd = closeNpcModal,
		onTalk = onGameTalk,
		onNpcChatWindow = sendNpcModal,
		onOpenNpcTrade = sendNpcTrade,
		onCloseNpcTrade = onCloseNpcTrade,
		onResourcesBalanceChange = onNpcModalResourcesBalanceChange,
		onPlayerGoods = onPlayerGoods
	})
	connect(LocalPlayer, {
		onPositionChange = checkNpcDistance,
		onInventoryChange = onNpcModalInventoryChange,
		onFreeCapacityChange = onNpcModalFreeCapacityChange
	})
	connect(Container, {
		onOpen = onNpcModalContainerChange,
		onAddItem = onNpcModalContainerChange,
		onUpdateItem = onNpcModalContainerChange,
		onRemoveItem = onNpcModalContainerChange
	})

	mainNpcModal = g_ui.createWidget("NpcModalWindow", rootWidget)

	setupNpcModalWindowHeaderDrag()

	npcOutfit = mainNpcModal:recursiveGetChildById("npcCreatureBox")
	multiNpc = mainNpcModal:recursiveGetChildById("multipleNpc")
	npcNameLabel = mainNpcModal:recursiveGetChildById("npcName")

	mainNpcModal:hide()
	npcOutfit:hide()
	multiNpc:hide()
	npcNameLabel:hide()

	function mainNpcModal.onFocusChange(widget, focused)
		setWindowOpacity(1)
	end

	setupNpcModalResizeGrip()

	menuButton = mainNpcModal:recursiveGetChildById("menuButton")
	sep1 = mainNpcModal:recursiveGetChildById("sep1")
	label1 = mainNpcModal:recursiveGetChildById("label1")
	currencyName = mainNpcModal:recursiveGetChildById("currencyName")
	item = mainNpcModal:recursiveGetChildById("item")
	buyButton = mainNpcModal:recursiveGetChildById("buyButton")
	sellButton = mainNpcModal:recursiveGetChildById("sellButton")
	itemsSelling = mainNpcModal:recursiveGetChildById("itemsSelling")
	searchEdit = mainNpcModal:recursiveGetChildById("search")
	clearSearch = mainNpcModal:recursiveGetChildById("clearSearch")
	countScrollBar = mainNpcModal:recursiveGetChildById("countScrollBar")
	label3 = mainNpcModal:recursiveGetChildById("label3")
	label4 = mainNpcModal:recursiveGetChildById("label4")
	label5 = mainNpcModal:recursiveGetChildById("label5")
	labelPrice = mainNpcModal:recursiveGetChildById("labelPrice")
	playerBalance = mainNpcModal:recursiveGetChildById("playerBalance")
	userInput = mainNpcModal:recursiveGetChildById("userInput")
	item2 = mainNpcModal:recursiveGetChildById("item2")
	if item2 then
		item2.onMousePress = function(widget, mousePos, mouseButton)
			if not npcTradeSelectedEntry or not npcTradeSelectedEntry.item then
				return false
			end
			local keyboardModifiers = g_keyboard.getModifiers()
			if keyboardModifiers == KeyboardShiftModifier then
				if g_game.inspectNpcTrade then
					g_game.inspectNpcTrade(npcTradeSelectedEntry.item)
				else
					g_game.look(npcTradeSelectedEntry.item)
				end
				return true
			end
			if mouseButton == MouseRightButton then
				npcTradeLookThing = npcTradeSelectedEntry.item
				showMenuFilters(true)
				return true
			end
			return false
		end
	end
	BuySellButton = mainNpcModal:recursiveGetChildById("BuySellButton")
	sellAllButton = mainNpcModal:recursiveGetChildById("sellAllButton")
	itemsPanel = mainNpcModal:recursiveGetChildById("itemsPanel")
	readOnlyPanel = mainNpcModal:recursiveGetChildById("readOnlyPanel")
	itemsPanelScrollBar = mainNpcModal:recursiveGetChildById("itemsPanelListScrollBar")
	npcTradeItemsPanel = mainNpcModal:recursiveGetChildById("npcTradeItemsPanel")

	hideTradeWindowChildrens()
	setupNpcTradeQuantityBindings()
	loadNpcModalSettings()

	sellAllModal = g_ui.createWidget("SellAllModalWindow", rootWidget)
	search2Edit = sellAllModal:recursiveGetChildById("search2")
	search3Edit = sellAllModal:recursiveGetChildById("search3")

	sellAllModal:hide()
	wireEscapeToClose(mainNpcModal, closeNpcModal)
	wireEscapeToClose(sellAllModal, closeSellAllWindow)
end

function terminate()
	saveNpcModalSettings()
	saveSellAllIgnoreList()
	stopSellAllAutoRefresh()
	disconnect(g_game, {
		onGameStart = npcModalOnSellAllGameStart,
		onGameEnd = closeNpcModal,
		onTalk = onGameTalk,
		onNpcChatWindow = sendNpcModal,
		onOpenNpcTrade = sendNpcTrade,
		onCloseNpcTrade = onCloseNpcTrade,
		onResourcesBalanceChange = onNpcModalResourcesBalanceChange,
		onPlayerGoods = onPlayerGoods
	})
	disconnect(LocalPlayer, {
		onPositionChange = checkNpcDistance,
		onInventoryChange = onNpcModalInventoryChange,
		onFreeCapacityChange = onNpcModalFreeCapacityChange
	})
	disconnect(Container, {
		onOpen = onNpcModalContainerChange,
		onAddItem = onNpcModalContainerChange,
		onUpdateItem = onNpcModalContainerChange,
		onRemoveItem = onNpcModalContainerChange
	})
	unbindNpcModalPlayerInventoryListener()

	if modules.game_console and modules.game_console.detachConsoleTextEditFromNpcModal then
		modules.game_console.detachConsoleTextEditFromNpcModal()
	end

	if sellAllModal then
		sellAllModal:destroy()
		sellAllModal = nil
	end
	if mainNpcModal then
		mainNpcModal:destroy()
		mainNpcModal = nil
	end
end

onCloseNpcTrade = function()
	stopSellAllAutoRefresh()

	if sellAllModal and sellAllModal:isVisible() then
		sellAllModal:hide()
	end

	if not mainNpcModal then
		return
	end

	hideTradeWindowChildrens()

	npcTradeSelectedEntry = nil
	clearNpcTradeItem2Preview()
	npcTradeCurrencyId = nil

	if label5 and not label5:isDestroyed() then
		label5:setText(tr("Gold:"))
	end

	if npcTradeItemsPanel then
		npcTradeItemsPanel:destroyChildren()
	end

	if npcModalTrade then
		mainNpcModal:setWidth(math.max(NPC_MODAL_MIN_W, mainNpcModal:getWidth() - NPC_MODAL_TRADE_EXTRA_W))
		mainNpcModal:bindRectToParent()
	end

	if readOnlyPanel then
		readOnlyPanel:setMarginRight(16)
	end

	unbindNpcModalPlayerInventoryListener()
	npcModalTrade = false
	addEvent(function()
		if mainNpcModal and not mainNpcModal:isDestroyed() then
			rewrapNpcModalDialogLines()
		end
	end)
end

function closeNpcModal()
	if g_tooltip then
		g_tooltip.hide(true)
		g_tooltip.hideSpecial(true)
	end

	stopSellAllAutoRefresh()

	local sellAllOpen = sellAllModal and sellAllModal:isVisible()
	local mainOpen = mainNpcModal and mainNpcModal:isVisible()

	if sellAllModal then
		sellAllModal:hide()
	end

	if not mainNpcModal or (not mainOpen and not sellAllOpen and not npcModalTrade) then
		return
	end

	onCloseNpcTrade()

	activeNpcCreature = nil
	currentNpcId = nil
	currentNpcIds = {}
	currentModalButtonsKey = ""
	currentTalkingToNpc = ""
	if modules.game_console and modules.game_console.resetTalkingToNpc then
		modules.game_console.resetTalkingToNpc()
	end
	if npcModalContainerUpdateEvent then
		removeEvent(npcModalContainerUpdateEvent)
		npcModalContainerUpdateEvent = nil
	end
	saveSellAllIgnoreList()
	saveNpcModalSettings()

	if modules.game_console and modules.game_console.detachConsoleTextEditFromNpcModal then
		modules.game_console.detachConsoleTextEditFromNpcModal()
	end

	npcModalClosedAt = os.clock()

	for _, w in pairs(sayButtonsActive) do
		if w and not w:isDestroyed() then
			w:destroy()
		end
	end
	sayButtonsActive = {}

	mainNpcModal:hide()

	if itemsPanel then
		itemsPanel:destroyChildren()
	end

	if readOnlyPanel then
		readOnlyPanel:setMarginRight(16)
	end

	if g_game.isOnline() then
		g_game.closeNpcTrade()
		local npcTab = modules.game_console and modules.game_console.consoleTabBar and modules.game_console.consoleTabBar:getTab("NPCs")
		if npcTab then
			modules.game_console.sendMessage("bye", npcTab)
		else
			g_game.talkPrivate(MessageModes.NpcTo, "NPCs", "bye")
		end
	end

	if sellAllModal then
		sellAllModal:hide()
	end
end

function sendNpcModal(data)
	if not data then data = {} end
	if not data.npcIds or #data.npcIds == 0 then
		local nearby = findNearbyNpcs(3)
		if #nearby > 0 then
			data.npcIds = {}
			for _, npc in ipairs(nearby) do
				table.insert(data.npcIds, npc:getId())
			end
		else
			local nearest = findNearestNpc()
			if nearest then
				data.npcIds = { nearest:getId() }
			else
				data.npcIds = {}
			end
		end
	end
	if not data.buttons or #data.buttons == 0 then
		local firstCreature = (data.npcIds and data.npcIds[1]) and g_map.getCreatureById(data.npcIds[1]) or nil
		data.buttons = detectNpcButtons(firstCreature and firstCreature:getName() or "", "", firstCreature)
	end

	currentNpcIds = {}
	for i = 1, #data.npcIds do
		table.insert(currentNpcIds, data.npcIds[i])
	end

	local npcNames = ""
	local npcCount = 0

	for i = 1, #data.npcIds do
		local creature = g_map.getCreatureById(data.npcIds[i])

		if creature then
			npcCount = npcCount + 1

			if npcNames == "" then
				npcNames = creature:getName()
			else
				npcNames = npcNames .. " and " .. creature:getName()
			end
		end
	end

	if npcCount == 0 then
		local nearest = findNearestNpc()
		if nearest then
			data.npcIds = { nearest:getId() }
			npcCount = 1
			npcNames = nearest:getName()
		else
			closeNpcModal()
			return
		end
	end

	if npcCount == 1 then
		if multiNpc then
			multiNpc:hide()
		end

		local creature = g_map.getCreatureById(data.npcIds[1])
		activeNpcCreature = creature

		if creature and npcOutfit then
			npcOutfit:setOutfit(creature:getOutfit())
			npcOutfit:show()
		end
	else
		if multiNpc then
			multiNpc:show()
		end

		local creature = g_map.getCreatureById(data.npcIds[1])
		activeNpcCreature = creature

		if npcOutfit then
			npcOutfit:hide()
		end
	end

	npcNameLabel:setText(npcNames)
	npcNameLabel:show()

	local targetId = (data.npcIds and data.npcIds[1]) or 0
	if currentNpcId ~= targetId then
		currentNpcId = targetId
		if itemsPanel then
			itemsPanel:destroyChildren()
		end
	end

	if npcNames and npcNames ~= "" and currentTalkingToNpc ~= npcNames:lower() then
		addNpcDialogHeader(npcNames)
	end

	updateNpcModalButtons(data.buttons)

	if mainNpcModal then
		if modules.game_console and modules.game_console.attachConsoleTextEditToNpcModal then
			modules.game_console.attachConsoleTextEditToNpcModal(mainNpcModal)
		end

		if not (sellAllModal and sellAllModal:isVisible()) then
			mainNpcModal:show()
			mainNpcModal:focus()
		end

		if modules.game_console and modules.game_console.onNpcModalOpened then
			modules.game_console.onNpcModalOpened()
		end
	end

	if not (sellAllModal and sellAllModal:isVisible()) then
		if npcModalTrade then
			onCloseNpcTrade()
		else
			hideTradeWindowChildrens()
			if readOnlyPanel then
				readOnlyPanel:setMarginRight(16)
			end
		end
	end
end

function sendNpcTrade(items, currencyId)
	npcTradeCurrencyId = currencyId

	local curId = (currencyId and currencyId > 0) and currencyId or GOLD_COIN_ITEM_ID
	local curName = "Gold Coin"
	if curId and curId ~= GOLD_COIN_ITEM_ID then
		local itemObj = Item.create(curId)
		if itemObj and itemObj.getName and itemObj:getName() and itemObj:getName() ~= "" then
			curName = capitalizeWords(itemObj:getName())
		else
			local itemType = g_things.getThingType(curId, ThingCategoryItem)
			if itemType and itemType.getName and itemType:getName() and itemType:getName() ~= "" then
				curName = capitalizeWords(itemType:getName())
			else
				curName = "Item " .. curId
			end
		end
	end

	if item and not item:isDestroyed() then
		item:setItemId(curId)
		item:setItemCount(100)
		item:setTooltip(curName)
	end

	if currencyName and not currencyName:isDestroyed() then
		currencyName:setText(tr(curName))
	end

	BuyNpcTradeItems = {}
	SellNpcTradeItems = {}

	if items and #items > 0 then
		for i, itemData in ipairs(items) do
			if itemData[4] > 0 then
				table.insert(BuyNpcTradeItems, {
					item = itemData[1],
					name = itemData[2],
					weight = itemData[3] / 100,
					buyPrice = itemData[4],
					sellPrice = itemData[5]
				})
			end

			if itemData[5] > 0 then
				table.insert(SellNpcTradeItems, {
					item = itemData[1],
					name = itemData[2],
					weight = itemData[3] / 100,
					buyPrice = itemData[4],
					sellPrice = itemData[5]
				})
			end
		end
	end

	npcTradeSelectedEntry = nil

	clearNpcTradeItem2Preview()

	npcTradeFilterText = ""

	if searchEdit then
		searchEdit:clearText()
	end

	if buyButton and sellButton then
		buyButton:setOn(true)
		sellButton:setOn(false)
		updateBuySellButtonTooltip()
	end

	local sellAllOpen = sellAllModal and sellAllModal:isVisible()

	local tradeButtons = detectNpcButtons(activeNpcCreature and activeNpcCreature:getName() or "", "trade", activeNpcCreature)

	if mainNpcModal and not mainNpcModal:isVisible() and not sellAllOpen then
		local creature = findNearestNpc()
		if creature then
			sendNpcModal({ npcIds = { creature:getId() }, buttons = tradeButtons })
		else
			mainNpcModal:show()
			mainNpcModal:raise()
			mainNpcModal:focus()
			updateNpcModalButtons(tradeButtons)
		end
	elseif mainNpcModal and mainNpcModal:isVisible() then
		updateNpcModalButtons(tradeButtons)
	end

	refreshNpcTradeItemList()
	if not sellAllOpen then
		showTradeWindow()
	else
		refreshSellAllModalLists()
	end
	refreshNpcTradeCurrencyState()
	addEvent(function()
		if not mainNpcModal or mainNpcModal:isDestroyed() then
			return
		end
		if npcModalTrade and npcTradeCurrencyId ~= nil then
			refreshNpcTradeCurrencyState()
		end
	end)
end

function showTradeWindow()
	if not mainNpcModal then
		return
	end

	mainNpcModal:show()
	mainNpcModal:raise()
	mainNpcModal:focus()

	if npcModalTrade then
		showTradeWindowChildrens()

		return
	end

	npcModalTrade = true

	bindNpcModalPlayerInventoryListener()

	if readOnlyPanel then
		readOnlyPanel:setMarginRight(220)
	end

	local newW = math.min(NPC_MODAL_MAX_W, mainNpcModal:getWidth() + NPC_MODAL_TRADE_EXTRA_W)

	mainNpcModal:setWidth(newW)
	mainNpcModal:bindRectToParent()
	showTradeWindowChildrens()
	addEvent(function()
		if mainNpcModal and not mainNpcModal:isDestroyed() then
			rewrapNpcModalDialogLines()
		end
	end)
end

function onPlayerGoods(money, items, lootPouch)
	if type(money) == "number" then
		npcTradePlayerMoney = money
	end

	playerItems = {}

	items = items or {}
	lootPouch = lootPouch or {}

	for _, data in pairs(items) do
		local raw = data[1]
		local id = (type(raw) == "number" and raw) or (raw and raw.getId and raw:getId()) or tonumber(raw)
		local amount = data[2] or 1

		if id and id > 0 then
			playerItems[id] = (playerItems[id] or 0) + amount
		end
	end

	lootPouchItems = {}

	for _, data in pairs(lootPouch) do
		local raw = data[1]
		local id = (type(raw) == "number" and raw) or (raw and raw.getId and raw:getId()) or tonumber(raw)
		local amount = data[2] or 1

		if id and id > 0 then
			lootPouchItems[id] = (lootPouchItems[id] or 0) + amount
		end
	end

	refreshSellAllButtonVisibility()

	if npcModalTrade then
		updateNpcTradePlayerBalanceLabel()
		refreshNpcTradeItemList()
		revalidateNpcTradeQuantity()
	end
end

local function handleSearchField()
	if not mainNpcModal or mainNpcModal:isDestroyed() then
		return
	end

	showSearchField = not showSearchField
	applySearchFieldVisibility()
	saveNpcModalSettings()
end

local function handleSorts(param)
	if param == 1 then
		sortByName = true
		sortByPrice = false
		sortByWeight = false
	elseif param == 2 then
		sortByName = false
		sortByPrice = true
		sortByWeight = false
	elseif param == 3 then
		sortByName = false
		sortByPrice = false
		sortByWeight = true
	end

	refreshNpcTradeItemList()
	saveNpcModalSettings()
end

function showMenuFilters(showLook)
	if not g_game.isOnline() then
		return
	end

	local menu = g_ui.createWidget("GamePopupMenu") or g_ui.createWidget("PopupMenu")
	if not menu then
		return
	end

	menu:setGameMenu(true)
	menu:setWidth(402)
	menu:setHeight(172)

	if showLook then
		menu:addOption(tr("Look"), function()
			if npcTradeLookThing then
				if g_game.inspectNpcTrade then
					g_game.inspectNpcTrade(npcTradeLookThing)
				else
					g_game.look(npcTradeLookThing)
				end
			end
		end)
		menu:addOption(tr("Inspect"), function()
			if not npcTradeLookThing then
				return
			end

			local count = npcTradeLookThing:getCount()

			if not count or count < 1 then
				count = 1
			end

			local inspectType = (InspectObjectTypes and (InspectObjectTypes.INSPECT_NPCTRADE or InspectObjectTypes.NpcTrade)) or 1
			if g_game.inspectionObject then
				g_game.inspectionObject(inspectType, npcTradeLookThing:getId(), count)
			end
		end)
	end

	menu:addCheckBox(tr("Sort by name"), sortByName, function()
		handleSorts(1)
	end)
	menu:addCheckBox(tr("Sort by price"), sortByPrice, function()
		handleSorts(2)
	end)
	menu:addCheckBox(tr("Sort by weight"), sortByWeight, function()
		handleSorts(3)
	end)
	menu:addSeparator()
	menu:addCheckBox(tr("Buy in shopping bags"), buyInShoppingBags, function()
		buyInShoppingBags = not buyInShoppingBags
		saveNpcModalSettings()
	end)
	menu:addCheckBox(tr("Ignore capacity"), ignoreCapacity, function()
		ignoreCapacity = not ignoreCapacity
		revalidateNpcTradeQuantity()
		saveNpcModalSettings()
	end)
	menu:addSeparator()
	menu:addCheckBox(tr("Sell equipped"), sellEquipped, function()
		sellEquipped = not sellEquipped
		refreshNpcTradeItemList()
		revalidateNpcTradeQuantity()
		saveNpcModalSettings()
	end)
	menu:addSeparator()
	menu:addCheckBox(tr("Show search field"), showSearchField, function()
		handleSearchField()
	end)
	menu:addCheckBox(tr("Do not show a warning when trading large amounts"), doNotShowWarningLargeAmounts, function()
		doNotShowWarningLargeAmounts = not doNotShowWarningLargeAmounts
		saveNpcModalSettings()
	end)
	menu:display()
	setWindowOpacity(1)
end

local function createSellAllItemBox(panel, itemId, amount, panelKind)
	if not panel or not itemId then
		return
	end

	local box = g_ui.createWidget("ItemBoxSell", panel)

	box.sellAllItemId = itemId
	box.sellAllAmount = amount
	box.sellAllPanelKind = panelKind

	local icon = box:recursiveGetChildById("itemsell")

	if not icon then
		return
	end

	icon:setItemId(itemId)
	if panelKind == "sell" then
		if icon.setShowCount then
			icon:setShowCount(true)
		end
		if icon.setDisplayCount then
			icon:setDisplayCount(amount)
		else
			icon:setItemCount(amount)
		end
	else
		if icon.setShowCount then
			icon:setShowCount(false)
		end
		if icon.clearDisplayCount then
			icon:clearDisplayCount()
		end
	end

	local thing = g_things.getThingType(itemId, ThingCategoryItem)
	if thing then
		box:setTooltip(thing:getName())
	end

	local border = box:recursiveGetChildById("ignoredBorder")
	local cross = box:recursiveGetChildById("ignoredCross")

	if panelKind == "sell" then
		if border then
			border:hide()
		end
		if cross then
			cross:hide()
		end

		local function onItemClick()
			if not box.sellAllItemId then
				return false
			end

			sellAllIgnoredItems[box.sellAllItemId] = true

			saveSellAllIgnoreList()
			addEvent(function()
				if sellAllModal and not sellAllModal:isDestroyed() then
					refreshSellAllModalLists()
				end
			end)

			return true
		end

		box.onClick = onItemClick
		box.onDoubleClick = onItemClick
		icon.onClick = onItemClick
		icon.onDoubleClick = onItemClick
	elseif panelKind == "ignore" then
		if border then
			border:show()
			border:raise()
		end
		if cross then
			cross:show()
			cross:raise()
		end

		local function onItemClick()
			if not box.sellAllItemId then
				return false
			end

			sellAllIgnoredItems[box.sellAllItemId] = false

			saveSellAllIgnoreList()
			addEvent(function()
				if sellAllModal and not sellAllModal:isDestroyed() then
					refreshSellAllModalLists()
				end
			end)

			return true
		end

		box.onClick = onItemClick
		box.onDoubleClick = onItemClick
		icon.onClick = onItemClick
		icon.onDoubleClick = onItemClick
	end
end

local lastSellAllSignature = ""
local sellAllAutoRefreshTimer = nil

stopSellAllAutoRefresh = function()
	if sellAllAutoRefreshTimer then
		removeEvent(sellAllAutoRefreshTimer)
		sellAllAutoRefreshTimer = nil
	end
end

scheduleSellAllAutoRefresh = function()
	stopSellAllAutoRefresh()
	if sellAllModal and sellAllModal:isVisible() then
		sellAllAutoRefreshTimer = scheduleEvent(function()
			if sellAllModal and sellAllModal:isVisible() then
				refreshSellAllModalLists()
				scheduleSellAllAutoRefresh()
			end
		end, 500)
	end
end

function refreshSellAllModalLists(force)
	if not sellAllModal or not sellAllModal:isVisible() then
		lastSellAllSignature = ""
		return
	end

	local sellItemsPanel = sellAllModal:recursiveGetChildById("npcSellItemsPanel")
	local ignorePanel = sellAllModal:recursiveGetChildById("npcIgnoreItemsPanel")

	if not sellItemsPanel or not ignorePanel then
		return
	end

	local tempSellAllItems = {}
	local sortedSellItems = {}
	local totalGoldToReceive = 0
	local sigParts = {}

	for _, entry in ipairs(SellNpcTradeItems or {}) do
		local itemId = entry.item:getId()
		local count = getSellablePlayerItemCount(itemId)
		if count > 0 and not sellAllIgnoredItems[itemId] then
			if not tempSellAllItems[itemId] then
				tempSellAllItems[itemId] = {
					id = itemId,
					count = count,
					price = entry.sellPrice or 0,
					name = entry.name or (entry.item and entry.item.getName and entry.item:getName()) or ""
				}
				table.insert(sortedSellItems, tempSellAllItems[itemId])
				totalGoldToReceive = totalGoldToReceive + ((entry.sellPrice or 0) * count)
				table.insert(sigParts, itemId .. ":" .. count)
			end
		end
	end

	table.sort(sortedSellItems, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	local sortedIgnored = {}
	for itemId, active in pairs(sellAllIgnoredItems) do
		if active == true then
			local thing = g_things.getThingType(itemId, ThingCategoryItem)
			local name = thing and thing:getName() or ("Item " .. itemId)
			table.insert(sortedIgnored, { id = itemId, name = name })
			table.insert(sigParts, "ign:" .. itemId)
		end
	end

	table.sort(sortedIgnored, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	local currentSig = table.concat(sigParts, "|") .. "|f2:" .. tostring(FilterText2 or "") .. "|f3:" .. tostring(FilterText3 or "")

	if not force and currentSig == lastSellAllSignature then
		local goldBalancePanel = sellAllModal:getChildById("goldBalancePanel")
		if goldBalancePanel then
			local goldBalanceValue = goldBalancePanel:getChildById("value")
			if goldBalanceValue then
				goldBalanceValue:setText(formatNumberWithCommas(totalGoldToReceive))
			end
		end
		return
	end

	lastSellAllSignature = currentSig

	sellItemsPanel:destroyChildren()
	ignorePanel:destroyChildren()

	for _, itemData in ipairs(sortedSellItems) do
		local itemName = itemData.name:lower()
		local filter2 = tostring(FilterText2 or ""):lower()

		if filter2 == "" or itemName:find(filter2, 1, true) then
			createSellAllItemBox(sellItemsPanel, itemData.id, itemData.count, "sell")
		end
	end

	for _, ign in ipairs(sortedIgnored) do
		local itemName = ign.name:lower()
		local filter3 = tostring(FilterText3 or ""):lower()

		if filter3 == "" or itemName:find(filter3, 1, true) then
			createSellAllItemBox(ignorePanel, ign.id, 0, "ignore")
		end
	end

	local goldBalancePanel = sellAllModal:getChildById("goldBalancePanel")
	if goldBalancePanel then
		local goldBalanceValue = goldBalancePanel:getChildById("value")
		if goldBalanceValue then
			goldBalanceValue:setText(formatNumberWithCommas(totalGoldToReceive))
		end
	end
end

function closeSellAllWindow()
	stopSellAllAutoRefresh()

	if sellAllModal then
		sellAllModal:hide()
	end

	if not mainNpcModal then
		return
	end

	mainNpcModal:show()
	mainNpcModal:raise()
	mainNpcModal:focus()

	if multiNpc then
		multiNpc:hide()
	end
	if npcOutfit then
		npcOutfit:show()
	end
	if npcNameLabel then
		npcNameLabel:show()
	end

	if npcModalTrade then
		showTradeWindowChildrens()
		refreshNpcTradeItemList()
		updateNpcTradePlayerBalanceLabel()
		revalidateNpcTradeQuantity()
	end

	setWindowOpacity(1)
end

function openSellAllWindow()
	if mainNpcModal then
		mainNpcModal:hide()
	end

	loadSellAllIgnoreList()
	FilterText2 = ""
	FilterText3 = ""
	if sellAllModal then
		local s2 = sellAllModal:recursiveGetChildById("search2")
		if s2 then s2:clearText() end
		local s3 = sellAllModal:recursiveGetChildById("search3")
		if s3 then s3:clearText() end
	end
	if sellAllModal then
		sellAllModal:show()
		sellAllModal:raise()
		sellAllModal:focus()
	end
	refreshSellAllModalLists(true)
	scheduleSellAllAutoRefresh()
end

function sendSellAll()
	if not SellNpcTradeItems or #SellNpcTradeItems == 0 then
		closeSellAllWindow()
		return
	end

	local itemsToSell = {}
	for _, entry in ipairs(SellNpcTradeItems) do
		local itemId = entry.item:getId()
		if not sellAllIgnoredItems[itemId] then
			local count = getSellablePlayerItemCount(itemId)
			if count > 0 then
				table.insert(itemsToSell, {
					item = entry.item,
					id = itemId,
					count = count,
					price = entry.sellPrice or 0
				})
			end
		end
	end

	if #itemsToSell == 0 then
		closeSellAllWindow()
		return
	end

	local maxAmountPerPacket = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
	local totalEarned = 0

	for _, sellData in ipairs(itemsToSell) do
		local rem = sellData.count
		while rem > 0 do
			local chunk = math.min(rem, maxAmountPerPacket)
			g_game.sellItem(sellData.item, chunk, not sellEquipped)
			rem = rem - chunk
		end

		if playerItems and playerItems[sellData.id] then
			playerItems[sellData.id] = math.max(0, playerItems[sellData.id] - sellData.count)
		end
		totalEarned = totalEarned + (sellData.price * sellData.count)
	end

	if npcTradePlayerMoney and isNpcTradeGoldCurrency() then
		npcTradePlayerMoney = npcTradePlayerMoney + totalEarned
	end

	closeSellAllWindow()
	updateNpcTradePlayerBalanceLabel()
	refreshNpcTradeItemList()
	revalidateNpcTradeQuantity()
end

function sellAll(delayed, exceptions)
	if type(delayed) == "table" then
		exceptions = delayed
		delayed = false
	end
	exceptions = exceptions or {}

	for _, entry in ipairs(SellNpcTradeItems or {}) do
		local itemId = entry.item:getId()
		if not table.find(exceptions, itemId) and not sellAllIgnoredItems[itemId] then
			local count = getSellablePlayerItemCount(itemId)
			if count > 0 then
				local maxAmount = math.min(count, 100)
				g_game.sellItem(entry.item, maxAmount, not sellEquipped)
				if playerItems and playerItems[itemId] then
					playerItems[itemId] = math.max(0, playerItems[itemId] - maxAmount)
				end
			end
		end
	end

	updateNpcTradePlayerBalanceLabel()
	refreshNpcTradeItemList()
	revalidateNpcTradeQuantity()
end

-- Compatibility wrappers for vBot and legacy modules
modules.game_npctrade = modules.game_npcmodal
modules.game_npcmodal.sellAll = sellAll
modules.game_npctrade.sellAll = sellAll

function isTrading(...)
	return npcModalTrade == true
end

function getSellItems(...)
	return SellNpcTradeItems or {}
end

function getBuyItems(...)
	return BuyNpcTradeItems or {}
end

function getSellQuantity(item)
	if not item then return 0 end
	local id = type(item) == "number" and item or (item.getId and item:getId()) or 0
	return getSellablePlayerItemCount(id)
end

function canTradeItem(item)
	if not item then return false end
	local id = type(item) == "number" and item or (item.getId and item:getId()) or 0
	return getSellablePlayerItemCount(id) > 0
end

function closeNpcTrade(...)
	return closeNpcModal()
end

function sellAll(...)
	return sendSellAll(...)
end

function inWhiteList(itemId)
	return sellAllIgnoredItems and sellAllIgnoredItems[itemId] ~= true
end

function addToWhitelist(itemId)
	if sellAllIgnoredItems then
		sellAllIgnoredItems[itemId] = false
		saveSellAllIgnoreList()
	end
end

function removeItemInList(itemId)
	if sellAllIgnoredItems then
		sellAllIgnoredItems[itemId] = true
		saveSellAllIgnoreList()
	end
end

_G.isTrading = isTrading
_G.getSellItems = getSellItems
_G.getBuyItems = getBuyItems
_G.getSellQuantity = getSellQuantity
_G.canTradeItem = canTradeItem
_G.closeNpcTrade = closeNpcTrade
_G.sellAll = sellAll
_G.inWhiteList = inWhiteList
_G.addToWhitelist = addToWhitelist
_G.removeItemInList = removeItemInList

