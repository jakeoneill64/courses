#include <vkf/vkf.hpp>

#include <algorithm>
#include <format>
#include <iterator>
#include <numeric>
#include <random>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "scan.hpp"
#include "u2.hpp"

namespace {

constexpr uint32_t localSize = 256;
constexpr uint32_t subgroupItems = 4;  // must equal ITEMS in scan_blocks.comp

struct Push {
    uint32_t count;
};

std::vector<uint32_t> exclusiveScan(std::span<const uint32_t> values) {
    std::vector<uint32_t> result(values.size());
    std::exclusive_scan(values.begin(), values.end(), result.begin(), 0u);
    return result;
}

void dispatch(VkCommandBuffer cmd, VkPipeline pipeline, VkPipelineLayout layout,
              VkDescriptorSet set, uint32_t count, uint32_t groups) {
    const Push push{count};
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                            nullptr);
    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    vkCmdDispatch(cmd, groups, 1, 1);
}

bool hillisSteele(const vkf::Context& ctx, vkf::DescriptorPool& pool, const vkf::Buffer& input,
                  const vkf::Buffer& output, std::span<const uint32_t> values) {
    const auto count = static_cast<uint32_t>(values.size());
    auto setLayout = u2::storageBufferLayout(ctx, 2);
    const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
    auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
    vkf::Specialization spec;
    spec.set(0, count);
    auto pipeline = u2::loadPipeline(ctx, layout, "hillis_steele.comp", spec);
    VkDescriptorSet set = pool.allocate(setLayout, "hillis-steele");
    u2::writeStorageBuffers(ctx, set, {input, output});
    vkf::submitNow(
        ctx, [&](VkCommandBuffer cmd) { dispatch(cmd, pipeline, layout, set, count, 1); });
    return vkf::download<uint32_t>(ctx, output, count) == exclusiveScan(values);
}

bool compact(const vkf::Context& ctx, vkf::DescriptorPool& pool,
             const u2::ScanKernels& kernels, std::span<const uint32_t> values, int runs) {
    const auto n = static_cast<uint32_t>(values.size());
    const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(uint32_t);
    const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    vkf::Buffer input =
        vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "values");
    vkf::Buffer flags =
        vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "flags");
    vkf::Buffer positions =
        vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "positions");
    vkf::Buffer kept =
        vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "kept");
    vkf::upload(ctx, input, values);

    const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
    auto flagsLayout = u2::storageBufferLayout(ctx, 2);
    auto scatterLayout = u2::storageBufferLayout(ctx, 4);
    auto flagsPipelineLayout = vkf::createPipelineLayout(ctx, {flagsLayout.get()}, {range});
    auto scatterPipelineLayout =
        vkf::createPipelineLayout(ctx, {scatterLayout.get()}, {range});
    vkf::Specialization spec;
    spec.set(0, localSize);
    auto flagsPipeline =
        u2::loadPipeline(ctx, flagsPipelineLayout, "compact_flags.comp", spec);
    auto scatterPipeline =
        u2::loadPipeline(ctx, scatterPipelineLayout, "compact_scatter.comp", spec);
    VkDescriptorSet flagsSet = pool.allocate(flagsLayout, "flags");
    VkDescriptorSet scatterSet = pool.allocate(scatterLayout, "scatter");
    u2::writeStorageBuffers(ctx, flagsSet, {input, flags});
    u2::writeStorageBuffers(ctx, scatterSet, {input, flags, positions, kept});
    const u2::MultiLevelScan scan(ctx, kernels, pool, flags, positions, n);
    const uint32_t groups = vkf::groupCount(n, localSize);

    // snippet:begin compact
    const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
        dispatch(cmd, flagsPipeline, flagsPipelineLayout, flagsSet, n, groups);
        u2::computeBarrier(cmd);
        scan.record(cmd);
        dispatch(cmd, scatterPipeline, scatterPipelineLayout, scatterSet, n, groups);
    });
    const uint32_t count = vkf::download<uint32_t>(ctx, scan.total(), 1)[0];
    // snippet:end compact

    std::vector<uint32_t> expected;
    std::copy_if(values.begin(), values.end(), std::back_inserter(expected),
                 [](uint32_t v) { return v % 3 == 0; });
    const bool ok = count == expected.size() &&
                    (count == 0 || vkf::download<uint32_t>(ctx, kept, count) == expected);
    vkf::print("flags, a {}-level scan and the scatter: {:.3f} ms\n", scan.levels(),
               ms.median);
    vkf::print("kept {} of {} values ({:.1f}%): {}\n", count, n, 100.0 * count / n,
               ok ? "exact" : "WRONG");
    return ok;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 1 << 22));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        const bool compaction = args.flag("--compact");
        if (n == 0) throw std::runtime_error("--n must be positive");
        vkf::Context ctx({.appName = "u2_scan"});
        const bool subgroups = u2::subgroupSupports(
            ctx, VK_SUBGROUP_FEATURE_BASIC_BIT | VK_SUBGROUP_FEATURE_ARITHMETIC_BIT);
        vkf::DescriptorPool pool(ctx);
        auto blellochKernels = u2::loadScanKernels(ctx, "blelloch.comp", localSize, 2);

        std::mt19937 rng(9);
        if (compaction) {
            std::vector<uint32_t> values(n);
            for (uint32_t& v : values) v = rng();
            vkf::print("stream compaction of {} values, keeping multiples of 3\n", n);
            const u2::ScanKernels kernels =
                subgroups
                    ? u2::loadScanKernels(ctx, "scan_blocks.comp", localSize, subgroupItems,
                                          u2::fullSubgroups(ctx, localSize))
                    : std::move(blellochKernels);
            const bool ok = compact(ctx, pool, kernels, values, runs);
            u2::finish(ok, "scan --compact: the kept values match std::copy_if");
            return;
        }

        std::vector<uint32_t> values(n);
        std::uniform_int_distribution<uint32_t> upTo15(0, 15);
        for (uint32_t& v : values) v = upTo15(rng);
        const std::vector<uint32_t> expected = exclusiveScan(values);
        const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(uint32_t);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        vkf::Buffer input =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "in");
        vkf::Buffer output =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "out");
        vkf::upload(ctx, input, std::span<const uint32_t>(values));

        int exact = 0, total = 0;
        const uint32_t oneGroup = std::min(
            n, std::min(1024u, ctx.properties().core.limits.maxComputeWorkGroupInvocations));
        const bool hsOk = hillisSteele(ctx, pool, input, output,
                                       std::span<const uint32_t>(values).first(oneGroup));
        exact += hsOk ? 1 : 0;
        ++total;
        vkf::print("Hillis-Steele scan of {} values in one workgroup: {}\n\n", oneGroup,
                   hsOk ? "exact" : "WRONG");

        vkf::print("exclusive scan of {} values; median of {} runs\n", n, runs);
        vkf::print("{:<30}{:>8}{:>9}{:>9}   result\n", "block scan", "levels", "ms", "GB/s");
        std::vector<std::pair<std::string, u2::ScanKernels>> methods;
        methods.emplace_back(std::format("Blelloch, blocks of {}", blellochKernels.blockSize),
                             std::move(blellochKernels));
        if (subgroups) {
            auto kernels =
                u2::loadScanKernels(ctx, "scan_blocks.comp", localSize, subgroupItems,
                                    u2::fullSubgroups(ctx, localSize));
            methods.emplace_back(std::format("subgroups, blocks of {}", kernels.blockSize),
                                 std::move(kernels));
        } else {
            vkf::print("subgroup scan skipped: no subgroup arithmetic in compute shaders\n");
        }
        for (const auto& [label, kernels] : methods) {
            // snippet:begin run
            const u2::MultiLevelScan scan(ctx, kernels, pool, input, output, n);
            const vkf::Stats ms =
                u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) { scan.record(cmd); });
            const bool ok = vkf::download<uint32_t>(ctx, output, n) == expected;
            // snippet:end run
            exact += ok ? 1 : 0;
            ++total;
            vkf::print("{:<30}{:>8}{:>9.3f}{:>9.1f}   {}\n", label, scan.levels(), ms.median,
                       u2::gbPerSecond(2.0 * bytes, ms.median), ok ? "exact" : "WRONG");
        }
        u2::finish(exact == total, std::format("scan: {} of {} scans exact", exact, total));
    });
}
