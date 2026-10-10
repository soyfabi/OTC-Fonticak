-- chunkname: @/game_cyclopedia/tab/boss_slots/boss_slots.lua

local UI

local OPCODE_BOSSTIARY_OPEN_SLOTS = 0xAF

local function requestBossSlotsWindow()
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return
	end

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_BOSSTIARY_OPEN_SLOTS)
	protocolGame:send(msg)
end

function Cyclopedia.clearBossSlotsUI()
	if UI and not UI:isDestroyed() then
		if UI.SearchEdit and not UI.SearchEdit:isDestroyed() then
			pcall(function()
				UI.SearchEdit:ungrabKeyboard()
			end)
		end
		UI:destroy()
	end

	if Cyclopedia.BossSlots then
		Cyclopedia.BossSlots.lastSelected = nil
		Cyclopedia.BossSlots.removePrices = nil
	end

	UI = nil
end

function showBossSlot()
	local container = modules.game_cyclopedia.getContentContainer and modules.game_cyclopedia.getContentContainer() or contentContainer
	if UI and not UI:isDestroyed() then
		UI:show()
		requestBossSlotsWindow()
		if Cyclopedia.setBossSlotTabChrome then
			Cyclopedia.setBossSlotTabChrome()
		end
		return
	end

	Cyclopedia.clearBossSlotsUI()

	UI = g_ui.loadUI("boss_slots", container)

	function UI.onDestroy()
		UI = nil

		if Cyclopedia.BossSlots then
			Cyclopedia.BossSlots.lastSelected = nil
		end
	end

	UI:show()
	UI.RightBase.LockLabel:setText("Unlocks at 1500 Boss Points")
	requestBossSlotsWindow()
	if Cyclopedia.setBossSlotTabChrome then
		Cyclopedia.setBossSlotTabChrome()
	end

	Cyclopedia.BossSlots.UnlockBosses = {}
end

local CATEGORY = {
	BANE = 0,
	ARCHFOE = 1,
	NEMESIS = 2
}
local SLOT_STATE = {
	EMPTY = 1,
	ACTIVE = 2,
	LOCKED = 0
}
local ICONS = {
	[CATEGORY.BANE] = "/images/icons/icon-bosstiary-bane",
	[CATEGORY.ARCHFOE] = "/images/icons/icon-bosstiary-archfoe",
	[CATEGORY.NEMESIS] = "/images/icons/icon-bosstiary-nemesis"
}
local SLOTS = {
	[1] = "LeftBase",
	[2] = "RightBase"
}
local CONFIG = {
	[0] = {
		MASTERY = 300,
		PROWESS = 25,
		EXPERTISE = 100
	},
	{
		MASTERY = 60,
		PROWESS = 5,
		EXPERTISE = 20
	},
	{
		MASTERY = 5,
		PROWESS = 1,
		EXPERTISE = 3
	}
}

Cyclopedia.BossSlots = {}

local function resolveBossSlotLook(bossId)
	bossId = tonumber(bossId)
	if not bossId or bossId <= 0 then
		return nil, "?"
	end

	local outfit
	local name
	local bosstiary = Cyclopedia.Bosstiary

	if bosstiary then
		outfit = bosstiary.OutfitsByRaceId and bosstiary.OutfitsByRaceId[bossId]
		name = bosstiary.NamesByRaceId and bosstiary.NamesByRaceId[bossId]

		local meta = bosstiary.TrackerMetaByRaceId and bosstiary.TrackerMetaByRaceId[bossId]
		if meta then
			if meta.name and meta.name ~= "" and meta.name ~= "?" then
				name = meta.name
			end
			if meta.outfit and (meta.outfit.type or 0) > 0 then
				outfit = meta.outfit
			end
		end

		if bosstiary.PendingServerData then
			for _, entry in ipairs(bosstiary.PendingServerData) do
				if tonumber(entry.raceId) == bossId then
					if (not outfit or (outfit.type or 0) == 0) and entry.outfit and (entry.outfit.type or 0) > 0 then
						outfit = entry.outfit
					end
					if (not name or name == "" or name == "?") and entry.name and entry.name ~= "" and entry.name ~= "?" then
						name = entry.name
					end
					break
				end
			end
		end
	end

	if protoData and protoData[bossId] and (protoData[bossId].type or 0) > 0 then
		if not outfit or (outfit.type or 0) == 0 then
			outfit = protoData[bossId]
		end
	end

	local raceData = g_things.getRaceData(bossId)
	if raceData and raceData.raceId ~= 0 then
		if (not outfit or (outfit.type or 0) == 0) and raceData.outfit and (raceData.outfit.type or 0) > 0 then
			outfit = raceData.outfit
		end
		if (not name or name == "" or name == "?") and raceData.name and raceData.name ~= "" then
			name = raceData.name
		end
	end

	if not name or name == "" then
		name = "?"
	end

	return outfit, name
end

local function applyBossSlotCreatureSprite(spriteWidget, outfit)
	if not spriteWidget or not outfit or (outfit.type or 0) <= 0 then
		return
	end

	spriteWidget:setOutfit(outfit)
	if spriteWidget.getCreature then
		local creature = spriteWidget:getCreature()
		if creature and creature.setStaticWalking then
			creature:setStaticWalking(1000)
		end
	end
end

local function bossSlotListNeedsBosstiaryData()
	if not Cyclopedia.BossSlots.UnlockBosses then
		return false
	end

	for _, entry in ipairs(Cyclopedia.BossSlots.UnlockBosses) do
		local outfit, name = resolveBossSlotLook(entry.bossId)
		if (not outfit or (outfit.type or 0) == 0) or not name or name == "?" then
			return true
		end
	end

	return false
end

function Cyclopedia.refreshBossSlotsFromCachedBosstiary()
	if Cyclopedia.BossSlots and Cyclopedia.BossSlots.lastSlotsData then
		Cyclopedia.loadBossSlots(Cyclopedia.BossSlots.lastSlotsData)
	end
end

local function getPlayerTotalGold(player)
	if not player then
		return 0
	end

	if player.getTotalMoney then
		return player:getTotalMoney() or 0
	end

	return (player:getResourceBalance(ResourceBank) or 0) + (player:getResourceBalance(ResourceInventary) or 0)
end

local function canAffordGoldCost(player, cost)
	return (cost or 0) <= getPlayerTotalGold(player)
end

local function refreshBossSlotsRemoveAffordability()
	if not UI then
		return
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	for slotNumber = 1, 2 do
		local widget = UI[SLOTS[slotNumber]]
		local removePrice = Cyclopedia.BossSlots.removePrices and Cyclopedia.BossSlots.removePrices[slotNumber]

		if widget and widget.ActivedBoss and widget.ActivedBoss:isVisible() and removePrice then
			local canAfford = canAffordGoldCost(player, removePrice)

			widget.ActivedBoss.Value:setColor(canAfford and "#C0C0C0" or "#D33C3C")
			widget.ActivedBoss.RemoveButton:setEnabled(canAfford)
		end
	end
end

function Cyclopedia.refreshBossSlotsRemoveAffordability()
	refreshBossSlotsRemoveAffordability()
end

local function refreshTopBossPointsProgress()
	local lastProgress = Cyclopedia.BossSlots.lastPointsProgress

	if lastProgress then
		Cyclopedia.setBosstiarySlotsProgress(lastProgress.value, lastProgress.maxValue)
	end
end

local function updateTopBossPointsBarWidth()
	if not UI or not UI.TopBase or not UI.TopBase.PointsBar then
		return
	end

	local defaultBarWidth = 278
	local topBase = UI.TopBase
	local pointsLabel = UI.TopBase.PointsLabel
	local infoLabel = UI.TopBase.InfoLabel
	local infoIcon = UI.TopBase.InfoIcon
	local pointsBar = UI.TopBase.PointsBar

	if not pointsLabel or not infoLabel or not infoIcon then
		pointsBar:setWidth(defaultBarWidth)
		refreshTopBossPointsProgress()

		return
	end

	local topWidth = topBase:getWidth() or 0

	if topWidth <= 0 then
		pointsBar:setWidth(defaultBarWidth)
		refreshTopBossPointsProgress()

		return
	end

	local leftUsed = 10 + (pointsLabel:getWidth() or 0) + 11
	local rightUsed = (infoLabel:getWidth() or 0) + 9 + (infoIcon:getWidth() or 0) + 10
	local gap = 9
	local availableWidth = topWidth - leftUsed - rightUsed - gap

	if availableWidth <= 0 then
		pointsBar:setWidth(1)
		refreshTopBossPointsProgress()

		return
	end

	pointsBar:setWidth(math.min(defaultBarWidth, availableWidth))
	refreshTopBossPointsProgress()
end

function Cyclopedia.loadBossSlots(data)
	if not UI or not UI.Sprite then
		return
	end

	Cyclopedia.BossSlots.lastSlotsData = data
	Cyclopedia.BossSlots.UnlockBosses = {}

	local unlockedBossIds = {}
	local boostedBossId = tonumber(data.boostedBossId) or 0
	local raceData = boostedBossId > 0 and g_things.getRaceData(boostedBossId) or nil
	local todaySlot = data.todaySlotData

	local function resolveBoostedBossLook()
		local outfit = data.boostedBossOutfit
		local name = data.boostedBossName

		if Cyclopedia.Bosstiary and Cyclopedia.Bosstiary.OutfitsByRaceId and boostedBossId > 0 then
			if (not outfit or (outfit.type or 0) == 0) and Cyclopedia.Bosstiary.OutfitsByRaceId[boostedBossId] then
				outfit = Cyclopedia.Bosstiary.OutfitsByRaceId[boostedBossId]
			end
			if (not name or name == "") and Cyclopedia.Bosstiary.NamesByRaceId and Cyclopedia.Bosstiary.NamesByRaceId[boostedBossId] then
				name = Cyclopedia.Bosstiary.NamesByRaceId[boostedBossId]
			end
		end

		if raceData then
			if (not outfit or (outfit.type or 0) == 0) and raceData.outfit and (raceData.outfit.type or 0) > 0 then
				outfit = raceData.outfit
			end
			if (not name or name == "") and raceData.name and raceData.name ~= "" then
				name = raceData.name
			end
		end

		return outfit, name
	end

	local boostedOutfit, boostedName = resolveBoostedBossLook()

	UI.TopBase.InfoLabel:setText(string.format("Equipment Loot Bonus: %d%% Next: %d%%", data.currentBonus or 0, data.nextBonus or 0))
	updateTopBossPointsBarWidth()
	scheduleEvent(updateTopBossPointsBarWidth, 1)
	Cyclopedia.setBosstiarySlotsProgress(data.playerPoints or 0, data.totalPointsNextBonus or 0)

	local function format(string)
		if not string or #string == 0 then
			return "?"
		end
		if #string > 18 then
			return string:sub(1, 15) .. "..."
		else
			return string
		end
	end

	local unlockedBosses = data.bossIdSlotTwo

	if todaySlot and boostedBossId > 0 then
		if boostedOutfit and (boostedOutfit.type or 0) > 0 and UI.Sprite then
			UI.Sprite:setOutfit(boostedOutfit)
			if UI.Sprite.getCreature then
				local creature = UI.Sprite:getCreature()
				if creature and creature.setStaticWalking then
					creature:setStaticWalking(1000)
				end
			end
		end

		local bossRace = tonumber(todaySlot.bossRace) or 0
		local bossConfig = CONFIG[bossRace] or CONFIG[0]
		local boostedKillCount = todaySlot.killCount or 0
		local fullText = ""

		if boostedKillCount >= bossConfig.MASTERY then
			fullText = "(fully unlocked)"
		end

		local progress = UI.BoostedProgress

		if progress then
			if progress.ProgressBorder1 then
				progress.ProgressBorder1:setTooltip(string.format(" %d / %d %s", boostedKillCount, bossConfig.PROWESS, fullText))
			end
			if progress.ProgressBorder2 then
				progress.ProgressBorder2:setTooltip(string.format(" %d / %d %s", boostedKillCount, bossConfig.EXPERTISE, fullText))
			end
			if progress.ProgressBorder3 then
				progress.ProgressBorder3:setTooltip(string.format(" %d / %d %s", boostedKillCount, bossConfig.MASTERY, fullText))
			end
			Cyclopedia.setBosstiaryBossStars(progress, boostedKillCount, bossConfig)
			Cyclopedia.setBosstiarySlotsBossProgress(progress, boostedKillCount, bossConfig.PROWESS, bossConfig.EXPERTISE, bossConfig.MASTERY)
		end

		if UI.MainLabel then
			UI.MainLabel:setText(string.format("Equipment loot bonus: %d%%\nKill bonus: %dx", todaySlot.lootBonus or 0, todaySlot.killBonus or 1))
		end

		if UI.MidTitle then
			UI.MidTitle:setText(string.format("Boosted Boss: %s", format(boostedName)))
		end

		if UI.TypeIcon and ICONS[bossRace] then
			UI.TypeIcon:setImageSource(ICONS[bossRace])

			local tooltip = "Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 5\nExpertise: 15\nMastery: 30"

			if bossRace == CATEGORY.ARCHFOE then
				tooltip = "Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60"
			elseif bossRace == CATEGORY.NEMESIS then
				tooltip = "Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60"
			end

			UI.TypeIcon:setTooltip(tooltip)
		end
	else
		if UI.MidTitle then
			UI.MidTitle:setText("Boosted Boss: None")
		end
		if UI.MainLabel then
			UI.MainLabel:setText("No boosted boss today.")
		end
	end

	for i, unlockData in ipairs(data.bossesUnlockedData or {}) do
		if not unlockData then
			break
		end

		if not unlockedBossIds[unlockData.bossId] then
			unlockedBossIds[unlockData.bossId] = true

			local outfit, bossName = resolveBossSlotLook(unlockData.bossId)
			local data_t = {
				visible = true,
				bossId = unlockData.bossId,
				category = unlockData.bossRace,
				name = bossName,
				outfit = outfit
			}

			table.insert(Cyclopedia.BossSlots.UnlockBosses, data_t)
		end
	end

	if Cyclopedia.BossSlots.UnlockBosses then
		table.sort(Cyclopedia.BossSlots.UnlockBosses, function(a, b)
			return a.name < b.name
		end)

		if data.isSlotOneUnlocked or data.isSlotTwoUnlocked then
			Cyclopedia.BossSlotChangeSlot(data, unlockedBosses)
		end
	end

	if bossSlotListNeedsBosstiaryData() and Cyclopedia.requestBosstiaryDataForTracker then
		Cyclopedia._bossSlotsAwaitingBosstiaryData = true
		Cyclopedia.requestBosstiaryDataForTracker()
	elseif bossSlotListNeedsBosstiaryData() and Cyclopedia.requestBosstiaryData then
		Cyclopedia._bossSlotsAwaitingBosstiaryData = true
		Cyclopedia.requestBosstiaryData()
	end
end

function Cyclopedia.BossSlotChangeSlot(data, unlockedBosses)
	local slots = {
		{
			slotNumber = 1,
			isUnlocked = data.isSlotOneUnlocked,
			slotData = data.slotOneData,
			bossId = data.bossIdSlotOne
		},
		{
			slotNumber = 2,
			isUnlocked = data.isSlotTwoUnlocked,
			slotData = data.slotTwoData,
			bossId = data.bossIdSlotTwo
		}
	}

	for _, slotInfo in ipairs(slots) do
		if slotInfo.isUnlocked then
			local widget = UI[SLOTS[slotInfo.slotNumber]]

			if slotInfo.slotData then
				Cyclopedia.setActiveSlot(widget, slotInfo.slotNumber, slotInfo.slotData, data, slotInfo.bossId)
			elseif data.bossesUnlocked and #data.bossesUnlockedData > 0 then
				Cyclopedia.setLockedSlot(widget, slotInfo.slotNumber, unlockedBosses)
			else
				Cyclopedia.setEmptySlot(widget, slotInfo.slotNumber, slotInfo.bossId)
			end
		end
	end
end

function Cyclopedia.setEmptySlot(widget, slot, bossIdSlotTwo)
	widget.LockLabel:setVisible(true)
	widget.SelectBoss:setVisible(false)
	widget.ActivedBoss:setVisible(false)
	widget:setText(string.format("Slot %d: Locked", slot))
	widget.LockLabel:setText(string.format("Unlocks at %d Boss Points", bossIdSlotTwo))
end

function Cyclopedia.setLockedSlot(widget, slot, unlockedBosses)
	widget.LockLabel:setVisible(false)
	widget.SelectBoss:setVisible(true)
	widget.ActivedBoss:setVisible(false)
	widget:setText(string.format("Slot %d: Select Boss", slot))

	Cyclopedia.BossSlots.lastSelected = nil

	widget.SelectBoss.ListBase.List:destroyChildren()

	local function format(string)
		if #string > 12 then
			return string:sub(1, 9) .. "..."
		else
			return string
		end
	end

	for _, internalData in ipairs(Cyclopedia.BossSlots.UnlockBosses) do
		local outfit = internalData.outfit
		local bossName = internalData.name
		if not outfit or (outfit.type or 0) == 0 or not bossName or bossName == "?" then
			outfit, bossName = resolveBossSlotLook(internalData.bossId)
			internalData.outfit = outfit
			internalData.name = bossName
		end

		local internalWidget = g_ui.createWidget("SelectBossBossSlots", widget.SelectBoss.ListBase.List)

		internalWidget:setId(tostring(internalData.bossId))
		applyBossSlotCreatureSprite(internalWidget.Sprite, outfit)
		internalWidget:setText(format(bossName))
		internalWidget.TypeIcon:setImageSource(ICONS[internalData.category])

		local tooltip = internalData.category == CATEGORY.ARCHFOE and "Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60" or "Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60"

		if internalData.category ~= CATEGORY.ARCHFOE then
			tooltip = "Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 5\nExpertise: 15\nMastery: 30"
		end

		internalWidget.TypeIcon:setTooltip(tooltip)
	end

	widget.SelectBoss.SelectButton:setEnabled(false)

	function widget.SelectBoss.SelectButton.onClick()
		g_game.requestBossSlotAction(slot, Cyclopedia.BossSlots.lastSelected:getId())

		Cyclopedia.BossSlots.UnlockBosses = {}
	end
end

function Cyclopedia.setActiveSlot(widget, slot, slotData, data, bossId)
	local outfit, bossName = resolveBossSlotLook(bossId)
	local currentKills = slotData.killCount or slotData.killBonus or 0

	widget.LockLabel:setVisible(false)
	widget.SelectBoss:setVisible(false)
	widget.ActivedBoss:setVisible(true)
	widget:setText(string.format("Slot %d: %s", slot, bossName))
	widget.ActivedBoss.TypeIcon:setImageSource(ICONS[slotData.bossRace])
	Cyclopedia.setBosstiarySlotsBossProgress(widget.ActivedBoss.Progress, currentKills, CONFIG[slotData.bossRace].PROWESS, CONFIG[slotData.bossRace].EXPERTISE, CONFIG[slotData.bossRace].MASTERY)

	local tooltip = slotData.bossRace == CATEGORY.ARCHFOE and "Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60" or "Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60"

	if slotData.bossRace ~= CATEGORY.ARCHFOE then
		tooltip = "Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 5\nExpertise: 15\nMastery: 30"
	end

	widget.ActivedBoss.TypeIcon:setTooltip(tooltip)
	widget.ActivedBoss.Progress.ProgressBorder1:setTooltip()

	local fullText = currentKills >= CONFIG[slotData.bossRace].MASTERY and "(fully unlocked)" or ""
	local progress = widget.ActivedBoss.Progress

	progress.ProgressBorder1:setTooltip(string.format(" %d / %d %s", currentKills, CONFIG[slotData.bossRace].PROWESS, fullText))
	progress.ProgressBorder2:setTooltip(string.format(" %d / %d %s", currentKills, CONFIG[slotData.bossRace].EXPERTISE, fullText))
	progress.ProgressBorder3:setTooltip(string.format(" %d / %d %s", currentKills, CONFIG[slotData.bossRace].MASTERY, fullText))
	Cyclopedia.setBosstiaryBossStars(progress, currentKills, CONFIG[slotData.bossRace])
	applyBossSlotCreatureSprite(widget.ActivedBoss.Sprite, outfit)
	widget.ActivedBoss.EquipmentLabel:setText(string.format("Equipment loot bonus: %d%%", slotData.lootBonus))

	Cyclopedia.BossSlots.removePrices = Cyclopedia.BossSlots.removePrices or {}
	Cyclopedia.BossSlots.removePrices[slot] = slotData.removePrice

	widget.ActivedBoss.Value:setText(comma_value(slotData.removePrice))

	local player = g_game.getLocalPlayer()

	if player then
		local canAfford = canAffordGoldCost(player, slotData.removePrice)

		widget.ActivedBoss.Value:setColor(canAfford and "#C0C0C0" or "#D33C3C")
		widget.ActivedBoss.RemoveButton:setEnabled(canAfford)
	end

	function widget.ActivedBoss.RemoveButton.onClick()
		g_game.requestBossSlotAction(slot, 0)
	end

	widget.ActivedBoss.RemoveButton:setTooltip(string.format("It will cost you %s gold to remove the currently selected boss from this slot.", comma_value(slotData.removePrice)))
end

function Cyclopedia.setBosstiarySlotsProgress(value, maxValue)
	if not UI or not UI.TopBase or not UI.TopBase.PointsBar then
		return
	end

	Cyclopedia.BossSlots.lastPointsProgress = {
		value = value,
		maxValue = maxValue
	}

	local fill = UI.TopBase.PointsBar.fill

	if not fill then
		return
	end

	local barWidth = UI.TopBase.PointsBar:getWidth() or 0

	if barWidth <= 0 then
		barWidth = 278
	end

	local progressValue = maxValue > 0 and math.min(value, maxValue) or 0
	local width = maxValue > 0 and math.floor(progressValue / maxValue * barWidth) or 0

	if value <= 0 or width < 1 then
		fill:setVisible(false)
		UI.TopBase.PointsBar.Value:setText(string.format("%d/%d", value, maxValue))

		return
	end

	fill:setVisible(true)

	local rect = {
		height = 18,
		y = 0,
		x = 0,
		width = width
	}

	fill:setImageRect(rect)
	fill:setImageClip(rect)
	UI.TopBase.PointsBar.Value:setText(string.format("%d/%d", value, maxValue))
end

function Cyclopedia.setBosstiarySlotsBossProgress(object, value, firstGoal, secondGoal, thirdGoal)
	local totalWidth = 126
	local segmentWidth = totalWidth / 3
	local clampedValue = math.max(value or 0, 0)
	local width = 0

	if clampedValue > 0 and firstGoal > 0 then
		local firstProgress = math.min(clampedValue, firstGoal) / firstGoal

		width = width + firstProgress * segmentWidth
	end

	if firstGoal < clampedValue and firstGoal < secondGoal then
		local secondProgress = math.min(clampedValue - firstGoal, secondGoal - firstGoal) / (secondGoal - firstGoal)

		width = width + secondProgress * segmentWidth
	end

	if secondGoal < clampedValue and secondGoal < thirdGoal then
		local thirdProgress = math.min(clampedValue - secondGoal, thirdGoal - secondGoal) / (thirdGoal - secondGoal)

		width = width + thirdProgress * segmentWidth
	end

	local rect = {
		height = 12,
		y = 0,
		x = 0,
		width = math.floor(math.min(width, totalWidth))
	}

	if clampedValue >= 0 and rect.width < 1 then
		object.fill:setVisible(false)
	else
		object.fill:setVisible(true)
	end

	object.fill:setImageRect(rect)
	object.fill:setImageClip(rect)
	object.ProgressValue:setText(clampedValue)

	if thirdGoal <= clampedValue then
		object.fill:setImageSource("/images/bars/progressbar-green-large")
	else
		object.fill:setImageSource("/images/bars/progressbar-orange-large")
	end
end

function Cyclopedia.bossSlotSelectBoss(widget)
	local button = widget:getParent():getParent():getParent().SelectButton

	for i = 1, widget:getParent():getChildCount() do
		local child = widget:getParent():getChildByIndex(i)

		child:setChecked(false)
	end

	widget:setChecked(true)

	Cyclopedia.BossSlots.lastSelected = widget

	button:setEnabled(true)
end

function Cyclopedia.readjustSelectBoss()
	local slot = 1

	if not UI.LeftBase.SelectBoss:isVisible() then
		slot = 2
	end

	local icons = {
		[CATEGORY.BANE] = "/images/icons/icon-bosstiary-bane",
		[CATEGORY.ARCHFOE] = "/images/icons/icon-archfoe",
		[CATEGORY.NEMESIS] = "/images/icons/icon-bosstiary-nemesis"
	}

	local function format(string)
		if #string > 12 then
			return string:sub(1, 9) .. "..."
		else
			return string
		end
	end

	local widget = UI[SLOTS[slot]]

	Cyclopedia.BossSlots.lastSelected = nil

	widget.SelectBoss.ListBase.List:destroyChildren()

	for _, internalData in ipairs(Cyclopedia.BossSlots.UnlockBosses) do
		if internalData.visible then
			local outfit = internalData.outfit
			local bossName = internalData.name
			if not outfit or (outfit.type or 0) == 0 or not bossName or bossName == "?" then
				outfit, bossName = resolveBossSlotLook(internalData.bossId)
				internalData.outfit = outfit
				internalData.name = bossName
			end

			local internalWidget = g_ui.createWidget("SelectBossBossSlots", widget.SelectBoss.ListBase.List)

			internalWidget:setId(tostring(internalData.bossId))
			applyBossSlotCreatureSprite(internalWidget.Sprite, outfit)
			internalWidget:setText(format(bossName))
			internalWidget.TypeIcon:setImageSource(icons[internalData.category])

			local tooltip = "Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 5\nExpertise: 15\nMastery: 30"

			tooltip = internalData.category == CATEGORY.ARCHFOE and "Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60" or "Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: 10\nExpertise: 30\nMastery: 60"

			internalWidget.TypeIcon:setTooltip(tooltip)
		end
	end

	widget.SelectBoss.SelectButton:setEnabled(false)
end

function Cyclopedia.SelectBossSearchText(text, clear, widget)
	if clear then
		widget:getParent().SearchEdit:setText("")
	end

	if text ~= "" then
		for _, creature in ipairs(Cyclopedia.BossSlots.UnlockBosses) do
			if string.find(creature.name:lower(), text:lower()) == nil then
				creature.visible = false
			else
				creature.visible = true
			end
		end
	else
		for _, creature in ipairs(Cyclopedia.BossSlots.UnlockBosses) do
			creature.visible = true
		end
	end

	Cyclopedia.readjustSelectBoss()
end
