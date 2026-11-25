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
#include "framework/graphics/coordsbuffer.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/graphics/image.h"
#include "framework/graphics/texture.h"
#include "framework/otml/otmlnode.h"
#include "framework/ui/uilayout.h"
#include <cmath>

namespace {
    constexpr int routeMaskSize = 32;

    TexturePtr makeRouteMask(bool round)
    {
        auto image = std::make_shared<Image>(Size(routeMaskSize, routeMaskSize));
        for (int y = 0; y < routeMaskSize; ++y) {
            const float vertical = y * 2.f / (routeMaskSize - 1) - 1.f;
            for (int x = 0; x < routeMaskSize; ++x) {
                const float horizontal = x * 2.f / (routeMaskSize - 1) - 1.f;
                const float distance = round ? std::hypot(horizontal, vertical) : std::abs(vertical);
                const float edge = std::clamp((1.f - distance) * 2.f, 0.f, 1.f);
                const float coverage = edge * edge * (3.f - 2.f * edge);
                const float fade = round ? 1.f : float(x) / (routeMaskSize - 1);
                image->setPixel(x, y, Color(1.f, 1.f, 1.f, coverage * fade));
            }
        }
        auto texture = std::make_shared<Texture>(image);
        texture->setSmooth(true);
        return texture;
    }
}

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

    if (m_fogOfWar && g_game.isOnline())
        g_minimap.drawFog(getPaddingRect(), m_cameraPosition, m_scale, offset);

    drawAutoWalkRoute(getPaddingRect(), offset);
}

void UIMinimap::drawAutoWalkRoute(const Rect& viewport, const PointF& offset)
{
    const auto& player = g_game.getLocalPlayer();
    if (!m_showAutoWalkRoute || !g_game.isOnline() || !player || player->getAutoWalkRoute().empty())
        return;

    const Position playerPosition = player->getPosition();
    if (playerPosition.z != m_cameraPosition.z)
        return;

    const auto oldClip = g_drawPool.getClipRect();
    const auto clip = oldClip.isValid() ? viewport.intersection(oldClip) : viewport;
    if (clip.isEmpty())
        return;

    const MinimapProjection projection(viewport, m_cameraPosition, m_scale, offset);
    const Point playerTile(playerPosition.x, playerPosition.y);
    const Point playerTileCenter = projection.tileCenter(playerTile);
    Point start = playerTileCenter;
    if (m_smoothWalk && !isDragging() && playerPosition == m_cameraPosition) {
        const PointF walkOffset = PointF(m_walkOffset.x, m_walkOffset.y) + m_walkRemainder;
        start = MinimapProjection(viewport, m_cameraPosition, m_scale, offset - walkOffset).tileCenter(playerTile);
    }

    std::vector<Point> points{ start };
    const auto& route = player->getAutoWalkRoute();
    points.reserve(route.size() + 2);
    if (playerTileCenter != start)
        points.push_back(playerTileCenter);
    for (const auto& tile : route) {
        const auto point = projection.tileCenter(Point(tile.x, tile.y));
        if (point != points.back())
            points.push_back(point);
    }
    if (points.size() < 2)
        return;

    constexpr float fadePixels = 18.f;
    float fadeLength = 0.f;
    for (size_t i = 1; i < points.size() && fadeLength < fadePixels; ++i) {
        const Point delta = points[i] - points[i - 1];
        fadeLength += std::hypot(float(delta.x), float(delta.y));
    }
    fadeLength = std::min(fadeLength, fadePixels);

    if (!m_routeStrokeMask) {
        m_routeStrokeMask = makeRouteMask(false);
        m_routeJoinMask = makeRouteMask(true);
    }

    g_drawPool.setClipRect(clip);
    constexpr float radius = 2.5f;
    constexpr float maskStart = .5f;
    constexpr float maskEnd = routeMaskSize - .5f;
    auto stroke = std::make_shared<CoordsBuffer>();
    auto joins = std::make_shared<CoordsBuffer>();
    const RectF joinSource(maskStart, maskStart, maskEnd - maskStart, maskEnd - maskStart);
    const auto addJoin = [&](const Point& center, const float opacity) {
        joins->clear();
        joins->addRect(RectF(center.x - radius, center.y - radius, radius * 2, radius * 2), joinSource);
        g_drawPool.addTexturedCoordsBuffer(m_routeJoinMask, joins, Color(m_autoWalkRouteColor, opacity));
    };
    float distance = 0.f;
    Point previousDelta;
    for (size_t i = 1; i < points.size(); ++i) {
        const Point& from = points[i - 1];
        const Point& to = points[i];
        const Point delta = to - from;
        const PointF startPoint(from.x, from.y);
        const PointF endPoint(to.x, to.y);
        const PointF direction = endPoint - startPoint;
        const float length = direction.length();
        const PointF normal = PointF(-direction.y, direction.x) * (radius / length);
        const auto addSegment = [&](const PointF& a, const PointF& b, const float startOpacity, const float endOpacity) {
            const float u0 = std::lerp(maskStart, maskEnd, startOpacity);
            const float u1 = std::lerp(maskStart, maskEnd, endOpacity);
            const PointF uvA(u0, maskStart), uvB(u0, maskEnd), uvC(u1, maskStart), uvD(u1, maskEnd);
            stroke->addTexturedTriangle(a + normal, a - normal, b + normal, uvA, uvB, uvC);
            stroke->addTexturedTriangle(b + normal, a - normal, b - normal, uvC, uvB, uvD);
        };

        const float opacity = std::min(distance / fadeLength, 1.f);
        if (i > 1 && previousDelta.x * delta.y != previousDelta.y * delta.x)
            addJoin(from, opacity);

        if (distance < fadeLength && distance + length > fadeLength) {
            const PointF fadeEnd = startPoint + direction * ((fadeLength - distance) / length);
            addSegment(startPoint, fadeEnd, opacity, 1.f);
            addSegment(fadeEnd, endPoint, 1.f, 1.f);
        } else {
            addSegment(startPoint, endPoint, opacity, std::min((distance + length) / fadeLength, 1.f));
        }
        distance += length;
        previousDelta = delta;
    }
    addJoin(points.back(), 1.f);
    g_drawPool.addTexturedCoordsBuffer(m_routeStrokeMask, stroke, m_autoWalkRouteColor);
    g_drawPool.setClipRect(oldClip);
}

void UIMinimap::setAutoWalkRouteStyle(bool visible, const Color& color)
{
    if (m_showAutoWalkRoute == visible && m_autoWalkRouteColor == color)
        return;
    m_showAutoWalkRoute = visible;
    m_autoWalkRouteColor = color;
    repaint();
}

void UIMinimap::setFogOfWar(bool enabled)
{
    if (m_fogOfWar == enabled)
        return;
    m_fogOfWar = enabled;
    repaint();
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
        else {
            m_hdCache.reset();
            g_minimap.removeHdView();
        }
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
        else if (node->tag() == "fog-of-war")
            setFogOfWar(node->value<bool>());
    }
}
