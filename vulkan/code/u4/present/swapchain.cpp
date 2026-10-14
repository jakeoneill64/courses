#include "swapchain.hpp"

#include <algorithm>
#include <string>

namespace u4 {

// snippet:begin surface-format
VkSurfaceFormatKHR chooseSurfaceFormat(const std::vector<VkSurfaceFormatKHR>& formats,
                                       bool srgb) {
    const VkFormat preferred[] = {
        srgb ? VK_FORMAT_B8G8R8A8_SRGB : VK_FORMAT_B8G8R8A8_UNORM,
        srgb ? VK_FORMAT_R8G8B8A8_SRGB : VK_FORMAT_R8G8B8A8_UNORM,
    };
    for (VkFormat format : preferred) {
        for (const VkSurfaceFormatKHR& candidate : formats) {
            if (candidate.format == format &&
                candidate.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return candidate;
            }
        }
    }
    return formats.front();
}
// snippet:end surface-format

// snippet:begin present-mode
VkPresentModeKHR choosePresentMode(const std::vector<VkPresentModeKHR>& modes,
                                   VkPresentModeKHR wanted) {
    if (std::find(modes.begin(), modes.end(), wanted) != modes.end()) return wanted;
    return VK_PRESENT_MODE_FIFO_KHR;
}
// snippet:end present-mode

// snippet:begin image-count
uint32_t chooseImageCount(const VkSurfaceCapabilitiesKHR& caps, uint32_t wanted) {
    uint32_t count = std::max(wanted, caps.minImageCount);
    if (caps.maxImageCount > 0) count = std::min(count, caps.maxImageCount);
    return count;
}

VkExtent2D chooseExtent(const VkSurfaceCapabilitiesKHR& caps, VkExtent2D framebuffer) {
    if (caps.currentExtent.width != UINT32_MAX) return caps.currentExtent;
    return {
        std::clamp(framebuffer.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        std::clamp(framebuffer.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}
// snippet:end image-count

VkCompositeAlphaFlagBitsKHR chooseCompositeAlpha(const VkSurfaceCapabilitiesKHR& caps) {
    const VkCompositeAlphaFlagBitsKHR candidates[] = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
    };
    for (VkCompositeAlphaFlagBitsKHR candidate : candidates) {
        if (caps.supportedCompositeAlpha & candidate) return candidate;
    }
    return VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
}

Swapchain::Swapchain(const vkf::Context& ctx, const SwapchainOptions& options)
    : ctx_(&ctx), options_(options) {
    if (ctx.surface() == VK_NULL_HANDLE) {
        throw vkf::Error(VK_ERROR_SURFACE_LOST_KHR,
                         "the context was created without a surface");
    }
}

Swapchain::~Swapchain() {
    destroyPerImage();
    if (swapchain_ != VK_NULL_HANDLE) {
        vkDestroySwapchainKHR(ctx_->device(), swapchain_, nullptr);
    }
}

void Swapchain::destroyPerImage() {
    for (VkImageView view : views_) vkDestroyImageView(ctx_->device(), view, nullptr);
    for (VkSemaphore semaphore : readyToPresent_) {
        vkDestroySemaphore(ctx_->device(), semaphore, nullptr);
    }
    views_.clear();
    readyToPresent_.clear();
    images_.clear();
}

void Swapchain::recreate(VkExtent2D framebufferExtent) {
    const VkPhysicalDevice physical = ctx_->physicalDevice();
    const VkSurfaceKHR surface = ctx_->surface();
    const VkDevice device = ctx_->device();

    // snippet:begin query-surface
    VkSurfaceCapabilitiesKHR caps;
    VKF_CHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &caps));
    uint32_t count = 0;
    VKF_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &count, nullptr));
    std::vector<VkSurfaceFormatKHR> formats(count);
    VKF_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &count, formats.data()));
    VKF_CHECK(vkGetPhysicalDeviceSurfacePresentModesKHR(physical, surface, &count, nullptr));
    std::vector<VkPresentModeKHR> modes(count);
    VKF_CHECK(
        vkGetPhysicalDeviceSurfacePresentModesKHR(physical, surface, &count, modes.data()));
    // snippet:end query-surface

    if ((caps.supportedUsageFlags & options_.usage) != options_.usage) {
        throw vkf::Error(VK_ERROR_FEATURE_NOT_PRESENT,
                         "the surface does not support the swapchain image usage requested");
    }
    surfaceFormat_ = chooseSurfaceFormat(formats, options_.srgb);
    presentMode_ = choosePresentMode(modes, options_.presentMode);
    extent_ = chooseExtent(caps, framebufferExtent);
    usage_ = options_.usage | (options_.optionalUsage & caps.supportedUsageFlags);
    const VkCompositeAlphaFlagBitsKHR alpha = chooseCompositeAlpha(caps);

    // snippet:begin create-swapchain
    const VkSwapchainCreateInfoKHR info{
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = chooseImageCount(caps, options_.imageCount),
        .imageFormat = surfaceFormat_.format,
        .imageColorSpace = surfaceFormat_.colorSpace,
        .imageExtent = extent_,
        .imageArrayLayers = 1,
        .imageUsage = usage_,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = caps.currentTransform,
        .compositeAlpha = alpha,
        .presentMode = presentMode_,
        .clipped = VK_TRUE,
        .oldSwapchain = swapchain_,
    };
    VkSwapchainKHR created = VK_NULL_HANDLE;
    VKF_CHECK(vkCreateSwapchainKHR(device, &info, nullptr, &created));
    destroyPerImage();
    if (swapchain_ != VK_NULL_HANDLE) vkDestroySwapchainKHR(device, swapchain_, nullptr);
    swapchain_ = created;
    // snippet:end create-swapchain

    // snippet:begin per-image
    VKF_CHECK(vkGetSwapchainImagesKHR(device, swapchain_, &count, nullptr));
    images_.resize(count);
    VKF_CHECK(vkGetSwapchainImagesKHR(device, swapchain_, &count, images_.data()));
    const VkImageUsageFlags viewable = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                                       VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
    for (uint32_t i = 0; i < count; ++i) {
        const VkImageViewCreateInfo viewInfo{
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = images_[i],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = surfaceFormat_.format,
            .subresourceRange = vkf::colorRange(),
        };
        VkImageView view = VK_NULL_HANDLE;
        if (usage_ & viewable) VKF_CHECK(vkCreateImageView(device, &viewInfo, nullptr, &view));
        views_.push_back(view);
        readyToPresent_.push_back(vkf::createSemaphore(*ctx_).release());
        const std::string name = "swapchain image " + std::to_string(i);
        ctx_->name(images_[i], name.c_str());
        ctx_->name(view, name.c_str());
        ctx_->name(readyToPresent_.back(), ("ready to present " + std::to_string(i)).c_str());
    }
    // snippet:end per-image
}

}  // namespace u4
