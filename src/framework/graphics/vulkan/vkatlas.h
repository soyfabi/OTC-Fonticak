/*
 * Stage 3 of the Vulkan renderer: TEXTURE ATLAS. This is the core of the whole project, not just
 * another feature.
 *
 * WHY we are writing this at all:
 * The OpenGL path creates a SEPARATE texture object for every animation phase of every thing - with
 * ~57 thousand phases the driver holds tens of thousands of objects AND its own CPU-side mirror
 * of the pixels (~250-300 MB that never show up in the client's counters). Each such object
 * also means a separate texture bind, i.e. a separate draw call. The atlas removes both problems
 * at once: the pixels live in ONE object, the driver has nothing to duplicate, and drawing can
 * go in a single batch.
 *
 * CHOICE: a single VkImage of type 2D ARRAY, grown by adding layers.
 * Two routes were considered and this one wins for a concrete reason:
 *   (a) a separate VkImage per layer - each needs its own descriptor, so either we swap
 *       descriptors between draw calls (losing the whole batching gain), or we reach for
 *       descriptor indexing (VK_EXT_descriptor_indexing) - which is OUTSIDE the Vulkan 1.1
 *       core that VkContext declares, and requires extra device features.
 *   (b) one 2D_ARRAY image - ONE view, ONE descriptor, one bind; the layer number
 *       rides in the vertex, so the layer count does NOT AFFECT the number of draw calls.
 * The price of (b): a VkImage's layer count is fixed at creation and cannot be increased.
 * Growth therefore means a new image + copying the old layers over (vkCmdCopyImage). We pay this
 * rarely (one 2048x2048 layer holds ~4 thousand 32x32 sprites) and only during loading,
 * and in exchange we do not reserve memory up front for layers that may never exist - which
 * matters at 16 MB per layer, because saving memory is the whole point.
 *
 * UPLOADS: batched, not one sprite at a time. add() only reserves a region and appends the pixels
 * to a pending buffer; only flush() makes ONE staging buffer, ONE
 * vkCmdCopyBufferToImage call with many regions, and ONE queue submission. Uploading sprite by
 * sprite would mean 57 thousand vkQueueWaitIdle calls, i.e. loading measured in minutes.
 */

#pragma once
 // The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
 // dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
 // so it can sit unconditionally on the source list in CMakeLists.
#ifdef WIN32


#include "vkloader.h"

#include <memory>
#include <string>
#include <vector>

// A forward declaration instead of <framework/graphics/declarations.h>: that header drags in
// glutil.h, i.e. the OpenGL headers. The Vulkan path must be fully independent of them, so the
// two APIs cannot accidentally be mixed in one translation unit. The alias is identical
// to the one in declarations.h, so both headers can coexist in a single file.
class Image;
using ImagePtr = std::shared_ptr<Image>;

// The spot one image occupies in the atlas. Everything the shader needs:
// a rectangle in normalized [0,1] coordinates and the layer number.
struct VkAtlasSlot
{
    float uvMin[2]{ 0.0f, 0.0f };
    float uvMax[2]{ 0.0f, 0.0f };
    uint32_t layer{ 0 };
    uint32_t width{ 0 };   // size in pixels - the caller usually wants to draw 1:1
    uint32_t height{ 0 };
    bool valid{ false };   // false = the image did not fit or could not be loaded
};

class VkTextureAtlas
{
public:
    // requestedSize is the side of a square layer in pixels; it gets clamped to the card's limit.
    // commandPool and graphicsQueue are BORROWED from VkContext (used only during uploads).
    bool init(VkPhysicalDevice physicalDevice, VkDevice device, VkQueue graphicsQueue,
              VkCommandPool commandPool, uint32_t requestedSize);

    // Reserves a region and QUEUES the pixels for upload. The returned slot is valid immediately
    // (the coordinates are known from the moment of reservation), but the pixels are on the card
    // only after flush().
    VkAtlasSlot add(const ImagePtr& image);
    VkAtlasSlot add(const uint8_t* rgba, uint32_t width, uint32_t height);

    // Uploads everything waiting in the queue, adding layers when needed.
    // On return the image is in SHADER_READ_ONLY_OPTIMAL layout and ready for sampling.
    bool flush();

    // Resets the region allocator. The layers and GPU memory STAY - that is the whole point:
    // reloading the sprite set must not keep giving memory back to the driver and taking it again.
    void clear();

    // Full rebuild: frees ALL GPU layers back to a single fresh one and resets the allocator.
    // Unlike clear() this ACTUALLY releases card memory - used to cap unbounded atlas growth
    // (the atlas never shrinks on its own as new sprites keep coming into view). Waits for the
    // device to go idle first, so no in-flight frame is sampling the image being destroyed.
    // Bumps the generation, so the descriptor is re-synced by the caller.
    bool reset();

    void terminate();

    bool isReady() const { return m_ready; }
    const std::string& getError() const { return m_error; }

    VkImageView getView() const { return m_view; }
    VkSampler getSampler() const { return m_sampler; }

    // Grows every time the image view has been recreated (growth by a layer).
    // A caller holding a descriptor must then rewrite it - otherwise it would sample a freed view.
    uint32_t getGeneration() const { return m_generation; }

    uint32_t getTileCount() const { return m_tileCount; }
    uint32_t getLayerCount() const { return static_cast<uint32_t>(m_layers.size()); }
    uint32_t getSize() const { return m_size; }
    VkDeviceSize getGpuBytes() const { return m_gpuBytes; }

    // How many pixels the tiles actually occupy relative to the area of all layers (0..1).
    // A packing-quality metric - bad packing shows up immediately as low occupancy.
    float getOccupancy() const;

private:
    // A shelf cannot be taller than the layer, and 1 pixel of padding protects against
    // "picking up" the neighbor when downscaling (a sample can land just outside the region).
    static constexpr uint32_t kPadding = 1;

    // Automatic upload threshold: 16 MB of pending pixels. Without it, loading the whole sprite
    // set would hold hundreds of MB of CPU-side copies - which is exactly what the atlas
    // is supposed to get rid of.
    static constexpr size_t kFlushThreshold = 16u * 1024u * 1024u;

    // A single shelf: a strip of fixed height, filled from left to right.
    // Shelf packing was chosen deliberately: it is O(1) per insertion and does not require
    // keeping a tree of free rectangles, and Tibia sprites are almost uniform in height (32/64 px),
    // so in the case we care about it wastes very little space.
    struct Shelf
    {
        uint32_t y{ 0 };
        uint32_t height{ 0 };
        uint32_t cursorX{ 0 };
    };

    struct Layer
    {
        std::vector<Shelf> shelves;
        uint32_t usedY{ 0 };
    };

    bool fail(const std::string& reason);
    bool loadFunctions();

    // Finds a spot for a w+h image. Adds a shelf or a layer when needed.
    bool allocateRegion(uint32_t w, uint32_t h, uint32_t& outLayer, uint32_t& outX, uint32_t& outY);

    // Recreates the image with the requested layer count and moves the old layers' contents.
    // Does nothing when there are already enough layers.
    bool ensureLayerCapacity(uint32_t needed);

    bool createSampler();
    bool createView();

    bool createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties,
                      VkBuffer& buffer, VkDeviceMemory& memory);
    uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) const;

    VkCommandBuffer beginOneShot();
    bool endOneShot(VkCommandBuffer cmd);

    // A barrier on ALL layers of the given image - we keep the whole image's layout as
    // a single value, because we never need different layouts on different layers.
    void barrier(VkCommandBuffer cmd, VkImage image, uint32_t layerCount,
                 VkImageLayout oldLayout, VkImageLayout newLayout,
                 VkAccessFlags srcAccess, VkAccessFlags dstAccess,
                 VkPipelineStageFlags srcStage, VkPipelineStageFlags dstStage) const;

    // --- borrowed from VkContext (we do not destroy these) ---
    VkPhysicalDevice m_physicalDevice{ VK_NULL_HANDLE };
    VkDevice m_device{ VK_NULL_HANDLE };
    VkQueue m_graphicsQueue{ VK_NULL_HANDLE };
    VkCommandPool m_commandPool{ VK_NULL_HANDLE };

    // --- own resources ---
    VkImage m_image{ VK_NULL_HANDLE };
    VkDeviceMemory m_memory{ VK_NULL_HANDLE };
    VkImageView m_view{ VK_NULL_HANDLE };
    VkSampler m_sampler{ VK_NULL_HANDLE };

    // The layout of the WHOLE image. Without it every barrier would have to guess the starting
    // state, and passing a wrong oldLayout means instant garbage on screen.
    VkImageLayout m_layout{ VK_IMAGE_LAYOUT_UNDEFINED };

    uint32_t m_size{ 0 };          // side of a layer in pixels
    uint32_t m_maxLayers{ 0 };     // card limit (maxImageArrayLayers)
    uint32_t m_gpuLayers{ 0 };     // how many layers the CURRENT VkImage has
    VkDeviceSize m_gpuBytes{ 0 };  // actual size of the image memory allocation
    uint32_t m_generation{ 0 };
    uint32_t m_tileCount{ 0 };
    uint64_t m_tilePixels{ 0 };    // sum of tile areas - for computing occupancy

    std::vector<Layer> m_layers;

    // Pending upload: the pixels lie tightly one after another, and each region points
    // at its own offset within this buffer.
    std::vector<uint8_t> m_pendingPixels;
    std::vector<VkBufferImageCopy> m_pendingCopies;

    bool m_ready{ false };
    std::string m_error;

    // --- device functions (local, as in VkContext/VkRectRenderer) ---
    PFN_vkCreateImage m_vkCreateImage{ nullptr };
    PFN_vkDestroyImage m_vkDestroyImage{ nullptr };
    PFN_vkGetImageMemoryRequirements m_vkGetImageMemoryRequirements{ nullptr };
    PFN_vkBindImageMemory m_vkBindImageMemory{ nullptr };
    PFN_vkCreateImageView m_vkCreateImageView{ nullptr };
    PFN_vkDestroyImageView m_vkDestroyImageView{ nullptr };
    PFN_vkCreateSampler m_vkCreateSampler{ nullptr };
    PFN_vkDestroySampler m_vkDestroySampler{ nullptr };

    PFN_vkCreateBuffer m_vkCreateBuffer{ nullptr };
    PFN_vkDestroyBuffer m_vkDestroyBuffer{ nullptr };
    PFN_vkGetBufferMemoryRequirements m_vkGetBufferMemoryRequirements{ nullptr };
    PFN_vkBindBufferMemory m_vkBindBufferMemory{ nullptr };

    PFN_vkAllocateMemory m_vkAllocateMemory{ nullptr };
    PFN_vkFreeMemory m_vkFreeMemory{ nullptr };
    PFN_vkMapMemory m_vkMapMemory{ nullptr };
    PFN_vkUnmapMemory m_vkUnmapMemory{ nullptr };

    PFN_vkAllocateCommandBuffers m_vkAllocateCommandBuffers{ nullptr };
    PFN_vkFreeCommandBuffers m_vkFreeCommandBuffers{ nullptr };
    PFN_vkBeginCommandBuffer m_vkBeginCommandBuffer{ nullptr };
    PFN_vkEndCommandBuffer m_vkEndCommandBuffer{ nullptr };
    PFN_vkQueueSubmit m_vkQueueSubmit{ nullptr };
    PFN_vkQueueWaitIdle m_vkQueueWaitIdle{ nullptr };

    PFN_vkCmdPipelineBarrier m_vkCmdPipelineBarrier{ nullptr };
    PFN_vkCmdCopyBufferToImage m_vkCmdCopyBufferToImage{ nullptr };
    PFN_vkCmdCopyImage m_vkCmdCopyImage{ nullptr };
};

#endif // WIN32
