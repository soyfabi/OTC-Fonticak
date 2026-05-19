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

#include "statictext.h"
#include <regex>

#include "gameconfig.h"
#include "map.h"
#include "framework/core/clock.h"
#include "framework/core/eventdispatcher.h"
#include "framework/core/graphicalapplication.h"
#include "framework/graphics/fontmanager.h"

StaticText::StaticText()
{
    m_cachedText.setFont(g_gameConfig.getStaticTextFont());
    m_cachedText.setAlign(Fw::AlignCenter);
}

void StaticText::drawText(const Point& dest, const Rect& parentRect)
{
    Size textSize = m_cachedText.getTextSize();
    // OTC-Fonticak base offset is Point(20, 5), but their MapView adds Point(8, 0) before calling drawText.
    // Since this client doesn't add the 8 in MapView, we apply the total +28 X offset here.
    Rect rect = Rect(dest.x + 28 - (textSize.width() / 2), dest.y + 5 - textSize.height(), textSize);
    rect.bind(parentRect);

    m_cachedText.draw(rect, m_color);
}



void StaticText::setText(const std::string_view text) { m_cachedText.setText(text); }
void StaticText::setFont(const std::string_view fontName) { m_cachedText.setFont(g_fonts.getFont(fontName)); }

bool StaticText::addMessage(const std::string_view name, const Otc::MessageMode mode, const std::string_view text)
{
    //TODO: this could be moved to lua
    // first message
    if (m_messages.empty()) {
        m_name = name;
        m_mode = mode;
    }
    // check if we can really own the message
    else if (m_name != name || m_mode != mode) {
        return false;
    }

    // too many messages
    else if (m_messages.size() > 10) {
        m_messages.pop_front();
        m_updateEvent->cancel();
        m_updateEvent = nullptr;
    }

    int delay = std::max<int>(g_gameConfig.getStaticDurationPerCharacter() * text.length(), g_gameConfig.getMinStatictextDuration());
    if (isYell())
        delay *= 2;

    if (g_app.mustOptimize())
        delay /= 2;

    m_messages.emplace_back(text, g_clock.millis() + delay);
    compose();

    if (!m_updateEvent)
        scheduleUpdate();

    return true;
}

void StaticText::update()
{
    m_messages.pop_front();
    if (m_messages.empty()) {
        // schedule removal
        g_textDispatcher.addEvent([self = asStaticText()] { g_map.removeStaticText(self); });
    } else {
        compose();
        scheduleUpdate();
    }
}

void StaticText::scheduleUpdate()
{
    const int delay = std::max<int>(m_messages.front().second - g_clock.millis(), 0);
    m_updateEvent = g_dispatcher.scheduleEvent([self = asStaticText()] {
        self->m_updateEvent = nullptr;
        self->update();
    }, delay);
}

void StaticText::compose()
{
    static constexpr Color
        MESSAGE_COLOR1(239, 239, 0),
        MESSAGE_COLOR2(254, 101, 0),
        MESSAGE_COLOR3(95, 247, 247);

    //TODO: this could be moved to lua
    std::string text;

    if (m_mode == Otc::MessageSay) {
        text += m_name;
        text += " says:\n";
        m_color = MESSAGE_COLOR1;
    } else if (m_mode == Otc::MessageWhisper) {
        text += m_name;
        text += " whispers:\n";
        m_color = MESSAGE_COLOR1;
    } else if (m_mode == Otc::MessageYell) {
        text += m_name;
        text += " yells:\n";
        m_color = MESSAGE_COLOR1;
    } else if (m_mode == Otc::MessageMonsterSay || m_mode == Otc::MessageMonsterYell || m_mode == Otc::MessageSpell
               || m_mode == Otc::MessageBarkLow || m_mode == Otc::MessageBarkLoud) {
        m_color = MESSAGE_COLOR2;
    } else if (m_mode == Otc::MessageNpcFrom || m_mode == Otc::MessageNpcFromStartBlock) {
        text += m_name;
        text += " says:\n";
        m_color = MESSAGE_COLOR3;
    } else {
        g_logger.warning("Unknown speak type: {}", static_cast<uint8_t>(m_mode));
    }

    for (uint32_t i = 0; i < m_messages.size(); ++i) {
        text += m_messages[i].first;

        if (i < m_messages.size() - 1)
            text += "\n";
    }

    std::vector<std::pair<int, Color>> textColors;
    std::string finalCleanText;
    
    static const std::regex expColor(R"(\{([^\}]+),[ ]*([^\}]+)\})");
    std::smatch res;
    std::string _text = text;

    while (std::regex_search(_text, res, expColor)) {
        std::string prefix = res.prefix().str();
        if (!prefix.empty()) {
            textColors.emplace_back(finalCleanText.size(), m_color);
            finalCleanText.append(prefix);
        }
        
        auto color = Color(res[2].str());
        std::string colorContent = res[1].str();
        
        static const std::regex expEvent(R"(\[text-event\](.*?)\[/text-event\])");
        std::smatch eventMatch;
        std::string cleanColorContent;
        std::string tempColorContent = colorContent;
        while(std::regex_search(tempColorContent, eventMatch, expEvent)) {
            cleanColorContent += eventMatch.prefix().str();
            std::string eventContent = eventMatch[1].str();
            if (!eventContent.empty() && eventContent[0] == '\x01')
                eventContent = eventContent.substr(1);
            cleanColorContent += eventContent;
            tempColorContent = eventMatch.suffix().str();
        }
        cleanColorContent += tempColorContent;

        textColors.emplace_back(finalCleanText.size(), color);
        finalCleanText.append(cleanColorContent);
        _text = res.suffix().str();
    }
    
    if (!_text.empty()) {
        textColors.emplace_back(finalCleanText.size(), m_color);
        finalCleanText.append(_text);
    }

    m_cachedText.setTextColors(textColors);
    m_cachedText.setText(textColors.empty() ? text : finalCleanText);
    m_cachedText.wrapText(275);
}