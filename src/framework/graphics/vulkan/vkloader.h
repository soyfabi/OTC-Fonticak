/*
 * Dynamic loading of Vulkan.
 *
 * The client links statically (triplet x64-windows-static), while the Vulkan loader is a SYSTEM
 * component (vulkan-1.dll) - it must not be linked in hard, because the client would stop
 * launching on machines without a driver with Vulkan support. That is why we take only the HEADERS
 * from vcpkg, and fetch the function pointers at runtime. When the library is missing or an
 * instance cannot be created, VkLoader::isAvailable() returns false and the renderer falls back to the GL path.
 */

#pragma once
// The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
// dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
// which lets it stay unconditionally on the source list in CMakeLists.
#ifdef WIN32


#include <cstdint>
#include <string>
#include <vector>

 // headers from vcpkg (vulkan-headers); VK_NO_PROTOTYPES, because we load everything ourselves
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

class VkLoader
{
public:
    static VkLoader& instance();

    // Loads vulkan-1.dll and fetches the global functions. Safe to call multiple times.
    // Returns false when Vulkan is not present in the system - the caller must then use GL.
    bool load();

    // Fetches instance-dependent functions (vkCreateDevice, surface handling etc.).
    bool loadInstanceFunctions(VkInstance instance);

    // Fetches device-dependent functions - the faster path, bypassing the loader's dispatcher.
    bool loadDeviceFunctions(VkDevice device);

    bool isAvailable() const { return m_available; }
    const std::string& getError() const { return m_error; }

    // API version reported by the loader (e.g. VK_MAKE_API_VERSION(0, 1, 3, 0))
    uint32_t getInstanceVersion() const { return m_instanceVersion; }

    // whether the given instance extension is available
    bool hasInstanceExtension(const std::string& name) const;

    // Foundation test: creates a TEMPORARY instance, prints the detected cards and destroys it.
    // Leaves no state behind - its sole purpose is to confirm that the loader works
    // on the given machine, before we build a device and swapchain on top of it.
    // Returns the number of detected devices (0 = Vulkan unavailable).
    uint32_t probeDevices();

    void unload();

    VkLoader(const VkLoader&) = delete;
    VkLoader& operator=(const VkLoader&) = delete;

private:
    VkLoader() = default;
    ~VkLoader();

    void* getSymbol(const char* name) const;

    void* m_library{ nullptr };
    bool m_available{ false };
    uint32_t m_instanceVersion{ 0 };
    std::string m_error;
    std::vector<std::string> m_instanceExtensions;
};

// Global and instance-level functions are kept as variables - the headers are built with VK_NO_PROTOTYPES,
// so these are the only definitions in the program (declarations here, definitions in vkloader.cpp).
extern PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr;
extern PFN_vkEnumerateInstanceExtensionProperties vkEnumerateInstanceExtensionProperties;
extern PFN_vkEnumerateInstanceLayerProperties vkEnumerateInstanceLayerProperties;
extern PFN_vkCreateInstance vkCreateInstance;
extern PFN_vkDestroyInstance vkDestroyInstance;
extern PFN_vkEnumeratePhysicalDevices vkEnumeratePhysicalDevices;
extern PFN_vkGetPhysicalDeviceProperties vkGetPhysicalDeviceProperties;
extern PFN_vkGetPhysicalDeviceFeatures vkGetPhysicalDeviceFeatures;
extern PFN_vkGetPhysicalDeviceMemoryProperties vkGetPhysicalDeviceMemoryProperties;
extern PFN_vkGetPhysicalDeviceQueueFamilyProperties vkGetPhysicalDeviceQueueFamilyProperties;
extern PFN_vkEnumerateDeviceExtensionProperties vkEnumerateDeviceExtensionProperties;
extern PFN_vkCreateDevice vkCreateDevice;
extern PFN_vkDestroyDevice vkDestroyDevice;
extern PFN_vkGetDeviceProcAddr vkGetDeviceProcAddr;
extern PFN_vkGetDeviceQueue vkGetDeviceQueue;
extern PFN_vkDeviceWaitIdle vkDeviceWaitIdle;

#endif // WIN32
