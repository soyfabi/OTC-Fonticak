
// The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
// dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
// so it can sit unconditionally on the source list in CMakeLists.
#ifdef WIN32
#include "vkcontext.h"

#include <framework/core/configmanager.h>
#include <framework/core/logger.h>
#include <framework/platform/platformwindow.h>

#include <algorithm>

#ifdef WIN32
#include <windows.h>
#include <vulkan/vulkan_win32.h>
#endif

VkContext& VkContext::instance()
{
    static VkContext ctx;
    return ctx;
}

VkContext::~VkContext()
{
    terminate();
}

bool VkContext::fail(const std::string& reason)
{
    m_error = reason;
    g_logger.warning("[vulkan] {} - staying on the OpenGL path", reason);
    terminate();
    return false;
}

bool VkContext::init(void* windowHandle, const int width, const int height)
{
    if (m_ready)
        return true;

    if (!VkLoader::instance().load())
        return fail(VkLoader::instance().getError());

    if (!createInstance())
        return false;

    if (!createSurface(windowHandle))
        return false;

    if (!pickPhysicalDevice())
        return false;

    if (!createDevice())
        return false;

    if (!createSwapchain(width, height))
        return false;

    // The render pass is created ONCE and survives swapchain recreation: it depends only on the
    // color format, and that does not change on window resize.
    if (!createRenderPass())
        return false;

    if (!createFramebuffers())
        return false;

    if (!createCommandBuffers())
        return false;

    if (!createSyncObjects())
        return false;

    m_ready = true;

    // Stages 2 and 3 are OPTIONAL: missing .spv files or images must not take down the whole
    // backend, because the stage 1 screen clearing works independently of them. So we ignore the
    // result - the failure reason already went to the log in their own fail().
    // We call this AFTER m_ready = true, because then a possible fail() cannot accidentally kill
    // the context (these classes' terminate() touches nothing that belongs to VkContext).
    //
    // The order is deliberate: the sprite batch first (stage 3, the main path), and the stage 2
    // rectangle ONLY as a fallback. If both ran at once, the stage 2 logo would overlap the tile
    // grid and the visual test would stop being unambiguous - and we would still pay for a second
    // pipeline and a second texture that no longer contribute anything.
    // The atlas layer size comes from config.ini (graphics.mapAtlasSize, 2048 for us).
    // A value <= 0 ("auto" on the GL side or a typo) = a safe 2048; clamped from both sides,
    // because the config field is int16_t and a negative value would sign-extend into billions
    // of pixels, while a too-small atlas would not even fit the login background.
    const int32_t configuredAtlasSize = g_configs.getPublicConfig().graphics.mapAtlasSize;
    const uint32_t atlasSize = configuredAtlasSize <= 0
        ? 2048u
        : std::clamp<uint32_t>(static_cast<uint32_t>(configuredAtlasSize), 1024u, 8192u);

    if (!m_batch.init(m_physicalDevice, m_device, m_renderPass, m_graphicsQueue, m_commandPool,
                      MAX_FRAMES_IN_FLIGHT, atlasSize)) {
        m_rect.init(m_physicalDevice, m_device, m_renderPass, m_graphicsQueue, m_commandPool);
    }

    return true;
}

bool VkContext::createInstance()
{
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "CrystalOTC";
    appInfo.apiVersion = VK_API_VERSION_1_1;

    // Without these two extensions drawing to a window is impossible at all.
    std::vector<const char*> extensions{ VK_KHR_SURFACE_EXTENSION_NAME };
#ifdef WIN32
    extensions.push_back(VK_KHR_WIN32_SURFACE_EXTENSION_NAME);
#endif

    for (const auto* ext : extensions) {
        if (!VkLoader::instance().hasInstanceExtension(ext))
            return fail(std::string("missing required instance extension: ") + ext);
    }

    // Validation layers only in debug: in release they cost and are often absent on a player's machine.
    std::vector<const char*> layers;
#ifndef NDEBUG
    static const char* kValidation = "VK_LAYER_KHRONOS_validation";
    uint32_t layerCount = 0;
    if (vkEnumerateInstanceLayerProperties && vkEnumerateInstanceLayerProperties(&layerCount, nullptr) == VK_SUCCESS && layerCount > 0) {
        std::vector<VkLayerProperties> available(layerCount);
        vkEnumerateInstanceLayerProperties(&layerCount, available.data());
        for (const auto& l : available) {
            if (std::string(l.layerName) == kValidation) {
                layers.push_back(kValidation);
                g_logger.info("[vulkan] validation layers enabled");
                break;
            }
        }
    }
#endif

    VkInstanceCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    info.pApplicationInfo = &appInfo;
    info.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    info.ppEnabledExtensionNames = extensions.data();
    info.enabledLayerCount = static_cast<uint32_t>(layers.size());
    info.ppEnabledLayerNames = layers.empty() ? nullptr : layers.data();

    if (vkCreateInstance(&info, nullptr, &m_instance) != VK_SUCCESS)
        return fail("failed to create the instance");

    if (!VkLoader::instance().loadInstanceFunctions(m_instance))
        return fail(VkLoader::instance().getError());

    const auto fn = [this](const char* name) { return vkGetInstanceProcAddr(m_instance, name); };

    m_vkDestroySurfaceKHR = reinterpret_cast<PFN_vkDestroySurfaceKHR>(fn("vkDestroySurfaceKHR"));
    m_vkGetPhysicalDeviceSurfaceSupportKHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(fn("vkGetPhysicalDeviceSurfaceSupportKHR"));
    m_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR>(fn("vkGetPhysicalDeviceSurfaceCapabilitiesKHR"));
    m_vkGetPhysicalDeviceSurfaceFormatsKHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(fn("vkGetPhysicalDeviceSurfaceFormatsKHR"));
    m_vkGetPhysicalDeviceSurfacePresentModesKHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfacePresentModesKHR>(fn("vkGetPhysicalDeviceSurfacePresentModesKHR"));

    if (!m_vkGetPhysicalDeviceSurfaceSupportKHR || !m_vkGetPhysicalDeviceSurfaceCapabilitiesKHR)
        return fail("missing surface support functions");

    return true;
}

bool VkContext::createSurface(void* windowHandle)
{
#ifdef WIN32
    if (!windowHandle)
        return fail("missing window handle");

    const auto createWin32Surface = reinterpret_cast<PFN_vkCreateWin32SurfaceKHR>(
        vkGetInstanceProcAddr(m_instance, "vkCreateWin32SurfaceKHR"));

    if (!createWin32Surface)
        return fail("missing vkCreateWin32SurfaceKHR");

    VkWin32SurfaceCreateInfoKHR info{};
    info.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
    info.hinstance = GetModuleHandleW(nullptr);
    info.hwnd = static_cast<HWND>(windowHandle);

    if (createWin32Surface(m_instance, &info, nullptr, &m_surface) != VK_SUCCESS)
        return fail("failed to create the window surface");

    return true;
#else
    (void)windowHandle;
    return fail("window surface implemented only for Windows");
#endif
}

bool VkContext::pickPhysicalDevice()
{
    uint32_t count = 0;
    vkEnumeratePhysicalDevices(m_instance, &count, nullptr);

    if (count == 0)
        return fail("no devices supporting Vulkan");

    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(m_instance, &count, devices.data());

    // Scoring: a dedicated card beats an integrated one. On a laptop with two GPUs (RTX + Radeon)
    // we would otherwise land on the integrated one, since it tends to be first on the list.
    int bestScore = -1;

    for (const auto& dev : devices) {
        VkPhysicalDeviceProperties props{};
        vkGetPhysicalDeviceProperties(dev, &props);

        uint32_t queueCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(dev, &queueCount, nullptr);
        if (queueCount == 0)
            continue;

        std::vector<VkQueueFamilyProperties> families(queueCount);
        vkGetPhysicalDeviceQueueFamilyProperties(dev, &queueCount, families.data());

        uint32_t graphics = UINT32_MAX;
        uint32_t present = UINT32_MAX;

        for (uint32_t i = 0; i < queueCount; ++i) {
            if ((families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && graphics == UINT32_MAX)
                graphics = i;

            VkBool32 supported = VK_FALSE;
            m_vkGetPhysicalDeviceSurfaceSupportKHR(dev, i, m_surface, &supported);
            if (supported && present == UINT32_MAX)
                present = i;
        }

        // a device without both queue families is useless to us
        if (graphics == UINT32_MAX || present == UINT32_MAX)
            continue;

        int score = 0;
        switch (props.deviceType) {
            case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU: score = 1000; break;
            case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: score = 500; break;
            case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU: score = 100; break;
            default: score = 10; break;
        }

        // the same family for graphics and presentation = less synchronization
        if (graphics == present)
            score += 50;

        if (score > bestScore) {
            bestScore = score;
            m_physicalDevice = dev;
            m_graphicsFamily = graphics;
            m_presentFamily = present;
            m_deviceName = props.deviceName;
        }
    }

    if (m_physicalDevice == VK_NULL_HANDLE)
        return fail("no device supports both graphics and presentation to this window");

    return true;
}

bool VkContext::createDevice()
{
    const float priority = 1.0f;
    std::vector<VkDeviceQueueCreateInfo> queueInfos;

    // when both families are the same, we create ONE queue - Vulkan forbids duplicates
    std::vector<uint32_t> families{ m_graphicsFamily };
    if (m_presentFamily != m_graphicsFamily)
        families.push_back(m_presentFamily);

    for (const uint32_t family : families) {
        VkDeviceQueueCreateInfo qi{};
        qi.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qi.queueFamilyIndex = family;
        qi.queueCount = 1;
        qi.pQueuePriorities = &priority;
        queueInfos.push_back(qi);
    }

    const char* deviceExtensions[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };

    VkDeviceCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    info.queueCreateInfoCount = static_cast<uint32_t>(queueInfos.size());
    info.pQueueCreateInfos = queueInfos.data();
    info.enabledExtensionCount = 1;
    info.ppEnabledExtensionNames = deviceExtensions;

    if (vkCreateDevice(m_physicalDevice, &info, nullptr, &m_device) != VK_SUCCESS)
        return fail("failed to create the logical device");

    if (!VkLoader::instance().loadDeviceFunctions(m_device))
        return fail(VkLoader::instance().getError());

    const auto fn = [this](const char* name) { return vkGetDeviceProcAddr(m_device, name); };

    m_vkCreateSwapchainKHR = reinterpret_cast<PFN_vkCreateSwapchainKHR>(fn("vkCreateSwapchainKHR"));
    m_vkDestroySwapchainKHR = reinterpret_cast<PFN_vkDestroySwapchainKHR>(fn("vkDestroySwapchainKHR"));
    m_vkGetSwapchainImagesKHR = reinterpret_cast<PFN_vkGetSwapchainImagesKHR>(fn("vkGetSwapchainImagesKHR"));
    m_vkCreateImageView = reinterpret_cast<PFN_vkCreateImageView>(fn("vkCreateImageView"));
    m_vkDestroyImageView = reinterpret_cast<PFN_vkDestroyImageView>(fn("vkDestroyImageView"));

    if (!m_vkCreateSwapchainKHR || !m_vkGetSwapchainImagesKHR || !m_vkCreateImageView)
        return fail("missing swapchain functions");

    m_vkCreateRenderPass = reinterpret_cast<PFN_vkCreateRenderPass>(fn("vkCreateRenderPass"));
    m_vkDestroyRenderPass = reinterpret_cast<PFN_vkDestroyRenderPass>(fn("vkDestroyRenderPass"));
    m_vkCreateFramebuffer = reinterpret_cast<PFN_vkCreateFramebuffer>(fn("vkCreateFramebuffer"));
    m_vkDestroyFramebuffer = reinterpret_cast<PFN_vkDestroyFramebuffer>(fn("vkDestroyFramebuffer"));

    m_vkCreateCommandPool = reinterpret_cast<PFN_vkCreateCommandPool>(fn("vkCreateCommandPool"));
    m_vkDestroyCommandPool = reinterpret_cast<PFN_vkDestroyCommandPool>(fn("vkDestroyCommandPool"));
    m_vkAllocateCommandBuffers = reinterpret_cast<PFN_vkAllocateCommandBuffers>(fn("vkAllocateCommandBuffers"));
    m_vkBeginCommandBuffer = reinterpret_cast<PFN_vkBeginCommandBuffer>(fn("vkBeginCommandBuffer"));
    m_vkEndCommandBuffer = reinterpret_cast<PFN_vkEndCommandBuffer>(fn("vkEndCommandBuffer"));
    m_vkResetCommandBuffer = reinterpret_cast<PFN_vkResetCommandBuffer>(fn("vkResetCommandBuffer"));
    m_vkCmdBeginRenderPass = reinterpret_cast<PFN_vkCmdBeginRenderPass>(fn("vkCmdBeginRenderPass"));
    m_vkCmdEndRenderPass = reinterpret_cast<PFN_vkCmdEndRenderPass>(fn("vkCmdEndRenderPass"));

    m_vkCreateSemaphore = reinterpret_cast<PFN_vkCreateSemaphore>(fn("vkCreateSemaphore"));
    m_vkDestroySemaphore = reinterpret_cast<PFN_vkDestroySemaphore>(fn("vkDestroySemaphore"));
    m_vkCreateFence = reinterpret_cast<PFN_vkCreateFence>(fn("vkCreateFence"));
    m_vkDestroyFence = reinterpret_cast<PFN_vkDestroyFence>(fn("vkDestroyFence"));
    m_vkWaitForFences = reinterpret_cast<PFN_vkWaitForFences>(fn("vkWaitForFences"));
    m_vkResetFences = reinterpret_cast<PFN_vkResetFences>(fn("vkResetFences"));

    m_vkQueueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(fn("vkQueueSubmit"));
    m_vkAcquireNextImageKHR = reinterpret_cast<PFN_vkAcquireNextImageKHR>(fn("vkAcquireNextImageKHR"));
    m_vkQueuePresentKHR = reinterpret_cast<PFN_vkQueuePresentKHR>(fn("vkQueuePresentKHR"));

    // We check the full set right away so any missing function shows up at startup (and falls
    // back to GL), not later in the frame loop as a jump to nullptr.
    if (!m_vkCreateRenderPass || !m_vkCreateFramebuffer || !m_vkCreateCommandPool ||
        !m_vkAllocateCommandBuffers || !m_vkBeginCommandBuffer || !m_vkEndCommandBuffer ||
        !m_vkResetCommandBuffer || !m_vkCmdBeginRenderPass || !m_vkCmdEndRenderPass ||
        !m_vkCreateSemaphore || !m_vkCreateFence || !m_vkWaitForFences || !m_vkResetFences ||
        !m_vkQueueSubmit || !m_vkAcquireNextImageKHR || !m_vkQueuePresentKHR)
        return fail("missing frame loop functions");

    vkGetDeviceQueue(m_device, m_graphicsFamily, 0, &m_graphicsQueue);
    vkGetDeviceQueue(m_device, m_presentFamily, 0, &m_presentQueue);

    return true;
}

bool VkContext::createSwapchain(const int width, const int height)
{
    VkSurfaceCapabilitiesKHR caps{};
    if (m_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(m_physicalDevice, m_surface, &caps) != VK_SUCCESS)
        return fail("failed to read the surface capabilities");

    // Format: UNORM, not SRGB - DELIBERATELY (stage 4). The client's GL path does all its
    // arithmetic (tints, opacity, blending) on raw sRGB bytes without linearization; an _SRGB
    // format would introduce hardware sRGB<->linear conversion around every multiply and blend,
    // making semi-transparencies and tinted sprites look different than in GL.
    // UNORM gives the same arithmetic byte for byte.
    uint32_t formatCount = 0;
    m_vkGetPhysicalDeviceSurfaceFormatsKHR(m_physicalDevice, m_surface, &formatCount, nullptr);
    if (formatCount == 0)
        return fail("the surface reports no formats");

    std::vector<VkSurfaceFormatKHR> formats(formatCount);
    m_vkGetPhysicalDeviceSurfaceFormatsKHR(m_physicalDevice, m_surface, &formatCount, formats.data());

    VkSurfaceFormatKHR chosen = formats[0];
    for (const auto& f : formats) {
        if (f.format == VK_FORMAT_B8G8R8A8_UNORM && f.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            chosen = f;
            break;
        }
    }

    // Presentation mode, driven by the client's vsync setting:
    //   vsync ON  -> FIFO: capped at the monitor refresh, no tearing.
    //   vsync OFF -> IMMEDIATE preferred: UNCAPPED FPS (may tear), lowest latency; then MAILBOX,
    //                then FIFO as the last resort.
    // Why not MAILBOX when vsync is off: MAILBOX presents at most once per vblank (it just swaps
    // the queued image for a fresher one), so it STILL pins the FPS to the refresh rate - which
    // is exactly the "max 144 fps" the user saw. Only IMMEDIATE lets the FPS exceed the refresh.
    const bool wantVsync = g_window.vsyncEnabled();

    VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
    {
        uint32_t presentModeCount = 0;
        m_vkGetPhysicalDeviceSurfacePresentModesKHR(m_physicalDevice, m_surface, &presentModeCount, nullptr);
        std::vector<VkPresentModeKHR> presentModes(presentModeCount);
        if (presentModeCount > 0)
            m_vkGetPhysicalDeviceSurfacePresentModesKHR(m_physicalDevice, m_surface, &presentModeCount, presentModes.data());

        bool hasImmediate = false;
        bool hasMailbox = false;
        for (const VkPresentModeKHR mode : presentModes) {
            if (mode == VK_PRESENT_MODE_IMMEDIATE_KHR)
                hasImmediate = true;
            else if (mode == VK_PRESENT_MODE_MAILBOX_KHR)
                hasMailbox = true;
        }

        if (!wantVsync) {
            if (hasImmediate)
                presentMode = VK_PRESENT_MODE_IMMEDIATE_KHR;
            else if (hasMailbox)
                presentMode = VK_PRESENT_MODE_MAILBOX_KHR;
        }
    }

    VkExtent2D extent = caps.currentExtent;
    if (extent.width == UINT32_MAX) { // the window manager lets us pick the size
        extent.width = std::clamp<uint32_t>(static_cast<uint32_t>(width), caps.minImageExtent.width, caps.maxImageExtent.width);
        extent.height = std::clamp<uint32_t>(static_cast<uint32_t>(height), caps.minImageExtent.height, caps.maxImageExtent.height);
    }

    if (extent.width == 0 || extent.height == 0)
        return fail("the window has zero size");

    uint32_t imageCount = caps.minImageCount + 1; // +1 so we do not wait on the driver
    if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount)
        imageCount = caps.maxImageCount;

    VkSwapchainCreateInfoKHR info{};
    info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    info.surface = m_surface;
    info.minImageCount = imageCount;
    info.imageFormat = chosen.format;
    info.imageColorSpace = chosen.colorSpace;
    info.imageExtent = extent;
    info.imageArrayLayers = 1;
    info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    info.preTransform = caps.currentTransform;
    info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    info.presentMode = presentMode;
    info.clipped = VK_TRUE;

    const uint32_t families[] = { m_graphicsFamily, m_presentFamily };
    if (m_graphicsFamily != m_presentFamily) {
        info.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
        info.queueFamilyIndexCount = 2;
        info.pQueueFamilyIndices = families;
    } else {
        info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    }

    if (m_vkCreateSwapchainKHR(m_device, &info, nullptr, &m_swapchain) != VK_SUCCESS)
        return fail("failed to create the swapchain");

    m_swapchainFormat = chosen.format;
    m_swapchainExtent = extent;

    uint32_t actualCount = 0;
    m_vkGetSwapchainImagesKHR(m_device, m_swapchain, &actualCount, nullptr);
    m_swapchainImages.resize(actualCount);
    m_vkGetSwapchainImagesKHR(m_device, m_swapchain, &actualCount, m_swapchainImages.data());

    m_swapchainViews.resize(actualCount, VK_NULL_HANDLE);
    for (uint32_t i = 0; i < actualCount; ++i) {
        VkImageViewCreateInfo vi{};
        vi.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        vi.image = m_swapchainImages[i];
        vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
        vi.format = m_swapchainFormat;
        vi.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        vi.subresourceRange.levelCount = 1;
        vi.subresourceRange.layerCount = 1;

        if (m_vkCreateImageView(m_device, &vi, nullptr, &m_swapchainViews[i]) != VK_SUCCESS)
            return fail("failed to create a swapchain image view");
    }

    return true;
}

void VkContext::destroySwapchain()
{
    if (m_device == VK_NULL_HANDLE)
        return;

    if (m_vkDestroyImageView) {
        for (auto& view : m_swapchainViews) {
            if (view != VK_NULL_HANDLE)
                m_vkDestroyImageView(m_device, view, nullptr);
        }
    }

    m_swapchainViews.clear();
    m_swapchainImages.clear();

    if (m_swapchain != VK_NULL_HANDLE && m_vkDestroySwapchainKHR) {
        m_vkDestroySwapchainKHR(m_device, m_swapchain, nullptr);
        m_swapchain = VK_NULL_HANDLE;
    }
}

bool VkContext::createRenderPass()
{
    VkAttachmentDescription color{};
    color.format = m_swapchainFormat;
    color.samples = VK_SAMPLE_COUNT_1_BIT;
    color.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;   // clearing with a color is the whole point of stage 1
    color.storeOp = VK_ATTACHMENT_STORE_OP_STORE; // the result must survive until presentation
    color.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    color.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    // UNDEFINED on entry, because the image's previous contents do not interest us - we clear anyway
    color.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    color.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    VkAttachmentReference colorRef{};
    colorRef.attachment = 0;
    colorRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorRef;

    // Without this dependency the UNDEFINED->COLOR_ATTACHMENT_OPTIMAL layout transition can start
    // before the imageAvailable semaphore reports the image is free; waiting at the color-write
    // stage ties the render pass to the submit's waitStage.
    VkSubpassDependency dep{};
    dep.srcSubpass = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass = 0;
    dep.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.srcAccessMask = 0;
    dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    info.attachmentCount = 1;
    info.pAttachments = &color;
    info.subpassCount = 1;
    info.pSubpasses = &subpass;
    info.dependencyCount = 1;
    info.pDependencies = &dep;

    if (m_vkCreateRenderPass(m_device, &info, nullptr, &m_renderPass) != VK_SUCCESS)
        return fail("failed to create the render pass");

    return true;
}

bool VkContext::createFramebuffers()
{
    m_framebuffers.resize(m_swapchainViews.size(), VK_NULL_HANDLE);

    for (size_t i = 0; i < m_swapchainViews.size(); ++i) {
        VkFramebufferCreateInfo info{};
        info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        info.renderPass = m_renderPass;
        info.attachmentCount = 1;
        info.pAttachments = &m_swapchainViews[i];
        info.width = m_swapchainExtent.width;
        info.height = m_swapchainExtent.height;
        info.layers = 1;

        if (m_vkCreateFramebuffer(m_device, &info, nullptr, &m_framebuffers[i]) != VK_SUCCESS)
            return fail("failed to create a framebuffer");
    }

    return true;
}

void VkContext::destroyFramebuffers()
{
    if (m_device == VK_NULL_HANDLE || !m_vkDestroyFramebuffer)
        return;

    for (auto& fb : m_framebuffers) {
        if (fb != VK_NULL_HANDLE)
            m_vkDestroyFramebuffer(m_device, fb, nullptr);
    }

    m_framebuffers.clear();
}

bool VkContext::createCommandBuffers()
{
    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    // RESET_COMMAND_BUFFER allows re-recording the same buffer every frame without resetting the whole pool
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = m_graphicsFamily;

    if (m_vkCreateCommandPool(m_device, &poolInfo, nullptr, &m_commandPool) != VK_SUCCESS)
        return fail("failed to create the command pool");

    m_commandBuffers.resize(MAX_FRAMES_IN_FLIGHT, VK_NULL_HANDLE);

    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = m_commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT;

    if (m_vkAllocateCommandBuffers(m_device, &allocInfo, m_commandBuffers.data()) != VK_SUCCESS)
        return fail("failed to allocate command buffers");

    return true;
}

bool VkContext::createSyncObjects()
{
    VkSemaphoreCreateInfo semInfo{};
    semInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    // signaled from the start, otherwise the first vkWaitForFences would hang forever
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    m_imageAvailable.resize(MAX_FRAMES_IN_FLIGHT, VK_NULL_HANDLE);
    m_inFlight.resize(MAX_FRAMES_IN_FLIGHT, VK_NULL_HANDLE);

    for (uint32_t i = 0; i < MAX_FRAMES_IN_FLIGHT; ++i) {
        if (m_vkCreateSemaphore(m_device, &semInfo, nullptr, &m_imageAvailable[i]) != VK_SUCCESS)
            return fail("failed to create the image-availability semaphore");

        if (m_vkCreateFence(m_device, &fenceInfo, nullptr, &m_inFlight[i]) != VK_SUCCESS)
            return fail("failed to create the frame fence");
    }

    // renderFinished must be PER IMAGE, not per frame in flight: the presentation engine waits
    // on the present semaphore, and it does not release it in the rhythm of our fences. With 2
    // frames and 3 images a per-frame semaphore can be reused while the previous
    // presentation still hangs on it - indexing by image rules out that race.
    m_renderFinished.resize(m_swapchainImages.size(), VK_NULL_HANDLE);
    for (auto& sem : m_renderFinished) {
        if (m_vkCreateSemaphore(m_device, &semInfo, nullptr, &sem) != VK_SUCCESS)
            return fail("failed to create the render-finished semaphore");
    }

    return true;
}

void VkContext::destroySyncObjects()
{
    if (m_device == VK_NULL_HANDLE)
        return;

    if (m_vkDestroySemaphore) {
        for (auto& sem : m_imageAvailable) {
            if (sem != VK_NULL_HANDLE)
                m_vkDestroySemaphore(m_device, sem, nullptr);
        }
        for (auto& sem : m_renderFinished) {
            if (sem != VK_NULL_HANDLE)
                m_vkDestroySemaphore(m_device, sem, nullptr);
        }
    }

    if (m_vkDestroyFence) {
        for (auto& fence : m_inFlight) {
            if (fence != VK_NULL_HANDLE)
                m_vkDestroyFence(m_device, fence, nullptr);
        }
    }

    m_imageAvailable.clear();
    m_renderFinished.clear();
    m_inFlight.clear();
    m_currentFrame = 0;
}

bool VkContext::recreateSwapchain(const int width, const int height)
{
    if (!m_ready)
        return false;

    // minimized window: there is nothing to create, we wait for it to be restored
    if (width <= 0 || height <= 0)
        return true;

    if (vkDeviceWaitIdle)
        vkDeviceWaitIdle(m_device);

    // Framebuffers hold the views of the old images, so they die together with the swapchain.
    // The render pass stays - it depends only on the format, and that does not change.
    destroyFramebuffers();
    destroySwapchain();

    if (!createSwapchain(width, height))
        return false;

    if (!createFramebuffers())
        return false;

    // The swapchain image count can change, and the present semaphores are indexed by image.
    if (m_renderFinished.size() != m_swapchainImages.size()) {
        VkSemaphoreCreateInfo semInfo{};
        semInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

        if (m_vkDestroySemaphore) {
            for (auto& sem : m_renderFinished) {
                if (sem != VK_NULL_HANDLE)
                    m_vkDestroySemaphore(m_device, sem, nullptr);
            }
        }

        m_renderFinished.assign(m_swapchainImages.size(), VK_NULL_HANDLE);
        for (auto& sem : m_renderFinished) {
            if (m_vkCreateSemaphore(m_device, &semInfo, nullptr, &sem) != VK_SUCCESS)
                return fail("failed to recreate the render-finished semaphore");
        }
    }

    return true;
}

bool VkContext::refreshSwapchain()
{
    VkSurfaceCapabilitiesKHR caps{};
    if (m_vkGetPhysicalDeviceSurfaceCapabilitiesKHR(m_physicalDevice, m_surface, &caps) != VK_SUCCESS)
        return fail("failed to read the surface capabilities while recreating the swapchain");

    // Minimized window (0x0): the recreation would crash, so we simply skip the frame.
    if (caps.currentExtent.width == 0 || caps.currentExtent.height == 0)
        return true;

    const uint32_t width = caps.currentExtent.width == UINT32_MAX ? m_swapchainExtent.width : caps.currentExtent.width;
    const uint32_t height = caps.currentExtent.height == UINT32_MAX ? m_swapchainExtent.height : caps.currentExtent.height;

    return recreateSwapchain(static_cast<int>(width), static_cast<int>(height));
}

bool VkContext::drawFrame(const float r, const float g, const float b)
{
    if (!m_ready || m_swapchain == VK_NULL_HANDLE)
        return false;

    if (m_vkWaitForFences(m_device, 1, &m_inFlight[m_currentFrame], VK_TRUE, UINT64_MAX) != VK_SUCCESS)
        return fail("waiting on the frame fence failed");

    uint32_t imageIndex = 0;
    const VkResult acquired = m_vkAcquireNextImageKHR(m_device, m_swapchain, UINT64_MAX,
                                                      m_imageAvailable[m_currentFrame], VK_NULL_HANDLE, &imageIndex);

    // OUT_OF_DATE at acquire: the image was NOT acquired and the semaphore is NOT signaled,
    // so the frame can be safely abandoned and the swapchain rebuilt.
    if (acquired == VK_ERROR_OUT_OF_DATE_KHR)
        return refreshSwapchain();

    // SUBOPTIMAL is a different thing: the image IS ours and the semaphore is ALREADY signaled.
    // Abandoning the frame would leave a dangling semaphore, so we finish the frame and rebuild
    // after presentation.
    bool needsRecreate = acquired == VK_SUBOPTIMAL_KHR;

    if (acquired != VK_SUCCESS && !needsRecreate)
        return fail("vkAcquireNextImageKHR failed");

    // fence reset only HERE: if we did it before acquiring the image, exiting through the
    // OUT_OF_DATE path would leave the fence unsignaled and the next frame would hang
    if (m_vkResetFences(m_device, 1, &m_inFlight[m_currentFrame]) != VK_SUCCESS)
        return fail("resetting the frame fence failed");

    const VkCommandBuffer cmd = m_commandBuffers[m_currentFrame];

    if (m_vkResetCommandBuffer(cmd, 0) != VK_SUCCESS)
        return fail("resetting the command buffer failed");

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    if (m_vkBeginCommandBuffer(cmd, &beginInfo) != VK_SUCCESS)
        return fail("beginning the command buffer failed");

    VkClearValue clear{};
    clear.color = { { r, g, b, 1.0f } };

    VkRenderPassBeginInfo rpInfo{};
    rpInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpInfo.renderPass = m_renderPass;
    rpInfo.framebuffer = m_framebuffers[imageIndex];
    rpInfo.renderArea.offset = { 0, 0 };
    rpInfo.renderArea.extent = m_swapchainExtent;
    rpInfo.clearValueCount = 1;
    rpInfo.pClearValues = &clear;

    // Entering the render pass performs the loadOp CLEAR (background), and exiting transitions
    // the image to PRESENT_SRC_KHR layout. In between, stage 3 draws (the sprite batch) or - if it
    // failed to initialize - stage 2 (the single rectangle). If neither works, both record() calls
    // are empty and only the stage 1 screen clearing remains.
    //
    // m_currentFrame is here the CORRECT frame-in-flight number: its fence was waited on above,
    // so the vertex buffer with that number is definitely no longer being read by the card.
    m_vkCmdBeginRenderPass(cmd, &rpInfo, VK_SUBPASS_CONTENTS_INLINE);
    m_batch.record(cmd, m_swapchainExtent, m_currentFrame);
    m_rect.record(cmd, m_swapchainExtent);
    m_vkCmdEndRenderPass(cmd);

    if (m_vkEndCommandBuffer(cmd) != VK_SUCCESS)
        return fail("ending the command buffer failed");

    const VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

    VkSubmitInfo submit{};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.waitSemaphoreCount = 1;
    submit.pWaitSemaphores = &m_imageAvailable[m_currentFrame];
    submit.pWaitDstStageMask = &waitStage;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &cmd;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &m_renderFinished[imageIndex];

    if (m_vkQueueSubmit(m_graphicsQueue, 1, &submit, m_inFlight[m_currentFrame]) != VK_SUCCESS)
        return fail("vkQueueSubmit failed");

    VkPresentInfoKHR present{};
    present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present.waitSemaphoreCount = 1;
    present.pWaitSemaphores = &m_renderFinished[imageIndex];
    present.swapchainCount = 1;
    present.pSwapchains = &m_swapchain;
    present.pImageIndices = &imageIndex;

    const VkResult presented = m_vkQueuePresentKHR(m_presentQueue, &present);

    if (presented == VK_ERROR_OUT_OF_DATE_KHR || presented == VK_SUBOPTIMAL_KHR)
        needsRecreate = true;
    else if (presented != VK_SUCCESS)
        return fail("vkQueuePresentKHR failed");

    m_currentFrame = (m_currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;

    return needsRecreate ? refreshSwapchain() : true;
}

void VkContext::terminate()
{
    // First we wait for the card to finish everything we sent it - otherwise we would be
    // destroying objects on which semaphores and in-flight command buffers still hang.
    if (m_device != VK_NULL_HANDLE && vkDeviceWaitIdle)
        vkDeviceWaitIdle(m_device);

    // The sprite batch and the rectangle go FIRST: their pipelines hold the render pass, and the
    // descriptors, buffers and atlas live on the same device - all of that is destroyed below,
    // so they must already be gone.
    m_batch.terminate();
    m_rect.terminate();

    // reverse creation order: synchronization -> commands -> framebuffers -> render pass -> swapchain
    destroySyncObjects();

    if (m_commandPool != VK_NULL_HANDLE && m_vkDestroyCommandPool) {
        // destroying the pool also frees all of its command buffers
        m_vkDestroyCommandPool(m_device, m_commandPool, nullptr);
        m_commandPool = VK_NULL_HANDLE;
    }
    m_commandBuffers.clear();

    destroyFramebuffers();

    if (m_renderPass != VK_NULL_HANDLE && m_vkDestroyRenderPass) {
        m_vkDestroyRenderPass(m_device, m_renderPass, nullptr);
        m_renderPass = VK_NULL_HANDLE;
    }

    destroySwapchain();

    if (m_device != VK_NULL_HANDLE && vkDestroyDevice) {
        vkDestroyDevice(m_device, nullptr);
        m_device = VK_NULL_HANDLE;
    }

    if (m_surface != VK_NULL_HANDLE && m_vkDestroySurfaceKHR) {
        m_vkDestroySurfaceKHR(m_instance, m_surface, nullptr);
        m_surface = VK_NULL_HANDLE;
    }

    if (m_instance != VK_NULL_HANDLE && vkDestroyInstance) {
        vkDestroyInstance(m_instance, nullptr);
        m_instance = VK_NULL_HANDLE;
    }

    m_physicalDevice = VK_NULL_HANDLE;
    m_graphicsQueue = VK_NULL_HANDLE;
    m_presentQueue = VK_NULL_HANDLE;
    m_ready = false;
}

#endif // WIN32
