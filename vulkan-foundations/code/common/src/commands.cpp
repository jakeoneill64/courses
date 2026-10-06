#include "vkf/commands.hpp"

#include <vector>

#include "vkf/check.hpp"

namespace vkf {

Unique<VkCommandPool> createCommandPool(const Context& ctx, uint32_t family,
                                        VkCommandPoolCreateFlags flags) {
    VkCommandPoolCreateInfo info{.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                 .flags = flags,
                                 .queueFamilyIndex = family};
    VkCommandPool pool = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateCommandPool(ctx.device(), &info, nullptr, &pool));
    return {ctx.device(), pool};
}

VkCommandBuffer allocateCommandBuffer(const Context& ctx, VkCommandPool pool) {
    VkCommandBufferAllocateInfo info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    VKF_CHECK(vkAllocateCommandBuffers(ctx.device(), &info, &cmd));
    return cmd;
}

void beginCommands(VkCommandBuffer cmd, VkCommandBufferUsageFlags usage) {
    VkCommandBufferBeginInfo info{.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                  .flags = usage};
    VKF_CHECK(vkBeginCommandBuffer(cmd, &info));
}

void endCommands(VkCommandBuffer cmd) {
    VKF_CHECK(vkEndCommandBuffer(cmd));
}

Unique<VkFence> createFence(const Context& ctx, bool signaled) {
    VkFenceCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = signaled ? VkFenceCreateFlags(VK_FENCE_CREATE_SIGNALED_BIT) : 0u,
    };
    VkFence fence = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateFence(ctx.device(), &info, nullptr, &fence));
    return {ctx.device(), fence};
}

Unique<VkSemaphore> createSemaphore(const Context& ctx) {
    VkSemaphoreCreateInfo info{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    VkSemaphore semaphore = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateSemaphore(ctx.device(), &info, nullptr, &semaphore));
    return {ctx.device(), semaphore};
}

Unique<VkSemaphore> createTimelineSemaphore(const Context& ctx, uint64_t initialValue) {
    VkSemaphoreTypeCreateInfo type{
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
        .semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = initialValue,
    };
    VkSemaphoreCreateInfo info{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                               .pNext = &type};
    VkSemaphore semaphore = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateSemaphore(ctx.device(), &info, nullptr, &semaphore));
    return {ctx.device(), semaphore};
}

void waitFence(const Context& ctx, VkFence fence, uint64_t timeoutNs) {
    if (VKF_CHECK(vkWaitForFences(ctx.device(), 1, &fence, VK_TRUE, timeoutNs)) ==
        VK_TIMEOUT) {
        throw Error(VK_TIMEOUT, "timed out waiting for a fence");
    }
}

void submit(VkQueue queue, std::span<const VkCommandBuffer> commandBuffers,
            std::span<const SemaphoreSubmit> waits, std::span<const SemaphoreSubmit> signals,
            VkFence fence) {
    std::vector<VkCommandBufferSubmitInfo> cmds;
    for (VkCommandBuffer cmd : commandBuffers) {
        cmds.push_back(
            {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = cmd});
    }
    auto convert = [](std::span<const SemaphoreSubmit> in) {
        std::vector<VkSemaphoreSubmitInfo> out;
        for (const SemaphoreSubmit& s : in) {
            out.push_back({
                .sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = s.semaphore,
                .value = s.value,
                .stageMask = s.stages,
            });
        }
        return out;
    };
    const auto waitInfos = convert(waits);
    const auto signalInfos = convert(signals);
    VkSubmitInfo2 info{
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .waitSemaphoreInfoCount = static_cast<uint32_t>(waitInfos.size()),
        .pWaitSemaphoreInfos = waitInfos.data(),
        .commandBufferInfoCount = static_cast<uint32_t>(cmds.size()),
        .pCommandBufferInfos = cmds.data(),
        .signalSemaphoreInfoCount = static_cast<uint32_t>(signalInfos.size()),
        .pSignalSemaphoreInfos = signalInfos.data(),
    };
    VKF_CHECK(vkQueueSubmit2(queue, 1, &info, fence));
}

void submitNow(const Context& ctx, const std::function<void(VkCommandBuffer)>& record) {
    VkCommandBuffer cmd = allocateCommandBuffer(ctx, ctx.commandPool());
    Unique<VkFence> fence = createFence(ctx);
    try {
        beginCommands(cmd);
        record(cmd);
        endCommands(cmd);
        submit(ctx.mainQueue().queue, std::span(&cmd, 1), {}, {}, fence);
        waitFence(ctx, fence);
    } catch (...) {
        vkFreeCommandBuffers(ctx.device(), ctx.commandPool(), 1, &cmd);
        throw;
    }
    vkFreeCommandBuffers(ctx.device(), ctx.commandPool(), 1, &cmd);
}

VkImageSubresourceRange colorRange(uint32_t baseMip, uint32_t mipCount, uint32_t baseLayer,
                                   uint32_t layerCount) {
    return {VK_IMAGE_ASPECT_COLOR_BIT, baseMip, mipCount, baseLayer, layerCount};
}

void memoryBarrier(VkCommandBuffer cmd, VkPipelineStageFlags2 srcStages,
                   VkAccessFlags2 srcAccess, VkPipelineStageFlags2 dstStages,
                   VkAccessFlags2 dstAccess) {
    VkMemoryBarrier2 barrier{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = srcStages,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStages,
        .dstAccessMask = dstAccess,
    };
    VkDependencyInfo dependency{.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
                                .memoryBarrierCount = 1,
                                .pMemoryBarriers = &barrier};
    vkCmdPipelineBarrier2(cmd, &dependency);
}

void bufferBarrier(VkCommandBuffer cmd, VkBuffer buffer, VkPipelineStageFlags2 srcStages,
                   VkAccessFlags2 srcAccess, VkPipelineStageFlags2 dstStages,
                   VkAccessFlags2 dstAccess, VkDeviceSize offset, VkDeviceSize size,
                   uint32_t srcFamily, uint32_t dstFamily) {
    VkBufferMemoryBarrier2 barrier{
        .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
        .srcStageMask = srcStages,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStages,
        .dstAccessMask = dstAccess,
        .srcQueueFamilyIndex = srcFamily,
        .dstQueueFamilyIndex = dstFamily,
        .buffer = buffer,
        .offset = offset,
        .size = size,
    };
    VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .bufferMemoryBarrierCount = 1,
        .pBufferMemoryBarriers = &barrier,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}

void imageBarrier(VkCommandBuffer cmd, VkImage image, VkImageLayout oldLayout,
                  VkImageLayout newLayout, VkPipelineStageFlags2 srcStages,
                  VkAccessFlags2 srcAccess, VkPipelineStageFlags2 dstStages,
                  VkAccessFlags2 dstAccess, VkImageSubresourceRange range, uint32_t srcFamily,
                  uint32_t dstFamily) {
    VkImageMemoryBarrier2 barrier{
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = srcStages,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStages,
        .dstAccessMask = dstAccess,
        .oldLayout = oldLayout,
        .newLayout = newLayout,
        .srcQueueFamilyIndex = srcFamily,
        .dstQueueFamilyIndex = dstFamily,
        .image = image,
        .subresourceRange = range,
    };
    VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}

}  // namespace vkf
