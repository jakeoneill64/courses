#include "display.hpp"

#define GLFW_INCLUDE_VULKAN
#include <GLFW/glfw3.h>

#include <vkf/check.hpp>

#include <cstdio>
#include <stdexcept>

namespace u4 {
namespace {

void onGlfwError(int code, const char* description) {
    std::fprintf(stderr, "glfw error 0x%x: %s\n", code, description);
}

}  // namespace

// snippet:begin window
Display::Display(const DisplayOptions& options) : headless_(options.headless) {
    if (headless_) {
        headlessExtent_ = {options.width, options.height};
        return;
    }
    glfwSetErrorCallback(onGlfwError);
#if GLFW_VERSION_MAJOR > 3 || GLFW_VERSION_MINOR >= 4
    // GLFW would otherwise look for a Vulkan loader of its own, which may not be on its path.
    glfwInitVulkanLoader(vkGetInstanceProcAddr);
#endif
    if (!glfwInit()) throw std::runtime_error("cannot open a window here; try --headless");
    if (!glfwVulkanSupported()) {
        glfwTerminate();
        throw std::runtime_error("GLFW cannot create Vulkan surfaces on this system");
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    window_ =
        glfwCreateWindow(static_cast<int>(options.width), static_cast<int>(options.height),
                         options.title.c_str(), nullptr, nullptr);
    if (window_ == nullptr) {
        glfwTerminate();
        throw std::runtime_error("glfwCreateWindow failed");
    }
    glfwSetWindowUserPointer(window_, this);
    glfwSetFramebufferSizeCallback(window_, onFramebufferResize);
}
// snippet:end window

Display::~Display() {
    if (window_ != nullptr) glfwDestroyWindow(window_);
    if (!headless_) glfwTerminate();
}

// snippet:begin surface
std::vector<const char*> Display::instanceExtensions() const {
    if (headless_) {
        return {VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_HEADLESS_SURFACE_EXTENSION_NAME};
    }
    uint32_t count = 0;
    const char** names = glfwGetRequiredInstanceExtensions(&count);
    return {names, names + count};
}

VkSurfaceKHR Display::createSurface(VkInstance instance) const {
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    if (headless_) {
        const auto create = reinterpret_cast<PFN_vkCreateHeadlessSurfaceEXT>(
            vkGetInstanceProcAddr(instance, "vkCreateHeadlessSurfaceEXT"));
        const VkHeadlessSurfaceCreateInfoEXT info{
            .sType = VK_STRUCTURE_TYPE_HEADLESS_SURFACE_CREATE_INFO_EXT,
        };
        VKF_CHECK(create(instance, &info, nullptr, &surface));
    } else {
        VKF_CHECK(glfwCreateWindowSurface(instance, window_, nullptr, &surface));
    }
    return surface;
}
// snippet:end surface

VkExtent2D Display::framebufferExtent() const {
    if (headless_) return headlessExtent_;
    int width = 0, height = 0;
    glfwGetFramebufferSize(window_, &width, &height);
    return {static_cast<uint32_t>(width), static_cast<uint32_t>(height)};
}

bool Display::takeResized() {
    const bool resized = resized_;
    resized_ = false;
    return resized;
}

void Display::resize(uint32_t width, uint32_t height) {
    if (headless_) {
        headlessExtent_ = {width, height};
        resized_ = true;
    } else {
        glfwSetWindowSize(window_, static_cast<int>(width), static_cast<int>(height));
    }
}

void Display::onFramebufferResize(GLFWwindow* window, int, int) {
    static_cast<Display*>(glfwGetWindowUserPointer(window))->resized_ = true;
}

void Display::pollEvents() {
    if (!headless_) glfwPollEvents();
}

void Display::waitEvents() {
    if (!headless_) glfwWaitEvents();
}

bool Display::closeRequested() const {
    return !headless_ && glfwWindowShouldClose(window_);
}

}  // namespace u4
