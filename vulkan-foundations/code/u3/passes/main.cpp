#include <vkf/vkf.hpp>

#include <algorithm>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"

namespace {

struct Stats {
    uint32_t selected;
    uint32_t blurredSum;
    uint32_t indexXor;
};

struct SeedPush {
    uint32_t seed;
};

struct SelectPush {
    uint32_t count;
    uint32_t minBlurred;
    uint32_t maxEdge;
};

struct StepPush {
    uint32_t count;
};

constexpr uint32_t Seed = 2024;
constexpr uint32_t MinBlurred = 1400;
constexpr uint32_t MaxEdge = 200;

Stats reference(uint32_t side) {
    std::vector<int> field(size_t(side) * side);
    for (uint32_t i = 0; i < field.size(); ++i) field[i] = int(u3::scramble(i ^ Seed) & 255u);
    const int last = int(side) - 1;
    const auto at = [&](int x, int y) {
        return field[size_t(std::clamp(y, 0, last)) * side + size_t(std::clamp(x, 0, last))];
    };
    Stats stats{};
    for (int y = 0; y <= last; ++y) {
        for (int x = 0; x <= last; ++x) {
            uint32_t blurred = 0;
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) blurred += uint32_t(at(x + dx, y + dy));
            }
            const int edge =
                std::abs(at(x + 1, y) - at(x - 1, y)) + std::abs(at(x, y + 1) - at(x, y - 1));
            if (blurred > MinBlurred && edge < int(MaxEdge)) {
                ++stats.selected;
                stats.blurredSum += blurred;
                stats.indexXor ^= uint32_t(y) * side + uint32_t(x);
            }
        }
    }
    return stats;
}

struct Passes {
    Passes(const vkf::Context& c, uint32_t s);

    const vkf::Context& ctx;
    uint32_t side;
    vkf::DescriptorPool pool;
    u3::Kernel generate, blur, edges, select, command, score;
    vkf::Image field;
    vkf::Buffer blurred, edgeBuffer, stats, list, commandBuffer, readback;
    VkDescriptorSet generateSet, blurSet, edgesSet, selectSet, commandSet, scoreSet;

    void record(VkCommandBuffer cmd) const;
};

VkDescriptorSet fieldSet(const vkf::Context& ctx, vkf::DescriptorPool& pool,
                         const u3::Kernel& kernel, VkImageView field, VkBuffer output) {
    const VkDescriptorSet set = pool.allocate(kernel.setLayout);
    vkf::DescriptorWriter writer;
    writer.image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, field, VK_IMAGE_LAYOUT_GENERAL);
    if (output != VK_NULL_HANDLE) writer.buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, output);
    writer.update(ctx, set);
    return set;
}

Passes::Passes(const vkf::Context& c, uint32_t s) : ctx(c), side(s), pool(c) {
    constexpr VkDescriptorType Image = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    constexpr VkDescriptorType Storage = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    generate = u3::makeKernel(c, "generate.comp", {Image}, sizeof(SeedPush));
    blur = u3::makeKernel(c, "blur.comp", {Image, Storage});
    edges = u3::makeKernel(c, "edges.comp", {Image, Storage});
    select = u3::makeKernel(c, "select.comp", {Storage, Storage, Storage, Storage},
                            sizeof(SelectPush));
    command = u3::makeKernel(c, "command.comp", {Storage, Storage});
    score = u3::makeKernel(c, "score.comp", {Storage, Storage, Storage});

    const VkDeviceSize cells = VkDeviceSize(side) * side * 4;
    constexpr auto Device = vkf::MemoryUse::DeviceLocal;
    field = vkf::createImage(c, {.format = VK_FORMAT_R32_UINT, .width = side, .height = side},
                             "field");
    blurred =
        vkf::createBuffer(c, cells, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, Device, "blurred");
    edgeBuffer =
        vkf::createBuffer(c, cells, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, Device, "edges");
    list = vkf::createBuffer(c, cells, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, Device, "list");
    stats = vkf::createBuffer(c, sizeof(Stats),
                              VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                  VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                  VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                              Device, "stats");
    commandBuffer = vkf::createBuffer(
        c, sizeof(VkDispatchIndirectCommand),
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, Device,
        "command");
    readback = vkf::createBuffer(c, sizeof(Stats), VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                 vkf::MemoryUse::Readback, "readback");

    generateSet = fieldSet(c, pool, generate, field.view, VK_NULL_HANDLE);
    blurSet = fieldSet(c, pool, blur, field.view, blurred);
    edgesSet = fieldSet(c, pool, edges, field.view, edgeBuffer);
    selectSet = u3::bufferSet(c, pool, select, {blurred, edgeBuffer, stats, list});
    commandSet = u3::bufferSet(c, pool, command, {stats, commandBuffer});
    scoreSet = u3::bufferSet(c, pool, score, {list, blurred, stats});
}

void Passes::record(VkCommandBuffer cmd) const {
    const uint32_t tiles = vkf::groupCount(side, 16);
    const uint32_t cells = side * side;
    vkCmdFillBuffer(cmd, stats, 0, VK_WHOLE_SIZE, 0);

    // snippet:begin before-generate
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
        .image = field,
        .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
    };
    const VkDependencyInfo beforeGenerate{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &toGeneral,
    };
    vkCmdPipelineBarrier2(cmd, &beforeGenerate);
    u3::dispatch(cmd, generate, generateSet, SeedPush{Seed}, tiles, tiles);
    // snippet:end before-generate

    // snippet:begin before-filters
    const VkMemoryBarrier2 fieldWritten{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
    };
    const VkDependencyInfo beforeFilters{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &fieldWritten,
    };
    vkCmdPipelineBarrier2(cmd, &beforeFilters);
    u3::dispatch(cmd, blur, blurSet, tiles, tiles);
    u3::dispatch(cmd, edges, edgesSet, tiles, tiles);
    // snippet:end before-filters

    // snippet:begin before-select
    const VkMemoryBarrier2 beforeSelect[] = {
        {
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
        },
        {
            .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
            .srcStageMask = VK_PIPELINE_STAGE_2_CLEAR_BIT,
            .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            .dstAccessMask =
                VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        },
    };
    const VkDependencyInfo selectDependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 2,
        .pMemoryBarriers = beforeSelect,
    };
    vkCmdPipelineBarrier2(cmd, &selectDependency);
    const SelectPush thresholds{cells, MinBlurred, MaxEdge};
    u3::dispatch(cmd, select, selectSet, thresholds, vkf::groupCount(cells, 256));
    // snippet:end before-select

    // snippet:begin before-command
    const VkMemoryBarrier2 selected{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .dstAccessMask =
            VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
    };
    const VkDependencyInfo beforeCommand{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &selected,
    };
    vkCmdPipelineBarrier2(cmd, &beforeCommand);
    u3::dispatch(cmd, command, commandSet, 1);
    // snippet:end before-command

    // snippet:begin before-score
    const VkMemoryBarrier2 commandWritten{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT,
        .dstAccessMask = VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT,
    };
    const VkDependencyInfo beforeScore{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &commandWritten,
    };
    vkCmdPipelineBarrier2(cmd, &beforeScore);
    u3::bind(cmd, score, scoreSet);
    vkCmdDispatchIndirect(cmd, commandBuffer, 0);
    // snippet:end before-score

    // snippet:begin readback
    const VkMemoryBarrier2 scored{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
        .dstAccessMask = VK_ACCESS_2_TRANSFER_READ_BIT,
    };
    const VkDependencyInfo beforeCopy{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &scored,
    };
    vkCmdPipelineBarrier2(cmd, &beforeCopy);
    const VkBufferCopy region{.size = sizeof(Stats)};
    vkCmdCopyBuffer(cmd, stats, readback, 1, &region);
    const VkMemoryBarrier2 copied{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
        .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT,
        .dstAccessMask = VK_ACCESS_2_HOST_READ_BIT,
    };
    const VkDependencyInfo afterCopy{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &copied,
    };
    vkCmdPipelineBarrier2(cmd, &afterCopy);
    // snippet:end readback
}

bool runPipeline(const vkf::Context& ctx, uint32_t side, int repeats) {
    Passes passes(ctx, side);
    vkf::GpuTimer timer(ctx, 2);
    std::vector<double> samples;
    for (int r = 0; r <= repeats; ++r) {
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            timer.reset(cmd);
            timer.stamp(cmd);
            passes.record(cmd);
            timer.stamp(cmd);
        });
        if (r > 0) samples.push_back(timer.read()[1]);
    }
    passes.readback.invalidate();
    const Stats got = *passes.readback.data<Stats>();
    const Stats want = reference(side);
    const bool ok = got.selected == want.selected && got.blurredSum == want.blurredSum &&
                    got.indexXor == want.indexXor;
    vkf::print("pipeline: {0}x{0} field, 7 passes, 7 vkCmdPipelineBarrier2 calls\n", side);
    vkf::print("  GPU: {} cells selected, blurred sum {}, index xor {:#010x}\n", got.selected,
               got.blurredSum, got.indexXor);
    vkf::print("  CPU: {} cells selected, blurred sum {}, index xor {:#010x}\n", want.selected,
               want.blurredSum, want.indexXor);
    vkf::print("  GPU time {:.3f} ms, median of {} runs\n", vkf::summarize(samples).median,
               repeats);
    return ok;
}

enum class Barrier { None, Precise, Full };

// snippet:begin cost-record
void recordSteps(VkCommandBuffer cmd, const u3::Kernel& step, VkDescriptorSet set,
                 uint32_t dispatches, uint32_t elements, bool chain, Barrier barrier) {
    const VkMemoryBarrier2 precise{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .dstAccessMask =
            VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
    };
    const VkMemoryBarrier2 full{
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .srcAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = barrier == Barrier::Full ? &full : &precise,
    };
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, step.pipeline);
    const StepPush push{elements};
    vkCmdPushConstants(cmd, step.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    for (uint32_t d = 0; d < dispatches; ++d) {
        if (d > 0 && barrier != Barrier::None) vkCmdPipelineBarrier2(cmd, &dependency);
        const uint32_t offset = chain ? 0 : d * elements * 4;
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, step.layout, 0, 1, &set,
                                1, &offset);
        vkCmdDispatch(cmd, vkf::groupCount(elements, 256), 1, 1);
    }
}
// snippet:end cost-record

constexpr uint32_t lcg(uint32_t x) {
    return x * 1664525u + 1013904223u;
}

struct Sequence {
    const char* name;
    const char* barrier;
    bool chain;
    Barrier kind;
};

struct CostResult {
    double medianMs = 0;
    bool correct = false;
};

CostResult measure(const vkf::Context& ctx, const u3::Kernel& step, VkDescriptorSet set,
                   const vkf::Buffer& values, uint32_t dispatches, uint32_t elements,
                   const Sequence& sequence, int repeats) {
    const uint32_t total = dispatches * elements;
    std::vector<uint32_t> initial(total);
    for (uint32_t i = 0; i < total; ++i) initial[i] = i;
    vkf::upload(ctx, values, std::span<const uint32_t>(initial));

    vkf::GpuTimer timer(ctx, 2);
    VkCommandBuffer cmd = vkf::allocateCommandBuffer(ctx, ctx.commandPool());
    vkf::beginCommands(cmd, 0);
    timer.reset(cmd);
    timer.stamp(cmd);
    recordSteps(cmd, step, set, dispatches, elements, sequence.chain, sequence.kind);
    timer.stamp(cmd);
    vkf::endCommands(cmd);

    const auto fence = vkf::createFence(ctx);
    std::vector<double> samples;
    for (int r = 0; r <= repeats; ++r) {
        vkf::submit(ctx.mainQueue(), std::span(&cmd, 1), {}, {}, fence);
        vkf::waitFence(ctx, fence);
        VKF_CHECK(vkResetFences(ctx.device(), 1, fence.ptr()));
        if (r > 0) samples.push_back(timer.read()[1]);
    }
    vkFreeCommandBuffers(ctx.device(), ctx.commandPool(), 1, &cmd);

    const auto got = vkf::download<uint32_t>(ctx, values, total);
    const uint32_t runs = uint32_t(repeats) + 1;
    bool correct = true;
    for (uint32_t i = 0; i < total && correct; ++i) {
        uint32_t want = initial[i];
        const uint32_t steps = sequence.chain ? (i < elements ? runs * dispatches : 0) : runs;
        for (uint32_t s = 0; s < steps; ++s) want = lcg(want);
        correct = got[i] == want;
    }
    return {vkf::summarize(samples).median, correct};
}

bool runCost(const vkf::Context& ctx, uint32_t dispatches, uint32_t elements, int repeats) {
    vkf::DescriptorPool pool(ctx);
    const u3::Kernel step = u3::makeKernel(
        ctx, "step.comp", {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC}, sizeof(StepPush));
    const vkf::Buffer values = vkf::createBuffer(ctx, VkDeviceSize(dispatches) * elements * 4,
                                                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                                 vkf::MemoryUse::DeviceLocal, "values");
    // A dynamic offset per dispatch shows validation which slice each dispatch touches.
    const VkDescriptorSet set = pool.allocate(step.setLayout);
    vkf::DescriptorWriter()
        .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, values, 0,
                VkDeviceSize(elements) * 4)
        .update(ctx, set);

    const Sequence sequences[] = {
        {"chain", "COMPUTE write -> COMPUTE read/write", true, Barrier::Precise},
        {"chain", "ALL_COMMANDS -> ALL_COMMANDS", true, Barrier::Full},
        {"independent", "none", false, Barrier::None},
        {"independent", "COMPUTE write -> COMPUTE read/write", false, Barrier::Precise},
        {"independent", "ALL_COMMANDS -> ALL_COMMANDS", false, Barrier::Full},
    };
    vkf::print("cost: {} dispatches of {} elements, GPU time, median of {} runs\n", dispatches,
               elements, repeats);
    vkf::print("  {:<12}{:<38}{:>9}{:>10}{:>12}\n", "sequence", "barrier between dispatches",
               "barriers", "GPU ms", "us/dispatch");
    std::vector<double> ms;
    bool allCorrect = true;
    for (const Sequence& s : sequences) {
        const CostResult r = measure(ctx, step, set, values, dispatches, elements, s, repeats);
        ms.push_back(r.medianMs);
        allCorrect = allCorrect && r.correct;
        const uint32_t barriers = s.kind == Barrier::None ? 0 : dispatches - 1;
        vkf::print("  {:<12}{:<38}{:>9}{:>10.3f}{:>12.2f}{}\n", s.name, s.barrier, barriers,
                   r.medianMs, 1000.0 * r.medianMs / dispatches, r.correct ? "" : "  WRONG");
    }
    vkf::print("  (a) precise, only where needed: {:.3f} ms\n", ms[0] + ms[2]);
    vkf::print("  (b) full barrier after every dispatch: {:.3f} ms\n", ms[1] + ms[4]);
    vkf::print("  (c) independent set, no barriers vs precise ones: {:.3f} vs {:.3f} ms\n",
               ms[2], ms[3]);
    return allCorrect;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const std::string part = args.text("--part", "all");
        const auto side = uint32_t(args.integer("--side", 512));
        const auto dispatches = uint32_t(args.integer("--dispatches", 256));
        const auto elements = uint32_t(args.integer("--elements", 16384));
        const auto repeats = int(args.integer("--repeats", 10));
        vkf::Context ctx({.appName = "u3_passes"});

        bool ok = true;
        if (part == "all" || part == "pipeline") ok = runPipeline(ctx, side, repeats) && ok;
        if (part == "all" || part == "cost") {
            ok = runCost(ctx, dispatches, elements, repeats) && ok;
        }
        if (!ok) throw std::runtime_error("results differ from the CPU reference");
        vkf::print("PASS\n");
    });
}
