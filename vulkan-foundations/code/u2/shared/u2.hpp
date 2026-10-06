#pragma once

#include <vkf/vkf.hpp>

#include <algorithm>
#include <functional>
#include <initializer_list>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace u2 {

// snippet:begin compute-barrier
inline void computeBarrier(VkCommandBuffer cmd) {
    vkf::memoryBarrier(
        cmd, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
}
// snippet:end compute-barrier

inline vkf::Unique<VkDescriptorSetLayout> storageBufferLayout(const vkf::Context& ctx,
                                                              uint32_t bindings) {
    vkf::DescriptorSetLayoutBuilder builder;
    for (uint32_t b = 0; b < bindings; ++b) {
        builder.add(b, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT);
    }
    return builder.build(ctx);
}

inline void writeStorageBuffers(const vkf::Context& ctx, VkDescriptorSet set,
                                std::initializer_list<VkBuffer> buffers) {
    vkf::DescriptorWriter writer;
    uint32_t binding = 0;
    for (VkBuffer buffer : buffers) {
        writer.buffer(binding++, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffer);
    }
    writer.update(ctx, set);
}

#ifdef VKF_SHADER_DIR
inline vkf::Unique<VkPipeline> loadPipeline(const vkf::Context& ctx, VkPipelineLayout layout,
                                            const char* shader, vkf::Specialization spec = {},
                                            VkPipelineShaderStageCreateFlags flags = 0,
                                            VkPipelineCache cache = VK_NULL_HANDLE) {
    const auto module = vkf::loadShader(ctx, vkf::shaderPath(shader));
    return vkf::createComputePipeline(ctx, {.layout = layout,
                                            .module = module,
                                            .specialization = spec.info(),
                                            .stageFlags = flags,
                                            .cache = cache,
                                            .name = shader});
}
#endif

inline bool subgroupSupports(const vkf::Context& ctx, VkSubgroupFeatureFlags operations) {
    const VkPhysicalDeviceVulkan11Properties& p = ctx.properties().v11;
    return (p.subgroupSupportedStages & VK_SHADER_STAGE_COMPUTE_BIT) != 0 &&
           (p.subgroupSupportedOperations & operations) == operations;
}

// Ordering invocations by (gl_SubgroupID, gl_SubgroupInvocationID) needs full subgroups.
inline VkPipelineShaderStageCreateFlags fullSubgroups(const vkf::Context& ctx,
                                                      uint32_t localSizeX) {
    if (localSizeX % ctx.properties().v13.maxSubgroupSize != 0) {
        throw std::runtime_error("the local size must be a multiple of maxSubgroupSize");
    }
    if (!ctx.features().v13.computeFullSubgroups) return 0;
    return VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT;
}

// snippet:begin time-gpu
inline vkf::Stats timeGpu(const vkf::Context& ctx, int runs,
                          const std::function<void(VkCommandBuffer)>& body) {
    vkf::GpuTimer timer(ctx, 2 * static_cast<uint32_t>(runs) + 2);
    auto repeat = [&](VkCommandBuffer cmd, int count, bool stampEach) {
        for (int run = 0; run < count; ++run) {
            vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                               VK_ACCESS_2_MEMORY_WRITE_BIT,
                               VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                               VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT);
            if (stampEach) timer.stamp(cmd);
            body(cmd);
            if (stampEach) timer.stamp(cmd);
        }
    };
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        timer.reset(cmd);
        timer.stamp(cmd);
        repeat(cmd, 3, false);
        timer.stamp(cmd);
    });
    // GPUs raise their clocks after some milliseconds of load, so warm up for about 25 ms.
    const double perRun = std::max(timer.elapsedMs(0, 1) / 3, 1e-3);
    const int warmup = std::clamp(static_cast<int>(25.0 / perRun), 1, 1000);
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        timer.reset(cmd);
        repeat(cmd, warmup, false);
        repeat(cmd, runs, true);
    });
    std::vector<double> ms;
    for (uint32_t run = 0; run < static_cast<uint32_t>(runs); ++run) {
        ms.push_back(timer.elapsedMs(2 * run, 2 * run + 1));
    }
    return vkf::summarize(ms);
}
// snippet:end time-gpu

inline double gbPerSecond(double bytes, double ms) {
    return bytes / (ms * 1e6);
}

inline void finish(bool passed, std::string_view summary) {
    vkf::print("{} {}\n", passed ? "PASS" : "FAIL", summary);
    if (!passed) throw std::runtime_error("the results are wrong");
}

}  // namespace u2
