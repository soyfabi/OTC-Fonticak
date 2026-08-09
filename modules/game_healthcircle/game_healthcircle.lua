imageSizeBroad = 0
imageSizeThin = 0

mapPanel = modules.game_interface.getMapPanel()
gameRootPanel = modules.game_interface.gameBottomPanel
gameLeftPanel = modules.game_interface.getLeftPanel()
gameTopMenu = modules.client_topmenu.getTopMenu()

function currentViewMode()
    return modules.game_interface.currentViewMode
end

healthCircle = nil
manaCircle = nil
manaShieldCircle = nil
manaShieldCircleFront = nil
expCircle = nil
skillCircle = nil

healthCircleFront = nil
manaCircleFront = nil
expCircleFront = nil
skillCircleFront = nil

manaShieldImageSizeBroad = 0
manaShieldImageSizeThin = 0
manaShieldCircleOffsetX = -52
manaShieldCircleOffsetY = 7

isHealthCircle = g_settings.exists('healthCheckBox') and g_settings.getBoolean('healthCheckBox') or
    not g_settings.getBoolean('healthcircle_hpcircle')
isManaCircle = g_settings.exists('manaCheckBox') and g_settings.getBoolean('manaCheckBox') or
    not g_settings.getBoolean('healthcircle_mpcircle')
isExpCircle = g_settings.exists('experienceCheckBox') and g_settings.getBoolean('experienceCheckBox') or
    g_settings.getBoolean('healthcircle_expcircle')
isSkillCircle = g_settings.exists('skillCheckBox') and g_settings.getBoolean('skillCheckBox') or
    g_settings.getBoolean('healthcircle_skillcircle')
skillTypes = g_settings.getNode('healthcircle_skilltypes')
skillsLoaded = false

if not skillTypes then
    skillTypes = {}
end

distanceFromCenter = g_settings.getNumber('healthcircle_distfromcenter')
opacityCircle = g_settings.getNumber('healthcircle_opacity', 0.35)

function init()
    g_ui.importStyle("game_healthcircle.otui")
    healthCircle = g_ui.createWidget('HealthCircle', mapPanel)
    manaCircle = g_ui.createWidget('ManaCircle', mapPanel)
    manaShieldCircle = g_ui.createWidget('ManaShieldCircle', mapPanel)
    expCircle = g_ui.createWidget('ExpCircle', mapPanel)
    skillCircle = g_ui.createWidget('SkillCircle', mapPanel)

    healthCircleFront = g_ui.createWidget('HealthCircleFront', mapPanel)
    manaCircleFront = g_ui.createWidget('ManaCircleFront', mapPanel)
    manaShieldCircleFront = g_ui.createWidget('ManaShieldCircleFront', mapPanel)
    expCircleFront = g_ui.createWidget('ExpCircleFront', mapPanel)
    skillCircleFront = g_ui.createWidget('SkillCircleFront', mapPanel)

    imageSizeBroad = healthCircle:getHeight()
    imageSizeThin = healthCircle:getWidth()
    manaShieldImageSizeBroad = manaShieldCircle:getHeight()
    manaShieldImageSizeThin = manaShieldCircle:getWidth()
    manaShieldCircle:setVisible(false)
    manaShieldCircleFront:setVisible(false)

    -- @ MONK
    initMonkWidgets()
    -- @
    whenMapResizeChange()
    initOnHpAndMpChange()
    initOnGeometryChange()
    initOnLoginChange()

    if not isHealthCircle then
        healthCircle:setVisible(false)
        healthCircleFront:setVisible(false)
    end

    if not isManaCircle then
        manaCircle:setVisible(false)
        manaCircleFront:setVisible(false)
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
    end

    if not isExpCircle then
        expCircle:setVisible(false)
        expCircleFront:setVisible(false)
    end

    if not isSkillCircle then
        skillCircle:setVisible(false)
        skillCircleFront:setVisible(false)
    end

    -- Add option window in options module
    addToOptionsModule()

    connect(g_game, {
        onGameStart = setPlayerValues
    })
    if StatusIconBar and StatusIconBar.init then
        StatusIconBar.init()
    end
end

function terminate()
    resetArcAnims()
    if StatusIconBar and StatusIconBar.terminate then
        StatusIconBar.terminate()
    end
    healthCircle:destroy()
    healthCircle = nil
    manaCircle:destroy()
    manaCircle = nil
    manaShieldCircle:destroy()
    manaShieldCircle = nil
    expCircle:destroy()
    expCircle = nil
    skillCircle:destroy()
    skillCircle = nil

    healthCircleFront:destroy()
    healthCircleFront = nil
    manaCircleFront:destroy()
    manaCircleFront = nil
    manaShieldCircleFront:destroy()
    manaShieldCircleFront = nil
    expCircleFront:destroy()
    expCircleFront = nil
    skillCircleFront:destroy()
    skillCircleFront = nil
    -- @ Destroy MONK
    terminateMonkWidgets()
    -- @
    terminateOnHpAndMpChange()
    terminateOnGeometryChange()
    terminateOnLoginChange()

    -- Delete from options module
    destroyOptionsModule()

    disconnect(g_game, {
        onGameStart = setPlayerValues
    })
    statsBarMenuLoaded = false
end

-------------------------------------------------
-- Scripts----------------------------------------
-------------------------------------------------

-- Displayed arc percents (ease-out toward server values).
local arcAnim = {
    health = {},
    mana = {},
    shield = {},
    exp = {},
    skill = {}
}

-- Arcs update at 30 Hz; 60 Hz is indistinguishable for pixel-clipped arcs
-- and doubles the per-frame work during combat.
local ARC_TWEEN_INTERVAL = 33
local ARC_APPLY_EPSILON = 0.2

local function tweenArc(slot, targetPercent, applyFn, wrap, vital, visible)
    targetPercent = math.max(0, math.min(100, targetPercent))

    local animateEnabled = true
    if modules.client_options and modules.client_options.isBarAnimationEnabled then
        animateEnabled = modules.client_options.isBarAnimationEnabled('showAnimationArcs')
    elseif modules.client_options and modules.client_options.getOption then
        animateEnabled = modules.client_options.getOption('showAnimationArcs') ~= false
    end

    if slot.value == nil or not animateEnabled or visible == false then
        g_effects.cancelValue(slot)
        slot.value = targetPercent
        slot.applied = targetPercent
        applyFn(targetPercent)
        return
    end

    local from = slot.value
    local duration = nil
    if vital then
        local delta = math.abs(targetPercent - from)
        local speed = 100
        if modules.client_options and modules.client_options.getOption then
            speed = modules.client_options.getOption('uiBarAnimationSpeed') or 100
        end
        local factor = 100 / math.max(speed, 1)
        duration = math.max(80, math.floor(math.min(1800, math.max(550, 420 + delta * 18)) * factor + 0.5))
    end

    g_effects.animateValue(slot, from, targetPercent, duration, function(v)
        slot.value = v
        -- Skip widget updates that wouldn't move the arc a visible amount;
        -- the final tick (v == target) always applies.
        if v ~= targetPercent and slot.applied and math.abs(v - slot.applied) < ARC_APPLY_EPSILON then
            return
        end
        slot.applied = v
        applyFn(v)
    end, wrap, ARC_TWEEN_INTERVAL)
end

local function resetArcAnims()
    for _, slot in pairs(arcAnim) do
        g_effects.cancelValue(slot)
        slot.value = nil
        slot.applied = nil
    end
end

local function applyHealthArc(healthPercent)
    if not healthCircle or not healthCircleFront then
        return
    end

    local yhppc = math.floor(imageSizeBroad * (1 - (healthPercent / 100)))
    local restYhppc = imageSizeBroad - yhppc

    healthCircleFront:setY(healthCircle:getY() + yhppc)
    healthCircleFront:setHeight(restYhppc)
    healthCircleFront:setImageClip({
        x = 0,
        y = yhppc,
        width = imageSizeThin,
        height = restYhppc
    })

    healthCircle:setHeight(yhppc)
    healthCircle:setImageClip({
        x = 0,
        y = 0,
        width = imageSizeThin,
        height = yhppc
    })

    if healthPercent > 92 then
        healthCircleFront:setImageColor('#00BC00')
    elseif healthPercent > 60 then
        healthCircleFront:setImageColor('#50A150')
    elseif healthPercent > 30 then
        healthCircleFront:setImageColor('#A1A100')
    elseif healthPercent > 8 then
        healthCircleFront:setImageColor('#BF0A0A')
    elseif healthPercent > 3 then
        healthCircleFront:setImageColor('#910F0F')
    else
        healthCircleFront:setImageColor('#850C0C')
    end
end

local function applyManaArc(manaPercent)
    if not manaCircle or not manaCircleFront then
        return
    end

    local ymppc = math.floor(imageSizeBroad * (1 - (manaPercent / 100)))
    local restYmppc = imageSizeBroad - ymppc
    if restYmppc <= 0 then
        manaCircleFront:setVisible(false)
    else
        manaCircleFront:setVisible(isManaCircle)

        if isManaCircle then
            manaCircleFront:setY(manaCircle:getY() + ymppc)
            manaCircleFront:setHeight(restYmppc)
            manaCircleFront:setImageClip({
                x = 0,
                y = ymppc,
                width = imageSizeThin,
                height = restYmppc
            })
        end
    end

    manaCircle:setHeight(ymppc)
    manaCircle:setImageClip({
        x = 0,
        y = 0,
        width = imageSizeThin,
        height = ymppc
    })
end

local function applyShieldArc(shieldPercent)
    if not manaShieldCircle or not manaShieldCircleFront then
        return
    end

    local emptyPixels = math.floor(manaShieldImageSizeBroad * (1 - shieldPercent / 100))
    if emptyPixels < 0 then
        emptyPixels = 0
    end
    if emptyPixels > manaShieldImageSizeBroad then
        emptyPixels = manaShieldImageSizeBroad
    end

    local filledPixels = manaShieldImageSizeBroad - emptyPixels

    manaShieldCircleFront:setY(manaShieldCircle:getY() + emptyPixels)
    manaShieldCircleFront:setHeight(filledPixels)
    manaShieldCircleFront:setImageClip({
        x = 0,
        y = emptyPixels,
        width = manaShieldImageSizeThin,
        height = filledPixels
    })

    manaShieldCircle:setHeight(emptyPixels)
    manaShieldCircle:setImageClip({
        x = 0,
        y = 0,
        width = manaShieldImageSizeThin,
        height = emptyPixels
    })
end

local function applyExpArc(levelPercent)
    if not expCircle or not expCircleFront then
        return
    end

    local Xexpc = math.floor(imageSizeBroad * (1 - levelPercent / 100))

    expCircleFront:setImageClip({
        x = 0,
        y = 0,
        width = imageSizeBroad - Xexpc,
        height = imageSizeThin
    })
    expCircleFront:setWidth(imageSizeBroad - Xexpc)

    expCircle:setImageClip({
        x = imageSizeBroad - Xexpc,
        y = 0,
        width = Xexpc,
        height = imageSizeThin
    })
    expCircle:setWidth(Xexpc)
    expCircle:setX(expCircleFront:getX() + expCircleFront:getWidth())
end

local function applySkillArc(skillPercent, skillColor)
    if not skillCircle or not skillCircleFront then
        return
    end

    local Xskpc = math.floor(imageSizeBroad * (1 - skillPercent / 100))
    if skillColor then
        skillCircleFront:setImageColor(skillColor)
    end

    skillCircleFront:setImageClip({
        x = 0,
        y = 0,
        width = imageSizeBroad - Xskpc,
        height = imageSizeThin
    })
    skillCircleFront:setWidth(imageSizeBroad - Xskpc)

    skillCircle:setImageClip({
        x = imageSizeBroad - Xskpc,
        y = 0,
        width = Xskpc,
        height = imageSizeThin
    })
    skillCircle:setWidth(Xskpc)
    skillCircle:setX(skillCircleFront:getX() + skillCircleFront:getWidth())
end

function initOnHpAndMpChange()
    connect(LocalPlayer, {
        onHealthChange = whenHealthChange,
        onManaChange = whenManaChange,
        onSkillChange = whenSkillsChange,
        onManaShieldChange = whenManaShieldChange,
        onMagicLevelChange = whenSkillsChange,
        onLevelChange = whenSkillsChange,
        -- @ MONK in modules\game_interface\widgets\statsbar.lua
        -- onHarmonyChange = whenMonkHarmonyChange,
        -- onSereneChange = whenMonkSereneChange,
        -- onVocationChange = function() checkMonkVocation() end
        -- @
    })
end

function terminateOnHpAndMpChange()
    disconnect(LocalPlayer, {
        onHealthChange = whenHealthChange,
        onManaChange = whenManaChange,
        onSkillChange = whenSkillsChange,
        onManaShieldChange = whenManaShieldChange,
        onMagicLevelChange = whenSkillsChange,
        onLevelChange = whenSkillsChange,
        -- @ MONK in modules\game_interface\widgets\statsbar.lua
        -- onHarmonyChange = whenMonkHarmonyChange,
        -- onSereneChange = whenMonkSereneChange,
        -- onVocationChange = function() checkMonkVocation() end
        -- @
    })
end

function initOnGeometryChange()
    connect(mapPanel, {
        onGeometryChange = whenMapResizeChange
    })
end

function terminateOnGeometryChange()
    disconnect(mapPanel, {
        onGeometryChange = whenMapResizeChange
    })
end

function initOnLoginChange()
    connect(g_game, {
        onGameStart = whenMapResizeChange
    })
end

function terminateOnLoginChange()
    disconnect(g_game, {
        onGameStart = whenMapResizeChange
    })
end

function whenHealthChange()
    if g_game.isOnline() then
        -- @ MONK
        if isMonkMode then
            whenMonkHealthChange()
            return
        end
        -- @
        local player = g_game.getLocalPlayer()
        if not player then
            return
        end
        local healthPercent = (player:getHealth() / math.max(player:getMaxHealth(), 1)) * 100
        tweenArc(arcAnim.health, healthPercent, applyHealthArc, false, true, isHealthCircle)
    end
end

local defaultManaCircleEmpty = '/data/images/game/healthcircle/right_empty'
local defaultManaCircleFull = '/data/images/game/healthcircle/right_full'
local defaultManaWithManaShieldCircleEmpty = '/data/images/game/healthcircle/right_tiny_empty'
local defaultManaWithManaShieldCircleFull = '/data/images/game/healthcircle/right_tiny_full'
local manaShieldManaCircleEmpty = '/data/images/game/healthcircle/right_extra_empty'
local manaShieldManaCircleFull = '/data/images/game/healthcircle/right_extra_full'

local function resetManaCircleImages()
    if manaCircle then
        manaCircle:setImageSource(defaultManaCircleEmpty)
    end

    if manaCircleFront then
        manaCircleFront:setImageSource(defaultManaCircleFull)
    end
end

local function updateManaShieldDisplay()
    if not manaShieldCircle or not manaShieldCircleFront or not manaCircle or not manaCircleFront then
        return
    end

    if not g_game.isOnline() or not isManaCircle then
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
        resetManaCircleImages()
        g_effects.cancelValue(arcAnim.shield)
        arcAnim.shield.value = nil
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local maxShield = player:getMaxManaShield()
    local remainingShield = player:getManaShield()

    if remainingShield <= 0 then
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
        resetManaCircleImages()
        g_effects.cancelValue(arcAnim.shield)
        arcAnim.shield.value = nil
        return
    end

    if maxShield <= 0 then
        maxShield = remainingShield
    end

    manaCircle:setImageSource(defaultManaWithManaShieldCircleEmpty)
    manaCircleFront:setImageSource(defaultManaWithManaShieldCircleFull)
    manaShieldCircle:setImageSource(manaShieldManaCircleEmpty)
    manaShieldCircleFront:setImageSource(manaShieldManaCircleFull)
    manaShieldCircle:setVisible(true)
    manaShieldCircleFront:setVisible(true)

    local clampedShield = math.max(math.min(remainingShield, maxShield), 0)
    local shieldPercent = (clampedShield / math.max(maxShield, 1)) * 100
    tweenArc(arcAnim.shield, shieldPercent, applyShieldArc, false, true)
end

function whenManaShieldChange()
    updateManaShieldDisplay()
end

function whenManaChange()
    if g_game.isOnline() then
        local player = g_game.getLocalPlayer()
        local maxMana = player:getMaxMana()
        if maxMana <= 0 then
            manaCircle:setVisible(false)
            manaCircleFront:setVisible(false)
            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setVisible(false)
                manaShieldCircleFront:setVisible(false)
            end
            resetManaCircleImages()
            g_effects.cancelValue(arcAnim.mana)
            arcAnim.mana.value = nil
            return
        elseif isManaCircle then
            manaCircle:setVisible(true)
            manaCircleFront:setVisible(true)
        end

        updateManaShieldDisplay()

        local manaPercent = (player:getMana() / maxMana) * 100
        tweenArc(arcAnim.mana, manaPercent, applyManaArc, false, true, isManaCircle)
    end
end

function whenSkillsChange()
    if g_game.isOnline() then
        local player = g_game.getLocalPlayer()
        if not player then
            return
        end

        if isExpCircle then
            tweenArc(arcAnim.exp, player:getLevelPercent(), applyExpArc, true)
        end

        if isSkillCircle then
            local skillPercent
            local skillColor
            local skillType = skillTypes[player:getName()]

            if skillType == 'fist' then
                skillPercent = player:getSkillLevelPercent(0)
                skillColor = '#9900cc'
            elseif skillType == 'club' then
                skillPercent = player:getSkillLevelPercent(1)
                skillColor = '#cc3399'
            elseif skillType == 'sword' then
                skillPercent = player:getSkillLevelPercent(2)
                skillColor = '#FF7F00'
            elseif skillType == 'axe' then
                skillPercent = player:getSkillLevelPercent(3)
                skillColor = '#696969'
            elseif skillType == 'distance' then
                skillPercent = player:getSkillLevelPercent(4)
                skillColor = '#A62A2A'
            elseif skillType == 'shielding' then
                skillPercent = player:getSkillLevelPercent(5)
                skillColor = '#663300'
            elseif skillType == 'fishing' then
                skillPercent = player:getSkillLevelPercent(6)
                skillColor = '#ffff33'
            else
                -- default skill: MAGIC
                skillPercent = player:getMagicLevelPercent()
                skillColor = '#00ffcc'
            end

            tweenArc(arcAnim.skill, skillPercent, function(percent)
                applySkillArc(percent, skillColor)
            end, true)
        end
    end
end

function whenMapResizeChange()
    if g_game.isOnline() then
        local barDistance = 90
        if not (math.floor(mapPanel:getHeight() / 2 * 0.2) < 100) then -- 0.381
            barDistance = math.floor(mapPanel:getHeight() / 2 * 0.2)
        end

        if currentViewMode() == 2 then
            healthCircleFront:setX(math.floor(mapPanel:getWidth() / 2 - barDistance - imageSizeThin) -
                distanceFromCenter)
            manaCircleFront:setX(math.floor(mapPanel:getWidth() / 2 + barDistance) + distanceFromCenter)

            healthCircle:setX(math.floor(mapPanel:getWidth() / 2 - barDistance - imageSizeThin) - distanceFromCenter)
            manaCircle:setX(math.floor((mapPanel:getWidth() / 2 + barDistance)) + distanceFromCenter)

            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setX(manaCircle:getX() - manaShieldImageSizeThin - manaShieldCircleOffsetX)
                manaShieldCircleFront:setX(manaShieldCircle:getX())
            end

            healthCircle:setY(mapPanel:getHeight() / 2 - imageSizeBroad / 2 + 0)
            manaCircle:setY(mapPanel:getHeight() / 2 - imageSizeBroad / 2 + 0)

            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setY(manaCircle:getY() + manaShieldCircleOffsetY)
                manaShieldCircleFront:setY(manaShieldCircle:getY())
            end

            if isExpCircle then
                expCircleFront:setY(math.floor(mapPanel:getHeight() / 2 - barDistance - imageSizeThin) -
                    distanceFromCenter)

                expCircleFront:setX(math.floor(mapPanel:getWidth() / 2 - imageSizeBroad / 2))
                expCircle:setY(math.floor(mapPanel:getHeight() / 2 - barDistance - imageSizeThin) - distanceFromCenter)
            end

            if isSkillCircle then
                skillCircleFront:setY(math.floor(mapPanel:getHeight() / 2 + barDistance) + distanceFromCenter)

                skillCircleFront:setX(math.floor(mapPanel:getWidth() / 2 - imageSizeBroad / 2))
                skillCircle:setY(math.floor(mapPanel:getHeight() / 2 + barDistance) + distanceFromCenter)
            end
        else
            healthCircleFront:setX(mapPanel:getX() + mapPanel:getWidth() / 2 - imageSizeThin - barDistance -
                distanceFromCenter)
            manaCircleFront:setX(mapPanel:getX() + mapPanel:getWidth() / 2 + barDistance + distanceFromCenter)

            healthCircle:setX(mapPanel:getX() + mapPanel:getWidth() / 2 - imageSizeThin - barDistance -
                distanceFromCenter)
            manaCircle:setX(mapPanel:getX() + mapPanel:getWidth() / 2 + barDistance + distanceFromCenter)

            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setX(manaCircle:getX() - manaShieldImageSizeThin - manaShieldCircleOffsetX)
                manaShieldCircleFront:setX(manaShieldCircle:getX())
            end

            healthCircle:setY(mapPanel:getY() + mapPanel:getHeight() / 2 - imageSizeBroad / 2)
            manaCircle:setY(mapPanel:getY() + mapPanel:getHeight() / 2 - imageSizeBroad / 2)

            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setY(manaCircle:getY() + manaShieldCircleOffsetY)
                manaShieldCircleFront:setY(manaShieldCircle:getY())
            end

            if isExpCircle then
                expCircleFront:setY(mapPanel:getY() + mapPanel:getHeight() / 2 - imageSizeThin - barDistance -
                    distanceFromCenter)

                expCircleFront:setX(mapPanel:getX() + mapPanel:getWidth() / 2 - imageSizeBroad / 2)
                expCircle:setY(mapPanel:getY() + mapPanel:getHeight() / 2 - imageSizeThin - barDistance -
                    distanceFromCenter)
            end

            if isSkillCircle then
                skillCircleFront:setY(mapPanel:getY() + mapPanel:getHeight() / 2 + barDistance + distanceFromCenter)

                skillCircleFront:setX(mapPanel:getX() + mapPanel:getWidth() / 2 - imageSizeBroad / 2)
                skillCircle:setY(mapPanel:getY() + mapPanel:getHeight() / 2 + barDistance + distanceFromCenter)
            end
        end

        whenHealthChange()
        whenManaChange()
        if isExpCircle or isSkillCircle then
            whenSkillsChange()
        end
        -- @ MONK
        positionMonkWidgets()
        -- @
    end

    -- Re-apply clip geometry after reposition without restarting tweens mid-flight.
    if arcAnim.health.value ~= nil and not isMonkMode then
        applyHealthArc(arcAnim.health.value)
    end
    if arcAnim.mana.value ~= nil then
        applyManaArc(arcAnim.mana.value)
    end
    if arcAnim.shield.value ~= nil then
        applyShieldArc(arcAnim.shield.value)
    end
    if isExpCircle and arcAnim.exp.value ~= nil then
        applyExpArc(arcAnim.exp.value)
    end
    if isSkillCircle and arcAnim.skill.value ~= nil then
        applySkillArc(arcAnim.skill.value)
    end

    updateManaShieldDisplay()
    if StatusIconBar and StatusIconBar.updatePosition then
        StatusIconBar.updatePosition()
    end
end

-------------------------------------------------
-- Controls---------------------------------------
-------------------------------------------------

function setHealthCircle(value)
    value = toboolean(value)
    isHealthCircle = value
    if value then
        -- @ MONK
        checkMonkVocation()
        if isMonkMode then
            healthCircle:setVisible(false)
            healthCircleFront:setVisible(false)
            setMonkWidgetsVisible(true)
        else
            healthCircle:setVisible(true)
            healthCircleFront:setVisible(true)
        end
        whenMapResizeChange()
        updateManaShieldDisplay()
        -- @
    else
        healthCircle:setVisible(false)
        healthCircleFront:setVisible(false)
        -- @ MONK
        setMonkWidgetsVisible(false)
        -- @
        if manaShieldCircle and manaShieldCircleFront then
            manaShieldCircle:setVisible(false)
            manaShieldCircleFront:setVisible(false)
        end
        resetManaCircleImages()
    end

    g_settings.set('healthcircle_hpcircle', not value)
end

function setManaCircle(value)
    value = toboolean(value)
    isManaCircle = value
    if value then
        manaCircle:setVisible(true)
        manaCircleFront:setVisible(true)
        whenMapResizeChange()
    else
        manaCircle:setVisible(false)
        manaCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_mpcircle', not value)
end

function setExpCircle(value)
    value = toboolean(value)
    isExpCircle = value

    if value then
        expCircle:setVisible(true)
        expCircleFront:setVisible(true)
        whenMapResizeChange()
    else
        expCircle:setVisible(false)
        expCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_expcircle', value)
end

function setSkillCircle(value)
    value = toboolean(value)
    isSkillCircle = value

    if value then
        skillCircle:setVisible(true)
        skillCircleFront:setVisible(true)
        whenMapResizeChange()
    else
        skillCircle:setVisible(false)
        skillCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_skillcircle', value)
end

function setSkillType(skill)
    if not skillsLoaded then
        return
    end

    local char = g_game.getCharacterName()
    local skillType = skillTypes[char]

    skillTypes[char] = skill
    whenMapResizeChange()
    g_settings.setNode('healthcircle_skilltypes', skillTypes)
end

function setDistanceFromCenter(value)
    distanceFromCenter = value
    whenMapResizeChange()

    g_settings.set('healthcircle_distfromcenter', value)
end

function setCircleOpacity(value)
    healthCircle:setOpacity(value)
    healthCircleFront:setOpacity(value)
    manaCircle:setOpacity(value)
    manaCircleFront:setOpacity(value)
    if manaShieldCircle then
        manaShieldCircle:setOpacity(value)
    end
    if manaShieldCircleFront then
        manaShieldCircleFront:setOpacity(value)
    end
    expCircle:setOpacity(value)
    expCircleFront:setOpacity(value)
    skillCircle:setOpacity(value)
    skillCircleFront:setOpacity(value)
    -- @ MONK
    setMonkCircleOpacity(value)
    -- @
    g_settings.set('healthcircle_opacity', value)
end

-------------------------------------------------
-- Option Settings--------------------------------
-------------------------------------------------

optionPanel = nil
healthCheckBox = nil
manaCheckBox = nil
experienceCheckBox = nil
skillCheckBox = nil
chooseSkillComboBox = nil
chooseStatsBarDimension = nil
chooseStatsBarPlacement = nil
distFromCenScrollbar = nil
opacityScrollbar = nil
sizeBox = nil

local arcStyleConfigs = {
    [0] = { prefix = "" },
    [1] = { prefix = "" },
    [2] = { prefix = "" }
}

local function normalizeArcStyle(value)
    value = tonumber(value) or 1
    value = math.floor(value)
    if not arcStyleConfigs[value] then
        return 1
    end
    return value
end

local function getInitialArcStyle()
    local sizeBoxValue = tonumber(g_settings.getNumber('sizeBox')) or 0
    if sizeBoxValue >= 1 and sizeBoxValue <= 3 then
        return normalizeArcStyle(sizeBoxValue - 1)
    end
    return normalizeArcStyle(g_settings.getNumber('healthcircle_style'))
end

local currentArcStyle = getInitialArcStyle()

local function getArcStyleConfig(style)
    return arcStyleConfigs[normalizeArcStyle(style or currentArcStyle)]
end

local function getArcImagePath(name, state, style)
    local config = getArcStyleConfig(style)
    return "/data/images/game/healthcircle/" .. config.prefix .. name .. "_" .. state
end

local function setArcImage(widget, name, state, style)
    if widget then
        widget:setImageSource(getArcImagePath(name, state, style))
    end
end

local function getHudOptionPanel()
    if modules.client_options and modules.client_options.panels then
        return modules.client_options.panels.interfaceHUD
    end
    return nil
end

function handleShowArc(value)
    value = toboolean(value)

    if value then
        isHealthCircle = true
        isManaCircle = true
        if healthCheckBox then healthCheckBox:setChecked(true) end
        if manaCheckBox then manaCheckBox:setChecked(true) end
        g_settings.set('healthcircle_hpcircle', false)
        g_settings.set('healthcircle_mpcircle', false)
        setHealthCircle(true)
        setManaCircle(true)
    else
        setHealthCircle(false)
        setManaCircle(false)
    end
end

function setArcStyle(value)
    currentArcStyle = normalizeArcStyle(value)

    setArcImage(healthCircle, "left", "empty")
    setArcImage(healthCircleFront, "left", "full")
    setArcImage(manaCircle, "right", "empty")
    setArcImage(manaCircleFront, "right", "full")
    setArcImage(manaShieldCircle, "right_extra", "empty")
    setArcImage(manaShieldCircleFront, "right_extra", "full")
    setArcImage(expCircle, "top", "empty")
    setArcImage(expCircleFront, "top", "full")
    setArcImage(skillCircle, "bottom", "empty")
    setArcImage(skillCircleFront, "bottom", "full")

    imageSizeBroad = healthCircle and healthCircle:getHeight() or 0
    imageSizeThin = healthCircle and healthCircle:getWidth() or 0
    whenMapResizeChange()
    if StatusIconBar and type(StatusIconBar.updatePosition) == 'function' then
        StatusIconBar.updatePosition()
    end
    g_settings.set('healthcircle_style', currentArcStyle)
end

function addToOptionsModule()
    optionPanel = getHudOptionPanel()
    if not optionPanel then
        return
    end

    healthCheckBox = optionPanel:recursiveGetChildById('healthCheckBox')
    manaCheckBox = optionPanel:recursiveGetChildById('manaCheckBox')
    experienceCheckBox = optionPanel:recursiveGetChildById('experienceCheckBox')
    skillCheckBox = optionPanel:recursiveGetChildById('skillCheckBox')
    chooseSkillComboBox = optionPanel:recursiveGetChildById('chooseSkillComboBox')
    chooseStatsBarDimension = optionPanel:recursiveGetChildById('chooseStatsBarDimension')
    chooseStatsBarPlacement = optionPanel:recursiveGetChildById('chooseStatsBarPlacement')
    distFromCenScrollbar = optionPanel:recursiveGetChildById('distFromCenScrollbar')
    opacityScrollbar = optionPanel:recursiveGetChildById('opacityScrollbar')
    sizeBox = optionPanel:recursiveGetChildById('sizeBox')

    if chooseSkillComboBox and #(chooseSkillComboBox.options or {}) == 0 then
        chooseSkillComboBox:addOption('Magic Level', 'magic')
        chooseSkillComboBox:addOption('Fist Fighting', 'fist')
        chooseSkillComboBox:addOption('Club Fighting', 'club')
        chooseSkillComboBox:addOption('Sword Fighting', 'sword')
        chooseSkillComboBox:addOption('Axe Fighting', 'axe')
        chooseSkillComboBox:addOption('Distance Fighting', 'distance')
        chooseSkillComboBox:addOption('Shielding', 'shielding')
        chooseSkillComboBox:addOption('Fishing', 'fishing')
    end

    if chooseStatsBarPlacement and #(chooseStatsBarPlacement.options or {}) == 0 then
        chooseStatsBarPlacement:addOption(tr('Top'), 'top')
        chooseStatsBarPlacement:addOption(tr('Bottom'), 'bottom')
    end

    if chooseStatsBarDimension and #(chooseStatsBarDimension.options or {}) == 0 then
        chooseStatsBarDimension:addOption(tr('Hide'), 'hide')
        chooseStatsBarDimension:addOption(tr('Compact'), 'compact')
        chooseStatsBarDimension:addOption(tr('Default'), 'default')
        chooseStatsBarDimension:addOption(tr('Large'), 'large')
        chooseStatsBarDimension:addOption(tr('Parallel'), 'parallel')
    end

    statsBarMenuLoaded = true

    if chooseStatsBarDimension then
        chooseStatsBarDimension:setCurrentOptionByData(g_settings.getString('statsbar_dimension'), true)
    end
    if chooseStatsBarPlacement then
        chooseStatsBarPlacement:setCurrentOptionByData(g_settings.getString('statsbar_placement'), true)
    end

    skillsLoaded = true

    if sizeBox and #(sizeBox.options or {}) == 0 then
        sizeBox:addOption(tr('Small Size'), 1)
        sizeBox:addOption(tr('Default Size'), 2)
        sizeBox:addOption(tr('Large Size'), 3)
    end
    if sizeBox then
        local idx = g_settings.getNumber('sizeBox')
        if idx < 1 or idx > 3 then
            idx = currentArcStyle + 1
        end
        sizeBox:setCurrentIndex(idx)
    end

    setArcStyle(currentArcStyle)
end

function updateStatsBar()
    if statsBarMenuLoaded and chooseStatsBarDimension and chooseStatsBarPlacement then
        modules.game_interface.updateStatsBar(chooseStatsBarDimension:getCurrentOption().data,
            chooseStatsBarPlacement:getCurrentOption().data)
    end
end

function setPlayerValues()
    resetArcAnims()
    if monkHealthAnim then
        g_effects.cancelValue(monkHealthAnim)
        monkHealthAnim.value = nil
    end
    local skillType = skillTypes[g_game.getCharacterName()]
    if not skillType then
        skillType = 'magic'
    end
    if chooseSkillComboBox then
        chooseSkillComboBox:setCurrentOptionByData(skillType, true)
    end
end

function setStatsBarOption(dimension, placement)
    if not chooseStatsBarDimension or not chooseStatsBarPlacement then
        optionPanel = getHudOptionPanel()
        if optionPanel then
            chooseStatsBarDimension = optionPanel:recursiveGetChildById('chooseStatsBarDimension')
            chooseStatsBarPlacement = optionPanel:recursiveGetChildById('chooseStatsBarPlacement')
        end
    end

    if not chooseStatsBarDimension or not chooseStatsBarPlacement then
        return
    end

    if not dimension or dimension == "" then
        dimension = g_settings.getString('statsbar_dimension')
        if dimension == "" then
            dimension = "compact"
        end
    end

    if not placement or placement == "" then
        placement = g_settings.getString('statsbar_placement')
        if placement == "" then
            placement = "top"
        end
    end

    chooseStatsBarDimension:setCurrentOptionByData(dimension, true)
    chooseStatsBarPlacement:setCurrentOptionByData(placement, true)
end

function destroyOptionsModule()
    healthCheckBox = nil
    manaCheckBox = nil
    experienceCheckBox = nil
    skillCheckBox = nil
    chooseSkillComboBox = nil
    distFromCenScrollbar = nil
    opacityScrollbar = nil
    chooseStatsBarDimension = nil
    chooseStatsBarPlacement = nil
    sizeBox = nil
    optionPanel = nil
end
