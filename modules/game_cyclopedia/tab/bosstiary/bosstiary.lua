-- chunkname: @/game_cyclopedia/tab/bosstiary/bosstiary.lua

local UI

local OPCODE_BOSSTIARY_OPEN = 0xAE

local function requestBosstiaryWindow()
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return false
	end

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_BOSSTIARY_OPEN)
	protocolGame:send(msg)
	return true
end

function Cyclopedia.requestBosstiaryData()
	return requestBosstiaryWindow()
end

function Cyclopedia.requestBosstiaryDataForTracker()
	Cyclopedia._bosstiaryTrackerRefreshOnly = true
	if Cyclopedia.bosstiaryTrackerDebug then
		Cyclopedia.bosstiaryTrackerDebug("requestBosstiaryDataForTracker -> send 0xAE")
	end
	return requestBosstiaryWindow()
end

Cyclopedia.Bosstiary = Cyclopedia.Bosstiary or {}
Cyclopedia.Bosstiary.TrackerMetaByRaceId = Cyclopedia.Bosstiary.TrackerMetaByRaceId or {}
Cyclopedia._bosstiaryTrackerOverrides = Cyclopedia._bosstiaryTrackerOverrides or {}

local function bosstiaryHasCachedList()
	if not Cyclopedia.Bosstiary or not Cyclopedia.Bosstiary.Creatures then
		return false
	end

	for _, page in pairs(Cyclopedia.Bosstiary.Creatures) do
		if page and #page > 0 then
			return true
		end
	end

	return false
end

local function ensureBosstiaryState()
	Cyclopedia.Bosstiary = Cyclopedia.Bosstiary or {}
	if Cyclopedia.Bosstiary.Page == nil then
		Cyclopedia.Bosstiary.Page = 1
	end
	if Cyclopedia.Bosstiary.TotalPages == nil then
		Cyclopedia.Bosstiary.TotalPages = 1
	end
	if Cyclopedia.Bosstiary.Creatures == nil then
		Cyclopedia.Bosstiary.Creatures = {}
	end
	if Cyclopedia.Bosstiary.NotVisibleCreatures == nil then
		Cyclopedia.Bosstiary.NotVisibleCreatures = {}
	end
end

function Cyclopedia.clearBosstiaryUI()
	if UI and not UI:isDestroyed() then
		if UI.SearchEdit and not UI.SearchEdit:isDestroyed() then
			pcall(function()
				UI.SearchEdit:ungrabKeyboard()
			end)
		end
		UI:destroy()
	end

	UI = nil

	if Cyclopedia.Bosstiary then
		Cyclopedia.Bosstiary.Creatures = {}
		Cyclopedia.Bosstiary.NotVisibleCreatures = {}
		Cyclopedia.Bosstiary.PendingServerData = nil
		Cyclopedia.Bosstiary.Page = 1
		Cyclopedia.Bosstiary.TotalPages = 1
	end

	Cyclopedia._bosstiarySoftRefresh = false
	Cyclopedia._suppressBosstiaryListReload = false
end

function showBosstiary()
	local container = modules.game_cyclopedia.getContentContainer and modules.game_cyclopedia.getContentContainer() or contentContainer
	if UI and not UI:isDestroyed() then
		UI:show()
		ensureBosstiaryState()
		Cyclopedia._bosstiarySoftRefresh = bosstiaryHasCachedList()
		requestBosstiaryWindow()
		if Cyclopedia.setBosstiaryTabChrome then
			Cyclopedia.setBosstiaryTabChrome()
		end
		return
	end

	Cyclopedia.clearBosstiaryUI()

	UI = g_ui.loadUI("bosstiary", container)

	function UI.onDestroy()
		UI = nil
	end

	UI:show()
	ensureBosstiaryState()
	if UI.PageValue then
		UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bosstiary.Page, Cyclopedia.Bosstiary.TotalPages))
	end
	if Cyclopedia.Bosstiary.PendingServerData then
		Cyclopedia.LoadBosstiaryCreatures(Cyclopedia.Bosstiary.PendingServerData)
	else
		requestBosstiaryWindow()
	end
	UI.FilterBase.BaneIcon:setTooltip("Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 5\nExpertise: 15\nMastery: 30")
	UI.FilterBase.ArchfoeIcon:setTooltip("Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60")
	UI.FilterBase.NemesisIcon:setTooltip("Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60")
	UI.StarBase.Info1:setTooltip("Once you have reached the Prowess level, you can assign the boss\nto a boss slot.")
	UI.StarBase.Info2:setTooltip("Once you have reached the Expertise Level, you can display the\nboss on a Podium of Vigour.")
	UI.StarBase.Info3:setTooltip("Once you have reached the Mastery Level, youl will receive an\nadditional 25% loot bonus when the boss is assigned to a boss slot.")
	if Cyclopedia.setBosstiaryTabChrome then
		Cyclopedia.setBosstiaryTabChrome()
	end
end

function Cyclopedia.toggleBosstiaryTrackerCheck(widget, checked)
	if not widget or widget._suppressTrackerChange then
		return
	end

	local parent = widget:getParent()

	if not parent then
		return
	end

	local raceId = tonumber(parent:getId())

	if not raceId then
		return
	end

	if Cyclopedia._bosstiarySuppressReloadEvent then
		removeEvent(Cyclopedia._bosstiarySuppressReloadEvent)
		Cyclopedia._bosstiarySuppressReloadEvent = nil
	end

	Cyclopedia._suppressBosstiaryListReload = true
	Cyclopedia._bosstiarySuppressReloadEvent = scheduleEvent(function()
		Cyclopedia._bosstiarySuppressReloadEvent = nil
		Cyclopedia._suppressBosstiaryListReload = false
	end, 800)

	if sendBosstiaryTrackerStatus then
		sendBosstiaryTrackerStatus(raceId, checked)
	else
		g_game.sendStatusTrackerBestiary(raceId, checked)
	end

	Cyclopedia._bosstiaryTrackerOverrides[raceId] = checked and 1 or 0

	if not checked then
		Cyclopedia.removeFromTracker(1, raceId)
	else
		local kills, category, bossName, bossOutfit = 0, 0, nil, nil
		if Cyclopedia.Bosstiary and Cyclopedia.Bosstiary.Creatures then
			for _, page in pairs(Cyclopedia.Bosstiary.Creatures) do
				for _, creature in ipairs(page) do
					if creature.raceId == raceId then
						kills = creature.kills or 0
						category = creature.category or 0
						bossName = creature.name
						bossOutfit = creature.outfit
						break
					end
				end
			end
		end
		if Cyclopedia.addToBosstiaryTracker then
			Cyclopedia.addToBosstiaryTracker(raceId, kills, category, bossName, bossOutfit)
		end
	end

	if Cyclopedia.Bosstiary and Cyclopedia.Bosstiary.Creatures then
		for _, page in pairs(Cyclopedia.Bosstiary.Creatures) do
			for _, creature in ipairs(page) do
				if creature.raceId == raceId then
					creature.isTrackerActived = checked and 1 or 0
				end
			end
		end
	end
end

local CATEGORY = {
	BANE = 0,
	ARCHFOE = 1,
	NEMESIS = 2
}
local CONFIG = {
	[0] = {
		PROWESS = 25,
		EXPERTISE = 100,
		MASTERY = 300
	},
	[1] = {
		PROWESS = 5,
		EXPERTISE = 20,
		MASTERY = 60
	},
	[2] = {
		PROWESS = 1,
		EXPERTISE = 3,
		MASTERY = 5
	}
}

local function normalizeBossCategory(category)
	category = tonumber(category) or 0
	if category < 0 then
		return 0
	end
	if category > 2 then
		return 2
	end
	return category
end

local function getBossCategoryConfig(category)
	return CONFIG[normalizeBossCategory(category)]
end

local function normalizeCreatureOutfit(outfit, name)
	if not outfit then
		return nil
	end

	local lookType = tonumber(outfit.type or outfit.lookType) or 0
	if lookType <= 0 then
		return nil
	end

	return {
		type = lookType,
		head = outfit.head or 0,
		body = outfit.body or 0,
		legs = outfit.legs or 0,
		feet = outfit.feet or 0,
		addons = outfit.addons or 0,
		name = name
	}
end

local function creatureOutfitIsRenderable(outfit)
	local lookType = outfit and outfit.type or 0
	if lookType <= 0 then
		return false
	end

	if not g_things.getThingType then
		return true
	end

	local thingType = g_things.getThingType(lookType, ThingCategoryCreature)
	if not thingType then
		return false
	end

	if thingType.isNull and thingType:isNull() then
		return false
	end

	if thingType.getId then
		return (thingType:getId() or 0) > 0
	end

	return true
end

local function resolveBossOutfit(raceId, data, raceData, displayName)
	local candidates = {}

	if raceData and raceData.outfit then
		candidates[#candidates + 1] = raceData.outfit
	end
	if data.outfit then
		candidates[#candidates + 1] = data.outfit
	end
	if protoData and protoData[raceId] then
		candidates[#candidates + 1] = protoData[raceId]
	end

	for _, candidate in ipairs(candidates) do
		local normalized = normalizeCreatureOutfit(candidate, displayName)
		if normalized and creatureOutfitIsRenderable(normalized) then
			return normalized
		end
	end

	for _, candidate in ipairs(candidates) do
		local normalized = normalizeCreatureOutfit(candidate, displayName)
		if normalized then
			return normalized
		end
	end

	return nil
end

function Cyclopedia.setBosstiaryBossStars(widget, kills, config)
	local bronzeFill = widget.bronzeStar:getChildById("bronzeStarFill")

	if bronzeFill then
		bronzeFill:setVisible(kills >= config.PROWESS)
	end

	for i = 1, 2 do
		local fill = widget.silverStar:getChildById("silverStarFill" .. i)

		if fill then
			fill:setVisible(kills >= config.EXPERTISE)
		end
	end

	for i = 1, 3 do
		local fill = widget.goldStar:getChildById("goldStarFill" .. i)

		if fill then
			fill:setVisible(kills >= config.MASTERY)
		end
	end
end

function Cyclopedia.CreateBosstiaryCreature(data)
	if not data or not data.visible then
		return
	end

	if not UI or UI:isDestroyed() or not UI.ListBase or not UI.ListBase.BossList then
		return
	end

	local category = normalizeBossCategory(data.category)
	local config = getBossCategoryConfig(category)
	if not config then
		return
	end

	local widget = g_ui.createWidget("BosstiaryItem", UI.ListBase.BossList)

	widget:setId(data.raceId)

	local raceData = g_things.getRaceData(data.raceId)
	local displayName = data.name
	if not displayName or displayName == "" then
		displayName = raceData and raceData.name ~= "" and raceData.name or "?"
	end

	local bossOutfit = resolveBossOutfit(data.raceId, data, raceData, displayName)

	local icons = {
		[CATEGORY.BANE] = "/images/icons/icon-bosstiary-bane",
		[CATEGORY.ARCHFOE] = "/images/icons/icon-bosstiary-archfoe",
		[CATEGORY.NEMESIS] = "/images/icons/icon-bosstiary-nemesis"
	}

	local function format(string)
		if #string > 19 then
			return string:sub(1, 16) .. "..."
		else
			return string
		end
	end

	local fullText = ""

	if data.kills >= config.MASTERY then
		fullText = "(fully unlocked)"
	end

	if widget.ProgressBorder1 then
		widget.ProgressBorder1:setTooltip(string.format(" %d / %d %s", data.kills, config.PROWESS, fullText))
	end
	if widget.ProgressBorder2 then
		widget.ProgressBorder2:setTooltip(string.format(" %d / %d %s", data.kills, config.EXPERTISE, fullText))
	end
	if widget.ProgressBorder3 then
		widget.ProgressBorder3:setTooltip(string.format(" %d / %d %s", data.kills, config.MASTERY, fullText))
	end
	Cyclopedia.setBosstiaryBossStars(widget, data.kills, config)
	if widget.TypeIcon and icons[category] then
		widget.TypeIcon:setImageSource(icons[category])
	end

	if category == CATEGORY.BANE then
		widget.TypeIcon:setTooltip("Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 5\nExpertise: 15\nMastery: 30")
	elseif category == CATEGORY.ARCHFOE then
		widget.TypeIcon:setTooltip("Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60")
	elseif category == CATEGORY.NEMESIS then
		widget.TypeIcon:setTooltip("Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60")
	end

	data.category = category

	widget.ProgressValue:setText(data.kills)
	Cyclopedia.SetBestiaryProgress(46, widget.ProgressBack, widget.ProgressBack33, widget.ProgressBack55, data.kills, config.PROWESS, config.EXPERTISE, config.MASTERY, 47, 12)

	if bossOutfit and widget.Sprite then
		widget.Sprite:setOutfit(bossOutfit)
	end

	local spriteCreature = widget.Sprite and widget.Sprite:getCreature()

	if spriteCreature and spriteCreature.setStaticWalking then
		spriteCreature:setStaticWalking(1000)
	end

	if data.unlocked then
		if spriteCreature then
			spriteCreature:setShader("")
		end

		widget:setText(format(displayName))
		widget.TrackCheck:enable()

		local override = Cyclopedia._bosstiaryTrackerOverrides[data.raceId]
		local trackerActived = override ~= nil and override or data.isTrackerActived

		widget.TrackCheck._suppressTrackerChange = true

		widget.TrackCheck:setChecked(trackerActived == 1)

		widget.TrackCheck._suppressTrackerChange = false
	else
		if spriteCreature then
			spriteCreature:setShader("Outfit - cyclopedia-black")
		end

		widget:setText("Unknown")
		widget.TrackCheck:disable()
	end
end

local function isBosstiaryRaceTracked(raceId, dataEntry)
	raceId = tonumber(raceId)
	if not raceId then
		return false
	end

	if Cyclopedia._bosstiaryTrackerOverrides and Cyclopedia._bosstiaryTrackerOverrides[raceId] ~= nil then
		return Cyclopedia._bosstiaryTrackerOverrides[raceId] == 1
	end

	if dataEntry and dataEntry.isTrackerActived == 1 then
		return true
	end

	if Cyclopedia.storedBosstiaryTrackerData then
		for _, entry in ipairs(Cyclopedia.storedBosstiaryTrackerData) do
			if tonumber(entry[1]) == raceId then
				return true
			end
		end
	end

	return false
end

local function getBosstiaryCreatureFromCache(raceId)
	raceId = tonumber(raceId)
	if not raceId or not Cyclopedia.Bosstiary or not Cyclopedia.Bosstiary.Creatures then
		return nil
	end

	for _, page in pairs(Cyclopedia.Bosstiary.Creatures) do
		for _, creature in ipairs(page) do
			if creature.raceId == raceId then
				return creature
			end
		end
	end

	return nil
end

local function refreshBosstiaryCreatureWidgetKills(widget, creature)
	if not widget or not creature or widget:isDestroyed() then
		return
	end

	local category = normalizeBossCategory(creature.category)
	local config = getBossCategoryConfig(category)
	if not config then
		return
	end

	local kills = creature.kills or 0
	local fullText = kills >= config.MASTERY and "(fully unlocked)" or ""

	if widget.ProgressBorder1 then
		widget.ProgressBorder1:setTooltip(string.format(" %d / %d %s", kills, config.PROWESS, fullText))
	end
	if widget.ProgressBorder2 then
		widget.ProgressBorder2:setTooltip(string.format(" %d / %d %s", kills, config.EXPERTISE, fullText))
	end
	if widget.ProgressBorder3 then
		widget.ProgressBorder3:setTooltip(string.format(" %d / %d %s", kills, config.MASTERY, fullText))
	end

	Cyclopedia.setBosstiaryBossStars(widget, kills, config)

	if widget.ProgressValue then
		widget.ProgressValue:setText(kills)
	end

	if widget.ProgressBack then
		Cyclopedia.SetBestiaryProgress(46, widget.ProgressBack, widget.ProgressBack33, widget.ProgressBack55, kills, config.PROWESS, config.EXPERTISE, config.MASTERY, 47, 12)
	end
end

function Cyclopedia.syncBosstiaryTrackerFromEntries(entries)
	if not entries then
		return
	end

	local killsByRace = {}
	local categoryByRace = {}
	local metaByRace = {}

	for _, dataEntry in ipairs(entries) do
		local raceId = tonumber(dataEntry.raceId)
		if raceId then
			killsByRace[raceId] = dataEntry.kills or killsByRace[raceId] or 0
			if dataEntry.category ~= nil then
				categoryByRace[raceId] = dataEntry.category
			end
			metaByRace[raceId] = dataEntry
		end
	end

	local trackedRaceIds = {}

	local function markTracked(raceId, dataEntry)
		if isBosstiaryRaceTracked(raceId, dataEntry) then
			trackedRaceIds[tonumber(raceId)] = true
		end
	end

	for _, dataEntry in ipairs(entries) do
		markTracked(dataEntry.raceId, dataEntry)
	end

	if Cyclopedia.storedBosstiaryTrackerData then
		for _, entry in ipairs(Cyclopedia.storedBosstiaryTrackerData) do
			markTracked(entry[1], nil)
		end
	end

	local tracked = {}
	for raceId, _ in pairs(trackedRaceIds) do
		local dataEntry = metaByRace[raceId]
		local cached = getBosstiaryCreatureFromCache(raceId)
		local category = categoryByRace[raceId]
		if category == nil and cached then
			category = cached.category
		end

		category = normalizeBossCategory(category)
		local config = getBossCategoryConfig(category)
		if config then
			local kills = killsByRace[raceId]
			if kills == nil and cached then
				kills = cached.kills
			end
			kills = kills or 0

			tracked[#tracked + 1] = {
				raceId,
				kills,
				config.PROWESS,
				config.EXPERTISE,
				config.MASTERY,
				0
			}

			if Cyclopedia.rememberBosstiaryTrackerMeta and dataEntry then
				Cyclopedia.rememberBosstiaryTrackerMeta(raceId, dataEntry.name, dataEntry.outfit)
			elseif Cyclopedia.rememberBosstiaryTrackerMeta and cached then
				Cyclopedia.rememberBosstiaryTrackerMeta(raceId, cached.name, cached.outfit)
			end
		end
	end

	if Cyclopedia.bosstiaryTrackerDebug then
		local parts = {}
		for i = 1, math.min(#tracked, 5) do
			parts[#parts + 1] = string.format("%s:%s", tostring(tracked[i][1]), tostring(tracked[i][2]))
		end
		Cyclopedia.bosstiaryTrackerDebug("syncBosstiaryTrackerFromEntries tracked=" .. #tracked .. " [" .. table.concat(parts, ", ") .. "]")
	end

	if Cyclopedia.onParseBosstiaryTracker then
		Cyclopedia.onParseBosstiaryTracker(tracked)
	end
end

function Cyclopedia.addToBosstiaryTracker(raceId, kills, category, name, outfit)
	raceId = tonumber(raceId)
	if not raceId or raceId <= 0 then
		return
	end

	if Cyclopedia.rememberBosstiaryTrackerMeta then
		Cyclopedia.rememberBosstiaryTrackerMeta(raceId, name, outfit)
	end

	local config = getBossCategoryConfig(normalizeBossCategory(category))
	if not config then
		return
	end

	local data = {}
	if Cyclopedia.storedBosstiaryTrackerData then
		for _, entry in ipairs(Cyclopedia.storedBosstiaryTrackerData) do
			if tonumber(entry[1]) ~= raceId then
				data[#data + 1] = entry
			end
		end
	end

	data[#data + 1] = {
		raceId,
		kills or 0,
		config.PROWESS,
		config.EXPERTISE,
		config.MASTERY,
		0
	}

	if Cyclopedia.onParseBosstiaryTracker then
		Cyclopedia.onParseBosstiaryTracker(data)
	end
end

function Cyclopedia.applyBosstiaryTrackerStateToList(data)
	if not data or not UI or UI:isDestroyed() or not UI.ListBase or not UI.ListBase.BossList then
		return
	end

	ensureBosstiaryState()

	for _, dataEntry in ipairs(data) do
		local raceId = dataEntry.raceId
		local trackerFlag = dataEntry.isTrackerActived

		if Cyclopedia._bosstiaryTrackerOverrides[raceId] ~= nil then
			trackerFlag = Cyclopedia._bosstiaryTrackerOverrides[raceId]
		end

		local cachedCreature

		for _, page in pairs(Cyclopedia.Bosstiary.Creatures or {}) do
			for _, creature in ipairs(page) do
				if creature.raceId == raceId then
					creature.isTrackerActived = trackerFlag
					if dataEntry.kills ~= nil then
						creature.kills = dataEntry.kills
					end
					cachedCreature = creature
				end
			end
		end

		local widget = UI.ListBase.BossList:getChildById(raceId)
		if widget and widget.TrackCheck and not widget.TrackCheck:isDestroyed() then
			widget.TrackCheck._suppressTrackerChange = true
			widget.TrackCheck:setChecked(trackerFlag == 1)
			widget.TrackCheck._suppressTrackerChange = false
		end

		if cachedCreature and widget then
			refreshBosstiaryCreatureWidgetKills(widget, cachedCreature)
		end
	end
end

function Cyclopedia.ingestBosstiaryServerData(data, options)
	if not data then
		return
	end

	options = options or {}

	Cyclopedia.Bosstiary = Cyclopedia.Bosstiary or {}
	Cyclopedia.Bosstiary.OutfitsByRaceId = Cyclopedia.Bosstiary.OutfitsByRaceId or {}
	Cyclopedia.Bosstiary.NamesByRaceId = Cyclopedia.Bosstiary.NamesByRaceId or {}
	Cyclopedia.Bosstiary.PendingServerData = data

	for _, dataEntry in ipairs(data) do
		local raceData = g_things.getRaceData(dataEntry.raceId)
		local name = (dataEntry.name and dataEntry.name ~= "" and dataEntry.name)
			or (raceData and raceData.name ~= "" and raceData.name)
			or "?"

		if dataEntry.outfit and (dataEntry.outfit.type or 0) > 0 then
			Cyclopedia.Bosstiary.OutfitsByRaceId[dataEntry.raceId] = dataEntry.outfit
			if protoData then
				protoData[dataEntry.raceId] = dataEntry.outfit
			end
		end
		if name and name ~= "?" then
			Cyclopedia.Bosstiary.NamesByRaceId[dataEntry.raceId] = name
		end
		if Cyclopedia.rememberBosstiaryTrackerMeta then
			Cyclopedia.rememberBosstiaryTrackerMeta(dataEntry.raceId, name, dataEntry.outfit)
		end
	end

	if not options.skipTrackerSync and Cyclopedia.syncBosstiaryTrackerFromEntries then
		Cyclopedia.syncBosstiaryTrackerFromEntries(data)
	end
end

function Cyclopedia.LoadBosstiaryCreatures(data)
	if not data then
		if Cyclopedia.bosstiaryTrackerDebug then
			Cyclopedia.bosstiaryTrackerDebug("LoadBosstiaryCreatures: nil data")
		end
		return
	end

	if Cyclopedia.bosstiaryTrackerDebug then
		Cyclopedia.bosstiaryTrackerDebug(string.format(
			"LoadBosstiaryCreatures count=%d trackerOnly=%s suppress=%s hasUI=%s",
			#data,
			tostring(Cyclopedia._bosstiaryTrackerRefreshOnly),
			tostring(Cyclopedia._suppressBosstiaryListReload),
			tostring(UI and not UI:isDestroyed())
		))
	end

	if Cyclopedia._bosstiaryTrackerRefreshOnly then
		Cyclopedia._bosstiaryTrackerRefreshOnly = false
		if Cyclopedia.bosstiaryTrackerDebug then
			Cyclopedia.bosstiaryTrackerDebug("LoadBosstiaryCreatures: tracker-only path")
		end
		Cyclopedia.ingestBosstiaryServerData(data)
		if UI and not UI:isDestroyed() then
			Cyclopedia.applyBosstiaryTrackerStateToList(data)
		end
		if Cyclopedia._bossSlotsAwaitingBosstiaryData and Cyclopedia.refreshBossSlotsFromCachedBosstiary then
			Cyclopedia._bossSlotsAwaitingBosstiaryData = false
			Cyclopedia.refreshBossSlotsFromCachedBosstiary()
		end
		return
	end

	if Cyclopedia._suppressBosstiaryListReload and UI and not UI:isDestroyed() then
		Cyclopedia._suppressBosstiaryListReload = false
		if Cyclopedia._bosstiarySuppressReloadEvent then
			removeEvent(Cyclopedia._bosstiarySuppressReloadEvent)
			Cyclopedia._bosstiarySuppressReloadEvent = nil
		end
		Cyclopedia.ingestBosstiaryServerData(data, { skipTrackerSync = true })
		Cyclopedia.applyBosstiaryTrackerStateToList(data)
		if Cyclopedia.syncBosstiaryTrackerFromEntries then
			Cyclopedia.syncBosstiaryTrackerFromEntries(data)
		end
		return
	end

	if Cyclopedia._bosstiarySoftRefresh and UI and not UI:isDestroyed() and bosstiaryHasCachedList() then
		Cyclopedia._bosstiarySoftRefresh = false
		Cyclopedia.ingestBosstiaryServerData(data)
		Cyclopedia.applyBosstiaryTrackerStateToList(data)
		if Cyclopedia.syncBosstiaryTrackerFromEntries then
			Cyclopedia.syncBosstiaryTrackerFromEntries(data)
		end
		if Cyclopedia._bossSlotsAwaitingBosstiaryData and Cyclopedia.refreshBossSlotsFromCachedBosstiary then
			Cyclopedia._bossSlotsAwaitingBosstiaryData = false
			Cyclopedia.refreshBossSlotsFromCachedBosstiary()
		end
		return
	end

	Cyclopedia._suppressBosstiaryListReload = false
	Cyclopedia._bosstiarySoftRefresh = false
	Cyclopedia.ingestBosstiaryServerData(data)

	if not UI then
		return
	end

	local maxCategoriesPerPage = 8

	Cyclopedia.Bosstiary.Creatures = {}
	Cyclopedia.Bosstiary.NotVisibleCreatures = {}
	Cyclopedia.Bosstiary.Page = 1
	Cyclopedia.Bosstiary.TotalPages = math.max(1, math.ceil(#data / maxCategoriesPerPage))

	UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bosstiary.Page, Cyclopedia.Bosstiary.TotalPages))

	local page = 1

	Cyclopedia.Bosstiary.Creatures[page] = {}

	local validCreatures = {}

	for i, dataEntry in ipairs(data) do
		local raceData = g_things.getRaceData(dataEntry.raceId)
		local creature = {
			visible = true,
			raceId = dataEntry.raceId,
			name = (dataEntry.name and dataEntry.name ~= "" and dataEntry.name)
				or (raceData and raceData.name ~= "" and raceData.name)
				or "?",
			outfit = dataEntry.outfit,
			kills = dataEntry.kills,
			category = dataEntry.category,
			isTrackerActived = dataEntry.isTrackerActived,
			unlocked = dataEntry.kills > 0 and true or false
		}

		if creature.outfit and (creature.outfit.type or 0) > 0 then
			Cyclopedia.Bosstiary.OutfitsByRaceId[creature.raceId] = creature.outfit
			if protoData then
				protoData[creature.raceId] = creature.outfit
			end
		end
		if creature.name and creature.name ~= "?" then
			Cyclopedia.Bosstiary.NamesByRaceId[creature.raceId] = creature.name
		end
		if Cyclopedia.rememberBosstiaryTrackerMeta then
			Cyclopedia.rememberBosstiaryTrackerMeta(creature.raceId, creature.name, creature.outfit)
		end

		table.insert(validCreatures, creature)
	end

	table.sort(validCreatures, function(a, b)
		if a.name == "?" and b.name ~= "?" then
			return false
		elseif a.name ~= "?" and b.name == "?" then
			return true
		elseif a.unlocked and not b.unlocked then
			return true
		elseif not a.unlocked and b.unlocked then
			return false
		else
			return a.name < b.name
		end
	end)

	for i = 1, #validCreatures do
		local creature = validCreatures[i]

		if creature.visible then
			table.insert(Cyclopedia.Bosstiary.Creatures[page], creature)
		else
			table.insert(Cyclopedia.Bosstiary.NotVisibleCreatures[page], creature)
		end

		if i % maxCategoriesPerPage == 0 and i < #validCreatures then
			page = page + 1
			Cyclopedia.Bosstiary.Creatures[page] = {}
		end
	end

	Cyclopedia.LoadBosstiaryCreature(Cyclopedia.Bosstiary.Page)
	Cyclopedia.verifyBosstiaryButtons()
	Cyclopedia.applyPendingBosstiaryShortcut()

	if Cyclopedia.syncBosstiaryTrackerFromEntries then
		Cyclopedia.syncBosstiaryTrackerFromEntries(data)
	end

	if Cyclopedia._bossSlotsAwaitingBosstiaryData and Cyclopedia.refreshBossSlotsFromCachedBosstiary then
		Cyclopedia._bossSlotsAwaitingBosstiaryData = false
		Cyclopedia.refreshBossSlotsFromCachedBosstiary()
	end
end

function Cyclopedia.applyPendingBosstiaryShortcut()
	local raceId = Cyclopedia._pendingBosstiaryRaceId

	if not raceId or not UI then
		return false
	end

	if not Cyclopedia.Bosstiary.Creatures or #Cyclopedia.Bosstiary.Creatures == 0 then
		return false
	end

	local searchText = nil
	if Cyclopedia.Bosstiary.NamesByRaceId and Cyclopedia.Bosstiary.NamesByRaceId[raceId] then
		searchText = Cyclopedia.Bosstiary.NamesByRaceId[raceId]
	end

	local raceData = g_things.getRaceData(raceId)
	if not searchText and raceData and raceData.name and raceData.name ~= "" then
		searchText = raceData.name
	end

	if not searchText or searchText == "" then
		return false
	end

	Cyclopedia._pendingBosstiaryRaceId = nil

	if UI.SearchEdit then
		UI.SearchEdit:setText(searchText)
	end

	Cyclopedia.BosstiarySearchText(searchText)

	return true
end

function Cyclopedia.focusBosstiaryRaceId(raceId)
	raceId = tonumber(raceId)
	if not raceId or not UI or not Cyclopedia.Bosstiary.Creatures then
		return false
	end

	if Cyclopedia.BosstiarySearchText then
		Cyclopedia.BosstiarySearchText("")
	end

	for page = 1, #Cyclopedia.Bosstiary.Creatures do
		local creatures = Cyclopedia.Bosstiary.Creatures[page]

		if creatures then
			for _, creature in ipairs(creatures) do
				if creature.raceId == raceId then
					Cyclopedia.Bosstiary.Page = page

					Cyclopedia.LoadBosstiaryCreature(page)
					Cyclopedia.verifyBosstiaryButtons()

					return true
				end
			end
		end
	end

	return false
end

function Cyclopedia.LoadBosstiaryCreature(page)
	if not UI or UI:isDestroyed() then
		return
	end

	ensureBosstiaryState()

	if not Cyclopedia.Bosstiary.Creatures[page] then
		return
	end

	UI.ListBase.BossList:destroyChildren()

	for _, data in ipairs(Cyclopedia.Bosstiary.Creatures[page]) do
		Cyclopedia.CreateBosstiaryCreature(data)
	end
end

function Cyclopedia.verifyBosstiaryButtons()
	if not UI or UI:isDestroyed() then
		return
	end

	ensureBosstiaryState()

	local page = Cyclopedia.Bosstiary.Page
	local totalPages = Cyclopedia.Bosstiary.TotalPages

	local function updateButtonState(button, condition)
		if condition then
			button:enable()
		else
			button:disable()
		end
	end

	local function updatePageValue(currentPage, maxPages)
		UI.PageValue:setText(string.format("%d / %d", currentPage, maxPages))
	end

	updateButtonState(UI.PrevPageButton, page > 1)
	updateButtonState(UI.NextPageButton, page < totalPages)
	updatePageValue(page, totalPages)
end

function Cyclopedia.changeBosstiaryPage(prev, next)
	if not UI or UI:isDestroyed() then
		return
	end

	ensureBosstiaryState()

	local page = Cyclopedia.Bosstiary.Page
	local totalPages = Cyclopedia.Bosstiary.TotalPages

	if next and page < totalPages then
		page = page + 1
	elseif prev and page > 1 then
		page = page - 1
	else
		return
	end

	Cyclopedia.Bosstiary.Page = page
	Cyclopedia.LoadBosstiaryCreature(page)
	Cyclopedia.verifyBosstiaryButtons()
end

function Cyclopedia.BosstiarySearchText(text, clear)
	local allCreatures = {}

	if clear then
		UI.SearchEdit:setText("")
	end

	for _, creatures in ipairs(Cyclopedia.Bosstiary.Creatures) do
		for _, creature in ipairs(creatures) do
			table.insert(allCreatures, creature)
		end
	end

	for _, creature in ipairs(Cyclopedia.Bosstiary.NotVisibleCreatures) do
		table.insert(allCreatures, creature)
	end

	if text ~= "" then
		for _, creature in ipairs(allCreatures) do
			if not creature.unlocked then
				creature.visible = false
			elseif string.find(creature.name:lower(), text:lower()) == nil then
				creature.visible = false
			else
				creature.visible = true
			end
		end
	else
		for _, creature in ipairs(allCreatures) do
			creature.visible = true
		end
	end

	Cyclopedia.ReadjustPages()
end

function Cyclopedia.changeBosstiaryFilter(widget, isCheck)
	widget:setChecked(not isCheck)

	local id = widget:getId()
	local allCreatures = {}

	for _, creatures in ipairs(Cyclopedia.Bosstiary.Creatures) do
		for _, creature in ipairs(creatures) do
			table.insert(allCreatures, creature)
		end
	end

	for _, creature in ipairs(Cyclopedia.Bosstiary.NotVisibleCreatures) do
		table.insert(allCreatures, creature)
	end

	for _, creature in ipairs(allCreatures) do
		if id == "BaneCheck" then
			if creature.category == CATEGORY.BANE then
				creature.visible = widget:isChecked()
			end
		elseif id == "ArchfoeCheck" then
			if creature.category == CATEGORY.ARCHFOE then
				creature.visible = widget:isChecked()
			end
		elseif id == "NemesisCheck" then
			if creature.category == CATEGORY.NEMESIS then
				creature.visible = widget:isChecked()
			end
		elseif id == "NoKillsCheck" then
			if creature.kills < 1 then
				creature.visible = widget:isChecked()
			end
		elseif id == "FewKillsCheck" then
			if creature.kills ~= 0 and creature.kills < CONFIG[creature.category].PROWESS then
				creature.visible = widget:isChecked()
			end
		elseif id == "ProwessCheck" then
			if creature.kills ~= 0 and creature.kills >= CONFIG[creature.category].PROWESS and creature.kills <= CONFIG[creature.category].EXPERTISE then
				creature.visible = widget:isChecked()
			end
		elseif id == "ExpertiseCheck" then
			if creature.kills ~= 0 and creature.kills >= CONFIG[creature.category].EXPERTISE and creature.kills <= CONFIG[creature.category].MASTERY then
				creature.visible = widget:isChecked()
			end
		elseif id == "MasteryCheck" and creature.kills ~= 0 and creature.kills >= CONFIG[creature.category].MASTERY then
			creature.visible = widget:isChecked()
		end
	end

	Cyclopedia.ReadjustPages()
end

function Cyclopedia.ReadjustPages()
	local maxCategoriesPerPage = 8
	local allCreatures = {}

	for _, creatures in ipairs(Cyclopedia.Bosstiary.Creatures) do
		for _, creature in ipairs(creatures) do
			table.insert(allCreatures, creature)
		end
	end

	for _, creature in ipairs(Cyclopedia.Bosstiary.NotVisibleCreatures) do
		table.insert(allCreatures, creature)
	end

	table.sort(allCreatures, function(a, b)
		if a.name == "?" and b.name ~= "?" then
			return false
		elseif a.name ~= "?" and b.name == "?" then
			return true
		elseif a.unlocked and not b.unlocked then
			return true
		elseif not a.unlocked and b.unlocked then
			return false
		else
			return a.name < b.name
		end
	end)

	Cyclopedia.Bosstiary.Creatures = {}
	Cyclopedia.Bosstiary.NotVisibleCreatures = {}

	local page = 1

	Cyclopedia.Bosstiary.Creatures[page] = {}

	for i, creature in ipairs(allCreatures) do
		if creature.visible then
			table.insert(Cyclopedia.Bosstiary.Creatures[page], creature)

			if #Cyclopedia.Bosstiary.Creatures[page] == maxCategoriesPerPage then
				page = page + 1
				Cyclopedia.Bosstiary.Creatures[page] = {}
			end
		else
			table.insert(Cyclopedia.Bosstiary.NotVisibleCreatures, creature)
		end
	end

	local totalVisible = 0

	for _, pageCreatures in ipairs(Cyclopedia.Bosstiary.Creatures) do
		totalVisible = totalVisible + #pageCreatures
	end

	Cyclopedia.Bosstiary.TotalPages = math.ceil(totalVisible / maxCategoriesPerPage)

	if Cyclopedia.Bosstiary.Page > Cyclopedia.Bosstiary.TotalPages then
		Cyclopedia.Bosstiary.Page = 1
	end

	UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bosstiary.Page, Cyclopedia.Bosstiary.TotalPages))
	Cyclopedia.LoadBosstiaryCreature(Cyclopedia.Bosstiary.Page)
	Cyclopedia.verifyBosstiaryButtons()
end
