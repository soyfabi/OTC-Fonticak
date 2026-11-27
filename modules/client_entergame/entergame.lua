-- chunkname: @/client_entergame/entergame.lua

EnterGame = {}

local loadBox, enterGame, motdWindow, clientBox
local accountsPanel, savedAccountsDirty, saveAccountOnLogin, saveAccountPassword
local recordingsPanel, recordingDeleteBox
local accountUndoEvent
local accountContextMenu, accountRenameBox
local motdEnabled = true
local twoFactorWindow
local protocolLogin

local function safeDecrypt(text)
	if not text or text == "" then
		return ""
	end
	local ok, res = pcall(g_crypt.decrypt, text)
	return ok and res or text
end

local SAVED_ACCOUNTS_SETTING = "login-saved-accounts"
local PINNED_ACCOUNT_SETTING = "login-pinned-account"

local function splitSavedAccount(entry)
	-- Existing entries have two base64 fields. The alias is an optional third field.
	return entry:match("^([^|]+)|([^|]*)|?(.*)$")
end

local function buildSavedAccount(key, password, alias)
	local entry = key .. "|" .. password
	return alias and alias ~= "" and entry .. "|" .. alias or entry
end

local function removeSavedAccount(entries, key)
	local removedEntry, removedIndex
	for index = #entries, 1, -1 do
		if splitSavedAccount(entries[index]) == key then
			removedEntry = table.remove(entries, index)
			removedIndex = index
		end
	end
	return removedEntry, removedIndex
end

local function clearAccountUndo()
	removeEvent(accountUndoEvent)
	accountUndoEvent = nil
	local bar = accountsPanel:getChildById("accountUndoBar")
	local button = bar:getChildById("undo")
	button:setTooltip(nil)
	button.onClick = nil
	bar:setHeight(1)
	bar:hide()
end

local function showAccountUndo(name, restore)
	removeEvent(accountUndoEvent)
	local bar = accountsPanel:getChildById("accountUndoBar")
	local button = bar:getChildById("undo")
	button:setTooltip(tr("Restore %s", name))
	button.onClick = function()
		clearAccountUndo()
		restore()
	end
	bar:setHeight(24)
	bar:show()
	accountUndoEvent = scheduleEvent(clearAccountUndo, 6000)
end

local function setSavedAccountAlias(key, alias)
	local entries = g_settings.getList(SAVED_ACCOUNTS_SETTING)
	for index, entry in ipairs(entries) do
		local entryKey, password = splitSavedAccount(entry)
		if entryKey == key then
			local encryptedAlias = alias ~= "" and g_crypt.encrypt(alias) or ""
			entries[index] = buildSavedAccount(key, password, encryptedAlias)
			g_settings.setList(SAVED_ACCOUNTS_SETTING, entries)
			g_settings.save()
			return true
		end
	end
	return false
end

local function setAccountRenameAction(action, name)
	local button = accountsPanel:getChildById("renameAccount")
	if not action and not button:isExplicitlyVisible() then
		return
	end

	button.onClick = action
	button:setTooltip(action and tr("Rename %s", name) or nil)
	button:setWidth(action and 46 or 1)
	button:setVisible(action ~= nil)
end

local function saveLoginAccount()
	if not saveAccountOnLogin or not G.account or G.account == "" then
		return
	end

	local entries = g_settings.getList(SAVED_ACCOUNTS_SETTING)
	local key = g_crypt.encrypt(G.account)
	local password = saveAccountPassword and G.password and G.password ~= "" and g_crypt.encrypt(G.password) or ""
	local previousEntry = removeSavedAccount(entries, key)
	local _, _, alias = splitSavedAccount(previousEntry or "")
	table.insert(entries, 1, buildSavedAccount(key, password, alias))
	g_settings.setList(SAVED_ACCOUNTS_SETTING, entries)
	savedAccountsDirty = true
	saveAccountOnLogin = false
end

local function updateAccountPin(row, pinned)
	local button = row:getChildById("pin")
	button:setOn(pinned)
	button:setTooltip(pinned and tr("Unpin account") or tr("Pin account"))
end

local function restoreAccountRowOrder(list, row)
	local index = 1
	for _, other in ipairs(list:getChildren()) do
		if other.savedAccountOrder < row.savedAccountOrder then
			index = index + 1
		end
	end
	list:moveChildToIndex(row, index)
end

local function refreshSavedAccounts()
	if not savedAccountsDirty then
		return
	end

	local list = accountsPanel:getChildById("accountList")
	local emptyLabel = accountsPanel:getChildById("emptyAccounts")
	local pinnedKey = g_settings.get(PINNED_ACCOUNT_SETTING)
	local encryptedEmptyPassword = g_crypt.encrypt("")
	local pinnedRow
	setAccountRenameAction(nil)
	list:destroyChildren()

	for index, entry in ipairs(g_settings.getList(SAVED_ACCOUNTS_SETTING)) do
		local key, encryptedPassword, encryptedAlias = splitSavedAccount(entry)
		local name = key and g_crypt.decrypt(key) or ""
		if name ~= "" then
			local alias = encryptedAlias ~= "" and g_crypt.decrypt(encryptedAlias) or ""
			local row = g_ui.createWidget("SavedAccountRow", list)
			row.savedAccountOrder = index
			local account = row:getChildById("account")
			local pin = row:getChildById("pin")
			row:getChildById("passwordSaved"):setVisible(encryptedPassword ~= "" and encryptedPassword ~= encryptedEmptyPassword)
			if not pinnedRow and key == pinnedKey then
				pinnedRow = row
			end
			updateAccountPin(row, pinnedRow == row)
			pin.onClick = function()
				local previous = pinnedRow
				if previous then
					updateAccountPin(previous, false)
					restoreAccountRowOrder(list, previous)
				end
				if previous == row then
					pinnedRow = nil
					g_settings.remove(PINNED_ACCOUNT_SETTING)
				else
					pinnedRow = row
					updateAccountPin(row, true)
					list:moveChildToIndex(row, 1)
					g_settings.set(PINNED_ACCOUNT_SETTING, key)
					local scrollbar = accountsPanel:getChildById("accountScroll")
					scrollbar:setValue(scrollbar:getMinimum())
				end
				g_settings.save()
			end
			local displayName
			local function updateAccountLabel()
				displayName = alias ~= "" and alias or name
				account:setText(displayName)
				account:setTooltip(alias ~= "" and alias .. "\n" .. name or name)
			end
			updateAccountLabel()
			local function renameAccount()
				if accountRenameBox and not accountRenameBox:isDestroyed() then
					accountRenameBox:destroy()
				end
				accountRenameBox = displayInputBox(tr("Rename Account"), tr("Alias (optional):"), function(text)
					local newAlias = text:match("^%s*(.-)%s*$")
					if newAlias == alias or not setSavedAccountAlias(key, newAlias) then
						return
					end
					if row:isDestroyed() then
						savedAccountsDirty = true
						refreshSavedAccounts()
						return
					end
					alias = newAlias
					updateAccountLabel()
					if accountsPanel:getChildById("renameAccount").onClick == renameAccount then
						setAccountRenameAction(renameAccount, displayName)
					end
				end, nil, alias, 40)
			end
			connect(account, {
				onHoverChange = function(_, hovered)
					if hovered then
						setAccountRenameAction(renameAccount, displayName)
					end
				end
			})
			local releaseAccountButton = account.onMouseRelease
			account.onMouseRelease = function(widget, pos, button)
				if button ~= MouseRightButton or not widget:containsPoint(pos) then
					return releaseAccountButton(widget, pos, button)
				end

				local menu = g_ui.createWidget("PopupMenu")
				accountContextMenu = menu
				menu:addOption(tr("Rename"), renameAccount)
				menu:display(pos)
				return true
			end
			account.onClick = function()
				local nameEdit = enterGame:getChildById("accountNameTextEdit")
				local passwordEdit = enterGame:getChildById("accountPasswordTextEdit")
				nameEdit:setText(name)
				passwordEdit:setText(g_crypt.decrypt(encryptedPassword))
				passwordEdit:setCursorPos(-1)
				accountsPanel:hide()
				enterGame:focus()
				passwordEdit:focus()
			end
			row:getChildById("remove").onClick = function()
				local entries = g_settings.getList(SAVED_ACCOUNTS_SETTING)
				local removed, index = removeSavedAccount(entries, key)
				if not removed then
					return
				end
				g_settings.setList(SAVED_ACCOUNTS_SETTING, entries)
				local wasPinned = pinnedRow == row
				if wasPinned then
					pinnedRow = nil
					g_settings.remove(PINNED_ACCOUNT_SETTING)
				end
				g_settings.save()
				setAccountRenameAction(nil)
				row:destroy()
				emptyLabel:setVisible(list:getChildCount() == 0)

				showAccountUndo(displayName, function()
					local current = g_settings.getList(SAVED_ACCOUNTS_SETTING)
					for _, currentEntry in ipairs(current) do
						if splitSavedAccount(currentEntry) == key then
							return
						end
					end
					table.insert(current, math.min(index, #current + 1), removed)
					g_settings.setList(SAVED_ACCOUNTS_SETTING, current)
					if wasPinned and not g_settings.exists(PINNED_ACCOUNT_SETTING) then
						g_settings.set(PINNED_ACCOUNT_SETTING, key)
					end
					g_settings.save()
					savedAccountsDirty = true
					refreshSavedAccounts()
				end)
			end
		end
	end

	if pinnedRow then
		list:moveChildToIndex(pinnedRow, 1)
	end
	emptyLabel:setVisible(list:getChildCount() == 0)
	savedAccountsDirty = false
end

local function positionAccountsPanel()
	local parent = enterGame:getParent()
	local tab = enterGame:getChildById("accountsToggle")
	local right = parent:getX() + parent:getWidth() - 6
	local x = tab:getX() + tab:getWidth() + 4
	local y = enterGame:getY() + math.floor((enterGame:getHeight() - accountsPanel:getHeight()) / 2)
	local width = math.max(140, math.min(216, right - x))
	accountsPanel:setWidth(width)
	accountsPanel:setPosition({ x = math.min(x, right - width), y = y })
end

function EnterGame.showAccounts()
	if not accountsPanel or accountsPanel:isVisible() then
		return
	end

	positionAccountsPanel()
	local target = accountsPanel:getPosition()
	accountsPanel:setPosition({ x = target.x - 22, y = target.y })
	refreshSavedAccounts()
	g_effects.fadeIn(accountsPanel, 150)
	accountsPanel:show()
	accountsPanel:raise()
	enterGame:raise()
	g_effects.moveTo(accountsPanel, target, 150)
end

local clipFormats = { mp4 = true, mkv = true, avi = true }
local recordingsOnWindows = g_platform.getOSName() == "Windows"

local function trimDirectory(path)
	return path:gsub("\\", "/"):gsub("/+$", "")
end

local function isSavedClip(path, writeDir)
	return g_resources.fileExists(path) and trimDirectory(g_resources.getRealDir(path)) == writeDir
end

local function closeRecordingDeleteBox()
	if recordingDeleteBox then
		recordingDeleteBox:destroy()
		recordingDeleteBox = nil
	end
end

local function confirmDeleteClip(clip, writeDir, refresh)
	if recordingDeleteBox then
		return
	end

	local title = tr("Delete clip")
	local function remove()
		closeRecordingDeleteBox()
		if isSavedClip(clip.path, writeDir) and not g_resources.deleteFile(clip.path) then
			displayErrorBox(title, tr("Could not delete the clip."))
		end
		refresh()
	end
	recordingDeleteBox = displayGeneralBox(title, tr("Permanently delete this clip?") .. "\n" .. clip.name, {
		{ text = tr("Cancel"), callback = closeRecordingDeleteBox },
		{ text = tr("Delete"), callback = remove },
		anchor = AnchorHorizontalCenter
	}, nil, closeRecordingDeleteBox)
end

local function refreshRecordings()
	local list = recordingsPanel:getChildById("clipList")
	local writeDir = trimDirectory(g_resources.getWriteDir())
	local clips = {}
	if writeDir ~= "" and g_resources.directoryExists("/recordings") then
		for _, file in ipairs(g_resources.listDirectoryFiles("/recordings")) do
			local format = file:lower():match("%.([a-z0-9]+)$")
			local path = "/recordings/" .. file
			if clipFormats[format] and not file:find('[/"\\%c]') and isSavedClip(path, writeDir) then
				local created = g_resources.getFileCreationTime and g_resources.getFileCreationTime(path) or 0
				local timestamp = created
				if timestamp == 0 then
					local modified = g_resources.getFileTime(path)
					timestamp = recordingsOnWindows and math.floor(modified / 10000000 - 11644473600) or modified
				end
				clips[#clips + 1] = { name = file, path = path, format = format, created = created > 0, timestamp = timestamp }
			end
		end
	end
	table.sort(clips, function(a, b)
		if a.timestamp == b.timestamp then
			return a.name < b.name
		end
		return a.timestamp > b.timestamp
	end)

	local previous = recordingsPanel.clips
	if previous and #previous == #clips then
		local changed = false
		for index, clip in ipairs(clips) do
			local old = previous[index]
			if clip.path ~= old.path or clip.created ~= old.created or clip.timestamp ~= old.timestamp then
				changed = true
				break
			end
		end
		if not changed then
			return
		end
	end

	recordingsPanel.clips = clips
	list:destroyChildren()
	recordingsPanel:getChildById("emptyClips"):setVisible(#clips == 0)
	for _, clip in ipairs(clips) do
		local row = g_ui.createWidget("RecordingClipRow", list)
		local entry = row:getChildById("clip")
		local date = clip.timestamp > 0 and os.date("%m/%d/%Y", clip.timestamp)
		entry:setText(date and (clip.format:upper() .. " " .. date) or clip.name)
		local tooltip = clip.name
		if date then
			local dateTime = os.date("%m/%d/%Y %H:%M:%S", clip.timestamp)
			tooltip = tooltip .. "\n" .. (clip.created and tr("Created: %s", dateTime) or tr("Modified: %s", dateTime))
		end
		entry:setTooltip(recordingsOnWindows and (tooltip .. "\n" .. tr("Show in folder")) or tooltip)
		row:getChildById("remove").onClick = function()
			confirmDeleteClip(clip, writeDir, refreshRecordings)
		end
		if recordingsOnWindows then
			entry.onClick = function()
				local path = (writeDir .. "/recordings/" .. clip.name):gsub("/", "\\")
				if not g_platform.openDir('/select,"' .. path .. '"', true) then
					modules.client_options.openRecordingFolder()
				end
			end
		end
	end
end

local function positionRecordingsPanel()
	local parent = enterGame:getParent()
	local tab = enterGame:getChildById("recordingsToggle")
	local left = parent:getX() + 6
	local right = tab:getX() - 4
	local width = math.max(170, math.min(222, right - left))
	local y = enterGame:getY() + math.floor((enterGame:getHeight() - recordingsPanel:getHeight()) / 2)
	recordingsPanel:setWidth(width)
	recordingsPanel:setPosition({ x = math.max(left, right - width), y = y })
end

function EnterGame.showRecordings()
	if not recordingsPanel or recordingsPanel:isVisible() or not enterGame:isVisible() then
		return
	end

	positionRecordingsPanel()
	local target = recordingsPanel:getPosition()
	refreshRecordings()
	recordingsPanel:setPosition({ x = target.x + 22, y = target.y })
	g_effects.fadeIn(recordingsPanel, 150)
	recordingsPanel:show()
	recordingsPanel:raise()
	enterGame:raise()
	g_effects.moveTo(recordingsPanel, target, 150, positionRecordingsPanel)
end

local user32 = nil
local okFfi, ffiMod = pcall(require, "ffi")
if okFfi and ffiMod then
	pcall(function()
		ffiMod.cdef[[
			short GetKeyState(int nVirtKey);
		]]
		user32 = ffiMod.load("user32")
	end)
end

local capsLockActive = false
local REMEMBER_EMAIL_MARGIN = 10
local REMEMBER_EMAIL_MARGIN_CAPS = 28
local CAPS_LOCK_EXTRA_HEIGHT = REMEMBER_EMAIL_MARGIN_CAPS - REMEMBER_EMAIL_MARGIN

local function isSystemCapsLockActive()
	if user32 and user32.GetKeyState then
		local success, state = pcall(user32.GetKeyState, 0x14)
		if success and state then
			return bit.band(state, 1) ~= 0
		end
	end
	return nil
end

local function updateCapsLockWarning(forceState)
	if not enterGame then
		return
	end

	local warning = enterGame:getChildById("capsLockWarning")
	local rememberEmailBox = enterGame:getChildById("rememberEmailBox")
	if not warning then
		return
	end

	local passwordEdit = enterGame:getChildById("accountPasswordTextEdit")
	local showWarning = false

	if passwordEdit and passwordEdit:isFocused() then
		local sys = isSystemCapsLockActive()
		if forceState ~= nil then
			capsLockActive = forceState
		elseif sys ~= nil then
			capsLockActive = sys
		end
		showWarning = capsLockActive
	end

	warning:setVisible(showWarning)

	if rememberEmailBox then
		rememberEmailBox:setMarginTop(showWarning and REMEMBER_EMAIL_MARGIN_CAPS or REMEMBER_EMAIL_MARGIN)
	end

	local baseHeight = enterGame.baseHeight or 246
	enterGame:setHeight(showWarning and (baseHeight + CAPS_LOCK_EXTRA_HEIGHT) or baseHeight)
end


local function buildLoginBody(token)
	local body = {
		stayloggedin = true,
		type = "login",
		email = G.account,
		password = G.password
	}

	if token and token:len() > 0 then
		body.token = token
	end

	return body
end

local function buildLoginUrl(useHttps)
	local scheme = useHttps and "https" or "http"

	return string.format("%s://%s:%d%s", scheme, G.loginHost, G.port, G.loginPath)
end

local function parseHttpLoginHost(hostString)
	if not hostString or hostString == "" then
		return nil, nil
	end

	hostString = hostString:gsub("^%a+://", "")

	local host, pathPart = hostString:match("^([^/]+)(.*)$")
	if not host or host == "" then
		return nil, nil
	end

	local path = pathPart or ""
	if path ~= "" and path:sub(1, 1) ~= "/" then
		path = "/" .. path
	end

	return host, path
end

local function abortHttpLogin(message)
	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	local errorBox = displayErrorBox(tr("Login Error"), message)

	connect(errorBox, {
		onOk = EnterGame.show
	})
end

local function sendHttpLoginRequest(httpLogin, token, useHttps)
	local requestId = G.requestId
	local url = buildLoginUrl(useHttps)

	G.httpOperationId = HTTP.postJSON(url, buildLoginBody(token), function(data, err)
		if G.requestId ~= requestId then
			return
		end

		EnterGame.handleHttpLoginResponse(data, err, requestId)
	end)
end

local function onError(protocol, message, errorCode)
	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	local errorBox = displayErrorBox(tr("Sorry"), message)

	connect(errorBox, {
		onOk = EnterGame.show
	})
end

local function onMotd(protocol, motd)
	G.motdNumber = tonumber(motd:sub(0, motd:find("\n")))
	G.motdMessage = motd:sub(motd:find("\n") + 1, #motd)
end

local function onSessionKey(protocol, sessionKey)
	G.sessionKey = sessionKey
end

local function onCharacterList(protocol, characters, account, otui)
	local httpLogin = false
	if Servers_init and next(Servers_init) ~= nil then
		local hostInit, valuesInit = next(Servers_init)
		httpLogin = valuesInit and valuesInit.httpLogin or false
	end

	g_settings.set("httpLogin", httpLogin)

	saveLoginAccount()
	EnterGame.saveRememberedCredentials(true)

	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	for _, characterInfo in pairs(characters) do
		if characterInfo.previewState and characterInfo.previewState ~= PreviewState.Default then
			characterInfo.worldName = characterInfo.worldName .. ", Preview"
		end
	end

	CharacterList.create(characters, account, otui)
	CharacterList.show()

	if motdEnabled then
		local lastMotdNumber = g_settings.getNumber("motd")

		if G.motdNumber and G.motdNumber ~= lastMotdNumber then
			g_settings.set("motd", G.motdNumber)

			motdWindow = displayInfoBox(tr("Message of the day"), G.motdMessage)

			connect(motdWindow, {
				onOk = function()
					CharacterList.show()

					motdWindow = nil
				end
			})
			CharacterList.hide()
		end
	end
end

local function onUpdateNeeded(protocol, signature)
	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	if EnterGame.updateFunc then
		local continueFunc = EnterGame.show
		local cancelFunc = EnterGame.show

		EnterGame.updateFunc(signature, continueFunc, cancelFunc)
	else
		local errorBox = displayErrorBox(tr("Update needed"), tr("Your client needs updating, try redownloading it."))

		connect(errorBox, {
			onOk = EnterGame.show
		})
	end
end

local ENTER_GAME_LABEL_COLOR = "#c0c0c0"
local ENTER_GAME_LABEL_HIGHLIGHT = "#ffffff"

local function setEnterGameTextHighlight(widget, highlight)
	if widget and not widget:isDestroyed() then
		widget:setColor(highlight and ENTER_GAME_LABEL_HIGHLIGHT or ENTER_GAME_LABEL_COLOR)
	end
end

local function setupEnterGameHighlights()
	if not enterGame then
		return
	end

	local function bindLabelHighlight(label, triggers)
		if not label then
			return
		end

		local hoverCount = 0
		local focusCount = 0

		local function refresh()
			setEnterGameTextHighlight(label, hoverCount > 0 or focusCount > 0)
		end

		for _, widget in ipairs(triggers) do
			if widget then
				local originalHover = widget.onHoverChange
				widget.onHoverChange = function(w, hovered)
					if originalHover then
						originalHover(w, hovered)
					end
					if hovered then
						hoverCount = hoverCount + 1
					else
						hoverCount = math.max(0, hoverCount - 1)
					end
					refresh()
				end

				local originalFocus = widget.onFocusChange
				widget.onFocusChange = function(w, focused)
					if originalFocus then
						originalFocus(w, focused)
					end
					if focused then
						focusCount = focusCount + 1
					else
						focusCount = math.max(0, focusCount - 1)
					end
					refresh()
				end
			end
		end
	end

	local function bindWidgetHighlight(widget, label)
		label = label or widget
		if not widget then
			return
		end

		local originalHover = widget.onHoverChange
		widget.onHoverChange = function(w, hovered)
			if originalHover then
				originalHover(w, hovered)
			end
			setEnterGameTextHighlight(label, hovered)
		end
	end

	bindLabelHighlight(enterGame:getChildById("emailLabel"), {
		enterGame:getChildById("accountNameTextEdit"),
		enterGame:getChildById("accountEmailVisibilityBox")
	})

	bindLabelHighlight(enterGame:getChildById("passwordLabel"), {
		enterGame:getChildById("accountPasswordTextEdit"),
		enterGame:getChildById("accountPasswordVisibilityBox")
	})

	bindWidgetHighlight(enterGame:getChildById("rememberEmailBox"))
	bindWidgetHighlight(enterGame:getChildById("rememberPasswordBox"))

	local forgotPassword = enterGame:getChildById("Forgot_password_email")
	if forgotPassword then
		bindWidgetHighlight(forgotPassword, forgotPassword:getChildById("forgotPasswordLabel"))
	end

	local loginWithGoogle = enterGame:getChildById("btnLoginWithGoogle")
	if loginWithGoogle then
		local googleLoginLabel = loginWithGoogle:recursiveGetChildById("googleLoginLabel")
		local googleLoginIcon = loginWithGoogle:recursiveGetChildById("googleLoginIcon")
		bindLabelHighlight(googleLoginLabel, {
			loginWithGoogle,
			googleLoginIcon,
			googleLoginLabel
		})
	end
end

local function updateLabelText()
	enterGame:setText("Journey Onwards")
	enterGame:getChildById("emailLabel"):setText(tr("Email/Acc. Name:"))
	enterGame:getChildById("rememberEmailBox"):setText(tr("Remember Email/Acc. Name"))
end

local function setupAccountsPanel()
	local accountsHoverEvent
	local keyboardMousePosition
	local selectedAccountRow
	savedAccountsDirty = true
	accountsPanel = g_ui.createWidget("EnterGameAccounts", enterGame:getParent())
	local accountsTab = enterGame:getChildById("accountsToggle")
	local list = accountsPanel:getChildById("accountList")
	local accountsTabLabel = accountsTab:getChildById("accountTabLabel")
	local accountsTabArrow = accountsTab:getChildById("accountTabArrow")
	accountsTabLabel:setFont(enterGame:getFont())
	accountsTabLabel:setColor(enterGame:getColor())
	local function updateTabHighlight()
		local active = accountsTab:isHovered() or accountsTab:isFocused()
		accountsTabLabel:setColor(active and "#dedede" or enterGame:getColor())
	end

	local function selectAccountRow(row)
		if selectedAccountRow == row then
			return
		end
		if selectedAccountRow and not selectedAccountRow:isDestroyed() then
			selectedAccountRow:getChildById("account"):setOn(false)
		end
		selectedAccountRow = row
		if row then
			row:getChildById("account"):setOn(true)
			list:ensureChildVisible(row)
		end
	end

	accountsTab.onKeyPress = function(_, keyCode, modifiers, repeatTicks)
		if keyCode == KeyTab and (modifiers == KeyboardNoModifier or modifiers == KeyboardShiftModifier) then
			local editId = modifiers == KeyboardShiftModifier and "accountPasswordTextEdit" or "accountNameTextEdit"
			enterGame:getChildById(editId):focus()
			return true
		end
		if keyCode == KeyEnter and modifiers == KeyboardNoModifier then
			if repeatTicks == 0 then
				EnterGame.showAccounts()
				keyboardMousePosition = g_window.getMousePosition()
				accountsPanel:focus()
				selectAccountRow(list:getChildByIndex(1))
			end
			return true
		end
	end

	accountsPanel.onKeyPress = function(panel, keyCode, modifiers, repeatTicks)
		if modifiers ~= KeyboardNoModifier then
			return false
		end
		local row = selectedAccountRow
		if row and row:isDestroyed() then
			row = nil
		end
		if keyCode == KeyEscape then
			panel:hide()
			enterGame:focus()
			accountsTab:focus()
			return true
		elseif keyCode == KeyEnter then
			if row and repeatTicks == 0 then
				row:getChildById("account"):onClick()
			end
			return true
		elseif keyCode == KeyUp or keyCode == KeyDown then
			keyboardMousePosition = g_window.getMousePosition()
			panel:focus()
			local count = list:getChildCount()
			if count > 0 then
				local step = keyCode == KeyUp and -1 or 1
				local index = row and list:getChildIndex(row) + step or 1
				selectAccountRow(list:getChildByIndex(math.max(1, math.min(count, index))))
			end
			return true
		end
		return false
	end

	connect(accountsTab, {
		onFocusChange = updateTabHighlight,
		onHoverChange = function(_, hovered)
			updateTabHighlight()
			if hovered then
				EnterGame.showAccounts()
			end
		end
	})
	connect(accountsPanel, {
		onVisibilityChange = function(panel, visible)
			accountsTabArrow:setOn(visible)
			if not visible then
				setAccountRenameAction(nil)
				if accountContextMenu and not accountContextMenu:isDestroyed() then
					accountContextMenu:destroy()
				end
				if accountRenameBox and not accountRenameBox:isDestroyed() then
					accountRenameBox:destroy()
				end
				accountContextMenu, accountRenameBox = nil, nil
				keyboardMousePosition = nil
				selectAccountRow(nil)
				removeEvent(accountsHoverEvent)
				accountsHoverEvent = nil
				g_effects.cancelMove(panel)
				g_effects.cancelFade(panel)
				return
			end

			accountsHoverEvent = cycleEvent(function()
				if panel.moveEvent
					or (accountContextMenu and not accountContextMenu:isDestroyed())
					or (accountRenameBox and not accountRenameBox:isDestroyed()) then
					return
				end

				local mouse = g_window.getMousePosition()
				if keyboardMousePosition then
					if panel:isFocused() and mouse.x == keyboardMousePosition.x and mouse.y == keyboardMousePosition.y then
						return
					end
					keyboardMousePosition = nil
					selectAccountRow(nil)
				end
				if panel:containsPoint(mouse) then
					return
				end
				setAccountRenameAction(nil)
				if accountsTab:containsPoint(mouse) then
					return
				end

				local between = mouse.x >= accountsTab:getX() + accountsTab:getWidth()
					and mouse.x < panel:getX()
					and mouse.y >= panel:getY()
					and mouse.y < panel:getY() + panel:getHeight()
				if not between then
					panel:hide()
				end
			end, 50)
		end
	})
	connect(enterGame, {
		onVisibilityChange = function(_, visible)
			if not visible and accountsPanel then
				accountsPanel:hide()
			end
		end,
		onGeometryChange = function()
			if accountsPanel and accountsPanel:isVisible() then
				g_effects.cancelMove(accountsPanel)
				positionAccountsPanel()
			end
		end
	})

	local loginOnKeyPress = enterGame.onKeyPress
	enterGame.onKeyPress = function(widget, keyCode, modifiers, repeatTicks)
		if accountsPanel and accountsPanel:isVisible()
			and (keyCode == KeyUp or keyCode == KeyDown or keyCode == KeyEscape)
			and accountsPanel:onKeyPress(keyCode, modifiers, repeatTicks) then
			return true
		end
		return loginOnKeyPress(widget, keyCode, modifiers, repeatTicks)
	end
end

local function setupRecordingsPanel()
	local hoverEvent
	local keyboardMousePosition
	recordingsPanel = g_ui.createWidget("EnterGameRecordings", enterGame:getParent())
	recordingsPanel:getChildById("openFolder"):setEnabled(recordingsOnWindows)
	local tab = enterGame:getChildById("recordingsToggle")
	local label = tab:getChildById("recordingsTabLabel")
	local arrow = tab:getChildById("recordingsTabArrow")
	label:setFont(enterGame:getFont())

	local function updateHighlight()
		label:setColor((tab:isHovered() or tab:isFocused()) and "#dedede" or enterGame:getColor())
	end
	updateHighlight()

	local function reposition()
		if recordingsPanel and recordingsPanel:isVisible() then
			g_effects.cancelMove(recordingsPanel)
			positionRecordingsPanel()
		end
	end

	tab.onKeyPress = function(_, keyCode, modifiers, repeatTicks)
		if keyCode == KeyEnter and modifiers == KeyboardNoModifier then
			if repeatTicks == 0 then
				EnterGame.showRecordings()
				keyboardMousePosition = g_window.getMousePosition()
				recordingsPanel:focus()
			end
			return true
		end
	end
	recordingsPanel.onKeyPress = function(panel, keyCode, modifiers)
		if keyCode == KeyEscape and modifiers == KeyboardNoModifier then
			panel:hide()
			enterGame:focus()
			tab:focus()
			return true
		end
	end

	connect(tab, {
		onFocusChange = updateHighlight,
		onGeometryChange = reposition,
		onHoverChange = function(_, hovered)
			updateHighlight()
			if hovered then
				EnterGame.showRecordings()
			end
		end
	})
	connect(recordingsPanel, {
		onVisibilityChange = function(panel, visible)
			arrow:setOn(visible)
			if not visible then
				closeRecordingDeleteBox()
				removeEvent(hoverEvent)
				hoverEvent = nil
				keyboardMousePosition = nil
				g_effects.cancelMove(panel)
				g_effects.cancelFade(panel)
				return
			end

			hoverEvent = cycleEvent(function()
				if panel.moveEvent or recordingDeleteBox then
					return
				end
				local mouse = g_window.getMousePosition()
				if keyboardMousePosition and mouse.x == keyboardMousePosition.x and mouse.y == keyboardMousePosition.y then
					return
				end
				keyboardMousePosition = nil
				local between = mouse.x >= panel:getX() + panel:getWidth() and mouse.x < tab:getX()
					and mouse.y >= panel:getY() and mouse.y < panel:getY() + panel:getHeight()
				if not between and not panel:containsPoint(mouse) and not tab:containsPoint(mouse) then
					panel:hide()
				end
			end, 50)
		end
	})
	connect(enterGame, {
		onVisibilityChange = function(_, visible)
			if not visible and recordingsPanel then
				recordingsPanel:hide()
			end
		end,
		onGeometryChange = reposition
	})
end

function EnterGame.init()
	enterGame = g_ui.displayUI("entergame")
	enterGame.baseHeight = enterGame:getHeight()
	setupAccountsPanel()
	setupRecordingsPanel()
	Keybind.new("Misc.", "Change Character", "Ctrl+G", "")
	Keybind.bind("Misc.", "Change Character", {
		{
			type = KEY_DOWN,
			callback = EnterGame.openWindow
		}
	})

	local account = g_settings.get("account")
	local password = g_settings.get("password")

	EnterGame.setAccountName(account)
	EnterGame.setPassword(password)

	if Servers_init and table.size(Servers_init) == 1 then
		local hostInit, valuesInit = next(Servers_init)

		EnterGame.setUniqueServer(hostInit, valuesInit.port, valuesInit.protocol)
	end

	updateLabelText()

	local emailEdit = enterGame:getChildById("accountNameTextEdit")
	local passwordEdit = enterGame:getChildById("accountPasswordTextEdit")
	emailEdit:focus()
	local editsToFix = {
		"accountNameTextEdit",
		"accountPasswordTextEdit"
	}

	for _, editId in ipairs(editsToFix) do
		local editWidget = enterGame:getChildById(editId)

		if editWidget and not editWidget.keyPressEventFixed then
			local originalOnKeyPress = editWidget.onKeyPress

			function editWidget:onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks)
				if keyCode == KeyTab and (keyboardModifiers == KeyboardNoModifier or keyboardModifiers == KeyboardShiftModifier) then
					local backwards = keyboardModifiers == KeyboardShiftModifier
					local toAccounts = (self == emailEdit and backwards) or (self == passwordEdit and not backwards)
					local target = toAccounts and enterGame:getChildById("accountsToggle")
						or (self == emailEdit and passwordEdit or emailEdit)

					if target and not target:isDestroyed() then
						target:focus()
					end

					return true
				end

				if keyCode == KeyEnter and autoRepeatTicks > 0 then
					return true
				end

				if self == passwordEdit and (keyCode == KeyCapsLock or keyCode == 20) then
					addEvent(function()
						local sys = isSystemCapsLockActive()
						if sys ~= nil then
							capsLockActive = sys
						else
							capsLockActive = not capsLockActive
						end
						updateCapsLockWarning(capsLockActive)
					end)
				end

				local cursorPos = self:getCursorPos()
				local textLen = self:getText():len()

				if keyCode == KeyRight and cursorPos == textLen then
					return true
				end

				if keyCode == KeyLeft and cursorPos == 0 then
					return true
				end

				if originalOnKeyPress then
					return originalOnKeyPress(self, keyCode, keyboardModifiers, autoRepeatTicks)
				end

				return false
			end

			editWidget.keyPressEventFixed = true
		end
	end

	if passwordEdit then
		local originalFocusChange = passwordEdit.onFocusChange
		passwordEdit.onFocusChange = function(widget, focused)
			if originalFocusChange then
				originalFocusChange(widget, focused)
			end
			if focused then
				addEvent(function()
					updateCapsLockWarning()
				end)
			else
				updateCapsLockWarning(false)
			end
		end

		local originalOnTextChange = passwordEdit.onTextChange
		passwordEdit.onTextChange = function(widget, text, oldText)
			if originalOnTextChange then
				originalOnTextChange(widget, text, oldText)
			end
			if oldText and #text > #oldText then
				local added = text:sub(#oldText + 1)
				for i = 1, #added do
					local c = added:sub(i, i)
					if c:match("%a") then
						local isUpper = c:match("%u") ~= nil
						local shift = g_keyboard.isShiftPressed()
						if isUpper and not shift then
							capsLockActive = true
						elseif not isUpper and not shift then
							capsLockActive = false
						elseif isUpper and shift then
							capsLockActive = false
						elseif not isUpper and shift then
							capsLockActive = true
						end
					end
				end
			end
			updateCapsLockWarning()
		end
	end

	g_keyboard.bindKeyDown("CapsLock", function()
		if passwordEdit and passwordEdit:isFocused() then
			addEvent(function()
				local sys = isSystemCapsLockActive()
				if sys ~= nil then
					capsLockActive = sys
				else
					capsLockActive = not capsLockActive
				end
				updateCapsLockWarning(capsLockActive)
			end)
		end
	end, enterGame)

	setupEnterGameHighlights()

	enterGame:hide()
	connect(g_game, {
		onGameStart = EnterGame.hidePanels
	})
	connect(g_game, {
		onGameEnd = EnterGame.showPanels
	})

	if g_app.isRunning() and not g_game.isOnline() then
		EnterGame.firstShow()
	end
end

function EnterGame.hidePanels(force)
	if loadBox then
		loadBox:destroy()
		loadBox = nil
	end

	if enterGame then
		enterGame:hide()
	end

	if g_modules.getModule("client_bottommenu"):isLoaded() then
		modules.client_bottommenu.hide()
	end

	modules.client_topmenu.hide()
end

function EnterGame.showPanels()
	if g_modules.getModule("client_bottommenu"):isLoaded() then
		modules.client_bottommenu.show()
	end

	modules.client_topmenu.show()
end

function EnterGame.loadStartupData()
	if Services and Services.status and g_modules.getModule("client_bottommenu"):isLoaded() then
		EnterGame.postCacheInfo()
		EnterGame.postEventScheduler()
		EnterGame.postShowCreatureBoost()
	end
end

function EnterGame.firstShow()
	EnterGame.show()
	EnterGame.loadStartupData()
end

function EnterGame.terminate()
	Keybind.delete("Misc.", "Change Character")

	if recordingsPanel then
		recordingsPanel:hide()
		recordingsPanel:destroy()
		recordingsPanel = nil
	end

	if accountsPanel then
		clearAccountUndo()
		accountsPanel:hide()
		accountsPanel:destroy()
		accountsPanel = nil
	end

	if clientBox then
		disconnect(clientBox, {
			onOptionChange = EnterGame.onClientVersionChange
		})

		clientBox = nil
	end

	disconnect(g_game, {
		onGameStart = EnterGame.hidePanels
	})
	disconnect(g_game, {
		onGameEnd = EnterGame.showPanels
	})

	if enterGame then
		enterGame:destroy()

		enterGame = nil
	end

	if motdWindow then
		motdWindow:destroy()

		motdWindow = nil
	end

	EnterGame.destroyTwoFactorWindow()

	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	EnterGame = nil
end

local function reportRequestWarning(requestType, msg, errorCode)
	g_logger.warning(("[Webscraping - %s] %s"):format(requestType, msg), errorCode)
end

function dump(o)
	if type(o) == "table" then
		local s = "{ "

		for k, v in pairs(o) do
			if type(k) ~= "number" then
				k = "\"" .. k .. "\""
			end

			s = s .. "[" .. k .. "] = " .. dump(v) .. ","
		end

		return s .. "} "
	else
		return tostring(o)
	end
end

function EnterGame.postCacheInfo()
	local requestType = "cacheinfo"

	local function onRecvInfo(message, err)
		if err then
			reportRequestWarning(requestType, "Bad Request. Game_entergame postCacheInfo1")

			return
		end

		local jsonString = message:match("{.*}")

		if not jsonString then
			reportRequestWarning(requestType, "Invalid JSON response format")

			return
		end

		local success, response = pcall(function()
			return json.decode(jsonString)
		end)

		if not success or not response then
			reportRequestWarning(requestType, "Failed to parse JSON response")

			return
		end

		if response.errorMessage then
			reportRequestWarning(requestType, response.errorMessage, response.errorCode)

			return
		end

		modules.client_topmenu.setPlayersOnline(response.playersonline)
	end

	HTTP.post(Services.status, json.encode({
		type = requestType
	}), onRecvInfo, false)
end

function EnterGame.postEventScheduler()
	local requestType = "eventschedule"

	local function onRecvInfo(message, err)
		if err then
			reportRequestWarning(requestType, "Bad Request.Game_entergame postEventScheduler1")

			return
		end

		local jsonString = message:match("{.*}")

		if not jsonString then
			reportRequestWarning(requestType, "Invalid JSON response format")

			return
		end

		local success, response = pcall(function()
			return json.decode(jsonString)
		end)

		if not success or not response then
			reportRequestWarning(requestType, "Failed to parse JSON response")

			return
		end

		if response.errorMessage then
			reportRequestWarning(requestType, response.errorMessage, response.errorCode)

			return
		end

		modules.client_bottommenu.setEventsSchedulerTimestamp(response.lastupdatetimestamp)
		modules.client_bottommenu.setEventsSchedulerCalender(response.eventlist)
	end

	HTTP.post(Services.status, json.encode({
		type = requestType
	}), onRecvInfo, false)
end

function EnterGame.postShowOff()
	local requestType = "showoff"

	local function onRecvInfo(message, err)
		if err then
			reportRequestWarning(requestType, "Bad Request.Game_entergame postShowOff")

			return
		end

		local jsonString = message:match("{.*}")

		if not jsonString then
			reportRequestWarning(requestType, "Invalid JSON response format")

			return
		end

		local success, response = pcall(function()
			return json.decode(jsonString)
		end)

		if not success or not response then
			reportRequestWarning(requestType, "Failed to parse JSON response")

			return
		end

		if response.errorMessage then
			reportRequestWarning(requestType, response.errorMessage, response.errorCode)

			return
		end

		modules.client_bottommenu.setShowOffData(response)
	end

	HTTP.post(Services.status, json.encode({
		type = requestType
	}), onRecvInfo, false)
end

function EnterGame.postShowCreatureBoost()
	local requestType = "boostedcreature"

	local function onRecvInfo(message, err)
		if err then
			reportRequestWarning(requestType, "Bad Request.Game_entergame postShowCreatureBoost1")

			return
		end

		local jsonString = message:match("{.*}")

		if not jsonString then
			reportRequestWarning(requestType, "Invalid JSON response format")

			return
		end

		local success, response = pcall(function()
			return json.decode(jsonString)
		end)

		if not success or not response then
			reportRequestWarning(requestType, "Failed to parse JSON response")

			return
		end

		if response.errorMessage then
			reportRequestWarning(requestType, response.errorMessage, response.errorCode)

			return
		end

		modules.client_bottommenu.setBoostedCreatureAndBoss(response)
	end

	HTTP.post(Services.status, json.encode({
		type = requestType
	}), onRecvInfo, false)
end

function EnterGame.show()
	if g_game.isOnline() or CharacterList.isVisible() then
		return
	end

	if loadBox then
		return
	end

	local background = modules.client_background.getBackground()

	-- serverLogo (the ported client logo) removed from background.otui at the user's request - the guard
	-- stays in case our own logo returns in this spot
	if background and background.serverLogo then
		background.serverLogo:show()
	end

	-- Fade the window in (appear effect on launch and whenever we return to the login screen).
	-- Hiding stays synchronous so the login<->character-list transitions (e.g. ESC) are not blocked
	-- by a window that is still "visible" mid-fade.
	if enterGame:getChildById("rememberEmailBox"):isChecked() and G.account and G.account ~= "" then
		enterGame:getChildById("accountNameTextEdit"):setText(G.account)
	end

	if enterGame:getChildById("rememberPasswordBox"):isChecked() and G.password and G.password ~= "" then
		enterGame:getChildById("accountPasswordTextEdit"):setText(G.password)
	end

	enterGame:show()
	enterGame:raise()
	enterGame:focus()
	g_effects.fadeIn(enterGame, 80)
end

function EnterGame.hide()
	g_effects.cancelFade(enterGame)
	enterGame:hide()
	enterGame:setOpacity(1)

	updateCapsLockWarning(false)

	local background = modules.client_background.getBackground()

	if background and background.serverLogo then
		background.serverLogo:hide()
	end
end

function EnterGame.openWindow()
	if g_game.isOnline() then
		CharacterList.show()
	elseif not g_game.isLogging() and not CharacterList.isVisible() then
		EnterGame.show()
	end
end

function EnterGame.setAccountName(account)
	local account = safeDecrypt(account)

	local widget = enterGame:getChildById("accountNameTextEdit")
	if widget then
		widget:setText(account)
		widget:setCursorPos(-1)
	end

	local rem = g_settings.getBoolean("rememberEmail")
	if rem == nil then
		rem = (#account > 0)
	end
	local box = enterGame:getChildById("rememberEmailBox")
	if box then
		box:setChecked(rem)
	end
end

function EnterGame.setPassword(password)
	local password = safeDecrypt(password)

	local widget = enterGame:getChildById("accountPasswordTextEdit")
	if widget then
		widget:setText(password)
	end

	local rem = g_settings.getBoolean("rememberPassword")
	if rem == nil then
		rem = (#password > 0)
	end
	local box = enterGame:getChildById("rememberPasswordBox")
	if box then
		box:setChecked(rem)
	end
end

function EnterGame.saveRememberedCredentials(clearFieldsWhenUnchecked, persistChecked)
	if not enterGame then
		return
	end

	if persistChecked == nil then
		persistChecked = true
	end

	local accountEdit = enterGame:getChildById("accountNameTextEdit")
	local passwordEdit = enterGame:getChildById("accountPasswordTextEdit")

	if enterGame:getChildById("rememberEmailBox"):isChecked() then
		if persistChecked then
			g_settings.set("account", g_crypt.encrypt(G.account or ""))
			g_settings.set("rememberEmail", true)
		end
	else
		g_settings.set("rememberEmail", false)
		g_settings.remove("account")
		if clearFieldsWhenUnchecked and accountEdit then
			accountEdit:clearText()
			accountEdit:focus()
		end
	end

	if enterGame:getChildById("rememberPasswordBox"):isChecked() then
		if persistChecked then
			g_settings.set("password", g_crypt.encrypt(G.password or ""))
			g_settings.set("rememberPassword", true)
		end
	else
		g_settings.set("rememberPassword", false)
		g_settings.remove("password")
		if clearFieldsWhenUnchecked and passwordEdit then
			passwordEdit:clearText()
			if accountEdit then
				accountEdit:focus()
			end
		end
	end

	g_settings.save()
end

function EnterGame.clearAccountFields()
	enterGame:getChildById("accountNameTextEdit"):clearText()
	enterGame:getChildById("accountPasswordTextEdit"):clearText()
	enterGame:getChildById("accountNameTextEdit"):focus()
	g_settings.remove("account")
	g_settings.remove("password")
end

function EnterGame.clearPasswordNameFields()
	enterGame:getChildById("accountPasswordTextEdit"):clearText()
	enterGame:getChildById("accountNameTextEdit"):focus()
	g_settings.remove("password")
end

function EnterGame.clearAccountNameFields()
	enterGame:getChildById("accountNameTextEdit"):clearText()
	enterGame:getChildById("accountNameTextEdit"):focus()
	g_settings.remove("account")
end

function EnterGame.onClientVersionChange(comboBox, text, data)
	updateLabelText()
end

function EnterGame.tryHttpLogin(clientVersion, httpLogin, token)
	G.pendingClientVersion = clientVersion
	G.pendingHttpLogin = httpLogin

	g_game.setClientVersion(clientVersion)
	g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
	g_game.chooseRsa(G.host)

	if not modules.game_things.isLoaded() then
		if loadBox then
			loadBox:destroy()

			loadBox = nil
		end

		local errorBox = displayErrorBox(tr("Sorry"), "Things are not loaded, please put assets in things/assets/.")

		connect(errorBox, {
			onOk = EnterGame.show
		})

		return
	end

	local host, path = parseHttpLoginHost(G.host)

	if not host then
		abortHttpLogin(tr("ERROR , try adding \n- ip/login.php \n- Enable HTTP login"))

		return
	end

	if not G.port then
		G.port = 443
	end

	G.loginHost = host
	G.loginPath = path

	loadBox = displayCancelBox(tr("Connecting"), tr("Your character list is being loaded. Please wait."))

	connect(loadBox, {
		onCancel = function(msgbox)
			if G.httpOperationId then
				HTTP.cancel(G.httpOperationId)

				G.httpOperationId = nil
			end

			loadBox = nil
			G.requestId = 0

			EnterGame.show()
		end
	})
	G.requestId = (G.requestId or 0) + 1

	sendHttpLoginRequest(httpLogin, token or "", true)
end

function EnterGame.destroyTwoFactorWindow()
	if twoFactorWindow then
		twoFactorWindow:destroy()

		twoFactorWindow = nil
	end
end

function EnterGame.showTwoFactorWindow()
	EnterGame.destroyTwoFactorWindow()

	twoFactorWindow = g_ui.displayUI("twofactor")

	local tokenTextEdit = twoFactorWindow:getChildById("tokenTextEdit")

	tokenTextEdit:clearText()
	tokenTextEdit:focus()
end

function EnterGame.submitTwoFactor()
	if not twoFactorWindow then
		return
	end

	local token = twoFactorWindow:getChildById("tokenTextEdit"):getText()

	if token:len() == 0 then
		return
	end

	G.authenticatorToken = token

	EnterGame.destroyTwoFactorWindow()
	EnterGame.tryHttpLogin(G.pendingClientVersion, G.pendingHttpLogin, token)
end

function EnterGame.cancelTwoFactor()
	EnterGame.destroyTwoFactorWindow()
	EnterGame.show()
end

function EnterGame.handleHttpLoginResponse(data, err, requestId)
	if G.requestId ~= requestId then
		return
	end

	if loadBox then
		loadBox:destroy()

		loadBox = nil
	end

	G.httpOperationId = nil

	if err then
		onError(nil, err, nil)

		return
	end

	if not data then
		onError(nil, tr("Unexpected JSON format."), nil)

		return
	end

	if data.errorCode == 6 then
		EnterGame.showTwoFactorWindow()

		return
	end

	if data.errorMessage then
		onError(nil, data.errorMessage, data.errorCode)

		return
	end

	if not data.session then
		onError(nil, tr("No session data"), nil)

		return
	end

	EnterGame.destroyTwoFactorWindow()

	local characters = {}
	local worlds = {}

	if data.playdata then
		characters = data.playdata.characters or {}
		worlds = data.playdata.worlds or {}
	end

	EnterGame.loginSuccess(requestId, json.encode(data.session), json.encode(worlds), json.encode(characters))
end

function EnterGame.loginSuccess(requestId, jsonSession, jsonWorlds, jsonCharacters)
	if G.requestId ~= requestId then
		return
	end

	EnterGame.destroyTwoFactorWindow()

	local worlds = {}

	for _, world in ipairs(json.decode(jsonWorlds)) do
		if world.id then
			worlds[world.id] = {
				name = world.name,
				ip = world.externaladdressprotected,
				port = world.externalportprotected,
				previewState = world.previewstate == 1,
				pvptype = world.pvptype
			}
		end
	end

	local characters = {}

	for index, character in ipairs(json.decode(jsonCharacters)) do
		local world = worlds[character.worldid]

		characters[index] = {
			name = character.name,
			level = character.level,
			main = character.ismaincharacter,
			dailyreward = character.dailyrewardstate,
			hidden = character.ishidden,
			vocation = character.vocation,
			outfitid = character.outfitid,
			headcolor = character.headcolor,
			torsocolor = character.torsocolor,
			legscolor = character.legscolor,
			detailcolor = character.detailcolor,
			addonsflags = character.addonsflags,
			worldName = world.name,
			worldIp = world.ip,
			worldPort = world.port,
			previewState = world.previewstate,
			worldPvpType = world.pvptype
		}
	end

	local session = json.decode(jsonSession)
	local premiumUntil = tonumber(session.premiumuntil)
	local account = {
		status = "",
		premDays = math.floor((premiumUntil - os.time()) / 86400),
		subStatus = premiumUntil > os.time() and SubscriptionStatus.Premium or SubscriptionStatus.Free,
		recoverySetupComplete = session.recoverysetupcomplete
	}

	G.sessionKey = session.sessionkey

	onCharacterList(nil, characters, account)
end

function EnterGame.loginFailed(requestId, msg, result)
	if G.requestId ~= requestId then
		return
	end

	onError(nil, msg, result)
end

function EnterGame.tryProtocolLogin(clientVersion)
	protocolLogin = ProtocolLogin.create()
	protocolLogin.onLoginError = onError
	protocolLogin.onMotd = onMotd
	protocolLogin.onSessionKey = onSessionKey
	protocolLogin.onCharacterList = onCharacterList
	protocolLogin.onUpdateNeeded = onUpdateNeeded

	loadBox = displayCancelBox(tr("Please wait"), tr("Connecting to login server..."))

	connect(loadBox, {
		onCancel = function(msgbox)
			loadBox = nil
			protocolLogin:cancelLogin()
			EnterGame.show()
		end
	})

	g_game.setClientVersion(clientVersion)
	g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
	g_game.chooseRsa(G.host)

	if modules.game_things.isLoaded() then
		protocolLogin:login(G.host, G.port, G.account, G.password, G.authenticatorToken or "", false)
	else
		if loadBox then
			loadBox:destroy()
			loadBox = nil
		end

		local errorBox = displayErrorBox(tr("Login Error"), string.format("Things are not loaded, please put spr and dat in things/%d/<here>.", clientVersion))

		connect(errorBox, {
			onOk = EnterGame.show
		})

		return
	end
end

function EnterGame.onGoogleLoginClick()
	-- Placeholder: visible in UI; opens Services.googleLogin only when configured.
	local url = Services and Services.googleLogin
	if url and url ~= "" then
		g_platform.openUrl(url)

		return true
	end

	displayInfoBox(tr("Information"), tr("Google login URL not configured. Please contact the server administrator."))

	return true
end

function EnterGame.setHttpLogin(httpLogin)
	g_settings.set("httpLogin", httpLogin == true)
end

function EnterGame.doLogin()
	G.account = enterGame:getChildById("accountNameTextEdit"):getText()
	G.password = enterGame:getChildById("accountPasswordTextEdit"):getText()
	G.authenticatorToken = ""
	saveAccountOnLogin = accountsPanel:getChildById("saveAccount"):isChecked()
	saveAccountPassword = enterGame:getChildById("rememberPasswordBox"):isChecked()

	EnterGame.saveRememberedCredentials(false, false)

	local hostInit = "127.0.0.1"
	local portInit = 7171
	local protocolInit = 860
	local httpLogin = false

	if Servers_init and next(Servers_init) ~= nil then
		local host, values = next(Servers_init)
		hostInit = host
		portInit = values.port or portInit
		protocolInit = tonumber(values.protocol) or protocolInit
		httpLogin = values.httpLogin or false
	end

	G.host = hostInit
	G.port = portInit

	local clientVersion = protocolInit

	EnterGame.hide()

	if g_game.isOnline() then
		local errorBox = displayErrorBox(tr("Sorry"), tr("Cannot login while already in game."))

		connect(errorBox, {
			onOk = EnterGame.show
		})

		return
	end

	g_settings.set("host", G.host)
	g_settings.set("port", G.port)
	g_settings.set("client-version", clientVersion)

	if httpLogin then
		EnterGame.tryHttpLogin(clientVersion, httpLogin)
	else
		EnterGame.tryProtocolLogin(clientVersion)
	end
end

function EnterGame.displayMotd()
	if not motdWindow then
		motdWindow = displayInfoBox(tr("Message of the day"), G.motdMessage)

		function motdWindow.onOk()
			motdWindow = nil
		end
	end
end

function EnterGame.setDefaultServer(host, port, protocol)
	local hostTextEdit = enterGame:getChildById("serverHostTextEdit")
	local portTextEdit = enterGame:getChildById("serverPortTextEdit")
	local accountTextEdit = enterGame:getChildById("accountNameTextEdit")
	local passwordTextEdit = enterGame:getChildById("accountPasswordTextEdit")

	if hostTextEdit:getText() ~= host then
		hostTextEdit:setText(host)
		portTextEdit:setText(port)
		clientBox:setCurrentOption(protocol)
		accountTextEdit:setText("")
		passwordTextEdit:setText("")
	end
end

function EnterGame.setUniqueServer(host, port, protocol, windowWidth, windowHeight)
	local clientVersion = tonumber(protocol)

	windowWidth = windowWidth or 280

	enterGame:setWidth(windowWidth)

	windowHeight = windowHeight or 244

	enterGame.baseHeight = windowHeight
	enterGame:setHeight(windowHeight)
	g_game.setClientVersion(clientVersion)
	g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
end

function EnterGame.setServerInfo(message)
	local label = enterGame:getChildById("serverInfoLabel")

	label:setText(message)
end

function EnterGame.disableMotd()
	motdEnabled = false
end

function ensableBtnCreateNewAccount()
	enterGame.btnCreateNewAccount:enable()
end
