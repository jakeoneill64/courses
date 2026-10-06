#include <vkf/vkf.hpp>

#include <algorithm>
#include <cmath>
#include <format>
#include <numeric>
#include <random>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "reduction.hpp"
#include "u2.hpp"

namespace {

struct Variant {
    uint32_t localSize;
    uint32_t items;
    uint32_t subgroupSize;
    vkf::Unique<VkPipeline> pipeline;
    double ms = 0;
    bool correct = false;
};

// snippet:begin cache
vkf::Unique<VkPipelineCache> createCache(const vkf::Context& ctx,
                                         const std::vector<char>& data) {
    const VkPipelineCacheCreateInfo info{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
        .initialDataSize = data.size(),
        .pInitialData = data.data(),
    };
    VkPipelineCache cache = VK_NULL_HANDLE;
    VKF_CHECK(vkCreatePipelineCache(ctx.device(), &info, nullptr, &cache));
    return {ctx.device(), cache};
}

std::vector<char> cacheData(const vkf::Context& ctx, VkPipelineCache cache) {
    size_t size = 0;
    VKF_CHECK(vkGetPipelineCacheData(ctx.device(), cache, &size, nullptr));
    std::vector<char> data(size);
    VKF_CHECK(vkGetPipelineCacheData(ctx.device(), cache, &size, data.data()));
    data.resize(size);
    return data;
}
// snippet:end cache

// snippet:begin subgroup-sizes
std::vector<uint32_t> requiredSubgroupSizes(const vkf::Context& ctx) {
    const VkPhysicalDeviceVulkan13Properties& p = ctx.properties().v13;
    if (!ctx.features().v13.subgroupSizeControl ||
        (p.requiredSubgroupSizeStages & VK_SHADER_STAGE_COMPUTE_BIT) == 0) {
        return {0};
    }
    std::vector<uint32_t> sizes;
    for (uint32_t size = p.minSubgroupSize; size <= p.maxSubgroupSize; size *= 2) {
        sizes.push_back(size);
    }
    return sizes;
}
// snippet:end subgroup-sizes

// snippet:begin build
vkf::Unique<VkPipeline> build(const vkf::Context& ctx, VkPipelineLayout layout,
                              VkShaderModule module, VkPipelineCache cache, const Variant& v) {
    vkf::Specialization spec;
    spec.set(0, v.localSize).set(1, v.items);
    return vkf::createComputePipeline(ctx, {.layout = layout,
                                            .module = module,
                                            .specialization = spec.info(),
                                            .requiredSubgroupSize = v.subgroupSize,
                                            .cache = cache});
}
// snippet:end build

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 1 << 24));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        if (n == 0) throw std::runtime_error("--n must be positive");
        vkf::Context ctx({.appName = "u2_tune"});
        if (!u2::subgroupSupports(
                ctx, VK_SUBGROUP_FEATURE_BASIC_BIT | VK_SUBGROUP_FEATURE_ARITHMETIC_BIT)) {
            throw std::runtime_error("u2_tune needs subgroup arithmetic in compute shaders");
        }
        const VkPhysicalDeviceLimits& limits = ctx.properties().core.limits;
        const VkPhysicalDeviceVulkan13Properties& v13 = ctx.properties().v13;

        std::vector<float> input(n);
        std::mt19937 rng(5);
        std::uniform_real_distribution<float> uniform(0.0f, 1.0f);
        for (float& v : input) v = uniform(rng);
        const double expected = std::accumulate(input.begin(), input.end(), 0.0);
        const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(float);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        vkf::Buffer source =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "input");
        const VkDeviceSize partialBytes = vkf::groupCount(n, 64) * sizeof(float);
        vkf::Buffer a =
            vkf::createBuffer(ctx, partialBytes, usage, vkf::MemoryUse::DeviceLocal, "a");
        vkf::Buffer b =
            vkf::createBuffer(ctx, partialBytes, usage, vkf::MemoryUse::DeviceLocal, "b");
        vkf::upload(ctx, source, std::span<const float>(input));
        auto setLayout = u2::storageBufferLayout(ctx, 2);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                        sizeof(u2::ReducePush)};
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet inputToA = pool.allocate(setLayout, "input to a");
        VkDescriptorSet aToB = pool.allocate(setLayout, "a to b");
        VkDescriptorSet bToA = pool.allocate(setLayout, "b to a");
        u2::writeStorageBuffers(ctx, inputToA, {source, a});
        u2::writeStorageBuffers(ctx, aToB, {a, b});
        u2::writeStorageBuffers(ctx, bToA, {b, a});

        const std::vector<uint32_t> subgroupSizes = requiredSubgroupSizes(ctx);
        if (subgroupSizes.front() == 0) {
            vkf::print(
                "subgroup size control: requiredSubgroupSizeStages lacks the compute "
                "stage,\nso every variant runs at the driver's subgroup size\n");
        }
        // snippet:begin variants
        std::vector<Variant> variants;
        for (uint32_t subgroupSize : subgroupSizes) {
            for (uint32_t localSize = 64; localSize <= limits.maxComputeWorkGroupInvocations;
                 localSize *= 2) {
                const bool fits = subgroupSize == 0 ||
                                  localSize <= subgroupSize * v13.maxComputeWorkgroupSubgroups;
                for (uint32_t items = 1; items <= 32 && fits; items *= 2) {
                    variants.push_back({localSize, items, subgroupSize});
                }
            }
        }
        // snippet:end variants

        // snippet:begin cold-warm
        const auto module = vkf::loadShader(ctx, vkf::shaderPath("subgroup.comp"));
        auto coldCache = createCache(ctx, {});
        vkf::CpuTimer timer;
        for (Variant& v : variants) v.pipeline = build(ctx, layout, module, coldCache, v);
        const double coldMs = timer.elapsedMs();
        const std::vector<char> data = cacheData(ctx, coldCache);
        auto warmCache = createCache(ctx, data);
        timer.restart();
        for (Variant& v : variants) v.pipeline = build(ctx, layout, module, warmCache, v);
        const double warmMs = timer.elapsedMs();
        // snippet:end cold-warm
        vkf::print(
            "built {} pipelines in {:.1f} ms with an empty pipeline cache, and in {:.1f} "
            "ms\nfrom the {} bytes that cache then held\n\n",
            variants.size(), coldMs, warmMs, data.size());

        // snippet:begin measure
        for (Variant& v : variants) {
            const std::vector<u2::ReducePass> passes =
                u2::planReduction(n, v.localSize * v.items, inputToA, aToB, bToA);
            if (passes.front().groups > limits.maxComputeWorkGroupCount[0]) continue;
            v.ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                       u2::recordReduction(cmd, v.pipeline, layout, passes);
                   }).median;
            const float sum = vkf::download<float>(ctx, passes.size() % 2 ? a : b, 1)[0];
            v.correct = std::abs(sum - expected) / expected < 1e-5;
        }
        // snippet:end measure

        const Variant* best = nullptr;
        int correct = 0, measured = 0;
        for (const Variant& v : variants) {
            if (v.ms == 0) continue;
            ++measured;
            correct += v.correct ? 1 : 0;
            if (v.correct && (best == nullptr || v.ms < best->ms)) best = &v;
        }
        for (uint32_t subgroupSize : subgroupSizes) {
            if (subgroupSize != 0) vkf::print("required subgroup size {}\n", subgroupSize);
            vkf::print("GB/s by local size (columns) and elements per invocation (rows)\n");
            vkf::print("{:>5}", "");
            for (uint32_t size = 64; size <= limits.maxComputeWorkGroupInvocations;
                 size *= 2) {
                vkf::print("{:>8}", size);
            }
            vkf::print("\n");
            for (uint32_t items = 1; items <= 32; items *= 2) {
                vkf::print("{:>5}", items);
                for (const Variant& v : variants) {
                    if (v.items != items || v.subgroupSize != subgroupSize) continue;
                    if (v.ms == 0) {
                        vkf::print("{:>8}", "-");
                    } else {
                        vkf::print("{:>8.1f}", u2::gbPerSecond(double(bytes), v.ms));
                    }
                }
                vkf::print("\n");
            }
        }
        if (best != nullptr) {
            vkf::print(
                "\nfastest: local size {}, {} elements per invocation{}: {:.3f} ms "
                "({:.1f} GB/s)\n",
                best->localSize, best->items,
                best->subgroupSize != 0 ? std::format(", subgroup size {}", best->subgroupSize)
                                        : std::string(),
                best->ms, u2::gbPerSecond(double(bytes), best->ms));
        }
        u2::finish(best != nullptr && correct == measured,
                   std::format("tune: {} of {} variants verified", correct, measured));
    });
}
