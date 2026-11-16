-- Server opcode 0x3F: party member vitals (0x3E is also used by boss difficulty).

local OPCODE_PARTY_VITALS = 0x3F
local PARTY_VITALS_VERSION_LEGACY = 1
local PARTY_VITALS_VERSION_MAP = 2

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

	if refreshPartyFloatingVitalsBars then
		refreshPartyFloatingVitalsBars(creatureId, healthPercent, manaPercent)
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

	local creatureId = creature:getId()
	local cache = PartyVitalsCache[creatureId] or {}
	PartyVitalsCache[creatureId] = cache

	if healthPercent and healthPercent <= 100 then
		cache.health = healthPercent

		if creature.setHealthPercent then
			creature:setHealthPercent(healthPercent)
		end
	end

	if cache.mana and cache.mana <= 100 then
		pushManaToCreature(creature, cache.mana)
	end

	updatePartyListVitalsBars(creatureId, cache.health or 101, cache.mana or 101)

	if modules.game_creatureinformation and modules.game_creatureinformation.refreshOtherManaBar then
		modules.game_creatureinformation.refreshOtherManaBar(creature)
	end
end

local function storePartyVitalsEntry(creatureId, healthPercent, manaPercent, level, extra, localId, seenIds)
	seenIds[creatureId] = true

	PartyVitalsCache[creatureId] = PartyVitalsCache[creatureId] or {}
	local cache = PartyVitalsCache[creatureId]
	cache.health = healthPercent
	cache.mana = manaPercent

	if level and level > 0 then
		cache.level = level
	end

	if extra then
		if extra.pos then
			cache.pos = extra.pos
		end
		if extra.isLeader ~= nil then
			cache.isLeader = extra.isLeader
		end
		if extra.vocation then
			cache.vocation = extra.vocation
		end
		if extra.name and extra.name ~= "" then
			cache.name = extra.name
		end
	end

	if creatureId ~= localId then
		applyPartyMemberVitals(creatureId, healthPercent, manaPercent)
	end
end

local function onPartyVitalsOpcode(_protocol, msg)
	local count = msg:getU8()

	if count == 0 then
		PartyVitalsCache = {}

		if modules.game_minimap and modules.game_minimap.refreshMinimapPartyPins then
			modules.game_minimap.refreshMinimapPartyPins()
		end

		return true
	end

	local posAfterCount = msg:getReadPos()
	local version = msg:getU8()

	if version ~= PARTY_VITALS_VERSION_LEGACY and version ~= PARTY_VITALS_VERSION_MAP then
		msg:setReadPos(posAfterCount)
		version = PARTY_VITALS_VERSION_LEGACY
	end

	local seenIds = {}
	local localPlayer = g_game.getLocalPlayer()
	local localId = localPlayer and localPlayer:getId()

	for _ = 1, count do
		local creatureId = msg:getU32()
		local healthPercent = msg:getU8()
		local manaPercent = msg:getU8()
		local level = msg:getU16()
		local extra

		if version >= PARTY_VITALS_VERSION_MAP then
			extra = {
				pos = {
					x = msg:getU16(),
					y = msg:getU16(),
					z = msg:getU8()
				},
				isLeader = msg:getU8() == 1,
				vocation = msg:getU8(),
				name = ""
			}

			local ok, name = pcall(function()
				return msg:getString()
			end)

			if ok and name then
				extra.name = name
			end
		end

		storePartyVitalsEntry(creatureId, healthPercent, manaPercent, level, extra, localId, seenIds)
	end

	for cachedId in pairs(PartyVitalsCache) do
		if not seenIds[cachedId] then
			PartyVitalsCache[cachedId] = nil
		end
	end

	if modules.game_minimap and modules.game_minimap.refreshMinimapPartyPins then
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

local function onLocalPartyShieldChange(player)
	if player and player.isPartyMember and not player:isPartyMember() then
		PartyVitalsCache = {}

		if modules.game_minimap and modules.game_minimap.refreshMinimapPartyPins then
			modules.game_minimap.refreshMinimapPartyPins()
		end
	end
end

function getPartyVitalsCacheTable()
	return PartyVitalsCache
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

	if not partyVitalsLocalConnected then
		connect(LocalPlayer, {
			onShieldChange = onLocalPartyShieldChange
		})
		partyVitalsLocalConnected = true
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

	if partyVitalsLocalConnected then
		disconnect(LocalPlayer, {
			onShieldChange = onLocalPartyShieldChange
		})
		partyVitalsLocalConnected = false
	end

	if partyVitalsSyncEvent then
		removeEvent(partyVitalsSyncEvent)
		partyVitalsSyncEvent = nil
	end

	PartyVitalsCache = {}
end
