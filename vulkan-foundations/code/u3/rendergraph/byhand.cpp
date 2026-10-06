#include "pipeline.hpp"

#include <utility>

namespace demo {
namespace {

VkMemoryBarrier2 memory(VkPipelineStageFlags2 srcStages, VkAccessFlags2 srcAccess,
                        VkPipelineStageFlags2 dstStages, VkAccessFlags2 dstAccess) {
    return {
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = srcStages,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStages,
        .dstAccessMask = dstAccess,
    };
}

VkImageMemoryBarrier2 image(VkImage image, VkImageLayout oldLayout, VkImageLayout newLayout,
                            VkPipelineStageFlags2 srcStages, VkAccessFlags2 srcAccess,
                            VkPipelineStageFlags2 dstStages, VkAccessFlags2 dstAccess) {
    return {
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = srcStages,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStages,
        .dstAccessMask = dstAccess,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
    };
}

// Records the barriers that precede one pass in a single call, and keeps a copy of them.
struct Recorder {
    VkCommandBuffer cmd;
    std::vector<rg::Barriers> log;

    void before(std::vector<VkMemoryBarrier2> memory = {},
                std::vector<VkImageMemoryBarrier2> images = {}) {
        if (!memory.empty() || !images.empty()) {
            const VkDependencyInfo dependency{
                .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                .memoryBarrierCount = uint32_t(memory.size()),
                .pMemoryBarriers = memory.data(),
                .imageMemoryBarrierCount = uint32_t(images.size()),
                .pImageMemoryBarriers = images.data(),
            };
            vkCmdPipelineBarrier2(cmd, &dependency);
        }
        log.push_back({std::move(memory), std::move(images)});
    }
};

constexpr VkPipelineStageFlags2 Compute = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
constexpr VkAccessFlags2 Read = VK_ACCESS_2_SHADER_STORAGE_READ_BIT;
constexpr VkAccessFlags2 Write = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT;

}  // namespace

std::vector<rg::Barriers> recordByHand(VkCommandBuffer cmd, const Pipeline& p,
                                       const Targets& t) {
    Recorder r{cmd, {}};
    // snippet:begin by-hand
    r.before();
    p.clearStats(cmd);
    r.before({}, {image(t.field, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                        VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE, Compute, Write)});
    p.generate(cmd);
    r.before({memory(Compute, Write, Compute, Read)});
    p.blur(cmd);
    r.before();
    p.edges(cmd);
    r.before({memory(Compute, Write, Compute, Read),
              memory(VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT, Compute,
                     Read | Write)},
             {image(t.mask, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                    VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE, Compute, Write)});
    p.select(cmd);
    r.before({memory(Compute, Write, Compute, Read)});
    p.command(cmd);
    r.before({memory(Compute, Write, VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
                     VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT),
              memory(Compute, Write, Compute, Read | Write)});
    p.score(cmd);
    r.before(
        {memory(Compute, Write, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT)},
        {image(t.mask, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, Compute,
               Write, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT)});
    p.readback(cmd);
    r.before({memory(VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT)});
    // snippet:end by-hand
    return r.log;
}

}  // namespace demo
