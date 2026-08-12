/*
 * Stage 2 of the Vulkan renderer: a single textured rectangle.
 *
 * This class is INTENTIONALLY minimal, yet complete: it contains all the building blocks that
 * were missing after stage 1 and without which nothing can be drawn beyond clearing the screen -
 * a shader module (SPIR-V), vertex and index buffers, a texture uploaded through a staging buffer,
 * a descriptor with a sampler, and a graphics pipeline. Every subsequent element of the renderer
 * (sprites, tiles, text) is just a repetition of the same scheme with different data.
 *
 * The object's lifetime is tied to VkContext: init() receives the context's ready device,
 * render pass and command pool, and record() appends draw commands to the frame's command buffer
 * ALREADY INSIDE the render pass. The class neither begins nor ends the render pass and does not
 * present - that is still VkContext's job.
 *
 * An init() failure is not a critical error: the context keeps running and clears the screen,
 * and the reason goes to the log. Thanks to that, missing .spv files do not take down the whole backend.
 *
 * Function pointers are LOCAL to the class and fetched via vkGetDeviceProcAddr - the same way
 * as in VkContext. So there is no global state to clean up when this object fails.
 */

#pragma once
 // The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
 // dependency is windows-only in vcpkg.json. Outside Windows the file compiles to nothing,
 // so it can be unconditionally on the source list in CMakeLists.
#ifdef WIN32


#include "vkloader.h"

#include <string>

class VkRectRenderer
{
public:
    // Builds everything needed to draw the rectangle. commandPool and graphicsQueue are
    // borrowed from VkContext solely for the duration of the texture upload (one-shot command buffer).
    bool init(VkPhysicalDevice physicalDevice, VkDevice device, VkRenderPass renderPass,
              VkQueue graphicsQueue, VkCommandPool commandPool);

    // Appends draw commands to an ALREADY STARTED render pass. extent is the current swapchain
    // size - the viewport, scissor and rectangle size are computed from it every frame,
    // so a window resize does not require rebuilding the pipeline.
    void record(VkCommandBuffer cmd, const VkExtent2D& extent);

    void terminate();

    bool isReady() const { return m_ready; }
    const std::string& getError() const { return m_error; }

private:
    bool fail(const std::string& reason);
    bool loadFunctions();

    bool createShaderModules();
    bool createGeometry();
    bool createTexture();
    bool createDescriptors();
    bool createPipeline();

    // Shared allocation code: creates a buffer and binds freshly allocated memory to it.
    bool createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties,
                      VkBuffer& buffer, VkDeviceMemory& memory);

    // Picks a memory type satisfying the object's requirements AND our visibility requirements.
    // Returns UINT32_MAX when there is none.
    uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) const;

    // Loads an .spv file through the ResourceManager (so it works the same from the data
    // directory and from the pak) and turns it into a VkShaderModule.
    VkShaderModule loadShader(const std::string& path);

    // One-shot command buffer for data uploads; there is no way to copy into device
    // memory other than with a command, and at startup we do not care about asynchronicity,
    // so we simply wait on the queue.
    VkCommandBuffer beginOneShot();
    bool endOneShot(VkCommandBuffer cmd);

    // --- borrowed from VkContext (we do not destroy these) ---
    VkPhysicalDevice m_physicalDevice{ VK_NULL_HANDLE };
    VkDevice m_device{ VK_NULL_HANDLE };
    VkRenderPass m_renderPass{ VK_NULL_HANDLE };
    VkQueue m_graphicsQueue{ VK_NULL_HANDLE };
    VkCommandPool m_commandPool{ VK_NULL_HANDLE };

    // --- own resources ---
    VkShaderModule m_vertShader{ VK_NULL_HANDLE };
    VkShaderModule m_fragShader{ VK_NULL_HANDLE };

    VkBuffer m_vertexBuffer{ VK_NULL_HANDLE };
    VkDeviceMemory m_vertexMemory{ VK_NULL_HANDLE };
    VkBuffer m_indexBuffer{ VK_NULL_HANDLE };
    VkDeviceMemory m_indexMemory{ VK_NULL_HANDLE };

    VkImage m_texture{ VK_NULL_HANDLE };
    VkDeviceMemory m_textureMemory{ VK_NULL_HANDLE };
    VkImageView m_textureView{ VK_NULL_HANDLE };
    VkSampler m_sampler{ VK_NULL_HANDLE };
    uint32_t m_textureWidth{ 0 };
    uint32_t m_textureHeight{ 0 };

    VkDescriptorSetLayout m_descriptorLayout{ VK_NULL_HANDLE };
    VkDescriptorPool m_descriptorPool{ VK_NULL_HANDLE };
    VkDescriptorSet m_descriptorSet{ VK_NULL_HANDLE };

    VkPipelineLayout m_pipelineLayout{ VK_NULL_HANDLE };
    VkPipeline m_pipeline{ VK_NULL_HANDLE };

    bool m_ready{ false };
    std::string m_error;

    // --- device functions (local, as in VkContext) ---
    PFN_vkCreateShaderModule m_vkCreateShaderModule{ nullptr };
    PFN_vkDestroyShaderModule m_vkDestroyShaderModule{ nullptr };

    PFN_vkCreateBuffer m_vkCreateBuffer{ nullptr };
    PFN_vkDestroyBuffer m_vkDestroyBuffer{ nullptr };
    PFN_vkGetBufferMemoryRequirements m_vkGetBufferMemoryRequirements{ nullptr };
    PFN_vkBindBufferMemory m_vkBindBufferMemory{ nullptr };

    PFN_vkAllocateMemory m_vkAllocateMemory{ nullptr };
    PFN_vkFreeMemory m_vkFreeMemory{ nullptr };
    PFN_vkMapMemory m_vkMapMemory{ nullptr };
    PFN_vkUnmapMemory m_vkUnmapMemory{ nullptr };

    PFN_vkCreateImage m_vkCreateImage{ nullptr };
    PFN_vkDestroyImage m_vkDestroyImage{ nullptr };
    PFN_vkGetImageMemoryRequirements m_vkGetImageMemoryRequirements{ nullptr };
    PFN_vkBindImageMemory m_vkBindImageMemory{ nullptr };
    PFN_vkCreateImageView m_vkCreateImageView{ nullptr };
    PFN_vkDestroyImageView m_vkDestroyImageView{ nullptr };
    PFN_vkCreateSampler m_vkCreateSampler{ nullptr };
    PFN_vkDestroySampler m_vkDestroySampler{ nullptr };

    PFN_vkCreateDescriptorSetLayout m_vkCreateDescriptorSetLayout{ nullptr };
    PFN_vkDestroyDescriptorSetLayout m_vkDestroyDescriptorSetLayout{ nullptr };
    PFN_vkCreateDescriptorPool m_vkCreateDescriptorPool{ nullptr };
    PFN_vkDestroyDescriptorPool m_vkDestroyDescriptorPool{ nullptr };
    PFN_vkAllocateDescriptorSets m_vkAllocateDescriptorSets{ nullptr };
    PFN_vkUpdateDescriptorSets m_vkUpdateDescriptorSets{ nullptr };

    PFN_vkCreatePipelineLayout m_vkCreatePipelineLayout{ nullptr };
    PFN_vkDestroyPipelineLayout m_vkDestroyPipelineLayout{ nullptr };
    PFN_vkCreateGraphicsPipelines m_vkCreateGraphicsPipelines{ nullptr };
    PFN_vkDestroyPipeline m_vkDestroyPipeline{ nullptr };

    PFN_vkAllocateCommandBuffers m_vkAllocateCommandBuffers{ nullptr };
    PFN_vkFreeCommandBuffers m_vkFreeCommandBuffers{ nullptr };
    PFN_vkBeginCommandBuffer m_vkBeginCommandBuffer{ nullptr };
    PFN_vkEndCommandBuffer m_vkEndCommandBuffer{ nullptr };
    PFN_vkQueueSubmit m_vkQueueSubmit{ nullptr };
    PFN_vkQueueWaitIdle m_vkQueueWaitIdle{ nullptr };

    PFN_vkCmdPipelineBarrier m_vkCmdPipelineBarrier{ nullptr };
    PFN_vkCmdCopyBufferToImage m_vkCmdCopyBufferToImage{ nullptr };

    PFN_vkCmdBindPipeline m_vkCmdBindPipeline{ nullptr };
    PFN_vkCmdBindVertexBuffers m_vkCmdBindVertexBuffers{ nullptr };
    PFN_vkCmdBindIndexBuffer m_vkCmdBindIndexBuffer{ nullptr };
    PFN_vkCmdBindDescriptorSets m_vkCmdBindDescriptorSets{ nullptr };
    PFN_vkCmdSetViewport m_vkCmdSetViewport{ nullptr };
    PFN_vkCmdSetScissor m_vkCmdSetScissor{ nullptr };
    PFN_vkCmdPushConstants m_vkCmdPushConstants{ nullptr };
    PFN_vkCmdDrawIndexed m_vkCmdDrawIndexed{ nullptr };
};

#endif // WIN32
