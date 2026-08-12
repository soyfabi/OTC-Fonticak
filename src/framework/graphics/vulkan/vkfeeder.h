/*
 * Stage 4 of the Vulkan renderer: the BRIDGE between the client's real drawing queue (DrawPool)
 * and the sprite batch (VkSpriteBatch).
 *
 * This is the only translation unit that DELIBERATELY sees both worlds at once: the DrawPool
 * headers (the OpenGL side - states, coordinate buffers, client textures) and the Vulkan batch
 * headers. The "do not mix APIs in one file" rule from vkatlas.h applies everywhere else; the
 * bridge is by definition the place where both ends must meet.
 *
 * How it works (per frame, on the main thread):
 *   1. for each pool in GL drawing order: take over the published DrawObject list
 *      with the same protocol as DrawPoolManager::drawObjects (swap under lock + clear the flag),
 *   2. translate every object with geometry into batch triangles: convert positions to screen
 *      pixels (pools with a GL framebuffer get an affine dest/src mapping instead of the FBO),
 *      convert texture coordinates from source pixels to the atlas region,
 *   3. textures seen for the first time go into the Vulkan atlas (registry by texture uniqueId).
 *
 * What stage 4 DELIBERATELY does not do (noted, not forgotten):
 *   - the LIGHT pool is skipped (lighting needs a separate pass and the MULTIPLY blend mode),
 *   - painter shader programs (effects, outfits) are ignored - we draw without the effect,
 *   - actions (GL lambdas: framebuffer bind/prepare, glDisable etc.) are skipped,
 *   - textures with no source and no pixel copy (e.g. extracted from a GL framebuffer) have
 *     no way into the atlas - the object is skipped with a one-time log.
 */

#pragma once
 // The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
 // dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
 // so it can sit unconditionally on the source list in CMakeLists.
#ifdef WIN32

#include "vkbatch.h"

#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class DrawPool;
class Texture;

class VkDrawFeeder
{
public:
    static VkDrawFeeder& instance();

    // Builds the geometry of the WHOLE frame from all pools into the batch. Call on the main
    // thread, BEFORE VkContext::drawFrame (the batch must be full before the frame is recorded).
    // extent is the swapchain size - the scissors are clamped to it.
    void feedFrame(VkSpriteBatch& batch, const VkExtent2D& extent);

    // Emergency: takes over the lists of ALL pools without drawing (Vulkan dead + no GL).
    // Without consuming the shouldRepaint flags the map thread would wedge in canDrawMap().
    void consumeAllPools();

    VkDrawFeeder(const VkDrawFeeder&) = delete;
    VkDrawFeeder& operator=(const VkDrawFeeder&) = delete;

private:
    VkDrawFeeder() = default;

    // Oversized textures (wider/taller than an atlas layer, e.g. the 5248x64 imbuement icon
    // strip) are stored as a GRID OF CHUNKS. At draw time each triangle picks the chunk that
    // contains its source-space bbox center; UI icon clips never straddle a 1024 px boundary
    // in practice, so the mapping is exact.
    struct BigSlot
    {
        uint32_t texWidth{ 0 };
        uint32_t texHeight{ 0 };
        uint32_t chunk{ 0 };
        uint32_t cols{ 0 };
        uint32_t rows{ 0 };
        std::vector<VkAtlasSlot> slots;
    };

    // Result of resolveSlot: a regular slot OR a multi-chunk entry (exactly one non-empty).
    struct ResolvedSlot
    {
        const VkAtlasSlot* slot{ nullptr };
        const BigSlot* big{ nullptr };
    };

    void feedPool(VkSpriteBatch& batch, DrawPool* pool, const VkExtent2D& extent);

    // Takes over a pool's list (swap + clear the flag) WITHOUT drawing. Necessary for skipped
    // pools (LIGHT): the map thread, via canDrawMap(), waits for the shouldRepaint flag to be consumed.
    void consumePool(DrawPool* pool);

    // Returns the atlas region for a client texture (adding it on first use).
    // An empty result = the texture cannot be drawn (no pixels and no source / atlas full).
    ResolvedSlot resolveSlot(VkSpriteBatch& batch, Texture* texture);

    // Registers a texture larger than an atlas layer as a grid of chunks.
    const BigSlot* registerBigTexture(VkSpriteBatch& batch, uint32_t key, Image* image);

    const VkAtlasSlot* whiteSlot(VkSpriteBatch& batch);

    // Registry of atlas regions by client texture uniqueId. We also keep FAILED entries
    // (slot.valid == false), so we do not try every frame to read a file from disk that is not there.
    std::unordered_map<uint32_t, VkAtlasSlot> m_slots;

    std::unordered_map<uint32_t, BigSlot> m_bigSlots;

    // CONTENT-BASED DEDUPLICATION: pixel hash -> slot. The thing GC cyclically kills and
    // recreates textures (each with a NEW uniqueId), so without this map the same sprites landed
    // in the atlas repeatedly and the atlas grew without end (measured: 11 layers/176 MB after
    // half an hour, 15/240 MB after an hour, occupancy barely 33%). A content hit
    // pins the new uniqueId to an EXISTING region - the atlas converges to the size
    // of the unique content and stops growing.
    std::unordered_map<uint64_t, VkAtlasSlot> m_slotsByContent;

    VkAtlasSlot m_white;

    // One-time logs - without this every skipped texture/shader would flood the log each frame.
    std::unordered_set<uint32_t> m_loggedMissing;
    bool m_loggedShader{ false };
    bool m_loggedGlOnly{ false };
    bool m_loggedSuspectPunch{ false };
    bool m_loggedLight{ false };
    bool m_loggedOverflow{ false };
    bool m_loggedComposition{ false };
    bool m_loggedFlushFail{ false };
    bool m_loggedUnbalancedFb{ false };

    uint64_t m_frame{ 0 };
};

#endif // WIN32
