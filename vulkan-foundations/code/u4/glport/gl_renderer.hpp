#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

#include "gl_api.hpp"
#include "mesh.hpp"
#include "scene.hpp"

struct GLFWwindow;

namespace glport {

class GlRenderer {
public:
    GlRenderer(uint32_t width, uint32_t height, const u4::Mesh& mesh);
    ~GlRenderer();
    GlRenderer(const GlRenderer&) = delete;
    GlRenderer& operator=(const GlRenderer&) = delete;

    FrameTiming renderFrame(std::span<const DrawData> draws);
    // RGBA rows from the top, like a Vulkan image.
    std::vector<uint8_t> readPixels();
    std::string version() const;

private:
    void checkErrors(const char* where);

    uint32_t width_, height_;
    GLFWwindow* window_ = nullptr;
    GlApi gl_;
    GLuint vertexArray_ = 0, vertexBuffer_ = 0, indexBuffer_ = 0;
    GLsizei indexCount_ = 0;
    GLuint program_ = 0;
    GLint mvpLocation_ = -1, colorLocation_ = -1;
    GLuint framebuffer_ = 0, colorBuffer_ = 0, depthBuffer_ = 0;
};

}  // namespace glport
