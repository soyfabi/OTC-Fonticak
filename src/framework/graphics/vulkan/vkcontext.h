/*
 * The Vulkan context: instance, device, queues, window surface and swapchain.
 *
 * Stage 1 of the plan (VULKAN_RENDERER_PLAN.md). The context is created ALONGSIDE the existing
 * OpenGL path and changes nothing in it. It is enabled with the `renderBackend` switch in
 * config.ini; on any failure init() returns false, the reason goes to the log, and the client
 * keeps rendering the old way.
 *
 * We keep the function pointers LOCAL to this class (not global as in vkloader), because they
 * belong to a specific instance and device - thanks to that there is no global state to clean up
 * when the context fails.
 */

#pragma once
// The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
// dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
// so it can sit unconditionally on the source list in CMakeLists.
#ifdef WIN32


#include "vkbatch.h"
#include "vkloader.h"
#include "vkrect.h"

#include <string>
#include <vector>

class VkContext
{
public:
    static VkContext& instance();

    // Creates the whole context. windowHandle is an HWND (passed as void* so the header
    // does not drag in windows.h). Returns false when anything fails - we then stay on GL.
    bool init(void* windowHandle, int width, int height);

    // Recreates the swapchain after a window resize. Safe with a minimized window
    // (size 0) - then it only remembers the size and does nothing.
    bool recreateSwapchain(int width, int height);

    // Draws and presents one frame: clears the color attachment with the given color.
    // Returns false ONLY on an unrecoverable error (the context is then already shut down,
    // isReady() gives false) - the caller must then go back to GL's swapBuffers.
    // Swapchain loss/staleness is NOT an error: we recreate it and return true.
    bool drawFrame(float r, float g, float b);

    void terminate();

    bool isReady() const { return m_ready; }
    const std::string& getError() const { return m_error; }
    const std::string& getDeviceName() const { return m_deviceName; }
    uint32_t getSwapchainImageCount() const { return static_cast<uint32_t>(m_swapchainImages.size()); }

    // Stage 4: the feeder feeds the batch geometry BEFORE drawFrame, so it must get a handle on it
    // together with the current swapchain size (for clamping the scissors).
    VkSpriteBatch& getBatch() { return m_batch; }
    const VkExtent2D& getExtent() const { return m_swapchainExtent; }

    VkContext(const VkContext&) = delete;
    VkContext& operator=(const VkContext&) = delete;

private:
    VkContext() = default;
    ~VkContext();

    bool createInstance();
    bool pickPhysicalDevice();
    bool createSurface(void* windowHandle);
    bool createDevice();
    bool createSwapchain(int width, int height);
    void destroySwapchain();

    bool createRenderPass();
    bool createFramebuffers();
    bool createCommandBuffers();
    bool createSyncObjects();
    void destroyFramebuffers();
    void destroySyncObjects();

    // Recreates the swapchain from the CURRENT surface size read from the driver.
    // drawFrame does not know the window size, and caps.currentExtent on Win32 always does - thanks
    // to that reacting to a resize does not require hooking into window events.
    bool refreshSwapchain();

    bool fail(const std::string& reason);

    // Two frames in flight: the CPU can prepare the next one while the card draws the current one,
    // and there is still no risk of outrunning the swapchain (which has 3 images).
    static constexpr uint32_t MAX_FRAMES_IN_FLIGHT = 2;

    // --- state ---
    VkInstance m_instance{ VK_NULL_HANDLE };
    VkPhysicalDevice m_physicalDevice{ VK_NULL_HANDLE };
    VkDevice m_device{ VK_NULL_HANDLE };
    VkSurfaceKHR m_surface{ VK_NULL_HANDLE };
    VkSwapchainKHR m_swapchain{ VK_NULL_HANDLE };

    VkQueue m_graphicsQueue{ VK_NULL_HANDLE };
    VkQueue m_presentQueue{ VK_NULL_HANDLE };
    uint32_t m_graphicsFamily{ UINT32_MAX };
    uint32_t m_presentFamily{ UINT32_MAX };

    std::vector<VkImage> m_swapchainImages;
    std::vector<VkImageView> m_swapchainViews;
    VkFormat m_swapchainFormat{ VK_FORMAT_UNDEFINED };
    VkExtent2D m_swapchainExtent{ 0, 0 };

    VkRenderPass m_renderPass{ VK_NULL_HANDLE };
    std::vector<VkFramebuffer> m_framebuffers;

    VkCommandPool m_commandPool{ VK_NULL_HANDLE };
    std::vector<VkCommandBuffer> m_commandBuffers;

    // Stage 3: the atlas sprite batch - N rectangles in one draw call. This is the MAIN
    // path; everything the client will draw is supposed to go exactly this way.
    VkSpriteBatch m_batch;

    // Stage 2: a single textured rectangle drawn inside the render pass. Held as a field,
    // not a pointer, because its lifetime is exactly the context's. When its init()
    // fails, the context keeps running and only clears the screen (the rectangle's isReady()
    // gives false). Since stage 3 it is a FALLBACK: we initialize it only when the sprite batch
    // failed (e.g. sprite.*.spv missing), so the screen still shows the renderer is alive.
    VkRectRenderer m_rect;

    std::vector<VkSemaphore> m_imageAvailable;   // one per frame in flight
    std::vector<VkSemaphore> m_renderFinished;   // one per swapchain IMAGE - see createSyncObjects
    std::vector<VkFence> m_inFlight;             // one per frame in flight
    uint32_t m_currentFrame{ 0 };

    std::string m_deviceName;
    std::string m_error;
    bool m_ready{ false };

    // --- instance/device functions (local, not global) ---
    PFN_vkDestroySurfaceKHR m_vkDestroySurfaceKHR{ nullptr };
    PFN_vkGetPhysicalDeviceSurfaceSupportKHR m_vkGetPhysicalDeviceSurfaceSupportKHR{ nullptr };
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR m_vkGetPhysicalDeviceSurfaceCapabilitiesKHR{ nullptr };
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR m_vkGetPhysicalDeviceSurfaceFormatsKHR{ nullptr };
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR m_vkGetPhysicalDeviceSurfacePresentModesKHR{ nullptr };

    PFN_vkCreateSwapchainKHR m_vkCreateSwapchainKHR{ nullptr };
    PFN_vkDestroySwapchainKHR m_vkDestroySwapchainKHR{ nullptr };
    PFN_vkGetSwapchainImagesKHR m_vkGetSwapchainImagesKHR{ nullptr };
    PFN_vkCreateImageView m_vkCreateImageView{ nullptr };
    PFN_vkDestroyImageView m_vkDestroyImageView{ nullptr };

    PFN_vkCreateRenderPass m_vkCreateRenderPass{ nullptr };
    PFN_vkDestroyRenderPass m_vkDestroyRenderPass{ nullptr };
    PFN_vkCreateFramebuffer m_vkCreateFramebuffer{ nullptr };
    PFN_vkDestroyFramebuffer m_vkDestroyFramebuffer{ nullptr };

    PFN_vkCreateCommandPool m_vkCreateCommandPool{ nullptr };
    PFN_vkDestroyCommandPool m_vkDestroyCommandPool{ nullptr };
    PFN_vkAllocateCommandBuffers m_vkAllocateCommandBuffers{ nullptr };
    PFN_vkBeginCommandBuffer m_vkBeginCommandBuffer{ nullptr };
    PFN_vkEndCommandBuffer m_vkEndCommandBuffer{ nullptr };
    PFN_vkResetCommandBuffer m_vkResetCommandBuffer{ nullptr };
    PFN_vkCmdBeginRenderPass m_vkCmdBeginRenderPass{ nullptr };
    PFN_vkCmdEndRenderPass m_vkCmdEndRenderPass{ nullptr };

    PFN_vkCreateSemaphore m_vkCreateSemaphore{ nullptr };
    PFN_vkDestroySemaphore m_vkDestroySemaphore{ nullptr };
    PFN_vkCreateFence m_vkCreateFence{ nullptr };
    PFN_vkDestroyFence m_vkDestroyFence{ nullptr };
    PFN_vkWaitForFences m_vkWaitForFences{ nullptr };
    PFN_vkResetFences m_vkResetFences{ nullptr };

    PFN_vkQueueSubmit m_vkQueueSubmit{ nullptr };
    PFN_vkAcquireNextImageKHR m_vkAcquireNextImageKHR{ nullptr };
    PFN_vkQueuePresentKHR m_vkQueuePresentKHR{ nullptr };
};

#endif // WIN32
