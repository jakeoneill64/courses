#include <chrono>
#include <cstdio>
#include <cstring>
#include <vector>

#include "basics.hpp"

namespace {

double millisecondsSince(std::chrono::steady_clock::time_point start) {
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start)
        .count();
}

// snippet:begin pool
VkCommandPool createPool(const u1::Device& device) {
    const VkCommandPoolCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = device.queueFamily,
    };
    VkCommandPool pool = VK_NULL_HANDLE;
    U1_CHECK(vkCreateCommandPool(device.device, &info, nullptr, &pool));
    return pool;
}

VkCommandBuffer allocate(const u1::Device& device, VkCommandPool pool) {
    const VkCommandBufferAllocateInfo info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    U1_CHECK(vkAllocateCommandBuffers(device.device, &info, &cmd));
    return cmd;
}
// snippet:end pool

// snippet:begin begin
void begin(VkCommandBuffer cmd) {
    const VkCommandBufferBeginInfo info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    U1_CHECK(vkBeginCommandBuffer(cmd, &info));
}
// snippet:end begin

// snippet:begin barrier
void barrier(VkCommandBuffer cmd, VkPipelineStageFlags2 srcStage, VkAccessFlags2 srcAccess,
             VkPipelineStageFlags2 dstStage, VkAccessFlags2 dstAccess) {
    const VkMemoryBarrier2 memory{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = srcStage,
        .srcAccessMask = srcAccess,
        .dstStageMask = dstStage,
        .dstAccessMask = dstAccess,
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &memory,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}
// snippet:end barrier

bool fillCopyReadBack(const u1::Device& device, VkCommandPool pool) {
    const VkDeviceSize bytes = 1 << 20;
    u1::Buffer gpu = u1::createBuffer(
        device, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    u1::Buffer host = u1::createBuffer(
        device, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    VkCommandBuffer cmd = allocate(device, pool);

    // snippet:begin record
    begin(cmd);
    vkCmdFillBuffer(cmd, gpu.buffer, 0, bytes, 0xC0FFEE00u);
    barrier(cmd, VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT);
    const VkBufferCopy region{.srcOffset = 0, .dstOffset = 0, .size = bytes};
    vkCmdCopyBuffer(cmd, gpu.buffer, host.buffer, 1, &region);
    barrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
    U1_CHECK(vkEndCommandBuffer(cmd));
    u1::submitAndWait(device, cmd);
    // snippet:end record

    const auto* words = static_cast<const uint32_t*>(host.mapped);
    bool ok = true;
    for (VkDeviceSize i = 0; i < bytes / 4; ++i) ok = ok && words[i] == 0xC0FFEE00u;
    std::printf("fill, copy and read back 1 MiB: %s\n", ok ? "ok" : "MISMATCH");
    u1::destroyBuffer(device, gpu);
    u1::destroyBuffer(device, host);
    return ok;
}

void uploadBandwidth(const u1::Device& device, VkCommandPool pool) {
    const VkDeviceSize bytes = 64 << 20;
    std::vector<uint8_t> source(bytes, 0x5A);
    u1::Buffer staging = u1::createBuffer(
        device, bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    u1::Buffer target = u1::createBuffer(
        device, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VkCommandBuffer cmd = allocate(device, pool);

    // snippet:begin staged-upload
    const auto start = std::chrono::steady_clock::now();
    std::memcpy(staging.mapped, source.data(), bytes);
    begin(cmd);
    const VkBufferCopy region{.size = bytes};
    vkCmdCopyBuffer(cmd, staging.buffer, target.buffer, 1, &region);
    barrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_READ_BIT);
    U1_CHECK(vkEndCommandBuffer(cmd));
    u1::submitAndWait(device, cmd);
    const double staged = millisecondsSince(start);
    // snippet:end staged-upload
    std::printf("64 MiB through a staging buffer: %.2f ms (%.1f GB/s)\n", staged,
                double(bytes) / (staged * 1e6));

    bool haveDirect = false;
    for (uint32_t i = 0; i < device.memory.memoryTypeCount; ++i) {
        const VkMemoryPropertyFlags want =
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
        if ((device.memory.memoryTypes[i].propertyFlags & want) == want) haveDirect = true;
    }
    if (haveDirect) {
        u1::Buffer shared = u1::createBuffer(
            device, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT);
        const auto t = std::chrono::steady_clock::now();
        std::memcpy(shared.mapped, source.data(), bytes);
        const double ms = millisecondsSince(t);
        std::printf(
            "64 MiB written straight into device-local, host-visible memory: %.2f ms (%.1f "
            "GB/s)\n",
            ms, double(bytes) / (ms * 1e6));
        u1::destroyBuffer(device, shared);
    } else {
        std::printf(
            "this device has no memory type that is both device-local and host-visible\n");
    }
    u1::destroyBuffer(device, staging);
    u1::destroyBuffer(device, target);
}

void submitOverhead(const u1::Device& device, VkCommandPool pool) {
    const int count = 200;
    VkCommandBuffer cmd = allocate(device, pool);
    // snippet:begin simultaneous
    const VkCommandBufferBeginInfo info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
    };
    // snippet:end simultaneous
    U1_CHECK(vkBeginCommandBuffer(cmd, &info));
    U1_CHECK(vkEndCommandBuffer(cmd));

    // snippet:begin overhead
    auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < count; ++i) u1::submitAndWait(device, cmd);
    const double oneByOne = millisecondsSince(start) / count;

    std::vector<VkCommandBufferSubmitInfo> infos(
        count, {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = cmd});
    const VkSubmitInfo2 batch{
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = static_cast<uint32_t>(infos.size()),
        .pCommandBufferInfos = infos.data(),
    };
    start = std::chrono::steady_clock::now();
    U1_CHECK(vkQueueSubmit2(device.queue, 1, &batch, VK_NULL_HANDLE));
    U1_CHECK(vkQueueWaitIdle(device.queue));
    const double batched = millisecondsSince(start) / count;
    // snippet:end overhead
    std::printf(
        "empty command buffer: %.1f us per submit and wait, %.2f us each when %d are "
        "batched\n",
        oneByOne * 1000, batched * 1000, count);
}

}  // namespace

int main() try {
    u1::Instance instance = u1::createInstance("u1_commands");
    u1::Device device = u1::createDevice(u1::pickPhysicalDevice(instance.instance));
    VkCommandPool pool = createPool(device);
    const bool ok = fillCopyReadBack(device, pool);
    uploadBandwidth(device, pool);
    submitOverhead(device, pool);
    vkDestroyCommandPool(device.device, pool, nullptr);
    vkDestroyDevice(device.device, nullptr);
    u1::destroyInstance(instance);
    return u1::finish(ok);
} catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
}
