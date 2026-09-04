UIGameMap = extends(UIMap, 'UIGameMap')

function UIGameMap.create()
    local gameMap = UIGameMap.internalCreate()
    gameMap:setKeepAspectRatio(true)
    gameMap:setVisibleDimension({
        width = 15,
        height = 11
    })
    gameMap:setDrawLights(true)
    return gameMap
end

local baseGetTile = UIMap.getTile

local function hasInteractiveFloorThing(tile)
    if not tile then return false end
    local useThing = tile:getTopUseThing()
    if useThing and (useThing:isContainer() or useThing:isLyingCorpse() or useThing:isUsable() or useThing:isPickupable() or not useThing:isGround()) then
        return true
    end
    return false
end

function UIGameMap:getTile(mousePos)
    local tile = baseGetTile(self, mousePos)
    local player = g_game.getLocalPlayer()
    if not player then
        return tile
    end

    local playerPos = player:getPosition()
    if not playerPos then
        return tile
    end

    if tile and tile:getPosition().z == playerPos.z then
        return tile
    end

    local playerFloorPos = self:getPosition(mousePos)
    if playerFloorPos then
        if playerFloorPos.z ~= playerPos.z then
            local dz = playerFloorPos.z - playerPos.z
            playerFloorPos.x = playerFloorPos.x + dz
            playerFloorPos.y = playerFloorPos.y + dz
            playerFloorPos.z = playerPos.z
        end

        local playerFloorTile = g_map.getTile(playerFloorPos)
        if playerFloorTile then
            -- If the upper tile has a creature, player might be interacting with the creature upstairs
            if tile and (tile:getTopCreature() or tile:getCollisionCreatureId() > 0) then
                return tile
            end

            -- If the upper tile is not walkable (e.g. roof/ceiling overhang) or the player floor tile
            -- has an interactive object/corpse/creature, prioritize the player's floor tile.
            if not tile or not tile:isWalkable() or playerFloorTile:getTopCreature() or hasInteractiveFloorThing(playerFloorTile) then
                return playerFloorTile
            end
        end
    end

    return tile
end

function UIGameMap:onDragEnter(mousePos)
    local tile = self:getTile(mousePos)
    if not tile then
        return false
    end

    local thing = tile:getTopMoveThing()
    if not thing then
        return false
    end

    if thing:isItem() and not thing:isNotMoveable() then
        UIDragIcon:display(thing)
    end

    self.currentDragThing = thing

    -- Use native cursor when enabled, otherwise use custom cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    self.allowNextRelease = false
    return true
end

function UIGameMap:onDragLeave(droppedWidget, mousePos)
    self.currentDragThing = nil
    self.hoveredWho = nil
    -- Restore cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    UIDragIcon:hide()
    return true
end

function UIGameMap:onDrop(widget, mousePos)
    if not self:canAcceptDrop(widget, mousePos) then
        return false
    end

    local tile = self:getTile(mousePos)
    if not tile then
        return false
    end

    local thing = widget.currentDragThing
    local thingPos = thing:getPosition()
    if not thingPos then
        return false
    end

    local thingTile = thing:getTile()
    if thingPos.x ~= 65535 and not thingTile then
        return false
    end

    local toPos = tile:getPosition()
    if thingPos.x == toPos.x and thingPos.y == toPos.y and thingPos.z == toPos.z then
        return false
    end

    if thing:isItem() and thing:getCount() > 1 then
        modules.game_interface.moveStackableItem(thing, toPos)
    else
        g_game.move(thing, toPos, 1)
    end

    UIDragIcon:hide()
    return true
end

function UIGameMap:onMousePress(mousePos, mouseButton)
    if not self:isDragging() then
        self.allowNextRelease = true
    end

    -- Mark look-combo as soon as the second button goes down so a fast
    -- dual release still looks instead of auto-walking.
    if mouseButton == MouseLeftButton or mouseButton == MouseRightButton then
        local other = mouseButton == MouseLeftButton and MouseRightButton or MouseLeftButton
        if g_mouse.isPressed(other) then
            self.blockNextLeftWalk = true
            self.lookComboHandled = false
        end
    end
end

function UIGameMap:onMouseMove()
    return false
end

function UIGameMap:onMouseRelease(mousePosition, mouseButton)
    if not self.allowNextRelease then
        -- Still consume a leftover left release after left+right look.
        if mouseButton == MouseLeftButton and self.blockNextLeftWalk then
            self.blockNextLeftWalk = false
            self.lookComboHandled = false
            return true
        end
        return true
    end

    local autoWalkPos = self:getPosition(mousePosition)
    local positionOffset = self:getPositionOffset(mousePosition)

    -- happens when clicking outside of map boundaries
    if not autoWalkPos then
        return false
    end

    local localPlayerPos = g_game.getLocalPlayer():getPosition()
    if autoWalkPos.z ~= localPlayerPos.z then
        local dz = autoWalkPos.z - localPlayerPos.z
        autoWalkPos.x = autoWalkPos.x + dz
        autoWalkPos.y = autoWalkPos.y + dz
        autoWalkPos.z = localPlayerPos.z
    end

    local lookThing
    local useThing
    local creatureThing
    local multiUseThing
    local attackCreature

    local tile = self:getTile(mousePosition)
    if tile then
        lookThing = tile:getTopLookThingEx(positionOffset)
        useThing = tile:getTopUseThing()
        creatureThing = tile:getTopCreatureEx(positionOffset)
        if not creatureThing then
            creatureThing = g_map.getCreatureById(tile:getCollisionCreatureId())
        end
    end

    local autoWalkTile = g_map.getTile(autoWalkPos)
    if autoWalkTile then
        attackCreature = autoWalkTile:getTopCreatureEx(positionOffset)
        if not creatureThing then
            creatureThing = autoWalkTile:getTopCreatureEx(positionOffset)
        end
    end

    -- Safety check: an item on a different Z level than the player can never be used in TFS/OT
    -- and will trigger "First go upstairs / downstairs". Fallback to the player's floor.
    if useThing and autoWalkTile and localPlayerPos and useThing:getPosition().z ~= localPlayerPos.z then
        local autoUseThing = autoWalkTile:getTopUseThing()
        if autoUseThing then
            useThing = autoUseThing
        end
    end

    if lookThing and autoWalkTile and localPlayerPos and lookThing:getPosition().z ~= localPlayerPos.z then
        local autoLookThing = autoWalkTile:getTopLookThingEx(positionOffset)
        if autoLookThing and (not lookThing or not tile or not tile:isWalkable() or not autoLookThing:isGround()) then
            lookThing = autoLookThing
        end
    end

    local ret = modules.game_interface.processMouseAction(mousePosition, mouseButton, autoWalkPos, lookThing, useThing,
        creatureThing, attackCreature)
    if ret then
        self.allowNextRelease = false
    end

    return ret
end

function UIGameMap:canAcceptDrop(widget, mousePos)
    if not widget or not widget.currentDragThing then
        return false
    end

    local children = rootWidget:recursiveGetChildrenByPos(mousePos)
    for i = 1, #children do
        local child = children[i]
        if child == self then
            return true
        elseif not child:isPhantom() then
            return false
        end
    end

    error('Widget ' .. self:getId() .. ' not in drop list.')
    return false
end
