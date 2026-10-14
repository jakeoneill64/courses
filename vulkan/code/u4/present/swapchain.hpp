#pragma once

#include <vkf/vkf.hpp>

#include <cstdint>
#include <vector>

namespace u4 {

struct SwapchainOptions {
    // FIFO is the fallback: it is the one mode every implementation supports.
    VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
    uint32_t imageCount = 3;
    // Prefer an _SRGB format, so that the hardware encodes the shaders' linear colours.
    bool srgb = true;
    VkImageUsageFlags usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    // Added only when the surface supports them; usage() reports what the swapchain got.
    VkImageUsageFlags optionalUsage = 0;
};

class Swapchain {
public:
    Swapchain(const vkf::Context& ctx, const SwapchainOptions& options);
    ~Swapchain();
    Swapchain(const Swapchain&) = delete;
    Swapchain& operator=(const Swapchain&) = delete;

    // The device must be idle.
    void recreate(VkExtent2D framebufferExtent);

    VkSwapchainKHR handle() const { return swapchain_; }
    VkSurfaceFormatKHR surfaceFormat() const { return surfaceFormat_; }
    VkPresentModeKHR presentMode() const { return presentMode_; }
    VkExtent2D extent() const { return extent_; }
    VkImageUsageFlags usage() const { return usage_; }
    uint32_t imageCount() const { return static_cast<uint32_t>(images_.size()); }
    VkImage image(uint32_t index) const { return images_[index]; }
    VkImageView view(uint32_t index) const { return views_[index]; }
    VkSemaphore readyToPresent(uint32_t index) const { return readyToPresent_[index]; }

private:
    void destroyPerImage();

    const vkf::Context* ctx_;
    SwapchainOptions options_;
    VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
    VkSurfaceFormatKHR surfaceFormat_{};
    VkPresentModeKHR presentMode_ = VK_PRESENT_MODE_FIFO_KHR;
    VkExtent2D extent_{};
    VkImageUsageFlags usage_ = 0;
    std::vector<VkImage> images_;
    std::vector<VkImageView> views_;
    std::vector<VkSemaphore> readyToPresent_;
};

VkSurfaceFormatKHR chooseSurfaceFormat(const std::vector<VkSurfaceFormatKHR>& formats,
                                       bool srgb);
VkPresentModeKHR choosePresentMode(const std::vector<VkPresentModeKHR>& modes,
                                   VkPresentModeKHR wanted);
uint32_t chooseImageCount(const VkSurfaceCapabilitiesKHR& caps, uint32_t wanted);
VkExtent2D chooseExtent(const VkSurfaceCapabilitiesKHR& caps, VkExtent2D framebuffer);
VkCompositeAlphaFlagBitsKHR chooseCompositeAlpha(const VkSurfaceCapabilitiesKHR& caps);

}  // namespace u4
