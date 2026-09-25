wheelSkillStatsActive = false
wheelSkillStatsHeightEvent = nil
lastDefenseInfo = nil
lastAbsorbValues = nil
lastOffenceInfo = nil

local function clearExtendedCombatCache()
	lastDefenseInfo = nil
	lastAbsorbValues = nil
	lastOffenceInfo = nil
end

function canShowExtendedCombatStats()
	return g_game.getClientVersion() >= 1412 or wheelSkillStatsActive
end

local function mapWheelAbsorbs(absorbs)
	if type(absorbs) ~= "table" then
		return {}
	end

	local mapped = {}

	for name, value in pairs(absorbs) do
		local id = WHEEL_ABSORB_NAME_TO_ID[name]

		if id ~= nil then
			mapped[id] = value
		end
	end

	return mapped
end

function scheduleWheelSkillStatsHeightUpdate()
	if wheelSkillStatsHeightEvent then
		removeEvent(wheelSkillStatsHeightEvent)
		wheelSkillStatsHeightEvent = nil
	end

	wheelSkillStatsHeightEvent = scheduleEvent(function()
		wheelSkillStatsHeightEvent = nil
		updateHeight()
	end, 50)
end

function areOffenceStatsEnabled()
	local char = g_game.getCharacterName()

	if not char or not skillSettings or not skillSettings[char] then
		return true
	end

	return skillSettings[char].offenceStats_visible ~= false
end

function areDefenceStatsEnabled()
	local char = g_game.getCharacterName()

	if not char or not skillSettings or not skillSettings[char] then
		return true
	end

	return skillSettings[char].defenceStats_visible ~= false
end

function hideAllOffenceStatsWidgets()
	if not skillsWindow then
		return
	end

	setSkillsWidgetsVisible(skillsWindow, OFFENCE_BAR_STATS_IDS, false)
	setSkillsWidgetsVisible(skillsWindow, EXTENDED_OFFENCE_STATS, false)

	local separator = skillsWindow:recursiveGetChildById(SKILLS_SEPARATOR_IDS.offence)

	if separator then
		separator:setVisible(false)
	end
end

function hideAllDefenceStatsWidgets()
	hideSkillsWidgetGroup(skillsWindow, EXTENDED_DEFENCE_STATS, SKILLS_SEPARATOR_IDS.defense)
end

function updateOffenceSeparatorVisibility()
	if not skillsWindow or not areOffenceStatsEnabled() then
		return
	end

	local separator = skillsWindow:recursiveGetChildById(SKILLS_SEPARATOR_IDS.offence)

	if separator then
		separator:setVisible(areOffenceStatsVisible())
	end
end

function refreshOffenceStatsFromCache()
	local player = g_game.getLocalPlayer()

	if not player or not lastOffenceInfo then
		return
	end

	if lastOffenceInfo.flatBonus ~= nil then
		onFlatDamageHealingChange(player, lastOffenceInfo.flatBonus)
	end

	if lastOffenceInfo.attackValue ~= nil then
		onAttackInfoChange(player, lastOffenceInfo.attackValue, lastOffenceInfo.attackElement)
	end

	if lastOffenceInfo.convertedDamage ~= nil then
		onConvertedDamageChange(player, lastOffenceInfo.convertedDamage, lastOffenceInfo.convertedElement or 0)
	end

	if lastOffenceInfo.imbuements then
		local imbuements = lastOffenceInfo.imbuements

		onImbuementsChange(player, imbuements.lifeLeech, imbuements.manaLeech, imbuements.critChance, imbuements.critDamage, imbuements.onslaught)
	end
end

function refreshDefenceStatsFromCache()
	local player = g_game.getLocalPlayer()

	if not player or not lastDefenseInfo then
		return
	end

	onDefenseInfoChange(player, lastDefenseInfo[1], lastDefenseInfo[2], lastDefenseInfo[3], lastDefenseInfo[4], lastDefenseInfo[5], lastDefenseInfo[6])

	if lastAbsorbValues then
		onCombatAbsorbValuesChange(player, lastAbsorbValues)
	end
end

function hideOffenceStatsInSkillsBar()
	setSkillsWidgetsVisible(skillsWindow, OFFENCE_BAR_STATS_IDS, false)
end

function applyExtendedCombatVisibilitySettings()
	local char = g_game.getCharacterName()

	if not char or not skillSettings or not skillSettings[char] then
		return
	end

	if not wheelSkillStatsActive and g_game.getClientVersion() < 1412 then
		return
	end

	local settings = skillSettings[char]

	hideOffenceStatsInSkillsBar()

	if settings.offenceStats_visible == false then
		hideAllOffenceStatsWidgets()
	end

	if settings.defenceStats_visible == false then
		hideAllDefenceStatsWidgets()
	end

	if settings.miscStats_visible ~= nil then
		local showMisc = settings.miscStats_visible
		local separator = skillsWindow:recursiveGetChildById(SKILLS_SEPARATOR_IDS.misc)

		if separator then
			separator:setVisible(showMisc)
		end

		if not showMisc then
			setSkillsWidgetsVisible(skillsWindow, EXTENDED_MISC_STATS, false)
		end
	end
end

function onWheelSkillStats(protocol, opcode, data)
	if type(data) ~= "table" then
		return
	end

	wheelSkillStatsActive = true
	applyExtendedCombatVisibilitySettings()

	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	onFlatDamageHealingChange(player, data.damageAndHealing or 0)
	onAttackInfoChange(player, data.attackValue or 0, data.attackElement or 0)
	onConvertedDamageChange(player, data.convertedValue or 0, data.convertedElement or 0)
	onImbuementsChange(player, data.lifeLeech or 0, data.manaLeech or 0, data.criticalChance or 0, data.criticalDamage or 0, data.onslaught or 0)
	onDefenseInfoChange(player, data.defense or 0, data.armor or 0, data.mitigation or 0, data.dodge or 0, data.damageReflection or 0, data.mantra or 0)
	onCombatAbsorbValuesChange(player, mapWheelAbsorbs(data.absorbs))
	scheduleWheelSkillStatsHeightUpdate()
end

function resetExtendedCombatPanel()
	if not skillsWindow then
		clearExtendedCombatCache()
		return
	end

	local function resetAndHide(widgetIds)
		for _, id in pairs(widgetIds) do
			local skill = skillsWindow:recursiveGetChildById(id)

			if skill then
				local valueWidget = skill:getChildById("value")

				if valueWidget then
					valueWidget:setText("0")
				end

				skill:hide()
			end
		end
	end

	resetAndHide(EXTENDED_OFFENCE_STATS)
	resetAndHide(EXTENDED_DEFENCE_STATS)
	resetAndHide(EXTENDED_MISC_STATS)

	for _, separatorId in pairs(SKILLS_SEPARATOR_IDS) do
		local separator = skillsWindow:recursiveGetChildById(separatorId)

		if separator then
			separator:hide()
		end
	end

	clearExtendedCombatCache()
end

function clearWheelSkillStatsState()
	wheelSkillStatsActive = false

	if wheelSkillStatsHeightEvent then
		removeEvent(wheelSkillStatsHeightEvent)
		wheelSkillStatsHeightEvent = nil
	end
end
