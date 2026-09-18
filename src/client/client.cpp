/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "client.h"

#include "game.h"
#include "gameconfig.h"
#include "localplayer.h"
#include "map.h"
#include "mapview.h"
#include "minimap.h"
#include "spriteappearances.h"
#include "spritemanager.h"
#include "thingtypemanager.h"
#include "uimap.h"
#include "framework/core/eventdispatcher.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/graphics/shadermanager.h"
#include "framework/ui/uimanager.h"
#ifdef FRAMEWORK_EDITOR
#include "creatures.h"
#endif
#include "paperdollmanager.h"

namespace
{
    UIMapPtr findHudLivePreviewMap()
    {
        const auto& root = g_ui.getRootWidget();
        if (!root)
            return nullptr;

        const auto& widget = root->recursiveGetChildById("hudLivePreviewMap");
        if (!widget || widget->isDestroyed() || !widget->isVisible())
            return nullptr;

        return widget->static_self_cast<UIMap>();
    }

    void drawMapWidget(const UIMapPtr& map, const DrawPoolType type)
    {
        if (!map || map->isDestroyed() || !map->isVisible())
            return;

        map->updateMapRect();

        if (type == DrawPoolType::FOREGROUND_MAP)
            map->draw(DrawPoolType::CREATURE_INFORMATION);

        map->draw(type);
    }

    bool shouldForceMapRepaint()
    {
        return findHudLivePreviewMap() != nullptr;
    }

    void forceRepaintMapLayers()
    {
        g_drawPool.repaint(DrawPoolType::MAP);
        g_drawPool.repaint(DrawPoolType::CREATURE_INFORMATION);
        g_drawPool.repaint(DrawPoolType::FOREGROUND_MAP);
        g_drawPool.repaint(DrawPoolType::LIGHT);
    }
}

Client g_client;

void Client::init(std::vector<std::string>& /*args*/)
{
    // register needed lua functions
    registerLuaFunctions();

    g_gameConfig.init();
    g_map.init();
    g_minimap.init();
    g_game.init();
    g_shaders.init();
    g_sprites.init();
    g_spriteAppearances.init();
    g_things.init();
}

void Client::terminate()
{
    m_mapWidget = nullptr;

#ifdef FRAMEWORK_EDITOR
    g_creatures.terminate();
#endif
    g_game.terminate();
    g_map.terminate();
    g_minimap.terminate();
    g_things.terminate();
    g_sprites.terminate();
    g_spriteAppearances.terminate();
    g_shaders.terminate();
    g_paperdolls.clear();
    g_gameConfig.terminate();
}

void Client::preLoad() {
    if (m_mapWidget) {
        if (m_mapWidget->isDestroyed())
            m_mapWidget = nullptr;
        else {
            m_mapWidget->updateMapRect();
            m_mapWidget->getMapView()->preLoad();
        }
    }

    if (const auto& previewMap = findHudLivePreviewMap()) {
        previewMap->updateMapRect();
        if (const auto& player = g_game.getLocalPlayer()) {
            const auto& playerCreature = std::static_pointer_cast<Creature>(player);
            if (previewMap->getFollowingCreature() != playerCreature)
                previewMap->followCreature(playerCreature);
        }
        previewMap->getMapView()->preLoad();
    }
}

void Client::draw(const DrawPoolType type)
{
    if (type == DrawPoolType::FOREGROUND) {
        g_ui.render(DrawPoolType::FOREGROUND);
        if (!g_game.isOnline())
            m_mapWidget = nullptr;
        return;
    }

    if (!g_game.isOnline()) {
        m_mapWidget = nullptr;
        return;
    }

    if (m_mapWidget && m_mapWidget->isDestroyed())
        m_mapWidget = nullptr;
    if (type == DrawPoolType::MAP && !m_mapWidget)
        m_mapWidget = g_ui.getRootWidget()->recursiveGetChildById("gameMapPanel")->static_self_cast<UIMap>();

    const auto previewMap = findHudLivePreviewMap();
    if (!m_mapWidget && !previewMap)
        return;

    if (type == DrawPoolType::FOREGROUND_MAP) {
        g_textDispatcher.poll();
    }

    drawMapWidget(m_mapWidget, type);
    drawMapWidget(previewMap, type);
}

bool Client::canDraw(const DrawPoolType type) const
{
    switch (type) {
        case DrawPoolType::MAP:
            if (g_game.isOnline() && shouldForceMapRepaint())
                forceRepaintMapLayers();
            return g_game.isOnline();

        case DrawPoolType::FOREGROUND: {
            // FOREGROUND is intentionally capped (~10 FPS) to save CPU, but while
            // dragging windows that makes the UI feel like ~5-10 FPS. Force a
            // refresh so drag follows the mouse at the display refresh rate.
            const auto pool = g_drawPool.get(type);
            if (g_ui.getDraggingWidget())
                pool->repaint();
            return pool->canRepaint();
        }

        case DrawPoolType::CREATURE_INFORMATION:
        case DrawPoolType::FOREGROUND_MAP:
            if (g_game.isOnline() && shouldForceMapRepaint())
                forceRepaintMapLayers();
            return g_game.isOnline() && g_drawPool.get(type)->canRepaint();

        case DrawPoolType::LIGHT: {
            const auto previewMap = findHudLivePreviewMap();
            if (g_game.isOnline() && shouldForceMapRepaint())
                forceRepaintMapLayers();
            return g_game.isOnline() && (
                (m_mapWidget && m_mapWidget->isDrawingLights()) ||
                (previewMap && previewMap->isDrawingLights())
            );
        }

        default:
            return false;
    }
}

bool Client::isLoadingAsyncTexture()
{
    return g_game.isUsingProtobuf();
}

bool Client::isUsingProtobuf()
{
    return g_game.isUsingProtobuf();
}

void Client::onLoadingAsyncTextureChanged(bool /*loadingAsync*/)
{
    g_sprites.reload();
}

void Client::doMapScreenshot(std::string file)
{
    if (!m_mapWidget)
        return;

    if (file.empty()) {
        file = "screenshot_map.png";
    }

    g_drawPool.get(DrawPoolType::MAP)->getFrameBuffer()->doScreenshot(file, g_gameConfig.getSpriteSize() * 3, g_gameConfig.getSpriteSize() * 3);
}

float Client::getSpellEffectAlpha(const Otc::MagicEffectSources source) const
{
    switch (source) {
        case Otc::ME_SOURCE_OTHER_PLAYER:
            return m_otherPlayerSpellEffectAlpha;
        case Otc::ME_SOURCE_MONSTER:
            return m_creatureSpellEffectAlpha;
        case Otc::ME_SOURCE_BOSS:
            return m_bossAreaCreatureEffectAlpha;
        case Otc::ME_SOURCE_OWN:
        case Otc::ME_SOURCE_DEFAULT:
        default:
            return m_ownSpellEffectAlpha;
    }
}