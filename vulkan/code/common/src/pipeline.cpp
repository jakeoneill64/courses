#include "vkf/pipeline.hpp"

#include <algorithm>
#include <vector>

#include "vkf/check.hpp"
#include "vkf/util.hpp"

namespace vkf {

std::vector<uint32_t> readSpirv(const std::string& path) {
    const std::vector<char> bytes = readFile(path);
    if (bytes.empty() || bytes.size() % 4 != 0) {
        throw Error(VK_ERROR_UNKNOWN, path + " is not a SPIR-V module");
    }
    std::vector<uint32_t> words(bytes.size() / 4);
    std::memcpy(words.data(), bytes.data(), bytes.size());
    if (words[0] != 0x07230203) {
        throw Error(VK_ERROR_UNKNOWN, path + " does not start with the SPIR-V magic number");
    }
    return words;
}

Unique<VkShaderModule> createShaderModule(const Context& ctx, std::span<const uint32_t> code,
                                          const char* name) {
    VkShaderModuleCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.size_bytes(),
        .pCode = code.data(),
    };
    VkShaderModule module = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateShaderModule(ctx.device(), &info, nullptr, &module));
    if (name != nullptr) ctx.name(module, name);
    return {ctx.device(), module};
}

Unique<VkShaderModule> loadShader(const Context& ctx, const std::string& path) {
    const std::vector<uint32_t> code = readSpirv(path);
    const std::string name = path.substr(path.find_last_of("/\\") + 1);
    return createShaderModule(ctx, code, name.c_str());
}

DescriptorSetLayoutBuilder& DescriptorSetLayoutBuilder::add(uint32_t binding,
                                                            VkDescriptorType type,
                                                            VkShaderStageFlags stages,
                                                            uint32_t count,
                                                            VkDescriptorBindingFlags flags) {
    bindings_.push_back({.binding = binding,
                         .descriptorType = type,
                         .descriptorCount = count,
                         .stageFlags = stages});
    flags_.push_back(flags);
    return *this;
}

Unique<VkDescriptorSetLayout> DescriptorSetLayoutBuilder::build(
    const Context& ctx, VkDescriptorSetLayoutCreateFlags flags) const {
    const bool anyFlags = std::any_of(flags_.begin(), flags_.end(),
                                      [](VkDescriptorBindingFlags f) { return f != 0; });
    VkDescriptorSetLayoutBindingFlagsCreateInfo bindingFlags{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .bindingCount = static_cast<uint32_t>(flags_.size()),
        .pBindingFlags = flags_.data(),
    };
    VkDescriptorSetLayoutCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = anyFlags ? &bindingFlags : nullptr,
        .flags = flags,
        .bindingCount = static_cast<uint32_t>(bindings_.size()),
        .pBindings = bindings_.data(),
    };
    VkDescriptorSetLayout layout = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateDescriptorSetLayout(ctx.device(), &info, nullptr, &layout));
    return {ctx.device(), layout};
}

Unique<VkPipelineLayout> createPipelineLayout(
    const Context& ctx, std::span<const VkDescriptorSetLayout> sets,
    std::span<const VkPushConstantRange> pushConstants) {
    VkPipelineLayoutCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = static_cast<uint32_t>(sets.size()),
        .pSetLayouts = sets.data(),
        .pushConstantRangeCount = static_cast<uint32_t>(pushConstants.size()),
        .pPushConstantRanges = pushConstants.data(),
    };
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VKF_CHECK(vkCreatePipelineLayout(ctx.device(), &info, nullptr, &layout));
    return {ctx.device(), layout};
}

Unique<VkPipelineLayout> createPipelineLayout(
    const Context& ctx, std::initializer_list<VkDescriptorSetLayout> sets,
    std::initializer_list<VkPushConstantRange> pushConstants) {
    return createPipelineLayout(ctx, std::span(sets.begin(), sets.size()),
                                std::span(pushConstants.begin(), pushConstants.size()));
}

Unique<VkPipeline> createComputePipeline(const Context& ctx, const ComputePipelineDesc& desc) {
    VkPipelineShaderStageRequiredSubgroupSizeCreateInfo subgroup{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_REQUIRED_SUBGROUP_SIZE_CREATE_INFO,
        .requiredSubgroupSize = desc.requiredSubgroupSize,
    };
    VkComputePipelineCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage =
            {
                .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .pNext = desc.requiredSubgroupSize != 0 ? &subgroup : nullptr,
                .flags = desc.stageFlags,
                .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                .module = desc.module,
                .pName = desc.entryPoint,
                .pSpecializationInfo = desc.specialization,
            },
        .layout = desc.layout,
    };
    VkPipeline pipeline = VK_NULL_HANDLE;
    VKF_CHECK(
        vkCreateComputePipelines(ctx.device(), desc.cache, 1, &info, nullptr, &pipeline));
    if (desc.name != nullptr) ctx.name(pipeline, desc.name);
    return {ctx.device(), pipeline};
}

const VkSpecializationInfo* Specialization::info() {
    info_ = {
        .mapEntryCount = static_cast<uint32_t>(entries_.size()),
        .pMapEntries = entries_.data(),
        .dataSize = data_.size(),
        .pData = data_.data(),
    };
    return &info_;
}

DescriptorPool::DescriptorPool(const Context& ctx, uint32_t maxSets,
                               uint32_t descriptorsPerType)
    : ctx_(&ctx) {
    const VkDescriptorType types[] = {
        VK_DESCRIPTOR_TYPE_SAMPLER,
        VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
        VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
        VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
    };
    std::vector<VkDescriptorPoolSize> sizes;
    for (VkDescriptorType type : types) sizes.push_back({type, descriptorsPerType});
    VkDescriptorPoolCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = maxSets,
        .poolSizeCount = static_cast<uint32_t>(sizes.size()),
        .pPoolSizes = sizes.data(),
    };
    VkDescriptorPool pool = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateDescriptorPool(ctx.device(), &info, nullptr, &pool));
    pool_ = Unique<VkDescriptorPool>(ctx.device(), pool);
}

VkDescriptorSet DescriptorPool::allocate(VkDescriptorSetLayout layout, const char* name) {
    VkDescriptorSetAllocateInfo info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool_,
        .descriptorSetCount = 1,
        .pSetLayouts = &layout,
    };
    VkDescriptorSet set = VK_NULL_HANDLE;
    VKF_CHECK(vkAllocateDescriptorSets(ctx_->device(), &info, &set));
    if (name != nullptr) ctx_->name(set, name);
    return set;
}

void DescriptorPool::reset() {
    VKF_CHECK(vkResetDescriptorPool(ctx_->device(), pool_, 0));
}

DescriptorWriter& DescriptorWriter::buffer(uint32_t binding, VkDescriptorType type,
                                           VkBuffer buffer, VkDeviceSize offset,
                                           VkDeviceSize range, uint32_t arrayElement) {
    buffers_.push_back({buffer, offset, range});
    pending_.push_back({binding, arrayElement, type, false, buffers_.size() - 1});
    return *this;
}

DescriptorWriter& DescriptorWriter::image(uint32_t binding, VkDescriptorType type,
                                          VkImageView view, VkImageLayout layout,
                                          VkSampler sampler, uint32_t arrayElement) {
    images_.push_back({sampler, view, layout});
    pending_.push_back({binding, arrayElement, type, true, images_.size() - 1});
    return *this;
}

void DescriptorWriter::update(const Context& ctx, VkDescriptorSet set) {
    std::vector<VkWriteDescriptorSet> writes;
    for (const Pending& p : pending_) {
        writes.push_back({
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = set,
            .dstBinding = p.binding,
            .dstArrayElement = p.arrayElement,
            .descriptorCount = 1,
            .descriptorType = p.type,
            .pImageInfo = p.isImage ? &images_[p.index] : nullptr,
            .pBufferInfo = p.isImage ? nullptr : &buffers_[p.index],
        });
    }
    vkUpdateDescriptorSets(ctx.device(), static_cast<uint32_t>(writes.size()), writes.data(),
                           0, nullptr);
}

}  // namespace vkf
