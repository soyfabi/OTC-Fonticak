local OPCODE_MONSTER_PODIUM = 0xC2

local function readOutfit(msg, lookType)
	lookType = lookType or msg:getU16()
	local outfit = { type = lookType }

	if lookType ~= 0 then
		outfit.head = msg:getU8()
		outfit.body = msg:getU8()
		outfit.legs = msg:getU8()
		outfit.feet = msg:getU8()
		outfit.addons = msg:getU8()
	else
		outfit.auxType = msg:getU16()
	end

	return outfit
end

-- position (5) + itemId u16 + stackPos + direction + podiumVisible + creatureVisible
local PODIUM_PACKET_FOOTER_SIZE = 11

local function onMonsterPodiumOpcode(_, msg)
	local currentOutfit = readOutfit(msg)
	local effectCount = msg:getU16()

	for _ = 1, effectCount do
		msg:getU16()
	end

	local bossPodium = msg:getU8() ~= 0
	local bosses = {}
	local bossOutfits = {}
	local monsters = {}
	local count = msg:getU16()
	if count > 5000 then
		g_logger.error(string.format('Monster podium 0xC2: invalid creature count %d', count))
		msg:setReadPos(msg:getMessageSize())
		return
	end

	local entryFormat = 0
	if bossPodium then
		entryFormat = 1
	elseif count > 0 and msg:getUnreadSize() > count * 2 + PODIUM_PACKET_FOOTER_SIZE then
		entryFormat = 1
	end

	for _ = 1, count do
		local raceId = msg:getU16()

		if entryFormat >= 1 then
			if msg:getUnreadSize() < 2 then
				g_logger.error('Monster podium 0xC2: truncated entry (expected name)')
				msg:setReadPos(msg:getMessageSize())
				return
			end
			local name = msg:getString()
			local outfit = readOutfit(msg)
			bosses[raceId] = name
			bossOutfits[raceId] = outfit
		end

		if not bossPodium then
			table.insert(monsters, raceId)
		end
	end

	local position = msg:getPosition()
	local itemId = msg:getU16()
	local stackPos = msg:getU8()
	local direction = msg:getU8()
	local podiumVisible = msg:getU8() ~= 0
	local creatureVisible = msg:getU8() ~= 0

	if modules.game_podium_monster then
		if modules.game_podium_monster.setBossOutfits then
			modules.game_podium_monster.setBossOutfits(bossOutfits)
		end
		if modules.game_podium_monster.onParseMonsterPodium then
			modules.game_podium_monster.onParseMonsterPodium(currentOutfit, 0, bossPodium, bosses, monsters, position,
				itemId, stackPos, podiumVisible, creatureVisible, direction)
		end
	end
end

function initPodiumProtocol()
	ProtocolGame.registerOpcode(OPCODE_MONSTER_PODIUM, onMonsterPodiumOpcode)
end

function terminatePodiumProtocol()
	ProtocolGame.unregisterOpcode(OPCODE_MONSTER_PODIUM)
end
