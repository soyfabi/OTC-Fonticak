-- Shared widget IDs and colors for the skills panel.
-- IDs match skills.otui / protocol bindings (legacy spelling and casing).

SKILL_COLORS = {
	positive = "#2EEA32",
	negative = "#D33C3C",
	value = "#FFEA79"
}

SKILL_POSITIVE_COLOR = SKILL_COLORS.positive
SKILL_NEGATIVE_COLOR = SKILL_COLORS.negative
SKILL_VALUE_COLOR = SKILL_COLORS.value

WHEEL_ABSORB_NAME_TO_ID = {
	physical = 0,
	fire = 1,
	earth = 2,
	energy = 3,
	ice = 4,
	holy = 5,
	death = 6,
	healing = 7,
	drown = 8,
	lifedrain = 9,
	manadrain = 10
}

OFFENCE_BAR_STATS_IDS = {
	"skillId7",
	"skillId8",
	"skillId9",
	"skillId10",
	"skillId11",
	"skillId12",
	"skillId13",
	"skillId14",
	"skillId15",
	"skillId16"
}

EXTENDED_OFFENCE_STATS = {
	"criticalHit",
	"damageHealing",
	"attackValue",
	"convertedDamage",
	"convertedElement",
	"lifeLeech",
	"manaLeech",
	"criticalChance",
	"criticalExtraDamage",
	"onslaught"
}

-- Legacy OTUI ids: UK "defence", typos drowResist/manadRainResist, mixed-case resist names.
EXTENDED_DEFENCE_STATS = {
	"physicalResist",
	"fireResist",
	"earthResist",
	"energyResist",
	"IceResist",
	"HolyResist",
	"deathResist",
	"HealingResist",
	"drowResist",
	"lifedrainResist",
	"manadRainResist",
	"defenceValue",
	"armorValue",
	"mantraValue",
	"mitigation",
	"dodge",
	"damageReflection"
}

EXTENDED_MISC_STATS = {
	"momentum",
	"transcendence",
	"amplification"
}

SKILLS_SEPARATOR_IDS = {
	offence = "separadorOnOffenceInfoChange",
	defense = "separadorOnDefenseInfoChange",
	misc = "separadorOnForgeBonusesChange"
}

PROGRESS_BAR_SKILL_IDS = {
	"level",
	"stamina",
	"offlineTraining",
	"magiclevel",
	"skillId0",
	"skillId1",
	"skillId2",
	"skillId3",
	"skillId4",
	"skillId5",
	"skillId6"
}

COMBAT_ABSORB_WIDGET_IDS = {
	[0] = "physicalResist",
	"fireResist",
	"earthResist",
	"energyResist",
	"IceResist",
	"HolyResist",
	"deathResist",
	"HealingResist",
	"drowResist",
	"lifedrainResist",
	"manadRainResist"
}

SKILL_HAND_CURSOR_IDS = {
	magiclevel = true,
	skillId0 = true,
	skillId1 = true,
	skillId2 = true,
	skillId3 = true,
	skillId4 = true,
	skillId5 = true,
	skillId6 = true
}

function setSkillsWidgetsVisible(window, widgetIds, visible)
	if not window then
		return
	end

	for _, id in pairs(widgetIds) do
		local widget = window:recursiveGetChildById(id)

		if widget then
			widget:setVisible(visible)
		end
	end
end

function hideSkillsWidgets(window, widgetIds)
	if not window then
		return
	end

	for _, id in pairs(widgetIds) do
		local widget = window:recursiveGetChildById(id)

		if widget then
			widget:hide()
		end
	end
end

function hideSkillsWidgetGroup(window, statIds, separatorId)
	setSkillsWidgetsVisible(window, statIds, false)

	if separatorId and window then
		local separator = window:recursiveGetChildById(separatorId)

		if separator then
			separator:setVisible(false)
		end
	end
end
