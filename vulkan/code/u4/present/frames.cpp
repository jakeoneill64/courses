#include "frames.hpp"

#include <string>

namespace u4 {

FrameRing::FrameRing(const vkf::Context& ctx, uint32_t queueFamily, uint32_t framesInFlight)
    : ctx_(&ctx), timeline_(vkf::createTimelineSemaphore(ctx, 0)) {
    ctx.name(timeline_.get(), "frames finished");
    for (uint32_t i = 0; i < framesInFlight; ++i) {
        Slot slot{.pool = vkf::createCommandPool(ctx, queueFamily, 0)};
        slot.cmd = vkf::allocateCommandBuffer(ctx, slot.pool);
        ctx.name(slot.cmd, ("frame slot " + std::to_string(i)).c_str());
        slots_.push_back(std::move(slot));
    }
}

void FrameRing::waitFor(uint64_t value) {
    const VkSemaphore timeline = timeline_;
    const VkSemaphoreWaitInfo wait{
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &timeline,
        .pValues = &value,
    };
    VKF_CHECK(vkWaitSemaphores(ctx_->device(), &wait, UINT64_MAX));
}

// snippet:begin begin-frame
VkCommandBuffer FrameRing::begin() {
    slot_ = static_cast<uint32_t>(submitted_ % slots_.size());
    const vkf::CpuTimer timer;
    if (submitted_ >= slots_.size()) waitFor(submitted_ + 1 - slots_.size());
    waitedMs_ = timer.elapsedMs();
    VKF_CHECK(vkResetCommandPool(ctx_->device(), slots_[slot_].pool, 0));
    vkf::beginCommands(slots_[slot_].cmd);
    return slots_[slot_].cmd;
}
// snippet:end begin-frame

// snippet:begin submit-frame
void FrameRing::submit(VkQueue queue, std::span<const vkf::SemaphoreSubmit> waits,
                       std::span<const vkf::SemaphoreSubmit> signals) {
    const VkCommandBuffer cmd = slots_[slot_].cmd;
    vkf::endCommands(cmd);
    std::vector<vkf::SemaphoreSubmit> allSignals(signals.begin(), signals.end());
    allSignals.push_back({timeline_, submitted_ + 1, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT});
    vkf::submit(queue, std::span(&cmd, 1), waits, allSignals);
    ++submitted_;
}
// snippet:end submit-frame

void FrameRing::drain() {
    if (submitted_ > 0) waitFor(submitted_);
}

}  // namespace u4
