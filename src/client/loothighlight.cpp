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

#include "loothighlight.h"

#include "const.h"
#include "item.h"

void removeLootHighlightAttachedEffects(const ItemPtr& item)
{
    if (!item || !item->hasAttachedEffects())
        return;

    std::vector<AttachedEffectPtr> toDetach;
    for (const auto& effect : item->getAttachedEffects()) {
        if (!effect)
            continue;

        auto* thingType = effect->getThingType();
        if (thingType && thingType->getId() == Otc::LootHighlightEffectId)
            toDetach.push_back(effect);
    }

    for (const auto& effect : toDetach)
        item->detachEffect(effect);
}

void applyContainerLootHighlightState(const ItemPtr& item, const uint8_t containerType)
{
    if (!item)
        return;

    item->setLootHighlight(false);

    switch (containerType) {
        case 4: // Loot Highlight
            removeLootHighlightAttachedEffects(item);
            item->setLootHighlight(true);
            break;
        default:
            if (containerType == 0)
                removeLootHighlightAttachedEffects(item);
            break;
    }
}
