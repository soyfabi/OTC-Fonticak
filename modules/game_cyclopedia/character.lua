local characterPanel = nil
local UI = nil
local selectedPanel = "InfoBase"
local lastOffenceData = nil
local sidebarButtons = {}
local playerConnections = nil
local openedCategory = nil
local selectedInventorySlot = nil
local infoItemSelected = false
local selectedCharacterItem = nil
local characterItemInfoCache = {}
local pendingCharacterItemInfo = {}
local characterGameConnection = nil

local OPCODE_ITEM_DETAILS = 0xC7

local DETAIL_LABEL_COLUMN_WIDTH = 100

local ICON_BASE = "/game_cyclopedia/images/ui/icon/icon-character-"
local ARROW_DOWN = "/game_cyclopedia/images/ui/arrow-down"
local ARROW_RIGHT = "/game_cyclopedia/images/ui/arrow-right"
local CATEGORY_BASE_HEIGHT = 22
local SUBCATEGORY_HEIGHT = 20
local SUBCATEGORY_ARROW_MARGIN_RIGHT = 6
local SUBCATEGORY_ARROW_MARGIN_RIGHT_PRESSED = 5

local INVENTORY_SLOT_STYLES = {
	[InventorySlotHead] = { icon = "/images/inventory/inventory_head", name = "HeadSlot" },
	[InventorySlotNeck] = { icon = "/images/inventory/inventory_neck", name = "NeckSlot" },
	[InventorySlotBack] = { icon = "/images/inventory/inventory_back", name = "BackSlot" },
	[InventorySlotBody] = { icon = "/images/inventory/inventory_torso", name = "BodySlot" },
	[InventorySlotRight] = { icon = "/images/inventory/inventory_right_hand", name = "RightSlot" },
	[InventorySlotLeft] = { icon = "/images/inventory/inventory_left_hand", name = "LeftSlot" },
	[InventorySlotLeg] = { icon = "/images/inventory/inventory_legs", name = "LegSlot" },
	[InventorySlotFeet] = { icon = "/images/inventory/inventory_feet", name = "FeetSlot" },
	[InventorySlotFinger] = { icon = "/images/inventory/inventory_finger", name = "FingerSlot" },
	[InventorySlotAmmo] = { icon = "/images/inventory/inventory_hip", name = "AmmoSlot" }
}

local CHARACTER_BUTTON_ICONS = {
	player = "/game_cyclopedia/images/ui/icon/inspect-player",
	outfit = "/game_cyclopedia/images/ui/icon/inspect-bp"
}

local CHARACTER_BUTTON_ICON_OFFSET = {
	player = {
		pressed = "1 1",
		idle = "0 0"
	},
	outfit = {
		pressed = "0 1",
		idle = "-1 0"
	}
}

local function refreshCharacterButtonIcon(widget, pressed)
	if not widget or widget:isDestroyed() then
		return
	end

	local mode = widget.state == 2 and "outfit" or "player"
	local offsetKey = pressed and "pressed" or "idle"
	widget:setIconOffset(topoint(CHARACTER_BUTTON_ICON_OFFSET[mode][offsetKey]))
end

local function bindCharacterButtonIcon(widget)
	if not widget or widget:isDestroyed() then
		return
	end

	refreshCharacterButtonIcon(widget, false)

	function widget:onMousePress(mousePos, mouseButton)
		if mouseButton == MouseLeftButton then
			refreshCharacterButtonIcon(self, true)
		end

		return false
	end

	function widget:onMouseRelease(mousePos, mouseButton)
		if mouseButton == MouseLeftButton then
			refreshCharacterButtonIcon(self, false)
		end

		return false
	end
end

local function applyCharacterOutfitPreview(spriteWidget)
	if not spriteWidget or spriteWidget:isDestroyed() then
		return
	end

	spriteWidget:setSize({ width = 128, height = 128 })
	if spriteWidget.setCenter then
		spriteWidget:setCenter(true)
	end
	if spriteWidget.setCreatureSize then
		spriteWidget:setCreatureSize(128)
	end
end

local function applyCharacterOutfitWidgets()
	if not UI then
		return
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local outfit = player:getOutfit()
	if UI.CharacterBase then
		local outfitWidget = UI.CharacterBase:recursiveGetChildById("Outfit")
		if outfitWidget then
			outfitWidget:setOutfit(outfit)
		end
	end

	if UI.InfoBase and UI.InfoBase.outfitPanel and UI.InfoBase.outfitPanel.Sprite then
		UI.InfoBase.outfitPanel.Sprite:setOutfit(outfit)
		applyCharacterOutfitPreview(UI.InfoBase.outfitPanel.Sprite)
	end
end

local function setCharacterButtonIcon(widget, mode)
	if not widget then
		return
	end

	widget:setIcon(CHARACTER_BUTTON_ICONS[mode])
	if widget.setIconClip then
		widget:setIconClip("0 0 33 33")
	end
	refreshCharacterButtonIcon(widget, false)
end

local SKILL_WIDGET_IDS = {
	[Skill.Fist] = "skillId0",
	[Skill.Club] = "skillId1",
	[Skill.Sword] = "skillId2",
	[Skill.Axe] = "skillId3",
	[Skill.Distance] = "skillId4",
	[Skill.Shielding] = "skillId5",
	[Skill.Fishing] = "skillId6"
}

local function getCharacterStatsPanel()
	return UI and UI.CharacterStats
end

local function formatPercent(value)
	local percentValue = math.floor((tonumber(value) or 0) * 10000 + 0.5) / 100
	if percentValue == 0 then
		return "0%"
	end

	local sign = percentValue > 0 and "+" or ""
	return sign .. percentValue .. "%"
end

local function formatClockTime(totalMinutes)
	local hours = math.floor((totalMinutes or 0) / 60)
	local minutes = (totalMinutes or 0) % 60
	return string.format("%d:%02d", hours, minutes)
end

local function setCharacterSkillValue(id, value, color)
	local statsPanel = getCharacterStatsPanel()
	if not statsPanel then
		return
	end

	local skill = statsPanel:recursiveGetChildById(id)
	if not skill then
		return
	end

	local widget = skill:getChildById("value")
	if not widget then
		return
	end

	widget:setText(tostring(value))
	widget:setColor(color or "#C0C0C0")
end

local function setCharacterSkillTooltip(id, tooltip)
	local statsPanel = getCharacterStatsPanel()
	if not statsPanel then
		return
	end

	local skill = statsPanel:recursiveGetChildById(id)
	if not skill then
		return
	end

	if tooltip and tooltip ~= "" then
		skill:setTooltip(tooltip)
	else
		skill:removeTooltip()
	end
end

local function setCharacterSkillPercent(id, percent, tooltip, color)
	local statsPanel = getCharacterStatsPanel()
	if not statsPanel then
		return
	end

	local skill = statsPanel:recursiveGetChildById(id)
	if not skill then
		return
	end

	local widget = skill:getChildById("percent")
	if not widget then
		return
	end

	widget:setPercent(math.floor((percent or 0) / 100))

	if tooltip then
		widget:setTooltip(tooltip)
	end

	if color then
		widget:setBackgroundColor(color)
	end
end

local function buildSkillTooltip(value, baseValue, loyaltyField, rawPercent)
	local skillsModule = modules.game_skills
	local percentLine

	if skillsModule and skillsModule.skillPercentToGoTooltipForDisplay then
		percentLine = skillsModule.skillPercentToGoTooltipForDisplay(rawPercent)
	else
		percentLine = tr("You have %s percent to go", string.format("%.2f", 100 - (rawPercent or 0) / 100))
	end

	if not skillsModule or not skillsModule.resolveSkillBonusesForDisplay then
		return percentLine
	end

	local itemBonus, loyaltyBonus = skillsModule.resolveSkillBonusesForDisplay(value, baseValue, loyaltyField or 0)
	if itemBonus > 0 or loyaltyBonus > 0 then
		local breakdown = skillsModule.buildLoyaltySkillTooltipLineForDisplay(value, baseValue, loyaltyField or 0)
		return breakdown .. "\n" .. percentLine
	end

	return percentLine
end

local function updateCharacterSkill(id, value, baseValue, loyaltyField, rawPercent, color)
	setCharacterSkillValue(id, value, color or "#C0C0C0")
	setCharacterSkillPercent(id, rawPercent)
	setCharacterSkillTooltip(id, buildSkillTooltip(value, baseValue, loyaltyField, rawPercent))
end

local function updateXpGainRate(player)
	local statsPanel = getCharacterStatsPanel()
	if not statsPanel or not player then
		return
	end

	local expGainRate = statsPanel:recursiveGetChildById("expGainRate")
	if not expGainRate then
		return
	end

	local skillsModule = modules.game_skills
	if skillsModule and skillsModule.updateXpGainRateWidget then
		skillsModule.updateXpGainRateWidget(expGainRate, player)
	end
end

local function refreshGeneralStatsFromPlayer()
	local player = g_game.getLocalPlayer()
	local statsPanel = getCharacterStatsPanel()
	if not player or not statsPanel then
		return
	end

	local levelPercent = player:getLevelPercent()
	local percentToGo = string.format("%.2f", 100 - (levelPercent or 0) / 100)
	local percentToGoText = tr("You have %s percent to go", percentToGo)

	setCharacterSkillValue("level", comma_value(player:getLevel()))
	setCharacterSkillTooltip("level", percentToGoText)
	setCharacterSkillPercent("level", levelPercent, percentToGoText)

	local currentExp = player:getExperience()
	setCharacterSkillValue("experience", comma_value(currentExp))

	local skillsModule = modules.game_skills
	local expNeeded = skillsModule and skillsModule.expToAdvance and skillsModule.expToAdvance(player:getLevel(), currentExp)
	if expNeeded and expNeeded > 0 then
		setCharacterSkillTooltip("experience", tr("%s XP for next level", comma_value(expNeeded)) .. "\n" .. percentToGoText)
	else
		setCharacterSkillTooltip("experience", nil)
	end

	updateXpGainRate(player)

	local health = player:getHealth()
	local maxHealth = player:getMaxHealth()
	setCharacterSkillValue("health", comma_value(health))
	setCharacterSkillTooltip("health", tr("You have %s of %s Hit Points left", comma_value(health), comma_value(maxHealth)))

	local mana = player:getMana()
	local maxMana = player:getMaxMana()
	setCharacterSkillValue("mana", comma_value(mana))
	setCharacterSkillTooltip("mana", tr("You have %s of %s Mana left", comma_value(mana), comma_value(maxMana)))

	setCharacterSkillValue("soul", player:getSoul())
	setCharacterSkillTooltip("soul", tr("You have %s Soul Points left", player:getSoul()))

	local freeCapacity = math.floor(player:getFreeCapacity())
	local totalCapacity = player:getTotalCapacity()
	setCharacterSkillValue("capacity", comma_value(freeCapacity))
	setCharacterSkillTooltip("capacity", tr("You have %s of %s Capacity left", comma_value(freeCapacity), comma_value(totalCapacity)))

	local speed = player:getSpeed()
	setCharacterSkillValue("speed", comma_value(speed), "#C0C0C0")
	setCharacterSkillTooltip("speed", tr("You have %s Speed", comma_value(speed)))

	local foodWidget = statsPanel:recursiveGetChildById("food")
	if foodWidget then
		if g_game.getFeature(GamePlayerRegenerationTime) and player.getRegenerationTime then
			foodWidget:show()
			local regenTime = player:getRegenerationTime()
			local minutes = math.floor(regenTime / 60)
			local seconds = regenTime % 60
			setCharacterSkillValue("food", string.format("%02d:%02d", minutes, seconds))
			if regenTime > 0 then
				local minutes = math.floor(regenTime / 60)
				local seconds = regenTime % 60
				setCharacterSkillTooltip("food", tr("You are regenerating hit points and mana for %s minutes and %s seconds", minutes, seconds))
			else
				setCharacterSkillTooltip("food", tr("You are hungry.\nEat something to regenerate hit points and mana over time"))
			end
		else
			foodWidget:hide()
		end
	end

	local staminaWidget = statsPanel:recursiveGetChildById("stamina")
	if staminaWidget then
		if player.getStamina then
			staminaWidget:show()
			local stamina = player:getStamina()
			local hours = math.floor(stamina / 60)
			local minutes = stamina % 60
			setCharacterSkillValue("stamina", formatClockTime(stamina))
			setCharacterSkillTooltip("stamina", tr("You have %s hours and %s minutes left", hours, minutes))
			setCharacterSkillPercent("stamina", math.floor(10000 * stamina / 2520), nil, stamina > 2340 and "green" or "#C06000")
		else
			staminaWidget:hide()
		end
	end

	local trainerWidget = statsPanel:recursiveGetChildById("trainer")
	if trainerWidget then
		if g_game.getFeature(GameOfflineTrainingTime) and player.getOfflineTrainingTime then
			trainerWidget:show()
			local offline = player:getOfflineTrainingTime()
			setCharacterSkillValue("trainer", formatClockTime(offline))
			setCharacterSkillTooltip("trainer", tr("You have %s hours and %s minutes of offline training time left", math.floor(offline / 60), offline % 60))
			setCharacterSkillPercent("trainer", math.floor(10000 * offline / 720), nil, "#C00000")
		else
			trainerWidget:hide()
		end
	end

	local magicLevel = player:getMagicLevel()
	local baseMagicLevel = player.getBaseMagicLevel and player:getBaseMagicLevel() or magicLevel
	local magicLoyalty = player.getMagicLoyalty and player:getMagicLoyalty() or 0
	local magicColor = magicLevel > baseMagicLevel and "#44AD25" or "#C0C0C0"
	updateCharacterSkill("magiclevel", magicLevel, baseMagicLevel, magicLoyalty, player:getMagicLevelPercent(), magicColor)

	for skillId, widgetId in pairs(SKILL_WIDGET_IDS) do
		local skillLevel = player:getSkillLevel(skillId)
		local baseSkill = player:getSkillBaseLevel(skillId)
		local loyaltySkill = player.getSkillLoyalty and player:getSkillLoyalty(skillId) or 0
		local skillColor = skillLevel > baseSkill and "#44AD25" or "#C0C0C0"
		updateCharacterSkill(widgetId, skillLevel, baseSkill, loyaltySkill, player:getSkillLevelPercent(skillId), skillColor)
	end
end

local function setStatRow(rowId, value, visible)
	if not characterPanel then
		return
	end

	local row = characterPanel:recursiveGetChildById(rowId)
	if not row then
		return
	end

	row:setVisible(visible ~= false)
	if visible == false then
		return
	end

	local valueLabel = row:getChildById("statValue")
	if valueLabel then
		valueLabel:setText(tostring(value))
	end
end

local function setSubStatRow(rowId, value, visible)
	setStatRow(rowId, value, visible)
end

local function hideAllOffenceRows()
	for _, rowId in ipairs({
		"convertedDamageRow",
		"lifeLeechRow",
		"manaLeechRow",
		"lifeGainOnHitRow",
		"lifeGainOnKillRow",
		"manaGainOnHitRow",
		"manaGainOnKillRow",
		"criticalChanceRow",
		"criticalChanceProficiencyRow",
		"criticalDamageRow",
		"criticalDamageProficiencyRow"
	}) do
		setStatRow(rowId, "", false)
	end
end

local function renderOffenceStats(data)
	if type(data) ~= "table" then
		return
	end

	lastOffenceData = data

	if not characterPanel or characterPanel:isDestroyed() then
		return
	end

	hideAllOffenceRows()
	setStatRow("flatDamageRow", math.floor((tonumber(data.damageAndHealing) or 0) + 0.5), true)
	setStatRow("attackValueRow", math.floor((tonumber(data.attackValue) or 0) + 0.5), true)

	local convertedValue = tonumber(data.convertedValue) or 0
	setStatRow("convertedDamageRow", formatPercent(convertedValue), convertedValue > 0.0001)

	local lifeLeech = tonumber(data.lifeLeech) or 0
	setStatRow("lifeLeechRow", formatPercent(lifeLeech), math.abs(lifeLeech) > 0.0001)

	local manaLeech = tonumber(data.manaLeech) or 0
	setStatRow("manaLeechRow", formatPercent(manaLeech), math.abs(manaLeech) > 0.0001)

	local lifeGainOnHit = math.floor((tonumber(data.lifeGainOnHit) or 0) + 0.5)
	setStatRow("lifeGainOnHitRow", lifeGainOnHit, lifeGainOnHit > 0)

	local lifeGainOnKill = math.floor((tonumber(data.lifeGainOnKill) or 0) + 0.5)
	setStatRow("lifeGainOnKillRow", lifeGainOnKill, lifeGainOnKill > 0)

	local manaGainOnHit = math.floor((tonumber(data.manaGainOnHit) or 0) + 0.5)
	setStatRow("manaGainOnHitRow", manaGainOnHit, manaGainOnHit > 0)

	local manaGainOnKill = math.floor((tonumber(data.manaGainOnKill) or 0) + 0.5)
	setStatRow("manaGainOnKillRow", manaGainOnKill, manaGainOnKill > 0)

	local criticalChance = tonumber(data.criticalChance) or 0
	setStatRow("criticalChanceRow", formatPercent(criticalChance), math.abs(criticalChance) > 0.0001)

	local criticalChanceProficiency = tonumber(data.criticalChanceProficiency) or 0
	setSubStatRow("criticalChanceProficiencyRow", formatPercent(criticalChanceProficiency), criticalChanceProficiency > 0.0001)

	local criticalDamage = tonumber(data.criticalDamage) or 0
	setStatRow("criticalDamageRow", formatPercent(criticalDamage), math.abs(criticalDamage) > 0.0001)

	local criticalDamageProficiency = tonumber(data.criticalDamageProficiency) or 0
	setSubStatRow("criticalDamageProficiencyRow", formatPercent(criticalDamageProficiency), criticalDamageProficiency > 0.0001)
end

local function getCharacterInventoryPanel()
	return UI and UI.InfoBase and UI.InfoBase.inventoryPanel
end

local function setInventorySlotSelected(widget, selected)
	if not widget or widget:isDestroyed() then
		return
	end

	if selected then
		widget:setBorderWidth(1)
		widget:setBorderColor("#FFFFFF")
	else
		widget:setBorderWidth(0)
	end
end

local function clearInventorySlotSelection()
	if selectedInventorySlot then
		local panel = getCharacterInventoryPanel()
		if panel then
			local widget = panel:getChildById("slot" .. selectedInventorySlot)
			setInventorySlotSelected(widget, false)
		end
		selectedInventorySlot = nil
	end
	selectedCharacterItem = nil
	infoItemSelected = false
end

local function appendDetailKeyValueRow(parent, key, value)
	local row = g_ui.createWidget("UIWidget", parent)
	row:setPhantom(true)
	row:setHeight(16)

	local keyLabel = g_ui.createWidget("Label", row)
	keyLabel:setText(key .. ":")
	keyLabel:setColor("#C0C0C0")
	keyLabel:setFont("verdana-11px-antialised")
	keyLabel:setTextAlign(AlignTopRight)
	keyLabel:setWidth(DETAIL_LABEL_COLUMN_WIDTH)
	keyLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
	keyLabel:addAnchor(AnchorTop, "parent", AnchorTop)

	local valueLabel = g_ui.createWidget("Label", row)
	valueLabel:setText(tostring(value or ""))
	valueLabel:setColor("#C0C0C0")
	valueLabel:setFont("verdana-11px-antialised")
	valueLabel:addAnchor(AnchorLeft, "prev", AnchorRight)
	valueLabel:addAnchor(AnchorTop, "parent", AnchorTop)
	valueLabel:setMarginLeft(8)
	valueLabel:setTextAutoResize(true)
end

local function getCharacterOutfitName(player)
	if not player then
		return nil
	end

	local outfit = player:getOutfit()
	local lookType = outfit and outfit.type
	if not lookType or lookType == 0 then
		return nil
	end

	if g_things and ThingCategoryCreature then
		local thingType = g_things.getThingType(lookType, ThingCategoryCreature)
		if thingType and thingType.getName then
			local name = thingType:getName()
			if name and name ~= "" and name ~= "unnamed" then
				return name
			end
		end
	end

	return nil
end

local function buildCharacterDescriptionRows()
	local player = g_game.getLocalPlayer()
	if not player then
		return {}
	end

	local rows = {
		{ tr("Level"), tostring(player:getLevel()) },
		{ tr("Vocation"), player:getVocationNameByClientId() or "" }
	}

	local outfitName = getCharacterOutfitName(player)
	if outfitName and outfitName ~= "" then
		table.insert(rows, { tr("Outfit"), outfitName })
	end

	return rows
end

local function renderCharacterOverviewDetails()
	if not UI or not UI.InfoBase or not UI.InfoBase.DetailsBase or not UI.InfoBase.DetailsBase.List then
		return
	end

	if infoItemSelected then
		return
	end

	UI.InfoBase.DetailsBase.List:destroyChildren()

	for _, row in ipairs(buildCharacterDescriptionRows()) do
		appendDetailKeyValueRow(UI.InfoBase.DetailsBase.List, row[1], row[2])
	end
end

local function showCharacterPlayerDetails()
	if not UI or not UI.InfoBase then
		return
	end

	clearInventorySlotSelection()

	local player = g_game.getLocalPlayer()
	if player and UI.InfoBase.InspectLabel then
		UI.InfoBase.InspectLabel:setText(tr("You are inspecting") .. ": " .. player:getName())
	end

	renderCharacterOverviewDetails()
end

local function resetCharacterInspectView()
	if not UI or not UI.InfoBase then
		return
	end

	UI.InfoBase.inventoryPanel:setVisible(true)
	UI.InfoBase.outfitPanel:setVisible(false)

	local characterButton = UI.InfoBase.CharacterButton
	if characterButton and characterButton.state ~= 1 then
		onCharacterInspectButton(characterButton)
	end
end

local function callItemMethod(item, method, ...)
	if item and item[method] then
		return item[method](item, ...)
	end
	return nil
end

local function isValidItemName(name)
	if not name or name == "" or name == "unnamed" then
		return false
	end

	local lowered = name:lower()
	return lowered ~= "unknown item" and lowered ~= "this object"
end

local function addUniqueItemId(ids, itemId)
	itemId = tonumber(itemId)
	if not itemId or itemId <= 0 then
		return
	end

	for _, existingId in ipairs(ids) do
		if existingId == itemId then
			return
		end
	end

	ids[#ids + 1] = itemId
end

local function collectCharacterItemIds(item)
	local ids = {}
	if not item then
		return ids
	end

	addUniqueItemId(ids, callItemMethod(item, "getId"))

	if item.getMarketData then
		local ok, marketData = pcall(function()
			return item:getMarketData()
		end)
		if ok and marketData then
			addUniqueItemId(ids, marketData.tradeAs)
			addUniqueItemId(ids, marketData.showAs)
		end
	end

	if Item and Item.create then
		local clientId = callItemMethod(item, "getId")
		if clientId and clientId > 0 then
			local ok, created = pcall(function()
				return Item.create(clientId, callItemMethod(item, "getCountOrSubType") or 1)
			end)
			if ok and created and created.getMarketData then
				local marketOk, marketData = pcall(function()
					return created:getMarketData()
				end)
				if marketOk and marketData then
					addUniqueItemId(ids, marketData.tradeAs)
					addUniqueItemId(ids, marketData.showAs)
				end
			end
		end
	end

	return ids
end

local function getCachedCharacterItemInfo(itemId)
	itemId = tonumber(itemId)
	if not itemId or itemId <= 0 then
		return nil
	end

	return characterItemInfoCache[itemId] or characterItemInfoCache[tostring(itemId)]
end

local function cacheCharacterItemInfo(itemId, name, description)
	itemId = tonumber(itemId)
	if not itemId or itemId <= 0 then
		return
	end

	local entry = characterItemInfoCache[itemId] or {}
	if isValidItemName(name) then
		entry.name = name
	end
	if description and description ~= "" then
		entry.description = description
	end
	characterItemInfoCache[itemId] = entry
	characterItemInfoCache[tostring(itemId)] = entry
end

local function getNameFromThingType(itemId)
	if not itemId or itemId <= 0 or not g_things or not ThingCategoryItem then
		return nil
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType then
		if thingType.getMarketData then
			local ok, marketData = pcall(function()
				return thingType:getMarketData()
			end)
			if ok and marketData and isValidItemName(marketData.name) then
				return marketData.name
			end
		end

		if thingType.getName then
			local ok, name = pcall(function()
				return thingType:getName()
			end)
			if ok and isValidItemName(name) then
				return name
			end
		end
	end

	if Item and Item.create then
		local ok, created = pcall(function()
			return Item.create(itemId, 1)
		end)
		if ok and created and created.getMarketData then
			local marketOk, marketData = pcall(function()
				return created:getMarketData()
			end)
			if marketOk and marketData and isValidItemName(marketData.name) then
				return marketData.name
			end
		end
	end

	return nil
end

local function getNameFromServerDetails(itemId)
	local itemsData = modules.game_cyclopedia and modules.game_cyclopedia.itemsData
	local cached = itemsData and (itemsData.serverDetails[tostring(itemId)] or itemsData.serverDetails[itemId])
	if not cached then
		return nil
	end

	local descriptions = cached.descriptions or cached
	if type(descriptions) ~= "table" then
		return nil
	end

	for _, entry in ipairs(descriptions) do
		if type(entry) == "table" then
			local detail = entry.detail or entry[1] or ""
			local description = entry.description or entry[2] or ""
			if detail:lower() == "name" and isValidItemName(description) then
				return description
			end
		end
	end

	return nil
end

local function extractNameFromDescription(description)
	if not description or description == "" then
		return nil
	end

	local firstLine = description:match("^([^\r\n]+)")
	if isValidItemName(firstLine) then
		return firstLine
	end

	return nil
end

local function getCharacterItemName(item)
	if not item then
		return ""
	end

	for _, itemId in ipairs(collectCharacterItemIds(item)) do
		local cached = getCachedCharacterItemInfo(itemId)
		if cached and isValidItemName(cached.name) then
			return cached.name
		end

		local serverName = getNameFromServerDetails(itemId)
		if serverName then
			cacheCharacterItemInfo(itemId, serverName)
			return serverName
		end
	end

	if item.getMarketData then
		local ok, marketData = pcall(function()
			return item:getMarketData()
		end)
		if ok and marketData and isValidItemName(marketData.name) then
			return marketData.name
		end
	end

	for _, itemId in ipairs(collectCharacterItemIds(item)) do
		local name = getNameFromThingType(itemId)
		if name then
			cacheCharacterItemInfo(itemId, name)
			return name
		end
	end

	local tooltip = callItemMethod(item, "getTooltip")
	if tooltip and tooltip ~= "" then
		local name = extractNameFromDescription(tooltip)
		if name then
			return name
		end
	end

	for _, itemId in ipairs(collectCharacterItemIds(item)) do
		local cached = getCachedCharacterItemInfo(itemId)
		if cached and cached.description then
			local name = extractNameFromDescription(cached.description)
			if name then
				return name
			end
		end
	end

	local fallbackId = collectCharacterItemIds(item)[1] or 0
	if fallbackId > 0 then
		return tr("Item") .. " " .. fallbackId
	end

	return tr("Unknown Item")
end

local function appendCharacterDetailTextLine(text)
	if not text or text == "" or not UI or not UI.InfoBase or not UI.InfoBase.DetailsBase or not UI.InfoBase.DetailsBase.List then
		return
	end

	local label = g_ui.createWidget("Label", UI.InfoBase.DetailsBase.List)
	label:setText(text)
	label:setColor("#BEBEBE")
	label:setTextWrap(true)
	label:setTextAutoResize(true)
end

local function appendCharacterDetailRows(descriptions)
	if not descriptions or not UI or not UI.InfoBase or not UI.InfoBase.DetailsBase or not UI.InfoBase.DetailsBase.List then
		return
	end

	for _, entry in ipairs(descriptions) do
		if type(entry) == "table" then
			local detail = entry.detail or entry[1] or ""
			local description = entry.description or entry[2] or ""
			if detail ~= "" and description ~= "" then
				appendDetailKeyValueRow(UI.InfoBase.DetailsBase.List, detail, description)
			elseif description ~= "" then
				appendCharacterDetailTextLine(description)
			end
		elseif type(entry) == "string" and entry ~= "" then
			appendCharacterDetailTextLine(entry)
		end
	end
end

local function requestCharacterItemInfo(item)
	if not item or not g_game then
		return
	end

	local itemId = callItemMethod(item, "getId") or 0
	if itemId <= 0 then
		return
	end

	local now = g_clock and g_clock.millis() or 0
	if pendingCharacterItemInfo[itemId] and now - pendingCharacterItemInfo[itemId] < 1500 then
		return
	end
	pendingCharacterItemInfo[itemId] = now

	if g_game.requestItemInfo then
		pcall(function()
			g_game.requestItemInfo(item, 0)
		end)
	end

	if OutputMessage and OutputMessage.create and g_game.getProtocolGame then
		local protocol = g_game.getProtocolGame()
		if protocol and protocol.send then
			pcall(function()
				local msg = OutputMessage.create()
				msg:addU8(OPCODE_ITEM_DETAILS)
				msg:addU16(itemId)
				protocol:send(msg)
			end)
		end
	end
end

local function refreshSelectedCharacterItemView()
	if not selectedCharacterItem or not infoItemSelected then
		return
	end

	if UI.InfoBase.InspectLabel then
		UI.InfoBase.InspectLabel:setText(tr("You are inspecting") .. ": " .. getCharacterItemName(selectedCharacterItem))
	end

	renderItemDetails(selectedCharacterItem)
end

local function onCharacterItemInfo(itemList)
	if not itemList then
		return
	end

	for _, data in pairs(itemList) do
		local item = data and data[1]
		local description = data and data[2]
		if item and item.getId then
			local itemId = item:getId()
			local name = extractNameFromDescription(description) or getNameFromThingType(itemId)
			cacheCharacterItemInfo(itemId, name, description)
			pendingCharacterItemInfo[itemId] = nil
		end
	end

	if selectedCharacterItem then
		local selectedId = callItemMethod(selectedCharacterItem, "getId")
		for _, data in pairs(itemList) do
			local item = data and data[1]
			if item and item.getId and item:getId() == selectedId then
				refreshSelectedCharacterItemView()
				break
			end
		end
	end
end

local function renderItemDetails(item)
	if not item or not UI or not UI.InfoBase or not UI.InfoBase.DetailsBase or not UI.InfoBase.DetailsBase.List then
		return
	end

	UI.InfoBase.DetailsBase.List:destroyChildren()

	for _, itemId in ipairs(collectCharacterItemIds(item)) do
		local itemsData = modules.game_cyclopedia and modules.game_cyclopedia.itemsData
		local cached = itemsData and (itemsData.serverDetails[tostring(itemId)] or itemsData.serverDetails[itemId])
		if cached then
			local descriptions = cached.descriptions or cached
			if type(descriptions) == "table" and #descriptions > 0 then
				appendCharacterDetailRows(descriptions)
				return
			end
		end
	end

	local tooltip = callItemMethod(item, "getTooltip")
	if tooltip and tooltip ~= "" then
		for line in tooltip:gmatch("[^\r\n]+") do
			if isValidItemName(line) or not line:lower():find("unknown item", 1, true) then
				appendCharacterDetailTextLine(line)
			end
		end
		if UI.InfoBase.DetailsBase.List:getChildCount() > 0 then
			return
		end
	end

	for _, itemId in ipairs(collectCharacterItemIds(item)) do
		local cached = getCachedCharacterItemInfo(itemId)
		if cached and cached.description and cached.description ~= "" then
			for line in cached.description:gmatch("[^\r\n]+") do
				appendCharacterDetailTextLine(line)
			end
			if UI.InfoBase.DetailsBase.List:getChildCount() > 0 then
				return
			end
		end
	end

	appendCharacterDetailTextLine(getCharacterItemName(item))
end

local function refreshCharacterInventory()
	local player = g_game.getLocalPlayer()
	local panel = getCharacterInventoryPanel()
	if not player or not panel then
		return
	end

	if UI.InfoBase.InspectLabel and not selectedInventorySlot then
		UI.InfoBase.InspectLabel:setText(tr("You are inspecting") .. ": " .. player:getName())
	end

	for slot = InventorySlotFirst, InventorySlotLast do
		local item = player:getInventoryItem(slot)
		local itemWidget = panel:getChildById("slot" .. slot)
		local style = INVENTORY_SLOT_STYLES[slot]

		if itemWidget and style then
			if item then
				itemWidget:setStyle("InventoryItemCyclopedia")
				itemWidget:setItem(item)
				itemWidget:setIcon("")
			else
				itemWidget:setStyle(style.name)
				itemWidget:setIcon(style.icon)
				itemWidget:setItem(nil)
			end
		end
	end
end

local function onCharacterInventorySlotClick(slot, widget)
	local player = g_game.getLocalPlayer()
	if not player or not widget then
		return
	end

	local item = player:getInventoryItem(slot) or widget:getItem()
	if not item then
		clearInventorySlotSelection()
		showCharacterPlayerDetails()
		return
	end

	if selectedInventorySlot == slot then
		clearInventorySlotSelection()
		showCharacterPlayerDetails()
		return
	end

	clearInventorySlotSelection()
	selectedInventorySlot = slot
	selectedCharacterItem = item
	infoItemSelected = true
	setInventorySlotSelected(widget, true)

	if UI.InfoBase.InspectLabel then
		UI.InfoBase.InspectLabel:setText(tr("You are inspecting") .. ": " .. getCharacterItemName(item))
	end

	renderItemDetails(item)
	requestCharacterItemInfo(item)
end

local function bindCharacterInventorySlots()
	local panel = getCharacterInventoryPanel()
	if not panel then
		return
	end

	for slot = InventorySlotFirst, InventorySlotLast do
		local itemWidget = panel:getChildById("slot" .. slot)
		if itemWidget then
			function itemWidget.onMouseRelease(widget, mousePos, mouseButton)
				if mouseButton == MouseLeftButton then
					onCharacterInventorySlotClick(slot, widget)
				end

				return false
			end
		end
	end
end

local function updateCharacterHeader()
	local player = g_game.getLocalPlayer()
	if not player or not UI then
		return
	end

	if UI.CharacterBase then
		UI.CharacterBase:setText(player:getName())
		if UI.CharacterBase.InfoLabel then
			UI.CharacterBase.InfoLabel:setText(string.format("Level %d\n%s", player:getLevel(), player:getVocationNameByClientId()))
		end

		local worldInfoLabel = UI.CharacterBase:recursiveGetChildById("worldInfoLabel")
		if worldInfoLabel then
			worldInfoLabel:setText(g_game.getWorldName() or "")
		end

		local outfitWidget = UI.CharacterBase:recursiveGetChildById("Outfit")
		if outfitWidget then
			outfitWidget:setOutfit(player:getOutfit())
		end
	end
end

local function setCharacterCategoryButtonChecked(button, checked)
	if not button or button:isDestroyed() then
		return
	end

	button:setChecked(checked)
	if button.Icon then
		button.Icon:setChecked(checked)
	end
	if button.Title then
		button.Title:setChecked(checked)
	end

	if not checked then
		if button.Icon then
			button.Icon:setMarginLeft(6)
			button.Icon:setMarginTop(0)
		end
		if button.Title then
			button.Title:setTextOffset("0 0")
		end
	end
end

local function bindSubcategoryButtonHandlers(button)
	if not button or button:isDestroyed() then
		return
	end

	button.Arrow:setMarginRight(SUBCATEGORY_ARROW_MARGIN_RIGHT)

	function button:onMousePress()
		self.Icon:setMarginLeft(7)
		self.Icon:setMarginTop(1)
		self.Title:setTextOffset("1 1")

		if self.Arrow:isVisible() then
			self.Arrow:setMarginRight(SUBCATEGORY_ARROW_MARGIN_RIGHT_PRESSED)
		end
	end

	function button:onMouseRelease()
		if not self:isChecked() then
			self.Icon:setMarginLeft(6)
			self.Icon:setMarginTop(0)
			self.Title:setTextOffset("0 0")

			if self.Arrow:isVisible() then
				self.Arrow:setMarginRight(SUBCATEGORY_ARROW_MARGIN_RIGHT)
			end
		end
	end
end

local function closeAllSidebarButtons()
	if not UI or not UI.OptionsBase then
		return
	end

	for i = 1, UI.OptionsBase:getChildCount() do
		local widget = UI.OptionsBase:getChildByIndex(i)
		if widget then
			if widget.subCategories then
				for subId in ipairs(widget.subCategories) do
					local subWidget = widget:getChildById(subId)
					if subWidget and subWidget.Button then
						setCharacterCategoryButtonChecked(subWidget.Button, false)
						subWidget.Button.Arrow:setVisible(false)
					end
				end
			elseif widget.Button then
				setCharacterCategoryButtonChecked(widget.Button, false)
				widget.Button.Arrow:setVisible(false)
			end
		end
	end
end

local function closeCategory(parent)
	if not parent or not parent.subCategories then
		return
	end

	for subId in ipairs(parent.subCategories) do
		local subWidget = parent:getChildById(subId)
		if subWidget then
			subWidget:setVisible(false)
		end
	end

	parent:setHeight(parent.closedSize)
	parent.opened = false
	parent.Button.Arrow:setVisible(true)
	parent.Button.Arrow:setImageSource(ARROW_DOWN)

	if openedCategory == parent then
		openedCategory = nil
	end
end

local function openCategory(parent)
	if not parent or not parent.subCategories then
		return
	end

	if openedCategory and openedCategory ~= parent then
		closeCategory(openedCategory)
	end

	for subId in ipairs(parent.subCategories) do
		local subWidget = parent:getChildById(subId)
		if subWidget then
			subWidget:setVisible(true)
		end
	end

	parent:setHeight(parent.openedSize)
	parent.opened = true
	parent.Button.Arrow:setVisible(false)
	openedCategory = parent
end

local function disconnectCharacterGameEvents()
	if characterGameConnection then
		disconnect(characterGameConnection)
		characterGameConnection = nil
	end
end

local function connectCharacterGameEvents()
	disconnectCharacterGameEvents()

	if not g_game.isOnline() then
		return
	end

	characterGameConnection = connect(g_game, {
		onItemInfo = onCharacterItemInfo
	})
end

local function disconnectPlayerEvents()
	if not playerConnections then
		return
	end

	for _, connection in ipairs(playerConnections) do
		disconnect(connection)
	end

	playerConnections = nil
end

local function connectPlayerEvents()
	disconnectPlayerEvents()

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local handlers = {
		onOutfitChange = function()
			updateCharacterHeader()
			applyCharacterOutfitWidgets()
			if selectedPanel == "InfoBase" and not infoItemSelected then
				renderCharacterOverviewDetails()
			end
		end,
		onInventoryChange = function()
			if selectedPanel == "InfoBase" then
				refreshCharacterInventory()
			end
		end
	}

	if selectedPanel == "CharacterStats" then
		handlers.onLevelChange = refreshGeneralStatsFromPlayer
		handlers.onExperienceChange = refreshGeneralStatsFromPlayer
		handlers.onHealthChange = refreshGeneralStatsFromPlayer
		handlers.onManaChange = refreshGeneralStatsFromPlayer
		handlers.onSoulChange = refreshGeneralStatsFromPlayer
		handlers.onFreeCapacityChange = refreshGeneralStatsFromPlayer
		handlers.onSpeedChange = refreshGeneralStatsFromPlayer
		handlers.onStaminaChange = refreshGeneralStatsFromPlayer
		handlers.onOfflineTrainingChange = refreshGeneralStatsFromPlayer
		handlers.onRegenerationChange = refreshGeneralStatsFromPlayer
		handlers.onMagicLevelChange = refreshGeneralStatsFromPlayer
		handlers.onBaseMagicLevelChange = refreshGeneralStatsFromPlayer
		handlers.onSkillChange = refreshGeneralStatsFromPlayer
		handlers.onBaseSkillChange = refreshGeneralStatsFromPlayer
	end

	playerConnections = {
		connect(player, handlers)
	}
end

local function switchPanel(panelId)
	if not UI then
		return
	end

	selectedPanel = panelId

	if UI.InfoBase then
		UI.InfoBase:setVisible(panelId == "InfoBase")
	end

	if UI.CharacterStats then
		UI.CharacterStats:setVisible(panelId == "CharacterStats")
	end

	if UI.offencePanel then
		UI.offencePanel:setVisible(panelId == "offencePanel")
	end

	closeAllSidebarButtons()

	local activeButton = sidebarButtons[panelId]
	if activeButton then
		setCharacterCategoryButtonChecked(activeButton, true)
		activeButton.Arrow:setVisible(true)
		activeButton.Arrow:setImageSource(ARROW_RIGHT)
		activeButton.Arrow:setMarginRight(SUBCATEGORY_ARROW_MARGIN_RIGHT)
	end

	if panelId == "InfoBase" then
		resetCharacterInspectView()
		clearInventorySlotSelection()
		updateCharacterHeader()
		applyCharacterOutfitWidgets()
		refreshCharacterInventory()
		showCharacterPlayerDetails()
	elseif panelId == "CharacterStats" then
		refreshGeneralStatsFromPlayer()
	elseif panelId == "offencePanel" then
		if lastOffenceData then
			renderOffenceStats(lastOffenceData)
		end
		local protocol = g_game.getProtocolGame()
		if protocol and protocol.sendExtendedJSONOpcode then
			protocol:sendExtendedJSONOpcode(ExtendedIds.CyclopediaCharacterOffence, { action = "request" })
		end
	end

	connectPlayerEvents()
end

function selectCharacterOverview()
	if openedCategory then
		closeCategory(openedCategory)
	end

	closeAllSidebarButtons()
	switchPanel("InfoBase")
end

function onCharacterInspectButton(button)
	if not UI or not UI.InfoBase then
		return
	end

	if button.state == 1 then
		button.state = 2
		setCharacterButtonIcon(button, "outfit")
		UI.InfoBase.inventoryPanel:setVisible(false)
		UI.InfoBase.outfitPanel:setVisible(true)
		applyCharacterOutfitWidgets()
		showCharacterPlayerDetails()
	else
		button.state = 1
		setCharacterButtonIcon(button, "player")
		UI.InfoBase.inventoryPanel:setVisible(true)
		UI.InfoBase.outfitPanel:setVisible(false)
		bindCharacterInventorySlots()
		showCharacterPlayerDetails()
	end
end

function onCharacterWheelButton()
	if modules.game_wheel and modules.game_wheel.toggle then
		modules.game_wheel.toggle()
	end
end

local function configureSidebar()
	if not UI or not UI.OptionsBase then
		return
	end

	UI.OptionsBase:destroyChildren()
	sidebarButtons = {}
	openedCategory = nil

	local buttons = {
		{
			icon = 1,
			text = tr("General Stats"),
			subCategories = {
				{ icon = 11, text = tr("Character Stats"), panelId = "CharacterStats" },
				{ icon = 12, text = tr("Offence Stats"), panelId = "offencePanel" }
			}
		},
		{
			icon = 2,
			text = tr("Battle Results"),
			subCategories = {
				{ icon = 21, text = tr("Recent Deaths") },
				{ icon = 22, text = tr("Recent PvP Kills") }
			}
		},
		{ icon = 3, text = tr("Achievements") },
		{ icon = 4, text = tr("Item Summary") },
		{ icon = 5, text = tr("Appearances") },
		{ icon = 6, text = tr("Character Titles") }
	}

	for id, buttonData in ipairs(buttons) do
		local widgetStyle = buttonData.subCategories and "CharacterCategoryGroup" or "CharacterCategoryItem"
		local widget = g_ui.createWidget(widgetStyle, UI.OptionsBase)

		widget:setId(id)
		widget.Button.Icon:setIcon(ICON_BASE .. buttonData.icon)
		widget.Button.Title:setText(buttonData.text)

		if buttonData.subCategories then
			widget.subCategories = buttonData.subCategories
			widget.subCategoriesSize = #buttonData.subCategories
			widget.Button.Arrow:setVisible(true)
			widget.Button.Arrow:setImageSource(ARROW_DOWN)
			widget.closedSize = CATEGORY_BASE_HEIGHT
			widget.openedSize = CATEGORY_BASE_HEIGHT + widget.subCategoriesSize * SUBCATEGORY_HEIGHT
			widget:setHeight(widget.closedSize)

			for subId, subButton in ipairs(buttonData.subCategories) do
				local subWidget = g_ui.createWidget("CharacterCategoryItem", widget)
				subWidget:setId(subId)
				subWidget.Button.Icon:setIcon(ICON_BASE .. subButton.icon)
				subWidget.Button.Title:setText(subButton.text)
				subWidget:setVisible(false)
				subWidget:setImageSource("")
				subWidget:setImageBorder(0)
				subWidget:setHeight(SUBCATEGORY_HEIGHT)
				bindSubcategoryButtonHandlers(subWidget.Button)

				if subButton.panelId then
					subWidget.panelId = subButton.panelId
					sidebarButtons[subButton.panelId] = subWidget.Button

					subWidget.Button.onClick = function()
						switchPanel(subButton.panelId)
					end
				end

				subWidget:setMarginLeft(0)

				if subId == 1 then
					subWidget:addAnchor(AnchorTop, "parent", AnchorTop)
					subWidget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
					subWidget:setMarginTop(20)
				else
					subWidget:addAnchor(AnchorTop, "prev", AnchorBottom)
					subWidget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
					subWidget:setMarginTop(1)
				end
			end
		else
			bindSubcategoryButtonHandlers(widget.Button)
		end

		widget:setMarginLeft(-3)

		if id == 1 then
			widget:addAnchor(AnchorTop, "parent", AnchorTop)
			widget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
			widget:setMarginTop(7)
		else
			widget:addAnchor(AnchorTop, "prev", AnchorBottom)
			widget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
			widget:setMarginTop(4)
		end

		widget.Button.onClick = function()
			if widget.subCategories then
				if widget.opened then
					closeCategory(widget)
				else
					openCategory(widget)
					local firstSub = widget:getChildById(1)
					if firstSub and firstSub.panelId then
						switchPanel(firstSub.panelId)
					end
				end
			end
		end
	end
end

local function refreshCharacterPanel()
	if not characterPanel or characterPanel:isDestroyed() then
		return
	end

	updateCharacterHeader()
	switchPanel(selectedPanel)
end

local function onCyclopediaCharacterOffence(protocol, opcode, data)
	renderOffenceStats(data)
end

function initCharacter(contentContainer)
	if not contentContainer then
		return
	end

	if characterPanel and not characterPanel:isDestroyed() then
		characterPanel:show()
		connectCharacterGameEvents()
		scheduleEvent(refreshCharacterPanel, 50)
		return
	end

	g_ui.importStyle("styles/character")
	characterPanel = g_ui.loadUI("styles/character", contentContainer)
	if not characterPanel then
		return
	end

	UI = {
		CharacterBase = characterPanel:recursiveGetChildById("CharacterBase"),
		OptionsBase = characterPanel:recursiveGetChildById("OptionsBase"),
		InfoBase = characterPanel:recursiveGetChildById("InfoBase"),
		CharacterStats = characterPanel:recursiveGetChildById("CharacterStats"),
		offencePanel = characterPanel:recursiveGetChildById("offencePanel")
	}
	selectedPanel = "InfoBase"
	characterPanel:show()

	configureSidebar()
	bindCharacterInventorySlots()
	connectCharacterGameEvents()
	if UI.InfoBase and UI.InfoBase.CharacterButton then
		bindCharacterButtonIcon(UI.InfoBase.CharacterButton)
	end
	scheduleEvent(refreshCharacterPanel, 50)
end

function terminateCharacter()
	disconnectPlayerEvents()
	disconnectCharacterGameEvents()

	if characterPanel and not characterPanel:isDestroyed() then
		characterPanel:destroy()
	end

	characterPanel = nil
	UI = nil
	lastOffenceData = nil
	sidebarButtons = {}
	openedCategory = nil
	selectedInventorySlot = nil
	selectedCharacterItem = nil
	infoItemSelected = false
	characterItemInfoCache = {}
	pendingCharacterItemInfo = {}
end

local function onCharacterItemDetails(protocol, msg)
	local ok, itemId = pcall(function()
		return msg:getU16()
	end)
	if not ok or not itemId or itemId <= 0 then
		return
	end

	pendingCharacterItemInfo[itemId] = nil

	local descriptions = {}
	local okHeader, descriptionsSize = pcall(function()
		msg:getU32()
		msg:getU32()
		msg:getU32()
		return msg:getU8()
	end)
	if not okHeader then
		return
	end

	for i = 1, descriptionsSize do
		local detailOk, detail = pcall(function()
			return msg:getString()
		end)
		local descriptionOk, description = pcall(function()
			return msg:getString()
		end)
		if detailOk and descriptionOk then
			descriptions[#descriptions + 1] = {
				detail = detail,
				description = description
			}
		end
	end

	pcall(function()
		local npcSaleDataSize = msg:getU16()
		for i = 1, npcSaleDataSize do
			msg:getString()
			msg:getString()
			msg:getU32()
			msg:getU32()
			msg:getString()
		end
	end)

	local name = nil
	for _, entry in ipairs(descriptions) do
		if entry.detail and entry.detail:lower() == "name" and isValidItemName(entry.description) then
			name = entry.description
			break
		end
	end

	if isValidItemName(name) then
		cacheCharacterItemInfo(itemId, name)
	end

	local itemsData = modules.game_cyclopedia.itemsData or {}
	itemsData.serverDetails = itemsData.serverDetails or {}
	itemsData.serverDetails[tostring(itemId)] = { descriptions = descriptions }
	modules.game_cyclopedia.itemsData = itemsData

	if selectedCharacterItem and callItemMethod(selectedCharacterItem, "getId") == itemId then
		refreshSelectedCharacterItemView()
	end
end

function terminateCharacterModule()
	if ProtocolGame.unregisterExtendedJSONOpcode then
		ProtocolGame.unregisterExtendedJSONOpcode(ExtendedIds.CyclopediaCharacterOffence)
	end
	if ProtocolGame and ProtocolGame.unregisterOpcode then
		ProtocolGame.unregisterOpcode(OPCODE_ITEM_DETAILS)
	end

	terminateCharacter()
end

ProtocolGame.registerExtendedJSONOpcode(ExtendedIds.CyclopediaCharacterOffence, onCyclopediaCharacterOffence)
if ProtocolGame and ProtocolGame.registerOpcode then
	ProtocolGame.registerOpcode(OPCODE_ITEM_DETAILS, onCharacterItemDetails)
end

modules.game_cyclopedia.selectCharacterOverview = selectCharacterOverview
modules.game_cyclopedia.onCharacterInspectButton = onCharacterInspectButton
modules.game_cyclopedia.onCharacterWheelButton = onCharacterWheelButton
