local window, previousType, currentType
local bestiaryPanel
cyclopediaButton = nil
bestiaryTrackerButton = nil

function init()
	
	-- The rest
	connect(g_game, { 
		onEnterGame = registerBestiaryProtocol,
		onPendingGame = registerBestiaryProtocol,
		onGameEnd = onCyclopediaGameEnd
	})
	if registerBestiaryProtocol then
		registerBestiaryProtocol()
	end
    
	g_ui.importStyle('styles/bestiary_tracker')
	window 	   = g_ui.displayUI('game_cyclopedia')
	
	cyclopediaButton = modules.client_topmenu.addRightGameToggleButton('cyclopediaButton', tr('Cyclopedia'), '/images/topbuttons/ciclopedia', toggle, false, 8)
	bestiaryTrackerButton = modules.client_topmenu.addRightGameToggleButton('bestiaryTrackerButton', tr('Bestiary Tracker'), '/images/topbuttons/bestiaryTracker', toggleTracker, false, 9)
	contentContainer = window:recursiveGetChildById('contentContainer')
	buttonSelection = window:recursiveGetChildById('buttonSelection')
		items = buttonSelection:recursiveGetChildById('items')
		bestiary = buttonSelection:recursiveGetChildById('bestiary')
		charms = buttonSelection:recursiveGetChildById('charms')
		map = buttonSelection:recursiveGetChildById('map')
		houses = buttonSelection:recursiveGetChildById('houses')
		character = buttonSelection:recursiveGetChildById('character')

	modules.game_cyclopedia = modules.game_cyclopedia
end

function terminate()
	disconnect(g_game, { 
		onEnterGame = registerBestiaryProtocol,
		onPendingGame = registerBestiaryProtocol,
		onGameEnd = onCyclopediaGameEnd
	})
	
	-- Internal protocols
	-- disconnect(g_game, {onEnterGame = registerBestiaryProtocol, onPendingGame = registerBestiaryProtocol})
	
	-- Hooked opcodes
	ProtocolGame.unregisterOpcode(0x29)
	if terminateBestiary then
		terminateBestiary()
	elseif unregisterBestiaryProtocol then
		unregisterBestiaryProtocol()
	else
		ProtocolGame.unregisterOpcode(0x48)
	end
	
	if cyclopediaButton then
		cyclopediaButton:destroy()
		cyclopediaButton = nil
	end
	if bestiaryTrackerButton then
		bestiaryTrackerButton:destroy()
		bestiaryTrackerButton = nil
	end
	
	window:destroy()
	
	if buyWindow then
		buyWindow:destroy()
	end
end

function getContentContainer()
	return contentContainer
end

function getCurrentType()
	return currentType
end

function onCyclopediaGameEnd()
	if window then
		window:hide()
	end
	if onBestiaryGameEnd then
		onBestiaryGameEnd()
	end
end

function toggle()
	if window:isVisible() then
		window:hide()
	else
		show("bestiary") -- We init on bestiary
	end
end

function show(type)
	type = type or "bestiary"

	if currentType ~= type then
		toggleWindow(type)
	end

	if not window:isVisible() then
		window:show()
	end

	window:raise()
	window:focus()
end

function toggleTracker()
	if toggleBestiaryTracker then
		toggleBestiaryTracker()
	end
end

function emptyContentContainer()
	for _, child in ipairs(contentContainer:getChildren()) do
		child:hide()
	end
end

function changePreviousType(type)
	previousType = type
end

function toggleWindow(type)
	if previousType then
		previousType:enable()
		previousType:setOn(false)
	end
	
	-- We empty the container
	emptyContentContainer()
	currentType = type
		
	if (type == "items") then
		items:setOn(true)
		items:disable()
		changePreviousType(items)
	elseif (type == "bestiary") then
		bestiary:setOn(true)
		bestiary:disable()
		changePreviousType(bestiary)
		
		-- Setup the widget
		initBestiary(contentContainer)
	elseif (type == "charms") then
		charms:setOn(true)
		charms:disable()
		changePreviousType(charms)
		
		-- Setup the charms
		initCharms(contentContainer)
	elseif (type == "map") then
		map:setOn(true)
		map:disable()
		changePreviousType(map)
		
		-- Setup the widget
		initMap(contentContainer)
	elseif (type == "houses") then
		houses:setOn(true)
		houses:disable()
		changePreviousType(houses)
	elseif (type == "character") then
		character:setOn(true)
		character:disable()
		changePreviousType(character)
	end
end
