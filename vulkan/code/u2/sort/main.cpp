#include <vkf/vkf.hpp>

#include <algorithm>
#include <random>
#include <span>
#include <stdexcept>
#include <vector>

#include "scan.hpp"
#include "u2.hpp"

namespace {

constexpr uint32_t localSize = 256;
constexpr uint32_t items = 4;      // must equal ITEMS in sort.glsl
constexpr uint32_t digitBits = 4;  // must equal DIGIT_BITS in sort.glsl
constexpr uint32_t buckets = 1u << digitBits;
constexpr uint32_t scanItems = 4;  // must equal ITEMS in scan_blocks.comp

struct Push {
    uint32_t count;
    uint32_t shift;
    uint32_t blocks;
};

struct Pair {
    uint32_t key;
    uint32_t value;
};

// The murmur3 finaliser is a bijection, so it spreads keys over 32 bits and keeps duplicates.
uint32_t mix(uint32_t x) {
    x ^= x >> 16;
    x *= 0x85ebca6bu;
    x ^= x >> 13;
    x *= 0xc2b2ae35u;
    return x ^ (x >> 16);
}

void dispatch(VkCommandBuffer cmd, VkPipeline pipeline, VkPipelineLayout layout,
              VkDescriptorSet set, const Push& push, uint32_t groups) {
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                            nullptr);
    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    vkCmdDispatch(cmd, groups, 1, 1);
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 1 << 22));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        if (n < 2) throw std::runtime_error("--n must be at least 2");
        vkf::Context ctx({.appName = "u2_sort"});
        if (!u2::subgroupSupports(
                ctx, VK_SUBGROUP_FEATURE_BASIC_BIT | VK_SUBGROUP_FEATURE_ARITHMETIC_BIT)) {
            throw std::runtime_error("u2_sort needs subgroup arithmetic in compute shaders");
        }
        const uint32_t blocks = vkf::groupCount(n, localSize * items);
        if (blocks > ctx.properties().core.limits.maxComputeWorkGroupCount[0]) {
            throw std::runtime_error("--n needs more workgroups than this device allows");
        }

        std::vector<uint32_t> keys(n), values(n);
        std::mt19937 rng(17);
        std::uniform_int_distribution<uint32_t> pick(0, n / 2);
        for (uint32_t i = 0; i < n; ++i) {
            keys[i] = mix(pick(rng));
            values[i] = i;
        }

        const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(uint32_t);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        auto buffer = [&](VkDeviceSize size, const char* name) {
            return vkf::createBuffer(ctx, size, usage, vkf::MemoryUse::DeviceLocal, name);
        };
        vkf::Buffer inKeys = buffer(bytes, "input keys"),
                    inValues = buffer(bytes, "input values");
        vkf::Buffer aKeys = buffer(bytes, "keys a"), aValues = buffer(bytes, "values a");
        vkf::Buffer bKeys = buffer(bytes, "keys b"), bValues = buffer(bytes, "values b");
        const VkDeviceSize tableBytes = VkDeviceSize(buckets) * blocks * sizeof(uint32_t);
        vkf::Buffer counts = buffer(tableBytes, "digit counts");
        vkf::Buffer offsets = buffer(tableBytes, "digit offsets");
        vkf::upload(ctx, inKeys, std::span<const uint32_t>(keys));
        vkf::upload(ctx, inValues, std::span<const uint32_t>(values));

        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
        auto countSetLayout = u2::storageBufferLayout(ctx, 2);
        auto scatterSetLayout = u2::storageBufferLayout(ctx, 6);
        auto countLayout = vkf::createPipelineLayout(ctx, {countSetLayout.get()}, {range});
        auto scatterLayout = vkf::createPipelineLayout(ctx, {scatterSetLayout.get()}, {range});
        vkf::Specialization spec;
        spec.set(0, localSize);
        const VkPipelineShaderStageCreateFlags full = u2::fullSubgroups(ctx, localSize);
        auto countPipeline = u2::loadPipeline(ctx, countLayout, "sort_count.comp", spec);
        auto scatterPipeline =
            u2::loadPipeline(ctx, scatterLayout, "sort_scatter.comp", spec, full);

        vkf::DescriptorPool pool(ctx);
        const auto scanKernels =
            u2::loadScanKernels(ctx, "scan_blocks.comp", localSize, scanItems, full);
        const u2::MultiLevelScan scan(ctx, scanKernels, pool, counts, offsets,
                                      buckets * blocks);

        // snippet:begin ping-pong
        const VkBuffer sourceKeys[] = {inKeys, aKeys, bKeys};
        const VkBuffer sourceValues[] = {inValues, aValues, bValues};
        const VkBuffer targetKeys[] = {aKeys, bKeys, aKeys};
        const VkBuffer targetValues[] = {aValues, bValues, aValues};
        VkDescriptorSet countSets[3], scatterSets[3];
        for (int s = 0; s < 3; ++s) {
            countSets[s] = pool.allocate(countSetLayout, "count");
            u2::writeStorageBuffers(ctx, countSets[s], {sourceKeys[s], counts});
            scatterSets[s] = pool.allocate(scatterSetLayout, "scatter");
            u2::writeStorageBuffers(ctx, scatterSets[s],
                                    {sourceKeys[s], sourceValues[s], targetKeys[s],
                                     targetValues[s], counts, offsets});
        }
        // snippet:end ping-pong

        // snippet:begin passes
        const uint32_t passes = 32 / digitBits;
        auto sort = [&](VkCommandBuffer cmd) {
            for (uint32_t pass = 0; pass < passes; ++pass) {
                const int s = pass == 0 ? 0 : pass % 2 == 1 ? 1 : 2;
                const Push push{n, pass * digitBits, blocks};
                dispatch(cmd, countPipeline, countLayout, countSets[s], push, blocks);
                u2::computeBarrier(cmd);
                scan.record(cmd);
                dispatch(cmd, scatterPipeline, scatterLayout, scatterSets[s], push, blocks);
                u2::computeBarrier(cmd);
            }
        };
        // snippet:end passes
        const vkf::Stats gpuMs = u2::timeGpu(ctx, runs, sort);
        const vkf::Buffer& sortedKeys = passes % 2 == 1 ? aKeys : bKeys;
        const vkf::Buffer& sortedValues = passes % 2 == 1 ? aValues : bValues;
        const std::vector<uint32_t> gpuKeys = vkf::download<uint32_t>(ctx, sortedKeys, n);
        const std::vector<uint32_t> gpuValues = vkf::download<uint32_t>(ctx, sortedValues, n);

        // snippet:begin verify
        std::vector<Pair> pairs(n);
        for (uint32_t i = 0; i < n; ++i) pairs[i] = {keys[i], values[i]};
        vkf::CpuTimer stableTimer;
        std::stable_sort(pairs.begin(), pairs.end(),
                         [](const Pair& x, const Pair& y) { return x.key < y.key; });
        const double stableMs = stableTimer.elapsedMs();
        bool exact = true;
        for (uint32_t i = 0; i < n; ++i) {
            exact = exact && gpuKeys[i] == pairs[i].key && gpuValues[i] == pairs[i].value;
        }
        // snippet:end verify
        std::vector<uint32_t> cpuKeys = keys;
        vkf::CpuTimer sortTimer;
        std::sort(cpuKeys.begin(), cpuKeys.end());
        const double sortMs = sortTimer.elapsedMs();
        uint32_t repeats = 0;
        for (uint32_t i = 1; i < n; ++i) repeats += pairs[i].key == pairs[i - 1].key ? 1 : 0;

        vkf::print("LSD radix sort of {} key-value pairs: {}-bit digits, {} passes\n", n,
                   digitBits, passes);
        vkf::print("{} keys repeat an earlier key, so their values test stability\n\n",
                   repeats);
        const double gpuRate = n / (gpuMs.median * 1e3);
        vkf::print("{:<32}{:>10.3f} ms {:>8.1f} M pairs/s\n", "GPU radix sort (median)",
                   gpuMs.median, gpuRate);
        vkf::print("{:<32}{:>10.3f} ms {:>8.1f} M keys/s\n", "std::sort, keys only", sortMs,
                   n / (sortMs * 1e3));
        vkf::print("{:<32}{:>10.3f} ms {:>8.1f} M pairs/s\n", "std::stable_sort, pairs",
                   stableMs, n / (stableMs * 1e3));
        u2::finish(exact && cpuKeys == gpuKeys,
                   "sort: the GPU pairs match std::stable_sort exactly");
    });
}
