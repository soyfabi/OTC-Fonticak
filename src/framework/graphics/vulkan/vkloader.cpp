
// The whole Vulkan renderer is Win32-only for now (window surface), and the vulkan-headers
// dependency is windows-only in vcpkg.json. Outside Windows this file compiles to nothing,
// which lets it stay unconditionally on the source list in CMakeLists.
#ifdef WIN32
#include "vkloader.h"

#include <framework/core/logger.h>

#ifdef WIN32
#include <windows.h>
#endif

// Function pointer definitions. The headers are built with VK_NO_PROTOTYPES, so these are the
// only symbols with these names in the program - the rest of the code can call vkCreateInstance(...) normally.
PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr = nullptr;
PFN_vkEnumerateInstanceExtensionProperties vkEnumerateInstanceExtensionProperties = nullptr;
PFN_vkEnumerateInstanceLayerProperties vkEnumerateInstanceLayerProperties = nullptr;
PFN_vkCreateInstance vkCreateInstance = nullptr;
PFN_vkDestroyInstance vkDestroyInstance = nullptr;
PFN_vkEnumeratePhysicalDevices vkEnumeratePhysicalDevices = nullptr;
PFN_vkGetPhysicalDeviceProperties vkGetPhysicalDeviceProperties = nullptr;
PFN_vkGetPhysicalDeviceFeatures vkGetPhysicalDeviceFeatures = nullptr;
PFN_vkGetPhysicalDeviceMemoryProperties vkGetPhysicalDeviceMemoryProperties = nullptr;
PFN_vkGetPhysicalDeviceQueueFamilyProperties vkGetPhysicalDeviceQueueFamilyProperties = nullptr;
PFN_vkEnumerateDeviceExtensionProperties vkEnumerateDeviceExtensionProperties = nullptr;
PFN_vkCreateDevice vkCreateDevice = nullptr;
PFN_vkDestroyDevice vkDestroyDevice = nullptr;
PFN_vkGetDeviceProcAddr vkGetDeviceProcAddr = nullptr;
PFN_vkGetDeviceQueue vkGetDeviceQueue = nullptr;
PFN_vkDeviceWaitIdle vkDeviceWaitIdle = nullptr;

VkLoader& VkLoader::instance()
{
    static VkLoader loader;
    return loader;
}

VkLoader::~VkLoader()
{
    unload();
}

void* VkLoader::getSymbol(const char* name) const
{
#ifdef WIN32
    if (!m_library)
        return nullptr;
    return reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(m_library), name));
#else
    (void)name;
    return nullptr;
#endif
}

bool VkLoader::load()
{
    if (m_available)
        return true;

#ifdef WIN32
    if (!m_library) {
        m_library = LoadLibraryA("vulkan-1.dll");
        if (!m_library) {
            m_error = "vulkan-1.dll not found (no driver with Vulkan support?)";
            return false;
        }
    }
#else
    m_error = "Vulkan loader implemented for Windows only";
    return false;
#endif

    vkGetInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(getSymbol("vkGetInstanceProcAddr"));
    if (!vkGetInstanceProcAddr) {
        m_error = "vulkan-1.dll does not export vkGetInstanceProcAddr";
        unload();
        return false;
    }

    // global functions are fetched with a VK_NULL_HANDLE instance
    const auto global = [](const char* name) {
        return vkGetInstanceProcAddr(VK_NULL_HANDLE, name);
    };

    vkEnumerateInstanceExtensionProperties = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(global("vkEnumerateInstanceExtensionProperties"));
    vkEnumerateInstanceLayerProperties = reinterpret_cast<PFN_vkEnumerateInstanceLayerProperties>(global("vkEnumerateInstanceLayerProperties"));
    vkCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(global("vkCreateInstance"));

    if (!vkCreateInstance || !vkEnumerateInstanceExtensionProperties) {
        m_error = "missing basic Vulkan global functions";
        unload();
        return false;
    }

    // vkEnumerateInstanceVersion only exists since Vulkan 1.1 - its absence means 1.0
    if (const auto enumerateVersion = reinterpret_cast<PFN_vkEnumerateInstanceVersion>(global("vkEnumerateInstanceVersion"))) {
        if (enumerateVersion(&m_instanceVersion) != VK_SUCCESS)
            m_instanceVersion = VK_API_VERSION_1_0;
    } else {
        m_instanceVersion = VK_API_VERSION_1_0;
    }

    uint32_t extCount = 0;
    if (vkEnumerateInstanceExtensionProperties(nullptr, &extCount, nullptr) == VK_SUCCESS && extCount > 0) {
        std::vector<VkExtensionProperties> props(extCount);
        if (vkEnumerateInstanceExtensionProperties(nullptr, &extCount, props.data()) == VK_SUCCESS) {
            m_instanceExtensions.reserve(extCount);
            for (const auto& p : props)
                m_instanceExtensions.emplace_back(p.extensionName);
        }
    }

    m_available = true;
    m_error.clear();
    return true;
}

bool VkLoader::loadInstanceFunctions(VkInstance instance)
{
    if (!m_available || instance == VK_NULL_HANDLE)
        return false;

    const auto fn = [instance](const char* name) {
        return vkGetInstanceProcAddr(instance, name);
    };

    vkDestroyInstance = reinterpret_cast<PFN_vkDestroyInstance>(fn("vkDestroyInstance"));
    vkEnumeratePhysicalDevices = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(fn("vkEnumeratePhysicalDevices"));
    vkGetPhysicalDeviceProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(fn("vkGetPhysicalDeviceProperties"));
    vkGetPhysicalDeviceFeatures = reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures>(fn("vkGetPhysicalDeviceFeatures"));
    vkGetPhysicalDeviceMemoryProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(fn("vkGetPhysicalDeviceMemoryProperties"));
    vkGetPhysicalDeviceQueueFamilyProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(fn("vkGetPhysicalDeviceQueueFamilyProperties"));
    vkEnumerateDeviceExtensionProperties = reinterpret_cast<PFN_vkEnumerateDeviceExtensionProperties>(fn("vkEnumerateDeviceExtensionProperties"));
    vkCreateDevice = reinterpret_cast<PFN_vkCreateDevice>(fn("vkCreateDevice"));
    vkGetDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(fn("vkGetDeviceProcAddr"));

    if (!vkEnumeratePhysicalDevices || !vkCreateDevice || !vkGetDeviceProcAddr) {
        m_error = "missing Vulkan instance-level functions";
        return false;
    }

    return true;
}

bool VkLoader::loadDeviceFunctions(VkDevice device)
{
    if (!m_available || device == VK_NULL_HANDLE || !vkGetDeviceProcAddr)
        return false;

    const auto fn = [device](const char* name) {
        return vkGetDeviceProcAddr(device, name);
    };

    vkDestroyDevice = reinterpret_cast<PFN_vkDestroyDevice>(fn("vkDestroyDevice"));
    vkGetDeviceQueue = reinterpret_cast<PFN_vkGetDeviceQueue>(fn("vkGetDeviceQueue"));
    vkDeviceWaitIdle = reinterpret_cast<PFN_vkDeviceWaitIdle>(fn("vkDeviceWaitIdle"));

    if (!vkGetDeviceQueue || !vkDeviceWaitIdle) {
        m_error = "missing Vulkan device-level functions";
        return false;
    }

    return true;
}

bool VkLoader::hasInstanceExtension(const std::string& name) const
{
    for (const auto& ext : m_instanceExtensions) {
        if (ext == name)
            return true;
    }
    return false;
}

uint32_t VkLoader::probeDevices()
{
    if (!load()) {
        g_logger.info("[vulkan] unavailable: {}", m_error);
        return 0;
    }

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "CrystalOTC";
    appInfo.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    VkInstance instance = VK_NULL_HANDLE;
    if (vkCreateInstance(&createInfo, nullptr, &instance) != VK_SUCCESS) {
        g_logger.info("[vulkan] failed to create the probe instance");
        return 0;
    }

    if (!loadInstanceFunctions(instance)) {
        g_logger.info("[vulkan] {}", m_error);
        if (vkDestroyInstance)
            vkDestroyInstance(instance, nullptr);
        return 0;
    }

    uint32_t count = 0;
    vkEnumeratePhysicalDevices(instance, &count, nullptr);

    if (count == 0) {
        g_logger.info("[vulkan] instance OK, but zero physical devices");
        vkDestroyInstance(instance, nullptr);
        return 0;
    }

    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(instance, &count, devices.data());

    for (uint32_t i = 0; i < count; ++i) {
        VkPhysicalDeviceProperties props{};
        vkGetPhysicalDeviceProperties(devices[i], &props);

        // the device type drives the selection: a discrete GPU takes precedence over an integrated one
        const char* type = "other";
        switch (props.deviceType) {
            case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU: type = "discrete"; break;
            case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: type = "integrated"; break;
            case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU: type = "virtual"; break;
            case VK_PHYSICAL_DEVICE_TYPE_CPU: type = "software"; break;
            default: break;
        }

        uint32_t queueCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queueCount, nullptr);

        g_logger.info("[vulkan]   [{}] {} ({}), API {}.{}.{}, queue families: {}",
                      i, props.deviceName, type,
                      VK_API_VERSION_MAJOR(props.apiVersion),
                      VK_API_VERSION_MINOR(props.apiVersion),
                      VK_API_VERSION_PATCH(props.apiVersion),
                      queueCount);
    }

    vkDestroyInstance(instance, nullptr);

    g_logger.info("[vulkan] foundation works - devices detected: {}", count);
    return count;
}

void VkLoader::unload()
{
#ifdef WIN32
    if (m_library) {
        FreeLibrary(static_cast<HMODULE>(m_library));
        m_library = nullptr;
    }
#endif

    vkGetInstanceProcAddr = nullptr;
    vkCreateInstance = nullptr;
    vkEnumerateInstanceExtensionProperties = nullptr;
    vkEnumerateInstanceLayerProperties = nullptr;

    m_instanceExtensions.clear();
    m_available = false;
    m_instanceVersion = 0;
}

#endif // WIN32
