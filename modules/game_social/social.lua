local BUTTON_ID = 'friendsDialog'

local socialButton

local function onGameStart()
	if socialButton or not modules.game_mainpanel or not modules.game_mainpanel.addToggleButton then
		return
	end

	socialButton = modules.game_mainpanel.addToggleButton(
		BUTTON_ID,
		tr('Open Social Dialog'),
		'/images/options/button_social_dialog',
		toggle,
		false,
		23
	)

	if Keybind and Keybind.syncToggleButtonTooltip then
		Keybind.syncToggleButtonTooltip(socialButton, BUTTON_ID, 'Open Social Dialog', 'Close Social Dialog')
	end
end

local function onGameEnd()
	if socialButton then
		socialButton:destroy()
		socialButton = nil
	end
end

function init()
	connect(g_game, {
		onGameStart = onGameStart,
		onGameEnd = onGameEnd
	})

	if g_game.isOnline() then
		onGameStart()
	end
end

function terminate()
	disconnect(g_game, {
		onGameStart = onGameStart,
		onGameEnd = onGameEnd
	})

	onGameEnd()
end

function toggle()
	displayErrorBox(tr('For Your Information'), tr('Content Under Development...'))
	if socialButton then
		socialButton:setOn(false)
	end
end

function show()
	toggle()
end

function hide()
	if socialButton then
		socialButton:setOn(false)
	end
end

function open()
	toggle()
end
