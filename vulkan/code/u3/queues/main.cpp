#include <vkf/vkf.hpp>

#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"

namespace {

struct CountPush {
    uint32_t count;
};

struct StepsPush {
    uint32_t steps;
};

// vkf::createBuffer always makes EXCLUSIVE buffers, so this one is made here.
struct ConcurrentBuffer {
    vkf::Unique<VkBuffer> buffer;
    vkf::Unique<VkDeviceMemory> memory;
};

// snippet:begin concurrent
ConcurrentBuffer createConcurrent(const vkf::Context& ctx, VkDeviceSize size,
                                  VkBufferUsageFlags usage, uint32_t familyA,
                                  uint32_t familyB) {
    const uint32_t families[] = {familyA, familyB};
    const VkBufferCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_CONCURRENT,
        .queueFamilyIndexCount = 2,
        .pQueueFamilyIndices = families,
    };
    // snippet:end concurrent
    VkBuffer buffer = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateBuffer(ctx.device(), &info, nullptr, &buffer));
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(ctx.device(), buffer, &requirements);
    const VkMemoryAllocateInfo allocate{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = vkf::findMemoryType(ctx, requirements.memoryTypeBits,
                                               VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VKF_CHECK(vkAllocateMemory(ctx.device(), &allocate, nullptr, &memory));
    VKF_CHECK(vkBindBufferMemory(ctx.device(), buffer, memory, 0));
    ctx.name(buffer, "concurrent target");
    return {{ctx.device(), buffer}, {ctx.device(), memory}};
}

// snippet:begin release
void recordCopy(VkCommandBuffer cmd, VkBuffer staging, VkBuffer target, VkDeviceSize bytes,
                uint32_t from, uint32_t to) {
    const VkBufferCopy region{.size = bytes};
    vkCmdCopyBuffer(cmd, staging, target, 1, &region);
    if (from == to) return;
    const VkBufferMemoryBarrier2 release{
        .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
        .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_NONE,
        .dstAccessMask = VK_ACCESS_2_NONE,
        .srcQueueFamilyIndex = from,
        .dstQueueFamilyIndex = to,
        .buffer = target,
        .offset = 0,
        .size = VK_WHOLE_SIZE,
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .bufferMemoryBarrierCount = 1,
        .pBufferMemoryBarriers = &release,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
}
// snippet:end release

// snippet:begin acquire
void recordUse(VkCommandBuffer cmd, const u3::Kernel& use, VkDescriptorSet set,
               VkBuffer target, uint32_t count, uint32_t from, uint32_t to) {
    if (from != to) {
        // The source stage matches the semaphore wait, so the acquire happens after it.
        const VkBufferMemoryBarrier2 acquire{
            .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_NONE,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
            .srcQueueFamilyIndex = from,
            .dstQueueFamilyIndex = to,
            .buffer = target,
            .offset = 0,
            .size = VK_WHOLE_SIZE,
        };
        const VkDependencyInfo dependency{
            .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .bufferMemoryBarrierCount = 1,
            .pBufferMemoryBarriers = &acquire,
        };
        vkCmdPipelineBarrier2(cmd, &dependency);
    }
    u3::dispatch(cmd, use, set, CountPush{count}, vkf::groupCount(count, 256));
    vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                       VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                       VK_ACCESS_2_HOST_READ_BIT);
}
// snippet:end acquire

bool uploadThenUse(const vkf::Context& ctx, VkBuffer target, bool exclusive, uint32_t count) {
    const VkDeviceSize bytes = VkDeviceSize(count) * 4;
    const vkf::Buffer staging = vkf::createBuffer(ctx, bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                                  vkf::MemoryUse::Upload, "staging");
    const vkf::Buffer results = vkf::createBuffer(
        ctx, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vkf::MemoryUse::Readback, "results");
    for (uint32_t i = 0; i < count; ++i) staging.data<uint32_t>()[i] = u3::scramble(i);
    staging.flush();

    const u3::Kernel use =
        u3::makeKernel(ctx, "use.comp",
                       {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER},
                       sizeof(CountPush));
    vkf::DescriptorPool pool(ctx);
    const VkDescriptorSet set = u3::bufferSet(ctx, pool, use, {target, results});
    const uint32_t from = ctx.transferQueue().family;
    const uint32_t to = ctx.mainQueue().family;
    const uint32_t releaseFrom = exclusive ? from : to;
    const auto transferPool = vkf::createCommandPool(ctx, from);
    const auto mainPool = vkf::createCommandPool(ctx, to);
    VkCommandBuffer copy = vkf::allocateCommandBuffer(ctx, transferPool);
    vkf::beginCommands(copy);
    recordCopy(copy, staging, target, bytes, releaseFrom, to);
    vkf::endCommands(copy);
    VkCommandBuffer read = vkf::allocateCommandBuffer(ctx, mainPool);
    vkf::beginCommands(read);
    recordUse(read, use, set, target, count, releaseFrom, to);
    vkf::endCommands(read);

    // snippet:begin upload-submit
    const auto uploaded = vkf::createSemaphore(ctx);
    const auto fence = vkf::createFence(ctx);
    const vkf::SemaphoreSubmit signal{uploaded, 0, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
    vkf::submit(ctx.transferQueue(), std::span(&copy, 1), {}, std::span(&signal, 1));
    const vkf::SemaphoreSubmit wait{uploaded, 0, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT};
    vkf::submit(ctx.mainQueue(), std::span(&read, 1), std::span(&wait, 1), {}, fence);
    vkf::waitFence(ctx, fence);
    // snippet:end upload-submit

    results.invalidate();
    for (uint32_t i = 0; i < count; ++i) {
        if (results.data<uint32_t>()[i] != u3::scramble(i) * 3u + 1u) return false;
    }
    return true;
}

struct Workload {
    uint32_t groups;
    uint32_t steps;
};

struct Overlap {
    double oneQueue = 0, oneQueueBarrier = 0, twoQueues = 0;
    double mainGpu = 0, computeGpu = 0;
    bool correct = true;
};

bool check(const vkf::Buffer& results, const Workload& w) {
    results.invalidate();
    for (uint32_t i = 0; i < w.groups * 64; ++i) {
        if (results.data<uint32_t>()[i] != u3::lcgJump(i * 7 + 1, w.steps)) return false;
    }
    return true;
}

Overlap overlap(const vkf::Context& ctx, const Workload& w, int repeats) {
    const u3::Kernel work = u3::makeKernel(
        ctx, "work.comp", {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER}, sizeof(StepsPush));
    vkf::DescriptorPool pool(ctx);
    const VkDeviceSize bytes = VkDeviceSize(w.groups) * 64 * 4;
    const auto results = [&](const char* name) {
        return vkf::createBuffer(ctx, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                 vkf::MemoryUse::Readback, name);
    };
    const vkf::Buffer first = results("first results");
    const vkf::Buffer second = results("second results");
    const VkDescriptorSet firstSet = u3::bufferSet(ctx, pool, work, {first});
    const VkDescriptorSet secondSet = u3::bufferSet(ctx, pool, work, {second});
    const auto mainPool = vkf::createCommandPool(ctx, ctx.mainQueue().family);
    const auto computePool = vkf::createCommandPool(ctx, ctx.computeQueue().family);
    const bool computeTimed =
        ctx.properties().queueFamilies[ctx.computeQueue().family].timestampValidBits > 0;
    vkf::GpuTimer mainTimer(ctx, 2), computeTimer(ctx, 2);
    const auto toHost = [](VkCommandBuffer cmd) {
        vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                           VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT,
                           VK_ACCESS_2_HOST_READ_BIT);
    };
    const auto both = [&](VkCommandBuffer cmd, bool barrier) {
        mainTimer.reset(cmd);
        mainTimer.stamp(cmd);
        u3::dispatch(cmd, work, firstSet, StepsPush{w.steps}, w.groups);
        if (barrier) {
            vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_NONE,
                               VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_NONE);
        }
        u3::dispatch(cmd, work, secondSet, StepsPush{w.steps}, w.groups);
        mainTimer.stamp(cmd);
        toHost(cmd);
    };
    const auto mainFence = vkf::createFence(ctx);
    const auto computeFence = vkf::createFence(ctx);
    const auto finish = [&](VkFence fence) {
        vkf::waitFence(ctx, fence);
        VKF_CHECK(vkResetFences(ctx.device(), 1, &fence));
    };

    Overlap out;
    std::vector<double> one, oneBarrier, two, mainGpu, computeGpu;
    for (int r = 0; r <= repeats; ++r) {
        for (bool barrier : {false, true}) {
            VkCommandBuffer cmd = vkf::allocateCommandBuffer(ctx, mainPool);
            vkf::beginCommands(cmd);
            both(cmd, barrier);
            vkf::endCommands(cmd);
            vkf::CpuTimer wall;
            vkf::submit(ctx.mainQueue(), std::span(&cmd, 1), {}, {}, mainFence);
            finish(mainFence);
            if (r > 0) (barrier ? oneBarrier : one).push_back(wall.elapsedMs());
            out.correct = out.correct && check(first, w) && check(second, w);
        }
        // snippet:begin two-queues
        VkCommandBuffer onMain = vkf::allocateCommandBuffer(ctx, mainPool);
        vkf::beginCommands(onMain);
        mainTimer.reset(onMain);
        mainTimer.stamp(onMain);
        u3::dispatch(onMain, work, firstSet, StepsPush{w.steps}, w.groups);
        mainTimer.stamp(onMain);
        toHost(onMain);
        vkf::endCommands(onMain);
        VkCommandBuffer onCompute = vkf::allocateCommandBuffer(ctx, computePool);
        vkf::beginCommands(onCompute);
        if (computeTimed) {
            computeTimer.reset(onCompute);
            computeTimer.stamp(onCompute);
        }
        u3::dispatch(onCompute, work, secondSet, StepsPush{w.steps}, w.groups);
        if (computeTimed) computeTimer.stamp(onCompute);
        toHost(onCompute);
        vkf::endCommands(onCompute);
        vkf::CpuTimer wall;
        vkf::submit(ctx.mainQueue(), std::span(&onMain, 1), {}, {}, mainFence);
        vkf::submit(ctx.computeQueue(), std::span(&onCompute, 1), {}, {}, computeFence);
        finish(mainFence);
        finish(computeFence);
        // snippet:end two-queues
        if (r > 0) {
            two.push_back(wall.elapsedMs());
            mainGpu.push_back(mainTimer.read()[1]);
            if (computeTimed) computeGpu.push_back(computeTimer.read()[1]);
        }
        out.correct = out.correct && check(first, w) && check(second, w);
        VKF_CHECK(vkResetCommandPool(ctx.device(), mainPool, 0));
        VKF_CHECK(vkResetCommandPool(ctx.device(), computePool, 0));
    }
    out.oneQueue = vkf::summarize(one).median;
    out.oneQueueBarrier = vkf::summarize(oneBarrier).median;
    out.twoQueues = vkf::summarize(two).median;
    out.mainGpu = vkf::summarize(mainGpu).median;
    out.computeGpu = vkf::summarize(computeGpu).median;
    return out;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool shared = args.flag("--shared-queue");
        const auto repeats = int(args.integer("--repeats", 10));
        const auto count = uint32_t(args.integer("--count", 1 << 20));
        vkf::Context ctx(
            {.appName = "u3_queues", .asyncCompute = !shared, .transferQueue = !shared});
        const uint32_t mainFamily = ctx.mainQueue().family;
        const uint32_t transferFamily = ctx.transferQueue().family;
        vkf::print(
            "queues: main family {}, transfer family {}{}, compute family {}{}\n", mainFamily,
            transferFamily, ctx.hasSeparateTransferQueue() ? "" : " (shared)",
            ctx.computeQueue().family, ctx.hasSeparateComputeQueue() ? "" : " (shared)");

        bool ok = true;
        const vkf::Buffer exclusive = vkf::createBuffer(
            ctx, VkDeviceSize(count) * 4,
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            vkf::MemoryUse::DeviceLocal, "exclusive target");
        const bool viaOwnership = uploadThenUse(ctx, exclusive, true, count);
        ok = ok && viaOwnership;
        vkf::print("upload, exclusive buffer: {}, {}\n",
                   transferFamily != mainFamily
                       ? "released by family " + std::to_string(transferFamily) +
                             ", acquired by family " + std::to_string(mainFamily)
                       : std::string("one family, so no ownership transfer"),
                   viaOwnership ? "correct" : "WRONG");
        if (transferFamily != mainFamily) {
            const ConcurrentBuffer concurrent = createConcurrent(
                ctx, VkDeviceSize(count) * 4,
                VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                transferFamily, mainFamily);
            const bool viaConcurrent = uploadThenUse(ctx, concurrent.buffer, false, count);
            ok = ok && viaConcurrent;
            vkf::print("upload, concurrent buffer: no ownership transfer, {}\n",
                       viaConcurrent ? "correct" : "WRONG");
        } else {
            vkf::print("upload, concurrent buffer: needs two families; skipped\n");
        }

        const Workload workloads[] = {{8, 400000}, {2048, 4000}};
        vkf::print("two independent workloads, ms from submit to finish, median of {}\n",
                   repeats);
        vkf::print("  {:<22}{:>11}{:>14}{:>12}{:>24}\n", "workload", "one queue", "+ barrier",
                   "two queues", "GPU ms: main, compute");
        for (const Workload& w : workloads) {
            const Overlap o = overlap(ctx, w, repeats);
            ok = ok && o.correct;
            vkf::print("  {:<22}{:>11.3f}{:>14.3f}{:>12.3f}{:>16.3f},{:>7.3f}{}\n",
                       std::to_string(w.groups) + " groups x " + std::to_string(w.steps),
                       o.oneQueue, o.oneQueueBarrier, o.twoQueues, o.mainGpu, o.computeGpu,
                       o.correct ? "" : "  WRONG");
        }
        if (!ok) throw std::runtime_error("results differ from the CPU");
        vkf::print("PASS\n");
    });
}
