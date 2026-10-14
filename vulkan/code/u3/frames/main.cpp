#include <vkf/vkf.hpp>

#include <algorithm>
#include <cstring>
#include <deque>
#include <stdexcept>
#include <string>
#include <vector>

#include "compute.hpp"

namespace {

constexpr uint32_t Side = 256;
constexpr uint32_t SeedCount = 16384;
constexpr uint32_t Steps = 8000;
constexpr uint32_t PaletteFrames = 16;

struct Push {
    uint32_t steps;
    uint32_t seedCount;
};

// lcgJump is affine in x, so the GPU's Steps-long loop collapses to one multiply-add here.
constexpr uint32_t JumpAdd = u3::lcgJump(0, Steps);
constexpr uint32_t JumpMul = u3::lcgJump(1, Steps) - JumpAdd;

std::vector<uint32_t> makePalette(uint32_t generation) {
    std::vector<uint32_t> colours(256);
    for (uint32_t j = 0; j < 256; ++j) {
        colours[j] = u3::scramble(generation * 256 + j) | 0xff000000u;
    }
    return colours;
}

void fillSeeds(uint32_t frame, std::vector<uint32_t>& seeds, int rounds) {
    for (uint32_t i = 0; i < SeedCount; ++i) {
        uint32_t x = frame * SeedCount + i;
        for (int r = 0; r < rounds; ++r) x = u3::scramble(x);
        seeds[i] = x;
    }
}

uint32_t expectedChecksum(const std::vector<uint32_t>& seeds,
                          const std::vector<uint32_t>& palette) {
    uint32_t sum = 0;
    for (uint32_t i = 0; i < Side * Side; ++i) {
        sum += palette[((seeds[i % SeedCount] ^ i) * JumpMul + JumpAdd) >> 24];
    }
    return sum;
}

uint32_t checksum(const uint32_t* pixels) {
    uint32_t sum = 0;
    for (uint32_t i = 0; i < Side * Side; ++i) sum += pixels[i];
    return sum;
}

struct Slot {
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    vkf::GpuTimer timer;
    VkDescriptorSet set = VK_NULL_HANDLE;
    int64_t frame = -1;
    uint32_t expected = 0;
};

// snippet:begin retired
// A resource that frames still in flight may use, kept until the timeline passes `after`.
struct Retired {
    uint64_t after;
    vkf::Buffer buffer;
};
// snippet:end retired

struct Result {
    double totalMs = 0, cpuMs = 0, waitMs = 0, gpuMs = 0;
    uint32_t correct = 0, palettes = 0, longestWait = 0;
};

class Frames {
public:
    Frames(const vkf::Context& ctx, uint32_t inFlight)
        : ctx_(ctx),
          inFlight_(inFlight),
          kernel_(u3::makeKernel(
              ctx, "simulate.comp",
              {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
               VK_DESCRIPTOR_TYPE_STORAGE_IMAGE},
              sizeof(Push))),
          pool_(ctx),
          image_(vkf::createImage(
              ctx,
              {.format = VK_FORMAT_R8G8B8A8_UINT,
               .width = Side,
               .height = Side,
               .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
              "frame image")),
          seeds_(vkf::createBuffer(ctx, VkDeviceSize(inFlight) * SeedCount * 4,
                                   VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vkf::MemoryUse::Upload,
                                   "seed ring")),
          readback_(vkf::createBuffer(ctx, VkDeviceSize(inFlight) * Side * Side * 4,
                                      VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                      vkf::MemoryUse::Readback, "readback ring")),
          commandPool_(vkf::createCommandPool(ctx, ctx.mainQueue().family)),
          timeline_(vkf::createTimelineSemaphore(ctx, 0)) {
        for (uint32_t s = 0; s < inFlight; ++s) {
            slots_.push_back({.cmd = vkf::allocateCommandBuffer(ctx, commandPool_),
                              .timer = vkf::GpuTimer(ctx, 2),
                              .set = pool_.allocate(kernel_.setLayout)});
        }
        newPalette(0);
    }

    Result run(uint32_t frames, int rounds, const std::string& png);

private:
    void newPalette(uint32_t generation);
    void waitFor(uint64_t value) const;
    void record(VkCommandBuffer cmd, Slot& slot, uint32_t s) const;

    const vkf::Context& ctx_;
    uint32_t inFlight_;
    u3::Kernel kernel_;
    vkf::DescriptorPool pool_;
    vkf::Image image_;
    vkf::Buffer seeds_, readback_, palette_;
    std::vector<uint32_t> colours_;
    vkf::Unique<VkCommandPool> commandPool_;
    vkf::Unique<VkSemaphore> timeline_;
    std::vector<Slot> slots_;
    std::deque<Retired> retired_;
    uint32_t palettes_ = 0;
};

void Frames::newPalette(uint32_t generation) {
    colours_ = makePalette(generation);
    palette_ = vkf::createBuffer(ctx_, 256 * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                 vkf::MemoryUse::Upload, "palette");
    std::memcpy(palette_.mapped, colours_.data(), 256 * 4);
    palette_.flush();
    ++palettes_;
}

void Frames::waitFor(uint64_t value) const {
    const VkSemaphoreWaitInfo info{
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = timeline_.ptr(),
        .pValues = &value,
    };
    if (VKF_CHECK(vkWaitSemaphores(ctx_.device(), &info, 5'000'000'000)) == VK_TIMEOUT) {
        throw std::runtime_error("timed out waiting for a frame");
    }
}

void Frames::record(VkCommandBuffer cmd, Slot& slot, uint32_t s) const {
    // snippet:begin record-frame
    slot.timer.reset(cmd);
    slot.timer.stamp(cmd);
    // The previous frame's copy may still be reading the image; this frame replaces it.
    VkImageMemoryBarrier2 image{
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT,
        .srcAccessMask = VK_ACCESS_2_NONE,
        .dstStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
        .dstAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
        .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = VK_IMAGE_LAYOUT_GENERAL,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = image_,
        .subresourceRange = vkf::colorRange(),
    };
    const VkDependencyInfo dependency{
        .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &image,
    };
    vkCmdPipelineBarrier2(cmd, &dependency);
    u3::dispatch(cmd, kernel_, slot.set, Push{Steps, SeedCount}, Side / 16, Side / 16);
    // snippet:end record-frame
    // snippet:begin record-copy
    image.srcStageMask = VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
    image.srcAccessMask = VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT;
    image.dstStageMask = VK_PIPELINE_STAGE_2_COPY_BIT;
    image.dstAccessMask = VK_ACCESS_2_TRANSFER_READ_BIT;
    image.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    image.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    vkCmdPipelineBarrier2(cmd, &dependency);
    const VkBufferImageCopy region{
        .bufferOffset = VkDeviceSize(s) * Side * Side * 4,
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {Side, Side, 1},
    };
    vkCmdCopyImageToBuffer(cmd, image_, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback_, 1,
                           &region);
    vkf::memoryBarrier(cmd, VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                       VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
    slot.timer.stamp(cmd);
    // snippet:end record-copy
}

Result Frames::run(uint32_t frames, int rounds, const std::string& png) {
    Result result;
    std::vector<double> cpu, waits, gpu;
    std::vector<uint32_t> seeds(SeedCount);
    const auto finish = [&](Slot& slot, uint32_t s) {
        readback_.invalidate(VkDeviceSize(s) * Side * Side * 4, VkDeviceSize(Side) * Side * 4);
        const uint32_t* pixels = readback_.data<uint32_t>() + size_t(s) * Side * Side;
        result.correct += checksum(pixels) == slot.expected ? 1 : 0;
        gpu.push_back(slot.timer.read()[1]);
        if (!png.empty() && slot.frame + 1 == int64_t(frames)) {
            vkf::writePng(
                png, Side, Side,
                std::span(reinterpret_cast<const uint8_t*>(pixels), Side * Side * 4));
        }
    };

    vkf::CpuTimer total;
    for (uint32_t f = 0; f < frames; ++f) {
        // snippet:begin pace
        const uint32_t s = f % inFlight_;
        Slot& slot = slots_[s];
        vkf::CpuTimer waiting;
        if (f >= inFlight_) waitFor(f - inFlight_ + 1);
        waits.push_back(waiting.elapsedMs());
        vkf::CpuTimer working;
        if (slot.frame >= 0) finish(slot, s);
        // snippet:end pace

        // snippet:begin deferred
        uint64_t completed = 0;
        VKF_CHECK(vkGetSemaphoreCounterValue(ctx_.device(), timeline_, &completed));
        while (!retired_.empty() && retired_.front().after <= completed) {
            result.longestWait =
                std::max(result.longestWait, f - uint32_t(retired_.front().after));
            retired_.pop_front();
        }
        if (f > 0 && f % PaletteFrames == 0) {
            // Frames up to f - 1 may still read the old palette; frame f - 1 signals f.
            retired_.push_back({f, std::move(palette_)});
            newPalette(f / PaletteFrames);
        }
        // snippet:end deferred

        fillSeeds(f, seeds, rounds);
        slot.expected = expectedChecksum(seeds, colours_);
        std::memcpy(seeds_.data<uint32_t>() + size_t(s) * SeedCount, seeds.data(),
                    SeedCount * 4);
        seeds_.flush(VkDeviceSize(s) * SeedCount * 4, SeedCount * 4);
        vkf::DescriptorWriter()
            .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, seeds_,
                    VkDeviceSize(s) * SeedCount * 4, SeedCount * 4)
            .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, palette_)
            .image(2, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, image_.view, VK_IMAGE_LAYOUT_GENERAL)
            .update(ctx_, slot.set);

        // snippet:begin submit-frame
        VKF_CHECK(vkResetCommandBuffer(slot.cmd, 0));
        vkf::beginCommands(slot.cmd);
        record(slot.cmd, slot, s);
        vkf::endCommands(slot.cmd);
        const vkf::SemaphoreSubmit done{timeline_, f + 1,
                                        VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
        vkf::submit(ctx_.mainQueue(), std::span(&slot.cmd, 1), {}, std::span(&done, 1));
        slot.frame = f;
        // snippet:end submit-frame
        cpu.push_back(working.elapsedMs());
    }
    waitFor(frames);
    for (uint32_t i = frames > inFlight_ ? frames - inFlight_ : 0; i < frames; ++i) {
        finish(slots_[i % inFlight_], i % inFlight_);
    }
    retired_.clear();
    result.totalMs = total.elapsedMs();
    result.cpuMs = vkf::summarize(cpu).median;
    result.waitMs = vkf::summarize(waits).median;
    result.gpuMs = vkf::summarize(gpu).median;
    result.palettes = palettes_;
    return result;
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto frames = uint32_t(args.integer("--frames", 120));
        const auto chosen = uint32_t(args.integer("--frames-in-flight", 0));
        const int rounds = int(args.integer("--cpu-rounds", 48));
        const std::string png = args.text("--out", "");
        if (chosen > 3) throw std::runtime_error("--frames-in-flight takes 1, 2 or 3");
        vkf::Context ctx({.appName = "u3_frames"});

        vkf::print("{} frames: CPU prepares {} seeds, GPU runs {} steps per pixel of {}x{}\n",
                   frames, SeedCount, Steps, Side, Side);
        vkf::print("  {:<10}{:>12}{:>12}{:>12}{:>12}{:>14}\n", "in flight", "ms/frame",
                   "CPU work", "CPU waits", "GPU", "checksums");
        bool ok = true;
        for (uint32_t inFlight = 1; inFlight <= 3; ++inFlight) {
            if (chosen != 0 && inFlight != chosen) continue;
            Frames runner(ctx, inFlight);
            const Result r = runner.run(frames, rounds, inFlight == 3 || chosen ? png : "");
            ok = ok && r.correct == frames;
            vkf::print("  {:<10}{:>12.3f}{:>12.3f}{:>12.3f}{:>12.3f}{:>14}\n", inFlight,
                       r.totalMs / frames, r.cpuMs, r.waitMs, r.gpuMs,
                       std::to_string(r.correct) + "/" + std::to_string(frames));
            vkf::print(
                "  {:<10}{} palettes, each destroyed at most {} frame(s) after it was "
                "replaced\n",
                "", r.palettes, r.longestWait);
        }
        if (!png.empty()) vkf::print("wrote {}\n", png);
        if (!ok) throw std::runtime_error("some frames had the wrong checksum");
        vkf::print("PASS\n");
    });
}
