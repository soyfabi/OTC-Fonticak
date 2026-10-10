-- chunkname: @/game_cyclopedia/tab/houses/houses.lua

local UI

function Cyclopedia.clearHousesUI()
	if UI and not UI:isDestroyed() then
		UI:destroy()
	end

	UI = nil
end

function showHouses()
	local container = modules.game_cyclopedia.getContentContainer and modules.game_cyclopedia.getContentContainer() or contentContainer
	if not container then
		return
	end

	if UI and not UI:isDestroyed() then
		UI:show()
		return
	end

	Cyclopedia.clearHousesUI()

	UI = g_ui.loadUI("houses", container)

	function UI.onDestroy()
		UI = nil
	end

	UI:show()
end
