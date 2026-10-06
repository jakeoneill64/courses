#pragma once

#include <vulkan/vulkan.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace vkf {

struct Queue {
    uint32_t family = 0;
    uint32_t index = 0;
    VkQueue queue = VK_NULL_HANDLE;
    VkQueueFlags flags = 0;

    operator VkQueue() const { return queue; }
};

// snippet:begin options
struct ContextOptions {
    std::string appName = "Vulkan Foundations";
    // VKF_VALIDATION=0 and VKF_SYNC_VALIDATION=0 in the environment override these two.
    bool validation = true;
    bool syncValidation = true;
    // Ask for a second compute-capable queue, preferably in another family, for async compute.
    bool asyncCompute = false;
    // Ask for a queue in a transfer-only family when the device has one.
    bool transferQueue = false;
    std::vector<const char*> instanceExtensions;
    std::vector<const char*> deviceExtensions;
    // The main queue's family must be able to present to the returned surface.
    std::function<VkSurfaceKHR(VkInstance)> createSurface;
    bool quiet = false;
};
// snippet:end options

struct DeviceProperties {
    VkPhysicalDeviceProperties core{};
    VkPhysicalDeviceVulkan11Properties v11{};
    VkPhysicalDeviceVulkan12Properties v12{};
    VkPhysicalDeviceVulkan13Properties v13{};
    VkPhysicalDeviceMemoryProperties memory{};
    std::vector<VkQueueFamilyProperties> queueFamilies;
};

// Enabled features: the required ones plus each listed optional one the device supports.
struct DeviceFeatures {
    VkPhysicalDeviceFeatures core{};
    VkPhysicalDeviceVulkan11Features v11{};
    VkPhysicalDeviceVulkan12Features v12{};
    VkPhysicalDeviceVulkan13Features v13{};
};

class Context {
public:
    explicit Context(const ContextOptions& options = {});
    ~Context();
    Context(const Context&) = delete;
    Context& operator=(const Context&) = delete;

    VkInstance instance() const;
    VkPhysicalDevice physicalDevice() const;
    VkDevice device() const;
    VkSurfaceKHR surface() const;
    const DeviceProperties& properties() const;
    const DeviceFeatures& features() const;
    bool extensionEnabled(const char* name) const;

    // Graphics, compute and transfer, and presentation when a surface was given.
    const Queue& mainQueue() const;
    // With asyncCompute, a second queue when the device has one; otherwise the main queue.
    const Queue& computeQueue() const;
    // Another family's queue when transferQueue was set and one exists; else the main queue.
    const Queue& transferQueue() const;
    bool hasSeparateComputeQueue() const;
    bool hasSeparateTransferQueue() const;

    // A pool on the main queue's family whose command buffers can be reset; used by submitNow.
    VkCommandPool commandPool() const;

    // No-ops when VK_EXT_debug_utils is unavailable.
    void setName(VkObjectType type, uint64_t handle, const char* name) const;
    template <class T>
    void name(T handle, const char* label) const;
    void beginLabel(VkCommandBuffer cmd, const char* label) const;
    void endLabel(VkCommandBuffer cmd) const;

    void waitIdle() const;

private:
    struct State;
    std::unique_ptr<State> s_;
};

template <class T>
struct ObjectType;
template <>
struct ObjectType<VkBuffer> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_BUFFER;
};
template <>
struct ObjectType<VkImage> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_IMAGE;
};
template <>
struct ObjectType<VkImageView> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_IMAGE_VIEW;
};
template <>
struct ObjectType<VkDeviceMemory> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_DEVICE_MEMORY;
};
template <>
struct ObjectType<VkPipeline> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_PIPELINE;
};
template <>
struct ObjectType<VkPipelineLayout> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_PIPELINE_LAYOUT;
};
template <>
struct ObjectType<VkShaderModule> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_SHADER_MODULE;
};
template <>
struct ObjectType<VkDescriptorSet> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_DESCRIPTOR_SET;
};
template <>
struct ObjectType<VkDescriptorSetLayout> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT;
};
template <>
struct ObjectType<VkCommandBuffer> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_COMMAND_BUFFER;
};
template <>
struct ObjectType<VkQueue> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_QUEUE;
};
template <>
struct ObjectType<VkSemaphore> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_SEMAPHORE;
};
template <>
struct ObjectType<VkFence> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_FENCE;
};
template <>
struct ObjectType<VkEvent> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_EVENT;
};
template <>
struct ObjectType<VkQueryPool> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_QUERY_POOL;
};
template <>
struct ObjectType<VkSampler> {
    static constexpr VkObjectType value = VK_OBJECT_TYPE_SAMPLER;
};

template <class T>
void Context::name(T handle, const char* label) const {
    setName(ObjectType<T>::value, reinterpret_cast<uint64_t>(handle), label);
}

// Messages the validation layers have reported as errors and warnings in this process so far.
uint64_t validationErrors();
uint64_t validationWarnings();

// Returns 1 if body throws or the validation layers report an error, otherwise 0.
int run(const std::function<void()>& body);

}  // namespace vkf
