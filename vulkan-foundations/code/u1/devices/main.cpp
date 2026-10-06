#include <cstdio>
#include <vector>

#include "basics.hpp"

namespace {

const char* typeName(VkPhysicalDeviceType type) {
    switch (type) {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU: return "discrete GPU";
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: return "integrated GPU";
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU: return "virtual GPU";
        case VK_PHYSICAL_DEVICE_TYPE_CPU: return "CPU";
        default: return "other";
    }
}

void printVersion(const char* label, uint32_t version) {
    std::printf("%s %u.%u.%u\n", label, VK_API_VERSION_MAJOR(version),
                VK_API_VERSION_MINOR(version), VK_API_VERSION_PATCH(version));
}

// snippet:begin queue-flags
void printQueueFamilies(VkPhysicalDevice device) {
    uint32_t count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &count, nullptr);
    std::vector<VkQueueFamilyProperties> families(count);
    vkGetPhysicalDeviceQueueFamilyProperties(device, &count, families.data());
    for (uint32_t i = 0; i < count; ++i) {
        const VkQueueFlags f = families[i].queueFlags;
        std::printf("    family %u: %u queue(s)%s%s%s, %u timestamp bits\n", i,
                    families[i].queueCount, (f & VK_QUEUE_GRAPHICS_BIT) ? " graphics" : "",
                    (f & VK_QUEUE_COMPUTE_BIT) ? " compute" : "",
                    (f & VK_QUEUE_TRANSFER_BIT) ? " transfer" : "",
                    families[i].timestampValidBits);
    }
}
// snippet:end queue-flags

// snippet:begin feature-chain
void printFeatures(VkPhysicalDevice device) {
    VkPhysicalDeviceVulkan13Features v13{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    VkPhysicalDeviceVulkan12Features v12{
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &v13};
    VkPhysicalDeviceFeatures2 features{.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                                       .pNext = &v12};
    vkGetPhysicalDeviceFeatures2(device, &features);

    std::printf(
        "    synchronization2 %s, dynamicRendering %s, timelineSemaphore %s, "
        "bufferDeviceAddress %s\n",
        v13.synchronization2 ? "yes" : "no", v13.dynamicRendering ? "yes" : "no",
        v12.timelineSemaphore ? "yes" : "no", v12.bufferDeviceAddress ? "yes" : "no");
    std::printf("    shaderFloat64 %s, shaderInt64 %s, pipelineStatisticsQuery %s\n",
                features.features.shaderFloat64 ? "yes" : "no",
                features.features.shaderInt64 ? "yes" : "no",
                features.features.pipelineStatisticsQuery ? "yes" : "no");
}
// snippet:end feature-chain

void printDevice(VkPhysicalDevice device, uint32_t index) {
    VkPhysicalDeviceProperties p;
    vkGetPhysicalDeviceProperties(device, &p);
    std::printf("device %u: %s (%s)\n", index, p.deviceName, typeName(p.deviceType));
    printVersion("    Vulkan", p.apiVersion);
    const VkPhysicalDeviceLimits& l = p.limits;
    std::printf(
        "    maxComputeWorkGroupSize %u x %u x %u, maxComputeWorkGroupInvocations %u\n",
        l.maxComputeWorkGroupSize[0], l.maxComputeWorkGroupSize[1],
        l.maxComputeWorkGroupSize[2], l.maxComputeWorkGroupInvocations);
    std::printf("    maxComputeSharedMemorySize %u bytes, maxPushConstantsSize %u bytes\n",
                l.maxComputeSharedMemorySize, l.maxPushConstantsSize);
    std::printf("    maxStorageBufferRange %u bytes, maxMemoryAllocationCount %u\n",
                l.maxStorageBufferRange, l.maxMemoryAllocationCount);
    std::printf("    timestampPeriod %.2f ns\n", static_cast<double>(l.timestampPeriod));
    printFeatures(device);
    printQueueFamilies(device);
}

}  // namespace

int main() try {
    uint32_t loaderVersion = 0;
    U1_CHECK(vkEnumerateInstanceVersion(&loaderVersion));
    printVersion("loader supports Vulkan", loaderVersion);

    u1::Instance instance = u1::createInstance("u1_devices");
    std::printf("validation %s, portability enumeration %s\n",
                instance.validation ? "on" : "off",
                instance.portability ? "enabled" : "not needed");

    // snippet:begin enumerate
    uint32_t count = 0;
    U1_CHECK(vkEnumeratePhysicalDevices(instance.instance, &count, nullptr));
    std::vector<VkPhysicalDevice> devices(count);
    U1_CHECK(vkEnumeratePhysicalDevices(instance.instance, &count, devices.data()));
    for (uint32_t i = 0; i < count; ++i) printDevice(devices[i], i);
    // snippet:end enumerate

    VkPhysicalDevice physical = u1::pickPhysicalDevice(instance.instance);
    u1::Device device = u1::createDevice(physical);
    std::printf("created a device on %s with queue family %u\n", device.properties.deviceName,
                device.queueFamily);

    vkDestroyDevice(device.device, nullptr);
    u1::destroyInstance(instance);
    return u1::finish(true);
} catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
}
