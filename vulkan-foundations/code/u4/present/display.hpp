#pragma once

#include <vulkan/vulkan.h>

#include <cstdint>
#include <string>
#include <vector>

struct GLFWwindow;

namespace u4 {

struct DisplayOptions {
    std::string title = "Vulkan Foundations";
    uint32_t width = 960;
    uint32_t height = 540;
    bool headless = false;
};

// Create it before the vkf::Context: the window must outlive the surface the context destroys.
class Display {
public:
    explicit Display(const DisplayOptions& options);
    ~Display();
    Display(const Display&) = delete;
    Display& operator=(const Display&) = delete;

    bool headless() const { return headless_; }
    std::vector<const char*> instanceExtensions() const;
    VkSurfaceKHR createSurface(VkInstance instance) const;

    // Zero while the window is minimised.
    VkExtent2D framebufferExtent() const;
    bool takeResized();
    // Headless, the size in pixels; with a window, the window's size in screen units.
    void resize(uint32_t width, uint32_t height);

    void pollEvents();
    void waitEvents();
    bool closeRequested() const;

private:
    static void onFramebufferResize(GLFWwindow* window, int width, int height);

    bool headless_ = false;
    bool resized_ = false;
    VkExtent2D headlessExtent_{};
    GLFWwindow* window_ = nullptr;
};

}  // namespace u4
