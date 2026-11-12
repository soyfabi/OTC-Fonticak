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

#include "luavaluecasts_client.h"
#include "uiminimap.h"

#include "game.h"
#include "gameconfig.h"
#include "localplayer.h"
#include "minimap.h"
#include "satellitemap.h"
#include "uimapanchorlayout.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/otml/otmlnode.h"
#include "framework/ui/uilayout.h"
#include <cmath>

UIMinimap::~UIMinimap()
{
    if (m_hdMode)
        g_minimap.removeHdView();
}

void UIMinimap::drawSelf(const DrawPoolType drawPane)
{
    UIWidget::drawSelf(drawPane);
    if (drawPane != DrawPoolType::FOREGROUND)
        return;

    if (!m_layout)
        m_layout = std::make_shared<UIMapAnchorLayout>(static_self_cast<UIWidget>());

    const auto offset = getProjectionOffset();
    if (m_satelliteMode && g_satelliteMap.hasChunksForView(m_cameraPosition.z))
        g_satelliteMap.draw(getPaddingRect(), m_cameraPosition, m_scale, m_floorSeparatorOpacity, offset);
    else if (m_hdMode) {
        if (!m_hdCache)
            m_hdCache = std::make_shared<MinimapHdCache>();
        g_minimap.drawHd(getPaddingRect(), m_cameraPosition, m_scale, m_color, m_hdLive, offset, m_zoomAnimating,
                         m_hdAnimations, m_showFloorItems, *m_hdCache);
    } else
        g_minimap.draw(getPaddingRect(), m_cameraPosition, m_scale, m_color, offset);
}

void UIMinimap::setSmoothWalk(bool enabled)
{
    if (enabled == m_smoothWalk)
        return;

    m_smoothWalk = enabled;
    g_minimap.setWalkView(static_self_cast<UIMinimap>(), enabled);
    updateWalkOffset();
}

void UIMinimap::updateWalkOffset()
{
    Point offset;
    PointF remainder;
    if (m_smoothWalk && isVisible() && !isDragging()) {
        const auto& player = g_game.getLocalPlayer();
        const int spriteSize = g_gameConfig.getSpriteSize();
        if (player && player->getPosition() == m_cameraPosition && spriteSize > 0) {
            const auto walk = player->getWalkOffset();
            const float scale = m_scale / spriteSize;
            const PointF screenOffset(-walk.x * scale, -walk.y * scale);
            offset = Point(std::lround(screenOffset.x), std::lround(screenOffset.y));
            if (m_hdMode || m_satelliteMode) {
                // Keep terrain moving between screen pixels at low zoom.
                remainder = PointF(screenOffset.x - offset.x, screenOffset.y - offset.y);
            }
        }
    }

    if (offset == m_walkOffset && remainder == m_walkRemainder)
        return;

    const bool anchorsMoved = offset != m_walkOffset;
    m_walkOffset = offset;
    m_walkRemainder = remainder;
    if (anchorsMoved && m_layout)
        m_layout->update();
    repaint();
}

void UIMinimap::setHdMode(bool enabled, bool live)
{
    if (m_hdMode == enabled && m_hdLive == live)
        return;

    if (m_hdMode != enabled) {
        m_hdMode = enabled;
        if (enabled)
            g_minimap.addHdView();
        else
            g_minimap.removeHdView();
    }
    m_hdLive = live;
    updateWalkOffset();
    repaint();
}

void UIMinimap::setHdAnimations(bool enabled)
{
    if (m_hdAnimations == enabled)
        return;

    m_hdAnimations = enabled;
    repaint();
}

void UIMinimap::setShowFloorItems(bool enabled)
{
    if (m_showFloorItems == enabled)
        return;

    m_showFloorItems = enabled;
    repaint();
}

void UIMinimap::setScale(float scale)
{
    scale = std::max(scale, 0.01f);
    if (scale == m_scale)
        return;

    m_scale = scale;
    updateWalkOffset();
    if (m_layout)
        m_layout->update();
    repaint();
}

bool UIMinimap::setZoom(const int8_t zoom)
{
    if (zoom == m_zoom)
        return true;

    if (zoom < m_minZoom || zoom > m_maxZoom)
        return false;

    const int oldZoom = m_zoom;
    m_zoom = zoom;

    setScale(std::ldexp(1.f, zoom));

    onZoomChange(zoom, oldZoom);
    return true;
}

void UIMinimap::setZoomAnimating(bool animating)
{
    if (m_zoomAnimating != animating) {
        m_zoomAnimating = animating;
        repaint();
    }
}

PointF UIMinimap::getProjectionOffset() const
{
    return PointF(m_walkOffset.x, m_walkOffset.y) + m_walkRemainder - m_cameraFraction * m_scale;
}

void UIMinimap::panByPixels(int dx, int dy)
{
    if (!m_cameraPosition.isMapPosition())
        return;

    constexpr double lastTile = 65534.0;
    const double x = std::clamp(m_cameraPosition.x + double(m_cameraFraction.x) - dx / double(m_scale), 0.0, lastTile);
    const double y = std::clamp(m_cameraPosition.y + double(m_cameraFraction.y) - dy / double(m_scale), 0.0, lastTile);
    const int tileX = std::lround(x);
    const int tileY = std::lround(y);
    applyCameraPosition(Position(tileX, tileY, m_cameraPosition.z), PointF(x - tileX, y - tileY));
}

void UIMinimap::setCameraPosition(const Position& pos)
{
    applyCameraPosition(pos, {});
}

void UIMinimap::applyCameraPosition(const Position& pos, const PointF& fraction)
{
    if (m_cameraPosition == pos && m_cameraFraction == fraction)
        return;

    const Position oldPos = m_cameraPosition;
    m_cameraPosition = pos;
    m_cameraFraction = fraction;

    updateWalkOffset();
    repaint();
    if (m_layout)
        m_layout->update();

    if (pos != oldPos)
        onCameraPositionChange(pos, oldPos);
}

bool UIMinimap::floorUp()
{
    Position pos = m_cameraPosition;
    if (!pos.up())
        return false;

    setCameraPosition(pos);
    return true;
}

bool UIMinimap::floorDown()
{
    Position pos = m_cameraPosition;
    if (!pos.down())
        return false;
    setCameraPosition(pos);
    return true;
}

Point UIMinimap::getTilePoint(const Position& pos)
{
    return g_minimap.getTilePoint(pos, getPaddingRect(), m_cameraPosition, m_scale, getProjectionOffset());
}

Rect UIMinimap::getTileRect(const Position& pos)
{
    return g_minimap.getTileRect(pos, getPaddingRect(), m_cameraPosition, m_scale, getProjectionOffset() - m_walkRemainder);
}

Position UIMinimap::getTilePosition(const Point& mousePos)
{
    return g_minimap.getTilePosition(mousePos, getPaddingRect(), m_cameraPosition, m_scale, getProjectionOffset());
}

void UIMinimap::anchorPosition(const UIWidgetPtr& anchoredWidget, const Fw::AnchorEdge anchoredEdge, const Position& hookedPosition, const Fw::AnchorEdge hookedEdge)
{
    if (!m_layout)
        return;

    const auto& layout = m_layout->static_self_cast<UIMapAnchorLayout>();
    assert(layout);
    layout->addPositionAnchor(anchoredWidget, anchoredEdge, hookedPosition, hookedEdge);
}

void UIMinimap::fillPosition(const UIWidgetPtr& anchoredWidget, const Position& hookedPosition)
{
    if (!m_layout)
        return;

    const auto& layout = m_layout->static_self_cast<UIMapAnchorLayout>();
    assert(layout);
    layout->fillPosition(anchoredWidget, hookedPosition);
}

void UIMinimap::centerInPosition(const UIWidgetPtr& anchoredWidget, const Position& hookedPosition)
{
    if (!m_layout)
        return;

    const auto& layout = m_layout->static_self_cast<UIMapAnchorLayout>();
    assert(layout);
    layout->centerInPosition(anchoredWidget, hookedPosition);
}

void UIMinimap::onZoomChange(const int zoom, const int oldZoom) { callLuaField("onZoomChange", zoom, oldZoom); }

void UIMinimap::onCameraPositionChange(const Position& position, const Position& oldPosition) { callLuaField("onCameraPositionChange", position, oldPosition); }

void UIMinimap::onStyleApply(const std::string_view styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);
    for (const auto& node : styleNode->children()) {
        if (node->tag() == "zoom")
            setZoom(node->value<int>());
        else if (node->tag() == "max-zoom")
            setMaxZoom(node->value<int>());
        else if (node->tag() == "min-zoom")
            setMinZoom(node->value<int>());
    }
}
