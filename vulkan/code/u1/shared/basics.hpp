#pragma once

#include <vulkan/vk_enum_string_helper.h>
#include <vulkan/vulkan.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace u1 {

// snippet:begin check
inline VkResult check(VkResult result, const char* call) {
    if (result < 0) {
        throw std::runtime_error(std::string(call) + " failed: " + string_VkResult(result));
    }
    return result;
}
// snippet:end check

#define U1_CHECK(call) ::u1::check((call), #call)

inline std::atomic<int> validationErrors{0};

// snippet:begin messenger
inline VKAPI_ATTR VkBool32 VKAPI_CALL onValidationMessage(
    VkDebugUtilsMessageSeverityFlagBitsEXT severity, VkDebugUtilsMessageTypeFlagsEXT,
    const VkDebugUtilsMessengerCallbackDataEXT* data, void*) {
    const bool error = (severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) != 0;
    if (error) ++validationErrors;
    std::fprintf(stderr, "[validation %s] %s\n", error ? "error" : "warning", data->pMessage);
    return VK_FALSE;
}

inline VkDebugUtilsMessengerCreateInfoEXT messengerInfo() {
    return {
        .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                           VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                       VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                       VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = onValidationMessage,
    };
}
// snippet:end messenger

inline bool validationRequested() {
    const char* value = std::getenv("VKF_VALIDATION");
    return value == nullptr || std::strcmp(value, "0") != 0;
}

struct Instance {
    VkInstance instance = VK_NULL_HANDLE;
    VkDebugUtilsMessengerEXT messenger = VK_NULL_HANDLE;
    bool validation = false;
    bool portability = false;
};

// snippet:begin create-instance
inline Instance createInstance(const char* appName) {
    Instance result;

    // snippet:begin instance-layers
    uint32_t count = 0;
    U1_CHECK(vkEnumerateInstanceLayerProperties(&count, nullptr));
    std::vector<VkLayerProperties> layers(count);
    U1_CHECK(vkEnumerateInstanceLayerProperties(&count, layers.data()));
    const char* validationLayer = "VK_LAYER_KHRONOS_validation";
    for (const VkLayerProperties& layer : layers) {
        if (std::strcmp(layer.layerName, validationLayer) == 0) {
            result.validation = validationRequested();
        }
    }
    // snippet:end instance-layers

    // snippet:begin instance-extensions
    U1_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr));
    std::vector<VkExtensionProperties> available(count);
    U1_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &count, available.data()));
    auto has = [&](const char* name) {
        for (const VkExtensionProperties& e : available) {
            if (std::strcmp(e.extensionName, name) == 0) return true;
        }
        return false;
    };

    std::vector<const char*> extensions;
    if (has(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
        extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        result.portability = true;
    }
    const bool settings = result.validation && has(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
    if (result.validation) extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    if (settings) extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
    // snippet:end instance-extensions

    // snippet:begin instance-app
    const VkApplicationInfo app{
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = appName,
        .applicationVersion = 1,
        .apiVersion = VK_API_VERSION_1_3,
    };

    VkDebugUtilsMessengerCreateInfoEXT chained = messengerInfo();
    // snippet:begin layer-settings
    const VkBool32 on = VK_TRUE;
    const VkLayerSettingEXT syncSettings[] = {
        {validationLayer, "validate_sync", VK_LAYER_SETTING_TYPE_BOOL32_EXT, 1, &on},
        {validationLayer, "syncval_shader_accesses_heuristic",
         VK_LAYER_SETTING_TYPE_BOOL32_EXT, 1, &on},
    };
    const VkLayerSettingsCreateInfoEXT layerSettings{
        .sType = VK_STRUCTURE_TYPE_LAYER_SETTINGS_CREATE_INFO_EXT,
        .pNext = &chained,
        .settingCount = 2,
        .pSettings = syncSettings,
    };
    // snippet:end layer-settings
    // snippet:end instance-app

    // snippet:begin instance-info
    const void* next = nullptr;
    if (result.validation) {
        next = settings ? static_cast<const void*>(&layerSettings) : &chained;
    }
    const VkInstanceCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = next,
        .flags = result.portability
                     ? VkInstanceCreateFlags(VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR)
                     : 0u,
        .pApplicationInfo = &app,
        .enabledLayerCount = result.validation ? 1u : 0u,
        .ppEnabledLayerNames = &validationLayer,
        .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
        .ppEnabledExtensionNames = extensions.data(),
    };
    U1_CHECK(vkCreateInstance(&info, nullptr, &result.instance));
    // snippet:end instance-info

    // snippet:begin instance-messenger
    if (result.validation) {
        auto create = reinterpret_cast<PFN_vkCreateDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(result.instance, "vkCreateDebugUtilsMessengerEXT"));
        const VkDebugUtilsMessengerCreateInfoEXT standalone = messengerInfo();
        U1_CHECK(create(result.instance, &standalone, nullptr, &result.messenger));
    }
    // snippet:end instance-messenger
    return result;
}
// snippet:end create-instance

inline void destroyInstance(Instance& instance) {
    if (instance.messenger != VK_NULL_HANDLE) {
        auto destroy = reinterpret_cast<PFN_vkDestroyDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(instance.instance, "vkDestroyDebugUtilsMessengerEXT"));
        destroy(instance.instance, instance.messenger, nullptr);
    }
    vkDestroyInstance(instance.instance, nullptr);
    instance = {};
}

// snippet:begin pick-device
inline VkPhysicalDevice pickPhysicalDevice(VkInstance instance) {
    uint32_t count = 0;
    U1_CHECK(vkEnumeratePhysicalDevices(instance, &count, nullptr));
    std::vector<VkPhysicalDevice> devices(count);
    U1_CHECK(vkEnumeratePhysicalDevices(instance, &count, devices.data()));

    VkPhysicalDevice best = VK_NULL_HANDLE;
    int bestScore = -1;
    for (VkPhysicalDevice device : devices) {
        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(device, &properties);
        if (properties.apiVersion < VK_API_VERSION_1_3) continue;
        int score = 0;
        if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            score = 3;
        } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            score = 2;
        }
        if (score > bestScore) {
            best = device;
            bestScore = score;
        }
    }
    if (best == VK_NULL_HANDLE) throw std::runtime_error("no device supports Vulkan 1.3");
    return best;
}
// snippet:end pick-device

// snippet:begin queue-family
inline uint32_t findQueueFamily(VkPhysicalDevice device, VkQueueFlags required) {
    uint32_t count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &count, nullptr);
    std::vector<VkQueueFamilyProperties> families(count);
    vkGetPhysicalDeviceQueueFamilyProperties(device, &count, families.data());
    for (uint32_t i = 0; i < count; ++i) {
        if ((families[i].queueFlags & required) == required) return i;
    }
    throw std::runtime_error("no queue family has the required capabilities");
}
// snippet:end queue-family

struct Device {
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    uint32_t queueFamily = 0;
    VkQueue queue = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties properties{};
    VkPhysicalDeviceMemoryProperties memory{};
};

// snippet:begin create-device
inline Device createDevice(VkPhysicalDevice physical) {
    Device result;
    result.physical = physical;
    vkGetPhysicalDeviceProperties(physical, &result.properties);
    vkGetPhysicalDeviceMemoryProperties(physical, &result.memory);
    result.queueFamily =
        findQueueFamily(physical, VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT);

    // snippet:begin device-queue
    const float priority = 1.0f;
    const VkDeviceQueueCreateInfo queueInfo{
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = result.queueFamily,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    // snippet:end device-queue

    // snippet:begin device-features
    VkPhysicalDeviceVulkan13Features v13{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .synchronization2 = VK_TRUE,
        .maintenance4 = VK_TRUE,
    };
    VkPhysicalDeviceVulkan12Features v12{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .pNext = &v13,
        .timelineSemaphore = VK_TRUE,
    };
    const VkPhysicalDeviceFeatures2 features{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &v12};
    // snippet:end device-features

    uint32_t count = 0;
    // snippet:begin device-create
    U1_CHECK(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, nullptr));
    std::vector<VkExtensionProperties> available(count);
    U1_CHECK(
        vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, available.data()));
    std::vector<const char*> extensions;
    for (const VkExtensionProperties& e : available) {
        if (std::strcmp(e.extensionName, "VK_KHR_portability_subset") == 0) {
            extensions.push_back("VK_KHR_portability_subset");
        }
    }

    const VkDeviceCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &features,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queueInfo,
        .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
        .ppEnabledExtensionNames = extensions.data(),
    };
    U1_CHECK(vkCreateDevice(physical, &info, nullptr, &result.device));
    vkGetDeviceQueue(result.device, result.queueFamily, 0, &result.queue);
    // snippet:end device-create
    return result;
}
// snippet:end create-device

// snippet:begin find-memory-type
inline uint32_t findMemoryType(const VkPhysicalDeviceMemoryProperties& memory,
                               uint32_t allowedTypes, VkMemoryPropertyFlags required) {
    for (uint32_t i = 0; i < memory.memoryTypeCount; ++i) {
        const bool allowed = (allowedTypes & (1u << i)) != 0;
        const bool suitable = (memory.memoryTypes[i].propertyFlags & required) == required;
        if (allowed && suitable) return i;
    }
    throw std::runtime_error("no memory type has the required properties");
}
// snippet:end find-memory-type

struct Buffer {
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkDeviceSize size = 0;
    uint32_t memoryType = 0;
    void* mapped = nullptr;
};

// snippet:begin create-buffer
inline Buffer createBuffer(const Device& device, VkDeviceSize size, VkBufferUsageFlags usage,
                           VkMemoryPropertyFlags properties) {
    Buffer result;
    result.size = size;
    const VkBufferCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };
    U1_CHECK(vkCreateBuffer(device.device, &info, nullptr, &result.buffer));

    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(device.device, result.buffer, &requirements);
    result.memoryType = findMemoryType(device.memory, requirements.memoryTypeBits, properties);
    const VkMemoryAllocateInfo allocation{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = result.memoryType,
    };
    U1_CHECK(vkAllocateMemory(device.device, &allocation, nullptr, &result.memory));
    U1_CHECK(vkBindBufferMemory(device.device, result.buffer, result.memory, 0));

    if (properties & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) {
        U1_CHECK(
            vkMapMemory(device.device, result.memory, 0, VK_WHOLE_SIZE, 0, &result.mapped));
    }
    return result;
}
// snippet:end create-buffer

inline void destroyBuffer(const Device& device, Buffer& buffer) {
    vkDestroyBuffer(device.device, buffer.buffer, nullptr);
    vkFreeMemory(device.device, buffer.memory, nullptr);
    buffer = {};
}

// snippet:begin submit-and-wait
inline void submitAndWait(const Device& device, VkCommandBuffer cmd) {
    const VkFenceCreateInfo fenceInfo{.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkFence fence = VK_NULL_HANDLE;
    U1_CHECK(vkCreateFence(device.device, &fenceInfo, nullptr, &fence));

    const VkCommandBufferSubmitInfo cmdInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };
    const VkSubmitInfo2 submit{
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmdInfo,
    };
    U1_CHECK(vkQueueSubmit2(device.queue, 1, &submit, fence));
    U1_CHECK(vkWaitForFences(device.device, 1, &fence, VK_TRUE, UINT64_MAX));
    vkDestroyFence(device.device, fence, nullptr);
}
// snippet:end submit-and-wait

// snippet:begin read-spirv
inline std::vector<uint32_t> readSpirv(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) throw std::runtime_error("cannot open " + path);
    const auto bytes = static_cast<size_t>(file.tellg());
    if (bytes == 0 || bytes % 4 != 0) throw std::runtime_error(path + " is not SPIR-V");
    std::vector<uint32_t> words(bytes / 4);
    file.seekg(0);
    file.read(reinterpret_cast<char*>(words.data()), static_cast<std::streamsize>(bytes));
    return words;
}

inline VkShaderModule createShaderModule(VkDevice device, const std::vector<uint32_t>& code) {
    const VkShaderModuleCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.size() * sizeof(uint32_t),
        .pCode = code.data(),
    };
    VkShaderModule module = VK_NULL_HANDLE;
    U1_CHECK(vkCreateShaderModule(device, &info, nullptr, &module));
    return module;
}
// snippet:end read-spirv

inline int finish(bool passed) {
    const int errors = validationErrors.load();
    if (errors > 0) std::fprintf(stderr, "validation reported %d error(s)\n", errors);
    return passed && errors == 0 ? 0 : 1;
}

}  // namespace u1
