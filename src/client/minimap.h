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

#pragma once

#include "declarations.h"
#include <framework/graphics/declarations.h>
#include <framework/util/spinlock.h>
#include <atomic>
#include <future>
#include <list>
#include <mutex>
#include <unordered_set>

constexpr uint8_t MMBLOCK_SIZE = 64;
constexpr uint8_t OTMM_VERSION = 1;
constexpr uint32_t OTMM_SIGNATURE = 0x4D4d544F;

enum MinimapTileFlags
{
    MinimapTileWasSeen = 1,
    MinimapTileNotPathable = 2,
    MinimapTileNotWalkable = 4,
    MinimapTileEmpty = 8,
    MinimapTileFogExplored = 16
};

#pragma pack(push,1) // disable memory alignment
struct MinimapTile
{
    uint8_t flags{ 0 };
    uint8_t color{ 255 };
    uint8_t speed{ 10 };
    bool hasFlag(const MinimapTileFlags flag) const { return flags & flag; }
    int getSpeed() const { return speed * 10; }
    bool operator==(const MinimapTile& other) const { return color == other.color && flags == other.flags && speed == other.speed; }
    bool operator!=(const MinimapTile& other) const { return !(*this == other); }
};

class MinimapBlock
{
public:
    void update();
    void updateTile(int x, int y, const MinimapTile& tile);
    MinimapTile& getTile(const int x, const int y) { return m_tiles[getTileIndex(x, y)]; }
    uint32_t getTileIndex(const int x, const int y) { return ((y % MMBLOCK_SIZE) * MMBLOCK_SIZE) + (x % MMBLOCK_SIZE); }
    const TexturePtr& getTexture() { return m_texture; }
    std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE>& getTiles() { return m_tiles; }
    void mustUpdate() { m_mustUpdate = true; ++m_fogRevision; }
    uint64_t getFogRevision() const { return m_fogRevision; }
    void justSaw() { m_wasSeen = true; }
    bool wasSeen() const { return m_wasSeen; }
private:
    TexturePtr m_texture;
    std::array<MinimapTile, MMBLOCK_SIZE* MMBLOCK_SIZE> m_tiles;

    bool m_mustUpdate{ true };
    uint64_t m_fogRevision{ 0 };
    bool m_wasSeen{ false };
};

#pragma pack(pop)

using MinimapBlock_ptr = std::shared_ptr<MinimapBlock>;

class MinimapProjection
{
public:
    MinimapProjection(const Rect& viewport, const Position& center, float scale, const PointF& offset = {});
    Point tileEdge(const Point& world) const;
    Point tileCenter(const Point& world) const;
    Point screenTile(const Point& screen) const;
    RectF tileRect(const Point& world, const Size& size) const;

private:
    PointF tileEdgeFloat(const Point& world) const;
    Point m_center;
    PointF m_origin;
    float m_scale;
};

void drawMinimapTexture(const RectF& dest, const TexturePtr& texture, const Color& tint);

struct MinimapHdCache
{
    struct Chunk
    {
        TexturePtr texture;
        std::list<uint64_t>::iterator order;
    };

    struct Animation
    {
        std::future<ImagePtr> decode;
        TexturePtr texture;
    };

    uint64_t revision{ 0 };
    int displayedLevel{ 0 };
    std::unordered_map<uint64_t, Chunk> textures;
    std::list<uint64_t> order;
    std::unordered_map<uint64_t, std::future<ImagePtr>> decodes;
    std::unordered_map<uint64_t, Animation> animations;
};

class Minimap
{
public:
    void init();
    void terminate();
    bool startPackDownload(bool animations);
    void cancelPackDownload();
    std::string getPackDownloadStatus(bool animations);
    bool canUninstallPack(bool animations) const;
    std::string uninstallPack(bool animations);
    int getPackDownloadProgress() const { return m_packDownloadProgress.load(); }
    int getPackDownloadSizeMb(bool animations) const;

    void clean();

    void draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color, const PointF& offset);
    void drawFog(const Rect& screenRect, const Position& mapCenter, float scale, const PointF& offset);
    void revealFog(const Position& center);
    void drawHd(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color, bool live,
                const PointF& offset, bool zooming, bool animationsEnabled, bool showFloorItems, MinimapHdCache& cache);
    void setWalkView(const UIMinimapPtr& widget, bool enabled);
    void onCameraMove() const;
    void addHdView();
    void removeHdView();
    void clearHdTerrain();
    void updateHdTile(const Position& pos, const TilePtr& tile);
    Point getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale, const PointF& offset);
    Position getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale, const PointF& offset);
    Rect getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale, const PointF& offset);

    void updateTile(const Position& pos, const TilePtr& tile);
    const MinimapTile& getTile(const Position& pos);
    std::pair<MinimapBlock_ptr, MinimapTile> threadGetTile(const Position& pos);

    bool loadImage(const std::string& fileName, const Position& topLeft, float colorFactor);
    void saveImage(const std::string& fileName, const Rect& mapRect);
    bool loadOtmm(const std::string& fileName);
    void saveOtmm(const std::string& fileName);

private:
    bool mountDownloadedPack(bool animations);
    std::future<std::string> m_packDownload;
    std::atomic_bool m_cancelPackDownload{ false };
    std::atomic_int m_packDownloadProgress{ 0 };
    std::atomic_bool m_reloadHdIndex{ false };
    std::array<std::string, 2> m_mountedPackPaths{};
    std::array<bool, 2> m_packChecked{};
    bool m_downloadingAnimations{ false };
    std::string m_packDownloadError;

    std::vector<std::weak_ptr<UIMinimap>> m_walkViews;
    struct FogChunk
    {
        std::array<uint64_t, 9> revisions{};
        TexturePtr texture;
        std::list<uint64_t>::iterator order;
    };
    std::unordered_map<uint64_t, FogChunk> m_fogChunks;
    std::list<uint64_t> m_fogChunkOrder;
    TexturePtr getFogTexture(const Position& pos);

    struct HdTile
    {
        std::vector<ItemPtr> items;
        std::list<uint64_t>::iterator order;
        size_t pickupables;
    };

    void loadHdIndex();
    void loadHdAnimationIndex();
    bool drawHdAnimation(uint64_t key, const RectF& dest, uint64_t tick, MinimapHdCache& cache);
    std::vector<Rect> drawHdPack(const Rect& screenRect, int floor, const MinimapProjection& projection,
                                 float scale, bool zooming, bool animateItems, MinimapHdCache& cache);

    std::atomic_uint m_hdViewCount{ 0 };
    std::mutex m_hdMutex;
    std::unordered_map<uint64_t, HdTile> m_hdTiles;
    std::list<uint64_t> m_hdTileOrder;
    size_t m_hdItemCount{ 0 };

    // Pack state belongs to the foreground renderer.
    std::pair<uint32_t, uint32_t> m_hdSignatures{};
    bool m_hdIndexChecked{ false };
    std::unordered_set<uint64_t> m_hdIndex;
    std::array<bool, 11> m_hdLevels{};
    uint64_t m_hdIndexRevision{ 0 };
    struct HdAnimation
    {
        Rect crop;
        int frames;
        bool replace;
        Size atlasSize() const;
    };
    bool m_hdAnimationIndexChecked{ false };
    std::string m_hdAnimationDirectory;
    std::unordered_map<uint64_t, HdAnimation> m_hdAnimations;

    bool hasBlock(const Position& pos) { return m_tileBlocks[pos.z].contains(getBlockIndex(pos)); }
    MinimapBlock& getBlock(const Position& pos)
    {
        SpinLock::Guard lock(m_lock);
        auto& ptr = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if (!ptr)
            ptr = std::make_shared<MinimapBlock>();
        return *ptr;
    }
    Point getBlockOffset(const Point& pos)
    {
        return {
            pos.x - (pos.x % MMBLOCK_SIZE + MMBLOCK_SIZE) % MMBLOCK_SIZE,
            pos.y - (pos.y % MMBLOCK_SIZE + MMBLOCK_SIZE) % MMBLOCK_SIZE
        };
    }
    Position getIndexPosition(const int index, const int z)
    {
        return {
            (index % (65536 / MMBLOCK_SIZE)) * MMBLOCK_SIZE,
                        (index / (65536 / MMBLOCK_SIZE)) * MMBLOCK_SIZE, static_cast<uint8_t>(z)
        };
    }
    uint32_t getBlockIndex(const Position& pos) { return ((pos.y / MMBLOCK_SIZE) * (65536 / MMBLOCK_SIZE)) + (pos.x / MMBLOCK_SIZE); }
    std::vector<std::unordered_map<uint32_t, MinimapBlock_ptr>> m_tileBlocks;
    SpinLock m_lock;
};

extern Minimap g_minimap;
