-- chunkname: @/client_entergame/entergame.lua

EnterGame = {}

local loadBox, enterGame, motdWindow, enterGameButton, clientBox
local motdEnabled = true
local twoFactorWindow, hostInfos
local protocolLogin

local function safeDecrypt(text)
	if not text or text == "" then
		return ""
	end
	local ok, res = pcall(g_crypt.decrypt, text)
	return ok and res or text
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

function EnterGame.init()
	enterGame = g_ui.displayUI("entergame")
	enterGame.baseHeight = enterGame:getHeight()

	Keybind.new("Misc.", "Change Character", "Ctrl+G", "")
	Keybind.bind("Misc.", "Change Character", {
		{
			type = KEY_DOWN,
			callback = EnterGame.openWindow
		}
	})

	local account = g_settings.get("account")
	local password = g_settings.get("password")
	local clientVersion = g_settings.getInteger("client-version")

	EnterGame.setAccountName(account)
	EnterGame.setPassword(password)

	if Servers_init and table.size(Servers_init) == 1 then
		local hostInit, valuesInit = next(Servers_init)

		EnterGame.setUniqueServer(hostInit, valuesInit.port, valuesInit.protocol)
	end

	updateLabelText()

	local emailEdit = enterGame:getChildById("accountNameTextEdit")
	local passwordEdit = enterGame:getChildById("accountPasswordTextEdit")
	local editsToFix = {
		"accountNameTextEdit",
		"accountPasswordTextEdit"
	}

	for _, editId in ipairs(editsToFix) do
		local editWidget = enterGame:getChildById(editId)

		if editWidget and not editWidget.keyPressEventFixed then
			local originalOnKeyPress = editWidget.onKeyPress

			function editWidget:onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks)
				if keyCode == KeyTab and (self == emailEdit or self == passwordEdit) then
					local target = self == emailEdit and passwordEdit or emailEdit

					if target and not target:isDestroyed() then
						target:focus()
					end

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
	local clientLabel = enterGame:getChildById("clientLabel")
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
	local rememberEmailBox = enterGame:getChildById("rememberEmailBox")

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
