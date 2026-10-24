-- Crystal game_customisepodium / game_outfit podium sends wired to Fonticak C++.

local function install(tbl, name, fn)
	if tbl and not tbl[name] then
		tbl[name] = fn
	end
end

install(g_game, 'requestConfigurePodium', function(thing)
	if thing then
		g_game.use(thing)
	end
end)

install(g_game, 'requestPodiumData', function(thing)
	if thing then
		g_game.use(thing)
	end
end)

install(g_game, 'changePodiumOutfit', function(outfit, position, itemClientId, direction, showPlatform)
	if g_game.changeOutfitPodium then
		local showOutfit = outfit and (outfit.type or 0) > 0
		g_game.changeOutfitPodium(outfit, position, itemClientId, 0, direction, showPlatform, showOutfit)
	end
end)

install(g_game, 'confirmEditPodium', function(raceId, thing, direction, showPlatform, showCreature)
	if not g_game.sendMonsterPodiumOutfit then
		return
	end

	local pos, itemId, stackPos
	local customise = modules.game_customisepodium
	if customise and customise.podiumProtocolData then
		local data = customise.podiumProtocolData
		pos = data.position
		itemId = data.itemClientId
		stackPos = data.stackpos
	end

	if thing then
		if not pos and thing.getPosition then
			pos = thing:getPosition()
		end
		if not itemId and thing.getId then
			itemId = thing:getId()
		end
		if stackPos == nil and thing.getStackPos then
			stackPos = thing:getStackPos()
		end
	end

	if not pos or pos.x == 65535 then
		return
	end

	g_game.sendMonsterPodiumOutfit(raceId or 0, pos, itemId or 0, stackPos or 0, direction or 2, showPlatform ~= false,
		showCreature ~= false)
end)

install(g_game, 'changeOutfitPodium', function(outfit, position, itemClientId, stackpos, direction, showPlatform,
	showOutfit)
	if not g_game.sendPlayerPodiumOutfit then
		return
	end

	local playerPodium = modules.game_podium_player
	if playerPodium and playerPodium.getPodiumSendContext then
		local ctx = playerPodium.getPodiumSendContext()
		if ctx then
			position = ctx.position or ctx.pos or position
			itemClientId = ctx.itemClientId or ctx.itemId or itemClientId
			stackpos = ctx.stackpos or stackpos
		end
	end

	if not position or position.x == 65535 then
		return
	end

	outfit = outfit or {}
	local lookType = showOutfit ~= false and (outfit.type or 0) or 0
	g_game.sendPlayerPodiumOutfit(lookType, outfit.head or 0, outfit.body or 0, outfit.legs or 0, outfit.feet or 0,
		outfit.addons or 0, outfit.mount or 0, position, itemClientId or 0, stackpos or 0, direction or 2,
		showPlatform ~= false, showOutfit ~= false)
end)

-- Preview helpers used by Crystal customisepodium (no C++ Lua API yet).
local podiumPreviewState = {}

local function podiumKey(item)
	if item and item.getId then
		return tostring(item:getId()) .. ':' .. tostring(item)
	end
	return nil
end

if Item then
	install(Item, 'getPodiumOutfit', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		return st and st.outfit or { type = 0 }
	end)

	install(Item, 'setPodium', function(self, outfit, direction, showPlatform, showCreature)
		local key = podiumKey(self)
		if not key then
			return
		end
		podiumPreviewState[key] = {
			outfit = outfit or { type = 0 },
			direction = direction,
			showPlatform = showPlatform,
			showCreature = showCreature,
		}
	end)

	install(Item, 'hasPodiumDisplay', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		local o = st and st.outfit
		return o and ((o.type or 0) > 0 or (o.auxType or 0) > 0)
	end)

	install(Item, 'getPodiumDirection', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		return st and st.direction
	end)

	install(Item, 'isPodiumShowPlatform', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		return st == nil or st.showPlatform ~= false
	end)

	install(Item, 'isPodiumShowCreature', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		return st == nil or st.showCreature ~= false
	end)

	install(Item, 'setOutfit', function(self, outfit)
		local key = podiumKey(self)
		if not key then
			return
		end
		podiumPreviewState[key] = podiumPreviewState[key] or {}
		podiumPreviewState[key].outfit = table.copy(outfit or { type = 0 })
	end)

	install(Item, 'getOutfit', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		if st and st.outfit then
			return table.copy(st.outfit)
		end
		return { type = 0 }
	end)

	install(Item, 'setPodiumDirection', function(self, direction)
		local key = podiumKey(self)
		if not key then
			return
		end
		podiumPreviewState[key] = podiumPreviewState[key] or {}
		podiumPreviewState[key].direction = direction
	end)

	install(Item, 'getPodiumDir', function(self)
		local st = podiumPreviewState[podiumKey(self)]
		return st and st.direction or 2
	end)
end

if UIItem then
	install(UIItem, 'setPodiumPreview', function() end)
end
