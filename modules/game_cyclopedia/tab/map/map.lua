-- chunkname: @/game_cyclopedia/tab/map/map.lua

local UI
local virtualFloor = 7
local refreshVirtualFloors
local updatingMapFlags = false
local loadingMapConfig = false
local MAP_CONFIG_FILE_NAME = "cyclopediaMapConfiguration.json"
local LAYER_FLOOR_MIN = 0
local LAYER_FLOOR_MAX = 15
local LEVEL_SEPARATOR_MIDDLE_FLOOR = 7
local DEFAULT_LEVEL_SEPARATOR = 0
local CYCLOPEDIA_MAP_ZOOM_OFFSET = 0
-- scale 0.5: viewport ~982x826 tiles, full LOD + city names + POI (see applyCyclopediaDefaultZoom)
local CYCLOPEDIA_MAP_DEFAULT_ZOOM = -1
-- which tile set is currently loaded - so we do not reload them on every refresh
local lastLoadedSatelliteDir = nil
local cyclopediaSatelliteReady = false

local function getCyclopediaTilesDir(useSurfaceFallback)
	local baseDir = "/things/" .. g_game.getClientVersion()

	return useSurfaceFallback and baseDir or (baseDir .. "_mapview")
end

local function isSurfaceViewSelected()
	local surfaceCheck = UI and UI:recursiveGetChildById("SurfaceCheck")

	return surfaceCheck and surfaceCheck:isChecked() or false
end

local function hasCyclopediaSatelliteData(tilesDir)
	tilesDir = tilesDir or getCyclopediaTilesDir(false)

	return g_resources.fileExists(tilesDir .. "/satellite/index.dat")
end

local function syncCyclopediaSatelliteMode(minimap, tilesDir)
	if not minimap or not minimap.setSatelliteMode then
		cyclopediaSatelliteReady = false

		return false
	end

	if not tilesDir or not hasCyclopediaSatelliteData(tilesDir) then
		minimap:setSatelliteMode(false)
		cyclopediaSatelliteReady = false
		lastLoadedSatelliteDir = nil

		if g_satelliteMap and g_satelliteMap.clearHighlight then
			g_satelliteMap.clearHighlight()
		end

		return false
	end

	if not g_satelliteMap or not g_satelliteMap.loadFloors then
		minimap:setSatelliteMode(false)
		cyclopediaSatelliteReady = false

		return false
	end

	if lastLoadedSatelliteDir ~= tilesDir then
		g_satelliteMap.loadFloors(tilesDir, 0, 15)
		lastLoadedSatelliteDir = tilesDir
	end

	local floorZ = 7
	local pos = minimap.getCameraPosition and minimap:getCameraPosition()

	if pos then
		floorZ = pos.z
	end

	cyclopediaSatelliteReady = g_satelliteMap.hasChunksForView and g_satelliteMap.hasChunksForView(floorZ) or false
	minimap:setSatelliteMode(cyclopediaSatelliteReady)

	return cyclopediaSatelliteReady
end
local MINIMAP_DRAW_MODE_NORMAL = 0
local MINIMAP_DRAW_MODE_CYCLOPEDIA = 1
local CYCLOPEDIA_VIEW_SURFACE = 0
local CYCLOPEDIA_VIEW_MAP = 1
local CYCLOPEDIA_AREA_TYPE_AREA = 1
local CYCLOPEDIA_AREA_TYPE_SUBAREA = 2
local CYCLOPEDIA_MAP_OPCODE = 219
local CYCLOPEDIA_MAP_ACTION_DONATE = 1
local CYCLOPEDIA_MAP_ACTION_SELECT = 2
local UINT32_MAX = 4294967295
local CYCLOPEDIA_AREA_LABEL_FONT = "Verdana Bold-11px-outline"
local CYCLOPEDIA_SUBAREA_LABEL_FONT = "Verdana Bold-11px-outline"
local CYCLOPEDIA_AREA_LABEL_COLOR = "#ffffffff"
local CYCLOPEDIA_AREA_LABEL_SELECTED_COLOR = "#ffff00ff"
local CYCLOPEDIA_SUBAREA_LABEL_COLOR = "#8f8f8fff"
local CYCLOPEDIA_SECTION_COLLAPSED_HEIGHT = 19
local CYCLOPEDIA_DISPLAY_PANEL_HEIGHT = 253
local CYCLOPEDIA_NAVIGATION_PANEL_HEIGHT = 97
local CYCLOPEDIA_AREA_PANEL_HEIGHT = 141
local CYCLOPEDIA_SUBAREA_PANEL_HEIGHT = 202
local CYCLOPEDIA_SECTION_ICON_COLLAPSED = "0 0 12 12"
local CYCLOPEDIA_SECTION_ICON_EXPANDED = "0 12 12 12"
-- Subareas (names of specific cities) only appeared from scale 1, i.e. from zoom 0,
-- while the default map view has zoom -1 (scale 0.5). Result: ONLY the main regions were visible,
-- and their names are drawn at the centroid of the whole region, so they landed next to the city.
-- The lowered thresholds show subareas already in the default view.
local CYCLOPEDIA_LABEL_TRANSITION_START_SCALE = 0.4
local CYCLOPEDIA_LABEL_TRANSITION_END_SCALE = 1
local CYCLOPEDIA_LABEL_PRELOAD_TILES = 64
local CYCLOPEDIA_BG_SURFACE_Z7 = "#284da6"
local CYCLOPEDIA_BG_MAP_Z7 = "#336699"
local CYCLOPEDIA_GROUND_FLOOR = 7
local dragStartMouseY = 0
local dragStartMargin = 0
local mapPositionConnected, areaLabelData
local areaDataById = {}
local areaLabelWidgets = {}
local areaLabelRefreshEvent
local selectedAreaId = -1
local selectedParentAreaId = 0
local selectedDonationAreaId = 0
local selectedDonationAmount = 0
local updatingDonationAmountEdit = false
local areaDonationConfirmWindow
local displayPanelExpanded = true
local navigationPanelExpanded = true
local areaPanelExpanded = true

local FLOOR_MARK_STEP = 4

local function layerMarginTopForFloor(z)
	z = math.max(LAYER_FLOOR_MIN, math.min(LAYER_FLOOR_MAX, z))

	return (z + 1) * FLOOR_MARK_STEP - FLOOR_MARK_STEP
end

local function floorFromMousePos(panel, mousePos)
	local strip = panel:getChildById("automapLayers")

	if not strip or strip:isDestroyed() then
		return nil
	end

	local mark = panel:getChildById("layersMark")
	local markHalf = mark and not mark:isDestroyed() and math.floor(mark:getHeight() / 2) or 0
	local offset = mousePos.y - strip:getY() - markHalf - 1

	return math.max(LAYER_FLOOR_MIN, math.min(LAYER_FLOOR_MAX, math.floor(offset / FLOOR_MARK_STEP + 0.5)))
end

local function getFilterFrame()
	if not UI or not UI.InformationBase then
		return nil
	end

	return UI.InformationBase.FilterFrame
end

local function getNavigationBase()
	local filterFrame = getFilterFrame()

	if not filterFrame then
		return nil
	end

	return filterFrame:recursiveGetChildById("NavigationBase")
end

local function getDisplayBase()
	local filterFrame = getFilterFrame()

	if not filterFrame then
		return nil
	end

	return filterFrame:recursiveGetChildById("DisplayBase")
end

local function setSectionToggleState(panel, buttonId, expanded)
	if not panel then
		return
	end

	local button = panel:recursiveGetChildById(buttonId)

	if button then
		button:setImageClip(torect(expanded and CYCLOPEDIA_SECTION_ICON_EXPANDED or CYCLOPEDIA_SECTION_ICON_COLLAPSED))
	end
end

local function applySectionFrameState(panel, expanded)
	if expanded then
		panel:setImageBorder(20)

		return
	end

	panel:setImageBorder(2)
	panel:setImageBorderTop(17)
	panel:setImageBorderBottom(2)
end

local function setPanelChildrenVisible(panel, childIds, visible)
	if not panel then
		return
	end

	for _, childId in ipairs(childIds) do
		local child = panel:recursiveGetChildById(childId)

		if child then
			child:setVisible(visible)
		end
	end
end

local function applyDisplayPanelState()
	local panel = getDisplayBase()

	if not panel then
		return
	end

	setPanelChildrenVisible(panel, {
		"filterMarksLabel",
		"MarkListFrame",
		"viewsLabel",
		"ViewBase"
	}, displayPanelExpanded)
	applySectionFrameState(panel, displayPanelExpanded)
	panel:setHeight(displayPanelExpanded and CYCLOPEDIA_DISPLAY_PANEL_HEIGHT or CYCLOPEDIA_SECTION_COLLAPSED_HEIGHT)
	setSectionToggleState(panel, "displayToggleButton", displayPanelExpanded)
end

local function applyNavigationPanelState()
	local panel = getNavigationBase()

	if not panel then
		return
	end

	setPanelChildrenVisible(panel, {
		"rosePanel",
		"layerSelector",
		"navigationZoom"
	}, navigationPanelExpanded)
	applySectionFrameState(panel, navigationPanelExpanded)
	panel:setHeight(navigationPanelExpanded and CYCLOPEDIA_NAVIGATION_PANEL_HEIGHT or CYCLOPEDIA_SECTION_COLLAPSED_HEIGHT)
	setSectionToggleState(panel, "navigationToggleButton", navigationPanelExpanded)
end

local function getLayersMark()
	local navigationBase = getNavigationBase()

	if not navigationBase then
		return nil
	end

	return navigationBase:recursiveGetChildById("layersMark")
end

local function getLayersPanel()
	local navigationBase = getNavigationBase()

	if not navigationBase then
		return nil
	end

	return navigationBase:recursiveGetChildById("layersPanel")
end

local function setupLayersPanelInteraction()
	local layersPanel = getLayersPanel()

	if not layersPanel or layersPanel:isDestroyed() then
		return
	end

	local layerSelector = layersPanel:getParent()

	local function onWheel(_, mousePos, direction)
		if direction == MouseWheelUp then
			Cyclopedia.setVirtualFloor(virtualFloor - 1)
		elseif direction == MouseWheelDown then
			Cyclopedia.setVirtualFloor(virtualFloor + 1)
		end

		return true
	end

	function layersPanel.onMousePress(self, mousePos, button)
		if button ~= MouseLeftButton then
			return false
		end

		self._floorDragActive = true

		if not g_ui.isMouseGrabbed() then
			self:grabMouse()
			self._floorDragGrabbed = true
		end

		Cyclopedia.setVirtualFloor(floorFromMousePos(self, mousePos))

		return true
	end

	function layersPanel.onMouseMove(self, mousePos, mouseMoved)
		if not self._floorDragActive then
			return false
		end

		Cyclopedia.setVirtualFloor(floorFromMousePos(self, mousePos))

		return true
	end

	function layersPanel.onMouseRelease(self, mousePos, button)
		if button ~= MouseLeftButton or not self._floorDragActive then
			return false
		end

		self._floorDragActive = nil

		if self._floorDragGrabbed then
			self._floorDragGrabbed = nil
			self:ungrabMouse()
		end

		return true
	end

	layersPanel.onMouseWheel = onWheel

	if layerSelector and not layerSelector:isDestroyed() and layerSelector ~= layersPanel then
		layerSelector.onMouseWheel = onWheel
	end
end

local function getCyclopediaMinimap()
	if not UI then
		return nil
	end

	return UI:recursiveGetChildById("minimap")
end

local function getAreaInfoPanel()
	return UI and UI:recursiveGetChildById("AreaBase") or nil
end

local function clearAreaLabelWidgets()
	for _, entry in pairs(areaLabelWidgets) do
		local label = entry.widget or entry

		if label and not label:isDestroyed() then
			label:destroy()
		end
	end

	areaLabelWidgets = {}
end

local function isAreaLabelAvailableOnFloor(labelFloor, visibleFloor)
	return labelFloor == visibleFloor or visibleFloor < CYCLOPEDIA_GROUND_FLOOR and labelFloor == CYCLOPEDIA_GROUND_FLOOR
end

local function getAreaLabelDisplayPosition(position, visibleFloor)
	if position.z == visibleFloor then
		return position
	end

	local floorOffset = CYCLOPEDIA_GROUND_FLOOR - visibleFloor

	return {
		x = position.x + floorOffset,
		y = position.y + floorOffset,
		z = visibleFloor
	}
end

local function getAreaSelectionPosition(position)
	if not position or position.z >= CYCLOPEDIA_GROUND_FLOOR then
		return position
	end

	local floorOffset = CYCLOPEDIA_GROUND_FLOOR - position.z

	return {
		x = position.x - floorOffset,
		y = position.y - floorOffset,
		z = CYCLOPEDIA_GROUND_FLOOR
	}
end

local function updateAreaLabelAppearance()
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	local scale = minimap:getScale()
	local transitionRange = CYCLOPEDIA_LABEL_TRANSITION_END_SCALE - CYCLOPEDIA_LABEL_TRANSITION_START_SCALE
	local subareaOpacity = math.max(0, math.min(1, (scale - CYCLOPEDIA_LABEL_TRANSITION_START_SCALE) / transitionRange))
	-- we do not fade the main regions out completely: once zoomed in to subareas we still want
	-- to see which region we are in
	local areaOpacity = math.max(0.35, 1 - subareaOpacity)
	local cameraPosition = minimap:getCameraPosition()
	local visibleFloor = cameraPosition and cameraPosition.z or -1

	for _, entry in pairs(areaLabelWidgets) do
		local label = entry.widget

		if label and not label:isDestroyed() then
			local opacity = entry.data.areaType == CYCLOPEDIA_AREA_TYPE_SUBAREA and subareaOpacity or areaOpacity
			local visible = entry.displayFloor == visibleFloor and isAreaLabelAvailableOnFloor(entry.data.position.z, visibleFloor) and opacity > 0.01
			local color = entry.data.areaType == CYCLOPEDIA_AREA_TYPE_AREA and entry.data.id == selectedAreaId and CYCLOPEDIA_AREA_LABEL_SELECTED_COLOR or entry.data.areaType == CYCLOPEDIA_AREA_TYPE_AREA and CYCLOPEDIA_AREA_LABEL_COLOR or CYCLOPEDIA_SUBAREA_LABEL_COLOR

			if entry.opacity ~= opacity then
				label:setOpacity(opacity)

				entry.opacity = opacity
			end

			if entry.color ~= color then
				label:setColor(color)

				entry.color = color
			end

			if entry.visible ~= visible then
				label:setVisible(visible)

				entry.visible = visible
			end
		end
	end

	-- This function reconstructs label visibility solely from floor and opacity, so it WIPED OUT
	-- the effect of hideOverlappingAreaLabels. And since it is the last callback of the smooth zoom
	-- animation, after every zoom step the area names came back overlapping each other. After
	-- restoring visibility we therefore have to hide the colliding ones again.
	if hideOverlappingAreaLabels then
		hideOverlappingAreaLabels()
	end
end

local function getAreaData(areaId)
	local data = areaDataById[areaId]

	if data then
		return data
	end

	if areaId == 0 or not g_minimap.getCyclopediaAreaName then
		return nil
	end

	local parentId = g_minimap.getCyclopediaParentAreaId and g_minimap.getCyclopediaParentAreaId(areaId) or 0

	return {
		id = areaId,
		name = g_minimap.getCyclopediaAreaName(areaId),
		areaType = parentId ~= 0 and CYCLOPEDIA_AREA_TYPE_SUBAREA or CYCLOPEDIA_AREA_TYPE_AREA
	}
end

local function applyAreaPanelState(panel, data)
	if not panel or not data then
		return
	end

	local isSubarea = data.areaType == CYCLOPEDIA_AREA_TYPE_SUBAREA

	setPanelChildrenVisible(panel, {
		"areaName",
		"discoveryProgress",
		"respawnRateTitle",
		"respawnRateValue",
		"donationRow"
	}, areaPanelExpanded)

	local description = panel:recursiveGetChildById("areaDescription")
	local status = panel:recursiveGetChildById("discoveryStatus")

	if description then
		description:setVisible(areaPanelExpanded and isSubarea)
	end

	if status then
		status:setVisible(areaPanelExpanded and isSubarea)
	end

	local expandedHeight = isSubarea and CYCLOPEDIA_SUBAREA_PANEL_HEIGHT or CYCLOPEDIA_AREA_PANEL_HEIGHT

	applySectionFrameState(panel, areaPanelExpanded)
	panel:setHeight(areaPanelExpanded and expandedHeight or CYCLOPEDIA_SECTION_COLLAPSED_HEIGHT)
	setSectionToggleState(panel, "areaToggleButton", areaPanelExpanded)
end

local function setElidedAreaPanelText(widget, name)
	name = name or ""

	widget:setText(name)

	local availableWidth = widget:getWidth() - widget:getPaddingLeft() - widget:getPaddingRight()

	if availableWidth >= widget:getTextSize().width then
		return
	end

	local ellipsis = "..."
	local low, high = 0, #name
	local displayName = ellipsis

	while low <= high do
		local middle = math.floor((low + high) / 2)
		local candidate = name:sub(1, middle) .. ellipsis

		widget:setText(candidate)

		if availableWidth >= widget:getTextSize().width then
			displayName = candidate
			low = middle + 1
		else
			high = middle - 1
		end
	end

	widget:setText(displayName)
end

local function getSelectedDonationAreaId()
	local data = getAreaData(selectedAreaId)

	if not data then
		return 0
	end

	if data.areaType == CYCLOPEDIA_AREA_TYPE_AREA then
		return data.id
	end

	return selectedParentAreaId
end

local function sendCyclopediaMapAction(action, areaId, donationAmount)
	if not areaId or areaId <= 0 or areaId > 65535 then
		return false
	end

	local protocolGame = g_game.getProtocolGame()

	if not protocolGame then
		return false
	end

	local message = OutputMessage.create()

	message:addByte(CYCLOPEDIA_MAP_OPCODE)
	message:addByte(action)
	message:addU16(areaId)

	if action == CYCLOPEDIA_MAP_ACTION_DONATE then
		if not donationAmount or donationAmount <= 0 or donationAmount > UINT32_MAX then
			return false
		end

		message:addU32(donationAmount)
	end

	protocolGame:send(message)

	return true
end

local function setDonationAmountEditText(edit, text)
	if not edit or edit:getText() == text then
		return
	end

	updatingDonationAmountEdit = true

	edit:setText(text)

	updatingDonationAmountEdit = false
end

local function updateDonationAmountEdit(edit)
	local hasAmount = selectedDonationAmount > 0

	setDonationAmountEditText(edit, hasAmount and tostring(selectedDonationAmount) or "")
	edit:setColor("#BDBDBD")
	edit:setTooltip(hasAmount and tr("%s gold", comma_value(selectedDonationAmount)) or "")
end

local function updateAreaDonationButtons(panel)
	local areaId = getSelectedDonationAreaId()

	if selectedDonationAreaId ~= areaId then
		selectedDonationAreaId = areaId
		selectedDonationAmount = 0
	end

	local hasArea = areaId ~= 0
	local amountEdit = panel:recursiveGetChildById("amountEdit")
	local donateButton = panel:recursiveGetChildById("donateButton")

	updateDonationAmountEdit(amountEdit)
	amountEdit:setEnabled(hasArea)
	donateButton:setEnabled(hasArea and selectedDonationAmount > 0 and g_game.getProtocolGame() ~= nil)
end

local function updateAreaInfoPanel()
	local panel = getAreaInfoPanel()
	local data = getAreaData(selectedAreaId)

	if not panel or not data or data.name == "" then
		if panel then
			panel:setVisible(false)
			panel:setHeight(0)
		end

		return
	end

	local isSubarea = data.areaType == CYCLOPEDIA_AREA_TYPE_SUBAREA
	local parentData = isSubarea and getAreaData(selectedParentAreaId) or data

	panel:setText(isSubarea and tr("Subarea") or tr("Area"))
	setElidedAreaPanelText(panel:recursiveGetChildById("areaName"), parentData and parentData.name or data.name)
	panel:recursiveGetChildById("discoveryPercent"):setText("0%")

	local description = panel:recursiveGetChildById("areaDescription")

	setElidedAreaPanelText(description, data.name)
	updateAreaDonationButtons(panel)
	applyAreaPanelState(panel, data)
	panel:setVisible(true)
end

function Cyclopedia.toggleMapSection(section)
	if section == "display" then
		displayPanelExpanded = not displayPanelExpanded

		applyDisplayPanelState()
	elseif section == "navigation" then
		navigationPanelExpanded = not navigationPanelExpanded

		applyNavigationPanelState()
	elseif section == "area" then
		areaPanelExpanded = not areaPanelExpanded

		updateAreaInfoPanel()
	else
		return false
	end

	Cyclopedia.saveMapConfiguration()

	return true
end

local function setSelectedArea(areaId, skipConfigurationSave)
	areaId = areaId or 0

	if selectedAreaId == areaId then
		return
	end

	selectedAreaId = areaId

	local data = getAreaData(areaId)

	if data and data.areaType == CYCLOPEDIA_AREA_TYPE_AREA then
		selectedParentAreaId = areaId
	elseif data and data.areaType == CYCLOPEDIA_AREA_TYPE_SUBAREA and data.parentAreaId then
		-- we take the parent from OUR OWN data (setupCyclopediaAreas stores parentAreaId).
		-- g_minimap.getCyclopediaParentAreaId is a function from the ported client that our
		-- engine does not have, so that branch never worked and the subarea was left without a region.
		selectedParentAreaId = data.parentAreaId
	elseif areaId ~= 0 and g_minimap.getCyclopediaParentAreaId then
		selectedParentAreaId = g_minimap.getCyclopediaParentAreaId(areaId)
	else
		selectedParentAreaId = 0
	end

	if areaId > 0 then
		sendCyclopediaMapAction(CYCLOPEDIA_MAP_ACTION_SELECT, areaId)
	end

	local minimap = getCyclopediaMinimap()

	if minimap and minimap.setHighlightedArea then
		minimap:setHighlightedArea(areaId)
	elseif cyclopediaSatelliteReady and minimap and g_satelliteMap and g_satelliteMap.clearHighlight then
		-- our exe has no UIMinimap:setHighlightedArea - we highlight via g_satelliteMap
		-- using subarea masks (satellite/zones/<sid>.png); C++ pulses the alpha like the original
		g_satelliteMap.clearHighlight()

		local data = areaDataById[areaId]

		if data and data.maskRects then
			g_satelliteMap.setHighlightColor("#FFD400")

			for _, m in ipairs(data.maskRects) do
				g_satelliteMap.addHighlightMask(m.x, m.y, m.w, m.h, m.sid)
			end
		end
	elseif g_satelliteMap and g_satelliteMap.clearHighlight then
		g_satelliteMap.clearHighlight()
	end

	updateAreaInfoPanel()
	updateAreaLabelAppearance()

	if not skipConfigurationSave then
		Cyclopedia.saveMapConfiguration()
	end
end

function Cyclopedia.onMapAreaAmountTextChange(widget, text)
	if updatingDonationAmountEdit then
		return
	end

	local filtered = text:gsub("[^0-9]", ""):sub(1, 10)
	local amount = math.floor(tonumber(filtered) or 0)

	if amount > UINT32_MAX then
		amount = UINT32_MAX
		filtered = tostring(amount)
	end

	selectedDonationAmount = amount

	if filtered ~= text then
		setDonationAmountEditText(widget, filtered)
		widget:setCursorPos(-1)
	end

	widget:setColor("#BDBDBD")
	widget:setTooltip(selectedDonationAmount > 0 and tr("%s gold", comma_value(selectedDonationAmount)) or "")

	local panel = getAreaInfoPanel()

	if panel then
		panel:recursiveGetChildById("donateButton"):setEnabled(getSelectedDonationAreaId() ~= 0 and selectedDonationAmount > 0 and g_game.getProtocolGame() ~= nil)
	end
end

function Cyclopedia.onMapAreaDonateClick()
	local areaId = getSelectedDonationAreaId()
	local donationAmount = selectedDonationAmount
	local areaData = getAreaData(areaId)

	if areaId == 0 or donationAmount <= 0 or not areaData then
		return false
	end

	if areaDonationConfirmWindow and not areaDonationConfirmWindow:isDestroyed() then
		areaDonationConfirmWindow:destroy()
	end

	areaDonationConfirmWindow = nil

	local function closeConfirmation()
		if areaDonationConfirmWindow and not areaDonationConfirmWindow:isDestroyed() then
			areaDonationConfirmWindow:destroy()
		end

		areaDonationConfirmWindow = nil
	end

	local function confirmDonation()
		closeConfirmation()

		if sendCyclopediaMapAction(CYCLOPEDIA_MAP_ACTION_DONATE, areaId, donationAmount) then
			selectedDonationAmount = 0

			updateAreaInfoPanel()
		end
	end

	local function cancelDonation()
		closeConfirmation()
	end

	areaDonationConfirmWindow = displayGeneralBox(tr("Information"), tr("Do you really want to donate %s gold for %s?", comma_value(donationAmount), areaData.name), {
		{
			text = tr("No"),
			callback = cancelDonation
		},
		{
			text = tr("Yes"),
			callback = confirmDonation
		}
	}, confirmDonation, cancelDonation)

	return true
end

local function formatAreaLabel(name, isSubarea)
	if not isSubarea or #name <= 11 then
		return name
	end

	local middle = #name / 2
	local bestIndex
	local bestDistance = math.huge

	for index in name:gmatch("() ") do
		local distance = math.abs(index - middle)

		if distance < bestDistance then
			bestIndex = index
			bestDistance = distance
		end
	end

	if not bestIndex then
		return name
	end

	return name:sub(1, bestIndex - 1) .. "\n" .. name:sub(bestIndex + 1)
end

local function refreshAreaLabels()
	areaLabelRefreshEvent = nil

	local minimap = getCyclopediaMinimap()

	if not minimap or not areaLabelData then
		return
	end

	local bounds = minimap:getVisibleTileBounds()

	if not bounds then
		return
	end

	for _, data in ipairs(areaLabelData) do
		local pos = data.position
		local displayPos = isAreaLabelAvailableOnFloor(pos.z, bounds.z) and getAreaLabelDisplayPosition(pos, bounds.z) or nil

		if displayPos and displayPos.x >= bounds.minX - CYCLOPEDIA_LABEL_PRELOAD_TILES and displayPos.x <= bounds.maxX + CYCLOPEDIA_LABEL_PRELOAD_TILES and displayPos.y >= bounds.minY - CYCLOPEDIA_LABEL_PRELOAD_TILES and displayPos.y <= bounds.maxY + CYCLOPEDIA_LABEL_PRELOAD_TILES then
			local entry = areaLabelWidgets[data.id]
			local label = entry and entry.widget or nil

			if label and not label:isDestroyed() and entry.displayFloor ~= bounds.z then
				label:destroy()

				label = nil
				entry = nil
			end

			if not label or label:isDestroyed() then
				label = g_ui.createWidget("CyclopediaMapAreaLabel", minimap)

				label:setId("cyclopediaAreaLabel" .. data.id)

				if data.areaType == CYCLOPEDIA_AREA_TYPE_SUBAREA then
					label:setFont(CYCLOPEDIA_SUBAREA_LABEL_FONT)
					label:setColor(CYCLOPEDIA_SUBAREA_LABEL_COLOR)
				else
					label:setFont(CYCLOPEDIA_AREA_LABEL_FONT)
					label:setColor(CYCLOPEDIA_AREA_LABEL_COLOR)
					label:setPhantom(false)

					label.cyclopediaAreaId = data.id

					function label.onMouseRelease(widget, mousePos, button)
						if button == MouseLeftButton then
							setSelectedArea(widget.cyclopediaAreaId)

							return true
						end

						return false
					end
				end

				label:setText(formatAreaLabel(data.name, data.areaType == CYCLOPEDIA_AREA_TYPE_SUBAREA))
				minimap:centerInPosition(label, displayPos)

				areaLabelWidgets[data.id] = {
					widget = label,
					data = data,
					displayFloor = bounds.z
				}
			end
		end
	end

	updateAreaLabelAppearance()
	hideOverlappingAreaLabels()
end

-- labels built from SatelliteZones can overlap (e.g. "Thais City" lies in the middle of
-- "Thais Surroundings") - we keep the more important one (AREA before SUBAREA), hide the rest
function hideOverlappingAreaLabels()
	local placed = {}
	local entries = {}

	for _, entry in pairs(areaLabelWidgets) do
		local label = entry.widget

		if label and not label:isDestroyed() and entry.visible then
			entries[#entries + 1] = entry
		end
	end

	table.sort(entries, function(a, b)
		local aArea = a.data.areaType == CYCLOPEDIA_AREA_TYPE_AREA and 1 or 0
		local bArea = b.data.areaType == CYCLOPEDIA_AREA_TYPE_AREA and 1 or 0

		if aArea ~= bArea then
			return aArea > bArea
		end

		return (a.data.name or "") < (b.data.name or "")
	end)

	for _, entry in ipairs(entries) do
		local label = entry.widget
		local rect = label:getRect()
		local collides = false

		for _, other in ipairs(placed) do
			if rect.x < other.x + other.width and other.x < rect.x + rect.width and rect.y < other.y + other.height and other.y < rect.y + rect.height then
				collides = true

				break
			end
		end

		if collides then
			label:setVisible(false)

			entry.visible = false
		else
			placed[#placed + 1] = rect
		end
	end
end

local function scheduleAreaLabelRefresh()
	if areaLabelRefreshEvent then
		removeEvent(areaLabelRefreshEvent)
	end

	areaLabelRefreshEvent = scheduleEvent(refreshAreaLabels, 35)
end

local function clearCyclopediaAreaState()
	if areaLabelRefreshEvent then
		removeEvent(areaLabelRefreshEvent)

		areaLabelRefreshEvent = nil
	end

	if areaDonationConfirmWindow and not areaDonationConfirmWindow:isDestroyed() then
		areaDonationConfirmWindow:destroy()
	end

	areaDonationConfirmWindow = nil

	cyclopediaSatelliteReady = false
	lastLoadedSatelliteDir = nil

	clearAreaLabelWidgets()

	areaLabelData = nil
	areaDataById = {}
	selectedAreaId = -1
	selectedParentAreaId = 0
	selectedDonationAreaId = 0
	selectedDonationAmount = 0
end

-- our exe has no g_minimap.getCyclopediaSubareaAt - we determine the area under the cursor
-- from the SatelliteZones rectangles (zones_data.lua)
local function cyclopediaAreaIdAtTile(tile)
	if not tile or not SatelliteZones then
		return 0
	end

	-- This used to return the id of the MAIN region, so a subarea could not be selected at all.
	-- Now we look for the specific SUBAREA (id = 100000 + index, exactly how setupCyclopediaAreas
	-- builds them). Region rectangles overlap each other, so the first hit alone
	-- can be wrong - we pick the candidate with the SMALLEST rectangle, and when a shape mask
	-- exists, we resolve with it definitively (g_satelliteMap.maskContains).
	local bestIndex, bestArea = nil, math.huge

	for i, z in ipairs(SatelliteZones) do
		for _, r in ipairs(z.rects or {}) do
			if tile.x >= r.x and tile.x < r.x + r.w and tile.y >= r.y and tile.y < r.y + r.h then
				if cyclopediaSatelliteReady and z.sid and g_satelliteMap and g_satelliteMap.maskContains then
					local ok, hit = pcall(g_satelliteMap.maskContains, z.sid, r.x, r.y, tile.x, tile.y)

					if ok and hit then
						return 100000 + i, z.areaId
					end
				end

				local rectArea = r.w * r.h

				if rectArea < bestArea then
					bestArea = rectArea
					bestIndex = i
				end
			end
		end
	end

	if bestIndex then
		return 100000 + bestIndex, SatelliteZones[bestIndex].areaId
	end

	return 0
end

local function zoneRectsBounds(rects)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge

	for _, r in ipairs(rects or {}) do
		minX = math.min(minX, r.x)
		minY = math.min(minY, r.y)
		maxX = math.max(maxX, r.x + r.w)
		maxY = math.max(maxY, r.y + r.h)
	end

	return minX, minY, maxX, maxY
end

local function setupCyclopediaAreas()
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	areaLabelData = {}
	areaDataById = {}

	if g_minimap.getCyclopediaAreaLabels then
		for _, row in ipairs(g_minimap.getCyclopediaAreaLabels()) do
			local data = {
				id = row[1],
				name = row[2],
				position = row[3],
				areaType = row[4]
			}

			areaLabelData[#areaLabelData + 1] = data
			areaDataById[data.id] = data
		end
	elseif SatelliteZones then
		-- our exe has no getCyclopediaAreaLabels: we build area/subarea labels from our
		-- own SatelliteZones (zones_data.lua). The AREA label is clickable (setSelectedArea
		-- -> unlocks respawn donations), the SUBAREA one is descriptive only.
		local areaAccum = {}

		for i, z in ipairs(SatelliteZones) do
			local minX, minY, maxX, maxY = zoneRectsBounds(z.rects)

			local subData = {
				id = 100000 + i,
				name = z.sub,
				position = {
					x = math.floor((minX + maxX) / 2),
					y = math.floor((minY + maxY) / 2),
					z = CYCLOPEDIA_GROUND_FLOOR
				},
				areaType = CYCLOPEDIA_AREA_TYPE_SUBAREA,
				sid = z.sid,
				rects = z.rects,
				-- without this, selecting a subarea had nothing to highlight: the block that draws
				-- the highlight reads only maskRects, which until now only the main regions had
				maskRects = (function()
					local m = {}

					for _, r in ipairs(z.rects or {}) do
						m[#m + 1] = { x = r.x, y = r.y, w = r.w, h = r.h, sid = z.sid }
					end

					return m
				end)(),
				parentAreaId = z.areaId
			}

			areaLabelData[#areaLabelData + 1] = subData
			areaDataById[subData.id] = subData

			local a = areaAccum[z.areaId]

			if not a then
				a = {
					name = z.area,
					minX = math.huge,
					minY = math.huge,
					maxX = -math.huge,
					maxY = -math.huge,
					rects = {},
					maskRects = {}
				}
				areaAccum[z.areaId] = a
			end

			a.minX = math.min(a.minX, minX)
			a.minY = math.min(a.minY, minY)
			a.maxX = math.max(a.maxX, maxX)
			a.maxY = math.max(a.maxY, maxY)

			for _, r in ipairs(z.rects or {}) do
				a.rects[#a.rects + 1] = r
				-- every rect carries the subarea mask (satellite/zones/<sid>.png), so the area
				-- highlight has the shape of the coastline rather than a rectangle
				a.maskRects[#a.maskRects + 1] = { x = r.x, y = r.y, w = r.w, h = r.h, sid = z.sid }

				-- we remember the LARGEST fragment of the region: it determines the label placement
				local rectArea = r.w * r.h

				if rectArea > (a.bestRectArea or -1) then
					a.bestRectArea = rectArea
					a.bestRect = r
				end
			end
		end

		for areaId, a in pairs(areaAccum) do
			local areaData = {
				id = areaId,
				name = a.name,
				-- Was: the center of the rectangle covering ALL subareas of the region. For regions
				-- scattered across several islands that center falls in the sea, far from anything -
				-- hence the main region names landed in wrong places when zoomed out.
				-- Now we take the center of the LARGEST fragment, i.e. the dominant landmass.
				position = (function()
					local best = a.bestRect

					if best then
						return {
							x = math.floor(best.x + best.w / 2),
							y = math.floor(best.y + best.h / 2),
							z = CYCLOPEDIA_GROUND_FLOOR
						}
					end

					return {
						x = math.floor((a.minX + a.maxX) / 2),
						y = math.floor((a.minY + a.maxY) / 2),
						z = CYCLOPEDIA_GROUND_FLOOR
					}
				end)(),
				areaType = CYCLOPEDIA_AREA_TYPE_AREA,
				rects = a.rects,
				maskRects = a.maskRects
			}

			areaLabelData[#areaLabelData + 1] = areaData
			areaDataById[areaId] = areaData
		end
	end

	if not minimap._cyclopediaAreaHooked then
		local baseZoomChange = minimap.onZoomChange

		function minimap.onZoomChange(widget, zoom, oldZoom)
			if baseZoomChange then
				baseZoomChange(widget, zoom, oldZoom)
			end

			scheduleAreaLabelRefresh()
		end

		local baseSmoothZoomScaleChange = minimap.onSmoothZoomScaleChange

		function minimap.onSmoothZoomScaleChange(widget, scale)
			if baseSmoothZoomScaleChange then
				baseSmoothZoomScaleChange(widget, scale)
			end

			updateAreaLabelAppearance()
		end

		local baseCameraChange = minimap.onCameraPositionChange

		function minimap.onCameraPositionChange(widget, position, oldPosition)
			if baseCameraChange then
				baseCameraChange(widget, position, oldPosition)
			end

			if position and oldPosition and position.z ~= oldPosition.z then
				if areaLabelRefreshEvent then
					removeEvent(areaLabelRefreshEvent)

					areaLabelRefreshEvent = nil
				end

				refreshAreaLabels()
			else
				updateAreaLabelAppearance()
				scheduleAreaLabelRefresh()
			end
		end

		local baseMouseRelease = minimap.onMouseRelease

		function minimap.onMouseRelease(widget, mousePos, button)
			local isGmTeleport = button == MouseLeftButton and g_game.getClientVersion() > 1288 and g_keyboard.isCtrlPressed() and g_keyboard.isShiftPressed()

			if isGmTeleport and baseMouseRelease then
				return baseMouseRelease(widget, mousePos, button)
			end

			if button == MouseLeftButton and widget.allowNextRelease then
				local tile = getAreaSelectionPosition(widget:getTilePosition(mousePos))
				local areaId = 0

				if tile then
					if g_minimap.getCyclopediaSubareaAt then
						areaId = g_minimap.getCyclopediaSubareaAt(tile) or 0
					end

					if areaId == 0 then
						areaId = cyclopediaAreaIdAtTile(tile)
					end
				end

				if areaId > 0 then
					setSelectedArea(areaId)
				end
			end

			if baseMouseRelease then
				return baseMouseRelease(widget, mousePos, button)
			end

			return false
		end

		minimap._cyclopediaAreaHooked = true
	end

	local restoredAreaId = selectedAreaId

	selectedAreaId = -1

	local restoredAreaData = restoredAreaId and restoredAreaId > 0 and getAreaData(restoredAreaId) or nil

	if restoredAreaData and restoredAreaData.name ~= "" then
		setSelectedArea(restoredAreaId, true)
	else
		setSelectedArea(0, true)
	end

	refreshAreaLabels()
end

local function getMainMinimapZoom()
	if not modules.game_minimap or not modules.game_minimap.getMiniMapUi then
		return nil
	end

	local mainMinimap = modules.game_minimap.getMiniMapUi()

	if mainMinimap and mainMinimap.getZoom then
		return mainMinimap:getZoom()
	end

	return nil
end

local function applyCyclopediaDefaultZoom(minimap)
	if not minimap or not minimap.getZoom or not minimap.setZoom then
		return
	end

	-- Previously the zoom was COPIED from the sidebar minimap, and that one is remembered between
	-- sessions. When the player had it zoomed out (zoom -3 and below), the Cyclopedia opened at scale
	-- 1/8 and the whole world shrank to a speck, with all area names blending into one.
	-- Scale is computed as 2^zoom, and the satellite draws 1 tile = scale pixels, so with a window
	-- of ~491x413 px zoom -1 (scale 0.5) gives a viewport of ~982x826 tiles, i.e. exactly a region the
	-- size of Carlin + Ab'Dendriel + Thais. It is also the LAST level at which the engine still draws
	-- the sharpest tile LOD, city names and POI markers (satellitemap.cpp: thresholds 0.4 and 0.3).
	local minZoom = minimap:getMinZoom()
	local targetZoom = math.max(minZoom, CYCLOPEDIA_MAP_DEFAULT_ZOOM - CYCLOPEDIA_MAP_ZOOM_OFFSET)

	if targetZoom == minimap:getZoom() then
		return
	end

	local savedSettingZoom = minimap.zoomMinimap

	minimap:setZoom(targetZoom)

	minimap.zoomMinimap = savedSettingZoom
end

local function getLevelScrollBar()
	if not UI then
		return nil
	end

	return UI:recursiveGetChildById("LevelScrollBar")
end

local function getMarkList()
	if not UI then
		return nil
	end

	return UI:recursiveGetChildById("MarkList")
end

local function getShowAllBox()
	if not UI then
		return nil
	end

	return UI:recursiveGetChildById("ShowAllBox")
end

local function isMapFlagFilterButton(widget)
	if not widget or not widget.getId then
		return false
	end

	local markerId = tonumber(widget:getId())

	return markerId ~= nil and markerId >= 0 and markerId <= 19
end

local function forEachMapFlagFilterButton(callback)
	local markList = getMarkList()

	if not markList then
		return
	end

	for _, child in ipairs(markList:getChildren()) do
		if isMapFlagFilterButton(child) then
			callback(child)
		end
	end
end

local function ensureMapConfigDir()
	if LoadedPlayer and LoadedPlayer.ensureCharacterDir then
		if LoadedPlayer.cacheFromLocalPlayer then
			LoadedPlayer:cacheFromLocalPlayer()
		end

		return LoadedPlayer:ensureCharacterDir()
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return nil
	end

	pcall(function()
		g_resources.makeDir("/characterdata")
	end)

	local characterDir = string.format("/characterdata/%d", player:getId())

	pcall(function()
		g_resources.makeDir(characterDir)
	end)

	return characterDir
end

local function getMapConfigFilePath()
	local characterDir = ensureMapConfigDir()

	if not characterDir then
		return nil
	end

	return characterDir .. "/" .. MAP_CONFIG_FILE_NAME
end

local function getDefaultMapConfiguration()
	return {
		showAreaAndSubAreaInfo = true,
		shadingValue = 0,
		surfaceView = false,
		showPassageMarker = false,
		showNavigation = true,
		showNPCMarker = false,
		showHouseMarker = false,
		showDisplay = true,
		selectedMarkers = {}
	}
end

local function getMarkFilterButton(markerId)
	local markList = getMarkList()

	if not markList then
		return nil
	end

	return markList:getChildById(tostring(markerId))
end

local function collectSelectedMarkers()
	local selectedMarkers = {}

	forEachMapFlagFilterButton(function(button)
		if button:isChecked() then
			selectedMarkers[#selectedMarkers + 1] = tonumber(button:getId())
		end
	end)
	table.sort(selectedMarkers)

	return selectedMarkers
end

local function buildMapConfiguration()
	local scroll = getLevelScrollBar()
	local shadingValue = 0

	if scroll then
		shadingValue = scroll:getValue() / 100
	end

	local npcMarker = getMarkFilterButton(20)
	local houseMarker = getMarkFilterButton(21)
	local passageMarker = getMarkFilterButton("passage")
	local surfaceCheck = UI and UI:recursiveGetChildById("SurfaceCheck")

	return {
		areaID = selectedAreaId > 0 and selectedAreaId or nil,
		selectedMarkers = collectSelectedMarkers(),
		shadingValue = shadingValue,
		showAreaAndSubAreaInfo = areaPanelExpanded,
		showDisplay = displayPanelExpanded,
		showHouseMarker = houseMarker and houseMarker:isChecked() or false,
		showNPCMarker = npcMarker and npcMarker:isChecked() or false,
		showNavigation = navigationPanelExpanded,
		showPassageMarker = passageMarker and passageMarker:isChecked() or false,
		surfaceView = surfaceCheck and surfaceCheck:isChecked() or false
	}
end

function Cyclopedia.saveMapConfiguration()
	if loadingMapConfig or not UI then
		return
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	local file = getMapConfigFilePath()

	if not file then
		return
	end

	local config = buildMapConfiguration()
	local status, contents = pcall(function()
		return json.encode(config, 2)
	end)

	if not status then
		g_logger.error("cyclopedia map: failed to save configuration. " .. tostring(contents))

		return
	end

	g_resources.writeFileContents(file, contents)
end

function Cyclopedia.loadMapConfiguration()
	if not UI then
		return
	end

	local config = getDefaultMapConfiguration()
	local file = getMapConfigFilePath()

	if file and g_resources.fileExists(file) then
		local status, loaded = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if status and type(loaded) == "table" then
			if type(loaded.areaID) == "number" then
				local areaId = math.floor(loaded.areaID)

				if areaId > 0 and areaId <= 65535 then
					config.areaID = areaId
				end
			end

			if type(loaded.selectedMarkers) == "table" then
				config.selectedMarkers = loaded.selectedMarkers
			end

			if type(loaded.shadingValue) == "number" then
				config.shadingValue = math.max(0, math.min(1, loaded.shadingValue))
			end

			if type(loaded.showHouseMarker) == "boolean" then
				config.showHouseMarker = loaded.showHouseMarker
			end

			if type(loaded.showNPCMarker) == "boolean" then
				config.showNPCMarker = loaded.showNPCMarker
			end

			if type(loaded.showPassageMarker) == "boolean" then
				config.showPassageMarker = loaded.showPassageMarker
			end

			if type(loaded.showAreaAndSubAreaInfo) == "boolean" then
				config.showAreaAndSubAreaInfo = loaded.showAreaAndSubAreaInfo
			end

			if type(loaded.showDisplay) == "boolean" then
				config.showDisplay = loaded.showDisplay
			end

			if type(loaded.showNavigation) == "boolean" then
				config.showNavigation = loaded.showNavigation
			end

			if type(loaded.surfaceView) == "boolean" then
				config.surfaceView = loaded.surfaceView
			end
		elseif not status then
			g_logger.error("cyclopedia map: failed to load configuration. " .. tostring(loaded))
		end
	end

	loadingMapConfig = true

	local enabledMarkers = {}

	for _, markerId in ipairs(config.selectedMarkers) do
		if type(markerId) == "number" then
			enabledMarkers[markerId] = true
		end
	end

	forEachMapFlagFilterButton(function(button)
		local markerId = tonumber(button:getId())

		button:setChecked(enabledMarkers[markerId] == true)
	end)

	local npcMarker = getMarkFilterButton(20)

	if npcMarker then
		npcMarker:setChecked(config.showNPCMarker)
	end

	local houseMarker = getMarkFilterButton(21)

	if houseMarker then
		houseMarker:setChecked(config.showHouseMarker)
	end

	local passageMarker = getMarkFilterButton("passage")

	if passageMarker then
		passageMarker:setChecked(config.showPassageMarker)
	end

	local surfaceCheck = UI:recursiveGetChildById("SurfaceCheck")

	if surfaceCheck then
		surfaceCheck:setChecked(config.surfaceView)
	end

	local mapCheck = UI:recursiveGetChildById("MapCheck")

	if mapCheck then
		mapCheck:setChecked(not config.surfaceView)
	end

	local scroll = getLevelScrollBar()

	if scroll then
		scroll:setValue(math.floor(config.shadingValue * 100 + 0.5))
	end

	selectedAreaId = config.areaID or -1
	selectedParentAreaId = 0
	displayPanelExpanded = config.showDisplay
	navigationPanelExpanded = config.showNavigation
	areaPanelExpanded = config.showAreaAndSubAreaInfo

	applyDisplayPanelState()
	applyNavigationPanelState()

	loadingMapConfig = false

	Cyclopedia.syncShowAllBox()
	Cyclopedia.applyMapFlagFilter()
	Cyclopedia.applyCyclopediaRenderMode()
end

local function prefetchCyclopediaMapCenter()
	local minimap = getCyclopediaMinimap()

	if not minimap or not g_minimap or not g_minimap.isOfficialLoaded then
		return
	end

	if not g_minimap.isOfficialLoaded() or not g_minimap.loadCyclopediaMapChunk then
		return
	end

	local pos = minimap:getCameraPosition()

	if not pos or pos.z > 7 then
		return
	end

	local viewMode = CYCLOPEDIA_VIEW_SURFACE

	if minimap.getCyclopediaViewMode then
		viewMode = minimap:getCyclopediaViewMode()
	end

	if viewMode ~= CYCLOPEDIA_VIEW_SURFACE and viewMode ~= CYCLOPEDIA_VIEW_MAP then
		return
	end

	for _, scaleFactor in ipairs({
		64,
		32,
		16
	}) do
		if g_minimap.loadCyclopediaMapChunk(pos.x, pos.y, pos.z, scaleFactor, viewMode) then
			break
		end
	end
end

function Cyclopedia.applyCyclopediaRenderMode()
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	-- our engine has no the ported client cyclopedia-draw mode, so we draw the map satellite-style
	-- (data/things/<version>/satellite). NOTE: the Surface/Map View switch does NOT change the
	-- drawing style - in Tibia it decides the FLOOR (see house.lua: isSurface = cameraZ <= 7).
	-- Disabling the satellite for "Map View" was a bug: bare ocean remained, because the regular
	-- minimap shows only what the player explored themselves.
	if not minimap.setDrawMode then
		local surfaceCheckFallback = UI and UI:recursiveGetChildById("SurfaceCheck")
		local useSurfaceFallback = surfaceCheckFallback and surfaceCheckFallback:isChecked() or false

		-- TWO DIFFERENT TILE SETS, because the engine has no Cyclopedia drawing mode (setDrawMode is
		-- ported client API which we do not have - that whole branch is dead).
		-- Surface View: satellite (terrain, 2 px per tile).
		-- Map View: classic Tibia palette with red building outlines, generated by
		-- tools/build_mapview_tiles.py from the unused minimap-32/minimap-64 files (1 px per tile,
		-- because the source has no minimap-16 equivalent).
		local tilesDir = getCyclopediaTilesDir(useSurfaceFallback)
		local cameraPos = minimap:getCameraPosition()

		if cameraPos then
			local player = g_game.getLocalPlayer()
			local playerPos = player and player:getPosition()
			local targetZ = useSurfaceFallback and 7 or (playerPos and playerPos.z or cameraPos.z)

			if targetZ ~= cameraPos.z then
				minimap:setCameraPosition({
					x = cameraPos.x,
					y = cameraPos.y,
					z = targetZ
				})
			end

			virtualFloor = targetZ
			refreshVirtualFloors()
		end

		syncCyclopediaSatelliteMode(minimap, tilesDir)
		Cyclopedia.updateLevelSeparatorState()

		return
	end

	minimap:setDrawMode(MINIMAP_DRAW_MODE_CYCLOPEDIA)

	local surfaceCheck = UI and UI:recursiveGetChildById("SurfaceCheck")
	local useSurface = surfaceCheck and surfaceCheck:isChecked()

	minimap:setCyclopediaViewMode(useSurface and CYCLOPEDIA_VIEW_SURFACE or CYCLOPEDIA_VIEW_MAP)

	if g_minimap.isOfficialLoaded and not g_minimap.isOfficialLoaded() then
		g_logger.warning("[Cyclopedia] Official map data not loaded (map.dat missing or corrupt)")
	end

	Cyclopedia.updateLevelSeparatorState()
	prefetchCyclopediaMapCenter()
end

local function onMapConfigurationChanged()
	Cyclopedia.saveMapConfiguration()
end

function Cyclopedia.onSurfaceViewChange(widget, checked)
	if loadingMapConfig then
		return
	end

	local mapCheck = UI and UI:recursiveGetChildById("MapCheck")

	if checked and mapCheck then
		mapCheck:setChecked(false)
	elseif not checked and mapCheck and not mapCheck:isChecked() then
		mapCheck:setChecked(true)
	end

	Cyclopedia.applyCyclopediaRenderMode()
	onMapConfigurationChanged()
end

function Cyclopedia.onMapViewChange(widget, checked)
	if loadingMapConfig then
		return
	end

	local surfaceCheck = UI and UI:recursiveGetChildById("SurfaceCheck")

	if checked and surfaceCheck then
		surfaceCheck:setChecked(false)
	elseif not checked and surfaceCheck and not surfaceCheck:isChecked() then
		surfaceCheck:setChecked(true)
	end

	Cyclopedia.applyCyclopediaRenderMode()
	onMapConfigurationChanged()
end

local function getMinimapViewFloor()
	local minimap = getCyclopediaMinimap()

	if minimap then
		local pos = minimap:getCameraPosition()

		if pos then
			return pos.z
		end
	end

	return virtualFloor
end

local function applyLevelSeparatorIntensity(scrollValue)
	local minimap = getCyclopediaMinimap()

	if not minimap or not minimap.setLevelSeparatorIntensity then
		return
	end

	if getMinimapViewFloor() < LEVEL_SEPARATOR_MIDDLE_FLOOR then
		local value = scrollValue or DEFAULT_LEVEL_SEPARATOR

		minimap:setLevelSeparatorIntensity(value / 100)
	else
		minimap:setLevelSeparatorIntensity(-1)
	end
end

function Cyclopedia.updateMinimapBackgroundColor()
	local minimap = getCyclopediaMinimap()

	if not minimap or not minimap.setColor then
		return
	end

	local floorZ = getMinimapViewFloor()

	if floorZ ~= CYCLOPEDIA_GROUND_FLOOR then
		minimap:setColor("black")

		return
	end

	local surfaceCheck = UI and UI:recursiveGetChildById("SurfaceCheck")
	local useSurface = surfaceCheck and surfaceCheck:isChecked()

	minimap:setColor(useSurface and CYCLOPEDIA_BG_SURFACE_Z7 or CYCLOPEDIA_BG_MAP_Z7)
end

function Cyclopedia.updateLevelSeparatorState()
	local scroll = getLevelScrollBar()

	if not scroll then
		Cyclopedia.updateMinimapBackgroundColor()

		return
	end

	local active = getMinimapViewFloor() < LEVEL_SEPARATOR_MIDDLE_FLOOR

	scroll:setEnabled(active)

	local label = UI and UI:recursiveGetChildById("levelSeparatorLabel")

	if label then
		label:setColor(active and "#c0c0c0" or "#707070")
	end

	if active then
		applyLevelSeparatorIntensity(scroll:getValue())
	else
		applyLevelSeparatorIntensity()
	end

	Cyclopedia.updateMinimapBackgroundColor()
end

function Cyclopedia.onLevelSeparatorChange(value)
	if getMinimapViewFloor() >= LEVEL_SEPARATOR_MIDDLE_FLOOR then
		return
	end

	applyLevelSeparatorIntensity(value)
	onMapConfigurationChanged()
end

local function setupLevelScrollBar()
	local scroll = getLevelScrollBar()

	if not scroll then
		return
	end

	scroll:setMinimum(0)
	scroll:setMaximum(100)
	scroll:setStep(10)
end

local function setupMapConfigurationCallbacks()
	local function hookConfigCheckbox(widget)
		if not widget then
			return
		end

		local previousHandler = widget.onCheckChange

		function widget.onCheckChange(w, checked)
			if previousHandler then
				previousHandler(w, checked)
			end

			onMapConfigurationChanged()
		end
	end

	hookConfigCheckbox(getMarkFilterButton(20))
	hookConfigCheckbox(getMarkFilterButton(21))
	hookConfigCheckbox(getMarkFilterButton("passage"))
end

refreshVirtualFloors = function()
	local layersMark = getLayersMark()

	if not layersMark or layersMark:isDestroyed() then
		return
	end

	layersMark:setMarginTop(layerMarginTopForFloor(virtualFloor))
end

function Cyclopedia.setVirtualFloor(target)
	if type(target) ~= "number" then
		return
	end

	target = math.max(LAYER_FLOOR_MIN, math.min(LAYER_FLOOR_MAX, target))

	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	local cameraPos = minimap:getCameraPosition()

	if not cameraPos then
		return
	end

	if target == cameraPos.z then
		if virtualFloor ~= target then
			virtualFloor = target
			refreshVirtualFloors()
		end

		return
	end

	minimap:setCameraPosition({
		x = cameraPos.x,
		y = cameraPos.y,
		z = target
	})

	virtualFloor = target

	refreshVirtualFloors()
	syncCyclopediaSatelliteMode(minimap, getCyclopediaTilesDir(isSurfaceViewSelected()))
	Cyclopedia.updateLevelSeparatorState()
	prefetchCyclopediaMapCenter()

	if minimap.updateCrossVisibility then
		minimap:updateCrossVisibility()
	end
end

function Cyclopedia.applyMapFlagFilter()
	local minimap = getCyclopediaMinimap()

	if not minimap or not minimap.flags then
		return
	end

	local enabledIcons = {}

	forEachMapFlagFilterButton(function(button)
		if button:isChecked() then
			enabledIcons[tonumber(button:getId())] = true
		end
	end)

	for _, flag in pairs(minimap.flags) do
		if flag and not flag:isDestroyed() then
			local icon = flag.icon

			if type(icon) == "number" and enabledIcons[icon] then
				flag:show()
			else
				flag:hide()
			end
		end
	end
end

function Cyclopedia.syncShowAllBox()
	local showAllBox = getShowAllBox()

	if not showAllBox then
		return
	end

	local total = 0
	local checked = 0

	forEachMapFlagFilterButton(function(button)
		total = total + 1

		if button:isChecked() then
			checked = checked + 1
		end
	end)

	updatingMapFlags = true

	showAllBox:setChecked(total > 0 and checked == total)

	updatingMapFlags = false
end

local function hookCyclopediaMinimapFlags()
	local minimap = getCyclopediaMinimap()

	if not minimap or minimap._cyclopediaFlagHooked then
		return
	end

	local baseAddFlag = minimap.addFlag

	function minimap:addFlag(pos, icon, description, temporary, bundled)
		baseAddFlag(self, pos, icon, description, temporary, bundled)
		Cyclopedia.applyMapFlagFilter()
	end

	minimap._cyclopediaFlagHooked = true
end

function Cyclopedia.disconnectMapPositionEvent()
	if mapPositionConnected then
		disconnect(LocalPlayer, {
			onPositionChange = Cyclopedia.onUpdateCameraPosition
		})

		mapPositionConnected = false
	end
end

function Cyclopedia.centerMapAtPosition(pos, zoomDelta)
	if not pos or not UI or not UI.MapBase then
		return false
	end

	local minimapWidget = UI.MapBase.minimap

	if not minimapWidget then
		return false
	end

	local targetPos = {
		x = pos.x or 0,
		y = pos.y or 0,
		z = pos.z or CYCLOPEDIA_GROUND_FLOOR
	}

	-- This flag was set once and NEVER went back to false, and the guard in onUpdateCameraPosition
	-- (below: `not minimapWidget.fullMapView`) uses it to block auto-centering on the player.
	-- Result: after the first manual centering the map stopped following the character forever.
	-- We set it only for the duration of this single camera jump.
	minimapWidget.fullMapView = true

	scheduleEvent(function()
		if minimapWidget and not minimapWidget:isDestroyed() then
			minimapWidget.fullMapView = false
		end
	end, 100)

	if zoomDelta and minimapWidget.getZoom and minimapWidget.setZoom then
		local maxZoom = minimapWidget.getMaxZoom and minimapWidget:getMaxZoom() or minimapWidget:getZoom()
		local targetZoom = math.min(maxZoom, minimapWidget:getZoom() + zoomDelta)
		local savedSettingZoom = minimapWidget.zoomMinimap

		minimapWidget:setZoom(targetZoom)

		minimapWidget.zoomMinimap = savedSettingZoom
	end

	minimapWidget:setCameraPosition(targetPos)

	local player = g_game.getLocalPlayer()

	if player and player:getPosition() then
		minimapWidget:setCrossPosition(player:getPosition())
	end

	virtualFloor = targetPos.z

	refreshVirtualFloors()
	Cyclopedia.updateLevelSeparatorState()
	prefetchCyclopediaMapCenter()

	if minimapWidget.updateCrossVisibility then
		minimapWidget:updateCrossVisibility()
	end

	return true
end

function Cyclopedia.clearMapUI()
	Cyclopedia.disconnectMapPositionEvent()

	local minimap = getCyclopediaMinimap()

	if minimap and minimap.setSatelliteMode then
		minimap:setSatelliteMode(false)
	end

	clearCyclopediaAreaState()

	local root = UI

	UI = nil

	if root and not root:isDestroyed() then
		root:destroy()
	end

end

function initMap(contentContainer)
	local pendingMapPosition = Cyclopedia.PendingMapPosition
	local pendingMapZoomDelta = Cyclopedia.PendingMapZoomDelta

	Cyclopedia.PendingMapPosition = nil
	Cyclopedia.PendingMapZoomDelta = nil

	Cyclopedia.clearMapUI()

	UI = g_ui.loadUI("map", contentContainer)

	if not UI then
		g_logger.error("game_cyclopedia: failed to load map.otui")

		return
	end

	function UI.onDestroy()
		clearCyclopediaAreaState()

		UI = nil
	end

	UI:show()
	Cyclopedia.disconnectMapPositionEvent()

	connect(LocalPlayer, {
		onPositionChange = Cyclopedia.onUpdateCameraPosition
	})

	mapPositionConnected = true

	Cyclopedia.prevFloor = 7

	Cyclopedia.loadMap()
	hookCyclopediaMinimapFlags()
	Cyclopedia.applyMapFlagFilter()

	local player = g_game.getLocalPlayer()

	if player and player:getPosition() then
		virtualFloor = player:getPosition().z
	else
		virtualFloor = 7
	end

	refreshVirtualFloors()
	setupLevelScrollBar()
	setupMapConfigurationCallbacks()
	Cyclopedia.loadMapConfiguration()
	Cyclopedia.applyCyclopediaRenderMode()
	setupCyclopediaAreas()
	setupLayersPanelInteraction()

	if pendingMapPosition then
		Cyclopedia.centerMapAtPosition(pendingMapPosition, pendingMapZoomDelta)
	else
		Cyclopedia.onUpdateCameraPosition()
	end

	scheduleEvent(function()
		if UI and getCyclopediaMinimap() then
			Cyclopedia.applyMapFlagFilter()
		end
	end, 100)

end

function Cyclopedia.loadMap()
	if not UI or not UI.MapBase then
		return
	end

	local minimapWidget = UI.MapBase.minimap

	minimapWidget:load()

	if modules.game_minimap and modules.game_minimap.applyBundledMarkers then
		modules.game_minimap.applyBundledMarkers(minimapWidget)
	end

	applyCyclopediaDefaultZoom(minimapWidget)
end

function Cyclopedia.CreateMarkItem(Data)
	local markList = getMarkList()

	if not markList then
		return
	end

	local MarkItem = g_ui.createWidget("MarkListItem", markList)

	MarkItem:setIcon("/images/game/minimap/flag" .. Data.flagId)
	Cyclopedia.applyMapFlagFilter()
end

function Cyclopedia.toggleMapFlag(widget, checked)
	if updatingMapFlags or not isMapFlagFilterButton(widget) then
		return
	end

	Cyclopedia.syncShowAllBox()
	Cyclopedia.applyMapFlagFilter()
	onMapConfigurationChanged()
end

function Cyclopedia.showAllFlags(checked)
	if updatingMapFlags then
		return
	end

	updatingMapFlags = true

	forEachMapFlagFilterButton(function(button)
		button:setChecked(checked)
	end)

	updatingMapFlags = false

	Cyclopedia.applyMapFlagFilter()
	onMapConfigurationChanged()
end

function Cyclopedia.moveMap(widget)
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	local distance = 5
	local direction = widget:getId()

	if direction == "n" then
		minimap:move(0, distance)
	elseif direction == "ne" then
		minimap:move(-distance, distance)
	elseif direction == "e" then
		minimap:move(-distance, 0)
	elseif direction == "se" then
		minimap:move(-distance, -distance)
	elseif direction == "s" then
		minimap:move(0, -distance)
	elseif direction == "sw" then
		minimap:move(distance, -distance)
	elseif direction == "w" then
		minimap:move(distance, 0)
	elseif direction == "nw" then
		minimap:move(distance, distance)
	end
end

function ConvertLayer(Value)
	if Value == 150 then
		return 7
	elseif Value == 300 then
		return 15
	elseif Value >= 1 and Value <= 300 then
		return math.floor((Value - 1) / 20)
	else
		return 0
	end
end

function Cyclopedia.onUpdateCameraPosition()
	if not UI or not UI.MapBase then
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

	local minimapWidget = UI.MapBase.minimap

	if not minimapWidget then
		return
	end

	local useSurface = isSurfaceViewSelected()
	local targetZ = useSurface and 7 or pos.z

	if not minimapWidget:isDragging() and not minimapWidget.fullMapView then
		minimapWidget:setCameraPosition({
			x = pos.x,
			y = pos.y,
			z = targetZ
		})
	end

	minimapWidget:setCrossPosition(pos)

	virtualFloor = targetZ

	refreshVirtualFloors()
	syncCyclopediaSatelliteMode(minimapWidget, getCyclopediaTilesDir(useSurface))
	Cyclopedia.updateLevelSeparatorState()
	prefetchCyclopediaMapCenter()
end

function Cyclopedia.resetMap()
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	minimap:reset()

	local player = g_game.getLocalPlayer()

	if player and player:getPosition() then
		virtualFloor = player:getPosition().z

		refreshVirtualFloors()
		Cyclopedia.updateLevelSeparatorState()
	end
end

function Cyclopedia.onClickRoseButton(dir)
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	if dir == "north" then
		minimap:move(0, 1)
	elseif dir == "north-east" then
		minimap:move(-1, 1)
	elseif dir == "east" then
		minimap:move(-1, 0)
	elseif dir == "south-east" then
		minimap:move(-1, -1)
	elseif dir == "south" then
		minimap:move(0, -1)
	elseif dir == "south-west" then
		minimap:move(1, -1)
	elseif dir == "west" then
		minimap:move(1, 0)
	elseif dir == "north-west" then
		minimap:move(1, 1)
	end
end

function Cyclopedia.setZooom(zoom)
	local minimap = getCyclopediaMinimap()

	if not minimap then
		return
	end

	minimap:smoothZoomBy(zoom and 1 or -1)
end

function Cyclopedia.downLayer()
	Cyclopedia.setVirtualFloor(virtualFloor + 1)
end

function Cyclopedia.upLayer()
	Cyclopedia.setVirtualFloor(virtualFloor - 1)
end
