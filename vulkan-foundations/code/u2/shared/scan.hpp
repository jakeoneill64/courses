#pragma once

#include <vkf/vkf.hpp>

#include <stdexcept>
#include <utility>
#include <vector>

#include "u2.hpp"

namespace u2 {

struct ScanPush {
    uint32_t count;
};

// snippet:begin scan-kernels
struct ScanKernels {
    vkf::Unique<VkDescriptorSetLayout> setLayout;
    vkf::Unique<VkPipelineLayout> layout;
    vkf::Unique<VkPipeline> scanBlocks;
    vkf::Unique<VkPipeline> addOffsets;
    uint32_t blockSize = 0;
};
// snippet:end scan-kernels

#ifdef VKF_SHADER_DIR
inline ScanKernels loadScanKernels(const vkf::Context& ctx, const char* blockShader,
                                   uint32_t localSize, uint32_t itemsPerInvocation,
                                   VkPipelineShaderStageCreateFlags flags = 0) {
    ScanKernels kernels;
    kernels.setLayout = storageBufferLayout(ctx, 3);
    const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ScanPush)};
    kernels.layout = vkf::createPipelineLayout(ctx, {kernels.setLayout.get()}, {range});
    vkf::Specialization spec;
    spec.set(0, localSize).set(1, itemsPerInvocation);
    kernels.scanBlocks = loadPipeline(ctx, kernels.layout, blockShader, spec, flags);
    kernels.addOffsets = loadPipeline(ctx, kernels.layout, "scan_add.comp", spec);
    kernels.blockSize = localSize * itemsPerInvocation;
    return kernels;
}
#endif

class MultiLevelScan {
public:
    MultiLevelScan(const vkf::Context& ctx, const ScanKernels& kernels,
                   vkf::DescriptorPool& pool, VkBuffer input, VkBuffer output, uint32_t count);
    void record(VkCommandBuffer cmd) const;
    const vkf::Buffer& total() const { return levels_.back().sums; }
    size_t levels() const { return levels_.size(); }

private:
    // snippet:begin level
    struct Level {
        uint32_t count = 0;
        uint32_t blocks = 0;
        VkBuffer input = VK_NULL_HANDLE;
        VkBuffer output = VK_NULL_HANDLE;
        vkf::Buffer ownedOutput;
        vkf::Buffer sums;
        VkDescriptorSet scanSet = VK_NULL_HANDLE;
        VkDescriptorSet addSet = VK_NULL_HANDLE;
    };
    // snippet:end level
    const ScanKernels* kernels_;
    std::vector<Level> levels_;
};

// snippet:begin build-levels
inline MultiLevelScan::MultiLevelScan(const vkf::Context& ctx, const ScanKernels& kernels,
                                      vkf::DescriptorPool& pool, VkBuffer input,
                                      VkBuffer output, uint32_t count)
    : kernels_(&kernels) {
    const VkBufferUsageFlags usage =
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    levels_.push_back({.count = count, .input = input, .output = output});
    for (size_t i = 0;; ++i) {
        Level& level = levels_[i];
        level.blocks = vkf::groupCount(level.count, kernels.blockSize);
        level.sums = vkf::createBuffer(ctx, level.blocks * sizeof(uint32_t), usage,
                                       vkf::MemoryUse::DeviceLocal, "block sums");
        level.scanSet = pool.allocate(kernels.setLayout, "scan blocks");
        writeStorageBuffers(ctx, level.scanSet, {level.input, level.output, level.sums});
        if (level.blocks == 1) break;

        Level next{.count = level.blocks, .input = level.sums};
        next.ownedOutput = vkf::createBuffer(ctx, level.blocks * sizeof(uint32_t), usage,
                                             vkf::MemoryUse::DeviceLocal, "scanned sums");
        next.output = next.ownedOutput;
        level.addSet = pool.allocate(kernels.setLayout, "add offsets");
        writeStorageBuffers(ctx, level.addSet, {next.output, level.output});
        levels_.push_back(std::move(next));
    }
    if (levels_.front().blocks > ctx.properties().core.limits.maxComputeWorkGroupCount[0]) {
        throw std::runtime_error("the scan needs more workgroups than this device allows");
    }
}
// snippet:end build-levels

// snippet:begin record-levels
inline void MultiLevelScan::record(VkCommandBuffer cmd) const {
    auto dispatch = [&](const Level& level, VkDescriptorSet set) {
        const ScanPush push{level.count};
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernels_->layout, 0, 1,
                                &set, 0, nullptr);
        vkCmdPushConstants(cmd, kernels_->layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push),
                           &push);
        vkCmdDispatch(cmd, level.blocks, 1, 1);
        computeBarrier(cmd);
    };
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernels_->scanBlocks);
    for (const Level& level : levels_) dispatch(level, level.scanSet);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, kernels_->addOffsets);
    for (size_t i = levels_.size() - 1; i-- > 0;) dispatch(levels_[i], levels_[i].addSet);
}
// snippet:end record-levels

}  // namespace u2
