
// The whole Vulkan renderer is for now Win32-only (window surface), and the vulkan-headers
// dependency is windows-only in vcpkg.json. Outside Windows the file compiles to nothing,
// which lets it stay unconditionally on the source list in CMakeLists.
#ifdef WIN32
#include "vkrect.h"

#include <framework/core/logger.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/image.h>

#include <cstddef>
#include <cstring>
#include <exception>
#include <vector>

namespace
{
    // Stage-2 resource paths. The "/data/..." form works both when running from the working
    // directory (dev) and from the embedded assets.pak - the pak keeps files under the same prefixes.
    constexpr const char* kRectVertShaderPath = "/data/shaders/vulkan/rect.vert.spv";
    constexpr const char* kRectFragShaderPath = "/data/shaders/vulkan/rect.frag.spv";

    // Any existing PNG - the icon is square and it is immediately obvious whether the texture
    // uploaded correctly (swapped channels or a wrong stride would be instantly visible).
    // (clientlogo.png removed at the user's request - it was third-party branding)
    constexpr const char* kRectTexturePath = "/data/images/clienticon.png";

    // One vertex: position within the unit square + texture coordinate.
    struct VkRectVertex
    {
        float pos[2];
        float uv[2];
    };

    // Must match the push_constant block in rect.vert byte for byte.
    struct VkRectPushConstants
    {
        float scale[2];
        float offset[2];
    };
}

bool VkRectRenderer::fail(const std::string& reason)
{
    m_error = reason;
    g_logger.warning("[vulkan] rectangle: {} - the context keeps running, but without drawing", reason);
    terminate();
    return false;
}

bool VkRectRenderer::init(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass,
                          VkQueue graphicsQueue, VkCommandPool commandPool)
{
    if (m_ready)
        return true;

    if (physicalDevice == VK_NULL_HANDLE || device == VK_NULL_HANDLE ||
        renderPass == VK_NULL_HANDLE || graphicsQueue == VK_NULL_HANDLE || commandPool == VK_NULL_HANDLE)
        return fail("incomplete context passed to the rectangle renderer");

    m_physicalDevice = physicalDevice;
    m_device = device;
    m_renderPass = renderPass;
    m_graphicsQueue = graphicsQueue;
    m_commandPool = commandPool;

    if (!loadFunctions())
        return false;

    if (!createShaderModules())
        return false;

    if (!createGeometry())
        return false;

    if (!createTexture())
        return false;

    if (!createDescriptors())
        return false;

    if (!createPipeline())
        return false;

    m_ready = true;

    g_logger.info("[vulkan] rectangle ready: texture {}x{} from {}",
                  m_textureWidth, m_textureHeight, kRectTexturePath);

    return true;
}

bool VkRectRenderer::loadFunctions()
{
    const auto fn = [this](const char* name) { return vkGetDeviceProcAddr(m_device, name); };

    m_vkCreateShaderModule = reinterpret_cast<PFN_vkCreateShaderModule>(fn("vkCreateShaderModule"));
    m_vkDestroyShaderModule = reinterpret_cast<PFN_vkDestroyShaderModule>(fn("vkDestroyShaderModule"));

    m_vkCreateBuffer = reinterpret_cast<PFN_vkCreateBuffer>(fn("vkCreateBuffer"));
    m_vkDestroyBuffer = reinterpret_cast<PFN_vkDestroyBuffer>(fn("vkDestroyBuffer"));
    m_vkGetBufferMemoryRequirements = reinterpret_cast<PFN_vkGetBufferMemoryRequirements>(fn("vkGetBufferMemoryRequirements"));
    m_vkBindBufferMemory = reinterpret_cast<PFN_vkBindBufferMemory>(fn("vkBindBufferMemory"));

    m_vkAllocateMemory = reinterpret_cast<PFN_vkAllocateMemory>(fn("vkAllocateMemory"));
    m_vkFreeMemory = reinterpret_cast<PFN_vkFreeMemory>(fn("vkFreeMemory"));
    m_vkMapMemory = reinterpret_cast<PFN_vkMapMemory>(fn("vkMapMemory"));
    m_vkUnmapMemory = reinterpret_cast<PFN_vkUnmapMemory>(fn("vkUnmapMemory"));

    m_vkCreateImage = reinterpret_cast<PFN_vkCreateImage>(fn("vkCreateImage"));
    m_vkDestroyImage = reinterpret_cast<PFN_vkDestroyImage>(fn("vkDestroyImage"));
    m_vkGetImageMemoryRequirements = reinterpret_cast<PFN_vkGetImageMemoryRequirements>(fn("vkGetImageMemoryRequirements"));
    m_vkBindImageMemory = reinterpret_cast<PFN_vkBindImageMemory>(fn("vkBindImageMemory"));
    m_vkCreateImageView = reinterpret_cast<PFN_vkCreateImageView>(fn("vkCreateImageView"));
    m_vkDestroyImageView = reinterpret_cast<PFN_vkDestroyImageView>(fn("vkDestroyImageView"));
    m_vkCreateSampler = reinterpret_cast<PFN_vkCreateSampler>(fn("vkCreateSampler"));
    m_vkDestroySampler = reinterpret_cast<PFN_vkDestroySampler>(fn("vkDestroySampler"));

    m_vkCreateDescriptorSetLayout = reinterpret_cast<PFN_vkCreateDescriptorSetLayout>(fn("vkCreateDescriptorSetLayout"));
    m_vkDestroyDescriptorSetLayout = reinterpret_cast<PFN_vkDestroyDescriptorSetLayout>(fn("vkDestroyDescriptorSetLayout"));
    m_vkCreateDescriptorPool = reinterpret_cast<PFN_vkCreateDescriptorPool>(fn("vkCreateDescriptorPool"));
    m_vkDestroyDescriptorPool = reinterpret_cast<PFN_vkDestroyDescriptorPool>(fn("vkDestroyDescriptorPool"));
    m_vkAllocateDescriptorSets = reinterpret_cast<PFN_vkAllocateDescriptorSets>(fn("vkAllocateDescriptorSets"));
    m_vkUpdateDescriptorSets = reinterpret_cast<PFN_vkUpdateDescriptorSets>(fn("vkUpdateDescriptorSets"));

    m_vkCreatePipelineLayout = reinterpret_cast<PFN_vkCreatePipelineLayout>(fn("vkCreatePipelineLayout"));
    m_vkDestroyPipelineLayout = reinterpret_cast<PFN_vkDestroyPipelineLayout>(fn("vkDestroyPipelineLayout"));
    m_vkCreateGraphicsPipelines = reinterpret_cast<PFN_vkCreateGraphicsPipelines>(fn("vkCreateGraphicsPipelines"));
    m_vkDestroyPipeline = reinterpret_cast<PFN_vkDestroyPipeline>(fn("vkDestroyPipeline"));

    m_vkAllocateCommandBuffers = reinterpret_cast<PFN_vkAllocateCommandBuffers>(fn("vkAllocateCommandBuffers"));
    m_vkFreeCommandBuffers = reinterpret_cast<PFN_vkFreeCommandBuffers>(fn("vkFreeCommandBuffers"));
    m_vkBeginCommandBuffer = reinterpret_cast<PFN_vkBeginCommandBuffer>(fn("vkBeginCommandBuffer"));
    m_vkEndCommandBuffer = reinterpret_cast<PFN_vkEndCommandBuffer>(fn("vkEndCommandBuffer"));
    m_vkQueueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(fn("vkQueueSubmit"));
    m_vkQueueWaitIdle = reinterpret_cast<PFN_vkQueueWaitIdle>(fn("vkQueueWaitIdle"));

    m_vkCmdPipelineBarrier = reinterpret_cast<PFN_vkCmdPipelineBarrier>(fn("vkCmdPipelineBarrier"));
    m_vkCmdCopyBufferToImage = reinterpret_cast<PFN_vkCmdCopyBufferToImage>(fn("vkCmdCopyBufferToImage"));

    m_vkCmdBindPipeline = reinterpret_cast<PFN_vkCmdBindPipeline>(fn("vkCmdBindPipeline"));
    m_vkCmdBindVertexBuffers = reinterpret_cast<PFN_vkCmdBindVertexBuffers>(fn("vkCmdBindVertexBuffers"));
    m_vkCmdBindIndexBuffer = reinterpret_cast<PFN_vkCmdBindIndexBuffer>(fn("vkCmdBindIndexBuffer"));
    m_vkCmdBindDescriptorSets = reinterpret_cast<PFN_vkCmdBindDescriptorSets>(fn("vkCmdBindDescriptorSets"));
    m_vkCmdSetViewport = reinterpret_cast<PFN_vkCmdSetViewport>(fn("vkCmdSetViewport"));
    m_vkCmdSetScissor = reinterpret_cast<PFN_vkCmdSetScissor>(fn("vkCmdSetScissor"));
    m_vkCmdPushConstants = reinterpret_cast<PFN_vkCmdPushConstants>(fn("vkCmdPushConstants"));
    m_vkCmdDrawIndexed = reinterpret_cast<PFN_vkCmdDrawIndexed>(fn("vkCmdDrawIndexed"));

    // We check the full set once, at startup - otherwise a single missing function would only
    // surface in the frame loop as a jump to nullptr.
    if (!m_vkCreateShaderModule || !m_vkDestroyShaderModule ||
        !m_vkCreateBuffer || !m_vkDestroyBuffer || !m_vkGetBufferMemoryRequirements || !m_vkBindBufferMemory ||
        !m_vkAllocateMemory || !m_vkFreeMemory || !m_vkMapMemory || !m_vkUnmapMemory ||
        !m_vkCreateImage || !m_vkDestroyImage || !m_vkGetImageMemoryRequirements || !m_vkBindImageMemory ||
        !m_vkCreateImageView || !m_vkDestroyImageView || !m_vkCreateSampler || !m_vkDestroySampler ||
        !m_vkCreateDescriptorSetLayout || !m_vkDestroyDescriptorSetLayout ||
        !m_vkCreateDescriptorPool || !m_vkDestroyDescriptorPool ||
        !m_vkAllocateDescriptorSets || !m_vkUpdateDescriptorSets ||
        !m_vkCreatePipelineLayout || !m_vkDestroyPipelineLayout ||
        !m_vkCreateGraphicsPipelines || !m_vkDestroyPipeline ||
        !m_vkAllocateCommandBuffers || !m_vkFreeCommandBuffers ||
        !m_vkBeginCommandBuffer || !m_vkEndCommandBuffer || !m_vkQueueSubmit || !m_vkQueueWaitIdle ||
        !m_vkCmdPipelineBarrier || !m_vkCmdCopyBufferToImage ||
        !m_vkCmdBindPipeline || !m_vkCmdBindVertexBuffers || !m_vkCmdBindIndexBuffer ||
        !m_vkCmdBindDescriptorSets || !m_vkCmdSetViewport || !m_vkCmdSetScissor ||
        !m_vkCmdPushConstants || !m_vkCmdDrawIndexed)
        return fail("missing functions required for drawing");

    // vkGetPhysicalDeviceMemoryProperties is an INSTANCE function, not a device one - we take it
    // from the vkloader globals, because it is already loaded there by loadInstanceFunctions.
    if (!vkGetPhysicalDeviceMemoryProperties)
        return fail("missing vkGetPhysicalDeviceMemoryProperties");

    return true;
}

VkShaderModule VkRectRenderer::loadShader(const std::string& path)
{
    std::string code;

    // readFileContents throws when the file does not exist. We catch it here, because a missing
    // .spv is supposed to degrade the renderer to just clearing the screen, not crash the client.
    try {
        code = g_resources.readFileContents(path);
    } catch (const std::exception& e) {
        g_logger.warning("[vulkan] cannot load {}: {}", path, e.what());
        return VK_NULL_HANDLE;
    }

    // SPIR-V is a stream of 32-bit words: the size must be a multiple of 4, and the first word
    // is the magic number 0x07230203. We check both so that a random file never reaches
    // the driver (validation on its side can end up crashing the process).
    if (code.size() < 4 || (code.size() % 4) != 0) {
        g_logger.warning("[vulkan] {} has size {} - this is not valid SPIR-V", path, code.size());
        return VK_NULL_HANDLE;
    }

    uint32_t magic = 0;
    std::memcpy(&magic, code.data(), sizeof(magic));
    if (magic != 0x07230203u) {
        g_logger.warning("[vulkan] {} does not start with the SPIR-V magic number", path);
        return VK_NULL_HANDLE;
    }

    // We copy into a uint32_t vector, because std::string does not guarantee 4-byte alignment,
    // and pCode is a pointer to uint32_t.
    std::vector<uint32_t> words(code.size() / 4);
    std::memcpy(words.data(), code.data(), code.size());

    VkShaderModuleCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = code.size();
    info.pCode = words.data();

    VkShaderModule module = VK_NULL_HANDLE;
    if (m_vkCreateShaderModule(m_device, &info, nullptr, &module) != VK_SUCCESS) {
        g_logger.warning("[vulkan] the driver rejected shader module {}", path);
        return VK_NULL_HANDLE;
    }

    return module;
}

bool VkRectRenderer::createShaderModules()
{
    m_vertShader = loadShader(kRectVertShaderPath);
    if (m_vertShader == VK_NULL_HANDLE)
        return fail("missing vertex shader module");

    m_fragShader = loadShader(kRectFragShaderPath);
    if (m_fragShader == VK_NULL_HANDLE)
        return fail("missing fragment shader module");

    return true;
}

uint32_t VkRectRenderer::findMemoryType(const uint32_t typeFilter, const VkMemoryPropertyFlags properties) const
{
    VkPhysicalDeviceMemoryProperties memProps{};
    vkGetPhysicalDeviceMemoryProperties(m_physicalDevice, &memProps);

    for (uint32_t i = 0; i < memProps.memoryTypeCount; ++i) {
        // typeFilter is a bitmask of the types the driver allows FOR THIS object;
        // additionally the type must have all the flags we requested (e.g. CPU visibility).
        if ((typeFilter & (1u << i)) && (memProps.memoryTypes[i].propertyFlags & properties) == properties)
            return i;
    }

    return UINT32_MAX;
}

bool VkRectRenderer::createBuffer(const VkDeviceSize size, const VkBufferUsageFlags usage,
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

bool VkRectRenderer::createGeometry()
{
    // Unit square: position and UV go 1:1, because Vulkan's NDC has Y pointing down just like the texture.
    static constexpr VkRectVertex vertices[4] = {
        { { 0.0f, 0.0f }, { 0.0f, 0.0f } },
        { { 1.0f, 0.0f }, { 1.0f, 0.0f } },
        { { 1.0f, 1.0f }, { 1.0f, 1.0f } },
        { { 0.0f, 1.0f }, { 0.0f, 1.0f } },
    };

    // Two triangles sharing the 0-2 diagonal. 16-bit indices are enough and will remain enough
    // later too: individual sprite batches do not come anywhere near 65535 vertices.
    static constexpr uint16_t indices[6] = { 0, 1, 2, 2, 3, 0 };

    // CPU-visible memory (HOST_VISIBLE|HOST_COHERENT) rather than DEVICE_LOCAL with a staging
    // buffer: this is 76 bytes of data in total, uploaded ONCE. A staging buffer would cost
    // more code and one extra trip through the queue, while gaining nothing measurable here.
    // For the texture it is the other way around - and there the staging buffer IS used (see createTexture).
    constexpr VkMemoryPropertyFlags hostFlags =
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;

    if (!createBuffer(sizeof(vertices), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, hostFlags,
                      m_vertexBuffer, m_vertexMemory))
        return fail("failed to create the vertex buffer");

    void* mapped = nullptr;
    if (m_vkMapMemory(m_device, m_vertexMemory, 0, sizeof(vertices), 0, &mapped) != VK_SUCCESS)
        return fail("failed to map the vertex buffer");

    std::memcpy(mapped, vertices, sizeof(vertices));
    m_vkUnmapMemory(m_device, m_vertexMemory);

    if (!createBuffer(sizeof(indices), VK_BUFFER_USAGE_INDEX_BUFFER_BIT, hostFlags,
                      m_indexBuffer, m_indexMemory))
        return fail("failed to create the index buffer");

    if (m_vkMapMemory(m_device, m_indexMemory, 0, sizeof(indices), 0, &mapped) != VK_SUCCESS)
        return fail("failed to map the index buffer");

    std::memcpy(mapped, indices, sizeof(indices));
    m_vkUnmapMemory(m_device, m_indexMemory);

    return true;
}

VkCommandBuffer VkRectRenderer::beginOneShot()
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

bool VkRectRenderer::endOneShot(VkCommandBuffer cmd)
{
    bool ok = m_vkEndCommandBuffer(cmd) == VK_SUCCESS;

    if (ok) {
        VkSubmitInfo submit{};
        submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;

        // No fence and no semaphores: this is a one-shot data upload at startup, so the
        // simplest correct solution is to wait for the queue to drain. Nothing is being
        // drawn yet, so there is nothing to stall.
        ok = m_vkQueueSubmit(m_graphicsQueue, 1, &submit, VK_NULL_HANDLE) == VK_SUCCESS &&
             m_vkQueueWaitIdle(m_graphicsQueue) == VK_SUCCESS;
    }

    m_vkFreeCommandBuffers(m_device, m_commandPool, 1, &cmd);
    return ok;
}

bool VkRectRenderer::createTexture()
{
    // We use the existing Image class to avoid duplicating the PNG decoder - it is the same
    // loading path the OpenGL renderer uses.
    const ImagePtr image = Image::load(kRectTexturePath);
    if (!image || image->getWidth() <= 0 || image->getHeight() <= 0)
        return fail(std::string("failed to load texture ") + kRectTexturePath);

    m_textureWidth = static_cast<uint32_t>(image->getWidth());
    m_textureHeight = static_cast<uint32_t>(image->getHeight());

    // Vulkan has no 24-bit format with guaranteed support, and Image can return
    // 3 bytes per pixel (PNG without an alpha channel). In that case we expand to RGBA with alpha = 255.
    const int bpp = image->getBpp();
    if (bpp != 3 && bpp != 4)
        return fail("texture has an unsupported channel count");

    const size_t pixelCount = static_cast<size_t>(m_textureWidth) * m_textureHeight;
    const VkDeviceSize imageBytes = pixelCount * 4;

    std::vector<uint8_t> rgba;
    const uint8_t* source = image->getPixelData();

    if (bpp == 3) {
        rgba.resize(pixelCount * 4);
        for (size_t i = 0; i < pixelCount; ++i) {
            rgba[i * 4 + 0] = source[i * 3 + 0];
            rgba[i * 4 + 1] = source[i * 3 + 1];
            rgba[i * 4 + 2] = source[i * 3 + 2];
            rgba[i * 4 + 3] = 255;
        }
        source = rgba.data();
    }

    // Staging buffer: DEVICE_LOCAL memory with OPTIMAL tiling (which is what we want for the
    // texture, since sampling from LINEAR can be many times slower and is not always supported)
    // is not mappable from the CPU. So the pixels go first into a CPU-visible buffer,
    // and from there into the image via a copy command.
    VkBuffer staging = VK_NULL_HANDLE;
    VkDeviceMemory stagingMemory = VK_NULL_HANDLE;

    // Staging buffer cleanup in one place - there are several error exits below.
    const auto releaseStaging = [&] {
        if (staging != VK_NULL_HANDLE)
            m_vkDestroyBuffer(m_device, staging, nullptr);
        if (stagingMemory != VK_NULL_HANDLE)
            m_vkFreeMemory(m_device, stagingMemory, nullptr);
    };

    if (!createBuffer(imageBytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                      staging, stagingMemory)) {
        releaseStaging();
        return fail("failed to create the texture staging buffer");
    }

    void* mapped = nullptr;
    if (m_vkMapMemory(m_device, stagingMemory, 0, imageBytes, 0, &mapped) != VK_SUCCESS) {
        releaseStaging();
        return fail("failed to map the texture staging buffer");
    }

    std::memcpy(mapped, source, static_cast<size_t>(imageBytes));
    m_vkUnmapMemory(m_device, stagingMemory);

    // Image hands out pixels in RGBA order (the same order the GL path passes as GL_RGBA),
    // and we pick the _SRGB variant to match the swapchain format - see the comment in rect.frag.
    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
    imageInfo.extent = { m_textureWidth, m_textureHeight, 1 };
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (m_vkCreateImage(m_device, &imageInfo, nullptr, &m_texture) != VK_SUCCESS) {
        releaseStaging();
        return fail("failed to create the texture image");
    }

    VkMemoryRequirements req{};
    m_vkGetImageMemoryRequirements(m_device, m_texture, &req);

    const uint32_t typeIndex = findMemoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (typeIndex == UINT32_MAX) {
        releaseStaging();
        return fail("no device memory available for the texture");
    }

    VkMemoryAllocateInfo alloc{};
    alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = typeIndex;

    if (m_vkAllocateMemory(m_device, &alloc, nullptr, &m_textureMemory) != VK_SUCCESS ||
        m_vkBindImageMemory(m_device, m_texture, m_textureMemory, 0) != VK_SUCCESS) {
        releaseStaging();
        return fail("failed to allocate texture memory");
    }

    const VkCommandBuffer cmd = beginOneShot();
    if (cmd == VK_NULL_HANDLE) {
        releaseStaging();
        return fail("failed to create a command buffer for the texture upload");
    }

    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = m_texture;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.layerCount = 1;

    // Transition 1: UNDEFINED -> TRANSFER_DST_OPTIMAL. UNDEFINED, because we do not care about
    // the image contents (we are about to overwrite it entirely), and that lets the driver skip
    // copying the old data during the layout change.
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

    m_vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                           0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy copy{};
    copy.bufferOffset = 0;
    copy.bufferRowLength = 0;   // 0 = rows tightly packed, no padding
    copy.bufferImageHeight = 0;
    copy.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copy.imageSubresource.layerCount = 1;
    copy.imageExtent = { m_textureWidth, m_textureHeight, 1 };

    m_vkCmdCopyBufferToImage(cmd, staging, m_texture, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);

    // Transition 2: TRANSFER_DST_OPTIMAL -> SHADER_READ_ONLY_OPTIMAL. The barrier ties the copy
    // write to the fragment shader read - without it the driver could start sampling
    // the texture before the copy finishes.
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    m_vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                           0, 0, nullptr, 0, nullptr, 1, &barrier);

    const bool uploaded = endOneShot(cmd);

    // The staging buffer is no longer needed - endOneShot waited on the queue, so the copy
    // has definitely finished and nothing holds on to it.
    releaseStaging();

    if (!uploaded)
        return fail("uploading the texture to device memory failed");

    VkImageViewCreateInfo viewInfo{};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = m_texture;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.layerCount = 1;

    if (m_vkCreateImageView(m_device, &viewInfo, nullptr, &m_textureView) != VK_SUCCESS)
        return fail("failed to create the texture view");

    VkSamplerCreateInfo samplerInfo{};
    samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    // NEAREST, because ultimately we render Tibia's pixel art - linear filtering blurs
    // the sprites. For the stage-2 test itself it does not matter, but we set the final value right away.
    samplerInfo.magFilter = VK_FILTER_NEAREST;
    samplerInfo.minFilter = VK_FILTER_NEAREST;
    samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    // Anisotropy requires an enabled device feature, and we enabled none in createDevice.
    samplerInfo.anisotropyEnable = VK_FALSE;
    samplerInfo.borderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
    samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;

    if (m_vkCreateSampler(m_device, &samplerInfo, nullptr, &m_sampler) != VK_SUCCESS)
        return fail("failed to create the sampler");

    return true;
}

bool VkRectRenderer::createDescriptors()
{
    VkDescriptorSetLayoutBinding binding{};
    binding.binding = 0;
    binding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    binding.descriptorCount = 1;
    binding.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 1;
    layoutInfo.pBindings = &binding;

    if (m_vkCreateDescriptorSetLayout(m_device, &layoutInfo, nullptr, &m_descriptorLayout) != VK_SUCCESS)
        return fail("failed to create the descriptor set layout");

    VkDescriptorPoolSize poolSize{};
    poolSize.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    poolSize.descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    // One set for the renderer's entire lifetime: the texture never changes, so there is no
    // reason to allocate it per frame on the fly. The set is only READ during drawing.
    poolInfo.maxSets = 1;
    poolInfo.poolSizeCount = 1;
    poolInfo.pPoolSizes = &poolSize;

    if (m_vkCreateDescriptorPool(m_device, &poolInfo, nullptr, &m_descriptorPool) != VK_SUCCESS)
        return fail("failed to create the descriptor pool");

    VkDescriptorSetAllocateInfo alloc{};
    alloc.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    alloc.descriptorPool = m_descriptorPool;
    alloc.descriptorSetCount = 1;
    alloc.pSetLayouts = &m_descriptorLayout;

    if (m_vkAllocateDescriptorSets(m_device, &alloc, &m_descriptorSet) != VK_SUCCESS)
        return fail("failed to allocate the descriptor set");

    VkDescriptorImageInfo imageInfo{};
    imageInfo.sampler = m_sampler;
    imageInfo.imageView = m_textureView;
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkWriteDescriptorSet write{};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = m_descriptorSet;
    write.dstBinding = 0;
    write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &imageInfo;

    m_vkUpdateDescriptorSets(m_device, 1, &write, 0, nullptr);

    return true;
}

bool VkRectRenderer::createPipeline()
{
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = m_vertShader;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = m_fragShader;
    stages[1].pName = "main";

    VkVertexInputBindingDescription bindingDesc{};
    bindingDesc.binding = 0;
    bindingDesc.stride = sizeof(VkRectVertex);
    bindingDesc.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

    VkVertexInputAttributeDescription attrs[2]{};
    attrs[0].location = 0;
    attrs[0].binding = 0;
    attrs[0].format = VK_FORMAT_R32G32_SFLOAT;
    attrs[0].offset = offsetof(VkRectVertex, pos);
    attrs[1].location = 1;
    attrs[1].binding = 0;
    attrs[1].format = VK_FORMAT_R32G32_SFLOAT;
    attrs[1].offset = offsetof(VkRectVertex, uv);

    VkPipelineVertexInputStateCreateInfo vertexInput{};
    vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertexInput.vertexBindingDescriptionCount = 1;
    vertexInput.pVertexBindingDescriptions = &bindingDesc;
    vertexInput.vertexAttributeDescriptionCount = 2;
    vertexInput.pVertexAttributeDescriptions = attrs;

    VkPipelineInputAssemblyStateCreateInfo assembly{};
    assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    // Viewport and scissor are DYNAMIC, so here we only give their counts. If they were part of
    // the pipeline, every window resize would require rebuilding the whole VkPipeline - one of
    // the most expensive operations in Vulkan.
    VkPipelineViewportStateCreateInfo viewportState{};
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.scissorCount = 1;

    const VkDynamicState dynamicStates[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };

    VkPipelineDynamicStateCreateInfo dynamicState{};
    dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = 2;
    dynamicState.pDynamicStates = dynamicStates;

    VkPipelineRasterizationStateCreateInfo raster{};
    raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    raster.polygonMode = VK_POLYGON_MODE_FILL;
    // No face culling: we draw flat rectangles, so their winding carries no information,
    // and disabling culling eliminates an entire species of "nothing is visible" bugs.
    raster.cullMode = VK_CULL_MODE_NONE;
    raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    raster.lineWidth = 1.0f;

    VkPipelineMultisampleStateCreateInfo multisample{};
    multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState blendAttachment{};
    blendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                     VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    // Alpha blending enabled, because the client's textures have transparent backgrounds - without
    // it the logo would be covered by a black (or garbage) square and a correct texture upload
    // would be indistinguishable from a failure.
    blendAttachment.blendEnable = VK_TRUE;
    blendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
    blendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    blendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
    blendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    blendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    blendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;

    VkPipelineColorBlendStateCreateInfo blend{};
    blend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    blend.attachmentCount = 1;
    blend.pAttachments = &blendAttachment;

    VkPushConstantRange pushRange{};
    pushRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pushRange.offset = 0;
    pushRange.size = sizeof(VkRectPushConstants);

    VkPipelineLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    layoutInfo.setLayoutCount = 1;
    layoutInfo.pSetLayouts = &m_descriptorLayout;
    layoutInfo.pushConstantRangeCount = 1;
    layoutInfo.pPushConstantRanges = &pushRange;

    if (m_vkCreatePipelineLayout(m_device, &layoutInfo, nullptr, &m_pipelineLayout) != VK_SUCCESS)
        return fail("failed to create the pipeline layout");

    VkGraphicsPipelineCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    info.stageCount = 2;
    info.pStages = stages;
    info.pVertexInputState = &vertexInput;
    info.pInputAssemblyState = &assembly;
    info.pViewportState = &viewportState;
    info.pRasterizationState = &raster;
    info.pMultisampleState = &multisample;
    info.pColorBlendState = &blend;
    info.pDynamicState = &dynamicState;
    info.layout = m_pipelineLayout;
    // The pipeline is tied to the render pass, not to the swapchain - VkContext's render pass
    // survives swapchain recreation, so the pipeline needs no rebuild on window resize either.
    info.renderPass = m_renderPass;
    info.subpass = 0;

    if (m_vkCreateGraphicsPipelines(m_device, VK_NULL_HANDLE, 1, &info, nullptr, &m_pipeline) != VK_SUCCESS)
        return fail("failed to create the graphics pipeline");

    return true;
}

void VkRectRenderer::record(VkCommandBuffer cmd, const VkExtent2D& extent)
{
    if (!m_ready || cmd == VK_NULL_HANDLE || extent.width == 0 || extent.height == 0)
        return;

    VkViewport viewport{};
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = static_cast<float>(extent.width);
    viewport.height = static_cast<float>(extent.height);
    viewport.minDepth = 0.0f;
    viewport.maxDepth = 1.0f;

    VkRect2D scissor{};
    scissor.offset = { 0, 0 };
    scissor.extent = extent;

    m_vkCmdSetViewport(cmd, 0, 1, &viewport);
    m_vkCmdSetScissor(cmd, 0, 1, &scissor);

    m_vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, m_pipeline);

    const VkDeviceSize offset = 0;
    m_vkCmdBindVertexBuffers(cmd, 0, 1, &m_vertexBuffer, &offset);
    m_vkCmdBindIndexBuffer(cmd, m_indexBuffer, 0, VK_INDEX_TYPE_UINT16);

    m_vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, m_pipelineLayout,
                              0, 1, &m_descriptorSet, 0, nullptr);

    // The rectangle has a FIXED size in pixels (the texture size) and is centered. We compute this
    // from the current swapchain size every frame, so after a window resize the logo
    // stays centered and does not stretch. The NDC range is [-1,1], hence the factor of 2.
    VkRectPushConstants push{};
    push.scale[0] = 2.0f * static_cast<float>(m_textureWidth) / static_cast<float>(extent.width);
    push.scale[1] = 2.0f * static_cast<float>(m_textureHeight) / static_cast<float>(extent.height);
    // The vertices are in [0,1], so the top-left corner is just the offset - we shift it by half
    // the width/height to the left and up from the screen center (i.e. from zero in NDC).
    push.offset[0] = -push.scale[0] * 0.5f;
    push.offset[1] = -push.scale[1] * 0.5f;

    m_vkCmdPushConstants(cmd, m_pipelineLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(push), &push);

    m_vkCmdDrawIndexed(cmd, 6, 1, 0, 0, 0);
}

void VkRectRenderer::terminate()
{
    // Note: we do NOT call vkDeviceWaitIdle here - VkContext::terminate does that before calling
    // us, and on an init() failure nothing has reached the drawing queue yet anyway.
    if (m_device == VK_NULL_HANDLE) {
        m_ready = false;
        return;
    }

    if (m_pipeline != VK_NULL_HANDLE && m_vkDestroyPipeline) {
        m_vkDestroyPipeline(m_device, m_pipeline, nullptr);
        m_pipeline = VK_NULL_HANDLE;
    }

    if (m_pipelineLayout != VK_NULL_HANDLE && m_vkDestroyPipelineLayout) {
        m_vkDestroyPipelineLayout(m_device, m_pipelineLayout, nullptr);
        m_pipelineLayout = VK_NULL_HANDLE;
    }

    // Descriptor sets die together with the pool - there is no need to (and without the right
    // flag no way to) free them individually.
    if (m_descriptorPool != VK_NULL_HANDLE && m_vkDestroyDescriptorPool) {
        m_vkDestroyDescriptorPool(m_device, m_descriptorPool, nullptr);
        m_descriptorPool = VK_NULL_HANDLE;
    }
    m_descriptorSet = VK_NULL_HANDLE;

    if (m_descriptorLayout != VK_NULL_HANDLE && m_vkDestroyDescriptorSetLayout) {
        m_vkDestroyDescriptorSetLayout(m_device, m_descriptorLayout, nullptr);
        m_descriptorLayout = VK_NULL_HANDLE;
    }

    if (m_sampler != VK_NULL_HANDLE && m_vkDestroySampler) {
        m_vkDestroySampler(m_device, m_sampler, nullptr);
        m_sampler = VK_NULL_HANDLE;
    }

    if (m_textureView != VK_NULL_HANDLE && m_vkDestroyImageView) {
        m_vkDestroyImageView(m_device, m_textureView, nullptr);
        m_textureView = VK_NULL_HANDLE;
    }

    if (m_texture != VK_NULL_HANDLE && m_vkDestroyImage) {
        m_vkDestroyImage(m_device, m_texture, nullptr);
        m_texture = VK_NULL_HANDLE;
    }

    if (m_textureMemory != VK_NULL_HANDLE && m_vkFreeMemory) {
        m_vkFreeMemory(m_device, m_textureMemory, nullptr);
        m_textureMemory = VK_NULL_HANDLE;
    }

    if (m_indexBuffer != VK_NULL_HANDLE && m_vkDestroyBuffer) {
        m_vkDestroyBuffer(m_device, m_indexBuffer, nullptr);
        m_indexBuffer = VK_NULL_HANDLE;
    }

    if (m_indexMemory != VK_NULL_HANDLE && m_vkFreeMemory) {
        m_vkFreeMemory(m_device, m_indexMemory, nullptr);
        m_indexMemory = VK_NULL_HANDLE;
    }

    if (m_vertexBuffer != VK_NULL_HANDLE && m_vkDestroyBuffer) {
        m_vkDestroyBuffer(m_device, m_vertexBuffer, nullptr);
        m_vertexBuffer = VK_NULL_HANDLE;
    }

    if (m_vertexMemory != VK_NULL_HANDLE && m_vkFreeMemory) {
        m_vkFreeMemory(m_device, m_vertexMemory, nullptr);
        m_vertexMemory = VK_NULL_HANDLE;
    }

    // Shader modules are only needed at pipeline creation, but we keep them until the end -
    // with a single pipeline there is no point complicating the lifecycle over a dozen or so kilobytes.
    if (m_fragShader != VK_NULL_HANDLE && m_vkDestroyShaderModule) {
        m_vkDestroyShaderModule(m_device, m_fragShader, nullptr);
        m_fragShader = VK_NULL_HANDLE;
    }

    if (m_vertShader != VK_NULL_HANDLE && m_vkDestroyShaderModule) {
        m_vkDestroyShaderModule(m_device, m_vertShader, nullptr);
        m_vertShader = VK_NULL_HANDLE;
    }

    // Handles borrowed from VkContext (device, render pass, queue, pool) are NOT destroyed -
    // they are not ours. We only zero them so that a repeated terminate() stays safe.
    m_device = VK_NULL_HANDLE;
    m_physicalDevice = VK_NULL_HANDLE;
    m_renderPass = VK_NULL_HANDLE;
    m_graphicsQueue = VK_NULL_HANDLE;
    m_commandPool = VK_NULL_HANDLE;

    m_ready = false;
}

#endif // WIN32
