modalDialog = nil
lastDialogChoices = 0
lastDialogChoice = 0
lastDialogAnswer = 0

function isModalDialogOpen()
	return modalDialog ~= nil and not modalDialog:isDestroyed()
end

local function resolveModalButtons(buttons, enterButton, escapeButton)
	if not buttons or #buttons == 0 then
		return enterButton, escapeButton
	end

	local buttonExistsById = {}
	for i = 1, #buttons do
		buttonExistsById[buttons[i][1]] = true
	end

	local firstButtonId = buttons[1][1]
	local lastButtonId = buttons[#buttons][1]

	if not buttonExistsById[enterButton] then
		enterButton = firstButtonId
	end

	if not buttonExistsById[escapeButton] then
		escapeButton = #buttons > 1 and lastButtonId or enterButton
	end

	if enterButton == escapeButton and #buttons > 1 then
		for i = #buttons, 1, -1 do
			local candidateId = buttons[i][1]
			if candidateId ~= enterButton then
				escapeButton = candidateId
				break
			end
		end
	end

	return enterButton, escapeButton
end

local function normalizeButtonText(text)
	if type(text) ~= "string" then
		return ""
	end
	return text:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function isAffirmativeButtonLabel(text)
	local t = normalizeButtonText(text)
	if t == "" then
		return false
	end
	if t == "yes" or t == "ok" or t == "accept" or t == "confirm" or t == "select"
		or t == "si" or t == "sí" or t == "elegir" or t == "seleccionar" or t == "aceptar" then
		return true
	end
	return t:find("choose", 1, true) ~= nil or t:find("select", 1, true) ~= nil
end

local function isNegativeButtonLabel(text)
	local t = normalizeButtonText(text)
	if t == "" then
		return false
	end
	if t == "no" or t == "cancel" or t == "cancelar" then
		return true
	end
	return t:find("cancel", 1, true) ~= nil
end

local function buttonTextById(buttons, buttonId)
	for i = 1, #buttons do
		if buttons[i][1] == buttonId then
			return buttons[i][2]
		end
	end
end

local function findButtonIdByLabel(buttons, predicate)
	for i = 1, #buttons do
		if predicate(buttons[i][2]) then
			return buttons[i][1]
		end
	end
end

local function resolveEnterEscapeButtonIds(buttons, serverEnter, serverCancel)
	if not buttons or #buttons == 0 then
		return serverEnter, serverCancel
	end

	local enterId = findButtonIdByLabel(buttons, isAffirmativeButtonLabel)
	local escapeId = findButtonIdByLabel(buttons, isNegativeButtonLabel)

	local function serverButtonExists(buttonId)
		for i = 1, #buttons do
			if buttons[i][1] == buttonId then
				return true
			end
		end
		return false
	end

	if not enterId and serverEnter and serverButtonExists(serverEnter) then
		local label = buttonTextById(buttons, serverEnter)
		if not isNegativeButtonLabel(label) then
			enterId = serverEnter
		end
	end

	if not escapeId and serverCancel and serverButtonExists(serverCancel) then
		local label = buttonTextById(buttons, serverCancel)
		if not isAffirmativeButtonLabel(label) then
			escapeId = serverCancel
		end
	end

	enterId = enterId or buttons[1][1]
	escapeId = escapeId or buttons[#buttons][1]

	if enterId == escapeId and #buttons > 1 then
		for i = 1, #buttons do
			local candidate = buttons[i][1]
			if candidate ~= enterId then
				escapeId = candidate
				break
			end
		end
	end

	return enterId, escapeId
end

function init()
	g_ui.importStyle("modaldialog")
	connect(g_game, {
		onModalDialog = onModalDialog,
		onGameEnd = destroyDialog
	})

	local dialog = rootWidget:recursiveGetChildById("modalDialog")
	if dialog then
		modalDialog = dialog
	end
end

function terminate()
	if g_client and g_client.setInputLockWidget then
		g_client.setInputLockWidget(nil)
	end

	disconnect(g_game, {
		onModalDialog = onModalDialog,
		onGameEnd = destroyDialog
	})

	if modalDialog then
		modalDialog:destroy()
		modalDialog = nil
	end
end

local function unbindModalDialogKeys()
	if not modalDialog or modalDialog:isDestroyed() then
		return
	end

	if modalDialog._boundEnter then
		g_keyboard.unbindKeyDown("Enter", modalDialog._boundEnter, modalDialog)
		modalDialog._boundEnter = nil
	end
	if modalDialog._boundEscape then
		g_keyboard.unbindKeyDown("Escape", modalDialog._boundEscape, modalDialog)
		modalDialog._boundEscape = nil
	end
end

function destroyDialog()
	unbindModalDialogKeys()

	if g_client and g_client.setInputLockWidget then
		g_client.setInputLockWidget(nil)
	end

	if modalDialog then
		modalDialog:destroy()
		modalDialog = nil
	end
end

function onModalDialog(id, title, message, buttons, enterButton, escapeButton, choices, priority)
	if modalDialog then
		return
	end

	enterButton, escapeButton = resolveModalButtons(buttons, enterButton, escapeButton)
	local enterButtonId, escapeButtonId = resolveEnterEscapeButtonIds(buttons, enterButton, escapeButton)

	modalDialog = g_ui.createWidget("ModalDialog", rootWidget)

	if g_client and g_client.setInputLockWidget then
		g_client.setInputLockWidget(modalDialog)
	end

	local messageLabel = modalDialog:getChildById("messageLabel")
	local choiceList = modalDialog:getChildById("choiceList")
	local choiceScrollbar = modalDialog:getChildById("choiceScrollBar")
	local buttonsPanel = modalDialog:getChildById("buttonsPanel")

	modalDialog:setText(title)
	messageLabel:setText(message)

	if messageLabel.setFont then
		messageLabel:setFont("Verdana Bold-11px-new")
	end

	local labelHeight
	local useZebra = #choices >= 2

	for i = 1, #choices do
		local choiceId = choices[i][1]
		local choiceName = choices[i][2]
		local labelStyle = (not useZebra or i % 2 == 1) and "ChoiceListLabelOdd" or "ChoiceListLabelEven"
		local label = g_ui.createWidget(labelStyle, choiceList)

		label.choiceId = choiceId
		label:setText(short_text(choiceName, 28))
		if #choiceName > 28 then
			label:setTooltip(choiceName)
		end
		label:setPhantom(false)
		labelHeight = labelHeight or label:getHeight()
	end

	if #choices > 0 then
		choiceList:focusChild(choiceList:getFirstChild())
	end

	for i = 1, #buttons do
		local buttonId = buttons[i][1]

		local button = g_ui.createWidget("ModalButton", buttonsPanel)
		button:setText(buttons[i][2])
		button.onClick = function()
			local focusedChoice = choiceList:getFocusedChild()
			local choice = 0xFF
			if focusedChoice then
				choice = focusedChoice.choiceId
				lastDialogChoice = choiceList:getChildIndex(focusedChoice)
				lastDialogAnswer = g_clock.millis()
			end
			g_game.answerModalDialog(id, buttonId, choice)
			destroyDialog()
		end
	end

	local choiceSeparator = modalDialog:getChildById("choiceSeparator")
	local additionalHeight = 0
	local listSeparatorGap = 0
	local visibleRows = 0
	local hasChoices = #choices > 0

	if hasChoices then
		choiceList:setVisible(true)
		choiceScrollbar:setVisible(true)

		visibleRows = math.min(modalDialog.maximumChoices, math.max(modalDialog.minimumChoices, #choices))
		listSeparatorGap = choiceList:getMarginBottom()

		local listContentHeight = visibleRows * labelHeight + choiceList:getPaddingTop() + choiceList:getPaddingBottom()

		choiceList:setHeight(listContentHeight)
		choiceList:setMarginBottom(0)
		if choiceSeparator then
			choiceSeparator:breakAnchors()
			choiceSeparator:addAnchor(AnchorTop, "choiceList", AnchorBottom)
			choiceSeparator:setMarginTop(listSeparatorGap)
			choiceSeparator:setHeight(2)
			choiceSeparator:setFixedSize(true)
			choiceSeparator:addAnchor(AnchorLeft, "parent", AnchorLeft)
			choiceSeparator:addAnchor(AnchorRight, "parent", AnchorRight)
		end

		additionalHeight = choiceList:getMarginTop() + listContentHeight + listSeparatorGap
	end

	modalDialog:setWidth(modalDialog.maximumWidth)

	if messageLabel.resizeToText then
		messageLabel:resizeToText()
	end

	local messageHeight = math.max(14, messageLabel:getTextSize().height)
	local paddingTop = modalDialog:getPaddingTop()
	local paddingBottom = modalDialog:getPaddingBottom()
	local buttonsHeight = buttonsPanel:getHeight()
	local separatorBlock = hasChoices and 22 - listSeparatorGap or 22
	local modalHeight = paddingTop + messageHeight + 4 + separatorBlock + buttonsHeight + paddingBottom + additionalHeight

	if hasChoices and visibleRows > modalDialog.minimumChoices then
		modalHeight = modalHeight - 1
	end

	modalDialog:setHeight(math.max(100, modalHeight))

	local answered = false

	local function currentChoiceId()
		local focusedChoice = choiceList:getFocusedChild()
		if not focusedChoice and hasChoices then
			focusedChoice = choiceList:getFirstChild()
			if focusedChoice then
				choiceList:focusChild(focusedChoice, KeyboardFocusReason)
			end
		end
		if focusedChoice then
			return focusedChoice.choiceId
		end
		return 0xFF
	end

	local function answer(buttonId, choice)
		if answered then
			return
		end
		answered = true

		local focusedChoice = choiceList:getFocusedChild()
		if focusedChoice and choice ~= 255 and choice ~= 0xFF then
			lastDialogChoice = choiceList:getChildIndex(focusedChoice)
			lastDialogAnswer = g_clock.millis()
		end

		g_game.answerModalDialog(id, buttonId, choice)
		destroyDialog()
	end

	local function enterFunc()
		answer(enterButtonId, currentChoiceId())
	end

	local function escapeFunc()
		answer(escapeButtonId, 0xFF)
	end

	choiceList.onDoubleClick = enterFunc
	modalDialog.onEnter = enterFunc
	modalDialog.onEscape = escapeFunc

	function modalDialog:onKeyPress(keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardNoModifier then
			return false
		end

		if g_keyboard.isEnterKey(keyCode) then
			enterFunc()
			return true
		elseif keyCode == KeyEscape then
			escapeFunc()
			return true
		elseif keyCode == KeyDown and hasChoices then
			choiceList:focusNextChild(KeyboardFocusReason)
			return true
		elseif keyCode == KeyUp and hasChoices then
			choiceList:focusPreviousChild(KeyboardFocusReason)
			return true
		end

		return false
	end

	function choiceList:onKeyPress(keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardNoModifier then
			return false
		end

		if g_keyboard.isEnterKey(keyCode) then
			enterFunc()
			return true
		elseif keyCode == KeyEscape then
			escapeFunc()
			return true
		end

		return false
	end

	modalDialog._boundEnter = enterFunc
	modalDialog._boundEscape = escapeFunc
	g_keyboard.bindKeyDown("Enter", modalDialog._boundEnter, modalDialog)
	g_keyboard.bindKeyDown("Escape", modalDialog._boundEscape, modalDialog)

	lastDialogChoices = #choices

	modalDialog:raise()
	modalDialog:show()
	modalDialog:focus()
	modalDialog:grabKeyboard()

	if hasChoices then
		local first = choiceList:getFirstChild()
		if first then
			choiceList:focusChild(first, KeyboardFocusReason)
		end
	end
end
