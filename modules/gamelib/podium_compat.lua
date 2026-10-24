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

install(g_game, 'confirmEditPodium', function(raceId, thing, direction, showPlatform, showCreature)
	if not thing or not g_game.sendMonsterPodiumOutfit then
		return
	end
	local pos = thing:getPosition()
	if not pos then
		return
	end
	g_game.sendMonsterPodiumOutfit(raceId or 0, pos, thing:getId(), thing:getStackPos() or 0, direction or 2,
		showPlatform ~= false, showCreature ~= false)
end)

install(g_game, 'changeOutfitPodium', function(outfit, position, itemClientId, stackpos, direction, showPlatform,
	showOutfit)
	if not g_game.sendPlayerPodiumOutfit or not position then
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
end

if UIItem then
	install(UIItem, 'setPodiumPreview', function() end)
end
