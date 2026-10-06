#pragma once

#include <vkf/vkf.hpp>

#include <vector>

#include "u2.hpp"

namespace u2 {

struct ReducePush {
    uint32_t count;
};

// snippet:begin passes
struct ReducePass {
    VkDescriptorSet set;
    uint32_t count;
    uint32_t groups;
};

inline std::vector<ReducePass> planReduction(uint32_t count, uint32_t perGroup,
                                             VkDescriptorSet inputToA, VkDescriptorSet aToB,
                                             VkDescriptorSet bToA) {
    const VkDescriptorSet evenOdd[] = {bToA, aToB};
    std::vector<ReducePass> passes;
    do {
        const VkDescriptorSet set = passes.empty() ? inputToA : evenOdd[passes.size() % 2];
        const uint32_t groups = vkf::groupCount(count, perGroup);
        passes.push_back({set, count, groups});
        count = groups;
    } while (count > 1);
    return passes;
}
// snippet:end passes

// snippet:begin record
inline void recordReduction(VkCommandBuffer cmd, VkPipeline pipeline, VkPipelineLayout layout,
                            const std::vector<ReducePass>& passes) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    for (size_t p = 0; p < passes.size(); ++p) {
        if (p > 0) computeBarrier(cmd);
        const ReducePush push{passes[p].count};
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1,
                                &passes[p].set, 0, nullptr);
        vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
        vkCmdDispatch(cmd, passes[p].groups, 1, 1);
    }
}
// snippet:end record

}  // namespace u2
