-- Server opcode 0x34: party member health/mana percentages (OTC-Fonticak + FS partyvitals.lua)

local OPCODE_PARTY_VITALS = 0x34

PartyVitalsCache = PartyVitalsCache or {}

local partyVitalsSyncEvent

local function findMapCreature(creatureId)
	local creature = g_map.getCreatureById(creatureId)

	if creature then
		return creature
	end

	local panel = modules.game_interface and modules.game_interface.getMapPanel()

	if panel then
		for _, spec in ipairs(panel:getSpectators()) do
			if spec:getId() == creatureId then
				return spec
			end
		end
	end

	if PartyListRegistry and PartyListRegistry.byId then
		return PartyListRegistry.byId[creatureId]
	end

	return nil
end

local function pushManaToCreature(creature, manaPercent)
	if not creature or not manaPercent or manaPercent > 100 then
		return
	end

	if creature.setManaPercent then
		creature:setManaPercent(manaPercent)
	end
end

local function refreshPartyMemberMapHud(creature)
	if not creature or creature:isLocalPlayer() then
		return
	end

	applyCachedPartyVitals(creature)

	if modules.game_creatureinformation and modules.game_creatureinformation.refreshOtherManaBar then
		modules.game_creatureinformation.refreshOtherManaBar(creature)
	end
end

function applyPartyMemberVitals(creatureId, healthPercent, manaPercent)
	if not creatureId then
		return
	end

	PartyVitalsCache[creatureId] = PartyVitalsCache[creatureId] or {}
	PartyVitalsCache[creatureId].health = healthPercent
	PartyVitalsCache[creatureId].mana = manaPercent

	local creature = findMapCreature(creatureId)

	if creature then
		if healthPercent <= 100 and creature.setHealthPercent then
			creature:setHealthPercent(healthPercent)
		end
		pushManaToCreature(creature, manaPercent)
	end

	updatePartyListVitalsBars(creatureId, healthPercent, manaPercent)

	if creature then
		refreshPartyMemberMapHud(creature)
	end

end

function updatePartyListVitalsBars(creatureId, healthPercent, manaPercent)
	if not PartyListManager or not PartyListManager.instances then
		return
	end

	for _, instance in pairs(PartyListManager.instances) do
		local btn = instance.battleButtons and instance.battleButtons[creatureId]

		if btn then
			if healthPercent <= 100 and btn.setLifeBarPercent then
				btn:setLifeBarPercent(healthPercent)
			end
			if manaPercent <= 100 and btn.setManaBarPercent then
				btn:setManaBarPercent(manaPercent)
			end
			if btn.updateShowStatus then
				btn:updateShowStatus(true)
			end
		end
	end
end

function getPartyVitalsForCreature(creature)
	if not creature or not creature.getId then
		return nil
	end

	return PartyVitalsCache[creature:getId()]
end

function applyCachedPartyVitals(creature)
	if not creature or not creature.getId then
		return
	end

	local cached = PartyVitalsCache[creature:getId()]

	if not cached then
		return
	end

	if cached.health and cached.health <= 100 and creature.setHealthPercent then
		creature:setHealthPercent(cached.health)
	end
	pushManaToCreature(creature, cached.mana)

	updatePartyListVitalsBars(creature:getId(), cached.health or 101, cached.mana or 101)
end

local function syncVisiblePartyMemberMana()
	if not g_game.isOnline() then
		return
	end

	local panel = modules.game_interface and modules.game_interface.getMapPanel()

	if not panel or not CreatureList or not CreatureList.isRemotePartyMember then
		return
	end

	for _, creature in ipairs(panel:getSpectators()) do
		if CreatureList.isRemotePartyMember(creature) then
			local cached = PartyVitalsCache[creature:getId()]

			if cached and cached.mana and cached.mana <= 100 then
				if creature.getManaPercent and creature:getManaPercent() ~= cached.mana then
					pushManaToCreature(creature, cached.mana)
				end
			end

			if modules.game_creatureinformation and modules.game_creatureinformation.refreshOtherManaBar then
				modules.game_creatureinformation.refreshOtherManaBar(creature)
			end
		end
	end
end

local function onPartyMemberHealthPercentChange(creature, healthPercent, oldHealthPercent)
	if not creature or creature:isLocalPlayer() then
		return
	end

	if not CreatureList or not CreatureList.isRemotePartyMember(creature) then
		return
	end

	local cached = PartyVitalsCache[creature:getId()]

	if cached and cached.mana and cached.mana <= 100 then
		pushManaToCreature(creature, cached.mana)
	end

	refreshPartyMemberMapHud(creature)
end

local function onPartyVitalsOpcode(_protocol, msg)
	-- Per member: u32 id, u8 hp%, u8 mana%, u16 level (FS partyvitals.lua)
	local count = msg:getU8()

	for _ = 1, count do
		local creatureId = msg:getU32()
		local healthPercent = msg:getU8()
		local manaPercent = msg:getU8()
		local level = msg:getU16()

		if level > 0 then
			PartyVitalsCache[creatureId] = PartyVitalsCache[creatureId] or {}
			PartyVitalsCache[creatureId].level = level
		end

		applyPartyMemberVitals(creatureId, healthPercent, manaPercent)
	end

	if count > 0 and modules.game_minimap and modules.game_minimap.refreshMinimapPartyPins then
		modules.game_minimap.refreshMinimapPartyPins()
	end

	return true
end

local function onPartyMemberAppear(creature)
	if CreatureList and CreatureList.isRemotePartyMember and CreatureList.isRemotePartyMember(creature) then
		refreshPartyMemberMapHud(creature)
	end
end

local function onPartyMemberShieldChange(creature)
	if CreatureList and CreatureList.isRemotePartyMember and CreatureList.isRemotePartyMember(creature) then
		refreshPartyMemberMapHud(creature)
	end
end

function initPartyVitalsProtocol()
	ProtocolGame.registerOpcode(OPCODE_PARTY_VITALS, onPartyVitalsOpcode)

	if not partyVitalsCreatureConnected then
		connect(Creature, {
			onAppear = onPartyMemberAppear,
			onShieldChange = onPartyMemberShieldChange,
			onHealthPercentChange = onPartyMemberHealthPercentChange
		})
		partyVitalsCreatureConnected = true
	end

	if not partyVitalsSyncEvent then
		partyVitalsSyncEvent = cycleEvent(syncVisiblePartyMemberMana, 500)
	end
end

function terminatePartyVitalsProtocol()
	ProtocolGame.unregisterOpcode(OPCODE_PARTY_VITALS)

	if partyVitalsCreatureConnected then
		disconnect(Creature, {
			onAppear = onPartyMemberAppear,
			onShieldChange = onPartyMemberShieldChange,
			onHealthPercentChange = onPartyMemberHealthPercentChange
		})
		partyVitalsCreatureConnected = false
	end

	if partyVitalsSyncEvent then
		removeEvent(partyVitalsSyncEvent)
		partyVitalsSyncEvent = nil
	end

	PartyVitalsCache = {}
end
