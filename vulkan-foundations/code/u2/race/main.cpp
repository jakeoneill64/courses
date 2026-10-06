#include <vkf/vkf.hpp>

#include <format>
#include <random>
#include <span>
#include <vector>

#include "u2.hpp"

namespace {

constexpr uint32_t localSize = 256;  // must equal local_size_x in both shaders

uint32_t countRace(const vkf::Context& ctx, bool fix, uint32_t groups) {
    vkf::Buffer counter = vkf::createBuffer(ctx, sizeof(uint32_t),
                                            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                                VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                                VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                            vkf::MemoryUse::DeviceLocal, "counter");
    // snippet:begin bool-constant
    auto setLayout = u2::storageBufferLayout(ctx, 1);
    auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()});
    vkf::Specialization spec;
    spec.set(0, VkBool32(fix ? VK_TRUE : VK_FALSE));
    auto pipeline = u2::loadPipeline(ctx, layout, "counter.comp", spec);
    // snippet:end bool-constant
    vkf::DescriptorPool pool(ctx);
    VkDescriptorSet set = pool.allocate(setLayout, "counter");
    u2::writeStorageBuffers(ctx, set, {counter});
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        vkCmdFillBuffer(cmd, counter, 0, VK_WHOLE_SIZE, 0);
        vkf::memoryBarrier(
            cmd, VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
            VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                nullptr);
        vkCmdDispatch(cmd, groups, 1, 1);
    });
    return vkf::download<uint32_t>(ctx, counter, 1)[0];
}

uint32_t treeRace(const vkf::Context& ctx, bool fix, uint32_t trials) {
    std::vector<uint32_t> values(size_t(trials) * localSize);
    std::mt19937 rng(11);
    std::uniform_int_distribution<uint32_t> small(0, 1000);
    for (uint32_t& v : values) v = small(rng);

    const VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    vkf::Buffer input = vkf::createBuffer(ctx, values.size() * sizeof(uint32_t), usage,
                                          vkf::MemoryUse::DeviceLocal, "values");
    vkf::Buffer sums = vkf::createBuffer(ctx, trials * sizeof(uint32_t), usage,
                                         vkf::MemoryUse::DeviceLocal, "sums");
    vkf::upload(ctx, input, std::span<const uint32_t>(values));
    auto setLayout = u2::storageBufferLayout(ctx, 2);
    auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()});
    vkf::Specialization spec;
    spec.set(0, VkBool32(fix ? VK_TRUE : VK_FALSE));
    auto pipeline = u2::loadPipeline(ctx, layout, "tree_sum.comp", spec);
    vkf::DescriptorPool pool(ctx);
    VkDescriptorSet set = pool.allocate(setLayout, "values sums");
    u2::writeStorageBuffers(ctx, set, {input, sums});
    vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                nullptr);
        vkCmdDispatch(cmd, trials, 1, 1);
    });

    const std::vector<uint32_t> result = vkf::download<uint32_t>(ctx, sums, trials);
    uint32_t wrong = 0;
    for (uint32_t g = 0; g < trials; ++g) {
        uint32_t expected = 0;
        for (uint32_t i = 0; i < localSize; ++i) expected += values[size_t(g) * localSize + i];
        if (result[g] != expected) ++wrong;
    }
    return wrong;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const bool fix = args.flag("--fix");
        const auto groups =
            vkf::groupCount(static_cast<uint32_t>(args.integer("--n", 1 << 20)), localSize);
        const auto trials = static_cast<uint32_t>(args.integer("--trials", 4096));
        vkf::Context ctx({.appName = "u2_race"});

        const uint32_t expected = groups * localSize;
        const uint32_t observed = countRace(ctx, fix, groups);
        vkf::print("race 1: {} invocations add 1 to one counter with {}\n", expected,
                   fix ? "atomicAdd" : "a plain read-modify-write");
        vkf::print("  expected {}, observed {} ({:.1f}% of the additions lost)\n", expected,
                   observed, 100.0 * (expected - observed) / expected);

        const uint32_t wrong = treeRace(ctx, fix, trials);
        vkf::print("race 2: {} workgroups each sum {} values in shared memory {} barrier()\n",
                   trials, localSize, fix ? "with" : "without");
        vkf::print("  wrong sums in {} of {} workgroups ({:.1f}%)\n", wrong, trials,
                   100.0 * wrong / trials);

        if (fix) {
            u2::finish(observed == expected && wrong == 0,
                       "race --fix: the synchronised kernels give exact results");
        } else {
            vkf::print(
                "A race depends on timing: how often it shows varies between GPUs, "
                "drivers and runs.\n");
            const int seen = (observed != expected ? 1 : 0) + (wrong != 0 ? 1 : 0);
            u2::finish(true, std::format("race: {} of 2 races showed; --fix synchronises "
                                         "the kernels",
                                         seen));
        }
    });
}
