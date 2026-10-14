#include <vkf/vkf.hpp>

#include <cmath>
#include <format>
#include <numeric>
#include <random>
#include <span>
#include <stdexcept>
#include <vector>

#include "reduction.hpp"
#include "u2.hpp"

namespace {

struct Variant {
    const char* label;
    const char* shader;
    uint32_t items;
    bool subgroups;
};

const Variant variants[] = {
    {"interleaved addressing", "interleaved.comp", 1, false},
    {"sequential addressing", "sequential.comp", 1, false},
    {"subgroupAdd, 1 per invocation", "subgroup.comp", 1, true},
    {"8 elements per invocation", "coarse.comp", 8, false},
    {"subgroupAdd, 8 per invocation", "subgroup.comp", 8, true},
};

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 1 << 24));
        const auto localSize = static_cast<uint32_t>(args.integer("--local", 512));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        const double tolerance = 1e-5;
        if (n == 0) throw std::runtime_error("--n must be positive");
        vkf::Context ctx({.appName = "u2_reduce"});
        const VkPhysicalDeviceLimits& limits = ctx.properties().core.limits;
        if (localSize > limits.maxComputeWorkGroupInvocations) {
            throw std::runtime_error("--local exceeds maxComputeWorkGroupInvocations");
        }

        // snippet:begin reference
        std::vector<float> input(n);
        std::mt19937 rng(5);
        std::uniform_real_distribution<float> uniform(0.0f, 1.0f);
        for (float& v : input) v = uniform(rng);
        const double expected = std::accumulate(input.begin(), input.end(), 0.0);
        // snippet:end reference

        const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(float);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        vkf::Buffer source =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "input");
        const VkDeviceSize partialBytes = vkf::groupCount(n, localSize) * sizeof(float);
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

        vkf::print("sum of {} floats ({} MiB), local size {}; median of {} runs\n", n,
                   bytes >> 20, localSize, runs);
        vkf::print("double-precision CPU sum {:.3f}\n\n", expected);
        vkf::print("{:<32}{:>7}{:>9}{:>9}   relative error\n", "variant", "passes", "ms",
                   "GB/s");
        const bool subgroupArithmetic = u2::subgroupSupports(
            ctx, VK_SUBGROUP_FEATURE_BASIC_BIT | VK_SUBGROUP_FEATURE_ARITHMETIC_BIT);
        int passed = 0, attempted = 0;
        for (const Variant& variant : variants) {
            if (variant.subgroups && !subgroupArithmetic) {
                vkf::print("{:<32}skipped: no subgroup arithmetic in compute shaders\n",
                           variant.label);
                continue;
            }
            ++attempted;
            vkf::Specialization spec;
            spec.set(0, localSize).set(1, variant.items);
            auto pipeline = u2::loadPipeline(ctx, layout, variant.shader, spec);
            const std::vector<u2::ReducePass> passes =
                u2::planReduction(n, localSize * variant.items, inputToA, aToB, bToA);
            if (passes.front().groups > limits.maxComputeWorkGroupCount[0]) {
                throw std::runtime_error("--n needs more workgroups than this device allows");
            }

            const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                u2::recordReduction(cmd, pipeline, layout, passes);
            });

            const vkf::Buffer& last = passes.size() % 2 ? a : b;
            const float sum = vkf::download<float>(ctx, last, 1)[0];
            const double error = std::abs(sum - expected) / expected;
            const bool ok = error < tolerance;
            passed += ok ? 1 : 0;
            vkf::print("{:<32}{:>7}{:>9.3f}{:>9.1f}   {:.1e} {}\n", variant.label,
                       passes.size(), ms.median, u2::gbPerSecond(double(bytes), ms.median),
                       error, ok ? "ok" : "WRONG");
        }
        u2::finish(passed == attempted,
                   std::format("reduce: {} of {} sums within {:.0e} of the CPU sum", passed,
                               attempted, tolerance));
    });
}
