// The portability subset's feature structure is declared among the beta extensions.
#define VK_ENABLE_BETA_EXTENSIONS
#include "vkf/context.hpp"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "vkf/check.hpp"
#include "vkf/util.hpp"

namespace vkf {
namespace {

std::atomic<uint64_t> g_errors{0};
std::atomic<uint64_t> g_warnings{0};
std::mutex g_printMutex;
std::unordered_map<int32_t, int> g_printed;

constexpr int MaxRepeats = 3;

bool envFlag(const char* name, bool fallback) {
    const char* value = std::getenv(name);
    if (value == nullptr) return fallback;
    return !(std::strcmp(value, "0") == 0 || std::strcmp(value, "false") == 0 ||
             std::strcmp(value, "off") == 0);
}

VKAPI_ATTR VkBool32 VKAPI_CALL onMessage(VkDebugUtilsMessageSeverityFlagBitsEXT severity,
                                         VkDebugUtilsMessageTypeFlagsEXT,
                                         const VkDebugUtilsMessengerCallbackDataEXT* data,
                                         void*) {
    const bool error = (severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) != 0;
    (error ? g_errors : g_warnings).fetch_add(1);

    std::lock_guard lock(g_printMutex);
    int& count = g_printed[data->messageIdNumber];
    ++count;
    if (count <= MaxRepeats) {
        std::fprintf(stderr, "[vulkan %s] %s\n", error ? "error" : "warning", data->pMessage);
    } else if (count == MaxRepeats + 1) {
        std::fprintf(stderr, "[vulkan] further %s messages are counted but not printed\n",
                     data->pMessageIdName != nullptr ? data->pMessageIdName : "repeated");
    }
    return VK_FALSE;
}

VkDebugUtilsMessengerCreateInfoEXT messengerInfo() {
    return {
        .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                           VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                       VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                       VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = onMessage,
    };
}

bool contains(const std::vector<VkExtensionProperties>& available, const char* name) {
    return std::any_of(available.begin(), available.end(),
                       [&](const VkExtensionProperties& e) {
                           return std::strcmp(e.extensionName, name) == 0;
                       });
}

const char* deviceTypeName(VkPhysicalDeviceType type) {
    switch (type) {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU: return "discrete GPU";
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: return "integrated GPU";
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU: return "virtual GPU";
        case VK_PHYSICAL_DEVICE_TYPE_CPU: return "CPU";
        default: return "device";
    }
}

int typeScore(VkPhysicalDeviceType type) {
    switch (type) {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU: return 3;
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: return 2;
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU: return 1;
        default: return 0;
    }
}

struct Supported {
    VkPhysicalDeviceVulkan13Features v13{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    VkPhysicalDeviceVulkan12Features v12{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &v13};
    VkPhysicalDeviceVulkan11Features v11{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES, .pNext = &v12};
    VkPhysicalDeviceFeatures2 core{.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                                   .pNext = &v11};

    explicit Supported(VkPhysicalDevice device) {
        vkGetPhysicalDeviceFeatures2(device, &core);
    }
    Supported(const Supported&) = delete;
};

// Required features first; every other one listed is enabled when the device has it.
DeviceFeatures chooseFeatures(const Supported& s) {
    DeviceFeatures f;
    f.v13.synchronization2 = VK_TRUE;
    f.v12.timelineSemaphore = VK_TRUE;

#define VKF_OPTIONAL(group, field) f.group.field = s.group.field
    VKF_OPTIONAL(v13, dynamicRendering);
    VKF_OPTIONAL(v13, maintenance4);
    VKF_OPTIONAL(v13, subgroupSizeControl);
    VKF_OPTIONAL(v13, computeFullSubgroups);
    VKF_OPTIONAL(v13, shaderDemoteToHelperInvocation);
    VKF_OPTIONAL(v13, shaderIntegerDotProduct);

    VKF_OPTIONAL(v12, bufferDeviceAddress);
    VKF_OPTIONAL(v12, descriptorIndexing);
    VKF_OPTIONAL(v12, runtimeDescriptorArray);
    VKF_OPTIONAL(v12, shaderSampledImageArrayNonUniformIndexing);
    VKF_OPTIONAL(v12, shaderStorageBufferArrayNonUniformIndexing);
    VKF_OPTIONAL(v12, shaderStorageImageArrayNonUniformIndexing);
    VKF_OPTIONAL(v12, descriptorBindingPartiallyBound);
    VKF_OPTIONAL(v12, descriptorBindingVariableDescriptorCount);
    VKF_OPTIONAL(v12, descriptorBindingSampledImageUpdateAfterBind);
    VKF_OPTIONAL(v12, descriptorBindingStorageImageUpdateAfterBind);
    VKF_OPTIONAL(v12, descriptorBindingStorageBufferUpdateAfterBind);
    VKF_OPTIONAL(v12, descriptorBindingUpdateUnusedWhilePending);
    VKF_OPTIONAL(v12, scalarBlockLayout);
    VKF_OPTIONAL(v12, uniformBufferStandardLayout);
    VKF_OPTIONAL(v12, hostQueryReset);
    VKF_OPTIONAL(v12, vulkanMemoryModel);
    VKF_OPTIONAL(v12, vulkanMemoryModelDeviceScope);
    VKF_OPTIONAL(v12, shaderFloat16);
    VKF_OPTIONAL(v12, shaderInt8);
    VKF_OPTIONAL(v12, storageBuffer8BitAccess);
    VKF_OPTIONAL(v12, uniformAndStorageBuffer8BitAccess);
    VKF_OPTIONAL(v12, shaderBufferInt64Atomics);
    VKF_OPTIONAL(v12, shaderSharedInt64Atomics);
    VKF_OPTIONAL(v12, shaderSubgroupExtendedTypes);
    VKF_OPTIONAL(v12, drawIndirectCount);
    VKF_OPTIONAL(v12, samplerFilterMinmax);
    VKF_OPTIONAL(v12, separateDepthStencilLayouts);

    VKF_OPTIONAL(v11, storageBuffer16BitAccess);
    VKF_OPTIONAL(v11, uniformAndStorageBuffer16BitAccess);
    VKF_OPTIONAL(v11, shaderDrawParameters);

    f.core.samplerAnisotropy = s.core.features.samplerAnisotropy;
    f.core.shaderInt64 = s.core.features.shaderInt64;
    f.core.shaderInt16 = s.core.features.shaderInt16;
    f.core.shaderFloat64 = s.core.features.shaderFloat64;
    f.core.multiDrawIndirect = s.core.features.multiDrawIndirect;
    f.core.drawIndirectFirstInstance = s.core.features.drawIndirectFirstInstance;
    f.core.fillModeNonSolid = s.core.features.fillModeNonSolid;
    f.core.independentBlend = s.core.features.independentBlend;
    f.core.fragmentStoresAndAtomics = s.core.features.fragmentStoresAndAtomics;
    f.core.vertexPipelineStoresAndAtomics = s.core.features.vertexPipelineStoresAndAtomics;
    f.core.shaderStorageImageExtendedFormats =
        s.core.features.shaderStorageImageExtendedFormats;
    f.core.shaderStorageImageReadWithoutFormat =
        s.core.features.shaderStorageImageReadWithoutFormat;
    f.core.shaderStorageImageWriteWithoutFormat =
        s.core.features.shaderStorageImageWriteWithoutFormat;
    f.core.imageCubeArray = s.core.features.imageCubeArray;
    f.core.depthClamp = s.core.features.depthClamp;
    f.core.largePoints = s.core.features.largePoints;
    f.core.pipelineStatisticsQuery = s.core.features.pipelineStatisticsQuery;
    f.core.textureCompressionBC = s.core.features.textureCompressionBC;
#undef VKF_OPTIONAL
    return f;
}

}  // namespace

struct Context::State {
    VkInstance instance = VK_NULL_HANDLE;
    VkDebugUtilsMessengerEXT messenger = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
    DeviceProperties properties;
    DeviceFeatures features;
    std::vector<std::string> extensions;
    Queue main, compute, transfer;
    bool separateCompute = false;
    bool separateTransfer = false;

    PFN_vkCreateDebugUtilsMessengerEXT createMessenger = nullptr;
    PFN_vkDestroyDebugUtilsMessengerEXT destroyMessenger = nullptr;
    PFN_vkSetDebugUtilsObjectNameEXT setObjectName = nullptr;
    PFN_vkCmdBeginDebugUtilsLabelEXT beginLabel = nullptr;
    PFN_vkCmdEndDebugUtilsLabelEXT endLabel = nullptr;

    ~State() {
        if (device != VK_NULL_HANDLE) {
            vkDeviceWaitIdle(device);
            if (pool != VK_NULL_HANDLE) vkDestroyCommandPool(device, pool, nullptr);
            vkDestroyDevice(device, nullptr);
        }
        if (surface != VK_NULL_HANDLE) vkDestroySurfaceKHR(instance, surface, nullptr);
        if (messenger != VK_NULL_HANDLE && destroyMessenger != nullptr) {
            destroyMessenger(instance, messenger, nullptr);
        }
        if (instance != VK_NULL_HANDLE) vkDestroyInstance(instance, nullptr);
    }
};

Context::Context(const ContextOptions& options) : s_(std::make_unique<State>()) {
    const bool wantValidation = envFlag("VKF_VALIDATION", options.validation);
    const bool wantSync = envFlag("VKF_SYNC_VALIDATION", options.syncValidation);
    const bool quiet = envFlag("VKF_QUIET", options.quiet);

    uint32_t count = 0;
    VKF_CHECK(vkEnumerateInstanceLayerProperties(&count, nullptr));
    std::vector<VkLayerProperties> layers(count);
    VKF_CHECK(vkEnumerateInstanceLayerProperties(&count, layers.data()));
    const char* validationLayer = "VK_LAYER_KHRONOS_validation";
    const bool haveValidation =
        std::any_of(layers.begin(), layers.end(), [&](const VkLayerProperties& l) {
            return std::strcmp(l.layerName, validationLayer) == 0;
        });
    const bool validation = wantValidation && haveValidation;
    if (wantValidation && !haveValidation) {
        std::fprintf(stderr,
                     "vkf: VK_LAYER_KHRONOS_validation is not installed; continuing without "
                     "validation\n");
    }

    VKF_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr));
    std::vector<VkExtensionProperties> available(count);
    VKF_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &count, available.data()));

    std::vector<const char*> extensions;
    const bool debugUtils = contains(available, VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    if (debugUtils) extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    const bool portability =
        contains(available, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    if (portability) extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    const bool layerSettings =
        validation && contains(available, VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
    if (layerSettings) extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
    for (const char* name : options.instanceExtensions) {
        if (!contains(available, name)) {
            throw Error(VK_ERROR_EXTENSION_NOT_PRESENT,
                        std::string("instance extension ") + name + " is not available");
        }
        if (std::find_if(extensions.begin(), extensions.end(), [&](const char* e) {
                return std::strcmp(e, name) == 0;
            }) == extensions.end()) {
            extensions.push_back(name);
        }
    }

    VkApplicationInfo app{
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = options.appName.c_str(),
        .applicationVersion = 1,
        .pEngineName = "vkf",
        .engineVersion = 1,
        .apiVersion = VK_API_VERSION_1_3,
    };

    const VkBool32 on = VK_TRUE;
    // Without the heuristic, synchronisation validation ignores shaders' memory accesses.
    VkLayerSettingEXT settings[] = {
        {validationLayer, "validate_sync", VK_LAYER_SETTING_TYPE_BOOL32_EXT, 1, &on},
        {validationLayer, "syncval_shader_accesses_heuristic",
         VK_LAYER_SETTING_TYPE_BOOL32_EXT, 1, &on},
    };
    VkLayerSettingsCreateInfoEXT settingsInfo{
        .sType = VK_STRUCTURE_TYPE_LAYER_SETTINGS_CREATE_INFO_EXT,
        .settingCount = 2,
        .pSettings = settings,
    };
    VkDebugUtilsMessengerCreateInfoEXT messenger = messengerInfo();
    if (layerSettings && wantSync) messenger.pNext = &settingsInfo;

    VkInstanceCreateInfo instanceInfo{
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = debugUtils ? &messenger : nullptr,
        .flags = portability
                     ? VkInstanceCreateFlags(VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR)
                     : 0u,
        .pApplicationInfo = &app,
        .enabledLayerCount = validation ? 1u : 0u,
        .ppEnabledLayerNames = validation ? &validationLayer : nullptr,
        .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
        .ppEnabledExtensionNames = extensions.data(),
    };
    VKF_CHECK(vkCreateInstance(&instanceInfo, nullptr, &s_->instance));

    if (debugUtils) {
        auto proc = [&](const char* name) {
            return vkGetInstanceProcAddr(s_->instance, name);
        };
        s_->createMessenger = reinterpret_cast<PFN_vkCreateDebugUtilsMessengerEXT>(
            proc("vkCreateDebugUtilsMessengerEXT"));
        s_->destroyMessenger = reinterpret_cast<PFN_vkDestroyDebugUtilsMessengerEXT>(
            proc("vkDestroyDebugUtilsMessengerEXT"));
        s_->setObjectName = reinterpret_cast<PFN_vkSetDebugUtilsObjectNameEXT>(
            proc("vkSetDebugUtilsObjectNameEXT"));
        s_->beginLabel = reinterpret_cast<PFN_vkCmdBeginDebugUtilsLabelEXT>(
            proc("vkCmdBeginDebugUtilsLabelEXT"));
        s_->endLabel = reinterpret_cast<PFN_vkCmdEndDebugUtilsLabelEXT>(
            proc("vkCmdEndDebugUtilsLabelEXT"));
        VkDebugUtilsMessengerCreateInfoEXT info = messengerInfo();
        VKF_CHECK(s_->createMessenger(s_->instance, &info, nullptr, &s_->messenger));
    }

    if (options.createSurface) s_->surface = options.createSurface(s_->instance);

    VKF_CHECK(vkEnumeratePhysicalDevices(s_->instance, &count, nullptr));
    std::vector<VkPhysicalDevice> devices(count);
    VKF_CHECK(vkEnumeratePhysicalDevices(s_->instance, &count, devices.data()));
    if (devices.empty()) {
        throw Error(VK_ERROR_INITIALIZATION_FAILED, "no Vulkan devices were found");
    }

    auto mainFamilyOf = [&](VkPhysicalDevice device) -> std::optional<uint32_t> {
        uint32_t n = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &n, nullptr);
        std::vector<VkQueueFamilyProperties> families(n);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &n, families.data());
        for (uint32_t i = 0; i < n; ++i) {
            const VkQueueFlags want = VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT;
            if ((families[i].queueFlags & want) != want) continue;
            if (s_->surface != VK_NULL_HANDLE) {
                VkBool32 present = VK_FALSE;
                VKF_CHECK(
                    vkGetPhysicalDeviceSurfaceSupportKHR(device, i, s_->surface, &present));
                if (!present) continue;
            }
            return i;
        }
        return std::nullopt;
    };

    auto usable = [&](VkPhysicalDevice device) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(device, &props);
        if (props.apiVersion < VK_API_VERSION_1_3) return false;
        Supported supported(device);
        if (!supported.v13.synchronization2 || !supported.v12.timelineSemaphore) return false;
        return mainFamilyOf(device).has_value();
    };

    const char* forced = std::getenv("VKF_DEVICE");
    if (forced != nullptr) {
        const auto index = static_cast<size_t>(std::strtoul(forced, nullptr, 10));
        if (index >= devices.size() || !usable(devices[index])) {
            throw Error(VK_ERROR_INITIALIZATION_FAILED,
                        std::string("VKF_DEVICE=") + forced + " is not a usable device");
        }
        s_->physical = devices[index];
    } else {
        int best = -1;
        for (VkPhysicalDevice device : devices) {
            if (!usable(device)) continue;
            VkPhysicalDeviceProperties props;
            vkGetPhysicalDeviceProperties(device, &props);
            if (typeScore(props.deviceType) > best) {
                best = typeScore(props.deviceType);
                s_->physical = device;
            }
        }
    }
    if (s_->physical == VK_NULL_HANDLE) {
        throw Error(
            VK_ERROR_INCOMPATIBLE_DRIVER,
            "no device supports Vulkan 1.3 with synchronization2 and timeline semaphores");
    }

    DeviceProperties& p = s_->properties;
    p.v13.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_PROPERTIES;
    p.v12 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES,
             .pNext = &p.v13};
    p.v11 = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES,
             .pNext = &p.v12};
    VkPhysicalDeviceProperties2 props2{.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
                                       .pNext = &p.v11};
    vkGetPhysicalDeviceProperties2(s_->physical, &props2);
    p.core = props2.properties;
    p.v11.pNext = nullptr;
    p.v12.pNext = nullptr;
    vkGetPhysicalDeviceMemoryProperties(s_->physical, &p.memory);
    vkGetPhysicalDeviceQueueFamilyProperties(s_->physical, &count, nullptr);
    p.queueFamilies.resize(count);
    vkGetPhysicalDeviceQueueFamilyProperties(s_->physical, &count, p.queueFamilies.data());
    const auto& families = p.queueFamilies;

    const uint32_t mainFamily = *mainFamilyOf(s_->physical);
    std::vector<uint32_t> perFamily(families.size(), 0);
    perFamily[mainFamily] = 1;
    s_->main = {mainFamily, 0, VK_NULL_HANDLE, families[mainFamily].queueFlags};

    auto claim = [&](uint32_t family) -> std::optional<Queue> {
        if (perFamily[family] >= families[family].queueCount) return std::nullopt;
        return Queue{family, perFamily[family]++, VK_NULL_HANDLE, families[family].queueFlags};
    };
    auto pick = [&](auto&& accept) -> std::optional<Queue> {
        for (uint32_t i = 0; i < families.size(); ++i) {
            if (accept(families[i].queueFlags) && perFamily[i] == 0) return claim(i);
        }
        for (uint32_t i = 0; i < families.size(); ++i) {
            if (accept(families[i].queueFlags)) {
                if (auto q = claim(i)) return q;
            }
        }
        return std::nullopt;
    };

    s_->compute = s_->main;
    if (options.asyncCompute) {
        auto dedicated = pick([](VkQueueFlags f) {
            return (f & VK_QUEUE_COMPUTE_BIT) && !(f & VK_QUEUE_GRAPHICS_BIT);
        });
        auto any = dedicated
                       ? dedicated
                       : pick([](VkQueueFlags f) { return (f & VK_QUEUE_COMPUTE_BIT) != 0; });
        if (any) {
            s_->compute = *any;
            s_->separateCompute = true;
        }
    }
    s_->transfer = s_->main;
    if (options.transferQueue) {
        auto dedicated = pick([](VkQueueFlags f) {
            return (f & VK_QUEUE_TRANSFER_BIT) &&
                   !(f & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT));
        });
        auto any = dedicated ? dedicated : pick([](VkQueueFlags f) {
            return (f & (VK_QUEUE_TRANSFER_BIT | VK_QUEUE_GRAPHICS_BIT |
                         VK_QUEUE_COMPUTE_BIT)) != 0;
        });
        if (any) {
            s_->transfer = *any;
            s_->separateTransfer = true;
        }
    }

    std::vector<std::vector<float>> priorities(families.size());
    std::vector<VkDeviceQueueCreateInfo> queueInfos;
    for (uint32_t i = 0; i < families.size(); ++i) {
        if (perFamily[i] == 0) continue;
        priorities[i].assign(perFamily[i], 1.0f);
        queueInfos.push_back({
            .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = i,
            .queueCount = perFamily[i],
            .pQueuePriorities = priorities[i].data(),
        });
    }

    VKF_CHECK(vkEnumerateDeviceExtensionProperties(s_->physical, nullptr, &count, nullptr));
    std::vector<VkExtensionProperties> deviceAvailable(count);
    VKF_CHECK(vkEnumerateDeviceExtensionProperties(s_->physical, nullptr, &count,
                                                   deviceAvailable.data()));
    std::vector<const char*> deviceExtensions;
    auto addDeviceExtension = [&](const char* name) {
        if (std::find_if(deviceExtensions.begin(), deviceExtensions.end(), [&](const char* e) {
                return std::strcmp(e, name) == 0;
            }) == deviceExtensions.end()) {
            deviceExtensions.push_back(name);
        }
    };
    const bool portabilitySubset = contains(deviceAvailable, "VK_KHR_portability_subset");
    // The spec requires VK_KHR_portability_subset whenever the device offers it.
    if (portabilitySubset) addDeviceExtension("VK_KHR_portability_subset");
    if (s_->surface != VK_NULL_HANDLE) addDeviceExtension(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    if (contains(deviceAvailable, VK_EXT_MEMORY_BUDGET_EXTENSION_NAME)) {
        addDeviceExtension(VK_EXT_MEMORY_BUDGET_EXTENSION_NAME);
    }
    for (const char* name : options.deviceExtensions) {
        if (!contains(deviceAvailable, name)) {
            throw Error(VK_ERROR_EXTENSION_NOT_PRESENT,
                        std::string("device extension ") + name + " is not available");
        }
        addDeviceExtension(name);
    }

    Supported supported(s_->physical);
    s_->features = chooseFeatures(supported);
    DeviceFeatures& f = s_->features;
    f.v13.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
    f.v12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
    f.v11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
    VkPhysicalDeviceVulkan13Features v13 = f.v13;
    VkPhysicalDeviceVulkan12Features v12 = f.v12;
    VkPhysicalDeviceVulkan11Features v11 = f.v11;
    v12.pNext = &v13;
    v11.pNext = &v12;
    // Unless this structure is chained, every portability feature counts as disabled.
    VkPhysicalDevicePortabilitySubsetFeaturesKHR portabilityFeatures{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR};
    if (portabilitySubset) {
        VkPhysicalDeviceFeatures2 query{.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                                        .pNext = &portabilityFeatures};
        vkGetPhysicalDeviceFeatures2(s_->physical, &query);
        portabilityFeatures.pNext = nullptr;
        v13.pNext = &portabilityFeatures;
    }
    VkPhysicalDeviceFeatures2 core{.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                                   .pNext = &v11,
                                   .features = f.core};

    VkDeviceCreateInfo deviceInfo{
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &core,
        .queueCreateInfoCount = static_cast<uint32_t>(queueInfos.size()),
        .pQueueCreateInfos = queueInfos.data(),
        .enabledExtensionCount = static_cast<uint32_t>(deviceExtensions.size()),
        .ppEnabledExtensionNames = deviceExtensions.data(),
    };
    VKF_CHECK(vkCreateDevice(s_->physical, &deviceInfo, nullptr, &s_->device));
    for (const char* name : deviceExtensions) s_->extensions.emplace_back(name);

    vkGetDeviceQueue(s_->device, s_->main.family, s_->main.index, &s_->main.queue);
    vkGetDeviceQueue(s_->device, s_->compute.family, s_->compute.index, &s_->compute.queue);
    vkGetDeviceQueue(s_->device, s_->transfer.family, s_->transfer.index, &s_->transfer.queue);
    setName(VK_OBJECT_TYPE_QUEUE, reinterpret_cast<uint64_t>(s_->main.queue), "main queue");
    if (s_->separateCompute) {
        setName(VK_OBJECT_TYPE_QUEUE, reinterpret_cast<uint64_t>(s_->compute.queue),
                "async compute queue");
    }
    if (s_->separateTransfer) {
        setName(VK_OBJECT_TYPE_QUEUE, reinterpret_cast<uint64_t>(s_->transfer.queue),
                "transfer queue");
    }

    VkCommandPoolCreateInfo poolInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT |
                 VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = s_->main.family,
    };
    VKF_CHECK(vkCreateCommandPool(s_->device, &poolInfo, nullptr, &s_->pool));

    if (!quiet) {
        const uint32_t v = p.core.apiVersion;
        std::fprintf(stdout, "vkf: %s (%s), Vulkan %u.%u.%u, %s %s\n", p.core.deviceName,
                     deviceTypeName(p.core.deviceType), VK_API_VERSION_MAJOR(v),
                     VK_API_VERSION_MINOR(v), VK_API_VERSION_PATCH(v), p.v12.driverName,
                     p.v12.driverInfo);
        const bool sync = validation && layerSettings && wantSync;
        std::fprintf(stdout, "vkf: validation %s, synchronisation validation %s\n",
                     validation ? "on" : "off", sync ? "on" : "off");
    }
}

Context::~Context() = default;

VkInstance Context::instance() const {
    return s_->instance;
}
VkPhysicalDevice Context::physicalDevice() const {
    return s_->physical;
}
VkDevice Context::device() const {
    return s_->device;
}
VkSurfaceKHR Context::surface() const {
    return s_->surface;
}
const DeviceProperties& Context::properties() const {
    return s_->properties;
}
const DeviceFeatures& Context::features() const {
    return s_->features;
}
const Queue& Context::mainQueue() const {
    return s_->main;
}
const Queue& Context::computeQueue() const {
    return s_->compute;
}
const Queue& Context::transferQueue() const {
    return s_->transfer;
}
bool Context::hasSeparateComputeQueue() const {
    return s_->separateCompute;
}
bool Context::hasSeparateTransferQueue() const {
    return s_->separateTransfer;
}
VkCommandPool Context::commandPool() const {
    return s_->pool;
}

bool Context::extensionEnabled(const char* name) const {
    return std::find(s_->extensions.begin(), s_->extensions.end(), name) !=
           s_->extensions.end();
}

void Context::setName(VkObjectType type, uint64_t handle, const char* name) const {
    if (s_->setObjectName == nullptr || name == nullptr || handle == 0) return;
    VkDebugUtilsObjectNameInfoEXT info{
        .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        .objectType = type,
        .objectHandle = handle,
        .pObjectName = name,
    };
    s_->setObjectName(s_->device, &info);
}

void Context::beginLabel(VkCommandBuffer cmd, const char* label) const {
    if (s_->beginLabel == nullptr) return;
    VkDebugUtilsLabelEXT info{.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT,
                              .pLabelName = label};
    s_->beginLabel(cmd, &info);
}

void Context::endLabel(VkCommandBuffer cmd) const {
    if (s_->endLabel != nullptr) s_->endLabel(cmd);
}

void Context::waitIdle() const {
    VKF_CHECK(vkDeviceWaitIdle(s_->device));
}

uint64_t validationErrors() {
    return g_errors.load();
}
uint64_t validationWarnings() {
    return g_warnings.load();
}

int run(const std::function<void()>& body) {
    int status = 0;
    try {
        body();
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        status = 1;
    }
    if (g_errors.load() > 0) {
        std::fprintf(stderr, "vkf: the validation layers reported %llu error(s)\n",
                     static_cast<unsigned long long>(g_errors.load()));
        status = 1;
    }
    return status;
}

}  // namespace vkf
