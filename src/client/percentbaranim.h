/*
 * Lightweight ease-out percent for nameplate HP/MP bars.
 * Cost when idle: one bool check. Cost while animating: a few floats per draw.
 */

#pragma once

#include <framework/core/clock.h>
#include <algorithm>
#include <cmath>

#include "gameconfig.h"

struct PercentBarAnim
{
    float drawn{ 100.f };
    float from{ 100.f };
    float to{ 100.f };
    ticks_t start{ 0 };
    int duration{ 0 };
    bool active{ false };

    void snap(const float target)
    {
        const float clamped = std::clamp(target, 0.f, 100.f);
        active = false;
        drawn = from = to = clamped;
    }

    void startToward(const float target, const bool animate)
    {
        const float clamped = std::clamp(target, 0.f, 100.f);
        if (!animate || std::abs(clamped - drawn) < 0.05f) {
            snap(clamped);
            return;
        }

        from = drawn;
        to = clamped;
        start = g_clock.millis();
        duration = g_gameConfig.getVitalBarAnimationDuration(to - from);
        active = true;
    }

    float value()
    {
        if (!active)
            return drawn;

        const float elapsed = static_cast<float>(g_clock.millis() - start);
        const float progress = std::min(elapsed / static_cast<float>(std::max(1, duration)), 1.f);
        const float inv = 1.f - progress;
        drawn = from + (to - from) * (1.f - inv * inv * inv);

        if (progress >= 1.f)
            snap(to);

        return drawn;
    }
};
