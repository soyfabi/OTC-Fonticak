#include <gtest/gtest.h>

#include "client/item.h"
#include "client/loothighlight.h"
#include "client/tile.h"

#include <framework/core/logger.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/texturemanager.h>

namespace {

class FrameworkEnvironment : public testing::Environment
{
public:
    void SetUp() override
    {
        m_previousLogLevel = g_logger.getLevel();
        g_logger.setLevel(Fw::LogFatal);
        g_resources.init(".");
        g_resources.addSearchPath(".");
        g_textures.init();
    }

    void TearDown() override
    {
        g_textures.terminate();
        g_resources.terminate();
        g_logger.setLevel(m_previousLogLevel);
    }

private:
    Fw::LogLevel m_previousLogLevel{ Fw::LogFatal };
};

[[maybe_unused]] testing::Environment* const g_frameworkEnv = testing::AddGlobalTestEnvironment(new FrameworkEnvironment);

ItemPtr makeItem()
{
    const auto& item = Item::create(100);
    EXPECT_TRUE(item);
    return item;
}

} // namespace

TEST(LootHighlightContainerState, RepeatedType4KeepsSingleHighlight)
{
    const auto& item = makeItem();

    applyContainerLootHighlightState(item, 4);
    EXPECT_TRUE(item->hasLootHighlight());

    applyContainerLootHighlightState(item, 4);
    EXPECT_TRUE(item->hasLootHighlight());
}

TEST(LootHighlightContainerState, Type0ClearsHighlight)
{
    const auto& item = makeItem();

    applyContainerLootHighlightState(item, 4);
    EXPECT_TRUE(item->hasLootHighlight());

    applyContainerLootHighlightState(item, 0);
    EXPECT_FALSE(item->hasLootHighlight());
}

TEST(LootHighlightContainerState, NonHighlightContainerTypeClearsHighlight)
{
    const auto& item = makeItem();

    applyContainerLootHighlightState(item, 4);
    EXPECT_TRUE(item->hasLootHighlight());

    applyContainerLootHighlightState(item, 1);
    EXPECT_FALSE(item->hasLootHighlight());
}

TEST(LootHighlightContainerState, TileFlagTracksStoredHighlightState)
{
    const Position position(100, 100, 7);
    Tile tile(position);

    const auto& item = makeItem();
    applyContainerLootHighlightState(item, 4);

    tile.addThing(item, -1);
    EXPECT_TRUE(tile.hasLootHighlightItems());

    applyContainerLootHighlightState(item, 0);
    tile.updateLootHighlightFlag();
    EXPECT_FALSE(tile.hasLootHighlightItems());
}
