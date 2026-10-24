local OPCODE_PLAYER_PODIUM = 0xC5

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

local function onPlayerPodiumOpcode(_, msg)
	local currentOutfit = readOutfit(msg)
	local mount = msg:getU16()
	if mount > 0 then
		currentOutfit.mount = mount
		currentOutfit.mountHead = msg:getU8()
		currentOutfit.mountBody = msg:getU8()
		currentOutfit.mountLegs = msg:getU8()
		currentOutfit.mountFeet = msg:getU8()
	end
	local effectCount = msg:getU16()

	for _ = 1, effectCount do
		msg:getU16()
	end

	local outfits = {}
	local count = msg:getU16()
	if count > 5000 then
		g_logger.error(string.format('Player podium 0xC5: invalid outfit count %d', count))
		msg:setReadPos(msg:getMessageSize())
		return
	end

	for _ = 1, count do
		local lookType = msg:getU16()
		local name = msg:getString()
		local addons = msg:getU8()
		local head = msg:getU8()
		local body = msg:getU8()
		local legs = msg:getU8()
		local feet = msg:getU8()
		table.insert(outfits, {
			lookType = lookType,
			name = name,
			addons = addons,
			head = head,
			body = body,
			legs = legs,
			feet = feet,
		})
	end

	local position = msg:getPosition()
	local itemId = msg:getU16()
	local stackPos = msg:getU8()
	local direction = msg:getU8()
	local podiumVisible = msg:getU8() ~= 0
	local creatureVisible = msg:getU8() ~= 0

	if modules.game_podium_player and modules.game_podium_player.onParsePlayerPodium then
		modules.game_podium_player.onParsePlayerPodium(currentOutfit, outfits, position, itemId, stackPos, podiumVisible,
			creatureVisible, direction)
	end
end

function initPlayerPodiumProtocol()
	ProtocolGame.registerOpcode(OPCODE_PLAYER_PODIUM, onPlayerPodiumOpcode)
end

function terminatePlayerPodiumProtocol()
	ProtocolGame.unregisterOpcode(OPCODE_PLAYER_PODIUM)
end
