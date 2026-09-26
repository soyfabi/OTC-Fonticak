-- chunkname: @/game_cyclopedia/tab/magicalArchives/magicalArchives.lua

local UI, currentSpell
local allSpells = {}
local filteredSpells = {}
local activeSearchText = ""
local filterPopup
local filterPopupVisible = false
local isInitializingPopup = false
local aimAtTargetBySpellId = {}
local firstOpen = true
local activeDetailsTab = "combat"
local lastSelectedSpellId
local selectedSpellListWidget
local selectSpellDetails
local preserveSelectionOnNextOpen = false
local FILTER_COLLAPSED_SIZE = {
	height = 19,
	width = 160
}
local FILTER_EXPANDED_SIZE = {
	height = 358,
	width = 160
}
local FILTER_TITLE_HEIGHT = 17
local FILTER_POPUP_OFFSET_X = 7
local FILTER_POPUP_OFFSET_Y = 5
local FILTER_ICON_CLIP_COLLAPSED = "0 0 12 12"
local FILTER_ICON_CLIP_EXPANDED = "0 12 12 12"

local function setFilterButtonIconClip(filterBtn, iconClip)
	filterBtn:setIconClip(torect(iconClip))
end

local function setFilterButtonOn(filterBtn, isOn)
	filterBtn:setOn(isOn)
end

local function setFilterButtonCollapsedStyle(filterBtn)
	filterBtn:setSize(FILTER_COLLAPSED_SIZE)
	filterBtn:setImageBorder(2)
	filterBtn:setImageBorderTop(17)
	filterBtn:setImageBorderBottom(2)
	setFilterButtonOn(filterBtn, false)
	setFilterButtonIconClip(filterBtn, FILTER_ICON_CLIP_COLLAPSED)
end

local function setFilterButtonExpandedStyle(filterBtn)
	filterBtn:setSize(FILTER_EXPANDED_SIZE)
	filterBtn:setImageBorder(20)
	setFilterButtonOn(filterBtn, true)
	setFilterButtonIconClip(filterBtn, FILTER_ICON_CLIP_EXPANDED)
end

local SPELLS_FILE = "/modules/game_cyclopedia/tab/magicalArchives/spells.json"
local SPELLS_PREVIEW_FILE = "/modules/game_cyclopedia/tab/magicalArchives/spells-preview.json"
local SPELL_ICON_FILE = "/images/game/spells/spell-icons-32x32"
local SPELL_ICON_SMALL_FILE = "/images/game/spells/spell-icons-20x20"
local SPELL_ICON_PROFILE = "Default"
local filters = {
	instantSpellsFilter = true,
	runeSpellsFilter = true,
	freeFilter = true,
	premiumFilter = true,
	allSpellGroupsFilter = true,
	supportFilter = true,
	healingFilter = true,
	attackFilter = true,
	allVocationsFilter = true,
	monkFilter = true,
	sorcererFilter = true,
	paladinFilter = true,
	knightFilter = true,
	druidFilter = true,
	learntSpellsFilter = false,
	charLevelFilter = false,
	charVocationFilter = true
}
local vocationIds = {
	["Royal Paladin"] = 7,
	["Elder Druid"] = 6,
	["Master Sorcerer"] = 5,
	Knight = 4,
	Paladin = 3,
	Druid = 2,
	Sorcerer = 1,
	["Exalted Monk"] = 10,
	Monk = 9,
	["Elite Knight"] = 8
}
local promotedToBase = {
	nil,
	nil,
	nil,
	nil,
	1,
	2,
	3,
	4,
	nil,
	9
}
local filterToBaseVoc = {
	monkFilter = 9,
	sorcererFilter = 1,
	paladinFilter = 3,
	knightFilter = 4,
	druidFilter = 2
}
local baseVocToFilter = {
	"sorcererFilter",
	"druidFilter",
	"paladinFilter",
	"knightFilter",
	nil,
	nil,
	nil,
	nil,
	"monkFilter"
}
local baseVocNames = {
	"Sorcerer",
	"Druid",
	"Paladin",
	"Knight",
	nil,
	nil,
	nil,
	nil,
	"Monk"
}
local groupNames = {
	SPELLGROUP_CONJURE = "Support",
	SPELLGROUP_SPECIAL = "Support",
	SPELLGROUP_CRIPPLING = "Support",
	SPELLGROUP_SUPPORT = "Support",
	SPELLGROUP_NONE = "Support",
	SPELLGROUP_HEALING = "Healing",
	SPELLGROUP_FOCUS = "Support",
	SPELLGROUP_ATTACK = "Attack"
}
local damageTypeNames = {
	DAMAGE_HEALING = "Healing",
	DAMAGE_ICE = "Ice",
	DAMAGE_FIRE = "Fire",
	DAMAGE_EARTH = "Earth",
	DAMAGE_ENERGY = "Energy",
	DAMAGE_MANADRAIN = "Mana Drain",
	DAMAGE_PHYSICAL = "Physical",
	DAMAGE_LIFEDRAIN = "Life Drain",
	DAMAGE_NONE = "-",
	DAMAGE_DEATH = "Death",
	DAMAGE_HOLY = "Holy"
}

local function resetFiltersToDefault()
	filters.charVocationFilter = true
	filters.charLevelFilter = false
	filters.learntSpellsFilter = false
	filters.druidFilter = true
	filters.knightFilter = true
	filters.paladinFilter = true
	filters.sorcererFilter = true
	filters.monkFilter = true
	filters.allVocationsFilter = true
	filters.attackFilter = true
	filters.healingFilter = true
	filters.supportFilter = true
	filters.allSpellGroupsFilter = true
	filters.premiumFilter = true
	filters.freeFilter = true
	filters.runeSpellsFilter = true
	filters.instantSpellsFilter = true
end

local function readJsonFile(file)
	if not g_resources.fileExists(file) then
		return nil
	end

	local ok, result = pcall(function()
		return json.decode(g_resources.readFileContents(file))
	end)

	if not ok then
		g_logger.error("Error while reading " .. file .. ". Details: " .. tostring(result))

		return nil
	end

	return result
end

local function normalizeBaseVocation(vocationId)
	local id = tonumber(vocationId) or 0

	return promotedToBase[id] or id
end

local function normalizeVocations(allowedVocations)
	local vocations = {}
	local seen = {}

	if type(allowedVocations) ~= "table" or #allowedVocations == 0 then
		return {
			0
		}
	end

	for _, vocationName in ipairs(allowedVocations) do
		local vocationId = vocationIds[vocationName]

		if vocationId and not seen[vocationId] then
			vocations[#vocations + 1] = vocationId
			seen[vocationId] = true
		end
	end

	if #vocations == 0 then
		return {
			0
		}
	end

	table.sort(vocations)

	return vocations
end

local function getSpellGroup(entry)
	return groupNames[entry.spellGroupPrimary] or groupNames[entry.spellGroupSecondary] or "Support"
end

local function getDamageType(entry)
	return damageTypeNames[entry.damagetype] or tostring(entry.damagetype or "-")
end

local function getScaling(entry)
	if type(entry.scaling) ~= "table" or #entry.scaling == 0 then
		return entry.aggressive and "Magic Level" or "-"
	end

	local labels = {}

	for _, value in ipairs(entry.scaling) do
		local text = tostring(value or "")

		if text == "magiclevel" then
			text = "Magic Level"
		elseif text == "level" then
			text = "Level"
		elseif text ~= "" then
			text = text:gsub("^%l", string.upper)
		end

		if text ~= "" then
			labels[#labels + 1] = text
		end
	end

	return #labels > 0 and table.concat(labels, ", ") or "-"
end

local function secondsToMilliseconds(value)
	local numberValue = tonumber(value) or 0

	if numberValue > 0 and numberValue < 100 then
		return numberValue * 1000
	end

	return numberValue
end

local function buildPreviewBySpellId()
	local previews = readJsonFile(SPELLS_PREVIEW_FILE)
	local byId = {}

	if type(previews) ~= "table" then
		return byId
	end

	for key, preview in pairs(previews) do
		if type(preview) == "table" then
			local id = tonumber(preview.spellid or key)

			if id then
				byId[id] = preview
			end
		end
	end

	return byId
end

local function getSpellIconLookup(entry)
	local spellId = tonumber(entry.spellid) or 0

	if Spells and Spells.getSpellDataById and spellId > 0 then
		local spellData = Spells.getSpellDataById(spellId)

		if spellData then
			return spellData
		end
	end

	if Spells and Spells.getSpellDataByWords and entry.formulaWithoutParams then
		local spellData = Spells.getSpellDataByWords(entry.formulaWithoutParams)

		if spellData then
			return spellData
		end
	end

	if Spells and Spells.getSpellByName and entry.name then
		local spellData = Spells.getSpellByName(entry.name)

		if spellData then
			return spellData
		end
	end

	return {
		id = spellId,
		clientId = tonumber(entry.iconIndex),
		name = entry.name or ""
	}
end

local function getMagicalArchivesIconSource(size)
	local settings = SpelllistSettings and SpelllistSettings[SPELL_ICON_PROFILE]

	if settings then
		if size == 32 and settings.iconFile then
			return settings.iconFile
		end

		if size == 20 and settings.iconsForGameCooldown then
			return settings.iconsForGameCooldown
		end
	end

	return size == 32 and SPELL_ICON_FILE or SPELL_ICON_SMALL_FILE
end

local function applyMagicalArchivesSpellIcon(widget, spellIconData, size)
	if not widget or widget:isDestroyed() or not spellIconData or not Spells then
		return
	end

	widget:setImageSource(getMagicalArchivesIconSource(size))

	if size == 32 and Spells.getSpellImageClip then
		widget:setImageClip(Spells.getSpellImageClip(spellIconData, SPELL_ICON_PROFILE))
	elseif size == 20 and Spells.getSpellCooldownImageClip then
		widget:setImageClip(Spells.getSpellCooldownImageClip(spellIconData, SPELL_ICON_PROFILE))
	end
end

local function normalizeSpell(entry, previewById)
	local id = tonumber(entry.spellid) or 0
	local preview = previewById[id]
	local hasPreview = Cyclopedia.MagicalArchivesPreview.hasActions(preview)

	preview = preview or {}

	local runeParams = type(entry.runeParams) == "table" and entry.runeParams or {}
	local group = getSpellGroup(entry)

	return {
		id = id,
		name = entry.name or "Unknown",
		words = entry.formulaWithoutParams or "",
		spellGroup = group,
		type = entry.isRune and "Conjure" or "Instant",
		isRune = entry.isRune == true,
		isRuneCreatable = entry.isRuneCreatable == true,
		level = tonumber(entry.minimumCasterLevel) or 0,
		maglevel = tonumber(runeParams.useMagicLevel) or 0,
		mana = tonumber(entry.castCostMana) or 0,
		useMana = tonumber(runeParams.useMana),
		soul = tonumber(entry.castCostSoulPoints) or 0,
		premium = entry.premium == true,
		aggressive = entry.aggressive == true,
		vocations = normalizeVocations(entry.allowedVocations),
		runeVocations = normalizeVocations(runeParams.allowedVocations),
		cooldown = secondsToMilliseconds(entry.cooldownSelf),
		exhaustion = secondsToMilliseconds(entry.cooldownSelf),
		groupCooldown = secondsToMilliseconds(entry.cooldownPrimaryGroup),
		secondaryGroupCooldown = secondsToMilliseconds(entry.cooldownSecondaryGroup),
		basePower = tonumber(entry.mean) or 0,
		scalesWith = getScaling(entry),
		damageType = getDamageType(entry),
		range = tonumber(entry.range or preview.range) or 0,
		source = entry.source and entry.source ~= "" and entry.source or "NPC",
		description = entry.description or "",
		amount = tonumber(runeParams.amount) or 1,
		runeType = tonumber(runeParams.runeType),
		spellIconData = getSpellIconLookup(entry),
		aimAtTarget = entry.aimattarget == true,
		hasPreview = hasPreview,
		preview = preview
	}
end

local function formatCooldown(milliseconds)
	local ms = tonumber(milliseconds) or 0

	if ms <= 0 then
		return "-"
	end

	local seconds = ms / 1000

	if seconds == math.floor(seconds) then
		return math.floor(seconds) .. "s"
	end

	return string.format("%.1fs", seconds)
end

local function getPlayerLevel()
	local player = g_game.getLocalPlayer()

	return player and player:getLevel() or 999
end

local function getPlayerVocation()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	local vocation = player:getVocation() or 0

	if translateVocation then
		return translateVocation(vocation)
	end

	return vocation
end

local function getPlayerPremium()
	local player = g_game.getLocalPlayer()

	return player and player:isPremium() or false
end

local function spellMatchesBaseVocation(spellVocations, baseVocation)
	if not spellVocations or #spellVocations == 0 then
		return true
	end

	for _, vocationId in ipairs(spellVocations) do
		if vocationId == 0 or normalizeBaseVocation(vocationId) == baseVocation then
			return true
		end
	end

	return false
end

local function passesVocationFilter(spellVocations, playerVocation)
	if not spellVocations or #spellVocations == 0 then
		return true
	end

	for _, vocationId in ipairs(spellVocations) do
		if vocationId == 0 then
			return true
		end
	end

	local playerBaseVocation = normalizeBaseVocation(playerVocation)

	if filters.charVocationFilter then
		local playerFilterKey = baseVocToFilter[playerBaseVocation]

		if playerFilterKey and not filters[playerFilterKey] then
			return false
		end

		return spellMatchesBaseVocation(spellVocations, playerBaseVocation)
	end

	if filters.allVocationsFilter then
		return true
	end

	for filterKey, baseVocation in pairs(filterToBaseVoc) do
		if filters[filterKey] and spellMatchesBaseVocation(spellVocations, baseVocation) then
			return true
		end
	end

	return false
end

local function passesLevelFilter(spellLevel, playerLevel)
	return not filters.charLevelFilter or not spellLevel or spellLevel <= playerLevel
end

local function passesSpellGroupFilter(spellGroup)
	if filters.allSpellGroupsFilter then
		return true
	end

	return filters.attackFilter and spellGroup == "Attack" or filters.healingFilter and spellGroup == "Healing" or filters.supportFilter and spellGroup == "Support"
end

local function passesLearntSpellsFilter(spell, playerLevel, playerVocation, isPremium)
	if not filters.learntSpellsFilter then
		return true
	end

	if spell.level and playerLevel < spell.level then
		return false
	end

	if not spellMatchesBaseVocation(spell.vocations, normalizeBaseVocation(playerVocation)) then
		return false
	end

	if spell.premium and not isPremium then
		return false
	end

	return true
end

local function isDirectionalSpell(spell)
	return spell and spell.aimAtTarget == true or false
end

local function isAimAtTargetEnabledForSpell(spell)
	if not spell or not spell.id or spell.id <= 0 then
		return false
	end

	return aimAtTargetBySpellId[spell.id] == true
end

local function sendSpellAimUpdate(spellId, enabled)
	if not spellId or spellId <= 0 or not g_game or not g_game.isOnline or not g_game.isOnline() then
		return
	end

	if not g_game.sendSelectSpellAim then
		return
	end

	local ok, err = pcall(function()
		g_game.sendSelectSpellAim({
			spellId
		}, enabled == true)
	end)

	if not ok then
		g_logger.error("[MagicalArchives] sendSelectSpellAim failed: " .. tostring(err))
	end
end

local function syncStoredSpellAimToServer()
	if not g_game or not g_game.sendSelectSpellAim or not g_game.isOnline or not g_game.isOnline() then
		return
	end

	for spellId, enabled in pairs(aimAtTargetBySpellId) do
		sendSpellAimUpdate(spellId, enabled)
	end
end

local function saveAimAtTargetData()
	local spells = {}

	for spellId, enabled in pairs(aimAtTargetBySpellId) do
		if enabled then
			spells[tostring(spellId)] = true
		end
	end

	g_settings.setNode("aimAtTargetPerSpell", {
		spells = spells
	})
end

local function loadAimAtTargetData()
	aimAtTargetBySpellId = {}

	local data = g_settings.getNode("aimAtTargetPerSpell")

	if data and data.spells and type(data.spells) == "table" then
		for spellIdKey, enabled in pairs(data.spells) do
			local spellId = tonumber(spellIdKey)

			if spellId and spellId > 0 and enabled == true then
				aimAtTargetBySpellId[spellId] = true
			end
		end

		return
	end

	local legacy = g_settings.getNode("aimAtTargetGlobal")

	if legacy and legacy.enabled == true then
		for _, spell in ipairs(allSpells) do
			if isDirectionalSpell(spell) and spell.id and spell.id > 0 then
				aimAtTargetBySpellId[spell.id] = true
			end
		end

		saveAimAtTargetData()
	end
end

local function selectTab(tabName)
	if not UI then
		return
	end

	local tabs = {
		combat = {
			tab = UI:recursiveGetChildById("combatStatsTab"),
			content = UI:recursiveGetChildById("combatStatsContent")
		},
		additional = {
			tab = UI:recursiveGetChildById("additionalTab"),
			content = UI:recursiveGetChildById("additionalContent")
		},
		rune = {
			tab = UI:recursiveGetChildById("runeSpellTab"),
			content = UI:recursiveGetChildById("runeSpellContent")
		}
	}

	for _, data in pairs(tabs) do
		if data.tab then
			data.tab:setOn(false)
		end

		if data.content then
			data.content:setVisible(false)
		end
	end

	local selected = tabs[tabName]

	if selected then
		activeDetailsTab = tabName

		if selected.tab then
			selected.tab:setOn(true)
		end

		if selected.content then
			selected.content:setVisible(true)
		end
	end
end

local function closeFilterPopup()
	filterPopupVisible = false

	if filterPopup then
		filterPopup:setVisible(false)
	end

	filterPopup = nil

	if UI and not UI:isDestroyed() then
		local filterBtn = UI:recursiveGetChildById("filterBtn")

		if filterBtn and not filterBtn:isDestroyed() then
			setFilterButtonCollapsedStyle(filterBtn)
		end

		local spellListContainer = UI:recursiveGetChildById("spellListContainer")

		if spellListContainer and not spellListContainer:isDestroyed() then
			spellListContainer:setVisible(true)
		end

		local searchPanel = UI:recursiveGetChildById("searchPanel")

		if searchPanel and not searchPanel:isDestroyed() then
			searchPanel:setVisible(true)
		end
	end

	if rootWidget then
		pcall(function()
			disconnect(rootWidget, {
				onMousePress = onMagicalArchivesRootMousePress
			})
		end)
	end
end

function onMagicalArchivesRootMousePress(widget, mousePos)
	if not filterPopup or not filterPopupVisible then
		return false
	end

	if UI and not UI:isDestroyed() then
		local filterBtn = UI:recursiveGetChildById("filterBtn")

		if filterBtn and not filterBtn:isDestroyed() then
			local pos = filterBtn:getPosition()
			local size = filterBtn:getSize()

			if mousePos.x >= pos.x and mousePos.x <= pos.x + size.width and mousePos.y >= pos.y and mousePos.y <= pos.y + size.height then
				return false
			end
		end
	end

	closeFilterPopup()

	return false
end

local function applyAllFilters()
	if not UI then
		return
	end

	local ok, err = pcall(function()
		filteredSpells = {}

		local playerLevel = getPlayerLevel()
		local playerVocation = getPlayerVocation()
		local isPremiumPlayer = getPlayerPremium()
		local search = (activeSearchText or ""):lower()

		for _, spell in ipairs(allSpells) do
			local passes = passesLearntSpellsFilter(spell, playerLevel, playerVocation, isPremiumPlayer) and passesVocationFilter(spell.vocations, playerVocation) and passesLevelFilter(spell.level, playerLevel) and passesSpellGroupFilter(spell.spellGroup)

			if passes then
				if spell.premium and not filters.premiumFilter then
					passes = false
				elseif not spell.premium and not filters.freeFilter then
					passes = false
				end
			end

			if passes then
				if spell.isRune and not filters.runeSpellsFilter then
					passes = false
				elseif not spell.isRune and not filters.instantSpellsFilter then
					passes = false
				end
			end

			if passes and search ~= "" then
				local name = (spell.name or ""):lower()
				local words = (spell.words or ""):lower()

				if not name:find(search, 1, true) and not words:find(search, 1, true) then
					passes = false
				end
			end

			if passes then
				filteredSpells[#filteredSpells + 1] = spell
			end
		end

		updateSpellListUI()
	end)

	if not ok then
		g_logger.error("[MagicalArchives] applyAllFilters failed: " .. tostring(err))
	end
end

local function getSearchEditWidget()
	if not UI then
		return nil
	end

	local panel = UI:recursiveGetChildById("searchEdit")

	if not panel or panel:isDestroyed() then
		return nil
	end

	local searchEdit = panel:getChildById("SearchEdit") or panel

	if searchEdit and not searchEdit:isDestroyed() then
		return searchEdit
	end

	return nil
end

local function focusMagicalArchivesSearchEdit()
	local searchEdit = getSearchEditWidget()

	if not searchEdit then
		return
	end

	searchEdit:setFocusable(true)
	searchEdit:focus()
	pcall(function()
		searchEdit:grabKeyboard()
	end)
	pcall(function()
		searchEdit:setEditable(true)
		searchEdit:setCursorVisible(true)
		searchEdit:setCursorPos(-1)
	end)
end

local function releaseMagicalArchivesSearchFocus()
	local searchEdit = getSearchEditWidget()

	if not searchEdit then
		return
	end

	pcall(function()
		searchEdit:ungrabKeyboard()
	end)
end

local function restoreGameKeyboardForWalking()
	releaseMagicalArchivesSearchFocus()

	local root = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()

	if root and not root:isDestroyed() and root.focus then
		root:focus()
	end
end

local function applySpellListItemSelectedStyle(widget, selected)
	if not widget or widget:isDestroyed() then
		return
	end

	widget:setBackgroundColor(selected and "#c0c0c033" or "alpha")

	local nameLabel = widget:getChildById("spellName")

	if nameLabel then
		nameLabel:setColor(selected and "#f4f4f4" or "#c0c0c0")
	end
end

local function selectSpellListWidget(widget, keepSearchFocus)
	if selectedSpellListWidget and not selectedSpellListWidget:isDestroyed() then
		applySpellListItemSelectedStyle(selectedSpellListWidget, false)
	end

	selectedSpellListWidget = widget

	if widget and not widget:isDestroyed() then
		applySpellListItemSelectedStyle(widget, true)
		selectSpellDetails(widget.spell)

		if not keepSearchFocus then
			restoreGameKeyboardForWalking()
		end
	end
end

local function setupFilterCheckboxesInPopup(popup)
	local filterIds = {
		"charVocationFilter",
		"charLevelFilter",
		"learntSpellsFilter",
		"druidFilter",
		"knightFilter",
		"paladinFilter",
		"sorcererFilter",
		"monkFilter",
		"allVocationsFilter",
		"attackFilter",
		"healingFilter",
		"supportFilter",
		"allSpellGroupsFilter",
		"premiumFilter",
		"freeFilter",
		"runeSpellsFilter",
		"instantSpellsFilter"
	}

	isInitializingPopup = true

	for _, filterId in ipairs(filterIds) do
		local checkbox = popup:recursiveGetChildById(filterId)

		if checkbox then
			function checkbox:onCheckChange()
				if not isInitializingPopup then
					onMagicalArchivesFilterChange(self, popup)
				end
			end

			checkbox:setChecked(filters[filterId] == true)
		end
	end

	isInitializingPopup = false
end

function onMagicalArchivesFilterChange(checkbox, popup)
	local id = checkbox:getId()
	local isChecked = checkbox:isChecked()

	filters[id] = isChecked

	local vocationFilters = {
		"druidFilter",
		"knightFilter",
		"paladinFilter",
		"sorcererFilter",
		"monkFilter"
	}

	if id == "allVocationsFilter" then
		for _, filterId in ipairs(vocationFilters) do
			filters[filterId] = isChecked

			local cb = popup:recursiveGetChildById(filterId)

			if cb then
				cb:setChecked(isChecked, true)
			end
		end
	elseif table.contains(vocationFilters, id) then
		local allChecked = true

		for _, filterId in ipairs(vocationFilters) do
			if not filters[filterId] then
				allChecked = false

				break
			end
		end

		filters.allVocationsFilter = allChecked

		local allVocCb = popup:recursiveGetChildById("allVocationsFilter")

		if allVocCb then
			allVocCb:setChecked(allChecked, true)
		end
	end

	local groupFilters = {
		"attackFilter",
		"healingFilter",
		"supportFilter"
	}

	if id == "allSpellGroupsFilter" then
		for _, filterId in ipairs(groupFilters) do
			filters[filterId] = isChecked

			local cb = popup:recursiveGetChildById(filterId)

			if cb then
				cb:setChecked(isChecked, true)
			end
		end
	elseif table.contains(groupFilters, id) then
		local allChecked = true

		for _, filterId in ipairs(groupFilters) do
			if not filters[filterId] then
				allChecked = false

				break
			end
		end

		filters.allSpellGroupsFilter = allChecked

		local allGroupCb = popup:recursiveGetChildById("allSpellGroupsFilter")

		if allGroupCb then
			allGroupCb:setChecked(allChecked, true)
		end
	end

	applyAllFilters()
end

local function showFilterPopup(button)
	closeFilterPopup()

	filterPopup = button:getChildById("filterPopup") or button:recursiveGetChildById("filterPopup")

	if not filterPopup then
		filterPopup = g_ui.createWidget("MagicalArchivesFilterPopup", button)

		if filterPopup then
			filterPopup:addAnchor(AnchorTop, "parent", AnchorTop)
			filterPopup:addAnchor(AnchorLeft, "parent", AnchorLeft)
		end
	end

	if not filterPopup then
		return
	end

	filterPopup:setMarginTop(FILTER_TITLE_HEIGHT + FILTER_POPUP_OFFSET_Y)
	filterPopup:setMarginLeft(FILTER_POPUP_OFFSET_X)
	setFilterButtonExpandedStyle(button)

	local spellListContainer = UI and UI:recursiveGetChildById("spellListContainer")

	if spellListContainer and not spellListContainer:isDestroyed() then
		spellListContainer:setVisible(false)
	end

	local searchPanel = UI and UI:recursiveGetChildById("searchPanel")

	if searchPanel and not searchPanel:isDestroyed() then
		searchPanel:setVisible(false)
	end

	setupFilterCheckboxesInPopup(filterPopup)
	filterPopup:setVisible(true)
	button:raise()
	filterPopup:raise()

	filterPopupVisible = true

	connect(rootWidget, {
		onMousePress = onMagicalArchivesRootMousePress
	})
end

local function toggleFilterPopup(button)
	if filterPopupVisible then
		closeFilterPopup()
	else
		showFilterPopup(button)
	end
end

local function setupFiltersUI()
	local filterBtn = UI:recursiveGetChildById("filterBtn")

	if filterBtn then
		setFilterButtonCollapsedStyle(filterBtn)

		function filterBtn:onClick()
			toggleFilterPopup(self)
		end
	end
end

local function setupSearchUI()
	local searchEdit = getSearchEditWidget()

	if not searchEdit then
		return
	end

	searchEdit:setFocusable(true)

	function searchEdit.onFocusChange(widget, focused)
		if focused and not widget:isDestroyed() then
			pcall(function()
				widget:grabKeyboard()
			end)
			pcall(function()
				widget:setEditable(true)
				widget:setCursorVisible(true)
			end)
		else
			releaseMagicalArchivesSearchFocus()
		end
	end

	function searchEdit.onKeyDown(widget, keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardNoModifier then
			return false
		end

		if keyCode == KeyEscape then
			releaseMagicalArchivesSearchFocus()

			if toggle then
				toggle()
			end

			return true
		end

		return false
	end

	function searchEdit:onTextChange()
		Cyclopedia.MagicalArchivesSearchText(self:getText() or "")
	end

	local clearButton = searchEdit:getParent() and searchEdit:getParent():getChildById("SearchClearButton")

	if clearButton then
		function clearButton.onClick()
			searchEdit:setText("")
			focusMagicalArchivesSearchEdit()
		end
	end
end

local vocationIconOrder = {
	{
		clip = "0 0 9 9",
		baseId = 4,
		name = "Knight"
	},
	{
		clip = "9 0 9 9",
		baseId = 3,
		name = "Paladin"
	},
	{
		clip = "18 0 9 9",
		baseId = 1,
		name = "Sorcerer"
	},
	{
		clip = "27 0 9 9",
		baseId = 2,
		name = "Druid"
	},
	{
		clip = "36 0 9 9",
		baseId = 9,
		name = "Monk"
	}
}
local VOCATION_ICON_WIDTH = 9
local VOCATION_ICON_SPACING = 5

local function createVocationIcons(panel, vocations, alignLeft)
	if not panel then
		return
	end

	panel:destroyChildren()

	local selected = {}
	local seen = {}

	for _, vocationId in ipairs(vocations or {}) do
		if vocationId == 0 then
			for _, vocationIcon in ipairs(vocationIconOrder) do
				selected[vocationIcon.baseId] = true
			end

			break
		end

		local baseVocation = normalizeBaseVocation(vocationId)

		selected[baseVocation] = true
	end

	local icons = {}

	for _, vocationIcon in ipairs(vocationIconOrder) do
		if selected[vocationIcon.baseId] and not seen[vocationIcon.baseId] then
			icons[#icons + 1] = vocationIcon
			seen[vocationIcon.baseId] = true
		end
	end

	for index, vocationIcon in ipairs(icons) do
		local icon = g_ui.createWidget("MagicalArchivesVocationIcon", panel)

		if icon then
			icon:addAnchor(AnchorTop, "parent", AnchorTop)

			if alignLeft then
				icon:addAnchor(AnchorLeft, "parent", AnchorLeft)
				icon:setMarginLeft((index - 1) * (VOCATION_ICON_WIDTH + VOCATION_ICON_SPACING))
			else
				icon:addAnchor(AnchorRight, "parent", AnchorRight)
				icon:setMarginRight((#icons - index) * (VOCATION_ICON_WIDTH + VOCATION_ICON_SPACING))
			end

			icon:setImageClip(vocationIcon.clip)
			icon:setTooltip(vocationIcon.name)
		end
	end
end

local function updateCombatStatsUI(spell)
	local manaValue = UI:recursiveGetChildById("manaValue")

	if manaValue then
		local mana = spell.isRune and spell.useMana or spell.mana

		mana = tonumber(mana) or 0

		manaValue:setText(mana > 0 and tostring(mana) or "-")
	end

	local groupValue = UI:recursiveGetChildById("groupValue")

	if groupValue then
		groupValue:setText(spell.spellGroup or "-")
	end

	local powerValue = UI:recursiveGetChildById("powerValue")

	if powerValue then
		powerValue:setText(spell.basePower and spell.basePower > 0 and tostring(spell.basePower) or "-")
	end

	local scalesValue = UI:recursiveGetChildById("scalesValue")

	if scalesValue then
		scalesValue:setText(spell.scalesWith or "-")
	end

	local cooldownValue = UI:recursiveGetChildById("cooldownValue")

	if cooldownValue then
		cooldownValue:setText(formatCooldown(spell.cooldown))
	end

	local groupCooldownValue = UI:recursiveGetChildById("groupCooldownValue")

	if groupCooldownValue then
		groupCooldownValue:setText(formatCooldown(spell.groupCooldown))
	end

	local typeValue = UI:recursiveGetChildById("typeValue")

	if typeValue then
		typeValue:setText(spell.damageType or "-")
	end

	local rangeValue = UI:recursiveGetChildById("rangeValue")

	if rangeValue then
		rangeValue:setText(spell.range and spell.range > 0 and tostring(spell.range) or "-")
	end

	local previewFrame = UI:recursiveGetChildById("spellPreviewFrame")

	if previewFrame then
		local ok, err = pcall(function()
			Cyclopedia.MagicalArchivesPreview.play(previewFrame, spell)
		end)

		if not ok then
			g_logger.error("[MagicalArchives] spell preview failed for \"" .. tostring(spell.name) .. "\": " .. tostring(err))
		end
	end
end

local function getAdditionalSourceText(spell)
	local source = tostring(spell.source or ""):lower()

	if source == "wheelofdestiny" then
		return "Wheel of Destiny"
	elseif source == "threefoldpath" then
		return "The Three-Fold Path"
	end

	local level = tonumber(spell.level) or 0

	if level <= 1 then
		return "Initial spell"
	end

	return "Spell learnt at level " .. level
end

local function formatSpellDescription(description)
	local text = tostring(description or "")

	text = text:gsub("<[Bb][Rr]%s*/?>", "\n")
	text = text:gsub("</?[Aa][^>]*>", "")
	text = text:gsub("<[^>]->", "")
	text = text:gsub("&nbsp;", " ")
	text = text:gsub("&amp;", "&")
	text = text:gsub("&quot;", "\"")
	text = text:gsub("&#39;", "'")

	return text ~= "" and text or "-"
end

local function updateAdditionalInfoUI(spell)
	local sourceValue = UI:recursiveGetChildById("sourceValue")

	if sourceValue then
		sourceValue:setText(getAdditionalSourceText(spell))
	end

	local descriptionValue = UI:recursiveGetChildById("descriptionValue")

	if descriptionValue then
		descriptionValue:setText(formatSpellDescription(spell.description))
	end
end

local function updateRuneSpellUI(spell)
	local runeManaValue = UI:recursiveGetChildById("runeManaValue")

	if runeManaValue then
		runeManaValue:setText((spell.mana or 0) .. " / " .. (spell.soul or 0))
	end

	local runeGroupValue = UI:recursiveGetChildById("runeGroupValue")

	if runeGroupValue then
		runeGroupValue:setText(spell.spellGroup or "-")
	end

	local runeRestrictionValue = UI:recursiveGetChildById("runeRestrictionValue")

	if runeRestrictionValue then
		runeRestrictionValue:setText(spell.level and spell.level > 0 and "Level " .. spell.level or "-")
	end

	local runeAmountValue = UI:recursiveGetChildById("runeAmountValue")

	if runeAmountValue then
		runeAmountValue:setText(tostring(spell.amount or 1))
	end

	local runeCooldownValue = UI:recursiveGetChildById("runeCooldownValue")

	if runeCooldownValue then
		runeCooldownValue:setText(formatCooldown(spell.cooldown))
	end

	local runeGroupCooldownValue = UI:recursiveGetChildById("runeGroupCooldownValue")

	if runeGroupCooldownValue then
		runeGroupCooldownValue:setText(formatCooldown(spell.groupCooldown))
	end

	createVocationIcons(UI:recursiveGetChildById("runeVocationsPanel"), spell.vocations, true)
end

selectSpellDetails = function(spell)
	currentSpell = spell
	lastSelectedSpellId = spell and spell.id or nil

	local emptyState = UI:recursiveGetChildById("emptyState")

	if emptyState then
		emptyState:setVisible(false)
	end

	local spellDetails = UI:recursiveGetChildById("spellDetails")

	if not spellDetails then
		return
	end

	spellDetails:setVisible(true)

	local spellIcon = spellDetails:recursiveGetChildById("spellIcon")

	if spellIcon then
		applyMagicalArchivesSpellIcon(spellIcon, spell.spellIconData, 32)
	end

	local spellName = spellDetails:recursiveGetChildById("spellName")

	if spellName then
		spellName:setText(spell.name or "Unknown")
	end

	local spellWords = spellDetails:recursiveGetChildById("spellWords")

	if spellWords then
		spellWords:setText(spell.words or "")
	end

	local spellLevel = spellDetails:recursiveGetChildById("spellLevel")

	if spellLevel then
		if spell.isRune then
			spellLevel:setText("Magic Level " .. (spell.maglevel or 0))
		else
			spellLevel:setText("Level " .. (spell.level or 0))
		end
	end

	createVocationIcons(spellDetails:recursiveGetChildById("vocationPanel"), spell.isRune and spell.runeVocations or spell.vocations)

	local runeSpellTab = UI:recursiveGetChildById("runeSpellTab")

	if runeSpellTab then
		runeSpellTab:setVisible(spell.isRune == true)
	end

	updateCombatStatsUI(spell)
	updateAdditionalInfoUI(spell)

	if spell.isRune then
		updateRuneSpellUI(spell)
	end

	local aimTargetBox = UI:recursiveGetChildById("aimTargetBox")

	if aimTargetBox then
		local showAimTarget = isDirectionalSpell(spell)

		aimTargetBox:setVisible(showAimTarget)

		if showAimTarget then
			aimTargetBox:setChecked(isAimAtTargetEnabledForSpell(spell), true)
		end
	end

	local nextTab = activeDetailsTab or "combat"

	if nextTab == "rune" and not spell.isRune then
		nextTab = "combat"
	end

	selectTab(nextTab)
end

function updateSpellListUI()
	if not UI then
		return
	end

	local searchEdit = getSearchEditWidget()
	local keepSearchFocus = searchEdit and searchEdit:isFocused()
	local spellList = UI:recursiveGetChildById("spellList")

	if not spellList then
		return
	end

	spellList:destroyChildren()

	local playerLevel = getPlayerLevel()
	local playerVocation = getPlayerVocation()
	local firstWidget, selectedWidget

	for _, spell in ipairs(filteredSpells) do
		local widget = g_ui.createWidget("MagicalArchivesSpellListItem", spellList)

		if widget then
			local spellIcon = widget:getChildById("spellIcon")

			if spellIcon then
				applyMagicalArchivesSpellIcon(spellIcon, spell.spellIconData, 20)
			end

			local nameLabel = widget:getChildById("spellName")

			if nameLabel then
				local displayName = spell.name or "Unknown"

				if #displayName > 18 then
					displayName = displayName:sub(1, 15) .. "..."

					nameLabel:setTooltip(spell.name)
				end

				nameLabel:setText(displayName)
			end

			local lockedMask = widget:getChildById("lockedMask")

			if lockedMask then
				local isLevelLocked = spell.level and playerLevel < spell.level
				local isVocationLocked = not spellMatchesBaseVocation(spell.vocations, normalizeBaseVocation(playerVocation))

				lockedMask:setVisible(isLevelLocked or isVocationLocked)
			end

			widget.spell = spell

			function widget:onClick()
				selectSpellListWidget(self, false)
			end

			firstWidget = firstWidget or widget

			if lastSelectedSpellId and spell.id == lastSelectedSpellId then
				selectedWidget = widget
			end
		end
	end

	if #filteredSpells == 0 then
		local emptyLabel = g_ui.createWidget("Label", spellList)

		emptyLabel:setText(tr("No spells found"))
		emptyLabel:setColor("#909090")
		emptyLabel:setTextAlign(AlignCenter)

		currentSpell = nil
		selectedSpellListWidget = nil
	else
		local widgetToSelect = selectedWidget or firstWidget

		if spellList.ensureChildVisible then
			spellList:ensureChildVisible(widgetToSelect)
		end

		selectSpellListWidget(widgetToSelect, keepSearchFocus)

		if keepSearchFocus then
			focusMagicalArchivesSearchEdit()
		end
	end
end

local function loadSpellsData()
	allSpells = {}

	local spells = readJsonFile(SPELLS_FILE)

	if type(spells) ~= "table" then
		applyAllFilters()

		return
	end

	local previewById = buildPreviewBySpellId()

	for _, entry in ipairs(spells) do
		if type(entry) == "table" then
			allSpells[#allSpells + 1] = normalizeSpell(entry, previewById)
		end
	end

	table.sort(allSpells, function(a, b)
		return (a.name or ""):lower() < (b.name or ""):lower()
	end)
	applyAllFilters()
end

local function assignSpellToActionBar()
	if not currentSpell then
		if modules.game_textmessage then
			modules.game_textmessage.displayStatusMessage(tr("Please select a spell first."))
		end

		return
	end

	if modules.game_actionbar and modules.game_actionbar.startCyclopediaSpellSlotAssign then
		local cyclopediaHide = modules.game_cyclopedia and modules.game_cyclopedia.hide
		if modules.game_actionbar.startCyclopediaSpellSlotAssign(currentSpell.name, currentSpell.words, "magicalArchives") and cyclopediaHide then
			preserveSelectionOnNextOpen = true

			cyclopediaHide()
		end
	elseif modules.game_textmessage then
		modules.game_textmessage.displayStatusMessage(tr("Action bar spell assignment is not available."))
	end
end

local function onAimTargetChange(checkbox)
	if not currentSpell or not currentSpell.id or currentSpell.id <= 0 then
		return
	end

	local enabled = checkbox:isChecked()
	local spellId = currentSpell.id

	if enabled then
		aimAtTargetBySpellId[spellId] = true
	else
		aimAtTargetBySpellId[spellId] = nil
	end

	saveAimAtTargetData()
	sendSpellAimUpdate(spellId, enabled)
end

local function bindUICallbacks()
	local combatStatsTab = UI:recursiveGetChildById("combatStatsTab")

	if combatStatsTab then
		function combatStatsTab.onClick()
			selectTab("combat")
		end
	end

	local additionalTab = UI:recursiveGetChildById("additionalTab")

	if additionalTab then
		function additionalTab.onClick()
			selectTab("additional")
		end
	end

	local runeSpellTab = UI:recursiveGetChildById("runeSpellTab")

	if runeSpellTab then
		function runeSpellTab.onClick()
			selectTab("rune")
		end
	end

	local assignSpellBtn = UI:recursiveGetChildById("assignSpellBtn")

	if assignSpellBtn then
		assignSpellBtn.onClick = assignSpellToActionBar
	end

	local aimTargetBox = UI:recursiveGetChildById("aimTargetBox")

	if aimTargetBox then
		aimTargetBox.onCheckChange = onAimTargetChange
	end
end

function Cyclopedia.MagicalArchivesSearchText(text)
	activeSearchText = tostring(text or "")

	if UI and UI:isVisible() then
		applyAllFilters()
	end
end

function Cyclopedia.releaseMagicalArchivesInput()
	if not UI or UI:isDestroyed() then
		restoreGameKeyboardForWalking()

		return
	end

	closeFilterPopup()

	local searchEdit = getSearchEditWidget()

	if searchEdit and not searchEdit:isDestroyed() and searchEdit:isFocused() then
		pcall(function()
			if searchEdit.blur then
				searchEdit:blur()
			end
		end)
	end

	restoreGameKeyboardForWalking()
end

function Cyclopedia.clearMagicalArchivesUI()
	closeFilterPopup()
	selectedSpellListWidget = nil
	Cyclopedia.releaseMagicalArchivesInput()
	Cyclopedia.MagicalArchivesPreview.stop()

	if UI and not UI:isDestroyed() then
		UI:destroy()
	end

	UI = nil
end

function Cyclopedia.openSpellInMagicalArchives(spellId)
	spellId = tonumber(spellId)

	if not spellId or spellId <= 0 then
		return false
	end

	Cyclopedia._pendingMagicalArchivesSpellId = spellId

	local cyclopedia = modules.game_cyclopedia

	if cyclopedia and cyclopedia.isVisible and cyclopedia.isVisible() then
		if cyclopedia.show then
			cyclopedia.show("magicalArchives")
		end

		return true
	end

	if cyclopedia and cyclopedia.show then
		cyclopedia.show("magicalArchives")

		return true
	end

	return false
end

function isAimAtTargetEnabled(spellId)
	spellId = tonumber(spellId)

	if not spellId or spellId <= 0 then
		return false
	end

	return aimAtTargetBySpellId[spellId] == true
end

local AIM_TURN_CAST_DELAY_MS = 50

local function toCardinalDirection(dir)
	if dir == nil then
		return nil
	end

	if dir == North or dir == East or dir == South or dir == West then
		return dir
	end

	if dir == NorthEast or dir == NorthWest then
		return North
	end

	if dir == SouthEast or dir == SouthWest then
		return South
	end

	return nil
end

local function resolveSpellFromInstantCastMessage(message)
	if not message or message == "" or not Spells then
		return nil
	end

	local lowered = message:lower()
	local spell = Spells.getSpellDataByParamWords(lowered)

	if not spell then
		spell = Spells.getSpellDataByWords(lowered:match("^%s*(.-)%s*$"))
	end

	return spell
end

local function getSpellAimTurnTarget()
	local target = g_game.getAttackingCreature()

	if target then
		return target
	end

	if g_game.getFollowingCreature then
		return g_game.getFollowingCreature()
	end

	return nil
end

-- Returns true when a turn packet was sent and the spell cast should be delayed briefly.
local function turnTowardTargetForAimSpell(spell)
	if not spell or not spell.id or not isAimAtTargetEnabled(spell.id) then
		return false
	end

	if not g_game.isOnline or not g_game.isOnline() then
		return false
	end

	local player = g_game.getLocalPlayer()
	local target = getSpellAimTurnTarget()

	if not player or not target then
		return false
	end

	if target.isRemoved and target:isRemoved() then
		return false
	end

	local playerPos = player:getPosition()
	local targetPos = target:getPosition()

	if not playerPos or not targetPos then
		return false
	end

	local rawDir

	if getDirectionFromPos then
		rawDir = getDirectionFromPos(playerPos, targetPos)
	else
		local dx = targetPos.x - playerPos.x
		local dy = targetPos.y - playerPos.y

		if math.abs(dx) > math.abs(dy) then
			rawDir = dx > 0 and East or West
		elseif dy ~= 0 then
			rawDir = dy > 0 and South or North
		end
	end

	local dir = toCardinalDirection(rawDir)
	local curDir = player:getDirection()

	if dir ~= nil and curDir ~= dir and g_game.turn then
		local ok = pcall(function()
			g_game.turn(dir)
		end)

		if ok then
			return true
		end
	end

	return false
end

local function onBeforeSpellTalk(message)
	if type(message) ~= "string" then
		return 0
	end

	local spell = resolveSpellFromInstantCastMessage(message)

	if turnTowardTargetForAimSpell(spell) then
		return AIM_TURN_CAST_DELAY_MS
	end

	return 0
end

function Cyclopedia.uninstallSpellAimTalkHook()
	if Cyclopedia._onBeforeSpellTalkHandler then
		disconnect(g_game, {
			onBeforeSpellTalk = Cyclopedia._onBeforeSpellTalkHandler
		})
		Cyclopedia._onBeforeSpellTalkHandler = nil
	end

	if g_game and g_game.__spellAimOriginalTalk then
		g_game.talk = g_game.__spellAimOriginalTalk
		g_game.__spellAimOriginalTalk = nil
	end
end

if Cyclopedia.uninstallSpellAimTalkHook then
	Cyclopedia.uninstallSpellAimTalkHook()
end

Cyclopedia._onBeforeSpellTalkHandler = onBeforeSpellTalk

function showMagicalArchives()
	closeFilterPopup()

	if UI and not UI:isDestroyed() then
		UI:destroy()
	end

	UI = g_ui.loadUI("magicalArchives", contentContainer)

	if not UI then
		g_logger.error("Failed to load magicalArchives UI")

		return
	end

	UI:show()

	if Cyclopedia.setGoldBaseVisible then
		Cyclopedia.setGoldBaseVisible(false)
	end

	if firstOpen then
		resetFiltersToDefault()

		firstOpen = false
	end

	currentSpell = nil

	if Cyclopedia._pendingMagicalArchivesSpellId then
		lastSelectedSpellId = Cyclopedia._pendingMagicalArchivesSpellId
		Cyclopedia._pendingMagicalArchivesSpellId = nil
	elseif preserveSelectionOnNextOpen then
		preserveSelectionOnNextOpen = false
	else
		lastSelectedSpellId = nil
	end

	activeSearchText = ""

	bindUICallbacks()
	setupFiltersUI()
	setupSearchUI()
	loadSpellsData()
	loadAimAtTargetData()
	syncStoredSpellAimToServer()
end

local function refreshAimAtTargetFromSettings()
	loadAimAtTargetData()
	syncStoredSpellAimToServer()
end

local function onMagicalArchivesGameStart()
	refreshAimAtTargetFromSettings()
	scheduleEvent(refreshAimAtTargetFromSettings, 1000)
end

refreshAimAtTargetFromSettings()

connect(g_game, {
	onGameStart = onMagicalArchivesGameStart,
	onBeforeSpellTalk = onBeforeSpellTalk
})
