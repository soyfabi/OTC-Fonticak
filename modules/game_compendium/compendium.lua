local PAGES_FILE = '/modules/game_compendium/compendium_pages.json'
local BUTTON_ID = 'compendiumDialog'

local compendiumWindow
local compendiumButton
local sections = {}
local currentSection = 1
local currentPage = 1

local function setInputLockWidget(widget)
	if g_client and g_client.setInputLockWidget then
		g_client.setInputLockWidget(widget)
	end
end

local function loadSections()
	local status, data = pcall(function()
		if not g_resources.fileExists(PAGES_FILE) then
			return nil
		end
		return json.decode(g_resources.readFileContents(PAGES_FILE))
	end)

	if status and type(data) == 'table' and #data > 0 then
		return data
	end

	g_logger.warning('[game_compendium] Failed to load %s, using built-in fallback.', PAGES_FILE)
	return {
		{
			title = 'Game Contents',
			pages = { 'Compendium pages could not be loaded. Check compendium_pages.json.' }
		}
	}
end

local function renderPage()
	if not compendiumWindow or #sections == 0 then
		return
	end

	local section = sections[currentSection]
	if not section or not section.pages or #section.pages == 0 then
		return
	end

	currentPage = math.max(1, math.min(currentPage, #section.pages))

	local content = compendiumWindow:recursiveGetChildById('compendiumContent')
	local pages = compendiumWindow:recursiveGetChildById('pages')
	local previousButton = compendiumWindow:recursiveGetChildById('previousPageButton')
	local nextButton = compendiumWindow:recursiveGetChildById('nextPageButton')

	if content then
		content:setText(section.pages[currentPage] or '')
	end
	if pages then
		pages:setText(string.format('%d / %d', currentPage, #section.pages))
	end
	if previousButton then
		previousButton:setEnabled(currentPage > 1)
	end
	if nextButton then
		nextButton:setEnabled(currentPage < #section.pages)
	end

	for index = 1, #sections do
		local button = compendiumWindow:recursiveGetChildById('buttonMenu' .. index)
		if button then
			button:setChecked(index == currentSection)
		end
	end
end

local function syncCompendiumButtonTooltip()
	if not compendiumButton or compendiumButton:isDestroyed() then
		return
	end

	if Keybind and Keybind.syncToggleButtonTooltip then
		Keybind.syncToggleButtonTooltip(compendiumButton, BUTTON_ID, 'Open Compendium', 'Close Compendium')
	else
		local label = compendiumButton:isOn() and tr('Close Compendium') or tr('Open Compendium')
		compendiumButton:setTooltip(label)
	end
end

local function onGameStart()
	if compendiumButton or not modules.game_mainpanel or not modules.game_mainpanel.addToggleButton then
		return
	end

	if Keybind and Keybind.registerControlButtonHotkey then
		Keybind.registerControlButtonHotkey(BUTTON_ID, 'Dialogs', 'Open Compendium')
	end

	compendiumButton = modules.game_mainpanel.addToggleButton(
		BUTTON_ID,
		tr('Open Compendium'),
		'/images/options/button_compendium',
		toggle,
		false,
		22
	)

	syncCompendiumButtonTooltip()
end

local function onGameEnd()
	if compendiumButton then
		compendiumButton:destroy()
		compendiumButton = nil
	end

	if compendiumWindow and compendiumWindow:isVisible() then
		hide()
	end
end

function init()
	sections = loadSections()
	compendiumWindow = g_ui.displayUI('compendium')
	currentSection = 1
	currentPage = 1
	renderPage()
	hide()

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
	setInputLockWidget(nil)

	if compendiumWindow then
		compendiumWindow:destroy()
		compendiumWindow = nil
	end
end

function hide()
	if not compendiumWindow then
		return
	end

	compendiumWindow:hide()
	setInputLockWidget(nil)

	if compendiumButton then
		compendiumButton:setOn(false)
		syncCompendiumButtonTooltip()
	end
end

function show()
	if not compendiumWindow then
		return
	end

	currentSection = 1
	currentPage = 1
	compendiumWindow:show(true)
	compendiumWindow:focus()
	compendiumWindow:raise()
	setInputLockWidget(compendiumWindow)
	renderPage()

	if compendiumButton then
		compendiumButton:setOn(true)
		syncCompendiumButtonTooltip()
	end
end

function toggle()
	if not compendiumWindow then
		return
	end

	if compendiumWindow:isVisible() then
		hide()
	else
		show()
	end
end

function selectSection(index)
	if not sections[index] then
		return
	end

	currentSection = index
	currentPage = 1
	renderPage()
end

function previousPage()
	currentPage = currentPage - 1
	renderPage()
end

function nextPage()
	currentPage = currentPage + 1
	renderPage()
end

function reloadPages()
	sections = loadSections()
	currentSection = math.min(currentSection, #sections)
	currentPage = 1
	renderPage()
end
