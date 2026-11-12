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

#include "minimap.h"

#include "gameconfig.h"
#include "item.h"
#include "map.h"
#include "spritemanager.h"
#include "thingtypemanager.h"
#include "tile.h"
#include "uiminimap.h"
#include "framework/core/asyncdispatcher.h"
#include "framework/core/filestream.h"
#include "framework/core/resourcemanager.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/graphics/image.h"
#include "framework/graphics/texture.h"
#include <bit>
#include <sstream>

Minimap g_minimap;
static MinimapTile nulltile;

namespace
{
    constexpr size_t MaxHdTiles = 8192;
    constexpr size_t MaxHdItems = 32768;
    constexpr size_t MaxHdTextures = 32;
    constexpr size_t MaxHdDecodes = 4;
    constexpr int HdChunkSize = 16;
    constexpr char HdPackDir[] = "/data/minimap_hd/";

    uint64_t hdTileKey(int x, int y, int z)
    {
        return (uint64_t(z) << 32) | (uint64_t(y) << 16) | uint64_t(x);
    }

    uint64_t hdChunkKey(int level, int x, int y, int z)
    {
        return (uint64_t(level) << 40) | hdTileKey(x, y, z);
    }

    std::string hdChunkName(int level, int x, int y, int z)
    {
        return fmt::format("satellite-{}-{}-{}-{}.png", level, x, y, z);
    }

    std::string readHdFile(const std::string& path, uint32_t maxSize)
    {
        const auto file = g_resources.openFile(path);
        const auto size = file->size();
        if (size == 0 || size > maxSize)
            return {};

        std::string data(size, '\0');
        if (file->read(data.data(), 1, size) != static_cast<int>(size))
            return {};
        return data;
    }

    ImagePtr decodeHdChunk(const std::string& path)
    {
        try {
            const auto data = readHdFile(path, 4 * 1024 * 1024);
            if (data.size() < 33 || data.compare(0, 8, "\x89PNG\r\n\x1a\n", 8) != 0 ||
                data.compare(12, 12, "IHDR\0\0\2\0\0\0\2\0", 12) != 0)
                return nullptr;

            // Reject animation and malformed chunk lengths before decoding.
            for (size_t offset = 8; offset + 12 <= data.size();) {
                const auto* bytes = reinterpret_cast<const uint8_t*>(data.data() + offset);
                const uint32_t length = (uint32_t(bytes[0]) << 24) | (uint32_t(bytes[1]) << 16) |
                                        (uint32_t(bytes[2]) << 8) | bytes[3];
                const std::string_view type(data.data() + offset + 4, 4);
                if (length > data.size() - offset - 12 || type == "acTL" || type == "fcTL" ||
                    type == "fdAT" || (type == "IHDR" && (offset != 8 || length != 13)))
                    return nullptr;

                offset += length + 12;
                if (type == "IEND" && length == 0 && offset == data.size())
                    return Image::loadPNG(data.data(), data.size());
            }
        } catch (const std::exception&) {
            // A missing or unreadable chunk leaves the classic map visible.
        }
        return nullptr;
    }
}

void MinimapBlock::clean()
{
    m_tiles.fill({});
    m_texture.reset();
    m_mustUpdate = false;
}

void MinimapBlock::update()
{
    if (!m_mustUpdate)
        return;

    m_image = std::make_shared<Image>(m_size);

    bool shouldDraw = false;
    for (uint_fast8_t x = 0; x < MMBLOCK_SIZE; ++x) {
        for (uint_fast8_t y = 0; y < MMBLOCK_SIZE; ++y) {
            const uint8_t c = getTile(x, y).color;

            Color col = Color::black;
            if (c != UINT8_MAX) {
                col = Color::from8bit(c);
                shouldDraw = true;
            }

            m_image->setPixel(x, y, col);
        }
    }

    if (shouldDraw)
        m_texture = std::make_shared<Texture>(m_image, true, false);
    else
        m_texture.reset();

    m_mustUpdate = false;
}

void MinimapBlock::updateTile(const int x, const int y, const MinimapTile& tile)
{
    if (m_tiles[getTileIndex(x, y)].color != tile.color)
        m_mustUpdate = true;

    m_tiles[getTileIndex(x, y)] = tile;
}

void Minimap::init() {
    m_tileBlocks.resize(g_gameConfig.getMapMaxZ() + 1);
}

void Minimap::terminate() { clean(); }

void Minimap::clean()
{
    clearHdTerrain();
    SpinLock::Guard lock(m_lock);
    for (uint_fast8_t i = 0; i <= g_gameConfig.getMapMaxZ(); ++i)
        m_tileBlocks[i].clear();
}

void Minimap::clearHdTerrain()
{
    std::scoped_lock lock(m_hdMutex);
    m_hdTiles.clear();
    m_hdTileOrder.clear();
    m_hdItemCount = 0;
}

void Minimap::addHdView()
{
    if (m_hdViewCount.fetch_add(1) != 0)
        return;

    for (const auto& tile : g_map.getTiles())
        updateHdTile(tile->getPosition(), tile);
}

void Minimap::removeHdView()
{
    if (m_hdViewCount.fetch_sub(1) == 1)
        clearHdTerrain();
}

void Minimap::updateHdTile(const Position& pos, const TilePtr& tile)
{
    if (m_hdViewCount == 0 || !pos.isMapPosition())
        return;

    auto items = tile ? tile->getItems() : std::vector<ItemPtr>{};
    if (items.size() > 64)
        items.clear();

    const auto key = hdTileKey(pos.x, pos.y, pos.z);
    std::scoped_lock lock(m_hdMutex);
    if (m_hdViewCount == 0)
        return;

    if (const auto it = m_hdTiles.find(key); it != m_hdTiles.end()) {
        const auto& old = it->second.items;
        if (items.size() == old.size() && std::equal(items.begin(), items.end(), old.begin(),
            [](const ItemPtr& a, const ItemPtr& b) {
                return a->getId() == b->getId() && a->getCountOrSubType() == b->getCountOrSubType();
            })) {
            m_hdTileOrder.splice(m_hdTileOrder.end(), m_hdTileOrder, it->second.order);
            return;
        }
        m_hdItemCount -= old.size();
        m_hdTileOrder.erase(it->second.order);
        m_hdTiles.erase(it);
    }

    if (items.empty())
        return;

    for (auto& item : items) {
        auto snapshot = Item::create(item->getId());
        snapshot->setCountOrSubType(item->getCountOrSubType());
        snapshot->setPosition(pos);
        item = std::move(snapshot);
    }

    while (m_hdTiles.size() >= MaxHdTiles || m_hdItemCount + items.size() > MaxHdItems) {
        const auto oldest = m_hdTileOrder.front();
        m_hdItemCount -= m_hdTiles.at(oldest).items.size();
        m_hdTiles.erase(oldest);
        m_hdTileOrder.pop_front();
    }
    m_hdItemCount += items.size();
    m_hdTileOrder.push_back(key);
    const auto pickupables = std::ranges::count_if(items, [](const ItemPtr& item) { return item->isPickupable(); });
    m_hdTiles.emplace(key, HdTile{ std::move(items), std::prev(m_hdTileOrder.end()), static_cast<size_t>(pickupables) });
}

void Minimap::loadHdIndex()
{
    const auto signatures = std::pair{ g_things.getDatSignature(), g_sprites.getSignature() };
    if (m_hdIndexChecked && signatures == m_hdSignatures)
        return;

    m_hdIndexChecked = true;
    m_hdSignatures = signatures;
    m_hdIndex.clear();
    m_hdLevels.fill(false);
    m_hdTextures.clear();
    m_hdTextureOrder.clear();

    const std::string path = std::string(HdPackDir) + "index.txt";
    if (!g_resources.fileExists(path))
        return;

    try {
        std::istringstream input(readHdFile(path, 8 * 1024 * 1024));
        std::string magic;
        int version, chunkSize, pixelsPerTile;
        uint32_t datSignature, sprSignature;
        size_t count;
        if (!(input >> magic >> version >> chunkSize >> pixelsPerTile >> datSignature >> sprSignature >> count) ||
            magic != "ASTRAHD" || version != 1 || chunkSize != HdChunkSize || pixelsPerTile != 32 ||
            count == 0 || count > 100000)
            throw std::runtime_error("invalid index header");

        if (std::pair{ datSignature, sprSignature } != signatures)
            throw std::runtime_error("the pack uses different DAT/SPR assets");

        std::unordered_set<uint64_t> index;
        std::array<bool, 11> levels{};
        for (size_t i = 0; i < count; ++i) {
            int level, x, y, z;
            std::string name;
            if (!(input >> level >> x >> y >> z >> name) || level < 1 || level > 1024 ||
                (level & (level - 1)) || x < 0 || x >= 65536 || y < 0 || y >= 65536 ||
                z < 0 || z > g_gameConfig.getMapMaxZ() ||
                x % (HdChunkSize * level) || y % (HdChunkSize * level) ||
                name != hdChunkName(level, x, y, z) || !index.insert(hdChunkKey(level, x, y, z)).second)
                throw std::runtime_error("invalid or duplicate chunk");

            levels[std::countr_zero(static_cast<unsigned>(level))] = true;
        }
        std::string extra;
        if (input >> extra)
            throw std::runtime_error("unexpected trailing index data");

        m_hdIndex = std::move(index);
        m_hdLevels = levels;
    } catch (const std::exception& e) {
        g_logger.warning("HD minimap: could not load {} ({})", path, e.what());
    }
}

std::optional<std::vector<Rect>> Minimap::drawHdPack(const Rect& screenRect, const Position& center, const Rect& mapRect,
                                                  const Point& origin, float scale, const PointF& subpixelOffset)
{
    if (!g_things.isDatLoaded() || !g_sprites.isLoaded())
        return std::nullopt;
    loadHdIndex();

    for (auto it = m_hdDecodes.begin(); it != m_hdDecodes.end();) {
        if (it->second.wait_for(std::chrono::seconds(0)) != std::future_status::ready) {
            ++it;
            continue;
        }

        auto image = it->second.get();
        if (m_hdIndex.contains(it->first)) {
            if (m_hdTextures.size() == MaxHdTextures) {
                m_hdTextures.erase(m_hdTextureOrder.front());
                m_hdTextureOrder.pop_front();
            }
            TexturePtr texture;
            if (image && image->getSize() == Size(512, 512)) {
                texture = std::make_shared<Texture>(image, false, false);
                if (image->getBpp() == 4)
                    texture->enableMipmaps(true);
            }
            m_hdTextureOrder.push_back(it->first);
            m_hdTextures.emplace(it->first, HdChunk{ std::move(texture), std::prev(m_hdTextureOrder.end()) });
        }
        it = m_hdDecodes.erase(it);
    }

    struct VisibleChunk
    {
        uint64_t key;
        Rect screen;
        Rect world;
    };
    // Invert the same projection used to draw the chunks, including camera motion.
    const Rect bounds = screenRect.expanded(1);
    const int left = std::max(0, mapRect.left() + int(std::floor((bounds.left() - origin.x) / scale)));
    const int top = std::max(0, mapRect.top() + int(std::floor((bounds.top() - origin.y) / scale)));
    const int right = std::min(65535, mapRect.left() + int(std::ceil((bounds.right() - origin.x) / scale)));
    const int bottom = std::min(65535, mapRect.top() + int(std::ceil((bounds.bottom() - origin.y) / scale)));
    const auto visibleChunks = [&](int level) {
        std::vector<VisibleChunk> chunks;
        const int span = HdChunkSize * level;
        for (int y = top / span * span; y <= bottom; y += span) {
            for (int x = left / span * span; x <= right; x += span) {
                const auto key = hdChunkKey(level, x, y, center.z);
                if (!m_hdIndex.contains(key))
                    continue;

                const Point offset = Point(x, y) - mapRect.topLeft();
                const Point dest = origin + offset * scale;
                const Point end = origin + (offset + Point(span, span)) * scale;
                const Rect rect(dest, Size(end.x - dest.x, end.y - dest.y));
                if (rect.isValid() && rect.intersects(bounds))
                    chunks.push_back({ key, rect, Rect(x, y, span, span) });
            }
        }
        return chunks;
    };

    const auto requestChunks = [&](const std::vector<VisibleChunk>& chunks, int level) {
        for (const auto& chunk : chunks) {
            if (const auto it = m_hdTextures.find(chunk.key); it != m_hdTextures.end()) {
                m_hdTextureOrder.splice(m_hdTextureOrder.end(), m_hdTextureOrder, it->second.order);
            } else if (m_hdDecodes.size() < MaxHdDecodes && !m_hdDecodes.contains(chunk.key)) {
                const auto path = HdPackDir + hdChunkName(level, chunk.world.left(), chunk.world.top(), center.z);
                m_hdDecodes.emplace(chunk.key, g_asyncDispatcher.submit_task([path] { return decodeHdChunk(path); }));
            }
        }
    };

    std::vector<VisibleChunk> detail;
    std::vector<VisibleChunk> overview;
    std::vector<VisibleChunk> ready;
    int detailLevel = 0;
    int overviewLevel = 0;
    for (size_t i = 0; i < m_hdLevels.size(); ++i) {
        if (!m_hdLevels[i])
            continue;

        const int level = 1 << i;
        const float chunkPixels = HdChunkSize * level * scale;
        // Base detail on the viewport size, so dragging across a chunk boundary cannot switch it.
        const int columns = int(std::ceil(bounds.width() / chunkPixels)) + 1;
        const int rows = int(std::ceil(bounds.height() / chunkPixels)) + 1;
        if (columns * rows > 24 || (chunkPixels < 64 && i + 1 < m_hdLevels.size() && m_hdLevels[i + 1]))
            continue;

        auto chunks = visibleChunks(level);
        if (chunks.empty())
            continue;

        if (detail.empty()) {
            detailLevel = level;
            detail = chunks;
        }
        if (ready.empty() && std::ranges::all_of(chunks, [&](const VisibleChunk& chunk) {
                const auto it = m_hdTextures.find(chunk.key);
                return it != m_hdTextures.end() && it->second.texture != nullptr;
            })) {
            ready = chunks;
        }
        if (chunkPixels >= std::max(bounds.width(), bounds.height())) {
            overviewLevel = level;
            overview = std::move(chunks);
            break;
        }
    }
    if (detail.empty())
        return std::nullopt;

    if (!overview.empty() && overviewLevel != detailLevel)
        requestChunks(overview, overviewLevel);
    requestChunks(detail, detailLevel);

    // Switch the whole visible map together once the requested detail is ready.
    const auto& displayed = !ready.empty() ? ready : (!overview.empty() ? overview : detail);
    if (!subpixelOffset.isNull()) {
        g_drawPool.pushTransformMatrix();
        g_drawPool.translate(subpixelOffset.x, subpixelOffset.y);
    }
    std::vector<Rect> coverage;
    for (const auto& chunk : displayed) {
        const auto it = m_hdTextures.find(chunk.key);
        if (it == m_hdTextures.end() || !it->second.texture)
            continue;
        m_hdTextureOrder.splice(m_hdTextureOrder.end(), m_hdTextureOrder, it->second.order);
        g_drawPool.addTexturedRect(chunk.screen, it->second.texture, Rect(0, 0, 512, 512));
        coverage.push_back(chunk.world);
    }
    if (!subpixelOffset.isNull())
        g_drawPool.popTransformMatrix();
    return coverage;
}

void Minimap::setWalkView(const UIMinimapPtr& widget, bool enabled)
{
    std::erase_if(m_walkViews, [&](const auto& entry) {
        const auto view = entry.lock();
        return !view || view == widget;
    });
    if (enabled)
        m_walkViews.emplace_back(widget);
}

void Minimap::onCameraMove() const
{
    for (const auto& entry : m_walkViews) {
        if (const auto view = entry.lock())
            view->updateWalkOffset();
    }
}

void Minimap::drawHd(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color, bool live,
                     const Point& offset, const PointF& subpixelOffset)
{
    if (screenRect.isEmpty() || !mapCenter.isMapPosition()) {
        draw(screenRect, mapCenter, scale, color, offset);
        return;
    }

    const auto mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto origin = screenRect.topLeft() - Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2 + offset;
    const auto oldClip = g_drawPool.getClipRect();
    g_drawPool.setClipRect(oldClip.isValid() ? screenRect.intersection(oldClip) : screenRect);
    g_drawPool.addFilledRect(screenRect, color);
    const auto packedAreas = drawHdPack(screenRect, mapCenter, mapRect, origin, scale, subpixelOffset);
    if (!packedAreas)
        draw(screenRect, mapCenter, scale, color, offset);

    if (!subpixelOffset.isNull()) {
        g_drawPool.pushTransformMatrix();
        g_drawPool.translate(subpixelOffset.x, subpixelOffset.y);
    }

    const int spriteSize = g_gameConfig.getSpriteSize();
    const auto view = mapRect.expanded(4);
    if (scale >= 2.f && spriteSize > 0) {
        struct VisibleTile
        {
            Point position;
            std::vector<ItemPtr> items;
            bool drawTerrain;
            bool drawPickupables;
        };

        const bool scanViewport = view.size().area() <= 4096;
        std::vector<VisibleTile> tiles;
        size_t itemCount = 0;
        {
            std::scoped_lock lock(m_hdMutex);
            const auto collect = [&](const Point& tile, const HdTile& snapshot) {
                const bool drawTerrain = live && scanViewport &&
                    (!packedAreas || std::ranges::none_of(*packedAreas, [&](const Rect& area) { return area.contains(tile); }));
                const bool drawPickupables = snapshot.pickupables > 0 &&
                    g_map.isAwareOfPosition(Position(tile.x, tile.y, mapCenter.z));
                const size_t visibleItems = (drawTerrain ? snapshot.items.size() - snapshot.pickupables : 0) +
                    (drawPickupables ? snapshot.pickupables : 0);
                if (visibleItems == 0)
                    return;

                itemCount += visibleItems;
                if (itemCount > 8192)
                    return;
                m_hdTileOrder.splice(m_hdTileOrder.end(), m_hdTileOrder, snapshot.order);
                tiles.push_back({ tile, snapshot.items, drawTerrain, drawPickupables });
            };

            if (scanViewport) {
                for (int y = std::max(0, view.top()); y <= std::min(65535, view.bottom()) && itemCount <= 8192; ++y) {
                    for (int x = std::max(0, view.left()); x <= std::min(65535, view.right()) && itemCount <= 8192; ++x) {
                        if (const auto it = m_hdTiles.find(hdTileKey(x, y, mapCenter.z)); it != m_hdTiles.end())
                            collect(Point(x, y), it->second);
                    }
                }
            } else {
                // Wide views still show nearby items without scanning every tile on the screen.
                for (const auto& [key, snapshot] : m_hdTiles) {
                    if ((key >> 32) != mapCenter.z)
                        continue;
                    const Point tile(key & 0xffff, (key >> 16) & 0xffff);
                    if (view.contains(tile))
                        collect(tile, snapshot);
                    if (itemCount > 8192)
                        break;
                }
            }
        }

        if (itemCount <= 8192) {
            if (!scanViewport) {
                std::ranges::sort(tiles, [](const VisibleTile& a, const VisibleTile& b) {
                    return std::tie(a.position.y, a.position.x) < std::tie(b.position.y, b.position.x);
                });
            }

            const auto oldScale = g_drawPool.getScaleFactor();
            const float spriteScale = scale / spriteSize;
            const float pickupSize = std::max(scale, 4.f);
            const float pickupScale = pickupSize / spriteSize;
            const int pickupInset = static_cast<int>((scale - pickupSize) / 2);
            g_drawPool.setScaleFactor(spriteScale);
            for (const auto& [position, items, drawTerrain, drawPickupables] : tiles) {
                const auto dest = origin + (position - mapRect.topLeft()) * scale;
                int elevation = 0;
                const auto drawItem = [&](const ItemPtr& item, int itemElevation) {
                    const auto itemPos = dest - Point(itemElevation, itemElevation) * spriteScale;
                    if (item->isPickupable()) {
                        if (drawPickupables) {
                            // Keep small loot sprites legible at normal minimap zoom.
                            g_drawPool.setScaleFactor(pickupScale);
                            item->drawMinimap(itemPos + Point(pickupInset, pickupInset));
                            g_drawPool.setScaleFactor(spriteScale);
                        }
                    } else if (drawTerrain) {
                        item->drawMinimap(itemPos);
                    }
                };
                const auto drawStackItem = [&](const ItemPtr& item) {
                    drawItem(item, elevation);
                    elevation = std::min<int>(elevation + item->getElevation(), g_gameConfig.getTileMaxElevation());
                };

                for (const auto& item : items) {
                    if (item->isGround() || item->isGroundBorder() || item->isOnBottom())
                        drawStackItem(item);
                }
                for (auto it = items.rbegin(); it != items.rend(); ++it) {
                    if ((*it)->isCommon())
                        drawStackItem(*it);
                }
                for (const auto& item : items) {
                    if (item->isOnTop())
                        drawItem(item, 0);
                }
            }
            g_drawPool.setScaleFactor(oldScale);
        }
    }
    if (!subpixelOffset.isNull())
        g_drawPool.popTransformMatrix();
    g_drawPool.setClipRect(oldClip);
}

void Minimap::draw(const Rect& screenRect, const Position& mapCenter, const float scale, const Color& color, const Point& offset)
{
    if (screenRect.isEmpty())
        return;

    const auto& oldClipRect = g_drawPool.getClipRect();
    g_drawPool.setClipRect(screenRect);

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    g_drawPool.addFilledRect(screenRect, color);

    if (MMBLOCK_SIZE * scale > 1 && mapCenter.isMapPosition()) {
        // Include the neighboring block when the animation reveals the edge of the map.
        const auto firstTile = mapRect.topLeft() - Point(offset.x > 0, offset.y > 0);
        const auto& blockOff = getBlockOffset(firstTile);
        const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
        const auto origin = screenRect.topLeft() - off + offset;

        // Project each shared edge once, avoiding accumulated rounding gaps at fractional zoom.
        for (int y = std::max(0, blockOff.y); y < 65536; y += MMBLOCK_SIZE) {
            const int top = origin.y + int((y - mapRect.top()) * scale);
            if (top > screenRect.bottom())
                break;
            const int bottom = origin.y + int((y + MMBLOCK_SIZE - mapRect.top()) * scale);

            for (int x = std::max(0, blockOff.x); x < 65536; x += MMBLOCK_SIZE) {
                const int left = origin.x + int((x - mapRect.left()) * scale);
                if (left > screenRect.right())
                    break;
                const int right = origin.x + int((x + MMBLOCK_SIZE - mapRect.left()) * scale);

                const auto& pos = Position(x, y, mapCenter.z);

                if (!hasBlock(pos))
                    continue;

                auto& block = getBlock(pos);
                block.update();

                const auto& tex = block.getTexture();
                if (tex) {
                    const Rect src(0, 0, MMBLOCK_SIZE, MMBLOCK_SIZE);
                    const Rect dest(left, top, right - left, bottom - top);
                    g_drawPool.addTexturedRect(dest, tex, src);
                }
            }
        }
    }

    g_drawPool.setClipRect(oldClipRect);
}

Point Minimap::getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, const float scale)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return { -1 };

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& posoff = (Point(pos.x, pos.y) - mapRect.topLeft()) * scale;
    return posoff + screenRect.topLeft() - off + (Point(1) * scale) / 2;
}

Position Minimap::getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, const float scale)
{
    if (screenRect.isEmpty())
        return {};

    const auto& mapRect = calcMapRect(screenRect, mapCenter, scale);
    const auto& off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const auto& pos2d = (point - screenRect.topLeft() + off) / scale + mapRect.topLeft();
    return { pos2d.x, pos2d.y, mapCenter.z };
}

Rect Minimap::getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, const float scale)
{
    if (screenRect.isEmpty() || pos.z != mapCenter.z)
        return {};

    const int tileSize = g_gameConfig.getSpriteSize() * scale;

    Rect tileRect(0, 0, tileSize, tileSize);
    tileRect.moveCenter(getTilePoint(pos, screenRect, mapCenter, scale));
    return tileRect;
}

Rect Minimap::calcMapRect(const Rect& screenRect, const Position& mapCenter, const float scale) const
{
    const int w = screenRect.width() / scale;
    const int h = std::ceil(screenRect.height() / scale);

    Rect mapRect(0, 0, w, h);
    mapRect.moveCenter(Point(mapCenter.x, mapCenter.y));
    return mapRect;
}

void Minimap::updateTile(const Position& pos, const TilePtr& tile)
{
    if (tile)
        updateHdTile(pos, tile);
    MinimapTile minimapTile;
    if (tile) {
        minimapTile.color = tile->getMinimapColorByte();
        minimapTile.flags |= MinimapTileWasSeen;
        if (!tile->isWalkable(true))
            minimapTile.flags |= MinimapTileNotWalkable;
        if (!tile->isPathable())
            minimapTile.flags |= MinimapTileNotPathable;
        minimapTile.speed = std::min<int>(static_cast<int>(std::ceil(tile->getGroundSpeed() / 10.f)), UINT8_MAX);
    } else {
        minimapTile.flags |= MinimapTileNotWalkable | MinimapTileNotPathable;
    }

    if (minimapTile != nulltile) {
        MinimapBlock& block = getBlock(pos);
        const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
        block.updateTile(pos.x - offsetPos.x, pos.y - offsetPos.y, minimapTile);
        block.justSaw();
    }
}

const MinimapTile& Minimap::getTile(const Position& pos)
{
    if (pos.z <= g_gameConfig.getMapMaxZ() && hasBlock(pos)) {
        MinimapBlock& block = getBlock(pos);
        const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
        return block.getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
    }
    return nulltile;
}

std::pair<MinimapBlock_ptr, MinimapTile> Minimap::threadGetTile(const Position& pos)
{
    SpinLock::Guard lock(m_lock);

    if (pos.z <= g_gameConfig.getMapMaxZ() && hasBlock(pos)) {
        const auto& block = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if (block) {
            const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
            return std::make_pair(block, block->getTile(pos.x - offsetPos.x, pos.y - offsetPos.y));
        }
    }
    return std::make_pair(nullptr, nulltile);
}

bool Minimap::loadImage(const std::string& fileName, const Position& topLeft, float colorFactor)
{
    // non pathable colors
    static Color nonPathableColors[] = {
       "#ffff00"sv, // yellow
    };

    // non walkable colors
    static Color nonWalkableColors[] = {
       "#000000"sv, // oil, black
       "#006600"sv, // trees, dark green
       "#ff3300"sv, // walls, red
       "#666666"sv, // mountain, grey
       "#ff6600"sv, // lava, orange
       "#00ff00"sv, // positon
       "#ccffff"sv, // ice, very light blue
    };

    if (colorFactor <= .01f)
        colorFactor = 1.f;

    try {
        const ImagePtr image = Image::load(fileName);

        const uint8_t waterc = Color::to8bit("#3300cc"sv);

        for (int_fast32_t y = -1; ++y < image->getHeight();) {
            for (int_fast32_t x = -1; ++x < image->getWidth();) {
                Color color = *(uint32_t*)image->getPixel(x, y);
                uint8_t c = Color::to8bit(color * colorFactor);
                int flags = 0;

                if (c == waterc || color.a() == 0) {
                    flags |= MinimapTileNotWalkable;
                    c = UINT8_MAX; // alpha
                }

                if (flags != 0) {
                    for (const Color& col : nonWalkableColors) {
                        if (col == color) {
                            flags |= MinimapTileNotWalkable;
                            break;
                        }
                    }
                }

                if (flags != 0) {
                    for (const Color& col : nonPathableColors) {
                        if (col == color) {
                            flags |= MinimapTileNotPathable;
                            break;
                        }
                    }
                }

                if (c == UINT8_MAX)
                    continue;

                Position pos(topLeft.x + x, topLeft.y + y, topLeft.z);
                MinimapBlock& block = getBlock(pos);
                const auto& offsetPos = getBlockOffset(Point(pos.x, pos.y));
                MinimapTile& tile = block.getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
                if (!(tile.flags & MinimapTileWasSeen)) {
                    tile.color = c;
                    tile.flags = flags;
                    block.mustUpdate();
                }
            }
        }
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("failed to load OTMM minimap: {}", e.what());
        return false;
    }
}

void Minimap::saveImage(const std::string&, const Rect&)
{
    //TODO
}

bool Minimap::loadOtmm(const std::string& fileName)
{
    try {
        const FileStreamPtr fin = g_resources.openFile(fileName);
        if (!fin)
            throw Exception("unable to open file");

        fin->cache();

        const uint32_t signature = fin->getU32();
        if (signature != OTMM_SIGNATURE)
            throw Exception("invalid OTMM file");

        const uint16_t start = fin->getU16();
        const uint16_t version = fin->getU16();
        fin->getU32(); // flags

        switch (version) {
            case 1:
            {
                fin->getString(); // description
                break;
            }
            default:
                throw Exception("OTMM version not supported");
        }

        fin->seek(start);

        constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        std::vector<uint8_t> compressBuffer(compressBound(blockSize));
        std::vector<uint8_t> decompressBuffer(blockSize);

        while (true) {
            Position pos;
            pos.x = fin->getU16();
            pos.y = fin->getU16();
            pos.z = fin->getU8();

            // end of file or file is corrupted
            if (!pos.isValid() || pos.z >= g_gameConfig.getMapMaxZ() + 1)
                break;

            MinimapBlock& block = getBlock(pos);
            const uint16_t len = fin->getU16();
            fin->read(compressBuffer.data(), len);

            unsigned long destLen = blockSize;
            const int ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), len);

            if (ret != Z_OK || destLen != blockSize)
                break;

            memcpy(&block.getTiles(), decompressBuffer.data(), blockSize);
            block.mustUpdate();
            block.justSaw();
        }

        fin->close();
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("failed to load OTMM minimap: {}", e.what());
        return false;
    }
}

void Minimap::saveOtmm(const std::string& fileName)
{
    try {
        const FileStreamPtr fin = g_resources.createFile(fileName);
        fin->cache();

        //TODO: compression flag with zlib
        constexpr uint32_t flags = 0;

        // header
        fin->addU32(OTMM_SIGNATURE);
        fin->addU16(0); // data start, will be overwritten later
        fin->addU16(OTMM_VERSION);
        fin->addU32(flags);

        // version 1 header
        fin->addString("OTMM 1.0"); // description

        // go back and rewrite where the map data starts
        const uint32_t start = fin->tell();
        fin->seek(4);
        fin->addU16(start);
        fin->seek(start);

        constexpr uint32_t blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        constexpr uint32_t COMPRESS_LEVEL = 3;
        std::vector<uint8_t> compressBuffer(compressBound(blockSize));

        for (uint_fast8_t z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
            for (const auto& [index, block] : m_tileBlocks[z]) {
                if (!block->wasSeen())
                    continue;

                const auto& pos = getIndexPosition(index, z);
                fin->addU16(pos.x);
                fin->addU16(pos.y);
                fin->addU8(pos.z);

                unsigned long len = blockSize;
                compress2(compressBuffer.data(), &len, (uint8_t*)&block->getTiles(), blockSize, COMPRESS_LEVEL);
                fin->addU16(len);
                fin->write(compressBuffer.data(), len);
            }
        }

        // end of file
        constexpr Position invalidPos;
        fin->addU16(invalidPos.x);
        fin->addU16(invalidPos.y);
        fin->addU8(invalidPos.z);

        fin->flush();

        fin->close();
    } catch (const stdext::exception& e) {
        g_logger.error("failed to save OTMM minimap: {}", e.what());
    }
}
