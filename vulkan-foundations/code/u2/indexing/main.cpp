#include <vkf/vkf.hpp>

#include <algorithm>
#include <format>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "u2.hpp"

namespace {

// snippet:begin record
struct Record {
    uint32_t globalId[2];
    uint32_t localId[2];
    uint32_t groupId[2];
    uint32_t localIndex;
    uint32_t subgroupId;
    uint32_t subgroupInvocation;
    uint32_t subgroupSize;
};
static_assert(sizeof(Record) == 40, "Record must match the std430 layout in indexing.comp");
// snippet:end record

struct Extent {
    uint32_t x;
    uint32_t y;
};

Extent parseExtent(const vkf::Args& args, std::string_view option, Extent fallback) {
    const std::string text = args.text(option, "");
    if (text.empty()) return fallback;
    const size_t comma = text.find(',');
    if (comma == std::string::npos) {
        throw std::runtime_error(std::format("{} takes two numbers: X,Y", option));
    }
    return {static_cast<uint32_t>(std::stoul(text.substr(0, comma))),
            static_cast<uint32_t>(std::stoul(text.substr(comma + 1)))};
}

// snippet:begin limits
void printLimits(const vkf::DeviceProperties& p) {
    const VkPhysicalDeviceLimits& l = p.core.limits;
    vkf::print("maxComputeWorkGroupCount       {} x {} x {}\n", l.maxComputeWorkGroupCount[0],
               l.maxComputeWorkGroupCount[1], l.maxComputeWorkGroupCount[2]);
    vkf::print("maxComputeWorkGroupSize        {} x {} x {}\n", l.maxComputeWorkGroupSize[0],
               l.maxComputeWorkGroupSize[1], l.maxComputeWorkGroupSize[2]);
    vkf::print("maxComputeWorkGroupInvocations {}\n", l.maxComputeWorkGroupInvocations);
    vkf::print("maxComputeSharedMemorySize     {} bytes\n", l.maxComputeSharedMemorySize);
    vkf::print("subgroupSize                   {} (minSubgroupSize {}, maxSubgroupSize {})\n",
               p.v11.subgroupSize, p.v13.minSubgroupSize, p.v13.maxSubgroupSize);
}
// snippet:end limits

void printSubgroupOperations(VkSubgroupFeatureFlags supported) {
    const std::pair<VkSubgroupFeatureFlags, const char*> operations[] = {
        {VK_SUBGROUP_FEATURE_BASIC_BIT, "basic"},
        {VK_SUBGROUP_FEATURE_VOTE_BIT, "vote"},
        {VK_SUBGROUP_FEATURE_ARITHMETIC_BIT, "arithmetic"},
        {VK_SUBGROUP_FEATURE_BALLOT_BIT, "ballot"},
        {VK_SUBGROUP_FEATURE_SHUFFLE_BIT, "shuffle"},
        {VK_SUBGROUP_FEATURE_SHUFFLE_RELATIVE_BIT, "shuffle_relative"},
        {VK_SUBGROUP_FEATURE_CLUSTERED_BIT, "clustered"},
        {VK_SUBGROUP_FEATURE_QUAD_BIT, "quad"},
    };
    std::string names;
    for (const auto& [bit, name] : operations) {
        if (supported & bit) names += std::string(names.empty() ? "" : " ") + name;
    }
    vkf::print("subgroupSupportedOperations    {}\n", names);
}

// snippet:begin check-limits
void checkLimits(const VkPhysicalDeviceLimits& limits, Extent groups, Extent local) {
    if (local.x == 0 || local.y == 0 || local.x > limits.maxComputeWorkGroupSize[0] ||
        local.y > limits.maxComputeWorkGroupSize[1] ||
        local.x * local.y > limits.maxComputeWorkGroupInvocations) {
        throw std::runtime_error(std::format(
            "a local size of {} x {} exceeds this device's limits", local.x, local.y));
    }
    if (groups.x == 0 || groups.y == 0 || groups.x > limits.maxComputeWorkGroupCount[0] ||
        groups.y > limits.maxComputeWorkGroupCount[1]) {
        throw std::runtime_error(
            std::format("{} x {} workgroups exceed this device's limits", groups.x, groups.y));
    }
}
// snippet:end check-limits

char symbol(uint32_t value) {
    return "0123456789abcdefghijklmnopqrstuvwxyz"[value % 36];
}

void printCheck(std::string_view what, uint32_t ok, uint32_t total) {
    vkf::print("{:<74}{:>5}/{}\n", what, ok, total);
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const Extent groups = parseExtent(args, "--groups", {4, 2});
        const Extent local = parseExtent(args, "--local", {8, 8});
        vkf::Context ctx({.appName = "u2_indexing"});
        printLimits(ctx.properties());
        printSubgroupOperations(ctx.properties().v11.subgroupSupportedOperations);
        checkLimits(ctx.properties().core.limits, groups, local);

        const Extent grid{groups.x * local.x, groups.y * local.y};
        if (uint64_t(grid.x) * grid.y > (1u << 22)) {
            throw std::runtime_error("keep the grid below 4194304 invocations");
        }
        const uint32_t count = grid.x * grid.y;
        const uint32_t groupCount = groups.x * groups.y;
        vkf::print("\ndispatch: {} x {} workgroups of {} x {} invocations, a {} x {} grid\n",
                   groups.x, groups.y, local.x, local.y, grid.x, grid.y);

        vkf::Buffer records = vkf::createBuffer(ctx, count * sizeof(Record),
                                                VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                                    VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                                    VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                                vkf::MemoryUse::DeviceLocal, "records");
        // snippet:begin pipeline
        auto setLayout = u2::storageBufferLayout(ctx, 1);
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()});
        vkf::Specialization spec;
        spec.set(0, local.x).set(1, local.y);
        auto pipeline = u2::loadPipeline(ctx, layout, "indexing.comp", spec);
        // snippet:end pipeline
        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet set = pool.allocate(setLayout, "records");
        u2::writeStorageBuffers(ctx, set, {records});

        // snippet:begin dispatch
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            vkCmdFillBuffer(cmd, records, 0, VK_WHOLE_SIZE, 0xFFFFFFFF);
            vkf::memoryBarrier(
                cmd, VK_PIPELINE_STAGE_2_CLEAR_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                    nullptr);
            vkCmdDispatch(cmd, groups.x, groups.y, 1);
        });
        const std::vector<Record> result = vkf::download<Record>(ctx, records, count);
        // snippet:end dispatch

        // snippet:begin checks
        uint32_t written = 0, globalOk = 0, indexOk = 0, linear = 0;
        std::set<uint32_t> subgroupSizes;
        std::vector<std::set<std::pair<uint32_t, uint32_t>>> lanes(groupCount);
        for (uint32_t y = 0; y < grid.y; ++y) {
            for (uint32_t x = 0; x < grid.x; ++x) {
                const Record& r = result[y * grid.x + x];
                if (r.localIndex == 0xFFFFFFFF) continue;
                ++written;
                const bool global = r.globalId[0] == x && r.globalId[1] == y &&
                                    x == r.groupId[0] * local.x + r.localId[0] &&
                                    y == r.groupId[1] * local.y + r.localId[1];
                if (!global) continue;
                ++globalOk;
                if (r.localIndex == r.localId[1] * local.x + r.localId[0]) ++indexOk;
                if (r.subgroupInvocation >= r.subgroupSize) continue;
                subgroupSizes.insert(r.subgroupSize);
                lanes[r.groupId[1] * groups.x + r.groupId[0]].insert(
                    {r.subgroupId, r.subgroupInvocation});
                if (r.localIndex == r.subgroupId * r.subgroupSize + r.subgroupInvocation) {
                    ++linear;
                }
            }
        }
        const auto uniqueLanes = static_cast<uint32_t>(
            std::count_if(lanes.begin(), lanes.end(),
                          [&](const auto& s) { return s.size() == local.x * local.y; }));
        // snippet:end checks

        uint32_t subgroupsPerGroup = 0;
        for (const Record& r : result) {
            if (r.localIndex != 0xFFFFFFFF) {
                subgroupsPerGroup = std::max(subgroupsPerGroup, r.subgroupId + 1);
            }
        }
        for (uint32_t size : subgroupSizes) vkf::print("gl_SubgroupSize {}", size);
        vkf::print(", {} subgroup(s) per workgroup\n\n", subgroupsPerGroup);

        if (grid.x <= 44 && grid.y <= 32) {
            const std::string title = std::format("gl_WorkGroupID as y * {} + x", groups.x);
            vkf::print("{:<{}}    gl_SubgroupID\n", title, grid.x);
            for (uint32_t y = 0; y < grid.y; ++y) {
                std::string groupRow, subgroupRow;
                for (uint32_t x = 0; x < grid.x; ++x) {
                    const Record& r = result[y * grid.x + x];
                    groupRow += symbol(r.groupId[1] * groups.x + r.groupId[0]);
                    subgroupRow += symbol(r.subgroupId);
                }
                vkf::print("{}    {}\n", groupRow, subgroupRow);
            }
            vkf::print("\n");
        }

        printCheck("invocations that wrote their record", written, count);
        printCheck("GlobalInvocationID = WorkGroupID * WorkGroupSize + LocalInvocationID",
                   globalOk, count);
        printCheck(std::format("LocalInvocationIndex = LocalInvocationID.y * {} + "
                               "LocalInvocationID.x",
                               local.x),
                   indexOk, count);
        printCheck("(SubgroupID, SubgroupInvocationID) unique within each workgroup",
                   uniqueLanes, groupCount);
        printCheck("LocalInvocationIndex = SubgroupID * SubgroupSize + SubgroupInvocationID",
                   linear, count);
        vkf::print(
            "  (the last line is the implementation's choice: Vulkan does not define it)\n");

        const bool passed = written == count && globalOk == count && indexOk == count &&
                            uniqueLanes == groupCount && subgroupSizes.size() == 1;
        u2::finish(passed,
                   std::format("indexing: {} invocations, every identity holds", count));
    });
}
