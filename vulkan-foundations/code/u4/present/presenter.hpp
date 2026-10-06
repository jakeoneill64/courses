#pragma once

#include <vkf/vkf.hpp>

#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

#include "display.hpp"
#include "frames.hpp"
#include "swapchain.hpp"

namespace u4 {

struct PresenterOptions {
    SwapchainOptions swapchain;
    uint32_t framesInFlight = 2;
    // The first barrier on an acquired image must include these stages in its srcStageMask.
    VkPipelineStageFlags2 imageWaitStage = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
};

struct AcquiredImage {
    uint32_t imageIndex = 0;
    VkImage image = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkExtent2D extent{};
    VkFormat format = VK_FORMAT_UNDEFINED;
    // Wait on it before the first command that touches the image.
    VkSemaphore acquired = VK_NULL_HANDLE;
    // Signal it when the image is finished: presentation waits on it.
    VkSemaphore ready = VK_NULL_HANDLE;
};

struct Frame : AcquiredImage {
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    uint32_t slot = 0;
    uint64_t number = 0;
    double slotWaitMs = 0;
    double acquireMs = 0;
};

class Presenter {
public:
    Presenter(const vkf::Context& ctx, Display& display, const PresenterOptions& options);
    ~Presenter();
    Presenter(const Presenter&) = delete;
    Presenter& operator=(const Presenter&) = delete;

    // Called after each swapchain creation, with the device idle.
    void onRecreate(std::function<void(const Swapchain&)> callback);

    // nullopt if the window was closed while minimised.
    std::optional<Frame> begin();
    void end(const Frame& frame);
    void drain();

    // Reuses the acquire semaphore of `slot`: first wait for the frame that last used it.
    std::optional<AcquiredImage> acquire(uint32_t slot);
    void present(const AcquiredImage& image);

    const Swapchain& swapchain() const { return swapchain_; }
    uint32_t framesInFlight() const { return ring_.framesInFlight(); }
    uint32_t recreations() const { return recreations_; }
    double lastPresentMs() const { return presentMs_; }

private:
    bool recreate();

    const vkf::Context* ctx_;
    Display* display_;
    PresenterOptions options_;
    Swapchain swapchain_;
    FrameRing ring_;
    std::vector<vkf::Unique<VkSemaphore>> imageAcquired_;
    std::function<void(const Swapchain&)> onRecreate_;
    uint32_t recreations_ = 0;
    double presentMs_ = 0;
    bool suboptimal_ = false;
};

}  // namespace u4
