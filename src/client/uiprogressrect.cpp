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

#include "uiprogressrect.h"

#include "framework/graphics/drawpoolmanager.h"
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>

#include "framework/otml/otmlnode.h"

#include <algorithm>
#include <cmath>

namespace
{
    constexpr int PROGRESS_UPDATE_CLASSIC_MS = 100;
    constexpr int PROGRESS_UPDATE_FRAME_MS = 33;
    constexpr int FINISH_FLASH_MS = 220;

    constexpr Color FRAME_GLOW(255, 180, 40, 90);
    constexpr Color FRAME_LINE(255, 210, 64, 230);
    constexpr Color FRAME_BRIGHT(255, 240, 140, 255);
    constexpr Color SPARK_CORE(255, 250, 200, 255);
    constexpr Color SPARK_TRAIL(255, 200, 60, 160);
}

UIProgressRect::~UIProgressRect()
{
    stop();
}

Point UIProgressRect::diagonalPoint(const Rect& rect, float progress)
{
    progress = std::clamp(progress, 0.f, 1.f);
    const Point from = rect.topLeft();
    const Point to = rect.bottomRight();
    return Point(
        from.x + static_cast<int>(std::round((to.x - from.x) * progress)),
        from.y + static_cast<int>(std::round((to.y - from.y) * progress))
    );
}

void UIProgressRect::drawDiagonalDarkReveal(const Rect& drawRect, float progress) const
{
    // Icon starts fully dark; clear zone grows from top-left toward bottom-right
    // behind a "/" frontier (x + y = threshold).
    if (progress >= 0.999f)
        return;

    const Color& dark = m_backgroundColor;
    if (progress <= 0.001f) {
        g_drawPool.addFilledRect(drawRect, dark);
        return;
    }

    const int L = drawRect.left();
    const int T = drawRect.top();
    const int R = drawRect.right();
    const int B = drawRect.bottom();
    const float s = static_cast<float>(L + T) + progress * static_cast<float>((R - L) + (B - T));

    const Point tr = drawRect.topRight();
    const Point br = drawRect.bottomRight();
    const Point bl = drawRect.bottomLeft();

    // Early: frontier cuts top + left. Most of the icon stays dark.
    if (s <= static_cast<float>(R + T) && s <= static_cast<float>(L + B)) {
        const Point iTop(static_cast<int>(std::lround(s - T)), T);
        const Point iLeft(L, static_cast<int>(std::lround(s - L)));
        g_drawPool.addFilledTriangle(iTop, tr, br, dark);
        g_drawPool.addFilledTriangle(iTop, br, bl, dark);
        g_drawPool.addFilledTriangle(iTop, bl, iLeft, dark);
        return;
    }

    // Mid (non-square): top+bottom or left+right.
    if (s <= static_cast<float>(R + T)) {
        const Point iTop(static_cast<int>(std::lround(s - T)), T);
        const Point iBottom(static_cast<int>(std::lround(s - B)), B);
        g_drawPool.addFilledTriangle(iTop, tr, br, dark);
        g_drawPool.addFilledTriangle(iTop, br, iBottom, dark);
        return;
    }
    if (s <= static_cast<float>(L + B)) {
        const Point iLeft(L, static_cast<int>(std::lround(s - L)));
        const Point iRight(R, static_cast<int>(std::lround(s - R)));
        g_drawPool.addFilledTriangle(iRight, br, bl, dark);
        g_drawPool.addFilledTriangle(iRight, bl, iLeft, dark);
        return;
    }

    // Late: only the bottom-right corner remains dark.
    if (s < static_cast<float>(R + B)) {
        const Point iRight(R, static_cast<int>(std::lround(s - R)));
        const Point iBottom(static_cast<int>(std::lround(s - B)), B);
        g_drawPool.addFilledTriangle(iRight, br, iBottom, dark);
    }
}

void UIProgressRect::drawClassicProgress(const Rect& drawRect) const
{
    // 0% - 12.5% (12.5)
    // triangle from top center, to top right (var x)
    if (m_percent < 12.5) {
        const auto& var = Point(std::max<int>(m_percent - 0.0, 0.0) * (drawRect.right() - drawRect.horizontalCenter()) / 12.5, 0);
        g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topRight() + Point(1, 0), drawRect.topCenter() + var, m_backgroundColor);
    }

    // 12.5% - 37.5% (25)
    // triangle from top right to bottom right (var y)
    if (m_percent < 37.5) {
        const auto& var = Point(0, std::max<int>(m_percent - 12.5, 0.0) * (drawRect.bottom() - drawRect.top()) / 25.0);
        g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomRight() + Point(1), drawRect.topRight() + var + Point(1, 0), m_backgroundColor);
    }

    // 37.5% - 62.5% (25)
    // triangle from bottom right to bottom left (var x)
    if (m_percent < 62.5) {
        const auto& var = Point(std::max<int>(m_percent - 37.5, 0.0) * (drawRect.right() - drawRect.left()) / 25.0, 0);
        g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomLeft() + Point(0, 1), drawRect.bottomRight() - var + Point(1), m_backgroundColor);
    }

    // 62.5% - 87.5% (25)
    // triangle from bottom left to top left
    if (m_percent < 87.5) {
        const auto& var = Point(0, std::max<int>(m_percent - 62.5, 0.0) * (drawRect.bottom() - drawRect.top()) / 25.0);
        g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topLeft(), drawRect.bottomLeft() - var + Point(0, 1), m_backgroundColor);
    }

    // 87.5% - 100% (12.5)
    // triangle from top left to top center
    if (m_percent < 100) {
        const auto& var = Point(std::max<int>(m_percent - 87.5, 0.0) * (drawRect.horizontalCenter() - drawRect.left()) / 12.5, 0);
        g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topCenter(), drawRect.topLeft() + var, m_backgroundColor);
    }
}

void UIProgressRect::drawFrameChargeProgress(const Rect& drawRect) const
{
    const float progress = std::clamp(m_percent, 0.f, 100.f) / 100.f;
    const bool flashing = m_flashEnd > g_clock.millis();

    if (progress <= 0.f && !flashing) {
        if (!m_frameOnly)
            g_drawPool.addFilledRect(drawRect, m_backgroundColor);
        return;
    }

    // Dark veil (skipped in frame-only selection overlays).
    if (!flashing && !m_frameOnly)
        drawDiagonalDarkReveal(drawRect, progress);

    // 2) Golden frame charge around the border (same progress).
    // Skip during finish flash so the soft yellow wash stays subtle.
    const float w = static_cast<float>(std::max(drawRect.width(), 1));
    const float h = static_cast<float>(std::max(drawRect.height(), 1));
    const float peri = 2.f * (w + h);
    const float lit = progress * peri;

    auto drawSegment = [](int x, int y, int width, int height, const Color& color) {
        if (width <= 0 || height <= 0)
            return;
        g_drawPool.addFilledRect(Rect(x, y, width, height), color);
    };

    if (!flashing && lit > 0.05f) {
        float remain = lit;

        const float topEdge = std::min(remain, w);
        if (topEdge > 0.f) {
            drawSegment(drawRect.left(), drawRect.top(), static_cast<int>(std::ceil(topEdge)), 2, FRAME_GLOW);
            drawSegment(drawRect.left(), drawRect.top(), static_cast<int>(std::ceil(topEdge)), 1, FRAME_LINE);
        }
        remain -= w;

        if (remain > 0.f) {
            const float edge = std::min(remain, h);
            drawSegment(drawRect.right() - 1, drawRect.top(), 2, static_cast<int>(std::ceil(edge)), FRAME_GLOW);
            drawSegment(drawRect.right(), drawRect.top(), 1, static_cast<int>(std::ceil(edge)), FRAME_LINE);
            remain -= h;
        }

        if (remain > 0.f) {
            const float edge = std::min(remain, w);
            const int seg = static_cast<int>(std::ceil(edge));
            drawSegment(drawRect.right() - seg + 1, drawRect.bottom() - 1, seg, 2, FRAME_GLOW);
            drawSegment(drawRect.right() - seg + 1, drawRect.bottom(), seg, 1, FRAME_LINE);
            remain -= w;
        }

        if (remain > 0.f) {
            const float edge = std::min(remain, h);
            const int seg = static_cast<int>(std::ceil(edge));
            drawSegment(drawRect.left(), drawRect.bottom() - seg + 1, 2, seg, FRAME_GLOW);
            drawSegment(drawRect.left(), drawRect.bottom() - seg + 1, 1, seg, FRAME_LINE);
        }
    }

    // 3) "/" spark travels along the diagonal TL -> BR.
    if (progress > 0.f && progress < 1.f && !flashing) {
        const Point tip = diagonalPoint(drawRect, progress);

        for (int i = 1; i <= 4; ++i) {
            const float trailProgress = std::max(0.f, progress - i * 0.035f);
            const Point p = diagonalPoint(drawRect, trailProgress);
            const int alpha = 150 - i * 28;
            g_drawPool.addFilledRect(Rect(p.x, p.y, 1, 1), Color(255, 200, 60, alpha));
            g_drawPool.addFilledRect(Rect(p.x - 1, p.y + 1, 1, 1), Color(255, 180, 40, alpha / 2));
        }

        // Bright "/" glyph at the frontier.
        g_drawPool.addFilledRect(Rect(tip.x - 2, tip.y + 2, 1, 1), FRAME_BRIGHT);
        g_drawPool.addFilledRect(Rect(tip.x - 1, tip.y + 1, 1, 1), SPARK_CORE);
        g_drawPool.addFilledRect(Rect(tip.x, tip.y, 1, 1), SPARK_CORE);
        g_drawPool.addFilledRect(Rect(tip.x + 1, tip.y - 1, 1, 1), SPARK_CORE);
        g_drawPool.addFilledRect(Rect(tip.x + 2, tip.y - 2, 1, 1), FRAME_BRIGHT);
        g_drawPool.addFilledRect(Rect(tip.x + 1, tip.y, 1, 1), SPARK_TRAIL);
        g_drawPool.addFilledRect(Rect(tip.x, tip.y - 1, 1, 1), SPARK_TRAIL);
    }
}

void UIProgressRect::drawFinishFlash(const Rect& drawRect) const
{
    const ticks_t now = g_clock.millis();
    if (now >= m_flashEnd)
        return;

    // Soft ease-out: readable, not explosive.
    const float life = static_cast<float>(m_flashEnd - now) / static_cast<float>(FINISH_FLASH_MS);
    const float intensity = life * life;
    const int washAlpha = static_cast<int>(std::clamp(intensity * 42.f, 0.f, 42.f));
    const int borderAlpha = static_cast<int>(std::clamp(intensity * 110.f, 0.f, 110.f));
    const int sparkAlpha = static_cast<int>(std::clamp(intensity * 200.f, 0.f, 200.f));

    // Quiet yellow wash so the icon briefly reads as "ready".
    g_drawPool.addFilledRect(drawRect, Color(255, 230, 110, washAlpha));
    if (borderAlpha > 8)
        g_drawPool.addBoundingRect(drawRect, Color(255, 220, 80, borderAlpha), 1);

    // Soft sparkle particles around the frame (twinkle, not explosion).
    const Point c = drawRect.center();
    const int halfW = std::max(drawRect.width() / 2, 1);
    const int halfH = std::max(drawRect.height() / 2, 1);

    // Fixed pixel offsets near corners/edges — tiny pops that fade with life.
    static constexpr Point kSparks[] = {
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
        { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 },
        { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }
    };
    static constexpr float kDist[] = {
        0.92f, 0.88f, 0.90f, 0.86f,
        0.98f, 0.96f, 0.97f, 0.95f,
        0.78f, 0.80f, 0.76f, 0.82f
    };

    for (size_t i = 0; i < sizeof(kSparks) / sizeof(kSparks[0]); ++i) {
        // Slight outward drift with time, but keep it close to the icon.
        const float drift = 1.f + (1.f - life) * 0.18f;
        const float d = kDist[i] * drift;
        const int x = c.x + static_cast<int>(kSparks[i].x * halfW * d);
        const int y = c.y + static_cast<int>(kSparks[i].y * halfH * d);

        // Stagger brightness so they don't all flash as one blob.
        const float stagger = 0.65f + 0.35f * static_cast<float>((i * 37) % 10) / 9.f;
        const int a = static_cast<int>(sparkAlpha * stagger);
        if (a < 20)
            continue;

        g_drawPool.addFilledRect(Rect(x, y, 1, 1), Color(255, 235, 120, a));
        // Tiny secondary pixel for a soft "spark" look.
        if ((i % 3) == 0 && a > 60)
            g_drawPool.addFilledRect(Rect(x + kSparks[i].x, y + kSparks[i].y, 1, 1), Color(255, 210, 70, a / 2));
    }
}

void UIProgressRect::drawSelf(const DrawPoolType drawPane)
{
    if (drawPane != DrawPoolType::FOREGROUND)
        return;

    // todo: check +1 to right/bottom
    const auto& drawRect = getPaddingRect();
    const bool flashing = m_flashEnd > g_clock.millis();

    if (m_showProgress) {
        if (m_progressStyle == ProgressRectStyle::FrameCharge) {
            if (m_running || flashing || m_percent < 100.f || m_holdCompleteFrame)
                drawFrameChargeProgress(drawRect);
            if (flashing)
                drawFinishFlash(drawRect);
        } else {
            drawClassicProgress(drawRect);
        }
    }

    drawImage(m_rect);
    drawBorder(m_rect);
    drawIcon(m_rect);
    drawText(m_rect);
}

void UIProgressRect::setPercent(float percent)
{
    percent = std::clamp<float>(percent, 0.f, 100.f);
    if (m_percent == percent)
        return;

    m_percent = percent;
    repaint();
}

void UIProgressRect::stop()
{
    if (m_updateEvent) {
        m_updateEvent->cancel();
        m_updateEvent = nullptr;
    }

    if (m_running) {
        m_timeElapsed = std::min<uint32_t>(m_timeElapsed, m_duration);
        m_running = false;
    }

    m_flashEnd = 0;
}

void UIProgressRect::setDuration(uint32_t duration)
{
    m_duration = duration;
}

void UIProgressRect::start()
{
    stop();
    m_flashEnd = 0;

    if (m_duration == 0) {
        setPercent(100);
        if (m_showTime)
            setText("");
        callLuaField("onProgressUpdate", m_percent, 0, 0);
        callLuaField("onProgressFinish");
        return;
    }

    m_running = true;
    m_startTime = g_clock.millis();
    m_timeElapsed = 0;

    setPercent(0);

    if (m_showTime)
        setText("");

    updateProgress();
}

void UIProgressRect::showTime(const bool showTime)
{
    if (m_showTime == showTime)
        return;

    m_showTime = showTime;
    if (!m_showTime)
        setText("");
    else if (m_running)
        updateText(std::max<int32_t>(static_cast<int32_t>(m_duration) - static_cast<int32_t>(m_timeElapsed), 0));
}

void UIProgressRect::showProgress(const bool showProgress)
{
    if (m_showProgress == showProgress)
        return;

    m_showProgress = showProgress;
    repaint();
}

void UIProgressRect::setProgressStyle(const uint8_t style)
{
    const auto next = (style == static_cast<uint8_t>(ProgressRectStyle::FrameCharge))
        ? ProgressRectStyle::FrameCharge
        : ProgressRectStyle::Classic;
    if (m_progressStyle == next)
        return;

    m_progressStyle = next;
    repaint();
}

void UIProgressRect::setFrameOnly(const bool frameOnly)
{
    if (m_frameOnly == frameOnly)
        return;

    m_frameOnly = frameOnly;
    repaint();
}

void UIProgressRect::setHoldCompleteFrame(const bool holdCompleteFrame)
{
    if (m_holdCompleteFrame == holdCompleteFrame)
        return;

    m_holdCompleteFrame = holdCompleteFrame;
    repaint();
}

uint32_t UIProgressRect::getTimeElapsed()
{
    if (m_running)
        return std::min<uint32_t>(static_cast<uint32_t>(std::max<int64_t>(g_clock.millis() - m_startTime, 0)), m_duration);

    return (std::min)(m_timeElapsed, m_duration);
}

void UIProgressRect::onStyleApply(const std::string_view styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    for (const auto& node : styleNode->children()) {
        if (node->tag() == "percent")
            setPercent(node->value<float>());
        else if (node->tag() == "duration")
            setDuration(node->value<int>());
        else if (node->tag() == "show-time")
            showTime(node->value<bool>());
        else if (node->tag() == "show-progress")
            showProgress(node->value<bool>());
        else if (node->tag() == "progress-style") {
            const auto& value = node->value();
            if (value == "frame-charge" || value == "1")
                setProgressStyle(static_cast<uint8_t>(ProgressRectStyle::FrameCharge));
            else
                setProgressStyle(static_cast<uint8_t>(ProgressRectStyle::Classic));
        } else if (node->tag() == "frame-only") {
            setFrameOnly(node->value<bool>());
        } else if (node->tag() == "hold-complete-frame") {
            setHoldCompleteFrame(node->value<bool>());
        }
    }
}

void UIProgressRect::scheduleNextUpdate(const int intervalMs)
{
    auto self = static_self_cast<UIProgressRect>();
    m_updateEvent = g_dispatcher.scheduleEvent([self] {
        self->m_updateEvent = nullptr;
        if (self->m_running)
            self->updateProgress();
        else if (self->m_flashEnd > 0)
            self->updateFlash();
    }, intervalMs);
}

void UIProgressRect::startFinishFlash()
{
    if (m_progressStyle != ProgressRectStyle::FrameCharge)
        return;

    m_flashEnd = g_clock.millis() + FINISH_FLASH_MS;
    setPercent(100);
    repaint();
    scheduleNextUpdate(PROGRESS_UPDATE_FRAME_MS);
}

void UIProgressRect::updateFlash()
{
    if (m_flashEnd == 0)
        return;

    if (g_clock.millis() >= m_flashEnd) {
        m_flashEnd = 0;
        repaint();
        return;
    }

    repaint();
    scheduleNextUpdate(PROGRESS_UPDATE_FRAME_MS);
}

void UIProgressRect::updateProgress()
{
    if (!m_running)
        return;

    const auto now = g_clock.millis();
    m_timeElapsed = std::min<uint32_t>(static_cast<uint32_t>(std::max<int64_t>(now - m_startTime, 0)), m_duration);

    const float percent = m_duration > 0 ? (static_cast<float>(m_timeElapsed) * 100.f) / m_duration : 100.f;
    setPercent(percent);

    const int32_t remainingMs = std::max<int32_t>(static_cast<int32_t>(m_duration) - static_cast<int32_t>(m_timeElapsed), 0);
    if (m_showTime)
        updateText(static_cast<uint32_t>(remainingMs));

    callLuaField("onProgressUpdate", m_percent, (std::max)(remainingMs, 0), m_timeElapsed);

    if (m_timeElapsed >= m_duration) {
        stop();
        if (m_showTime)
            setText("");
        startFinishFlash();
        callLuaField("onProgressFinish");
        return;
    }

    const int interval = (m_progressStyle == ProgressRectStyle::FrameCharge)
        ? PROGRESS_UPDATE_FRAME_MS
        : PROGRESS_UPDATE_CLASSIC_MS;
    scheduleNextUpdate(interval);
}

void UIProgressRect::updateText(const uint32_t remainingTimeMs)
{
    if (!m_showTime)
        return;

    if (remainingTimeMs == 0) {
        setText("");
        return;
    }

    const float seconds = std::round(static_cast<float>(remainingTimeMs)) / 1000.f;
    if (seconds >= 10.f)
        setText(fmt::format("{:.0f}s", seconds));
    else if (seconds >= 1.f)
        setText(fmt::format("{:.1f}s", seconds));
    else
        setText(fmt::format("{:.2f}s", seconds));
}
