#include "presenter.hpp"

#include <string>

namespace u4 {

Presenter::Presenter(const vkf::Context& ctx, Display& display,
                     const PresenterOptions& options)
    : ctx_(&ctx),
      display_(&display),
      options_(options),
      swapchain_(ctx, options.swapchain),
      ring_(ctx, ctx.mainQueue().family, options.framesInFlight) {
    for (uint32_t i = 0; i < options.framesInFlight; ++i) {
        imageAcquired_.push_back(vkf::createSemaphore(ctx));
        ctx.name(imageAcquired_.back().get(), ("image acquired " + std::to_string(i)).c_str());
    }
    VkExtent2D extent = display.framebufferExtent();
    while ((extent.width == 0 || extent.height == 0) && !display.closeRequested()) {
        display.waitEvents();
        extent = display.framebufferExtent();
    }
    swapchain_.recreate(extent);
}

Presenter::~Presenter() {
    if (ctx_->device() != VK_NULL_HANDLE) vkDeviceWaitIdle(ctx_->device());
}

void Presenter::onRecreate(std::function<void(const Swapchain&)> callback) {
    onRecreate_ = std::move(callback);
    if (onRecreate_) onRecreate_(swapchain_);
}

// snippet:begin recreate
bool Presenter::recreate() {
    VkExtent2D extent = display_->framebufferExtent();
    while (extent.width == 0 || extent.height == 0) {
        if (display_->closeRequested()) return false;
        display_->waitEvents();
        extent = display_->framebufferExtent();
    }
    VKF_CHECK(vkDeviceWaitIdle(ctx_->device()));
    swapchain_.recreate(extent);
    suboptimal_ = false;
    ++recreations_;
    if (onRecreate_) onRecreate_(swapchain_);
    return true;
}
// snippet:end recreate

// snippet:begin acquire
std::optional<AcquiredImage> Presenter::acquire(uint32_t slot) {
    if (display_->takeResized() && !recreate()) return std::nullopt;
    uint32_t index = 0;
    for (;;) {
        const VkResult result =
            vkAcquireNextImageKHR(ctx_->device(), swapchain_.handle(), UINT64_MAX,
                                  imageAcquired_[slot], VK_NULL_HANDLE, &index);
        if (result == VK_ERROR_OUT_OF_DATE_KHR) {
            if (!recreate()) return std::nullopt;
            continue;
        }
        // Suboptimal still signals the semaphore: render this frame, and present() recreates.
        if (result == VK_SUBOPTIMAL_KHR) suboptimal_ = true;
        vkf::check(result, "vkAcquireNextImageKHR");
        break;
    }
    return AcquiredImage{index,
                         swapchain_.image(index),
                         swapchain_.view(index),
                         swapchain_.extent(),
                         swapchain_.surfaceFormat().format,
                         imageAcquired_[slot],
                         swapchain_.readyToPresent(index)};
}
// snippet:end acquire

// snippet:begin present
void Presenter::present(const AcquiredImage& image) {
    const VkSwapchainKHR swapchain = swapchain_.handle();
    const VkPresentInfoKHR info{
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &image.ready,
        .swapchainCount = 1,
        .pSwapchains = &swapchain,
        .pImageIndices = &image.imageIndex,
    };
    const VkResult result = vkQueuePresentKHR(ctx_->mainQueue(), &info);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR || suboptimal_) {
        recreate();
    } else {
        vkf::check(result, "vkQueuePresentKHR");
    }
}
// snippet:end present

// snippet:begin begin-end
std::optional<Frame> Presenter::begin() {
    Frame frame;
    frame.cmd = ring_.begin();
    frame.slot = ring_.slot();
    frame.number = ring_.submitted();
    frame.slotWaitMs = ring_.waitedMs();
    const vkf::CpuTimer timer;
    const std::optional<AcquiredImage> image = acquire(frame.slot);
    if (!image) return std::nullopt;
    static_cast<AcquiredImage&>(frame) = *image;
    frame.acquireMs = timer.elapsedMs();
    return frame;
}

void Presenter::end(const Frame& frame) {
    const vkf::CpuTimer timer;
    const vkf::SemaphoreSubmit wait{frame.acquired, 0, options_.imageWaitStage};
    const vkf::SemaphoreSubmit signal{frame.ready, 0, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
    ring_.submit(ctx_->mainQueue(), std::span(&wait, 1), std::span(&signal, 1));
    present(frame);
    presentMs_ = timer.elapsedMs();
}
// snippet:end begin-end

void Presenter::drain() {
    ring_.drain();
}

}  // namespace u4
