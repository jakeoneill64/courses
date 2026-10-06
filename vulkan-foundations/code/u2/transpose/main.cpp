#include <vkf/vkf.hpp>

#include <bit>
#include <format>
#include <random>
#include <span>
#include <stdexcept>
#include <vector>

#include "u2.hpp"

namespace {

struct Push {
    uint32_t n;
};

constexpr uint32_t tile = 32;  // must equal TILE in the shaders

// snippet:begin variants
struct Variant {
    const char* label;
    const char* shader;
    uint32_t pad;
    bool transposes;
};

const Variant variants[] = {
    {"copy (the bandwidth reference)", "copy.comp", 0, false},
    {"naive transpose", "naive.comp", 0, true},
    {"tiled in shared memory", "tiled.comp", 0, true},
    {"tiled, rows padded to 33 floats", "tiled.comp", 1, true},
};
// snippet:end variants

// snippet:begin verify
bool exact(std::span<const float> in, std::span<const float> out, uint32_t n,
           bool transposed) {
    for (size_t y = 0; y < n; ++y) {
        for (size_t x = 0; x < n; ++x) {
            const float expected = in[y * n + x];
            const float actual = transposed ? out[x * n + y] : out[y * n + x];
            if (std::bit_cast<uint32_t>(actual) != std::bit_cast<uint32_t>(expected)) {
                return false;
            }
        }
    }
    return true;
}
// snippet:end verify

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto n = static_cast<uint32_t>(args.integer("--n", 4096));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        if (n == 0 || n % tile != 0) {
            throw std::runtime_error("--n must be a positive multiple of 32");
        }
        vkf::Context ctx({.appName = "u2_transpose"});

        const size_t count = size_t(n) * n;
        std::vector<float> input(count);
        std::mt19937 rng(7);
        std::uniform_real_distribution<float> uniform(-1.0f, 1.0f);
        for (float& v : input) v = uniform(rng);
        const VkDeviceSize bytes = count * sizeof(float);
        const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        vkf::Buffer src =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "src");
        vkf::Buffer dst =
            vkf::createBuffer(ctx, bytes, usage, vkf::MemoryUse::DeviceLocal, "dst");
        vkf::upload(ctx, src, std::span<const float>(input));

        auto setLayout = u2::storageBufferLayout(ctx, 2);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet set = pool.allocate(setLayout, "src dst");
        u2::writeStorageBuffers(ctx, set, {src, dst});

        vkf::print("{} x {} floats ({} MiB); median of {} runs after a 25 ms warm-up\n\n", n,
                   n, bytes >> 20, runs);
        vkf::print("{:<34}{:>8}{:>9}   result\n", "kernel", "ms", "GB/s");
        int correct = 0;
        for (const Variant& variant : variants) {
            // snippet:begin run
            vkf::Specialization spec;
            spec.set(0, variant.pad);
            auto pipeline = u2::loadPipeline(ctx, layout, variant.shader, spec);
            const Push push{n};
            const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
                vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1,
                                        &set, 0, nullptr);
                vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push),
                                   &push);
                vkCmdDispatch(cmd, n / tile, n / tile, 1);
            });
            // snippet:end run
            const std::vector<float> output = vkf::download<float>(ctx, dst, count);
            const bool ok = exact(input, output, n, variant.transposes);
            correct += ok ? 1 : 0;
            vkf::print("{:<34}{:>8.3f}{:>9.1f}   {}\n", variant.label, ms.median,
                       u2::gbPerSecond(2.0 * bytes, ms.median), ok ? "exact" : "WRONG");
        }
        u2::finish(
            correct == std::size(variants),
            std::format("transpose: {} of {} results exact", correct, std::size(variants)));
    });
}
