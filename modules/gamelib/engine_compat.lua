-- Shims for APIs used by ported modules (Crystal) that this client lacks in C++.

local function install(tbl, name, fn)
    if tbl and not tbl[name] then
        tbl[name] = fn
    end
end

do
    local hoveredCreature = nil

    install(g_game, 'setHoveredCreature', function(creature)
        if hoveredCreature == creature then
            return
        end

        local oldCreature = hoveredCreature
        hoveredCreature = creature
        signalcall(g_game.onHoveredCreatureChange, creature, oldCreature)
    end)

    install(g_game, 'clearHoveredCreature', function(creature)
        if creature ~= nil and hoveredCreature ~= creature then
            return
        end

        local oldCreature = hoveredCreature
        hoveredCreature = nil

        if oldCreature then
            signalcall(g_game.onHoveredCreatureChange, nil, oldCreature)
        end
    end)

    install(g_game, 'getHoveredCreature', function()
        return hoveredCreature
    end)
end
