#pragma once

#include <vkf/vkf.hpp>

#include <cstdint>
#include <span>
#include <vector>

namespace u4 {

// Frame n, counting from 0, signals the timeline to n + 1 when the GPU has finished it.
class FrameRing {
public:
    FrameRing(const vkf::Context& ctx, uint32_t queueFamily, uint32_t framesInFlight);

    VkCommandBuffer begin();
    void submit(VkQueue queue, std::span<const vkf::SemaphoreSubmit> waits = {},
                std::span<const vkf::SemaphoreSubmit> signals = {});
    void drain();

    uint32_t slot() const { return slot_; }
    uint32_t framesInFlight() const { return static_cast<uint32_t>(slots_.size()); }
    uint64_t submitted() const { return submitted_; }
    VkSemaphore timeline() const { return timeline_; }
    double waitedMs() const { return waitedMs_; }

private:
    void waitFor(uint64_t value);

    struct Slot {
        vkf::Unique<VkCommandPool> pool;
        VkCommandBuffer cmd = VK_NULL_HANDLE;
    };
    const vkf::Context* ctx_;
    std::vector<Slot> slots_;
    vkf::Unique<VkSemaphore> timeline_;
    uint64_t submitted_ = 0;
    uint32_t slot_ = 0;
    double waitedMs_ = 0;
};

}  // namespace u4
