#include <vkf/vkf.hpp>

#include <algorithm>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"
#include "messages.hpp"

namespace {

constexpr uint32_t Count = 1 << 16;
constexpr uint32_t HostCount = 1 << 20;
constexpr uint32_t Side = 256;

struct FillPush {
    uint32_t count;
    uint32_t seed;
};

struct CountPush {
    uint32_t count;
};

struct SeedPush {
    uint32_t seed;
};

constexpr uint32_t filled(uint32_t i, uint32_t seed) {
    return u3::scramble(i ^ seed);
}
constexpr uint32_t transformed(uint32_t value) {
    return value * 3u + 1u;
}

constexpr VkBufferUsageFlags StorageCopy = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                           VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                           VK_BUFFER_USAGE_TRANSFER_DST_BIT;

struct Env {
    explicit Env(const vkf::Context& c)
        : ctx(c),
          pool(c),
          fill(u3::makeKernel(c, "fill.comp", {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
                              sizeof(FillPush))),
          transform(u3::makeKernel(
              c, "transform.comp",
              {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
              sizeof(CountPush))),
          args(u3::makeKernel(c, "args.comp", {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
                              sizeof(CountPush))),
          pattern(u3::makeKernel(c, "pattern.comp", {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE},
                                 sizeof(SeedPush))),
          a(vkf::createBuffer(c, Count * 4, StorageCopy, vkf::MemoryUse::DeviceLocal, "a")),
          b(vkf::createBuffer(c, Count * 4, StorageCopy, vkf::MemoryUse::DeviceLocal, "b")),
          indirect(vkf::createBuffer(c, 12,
                                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                     vkf::MemoryUse::DeviceLocal, "indirect")),
          staging(vkf::createBuffer(c, Count * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                    vkf::MemoryUse::Upload, "staging")),
          upload(vkf::createBuffer(c, HostCount * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                   vkf::MemoryUse::Upload, "upload")),
          uploadOut(vkf::createBuffer(c, HostCount * 4, StorageCopy,
                                      vkf::MemoryUse::DeviceLocal, "upload out")),
          readback(vkf::createBuffer(c, Side * Side * 4, StorageCopy, vkf::MemoryUse::Readback,
                                     "readback")),
          image(vkf::createImage(
              c,
              {.format = VK_FORMAT_R32_UINT,
               .width = Side,
               .height = Side,
               .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
              "image")) {}

    const vkf::Context& ctx;
    vkf::DescriptorPool pool;
    u3::Kernel fill, transform, args, pattern;
    vkf::Buffer a, b, indirect, staging, upload, uploadOut, readback;
    vkf::Image image;

    void fillBuffer(VkCommandBuffer cmd, VkBuffer target, uint32_t count, uint32_t seed) {
        const VkDescriptorSet set = u3::bufferSet(ctx, pool, fill, {target});
        u3::dispatch(cmd, fill, set, FillPush{count, seed}, vkf::groupCount(count, 256));
    }

    void transformBuffer(VkCommandBuffer cmd, VkBuffer src, VkBuffer dst, uint32_t count) {
        const VkDescriptorSet set = u3::bufferSet(ctx, pool, transform, {src, dst});
        u3::dispatch(cmd, transform, set, CountPush{count}, vkf::groupCount(count, 256));
    }
};

template <class Expected>
uint32_t countWrong(const uint32_t* values, uint32_t count, Expected expected) {
    uint32_t wrong = 0;
    for (uint32_t i = 0; i < count; ++i) wrong += values[i] != expected(i) ? 1 : 0;
    return wrong;
}

template <class Expected>
uint32_t countWrong(const vkf::Context& ctx, const vkf::Buffer& buffer, uint32_t count,
                    Expected expected) {
    const std::vector<uint32_t> values = vkf::download<uint32_t>(ctx, buffer, count);
    return countWrong(values.data(), count, expected);
}

uint32_t computeCompute(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.fillBuffer(cmd, e.a, Count, 1);
        // snippet:begin compute-compute
        const VkMemoryBarrier2 barrier{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &barrier,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &dependency);
        // snippet:end compute-compute
        e.transformBuffer(cmd, e.a, e.b, Count);
    });
    return countWrong(e.ctx, e.b, Count, [](uint32_t i) { return transformed(filled(i, 1)); });
}

uint32_t writeAfterRead(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) { e.fillBuffer(cmd, e.a, Count, 2); });
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.transformBuffer(cmd, e.a, e.b, Count);
        // snippet:begin war
        const VkMemoryBarrier2 barrier{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_NONE,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_NONE,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &barrier,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &dependency);
        // snippet:end war
        e.fillBuffer(cmd, e.a, Count, 3);
    });
    return countWrong(e.ctx, e.b, Count,
                      [](uint32_t i) { return transformed(filled(i, 2)); }) +
           countWrong(e.ctx, e.a, Count, [](uint32_t i) { return filled(i, 3); });
}

uint32_t writeAfterWrite(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.fillBuffer(cmd, e.a, Count, 4);
        // snippet:begin waw
        const VkMemoryBarrier2 barrier{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &barrier,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &dependency);
        // snippet:end waw
        e.fillBuffer(cmd, e.a, Count, 5);
    });
    return countWrong(e.ctx, e.a, Count, [](uint32_t i) { return filled(i, 5); });
}

uint32_t transferCompute(Env& e, bool bug) {
    auto* staged = e.staging.data<uint32_t>();
    for (uint32_t i = 0; i < Count; ++i) staged[i] = filled(i, 6);
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        const VkBufferCopy region{.size = Count * 4};
        vkCmdCopyBuffer(cmd, e.staging, e.a, 1, &region);
        // snippet:begin transfer-compute
        const VkBufferMemoryBarrier2 barrier{
            .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
            .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .buffer = e.a,
            .offset = 0,
            .size = VK_WHOLE_SIZE,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .bufferMemoryBarrierCount = 1,
            .pBufferMemoryBarriers = &barrier,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &dependency);
        // snippet:end transfer-compute
        e.transformBuffer(cmd, e.a, e.b, Count);
    });
    return countWrong(e.ctx, e.b, Count, [](uint32_t i) { return transformed(filled(i, 6)); });
}

uint32_t computeTransfer(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.fillBuffer(cmd, e.a, Count, 7);
        // snippet:begin compute-transfer
        const VkMemoryBarrier2 toCopy{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
            .dstAccessMask = VK_ACCESS_2_TRANSFER_READ_BIT,
        };
        const VkDependencyInfo beforeCopy{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &toCopy,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &beforeCopy);
        const VkBufferCopy region{.size = Count * 4};
        vkCmdCopyBuffer(cmd, e.a, e.readback, 1, &region);
        const VkMemoryBarrier2 toHost{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
            .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
            .dstAccessMask = VK_ACCESS_2_HOST_READ_BIT,
        };
        const VkDependencyInfo afterCopy{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &toHost,
        };
        vkCmdPipelineBarrier2(cmd, &afterCopy);
        // snippet:end compute-transfer
    });
    e.readback.invalidate();
    return countWrong(e.readback.data<uint32_t>(), Count,
                      [](uint32_t i) { return filled(i, 7); });
}

uint32_t computeIndirect(Env& e, bool bug) {
    const uint32_t items = Count - 1000;
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        vkCmdFillBuffer(cmd, e.indirect, 0, VK_WHOLE_SIZE, 0);
        vkCmdFillBuffer(cmd, e.b, 0, VK_WHOLE_SIZE, 0);
    });
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        const VkDescriptorSet argsSet = u3::bufferSet(e.ctx, e.pool, e.args, {e.indirect});
        u3::dispatch(cmd, e.args, argsSet, CountPush{items}, 1);
        // snippet:begin compute-indirect
        const VkMemoryBarrier2 barrier{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
            .dstAccessMask = VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &barrier,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &dependency);
        const VkDescriptorSet fillSet = u3::bufferSet(e.ctx, e.pool, e.fill, {e.b});
        u3::bind(cmd, e.fill, fillSet, FillPush{items, 8});
        vkCmdDispatchIndirect(cmd, e.indirect, 0);
        // snippet:end compute-indirect
    });
    return countWrong(e.ctx, e.b, items, [](uint32_t i) { return filled(i, 8); });
}

// Stands in for real work on the host: a few milliseconds for the whole buffer.
constexpr uint32_t produced(uint32_t i, uint32_t seed) {
    uint32_t x = i ^ seed;
    for (int round = 0; round < 32; ++round) x = u3::scramble(x);
    return x;
}

void writeHostValues(const vkf::Buffer& buffer, uint32_t seed) {
    auto* values = buffer.data<uint32_t>();
    for (uint32_t i = 0; i < HostCount; ++i) values[i] = produced(i, seed);
}

uint32_t hostDevice(Env& e, bool bug) {
    writeHostValues(e.upload, 9);
    // snippet:begin host-device
    VkCommandBuffer cmd = vkf::allocateCommandBuffer(e.ctx, e.ctx.commandPool());
    vkf::beginCommands(cmd);
    e.transformBuffer(cmd, e.upload, e.uploadOut, HostCount);
    vkf::endCommands(cmd);
    const auto fence = vkf::createFence(e.ctx);
    if (!bug) writeHostValues(e.upload, 10);
    vkf::submit(e.ctx.mainQueue(), std::span(&cmd, 1), {}, {}, fence);
    if (bug) writeHostValues(e.upload, 10);
    vkf::waitFence(e.ctx, fence);
    // snippet:end host-device
    vkFreeCommandBuffers(e.ctx.device(), e.ctx.commandPool(), 1, &cmd);
    return countWrong(e.ctx, e.uploadOut, HostCount,
                      [](uint32_t i) { return transformed(produced(i, 10)); });
}

uint32_t deviceHost(Env& e, bool bug) {
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        e.fillBuffer(cmd, e.readback, Count, 11);
        // snippet:begin device-host
        const VkMemoryBarrier2 barrier{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
            .dstAccessMask = VK_ACCESS_2_HOST_READ_BIT,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &barrier,
        };
        if (!bug) vkCmdPipelineBarrier2(cmd, &dependency);
        // snippet:end device-host
    });
    e.readback.invalidate();
    const uint32_t* values = e.readback.data<uint32_t>();
    return countWrong(values, Count, [](uint32_t i) { return filled(i, 11); });
}

uint32_t imageLayout(Env& e, bool bug) {
    VkDescriptorSet set = e.pool.allocate(e.pattern.setLayout);
    vkf::DescriptorWriter()
        .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, e.image.view, VK_IMAGE_LAYOUT_GENERAL)
        .update(e.ctx, set);
    vkf::submitNow(e.ctx, [&](VkCommandBuffer cmd) {
        // snippet:begin image-general
        const VkImageMemoryBarrier2 toGeneral{
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_NONE,
            .srcAccessMask = VK_ACCESS_2_NONE,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = VK_IMAGE_LAYOUT_GENERAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = e.image,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
        };
        const VkDependencyInfo beforeWrite{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &toGeneral,
        };
        vkCmdPipelineBarrier2(cmd, &beforeWrite);
        u3::dispatch(cmd, e.pattern, set, SeedPush{12}, Side / 16, Side / 16);
        // snippet:end image-general
        // snippet:begin image-transfer
        VkImageMemoryBarrier2 toTransfer{
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
            .dstAccessMask = VK_ACCESS_2_TRANSFER_READ_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_GENERAL,
            .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = e.image,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
        };
        if (bug) {
            toTransfer.srcStageMask = VK_PIPELINE_STAGE_2_NONE;
            toTransfer.srcAccessMask = VK_ACCESS_2_NONE;
        }
        const VkDependencyInfo beforeCopy{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &toTransfer,
        };
        vkCmdPipelineBarrier2(cmd, &beforeCopy);
        // snippet:end image-transfer
        const VkBufferImageCopy region{
            .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
            .imageExtent = {Side, Side, 1},
        };
        vkCmdCopyImageToBuffer(cmd, e.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, e.readback,
                               1, &region);
        vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                           VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
    });
    e.readback.invalidate();
    return countWrong(e.readback.data<uint32_t>(), Side * Side,
                      [](uint32_t i) { return filled(i, 12); });
}

struct Case {
    const char* name;
    const char* hazard;
    const char* scenario;
    const char* bug;
    uint32_t (*run)(Env&, bool);
    bool hostSide = false;
};

constexpr Case Cases[] = {
    {"compute-compute", "RAW", "dispatch writes, dispatch reads", "no barrier",
     computeCompute},
    {"war", "WAR", "dispatch reads, dispatch writes", "no barrier", writeAfterRead},
    {"waw", "WAW", "dispatch writes, dispatch writes", "no barrier", writeAfterWrite},
    {"transfer-compute", "RAW", "copy writes, dispatch reads", "no barrier", transferCompute},
    {"compute-transfer", "RAW", "dispatch writes, copy reads", "no barrier", computeTransfer},
    {"compute-indirect", "RAW", "dispatch writes, indirect dispatch reads", "no barrier",
     computeIndirect},
    {"host-device", "RAW", "host writes, dispatch reads", "write after submit", hostDevice,
     true},
    {"device-host", "RAW", "dispatch writes, host reads", "no barrier", deviceHost, true},
    {"image-layout", "RAW", "dispatch writes image, copy reads", "empty source scope",
     imageLayout},
};

std::string join(const std::vector<std::string>& ids) {
    std::string text;
    for (const std::string& id : ids) text += (text.empty() ? "" : ", ") + id;
    return text;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const std::string only = args.text("--case", "all");
        const bool bug = args.flag("--bug");
        vkf::Context ctx({.appName = "u3_hazards"});
        u3::MessageLog log(ctx);
        Env env(ctx);

        int ran = 0;
        int detected = 0;
        int undetected = 0;
        for (const Case& c : Cases) {
            if (only != "all" && only != c.name) continue;
            ++ran;
            env.pool.reset();
            const uint32_t wrong = c.run(env, bug);
            const std::vector<std::string> ids = log.take();
            const bool clean = wrong == 0 && ids.empty();
            std::string status = clean ? "ok" : "FAIL";
            if (bug) status = std::string("bug: ") + c.bug;
            vkf::print("{:<17}{:<5}{:<42}{}\n", c.name, c.hazard, c.scenario, status);
            if (clean) {
                undetected += bug ? 1 : 0;
                if (!bug) continue;
            } else {
                ++detected;
            }
            const std::string silent = c.hostSide ? " (host accesses are not tracked)" : "";
            vkf::print("  validation: {}\n", ids.empty() ? "nothing" + silent : join(ids));
            vkf::print("  results: {}\n", wrong == 0 ? std::string("correct")
                                                     : std::format("{} values wrong", wrong));
        }
        if (ran == 0) throw std::runtime_error("unknown --case " + only);
        if (bug) {
            throw std::runtime_error(
                std::format("--bug: {} detected, {} undetected", detected, undetected));
        }
        if (detected > 0) throw std::runtime_error(std::format("{} case(s) failed", detected));
        vkf::print("PASS {} case{}\n", ran, ran == 1 ? "" : "s");
    });
}
