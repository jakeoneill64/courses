#pragma once

#include <vulkan/vulkan.h>

#include <utility>

namespace vkf {

static_assert(sizeof(void*) == 8, "Vulkan handles are distinct types only on 64-bit targets");

inline void destroy(VkDevice d, VkBuffer h) {
    vkDestroyBuffer(d, h, nullptr);
}
inline void destroy(VkDevice d, VkBufferView h) {
    vkDestroyBufferView(d, h, nullptr);
}
inline void destroy(VkDevice d, VkImage h) {
    vkDestroyImage(d, h, nullptr);
}
inline void destroy(VkDevice d, VkImageView h) {
    vkDestroyImageView(d, h, nullptr);
}
inline void destroy(VkDevice d, VkSampler h) {
    vkDestroySampler(d, h, nullptr);
}
inline void destroy(VkDevice d, VkDeviceMemory h) {
    vkFreeMemory(d, h, nullptr);
}
inline void destroy(VkDevice d, VkShaderModule h) {
    vkDestroyShaderModule(d, h, nullptr);
}
inline void destroy(VkDevice d, VkPipeline h) {
    vkDestroyPipeline(d, h, nullptr);
}
inline void destroy(VkDevice d, VkPipelineLayout h) {
    vkDestroyPipelineLayout(d, h, nullptr);
}
inline void destroy(VkDevice d, VkPipelineCache h) {
    vkDestroyPipelineCache(d, h, nullptr);
}
inline void destroy(VkDevice d, VkDescriptorSetLayout h) {
    vkDestroyDescriptorSetLayout(d, h, nullptr);
}
inline void destroy(VkDevice d, VkDescriptorPool h) {
    vkDestroyDescriptorPool(d, h, nullptr);
}
inline void destroy(VkDevice d, VkCommandPool h) {
    vkDestroyCommandPool(d, h, nullptr);
}
inline void destroy(VkDevice d, VkFence h) {
    vkDestroyFence(d, h, nullptr);
}
inline void destroy(VkDevice d, VkSemaphore h) {
    vkDestroySemaphore(d, h, nullptr);
}
inline void destroy(VkDevice d, VkEvent h) {
    vkDestroyEvent(d, h, nullptr);
}
inline void destroy(VkDevice d, VkQueryPool h) {
    vkDestroyQueryPool(d, h, nullptr);
}
inline void destroy(VkDevice d, VkSwapchainKHR h) {
    vkDestroySwapchainKHR(d, h, nullptr);
}

// Owns one Vulkan object and destroys it with the device it came from.
// snippet:begin unique
template <class T>
class Unique {
public:
    Unique() = default;
    Unique(VkDevice device, T handle) : device_(device), handle_(handle) {}
    Unique(const Unique&) = delete;
    Unique& operator=(const Unique&) = delete;
    Unique(Unique&& other) noexcept
        : device_(other.device_), handle_(std::exchange(other.handle_, VK_NULL_HANDLE)) {}
    Unique& operator=(Unique&& other) noexcept {
        if (this != &other) {
            reset();
            device_ = other.device_;
            handle_ = std::exchange(other.handle_, VK_NULL_HANDLE);
        }
        return *this;
    }
    ~Unique() { reset(); }

    void reset() {
        if (handle_ != VK_NULL_HANDLE) {
            destroy(device_, handle_);
            handle_ = VK_NULL_HANDLE;
        }
    }
    T get() const { return handle_; }
    operator T() const { return handle_; }
    const T* ptr() const { return &handle_; }
    T release() { return std::exchange(handle_, VK_NULL_HANDLE); }
    explicit operator bool() const { return handle_ != VK_NULL_HANDLE; }

private:
    VkDevice device_ = VK_NULL_HANDLE;
    T handle_ = VK_NULL_HANDLE;
};
// snippet:end unique

}  // namespace vkf
