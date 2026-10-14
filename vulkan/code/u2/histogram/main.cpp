#include <vkf/vkf.hpp>

#include <algorithm>
#include <array>
#include <format>
#include <random>
#include <span>
#include <vector>

#include "u2.hpp"

namespace {

struct Push {
    uint32_t words;
};

constexpr uint32_t binCount = 256;
constexpr uint32_t localSize = 256;  // must equal local_size_x in the shaders
constexpr uint32_t wordsPerInvocation = 16;

// snippet:begin reference
std::array<uint32_t, binCount> histogram(std::span<const uint32_t> words) {
    std::array<uint32_t, binCount> counts{};
    for (uint32_t word : words) {
        for (int byte = 0; byte < 4; ++byte) ++counts[(word >> (8 * byte)) & 0xFF];
    }
    return counts;
}
// snippet:end reference

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto mib = static_cast<uint32_t>(args.integer("--mib", 64));
        const auto runs = static_cast<int>(args.integer("--runs", 10));
        if (mib == 0 || mib > 1024) {
            throw std::runtime_error("--mib must be between 1 and 1024");
        }
        vkf::Context ctx({.appName = "u2_histogram"});

        const uint32_t words = mib * (1u << 20) / 4;
        std::vector<uint32_t> uniform(words);
        std::mt19937 rng(3);
        for (uint32_t& w : uniform) w = rng();
        const std::vector<uint32_t> identical(words, 0x2A2A2A2Au);

        const VkDeviceSize bytes = VkDeviceSize(words) * 4;
        vkf::Buffer data = vkf::createBuffer(
            ctx, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            vkf::MemoryUse::DeviceLocal, "data");
        vkf::Buffer bins = vkf::createBuffer(ctx, binCount * 4,
                                             VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                                 VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                                 VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                             vkf::MemoryUse::DeviceLocal, "bins");

        auto setLayout = u2::storageBufferLayout(ctx, 2);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(Push)};
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet set = pool.allocate(setLayout, "data bins");
        u2::writeStorageBuffers(ctx, set, {data, bins});
        const std::pair<const char*, vkf::Unique<VkPipeline>> kernels[] = {
            {"global atomics", u2::loadPipeline(ctx, layout, "global.comp")},
            {"shared, then global", u2::loadPipeline(ctx, layout, "shared.comp")},
        };
        const uint32_t groups =
            std::min(vkf::groupCount(words, localSize * wordsPerInvocation),
                     ctx.properties().core.limits.maxComputeWorkGroupCount[0]);

        vkf::print("{} MiB of bytes, {} bins, {} workgroups; median of {} runs\n\n", mib,
                   binCount, groups, runs);
        vkf::print("{:<15}{:<22}{:>9}{:>9}   bins\n", "input", "kernel", "ms", "GB/s");
        int exact = 0, total = 0;
        const std::pair<const char*, const std::vector<uint32_t>*> inputs[] = {
            {"uniform", &uniform},
            {"all identical", &identical},
        };
        for (const auto& [inputName, input] : inputs) {
            vkf::upload(ctx, data, std::span<const uint32_t>(*input));
            const std::array<uint32_t, binCount> expected = histogram(*input);
            for (const auto& [kernelName, pipeline] : kernels) {
                // snippet:begin run
                const Push push{words};
                const vkf::Stats ms = u2::timeGpu(ctx, runs, [&](VkCommandBuffer cmd) {
                    vkCmdFillBuffer(cmd, bins, 0, VK_WHOLE_SIZE, 0);
                    vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_CLEAR_BIT,
                                       VK_ACCESS_2_TRANSFER_WRITE_BIT,
                                       VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                                       VK_ACCESS_2_SHADER_STORAGE_READ_BIT |
                                           VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
                    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
                    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1,
                                            &set, 0, nullptr);
                    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                       sizeof(push), &push);
                    vkCmdDispatch(cmd, groups, 1, 1);
                });
                // snippet:end run
                const auto result = vkf::download<uint32_t>(ctx, bins, binCount);
                const bool ok = std::equal(result.begin(), result.end(), expected.begin());
                exact += ok ? 1 : 0;
                ++total;
                vkf::print("{:<15}{:<22}{:>9.3f}{:>9.1f}   {}\n", inputName, kernelName,
                           ms.median, u2::gbPerSecond(double(bytes), ms.median),
                           ok ? "exact" : "WRONG");
            }
        }
        u2::finish(exact == total,
                   std::format("histogram: {} of {} histograms exact", exact, total));
    });
}
