#pragma once

#include <vulkan/vulkan.h>

#include <cstdint>
#include <functional>
#include <span>

#include "vkf/context.hpp"
#include "vkf/handles.hpp"

namespace vkf {

// Records into a fresh command buffer, submits it to the main queue and waits on a fence.
void submitNow(const Context& ctx, const std::function<void(VkCommandBuffer)>& record);

Unique<VkCommandPool> createCommandPool(
    const Context& ctx, uint32_t family,
    VkCommandPoolCreateFlags flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT);
VkCommandBuffer allocateCommandBuffer(const Context& ctx, VkCommandPool pool);
void beginCommands(VkCommandBuffer cmd, VkCommandBufferUsageFlags usage =
                                            VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
void endCommands(VkCommandBuffer cmd);

Unique<VkFence> createFence(const Context& ctx, bool signaled = false);
Unique<VkSemaphore> createSemaphore(const Context& ctx);
Unique<VkSemaphore> createTimelineSemaphore(const Context& ctx, uint64_t initialValue = 0);
void waitFence(const Context& ctx, VkFence fence, uint64_t timeoutNs = UINT64_MAX);

struct SemaphoreSubmit {
    VkSemaphore semaphore = VK_NULL_HANDLE;
    uint64_t value = 0;  // ignored for binary semaphores
    VkPipelineStageFlags2 stages = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
};

void submit(VkQueue queue, std::span<const VkCommandBuffer> commandBuffers,
            std::span<const SemaphoreSubmit> waits = {},
            std::span<const SemaphoreSubmit> signals = {}, VkFence fence = VK_NULL_HANDLE);

VkImageSubresourceRange colorRange(uint32_t baseMip = 0,
                                   uint32_t mipCount = VK_REMAINING_MIP_LEVELS,
                                   uint32_t baseLayer = 0,
                                   uint32_t layerCount = VK_REMAINING_ARRAY_LAYERS);

void memoryBarrier(VkCommandBuffer cmd, VkPipelineStageFlags2 srcStages,
                   VkAccessFlags2 srcAccess, VkPipelineStageFlags2 dstStages,
                   VkAccessFlags2 dstAccess);

void bufferBarrier(VkCommandBuffer cmd, VkBuffer buffer, VkPipelineStageFlags2 srcStages,
                   VkAccessFlags2 srcAccess, VkPipelineStageFlags2 dstStages,
                   VkAccessFlags2 dstAccess, VkDeviceSize offset = 0,
                   VkDeviceSize size = VK_WHOLE_SIZE,
                   uint32_t srcFamily = VK_QUEUE_FAMILY_IGNORED,
                   uint32_t dstFamily = VK_QUEUE_FAMILY_IGNORED);

void imageBarrier(VkCommandBuffer cmd, VkImage image, VkImageLayout oldLayout,
                  VkImageLayout newLayout, VkPipelineStageFlags2 srcStages,
                  VkAccessFlags2 srcAccess, VkPipelineStageFlags2 dstStages,
                  VkAccessFlags2 dstAccess, VkImageSubresourceRange range = colorRange(),
                  uint32_t srcFamily = VK_QUEUE_FAMILY_IGNORED,
                  uint32_t dstFamily = VK_QUEUE_FAMILY_IGNORED);

}  // namespace vkf
