
// The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
// dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
// so it can sit unconditionally on the source list in CMakeLists.
#ifdef WIN32
#include "vkatlas.h"

#include <framework/core/logger.h>
#include <framework/graphics/image.h>

#include <algorithm>
#include <cstring>

bool VkTextureAtlas::fail(const std::string& reason)
{
    m_error = reason;
    g_logger.warning("[vulkan] atlas: {}", reason);
    terminate();
    return false;
}

bool VkTextureAtlas::init(VkPhysicalDevice physicalDevice, VkDevice device, VkQueue graphicsQueue,
                          VkCommandPool commandPool, const uint32_t requestedSize)
{
    if (m_ready)
        return true;

    if (physicalDevice == VK_NULL_HANDLE || device == VK_NULL_HANDLE ||
        graphicsQueue == VK_NULL_HANDLE || commandPool == VK_NULL_HANDLE)
        return fail("incomplete context passed to the atlas");

    m_physicalDevice = physicalDevice;
    m_device = device;
    m_graphicsQueue = graphicsQueue;
    m_commandPool = commandPool;

    if (!loadFunctions())
        return false;

    // The card's limits are HARD: trying to create an image larger than maxImageDimension2D or
    // with more layers than maxImageArrayLayers is an error that on some drivers ends with
    // the process crashing instead of an error code being returned.
    VkPhysicalDeviceProperties props{};
    vkGetPhysicalDeviceProperties(m_physicalDevice, &props);

    m_size = std::min(requestedSize, props.limits.maxImageDimension2D);
    m_maxLayers = props.limits.maxImageArrayLayers;

    if (m_size == 0 || m_maxLayers == 0)
        return fail("the card does not report sensible image limits");

    if (!createSampler())
        return fail("failed to create the atlas sampler");

    // The first layer is created right away so the atlas has a valid view even before
    // anything lands in it - the caller can then safely build a descriptor.
    m_layers.emplace_back();
    if (!ensureLayerCapacity(1))
        return fail(m_error.empty() ? std::string("failed to create the first atlas layer") : m_error);

    m_ready = true;
    return true;
}

bool VkTextureAtlas::loadFunctions()
{
    const auto fn = [this](const char* name) { return vkGetDeviceProcAddr(m_device, name); };

    m_vkCreateImage = reinterpret_cast<PFN_vkCreateImage>(fn("vkCreateImage"));
    m_vkDestroyImage = reinterpret_cast<PFN_vkDestroyImage>(fn("vkDestroyImage"));
    m_vkGetImageMemoryRequirements = reinterpret_cast<PFN_vkGetImageMemoryRequirements>(fn("vkGetImageMemoryRequirements"));
    m_vkBindImageMemory = reinterpret_cast<PFN_vkBindImageMemory>(fn("vkBindImageMemory"));
    m_vkCreateImageView = reinterpret_cast<PFN_vkCreateImageView>(fn("vkCreateImageView"));
    m_vkDestroyImageView = reinterpret_cast<PFN_vkDestroyImageView>(fn("vkDestroyImageView"));
    m_vkCreateSampler = reinterpret_cast<PFN_vkCreateSampler>(fn("vkCreateSampler"));
    m_vkDestroySampler = reinterpret_cast<PFN_vkDestroySampler>(fn("vkDestroySampler"));

    m_vkCreateBuffer = reinterpret_cast<PFN_vkCreateBuffer>(fn("vkCreateBuffer"));
    m_vkDestroyBuffer = reinterpret_cast<PFN_vkDestroyBuffer>(fn("vkDestroyBuffer"));
    m_vkGetBufferMemoryRequirements = reinterpret_cast<PFN_vkGetBufferMemoryRequirements>(fn("vkGetBufferMemoryRequirements"));
    m_vkBindBufferMemory = reinterpret_cast<PFN_vkBindBufferMemory>(fn("vkBindBufferMemory"));

    m_vkAllocateMemory = reinterpret_cast<PFN_vkAllocateMemory>(fn("vkAllocateMemory"));
    m_vkFreeMemory = reinterpret_cast<PFN_vkFreeMemory>(fn("vkFreeMemory"));
    m_vkMapMemory = reinterpret_cast<PFN_vkMapMemory>(fn("vkMapMemory"));
    m_vkUnmapMemory = reinterpret_cast<PFN_vkUnmapMemory>(fn("vkUnmapMemory"));

    m_vkAllocateCommandBuffers = reinterpret_cast<PFN_vkAllocateCommandBuffers>(fn("vkAllocateCommandBuffers"));
    m_vkFreeCommandBuffers = reinterpret_cast<PFN_vkFreeCommandBuffers>(fn("vkFreeCommandBuffers"));
    m_vkBeginCommandBuffer = reinterpret_cast<PFN_vkBeginCommandBuffer>(fn("vkBeginCommandBuffer"));
    m_vkEndCommandBuffer = reinterpret_cast<PFN_vkEndCommandBuffer>(fn("vkEndCommandBuffer"));
    m_vkQueueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(fn("vkQueueSubmit"));
    m_vkQueueWaitIdle = reinterpret_cast<PFN_vkQueueWaitIdle>(fn("vkQueueWaitIdle"));

    m_vkCmdPipelineBarrier = reinterpret_cast<PFN_vkCmdPipelineBarrier>(fn("vkCmdPipelineBarrier"));
    m_vkCmdCopyBufferToImage = reinterpret_cast<PFN_vkCmdCopyBufferToImage>(fn("vkCmdCopyBufferToImage"));
    m_vkCmdCopyImage = reinterpret_cast<PFN_vkCmdCopyImage>(fn("vkCmdCopyImage"));

    // We check the full set ONCE, at startup - otherwise a single missing function would only
    // reveal itself later as a jump to nullptr in the middle of sprite loading.
    if (!m_vkCreateImage || !m_vkDestroyImage || !m_vkGetImageMemoryRequirements || !m_vkBindImageMemory ||
        !m_vkCreateImageView || !m_vkDestroyImageView || !m_vkCreateSampler || !m_vkDestroySampler ||
        !m_vkCreateBuffer || !m_vkDestroyBuffer || !m_vkGetBufferMemoryRequirements || !m_vkBindBufferMemory ||
        !m_vkAllocateMemory || !m_vkFreeMemory || !m_vkMapMemory || !m_vkUnmapMemory ||
        !m_vkAllocateCommandBuffers || !m_vkFreeCommandBuffers ||
        !m_vkBeginCommandBuffer || !m_vkEndCommandBuffer || !m_vkQueueSubmit || !m_vkQueueWaitIdle ||
        !m_vkCmdPipelineBarrier || !m_vkCmdCopyBufferToImage || !m_vkCmdCopyImage)
        return fail("missing functions required to operate the atlas");

    // INSTANCE functions, not device ones - I take them from vkloader's globals.
    if (!vkGetPhysicalDeviceMemoryProperties || !vkGetPhysicalDeviceProperties)
        return fail("missing physical-device property functions");

    return true;
}

uint32_t VkTextureAtlas::findMemoryType(const uint32_t typeFilter, const VkMemoryPropertyFlags properties) const
{
    VkPhysicalDeviceMemoryProperties memProps{};
    vkGetPhysicalDeviceMemoryProperties(m_physicalDevice, &memProps);

    for (uint32_t i = 0; i < memProps.memoryTypeCount; ++i) {
        if ((typeFilter & (1u << i)) && (memProps.memoryTypes[i].propertyFlags & properties) == properties)
            return i;
    }

    return UINT32_MAX;
}

bool VkTextureAtlas::createBuffer(const VkDeviceSize size, const VkBufferUsageFlags usage,
                                  const VkMemoryPropertyFlags properties,
                                  VkBuffer& buffer, VkDeviceMemory& memory)
{
    VkBufferCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    info.size = size;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (m_vkCreateBuffer(m_device, &info, nullptr, &buffer) != VK_SUCCESS)
        return false;

    VkMemoryRequirements req{};
    m_vkGetBufferMemoryRequirements(m_device, buffer, &req);

    const uint32_t typeIndex = findMemoryType(req.memoryTypeBits, properties);
    if (typeIndex == UINT32_MAX)
        return false;

    VkMemoryAllocateInfo alloc{};
    alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = typeIndex;

    if (m_vkAllocateMemory(m_device, &alloc, nullptr, &memory) != VK_SUCCESS)
        return false;

    return m_vkBindBufferMemory(m_device, buffer, memory, 0) == VK_SUCCESS;
}

VkCommandBuffer VkTextureAtlas::beginOneShot()
{
    VkCommandBufferAllocateInfo alloc{};
    alloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc.commandPool = m_commandPool;
    alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc.commandBufferCount = 1;

    VkCommandBuffer cmd = VK_NULL_HANDLE;
    if (m_vkAllocateCommandBuffers(m_device, &alloc, &cmd) != VK_SUCCESS)
        return VK_NULL_HANDLE;

    VkCommandBufferBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    if (m_vkBeginCommandBuffer(cmd, &begin) != VK_SUCCESS) {
        m_vkFreeCommandBuffers(m_device, m_commandPool, 1, &cmd);
        return VK_NULL_HANDLE;
    }

    return cmd;
}

bool VkTextureAtlas::endOneShot(VkCommandBuffer cmd)
{
    bool ok = m_vkEndCommandBuffer(cmd) == VK_SUCCESS;

    if (ok) {
        VkSubmitInfo submit{};
        submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;

        // Waiting for the queue to drain is acceptable here because it happens ONCE PER BATCH
        // (not once per sprite) and during loading, when nothing is being drawn anyway. An
        // asynchronous version (fence + separate transfer queue) is a topic for later.
        ok = m_vkQueueSubmit(m_graphicsQueue, 1, &submit, VK_NULL_HANDLE) == VK_SUCCESS &&
             m_vkQueueWaitIdle(m_graphicsQueue) == VK_SUCCESS;
    }

    m_vkFreeCommandBuffers(m_device, m_commandPool, 1, &cmd);
    return ok;
}

void VkTextureAtlas::barrier(VkCommandBuffer cmd, VkImage image, const uint32_t layerCount,
                             const VkImageLayout oldLayout, const VkImageLayout newLayout,
                             const VkAccessFlags srcAccess, const VkAccessFlags dstAccess,
                             const VkPipelineStageFlags srcStage, const VkPipelineStageFlags dstStage) const
{
    VkImageMemoryBarrier b{};
    b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = image;
    b.oldLayout = oldLayout;
    b.newLayout = newLayout;
    b.srcAccessMask = srcAccess;
    b.dstAccessMask = dstAccess;
    b.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    b.subresourceRange.levelCount = 1;
    b.subresourceRange.layerCount = layerCount;

    m_vkCmdPipelineBarrier(cmd, srcStage, dstStage, 0, 0, nullptr, 0, nullptr, 1, &b);
}

bool VkTextureAtlas::createSampler()
{
    VkSamplerCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    // NEAREST, because we render pixel art - linear filtering blurs the sprites
    // AND would pull in neighbors from the atlas, since in an atlas the neighbor sits right next
    // to you, not past the edge.
    info.magFilter = VK_FILTER_NEAREST;
    info.minFilter = VK_FILTER_NEAREST;
    info.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    info.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    info.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    info.anisotropyEnable = VK_FALSE;
    info.borderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
    info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;

    // The sampler is NOT tied to a specific image, so it survives atlas growth
    // and does not need to be recreated together with the view.
    return m_vkCreateSampler(m_device, &info, nullptr, &m_sampler) == VK_SUCCESS;
}

bool VkTextureAtlas::createView()
{
    VkImageViewCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    info.image = m_image;
    // 2D_ARRAY even with a single layer: the shader declares sampler2DArray, so the view type
    // must match ALWAYS, including before we add a second layer.
    info.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    // UNORM, not SRGB: color arithmetic parity with the GL path - see the comment at the
    // swapchain format selection in vkcontext.cpp.
    info.format = VK_FORMAT_R8G8B8A8_UNORM;
    info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    info.subresourceRange.levelCount = 1;
    info.subresourceRange.layerCount = m_gpuLayers;

    return m_vkCreateImageView(m_device, &info, nullptr, &m_view) == VK_SUCCESS;
}

bool VkTextureAtlas::ensureLayerCapacity(const uint32_t needed)
{
    if (needed <= m_gpuLayers)
        return true;

    if (needed > m_maxLayers) {
        m_error = "array image layer limit exceeded";
        g_logger.warning("[vulkan] atlas: {} layers needed, the card allows at most {}", needed, m_maxLayers);
        return false;
    }

    // A new image with more layers. We grow by exactly as much as is needed (rather than
    // doubling), because at 2048 a single layer is a whole 16 MB of card memory - doubling could
    // waste more than the entire atlas saves.
    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
    imageInfo.extent = { m_size, m_size, 1 };
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = needed;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    // TRANSFER_SRC is needed not for drawing but for the NEXT growth - the old image
    // must serve as the copy source. Without this flag growth number two would be impossible.
    imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                      VK_IMAGE_USAGE_SAMPLED_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkImage newImage = VK_NULL_HANDLE;
    if (m_vkCreateImage(m_device, &imageInfo, nullptr, &newImage) != VK_SUCCESS) {
        m_error = "failed to create the atlas image";
        return false;
    }

    VkMemoryRequirements req{};
    m_vkGetImageMemoryRequirements(m_device, newImage, &req);

    const uint32_t typeIndex = findMemoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VkDeviceMemory newMemory = VK_NULL_HANDLE;

    VkMemoryAllocateInfo alloc{};
    alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = typeIndex;

    if (typeIndex == UINT32_MAX ||
        m_vkAllocateMemory(m_device, &alloc, nullptr, &newMemory) != VK_SUCCESS ||
        m_vkBindImageMemory(m_device, newImage, newMemory, 0) != VK_SUCCESS) {
        if (newMemory != VK_NULL_HANDLE)
            m_vkFreeMemory(m_device, newMemory, nullptr);
        m_vkDestroyImage(m_device, newImage, nullptr);
        m_error = "failed to allocate atlas memory";
        return false;
    }

    const VkCommandBuffer cmd = beginOneShot();
    if (cmd == VK_NULL_HANDLE) {
        m_vkFreeMemory(m_device, newMemory, nullptr);
        m_vkDestroyImage(m_device, newImage, nullptr);
        m_error = "failed to create a command buffer for atlas growth";
        return false;
    }

    barrier(cmd, newImage, needed,
            VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            0, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

    if (m_gpuLayers > 0) {
        // The old image takes the source role. We know its layout exactly (m_layout), so the barrier
        // is correct regardless of whether it was previously read by a shader or has only just
        // been written by a copy.
        barrier(cmd, m_image, m_gpuLayers,
                m_layout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

        // One region covers ALL old layers at once - copying layer by layer
        // would give exactly the same result, just with an n-times longer region list.
        VkImageCopy region{};
        region.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.srcSubresource.layerCount = m_gpuLayers;
        region.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        region.dstSubresource.layerCount = m_gpuLayers;
        region.extent = { m_size, m_size, 1 };

        m_vkCmdCopyImage(cmd, m_image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                         newImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    }

    barrier(cmd, newImage, needed,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

    if (!endOneShot(cmd)) {
        m_vkFreeMemory(m_device, newMemory, nullptr);
        m_vkDestroyImage(m_device, newImage, nullptr);
        m_error = "copying layers during atlas growth failed";
        return false;
    }

    // Only NOW can the old resources be released: endOneShot waited on the queue, so the copy
    // has definitely finished and nothing holds them anymore.
    if (m_view != VK_NULL_HANDLE)
        m_vkDestroyImageView(m_device, m_view, nullptr);
    if (m_image != VK_NULL_HANDLE)
        m_vkDestroyImage(m_device, m_image, nullptr);
    if (m_memory != VK_NULL_HANDLE)
        m_vkFreeMemory(m_device, m_memory, nullptr);

    m_image = newImage;
    m_memory = newMemory;
    m_gpuLayers = needed;
    m_gpuBytes = req.size;
    m_layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    m_view = VK_NULL_HANDLE;

    if (!createView()) {
        m_error = "failed to create the atlas view";
        return false;
    }

    // The view is NEW, so any descriptor pointing at the old one is now stale.
    // The generation number is the only way the caller can find out about it.
    ++m_generation;

    return true;
}

bool VkTextureAtlas::allocateRegion(const uint32_t w, const uint32_t h,
                                    uint32_t& outLayer, uint32_t& outX, uint32_t& outY)
{
    // The padding is counted into the occupied space, not into the region itself: a tile takes
    // w x h pixels, and the next one starts kPadding further.
    const uint32_t stepX = w + kPadding;
    const uint32_t stepY = h + kPadding;

    if (w > m_size || h > m_size)
        return false;

    const auto placeInLayer = [&](Layer& target, const uint32_t layerIndex) -> bool {
        for (Shelf& shelf : target.shelves) {
            // A shelf fits when the tile is not taller than it and fits in the remaining width.
            if (stepY <= shelf.height && shelf.cursorX + stepX <= m_size) {
                outLayer = layerIndex;
                outX = shelf.cursorX;
                outY = shelf.y;
                shelf.cursorX += stepX;
                return true;
            }
        }

        if (target.usedY + stepY <= m_size) {
            // A new shelf takes the height of its FIRST tile - which is why inserting tallest-first
            // packs best. Our API is incremental, so we cannot sort the input;
            // with sprites of uniform height it does not matter anyway.
            target.shelves.push_back(Shelf{ target.usedY, stepY, stepX });
            outLayer = layerIndex;
            outX = 0;
            outY = target.usedY;
            target.usedY += stepY;
            return true;
        }

        return false;
    };

    // We try ALL layers, oldest first. Previously only the last one was packed
    // and occupancy sat at ~34% - every new shelf left dead scraps behind it.
    // Cost: O(layers x shelves) per insertion, but insertions are RARE (content-based
    // deduplication in the feeder means every unique sprite enters once per session).
    for (size_t i = 0; i < m_layers.size(); ++i) {
        if (placeInLayer(m_layers[i], static_cast<uint32_t>(i)))
            return true;
    }

    // All layers full - we add the next one. GPU memory only grows at flush(),
    // so the reservation itself is free.
    if (m_layers.size() + 1 > m_maxLayers)
        return false;

    m_layers.emplace_back();
    return placeInLayer(m_layers.back(), static_cast<uint32_t>(m_layers.size() - 1));
}

VkAtlasSlot VkTextureAtlas::add(const ImagePtr& image)
{
    VkAtlasSlot slot;

    if (!image || image->getWidth() <= 0 || image->getHeight() <= 0)
        return slot;

    const uint32_t w = static_cast<uint32_t>(image->getWidth());
    const uint32_t h = static_cast<uint32_t>(image->getHeight());
    const int bpp = image->getBpp();

    if (bpp == 4)
        return add(image->getPixelData(), w, h);

    // Vulkan has no 24-bit format with guaranteed support, so a PNG without an alpha channel
    // gets expanded to RGBA. The buffer is temporary - add() copies the pixels into its queue anyway.
    if (bpp != 3) {
        g_logger.warning("[vulkan] atlas: image has {} bytes per pixel - skipping", bpp);
        return slot;
    }

    const size_t pixelCount = static_cast<size_t>(w) * h;
    std::vector<uint8_t> rgba(pixelCount * 4);
    const uint8_t* source = image->getPixelData();

    for (size_t i = 0; i < pixelCount; ++i) {
        rgba[i * 4 + 0] = source[i * 3 + 0];
        rgba[i * 4 + 1] = source[i * 3 + 1];
        rgba[i * 4 + 2] = source[i * 3 + 2];
        rgba[i * 4 + 3] = 255;
    }

    return add(rgba.data(), w, h);
}

VkAtlasSlot VkTextureAtlas::add(const uint8_t* rgba, const uint32_t width, const uint32_t height)
{
    VkAtlasSlot slot;

    if (!m_ready || rgba == nullptr || width == 0 || height == 0)
        return slot;

    uint32_t layer = 0;
    uint32_t x = 0;
    uint32_t y = 0;

    if (!allocateRegion(width, height, layer, x, y)) {
        g_logger.warning("[vulkan] atlas: {}x{} does not fit in the {}x{} atlas (or we ran out of layers)",
                         width, height, m_size, m_size);
        return slot;
    }

    const size_t bytes = static_cast<size_t>(width) * height * 4;
    const size_t offset = m_pendingPixels.size();

    m_pendingPixels.resize(offset + bytes);
    std::memcpy(m_pendingPixels.data() + offset, rgba, bytes);

    VkBufferImageCopy copy{};
    // bufferOffset must be a multiple of the texel size (4 B). Every appended block has
    // size w*h*4, so the offsets stay aligned by themselves and no padding is needed.
    copy.bufferOffset = offset;
    copy.bufferRowLength = 0;    // 0 = rows tightly packed
    copy.bufferImageHeight = 0;
    copy.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copy.imageSubresource.mipLevel = 0;
    copy.imageSubresource.baseArrayLayer = layer;
    copy.imageSubresource.layerCount = 1;
    copy.imageOffset = { static_cast<int32_t>(x), static_cast<int32_t>(y), 0 };
    copy.imageExtent = { width, height, 1 };

    m_pendingCopies.push_back(copy);

    ++m_tileCount;
    m_tilePixels += static_cast<uint64_t>(width) * height;

    const float inv = 1.0f / static_cast<float>(m_size);
    slot.uvMin[0] = static_cast<float>(x) * inv;
    slot.uvMin[1] = static_cast<float>(y) * inv;
    slot.uvMax[0] = static_cast<float>(x + width) * inv;
    slot.uvMax[1] = static_cast<float>(y + height) * inv;
    slot.layer = layer;
    slot.width = width;
    slot.height = height;
    slot.valid = true;

    // Automatic upload so the CPU-side queue does not grow past the threshold.
    if (m_pendingPixels.size() >= kFlushThreshold)
        flush();

    return slot;
}

bool VkTextureAtlas::flush()
{
    if (!m_ready)
        return false;

    // Growth must go BEFORE the copy: regions may point at layers the current
    // image does not have yet.
    if (!ensureLayerCapacity(static_cast<uint32_t>(m_layers.size())))
        return false;

    if (m_pendingCopies.empty())
        return true;

    VkBuffer staging = VK_NULL_HANDLE;
    VkDeviceMemory stagingMemory = VK_NULL_HANDLE;

    const auto releaseStaging = [&] {
        if (staging != VK_NULL_HANDLE)
            m_vkDestroyBuffer(m_device, staging, nullptr);
        if (stagingMemory != VK_NULL_HANDLE)
            m_vkFreeMemory(m_device, stagingMemory, nullptr);
    };

    const VkDeviceSize bytes = m_pendingPixels.size();

    if (!createBuffer(bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                      staging, stagingMemory)) {
        releaseStaging();
        m_error = "failed to create the atlas staging buffer";
        return false;
    }

    void* mapped = nullptr;
    if (m_vkMapMemory(m_device, stagingMemory, 0, bytes, 0, &mapped) != VK_SUCCESS) {
        releaseStaging();
        m_error = "failed to map the atlas staging buffer";
        return false;
    }

    std::memcpy(mapped, m_pendingPixels.data(), static_cast<size_t>(bytes));
    m_vkUnmapMemory(m_device, stagingMemory);

    const VkCommandBuffer cmd = beginOneShot();
    if (cmd == VK_NULL_HANDLE) {
        releaseStaging();
        m_error = "failed to create a command buffer for uploading tiles";
        return false;
    }

    barrier(cmd, m_image, m_gpuLayers,
            m_layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

    // HERE is the whole saving: all tiles of this batch go in ONE copy command.
    m_vkCmdCopyBufferToImage(cmd, staging, m_image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                             static_cast<uint32_t>(m_pendingCopies.size()), m_pendingCopies.data());

    barrier(cmd, m_image, m_gpuLayers,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

    const bool uploaded = endOneShot(cmd);
    releaseStaging();

    if (!uploaded) {
        m_error = "uploading tiles to the atlas failed";
        return false;
    }

    m_layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    // We release the CPU-side copies IMMEDIATELY - keeping them is exactly the same
    // disease we are curing on the GL driver side. shrink_to_fit, because clear() alone
    // would leave the reserved capacity in place (here up to the 16 MB threshold).
    m_pendingPixels.clear();
    m_pendingPixels.shrink_to_fit();
    m_pendingCopies.clear();
    m_pendingCopies.shrink_to_fit();

    return true;
}

void VkTextureAtlas::clear()
{
    m_layers.clear();
    m_layers.emplace_back();
    m_tileCount = 0;
    m_tilePixels = 0;
    m_pendingPixels.clear();
    m_pendingPixels.shrink_to_fit();
    m_pendingCopies.clear();
    m_pendingCopies.shrink_to_fit();

    // We do NOT give the layers back: m_gpuLayers stays. Old pixels remain in card memory, but
    // they are unreachable (no slot points at them anymore), and they will be overwritten
    // as the atlas fills up again. Releasing and re-taking 16 MB blocks over and over would be worse.
}

float VkTextureAtlas::getOccupancy() const
{
    const uint64_t total = static_cast<uint64_t>(m_size) * m_size * m_layers.size();
    if (total == 0)
        return 0.0f;

    return static_cast<float>(static_cast<double>(m_tilePixels) / static_cast<double>(total));
}

bool VkTextureAtlas::reset()
{
    if (!m_ready || m_device == VK_NULL_HANDLE)
        return false;

    // Nothing to do if the atlas is already at its minimum footprint.
    if (m_gpuLayers <= 1 && m_tileCount == 0)
        return true;

    // Wait for the card to finish every frame still sampling the current image, so destroying
    // it is safe. Rare (only when the atlas crossed the growth threshold), so the stall is fine.
    if (vkDeviceWaitIdle)
        vkDeviceWaitIdle(m_device);

    if (m_view != VK_NULL_HANDLE && m_vkDestroyImageView) {
        m_vkDestroyImageView(m_device, m_view, nullptr);
        m_view = VK_NULL_HANDLE;
    }
    if (m_image != VK_NULL_HANDLE && m_vkDestroyImage) {
        m_vkDestroyImage(m_device, m_image, nullptr);
        m_image = VK_NULL_HANDLE;
    }
    if (m_memory != VK_NULL_HANDLE && m_vkFreeMemory) {
        m_vkFreeMemory(m_device, m_memory, nullptr);
        m_memory = VK_NULL_HANDLE;
    }

    // Reset all bookkeeping to a blank atlas, then build ONE fresh layer.
    m_layers.clear();
    m_layers.emplace_back();
    m_pendingPixels.clear();
    m_pendingPixels.shrink_to_fit();
    m_pendingCopies.clear();
    m_pendingCopies.shrink_to_fit();
    m_gpuLayers = 0;
    m_gpuBytes = 0;
    m_tileCount = 0;
    m_tilePixels = 0;
    m_layout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (!ensureLayerCapacity(1)) {
        m_error = "atlas rebuild failed to create the first layer";
        return false;
    }

    // ensureLayerCapacity already bumped m_generation, so the caller's descriptor re-syncs.
    return true;
}

void VkTextureAtlas::terminate()
{
    // Note: we do NOT call vkDeviceWaitIdle here - VkContext::terminate does it before calling us,
    // and on an init() failure nothing has reached the drawing queue yet.
    if (m_device == VK_NULL_HANDLE) {
        m_ready = false;
        return;
    }

    if (m_view != VK_NULL_HANDLE && m_vkDestroyImageView) {
        m_vkDestroyImageView(m_device, m_view, nullptr);
        m_view = VK_NULL_HANDLE;
    }

    if (m_sampler != VK_NULL_HANDLE && m_vkDestroySampler) {
        m_vkDestroySampler(m_device, m_sampler, nullptr);
        m_sampler = VK_NULL_HANDLE;
    }

    if (m_image != VK_NULL_HANDLE && m_vkDestroyImage) {
        m_vkDestroyImage(m_device, m_image, nullptr);
        m_image = VK_NULL_HANDLE;
    }

    if (m_memory != VK_NULL_HANDLE && m_vkFreeMemory) {
        m_vkFreeMemory(m_device, m_memory, nullptr);
        m_memory = VK_NULL_HANDLE;
    }

    m_layers.clear();
    m_pendingPixels.clear();
    m_pendingPixels.shrink_to_fit();
    m_pendingCopies.clear();
    m_pendingCopies.shrink_to_fit();

    m_gpuLayers = 0;
    m_gpuBytes = 0;
    m_tileCount = 0;
    m_tilePixels = 0;
    m_layout = VK_IMAGE_LAYOUT_UNDEFINED;

    // We do NOT destroy handles borrowed from VkContext - they are not ours. We only zero them
    // so that a repeated terminate() is safe.
    m_device = VK_NULL_HANDLE;
    m_physicalDevice = VK_NULL_HANDLE;
    m_graphicsQueue = VK_NULL_HANDLE;
    m_commandPool = VK_NULL_HANDLE;

    m_ready = false;
}

#endif // WIN32
