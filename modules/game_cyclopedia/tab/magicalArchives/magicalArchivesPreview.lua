-- chunkname: @/game_cyclopedia/tab/magicalArchives/magicalArchivesPreview.lua

if Cyclopedia.MagicalArchivesPreview then
	return
end

Cyclopedia.MagicalArchivesPreview = {}

local M = Cyclopedia.MagicalArchivesPreview
local PREVIEW_MAX_TILE_SIZE = 32
local PREVIEW_BASE_SPRITE_SIZE = 32
local PREVIEW_MAX_WIDTH = 469
local PREVIEW_MAX_HEIGHT = 199
local PREVIEW_PADDING = 1
local PREVIEW_GROUND_ID = 8284
local PREVIEW_TARGET_ID = 5787
local PREVIEW_LOOP_DELAY = 2000
local PREVIEW_EFFECT_DURATION = 1000
local PREVIEW_EFFECT_TICKS_PER_FRAME = 75
local PREVIEW_CREATURE_IDLE_ANIMATION = 0
local PREVIEW_CREATURE_MIN_FRAME_SIZE = PREVIEW_BASE_SPRITE_SIZE * 2
local PREVIEW_CREATURE_RENDER_SIZE = 100
-- Fine-tune preview creature position on the SQM (Fonticak draw offset). Negative = left / up.
local PREVIEW_CREATURE_TILE_NUDGE_X = -10
local PREVIEW_CREATURE_TILE_NUDGE_Y = 10
-- Field effects (one cell per SQM). Negative = left / up.
local PREVIEW_EFFECT_TILE_NUDGE_X = 0
local PREVIEW_EFFECT_TILE_NUDGE_Y = 0
local PREVIEW_MISSILE_STEP_DELAY = 10
local PREVIEW_MISSILE_MS_PER_TILE = 50
local previewEvents = {}
local previewLoopEvent, previewState

local function getPreviewPosition(action, layout)
	local x = tonumber(action.x) or 0
	local y = tonumber(action.y) or 0

	return {
		x = layout.originX + x * layout.tileSize,
		y = layout.originY + y * layout.tileSize
	}
end

local function setPreviewWidgetPosition(widget, pos, offsetX, offsetY)
	widget:setMarginTop(pos.y + (offsetY or 0))
	widget:setMarginLeft(pos.x + (offsetX or 0))
end

local function getEffectCycleDuration(effectId)
	if not g_things or not g_things.getThingType then
		return PREVIEW_EFFECT_DURATION
	end

	local ok, thingType = pcall(function()
		return g_things.getThingType(effectId, ThingCategoryEffect)
	end)

	if not ok or not thingType then
		return PREVIEW_EFFECT_DURATION
	end

	local ok2, dur = pcall(function()
		if thingType.getEffectAnimationDuration then
			return thingType:getEffectAnimationDuration(effectId)
		end

		return 0
	end)

	if ok2 and dur and dur > 0 then
		return dur
	end

	local ok3, phases = pcall(function()
		return thingType:getAnimationPhases()
	end)

	if not ok3 or not phases or phases <= 0 then
		return PREVIEW_EFFECT_DURATION
	end

	local ticksPerFrame = PREVIEW_EFFECT_TICKS_PER_FRAME

	if effectId == 33 then
		ticksPerFrame = ticksPerFrame * 4
	end

	return math.max(100, phases * ticksPerFrame)
end

local function getPreviewThingPixelSize(thingId, thingCategory)
	local exactSize = PREVIEW_BASE_SPRITE_SIZE

	if g_things and g_things.getThingType and thingCategory then
		local ok, thingType = pcall(function()
			return g_things.getThingType(thingId, thingCategory)
		end)

		if ok and thingType and thingType.getExactSize then
			exactSize = math.max(PREVIEW_BASE_SPRITE_SIZE, tonumber(thingType:getExactSize()) or PREVIEW_BASE_SPRITE_SIZE)
		end
	end

	return exactSize
end

local function placePreviewSizedWidget(parent, widget, action, layout, size)
	local pos = getPreviewPosition(action, layout)
	local offset = math.floor((size - layout.tileSize) / 2)

	widget:setSize({
		width = size,
		height = size
	})
	widget:addAnchor(AnchorTop, "parent", AnchorTop)
	widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
	widget:setMarginTop(pos.y - offset + (action.offsetY or 0))
	widget:setMarginLeft(pos.x - offset + (action.offsetX or 0))
	widget:setPhantom(true)
end

local function getPreviewMissileDirection(action)
	local x = tonumber(action.x) or 0
	local y = tonumber(action.y) or 0

	if x == 0 and y < 0 then
		return 0
	elseif x > 0 and y < 0 then
		return 4
	elseif x > 0 and y == 0 then
		return 1
	elseif x > 0 and y > 0 then
		return 5
	elseif x == 0 and y > 0 then
		return 2
	elseif x < 0 and y > 0 then
		return 6
	elseif x < 0 and y == 0 then
		return 3
	elseif x < 0 and y < 0 then
		return 7
	end

	return 2
end

local function placePreviewWidget(parent, widget, action, layout)
	local pos = getPreviewPosition(action, layout)

	widget:setSize({
		width = layout.tileSize,
		height = layout.tileSize
	})
	widget:addAnchor(AnchorTop, "parent", AnchorTop)
	widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
	setPreviewWidgetPosition(widget, pos, action.offsetX, action.offsetY)
	widget:setPhantom(true)
end

local function getPreviewCreatureBoundingBox(outfit, direction)
	local outfitId = tonumber(outfit and outfit.type) or 0

	if outfitId <= 0 or not g_things or not g_things.getCreatureBoundingBox then
		return nil
	end

	if direction == Directions.NorthEast or direction == Directions.SouthEast then
		direction = Directions.East
	elseif direction == Directions.SouthWest or direction == Directions.NorthWest then
		direction = Directions.West
	end

	local zPattern = (tonumber(outfit.mount) or 0) > 0 and 1 or 0
	local ok, bounds = pcall(function()
		return g_things.getCreatureBoundingBox(outfitId, PREVIEW_CREATURE_IDLE_ANIMATION, direction, zPattern)
	end)

	if not ok or type(bounds) ~= "table" then
		return nil
	end

	local width = tonumber(bounds.width) or 0
	local height = tonumber(bounds.height) or 0

	if width <= 0 or height <= 0 then
		return nil
	end

	return {
		width = width,
		height = height
	}
end

local function getPreviewCreatureSourceSize(widget)
	local sourceSize = PREVIEW_CREATURE_MIN_FRAME_SIZE
	local creature = widget:getCreature()

	if creature and creature.getExactSize then
		local ok, exactSize = pcall(function()
			return creature:getExactSize()
		end)

		if ok then
			sourceSize = math.max(sourceSize, tonumber(exactSize) or sourceSize)
		end
	end

	return math.min(255, math.ceil(sourceSize))
end

local function roundPreviewPixel(value)
	if value < 0 then
		return math.ceil(value - 0.5)
	end

	return math.floor(value + 0.5)
end

local function callWidgetOptional(widget, methodName, ...)
	if not widget or not widget[methodName] then
		return false
	end

	local ok = pcall(widget[methodName], widget, ...)

	return ok
end

local function freezePreviewCreatureWidget(widget)
	callWidgetOptional(widget, "setAnimate", false)
	callWidgetOptional(widget, "setIdleAnimate", false)
	callWidgetOptional(widget, "setStaticWalking", false)

	local internalCreature = widget.getCreature and widget:getCreature()

	if internalCreature and internalCreature.setStaticWalking then
		internalCreature:setStaticWalking(0)
	end
end

local function getPreviewCreatureDrawSize(layout)
	return math.min(255, math.max(layout.tileSize * 2, 48))
end

-- Large preview sprite (2x tile) with feet on the bottom edge of the SQM.
local function placePreviewCreatureOnTile(widget, action, layout)
	local parent = widget:getParent()

	if not parent then
		return
	end

	local tileSize = layout.tileSize
	local drawSize = getPreviewCreatureDrawSize(layout)
	local pos = getPreviewPosition(action, layout)

	if widget.setCreatureSize then
		widget:setCreatureSize(drawSize)
	else
		widget:setSize({
			width = drawSize,
			height = drawSize
		})
	end

	widget:addAnchor(AnchorTop, "parent", AnchorTop)
	widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
	widget:setMarginLeft(roundPreviewPixel(pos.x + (tileSize - drawSize) / 2 + (action.offsetX or 0) + PREVIEW_CREATURE_TILE_NUDGE_X))
	widget:setMarginTop(roundPreviewPixel(pos.y + tileSize - drawSize + (action.offsetY or 0) + PREVIEW_CREATURE_TILE_NUDGE_Y))
	widget:setPhantom(true)
end

local function placePreviewEffectOnTile(parent, widget, action, layout)
	local pos = getPreviewPosition(action, layout)
	local tileSize = layout.tileSize

	widget:setSize({
		width = tileSize,
		height = tileSize
	})
	widget:addAnchor(AnchorTop, "parent", AnchorTop)
	widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
	widget:setMarginLeft(roundPreviewPixel(pos.x + (action.offsetX or 0) + PREVIEW_EFFECT_TILE_NUDGE_X))
	widget:setMarginTop(roundPreviewPixel(pos.y + (action.offsetY or 0) + PREVIEW_EFFECT_TILE_NUDGE_Y))
	widget:setPhantom(true)
end

local function placePreviewCreature(parent, widget, action, layout, sourceSize, bounds)
	local pos = getPreviewPosition(action, layout)

	sourceSize = sourceSize or PREVIEW_CREATURE_MIN_FRAME_SIZE

	local tileScale = layout.tileSize / PREVIEW_BASE_SPRITE_SIZE
	local displaySize = math.max(1, roundPreviewPixel(sourceSize * tileScale))
	local displayScale = displaySize / sourceSize
	local boundWidth = math.min(sourceSize, math.max(1, bounds and bounds.width or PREVIEW_BASE_SPRITE_SIZE))
	local boundHeight = math.min(sourceSize, math.max(1, bounds and bounds.height or PREVIEW_BASE_SPRITE_SIZE))
	local visualRight = (sourceSize + boundWidth) / 2
	local visualBottom = (sourceSize + boundHeight) / 2
	local marginLeft = roundPreviewPixel(pos.x + layout.tileSize - visualRight * displayScale)
	local marginTop = roundPreviewPixel(pos.y + layout.tileSize - visualBottom * displayScale)

	widget:setSize({
		width = displaySize,
		height = displaySize
	})
	widget:addAnchor(AnchorTop, "parent", AnchorTop)
	widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
	widget:setMarginTop(marginTop)
	widget:setMarginLeft(marginLeft)
	widget:setPhantom(true)
end

local function configurePreviewCreature(widget, action, layout, outfit, direction)
	direction = tonumber(direction) or Directions.South

	widget:setOutfit(outfit)

	local internalCreature = widget:getCreature()

	if internalCreature then
		internalCreature:setDirection(direction)
	end

	freezePreviewCreatureWidget(widget)
	callWidgetOptional(widget, "setCenter", true)

	local resolvedOutfit = internalCreature and internalCreature:getOutfit() or outfit
	local bounds = getPreviewCreatureBoundingBox(resolvedOutfit, direction)
	local hasAdvancedPlacement = widget.setCenterByBoundingBox and bounds

	if hasAdvancedPlacement then
		callWidgetOptional(widget, "setCenterByBoundingBox", true)
		callWidgetOptional(widget, "setFixedCreatureSize", false)
		callWidgetOptional(widget, "setCreatureSize", PREVIEW_CREATURE_RENDER_SIZE)
		callWidgetOptional(widget, "setBaseScale", false)
		callWidgetOptional(widget, "setIgnoreDisplacementShift", false)
		callWidgetOptional(widget, "setCreatureSmooth", layout.tileSize < PREVIEW_MAX_TILE_SIZE)
		placePreviewCreature(widget:getParent(), widget, action, layout, getPreviewCreatureSourceSize(widget), bounds)
	else
		placePreviewCreatureOnTile(widget, action, layout)
	end
end

local function createPreviewItem(parent, itemId, action, layout)
	local item = g_ui.createWidget("UIItem", parent)

	if not item then
		return nil
	end

	placePreviewWidget(parent, item, action, layout)

	local ok, err = pcall(function()
		item:setItemId(tonumber(itemId) or 0)
	end)

	if not ok then
		g_logger.warning("[MagicalArchivesPreview] failed to set preview item %s: %s", tostring(itemId), tostring(err))
		item:destroy()

		return nil
	end

	callWidgetOptional(item, "setShowCount", false)
	callWidgetOptional(item, "setFixedItemSize", true)
	callWidgetOptional(item, "setItemSmooth", layout.tileSize < PREVIEW_MAX_TILE_SIZE)

	return item
end

local function getPreviewMetrics(preview)
	local minX, maxX, minY, maxY = 0, 0, 0, 0
	local sumX, sumY, count = 0, 0, 0
	local maxTimestamp = 0
	local hasObjects = false

	local function includeAction(action)
		if type(action) == "table" then
			local x = tonumber(action.x) or 0
			local y = tonumber(action.y) or 0

			minX = math.min(minX, x)
			maxX = math.max(maxX, x)
			minY = math.min(minY, y)
			maxY = math.max(maxY, y)
			sumX = sumX + x
			sumY = sumY + y
			count = count + 1

			if action.action == "objecttype" or action.action == "creature" or action.action == "transform" then
				hasObjects = true
			end
		end
	end

	if type(preview.timestamps) == "table" then
		for _, timestamp in ipairs(preview.timestamps) do
			if type(timestamp) == "table" then
				maxTimestamp = math.max(maxTimestamp, tonumber(timestamp.timestamp) or 0)

				if type(timestamp.actions) == "table" then
					for _, action in ipairs(timestamp.actions) do
						includeAction(action)
					end
				end
			end
		end
	end

	if type(preview.initActions) == "table" then
		for _, action in ipairs(preview.initActions) do
			includeAction(action)
		end
	end

	local gridBounds = type(preview.gridBounds) == "table" and preview.gridBounds or nil
	local customMinX = gridBounds and tonumber(gridBounds.minX) or nil
	local customMaxX = gridBounds and tonumber(gridBounds.maxX) or nil
	local customMinY = gridBounds and tonumber(gridBounds.minY) or nil
	local customMaxY = gridBounds and tonumber(gridBounds.maxY) or nil
	local hasCustomBounds = customMinX and customMaxX and customMinY and customMaxY and customMinX <= customMaxX and customMinY <= customMaxY

	if hasCustomBounds then
		minX = math.floor(customMinX)
		maxX = math.floor(customMaxX)
		minY = math.floor(customMinY)
		maxY = math.floor(customMaxY)
	else
		minX = minX - 1
		maxX = maxX + 1
		minY = math.min(minY, -1)
		maxY = math.max(maxY, 1)

		local yRadius = math.max(math.abs(minY), math.abs(maxY))

		if yRadius <= 2 then
			minY = minY - 1
			maxY = maxY + 1
		end
	end

	local columns = math.max(1, maxX - minX + 1)
	local rows = math.max(1, maxY - minY + 1)
	local availW = PREVIEW_MAX_WIDTH - PREVIEW_PADDING * 2
	local availH = PREVIEW_MAX_HEIGHT - PREVIEW_PADDING * 2
	local tileSize = math.min(PREVIEW_MAX_TILE_SIZE, math.floor(availW / columns), math.floor(availH / rows))

	tileSize = math.max(12, tileSize)

	local contentWidth = columns * tileSize
	local contentHeight = rows * tileSize

	return {
		tileSize = tileSize,
		minX = minX,
		maxX = maxX,
		minY = minY,
		maxY = maxY,
		originX = math.floor((PREVIEW_MAX_WIDTH - contentWidth) / 2) - minX * tileSize,
		originY = math.floor((PREVIEW_MAX_HEIGHT - contentHeight) / 2) - minY * tileSize,
		maxTimestamp = maxTimestamp,
		hasObjects = hasObjects,
		avgX = count > 0 and sumX / count or 0,
		avgY = count > 0 and sumY / count or 1
	}
end

local function getPreviewPlayerDirection(layout)
	if math.abs(layout.avgX) >= math.abs(layout.avgY) then
		if layout.avgX > 0 then
			return 1
		elseif layout.avgX < 0 then
			return 3
		end

		return 2
	end

	return layout.avgY > 0 and 2 or 0
end

local function clearPreviewEvents()
	for _, event in ipairs(previewEvents) do
		if event then
			removeEvent(event)
		end
	end

	previewEvents = {}

	if previewLoopEvent then
		removeEvent(previewLoopEvent)

		previewLoopEvent = nil
	end
end

local function schedulePreviewEvent(callback, delay)
	local event

	event = scheduleEvent(function()
		local found = false

		for index, previewEvent in ipairs(previewEvents) do
			if previewEvent == event then
				table.remove(previewEvents, index)

				found = true

				break
			end
		end

		if not found or not previewState then
			return
		end

		local ok, err = pcall(callback)

		if not ok then
			g_logger.error("[MagicalArchivesPreview] preview event failed: " .. tostring(err))
		end
	end, delay)
	previewEvents[#previewEvents + 1] = event

	return event
end

local function createPreviewLayer(parent, id)
	local layer = g_ui.createWidget("UIWidget", parent)

	if not layer then
		return nil
	end

	layer:setId(id)
	layer:addAnchor(AnchorTop, "parent", AnchorTop)
	layer:addAnchor(AnchorLeft, "parent", AnchorLeft)
	layer:addAnchor(AnchorRight, "parent", AnchorRight)
	layer:addAnchor(AnchorBottom, "parent", AnchorBottom)
	layer:setPhantom(true)
	pcall(function()
		layer:setClipping(true)
	end)

	return layer
end

local function createPreviewLayers(previewFrame)
	return {
		ground = createPreviewLayer(previewFrame, "previewGroundLayer"),
		objects = createPreviewLayer(previewFrame, "previewObjectLayer"),
		actors = createPreviewLayer(previewFrame, "previewActorLayer"),
		effects = createPreviewLayer(previewFrame, "previewEffectLayer")
	}
end

local function drawPreviewBase(layout, preview)
	local layers = previewState.layers
	local groundLayer = layers.ground or previewState.frame
	local actorLayer = layers.actors or previewState.frame

	for row = layout.minY, layout.maxY do
		for column = layout.minX, layout.maxX do
			createPreviewItem(groundLayer, PREVIEW_GROUND_ID, {
				x = column,
				y = row
			}, layout)
		end
	end

	if type(preview.initActions) == "table" then
		for _, action in ipairs(preview.initActions) do
			if type(action) == "table" and action.action == "target" then
				local targetAction = {
					x = action.x,
					y = action.y,
					offsetX = tonumber(action.offsetX) or 0,
					offsetY = tonumber(action.offsetY) or 0
				}
				local dummyItem = createPreviewItem(actorLayer, PREVIEW_TARGET_ID, targetAction, layout)

				if not dummyItem then
					local lookType = tonumber(action.lookType) or 1137
					local creature = g_ui.createWidget("UICreature", actorLayer)

					if creature then
						local creatureOk = pcall(function()
							configurePreviewCreature(creature, targetAction, layout, {
								type = lookType
							}, tonumber(action.direction) or Directions.South)
						end)

						if not creatureOk then
							creature:destroy()
						elseif previewState and previewState.creatures then
							previewState.creatures[#previewState.creatures + 1] = creature
						end
					end
				end
			end
		end
	end

	local player = g_game.getLocalPlayer()

	if player then
		local creature = g_ui.createWidget("UICreature", actorLayer)

		if creature then
			local ok = pcall(function()
				configurePreviewCreature(creature, {
					x = 0,
					y = 0
				}, layout, player:getOutfit(), getPreviewPlayerDirection(layout))
			end)

			if not ok then
				creature:destroy()
			else
				previewState.playerCreature = creature
			end
		end
	end
end

local function addPreviewCreature(action)
	if not previewState then
		return
	end

	local lookType = tonumber(action.lookType) or 0

	if lookType <= 0 then
		return
	end

	local parent = previewState.layers.actors or previewState.frame
	local creature = g_ui.createWidget("UICreature", parent)

	if not creature then
		return
	end

	local ok = pcall(function()
		configurePreviewCreature(creature, action, previewState.layout, {
			type = lookType
		}, tonumber(action.direction) or 2)
	end)

	if not ok then
		creature:destroy()

		return
	end

	previewState.creatures[#previewState.creatures + 1] = creature
end

local function transformPreviewPlayer(action)
	if not previewState then
		return
	end

	local creature = previewState.playerCreature
	local lookType = tonumber(action.lookType) or 0

	if not creature or creature:isDestroyed() or lookType <= 0 then
		return
	end

	configurePreviewCreature(creature, action, previewState.layout, {
		type = lookType
	}, creature:getDirection())
end

local function getPreviewObjectKey(action, objectId)
	return table.concat({
		tostring(tonumber(action.x) or 0),
		tostring(tonumber(action.y) or 0),
		tostring(tonumber(objectId) or 0)
	}, ":")
end

local function addPreviewObject(action)
	if not previewState then
		return
	end

	local objectId = tonumber(action.objecttypeID) or 0
	local key = getPreviewObjectKey(action, objectId)

	if previewState.objects[key] and not previewState.objects[key]:isDestroyed() then
		previewState.objects[key]:destroy()
	end

	local parent = previewState.layers.objects or previewState.frame

	previewState.objects[key] = createPreviewItem(parent, objectId, action, previewState.layout)
end

local function removePreviewObject(action)
	if not previewState then
		return
	end

	local objectId = tonumber(action.objecttypeID) or 0

	if objectId > 0 then
		local key = getPreviewObjectKey(action, objectId)
		local object = previewState.objects[key]

		if object and not object:isDestroyed() then
			object:destroy()
		end

		previewState.objects[key] = nil

		return
	end

	local x = tostring(tonumber(action.x) or 0)
	local y = tostring(tonumber(action.y) or 0)

	for key, object in pairs(previewState.objects) do
		if key:find("^" .. x .. ":" .. y .. ":") then
			if object and not object:isDestroyed() then
				object:destroy()
			end

			previewState.objects[key] = nil
		end
	end
end

local function addTimedPreviewWidget(widget, duration)
	schedulePreviewEvent(function()
		if widget and not widget:isDestroyed() then
			widget:destroy()
		end
	end, duration or PREVIEW_EFFECT_DURATION)
end

local function addPreviewMissile(action)
	if not previewState then
		return
	end

	local parent = previewState.layers.effects or previewState.frame
	local missile = g_ui.createWidget("Missile", parent)

	if not missile then
		return
	end

	local layout = previewState.layout
	local fromAction = {
		x = 0,
		y = 0
	}
	local fromPos = getPreviewPosition(fromAction, layout)
	local toPos = getPreviewPosition(action, layout)
	local dx = math.abs(tonumber(action.x) or 0)
	local dy = math.abs(tonumber(action.y) or 0)
	local distance = math.max(1, math.max(dx, dy))
	local totalDuration = distance * PREVIEW_MISSILE_MS_PER_TILE
	local steps = math.max(1, math.floor(totalDuration / PREVIEW_MISSILE_STEP_DELAY))

	placePreviewWidget(parent, missile, fromAction, layout)
	missile:setMissileId(tonumber(action.missileID) or 0)
	missile:setDirection(getPreviewMissileDirection(action))
	missile:setMissileVisible(true)

	for step = 1, steps do
		schedulePreviewEvent(function()
			if not missile or missile:isDestroyed() then
				return
			end

			local progress = step / steps

			setPreviewWidgetPosition(missile, {
				x = math.floor(fromPos.x + (toPos.x - fromPos.x) * progress),
				y = math.floor(fromPos.y + (toPos.y - fromPos.y) * progress)
			})
		end, step * PREVIEW_MISSILE_STEP_DELAY)
	end

	schedulePreviewEvent(function()
		if missile and not missile:isDestroyed() then
			missile:destroy()
		end
	end, totalDuration + PREVIEW_MISSILE_STEP_DELAY)
end

local function executePreviewAction(action)
	if not previewState or type(action) ~= "table" then
		return
	end

	local actionType = action.action

	if actionType == "objecttype" then
		addPreviewObject(action)
	elseif actionType == "creature" then
		addPreviewCreature(action)
	elseif actionType == "transform" then
		transformPreviewPlayer(action)
	elseif actionType == "clearField" then
		removePreviewObject(action)
	elseif actionType == "fieldEffect" then
		local parent = previewState.layers.effects or previewState.frame
		local effect = g_ui.createWidget("Effect", parent)

		if effect then
			local effectId = tonumber(action.effectID) or 0
			local layout = previewState.layout

			placePreviewEffectOnTile(parent, effect, action, layout)
			effect:setEffectId(effectId)

			if previewState.preview and previewState.preview.useMapEffectPatterns == true then
				local player = g_game.getLocalPlayer()
				local playerPosition = player and player:getPosition() or nil
				local internalEffect = effect:getEffect()

				if playerPosition and internalEffect then
					internalEffect:setPosition({
						x = playerPosition.x + (tonumber(action.x) or 0),
						y = playerPosition.y + (tonumber(action.y) or 0),
						z = playerPosition.z
					})
				end
			end

			effect:setEffectVisible(true)
			pcall(function()
				effect:setEffectSmooth(layout.tileSize < PREVIEW_MAX_TILE_SIZE)
			end)
			addTimedPreviewWidget(effect, getEffectCycleDuration(effectId))
		end
	elseif actionType == "missile" then
		addPreviewMissile(action)
	end
end

local function startSpellPreview(frame, spell)
	M.stop()

	if not frame or frame:isDestroyed() then
		return
	end

	frame:setVisible(spell.hasPreview == true)
	pcall(function()
		frame:setClipping(true)
	end)

	if not spell.hasPreview then
		return
	end

	local preview = spell.preview or {}
	local layout = getPreviewMetrics(preview)

	previewState = {
		frame = frame,
		preview = preview,
		layout = layout,
		objects = {},
		creatures = {},
		layers = createPreviewLayers(frame)
	}

	drawPreviewBase(layout, preview)

	if type(preview.timestamps) == "table" then
		for _, timestamp in ipairs(preview.timestamps) do
			if type(timestamp) == "table" and type(timestamp.actions) == "table" then
				local actions = timestamp.actions

				schedulePreviewEvent(function()
					for _, action in ipairs(actions) do
						executePreviewAction(action)
					end
				end, tonumber(timestamp.timestamp) or 0)
			end
		end
	end

	local maxEffectDuration = 0

	if type(preview.timestamps) == "table" then
		for _, timestamp in ipairs(preview.timestamps) do
			if type(timestamp) == "table" and type(timestamp.actions) == "table" then
				for _, action in ipairs(timestamp.actions) do
					if action.action == "fieldEffect" then
						local dur = getEffectCycleDuration(tonumber(action.effectID) or 0)

						if maxEffectDuration < dur then
							maxEffectDuration = dur
						end
					end
				end
			end
		end
	end

	local extraDuration = layout.hasObjects and 3000 or math.max(maxEffectDuration, 100)

	previewLoopEvent = scheduleEvent(function()
		if not previewState or previewState.frame ~= frame or previewState.frame:isDestroyed() then
			return
		end

		local ok, err = pcall(function()
			startSpellPreview(frame, spell)
		end)

		if not ok then
			g_logger.error("[MagicalArchivesPreview] preview loop failed for \"" .. tostring(spell.name) .. "\": " .. tostring(err))
		end
	end, layout.maxTimestamp + extraDuration + PREVIEW_LOOP_DELAY)
end

function M.hasActions(preview)
	if type(preview) ~= "table" then
		return false
	end

	if type(preview.initActions) == "table" and #preview.initActions > 0 then
		return true
	end

	if type(preview.timestamps) == "table" then
		for _, timestamp in ipairs(preview.timestamps) do
			if type(timestamp) == "table" and type(timestamp.actions) == "table" and #timestamp.actions > 0 then
				return true
			end
		end
	end

	return false
end

function M.play(frame, spell)
	local ok, err = pcall(function()
		startSpellPreview(frame, spell)
	end)

	if not ok then
		g_logger.error("[MagicalArchivesPreview] play failed for \"" .. tostring(spell and spell.name) .. "\": " .. tostring(err))
	end
end

function M.stop()
	clearPreviewEvents()

	if previewState then
		if previewState.frame and not previewState.frame:isDestroyed() then
			previewState.frame:destroyChildren()
			previewState.frame:setVisible(false)
		end

		previewState = nil
	end
end
