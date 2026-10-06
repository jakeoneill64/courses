#include "pipeline.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>

namespace demo {
namespace {

constexpr uint32_t Seed = 2024;
constexpr uint32_t MinBlurred = 1400;
constexpr uint32_t MaxEdge = 200;

struct SeedPush {
    uint32_t seed;
};

struct SelectPush {
    uint32_t count;
    uint32_t minBlurred;
    uint32_t maxEdge;
};

constexpr VkDescriptorType Image = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
constexpr VkDescriptorType Storage = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;

}  // namespace

Kernels::Kernels(const vkf::Context& ctx)
    : generate(u3::makeKernel(ctx, "generate.comp", {Image}, sizeof(SeedPush))),
      blur(u3::makeKernel(ctx, "blur.comp", {Image, Storage})),
      edges(u3::makeKernel(ctx, "edges.comp", {Image, Storage})),
      select(u3::makeKernel(ctx, "select.comp", {Storage, Storage, Storage, Storage, Image},
                            sizeof(SelectPush))),
      command(u3::makeKernel(ctx, "command.comp", {Storage, Storage})),
      score(u3::makeKernel(ctx, "score.comp", {Storage, Storage, Storage})) {}

Pipeline::Pipeline(const vkf::Context& ctx, const Kernels& kernels, const Targets& targets,
                   uint32_t side)
    : kernels_(kernels), targets_(targets), side_(side), pool_(ctx) {
    const auto imageAndBuffer = [&](const u3::Kernel& kernel, VkBuffer output) {
        const VkDescriptorSet set = pool_.allocate(kernel.setLayout);
        vkf::DescriptorWriter writer;
        writer.image(0, Image, targets.fieldView, VK_IMAGE_LAYOUT_GENERAL);
        if (output != VK_NULL_HANDLE) writer.buffer(1, Storage, output);
        writer.update(ctx, set);
        return set;
    };
    generateSet_ = imageAndBuffer(kernels.generate, VK_NULL_HANDLE);
    blurSet_ = imageAndBuffer(kernels.blur, targets.blurred);
    edgesSet_ = imageAndBuffer(kernels.edges, targets.edges);
    selectSet_ = pool_.allocate(kernels.select.setLayout);
    vkf::DescriptorWriter()
        .buffer(0, Storage, targets.blurred)
        .buffer(1, Storage, targets.edges)
        .buffer(2, Storage, targets.stats)
        .buffer(3, Storage, targets.list)
        .image(4, Image, targets.maskView, VK_IMAGE_LAYOUT_GENERAL)
        .update(ctx, selectSet_);
    commandSet_ = u3::bufferSet(ctx, pool_, kernels.command, {targets.stats, targets.command});
    scoreSet_ = u3::bufferSet(ctx, pool_, kernels.score,
                              {targets.list, targets.blurred, targets.stats});
}

void Pipeline::clearStats(VkCommandBuffer cmd) const {
    vkCmdFillBuffer(cmd, targets_.stats, 0, VK_WHOLE_SIZE, 0);
}

void Pipeline::generate(VkCommandBuffer cmd) const {
    const uint32_t tiles = vkf::groupCount(side_, 16);
    u3::dispatch(cmd, kernels_.generate, generateSet_, SeedPush{Seed}, tiles, tiles);
}

void Pipeline::blur(VkCommandBuffer cmd) const {
    const uint32_t tiles = vkf::groupCount(side_, 16);
    u3::dispatch(cmd, kernels_.blur, blurSet_, tiles, tiles);
}

void Pipeline::edges(VkCommandBuffer cmd) const {
    const uint32_t tiles = vkf::groupCount(side_, 16);
    u3::dispatch(cmd, kernels_.edges, edgesSet_, tiles, tiles);
}

void Pipeline::select(VkCommandBuffer cmd) const {
    const uint32_t cells = side_ * side_;
    u3::dispatch(cmd, kernels_.select, selectSet_, SelectPush{cells, MinBlurred, MaxEdge},
                 vkf::groupCount(cells, 256));
}

void Pipeline::command(VkCommandBuffer cmd) const {
    u3::dispatch(cmd, kernels_.command, commandSet_, 1);
}

void Pipeline::score(VkCommandBuffer cmd) const {
    u3::bind(cmd, kernels_.score, scoreSet_);
    vkCmdDispatchIndirect(cmd, targets_.command, 0);
}

void Pipeline::readback(VkCommandBuffer cmd) const {
    const VkBufferCopy stats{.size = sizeof(Stats)};
    vkCmdCopyBuffer(cmd, targets_.stats, targets_.results, 1, &stats);
    const VkBufferImageCopy mask{
        .bufferOffset = sizeof(Stats),
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {side_, side_, 1},
    };
    vkCmdCopyImageToBuffer(cmd, targets_.mask, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                           targets_.results, 1, &mask);
}

VkDeviceSize resultsSize(uint32_t side) {
    return sizeof(Stats) + VkDeviceSize(side) * side * 4;
}

bool verify(const vkf::Buffer& results, uint32_t side, Stats& got) {
    std::vector<int> field(size_t(side) * side);
    for (uint32_t i = 0; i < field.size(); ++i) field[i] = int(u3::scramble(i ^ Seed) & 255u);
    const int last = int(side) - 1;
    const auto at = [&](int x, int y) {
        return field[size_t(std::clamp(y, 0, last)) * side + size_t(std::clamp(x, 0, last))];
    };
    results.invalidate();
    std::memcpy(&got, results.mapped, sizeof(Stats));
    const auto* mask =
        reinterpret_cast<const uint32_t*>(results.data<uint8_t>() + sizeof(Stats));
    Stats want{};
    bool maskMatches = true;
    for (int y = 0; y <= last; ++y) {
        for (int x = 0; x <= last; ++x) {
            uint32_t blurred = 0;
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) blurred += uint32_t(at(x + dx, y + dy));
            }
            const int edge =
                std::abs(at(x + 1, y) - at(x - 1, y)) + std::abs(at(x, y + 1) - at(x, y - 1));
            const uint32_t i = uint32_t(y) * side + uint32_t(x);
            const bool chosen = blurred > MinBlurred && edge < int(MaxEdge);
            if (chosen) {
                ++want.selected;
                want.blurredSum += blurred;
                want.indexXor ^= i;
            }
            maskMatches = maskMatches && mask[i] == (chosen ? 1u : 0u);
        }
    }
    return maskMatches && got.selected == want.selected && got.blurredSum == want.blurredSum &&
           got.indexXor == want.indexXor;
}

}  // namespace demo
