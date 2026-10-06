#pragma once

#include <vulkan/vulkan.h>

#include <cstdint>
#include <cstring>
#include <deque>
#include <initializer_list>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "vkf/context.hpp"
#include "vkf/handles.hpp"

namespace vkf {

std::vector<uint32_t> readSpirv(const std::string& path);
Unique<VkShaderModule> createShaderModule(const Context& ctx, std::span<const uint32_t> code,
                                          const char* name = nullptr);
Unique<VkShaderModule> loadShader(const Context& ctx, const std::string& path);

#ifdef VKF_SHADER_DIR
// vkf_shaders in cmake/Course.cmake compiles each shader to <name>.spv in VKF_SHADER_DIR.
inline std::string shaderPath(std::string_view file) {
    return std::string(VKF_SHADER_DIR) + "/" + std::string(file) + ".spv";
}
#endif

class DescriptorSetLayoutBuilder {
public:
    DescriptorSetLayoutBuilder& add(uint32_t binding, VkDescriptorType type,
                                    VkShaderStageFlags stages, uint32_t count = 1,
                                    VkDescriptorBindingFlags flags = 0);
    Unique<VkDescriptorSetLayout> build(const Context& ctx,
                                        VkDescriptorSetLayoutCreateFlags flags = 0) const;

private:
    std::vector<VkDescriptorSetLayoutBinding> bindings_;
    std::vector<VkDescriptorBindingFlags> flags_;
};

Unique<VkPipelineLayout> createPipelineLayout(
    const Context& ctx, std::span<const VkDescriptorSetLayout> sets,
    std::span<const VkPushConstantRange> pushConstants = {});
Unique<VkPipelineLayout> createPipelineLayout(
    const Context& ctx, std::initializer_list<VkDescriptorSetLayout> sets,
    std::initializer_list<VkPushConstantRange> pushConstants = {});

struct ComputePipelineDesc {
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkShaderModule module = VK_NULL_HANDLE;
    const char* entryPoint = "main";
    const VkSpecializationInfo* specialization = nullptr;
    // Non-zero pins the subgroup size (VK_EXT_subgroup_size_control, core in Vulkan 1.3).
    uint32_t requiredSubgroupSize = 0;
    VkPipelineShaderStageCreateFlags stageFlags = 0;
    VkPipelineCache cache = VK_NULL_HANDLE;
    const char* name = nullptr;
};

Unique<VkPipeline> createComputePipeline(const Context& ctx, const ComputePipelineDesc& desc);

// Values must be trivially copyable; each is stored under its constant_id.
class Specialization {
public:
    template <class T>
    Specialization& set(uint32_t constantId, const T& value) {
        const auto offset = static_cast<uint32_t>(data_.size());
        data_.resize(data_.size() + sizeof(T));
        std::memcpy(data_.data() + offset, &value, sizeof(T));
        entries_.push_back({constantId, offset, sizeof(T)});
        return *this;
    }
    const VkSpecializationInfo* info();

private:
    std::vector<VkSpecializationMapEntry> entries_;
    std::vector<uint8_t> data_;
    VkSpecializationInfo info_{};
};

// Sized for every descriptor type the course uses; reset() frees every set at once.
class DescriptorPool {
public:
    explicit DescriptorPool(const Context& ctx, uint32_t maxSets = 64,
                            uint32_t descriptorsPerType = 256);
    VkDescriptorSet allocate(VkDescriptorSetLayout layout, const char* name = nullptr);
    void reset();
    VkDescriptorPool get() const { return pool_; }

private:
    const Context* ctx_;
    Unique<VkDescriptorPool> pool_;
};

class DescriptorWriter {
public:
    DescriptorWriter& buffer(uint32_t binding, VkDescriptorType type, VkBuffer buffer,
                             VkDeviceSize offset = 0, VkDeviceSize range = VK_WHOLE_SIZE,
                             uint32_t arrayElement = 0);
    DescriptorWriter& image(uint32_t binding, VkDescriptorType type, VkImageView view,
                            VkImageLayout layout, VkSampler sampler = VK_NULL_HANDLE,
                            uint32_t arrayElement = 0);
    void update(const Context& ctx, VkDescriptorSet set);

private:
    struct Pending {
        uint32_t binding;
        uint32_t arrayElement;
        VkDescriptorType type;
        bool isImage;
        size_t index;
    };
    std::deque<VkDescriptorBufferInfo> buffers_;
    std::deque<VkDescriptorImageInfo> images_;
    std::vector<Pending> pending_;
};

}  // namespace vkf
