local preloaded, fullmapView, minimapWidget, mapPanel, mapConnected = false, false

function initMap(contentContainer)
	mapPanel = g_ui.loadUI("styles/map", contentContainer)
	mapPanel:show()
	
	minimapWidget = mapPanel:recursiveGetChildById("minimap")
	if not mapConnected then
		connect(
			g_game,
			{
				onGameStart = online
			}
		)

		connect(
			LocalPlayer,
			{
				onPositionChange = updateCameraPosition
			}
		)
		mapConnected = true
	end
	
	if g_game.isOnline() then
        online()
    end
end

function online()
    loadMap(false)
    updateCameraPosition()
end

function terminateMap()
	if not mapConnected then
		return
	end

	disconnect(
		g_game,
		{
			onGameStart = online
		}
	)

	disconnect(
		LocalPlayer,
		{
			onPositionChange = updateCameraPosition
		}
	)
	mapConnected = false
end


function loadMap(clean)
    if not minimapWidget then
        return
    end

    local clientVersion = g_game.getClientVersion()

    if clean then
        g_minimap.clean()
    end

    if otmm then
        local minimapFile = "/minimap.otmm"
        if g_resources.fileExists(minimapFile) then
            g_minimap.loadOtmm(minimapFile)
        end
    else
        local minimapFile = "/minimap_" .. clientVersion .. ".otcm"
        if g_resources.fileExists(minimapFile) then
            g_map.loadOtcm(minimapFile)
        end
    end
    minimapWidget:load()
end



function updateCameraPosition()
    if not minimapWidget then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    local pos = player:getPosition()
    if not pos then
        return
    end
    if not minimapWidget:isDragging() then
        if not fullmapView then
            minimapWidget:setCameraPosition(player:getPosition())
        end
        minimapWidget:setCrossPosition(player:getPosition())
    end
end
