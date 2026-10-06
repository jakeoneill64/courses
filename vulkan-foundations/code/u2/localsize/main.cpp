#include <vkf/vkf.hpp>

#include <algorithm>
#include <cmath>
#include <format>
#include <random>
#include <span>
#include <vector>

#include "u2.hpp"

namespace {

struct SaxpyPush {
    float a;
    uint32_t n;
};

struct ChainPush {
    float a;
    float b;
    uint32_t n;
};

constexpr uint32_t chain = 512;  // must equal CHAIN in fma_chain.comp

// snippet:begin verify
double saxpyError(std::span<const float> z, std::span<const float> x, std::span<const float> y,
                  float a) {
    double worst = 0;
    for (size_t i = 0; i < z.size(); ++i) {
        const double expected = double(a) * x[i] + y[i];
        worst =
            std::max(worst, std::abs(z[i] - expected) / std::max(1e-30, std::abs(expected)));
    }
    return worst;
}

double chainError(std::span<const float> z, std::span<const float> x, ChainPush p) {
    const double scale = std::pow(double(p.a), chain);
    const double offset = double(p.b) * (1 - scale) / (1 - double(p.a));
    double worst = 0;
    for (size_t i = 0; i < z.size(); ++i) {
        worst = std::max(worst, std::abs(z[i] - (scale * x[i] + offset)));
    }
    return worst;
}
// snippet:end verify

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 1 << 24));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        vkf::Context ctx({.appName = "u2_localsize"});
        const VkPhysicalDeviceLimits& limits = ctx.properties().core.limits;

        std::vector<float> x(n), y(n);
        std::mt19937 rng(42);
        std::uniform_real_distribution<float> uniform(0.0f, 1.0f);
        for (uint32_t i = 0; i < n; ++i) {
            x[i] = uniform(rng);
            y[i] = uniform(rng);
        }
        const VkDeviceSize bytes = VkDeviceSize(n) * sizeof(float);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        vkf::Buffer xBuffer =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "x");
        vkf::Buffer yBuffer =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "y");
        vkf::Buffer zBuffer =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "z");
        vkf::upload(ctx, xBuffer, std::span<const float>(x));
        vkf::upload(ctx, yBuffer, std::span<const float>(y));

        auto setLayout = u2::storageBufferLayout(ctx, 3);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ChainPush)};
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet set = pool.allocate(setLayout, "x y z");
        u2::writeStorageBuffers(ctx, set, {xBuffer, yBuffer, zBuffer});

        const SaxpyPush saxpy{0.5f, n};
        const ChainPush fmaChain{0.999f, 0.001f, n};
        auto record = [&](VkCommandBuffer cmd, VkPipeline pipeline, const void* push,
                          uint32_t pushBytes, uint32_t groups) {
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                    nullptr);
            vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, pushBytes, push);
            vkCmdDispatch(cmd, groups, 1, 1);
        };

        vkf::print(
            "SAXPY over {} floats ({} MiB moved per run); an FMA chain of {} per float\n", n,
            3 * bytes >> 20, chain);
        vkf::print("median of {} runs after a 25 ms warm-up\n\n", runs);
        vkf::print("local size   SAXPY ms     GB/s   FMA chain ms    GFLOP/s   results\n");

        const uint32_t largest =
            std::min(limits.maxComputeWorkGroupInvocations, limits.maxComputeWorkGroupSize[0]);
        uint32_t sizes = 0, verified = 0;
        for (uint32_t local = 32; local <= largest; local *= 2) {
            // snippet:begin sweep
            vkf::Specialization spec;
            spec.set(0, local);
            auto saxpyPipeline = u2::loadPipeline(ctx, layout, "saxpy.comp", spec);
            auto chainPipeline = u2::loadPipeline(ctx, layout, "fma_chain.comp", spec);
            const uint32_t groups =
                std::min(vkf::groupCount(n, local), limits.maxComputeWorkGroupCount[0]);

            const vkf::Stats saxpyMs = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                record(cmd, saxpyPipeline, &saxpy, sizeof(saxpy), groups);
            });
            const std::vector<float> saxpyOut = vkf::download<float>(ctx, zBuffer, n);
            const vkf::Stats chainMs = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                record(cmd, chainPipeline, &fmaChain, sizeof(fmaChain), groups);
            });
            const std::vector<float> chainOut = vkf::download<float>(ctx, zBuffer, n);
            // snippet:end sweep

            const bool ok = saxpyError(saxpyOut, x, y, saxpy.a) < 1e-6 &&
                            chainError(chainOut, x, fmaChain) < 1e-4;
            ++sizes;
            verified += ok ? 1 : 0;
            const double flops = 2.0 * chain * n;
            vkf::print("{:>10} {:>10.3f} {:>8.1f} {:>14.3f} {:>10.1f}   {}\n", local,
                       saxpyMs.median, u2::gbPerSecond(3.0 * bytes, saxpyMs.median),
                       chainMs.median, flops / (chainMs.median * 1e6), ok ? "ok" : "WRONG");
        }
        u2::finish(verified == sizes,
                   std::format("localsize: {} of {} local sizes verified", verified, sizes));
    });
}
