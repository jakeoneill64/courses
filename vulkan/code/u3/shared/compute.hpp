#pragma once

#include <vkf/vkf.hpp>

#include <initializer_list>
#include <type_traits>

namespace u3 {

// A compute pipeline whose bindings 0, 1, ... have the given descriptor types.
struct Kernel {
    vkf::Unique<VkDescriptorSetLayout> setLayout;
    vkf::Unique<VkPipelineLayout> layout;
    vkf::Unique<VkPipeline> pipeline;
};

inline Kernel makeKernel(const vkf::Context& ctx, const char* shader,
                         std::initializer_list<VkDescriptorType> bindings,
                         uint32_t pushBytes = 0) {
    vkf::DescriptorSetLayoutBuilder builder;
    uint32_t binding = 0;
    for (VkDescriptorType type : bindings) {
        builder.add(binding++, type, VK_SHADER_STAGE_COMPUTE_BIT);
    }
    Kernel kernel;
    kernel.setLayout = builder.build(ctx);
    const VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, pushBytes};
    kernel.layout = pushBytes > 0
                        ? vkf::createPipelineLayout(ctx, {kernel.setLayout.get()}, {push})
                        : vkf::createPipelineLayout(ctx, {kernel.setLayout.get()});
    const auto module = vkf::loadShader(ctx, vkf::shaderPath(shader));
    kernel.pipeline = vkf::createComputePipeline(
        ctx, {.layout = kernel.layout, .module = module, .name = shader});
    return kernel;
}

// A set for a kernel whose bindings are all storage buffers, given in binding order.
inline VkDescriptorSet bufferSet(const vkf::Context& ctx, vkf::DescriptorPool& pool,
                                 const Kernel& kernel,
                                 std::initializer_list<VkBuffer> buffers) {
    const VkDescriptorSet set = pool.allocate(kernel.setLayout);
    vkf::DescriptorWriter writer;
    uint32_t binding = 0;
    for (VkBuffer buffer : buffers) {
        writer.buffer(binding++, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffer);
    }
    writer.update(ctx, set);
    return set;
}

inline void bind(VkCommandBuffer cmd, const Kernel& kernel, VkDescriptorSet set) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernel.pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernel.layout, 0, 1, &set, 0,
                            nullptr);
}

// Push constants are structs, so a push value can never be mistaken for a group count.
template <class Push>
    requires std::is_class_v<Push>
void bind(VkCommandBuffer cmd, const Kernel& kernel, VkDescriptorSet set, const Push& push) {
    bind(cmd, kernel, set);
    vkCmdPushConstants(cmd, kernel.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push),
                       &push);
}

inline void dispatch(VkCommandBuffer cmd, const Kernel& kernel, VkDescriptorSet set,
                     uint32_t groupsX, uint32_t groupsY = 1) {
    bind(cmd, kernel, set);
    vkCmdDispatch(cmd, groupsX, groupsY, 1);
}

template <class Push>
    requires std::is_class_v<Push>
void dispatch(VkCommandBuffer cmd, const Kernel& kernel, VkDescriptorSet set, const Push& push,
              uint32_t groupsX, uint32_t groupsY = 1) {
    bind(cmd, kernel, set, push);
    vkCmdDispatch(cmd, groupsX, groupsY, 1);
}

// The integer hash the shaders use (scramble.glsl), so results can be checked exactly.
constexpr uint32_t scramble(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

// x after `steps` steps of x = x * 1664525 + 1013904223, by repeatedly squaring the map.
constexpr uint32_t lcgJump(uint32_t x, uint64_t steps) {
    uint32_t mul = 1664525u, add = 1013904223u;
    uint32_t totalMul = 1u, totalAdd = 0u;
    for (; steps != 0; steps >>= 1) {
        if (steps & 1) {
            totalMul *= mul;
            totalAdd = totalAdd * mul + add;
        }
        add = add * mul + add;
        mul *= mul;
    }
    return x * totalMul + totalAdd;
}
static_assert(lcgJump(5, 2) == (5u * 1664525u + 1013904223u) * 1664525u + 1013904223u);

}  // namespace u3
