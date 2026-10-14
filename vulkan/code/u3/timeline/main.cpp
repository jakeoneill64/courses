#include <vkf/vkf.hpp>

#include <algorithm>
#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"

namespace {

struct CountPush {
    uint32_t count;
};

constexpr uint32_t inputValue(uint32_t item, uint32_t i) {
    return u3::scramble(item * 0x9e3779b9u + i);
}
constexpr uint32_t processed(uint32_t value) {
    return value * 2654435761u + 1u;
}

struct Ring {
    Ring(const vkf::Context& ctx, uint32_t slots, uint32_t count)
        : slots(slots),
          count(count),
          inputs(vkf::createBuffer(ctx, VkDeviceSize(slots) * count * 4,
                                   VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vkf::MemoryUse::Upload,
                                   "inputs")),
          outputs(vkf::createBuffer(ctx, VkDeviceSize(slots) * count * 4,
                                    VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                    vkf::MemoryUse::Readback, "outputs")),
          pool(ctx),
          kernel(u3::makeKernel(
              ctx, "process.comp",
              {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
              sizeof(CountPush))) {
        const VkDeviceSize bytes = VkDeviceSize(count) * 4;
        for (uint32_t s = 0; s < slots; ++s) {
            sets.push_back(pool.allocate(kernel.setLayout));
            vkf::DescriptorWriter()
                .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, inputs, s * bytes, bytes)
                .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, outputs, s * bytes, bytes)
                .update(ctx, sets.back());
        }
    }

    void fill(uint32_t slot, uint32_t item) const {
        uint32_t* values = inputs.data<uint32_t>() + size_t(slot) * count;
        for (uint32_t i = 0; i < count; ++i) values[i] = inputValue(item, i);
        inputs.flush(VkDeviceSize(slot) * count * 4, VkDeviceSize(count) * 4);
    }

    bool check(uint32_t slot, uint32_t item) const {
        outputs.invalidate(VkDeviceSize(slot) * count * 4, VkDeviceSize(count) * 4);
        const uint32_t* values = outputs.data<uint32_t>() + size_t(slot) * count;
        for (uint32_t i = 0; i < count; ++i) {
            if (values[i] != processed(inputValue(item, i))) return false;
        }
        return true;
    }

    uint32_t slots;
    uint32_t count;
    vkf::Buffer inputs;
    vkf::Buffer outputs;
    vkf::DescriptorPool pool;
    u3::Kernel kernel;
    std::vector<VkDescriptorSet> sets;
};

void toHost(VkCommandBuffer cmd) {
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
    vkCmdPipelineBarrier2(cmd, &dependency);
}

// snippet:begin record-item
void recordItem(VkCommandBuffer cmd, const Ring& ring, uint32_t slot, bool hostWritesLater) {
    // Host writes made after the submission are not covered by the submission itself.
    if (hostWritesLater) {
        const VkMemoryBarrier2 fromHost{
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
            .srcAccessMask = VK_ACCESS_2_HOST_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
        };
        const VkDependencyInfo before{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .memoryBarrierCount = 1,
            .pMemoryBarriers = &fromHost,
        };
        vkCmdPipelineBarrier2(cmd, &before);
    }
    u3::dispatch(cmd, ring.kernel, ring.sets[slot], CountPush{ring.count},
                 vkf::groupCount(ring.count, 256));
    toHost(cmd);
}
// snippet:end record-item

std::vector<VkCommandBuffer> recordSlots(const vkf::Context& ctx, VkCommandPool pool,
                                         const Ring& ring, bool hostWritesLater) {
    std::vector<VkCommandBuffer> cmds;
    for (uint32_t slot = 0; slot < ring.slots; ++slot) {
        cmds.push_back(vkf::allocateCommandBuffer(ctx, pool));
        vkf::beginCommands(cmds.back(), 0);
        recordItem(cmds.back(), ring, slot, hostWritesLater);
        vkf::endCommands(cmds.back());
    }
    return cmds;
}

double runTimeline(const vkf::Context& ctx, const Ring& ring, uint32_t items,
                   uint32_t& correct) {
    const auto pool = vkf::createCommandPool(ctx, ctx.mainQueue().family);
    const std::vector<VkCommandBuffer> cmds = recordSlots(ctx, pool, ring, true);
    const auto timeline = vkf::createTimelineSemaphore(ctx, 0);
    // snippet:begin timeline-helpers
    // Item i waits for the host's value 2i + 1 and signals 2i + 2 when its result is ready.
    const auto submitItem = [&](uint32_t item) {
        const vkf::SemaphoreSubmit ready{timeline, 2 * uint64_t(item) + 1,
                                         VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT};
        const vkf::SemaphoreSubmit done{timeline, 2 * uint64_t(item) + 2,
                                        VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
        vkf::submit(ctx.mainQueue(), std::span(&cmds[item % ring.slots], 1),
                    std::span(&ready, 1), std::span(&done, 1));
    };
    const auto signal = [&](uint64_t value) {
        const VkSemaphoreSignalInfo info{
            .sType = VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO,
            .semaphore = timeline,
            .value = value,
        };
        VKF_CHECK(vkSignalSemaphore(ctx.device(), &info));
    };
    const auto waitFor = [&](uint64_t value) {
        const VkSemaphoreWaitInfo info{
            .sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
            .semaphoreCount = 1,
            .pSemaphores = timeline.ptr(),
            .pValues = &value,
        };
        if (VKF_CHECK(vkWaitSemaphores(ctx.device(), &info, 5'000'000'000)) == VK_TIMEOUT) {
            throw std::runtime_error("timed out waiting for the timeline semaphore");
        }
    };
    // snippet:end timeline-helpers

    vkf::CpuTimer timer;
    // snippet:begin timeline-loop
    const uint32_t ahead = std::min(items, ring.slots);
    for (uint32_t i = 0; i < ahead; ++i) submitItem(i);
    for (uint32_t i = 0; i < ahead; ++i) ring.fill(i, i);
    signal(1);
    for (uint32_t i = 0; i < items; ++i) {
        waitFor(2 * uint64_t(i) + 2);
        if (i + 1 < items) signal(2 * uint64_t(i) + 3);
        correct += ring.check(i % ring.slots, i) ? 1 : 0;
        if (i + ring.slots < items) {
            submitItem(i + ring.slots);
            ring.fill(i % ring.slots, i + ring.slots);
        }
    }
    // snippet:end timeline-loop
    return timer.elapsedMs();
}

double runFences(const vkf::Context& ctx, const Ring& ring, uint32_t items,
                 uint32_t& correct) {
    const auto pool = vkf::createCommandPool(ctx, ctx.mainQueue().family);
    const std::vector<VkCommandBuffer> cmds = recordSlots(ctx, pool, ring, false);
    std::vector<vkf::Unique<VkFence>> fences;
    for (uint32_t slot = 0; slot < ring.slots; ++slot) fences.push_back(vkf::createFence(ctx));

    vkf::CpuTimer timer;
    // snippet:begin fence-loop
    for (uint32_t i = 0; i < items + ring.slots; ++i) {
        const uint32_t slot = i % ring.slots;
        if (i >= ring.slots) {
            vkf::waitFence(ctx, fences[slot]);
            VKF_CHECK(vkResetFences(ctx.device(), 1, fences[slot].ptr()));
            correct += ring.check(slot, i - ring.slots) ? 1 : 0;
        }
        if (i < items) {
            ring.fill(slot, i);
            vkf::submit(ctx.mainQueue(), std::span(&cmds[slot], 1), {}, {}, fences[slot]);
        }
    }
    // snippet:end fence-loop
    return timer.elapsedMs();
}

bool runBinaryChain(const vkf::Context& ctx, Ring& ring) {
    const VkDeviceSize bytes = VkDeviceSize(ring.count) * 4;
    const vkf::Buffer middle = vkf::createBuffer(
        ctx, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vkf::MemoryUse::DeviceLocal, "middle");
    const VkDescriptorSet firstSet = ring.pool.allocate(ring.kernel.setLayout);
    vkf::DescriptorWriter()
        .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, ring.inputs, 0, bytes)
        .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, middle)
        .update(ctx, firstSet);
    const VkDescriptorSet secondSet = ring.pool.allocate(ring.kernel.setLayout);
    vkf::DescriptorWriter()
        .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, middle)
        .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, ring.outputs, 0, bytes)
        .update(ctx, secondSet);
    const auto pool = vkf::createCommandPool(ctx, ctx.mainQueue().family);
    const uint32_t groups = vkf::groupCount(ring.count, 256);
    VkCommandBuffer first = vkf::allocateCommandBuffer(ctx, pool);
    vkf::beginCommands(first);
    u3::dispatch(first, ring.kernel, firstSet, CountPush{ring.count}, groups);
    vkf::endCommands(first);
    VkCommandBuffer second = vkf::allocateCommandBuffer(ctx, pool);
    vkf::beginCommands(second);
    u3::dispatch(second, ring.kernel, secondSet, CountPush{ring.count}, groups);
    toHost(second);
    vkf::endCommands(second);
    ring.fill(0, 7);

    // snippet:begin binary-chain
    const auto written = vkf::createSemaphore(ctx);
    const auto fence = vkf::createFence(ctx);
    const vkf::SemaphoreSubmit signal{written, 0, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT};
    const vkf::SemaphoreSubmit wait{written, 0, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT};
    vkf::submit(ctx.mainQueue(), std::span(&first, 1), {}, std::span(&signal, 1));
    vkf::submit(ctx.mainQueue(), std::span(&second, 1), std::span(&wait, 1), {}, fence);
    vkf::waitFence(ctx, fence);
    // snippet:end binary-chain

    ring.outputs.invalidate(0, bytes);
    const uint32_t* values = ring.outputs.data<uint32_t>();
    for (uint32_t i = 0; i < ring.count; ++i) {
        if (values[i] != processed(processed(inputValue(7, i)))) return false;
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto slots = uint32_t(args.integer("--slots", 3));
        const auto items = uint32_t(args.integer("--items", 300));
        const auto count = uint32_t(args.integer("--count", 65536));
        if (slots < 2) throw std::runtime_error("--slots must be at least 2");
        vkf::Context ctx({.appName = "u3_timeline"});
        Ring ring(ctx, slots, count);

        uint32_t viaTimeline = 0;
        const double timelineMs = runTimeline(ctx, ring, items, viaTimeline);
        vkf::print(
            "timeline: {} slots, {} items of {} values, each submitted before its input\n",
            slots, items, count);
        vkf::print("  {} of {} correct in {:.1f} ms ({:.0f} items per second)\n", viaTimeline,
                   items, timelineMs, 1000.0 * items / timelineMs);
        uint32_t viaFences = 0;
        const double fenceMs = runFences(ctx, ring, items, viaFences);
        vkf::print("fences: {} slots, {} items, one fence per submission\n", slots, items);
        vkf::print("  {} of {} correct in {:.1f} ms ({:.0f} items per second)\n", viaFences,
                   items, fenceMs, 1000.0 * items / fenceMs);
        const bool chained = runBinaryChain(ctx, ring);
        vkf::print("binary semaphore: the second submission read the first's output: {}\n",
                   chained ? "correct" : "WRONG");
        if (viaTimeline != items || viaFences != items || !chained) {
            throw std::runtime_error("some results were wrong");
        }
        vkf::print("PASS\n");
    });
}
