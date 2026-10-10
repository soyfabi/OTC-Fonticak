-- Forgotten Server / Fonticak bosstiary wire format (opcodes 0x61, 0x73).
-- Handled in Lua so parsing stays correct even when the C++ switch is outdated.

local OPCODE_BOSSTIARY_DATA = 0x61
local OPCODE_BOSSTIARY_SLOTS = 0x62
local OPCODE_BOSSTIARY_WINDOW = 0x73
local OPCODE_BOSSTIARY_TRACKER = 0x2A
local SLOT_TWO_UNLOCK_POINTS = 1500

local registered = false

local function skipBosstiaryBaseData(msg)
	for _ = 1, 18 do
		msg:getU16()
	end
end

local function readCreatureInfo(msg)
	local name = msg:getString()

	return {
		name = name,
		outfit = {
			type = msg:getU16(),
			head = msg:getU8(),
			body = msg:getU8(),
			legs = msg:getU8(),
			feet = msg:getU8(),
			addons = msg:getU8()
		}
	}
end

local function skipCreatureInfo(msg)
	readCreatureInfo(msg)
end

local function readOptionalCreatureInfo(msg)
	if msg:getU8() == 0 then
		return nil
	end
	return readCreatureInfo(msg)
end

local function skipOptionalCreatureInfo(msg)
	readOptionalCreatureInfo(msg)
end

local function readSlotBytes(msg)
	return {
		bossRace = msg:getU8(),
		killCount = msg:getU32(),
		lootBonus = msg:getU16(),
		killBonus = msg:getU8(),
		bossRaceRepeat = msg:getU8(),
		removePrice = msg:getU32(),
		inactive = msg:getU8()
	}
end

local function shouldReadAssignedSlotBytes(isUnlocked, bossId)
	return isUnlocked and bossId and bossId > 0 and bossId ~= SLOT_TWO_UNLOCK_POINTS
end

local function parseBosstiaryWindow(_protocol, msg)
	local count = msg:getU16()
	local data = {}

	for _ = 1, count do
		local raceId = msg:getU32()
		local category = msg:getU8()
		local kills = msg:getU32()
		msg:getU8()
		local isTrackerActived = msg:getU8()
		local creatureInfo = readCreatureInfo(msg)

		data[#data + 1] = {
			raceId = raceId,
			category = category,
			kills = kills,
			isTrackerActived = isTrackerActived,
			name = creatureInfo.name,
			outfit = creatureInfo.outfit,
			visible = true
		}
	end

	if Cyclopedia and Cyclopedia.bosstiaryTrackerDebug then
		Cyclopedia.bosstiaryTrackerDebug("parseBosstiaryWindow (Lua 0x73) count=" .. tostring(count))
	end

	if Cyclopedia and Cyclopedia.LoadBosstiaryCreatures then
		Cyclopedia.LoadBosstiaryCreatures(data)
	end

	return true
end

local function parseBossSlots(_protocol, msg)
	local data = {}

	data.playerPoints = msg:getU32()
	data.totalPointsNextBonus = msg:getU32()
	data.currentBonus = msg:getU16()
	data.nextBonus = msg:getU16()

	data.isSlotOneUnlocked = msg:getU8() == 1
	data.bossIdSlotOne = msg:getU32()
	data.slotOneData = nil
	if shouldReadAssignedSlotBytes(data.isSlotOneUnlocked, data.bossIdSlotOne) then
		data.slotOneData = readSlotBytes(msg)
	end
	skipOptionalCreatureInfo(msg)

	data.isSlotTwoUnlocked = msg:getU8() == 1
	data.bossIdSlotTwo = msg:getU32()
	data.slotTwoData = nil
	if shouldReadAssignedSlotBytes(data.isSlotTwoUnlocked, data.bossIdSlotTwo) then
		data.slotTwoData = readSlotBytes(msg)
	end
	skipOptionalCreatureInfo(msg)

	data.isTodaySlotUnlocked = msg:getU8() == 1
	data.boostedBossId = msg:getU32()
	data.todaySlotData = nil
	if data.isTodaySlotUnlocked and data.boostedBossId and data.boostedBossId > 0 then
		data.todaySlotData = readSlotBytes(msg)
	end
	local boostedCreature = readOptionalCreatureInfo(msg)
	if boostedCreature then
		data.boostedBossName = boostedCreature.name
		data.boostedBossOutfit = boostedCreature.outfit
		if Cyclopedia and Cyclopedia.Bosstiary and data.boostedBossId and data.boostedBossId > 0 then
			Cyclopedia.Bosstiary.OutfitsByRaceId = Cyclopedia.Bosstiary.OutfitsByRaceId or {}
			Cyclopedia.Bosstiary.NamesByRaceId = Cyclopedia.Bosstiary.NamesByRaceId or {}
			if boostedCreature.outfit and (boostedCreature.outfit.type or 0) > 0 then
				Cyclopedia.Bosstiary.OutfitsByRaceId[data.boostedBossId] = boostedCreature.outfit
			end
			if boostedCreature.name and boostedCreature.name ~= "" then
				Cyclopedia.Bosstiary.NamesByRaceId[data.boostedBossId] = boostedCreature.name
			end
			if Cyclopedia.rememberBosstiaryTrackerMeta then
				Cyclopedia.rememberBosstiaryTrackerMeta(data.boostedBossId, boostedCreature.name, boostedCreature.outfit)
			end
		end
	end

	data.bossesUnlocked = msg:getU8() == 1
	data.bossesUnlockedData = {}
	if data.bossesUnlocked then
		local count = msg:getU16()
		for _ = 1, count do
			data.bossesUnlockedData[#data.bossesUnlockedData + 1] = {
				bossId = msg:getU32(),
				bossRace = msg:getU8()
			}
		end
	end

	if Cyclopedia and Cyclopedia.loadBossSlots then
		Cyclopedia.loadBossSlots(data)
	end

	return true
end

function sendBosstiaryTrackerStatus(raceId, enabled)
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return false
	end

	raceId = tonumber(raceId) or 0
	if raceId <= 0 then
		return false
	end

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_BOSSTIARY_TRACKER)
	msg:addU32(raceId)
	msg:addU8(enabled and 1 or 0)
	protocolGame:send(msg)
	return true
end

function initBosstiaryProtocol()
	if registered then
		return
	end

	ProtocolGame.registerOpcode(OPCODE_BOSSTIARY_DATA, function(_protocol, msg)
		skipBosstiaryBaseData(msg)
		return true
	end)

	ProtocolGame.registerOpcode(OPCODE_BOSSTIARY_WINDOW, parseBosstiaryWindow)
	ProtocolGame.registerOpcode(OPCODE_BOSSTIARY_SLOTS, parseBossSlots)
	registered = true
end

function terminateBosstiaryProtocol()
	if not registered then
		return
	end

	ProtocolGame.unregisterOpcode(OPCODE_BOSSTIARY_DATA)
	ProtocolGame.unregisterOpcode(OPCODE_BOSSTIARY_WINDOW)
	ProtocolGame.unregisterOpcode(OPCODE_BOSSTIARY_SLOTS)
	registered = false
end
